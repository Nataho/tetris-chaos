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

#We store everything mode-specific in this generic dictionary
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
		var raw_id = data.get("uid", data.get("player_id", -1))
		var p_id:int = int(raw_id)
		
		if p_id == -1: continue
		
		new_data[p_id] = {
			"name": data.get("name", "player"),
			"team": data.get("team", "red"),
			"uid": p_id,
			"is_spectator": data.get("is_spectator", false)
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
	match _game_mode:
		VERSUS:
			if versus_scene:
				mode_manager = versus_scene.instantiate()
			else:
				mode_manager = BattleVersus.FILE.instantiate() 
		VERSUS_PLUS:
			if versus_plus_scene:
				mode_manager = versus_plus_scene.instantiate()
			else:
				mode_manager = BattleVersusPlus.FILE.instantiate()
	
	if mode_manager == null:
		push_error("CRITICAL: BattleManager failed to spawn mode_manager! Did you assign the scenes in the Inspector?")
		return
		
	add_child(mode_manager)
	
	mode_manager.setup(active_players.values(), _player_id, _game_mode, _is_spectator, current_seed, match_settings)
	
	if mode_manager.has_signal("request_network_sync"):
		mode_manager.request_network_sync.connect(_on_mode_sync_request)
	if mode_manager.has_signal("game_concluded"):
		mode_manager.game_concluded.connect(func(): game_concluded.emit())
	
	await get_tree().process_frame

func _run_intro_sequence() -> void:
	if mode_manager.has_method("play_intro"):
		await mode_manager.play_intro()
		
	var ready_payload = {"action": "player_ready", "uid": _player_id, "player_id": _player_id}
	
	if NetworkSync.current_mode == NetworkSync.NetMode.ONLINE:
		NetworkSync.sync_data(ready_payload)
	elif NetworkServer.server_active:
		NetworkSync.sync_data(ready_payload)
		_on_sync_data(ready_payload) 
	elif NetworkClient.client_active:
		NetworkClient.sync_data(ready_payload)

func _on_mode_sync_request(payload: Dictionary) -> void:
	if NetworkServer.server_active:
		NetworkSync.sync_data(payload)
	elif NetworkClient.client_active:
		NetworkClient.sync_data(payload)

func _on_sync_data(payload: Dictionary) -> void:
	var data = payload.get("data", payload)
	var action = data.get("action", "")

	# --- GARBAGE DISTRIBUTOR ---
	if action == "spawn_garbage":
		if NetworkSync.current_mode == NetworkSync.NetMode.ONLINE:
			return 
		
		if NetworkServer.server_active and _game_mode == VERSUS_PLUS:
			_handle_lan_team_garbage(data)
			return

	# --- RECEIVE DISTRIBUTED GARBAGE ---
	if action == "spawn_garbage_distributed":
		data["action"] = "spawn_garbage"
		action = "spawn_garbage"
		if data.has("target_id"):
			data["target_id"] = int(data["target_id"])

	# Pass the final action to the boards
	if mode_manager and mode_manager.has_method("process_action"):
		mode_manager.process_action(action, data)

func _handle_lan_team_garbage(data: Dictionary) -> void:
	var attacker_id = data.get("attacker_id", data.get("player_id", -1))
	var value_dict = data.get("value", {})
	var target_team_id = data.get("target_id", value_dict.get("target", 0))
	var amount = int(data.get("amount", value_dict.get("amount", 0)))
	
	if target_team_id < 0: 
		var alive_targets = []
		if mode_manager and mode_manager.has_method("get_alive_team"):
			alive_targets = mode_manager.get_alive_team(target_team_id)
		
		if alive_targets.size() > 0:
			var base_amount = amount / alive_targets.size()
			var remainder = amount % alive_targets.size()
			
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
					NetworkSync.sync_data(dist_payload)
					_on_sync_data(dist_payload)

func _on_garbage_sent(payload: Dictionary) -> void:
	var sync_payload = payload.duplicate(true)
	sync_payload["action"] = "spawn_garbage"
	
	if NetworkServer.server_active:
		NetworkSync.sync_data(sync_payload) 
	elif NetworkClient.client_active:
		NetworkClient.sync_data(sync_payload)

func _on_peer_disconnected(id: int) -> void:
	if mode_manager != null and mode_manager.has_method("handle_player_disconnect"):
		mode_manager.handle_player_disconnect(id)
