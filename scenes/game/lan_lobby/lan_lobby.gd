extends Control
@onready var host: Button = $VBoxContainer/host
@onready var join: Button = $VBoxContainer/join

@onready var local_board: LocalBoard = $local_anchor/board
@onready var network_board: NetworkBoard = $network_anchor/board

var seed_val = -1

func _ready() -> void:
	GameManager.change_resolution(1280,720)
	_connect_signals()


func randomize_seed():
	seed_val = randi()

func _connect_signals() -> void:
	host.pressed.connect(func():
		print("hosting")
		NetworkServer.start()
		
		join.disabled = true
		randomize_seed()
		host.release_focus()
		local_board.initialize(seed_val)
		#local_board.start(3)
		)

	join.pressed.connect(func():
		print("joining")
		NetworkClient.start()
		host.disabled = true
		)
	
	#both sides
	Events.sync_interaction.connect(func(payload):
		#print("payload:", payload)
		pass
		var action = payload["action"]
		if action == "start_game":
			local_board.start(3)
		
		)
	
	Events.sync_data.connect(func(payload):
		print("payload: ", payload)
		var data = payload["data"]
		var action = data["action"]
		var seed = data["seed"]
		
		match action:
			"initialize_boards":
				local_board.initialize(seed)
		
		)
	
	#client side
	Events.client_connected.connect(func():
		#local_board.initialize(seed_val)
		NetworkClient.send_signal("join_lobby", {"data":GameManager.player_data})
		#local_board.start(2)
		#await get_tree().create_timer(5).timeout
		#local_board.get_all_board_tile_info()
		)
	Events.server_accepted_join.connect(func():
		network_board.initialze()
		pass
		)
	Events.server_rejected_join.connect(func():
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
		)
	
	#server side
	Events.client_joined_lobby.connect(func(payload):
		print("payload: ", payload)
		if NetworkServer.server_active:
			NetworkSync.sync_data({"action": "initialize_boards", "seed": seed_val})
		network_board.initialze()
		)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	if event.is_action_pressed("ready"):
		print("did i press?")
		NetworkSync.sync_interaction("start_game")

			#local_board.start(3)
