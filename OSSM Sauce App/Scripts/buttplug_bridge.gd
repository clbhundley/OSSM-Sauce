extends Node

## This bridge provides:
## - Buttplug.io WebSocket client
## - tcode-v03 parsing
## - OSSM command forwarding              # WebSocket Device Manager (device emulation)

var bpioconnectioncounter: int
var wdsmconnectioncounter: int

var ws_client = WebSocketPeer.new()      # Commands
var ws_device_client = WebSocketPeer.new()    # WSDM device emulation

# Device connection states
var device_connected:bool
var client_connected:bool
# Add a flag for UI to confirm device connection
var device_connected_ok:bool

var handshake_popup_shown:bool
var handshake_popup_dialog:AcceptDialog
var handshake_popup_ever_shown: bool = false

enum {
	TRANS_LINEAR,
	TRANS_SINE,
	TRANS_CIRC,
	TRANS_EXPO,
	TRANS_QUAD,
	TRANS_CUBIC,
	TRANS_QUART,
	TRANS_QUINT
}

enum {
	EASE_IN,
	EASE_OUT,
	EASE_IN_OUT,
	EASE_OUT_IN
}


func _ready():
	# Add a timer to poll device connection every 2 seconds
	if not has_node("DevicePollTimer"):
		var timer = Timer.new()
		timer.name = "DevicePollTimer"
		timer.wait_time = 2.0
		timer.one_shot = false
		timer.autostart = true
		timer.connect("timeout", Callable(self, "poll_device_connection"))
		add_child(timer)
		


