extends RefCounted

var app


func setup(app_owner):
	app = app_owner


func _video_player():
	return app.get_node("%VideoPlayer")


func _action_panel():
	return app.get_node("%ActionPanel")


func _circle_selection():
	return app.get_node("%CircleSelection")


func _path_area():
	return app.get_node("PathDisplay/PathArea")


func _paths_container():
	return app.get_node("PathDisplay/Paths")


func _ball():
	return app.get_node("PathDisplay/Ball")


func _seek_slider():
	return app.get_node("SeekSlider")


func on_video_player_played(video_time_seconds: float, from_stopped: bool):
	print("[ossm] _on_video_player_played: paused=", app.paused, " mode=", AppMode.active, " index=", app.active_path_index)
	if app.active_path_index == null or AppMode.active != AppMode.MOVE:
		return
	if not app.paused:
		return
	if from_stopped:
		var path_time = float(app.frame) / app.ticks_per_second
		_video_player().pause_and_seek(path_time)
		return
	var total_frames: int = app.paths[app.active_path_index].size()
	if total_frames == 0:
		return

	var target_frame = clampi(int(video_time_seconds * app.ticks_per_second), 0, total_frames - 1)
	app.frame = target_frame

	var frames = app.marker_frames[app.active_path_index]
	var cascade_index := 0
	for i in frames.size():
		if frames[i] <= target_frame:
			cascade_index = i
		else:
			break
	app.marker_index = mini(cascade_index + 1 + app.buffer_sent, app.network_paths[app.active_path_index].size())

	var path_line = _paths_container().get_child(app.active_path_index)
	path_line.position.x = (_path_area().size.x / 2) + app.path_speed - (target_frame * app.path_speed)
	_ball().position.y = app.render_depth(app.paths[app.active_path_index][target_frame])
	_seek_slider().set_value_no_signal(float(target_frame) / (total_frames - 1))
	app.update_time_display()

	_action_panel().clear_selections()
	_action_panel().get_node("Play").hide()
	_action_panel().get_node("Pause").show()
	_circle_selection().hide()
	print("[ossm] calling play()")
	app.play()


func on_video_player_paused():
	print("[ossm] _on_video_player_paused: paused=", app.paused, " mode=", AppMode.active)
	if AppMode.active != AppMode.MOVE:
		return
	if app.paused:
		return
	_action_panel().clear_selections()
	_action_panel().get_node("Pause").hide()
	_action_panel().get_node("Play").show()
	print("[ossm] calling pause()")
	app.pause()


func on_video_player_seeked(video_time_seconds: float):
	print("[ossm] _on_video_player_seeked: t=", video_time_seconds, " mode=", AppMode.active)
	if app.active_path_index == null or AppMode.active != AppMode.MOVE:
		return
	var total_frames: int = app.paths[app.active_path_index].size()
	if total_frames == 0:
		return
	var target_frame = clampi(int(video_time_seconds * app.ticks_per_second), 0, total_frames - 1)
	_seek_slider().set_value_no_signal(float(target_frame) / (total_frames - 1))
	app.seek()
