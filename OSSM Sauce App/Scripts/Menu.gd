extends Panel

func _on_Back_pressed():
	tween(false)
	$Playlist.deselect_all()

func _on_Settings_pressed():
	%Settings.show()
	hide()

func _on_Exit_pressed():
	owner.exit()
	get_tree().quit()

func _on_up_pressed():
	flash_button($PathControls/Up)
	var selected_index = $Playlist.selected_index
	if selected_index > 0:
		$Playlist.move_item(selected_index, selected_index - 1)

func _on_down_pressed():
	flash_button($PathControls/Down)
	var selected_index = $Playlist.selected_index
	if selected_index < $Playlist/Scroll/VBox.get_child_count() - 1:
		$Playlist.move_item(selected_index, selected_index + 1)

func _on_play_pressed():
	#owner.vid_play()
	flash_button($PathControls/HBox/Play)
	tween(false)
	%ActionPanel.clear_selections()
	var index = $Playlist.selected_index
	if not owner.active_path_index == index:
		owner.active_path_index = index
		owner.display_active_path_index()
		$Playlist/Scroll/VBox.get_child(index).set_active()
		if %WebSocket.ossm_connected:
			%CircleSelection.show_hourglass()
			%PositionControls.modulate.a = 0.05
			owner.home_to(0)
			return
	%CircleSelection.show_play()

func _on_pause_pressed():
	#owner.vid_pause()
	owner.pause()
	%ActionPanel.clear_selections()
	%ActionPanel/Play.show()
	%ActionPanel/Pause.hide()
	refresh_selection()

func _on_restart_pressed():
	hide()
	%ActionPanel.show()
	flash_button($PathControls/HBox/Restart)
	owner.display_active_path_index()
	refresh_selection()
	if %WebSocket.ossm_connected:
		%CircleSelection.show_hourglass()
		%PathDisplay.modulate.a = 0.05
		owner.home_to(0)
	else:
		%CircleSelection.show_play()

func _on_delete_pressed():
	flash_button($PathControls/HBox/Delete)
	var selected_item = $Playlist.selected_index
	if owner.active_path_index == selected_item:
		owner.active_path_index = null
		$PathControls.hide()
		if not owner.paused:
			_on_pause_pressed()
	%PathDisplay/Paths.remove_child(%PathDisplay/Paths.get_child(selected_item))
	var pl_item = $Playlist/Scroll/VBox.get_child(selected_item)
	$Playlist/Scroll/VBox.remove_child(pl_item)
	owner.paths.remove_at(selected_item)
	owner.markers.remove_at(selected_item)
	owner.network_paths.remove_at(selected_item)
	$Playlist.selected_index = null
	if $Playlist/Scroll/VBox.get_child_count() == 0:
		$Main/PlaylistButtons/SavePlaylist.disabled = true
	refresh_selection()

func _on_load_playlist_pressed():
	%AddFile.show_playlists()
	hide()

func _on_save_playlist_pressed():
	hide_menu_buttons()
	$SavePlaylist.show()
	$Header.hide()

func _on_add_path_pressed():
	%AddFile.show_paths()
	hide()

func _on_add_delay_pressed():
	hide_menu_buttons()
	$AddDelay.show()
	$Header.hide()

func hide_menu_buttons():
	$Main/PlaylistButtons.hide()
	$Main/PathButtons.hide()
	$Main/LoopPlaylistButton.hide()
	$PathControls.hide()
	$Main/Mode.hide()

func refresh_selection():
	if $Main/Mode.selected != 0:
		return
	var selected_item = $Playlist.selected_index
	if selected_item != null:
		var item = $Playlist/Scroll/VBox.get_child(selected_item)
		$Playlist._on_item_selected(item)
	else:
		$PathControls.hide()

func show_play():
	$PathControls/HBox/Pause.hide()
	$PathControls/HBox/Play.show()
	$PathControls.show()

func show_pause():
	$PathControls/HBox/Pause.show()
	$PathControls/HBox/Play.hide()
	$PathControls.show()

func flash_button(button:Node):
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	var start_color:Color = Color.DARK_ORANGE
	var end_color:Color = Color.WHITE
	tween.tween_method(button.set_self_modulate, start_color, end_color, 0.6)

@onready var buttons:Array = [
	$PathControls/Up,
	$PathControls/Down,
	$PathControls/HBox/Play,
	$PathControls/HBox/Pause,
	$PathControls/HBox/Restart,
	$PathControls/HBox/Delete]

