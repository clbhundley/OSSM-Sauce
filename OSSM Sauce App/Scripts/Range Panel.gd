extends Panel

var min_range_pos:float
var max_range_pos:float

@onready var min_slider:TextureRect = $RangeBar/MinSlider
@onready var max_slider:TextureRect = $RangeBar/MaxSlider


func _ready():
	$LabelTop.self_modulate.a = 0
	$LabelBot.self_modulate.a = 0
	$BackTexture.self_modulate.a = 0
	$BackTexture.self_modulate.a = 0
	$BackButton.hide()
	min_slider.connect('gui_input', min_slider_gui_input)
	max_slider.connect('gui_input', max_slider_gui_input)
	min_range_pos = min_slider.position.y
	max_range_pos = max_slider.position.y


func min_slider_gui_input(event):
	if 'relative' in event and event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_LEFT:
			var drag_pos = min_slider.position.y + event.relative.y
			var max_range = max_slider.position.y + max_slider.size.y
			min_slider.position.y = clamp(drag_pos, max_range, min_range_pos)
			if %Menu/Main/Mode.selected != 1:
				update_min_range()
				if owner.app_mode == 5:
					if %VibrationControls.pulse_active:
						%VibrationControls.pulse_controller()
					else:
						%VibrationControls.send_vibrate_command()


func max_slider_gui_input(event):
	if 'relative' in event and event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_LEFT:
			var drag_pos = max_slider.position.y + event.relative.y
			var min_range = min_slider.position.y - min_slider.size.y
			max_slider.position.y = clamp(drag_pos, max_range_pos, min_range)
			if %Menu/Main/Mode.selected != 1:
				update_max_range()
				if owner.app_mode == 5:
					if %VibrationControls.pulse_active:
						%VibrationControls.pulse_controller()
					else:
						%VibrationControls.send_vibrate_command()


func update_min_range():
	var slider_pos = min_slider.position.y
	var range_map = remap(slider_pos, min_range_pos, max_range_pos, 0, 10000)
	var percent = remap(slider_pos, min_range_pos, max_range_pos, 0, 1)
	owner.user_settings.set_value('range_slider_min', 'position_percent', percent)
	if owner.connected_to_server:
		const MIN_RANGE = 0
		var command:PackedByteArray
		command.resize(4)
		command.encode_u8(0, owner.CommandType.SET_RANGE_LIMIT)
		command.encode_u8(1, MIN_RANGE)
		command.encode_u16(2, range_map)
		owner.websocket.send(command)
	var text_value = str(snapped(percent * 100, 0.01))
	$LabelBot.text = "Min Position:\n" + text_value + "%"


func update_max_range():
	var slider_pos = max_slider.position.y
	var range_map = remap(slider_pos, min_range_pos, max_range_pos, 0, 10000)
	var percent = remap(slider_pos, min_range_pos, max_range_pos, 0, 1)
	owner.user_settings.set_value('range_slider_max', 'position_percent', percent)
	if owner.connected_to_server:
		const MAX_RANGE = 1
		var command:PackedByteArray
		command.resize(4)
		command.encode_u8(0, owner.CommandType.SET_RANGE_LIMIT)
		command.encode_u8(1, MAX_RANGE)
		command.encode_u16(2, range_map)
		owner.websocket.send(command)
	var text_value = str(snapped(percent * 100, 0.01))
	$LabelTop.text = "Max Position:\n" + text_value + "%"


func set_min_slider_pos(percent):
	var slider_map = remap(
			percent,
			0,
			1,
			min_range_pos,
			max_range_pos)
	min_slider.position.y = slider_map
	update_min_range()


func set_max_slider_pos(percent):
	var slider_map = remap(
			percent,
			0,
			1,
			min_range_pos,
			max_range_pos)
	max_slider.position.y = slider_map
	update_max_range()


func tween(activating:bool = true):
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_parallel()
	var viewport_right_edge = get_viewport_rect().size.x
	var viewport_middle = get_viewport_rect().size.x / 2
	var outside_pos := Vector2(viewport_right_edge, position.y)
	var inside_pos := Vector2(viewport_middle, outside_pos.y)
	var positions:Array = [outside_pos, inside_pos]
	if not activating:
		positions.reverse()
	tween.tween_method(set_position, position, positions[1], owner.ANIM_TIME)
	var back = $BackTexture
	var start_color:Color = $BackTexture.self_modulate
	var end_color:Color = start_color
	start_color.a = 0
	end_color.a = 1
	var colors:Array = [start_color, end_color]
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
	if owner.connected_to_ossm and %Menu/Main/Mode.selected == 1:
		update_min_range()
		update_max_range()
		%CircleSelection.show_hourglass()
		%PositionControls.modulate.a = 0.05
		owner.home_to(%PositionControls.last_position)
	$BackButton.hide()
	tween(false)
	%ActionPanel.show()
