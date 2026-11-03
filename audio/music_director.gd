extends Node

## Local presentation. The music director (group "music_director", under
## UIRoot/Audio, alive for the whole app, menu included). Music follows where
## the local player is and what's happening (docs/GAME.md "the soundtrack"):
## the theme in the menu, the work tracks on the yard by day and Golden Hour
## from 5 PM, Aisle Seven at Homie Depot, Quiet Hours anywhere after 9 PM, Hot
## Yard on a hot yard, a hard cut for a raid's warning and chase, Please Hold
## (lobby muzak) at Satellite Annex B and Clean Getaway when it turns urgent,
## and nothing while you sleep or read the day's summary. Every peer
## decides for itself from state it already has (no RPCs; docs/DECISIONS.md
## "Audio: a local music director").
##
##   pick_mood(state, current)   the rules, one pure static function
##   gather_state()              this peer's state for it
##   MusicSchedule               which track a mood plays, loops and rests
##   stinger(id)                 a short cue over the music, which ducks under it
##   push_mood / pop_mood        another feature overrides the mood (driving's road)
##   duck / request_section / set_ambience / slowdown   the NICE BOYS' hooks (R2):
##                               a gotcha's duck, the chase's "hide!" section while
##                               hidden, the van cab's muffle, closing time's
##                               dying record
## Tracks that share a sync name (annex_hold, escape_run) switch on a bar line
## and pick up at the same bar, so the Annex's muzak turns into the escape cue
## mid-phrase instead of crossfading.
## Calm changes wait MUSIC_MOOD_HOLD_SECONDS (a teleport doesn't flap the music)
## and crossfade over MUSIC_FADE_SECONDS; urgent moods switch at once over
## MUSIC_FADE_URGENT_SECONDS. The phone and the pause menu muffle the Music bus.
## M turns the music off and on through Settings (audio/music); off fades the
## director's own players out, so the Music bus volume stays the Settings slider's.
## Headless and automated runs are dry: no players or streams, but every decision
## is still taken and logged (mood_log, stinger_log) for --audio-test and the probe.

const _Tracks = preload("res://audio/music_tracks.gd")
const _Schedule = preload("res://audio/music_schedule.gd")
const _Buses = preload("res://audio/buses.gd")
const _Strings = preload("res://ui/strings.gd")
const _SfxScript = preload("res://audio/sfx.gd")
## How many entries mood_log and stinger_log keep.
const LOG_SIZE: int = 100
## A fully faded-out deck, in dB.
const SILENT_DB: float = -80.0
## net/run_events/director.gd Phase.WARNING and Phase.CHASE (not preloaded: that
## script drags the crew scene in with it).
const PHASE_WARNING: int = 1
const PHASE_CHASE: int = 2

## The moods this peer's director switched to, oldest first.
static var mood_log: Array[String] = []
## The stingers fired on this peer, oldest first (logged even when nothing plays).
static var stinger_log: Array[String] = []
## The R2 hooks' calls on this peer, oldest first (for --audio-test and the
## probe): "duck", "section hide on", "ambience van_cab on", "slowdown",
## "sync annex_hold>escape_run".
static var hook_log: Array[String] = []

var _schedule: _Schedule = _Schedule.new()
var _mood: String = ""
var _candidate: String = ""
var _candidate_for: float = 0.0
var _tick: float = 0.0
## source -> {mood, priority}
var _pushed: Dictionary = {}
var _dry: bool = true
var _music_on: bool = true
## What the schedule says is playing ("" while resting or silent).
var _track: String = ""
## Two crossfading decks: {player, gain 0..1, target, rate per second, db}.
var _decks: Array[Dictionary] = []
var _front: int = 0
var _stinger_player: AudioStreamPlayer
var _stinger_queue: Array[String] = []
var _stinger_db: float = 0.0
var _duck_db: float = 0.0
var _muffled: bool = false
## duck(): how deep (dB) and until when (msec); _hook_duck_now is where it is.
var _hook_duck_db: float = 0.0
var _hook_duck_until: int = 0
var _hook_duck_now: float = 0.0
## request_section(): the sections asked for (section -> true).
var _sections: Dictionary = {}
## set_ambience(): the beds asked for (name -> true).
var _ambience: Dictionary = {}
## slowdown(): when it began (msec) and how long it takes; -1 when not slowing.
var _slow_from: int = -1
var _slow_seconds: float = 0.0
## A bar-line switch waiting to happen: {id, at (msec), seek (seconds)}.
var _sync_pending: Dictionary = {}


