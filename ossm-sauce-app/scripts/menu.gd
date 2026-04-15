extends Panel


func _on_Back_pressed():
	tween(false)
	$Playlist.deselect_all()


func _on_Settings_pressed():
	%Settings.show()
	hide()


func _on_Exit_pressed():
	owner.exit()
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
		if %WebSocket.ossm_connected:
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
	if %VideoPlayer.is_active() and AppMode.active == AppMode.MOVE:
		%VideoPlayer.sync_seek(0.0)
	if not %WebSocket.ossm_connected:
		%CircleSelection.show_play()


func _on_delete_pressed():
	flash_button($PathControls/HBox/Delete)
	var selected_item = $Playlist.selected_index
	if owner.active_path_index == selected_item:
		owner.paused = true
		owner.active_path_index = null
		$PathControls.hide()
		%ActionPanel.clear_selections()
		%ActionPanel/Play.show()
		%ActionPanel/Pause.hide()
		owner.send_command(OSSM.Command.PAUSE)
		owner.send_command(OSSM.Command.RESET)
		owner.home_to(0)
	elif owner.active_path_index != null and selected_item < owner.active_path_index:
		owner.active_path_index -= 1
	%PathDisplay/Paths.remove_child(%PathDisplay/Paths.get_child(selected_item))
	var pl_item = $Playlist/Scroll/VBox.get_child(selected_item)
	$Playlist/Scroll/VBox.remove_child(pl_item)
	owner.paths.remove_at(selected_item)
	owner.marker_frames.remove_at(selected_item)
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
	$Main/LoopAndVideoButtons.hide()
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
	var start_color := Color.DARK_ORANGE
	var end_color := Color.WHITE
	tween.tween_method(button.set_self_modulate, start_color, end_color, 0.6)


@onready var buttons:Array = [
	$PathControls/Up,
	$PathControls/Down,
	$PathControls/HBox/Play,
	$PathControls/HBox/Pause,
	$PathControls/HBox/Restart,
	$PathControls/HBox/Delete]

const ANIM_TIME = 0.35
func tween(activating: bool = true):
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_parallel()
	var start_color: Color = modulate
	var end_color: Color = start_color
	start_color.a = 0
	end_color.a = 1
	var colors: Array = [start_color, end_color]
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


var loop_playlist: bool
func _on_loop_playlist_button_toggled(toggled_on: bool) -> void:
	loop_playlist = toggled_on
	if toggled_on:
		$Main/LoopAndVideoButtons/LoopPlaylistButton.text = "Loop Playlist: ON"
	else:
		$Main/LoopAndVideoButtons/LoopPlaylistButton.text = "Loop Playlist: OFF"


func _on_video_player_sync_pressed() -> void:
	%VideoPlayer.show()


func set_min_stroke_duration(value):
	$LoopSettings/MinStrokeDuration/Input.set_value(value)


func set_max_stroke_duration(value):
	$LoopSettings/MaxStrokeDuration/Input.set_value(value)


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


func _on_bridge_mode_selected(index: int) -> void:
	%Menu/BridgeSettings/BPIO.hide()
	%Menu/BridgeSettings/XToys.hide()
	%Menu/BridgeSettings/MCP.hide()
	
	%BridgeControls/Smoothing/Label.self_modulate.a = 1
	%BridgeControls/Smoothing/TransType.disabled = false
	
	%Menu/BridgeSettings/SpeedOverrides/Label.self_modulate.a = 1
	%Menu/BridgeSettings/SpeedOverrides/Inputs/MinMoveDuration/Label.self_modulate.a = 1
	%Menu/BridgeSettings/SpeedOverrides/Inputs/MinMoveDuration/Input.editable = true
	%Menu/BridgeSettings/SpeedOverrides/Inputs/MaxMoveDuration/Label.self_modulate.a = 1
	%Menu/BridgeSettings/SpeedOverrides/Inputs/MaxMoveDuration/Input.editable = true
	
	match index:
		0:  # Buttplug.io
			%Menu/BridgeSettings/BPIO.show()
		1:  # XToys
			%Menu/BridgeSettings/XToys.show()
		2:  # MCP
			%Menu/BridgeSettings/MCP.show()
			%BridgeControls/Smoothing/Label.self_modulate.a = 0.4
			%BridgeControls/Smoothing/TransType.disabled = true
			%Menu/BridgeSettings/SpeedOverrides/Label.self_modulate.a = 0.4
			%Menu/BridgeSettings/SpeedOverrides/Inputs/MinMoveDuration/Label.self_modulate.a = 0.4
			%Menu/BridgeSettings/SpeedOverrides/Inputs/MinMoveDuration/Input.editable = false
			%Menu/BridgeSettings/SpeedOverrides/Inputs/MaxMoveDuration/Label.self_modulate.a = 0.4
			%Menu/BridgeSettings/SpeedOverrides/Inputs/MaxMoveDuration/Input.editable = false
	
	%BridgeControls.activate()
	owner.user_settings.set_value('bridge_settings', 'bridge_mode', index)


func _on_mode_selected(index: int):
	AppMode.active = $Main/Mode.get_item_id(index)
	owner.user_settings.set_value('app_settings', 'mode', index)
	owner.send_command(OSSM.Command.RESET)
	if AppMode.active == AppMode.VIBRATE:
		owner.home_to(1500)
	else:
		owner.home_to(0)
	if %WebSocket.ossm_connected:
		await owner.homing_complete
	owner.paused = true
	%ActionPanel.clear_selections()
	# Deactivate all modes, then activate the selected one
	owner.deactivate_move_mode()
	%BridgeControls.deactivate()
	%PositionControls.deactivate()
	%LoopControls.deactivate()
	%VibrationControls.deactivate()
	match AppMode.active:
		AppMode.MOVE:
			owner.activate_move_mode()
		AppMode.POSITION:
			%PositionControls.activate()
		AppMode.LOOP:
			%LoopControls.activate()
		AppMode.VIBRATE:
			%VibrationControls.activate()
		AppMode.BRIDGE:
			%BridgeControls.activate()
