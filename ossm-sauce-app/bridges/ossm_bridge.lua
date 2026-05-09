-- OSSM Sauce <-> MPV bridge
--
-- Exposes mpv's JSON IPC protocol over TCP on 0.0.0.0:9001.
-- OSSM Sauce connects, sends {"command":[...]} lines, receives
-- {"event":"property-change","name":"...","data":...} events for the
-- observed properties (time-pos, pause, duration, filename).
--
-- Requires LuaJIT (standard in desktop mpv builds on Windows/Linux/macOS).
-- mpv-android ships plain Lua 5.2 with no FFI — see project notes for the
-- separate file-IPC approach planned there.
--
-- Install: drop into your mpv scripts dir, e.g.
--   Windows: %APPDATA%\mpv\scripts\ossm_bridge.lua
--   Linux/macOS: ~/.config/mpv/scripts/ossm_bridge.lua

local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'

local ffi_ok, ffi = pcall(require, 'ffi')
if not ffi_ok then
    mp.msg.error("ossm_bridge: LuaJIT FFI not available; cannot open TCP server.")
    return
end
local bit = require 'bit'

-- Read port from script-opts/ossm_bridge.conf (key: port=NNNN). OSSM Sauce
-- maintains that file as its single source of truth for the bridge port.
local opts = {port = 9001}
options.read_options(opts, "ossm_bridge")
local PORT = opts.port
local IS_WIN = (ffi.os == 'Windows')

local function htons(n)
    return bit.bor(bit.lshift(bit.band(n, 0xff), 8),
                   bit.rshift(bit.band(n, 0xff00), 8))
end

-- ============================================================
-- FFI: socket primitives
-- ============================================================

ffi.cdef[[
struct sockaddr_in {
    uint16_t sin_family;
    uint16_t sin_port;
    uint32_t sin_addr;
    char     sin_zero[8];
};
]]

local sock, INVALID_FD

if IS_WIN then
    ffi.cdef[[
    typedef uintptr_t SOCKET;
    struct WSAData_padded { char pad[512]; };
    struct fd_set_win {
        uint32_t fd_count;
        uintptr_t fd_array[64];
    };
    struct timeval_win { int32_t tv_sec; int32_t tv_usec; };
    int __stdcall WSAStartup(uint16_t, struct WSAData_padded*);
    int __stdcall WSAGetLastError(void);
    SOCKET __stdcall socket(int, int, int);
    int __stdcall bind(SOCKET, const struct sockaddr_in*, int);
    int __stdcall listen(SOCKET, int);
    SOCKET __stdcall accept(SOCKET, void*, int*);
    int __stdcall closesocket(SOCKET);
    int __stdcall send(SOCKET, const char*, int, int);
    int __stdcall recv(SOCKET, char*, int, int);
    int __stdcall select(int32_t, struct fd_set_win*, struct fd_set_win*,
                         struct fd_set_win*, const struct timeval_win*);
    int __stdcall setsockopt(SOCKET, int, int, const char*, int);
    ]]
    sock = ffi.load('ws2_32')
    INVALID_FD = ffi.cast('uintptr_t', -1)
    local wsa = ffi.new('struct WSAData_padded')
    if sock.WSAStartup(0x0202, wsa) ~= 0 then
        mp.msg.error("ossm_bridge: WSAStartup failed")
        return
    end
else
    ffi.cdef[[
    typedef uint32_t socklen_t;
    int socket(int, int, int);
    int bind(int, const struct sockaddr_in*, socklen_t);
    int listen(int, int);
    int accept(int, void*, socklen_t*);
    int close(int);
    int send(int, const char*, size_t, int);
    int recv(int, char*, size_t, int);
    int fcntl(int, int, int);
    int setsockopt(int, int, int, const void*, socklen_t);
    ]]
    sock = ffi.C
    INVALID_FD = -1
end

local function is_bad_fd(fd)
    if IS_WIN then return fd == INVALID_FD end
    return tonumber(fd) < 0
end

local function close_fd(fd)
    if IS_WIN then sock.closesocket(fd) else sock.close(fd) end
end

local function last_err()
    if IS_WIN then return tonumber(sock.WSAGetLastError()) end
    return -1
end

-- POSIX nonblock via fcntl. Windows uses select() polling instead
-- (ioctlsocket FIONBIO has returned WSAEOPNOTSUPP in our LuaJIT tests).
local function set_nonblock_posix(fd)
    local F_GETFL, F_SETFL = 3, 4
    local O_NONBLOCK = (ffi.os == 'OSX') and 0x0004 or 0x0800
    local flags = sock.fcntl(fd, F_GETFL, 0)
    sock.fcntl(fd, F_SETFL, bit.bor(flags, O_NONBLOCK))
end

