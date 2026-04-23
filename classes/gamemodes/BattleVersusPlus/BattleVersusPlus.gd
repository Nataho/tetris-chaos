extends Control
class_name BattleVersusPlus

const FILE = preload("uid://dgaj6dtavx53s")

signal request_network_sync(payload: Dictionary)
signal game_concluded

const SLIDE_SPEED: float = 10.0
const DISTANCE: float = 0.25

var red_grid_scale: float = 0.25
var blue_grid_scale: float = 0.25

@onready var anim: AnimationPlayer = $anim
@onready var scoreboard: RichTextLabel = $versus/score
@onready var p1_name: Label = $versus/HBoxContainer/left_side/Label
@onready var p2_name: Label = $versus/HBoxContainer/right_side/Label

var active_players: Dictionary = {}
var active_boards: Dictionary = {}

var active_anchors: Dictionary = {}
var board_targets: Dictionary = {}

# Track starting targets and dead players to allow for grid reflowing
var original_targets: Dictionary = {} 
var dead_ids: Array = []              

var _player_id: int = -1
var _is_spectator: bool = false
var current_seed: int = -1
var first_to: int = 1

var red_match_score: int = 0
var blue_match_score: int = 0

var red_team_ids: Array = []
var blue_team_ids: Array = []
var alive_red: Array = []
var alive_blue: Array = []

var my_team: String = "spectator"

var game_started: bool = false
var game_finished: bool = false
var is_resetting: bool = false

# --- DYNAMIC LAYOUT NODES ---
var my_anchor: Control
var red_grid: GridContainer
var blue_grid: GridContainer

func _ready():
	print("VERSUS PLUS SPAWNED: ", get_instance_id())
	
	my_anchor = Control.new()
	my_anchor.set_anchors_preset(Control.PRESET_CENTER)
	add_child(my_anchor)
	
	red_grid = GridContainer.new()
	red_grid.columns = 3
	red_grid.set_anchors_preset(Control.PRESET_CENTER)
	red_grid.add_theme_constant_override("h_separation", 10)
	add_child(red_grid)
	
	blue_grid = GridContainer.new()
	blue_grid.columns = 3
	blue_grid.set_anchors_preset(Control.PRESET_CENTER)
	blue_grid.add_theme_constant_override("h_separation", 10)
	add_child(blue_grid)

func setup(players: Dictionary, local_id: int, spectator: bool, seed: int, settings: Dictionary) -> void:
	active_players = players
	_player_id = local_id
	_is_spectator = spectator
	current_seed = seed
	first_to = settings.get("first_to", 1)
	
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	for id in active_players:
		var team = active_players[id].get("team", "red")
		if team == "red":
			red_team_ids.append(id)
		elif team == "blue":
			blue_team_ids.append(id)
			
		if id == _player_id:
			my_team = team
			
	for id in active_players:
		_spawn_player(id)
		
	update_scoreboard()
	_update_grid_layouts()

func _spawn_player(id: int) -> void:
	var team = active_players[id].get("team", "red")
	var is_local = (id == _player_id)
	
	var target_id = -2 if team == "red" else -3
	
	var board: MultiplayerBoard
	if is_local:
		board = LocalBoard.create(id, target_id)
	else:
		board = NetworkBoard.create(id, target_id, _is_spectator)
		
	active_boards[id] = board
	
	board.add_username(active_players[id]["name"])
	
	# UNIFIED ANCHOR LOGIC
	var anchor = Control.new()
	anchor.size = Vector2.ZERO
	
	var goes_to_main = false
	if not _is_spectator and id == _player_id:
		goes_to_main = true
		
	if goes_to_main:
		board_targets[id] = my_anchor
		anchor.scale = Vector2(1.0, 1.0)
	else:
		var wrapper = Control.new()
		wrapper.custom_minimum_size = Vector2(96, 160)
		wrapper.pivot_offset = wrapper.custom_minimum_size / 2.0 
		
		var center_point = Control.new()
		center_point.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		wrapper.add_child(center_point)
		
		if team == "red":
			red_grid.add_child(wrapper)
		else:
			blue_grid.add_child(wrapper)
			
		board_targets[id] = center_point
		anchor.scale = Vector2(0.25, 0.25)
		
	anchor.add_child(board)
	board.position = Vector2.ZERO
	add_child(anchor)
	
	active_anchors[id] = anchor
	original_targets[id] = board_targets[id] # SAVE FOR ROUND RESETS!

	board.knocked_out.connect(_on_board_knocked_out)

	if board is LocalBoard:
		board.initialize(current_seed)
	else:
		board.initialize()

