extends RefCounted

const VlcBackendScript = preload("res://scripts/video_player_backends/vlc_backend.gd")
const MpcBackendScript = preload("res://scripts/video_player_backends/mpc_backend.gd")

var player
var _vlc_backend = VlcBackendScript.new()
var _mpc_backend = MpcBackendScript.new()


func setup(player_owner):
	player = player_owner
	_vlc_backend.setup(player, self)
	_mpc_backend.setup(player, self)


func base_url() -> String:
	return "http://" + player.player_address + ":" + str(player.player_port)


func vlc_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Basic " + Marshalls.utf8_to_base64(":" + player.vlc_password)
	])


func send_play():
	if player.player_type == player.PlayerType.MPV:
		player._mpv_backend.send_play()
		return
	player._command_http.cancel_request()
	match player.player_type:
		player.PlayerType.VLC:
			_vlc_backend.send_play()
		player.PlayerType.MPC_HC:
			_mpc_backend.send_play()


func send_pause():
	if player.player_type == player.PlayerType.MPV:
		player._mpv_backend.send_pause()
		return
	player._command_http.cancel_request()
	match player.player_type:
		player.PlayerType.VLC:
			_vlc_backend.send_pause()
		player.PlayerType.MPC_HC:
			_mpc_backend.send_pause()


func send_seek(time_seconds: float):
	if player.player_type == player.PlayerType.MPV:
		player._mpv_backend.send_seek(time_seconds)
		return
	player._command_http.cancel_request()
	match player.player_type:
		player.PlayerType.VLC:
			_vlc_backend.send_seek(time_seconds)
		player.PlayerType.MPC_HC:
			_mpc_backend.send_seek(time_seconds)


func on_command_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		player._seek_after_pause = -1.0
		return
	match player.player_type:
		player.PlayerType.VLC:
			_vlc_backend.on_command_completed(body)
	if player._seek_after_pause >= 0.0:
		var time = player._seek_after_pause
		player._seek_after_pause = -1.0
		await player.get_tree().create_timer(0.1).timeout
		send_seek(time)


func poll_status():
	if player.player_type == player.PlayerType.OFF or player.player_type == player.PlayerType.MPV or player._poll_in_flight:
		return
	player._poll_in_flight = true
	match player.player_type:
		player.PlayerType.VLC:
			_vlc_backend.poll_status()
		player.PlayerType.MPC_HC:
			_mpc_backend.poll_status()


func on_poll_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	player._poll_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if player.connected:
			player.connected = false
			player.player_state = "stopped"
			player.connection_changed.emit(false)
			player.player_paused.emit()
		return
	if not player.connected:
		player.connected = true
		player.connection_changed.emit(true)
	match player.player_type:
		player.PlayerType.VLC:
			_vlc_backend.on_poll_completed(body)
		player.PlayerType.MPC_HC:
			_mpc_backend.on_poll_completed(body)


func parse_vlc(body: PackedByteArray):
	_vlc_backend.parse_status(body)


func parse_mpc(body: PackedByteArray):
	_mpc_backend.parse_status(body)


func process_state(new_state: String, new_time: float, new_duration: float):
	var old_state = player.player_state
	var old_time = player.player_time
	player.player_state = new_state
	player.player_time = new_time
	player.player_duration = new_duration
	if player._cooldown:
		return
	if new_state != old_state:
		match new_state:
			"playing":
				var adjusted = new_time - player.video_offset_ms / 1000.0 + player.delay_ms / 1000.0 + player.advance_ms / 1000.0
				player.player_played.emit(maxf(adjusted, 0.0), old_state == "stopped")
			"paused", "stopped":
				player.player_paused.emit()
	elif abs(new_time - old_time) > 1.5:
		var adjusted = new_time - player.video_offset_ms / 1000.0 + player.delay_ms / 1000.0
		player.player_seeked.emit(maxf(adjusted, 0.0))
