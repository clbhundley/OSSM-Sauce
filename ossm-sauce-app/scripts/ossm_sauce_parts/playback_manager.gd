extends RefCounted

var app
var _seeking: bool = false


func setup(app_owner):
	app = app_owner


func _websocket():
	return app.get_node("%WebSocket")


func _video_player():
	return app.get_node("%VideoPlayer")


func _action_panel():
	return app.get_node("ActionPanel")


func _circle_selection():
	return app.get_node("CircleSelection")


func _menu():
	return app.get_node("Menu")


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


func transition_to_path(next_index: int):
	var websocket = _websocket()
	var overreach_sent = maxi(app.marker_index - app.network_paths[app.active_path_index].size(), 0)
	var next_path = app.network_paths[next_index]
	app.active_path_index = next_index
	await display_active_path_index(false, false)
	app.marker_index = overreach_sent
	app.buffer_sent = overreach_sent
	while app.buffer_sent < 6 and app.marker_index < next_path.size():
		websocket.server.broadcast_binary(next_path[app.marker_index])
		app.marker_index += 1
		app.buffer_sent += 1
	var path_list = _menu().get_node("Playlist/Scroll/VBox")
	_menu().get_node("Playlist")._on_item_selected(path_list.get_child(next_index))
	path_list.get_child(next_index).set_active()


func display_active_path_index(pause := true, send_buffer := true):
	var websocket = _websocket()
	var action_panel = _action_panel()
	var paths_container = _paths_container()
	var path_area = _path_area()
	var ball = _ball()
	var video_player = _video_player()
	app.paused = pause
	app.frame = 0
	app.marker_index = 0
	app.play_offset_ms = 0
	_seek_slider().set_value_no_signal(0)
	update_time_display()
	if send_buffer:
		if websocket.ossm_connected:
			app.send_command(OSSM.Command.RESET)
			var start_depth: float = app.paths[app.active_path_index][0]
			app.home_to(round(start_depth * 10000))
			await app.homing_complete
			if not websocket.ossm_connected:
				return
			app.buffer_sent = 0
			while app.buffer_sent < 6 and app.marker_index < app.network_paths[app.active_path_index].size():
				websocket.server.broadcast_binary(app.network_paths[app.active_path_index][app.marker_index])
				app.marker_index += 1
				app.buffer_sent += 1
	else:
		app.marker_index = 6
		app.buffer_sent = 6

	action_panel.clear_selections()
	if pause:
		action_panel.get_node("Pause").hide()
		action_panel.get_node("Play").show()
	for path in paths_container.get_children():
		path.hide()
	var path = paths_container.get_child(app.active_path_index)
	path.position.x = (path_area.size.x / 2) + app.path_speed
	path.show()
	ball.position.y = render_depth(app.paths[app.active_path_index][0])
	ball.show()
	_path_display().show()
	if video_player.is_active() and AppMode.active == AppMode.MOVE:
		video_player.sync_seek(0.0)


func seek() -> void:
	var websocket = _websocket()
	var action_panel = _action_panel()
	var circle_selection = _circle_selection()
	var ball = _ball()
	var path_area = _path_area()
	var video_player = _video_player()
	if app.active_path_index == null or _seeking:
		return
	_seeking = true
	if not app.paused:
		app.paused = true
		app.send_command(OSSM.Command.PAUSE)
		action_panel.clear_selections()
		action_panel.get_node("Pause").hide()
		action_panel.get_node("Play").show()
		circle_selection.hide()

	var active_path = app.paths[app.active_path_index]
	if active_path.is_empty():
		_seeking = false
		return

	var value = _seek_slider().value
	var total_frames: int = active_path.size()
	var target_frame := clampi(roundi(value * (total_frames - 1)), 0, total_frames - 1)
	var target_depth: float = active_path[target_frame]
	app.play_offset_ms = int(target_frame * 1000.0 / app.ticks_per_second)

	var frames = app.marker_frames[app.active_path_index]
	var buffer_start := 0
	var cascade_index := 0
	for i in frames.size():
		if frames[i] <= target_frame:
			cascade_index = i
			buffer_start = i + 1
		else:
			break

	app.frame = target_frame
	var path_line = _paths_container().get_child(app.active_path_index)
	path_line.position.x = (path_area.size.x / 2) + app.path_speed - (target_frame * app.path_speed)
	ball.position.y = render_depth(target_depth)
	update_time_display()

	if websocket.ossm_connected:
		app.send_command(OSSM.Command.RESET)
		app.home_to(round(target_depth * 10000))
		await app.homing_complete
		if not websocket.ossm_connected:
			_seeking = false
			return
		var cascade_packet = app.network_paths[app.active_path_index][cascade_index]
		websocket.server.broadcast_binary(cascade_packet)
		app.marker_index = buffer_start
		app.buffer_sent = 0
		while app.buffer_sent < 6 and app.marker_index < app.network_paths[app.active_path_index].size():
			var packet = app.network_paths[app.active_path_index][app.marker_index]
			websocket.server.broadcast_binary(packet)
			app.marker_index += 1
			app.buffer_sent += 1

	if video_player.is_active():
		video_player.pause_and_seek(app.play_offset_ms / 1000.0)

	_seeking = false
	app._seek_dragging = false


func update_time_display():
	var total_frames: int = app.paths[app.active_path_index].size()
	var current_sec: int = app.frame / app.ticks_per_second
	var total_sec: int = (total_frames - 1) / app.ticks_per_second
	if total_sec >= 3600:
		_time_display().text = "%d:%02d:%02d / %d:%02d:%02d" % [
			current_sec / 3600, current_sec % 3600 / 60, current_sec % 60,
			total_sec / 3600, total_sec % 3600 / 60, total_sec % 60]
	else:
		_time_display().text = "%d:%02d / %d:%02d" % [
			current_sec / 60, current_sec % 60,
			total_sec / 60, total_sec % 60]


func render_depth(depth) -> float:
	return app.PATH_BOTTOM + depth * (app.PATH_TOP - app.PATH_BOTTOM)
