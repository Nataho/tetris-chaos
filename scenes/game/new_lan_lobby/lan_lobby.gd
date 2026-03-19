extends Control

const versus_plus_teams = {
	"red": Color8(203,0,0),
	"blue": Color8(0,0,203)
}

# - onready variables -
@onready var host_btn: Button = $"Control/side bar/host"
@onready var join_btn: Button = $"Control/side bar/IP_bar/join"
@onready var player_toggle: Button = $"Control/side bar/player_toggle"

@onready var ip_text_box: LineEdit = $"Control/side bar/IP_bar/ip_text_box"
@onready var username_text_box: LineEdit = $"Control/side bar/name"

@onready var player_node_snapshot:RichTextLabel = null
@onready var ui_player_node: RichTextLabel = $Control/Players/Player

@onready var chat_panel: VBoxContainer = $chat

@onready var chat: RichTextLabel = $chat/Panel/chat
@onready var chat_box: LineEdit = $chat/chat_box
@onready var master_timer: Timer = $MasterTimer

@onready var gamemode_selector: OptionButton = $"Control/side bar/gamemode_selector"
@onready var versus_plus_options: VBoxContainer = $"Control/side bar/versus_plus"
@onready var team_toggle: Button = $"Control/side bar/versus_plus/HBoxContainer/team_toggle"

var _ip_to_search:String = ""

var players_in_lobby = []
var match_ready_players:Array = []

var lobby_id = -1 #-1 means no ID
var battle_manager:BattleManager
var is_spectator:bool = false

var is_countdown_active = false
var countdown:int = 10

var game_started = false
var game_mode = BattleManager.VERSUS

var locked_in_time:int = 3

var current_p1_id: int = -1
var current_p2_id: int = -1

# versus_plus variables
var versus_plus_team = versus_plus_teams["red"]

func _ready() -> void:
	#if GameManager.dev_build: GameManager.change_resolution(500,500)
	
	players_in_lobby = [GameManager.player_data]
	
	connect_signals()
	setup_ui()
	
	Audio.play_music("lobby",Audio.SOUND_END_EFFECTS.FADE)

func _input(event: InputEvent) -> void:
	if GameManager.is_prompt_open: return
	if event.is_action_pressed("ready"):
		if !chat_box.has_focus():
			chat_box.grab_focus()
			get_viewport().set_input_as_handled()
	if event.is_action_pressed("pause"):
		back()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	const hidden_chat = Color(1,1,1,0.2)
	const visible_chat = Color(1,1,1,1)
	var target_modulate: Color
	
	if chat_box.has_focus():
		target_modulate = visible_chat
		chat_panel.z_index = 5
	else:
		target_modulate = hidden_chat
		chat_panel.z_index = 0
	
	chat_panel.modulate = chat_panel.modulate.lerp(target_modulate, 5 * delta)
	

func connect_signals():
	connect_network_signals()
	connect_ui_signals()
	
	
	
func connect_network_signals():
	# - network signals -
	Events.sync_interaction.connect(_on_sync_interaction)
	Events.sync_data.connect(_on_sync_data)
	
	# - server signals -
	Events.client_joined_lobby.connect(_on_client_joined)
	Events.client_left_lobby.connect(_on_client_left)
	
	# - client signals - 
	Events.client_disconnected.connect(_on_disconnected_from_host)
	Events.client_connected_to_server.connect(_on_client_connected_to_server)
	Events.server_accepted_join.connect(_on_server_accepted)
	Events.server_rejected_join.connect(_on_server_rejected)
	Events.connection_timeout.connect(_on_connection_timeout)

func connect_ui_signals():
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	username_text_box.text_changed.connect(_on_username_changed)
	
	ip_text_box.text_changed.connect(_on_ip_box_edited)
	player_toggle.pressed.connect(_on_player_toggled)
	chat_box.text_submitted.connect(_on_send_chat)
	Events.android_back_pressed.connect(back)
	
	master_timer.timeout.connect(_on_countdown_timer_timeout)
	
	gamemode_selector.item_selected.connect(_on_gamemode_selected)
	connect_versus_plus_signals()

func connect_versus_plus_signals():
	team_toggle.toggled.connect(_on_versus_team_toggled)

#region network handlers
func _on_sync_interaction(payload:Dictionary):
	var action = payload.get("action")
	match action:
		"start_game":
			pass
		"return_to_lobby":
			_on_game_concluded()

