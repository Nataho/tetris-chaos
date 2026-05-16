extends Control
@onready var fps_label: Label = $fps
@onready var ping_label: Label = $ping

var achievement_queue : Array[AchievementBar] = []
var rolling_achievements:bool = false

func _ready() -> void:
	#achievement_get("1", "amazing")
	#achievement_get("2", "amazing")
	#achievement_get("3", "amazing")
	#achievement_get("4", "amazing")
	Events.achievement_get.connect(achievement_get)

func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var text = "FPS: %d" % fps 
	fps_label.text = text

func show_ping(ping:int = -1):
	if ping == -1:
		ping_label.text = ""
		return
	
	var text = "Ping: %d" % ping
	
	ping_label.text = text

func achievement_get(achievement, description):
	achievement_queue.append(AchievementBar.create(achievement, description))
	if !rolling_achievements:
		rolling_achievements = true
		roll_achievement_queue()
	
func roll_achievement_queue():
	print("executed rolling achievement")
	while rolling_achievements:
		if achievement_queue.is_empty(): 
			rolling_achievements = false
			return
			
		var ach = achievement_queue.pop_front()
		
		$top.add_child(ach)
		ach.set_anchors_preset(Control.PRESET_CENTER_TOP)
		
		#print("trying to fucking roll the fucking achievement motherfucker")
		await get_tree().create_timer(5).timeout
		ach.queue_free()
