extends Node2D
class_name Board

signal countdown_ticked(time_left: int)
@export var target_player: int = -1
@export var _player_index = -1 #-1 = keyboard

const MAX_GARBAGE_PER_DROP: int = 100

@export var board_controller: BoardController
@export var pieces_controller: PiecesController
@export var queue_controller: QueueController
@export var board_id:int = -1 # -1: offline; 1/4: local; 100+: online; used for targeting players

@export var random_seed:bool = true
@export var seed:int = -1
@export var handicap:float = 1 ##the amount of lines mutiplied or devided from 

@onready var line_clear_message: RichTextLabel = $Control/line_clear_message
@onready var lines_levels: Label = $Control/lines_levels
@onready var score: Label = $Control/score
@onready var add_score_message: Label = $Control/score/add

enum game_modes {MARATHON, VERSUS, ONLINE}
var game_mode:game_modes

const max_message_duration:float = 5
const message_fade_time:float = 2
var line_clear_message_value:float = max_message_duration
var score_add_message_value:float = max_message_duration
var countdown_value:float = max_message_duration
var has_initialized = false
var has_reached_new_high_score = false
var last_garbage_sender:int = -1 #player_id
#var garbage_amounts: Array[int]

var knockout_credit = -1 ##the one who get's the KO score
var garbage_queue: Array[Dictionary] = []
var controller_keybinds = {
	
}

func _ready() -> void:
	#board_controller.start()
	#pieces_controller.start()
	_super_ready()
	
	Events.player_cleared.connect(display_line_clear_message)
	Events.player_kod.connect(_check_ko)
	Events.sent_garbage.connect(receive_garbage)
	pieces_controller.spawned_piece.connect(func(is_hold):
		Events.player_spawned_piece.emit(is_hold)
		)

func initialize_game_mode(gamemode:String, randomization_seed = -1):
	if randomization_seed != -1:
		random_seed = false
		seed = randomization_seed
		
	match gamemode.to_lower(): 
		"marathon":
			game_mode = game_modes.MARATHON
		"versus":
			game_mode = game_modes.VERSUS
		"online":
			game_mode = game_modes.ONLINE
			
	board_controller.start()
	queue_controller.start(board_controller.grid_start,pieces_controller)
	has_initialized = true

#func initialize_game_mode(gamemode:String):
	#match gamemode: 
		#"marathon":
			#board_controller.start()
			#queue_controller.start(board_controller.grid_start,pieces_controller)
			#
			#game_mode = game_modes.MARATHON
			#has_initialized = true
			
func start(countdown: float):
	assert(has_initialized, "game mode has not initialized yet")
	
	if random_seed:
		pieces_controller.randomization_seed = randi()
	else:
		pieces_controller.randomization_seed = seed
	
	pieces_controller.initialize()

	
	# 1. Slice off the decimal part (e.g., 5.4 becomes 0.4)
	var decimal_part = fmod(countdown, 1.0)
	
	# 2. Wait out that fraction of a second in silence FIRST
	if decimal_part > 0.0:
		await get_tree().create_timer(decimal_part, false).timeout
		countdown -= decimal_part
		
	# Now your countdown is a perfect whole number! (e.g., 5.0)
	
	# 3. The perfect 1-second countdown loop
	while countdown > 0.0:
		display_countdown(int(countdown))
		
		# Now we always wait exactly 1 second
		await get_tree().create_timer(1.0, false).timeout
		countdown -= 1.0
		
	# 4. Hit 0! (Your display function turns this into "GO!")
	display_countdown(0)
	pieces_controller.start()
	
func _physics_process(delta: float) -> void:
	_super_physics_process(delta)
	if line_clear_message_value > 0:
		line_clear_message_value -= delta
		
		if line_clear_message_value <= message_fade_time:
			# Directly set the alpha. It will smoothly go from 1.0 to 0.0
			line_clear_message.modulate.a = line_clear_message_value / message_fade_time
		else:
			# Ensure it's fully visible before the fade starts
			line_clear_message.modulate.a = 1.0
			
	if score_add_message_value > 0:
		score_add_message_value -= delta *2
		
		if score_add_message_value <= message_fade_time:
			# Directly set the alpha. It will smoothly go from 1.0 to 0.0
			add_score_message.modulate.a = score_add_message_value / message_fade_time
		else:
			# Ensure it's fully visible before the fade starts
			add_score_message.modulate.a = 1.0
			
	if countdown_value > 0:
		countdown_value -= delta * 10
		
		if countdown_value <= message_fade_time:
			# Directly set the alpha. It will smoothly go from 1.0 to 0.0
			$Control/countdown.modulate.a = countdown_value / message_fade_time
		else:
			# Ensure it's fully visible before the fade starts
			$Control/countdown.modulate.a = 1.0

