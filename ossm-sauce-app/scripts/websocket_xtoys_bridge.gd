extends Node

## XToys WebSocket bridge
## Designed to use Position and Speed controls on xtoys.app

var ws_server: WebSocketServer

var xtoys_running: bool

var speed_mode_min_depth: int
var speed_mode_max_depth: int
var speed_mode_stroke_duration_ms: int

var push_stroke: bool = true

enum { EASE_IN, EASE_OUT, EASE_IN_OUT, EASE_OUT_IN }


func start_xtoys():
	if xtoys_running:
		_log("xtoys bridge already running")
		return
	
	var port: int = %Menu/BridgeSettings/XToys/Port/Input.value
	_log("Starting xtoys WebSocket server on port %d" % int(port))
	ws_server = WebSocketServer.new()
	ws_server.client_connected.connect(_on_client_connected)
	ws_server.client_disconnected.connect(_on_client_disconnected)
	ws_server.message_received.connect(_on_message_received)
	ws_server.server_error.connect(_on_server_error)
	var ok = ws_server.start(int(port))
	if ok:
		_log("WebSocket server started on port %d" % int(port))
		%BridgeControls/ConnectionSymbol.self_modulate = Color.WHITE_SMOKE
		xtoys_running = true
		$PingTimer.start()
	else:
		_log("Failed to start WebSocket server on port %d" % int(port))


func stop_xtoys():
	_log("Stopping xtoys WebSocket server")
	if ws_server:
		ws_server.stop()
		ws_server = null
		_log("WebSocket server stopped")
	else:
		_log("No WebSocket server to stop")
	%BridgeControls/ConnectionSymbol.self_modulate = Color.WHITE_SMOKE
	%BridgeControls/ConnectionSymbol.self_modulate.a = 0.2
	xtoys_running = false
	$SpeedTimer.stop()
	$PingTimer.stop()
	_log("xtoys bridge stopped")


func _process(delta):
	if ws_server and ws_server.is_listening():
		ws_server.process()


func _on_client_connected(client_id):
	%BridgeControls/ConnectionSymbol.self_modulate = Color.SEA_GREEN
	_log("xtoys client connected: %d" % client_id)


func _on_client_disconnected(client_id, code):
	_log("xtoys client disconnected: %d (code: %d)" % [client_id, code])
	$SpeedTimer.stop()


func _on_message_received(client_id, message):
	var xtoys_command:Dictionary = JSON.parse_string(message)
	
	if not xtoys_command:
		_log("ERROR: Invalid XToys command!")
		return
	
	_log("")
	_log("XToys JSON command:")
	_log(JSON.stringify(xtoys_command, "\t"))
	_log("")
	
	if not xtoys_command.has('mode'):
		_log("ERROR: XToys command does not contain a mode!")
		return
	
	match xtoys_command.mode:
		"position":
			position_command(xtoys_command)
		"speed":
			speed_command(xtoys_command)
		_:
			_log("Unknown mode: %s" % xtoys_command.mode)


func position_command(xtoys_command):
	_log("Position command received")
	
	$SpeedTimer.stop()
	
	for section in ['position', 'duration']:
		if not xtoys_command.has(section):
			_log("ERROR: XToys position command missing section: %s" % section)
			return
	
	var use_command_duration: bool = %Menu/BridgeSettings/XToys/UseCommandDuration.button_pressed
	var max_msg_frequency: float = %Menu/BridgeSettings/XToys/MaxMsgFrequency/Input.value
	
	var stroke_duration_ms: int
	if use_command_duration:
		stroke_duration_ms = int(xtoys_command.duration)
	else:
		stroke_duration_ms = int(1000.0 / max_msg_frequency)
	stroke_duration_ms = clampi(stroke_duration_ms, %BridgeControls.min_move_duration, %BridgeControls.max_move_duration)
	
	var stroke_target_position: int = int(remap(clampf(xtoys_command.position, 0, 100), 0, 100, 0, 10000))
	
	var trans: int = %BridgeControls.auto_smoothing
	var ease: int = EASE_IN_OUT
	var auxiliary: int = 0
	
	send_smooth_move(stroke_duration_ms, stroke_target_position, trans, ease, auxiliary)

func speed_command(xtoys_command):
	_log("Speed command received")
	
	for section in ['speed', 'lower', 'upper']:
		if not xtoys_command.has(section):
			_log("ERROR: XToys speed command missing section: %s" % section)
			return
	
	var _speed: int = clamp(int(xtoys_command.speed), 0, 100)
	speed_mode_stroke_duration_ms = int(remap(_speed, 0, 100, %BridgeControls.max_move_duration, %BridgeControls.min_move_duration))
	
	if _speed == 0:
		$SpeedTimer.stop()
		_log("Speed = 0 -- Pausing")
		return
	
	var _min_depth: int = clamp(int(xtoys_command.lower), 0, 100)
	speed_mode_min_depth = remap(_min_depth, 0, 100, 0, 10000)
	
	var _max_depth: int = clamp(int(xtoys_command.upper), 0, 100)
	speed_mode_max_depth = remap(_max_depth, 0, 100, 0, 10000)
	
	push_stroke = true
	_on_speed_timer_timeout() # Start immediately
	$SpeedTimer.wait_time = speed_mode_stroke_duration_ms / float(1000)
	$SpeedTimer.start()


func _on_speed_timer_timeout():
	var trans: int = %BridgeControls.auto_smoothing
	var ease: int = EASE_IN_OUT
	var aux: int = 0
	
	if push_stroke:
		send_smooth_move(speed_mode_stroke_duration_ms, speed_mode_min_depth, trans, ease, aux)
	else:
		send_smooth_move(speed_mode_stroke_duration_ms, speed_mode_max_depth, trans, ease, aux)
	
	push_stroke = !push_stroke


func send_smooth_move(ms_duration: int, depth: int, trans: int, ease: int, auxiliary: int):
	if not %WebSocket.ossm_connected:
		return
	_log("  → duration=%d, depth=%d, trans=%d, ease=%d" % [ms_duration, depth, trans, ease])
	var command: PackedByteArray
	command.resize(10)
	command.encode_u8(0, OSSM.Command.SMOOTH_MOVE)
	command.encode_u32(1, ms_duration)
	command.encode_u16(5, abs(owner.motor_direction * 10000 - depth))
	command.encode_u8(7, trans)
	command.encode_u8(8, ease)
	command.encode_u8(9, auxiliary)
	%WebSocket.server.broadcast_binary(command)


func _on_ping_timer_timeout():
	if ws_server and ws_server.is_listening():
		ws_server.broadcast_ping()


func _on_server_error(error):
	printerr("Server error: %s" % error)
	_log("Server error: %s" % error)


func _log(log_text: String):
	if not %Menu/BridgeSettings/LoggingEnabled.button_pressed:
		return
	var log_node = %BridgeControls/Log
	log_node.text += log_text + "\n"
	var lines = log_node.text.split("\n")
	if lines.size() > 1000:
		log_node.text = "\n".join(lines.slice(lines.size() - 1000))
