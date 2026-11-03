extends Node

## Authority: host. --audio-test checks the audio core (gap-specs/audio.json,
## chunk 1; docs/DECISIONS.md "Audio: buses, a sound bank, positional sounds"):
##   bank_files   every audio/sound_bank.gd id has all its files, and they load
##                with a sane length (loops at least LOOP_MIN_SECONDS)
##   source_scan  every sound id or audio path the code names is registered or exists
##   buses        the mixer buses exist, send where they should, and the Music
##                low-pass muffles and unmuffles
##   sfx_node     Sfx lives at UIRoot/Audio/Sfx in group "sfx"
##   sfx_api      play and play_at log, the bank's gap throttles, unknown ids are caught
##   ride_truck   Chefty's departure sound is a play_on the truck's body (Sfx.placed),
##                and the ride reaches the lot
##   positional   a bag, a throw and a heavy bonk on the lot are play_at where they
##                happened (Sfx.placed), not 2D
##   no_unknown   nothing asked Sfx for an unregistered id during the whole run
##   music_files  every .ogg in assets/audio/music (tools/make_music.py, then
##                tools/encode_ogg.py; chunk 2) loads as Vorbis with a sane length
## The music director (chunk 3; docs/DECISIONS.md "Audio: a local music director"):
##   moods          every mood has tracks unless MOODS_WAITING lists it, every track it
##                  names is in TRACKS and loads at its length, stingers and titles line up,
##                  loops are 60 to 150 s (the warning's may be 15) and loop back to a
##                  whole 20 ms frame (audio chunk 4a)
##   picker_table   pick_mood's rules, case by case, and push_mood over them
##   schedule_sim   900 simulated seconds of work music: loops, a rest, the next
##                  track; urgent moods fade fast and never rest; rests can be off
##   store_morning  the director (group music_director) plays the store at 8 AM
##   now_playing    the Settings window's Sound tab has its "Now playing" row, and
##                  opened from the pause buttons it keeps the music muffled
##   register       a confirmed buy at Homie Depot rings the register cue
##   ride_to_lot    the mood holds through Chefty's ride, then the yard's work music
##   hot            a hot yard (heat) gets Hot Yard
##   raid           the warning cuts in at once, then the chase, then back after
##   day_end        sleeping: Clock Out then Promoted!, silence under the card, Rise
##                  and Rake when it closes, and one buzz for the night's texts
##   escape         (chunk 4b) the border cuts to the escape music, the crossing's
##                  start, throw-back and finish play their pistol, boing and
##                  "Made It Back"; "crossing" is still a mood (escape's alias)
## The Target client checks itself through its probe "audio" report: its stingers
## must include Clock Out and Promoted! (ci_local and netcode.yml).
## Each step prints an [AudioTest] line.

const _Bank = preload("res://audio/sound_bank.gd")
const _Buses = preload("res://audio/buses.gd")
const _SfxScript = preload("res://audio/sfx.gd")
const _Tracks = preload("res://audio/music_tracks.gd")
const _Schedule = preload("res://audio/music_schedule.gd")
const _Director = preload("res://audio/music_director.gd")
const _CueHooks = preload("res://audio/cue_hooks.gd")
const _Strings = preload("res://ui/strings.gd")
const _Ranks = preload("res://core/ranks.gd")
## A looping track's file may be this far from its bars' length (seconds).
const TRACK_LENGTH_SLACK: float = 0.6
## A stinger is at most this long.
const STINGER_MAX_SECONDS: float = 6.0
## A looping track's length by its bars, shortest to longest (gap-specs/audio.json, check 2).
const LOOP_TRACK_SECONDS: Vector2 = Vector2(60.0, 150.0)
## A track only the raid warning plays may loop this short.
const WARNING_LOOP_MIN_SECONDS: float = 15.0
## tools/make_music.py puts a loop's intro on this grid (Movie Maker's fixed fps in tools/encode_ogg.py).
const MUSIC_FRAMES_PER_SECOND: float = 50.0
## Simulated seconds of work music in schedule_sim.
const SIM_SECONDS: float = 900.0
const SIM_STEP: float = 0.25
## Extra seconds a mood change may take past MUSIC_MOOD_HOLD_SECONDS (ticks, fades).
const MOOD_SLACK_SECONDS: float = 1.0
## The moods allowed to have no tracks yet (silence never has any). Every other
## mood fails the moods check without one; audio chunks 4a and 4b take each mood
## out of this list as they give it its track, so the check tightens with them.
const MOODS_WAITING: Array[String] = ["road"]
## How long the host waits for the Target client before going on alone.
const CLIENT_WAIT_SECONDS: float = 10.0

## A loop shorter than this would stutter.
const LOOP_MIN_SECONDS: float = 0.5
## The soundtrack: every track is at most 150 s plus the one frame the encode adds.
const MUSIC_DIR: String = "res://assets/audio/music/"
const MUSIC_MAX_SECONDS: float = 150.5
## How long the ride may take before the test gives up on it.
const RIDE_TIMEOUT_SECONDS: float = 20.0
## Where the source scan doesn't look.
const SCAN_SKIP: Array[String] = ["res://addons", "res://.godot", "res://build", "res://tools/audio/jukebox.gd"]
## Calls whose string arguments are sound ids: the sfx group's methods called
## by name, Sfx's own methods on a receiver named sfx..., and the sound helpers
## (say, stinger, looped and the per-node wrappers). Not AnimationPlayer.play().
const ID_CALLS: Array[String] = [
	"\\.call\\(\"(?:play|play_at|play_on|say|say_to_all|stinger)\",\\s*",
	"(?i)\\bsfx\\w*(?:\\(\\))?\\.(?:play|play_at|play_on)\\(",
	"(?<!\\w)(?:say|say_to_all|_say|_speak|_play_sfx|_play|_one_shot|_loop_player|stinger|_stinger)\\(",
	"\\blooped\\(",
]

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or Net.current_state() != Net.State.IN_SESSION:
		return
	if get_tree().get_first_node_in_group("world") == null or _me() == null:
		return
	_started = true
	_run()


