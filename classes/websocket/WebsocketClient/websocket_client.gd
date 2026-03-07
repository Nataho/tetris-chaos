extends Node

#region Variables
@export var listen_port: int = 4242
@export var server_port: int = 8080

# The Timer node from the scene tree
@onready var timer: Timer = $Timer

var client := WebSocketPeer.new()
var udp_listener := PacketPeerUDP.new()

var client_active: bool = false
var found_server_ip: String = ""
var is_connecting: bool = false

# We'll use 15 seconds as our search window
const CONNECTION_TIMEOUT: float = 15.0
#endregion

func _ready() -> void:
	# Connect the timer's signal once at the start
	timer.timeout.connect(_on_timeout)
	timer.one_shot = true # Ensure it only fires once per search

func start(direct_ip: String = "") -> void:
	if client_active or is_connecting:
		print("Client| Already searching or active. Ignoring request.")
		return
	
	client_active = true
	found_server_ip = ""
	
	# Start the timeout timer immediately
	timer.start(CONNECTION_TIMEOUT)
	
	if direct_ip != "":
		print("Client| Force connecting directly to IP: ", direct_ip)
		is_connecting = true
		found_server_ip = direct_ip
		var url = "ws://" + found_server_ip + ":" + str(server_port)
		client.connect_to_url(url)
	else:
		if udp_listener.bind(listen_port) == OK:
			print("Client| Searching for server on LAN (port ", listen_port, ")...")
			Events.client_searching.emit() 
		else:
			push_error("Client| Could not bind UDP listener.")
			stop()

func stop() -> void:
	timer.stop() # Stop the timer so it doesn't fire after we've quit
	
	if udp_listener.is_bound():
		udp_listener.close()
		
	if client.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		client.close()
		
	client_active = false
	is_connecting = false
	found_server_ip = ""
	print("Client| Stopped and ready for new connection attempts.")
	
func _on_timeout() -> void:
	if client_active and (found_server_ip == "" or is_connecting):
		print("Client| Connection/Discovery timed out.")
		stop()
		Events.connection_timeout.emit() # Remember to add this to Events.gd!
	
func _process(delta: float) -> void:
	if not client_active: return

	# TIMEOUT LOGIC
	if is_connecting:
			is_connecting = false 
			timer.stop() # WE FOUND IT! Stop the timer immediately.

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
			print("Client| Server accepted join.")
			# Pass the data dictionary that the server sent us!
			Events.server_accepted_join.emit(data["data"])

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
