extends RefCounted

## Data, like core/ranks.gd. The soundtrack's tracks and the moods that pick
## them (docs/GAME.md "the soundtrack"; gap-specs/audio.json). The music
## director (audio/music_director.gd) and its schedule (audio/music_schedule.gd)
## read it; --audio-test checks it.
##
## TRACKS: id -> {file, bpm, bars, intro_bars, loop, stinger, title_key, db, sync?}
##   file        the .ogg tools/make_music.py and tools/encode_ogg.py made
##   bpm         the exact tempo make_music.py rendered ("bpm_exact" in its
##               sidecar): it nudges a song's tempo so the loop and its intro are
##               whole 20 ms frames, and loop_offset() is only sample-exact with it
##   bars        the whole track, intro included, in 4/4 bars
##   intro_bars  bars before the loop start (a loop goes back to A, not the top)
##   title_key   its title, ui/strings.gd MUSIC_TITLES
##   db          volume trim on top of Constants.MUSIC_TRACK_DB
##   sync        tracks with the same sync name share tempo and bars: a switch
##               between them waits for the next bar line and picks up at the
##               same place (annex_hold and escape_run)
## Only tracks that exist are listed. The calm moods' music came in audio chunk
## 4a (it retired the old 8-bar stand-in loop); the tension tracks and the rest
## of the stingers in 4b (st_lost_em with driving:F).
##
## MOODS: mood -> {tracks, rests, urgent, priority, stand_in?}, or {alias: mood}
##   tracks    played in turn, never the same one twice in a row when there are two
##   rests     calm music: MUSIC_LOOPS_BEFORE_REST loops, then a break of ambience only
##   urgent    switched to at once with the short fade, and never rests
##   priority  a pushed mood (push_mood) wins over a picked one of lower priority
##   stand_in  while the mood has no tracks: another mood to play instead, or "hold"
##             to keep whatever is already playing (road)
##   alias     another name for that mood: every function here answers for the mood
##             it names, and the director stores the real one (canonical())
## "silence" plays nothing; "hold" is never stored, pick_mood returns the current mood for it.