func _run() -> void:
	result = {"done": false, "checks": {}, "missing": [], "unknown_ids": [], "bad_lengths": [], "pick_failures": []}
	await get_tree().create_timer(1.0).timeout
	_check("bank_files", _bank_files())
	_check("source_scan", _source_scan())
	_check("buses", _buses())
	_check("music_files", _music_files())
	_check("moods", _moods())
	_check("picker_table", _picker_table())
	_check("schedule_sim", _schedule_sim())
	# The Target client rides along, and checks its own stingers in its report.
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < CLIENT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	print("[AudioTest] players: %d" % Net.peer_ids().size())
	if Net.peer_ids().size() > 1:
		await get_tree().create_timer(1.0).timeout
	var sfx := get_tree().get_first_node_in_group("sfx")
	var at_home := sfx != null and str(sfx.get_path()).ends_with("UIRoot/Audio/Sfx")
	print("[AudioTest] Sfx is at %s" % (str(sfx.get_path()) if sfx != null else "nowhere"))
	_check("sfx_node", at_home)
	if sfx == null:
		_finish("no Sfx node in group sfx")
		return
	_check("sfx_api", _sfx_api(sfx))
	var music := get_tree().get_first_node_in_group("music_director")
	print("[AudioTest] the music director is at %s" % (str(music.get_path()) if music != null else "nowhere"))
	if music == null:
		_check("store_morning", false)
		_finish("no node in group music_director")
		return
	_check("push_mood", _push_mood(music))
	_check("store_morning", await _wait_mood(music, [&"store"], 2.0))
	_check("now_playing", await _now_playing(music))
	_check("register", await _register())
	_check("ride_truck", await _ride(music))
	_check("positional", await _positional())
	_check("hot", await _hot(music))
	_check("raid", await _raid(music))
	_check("day_end", await _day_end(music))
	_check("escape", await _escape(music))
	_check("annex_music", await _annex_music(music))
	_SfxScript.unknown.erase(_bogus_id())
	result["unknown_ids"] = _SfxScript.unknown.duplicate()
	_check("no_unknown", _SfxScript.unknown.is_empty())
	_finish("")


func _check(check_name: String, ok: bool) -> void:
	(result["checks"] as Dictionary)[check_name] = ok
	print("[AudioTest] %s: %s" % [check_name, ok])


func _finish(error: String) -> void:
	var ok := error == ""
	for value: Variant in (result["checks"] as Dictionary).values():
		ok = ok and bool(value)
	result["ok"] = ok
	result["error"] = error
	result["done"] = true
	print("[AudioTest] done, ok=%s %s" % [ok, error])


# ---------------------------------------------------------------- static checks

func _bank_files() -> bool:
	var ok := true
	var files := 0
	for id: String in _Bank.SOUNDS:
		var entry := _Bank.entry(id)
		for path: String in _Bank.files(id):
			files += 1
			if not ResourceLoader.exists(path):
				(result["missing"] as Array).append(path)
				ok = false
				continue
			var stream := load(path) as AudioStream
			var seconds := stream.get_length() if stream != null else 0.0
			var too_long := seconds > float(entry["max_seconds"])
			var too_short := seconds <= 0.0 or (bool(entry["loop"]) and seconds < LOOP_MIN_SECONDS)
			if too_long or too_short:
				(result["bad_lengths"] as Array).append("%s %.2fs" % [path, seconds])
				ok = false
	print("[AudioTest] %d ids, %d files; missing %s, bad lengths %s" % [_Bank.SOUNDS.size(), files, result["missing"], result["bad_lengths"]])
	return ok


func _source_scan() -> bool:
	var heads: Array[RegEx] = []
	for pattern: String in ID_CALLS:
		heads.append(RegEx.create_from_string(pattern))
	var path_rx := RegEx.create_from_string("\"(res://assets/audio/[^\"%]+)\"")
	var scripts: Array[String] = []
	_walk("res://", scripts)
	var bad: Array[String] = []
	var ids_seen := 0
	for script_path: String in scripts:
		var text := FileAccess.get_file_as_string(script_path)
		for line: String in text.split("\n"):
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			for head: RegEx in heads:
				for found: RegExMatch in head.search_all(line):
					for id: String in _ids_in(_args_after(line, found.get_end())):
						ids_seen += 1
						# A stinger is music (audio/music_tracks.gd), not a sound effect.
						if not _Bank.has(id) and not _Tracks.STINGER_IDS.has(id):
							bad.append("%s: %s" % [script_path.get_file(), id])
			for found: RegExMatch in path_rx.search_all(line):
				var named := found.get_string(1)
				var there := DirAccess.dir_exists_absolute(named) if named.ends_with("/") else (ResourceLoader.exists(named) or FileAccess.file_exists(named))
				if not there:
					bad.append("%s: %s" % [script_path.get_file(), found.get_string(1)])
	(result["unknown_ids"] as Array).append_array(bad)
	print("[AudioTest] scanned %d scripts, %d sound ids named; unregistered %s" % [scripts.size(), ids_seen, bad])
	# The scanner itself: it reads ids out of a ternary and a list, and leaves
	# comparisons, lookups, nested calls and an AnimationPlayer alone.
	var samples := {
		"\tsfx.call(\"play_at\", \"thud\" if tier == \"heavy\" else \"bonk\", at)": ["thud", "bonk"],
		"\tsay_to_all(\"vo_yelp\" if is_in_group(\"vans\") else \"vo_ah\")": ["vo_yelp", "vo_ah"],
		"\t_speak(str(staging[\"sound\"]))": [],
		"\tplayer.call(\"say\", [\"vo_hup\", \"vo_eh\"][randi() % 3])": ["vo_hup", "vo_eh"],
		"\t_anim.play(\"walk\")": [],
	}
	var scanner_ok := true
	for sample: String in samples:
		var got: Array[String] = []
		for head: RegEx in heads:
			for found: RegExMatch in head.search_all(sample):
				got.append_array(_ids_in(_args_after(sample, found.get_end())))
		if got != Array(samples[sample], TYPE_STRING, "", null):
			print("[AudioTest] scanner read %s from %s" % [got, sample])
			scanner_ok = false
	print("[AudioTest] the scanner reads ids right: %s" % scanner_ok)
	return bad.is_empty() and scanner_ok


func _music_files() -> bool:
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		print("[AudioTest] no %s" % MUSIC_DIR)
		return false
	var ok := true
	var count := 0
	for file: String in dir.get_files():
		# Vorbis normally; a WAV when tools/encode_ogg.py --wav-fallback wrote it.
		var stream: AudioStream = null
		if file.ends_with(".ogg"):
			stream = load(MUSIC_DIR.path_join(file)) as AudioStreamOggVorbis
		elif file.ends_with(".wav"):
			stream = load(MUSIC_DIR.path_join(file)) as AudioStreamWAV
		else:
			continue
		count += 1
		var path := MUSIC_DIR.path_join(file)
		var seconds := stream.get_length() if stream != null else 0.0
		var good := stream != null and seconds > 1.0 and seconds <= MUSIC_MAX_SECONDS
		print("[AudioTest] music %s: %s, %.4f s" % [file, stream.get_class() if stream != null else "not Vorbis/WAV", seconds])
		if not good:
			(result["bad_lengths"] as Array).append("%s %.2fs" % [path, seconds])
		ok = ok and good
	return ok and count > 0


func _walk(dir_path: String, out: Array[String]) -> void:
	for skip: String in SCAN_SKIP:
		if dir_path.trim_suffix("/") == skip:
			return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		var path := dir_path.path_join(file)
		if file.ends_with(".gd") and not SCAN_SKIP.has(path):
			out.append(path)


