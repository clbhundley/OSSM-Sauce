extends RefCounted

# GDScript wrapper for MpvShizukuPlugin Android plugin
# Exposes the same interface as before so video_player.gd doesn't care
# whether we're using the plugin or the desktop TCP bridge

const PLUGIN_NAME = "MpvShizuku"
const SOCAT_ASSET = "res://addons/MpvShizuku/socat"  # bundled ARM64 static binary

var _plugin = null

signal line_received(line: String)
signal connection_lost


func _init():
	if Engine.has_singleton(PLUGIN_NAME):
		_plugin = Engine.get_singleton(PLUGIN_NAME)
		# Forward plugin signals to our own signals
		_plugin.connect("mpv_line_received", _on_line)
		_plugin.connect("mpv_disconnected", _on_disconnected)
	else:
		push_error("[mpv_shizuku] Plugin singleton not found — is MpvShizuku plugin enabled?")


func is_shizuku_available() -> bool:
	if _plugin == null:
		return false
	return _plugin.isShizukuAvailable()


func has_permission() -> bool:
	if _plugin == null:
		return false
	return _plugin.hasPermission()


func request_permission():
	if _plugin != null:
		_plugin.requestPermission()


func connect_mpv() -> bool:
	if _plugin == null:
		return false

	# Extract socat binary on first run
	var socat_tmp = OS.get_user_data_dir() + "/socat"
	_extract_socat_to_tmp(socat_tmp)
	if not _plugin.extractSocat(socat_tmp):
		push_error("[mpv_shizuku] socat extraction failed")
		return false

	return _plugin.connectMpv()


func send(json: String):
	if _plugin != null:
		_plugin.sendToMpv(json)


func poll():
	# No-op on Android plugin path — events arrive via signal from background thread
	# Kept for API compatibility with desktop TCP path
	pass


func close_mpv():
	if _plugin != null:
		_plugin.disconnectMpv()


func _on_line(line: String):
	line_received.emit(line)


func _on_disconnected():
	connection_lost.emit()


func _extract_socat_to_tmp(dest_path: String):
	# Only extract if not already there
	if FileAccess.file_exists(dest_path):
		return
	var asset = FileAccess.open(SOCAT_ASSET, FileAccess.READ)
	if asset == null:
		push_error("[mpv_shizuku] socat asset missing at " + SOCAT_ASSET)
		return
	var out = FileAccess.open(dest_path, FileAccess.WRITE)
	if out == null:
		push_error("[mpv_shizuku] failed to write socat to " + dest_path)
		return
	out.store_buffer(asset.get_buffer(asset.get_length()))
	out.close()
	asset.close()
	print("[mpv_shizuku] socat extracted to ", dest_path)
