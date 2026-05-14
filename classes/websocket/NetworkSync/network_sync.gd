extends Node

enum NetMode { OFFLINE, LAN_HOST, LAN_CLIENT, ONLINE }
var current_mode: NetMode = NetMode.OFFLINE

# ---------------------------------------------------------
# OUTBOUND ROUTING (Sending data to the opponent)
# ---------------------------------------------------------

func sync_interaction(action: String):
	match current_mode:
		NetMode.LAN_CLIENT:
			NetworkClient.sync_interaction(action)
		NetMode.LAN_HOST:
			NetworkServer.sync_interaction(action)
		NetMode.ONLINE:
			# Wrap it in "room_action" so the Python server knows to forward it
			var payload = {"type": "room_action", "signal": "sync_interaction", "action": action}
			TCPBridge.send_to_server(payload)

func sync_data(data: Dictionary = {}):
	match current_mode:
		NetMode.LAN_CLIENT:
			NetworkClient.sync_data(data)
		NetMode.LAN_HOST:
			NetworkServer.sync_data(data)
		NetMode.ONLINE:
			var payload = {"type": "room_action", "signal": "sync_data", "data": data}
			TCPBridge.send_to_server(payload)
			# --- THE FIX: Local Echo ---
			# This ensures the sender also processes the action immediately
			Events.sync_data.emit(data)

func send_board_data(data: Dictionary):
	match current_mode:
		NetMode.LAN_CLIENT:
			NetworkClient.send_signal("send_board_data", data)
		NetMode.LAN_HOST:
			NetworkServer.broadcast_signal("send_board_data", data)
		NetMode.ONLINE:
			var payload = {"type": "room_action", "signal": "send_board_data", "data": data}
			TCPBridge.send_to_server(payload)
