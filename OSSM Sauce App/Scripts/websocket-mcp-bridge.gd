# websocket_mcp_bridge.gd
# Bridges MCP commands to WebSocket binary broadcasts

extends Node

# Reference to the MCP command server
@export var mcp_command_server: Node  # Assign this in the editor
@export var websocket_node_path: NodePath = "%WebSocket"  # Path to WebSocket node

var websocket_node: Node

func _ready():
	# Get WebSocket node
	websocket_node = get_node_or_null(websocket_node_path)
	if not websocket_node:
		push_error("WebSocket MCP Bridge: WebSocket node not found at path: " + str(websocket_node_path))
		return
	
	# Connect to the MCP command server's signal
	if mcp_command_server:
		mcp_command_server.command_received.connect(_on_mcp_command_received)
		print("WebSocket MCP Bridge: Connected to command server")
	else:
		push_error("WebSocket MCP Bridge: No MCP command server assigned!")


func _on_mcp_command_received(command_data):
	if not websocket_node:
		push_error("WebSocket MCP Bridge: WebSocket node not available")
		return
		
	if command_data is PackedByteArray:
		# Handle binary command data
		if websocket_node.server and websocket_node.server.is_listening():
			%WebSocket.server.broadcast_binary(command_data)
		else:
			push_warning("WebSocket MCP Bridge: Cannot send command - WebSocket server not listening")
			print("Command data: ", command_data.hex_encode())
	else:
		push_warning("WebSocket MCP Bridge: Unexpected command data type: ", type_string(typeof(command_data)))
