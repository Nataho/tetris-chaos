extends Control

const versus_plus_teams = {
	"red": Color8(203,0,0),
	"blue": Color8(0,0,203)
}

# - onready variables -
@onready var create_btn: Button = $"Control/side bar/host" 
@onready var join_btn: Button = $"Control/side bar/IP_bar/join"
@onready var player_toggle: Button = $"Control/side bar/player_toggle"

@onready var room_id_box: LineEdit = $"Control/side bar/IP_bar/ip_text_box" 
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

var players_in_lobby = []
var match_ready_players:Array = []

var room_id: String = "" 
var is_host: bool = false 
var battle_manager: BattleManager
var is_spectator: bool = false

var is_countdown_active = false
var countdown: int = 10
var game_started = false
var game_mode = BattleManager.VERSUS
var locked_in_time: int = 3
var versus_first_to = 5
var versus_plus_team = versus_plus_teams["red"]

func _startup():
	is_host = TCPBridge.get_host_info()
	if is_host: 
		room_id_box.editable = false
		join_btn.disabled = true
		room_id_box.text = str(TCPBridge.get_lobby_id())
		$"Control/side bar/guide".text = "HOSTING: " + str(TCPBridge.get_lobby_id())

func _ready() -> void:
	_startup()
	NetworkSync.current_mode = NetworkSync.NetMode.ONLINE
	
	connect_signals()
	setup_ui()
	
	# --- NEW: REGISTER PROFILE WITH PYTHON SERVER ---
	# We send this immediately so Python knows who we are and can give us the player list!
	var my_profile = GameManager.player_data.duplicate()
	my_profile["is_spectator"] = is_spectator
	my_profile["team"] = "red"
	
	TCPBridge.send_to_server({
		"type": "room_action",
		"signal": "join_lobby",
		"data": my_profile
	})
	
	Audio.play_music("lobby", Audio.SOUND_END_EFFECTS.FADE)

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
	# Route game actions through NetworkSync
	Events.sync_interaction.connect(_on_sync_interaction)
	Events.sync_data.connect(_on_sync_data)
	
	# --- NEW: AUTHORITATIVE SERVER SIGNALS ---
	Events.server_accepted_join.connect(_on_join_accepted)
	Events.server_rejected_join.connect(_on_join_rejected)
	Events.client_joined_lobby.connect(_on_client_joined)
	Events.client_left_lobby.connect(_on_client_left)

	username_text_box.text_changed.connect(_on_username_changed)
	player_toggle.pressed.connect(_on_player_toggled)
	chat_box.text_submitted.connect(_on_send_chat)
	Events.android_back_pressed.connect(back)
	
	master_timer.timeout.connect(_on_countdown_timer_timeout)
	gamemode_selector.item_selected.connect(_on_gamemode_selected)
	team_toggle.toggled.connect(_on_versus_team_toggled)


# ==========================================
# SERVER HANDSHAKE RESPONSES
# ==========================================

func _on_join_accepted(data: Dictionary):
	# The server officially accepted us and sent us the current player list!
	players_in_lobby = data.get("players", [])
	_update_player_list(players_in_lobby)
	
	chat.text += "\n[color=yellow]Connected to Lobby %s[/color]" % str(TCPBridge.get_lobby_id())
	if is_host: _check_start_requirements()

func _on_join_rejected(data: Dictionary):
	var reason = data.get("reason", "Unknown Error")
	var prompt := ConfirmPrompt.create("Failed to join: " + reason, ["no_cancel"])
	add_child(prompt)
	await prompt.result
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")

func _on_client_joined(new_player: Dictionary):
	# The server is telling us someone else just walked into the room
	for p in players_in_lobby:
		# FIX: Changed 'data' to 'new_player' 
		if p.get("uid", -1) == new_player.get("uid", -2):
			return
	
	players_in_lobby.append(new_player)
	_update_player_list(players_in_lobby)
	
	var joining_name = new_player.get("name", "Unknown")
	chat.text += "\n[color=green]%s joined the lobby[/color]" % joining_name
	print(players_in_lobby)
	if is_host: 
		var payload = {
			"action": "list_updated",
			"players": players_in_lobby
		} 
		NetworkSync.sync_data(payload)
		_check_start_requirements()

func _on_client_left(leaving_player: Dictionary):
	# The server is telling us someone left
	var leaving_name = leaving_player.get("name", "Unknown")
	chat.text += "\n[color=yellow]%s left the lobby[/color]" % leaving_name
	
	for i in range(players_in_lobby.size() - 1, -1, -1):
		# Check by UID or Name
		if players_in_lobby[i].get("uid") == leaving_player.get("uid") or players_in_lobby[i].get("name") == leaving_name:
			players_in_lobby.remove_at(i)
			break
			
	_update_player_list(players_in_lobby)
	if is_host: _check_start_requirements()

# ==========================================
# ROOM DATA SYNC (Relayed via Python)
# ==========================================