func display_line_clear_message(payload):
	var player_index:int = payload["player_index"]
	if player_index != _player_index: return
	
	line_clear_message.modulate.a = 1.0
	line_clear_message_value = max_message_duration
	add_score_message.modulate.a = 1.0
	score_add_message_value = max_message_duration
	var message:String = ""
	
	print(payload)
	var name = payload["name"]
	var values = payload["value"]
	var is_spin:bool = values["is_spin"]
	var b2b_count:int = values["b2b_count"]
	var is_mini:bool = values["is_mini"]
	var is_all_spin:bool = values["is_all_spin"]
	#var piece_type = values["piece_type"] #for all spin
	var lines_to_clear:int = values["lines_to_clear"]
	var is_perfect_clear:bool = values["is_perfect_clear"]
	var combo_count:int = values["combo_count"]
	var total_lines_cleared:int = values["total_lines_cleared"]
	var current_level:int = values["current_level"]
	var clear_score:int = values["clear_score"]
	var current_score:int = values["current_score"]
	var piece_type:String = values["piece_type"]
	print("clear_score: ", clear_score)
	
	
	var color:String = "white"
	match piece_type:
		"L": color = "orange"
		"J": color = "blue"
		"S": color = "green"
		"Z": color = "red"
		"O": color = "yellow"
		"I": color = "cyan"
		"T": color = "violet"
	
	if is_spin:
		message += "[color=%s]%s-Spin[/color]" %[color,piece_type]
		if is_mini:
			message += " Mini"
	
	match lines_to_clear:
		0: pass
		1: message += " Single!"
		2: message += " Double!"
		3: message += " Triple!"
		4: message += " [color=red]T[/color][color=green]E[/color][color=orange]T[/color][color=violet]R[/color][color=cyan]I[/color][color=orange]S[/color]!"
	
	if b2b_count > 0 and lines_to_clear > 0:
		message += "\nB2B %dx" % [b2b_count]
	
	if combo_count >0:
		message += "\n[shake rate=%d level=%d]Combo %dx[/shake]" % [combo_count*20,combo_count,combo_count]
	
	if is_perfect_clear:
		message += "\n[rainbow freq=1 sat=10 val=1][bounce freq=10 amp=5]PERFECT CLEAR![/bounce][/rainbow]"
	message = "[wave amp=50 freq=5]%s[/wave]" % [message]
	line_clear_message.text = message
	
	var lines_cleared:int = 0
	var lines_for_next_level:int = 10
	if total_lines_cleared < current_level * 10:
		lines_cleared = total_lines_cleared
		lines_for_next_level = current_level*10
	else:
		lines_cleared  = total_lines_cleared % 10
	var level = (1 + (total_lines_cleared / 10))
	
	lines_levels.text = "Lines:\n%d/%d\n\nlvl:\n%d" % [lines_cleared, lines_for_next_level, current_level]
	score.text = str(current_score)
	add_score_message.text = "+" + str(clear_score)
	
	if (current_score > GameManager.player_data["high_score"]) and !has_reached_new_high_score:
		Audio.play_sound("new_high_score")
		has_reached_new_high_score = true

func update_details(level:int):
	var lines_cleared = 0
	var lines_for_next_level = 10 * level
	var current_level = level
	lines_levels.text = "Lines:\n%d/%d\n\nlvl:\n%d" % [lines_cleared, lines_for_next_level, current_level]
	
	board_controller.current_level = level

func display_countdown(time_left:int):
	var countdown_text = str(time_left)
	Audio.play_sound("countdown_%s" % countdown_text)
	match countdown_text:
		"0":
			countdown_text = "GO!"
			
	print("displaying countdown: ", time_left)
	
	
	$Control/countdown.text = countdown_text
	$Control/countdown.modulate.a = 1
	countdown_value = max_message_duration
	
func reset():
	_super_reset()
	# 1. Hide Game Over screen and floating texts
	garbage_queue = []
	
	$Control/gameover.hide()
	line_clear_message.modulate.a = 0
	add_score_message.modulate.a = 0
	$Control/countdown.modulate.a = 0
	
	line_clear_message_value = 0
	score_add_message_value = 0
	countdown_value = 0
	has_reached_new_high_score = false
	
	# 2. Reset all the individual controllers
	board_controller.reset()
	pieces_controller.reset()
	queue_controller.reset()
	
	# 3. Reset the UI Text manually
	update_details(1) # Sets level to 1, lines to 0
	score.text = "0"
	
	# 4. Fire the game back up!
	#initialize_game_mode("marathon")
	#start(3.0) # Starts the 3-second countdown


#@onready var board: BoardController = $board # Change this to whatever your BoardController node is named!

# Call this when the OPPONENT clears lines and sends an attack to this board
func receive_garbage(payload):
	if game_mode == game_modes.MARATHON: return
	
	var attacker = payload["player_id"]
	var amount = payload["value"]["amount"]
	var target = payload["value"]["target"]
	
	# NEW FIX: Add `amount <= 0` to the abort check so we ignore empty attacks!
	if target != _player_index or amount <= 0: 
		return
	
	# All lines in this specific attack get the same gap (Clean Garbage!)
	var random_gap = randi() % board_controller.grid_size.x 
	
	garbage_queue.append({
		"sender":attacker,
		"amount": amount,
		"gap_index": random_gap
	})
	
	board_controller.update_garbage_meter()

func _check_ko(payload):
	if payload["player_id"] != _player_index:
		return
	print("player died")
	$Control/gameover.show()

#functions to be used on children
func _super_ready() -> void: pass
func _super_physics_process(_delta) -> void: pass
func _super_reset() -> void: pass
