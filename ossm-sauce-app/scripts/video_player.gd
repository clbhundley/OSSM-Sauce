extends Panel

enum PlayerType { OFF, VLC, MPC_HC }

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


func _ready():
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
	if type != PlayerType.OFF:
		_poll_timer.start()


func deactivate():
	player_type = PlayerType.OFF
	_poll_timer.stop()
	_delay_timer.stop()
	_cooldown_timer.stop()
	_poll_http.cancel_request()
	_command_http.cancel_request()
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
		PlayerType.MPC_HC:
			_command_http.request(_base_url() + "/command.html?wm_command=887")


func _send_pause():
	_command_http.cancel_request()
	match player_type:
		PlayerType.VLC:
			_command_http.request(
				_base_url() + "/requests/status.json?command=pl_forcepause",
				_vlc_headers())
		PlayerType.MPC_HC:
			_command_http.request(_base_url() + "/command.html?wm_command=888")


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
		PlayerType.MPC_HC:
			var total_ms = int(time_seconds * 1000)
			var h = total_ms / 3600000
			var m = (total_ms % 3600000) / 60000
			var s = (total_ms % 60000) / 1000
			var ms = total_ms % 1000
			_command_http.request(
				_base_url() + "/command.html?wm_command=-1&position=" \
				+ "%02d:%02d:%02d.%03d" % [h, m, s, ms])


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
	if player_type == PlayerType.OFF or _poll_in_flight:
		return
	_poll_in_flight = true
	match player_type:
		PlayerType.VLC:
			_poll_http.request(_base_url() + "/requests/status.json", _vlc_headers())
		PlayerType.MPC_HC:
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
		PlayerType.MPC_HC:
			_parse_mpc(body)


# ---- Response Parsing ----

func _parse_vlc(body: PackedByteArray):
	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json is Dictionary:
		return
	var length = float(json.get("length", 0))
	var position = float(json.get("position", 0))
	_process_state(
		json.get("state", "stopped"),
		position * length,
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


func _start_cooldown():
	_cooldown = true
	_cooldown_timer.start()


func reconnect(_player_type: PlayerType) -> void:
	deactivate()
	if _player_type > 0:
		activate(_player_type)


func _on_player_selection_item_selected(index: int) -> void:
	player_type = index as PlayerType
	match player_type:
		PlayerType.OFF:
			deactivate()
		PlayerType.VLC:
			player_port = owner.user_settings.get_value('video_player', 'vlc_port', 8080)
			$VBox/PlayerPort/Input.set_value_no_signal(player_port)
			delay_ms = owner.user_settings.get_value('video_player', 'vlc_delay_ms', 0)
			$VBox/DelayMs/Input.value = delay_ms
			advance_ms = owner.user_settings.get_value('video_player', 'vlc_advance_ms', 100)
			$VBox/AdvanceMs/Input.value = advance_ms
			activate(player_type)
		PlayerType.MPC_HC:
			player_port = owner.user_settings.get_value('video_player', 'mpc_port', 13579)
			$VBox/PlayerPort/Input.set_value_no_signal(player_port)
			delay_ms = owner.user_settings.get_value('video_player', 'mpc_delay_ms', 0)
			$VBox/DelayMs/Input.value = delay_ms
			advance_ms = owner.user_settings.get_value('video_player', 'mpc_advance_ms', 100)
			$VBox/AdvanceMs/Input.value = advance_ms
			activate(player_type)
	owner.user_settings.set_value('video_player', 'player_type', index)


func _on_player_address_text_submitted(new_text: String) -> void:
	player_address = new_text
	owner.user_settings.set_value('video_player', 'player_address', new_text)
	reconnect(player_type)


func _on_player_port_value_changed(value: float) -> void:
	player_port = int(value)
	match player_type:
		PlayerType.VLC:
			owner.user_settings.set_value('video_player', 'vlc_port', player_port)
		PlayerType.MPC_HC:
			owner.user_settings.set_value('video_player', 'mpc_port', player_port)
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
		PlayerType.MPC_HC:
			owner.user_settings.set_value('video_player', 'mpc_delay_ms', delay_ms)


func _on_advance_ms_value_changed(value: float) -> void:
	advance_ms = int(value)
	match player_type:
		PlayerType.VLC:
			owner.user_settings.set_value('video_player', 'vlc_advance_ms', advance_ms)
		PlayerType.MPC_HC:
			owner.user_settings.set_value('video_player', 'mpc_advance_ms', advance_ms)


func _on_video_offset_ms_value_changed(value: float) -> void:
	video_offset_ms = int(value)
	owner.user_settings.set_value('video_player', 'video_offset_ms', video_offset_ms)


func _on_vlc_seek_correction_value_changed(value: float) -> void:
	vlc_seek_correction = value
	owner.user_settings.set_value('video_player', 'vlc_seek_correction', vlc_seek_correction)


func _on_back_pressed() -> void:
	hide()
