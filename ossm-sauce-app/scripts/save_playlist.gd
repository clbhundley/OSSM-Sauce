extends Control


func _on_text_edit_text_changed():
	var filter:Array = ['\\', '/', ':', '*', '?', '"', '<', '>', '|', '\n']
	var filtered_text:String = $TextEdit.text
	for character in filter:
		filtered_text = filtered_text.replace(character,"")
	if $TextEdit.text != filtered_text:
		$TextEdit.text = filtered_text
		$TextEdit.set_caret_column($TextEdit.text.length())
	if $TextEdit.text.length() > 0:
		$HBox/Save.disabled = false
	else:
		$HBox/Save.disabled = true


func _on_save_pressed():
	var filename:String = $TextEdit.text
	var file = owner.playlists_open_write(filename + ".bxpl")
	for path_name in %Menu/Playlist.get_items():
		file.store_line(path_name)
	file.close()
	show_menu_buttons()


func show_menu_buttons():
	var buttons = [
		%Menu/Main/PlaylistButtons,
		%Menu/Main/PathButtons,
		%Menu/Main/LoopAndVideoButtons,
		%Menu/PathControls,
		%Menu/Header,
		%Menu/Main/Mode]
	for button in buttons:
		button.show()
	%Menu.refresh_selection()
	hide()


func _on_back_pressed():
	show_menu_buttons()
