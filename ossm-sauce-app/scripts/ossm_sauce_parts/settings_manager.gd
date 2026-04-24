extends RefCounted

var app


func setup(app_owner):
	app = app_owner


func _n(path: String):
	return app.get_node(path)


func _u(path: String):
	return app.get_node(path)


func apply_user_settings():
	var user_settings = app.user_settings
	var cfg_version_number = user_settings.get_value('app_settings', 'version_number', "")

	if cfg_version_number.naturalcasecmp_to("1.5") < 0:
		user_settings.clear()
		user_settings.set_value('app_settings', 'version_number', app.app_version_number)
		user_settings.save(app.cfg_path)

	if OS.get_name() != 'Android':
		if user_settings.has_section_key('window', 'size'):
			DisplayServer.window_set_size(user_settings.get_value('window', 'size'))
		else:
			DisplayServer.window_set_size(Vector2(435, 774))

		if user_settings.has_section_key('window', 'always_on_top'):
			var checkbox = _n("Settings/VBox/AlwaysOnTop")
			checkbox.button_pressed = user_settings.get_value('window', 'always_on_top')

	if user_settings.get_value('app_settings', 'show_splash', true):
		_n("Splash").show()

	if user_settings.has_section_key('network', 'port'):
		var port_number = user_settings.get_value('network', 'port')
		_n("Settings/VBox/Network/Port/Input").value = port_number
		_u("%WebSocket").port = port_number

	if user_settings.has_section_key('device_settings', 'motor_direction'):
		var value = user_settings.get_value('device_settings', 'motor_direction', 0)
		_n("Settings/VBox/ReverseMotorDirection").button_pressed = bool(value)

	apply_device_settings()

	if user_settings.has_section_key('app_settings', 'smoothing_slider'):
		_n("PositionControls/Smoothing/HSlider").set_value(user_settings.get_value('app_settings', 'smoothing_slider'))

	if user_settings.has_section_key('stroke_settings', 'min_duration'):
		_n("Menu").set_min_stroke_duration(user_settings.get_value('stroke_settings', 'min_duration'))
	if user_settings.has_section_key('stroke_settings', 'max_duration'):
		_n("Menu").set_max_stroke_duration(user_settings.get_value('stroke_settings', 'max_duration'))
	if user_settings.has_section_key('stroke_settings', 'display_mode'):
		_n("Menu").set_stroke_duration_display_mode(user_settings.get_value('stroke_settings', 'display_mode'))
	if user_settings.has_section_key('stroke_settings', 'in_trans'):
		_n("LoopControls/In/AccelerationControls/Transition").select(user_settings.get_value('stroke_settings', 'in_trans'))
	if user_settings.has_section_key('stroke_settings', 'in_ease'):
		_n("LoopControls/In/AccelerationControls/Easing").select(user_settings.get_value('stroke_settings', 'in_ease'))
	if user_settings.has_section_key('stroke_settings', 'out_trans'):
		_n("LoopControls/Out/AccelerationControls/Transition").select(user_settings.get_value('stroke_settings', 'out_trans'))
	if user_settings.has_section_key('stroke_settings', 'out_ease'):
		_n("LoopControls/Out/AccelerationControls/Easing").select(user_settings.get_value('stroke_settings', 'out_ease'))
	_n("LoopControls").draw_easing()

	if user_settings.has_section_key('bridge_settings', 'min_move_duration') or user_settings.has_section_key('bridge_settings', 'max_move_duration'):
		_u("%BridgeControls").set_move_duration_limits(
			user_settings.get_value('bridge_settings', 'min_move_duration', 500),
			user_settings.get_value('bridge_settings', 'max_move_duration', 6000)
		)
	if user_settings.has_section_key('bridge_settings', 'bridge_mode'):
		var bridge_mode = user_settings.get_value('bridge_settings', 'bridge_mode')
		_u("%Menu/BridgeSettings/BridgeMode/ModeSelection").selected = bridge_mode
		_n("Menu")._on_bridge_mode_selected(bridge_mode)
	if user_settings.has_section_key('bridge_settings', 'logging_enabled'):
		_u("%Menu/BridgeSettings/LoggingEnabled").button_pressed = user_settings.get_value('bridge_settings', 'logging_enabled')

	if user_settings.has_section_key('bpio_settings', 'server_address'):
		_u("%Menu/BridgeSettings/BPIO/ServerAddress/Input").text = user_settings.get_value('bpio_settings', 'server_address')
	if user_settings.has_section_key('bpio_settings', 'server_port'):
		_u("%Menu/BridgeSettings/BPIO/Ports/ServerPort/Input").value = user_settings.get_value('bpio_settings', 'server_port')
	if user_settings.has_section_key('bpio_settings', 'wsdm_port'):
		_u("%Menu/BridgeSettings/BPIO/Ports/WSDMPort/Input").value = user_settings.get_value('bpio_settings', 'wsdm_port')
	if user_settings.has_section_key('bpio_settings', 'identifier'):
		_u("%Menu/BridgeSettings/BPIO/Identifier/Input").text = user_settings.get_value('bpio_settings', 'identifier')
	if user_settings.has_section_key('bpio_settings', 'client_name'):
		_u("%Menu/BridgeSettings/BPIO/ClientName/Input").text = user_settings.get_value('bpio_settings', 'client_name')
	if user_settings.has_section_key('bpio_settings', 'address'):
		_u("%Menu/BridgeSettings/BPIO/Address/Input").text = user_settings.get_value('bpio_settings', 'address')

	if user_settings.has_section_key('xtoys_settings', 'port'):
		_u("%Menu/BridgeSettings/XToys/Port/Input").value = user_settings.get_value('xtoys_settings', 'port')
	if user_settings.has_section_key('xtoys_settings', 'max_msg_frequency'):
		_u("%Menu/BridgeSettings/XToys/MaxMsgFrequency/Input").set_value_no_signal(user_settings.get_value('xtoys_settings', 'max_msg_frequency'))
	if user_settings.has_section_key('xtoys_settings', 'use_command_duration'):
		_u("%Menu/BridgeSettings/XToys/UseCommandDuration").button_pressed = user_settings.get_value('xtoys_settings', 'use_command_duration')

	if user_settings.has_section_key('mcp_settings', 'port'):
		_u("%Menu/BridgeSettings/MCP/Port/Input").set_value_no_signal(user_settings.get_value('mcp_settings', 'port'))

	var video_player = _u("%VideoPlayer")
	if user_settings.has_section_key('video_player', 'player_address'):
		video_player.player_address = user_settings.get_value('video_player', 'player_address')
		_u("%VideoPlayer/VBox/PlayerAddress/Input").text = video_player.player_address
	if user_settings.has_section_key('video_player', 'vlc_password'):
		video_player.vlc_password = user_settings.get_value('video_player', 'vlc_password')
		_u("%VideoPlayer/VBox/VLCPassword/Input").text = video_player.vlc_password
	if user_settings.has_section_key('video_player', 'video_offset_ms'):
		_u("%VideoPlayer/VBox/VideoOffset/Input").value = user_settings.get_value('video_player', 'video_offset_ms')
	if user_settings.has_section_key('video_player', 'vlc_seek_correction'):
		_u("%VideoPlayer/VBox/VLCSeekCorrection/Input").value = user_settings.get_value('video_player', 'vlc_seek_correction')
	if user_settings.has_section_key('video_player', 'player_type'):
		var vp_type = user_settings.get_value('video_player', 'player_type')
		_u("%VideoPlayer/VBox/PlayerSelection").select(vp_type)
		video_player._on_player_selection_item_selected(vp_type)

	if user_settings.has_section_key('app_settings', 'mode'):
		_n("Menu").select_mode(user_settings.get_value('app_settings', 'mode'))
	else:
		_n("Menu").select_mode(1)


