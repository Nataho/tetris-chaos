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
@export var ranked:Button
@export var classic:Button

@export_group("Settings")
@export var controls:Button
@export var handling:Button
@export var change_server:Button

enum tabs {MAIN, MULTIPLAYER, SETTINGS}
enum settings_tabs {CONTROLS,HANDLING}
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
#@onready var main_nodes := [
	#
#]



@onready var settings_nodes := [
	$settings/right_side/controls,
	$settings/right_side/handling,
]

func _ready() -> void:
	#display_input_Key(%test,"soft_drop")
	if OS.get_name() == "Android":
		$Multiplayer/empty_space/VBoxContainer/local_versus.hide()
	
	
	for i in range(get_children().size()):
		if i <2: continue
		
		get_child(i).hide()
	
	$main.show()
	
	Audio.play_music("main_menu")
	#Audio.music_player_node.stream = Audio.music["main_menu"][0]
	#Audio.music_player_node.play()
	change_background(Color("a000f0"))
	connect_buttons()
	setup_version_label()
	
func setup_version_label():
	var version = str(GameManager.game_version)
	var dev_build = "dev " if GameManager.dev_build else ""
	
	$Label.text = "version: %s%s" % [dev_build, version]
	$Label.show()

func change_background(color:Color):
	target_color = color

func _physics_process(delta: float) -> void:
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
	
	controls.pressed.connect(func():
		change_settings_display(settings_tabs.CONTROLS)
		)
	handling.pressed.connect(func():
		change_settings_display(settings_tabs.HANDLING)
		)
	
	local_versus.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/game/local_multiplayer/local_multiplayer.tscn")
		)
	
	lan.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/game/new_lan_lobby/lan_lobby.tscn")
		)
	
	Events.android_back_pressed.connect(_back)
	
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