local is_readable
if IS_WIN then
    local rset = ffi.new('struct fd_set_win')
    local tv = ffi.new('struct timeval_win')
    is_readable = function(fd)
        rset.fd_count = 1
        rset.fd_array[0] = fd
        tv.tv_sec = 0
        tv.tv_usec = 0
        return sock.select(0, rset, nil, nil, tv) > 0
    end
else
    -- POSIX: socket is nonblocking, recv returns -1/EWOULDBLOCK when empty
    is_readable = function(_) return true end
end

-- ============================================================
-- Create listen socket
-- ============================================================

local AF_INET, SOCK_STREAM = 2, 1
-- SOL_SOCKET and SO_REUSEADDR values diverge: Windows and macOS use
-- BSD-legacy 0xFFFF / 4; Linux uses 1 / 2. Apply non-fatally — if
-- setsockopt silently hits the wrong option, we just lose the TIME_WAIT
-- skip, not functionality.
local SOL_SOCKET, SO_REUSEADDR
if IS_WIN or ffi.os == 'OSX' then
    SOL_SOCKET, SO_REUSEADDR = 0xffff, 0x0004
else
    SOL_SOCKET, SO_REUSEADDR = 1, 2
end

local listen_fd = sock.socket(AF_INET, SOCK_STREAM, 0)
if is_bad_fd(listen_fd) then
    mp.msg.error("ossm_bridge: socket() failed, err=" .. last_err())
    return
end

-- SO_REUSEADDR so we can re-bind after a crashy restart without TIME_WAIT hell
do
    local yes = ffi.new('int[1]', 1)
    sock.setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR,
                    ffi.cast(IS_WIN and 'const char*' or 'const void*', yes),
                    ffi.sizeof('int'))
end

if not IS_WIN then set_nonblock_posix(listen_fd) end

local addr = ffi.new('struct sockaddr_in')
addr.sin_family = AF_INET
addr.sin_port = htons(PORT)
addr.sin_addr = 0  -- INADDR_ANY, all interfaces

if sock.bind(listen_fd, addr, ffi.sizeof('struct sockaddr_in')) ~= 0 then
    mp.msg.error("ossm_bridge: bind() failed on port " .. PORT .. ", err=" .. last_err())
    close_fd(listen_fd)
    return
end

if sock.listen(listen_fd, 4) ~= 0 then
    mp.msg.error("ossm_bridge: listen() failed, err=" .. last_err())
    close_fd(listen_fd)
    return
end

mp.msg.info("ossm_bridge: listening on 0.0.0.0:" .. PORT)

-- ============================================================
-- Client state
-- ============================================================

-- clients[i] = { fd=SOCKET, rbuf=string, wbuf=string }
local clients = {}
local recv_buf = ffi.new('char[4096]')

local function accept_one()
    if not is_readable(listen_fd) then return nil end
    local ca = ffi.new('struct sockaddr_in')
    local fd
    if IS_WIN then
        local al = ffi.new('int[1]', ffi.sizeof('struct sockaddr_in'))
        fd = sock.accept(listen_fd, ca, al)
        if fd == INVALID_FD then return nil end
    else
        local al = ffi.new('socklen_t[1]', ffi.sizeof('struct sockaddr_in'))
        fd = sock.accept(listen_fd, ca, al)
        if tonumber(fd) < 0 then return nil end
        set_nonblock_posix(fd)
    end
    return fd
end

local function queue_write(client, s)
    client.wbuf = client.wbuf .. s
end

local function broadcast(line)
    for _, c in ipairs(clients) do
        queue_write(c, line)
    end
end

