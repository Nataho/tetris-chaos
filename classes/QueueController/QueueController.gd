extends TileMapLayer
class_name QueueController


enum PIECE_TYPE{Z, L, O, S, I, J, T}
const random_7_bag := ["Z", "L", "O", "S", "I", "J", "T"]

const queue_tile_0 : Vector2i = Vector2i(12,0)
const queue_tile_1 : Vector2i = Vector2i(12,4)
const queue_tile_2 : Vector2i = Vector2i(12,8)
const queue_tile_3 : Vector2i = Vector2i(12,12)
const queue_tile_4 : Vector2i = Vector2i(12,16)
const queue_tile_hold : Vector2i = Vector2i(-6,0)

const queue_tiles = {
	-1: queue_tile_hold,
	0: queue_tile_0,
	1: queue_tile_1,
	2: queue_tile_2,
	3: queue_tile_3,
	4: queue_tile_4,
}

var pieces_controller: PiecesController

var grid_start:Vector2i
var queue:Array[String]
var hold_piece:String = ""
var _signals_connected: bool = false # <-- Add this tracker at the top
#func _init(grid_start:Vector2i) -> void:
	#self.grid_start = grid_start
	#_create_tiles()


func start(grid_start:Vector2i, pieces_controller:PiecesController) -> void:
	self.grid_start = grid_start
	self.pieces_controller = pieces_controller
	_create_tiles()
	
	# Only connect these the VERY FIRST time the game boots up
	if not _signals_connected:
		self.pieces_controller.new_bag.connect(func(bag:Array):
			queue.append_array(bag)
			update_queue()
			)
			
		self.pieces_controller.spawned_piece.connect(func(is_hold: bool):
			if !is_hold:
				queue.remove_at(0)
			update_queue()
			)
			
		self.pieces_controller.hold_piece.connect(func(active_piece: int):
			if hold_piece == "":
				hold_piece = random_7_bag[active_piece]
				pieces_controller.spawn_piece(false)
				return
				
			pieces_controller.spawn_piece(true)
			hold_piece = random_7_bag[active_piece]
			update_queue()
			)
		
		_signals_connected = true # <-- Prevent future connections
	

func _create_tiles():
	for queue_tile:Vector2i in queue_tiles.values():
		for y in range(3):
			for x in range(4):
				var tile_position:Vector2i = queue_tile + Vector2i(x,y) + grid_start
				set_cell(tile_position, 0, Vector2i(10,0))
			
func update_queue():
	_create_tiles()
	for i in range(0,5):
		display_piece(i)
	
	display_piece(-1)

func display_piece(queue_index:int):
	var piece_type : int = parse_tile_to_piece_type(queue[queue_index])
	
	if queue_index == -1: 
		if hold_piece == null: return
		piece_type = parse_tile_to_piece_type(hold_piece)
		
	else: piece_type = parse_tile_to_piece_type(queue[queue_index])
	
	var spawn_tile_position = Vector2i.ZERO
	#var tile_controllers: Array[TileController]
	
	for row in PieceController.tile_positions[piece_type]:
		for column in row:
			var tile_position:Vector2i = grid_start + queue_tiles[queue_index] + spawn_tile_position
			match column:
				"-":
					pass
				"*","x":
					if piece_type == -1:
						set_cell(tile_position, 0, Vector2i(10,0))
						
					else: 
						var hold_atlas_index: = piece_type
						if !pieces_controller.can_hold && queue_tiles[queue_index] == queue_tile_hold: hold_atlas_index = 8
						set_cell(tile_position, 0, Vector2i(hold_atlas_index,0))
			spawn_tile_position.x += 1
			#await get_tree().create_timer(0.01).timeout
		
		spawn_tile_position.x = 0
		spawn_tile_position.y += 1
		if spawn_tile_position.y >= PieceController.tile_positions[piece_type].size(): #stop when loop ofershots
			break
			

func parse_tile_to_piece_type(piece_form:String) -> int:
	return random_7_bag.find(piece_form)
	##tiles = spawn_tiles(index)
	#self.piece_type = index
	#return

func reset():
	queue.clear()
	hold_piece = ""
	clear() # Clears the actual visual tiles from the layer
	_create_tiles() # Redraws the empty background boxes for the queue
