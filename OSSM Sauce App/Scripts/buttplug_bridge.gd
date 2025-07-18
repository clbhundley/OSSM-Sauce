extends Node

## This bridge provides:
## - Buttplug.io WebSocket client
## - tcode-v03 parsing
## - OSSM command forwarding              # WebSocket Device Manager (device emulation)

const RECONNECT_DELAY:int = 2
var client_reconnect_timer:float
var device_reconnect_timer:float

var ws_client = WebSocketPeer.new()      # Commands
var ws_device_client = WebSocketPeer.new()    # WSDM device emulation

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
	var server_port: int = int (%Menu/BridgeSettings/BPIO/ServerPort/LineEdit.text)
	
	var ws_client_url:String = "ws://127.0.0.1:%d" % [server_port]
	var err = ws_client.connect_to_url(ws_client_url)
	_log("[DEBUG] Client - Connection attempt result: " + str(err))
	if err != OK:
		_log("[DEBUG] Client - Failed to connect to Buttplug main server: " + str(err))
		#ws_client = null
		client_connected = false
		# _show_connection_error_dialog() # Removed
	else:
		_log("Connecting to Buttplug main server at " + ws_client_url)
		%BridgeControls/ConnectionSymbol.self_modulate = Color.WHITE_SMOKE
		client_connected = true
		client_handshake_sent = false
		client_handshake_complete = false
		client_prev_ready_state = -1
		ws_client.poll()
		var state = ws_client.get_ready_state()
		# Do NOT send handshake for client
		# Wait for device handshake, then send client requests after delay
		# Wait for ws_device_client to reach STATE_OPEN
		var counter: int
		while ws_client.get_ready_state() != WebSocketPeer.STATE_OPEN:
			if counter < 50:
				await get_tree().create_timer(0.5).timeout
				ws_client.poll()
				counter += 1
			# Once open, wait 1 second and call poll_ws_client
		await get_tree().create_timer(0.2).timeout
		if state == WebSocketPeer.STATE_OPEN:
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
			_log("[DEBUG] Clinet - Sent RequestServerInfo request")
			# Send RequestDeviceList
		poll_ws_client(0)


func start_device():
	ws_device_client = WebSocketPeer.new()
	var wsdm_port: int  = int (%Menu/BridgeSettings/BPIO/WSDMPort/LineEdit.text)
	
	var ws_device_client_url:String = "ws://127.0.0.1:%d" % [wsdm_port]
	var err = ws_device_client.connect_to_url(ws_device_client_url)
	_log("[Debug] Device - Connection attempt result: " + str(err))
	if err != OK:
		_log("[DEBUG] Device - Failed to connect to WSDM: " + str(err))
		#ws_device_client = null
		device_connected = false
		# _show_connection_error_dialog() # Removed
	else:
		_log("Connecting to WSDM at " + ws_device_client_url)
		device_connected = true
		device_handshake_sent = false
		device_handshake_complete = false
		device_prev_ready_state = -1
		ws_device_client.poll()
		# Wait for ws_device_client to reach STATE_OPEN
		var counter: int
		while ws_device_client.get_ready_state() != WebSocketPeer.STATE_OPEN:
			if counter < 50:
				await get_tree().create_timer(0.5).timeout
				ws_device_client.poll()
				counter += 1
			# Once open, wait 1 second and call poll_ws_client
		await get_tree().create_timer(0.2).timeout
		var handshake = {
			"identifier": "ossm",
			"address": "ossm-sauce",
			"version": 0
		}
		ws_device_client.send_text(JSON.stringify(handshake))
		_log("[DEBUG] Sent handshake: " + JSON.stringify(handshake))
		poll_device_connection()
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
			ws_device_client.close(1000, "Device disconnect")
			ws_device_client = null
			device_connected = false
			device_handshake_sent = false
			device_handshake_complete = false
			device_prev_ready_state = -1