func _on_sync_data(payload: Dictionary):
	var data = payload.get("data", payload)
	var action = data.get("action", "")
	
	match action:
		"list_updated":
			players_in_lobby = data.get("players", [])
			_update_player_list(players_in_lobby)

		"role_changed":
			var target_name = data.get("name", "")
			var new_spectator_state = data.get("is_spectator", false)
			
			for p in players_in_lobby:
				if p.get("name", "") == target_name:
					p["is_spectator"] = new_spectator_state
					break
			_update_player_list(players_in_lobby)
			
			if is_host:
				NetworkSync.sync_data({"action": "list_updated", "players": players_in_lobby})
				_check_start_requirements()
				
		"gamemode_changed":
			if is_host: return # Host already applied it locally
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
			
			if is_host:
				NetworkSync.sync_data({"action": "list_updated", "players": players_in_lobby})
				_check_start_requirements()

		"match_starting":
			var match_title = data.get("title", "Battle")
			var match_seed = data.get("seed", -1)
			var settings = data.get("settings", {})
			
			match_ready_players.clear()
			print("Lobby| PREPARING MATCH: ", match_title)
			$"Control/side bar/guide".text = match_title
			initiate_start_sequence(match_seed, settings)

		"chat":
			var sender:String = data.get("sender", "player")
			var message:String = data.get("message", "...")
			chat.text += "\n<%s> %s" % [sender, message]

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

func _on_sync_interaction(payload:Dictionary):
	var action = payload.get("action")
	if action == "return_to_lobby":
		_on_game_concluded()

# ==========================================
# BATTLE LOGIC (Handled by Host)
# ==========================================

func _check_start_requirements() -> void:
	if not is_host or game_started: return

	var eligible_players = []
	for p in players_in_lobby:
		if not p.get("is_spectator", false):
			eligible_players.append(p)

	var can_start = false
	
	if game_mode == BattleManager.VERSUS:
		can_start = (eligible_players.size() >= 2)
	elif game_mode == BattleManager.VERSUS_PLUS:
		var red_count = 0; var blue_count = 0
		for p in eligible_players:
			if p.get("team", "red") == "red": red_count += 1
			elif p.get("team", "red") == "blue": blue_count += 1
		can_start = (red_count > 0 and blue_count > 0)

	if can_start:
		if not is_countdown_active:
			is_countdown_active = true
			countdown = 10
			$"Control/side bar/guide".text = "STARTING IN: 10"
			NetworkSync.sync_data({"action": "timer_sync", "active": true})
			master_timer.wait_time = 1.0 
			master_timer.start()
	else:
		if is_countdown_active:
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
	NetworkSync.sync_data({"action": "timer_tick", "time": countdown})
	
	if countdown <= locked_in_time:
		toggle_lobby_ui(true)
	$"Control/side bar/guide".text = "STARTING IN: " + str(countdown)
	
	if countdown <= 0:
		master_timer.stop()
		_fire_start_game()

func _fire_start_game() -> void:
	if not is_host: return
	is_countdown_active = false
	var eligible_players = []
	for p in players_in_lobby:
		if not p.get("is_spectator", false): eligible_players.append(p)
			
	var current_seed = randi()
	var match_settings = {}
	var match_title = ""
	
	if game_mode == BattleManager.VERSUS:
		eligible_players.shuffle()
		# Use 'uid' here because 'player_id' changes/clashes on the Python server
		match_settings["p1_id"] = int(eligible_players[0].get("uid", -1))
		match_settings["p2_id"] = int(eligible_players[1].get("uid", -1))
		match_settings["first_to"] = versus_first_to 
		match_title = "%s VS %s" % [eligible_players[0].get("name", "P1"), eligible_players[1].get("name", "P2")]
		
	elif game_mode == BattleManager.VERSUS_PLUS:
		var red_team_ids = []
		var blue_team_ids = []
		for p in eligible_players:
			var p_uid = int(p.get("uid", -1))
			if p.get("team", "red") == "red":
				red_team_ids.append(p_uid)
			else:
				blue_team_ids.append(p_uid)
				
		match_settings["red_team"] = red_team_ids
		match_settings["blue_team"] = blue_team_ids
		match_settings["first_to"] = versus_first_to 
		match_title = "TEAM RED (%d) VS TEAM BLUE (%d)" % [red_team_ids.size(), blue_team_ids.size()]

	# ONLY send the network signal. 
	# The Host will start automatically when it receives its own 'echo' signal.
	print("Lobby| Blasting match_starting signal...")
	NetworkSync.sync_data({
		"action": "match_starting",
		"title": match_title,
		"seed": current_seed,
		"settings": match_settings
	})

func initiate_start_sequence(match_seed: int, settings: Dictionary) -> void:
	game_started = true
	$Control.visible = false
	$ColorRect.visible = false
	
	# FIND OUR OWN UID: This is how we know which board we control!
	var my_name = GameManager.player_data["name"]
	var my_uid = -1
	for p in players_in_lobby:
		if p.get("name") == my_name:
			my_uid = int(p.get("uid", -1))
			break
	
	print("Lobby| Starting Battle as Local UID: ", my_uid)
	
	battle_manager = BattleManager.create(
		players_in_lobby,
		my_uid, # Pass the UID, NOT the Room ID!
		game_mode,
		is_spectator,
		match_seed,
		settings
	)
	battle_manager.game_concluded.connect(_on_game_concluded)
	add_child(battle_manager)

