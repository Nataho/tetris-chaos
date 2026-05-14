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
	
	#await get_tree().create_timer(1).timeout

func _process(delta: float) -> void:
	
	var fg_modulate := foreground.modulate
	fg_modulate = fg_modulate.lerp(fg_target_color, 7*delta)
	foreground.modulate = fg_modulate

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
	var response = await TCPBridge.active_bridge.server_response
	if response.get("type") == "room_created":
		_open_foreground("room has created")
	
