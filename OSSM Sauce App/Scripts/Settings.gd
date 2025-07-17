extends Panel

@onready var address_input = $Network/Address/TextEdit
@onready var buttplug_ip_textedit = $Network/ButtplugIP/TextEdit if has_node("Network/ButtplugIP/TextEdit") else null
@onready var buttplug_ip_button = $Network/ButtplugIP/SetButton if has_node("Network/ButtplugIP/SetButton") else null
@onready var buttplug_main_port_textedit = $Network/ButtplugMainPort/TextEdit if has_node("Network/ButtplugMainPort/TextEdit") else null
@onready var buttplug_wsdm_port_textedit = $Network/ButtplugWSDMPort/TextEdit if has_node("Network/ButtplugWSDMPort/TextEdit") else null
@onready var xtoys_panel = $XtoysSettings if has_node("XtoysSettings") else null
@onready var buttplug_panel = $ButtplugSettings if has_node("ButtplugSettings") else self
@onready var xtoys_bridge = %XtoysBridge if has_node("../XtoysBridge") else null


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

	# Add Buttplug IP input if not present
	var buttplug_address = "127.0.0.1"
	var buttplug_main_port = "12345"
	var buttplug_wsdm_port = "54817"
	if has_node("../BPIOBridge"):
		var bpio_bridge = get_node("../BPIOBridge")
		if bpio_bridge.has_method("get_buttplug_address"):
			buttplug_address = bpio_bridge.buttplug_address
			buttplug_main_port = str(bpio_bridge.buttplug_server_port)
			buttplug_wsdm_port = str(bpio_bridge.wsdm_port)
	if not $Network.has_node("ButtplugIP"):
		var hbox = HBoxContainer.new()
		hbox.name = "ButtplugIP"
		var label = Label.new()
		label.text = "Buttplug Address:"
		var textedit = LineEdit.new()
		textedit.name = "TextEdit"
		textedit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		textedit.text = buttplug_address
		var setbtn = Button.new()
		setbtn.name = "SetButton"
		setbtn.text = "Set"
		hbox.add_child(label)
		hbox.add_child(textedit)
		hbox.add_child(setbtn)
		$Network.add_child(hbox)
		buttplug_ip_textedit = textedit
		buttplug_ip_button = setbtn
	if not $Network.has_node("ButtplugMainPort"):
		var hbox = HBoxContainer.new()
		hbox.name = "ButtplugMainPort"
		var label = Label.new()
		label.text = "Buttplug Main Port:"
		var textedit = LineEdit.new()
		textedit.name = "TextEdit"
		textedit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		textedit.text = buttplug_main_port
		hbox.add_child(label)
		hbox.add_child(textedit)
		$Network.add_child(hbox)
		buttplug_main_port_textedit = textedit
	if not $Network.has_node("ButtplugWSDMPort"):
		var hbox = HBoxContainer.new()
		hbox.name = "ButtplugWSDMPort"
		var label = Label.new()
		label.text = "Buttplug WSDM Port:"
		var textedit = LineEdit.new()
		textedit.name = "TextEdit"
		textedit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		textedit.text = buttplug_wsdm_port
		hbox.add_child(label)
		hbox.add_child(textedit)
		$Network.add_child(hbox)
		buttplug_wsdm_port_textedit = textedit
	if buttplug_ip_button:
		buttplug_ip_button.pressed.connect(_on_buttplug_ip_set_pressed)
	if buttplug_ip_textedit:
		buttplug_ip_textedit.text = buttplug_address
	if buttplug_main_port_textedit:
		buttplug_main_port_textedit.text = buttplug_main_port
	if buttplug_wsdm_port_textedit:
		buttplug_wsdm_port_textedit.text = buttplug_wsdm_port

	if xtoys_panel:
		xtoys_panel.hide()
		xtoys_panel.get_node("EnableCheckbox").toggled.connect(_on_xtoys_enable_toggled)
		xtoys_panel.get_node("PortLineEdit").text = str(xtoys_bridge.get_port())
		xtoys_panel.get_node("PortApplyButton").pressed.connect(_on_xtoys_port_apply)
		xtoys_panel.get_node("DebugCheckbox").toggled.connect(_on_xtoys_debug_toggled)
		xtoys_panel.get_node("AutoReconnectCheckbox").toggled.connect(_on_xtoys_auto_reconnect_toggled)

	if not has_node("XtoysSettings"):
		var panel = Panel.new()
		panel.name = "XtoysSettings"
		panel.visible = false
		var vbox = VBoxContainer.new()
		panel.add_child(vbox)
		var enable = CheckBox.new()
		enable.name = "EnableCheckbox"
		enable.text = "Enable xtoys bridge"
		enable.button_pressed = xtoys_bridge.enabled if xtoys_bridge else false
		vbox.add_child(enable)
		var hbox = HBoxContainer.new()
		var port_label = Label.new()
		port_label.text = "Port:"
		hbox.add_child(port_label)
		var port_edit = LineEdit.new()
		port_edit.name = "PortLineEdit"
		port_edit.text = str(xtoys_bridge.get_port()) if xtoys_bridge else "8080"
		hbox.add_child(port_edit)
		var port_btn = Button.new()
		port_btn.name = "PortApplyButton"
		port_btn.text = "Apply"
		hbox.add_child(port_btn)
		vbox.add_child(hbox)
		var debug = CheckBox.new()
		debug.name = "DebugCheckbox"
		debug.text = "Debug logging"
		debug.button_pressed = xtoys_bridge.debug_log if xtoys_bridge else false
		vbox.add_child(debug)
		var auto = CheckBox.new()
		auto.name = "AutoReconnectCheckbox"
		auto.text = "Auto-reconnect"
		auto.button_pressed = xtoys_bridge.auto_reconnect if xtoys_bridge else true
		vbox.add_child(auto)
		add_child(panel)
		xtoys_panel = panel


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
		if is_private_ip(addr) and not addr.begins_with("127."):
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


