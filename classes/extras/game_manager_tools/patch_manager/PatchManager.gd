class_name PatchManager extends Node

signal update_status_msg(message: String)
signal update_finished()
signal update_progress(current_bytes: int, total_bytes: int)

const VERSION_URL = "https://nataho.github.io/tetris-chaos/version.json"

var active_version: String = ""
var target_version: String = ""

var http_request: HTTPRequest
var is_downloading_patch: bool = false

# ==========================================
# STATIC INITIALIZATION
# ==========================================
static func apply_existing_patch(fallback_version: String) -> String:
	#If we have a downloaded patch, inject it into the game on boot
	if FileAccess.file_exists("user://hotfix.pck"):
		ProjectSettings.load_resource_pack("user://hotfix.pck")
		
	#Read what version that patch was so we don't redownload it
	if FileAccess.file_exists("user://patch_version.txt"):
		var file = FileAccess.open("user://patch_version.txt", FileAccess.READ)
		return file.get_as_text().strip_edges()
	
	# If no patch exists, return the base game version
	return fallback_version

# ==========================================
# AUTO UPDATER ENGINE
# ==========================================
func _process(_delta: float) -> void:
	#print("patch manager is workin")
	if is_downloading_patch and http_request and http_request.get_http_client_status() == HTTPClient.STATUS_BODY:
		var current = http_request.get_downloaded_bytes()
		var total = http_request.get_body_size()
		update_progress.emit(current, total)

func check_for_updates(current_game_version: String) -> void:
	active_version = current_game_version
	
	# Create HTTP node when needed
	if not http_request:
		http_request = HTTPRequest.new()
		add_child(http_request)
		
	update_status_msg.emit("Checking for updates...")
	http_request.request_completed.connect(_on_version_check_completed)
	http_request.request(VERSION_URL)

func _on_version_check_completed(_result, response_code, _headers, body) -> void:
	http_request.request_completed.disconnect(_on_version_check_completed)
	
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json == null or not json.has("latest_version"):
			_finish_update("Up to date!")
			return
			
		var latest_version = json["latest_version"]
		
		if is_version_older(active_version, latest_version):
			target_version = latest_version
			update_status_msg.emit("Downloading patch " + latest_version + "...")
			download_patch(json["patch_url"])
		else:
			_finish_update("Game is up to date!")
	else:
		_finish_update("Playing Offline")

func is_version_older(current: String, latest: String) -> bool:
	var curr_parts = current.replace("v", "").split(".")
	var latest_parts = latest.replace("v", "").split(".")
	
	if curr_parts.size() < 3 or latest_parts.size() < 3: return false
	
	for i in range(3):
		if int(curr_parts[i]) < int(latest_parts[i]): return true
		elif int(curr_parts[i]) > int(latest_parts[i]): return false
	return false

func download_patch(patch_url: String) -> void:
	http_request.download_file = "user://hotfix.pck"
	is_downloading_patch = true
	http_request.request_completed.connect(_on_patch_downloaded)
	http_request.request(patch_url)

func _on_patch_downloaded(_result, response_code, _headers, _body) -> void:
	is_downloading_patch = false
	http_request.request_completed.disconnect(_on_patch_downloaded)
	if response_code == 200 or response_code == 302:
		var success = ProjectSettings.load_resource_pack("user://hotfix.pck")
		if success:
			var file = FileAccess.open("user://patch_version.txt", FileAccess.WRITE)
			file.store_string(target_version)
			active_version = target_version
			
			_finish_update("Update Applied Successfully!")
		else:
			_finish_update("Failed to apply patch.")
	else:
		_finish_update("Download failed.")

func _finish_update(final_message: String) -> void:
	print(final_message)
	update_status_msg.emit(final_message)
	update_finished.emit()
