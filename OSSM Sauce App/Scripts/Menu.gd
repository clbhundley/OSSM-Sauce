extends Panel

func _on_Back_pressed():
	tween(false)
	$Playlist.deselect_all()


func _on_Settings_pressed():
	%Settings.show()
	hide()


func _on_Exit_pressed():
	owner.user_settings.save(owner.cfg_path)
	get_tree().quit()


func _on_up_pressed():
	flash_button($PathControls/Up)
	var selected_index = $Playlist.selected_index
	if selected_index > 0:
		$Playlist.move_item(selected_index, selected_index - 1)


func _on_down_pressed():
	flash_button($PathControls/Down)
	var selected_index = $Playlist.selected_index
	if selected_index < $Playlist/Scroll/VBox.get_child_count() - 1:
		$Playlist.move_item(selected_index, selected_index + 1)


func _on_play_pressed():
	flash_button($PathControls/HBox/Play)
	tween(false)
	%ActionPanel.clear_selections()
	var index = $Playlist.selected_index
	if not owner.active_path_index == index:
		owner.active_path_index = index
		owner.display_active_path_index()
		$Playlist/Scroll/VBox.get_child(index).set_active()
		if owner.connected_to_ossm:
			%CircleSelection.show_hourglass()
			%PositionControls.modulate.a = 0.05
			owner.home_to(0)
			return
	%CircleSelection.show_play()


func _on_pause_pressed():
	owner.pause()
	%ActionPanel.clear_selections()
	%ActionPanel/Play.show()
	%ActionPanel/Pause.hide()
	refresh_selection()


func _on_restart_pressed():
	hide()
	%ActionPanel.show()
	flash_button($PathControls/HBox/Restart)
	owner.display_active_path_index()
	refresh_selection()
	if owner.connected_to_ossm:
		%CircleSelection.show_hourglass()
		%PathDisplay.modulate.a = 0.05
		owner.home_to(0)
	else:
		%CircleSelection.show_play()


func _on_delete_pressed():
	flash_button($PathControls/HBox/Delete)
	var selected_item = $Playlist.selected_index
	if owner.active_path_index == selected_item:
		owner.active_path_index = null
		$PathControls.hide()
		if not owner.paused:
			_on_pause_pressed()
	%PathDisplay/Paths.remove_child(%PathDisplay/Paths.get_child(selected_item))
	var pl_item = $Playlist/Scroll/VBox.get_child(selected_item)
	$Playlist/Scroll/VBox.remove_child(pl_item)
	owner.paths.remove_at(selected_item)
	owner.markers.remove_at(selected_item)
	owner.network_paths.remove_at(selected_item)
	$Playlist.selected_index = null
	if $Playlist/Scroll/VBox.get_child_count() == 0:
		$Main/PlaylistButtons/SavePlaylist.disabled = true
	refresh_selection()


func _on_load_playlist_pressed():
	%AddFile.show_playlists()
	hide()


func _on_save_playlist_pressed():
	hide_menu_buttons()
	$SavePlaylist.show()
	$Header.hide()


func _on_add_path_pressed():
	%AddFile.show_paths()
	hide()


func _on_add_delay_pressed():
	hide_menu_buttons()
	$AddDelay.show()
	$Header.hide()


func hide_menu_buttons():
	$Main/PlaylistButtons.hide()
	$Main/PathButtons.hide()
	$Main/LoopPlaylistButton.hide()
	$PathControls.hide()
	$Main/Mode.hide()


func refresh_selection():
	if $Main/Mode.selected != 0:
		return
	var selected_item = $Playlist.selected_index
	if selected_item != null:
		var item = $Playlist/Scroll/VBox.get_child(selected_item)
		$Playlist._on_item_selected(item)
	else:
		$PathControls.hide()


func show_play():
	$PathControls/HBox/Pause.hide()
	$PathControls/HBox/Play.show()
	$PathControls.show()


func show_pause():
	$PathControls/HBox/Pause.show()
	$PathControls/HBox/Play.hide()
	$PathControls.show()


func flash_button(button:Node):
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	var start_color:Color = Color.DARK_ORANGE
	var end_color:Color = Color.WHITE
	tween.tween_method(button.set_self_modulate, start_color, end_color, 0.6)


@onready var buttons:Array = [
	$PathControls/Up,
	$PathControls/Down,
	$PathControls/HBox/Play,
	$PathControls/HBox/Pause,
	$PathControls/HBox/Restart,
	$PathControls/HBox/Delete]

const ANIM_TIME = 0.35
func tween(activating:bool = true):
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_parallel()
	var start_color:Color = modulate
	var end_color:Color = start_color
	start_color.a = 0
	end_color.a = 1
	var colors:Array = [start_color, end_color]
	if activating:
		refresh_selection()
	else:
		for button in buttons:
			button.disabled = true
		colors.reverse()
		%ActionPanel.show()
		tween.tween_callback(anim_finished).set_delay(ANIM_TIME)
	tween.tween_method(set_modulate, colors[0], colors[1], ANIM_TIME)


