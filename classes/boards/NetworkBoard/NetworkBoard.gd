extends MultiplayerBoard
class_name NetworkBoard
const FILE = preload("uid://d2l8ojou1pilf")

var _just_spun: bool = false
var _is_spectator: bool = false

static func create(id: int, target: int, is_spectator:bool) -> NetworkBoard:
	var inst:NetworkBoard = FILE.instantiate()
	inst._player_index = id
	inst.target_player = target
	inst._is_spectator = is_spectator
	return inst

func set_board(playerid: int, target: int):
	_player_index = playerid
	target_player = target

func initialize(seed_val: int = -1):
	super.initialize_game_mode("online", seed_val) # <--- Pass the seed here!
	
	# --- NEW FIX: Wipe ghost garbage from the previous round! ---
	garbage_queue.clear()
	Events.garbage_queue_updated.emit({
		"player_id": _player_index,
		"new_queue": garbage_queue
	})
	
	# Kill the local physics so the opponent's board doesn't play itself!
	pieces_controller.set_physics_process(false)
	pieces_controller.set_process(false)

func _ready() -> void:
	super._ready()
	
	Events.received_board_data.connect(func(payload):
		if payload == null or payload.size() < 1: return
		
		var type = payload.get("update_type")
		
		# --- 1. THE GARBAGE CATCHER (Re-activated) ---
		# This ensures the puppet board actually ADDS the garbage to its queue
		if type == "garbage" and _is_spectator:
			var target = payload["value"]["target"]
			if target == _player_index:
				# Check if this board is already handling this in the parent.
				# If your puppet is getting 2x, try commenting out this call
				# to see if the parent class is already adding it to the queue.
				receive_garbage(payload)
				
				Events.garbage_queue_updated.emit({
					"player_id": _player_index,
					"new_queue": garbage_queue.duplicate()
				})
			return
			
		# --- 2. THE BOUNCER ---
		if payload.get("player_id") != _player_index: return
		
		elif type == "take_garbage":
			var instructions = payload["instructions"]
			
			# We keep the BoardController as the boss here. 
			# It handles the subtraction logic internally.
			board_controller.process_garbage_queue(instructions)
			
			# We sync the UI meter to match the controller's new state
			Events.garbage_queue_updated.emit({
				"player_id": _player_index,
				"new_queue": garbage_queue.duplicate()
			})
		
		elif type == "sync_garbage_queue":
			garbage_queue.clear()
			garbage_queue.append_array(payload["queue"])
			
			Events.garbage_queue_updated.emit({
				"player_id": _player_index,
				"new_queue": garbage_queue.duplicate()
			})
		
		# --- 3. NORMAL BOARD UPDATES ---
		if type == "piece_update":
			set_piece_tiles(payload["piece_tiles"])
			set_ghost_tiles(payload["ghost_tiles"])
			
		elif type == "lock":
			set_placed_tiles(payload["placed_tiles"])
			pieces_controller.clear()
			
			# We force a hard-sync on every lock to kill any drift
			if payload.has("garbage_queue"):
				garbage_queue.clear()
				garbage_queue.append_array(payload["garbage_queue"])
			
			var event_data = payload.get("event_data")
			if event_data != null and typeof(event_data) == TYPE_DICTIONARY:
				var clear_info: Dictionary = event_data.get("value", event_data)
				
				var lines = int(clear_info.get("lines_to_clear", 0))
				var is_spin = bool(clear_info.get("is_spin", false))
				var is_all_spin = bool(clear_info.get("is_all_spin", false))
				
				if lines > 0 or is_spin or is_all_spin:
					if lines > 0:
						board_controller.play_network_clear_animation(clear_info)
					
					if lines > 0 or is_spin or is_all_spin:
						event_data["player_index"] = _player_index 
						display_line_clear_message(event_data)
		
		elif type == "spin":
			var center_pos := Vector2i(int(payload["center_pos"]["x"]), int(payload["center_pos"]["y"]))
			var clockwise: bool = bool(payload["clockwise"])
			_just_spun = true
			board_controller.add_spin_particle(center_pos, clockwise)
			Audio.play_sound("spin")
		
		elif type == "hard_drop":
			Audio.play_sound("hard_drop")
			
		elif type == "queue":
			set_queue_tiles(payload["queue"], payload.get("hold_piece"))
			
		elif type == "player_kod":
			_check_ko(payload)
	)

func set_piece_tiles(data: Array):
	pieces_controller.clear()
	for tile_data in data:
		pieces_controller.set_cell(Vector2i(tile_data["pos_x"], tile_data["pos_y"]), 0, Vector2i(tile_data["type"], 0))

func set_ghost_tiles(data: Array):
	var ghost_tiles = pieces_controller.ghost_tiles
	ghost_tiles.clear()
	for tile_data in data:
		ghost_tiles.set_cell(Vector2i(tile_data["pos_x"], tile_data["pos_y"]), 0, Vector2i(7, 0))

func set_placed_tiles(data: Array):
	var placed_tiles = board_controller.placed_tiles
	placed_tiles.clear() # NOW this heavy operation only happens when a piece locks!
	for tile_data in data:
		var atlas_id:int = 0
		if tile_data["type"] == 9: atlas_id = 2
		placed_tiles.set_cell(Vector2i(int(tile_data["pos_x"]), int(tile_data["pos_y"])), atlas_id, Vector2i(int(tile_data["type"]), 0))

func set_queue_tiles(data: Array, hold_piece):
	queue_controller.queue.clear()
	queue_controller.queue.append_array(data)
	if hold_piece != null:
		queue_controller.hold_piece = hold_piece
	queue_controller.update_queue()


func _handle_rotate_sound() -> void:
	# Wait until the absolute end of the current frame
	await get_tree().process_frame
	
	# If a spin packet didn't also arrive and flip this to true, play the normal sound
	if not _just_spun:
		Audio.play_sound("rotate")
		
	# Reset the flag for the next time the player rotates
	_just_spun = false
