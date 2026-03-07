extends Control

@onready var host_btn: Button = $"Control/side bar/host"
@onready var join_btn: Button = $"Control/side bar/IP_bar/join"

@onready var ip_text_box: LineEdit = $"Control/side bar/IP_bar/ip_text_box"
@onready var plyr_tgl_btn: Button = $"Control/side bar/player_toggle"

@onready var username_text_box: LineEdit = $"Control/side bar/name"

@onready var local_board: LocalBoard = $local_anchor/board
@onready var network_board: NetworkBoard = $network_anchor/board

@onready var ui_player_node: RichTextLabel = $Control/Players/Player

@onready var anim: AnimationPlayer = $versus/AnimationPlayer
@onready var master_timer: Timer = $MasterTimer

@onready var player_1_anchor: Control = $versus/player1_anchor
@onready var player_2_anchor: Control = $versus/player2_anchor


var is_countdown_active: bool = false
var last_synced_sec: int = -1

var player_node_snapshot = null
var current_seed: int = -1
var _ip_to_search:String = ""
var active_players

# SESSION DATA (Resets every time you enter the lobby)
var my_lobby_id: int = -1
var is_spectator: bool = false
var countdown:int = 15
var locked_in_time:int = 5

# --- Constants ---
const SLIDE_SPEED: float = 10.0
const DISTANCE: float = 0.25

# --- Animation States ---
var local_active: bool = false
var network_active: bool = false

func _ready() -> void:
	GameManager.change_resolution(1280, 720)
	Audio.play_music("lobby",Audio.SOUND_END_EFFECTS.FADE)
	
	_setup_ui()
	_connect_ui_signals()
	_connect_network_signals()
	
	# Add this line!
	master_timer.timeout.connect(_on_master_timer_timeout)
	
	active_players = [GameManager.player_data]
	_update_player_list(active_players)

func _process(delta: float) -> void:
	handle_ui_animations(delta)
	
	if not is_countdown_active: return
	
	if NetworkServer.server_active:
		var time_left = ceil(master_timer.time_left)
		var display_text = "STARTING IN: " + str(time_left)
		$"Control/side bar/guide".text = display_text
		
		# Only sync to clients when the second actually changes
		if int(time_left) != last_synced_sec:
			last_synced_sec = int(time_left)
			NetworkSync.sync_data({"action": "timer_tick", "time": last_synced_sec})

func _setup_ui():
	player_node_snapshot = ui_player_node.duplicate()
	ui_player_node.queue_free()
	
	var my_name: String = GameManager.player_data["name"]
	username_text_box.text = my_name
	
	$versus.hide()
	$Control.show()

# ------------------------------------------------------------------------------
# Signal Setup
# ------------------------------------------------------------------------------
func _connect_ui_signals() -> void:
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	ip_text_box.text_changed.connect(_on_ip_box_edited)
	plyr_tgl_btn.pressed.connect(_on_player_toggled)
	username_text_box.text_changed.connect(_on_username_changed)
	Events.android_back_pressed.connect(back)

func _connect_network_signals() -> void:
	Events.sync_interaction.connect(_on_sync_interaction)
	Events.sync_data.connect(_on_sync_data)
	Events.client_connected.connect(_on_client_connected)
	Events.server_accepted_join.connect(_on_server_accepted)
	Events.server_rejected_join.connect(_on_server_rejected)
	Events.client_disconnected.connect(_on_disconnected_from_host)
	Events.client_joined_lobby.connect(_on_client_joined)
	Events.client_left_lobby.connect(_on_client_left)
	Events.connection_timeout.connect(_on_connection_timeout)

# ------------------------------------------------------------------------------
# UI Element Handlers
# ------------------------------------------------------------------------------
func _on_host_pressed() -> void:
	print("Hosting...")
	host_btn.release_focus()
	host_btn.disabled = true
	join_btn.disabled = true
	plyr_tgl_btn.disabled = false
	ip_text_box.editable = false
	username_text_box.editable = false
	host_btn.text = "SERVER HOSTED"
	
	current_seed = randi()
	NetworkServer.start()
	
	var host_session = {
		"name": GameManager.player_data["name"],
		"player_id": my_lobby_id,
		"is_spectator": is_spectator,
		"is_host": true,
		"is_ready": false
	}
	active_players = [host_session]
	_update_player_list(active_players)

func _on_join_pressed() -> void:
	host_btn.disabled = true
	join_btn.disabled = true
	ip_text_box.editable = false
	username_text_box.editable = false
	
	# Give the user immediate feedback
	$"Control/side bar/guide".text = "Searching for host..."
	
	NetworkClient.start(_ip_to_search)

func _on_ip_box_edited(text:String) -> void:
	_ip_to_search = text

