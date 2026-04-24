extends RefCounted

var app


func setup(app_owner):
	app = app_owner


func _menu():
	return app.get_node("Menu")


func _playlist():
	return app.get_node("Menu/Playlist")


func _path_controls():
	return app.get_node("Menu/PathControls")


func _action_panel():
	return app.get_node("%ActionPanel")


func _path_display():
	return app.get_node("%PathDisplay")


func _paths_container():
	return app.get_node("%PathDisplay/Paths")


func _playlist_buttons():
	return app.get_node("%Menu/Main/PlaylistButtons")


func move_selected(delta: int):
	var selected_index = _playlist().selected_index
	if selected_index == null:
		return
	var new_index = selected_index + delta
	if new_index < 0 or new_index >= _playlist().get_item_count():
		return
	move_item(selected_index, new_index)


func move_item(current_index: int, new_index: int):
	_playlist().move_item_ui(current_index, new_index)

	var path_data = app.paths[current_index]
	app.paths.remove_at(current_index)
	app.paths.insert(new_index, path_data)

	var marker_data = app.marker_frames[current_index]
	app.marker_frames.remove_at(current_index)
	app.marker_frames.insert(new_index, marker_data)

	var network_data = app.network_paths[current_index]
	app.network_paths.remove_at(current_index)
	app.network_paths.insert(new_index, network_data)

	if app.active_path_index == current_index:
		app.active_path_index = new_index
	elif app.active_path_index == new_index:
		app.active_path_index = current_index


func delete_selected_item():
	var selected_item = _playlist().selected_index
	if selected_item == null:
		return

	if app.active_path_index == selected_item:
		app.paused = true
		app.active_path_index = null
		_path_controls().hide()
		_action_panel().clear_selections()
		_action_panel().get_node("Play").show()
		_action_panel().get_node("Pause").hide()
		app.send_command(OSSM.Command.PAUSE)
		app.send_command(OSSM.Command.RESET)
		app.home_to(0)
	elif app.active_path_index != null and selected_item < app.active_path_index:
		app.active_path_index -= 1

	_paths_container().remove_child(_paths_container().get_child(selected_item))
	_playlist().remove_item_ui(selected_item)
	app.paths.remove_at(selected_item)
	app.marker_frames.remove_at(selected_item)
	app.network_paths.remove_at(selected_item)
	_playlist().selected_index = null
	if _playlist().get_item_count() == 0:
		_playlist_buttons().get_node("SavePlaylist").disabled = true
	_menu().refresh_selection()


func add_path_file(file_name: String) -> bool:
	if not app.load_path(file_name):
		return false
	_playlist().add_item(file_name)
	return true


func load_playlist_file(file_name: String):
	var file = FileAccess.open(app.playlists_dir + file_name, FileAccess.READ)
	if not file:
		return
	clear_playlist()
	while file.get_position() < file.get_length():
		var line: String = file.get_line()
		if line.begins_with('delay(') and line.ends_with(')'):
			var begin_index = line.find("(") + 1
			var end_index = line.find(")") - begin_index
			var delay_duration = float(line.substr(begin_index, end_index))
			app.create_delay(delay_duration)
		elif app.load_path(line):
			_playlist().add_item(line)
	app.send_command(OSSM.Command.RESET)


func save_playlist(filename: String):
	var path: String = app.playlists_dir + "/" + filename + ".bxpl"
	var file = FileAccess.open(path, FileAccess.WRITE)
	for path_name in _playlist().get_items():
		file.store_line(path_name)
	file.close()


func clear_playlist():
	if app.active_path_index != null:
		app.active_path_index = null
		_path_controls().hide()
		if not app.paused:
			_menu()._on_pause_pressed()
	app.paths.clear()
	app.marker_frames.clear()
	app.network_paths.clear()
	_playlist().clear_ui()
	for path in _paths_container().get_children():
		_paths_container().remove_child(path)
	_path_display().get_node("Ball").hide()
