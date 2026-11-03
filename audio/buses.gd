extends RefCounted

## Local presentation. The mixer buses, made at runtime (there is no
## default_bus_layout.tres; docs/DECISIONS.md, "Audio: buses, a sound bank,
## positional sounds"). Every AudioStreamPlayer sets .bus to one of these,
## through its audio/sound_bank.gd entry where it plays a sound id:
##   Music     the soundtrack and stingers, with a low-pass for "another room"
##   Sfx       sound effects; Ambience and UI send into it
##   Ambience  wind, birds, the dog, passing cars
##   UI        menu clicks and the HUD's run cues
##   Chatter   character noises: NPC babble, vo_*, the player's mouth, crew barks
##   Voice     proximity voice chat
##   SfxClear  effects right at a hider's own ears (audio/sfx.gd play_clear): it
##             skips the hiding muffle on Sfx (player/hide_view.gd) but follows
##             Sfx's volume and mute (FOLLOWS; the settings have no fader for it)
## ensure() is idempotent: ui_root, audio_root and tools call it freely.

const MASTER := &"Master"
const MUSIC := &"Music"
const SFX := &"Sfx"
const AMBIENCE := &"Ambience"
const UI := &"UI"
const CHATTER := &"Chatter"
const VOICE := &"Voice"
const SFX_CLEAR := &"SfxClear"

## Each bus and the bus it sends to, in creation order.
const LAYOUT: Array = [
	[&"Music", &"Master"],
	[&"Sfx", &"Master"],
	[&"Ambience", &"Sfx"],
	[&"UI", &"Sfx"],
	[&"Chatter", &"Master"],
	[&"Voice", &"Master"],
	[&"SfxClear", &"Master"],
]
## A bus that takes another's volume and mute, not a fader of its own.
const FOLLOWS: Dictionary = {&"SfxClear": &"Sfx"}


static func ensure() -> void:
	for entry: Array in LAYOUT:
		var bus_name: StringName = entry[0]
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	# Sends once every bus exists, so Ambience can find Sfx.
	for entry: Array in LAYOUT:
		AudioServer.set_bus_send(AudioServer.get_bus_index(entry[0]), entry[1])
	var music := AudioServer.get_bus_index(MUSIC)
	if _muffle_slot(music) < 0:
		var low_pass := AudioEffectLowPassFilter.new()
		low_pass.cutoff_hz = Constants.MUSIC_MUFFLE_CUTOFF_HZ
		AudioServer.add_bus_effect(music, low_pass)
		AudioServer.set_bus_effect_enabled(music, AudioServer.get_bus_effect_count(music) - 1, false)
	sync_followers()


## Every FOLLOWS bus takes its leader's volume and mute now (core/settings.gd
## calls it whenever it sets the faders).
static func sync_followers() -> void:
	for follower: StringName in FOLLOWS:
		var index := AudioServer.get_bus_index(follower)
		var leader := AudioServer.get_bus_index(FOLLOWS[follower])
		if index < 0 or leader < 0:
			continue
		AudioServer.set_bus_volume_db(index, AudioServer.get_bus_volume_db(leader))
		AudioServer.set_bus_mute(index, AudioServer.is_bus_mute(leader))


## True when every bus is there and sends where LAYOUT says.
static func is_ready() -> bool:
	for entry: Array in LAYOUT:
		var index := AudioServer.get_bus_index(entry[0])
		if index < 0 or AudioServer.get_bus_send(index) != entry[1]:
			return false
	return _muffle_slot(AudioServer.get_bus_index(MUSIC)) >= 0


## Music sounds like it comes from another room (phone out, pause menu open).
static func set_muffled(on: bool) -> void:
	var music := AudioServer.get_bus_index(MUSIC)
	var slot := _muffle_slot(music)
	if slot >= 0:
		AudioServer.set_bus_effect_enabled(music, slot, on)


static func is_muffled() -> bool:
	var music := AudioServer.get_bus_index(MUSIC)
	var slot := _muffle_slot(music)
	return slot >= 0 and AudioServer.is_bus_effect_enabled(music, slot)


static func _muffle_slot(bus: int) -> int:
	if bus < 0:
		return -1
	for slot: int in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, slot) is AudioEffectLowPassFilter:
			return slot
	return -1
