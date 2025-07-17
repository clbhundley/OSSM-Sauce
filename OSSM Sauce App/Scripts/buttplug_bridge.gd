extends Node

## This bridge provides:
## - Buttplug.io WebSocket client
## - tcode-v03 parsing
## - OSSM command forwarding

var server_address := "127.0.0.1"
var server_port := 12345              # Main Buttplug server (client role)
var wsdm_port := 54817                # WebSocket Device Manager (device emulation)

const RECONNECT_DELAY:int = 8
var client_reconnect_timer:float
var device_reconnect_timer:float

var ws_client:WebSocketPeer           # Commands
var ws_device_client:WebSocketPeer    # WSDM device emulation

# Client connection states
var client_connected:bool
var client_handshake_sent:bool
var client_handshake_complete:bool
var client_prev_ready_state:int = -1

# Device connection states
var device_connected:bool
var device_handshake_sent:bool
var device_handshake_complete:bool
var device_prev_ready_state:int = -1

# Add a timer to track when to send client requests after device handshake
var client_request_delay:float = 0.2
var client_request_timer:float
var client_requests_sent:bool

# Add a flag for UI to confirm device connection
var device_connected_ok:bool

# Track retry attempts to show dialog after first retry
var client_retry_count:int
var device_retry_count:int
var dialog_shown:bool

# Track handshake attempts for popup
var handshake_count:int
var handshake_timer:Timer

var handshake_popup_shown:bool
var handshake_timer_7s:Timer
var handshake_timer_active:bool
var handshake_popup_dialog:AcceptDialog

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


func start_client():
	if ws_client == null:
		ws_client = WebSocketPeer.new()
		var ws_client_url:String = "ws://%s:%d" % [server_address, server_port]
		var err = ws_client.connect_to_url(ws_client_url)
		_log("[Client] Connection attempt result: " + str(err))
		if err != OK:
			_log("Failed to connect to Buttplug main server: " + str(err))
			ws_client = null
			client_connected = false
			# _show_connection_error_dialog() # Removed
		else:
			_log("Connecting to Buttplug main server at " + ws_client_url)
			%BridgeControls/ConnectionSymbol.self_modulate = Color.WHITE_SMOKE
			client_connected = true
			client_handshake_sent = false
			client_handshake_complete = false
			client_prev_ready_state = -1


func start_device():
	if ws_device_client == null:
		ws_device_client = WebSocketPeer.new()
		var ws_device_client_url:String = "ws://%s:%d" % [server_address, wsdm_port]
		var err = ws_device_client.connect_to_url(ws_device_client_url)
		_log("[Device] Connection attempt result: " + str(err))
		if err != OK:
			_log("Failed to connect to WSDM: " + str(err))
			# Send disconnect frame to reset the connection
			_send_disconnect_frame()
			ws_device_client = null
			device_connected = false
			# _show_connection_error_dialog() # Removed
		else:
			_log("Connecting to WSDM at " + ws_device_client_url)
			device_connected = true
			device_handshake_sent = false
			device_handshake_complete = false
			device_prev_ready_state = -1
			
			# Reset handshake count when starting
			#handshake_count = 0


func stop_client():
	if ws_client:
		ws_client.close(1000, "Client disconnect")
		ws_client = null
		client_connected = false
		client_handshake_sent = false
		client_handshake_complete = false
		client_prev_ready_state = -1
		_log("Disconnected from Buttplug main server")


func stop_device():
	if ws_device_client:
		# Send a proper disconnect frame before closing
		if ws_device_client.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_send_disconnect_frame_to_server()
		ws_device_client.close(1000, "Device disconnect")
		ws_device_client = null
		device_connected = false
		device_handshake_sent = false
		device_handshake_complete = false
		device_prev_ready_state = -1
		
		# Reset handshake count when stopping
		handshake_count = 0
		if handshake_timer:
			handshake_timer.stop()
			handshake_timer.queue_free()
			handshake_timer = null