func _ready() -> void:
	add_to_group("music_director")
	_dry = Net.is_automated() or DisplayServer.get_name() == "headless"
	_music_on = bool(Settings.get_value("audio", "music"))
	_schedule.rests_on = bool(Settings.get_value("audio", "music_rests"))
	Settings.changed.connect(_on_setting_changed)
	Net.state_changed.connect(func(next_state: Net.State) -> void:
		if next_state == Net.State.OFFLINE:
			_pushed.clear()
	)
	if _dry:
		return
	for index: int in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Deck%d" % (index + 1)
		player.bus = _Buses.MUSIC
		player.volume_db = SILENT_DB
		add_child(player)
		_decks.append({"player": player, "gain": 0.0, "target": 0.0, "rate": 1.0, "db": 0.0})
	_stinger_player = AudioStreamPlayer.new()
	_stinger_player.name = "Stinger"
	_stinger_player.bus = _Buses.MUSIC
	_stinger_player.finished.connect(_on_stinger_finished)
	add_child(_stinger_player)


## Let go of every stream on the way out, or they outlive the engine at quit.
func _exit_tree() -> void:
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
			(child as AudioStreamPlayer).stream = null
		child.free()
	_decks.clear()
	_stinger_player = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_music"):
		Settings.set_value("audio", "music", not _music_on)


func _process(delta: float) -> void:
	_fade(delta)
	_sync_switch()
	_hold_section()
	_tick += delta
	if _tick < Constants.MUSIC_TICK_SECONDS:
		return
	var dt := _tick
	_tick = 0.0
	_decide(dt)
	_update_muffle()


# ---------------------------------------------------------------- the API

func current_mood() -> StringName:
	return StringName(_mood)


func current_track() -> StringName:
	return StringName(_track)


## The title of what's playing, "" for nothing (the Settings window's "Now playing").
func now_playing_title() -> String:
	if _track == "" or not _music_on:
		return ""
	return _Strings.track_title(_Tracks.title_key(_track))


## The stingers fired here, oldest first (the probe reads it).
func stingers() -> Array[String]:
	return stinger_log.duplicate()


func is_muffling() -> bool:
	return _muffled


func is_dry() -> bool:
	return _dry


## A short cue over the music (MusicTracks.STINGER_IDS). It is logged even when
## its file doesn't exist yet or the music is off; the music ducks under it, and
## several in a row play one after another.
func stinger(id: StringName) -> void:
	var stinger_id := String(id)
	if not _Tracks.STINGER_IDS.has(stinger_id):
		push_warning("[Music] '%s' is not a stinger (audio/music_tracks.gd STINGER_IDS)" % stinger_id)
		return
	stinger_log.append(stinger_id)
	if stinger_log.size() > LOG_SIZE:
		stinger_log.pop_front()
	if _dry:
		print("[Music] stinger %s" % stinger_id)
		return
	if not _music_on or not _Tracks.has_track(stinger_id):
		return
	_stinger_queue.append(stinger_id)
	if not _stinger_player.playing:
		_next_stinger()


## Another feature takes over the mood while it lasts: the drivable truck pushes
## &"road" at 50 while someone drives, and an escape sequence can push &"escape"
## at 80. The highest push wins over the picked mood when its priority is at
## least that mood's (MusicTracks MOODS priority). An alias ("crossing") pushes
## the mood it names.
func push_mood(source: StringName, mood_id: StringName, priority: int) -> void:
	if not _Tracks.has_mood(String(mood_id)):
		push_warning("[Music] '%s' is not a mood (audio/music_tracks.gd MOODS)" % mood_id)
		return
	_pushed[String(source)] = {"mood": _Tracks.canonical(String(mood_id)), "priority": priority}


