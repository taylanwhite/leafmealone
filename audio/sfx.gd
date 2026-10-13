extends Node

## Local presentation. Short synthesized placeholders until a real sound pass replaces them.

var _next_msec: Dictionary = {}


func _ready() -> void:
	add_to_group("sfx")


func _exit_tree() -> void:
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			var player := child as AudioStreamPlayer
			player.stop()
			player.stream = null
			player.free()


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
	var stream := load("res://assets/audio/sfx/%s.wav" % sound_name) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
