extends Control
@onready var host: Button = $VBoxContainer/host
@onready var join: Button = $VBoxContainer/join

func _ready() -> void:
	GameManager.change_resolution(1280,720)
	_connect_signals()

func _connect_signals() -> void:
	host.pressed.connect(func():
		print("hosting")
		NetworkServer.start()
		join.disabled = true
		)

	join.pressed.connect(func():
		print("joining")
		NetworkClient.start()
		host.disabled = true
		)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
		

	
