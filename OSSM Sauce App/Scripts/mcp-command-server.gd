# mcp_command_server.gd
# HTTP server that receives commands from the MCP server
extends Node

signal command_received(command_data)

var http_server = TCPServer.new()
var clients = []

func _ready():
	# Start HTTP server on port 8081
	var error = http_server.listen(8081, "127.0.0.1")
	if error == OK:
		print("MCP Command server listening on http://127.0.0.1:8081")
	else:
		print("Failed to start MCP server: ", error)


func _process(_delta):
	# Handle new connections
	if http_server.is_connection_available():
		var client = http_server.take_connection()
		clients.append(client)
	
	# Process existing clients
	for i in range(clients.size() - 1, -1, -1):
		var client = clients[i]
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			clients.remove_at(i)
			continue
			
		if client.get_available_bytes() > 0:
			handle_http_request(client)


func handle_http_request(client: StreamPeerTCP):
	var request = client.get_string(client.get_available_bytes())
	
	# Parse HTTP request
	var lines = request.split("\r\n")
	if lines.size() < 1:
		send_http_response(client, 400, {"error": "Bad Request"})
		return
	
	var request_line = lines[0].split(" ")
	if request_line.size() < 3:
		send_http_response(client, 400, {"error": "Bad Request"})
		return
		
	var method = request_line[0]
	var path = request_line[1]
	
	# Handle CORS preflight
	if method == "OPTIONS":
		send_http_response(client, 204, {})
		return
	
	if method != "POST":
		send_http_response(client, 405, {"error": "Method Not Allowed"})
		return
	
	# Find content length and body
	var content_length = 0
	var body_start = -1
	
	for i in range(lines.size()):
		if lines[i].begins_with("Content-Length:"):
			content_length = lines[i].split(":")[1].strip_edges().to_int()
		elif lines[i] == "":
			body_start = i + 1
			break
	
	if body_start == -1:
		send_http_response(client, 400, {"error": "Bad Request"})
		return
	
	# Extract JSON body
	var body = ""
	for i in range(body_start, lines.size()):
		body += lines[i]
		if i < lines.size() - 1:
			body += "\r\n"
	
	# Handle different endpoints
	match path:
		"/send_binary":
			handle_send_binary(client, body)
		"/status":
			handle_status(client)
		_:
			send_http_response(client, 404, {"error": "Not Found", "path": path})


func handle_send_binary(client: StreamPeerTCP, body: String):
	var json = JSON.new()
	var parse_result = json.parse(body)
	
	if parse_result != OK:
		send_http_response(client, 400, {"error": "Invalid JSON"})
		return
	
	var data = json.data
	if not data.has("hex_data"):
		send_http_response(client, 400, {"error": "Missing hex_data field"})
		return
	
	# Convert hex string to binary
	var hex_string = data.hex_data as String
	var binary_data = hex_to_bytes(hex_string)
	
	# Emit signal so the WebSocket bridge can handle it
	command_received.emit(binary_data)
	
	# Log command details
	var command_type = binary_data[0] if binary_data.size() > 0 else -1
	var command_name = get_command_name(command_type)
	
	send_http_response(client, 200, {
		"status": "sent",
		"bytes": binary_data.size(),
		"command": command_name,
		"hex": binary_data.hex_encode()
	})


func handle_status(client: StreamPeerTCP):
	# Get status from the system
	var status = {
		"mcp_server": {
			"running": true,
			"host": "127.0.0.1",
			"port": 8081
		},
		"websocket": get_websocket_status()
	}
	
	send_http_response(client, 200, status)


func get_websocket_status() -> Dictionary:
	# Try to get WebSocket status from bridge or global
	var bridge = get_node_or_null("/root/MCPBridge")
	if bridge and bridge.has_method("get_status"):
		return bridge.get_status()
	
	# Try global WebSocket singleton
	if has_node("%WebSocket"):
		var ws = get_node("%WebSocket")
		return {
			"listening": ws.server.is_listening() if ws.has("server") else false,
			"connected_clients": ws.server.get_client_count() if ws.has("server") else 0,
			"host": ws.host if ws.has("host") else "unknown",
			"port": ws.port if ws.has("port") else 0
		}
	
	return {"status": "WebSocket not found"}


func send_http_response(client: StreamPeerTCP, status_code: int, body_data):
	var status_texts = {
		200: "OK",
		204: "No Content",
		400: "Bad Request",
		404: "Not Found",
		405: "Method Not Allowed",
		500: "Internal Server Error"
	}
	
	var status_text = status_texts.get(status_code, "Unknown")
	var body = JSON.stringify(body_data) if status_code != 204 else ""
	
	var response = "HTTP/1.1 " + str(status_code) + " " + status_text + "\r\n"
	response += "Content-Type: application/json\r\n"
	response += "Content-Length: " + str(body.length()) + "\r\n"
	response += "Access-Control-Allow-Origin: *\r\n"
	response += "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n"
	response += "Access-Control-Allow-Headers: Content-Type\r\n"
	response += "Connection: close\r\n"
	response += "\r\n"
	
	if status_code != 204:
		response += body
	
	client.put_data(response.to_utf8_buffer())
	client.disconnect_from_host()


func hex_to_bytes(hex_string: String) -> PackedByteArray:
	var bytes = PackedByteArray()
	# Remove any spaces or formatting
	hex_string = hex_string.replace(" ", "").replace("\n", "").replace("\t", "")
	
	# Convert pairs of hex characters to bytes
	for i in range(0, hex_string.length(), 2):
		if i + 1 < hex_string.length():
			var hex_byte = hex_string.substr(i, 2)
			var byte_value = hex_byte.hex_to_int()
			bytes.append(byte_value)
	
	return bytes


func get_command_name(command_type: int) -> String:
	# Map command bytes to readable names
	match command_type:
		0x02: return "LOOP"
		0x04: return "VIBRATE"
		0x05: return "PLAY"
		0x06: return "PAUSE"
		0x0A: return "SET_SPEED_LIMIT"
		0x0B: return "SET_GLOBAL_ACCELERATION"
		0x0C: return "SET_RANGE_LIMIT"
		0x0F: return "SMOOTH_MOVE"
		_: return "UNKNOWN(0x" + "%02X" % command_type + ")"


func _exit_tree():
	# Clean up server
	if http_server.is_listening():
		http_server.stop()
		print("MCP Command server stopped")
