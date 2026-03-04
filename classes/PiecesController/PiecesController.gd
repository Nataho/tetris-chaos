extends TileMapLayer
class_name PiecesController

signal new_bag(bag)
signal spawned_piece(is_hold:bool)
signal hold_piece

enum PIECE_TYPE{Z, L, O, S, I, J, T}

const random_7_bag := ["Z", "L", "O", "S", "I", "J", "T"]

# Structure: { TestIndex: [Rot0, Rot1, Rot2, Rot3] }
const JLSTZ_OFFSET_DATA: Dictionary = {
	0: [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO],
	1: [Vector2i.ZERO, Vector2i(1, 0), Vector2i.ZERO, Vector2i(-1, 0)],
	2: [Vector2i.ZERO, Vector2i(1, 1), Vector2i.ZERO, Vector2i(-1, 1)],
	3: [Vector2i.ZERO, Vector2i(0, -2), Vector2i.ZERO, Vector2i(0, -2)],
	4: [Vector2i.ZERO, Vector2i(1, -2), Vector2i.ZERO, Vector2i(-1, -2)]
}
const I_OFFSET_DATA: Dictionary = {
	0: [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1)],
	1: [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, -1), Vector2i(0, -1)],
	2: [Vector2i(2, 0), Vector2i.ZERO, Vector2i(-2, -1), Vector2i(0, -1)],
	3: [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1)],
	4: [Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2)]
}
const O_OFFSET_DATA: Dictionary = {
	0: [Vector2i.ZERO, Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
	#0: [Vector2i.ZERO, Vector2i(1, 1), Vector2i(1, 1), Vector2i(1, 1)]
}

#@export var spawn_piece:PIECE_TYPE = PIECE_TYPE.I
@export var board_controller: BoardController
@export var queue_controller: QueueController
@export var ghost_tiles: TileMapLayer
@export var randomization_seed:int = -1
@export var board_parent: Board
var rng := RandomNumberGenerator.new() ## the seed on both players

var cur_piece_controller: PieceController = null
var gamepad_handler: GamepadHandler

var started:bool = false
var can_hold:bool = true
var move_direction: Vector2i = Vector2i.ZERO
var held_move_keys: Array[String] = [] # Track all currently held movement keys
var held_gamepad_buttons: Dictionary = {} # Track gamepad button states

#handling
@export var soft_drop_ms: int = 100
@export var das_ms: int = 167
@export var arr_ms: int = 33

@export var soft_drop_timer: Timer
@export var das_timer: Timer
@export var arr_timer: Timer


#stores 2 bags of 7 
var current_bag = []

var _signals_connected: bool = false # <-- Add this near your other vars

func initialize():
	rng.seed = randomization_seed
	generate_bag()
	pass

func start():
	
	#[TEST]
	#print(gamepad_handler.controllers)
	# Only set up the gamepad and timers the VERY FIRST time
	if not _signals_connected:
		gamepad_handler = GamepadHandler.new()
		_set_gamepad_signals()
		_set_handling_timers()
		_signals_connected = true # <-- Prevent future connections
	
	started = true
	
	if current_bag.size() < 14: #if current bag is less than 2 sets of pieces
		generate_bag()
	
	spawn_piece()

func _process(delta: float) -> void:
	#print("boardcontroller.current_level = ",board_controller.current_level)
	if !started: return
	gamepad_handler.handle_controller_input()
	
	if !cur_piece_controller: return
	if board_controller.game_over: return
	
# 1. READ INPUTS
	var left_held := false
	var right_held := false
	var soft_drop_held := false
	
	var is_keyboard: bool = GamepadHandler.controllers.get(-1, -100) == board_parent._player_index
	
	if board_parent.game_mode == board_parent.game_modes.VERSUS:
		# --- STRICT ISOLATION FOR MULTIPLAYER ---
		if is_keyboard:
			left_held = Input.is_action_pressed("move_left")
			right_held = Input.is_action_pressed("move_right")
			soft_drop_held = Input.is_action_pressed("soft_drop")
		else:
			left_held = held_gamepad_buttons.get("L", false)
			right_held = held_gamepad_buttons.get("R", false)
			soft_drop_held = held_gamepad_buttons.get("D", false)
	else:
		# --- RELAXED INPUT FOR SINGLE PLAYER ---
		# Let the player use the keyboard OR the gamepad seamlessly
		left_held = Input.is_action_pressed("move_left") or held_gamepad_buttons.get("L", false)
		right_held = Input.is_action_pressed("move_right") or held_gamepad_buttons.get("R", false)
		soft_drop_held = Input.is_action_pressed("soft_drop") or held_gamepad_buttons.get("D", false)
		
	# Handle movement key releases
	if not left_held and "L" in held_move_keys:
		held_move_keys.erase("L")
		if held_move_keys.is_empty():
			stop_move()
		elif "R" in held_move_keys:
			start_move_right()
	
	if not right_held and "R" in held_move_keys:
		held_move_keys.erase("R")
		if held_move_keys.is_empty():
			stop_move()
		elif "L" in held_move_keys:
			start_move_left()
	
	# Handle movement key presses
	if left_held and "L" not in held_move_keys:
		start_move_left()
	
	if right_held and "R" not in held_move_keys:
		start_move_right()
	
	# Check soft drop continuously too
	#soft_drop_held = Input.is_action_pressed("soft_drop") or held_gamepad_buttons.get("D", false)
	if soft_drop_held and soft_drop_timer.is_stopped():
		start_soft_drop()
	elif not soft_drop_held and not soft_drop_timer.is_stopped():
		stop_soft_drop()

func spawn_piece(is_hold:bool = false): 
	# 1. Safety check: Don't try to spawn pieces if we are already dead!
	if board_controller.game_over:
		return
		
	if cur_piece_controller != null and not cur_piece_controller.is_queued_for_deletion():
		cur_piece_controller.queue_free()
		
	cur_piece_controller = PieceController.new(self,board_controller)
	add_child(cur_piece_controller)
	
	# 2. Safety check: Only allow forced_place to trigger if the game is still running
	cur_piece_controller.forced_place.connect(func():
		if not board_controller.game_over:
			spawn_piece()
	)
	
	if is_hold: 
		cur_piece_controller.initialize_piece(queue_controller.hold_piece, get_lock_delay(board_controller.current_level))
		print("hold piece: ", queue_controller.hold_piece)
	else: 
		cur_piece_controller.initialize_piece(current_bag[0], get_lock_delay(board_controller.current_level))
		current_bag.remove_at(0)
	
	# ==========================================
	# THE FIX: Abort the spawn if it triggered a Game Over
	# ==========================================
	if board_controller.game_over or cur_piece_controller.tiles.is_empty():
		cur_piece_controller.queue_free()
		cur_piece_controller = null
		return # Stop reading this function so we don't cause an infinite loop!
	# ==========================================
	
	spawned_piece.emit(is_hold)
	
	if current_bag.size() < 7:
		generate_bag()
	
	update_ghost_piece()

#region bags and queue
func generate_bag():
	var bag := random_7_bag.duplicate()
	var randomized_bag = _randomize_bag(bag)
	
	current_bag.append_array(randomized_bag)
	new_bag.emit(randomized_bag)

#a custom function to randomize the bag
func _randomize_bag(bag:Array) -> Array:
	for i in range(bag.size()):
		var swap_index = rng.randi_range(0,i)
		var temp = bag[i]
		bag[i] = bag[swap_index]
		bag[swap_index] = temp
	return bag

#endregion

func _set_handling_timers():
	soft_drop_ms = GameManager.handling["SD"]
	das_ms = GameManager.handling["DAS"]
	arr_ms = GameManager.handling["ARR"]
	
	soft_drop_timer.timeout.connect(soft_drop_timeout)
	das_timer.timeout.connect(das_timeout)
	arr_timer.timeout.connect(arr_timeout)

#region input
#######################################################################################
func _set_gamepad_signals():
	gamepad_handler.gamepad_button_press.connect(gamepad_button_pressed)
	gamepad_handler.gamepad_button_released.connect(gamepad_button_released)

func gamepad_button_pressed(button:ButtonData):
	if button.player_index != board_parent._player_index and board_parent.game_mode == board_parent.game_modes.VERSUS: return
	if !cur_piece_controller or cur_piece_controller.is_queued_for_deletion(): return
	if !started: return
	
	# CRITICAL: This is what allows the piece to be HELD in _process!
	held_gamepad_buttons[button.name] = true 
	
	match button.name:
		"U": hard_drop() 
		"L": _handle_move_input("L")
		"R": _handle_move_input("R")
		"D": start_soft_drop()
		"A": rotate_left()
		"B": rotate_right()
		"LB", "RB": hold()
func gamepad_button_released(button:ButtonData):
	if button.player_index != board_parent._player_index and board_parent.game_mode == board_parent.game_modes.VERSUS: return
	if !cur_piece_controller or cur_piece_controller.is_queued_for_deletion(): return
	if !started: return
	
	# CRITICAL: This tells _process to STOP holding the piece!
	held_gamepad_buttons[button.name] = false 
	
	match button.name:
		"L": _handle_release_input("L")
		"R": _handle_release_input("R")
		"D": stop_soft_drop()

func _input(event: InputEvent) -> void:
	#if board_parent._player_index != -1: return #keyboard
	var is_keyboard: bool = GamepadHandler.controllers.get(-1, -100) == board_parent._player_index
	if board_parent.game_mode == board_parent.game_modes.VERSUS and not is_keyboard: return
	if !cur_piece_controller: return
	if board_controller.game_over: return
	if !started: return

	# MOVEMENT PRESSES
	if event.is_action_pressed("move_left"):
		_handle_move_input("L")
	elif event.is_action_pressed("move_right"):
		_handle_move_input("R")
	
	# MOVEMENT RELEASES
	if event.is_action_released("move_left"):
		_handle_release_input("L")
	elif event.is_action_released("move_right"):
		_handle_release_input("R")

	# ACTION PRESSES (Rotations/Hold)
	if event.is_action_pressed("soft_drop"): start_soft_drop()
	if event.is_action_released("soft_drop"): stop_soft_drop()
	if event.is_action_pressed("hard_drop"): hard_drop()
	if event.is_action_pressed("rotate_left"): rotate_left()
	if event.is_action_pressed("rotate_right"): rotate_right()
	if event.is_action_pressed("hold"): hold()

# Helper to keep Gamepad and Keyboard synced
func _handle_move_input(dir_key: String):
	if dir_key not in held_move_keys:
		held_move_keys.append(dir_key)
		if dir_key == "L":
			start_move_left()
		else:
			start_move_right()

func _handle_release_input(dir_key: String):
	held_move_keys.erase(dir_key)
	if held_move_keys.is_empty():
		stop_move()
	else:
		# If the other key is still held, immediately switch to it
		var remaining = held_move_keys.back()
		if remaining == "L": start_move_left()
		else: start_move_right()
		
################################################################
	
func start_move_left(): # moves the piece to the left
	
	if "L" not in held_move_keys:
		held_move_keys.append("L")
	das_timer.start(das_ms / 1000.0)
	cur_piece_controller.move_piece(Vector2i.LEFT)
	move_direction = Vector2i.LEFT

func stop_move():
	held_move_keys.clear()
	das_timer.stop()
	arr_timer.stop()

func start_move_right(): # moves the piece to the right
	if "R" not in held_move_keys:
		held_move_keys.append("R")
	das_timer.start(das_ms / 1000.0)
	cur_piece_controller.move_piece(Vector2i.RIGHT)
	move_direction = Vector2i.RIGHT
	
func das_timeout(): #DAS movement for left and right
	if !cur_piece_controller or cur_piece_controller.is_queued_for_deletion(): return
	if arr_ms == 0:
		cur_piece_controller.hard_move(move_direction)
		return
	arr_timer.start(arr_ms / 1000.0)
	cur_piece_controller.move_piece(move_direction)
	
func arr_timeout(): #ARR movement for left and right
	if !cur_piece_controller or cur_piece_controller.is_queued_for_deletion(): return
	cur_piece_controller.move_piece(move_direction)
	
	
func start_soft_drop(): # moves the piece downward
	if cur_piece_controller == null: return
	if cur_piece_controller.is_queued_for_deletion(): return
	
	if soft_drop_ms == 0: 
		cur_piece_controller.hard_soft_drop()	
		return
	soft_drop_timer.start(soft_drop_ms / 1000.0)
	cur_piece_controller.move_piece(Vector2i.DOWN)
	
func stop_soft_drop(): # moves the piece downward
	soft_drop_timer.stop()

func soft_drop_timeout():
	if !cur_piece_controller or cur_piece_controller.is_queued_for_deletion(): return
	cur_piece_controller.move_piece(Vector2i.DOWN)
	#[TEST]
	Audio.play_sound("soft_drop")

func hard_drop():
	if cur_piece_controller == null or cur_piece_controller.is_queued_for_deletion(): return
	
	# SAFETY: If garbage is still rising, wait. 
	# Otherwise, we place a piece while the board is shifting = CRASH.
	#while board_controller.is_garbage_rising:
		#await get_tree().process_frame
		
	cur_piece_controller.drop_piece()
	Events.player_placed.emit({"player_id": board_parent._player_index})
	Audio.play_sound("hard_drop")
	
	# Let the engine finish line clears before spawning next
	await get_tree().process_frame 
	spawn_piece()
	
func rotate_left(): # rotates counter_clockwise
	if cur_piece_controller == null: return
	if cur_piece_controller.is_queued_for_deletion(): return
	
	cur_piece_controller.rotate_piece(false,true)
	
func rotate_right(): # rotates clockwise
	if cur_piece_controller == null: return
	if cur_piece_controller.is_queued_for_deletion(): return
	
	cur_piece_controller.rotate_piece(true,true)

func rotate_180(): # rotates 180 #[CHECK] it's either i add this or not :v
	pass
	
func hold():
	if !cur_piece_controller: return 
	if !can_hold: return
	
	can_hold = false
	
	stop_move()
	stop_soft_drop()
	
	var type_to_hold = cur_piece_controller.piece_type
	
	if cur_piece_controller:
		# 2. Paralyze the piece! Stop its internal gravity from ticking.
		cur_piece_controller.set_physics_process(false)
		
		# 3. Tell the individual tiles to erase themselves properly
		for tile: TileController in cur_piece_controller.tiles:
			tile.remove_tile()
			
		# 4. Remove it from the tree INSTANTLY, then queue it for deletion
		remove_child(cur_piece_controller)
		cur_piece_controller.queue_free()
		cur_piece_controller = null 
		
	# 5. Wipe the layer one last time just to be absolutely sure
	clear()
	
	# 6. Pass the baton to the queue
	hold_piece.emit(type_to_hold)
	
	#[TEST]
	Audio.play_sound("hold")

#endregion

func update_ghost_piece():
	if !cur_piece_controller: return
	ghost_tiles.clear()
	
	var drop_offset: int = 0
	var hit_bottom: bool = false
	
	# Safety cap of 25 rows prevents infinite while loops
	while !hit_bottom and drop_offset < 25: 
		for tile: TileController in cur_piece_controller.tiles:
			var test_pos = tile.coordinates + Vector2i(0, drop_offset)
			if !board_controller.is_pos_empty(test_pos) or !board_controller.is_in_bounds(test_pos):
				hit_bottom = true
				break
		if !hit_bottom: drop_offset += 1
	
	for tile in cur_piece_controller.tiles:
		ghost_tiles.set_cell(tile.coordinates + Vector2i(0, drop_offset) + Vector2i.UP, 0, Vector2i(7,0))
		
func get_lock_delay(current_level: int) -> float:
	# Loop through each key (100, then 75, then 50...)
	for threshold in board_controller.delays.keys():
		# The moment we find a threshold the player has passed, use that delay!
		if current_level >= threshold:
			return board_controller.delays[threshold]
			
	# Fallback just in case something goes weird (defaults to Level 1 speed)
	return 5.0

func reset():
	started = false
	can_hold = true
	move_direction = Vector2i.ZERO
	held_move_keys.clear()
	held_gamepad_buttons.clear()
	
	# Kill ongoing movement
	stop_move()
	stop_soft_drop()
	
	# Destroy the active piece if it exists
	if cur_piece_controller != null and is_instance_valid(cur_piece_controller):
		cur_piece_controller.queue_free()
		cur_piece_controller = null
		
	clear() # Clears the active piece TileMapLayer
	ghost_tiles.clear() # Clears the ghost layer
	
	current_bag.clear() # Empty the bag so a fresh one generates

func stop():
	# 1. STOP THE GRAVITY & AUTOMATIC LOCKING
	# We stop the piece from falling on its own, but we DON'T kill the keyboard yet.
	if cur_piece_controller and is_instance_valid(cur_piece_controller):
		cur_piece_controller.stop()
	
	# 2. KILL THE HANDLING TIMERS
	# This stops DAS (fast sliding) and ARR, so the piece can't be moved anymore.
	das_timer.stop()
	arr_timer.stop()
	soft_drop_timer.stop()
	
	# 3. SET THE BARRIER
	# Your _process loop checks this. Setting it to false stops gamepad polling.
	started = false
	
	# 4. CLEAR THE BUFFERS
	held_move_keys.clear()
	held_gamepad_buttons.clear()

	print("PiecesController: Logic frozen, but waiting for final place.")
