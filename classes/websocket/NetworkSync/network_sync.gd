extends Node

var is_client = true

func sync_interaction(action: String):
	#print("action: ", action)
	if is_client:
		NetworkClient.sync_interaction(action) #Client| send sync signal
	else:
		NetworkServer.sync_interaction(action) #Server| send sync signal

func sync_data(data = {}):
	if is_client:
		NetworkClient.sync_data(data)
	else:
		NetworkServer.sync_data(data)
