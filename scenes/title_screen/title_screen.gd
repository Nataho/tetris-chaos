extends Control

@onready var start_button: Button = $start_button
@onready var title: Label = $title
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var status: Label = $ProgressBar/status

var target_progress: float = 0.0

func _ready() -> void:
	Audio.play_music("title_screen")
	
	# 1. Lock the start button so they can't skip the update check
	start_button.disabled = true
	
	# Reset progress bar visual
	progress_bar.value = 0.0
	target_progress = 0.0
	
	# 2. Connect your UI to the GameManager's update signals
	GameManager.update_status_msg.connect(_on_status_updated)
	GameManager.update_progress.connect(_on_progress_updated) # <-- CONNECT NEW SIGNAL
	GameManager.update_finished.connect(_on_update_finished)
	start_button.pressed.connect(_on_start_button_pressed)
	
	# 3. Tell the GameManager to start checking GitHub!
	GameManager.check_for_updates()

func _process(delta: float) -> void:
	# Smoothly interpolate the visual progress bar to match the target percentage.
	# The '8.0' is the speed. Higher = faster snapping, Lower = slower floating.
	progress_bar.value = lerpf(progress_bar.value, target_progress, delta * 8.0)

# This updates your Label inside the ProgressBar every time the status changes
func _on_status_updated(msg: String) -> void:
	status.text = msg

# This triggers every frame while downloading
func _on_progress_updated(current_bytes: int, total_bytes: int) -> void:
	# Convert raw bytes to Megabytes (1 MB = 1,048,576 bytes)
	var current_mb := current_bytes / 1048576.0
	
	# Sometimes servers hide the total file size. If total is -1, we just show downloaded MB.
	if total_bytes > 0:
		var total_mb := total_bytes / 1048576.0
		# Set the target percentage for the lerp
		target_progress = (float(current_bytes) / float(total_bytes)) * 100.0
		status.text = "Downloading patch... %.2f MB / %.2f MB" % [current_mb, total_mb]
	else:
		# Fallback if the server hides file size
		status.text = "Downloading patch... %.2f MB" % [current_mb]
		# Fake a pulsing progress bar or leave it at 0
		target_progress = wrapf(target_progress + 1.0, 0.0, 100.0)

# This triggers when the check/download is 100% complete
func _on_update_finished() -> void:
	# Unlock the play button!
	start_button.disabled = false
	
	# Force the bar to be 100% full visually at the end
	target_progress = 100.0 
	
	# Clean up the signals
	GameManager.update_status_msg.disconnect(_on_status_updated)
	GameManager.update_progress.disconnect(_on_progress_updated)
	GameManager.update_finished.disconnect(_on_update_finished)

# Don't forget to connect this function to your start_button's "pressed" signal in the editor!
func _on_start_button_pressed() -> void:
	print("Entering the game...")
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
