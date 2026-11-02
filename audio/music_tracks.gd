extends RefCounted

## Data, like core/ranks.gd. The soundtrack's tracks and the moods that pick
## them (docs/GAME.md "the soundtrack"; gap-specs/audio.json). The music
## director (audio/music_director.gd) and its schedule (audio/music_schedule.gd)
## read it; --audio-test checks it.
##
## TRACKS: id -> {file, bpm, bars, intro_bars, loop, stinger, title_key, db}
##   file        the .ogg tools/make_music.py and tools/encode_ogg.py made
##   bars        the whole track, intro included, in 4/4 bars
##   intro_bars  bars before the loop start (a loop goes back to A, not the top)
##   title_key   its title, ui/strings.gd MUSIC_TITLES
##   db          volume trim on top of Constants.MUSIC_TRACK_DB
## Only tracks that exist are listed (audio chunk 3). The rest of the planned
## soundtrack joins in chunks 4a and 4b, which also take "old_tune" back out:
## until then the old 8-bar loop that ambience.gd used to play stands in for
## the calm moods that have no track of their own yet.
##
## MOODS: mood -> {tracks, rests, urgent, priority, stand_in?}
##   tracks    played in turn, never the same one twice in a row when there are two
##   rests     calm music: MUSIC_LOOPS_BEFORE_REST loops, then a break of ambience only
##   urgent    switched to at once with the short fade, and never rests
##   priority  a pushed mood (push_mood) wins over a picked one of lower priority
##   stand_in  while the mood has no tracks: another mood to play instead (hot plays
##             the work music), or "hold" to keep whatever is already playing (road)
## "silence" plays nothing; "hold" is never stored, pick_mood returns the current mood for it.

const TRACKS: Dictionary = {
	"rake_it_easy": {"file": "res://assets/audio/music/rake_it_easy.ogg", "bpm": 100.0, "bars": 54, "intro_bars": 4, "loop": true, "stinger": false, "title_key": "track_rake_it_easy", "db": 0.0},
	"st_day_end": {"file": "res://assets/audio/music/st_day_end.ogg", "bpm": 60.0, "bars": 1, "intro_bars": 0, "loop": false, "stinger": true, "title_key": "track_st_day_end", "db": 0.0},
	# The old tune from the first sound pass (tools/make_loops.py), at the level it
	# always had under ambience.gd (-15 dB). Chunk 4 retires it.
	"old_tune": {"file": "res://assets/audio/sfx/music_loop.wav", "bpm": 92.0, "bars": 8, "intro_bars": 0, "loop": true, "stinger": false, "title_key": "track_old_tune", "db": -9.0},
}

const MOODS: Dictionary = {
	"title": {"tracks": ["old_tune"], "rests": false, "urgent": false, "priority": 90},
	"work_morning": {"tracks": ["rake_it_easy"], "rests": true, "urgent": false, "priority": 10},
	"work_evening": {"tracks": ["old_tune"], "rests": true, "urgent": false, "priority": 10},
	"store": {"tracks": ["old_tune"], "rests": true, "urgent": false, "priority": 10},
	"night": {"tracks": ["old_tune"], "rests": true, "urgent": false, "priority": 20},
	"hot": {"tracks": [], "rests": true, "urgent": false, "priority": 30, "stand_in": "work_morning"},
	"warning": {"tracks": [], "rests": false, "urgent": true, "priority": 60},
	"chase": {"tracks": [], "rests": false, "urgent": true, "priority": 70},
	"crossing": {"tracks": [], "rests": false, "urgent": true, "priority": 80},
	"silence": {"tracks": [], "rests": false, "urgent": false, "priority": 55},
	# The drivable truck's radio (driving pushes it); keeps what's playing until it has a track.
	"road": {"tracks": [], "rests": true, "urgent": false, "priority": 50, "stand_in": "hold"},
}

## Every stinger the game fires (MusicDirector.stinger), whether its file exists
## yet or not. Chunk 4b makes the missing ones; st_lost_em is driving's.
const STINGER_IDS: Array[String] = [
	"st_day_end", "st_rank_up", "st_season", "st_morning", "st_new_client",
	"st_job_paid", "st_busted", "st_made_it", "st_lost_em",
]


static func has_track(id: String) -> bool:
	return TRACKS.has(id)


static func track(id: String) -> Dictionary:
	return TRACKS.get(id, {}) as Dictionary


static func has_mood(mood_id: String) -> bool:
	return MOODS.has(mood_id)


static func mood(mood_id: String) -> Dictionary:
	return MOODS.get(mood_id, {}) as Dictionary


## The tracks a mood plays, in turn. Empty for silence and for moods still waiting on theirs.
static func tracks_for(mood_id: String) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in (mood(mood_id).get("tracks", []) as Array):
		out.append(str(id))
	return out


## A mood that keeps whatever is playing: "hold" itself, or one with no tracks
## yet whose stand_in is "hold" (road).
static func holds(mood_id: String) -> bool:
	if mood_id == "hold":
		return true
	return tracks_for(mood_id).is_empty() and stand_in(mood_id) == "hold"


## What a mood with no tracks yet plays instead: "hold", another mood, or "".
static func stand_in(mood_id: String) -> String:
	return str(mood(mood_id).get("stand_in", ""))


static func is_urgent(mood_id: String) -> bool:
	return bool(mood(mood_id).get("urgent", false))


static func rests(mood_id: String) -> bool:
	return bool(mood(mood_id).get("rests", false))


static func priority(mood_id: String) -> int:
	return int(mood(mood_id).get("priority", 0))


## How long the track is, intro included, by its bars (the file is 0.02 s longer).
static func seconds(id: String) -> float:
	var entry := track(id)
	if entry.is_empty():
		return 0.0
	return float(entry["bars"]) * 4.0 * 60.0 / float(entry["bpm"])


## Where a loop goes back to: the end of the intro, plus the frame the encode adds (.ogg only).
static func loop_offset(id: String) -> float:
	var entry := track(id)
	if entry.is_empty():
		return 0.0
	var lead := Constants.MUSIC_ENCODE_LEAD_SECONDS if str(entry["file"]).ends_with(".ogg") else 0.0
	return float(entry["intro_bars"]) * 4.0 * 60.0 / float(entry["bpm"]) + lead


## How long `loops` passes take: the first plays the intro, later ones start at the loop.
static func play_seconds(id: String, loops: int) -> float:
	var intro := float(track(id).get("intro_bars", 0)) * 4.0 * 60.0 / maxf(float(track(id).get("bpm", 1.0)), 1.0)
	return seconds(id) + float(maxi(loops - 1, 0)) * (seconds(id) - intro)


static func is_stinger(id: String) -> bool:
	return bool(track(id).get("stinger", false))


static func title_key(id: String) -> String:
	return str(track(id).get("title_key", ""))
