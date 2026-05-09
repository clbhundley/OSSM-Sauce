extends Control

var app_version_number: String = ProjectSettings.get_setting("application/config/version")

var storage_dir: String
var paths_dir: String
var playlists_dir: String
var cfg_path: String

const SAF_CONFIG_PATH := "user://saf_storage.cfg"
var saf_storage := ConfigFile.new()
var saf_paths_uri: String = ""
var saf_mpv_bridge_uri: String = ""
var _saf_paths_subdir_exists: bool = false
var _saf_playlists_subdir_exists: bool = false
var _saf_file_subdirs: Dictionary = {}

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
var _seeking: bool

var max_speed: int
var max_acceleration: int
var motor_direction: int = 0

var min_stroke_duration: float
var max_stroke_duration: float

signal homing_complete

@onready var PATH_TOP = $PathDisplay/PathArea.position.y
@onready var PATH_BOTTOM = PATH_TOP + $PathDisplay/PathArea.size.y


func _init():
	max_speed = 25000
	max_acceleration = 500000


func _ready():
	set_process(false)
	OS.request_permissions()
	
	var physics_ticks = "physics/common/physics_ticks_per_second"
	ticks_per_second = ProjectSettings.get_setting(physics_ticks)
	
	min_stroke_duration = $Menu/LoopSettings/MinStrokeDuration/Input.value
	max_stroke_duration = $Menu/LoopSettings/MaxStrokeDuration/Input.value
	
	if OS.get_name() == 'Android':
		#storage_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
		cfg_path = "user://UserSettings.cfg"
	else:
		storage_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		cfg_path = storage_dir + "/OSSM Sauce/UserSettings.cfg"
	paths_dir = storage_dir + "/OSSM Sauce/Paths/"
	playlists_dir = storage_dir + "/OSSM Sauce/Playlists/"
	
	for node in [$Menu, $Settings, $SpeedPanel, $RangePanel]:
		node.self_modulate.a = 1.65
	
	$PathDisplay/Ball.position.x = $PathDisplay/PathArea.size.x / 2
	
	check_root_directory()
	
	user_settings.load(cfg_path)
	apply_user_settings()
	
	$Menu/VersionLabel.text = "v" + app_version_number
	%WebSocket.start_server()
	
	%VideoPlayer.player_played.connect(_on_video_player_played)
	%VideoPlayer.player_paused.connect(_on_video_player_paused)
	%VideoPlayer.player_seeked.connect(_on_video_player_seeked)
	
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
	if paused or paths[active_path_index].is_empty():
		return
	
	var total_frames: int = paths[active_path_index].size()
	if frame >= total_frames - 1:
		if active_path_index < network_paths.size() - 1:
			transition_to_path(active_path_index + 1)
		elif $Menu.loop_playlist:
			transition_to_path(0)
		else:
			paused = true
			send_command(OSSM.Command.PAUSE)
			%VideoPlayer.pause_player()
			$Menu.show_play()
			$CircleSelection.show_restart()
		return
	
	var frames = marker_frames[active_path_index]
	var active_path = network_paths[active_path_index]
	var current_marker = marker_index - buffer_sent
	if current_marker < frames.size() and frame == frames[current_marker]:
		if %WebSocket.server_started:
			if marker_index < active_path.size():
				%WebSocket.server.broadcast_binary(active_path[marker_index])
			elif active_path_index < network_paths.size() - 1:
				var overreach_index = marker_index - active_path.size()
				var next_path = network_paths[active_path_index + 1]
				if overreach_index < next_path.size():
					%WebSocket.server.broadcast_binary(next_path[overreach_index])
			elif $Menu.loop_playlist:
				var overreach_index = marker_index - active_path.size()
				var next_path = network_paths[0]
				if overreach_index < next_path.size():
					%WebSocket.server.broadcast_binary(next_path[overreach_index])
		if current_marker < frames.size() - 1:
			marker_index += 1
	
	var depth: float = paths[active_path_index][frame]
	$PathDisplay/Paths.get_child(active_path_index).position.x -= path_speed
	$PathDisplay/Ball.position.y = render_depth(depth)
	if not _seek_dragging:
		$SeekSlider.set_value_no_signal(float(frame) / (total_frames - 1))
		update_time_display()
	frame += 1


func transition_to_path(next_index: int):
	var overreach_sent = maxi(marker_index - network_paths[active_path_index].size(), 0)
	var next_path = network_paths[next_index]
	active_path_index = next_index
	display_active_path_index(false, false)
	# Top up buffer if overreach didn't cover it
	marker_index = overreach_sent
	buffer_sent = overreach_sent
	while buffer_sent < 6 and marker_index < next_path.size():
		%WebSocket.server.broadcast_binary(next_path[marker_index])
		marker_index += 1
		buffer_sent += 1
	var path_list = $Menu/Playlist/Scroll/VBox
	$Menu/Playlist._on_item_selected(path_list.get_child(next_index))
	path_list.get_child(next_index).set_active()


func send_command(value: int):
	if %WebSocket.ossm_connected:
		var command:PackedByteArray
		command.resize(1)
		command[0] = value
		%WebSocket.server.broadcast_binary(command)


func home_to(target_position: int):
	if %WebSocket.ossm_connected:
		%CircleSelection.show_hourglass()
		%ActionPanel.disable_buttons(true)
		var displays = [
			%PathDisplay,
			%PositionControls,
			%LoopControls,
			%VibrationControls,
			%BridgeControls,
			%ActionPanel,
			%VideoPlayer,
			%Settings,
			%AddFile,
			%Menu]
		for display in displays:
			display.modulate.a = 0.05
		var command: PackedByteArray
		command.resize(5)
		command.encode_u8(0, OSSM.Command.HOMING)
		command.encode_s32(1, abs(motor_direction * 10000 - target_position))
		%WebSocket.server.broadcast_binary(command)


