extends RefCounted

## Command-line flags from docs/NETCODE.md. User arguments are the ones after --.

var host: bool = false
var join_address: String = ""
var port: int = Constants.DEFAULT_PORT
var player_name: String = ""
var start_zone: String = "store"
var lot: int = 0
var no_steam: bool = false
var smoke_test: bool = false
var smoke_client: bool = false


func read() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--host":
			host = true
		elif argument.begins_with("--join="):
			join_address = argument.trim_prefix("--join=")
		elif argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--name="):
			player_name = argument.trim_prefix("--name=")
		elif argument.begins_with("--start-zone="):
			start_zone = argument.trim_prefix("--start-zone=")
		elif argument.begins_with("--lot="):
			lot = int(argument.trim_prefix("--lot="))
		elif argument == "--no-steam":
			no_steam = true
		elif argument == "--smoke-test":
			smoke_test = true
			no_steam = true
		elif argument == "--smoke-client":
			smoke_client = true
			no_steam = true
		else:
			push_warning("[Net] ignored command-line argument %s" % argument)
