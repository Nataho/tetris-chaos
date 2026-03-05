extends Node

@warning_ignore("unused_signal")
signal gamepad_handler_activity

#region local player
signal player_placed(payload)
signal player_moved(payload)
signal player_rotated(payload)
signal player_cleared(payload)
signal player_kod(payload)
#endregion

#region local signals
signal local_countdown(time_left:int)
signal android_back_pressed
#endregion

#region multiplayer signals
signal sent_garbage(payload)
#endregion

#region server-client signals
signal client_searching
signal client_connected

func _notification(what: int) -> void:
	# This listens specifically for the Android Back Button / Gesture
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		
		# Prevent it from triggering multiple times
		get_tree().root.set_input_as_handled() 
		
		# --- Do your Tetris stuff here! ---
		print("Android Back Button was pressed!")
		android_back_pressed.emit()
		# Example: If the game is running, pause it. 
		# If it's already paused, unpause it or go to the main menu.
		# toggle_pause_menu()
