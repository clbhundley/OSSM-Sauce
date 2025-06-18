extends Panel

@onready var address_input = $Network/Address/TextEdit


func _ready():
	if OS.get_name() == "Android":
		$Window.hide()
	
	var numeric_inputs:Array = [
		$Network/Port/TextEdit,
		$Sliders/MaxSpeed/TextEdit,
		$Sliders/MaxAcceleration/TextEdit]
	for node in numeric_inputs:
		node.text_changed.connect(_on_numeric_input_changed.bind(node))
	
	$Network/Address/TextEdit.text = get_primary_ip()


func _on_numeric_input_changed(input_node:Node):
	var regex = RegEx.new()
	regex.compile("[^0-9]")
	var filtered_text = regex.sub(input_node.text, "", true)
	if input_node.text != filtered_text:
		input_node.text = filtered_text
		input_node.set_caret_column(input_node.text.length())


func get_primary_ip() -> String:
	var addresses = IP.get_local_addresses()
	for addr in addresses:
		if is_private_ip(addr) and not addr.begins_with("127."):  # Skip localhost
			return addr
	return "No WiFi IP found"


func is_private_ip(ip: String) -> bool:
	return (ip.begins_with("192.168.") or   # Most home routers
		ip.begins_with("10.") or            # Corporate/hotspots  
		ip.begins_with("172.16.") or        # Less common private range
		ip.begins_with("172.17.") or        # Docker networks
		ip.begins_with("172.18.") or
		ip.begins_with("172.31."))


func _on_Back_pressed():
	var speed_value = int($Sliders/MaxSpeed/TextEdit.text)
	speed_value = clamp(speed_value, 100, 200000)
	$Sliders/MaxSpeed/TextEdit.text = str(speed_value)
	var accel_value = int($Sliders/MaxAcceleration/TextEdit.text)
	accel_value = clamp(accel_value, 5000, 9000000)
	$Sliders/MaxAcceleration/TextEdit.text = str(accel_value)
	%Menu.show()
	hide()


func _on_change_port_pressed() -> void:
	var port_text = $Network/Port/TextEdit.text.strip_edges()
	
	if port_text == "" or not port_text.is_valid_int():
		$Network/Port/TextEdit.text = str(%WebSocket.port)
		printerr("Invalid port number.")
		return
	
	var new_port = int(port_text)
	if new_port < 1024 or new_port > 49151:
		$Network/Port/TextEdit.text = str(%WebSocket.port)
		printerr("Port must be within range (1024 - 49151)")
		return
	
	%WebSocket.server.stop()
	%WebSocket.port = new_port
	%WebSocket.start_server()
	owner.user_settings.set_value('network', 'port', new_port)


func set_max_speed(value):
	$Sliders/MaxSpeed/TextEdit.text = str(value)
	_on_speed_input_changed()


func set_max_acceleration(value):
	$Sliders/MaxAcceleration/TextEdit.text = str(value)
	_on_acceleration_input_changed()


func _on_speed_input_changed():
	var value = int($Sliders/MaxSpeed/TextEdit.text)
	value = clamp(value, 100, 200000)
	owner.max_speed = value
	owner.user_settings.set_value('speed_slider', 'max_speed', value)


func _on_acceleration_input_changed():
	var value = int($Sliders/MaxAcceleration/TextEdit.text)
	value = clamp(value, 5000, 9000000)
	owner.max_acceleration = value
	owner.user_settings.set_value('accel_slider', 'max_acceleration', value)


func send_syncing_speed():
	if %WebSocket.ossm_connected:
		var command:PackedByteArray
		command.resize(5)
		command.encode_u32(0, OSSM.Command.SET_HOMING_SPEED)
		command.encode_u32(1, $SyncingSpeed/SpinBox.value)
		%WebSocket.server.broadcast_binary(command)


func _on_syncing_speed_changed(value):
	send_syncing_speed()
	owner.user_settings.set_value('device_settings', 'syncing_speed', value)


func send_homing_trigger():
	if %WebSocket.ossm_connected:
		var command:PackedByteArray
		command.resize(5)
		command.encode_u32(0, OSSM.Command.SET_HOMING_TRIGGER)
		command.encode_float(1, $HomingTrigger/SpinBox.value)
		%WebSocket.server.broadcast_binary(command)


func _on_homing_trigger_changed(value: float) -> void:
	$HomingTrigger/DebounceTimer.start()


func _on_homing_trigger_debounce_timer_timeout() -> void:
	var default_string:String = "Default value: 1.5\nYour value is: "
	$HomingTriggerPopup/ValueLabel.text = default_string + str($HomingTrigger/SpinBox.value)
	$HomingTriggerPopup.show()


func _on_always_on_top_toggled(toggled):
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, toggled)
	owner.user_settings.set_value('window', 'always_on_top', toggled)


func _on_transparent_background_toggled(toggled):
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, toggled)
	owner.user_settings.set_value('window', 'transparent_background', toggled)
