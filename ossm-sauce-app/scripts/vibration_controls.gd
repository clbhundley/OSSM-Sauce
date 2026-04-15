extends Control

const SLIDER_RESIST: float = 1

var touch_pos: float
var touch_pos_offset: int

var slider: TextureRect
var slider_min: float
var slider_max: float

var range_percent: int
var half_period_ms: int
var origin_position: int

var pulse_active: bool
var pulse_length_ms: int
var pulse_ms: int

var paused: bool


func _ready() -> void:
	$RangeSlider/Slider.gui_input.connect(_on_slider_gui_input.bind($RangeSlider/Slider))
	$FrequencySlider/Slider.gui_input.connect(_on_slider_gui_input.bind($FrequencySlider/Slider))
	$PositionSlider/Slider.gui_input.connect(_on_slider_gui_input.bind($PositionSlider/Slider))


func _input(event) -> void:
	if slider:
		if 'position' in event:
			touch_pos = event.position.y - touch_pos_offset


func _process(delta: float) -> void:
	if pulse_active:
		pulse_controller()
	if slider:
		var pos = lerp(slider.position.y, touch_pos, delta * SLIDER_RESIST)
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
	$PulseControl/Timers/OnTime.value = 0
	$PulseControl/Timers/OffTime.value = 0
	
	var range_slider = $RangeSlider/Slider
	var range_min = $RangeSlider/SliderMin.position.y
	var range_max = $RangeSlider/SliderMax.position.y
	range_slider.position.y = range_min
	range_percent = round(remap(range_slider.position.y, range_min, range_max, 0, 100))
	$RangeSlider/ValueLabel.text = str(range_percent) + "%"
	
	var frequency_slider = $FrequencySlider/Slider
	var freq_min = $FrequencySlider/SliderMin.position.y
	var freq_max = $FrequencySlider/SliderMax.position.y
	frequency_slider.position.y = remap(750, 0, 10000, freq_min, freq_max)
	var ms_min = 3
	var ms_max = 1000
	half_period_ms = round(remap(frequency_slider.position.y, freq_min, freq_max, ms_max, ms_min))
	var hertz = snappedf(1000 / float(half_period_ms * 2), 0.01) 
	$FrequencySlider/ValueLabel.text = str(half_period_ms) + "ms\n" + str(hertz) + "Hz"
	
	var position_slider = $PositionSlider/Slider
	var position_min = $PositionSlider/SliderMin.position.y
	var position_max = $PositionSlider/SliderMax.position.y
	# Start at 15% to prevent blocking if motor direction is reversed
	position_slider.position.y = remap(1500, 0, 10000, position_min, position_max)
	origin_position = round(remap(position_slider.position.y, position_min, position_max, 0, 10000))
	$PositionSlider/ValueLabel.text = str(origin_position * 0.01) + "%"


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


func _on_pulse_control_time_value_changed() -> void:
	var on_ms: int = $PulseControl/Timers/OnTime.value
	var off_ms: int = $PulseControl/Timers/OffTime.value
	pulse_length_ms = on_ms + off_ms
	pulse_active = on_ms > 0 and off_ms > 0


func _on_waveform_value_changed() -> void:
	if not pulse_active and $DebounceTimer.is_stopped():
		$DebounceTimer.start()


func pulse_controller():
	var current_ms = Time.get_ticks_msec()
	if current_ms >= pulse_ms:
		pulse_ms = current_ms + pulse_length_ms
		send_vibrate_command($PulseControl/Timers/OnTime.value)


func send_vibrate_command(duration: int = -1) -> void:
	if paused or not %WebSocket.ossm_connected:
		return
	var command:PackedByteArray
	command.resize(13)
	command.encode_u8(0, OSSM.Command.VIBRATE)
	command.encode_s32(1, duration)
	command.encode_u32(5, half_period_ms)
	command.encode_u16(9, abs(owner.motor_direction * 10000 - origin_position))
	command.encode_u8(11, range_percent)
	command.encode_u8(12, $Waveform/HSlider.value)
	%WebSocket.server.broadcast_binary(command)


func update_blocked_indicator() -> void:
	$PositionSlider/MinLimit.visible = owner.motor_direction == 1
	$PositionSlider/MaxLimit.visible = owner.motor_direction == 0


func ui_enabled(enabled: bool) -> void:
	$Waveform/HSlider.editable = enabled
	$PulseControl/Timers/OnTime.editable = enabled
	$PulseControl/Timers/OffTime.editable = enabled


func activate():
	paused = false
	set_process(true)
	set_process_input(true)
	ui_enabled(true)
	reset_sliders()
	update_blocked_indicator()
	send_vibrate_command(0)
	show()


func deactivate():
	set_process(false)
	set_process_input(false)
	hide()
