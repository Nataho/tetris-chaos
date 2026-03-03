extends Button
class_name RebindButton

# --- STATIC LOGIC ---
# This array stays in memory and is shared by ALL RebindButton instances
static var all_buttons: Array[RebindButton] = []

static func update_all_displays() -> void:
	for button in all_buttons:
		if is_instance_valid(button):
			button.display_current_key()

# --- INSTANCE LOGIC ---
@export var action_name: String = "unbound"
var is_listening: bool = false

var action_map = {
	"move_left": "ML",
	"move_right": "MR",
	"soft_drop": "SD",
	"hard_drop": "HD",
	"rotate_left": "RL",
	"rotate_right": "RR",
	"hold": "H"
}

func _enter_tree() -> void:
	# Add this specific button to the static list when it enters the scene
	all_buttons.append(self)

func _exit_tree() -> void:
	# Remove it when the button is deleted/hidden to prevent memory leaks
	all_buttons.erase(self)

func _ready() -> void:
	display_current_key()
	#mouse_entered.connect(_on_button_pressed)
	pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	is_listening = true
	text = "Press any key..."

func _input(event: InputEvent) -> void:
	if not is_listening:
		return
		
	if event is InputEventKey and event.pressed:
		# Update InputMap
		InputMap.action_erase_events(action_name)
		InputMap.action_add_event(action_name, event)
		
		# Update GameManager (Saving only the keycode as an int)
		# Using shorthand mapping if needed, or just the keycode
		GameManager.controls[action_map[action_name]] = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		GameManager.SAVE_GAME()
		
		is_listening = false
		display_current_key()
		get_viewport().set_input_as_handled()

func display_current_key() -> void:
	var events = InputMap.action_get_events(action_name)
	
	if events.size() > 0:
		var current_event = events[0]
		if current_event is InputEventKey:
			var key_name = OS.get_keycode_string(current_event.physical_keycode)
			if key_name == "":
				key_name = OS.get_keycode_string(current_event.keycode)
			text = key_name
	else:
		text = "Unbound"
