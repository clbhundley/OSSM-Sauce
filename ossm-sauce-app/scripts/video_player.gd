extends Panel

enum PlayerType { OFF, VLC, MPC, MPV, MPV_ANDROID }

# Configuration — set these from your UI
var player_type: PlayerType = PlayerType.OFF
var player_address: String = "127.0.0.1"
var player_port: int = 8080
var vlc_password: String = ""
var delay_ms: int = 0
var advance_ms: int = 100
var video_offset_ms: int = 0
var vlc_seek_correction: float = 0.0

# Read-only state
var connected: bool = false
var player_state: String = "stopped"
var player_time: float = 0.0
var player_duration: float = 0.0

# Signals for bidirectional sync
signal player_played(video_time_seconds: float, from_stopped: bool)
signal player_paused
signal player_seeked(video_time_seconds: float)
signal connection_changed(is_connected: bool)

var _cooldown: bool = false
var _poll_in_flight: bool = false
var _pending_action: String = ""
var _seek_after_pause: float = -1.0

var _command_http: HTTPRequest
var _poll_http: HTTPRequest
var _poll_timer: Timer
var _delay_timer: Timer
var _cooldown_timer: Timer

var _mpc_state_regex: RegEx
var _mpc_pos_regex: RegEx
var _mpc_dur_regex: RegEx

var _mpv_tcp: StreamPeerTCP = null
var _mpv_buffer: String = ""
var _mpv_pause: bool = true
var _mpv_filename = null
var _mpv_time_pos = null
var _mpv_duration = null
var _mpv_received_filename: bool = false
var _mpv_reconnect_accum: float = 0.0

const _MPV_ANDROID_HEARTBEAT_TIMEOUT := 3.0  # seconds without heartbeat change
const _MPV_ANDROID_STATE_FILE := "ossm_bridge/state.json"
const _MPV_ANDROID_BRIDGE_SUBDIR := "ossm_bridge"
const _MPV_ANDROID_COMMAND_SUBDIR := "ossm_bridge/command_queue"
const _MPV_ANDROID_SCRIPTS_SUBDIR := "scripts"
const _MPV_ANDROID_LUA_FILE := "scripts/ossm_android_bridge.lua"
const _MPV_ANDROID_LUA_SOURCE := "res://bridges/ossm_android_bridge.lua"
# Hardcoded — mpv-android can only load scripts from its own /Android/media/
# package dir under scoped storage, so this path is fixed by platform.
const _MPV_ANDROID_SCRIPT_LINE := \
	"script=/sdcard/Android/media/is.xyz.mpv/scripts/ossm_android_bridge.lua"
const _MPV_ANDROID_EXPECTED_DOC_ID := "primary:Android/media/is.xyz.mpv"

var _mpv_android_state: Dictionary = {}
var _mpv_android_received_filename: bool = false
var _mpv_android_last_heartbeat: int = 0
var _mpv_android_last_heartbeat_seen_at: float = 0.0
var _mpv_android_command_counter: int = 0
var _mpv_android_pending_player_type: PlayerType = PlayerType.OFF
var _mpv_desktop_pending_player_type: PlayerType = PlayerType.OFF


func _ready():
	self_modulate.a = 2
	
	$Main/HelpButton.hide()
	
	if OS.get_name() != "Android":
		$Main/PlayerSelection.set_item_disabled(PlayerType.MPV_ANDROID, true)
	
	connection_changed.connect(func(is_connected: bool):
			if is_connected:
				$Main/ConnectionIndicator.show()
			else:
				$Main/ConnectionIndicator.hide())
	
	_command_http = HTTPRequest.new()
	_command_http.name = "CommandHTTP"
	_command_http.timeout = 2
	add_child(_command_http)
	_command_http.request_completed.connect(_on_command_completed)
	
	_poll_http = HTTPRequest.new()
	_poll_http.name = "PollHTTP"
	_poll_http.timeout = 2
	add_child(_poll_http)
	_poll_http.request_completed.connect(_on_poll_completed)
	
	_poll_timer = Timer.new()
	_poll_timer.name = "PollTimer"
	_poll_timer.wait_time = 0.1
	add_child(_poll_timer)
	_poll_timer.timeout.connect(_poll_status)
	
	_delay_timer = Timer.new()
	_delay_timer.name = "DelayTimer"
	_delay_timer.one_shot = true
	add_child(_delay_timer)
	_delay_timer.timeout.connect(_on_delay_timeout)
	
	_cooldown_timer = Timer.new()
	_cooldown_timer.name = "CooldownTimer"
	_cooldown_timer.one_shot = true
	_cooldown_timer.wait_time = 0.5
	add_child(_cooldown_timer)
	_cooldown_timer.timeout.connect(func(): _cooldown = false)
	
	_mpc_state_regex = RegEx.new()
	_mpc_state_regex.compile('<p id="state">(\\d+)</p>')
	_mpc_pos_regex = RegEx.new()
	_mpc_pos_regex.compile('<p id="position">(\\d+)</p>')
	_mpc_dur_regex = RegEx.new()
	_mpc_dur_regex.compile('<p id="duration">(\\d+)</p>')