func _on_sync_data(payload:Dictionary):
	var data = payload.get("data", payload)
	var action = data.get("action", "")
	
	match action:
		"player_joined":
			# Safely extract just the name, whether it's a Dictionary or a String
			var joined_data = data.get("new_player", "Unknown")
			var new_name = ""
			if typeof(joined_data) == TYPE_DICTIONARY:
				new_name = str(joined_data.get("name", "Unknown"))
			else:
				new_name = str(joined_data)
				
			chat.text += "\n" + "[color=green]%s has joined the lobby[/color]" % new_name
			
			players_in_lobby = data.get("players", [])
			_update_player_list(players_in_lobby)
			
			# --- LATE JOINER SYNC LOGIC ---
			if data.has("game_mode"):
				var gm = int(data.get("game_mode", 0))
				if game_mode != gm:
					_on_gamemode_selected(gm)
					
			if data.get("game_started", false):
				game_started = true 
				$"Control/side bar/guide".text = "Match in progress... Please wait."
			else:
				$"Control/side bar/guide".text = "Waiting for opponent..."
				_check_start_requirements()
		"player_left":
			var left_name = data.get("player_left", "")
			chat.text += "\n" + "[color=yellow]%s has left the lobby [/color]" % left_name
			
			players_in_lobby = data.get("players", [])
			_update_player_list(players_in_lobby)
			
			if is_instance_valid(battle_manager):
				# Changed payload.get to data.get!
				var dropped_id = int(data.get("leaving_id", -1))
				print("Lobby Client| Received disconnect for ID: ", dropped_id)
				
				if dropped_id != -1 and battle_manager.has_method("_on_peer_disconnected"):
					battle_manager._on_peer_disconnected(dropped_id)
					
		"role_changed":
			var target_name = data.get("name", "")
			var new_spectator_state = data.get("is_spectator", false)
			
			for p in players_in_lobby:
				if p.get("name", "") == target_name:
					p["is_spectator"] = new_spectator_state
					break
					
			_update_player_list(players_in_lobby)
			
			if NetworkServer.server_active:
				var broadcast_payload = {
					"action": "list_updated", 
					"players": players_in_lobby
				}
				NetworkSync.sync_data(broadcast_payload)
				_check_start_requirements()
		
		"gamemode_changed":
			if NetworkServer.server_active: return
			var index:int = data.get("gamemode_index")
			_on_gamemode_selected(index)
		
		"team_changed":
			var target_name = data.get("name", "")
			var new_team = data.get("team", "red")
			
			for p in players_in_lobby:
				if p.get("name", "") == target_name:
					p["team"] = new_team
					break
					
			_update_player_list(players_in_lobby)
			
			if NetworkServer.server_active:
				var broadcast_payload = {
					"action": "list_updated", 
					"players": players_in_lobby
				}
				NetworkSync.sync_data(broadcast_payload)
				_check_start_requirements()
		
		"match_starting":
			var match_title = data.get("title", "Battle")
			var match_seed = data.get("seed", -1)
			var settings = data.get("settings", {})
			
			match_ready_players.clear()
			
			print("Lobby| PREPARING MATCH: ", match_title)
			$"Control/side bar/guide".text = match_title
			
			# Pass the generic dictionary directly into the start sequence
			initiate_start_sequence(match_seed, settings)
		
		#checks if both selected players are ready for battle
		"match_client_ready":
			var p_id = int(data.get("player_id", -1))
			
			if not match_ready_players.has(p_id):
				match_ready_players.append(p_id)
				print("Lobby| Player ", p_id, " finished intro. Ready list: ", match_ready_players)
		
		"chat":
			var sender:String = data.get("sender", "player")
			var message:String = data.get("message", "sent a message..")
			
			chat.text += "\n"
			chat.text += "<%s> %s" % [sender, message]
		
		"timer_sync":
			is_countdown_active = data.get("active", false)
			if not is_countdown_active:
				$"Control/side bar/guide".text = "Waiting for players..."
				player_toggle.disabled = false
		
		"timer_tick":
			var time = data.get("time")
			if time <= locked_in_time:
				player_toggle.disabled = true
			$"Control/side bar/guide".text = "STARTING IN: " + str(int(time))
		
# -client network signals-
func _on_client_connected_to_server():
	print("Client| connected")
	var join_data = GameManager.player_data.duplicate()
	join_data["is_spectator"] = is_spectator 
	join_data["team"] = "red" # default team
	NetworkClient.send_signal("join_lobby", join_data)

