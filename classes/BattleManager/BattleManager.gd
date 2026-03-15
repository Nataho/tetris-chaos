extends Control
class_name BattleManager
const FILE = preload("uid://3deoyvpw2i7d")

@export var versus_scene: PackedScene 
@export var versus_plus_scene: PackedScene

signal game_concluded

enum {VERSUS, VERSUS_PLUS, BATTLE_ROYALE}
var _game_mode = VERSUS

var _is_spectator = true
var _player_id:int = -1

var active_players:Dictionary = {} 
var match_ready_players = []

var current_seed:int = -1

# NEW: We store everything mode-specific in this generic dictionary
var match_settings: Dictionary = {}

var mode_manager = null

# p1, p2, and ft are replaced by the settings dictionary
static func create(player_data: Array, lobby_id: int, game_mode: int, is_spectator: bool, seed: int, settings: Dictionary) -> BattleManager:
	var obj: BattleManager = FILE.instantiate()
	obj.active_players = _convert_players(player_data)
	obj._player_id = lobby_id
	obj._is_spectator = is_spectator
	obj._game_mode = game_mode
	
	obj.current_seed = seed
	obj.match_settings = settings
	return obj

static func _convert_players(player_data:Array) -> Dictionary:
	var new_data:Dictionary = {}
	for data in player_data:
		var player_id:int = data.get("player_id", -1)
		var player_name:String = data.get("name", "player")
		var player_spectator:bool = data.get("is_spectator", true)
		
		# Grab the team from the lobby (default to red just in case)
		var player_team:String = data.get("team", "red") 
		
		if player_spectator: continue
		
		# Save both the name AND the team to the new dictionary!
		new_data[player_id] = {
			"name": player_name,
			"team": player_team
		}
	return new_data

func _ready() -> void:
	await initialize_mode()
	
	if mode_manager:
		await _run_intro_sequence()
			
	_connect_signals()

func _connect_signals():
	Events.sent_garbage.connect(_on_garbage_sent)
	Events.sync_data.connect(_on_sync_data)

func initialize_mode():
	# 1. Instantiate the correct scene based on the game mode
	match _game_mode:
		VERSUS:
			if versus_scene:
				mode_manager = versus_scene.instantiate()
			else:
				# Fallback if the export variable is empty
				mode_manager = BattleVersus.FILE.instantiate() 
		VERSUS_PLUS:
			if versus_plus_scene:
				mode_manager = versus_plus_scene.instantiate()
			else:
				mode_manager = BattleVersusPlus.FILE.instantiate()
	
	if mode_manager == null:
		push_error("CRITICAL: BattleManager failed to spawn mode_manager! Did you assign the scenes in the Inspector?")
		return
		
	# 2. ADD TO TREE FIRST! (This wakes up all @onready variables inside the boards)
	add_child(mode_manager)
	
	# 3. NOW run setup safely since the nodes actually exist!
	mode_manager.setup(active_players, _player_id, _is_spectator, current_seed, match_settings)
	
	# 4. Connect signals dynamically
	if mode_manager.has_signal("request_network_sync"):
		mode_manager.request_network_sync.connect(_on_mode_sync_request)
	if mode_manager.has_signal("game_concluded"):
		mode_manager.game_concluded.connect(func(): game_concluded.emit())
	
	await get_tree().process_frame

func _run_intro_sequence() -> void:
	if mode_manager.has_method("play_intro"):
		await mode_manager.play_intro()
		
	var ready_payload = {"action": "client_ready", "player_id": _player_id}
	
	if NetworkServer.server_active:
		NetworkSync.sync_data(ready_payload)
		_on_sync_data(ready_payload) 
	elif NetworkClient.client_active:
		NetworkClient.sync_data(ready_payload)

func _on_mode_sync_request(payload: Dictionary) -> void:
	if NetworkServer.server_active:
		NetworkSync.sync_data(payload)
		# REMOVED: _on_sync_data(payload) <-- Let the network echo handle it
	elif NetworkClient.client_active:
		NetworkClient.sync_data(payload)

func _on_sync_data(payload: Dictionary) -> void:
	var data = payload.get("data", payload)
	var action = data.get("action", "")
	
	if action == "client_ready":
		var client_id = int(data.get("player_id", -1))
		if client_id != -1 and not match_ready_players.has(client_id):
			match_ready_players.append(client_id)
			
		if NetworkServer.server_active:
			if match_ready_players.size() >= active_players.size() or active_players.size() == 1:
				match_ready_players.clear() 
				var start_payload = {"action": "start_match"}
				NetworkSync.sync_data(start_payload)
				_on_sync_data(start_payload) 
		return
	
	# --- SERVER GARBAGE DISTRIBUTOR (VERSUS PLUS ONLY) ---
	if action == "spawn_garbage":
		# Safely dig into the payload to extract the values, accounting for the "value" sub-dictionary!
		var attacker_id = data.get("attacker_id", data.get("player_id", -1))
		var value_dict = data.get("value", {})
		var target_team_id = data.get("target_id", value_dict.get("target", 0))
		var amount = data.get("amount", value_dict.get("amount", 0))
		amount = int(amount)
		
		# Now we can properly check if it's a team attack (-2 or -3)
		if target_team_id < 0: 
			if NetworkServer.server_active and _game_mode == VERSUS_PLUS:
				print("garbage data: ", data)
				
				# Ask the mode for who is alive on that team
				var alive_targets = []
				if mode_manager and mode_manager.has_method("get_alive_team"):
					alive_targets = mode_manager.get_alive_team(target_team_id)
				
				if alive_targets.size() > 0:
					var base_amount = amount / alive_targets.size()
					var remainder = amount % alive_targets.size()
					
					# Shuffle the array so the remainder goes to a random player
					alive_targets.shuffle() 
					
					for t_id in alive_targets:
						var final_amount = base_amount + (1 if remainder > 0 else 0)
						remainder -= 1
						
						if final_amount > 0:
							var dist_payload = {
								"action": "spawn_garbage_distributed",
								"attacker_id": attacker_id,
								"target_id": t_id,
								"amount": final_amount
							}
							# Send the precise garbage drop back to all clients
							NetworkSync.sync_data(dist_payload)
							# Execute locally for the host
							#_on_sync_data(dist_payload) 
				return # Block the raw team attack from passing down!
				
			elif NetworkClient.client_active:
				# Clients completely ignore the raw team attack packet. 
				# They just sit and wait for the Server to send 'spawn_garbage_distributed'.
				return

	# --- RECEIVE DISTRIBUTED GARBAGE ---
	if action == "spawn_garbage_distributed":
		data["action"] = "spawn_garbage"
		action = "spawn_garbage"

	if mode_manager and mode_manager.has_method("process_action"):
		mode_manager.process_action(action, data)

func _on_garbage_sent(payload: Dictionary) -> void:
	var sync_payload = payload.duplicate(true)
	sync_payload["action"] = "spawn_garbage"
	
	if NetworkServer.server_active:
		NetworkSync.sync_data(sync_payload) 
		# REMOVED: _on_sync_data(sync_payload) -> The network echo handles this now!
	elif NetworkClient.client_active:
		NetworkClient.sync_data(sync_payload)