func is_active() -> bool:
	return player_type != PlayerType.OFF


func activate(type: PlayerType):
	deactivate()
	player_type = type
	match type:
		PlayerType.OFF:
			pass
		PlayerType.MPV:
			_mpv_connect()
		PlayerType.MPV_ANDROID:
			_mpv_android_activate()
			_poll_timer.wait_time = 0.1
			_poll_timer.start()
		_:
			# Slower poll on Android: VLC/MPC HTTP polling keeps the WiFi
			# radio busy continuously, draining battery. 500ms is well within
			# what the offset inputs can absorb. Desktop stays at 100ms.
			_poll_timer.wait_time = 0.5 if OS.get_name() == "Android" else 0.1
			_poll_timer.start()


func deactivate():
	player_type = PlayerType.OFF
	_poll_timer.stop()
	_delay_timer.stop()
	_cooldown_timer.stop()
	_poll_http.cancel_request()
	_command_http.cancel_request()
	_mpv_disconnect()
	_mpv_android_disconnect()
	_poll_in_flight = false
	_cooldown = false
	_pending_action = ""
	player_state = "stopped"
	player_time = 0.0
	player_duration = 0.0
	if connected:
		connected = false
		connection_changed.emit(false)


# ---- App -> Video Player ----

func sync_play():
	_send_play()
	_start_cooldown()
	if delay_ms > 0:
		_pending_action = "play"
		_delay_timer.wait_time = delay_ms / 1000.0
		_delay_timer.start()
	else:
		owner.play()


func sync_pause():
	_send_pause()
	_start_cooldown()
	if delay_ms > 0:
		_pending_action = "pause"
		_delay_timer.wait_time = delay_ms / 1000.0
		_delay_timer.start()
	else:
		owner.pause()


func sync_seek(path_time_seconds: float):
	_send_seek(_path_to_video_time(path_time_seconds))
	_start_cooldown()


func pause_and_seek(path_time_seconds: float):
	var video_time = _path_to_video_time(path_time_seconds)
	if player_type == PlayerType.MPV or player_type == PlayerType.MPV_ANDROID:
		_send_pause()
		_send_seek(video_time)
	else:
		_seek_after_pause = video_time
		_send_pause()
	_start_cooldown()


func pause_player():
	if not is_active():
		return
	_send_pause()
	_start_cooldown()


func _on_delay_timeout():
	match _pending_action:
		"play":
			owner.play()
		"pause":
			owner.pause()
	_pending_action = ""


# ---- HTTP Commands ----

func _path_to_video_time(path_time_seconds: float) -> float:
	var video_time = path_time_seconds - delay_ms / 1000.0 + video_offset_ms / 1000.0
	if player_type == PlayerType.VLC and vlc_seek_correction != 0:
		video_time -= vlc_seek_correction * video_time / 60.0 / 1000.0
	return maxf(video_time, 0.0)


func _base_url() -> String:
	return "http://" + player_address + ":" + str(player_port)


func _vlc_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Basic " + Marshalls.utf8_to_base64(":" + vlc_password)
	])


func _send_play():
	_command_http.cancel_request()
	match player_type:
		PlayerType.VLC:
			_command_http.request(
				_base_url() + "/requests/status.json?command=pl_forceresume",
				_vlc_headers())
		PlayerType.MPC:
			_command_http.request(_base_url() + "/command.html?wm_command=887")
		PlayerType.MPV:
			_mpv_send_command(["set_property", "pause", false])
		PlayerType.MPV_ANDROID:
			_mpv_android_send_command(["set_property", "pause", false])


func _send_pause():
	_command_http.cancel_request()
	match player_type:
		PlayerType.VLC:
			_command_http.request(
				_base_url() + "/requests/status.json?command=pl_forcepause",
				_vlc_headers())
		PlayerType.MPC:
			_command_http.request(_base_url() + "/command.html?wm_command=888")
		PlayerType.MPV:
			_mpv_send_command(["set_property", "pause", true])
		PlayerType.MPV_ANDROID:
			_mpv_android_send_command(["set_property", "pause", true])


