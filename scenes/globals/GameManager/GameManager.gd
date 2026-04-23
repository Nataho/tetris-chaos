extends Node

const GAME_VERSION = "v0.5.8" 
const dev_build = true

var active_version: String = GAME_VERSION

# ui state variables
var is_prompt_open:bool = false

var server_info := {
	"ip": "",
	"port": 0,
	"server_id": 0
}

var achievements = {}
var player_data = {
	"uid": "",
	"name": "guest",
	"high_score": 0,
	"marathon_level": 1,
}

var controls = {}
var handling = {}
var settings = {
	"server_ip": ""
}
var _save_data = {}

# --- TCP for server ---
var server_tcp: TCPBridge

# --- LOAD & SAVE MANAGER ---
var lns: LoadNSave

func _ready() -> void:
	Tools.CLA()
	
	# --- 1. CALL STATIC FUNCTION TO LOAD EXISTING PATCH ---
	# This injects the PCK and returns the text file's version (or GAME_VERSION if no patch exists)
	active_version = PatchManager.apply_existing_patch(GAME_VERSION)
	
	lns = LoadNSave.new()
	
	server_info["ip"] = lns.default_server_ip
	server_info["port"] = lns.default_port
	settings["server_ip"] = lns.default_server_ip
	controls = lns.default_keyboard_controls.duplicate()
	handling = lns.default_handling.duplicate()
	
	if not LOAD_GAME():
		_apply_controls_to_engine()
	SAVE_GAME()
	
	_instantiate_singletons()

func _instantiate_singletons():
	add_child(TCPBridge.new())
	add_child(Audio.new())

func _apply_controls_to_engine():
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
		
		InputMap.action_erase_events(action_name)
		var new_event = InputEventKey.new()
		new_event.physical_keycode = key_code
		InputMap.action_add_event(action_name, new_event)

func update_save_data():
	_save_data = {
		"achievements": achievements,
		"player_data": player_data,
		"controls": controls,
		"handling": handling,
		"settings": settings,
	}

func SAVE_GAME():
	update_save_data()
	lns.save_file(_save_data)

func LOAD_GAME() -> bool:
	var data = lns.load_file()
	
	if data.is_empty():
		return false

	achievements.merge(data.get("achievements", {}), true)
	player_data.merge(data.get("player_data", {}), true)
	settings.merge(data.get("settings", {}), true)

	var loaded_controls = data.get("controls", {})
	for key in loaded_controls:
		controls[key] = int(loaded_controls[key])
	
	var loaded_handling = data.get("handling",{})
	for key in loaded_handling:
		handling[key] = int(loaded_handling[key])

	_apply_controls_to_engine()
	update_save_data()
	return true

func _exit_tree() -> void:
	SAVE_GAME()

func change_resolution(width: int, height: int):
	DisplayServer.window_set_size(Vector2i(width, height))
	var screen_size = DisplayServer.screen_get_size()
	var window_size = DisplayServer.window_get_size()
	@warning_ignore("integer_division")
	DisplayServer.window_set_position(screen_size / 2 - window_size / 2)

func get_port_and_ip() -> String:
	return str(server_info["ip"]) + ":" + str(server_info["port"])
