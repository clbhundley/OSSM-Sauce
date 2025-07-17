extends Control

var auto_smoothing:int

func _ready() -> void:
	auto_smoothing = $Smoothing/MenuButton.get_selected_id()


func _process(delta: float) -> void:
	pass


func activate():
	%Menu/BridgeSettings.show()
	$ConnectionSymbol.self_modulate.a = 0.2
	match %Menu/BridgeSettings/BridgeMode/OptionButton.selected:
		0:
			%BPIOBridge.start_client()
			%BPIOBridge.start_device()
		1:
			%XToysBridge.start_xtoys()
		2:
			pass
	show()


func deactivate():
	%Menu/BridgeSettings.hide()
	%BPIOBridge.stop_client()
	%BPIOBridge.stop_device()
	%XToysBridge.stop_xtoys()
	hide()


func _on_clear_log_pressed() -> void:
	$Log.clear()
