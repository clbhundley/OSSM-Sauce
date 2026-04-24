extends Control

var app_version_number: String = ProjectSettings.get_setting("application/config/version")

var storage_dir: String
var paths_dir: String
var playlists_dir: String
var cfg_path: String

const ANIM_TIME = 0.65

var user_settings := ConfigFile.new()

var ticks_per_second: int

var path_speed: int = 30

var paused := true
var _seek_dragging := false

var active_path_index

var paths: Array
var marker_frames: Array
var network_paths: Array

var frame: int
var buffer_sent: int
var play_offset_ms: int

var max_speed: int
var max_acceleration: int
var motor_direction: int = 0

var min_stroke_duration: float
var max_stroke_duration: float

signal homing_complete

const SettingsManagerScript = preload("res://scripts/ossm_sauce_parts/settings_manager.gd")
const PathManagerScript = preload("res://scripts/ossm_sauce_parts/path_manager.gd")
const PlaybackManagerScript = preload("res://scripts/ossm_sauce_parts/playback_manager.gd")
const MoveRuntimeScript = preload("res://scripts/ossm_sauce_parts/move_runtime.gd")
const VideoSyncControllerScript = preload("res://scripts/ossm_sauce_parts/video_sync_controller.gd")
const PlaylistManagerScript = preload("res://scripts/ossm_sauce_parts/playlist_manager.gd")

var _settings_manager = SettingsManagerScript.new()
var _path_manager = PathManagerScript.new()
var _playback_manager = PlaybackManagerScript.new()
var _move_runtime = MoveRuntimeScript.new()
var _video_sync_controller = VideoSyncControllerScript.new()
var _playlist_manager = PlaylistManagerScript.new()

@onready var PATH_TOP = $PathDisplay/PathArea.position.y
@onready var PATH_BOTTOM = PATH_TOP + $PathDisplay/PathArea.size.y


func _init():
	max_speed = 25000
	max_acceleration = 500000


func _ready():
	_settings_manager.setup(self)
	_path_manager.setup(self)
	_playback_manager.setup(self)
	_move_runtime.setup(self)
	_video_sync_controller.setup(self)
	_playlist_manager.setup(self)

	set_process(false)
	OS.request_permissions()

	var physics_ticks = "physics/common/physics_ticks_per_second"
	ticks_per_second = ProjectSettings.get_setting(physics_ticks)

	min_stroke_duration = $Menu/LoopSettings/MinStrokeDuration/Input.value
	max_stroke_duration = $Menu/LoopSettings/MaxStrokeDuration/Input.value

	if OS.get_name() == 'Android':
		storage_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	else:
		storage_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	paths_dir = storage_dir + "/OSSM Sauce/Paths/"
	playlists_dir = storage_dir + "/OSSM Sauce/Playlists/"
	cfg_path = storage_dir + "/OSSM Sauce/UserSettings.cfg"

	for node in [$Menu, $Settings, $SpeedPanel, $RangePanel]:
		node.self_modulate.a = 1.65

	$PathDisplay/Ball.position.x = $PathDisplay/PathArea.size.x / 2

	check_root_directory()

	user_settings.load(cfg_path)
	apply_user_settings()

	$Menu/VersionLabel.text = "v" + app_version_number
	%WebSocket.start_server()

	%VideoPlayer.player_played.connect(_video_sync_controller.on_video_player_played)
	%VideoPlayer.player_paused.connect(_video_sync_controller.on_video_player_paused)
	%VideoPlayer.player_seeked.connect(_video_sync_controller.on_video_player_seeked)

	if OS.get_name() != 'Android':
		var window_size = get_viewport().size
		var screen_size = DisplayServer.screen_get_size()
		var centered_position = Vector2(
			(screen_size.x - window_size.x) / 2,
			(screen_size.y - window_size.y) / 2)
		DisplayServer.window_set_position(centered_position)
		get_viewport().size_changed.connect(_on_window_size_changed)


var marker_index: int
func _physics_process(delta) -> void:
	_move_runtime.physics_process(delta)


func transition_to_path(next_index: int):
	await _playback_manager.transition_to_path(next_index)


