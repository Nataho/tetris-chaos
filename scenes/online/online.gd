extends Control

@onready var background: ColorRect = $bg
@onready var foreground: Panel = $fg
@onready var foreground_message: RichTextLabel = $fg/message


var fg_target_color := Color.TRANSPARENT

func setup_startup():
	foreground.show()
	foreground.modulate.a = 0

func _ready() -> void:
	setup_startup()
	_connect_to_server()
	
	Events.android_back_pressed.connect(func(): back())
	#await get_tree().create_timer(1).timeout

func _process(delta: float) -> void:
	
	var fg_modulate := foreground.modulate
	fg_modulate = fg_modulate.lerp(fg_target_color, 7*delta)
	foreground.modulate = fg_modulate

func _input(event: InputEvent) -> void:
	if GameManager.is_prompt_open: return
	if event.is_action_pressed("ui_cancel"):
		back()
		get_viewport().set_input_as_handled()


func _connect_to_server():
	var connected = false
	
	# Optional: Give Autoloads a split second to initialize if active_bridge is null
	if TCPBridge.active_bridge == null:
		await get_tree().process_frame
		
	while !connected:
		# 1. Check FIRST if we are already connected
		if TCPBridge.active_bridge.is_connected_to_server:
			_close_foreground() # Silently clear any loading screens
			connected = true
			break # Exit the loop immediately!
			
		# 2. If we are NOT connected, show the message and attempt to connect
		_open_foreground("connecting to server...")
		TCPBridge.restart() 
		
		# Wait for the signal to emit (either true or false)
		var is_online = await TCPBridge.active_bridge.connection_status_changed
		
		# 3. Handle the result of the attempt
		if is_online:
			_close_foreground("found server!")
			connected = true
			# Add a tiny delay so the player can actually read "found server!"
			await get_tree().create_timer(0.5).timeout 
			
		else:
			_close_foreground("server not found")
			var prompt := ConfirmPrompt.create("server not found or disconnected", ["no_cancel"])
			add_child(prompt)
			await prompt.result # Wait for player to press OK
			# Once they press OK, the while loop automatically restarts at the top!

func _open_foreground(message:String):
	
	foreground_message.text = message
	
	fg_target_color = Color.WHITE

func _update_foreground_message():
	pass

func _close_foreground(message:String = ""):
	if message != "":
		foreground_message.text = message
		
	fg_target_color = Color.TRANSPARENT

func create_room():
	TCPBridge.create_room()
	
	# 1. Protection against the "Wrong Response" trap
	var response = {}
	while true:
		response = await TCPBridge.active_bridge.server_response
		if response.get("type") == "room_created":
			break
			
	# 2. THE BIG FIX: Use str(), not int(). 
	# Server sent "031606". int() would turn it into 31606.
	var room_id = str(response.get("room_id"))
	
	# Set host status so the Room scene knows to show "Start Game" buttons
	TCPBridge.active_bridge._is_host = true 
	
	enter_room(room_id)

func join_room():
	var prompt := ConfirmPrompt.create("Enter Room ID", ["input"])
	add_child(prompt)
	var result = await prompt.result
	
	if result["result"]:
		# 1. Keep as String to preserve leading zeros (e.g., "001234")
		var target_id = str(result.get("value")).strip_edges()
		
		if target_id.is_empty():
			return
			
		_open_foreground("Joining room " + target_id + "...")
		
		# 2. Tell Python we want to join
		TCPBridge.join_room(target_id)
		
		# 3. Wait for the server to confirm if we actually got in
		var response = {}
		while true:
			response = await TCPBridge.active_bridge.server_response
			if response.get("type") == "join_response":
				break
		
		# 4. Handle the result
		if response.get("success", false) == true:
			# Success! Save the info globally and enter
			TCPBridge.set_room_id(target_id)
			#TCPBridge.is_host = false 
			
			_close_foreground("Joined!")
			await get_tree().create_timer(0.5).timeout
			get_tree().change_scene_to_file("res://scenes/online/room/room.tscn")
		else:
			# Failure (Room full, room doesn't exist, etc.)
			_close_foreground("Could not join room")
			var error_msg = response.get("message", "Room not found or full.")
			var error_prompt := ConfirmPrompt.create(error_msg, ["no_cancel"])
			add_child(error_prompt)
			
	#get_tree().change_scene_to_file("res://scenes/online/room/room.tscn")

func enter_room(room_id: String): # Explicitly a String
	_open_foreground("entering room")
	TCPBridge.set_room_id(room_id)
	
	# Give the UI half a second to breathe
	await get_tree().create_timer(0.5).timeout 
	get_tree().change_scene_to_file("res://scenes/online/room/room.tscn")

func back():
	GameManager.is_prompt_open = true
	
	var prompt := ConfirmPrompt.create("Are you sure you want to exit the lobby?")
	add_child(prompt)
	
	var confirmed = await prompt.result
	
	if confirmed:
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	
	GameManager.is_prompt_open = false
