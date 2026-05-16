extends Panel
class_name ConfirmPrompt
const FILE = preload("uid://cilno8og0akis")

signal result(param) ## true = confirm, false = cancel

var _has_input_field = false
var _has_secret_input_field = false
var _no_cancel = false
var _size_up = false

var _display_text:String = "Prompt"
var _input_field_text:String = ""
@onready var message: Label = $Panel/Label
@onready var cancel: Button = $Panel/HBoxContainer/cancel
@onready var confirm: Button = $Panel/HBoxContainer/confirm
@onready var input: LineEdit = $Panel/input


static func create(text:String, flags:Array[String] = []) -> ConfirmPrompt:
	var obj: ConfirmPrompt = FILE.instantiate()
	obj._display_text = text
	
	for flag in flags:
		match flag:
			"input": obj._has_input_field = true
			"secret_input": obj._has_secret_input_field = true
			"no_cancel": obj._no_cancel = true
			#"size_up": obj._size_up = true
			
	return obj

func _ready() -> void:
	message.text = _display_text
	
	_check_flags()
	_connect_signals()

func _check_flags():
	if _has_secret_input_field: 
		_has_input_field = true
		input.secret = true
	if !_has_input_field: input.hide()
	if _no_cancel: cancel.hide()
	#if _size_up: _size_up_prompt_box()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): # Usually Escape
		_on_canceled()
	elif event.is_action_pressed("ui_accept"): # Usually Enter/Space
		_on_confirmed()
	
	if !self.is_queued_for_deletion():
		get_viewport().set_input_as_handled()

func _input_field_changed(text:String):
	_input_field_text = text

func _connect_signals() -> void:
	cancel.pressed.connect(_on_canceled)
	confirm.pressed.connect(_on_confirmed)
	input.text_changed.connect(_input_field_changed)

func _on_canceled() -> void:
	print("cancelled")
	
	if input.visible:
		result.emit({
			"result": false,
			"value": "none"
		})
	else: result.emit(false)
	
	queue_free()

func _on_confirmed() -> void:
	if input.visible:
		result.emit({
			"result": true,
			"value": _input_field_text
		})
	else: result.emit(true)
	
	queue_free()

#func _size_up_prompt_box() -> void:
	