func _on_username_changed(text:String) -> void:
	if text == "": text = "guest"
	GameManager.player_data["name"] = text
	GameManager.SAVE_GAME()
	
	if active_players.size() > 0:
		active_players[0]["name"] = text
		
	_update_player_list(active_players)

func _on_player_toggled():
	is_spectator = !is_spectator
	plyr_tgl_btn.text = "SPECTATOR" if is_spectator else "PLAYER"
	
	var my_name = GameManager.player_data["name"]
	
	for p in active_players:
		if p.get("name", "") == my_name:
			p["is_spectator"] = is_spectator
			break
			
	_update_player_list(active_players)
		
	var sync_payload = {
		"action": "role_changed",
		"name": my_name,
		"is_spectator": is_spectator
	}
	
	if NetworkServer.server_active:
		NetworkSync.sync_data(sync_payload)
	elif NetworkClient.client_active:
		NetworkClient.send_signal("sync_data", sync_payload)
	
	if NetworkServer.server_active:
		_check_start_requirements()
		
# ------------------------------------------------------------------------------
# Network Event Handlers
# ------------------------------------------------------------------------------
func _on_sync_interaction(payload: Dictionary) -> void:
	if payload.get("action") == "start_game":
		start_battle()

func _on_sync_data(payload: Dictionary) -> void:
	var data = payload.get("data", payload)
	var action = data.get("action", "")
	
	if action == "initialize_boards" and NetworkClient.client_active:
		local_board.initialize(data.get("seed", -1))
		
	elif action == "player_joined":
		active_players = data.get("players", [])
		_update_player_list(active_players)
		
	elif action == "role_changed":
		var target_name = data.get("name", "")
		var new_spectator_state = data.get("is_spectator", false)
		
		for p in active_players:
			if p.get("name", "") == target_name:
				p["is_spectator"] = new_spectator_state
				break
				
		_update_player_list(active_players)
		
		if NetworkServer.server_active:
			var broadcast_payload = {
				"action": "player_joined", 
				"players": active_players
			}
			NetworkSync.sync_data(broadcast_payload)
			_check_start_requirements()

	
	elif action == "players_selected":
		var p1_name = data.get("p1_name", "Player 1")
		var p2_name = data.get("p2_name", "Player 2")
		var match_seed = data.get("seed", -1)
		
		# Print for the Client
		print("Lobby| MATCHUP: ", p1_name, " VS ", p2_name)
		$"Control/side bar/guide".text = p1_name + " VS " + p2_name
		
		initiate_start_sequence(p1_name, p2_name, match_seed)
	
	
	elif action == "timer_sync":
		is_countdown_active = data.get("active", false)
		if not is_countdown_active:
			$"Control/side bar/guide".text = "Waiting for players..."
			plyr_tgl_btn.disabled = false
	
	elif action == "timer_tick": # Changed from "tick" to match _process
		var time = data.get("time")
		if time < locked_in_time:
			plyr_tgl_btn.disabled = true
		$"Control/side bar/guide".text = "STARTING IN: " + str(time)
			
func _on_client_connected() -> void:
	print("Client| connected")
	var join_data = GameManager.player_data.duplicate()
	join_data["is_spectator"] = is_spectator 
	NetworkClient.send_signal("join_lobby", join_data)

func _on_server_accepted(extra_data: Dictionary) -> void:
	my_lobby_id = extra_data.get("player_id", -1)
	$"Control/side bar/guide".text = "Connected. ID: " + str(my_lobby_id)
	plyr_tgl_btn.disabled = false

func _on_server_rejected() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")

func _on_client_joined(payload: Dictionary) -> void:
	if not NetworkServer.server_active: return
	active_players.append(payload)
	_update_player_list(active_players)
	
	var sync_payload = {
		"action": "player_joined", 
		"players": active_players
	}
	NetworkSync.sync_data(sync_payload)
	_check_start_requirements() # Add this!

func _update_player_list(players_array: Array) -> void:
	for child in $Control/Players.get_children():
		child.queue_free()

	for player in players_array:
		var p_name = str(player.get("name", "Unknown"))
		var is_spec = player.get("is_spectator", false)
		var p_is_host = player.get("is_host", false)
		
		var color = "white"
		if is_spec:
			color = "gray"
		elif p_is_host:
			color = "gold"
			
		# Visual display only: forcing uppercase here
		var bbcode_text = "[color=" + color + "]" + p_name.to_upper() + "[/color]"
		
		var new_player_node = player_node_snapshot.duplicate()
		new_player_node.text = bbcode_text
		$Control/Players.add_child(new_player_node)

func _on_client_left(leaving_player: Dictionary) -> void:
	var p_name = str(leaving_player.get("name", "Unknown"))
	for i in range(active_players.size() - 1, -1, -1):
		if str(active_players[i].get("name", "")) == p_name:
			active_players.remove_at(i)
			break
			
	_update_player_list(active_players)
	$"Control/side bar/guide".text = "Waiting for opponent..."
	
	if NetworkServer.server_active:
		var sync_payload = {
			"action": "player_joined", 
			"players": active_players
		}
		NetworkSync.sync_data(sync_payload)
		_check_start_requirements()