const TRACKS: Dictionary = {
	"rake_it_easy": {"file": "res://assets/audio/music/rake_it_easy.ogg", "bpm": 100.0, "bars": 54, "intro_bars": 4, "loop": true, "stinger": false, "title_key": "track_rake_it_easy", "db": 0.0},
	"st_day_end": {"file": "res://assets/audio/music/st_day_end.ogg", "bpm": 60.0, "bars": 1, "intro_bars": 0, "loop": false, "stinger": true, "title_key": "track_st_day_end", "db": 0.0},
	# The calm moods (audio chunk 4a; docs/GAME.md "the calm moods' music").
	"leaf_me_alone_theme": {"file": "res://assets/audio/music/leaf_me_alone_theme.ogg", "bpm": 96.0, "bars": 44, "intro_bars": 4, "loop": true, "stinger": false, "title_key": "track_leaf_me_alone_theme", "db": 0.0},
	"curb_appeal": {"file": "res://assets/audio/music/curb_appeal.ogg", "bpm": 108.1081081081081, "bars": 48, "intro_bars": 4, "loop": true, "stinger": false, "title_key": "track_curb_appeal", "db": 0.0},
	"golden_hour": {"file": "res://assets/audio/music/golden_hour.ogg", "bpm": 88.07339449541284, "bars": 40, "intro_bars": 4, "loop": true, "stinger": false, "title_key": "track_golden_hour", "db": 0.0},
	"homie_depot_muzak": {"file": "res://assets/audio/music/homie_depot_muzak.ogg", "bpm": 111.8881118881119, "bars": 48, "intro_bars": 4, "loop": true, "stinger": false, "title_key": "track_homie_depot_muzak", "db": 0.0},
	"quiet_hours": {"file": "res://assets/audio/music/quiet_hours.ogg", "bpm": 80.0, "bars": 40, "intro_bars": 4, "loop": true, "stinger": false, "title_key": "track_quiet_hours", "db": 0.0},
	# ---- audio 4b: the tense half (tools/music_tension.py). A loop's bpm is the
	# exact tempo make_music.py rendered (its .json sidecar's bpm_exact), nudged
	# so the loop is a whole number of 20 ms frames; loop_offset needs it exact.
	"hot_yard": {"file": "res://assets/audio/music/hot_yard.ogg", "bpm": 115.94202898550725, "bars": 48, "intro_bars": 4, "loop": true, "stinger": false, "title_key": "track_hot_yard", "db": 0.0},
	"nice_boys_incoming": {"file": "res://assets/audio/music/nice_boys_incoming.ogg", "bpm": 128.0, "bars": 8, "intro_bars": 0, "loop": true, "stinger": false, "title_key": "track_nice_boys_incoming", "db": 0.0},
	"nice_boys_chase": {"file": "res://assets/audio/music/nice_boys_chase.ogg", "bpm": 151.89873417721518, "bars": 64, "intro_bars": 4, "loop": true, "stinger": false, "title_key": "track_nice_boys_chase", "db": 0.0},
	# The escape/end-sequence cue: Border Return's lanes today, the Field Office escape later.
	"escape_run": {"file": "res://assets/audio/music/escape_run.ogg", "bpm": 144.14414414414415, "bars": 40, "intro_bars": 4, "loop": true, "stinger": false, "title_key": "track_escape_run", "db": 0.0, "sync": "getaway"},
	# ---- R2:5 Satellite Annex B's lobby muzak (tools/music_tension.py annex_hold):
	# Clean Getaway for vibraphone and brushes, the same tempo, form and bars, so
	# the switch between them waits for a bar line and lands on the same bar
	# (MusicDirector, "sync").
	"annex_hold": {"file": "res://assets/audio/music/annex_hold.ogg", "bpm": 144.14414414414415, "bars": 40, "intro_bars": 4, "loop": true, "stinger": false, "title_key": "track_annex_hold", "db": 0.0, "sync": "getaway"},
	"st_rank_up": {"file": "res://assets/audio/music/st_rank_up.ogg", "bpm": 100.0, "bars": 1, "intro_bars": 0, "loop": false, "stinger": true, "title_key": "track_st_rank_up", "db": 0.0},
	"st_season": {"file": "res://assets/audio/music/st_season.ogg", "bpm": 96.0, "bars": 1, "intro_bars": 0, "loop": false, "stinger": true, "title_key": "track_st_season", "db": 0.0},
	"st_morning": {"file": "res://assets/audio/music/st_morning.ogg", "bpm": 110.0, "bars": 1, "intro_bars": 0, "loop": false, "stinger": true, "title_key": "track_st_morning", "db": 0.0},
	"st_new_client": {"file": "res://assets/audio/music/st_new_client.ogg", "bpm": 100.0, "bars": 1, "intro_bars": 0, "loop": false, "stinger": true, "title_key": "track_st_new_client", "db": 0.0},
	"st_job_paid": {"file": "res://assets/audio/music/st_job_paid.ogg", "bpm": 120.0, "bars": 1, "intro_bars": 0, "loop": false, "stinger": true, "title_key": "track_st_job_paid", "db": 0.0},
	"st_busted": {"file": "res://assets/audio/music/st_busted.ogg", "bpm": 92.0, "bars": 1, "intro_bars": 0, "loop": false, "stinger": true, "title_key": "track_st_busted", "db": 0.0},
	"st_made_it": {"file": "res://assets/audio/music/st_made_it.ogg", "bpm": 132.0, "bars": 1, "intro_bars": 0, "loop": false, "stinger": true, "title_key": "track_st_made_it", "db": 0.0},
	# driving:F: the NICE BOYS' van gives up the chase (net/run_events/pursuit.gd, ui/run_cues.gd).
	"st_lost_em": {"file": "res://assets/audio/music/st_lost_em.ogg", "bpm": 126.0, "bars": 1, "intro_bars": 0, "loop": false, "stinger": true, "title_key": "track_st_lost_em", "db": 0.0},
}

const MOODS: Dictionary = {
	"title": {"tracks": ["leaf_me_alone_theme"], "rests": false, "urgent": false, "priority": 90},
	"work_morning": {"tracks": ["rake_it_easy", "curb_appeal"], "rests": true, "urgent": false, "priority": 10},
	"work_evening": {"tracks": ["golden_hour"], "rests": true, "urgent": false, "priority": 10},
	"store": {"tracks": ["homie_depot_muzak"], "rests": true, "urgent": false, "priority": 10},
	"night": {"tracks": ["quiet_hours"], "rests": true, "urgent": false, "priority": 20},
	"hot": {"tracks": ["hot_yard"], "rests": true, "urgent": false, "priority": 30},
	"warning": {"tracks": ["nice_boys_incoming"], "rests": false, "urgent": true, "priority": 60},
	"chase": {"tracks": ["nice_boys_chase"], "rests": false, "urgent": true, "priority": 70},
	# An escape or end sequence: Border Return's lanes today (pick_mood's BORDER),
	# the NICE BOYS' Field Office escape later (push_mood or a pick_mood rule).
	"escape": {"tracks": ["escape_run"], "rests": false, "urgent": true, "priority": 80},
	# Satellite Annex B (pick_mood's BORDER): the lobby muzak, until the Annex
	# turns urgent (closing time, the big stamp spotted) and it switches to escape.
	"annex_hold": {"tracks": ["annex_hold"], "rests": false, "urgent": false, "priority": Constants.ANNEX_HOLD_PRIORITY},
	# The old name for escape, still accepted everywhere a mood id is (MOOD_ALIASES).
	"crossing": {"alias": "escape"},
	"silence": {"tracks": [], "rests": false, "urgent": false, "priority": 55},
	# The drivable truck's radio (driving pushes it); keeps what's playing until it has a track.
	"road": {"tracks": [], "rests": true, "urgent": false, "priority": 50, "stand_in": "hold"},
}