func pop_mood(source: StringName) -> void:
	_pushed.erase(String(source))


# ---------------------------------------------------------------- the R2 hooks
# The NICE BOYS' encounter (gap-specs nice_boys C15). Callers guard with has_method.

## The music dips db (negative) for seconds and comes back, as it does under a
## stinger: the gotcha's slap, a hold of silence.
func duck(db: float, seconds: float) -> void:
	_hook_duck_db = minf(db, 0.0)
	_hook_duck_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	_hook("duck %.0f %.2f" % [db, seconds])


## Hold the playing track in one of its sections while on (audio/music_tracks.gd
## SECTIONS: the chase's "hide!" while the local player is hidden). It jumps in
## at the next bar line and loops there; let go, it plays on out of it.
func request_section(section: StringName, on: bool) -> void:
	if on:
		_sections[String(section)] = true
	else:
		_sections.erase(String(section))
	_hook("section %s %s" % [section, "on" if on else "off"])


## A bed of sound for where the local player is: &"van_cab" muffles the music
## behind the van's walls (Constants.MUSIC_CAB_CUTOFF_HZ) and asks the world's
## ambience for the cab's own sound when it has it.
func set_ambience(bed: StringName, on: bool) -> void:
	if on:
		_ambience[String(bed)] = true
	else:
		_ambience.erase(String(bed))
	_hook("ambience %s %s" % [bed, "on" if on else "off"])
	var ambience := get_tree().get_first_node_in_group("ambience")
	if ambience != null and ambience.has_method("set_bed"):
		ambience.call("set_bed", bed, on)
	_update_muffle()


## Closing time's dying record: the music sinks in pitch over seconds and stops.
## The next track to play plays at its own speed again.
func slowdown(seconds: float) -> void:
	_slow_from = Time.get_ticks_msec()
	_slow_seconds = maxf(seconds, 0.1)
	_hook("slowdown %.2f" % seconds)


func ambience_on(bed: StringName) -> bool:
	return _ambience.has(String(bed))


func section_requested(section: StringName) -> bool:
	return _sections.has(String(section))


func _hook(entry: String) -> void:
	hook_log.append(entry)
	if hook_log.size() > LOG_SIZE:
		hook_log.pop_front()
	if _dry:
		print("[Music] %s" % entry)


# ---------------------------------------------------------------- the rules

## The mood for this state, in priority order. state keys: net_state (Net.State),
## zone (Net.Zone, -1 outside a session), hour (7 to 26), heat (0 to 100), phase
## (RunDirector.Phase), sleeping, summary_open. current is the mood playing now,
## for the hot yard's hysteresis and for holding through transit.
static func pick_mood(state: Dictionary, current: StringName) -> StringName:
	if int(state.get("net_state", Net.State.OFFLINE)) != Net.State.IN_SESSION:
		return &"title"
	var zone := int(state.get("zone", -1))
	var hour := float(state.get("hour", Constants.DAY_START_HOUR))
	var heat := float(state.get("heat", 0.0))
	var phase := int(state.get("phase", 0))
	# Satellite Annex B (R2): the lobby muzak, and the escape cue ("crossing" is
	# its old name) while the Annex is urgent (closing time, the big stamp spotted).
	if zone == Net.Zone.BORDER:
		return &"escape" if bool(state.get("annex_urgent", false)) else &"annex_hold"
	if zone == Net.Zone.LOT and phase == PHASE_CHASE:
		return &"chase"
	if zone == Net.Zone.LOT and phase == PHASE_WARNING:
		return &"warning"
	if bool(state.get("sleeping", false)) or bool(state.get("summary_open", false)):
		return &"silence"
	# Riding Chefty (or the van) keeps whatever was playing.
	if zone == Net.Zone.TRANSIT:
		return current if String(current) != "" else &"hold"
	if hour >= Constants.QUIET_HOURS_START:
		return &"night"
	if zone == Net.Zone.LOT and (heat >= Constants.MUSIC_HOT_HEAT or (current == &"hot" and heat >= Constants.MUSIC_HOT_HEAT_EXIT)):
		return &"hot"
	if zone == Net.Zone.STORE:
		return &"store"
	if hour >= Constants.MUSIC_GOLDEN_HOUR:
		return &"work_evening"
	# The yard by day, and the drivable town's streets.
	return &"work_morning"


