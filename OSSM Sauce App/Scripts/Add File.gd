extends Panel


func create_file_list(directory:String, file_types:PackedStringArray):
	var dir = DirAccess.open(directory)
	for file_name in dir.get_files():
		for type in file_types:
			if file_name.ends_with(type):
				$FileList.add_item(file_name)


func show_paths():
	show()
	$FileList.clear()
	$FileList.mode = $FileList.Mode.PATH
	$HBox/AddPath.disabled = true
	$HBox/AddPath.show()
	$HBox/LoadPlaylist.hide()
	create_file_list(owner.paths_dir, [".bx", ".funscript"])
	if OS.get_name() == 'Android':
		$Label.text = "Internal Storage/OSSM Sauce/Paths"
	else:
		$Label.text = "Documents/OSSM Sauce/Paths"


func show_playlists():
	show()
	$FileList.clear()
	$FileList.mode = $FileList.Mode.PLAYLIST
	$HBox/LoadPlaylist.disabled = true
	$HBox/LoadPlaylist.show()
	$HBox/AddPath.hide()
	create_file_list(owner.playlists_dir, [".bxpl"])
	if OS.get_name() == 'Android':
		$Label.text = "Internal Storage/OSSM Sauce/Playlists"
	else:
		$Label.text = "Documents/OSSM Sauce/Playlists"


func _on_path_list_item_selected(index):
	$HBox/AddPath.disabled = false


func _on_add_path_pressed():
	var file_name:String = $FileList.get_item_text($FileList.selected_index)
	if owner.load_path(file_name):
		%Menu/Playlist.add_item(file_name)
	%Menu.show()
	hide()


func _on_load_playlist_pressed():
	var file_name:String = $FileList.get_item_text($FileList.selected_index)
	var file = FileAccess.open(owner.playlists_dir + file_name, FileAccess.READ)
	if not file:
		return
	%Menu/Playlist.clear()
	while file.get_position() < file.get_length():
		var line:String = file.get_line()
		if line.begins_with('delay(') and line.ends_with(')'):
			var begin_index = line.find("(") + 1
			var end_index = line.find(")") - begin_index
			var delay_duration = float(line.substr(begin_index, end_index))
			owner.create_delay(delay_duration)
		elif owner.load_path(line):
			%Menu/Playlist.add_item(line)
	owner.send_command(owner.CommandType.RESET)
	%Menu.show()
	hide()


func _on_back_pressed():
	%Menu.show()
	hide()
