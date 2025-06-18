# Add this to your existing Godot app
# Create a new script: mcp_command_server.gd

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
		send_http_response(client, 400, "Bad Request")
		return
	
	var request_line = lines[0].split(" ")
	if request_line.size() < 3 or request_line[0] != "POST":
		send_http_response(client, 405, "Method Not Allowed")
		return
	
	var path = request_line[1]
	
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
		send_http_response(client, 400, "Bad Request")
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
		"/connect":
			handle_connect(client, body)
		"/disconnect":
			handle_disconnect(client, body)
		"/status":
			handle_status(client)
		_:
			send_http_response(client, 404, "Not Found")

func handle_send_binary(client: StreamPeerTCP, body: String):
	var json = JSON.new()
	var parse_result = json.parse(body)
	
	if parse_result != OK:
		send_http_response(client, 400, "Invalid JSON")
		return
	
	var data = json.data
	if not data.has("hex_data"):
		send_http_response(client, 400, "Missing hex_data field")
		return
	
	# Convert hex string to binary and send via WebSocket
	var hex_string = data.hex_data as String
	var binary_data = hex_to_bytes(hex_string)
	
	# Emit signal so your main WebSocket logic can handle it
	command_received.emit(binary_data)
	
	send_http_response(client, 200, '{"status": "sent", "bytes": ' + str(binary_data.size()) + '}')

func handle_connect(client: StreamPeerTCP, body: String):
	var json = JSON.new()
	var parse_result = json.parse(body)
	
	if parse_result != OK:
		send_http_response(client, 400, "Invalid JSON")
		return
	
	var data = json.data
	var url = data.get("url", "")
	
	# Emit signal for your WebSocket connection logic
	command_received.emit({"action": "connect", "url": url})
	
	send_http_response(client, 200, '{"status": "connecting", "url": "' + url + '"}')

func handle_disconnect(client: StreamPeerTCP, _body: String):
	# Emit signal for disconnect
	command_received.emit({"action": "disconnect"})
	
	send_http_response(client, 200, '{"status": "disconnected"}')

func handle_status(client: StreamPeerTCP):
	# Get status from WebSocket bridge if available
	var bridge = get_node_or_null("../MCPBridge") # Adjust path as needed
	var status = {
		"websocket_listening": false,
		"connected_clients": 0,
		"server_started": false,
		"ossm_connected": false
	}
	
	if bridge and bridge.has_method("get_status"):
		status = bridge.get_status()
	else:
		# Fallback to direct WebSocket status if bridge not found
		status = {
			"websocket_listening": %WebSocket.server.is_listening(),
			"connected_clients": %WebSocket.server.get_client_count(),
			"websocket_host": %WebSocket.host,
			"websocket_port": %WebSocket.port,
			"server_started": %WebSocket.server_started,
			"ossm_connected": %WebSocket.ossm_connected,
			"has_mcp_server": true
		}
	
	send_http_response(client, 200, JSON.stringify(status))

func send_http_response(client: StreamPeerTCP, status_code: int, body: String):
	var status_text = "OK" if status_code == 200 else "Error"
	var response = "HTTP/1.1 " + str(status_code) + " " + status_text + "\r\n"
	response += "Content-Type: application/json\r\n"
	response += "Content-Length: " + str(body.length()) + "\r\n"
	response += "Access-Control-Allow-Origin: *\r\n"
	response += "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n"
	response += "Access-Control-Allow-Headers: Content-Type\r\n"
	response += "\r\n"
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

# Connect this to your existing WebSocket logic
func _on_command_received(command_data):
	if command_data is Dictionary:
		# Handle connect/disconnect commands
		match command_data.action:
			"connect":
				# Call your existing WebSocket connect function
				print("Connecting to: ", command_data.url)
			"disconnect":
				# Call your existing WebSocket disconnect function
				print("Disconnecting from WebSocket")
	elif command_data is PackedByteArray:
		# Send binary data via WebSocket
		# Call your existing WebSocket send function
		print("Sending binary data: ", command_data.size(), " bytes")
		# your_%WebSocket.send(command_data, WebSocketPeer.WRITE_MODE_BINARY)
