extends Control
@onready var board: Board = $Control/board
@onready var board1: Board = $test_board/board

func _ready() -> void:
	board.initialize_game_mode("marathon")
	board1.initialize_game_mode("marathon")
	
	board1.hide_queue()
	
	board.start(3)
	board1.start(3)
	
	var particle:AttackParticles = AttackParticles.create($GridContainer/Control2)
	particle.position = Vector2(500,500)
	add_child(particle)
	
	#await get_tree().process_frame
	#$GridContainer.force_update_transform()
	
	var p1 = $test_board
	var p2 = $test_board2
	print("p1",p1.position)
	print("p2",p2.position)

func _process(delta: float) -> void:
	var anchors = []
	var nodes = $GridContainer.get_children()
	for node:Control in nodes:
		var anchor = node.get_child(1)
		anchors.append(anchor)
	
	$test_board.global_position = $test_board.global_position.lerp(anchors[2].global_position, 5*delta)
	$test_board2.global_position = $test_board2.global_position.lerp(anchors[5].global_position, 5*delta)
