extends RefCounted

## Local presentation, pure and deterministic. Which track a mood plays and
## when the music takes a break, so a 10 to 20 hour game doesn't grate (docs/GAME.md
## "the soundtrack"). The music director feeds it the mood every tick; headless
## tests feed it simulated time. It never touches a player.
##
## advance(dt, mood) -> {action, track, fade}
##   "play"  start track, crossfading over fade seconds
##   "keep"  nothing changes (track is what's playing, "" while resting)
##   "rest"  fade out over fade seconds and play nothing for a while
##   "stop"  fade out: the mood plays nothing (silence, or no track yet)
## Calm moods (MusicTracks rests) play a track for MUSIC_LOOPS_BEFORE_REST loops,
## rest MUSIC_REST_SECONDS (a seeded random length), then play the mood's next
## track in turn. Urgent moods use the short fade and never rest. A mood that holds
## (MusicTracks.holds: road, hold) keeps the previous mood's music going and its
## loop count running; a mood with no tracks yet and a stand_in mood plays that one
## (hot plays the work music). A mood that lists the track already playing keeps it.

const _Tracks = preload("res://audio/music_tracks.gd")

## The "Breaks between songs" setting (Settings audio/music_rests).
var rests_on: bool = true

var _rng := RandomNumberGenerator.new()
## The mood whose music is being served (never a holding mood).
var _mood: String = ""
## What's playing, "" for nothing.
var _track: String = ""
## Seconds of _track played since it started.
var _played: float = 0.0
## Seconds of rest left, 0 when not resting.
var _rest_left: float = 0.0
## mood -> how many tracks it has started, for taking turns.
var _turns: Dictionary = {}


## seed_value 0 picks a random seed.
func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


func current_track() -> String:
	return _track


func is_resting() -> bool:
	return _rest_left > 0.0


func advance(dt: float, mood_id: StringName) -> Dictionary:
	var mood_name := String(mood_id)
	# Hot, the truck's radio, and transit keep the music that was on.
	if _Tracks.holds(mood_name):
		if _mood == "":
			return _keep()
		mood_name = _mood
	elif _Tracks.tracks_for(mood_name).is_empty() and _Tracks.has_mood(_Tracks.stand_in(mood_name)):
		# Hot plays the work music until it has a track of its own.
		mood_name = _Tracks.stand_in(mood_name)
	var tracks := _Tracks.tracks_for(mood_name)
	var fade := Constants.MUSIC_FADE_URGENT_SECONDS if _Tracks.is_urgent(mood_name) else Constants.MUSIC_FADE_SECONDS
	if mood_name != _mood:
		_mood = mood_name
		_rest_left = 0.0
		if tracks.has(_track):
			_played += dt
			return _keep()
		if tracks.is_empty():
			return _stop(fade)
		return _start(tracks, fade)
	if _rest_left > 0.0:
		_rest_left -= dt
		if _rest_left > 0.0:
			return _keep()
		_rest_left = 0.0
		return _start(tracks, Constants.MUSIC_FADE_SECONDS) if not tracks.is_empty() else _keep()
	if _track == "":
		return _start(tracks, fade) if not tracks.is_empty() else _keep()
	_played += dt
	if _Tracks.rests(mood_name) and rests_on and _played >= _Tracks.play_seconds(_track, Constants.MUSIC_LOOPS_BEFORE_REST):
		_track = ""
		_played = 0.0
		_rest_left = _rng.randf_range(Constants.MUSIC_REST_SECONDS.x, Constants.MUSIC_REST_SECONDS.y)
		return {"action": "rest", "track": "", "fade": Constants.MUSIC_FADE_SECONDS}
	return _keep()


func _start(tracks: Array[String], fade: float) -> Dictionary:
	var turn := int(_turns.get(_mood, 0))
	var pick := tracks[turn % tracks.size()]
	# Taking turns already avoids a repeat, unless the mood changed in between.
	if pick == _track and tracks.size() > 1:
		turn += 1
		pick = tracks[turn % tracks.size()]
	_turns[_mood] = turn + 1
	_track = pick
	_played = 0.0
	return {"action": "play", "track": pick, "fade": fade}


func _stop(fade: float) -> Dictionary:
	var was := _track
	_track = ""
	_played = 0.0
	if was == "":
		return _keep()
	return {"action": "stop", "track": "", "fade": fade}


func _keep() -> Dictionary:
	return {"action": "keep", "track": _track, "fade": 0.0}
