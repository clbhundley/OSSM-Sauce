extends Control

var app_version_number:String = "1.1.0"

var storage_dir:String
var paths_dir:String
var playlists_dir:String
var cfg_path:String

const ANIM_TIME = 0.65

var user_settings := ConfigFile.new()

var websocket = WebSocketPeer.new()

var connected_to_server:bool
var connected_to_ossm:bool

var ticks_per_second:int

var path_speed:int = 30

var paused:bool = true

var active_path_index

var paths:Array
var markers:Array
var network_paths:Array

var frame:int

enum CommandType {
	RESPONSE,
	MOVE,
	LOOP,
	POSITION,
	PLAY,
	PAUSE,
	RESET,
	HOMING,
	CONNECTION,
	SET_SPEED_LIMIT,
	SET_GLOBAL_ACCELERATION,
	SET_RANGE_LIMIT,
	SET_HOMING_SPEED,
}

var app_mode:int
enum Mode {
	IDLE,
	HOMING,
	MOVE,
	POSITION,
	LOOP,
}

var max_speed:int
var max_acceleration:int

var min_stroke_duration:float
var max_stroke_duration:float

signal homing_complete

@onready var PATH_TOP = $PathDisplay/PathArea.position.y
@onready var PATH_BOTTOM = PATH_TOP + $PathDisplay/PathArea.size.y

@onready var ossm_connection_timeout:Timer = $Settings/Network/ConnectionTimeout


func _init():
	max_speed = 25000
	max_acceleration = 500000


func _ready():
	var physics_ticks = "physics/common/physics_ticks_per_second"
	ticks_per_second = ProjectSettings.get_setting(physics_ticks)
	set_process(false)
	$PositionControls.set_physics_process(false)
	
	min_stroke_duration = $Menu/LoopSettings/MinStrokeDuration/SpinBox.value
	max_stroke_duration = $Menu/LoopSettings/MaxStrokeDuration/SpinBox.value
	
	max_speed = int($Settings/Sliders/MaxSpeed/TextEdit.text)
	max_acceleration = int($Settings/Sliders/MaxAcceleration/TextEdit.text)
	
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
	apply_user_settings()
	
	if OS.get_name() != 'Android':
		var window_size = get_viewport().size
		var screen_size = DisplayServer.screen_get_size()
		var centered_position = Vector2(
			(screen_size.x - window_size.x) / 2,
			(screen_size.y - window_size.y) / 2)
		DisplayServer.window_set_position(centered_position)
		get_viewport().size_changed.connect(_on_window_size_changed)


var marker_index:int
func _physics_process(delta):
	if paused or paths[active_path_index].is_empty():
		return
	
	if frame >= paths[active_path_index].size() - 1:
		
		if active_path_index < network_paths.size() - 1:
			var overreach_index = marker_index - network_paths[active_path_index].size() + 1
			var next_path = network_paths[active_path_index + 1]
			websocket.send(next_path[overreach_index])
		
		if active_path_index < paths.size() - 1:
			var path_list = $Menu/Playlist/Scroll/VBox
			var next_index = active_path_index + 1
			var next_path = path_list.get_child(next_index) 
			active_path_index = next_index
			display_active_path_index(false, false)
			$Menu/Playlist._on_item_selected(next_path)
			path_list.get_child(next_index).set_active()
		else:
			pause()
			$Menu.show_play()
			$CircleSelection.show_restart()
			paused = true
		
		return
	
	var marker_list = markers[active_path_index]
	var active_path = network_paths[active_path_index]
	var current_marker = marker_index - 6
	var current_marker_frame = int(marker_list.keys()[current_marker])
	if frame == current_marker_frame:
		if connected_to_server:
			if marker_index < active_path.size():
				websocket.send(active_path[marker_index])
			elif active_path_index < network_paths.size() - 1:
				var overreach_index = marker_index - active_path.size()
				var next_path = network_paths[active_path_index + 1]
				websocket.send(next_path[overreach_index])
		if current_marker < marker_list.size() - 1:
			marker_index += 1
	
	var depth:float = paths[active_path_index][frame]
	frame += 1

	$PathDisplay/Paths.get_child(active_path_index).position.x -= path_speed
	$PathDisplay/Ball.position.y = render_depth(depth)


