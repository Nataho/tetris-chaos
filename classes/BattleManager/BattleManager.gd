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
var first_to: int = 1 
var p1_id:int = -1
var p2_id:int = -1

var mode_manager = null
var active_boards:Dictionary = {} 

static func create(player_data: Array, lobby_id: int, game_mode: int, is_spectator: bool, p1: int, p2: int, seed: int) -> BattleManager:
	var obj: BattleManager = FILE.instantiate()
	obj.active_players = _convert_players(player_data)
	obj._player_id = lobby_id
	obj._is_spectator = is_spectator
	obj._game_mode = game_mode
	
	obj.p1_id = p1
	obj.p2_id = p2
	obj.current_seed = seed
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
	mode_manager = BattleVersus.create(active_players, _player_id, p1_id, p2_id, _is_spectator, current_seed, first_to)
	
	if mode_manager == null:
		push_error("CRITICAL: BattleManager failed to spawn mode_manager!")
		return
		
	add_child(mode_manager)
	
	# Hook up signals so the mode can communicate outward
	mode_manager.request_network_sync.connect(_on_mode_sync_request)
	mode_manager.game_concluded.connect(func(): game_concluded.emit())
	
	# Wait one frame to guarantee all UI nodes are loaded before the intro fires
	await get_tree().process_frame

func _run_intro_sequence() -> void:
	if mode_manager.has_method("play_intro"):
		await mode_manager.play_intro()
		
	var ready_payload = {
		"action": "client_ready",
		"player_id": _player_id
	}
	
	if NetworkServer.server_active:
		NetworkSync.sync_data(ready_payload)
		_on_sync_data(ready_payload)
	elif NetworkClient.client_active:
		NetworkClient.sync_data(ready_payload)

func _on_mode_sync_request(payload: Dictionary) -> void:
	if NetworkServer.server_active:
		NetworkSync.sync_data(payload)
		_on_sync_data(payload)
	elif NetworkClient.client_active:
		NetworkClient.sync_data(payload)

func _on_sync_data(payload: Dictionary) -> void:
	var data = payload.get("data", payload)
	var action = data.get("action", "")
	
	# ONLY execute native logic for client_ready checks
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
		return # <-- STOPS double execution right here!
	
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
