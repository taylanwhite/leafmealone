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
	"step": {"variants": 4, "bus": &"Sfx", "gap_ms": Constants.FOLEY_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0, "unit_size": Constants.FOLEY_STEP_UNIT_SIZE, "max_distance": Constants.FOLEY_STEP_MAX_DISTANCE, "near_db": 0.0, "muffle_db": Constants.FOLEY_STEP_MUFFLE_DB, "shuffle": true},
	"step_leaves": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.FOLEY_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0, "unit_size": Constants.FOLEY_STEP_UNIT_SIZE, "max_distance": Constants.FOLEY_STEP_MAX_DISTANCE, "near_db": 0.0, "muffle_db": Constants.FOLEY_STEP_MUFFLE_DB, "shuffle": true},
	"step_grass": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.FOLEY_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0, "unit_size": Constants.FOLEY_STEP_UNIT_SIZE, "max_distance": Constants.FOLEY_STEP_MAX_DISTANCE, "near_db": 0.0, "muffle_db": Constants.FOLEY_STEP_MUFFLE_DB, "shuffle": true},
	"step_hard": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.FOLEY_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": Constants.FOLEY_STEP_HARD_DB, "unit_size": Constants.FOLEY_STEP_UNIT_SIZE, "max_distance": Constants.FOLEY_STEP_MAX_DISTANCE, "near_db": 0.0, "muffle_db": Constants.FOLEY_STEP_MUFFLE_DB, "shuffle": true},
	# Work and slapstick.
	"rake": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"bag": {"variants": 2, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	# ---- raking: the rake and the leaves (R1 chunk 5, tools/sfx_leaves.py), played by
	# audio/leaf_audio.gd from the leaf field's stroke events, at the head, keyed per raker.
	"rake_plant": {"variants": 6, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.14, "db": Constants.LEAF_SFX_MIX_DB["rake_plant"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"rake_scrape": {"variants": 8, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.30, "db": Constants.LEAF_SFX_MIX_DB["rake_scrape"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"rake_empty": {"variants": 4, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.18, "db": Constants.LEAF_SFX_MIX_DB["rake_empty"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"rake_leaves_light": {"variants": 6, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.30, "db": Constants.LEAF_SFX_MIX_DB["rake_leaves_light"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"rake_leaves_med": {"variants": 6, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.42, "db": Constants.LEAF_SFX_MIX_DB["rake_leaves_med"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"rake_leaves_heavy": {"variants": 6, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.55, "db": Constants.LEAF_SFX_MIX_DB["rake_leaves_heavy"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"leaf_flick": {"variants": 4, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.22, "db": Constants.LEAF_SFX_MIX_DB["leaf_flick"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"hand_scoop": {"variants": 4, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.25, "db": Constants.LEAF_SFX_MIX_DB["hand_scoop"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"bag_open": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.25, "db": Constants.LEAF_SFX_MIX_DB["bag_open"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"bag_stuff": {"variants": 4, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.60, "db": Constants.LEAF_SFX_MIX_DB["bag_stuff"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"bag_tie": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.36, "db": Constants.LEAF_SFX_MIX_DB["bag_tie"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"leaf_settle": {"variants": 6, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.35, "db": Constants.LEAF_SFX_MIX_DB["leaf_settle"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"pile_whump": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.30, "db": Constants.LEAF_SFX_MIX_DB["pile_whump"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	"leaf_kick": {"variants": 4, "bus": &"Sfx", "gap_ms": Constants.LEAF_SFX_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.30, "db": Constants.LEAF_SFX_MIX_DB["leaf_kick"], "near_db": Constants.RAKE_SFX_NEAR_DB, "muffle_db": Constants.RAKE_SFX_MUFFLE_DB, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.RAKE_SFX_UNIT_SIZE, "max_distance": Constants.RAKE_SFX_MAX_DISTANCE, "shuffle": true},
	# Deeper leaves underfoot: audio/player_foley.gd picks them with LeafAudio.step_id.
	"step_leaves_deep": {"variants": 4, "bus": &"Sfx", "gap_ms": Constants.FOLEY_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.35, "db": 0.0, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.FOLEY_STEP_UNIT_SIZE, "max_distance": Constants.FOLEY_STEP_MAX_DISTANCE, "near_db": 0.0, "muffle_db": Constants.FOLEY_STEP_MUFFLE_DB, "shuffle": true},
	"step_leaves_pile": {"variants": 4, "bus": &"Sfx", "gap_ms": Constants.FOLEY_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.35, "db": 0.0, "wobble": Constants.RAKE_SFX_WOBBLE, "db_jitter": Constants.RAKE_SFX_DB_JITTER, "unit_size": Constants.FOLEY_STEP_UNIT_SIZE, "max_distance": Constants.FOLEY_STEP_MAX_DISTANCE, "near_db": 0.0, "muffle_db": Constants.FOLEY_STEP_MUFFLE_DB, "shuffle": true},
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
	"register": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.5, "db": -4.0},
	"cash_drawer": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	# Rusty's (shops chunk 5): his long "hmmm?" over a haggle (npcs/store_clerk.gd think).
	"haggle_hmm": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.5, "db": 0.0},
	# Shops (chunk 6): eating and drinking at the mouth (player/snack_eater.gd), the
	# Snak-o-Matic's clunk and its sad trombone (props/vending_machine.gd), and the
	# Turbo crash's yawn and the queasy burp (player.say, voices).
	"munch": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0, "shuffle": true},
	"slurp": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.6, "db": 0.0},
	"vend_clunk": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.8, "db": 0.0},
	"vend_eat": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.2, "db": -1.0},
	"vo_yawn": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.6, "db": 0.0},
	"vo_burp": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.0, "db": 0.0},
	# Shops (chunk 7): a new hat landing on a head (player/cartoon_body.gd), and
	# Chefty's paint going on in a cloud (net/components/chefty_paint.gd).
	"hat_on": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"spray_can": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.5, "db": 0.0},
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
	# Pulling away (or driving on): the putt-putt alone, no door bonk after the slam.
	"van_pull": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 3.0, "db": 0.0},
	"radio_babble": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 4.0, "db": -4.0},
	# The HUD's run-event cues (ui/run_cues.gd), heard wherever you are.
	"warning": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	"radio": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	"arrive": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.5, "db": 0.0},
	"tick": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"clear": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	# ---- audio 4b's crossing_go and crossing_bonk went with Border Return (R2
	# chunk 6); Satellite Annex B's sounds are chunk 5's (net/annex/annex.gd plays
	# stand-ins from this table until they're in).
	# The Settings window (ui/settings_window.gd): a wooden pip per slider step or
	# toggle, a soft pop for tabs and buttons, a rubber stamp for a new key binding.
	"ui_tick": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SETTINGS_TICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.2, "db": -4.0},
	"ui_pop": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SETTINGS_TICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.3, "db": -2.0},
	"ui_stamp": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	# ---- R2:2 the NICE BOYS' catch (tools/sfx_r2_crew.py): their barks (Chatter,
	# critic C2), the pea whistle, the citation scribble, the gotcha slap, the
	# lunge, the sticker, the torn page, the itemized pops, their footsteps and
	# the hop down from the van (npcs/crew_member.gd, net/run_events/encounter.gd).
	"bark": {"variants": 3, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"whistle": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.8, "db": -2.0},
	"scribble": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.5, "db": -3.0},
	"gotcha_grab": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0},
	"lunge_whoosh": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	# R2c: the wind-up's crouch, heard from his side (a wind-up out of view).
	"windup_squeak": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"sticker_slap": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"paper_tear": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0},
	"itemize_pop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.ITEMIZE_POP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.3, "db": -2.0},
	"crew_step": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.CREW_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.4, "db": -3.0},
	"hop_land": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
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
	# ---- R2:3 hiding (tools/sfx_r2_hide.py; net/components/hide_spot.gd, props/hide_spot.gd, player/hide_view.gd).
	"hedge_rustle": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.8, "db": 0.0},
	"hedge_poke": {"variants": 2, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"peek_rustle": {"variants": 2, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": -3.0},
	"bin_lid": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.8, "db": 0.0},
	"bin_clang": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.2, "db": 0.0},
	"shed_door": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.3, "db": 0.0},
	"pile_dive": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"pile_pop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"hide_bonk": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.7, "db": 0.0},
	"notice_slap": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0},
	# R2b hide: his hands close on you inside the spot (props/hide_spot.gd _found).
	"hide_grab": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": 2.0},
	# R2b hide: the shed door eased open a crack for a peek (props/hide_spot.gd _show_peek).
	"shed_creak": {"variants": 2, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	# The neighborhood (audio/ambience.gd).
	"bird": {"variants": 4, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 2.0, "db": -6.0},
	"dog": {"variants": 0, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 2.0, "db": -4.0},
	"car_pass": {"variants": 0, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 5.0, "db": 0.0},
	"wind_loop": {"variants": 0, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 10.0, "db": 0.0},
	# ---- audio:6 (tools/sfx_foley.py). The neighborhood by night and the store's
	# lot (audio/ambience.gd): crickets, an owl, Homie Depot's hum and PA, a cart,
	# a neighbor's mower a few yards over.
	"crickets_loop": {"variants": 0, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 8.0, "db": 0.0},
	"owl": {"variants": 2, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": true, "loop": false, "max_seconds": 2.0, "db": -2.0, "unit_size": Constants.AMBIENCE_UNIT_SIZE, "max_distance": Constants.AMBIENCE_MAX_DISTANCE},
	"store_hum_loop": {"variants": 0, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 6.0, "db": 0.0},
	"pa_chime": {"variants": 2, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 3.2, "db": -2.0, "unit_size": Constants.AMBIENCE_UNIT_SIZE, "max_distance": Constants.AMBIENCE_MAX_DISTANCE},
	"cart_rattle": {"variants": 2, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.6, "db": -2.0, "unit_size": Constants.AMBIENCE_UNIT_SIZE, "max_distance": Constants.AMBIENCE_MAX_DISTANCE},
	"distant_mower": {"variants": 0, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 8.0, "db": 0.0, "unit_size": Constants.AMBIENCE_UNIT_SIZE, "max_distance": Constants.AMBIENCE_FAR_MAX_DISTANCE},
	# ---- audio:6 foley (tools/sfx_foley.py): what a body does, from replicated
	# state (audio/player_foley.gd), heard where it happens.
	"paint_splat": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0},
	"splash": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.8, "db": 0.0},
	"land_thump": {"variants": 2, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0},
	"grab_yoink": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": -3.0},
	"throw_big": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.9, "db": 0.0},
	"punch_windup": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 1.5, "db": 0.0},
	"foot_pop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	# What a prop does (audio/prop_foley.gd): a ladder set up and knocked down, a
	# hose hooked up, a bag into the wheelbarrow, a pickup off the ground (never
	# a draw from a pocket: critic C12), a TurfMasters sign's first pull.
	"ladder_clack": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"ladder_crash": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.5, "db": 0.0},
	"hose_click": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"bag_plop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.7, "db": 0.0},
	"pickup_light": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.3, "db": 0.0},
	"pickup_heavy": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"sign_pull": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.7, "db": 0.0},
	# Task work at the spot (levels/lots/task_looks.gd TASK_SOUNDS), throttled per
	# 2 m patch (Constants.TASK_SFX_GAP_MS).
	"litter_crinkle": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.TASK_SFX_GAP_MS["litter_crinkle"], "voice": false, "loop": false, "max_seconds": 0.4, "db": 0.0, "shuffle": true},
	"weed_pluck": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.TASK_SFX_GAP_MS["weed_pluck"], "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0, "shuffle": true},
	"gutter_gloop": {"variants": 2, "bus": &"Sfx", "gap_ms": Constants.TASK_SFX_GAP_MS["gutter_gloop"], "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0, "shuffle": true},
	"squeegee": {"variants": 2, "bus": &"Sfx", "gap_ms": Constants.TASK_SFX_GAP_MS["squeegee"], "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0, "shuffle": true},
	"snip": {"variants": 3, "bus": &"Sfx", "gap_ms": Constants.TASK_SFX_GAP_MS["snip"], "voice": false, "loop": false, "max_seconds": 0.4, "db": 0.0, "shuffle": true},
	"splash_small": {"variants": 2, "bus": &"Sfx", "gap_ms": Constants.TASK_SFX_GAP_MS["splash_small"], "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0, "shuffle": true},
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
	# ---- R2:5 Satellite Annex B (tools/sfx_r2_annex.py): the props' own sounds
	# (props/office_props.gd, each on the frame its motion lands), the staff's
	# (npcs/clerk.gd), the receipt's printer, and the office's bed through the
	# wall (audio/ambience.gd).
	"stamp_kachunk": {"variants": 3, "bus": &"Sfx", "gap_ms": 60, "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0},
	"stamp_smudge": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": -2.0},
	"desk_bell": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	"office_ding": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.5, "db": -3.0},
	"blinds_rattle": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"shutter_roll": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.5, "db": 0.0},
	"turnstile_clack": {"variants": 0, "bus": &"Sfx", "gap_ms": 90, "voice": false, "loop": false, "max_seconds": 0.6, "db": 0.0},
	"turnstile_clunk": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.8, "db": 0.0},
	"door_chime": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.6, "db": -2.0},
	"pen_squeak": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.8, "db": -2.0},
	"receipt_print": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.5, "db": -2.0},
	"punch_card": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"copier_beep": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.6, "db": -4.0},
	"clerk_snore": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.5, "db": -3.0},
	"party_toot": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"closing_bell": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	"lights_off_clunk": {"variants": 0, "bus": &"Sfx", "gap_ms": 120, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"office_phone": {"variants": 0, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": -4.0},
	"typewriter_bed": {"variants": 0, "bus": &"Ambience", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 10.0, "db": 0.0},
	# ---- driving: the drivable Chefty (net/components/chefty_drive.gd). The ids are
	# the ones the integration review settled (gap-specs/critic.md C12); audio chunk 7
	# may retune their recipes and drive the engine through audio/vehicle_sound.gd.
	"truck_horn": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"horn_loop": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 2.0, "db": 0.0},
	"door_slam": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"engine_idle": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 3.0, "db": 0.0},
	"skid": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	# ---- driving C3: Chefty's crash comedy (net/components/chefty_crash.gd): a crash
	# (clang, boing, a short slide whistle), a big one (crunch, a slide whistle down,
	# a car alarm's warble), and bags flying out of the bed (pomf-pomf).
	"crash": {"variants": 0, "bus": &"Sfx", "gap_ms": 200, "voice": false, "loop": false, "max_seconds": 1.4, "db": 0.0, "max_distance": Constants.CHEFTY_SOUND_MAX_DISTANCE},
	"crash_big": {"variants": 0, "bus": &"Sfx", "gap_ms": 200, "voice": false, "loop": false, "max_seconds": 2.6, "db": 0.0, "max_distance": Constants.CHEFTY_SOUND_MAX_DISTANCE},
	"bag_spill": {"variants": 0, "bus": &"Sfx", "gap_ms": 150, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	# R2c van: the Courtesy Shuttle's brakes, its own squeal (it borrowed skid, which
	# its engine buried), carrying as far as the engine does.
	"van_brake": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.2, "db": 0.0, "unit_size": Constants.VAN_BRAKE_UNIT_SIZE, "max_distance": Constants.VAN_ENGINE_MAX_DISTANCE},
	# ---- hotbar (player/pockets.gd): picking a pocket, something going into one,
	# something coming out of one, and full pockets jangling as you walk (chunk D).
	"slot_tick": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SETTINGS_TICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.2, "db": -3.0},
	"pocket": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SETTINGS_TICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.4, "db": 0.0},
	"draw": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SETTINGS_TICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"jangle": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_STEP_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": -4.0},
	# ---- bags: throw into Chefty: a bag landing in the bed (props/truck_bed_load.gd).
	"bed_thump": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SETTINGS_TICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.8, "db": 0.0},
	# ---- audio:5 UI, store, phone and day sounds (tools/sfx_ui.py). Buttons
	# (audio/ui_sounds.gd), the phone and windows are this player's own ears (UI);
	# the coin, the homeowner's cash and the cot happen in the world (play_at).
	"ui_click": {"variants": 0, "bus": &"UI", "gap_ms": Constants.UI_CLICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.2, "db": 0.0},
	"ui_hover": {"variants": 0, "bus": &"UI", "gap_ms": Constants.UI_HOVER_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.1, "db": -6.0},
	"ui_back": {"variants": 0, "bus": &"UI", "gap_ms": Constants.UI_CLICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.3, "db": 0.0},
	"ui_tab": {"variants": 0, "bus": &"UI", "gap_ms": Constants.UI_CLICK_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.2, "db": 0.0},
	"ui_deny": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.4, "db": 0.0},
	"store_bell": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.5, "db": -5.0},
	"coin": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.COIN_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": -3.0},
	"receipt": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.2, "db": -2.0},
	"cash_grab": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"pin": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.3, "db": 0.0},
	"phone_open": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.8, "db": -1.0},
	"phone_close": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": -1.0},
	"phone_buzz": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"text_pop": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.5, "db": 0.0},
	"text_bad": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	"phone_take": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 0.8, "db": 0.0},
	"quiet_chime": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 3.0, "db": -2.0},
	"closing_yawn": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 2.0, "db": 0.0},
	"cot_creak": {"variants": 0, "bus": &"Sfx", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0, "max_distance": Constants.COT_CREAK_MAX_DISTANCE},
	"task_done": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": -1.0},
	"heat_whoop": {"variants": 0, "bus": &"UI", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": false, "max_seconds": 1.0, "db": 0.0},
	# Registered and generated only: audio:6's player foley plays it while someone sleeps.
	"snore_loop": {"variants": 0, "bus": &"Chatter", "gap_ms": Constants.SFX_DEFAULT_GAP_MS, "voice": false, "loop": true, "max_seconds": 5.0, "db": -4.0},
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


## Optional per-id keys (the rake and leaf sounds use them; every other id keeps
## the defaults below, which are what Sfx always did):
##   wobble        pitch lands in 1 +- this (default: Constants.SFX_PITCH_WOBBLE)
##   db_jitter     volume lands in +- this many dB (default 0)
##   unit_size     full volume inside this many meters (default Constants.SFX_UNIT_SIZE)
##   max_distance  silent past this many meters (default Constants.SFX_MAX_DISTANCE)
##   shuffle       variants come from a shuffle bag: each once per refill (default false)
##   near_db       up close, at most this many dB over its own volume (default:
##                 Godot's max_db, 3 dB over nothing, whatever the volume)
##   muffle_db     the distance low-pass's depth (default: Godot's -24 dB)

## The pitch range of one play, as a multiple of normal.
static func wobble(id: String) -> Vector2:
	var e := entry(id)
	if not e.has("wobble"):
		return Constants.SFX_PITCH_WOBBLE
	var w := float(e["wobble"])
	return Vector2(1.0 - w, 1.0 + w)


static func db_jitter(id: String) -> float:
	return float(entry(id).get("db_jitter", 0.0))


static func unit_size(id: String) -> float:
	return float(entry(id).get("unit_size", Constants.SFX_UNIT_SIZE))


static func max_distance(id: String) -> float:
	return float(entry(id).get("max_distance", Constants.SFX_MAX_DISTANCE))


static func shuffle(id: String) -> bool:
	return bool(entry(id).get("shuffle", false))


## near_db: up close a positional play of id is at most this many dB over its own
## volume (Sfx.configure_3d sets max_db to volume + this). Without it Godot's
## max_db (3 dB) caps volume and distance gain together, flattening its trims.
static func has_near_db(id: String) -> bool:
	return entry(id).has("near_db")


static func near_db(id: String) -> float:
	return float(entry(id).get("near_db", 0.0))


## muffle_db: the most Godot's distance low-pass (attenuation_filter_db, -24 by
## default) takes off id's highs.
static func has_muffle_db(id: String) -> bool:
	return entry(id).has("muffle_db")


static func muffle_db(id: String) -> float:
	return float(entry(id).get("muffle_db", -24.0))


## A character noise (vo_*, babble, dog, bird): it moves a mouth.
static func is_voice(id: String) -> bool:
	return bool(entry(id).get("voice", id.begins_with("vo_")))
