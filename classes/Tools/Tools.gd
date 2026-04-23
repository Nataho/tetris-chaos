extends Node
class_name Tools

static func cycle_window_mode() -> String:
	var current_mode = DisplayServer.window_get_mode()
	
	# If we are currently in Windowed mode, switch to Fullscreen
	if current_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return "fullscreen"
		
	# If we are in Fullscreen (or any other mode), switch back to Windowed
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		
		# Re-center the window so it doesn't get stuck in the corner!
		var screen_size = DisplayServer.screen_get_size()
		var window_size = DisplayServer.window_get_size()
		@warning_ignore("integer_division")
		DisplayServer.window_set_position(screen_size / 2 - window_size / 2)
		
		return "windowed"

static func has_space(text:String) -> bool:
	return true if " " in text else false

static func CLA(): ## Specifically used by game manager when game first starts
	var args = OS.get_cmdline_args()
	if "--mute" in args:
		print("muting")
		AudioServer.set_bus_mute(0,true)
