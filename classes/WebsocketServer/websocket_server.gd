extends Node

#region Variables
var server_active := false
var tcp_server = TCPServer.new()
var connected_clients = [] 

var udp_broadcaster := PacketPeerUDP.new()
var broadcast_port := 4242
var broadcast_timer := 0.0
#endregion

func start():
	if server_active: return
	
	tcp_server.listen(8080)
	udp_broadcaster.set_broadcast_enabled(true)
	udp_broadcaster.set_dest_address("255.255.255.255", broadcast_port)
	print("Server| Listening on 8080...")
	
	server_active = true
	NetworkSync.is_client = false
func _process(_delta):
	if not server_active: return
	
	_handle_udp_broadcast(_delta)
	_check_for_new_connections()
	_process_client_messages()

#region Discovery Logic
func _handle_udp_broadcast(delta):
	broadcast_timer += delta
	if broadcast_timer > 2.0:
		broadcast_timer = 0.0
		udp_broadcaster.put_packet("nataho_server".to_utf8_buffer())
#endregion

#region Connection & Messaging
func _check_for_new_connections():
	while tcp_server.is_connection_available():
		var conn = tcp_server.take_connection()
		var ws = WebSocketPeer.new()
		ws.accept_stream(conn)
		connected_clients.append(ws)
		
		print("Server| New client connected!")
		if has_node("connected"):
			$connected.play()

func _process_client_messages():
	# Loop backwards to safely remove disconnected clients
	for i in range(connected_clients.size() - 1, -1, -1):
		var ws = connected_clients[i]
		ws.poll()
		
		var state = ws.get_ready_state()
		
		if state == WebSocketPeer.STATE_CLOSED:
			connected_clients.remove_at(i)
			print("Server| Client removed from list.")
			continue
			
		if state == WebSocketPeer.STATE_OPEN:
			if not ws.get_meta("welcomed", false):
				_send_welcome(ws)
				ws.set_meta("welcomed", true)
			
			_read_packets(ws)

func _read_packets(ws: WebSocketPeer):
	while ws.get_available_packet_count() > 0:
		var msg = ws.get_packet().get_string_from_utf8()
		var parsed_msg = JSON.parse_string(msg)
		
		if parsed_msg == null or not parsed_msg.has("signal"):
			continue

		_handle_signal(ws, parsed_msg)

func _handle_signal(ws: WebSocketPeer, data: Dictionary):
	match data["signal"]:
			
		"enter_game":
			Events.enter_game.emit()
			print("Server| Enter Game")
			# Example: Tell everyone someone entered
			#broadcast_signal("player_entered")
			
		"sync_interaction":
			Events.sync_interaction.emit(data)
			print("Server| Sync Interaction")
			# Broadcast the interaction data so all players see it
			broadcast_signal("sync_interaction", data)
		
		"interact":
			Events.server_interaction.emit(data)
			print("Server| Server Interaction")
			
#endregion

#region Helper Functions (The Integration)

# Use this to send a signal to EVERYONE
func broadcast_signal(signal_name: String, extra_data: Dictionary = {}):
	var payload = {"signal": signal_name}
	payload.merge(extra_data)
	var json_string = JSON.stringify(payload)
	
	for ws in connected_clients:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(json_string)

# Use this to send a signal back to ONE specific client
func _send_to_client(ws: WebSocketPeer, signal_name: String, extra_data: Dictionary = {}):
	var payload = {"signal": signal_name}
	payload.merge(extra_data)
	ws.send_text(JSON.stringify(payload))

func _send_welcome(ws: WebSocketPeer):
	_send_to_client(ws, "server_connected")
	print("Server| Welcome sent to client!")

#endregion

#region server functions
func sync_interaction(action: String):
	var payload = {
		"signal": "sync_interaction",
		"action": action
	}
	broadcast_signal(payload["signal"],payload)
	
	Events.sync_interaction.emit(payload)
	print("Serveer| Sync Interaction")
#endregion