func start_client():
	ws_client = WebSocketPeer.new()
	var address:String = %Menu/BridgeSettings/BPIO/ServerAddress/TextEdit.text
	var server_port: int = int (%Menu/BridgeSettings/BPIO/ServerPort/LineEdit.text)
	var ws_client_url:String = "ws://%s:%d" % [address, server_port]
	ws_client.connect_to_url(ws_client_url)
	await get_tree().create_timer(0.2).timeout
	ws_client.poll()
	var state = ws_client.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_log("Connecting to Buttplug main server at " + ws_client_url)
		ws_client.poll()
		if state == WebSocketPeer.STATE_OPEN:
			var request_server_info = [
				{
					"RequestServerInfo": {
						"Id": 2,
						"ClientName": "ossm-client",
						"MessageVersion": 3
					}
				}
			]
			ws_client.send_text(JSON.stringify(request_server_info))
			_log("[DEBUG] Client - Sent RequestServerInfo request")
			await get_tree().create_timer(0.1).timeout
			var request_device_list = [
				{
					"RequestDeviceList": {
						"Id": 1
					}
				}
			]
			ws_client.send_text(JSON.stringify(request_device_list))
			_log("[DEBUG] Sent RequestDeviceList request")
			# Send RequestDeviceList
			client_connected = true
		poll_ws_client()
	elif state == WebSocketPeer.STATE_CLOSING:
		# Keep polling to achieve proper close.
		pass
	elif state == WebSocketPeer.STATE_CLOSED:
		var code = ws_client.get_close_code()
		var reason = ws_client.get_close_reason()
		print("WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1])
		await get_tree().create_timer(2).timeout
		start_client()


func start_device():
	if %BridgeControls/Controls/Enable.button_pressed:
		ws_device_client = WebSocketPeer.new()
		wdsmconnectioncounter += 1
		var wsdm_port: int  = int (%Menu/BridgeSettings/BPIO/WSDMPort/LineEdit.text)
		var ws_device_client_url:String = "ws://127.0.0.1:%d" % [wsdm_port]
		ws_device_client.connect_to_url(ws_device_client_url)
		await get_tree().create_timer(0.2).timeout
		_log("Connecting attempt %d to WSDM at %s" % [wdsmconnectioncounter, ws_device_client_url])
		if wdsmconnectioncounter == 5:
			_show_handshake_popup()
		ws_device_client.poll()
		var state = ws_device_client.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			ws_device_client.poll()
			# Wait for ws_device_client to reach STATE_OPEN
			var handshake = {
				"identifier": "ossm",
				"address": "ossm-sauce",
				"version": 0
			}
			ws_device_client.send_text(JSON.stringify(handshake))
			_log("[DEBUG] Sent handshake: " + JSON.stringify(handshake))
			start_client()
			# Reset handshake count when starting
			#handshake_count = 0
		elif state == WebSocketPeer.STATE_CLOSING:
			# Keep polling to achieve proper close.
			pass
		elif state == WebSocketPeer.STATE_CLOSED:
			var code = ws_device_client.get_close_code()
			var reason = ws_device_client.get_close_reason()
			print("WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1])
			await get_tree().create_timer(2).timeout
			start_device()
		else:
			wdsmconnectioncounter = 0


func stop_client():
	if ws_client:
		ws_client.close(1000, "Client disconnect")
		ws_client = null
		_log("Disconnected from Buttplug main server")
		%BridgeControls/ConnectionSymbol.self_modulate = Color.WHITE_SMOKE
		%BridgeControls/ConnectionSymbol.self_modulate.a = 0.2


func stop_device():
	if ws_device_client:
		# Send a proper disconnect frame before closing
		if ws_device_client.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws_device_client.close(1000, "Device disconnect")
			ws_device_client = null
			device_connected = false


func device_confirmed(): # Auto-disconnect device
	if ws_client:
		ws_client.close(1000, "Client disconnect")
		ws_client = null
		_log("Confirmed device connected to Buttplug main server, disconnecting client")
		client_connected = false


func poll_ws_client():
	if %BridgeControls/Controls/Enable.button_pressed:
		if client_connected:
			ws_client.poll()
			await get_tree().create_timer(0.1).timeout
			while ws_client.get_available_packet_count() > 0:
				var packet = ws_client.get_packet()
				if packet.size() > 0:
					var msg_str = packet.get_string_from_utf8()
					_log("[DEBUG] Client - Got packet: " + msg_str)
					# Parse DeviceList and check for ossm-godot
					var json = JSON.new()
					var err = json.parse(msg_str)
					if err == OK and typeof(json.data) == TYPE_ARRAY:
						for obj in json.data:
							if obj.has("DeviceList"):
								var device_list = obj["DeviceList"]
								if device_list.has("Devices"):
									var found = false
									for device in device_list["Devices"]:
										if device.has("DeviceName") and device["DeviceName"] == "TCode v0.3 (Single Linear Axis)":
											_log("OSSM device is connected and visible!")
											set_device_connected_ok(true)
											found = true
											device_confirmed()
											return
									if not found:
										set_device_connected_ok(false)
										_log("OSSM device NOT found in DeviceList.")


func _process(_delta):
	if ws_device_client:
		ws_device_client.poll()
	if ws_client:
		ws_client.poll()
	# --- WSDM (device emulation) ---
	if device_connected == true:
		
		# Only handle packet reading here
		while ws_device_client.get_available_packet_count() > 0:
			var packet = ws_device_client.get_packet()
			if packet.size() > 0:
				var msg_str = packet.get_string_from_utf8()
				_log("[DEBUG] Device Got packet: " + msg_str)
				for line in msg_str.split('\n'):
					if line.strip_edges() != "":
						_translate_and_forward(line.strip_edges())


func _translate_and_forward(tcode_cmd: String):
	# Example: L077I500, V099, L020S10
	var regex = RegEx.new()
	regex.compile("([LRVA])(\\d+)(I(\\d+))?(S(\\d+))?")
	var matches = regex.search_all(tcode_cmd)
	for match in matches:
		var type = match.get_string(1)
		var channel = int(match.get_string(2)[0])
		var magnitude_str = int(match.get_string(2).substr(1))
		var interval = int(match.get_string(4)) if match.get_string(4) != null and match.get_string(4) != "" else 0
		var speed = int(match.get_string(6)) if match.get_string(6) != null and match.get_string(6) != "" else 0

		# Only support channel 0 for OSSM for now
		if channel != 0:
			continue

		if type == "L":
			# Linear move: map to OSSM SMOOTH_MOVE
			var depth:int = remap(magnitude_str, 0, 100, 0, 10000)
			var ms_timing:int = interval if interval > 0 else 100 # Default timing
			var trans:int = %BridgeControls.auto_smoothing
			var ease:int = EASE_IN_OUT
			var auxiliary:int = 0
			var move_cmd = get_parent().create_move_command(ms_timing, float(depth) / 10000.0, trans, ease, auxiliary)
			send_smooth_move_command(interval, depth, trans, ease, auxiliary)

		elif type == "V":
			# Vibrate: map to OSSM VIBRATE
			pass
			#var strength = int(round(magnitude * 100))
			#var duration = interval if interval > 0 else -1
			#var half_period_ms = 10
			#var origin_position = 0
			#var range_percent = 100
			#var waveform = 5
			#var vibrate_cmd = PackedByteArray()
			#vibrate_cmd.resize(13)
			#vibrate_cmd.encode_u8(0, OSSM.Command.VIBRATE)
			#vibrate_cmd.encode_s32(1, duration)
			#vibrate_cmd.encode_u32(5, half_period_ms)
			#vibrate_cmd.encode_u16(9, int(magnitude * 10000))
			#vibrate_cmd.encode_u8(11, range_percent)
			#vibrate_cmd.encode_u8(12, waveform)
			#if %WebSocket.ossm_connected:
				#%WebSocket.server.broadcast_binary(vibrate_cmd)
		# Add more mappings as needed for R, A, etc. 


func send_smooth_move_command(ms_duration:int, depth:int, trans:int, ease:int, auxiliary:int):
	# Clamp to app's configured max_speed, max_acceleration, and range
	var root = get_tree().root.get_child(0)
	if "max_speed" in root:
		ms_duration = max(ms_duration, int(1000.0 / float(root.max_speed)))
	if "max_acceleration" in root:
		# Optionally use this for acceleration-limited moves
		pass # Not directly used in this function, but available
	if "min_stroke_duration" in root and "max_stroke_duration" in root:
		depth = clamp(depth, int(root.min_stroke_duration), int(root.max_stroke_duration))
	else:
		depth = clamp(depth, 0, 10000)
	var command:PackedByteArray
	command.resize(10)
	command.encode_u8(0, OSSM.Command.SMOOTH_MOVE)
	command.encode_u32(1, ms_duration)
	command.encode_u16(5, depth)
	command.encode_u8(7, trans)
	command.encode_u8(8, ease)
	command.encode_u8(9, auxiliary)
	%WebSocket.server.broadcast_binary(command)


func _show_handshake_popup():
	if handshake_popup_ever_shown:
		_log("[DEBUG] Handshake popup has already been shown once, not showing again.")
		return
	if handshake_popup_shown:
		_log("[DEBUG] Popup already shown, skipping")
		return
	if handshake_popup_dialog and handshake_popup_dialog.visible:
		_log("[DEBUG] Handshake popup dialog already visible, not showing again.")
		return
	handshake_popup_shown = true
	handshake_popup_dialog = AcceptDialog.new()
	handshake_popup_dialog.title = "Buttplug.io Connection Issue"
	handshake_popup_dialog.dialog_text = "Could not connect to Intiface Central within 10 seconds.\n\nPlease ensure:\n- Intiface Central is running\n- The WebSocket Device Manager (WSDM) is enabled\n- The correct ports are configured"
	handshake_popup_dialog.ok_button_text = "OK"
	handshake_popup_dialog.add_theme_font_size_override("font_size", 30)
	handshake_popup_dialog.add_theme_font_size_override("title_font_size", 40)
	get_tree().current_scene.add_child(handshake_popup_dialog)
	handshake_popup_dialog.popup_centered()
	handshake_popup_ever_shown = true  # <-- Move this here, after the popup is actually shown
	handshake_popup_dialog.confirmed.connect(func():
		_log("[DEBUG] Popup OK pressed, freeing dialog")
		handshake_popup_shown = false
		handshake_popup_dialog.queue_free()
		handshake_popup_dialog = null
	)


func set_device_connected_ok(device_connected_ok):
	_log("[DEBUG] set_device_connected_ok called with: " + str(device_connected_ok))
	%BridgeControls/ConnectionSymbol.self_modulate = Color.SEA_GREEN
	if handshake_popup_dialog:
		_log("[DEBUG] Dismissing handshake popup dialog")
		if handshake_popup_dialog.visible:
			handshake_popup_dialog.hide()
			device_connected = true
			_log("[DEBUG] Device Connected !")
		if is_instance_valid(handshake_popup_dialog):
			handshake_popup_dialog.queue_free()
			handshake_popup_dialog = null
			device_connected = true
			_log("[DEBUG] Device Connected !")
		handshake_popup_shown = false
	else:
		_log("[DEBUG] Handshake popup dialog not visible, skipping")
		device_connected = true
		_log("[DEBUG] Device Connected !")


func _on_reconnect_timer_timeout() -> void:
	_show_handshake_popup()
	_log("[DEBUG] Timer finished, showing popup")


func _log(log_text:String):
	if not %Menu/BridgeSettings/LoggingEnabled.button_pressed:
		return
	# Only show [DEBUG] logs if debug_log_enabled is true
	var show_debug = true
	if get_tree().root.has_node("Settings"):
		show_debug = get_tree().root.get_node("Settings").debug_log_enabled
	if log_text.begins_with("[DEBUG]*") and not show_debug:
		return
	var log_node = %BridgeControls/Log
	log_node.text += log_text + "\n"
	var max_lines = 1000
	var lines = log_node.text.split("\n")
	if lines.size() > max_lines:
		log_node.text = "\n".join(lines.slice(lines.size() - max_lines, lines.size()))