func apply_device_settings():
	var user_settings = app.user_settings
	if user_settings.has_section_key('speed_slider', 'max_speed'):
		var speed_value = user_settings.get_value('speed_slider', 'max_speed', 25000)
		_n("Settings/VBox/Sliders/MaxSpeed/Input").value = int(speed_value)

	if user_settings.has_section_key('accel_slider', 'max_acceleration'):
		var accel_value = user_settings.get_value('accel_slider', 'max_acceleration', 500000)
		_n("Settings/VBox/Sliders/MaxAcceleration/Input").value = int(accel_value)

	if user_settings.has_section_key('speed_slider', 'position_percent'):
		_n("SpeedPanel").set_speed_slider_pos(user_settings.get_value('speed_slider', 'position_percent', 0.6))
	else:
		_n("SpeedPanel").set_speed_slider_pos(0.6)

	if user_settings.has_section_key('accel_slider', 'position_percent'):
		_n("SpeedPanel").set_acceleration_slider_pos(user_settings.get_value('accel_slider', 'position_percent', 0.4))
	else:
		_n("SpeedPanel").set_acceleration_slider_pos(0.4)

	if user_settings.has_section_key('range_slider_min', 'position_percent'):
		_n("RangePanel").set_min_slider_pos(user_settings.get_value('range_slider_min', 'position_percent', 0))
	else:
		_n("RangePanel").set_min_slider_pos(0)

	if user_settings.has_section_key('range_slider_max', 'position_percent'):
		_n("RangePanel").set_max_slider_pos(user_settings.get_value('range_slider_max', 'position_percent', 1))
	else:
		_n("RangePanel").set_max_slider_pos(1)

	if user_settings.has_section_key('device_settings', 'syncing_speed'):
		_n("Settings/VBox/SyncingSpeed/Input").set_value_no_signal(int(user_settings.get_value('device_settings', 'syncing_speed', 1000)))

	if user_settings.has_section_key('device_settings', 'homing_trigger'):
		_n("Settings/VBox/HomingTrigger/Input").set_value_no_signal(float(user_settings.get_value('device_settings', 'homing_trigger', 1.5)))

	_n("SpeedPanel").send_speed_limits()
	_n("RangePanel").send_range_limits()


func check_root_directory():
	var dir = DirAccess.open(app.storage_dir)
	if not dir.dir_exists("OSSM Sauce"):
		dir.make_dir("OSSM Sauce")
	dir.change_dir("OSSM Sauce")
	for directory in ["Paths", "Playlists"]:
		if not dir.dir_exists(directory):
			dir.make_dir(directory)
