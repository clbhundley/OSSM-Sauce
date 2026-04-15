extends Control


func _on_gui_input(event):
	if event is InputEventMouseButton and owner.active_path_index != null:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				$Timer.start()
			elif event.is_released():
				$Timer.stop()


func _on_timer_timeout():
	if owner.paused:
		%CircleSelection.show_play()
	else:
		%CircleSelection.show_pause()
