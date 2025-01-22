extends Control

var touch_pos:float
var touch_pos_offset:int

var slider:TextureRect
var slider_min:float
var slider_max:float

var slider_resist:float = 0.8

var range_percent:int
var half_period_ms:int
var origin_position:int

var waveform:int

var pulse_active:bool
var pulse_length_ms:int
var pulse_ms:int

func _ready() -> void:
	$RangeSlider/Slider.gui_input.connect(_on_slider_gui_input.bind($RangeSlider/Slider))
	$FrequencySlider/Slider.gui_input.connect(_on_slider_gui_input.bind($FrequencySlider/Slider))
	$PositionSlider/Slider.gui_input.connect(_on_slider_gui_input.bind($PositionSlider/Slider))


func _input(event):
	if slider:
		if 'position' in event:
			touch_pos = event.position.y - touch_pos_offset


func _process(delta: float) -> void:
	if pulse_active:
		pulse_controller()
	if slider:
		var pos = lerp(slider.position.y, touch_pos, delta * slider_resist)
		var clamped_pos = clamp(pos, slider_max, slider_min)
		slider.position.y = clamped_pos
		update_sliders()
		if not pulse_active and $DebounceTimer.is_stopped():
			$DebounceTimer.start()


func update_sliders() -> void:
	if slider == $RangeSlider/Slider:
		range_percent = round(remap(slider.position.y, slider_min, slider_max, 0, 100))
		$RangeSlider/ValueLabel.text = str(range_percent) + "%"
	elif slider == $FrequencySlider/Slider:
		var ms_min = 3
		var ms_max = 1000
		half_period_ms = round(remap(slider.position.y, slider_min, slider_max, ms_max, ms_min))
		var hertz = snappedf(1000 / float(half_period_ms * 2), 0.01) 
		$FrequencySlider/ValueLabel.text = str(half_period_ms) + "ms\n" + str(hertz) + "Hz"
	elif slider == $PositionSlider/Slider:
		origin_position = round(remap(slider.position.y, slider_min, slider_max, 0, 10000))
		$PositionSlider/ValueLabel.text = str(origin_position * 0.01) + "%"


func reset_sliders() -> void:
	_on_waveform_value_changed($Waveform/HSlider.value)
	
	var range_slider = $RangeSlider/Slider
	var range_min = $RangeSlider/SliderMin.position.y
	var range_max = $RangeSlider/SliderMax.position.y
	range_slider.position.y = range_min
	range_percent = round(remap(range_slider.position.y, range_min, range_max, 0, 100))
	$RangeSlider/ValueLabel.text = str(range_percent) + "%"
	
	var frequency_slider = $FrequencySlider/Slider
	var freq_min = $FrequencySlider/SliderMin.position.y
	var freq_max = $FrequencySlider/SliderMax.position.y
	frequency_slider.position.y = freq_min
	var ms_min = 3
	var ms_max = 1000
	half_period_ms = round(remap(frequency_slider.position.y, freq_min, freq_max, ms_max, ms_min))
	var hertz = snappedf(1000 / float(half_period_ms * 2), 0.01) 
	$FrequencySlider/ValueLabel.text = str(half_period_ms) + "ms\n" + str(hertz) + "Hz"
	
	var position_slider = $FrequencySlider/Slider
	var position_min = $FrequencySlider/SliderMin.position.y
	var position_max = $FrequencySlider/SliderMax.position.y
	position_slider.position.y = position_min
	origin_position = round(remap(position_slider.position.y, position_min, position_max, 0, 10000))
	$PositionSlider/ValueLabel.text = str(origin_position * 0.01) + "%"


func _on_debounce_timer_timeout() -> void:
	send_vibrate_command()


func _on_slider_gui_input(event:InputEvent, active_slider:Node) -> void:
	if event is InputEventScreenDrag:
		slider = active_slider
		slider_min = slider.get_node('../SliderMin').position.y
		slider_max = slider.get_node('../SliderMax').position.y
		touch_pos_offset = slider.get_parent().position.y + 70
	elif event is InputEventScreenTouch and not event.pressed:
		slider = null
		slider_min = 0
		slider_max = 0


func _on_pulse_control_time_value_changed(value: float) -> void:
	pulse_length_ms = $PulseControl/OnTime.value + $PulseControl/OffTime.value
	if $PulseControl/OnTime.value > 0 and $PulseControl/OffTime.value > 0:
		pulse_active = true


func _on_waveform_value_changed(value: float) -> void:
	waveform = value
	if not pulse_active and $DebounceTimer.is_stopped():
		$DebounceTimer.start()


func pulse_controller():
	var current_ms = Time.get_ticks_msec()
	if current_ms >= pulse_ms:
		pulse_ms = current_ms + pulse_length_ms
		send_vibrate_command($PulseControl/OnTime.value)


func send_vibrate_command(duration:int = -1) -> void:
	var command:PackedByteArray
	command.resize(13)
	command.encode_u8(0, owner.CommandType.VIBRATE)
	command.encode_s32(1, duration)
	command.encode_u32(5, half_period_ms)
	command.encode_u16(9, origin_position)
	command.encode_u8(11, range_percent)
	command.encode_u8(12, waveform)
	owner.websocket.send(command)


func activate():
	set_physics_process(true)
	set_process_input(true)
	reset_sliders()
	show()


func deactivate():
	set_physics_process(false)
	set_process_input(false)
	hide()