func _send_seek(time_seconds: float):
	_command_http.cancel_request()
	match player_type:
		PlayerType.VLC:
			var pct = "0"
			if player_duration > 0.0:
				pct = "%f" % (time_seconds / player_duration * 100.0)
			_command_http.request(
				_base_url() + "/requests/status.json?command=seek&val=" \
				+ pct + "%25",
				_vlc_headers())
		PlayerType.MPC:
			var total_ms = int(time_seconds * 1000)
			var h = total_ms / 3600000
			var m = (total_ms % 3600000) / 60000
			var s = (total_ms % 60000) / 1000
			var ms = total_ms % 1000
			_command_http.request(
				_base_url() + "/command.html?wm_command=-1&position=" \
				+ "%02d:%02d:%02d.%03d" % [h, m, s, ms])
		PlayerType.MPV:
			_mpv_send_command(["seek", time_seconds, "absolute"])
		PlayerType.MPV_ANDROID:
			_mpv_android_send_command(["seek", time_seconds, "absolute"])


func _on_command_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_seek_after_pause = -1.0
		return
	if player_type == PlayerType.VLC:
		_parse_vlc(body)
	if _seek_after_pause >= 0.0:
		var time = _seek_after_pause
		_seek_after_pause = -1.0
		await get_tree().create_timer(0.1).timeout
		_send_seek(time)


# ---- Polling ----

func _poll_status():
	if player_type == PlayerType.OFF:
		return
	if player_type == PlayerType.MPV_ANDROID:
		_mpv_android_poll()
		return
	if _poll_in_flight:
		return
	_poll_in_flight = true
	match player_type:
		PlayerType.VLC:
			_poll_http.request(_base_url() + "/requests/status.json", _vlc_headers())
		PlayerType.MPC:
			_poll_http.request(_base_url() + "/variables.html")


func _on_poll_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	_poll_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if connected:
			connected = false
			player_state = "stopped"
			connection_changed.emit(false)
			player_paused.emit()
		return
	if not connected:
		connected = true
		connection_changed.emit(true)
	match player_type:
		PlayerType.VLC:
			_parse_vlc(body)
		PlayerType.MPC:
			_parse_mpc(body)


# ---- Response Parsing ----

func _parse_vlc(body: PackedByteArray):
	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json is Dictionary:
		return
	var length = float(json.get("length", 0))
	var _position = float(json.get("position", 0))
	_process_state(
		json.get("state", "stopped"),
		_position * length,
		length)


func _parse_mpc(body: PackedByteArray):
	var html = body.get_string_from_utf8()
	var state_match = _mpc_state_regex.search(html)
	if not state_match:
		return
	var state_code = int(state_match.get_string(1))
	var state: String
	match state_code:
		0: state = "stopped"
		1: state = "paused"
		2: state = "playing"
		_: state = "stopped"
	var time_sec := 0.0
	var duration_sec := 0.0
	var pos_match = _mpc_pos_regex.search(html)
	if pos_match:
		time_sec = float(pos_match.get_string(1)) / 1000.0
	var dur_match = _mpc_dur_regex.search(html)
	if dur_match:
		duration_sec = float(dur_match.get_string(1)) / 1000.0
	_process_state(state, time_sec, duration_sec)


func _process_state(new_state: String, new_time: float, new_duration: float):
	var old_state = player_state
	var old_time = player_time
	player_state = new_state
	player_time = new_time
	player_duration = new_duration
	if _cooldown:
		return
	if new_state != old_state:
		match new_state:
			"playing":
				var adjusted = new_time - video_offset_ms / 1000.0 + delay_ms / 1000.0 + advance_ms / 1000.0
				player_played.emit(maxf(adjusted, 0.0), old_state == "stopped")
			"paused", "stopped":
				player_paused.emit()
	elif abs(new_time - old_time) > 1.5:
		var adjusted = new_time - video_offset_ms / 1000.0 + delay_ms / 1000.0
		player_seeked.emit(maxf(adjusted, 0.0))


# ---- MPV TCP ----

func _mpv_connect():
	_mpv_tcp = StreamPeerTCP.new()
	var err := _mpv_tcp.connect_to_host(player_address, player_port)
	if err != OK:
		push_warning("MPV TCP connect_to_host failed: %d" % err)
		_mpv_tcp = null


func _mpv_disconnect():
	if _mpv_tcp != null:
		_mpv_tcp.disconnect_from_host()
		_mpv_tcp = null
	_mpv_buffer = ""
	_mpv_pause = true
	_mpv_filename = null
	_mpv_time_pos = null
	_mpv_duration = null
	_mpv_received_filename = false