func _process(delta: float) -> void:
	var screen_size := get_viewport_rect().size
	var lerp_weight = 1.0 - exp(-SLIDE_SPEED * delta)
	var screen_center = screen_size * 0.5
	
	var left_pos = Vector2(screen_size.x * (0.5 - DISTANCE), screen_center.y)
	var right_pos = Vector2(screen_size.x * (0.5 + DISTANCE), screen_center.y)
	
	var grid_offset_y = 350.0 
	
	# Helper to check if a grid should be centered (1 player left) or offset (teammates/multiple)
	var is_red_solo = alive_red.size() == 1
	var is_blue_solo = alive_blue.size() == 1
	
	red_grid.size = Vector2.ZERO
	blue_grid.size = Vector2.ZERO
	
	# 1. LERP THE GRIDS & MAIN ANCHOR
	if _is_spectator:
		# Spectators see both teams centered
		red_grid.position = red_grid.position.lerp(left_pos - (red_grid.size / 2.0), lerp_weight)
		blue_grid.position = blue_grid.position.lerp(right_pos - (blue_grid.size / 2.0), lerp_weight)
	else:
		if my_team == "red":
			my_anchor.position = my_anchor.position.lerp(left_pos, lerp_weight)
			
			# Red Grid (Teammates): If solo (just me), this grid is empty/hidden, 
			# but if teammates exist, they stay offset.
			var red_t = left_pos + Vector2(-red_grid.size.x / 2.0, grid_offset_y)
			red_grid.position = red_grid.position.lerp(red_t, lerp_weight)
			
			# Blue Grid (Enemies): Center if solo, center if many (enemies always center)
			var blue_t = right_pos - (blue_grid.size / 2.0)
			blue_grid.position = blue_grid.position.lerp(blue_t, lerp_weight)
		else:
			my_anchor.position = my_anchor.position.lerp(right_pos, lerp_weight)
			
			# Blue Grid (Teammates): Offset
			var blue_t = right_pos + Vector2(-blue_grid.size.x / 2.0, grid_offset_y)
			blue_grid.position = blue_grid.position.lerp(blue_t, lerp_weight)
			
			# Red Grid (Enemies): Center
			var red_t = left_pos - (red_grid.size / 2.0)
			red_grid.position = red_grid.position.lerp(red_t, lerp_weight)

	# 2. LERP BOARDS TO TARGETS
	for id in board_targets.keys():
		if active_anchors.has(id) and not dead_ids.has(id):
			var anchor = active_anchors[id]
			var target = board_targets[id]
			
			anchor.global_position = anchor.global_position.lerp(target.global_position, lerp_weight)
			
			var team = active_players[id].get("team", "red")
			var grid_scale = red_grid_scale if team == "red" else blue_grid_scale
			
			# Final logic: 1.0 scale if it's my main anchor OR if it's the last opponent
			var target_scale_val = 1.0 if (target == my_anchor or grid_scale == 1.0) else grid_scale
			anchor.scale = anchor.scale.lerp(Vector2(target_scale_val, target_scale_val), lerp_weight)

func get_alive_team(target_team_id: int) -> Array:
	if target_team_id == -2: return alive_blue.duplicate()
	if target_team_id == -3: return alive_red.duplicate()
	return []

# --- NETWORK DATA FEED ---
func process_action(action: String, data: Dictionary) -> void:
	match action:
		"start_match":
			if game_started: return
			start_boards()
			
		"spawn_garbage":
			var attacker_id = int(data.get("attacker_id", -1))
			var target_id = int(data.get("target_id", -1))
			var amount = int(data.get("amount", 1))
			
			spawn_garbage_visual(attacker_id, target_id, amount)
			
			if active_boards.has(target_id):
				var board = active_boards[target_id]
				if board.has_method("receive_garbage"):
					board.receive_garbage({
						"player_id": attacker_id,
						"value": {"target": target_id, "amount": amount}
					})
				Events.garbage_queue_updated.emit({
					"player_id": target_id,
					"new_queue": board.garbage_queue.duplicate()
				})
				
		"next_round":
			if is_resetting: return
			is_resetting = true
			
			var next_seed = int(data.get("seed", -1))
			var scores = data.get("scores", {})
			
			red_match_score = int(scores.get("red_score", red_match_score))
			blue_match_score = int(scores.get("blue_score", blue_match_score))
					
			_perform_next_round_transition(next_seed)
			
		"match_over":
			if game_finished: return
			game_finished = true
			
			var scores = data.get("scores", {})
			red_match_score = int(scores.get("red_score", red_match_score))
			blue_match_score = int(scores.get("blue_score", blue_match_score))
					
			_perform_match_over_sequence(data.get("winner_team", ""))

