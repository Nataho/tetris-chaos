extends Node
class_name PieceController

var rotation_index = 0
var tiles:Array[TileController]
var cur_type
var end_offset:Vector2i
var test_index:int

#enum PIECE_TYPE{O, I, S, Z, L, J, T}
enum PIECE_TYPE{Z, L, O, S, I, J, T}

func rotate_piece(clockwise: bool, shouldOffset:bool) -> void:
	var old_rotation_index = rotation_index
	rotation_index += 1 if clockwise else -1
	rotation_index = _Mod(rotation_index,4)
	
	for i in range(tiles.size()):
		tiles[i].rotate_tile(tiles[0].coordinates, clockwise)
	
	if !shouldOffset: return;
	
	var can_offset: bool = offset(old_rotation_index,rotation_index)
	
	if !can_offset:
		rotate_piece(!clockwise, false)
		
func _Mod(x: int, m: int):
	return(x % m + m) % m
	
func offset(old_rot_index: int, new_rot_index: int) -> bool:
	var offset_val1: Vector2i
	var offset_val2: Vector2ican
	var offset_val3: Vector2i
	var cur_offset_data: Dictionary
	
	if cur_type == PIECE_TYPE.O: #look for O
		cur_offset_data = PiecesController.O_OFFSET_DATA
	elif cur_type == PIECE_TYPE.I: #look for I
		cur_offset_data = PiecesController.I_OFFSET_DATA
	else: #look for JLSTZ
		cur_offset_data = PiecesController.JLSTZ_OFFSET_DATA
	
	end_offset = Vector2i.ZERO
	var move_possible: bool = false
	
	for i in range(5):
		offset_val1 = cur_offset_data[test_index][old_rot_index]
		offset_val2 = cur_offset_data[test_index][new_rot_index]
		end_offset = offset_val1 - offset_val2
	
		if (can_move_piece(end_offset)):
			move_possible = true
			break
	
	if move_possible:
		move_piece(end_offset)
	else:
		print("move impossible")
	return move_possible

func can_move_piece(movement:Vector2i) -> bool:
	for i in range(tiles.size()):
		if tiles[i].can_tile_move(movement + tiles[i].coordinates):
			return false
	
	return true

func move_piece(movement: Vector2i) -> bool:
	for i in range(tiles.size()):
		if tiles[i].can_tile_move(movement + tiles[i].coordinates):
			print("can't go there")
			if movement == Vector2i.DOWN:
				set_piece()
			return false
			
	for i in range(tiles.size()):
		tiles[i].move_tile(movement)
	return true
