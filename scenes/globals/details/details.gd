extends Control
@onready var fps_label: Label = $fps
@onready var ping_label: Label = $ping


func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var text = "FPS: %d" % fps 
	fps_label.text = text

func show_ping(ping:int = -1):
	if ping == -1:
		ping_label.text = ""
		return
	
	var text = "Ping: %d" % ping
	
	ping_label.text = text
