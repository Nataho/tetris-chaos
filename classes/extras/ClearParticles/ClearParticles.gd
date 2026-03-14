extends CPUParticles2D
class_name ClearParticle

const FILE = preload("uid://f08e0rrudit0")

var has_entered_scene:bool = false
var diffuse_timer:float = 0.25

static func create() -> ClearParticle:
	var obj:ClearParticle = FILE.instantiate()
	
	obj.emitting = true
	return obj

func _ready() -> void:
	has_entered_scene = true

	if emitting == false:
		queue_free()

func _physics_process(_delta: float) -> void:
	if !has_entered_scene: return
	
	#orbit_velocity_min = lerpf(orbit_velocity_min,0,0.01)
	#orbit_velocity_max = lerpf(orbit_velocity_max,0,0.01)
	
	if emitting == false:
		queue_free()
