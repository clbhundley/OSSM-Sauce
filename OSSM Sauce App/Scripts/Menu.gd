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
		elif mode_id == AppMode.AppMode.INTERACTIVE_VIDEO:
			# Hide the menu first, then show InteractiveVideoMode after menu is hidden
			self.hide()
			call_deferred("_show_interactive_video_mode")
			%ActionPanel.show()
			# Hide other controls
			%BridgeControls.deactivate()
			%PositionControls.deactivate()
			%LoopControls.deactivate()
			%VibrationControls.deactivate()
			# Show funscript UI at the bottom (handled by InteractiveVideoMode scene)
			return

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
		AppMode.AppMode.INTERACTIVE_VIDEO:
			# All UI handled by InteractiveVideoMode scene
			pass

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

# Add a file dialog for video selection
@onready var video_file_dialog = FileDialog.new()

func _ready():
	# Populate mode OptionButton with all AppMode values
	mode_option_button.clear()
	mode_option_button.add_item("Idle", AppMode.AppMode.IDLE)
	mode_option_button.add_item("Homing", AppMode.AppMode.HOMING)
	mode_option_button.add_item("Move", AppMode.AppMode.MOVE)
	mode_option_button.add_item("Path", AppMode.AppMode.PATH)
	mode_option_button.add_item("Position", AppMode.AppMode.POSITION)
	mode_option_button.add_item("Loop", AppMode.AppMode.LOOP)
	mode_option_button.add_item("Vibrate", AppMode.AppMode.VIBRATE)
	mode_option_button.add_item("Bridge", AppMode.AppMode.BRIDGE)
	mode_option_button.add_item("xtoys", AppMode.AppMode.XTOYS)
	mode_option_button.add_item("Interactive Video", AppMode.AppMode.INTERACTIVE_VIDEO)
	# Add BridgeStatusLabel if not present
	if not has_node("BridgeStatusLabel"):
		var label = Label.new()
		label.name = "BridgeStatusLabel"
		label.text = "Bridge: Not Connected"
		label.modulate = Color(1,0,0) # Red
		label.visible = false
		add_child(label)

func _show_interactive_video_mode():
	if not has_node("../InteractiveVideoMode"):
		var scene = load("res://InteractiveVideoMode.tscn").instantiate()
		print("New Scene added is %s" % scene.name)
		get_tree().current_scene.add_child(scene)
		# Optionally, set up references if needed
	else:
		get_node("../InteractiveVideoMode").show()
	# Ensure ActionPanel is visible
	%ActionPanel.show()
