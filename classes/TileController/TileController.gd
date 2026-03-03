#extends Node
class_name TileController

enum PIECE_TYPE{Z, L, O, S, I, J, T}
const cat_talk:bool = false
const cw_matrix: Array[Vector2i] = [
	Vector2i(0,-1), 
	Vector2i(1,0)
]

const ccw_matrix: Array[Vector2i] = [
	Vector2i(0,1),
	Vector2i(-1,0)
]

var pieces_controller: PiecesController
var piece_controller: PieceController

var coordinates: Vector2i = Vector2i.ZERO
var relative_coordinates: Vector2i = Vector2i.ZERO
var piece_type:PIECE_TYPE
var is_center:bool = false:
	set(value):
		is_center = value
		relative_coordinates = Vector2i.ZERO
		print("set tile ", coordinates, " as the relative center")

func _init(coordinates:Vector2i, piece_type:int, pieces_controller: PiecesController, piece_controller: PieceController) -> void:
	self.coordinates = coordinates
	self.piece_type = piece_type
	self.pieces_controller = pieces_controller
	self.piece_controller = piece_controller
#	
func update_position(new_pos:Vector2i):
	var old_pos:Vector2i = coordinates
	coordinates = new_pos
	#pieces_controller.set_cell(old_pos)
	pieces_controller.set_cell(new_pos, 0, Vector2i(piece_type,0)) # set new tile
	#pieces_controller.update_ghost_piece()

func remove_tile():
	pieces_controller.set_cell(coordinates) #clear tile

#based on
# Vector2Int[] rotMatrix = clockwise ? new Vector2Int[2] { new Vector2Int(0, -1), new Vector2Int(1, 0) }
	#								 : new Vector2Int[2] { new Vector2Int(0, 1), new Vector2Int(-1, 0) };
func rotate_tile(origin_pos:Vector2i, clockwise: bool):
	
	relative_coordinates = coordinates - origin_pos
	var rot_matrix:Array[Vector2i] = cw_matrix if clockwise else ccw_matrix
	var new_x_pos:int = (rot_matrix[0].x * relative_coordinates.x) + (rot_matrix[0].y * relative_coordinates.y)
	var new_y_pos:int = (rot_matrix[1].x * relative_coordinates.x) + (rot_matrix[1].y * relative_coordinates.y)
	var new_coordinates := Vector2i(new_x_pos, new_y_pos)
	
	#print("from ", relative_coordinates, " to ", new_coordinates)
	
	
	update_position(new_coordinates + origin_pos)
	
	#check_spin()
	#update_position(new_coordinates)
	
	#print(relative_coordinates)
	if cat_talk: print("i am myellow") #coded by myellow

func move_tile(movement: Vector2i, is_rotate:bool = false):
	var end_pos: Vector2i = coordinates + movement
	update_position(end_pos)
	
	if is_rotate:
		check_spin()

func can_tile_move(end_pos:Vector2i) -> bool: #[CHECK] needs to be updated after sucessful rotation
	if !pieces_controller.board_controller.is_in_bounds(end_pos):
		return false

	if !pieces_controller.board_controller.is_pos_empty(end_pos):
		return false
	
	return true

func check_spin():
	var is_t_piece: bool = (piece_controller.piece_type == piece_controller.PIECE_TYPE.T)
	
	# 1. --- ALL-SPIN LOGIC (Non-T Pieces) ---
	if not is_t_piece:
		if self == piece_controller.tiles[piece_controller.tiles.size() - 1]:
			# FIX: Directly set the boolean. This forces it to turn OFF 
			# if the piece is rotated into a spot where it can move!
			piece_controller.is_all_spin = is_piece_immobile()
			
	# 2. --- EARLY RETURNS FOR T-SPIN LOGIC ---
	if is_center: return
	if self == piece_controller.tiles[0] and piece_type == PIECE_TYPE.T: 
		return
		
	# 3. --- T-SPIN LOGIC (Your Original Reference) ---
	if is_t_piece:
		var is_even_rotation: bool = (piece_controller.rotation_index % 2 == 0)
		
		# Condition 1: T-Piece Even Rotation
		if is_even_rotation:
			if !pieces_controller.board_controller.is_pos_empty(coordinates + Vector2i.UP, true):
				piece_controller.add_corner_spin_tile()
			if !pieces_controller.board_controller.is_pos_empty(coordinates + Vector2i.DOWN, true):
				piece_controller.add_corner_spin_tile()
		# Condition 2: T-Piece Odd Rotation
		else:
			if !pieces_controller.board_controller.is_pos_empty(coordinates + Vector2i.LEFT, true):
				piece_controller.add_corner_spin_tile()
			if !pieces_controller.board_controller.is_pos_empty(coordinates + Vector2i.RIGHT, true):
				piece_controller.add_corner_spin_tile()

func is_piece_immobile() -> bool:
	# Checks all 4 directions. If ANY direction is free, return false.
	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for dir in directions:
		if piece_controller.can_move_to_offset(dir):
			return false
	return true
