extends Control

var auto_smoothing:int
var enabled: bool = false
var xtoysenabled: bool = false
var bpioenabled: bool = false

func _ready() -> void:
	enabled = false
	auto_smoothing = $Smoothing/MenuButton.get_selected_id()
	# Add Enable/Disable toggle button to Bridge Controls if not present
	
	#_disable_controls()
	# Connect OptionButton signal
	var option_btn = %Menu/BridgeSettings/BridgeMode/OptionButton
	if option_btn:
		option_btn.connect("item_selected", Callable(self, "_on_bridge_mode_item_selected"))
	# Initial UI update
	_update_bridge_mode_ui(option_btn.selected if option_btn else 0)

# Get the auto smoothing value, not sure if needed SP
func get_auto_smoothing() -> int:
	if enabled:
		return auto_smoothing
	else:
		return 0  # Default value when not enabled

func _process(delta: float) -> void:
	pass

func toggle_bridge_enable():
	# Toggle the bridge enable/disable state
	if enabled:
		# Disable bridge
		enabled = false
		# Stop all bridge connections
		_stop_bridge_connections()
		print("Bridge Controls disabled")
	else:
		# Enable bridge
		enabled = true
		# Start the bridge connections for the currently selected option
		_start_bridge_connections()
		print("Bridge Controls enabled")

func _on_enable_button_pressed():
	if $EnableBridge.get_theme_color("font_color") == Color.RED:
		# Enable bridge
		enabled = true
		$EnableBridge.add_theme_color_override("font_color", Color.GREEN)
		$EnableBridge.add_theme_color_override("font_hover_color", Color.GREEN)
		$EnableBridge.add_theme_color_override("font_focus_color", Color.GREEN)
		# Start the bridge connections for the currently selected option
		_start_bridge_connections()
		return
	if $EnableBridge.get_theme_color("font_color") == Color.GREEN:
		# Disable bridge
		enabled = false
		$EnableBridge.add_theme_color_override("font_color", Color.RED)
		$EnableBridge.add_theme_color_override("font_hover_color", Color.RED)
		$EnableBridge.add_theme_color_override("font_focus_color", Color.RED)
		# Stop all bridge connections
		_stop_bridge_connections()

func _stop_bridge_connections():
	var option_btn = %Menu/BridgeSettings/BridgeMode/OptionButton
	if not option_btn:
		return
	match option_btn.selected:
		0:  # Buttplug.io
			bpioenabled = false
			%BPIOBridge.stop_device()
			%BPIOBridge.stop_client()
		1:  # XToys
			xtoysenabled = false
			%XToysBridge.stop_xtoys()
		2:  # MCP
			pass  # MCP not implemented yet

func _start_bridge_connections():
	if not enabled:
		return
	var option_btn = %Menu/BridgeSettings/BridgeMode/OptionButton
	if not option_btn:
		return
	match option_btn.selected:
		0:  # Buttplug.io
			bpioenabled = true
			%BPIOBridge.start_device()
		1:  # XToys
			xtoysenabled = true
			%XToysBridge.start_xtoys()
		2:  # MCP
			pass  # MCP not implemented yet




func activate():
	# Always show BridgeSettings when activating, regardless of enabled state
	%Menu/BridgeSettings.show()
	$ConnectionSymbol.self_modulate.a = 0.2
	show()
	# If already enabled, start connections
	#if enabled:
	#	_start_bridge_connections()

func deactivate():
	%Menu/BridgeSettings.hide()
	hide()


func _on_clear_log_pressed() -> void:
	$Log.clear()


func _on_autoscroll_pressed() -> void:
	$Log.scroll_following = !$Log.scroll_following
	if $Log.scroll_following:
		$AutoScroll.text = "Autoscroll: ON"
	else:
		$AutoScroll.text = "Autoscroll: OFF"

func _on_bridge_mode_item_selected(index):
	# Automatically disable bridge when mode changes
	if enabled:
		$EnableButton.button_pressed = false
		_on_enable_button_pressed()  # This will disable the bridge
	_update_bridge_mode_ui(index)

func _update_bridge_mode_ui(index):
	var bpio = %Menu/BridgeSettings/BPIO
	var xtoys = %Menu/BridgeSettings/XToys
	if bpio: bpio.hide()
	if xtoys: xtoys.hide()
	if index == 0 and bpio:
		bpio.show()
	elif index == 1 and xtoys:
		xtoys.show()
	# MCP (index 2) shows neither


func _on_enable_bridge_pressed() -> void:
	pass # Replace with function body.