func play():
	var command: PackedByteArray
	if AppMode.active == AppMode.MOVE and active_path_index != null:
		paused = false
		play_offset_ms = int(frame * 1000.0 / ticks_per_second)
	command.resize(6)
	command.encode_u8(0, OSSM.Command.PLAY)
	command.encode_u8(1, AppMode.active)
	command.encode_u32(2, play_offset_ms)
	if %WebSocket.ossm_connected:
		if AppMode.active == AppMode.MOVE:
			var safe_accel: PackedByteArray
			safe_accel.resize(5)
			safe_accel.encode_u8(0, OSSM.Command.SET_GLOBAL_ACCELERATION)
			safe_accel.encode_u32(1, 60000)
			%WebSocket.server.broadcast_binary(safe_accel)
		%WebSocket.server.broadcast_binary(command)
		# Restore user's acceleration after a comfortable ramp-up
		$PathDisplay/AccelTimer.start(0.8)


func pause():
	paused = true
	if not %WebSocket.ossm_connected:
		return
	send_command(OSSM.Command.PAUSE)
	
	if active_path_index == null:
		return
	if AppMode.active != AppMode.MOVE or paths[active_path_index].is_empty():
		return
	
	# Sync OSSM to current path position
	var current_depth: float = paths[active_path_index][frame]
	send_command(OSSM.Command.RESET)
	home_to(round(current_depth * 10000))
	await homing_complete
	if not %WebSocket.ossm_connected:
		return
	
	# Find cascade and buffer start for current frame
	var frames = marker_frames[active_path_index]
	var buffer_start := 0
	var cascade_index := 0
	for i in frames.size():
		if frames[i] <= frame:
			cascade_index = i
			buffer_start = i + 1
		else:
			break
	
	# Send cascade packet + buffer
	%WebSocket.server.broadcast_binary(network_paths[active_path_index][cascade_index])
	marker_index = buffer_start
	buffer_sent = 0
	while buffer_sent < 6 and marker_index < network_paths[active_path_index].size():
		%WebSocket.server.broadcast_binary(network_paths[active_path_index][marker_index])
		marker_index += 1
		buffer_sent += 1
	
	# Reduce acceleration and nudge in both directions to force direction change
	var safe_accel: PackedByteArray
	safe_accel.resize(5)
	safe_accel.encode_u8(0, OSSM.Command.SET_GLOBAL_ACCELERATION)
	safe_accel.encode_u32(1, 60000)
	%WebSocket.server.broadcast_binary(safe_accel)
	var depth_val:int = abs(motor_direction * 10000 - round(current_depth * 10000))
	var nudge: PackedByteArray
	nudge.resize(10)
	nudge.encode_u8(0, OSSM.Command.SMOOTH_MOVE)
	nudge.encode_u8(7, 0)  # TRANS_LINEAR
	nudge.encode_u8(8, 0)  # EASE_IN
	nudge.encode_u8(9, 0)
	# Nudge out
	nudge.encode_u32(1, 100)
	nudge.encode_u16(5, clampi(depth_val + 500, 0, 10000))
	%WebSocket.server.broadcast_binary(nudge)
	await get_tree().create_timer(0.15).timeout
	# Nudge in (guaranteed direction change)
	nudge.encode_u16(5, clampi(depth_val - 500, 0, 10000))
	%WebSocket.server.broadcast_binary(nudge)
	await get_tree().create_timer(0.15).timeout
	# Return to position
	nudge.encode_u16(5, clampi(depth_val, 0, 10000))
	%WebSocket.server.broadcast_binary(nudge)


func check_root_directory():
	if OS.get_name() == 'Android':
		return
	var dir = DirAccess.open(storage_dir)
	if not dir.dir_exists("OSSM Sauce"):
		dir.make_dir("OSSM Sauce")
	dir.change_dir("OSSM Sauce")
	for directory in ["Paths", "Playlists"]:
		if not dir.dir_exists(directory):
			dir.make_dir(directory)


