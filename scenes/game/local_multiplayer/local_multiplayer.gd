extends Control

# --- Constants ---
const SLIDE_SPEED: float = 10.0
const DISTANCE: float = 0.25

# --- Exports ---
@export_range(1, 10, 1) var first_to: int = 5

# --- Onready Nodes ---
@onready var anim: AnimationPlayer = $anim
@onready var p1_anchor: Control = $p1_anchor
@onready var p2_anchor: Control = $p2_anchor
@onready var p1_board: MultiplayerBoard = $p1_anchor/board
@onready var p2_board: MultiplayerBoard = $p2_anchor/board
@onready var score_label: RichTextLabel = $score

@onready var rematch_menu_left: Control = $halves/left_half/match
@onready var rematch_menu_right: Control = $halves/right_half/match

@onready var boards: Array[MultiplayerBoard] = [p1_board, p2_board]

var is_paused: bool = false
# --- State Variables ---
var gamepad_handler :GamepadHandler
var next_player_index: int = 1
var game_started: bool = false
var game_finished: bool = false

var p1_active: bool = false
var p2_active: bool = false

var p1_display_text: String = "(PRESS [img=64]uid://bmnsg3vh6320g[/img] OR [img=64]uid://6ckyl4ggwwrt[/img])"
var p2_display_text: String = "(PRESS [img=64]uid://bmnsg3vh6320g[/img] OR [img=64]uid://6ckyl4ggwwrt[/img])"

# --- Lifecycle ---

func _ready() -> void:
	gamepad_handler = GamepadHandler.new(true)
	_connect_signals()
	update_scoreboard()
	_initialize_boards()

func _process(delta: float) -> void:
	gamepad_handler.handle_controller_input()
	handle_ui_animations(delta)

func _input(event: InputEvent) -> void:
	# Only process keyboard here to avoid double-inputs from GamepadHandler polling
	if not event is InputEventKey:
		return
	
	if event.is_action_pressed("pause"):
		if game_started:
			var current_p_index = gamepad_handler.controllers.get(-1, -1)
			_button_input(ButtonData.new("START", current_p_index, 1, true))
		else:
			get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	
	if event.is_action_pressed("ready") and !game_started:
		var current_p_index = gamepad_handler.controllers.get(-1, -1)
		_button_input(ButtonData.new("START", current_p_index, -1, true))
	elif event.is_action_pressed("ui_up"):
		_button_input(ButtonData.new("U", -1, -1, true))
	elif event.is_action_pressed("ui_down"):
		_button_input(ButtonData.new("D", -1, -1, true))

# --- Core Game Logic ---

func _button_input(button: ButtonData) -> void:
	if is_paused: return
	
	var device_id = button.device_index
	var controllers = gamepad_handler.controllers
	var is_joined = controllers.has(device_id)

	# 1. FT Adjustment Logic
	if button.name in ["U", "D"]:
		# Must be keyboard or a joined controller, and game must not have started
		if not (device_id == -1 or is_joined) or game_started:
			return
		
		# Prevent change if someone is ready
		if not (p1_board.player_ready or p2_board.player_ready):
			first_to = clampi(first_to + (1 if button.name == "U" else -1), 1, 10)
			update_scoreboard()
		return

	# 2. START / READY Logic
	if button.name != "START":
		return

	# BLOCK TOGGLE IF GAME IS ACTIVE
	# This prevents players from un-readying while the game is running
	if game_started:
		trigger_pause()
		return

	if not is_joined:
		_handle_player_joining(button)
	else:
		_toggle_player_ready(controllers[device_id])


func _initialize_boards() -> void:
	var seed_val = randi()
	for board in boards:
		board.initialize_game_mode("versus", seed_val)

func process_next_round(_board: MultiplayerBoard) -> void:
	await get_tree().process_frame
	update_scoreboard(true)
	
	if game_finished:
		return 

	_reset_players()

func _perform_transition(reset_scores: bool = false, start_game: bool = true) -> void:
	await get_tree().create_timer(1).timeout
	anim.play("next_round_in")
	await anim.animation_finished
	rematch_menu_left.hide()
	rematch_menu_right.hide()
	
	game_finished = false
	
	var new_seed = randi()
	for board in boards:
		if reset_scores: 
			board.kos = 0
		
		board.initialize_game_mode("versus", new_seed)
		await board.reset() 
	
	update_scoreboard()
	
	anim.play("next_round_out")
	await anim.animation_finished
	
	# FIX: Only set game_started to true if we are actually starting the countdown
	if start_game:
		game_started = true
		for board: MultiplayerBoard in boards:
			board.start(3)
	else:
		game_started = false # Ensure it's false on a hard reset

