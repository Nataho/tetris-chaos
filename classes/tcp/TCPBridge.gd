extends Node
class_name TCPBridge
const _FILE = preload("uid://6eoa2o8g6e0a")
static var active_bridge:TCPBridge = null

signal server_response(payload)
signal connection_status_changed(connected: bool)

var tcp := StreamPeerTCP.new()
var is_connected_to_server := false
var is_connecting := false

# Change this to your Tailscale IP (100.x.x.x) when testing with friends!
#var server_ip := "100.120.66.37"
var server_ip := "10.147.17.203"
var server_port := 10100

var _last_ping_time: int = 0 
var _reconnect_timer: float = 0.0

# --- NEW VARIABLES FOR RECONNECT LIMIT ---
var _reconnect_attempts: int = 0
const MAX_RECONNECT_ATTEMPTS: int = 12

@onready var ping_timer: Timer = $ping

## lobby variables
var _room_id := "000000"
var _is_host := false
##
static func create() -> TCPBridge:
	var inst = _FILE.instantiate()
	active_bridge = inst
	return inst

func _enter_tree() -> void:
	active_bridge = self

func _exit_tree() -> void:
	if tcp:
		tcp.disconnect_from_host()
		print("tcp bridge socket closed")
		ping_timer.stop()

func start() -> void:
	print("Attempting to connect to server at %s:%d... (Attempt %d/%d)" % [server_ip, server_port, _reconnect_attempts + 1, MAX_RECONNECT_ATTEMPTS])
	tcp.connect_to_host(server_ip, server_port)
	is_connecting = true

static func restart() -> void:
	if active_bridge:
		active_bridge._restart()

func _restart() -> void:
	print("Restarting TCPBridge connection...")
	tcp.disconnect_from_host()
	
	if is_connected_to_server:
		is_connected_to_server = false
		connection_status_changed.emit(false) 
		
	ping_timer.stop()
	
	# Reset the attempt counter on a manual restart
	_reconnect_attempts = 0
	_reconnect_timer = 0.0 
	start()

func _process(delta: float) -> void:
	# Keep the connection alive and listen for incoming messages
	tcp.poll() 
	var status := tcp.get_status()
	
	# 1. Are we connected?
	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not is_connected_to_server:
			is_connected_to_server = true
			is_connecting = false
			_reconnect_attempts = 0 # <-- Reset attempt counter on success!
			print("Successfully connected to tetris-chaos-server!")
			connection_status_changed.emit(true)
			ping_timer.start()
			
		# Are we waiting for a message back?
		var available_bytes := tcp.get_available_bytes()
		if available_bytes > 0:
			var raw_data := tcp.get_data(available_bytes)
			if raw_data[0] == OK:
				var string_data = raw_data[1].get_string_from_utf8()
				
				# --- THE FIX: SPLIT BY NEWLINE ---
				var messages = string_data.split("\n", false) 
				
				for msg in messages:
					var response_dict = JSON.parse_string(msg)
					if response_dict is Dictionary:
						if response_dict.get("type") != "pong":
							print("Server Responded: ", msg)
							
						# --- INTERCEPT ROOM ACTIONS ---
						if response_dict.get("type") == "room_action":
							var sig = response_dict.get("signal")
							var data = response_dict.get("data", {})
							
							match sig:
								"send_board_data":
									Events.received_board_data.emit(data)
								"sync_interaction":
									Events.sync_interaction.emit(response_dict)
								"sync_data":
									Events.sync_data.emit(response_dict)
								
								# --- NEW SIGNALS FROM PYTHON ---
								"join_accepted":
									Events.server_accepted_join.emit(data)
								"join_rejected":
									Events.server_rejected_join.emit(data)
								"join_lobby":
									Events.client_joined_lobby.emit(data)
								"left_lobby":
									Events.client_left_lobby.emit(data)
								#"join_lobby":
									#print("WOHOOO, JOINED THE LOBBY")
						# -----------------------------------
						else:
							# Normal server responses
							server_response.emit(response_dict)
					
						if response_dict.get("type") == "pong":
							var lag = Time.get_ticks_msec() - _last_ping_time
							Details.show_ping(lag)

	# 2. Did we disconnect OR fail to connect?
	elif status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		# Check if we were connected OR if we were currently trying to connect
		if is_connected_to_server or is_connecting: 
			if is_connected_to_server:
				print("Disconnected from server! Connection lost.")
			else:
				print("Connection attempt failed.")
				
			is_connected_to_server = false
			is_connecting = false 
			ping_timer.stop()
			tcp.disconnect_from_host() 
			
			_reconnect_attempts += 1 # Increment failure count
			
			if _reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
				print("Failed to connect after %d attempts. Giving up." % MAX_RECONNECT_ATTEMPTS)
				connection_status_changed.emit(false) # <-- EMIT FALSE ONLY WHEN GIVING UP
			else:
				print("Retrying in 5 seconds...")
		
		# 3. Auto-Reconnect Logic (Only run if we haven't hit the limit)
		if _reconnect_attempts < MAX_RECONNECT_ATTEMPTS:
			_reconnect_timer -= delta
			if _reconnect_timer <= 0.0:
				_reconnect_timer = 5.0 # Reset the countdown
				start()

