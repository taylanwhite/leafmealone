extends Node

## Local presentation. Sounds are synthesized by tools/make_sfx.py.
## Frequent sounds have variants (step_1.wav ...) and every play gets a slight
## pitch wobble, so repeats don't sound like the same file over and over.

## How many numbered variants a sound has. Sounds not listed are one file.
const VARIANTS: Dictionary = {"step": 4, "rake": 3, "bag": 2}
## Pitch range for each play, as a multiple of normal.
const PITCH_WOBBLE := Vector2(0.93, 1.07)

var _next_msec: Dictionary = {}
var _last_variant: Dictionary = {}


func _ready() -> void:
	add_to_group("sfx")


func _exit_tree() -> void:
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			var player := child as AudioStreamPlayer
			player.stop()
			player.stream = null
			player.free()


## A random variant's file name, never the same one twice in a row.
func _pick_file(sound_name: String) -> String:
	var count := int(VARIANTS.get(sound_name, 0))
	if count <= 0:
		return sound_name
	var variant := randi_range(1, count)
	if count > 1 and variant == int(_last_variant.get(sound_name, 0)):
		variant = variant % count + 1
	_last_variant[sound_name] = variant
	return "%s_%d" % [sound_name, variant]


func play(sound_name: String) -> void:
	if Net.is_automated():
		return
	var now := Time.get_ticks_msec()
	if int(_next_msec.get(sound_name, 0)) > now:
		return
	var gap := 160
	if sound_name == "step":
		gap = 380
	_next_msec[sound_name] = now + gap
	var stream := load("res://assets/audio/sfx/%s.wav" % _pick_file(sound_name)) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.pitch_scale = randf_range(PITCH_WOBBLE.x, PITCH_WOBBLE.y)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
