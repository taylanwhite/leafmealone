extends Node

## Authority: local. Development tools turned on by command-line flags:
## --bot, --bot-stay, --measure=<file>, --screenshot=<dir>, --run-seconds=<n>,
## --mute-audio, --run-event-at=<n>, --open-shop and --open-settings=<tab>.
## tools/soak.sh launches whole sessions with them. Nothing here runs in a
## normal game.

const _BotScript = preload("res://net/dev/bot.gd")
const _ProbeScript = preload("res://net/dev/probe.gd")
const _CaptureScript = preload("res://net/dev/capture.gd")
## --open-shop waits this long after launch, so the session and UI are up.
const OPEN_SHOP_AFTER_SECONDS: float = 1.0
## Once every test here is done, the host waits this long so the last replicated
## changes (task progress, leaves, heat) reach clients before anyone reports.
const FINISH_SETTLE_SECONDS: float = 0.5
## How long the host waits for clients to report and leave before it quits anyway.
const FINISH_CLIENT_WAIT_SECONDS: float = 5.0

## The scripts of the *_test.gd nodes added here; each sets result["done"] when it ends.
var _tests: Array[Script] = []
var _finishing: bool = false


func _ready() -> void:
	var options := Net.dev_options()
	if bool(options.get("bot")):
		_add(_BotScript.new(), "Bot")
	if str(options.get("measure_path")) != "":
		_add(_ProbeScript.new(), "Probe")
	if str(options.get("screenshot_dir")) != "":
		_add(_CaptureScript.new(), "Capture")
	if bool(options.get("mute_audio")):
		# Streams still mix on a muted bus, so voice playback is measured but silent.
		AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), true)
	var seconds := float(options.get("run_seconds"))
	if seconds > 0.0:
		get_tree().create_timer(seconds).timeout.connect(_finish)
	if bool(options.get("mower_test")):
		_add(preload("res://net/dev/mower_test.gd").new(), "MowerTest")
	if bool(options.get("water_test")):
		_add(preload("res://net/dev/water_test.gd").new(), "WaterTest")
	if bool(options.get("brawl_test")):
		_add(preload("res://net/dev/brawl_test.gd").new(), "BrawlTest")
	if bool(options.get("gag_test")):
		_add(preload("res://net/dev/gag_test.gd").new(), "GagTest")
	if bool(options.get("board_test")):
		_add(preload("res://net/dev/board_test.gd").new(), "BoardTest")
	if bool(options.get("throw_test")):
		_add(preload("res://net/dev/throw_test.gd").new(), "ThrowTest")
	if bool(options.get("work_test")):
		_add(preload("res://net/dev/work_test.gd").new(), "WorkTest")
	if bool(options.get("bonk_test")):
		_add(preload("res://net/dev/bonk_test.gd").new(), "BonkTest")
	if bool(options.get("job_test")):
		_add(preload("res://net/dev/job_test.gd").new(), "JobTest")
	if bool(options.get("day_test")):
		_add(preload("res://net/dev/day_test.gd").new(), "DayTest")
	if bool(options.get("town_test")):
		_add(preload("res://net/dev/town_test.gd").new(), "TownTest")
	if str(options.get("remote_play")) != "":
		_add(preload("res://net/dev/remote_play.gd").new(), "RemotePlay")
	if bool(options.get("rival_test")):
		_add(preload("res://net/dev/rival_test.gd").new(), "RivalTest")
	if bool(options.get("hire_test")):
		_add(preload("res://net/dev/hire_test.gd").new(), "HireTest")
	if bool(options.get("layout_test")):
		_add(preload("res://net/dev/layout_test.gd").new(), "LayoutTest")
	if bool(options.get("cast_test")):
		_add(preload("res://net/dev/cast_test.gd").new(), "CastTest")
	if bool(options.get("audio_test")):
		_add(preload("res://net/dev/audio_test.gd").new(), "AudioTest")
	if bool(options.get("settings_test")):
		_add(preload("res://net/dev/settings_test.gd").new(), "SettingsTest")
	if bool(options.get("shop_test")):
		_add(preload("res://net/dev/shop_test.gd").new(), "ShopTest")
	if bool(options.get("hotbar_test")):
		_add(preload("res://net/dev/hotbar_test.gd").new(), "HotbarTest")
	if bool(options.get("townmap_test")):
		_add(preload("res://net/dev/townmap_test.gd").new(), "TownmapTest")
	if bool(options.get("icons_test")):
		_add(preload("res://net/dev/icons_test.gd").new(), "IconsTest")
	if bool(options.get("drive_test")):
		_add(preload("res://net/dev/drive_test.gd").new(), "DriveTest")
	if bool(options.get("open_shop")):
		# For screenshots of the shop window: bots never walk up to the counter.
		get_tree().create_timer(OPEN_SHOP_AFTER_SECONDS).timeout.connect(func() -> void:
			var ui := get_tree().get_first_node_in_group("game_ui")
			if ui != null:
				ui.call("open_store")
		)
	if bool(options.get("open_board")):
		# For screenshots of the job board window.
		get_tree().create_timer(OPEN_SHOP_AFTER_SECONDS).timeout.connect(func() -> void:
			var ui := get_tree().get_first_node_in_group("game_ui")
			if ui != null:
				ui.call("open_job_board")
		)
	if str(options.get("open_settings")) != "":
		# For screenshots of the Settings window: "<tab>", "keys:listen" or "keys:swap".
		get_tree().create_timer(OPEN_SHOP_AFTER_SECONDS).timeout.connect(func() -> void:
			var ui := get_tree().get_first_node_in_group("game_ui")
			var parts := str(options.get("open_settings")).split(":")
			if ui != null:
				ui.call("open_settings", false, parts[0])
			var window := get_tree().get_first_node_in_group("settings_window")
			if window == null or parts.size() < 2:
				return
			if parts[1] == "listen":
				window.call("listen", &"interact", 0)
			elif parts[1] == "swap":
				window.call("listen", &"interact", 0)
				window.call("_accept", Settings.code_to_event("key:%d" % KEY_F))
		)
	if str(options.get("open_phone")) != "":
		get_tree().create_timer(OPEN_SHOP_AFTER_SECONDS).timeout.connect(func() -> void:
			var phone := get_tree().get_first_node_in_group("phone")
			if phone != null:
				phone.call("open_phone", str(options.get("open_phone")))
		)
	if float(options.get("end_day_at")) >= 0.0 and Net.is_host():
		get_tree().create_timer(float(options.get("end_day_at"))).timeout.connect(func() -> void:
			var clock := get_tree().get_first_node_in_group("day_clock")
			if clock != null:
				clock.call("force_sleep")
		)
	var ride_at := float(options.get("ride_at"))
	if ride_at >= 0.0:
		get_tree().create_timer(ride_at).timeout.connect(_force_ride)
	var event_at := float(options.get("run_event_at"))
	if event_at >= 0.0:
		get_tree().create_timer(event_at).timeout.connect(_force_run_event)


