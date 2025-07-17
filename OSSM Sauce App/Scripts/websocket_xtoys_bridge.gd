extends Node

var ws_server:WebSocketServer
@export var xtoys_port := 8080
@export var auto_reconnect := true
@export var debug_log := true
@export var enabled := true
var xtoys_running:bool
var speed_timer:Timer
var speed_mode_active:bool
var speed_upper := 10000
var speed_lower := 0
var speed_ms := 1000
var speed_next_target := 0
var message_queue:Array

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

func set_port(port: int):
	xtoys_port = port
	if xtoys_running:
		stop_xtoys()
		start_xtoys()

func get_port() -> int:
	return xtoys_port

func set_log_log(val: bool):
	debug_log = val

func set_enabled(val: bool):
	enabled = val
	if enabled and not xtoys_running:
		start_xtoys()
	elif not enabled and xtoys_running:
		stop_xtoys()

func start_xtoys():
	if not enabled:
		_log("xtoys bridge disabled, not starting")
		return
	if xtoys_running:
		_log("xtoys bridge already running")
		return
	
	_log("Starting xtoys WebSocket server on port %d" % xtoys_port)
	ws_server = WebSocketServer.new()
	ws_server.client_connected.connect(_on_client_connected)
	ws_server.client_disconnected.connect(_on_client_disconnected)
	ws_server.message_received.connect(_on_message_received)
	var ok = ws_server.start(xtoys_port)
	if ok:
		_log("WebSocket server started on port %d" % xtoys_port)
		%BridgeControls/ConnectionSymbol.self_modulate = Color.WHITE_SMOKE
		xtoys_running = true
	else:
		_log("Failed to start WebSocket server on port %d" % xtoys_port)

func stop_xtoys():
	_log("Stopping xtoys WebSocket server")
	if ws_server:
		ws_server.stop()
		ws_server = null
		_log("WebSocket server stopped")
	else:
		_log("No WebSocket server to stop")
	xtoys_running = false
	_stop_speed_mode()
	_log("xtoys bridge stopped")

func _process(delta):
	if ws_server and ws_server.is_listening():
		ws_server.process()
	# Process up to 10 messages per frame
	var processed = 0
	while message_queue.size() > 0 and processed < 10:
		var result = message_queue.pop_front()
		_log("Processing queued xtoys message: %s" % str(result))
		if result.has("mode"):
			_log("Processing mode: %s" % result["mode"])
			match result["mode"]:
				"position":
					_log("Handling position command")
					_stop_speed_mode()
					_handle_position(result)
				"speed":
					_log("Handling speed command")
					_handle_speed(result)
				_:
					_log("Unknown mode: %s" % result["mode"])
		else:
			_log("No 'mode' key found in message")
		processed += 1

func _on_client_connected(client_id):
	%BridgeControls/ConnectionSymbol.self_modulate = Color.SEA_GREEN
	_log("xtoys client connected: %d" % client_id)

func _on_client_disconnected(client_id, code):
	_log("xtoys client disconnected: %d (code: %d)" % [client_id, code])
	_stop_speed_mode()

func _on_message_received(client_id, message):
	_log("message from xtoys client %d: %s" % [client_id, message])
	var result = JSON.parse_string(message)
	_log("Parsed JSON result type: %s" % typeof(result))
	if typeof(result) != TYPE_DICTIONARY:
		_log("Invalid xtoys JSON - expected Dictionary, got %s" % typeof(result))
		return
	# Queue the message for batch processing
	message_queue.append(result)

func _handle_position(cmd):
	_log("Position command received: %s" % cmd)
	var duration = int(cmd.get("duration", 100))
	var position = int(cmd.get("position", 0))
	var depth = clamp(int(round(remap(position, 0, 100, 0, 10000))), 0, 10000)
	var trans = %BridgeControls.auto_smoothing
	var ease = EASE_IN_OUT
	var auxiliary = 0
	_log("Sending smooth move: duration=%d, depth=%d, trans=%d, ease=%d" % [duration, depth, trans, ease])
	_send_smooth_move(duration, depth, trans, ease, auxiliary)

func _handle_speed(cmd):
	_log("Speed command received: %s" % cmd)
	# speed is ms per stroke, upper/lower are 0-100
	var speed = int(cmd.get("speed", 1000))
	if speed == 0:
		_log("Ignoring speed command with speed=0")
		return
	var upper = int(cmd.get("upper", 100))
	var lower = int(cmd.get("lower", 0))
	speed_upper = clamp(int(round(remap(upper, 0, 100, 0, 10000))), 0, 10000)
	speed_lower = clamp(int(round(remap(lower, 0, 100, 0, 10000))), 0, 10000)
	speed_ms = speed
	speed_next_target = speed_upper
	_log("Speed mode params: speed=%d, upper=%d, lower=%d" % [speed, speed_upper, speed_lower])
	if not speed_mode_active:
		_log("Starting speed mode")
		_start_speed_mode()
	else:
		_log("Speed mode already active")

func _start_speed_mode():
	speed_mode_active = true
	if speed_timer:
		speed_timer.stop()
		speed_timer = null
	speed_timer = Timer.new()
	speed_timer.wait_time = float(speed_ms) / 1000.0
	speed_timer.one_shot = false
	speed_timer.timeout.connect(_on_speed_timer_timeout)
	add_child(speed_timer)
	speed_timer.start()
	# Start at lower, move to upper
	var trans_type = %BridgeControls.auto_smoothing
	_send_smooth_move(int(speed_ms / 2), speed_lower, trans_type, EASE_IN_OUT, 0)
	speed_next_target = speed_upper

func _stop_speed_mode():
	speed_mode_active = false
	if speed_timer:
		speed_timer.stop()
		remove_child(speed_timer)
		speed_timer = null

func _on_speed_timer_timeout():
	# Alternate between upper and lower
	var trans_type:int = %BridgeControls.auto_smoothing
	if speed_next_target == speed_upper:
		_send_smooth_move(speed_ms, speed_upper, trans_type, EASE_IN_OUT, 0)
		speed_next_target = speed_lower
	else:
		_send_smooth_move(speed_ms, speed_lower, trans_type, EASE_IN_OUT, 0)
		speed_next_target = speed_upper

func _send_smooth_move(ms_duration:int, depth:int, trans:int, ease:int, auxiliary:int):
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
	_log("Sending smooth move command: duration=%d, depth=%d, trans=%d, ease=%d, aux=%d" % [ms_duration, depth, trans, ease, auxiliary])
	var command:PackedByteArray
	command.resize(10)
	command.encode_u8(0, OSSM.Command.SMOOTH_MOVE)
	command.encode_u32(1, ms_duration)
	command.encode_u16(5, depth)
	command.encode_u8(7, trans)
	command.encode_u8(8, ease)
	command.encode_u8(9, auxiliary)
	_log("Command bytes: %s" % command.hex_encode())
	if %WebSocket.ossm_connected:
		_log("WebSocket connected, broadcasting command")
		%WebSocket.server.broadcast_binary(command)
	else:
		_log("WebSocket not connected, cannot send command") 

func _log(log_text:String):
	%BridgeControls/Log.text += log_text + "\n"

#func _debug(msg):
	#if debug_log:
		#print("[xtoys] %s" % msg) 