func apply_user_settings():
	var cfg_version_number = user_settings.get_value(
			'app_settings',
			'version_number',
			"")
	
	if cfg_version_number.naturalcasecmp_to("1.5") < 0:
		user_settings.clear()
		user_settings.set_value(
				'app_settings',
				'version_number',
				app_version_number)
		user_settings.save(cfg_path)
	
	if OS.get_name() != 'Android':
		if user_settings.has_section_key('window', 'size'):
			DisplayServer.window_set_size(
					user_settings.get_value('window', 'size'))
		else:
			DisplayServer.window_set_size(Vector2(435, 774))
		
		if user_settings.has_section_key('window', 'always_on_top'):
			var checkbox = $Settings/VBox/AlwaysOnTop
			checkbox.button_pressed = user_settings.get_value(
					'window',
					'always_on_top')
		
		#if user_settings.has_section_key('window', 'transparent_background'):
			#var checkbox = $Settings/VBox/TransparentBg
			#checkbox.button_pressed = user_settings.get_value(
					#'window',
					#'transparent_background')
	
	if user_settings.get_value('app_settings', 'show_splash', true):
		$Splash.show()
	
	_check_storage_setup()
	
	if user_settings.has_section_key('network', 'port'):
		var port_number = user_settings.get_value('network', 'port')
		$Settings/VBox/Network/Port/Input.value = port_number
		%WebSocket.port = port_number
	
	if user_settings.has_section_key('device_settings', 'motor_direction'):
		var value = user_settings.get_value('device_settings', 'motor_direction', 0)
		$Settings/VBox/ReverseMotorDirection.button_pressed = bool(value)
	
	apply_device_settings()
	
	if user_settings.has_section_key('app_settings', 'smoothing_slider'):
		$PositionControls/Smoothing/HSlider.set_value(
				user_settings.get_value('app_settings', 'smoothing_slider'))
	
	if user_settings.has_section_key('stroke_settings', 'min_duration'):
		$Menu.set_min_stroke_duration(
				user_settings.get_value('stroke_settings', 'min_duration'))
	if user_settings.has_section_key('stroke_settings', 'max_duration'):
		$Menu.set_max_stroke_duration(
				user_settings.get_value('stroke_settings', 'max_duration'))
	if user_settings.has_section_key('stroke_settings', 'display_mode'):
		$Menu.set_stroke_duration_display_mode(
				user_settings.get_value('stroke_settings', 'display_mode'))
	if user_settings.has_section_key('stroke_settings', 'in_trans'):
		$LoopControls/In/AccelerationControls/Transition.select(
				user_settings.get_value('stroke_settings', 'in_trans'))
	if user_settings.has_section_key('stroke_settings', 'in_ease'):
		$LoopControls/In/AccelerationControls/Easing.select(
				user_settings.get_value('stroke_settings', 'in_ease'))
	if user_settings.has_section_key('stroke_settings', 'out_trans'):
		$LoopControls/Out/AccelerationControls/Transition.select(
				user_settings.get_value('stroke_settings', 'out_trans'))
	if user_settings.has_section_key('stroke_settings', 'out_ease'):
		$LoopControls/Out/AccelerationControls/Easing.select(
				user_settings.get_value('stroke_settings', 'out_ease'))
	$LoopControls.draw_easing()
	
	if user_settings.has_section_key('bridge_settings', 'min_move_duration') \
			or user_settings.has_section_key('bridge_settings', 'max_move_duration'):
		%BridgeControls.set_move_duration_limits(
				user_settings.get_value('bridge_settings', 'min_move_duration', 500),
				user_settings.get_value('bridge_settings', 'max_move_duration', 6000))
	if user_settings.has_section_key('bridge_settings', 'bridge_mode'):
		var bridge_mode = user_settings.get_value('bridge_settings', 'bridge_mode')
		%Menu/BridgeSettings/BridgeMode/ModeSelection.selected = bridge_mode
		$Menu._on_bridge_mode_selected(bridge_mode)
	if user_settings.has_section_key('bridge_settings', 'logging_enabled'):
		%Menu/BridgeSettings/LoggingEnabled.button_pressed = user_settings.get_value(
				'bridge_settings', 'logging_enabled')
	
	if user_settings.has_section_key('bpio_settings', 'server_address'):
		%Menu/BridgeSettings/BPIO/ServerAddress/Input.text = user_settings.get_value(
				'bpio_settings', 'server_address')
	if user_settings.has_section_key('bpio_settings', 'server_port'):
		%Menu/BridgeSettings/BPIO/Ports/ServerPort/Input.value = user_settings.get_value(
				'bpio_settings', 'server_port')
	if user_settings.has_section_key('bpio_settings', 'wsdm_port'):
		%Menu/BridgeSettings/BPIO/Ports/WSDMPort/Input.value = user_settings.get_value(
				'bpio_settings', 'wsdm_port')
	if user_settings.has_section_key('bpio_settings', 'identifier'):
		%Menu/BridgeSettings/BPIO/Identifier/Input.text = user_settings.get_value(
				'bpio_settings', 'identifier')
	if user_settings.has_section_key('bpio_settings', 'client_name'):
		%Menu/BridgeSettings/BPIO/ClientName/Input.text = user_settings.get_value(
				'bpio_settings', 'client_name')
	if user_settings.has_section_key('bpio_settings', 'address'):
		%Menu/BridgeSettings/BPIO/Address/Input.text = user_settings.get_value(
				'bpio_settings', 'address')
	
	if user_settings.has_section_key('xtoys_settings', 'port'):
		%Menu/BridgeSettings/XToys/Port/Input.value = user_settings.get_value(
				'xtoys_settings', 'port')
	if user_settings.has_section_key('xtoys_settings', 'max_msg_frequency'):
		%Menu/BridgeSettings/XToys/MaxMsgFrequency/Input.set_value_no_signal(
				user_settings.get_value('xtoys_settings', 'max_msg_frequency'))
	if user_settings.has_section_key('xtoys_settings', 'use_command_duration'):
		%Menu/BridgeSettings/XToys/UseCommandDuration.button_pressed = user_settings.get_value(
				'xtoys_settings', 'use_command_duration')
	
	if user_settings.has_section_key('video_player', 'player_address'):
		%VideoPlayer.player_address = user_settings.get_value('video_player', 'player_address')
		%VideoPlayer/Main/PlayerAddress/Input.text = %VideoPlayer.player_address
	if user_settings.has_section_key('video_player', 'vlc_password'):
		%VideoPlayer.vlc_password = user_settings.get_value('video_player', 'vlc_password')
		%VideoPlayer/Main/VLCPassword/Input.text = %VideoPlayer.vlc_password
	if user_settings.has_section_key('video_player', 'video_offset_ms'):
		%VideoPlayer/Main/VideoOffset/Input.value = user_settings.get_value('video_player', 'video_offset_ms')
	if user_settings.has_section_key('video_player', 'vlc_seek_correction'):
		%VideoPlayer/Main/VLCSeekCorrection/Input.value = user_settings.get_value('video_player', 'vlc_seek_correction')
	if user_settings.has_section_key('video_player', 'player_type'):
		var vp_type: int = user_settings.get_value('video_player', 'player_type')
		if OS.get_name() != "Android" and vp_type == 4:
			vp_type = 0
		%VideoPlayer/Main/PlayerSelection.select(vp_type)
		%VideoPlayer._on_player_selection_item_selected(vp_type)
	
	if user_settings.has_section_key('app_settings', 'mode'):
		$Menu.select_mode(user_settings.get_value('app_settings', 'mode'))
	else:
		$Menu.select_mode(1)