const ANIM_TIME = 0.35
func tween(activating:bool = true):
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_parallel()
	var start_color:Color = modulate
	var end_color:Color = start_color
	start_color.a = 0
	end_color.a = 1
	var colors:Array = [start_color, end_color]
	if activating:
		refresh_selection()
	else:
		for button in buttons:
			button.disabled = true
		colors.reverse()
		%ActionPanel.show()
		tween.tween_callback(anim_finished).set_delay(ANIM_TIME)
	tween.tween_method(set_modulate, colors[0], colors[1], ANIM_TIME)

func anim_finished():
	for button in buttons:
		button.disabled = false
	%ActionPanel/Menu/Selection.hide()
	hide()

var loop_playlist:bool
func _on_loop_playlist_button_toggled(toggled_on: bool) -> void:
	loop_playlist = toggled_on
	if toggled_on:
		$Main/LoopPlaylistButton.text = "Loop Playlist: ON"
	else:
		$Main/LoopPlaylistButton.text = "Loop Playlist: OFF"

func set_min_stroke_duration(value):
	$LoopSettings/MinStrokeDuration/SpinBox.set_value(value)

func set_max_stroke_duration(value):
	$LoopSettings/MaxStrokeDuration/SpinBox.set_value(value)

func set_stroke_duration_display_mode(value):
	$LoopSettings/DisplayMode/OptionButton.select(value)
	_on_stroke_duration_display_mode_changed(value)

func _on_min_stroke_duration_changed(value):
	owner.min_stroke_duration = value
	%LoopControls.reset_stroke_duration_sliders()
	owner.user_settings.set_value('stroke_settings', 'min_duration', value)

func _on_max_stroke_duration_changed(value):
	owner.max_stroke_duration = value
	%LoopControls.reset_stroke_duration_sliders()
	owner.user_settings.set_value('stroke_settings', 'max_duration', value)

func _on_stroke_duration_display_mode_changed(index):
	owner.user_settings.set_value('stroke_settings', 'display_mode', index)
	%LoopControls.update_stroke_duration_text()

func select_mode(index):
	print_stack()
	$Main/Mode.select(index)
	_on_mode_selected(index)

@onready var mode_option_button = $Main/Mode
@onready var mode_config_panel = $Main/ModeConfigPanel if $Main.has_node("ModeConfigPanel") else null
@onready var xtoys_bridge = %XtoysBridge if has_node("../XtoysBridge") else null

func _on_mode_selected(index:int):
	var mode_id:int = $Main/Mode.get_item_id(index)
	AppMode.active = mode_id
	owner.user_settings.set_value('app_settings', 'mode', index)
	
	owner.send_command(OSSM.Command.RESET)
	
	owner.home_to(0)
	if %WebSocket.ossm_connected:
		await owner.homing_complete
	
	owner.paused = true
	
	%ActionPanel.clear_selections()
	
	# Stop bridge if leaving bridge mode
	print("[Menu] Checking for BPIOBridge node...")
	print("[Menu] Current node path: ", get_path())
	print("[Menu] Parent node path: ", get_parent().get_path())
	if has_node("../BPIOBridge"):
		var bridge = get_node("../BPIOBridge")
		print("[Menu] BPIOBridge found, managing for mode: %d (BRIDGE=%d)" % [mode_id, AppMode.AppMode.BRIDGE])
		if mode_id == AppMode.AppMode.BRIDGE:
			print("[Menu] Bridge mode selected - Bridge Controls will handle connection when enabled")
		else:
			print("[Menu] Stopping buttplug bridge")
			bridge.stop_client()
			bridge.stop_device()
	else:
		print("[Menu] BPIOBridge node not found!")
	# Start/stop xtoys bridge
	if has_node("../XtoysBridge"):
		var xtoys_bridge = get_node("../XtoysBridge")
		print("[Menu] Mode switching to: %d (XTOYS=%d)" % [mode_id, AppMode.AppMode.XTOYS])
		if mode_id == AppMode.AppMode.XTOYS:
			print("[Menu] Starting xtoys bridge")
		else:
			print("[Menu] Stopping xtoys bridge")
			xtoys_bridge.stop_xtoys()

	# Show config options below mode selector
	if mode_config_panel:
		for child in mode_config_panel.get_children():
			mode_config_panel.remove_child(child)
			child.queue_free()
		if mode_id == AppMode.AppMode.BRIDGE:
			pass
			#mode_config_panel.add_child(create_buttplug_config_ui())
		elif mode_id == AppMode.AppMode.XTOYS:
			pass
			#mode_config_panel.add_child(create_xtoys_config_ui())

	match mode_id:
		AppMode.AppMode.IDLE:
			owner.deactivate_move_mode()
			%BridgeControls.deactivate()
			%PositionControls.deactivate()
			%LoopControls.deactivate()
			%VibrationControls.deactivate()
		AppMode.AppMode.HOMING:
			owner.deactivate_move_mode()
			%BridgeControls.deactivate()
			%PositionControls.deactivate()
			%LoopControls.deactivate()
			%VibrationControls.deactivate()
		AppMode.AppMode.MOVE:
			%BridgeControls.deactivate()
			%PositionControls.deactivate()
			%LoopControls.deactivate()
			%VibrationControls.deactivate()
			owner.activate_move_mode()
		AppMode.AppMode.POSITION:
			owner.deactivate_move_mode()
			%BridgeControls.deactivate()
			%LoopControls.deactivate()
			%VibrationControls.deactivate()
			%PositionControls.activate()
		AppMode.AppMode.LOOP:
			owner.deactivate_move_mode()
			%BridgeControls.deactivate()
			%VibrationControls.deactivate()
			%PositionControls.deactivate()
			%LoopControls.activate()
		AppMode.AppMode.VIBRATE:
			owner.deactivate_move_mode()
			%BridgeControls.deactivate()
			%PositionControls.deactivate()
			%LoopControls.deactivate()
			%VibrationControls.activate()
		AppMode.AppMode.BRIDGE:
			owner.deactivate_move_mode()
			%BridgeControls.activate()  # Show Bridge Controls UI
			%PositionControls.deactivate()
			%LoopControls.deactivate()
			%VibrationControls.deactivate()


