extends Node

## Local presentation. "Audio", made by ui/ui_root.gd and alive for the whole
## app, menu included: it makes the mixer buses (audio/buses.gd) and holds the
## sound-effects player, Sfx (audio/sfx.gd, group "sfx"). The music director,
## UI sounds and cue hooks join it later (gap-specs/audio.json, chunks 3 and 5).

const _Buses = preload("res://audio/buses.gd")
const _SfxScript = preload("res://audio/sfx.gd")


func _ready() -> void:
	_Buses.ensure()
	var sfx := _SfxScript.new()
	sfx.name = "Sfx"
	add_child(sfx)