## This peer's state for pick_mood.
func gather_state() -> Dictionary:
	var state := {
		"net_state": int(Net.current_state()),
		"zone": -1,
		"hour": Constants.DAY_START_HOUR,
		"heat": 0.0,
		"phase": 0,
		"sleeping": false,
		"summary_open": false,
		"annex_urgent": false,
	}
	if Net.current_state() != Net.State.IN_SESSION:
		return state
	var me := Net.local_peer_id()
	state["zone"] = int(Net.player_zone(me))
	var clock := get_tree().get_first_node_in_group("day_clock")
	if clock != null:
		state["hour"] = float(clock.call("hour"))
		state["sleeping"] = bool(clock.call("is_sleeping", me))
	var heat := get_tree().get_first_node_in_group("heat")
	if heat != null:
		state["heat"] = float(heat.get("heat"))
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null:
		state["phase"] = int(director.call("phase"))
	var summary := get_tree().get_first_node_in_group("day_summary") as CanvasItem
	state["summary_open"] = summary != null and summary.visible
	var annex := get_tree().get_first_node_in_group("annex")
	if annex != null and annex.has_method("urgent"):
		state["annex_urgent"] = bool(annex.call("urgent"))
	return state


# ---------------------------------------------------------------- deciding

func _decide(dt: float) -> void:
	var picked := _with_pushes(String(pick_mood(gather_state(), StringName(_mood))))
	if picked != _mood:
		if picked != _candidate:
			_candidate = picked
			_candidate_for = 0.0
		else:
			_candidate_for += dt
		if _mood == "" or _Tracks.is_urgent(picked) or _candidate_for >= Constants.MUSIC_MOOD_HOLD_SECONDS:
			_set_mood(picked)
	else:
		_candidate = ""
		_candidate_for = 0.0
	_apply(_schedule.advance(dt, StringName(_mood)))


func _with_pushes(picked: String) -> String:
	var best := ""
	var best_priority := -1
	for source: String in _pushed:
		var entry: Dictionary = _pushed[source]
		if int(entry["priority"]) > best_priority:
			best = str(entry["mood"])
			best_priority = int(entry["priority"])
	if best != "" and picked != "title" and best_priority >= _Tracks.priority(picked):
		return best
	return picked


func _set_mood(mood_id: String) -> void:
	_mood = mood_id
	_candidate = ""
	_candidate_for = 0.0
	mood_log.append(mood_id)
	if mood_log.size() > LOG_SIZE:
		mood_log.pop_front()
	if _dry:
		print("[Music] mood %s" % mood_id)


func _apply(step: Dictionary) -> void:
	match str(step["action"]):
		"play":
			var before := _track
			_track = str(step["track"])
			if _dry:
				print("[Music] play %s" % _track)
			# The muzak and the escape cue are one tune: change on the bar line.
			if before != "" and _Tracks.sync_of(before, _track) != "":
				_hook("sync %s>%s" % [before, _track])
				_play_synced(_track, float(step["fade"]))
			else:
				_play(_track, float(step["fade"]))
		"rest", "stop":
			_track = ""
			_fade_out(float(step["fade"]))


func _on_setting_changed(section: StringName, key: StringName, value: Variant) -> void:
	if section != &"audio":
		return
	if key == &"music_rests":
		_schedule.rests_on = bool(value)
	elif key == &"music" and bool(value) != _music_on:
		_music_on = bool(value)
		if _dry:
			return
		if _music_on:
			if _track != "":
				_play(_track, Constants.MUSIC_FADE_SECONDS)
		else:
			_fade_out(Constants.MUSIC_FADE_SECONDS)
			_stinger_queue.clear()
			_stinger_player.stop()
			_stinger_player.stream = null


# ---------------------------------------------------------------- playing