func _reset_players() -> void:
	if game_finished: return 
	await _perform_transition(false)

func _hard_reset() -> void:
	game_started = false
	game_finished = false
	for board: MultiplayerBoard in boards:
		board.player_ready = false
		# Reset the visual labels too
		if board == p1_board: $p1_anchor/name.text = p1_display_text
		if board == p2_board: $p2_anchor/name.text = p2_display_text
		
	await _perform_transition(true, false)

func check_start_condition() -> void:
	if p1_active and p2_active:
		if p1_board.player_ready and p2_board.player_ready:
			p1_board.player_ready = false
			p2_board.player_ready = false
			
			
			await _reset_players()
			Audio.play_music("epic_battle")
			
			#Audio.play_music("pro_battle")
			
			#Audio.play_loop()
			$p1_anchor/name.text = p1_display_text
			$p2_anchor/name.text = p2_display_text
			

# --- Scoring and UI Logic ---

func update_scoreboard(discrete: bool = false) -> void:
	var p1_score = boards[0].kos
	var p2_score = boards[1].kos
	var match_point = first_to - 1
	
	if (p1_score >= first_to or p2_score >= first_to) and not game_finished:
		game_finished = true
		_handle_match_end(p1_score >= first_to)
	
	
	var p1_text = "[color=red](%d/%d)[/color]" % [p1_score, first_to]
	var p2_text = "[color=blue](%d/%d)[/color]" % [p2_score, first_to]
	if discrete: return

	if p1_score == match_point and p2_score == match_point:
		p1_text = "[shake rate=20.0 level=8]%s[/shake]" % p1_text
		p2_text = "[shake rate=20.0 level=8]%s[/shake]" % p2_text
	else:
		p1_text = apply_status_effects(p1_text, p1_score, p2_score, match_point)
		p2_text = apply_status_effects(p2_text, p2_score, p1_score, match_point)

	score_label.text = "[center]%s  FT%d  %s[/center]" % [p1_text, first_to, p2_text]

func apply_status_effects(text: String, score: int, opp_score: int, mp: int) -> String:
	
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

func handle_ui_animations(delta: float) -> void:
	var screen_size := get_viewport_rect().size
	var lerp_weight = 1.0 - exp(-SLIDE_SPEED * delta)
	var screen_center = screen_size * 0.5
	
	var p1_pos = screen_center
	var p2_pos = screen_center
	var p1_mod = Color.TRANSPARENT
	var p2_mod = Color.TRANSPARENT
	
	if p1_active:
		p1_pos = Vector2(screen_size.x * (0.5 - DISTANCE), screen_center.y)
		p1_mod = Color.WHITE
	if p2_active:
		p2_pos = Vector2(screen_size.x * (0.5 + DISTANCE), screen_center.y)
		p2_mod = Color.WHITE
	
	p1_anchor.position = p1_anchor.position.lerp(p1_pos, lerp_weight)
	p2_anchor.position = p2_anchor.position.lerp(p2_pos, lerp_weight)
	p1_anchor.modulate = p1_anchor.modulate.lerp(p1_mod, lerp_weight)
	p2_anchor.modulate = p2_anchor.modulate.lerp(p2_mod, lerp_weight)

# --- Signal and Event Handling ---

func _handle_match_end(p1_won: bool) -> void:
	_play_victory_sequence()
	Audio.play_music("victory", Audio.SOUND_END_EFFECTS.VINYL)
	
	await Audio.music_player_node.finished
	Audio.play_music("main_menu")
	
	if game_finished:
		if p1_won: rematch_menu_right.show() 
		else: rematch_menu_left.show()

func _play_victory_sequence() -> void:
	update_scoreboard()
	for board in boards:
		board.stop()

func _connect_signals() -> void:
	gamepad_handler.gamepad_button_press.connect(_button_input)
	gamepad_handler.controller_connected.connect(_controller_connected)
	gamepad_handler.player_disconnected.connect(_player_disconnected)
	Events.sent_garbage.connect(_on_garbage_sent)
	
	$halves/left_half/match/VBoxContainer/rematch.pressed.connect(func(): _hard_reset())
	$halves/right_half/match/VBoxContainer/rematch.pressed.connect(func(): _hard_reset())
	$halves/left_half/match/VBoxContainer/exit.pressed.connect(func(): exit())
	$halves/right_half/match/VBoxContainer/exit.pressed.connect(func(): exit())