func _on_board_knocked_out(node: MultiplayerBoard) -> void:
	if is_resetting or game_finished: return
	
	var loser_id = node._player_index
	if loser_id == -1: return
	
	var loser_team = active_players[loser_id].get("team", "red")
	
	# --- 1. DYNAMIC CAMERA SWAP & GRID REFLOW ---
	var is_main_view = (board_targets.get(loser_id) == my_anchor)
	var grid_wrapper_to_hide = null
	
	if loser_team == "red":
		if alive_red.has(loser_id): alive_red.erase(loser_id)
		
		if is_main_view and alive_red.size() > 0:
			var new_main_id = alive_red[0]
			var old_grid_target = board_targets[new_main_id]
			
			board_targets[new_main_id] = my_anchor    
			grid_wrapper_to_hide = old_grid_target.get_parent() 
		else:
			if board_targets.has(loser_id) and board_targets[loser_id] != my_anchor:
				grid_wrapper_to_hide = board_targets[loser_id].get_parent()
				
	elif loser_team == "blue":
		if alive_blue.has(loser_id): alive_blue.erase(loser_id)
		
		if is_main_view and alive_blue.size() > 0:
			var new_main_id = alive_blue[0]
			var old_grid_target = board_targets[new_main_id]
			
			board_targets[new_main_id] = my_anchor
			grid_wrapper_to_hide = old_grid_target.get_parent()
		else:
			if board_targets.has(loser_id) and board_targets[loser_id] != my_anchor:
				grid_wrapper_to_hide = board_targets[loser_id].get_parent()
				
	if grid_wrapper_to_hide: grid_wrapper_to_hide.hide()
	
	_update_grid_layouts()
	
	# --- 2. LET THE DEAD BOARD ANIMATE IN PLACE ---
	dead_ids.append(loser_id)
		
	# --- 3. CHECK WIN CONDITION ---
	_check_win_condition()

func _check_win_condition() -> void:
	if alive_red.size() > 0 and alive_blue.size() > 0:
		return 
		
	if not NetworkServer.server_active: return 
	
	# Server-only logic follows
	is_resetting = true # Set immediately to prevent simultaneous death bugs
	stop_boards()
	
	var winning_team = ""
	if alive_red.size() == 0:
		winning_team = "blue"
	elif alive_blue.size() == 0:
		winning_team = "red"
	
	if winning_team == "": return

	var new_red_score = red_match_score + (1 if winning_team == "red" else 0)
	var new_blue_score = blue_match_score + (1 if winning_team == "blue" else 0)
	
	var scores_payload = {
		"red_score": new_red_score,
		"blue_score": new_blue_score
	}
	
	var action_data = {
		"action": "next_round",
		"seed": randi(),
		"scores": scores_payload
	}
	
	if new_red_score >= first_to or new_blue_score >= first_to:
		action_data["action"] = "match_over"
		action_data["winner_team"] = winning_team

	# Send to clients
	request_network_sync.emit(action_data)
	
	# Unlock the state temporarily so the host can process its own action!
	is_resetting = false 
	process_action(action_data["action"], action_data)

func _perform_next_round_transition(next_seed: int) -> void:
	update_scoreboard()
	
	# Make sure the UI is ready
	anim.play("next_round_in")
	await anim.animation_finished
	
	current_seed = next_seed
	for id in active_boards:
		var board = active_boards[id]
		if board.has_method("reset"): board.reset()
		
		if board is LocalBoard:
			board.initialize(current_seed)
		else:
			board.initialize()
			
	anim.play("next_round_out")
	await anim.animation_finished
	
	# RESET FLAGS BEFORE STARTING
	is_resetting = false 
	game_started = false # Allow start_boards to set it to true
	start_boards()
			
