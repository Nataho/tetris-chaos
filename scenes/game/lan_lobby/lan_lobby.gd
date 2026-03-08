extends Control

@export_range(1, 10, 1) var first_to: int = 5

@onready var host_btn: Button = $"Control/side bar/host"
@onready var join_btn: Button = $"Control/side bar/IP_bar/join"

@onready var ip_text_box: LineEdit = $"Control/side bar/IP_bar/ip_text_box"
@onready var plyr_tgl_btn: Button = $"Control/side bar/player_toggle"

@onready var username_text_box: LineEdit = $"Control/side bar/name"

@onready var ui_player_node: RichTextLabel = $Control/Players/Player

@onready var anim: AnimationPlayer = $versus/AnimationPlayer
@onready var master_timer: Timer = $MasterTimer

@onready var player_1_anchor: Control = $versus/player1_anchor
@onready var player_2_anchor: Control = $versus/player2_anchor

@onready var scoreboard: RichTextLabel = $versus/score

var game_started:bool = false
var game_finished: bool = false

var match_ready_players: Array = []

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
var p1_active: bool = false
var p2_active: bool = false

# --- Active Match Variables ---
var active_p1_board:MultiplayerBoard = null
var active_p2_board:MultiplayerBoard = null

var is_resetting: bool = false

var current_p1_id: int = -1
var current_p2_id: int = -1

