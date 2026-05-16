extends Control

@export_group("Main")
@onready var background: ColorRect = $background
@export var marathon:Button
@export var zen:Button
@export var multiplayer_button:Button
@export var settings:Button

@export_group("Multiplayer")
@export var local_versus:Button
@export var lan:Button
@export var online:Button
@export var classic:Button

@export_group("Settings")
@export var controls:Button
@export var handling:Button
@export var graphics:Button
@export var account:Button

#temporary enums, will be automated via index when finished with settings
enum tabs {MAIN, MULTIPLAYER, SETTINGS}
enum settings_tabs {CONTROLS,HANDLING,GRAPHICS,ACCOUNT}
enum multiplayer_tabs {LOCAL_VERSUS, LAN, RANKED, CLASSIC}

var current_tab = tabs.MAIN
var current_settings_tab = settings_tabs.CONTROLS
var current_multiplayer_tab = multiplayer_tabs.LOCAL_VERSUS

var target_color:Color
#var current_settings_tab
@onready var tab_nodes := [
	$main,
	$Multiplayer,
	$settings,
]

@onready var settings_nodes := [
	$settings/right_side/controls,
	$settings/right_side/handling,
	$settings/right_side/graphics,
	$settings/right_side/account
]

@onready var window_mode_button: Button = $settings/right_side/graphics/window_mode/button

const default_messages = {
	"default": "submit password to login/signup\nno password = guest"
}

var password:String = ""
var is_guest:bool = true
var is_login:bool


func _ready() -> void:
	TCPBridge.active_bridge.start()
	
	#display_input_Key(%test,"soft_drop")
	if OS.get_name() == "Android":
		$Multiplayer/empty_space/VBoxContainer/local_versus.hide()
	
	
	for i in range(get_children().size()):
		if i <2: continue
		
		get_child(i).hide()
	
	$main.show()
	
	Audio.play_music("title_screen")
	#Audio.music_player_node.stream = Audio.music["main_menu"][0]
	#Audio.music_player_node.play()
	change_background(Color("a000f0"))
	connect_buttons()
	setup_version_label()
	#var player_data = GameManager.player_data
	#TCPBridge.update_high_score(player_data["uid"], player_data["high_score"])
	
	await get_tree().create_timer(0.2).timeout
	load_account()
	
func setup_version_label():
	var version = str(GameManager.GAME_VERSION)
	var dev_build = "dev " if GameManager.dev_build else ""
	
	$Label.text = "version: %s%s" % [dev_build, version]
	$Label.show()

func change_background(color:Color):
	target_color = color

func _physics_process(_delta: float) -> void:
	background.color = background.color.lerp(target_color, 0.1)

func connect_buttons():
	marathon.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/game/marathon/marathon.tscn")
		)
	multiplayer_button.pressed.connect(func():
		change_tab(tabs.MULTIPLAYER)
		)
	settings.pressed.connect(func():
		change_tab(tabs.SETTINGS)
		)
	
	
	window_mode_button.pressed.connect(func():
		var text = Tools.cycle_window_mode()
		window_mode_button.text = text
		)
	
	#settings
	controls.pressed.connect(func():
		change_settings_display(settings_tabs.CONTROLS)
		)
	handling.pressed.connect(func():
		change_settings_display(settings_tabs.HANDLING)
		)
	graphics.pressed.connect(func():
		change_settings_display(settings_tabs.GRAPHICS)
		)
	account.pressed.connect(func():
		change_settings_display(settings_tabs.ACCOUNT)
		)
	
	local_versus.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/game/local_multiplayer/local_multiplayer.tscn")
		)
	
	lan.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/game/new_lan_lobby/lan_lobby.tscn")
		)
	
	online.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/online/online.tscn")
		)
	
	%username_edit.text_changed.connect(func(text:String): settings_username_changed(text,%username_edit))
	%password_edit.text_changed.connect(settings_password_changed)
	%password_edit.text_submitted.connect(settings_login_signup)
	%logout_button.pressed.connect(logout)
	%delete_button.pressed.connect(delete)
	Events.android_back_pressed.connect(_back)

func load_account():
	var local_uid = GameManager.player_data.get("uid", -1)
	var local_name = GameManager.player_data.get("name", "GUEST")
	var local_score = GameManager.player_data.get("high_score", 0)
	var local_status = GameManager.player_data.get("status", "guest")

	# 1. CHECK IF CONNECTED
	if TCPBridge.active_bridge.is_connected_to_server:
		print("Server connected. Syncing data...")

		# 2. UPLOAD HIGH SCORE FIRST (if not a guest)
		if str(local_uid) not in ["-1", "0"] and local_status != "guest":
			TCPBridge.update_high_score(local_uid, local_score)
			# Brief wait for server processing
			await get_tree().create_timer(0.1).timeout 

		# 3. GET PLAYER INFO TO REFRESH STATS
		TCPBridge.get_player_info(local_name)
		var server_data = await TCPBridge.active_bridge.server_response
		
		if server_data.get("success", false):
			print("Online data retrieved. Applying stats.")
			TCPBridge.refresh_login(local_uid)
			logged_in(server_data)
			return # Exit early: online sync complete
		else:
			print("Server info fetch failed. Using local fallback.")

	# 4. OFFLINE FALLBACK
	# We manually build a dictionary from local data to pass to logged_in
	print("Offline: Applying local settings.")
	var offline_data = {
		"uid": local_uid,
		"status": GameManager.player_data.get("status", "guest"),
		"highscore": local_score
	}
	logged_in(offline_data)
	

