extends Panel


func _on_play_button_pressed():
	flash_button($Play)
	$Timer.start()
	match AppMode.active:
		AppMode.MOVE:
			if owner.active_path_index == null:
				return
		AppMode.POSITION:
			%PositionControls.set_physics_process(true)
			%PositionControls.set_process_input(true)
		AppMode.LOOP:
			%LoopControls.active = true
			%LoopControls/Pause.hide()
		AppMode.VIBRATE:
			%VibrationControls.paused = false
			%VibrationControls.ui_enabled(true)
			%VibrationControls.set_process(true)
			%VibrationControls.set_process_input(true)
	$Play.hide()
	$Pause.show()
	$Pause/Selection.show()
	if %VideoPlayer.is_active() and AppMode.active == AppMode.MOVE:
		%VideoPlayer.sync_play()
	else:
		owner.play()


func _on_pause_button_pressed():
	flash_button($Pause)
	$Timer.stop()
	match AppMode.active:
		AppMode.POSITION:
			%PositionControls.set_physics_process(false)
			%PositionControls.set_process_input(false)
		AppMode.LOOP:
			%LoopControls.active = false
			%LoopControls/Pause.show()
		AppMode.VIBRATE:
			%VibrationControls.paused = true
			%VibrationControls.ui_enabled(false)
			%VibrationControls.set_process(false)
			%VibrationControls.set_process_input(false)
	$Pause.hide()
	$Play.show()
	$Play/Selection.show()
	if %VideoPlayer.is_active() and AppMode.active == AppMode.MOVE:
		%VideoPlayer.sync_pause()
	else:
		owner.pause()


func _on_speed_button_pressed():
	flash_button($Speed)
	$Timer.stop()
	%SpeedPanel.tween()
	hide()


func _on_range_button_pressed():
	flash_button($Range)
	$Timer.stop()
	%RangePanel.tween()
	hide()


func _on_menu_button_pressed():
	flash_button($Menu)
	$Timer.stop()
	%Menu.tween()
	hide()
	%Menu.show()


func flash_button(button: Node) -> void:
	clear_selections()
	self_modulate.a = 1.2
	%CircleSelection.hide_and_reset()
	button.get_node("Selection").show()


func disable_buttons(set_disabled: bool) -> void:
	for button: TextureButton in [
			$Play/Button,
			$Pause/Button,
			$Speed/Button,
			$Range/Button,
			$Menu/Button]:
		button.disabled = set_disabled


func _on_timer_timeout():
	self_modulate.a = 1
	clear_selections()


func clear_selections():
	for selection: TextureRect in [
			$Play/Selection,
			$Pause/Selection,
			$Speed/Selection,
			$Range/Selection,
			$Menu/Selection]:
		selection.hide()
