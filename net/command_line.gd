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
## --bot-crew (with --bot; tools/play.ps1 -Bots): the bot plays a whole day as a crew
## member instead of soaking zone moves: it waits by Chefty and rides along, works
## the job, rides home, and never asks for a zone move itself (net/dev/bot.gd).
var bot_crew: bool = false
var open_shop: bool = false
## --open-shop=<shop>[:<tab>] opens that shop's window on that tab (open_shop too).
var open_shop_id: String = ""
var open_board: bool = false
## --yard-size=N: every job's yard is this size (0 small, 1 regular, 2 big), -1 for the offer's.
var yard_size: int = -1
## --hood=<id>: every job yard is in this neighborhood (net/town/neighborhoods.gd id),
## built in its style with its street block (levels/town/hood_styles.gd), for tests
## and screenshots. The host's choice reaches clients with the lot.
var hood: String = ""
var walk_straight: bool = false
var ride_at: float = -1.0
var job_test: bool = false
var bonk_test: bool = false
var work_test: bool = false
var throw_test: bool = false
var board_test: bool = false
var gag_test: bool = false
var brawl_test: bool = false
## --encounter-test: the NICE BOYS' catch (net/dev/encounter_test.gd, R2 chunk 2).
var encounter_test: bool = false
## --heat=N: the crew starts with this much heat (0 to 100).
var heat: float = 0.0
var water_test: bool = false
## --hide-test (R2 chunk 3): hiding's live view, dives, tells, suspicion and inspection.
var hide_test: bool = false
var mower_test: bool = false
## --job-seed=N builds that yard every time; --all-tasks asks for every task; --all-tools gives you every tool.
var job_seed: int = 0
var all_tasks: bool = false
var all_tools: bool = false
## The spine (docs/SPINE.md). --rank=N: the crew is at least tier N (0 = Rake
## Rookie I). --start-hour=H: the day clock starts at H (7 to 26). --clock-scale=S:
## real seconds per in-game minute times S (tests run the day fast with 0.02).
var rank: int = 0
var start_hour: float = -1.0
var clock_scale: float = 1.0
var day_test: bool = false
var town_test: bool = false
## --layout-test: build many yards and check for clipping (net/dev/layout_test.gd).
var layout_test: bool = false
var hire_test: bool = false
var rival_test: bool = false
## --stage-test: R2's stage camera, staged bodies, locks, captions and iris (net/dev/stage_test.gd).
var stage_test: bool = false
## --hud-test: R2b, what's on screen during the encounter (net/dev/hud_test.gd).
var hud_test: bool = false
## --depart-test: p1-depart, how a crew leaves together and how a job ends (net/dev/depart_test.gd).
var depart_test: bool = false
## --ui-test: p1-ui, the windows and the words hung in the world (net/dev/ui_test.gd).
var ui_test: bool = false
## --cast-test: the string table audit and the cast (net/dev/cast_test.gd).
var cast_test: bool = false
## --remote-play=<dir>: an agent plays by hand through <dir>/cmd.json (net/dev/remote_play.gd).
var remote_play: String = ""
## --start-day=N: the campaign's day (seasons turn every Constants.SEASON_DAYS).
var start_day: int = 0
## For screenshots: --open-phone=<texts|clients|map|crew> takes the phone out after a second;
## --end-day-at=<s> ends the day then (the host), so the summary card shows.
var open_phone: String = ""
var end_day_at: float = -1.0
## The host's world mode (net/session_root.gd): --town-map builds the connected
## town, --legacy-map the separate store, lot and border zones. Neither means
## Constants.TOWN_MAP_DEFAULT. Clients get the host's mode with the world.
var town_map: bool = false
var legacy_map: bool = false
## --warp-rides: Chefty's autopilot trips (depart(), the chauffeur) follow their
## route at Constants.AUTOPILOT_TEST_WARP times cruise speed instead of driving
## it, as automated runs do (net/components/vehicle_autopilot.gd).
var warp_rides: bool = false
## --audio-test: buses, the sound bank, Sfx and positional sounds (net/dev/audio_test.gd).
var audio_test: bool = false
## --settings-test: volumes, look, FOV, bindings and the settings file (net/dev/settings_test.gd).
var settings_test: bool = false
## For screenshots: --open-settings=<sound|controls|keys|video|interface> opens the
## Settings window on that tab after a second; "keys:listen" leaves a slot waiting
## for a key, "keys:swap" rebinds Interact to F so the swap notice shows;
## "captions" keeps it closed and shows a quip, a homeowner and her prompt instead.
var open_settings: String = ""
## --shop-test: buying, hours, stock, supplies and the shops save (net/dev/shop_test.gd).
## Also the one timed run that uses the real starter supplies (net/shops/shops.gd).
var shop_test: bool = false
## --hotbar-test: pockets, slots, stacks, hands full, emptied pockets (net/dev/hotbar_test.gd).
var hotbar_test: bool = false
## --fill-pockets (host): once the yard is up, pick up the rake and every job tool,
## so screenshots show a full hotbar (net/dev/dev_tools.gd).
var fill_pockets: bool = false
## --townmap-test: the connected town's layout, roads, routes, slots and colliders (net/dev/townmap_test.gd).
var townmap_test: bool = false
## --icons-test: every icon, its recipe, coverage, key tokens and the window icon (net/dev/icons_test.gd).
var icons_test: bool = false
## --drive-test: the drivable Chefty's seats, driving, prediction, horn and getting out (net/dev/drive_test.gd).
var drive_test: bool = false
## --skate-test: the Gutter Shredder's buying, riding, tricks and wipeouts (net/dev/skate_test.gd).
var skate_test: bool = false
## --pursuit-test: the NICE BOYS chase the crew's truck through the town, pull it over, get rammed and lose it (net/dev/pursuit_test.gd).
var pursuit_test: bool = false
## --balance-test: the engine side of the balance lab's parity check: every tuning constant,
## a grid of economy formulas, and the tables' invariants (net/dev/balance_test.gd).
var balance_test: bool = false
## Playtesting (docs/PLAYTEST.md). --scenario=<name>: the host jumps to a moment once the
## world is up (net/dev/scenarios.gd). --observer: a remote-play client that parks at the
## store and watches the host (tools/play.ps1 -Observer). --playtest-tools-test: the
## scenarios and the recorder (net/dev/playtest_tools_test.gd).
var scenario: String = ""
var observer: bool = false
var playtest_tools_test: bool = false
## --annex-test: Satellite Annex B, its schedule, forms and turnstile (net/dev/annex_test.gd, R2 chunk 6).
var annex_test: bool = false
## --fixed-step=N: this run was launched with the engine's --fixed-fps N (which
## scripts can't see), so every frame is exactly 1/N s of game time. The dev tools
## then hold it to real time (net/dev/pacer.gd) and Net's clock counts game time
## (net/clock_sync.gd), so recordings are evenly spaced and rides and raids keep
## in step with physics even on a loaded machine. tools/play.ps1 passes both.
var fixed_step: int = 0
## --clock-skew=S (P1 catch): a client's estimate of the host's clock held S s off
## (negative: behind), the way a starved window's drifted in crew playtest 1, so a
## playtest can watch the stage on a drifted clock (net/clock_sync.gd). The host's
## own clock ignores it.
var clock_skew: float = 0.0
## --art-test: every neighborhood's look in the running game: styles, signatures,
## budgets, layout, determinism, seasons and words (net/dev/art_test.gd).
var art_test: bool = false
## --rake-net-test: the leaf field's stroke events, atomic batches and prediction
## ledger at 150 ms / 2% loss, and the golden density rules (net/dev/rake_net_test.gd, raking:1).
var rake_net_test: bool = false
## --leaf-motion-test: leaves flying between cells (net/dev/leaf_motion_test.gd, raking:3).
var leaf_motion_test: bool = false
## --leaf-motion-headless: the leaf view and motion keep their state headless
## (leaves/leaf_renderer.gd reads it from the user args itself; registered here so it isn't "ignored").
var leaf_motion_headless: bool = false
## --rake-stroke-test: the rake swing's bites, a remote swing and a hired hand's rake (net/dev/rake_stroke_test.gd, raking:4).
var rake_stroke_test: bool = false
## --hands-test: what your hands do: the punch, E's choice, the bag, the fence, the wheelbarrow, the sleep pose (net/dev/hands_test.gd, p1-hands).
var hands_test: bool = false
## True when --port= was on the command line (a dev flag; the run uses campaign_test_<port>.json).
var port_given: bool = false
## Every user argument that isn't a player flag, unknown ones included (docs/DECISIONS.md,
## "Dev sessions never touch the real save"). Any of them makes this a dev session.
var dev_flags: PackedStringArray = []
## --toss-test: tossing leaf bags into Chefty's bed with G (net/dev/toss_test.gd).
## --toss-survey: the same, but a table of throws from 2, 4 and 6 m instead.
var toss_test: bool = false
var toss_survey: bool = false