func settings_username_changed(new_text: String, node: LineEdit) -> void:
	# Clean the text in one pass instead of multiple checks
	var clean_text := new_text.replace(" ", "").to_upper()
	
	# Only update the LineEdit if we actually changed something to avoid infinite signal loops
	if clean_text != new_text:
		var cursor_pos := node.caret_column
		node.text = clean_text
		# Adjust cursor so it doesn't jump to the end unnecessarily 
		node.caret_column = max(0, cursor_pos - (new_text.length() - clean_text.length()))
	
	GameManager.player_data["name"] = clean_text if not clean_text.is_empty() else "GUEST"
	GameManager.SAVE_GAME()

func settings_password_changed(new_text: String) -> void:
	password = new_text
	is_guest = password.is_empty()

func settings_login_signup(text:String):
	print("Checking if account exists...")
	%account_note.text = "Checking account..."
	
	# 1. CHECK IF ACCOUNT EXISTS FIRST
	TCPBridge.get_player_info(GameManager.player_data["name"])
	var info_response = await TCPBridge.active_bridge.server_response
	
	# 2. IF ACCOUNT EXISTS -> LOGIN
	if info_response.get("success", false) == true:
		print("Account found. Logging in...")
		%status_status.text = "Logging in..."
		
		# --- NEW: UPGRADE GUEST ACCOUNT PASSWORD CONFIRMATION ---
		if info_response.get("status") == "guest" and !password.is_empty():
			var prompt := ConfirmPrompt.create("Confirm Password to Upgrade", ["secret_input"])
			add_child(prompt)
			var prompt_result = await prompt.result
			
			if !prompt_result:
				%status_status.text = "OFFLINE"
				%account_note.text = default_messages.default
				return
				
			if prompt_result["value"] != password and prompt_result["result"]:
				var prompt_2 = ConfirmPrompt.create("Different passwords!", ["no_cancel"])
				add_child(prompt_2)
				%status_status.text = "OFFLINE"
				%account_note.text = default_messages.default
				return
			
			if !prompt_result["result"]:
				%status_status.text = "OFFLINE"
				%account_note.text = default_messages.default
				return
		# --------------------------------------------------------
		
		TCPBridge.send_login_request(GameManager.player_data["name"], password)
		var login_response = await TCPBridge.active_bridge.server_response
		
		var status_code = login_response.get("status_code", 200) 
		
		if status_code == 201 or status_code == 200: #success
			var status_message = ""
			var user_status = login_response.get("user_status", "guest")
			
			match user_status:
				"registered": status_message = "Logged in"
				"banned": status_message = "banned"
				_: status_message = "guest"
			
			%status_status.text = status_message
			%account_note.text = default_messages.default # Clear any previous error text
			print("info response: ", info_response)
			login_response["highscore"] = info_response.get("highscore",0)
			logged_in(login_response)
		else:
			var passwd_prompt = ConfirmPrompt.create(login_response.get("message", "Client Error"), ["no_cancel"])
			add_child(passwd_prompt)
			%status_status.text = "OFFLINE"
			await passwd_prompt.result
			
			%account_note.text = login_response.get("message", default_messages.default)

	# 3. IF ACCOUNT DOES NOT EXIST -> REGISTER
	else:
		print("Account not found. Automatically registering...")
		%status_status.text = "Signing up"
		
		if !password.is_empty():
			var prompt := ConfirmPrompt.create("Confirm Password", ["secret_input"])
			add_child(prompt)
			var prompt_result = await prompt.result
			
			if !prompt_result:
				%status_status.text = "OFFLINE"
				%account_note.text = default_messages.default
				return
				
			if prompt_result["value"] != password and prompt_result["result"]:
				var prompt_2 = ConfirmPrompt.create("Different passwords!", ["no_cancel"])
				add_child(prompt_2)
				%status_status.text = "OFFLINE"
				%account_note.text = default_messages.default
				return
			
			if !prompt_result["result"]:
				%status_status.text = "OFFLINE"
				%account_note.text = default_messages.default
				return
		
		TCPBridge.send_signup_request(GameManager.player_data["name"], password)
		var signup_response = await TCPBridge.active_bridge.server_response
		
		var status_code = signup_response.get("status_code", 200)
		
		if status_code == 201 or status_code == 200:
			%status_status.text = "Logged in" if !password.is_empty() else "guest"
			var prompt_3 = ConfirmPrompt.create(signup_response.get("message", "Signed up successfully!"), ["no_cancel"])
			%account_note.text = default_messages.default
			logged_in(signup_response)
		else:
			%account_note.text = signup_response.get("message", "Signup failed.")