func _on_server_accepted(extra_data:Dictionary) -> void:
	lobby_id = extra_data.get("player_id", -1)
	
	# NEW: Ensure client captures the player list immediately on join
	if extra_data.has("players"):
		players_in_lobby = extra_data["players"]
		_update_player_list(players_in_lobby)
	
	if extra_data.get("is_mid_game", false):
		var snap = extra_data["snapshot"]
		# ... (your existing mid-game snapshot logic) ...
		game_started = true # This prevents the timer from starting on the client too
		$"Control/side bar/guide".text = "game in progress " + str(lobby_id)
	else:
		$"Control/side bar/guide".text = "Connected. ID: " + str(lobby_id)
		
	player_toggle.disabled = false
	gamemode_selector.disabled = true

func _on_server_rejected(extra_data:Dictionary) -> void:
	force_back()

func _on_disconnected_from_host() -> void:
	force_back()

# -server network signals-
func _on_client_joined(payload: Dictionary) -> void:
	if not NetworkServer.server_active: return
	
	# 1. Duplicate the dictionary so we don't mess up the actual server data
	var safe_player = payload.duplicate()
	
	# 2. Erase the socket object so it can be safely converted to JSON!
	safe_player.erase("socket")
	
	# 3. Add the safe version to the UI list
	players_in_lobby.append(safe_player)
	print("active_players", players_in_lobby)
	_update_player_list(players_in_lobby)
	
	# 4. Broadcast the safe data to all clients
	var sync_payload = {
		"action": "player_joined", 
		"players": players_in_lobby,
		"new_player": safe_player,
		"game_mode": game_mode, 
		"game_started": game_started
	}
	NetworkSync.sync_data(sync_payload)
	
	_check_start_requirements()

func _on_client_left(leaving_player: Dictionary) -> void:
	var p_name = str(leaving_player.get("name", "Unknown"))
	
	# Check for both common keys just in case!
	var leaving_id = leaving_player.get("player_id", leaving_player.get("id", -1))
	
	print("Lobby Server| Player Left! Name: ", p_name, " ID: ", leaving_id)
	
	# 1. Update local list
	for i in range(players_in_lobby.size() - 1, -1, -1):
		if str(players_in_lobby[i].get("name", "")) == p_name:
			players_in_lobby.remove_at(i)
			break
			
	_update_player_list(players_in_lobby)
	
	# 2. BROADCAST TO EVERYONE
	if NetworkServer.server_active:
		var sync_payload = {
			"action": "player_left", 
			"players": players_in_lobby,
			"player_left": p_name,
			"leaving_id": leaving_id
		}
		NetworkSync.sync_data(sync_payload)
	
		# 3. Handle Mid-Game Logic
		if game_started and is_instance_valid(battle_manager):
			if battle_manager.has_method("_on_peer_disconnected"):
				battle_manager._on_peer_disconnected(leaving_id)
			return 
	
		# 4. Normal Lobby Behavior
		$"Control/side bar/guide".text = "Waiting for opponent..."
		_check_start_requirements()

func _on_connection_timeout() -> void:
	print("Lobby| Connection timed out.")
	
	# Re-enable the UI so the player can try again
	host_btn.disabled = false
	join_btn.disabled = false
	ip_text_box.editable = true
	username_text_box.editable = true
	
	# Update the guide text to notify the user
	$"Control/side bar/guide".text = "Connection timed out. Server not found."
#endregion

#region battle logic
func initiate_start_sequence(match_seed: int, settings: Dictionary) -> void:
	print("Lobby| LAUNCHING BATTLE SCENE...")
	game_started = true
	
	$Control.visible = false
	$ColorRect.visible = false
	
	
	# Create the BattleManager using the new generic signature
	battle_manager = BattleManager.create(
		players_in_lobby,
		lobby_id,
		game_mode,
		is_spectator,
		match_seed,
		settings
	)
	
	battle_manager.game_concluded.connect(_on_game_concluded)
	add_child(battle_manager)

func _on_game_concluded():
	print("Lobby| Match concluded. Returning to lobby.")
	game_started = false
	
	# Safely delete the active battle
	if is_instance_valid(battle_manager):
		battle_manager.queue_free()
		
	# Bring the Lobby UI back
	$Control.visible = true
	$chat.visible = true
	$ColorRect.visible = true
	
	$"Control/side bar/guide".text = "Waiting for players..."
	toggle_lobby_ui(false)
	
	# If host, check if enough people are still here to immediately start a new countdown
	if NetworkServer.server_active:
		_check_start_requirements()
	
	Audio.play_music("lobby",Audio.SOUND_END_EFFECTS.FADE)