func _perform_match_over_sequence(winner_team: String) -> void:
	update_scoreboard()
	stop_boards()
	
	print("BattlePlus| MATCH OVER! Winner: ", winner_team)
	var color_tag = "red" if winner_team == "red" else "blue"
	scoreboard.text = "[center][wave amp=50.0 freq=5.0 connected=1][color=%s]%s TEAM WINS![/color][/wave][/center]" % [color_tag, winner_team.to_upper()]
	
	Audio.play_music("victory", Audio.SOUND_END_EFFECTS.VINYL)
	await Audio.active_node.music_player_node.finished
	game_concluded.emit()

func update_scoreboard(discrete: bool = false) -> void:
	var s1 = red_match_score
	var s2 = blue_match_score
	
	var p1_text = "[color=red](%d/%d)[/color]" % [s1, first_to]
	var p2_text = "[color=blue](%d/%d)[/color]" % [s2, first_to]

	scoreboard.text = "[center]%s  FT%d  %s[/center]" % [p1_text, first_to, p2_text]

func spawn_garbage_visual(attacker_id: int, target_id: int, amount: int) -> void:
	if not active_boards.has(attacker_id) or not active_boards.has(target_id): return
	var target_node = active_boards[target_id]
	var start_pos = active_boards[attacker_id].global_position
	
	# Find out if the target board is scaled up (1v1 / main board) or small (grid)
	var c_offset = Vector2.ZERO
	
	if board_targets.has(target_id):
		var team = active_players[target_id].get("team", "red")
		var grid_scale = red_grid_scale if team == "red" else blue_grid_scale
		
		# If it's my main board, or if it's the last opponent (scale 1.0), it's full size. 
		# Otherwise, it's tucked in a grid, so use the (1, 1) offset.
		var is_full_size = (board_targets[target_id] == my_anchor or grid_scale == 1.0)
		
		if not is_full_size:
			c_offset = Vector2(1, 1)
			
	for i in range(amount): 
		var particle = AttackParticles.create(target_node, c_offset) 
		particle.modulate = Color.RED if amount < 4 else (Color.TURQUOISE if amount < 6 else Color.VIOLET)
		particle.global_position = start_pos 
		add_child(particle)

func start_boards() -> void:
	game_started = true
	game_finished = false
	
	alive_red = red_team_ids.duplicate()
	alive_blue = blue_team_ids.duplicate()
	dead_ids.clear()
	
	# Restore everyone's original targets for the new round!
	board_targets = original_targets.duplicate()
	
	for id in board_targets.keys():
		# Add the is_instance_valid check here to prevent crashes from freed nodes!
		if is_instance_valid(board_targets[id]) and board_targets[id] != my_anchor:
			board_targets[id].get_parent().show()
	
	_update_grid_layouts()
	
	for board in active_boards.values():
		if board is LocalBoard:
			board.start(3)

func stop_boards() -> void:
	for board in active_boards.values():
		if board.has_method("stop"):
			board.stop()

func play_intro() -> void:
	modulate = Color.WHITE 
	show()
	
	p1_name.text = "YOU"
	p2_name.text = "YOU"
	
	var am_i_left = (my_team == "red")
	var am_i_right = (my_team == "blue")
		
	p1_name.visible = am_i_left
	p2_name.visible = am_i_right
	
	update_scoreboard()
	
	anim.play("intro")
	Audio.active_node._trigger_fade_out(2)
	Audio.play_sound("match_intro", 0.56)
		
	await anim.animation_finished
	
	p1_name.hide()
	p2_name.hide()
	
	Audio.play_music("epic_battle")

func _update_grid_layouts() -> void:
	_apply_grid_logic(red_grid, "red")
	_apply_grid_logic(blue_grid, "blue")

