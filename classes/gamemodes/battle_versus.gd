extends Control
class_name BattleVersus

const FILE = preload("uid://bi7behrrxvr38")

signal request_network_sync(payload: Dictionary)
signal game_concluded

const SLIDE_SPEED: float = 10.0
const DISTANCE: float = 0.25

@onready var anim: AnimationPlayer = $anim
@onready var scoreboard: RichTextLabel = $versus/score
@onready var p1_name: Label = $versus/HBoxContainer/left_side/Label
@onready var p2_name: Label = $versus/HBoxContainer/right_side/Label

var active_players: Dictionary = {}
var active_boards: Dictionary = {}
var active_anchors: Dictionary = {}

var _player_id: int = -1
var p1_id: int = -1
var p2_id: int = -1
var _is_spectator: bool = false
var current_seed: int = -1

# NEW: Explicit IDs to map to the Left and Right side of the screen
var left_id: int = -1
var right_id: int = -1

var p1_anchor: Control = null # ALWAYS the Left Side
var p2_anchor: Control = null # ALWAYS the Right Side

var _match_started_flag: bool = false
var game_started: bool = false
var game_finished: bool = false
var is_resetting: bool = false
var first_to: int = 1

static func create(players: Dictionary, local_id: int, p1: int, p2: int, spectator: bool, seed: int, ft: int) -> BattleVersus:
	var scene = FILE.instantiate()
	
	if scene == null:
		push_error("CRITICAL: Failed to instantiate the BattleVersus scene. Check your UID!")
		return null
		
	var obj = scene as BattleVersus
	
	if obj == null:
		push_error("CRITICAL: The BattleVersus.tscn scene does NOT have BattleVersus.gd attached to its root node!")
		return null
		
	obj.setup(players, local_id, p1, p2, spectator, seed, ft)
	return obj

func setup(players: Dictionary, local_id: int, p1: int, p2: int, spectator: bool, seed: int, ft: int) -> void:
	active_players = players
	_player_id = local_id
	p1_id = p1
	p2_id = p2
	_is_spectator = spectator
	current_seed = seed
	first_to = ft
	
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	_spawn_player(p1_id, p1_id == _player_id)
	_spawn_player(p2_id, p2_id == _player_id)
	
	# Strict rule: P1 is ALWAYS on the left, P2 is ALWAYS on the right.
	left_id = p1_id
	right_id = p2_id
	
	p1_anchor = active_anchors[left_id]
	p2_anchor = active_anchors[right_id]
	
	var p1_board = active_boards[p1_id]
	var p2_board = active_boards[p2_id]
	
	if p1_board is LocalBoard:
		p1_board.initialize(current_seed)
	else:
		p1_board.initialize()
		
	if p2_board is LocalBoard:
		p2_board.initialize(current_seed)
	else:
		p2_board.initialize()

func _spawn_player(id: int, is_local: bool) -> void:
	var anchor: Control = Control.new()
	var board: MultiplayerBoard
	anchor.position = Vector2.ZERO
	
	var target = -1
	for key in active_players.keys():
		if key != id:
			target = key
			break
	
	if is_local:
		board = LocalBoard.create(id, target)
	else:
		board = NetworkBoard.create(id, target, _is_spectator)
	
	anchor.set_anchors_preset(Control.PRESET_CENTER)
	board.knocked_out.connect(_on_board_knocked_out)
	
	anchor.add_child(board)
	board.position = Vector2.ZERO
	add_child(anchor)
	
	active_boards[id] = board
	active_anchors[id] = anchor

