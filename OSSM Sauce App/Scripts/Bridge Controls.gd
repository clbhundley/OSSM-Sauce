extends Control

var auto_smoothing:int

func _ready() -> void:
	$ConnectionSymbol.self_modulate.a = 0.2
	auto_smoothing = $Smoothing/TransType.get_selected_id()


func activate():
	%Menu/BridgeSettings.show()
	show()


func deactivate():
	%Menu/BridgeSettings.hide()
	%BPIOBridge.stop_device()
	%BPIOBridge.stop_client()
	%XToysBridge.stop_xtoys()
	hide()


func _on_trans_type_selected(index:int) -> void:
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
		var bridge_mode = %Menu/BridgeSettings/BridgeMode/OptionButton
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
