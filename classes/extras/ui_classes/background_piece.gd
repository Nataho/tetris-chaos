extends Node2D
class_name BackgroundPiece

@onready var timer: Timer = $Timer

var current_rotation_index: int = 0
var rotations = [0, 90, 180, 270]
var max_time:float = 1.0

# Adjust this to change how fast it spins
@export var rotation_speed: float = 5.0 

func _ready() -> void:
	# No need to pass 'false' manually, it's the default
	timer.timeout.connect(turn)
	start_random_timer()

func _physics_process(delta: float) -> void:
	var target_deg = rotations[current_rotation_index]
	
	# lerp_angle uses radians, so we convert for smooth "shortest path" rotation
	var target_rad = deg_to_rad(target_deg)
	rotation = lerp_angle(rotation, target_rad, rotation_speed * delta)

func turn():
	# Wrap index using modulo (%) for cleaner code
	# This picks -1, 0, or 1 and wraps it between 0-3
	var move = randi_range(-1, 1)
	current_rotation_index = posmod(current_rotation_index + move, 4)
	
	start_random_timer()

func start_random_timer():
	timer.start(randf_range(0.5, max_time))