func apply_device_settings():
	if user_settings.has_section_key('speed_slider', 'max_speed'):
		var value = user_settings.get_value('speed_slider', 'max_speed', 25000)
		$Settings/VBox/Sliders/MaxSpeed/Input.value = int(value)
	
	if user_settings.has_section_key('accel_slider', 'max_acceleration'):
		var value = user_settings.get_value('accel_slider', 'max_acceleration', 500000)
		$Settings/VBox/Sliders/MaxAcceleration/Input.value = int(value)
	
	if user_settings.has_section_key('speed_slider', 'position_percent'):
		$SpeedPanel.set_speed_slider_pos(
				user_settings.get_value('speed_slider', 'position_percent', 0.6))
	else:
		$SpeedPanel.set_speed_slider_pos(0.6)
	
	if user_settings.has_section_key('accel_slider', 'position_percent'):
		$SpeedPanel.set_acceleration_slider_pos(
				user_settings.get_value('accel_slider', 'position_percent', 0.4))
	else:
		$SpeedPanel.set_acceleration_slider_pos(0.4)
	
	if user_settings.has_section_key('range_slider_min', 'position_percent'):
		$RangePanel.set_min_slider_pos(
				user_settings.get_value('range_slider_min', 'position_percent', 0))
	else:
		$RangePanel.set_min_slider_pos(0)
	
	if user_settings.has_section_key('range_slider_max', 'position_percent'):
		$RangePanel.set_max_slider_pos(
				user_settings.get_value('range_slider_max', 'position_percent', 1))
	else:
		$RangePanel.set_max_slider_pos(1)
	
	if user_settings.has_section_key('device_settings', 'syncing_speed'):
		$Settings/VBox/SyncingSpeed/Input.set_value_no_signal(
				int(user_settings.get_value('device_settings', 'syncing_speed', 1000)))
	
	if user_settings.has_section_key('device_settings', 'homing_trigger'):
		$Settings/VBox/HomingTrigger/Input.set_value_no_signal(
				float(user_settings.get_value('device_settings', 'homing_trigger' , 1.5)))
	
	$SpeedPanel.send_speed_limits()
	$RangePanel.send_range_limits()


func create_move_command(ms_timing: int, depth: float, trans: int, ease: int, auxiliary: int):
	var network_packet: PackedByteArray
	network_packet.resize(10)
	network_packet.encode_u8(0, OSSM.Command.MOVE)
	network_packet.encode_u32(1, ms_timing)
	network_packet.encode_u16(5, round(remap(abs(motor_direction - depth), 0, 1, 0, 10000)))
	network_packet.encode_u8(7, trans)
	network_packet.encode_u8(8, ease)
	network_packet.encode_u8(9, auxiliary)
	return network_packet


func round_to(value: float, decimals: int) -> float:
	var factor = pow(10, decimals)
	return round(value * factor) / factor


func load_path(file_name: String) -> bool:
	var file = paths_open_read(file_name)
	if not file:
		printerr("Error: Failed to read file.")
		return false
	var file_text := file.get_as_text()
	file.close()
	
	var file_data: Dictionary
	
	if file_name.ends_with(".funscript"):
		file_text = file_text.replace("\n", "")
		var parsed_funscript = JSON.parse_string(file_text)
		var inverted := false
		if parsed_funscript is Dictionary and parsed_funscript.get("inverted", false):
			inverted = true
	
		var actions_pattern = RegEx.new()
		actions_pattern.compile('"[Aa]ctions":\\s*\\[.*?\\]')
		var actions_regex = actions_pattern.search(file_text)
		if not actions_regex:
			actions_pattern.compile('"[Rr]aw[Aa]ctions":\\s*\\[.*?\\]')
			actions_regex = actions_pattern.search(file_text)
		if actions_regex:
			var actions_text = actions_regex.get_string(0)
			actions_text = actions_text.replace("'", '"')
			actions_text = actions_text.insert(0, "{")
			actions_text = actions_text.insert(actions_text.length(), "}")
			var actions_data = JSON.parse_string(actions_text)
			if actions_data:
				var actions_list = actions_data[actions_data.keys()[0]]
				var first_depth = round_to(clamp(actions_list[0].pos / 100, 0, 1), 4)
				if inverted:
					first_depth = round_to(1.0 - first_depth, 4)
				file_data[0] = [first_depth, 1, 2, 0]
				for action in actions_list:
					var frame: int = action.at / (1000.0 / 60.0)
					var depth = round_to(clamp(action.pos / 100, 0, 1), 4)
					if inverted:
						depth = round_to(1.0 - depth, 4)
					file_data[frame] = [depth, 1, 2, 0]
			else:
				printerr("Failed to parse funscript JSON")
		else:
			printerr("No actions data found in the funscript")
	else:
		file_data = JSON.parse_string(file_text)
		if not file_data:
			printerr("Error: No JSON data found in file.")
			return false
		if file_data.has("meta"):
			var meta = file_data["meta"]
			if meta is Dictionary and meta.has("video_offset_ms"):
				%VideoPlayer/Main/VideoOffset/Input.value = meta["video_offset_ms"]
		if file_data.has("markers"):
			file_data = file_data["markers"]
	
	var marker_data: Dictionary = file_data
	if marker_data.size() < 6:
		printerr("Error: Insufficient path data in file.")
		return false
	
	var sorted_keys := marker_data.keys()
	sorted_keys.sort_custom(func(a, b): return int(a) < int(b))
	
	var network_packets: Array
	for marker_frame in sorted_keys:
		var marker = marker_data[marker_frame]
		var ms_timing := int(round((float(marker_frame) / 60) * 1000))
		network_packets.append(create_move_command(ms_timing, marker[0], marker[1], marker[2], marker[3]))
		# Adjust for physics tick rate change from BounceX (60Hz to 50Hz)
		marker_data[round(int(marker_frame) / 1.2)] = marker
		marker_data.erase(marker_frame)
	
	network_paths.append(network_packets)
	
	var previous_depth: float
	var previous_frame: int
	var marker_list: Array = marker_data.keys()
	var path: PackedFloat32Array
	var frames: PackedInt32Array
	var path_line := Line2D.new()
	path_line.width = 15
	path_line.hide()
	marker_list.sort()
	for marker_frame in marker_list:
		var marker = marker_data[marker_frame]
		var depth = marker[0]
		var trans = marker[1]
		var ease = marker[2]
		if marker_frame > 0:
			var steps: int = marker_frame - previous_frame
			frames.append(previous_frame)
			for step in steps:
				var step_depth: float = Tween.interpolate_value(
						previous_depth,
						depth - previous_depth,
						step,
						steps,
						trans,
						ease)
				path.append(step_depth)
				var x_pos = (previous_frame * path_speed) + (step * path_speed)
				var y_pos = render_depth(step_depth)
				path_line.add_point(Vector2(x_pos, y_pos))
		previous_depth = depth
		previous_frame = marker_frame
	paths.append(path)
	marker_frames.append(frames)
	$PathDisplay/Paths.add_child(path_line)
	return true


