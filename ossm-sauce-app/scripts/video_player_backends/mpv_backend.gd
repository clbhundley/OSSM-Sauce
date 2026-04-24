extends RefCounted

var player
var _mpv_shizuku = null
var _mpv_socket: StreamPeerTCP = null
var _mpv_buffer: String = ""
var _mpv_observed: bool = false
var _mpv_initial_sync: bool = true
var _manual_seek_occurred: bool = false
var _mpv_seek_in_flight: bool = false


func setup(player_owner):
	player = player_owner


func process():
	if player.player_type != player.PlayerType.MPV:
		return

	if OS.get_name() == "Android":
		if _mpv_shizuku != null:
			_mpv_shizuku.poll()
		return

	if _mpv_socket == null:
		return

	var status = _mpv_socket.get_status()

	if status == StreamPeerTCP.STATUS_CONNECTING:
		_mpv_socket.poll()
		return

	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not _mpv_observed:
			_mpv_observed = true
			player.connected = true
			player.connection_changed.emit(true)
			print("[mpv] connected via TCP bridge, scheduling observe commands")
			send_observe_commands()

		_mpv_socket.poll()
		var available = _mpv_socket.get_available_bytes()
		if available > 0:
			_mpv_buffer += _mpv_socket.get_utf8_string(available)
			parse_buffer()

	elif status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		handle_disconnect()


func try_connect():
	if player.player_type != player.PlayerType.MPV:
		return
	disconnect_backend()
	_mpv_initial_sync = true
	_manual_seek_occurred = false
	_mpv_seek_in_flight = false

	if OS.get_name() == "Android":
		try_connect_shizuku()
	else:
		try_connect_tcp()


func try_connect_shizuku():
	var ShizukuBridge = load("res://scripts/mpv_shizuku.gd")
	if ShizukuBridge == null:
		push_error("[mpv] mpv_shizuku.gd not found")
		player._mpv_reconnect_timer.start()
		return

	_mpv_shizuku = ShizukuBridge.new()

	if not _mpv_shizuku.is_shizuku_available():
		push_error("[mpv] Shizuku not installed or not running")
		player._mpv_reconnect_timer.start()
		return

	if not _mpv_shizuku.has_permission():
		print("[mpv] requesting Shizuku permission...")
		_mpv_shizuku.request_permission()
		player._mpv_reconnect_timer.start()
		return

	if not _mpv_shizuku.connect_mpv():
		push_error("[mpv] Shizuku connect failed")
		_mpv_shizuku = null
		player._mpv_reconnect_timer.start()
		return

	_mpv_shizuku.line_received.connect(on_line_received)
	_mpv_shizuku.connection_lost.connect(handle_disconnect)

	_mpv_observed = true
	player.connected = true
	player.connection_changed.emit(true)
	print("[mpv] Shizuku connected, scheduling observe commands")
	send_observe_commands()


func try_connect_tcp():
	print("[mpv] connecting to TCP bridge on port ", player.mpv_bridge_port)
	_mpv_socket = StreamPeerTCP.new()
	_mpv_socket.connect_to_host("127.0.0.1", player.mpv_bridge_port)


func disconnect_backend():
	if _mpv_shizuku != null:
		_mpv_shizuku.close_mpv()
		_mpv_shizuku = null
	if _mpv_socket != null:
		_mpv_socket.disconnect_from_host()
		_mpv_socket = null
	_mpv_buffer = ""
	_mpv_observed = false
	_mpv_initial_sync = true
	_mpv_seek_in_flight = false


func handle_disconnect():
	disconnect_backend()
	if player.connected:
		player.connected = false
		player.player_state = "stopped"
		player.connection_changed.emit(false)
		player.player_paused.emit()
	if player.player_type == player.PlayerType.MPV:
		player._mpv_reconnect_timer.start()


func send(json: String):
	if OS.get_name() == "Android":
		if _mpv_shizuku != null:
			_mpv_shizuku.send(json)
	else:
		if _mpv_socket != null and _mpv_socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_mpv_socket.put_data((json + "\n").to_utf8_buffer())


