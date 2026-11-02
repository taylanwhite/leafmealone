extends Node

## Local presentation. "Audio", made by ui/ui_root.gd and alive for the whole
## app, menu included: it makes the mixer buses (audio/buses.gd) and holds the
## sound-effects player, Sfx (audio/sfx.gd, group "sfx"), the music director
## (audio/music_director.gd, group "music_director") and the game cues
## (audio/cue_hooks.gd). The UI sounds join it later (gap-specs/audio.json, chunk 5).

const _Buses = preload("res://audio/buses.gd")
const _SfxScript = preload("res://audio/sfx.gd")
const _DirectorScript = preload("res://audio/music_director.gd")
const _CueHooksScript = preload("res://audio/cue_hooks.gd")


func _ready() -> void:
	_Buses.ensure()
	var sfx := _SfxScript.new()
	sfx.name = "Sfx"
	add_child(sfx)
	var director := _DirectorScript.new()
	director.name = "MusicDirector"
	add_child(director)
	var cues := _CueHooksScript.new()
	cues.name = "CueHooks"
	add_child(cues)
