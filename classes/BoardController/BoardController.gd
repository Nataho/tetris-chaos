extends TileMapLayer
class_name BoardController
const grid_offset := Vector2i(1,1)

enum garbage_types{INSTANT, GRADUAL}
@export var grid_size: Vector2i = Vector2i(10,20)
@export var grid_start: Vector2i = Vector2i((grid_size.x /2)*-1,-10) 

@export var pieces_controller : PiecesController
@export var placed_tiles: TileMapLayer
@export var board_parent: Board = null 

@export var current_level:int = 1
var consecutive_clear:int = 0 #combo
var b2b_count:int = -1
const max_level:int = 100
var total_lines_cleared:int = 0
var score:int = 0
var game_over:bool = false

var is_garbage_rising: bool = false
var is_power_combo: bool = false # Tracks if the current combo is high-voltage

var garbage_type = garbage_types.GRADUAL
var delays = { 
	100: 0.1,
	75: 0.25,
	50: 0.5,
	30: 1.0,
	15: 3.0,
	1: 5.0,
}

const scores = {
	"clear": {
		1: 100, 2: 500, 3: 1000, 4: 4000
	},
	"x-spin": {
		0: 400, 
		1: 2000, 2: 4000, 3: 6000, 4: 10000
	},
	"x-spin mini": {
		0: 100, 
		1: 1000, 2: 2000, 3: 3000
	},
	"perfect clear":{
		0: 20000
	}
}

func start():
	clear()
	board_parent = get_parent()

func create_grid() -> void:
	for y in range(grid_size.y +2):
		for x in range(grid_size.x +2):
			if y == 0: continue
			set_cell(Vector2i(x,y) - grid_offset + grid_start,0,Vector2i(8,0))
	for y in range(grid_size.y+1):
		for x in range(grid_size.x):
			set_cell(Vector2i(x,y-1) + grid_start)

func is_in_bounds(coords_to_test:Vector2i) -> bool:
	if coords_to_test.x < grid_start.x || coords_to_test.x >= (grid_size.x + grid_start.x) || coords_to_test.y >= (grid_size.y + grid_start.y):
		return false
	else:
		return true

func is_pos_empty(coords_to_test:Vector2i, spin_check:bool = false) -> bool:
	if !is_in_bounds(coords_to_test) and spin_check:
		return false
	
	if placed_tiles.get_cell_source_id(coords_to_test) != -1:
		return false 
	else:
		return true 
	
