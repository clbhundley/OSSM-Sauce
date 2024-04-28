extends Panel

var speed_slider_min_pos:float
var speed_slider_max_pos:float
@onready var speed_slider:TextureRect = $SpeedBar/Slider
@onready var speed_bottom:TextureRect = $SpeedBar/SliderBottom

var accel_slider_min_pos:float
var accel_slider_max_pos:float
@onready var acceleration_slider:TextureRect = $AccelerationBar/Slider
@onready var acceleration_bottom:TextureRect = $AccelerationBar/SliderBottom


func _ready():
	$LabelTop.self_modulate.a = 0
	$LabelBot.self_modulate.a = 0
	$BackTexture.self_modulate.a = 0
	$BackButton.hide()
	
	speed_slider.connect('gui_input', speed_slider_gui_input)
	speed_slider_max_pos = speed_slider.position.y
	speed_slider_min_pos = speed_bottom.position.y
	
	acceleration_slider.connect('gui_input', acceleration_slider_gui_input)
	accel_slider_max_pos = acceleration_slider.position.y
	accel_slider_min_pos = acceleration_bottom.position.y


func set_speed_slider_pos(percent):
	var slider_map = remap(
			percent,
			0,
			1,
			speed_slider_min_pos,
			speed_slider_max_pos)
	speed_slider.position.y = slider_map
	owner.user_settings.set_value('speed_slider', 'position_percent', percent)
	update_speed()


func set_acceleration_slider_pos(percent):
	var slider_map = remap(
			percent,
			0,
			1,
			accel_slider_min_pos,
			accel_slider_max_pos)
	acceleration_slider.position.y = slider_map
	owner.user_settings.set_value('accel_slider', 'position_percent', percent)
	update_acceleration()


func update_speed():
	var speed_map = round(remap(
			speed_slider.position.y,
			speed_slider_min_pos,
			speed_slider_max_pos,
			0,
			owner.max_speed))
	if owner.connected_to_server:
		var command:PackedByteArray
		command.resize(5)
		command.encode_u8(0, owner.CommandType.SET_SPEED_LIMIT)
		command.encode_u32(1, speed_map)
		owner.websocket.send(command)
	$LabelTop.text = "Max Speed:\n" + str(speed_map) + " steps/sec"


func update_acceleration():
	var acceleration_map = round(remap(
			acceleration_slider.position.y,
			accel_slider_min_pos,
			accel_slider_max_pos,
			1000,
			owner.max_acceleration))
	if owner.connected_to_server:
		var command:PackedByteArray
		command.resize(5)
		command.encode_u8(0, owner.CommandType.SET_GLOBAL_ACCELERATION)
		command.encode_u32(1, acceleration_map)
		owner.websocket.send(command)
	$LabelBot.text = "Acceleration:\n" + str(acceleration_map) + " steps/sec²"


func speed_slider_gui_input(event):
	if 'relative' in event and event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_LEFT:
			var drag_pos = speed_slider.position.y + event.relative.y
			var new_slider_pos = clamp(
					drag_pos,
					speed_slider_max_pos,
					speed_slider_min_pos)
			speed_slider.position.y = new_slider_pos
			update_speed()
			var slider_position_percent = remap(
					new_slider_pos,
					speed_slider_min_pos,
					speed_slider_max_pos,
					0,
					1)
			owner.user_settings.set_value(
					'speed_slider',
					'position_percent',
					slider_position_percent)


func acceleration_slider_gui_input(event):
	if 'relative' in event and event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_LEFT:
			var drag_pos = acceleration_slider.position.y + event.relative.y
			var new_slider_pos = clamp(
					drag_pos,
					accel_slider_max_pos,
					accel_slider_min_pos)
			acceleration_slider.position.y = new_slider_pos
			update_acceleration()
			var slider_position_percent = remap(
					new_slider_pos,
					speed_slider_min_pos,
					speed_slider_max_pos,
					0,
					1)
			owner.user_settings.set_value(
					'accel_slider',
					'position_percent',
					slider_position_percent)


func tween(activating:bool = true):
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_parallel()
	var outside_pos := Vector2(-size.x, position.y)
	var inside_pos := Vector2(0, outside_pos.y)
	var positions:Array = [outside_pos, inside_pos]
	if not activating:
		positions.reverse()
	tween.tween_method(set_position, position, positions[1], owner.ANIM_TIME)
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
	var visuals = [$BackTexture, $LabelTop, $LabelBot]
	for node in visuals:
		tween.tween_method(
			node.set_self_modulate,
			colors[0],
			colors[1],
			owner.ANIM_TIME)


func anim_finished():
	%ActionPanel/Speed/Selection.hide()
	%ActionPanel.self_modulate.a = 1
	$BackButton.hide()


func _on_back_button_pressed():
	tween(false)
	$BackButton.hide()
	%ActionPanel.show()
