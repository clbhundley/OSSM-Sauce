extends Control

var stroke_duration: float

# Slider Y range. Godot Y grows downward, so off_y is visually at the top of
# the track. off_y = stroke_duration 0; max_y = max stroke duration.
var off_y: float
var max_y: float

@onready var slider: TextureRect = $StrokeDurationSlider/Slider
@onready var slider_stop: TextureRect = $StrokeDurationSlider/SliderStop
@onready var sibling: Control = get_node("../Out") if name == "In" else get_node("../In")
@onready var link_button: Button = get_node('../LinkSpeedSliders')

var input_active: bool
var touch_pos: float


func _ready():
	off_y = slider.position.y
	max_y = slider_stop.position.y
	touch_pos = off_y


func reset_to_off():
	slider.position.y = off_y
	touch_pos = off_y
	stroke_duration = 0
	input_active = false
	update_stroke_duration_text()


func _physics_process(delta) -> void:
	if not input_active:
		return
	var slider_resist = get_parent().slider_resist
	var pos = lerp(slider.position.y, touch_pos, delta * slider_resist)
	slider.position.y = clamp(pos, max_y, off_y)
	map_stroke_duration()
	update_stroke_duration_text()
	if link_button.button_pressed:
		sibling.slider.position.y = slider.position.y
		sibling.map_stroke_duration()
		sibling.update_stroke_duration_text()
	get_parent().request_send()


func _input(event) -> void:
	if input_active and 'position' in event:
		var parent_local = slider.get_parent().get_global_transform_with_canvas().affine_inverse() * event.position
		var offset = 70
		touch_pos = parent_local.y - offset


func _on_slider_gui_input(event):
	if event is InputEventScreenDrag:
		input_active = true
	elif event is InputEventScreenTouch and not event.pressed:
		input_active = false


func map_stroke_duration():
	var slider_position_percent = remap(slider.position.y, off_y, max_y, 0, 1)
	if slider_position_percent < 0.005:
		stroke_duration = 0
		return
	stroke_duration = snappedf(remap(
			slider.position.y,
			max_y,
			off_y,
			owner.min_stroke_duration,
			owner.max_stroke_duration), 0.01)


func reset_stroke_duration_slider():
	slider.position.y = off_y
	if %WebSocket.ossm_connected:
		get_parent().request_send()
	update_stroke_duration_text()


func update_stroke_duration_text():
	var label_prefix: String = name.to_upper()
	var slider_position_percent = remap(slider.position.y, off_y, max_y, 0, 1)
	if slider_position_percent < 0.005:
		$StrokeDurationLabel.text = label_prefix + ": OFF"
		return
	var display_text: String
	if %Menu/LoopSettings/DisplayMode/OptionButton.selected == 0:
		display_text = label_prefix + ": " + str(stroke_duration) + "s"
	else:
		var pct = snappedf(remap(slider.position.y, off_y, max_y, 1, 100), 0.01)
		display_text = label_prefix + ": " + str(pct) + "%"
	$StrokeDurationLabel.text = display_text


func _on_transition_item_selected(index):
	get_parent().on_transition_changed(self, index)


func _on_easing_item_selected(index):
	get_parent().on_easing_changed(self, index)