func _process(delta):
	websocket.poll()
	var state = websocket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not connected_to_server:
			user_settings.set_value(
				'app_settings',
				'last_server_connection',
				$Settings/Network/Address/TextEdit.text)
			connected_to_server = true
			send_command(CommandType.CONNECTION)
			$Wifi.self_modulate = Color.WHITE
			$Wifi.show()
		while websocket.get_available_packet_count():
			var packet:PackedByteArray = websocket.get_packet()
			if packet[0] == CommandType.RESPONSE:
				match packet[1]:
					
					CommandType.CONNECTION:
						connected_to_ossm = true
						ossm_connection_timeout.emit_signal('timeout')
						ossm_connection_timeout.stop()
						$Wifi.self_modulate = Color.SEA_GREEN
						$SpeedPanel.update_speed()
						$SpeedPanel.update_acceleration()
						$RangePanel.update_min_range()
						$RangePanel.update_max_range()
						$Settings.send_homing_speed()
						$Menu.select_mode($Menu/Main/Mode.selected)
					
					CommandType.HOMING:
						$CircleSelection.hide()
						$CircleSelection.homing_lock = false
						var display = [
							$PositionControls,
							$LoopControls,
							$PathDisplay,
							$ActionPanel,
							$Menu]
						for node in display:
							node.modulate.a = 1
						emit_signal("homing_complete")
						if $Menu/Main/Mode.selected == 0:
							if active_path_index != null:
								$CircleSelection.show_play()
						elif $Menu/Main/Mode.selected == 1:
							play()
	
	elif state == WebSocketPeer.STATE_CLOSING:
		pass # Keep polling to achieve proper close.
	elif state == WebSocketPeer.STATE_CLOSED:
		var code = websocket.get_close_code()
		var reason = websocket.get_close_reason()
		var text = "Webwebsocket closed with code: %d, reason %s. Clean: %s"
		print(text % [code, reason, code != -1])
		connected_to_server = false
		set_process(false)
		$Wifi.hide()


func send_command(value:int):
	if connected_to_server:
		var command:PackedByteArray
		command.resize(1)
		command[0] = value
		websocket.send(command)


func home_to(target_position:int):
	if connected_to_ossm:
		$CircleSelection.show_hourglass()
		var displays = [
			$PositionControls,
			$LoopControls,
			$PathDisplay,
			$ActionPanel,
			$Menu]
		for display in displays:
			display.modulate.a = 0.05
		var command:PackedByteArray
		command.resize(5)
		command.encode_u8(0, CommandType.HOMING)
		command.encode_s32(1, target_position)
		websocket.send(command)


func play(play_time_ms = null):
	var command:PackedByteArray
	if app_mode == Mode.MOVE and active_path_index != null:
		paused = false
		#if play_time_ms != null:
			#command.resize(6)
			#command.encode_u8(0, CommandType.PLAY)
			#command.encode_u8(1, app_mode)
			#command.encode_u32(2, play_time_ms)
			#if connected_to_server:
				#websocket.send(command)
			#return
	command.resize(2)
	command.encode_u8(0, CommandType.PLAY)
	command.encode_u8(1, app_mode)
	if connected_to_server:
		websocket.send(command)


func pause():
	if connected_to_server:
		var command:PackedByteArray
		command.resize(1)
		command[0] = CommandType.PAUSE
		websocket.send(command)
	paused = true


func check_root_directory():
	var dir = DirAccess.open(storage_dir)
	if not dir.dir_exists("OSSM Sauce"):
		dir.make_dir("OSSM Sauce")
	dir.change_dir("OSSM Sauce")
	for directory in ["Paths", "Playlists"]:
		if not dir.dir_exists(directory):
			dir.make_dir(directory)