func create_delay(duration: float):
	var delay_path: PackedFloat32Array
	var path_line := Line2D.new()
	path_line.hide()
	for point in round(duration * ticks_per_second):
		delay_path.append(-1)
	var frames: PackedInt32Array
	var network_packets: Array
	for timing in 6:
		var move_command = create_move_command(timing, 0, 0, 0, 0)
		network_packets.append(move_command)
		frames.append(timing)
	var end_move = create_move_command(duration * 1000, 0, 0, 0, 0)
	network_packets.append(end_move)
	network_paths.append(network_packets)
	paths.append(delay_path)
	marker_frames.append(frames)
	$PathDisplay/Paths.add_child(path_line)
	$Menu/Playlist.add_item("delay(%s)" % [duration])


func display_active_path_index(pause := true, send_buffer := true):
	paused = pause
	frame = 0
	marker_index = 0
	play_offset_ms = 0
	$SeekSlider.set_value_no_signal(0)
	update_time_display()
	if send_buffer:
		if %WebSocket.ossm_connected:
			send_command(OSSM.Command.RESET)
			var start_depth:float = paths[active_path_index][0]
			home_to(round(start_depth * 10000))
			await homing_complete
			if not %WebSocket.ossm_connected:
				return
			buffer_sent = 0
			while buffer_sent < 6 and marker_index < network_paths[active_path_index].size():
				%WebSocket.server.broadcast_binary(network_paths[active_path_index][marker_index])
				marker_index += 1
				buffer_sent += 1
	else:
		marker_index = 6
		buffer_sent = 6
	
	$ActionPanel.clear_selections()
	if pause:
		$ActionPanel/Pause.hide() 
		$ActionPanel/Play.show()
	for path in $PathDisplay/Paths.get_children():
		path.hide()
	var path = $PathDisplay/Paths.get_child(active_path_index)
	path.position.x = ($PathDisplay/PathArea.size.x / 2) + path_speed
	path.show()
	$PathDisplay/Ball.position.y = render_depth(paths[active_path_index][0])
	$PathDisplay/Ball.show()
	$PathDisplay.show()
	if %VideoPlayer.is_active() and AppMode.active == AppMode.MOVE:
		%VideoPlayer.sync_seek(0.0)


