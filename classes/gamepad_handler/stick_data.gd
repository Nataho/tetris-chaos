class_name StickData

var name: String # name of Stick
var index: int # controller index
var value: Vector2 # value of inputs

func _init(Name: String, Index: int, Value:Vector2) -> void:
	name = Name
	index = Index
	value = Value

func print_values():
	var values = {
		"name": name,
		"index": index,
		"value": value
	}
	print(values)
