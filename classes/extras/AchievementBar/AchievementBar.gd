class_name AchievementBar extends Label
const file = preload("uid://dvlvvrekgsrlb")

var achievement_name:String = "generic"
var description_text:String = "there was never an achievement"

static func create(achievement, description) -> AchievementBar:
	var obj : AchievementBar = file.instantiate()
	obj.achievement_name = achievement
	obj.description_text = description
	return obj
	

func _ready() -> void:
	text = "Achievement Get!\n\n"
	text += achievement_name + "\n"
	text += "[" + description_text + "]"
	
