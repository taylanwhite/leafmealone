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
## Development tools in net/dev/. See tools/soak.sh.
var sim_lag_ms: int = 0
var sim_loss_percent: float = 0.0
var bot: bool = false
var measure_path: String = ""
var run_seconds: float = 0.0
var screenshot_dir: String = ""
var screenshot_every: float = 5.0
## With --screenshot: also shoot a fixed list of close-ups in each zone (net/dev/capture.gd TOUR).
var tour: bool = false
var voice_test: bool = false
var mute_audio: bool = false
var run_event_at: float = -1.0
var bot_stay: bool = false
var open_shop: bool = false
var open_board: bool = false
## --yard-size=N: every job's yard is this size (0 small, 1 regular, 2 big), -1 for the offer's.
var yard_size: int = -1
var walk_straight: bool = false
var ride_at: float = -1.0
var job_test: bool = false
var bonk_test: bool = false
var work_test: bool = false
var throw_test: bool = false
var board_test: bool = false
var gag_test: bool = false
var brawl_test: bool = false
## --heat=N: the crew starts with this much heat (0 to 100).
var heat: float = 0.0
var water_test: bool = false
var mower_test: bool = false
## --job-seed=N builds that yard every time; --all-tasks asks for every task; --all-tools gives you every tool.
var job_seed: int = 0
var all_tasks: bool = false
var all_tools: bool = false


## True when the transport should be wrapped in LinkPeer for counting or simulation.
func wants_link_peer() -> bool:
	return sim_lag_ms > 0 or sim_loss_percent > 0.0 or measure_path != ""


## True when any net/dev tool is requested.
func wants_dev_tools() -> bool:
	return bot or measure_path != "" or run_seconds > 0.0 or screenshot_dir != "" or mute_audio or run_event_at >= 0.0 or open_shop or open_board or ride_at >= 0.0 or job_test or bonk_test or work_test or throw_test or water_test or mower_test or board_test or gag_test or brawl_test


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
		elif argument.begins_with("--sim-lag="):
			sim_lag_ms = int(argument.trim_prefix("--sim-lag="))
		elif argument.begins_with("--sim-loss="):
			sim_loss_percent = float(argument.trim_prefix("--sim-loss="))
		elif argument == "--bot":
			bot = true
		elif argument.begins_with("--measure="):
			measure_path = argument.trim_prefix("--measure=")
		elif argument.begins_with("--run-seconds="):
			run_seconds = float(argument.trim_prefix("--run-seconds="))
		elif argument.begins_with("--screenshot="):
			screenshot_dir = argument.trim_prefix("--screenshot=")
		elif argument == "--voice-test":
			voice_test = true
		elif argument == "--mute-audio":
			mute_audio = true
		elif argument.begins_with("--run-event-at="):
			run_event_at = float(argument.trim_prefix("--run-event-at="))
		elif argument == "--bot-stay":
			bot_stay = true
		elif argument == "--open-shop":
			open_shop = true
		elif argument.begins_with("--yard-size="):
			yard_size = int(argument.trim_prefix("--yard-size="))
		elif argument == "--open-board":
			open_board = true
		elif argument.begins_with("--ride-at="):
			ride_at = float(argument.trim_prefix("--ride-at="))
		elif argument == "--job-test":
			job_test = true
		elif argument == "--tour":
			tour = true
		elif argument.begins_with("--job-seed="):
			job_seed = int(argument.trim_prefix("--job-seed="))
		elif argument == "--all-tasks":
			all_tasks = true
		elif argument == "--all-tools":
			all_tools = true
		elif argument == "--mower-test":
			mower_test = true
		elif argument == "--water-test":
			water_test = true
		elif argument == "--brawl-test":
			brawl_test = true
		elif argument == "--gag-test":
			gag_test = true
		elif argument.begins_with("--heat="):
			heat = float(argument.trim_prefix("--heat="))
		elif argument == "--board-test":
			board_test = true
		elif argument == "--throw-test":
			throw_test = true
		elif argument == "--work-test":
			work_test = true
		elif argument == "--bonk-test":
			bonk_test = true
		elif argument == "--walk-straight":
			walk_straight = true
			bot = true
		elif argument.begins_with("--screenshot-every="):
			screenshot_every = float(argument.trim_prefix("--screenshot-every="))
		else:
			push_warning("[Net] ignored command-line argument %s" % argument)
