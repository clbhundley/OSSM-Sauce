class_name MPVBridgeInstaller

# Installs the OSSM Sauce <-> MPV bridge into the user's mpv config dir.
#
# Desktop (Windows/Linux/macOS) — TCP bridge:
#   <mpv_config_dir>/scripts/ossm_bridge.lua
#   <mpv_config_dir>/script-opts/ossm_bridge.conf   (key: port=NNNN)
#
# Android install is handled separately in video_player.gd via SAF —
# mpv-android's scoped storage requires a tree URI grant, not a static path.

const BUNDLED_BRIDGE_PATH := "res://bridges/ossm_bridge.lua"
const LUA_FILENAME := "ossm_bridge.lua"
const CONF_FILENAME := "ossm_bridge.conf"


static func is_supported_platform() -> bool:
	match OS.get_name():
		"Windows", "Linux", "macOS":
			return true
		_:
			return false


static func get_mpv_config_dir() -> String:
	match OS.get_name():
		"Windows":
			var appdata := OS.get_environment("APPDATA")
			if appdata.is_empty():
				return ""
			return appdata.path_join("mpv")
		"Linux":
			var xdg := OS.get_environment("XDG_CONFIG_HOME")
			if not xdg.is_empty():
				return xdg.path_join("mpv")
			var home := OS.get_environment("HOME")
			if home.is_empty():
				return ""
			return home.path_join(".config").path_join("mpv")
		"macOS":
			var home := OS.get_environment("HOME")
			if home.is_empty():
				return ""
			return home.path_join(".config").path_join("mpv")
		_:
			return ""


static func get_scripts_dir() -> String:
	var base := get_mpv_config_dir()
	if base.is_empty():
		return ""
	return base.path_join("scripts")


static func get_script_opts_dir() -> String:
	var base := get_mpv_config_dir()
	if base.is_empty():
		return ""
	return base.path_join("script-opts")


static func get_lua_path() -> String:
	var dir := get_scripts_dir()
	if dir.is_empty():
		return ""
	return dir.path_join(LUA_FILENAME)


static func get_conf_path() -> String:
	var dir := get_script_opts_dir()
	if dir.is_empty():
		return ""
	return dir.path_join(CONF_FILENAME)


static func is_installed() -> bool:
	var path := get_lua_path()
	if path.is_empty():
		return false
	return FileAccess.file_exists(path)


static func install(port: int) -> Error:
	if not is_supported_platform():
		return ERR_UNAVAILABLE
	return _install_desktop(port)


static func update_port(port: int) -> void:
	if not is_installed():
		return
	_write_conf(port)


static func open_mpv_folder() -> void:
	var dir := get_mpv_config_dir()
	if dir.is_empty():
		return
	OS.shell_open(dir)


static func _install_desktop(port: int) -> Error:
	var lua_path := get_lua_path()
	var conf_path := get_conf_path()
	if lua_path.is_empty() or conf_path.is_empty():
		return ERR_CANT_RESOLVE
	
	var src := FileAccess.open(BUNDLED_BRIDGE_PATH, FileAccess.READ)
	if src == null:
		return FileAccess.get_open_error()
	var lua_content := src.get_as_text()
	src.close()
	
	var dir_err := _ensure_dir(get_scripts_dir())
	if dir_err != OK:
		return dir_err
	dir_err = _ensure_dir(get_script_opts_dir())
	if dir_err != OK:
		return dir_err
	
	var lua_file := FileAccess.open(lua_path, FileAccess.WRITE)
	if lua_file == null:
		return FileAccess.get_open_error()
	lua_file.store_string(lua_content)
	lua_file.close()
	
	return _write_conf(port)


static func _ensure_dir(path: String) -> Error:
	if path.is_empty():
		return ERR_CANT_RESOLVE
	if DirAccess.dir_exists_absolute(path):
		return OK
	return DirAccess.make_dir_recursive_absolute(path)


static func _write_conf(port: int) -> Error:
	var conf_path := get_conf_path()
	if conf_path.is_empty():
		return ERR_CANT_RESOLVE
	var dir_err := _ensure_dir(get_script_opts_dir())
	if dir_err != OK:
		return dir_err
	var conf_file := FileAccess.open(conf_path, FileAccess.WRITE)
	if conf_file == null:
		return FileAccess.get_open_error()
	conf_file.store_string("port=%d\n" % port)
	conf_file.close()
	return OK
