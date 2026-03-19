extends Panel
class_name ConfirmPrompt
const FILE = preload("uid://cilno8og0akis")

signal result(param) ## true = confirm, false = cancel

var _display_text = "Prompt"

@onready var message: Label = $Panel/Label
@onready var cancel: Button = $Panel/HBoxContainer/cancel
@onready var confirm: Button = $Panel/HBoxContainer/confirm

static func create(text:String) -> ConfirmPrompt:
	var obj: ConfirmPrompt = FILE.instantiate()
	obj._display_text = text
	return obj

func _ready() -> void:
	message.text = _display_text
	_connect_signals()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): # Usually Escape
		_on_canceled()
	elif event.is_action_pressed("ui_accept"): # Usually Enter/Space
		_on_confirmed()
	
	if !self.is_queued_for_deletion():
		get_viewport().set_input_as_handled()

func _connect_signals() -> void:
	cancel.pressed.connect(_on_canceled)
	confirm.pressed.connect(_on_confirmed)

func _on_canceled() -> void:
	print("cancelled")
	result.emit(false)
	queue_free()

func _on_confirmed() -> void:
	result.emit(true)
	queue_free()
	
