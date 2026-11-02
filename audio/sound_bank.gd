extends RefCounted

## Data. Every sound effect id the game plays, and how it plays. audio/sfx.gd,
## the tool loops, ambience and the character voices all read it, and
## --audio-test (net/dev/audio_test.gd) checks that every id has its files and
## that every id the code names is in here. Add a new sound here and generate it
## in tools/make_sfx.py or tools/make_loops.py, or the test fails.
##
## Each entry:
##   variants     numbered files <id>_1.wav ... (0 means one file, <id>.wav)
##   bus          an audio/buses.gd bus
##   gap_ms       the least time between two plays of it
##   voice        a character noise (it moves a mouth; player.say keeps it)
##   loop         played looped (tools, engines, wind, music)
##   max_seconds  the longest a file may be (the test checks it)
##   db           volume trim, added to whatever the caller asks for

const DIR := "res://assets/audio/sfx/"

const SOUNDS: Dictionary = {
	# Footsteps.
	"step": {"variants": 4, "bus": &"Sfx", "gap_ms": Constants.SFX_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"step_leaves": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.SFX_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0},
	"step_grass": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.SFX_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0},
	"step_hard": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.SFX_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0},
	# Work and slapstick.
	"rake": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"bag": {"variants": 2, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"bonk": {"variants": 2, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"thud": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.5, "db": 0.0},
	"whoosh": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"dizzy": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	"pullcord": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"mower_start": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	"chop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"grind": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.5, "db": 0.0},
	# Gas (shops chunk 3): a gas tool running dry, and the gas can filling one.
	"sputter": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	"glug": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	# Vehicles.
	"truck": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 4.0, "db": 0.0},
	"van": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 4.0, "db": 0.0},
	# The HUD's run-event cues (ui/run_cues.gd), heard wherever you are.
	"warning": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	"radio": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	"arrive": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.5, "db": 0.0},
	"tick": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"clear": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	# The Settings window (ui/settings_window.gd): a wooden pip per slider step or
	# toggle, a soft pop for tabs and buttons, a rubber stamp for a new key binding.
	"ui_tick": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SETTINGS_TICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.2, "db": -4.0},
	"ui_pop": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SETTINGS_TICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.3, "db": -2.0},
	"ui_stamp": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	# Character noises.
	"babble": {"variants": 5, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.5, "db": 0.0},
	"vo_ah": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"vo_eh": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"vo_heave": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"vo_huh": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"vo_hup": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"vo_oof": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"vo_strain": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.5, "db": 0.0},
	"vo_yelp": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.0, "db": 0.0},
	# The neighborhood (audio/ambience.gd).
	"bird": {"variants": 4, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 2.0, "db": -6.0},
	"dog": {"variants": 0, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 2.0, "db": -4.0},
	"car_pass": {"variants": 0, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 5.0, "db": 0.0},
	"wind_loop": {"variants": 0, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 10.0, "db": 0.0},
	# The old 8-bar tune (until the soundtrack replaces it).
	"music_loop": {"variants": 0, "bus": &"Music", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 30.0, "db": 0.0},
	# Tool loops (audio/tool_sound.gd).
	"mower_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": 0.0},
	"blower_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": 0.0},
	"hose_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": 0.0},
	"washer_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": 0.0},
	"trimmer_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": 0.0},
	"roller_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": 0.0},
}


static func has(id: String) -> bool:
	return SOUNDS.has(id)


## The entry for an id, or {} when it isn't registered.
static func entry(id: String) -> Dictionary:
	return SOUNDS.get(id, {}) as Dictionary


## Every file of an id, variants in order.
static func files(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var count := int(entry(id).get("variants", 0))
	if count <= 0:
		out.append("%s%s.wav" % [DIR, id])
	else:
		for variant: int in range(1, count + 1):
			out.append("%s%s_%d.wav" % [DIR, id, variant])
	return out


## The bus an id plays on; unknown ids go on Sfx.
static func bus(id: String) -> StringName:
	return StringName(entry(id).get("bus", &"Sfx"))


static func gap_ms(id: String) -> int:
	return int(entry(id).get("gap_ms", Constants.SFX_DEFAULT_GAP_MS))


static func db(id: String) -> float:
	return float(entry(id).get("db", 0.0))


static func is_loop(id: String) -> bool:
	return bool(entry(id).get("loop", false))


## A character noise (vo_*, babble, dog, bird): it moves a mouth.
static func is_voice(id: String) -> bool:
	return bool(entry(id).get("voice", id.begins_with("vo_")))