func apply_user_settings():
	user_settings.load(cfg_path)
	
	var cfg_version_number = user_settings.get_value(
			'app_settings',
			'version_number',
			"")
	if cfg_version_number != app_version_number:
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
		if user_settings.has_section_key('window', 'always_on_top'):
			var checkbox = $Settings/Window/AlwaysOnTop/CheckBox
			checkbox.button_pressed = user_settings.get_value(
					'window',
					'always_on_top')
		if user_settings.has_section_key('window', 'transparent_background'):
			var checkbox = $Settings/Window/TransparentBg/CheckBox
			checkbox.button_pressed = user_settings.get_value(
					'window',
					'transparent_background')
	
	if user_settings.get_value('app_settings', 'show_splash', true):
		$Splash.show()
	
	if user_settings.has_section_key('app_settings', 'last_server_connection'):
		$Settings/Network/Address/TextEdit.text = user_settings.get_value(
				'app_settings',
				'last_server_connection')
		$ActionPanel.hide()
		$ConnectingLabel.show()
		$Settings._on_connect_pressed()
		ossm_connection_timeout.start()
		await ossm_connection_timeout.timeout
		$ActionPanel.show()
		$ConnectingLabel.hide()
	
	if user_settings.has_section_key('speed_slider', 'max_speed'):
		$Settings.set_max_speed(
				user_settings.get_value('speed_slider', 'max_speed'))
	
	if user_settings.has_section_key('accel_slider', 'max_acceleration'):
		$Settings.set_max_acceleration(
				user_settings.get_value('accel_slider', 'max_acceleration'))
	
	if user_settings.has_section_key('speed_slider', 'position_percent'):
		$SpeedPanel.set_speed_slider_pos(
				user_settings.get_value('speed_slider', 'position_percent'))
	else:
		$SpeedPanel.set_speed_slider_pos(0.6)
	
	if user_settings.has_section_key('accel_slider', 'position_percent'):
		$SpeedPanel.set_acceleration_slider_pos(
				user_settings.get_value('accel_slider', 'position_percent'))
	else:
		$SpeedPanel.set_acceleration_slider_pos(0.4)
	
	if user_settings.has_section_key('range_slider_min', 'position_percent'):
		$RangePanel.set_min_slider_pos(
				user_settings.get_value('range_slider_min', 'position_percent'))
	else:
		$RangePanel.set_min_slider_pos(0)
	
	if user_settings.has_section_key('range_slider_max', 'position_percent'):
		$RangePanel.set_max_slider_pos(
				user_settings.get_value('range_slider_max', 'position_percent'))
	else:
		$RangePanel.set_max_slider_pos(1)
	
	if user_settings.has_section_key('device_settings', 'homing_speed'):
		$Settings/HomingSpeed/SpinBox.set_value(
				user_settings.get_value('device_settings', 'homing_speed'))
		$Settings.send_homing_speed()
	
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
	
	if user_settings.has_section_key('app_settings', 'mode'):
		$Menu.select_mode(user_settings.get_value('app_settings', 'mode'))
	else:
		$Menu.select_mode(0)
	


