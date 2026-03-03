extends Board
class_name MultiplayerBoard

signal knocked_out(node: MultiplayerBoard)

@onready var anim: AnimationPlayer = $AnimationPlayer


var kos: int = 0
var center_pos = Vector2.ZERO

#region shake variables
signal shake_finished
var _initial_position: Vector2
var _shake_tween: Tween
#endregion shake variables

func set_player(player_index:int):
	_player_index = player_index

#func _super_ready() -> void:
	#print("huh?")

func _super_reset() -> void:
	anim.play("RESET")
	#position = Vector2(0,0)
	#modulate = Color(1,1,1,1)
#func _super_physics_process(_delta) -> void:
	#position = center_pos

func _check_ko(payload):
	#print("checking knockout")
	var KO_credit = payload["knockout_credit"] #player who gets the credit
	var kod_id = payload["player_id"] #player who toped out
	
	if KO_credit == _player_index:
		kos += 1
		push_warning("player %d, has kod player, %d" % [_player_index, kod_id])
	elif kod_id == _player_index:
		Audio.play_sound("topout")
		knocked_out.emit(self)
		shake(100)
		await shake_finished
		
		anim.play("knockout")
		#await anim.animation_finished
		

func shake(intensity: float = 8.0, duration: float = 0.2):
	# FIX: Capture the starting position if we haven't yet
	if _initial_position == Vector2.ZERO:
		_initial_position = position

	# Clean up any active tweens to prevent "position drifting"
	if _shake_tween:
		_shake_tween.kill()
	
	_shake_tween = create_tween()
	
	var shake_count: int = 10 
	var step_time: float = duration / shake_count
	
	for i in range(shake_count):
		# Calculate the random offset
		var offset := Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		
		# Animate to the new offset relative to the original center
		_shake_tween.tween_property(self, "position", _initial_position + offset, step_time)
		
		# Gradually reduce intensity for a "settling" feel
		intensity *= 0.8 

	# Final step: Snap back to the exact starting point
	_shake_tween.tween_property(self, "position", _initial_position, step_time)
	
	# Emit the custom signal when done
	_shake_tween.finished.connect(func(): shake_finished.emit())

func _on_shake_finished():
	shake_finished.emit()
	