func seek() -> void:
	if active_path_index == null or _seeking:
		return
	_seeking = true
	if not paused:
		paused = true
		send_command(OSSM.Command.PAUSE)
		%ActionPanel.clear_selections()
		%ActionPanel/Pause.hide()
		%ActionPanel/Play.show()
		%CircleSelection.hide()
	
	var active_path = paths[active_path_index]
	if active_path.is_empty():
		_seeking = false
		return
	
	var value = $SeekSlider.value
	
	var total_frames: int = active_path.size()
	var target_frame := clampi(roundi(value * (total_frames - 1)), 0, total_frames - 1)
	var target_depth: float = active_path[target_frame]
	play_offset_ms = int(target_frame * 1000.0 / ticks_per_second)
	
	# Find the first marker_frame index AFTER target_frame
	var frames = marker_frames[active_path_index]
	var buffer_start := 0
	var cascade_index := 0
	for i in frames.size():
		if frames[i] <= target_frame:
			cascade_index = i
			buffer_start = i + 1
		else:
			break
	
	# Update display
	frame = target_frame
	var path_line = $PathDisplay/Paths.get_child(active_path_index)
	path_line.position.x = ($PathDisplay/PathArea.size.x / 2) + path_speed - (target_frame * path_speed)
	$PathDisplay/Ball.position.y = render_depth(target_depth)
	update_time_display()
	
	if %WebSocket.ossm_connected:
		send_command(OSSM.Command.RESET)
		home_to(round(target_depth * 10000))
		await homing_complete
		if not %WebSocket.ossm_connected:
			_seeking = false
			return
		# Send cascade packet (timestamp <= play_offset, firmware immediately skips it)
		var cascade_packet = network_paths[active_path_index][cascade_index]
		%WebSocket.server.broadcast_binary(cascade_packet)
		# Send buffer packets from seek position
		marker_index = buffer_start
		buffer_sent = 0
		while buffer_sent < 6 and marker_index < network_paths[active_path_index].size():
			var packet = network_paths[active_path_index][marker_index]
			var packet_ms = packet.decode_u32(1)
			var packet_depth = packet.decode_u16(5)
			%WebSocket.server.broadcast_binary(packet)
			marker_index += 1
			buffer_sent += 1
	
	if %VideoPlayer.is_active():
		%VideoPlayer.pause_and_seek(play_offset_ms / 1000.0)
	
	_seeking = false
	_seek_dragging = false


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
	var total_frames: int = paths[active_path_index].size()
	var current_sec := frame / ticks_per_second
	var total_sec := (total_frames - 1) / ticks_per_second
	if total_sec >= 3600:
		$TimeDisplay.text = "%d:%02d:%02d / %d:%02d:%02d" % [
			current_sec / 3600, current_sec % 3600 / 60, current_sec % 60,
			total_sec / 3600, total_sec % 3600 / 60, total_sec % 60]
	else:
		$TimeDisplay.text = "%d:%02d / %d:%02d" % [
			current_sec / 60, current_sec % 60,
			total_sec / 60, total_sec % 60]


func render_depth(depth) -> float:
	return PATH_BOTTOM + depth * (PATH_TOP - PATH_BOTTOM)


func activate_move_mode():
	set_physics_process(true)
	%ActionPanel/Play.show()
	%ActionPanel/Pause.hide()
	%PathDisplay/Paths.show()
	%PathDisplay/Ball.show()
	$SeekSlider.show()
	$TimeDisplay.show()
	%Menu/Main/PlaylistButtons.show()
	%Menu/Main/PathButtons.show()
	%Menu/Main/LoopAndVideoButtons/LoopPlaylistButton.show()
	%Menu/Main/LoopAndVideoButtons/VideoPlayerSync.show()
	%Menu/PathControls.show()
	%Menu/Playlist.show()
	if active_path_index != null:
		display_active_path_index()
	%Menu.refresh_selection()


func deactivate_move_mode():
	set_physics_process(false)
	%ActionPanel/Play.hide()
	%ActionPanel/Pause.show()
	%PathDisplay.hide()
	%PathDisplay/Paths.hide()
	%PathDisplay/Ball.hide()
	$SeekSlider.hide()
	$TimeDisplay.hide()
	%Menu/Main/PlaylistButtons.hide()
	%Menu/Main/PathButtons.hide()
	%Menu/Main/LoopAndVideoButtons/LoopPlaylistButton.hide()
	%Menu/Main/LoopAndVideoButtons/VideoPlayerSync.hide()
	%Menu/PathControls.hide()
	%Menu/Playlist.hide()


func _input(event: InputEvent) -> void: # Handle ui element outside click
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
	# NOTIFICATION_WM_GO_BACK_REQUEST:  # Android back button
	# NOTIFICATION_APPLICATION_PAUSED:  # App going to background
	# NOTIFICATION_APPLICATION_FOCUS_OUT:


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


func _on_video_player_played(video_time_seconds: float, from_stopped: bool):
	if active_path_index == null or not paused or AppMode.active != AppMode.MOVE:
		return
	if from_stopped:
		var path_time = float(frame) / ticks_per_second
		%VideoPlayer.pause_and_seek(path_time)
		return
	var total_frames: int = paths[active_path_index].size()
	if total_frames == 0:
		return
	
	var target_frame = clampi(int(video_time_seconds * ticks_per_second), 0, total_frames - 1)
	frame = target_frame
	
	# Realign buffer tracking to new frame position
	var frames = marker_frames[active_path_index]
	var cascade_index := 0
	for i in frames.size():
		if frames[i] <= target_frame:
			cascade_index = i
		else:
			break
	marker_index = mini(cascade_index + 1 + buffer_sent, network_paths[active_path_index].size())
	
	# Update display
	var path_line = $PathDisplay/Paths.get_child(active_path_index)
	path_line.position.x = ($PathDisplay/PathArea.size.x / 2) + path_speed - (target_frame * path_speed)
	$PathDisplay/Ball.position.y = render_depth(paths[active_path_index][target_frame])
	$SeekSlider.set_value_no_signal(float(target_frame) / (total_frames - 1))
	update_time_display()
	
	# Play
	%ActionPanel.clear_selections()
	%ActionPanel/Play.hide()
	%ActionPanel/Pause.show()
	%CircleSelection.hide()
	play()


func _on_video_player_paused():
	if paused or AppMode.active != AppMode.MOVE:
		return
	%ActionPanel.clear_selections()
	%ActionPanel/Pause.hide()
	%ActionPanel/Play.show()
	pause()


func _on_video_player_seeked(video_time_seconds: float):
	if active_path_index == null or AppMode.active != AppMode.MOVE:
		return
	var total_frames: int = paths[active_path_index].size()
	if total_frames == 0:
		return
	var target_frame = clampi(int(video_time_seconds * ticks_per_second), 0, total_frames - 1)
	$SeekSlider.set_value_no_signal(float(target_frame) / (total_frames - 1))
	seek()