func _on_master_timer_timeout() -> void:
	if not NetworkServer.server_active: return
	
	is_countdown_active = false
	var eligible_players = []
	for p in players_in_lobby:
		if not p.get("is_spectator", false):
			eligible_players.append(p)
			
	var current_seed = randi()
	var match_settings = {}
	var match_title = ""
	
	if game_mode == BattleManager.VERSUS:
		eligible_players.shuffle()
		var p1 = eligible_players[0]
		var p2 = eligible_players[1]
		
		match_settings["p1_id"] = p1.get("player_id", -1)
		match_settings["p2_id"] = p2.get("player_id", -1)
		match_settings["first_to"] = 5 # You can change this later if you want a UI toggle
		
		match_title = "%s VS %s" % [p1.get("name", "P1"), p2.get("name", "P2")]
		
	elif game_mode == BattleManager.VERSUS_PLUS:
		var red_team_ids = []
		var blue_team_ids = []
		
		for p in eligible_players:
			if p.get("team", "red") == "red":
				red_team_ids.append(p.get("player_id", -1))
			else:
				blue_team_ids.append(p.get("player_id", -1))
				
		match_settings["red_team"] = red_team_ids
		match_settings["blue_team"] = blue_team_ids
		match_settings["first_to"] = 3
		
		match_title = "TEAM RED (%d) VS TEAM BLUE (%d)" % [red_team_ids.size(), blue_team_ids.size()]

	print("Lobby| MATCHUP: ", match_title)
	$"Control/side bar/guide".text = match_title
	
	# Broadcast the generic dictionary to all clients!
	NetworkSync.sync_data({
		"action": "match_starting",
		"title": match_title,
		"seed": current_seed,
		"settings": match_settings
	})

func _check_start_requirements() -> void:
	if not NetworkServer.server_active: return
	if game_started:
		return

	var eligible_players = []
	for p in players_in_lobby:
		if not p.get("is_spectator", false):
			eligible_players.append(p)

	var can_start = false
	
	# Determine logic based on Gamemode
	if game_mode == BattleManager.VERSUS:
		can_start = (eligible_players.size() >= 2)
	elif game_mode == BattleManager.VERSUS_PLUS:
		var red_count = 0
		var blue_count = 0
		for p in eligible_players:
			if p.get("team", "red") == "red": red_count += 1
			elif p.get("team", "red") == "blue": blue_count += 1
		can_start = (red_count > 0 and blue_count > 0)

	# Start or stop the timer
	if can_start:
		if not is_countdown_active:
			print("Lobby| Requirements met. Starting countdown!")
			is_countdown_active = true
			countdown = 10
			$"Control/side bar/guide".text = "STARTING IN: 10"
			NetworkSync.sync_data({"action": "timer_sync", "active": true})
			master_timer.wait_time = 1.0 
			master_timer.start()
	else:
		if is_countdown_active:
			print("Lobby| Requirements lost. Aborting countdown!")
			is_countdown_active = false
			master_timer.stop()
			NetworkSync.sync_data({"action": "timer_sync", "active": false})
			player_toggle.disabled = false
			$"Control/side bar/guide".text = "Waiting for players..."

func _on_countdown_timer_timeout() -> void:
	if not is_countdown_active:
		master_timer.stop()
		return
		
	countdown -= 1
	
	# Broadcast the tick to all clients
	NetworkSync.sync_data({
		"action": "timer_tick",
		"time": countdown
	})
	
	# Update the Host's local UI
	if countdown <= locked_in_time:
		toggle_lobby_ui(true)
	$"Control/side bar/guide".text = "STARTING IN: " + str(countdown)
	
	# When we hit zero, stop ticking and start the match!
	if countdown <= 0:
		master_timer.stop()
		_on_master_timer_timeout() # Your existing function that fires the game!
#endregion

#region UI element handlers
func setup_ui():
	player_node_snapshot = ui_player_node.duplicate()
	var my_name: String = GameManager.player_data["name"]
	username_text_box.text = my_name
	
	ui_player_node.text = my_name.to_upper()
	
	$"Control/side bar/versus_plus".hide()
	#ui_player_node.queue_free()
	
func _on_host_pressed() -> void:
	print("Hosting...")
	host_btn.release_focus()
	host_btn.disabled = true
	join_btn.disabled = true
	player_toggle.disabled = false
	ip_text_box.editable = false
	username_text_box.editable = false
	host_btn.text = "SERVER HOSTED"
	
	NetworkServer.start()
	
	lobby_id = 1
	
	var host_session = {
		"name": GameManager.player_data["name"],
		"player_id": lobby_id,
		"is_spectator": is_spectator,
		"is_host": true,
		"team": "red" #default team
	}
	players_in_lobby = [host_session]
	_update_player_list(players_in_lobby)

