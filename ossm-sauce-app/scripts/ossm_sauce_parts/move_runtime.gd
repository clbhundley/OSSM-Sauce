extends RefCounted

var app


func setup(app_owner):
	app = app_owner


func _websocket():
	return app.get_node("%WebSocket")


func _video_player():
	return app.get_node("%VideoPlayer")


func _menu():
	return app.get_node("Menu")


func _circle_selection():
	return app.get_node("CircleSelection")


func _action_panel():
	return app.get_node("ActionPanel")


func _path_display():
	return app.get_node("PathDisplay")


func _path_area():
	return app.get_node("PathDisplay/PathArea")


func _paths_container():
	return app.get_node("PathDisplay/Paths")


func _ball():
	return app.get_node("PathDisplay/Ball")


func _seek_slider():
	return app.get_node("SeekSlider")


func _time_display():
	return app.get_node("TimeDisplay")


func physics_process(_delta: float) -> void:
	if app.paused or app.paths[app.active_path_index].is_empty():
		return

	var total_frames: int = app.paths[app.active_path_index].size()
	if app.frame >= total_frames - 1:
		if app.active_path_index < app.network_paths.size() - 1:
			app.transition_to_path(app.active_path_index + 1)
		elif _menu().loop_playlist:
			app.transition_to_path(0)
		else:
			app.paused = true
			send_command(OSSM.Command.PAUSE)
			_video_player().pause_player()
			_menu().show_play()
			_circle_selection().show_restart()
		return

	var frames = app.marker_frames[app.active_path_index]
	var active_path = app.network_paths[app.active_path_index]
	var current_marker = app.marker_index - app.buffer_sent
	if current_marker < frames.size() and app.frame == frames[current_marker]:
		if _websocket().server_started:
			if app.marker_index < active_path.size():
				_websocket().server.broadcast_binary(active_path[app.marker_index])
			elif app.active_path_index < app.network_paths.size() - 1:
				var overreach_index = app.marker_index - active_path.size()
				var next_path = app.network_paths[app.active_path_index + 1]
				if overreach_index < next_path.size():
					_websocket().server.broadcast_binary(next_path[overreach_index])
			elif _menu().loop_playlist:
				var overreach_index = app.marker_index - active_path.size()
				var next_path = app.network_paths[0]
				if overreach_index < next_path.size():
					_websocket().server.broadcast_binary(next_path[overreach_index])
		if current_marker < frames.size() - 1:
			app.marker_index += 1

	var depth: float = app.paths[app.active_path_index][app.frame]
	_paths_container().get_child(app.active_path_index).position.x -= app.path_speed
	_ball().position.y = app.render_depth(depth)
	if not app._seek_dragging:
		_seek_slider().set_value_no_signal(float(app.frame) / (total_frames - 1))
		app.update_time_display()
	app.frame += 1


func send_command(value: int):
	if _websocket().ossm_connected:
		var command: PackedByteArray
		command.resize(1)
		command[0] = value
		_websocket().server.broadcast_binary(command)


func home_to(target_position: int):
	if _websocket().ossm_connected:
		_circle_selection().show_hourglass()
		_action_panel().disable_buttons(true)
		var displays = [
			app.get_node("%PathDisplay"),
			app.get_node("%PositionControls"),
			app.get_node("%LoopControls"),
			app.get_node("%VibrationControls"),
			app.get_node("%BridgeControls"),
			app.get_node("%ActionPanel"),
			app.get_node("%VideoPlayer"),
			app.get_node("%Settings"),
			app.get_node("%AddFile"),
			app.get_node("%Menu")]
		for display in displays:
			display.modulate.a = 0.05
		var command: PackedByteArray
		command.resize(5)
		command.encode_u8(0, OSSM.Command.HOMING)
		command.encode_s32(1, abs(app.motor_direction * 10000 - target_position))
		_websocket().server.broadcast_binary(command)


func play():
	var command: PackedByteArray
	if AppMode.active == AppMode.MOVE and app.active_path_index != null:
		app.paused = false
		app.play_offset_ms = int(app.frame * 1000.0 / app.ticks_per_second)
	command.resize(6)
	command.encode_u8(0, OSSM.Command.PLAY)
	command.encode_u8(1, AppMode.active)
	command.encode_u32(2, app.play_offset_ms)
	if _websocket().ossm_connected:
		if AppMode.active == AppMode.MOVE:
			var safe_accel: PackedByteArray
			safe_accel.resize(5)
			safe_accel.encode_u8(0, OSSM.Command.SET_GLOBAL_ACCELERATION)
			safe_accel.encode_u32(1, 60000)
			_websocket().server.broadcast_binary(safe_accel)
		_websocket().server.broadcast_binary(command)
		_path_display().get_node("AccelTimer").start(0.8)


