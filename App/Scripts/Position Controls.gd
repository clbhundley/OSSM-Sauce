extends Control

@onready var slider:TextureRect = $MovementBar/Slider

@onready var max_range:float = $MovementBar/SliderTop.position.y
@onready var min_range:float = slider.position.y

@onready var touch_pos:float = min_range

var smoothing:float

var last_position:int

var input_active: bool

func _ready():
	_on_smoothing_slider_value_changed($Smoothing/HSlider.value)

func _physics_process(delta):
	var pos = lerp(slider.position.y, touch_pos, delta * smoothing)
	slider.position.y = clamp(pos, max_range, min_range)
	var mapped_pos:int = remap(slider.position.y, min_range, max_range, 0, 9999)
	if owner.connected_to_server and last_position != mapped_pos:
		owner.websocket.send_text('P' + str(mapped_pos))
		last_position = mapped_pos

func _input(event):
	if input_active:
		var offset = 265
		touch_pos = event.position.y - offset

func _on_slider_gui_input(event):
	if event is InputEventScreenDrag:
		input_active = true
	else:
		input_active = false

func _on_smoothing_slider_value_changed(value):
	var min_value = $Smoothing/HSlider.min_value
	var max_value = $Smoothing/HSlider.max_value
	smoothing = max_value - (value - min_value)
	owner.user_settings.set_value('app_settings', 'smoothing_slider', value)
