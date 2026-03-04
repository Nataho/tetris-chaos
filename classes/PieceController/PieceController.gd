extends Node
class_name PieceController

signal forced_place

enum PIECE_TYPE{Z, L, O, S, I, J, T}
const random_7_bag := ["Z", "L", "O", "S", "I", "J", "T"]

#region tile positions
const i_tile_positions := [
	"----",
	"*x**",
	"----"
]
const j_tile_positions := [
	"*--",
	"*x*",
	"---"
]
const l_tile_positions := [
	"--*",
	"*x*",
	"---"
]
const s_tile_positions := [
	"-**",
	"*x-",
	"---"
]
const z_tile_positions := [
	"**-",
	"-x*",
	"---"
]
const o_tile_positions := [
	"-**",
	"-x*",
	"---"
]
const t_tile_positions := [
	"-*-",
	"*x*",
	"---"
]

const tile_positions :Array[Array]= [
	z_tile_positions,
	l_tile_positions,
	o_tile_positions,
	s_tile_positions,
	i_tile_positions,
	j_tile_positions,
	t_tile_positions,
]
#endregion

var pieces_controller: PiecesController = null
var board_controller: BoardController = null
var board_center: Vector2i
var rotation_index: int = 0
var corner_spin_tiles:int = 0
var tiles: Array[TileController]
var ghost_tiles: Array[TileController]
var piece_type: PIECE_TYPE
var piece_offset: Vector2i
var is_all_spin:bool
var is_stopped: bool = false


var current_lock_delay:float = 3.0
var max_lock_delay:float = 3.0
var move_resets_left:int = 15
var fall_time:float = 1.0
var is_on_floor:bool = false

var center_tile: TileController:
	set(value):
		center_tile = value
		print("piece center tile has been set! | ", value.coordinates)

func _init(PcC: PiecesController, BC:BoardController) -> void:
	pieces_controller = PcC
	board_controller = BC
	
	
	board_center = get_spawn_pos()
	reset_fall_time()

func _physics_process(delta: float) -> void:
			
	if board_controller.game_over or is_stopped:
		return
	# 1. Handle Gravity (Falling)
	if not is_on_floor:
		fall_time -= delta
		
		# Reset modulate to normal just in case the piece slid off a ledge
		pieces_controller.modulate = Color.WHITE 
		
		if fall_time <= 0:
			if can_move_piece(Vector2i.DOWN):
				move_piece(Vector2i.DOWN)
			reset_fall_time() # Restarts the timer based on the level formula
			
	# 2. Handle Lock Delay (Floor Time)
	else:
		# In official Tetris, lock delay is almost always a flat 0.5 seconds
		# regardless of the gravity speed.
		current_lock_delay -= delta
		
		# --- NEW DARKENING LOGIC ---
		# Get a percentage between 0.0 (locked) and 1.0 (just touched the floor)
		var lock_ratio: float = max(0.0, current_lock_delay / max_lock_delay)
		
		# Lerp smoothly between Dark Gray (0.3) and White (1.0)
		var color_val: float = lerp(0.3, 1.0, lock_ratio)
		pieces_controller.modulate = Color(color_val, color_val, color_val, 1.0)
		# ---------------------------
		
		if current_lock_delay <= 0:
			pieces_controller.modulate = Color.WHITE # Reset color before placing!
			place() 
			forced_place.emit()

## piece type must be from the enum "PIECE_TYPE"
func initialize_piece(piece_form, lock_delay = 5.0):
	current_lock_delay = lock_delay
	max_lock_delay = lock_delay
	
	if typeof(piece_form) == TYPE_STRING:
		var index := random_7_bag.find(piece_form)
		tiles = spawn_tiles(index)
		self.piece_type = index
		
	if typeof(piece_form) == TYPE_INT:
		tiles = spawn_tiles(piece_form)
		self.piece_type = piece_form
			