func _process(delta):
	if player_type != PlayerType.MPV:
		return
	if _mpv_tcp == null:
		_mpv_reconnect_accum += delta
		if _mpv_reconnect_accum >= 1.0:
			_mpv_reconnect_accum = 0.0
			_mpv_connect()
		return
	_mpv_reconnect_accum = 0.0
	_mpv_tcp.poll()
	match _mpv_tcp.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			if not connected:
				connected = true
				connection_changed.emit(true)
			var avail := _mpv_tcp.get_available_bytes()
			if avail > 0:
				var result = _mpv_tcp.get_data(avail)
				if result[0] == OK:
					_mpv_buffer += (result[1] as PackedByteArray).get_string_from_utf8()
					_mpv_drain_buffer()
		StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
			if connected:
				connected = false
				player_state = "stopped"
				connection_changed.emit(false)
				player_paused.emit()
			_mpv_disconnect()


func _mpv_drain_buffer():
	while true:
		var nl_idx := _mpv_buffer.find("\n")
		if nl_idx < 0:
			break
		var line := _mpv_buffer.substr(0, nl_idx)
		_mpv_buffer = _mpv_buffer.substr(nl_idx + 1)
		if line.strip_edges().is_empty():
			continue
		_mpv_handle_line(line)


func _mpv_handle_line(line: String):
	var msg = JSON.parse_string(line)
	if not msg is Dictionary:
		return
	if msg.has("event"):
		_mpv_handle_event(msg)
	# Replies (msg.has("error")) are intentionally ignored — property
	# observers tell us everything we need to know about player state.


func _mpv_handle_event(msg: Dictionary):
	match msg.get("event", ""):
		"property-change":
			var name: String = msg.get("name", "")
			var value = msg.get("data")
			match name:
				"pause":
					if value is bool:
						_mpv_pause = value
				"time-pos":
					_mpv_time_pos = value
				"duration":
					_mpv_duration = value
				"filename":
					_mpv_filename = value
					_mpv_received_filename = true
			_mpv_update_state()
		"end-file":
			_mpv_filename = null
			_mpv_received_filename = true
			_mpv_update_state()


func _mpv_update_state():
	# Wait for filename to arrive before deriving state — during the initial
	# snapshot burst the other properties land first, and acting on them
	# would emit phantom seek/pause signals before we know if a file is loaded.
	if not _mpv_received_filename:
		return
	var state: String
	if _mpv_filename == null:
		state = "stopped"
	elif _mpv_pause:
		state = "paused"
	else:
		state = "playing"
	var time := 0.0
	var duration := 0.0
	if _mpv_filename != null:
		if _mpv_time_pos != null:
			time = float(_mpv_time_pos)
		if _mpv_duration != null:
			duration = float(_mpv_duration)
	_process_state(state, time, duration)


func _mpv_send_command(arr: Array):
	if _mpv_tcp == null:
		return
	if _mpv_tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var line := JSON.stringify({"command": arr}) + "\n"
	_mpv_tcp.put_data(line.to_utf8_buffer())


# ---- MPV Android File IPC (SAF) ----

func _mpv_android_saf_path(rel: String) -> String:
	# Builds a Godot SAF FileAccess path from the picked bridge tree URI.
	var uri: String = owner.saf_mpv_bridge_uri
	if uri.is_empty():
		return ""
	return uri + "#" + rel


func _mpv_android_activate():
	_mpv_android_state = {}
	_mpv_android_received_filename = false
	_mpv_android_last_heartbeat = 0
	_mpv_android_last_heartbeat_seen_at = 0.0
	_mpv_android_command_counter = 0
	_mpv_android_ensure_subdir(_MPV_ANDROID_BRIDGE_SUBDIR)
	_mpv_android_ensure_subdir(_MPV_ANDROID_COMMAND_SUBDIR)
	_mpv_android_clear_command_queue()


func _mpv_android_disconnect():
	_mpv_android_state = {}
	_mpv_android_received_filename = false
	_mpv_android_last_heartbeat = 0
	_mpv_android_last_heartbeat_seen_at = 0.0