func _process(_delta):
	# --- WSDM (device emulation) ---
	if ws_device_client:
		ws_device_client.poll()
		var state = ws_device_client.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN and not device_handshake_sent:
			var handshake = {
				"identifier": "ossm",
				"address": "ossm-sauce",
				"version": 0
			}
			ws_device_client.send_text(JSON.stringify(handshake))
			_log("[Device] Sent handshake: " + JSON.stringify(handshake))
			handshake_count = handshake_count + 1
			check_device_connection_timeout() # Start/check the 7s timer for device connection
			if handshake_count >= 2:
				_show_handshake_popup()
			device_handshake_sent = true
			client_request_timer = 0.0
			client_requests_sent = false
		device_prev_ready_state = state
		if state != WebSocketPeer.STATE_OPEN:
			device_connected = false
			if dialog_shown:
				return
			device_reconnect_timer += _delta
			if device_reconnect_timer >= RECONNECT_DELAY:
				device_retry_count += 1
				_log("[Device] Attempting reconnect #%d..." % device_retry_count)
				stop_device()
				await get_tree().create_timer(0.5).timeout
				start_device()
				device_reconnect_timer = 0.0
				if device_retry_count >= 2:
					_log("[Device] Multiple retries failed (retry count: %d)" % device_retry_count)
					# _show_connection_error_dialog() # Removed
			device_handshake_sent = false
			client_request_timer = 0.0
			client_requests_sent = false
			return
		else:
			device_connected = true
			device_reconnect_timer = 0.0
			device_retry_count = 0
			dialog_shown = false
			handshake_popup_shown = false
		while ws_device_client.get_available_packet_count() > 0:
			var packet = ws_device_client.get_packet()
			if packet.size() > 0:
				var msg_str = packet.get_string_from_utf8()
				_log("[Device] Got packet: " + msg_str)
				for line in msg_str.split('\n'):
					if line.strip_edges() != "":
						_translate_and_forward(line.strip_edges())

	# --- Main Buttplug server (client role) ---
	if ws_client:
		ws_client.poll()
		var state = ws_client.get_ready_state()
		# Do NOT send handshake for client
		# Wait for device handshake, then send client requests after delay
		if device_handshake_sent and not client_requests_sent:
			client_request_timer += _delta
			if client_request_timer >= client_request_delay and state == WebSocketPeer.STATE_OPEN:
				# Send RequestServerInfo
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
				_log("[Client] Sent RequestServerInfo request")
				# Send RequestDeviceList
				var request_device_list = [
					{
						"RequestDeviceList": {
							"Id": 1
						}
					}
				]
				ws_client.send_text(JSON.stringify(request_device_list))
				_log("[Client] Sent RequestDeviceList request")
				client_requests_sent = true
		client_prev_ready_state = state
		if state != WebSocketPeer.STATE_OPEN:
			client_connected = false
			if dialog_shown:
				return
			client_reconnect_timer += _delta
			if client_reconnect_timer >= RECONNECT_DELAY:
				client_retry_count += 1
				_log("[Client] Attempting reconnect #%d..." % client_retry_count)
				stop_client()
				start_client()
				client_reconnect_timer = 0.0
				if client_retry_count >= 2:
					_log("[Client] Multiple retries failed (retry count: %d)" % client_retry_count)
					# _show_connection_error_dialog() # Removed
			client_requests_sent = false
			client_request_timer = 0.0
			set_device_connected_ok(false)
			return
		else:
			client_connected = true
			client_reconnect_timer = 0.0
			client_retry_count = 0  # Reset retry counter on successful connection
			dialog_shown = false  # Reset dialog flag on successful connection
		while ws_client.get_available_packet_count() > 0:
			var packet = ws_client.get_packet()
			if packet.size() > 0:
				var msg_str = packet.get_string_from_utf8()
				_log("[Client] Got packet: " + msg_str)
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
										_log("[Client] OSSM device 'ossm-sauce' is connected and visible!")
										set_device_connected_ok(true)
										found = true
								if not found:
									set_device_connected_ok(false)
									_log("[Client] OSSM device 'ossm-godot' NOT found in DeviceList.")


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


