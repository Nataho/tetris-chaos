extends CPUParticles2D
class_name SpinParticle
const file = preload("uid://b6qkt6s4j357r")

var has_entered_scene:bool = false
var diffuse_timer:float = 0.25

static func create(clockwise:bool) -> SpinParticle:
	var obj:SpinParticle = file.instantiate()
	
	if clockwise: 
		obj.orbit_velocity_min = -2
		obj.orbit_velocity_max = 0
	else:
		obj.orbit_velocity_min = 0
		obj.orbit_velocity_max = 2
	
	obj.emitting = true
	return obj

func _ready() -> void:
	has_entered_scene = true

	if emitting == false:
		queue_free()

func _physics_process(delta: float) -> void:
	if !has_entered_scene: return
	
	orbit_velocity_min = lerpf(orbit_velocity_min,0,0.01)
	orbit_velocity_max = lerpf(orbit_velocity_max,0,0.01)
	
	if emitting == false:
		queue_free()
