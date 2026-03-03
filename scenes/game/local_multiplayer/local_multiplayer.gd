extends Control

const SLIDE_SPEED: float = 10.0
const DISTANCE: float = 0.25

@onready var anim: AnimationPlayer = $anim

@onready var p1_anchor: Control = $p1_anchor
@onready var p2_anchor: Control = $p2_anchor

@onready var p1_board: MultiplayerBoard = $p1_anchor/board
@onready var p2_board: MultiplayerBoard = $p2_anchor/board

@onready var boards: Array[MultiplayerBoard] = [
	p1_board,
	p2_board,
]

var gamepad_handler := GamepadHandler.new()
var next_player_index:int = 1
var game_started:bool = false

func _ready() -> void:
	Audio.play_music("battle")
	
	_connect_signals()
	_start_players()

#[CONTINUE]you were last dealing with garbage lines

func _process(delta: float) -> void:
	gamepad_handler.handle_controller_input()
	handle_ui_animations(delta)

func process_next_round(board:MultiplayerBoard):
	var KO_credit = board.knockout_credit
	print("trying to go next round..")
	print("knockout credit goes to: ", KO_credit)
	
	_reset_players()

func handle_ui_animations(delta: float):
	var screen_size := get_viewport_rect().size
	
	# Flawless frame-rate independent lerp!
	var lerp_weight = 1.0 - exp(-SLIDE_SPEED * delta)
	
	# Use decimals so Godot calculates floats instead of integers
	var p1_position = Vector2(screen_size.x * (0.50 - DISTANCE), screen_size.y * 0.5)
	var p2_position = Vector2(screen_size.x * (0.50 + DISTANCE), screen_size.y * 0.5)
	
	p1_anchor.position = p1_anchor.position.lerp(p1_position, lerp_weight)
	p2_anchor.position = p2_anchor.position.lerp(p2_position, lerp_weight)

func _start_players():
	var seed = randi()
	for board in boards:
		board.initialize_game_mode("versus", seed)
		board.start(3)
		
		if game_started: continue #don't proceed if game is started
		board.knocked_out.connect(process_next_round)
	
	game_started = true
		
func _reset_players():
	anim.play("next_round_in")
	await anim.animation_finished
	
	for board:MultiplayerBoard in boards:
		await board.reset()
	
	await get_tree().create_timer(1).timeout #[TEST]
	
	_start_players()
	anim.play("next_round_out")
	await anim.animation_finished
	


func _connect_signals():
	gamepad_handler.gamepad_button_press.connect(_button_input)
	gamepad_handler.controller_connected.connect(_controller_connected)
	gamepad_handler.player_disconnected.connect(_player_disconnected)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ready"):
		# Check if keyboard (-1) is already assigned. If not, default to -1.
		var current_p_index = gamepad_handler.controllers.get(-1, -1)
		
		# Now it will pass 1 (or 2) if it has been assigned!
		var button: ButtonData = ButtonData.new("START", current_p_index, -1, true)
		_button_input(button)

func _button_input(button:ButtonData):
	print("pindex before: {player_index}".format(button))
	if button.name == "START":
		if !gamepad_handler.controllers.has(button.device_index):
			# 1. Assign it in the dictionary
			gamepad_handler.assign_controller_to_player(button.device_index, next_player_index)
			
			# 2. Tell the specific board what its player index is!
			# (next_player_index is 1, so index 1 - 1 = array index 0 for p1_board)
			boards[next_player_index - 1]._player_index = next_player_index
			
			print("Player %d has joined on Device %d!" % [next_player_index, button.device_index])
			next_player_index += 1
			return
		
	if !gamepad_handler.controllers.has(button.device_index): return
	print("Pindex: {player_index}; Dindex: {device_index}".format(button))

func _controller_connected(device_id:int):
	print(device_id)
func _player_disconnected(player_id:int, device_id:int):
	pass
