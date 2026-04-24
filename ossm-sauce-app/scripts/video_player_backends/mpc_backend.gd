extends RefCounted

var player
var http_backend


func setup(player_owner, http_owner):
	player = player_owner
	http_backend = http_owner


func send_play():
	player._command_http.request(http_backend.base_url() + "/command.html?wm_command=887")


func send_pause():
	player._command_http.request(http_backend.base_url() + "/command.html?wm_command=888")


func send_seek(time_seconds: float):
	var total_ms = int(time_seconds * 1000)
	var h = total_ms / 3600000
	var m = (total_ms % 3600000) / 60000
	var s = (total_ms % 60000) / 1000
	var ms = total_ms % 1000
	player._command_http.request(
		http_backend.base_url() + "/command.html?wm_command=-1&position=" + "%02d:%02d:%02d.%03d" % [h, m, s, ms])


func poll_status():
	player._poll_http.request(http_backend.base_url() + "/variables.html")


func on_poll_completed(body: PackedByteArray):
	parse_status(body)


func parse_status(body: PackedByteArray):
	var html = body.get_string_from_utf8()
	var state_match = player._mpc_state_regex.search(html)
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
	var pos_match = player._mpc_pos_regex.search(html)
	if pos_match:
		time_sec = float(pos_match.get_string(1)) / 1000.0
	var dur_match = player._mpc_dur_regex.search(html)
	if dur_match:
		duration_sec = float(dur_match.get_string(1)) / 1000.0
	http_backend.process_state(state, time_sec, duration_sec)
