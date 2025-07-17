extends Node

var server: WebSocketServer

var port:int = 8008
var host:String = "0.0.0.0"

var server_started:bool
var ossm_connected:bool

func _ready():
	server = WebSocketServer.new()
	server.client_connected.connect(_on_client_connected)
	server.client_disconnected.connect(_on_client_disconnected)
	server.message_received.connect(_on_message_received)
	server.data_received.connect(_on_data_received)
	server.server_error.connect(_on_server_error)


func start_server():
	server_started = server.start(port, host)
	if server_started:
		print("WebSocket server started successfully on port %d" % port)
	else:
		printerr("Failed to start WebSocket server on port %d" % port)
	
	update_server_status()


# Process signals from the main thread to listen for incoming messages
func _process(delta:float) -> void:
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


func _on_message_received(client_id, message):
	print("Text message from client %d: %s" % [client_id, message])


func _on_data_received(client_id, data):
	if data[0] == OSSM.Command.RESPONSE:
		match data[1]:
			OSSM.Command.CONNECTION:
				%WiFi.self_modulate = Color.SEA_GREEN
				%WiFi.show()
				ossm_connected = true
				owner.apply_device_settings()
				owner.home_to(0)
			OSSM.Command.HOMING:
				%CircleSelection.hide()
				%CircleSelection.homing_lock = false
				var display = [
					%PositionControls,
					%LoopControls,
					%PathDisplay,
					%ActionPanel,
					%Menu]
				for node in display:
					node.modulate.a = 1
				owner.emit_signal("homing_complete")
				if AppMode.active == AppMode.AppMode.MOVE:
					if owner.active_path_index != null:
						%CircleSelection.show_play()
				elif AppMode.active == AppMode.AppMode.POSITION:
					owner.play()


func _on_server_error(error):
	printerr("Server error: %s" % error)


func _exit_tree():
	if server and server.is_listening():
		server.stop()
