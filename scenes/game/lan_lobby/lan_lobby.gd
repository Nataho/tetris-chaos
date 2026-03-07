extends Control

@onready var host_btn: Button = $Control/host
@onready var join_btn: Button = $VBoxContainer/join

@onready var ip_text_box: LineEdit = $"Control/side bar/IP_bar/ip_text_box"
@onready var ip_connect_button: Button = $"Control/side bar/IP_bar/ip_connect_button"

@onready var username_text_box: LineEdit = $"Control/side bar/name"


@onready var local_board: LocalBoard = $local_anchor/board
@onready var network_board: NetworkBoard = $network_anchor/board

var current_seed: int = -1

var _ip_to_search:String = ""

#TODO: make 2 buttons for searching, for udp or foced connect
#TODO: add active players in the top left
#TODO: add chat capabilities in the bottom right

func _ready() -> void:
	_connect_ui_signals()
	_connect_network_signals()
	username_text_box.text = GameManager.player_data["name"]
# ------------------------------------------------------------------------------
# Signal Setup
# ------------------------------------------------------------------------------
func _connect_ui_signals() -> void:
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	
	ip_text_box.text_changed.connect(_on_ip_box_edited)
	ip_connect_button.pressed.connect(_on_ip_button_pressed)
	
	username_text_box.text_changed.connect(_on_username_changed)
	
	Events.android_back_pressed.connect(back)
	

func _connect_network_signals() -> void:
	# Shared Syncs
	Events.sync_interaction.connect(_on_sync_interaction)
	Events.sync_data.connect(_on_sync_data)
	
	# Client-Specific
	Events.client_connected.connect(_on_client_connected)
	Events.server_accepted_join.connect(_on_server_accepted)
	Events.server_rejected_join.connect(_on_server_rejected)
	
	# Server-Specific
	Events.client_joined_lobby.connect(_on_client_joined)

# ------------------------------------------------------------------------------
# UI Element Handlers
# ------------------------------------------------------------------------------
func _on_host_pressed() -> void:
	print("Hosting...")
	join_btn.disabled = true
	host_btn.release_focus()
	
	# Set up the game
	current_seed = randi()
	NetworkServer.start()
	#local_board.initialize(current_seed) 
	#TEST: commenting this for a bit for testing
	#TODO: after testing uncomment this.
	
	# TODO: Add UI logic here (e.g., show "Waiting for opponent..." text)

func _on_join_pressed() -> void:
	print("Joining...")
	host_btn.disabled = true
	join_btn.release_focus()
	NetworkClient.start()
	
	# TODO: Add UI logic here (e.g., show "Connecting to host..." spinner)

func _on_ip_box_edited(text:String) -> void:
	_ip_to_search = text

func _on_ip_button_pressed() -> void:
	#if _ip_to_search == "": return
	NetworkClient.start(_ip_to_search)

func _on_username_changed(text:String) -> void:
	if text == "": text = "guest"
	GameManager.player_data["name"] = text
	GameManager.SAVE_GAME()

# ------------------------------------------------------------------------------
# Network Event Handlers
# ------------------------------------------------------------------------------
func _on_sync_interaction(payload: Dictionary) -> void:
	if payload.get("action") == "start_game":
		local_board.start(3) # Starts the 3-2-1 countdown

func _on_sync_data(payload: Dictionary) -> void:
	var data = payload.get("data", {})
	var action = data.get("action", "")
	
	if action == "initialize_boards" and NetworkClient.client_active:
		var seed_val = data.get("seed", -1)
		local_board.initialize(seed_val)

func _on_client_connected() -> void:
	print("Client| connected")
	NetworkClient.send_signal("join_lobby", {"data": GameManager.player_data})

func _on_server_accepted() -> void:
	# Client perspective: The opponent (Server) is Player 1
	network_board.set_board(1, 2) 
	network_board.initialize()
	
	# TODO: Hide lobby UI and show "Ready up" UI

func _on_server_rejected() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")

func _on_client_joined(payload: Dictionary) -> void:
	if not NetworkServer.server_active: return
	
	# Tell the client what seed to use
	NetworkSync.sync_data({"action": "initialize_boards", "seed": current_seed})
	
	# Server perspective: The opponent (Client) is Player 2
	network_board.set_board(2, 1) 
	network_board.initialize()
	
	# TODO: Hide lobby UI and show "Ready up" UI

# ------------------------------------------------------------------------------
# Input
# ------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		back()
		
	elif event.is_action_pressed("ready"):
		# Ensure NetworkSync.sync_interaction wraps this string into a dict on the other side!
		NetworkSync.sync_interaction("start_game")

func back():
	NetworkClient.stop()
	NetworkServer.stop_server()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	pass