## Switch to id at the playing track's next bar line, at the same place in the
## song (both share the sync name, so bar n of one is bar n of the other).
## With nothing playing it is an ordinary start.
func _play_synced(id: String, fade: float) -> void:
	_sync_pending = {}
	if _dry or not _music_on:
		return
	var front: Dictionary = _decks[_front]
	var player: AudioStreamPlayer = front["player"]
	if not player.playing or float(front["target"]) <= 0.0:
		_play(id, fade)
		return
	var position := player.get_playback_position() + AudioServer.get_time_since_last_mix()
	var bar := _Tracks.bar_seconds(id)
	var next := ceilf(position / bar + 0.05) * bar
	var wait := next - position
	if wait > Constants.MUSIC_BAR_SWITCH_MAX_WAIT:
		_play(id, fade)
		return
	# Past the song's end the next bar is the loop's start.
	var song := _Tracks.seconds(id)
	if next >= song - 0.01:
		next = _Tracks.loop_offset(id) - Constants.MUSIC_ENCODE_LEAD_SECONDS + (next - song)
	_sync_pending = {"id": id, "at": Time.get_ticks_msec() + int(wait * 1000.0), "seek": next}


func _sync_switch() -> void:
	if _sync_pending.is_empty() or Time.get_ticks_msec() < int(_sync_pending["at"]):
		return
	var pending := _sync_pending
	_sync_pending = {}
	if str(pending["id"]) == _track:
		_play(str(pending["id"]), Constants.MUSIC_BAR_SWITCH_FADE, float(pending["seek"]))


## While a section is asked for and the track has it: in at the next bar line,
## round and round inside it. Let go, the song plays on out of it.
func _hold_section() -> void:
	if _dry or _sections.is_empty() or _track == "" or _decks.is_empty():
		return
	var player: AudioStreamPlayer = _decks[_front]["player"]
	if not player.playing:
		return
	for section: String in _sections:
		var span := _Tracks.section_seconds(_track, section)
		if span.is_empty():
			continue
		var position := player.get_playback_position()
		var start: float = span[0]
		var end: float = span[1]
		if position >= end - 0.005:
			player.seek(start + maxf(position - end, 0.0))
		elif position < start:
			var bar := _Tracks.bar_seconds(_track)
			var into_bar := fmod(position, bar)
			# On the bar line (within a frame), jump in.
			if into_bar < 0.03 or bar - into_bar < 0.008:
				player.seek(start + (into_bar if into_bar < 0.03 else 0.0))
		return


## Crossfade to id on the back deck over fade seconds, from `from` seconds in.
func _play(id: String, fade: float, from: float = 0.0) -> void:
	if _dry or not _music_on:
		return
	var stream := _stream(id)
	if stream == null:
		_fade_out(fade)
		return
	_slow_from = -1
	var rate := 1.0 / maxf(fade, 0.01)
	var old: Dictionary = _decks[_front]
	old["target"] = 0.0
	old["rate"] = rate
	_front = 1 - _front
	var deck: Dictionary = _decks[_front]
	var player: AudioStreamPlayer = deck["player"]
	player.stop()
	player.stream = stream
	deck["gain"] = 0.0
	deck["target"] = 1.0
	deck["rate"] = rate
	deck["db"] = float(_Tracks.track(id).get("db", 0.0))
	player.volume_db = SILENT_DB
	player.pitch_scale = 1.0
	player.play(maxf(from, 0.0))


func _fade_out(fade: float) -> void:
	for deck: Dictionary in _decks:
		deck["target"] = 0.0
		deck["rate"] = 1.0 / maxf(fade, 0.01)


