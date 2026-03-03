extends Node2D

var i := {
	"piece":[Vector2i(0,2), Vector2i(1,2), Vector2i(2,2), Vector2i(3,2)],
	"pivot_index":2
}

@onready var layer_board := $board
@onready var layer_piece :TileMapLayer= $piece
@onready var timer: Timer = $Timer

func _ready() -> void:
	$board.start()
