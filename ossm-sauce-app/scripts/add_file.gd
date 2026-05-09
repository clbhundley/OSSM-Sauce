extends Panel


func _ready() -> void:
	self_modulate.a = 2


func create_file_list(category: String, file_types: PackedStringArray):
	for file_name in owner.list_files(category, file_types):
		$FileList.add_item(file_name)


func show_paths():
	show()
	$FileList.clear()
	$FileList.mode = $FileList.Mode.PATH
	$HBox/AddPath.disabled = true
	$HBox/AddPath.show()
	$HBox/LoadPlaylist.hide()
	create_file_list("paths", [".bx", ".funscript"])
	$Label.text = owner.get_storage_label("paths")


func show_playlists():
	show()
	$FileList.clear()
	$FileList.mode = $FileList.Mode.PLAYLIST
	$HBox/LoadPlaylist.disabled = true
	$HBox/LoadPlaylist.show()
	$HBox/AddPath.hide()
	create_file_list("playlists", [".bxpl"])
	$Label.text = owner.get_storage_label("playlists")


func _on_add_path_pressed():
	var file_name: String = $FileList.get_item_text($FileList.selected_index)
	if owner.load_path(file_name):
		%Menu/Playlist.add_item(file_name)
	%Menu.show()
	hide()


func _on_load_playlist_pressed():
	var file_name: String = $FileList.get_item_text($FileList.selected_index)
	var file = owner.playlists_open_read(file_name)
	if not file:
		return
	%Menu/Playlist.clear()
	while file.get_position() < file.get_length():
		var line: String = file.get_line()
		if line.begins_with('delay(') and line.ends_with(')'):
			var begin_index = line.find("(") + 1
			var end_index = line.find(")") - begin_index
			var delay_duration = float(line.substr(begin_index, end_index))
			owner.create_delay(delay_duration)
		elif owner.load_path(line):
			%Menu/Playlist.add_item(line)
	owner.send_command(OSSM.Command.RESET)
	%Menu.show()
	hide()


func _on_back_pressed():
	%Menu.show()
	hide()
