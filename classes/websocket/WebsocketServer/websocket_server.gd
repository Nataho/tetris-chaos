extends Node

#region Variables
@export var listen_port: int = 8080
@export var broadcast_port: int = 4242

var server_active := false
var tcp_server = TCPServer.new()
var connected_clients: Array[WebSocketPeer] = [] 

var udp_broadcaster := PacketPeerUDP.new()
var broadcast_timer := 0.0
#endregion

func start() -> void:
	if server_active: return
	
	# Start TCP Listener for WebSockets
	var err = tcp_server.listen(listen_port)
	if err != OK:
		push_error("Server| Could not listen on port ", listen_port)
		return

	# Setup UDP Discovery
	udp_broadcaster.set_broadcast_enabled(true)
	udp_broadcaster.set_dest_address("255.255.255.255", broadcast_port)
	
	print("Server| WebSocket server listening on ", listen_port)
	print("Server| UDP Discovery broadcasting on ", broadcast_port)
	
	server_active = true

func _process(delta: float) -> void:
	if not server_active: return
	
	_handle_udp_broadcast(delta)
	_check_for_new_connections()
	_process_client_messages()

#region Discovery Logic
func _handle_udp_broadcast(delta: float) -> void:
	broadcast_timer += delta
	if broadcast_timer > 2.0:
		broadcast_timer = 0.0
		# This "nataho_server" string must match the Client's search string
		udp_broadcaster.put_packet("nataho_server".to_utf8_buffer())
#endregion

#region Connection & Messaging
func _check_for_new_connections() -> void:
	while tcp_server.is_connection_available():
		var conn = tcp_server.take_connection()
		var ws = WebSocketPeer.new()
		ws.accept_stream(conn)
		
		# Set metadata to track if we've handled the initial handshake
		ws.set_meta("welcomed", false)
		connected_clients.append(ws)
		print("Server| New connection attempt...")

func _process_client_messages() -> void:
	for i in range(connected_clients.size() - 1, -1, -1):
		var ws = connected_clients[i]
		ws.poll()
		
		var state = ws.get_ready_state()
		
		if state == WebSocketPeer.STATE_OPEN:
			# Send handshake welcome message once
			if not ws.get_meta("welcomed"):
				_send_welcome(ws)
				ws.set_meta("welcomed", true)
			
			_read_packets(ws)
			
		elif state == WebSocketPeer.STATE_CLOSED:
			connected_clients.remove_at(i)
			print("Server| Client disconnected and removed.")

func _read_packets(ws: WebSocketPeer) -> void:
	while ws.get_available_packet_count() > 0:
		var packet = ws.get_packet()
		var msg = packet.get_string_from_utf8()
		var parsed_msg = JSON.parse_string(msg)
		
		if typeof(parsed_msg) != TYPE_DICTIONARY or not parsed_msg.has("signal"):
			continue

		_handle_signal(ws, parsed_msg)

func _handle_signal(ws: WebSocketPeer, data: Dictionary) -> void:
	# Generic routing via Events bus
	match data["signal"]:
		"enter_game":
			Events.enter_game.emit()
		"sync_interaction":
			Events.sync_interaction.emit(data)
			# Relay to all other clients if needed
			broadcast_signal("sync_interaction", data)
		"interact":
			Events.server_interaction.emit(data)
		_:
			print("Server| Received unknown signal: ", data["signal"])

func stop_server():
	if not server_active: return
	
	print("Server| Shutting down...")
	
	# 1. Close all active client connections
	for ws in connected_clients:
		ws.close(1000, "Server shutting down")
	
	# 2. Clear the list and stop the listener
	connected_clients.clear()
	tcp_server.stop()
	
	# 3. Stop the UDP broadcast
	server_active = false
	print("Server| Offline.")
#endregion

#region Outbound Communication
func broadcast_signal(signal_name: String, extra_data: Dictionary = {}) -> void:
	var payload = {"signal": signal_name}
	payload.merge(extra_data)
	var json_string = JSON.stringify(payload)
	
	for ws in connected_clients:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(json_string)

func send_to_client(ws: WebSocketPeer, signal_name: String, extra_data: Dictionary = {}) -> void:
	var payload = {"signal": signal_name}
	payload.merge(extra_data)
	ws.send_text(JSON.stringify(payload))

func _send_welcome(ws: WebSocketPeer) -> void:
	send_to_client(ws, "server_connected")
	print("Server| Handshake sent to client.")

func disconnect_client(ws: WebSocketPeer, reason: String = "Kicked by server"):
	if ws in connected_clients:
		ws.close(1000, reason)
		# The _process loop will handle removing them from the array 
		# when it detects the STATE_CLOSED next frame.
		print("Server| Disconnecting client: ", reason)
#endregion
