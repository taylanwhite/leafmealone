extends Node

## Authority: local. Development tools turned on by command-line flags:
## --bot, --bot-stay, --measure=<file>, --screenshot=<dir>, --run-seconds=<n>,
## --mute-audio, --run-event-at=<n>, and --open-shop.
## tools/soak.sh launches whole sessions with them. Nothing here runs in a
## normal game.

const _BotScript = preload("res://net/dev/bot.gd")
const _ProbeScript = preload("res://net/dev/probe.gd")
const _CaptureScript = preload("res://net/dev/capture.gd")
## --open-shop waits this long after launch, so the session and UI are up.
const OPEN_SHOP_AFTER_SECONDS: float = 1.0


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
	if bool(options.get("bonk_test")):
		_add(preload("res://net/dev/bonk_test.gd").new(), "BonkTest")
	if bool(options.get("job_test")):
		_add(preload("res://net/dev/job_test.gd").new(), "JobTest")
	if bool(options.get("open_shop")):
		# For screenshots of the shop window: bots never walk up to the counter.
		get_tree().create_timer(OPEN_SHOP_AFTER_SECONDS).timeout.connect(func() -> void:
			var ui := get_tree().get_first_node_in_group("game_ui")
			if ui != null:
				ui.call("open_store")
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


func _finish() -> void:
	var probe := get_node_or_null("Probe")
	if probe != null:
		probe.call("write_report")
	print("[Dev] run finished")
	get_tree().quit(0)
