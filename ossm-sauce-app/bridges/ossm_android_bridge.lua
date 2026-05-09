-- ossm_android_bridge.lua
-- OSSM Sauce bridge for mpv-android (Phase 2: file-based IPC).
-- Companion to ossm_bridge.lua (desktop TCP version).
--
-- Out: writes /sdcard/Android/media/is.xyz.mpv/ossm_bridge/state.json
--      on every observed property change (truncate-write snapshot).
-- In:  polls .../ossm_bridge/command_queue/cmd_*.json every 50ms,
--      processes oldest-first, deletes after.
--
-- The bridge directory and command_queue subdirectory must exist before
-- the script loads; the OSSM Sauce installer creates them.

local utils = require 'mp.utils'

local BRIDGE_DIR  = '/storage/emulated/0/Android/media/is.xyz.mpv/ossm_bridge'
local STATE_PATH  = BRIDGE_DIR .. '/state.json'
local COMMAND_DIR = BRIDGE_DIR .. '/command_queue'
local POLL_INTERVAL = 0.05

local PROPERTIES = {
    {name = 'time-pos', type = 'number'},
    {name = 'pause',    type = 'bool'},
    {name = 'duration', type = 'number'},
    {name = 'filename', type = 'string'},
}

local state = {}
local heartbeat = 0

local function write_state()
    -- OSSM Sauce reads state.json over SAF and uses this counter to detect
    -- liveness — SAF mtime is unreliable, so the heartbeat lives in-band.
    heartbeat = heartbeat + 1
    state.heartbeat = heartbeat
    local body = utils.format_json(state)
    local f, err = io.open(STATE_PATH, 'w')
    if f == nil then
        mp.msg.error('write_state: io.open failed: ' .. tostring(err))
        return
    end
    f:write(body)
    f:close()
end

for _, p in ipairs(PROPERTIES) do
    mp.observe_property(p.name, p.type, function(_, v)
        state[p.name] = v
        write_state()
    end)
end

local function process_command_file(path)
    local f, err = io.open(path, 'r')
    if f == nil then
        mp.msg.error('cannot read ' .. path .. ': ' .. tostring(err))
        os.remove(path)
        return
    end
    local body = f:read('*a')
    f:close()

    local parsed, _perr = utils.parse_json(body)
    if parsed == nil then
        -- Likely a half-written file from a racing GDScript writer.
        -- Leave it; next poll should see the complete file. Genuinely
        -- corrupt files are wiped by clear_command_queue on next session.
        return
    end
    os.remove(path)

    if type(parsed.command) ~= 'table' then
        mp.msg.error('missing "command" array in ' .. path)
        return
    end

    -- Mirrors desktop bridge dispatch: route property setters through
    -- set_property_native, everything else through command_native.
    local cmd = parsed.command[1]
    if cmd == 'set_property' or cmd == 'set_property_native' then
        local ok, cerr = pcall(mp.set_property_native,
                               parsed.command[2], parsed.command[3])
        if not ok then
            mp.msg.warn('set_property error: ' .. tostring(cerr))
        end
    elseif cmd == 'get_property' or cmd == 'get_property_native' then
        mp.msg.warn('get_property received as command; clients should ' ..
                    'read state.json instead')
    else
        local ok, cerr = pcall(mp.command_native, parsed.command)
        if not ok then
            mp.msg.warn('command error: ' .. tostring(cerr))
        end
    end
end

local function poll_commands()
    local entries, _ = utils.readdir(COMMAND_DIR, 'files')
    if entries == nil then return end
    table.sort(entries)
    for _, name in ipairs(entries) do
        if name:match('^cmd_.+%.json$') then
            process_command_file(COMMAND_DIR .. '/' .. name)
        end
    end
end

mp.add_periodic_timer(POLL_INTERVAL, poll_commands)

-- 1Hz heartbeat so OSSM Sauce can distinguish "bridge alive but paused
-- on a single frame" from "mpv-android closed". State writes are
-- idempotent — same content rewriting is a no-op semantically.
mp.add_periodic_timer(1.0, write_state)

mp.msg.info('[ossm_android_bridge] loaded; bridge dir = ' .. BRIDGE_DIR)
write_state()
