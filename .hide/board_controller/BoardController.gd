extends TileMapLayer
class_name BoardController

@export var grid_size:Vector2i = Vector2i(10,20)
@export var grid_start: Vector2i = Vector2i(21,4) #(0,0)
@export var piece_layer: TileMapLayer
const grid_offset := Vector2i(1,1)

var is_sacrificing:bool = false

func start():
	create_grid()
	#await get_tree().create_timer(1).timeout
	is_pos_empty(Vector2i(21,4))

func create_grid() -> void:
	for y in range(grid_size.y +2):
		for x in range(grid_size.x +2):
			set_cell(Vector2i(x,y) - grid_offset + grid_start,0,Vector2i(8,0))
	#grid
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			set_cell(Vector2i(x,y) + grid_start, 0, Vector2i(10,0))
	

func is_in_bounds(coords_to_test:Vector2i) -> bool:
	if coords_to_test.x < grid_start.x || coords_to_test.x >= (grid_size.x + grid_start.x) || coords_to_test.y >= (grid_size.y + grid_start.y):
		return true
	else:
		return false

func is_pos_empty(coords_to_test:Vector2i) -> bool:
	#if coords_to_test.y <= grid_start.y:
		#return true
	if(piece_layer.get_cell_source_id(coords_to_test) != -1):
		return false #found a tile
	else:
		return true #didn't found a tile

#for pieces
func occupy_pos(coords:Vector2i, tilecontroller:TileController):
	piece_layer.set_cell(coords)