func _mpv_android_clear_command_queue():
	# Stale commands from a previous session would otherwise be eaten by
	# the bridge as soon as it sees them, with no relation to current intent.
	var uri: String = owner.saf_mpv_bridge_uri
	if uri.is_empty():
		return
	var DocumentsContract = JavaClassWrapper.wrap("android.provider.DocumentsContract")
	var Uri = JavaClassWrapper.wrap("android.net.Uri")
	var ActivityThread = JavaClassWrapper.wrap("android.app.ActivityThread")
	if DocumentsContract == null or Uri == null or ActivityThread == null:
		return
	var tree_uri_obj = Uri.parse(uri)
	if tree_uri_obj == null:
		return
	var tree_doc_id = DocumentsContract.getTreeDocumentId(tree_uri_obj)
	var cmd_doc_id := str(tree_doc_id) + "/" + _MPV_ANDROID_COMMAND_SUBDIR
	var children_uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree_uri_obj, cmd_doc_id)
	if children_uri == null:
		return
	var resolver = ActivityThread.currentActivityThread().getApplication().getContentResolver()
	var projection := PackedStringArray(["document_id", "_display_name"])
	var cursor = resolver.query(children_uri, projection, "", PackedStringArray(), "", null)
	if cursor == null:
		return
	var doc_id_col = cursor.getColumnIndex("document_id")
	var name_col = cursor.getColumnIndex("_display_name")
	while cursor.moveToNext():
		var name: String = cursor.getString(name_col)
		if name.begins_with("cmd_"):
			var doc_id = cursor.getString(doc_id_col)
			var doc_uri = DocumentsContract.buildDocumentUriUsingTree(tree_uri_obj, doc_id)
			DocumentsContract.deleteDocument(resolver, doc_uri)
	cursor.close()


func _mpv_android_ensure_subdir(rel_path: String) -> bool:
	# Walks rel_path and creates each missing component as a directory.
	var uri: String = owner.saf_mpv_bridge_uri
	if uri.is_empty():
		return false
	var DocumentsContract = JavaClassWrapper.wrap("android.provider.DocumentsContract")
	var Uri = JavaClassWrapper.wrap("android.net.Uri")
	var ActivityThread = JavaClassWrapper.wrap("android.app.ActivityThread")
	if DocumentsContract == null or Uri == null or ActivityThread == null:
		return false
	var tree_uri_obj = Uri.parse(uri)
	if tree_uri_obj == null:
		return false
	var tree_doc_id = DocumentsContract.getTreeDocumentId(tree_uri_obj)
	var resolver = ActivityThread.currentActivityThread().getApplication().getContentResolver()
	var current_doc_id := str(tree_doc_id)
	for part in rel_path.split("/", false):
		var children_uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree_uri_obj, current_doc_id)
		var found := false
		var cursor = resolver.query(children_uri, PackedStringArray(["_display_name"]), "", PackedStringArray(), "", null)
		if cursor != null:
			var name_col = cursor.getColumnIndex("_display_name")
			while cursor.moveToNext():
				if cursor.getString(name_col) == part:
					found = true
					break
			cursor.close()
		if not found:
			var parent_uri = DocumentsContract.buildDocumentUriUsingTree(tree_uri_obj, current_doc_id)
			var created = DocumentsContract.createDocument(resolver, parent_uri, "vnd.android.document/directory", part)
			if created == null:
				push_warning("MPV_ANDROID: createDocument failed at " + part)
				return false
		current_doc_id = current_doc_id + "/" + part
	return true


func _mpv_android_poll():
	var state_path := _mpv_android_saf_path(_MPV_ANDROID_STATE_FILE)
	if state_path.is_empty():
		_mpv_android_set_disconnected()
		return
	
	var f := FileAccess.open(state_path, FileAccess.READ)
	if f == null:
		_mpv_android_set_disconnected()
		return
	var body := f.get_as_text()
	f.close()
	
	var json = JSON.parse_string(body)
	if not json is Dictionary:
		return  # Partial write race — retry next poll.
	
	var heartbeat := int(json.get("heartbeat", 0))
	var now := Time.get_ticks_msec() / 1000.0
	
	# Bootstrap: first poll just records the heartbeat without marking alive.
	# Liveness = heartbeat changed within HEARTBEAT_TIMEOUT seconds.
	if _mpv_android_last_heartbeat_seen_at == 0.0:
		_mpv_android_last_heartbeat = heartbeat
		_mpv_android_last_heartbeat_seen_at = now
		return
	
	if heartbeat != _mpv_android_last_heartbeat:
		_mpv_android_last_heartbeat = heartbeat
		_mpv_android_last_heartbeat_seen_at = now
	
	var alive := (now - _mpv_android_last_heartbeat_seen_at) < _MPV_ANDROID_HEARTBEAT_TIMEOUT
	
	if alive and not connected:
		connected = true
		connection_changed.emit(true)
	elif not alive and connected:
		_mpv_android_set_disconnected()
		return
	
	if not connected:
		return
	
	_mpv_android_state = json
	if json.get("filename") != null:
		_mpv_android_received_filename = true
	_mpv_android_update_state()


func _mpv_android_set_disconnected():
	if connected:
		connected = false
		player_state = "stopped"
		connection_changed.emit(false)
		player_paused.emit()
	_mpv_android_received_filename = false