func poll_device_connection():
	# This function handles ws_device_client connection/handshake/reconnect logic, called every 2 seconds
	if %BridgeControls.bpioenabled == true:
		if ws_device_client:
			ws_device_client.poll()
			var state = ws_device_client.get_ready_state()
			if state == WebSocketPeer.STATE_OPEN and not device_handshake_sent:
				device_handshake_sent = true
				client_request_timer = 0.0
				client_requests_sent = false
			device_prev_ready_state = state
			if state != WebSocketPeer.STATE_OPEN:
				device_connected = false
				if dialog_shown:
					return
				device_reconnect_timer += 2.0 # Since this is called every 2 seconds
				if device_reconnect_timer >= RECONNECT_DELAY:
					device_retry_count += 1
					_log("[DEBUG] Attempting reconnect #%d..." % device_retry_count)
					stop_device()
					await get_tree().create_timer(0.5).timeout
					start_device()
					device_reconnect_timer = 10.0
					if device_retry_count >= 2:
						_log("[DEBUG] Multiple retries failed (retry count: %d)" % device_retry_count)
					# Wait 1 second before trying ws_client
					await get_tree().create_timer(10.0).timeout
					# Only attempt to connect/reconnect ws_client after ws_device_client attempt
					if not ws_client or ws_client.get_ready_state() != WebSocketPeer.STATE_OPEN:
						stop_client()
						await get_tree().create_timer(1.0).timeout
						start_client()
				device_handshake_sent = false
				client_requests_sent = false
				if $ReconnectTimer.paused or $ReconnectTimer.is_stopped():
					$ReconnectTimer.start()
				return
			else:
				device_connected = true
				device_reconnect_timer = 0.0
				device_retry_count = 0
				dialog_shown = false
				handshake_popup_shown = false
	# After device polling, wait 1 second and call poll_ws_client



func poll_ws_client(_delta):
	if %BridgeControls.enabled == true:
		if ws_client:
			ws_client.poll()
			var state = ws_client.get_ready_state()
			if state == WebSocketPeer.STATE_OPEN and not client_requests_sent:
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
				_log("[DEBUG] Clinet - Sent RequestServerInfo request")
				var request_device_list = [
					{
						"RequestDeviceList": {
							"Id": 1
						}
					}
				]
				ws_client.send_text(JSON.stringify(request_device_list))
				_log("[DEBUG] Sent RequestDeviceList request")
				client_requests_sent = true
			client_prev_ready_state = state
			if state != WebSocketPeer.STATE_OPEN:
				client_connected = false
				if dialog_shown:
					return
				client_reconnect_timer += _delta
				if client_reconnect_timer >= RECONNECT_DELAY:
					client_retry_count += 1
					_log("[Debug] Client - Attempting reconnect #%d..." % client_retry_count)
					#stop_client()
					await get_tree().create_timer(1).timeout
					#start_client()
					client_reconnect_timer = 1.0
					set_device_connected_ok(false)
					if client_retry_count >= 2:
						_log("[Debug] Client - Multiple retries failed (retry count: %d)" % client_retry_count)
						# _show_connection_error_dialog() # Removed
					client_requests_sent = false
					client_request_timer = 0.0
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
					_log("[Debug] Client - Got packet: " + msg_str)
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
									if not found:
										set_device_connected_ok(false)
										_log("OSSM device NOT found in DeviceList.")


func _process(_delta):
	# --- WSDM (device emulation) ---
	if device_connected == true:
		ws_device_client.poll()
		
		# Only handle packet reading here
		while ws_device_client.get_available_packet_count() > 0:
			var packet = ws_device_client.get_packet()
			if packet.size() > 0:
				var msg_str = packet.get_string_from_utf8()
				_log("[DEBUG] Device Got packet: " + msg_str)
				for line in msg_str.split('\n'):
					if line.strip_edges() != "":
						_translate_and_forward(line.strip_edges())
						
	if client_connected == true:
		ws_client.poll()


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
	if device_connected_ok and handshake_popup_dialog:
		%BridgeControls/ConnectionSymbol.self_modulate = Color.SEA_GREEN
		_log("[DEBUG] Dismissing handshake popup dialog")
		if handshake_popup_dialog.visible:
			handshake_popup_dialog.hide()
		if is_instance_valid(handshake_popup_dialog):
			handshake_popup_dialog.queue_free()
			handshake_popup_dialog = null
		handshake_popup_shown = false
	else:
		_log("[DEBUG] Handshake popup dialog not visible, skipping")
		
func _log(log_text:String):
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


func _on_reconnect_timer_timeout() -> void:
	_show_handshake_popup()
	_log("[DEBUG] Timer finished, showing popup")
	pass # Replace with function body.
