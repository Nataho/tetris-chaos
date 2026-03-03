class_name ButtonData

var name: String ## name of the button
var device_index: int ## controller index
var player_index: int
var value: float ## value of input

@warning_ignore("shadowed_variable")
func _init(Name, Index: int, device_index: int, IsPressed = false) -> void:
	
	if IsPressed:
		IsPressed = 1.0
	else:
		IsPressed = 0.0
	
	name = Name 
	self.device_index = device_index
	player_index = Index
	value = IsPressed