func _on_buttplug_ip_set_pressed():
	var address = buttplug_ip_textedit.text.strip_edges()
	var main_port = buttplug_main_port_textedit.text.strip_edges() if buttplug_main_port_textedit else "12345"
	var wsdm_port = buttplug_wsdm_port_textedit.text.strip_edges() if buttplug_wsdm_port_textedit else "54817"
	if %BPIOBridge != null:
		%BPIOBridge.buttplug_address = address
		%BPIOBridge.buttplug_server_port = int(main_port)
		%BPIOBridge.wsdm_port = int(wsdm_port)
		%BPIOBridge.stop_client()
		%BPIOBridge.stop_device()
		%BPIOBridge.start_client()
		%BPIOBridge.start_device()
		# Save to user settings
		owner.user_settings.set_value('buttplug', 'address', address)
		owner.user_settings.set_value('buttplug', 'main_port', int(main_port))
		owner.user_settings.set_value('buttplug', 'wsdm_port', int(wsdm_port))
	buttplug_ip_textedit.text = address
	if buttplug_main_port_textedit:
		buttplug_main_port_textedit.text = main_port
	if buttplug_wsdm_port_textedit:
		buttplug_wsdm_port_textedit.text = wsdm_port


func _on_xtoys_tab_pressed():
	if buttplug_panel:
		buttplug_panel.hide()
	if xtoys_panel:
		xtoys_panel.show()


func _on_buttplug_tab_pressed():
	if xtoys_panel:
		xtoys_panel.hide()
	if buttplug_panel:
		buttplug_panel.show()


func _on_xtoys_enable_toggled(pressed):
	if xtoys_bridge:
		xtoys_bridge.set_enabled(pressed)


func _on_xtoys_port_apply():
	if xtoys_bridge and xtoys_panel:
		var port = int(xtoys_panel.get_node("PortLineEdit").text)
		if port >= 1024 and port <= 49151:
			xtoys_bridge.set_port(port)
		else:
			xtoys_panel.get_node("PortLineEdit").text = str(xtoys_bridge.get_port())


func _on_xtoys_debug_toggled(pressed):
	if xtoys_bridge:
		xtoys_bridge.set_debug_log(pressed)


func _on_xtoys_auto_reconnect_toggled(pressed):
	if xtoys_bridge:
		xtoys_bridge.auto_reconnect = pressed
