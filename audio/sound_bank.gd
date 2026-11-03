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
	# Shops (chunk 4): the register on a confirmed buy (audio/cue_hooks.gd, the
	# buyer's own ears), and the keeper's cash drawer slamming after it (npcs/store_clerk.gd).
	"register": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.5, "db": -2.0},
	"cash_drawer": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	# Vehicles.
	"truck": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 4.0, "db": 0.0},
	"van": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 4.0, "db": 0.0},
	# The NICE BOYS' van's horn alone, as it pulls up (net/run_events/van_arrival.gd).
	"van_honk": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	# ---- nice_boys:4, the Courtesy Shuttle (net/run_events/shuttle.gd; made by
	# tools/sfx_r2_van.py): the sliding door, a buckle, the blinker, a pothole, a
	# rider's knock on the glass, the mirror's glint, and the cab radio (a loop).
	"van_door_slide": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"seatbelt_click": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.3, "db": 0.0},
	"blinker_tick": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.2, "db": -2.0},
	"van_bump": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"window_knock": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 2.0},
	"mirror_glint": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": -2.0},
	"radio_babble": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": -4.0},
	# The HUD's run-event cues (ui/run_cues.gd), heard wherever you are.
	"warning": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	"radio": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	"arrive": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.5, "db": 0.0},
	"tick": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"clear": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	# ---- audio 4b: an escape sequence (net/border_return.gd today). The starting
	# pistol and whistle when it starts (2D, it's yours), and the boing and slide
	# whistle down when a hazard throws you back (where you were hit).
	"crossing_go": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.5, "db": 0.0},
	"crossing_bonk": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
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
	# ---- R2:1 the stage (tools/sfx_r2_stage.py): the iris closing or opening (ui/iris.gd).
	"iris_swish": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.8, "db": -3.0},
	# The old 8-bar tune (until the soundtrack replaces it).
	"music_loop": {"variants": 0, "bus": &"Music", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 30.0, "db": 0.0},
	# Tool loops (audio/tool_sound.gd).
	"mower_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": 0.0},
	"blower_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": 0.0},
	"hose_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": 0.0},
	"washer_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": 0.0},
	"trimmer_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": 0.0},
	"roller_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": 0.0},
	# ---- driving: the drivable Chefty (net/components/chefty_drive.gd). The ids are
	# the ones the integration review settled (gap-specs/critic.md C12); audio chunk 7
	# may retune their recipes and drive the engine through audio/vehicle_sound.gd.
	"truck_horn": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"horn_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 2.0, "db": 0.0},
	"door_slam": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"engine_idle": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 3.0, "db": 0.0},
	"skid": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	# ---- hotbar (player/pockets.gd): picking a pocket, something going into one,
	# something coming out of one, and full pockets jangling as you walk (chunk D).
	"slot_tick": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SETTINGS_TICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.2, "db": -3.0},
	"pocket": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SETTINGS_TICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.4, "db": 0.0},
	"draw": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SETTINGS_TICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"jangle": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": -4.0},
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
