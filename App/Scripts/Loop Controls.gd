extends Control

var active:bool = true

enum Trans {
	LINEAR,
	SINE,
	CIRC,
	EXPO,
	QUAD,
	CUBIC,
	QUART,
	QUINT
}

var tween_map:Dictionary = {
	Trans.LINEAR : 0,
	Trans.SINE : 1,
	Trans.CIRC : 8,
	Trans.EXPO : 5,
	Trans.QUAD : 4,
	Trans.CUBIC : 7,
	Trans.QUART : 3,
	Trans.QUINT : 2
}

var stroke_duration:float

var slider_min_pos:float
var slider_max_pos:float
@onready var slider:TextureRect = $StrokeDurationSlider/Slider
@onready var slider_stop:TextureRect = $StrokeDurationSlider/SliderStop

@onready var touch_pos:float = slider_min_pos

func _physics_process(delta):
	if not input_active:
		return
	
	var pos = lerp(slider.position.y, touch_pos, delta)
	slider.position.y = clamp(pos, slider_max_pos, slider_min_pos)
	
	var slider_position_percent = remap(
		slider.position.y,
		slider_max_pos,
		slider_min_pos,
		0,
		1)
	if slider_position_percent < 0.005:
		$StrokeDurationLabel.text = "OFF"
		if owner.connected_to_server:
			owner.websocket.send_text("L0")
		return
	
	stroke_duration = snappedf(remap(
		slider.position.y,
		slider_min_pos,
		slider_max_pos,
		owner.min_stroke_duration,
		owner.max_stroke_duration), 0.01)
	
	send_command()
	
	var display_text:String
	if %Menu/LoopSettings/DisplayMode/OptionButton.selected == 0:
		display_text = "Stroke Duration: " + str(stroke_duration) + "s"
	else:
		var map = snappedf(remap(
			slider.position.y,
			slider_max_pos,
			slider_min_pos,
			1,
			100), 0.01)
		display_text = "Speed: " + str(map) + "%"
	$StrokeDurationLabel.text = display_text

func update_stroke_duration_text():
	var slider_position_percent = remap(
		slider.position.y,
		slider_max_pos,
		slider_min_pos,
		0,
		1)
	if slider_position_percent < 0.005:
		$StrokeDurationLabel.text = "OFF"
	else:
		var display_text:String
		if %Menu/LoopSettings/DisplayMode/OptionButton.selected == 0:
			display_text = "Stroke Duration: " + str(stroke_duration) + "s"
		else:
			var map = snappedf(remap(
				slider.position.y,
				slider_max_pos,
				slider_min_pos,
				1,
				100), 0.01)
			display_text = "Speed: " + str(map) + "%"
		$StrokeDurationLabel.text = display_text

var input_active:bool
func _input(event):
	if input_active:
		var offset = 225
		touch_pos = event.position.x - offset

func _on_slider_gui_input(event):
	if event is InputEventScreenDrag:
		input_active = true
	elif event is InputEventScreenTouch and not event.pressed:
		input_active = false

func _ready():
	slider_min_pos = slider_stop.position.y
	slider_max_pos = slider.position.y
	A.x = $Control.position.x
	A.y = $Control.position.y + $Control.size.y
	B.x = $Control.position.x + $Control.size.x / 2
	B.y = $Control.position.y
	C.x = $Control.position.x + $Control.size.x
	C.y = $Control.position.y + $Control.size.y

func rmt(input:int):
	return tween_map[input]

func draw_easing():
	$Line2D.clear_points()
	var x_pos = A.x
	
	for i in 383:
		var w = Tween.interpolate_value(
			A.y,
			(B.y - A.y),
			float(i) / 383,
			1,
			rmt($Controls/Transitions/In.selected),
			$Controls/Easings/In.selected)
		$Line2D.add_point(Vector2(x_pos, w - 25))
		x_pos += 1
	
	for i in 383:
		var w = Tween.interpolate_value(
			B.y,
			-(B.y - C.y),
			float(i) / 383,
			1,
			rmt($Controls/Transitions/Out.selected),
			$Controls/Easings/Out.selected)
		$Line2D.add_point(Vector2(x_pos, w - 25))
		x_pos += 1

var A:Vector2
var B:Vector2
var C:Vector2

func _on_active_switch_toggled(toggled_on):
	if toggled_on:
		$ActiveSwitch.self_modulate = Color.GREEN
		$ActiveSwitch.text = "ON"
		send_command()
	else:
		if owner.connected_to_server:
			owner.websocket.send_text("L0")
		$ActiveSwitch.self_modulate = Color.RED
		$ActiveSwitch.text = "OFF"

func send_command(value=true):
	draw_easing()
	var in_trans = $Controls/Transitions/In.selected
	var in_ease = $Controls/Easings/In.selected
	var out_trans = $Controls/Transitions/Out.selected
	var out_ease = $Controls/Easings/Out.selected
	owner.user_settings.set_value('stroke_settings', 'in_trans', in_trans)
	owner.user_settings.set_value('stroke_settings', 'in_ease', in_ease)
	owner.user_settings.set_value('stroke_settings', 'out_trans', out_trans)
	owner.user_settings.set_value('stroke_settings', 'out_ease', out_ease)
	if owner.connected_to_server and active:
		owner.websocket.send_text(
			'L' + str((stroke_duration * 1000) * 0.5) + 
			"T" + str(in_trans) + 
			"E" + str(in_ease) + 
			"T" + str(out_trans) + 
			"E" + str(out_ease))

func reset_stroke_duration_slider():
	if owner.connected_to_server:
		owner.websocket.send_text("L0")
	slider.position.y = slider_max_pos
	var stroke_duration = snappedf(remap(
		slider.position.y,
		slider_min_pos,
		slider_max_pos,
		owner.min_stroke_duration,
		owner.max_stroke_duration), 0.01)
	$StrokeDurationLabel.text = "Stroke Duration: " + str(stroke_duration) + "s"

func _on_ttc_toggled(toggled_on):
	if toggled_on:
		$Controls/ttc.self_modulate = Color.SEA_GREEN
		$Controls/ttc.text = "Tap to Cycle: ON"
	else:
		$Controls/ttc.self_modulate = Color.WHITE
		$Controls/ttc.text = "Tap to Cycle: OFF"

var prev_ms:int
func _on_tap_pressed():
	if not $Controls/ttc.button_pressed:
		return
	var duration = $SpinBox.value * 1000
	var tap_time = Time.get_ticks_msec() - prev_ms
	if prev_ms and tap_time < duration:
		duration = tap_time
	prev_ms = Time.get_ticks_msec()
	if owner.connected_to_server and $ActiveSwitch.button_pressed:
		owner.websocket.send_text(
			'L' + str((duration) * 0.5) + 
			"T" + str($Controls/Transitions/In.selected) + 
			"E" + str($Controls/Easings/In.selected) + 
			"T" + str($Controls/Transitions/Out.selected) + 
			"E" + str($Controls/Easings/Out.selected) +
			"C")