#func create_xtoys_config_ui():
	#print("[DEBUG] create_xtoys_config_ui called, xtoys_bridge:", xtoys_bridge)
	#var vbox = VBoxContainer.new()
	#var theme = preload("res://Theme.tres")
	## For custom size, create a Font resource (.tres) in the editor and load that instead
	#var font = load("res://Font/Rubik-Light.ttf") # This is a FontFile
	#if xtoys_bridge:
		#var enable = CheckBox.new()
		#enable.text = "Enable xtoys bridge"
		#enable.button_pressed = xtoys_bridge.enabled
		#enable.toggled.connect(xtoys_bridge.set_enabled)
		#enable.theme = theme
		#enable.add_theme_font_override("font", font)
		#vbox.add_child(enable)
		#var hbox = HBoxContainer.new()
		#var port_label = Label.new()
		#port_label.text = "Port:"
		#port_label.theme = theme
		#port_label.add_theme_font_override("font", font)
		#hbox.add_child(port_label)
		#var port_edit = LineEdit.new()
		#port_edit.text = str(xtoys_bridge.get_port())
		#port_edit.theme = theme
		#port_edit.add_theme_font_override("font", font)
		#hbox.add_child(port_edit)
		#var port_btn = Button.new()
		#port_btn.text = "Apply"
		#port_btn.theme = theme
		#port_btn.add_theme_font_override("font", font)
		#port_btn.pressed.connect(func():
			#var port = int(port_edit.text)
			#if port >= 1024 and port <= 49151:
				#xtoys_bridge.set_port(port)
			#else:
				#port_edit.text = str(xtoys_bridge.get_port())
		#)
		#hbox.add_child(port_btn)
		#vbox.add_child(hbox)
		#var debug = CheckBox.new()
		#debug.text = "Debug logging"
		#debug.button_pressed = xtoys_bridge.debug_log
		#debug.toggled.connect(xtoys_bridge.set_debug_log)
		#debug.theme = theme
		#debug.add_theme_font_override("font", font)
		#vbox.add_child(debug)
		#var auto = CheckBox.new()
		#auto.text = "Auto-reconnect"
		#auto.button_pressed = xtoys_bridge.auto_reconnect
		#auto.toggled.connect(func(val): xtoys_bridge.auto_reconnect = val)
		#auto.theme = theme
		#auto.add_theme_font_override("font", font)
		#vbox.add_child(auto)
	#else:
		#print("[DEBUG] xtoys_bridge is null in create_xtoys_config_ui")
	#return vbox