func anim_finished():
	for button in buttons:
		button.disabled = false
	%ActionPanel/Menu/Selection.hide()
	hide()


var loop_playlist:bool
func _on_loop_playlist_button_toggled(toggled_on: bool) -> void:
	loop_playlist = toggled_on
	if toggled_on:
		$Main/LoopPlaylistButton.text = "Loop Playlist: ON"
	else:
		$Main/LoopPlaylistButton.text = "Loop Playlist: OFF"


func set_min_stroke_duration(value):
	$LoopSettings/MinStrokeDuration/SpinBox.set_value(value)


func set_max_stroke_duration(value):
	$LoopSettings/MaxStrokeDuration/SpinBox.set_value(value)


func set_stroke_duration_display_mode(value):
	$LoopSettings/DisplayMode/OptionButton.select(value)
	_on_stroke_duration_display_mode_changed(value)


func _on_min_stroke_duration_changed(value):
	owner.min_stroke_duration = value
	%LoopControls.reset_stroke_duration_sliders()
	owner.user_settings.set_value('stroke_settings', 'min_duration', value)


func _on_max_stroke_duration_changed(value):
	owner.max_stroke_duration = value
	%LoopControls.reset_stroke_duration_sliders()
	owner.user_settings.set_value('stroke_settings', 'max_duration', value)


func _on_stroke_duration_display_mode_changed(index):
	owner.user_settings.set_value('stroke_settings', 'display_mode', index)
	%LoopControls.update_stroke_duration_text()


func select_mode(index):
	$Main/Mode.select(index)
	_on_mode_selected(index)


func _on_mode_selected(index:int):
	var mode_id:int = $Main/Mode.get_item_id(index)
	owner.app_mode = mode_id
	owner.user_settings.set_value('app_settings', 'mode', index)
	owner.send_command(owner.CommandType.RESET)
	owner.home_to(0)
	if owner.connected_to_ossm:
		await owner.homing_complete
	match mode_id:
		owner.Mode.MOVE:
			owner.set_physics_process(true)
			%PositionControls.set_physics_process(false)
			%LoopControls/In.set_physics_process(false)
			%LoopControls/Out.set_physics_process(false)
			%ActionPanel.clear_selections()
			%ActionPanel/Play.show()
			%ActionPanel/Pause.hide()
			%PositionControls.hide()
			%LoopControls.hide()
			$LoopSettings.hide()
			%PathDisplay/Paths.show()
			%PathDisplay/Ball.show()
			$Main/PlaylistButtons.show()
			$Main/PathButtons.show()
			$Main/LoopPlaylistButton.show()
			$PathControls.show()
			$Playlist.show()
			if owner.active_path_index != null:
				owner.display_active_path_index()
			refresh_selection()
		
		owner.Mode.POSITION:
			owner.paused = true
			owner.set_physics_process(false)
			%LoopControls/In.set_physics_process(false)
			%LoopControls/Out.set_physics_process(false)
			var min_pos = %PositionControls.min_range
			%PositionControls.touch_pos = min_pos
			%PositionControls.last_position = 0
			%PositionControls/MovementBar/Slider.position.y = min_pos
			%PositionControls.set_physics_process(true)
			%PositionControls.set_process_input(true)
			%ActionPanel.clear_selections()
			%ActionPanel/Play.hide()
			%ActionPanel/Pause.show()
			%PositionControls.show()
			%LoopControls.hide()
			$LoopSettings.hide()
			%PathDisplay/Paths.hide()
			%PathDisplay/Ball.hide()
			$Main/PlaylistButtons.hide()
			$Main/PathButtons.hide()
			$Main/LoopPlaylistButton.hide()
			$PathControls.hide()
			$Playlist.hide()
			owner.play()
		
		owner.Mode.LOOP:
			owner.paused = true
			owner.set_physics_process(false)
			%PositionControls.set_physics_process(false)
			var stop_pos = %LoopControls/In.slider_max_pos
			%LoopControls/In.touch_pos = stop_pos
			%LoopControls/Out.touch_pos = stop_pos
			%LoopControls/In/StrokeDurationSlider/Slider.position.y = stop_pos
			%LoopControls/Out/StrokeDurationSlider/Slider.position.y = stop_pos
			%LoopControls/In.stroke_duration = 0
			%LoopControls/Out.stroke_duration = 0
			%LoopControls.update_stroke_duration_text()
			%LoopControls/In.set_physics_process(true)
			%LoopControls/Out.set_physics_process(true)
			%LoopControls/In.input_active = false
			%LoopControls/Out.input_active = false
			%LoopControls.active = false
			%LoopControls/Pause.hide()
			%ActionPanel.clear_selections()
			%ActionPanel/Play.hide()
			%ActionPanel/Pause.show()
			%PositionControls.hide()
			%LoopControls.show()
			$LoopSettings.show()
			%PathDisplay/Paths.hide()
			%PathDisplay/Ball.hide()
			$Main/PlaylistButtons.hide()
			$Main/PathButtons.hide()
			$Main/LoopPlaylistButton.hide()
			$PathControls.hide()
			$Playlist.hide()
