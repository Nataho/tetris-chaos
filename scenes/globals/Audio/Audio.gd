extends Node

enum SOUND_END_EFFECTS {NONE, FADE, VINYL}
enum SOUND_START_EFFECTS {NONE, FADE}

@export var music_player_node: AudioStreamPlayer

var stop_tween: Tween
var start_tween: Tween

const sound := {
	#sound name: [sound file, decibles]
	"hard_drop" : [preload("uid://bly66k1bw7i1w"), 0],
	"hold": [preload("uid://doi6o733o8ydj"), 10],
	"rotate": [preload("uid://civksgwgabla4"), -5],
	"soft_drop": [preload("uid://bpvbrin41ifu0"), 0],
	"line_clear": [preload("uid://dt14t6gcebly8"), 0],
	"quad_clear": [preload("uid://cddix10vm3ovc"), 0],
	"spin_clear": [preload("uid://vh8sc8onink4"), 0],
	"spin": [preload("uid://cxj87kj1xeghj"), 0],
	"perfect_clear": [preload("uid://odfrec7etp1x"), 0],
	"b2b": [preload("uid://dmj5yt3ggtu4c"), 0],
	"break_b2b": [preload("uid://dx1c2hsg6v46d"), 0],
	"lvlup":[preload("uid://c8ikouvnemetn"), 10],
	"new_high_score":[preload("uid://b02c72sgb1j6y"), 0],
	"topout": [preload("uid://b0qj646pe160e"), 10],
	
	"garbage_rise":[preload("uid://cu6jrki6jgrqe"),5],
	
	"countdown_3": [preload("uid://du20tbalvyobt"),0],
	"countdown_2": [preload("uid://du20tbalvyobt"),0],
	"countdown_1": [preload("uid://du20tbalvyobt"),0],
	"countdown_0": [preload("uid://bs41psrwkwep8"),0],
	
	"combo1": [preload("uid://de35a0m5vitxq"), 0],
	"combo2": [preload("uid://cu30713gq3pdn"), 0],
	"combo3": [preload("uid://odr2h871ivch"), 0],
	"combo4": [preload("uid://8emmcn7eleea"), 0],
	"combo5": [preload("uid://bmcauxqc2yg7"), 0],
	"combo6": [preload("uid://dm6jis6pm7jv0"), 0],
	"combo7": [preload("uid://dddnv3tkf1j02"), 0],
	"combo8": [preload("uid://bqqfeg7pk3ngs"), 0],
	"combo9": [preload("uid://dowpjivu1bwfv"), 0],
	"combo10": [preload("uid://cuw6y4ynvfxp7"), 0],
	"combo11": [preload("uid://btqesn8cj1pje"), 0],
	"combo12": [preload("uid://dcoqgg2g0v4h7"), 0],
	"combo13": [preload("uid://c805vnybmoomx"), 0],
	"combo14": [preload("uid://8vehfnir5128"), 0],
	"combo15": [preload("uid://hmn4qnhil04h"), 0],
	"combo16": [preload("uid://bxpehpwfaus1"), 0],
}

const music := {
	"marathon": [preload("uid://cswc5yxc0ajka"), 0],
	"main_menu": [preload("uid://cxkfkkchh6ne3"), 0],
	"battle": [preload("uid://dan8cx51lryal"), 0],
	"game_over": [preload("uid://biqalsdu1ga07"), 0],
}

func play_sound(sound_key:String):
	if sound_key not in sound.keys(): 
		push_error("sound not found:", sound_key)
		return
	var sfx := AudioStreamPlayer.new()
	sfx.stream = sound[sound_key][0]
	sfx.volume_db = sound[sound_key][1]
	sfx.bus = &"Sfx"
	
	add_child(sfx)
	sfx.play()
	await sfx.finished
	sfx.queue_free()

func play_music(music_key: String,
	end_effect: SOUND_END_EFFECTS = SOUND_END_EFFECTS.NONE, 
	start_effect: SOUND_START_EFFECTS = SOUND_START_EFFECTS.NONE) -> void:
	assert(music_key in music, "The sound key is not found in the dictionary.")
	
	var loaded_file = music[music_key][0]
	var target_volume = music[music_key][1]
	var bus = &"Music" # Consider changing this to &"Music" later if you want separate volume sliders!
	
	# If this exact track is already playing, don't restart it
	if music_player_node.stream == loaded_file and music_player_node.playing:
		return
		
	# 1. Handle the END effect of the currently playing track
	if music_player_node.playing:
		match end_effect:
			SOUND_END_EFFECTS.VINYL:
				await trigger_vinyl_stop(2.0)
			SOUND_END_EFFECTS.FADE:
				await trigger_fade_out(1.5)
			SOUND_END_EFFECTS.NONE:
				music_player_node.stop()
				
	# 2. Setup the NEW track
	music_player_node.stream = loaded_file
	music_player_node.bus = bus
	music_player_node.pitch_scale = 1.0 # Ensure pitch is reset in case vinyl stop warped it
	
	# 3. Handle the START effect for the new track
	match start_effect:
		SOUND_START_EFFECTS.FADE:
			music_player_node.volume_db = -80.0 # Start silent
			music_player_node.play()
			trigger_fade_in(target_volume, 1.5)
		SOUND_START_EFFECTS.NONE:
			music_player_node.volume_db = target_volume
			music_player_node.play()

# ==========================================
# AUDIO EFFECTS LOGIC
# ==========================================

func trigger_fade_out(duration: float = 1.5) -> void:
	if stop_tween and stop_tween.is_running():
		stop_tween.kill()
		
	stop_tween = create_tween()
	stop_tween.tween_property(music_player_node, "volume_db", -80.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	stop_tween.tween_callback(func():
		music_player_node.stop()
	)
	
	# We await this so the next song doesn't start until the fade is done
	await stop_tween.finished

func trigger_fade_in(target_volume: float, duration: float = 1.5) -> void:
	if start_tween and start_tween.is_running():
		start_tween.kill()
		
	start_tween = create_tween()
	start_tween.tween_property(music_player_node, "volume_db", target_volume, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func trigger_vinyl_stop(duration: float =20.0) -> void:
	if stop_tween and stop_tween.is_running():
		stop_tween.kill()
		
	# set_parallel(true) lets us tween both pitch and volume at the same time
	stop_tween = create_tween().set_parallel(true)
	
	# Slide pitch down to 0.01 (Godot crashes at exactly 0.0)
	stop_tween.tween_property(music_player_node, "pitch_scale", 0.01, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	
	# Slide volume down to silence (-80.0 db)
	stop_tween.tween_property(music_player_node, "volume_db", -80.0, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	
	# chain() tells the tween to wait until the parallel movements are done before firing the callback
	stop_tween.chain().tween_callback(func():
		music_player_node.stop()
		music_player_node.pitch_scale = 1.0 # Reset pitch for the next track
	)
	
	await stop_tween.finished

func _apply_wavy_pitch(player: AudioStreamPlayer, progress: float) -> void:
	var time: float = Time.get_ticks_msec() / 1000.0 
	var wobble: float = sin(time * 30.0) * 0.15 * progress
	
	player.pitch_scale = max(0.01, progress + wobble)
	# Fades the volume out slightly alongside the pitch drop
	player.volume_db = linear_to_db(progress)