func _apply_grid_logic(grid: GridContainer, team_name: String) -> void:
	var visible_count = 0
	for child in grid.get_children():
		if child.visible:
			visible_count += 1
	
	if visible_count == 0: return

	var cols: int = 1
	var wrap_size: Vector2 = Vector2(96, 160)
	var t_scale: float = 0.25
	var show_q: bool = true

	var is_my_team = (team_name == my_team)
	
	if is_my_team and not _is_spectator:
		# --- TEAMMATE LOGIC ---
		cols = 5
		t_scale = 0.25
		if visible_count <= 5:
			wrap_size = Vector2(176, 160)
			show_q = true
		else:
			wrap_size = Vector2(96, 160)
			show_q = false
	else:
		# --- OPPONENT / SPECTATOR LOGIC ---
		if visible_count == 1:
			# 1 Opponent = Boss/1v1 Layout
			cols = 1
			wrap_size = Vector2(704, 640) # Full scale width with queue!
			t_scale = 1.0
			show_q = true
		elif visible_count == 2:
			# 2 Opponents = 1 Column (Stacked vertically)
			cols = 1
			wrap_size = Vector2(458, 416) # 704 * 0.65 = 458
			t_scale = 0.65
			show_q = true
		elif visible_count <= 4:
			# 3 to 4 Opponents = 2 Columns (2x2 style)
			cols = 2
			wrap_size = Vector2(282, 256) # 704 * 0.4 = 282
			t_scale = 0.4
			show_q = true
		elif visible_count <= 18:
			# 5 to 18 Opponents = 3 Columns
			cols = 3
			wrap_size = Vector2(176, 160) # Your perfectly tested 0.25 size
			t_scale = 0.25
			show_q = true
		else:
			# > 18 Opponents = 5 Columns (Queue Hidden)
			cols = 5
			wrap_size = Vector2(96, 160) # No queue width (384 * 0.25 = 96)
			t_scale = 0.25
			show_q = false

	grid.columns = cols
	
	if team_name == "red": red_grid_scale = t_scale
	else: blue_grid_scale = t_scale

	# 1. Update Grid Cell Sizes
	for wrapper in grid.get_children():
		wrapper.custom_minimum_size = wrap_size
		wrapper.pivot_offset = wrap_size / 2.0
		
	# 2. Dynamically Show/Hide the Garbage Queue on the actual Boards
	for id in active_boards.keys():
		if active_players.has(id) and active_players[id].get("team", "red") == team_name:
			var board = active_boards[id]
			
			# Ensure your personal main board NEVER hides its queue
			if id == _player_id:
				if board.has_method("show_queue"): board.show_queue()
			else:
				if show_q:
					if board.has_method("show_queue"): board.show_queue()
				else:
					if board.has_method("hide_queue"): board.hide_queue()

func handle_player_disconnect(in_id: int) -> void:
	push_warning("BattlePlus| Received disconnect request for ID: ", in_id)
	
	# Safely find the exact dictionary key, forcing both to integers
	var id: int = -1
	for key in active_players.keys():
		if int(key) == int(in_id):
			id = key
			break
			
	if id == -1: 
		print("BattlePlus| Error: Could not find player in active_players! Keys: ", active_players.keys())
		return
	
	var is_spectator = active_players[id].get("is_spectator", false)
	if is_spectator:
		active_players.erase(id)
		print("BattlePlus| Spectator %d left." % id)
		return
		
	push_warning("BattlePlus| Player %d dropped! Cleaning up nodes..." % id)
	
	# --- 1. REMOVE FROM ALL TRACKING ARRAYS ---
	var team = active_players[id].get("team", "red")
	active_players.erase(id)
	
	if team == "red":
		if alive_red.has(id): alive_red.erase(id)
		if red_team_ids.has(id): red_team_ids.erase(id)
	else:
		if alive_blue.has(id): alive_blue.erase(id)
		if blue_team_ids.has(id): blue_team_ids.erase(id)
		
	if dead_ids.has(id): dead_ids.erase(id)
		
	# --- 2. DESTROY THE NODES SAFELY ---
	if active_boards.has(id):
		active_boards[id].queue_free()
		active_boards.erase(id)
		
	if active_anchors.has(id):
		var anchor = active_anchors[id]
		var target_wrapper = board_targets.get(id)
		
		anchor.queue_free()
		active_anchors.erase(id)
		
		# Free the grid cell so the grid automatically shrinks!
		if target_wrapper and target_wrapper != my_anchor:
			target_wrapper.get_parent().queue_free()
			
	if board_targets.has(id):
		board_targets.erase(id)
	
	if original_targets.has(id):
		original_targets.erase(id)
	
	# Force the UI to recalculate columns and sizes
	_update_grid_layouts()
	
	# --- 3. CHECK MATCH INTEGRITY (Server Only) ---
	if NetworkServer.server_active:
		var total_playing = red_team_ids.size() + blue_team_ids.size()
		
		if total_playing <= 1:
			print("BattlePlus| Only 1 or 0 players left total. Aborting match to lobby.")
			NetworkSync.sync_interaction("return_to_lobby")
		else:
			_check_win_condition()