# ==========================================
# CLIENT REQUESTS TO SERVER
# ==========================================

static func send_signup_request(username: String, password: String) -> void:
	if not active_bridge.is_connected_to_server:
		print("Error: Cannot sign up, not connected to server!")
		return
	
	var data := {
		"type": "signup",
		"username": username,
		"password": password,
	}
	
	print("Sent sign-up request for: ", username)
	send_to_server(data)

static func send_login_request(username: String, password: String) -> void:
	if not active_bridge.is_connected_to_server:
		print("Error: Cannot log in, not connected to server!")
		return
	
	var data := {
		"type": "login",
		"username": username,
		"password": password,
	}
	
	print("Sent login request for: ", username)
	send_to_server(data)

static func get_player_info(username:String) -> void:
	if not active_bridge.is_connected_to_server:
		return
	var data ={
		"type": "get_player_info",
		"username": username
	}
	send_to_server(data)

static func update_high_score(uid:int, highscore:int):
	if not active_bridge.is_connected_to_server:
		print("failed to connect to server")
		return
	var data ={
		"type": "update_highscore",
		"uid": uid,
		"highscore": highscore
	}
	send_to_server(data)

static func create_room():
	if not active_bridge.is_connected_to_server:
		print("failed to connect to server")
		return
	var data ={
		"type": "create_room"
	}
	active_bridge._is_host = true
	send_to_server(data)

# Inside TCPBridge.gd (Wherever you put your custom join code)
static func join_room(roomID: String):
	if not active_bridge.is_connected_to_server: return

	var data = {
		"type": "join_room", 
		"room_id": roomID
	}

	# --- YOU MUST ADD THIS LINE! ---
	active_bridge._is_host = false
	# -------------------------------

	active_bridge._room_id = roomID
	send_to_server(data)

static func refresh_login(uid:int):
	if not active_bridge.is_connected_to_server:
		print("failed to connect to server")
		return
	var data = {
		"type" : "refresh_login",
		"uid": uid
	}
	send_to_server(data)

static func check_room_exsistence(roomID: String): # Use String!
	if not active_bridge.is_connected_to_server:
		print("failed to connect to server")
		return
	var data = {
		"type" : "check_room_existence", # Spelled correctly!
		"room_id": roomID # Use "room_id" instead of "uid"!
	}
	send_to_server(data)

# ==========================================
# NETWORK UTILS
# ==========================================

static func ping():
	active_bridge._ping()

func _ping():
	var payload = {
		"type": "ping"
	}
	_last_ping_time = Time.get_ticks_msec()
	send_to_server(payload)

static func send_to_server(payload:Dictionary):
	active_bridge._send_to_server(payload)

func _send_to_server(payload: Dictionary) -> void:
	# Add the newline character here!
	var json_string := JSON.stringify(payload) + "\n" 
	tcp.put_data(json_string.to_utf8_buffer())

# ==========================================
# LOBBY FUNCTIONS
# ==========================================
static func set_room_id(roomId: String): # Use String!
	active_bridge._room_id = roomId

static func get_lobby_id():
	return active_bridge._room_id

static func get_host_info():
	return active_bridge._is_host

static func send_player_ready() -> void:
	if not active_bridge.is_connected_to_server: return
	var data = {
		"type": "room_action",
		"signal": "player_ready",
		"data": {
			"room_id": active_bridge._room_id
		}
	}
	send_to_server(data)
