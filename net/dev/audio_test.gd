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
##   ride_truck   Chefty's departure sound rides along with the truck to the lot
##   positional   a bag, a throw and a heavy bonk on the lot play positionally
##   no_unknown   nothing asked Sfx for an unregistered id during the whole run
## Each step prints an [AudioTest] line. Later chunks add the music checks.

const _Bank = preload("res://audio/sound_bank.gd")
const _Buses = preload("res://audio/buses.gd")
const _SfxScript = preload("res://audio/sfx.gd")

## A loop shorter than this would stutter.
const LOOP_MIN_SECONDS: float = 0.5
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
	"(?<!\\w)(?:say|say_to_all|_say|_speak|_play_sfx|_play|_one_shot|_loop_player|stinger)\\(",
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
	result = {"done": false, "checks": {}, "missing": [], "unknown_ids": [], "bad_lengths": []}
	await get_tree().create_timer(1.0).timeout
	_check("bank_files", _bank_files())
	_check("source_scan", _source_scan())
	_check("buses", _buses())
	var sfx := get_tree().get_first_node_in_group("sfx")
	var at_home := sfx != null and str(sfx.get_path()).ends_with("UIRoot/Audio/Sfx")
	print("[AudioTest] Sfx is at %s" % (str(sfx.get_path()) if sfx != null else "nowhere"))
	_check("sfx_node", at_home)
	if sfx == null:
		_finish("no Sfx node in group sfx")
		return
	_check("sfx_api", _sfx_api(sfx))
	_check("ride_truck", await _ride())
	_check("positional", await _positional())
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
						if not _Bank.has(id):
							bad.append("%s: %s" % [script_path.get_file(), id])
			for found: RegExMatch in path_rx.search_all(line):
				var named := found.get_string(1)
				var there := DirAccess.dir_exists_absolute(named) if named.ends_with("/") else (ResourceLoader.exists(named) or FileAccess.file_exists(named))
				if not there:
					bad.append("%s: %s" % [script_path.get_file(), found.get_string(1)])
	(result["unknown_ids"] as Array).append_array(bad)
	print("[AudioTest] scanned %d scripts, %d sound ids named; unregistered %s" % [scripts.size(), ids_seen, bad])
	# The scanner itself: it reads ids out of a ternary and a lookup, and leaves
	# comparisons, nested calls and an AnimationPlayer alone.
	var samples := {
		"\tsfx.call(\"play_at\", \"thud\" if tier == \"heavy\" else \"bonk\", at)": ["thud", "bonk"],
		"\tsay_to_all(\"vo_yelp\" if is_in_group(\"vans\") else \"vo_ah\")": ["vo_yelp", "vo_ah"],
		"\t_speak(str(staging[\"sound\"]))": [],
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
## keys ("a": ...), not compared against (== "a"), not indexes (["a"]) and not
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
		if before.ends_with("==") or before.ends_with("!=") or before.ends_with("["):
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
	var positional: bool = _SfxScript.log.back() == "grind"
	sfx.call("play", _bogus_id())
	var caught := _SfxScript.unknown.has(_bogus_id())
	var buses_right := _Bank.bus("babble") == _Buses.CHATTER and _Bank.bus("wind_loop") == _Buses.AMBIENCE and _Bank.bus("tick") == _Buses.UI and _Bank.bus("bonk") == _Buses.SFX and _Bank.bus("music_loop") == _Buses.MUSIC
	var voices_right := _Bank.is_voice("vo_oof") and _Bank.is_voice("babble") and _Bank.is_voice("dog") and not _Bank.is_voice("bonk")
	print("[AudioTest] play logs once inside its gap %s, play_at logs %s, unknown ids caught %s, bank buses %s, voices %s" % [logged_once, positional, caught, buses_right, voices_right])
	return logged_once and positional and caught and buses_right and voices_right


func _ride() -> bool:
	var chefty := get_tree().get_first_node_in_group("chefty")
	if chefty == null:
		print("[AudioTest] no Chefty")
		return false
	var before := _SfxScript.log.count("truck")
	chefty.call("depart", Net.players_in_zone(Net.Zone.STORE), Net.Zone.LOT)
	await get_tree().create_timer(0.3).timeout
	var heard := _SfxScript.log.count("truck") > before
	var waited := 0.0
	while Net.player_zone(Net.local_peer_id()) != Net.Zone.LOT and waited < RIDE_TIMEOUT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var arrived := Net.player_zone(Net.local_peer_id()) == Net.Zone.LOT
	print("[AudioTest] Chefty's truck sound on departure %s, arrived on the lot %s after %.1f s" % [heard, arrived, waited])
	return heard and arrived


func _positional() -> bool:
	var world := get_tree().get_first_node_in_group("world")
	var me := _me()
	await get_tree().create_timer(0.5).timeout
	var at := me.global_position + (-me.global_transform.basis.z) * 1.5
	var props_before := get_tree().get_nodes_in_group("props").size()
	world.call("_spawn_bag", at, 5)
	var bag_heard: bool = _SfxScript.log.back() == "bag"
	await get_tree().create_timer(0.3).timeout
	var props := get_tree().get_nodes_in_group("props")
	if props.size() <= props_before:
		print("[AudioTest] the bag never showed up")
		return false
	var prop := props.back() as Node
	var before := [_SfxScript.log.count("whoosh"), _SfxScript.log.count("thud"), _SfxScript.log.count("dizzy")]
	prop.call("_rpc_throw_fx")
	prop.call("_rpc_bonk_fx", NodePath(), "heavy", Vector3.ZERO)
	var after := [_SfxScript.log.count("whoosh"), _SfxScript.log.count("thud"), _SfxScript.log.count("dizzy")]
	var fx_heard := int(after[0]) > int(before[0]) and int(after[1]) > int(before[1]) and int(after[2]) > int(before[2])
	print("[AudioTest] bag %s; whoosh, thud, dizzy before %s and after %s" % [bag_heard, before, after])
	return bag_heard and fx_heard


func _bogus_id() -> String:
	return "not_a_" + "real_sound"


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
