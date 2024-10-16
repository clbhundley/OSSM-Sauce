extends Control


func _ready():
	$AnimationPlayer.play('Spin')


var homing_lock:bool
var restart_ready:bool
func _on_inside_button_pressed():
	if homing_lock:
		return
	if restart_ready:
		hide()
		owner.active_path_index = 0
		%Menu/Playlist/Scroll/VBox.get_child(0).set_active()
		%Menu._on_restart_pressed()
		restart_ready = false
		return
	elif owner.paused:
		owner.play()
		%ActionPanel/Pause/Selection.hide()
		%ActionPanel/Pause.show()
		%ActionPanel/Play.hide()
	else:
		owner.pause()
		%ActionPanel/Play/Selection.hide()
		%ActionPanel/Pause.hide()
		%ActionPanel/Play.show()
	hide()


func _on_outside_button_pressed():
	if homing_lock:
		return
	elif restart_ready:
		restart_ready = false
	hide()


func hide_and_reset():
	restart_ready = false
	hide()


func show_pause():
	$Hourglass.hide()
	$Restart.hide()
	$Pause.show()
	$Play.hide()
	show()


func show_play():
	$Hourglass.hide()
	$Restart.hide()
	$Pause.hide()
	$Play.show()
	show()


func show_restart():
	restart_ready = true
	$Hourglass.hide()
	$Restart.show()
	$Pause.hide()
	$Play.hide()
	show()


func show_hourglass():
	print_stack()
	homing_lock = true
	$Hourglass.show()
	$Restart.hide()
	$Pause.hide()
	$Play.hide()
	show()
