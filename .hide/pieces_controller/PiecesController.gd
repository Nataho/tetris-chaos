extends Node
class_name PiecesController

var spawn_pos: Vector2i
var drop_time: float
var turns_to_sac: int

# Structure: { TestIndex: [Rot0, Rot1, Rot2, Rot3] }
static var JLSTZ_OFFSET_DATA: Dictionary = {
	0: [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO],
	1: [Vector2i.ZERO, Vector2i(1, 0), Vector2i.ZERO, Vector2i(-1, 0)],
	2: [Vector2i.ZERO, Vector2i(1, 1), Vector2i.ZERO, Vector2i(-1, 1)],
	3: [Vector2i.ZERO, Vector2i(0, -2), Vector2i.ZERO, Vector2i(0, -2)],
	4: [Vector2i.ZERO, Vector2i(1, -2), Vector2i.ZERO, Vector2i(-1, -2)]
}

static var I_OFFSET_DATA: Dictionary = {
	0: [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1)],
	1: [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, -1), Vector2i(0, -1)],
	2: [Vector2i(2, 0), Vector2i.ZERO, Vector2i(-2, -1), Vector2i(0, -1)],
	3: [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1)],
	4: [Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2)]
}

static var O_OFFSET_DATA: Dictionary = {
	0: [Vector2i.ZERO, Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
}

# No need for _set_offset_data() anymore!
func _ready() -> void:
	pass