var p1_match_score: int = 0
var p2_match_score: int = 0

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
	
	NetworkServer.start()
	
	my_lobby_id = 1
	
	var host_session = {
		"name": GameManager.player_data["name"],
		"player_id": my_lobby_id,
		"is_spectator": is_spectator,
		"is_host": true,
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
	print("payload", payload)
	if payload.get("action") == "start_game":
		start_battle()

func _on_sync_data(payload: Dictionary) -> void:
	var data = payload.get("data", payload)
	var action = data.get("action", "")
		
	if action == "player_joined":
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
		var p1_id = int(data.get("p1_id", -1)) 
		var p2_id = int(data.get("p2_id", -1)) 
		var match_seed = data.get("seed", -1)
		
		# --> SAVE THESE FOR THE START CHECK <--
		current_p1_id = p1_id
		current_p2_id = p2_id
		
		match_ready_players.clear()
		
		print("Lobby| MATCHUP: ", p1_name, " VS ", p2_name)
		$"Control/side bar/guide".text = p1_name + " VS " + p2_name
		
		initiate_start_sequence(p1_name, p2_name, match_seed, p1_id, p2_id)
	
	elif action == "match_client_ready":
		var p_id = int(data.get("player_id", -1))
		
		if not match_ready_players.has(p_id):
			match_ready_players.append(p_id)
			print("Lobby| Player ", p_id, " finished intro. Ready list: ", match_ready_players)
			
		# ONLY the Host checks to see if it's time to start
		if NetworkServer.server_active:
			print("Lobby| Host waiting for IDs: ", current_p1_id, " and ", current_p2_id)
			
			# Check against our safely saved IDs instead of asking the boards!
			if match_ready_players.has(current_p1_id) and match_ready_players.has(current_p2_id):
				print("Lobby| ALL CLEAR! Both players ready. Firing start_game.")
				match_ready_players.clear()
				
				# Fire the universal start command
				NetworkSync.sync_interaction("start_game")
	
	elif action == "next_round":
		var next_seed = data.get("seed", -1)
		# Grab the scores, fallback to the current ones just in case
		var p1_score = data.get("p1_score", active_p1_board.kos)
		var p2_score = data.get("p2_score", active_p2_board.kos)
		
		_perform_next_round_transition(next_seed, p1_score, p2_score) # Pass them here
	
	elif action == "match_over":
		var p1_won = data.get("p1_won", true)
		
		# Grab the final scores
		var p1_score = data.get("p1_score", p1_match_score)
		var p2_score = data.get("p2_score", p2_match_score)
		
		p1_match_score = p1_score
		p2_match_score = p2_score
		
		# Force the final UI update before the victory screen
		if active_p1_board: active_p1_board.kos = p1_score
		if active_p2_board: active_p2_board.kos = p2_score
		update_scoreboard(p1_score, p2_score)
		
		_perform_match_over_sequence(p1_won)
	
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
	var leaving_id = leaving_player.get("player_id", -1) # Grab their ID
	
	# 1. Remove them from the lobby list (happens whether in-game or not)
	for i in range(active_players.size() - 1, -1, -1):
		if str(active_players[i].get("name", "")) == p_name:
			active_players.remove_at(i)
			break
			
	_update_player_list(active_players)
	
	# 2. Check if a match is currently running
	if game_started:
		# Was the person who left actually fighting?
		if leaving_id == current_p1_id or leaving_id == current_p2_id:
			print("Lobby| ACTIVE PLAYER DISCONNECTED! Aborting match...")
			_return_to_lobby()
			$"Control/side bar/guide".text = p_name + " disconnected!"
		else:
			print("Lobby| Spectator " + p_name + " left. The match continues.")
			
		# We return early here so we don't accidentally trigger lobby timers mid-game
		return 

	# 3. Normal Lobby Behavior (Only runs if game_started is false)
	$"Control/side bar/guide".text = "Waiting for opponent..."
	
	if NetworkServer.server_active:
		var sync_payload = {
			"action": "player_joined", # (Reusing this action to sync the updated list)
			"players": active_players
		}
		NetworkSync.sync_data(sync_payload)
		_check_start_requirements()

func _on_disconnected_from_host() -> void:
	back()
	#get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")

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
		var p1_id = p1.get("player_id", -1) # <--- GET ID
		var p2_id = p2.get("player_id", -1) # <--- GET ID
		
		current_seed = randi()
		
		print("Lobby| MATCHUP: ", p1_name, " VS ", p2_name)
		$"Control/side bar/guide".text = p1_name + " VS " + p2_name
		
		# Broadcast to Clients
		NetworkSync.sync_data({
			"action": "players_selected",
			"p1_name": p1_name,
			"p2_name": p2_name,
			"p1_id": p1_id,     # <--- SEND ID
			"p2_id": p2_id,     # <--- SEND ID
			"seed": current_seed
		})
		
		# Host triggers their own start sequence!
		#initiate_start_sequence(p1_name, p2_name, current_seed, p1_id, p2_id)
	else:
		$"Control/side bar/guide".text = "Not enough players!"
		_check_start_requirements()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		back()
	#elif event.is_action_pressed("ready"):
		#if NetworkServer.server_active:
			## Host can force start instantly if they want
			#_on_master_timer_timeout()
		#else:
			#print("Client| Only the host can force start.")

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
	
	if p1_active:
		local_pos = Vector2(screen_size.x * (0.5 - DISTANCE), screen_center.y)
		local_mod = Color.WHITE
	if p2_active:
		network_pos = Vector2(screen_size.x * (0.5 + DISTANCE), screen_center.y)
		network_mod = Color.WHITE
	
	player_1_anchor.position = player_1_anchor.position.lerp(local_pos, lerp_weight)
	player_2_anchor.position = player_2_anchor.position.lerp(network_pos, lerp_weight)
	player_1_anchor.modulate = player_1_anchor.modulate.lerp(local_mod, lerp_weight)
	player_2_anchor.modulate = player_2_anchor.modulate.lerp(network_mod, lerp_weight)

func initiate_start_sequence(p1_name: String, p2_name: String, seed: int, p1_id: int, p2_id: int):
	# Make sure your "intro" animation actually changes this modulate back to visible!
	$versus.modulate = Color.TRANSPARENT 
	$Control.hide()
	$versus.show()
	
	# You successfully give it the names right here!
	$versus/HBoxContainer/left_side/Label.text = p1_name.to_upper()
	$versus/HBoxContainer/right_side/Label.text = p2_name.to_upper()
	$versus/HBoxContainer/left_side/Label.show()
	$versus/HBoxContainer/right_side/Label.show()

	player_1_anchor.show()
	player_2_anchor.show()
	
	p1_match_score = 0
	p2_match_score = 0
	update_scoreboard(0, 0)
	
	# Start the intro animation
	anim.play("intro")
	
	p1_active = true
	p2_active = true
	
	initialize_boards(seed, p1_id, p2_id)
	
	Audio.trigger_fade_out(2)
	Audio.play_sound("match_intro", 0.56)
	
	# ---> ADD THIS LINE: Wait for the intro animation to finish! <---
	await anim.animation_finished 
	
	# NOW hide the labels, after the player has had time to read them
	$versus/HBoxContainer/left_side/Label.hide()
	$versus/HBoxContainer/right_side/Label.hide()
	
	Audio.play_music("epic_battle")
	
	var ready_payload = {
		"action": "match_client_ready",
		"player_id": my_lobby_id
	}
	
	if NetworkServer.server_active:
		NetworkSync.sync_data(ready_payload)
	elif NetworkClient.client_active:
		NetworkClient.sync_data(ready_payload)

func initialize_boards(seed: int, p1_id: int, p2_id: int):
	# Are we one of the players?
	var i_am_p1 = (my_lobby_id == p1_id)
	var i_am_p2 = (my_lobby_id == p2_id)
	
	if i_am_p1:
		# I am P1: My board is Local, opponent is Network
		active_p1_board = LocalBoard.create(p1_id, p2_id)
		active_p2_board = NetworkBoard.create(p2_id, p1_id, is_spectator)
	elif i_am_p2:
		# I am P2: Opponent is Network, my board is Local
		active_p1_board = NetworkBoard.create(p1_id, p2_id, is_spectator)
		active_p2_board = LocalBoard.create(p2_id, p1_id)
	else:
		# I am a Spectator: Both are Network boards
		active_p1_board = NetworkBoard.create(p1_id, p2_id, is_spectator)
		active_p2_board = NetworkBoard.create(p2_id, p1_id, is_spectator)
	
	# Add to the Scene Tree first so _ready() fires before initialize()
	player_1_anchor.add_child(active_p1_board)
	player_2_anchor.add_child(active_p2_board)
	
	active_p1_board.knocked_out.connect(_on_board_knocked_out)
	active_p2_board.knocked_out.connect(_on_board_knocked_out)
	
	# Only initialize with a seed if the board is a LocalBoard
	if active_p1_board is LocalBoard:
		active_p1_board.initialize(seed)
	else:
		active_p1_board.initialize()
		
	if active_p2_board is LocalBoard:
		active_p2_board.initialize(seed)
	else:
		active_p2_board.initialize()

func _on_board_knocked_out(dead_board) -> void:
	if is_resetting: return
	
	if NetworkServer.server_active:
		is_resetting = true
		
		# The Server decides the score based on who died
		if dead_board == active_p1_board:
			p2_match_score += 1
		elif dead_board == active_p2_board:
			p1_match_score += 1
		
		# Check if anyone hit the win limit
		if p1_match_score >= first_to or p2_match_score >= first_to:
			var p1_won = p1_match_score >= first_to
			
			NetworkSync.sync_data({
				"action": "match_over",
				"p1_won": p1_won,
				"p1_score": p1_match_score, # Send final score to clients
				"p2_score": p2_match_score
			})
		else:
			var new_seed = randi()
			NetworkSync.sync_data({
				"action": "next_round",
				"seed": new_seed,
				"p1_score": p1_match_score,
				"p2_score": p2_match_score 
			})

func _perform_next_round_transition(new_seed: int, p1_score: int, p2_score: int) -> void:
	is_resetting = true # Lock clients out too
	
	# Sync our local script variables
	p1_match_score = p1_score
	p2_match_score = p2_score
	
	# Force the boards' internal counters to match the server's source of truth!
	if active_p1_board: active_p1_board.kos = p1_score
	if active_p2_board: active_p2_board.kos = p2_score
	
	# Pass the correct scores to the UI
	update_scoreboard(p1_score, p2_score)
	
	# 1. Wait a second so the players can actually see the KO happen
	await get_tree().create_timer(1.0).timeout
	
	# (Optional: Play your screen wipe animation here if you have one)
	anim.play("next_round_in")
	await anim.animation_finished
	
	# 2. Re-initialize and Reset both boards
	if active_p1_board:
		if active_p1_board is LocalBoard:
			active_p1_board.initialize(new_seed)
		else:
			active_p1_board.initialize()
		await active_p1_board.reset()
		
	if active_p2_board:
		if active_p2_board is LocalBoard:
			active_p2_board.initialize(new_seed)
		else:
			active_p2_board.initialize()
		await active_p2_board.reset()
		
	# (Optional: Play screen wipe out animation here)
	anim.play("next_round_out")
	await anim.animation_finished
	
	# 3. Trigger the 3-2-1-GO sequence again!
	start_battle()
	
	# 4. Unlock
	is_resetting = false

func _perform_match_over_sequence(p1_won: bool) -> void:
	is_resetting = true
	
	# 1. Stop the game logic completely
	if active_p1_board: active_p1_board.stop()
	if active_p2_board: active_p2_board.stop()
	
	# (Optional: Trigger your big "PLAYER X WINS!" UI text here)
	
	# 2. Play the victory audio (ported from your local script)
	Audio.play_music("victory", Audio.SOUND_END_EFFECTS.VINYL)
	await Audio.music_player_node.finished
	
	# 3. Wait for the music/sound to finish, or just wait a fixed amount of time
	# If you want to use the audio signal: await Audio.music_player_node.finished
	#await get_tree().create_timer(4.0).timeout 
	
	# 4. Return back to the Lobby
	_return_to_lobby()

func _return_to_lobby() -> void:
	# Clean up the active game boards
	if active_p1_board: 
		active_p1_board.queue_free()
		active_p1_board = null
	if active_p2_board: 
		active_p2_board.queue_free()
		active_p2_board = null
		
	# Reset state variables
	game_started = false
	is_resetting = false
	game_finished = false
	
	# Reset animation variables so they slide back in correctly next time
	p1_active = false
	p2_active = false
	
	plyr_tgl_btn.disabled = false
	
	# Restart the lobby music
	Audio.play_music("lobby", Audio.SOUND_END_EFFECTS.FADE)
	
	# Show the Lobby UI and hide the Versus Game UI
	$versus.hide()
	$Control.show()
	$ColorRect.modulate = Color.WHITE
	# Reset the guide text and check if we have enough players to start the timer again
	$"Control/side bar/guide".text = "Waiting for players..."
	_check_start_requirements()

# --- Scoring and UI Logic ---

func update_scoreboard(p1_score: int, p2_score: int, discrete: bool = false) -> void:
	var match_point = first_to - 1
	
	if (p1_score >= first_to or p2_score >= first_to) and not game_finished:
		game_finished = true
		# _perform_match_over_sequence handles the actual win logic in the network script
	
	var p1_text = "[color=red](%d/%d)[/color]" % [p1_score, first_to]
	var p2_text = "[color=blue](%d/%d)[/color]" % [p2_score, first_to]
	if discrete: return

	if p1_score == match_point and p2_score == match_point:
		p1_text = "[shake rate=20.0 level=8]%s[/shake]" % p1_text
		p2_text = "[shake rate=20.0 level=8]%s[/shake]" % p2_text
	else:
		p1_text = apply_status_effects(p1_text, p1_score, p2_score, match_point)
		p2_text = apply_status_effects(p2_text, p2_score, p1_score, match_point)

	# Adapted to use 'scoreboard' instead of 'score_label'
	scoreboard.text = "[center]%s  FT%d  %s[/center]" % [p1_text, first_to, p2_text]

func apply_status_effects(text: String, score: int, opp_score: int, mp: int) -> String:
	
	var modified_text = text
	
	if score == mp and !game_finished:
		if game_started:
			Audio.play_sound("match_point")
		modified_text = "[bounce amp=15.0 freq=5.0]%s[/bounce]" % text
	elif score > opp_score:
		modified_text = "[wave amp=50.0 freq=5.0 connected=1]%s[/wave]" % text
	
	if score > mp and game_finished:
		modified_text = "[bounce amp=15.0 freq=5.0]%s[/bounce]" % text
	elif game_finished: 
		modified_text = "[shake rate=20.0 level=8]%s[/shake]" % text
	
	return modified_text

func start_battle():
	game_started = true
	
	# Trigger the 3-2-1-GO sequence for whatever boards exist
	if active_p1_board:
		if active_p1_board is LocalBoard:
			active_p1_board.start(3)
	if active_p2_board:
		if active_p2_board is LocalBoard:
			active_p2_board.start(3)
