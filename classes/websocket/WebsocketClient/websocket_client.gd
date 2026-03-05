extends Node

#region Variables
@export var listen_port: int = 4242
@export var server_port: int = 8080

var client := WebSocketPeer.new()
var udp_listener := PacketPeerUDP.new()

var client_active: bool = false
var found_server_ip: String = ""
#endregion

func start() -> void:
	if client_active: return
	
	if udp_listener.bind(listen_port) == OK:
		print("Client| Searching for server on port ", listen_port, "...")
	
	client_active = true

func _process(_delta: float) -> void:
	if not client_active: return

	# Discovery Mode: If we have no IP, keep listening for UDP broadcast
	if found_server_ip == "":
		_search_for_server()
		return 
	
	client.poll() 
	
	var state = client.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		_handle_server_messages()
	elif state == WebSocketPeer.STATE_CLOSED:
		_handle_disconnection()

#region Network Logic
func _search_for_server() -> void:
	Events.client_searching.emit()
	
	if udp_listener.get_available_packet_count() == 0:
		return
		
	var packet_msg = udp_listener.get_packet().get_string_from_utf8()
	
	# Verify the broadcast "password"
	if packet_msg == "nataho_server":
		found_server_ip = udp_listener.get_packet_ip()
		print("Client| Server found at: ", found_server_ip)
		
		var url = "ws://" + found_server_ip + ":" + str(server_port)
		client.connect_to_url(url)
		Events.client_connected.emit()

func _handle_disconnection() -> void:
	print("Client| Connection lost. Reverting to discovery mode...")
	
	found_server_ip = "" 
	client.close() 
	Events.client_disconnected.emit()

func _handle_server_messages() -> void:
	while client.get_available_packet_count() > 0:
		var packet = client.get_packet()
		var raw_data = packet.get_string_from_utf8()
		
		if raw_data.is_empty():
			continue

		var parsed_msg = JSON.parse_string(raw_data)
		
		if typeof(parsed_msg) != TYPE_DICTIONARY:
			print("Client| Error: Received invalid JSON format.")
			continue

		_process_server_signal(parsed_msg)

func _process_server_signal(data: Dictionary) -> void:
	if not data.has("signal"):
		return

	match data["signal"]:
		"server_connected":
			print("Client| Handshake complete.")
		"sync_interaction":
			Events.sync_interaction.emit(data)
		"interact":
			Events.client_interaction.emit(data)
		"error":
			print("Client| Server Error: ", data.get("message", "Unknown"))
		_:
			print("Client| Unhandled signal: ", data["signal"])
#endregion

#region Outbound Communication
func send_signal(signal_name: String, extra_data: Dictionary = {}) -> void:
	if client.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
		
	var payload = {"signal": signal_name}
	payload.merge(extra_data)
	
	client.send_text(JSON.stringify(payload))
	
func disconnect_from_server():
	if client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		# 1. (Optional) Send a final "goodbye" signal so the server knows it was intentional
		send_signal("player_leaving")
		
		# 2. Close the connection gracefully
		client.close(1000, "Client disconnected normally")
	
	# 3. Clean up variables
	found_server_ip = ""
	client_active = false
	print("Client| Disconnected.")
	Events.client_disconnected.emit()
#endregion