func _mpv_android_update_state():
	# Mirrors _mpv_update_state — wait for filename to land before deriving,
	# so phantom signals don't fire from a partial state snapshot.
	if not _mpv_android_received_filename:
		return
	var filename = _mpv_android_state.get("filename")
	var pause_val = _mpv_android_state.get("pause")
	var time_pos = _mpv_android_state.get("time-pos")
	var duration = _mpv_android_state.get("duration")
	
	var state: String
	if filename == null:
		state = "stopped"
	elif pause_val == true:
		state = "paused"
	else:
		state = "playing"
	
	var time_sec := 0.0
	var duration_sec := 0.0
	if filename != null:
		if time_pos != null:
			time_sec = float(time_pos)
		if duration != null:
			duration_sec = float(duration)
	_process_state(state, time_sec, duration_sec)


func _mpv_android_send_command(arr: Array):
	_mpv_android_command_counter += 1
	var seq := _mpv_android_command_counter
	var rel := _MPV_ANDROID_COMMAND_SUBDIR + "/cmd_%010d.json" % seq
	var path := _mpv_android_saf_path(rel)
	if path.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("MPV_ANDROID: cannot open command file " + path)
		return
	f.store_string(JSON.stringify({"command": arr}))
	f.close()


func _mpv_android_install_lua() -> bool:
	if not _mpv_android_ensure_subdir(_MPV_ANDROID_SCRIPTS_SUBDIR):
		return false
	var src := FileAccess.open(_MPV_ANDROID_LUA_SOURCE, FileAccess.READ)
	if src == null:
		push_warning("MPV_ANDROID: lua source missing at " + _MPV_ANDROID_LUA_SOURCE)
		return false
	var body := src.get_as_text()
	src.close()
	var dst_path := _mpv_android_saf_path(_MPV_ANDROID_LUA_FILE)
	var dst := FileAccess.open(dst_path, FileAccess.WRITE)
	if dst == null:
		push_warning("MPV_ANDROID: cannot write lua to " + dst_path)
		return false
	dst.store_string(body)
	dst.close()
	return true


func _mpv_android_ensure_mpv_media_dir() -> bool:
	# Attempts to create /Android/media/is.xyz.mpv/ so the SAF picker has
	# a target to navigate to even when mpv-android hasn't been opened yet.
	# Cross-app writes into another package's /Android/media/<pkg>/ are
	# generally blocked by scoped storage on API 30+ — if this fails, the
	# user has to open mpv-android once first to create the dir.
	var path := "/storage/emulated/0/Android/media/is.xyz.mpv"
	if DirAccess.dir_exists_absolute(path):
		return true
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_warning("MPV_ANDROID: could not create mpv media dir: " + str(err))
		return false
	return true


func _start_cooldown():
	_cooldown = true
	_cooldown_timer.start()


func reconnect(_player_type: PlayerType) -> void:
	deactivate()
	if _player_type > 0:
		activate(_player_type)


func _on_player_selection_item_selected(index: int) -> void:
	$Main/PlayerAddress.show()
	$Main/PlayerPort.show()
	$Main/DelayMs.show()
	$Main/AdvanceMs.show()
	$Main/VideoOffset.show()
	$Main/HelpButton.show()
	$Main/VLCPassword.hide()
	$Main/VLCSeekCorrection.hide()
	player_type = index as PlayerType
	owner.user_settings.set_value('video_player', 'player_type', index)
	match player_type:
		PlayerType.OFF:
			$Main/PlayerAddress.hide()
			$Main/PlayerPort.hide()
			$Main/DelayMs.hide()
			$Main/AdvanceMs.hide()
			$Main/VideoOffset.hide()
			$Main/HelpButton.hide()
			deactivate()
			return
		PlayerType.VLC:
			$Main/VLCPassword.show()
			$Main/VLCSeekCorrection.show()
			player_port = owner.user_settings.get_value('video_player', 'vlc_port', 8080)
			delay_ms = owner.user_settings.get_value('video_player', 'vlc_delay_ms', 0)
			advance_ms = owner.user_settings.get_value('video_player', 'vlc_advance_ms', 100)
		PlayerType.MPC:
			player_port = owner.user_settings.get_value('video_player', 'mpc_port', 13579)
			delay_ms = owner.user_settings.get_value('video_player', 'mpc_delay_ms', 0)
			advance_ms = owner.user_settings.get_value('video_player', 'mpc_advance_ms', 100)
		PlayerType.MPV:
			player_port = owner.user_settings.get_value('video_player', 'mpv_port', 9001)
			delay_ms = owner.user_settings.get_value('video_player', 'mpv_delay_ms', 0)
			advance_ms = owner.user_settings.get_value('video_player', 'mpv_advance_ms', 100)
		PlayerType.MPV_ANDROID:
			$Main/PlayerAddress.hide()
			$Main/PlayerPort.hide()
			delay_ms = owner.user_settings.get_value('video_player', 'mpv_android_delay_ms', 0)
			advance_ms = owner.user_settings.get_value('video_player', 'mpv_android_advance_ms', 100)
	$Main/PlayerPort/Input.set_value_no_signal(player_port)
	$Main/DelayMs/Input.value = delay_ms
	$Main/AdvanceMs/Input.value = advance_ms
	if player_type == PlayerType.MPV_ANDROID and owner.saf_mpv_bridge_uri.is_empty():
		# Defer activation until SAF folder is granted.
		_mpv_android_pending_player_type = PlayerType.MPV_ANDROID
		_mpv_android_ensure_mpv_media_dir()
		$MPVBridgeSplash.show()
		return
	if player_type == PlayerType.MPV and not MPVBridgeInstaller.is_installed():
		# Defer activation until the user consents to the lua/conf install.
		_mpv_desktop_pending_player_type = PlayerType.MPV
		_populate_mpv_bridge_desktop_splash()
		$MPVBridgeDesktopSplash.show()
		return
	activate(player_type)