func send_observe_commands():
	await player.get_tree().create_timer(0.3).timeout
	print("[mpv] sending observe commands")
	send('{"command":["observe_property",1,"pause"]}')
	send('{"command":["observe_property",2,"seeking"]}')
	send('{"command":["observe_property",3,"time-pos"]}')
	send('{"command":["get_property","duration"],"request_id":98}')


func on_line_received(line: String):
	var json = JSON.parse_string(line)
	if json is Dictionary:
		handle_message(json)


func parse_buffer():
	while "\n" in _mpv_buffer:
		var idx = _mpv_buffer.find("\n")
		var line = _mpv_buffer.left(idx).strip_edges()
		_mpv_buffer = _mpv_buffer.substr(idx + 1)
		print("[mpv] raw: ", line)
		if line.is_empty():
			continue
		var json = JSON.parse_string(line)
		if not json is Dictionary:
			continue
		handle_message(json)


func handle_message(msg: Dictionary):
	var event = msg.get("event", "")
	var request_id = msg.get("request_id", -1)

	if _mpv_seek_in_flight and event != "":
		var prop_id = int(msg.get("id", -1))
		var is_pause_event = (event == "property-change" and prop_id == 1)
		if event == "playback-restart":
			_mpv_seek_in_flight = false
			print("[mpv] seek complete")
			return
		elif not is_pause_event:
			return

	if event == "property-change":
		var prop_id = int(msg.get("id", -1))
		match prop_id:
			1:
				var is_paused = msg.get("data", false)
				print("[mpv] pause=", is_paused)
				if is_paused:
					process_event("paused", player.player_time)
			2:
				pass
			3:
				var t = msg.get("data")
				if t == null:
					return
				if _mpv_initial_sync:
					_mpv_initial_sync = false
					player.player_time = float(t)
					player.player_state = "playing"
					print("[mpv] initial sync t=", t)
					return
				process_event("playing", float(t))

	elif event == "seek":
		print("[mpv] seek event")
		_manual_seek_occurred = true

	elif event == "end-file" or event == "idle":
		process_event("stopped", 0.0)

	elif request_id == 98:
		if msg.get("error", "") == "success" and msg.get("data") != null:
			player.player_duration = float(msg.get("data", 0.0))
			print("[mpv] duration=", player.player_duration)


func process_event(new_state: String, new_time: float):
	var old_state = player.player_state
	var old_time = player.player_time
	player.player_state = new_state
	player.player_time = new_time

	print("[mpv] state: ", new_state, " t=", new_time, " old=", old_state, " seek=", _manual_seek_occurred)

	if new_state != old_state:
		match new_state:
			"playing":
				var adjusted = new_time - player.video_offset_ms / 1000.0 + player.delay_ms / 1000.0 + player.advance_ms / 1000.0
				print("[mpv] emit player_played")
				player.player_played.emit(maxf(adjusted, 0.0), old_state == "stopped")
			"paused", "stopped":
				print("[mpv] emit player_paused")
				player.player_paused.emit()
	elif _manual_seek_occurred:
		_manual_seek_occurred = false
		var adjusted = new_time - player.video_offset_ms / 1000.0 + player.delay_ms / 1000.0
		print("[mpv] emit player_seeked (seek flag)")
		player.player_seeked.emit(maxf(adjusted, 0.0))
	elif abs(new_time - old_time) > 1.5:
		var adjusted = new_time - player.video_offset_ms / 1000.0 + player.delay_ms / 1000.0
		print("[mpv] emit player_seeked (time jump)")
		player.player_seeked.emit(maxf(adjusted, 0.0))


func send_play():
	send('{"command":["set_property","pause",false]}')


func send_pause():
	send('{"command":["set_property","pause",true]}')


func send_seek(time_seconds: float):
	_mpv_seek_in_flight = true
	_manual_seek_occurred = false
	send('{"command":["seek",%s,"absolute"]}' % str(time_seconds))