func spawn_tiles(piece_type:PIECE_TYPE) -> Array[TileController]:
	pieces_controller.clear()
	var spawn_tile_position = Vector2i.ZERO
	var tile_controllers: Array[TileController]
	
	if !_are_tiles_spawnable():
			board_controller.game_over = true
			Events.player_kod.emit({
				"player_id": board_controller.board_parent._player_index,
				"knockout_credit": board_controller.board_parent.knockout_credit,
				"score": board_controller.score
			})
			return []
		#return []

	for row in tile_positions[piece_type]:
		for column in row:
			var tile_coordinates:Vector2i = board_center + spawn_tile_position
			print("tile coorinates, after checking: ", tile_coordinates)
			var tile : TileController
			
			## spawning of tiles ###
			match column:
				"-": #nothing
					pass
				"*":
					pieces_controller.set_cell(tile_coordinates, 0, Vector2i(piece_type,0))
					tile = TileController.new(tile_coordinates, piece_type, pieces_controller, self)
					tile_controllers.append(tile)
					
					print("setting piece | ", spawn_tile_position)
				"x":
					pieces_controller.set_cell(tile_coordinates, 0, Vector2i(piece_type,0))
					tile = TileController.new(tile_coordinates, piece_type, pieces_controller, self)
					tile.is_center = true
					
					tile_controllers.append(tile)
					center_tile = tile # sets our center tile
					
					print("setting piece | ", spawn_tile_position)
					
			spawn_tile_position.x += 1 #add after column loop
			
		spawn_tile_position.x = 0 #reset after entire column loop
		spawn_tile_position.y += 1 #add after row loop
		if spawn_tile_position.y >= tile_positions[piece_type].size(): #stop when loop ofershots
			break
	
	# setting of relative coordinates
	for tile in tile_controllers:
		if tile == center_tile: continue
		
		#subtract to get relative coordinates
		tile.relative_coordinates = tile.coordinates - center_tile.coordinates 
		print(tile.relative_coordinates)

	return tile_controllers

func _are_tiles_spawnable() -> bool:
	var spawn_tile_position = Vector2i.ZERO
	print("checking if tile is spawnable")
	
	for row in tile_positions[piece_type]:
		for column in row:
			var tile_coordinates:Vector2i = board_center + spawn_tile_position
			
			# ONLY check for collision if this cell is an actual block!
			if column == "*" or column == "x":
				if !board_controller.is_pos_empty(tile_coordinates):
					return false
					
			spawn_tile_position.x += 1
		
		spawn_tile_position.x = 0
		spawn_tile_position.y += 1
		
	return true

func rotate_piece(is_clockwise:bool, should_offset:bool):
	if is_stopped: return
	var old_rotation_index = rotation_index
	rotation_index += 1 if is_clockwise else -1
	rotation_index = mod(rotation_index,4)
	corner_spin_tiles = 0 #reset tiles
	
	for tile:TileController in tiles:
		tile.remove_tile()
	
	for tile:TileController in tiles:
		tile.rotate_tile(center_tile.coordinates,is_clockwise)
	
	if !should_offset: return
	
	var can_offset:bool = offset(old_rotation_index, rotation_index, is_clockwise)

	if !can_offset:
		rotate_piece(!is_clockwise,false)
	pieces_controller.update_ghost_piece()
	Events.player_rotated.emit({
		"name":"local",
		"value": tiles
	})
	reset_fall_time()

func offset(old_rot_index: int, new_rot_index: int, clockwise:bool) -> bool:
	var offset_val_1: Vector2i
	var offset_val_2: Vector2i
	var end_offset: Vector2i
	
	#simulate 2 dimentional array
	#no shortcuts for 2 dimentional arrays in godot :< 
	var offset_data:Dictionary = {}
	
	match piece_type:
		PIECE_TYPE.O:
			offset_data = pieces_controller.O_OFFSET_DATA
		PIECE_TYPE.I:
			offset_data = pieces_controller.I_OFFSET_DATA
		_:
			offset_data = pieces_controller.JLSTZ_OFFSET_DATA
	
	end_offset = Vector2i.ZERO
	
	var move_possible: bool = false
	
	for i in range(5):
		for tile:TileController in tiles:
			tile.remove_tile()
		#print("offset_data1 = offset_data[%d][%d]" %[i,old_rot_index])
		#print(offset_data)
		offset_val_1 = offset_data[i][old_rot_index]
		offset_val_2 = offset_data[i][new_rot_index]
		end_offset = offset_val_1 - offset_val_2
		#print("offset1: ", offset_val_1)
		#print("offset2: ", offset_val_2)
		#print("end offset: ", end_offset)
		
		if can_move_piece(end_offset): #break loop once movement is possible
			move_possible = true
			#print("move is possible!")
			print(parse_piece_type_to_string() + " offset: ", end_offset)
			piece_offset = end_offset
			break
	
	#print("move possible: ", move_possible)
	if move_possible:
		move_piece(end_offset, true, clockwise)
	else:
		print("move impossible")
	return move_possible

func can_move_piece(movement:Vector2i) -> bool:
	for tile:TileController in tiles:
		if !tile.can_tile_move(movement + tile.coordinates):
			return false
	return true

