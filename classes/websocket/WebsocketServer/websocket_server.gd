extends Node

var active_players = []

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
	NetworkSync.is_client = false
	
	active_players.clear()
	active_players.append(GameManager.player_data)
	
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
			# Scrub them from active_players AND tell the UI they left
			for p in range(active_players.size() - 1, -1, -1):
				if active_players[p].get("socket") == ws:
					var leaving_player = active_players[p]
					active_players.remove_at(p)
					
					# Tell the Host's UI to remove them!
					Events.client_left_lobby.emit(leaving_player)
					
			connected_clients.remove_at(i)
			print("Server| Client disconnected and removed.")

func _read_packets(ws: WebSocketPeer) -> void:
	while ws.get_available_packet_count() > 0:
		var packet = ws.get_packet()
		var msg = packet.get_string_from_utf8()
		var parsed_msg = JSON.parse_string(msg)
		
		if typeof(parsed_msg) != TYPE_DICTIONARY or not parsed_msg.has("signal"):
			continue

		#print("hiiii")
		_handle_signal(ws, parsed_msg)

func _handle_signal(ws: WebSocketPeer, data: Dictionary) -> void:
	# Generic routing via Events bus
	match data["signal"]:
		"join_lobby":
			# The client sent their database profile (GameManager.player_data)
			var profile_data = data["data"] 
			var joining_name = str(profile_data.get("name", "Unknown"))
			
			# 1. Check for duplicate names FIRST
			var is_name_taken = false
			for p in active_players:
				if str(p.get("name", "")) == joining_name:
					is_name_taken = true
					break
			
			if is_name_taken:
				print("Server| Rejecting join: Name '", joining_name, "' is already taken.")
				send_to_client(ws, "join_rejected", {"reason": "Name already taken"})
				return # Stop right here, don't let them in!
			
			# 2. Check if the lobby is full
			if active_players.size() >= 10: 
				print("Server| Rejecting join: Lobby is full.")
				send_to_client(ws, "join_rejected", {"reason": "Lobby is full"})
				return # Stop right here!
			
			# 3. If they passed the checks, create their session and let them in
			var session_player = {
				"socket": ws,
				"name": joining_name,
				"player_id": active_players.size() + 1,      # Session ID
				"wants_to_play": true                        # Default to wanting to play
			}
			
			active_players.append(session_player)
			Events.client_joined_lobby.emit(session_player)
			send_to_client(ws, "join_accepted", {"player_id": session_player["player_id"]})
		"enter_game":
			Events.enter_game.emit()
		
		"send_board_data":
			# Process it locally on the Host's machine
			Events.received_board_data.emit(data["data"])
			
			# Relay it to all other connected clients (spectators, etc.)
			broadcast_signal("send_board_data", data)
		
		"sync_data":
			Events.sync_data.emit(data)
			broadcast_signal("sync_data", data)
		
		"sync_interaction":
			Events.sync_interaction.emit(data)
			# Relay to all other clients if needed
			broadcast_signal("sync_interaction", data)
		#"send_board_data":
			#Events.received_board_data.emit(data["data"])
		#"interact":
			#Events.server_interaction.emit(data)
		"testing":
			print(data["data"])
			#for tile in data["data"]:
				#print(tile.coordinates)
			#print(.coordinates)
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

func sync_interaction(action: String):
	var payload = {
		"signal": "sync_interaction",
		"action": action
	}
	broadcast_signal(payload["signal"],payload)
	
	Events.sync_interaction.emit(payload)
	print("Server| Sync Interaction")

func sync_data(data:Dictionary):
	var payload = {
		"signal": "sync_data",
		"data": data
	}
	
	broadcast_signal(payload["signal"], payload)
	
	Events.sync_data.emit(payload)
	print("Server| Sent 'sync_data'")

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
	payload["data"] = extra_data
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