func send_command(value: int):
	_move_runtime.send_command(value)


func home_to(target_position: int):
	_move_runtime.home_to(target_position)


func play():
	_move_runtime.play()


func pause():
	await _move_runtime.pause()


func check_root_directory():
	_settings_manager.check_root_directory()


func apply_user_settings():
	_settings_manager.apply_user_settings()


func apply_device_settings():
	_settings_manager.apply_device_settings()


func create_move_command(ms_timing: int, depth: float, trans: int, ease: int, auxiliary: int):
	return _path_manager.create_move_command(ms_timing, depth, trans, ease, auxiliary)


func round_to(value: float, decimals: int) -> float:
	return _path_manager.round_to(value, decimals)


func load_path(file_name: String) -> bool:
	return _path_manager.load_path(file_name)


func create_delay(duration: float):
	_path_manager.create_delay(duration)


func move_selected_playlist_item(delta: int):
	_playlist_manager.move_selected(delta)


func delete_selected_playlist_item():
	_playlist_manager.delete_selected_item()


func add_path_file(file_name: String) -> bool:
	return _playlist_manager.add_path_file(file_name)


func load_playlist_file(file_name: String):
	_playlist_manager.load_playlist_file(file_name)


func save_playlist(filename: String):
	_playlist_manager.save_playlist(filename)


func clear_playlist():
	_playlist_manager.clear_playlist()


func display_active_path_index(pause := true, send_buffer := true):
	await _playback_manager.display_active_path_index(pause, send_buffer)


func seek() -> void:
	await _playback_manager.seek()


func _on_seek_slider_drag_started() -> void:
	_seek_dragging = true


func _on_seek_slider_value_changed(value: float) -> void:
	if active_path_index == null:
		return
	var total_frames: int = paths[active_path_index].size()
	var total_sec := (total_frames - 1) / ticks_per_second
	var current_sec := int(value * total_sec)
	if total_sec >= 3600:
		$TimeDisplay.text = "%d:%02d:%02d / %d:%02d:%02d" % [
			current_sec / 3600, current_sec % 3600 / 60, current_sec % 60,
			total_sec / 3600, total_sec % 3600 / 60, total_sec % 60]
	else:
		$TimeDisplay.text = "%d:%02d / %d:%02d" % [
			current_sec / 60, current_sec % 60,
			total_sec / 60, total_sec % 60]


func update_time_display():
	_playback_manager.update_time_display()


func render_depth(depth) -> float:
	return _playback_manager.render_depth(depth)


func activate_move_mode():
	_move_runtime.activate_move_mode()


func deactivate_move_mode():
	_move_runtime.deactivate_move_mode()


func _input(event: InputEvent) -> void:
	var pressed = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if not pressed:
		return
	for spin_box in get_tree().get_nodes_in_group("spinboxes"):
		var line_edit: LineEdit = spin_box.get_line_edit()
		if not line_edit.has_focus():
			continue
		if not spin_box.get_global_rect().has_point(event.position):
			line_edit.release_focus()
	for line_edit in get_tree().get_nodes_in_group("lineedits"):
		if not line_edit.has_focus():
			continue
		if not line_edit.get_global_rect().has_point(event.position):
			line_edit.text_submitted.emit(line_edit.text)
			line_edit.release_focus()


func _on_window_size_changed():
	if OS.get_name() != "Android":
		var window_size = DisplayServer.window_get_size()
		user_settings.set_value('window', 'size', window_size)


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		exit()


func exit():
	user_settings.save(cfg_path)
	%BPIOBridge.stop_client()
	%BPIOBridge.stop_device()
	%XToysBridge.stop_xtoys()
	if %WebSocket.ossm_connected:
		paused = true
		send_command(OSSM.Command.PAUSE)
		const MIN_RANGE = 0
		const MAX_RANGE = 1
		var command: PackedByteArray
		command.resize(4)
		command.encode_u8(0, OSSM.Command.SET_RANGE_LIMIT)
		command.encode_u8(1, MIN_RANGE if motor_direction == 0 else MAX_RANGE)
		command.encode_u16(2, motor_direction * 10000)
		%WebSocket.server.broadcast_binary(command)
		home_to(1500)
