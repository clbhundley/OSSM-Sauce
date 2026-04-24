extends Panel

const MpvBackendScript = preload("res://scripts/video_player_backends/mpv_backend.gd")
const HttpBackendScript = preload("res://scripts/video_player_backends/http_backend.gd")
const SettingsControllerScript = preload("res://scripts/video_player_parts/settings_controller.gd")

enum PlayerType { OFF, VLC, MPC_HC, MPV }

# Configuration — set these from your UI
var player_type: PlayerType = PlayerType.OFF
var player_address: String = "127.0.0.1"
var player_port: int = 8080
var vlc_password: String = ""
var delay_ms: int = 0
var advance_ms: int = 100
var video_offset_ms: int = 0
var vlc_seek_correction: float = 0.0

# MPV bridge config (desktop only — Android uses Shizuku directly)
var mpv_bridge_port: int = 9876

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

# MPV reconnect lifecycle (backend owns MPV session state)
var _mpv_reconnect_timer: Timer

var _mpv_backend = MpvBackendScript.new()
var _http_backend = HttpBackendScript.new()
var _settings_controller = SettingsControllerScript.new()


func _ready():
	_mpv_backend.setup(self)
	_http_backend.setup(self)
	_settings_controller.setup(self)

	self_modulate.a = 2

	connection_changed.connect(func(is_connected: bool):
			if is_connected:
				$VBox/ConnectionIndicator.show()
			else:
				$VBox/ConnectionIndicator.hide())

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
	_poll_timer.wait_time = 1.0  # 1hz for VLC/MPC
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

	_mpv_reconnect_timer = Timer.new()
	_mpv_reconnect_timer.name = "MpvReconnectTimer"
	_mpv_reconnect_timer.one_shot = true
	_mpv_reconnect_timer.wait_time = 3.0
	add_child(_mpv_reconnect_timer)
	_mpv_reconnect_timer.timeout.connect(_mpv_try_connect)

	_mpc_state_regex = RegEx.new()
	_mpc_state_regex.compile('<p id="state">(\\d+)</p>')
	_mpc_pos_regex = RegEx.new()
	_mpc_pos_regex.compile('<p id="position">(\\d+)</p>')
	_mpc_dur_regex = RegEx.new()
	_mpc_dur_regex.compile('<p id="duration">(\\d+)</p>')


func _process(_delta: float):
	_mpv_backend.process()


func is_active() -> bool:
	return player_type != PlayerType.OFF


func activate(type: PlayerType):
	deactivate()
	player_type = type
	if type == PlayerType.MPV:
		_mpv_try_connect()
	elif type != PlayerType.OFF:
		_poll_timer.start()


func deactivate():
	player_type = PlayerType.OFF
	_poll_timer.stop()
	_delay_timer.stop()
	_cooldown_timer.stop()
	if _mpv_reconnect_timer:
		_mpv_reconnect_timer.stop()
	_poll_http.cancel_request()
	_command_http.cancel_request()
	_poll_in_flight = false
	_cooldown = false
	_pending_action = ""
	player_state = "stopped"
	player_time = 0.0
	player_duration = 0.0
	_mpv_disconnect()
	if connected:
		connected = false
		connection_changed.emit(false)


# ---- MPV Connection ----

func _mpv_try_connect():
	_mpv_backend.try_connect()


func _mpv_try_connect_shizuku():
	_mpv_backend.try_connect_shizuku()


func _mpv_try_connect_tcp():
	_mpv_backend.try_connect_tcp()


func _mpv_disconnect():
	_mpv_backend.disconnect_backend()


func _mpv_handle_disconnect():
	_mpv_backend.handle_disconnect()


# ---- MPV Send ----

func _mpv_send(json: String):
	_mpv_backend.send(json)


func _send_observe_commands():
	await _mpv_backend.send_observe_commands()


# ---- MPV Receive ----

func _on_mpv_line_received(line: String):
	_mpv_backend.on_line_received(line)


func _parse_mpv_buffer():
	_mpv_backend.parse_buffer()


func _handle_mpv_message(msg: Dictionary):
	_mpv_backend.handle_message(msg)


# MPV state processor — bypasses cooldown (cooldown is for VLC/MPC polling only)
func _process_mpv_event(new_state: String, new_time: float):
	_mpv_backend.process_event(new_state, new_time)


# ---- MPV Commands ----

func _mpv_send_play():
	_mpv_backend.send_play()


func _mpv_send_pause():
	_mpv_backend.send_pause()


func _mpv_send_seek(time_seconds: float):
	_mpv_backend.send_seek(time_seconds)


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
	_seek_after_pause = _path_to_video_time(path_time_seconds)
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


# ---- HTTP / IPC Dispatch ----

func _path_to_video_time(path_time_seconds: float) -> float:
	var video_time = path_time_seconds - delay_ms / 1000.0 + video_offset_ms / 1000.0
	if player_type == PlayerType.VLC and vlc_seek_correction != 0:
		video_time -= vlc_seek_correction * video_time / 60.0 / 1000.0
	return maxf(video_time, 0.0)


func _base_url() -> String:
	return _http_backend.base_url()


func _vlc_headers() -> PackedStringArray:
	return _http_backend.vlc_headers()


func _send_play():
	_http_backend.send_play()


func _send_pause():
	_http_backend.send_pause()


func _send_seek(time_seconds: float):
	_http_backend.send_seek(time_seconds)


func _on_command_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	await _http_backend.on_command_completed(result, response_code, _headers, body)


# ---- Polling (VLC / MPC only) ----

func _poll_status():
	_http_backend.poll_status()


func _on_poll_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	_http_backend.on_poll_completed(result, response_code, _headers, body)


# ---- Response Parsing ----

func _parse_vlc(body: PackedByteArray):
	_http_backend.parse_vlc(body)


func _parse_mpc(body: PackedByteArray):
	_http_backend.parse_mpc(body)


func _process_state(new_state: String, new_time: float, new_duration: float):
	_http_backend.process_state(new_state, new_time, new_duration)


func _start_cooldown():
	_cooldown = true
	_cooldown_timer.start()


func reconnect(_player_type: PlayerType) -> void:
	_settings_controller.reconnect(_player_type)


func _on_player_selection_item_selected(index: int) -> void:
	_settings_controller.apply_player_selection(index)


func _on_player_address_text_submitted(new_text: String) -> void:
	_settings_controller.set_player_address(new_text)


func _on_player_port_value_changed(value: float) -> void:
	_settings_controller.set_player_port(value)


func _on_vlc_password_text_submitted(new_text: String) -> void:
	_settings_controller.set_vlc_password(new_text)


func _on_delay_ms_value_changed(value: float) -> void:
	_settings_controller.set_delay_ms(value)


func _on_advance_ms_value_changed(value: float) -> void:
	_settings_controller.set_advance_ms(value)


func _on_video_offset_ms_value_changed(value: float) -> void:
	_settings_controller.set_video_offset_ms(value)


func _on_vlc_seek_correction_value_changed(value: float) -> void:
	_settings_controller.set_vlc_seek_correction(value)


func _on_back_pressed() -> void:
	hide()