func move_piece(movement: Vector2i, is_rotate:bool = false, clockwise:bool = false) -> bool:
	if is_stopped: return false
	
	for tile:TileController in tiles:
		tile.remove_tile()
	
	if movement == Vector2i.DOWN:
		reset_fall_time()

	
	for tile:TileController in tiles:
		if !tile.can_tile_move(movement + tile.coordinates):
			#print("can't go there")
			for _tile:TileController in tiles:
				_tile.update_position(_tile.coordinates)
				#_tile.check_spin()
			#if movement == Vector2.DOWN:
				#set_piece()
			pieces_controller.update_ghost_piece()
			Events.player_moved.emit({
				"name":"local",
				"value": tiles
			})
			#reset_fall_time()
			return false

	for tile:TileController in tiles:
		tile.move_tile(movement,is_rotate)
		pieces_controller.update_ghost_piece()
		Events.player_moved.emit({
			"name":"local",
			"value": tiles
		})
	if is_on_floor:
		reset_fall_time()
		
	if (corner_spin_tiles >= 3 or is_all_spin) and is_rotate :
		Audio.play_sound("spin")
		board_controller.add_spin_particle(center_tile.coordinates,clockwise)
	elif is_rotate:
		Audio.play_sound("rotate")
		print("playing rotate")
	return true

func drop_piece() -> void:
	while move_piece(Vector2i.DOWN): pass
	place()

func place(): #places the piece tiles on the placed_tiles_layer
	var placed_tiles_layer:TileMapLayer = pieces_controller.board_controller.placed_tiles
	for tile in tiles:
		placed_tiles_layer.set_cell(tile.coordinates, 0, Vector2i(tile.piece_type, 0))
		tile.remove_tile()
		
		#await pieces_controller.get_tree().create_timer(0.25).timeout
	
	var is_spin = false
	var is_mini = false
	if corner_spin_tiles >= 3 or is_all_spin:
		is_spin = true
	
	if (is_spin and piece_offset != Vector2i.ZERO) or is_all_spin:
		is_mini = true
	
	# Check for line clears after all tiles are placed
	pieces_controller.can_hold = true
	pieces_controller.board_controller.check_line_clears(is_spin, is_mini, parse_piece_type_to_string())
	queue_free()

func hard_soft_drop(): #instant soft drop
	while move_piece(Vector2i.DOWN): pass

func hard_move(movement: Vector2i):
	while move_piece(movement): pass
#custom modular function
func mod(x:int, m:int) -> int:
	return (x % m + m) % m

func parse_piece_type_to_string() -> String:
	match piece_type:
		PIECE_TYPE.Z: return "Z"
		PIECE_TYPE.L: return "L"
		PIECE_TYPE.O: return "O"
		PIECE_TYPE.S: return "S"
		PIECE_TYPE.I: return "I"
		PIECE_TYPE.J: return "J"
		PIECE_TYPE.T: return "T"
	
	return ""
		

func add_corner_spin_tile():
	corner_spin_tiles += 1
	print("added spin tile. current spin tiles: ", corner_spin_tiles)
	
	

func reset_fall_time():

	fall_time = board_controller.get_gravity_time(board_controller.current_level)
	is_on_floor = !can_move_piece(Vector2i.DOWN)

func can_move_to_offset(direction: Vector2i) -> bool:
	for tile: TileController in tiles:
		var target_pos = tile.coordinates + direction
		
		# If even ONE tile is blocked by a wall or another block, 
		# the whole piece cannot move in that direction.
		if !board_controller.is_pos_empty(target_pos, true):
			return false
			
	# If we checked all 4 tiles and none were blocked:
	return true

func get_spawn_pos() -> Vector2i:
	# 1. Get the dynamic left-shifted center
	# For a 10-wide board: (10 / 2) - 2 = 3
	# For a 12-wide board: (12 / 2) - 2 = 4
	var relative_x: int = (board_controller.grid_size.x / 2) - 2
	
	# 2. Set your Y spawn height 
	# (Usually 0 if your top row is 0, or grid_size.y if it grows upward)
	var relative_y: int = -1 
	
	var spawn_pos = Vector2i(relative_x, relative_y)
	
	# 3. Apply your grid_start offset!
	# Since your grid_start.x is -5, if you need the actual world/grid coordinate, 
	# you add the start offset so the piece spawns at -2 (which is visually x=3 inside the grid).
	# If your piece controller just needs the 0-9 index, don't add grid_start!
	
	var absolute_spawn_pos = board_controller.grid_start + spawn_pos
	
	return absolute_spawn_pos

#var is_frozen: bool = false

func stop():
	# 1. Stop the physics engine from ever looking at this node
	set_physics_process(false)
	set_process(false)
	
	# 2. Reset visual state
	pieces_controller.modulate = Color.WHITE
	
	# 3. Mark as frozen for any other scripts trying to access it
	is_stopped = true