## The text of a call's arguments, from just after its "(" (or after the
## method-name argument) to its closing ")", skipping parentheses in strings.
func _args_after(line: String, from: int) -> String:
	var depth := 1
	var quoted := false
	var index := from
	while index < line.length():
		var c := line[index]
		if c == "\"" and (index == 0 or line[index - 1] != "\\"):
			quoted = not quoted
		elif not quoted:
			if c == "(":
				depth += 1
			elif c == ")":
				depth -= 1
				if depth == 0:
					break
		index += 1
	return line.substr(from, index - from)


## The string literals in a call's arguments that are sound ids: not dictionary
## keys ("a": ...), not compared against (== "a"), not indexes (x["a"]) and not
## arguments of a call nested inside (is_in_group("a")).
func _ids_in(args: String) -> Array[String]:
	var out: Array[String] = []
	var rx := RegEx.create_from_string("\"([^\"\\\\]*)\"")
	for found: RegExMatch in rx.search_all(args):
		var value := found.get_string(1)
		var before := args.substr(0, found.get_start()).strip_edges(false, true)
		var after := args.substr(found.get_end()).strip_edges(true, false)
		if value == "" or value.contains("%") or after.begins_with(":"):
			continue
		if before.ends_with("==") or before.ends_with("!="):
			continue
		# staging["sound"] is an index; ["a", "b"][i] is a list of ids.
		if before.ends_with("[") and before.length() > 1 and (_is_word(before[before.length() - 2]) or before[before.length() - 2] in ["]", ")"]):
			continue
		if before.ends_with("(") and before.length() > 1 and _is_word(before[before.length() - 2]):
			continue
		if value.begins_with("res://"):
			continue
		out.append(value)
	return out


