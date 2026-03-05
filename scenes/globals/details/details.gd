extends Control
@onready var label: Label = $Label

func _process(delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var text = "FPS: %d" % fps 
	label.text = text
	pass