func _on_game_concluded():
	game_started = false
	if is_instance_valid(battle_manager): battle_manager.queue_free()
		
	$Control.visible = true
	$chat.visible = true
	$ColorRect.visible = true
	
	$"Control/side bar/guide".text = "Waiting for players..."
	toggle_lobby_ui(false)
	
	if is_host: _check_start_requirements()
	Audio.play_music("lobby", Audio.SOUND_END_EFFECTS.FADE)

# ==========================================
# UI & HELPERS
# ==========================================

func setup_ui():
	player_node_snapshot = ui_player_node.duplicate()
	var my_name: String = GameManager.player_data["name"]
	username_text_box.text = my_name
	ui_player_node.text = my_name.to_upper()
	$"Control/side bar/versus_plus".hide()

func _on_player_toggled():
	is_spectator = !is_spectator
	player_toggle.text = "SPECTATOR" if is_spectator else "PLAYER"
	var my_name = GameManager.player_data["name"]
	
	for p in players_in_lobby:
		if p.get("name", "") == my_name:
			p["is_spectator"] = is_spectator
			break
			
	_update_player_list(players_in_lobby)
	var sync_payload = {"action": "role_changed", "name": my_name, "is_spectator": is_spectator}
	NetworkSync.sync_data(sync_payload)
	if is_host: _check_start_requirements()

func _on_gamemode_selected(index:int):
	gamemode_selector.selected = index
	game_mode = index 
	
	versus_plus_options.hide()
	if index == 1: versus_plus_options.show()
	
	if is_host:
		NetworkSync.sync_data({"action": "gamemode_changed", "gamemode_index": index})
		_check_start_requirements()

func _on_versus_team_toggled(toggled_on: bool):
	var team_string = "blue" if toggled_on else "red"
	versus_plus_team = versus_plus_teams[team_string]
	$"Control/side bar/versus_plus/HBoxContainer/team_toggle/ColorRect".color = versus_plus_team

	var my_name = GameManager.player_data["name"]
	for p in players_in_lobby:
		if p.get("name", "") == my_name:
			p["team"] = team_string
			break
			
	_update_player_list(players_in_lobby)
	NetworkSync.sync_data({"action": "team_changed", "name": my_name, "team": team_string})
	if is_host: _check_start_requirements()

func _on_username_changed(text:String) -> void:
	if text == "": text = "guest"
	GameManager.player_data["name"] = text
	GameManager.SAVE_GAME()
	
	if players_in_lobby.size() > 0:
		players_in_lobby[0]["name"] = text
	_update_player_list(players_in_lobby)

func _on_send_chat(text:String):
	chat_box.text = ""
	chat_box.release_focus()
	if text == "": return
	
	var my_name = GameManager.player_data["name"]
	
	# THE CHAT FIX: Display the text to ourselves immediately!
	chat.text += "\n<%s> %s" % [my_name, text]
	
	# Send it to the server so everyone else can see it
	NetworkSync.sync_data({
		"action": "chat", "message": text, "sender": my_name
	})

func _update_player_list(players_array: Array) -> void:
	for child in $Control/Players.get_children():
		child.queue_free()

	for player in players_array:
		var p_name = str(player.get("name", "Unknown"))
		var is_spec = player.get("is_spectator", false)
		var p_team = player.get("team", "red")
		
		# (Optional) If you want the Host to be Gold again, we can re-add logic for it later,
		# but right now Python isn't tracking who the host is inside the player_data dict!
		var color_hex = "white"
		
		if is_spec: color_hex = "gray"
		elif game_mode == BattleManager.VERSUS_PLUS:
			color_hex = "#cb0000" if p_team == "red" else "#0000cb"
			
		var bbcode_text = "[color=" + color_hex + "]" + p_name.to_upper() + "[/color]"
		var new_player_node = player_node_snapshot.duplicate()
		new_player_node.text = bbcode_text
		$Control/Players.add_child(new_player_node)

func toggle_lobby_ui(is_disabled:bool):
	create_btn.disabled = is_disabled
	join_btn.disabled = is_disabled
	room_id_box.editable = !is_disabled
	username_text_box.editable = !is_disabled
	player_toggle.disabled = is_disabled
	team_toggle.disabled = is_disabled
	# Only allow the host to change gamemode when ui is "enabled"
	gamemode_selector.disabled = is_disabled if is_host else true 

func back():
	GameManager.is_prompt_open = true
	var prompt := ConfirmPrompt.create("Are you sure you want to exit the lobby?")
	add_child(prompt)
	
	var confirmed = await prompt.result
	if confirmed:
		# Optionally, tell Python we are leaving
		# TCPBridge.send_to_server({"type": "leave_room"}) 
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	
	GameManager.is_prompt_open = false
