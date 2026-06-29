extends Node

var Papa = get_parent()

func _ready():
	DiscordRPC.app_id = 1521222889448276042 # Application ID
	DiscordRPC.details = "GodotCD"
	DiscordRPC.state = "Listening On GodotCD"
	
	DiscordRPC.large_image = "mainimage"
	
	DiscordRPC.start_timestamp = int(Time.get_unix_time_from_system()) # "02:46 elapsed"
	# DiscordRPC.end_timestamp = int(Time.get_unix_time_from_system()) + 3600 # +1 hour in unix time / "01:00:00 remaining"

	DiscordRPC.refresh() # Always refresh after changing the values!

func _process(delta: float):
	DiscordRPC.details = "Listening To " + $Node/Ui/AlbumTitle.text
	DiscordRPC.state = $Node/Ui/CurrentTrack.text
	DiscordRPC.refresh() # Always refresh after changing the values!
