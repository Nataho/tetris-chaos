extends Board
class_name MultiplayerBoard

signal knocked_out(node: MultiplayerBoard)

@onready var anim: AnimationPlayer = $AnimationPlayer

var kos: int = 0
var center_pos = Vector2.ZERO
var player_ready = false

#region shake variables
signal shake_finished
var _initial_position: Vector2
var _shake_tween: Tween
#endregion shake variables

#static func create(id, target):
	
	#pass

func set_player(player_index:int):
	_player_index = player_index

#func _super_ready() -> void:
	#print("huh?")

# Inside Board.gd or MultiplayerBoard.gd
func setup_multiplayer(my_id: int, enemy_id: int):
	_player_index = my_id
	target_player = enemy_id
	# Now the logic in _check_ko will have real IDs to compare against

func reset():
	super.reset()
	anim.play("RESET")
	player_ready = false # Ensure they aren't auto-ready for the next round
	_initial_position = position

func stop():
	#pieces_controller.cur_piece_controller.stop()
	pieces_controller.stop()

func _check_ko(payload):
	var credit_id = payload["knockout_credit"] 
	var victim_id = payload["player_id"]
	
	if _player_index == -1: return

	# 1. HANDLE SELF-KO (Fixed Logic)
	# Only re-map the credit if the victim of the KO is NOT me.
	# If my opponent died and no one was credited, then I must be the winner!
	if victim_id != _player_index and (credit_id == victim_id or credit_id == -1):
		credit_id = _player_index
	
	# 2. ASSIGN POINTS
	if credit_id == _player_index:
		kos += 1
		# Explicitly tell the UI to update
		#get_parent().get_parent().update_scoreboard()

	# 3. DEATH SEQUENCE
	if victim_id == _player_index:
		handle_death_sequence()

func handle_death_sequence():
	Audio.play_sound("topout")
	knocked_out.emit(self)
	
	shake(100)
	await shake_finished
	
	anim.play("knockout")
	# You can add a 'yield' or 'await' here if you need to pause 
	# before resetting the board

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

func toggle_ready() -> bool:
	player_ready = !player_ready
	if player_ready:
		#Audio.play_sound("ready_up")
		pass
	return player_ready
