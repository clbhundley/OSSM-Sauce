extends Control

var ticks_per_second:int

var paused:bool = true

var frame:int

var active_path_index

var paths:Array
var markers:Array

var path_speed:int = 30

const ANIM_TIME = 0.65

var user_settings := ConfigFile.new()

var websocket = WebSocketPeer.new()

var storage_dir:String
var paths_dir:String
var playlists_dir:String
var cfg_path:String

var app_mode:int
enum Mode {
	PATH,
	POSITION,
	LOOP
}

var connected_to_server:bool
var connected_to_ossm:bool

var USER_MIN_POS:int
var USER_MAX_POS:int

var min_pos:int
var min_pos_pct:float = 1

var max_pos:int
var max_pos_pct:float = 0

var max_speed:int
var max_acceleration:int

var min_stroke_duration:float
var max_stroke_duration:float

@onready var PATH_TOP = $PathDisplay/PathArea.position.y
@onready var PATH_BOTTOM = PATH_TOP + $PathDisplay/PathArea.size.y

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
		if active_path_index < paths.size() - 1:
			var path_list = $Menu/Playlist/Scroll/VBox
			var next_index = active_path_index + 1
			var next_path = path_list.get_child(next_index) 
			active_path_index = next_index
			display_active_path_index(false)
			$Menu/Playlist._on_item_selected(next_path)
			path_list.get_child(next_index).set_active()
		else:
			$Menu.show_play()
			$CircleSelection.show_restart()
			paused = true
		return
	
	var marker_list = markers[active_path_index]
	var marker_frame = int(marker_list.keys()[marker_index])
	if frame == marker_frame:
		if connected_to_server:
			websocket.send_text(marker_list[marker_frame])
		if marker_index < marker_list.size() - 1:
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
			websocket.send_text('C:APP')
			connected_to_server = true
			$Wifi.self_modulate = Color.WHITE
			$Wifi.show()
		while websocket.get_available_packet_count():
			var packet = websocket.get_packet()
			var message:String = packet.get_string_from_ascii()
			print("Received: ", message)
			if message.begins_with("C"):
				if message.substr(1) == ":OSSM":
					connected_to_ossm = true
					$Wifi.self_modulate = Color.SEA_GREEN
					$SpeedPanel.update_speed()
					$SpeedPanel.update_acceleration()
					var homing_speed = $Settings/HomingSpeed/SpinBox.value
					websocket.send_text('HS' + str(homing_speed))
			elif message == "HC":
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
				if $Menu/Main/Mode.selected == 0 and active_path_index != null:
					websocket.send_text("M0D0T0E0")
					if not $Menu.is_visible_in_tree():
						$CircleSelection.show_play()
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
	
	if user_settings.get_value('app_settings', 'show_splash', true):
		$Splash.show()
	
	if user_settings.has_section_key('app_settings', 'mode'):
		$Menu.select_mode(user_settings.get_value('app_settings', 'mode'))
	
	if user_settings.has_section_key('app_settings', 'last_server_connection'):
		$Settings/Network/Address/TextEdit.text = user_settings.get_value(
			'app_settings',
			'last_server_connection')
		$Settings._on_connect_pressed()
	
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
	
	if user_settings.has_section_key('device_settings', 'homing_speed'):
		$Settings/HomingSpeed/SpinBox.set_value(
			user_settings.get_value('device_settings', 'homing_speed'))
	
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
		$LoopControls/Controls/Transitions/In.select(
			user_settings.get_value('stroke_settings', 'in_trans'))
	
	if user_settings.has_section_key('stroke_settings', 'out_trans'):
		$LoopControls/Controls/Transitions/Out.select(
			user_settings.get_value('stroke_settings', 'out_trans'))
	
	if user_settings.has_section_key('stroke_settings', 'in_ease'):
		$LoopControls/Controls/Easings/In.select(
			user_settings.get_value('stroke_settings', 'in_ease'))
	
	if user_settings.has_section_key('stroke_settings', 'out_ease'):
		$LoopControls/Controls/Easings/Out.select(
			user_settings.get_value('stroke_settings', 'out_ease'))
	
	$LoopControls.draw_easing()
	
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
	for i in marker_data.keys():
		 #5/6 pulldown from BounceX physics tick rate
		marker_data[round(int(i) / 1.2)] = marker_data[i]
		marker_data.erase(i)
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
	$PathDisplay/Paths.add_child(path_line)
	$Menu/Playlist.add_item("delay(%s)" % [duration])

func display_active_path_index(pause:bool = true):
	paused = pause
	frame = 0
	marker_index = 0
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
