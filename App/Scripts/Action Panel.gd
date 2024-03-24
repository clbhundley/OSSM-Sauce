extends Panel

func _on_play_button_pressed():
	clear_selections()
	self_modulate.a = 1.2
	%CircleSelection.hide_and_reset()
	$Play/Selection.show()
	$Timer.start()
	match owner.app_mode:
		owner.Mode.PATH:
			if owner.active_path_index != null:
				owner.paused = false
				$Play.hide()
				$Pause/Selection.show()
				$Pause.show()
		owner.Mode.LOOP:
			%LoopControls.active = true
			%LoopControls.send_command()
			%LoopControls/Pause.hide()
			$Play.hide()
			$Pause/Selection.show()
			$Pause.show()

func _on_pause_button_pressed():
	match owner.app_mode:
		owner.Mode.PATH:
			clear_selections()
			self_modulate.a = 1.2
			%CircleSelection.hide_and_reset()
			$Pause/Selection.show()
			owner.paused = true
			$Timer.stop()
			$Pause.hide()
			$Play/Selection.show()
			$Play.show()
		owner.Mode.LOOP:
			if owner.connected_to_server:
				owner.websocket.send_text("L0")
			%LoopControls.active = false
			%LoopControls/Pause.show()
			$Play.show()
			$Play/Selection.show()
			$Pause.hide()

func _on_speed_button_pressed():
	clear_selections()
	self_modulate.a = 1.2
	%CircleSelection.hide_and_reset()
	$Speed/Selection.show()
	%SpeedPanel.tween()
	$Timer.stop()
	hide()

func _on_range_button_pressed():
	clear_selections()
	self_modulate.a = 1.2
	%CircleSelection.hide_and_reset()
	$Range/Selection.show()
	%RangePanel.tween()
	$Timer.stop()
	hide()

func _on_menu_button_pressed():
	clear_selections()
	self_modulate.a = 1.2
	%CircleSelection.hide_and_reset()
	$Menu/Selection.show()
	%Menu.tween()
	$Timer.stop()
	hide()
	%Menu.show()

func _on_timer_timeout():
	self_modulate.a = 1
	clear_selections()

func clear_selections():
	for button in get_children():
		if button.has_node('Selection'):
			button.get_node('Selection').hide()