local function flush_writes(client)
    if #client.wbuf == 0 then return true end
    local data = client.wbuf
    local n = tonumber(sock.send(client.fd, data, #data, 0))
    if n and n > 0 then
        client.wbuf = data:sub(n + 1)
        return true
    end
    -- n == 0 shouldn't happen on a connected stream socket without an error.
    -- n < 0 = would-block or real error; we just try again next tick.
    return n and n >= 0
end

-- ============================================================
-- JSON encoding helpers
-- ============================================================

-- mpv's property values can be nil (e.g., time-pos before a file loads).
-- Lua tables drop nil fields, so we build the event envelope as a string.
local function encode_property_event(name, value)
    local data_json
    if value == nil then
        data_json = "null"
    else
        data_json = utils.format_json(value)
    end
    return '{"event":"property-change","name":' .. utils.format_json(name)
        .. ',"data":' .. data_json .. '}\n'
end

local function encode_event(tbl)
    -- Generic event; caller provides the full table.
    return utils.format_json(tbl) .. '\n'
end

local function encode_reply(request_id, ok, data_or_err)
    local parts = {}
    if ok then
        parts[#parts+1] = '"error":"success"'
        if data_or_err ~= nil then
            parts[#parts+1] = '"data":' .. utils.format_json(data_or_err)
        else
            parts[#parts+1] = '"data":null'
        end
    else
        parts[#parts+1] = '"error":' .. utils.format_json(tostring(data_or_err))
    end
    if request_id ~= nil then
        parts[#parts+1] = '"request_id":' .. utils.format_json(request_id)
    end
    return '{' .. table.concat(parts, ',') .. '}\n'
end

-- ============================================================
-- Command dispatch
-- ============================================================

-- Property accessor commands fail through mp.command_native in some mpv
-- builds even though they work over real JSON IPC. Route them to the
-- dedicated mp.get_property* / mp.set_property* functions, which talk
-- to mpv's property store directly and bypass the command dispatcher.
local function dispatch(cmd)
    local op = cmd[1]
    if op == "get_property" then
        return mp.get_property(cmd[2])
    elseif op == "get_property_native" then
        return mp.get_property_native(cmd[2])
    elseif op == "set_property" or op == "set_property_native" then
        -- Both names route to the native setter. Clients should send JSON
        -- values matching the property's type (bool for pause, number for
        -- volume, etc). String-format setting hit "unsupported format" on
        -- the pause property in testing — native is the reliable path.
        local ok, e = mp.set_property_native(cmd[2], cmd[3])
        if not ok then return nil, e end
        return nil
    else
        return mp.command_native(cmd)
    end
end

local function handle_command_line(client, line)
    if line == "" then return end
    local msg, err = utils.parse_json(line)
    if not msg then
        queue_write(client, encode_reply(nil, false, "json parse error: " .. tostring(err)))
        return
    end
    local cmd = msg.command
    if type(cmd) ~= "table" then
        queue_write(client, encode_reply(msg.request_id, false, "missing or invalid 'command' array"))
        return
    end
    local result, run_err = dispatch(cmd)
    if run_err then
        queue_write(client, encode_reply(msg.request_id, false, run_err))
    else
        queue_write(client, encode_reply(msg.request_id, true, result))
    end
end

local function consume_lines(client)
    while true do
        local nl = client.rbuf:find("\n", 1, true)
        if not nl then break end
        local line = client.rbuf:sub(1, nl - 1):gsub("\r$", "")
        client.rbuf = client.rbuf:sub(nl + 1)
        handle_command_line(client, line)
    end
end

-- ============================================================
-- Property observers → broadcast events
-- ============================================================

local OBSERVED = {"time-pos", "pause", "duration", "filename"}

for _, name in ipairs(OBSERVED) do
    mp.observe_property(name, "native", function(pname, value)
        if #clients == 0 then return end
        broadcast(encode_property_event(pname, value))
    end)
end

-- Also emit file-loaded / end-file as discrete events, matching mpv IPC style.
mp.register_event("file-loaded", function()
    if #clients == 0 then return end
    broadcast(encode_event({event = "file-loaded"}))
end)

mp.register_event("end-file", function(ev)
    if #clients == 0 then return end
    broadcast(encode_event({event = "end-file", reason = ev.reason}))
end)

-- ============================================================
-- Main I/O loop (mpv periodic timer)
-- ============================================================

local function drop_client(i, reason)
    local c = clients[i]
    mp.msg.info("ossm_bridge: client " .. tostring(c.fd) .. " disconnected (" .. reason .. ")")
    close_fd(c.fd)
    table.remove(clients, i)
end

mp.add_periodic_timer(0.05, function()
    -- 1. Accept new clients
    while true do
        local fd = accept_one()
        if not fd then break end
        local c = {fd = fd, rbuf = "", wbuf = ""}
        table.insert(clients, c)
        mp.msg.info("ossm_bridge: client " .. tostring(fd) .. " connected")
        -- Send a snapshot of the currently observed properties so the client
        -- doesn't have to wait for the next property change to learn state.
        for _, name in ipairs(OBSERVED) do
            queue_write(c, encode_property_event(name, mp.get_property_native(name)))
        end
    end

    -- 2. Read from clients
    for i = #clients, 1, -1 do
        local c = clients[i]
        if is_readable(c.fd) then
            local n = tonumber(sock.recv(c.fd, recv_buf, 4096, 0))
            if n and n > 0 then
                c.rbuf = c.rbuf .. ffi.string(recv_buf, n)
                consume_lines(c)
            elseif n == 0 then
                drop_client(i, "remote close")
            end
            -- n < 0 on POSIX = EWOULDBLOCK; ignore.
        end
    end

    -- 3. Flush writes
    for i = #clients, 1, -1 do
        if not flush_writes(clients[i]) then
            drop_client(i, "send error")
        end
    end
end)

-- ============================================================
-- Shutdown
-- ============================================================

mp.register_event("shutdown", function()
    for i = #clients, 1, -1 do
        close_fd(clients[i].fd)
        clients[i] = nil
    end
    close_fd(listen_fd)
    mp.msg.info("ossm_bridge: stopped")
end)