func _on_join_pressed() -> void:
	host_btn.disabled = true
	join_btn.disabled = true
	ip_text_box.editable = false
	username_text_box.editable = false
	
	# Give the user immediate feedback
	$"Control/side bar/guide".text = "Searching for host..."
	
	NetworkClient.start(_ip_to_search)

func _on_player_toggled():
	is_spectator = !is_spectator
	player_toggle.text = "SPECTATOR" if is_spectator else "PLAYER"
	
	var my_name = GameManager.player_data["name"]
	
	for p in players_in_lobby:
		if p.get("name", "") == my_name:
			p["is_spectator"] = is_spectator
			break
			
	_update_player_list(players_in_lobby)
		
	var sync_payload = {
		"action": "role_changed",
		"name": my_name,
		"is_spectator": is_spectator
	}
	
	if NetworkServer.server_active:
		NetworkSync.sync_data(sync_payload)
		_check_start_requirements()
	elif NetworkClient.client_active:
		NetworkClient.send_signal("sync_data", sync_payload)

func _on_ip_box_edited(text:String) -> void:
	_ip_to_search = text

func _on_username_changed(text:String) -> void:
	if text == "": text = "guest"
	GameManager.player_data["name"] = text
	GameManager.SAVE_GAME()
	
	# ONLY update the visual list if we are currently in a lobby!
	if players_in_lobby.size() > 0:
		players_in_lobby[0]["name"] = text
	_update_player_list(players_in_lobby)

func _on_send_chat(text:String):
	chat_box.text = ""
	chat_box.release_focus()
	if text == "": return
	var payload = {
		"action": "chat",
		"message": text,
		"sender": GameManager.player_data["name"]
	}
	NetworkSync.sync_data(payload)

func _update_player_list(players_array: Array) -> void:
	for child in $Control/Players.get_children():
		child.queue_free()

	for player in players_array:
		var p_name = str(player.get("name", "Unknown"))
		var is_spec = player.get("is_spectator", false)
		var p_is_host = player.get("is_host", false)
		var p_team = player.get("team", "red")
		
		var color_hex = "white"
		
		# Determine rendering color based on gamemode and state
		if is_spec:
			color_hex = "gray"
		elif game_mode == BattleManager.VERSUS_PLUS:
			color_hex = "#cb0000" if p_team == "red" else "#0000cb"
		elif p_is_host:
			color_hex = "gold"
			
		var bbcode_text = "[color=" + color_hex + "]" + p_name.to_upper() + "[/color]"
		
		var new_player_node = player_node_snapshot.duplicate()
		new_player_node.text = bbcode_text
		$Control/Players.add_child(new_player_node)

func _on_gamemode_selected(index:int):
	gamemode_selector.selected = index
	game_mode = index 
	
	var nodes_to_refresh = [versus_plus_options]
	for node:Control in nodes_to_refresh:
		node.hide()
		
	match index:
		0: # VERSUS
			pass
		1: # VERSUS_PLUS
			versus_plus_options.show()
	
	if NetworkServer.server_active:
		var payload = {
			"action": "gamemode_changed",
			"gamemode_index": index
		}
		NetworkSync.sync_data(payload)
		_check_start_requirements() # Re-check if we can start under the new mode's rules!


func _on_versus_team_toggled(toggled_on: bool):
	var team_string = "blue" if toggled_on else "red"
	versus_plus_team = versus_plus_teams[team_string]
	$"Control/side bar/versus_plus/HBoxContainer/team_toggle/ColorRect".color = versus_plus_team

	var my_name = GameManager.player_data["name"]
	
	# Update local dictionary
	for p in players_in_lobby:
		if p.get("name", "") == my_name:
			p["team"] = team_string
			break
			
	_update_player_list(players_in_lobby)
	
	# Sync with network
	var sync_payload = {
		"action": "team_changed",
		"name": my_name,
		"team": team_string
	}
	
	if NetworkServer.server_active:
		NetworkSync.sync_data(sync_payload)
		_check_start_requirements()
	elif NetworkClient.client_active:
		NetworkClient.send_signal("sync_data", sync_payload)

#endregion

#region helper functions

func toggle_lobby_ui(is_disabled:bool):
	player_toggle.disabled = is_disabled
	gamemode_selector.disabled = is_disabled
	team_toggle.disabled = is_disabled

func back():
	GameManager.is_prompt_open = true
	
	var prompt := ConfirmPrompt.create("Are you sure you want to exit the lobby?")
	add_child(prompt)
	
	var confirmed = await prompt.result
	
	if confirmed:
		NetworkClient.stop()
		NetworkServer.stop_server()
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	
	GameManager.is_prompt_open = false

func force_back():
	NetworkClient.stop()
	NetworkServer.stop_server()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
#endregion
