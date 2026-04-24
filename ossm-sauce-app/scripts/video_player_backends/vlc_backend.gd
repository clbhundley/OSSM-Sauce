extends RefCounted

var player
var http_backend


func setup(player_owner, http_owner):
	player = player_owner
	http_backend = http_owner


func send_play():
	player._command_http.request(
		http_backend.base_url() + "/requests/status.json?command=pl_forceresume",
		http_backend.vlc_headers())


func send_pause():
	player._command_http.request(
		http_backend.base_url() + "/requests/status.json?command=pl_forcepause",
		http_backend.vlc_headers())


func send_seek(time_seconds: float):
	var pct = "0"
	if player.player_duration > 0.0:
		pct = "%f" % (time_seconds / player.player_duration * 100.0)
	player._command_http.request(
		http_backend.base_url() + "/requests/status.json?command=seek&val=" + pct + "%25",
		http_backend.vlc_headers())


func poll_status():
	player._poll_http.request(http_backend.base_url() + "/requests/status.json", http_backend.vlc_headers())


func on_command_completed(body: PackedByteArray):
	parse_status(body)


func on_poll_completed(body: PackedByteArray):
	parse_status(body)


func parse_status(body: PackedByteArray):
	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json is Dictionary:
		return
	var length = float(json.get("length", 0))
	var position = float(json.get("position", 0))
	http_backend.process_state(json.get("state", "stopped"), position * length, length)
