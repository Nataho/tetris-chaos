class_name GamepadHandler

signal gamepad_button_press(button: ButtonData)
signal gamepad_button_released(button: ButtonData)
signal gamepad_axis_changed(axis_data: AxisData)
signal gamepad_stick_changed(stick_data: StickData)
signal controller_connected(device_index: int)
signal controller_disconnected(device_index: int)
signal player_disconnected(player_index: int)
signal activity ##a signal to tell that there is activity on the gamepad handler

var isDebug = false
var isSetup = false
var axis_deadzone := 0.01

# active players (e.g. { 0: 1, 1: 3 } means player 0 uses device 1, player 1 uses device 3)
static var controllers := {}
var connected_controllers: Array = []
var active_controller_index: int = 0 # fallback for single input mode

var prev_button_states = {}
var prev_axis_states = {}
var prev_stick_states = {}

# (Optional) treat keyboard as "virtual controllers"
const KEYBOARD_P1_INDEX := -10
const KEYBOARD_P2_INDEX := -11

# Button & Axis mappings
const BUTTONS = {
	"U": JOY_BUTTON_DPAD_UP,
	"D": JOY_BUTTON_DPAD_DOWN,
	"L": JOY_BUTTON_DPAD_LEFT,
	"R": JOY_BUTTON_DPAD_RIGHT,
	
	"A": JOY_BUTTON_A,
	"B": JOY_BUTTON_B,
	"X": JOY_BUTTON_X,
	"Y": JOY_BUTTON_Y,
	
	"LB": JOY_BUTTON_LEFT_SHOULDER,
	"RB": JOY_BUTTON_RIGHT_SHOULDER,
	"LS": JOY_BUTTON_LEFT_STICK,
	"RS": JOY_BUTTON_RIGHT_STICK,
	
	"START": JOY_BUTTON_START,
	"SELECT": JOY_BUTTON_BACK
}

const axes = {
	"LT": JOY_AXIS_TRIGGER_LEFT,
	"RT": JOY_AXIS_TRIGGER_RIGHT,
}

const sticks = {
	"LS": [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y],
	"RS": [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y],
}

# Initialize
func _init(initial_setup:bool = false, enable_debug: bool = false) -> void:
	isDebug = enable_debug
	isSetup = initial_setup
	
	if isSetup:
		controllers = {}
	_check_controllers()
	_connect_signals()

func _connect_signals():
	gamepad_button_press.connect(_show_activity)
	gamepad_button_released.connect(_show_activity)
	gamepad_axis_changed.connect(_show_activity)
	gamepad_stick_changed.connect(_show_activity)
	controller_connected.connect(_show_activity)
	controller_disconnected.connect(_show_activity)
	player_disconnected.connect(_show_activity)

# Manual override for which controller index is active
func set_controller_index(index: int) -> void:
	active_controller_index = index
	if isDebug:
		print("Active controller set to index %d" % index)

# Detect new or removed controllers
func _check_controllers() -> void:
	var connected = Input.get_connected_joypads()
	for id in connected:
		if not prev_button_states.has(id):
			prev_button_states[id] = {}
			prev_axis_states[id] = {}
			prev_stick_states[id] = {}
			connected_controllers.append(id)
			if isDebug:
				print("Controller [%d]%s connected" % [id,Input.get_joy_name(id)])
			emit_signal("controller_connected", id)

	for id in prev_button_states.keys():
		if id not in connected:
			_on_controller_disconnected(id)

func _check_buttons(device_id: int) -> void:
	var player_index = controllers.get(device_id, device_id)
	for name in BUTTONS.keys():
		var button = BUTTONS[name]
		var pressed = Input.is_joy_button_pressed(device_id, button)
		var was_pressed = prev_button_states[device_id].get(button, false)
		
		
		prev_button_states[device_id][button] = pressed
		if isSetup and name != "START" and !controllers.has(device_id):
			#print("asdf")
			continue
		
		if pressed and not was_pressed:
			emit_signal("gamepad_button_press", ButtonData.new(name, player_index, device_id, true))
			if isDebug: print("Device %d (Player %d) pressed %s" % [device_id, player_index, name])
		elif not pressed and was_pressed:
			emit_signal("gamepad_button_released", ButtonData.new(name, player_index, device_id, false))


func _check_axes(device_id: int) -> void:
	var player_index = controllers.get(device_id, device_id)
	for axis_name in axes.keys():
		var axis_index = axes[axis_name]
		var value = Input.get_joy_axis(device_id, axis_index)
		if abs(value) < axis_deadzone:
			value = 0.0
		var prev = prev_axis_states[device_id].get(axis_name, 0.0)
		if abs(value - prev) > 0.01:
			prev_axis_states[device_id][axis_name] = value
			
			if isSetup:
				if !controllers.has(device_id):
					return
			
			emit_signal("gamepad_axis_changed", AxisData.new(axis_name, player_index, value))


func _check_stick(device_id: int) -> void:
	var player_index = controllers.get(device_id, device_id)
	for stick_name in sticks.keys():
		var stick_indices: Array = sticks[stick_name]
		var x = Input.get_joy_axis(device_id, stick_indices[0])
		var y = Input.get_joy_axis(device_id, stick_indices[1])
		if abs(x) < axis_deadzone: x = 0.0
		if abs(y) < axis_deadzone: y = 0.0
		var vec = Vector2(x, y)
		var prev_vec = prev_stick_states[device_id].get(stick_name, Vector2.ZERO)
		if vec.distance_to(prev_vec) > 0.01:
			prev_stick_states[device_id][stick_name] = vec
			
			if isSetup:
				if !controllers.has(device_id):
					return
			
			emit_signal("gamepad_stick_changed", StickData.new(stick_name, player_index, vec))

func _on_controller_disconnected(device_id: int) -> void:
	var player_index := -1
	if controllers.has(device_id):
		player_index = controllers[device_id]
		controllers.erase(device_id)
		if isDebug:
			print("Removed controller %d from player %d" % [device_id, player_index])
		emit_signal("player_disconnected", player_index, device_id)
	
	prev_button_states.erase(device_id)
	prev_axis_states.erase(device_id)
	prev_stick_states.erase(device_id)
	if device_id in connected_controllers:
		connected_controllers.erase(device_id)
	
	if isDebug:
		print("Controller %d disconnected" % device_id)
	emit_signal("controller_disconnected", device_id)

# Core loop
func handle_controller_input() -> void:
	_check_controllers()
	for id in prev_button_states.keys():
		_check_buttons(id)
		_check_axes(id)
		_check_stick(id)

# For keyboard-based pseudo-controllers
func handle_keyboard_input(action: String, virtual_index: int):
	if isDebug: print("Virtual controller %d pressed %s" % [virtual_index, action])
	emit_signal("gamepad_button_press", ButtonData.new(action, virtual_index, true))

# Assign a physical controller to a player slot
func assign_controller_to_player(device_index: int, player_index: int):
	controllers[device_index] = player_index
	if isDebug:
		print("Assigned Controller %d -> Player %d" % [device_index, player_index])

# Return controllers list
func get_connected_controllers() -> Array:
	return connected_controllers

func _show_activity(_arg1 = null, _arg2 = null, _arg3 = null, _arg4 = null):
	activity.emit()
	Events.gamepad_handler_activity.emit()
