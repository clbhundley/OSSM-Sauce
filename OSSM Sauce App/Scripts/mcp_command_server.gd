extends Node

signal command_received(command_data)

var http_server := TCPServer.new()
var clients:Array


func start_mcp_server():
	var port:int = %Menu/BridgeSettings/MCP/Port/Input.value
	var error = http_server.listen(port, "127.0.0.1")
	if error == OK:
		get_parent()._log("MCP Command server listening on port " + str(port))
		%BridgeControls/ConnectionSymbol.self_modulate = Color.SEA_GREEN
		set_process(true)
	else:
		get_parent()._log("Failed to start MCP server: ", str(error))


func stop_mcp_server():
	http_server.stop()
	get_parent()._log("MCP Command server stopped")
	set_process(false)


func _process(_delta):
	if http_server.is_connection_available():
		var client:StreamPeerTCP = http_server.take_connection()
		clients.append(client)
	
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
	
	var hex_string = data.hex_data as String
	var binary_data = hex_to_bytes(hex_string)
	
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
	
	command_received.emit({"action": "connect", "url": url})
	send_http_response(client, 200, '{"status": "connecting", "url": "' + url + '"}')


func handle_disconnect(client: StreamPeerTCP, _body: String):
	command_received.emit({"action": "disconnect"})
	send_http_response(client, 200, '{"status": "disconnected"}')


func handle_status(client: StreamPeerTCP):
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
	
	hex_string = hex_string.replace(" ", "").replace("\n", "").replace("\t", "")
	
	# Convert pairs of hex characters to bytes
	for i in range(0, hex_string.length(), 2):
		if i + 1 < hex_string.length():
			var hex_byte = hex_string.substr(i, 2)
			var byte_value = hex_byte.hex_to_int()
			bytes.append(byte_value)
	
	return bytes
