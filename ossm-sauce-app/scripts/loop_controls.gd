extends Control

const THROTTLE_INTERVAL: float = 0.1

var active: bool

# Dropdown index → Godot Tween.TransitionType (visual curve only).
# The packet sent to firmware uses the raw dropdown index.
var tween_map: Dictionary = {
	0: Tween.TRANS_LINEAR,
	1: Tween.TRANS_SINE,
	2: Tween.TRANS_CIRC,
	3: Tween.TRANS_EXPO,
	4: Tween.TRANS_QUAD,
	5: Tween.TRANS_CUBIC,
	6: Tween.TRANS_QUART,
	7: Tween.TRANS_QUINT,
}

# Slider lerp resistance — safety feature, do not loosen.
var slider_resist: float = 0.8

var A: Vector2
var B: Vector2
var C: Vector2

# Throttle + dedup state.
var last_sent: PackedByteArray
var pending: bool

@onready var debounce_timer: Timer = $DebounceTimer


func _ready():
	A.x = $Control.position.x
	A.y = $Control.position.y + $Control.size.y
	B.x = $Control.position.x + $Control.size.x / 2
	B.y = $Control.position.y
	C.x = $Control.position.x + $Control.size.x
	C.y = $Control.position.y + $Control.size.y
	debounce_timer.wait_time = THROTTLE_INTERVAL
	debounce_timer.one_shot = true
	debounce_timer.timeout.connect(_on_throttle_timeout)
	_on_link_speed_sliders_toggled(true)


func draw_easing():
	var in_trans: int = $In/AccelerationControls/Transition.selected
	var in_ease: int = $In/AccelerationControls/Easing.selected
	var out_trans: int = $Out/AccelerationControls/Transition.selected
	var out_ease: int = $Out/AccelerationControls/Easing.selected
	$Line2D.clear_points()
	var x_pos = A.x
	for i in 383:
		var w = Tween.interpolate_value(
				A.y,
				(B.y - A.y),
				float(i) / 383,
				1,
				tween_map[in_trans],
				in_ease)
		$Line2D.add_point(Vector2(x_pos, w - 25))
		x_pos += 1
	for i in 383:
		var w = Tween.interpolate_value(
				B.y,
				-(B.y - C.y),
				float(i) / 383,
				1,
				tween_map[out_trans],
				out_ease)
		$Line2D.add_point(Vector2(x_pos, w - 25))
		x_pos += 1


# Called by child sliders on every meaningful tick. Throttles to ~20Hz with
# trailing-edge coalescing: leading send goes through immediately, additional
# requests during cooldown set `pending` and are sent when the cooldown ends.
func request_send():
	if debounce_timer.is_stopped():
		_do_send()
		debounce_timer.start()
	else:
		pending = true


func _on_throttle_timeout():
	if pending:
		pending = false
		_do_send()
		debounce_timer.start()


func _do_send():
	var packet = _build_loop_packet()
	if packet == last_sent:
		return
	last_sent = packet
	if not %WebSocket.ossm_connected:
		return
	%WebSocket.server.broadcast_binary(packet)
	_update_active_state()


func _build_loop_packet() -> PackedByteArray:
	var in_duration: float = $In.stroke_duration
	var out_duration: float = $Out.stroke_duration
	var in_trans: int = $In/AccelerationControls/Transition.selected
	var in_ease: int = $In/AccelerationControls/Easing.selected
	var out_trans: int = $Out/AccelerationControls/Transition.selected
	var out_ease: int = $Out/AccelerationControls/Easing.selected
	var packet: PackedByteArray
	packet.resize(19)
	packet.encode_u8(0, OSSM.Command.LOOP)
	packet.encode_u32(1, in_duration * 1000)
	packet.encode_u16(5, abs(owner.motor_direction * 10000 - 10000))
	packet.encode_u8(7, in_trans)
	packet.encode_u8(8, in_ease)
	packet.encode_u8(9, 0)
	packet.encode_u32(10, out_duration * 1000)
	packet.encode_u16(14, owner.motor_direction * 10000)
	packet.encode_u8(16, out_trans)
	packet.encode_u8(17, out_ease)
	packet.encode_u8(18, 0)
	return packet


func _update_active_state():
	var total: float = $In.stroke_duration + $Out.stroke_duration
	if total == 0 and active:
		owner.pause()
		active = false
	elif total > 0 and not active:
		owner.play()
		active = true


func _persist_and_mirror(child: Node, suffix: String, dropdown_name: String, index: int) -> void:
	var side: String = "in" if child.name == "In" else "out"
	var other_side: String = "out" if side == "in" else "in"
	var other_node: String = "Out" if side == "in" else "In"
	owner.user_settings.set_value('stroke_settings', side + "_" + suffix, index)
	if $LinkSpeedSliders.button_pressed:
		get_node(other_node + "/AccelerationControls/" + dropdown_name).select(index)
		owner.user_settings.set_value('stroke_settings', other_side + "_" + suffix, index)
	draw_easing()
	request_send()


func on_transition_changed(child: Node, index: int) -> void:
	_persist_and_mirror(child, "trans", "Transition", index)


func on_easing_changed(child: Node, index: int) -> void:
	_persist_and_mirror(child, "ease", "Easing", index)


func reset_stroke_duration_sliders():
	$In.reset_stroke_duration_slider()
	$Out.reset_stroke_duration_slider()


func update_stroke_duration_text():
	$In.update_stroke_duration_text()
	$Out.update_stroke_duration_text()


func _on_link_speed_sliders_toggled(toggled_on):
	if toggled_on:
		$LinkSpeedSliders/Label.set_modulate('00b97d')
	else:
		$LinkSpeedSliders/Label.set_modulate(Color.WHITE)


func activate():
	$In.reset_to_off()
	$Out.reset_to_off()
	$In.set_physics_process(true)
	$Out.set_physics_process(true)
	active = false
	last_sent.clear()
	pending = false
	debounce_timer.stop()
	draw_easing()
	%Menu/LoopSettings.show()
	show()


func deactivate():
	$In.set_physics_process(false)
	$Out.set_physics_process(false)
	debounce_timer.stop()
	%Menu/LoopSettings.hide()
	hide()