func _process(delta: float) -> void:
	var screen_size := get_viewport_rect().size
	var lerp_weight = 1.0 - exp(-SLIDE_SPEED * delta)
	var screen_center = screen_size * 0.5
	
	var p1_pos = screen_center
	var p2_pos = screen_center
	var p1_mod = Color.TRANSPARENT
	var p2_mod = Color.TRANSPARENT
	
	if p1_anchor != null:
		p1_pos = Vector2(screen_size.x * (0.5 - DISTANCE), screen_center.y)
		p1_mod = Color.WHITE
	if p2_anchor != null:
		p2_pos = Vector2(screen_size.x * (0.5 + DISTANCE), screen_center.y)
		p2_mod = Color.WHITE
	
	if p1_anchor:
		p1_anchor.position = p1_anchor.position.lerp(p1_pos, lerp_weight)
		p1_anchor.modulate = p1_anchor.modulate.lerp(p1_mod, lerp_weight)
	if p2_anchor:
		p2_anchor.position = p2_anchor.position.lerp(p2_pos, lerp_weight)
		p2_anchor.modulate = p2_anchor.modulate.lerp(p2_mod, lerp_weight)

# --- NETWORK DATA FEED ---
func process_action(action: String, data: Dictionary) -> void:
	match action:
		"start_match":
			if _match_started_flag: return
			_match_started_flag = true
			start_boards()
			
		"spawn_garbage":
			var attacker_id = int(data.get("player_id", -1))
			var value_dict = data.get("value", {})
			var target_id = int(value_dict.get("target", -1))
			var amount = int(value_dict.get("amount", 1))
			
			# We removed the 'if' check so the sender sees their own attack!
			spawn_garbage_visual(attacker_id, target_id, amount)
				
		"next_round":
			var next_seed = int(data.get("seed", -1))
			var scores = data.get("scores", {})
			
			# Apply exact scores by explicit ID
			for id_str in scores.keys():
				var id = int(id_str)
				if active_boards.has(id): 
					active_boards[id].kos = int(scores[id_str])
					
			_perform_next_round_transition(next_seed)
			
		"match_over":
			var winner_id = int(data.get("winner_id", -1))
			var scores = data.get("scores", {})
			
			# Apply exact scores by explicit ID
			for id_str in scores.keys():
				var id = int(id_str)
				if active_boards.has(id): 
					active_boards[id].kos = int(scores[id_str])
					
			_perform_match_over_sequence(winner_id)

# --- STATE LOGIC ---
func _on_board_knocked_out(node: MultiplayerBoard) -> void:
	var loser_id = node._player_index
	if loser_id == -1: return
	if game_finished or is_resetting: return
	if not NetworkServer.server_active: return 
	
	is_resetting = true
	await get_tree().create_timer(1.0).timeout
	
	var winner_id = p1_id if loser_id == p2_id else p2_id
	active_boards[winner_id].kos += 1
	
	# Send the dictionary mapping actual IDs to actual scores!
	var scores_payload = {
		str(p1_id): active_boards[p1_id].kos,
		str(p2_id): active_boards[p2_id].kos
	}
	
	if active_boards[p1_id].kos >= first_to or active_boards[p2_id].kos >= first_to:
		request_network_sync.emit({
			"action": "match_over",
			"winner_id": winner_id,
			"scores": scores_payload
		})
	else:
		request_network_sync.emit({
			"action": "next_round",
			"seed": randi(),
			"scores": scores_payload
		})

func _perform_next_round_transition(next_seed: int) -> void:
	is_resetting = true
	update_scoreboard()
	
	_match_started_flag = false
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
	
	is_resetting = false
	start_boards()
			
func _perform_match_over_sequence(winner_id: int) -> void:
	game_finished = true
	update_scoreboard()
	
	var winner_name = active_players.get(winner_id, {"name": "Someone"}).get("name")
	
	stop_boards()
	
	print("Battle| MATCH OVER! Winner: ", winner_name)
	scoreboard.text = "[center][wave amp=50.0 freq=5.0 connected=1]%s WINS![/wave][/center]" % winner_name.to_upper()
	
	Audio.play_music("victory", Audio.SOUND_END_EFFECTS.VINYL)
	await Audio.music_player_node.finished
	game_concluded.emit()