func pause():
	app.paused = true
	if not _websocket().ossm_connected:
		return
	send_command(OSSM.Command.PAUSE)

	if app.active_path_index == null:
		return
	if AppMode.active != AppMode.MOVE or app.paths[app.active_path_index].is_empty():
		return

	var current_depth: float = app.paths[app.active_path_index][app.frame]
	send_command(OSSM.Command.RESET)
	home_to(round(current_depth * 10000))
	await app.homing_complete
	if not _websocket().ossm_connected:
		return

	var frames = app.marker_frames[app.active_path_index]
	var buffer_start := 0
	var cascade_index := 0
	for i in frames.size():
		if frames[i] <= app.frame:
			cascade_index = i
			buffer_start = i + 1
		else:
			break

	_websocket().server.broadcast_binary(app.network_paths[app.active_path_index][cascade_index])
	app.marker_index = buffer_start
	app.buffer_sent = 0
	while app.buffer_sent < 6 and app.marker_index < app.network_paths[app.active_path_index].size():
		_websocket().server.broadcast_binary(app.network_paths[app.active_path_index][app.marker_index])
		app.marker_index += 1
		app.buffer_sent += 1

	var safe_accel: PackedByteArray
	safe_accel.resize(5)
	safe_accel.encode_u8(0, OSSM.Command.SET_GLOBAL_ACCELERATION)
	safe_accel.encode_u32(1, 60000)
	_websocket().server.broadcast_binary(safe_accel)
	var depth_val: int = abs(app.motor_direction * 10000 - round(current_depth * 10000))
	var nudge: PackedByteArray
	nudge.resize(10)
	nudge.encode_u8(0, OSSM.Command.SMOOTH_MOVE)
	nudge.encode_u8(7, 0)
	nudge.encode_u8(8, 0)
	nudge.encode_u8(9, 0)
	nudge.encode_u32(1, 100)
	nudge.encode_u16(5, clampi(depth_val + 500, 0, 10000))
	_websocket().server.broadcast_binary(nudge)
	await app.get_tree().create_timer(0.15).timeout
	nudge.encode_u16(5, clampi(depth_val - 500, 0, 10000))
	_websocket().server.broadcast_binary(nudge)
	await app.get_tree().create_timer(0.15).timeout
	nudge.encode_u16(5, clampi(depth_val, 0, 10000))
	_websocket().server.broadcast_binary(nudge)


func activate_move_mode():
	app.set_physics_process(true)
	app.get_node("%ActionPanel/Play").show()
	app.get_node("%ActionPanel/Pause").hide()
	app.get_node("%PathDisplay/Paths").show()
	app.get_node("%PathDisplay/Ball").show()
	_seek_slider().show()
	_time_display().show()
	app.get_node("%Menu/Main/PlaylistButtons").show()
	app.get_node("%Menu/Main/PathButtons").show()
	app.get_node("%Menu/Main/LoopAndVideoButtons/LoopPlaylistButton").show()
	app.get_node("%Menu/Main/LoopAndVideoButtons/VideoPlayerSync").show()
	app.get_node("%Menu/PathControls").show()
	app.get_node("%Menu/Playlist").show()
	if app.active_path_index != null:
		app.display_active_path_index()
	_menu().refresh_selection()


func deactivate_move_mode():
	app.set_physics_process(false)
	app.get_node("%ActionPanel/Play").hide()
	app.get_node("%ActionPanel/Pause").show()
	_path_display().hide()
	app.get_node("%PathDisplay/Paths").hide()
	_ball().hide()
	_seek_slider().hide()
	_time_display().hide()
	app.get_node("%Menu/Main/PlaylistButtons").hide()
	app.get_node("%Menu/Main/PathButtons").hide()
	app.get_node("%Menu/Main/LoopAndVideoButtons/LoopPlaylistButton").hide()
	app.get_node("%Menu/Main/LoopAndVideoButtons/VideoPlayerSync").hide()
	app.get_node("%Menu/PathControls").hide()
	app.get_node("%Menu/Playlist").hide()
