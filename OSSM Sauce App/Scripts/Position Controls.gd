extends Control

@onready var slider:TextureRect = $MovementBar/Slider

@onready var max_range:float = $MovementBar/SliderTop.position.y
@onready var min_range:float = slider.position.y

@onready var touch_pos:float = min_range

var smoothing:float

var last_position:int

var input_active:bool


func _ready():
	_on_smoothing_slider_value_changed($Smoothing/HSlider.value)


func _physics_process(delta):
	var pos = lerp(slider.position.y, touch_pos, delta * smoothing)
	slider.position.y = clamp(pos, max_range, min_range)
	var mapped_pos:int = remap(slider.position.y, min_range, max_range, 0, 10000)
	if %WebSocket.ossm_connected and last_position != mapped_pos:
		var command:PackedByteArray
		command.resize(5)
		command.encode_u8(0, OSSM.Command.POSITION)
		command.encode_u32(1, mapped_pos)
		%WebSocket.server.broadcast_binary(command)
		last_position = mapped_pos


func _input(event):
	if input_active:
		var offset = 265
		touch_pos = event.position.y - offset
	elif event is InputEventJoypadMotion:
		#var input_position = Input.get_action_strength("analog_up") - Input.get_action_strength("analog_down")
		var input_position = Input.get_action_strength("right_trigger")
		
		#touch_pos = remap(pos_avg, -1, 1, min_range, max_range)
		touch_pos = remap(input_position, 0, 1, min_range, max_range)


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


func activate():
	touch_pos = min_range
	last_position = 0
	$MovementBar/Slider.position.y = min_range
	set_physics_process(true)
	set_process_input(true)
	owner.play()
	show()


func deactivate():
	set_physics_process(false)
	set_process_input(false)
	hide()