## The only flags a player launches with. Everything else is a dev, test or automation
## flag, so a new flag is a dev flag until it is added here. --town-map is a player flag
## only on its own: with any other flag the session is a dev one anyway. --port= is a
## dev flag: no menu offers a port, and agents pick custom ports to keep runs apart.
const PLAYER_FLAGS: Array[String] = ["--host", "--no-steam", "--town-map"]
const PLAYER_FLAG_PREFIXES: Array[String] = ["--join=", "--name="]


## True when this run is a dev, test or automation session: any non-player user flag,
## a headless display, or a Movie Maker run. Such a session never reads or writes the
## player's real save or settings (net/campaign.gd save_path()).
## Engine arguments Godot consumes (--fixed-fps, --quit-after, --script, --quit ...)
## never reach scripts (OS.get_cmdline_args() leaves them out), so they can't mark a
## session: an automated windowed run must also pass a dev user flag (--port=,
## --fixed-step= next to --fixed-fps, ...), as ci_local.ps1, play.ps1 and the soaks do.
func is_dev_session() -> bool:
	return not dev_session_reasons().is_empty()


## Why this is a dev session (empty for a player's session), for the save guard's error.
func dev_session_reasons() -> PackedStringArray:
	var reasons := dev_flags.duplicate()
	if DisplayServer.get_name() == "headless":
		reasons.append("headless")
	if Engine.get_write_movie_path() != "":
		reasons.append("--write-movie")
	return reasons


