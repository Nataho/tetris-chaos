extends Control

@onready var start_button: Button = $start_button
@onready var title: Label = $title
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var status: Label = $ProgressBar/status

func _ready() -> void:
	Audio.play_music("title_screen")
	
	# 1. Lock the start button so they can't skip the update check
	start_button.disabled = true
	
	# 2. Connect your UI to the GameManager's update signals
	GameManager.update_status_msg.connect(_on_status_updated)
	GameManager.update_finished.connect(_on_update_finished)
	start_button.pressed.connect(_on_start_button_pressed)
	
	# 3. Tell the GameManager to start checking GitHub!
	GameManager.check_for_updates()

# This updates your Label inside the ProgressBar every time the status changes
func _on_status_updated(msg: String) -> void:
	status.text = msg

# This triggers when the check/download is 100% complete
func _on_update_finished() -> void:
	# Unlock the play button!
	start_button.disabled = false
	
	# Optional: Fill the progress bar visually so the player knows it's done
	progress_bar.value = 100 
	
	# Clean up the signals
	GameManager.update_status_msg.disconnect(_on_status_updated)
	GameManager.update_finished.disconnect(_on_update_finished)

# Don't forget to connect this function to your start_button's "pressed" signal in the editor!
func _on_start_button_pressed() -> void:
	print("Entering the game...")
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
