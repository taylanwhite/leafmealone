extends Node

## Authority: local. Development tools turned on by command-line flags:
## --bot, --measure=<file>, --screenshot=<dir>, and --run-seconds=<n>.
## tools/soak.sh launches whole sessions with them. Nothing here runs in a
## normal game.

const _BotScript = preload("res://net/dev/bot.gd")
const _ProbeScript = preload("res://net/dev/probe.gd")
const _CaptureScript = preload("res://net/dev/capture.gd")


func _ready() -> void:
	var options := Net.dev_options()
	if bool(options.get("bot")):
		_add(_BotScript.new(), "Bot")
	if str(options.get("measure_path")) != "":
		_add(_ProbeScript.new(), "Probe")
	if str(options.get("screenshot_dir")) != "":
		_add(_CaptureScript.new(), "Capture")
	var seconds := float(options.get("run_seconds"))
	if seconds > 0.0:
		get_tree().create_timer(seconds).timeout.connect(_finish)


func _add(node: Node, node_name: String) -> void:
	node.name = node_name
	add_child(node)


func _finish() -> void:
	var probe := get_node_or_null("Probe")
	if probe != null:
		probe.call("write_report")
	print("[Dev] run finished")
	get_tree().quit(0)