func _on_player_address_text_submitted(new_text: String) -> void:
	player_address = new_text
	owner.user_settings.set_value('video_player', 'player_address', new_text)
	reconnect(player_type)


func _on_player_port_value_changed(value: float) -> void:
	player_port = int(value)
	match player_type:
		PlayerType.VLC:
			owner.user_settings.set_value('video_player', 'vlc_port', player_port)
		PlayerType.MPC:
			owner.user_settings.set_value('video_player', 'mpc_port', player_port)
		PlayerType.MPV:
			owner.user_settings.set_value('video_player', 'mpv_port', player_port)
			MPVBridgeInstaller.update_port(player_port)
	reconnect(player_type)


func _on_vlc_password_text_submitted(new_text: String) -> void:
	vlc_password = new_text
	owner.user_settings.set_value('video_player', 'vlc_password', new_text)
	reconnect(player_type)


func _on_delay_ms_value_changed(value: float) -> void:
	delay_ms = int(value)
	match player_type:
		PlayerType.VLC:
			owner.user_settings.set_value('video_player', 'vlc_delay_ms', delay_ms)
		PlayerType.MPC:
			owner.user_settings.set_value('video_player', 'mpc_delay_ms', delay_ms)
		PlayerType.MPV:
			owner.user_settings.set_value('video_player', 'mpv_delay_ms', delay_ms)
		PlayerType.MPV_ANDROID:
			owner.user_settings.set_value('video_player', 'mpv_android_delay_ms', delay_ms)


func _on_advance_ms_value_changed(value: float) -> void:
	advance_ms = int(value)
	match player_type:
		PlayerType.VLC:
			owner.user_settings.set_value('video_player', 'vlc_advance_ms', advance_ms)
		PlayerType.MPC:
			owner.user_settings.set_value('video_player', 'mpc_advance_ms', advance_ms)
		PlayerType.MPV:
			owner.user_settings.set_value('video_player', 'mpv_advance_ms', advance_ms)
		PlayerType.MPV_ANDROID:
			owner.user_settings.set_value('video_player', 'mpv_android_advance_ms', advance_ms)


func _on_video_offset_ms_value_changed(value: float) -> void:
	video_offset_ms = int(value)
	owner.user_settings.set_value('video_player', 'video_offset_ms', video_offset_ms)


func _on_vlc_seek_correction_value_changed(value: float) -> void:
	vlc_seek_correction = value
	owner.user_settings.set_value('video_player', 'vlc_seek_correction', vlc_seek_correction)


func _on_mpv_bridge_pick_pressed() -> void:
	var err := DisplayServer.file_dialog_show(
			"Pick mpv-android folder",
			"",
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_DIR,
			PackedStringArray(),
			_on_mpv_bridge_folder_picked)
	if err != OK:
		push_error("file_dialog_show failed: %s" % err)


func _on_mpv_bridge_folder_picked(
		status: bool,
		paths: PackedStringArray,
		_filter_idx: int) -> void:
	if not status or paths.is_empty():
		return
	var uri: String = paths[0]
	if not _mpv_android_uri_is_correct_folder(uri):
		OS.alert(
			"Please pick the 'is.xyz.mpv' folder inside Android/media.",
			"Wrong folder")
		return
	owner.saf_mpv_bridge_uri = uri
	owner.save_saf_mpv_bridge_uri(uri)
	owner._take_persistable_uri_permission(uri)
	if not _mpv_android_install_lua():
		push_warning("MPV_ANDROID: lua install failed")
	$MPVBridgeSplash.hide()
	$MPVSettingsCopySplash.show()