func _is_word(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")


func _buses() -> bool:
	_Buses.ensure()
	_Buses.ensure()
	var ready := _Buses.is_ready()
	var count := AudioServer.bus_count
	var off_at_start := not _Buses.is_muffled()
	_Buses.set_muffled(true)
	var muffled := _Buses.is_muffled()
	_Buses.set_muffled(false)
	var clear := not _Buses.is_muffled()
	var names: Array[String] = []
	for index: int in count:
		names.append("%s->%s" % [AudioServer.get_bus_name(index), AudioServer.get_bus_send(index)])
	# ensure() twice must not add a second set of buses.
	var once := true
	for entry: Array in _Buses.LAYOUT:
		var seen := 0
		for index: int in count:
			if AudioServer.get_bus_name(index) == String(entry[0]):
				seen += 1
		once = once and seen == 1
	print("[AudioTest] buses %s; layout right %s, made once %s, muffle off/on/off %s/%s/%s" % [names, ready, once, off_at_start, muffled, clear])
	return ready and once and off_at_start and muffled and clear


# ---------------------------------------------------------------- live checks

func _sfx_api(sfx: Node) -> bool:
	var before := _SfxScript.log.count("tick")
	sfx.call("play", "tick")
	sfx.call("play", "tick")
	var logged_once: bool = _SfxScript.log.count("tick") == before + 1 and _SfxScript.log.back() == "tick"
	var me := _me()
	sfx.call("play_at", "grind", me.global_position)
	var positional: bool = _SfxScript.log.back() == "grind" and _placed_at("grind", me.global_position)
	sfx.call("play", _bogus_id())
	var caught := _SfxScript.unknown.has(_bogus_id())
	var buses_right := _Bank.bus("babble") == _Buses.CHATTER and _Bank.bus("wind_loop") == _Buses.AMBIENCE and _Bank.bus("tick") == _Buses.UI and _Bank.bus("bonk") == _Buses.SFX and _Bank.bus("music_loop") == _Buses.MUSIC
	var voices_right := _Bank.is_voice("vo_oof") and _Bank.is_voice("babble") and _Bank.is_voice("dog") and not _Bank.is_voice("bonk")
	print("[AudioTest] play logs once inside its gap %s, play_at logs %s, unknown ids caught %s, bank buses %s, voices %s" % [logged_once, positional, caught, buses_right, voices_right])
	return logged_once and positional and caught and buses_right and voices_right


## Chefty takes everyone at the store to the lot. Its sound rides on the truck,
## and (ride_to_lot) the music holds the store's mood through the ride and turns
## to the yard's work music once there.
func _ride(music: Node) -> bool:
	var chefty := get_tree().get_first_node_in_group("chefty")
	if chefty == null:
		print("[AudioTest] no Chefty")
		_check("ride_to_lot", false)
		return false
	var body := chefty.get("_body") as Node3D
	var before := _SfxScript.log.count("truck")
	var mood_before := str(music.call("current_mood"))
	_SfxScript.placed.clear()
	chefty.call("depart", Net.players_in_zone(Net.Zone.STORE), Net.Zone.LOT)
	await get_tree().create_timer(0.3).timeout
	# It has to ride on the truck's body, not play 2D or stay at the curb.
	var entry := _placed("truck")
	var on_body: bool = body != null and not entry.is_empty() and entry["kind"] == "on" and entry["node"] == str(body.get_path())
	var heard: bool = _SfxScript.log.count("truck") > before and on_body
	var waited := 0.0
	var moods_in_transit: Array[String] = []
	while Net.player_zone(Net.local_peer_id()) != Net.Zone.LOT and waited < RIDE_TIMEOUT_SECONDS:
		if Net.player_zone(Net.local_peer_id()) == Net.Zone.TRANSIT:
			var now := str(music.call("current_mood"))
			if not moods_in_transit.has(now):
				moods_in_transit.append(now)
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var arrived := Net.player_zone(Net.local_peer_id()) == Net.Zone.LOT
	print("[AudioTest] Chefty's truck sound %s rides on %s" % [entry, str(body.get_path()) if body != null else "no body"])
	print("[AudioTest] Chefty's truck sound on departure %s, arrived on the lot %s after %.1f s" % [heard, arrived, waited])
	var held := moods_in_transit.size() == 1 and moods_in_transit[0] == mood_before
	var to_work := arrived and await _wait_mood(music, [&"work_morning"], Constants.MUSIC_MOOD_HOLD_SECONDS + MOOD_SLACK_SECONDS)
	print("[AudioTest] the music in transit %s (was %s), then %s on the lot" % [moods_in_transit, mood_before, music.call("current_mood")])
	_check("ride_to_lot", held and to_work)
	return heard and arrived


func _positional() -> bool:
	var world := get_tree().get_first_node_in_group("world")
	var me := _me()
	await get_tree().create_timer(0.5).timeout
	var at := me.global_position + (-me.global_transform.basis.z) * 1.5
	var props_before := get_tree().get_nodes_in_group("props").size()
	_SfxScript.placed.clear()
	world.call("_spawn_bag", at, 5)
	var bag_heard: bool = _SfxScript.log.back() == "bag" and _placed_at("bag", at)
	await get_tree().create_timer(0.3).timeout
	var props := get_tree().get_nodes_in_group("props")
	if props.size() <= props_before:
		print("[AudioTest] the bag never showed up")
		return false
	var prop := props.back() as Node3D
	var where := prop.global_position
	var before := [_SfxScript.log.count("whoosh"), _SfxScript.log.count("thud"), _SfxScript.log.count("dizzy")]
	prop.call("_rpc_throw_fx")
	prop.call("_rpc_bonk_fx", NodePath(), "heavy", Vector3.ZERO)
	var after := [_SfxScript.log.count("whoosh"), _SfxScript.log.count("thud"), _SfxScript.log.count("dizzy")]
	var fx_heard := int(after[0]) > int(before[0]) and int(after[1]) > int(before[1]) and int(after[2]) > int(before[2])
	# With no target, the bonk plays where the prop is.
	var fx_placed := _placed_at("whoosh", where) and _placed_at("thud", where) and _placed_at("dizzy", where)
	print("[AudioTest] bag %s; whoosh, thud, dizzy before %s and after %s, at the prop %s" % [bag_heard, before, after, fx_placed])
	return bag_heard and fx_heard and fx_placed


# ---------------------------------------------------------------- the music director, static

func _moods() -> bool:
	var ok := true
	var bad: Array[String] = []
	var waiting: Array[String] = []
	for mood_id: String in _Tracks.MOODS:
		var tracks := _Tracks.tracks_for(mood_id)
		var stand_in := _Tracks.stand_in(mood_id)
		if tracks.is_empty() and mood_id != "silence":
			waiting.append(mood_id)
			if not MOODS_WAITING.has(mood_id):
				bad.append("%s has no tracks and is not in MOODS_WAITING" % mood_id)
		elif MOODS_WAITING.has(mood_id):
			bad.append("%s has tracks now: take it out of MOODS_WAITING" % mood_id)
		if stand_in != "" and stand_in != "hold" and (not _Tracks.has_mood(stand_in) or _Tracks.tracks_for(stand_in).is_empty()):
			bad.append("%s stands in with %s, which plays nothing" % [mood_id, stand_in])
		for id: String in tracks:
			if not _Tracks.has_track(id) or _Tracks.is_stinger(id):
				bad.append("%s names %s, not a looping track" % [mood_id, id])
	for id: String in _Tracks.TRACKS:
		if _Tracks.is_stinger(id) and not _Tracks.STINGER_IDS.has(id):
			bad.append("%s is a stinger missing from STINGER_IDS" % id)
		if _Strings.track_title(_Tracks.title_key(id)) == "":
			bad.append("%s has no title" % id)
		var path := str(_Tracks.track(id)["file"])
		if not ResourceLoader.exists(path):
			(result["missing"] as Array).append(path)
			ok = false
			continue
		var stream := load(path) as AudioStream
		var seconds := stream.get_length() if stream != null else 0.0
		var good := seconds > 0.0 and seconds <= STINGER_MAX_SECONDS if _Tracks.is_stinger(id) else absf(seconds - _Tracks.seconds(id)) <= TRACK_LENGTH_SLACK
		print("[AudioTest] track %s: %.3f s for %.3f s of bars, loops back to %.4f s" % [id, seconds, _Tracks.seconds(id), _Tracks.loop_offset(id)])
		if not good:
			(result["bad_lengths"] as Array).append("%s %.2fs" % [path, seconds])
			ok = false
		if not _Tracks.is_stinger(id):
			# A loop is LOOP_TRACK_SECONDS long (the raid warning's may be shorter), and
			# its intro ends on a whole 20 ms frame, so the loop point is a whole sample:
			# true only with the exact tempo make_music.py rendered (music_tracks.gd, bpm).
			var floor_seconds := LOOP_TRACK_SECONDS.x if not _warning_only(id) else WARNING_LOOP_MIN_SECONDS
			if _Tracks.seconds(id) < floor_seconds or _Tracks.seconds(id) > LOOP_TRACK_SECONDS.y:
				bad.append("%s is %.1f s, outside %.0f-%.0f s" % [id, _Tracks.seconds(id), floor_seconds, LOOP_TRACK_SECONDS.y])
			var intro_frames := (_Tracks.loop_offset(id) - Constants.MUSIC_ENCODE_LEAD_SECONDS) * MUSIC_FRAMES_PER_SECOND
			if absf(intro_frames - roundf(intro_frames)) > 0.001:
				bad.append("%s loops back to %.6f s, between frames: is its bpm the exact one?" % [id, _Tracks.loop_offset(id)])
	for id: String in _Tracks.STINGER_IDS:
		if _Strings.track_title("track_" + id) == "":
			bad.append("stinger %s has no title" % id)
	# An alias names a real mood and answers exactly as it does ("crossing" is escape's old name).
	for mood_id: String in _Tracks.MOODS:
		var target := _Tracks.canonical(mood_id)
		if target == mood_id:
			continue
		if not _Tracks.has_mood(target) or _Tracks.is_alias(target):
			bad.append("alias %s names %s, not a mood" % [mood_id, target])
		elif _Tracks.tracks_for(mood_id) != _Tracks.tracks_for(target) or _Tracks.priority(mood_id) != _Tracks.priority(target) or _Tracks.is_urgent(mood_id) != _Tracks.is_urgent(target):
			bad.append("alias %s doesn't answer like %s" % [mood_id, target])
	if _Tracks.canonical("crossing") != "escape":
		bad.append("crossing is not escape's alias")
	print("[AudioTest] %d moods, %d tracks; waiting for a track of their own %s; problems %s" % [_Tracks.MOODS.size(), _Tracks.TRACKS.size(), waiting, bad])
	return ok and bad.is_empty()


## True when the raid warning is the only mood that plays this track.
func _warning_only(id: String) -> bool:
	var moods: Array[String] = []
	for mood_id: String in _Tracks.MOODS:
		if _Tracks.tracks_for(mood_id).has(id):
			moods.append(mood_id)
	return moods.size() == 1 and moods[0] == "warning"


## A state for pick_mood.
func _state(net_state: int, zone: int, hour: float, heat: float = 0.0, phase: int = 0, sleeping: bool = false, summary_open: bool = false) -> Dictionary:
	return {"net_state": net_state, "zone": zone, "hour": hour, "heat": heat, "phase": phase, "sleeping": sleeping, "summary_open": summary_open}


func _picker_table() -> bool:
	var on := int(Net.State.IN_SESSION)
	var lot := int(Net.Zone.LOT)
	var store := int(Net.Zone.STORE)
	var chase := _Director.PHASE_CHASE
	var warning := _Director.PHASE_WARNING
	# [name, state, current mood, expected]
	var cases: Array = [
		["lobby", _state(Net.State.LOBBY, -1, 8.0), &"", &"title"],
		["offline", _state(Net.State.OFFLINE, -1, 8.0), &"store", &"title"],
		["the Annex at 23:00", _state(on, Net.Zone.BORDER, 23.0), &"chase", &"annex_hold"],
		["the Annex while hot", _state(on, Net.Zone.BORDER, 10.0, 90.0), &"hot", &"annex_hold"],
		["the Annex turns urgent", _state(on, Net.Zone.BORDER, 10.0).merged({"annex_urgent": true}, true), &"annex_hold", &"escape"],
		["lot chase at 22:00", _state(on, lot, 22.0, 20.0, chase), &"night", &"chase"],
		["lot warning", _state(on, lot, 10.0, 20.0, warning), &"work_morning", &"warning"],
		["a raid beats the summary card", _state(on, lot, 10.0, 0.0, chase, false, true), &"silence", &"chase"],
		["lot heat 70", _state(on, lot, 10.0, 70.0), &"work_morning", &"hot"],
		["lot heat 60, already hot", _state(on, lot, 10.0, 60.0), &"hot", &"hot"],
		["lot heat 60, not hot yet", _state(on, lot, 10.0, 60.0), &"work_morning", &"work_morning"],
		["lot heat 50, was hot", _state(on, lot, 10.0, 50.0), &"hot", &"work_morning"],
		["lot at 18:00", _state(on, lot, 18.0), &"work_morning", &"work_evening"],
		["lot at 22:00", _state(on, lot, 22.0, 10.0), &"work_evening", &"night"],
		["lot heat 90 at 22:00", _state(on, lot, 22.0, 90.0), &"hot", &"night"],
		["store at 10:00", _state(on, store, 10.0), &"", &"store"],
		["store heat 90", _state(on, store, 10.0, 90.0), &"store", &"store"],
		["store at 23:00", _state(on, store, 23.0), &"store", &"night"],
		["store closed at 2 AM", _state(on, store, 26.0), &"night", &"night"],
		["transit holds the store", _state(on, Net.Zone.TRANSIT, 10.0), &"store", &"store"],
		["transit holds the night", _state(on, Net.Zone.TRANSIT, 23.0), &"night", &"night"],
		["transit with nothing on", _state(on, Net.Zone.TRANSIT, 10.0), &"", &"hold"],
		["asleep on a cot", _state(on, store, 22.0, 0.0, 0, true), &"night", &"silence"],
		["the summary card", _state(on, store, 8.0, 0.0, 0, false, true), &"store", &"silence"],
		["the town by day", _state(on, Net.Zone.TOWN, 10.0), &"store", &"work_morning"],
		["the town at 18:00", _state(on, Net.Zone.TOWN, 18.0), &"work_morning", &"work_evening"],
	]
	var failures: Array[String] = []
	for case: Array in cases:
		var got := _Director.pick_mood(case[1], case[2])
		if got != case[3] or (got != &"hold" and not _Tracks.has_mood(String(got))):
			failures.append("%s: %s, not %s" % [case[0], got, case[3]])
	(result["pick_failures"] as Array).append_array(failures)
	print("[AudioTest] %d picker cases; wrong %s" % [cases.size(), failures])
	return failures.is_empty()


## A stand-in for the director's tick: feed a schedule one mood for a while and
## note every change it asks for, as [time, action, track, fade].
func _simulate(schedule: _Schedule, mood_id: StringName, seconds: float, from: float, out: Array) -> float:
	var t := from
	while t < from + seconds:
		var step: Dictionary = schedule.advance(SIM_STEP, mood_id)
		if str(step["action"]) != "keep":
			out.append([t, str(step["action"]), str(step["track"]), float(step["fade"])])
		t += SIM_STEP
	return t


func _schedule_sim() -> bool:
	var work := _Tracks.tracks_for("work_morning")
	if work.is_empty():
		print("[AudioTest] work_morning has no tracks")
		return false
	# Work hours: a track for its loops, a rest, then the next track in turn.
	var events: Array = []
	_simulate(_Schedule.new(1234), &"work_morning", SIM_SECONDS, 0.0, events)
	var first_play: bool = events.size() >= 3 and events[0][1] == "play" and events[0][2] == work[0] and is_equal_approx(float(events[0][0]), 0.0) and is_equal_approx(float(events[0][3]), Constants.MUSIC_FADE_SECONDS)
	var loops_end := _Tracks.play_seconds(work[0], Constants.MUSIC_LOOPS_BEFORE_REST)
	var rested: bool = first_play and events[1][1] == "rest" and absf(float(events[1][0]) - loops_end) <= SIM_STEP + 0.001
	var rest_for := float(events[2][0]) - float(events[1][0]) if events.size() >= 3 else -1.0
	var rest_ok := rest_for >= Constants.MUSIC_REST_SECONDS.x and rest_for <= Constants.MUSIC_REST_SECONDS.y + SIM_STEP
	var next_ok: bool = events.size() >= 3 and events[2][1] == "play" and events[2][2] == work[1 % work.size()]
	print("[AudioTest] work music %s (loops end at %.2f s, rested %.2f s)" % [events.slice(0, 4), loops_end, rest_for])
	# Breaks between songs off: it never rests.
	var no_rests := _Schedule.new(99)
	no_rests.rests_on = false
	var plain: Array = []
	_simulate(no_rests, &"work_morning", SIM_SECONDS, 0.0, plain)
	var never_rests := plain.size() >= 1 and plain.all(func(event: Array) -> bool: return event[1] != "rest")
	# A raid: the chase cuts in with the short fade and never rests; a hot yard
	# crossfades to Hot Yard (calm, the long fade) before it.
	var raid := _Schedule.new(7)
	var raid_events: Array = []
	var t := _simulate(raid, &"work_morning", 10.0, 0.0, raid_events)
	var hot_from := raid_events.size()
	t = _simulate(raid, &"hot", 10.0, t, raid_events)
	var hot_events := raid_events.slice(hot_from)
	var hot_track := _Tracks.tracks_for("hot")
	var hot_keeps: bool = not hot_track.is_empty() and hot_events.size() == 1 and hot_events[0][1] == "play" \
		and hot_events[0][2] == hot_track[0] and is_equal_approx(float(hot_events[0][3]), Constants.MUSIC_FADE_SECONDS)
	var chase_from := raid_events.size()
	_simulate(raid, &"chase", 300.0, t, raid_events)
	var chase_events := raid_events.slice(chase_from)
	var urgent := chase_events.size() >= 1 and is_equal_approx(float(chase_events[0][3]), Constants.MUSIC_FADE_URGENT_SECONDS) \
		and chase_events.all(func(event: Array) -> bool: return event[1] != "rest")
	print("[AudioTest] rests off never rests %s; a hot yard crossfades to %s %s; the chase %s" % [never_rests, hot_track, hot_keeps, chase_events])
	return first_play and rested and rest_ok and next_ok and never_rests and hot_keeps and urgent


# ---------------------------------------------------------------- the music director, live

func _push_mood(music: Node) -> bool:
	music.call("push_mood", &"audio_test", &"road", 50)
	var over_store := str(music.call("_with_pushes", "store")) == "road"
	var under_chase := str(music.call("_with_pushes", "chase")) == "chase"
	var not_title := str(music.call("_with_pushes", "title")) == "title"
	music.call("pop_mood", &"audio_test")
	var popped := str(music.call("_with_pushes", "store")) == "store"
	# An escape sequence can push the old name; the director plays the mood it stands for.
	music.call("push_mood", &"audio_test", &"crossing", _Tracks.priority("escape"))
	var alias_pushed := str(music.call("_with_pushes", "chase")) == "escape"
	music.call("pop_mood", &"audio_test")
	print("[AudioTest] a pushed road mood beats the store %s, not a chase %s, not the menu %s, and pops %s; a pushed crossing plays escape over a chase %s" % [over_store, under_chase, not_title, popped, alias_pushed])
	return over_store and under_chase and not_title and popped and alias_pushed


## Waits up to seconds for the director's mood to be one of moods.
func _wait_mood(music: Node, moods: Array, seconds: float) -> bool:
	var waited := 0.0
	while waited <= seconds:
		if moods.has(music.call("current_mood")):
			print("[AudioTest] mood %s after %.2f s" % [music.call("current_mood"), waited])
			return true
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	print("[AudioTest] mood %s, not %s, after %.2f s" % [music.call("current_mood"), moods, seconds])
	return false


## The Settings window's Sound tab shows "Now playing" once a director exists,
## with the title of what the director is playing.
func _now_playing(music: Node) -> bool:
	var ui := get_tree().get_first_node_in_group("game_ui")
	var window := ui.get_node_or_null("SettingsWindow") if ui != null else null
	if window == null:
		print("[AudioTest] no Settings window")
		return false
	ui.call("open_settings", false, "sound")
	await get_tree().process_frame
	var labels: PackedStringArray = window.call("row_labels")
	var has_row := labels.has(str(_Strings.UI["row_now_playing"]))
	ui.call("close_settings")
	await get_tree().process_frame
	# Settings opened from the pause buttons hides them, and the music stays muffled.
	var tick := Constants.MUSIC_TICK_SECONDS + 0.1
	var shut_at_start := not bool(ui.call("pause_open"))
	ui.call("open_settings", true, "sound")
	await get_tree().create_timer(tick).timeout
	var paused := bool(ui.call("pause_open"))
	var muffled := bool(music.call("is_muffling"))
	ui.call("_dismiss_settings")
	await get_tree().create_timer(tick).timeout
	var cleared := not bool(ui.call("pause_open")) and not bool(music.call("is_muffling"))
	print("[AudioTest] Settings from pause: pause_open %s -> %s, muffled %s, cleared after %s" % [not shut_at_start, paused, muffled, cleared])
	var pause_muffle := shut_at_start and paused and muffled and cleared
	var track := str(music.call("current_track"))
	var title := str(music.call("now_playing_title"))
	var title_ok := title == _Strings.track_title(_Tracks.title_key(track)) and (track == "" or title != "")
	# A windowed run really plays it (a headless one is dry and makes no players).
	var audible := true
	if not bool(music.call("is_dry")) and track != "":
		audible = false
		for deck: Node in music.get_children():
			if deck is AudioStreamPlayer and deck.name.begins_with("Deck") and (deck as AudioStreamPlayer).playing:
				audible = true
	print("[AudioTest] Now playing row %s: %s (%s), playing %s" % [has_row, title, track, audible])
	return has_row and title_ok and audible and pause_muffle


## A buy the host confirms rings the register; a refused one doesn't.
func _register() -> bool:
	var shops := get_tree().get_first_node_in_group("shops")
	if shops == null:
		print("[AudioTest] no Shops")
		return false
	await _stand_at("homie_depot")
	Campaign._add_credits(Net.local_peer_id(), 10000)
	var before := _CueHooks.cue_log.count("register")
	var refused := str(shops.call("request_buy", "homie_depot", "hot_dog", 1))
	await get_tree().process_frame
	var quiet := _CueHooks.cue_log.count("register") == before
	var code := str(shops.call("request_buy", "homie_depot", "lawn_bags", 1))
	var waited := 0.0
	while _CueHooks.cue_log.count("register") == before and waited < 1.0:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	var rang := _CueHooks.cue_log.count("register") == before + 1
	print("[AudioTest] a refused buy (%s) is quiet %s; a confirmed buy (%s) rings the register %s" % [refused, quiet, code, rang])
	return code == "ok" and refused != "ok" and quiet and rang


func _hot(music: Node) -> bool:
	var heat := get_tree().get_first_node_in_group("heat")
	if heat == null:
		return false
	heat.call("add", Constants.MUSIC_HOT_HEAT + 5.0, "audio test")
	return await _wait_mood(music, [&"hot"], Constants.MUSIC_MOOD_HOLD_SECONDS + MOOD_SLACK_SECONDS)


## The raid's warning cuts in at once, the chase follows, and when the NICE BOYS
## give up the yard's music comes back.
func _raid(music: Node) -> bool:
	var director := get_tree().get_first_node_in_group("run_director")
	if director == null:
		return false
	director.call("force_event")
	var warned := await _wait_mood(music, [&"warning"], Constants.MUSIC_FADE_URGENT_SECONDS + 0.2)
	var chased := await _wait_mood(music, [&"chase"], Constants.RUN_WARNING_SECONDS + 1.0)
	# Before the crew can catch anyone (a capture would send us to the border).
	director.call("_give_up")
	var back := await _wait_mood(music, [&"hot", &"work_morning"], Constants.MUSIC_MOOD_HOLD_SECONDS + MOOD_SLACK_SECONDS)
	print("[AudioTest] raid: warning %s, chase %s, back to the yard %s" % [warned, chased, back])
	return warned and chased and back


## Bedtime with a rank-up: Clock Out, then Promoted!; silence under the card;
## Rise and Rake when it closes, with one buzz for the texts that came overnight.
func _day_end(music: Node) -> bool:
	var clock := get_tree().get_first_node_in_group("day_clock")
	var town := get_tree().get_first_node_in_group("town")
	var summary := get_tree().get_first_node_in_group("day_summary") as CanvasItem
	if clock == null or summary == null:
		print("[AudioTest] no clock or summary card")
		return false
	for peer_id: int in Net.peer_ids():
		Net.move_player_to_zone(peer_id, Net.Zone.STORE)
	var waited := 0.0
	while Net.players_in_zone(Net.Zone.STORE).size() < Net.peer_ids().size() and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var texts: Array = []
	var count_text := func(_entry: Dictionary) -> void: texts.append(1)
	if town != null:
		town.connect("texted", count_text)
	var needed := _Ranks.xp_to_reach(Campaign.crew_tier() + 1) - Campaign.crew_xp() - Campaign.pending_xp()
	Campaign.add_xp(maxi(1, needed), "test")
	var stingers_before := _Director.stinger_log.size()
	var buzzes_before := _CueHooks.cue_log.count("phone_buzz")
	clock.call("force_sleep")
	await get_tree().create_timer(0.5).timeout
	var fired := _Director.stinger_log.slice(stingers_before)
	var day_end: bool = fired.size() >= 2 and fired[0] == "st_day_end" and fired[1] == "st_rank_up"
	# Windowed, Clock Out is really playing over the ducked music.
	if not bool(music.call("is_dry")):
		var player := music.get_node_or_null("Stinger") as AudioStreamPlayer
		var playing := player != null and player.playing
		print("[AudioTest] the stinger is playing %s" % playing)
		day_end = day_end and playing
	var card := summary.visible
	var silent := await _wait_mood(music, [&"silence"], Constants.MUSIC_MOOD_HOLD_SECONDS + MOOD_SLACK_SECONDS)
	# Nothing buzzes while the card is up; the night's texts wait for it.
	var held := _CueHooks.cue_log.count("phone_buzz") == buzzes_before
	var mornings := _Director.stinger_log.count("st_morning")
	summary.call("close_window")
	await get_tree().create_timer(0.2).timeout
	if town != null:
		town.disconnect("texted", count_text)
	var morning := _Director.stinger_log.count("st_morning") == mornings + 1
	var buzzes := _CueHooks.cue_log.count("phone_buzz") - buzzes_before
	var buzz_ok := buzzes == (1 if texts.size() > 0 else 0)
	print("[AudioTest] bedtime: stingers %s, card up %s, silence %s; %d texts overnight, held %s, then %d buzz; morning stinger %s" % [fired, card, silent, texts.size(), held, buzzes, morning])
	return day_end and card and silent and held and morning and buzz_ok


## An escape sequence (Border Return today; audio chunk 4b): the border cuts to
## the escape music at once (urgent), the start fires the starting pistol, a
## throw-back's boing rides on you through the flight, and finishing plays "Made It Back". The
## crossing's own RPC handlers run here as plain calls, so nothing goes over the
## network, and _rpc_end puts the crossing back as it was.
func _escape(music: Node) -> bool:
	var crossing := get_tree().get_first_node_in_group("border_return")
	var me := _me()
	if crossing == null or me == null:
		print("[AudioTest] no Border Return or no player")
		return false
	var me_id := Net.local_peer_id()
	Net.move_player_to_zone(me_id, Net.Zone.BORDER)
	# The BORDER zone is Satellite Annex B's lobby muzak now (R2 chunk 5); the
	# escape cue is a push, as the Annex's stamp chase pushes it.
	await _wait_mood(music, [&"annex_hold"], Constants.MUSIC_TICK_SECONDS + Constants.MUSIC_MOOD_HOLD_SECONDS + MOOD_SLACK_SECONDS)
	music.call("push_mood", &"audio_test_escape", &"escape", _Tracks.priority("escape"))
	var cut := await _wait_mood(music, [&"escape"], Constants.MUSIC_TICK_SECONDS + Constants.MUSIC_FADE_URGENT_SECONDS + 0.2)
	var track := str(music.call("current_track"))
	var plays := track == _Tracks.tracks_for("escape")[0]
	await get_tree().physics_frame
	var go_before := _SfxScript.log.count("crossing_go")
	var bonk_before := _SfxScript.log.count("crossing_bonk")
	var made_before := _Director.stinger_log.count("st_made_it")
	_SfxScript.placed.clear()
	var roster: Array[int] = [me_id]
	var finished: Array[int] = []
	crossing.set("_roster", roster)
	crossing.set("_finished", finished)
	crossing.call("_rpc_go", Net.server_time())
	var go := _SfxScript.log.count("crossing_go") == go_before + 1
	var where := me.global_position
	crossing.call("_rpc_throwback", where)
	# The bonk rides on the flying body (play_on), so its landing pomf lands under you.
	var entry := _placed("crossing_bonk")
	var on_me: bool = not entry.is_empty() and entry["kind"] == "on" and entry["node"] == str(me.get_path())
	var bonk := _SfxScript.log.count("crossing_bonk") == bonk_before + 1 and on_me
	# Let the throw-back land before leaving, or it drags the body back to the border.
	var flying := 0.0
	while bool(me.call("is_throwing_back")) and flying < Constants.BORDER_THROWBACK_SECONDS + 1.0:
		await get_tree().physics_frame
		flying += get_physics_process_delta_time()
	crossing.call("_rpc_clear", me_id)
	var made_it: bool = _Director.stinger_log.count("st_made_it") == made_before + 1 and _Director.stinger_log.back() == "st_made_it"
	crossing.call("_rpc_end")
	music.call("pop_mood", &"audio_test_escape")
	Net.move_player_to_zone(me_id, Net.Zone.STORE)
	var after := await _wait_mood(music, [&"store", &"night", &"silence"], Constants.MUSIC_MOOD_HOLD_SECONDS + MOOD_SLACK_SECONDS)
	print("[AudioTest] escape: the border cuts to escape %s playing %s (%s), pistol %s, bonk riding on you %s, Made It Back %s, back to %s %s" % [cut, track, plays, go, bonk, made_it, music.call("current_mood"), after])
	return cut and plays and go and bonk and made_it and after


## The host stands at a shop's counter, on the customer's side (as --shop-test does).
func _stand_at(shop: String) -> void:
	var counter: Vector3 = (Constants.SHOP_SITES[shop] as Dictionary)["counter"]
	var world := get_tree().get_first_node_in_group("world")
	var zone := world.get_node_or_null("StoreZone") as Node3D
	var me := _me()
	if me == null or zone == null:
		return
	me.global_position = zone.to_global(counter + Vector3(0.0, 0.1, 1.8))
	if me is CharacterBody3D:
		(me as CharacterBody3D).velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame


## The latest positional play of id, or {} when it never played positionally.
func _placed(id: String) -> Dictionary:
	for index: int in range(_SfxScript.placed.size() - 1, -1, -1):
		var entry: Dictionary = _SfxScript.placed[index]
		if entry["id"] == id:
			return entry
	return {}


## Whether id's latest play was a play_at at where (not 2D, not elsewhere).
func _placed_at(id: String, where: Vector3) -> bool:
	var entry := _placed(id)
	return not entry.is_empty() and entry["kind"] == "at" and (entry["at"] as Vector3).distance_to(where) < 0.05


func _bogus_id() -> String:
	return "not_a_" + "real_sound"


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null

# ---- R2:5 Satellite Annex B's music (audio/music_tracks.gd annex_hold; the
# music director's R2 hooks, gap-specs nice_boys C15).

## A stand-in for R2 chunk 6's Annex node (group "annex"): only urgent().
class UrgentStub extends Node:
	var now_urgent: bool = false

	func _ready() -> void:
		add_to_group("annex")

	func urgent() -> bool:
		return now_urgent


## The Annex plays its lobby muzak; when it turns urgent the music switches to
## the escape cue on a bar line (the two share a sync name, tempo and bars); the
## hooks answer: duck, the chase's hide section, the van cab's muffle, slowdown.
func _annex_music(music: Node) -> bool:
	var me_id := Net.local_peer_id()
	var stub: UrgentStub = null
	if get_tree().get_first_node_in_group("annex") == null:
		stub = UrgentStub.new()
		stub.name = "AudioTestAnnex"
		add_child(stub)
	var same: bool = _Tracks.sync_of("annex_hold", "escape_run") != "" and _Tracks.track("annex_hold")["bars"] == _Tracks.track("escape_run")["bars"] and _Tracks.track("annex_hold")["intro_bars"] == _Tracks.track("escape_run")["intro_bars"] and is_equal_approx(float(_Tracks.track("annex_hold")["bpm"]), float(_Tracks.track("escape_run")["bpm"]))
	Net.move_player_to_zone(me_id, Net.Zone.BORDER)
	var lobby := await _wait_mood(music, [&"annex_hold"], Constants.MUSIC_TICK_SECONDS + Constants.MUSIC_MOOD_HOLD_SECONDS + MOOD_SLACK_SECONDS)
	var muzak := str(music.call("current_track")) == "annex_hold"
	var synced := true
	var urgent := true
	if stub != null:
		var syncs := _Director.hook_log.count("sync annex_hold>escape_run")
		stub.now_urgent = true
		urgent = await _wait_mood(music, [&"escape"], Constants.MUSIC_TICK_SECONDS + Constants.MUSIC_FADE_URGENT_SECONDS + 0.3)
		synced = _Director.hook_log.count("sync annex_hold>escape_run") == syncs + 1
	# The hooks.
	var hooks_before := _Director.hook_log.size()
	music.call("duck", -12.0, 0.4)
	music.call("request_section", &"hide", true)
	var section_on := bool(music.call("section_requested", &"hide"))
	var hide_span := _Tracks.section_seconds("nice_boys_chase", "hide")
	var bar := _Tracks.bar_seconds("nice_boys_chase")
	var span_ok := hide_span.size() == 2 and is_equal_approx(float(hide_span[0]), 28.0 * bar) and is_equal_approx(float(hide_span[1]), 36.0 * bar)
	music.call("request_section", &"hide", false)
	music.call("set_ambience", &"van_cab", true)
	var cab_muffled := bool(music.call("is_muffling"))
	music.call("set_ambience", &"van_cab", false)
	var cab_clear := not bool(music.call("ambience_on", &"van_cab"))
	music.call("slowdown", 1.0)
	var logged := _Director.hook_log.size() == hooks_before + 6
	var math := _bar_math()
	if stub != null:
		stub.queue_free()
	Net.move_player_to_zone(me_id, Net.Zone.STORE)
	var after := await _wait_mood(music, [&"store", &"night", &"silence"], Constants.MUSIC_MOOD_HOLD_SECONDS + MOOD_SLACK_SECONDS)
	print("[AudioTest] annex music: same tune %s, the Annex plays the muzak %s (%s), urgent cuts to escape %s on the bar %s; hooks: section %s %s, cab muffle %s cleared %s, logged %s; bar and section math %s; back %s" % [same, lobby, muzak, urgent, synced, section_on, span_ok, cab_muffled, cab_clear, logged, math, after])
	return same and lobby and muzak and urgent and synced and section_on and span_ok and cab_muffled and cab_clear and logged and math and after


## The director's bar-line cut and section hold, by the arithmetic it uses
## (audio/music_tracks.gd bar_switch, section_seek), at a few playback
## positions: mid-bar, just past a line, the last bar (the loop's wrap), and
## the hide section's way in, its loop back and inside it. A dry run never seeks.
func _bar_math() -> bool:
	var problems := PackedStringArray()
	var bar := _Tracks.bar_seconds("escape_run")
	var lead := _Tracks.lead_seconds("escape_run")
	var bars := int(_Tracks.track("escape_run")["bars"])
	var intro := int(_Tracks.track("escape_run")["intro_bars"])
	var cases := [
		# [position into the file, wait expected, seek expected]
		[lead + 10.5 * bar, 0.5 * bar, lead + 11.0 * bar],
		[lead + 10.0 * bar + 0.01, bar - 0.01, lead + 11.0 * bar],
		[lead + (float(bars) - 0.5) * bar, 0.5 * bar, lead + float(intro) * bar],
	]
	for entry: Array in cases:
		var cut := _Tracks.bar_switch("escape_run", float(entry[0]))
		if cut.is_empty() or absf(float(cut["wait"]) - float(entry[1])) > 0.002 or absf(float(cut["seek"]) - float(entry[2])) > 0.002:
			problems.append("bar_switch at %.3f gave %s, wanted wait %.3f seek %.3f" % [float(entry[0]), str(cut), float(entry[1]), float(entry[2])])
	# Every cut lands on a bar line of the new file and after the old one's.
	for step: int in 40:
		var position := lead + float(step) * bar * 0.37
		var cut := _Tracks.bar_switch("escape_run", position)
		if cut.is_empty():
			continue
		var on_line := fmod(float(cut["seek"]) - lead + 0.0001, bar) < 0.001
		if not on_line or float(cut["wait"]) <= 0.0:
			problems.append("bar_switch at %.3f is off the bar line: %s" % [position, str(cut)])
			break
	var span := _Tracks.section_seconds("nice_boys_chase", "hide")
	if span.size() == 2:
		var chase_bar := _Tracks.bar_seconds("nice_boys_chase")
		var chase_lead := _Tracks.lead_seconds("nice_boys_chase")
		var start := float(span[0]) + chase_lead
		var end := float(span[1]) + chase_lead
		var holds := [
			# [position, seek expected (-1 plays on)]
			[chase_lead + 20.0 * chase_bar + 0.01, start + 0.01],
			[chase_lead + 20.5 * chase_bar, -1.0],
			[end + 0.01, start + 0.01],
			[start + 2.0 * chase_bar, -1.0],
		]
		for entry: Array in holds:
			var seek := _Tracks.section_seek("nice_boys_chase", "hide", float(entry[0]))
			if absf(seek - float(entry[1])) > 0.002:
				problems.append("section_seek at %.3f gave %.3f, wanted %.3f" % [float(entry[0]), seek, float(entry[1])])
	else:
		problems.append("the chase has no hide section")
	for problem: String in problems:
		print("[AudioTest] annex music FAIL  %s" % problem)
	return problems.is_empty()