func check_line_clears(is_spin:bool = false, is_mini:bool = true, piece_type:String = "T", is_all_spin:bool = false) -> void:
	var lines_to_clear:Array[int] = []
	var grid_end:Vector2i = grid_start + grid_size
	var is_b2b:bool = false
	var is_perfect_clear:bool = false
	
	var any_spin:bool = is_spin or is_all_spin 
	
	for y in range(grid_start.y, grid_end.y):
		var line_clear:bool = true
		for x in range(grid_start.x, grid_end.x):
			if placed_tiles.get_cell_source_id(Vector2i(x,y)) == -1:
				line_clear = false
		
		if line_clear:
			lines_to_clear.append(y)
	
	var cleared_count = lines_to_clear.size()
		
	if cleared_count == 3 && piece_type == "T":
		is_mini = false
	
	if cleared_count == 0:
		consecutive_clear = 0
		is_power_combo = false 
		process_garbage_queue()
	else:
		consecutive_clear += 1
		
		# Initial clear sounds
		if any_spin:
			is_b2b = true 
			Audio.play_sound("spin_clear") 
		else:
			match cleared_count:
				1, 2, 3: 
					Audio.play_sound("line_clear")
				4: 
					Audio.play_sound("quad_clear")
					is_b2b = true
	
	# Clear marked lines
	for line_y in lines_to_clear:
		for x in range(grid_start.x, grid_end.x):
			placed_tiles.erase_cell(Vector2i(x, line_y))
	
	var shift_start_y: int = grid_start.y - 20 
	var shift_map: Dictionary = {}
	for y in range(shift_start_y, grid_end.y):
		var shifts = 0
		for cleared_line in lines_to_clear:
			if cleared_line > y:
				shifts += 1
		if shifts > 0:
			shift_map[y] = shifts
	
	for y in range(grid_end.y - 1, shift_start_y - 1, -1):
		if shift_map.has(y):
			var shift_amount = shift_map[y]
			for x in range(grid_start.x, grid_end.x):
				var source_id = placed_tiles.get_cell_source_id(Vector2i(x, y))
				var atlas_coords = placed_tiles.get_cell_atlas_coords(Vector2i(x, y))
				if source_id != -1:
					placed_tiles.set_cell(Vector2i(x, y + shift_amount), source_id, atlas_coords)
					placed_tiles.erase_cell(Vector2i(x, y))
	
	if cleared_count > 0:
		is_perfect_clear = check_perfect_clear()
		if is_perfect_clear:
			Audio.play_sound("perfect_clear")
			
		if is_b2b:
			b2b_count += 1
			if b2b_count > 0:
				Audio.play_sound("b2b")
		elif !is_b2b and b2b_count > 0:
			b2b_count = -1
			Audio.play_sound("break_b2b")
		else:
			b2b_count = -1
			
		_add_cleared_lines(cleared_count)

	# --- CALCULATION BLOCK ---
	var payload_to_signal = {
		"name":"local",
		"player_index": board_parent._player_index,
		"value": {
			"lines_to_clear": cleared_count,
			"is_spin": is_spin,
			"b2b_count": b2b_count,
			"is_mini": is_mini,
			"is_all_spin": is_all_spin,
			"is_perfect_clear": is_perfect_clear,
			"combo_count": max(0, consecutive_clear - 1),
			"total_lines_cleared": total_lines_cleared,
			"current_level": current_level,
			"piece_type": piece_type
		}
	}
	
	_calculate_score(payload_to_signal)
	var garbage = calculate_garbage_sent(payload_to_signal["value"])
	
	# Update Power State before playing combo sound
	if garbage >= 6:
		is_power_combo = true

	# --- COMBO SOUNDS (Moved after Power Logic) ---
	if consecutive_clear > 1:
		var combo_sound_index: int = clampi(consecutive_clear - 1, 1, 16)
		var sound_prefix: String = "power_combo" if is_power_combo else "combo"
		Audio.play_sound(sound_prefix + str(combo_sound_index))

	if payload_to_signal["value"]["clear_score"] != 0: 
		Events.player_cleared.emit(payload_to_signal)
	
	# Cancel incoming garbage
	if garbage > 0:
		var queue = board_parent.garbage_queue
		while garbage > 0 and not queue.is_empty():
			var incoming_attack = queue[0]
			if garbage >= incoming_attack["amount"]:
				garbage -= incoming_attack["amount"]
				queue.pop_front() 
			else:
				incoming_attack["amount"] -= garbage
				garbage = 0 
		update_garbage_meter()

	# Send remaining garbage
	if garbage > 0:
		var final_amount: int = int(garbage * board_parent.handicap)
		Events.sent_garbage.emit({
			"player_id": board_parent._player_index,
			"value": {
				"amount": final_amount,
				"target": board_parent.target_player
			}
		})

func check_perfect_clear() -> bool:
	var grid_end: Vector2i = grid_start + grid_size
	for y in range(grid_start.y, grid_end.y):
		for x in range(grid_start.x, grid_end.x):
			if !is_pos_empty(Vector2i(x, y)):
				return false
	return true

func get_gravity_time(level:int) -> float:
	var l = float(level - 1)
	return pow((0.8 - (l * 0.007)), l)

func _add_cleared_lines(amount:int):
	total_lines_cleared += amount
	var new_level = 1 + (total_lines_cleared/10)
	if new_level > current_level:
		current_level = new_level
		Audio.play_sound("lvlup")
		if current_level > max_level: current_level = max_level