# --- VISUALS AND ANIMATIONS ---
func play_intro() -> void:
	modulate = Color.WHITE 
	show()
	
	# Names now directly read from the explicit visual Left/Right IDs!
	p1_name.text = active_players.get(left_id, {"name": "Player 1"}).get("name").to_upper()
	p2_name.text = active_players.get(right_id, {"name": "Player 2"}).get("name").to_upper()
	p1_name.show()
	p2_name.show()
	
	if p1_anchor: p1_anchor.show()
	if p2_anchor: p2_anchor.show()
	
	update_scoreboard()
	
	anim.play("intro")
	if has_node("/root/Audio"):
		Audio.trigger_fade_out(2)
		Audio.play_sound("match_intro", 0.56)
		
	await anim.animation_finished
	
	p1_name.hide()
	p2_name.hide()
	
	if has_node("/root/Audio"):
		Audio.play_music("epic_battle")

func update_scoreboard(discrete: bool = false) -> void:
	# Scores now directly read from the explicit visual Left/Right IDs!
	var s1 = active_boards[left_id].kos if active_boards.has(left_id) else 0
	var s2 = active_boards[right_id].kos if active_boards.has(right_id) else 0
	
	var match_point = first_to - 1
	if (s1 >= first_to or s2 >= first_to) and not game_finished:
		game_finished = true

	var p1_text = "[color=red](%d/%d)[/color]" % [s1, first_to]
	var p2_text = "[color=blue](%d/%d)[/color]" % [s2, first_to]
	if discrete: return

	if s1 == match_point and s2 == match_point:
		p1_text = "[shake rate=20.0 level=8]%s[/shake]" % p1_text
		p2_text = "[shake rate=20.0 level=8]%s[/shake]" % p2_text
	else:
		p1_text = _apply_status_effects(p1_text, s1, s2, match_point)
		p2_text = _apply_status_effects(p2_text, s2, s1, match_point)

	scoreboard.text = "[center]%s  FT%d  %s[/center]" % [p1_text, first_to, p2_text]

func _apply_status_effects(text: String, score: int, opp_score: int, mp: int) -> String:
	var modified_text = text
	if score == mp and !game_finished:
		if game_started:
			Audio.play_sound("match_point")
		modified_text = "[bounce amp=15.0 freq=5.0]%s[/bounce]" % text
	elif score > opp_score:
		modified_text = "[wave amp=50.0 freq=5.0 connected=1]%s[/wave]" % text
	
	if score > mp and game_finished:
		modified_text = "[bounce amp=15.0 freq=5.0]%s[/bounce]" % text
	elif game_finished: 
		modified_text = "[shake rate=20.0 level=8]%s[/shake]" % text
	
	return modified_text

func spawn_garbage_visual(attacker_id: int, target_id: int, amount: int) -> void:
	if not active_boards.has(attacker_id) or not active_boards.has(target_id): return
	
	var target_node = active_boards[target_id]
	var start_pos = active_boards[attacker_id].global_position
	
	for i in range(amount): 
		var particle = AttackParticles.create(target_node) 
		if amount < 4: 
			particle.modulate = Color.RED 
		elif amount < 6: 
			particle.modulate = Color.TURQUOISE 
		elif amount < 10: 
			particle.modulate = Color.VIOLET 
		else: 
			var colors = [Color.RED, Color.GREEN, Color.ORANGE, Color.BLUE, Color.TURQUOISE, Color.MAGENTA, Color.YELLOW] 
			particle.modulate = colors.pick_random() 
			
		particle.global_position = start_pos 
		add_child(particle) 

func start_boards() -> void:
	game_started = true
	game_finished = false
	for board in active_boards.values():
		#board.start(3)
		if board is LocalBoard:
			board.start(3)

func stop_boards() -> void:
	for board in active_boards.values():
		if board.has_method("stop"):
			board.stop()
