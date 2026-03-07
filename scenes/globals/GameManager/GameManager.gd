extends Node
#const default_server_ip = "10.147.17.203"
const default_server_ip = "127.0.0.1"
const default_port = 69671

var server_info := {
	"ip": default_server_ip,
	"port": default_port,
	"server_id": 0
}

const default_keyboard_controls = {
	"ML": KEY_LEFT,
	"MR": KEY_RIGHT,
	"SD": KEY_DOWN,
	"HD": KEY_SPACE,
	"RL": KEY_Z,
	"RR": KEY_X,
	"H": KEY_C
}

const default_gamepad_controls = {
	"ML": ["L"],
	"MR": ["R"],
	"SD": ["D"],
	"HD": ["U"],
	"RL": ["A"],
	"RR": ["B"],
	"H": ["LB","RB"]
}

const default_handling = {
	"SD": 100,
	"DAS": 167,
	"ARR": 33,
}

var achievements = {
	
}
var player_data = {
	"uid": "",
	"name": "guest",
	"high_score": 0,
	"marathon_level": 1,
}
var controls = default_keyboard_controls.duplicate()
var handling = default_handling.duplicate()

var settings = {
	"server_ip": default_server_ip
}
var _save_data = {
	"achievements": achievements,
	"player_data": player_data,
	"controls": controls,
	"settings": settings
}

func _ready() -> void:
	# Load the game immediately when the manager starts
	CLA()
	if not LOAD_GAME():
		# If no save exists, apply defaults for the first time
		_apply_controls_to_engine()
	SAVE_GAME()

func CLA():
	var args = OS.get_cmdline_args()
	if "--mute" in args:
		print("muting")
		AudioServer.set_bus_mute(0,true)
	#if "-nosave"
	#if "--force_mobile" in args:
		#force_mobile = true

func _apply_controls_to_engine():
	# Define a map of your shorthand keys to actual InputMap action names
	var action_map = {
		"ML": "move_left",
		"MR": "move_right",
		"SD": "soft_drop",
		"HD": "hard_drop",
		"RL": "rotate_left",
		"RR": "rotate_right",
		"H": "hold"
	}

	for shorthand in action_map:
		var action_name = action_map[shorthand]
		var key_code = int(controls[shorthand])
		
		# Clear existing events and add the new one
		InputMap.action_erase_events(action_name)
		var new_event = InputEventKey.new()
		new_event.physical_keycode = key_code
		InputMap.action_add_event(action_name, new_event)

func update_save_data():
	# Explicitly re-map these to ensure _save_data has the LATEST values
	_save_data = {
		"achievements": achievements,
		"player_data": player_data,
		"controls": controls,
		"handling": handling,
		"settings": settings,
	}

func _save() -> Dictionary:
	update_save_data()
	var save = _save_data
	return save

func SAVE_GAME():
	var save_file = FileAccess.open("user://Save.save",FileAccess.WRITE) #get save file and write
	var json_string = JSON.stringify(_save(),"\t",false,true) #convert to json string
	save_file.store_line(json_string) #write the info to file as json
	print("sucessfully saved game")
	#print(json_string)

func LOAD_GAME() -> bool:
	if not FileAccess.file_exists("user://Save.save"):
		return false

	var save_file = FileAccess.open("user://Save.save", FileAccess.READ)
	var data = JSON.parse_string(save_file.get_as_text())
	save_file.close()

	if data == null:
		return false

	# Use .merge to update the existing dictionaries instead of replacing them
	# This keeps the reference inside _save_data intact!
	achievements.merge(data.get("achievements", {}), true)
	player_data.merge(data.get("player_data", {}), true)
	settings.merge(data.get("settings", {}), true)

	# Handle Controls specifically because of the Integer cast
	var loaded_controls = data.get("controls", {})
	for key in loaded_controls:
		controls[key] = int(loaded_controls[key])
	
	var loaded_handling = data.get("handling",{})
	for key in loaded_handling:
		handling[key] = int(loaded_handling[key])

	_apply_controls_to_engine()
	
	# IMPORTANT: Refresh the save_data container with the loaded values
	update_save_data()
	
	print("Loaded and synced: ", controls)
	return true

func _exit_tree() -> void:
	SAVE_GAME()

func change_resolution(width: int, height: int):
	# Set the window size
	DisplayServer.window_set_size(Vector2i(width, height))
	
	# Optional: Center the window on the screen after resizing
	var screen_size = DisplayServer.screen_get_size()
	var window_size = DisplayServer.window_get_size()
	DisplayServer.window_set_position(screen_size / 2 - window_size / 2)

func get_port_and_ip() -> String:
	return server_info["ip"] + ":" + server_info["port"]
