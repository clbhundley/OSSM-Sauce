extends Panel


func _ready():
	$VBox/Network/Address/TextEdit.text = get_primary_ip()


func get_primary_ip() -> String:
	var addresses = IP.get_local_addresses()
	# Priority: real LAN ranges first, virtual-adapter-prone ranges last
	# 192.168.x.x — typical home router
	# 10.x.x.x    — corporate/hotspot LANs, or VPN tunnels
	# 172.16-31   — usually WSL/Docker/Hyper-V virtual switches
	for prefix in ["192.168.", "10.", "172."]:
		for addr in addresses:
			if addr.begins_with(prefix) and is_private_ip(addr):
				return addr
	return "No WiFi IP found"


func is_private_ip(ip: String) -> bool:
	if ip.begins_with("192.168.") or ip.begins_with("10."):
		return true
	if ip.begins_with("172."):
		var second_octet := int(ip.split(".")[1])
		return second_octet >= 16 and second_octet <= 31
	return false


func _on_Back_pressed():
	%Menu.show()
	hide()


func _on_change_port_pressed() -> void:
	var new_port: int = $VBox/Network/Port/Input.value
	%WebSocket.server.stop()
	#return
	%WebSocket.port = new_port
	%WebSocket.start_server()
	owner.user_settings.set_value('network', 'port', new_port)


func _on_reverse_motor_direction_toggled(toggled_on: bool) -> void:
	var direction = 1 if toggled_on else 0
	owner.user_settings.set_value('device_settings', 'motor_direction', direction)
	owner.motor_direction = direction
	if not %WebSocket.ossm_connected:
		return
	# Stop fast processes for safety
	%VibrationControls.set_process(false)
	%PositionControls.set_physics_process(false)
	%RangePanel.update_min_range()
	%RangePanel.update_max_range()
	# Reset and home to base by reselecting mode
	%Menu._on_mode_selected(%Menu/Main/Mode.selected)


func _on_slider_max_speed_value_changed(value: float) -> void:
	owner.max_speed = value
	owner.user_settings.set_value('speed_slider', 'max_speed', value)


func _on_slider_max_acceleration_value_changed(value: float) -> void:
	owner.max_acceleration = value
	owner.user_settings.set_value('accel_slider', 'max_acceleration', value)


func _on_syncing_speed_changed():
	$VBox/SyncingSpeed/DebounceTimer.start()


func _on_syncing_speed_debounce_timer_timeout() -> void:
	if %WebSocket.ossm_connected:
		var command:PackedByteArray
		command.resize(5)
		command.encode_u32(0, OSSM.Command.SET_HOMING_SPEED)
		command.encode_u32(1, $VBox/SyncingSpeed/Input.value)
		%WebSocket.server.broadcast_binary(command)
	var new_syncing_speed: int = $VBox/SyncingSpeed/Input.value
	owner.user_settings.set_value('device_settings', 'syncing_speed', new_syncing_speed)


func _on_homing_trigger_changed() -> void:
	$VBox/HomingTrigger/DebounceTimer.start()


func _on_homing_trigger_debounce_timer_timeout() -> void:
	var default_string: String = "Default value: 1.5\nYour value is: "
	$HomingTriggerPopup/VBox/ValueLabel.text = default_string + str($VBox/HomingTrigger/Input.value)
	$HomingTriggerPopup.show()


func _on_always_on_top_toggled(toggled):
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, toggled)
	owner.user_settings.set_value('window', 'always_on_top', toggled)


#func _on_transparent_background_toggled(toggled):
	#DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, toggled)
	#owner.user_settings.set_value('window', 'transparent_background', toggled)
