extends RefCounted

var app
var websocket


func setup(app_owner, websocket_owner):
	app = app_owner
	websocket = websocket_owner


func _wifi():
	return websocket.get_node("%WiFi")


func _circle_selection():
	return websocket.get_node("%CircleSelection")


func _action_panel():
	return websocket.get_node("%ActionPanel")


func _menu():
	return websocket.get_node("%Menu")


func _restore_dimmed_displays():
	var displays = [
		websocket.get_node("%PathDisplay"),
		websocket.get_node("%PositionControls"),
		websocket.get_node("%LoopControls"),
		websocket.get_node("%VibrationControls"),
		websocket.get_node("%BridgeControls"),
		websocket.get_node("%ActionPanel"),
		websocket.get_node("%VideoPlayer"),
		websocket.get_node("%Settings"),
		websocket.get_node("%AddFile"),
		websocket.get_node("%Menu")]
	for node in displays:
		node.modulate.a = 1


func _restore_disconnect_displays():
	var displays = [
		websocket.get_node("%PathDisplay"),
		websocket.get_node("%PositionControls"),
		websocket.get_node("%LoopControls"),
		websocket.get_node("%VibrationControls"),
		websocket.get_node("%ActionPanel"),
		websocket.get_node("%Menu")]
	for node in displays:
		node.modulate.a = 1


func handle_response(data: PackedByteArray):
	match data[1]:
		OSSM.Command.CONNECTION:
			handle_connection_response()
		OSSM.Command.HOMING:
			handle_homing_response()


func handle_connection_response():
	_wifi().self_modulate = Color.SEA_GREEN
	_wifi().show()

	websocket.get_node("%VibrationControls").set_process(false)
	websocket.get_node("%PositionControls").set_physics_process(false)

	var release_event = InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	Input.parse_input_event(release_event)

	websocket.ossm_connected = true
	app.apply_device_settings()
	_menu()._on_mode_selected(_menu().get_node("Main/Mode").selected)


func handle_homing_response():
	_circle_selection().hide()
	_circle_selection().homing_lock = false
	_action_panel().disable_buttons(false)
	_restore_dimmed_displays()
	app.emit_signal("homing_complete")
	if AppMode.active == AppMode.MOVE and app.active_path_index != null and app.frame == 0:
		_circle_selection().show_play()


func handle_disconnect_cleanup():
	websocket.ossm_connected = false
	_wifi().self_modulate = Color.WHITE
	_action_panel()._on_pause_button_pressed()
	_circle_selection().hide()
	_circle_selection().homing_lock = false
	_action_panel().disable_buttons(false)
	_restore_disconnect_displays()
	app.emit_signal("homing_complete")
