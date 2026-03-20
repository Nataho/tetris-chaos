extends Node

# --- NEW SIGNALS FOR YOUR UI ---
signal update_status_msg(message: String)
signal update_finished()

#const default_server_ip = "10.147.17.203"
const default_server_ip = "127.0.0.1"
const default_port = 69671

# --- UPDATED VERSIONING ---
const GAME_VERSION = "v0.5.4" 
const VERSION_URL = "https://nataho.github.io/tetris-chaos/version.json"
const dev_build = false

var active_version: String = GAME_VERSION
var target_version: String = ""

#ui state variables
var is_prompt_open:bool = false

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

var achievements = {}
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

# --- NEW HTTP NODE ---
var http_request: HTTPRequest

func _ready() -> void:
	# Load the game immediately when the manager starts
	CLA()
	if not LOAD_GAME():
		# If no save exists, apply defaults for the first time
		_apply_controls_to_engine()
	SAVE_GAME()
	
	# --- 1. LOAD THE EXISTING PATCH SO IT DOESN'T FORGET ---
	_load_existing_patch()
	
	# --- START THE UPDATER ---
	# We create the HTTP node purely in code so you don't have to mess with your Scene Tree!
	http_request = HTTPRequest.new()
	add_child(http_request)
	#check_for_updates()

func CLA():
	var args = OS.get_cmdline_args()
	if "--mute" in args:
		print("muting")
		AudioServer.set_bus_mute(0,true)

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

func _save() -> Dictionary:
	update_save_data()
	return _save_data

func SAVE_GAME():
	var save_file = FileAccess.open("user://Save.save",FileAccess.WRITE)
	var json_string = JSON.stringify(_save(),"\t",false,true)
	save_file.store_line(json_string)
	print("sucessfully saved game")

func LOAD_GAME() -> bool:
	if not FileAccess.file_exists("user://Save.save"):
		return false

	var save_file = FileAccess.open("user://Save.save", FileAccess.READ)
	var data = JSON.parse_string(save_file.get_as_text())
	save_file.close()

	if data == null:
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
	return server_info["ip"] + ":" + server_info["port"]

# ==========================================
# AUTO UPDATER ENGINE
# ==========================================

func _load_existing_patch() -> void:
	# 1. If we have a downloaded patch, inject it into the game on boot!
	if FileAccess.file_exists("user://hotfix.pck"):
		ProjectSettings.load_resource_pack("user://hotfix.pck")
		
	# 2. Read what version that patch was so we don't redownload it
	if FileAccess.file_exists("user://patch_version.txt"):
		var file = FileAccess.open("user://patch_version.txt", FileAccess.READ)
		active_version = file.get_as_text().strip_edges()
	else:
		active_version = GAME_VERSION

func check_for_updates() -> void:
	update_status_msg.emit("Checking for updates...")
	http_request.request_completed.connect(_on_version_check_completed)
	http_request.request(VERSION_URL)

func _on_version_check_completed(_result, response_code, _headers, body) -> void:
	http_request.request_completed.disconnect(_on_version_check_completed)
	
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json == null or not json.has("latest_version"):
			_finish_update("Up to date!")
			return
			
		var latest_version = json["latest_version"]
		
		# --- 2. COMPARE AGAINST active_version INSTEAD OF GAME_VERSION ---
		if is_version_older(active_version, latest_version):
			target_version = latest_version
			update_status_msg.emit("Downloading patch " + latest_version + "...")
			download_patch(json["patch_url"])
		else:
			_finish_update("Game is up to date!")
	else:
		_finish_update("Playing Offline")

func is_version_older(current: String, latest: String) -> bool:
	var curr_parts = current.replace("v", "").split(".")
	var late_parts = latest.replace("v", "").split(".")
	
	if curr_parts.size() < 3 or late_parts.size() < 3: return false
	
	for i in range(3):
		if int(curr_parts[i]) < int(late_parts[i]): return true
		elif int(curr_parts[i]) > int(late_parts[i]): return false
	return false

func download_patch(patch_url: String) -> void:
	http_request.download_file = "user://hotfix.pck"
	http_request.request_completed.connect(_on_patch_downloaded)
	http_request.request(patch_url)

func _on_patch_downloaded(_result, response_code, _headers, _body) -> void:
	http_request.request_completed.disconnect(_on_patch_downloaded)
	if response_code == 200 or response_code == 302:
		var success = ProjectSettings.load_resource_pack("user://hotfix.pck")
		if success:
			# --- 3. SAVE THE TEXT FILE SO IT REMEMBERS TOMORROW ---
			var file = FileAccess.open("user://patch_version.txt", FileAccess.WRITE)
			file.store_string(target_version)
			active_version = target_version
			
			_finish_update("Update Applied Successfully!")
		else:
			_finish_update("Failed to apply patch.")
	else:
		_finish_update("Download failed.")

func _finish_update(final_message: String) -> void:
	print(final_message)
	update_status_msg.emit(final_message)
	update_finished.emit()
