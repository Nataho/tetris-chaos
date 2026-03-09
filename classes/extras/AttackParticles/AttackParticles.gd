extends CPUParticles2D
class_name AttackParticles

const _FILE = preload("uid://c4pbpcjtu32w6")
var _target: Node = null # opponent
var _wait_time: float = 0.12 
var _target_pos: Vector2
var _spawn_pos: Vector2 
var _target_offset: Vector2 = Vector2(30* -6, 30*10)

# Arc Math Variables
var _is_homing: bool = false 
var _t: float = 0.0
var _t_speed: float = 0.5 
var _p0: Vector2
var _p1: Vector2

static func create(target: Node) -> AttackParticles:
	var obj: AttackParticles = _FILE.instantiate()
	obj._target = target
	return obj

func _ready() -> void: 
	_spawn_pos = global_position # Save the origin point
	
	var x = randf_range(-120, 120) 
	var y = randf_range(-120, 120)
	_target_pos = global_position + Vector2(x, y)
	
	modulate.a = 0.0 
	
	var tween = create_tween()
	# Changed 0.25 to 0.10 here!
	tween.tween_property(self, "modulate:a", 0.10, _wait_time)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		queue_free()
		return

	if _wait_time > 0:
		# PHASE 1: The "Burst" 
		_wait_time -= delta
		global_position = global_position.lerp(_target_pos, 15.0 * delta) 
	else:
		# Calculate the exact spot we want to hit
		var actual_target_pos = _target.global_position + _target_offset
		
		# --- TRANSITION LOGIC ---
		if not _is_homing:
			_is_homing = true
			_p0 = global_position 
			
			var burst_dir = (_p0 - _spawn_pos).normalized()
			# Change to actual_target_pos
			var dist_to_target = _p0.distance_to(actual_target_pos)
			
			_p1 = _p0 + (burst_dir * dist_to_target * 0.6)
			
		# PHASE 2: The "Homing Arc"
		_t_speed += delta * 3.5 
		_t += _t_speed * delta
		
		if _t >= 1.0:
			_t = 1.0
			set_physics_process(false)
			emitting = false
			await get_tree().create_timer(lifetime).timeout
			queue_free()
			return
		
		# --- QUADRATIC BEZIER MATH ---
		var q0 = _p0.lerp(_p1, _t)
		# Change to actual_target_pos
		var q1 = _p1.lerp(actual_target_pos, _t) 
		global_position = q0.lerp(q1, _t)
		
		# --- DISTANCE-BASED FADE ---
		var ease_late_progress = _t * _t 
		modulate.a = lerp(0.10, 1.0, ease_late_progress)