static func is_player_flag(argument: String) -> bool:
	if PLAYER_FLAGS.has(argument):
		return true
	for prefix: String in PLAYER_FLAG_PREFIXES:
		if argument.begins_with(prefix):
			return true
	return false
## --shuttle-test: the Courtesy Shuttle's trips, seats, unbuckling, straggler and drop-off (net/dev/shuttle_test.gd, nice_boys:4).
var shuttle_test: bool = false
## --lens-test: P1 lens, the near-lens dissolve and the homeowner's manners (net/dev/lens_test.gd).
var lens_test: bool = false
## --arrive-test: stepping off Chefty, each rider to their own spot, and room to stand (net/dev/arrive_test.gd, p1-arrive).
var arrive_test: bool = false
## p2-kit (net/kit/kit.gd _seed_dev). --starter-kit=N: N rakes in Chefty's bed
## (-1, unset: none, except a session started on the yard, which finds one
## rake where the yard's own used to lie; --starter-kit=0 not even that).
var starter_kit: int = -1
## --kit-test: buy a rake with the starting $50, load it, ride, take it out,
## rake, leave it at the yard, sleep, find it by the door (net/dev/kit_test.gd).
var kit_test: bool = false
## --yard-test: the yard's edges and the people on it: the rake bin under your look, the solid fence, the homeowner framed, the town's edge giving, a teammate's catch-up (net/dev/yard_test.gd, fx-yard).
var yard_test: bool = false


## True when the transport should be wrapped in LinkPeer for counting or simulation.
func wants_link_peer() -> bool:
	return sim_lag_ms > 0 or sim_loss_percent > 0.0 or measure_path != ""


## True when any net/dev tool is requested.
func wants_dev_tools() -> bool:
	return bot or measure_path != "" or run_seconds > 0.0 or screenshot_dir != "" or mute_audio or run_event_at >= 0.0 or open_shop or open_board or ride_at >= 0.0 or job_test or bonk_test or work_test or throw_test or water_test or hide_test or mower_test or board_test or gag_test or brawl_test or encounter_test or day_test or town_test or layout_test or hire_test or rival_test or stage_test or hud_test or depart_test or cast_test or remote_play != "" or open_phone != "" or end_day_at >= 0.0 or audio_test or settings_test or open_settings != "" or shop_test or hotbar_test or fill_pockets or townmap_test or icons_test or drive_test or skate_test or balance_test or scenario != "" or playtest_tools_test or annex_test or fixed_step > 0 or art_test or rake_net_test or leaf_motion_test or rake_stroke_test or hands_test or shuttle_test or toss_test or toss_survey or lens_test or arrive_test or ui_test or kit_test or pursuit_test or yard_test


func read() -> void:
	parse(OS.get_cmdline_user_args())


