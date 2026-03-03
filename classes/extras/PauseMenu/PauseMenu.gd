extends Control
class_name PauseMenu

const FILE = preload("uid://bi5x52ocv1j03")

static func create() -> PauseMenu:
	var obj:PauseMenu = FILE.instantiate()
	return obj

func _enter_tree() -> void:
	# CRITICAL: This tells the menu to stay awake even when the tree is paused!
	process_mode = Node.PROCESS_MODE_ALWAYS 
	
	Events.android_back_pressed.connect(resume)
	$vbox/resume.pressed.connect(resume)
	$vbox/restart.pressed.connect(restart)
	$vbox/main_menu.pressed.connect(main_menu)

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
