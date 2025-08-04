extends Node

## Bridge MCP commands to WebSocket binary broadcasts

func _ready():
	$MCPCommandServer.command_received.connect(_on_mcp_command_received)


func _on_mcp_command_received(command_data):
	if command_data is Dictionary:
		match command_data.action:
			"connect":
				handle_websocket_connect(command_data.url)
			"disconnect":
				handle_websocket_disconnect()
			_:
				_log("WebSocket MCP Bridge: Unknown action: " + command_data.action)
	
	elif command_data is PackedByteArray:
		if %WebSocket.server.is_listening():
			broadcast_binary_command(command_data)
		else:
			_log("WebSocket MCP Bridge: Cannot send command - WebSocket server not listening")
			_log("Command data: " + command_data.hex_encode())


func handle_websocket_connect(url: String):
	_log("WebSocket MCP Bridge: Starting WebSocket server")
	if not %WebSocket.server.is_listening():
		%WebSocket.start_server()
		_log("WebSocket MCP Bridge: Server started on " + %WebSocket.host + ":" + %WebSocket.port)
	else:
		_log("WebSocket MCP Bridge: Server already running")


func handle_websocket_disconnect():
	_log("WebSocket MCP Bridge: Stopping WebSocket server")
	if %WebSocket.server.is_listening():
		%WebSocket.server.stop()
		_log("WebSocket MCP Bridge: Server stopped")
	else:
		_log("WebSocket MCP Bridge: Server already stopped")


func broadcast_binary_command(binary_data: PackedByteArray):
	%WebSocket.server.broadcast_binary(binary_data)
	
	var command_type:int = binary_data[0] if binary_data.size() > 0 else -1
	var command_name:String = get_command_name(command_type)
	var client_count:int = %WebSocket.server.get_client_count()
	
	_log(
		"WebSocket MCP Bridge: Broadcasted " +
		command_name + " (" + str(binary_data.size()) + " bytes) to " + 
		str(client_count) + " clients: " + binary_data.hex_encode())


func get_command_name(command_type: int) -> String:
	match command_type:
		0x00: return "RESPONSE"
		0x01: return "MOVE"
		0x02: return "LOOP"
		0x03: return "POSITION"
		0x04: return "VIBRATE"
		0x05: return "PLAY"
		0x06: return "PAUSE"
		0x07: return "RESET"
		0x08: return "HOMING"
		0x09: return "CONNECTION"
		0x0A: return "SET_SPEED_LIMIT"
		0x0B: return "SET_GLOBAL_ACCELERATION"
		0x0C: return "SET_RANGE_LIMIT"
		0x0D: return "SET_HOMING_SPEED"
		0x0E: return "SET_HOMING_TRIGGER"
		0x0F: return "SMOOTH_MOVE"
		_: return "UNKNOWN(" + str(command_type) + ")"


func get_status() -> Dictionary:
	return {
		"websocket_listening": %WebSocket.server.is_listening(),
		"connected_clients": %WebSocket.server.get_client_count(),
		"websocket_host": %WebSocket.host,
		"websocket_port": %WebSocket.port,
		"server_started": %WebSocket.server_started,
		"ossm_connected": %WebSocket.ossm_connected,
		"has_mcp_server": $MCPCommandServer.http_server != null
	}


func _log(log_text:String):
	if %Menu/BridgeSettings/LoggingEnabled.button_pressed:
		%BridgeControls/Log.text += log_text + "\n"
