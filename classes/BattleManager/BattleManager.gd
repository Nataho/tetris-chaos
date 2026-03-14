extends Control
class_name BattleManager
const FILE = preload("uid://3deoyvpw2i7d")

@export var versus_scene: PackedScene 

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
		
		if player_spectator: continue
		new_data[player_id] = {"name": player_name}
	return new_data

func _ready() -> void:
	if _game_mode == VERSUS:
		await initialize_versus()
		await _run_intro_sequence()
			
	_connect_signals()

func _connect_signals():
	Events.sent_garbage.connect(_on_garbage_sent)
	Events.sync_data.connect(_on_sync_data)

func initialize_versus():
	# 1. Instantiate the scene directly from the preloaded FILE
	mode_manager = BattleVersus.FILE.instantiate()
	
	if mode_manager == null:
		push_error("CRITICAL: BattleManager failed to spawn mode_manager!")
		return
		
	# 2. ADD TO TREE FIRST! (This wakes up all @onready variables inside the boards)
	add_child(mode_manager)
	
	# 3. NOW run setup safely since the nodes actually exist!
	mode_manager.setup(active_players, _player_id, _is_spectator, current_seed, match_settings)
	
	# 4. Connect signals
	mode_manager.request_network_sync.connect(_on_mode_sync_request)
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
				
				# 1. Send to others
				NetworkSync.sync_data(start_payload)
				# 2. FIX: Execute locally for the server. 
				# BattleVersus._match_started_flag will prevent double-firing!
				_on_sync_data(start_payload) 
		return
	
	# EVERYTHING else gets completely handed off to the mode!
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
