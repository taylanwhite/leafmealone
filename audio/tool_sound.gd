extends AudioStreamPlayer3D

## The running sound of a tool, heard by everyone nearby: a mower's engine, a
## blower's roar, a hose's hiss, and so on. It follows the prop's replicated
## spraying flag. The holder also hears it the moment they press, before the
## host says so, so it never lags their own click.

const _Sfx = preload("res://audio/sfx.gd")

## The loop for each tool kind.
const LOOPS: Dictionary = {
	"lawn_mower": "mower_loop",
	"leaf_blower": "blower_loop",
	"hose": "hose_loop",
	"pressure_washer": "washer_loop",
	"hedge_trimmer": "trimmer_loop",
	"paint_roller": "roller_loop",
}
## How fast the sound swells in and dies away, in volume share per second.
const FADE_PER_SECOND := 6.0
## Quietest volume, in decibels, before it stops playing.
const SILENT_DB := -40.0

var _level: float = 0.0


func _ready() -> void:
	if Net.is_automated() or DisplayServer.get_name() == "headless":
		set_process(false)
		return
	var prop := get_parent()
	stream = _Sfx.looped(str(LOOPS.get(str(prop.get("kind")), "")))
	unit_size = 6.0
	max_distance = 45.0
	attenuation_filter_cutoff_hz = 9000.0
	volume_db = SILENT_DB


## Let go of the sound on the way out, or it outlives the engine at quit.
func _exit_tree() -> void:
	stop()
	stream = null


func _process(delta: float) -> void:
	if stream == null:
		return
	var on := _running()
	_level = move_toward(_level, 1.0 if on else 0.0, FADE_PER_SECOND * delta)
	if _level <= 0.0:
		if playing:
			stop()
		return
	if not playing:
		play(randf() * stream.get_length())
	volume_db = linear_to_db(_level)
	# A little engine wobble so two mowers don't drone in unison.
	pitch_scale = 1.0 + sin(Time.get_ticks_msec() / 1000.0 * 1.3 + get_instance_id() % 7) * 0.02


func _running() -> bool:
	var prop := get_parent()
	var kind := str(prop.get("kind"))
	var holder := int(prop.get("held_by"))
	if kind == "lawn_mower":
		return bool(prop.get("spraying"))
	if holder == 0:
		return false
	if kind == "hose" and str(prop.get("hose_source")) == "":
		return false
	if (kind == "pressure_washer" or kind == "paint_roller") and float(prop.get("water")) <= 0.0:
		return false
	if bool(prop.get("spraying")):
		return true
	return holder == Net.local_peer_id() and Input.is_action_pressed("primary") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
