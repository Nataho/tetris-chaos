extends Node
class_name TileController;

var coordinates: Vector2i #[CHECK]
var board: BoardController

func _init(board) -> void:
	self.board = board

func rotate_tile(origin_pos: Vector2i, clockwise:bool) -> void:
	
	var relative_pos : Vector2i = coordinates - origin_pos
	#Vector2Int[] rotMatrix = clockwise new Vector2Int[2] {new Vector2Int(0,-1), new Vector2Int(1,0)} : new Vector2Int[2] {new Vector2Int(0,1), new Vector2Int(-1,0)}'
	#[CHECK]
	var rot_matrix: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0)] if clockwise else [Vector2i(0, -1), Vector2i(-1, 0)]
	
	var new_x_pos = (rot_matrix[0].x * relative_pos.x) + (rot_matrix[1].x * relative_pos.y)
	var new_y_pos = (rot_matrix[0].y * relative_pos.x) + (rot_matrix[1].y * relative_pos.y)
	var new_pos: Vector2i = Vector2i(new_x_pos, new_y_pos)
	
	new_pos += origin_pos
	update_position(new_pos)

func move_tile(movement:Vector2i) -> void:
	var endpos: Vector2i = coordinates + movement
	update_position(endpos)


func update_position(new_position: Vector2i):
	pass
#
func can_tile_move(end_pos:Vector2i) -> bool:
	if !board.is_in_bounds(end_pos):
		return false
	if !board.is_pos_empty(end_pos):
		return false
		
	return true
