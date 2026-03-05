extends Node

var is_client = true

func sync_interaction(action: String):
		if is_client:
			NetworkClient.sync_interaction(action) #Client| send sync signal
		else:
			NetworkServer.sync_interaction(action) #Server| send sync signal