func _send_disconnect_frame():
	# Send a disconnect frame to reset the buttplug.io connection
	# This helps clear any stuck connections on the server side
	var disconnect_frame = {
		"type": "disconnect",
		"identifier": "ossm",
		"address": "ossm-sauce"
	}
	_log("[Device] Sending disconnect frame to reset connection")
	# Note: We can't send this through the failed connection, but this function
	# can be called before attempting to reconnect to help reset the server state


func _send_disconnect_frame_to_server():
	# Send a proper disconnect frame to the WSDM server
	var disconnect_frame = {
		"type": "disconnect",
		"identifier": "ossm",
		"address": "ossm-sauce"
	}
	if ws_device_client and ws_device_client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_device_client.send_text(JSON.stringify(disconnect_frame))
		_log("[Device] Sent disconnect frame to WSDM server")


func reset_dialog_flag():
	# Manual function to reset the dialog flag
	dialog_shown = false
	_log("[Dialog] Dialog flag manually reset")


func check_device_connection_timeout():
	# Start the 7s timer if not already running
	if not handshake_timer_active:
		handshake_timer_active = true
		if not handshake_timer_7s:
			handshake_timer_7s = Timer.new()
			handshake_timer_7s.one_shot = true
			handshake_timer_7s.wait_time = 7.0
			handshake_timer_7s.timeout.connect(_on_handshake_timer_7s_timeout)
			get_tree().root.add_child(handshake_timer_7s)
		handshake_timer_7s.start()


func _on_handshake_timer_7s_timeout():
	if not device_connected_ok and not handshake_popup_shown:
		_show_handshake_popup()
	handshake_timer_active = false


func _show_handshake_popup():
	if handshake_popup_shown:
		_log("[DEBUG] Popup already shown, skipping")
		return
	handshake_popup_shown = true
	handshake_count = 0
	if handshake_timer_7s:
		handshake_timer_7s.stop()
		handshake_timer_active = false
	_log("[Device] Showing handshake popup after 7 seconds without device_connected_ok.")
	handshake_popup_dialog = AcceptDialog.new()
	handshake_popup_dialog.title = "Buttplug.io Connection Issue"
	handshake_popup_dialog.dialog_text = "Could not connect to Intiface Central (WSDM) within 7 seconds.\n\nPlease ensure:\n- Intiface Central is running\n- The WebSocket Device Manager (WSDM) is enabled\n- The correct ports are configured"
	handshake_popup_dialog.ok_button_text = "OK"
	handshake_popup_dialog.add_theme_font_size_override("font_size", 24)
	handshake_popup_dialog.add_theme_font_size_override("title_font_size", 28)
	get_tree().current_scene.add_child(handshake_popup_dialog)
	handshake_popup_dialog.popup_centered()
	handshake_popup_dialog.confirmed.connect(func():
		_log("[DEBUG] Popup OK pressed, freeing dialog")
		handshake_popup_shown = false
		handshake_count = 0
		if handshake_timer_7s:
			handshake_timer_7s.stop()
			handshake_timer_active = false
		handshake_popup_dialog.queue_free()
		handshake_popup_dialog = null
	)


func _on_handshake_timer_timeout():
	_log("[Device] Handshake timer timeout. Resetting handshake count.")
	handshake_count = 0


func set_device_connected_ok(device_connected_ok):
	_log("[DEBUG] set_device_connected_ok called with: " + str(device_connected_ok))
	if device_connected_ok and handshake_popup_dialog:
		%BridgeControls/ConnectionSymbol.self_modulate = Color.SEA_GREEN
		_log("[DEBUG] Dismissing handshake popup dialog")
		handshake_popup_dialog.hide()
		handshake_popup_dialog.queue_free()
		handshake_popup_dialog = null
		handshake_popup_shown = false
		handshake_count = 0
		if handshake_timer_7s:
			handshake_timer_7s.stop()
			handshake_timer_active = false

func _log(log_text:String):
	%BridgeControls/Log.text += log_text + "\n"
