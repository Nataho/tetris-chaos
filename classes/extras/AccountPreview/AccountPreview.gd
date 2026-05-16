class_name AccountPreview extends Control
const FILE = preload("uid://dnsjptmes1h1h")

var uid = -1
var username = "guest"
var highscore = 0
var friendship_status = "stranger"

static func create(uid:int) -> AccountPreview:
	var obj = FILE.instantiate()
	obj.uid = uid
	return obj

func _ready() -> void:
	#TCPBridge.lookup_user()
	
	TCPBridge.lookup_user(uid)
	
	var result = await TCPBridge.active_bridge.server_response
	var data = result.get("data")
	uid = data.get("uid", -1)
	username = data.get("username", "guest")
	highscore = data.get("highscore", 0)
	friendship_status = data.get("friend_status", "stranger")
	
	load_player_data()
	
	await get_tree().create_timer(7).timeout
	$AnimationPlayer.play_backwards("open")
	await $AnimationPlayer.animation_finished
	queue_free() 

func add_friend():
	if friendship_status.to_lower() in ["you","friends"]:
		return
	
	TCPBridge.add_friend(uid)

func load_player_data():
	$Panel/username.text = username
	$Panel/status.text = friendship_status
	