## Host only: send everyone in the store to the lot in Chefty, for testing rides.
func _force_ride() -> void:
	if not Net.is_host():
		return
	var chefty := get_tree().get_first_node_in_group("chefty")
	var riders: Array = Net.players_in_zone(Net.Zone.STORE)
	if chefty == null or riders.is_empty():
		push_warning("[Dev] nobody to send in Chefty")
		return
	print("[Dev] forcing a ride for %d players" % riders.size())
	chefty.call("depart", riders, Net.Zone.LOT)


## Host only: start a run event's warning now, as F6 does.
func _force_run_event() -> void:
	if not Net.is_host():
		return
	var director := get_tree().get_first_node_in_group("run_director")
	if director == null:
		push_warning("[Dev] no run director to start an event")
		return
	print("[Dev] forcing a run event")
	director.call("force_event")


func _add(node: Node, node_name: String) -> void:
	node.name = node_name
	add_child(node)
	if node_name.ends_with("Test"):
		_tests.append(node.get_script())


## Host: the moment every test here has set result["done"], finish the run
## instead of waiting out --run-seconds (which stays as the ceiling for a hung test).
func _process(_delta: float) -> void:
	if _finishing or _tests.is_empty() or not Net.is_host():
		return
	for script: Script in _tests:
		var result: Dictionary = script.get("result")
		if not bool(result.get("done", false)):
			return
	_finishing = true
	_finish_early()


func _finish_early() -> void:
	print("[Dev] test done; finishing early")
	await get_tree().create_timer(FINISH_SETTLE_SECONDS).timeout
	# Heat syncs at most four times a second; send it now, ahead of the finish
	# message on the same reliable channel, so both reports see the same heat.
	var heat := get_tree().get_first_node_in_group("heat")
	if heat != null and heat.has_method("sync_now"):
		heat.call("sync_now")
	_write_report()
	if multiplayer.multiplayer_peer != null and Net.peer_ids().size() > 1:
		_rpc_finish.rpc()
		var waited := 0.0
		while Net.peer_ids().size() > 1 and waited < FINISH_CLIENT_WAIT_SECONDS:
			await get_tree().create_timer(0.1).timeout
			waited += 0.1
	print("[Dev] run finished early")
	get_tree().quit(0)


## Client: the host's test is done; report now and leave.
@rpc("authority", "call_remote", "reliable")
func _rpc_finish() -> void:
	_finish()


func _finish() -> void:
	# The host is already finishing early; the ceiling must not write its report twice.
	if _finishing:
		return
	_write_report()
	print("[Dev] run finished")
	get_tree().quit(0)


func _write_report() -> void:
	var probe := get_node_or_null("Probe")
	if probe != null:
		probe.call("write_report")