func process_garbage_queue():
	var garbage_queue = board_parent.garbage_queue
	if garbage_queue.is_empty(): return
	
	var lines_added_this_turn: int = 0
	while not garbage_queue.is_empty() and lines_added_this_turn < board_parent.MAX_GARBAGE_PER_DROP:
		var current_attack = garbage_queue[0]
		var space_left = board_parent.MAX_GARBAGE_PER_DROP - lines_added_this_turn
		var amount_to_take = min(current_attack["amount"], space_left)
		if amount_to_take <= 0: break
			
		match garbage_type:
			garbage_types.GRADUAL:
				await apply_garbage_gradual(amount_to_take, current_attack["gap_index"], current_attack["sender"])
			_:
				apply_garbage_instant(amount_to_take, current_attack["gap_index"], current_attack["sender"])
				current_attack["amount"] -= amount_to_take
				if current_attack["amount"] <= 0: garbage_queue.pop_front()
		lines_added_this_turn += amount_to_take
	update_garbage_meter()

func apply_garbage_instant(amount: int, gap_index: int, KO_credit:int):
	var grid_end: Vector2i = grid_start + grid_size
	var highest_y: int = grid_start.y - 20
	for y in range(highest_y, grid_end.y):
		for x in range(grid_start.x, grid_end.x):
			var source_id = placed_tiles.get_cell_source_id(Vector2i(x, y))
			if source_id != -1:
				var atlas_coords = placed_tiles.get_cell_atlas_coords(Vector2i(x, y))
				placed_tiles.set_cell(Vector2i(x, y - amount), source_id, atlas_coords)
				placed_tiles.erase_cell(Vector2i(x, y))

	var garbage_source_id: int = 0
	var garbage_atlas_coords: Vector2i = Vector2i(9, 0)
	for i in range(amount):
		var garbage_y = (grid_end.y - 1) - i
		for x in range(grid_start.x, grid_end.x):
			if (x - grid_start.x) == gap_index: continue
			placed_tiles.set_cell(Vector2i(x, garbage_y), garbage_source_id, garbage_atlas_coords)
	Audio.play_sound("garbage_rise")
	board_parent.knockout_credit = KO_credit

func apply_garbage_gradual(amount: int, gap_index: int, KO_credit:int):
	if is_garbage_rising: return
	is_garbage_rising = true
	var queue = board_parent.garbage_queue
	
	for i in range(amount):
		if queue.is_empty(): break
		_shift_everything_up_one_pixel_perfect()
		_add_single_garbage_row(gap_index)
		
		if pieces_controller and pieces_controller.cur_piece_controller:
			var piece = pieces_controller.cur_piece_controller
			var needs_push = false
			for tile in piece.tiles:
				if not is_pos_empty(tile.coordinates):
					needs_push = true
					break
			if needs_push: piece.move_piece(Vector2i.UP)
			pieces_controller.update_ghost_piece()
		
		if not queue.is_empty():
			queue[0]["amount"] -= 1
			if queue[0]["amount"] <= 0: queue.pop_front()
		
		update_garbage_meter()
		Audio.play_sound("garbage_rise")
		board_parent.knockout_credit = KO_credit
		await get_tree().create_timer(0.05).timeout
		
	is_garbage_rising = false

func _shift_everything_up_one_pixel_perfect():
	var grid_end: Vector2i = grid_start + grid_size
	var highest_y: int = grid_start.y - 20
	for y in range(highest_y, grid_end.y):
		for x in range(grid_start.x, grid_end.x):
			var source_id = placed_tiles.get_cell_source_id(Vector2i(x, y))
			if source_id != -1:
				var atlas = placed_tiles.get_cell_atlas_coords(Vector2i(x, y))
				placed_tiles.set_cell(Vector2i(x, y - 1), source_id, atlas)
				placed_tiles.erase_cell(Vector2i(x, y))

func _add_single_garbage_row(gap_index: int):
	var bottom_y = (grid_start.y + grid_size.y) - 1
	for x in range(grid_start.x, grid_start.x + grid_size.x):
		if (x - grid_start.x) != gap_index:
			placed_tiles.set_cell(Vector2i(x, bottom_y), 2, Vector2i(9, 0))

