extends LineEdit
class_name HandlingEditor

# --- STATIC REGISTRY ---
static var all_editors: Array[HandlingEditor] = []

static func update_all_displays() -> void:
	for editor in all_editors:
		if is_instance_valid(editor):
			editor.display_current_value()

# --- INSTANCE LOGIC ---
@export var handling_name: String

func _enter_tree() -> void:
	all_editors.append(self)

func _exit_tree() -> void:
	all_editors.erase(self)

func _ready() -> void:
	# Initial display when the node enters the scene
	display_current_value()
	text_changed.connect(text_updated)

func text_updated(new_text: String) -> void:
	# Ensure we only store valid integers
	var int_val: int = 0
	if new_text != "":
		int_val = int(new_text)
	
	if int_val == 0:
		int_val = GameManager.default_handling[handling_name]
		print("int val: ", int_val)
		
	match handling_name:
		"DAS": if int_val < 60:int_val = 60
		"ARR": if int_val < 10:int_val = 10
		"SD": if int_val < 25:int_val = 25
	
		
	# Update GameManager directly
	if GameManager.handling.has(handling_name):
		GameManager.handling[handling_name] = int_val
		GameManager.SAVE_GAME()
	else:
		push_warning("Handling key not found in GameManager: " + handling_name)

func display_current_value() -> void:
	# Pull the value from GameManager and put it in the LineEdit
	if GameManager.handling.has(handling_name):
		text = str(GameManager.handling[handling_name])
	else:
		text = "0"
	
	match handling_name:
		"DAS": placeholder_text = "> 60"
		"ARR": placeholder_text = "> 10"
		"SD": placeholder_text = "> 25"