func exit():
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	pass

func _toggle_player_ready(p_index: int) -> void:
	var board = boards[p_index - 1]
	var is_ready = board.toggle_ready()
	
	var base_text = p1_display_text if p_index == 1 else p2_display_text
	var ready_label = " [color=green][READY][/color]" if is_ready else ""
	var target_label = $p1_anchor/name if p_index == 1 else $p2_anchor/name
	
	target_label.text = base_text + ready_label
	check_start_condition()

func _handle_player_joining(button: ButtonData) -> void:
	gamepad_handler.assign_controller_to_player(button.device_index, next_player_index)
	var my_idx = next_player_index - 1
	var enemy_idx = 1 if my_idx == 0 else 0
	
	boards[my_idx]._player_index = next_player_index
	boards[my_idx].target_player = (enemy_idx + 1)
	
	boards[my_idx].knocked_out.connect(process_next_round)
	
	var device_name = "KEYBOARD" if button.device_index == -1 else "CONTROLLER %d" % button.device_index
	
	if my_idx == 0:
		p1_display_text = device_name
		p1_active = true
		$p1_anchor/name.text = p1_display_text
	else:
		p2_display_text = device_name
		p2_active = true
		$p2_anchor/name.text = p2_display_text
	
	Audio.play_sound("connect")
	next_player_index += 1

func trigger_pause() -> void:
	is_paused = true
	get_tree().paused = true
	print("Game Paused")
	
	# Spawn the Pause Menu
	var pause_menu = PauseMenu.create(gamepad_handler,["no_restart"])
	add_child(pause_menu)

func _on_garbage_sent(payload: Dictionary) -> void:
	# 1. Grab the raw data from the local signal
	var attacker_id = payload.get("player_id")
	var target_id = payload["value"]["target"]
	var amount = payload["value"]["amount"]
	
	#var attacker_id = data.get("attacker_id", -1)
	#var target_id = data.get("target_id", -1)
	#var amount = data.get("amount", 1)
	
	var attacker_node = null
	var target_node = null
	
	# Match the networked IDs to the local active boards
	if attacker_id == p1_board._player_index:
		attacker_node = p1_board
	elif attacker_id == p2_board._player_index:
		attacker_node = p2_board
		
	if target_id == p1_board._player_index:
		target_node = p1_board
	elif target_id == p2_board._player_index:
		target_node = p2_board
		
	# Safety check: ensure both boards are active and found
	if attacker_node == null or target_node == null:
		return
		
	# Start at the attacker's anchor, aim for the target's anchor
	var start_pos = attacker_node.get_parent().global_position
	var target_anchor = target_node.get_parent()
	
	_spawn_attack_visual(start_pos, target_anchor, amount)
	# 2. Package it into a network-friendly dictionary
	#var sync_payload = {
		#"action": "spawn_garbage",
		#"attacker_id": attacker_id,
		#"target_id": target_id,
		#"amount": amount
	#}
	
	# 3. Fire it off to the server/clients!
	#NetworkSync.sync_data(sync_payload)

func _spawn_attack_visual(start_pos: Vector2, target_node: Node, amount: int) -> void:
	# Loop through the amount of garbage to spawn a "swarm" of particles
	# If they sent 4 lines, 4 particles will burst out!
	
	for i in range(amount):
		# Use your custom static create function!
		var particle = AttackParticles.create(target_node)
		if amount < 4:
			particle.modulate = Color.RED
		elif amount < 6:
			particle.modulate = Color.TURQUOISE
		elif amount < 10:
			particle.modulate = Color.VIOLET
		else:
			
			var r = randf_range(0.5,0.8)
			var g = randf_range(0.5,0.8)
			var b = randf_range(0.5,0.8)
			particle.modulate = Color(r,g,b)
		# Set its starting position BEFORE adding to the tree
		# so its _enter_tree random scatter math works perfectly
		particle.global_position = start_pos
		
		# Add it to the $versus node so it renders safely above the game boards
		add_child(particle)

func _controller_connected(device_id: int) -> void: print("Connected: ", device_id)
func _player_disconnected(_player_id: int, _device_id: int) -> void: pass
