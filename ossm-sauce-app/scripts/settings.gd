extends Panel


func _ready():
	$VBox/Network/Address/TextEdit.text = LanAddress.get_primary()
	$IPListPanel/TextEdit.text = LanAddress.get_candidate_list()
	if OS.get_name() == 'Android':
		$VBox/ReselectAndroidStorage.show()
		$VBox/AlwaysOnTop.hide()
	else:
		$VBox/ReselectAndroidStorage.hide()
		$VBox/AlwaysOnTop.show()


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


const HOLD_TICKS_REQUIRED := 3
const RESELECT_LABEL := "Hold to reselect storage location"
var _hold_ticks_remaining: int = 0

func _on_reselect_android_storage_button_down() -> void:
	$VBox/ReselectAndroidStorage.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hold_ticks_remaining = HOLD_TICKS_REQUIRED
	$VBox/ReselectAndroidStorage.text = str(_hold_ticks_remaining)
	$StorageHoldTimer.start()


func _on_reselect_android_storage_button_up() -> void:
	$VBox/ReselectAndroidStorage.alignment = HORIZONTAL_ALIGNMENT_CENTER
	$StorageHoldTimer.stop()
	_hold_ticks_remaining = 0
	$VBox/ReselectAndroidStorage.text = RESELECT_LABEL


func _on_storage_hold_timer_timeout() -> void:
	_hold_ticks_remaining -= 1
	if _hold_ticks_remaining <= 0:
		$StorageHoldTimer.stop()
		$VBox/ReselectAndroidStorage.release_focus()
		owner.pick_storage_folder()
	else:
		$VBox/ReselectAndroidStorage.text = str(_hold_ticks_remaining)
