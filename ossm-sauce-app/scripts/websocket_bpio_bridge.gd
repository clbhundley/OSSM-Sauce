extends Node

## Buttplug.io WebSocket bridge
## Connects to Intiface Central via WSDM (device emulation),
## receives TCode commands, and forwards them to the OSSM.

var ws_client: WebSocketPeer
var ws_device: WebSocketPeer

var device_connected: bool
var client_connected: bool

var tcode_regex: RegEx

enum { EASE_IN, EASE_OUT, EASE_IN_OUT, EASE_OUT_IN }


func _ready():
	tcode_regex = RegEx.new()
	tcode_regex.compile("([LRVA])(\\d+)(I(\\d+))?(S(\\d+))?")


func start_device():
	if not %BridgeControls/Controls/Enable.button_pressed:
		return
	ws_device = WebSocketPeer.new()
	var address: String = %Menu/BridgeSettings/BPIO/ServerAddress/Input.text
	var port: int = int(%Menu/BridgeSettings/BPIO/Ports/WSDMPort/Input.value)
	var url: String = "ws://%s:%d" % [address, port]
	ws_device.connect_to_url(url)
	await get_tree().create_timer(0.2).timeout
	ws_device.poll()
	var state = ws_device.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_log("Connected to WSDM at " + url)
		var handshake = {
			"identifier": %Menu/BridgeSettings/BPIO/Identifier/Input.text,
			"address": %Menu/BridgeSettings/BPIO/Address/Input.text,
			"version": 0
		}
		ws_device.send_text(JSON.stringify(handshake))
		start_client()
	elif state == WebSocketPeer.STATE_CLOSED:
		_log("WSDM connection failed")
		await get_tree().create_timer(2).timeout
		start_device()


func start_client():
	ws_client = WebSocketPeer.new()
	var address: String = %Menu/BridgeSettings/BPIO/ServerAddress/Input.text
	var port: int = int(%Menu/BridgeSettings/BPIO/Ports/ServerPort/Input.value)
	var url: String = "ws://%s:%d" % [address, port]
	ws_client.connect_to_url(url)
	await get_tree().create_timer(0.2).timeout
	ws_client.poll()
	if ws_client.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_log("Could not connect to Buttplug server at " + url)
		return
	_log("Connected to Buttplug server at " + url)
	# Handshake: request server info then device list
	ws_client.send_text(JSON.stringify([{
		"RequestServerInfo": {
			"Id": 2,
			"ClientName": %Menu/BridgeSettings/BPIO/ClientName/Input.text,
			"MessageVersion": 3
		}
	}]))
	await get_tree().create_timer(0.1).timeout
	ws_client.send_text(JSON.stringify([{
		"RequestDeviceList": {"Id": 1}
	}]))
	client_connected = true
	poll_device_list()


func poll_device_list():
	if not client_connected:
		return
	ws_client.poll()
	await get_tree().create_timer(0.1).timeout
	while ws_client.get_available_packet_count() > 0:
		var packet = ws_client.get_packet()
		if packet.size() == 0:
			continue
		var msg = packet.get_string_from_utf8()
		_log("Client: " + msg)
		var json = JSON.new()
		if json.parse(msg) != OK or typeof(json.data) != TYPE_ARRAY:
			continue
		for obj in json.data:
			if not obj.has("DeviceList"):
				continue
			for device in obj["DeviceList"].get("Devices", []):
				if device.get("DeviceName") == "TCode v0.3 (Single Linear Axis)":
					_log("OSSM device found in Buttplug device list!")
					set_connected(true)
					stop_client()
					return
			_log("OSSM device not found in device list.")
			set_connected(false)


func stop_client():
	if ws_client and ws_client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_client.close(1000, "Client stopped")
	ws_client = null
	client_connected = false


func stop_device():
	if ws_device and ws_device.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_device.close(1000, "Device stopped")
	ws_device = null
	device_connected = false
	%BridgeControls/ConnectionSymbol.self_modulate = Color.WHITE_SMOKE
	%BridgeControls/ConnectionSymbol.self_modulate.a = 0.2


func set_connected(connected: bool):
	device_connected = connected
	if connected:
		%BridgeControls/ConnectionSymbol.self_modulate = Color.SEA_GREEN
		%BridgeControls/ConnectionSymbol.self_modulate.a = 1.0
		_log("Device connected!")
	else:
		%BridgeControls/ConnectionSymbol.self_modulate = Color.WHITE_SMOKE
		%BridgeControls/ConnectionSymbol.self_modulate.a = 0.2


func _process(_delta):
	if ws_device:
		ws_device.poll()
	if ws_client:
		ws_client.poll()
	if not device_connected or not ws_device:
		return
	while ws_device.get_available_packet_count() > 0:
		var packet = ws_device.get_packet()
		if packet.size() == 0:
			continue
		var msg = packet.get_string_from_utf8()
		_log("T-code: " + msg)
		for line in msg.split('\n'):
			var cmd = line.strip_edges()
			if cmd != "":
				_translate_and_forward(cmd)


func _translate_and_forward(tcode_cmd: String):
	for result in tcode_regex.search_all(tcode_cmd):
		var type = result.get_string(1)
		var digits = result.get_string(2)
		var channel = int(digits[0])
		var value_str = digits.substr(1)
		var magnitude = int(value_str)
		var interval = int(result.get_string(4)) if result.get_string(4) != "" else 0
		if channel != 0:
			continue
		match type:
			"L":
				# Intiface sends 0-1000 range (0%=0, 100%=1000)
				var depth: int = clampi(magnitude * 10, 0, 10000)
				var ms_duration: int = clampi(interval if interval > 0 else 100, %BridgeControls.min_move_duration, %BridgeControls.max_move_duration)
				_log("  → magnitude=%d, depth=%d, duration=%dms" % [magnitude, depth, ms_duration])
				send_smooth_move(ms_duration, depth, %BridgeControls.auto_smoothing, EASE_IN_OUT, 0)
			"V":
				pass # TODO: Map to OSSM vibrate


func send_smooth_move(ms_duration: int, depth: int, trans: int, ease: int, auxiliary: int):
	if not %WebSocket.ossm_connected:
		return
	var command: PackedByteArray
	command.resize(10)
	command.encode_u8(0, OSSM.Command.SMOOTH_MOVE)
	command.encode_u32(1, ms_duration)
	command.encode_u16(5, abs(owner.motor_direction * 10000 - depth))
	command.encode_u8(7, trans)
	command.encode_u8(8, ease)
	command.encode_u8(9, auxiliary)
	%WebSocket.server.broadcast_binary(command)


func _log(text: String):
	if not %Menu/BridgeSettings/LoggingEnabled.button_pressed:
		return
	var log_node = %BridgeControls/Log
	log_node.text += text + "\n"
	var lines = log_node.text.split("\n")
	if lines.size() > 1000:
		log_node.text = "\n".join(lines.slice(lines.size() - 1000))