func _check_storage_setup() -> void:
	if OS.get_name() != 'Android':
		return
	saf_paths_uri = _load_saf_paths_uri()
	saf_mpv_bridge_uri = load_saf_mpv_bridge_uri()
	_refresh_saf_subdirs()
	if saf_paths_uri.is_empty():
		$FolderPickSplash.show()


func pick_storage_folder() -> void:
	var err := DisplayServer.file_dialog_show(
			"Pick a folder for paths and playlists",
			"",
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_DIR,
			PackedStringArray(),
			_on_storage_folder_picked)
	if err != OK:
		push_error("file_dialog_show failed: %s" % err)


func _on_storage_folder_picked(
		status: bool,
		_paths: PackedStringArray,
		_filter_idx: int) -> void:
	if not status or _paths.is_empty():
		return
	saf_paths_uri = _paths[0]
	_save_saf_paths_uri(saf_paths_uri)
	_take_persistable_uri_permission(saf_paths_uri)
	_refresh_saf_subdirs()
	$FolderPickSplash.hide()


func _handle_dead_saf_grant() -> void:
	push_warning("SAF grant on saved URI is dead, clearing and re-prompting")
	saf_paths_uri = ""
	_save_saf_paths_uri("")
	_saf_file_subdirs.clear()
	_saf_paths_subdir_exists = false
	_saf_playlists_subdir_exists = false
	$FolderPickSplash.show()


func _take_persistable_uri_permission(uri_str: String) -> void:
	if OS.get_name() != 'Android' or uri_str.is_empty():
		return
	var Uri = JavaClassWrapper.wrap("android.net.Uri")
	var Intent = JavaClassWrapper.wrap("android.content.Intent")
	var ActivityThread = JavaClassWrapper.wrap("android.app.ActivityThread")
	if Uri == null or Intent == null or ActivityThread == null:
		return
	var uri_obj = Uri.parse(uri_str)
	var flags = Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
	var resolver = ActivityThread.currentActivityThread().getApplication().getContentResolver()
	resolver.takePersistableUriPermission(uri_obj, flags)


func _load_saf_paths_uri() -> String:
	if not FileAccess.file_exists(SAF_CONFIG_PATH):
		return ""
	if saf_storage.load(SAF_CONFIG_PATH) != OK:
		return ""
	return saf_storage.get_value("storage", "paths_uri", "")


func _save_saf_paths_uri(uri: String) -> void:
	saf_storage.set_value("storage", "paths_uri", uri)
	saf_storage.save(SAF_CONFIG_PATH)


func load_saf_mpv_bridge_uri() -> String:
	if not FileAccess.file_exists(SAF_CONFIG_PATH):
		return ""
	if saf_storage.load(SAF_CONFIG_PATH) != OK:
		return ""
	return saf_storage.get_value("storage", "mpv_bridge_uri", "")


func save_saf_mpv_bridge_uri(uri: String) -> void:
	saf_storage.set_value("storage", "mpv_bridge_uri", uri)
	saf_storage.save(SAF_CONFIG_PATH)


func paths_open_read(file_name: String) -> FileAccess:
	return FileAccess.open(_resolve_storage_path(file_name, "paths"), FileAccess.READ)


func playlists_open_read(file_name: String) -> FileAccess:
	return FileAccess.open(_resolve_storage_path(file_name, "playlists"), FileAccess.READ)


func playlists_open_write(file_name: String) -> FileAccess:
	if OS.get_name() == 'Android' and _saf_playlists_subdir_exists:
		_saf_file_subdirs[file_name] = "Playlists"
	return FileAccess.open(_resolve_storage_path(file_name, "playlists"), FileAccess.WRITE)


func list_files(category: String, extensions: PackedStringArray) -> PackedStringArray:
	if OS.get_name() == 'Android':
		return _list_files_saf(extensions, category)
	
	var result: PackedStringArray = []
	var dir_path := _resolve_storage_dir(category)
	if dir_path.is_empty():
		return result
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	for file_name in dir.get_files():
		for ext in extensions:
			if file_name.ends_with(ext):
				result.append(file_name)
				break
	return result


# Detects whether legacy "Paths" and "Playlists" subdirs exist at the SAF
# tree root. Called at startup and after folder pick so the existence flags
# are correct before any list_files or write call.
func _refresh_saf_subdirs() -> void:
	_saf_paths_subdir_exists = false
	_saf_playlists_subdir_exists = false
	if OS.get_name() != 'Android' or saf_paths_uri.is_empty():
		return
	
	var DocumentsContract = JavaClassWrapper.wrap("android.provider.DocumentsContract")
	var Uri = JavaClassWrapper.wrap("android.net.Uri")
	var ActivityThread = JavaClassWrapper.wrap("android.app.ActivityThread")
	if DocumentsContract == null or Uri == null or ActivityThread == null:
		return
	var tree_uri_obj = Uri.parse(saf_paths_uri)
	if tree_uri_obj == null:
		return
	var root_doc_id = DocumentsContract.getTreeDocumentId(tree_uri_obj)
	var children_uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree_uri_obj, root_doc_id)
	if children_uri == null:
		return
	var resolver = ActivityThread.currentActivityThread().getApplication().getContentResolver()
	var cursor = resolver.query(children_uri,
			PackedStringArray(["_display_name", "mime_type"]),
			"", PackedStringArray(), "", null)
	if cursor == null:
		return
	var name_col = cursor.getColumnIndex("_display_name")
	var mime_col = cursor.getColumnIndex("mime_type")
	while cursor.moveToNext():
		if cursor.getString(mime_col) == "vnd.android.document/directory":
			match cursor.getString(name_col):
				"Paths": _saf_paths_subdir_exists = true
				"Playlists": _saf_playlists_subdir_exists = true
	cursor.close()