#func create_buttplug_config_ui():
	#var vbox = VBoxContainer.new()
	#var theme = preload("res://Theme.tres")
	## For custom size, create a Font resource (.tres) in the editor and load that instead
	#var font = load("res://Font/Rubik-Light.ttf") # This is a FontFile
	#if %BPIOBridge:
		#var ip_hbox = HBoxContainer.new()
		#var ip_label = Label.new()
		#ip_label.text = "Buttplug Address:"
		#ip_label.theme = theme
		#ip_label.add_theme_font_override("font", font)
		#ip_hbox.add_child(ip_label)
		#var ip_edit = LineEdit.new()
		#ip_edit.text = %BPIOBridge.server_address
		#ip_edit.theme = theme
		#ip_edit.add_theme_font_override("font", font)
		#ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		#ip_hbox.add_child(ip_edit)
		#vbox.add_child(ip_hbox)
		#var main_hbox = HBoxContainer.new()
		#var main_label = Label.new()
		#main_label.text = "Main Port:"
		#main_label.theme = theme
		#main_label.add_theme_font_override("font", font)
		#main_hbox.add_child(main_label)
		#var main_edit = LineEdit.new()
		#main_edit.text = str(%BPIOBridge.server_port)
		#main_edit.theme = theme
		#main_edit.add_theme_font_override("font", font)
		#main_hbox.add_child(main_edit)
		#vbox.add_child(main_hbox)
		#var wsdm_hbox = HBoxContainer.new()
		#var wsdm_label = Label.new()
		#wsdm_label.text = "WSDM Port:"
		#wsdm_label.theme = theme
		#wsdm_label.add_theme_font_override("font", font)
		#wsdm_hbox.add_child(wsdm_label)
		#var wsdm_edit = LineEdit.new()
		#wsdm_edit.text = str(%BPIOBridge.wsdm_port)
		#wsdm_edit.theme = theme
		#wsdm_edit.add_theme_font_override("font", font)
		#wsdm_hbox.add_child(wsdm_edit)
		#vbox.add_child(wsdm_hbox)
		#var apply_btn = Button.new()
		#apply_btn.text = "Apply"
		#apply_btn.theme = theme
		#apply_btn.add_theme_font_override("font", font)
		#apply_btn.pressed.connect(func():
			#%BPIOBridge.server_address = ip_edit.text
			#%BPIOBridge.server_port = int(main_edit.text)
			#%BPIOBridge.wsdm_port = int(wsdm_edit.text)
			#%BPIOBridge.stop_client()
			#%BPIOBridge.stop_device()
			#%BPIOBridge.start_client()
			#%BPIOBridge.start_device()
		#)
		#vbox.add_child(apply_btn)
	#return vbox

# Add a label for Buttplug device connection status
#@onready var bridge_status_label = $BridgeStatusLabel if has_node("BridgeStatusLabel") else null

#func _ready():
	## Populate mode OptionButton with all AppMode values
	#mode_option_button.clear()
	#mode_option_button.add_item("Idle", AppMode.AppMode.IDLE)
	#mode_option_button.add_item("Homing", AppMode.AppMode.HOMING)
	#mode_option_button.add_item("Move", AppMode.AppMode.MOVE)
	#mode_option_button.add_item("Path", AppMode.AppMode.PATH)
	#mode_option_button.add_item("Position", AppMode.AppMode.POSITION)
	#mode_option_button.add_item("Loop", AppMode.AppMode.LOOP)
	#mode_option_button.add_item("Vibrate", AppMode.AppMode.VIBRATE)
	#mode_option_button.add_item("Bridge", AppMode.AppMode.BRIDGE)
	#mode_option_button.add_item("xtoys", AppMode.AppMode.XTOYS)
	## Add BridgeStatusLabel if not present
	#if not has_node("BridgeStatusLabel"):
		#var label = Label.new()
		#label.name = "BridgeStatusLabel"
		#label.text = "Bridge: Not Connected"
		#label.modulate = Color(1,0,0) # Red
		#label.visible = false
		#add_child(label)
		#bridge_status_label = label
#
#func _process(_delta):
	## Update bridge status indicator if in Bridge mode
	#if AppMode.active == AppMode.AppMode.BRIDGE and bridge_status_label:
		#bridge_status_label.visible = true
		#var bpio_bridge = get_node_or_null("../BPIOBridge")
		#if bpio_bridge != null and bpio_bridge.device_connected_ok:
			#bridge_status_label.text = "Bridge: OSSM device connected"
			#bridge_status_label.modulate = Color(0,1,0) # Green
		#else:
			#bridge_status_label.text = "Bridge: OSSM device NOT connected"
			#bridge_status_label.modulate = Color(1,0,0) # Red
	#else:
		#if bridge_status_label:
			#bridge_status_label.visible = false


func _on_bridge_mode_item_selected(index: int) -> void:
	# Bridge Controls.gd now handles the UI updates
	pass
