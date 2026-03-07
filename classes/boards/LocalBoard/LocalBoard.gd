extends MultiplayerBoard
class_name LocalBoard
const FILE = preload("uid://c2rodumqoa3fe")
func setup_client():
	_player_index = 2
	target_player = 1
	print("client board set")

func setup_server():
	_player_index = 1
	target_player = 2
	print("server board set")

static func create(id: int, target: int) -> LocalBoard:
	var inst:LocalBoard = FILE.instantiate()
	inst._player_index = id
	inst.target_player = target
	return inst

func initialize(seed_val: int = -1):
	super.initialize_game_mode("online", seed_val)
	if NetworkClient.client_active: setup_client()
	if NetworkServer.server_active: setup_server()
	_connect_signals()

func _connect_signals():
	# CHEAP: Just the piece moving (High frequency)
	Events.player_moved.connect(_on_player_moved)
	Events.player_rotated.connect(_on_player_rotated)
	
	# HEAVY: The piece locked or cleared lines (Low frequency)
	Events.player_placed.connect(_send_board_correction)
	Events.player_cleared.connect(_send_board_correction)
	
	# QUEUE: Piece spawned (Low frequency)
	Events.player_spawned_piece.connect(func(_is_hold): 
		_send_queue_data.call_deferred()
		_send_movement_delta.call_deferred()
		)
		
	Events.player_spun.connect(_send_spin_data)
	Events.player_hard_dropped.connect(_send_hard_drop_data)
	Events.sent_garbage.connect(_on_local_garbage_sent)
	Events.player_took_garbage.connect(_send_garbage_taken)
	Events.garbage_queue_updated.connect(_on_garbage_queue_updated)
	Events.received_board_data.connect(_on_network_data_received)
	
	Events.player_kod.connect(_send_ko_data)
	
# --- Packet Generators ---

func _on_local_garbage_sent(payload: Dictionary) -> void:
	# Only send it to the network if WE generated it
	if payload.get("player_id") == _player_index:
		var network_packet = {
			"update_type": "garbage",
			"player_id": _player_index,
			"value": payload["value"]
		}
		_dispatch_to_network(network_packet)

func _send_garbage_taken(payload: Dictionary) -> void:
	if payload.get("player_id") == _player_index:
		var data = {
			"update_type": "take_garbage",
			"instructions": payload["instructions"] # Sending the whole batch!
		}
		_dispatch_to_network(data)

func _on_garbage_queue_updated(payload: Dictionary) -> void:
	if payload.get("player_id") == _player_index:
		var data = {
			"update_type": "sync_garbage_queue",
			"queue": payload["new_queue"]
		}
		_dispatch_to_network(data)

func _on_network_data_received(payload: Dictionary) -> void:
	if payload == null or payload.size() < 1: return
	
	var type = payload.get("update_type")
	
	# We ONLY care about incoming garbage right now
	if type == "garbage":
		var target = payload["value"]["target"]
		
		# Is the internet trying to attack ME?
		if target == _player_index:
			# Pass it directly into the Board.gd function you already wrote!
			receive_garbage(payload)

func _send_hard_drop_data(payload: Dictionary) -> void:
	if payload.get("player_id") == _player_index:
		var data = {
			"update_type": "hard_drop"
		}
		_dispatch_to_network(data)

func _on_player_moved(payload: Dictionary = {}) -> void:
	var direction = payload.get("direction", Vector2i.ZERO)
	
	# Break it down into primitive numbers so JSON/Network doesn't delete it!
	var safe_direction = {"x": direction.x, "y": direction.y}
	
	_send_movement_delta("move", {
		"direction": safe_direction,
		"soft_drop": payload.get("soft_drop", false)
		
		})

func _on_player_rotated(payload: Dictionary = {}) -> void:
	# Extract the clockwise bool from the dictionary!
	var clockwise = payload.get("clockwise", true)
	_send_movement_delta("rotate", {"clockwise": clockwise})


func _send_spin_data(payload: Dictionary) -> void:
	# Make sure we only broadcast OUR player's spins!
	if payload.get("player_id") == _player_index:
		
		# Package the data for the network
		var data = {
			"update_type": "spin", # <--- Fixed to match your architecture!
			"center_pos": payload["center_pos"],
			"clockwise": payload["clockwise"]
		}
		
		_dispatch_to_network(data)

func _send_movement_delta(action_type: String = "move", extra_data: Dictionary = {}):
	var data = {
		"update_type": "piece_update", # Changed from "move" to be more generic
		"action": action_type,         # "move" or "rotate"
		"extra_data": extra_data,      # Contains direction or clockwise bool
		"piece_tiles": pieces_controller.cur_piece_controller.get_tile_data(),
		"ghost_tiles": pieces_controller.get_ghost_data()
	}
	_dispatch_to_network(data)

func _send_board_correction(_payload = null):
	var data = {
		"update_type": "lock",
		"placed_tiles": board_controller.get_placed_tiles_data(),
		"event_data": _payload,
		# NEW: Send our actual garbage queue state to the opponent!
		"garbage_queue": garbage_queue 
	}
	_dispatch_to_network(data)

func _send_queue_data():
	var data = {
		"update_type": "queue",
		"queue": queue_controller.queue,
		"hold_piece": queue_controller.hold_piece
	}
	_dispatch_to_network(data)

func _send_ko_data(payload: Dictionary) -> void:
	# Only broadcast if WE died
	if payload.get("player_id") == _player_index:
		var data = {
			"update_type": "player_kod",
			"player_id": payload["player_id"],
			"knockout_credit": payload.get("knockout_credit", -1),
			"score": payload.get("score", 0)
		}
		_dispatch_to_network(data)

# --- Dispatcher ---
func _dispatch_to_network(data: Dictionary):
	data["player_id"] = _player_index
	
	if NetworkClient.client_active:
		NetworkClient.send_signal("send_board_data", data)
	elif NetworkServer.server_active and NetworkServer.active_players.size() > 0:
		NetworkServer.send_to_client(NetworkServer.active_players[0]["socket"], "send_board_data", data)