func _mpv_android_uri_is_correct_folder(uri: String) -> bool:
	# SAF tree URI ends with the URL-encoded document ID, e.g.
	# .../tree/primary%3AAndroid%2Fmedia%2Fis.xyz.mpv
	return uri.uri_decode().trim_suffix("/").ends_with(
		_MPV_ANDROID_EXPECTED_DOC_ID)


func _on_mpv_bridge_copy_pressed() -> void:
	DisplayServer.clipboard_set(_MPV_ANDROID_SCRIPT_LINE)


func _on_mpv_bridge_done_pressed() -> void:
	$MPVSettingsCopySplash.hide()
	if _mpv_android_pending_player_type == PlayerType.MPV_ANDROID:
		_mpv_android_pending_player_type = PlayerType.OFF
		activate(PlayerType.MPV_ANDROID)


func _on_mpv_bridge_cancel_pressed() -> void:
	$MPVBridgeSplash.hide()
	_mpv_android_pending_player_type = PlayerType.OFF
	$Main/PlayerSelection.select(PlayerType.OFF)
	player_type = PlayerType.OFF
	owner.user_settings.set_value('video_player', 'player_type', PlayerType.OFF)
	deactivate()


func _populate_mpv_bridge_desktop_splash() -> void:
	var lua_path := MPVBridgeInstaller.get_lua_path()
	var conf_path := MPVBridgeInstaller.get_conf_path()
	$MPVBridgeDesktopSplash/VBox/Label.text = (
			"[u]To use mpv, OSSM Sauce needs to install a bridge script.[/u]\n\n"
			+ "Files will be written to:\n\n"
			+ lua_path + "\n\n"
			+ conf_path + "\n\n"
			+ "[u]Make sure to restart mpv player after installing.[/u]")


func _on_mpv_bridge_install_pressed() -> void:
	var err := MPVBridgeInstaller.install(player_port)
	if err != OK:
		printerr("MPV bridge install failed: %s" % error_string(err))
		_on_mpv_bridge_install_cancel_pressed()
		return
	$MPVBridgeDesktopSplash.hide()
	if _mpv_desktop_pending_player_type == PlayerType.MPV:
		_mpv_desktop_pending_player_type = PlayerType.OFF
		activate(PlayerType.MPV)


func _on_mpv_bridge_install_cancel_pressed() -> void:
	$MPVBridgeDesktopSplash.hide()
	_mpv_desktop_pending_player_type = PlayerType.OFF
	$Main/PlayerSelection.select(PlayerType.OFF)
	player_type = PlayerType.OFF
	owner.user_settings.set_value('video_player', 'player_type', PlayerType.OFF)
	deactivate()


func _on_back_pressed() -> void:
	if $Help/VLCSetupInstructions.visible:
		$Help/VLCSetupInstructions.hide()
		$Help/VLCInfo.show()
		return
	if $Help/MPCSetupInstructions.visible:
		$Help/MPCSetupInstructions.hide()
		$Help/MPCInfo.show()
		return
	if $Help.visible:
		$Help.hide()
		$Main.show()
		return
	hide()


func _on_help_button_pressed() -> void:
	$Main.hide()
	$Help/VLCInfo.hide()
	$Help/MPCInfo.hide()
	$Help/mpvInfo.hide()
	$Help/mpvAndroidInfo.hide()
	$Help/VLCSetupInstructions.hide()
	$Help/MPCSetupInstructions.hide()
	$Help/mpvRestartReminder.hide()
	match player_type:
		PlayerType.VLC:
			$Help/VLCInfo.show()
		PlayerType.MPC:
			$Help/MPCInfo.show()
		PlayerType.MPV:
			$Help/mpvInfo.show()
		PlayerType.MPV_ANDROID:
			$Help/mpvAndroidInfo.show()
	$Help.show()


func _on_reinstall_lua_scripts_pressed() -> void:
	var err := MPVBridgeInstaller.install(player_port)
	if err != OK:
		printerr("MPV bridge reinstall failed: %s" % error_string(err))
		return
	$Help/mpvRestartReminder.show()


func _on_open_mpv_directory_pressed() -> void:
	MPVBridgeInstaller.open_mpv_folder()


func _on_reinstall_mpv_android_lua_pressed() -> void:
	if not _mpv_android_install_lua():
		return
	$Help/mpvRestartReminder.show()


func _on_vlc_setup_instructions_pressed() -> void:
	$Help/VLCInfo.hide()
	$Help/mpvRestartReminder.hide()
	$Help/VLCSetupInstructions.show()


func _on_mpc_setup_instructions_pressed() -> void:
	$Help/MPCInfo.hide()
	$Help/mpvRestartReminder.hide()
	$Help/MPCSetupInstructions.show()
