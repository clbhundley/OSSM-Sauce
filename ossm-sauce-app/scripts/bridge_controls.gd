extends Control

var auto_smoothing: int

var min_move_duration: int = 500
var max_move_duration: int = 6000


func _ready() -> void:
	$ConnectionSymbol.self_modulate.a = 0.2
	auto_smoothing = $Smoothing/TransType.get_selected_id()
	%Menu._on_bridge_mode_selected(%Menu/BridgeSettings/BridgeMode/ModeSelection.selected)


func activate():
	$Controls/Enable.button_pressed = false
	%Menu/BridgeSettings.show()
	show()


func deactivate():
	%Menu/BridgeSettings.hide()
	%Menu/BridgeHelp.hide()
	%BPIOBridge.stop_device()
	%BPIOBridge.stop_client()
	%XToysBridge.stop_xtoys()
	hide()


func _on_trans_type_selected(index: int) -> void:
	auto_smoothing = index


func _on_clear_log_pressed() -> void:
	$Log.text = ""
	$Log.clear()


func _on_autoscroll_pressed() -> void:
	$Log.scroll_following = !$Log.scroll_following
	if $Log.scroll_following:
		$Controls/AutoScroll.text = "Autoscroll: ON"
	else:
		$Controls/AutoScroll.text = "Autoscroll: OFF"


func _on_enable_toggled(toggled_on: bool) -> void:
	if toggled_on:
		$Controls/Enable.text = "Enabled"
		$ConnectionSymbol.self_modulate.a = 1
		var bridge_mode = %Menu/BridgeSettings/BridgeMode/ModeSelection
		match bridge_mode.selected:
			0:  # Buttplug.io
				%BPIOBridge.start_device()
			1:  # XToys
				%XToysBridge.start_xtoys()
			2:  # MCP
				%MCPCommandServer.start_mcp_server()
	else:
		$Controls/Enable.text = "Disabled"
		%BPIOBridge.stop_device()
		%BPIOBridge.stop_client()
		%XToysBridge.stop_xtoys()
		%MCPCommandServer.stop_mcp_server()


func _on_min_move_duration_value_changed(value: float) -> void:
	min_move_duration = int(value)
	%Menu/BridgeSettings/SpeedOverrides/Inputs/MaxMoveDuration/Input.min_value = maxf(value, 1)
	owner.user_settings.set_value('bridge_settings', 'min_move_duration', min_move_duration)


func _on_max_move_duration_value_changed(value: float) -> void:
	max_move_duration = int(value)
	%Menu/BridgeSettings/SpeedOverrides/Inputs/MinMoveDuration/Input.max_value = minf(value, 99999)
	owner.user_settings.set_value('bridge_settings', 'max_move_duration', max_move_duration)


func set_move_duration_limits(min_val: int, max_val: int) -> void:
	var min_input = %Menu/BridgeSettings/SpeedOverrides/Inputs/MinMoveDuration/Input
	var max_input = %Menu/BridgeSettings/SpeedOverrides/Inputs/MaxMoveDuration/Input
	min_input.max_value = 99999
	max_input.min_value = 1
	min_input.set_value_no_signal(min_val)
	max_input.set_value_no_signal(max_val)
	min_move_duration = min_val
	max_move_duration = max_val
	min_input.max_value = max_val
	max_input.min_value = min_val


func _on_logging_enabled_toggled(toggled_on: bool) -> void:
	owner.user_settings.set_value('bridge_settings', 'logging_enabled', toggled_on)


func _on_bpio_server_address_changed(new_text: String) -> void:
	owner.user_settings.set_value('bpio_settings', 'server_address', new_text)


func _on_bpio_server_port_changed(value: float) -> void:
	owner.user_settings.set_value('bpio_settings', 'server_port', int(value))


func _on_bpio_wsdm_port_changed(value: float) -> void:
	owner.user_settings.set_value('bpio_settings', 'wsdm_port', int(value))


func _on_bpio_identifier_changed(new_text: String) -> void:
	owner.user_settings.set_value('bpio_settings', 'identifier', new_text)


func _on_bpio_client_name_changed(new_text: String) -> void:
	owner.user_settings.set_value('bpio_settings', 'client_name', new_text)


func _on_bpio_address_changed(new_text: String) -> void:
	owner.user_settings.set_value('bpio_settings', 'address', new_text)


func _on_xtoys_port_changed(value: float) -> void:
	owner.user_settings.set_value('xtoys_settings', 'port', value)


func _on_xtoys_max_msg_frequency_changed(value: float) -> void:
	owner.user_settings.set_value('xtoys_settings', 'max_msg_frequency', value)


func _on_xtoys_use_command_duration_toggled(toggled_on: bool) -> void:
	owner.user_settings.set_value('xtoys_settings', 'use_command_duration', toggled_on)


func _on_mcp_port_changed(value: float) -> void:
	owner.user_settings.set_value('mcp_settings', 'port', int(value))


func _on_bpio_help_button_pressed() -> void:
	_open_bridge_help(%Menu/BridgeHelp/BPIOInfo)


func _on_xtoys_help_button_pressed() -> void:
	_open_bridge_help(%Menu/BridgeHelp/XToysInfo)


func _on_mcp_help_button_pressed() -> void:
	_open_bridge_help(%Menu/BridgeHelp/MCPInfo)


func _open_bridge_help(info_panel: Control) -> void:
	%Menu/BridgeSettings.hide()
	%Menu/BridgeHelp/BPIOInfo.hide()
	%Menu/BridgeHelp/XToysInfo.hide()
	%Menu/BridgeHelp/MCPInfo.hide()
	info_panel.show()
	%Menu/BridgeHelp.show()


func _close_bridge_help() -> void:
	%Menu/BridgeHelp.hide()
	%Menu/BridgeSettings.show()