## Every frame: decks move toward their targets (an equal-power curve), and
## the music ducks while a stinger plays.
func _fade(delta: float) -> void:
	if _dry:
		return
	var ducking := _stinger_player != null and _stinger_player.playing
	var duck_target := Constants.MUSIC_STINGER_DUCK_DB if ducking else 0.0
	var duck_step := absf(Constants.MUSIC_STINGER_DUCK_DB) / maxf(Constants.MUSIC_DUCK_FADE_SECONDS, 0.01) * delta
	_duck_db = move_toward(_duck_db, duck_target, duck_step)
	# duck(): the same ramp, its own depth.
	var hook_target := _hook_duck_db if Time.get_ticks_msec() < _hook_duck_until else 0.0
	_hook_duck_now = move_toward(_hook_duck_now, hook_target, absf(minf(_hook_duck_db, -1.0)) / maxf(Constants.MUSIC_DUCK_FADE_SECONDS, 0.01) * delta)
	# slowdown(): the pitch sinks, slowly at first, and the last of it fades out.
	var pitch := 1.0
	var slow_fade := 0.0
	if _slow_from >= 0:
		var k := clampf(float(Time.get_ticks_msec() - _slow_from) / 1000.0 / _slow_seconds, 0.0, 1.0)
		pitch = lerpf(1.0, Constants.MUSIC_SLOWDOWN_PITCH, k * k)
		slow_fade = linear_to_db(maxf(1.0 - smoothstep(0.7, 1.0, k), 0.0001))
	for deck: Dictionary in _decks:
		var player: AudioStreamPlayer = deck["player"]
		if _slow_from >= 0:
			player.pitch_scale = pitch
		var gain := move_toward(float(deck["gain"]), float(deck["target"]), float(deck["rate"]) * delta)
		deck["gain"] = gain
		if gain <= 0.0 and float(deck["target"]) <= 0.0:
			if player.playing or player.stream != null:
				player.stop()
				player.stream = null
			continue
		var amplitude := sin(gain * PI * 0.5)
		player.volume_db = maxf(Constants.MUSIC_TRACK_DB + float(deck["db"]) + _duck_db + _hook_duck_now + slow_fade + linear_to_db(maxf(amplitude, 0.0001)), SILENT_DB)


func _next_stinger() -> void:
	while not _stinger_queue.is_empty():
		var id: String = _stinger_queue.pop_front()
		var stream := _stream(id)
		if stream == null:
			continue
		_stinger_player.stream = stream
		_stinger_player.volume_db = Constants.MUSIC_STINGER_DB + float(_Tracks.track(id).get("db", 0.0))
		_stinger_player.play()
		return


func _on_stinger_finished() -> void:
	_stinger_player.stream = null
	_next_stinger()


## A fresh stream for a track: looping from the end of its intro when it loops.
func _stream(id: String) -> AudioStream:
	var entry := _Tracks.track(id)
	var path := str(entry.get("file", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var base := load(path) as AudioStream
	var looping := bool(entry.get("loop", false))
	if base is AudioStreamOggVorbis:
		var ogg := (base as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		ogg.loop = looping
		ogg.loop_offset = _Tracks.loop_offset(id)
		return ogg
	if base is AudioStreamWAV and looping:
		return _SfxScript.looped(path)
	return base


# ---------------------------------------------------------------- muffle

## The music sounds like it comes from another room while the phone is out or
## the pause buttons are up.
func _update_muffle() -> void:
	var want := _wants_muffle()
	var cab := _ambience.has("van_cab")
	if not _dry:
		# Behind the van's walls the music is muffled less than from another room.
		var bus := AudioServer.get_bus_index(_Buses.MUSIC)
		var slot := _Buses._muffle_slot(bus)
		if slot >= 0:
			var filter := AudioServer.get_bus_effect(bus, slot) as AudioEffectLowPassFilter
			filter.cutoff_hz = Constants.MUSIC_CAB_CUTOFF_HZ if cab and not _wants_room_muffle() else Constants.MUSIC_MUFFLE_CUTOFF_HZ
	if want == _muffled:
		return
	_muffled = want
	if not _dry:
		_Buses.set_muffled(want)


func _wants_muffle() -> bool:
	return _ambience.has("van_cab") or _wants_room_muffle()


func _wants_room_muffle() -> bool:
	if Net.current_state() != Net.State.IN_SESSION:
		return false
	var phone := get_tree().get_first_node_in_group("phone") as CanvasItem
	if phone != null and phone.visible:
		return true
	var ui := get_tree().get_first_node_in_group("game_ui")
	return ui != null and ui.has_method("pause_open") and bool(ui.call("pause_open"))
