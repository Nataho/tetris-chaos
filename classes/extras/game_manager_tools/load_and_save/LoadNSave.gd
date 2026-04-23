class_name LoadNSave extends RefCounted

const default_server_ip = "127.0.0.1"
const default_port = 10100

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

func save_file(data: Dictionary) -> void:
	var save_file = FileAccess.open("user://Save.save", FileAccess.WRITE)
	var json_string = JSON.stringify(data, "\t", false, true)
	save_file.store_line(json_string)
	print("sucessfully saved game")

func load_file() -> Dictionary:
	if not FileAccess.file_exists("user://Save.save"):
		return {}

	var save_file = FileAccess.open("user://Save.save", FileAccess.READ)
	var data = JSON.parse_string(save_file.get_as_text())
	save_file.close()

	if data == null:
		return {}

	return data