func calculate_garbage_sent(payload_values: Dictionary) -> int:
	var lines_cleared: int = payload_values["lines_to_clear"]
	var is_spin: bool = payload_values["is_spin"]
	var is_mini: bool = payload_values["is_mini"]
	var b2b_count: int = payload_values["b2b_count"]
	var combo_count: int = payload_values["combo_count"]
	var is_perfect_clear: bool = payload_values["is_perfect_clear"]
	
	if lines_cleared == 0: return 0
	if is_perfect_clear: return 10
		
	var base_damage: int = 0
	if is_spin:
		if is_mini: base_damage = 0
		else:
			match lines_cleared:
				1: base_damage = 2
				2: base_damage = 4
				3: base_damage = 6
	else:
		match lines_cleared:
			1: base_damage = 0
			2: base_damage = 1
			3: base_damage = 2
			4: base_damage = 4

	var b2b_bonus: int = 0
	if b2b_count > 0:
		if b2b_count <= 2: b2b_bonus = 1
		elif b2b_count <= 7: b2b_bonus = 2
		else: b2b_bonus = 3
		
	var attack_power: float = float(base_damage + b2b_bonus)
	var final_garbage: int = 0
	
	if attack_power > 0.0:
		var multiplier: float = 1.0 + (0.25 * combo_count)
		final_garbage = floori(attack_power * multiplier)
	else:
		if combo_count > 0:
			final_garbage = floori(log(1.0 + (1.25 * float(combo_count))))
			
	return final_garbage

func update_garbage_meter():
	var total_garbage: int = 0
	for attack in board_parent.garbage_queue:
		total_garbage += attack["amount"]
	var meter_x: int = grid_start.x - 1 
	var grid_bottom: int = grid_start.y + grid_size.y - 1 
	for y in range(grid_start.y - 20, grid_bottom + 1):
		placed_tiles.erase_cell(Vector2i(meter_x, y))
	if total_garbage == 0: return 

	var visual_lines = total_garbage % grid_size.y
	var full_wraps = total_garbage / grid_size.y
	if visual_lines == 0 and total_garbage > 0:
		visual_lines = grid_size.y
		full_wraps -= 1

	var tier_colors: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(4, 0), 
		Vector2i(5, 0), Vector2i(6, 0), Vector2i(8, 0)
	]
	var fg_tier = min(full_wraps, tier_colors.size() - 1)
	var bg_tier = min(max(0, full_wraps - 1), tier_colors.size() - 1)
	
	for i in range(grid_size.y):
		var y_pos = grid_bottom - i
		if i < visual_lines:
			placed_tiles.set_cell(Vector2i(meter_x, y_pos), 2, tier_colors[fg_tier])
		elif full_wraps > 0:
			placed_tiles.set_cell(Vector2i(meter_x, y_pos), 2, tier_colors[bg_tier])

func _calculate_score(payload_data):
	var payload = payload_data["value"]
	var cleared_lines = payload["lines_to_clear"]
	var clear_type: String = "clear"
	var final_move_score: int = 0
	
	if cleared_lines > 0 or payload.get("is_spin", false) or payload.get("is_all_spin", false): 
		if payload.get("is_spin", false) or payload.get("is_all_spin", false): 
			clear_type = "x-spin mini" if payload.get("is_mini", false) else "x-spin"
		var base_action_score = scores[clear_type][cleared_lines]
		if payload.get("is_perfect_clear", false):
			base_action_score += scores["perfect clear"][0]
		var valid_b2b_count = max(0, payload.get("b2b_count", 0))
		var valid_combo_count = max(0, payload.get("combo_count", 0))
		var b2b_multi: float = 1.0 + (float(valid_b2b_count) * 0.05)
		var combo_multi: float = 1.0 + (float(valid_combo_count) * 0.10)
		final_move_score = int(base_action_score * b2b_multi * combo_multi) * payload.get("current_level", current_level)
	
	score += final_move_score
	payload_data["value"]["current_score"] = score
	payload_data["value"]["clear_score"] = final_move_score

func add_spin_particle(center_pos:Vector2i, clockwise:bool):
	var particle := SpinParticle.create(clockwise)
	var local_pos := map_to_local(center_pos)
	particle.position = local_pos
	board_parent.add_child(particle)

func reset():
	placed_tiles.clear() 
	current_level = 1
	consecutive_clear = 0
	b2b_count = -1
	total_lines_cleared = 0
	score = 0
	game_over = false
	is_power_combo = false
