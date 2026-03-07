extends Node

#region Variables
@export var listen_port: int = 4242
@export var server_port: int = 8080

var client := WebSocketPeer.new()
var udp_listener := PacketPeerUDP.new()

var client_active: bool = false
var found_server_ip: String = ""

var is_connecting: bool = false
var connection_timer: float = 0.0
const CONNECTION_TIMEOUT: float = 15.0
#endregion

func start(direct_ip: String = "") -> void:
	# Prevent multiple searches if we are already trying!
	if client_active or is_connecting:
		print("Client| Already searching or active. Ignoring request.")
		return
	
	is_connecting = true
	connection_timer = 0.0
	client_active = true
	found_server_ip = ""
	
	if direct_ip != "":
		print("Client| Force connecting directly to IP: ", direct_ip)
		found_server_ip = direct_ip
		var url = "ws://" + found_server_ip + ":" + str(server_port)
		client.connect_to_url(url)
	else:
		if udp_listener.bind(listen_port) == OK:
			print("Client| Searching for server on LAN (port ", listen_port, ")...")
			Events.client_searching.emit() 
		else:
			push_error("Client| Could not bind UDP listener.")
			stop() # Clean up immediately on error

func stop() -> void:
	# 1. Close the UDP listener if it's bound
	if udp_listener.is_bound():
		udp_listener.close()
		
	# 2. Close the WebSocket if it's running
	if client.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		client.close()
		
	# 3. Reset all states so we can search again later
	client_active = false
	is_connecting = false
	found_server_ip = ""
	connection_timer = 0.0
	print("Client| Stopped and ready for new connection attempts.")
	
func _process(delta: float) -> void:
	if not client_active: return

	# TIMEOUT LOGIC
	if is_connecting:
		connection_timer += delta
		if connection_timer >= CONNECTION_TIMEOUT:
			print("Client| Connection timed out after 15 seconds.")
			stop()
			Events.connection_timeout.emit() # Make sure you add this to Events.gd!
			return

	# Discovery Mode
	if found_server_ip == "":
		_search_for_server()
		return 
	
	# Connection Mode
	client.poll() 
	var state = client.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		# We successfully opened the socket! Stop the timeout timer.
		if is_connecting:
			is_connecting = false 
			
		_handle_server_messages()
		
	elif state == WebSocketPeer.STATE_CLOSED:
		_handle_disconnection()
		
#region Network Logic
func _search_for_server() -> void:
	# Read ALL pending UDP packets in case they stack up
	while udp_listener.get_available_packet_count() > 0:
		var packet_msg = udp_listener.get_packet().get_string_from_utf8()
		
		# Verify the broadcast "password"
		if packet_msg == "nataho_server":
			found_server_ip = udp_listener.get_packet_ip()
			print("Client| Server found at: ", found_server_ip)
			
			var url = "ws://" + found_server_ip + ":" + str(server_port)
			client.connect_to_url(url)
			break # Stop searching, we found it!

func _handle_disconnection() -> void:
	print("Client| Connection lost. Reverting to discovery mode...")
	found_server_ip = "" 
	client.close() 
	Events.client_disconnected.emit()
	Events.client_searching.emit() # Tell the UI we are searching again

func _handle_server_messages() -> void:
	while client.get_available_packet_count() > 0:
		var packet = client.get_packet()
		var raw_data = packet.get_string_from_utf8()
		
		if raw_data.is_empty():
			continue

		var parsed_msg = JSON.parse_string(raw_data)
		
		if typeof(parsed_msg) != TYPE_DICTIONARY:
			push_warning("Client| Error: Received invalid JSON format.")
			continue

		_process_server_signal(parsed_msg)

func _process_server_signal(data: Dictionary) -> void:
	var signal_name = data.get("signal", "")
	if signal_name == "": return

	match signal_name:
		"server_connected":
			print("Client| Handshake complete.")
			Events.client_connected.emit()
		
		"join_accepted":
			print("Client| Server accepted join request.")
			Events.server_accepted_join.emit()

		"join_rejected":
			print("Client| Server rejected join request.")
			Events.server_rejected_join.emit()
		
		"send_board_data":
			Events.received_board_data.emit(data.get("data", {}))
		
		"sync_interaction":
			Events.sync_interaction.emit(data)
			
		"sync_data":
			Events.sync_data.emit(data)
			
		"error":
			print("Client| Server Error: ", data.get("message", "Unknown"))
			
		_:
			print("Client| Unhandled signal: ", signal_name)
#endregion

#region Outbound Communication
func sync_interaction(action: String) -> void:
	var payload = {
		"signal": "sync_interaction",
		"action": action
	}
	_send_json(payload)
	print("Client| Sent 'sync_interaction'")

func sync_data(data: Dictionary) -> void:
	var payload = {
		"signal": "sync_data",
		"data": data
	}
	_send_json(payload)
	print("Client| Sent 'sync_data'")

func send_signal(signal_name: String, extra_data: Dictionary = {}) -> void:
	var payload = {
		"signal": signal_name,
		"data": extra_data
	}
	_send_json(payload)

func _send_json(payload: Dictionary) -> void:
	if client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		client.send_text(JSON.stringify(payload))

func disconnect_from_server() -> void:
	if client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		send_signal("player_leaving")
		client.close(1000, "Client disconnected normally")
	
	found_server_ip = ""
	client_active = false
	print("Client| Disconnected.")
	Events.client_disconnected.emit()
#endregion
