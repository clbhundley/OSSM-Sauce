# websocket_mcp_bridge.gd
# Bridges MCP commands to WebSocket binary broadcasts

extends Node

# Reference to the MCP command server
@export var mcp_command_server: Node  # Assign this in the editor

func _ready():
	# Connect to the MCP command server's signal
	if mcp_command_server:
		mcp_command_server.command_received.connect(_on_mcp_command_received)
		print("WebSocket MCP Bridge: Connected to command server")
	else:
		print("WebSocket MCP Bridge: No MCP command server assigned!")

func _on_mcp_command_received(command_data):
	if command_data is Dictionary:
		# Handle connection management commands
		match command_data.action:
			"connect":
				handle_websocket_connect(command_data.url)
			"disconnect":
				handle_websocket_disconnect()
			_:
				print("WebSocket MCP Bridge: Unknown action: ", command_data.action)
	
	elif command_data is PackedByteArray:
		# Handle binary command data
		if %WebSocket.server.is_listening():
			broadcast_binary_command(command_data)
		else:
			print("WebSocket MCP Bridge: Cannot send command - WebSocket server not listening")
			print("Command data: ", command_data.hex_encode())

func handle_websocket_connect(url: String):
	print("WebSocket MCP Bridge: Starting WebSocket server")
	# Since your WebSocket is a server, not a client, we just start the server
	# The URL parameter is ignored since your server runs on predefined host:port
	if not %WebSocket.server.is_listening():
		%WebSocket.start_server()
		print("WebSocket MCP Bridge: Server started on ", %WebSocket.host, ":", %WebSocket.port)
	else:
		print("WebSocket MCP Bridge: Server already running")

func handle_websocket_disconnect():
	print("WebSocket MCP Bridge: Stopping WebSocket server")
	if %WebSocket.server.is_listening():
		%WebSocket.server.stop()
		print("WebSocket MCP Bridge: Server stopped")
	else:
		print("WebSocket MCP Bridge: Server already stopped")

func broadcast_binary_command(binary_data: PackedByteArray):
	# Use the global WebSocket singleton to broadcast
	%WebSocket.server.broadcast_binary(binary_data)
	
	# Log the command for debugging
	var command_type = binary_data[0] if binary_data.size() > 0 else -1
	var command_name = get_command_name(command_type)
	var client_count = %WebSocket.server.get_client_count()
	
	print("WebSocket MCP Bridge: Broadcasted ", command_name, " (", binary_data.size(), " bytes) to ", client_count, " clients: ", binary_data.hex_encode())

func get_command_name(command_type: int) -> String:
	# Map command bytes to readable names for logging
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
		_: return "UNKNOWN(" + str(command_type) + ")"

# Status method for debugging and MCP server status endpoint
func get_status() -> Dictionary:
	return {
		"websocket_listening": %WebSocket.server.is_listening(),
		"connected_clients": %WebSocket.server.get_client_count(),
		"websocket_host": %WebSocket.host,
		"websocket_port": %WebSocket.port,
		"server_started": %WebSocket.server_started,
		"ossm_connected": %WebSocket.ossm_connected,
		"has_mcp_server": mcp_command_server != null
	}
