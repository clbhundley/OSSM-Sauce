extends Node

const WebSocketSessionManagerScript = preload("res://scripts/ossm_sauce_parts/websocket_session_manager.gd")

var server: WebSocketServer

var port: int = 8008
var host: String = "0.0.0.0"

var server_started: bool
var ossm_connected: bool
var ping_timer: Timer
var _session_manager = WebSocketSessionManagerScript.new()

func _ready():
	_session_manager.setup(owner, self)
	server = WebSocketServer.new()
	server.client_connected.connect(_on_client_connected)
	server.client_disconnected.connect(_on_client_disconnected)
	server.message_received.connect(_on_message_received)
	server.data_received.connect(_on_data_received)
	server.server_error.connect(_on_server_error)
	ping_timer = Timer.new()
	ping_timer.wait_time = 3.0
	ping_timer.timeout.connect(func(): server.broadcast_ping())
	add_child(ping_timer)


func start_server():
	server_started = server.start(port, host)
	if server_started:
		print("WebSocket server started successfully on port %d" % port)
		ping_timer.start()
	else:
		printerr("Failed to start WebSocket server on port %d" % port)
	
	update_server_status()


# Process signals from the main thread to listen for incoming messages
func _process(delta: float) -> void:
	if server and server.is_listening():
		server.process()


func update_server_status():
	if server.is_listening():
		print("Server Status: Running on %s:%d" % [host, port])
		%WiFi.self_modulate = Color.WHITE
		%WiFi.show()
		server_started = true
	else:
		print("Server Status: Stopped")
		%WiFi.hide()
		server_started = false
		ossm_connected = false
	update_client_count()


func update_client_count():
	print("Connected Clients: %d" % server.get_client_count())


func _on_client_connected(client_id):
	print("Client connected: #%d" % client_id)
	update_client_count()


func _on_client_disconnected(client_id, code):
	print("Client disconnected: #%d (code: %d)" % [client_id, code])
	update_client_count()
	if server.get_client_count() == 0:
		_on_client_disconnected_cleanup()


func _on_message_received(client_id, message):
	print("Text message from client %d: %s" % [client_id, message])


func _on_data_received(client_id, data):
	if data[0] == OSSM.Command.RESPONSE:
		_session_manager.handle_response(data)


func _on_client_disconnected_cleanup():
	_session_manager.handle_disconnect_cleanup()


func _on_server_error(error):
	printerr("Server error: %s" % error)


func _exit_tree():
	if server and server.is_listening():
		server.stop()