## Reads these user arguments (read() passes the real ones; the settings test passes its own).
func parse(arguments: PackedStringArray) -> void:
	for argument: String in arguments:
		if not is_player_flag(argument):
			dev_flags.append(argument)
		if argument == "--host":
			host = true
		elif argument.begins_with("--join="):
			join_address = argument.trim_prefix("--join=")
		elif argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
			port_given = true
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
		elif argument == "--bot-crew":
			bot_crew = true
			bot = true
		elif argument == "--open-shop":
			open_shop = true
		elif argument.begins_with("--open-shop="):
			open_shop = true
			open_shop_id = argument.trim_prefix("--open-shop=")
		elif argument.begins_with("--yard-size="):
			yard_size = int(argument.trim_prefix("--yard-size="))
		elif argument.begins_with("--hood="):
			hood = argument.trim_prefix("--hood=")
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
		elif argument == "--hide-test":
			hide_test = true
		elif argument == "--brawl-test":
			brawl_test = true
		elif argument == "--encounter-test":
			encounter_test = true
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
		elif argument.begins_with("--rank="):
			rank = int(argument.trim_prefix("--rank="))
		elif argument.begins_with("--start-hour="):
			start_hour = float(argument.trim_prefix("--start-hour="))
		elif argument.begins_with("--clock-scale="):
			clock_scale = maxf(0.001, float(argument.trim_prefix("--clock-scale=")))
		elif argument == "--day-test":
			day_test = true
		elif argument == "--town-test":
			town_test = true
		elif argument == "--layout-test":
			layout_test = true
		elif argument == "--hire-test":
			hire_test = true
		elif argument == "--rival-test":
			rival_test = true
		elif argument == "--stage-test":
			stage_test = true
		elif argument == "--hud-test":
			hud_test = true
		elif argument == "--depart-test":
			depart_test = true
		elif argument == "--ui-test":
			ui_test = true
		elif argument == "--cast-test":
			cast_test = true
		elif argument.begins_with("--remote-play="):
			remote_play = argument.trim_prefix("--remote-play=")
		elif argument.begins_with("--start-day="):
			start_day = int(argument.trim_prefix("--start-day="))
		elif argument.begins_with("--open-phone="):
			open_phone = argument.trim_prefix("--open-phone=")
		elif argument.begins_with("--end-day-at="):
			end_day_at = float(argument.trim_prefix("--end-day-at="))
		elif argument == "--town-map":
			town_map = true
		elif argument == "--legacy-map":
			legacy_map = true
		elif argument == "--warp-rides":
			warp_rides = true
		elif argument == "--audio-test":
			audio_test = true
		elif argument == "--settings-test":
			settings_test = true
		elif argument.begins_with("--open-settings="):
			open_settings = argument.trim_prefix("--open-settings=")
		elif argument == "--shop-test":
			shop_test = true
		elif argument == "--hotbar-test":
			hotbar_test = true
		elif argument.begins_with("--starter-kit"):
			starter_kit = int(argument.trim_prefix("--starter-kit=")) if argument.begins_with("--starter-kit=") else 1
		elif argument == "--kit-test":
			kit_test = true
		elif argument == "--yard-test":
			yard_test = true
		elif argument == "--fill-pockets":
			fill_pockets = true
		elif argument == "--townmap-test":
			townmap_test = true
		elif argument == "--icons-test":
			icons_test = true
		elif argument == "--drive-test":
			drive_test = true
		elif argument == "--skate-test":
			skate_test = true
		elif argument == "--pursuit-test":
			pursuit_test = true
		elif argument == "--balance-test":
			balance_test = true
		elif argument.begins_with("--scenario="):
			scenario = argument.trim_prefix("--scenario=")
		elif argument == "--observer":
			observer = true
		elif argument == "--playtest-tools-test":
			playtest_tools_test = true
		elif argument == "--annex-test":
			annex_test = true
		elif argument.begins_with("--fixed-step="):
			fixed_step = maxi(0, int(argument.trim_prefix("--fixed-step=")))
		elif argument.begins_with("--clock-skew="):
			clock_skew = float(argument.trim_prefix("--clock-skew="))
		elif argument == "--art-test":
			art_test = true
		elif argument == "--rake-net-test":
			rake_net_test = true
		elif argument == "--leaf-motion-test":
			leaf_motion_test = true
		elif argument == "--leaf-motion-headless":
			leaf_motion_headless = true
		elif argument == "--rake-stroke-test":
			rake_stroke_test = true
		elif argument == "--hands-test":
			hands_test = true
		elif argument == "--toss-test":
			toss_test = true
		elif argument == "--toss-survey":
			toss_survey = true
		elif argument == "--shuttle-test":
			shuttle_test = true
		elif argument == "--lens-test":
			lens_test = true
		elif argument == "--arrive-test":
			arrive_test = true
		else:
			push_warning("[Net] ignored command-line argument %s" % argument)
