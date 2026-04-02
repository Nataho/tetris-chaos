extends Node
class_name TCPBridge
const _FILE = preload("uid://6eoa2o8g6e0a")
static var active_bridge:TCPBridge = null

signal server_response(payload)

var tcp := StreamPeerTCP.new()
var is_connected_to_server := false

# Change this to your Tailscale IP (100.x.x.x) when testing with friends!
var server_ip := "100.120.66.37"
var server_port := 10100

static func create() -> TCPBridge:
	var inst = _FILE.instantiate()
	active_bridge = inst
	return inst

func _exit_tree() -> void:
	if tcp:
		tcp.disconnect_from_host()
		print("tcp bridge socket closed")

func start() -> void:
	print("Attempting to connect to server at %s:%d..." % [server_ip, server_port])
	tcp.connect_to_host(server_ip, server_port)

func _process(_delta: float) -> void:
	# Keep the connection alive and listen for incoming messages
	tcp.poll() 
	var status := tcp.get_status()
	
	# 1. Did we just successfully connect?
	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not is_connected_to_server:
			is_connected_to_server = true
			print("Successfully connected to tetris-chaos-server!")
			
		# 2. Are we waiting for a message back?
		var available_bytes := tcp.get_available_bytes()
		if available_bytes > 0:
			var raw_data := tcp.get_data(available_bytes)
			
			if raw_data[0] == OK:
				var string_data = raw_data[1].get_string_from_utf8()
				print("Server Responded: ", string_data)
				
				var response_dict = JSON.parse_string(string_data)
				if response_dict is Dictionary:
					server_response.emit(response_dict)
				else:
					print("[ERROR] Failed to parse server response into a Dictionary. Received: ", string_data)

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
		"password": password
	}
	
	print("Sent sign-up request for: ", username)
	active_bridge.send_to_server(data)

static func send_login_request(username: String, password: String) -> void:
	if not active_bridge.is_connected_to_server:
		print("Error: Cannot log in, not connected to server!")
		return
		
	var data := {
		"type": "login",
		"username": username,
		"password": password
	}
	
	print("Sent login request for: ", username)
	active_bridge.send_to_server(data)

# ==========================================
# NETWORK UTILS
# ==========================================

func send_to_server(payload: Dictionary) -> void:
	var json_string := JSON.stringify(payload) # Convert to json
	tcp.put_data(json_string.to_utf8_buffer()) # Convert to bytes then send to server