## Every stinger the game fires (MusicDirector.stinger), whether its file exists
## yet or not. All of them have one (st_lost_em came with driving:F's pursuit).
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
	return MOODS.get(canonical(mood_id), {}) as Dictionary


## The mood an alias stands for ("crossing" -> "escape"); any other id as it is.
static func canonical(mood_id: String) -> String:
	var entry: Dictionary = MOODS.get(mood_id, {})
	return str(entry["alias"]) if entry.has("alias") else mood_id


static func is_alias(mood_id: String) -> bool:
	return canonical(mood_id) != mood_id


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

## Sections a playing track can be held in (MusicDirector.request_section):
## track -> {section: [first bar, end bar)} in the track's own bars, intro
## included. The chase's half-time "hide!" section for hidden players.
const SECTIONS: Dictionary = {
	"nice_boys_chase": {"hide": [28, 36]},
}


## Where a section of a track starts and ends, in seconds into its file's song
## (without the encode lead), or [] when the track has no such section.
static func section_seconds(id: String, section: String) -> Array:
	var bars: Array = (SECTIONS.get(id, {}) as Dictionary).get(section, [])
	if bars.size() < 2 or not TRACKS.has(id):
		return []
	var bar := bar_seconds(id)
	return [float(bars[0]) * bar, float(bars[1]) * bar]


## One 4/4 bar of a track, in seconds.
static func bar_seconds(id: String) -> float:
	return 4.0 * 60.0 / maxf(float(track(id).get("bpm", 120.0)), 1.0)


## The silence an encode puts before a track's first beat (s; .ogg only).
static func lead_seconds(id: String) -> float:
	return Constants.MUSIC_ENCODE_LEAD_SECONDS if str(track(id).get("file", "")).ends_with(".ogg") else 0.0


## A cut to id on the next bar line, from `position` seconds into the playing
## file (the two tracks share tempo, form and encode lead): {"wait": seconds
## until that bar line, "seek": where in id's file to start}, or {} when the bar
## line is further off than Constants.MUSIC_BAR_SWITCH_MAX_WAIT. A bar line at
## or past the song's end is the loop's start (plus however far past it is).
static func bar_switch(id: String, position: float) -> Dictionary:
	var bar := bar_seconds(id)
	var lead := lead_seconds(id)
	var into := position - lead
	# A bar line less than a twentieth of a bar off is too close to make: the next.
	var next := ceilf(into / bar + 0.05) * bar
	var wait := next - into
	if wait > Constants.MUSIC_BAR_SWITCH_MAX_WAIT:
		return {}
	var song := seconds(id)
	if next >= song - 0.01:
		next = loop_offset(id) - lead + (next - song)
	return {"wait": wait, "seek": next + lead}


## Where a track held in `section` jumps to from `position` seconds into its
## file, or -1.0 to play on: from the section's end back to its start, and from
## before it in on a bar line (`frame` is how late a check can be, s).
static func section_seek(id: String, section: String, position: float, frame: float = 0.03) -> float:
	var span := section_seconds(id, section)
	if span.is_empty():
		return -1.0
	var lead := lead_seconds(id)
	var start: float = float(span[0]) + lead
	var end: float = float(span[1]) + lead
	if position >= end - 0.005:
		return start + maxf(position - end, 0.0)
	if position < start:
		var bar := bar_seconds(id)
		var into_bar := fmod(position - lead, bar)
		if into_bar < frame:
			return start + into_bar
		if bar - into_bar < 0.008:
			return start
	return -1.0


## The sync name two tracks share, or "" when a switch between them is an
## ordinary crossfade.
static func sync_of(a: String, b: String) -> String:
	var sync_a := str(track(a).get("sync", ""))
	return sync_a if sync_a != "" and sync_a == str(track(b).get("sync", "")) and a != b else ""