func _on_disconnected_from_host() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")

func _on_connection_timeout() -> void:
	print("Lobby| Connection timed out.")
	
	# Re-enable the UI so the player can try again
	host_btn.disabled = false
	join_btn.disabled = false
	ip_text_box.editable = true
	username_text_box.editable = true
	
	# Update the guide text to notify the user
	$"Control/side bar/guide".text = "Connection timed out. Server not found."


func _check_start_requirements() -> void:
	if not NetworkServer.server_active: return
	
	var ready_count = 0
	for p in active_players:
		# Counting everyone who is NOT a spectator
		if not p.get("is_spectator", false):
			ready_count += 1
			
	if ready_count >= 2:
		if not is_countdown_active:
			is_countdown_active = true
			master_timer.start(countdown) # <--- Changed here
			NetworkSync.sync_data({"action": "timer_sync", "active": true})
	else:
		if is_countdown_active:
			is_countdown_active = false
			master_timer.stop()
			NetworkSync.sync_data({"action": "timer_sync", "active": false})
			# Reset guide text manually here
			$"Control/side bar/guide".text = "Waiting for players..."

func _on_master_timer_timeout() -> void:
	if not NetworkServer.server_active: return
	
	is_countdown_active = false
	
	var eligible_players = []
	for p in active_players:
		if not p.get("is_spectator", false):
			eligible_players.append(p)
			
	if eligible_players.size() >= 2:
		eligible_players.shuffle()
		
		var p1 = eligible_players[0]
		var p2 = eligible_players[1]
		
		var p1_name = p1.get("name", "Unknown")
		var p2_name = p2.get("name", "Unknown")
		
		# Generate the match seed now that we have players
		current_seed = randi()
		
		# Print for the Host
		print("Lobby| MATCHUP: ", p1_name, " VS ", p2_name)
		$"Control/side bar/guide".text = p1_name + " VS " + p2_name
		
		# Broadcast to Clients
		NetworkSync.sync_data({
			"action": "players_selected",
			"p1_name": p1_name,
			"p2_name": p2_name,
			"seed": current_seed
		})
		
		# Host triggers their own start sequence!
		initiate_start_sequence(p1_name, p2_name, current_seed)
	else:
		$"Control/side bar/guide".text = "Not enough players!"
		_check_start_requirements()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		back()
	elif event.is_action_pressed("ready"):
		if NetworkServer.server_active:
			# Host can force start instantly if they want
			_on_master_timer_timeout()
		else:
			print("Client| Only the host can force start.")

func back():
	NetworkClient.stop()
	NetworkServer.stop_server()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


# -------------------------
# battle logic
# -------------------------

func handle_ui_animations(delta: float) -> void:
	var screen_size := get_viewport_rect().size
	var lerp_weight = 1.0 - exp(-SLIDE_SPEED * delta)
	var screen_center = screen_size * 0.5
	
	var local_pos = screen_center
	var network_pos = screen_center
	var local_mod = Color.TRANSPARENT
	var network_mod = Color.TRANSPARENT
	
	if local_active:
		local_pos = Vector2(screen_size.x * (0.5 - DISTANCE), screen_center.y)
		local_mod = Color.WHITE
	if network_active:
		network_pos = Vector2(screen_size.x * (0.5 + DISTANCE), screen_center.y)
		network_mod = Color.WHITE
	
	player_1_anchor.position = player_1_anchor.position.lerp(local_pos, lerp_weight)
	player_2_anchor.position = player_2_anchor.position.lerp(network_pos, lerp_weight)
	player_1_anchor.modulate = player_1_anchor.modulate.lerp(local_mod, lerp_weight)
	player_2_anchor.modulate = player_2_anchor.modulate.lerp(network_mod, lerp_weight)

func initiate_start_sequence(p1_name: String, p2_name: String, seed: int):
	$versus.modulate = Color.TRANSPARENT
	$Control.hide()
	$versus.show()
	anim.play("intro")
	
	# Trigger the slide animation
	local_active = true
	network_active = true
	
	Audio.trigger_fade_out(2)
	await Audio.play_sound("match_intro", 0.56)
	
	initialize_boards(seed)
	
	# If Host, tell everyone the animation is over and to start the countdown
	if NetworkServer.server_active:
		NetworkSync.sync_interaction("start_game")

func initialize_boards(seed: int):
	# Set up the local board
	local_board.initialize(seed)
	
	# TODO: Set up network_board here once you know who is playing
	# network_board.initialize(seed)

func start_battle():
	# This triggers the actual 3-2-1-GO sequence on the board
	local_board.start(3)