func delete():
	var prompt := ConfirmPrompt.create("Are you sure? This cannot be undone.")
	add_child(prompt)
	var result = await prompt.result
	if !result: return
	
	var prompt2 := ConfirmPrompt.create("Enter password to confirm deletion", ["secret_input"])
	add_child(prompt2)
	var result2 = await prompt2.result
	if !result2.get("result"): return
	
	# 1. Re-authenticate
	TCPBridge.send_login_request(GameManager.player_data["name"], result2.get("value"))
	
	# SIFTING LOGIC: Wait for login_response
	var auth_success = false
	while true:
		var res = await TCPBridge.active_bridge.server_response
		if res.get("type") == "login_response":
			auth_success = res.get("success", false)
			break
	
	if auth_success:
		# 2. Re-auth passed, send delete command
		TCPBridge.delete_account()
		
		# SIFTING LOGIC: Wait for delete_response
		var delete_success = false
		while true:
			var del_res = await TCPBridge.active_bridge.server_response
			if del_res.get("type") == "delete_response":
				delete_success = del_res.get("success", false)
				break
		
		if delete_success:
			# 3. Purge local cache and exit
			GameManager.player_data = {"name": "Guest", "uid": -1}
			GameManager.SAVE_GAME()
			get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
		else:
			var err := ConfirmPrompt.create("Server failed to delete account.", ["no_cancel"])
			add_child(err)
	else:
		var prompt3 := ConfirmPrompt.create("Incorrect password.", ["no_cancel"])
		add_child(prompt3)
		

func logout(): 
	#TCPBridge.get_player_info("Nataho")
	var player_data = {
		"uid": "",
		"name": "guest",
		"high_score": 0,
		"marathon_level": 1,
		"status": "guest"
	}
	GameManager.player_data = player_data
	%uid.hide(); $settings/right_side/account/password.show()
	%delete.hide()
	%username_edit.editable = true
	%password_edit.editable = true
	%logout_button.disabled = true
	
	%status_status.text = "OFFLINE"
	%username_edit.text = ""
	%password_edit.text = ""
	
	print("player has logged out")

func logged_in(player_data: Dictionary):
	# Update GameManager with server or local fallback data
	GameManager.player_data["uid"] = int(player_data.get("uid", -1))
	
	if player_data.has("status"):
		GameManager.player_data["status"] = player_data.get("status", "guest")
	elif player_data.has("user_status"):
		GameManager.player_data["status"] = player_data.get("user_status", "guest")
	
	# Check both possible key names for high score
	if player_data.has("highscore"):
		GameManager.player_data["high_score"] = int(player_data["highscore"])
	elif player_data.has("high_score"):
		GameManager.player_data["high_score"] = int(player_data["high_score"])
		
	GameManager.SAVE_GAME()
	
	# --- UI UPDATES ---
	%username_edit.text = GameManager.player_data["name"]
	%uid_label.text = str(GameManager.player_data["uid"])
	%status_status.text = GameManager.player_data["status"].to_upper()
	
	# If we have a valid UID, lock the account UI
	if str(GameManager.player_data["uid"]) != "-1":
		%uid.show()
		$settings/right_side/account/password.hide()
		%delete.show()
		%username_edit.editable = false
		%password_edit.editable = false
		%logout_button.disabled = false
		
	else:
		# Keep fields open for guests/new logins
		%uid.hide()
		%delete.hide()
		$settings/right_side/account/password.show()
		%logout_button.disabled = true

func show_account_status(node: Label, text: String, color: Color) -> void:
	if text.is_empty():
		node.hide()
		return
		
	node.text = text
	
	node.label_settings.font_color = color
	node.show()
	
func change_tab(tab:tabs):
	for node in tab_nodes:
		node.hide()
	
	tab_nodes[tab].show()
	current_tab = tab
	
	match tab:
		tabs.MAIN:
			change_background(Color("a000f0"))
		tabs.SETTINGS:
			change_background(Color.YELLOW)
		tabs.MULTIPLAYER:
			change_background(Color.BLUE)

func change_settings_display(tab:settings_tabs):
	for node in settings_nodes:
		node.hide()
	
	settings_nodes[tab].show()
	current_settings_tab = tab

func _input(event: InputEvent) -> void:
	if GameManager.is_prompt_open: return
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()

func _back():
	if current_tab > 0:
		change_tab(tabs.MAIN)
	else:
		GameManager.is_prompt_open = true
		
		var prompt := ConfirmPrompt.create("You don't wanna play anymore??")
		add_child(prompt)
		
		var confirmed = await prompt.result
		
		if confirmed:
			get_tree().quit()
			
		GameManager.is_prompt_open = false


#[TEST]
#func test():
	#InputMap.erase_action("hard_drop")
	#
	#var new_event := InputEventKey.new()
	#
	#new_event.physical_keycode = 
	#
