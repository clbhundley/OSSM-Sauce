extends Panel

enum {MIN_RANGE, MAX_RANGE}

var min_range_pos: float
var max_range_pos: float
var min_range_limit: int
var max_range_limit: int

@onready var min_slider: TextureRect = $RangeBar/MinSlider
@onready var max_slider: TextureRect = $RangeBar/MaxSlider


func _ready():
	$LabelTop.self_modulate.a = 0
	$LabelBot.self_modulate.a = 0
	$BackTexture.self_modulate.a = 0
	$BackTexture.show()
	min_range_pos = min_slider.position.y
	max_range_pos = max_slider.position.y


func _on_min_slider_gui_input(event):
	if 'relative' in event and event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_LEFT:
			var drag_pos = min_slider.position.y + event.relative.y
			var max_range = max_slider.position.y + max_slider.size.y
			min_slider.position.y = clamp(drag_pos, max_range, min_range_pos)
			if AppMode.active == AppMode.POSITION:
				update_min_range(true)
			else:
				update_min_range()


func _on_max_slider_gui_input(event):
	if 'relative' in event and event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_LEFT:
			var drag_pos = max_slider.position.y + event.relative.y
			var min_range = min_slider.position.y - min_slider.size.y
			max_slider.position.y = clamp(drag_pos, max_range_pos, min_range)
			if AppMode.active == AppMode.POSITION:
				update_max_range(true)
			else:
				update_max_range()


func update_min_range(label_only := false):
	var slider_pos = min_slider.position.y
	min_range_limit = round(remap(slider_pos, min_range_pos, max_range_pos, 0, 10000))
	var percent = remap(slider_pos, min_range_pos, max_range_pos, 0, 1)
	if not label_only:
		owner.user_settings.set_value('range_slider_min', 'position_percent', percent)
		if $DebounceTimer.is_stopped():
			$DebounceTimer.start()
	$LabelBot.text = "Min Position:\n" + str(snapped(percent * 100, 0.01)) + "%"


func update_max_range(label_only := false):
	var slider_pos = max_slider.position.y
	max_range_limit = round(remap(slider_pos, min_range_pos, max_range_pos, 0, 10000))
	var percent = remap(slider_pos, min_range_pos, max_range_pos, 0, 1)
	if not label_only:
		owner.user_settings.set_value('range_slider_max', 'position_percent', percent)
		if $DebounceTimer.is_stopped():
			$DebounceTimer.start()
	$LabelTop.text = "Max Position:\n" + str(snapped(percent * 100, 0.01)) + "%"


func send_range_limits():
	if %WebSocket.ossm_connected:
		var command:PackedByteArray
		command.resize(4)
		command.encode_u8(0, OSSM.Command.SET_RANGE_LIMIT)
		command.encode_u8(1, MIN_RANGE if owner.motor_direction == 0 else MAX_RANGE)
		command.encode_u16(2, abs(owner.motor_direction * 10000 - min_range_limit))
		%WebSocket.server.broadcast_binary(command)
		command = PackedByteArray()
		command.resize(4)
		command.encode_u8(0, OSSM.Command.SET_RANGE_LIMIT)
		command.encode_u8(1, MAX_RANGE if owner.motor_direction == 0 else MIN_RANGE)
		command.encode_u16(2, abs(owner.motor_direction * 10000 - max_range_limit))
		%WebSocket.server.broadcast_binary(command)
		if AppMode.active == AppMode.VIBRATE:
			if %VibrationControls.pulse_active:
				%VibrationControls.pulse_controller()
			else:
				%VibrationControls.send_vibrate_command()


func set_min_slider_pos(percent):
	var slider_map = remap(
			percent,
			0,
			1,
			min_range_pos,
			max_range_pos)
	min_slider.position.y = slider_map
	update_min_range(true)


func set_max_slider_pos(percent):
	var slider_map = remap(
			percent,
			0,
			1,
			min_range_pos,
			max_range_pos)
	max_slider.position.y = slider_map
	update_max_range(true)


func tween(activating:bool = true):
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_parallel()
	var viewport_right_edge = get_viewport_rect().size.x
	var viewport_middle = get_viewport_rect().size.x / 2
	var outside_pos := Vector2(viewport_right_edge, position.y)
	var inside_pos := Vector2(viewport_middle, outside_pos.y)
	var positions: Array = [outside_pos, inside_pos]
	if not activating:
		positions.reverse()
	tween.tween_method(set_position, position, positions[1], owner.ANIM_TIME)
	var start_color: Color = $BackTexture.self_modulate
	var end_color: Color = start_color
	start_color.a = 0
	end_color.a = 1
	var colors: Array = [start_color, end_color]
	if not activating:
		colors.reverse()
		$BackButton.hide()
		tween.tween_callback(anim_finished).set_delay(owner.ANIM_TIME)
	else:
		$BackButton.show()
	var visuals = [$BackTexture, $LabelBot, $LabelTop]
	for node in visuals:
		tween.tween_method(
				node.set_self_modulate,
				colors[0],
				colors[1],
				owner.ANIM_TIME)


func anim_finished():
	%ActionPanel/Range/Selection.hide()
	%ActionPanel.self_modulate.a = 1
	$BackButton.hide()


func _on_back_button_pressed():
	if %WebSocket.ossm_connected and AppMode.active == AppMode.POSITION:
		update_min_range()
		update_max_range()
		$DebounceTimer.stop()
		send_range_limits()
		%CircleSelection.show_hourglass()
		%PositionControls.modulate.a = 0.05
		owner.home_to(abs(owner.motor_direction * 10000 - %PositionControls.last_position))
	$BackButton.hide()
	tween(false)
	%ActionPanel.show()
