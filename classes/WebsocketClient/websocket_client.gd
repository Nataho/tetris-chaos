extends Node
#class_name NetworkClient

#region Variables
var client_active = false
var gp_handler := GamepadHandler.new()
var client = WebSocketPeer.new()

var udp_listener := PacketPeerUDP.new()
var listen_port := 4242
var found_server_ip := ""
#endregion

func start():
	if client_active: return
	
	#_set_inputs_to_scene()
	if udp_listener.bind(listen_port) == OK:
		print("Client| Searching for server...")
	
	client_active = true

func _process(_delta):
	gp_handler.handle_controller_input()
	
	# If we have no IP, keep searching
	if found_server_ip == "":
		_search_for_server()
		return 
	
	client.poll() 
	
	# Check if the connection we HAD is now closed
	var state = client.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		_handle_disconnection()
		return
		
	_handle_server_messages()

#region Network Logic
func _search_for_server():
	Events.client_searching.emit()
	
	if udp_listener.get_available_packet_count() == 0:
		return
		
	var packet_msg = udp_listener.get_packet().get_string_from_utf8()
	if packet_msg == "nataho_server":
		found_server_ip = udp_listener.get_packet_ip()
		print("Client| Server found at: ", found_server_ip)
		client.connect_to_url("ws://" + found_server_ip + ":8080")
		Events.client_connected.emit()

func _handle_disconnection():
	print("Client| Connection lost. Searching for server again...")
	get_tree().change_scene_to_file("uid://b64qch8epqiq3")
	
	# Reset these to trigger the search in _process
	found_server_ip = "" 
	
	# Close the existing peer to clean up the old attempt
	client.close() 
	Events.client_disconnected.emit()
	
	# (Optional) Re-bind UDP if it was closed, though usually it stays bound
	# udp_listener.unbind()
	# udp_listener.bind(listen_port)

func _handle_server_messages():
	while client.get_available_packet_count() > 0:
		var packet = client.get_packet()
		var raw_data = packet.get_string_from_utf8()
		
		# 1. Check if the string is empty or invalid
		if raw_data.is_empty():
			continue

		# 2. Attempt to parse JSON
		var parsed_msg = JSON.parse_string(raw_data)
		
		# 3. Safety Check: Is it valid JSON and is it a Dictionary?
		# (Sometimes hackers or bugs send an Array [] or String "" instead of {})
		if typeof(parsed_msg) != TYPE_DICTIONARY:
			print("asdf")
			print("Client| Error: Received invalid message format (not a dictionary).")
			continue

		_process_server_signal(parsed_msg)

func _process_server_signal(data: Dictionary):
	# 4. Safety Check: Does the signal key exist?
	if not data.has("signal"):
		print("Client| Warning: Message missing 'signal' key: ", data)
		return

	# 5. Route the signal safely
	match data["signal"]:
		"server_connected":
			print("Client| Sucessfully connected to server")
		
		"sync_interaction":
			print("Client| Recieved a sync command")
			Events.sync_interaction.emit(data)
		
		"interact":
			print("Client| Recieved an interaction command")
			Events.client_interaction.emit(data)
		
		"error":
			print("Client| Server Error: ", data.get("message", "Unknown error"))
		_:
			print("Client| Unknown signal received: ", data["signal"])
#endregion

#region Communication
#enter the game from title screen
func enter_game():
	if client.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
		
	var payload = {
		"signal": "enter_game"
	}
	client.send_text(JSON.stringify(payload))
	print("Client| Sent 'enter_game'")

func sync_interaction(action: String):
	if client.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	
	var payload = {
		"signal": "sync_interaction",
		"action": action
	}
	
	client.send_text(JSON.stringify(payload))
	print("Client| Sent 'sync_interaction")
#endregion

#region Gameplay Actions

#endregion