func _list_files_saf(extensions: PackedStringArray, category: String) -> PackedStringArray:
	var result: PackedStringArray = []
	if saf_paths_uri.is_empty():
		return result
	
	var DocumentsContract = JavaClassWrapper.wrap("android.provider.DocumentsContract")
	var Uri = JavaClassWrapper.wrap("android.net.Uri")
	var ActivityThread = JavaClassWrapper.wrap("android.app.ActivityThread")
	if DocumentsContract == null or Uri == null or ActivityThread == null:
		return result
	
	var tree_uri_obj = Uri.parse(saf_paths_uri)
	if tree_uri_obj == null:
		return result
	
	var current_thread = ActivityThread.currentActivityThread()
	if current_thread == null:
		return result
	var app = current_thread.getApplication()
	if app == null:
		return result
	var resolver = app.getContentResolver()
	if resolver == null:
		return result
	
	var subdir_name := "Paths" if category == "paths" else "Playlists"
	var root_doc_id = DocumentsContract.getTreeDocumentId(tree_uri_obj)
	var root_children_uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree_uri_obj, root_doc_id)
	if root_children_uri == null:
		return result
	
	# Pass 1: scan root for matching files; record the relevant subdir's
	# document_id if found; opportunistically refresh both existence flags.
	var cursor = resolver.query(root_children_uri,
			PackedStringArray(["_display_name", "mime_type", "document_id"]),
			"", PackedStringArray(), "", null)
	if cursor == null:
		_handle_dead_saf_grant()
		return result
	
	var combined: Dictionary = {}
	var name_col = cursor.getColumnIndex("_display_name")
	var mime_col = cursor.getColumnIndex("mime_type")
	var id_col = cursor.getColumnIndex("document_id")
	var subdir_doc_id := ""
	while cursor.moveToNext():
		var _name: String = cursor.getString(name_col)
		var mime: String = cursor.getString(mime_col)
		if mime == "vnd.android.document/directory":
			match _name:
				"Paths": _saf_paths_subdir_exists = true
				"Playlists": _saf_playlists_subdir_exists = true
			if _name == subdir_name:
				subdir_doc_id = cursor.getString(id_col)
		else:
			for ext in extensions:
				if _name.ends_with(ext):
					combined[_name] = ""
					break
	cursor.close()
	
	# Pass 2: scan the category subdir if present. Subdir entries override
	# root entries (per design: "subdir wins" on name conflict).
	if not subdir_doc_id.is_empty():
		var sub_children_uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree_uri_obj, subdir_doc_id)
		if sub_children_uri != null:
			var sub_cursor = resolver.query(sub_children_uri,
					PackedStringArray(["_display_name"]),
					"", PackedStringArray(), "", null)
			if sub_cursor != null:
				var sub_name_col = sub_cursor.getColumnIndex("_display_name")
				while sub_cursor.moveToNext():
					var _name: String = sub_cursor.getString(sub_name_col)
					for ext in extensions:
						if _name.ends_with(ext):
							combined[_name] = subdir_name
							break
				sub_cursor.close()
	
	for _name in combined:
		_saf_file_subdirs[_name] = combined[_name]
		result.append(_name)
	return result


func _resolve_storage_path(file_name: String, category: String) -> String:
	if OS.get_name() == 'Android':
		if saf_paths_uri.is_empty():
			return ""
		var subdir: String = _saf_file_subdirs.get(file_name, "")
		if subdir.is_empty():
			return saf_paths_uri + "#" + file_name
		return saf_paths_uri + "#" + subdir + "/" + file_name
	return _resolve_storage_dir(category) + file_name


func _resolve_storage_dir(category: String) -> String:
	if OS.get_name() == 'Android':
		if saf_paths_uri.is_empty():
			return ""
		return _saf_tree_uri_to_fs_path(saf_paths_uri)
	return paths_dir if category == "paths" else playlists_dir


func _saf_tree_uri_to_fs_path(tree_uri: String) -> String:
	var prefix := "content://com.android.externalstorage.documents/tree/"
	if not tree_uri.begins_with(prefix):
		return ""
	var doc_id := tree_uri.substr(prefix.length()).uri_decode()
	var colon := doc_id.find(":")
	if colon < 0:
		return ""
	var volume := doc_id.substr(0, colon)
	var rel_path := doc_id.substr(colon + 1)
	if volume == "primary":
		return "/storage/emulated/0/" + rel_path + "/"
	return "/storage/" + volume + "/" + rel_path + "/"


func get_storage_label(category: String) -> String:
	var subdir_name := "Paths" if category == "paths" else "Playlists"
	if OS.get_name() == 'Android':
		var base := _saf_uri_to_friendly_path(saf_paths_uri)
		if base.is_empty():
			return ""
		var subdir_present := _saf_paths_subdir_exists if category == "paths" \
				else _saf_playlists_subdir_exists
		return base + "/" + subdir_name if subdir_present else base
	return "Documents/OSSM Sauce/" + subdir_name


func _saf_uri_to_friendly_path(tree_uri: String) -> String:
	var prefix := "content://com.android.externalstorage.documents/tree/"
	if not tree_uri.begins_with(prefix):
		return ""
	var doc_id := tree_uri.substr(prefix.length()).uri_decode()
	var colon := doc_id.find(":")
	if colon < 0:
		return ""
	var volume := doc_id.substr(0, colon)
	var rel_path := doc_id.substr(colon + 1)
	if volume == "primary":
		return "Internal Storage/" + rel_path
	return volume + "/" + rel_path
