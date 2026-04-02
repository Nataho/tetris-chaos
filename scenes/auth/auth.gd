extends Control

# ==========================================
# NODES
# ==========================================
@onready var login_username_field: LineEdit = $login_panel/vbox/username
@onready var login_password_field: LineEdit = $login_panel/vbox/password
@onready var login_confirm_button: Button = $login_panel/confirm
@onready var login_message: Label = $login_panel/message

@onready var signup_username_field: LineEdit = $signup_panel/vbox/username
@onready var signup_password_field: LineEdit = $signup_panel/vbox/password
@onready var signup_confirm_button: Button = $signup_panel/confirm
@onready var signup_message: Label = $signup_panel/message

# ==========================================
# VARIABLES
# ==========================================
var username: String = "GUEST"
var password: String = ""
var is_guest: bool = true

# ==========================================
# INITIALIZATION
# ==========================================
func _ready() -> void:
	_connect_signals()
	TCPBridge.active_bridge.start()

func _connect_signals() -> void:
	# UI Signals (Wired up for both login and signup!)
	login_username_field.text_changed.connect(_username_changed.bind(login_username_field))
	login_password_field.text_changed.connect(_password_changed)
	login_confirm_button.pressed.connect(login)
	
	signup_username_field.text_changed.connect(_username_changed.bind(signup_username_field))
	signup_password_field.text_changed.connect(_password_changed)
	signup_confirm_button.pressed.connect(signup)
	
	# Network Signal: Connect this ONCE, globally.
	TCPBridge.active_bridge.server_response.connect(_on_server_response)


# ========================================== 
# INPUT HANDLING
# ==========================================
# By passing the node via .bind(), we can reuse this function for both Login and Signup!
func _username_changed(new_text: String, node: LineEdit) -> void:
	# Clean the text in one pass instead of multiple checks
	var clean_text := new_text.replace(" ", "").to_upper()
	
	# Only update the LineEdit if we actually changed something to avoid infinite signal loops
	if clean_text != new_text:
		var cursor_pos := node.caret_column
		node.text = clean_text
		# Adjust cursor so it doesn't jump to the end unnecessarily 
		node.caret_column = max(0, cursor_pos - (new_text.length() - clean_text.length()))
	
	username = clean_text if not clean_text.is_empty() else "GUEST"

func _password_changed(new_text: String) -> void:
	password = new_text
	is_guest = password.is_empty()

# ==========================================
# NETWORK REQUESTS
# ==========================================
func login() -> void:
	show_message(login_message, "Logging in...", Color.YELLOW)
	TCPBridge.send_login_request(username, password)

func signup() -> void:
	show_message(signup_message, "Signing up...", Color.YELLOW)
	TCPBridge.send_signup_request(username, password)

# ==========================================
# NETWORK RESPONSES
# ==========================================
func _on_server_response(response: Dictionary) -> void:
	var response_type: String = response.get("type", "null")
	var server_msg: String = response.get("message", "server error")
	var success: bool = response.get("success", false)
	var text_color: Color = Color.CYAN if success else Color.RED
	
	# Route the response to the correct UI panel
	print("color: ", text_color)
	match response_type:
		"login_response":
			show_message(login_message, server_msg, text_color)
			if success:
				print("Proceed to game lobby!") # Add your scene transition here
		"signup_response":
			show_message(signup_message, server_msg, text_color)
		_:
			print("[WARNING] Unhandled server response: ", response_type)

# ==========================================
# UI HELPERS
# ==========================================
func show_message(node: Label, text: String, color: Color) -> void:
	if text.is_empty():
		node.hide()
		return
		
	node.text = text
	
	# OVERRIDE the theme color, do not modify LabelSettings!
	node.label_settings.font_color = color
	node.show()
