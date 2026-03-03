class_name AxisData

var name: String ## name of the Axis
var index: int ## controller index
var value: float ## value of input

func _init(Name: String, Index: int, Value:float) -> void:
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
