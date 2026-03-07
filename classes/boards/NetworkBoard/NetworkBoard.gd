extends MultiplayerBoard
class_name NetworkBoard

var _just_spun: bool = false

func set_board(playerid: int, target: int):
	_player_index = playerid
	target_player = target

func initialize():
	# Initialize the visual grids
	super.initialize_game_mode("online")
	# Kill the local physics so the opponent's board doesn't play itself!
	pieces_controller.set_physics_process(false)
	pieces_controller.set_process(false)

func _ready() -> void:
	super._ready()
	
	Events.received_board_data.connect(func(payload):
		if payload == null or payload.size() < 1: return
		
		var type = payload.get("update_type")
		
		# --- 1. THE GARBAGE CATCHER (Bypasses the sender check!) ---
		if type == "garbage":
			var target = payload["value"]["target"]
			
			# Is this garbage targeted at the player this NetworkBoard represents?
			if target == _player_index:
				receive_garbage(payload)
			
			#return # We are done with this packet, stop here!
			
			
		# --- 2. THE BOUNCER ---
		# For moves, locks, and spins, ONLY listen if the opponent sent them!
		if payload.get("player_id") != _player_index: return
		
		elif type == "take_garbage":
			var instructions = payload["instructions"]
			board_controller.process_garbage_queue(instructions)
		
		elif type == "sync_garbage_queue":
			# Overwrite the puppet's queue with the exact state from the local player
			garbage_queue.clear()
			garbage_queue.append_array(payload["queue"])
		
		# --- 3. NORMAL BOARD UPDATES ---
		# Route the packet to the right function
		if type == "piece_update":
			# 1. Force the exact positions so it can never desync
			set_piece_tiles(payload["piece_tiles"])
			set_ghost_tiles(payload["ghost_tiles"])
			
			# 2. Read the action to play the right feedback!
			var action = payload.get("action", "move")
			var extra_data = payload["extra_data"]
			
			if action == "rotate":
				_handle_rotate_sound()
				
			elif action == "move":
				# Safely get the dict, defaulting to a zero dict if it's somehow missing
				var dir_dict = extra_data.get("direction", {"x": 0, "y": 0})
				
				# Rebuild the Vector2i!
				var direction = Vector2i(dir_dict["x"], dir_dict["y"])
				
				#print("Rebuilt direction: ", direction)
				#print("extra_data", extra_data)
				
				if direction == Vector2i.DOWN and extra_data.get("soft_drop", false):
					Audio.play_sound("soft_drop")
					pass
				else:
					pass # Audio.play_sound("move")
			
		elif type == "lock":
			set_placed_tiles(payload["placed_tiles"])
			
			pieces_controller.clear()
			pieces_controller.ghost_tiles.clear()
			
			# --- NEW: Sync the puppet's garbage queue with the real player's queue! ---
			if payload.has("garbage_queue"):
				garbage_queue.clear()
				garbage_queue.append_array(payload["garbage_queue"])
			# --------------------------------------------------------------------------
			
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
			var center_x: int = int(payload["center_pos"]["x"])
			var center_y: int = int(payload["center_pos"]["y"])
			var center_pos := Vector2i(center_x, center_y)
			var clockwise: bool = bool(payload["clockwise"])
			
			_just_spun = true # Flag that a spin happened this exact frame!
			board_controller.add_spin_particle(center_pos, clockwise)
			Audio.play_sound("spin")
		
		elif type == "hard_drop":
			Audio.play_sound("hard_drop")
			
		elif type == "queue":
			set_queue_tiles(payload["queue"], payload.get("hold_piece"))
			
		elif type == "player_kod":
			# Just pass the internet packet straight into your existing logic!
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