func load_path(file_name:String) -> bool:
	var file = FileAccess.open(paths_dir + file_name, FileAccess.READ)
	if not file:
		return false
	var file_data = JSON.parse_string(file.get_line())
	if not file_data:
		return false
	var marker_data:Dictionary = file_data
	
	if marker_data.is_empty():
		return false
	
	var network_packets:Array
	for marker_frame in marker_data.keys():
		var ms_timing = round((float(marker_frame) / 60) * 1000)
		var depth = marker_data[marker_frame][0]
		var trans = marker_data[marker_frame][1]
		var ease = marker_data[marker_frame][2]
		var auxiliary = marker_data[marker_frame][3]
		
		var network_packet:PackedByteArray
		network_packet.resize(10)
		network_packet.encode_u8(0, CommandType.MOVE)
		network_packet.encode_u32(1, ms_timing)
		network_packet.encode_u16(5, round(remap(depth, 0, 1, 0, 10000)))
		network_packet.encode_u8(7, trans)
		network_packet.encode_u8(8, ease)
		network_packet.encode_u8(9, auxiliary)
		network_packets.append(network_packet)
		
		#adjusting for physics tick rate change from BounceX (60Hz to 50Hz)
		marker_data[round(int(marker_frame) / 1.2)] = marker_data[marker_frame]
		marker_data.erase(marker_frame)
	
	network_paths.append(network_packets)
	
	file.close()
	var previous_depth:float
	var previous_frame:int
	var marker_list:Array = marker_data.keys()
	var path:PackedFloat32Array
	var path_new:Dictionary
	var path_line:Line2D = Line2D.new()
	path_line.width = 15
	path_line.hide()
	marker_list.sort()
	for marker_frame in marker_list:
		var depth = marker_data[marker_frame][0]
		var trans = marker_data[marker_frame][1]
		var ease = marker_data[marker_frame][2]
		var auxiliary = marker_data[marker_frame][3]
		if marker_frame > 0:
			var steps:int = marker_frame - previous_frame
			var duration = (float(steps) / ticks_per_second) * 1000
			var scaled_depth:int = round(clamp(depth, 0, 0.9999) * 10000)
			var headers:String = "M%sD%sT%sE%s"
			var message:String = headers%[scaled_depth, duration, trans, ease]
			path_new[previous_frame] = message
			for step in steps:
				var step_depth:float = Tween.interpolate_value(
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
	markers.append(path_new)
	$PathDisplay/Paths.add_child(path_line)
	return true


func create_delay(duration:float):
	var delay_path:PackedFloat32Array
	var path_line:Line2D = Line2D.new()
	path_line.hide()
	var headers:String = "M%sD%sT%sE%s"
	var message:String = headers%[0, duration * 1000, 0, 2]
	for point in round(duration * ticks_per_second):
		delay_path.append(-1)
	paths.append(delay_path)
	markers.append({0:message})
	markers.append({1:message})
	markers.append({2:message})
	markers.append({3:message})
	markers.append({4:message})
	markers.append({5:message})
	markers.append({6:message})
	
	var network_packets:Array
	
	var network_packet_start:PackedByteArray
	network_packet_start.resize(10)
	network_packet_start.encode_u8(0, CommandType.MOVE)
	network_packet_start.encode_u32(1, 0)
	network_packet_start.encode_u16(5, 0)
	network_packet_start.encode_u8(7, 0)
	network_packet_start.encode_u8(8, 2)
	network_packet_start.encode_u8(9, 0)
	network_packets.append(network_packet_start)
	
	for i in 5:
		var network_packet_fill:PackedByteArray
		network_packet_fill.resize(10)
		network_packet_fill.encode_u8(0, CommandType.MOVE)
		network_packet_fill.encode_u32(1, i)
		network_packet_fill.encode_u16(5, 0)
		network_packet_fill.encode_u8(7, 0)
		network_packet_fill.encode_u8(8, 2)
		network_packet_fill.encode_u8(9, 0)
		network_packets.append(network_packet_start)
	
	var network_packet_end:PackedByteArray
	network_packet_end.resize(10)
	network_packet_end.encode_u8(0, CommandType.MOVE)
	network_packet_end.encode_u32(1, duration * 1000)
	network_packet_end.encode_u16(5, 0)
	network_packet_end.encode_u8(7, 0)
	network_packet_end.encode_u8(8, 2)
	network_packet_end.encode_u8(9, 0)
	network_packets.append(network_packet_end)
	
	network_paths.append(network_packets)
	
	$PathDisplay/Paths.add_child(path_line)
	$Menu/Playlist.add_item("delay(%s)" % [duration])


func display_active_path_index(pause := true, send_buffer := true):
	paused = pause
	frame = 0
	marker_index = 0
	
	if send_buffer:
		if connected_to_server:
			send_command(CommandType.RESET)
			while marker_index < 6:
				websocket.send(network_paths[active_path_index][marker_index])
				marker_index += 1
	else:
		marker_index = 6
	
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


func render_depth(depth) -> float:
	return PATH_BOTTOM + depth * (PATH_TOP - PATH_BOTTOM)


func _on_window_size_changed():
	if OS.get_name() != "Android":
		var window_size = DisplayServer.window_get_size()
		user_settings.set_value('window', 'size', window_size)


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		user_settings.save(cfg_path)
		if connected_to_server:
			const MIN_RANGE = 0
			var command:PackedByteArray
			command.resize(4)
			command.encode_u8(0, CommandType.SET_RANGE_LIMIT)
			command.encode_u8(1, MIN_RANGE)
			command.encode_u16(2, 0)
			websocket.send(command)
			home_to(0)
