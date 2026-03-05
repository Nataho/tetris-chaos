extends Control
class_name PauseMenu

const FILE = preload("uid://bi5x52ocv1j03")
var _gamepad_handler:GamepadHandler
var _args = []
#@onready var buttons = {
	#"resume": $vbox/resume,
	#"restart": $vbox/restart,
	#""
#}


static func create(gamepad_handler:GamepadHandler = null, args:Array[String] = []) -> PauseMenu:
	
	var obj:PauseMenu = FILE.instantiate()
	if gamepad_handler != null:
		obj._gamepad_handler = gamepad_handler
		obj._args = args
	return obj

func _enter_tree() -> void:
	# CRITICAL: This tells the menu to stay awake even when the tree is paused!
	process_mode = Node.PROCESS_MODE_ALWAYS 
	if _args.size() > 0:
		for arg in _args:
			match arg:
				"no_restart":
					$vbox/restart.hide()
	
	Events.android_back_pressed.connect(resume)
	$vbox/resume.pressed.connect(resume)
	$vbox/restart.pressed.connect(restart)
	$vbox/main_menu.pressed.connect(main_menu)
	
	if _gamepad_handler == null: return
	_gamepad_handler.gamepad_button_press.connect(func(button:ButtonData):
		#get_viewport().set_input_as_handled()
		if button.name == "START":
			resume()
		)

func _process(delta: float) -> void:
	_gamepad_handler.handle_controller_input()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled() # Eats the input so it doesn't double-fire
		resume()
 
func resume() -> void:
	get_tree().paused = false
	
	# Safely tell the parent (Main script) that we are unpaused
	if get_parent() != null and "is_paused" in get_parent():
		get_parent().is_paused = false
		
	print("Game Resumed")
	
	# Disconnect the signal before deleting so we don't cause memory leaks
	if Events.android_back_pressed.is_connected(resume):
		Events.android_back_pressed.disconnect(resume)
		
	queue_free()
	print("kaabot diri?")

func restart() -> void:
	get_tree().paused = false
	#if get_parent() != null and "is_paused" in get_parent():
		#get_parent().is_paused = false
	
	queue_free()
	get_tree().reload_current_scene()

func main_menu() -> void:
	get_tree().paused = false
	queue_free()
	
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	pass
