extends Control
#class_name MarathonMode # Optional, but good practice if other scripts need to find this!

# ==========================================
# CONSTANTS & CONSTANT STATE
# ==========================================
const SLIDE_SPEED: float = 10.0
const MOBILE_SHOW := Color(1, 1, 1, 1)
const MOBILE_HIDE := Color(1, 1, 1, 0)

# ==========================================
# EXPORTS
# ==========================================
@export_category("UI Nodes")
@export var board_anchor_point_node: Control
@export var set_ui_node: Control
@export var level_text_box: LineEdit
@export var start_button: Button

# ==========================================
# ONREADY VARIABLES
# ==========================================
# Cache these so Godot doesn't have to search the tree every frame
@onready var mobile_controls: Control = $mobile_controls
@onready var board_node: Node = board_anchor_point_node.get_child(0)

# ==========================================
# STATE VARIABLES
# ==========================================
var is_playing: bool = false
var is_paused: bool = false
var selected_level: int = 1

# ==========================================
# BUILT-IN ENGINE FUNCTIONS
# ==========================================
func _ready() -> void:
	_on_level_text_changed(str(GameManager.player_data["marathon_level"]))
	Audio.play_music("main_menu")
	
	# 1. Initial Hardcoded Layouts
	set_ui_node.position = Vector2(0, -1258)
	board_anchor_point_node.position = Vector2(-498, 540)
	
	$set_ui/VBoxContainer/high_schore.text = "High Score:\n%d" % GameManager.player_data["high_score"]
	
	# 2. Platform Checks
	if OS.get_name() not in ["Android", "iOS"]:
		mobile_controls.hide()

	# 3. Initialization
	board_node.initialize_game_mode("marathon")
	_connect_signals()

func _process(delta: float) -> void:
	# Keep _process clean! Just call the helper function.
	_handle_ui_animations(delta)

func _input(event: InputEvent) -> void:
	# Only allow the Main script to pause if the game is running AND not already paused
	if event.is_action_pressed("pause"):
		
		if is_playing and not is_paused:
			trigger_pause()
		if !is_playing:
			_back()
# ==========================================
# PRIVATE LOGIC FUNCTIONS
# ==========================================
func _handle_ui_animations(delta: float) -> void:
	var screen_size = get_viewport_rect().size
	
	# 1. Calculate Targets
	var menu_board_pos = Vector2(screen_size.x / 1.618, screen_size.y / 2.0)
	var play_board_pos = screen_size / 2.0 
	
	var show_ui_pos = Vector2.ZERO
	var hide_ui_pos = Vector2(0, -screen_size.y)
	
	# 2. Assign Targets via Ternary Operators (Super clean one-liners!)
	var target_board_pos: Vector2 = play_board_pos if is_playing else menu_board_pos
	var target_ui_pos: Vector2 = hide_ui_pos if is_playing else show_ui_pos
	var target_mobile_opacity: Color = MOBILE_SHOW if is_playing else MOBILE_HIDE

	# 3. Frame-Rate Independent Lerping
	var lerp_weight = 1.0 - exp(-SLIDE_SPEED * delta)
	
	board_anchor_point_node.position = board_anchor_point_node.position.lerp(target_board_pos, lerp_weight)
	set_ui_node.position = set_ui_node.position.lerp(target_ui_pos, lerp_weight)
	mobile_controls.modulate.a = lerp(mobile_controls.modulate.a, target_mobile_opacity.a, lerp_weight)

func _connect_signals() -> void:
	level_text_box.text_changed.connect(_on_level_text_changed)
	start_button.pressed.connect(_on_start_button_pressed)
	Events.player_kod.connect(_on_player_kod)
	
	# Only connect this if we are actively playing and NOT paused
	Events.android_back_pressed.connect(func():
		if is_playing and not is_paused:
			trigger_pause()
		if !is_playing:
			_back()
	)

func trigger_pause() -> void:
	is_paused = true
	get_tree().paused = true
	print("Game Paused")
	
	# Spawn the Pause Menu
	var pause_menu = PauseMenu.create()
	add_child(pause_menu)

# ==========================================
# SIGNAL CALLBACKS
# ==========================================
func _on_level_text_changed(text: String) -> void:
	var parsed_input: int = text.to_int()
	if parsed_input == 0: 
		parsed_input = 1
	selected_level = parsed_input
	GameManager.player_data["marathon_level"] = parsed_input
	GameManager.SAVE_GAME()
	board_node.update_details(parsed_input)

func _on_start_button_pressed() -> void:
	board_node.reset()
	board_node.update_details(selected_level)
	board_node.start(3.7)
	Audio.play_music("marathon")
	
	is_playing = true 
	start_button.release_focus()

func _on_player_kod(payload) -> void:
	is_playing = false
	
	
	# Make sure the game unpauses if they die while paused (just in case!)
	#if is_paused:
		#toggle_pause()
		
	if payload["score"] > GameManager.player_data["high_score"]:
		GameManager.player_data["high_score"] = payload["score"]
	
	$set_ui/VBoxContainer/high_schore.text = "High Score:\n%d" % GameManager.player_data["high_score"]
	GameManager.SAVE_GAME()
	Audio.play_music("game_over", Audio.SOUND_END_EFFECTS.VINYL)

func _back():
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	pass
