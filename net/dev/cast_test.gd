extends Node

## Authority: host. --cast-test checks the cast (docs/GAME.md, "2026-11-01, the
## cast"; docs/DECISIONS.md, 2026-11-01). Each step prints a [CastTest] line.
##
## Phase A, the string table audit (host, instant), walks every constant in
## ui/strings.gd:
##   1. no empty or blank text
##   2. nothing unfinished: no [SOME NAME] slots, todo, tbd, placeholder, stand-in
##   3. every pool has enough lines, no repeats, and the %s/%d slots FORMAT_ARGS says
##   4. a pool for every personality x mood, bill, text kind, keeper trigger, bark
##      kind, run cue, rank, day bucket, neighborhood, season, unlock, task and tool
##   5. the humor guardrail (GUARDRAIL_PATTERNS) and "NICE BOYS" in capitals
##   6. player-facing sentences written inline in game code, outside ui/strings.gd
##      (report only for now; cast:3 moves them and makes this step fail)
##   7. Strings.homeowner_pool() resolves mood, bill and personality pools
##   8. Strings.summary_quip() picks the right bucket, the same line every time
## Phase B (the NICE BOYS' look, the van livery, the beacon) and Phase C (the
## crew on a client: outfits, name tags, barks) come with cast:4 to cast:6, which
## flip the PHASE_* switches below and fill in their steps.

const _Strings = preload("res://ui/strings.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")
const _Ranks = preload("res://core/ranks.gd")

## Steps 9-12: the outfit and its triangles (cast:4), the van and beacon (cast:5).
const PHASE_B_LOOK: bool = false
## Steps 13-16: crew outfits and name tags on a networked crew (cast:4).
const PHASE_C_CREW: bool = false
## Step 17: barks reach the client (cast:6).
const PHASE_C_BARKS: bool = false

## Words and names that never appear in player-facing text (docs/GAME.md, "Rules
## for agents working on content"; CLAUDE.md). One pattern per line, so a writer
## can see why a line failed. Never weaken one to make a line pass without Taylan.
## net/dev/guardrail.gd's PATTERNS, once it exists, are checked as well.
const GUARDRAIL_PATTERNS: Array[String] = [
	"\\bICE\\b", # the real agency; case-sensitive, so NICE never reads as ...ICE
	"(?i)immigra",
	"(?i)illegal",
	"(?i)alien",
	"(?i)deport",
	"(?i)\\bvisa\\b",
	"(?i)green card",
	"(?i)citizen",
	"(?i)papers,? please",
	"(?i)your papers",
	"(?i)go back to",
	"(?i)where are you from",
	"(?i)speak english",
	"(?i)accent",
	"(?i)ethnic",
	"(?i)border patrol",
	"(?i)homeland",
	"(?i)customs",
	"(?i)\\bpolice\\b",
	"(?i)sheriff",
	"(?i)\\bcops?\\b",
	"(?i)\\b(DHS|CBP|USCIS|FBI|DEA|ATF|IRS|INS)\\b",
	"(?i)ice cream", # the van is never an ice cream truck
	"Nice Boys?", # canon casing is "NICE BOYS"; lowercase "nice boys" is the pun, and fine
]
const GUARDRAIL_SHARED_PATH := "res://net/dev/guardrail.gd"

## Unfinished text. A [SOME NAME] slot needs a space or underscore inside, so key
## labels like "[E]" are not caught.
const PLACEHOLDER_PATTERNS: Array[String] = [
	"\\[[A-Z]+[ _][A-Z _]*\\]",
	"(?i)\\b(todo|tbd|fixme|lorem|placeholder|stand-?ins?)\\b",
]
## A %s, %d or %.Nf slot ("%%" is removed first).
const SLOT_PATTERN := "%-?\\d*(?:\\.\\d+)?[sdf]"
## A pool with no FORMAT_ARGS entry: no slots, at least three lines.
const DEFAULT_FORMAT: Array = [0, 3]

## Text kinds the host composes phone texts from (net/town/town.gd, net/crew/hires.gd).
const TEXT_KINDS: Array[String] = [
	"request", "clerk_intro", "clerk_lead", "referral_named", "referral_anon", "referral_body",
	"poached", "won_back_named", "won_back_signs", "won_back_tail",
	"rival_arrival", "rival_taunt", "rival_sign", "rival_sore",
	"hire_hired", "hire_quit", "hire_fired",
]
const BILL_POOLS: Array[String] = ["bill_hose", "bill_gnome", "bill_medical", "bill_water", "paid"]
const CUE_KINDS: Array[String] = ["radio", "arrived", "clear"]
## Until npcs/store_clerk.gd and npcs/crew_member.gd define TRIGGERS and BARK_KINDS
## (cast:2, cast:6), these are the lists every keeper and the crew must cover.
const DEFAULT_KEEPER_TRIGGERS: Array[String] = ["greet", "morning", "night", "open", "buy", "after_raid", "closed"]
const DEFAULT_BARK_KINDS: Array[String] = ["arrive", "spot", "chase", "lost", "search", "pile", "caught", "bonked"]

## The inline-text sweep: game code that puts a sentence of its own on screen.
const SWEEP_DIRS: Array[String] = [
	"res://net", "res://npcs", "res://ui", "res://levels", "res://props", "res://player", "res://core",
]
const SWEEP_SKIP: Array[String] = ["res://ui/strings.gd", "res://net/dev/"]
const SWEEP_SITES: Array[String] = [".text =", "text_sign(", "_status = ", "_show_ended(", "_text(", "_set_phase("]
const SWEEP_LITERAL := "\"[A-Za-z][^\"%\\n]*\\s[A-Za-z][^\"\\n]*\""
## Canon brand names that may stay where they are painted.
const SWEEP_ALLOW: Array[String] = ["HOMIE DEPOT", "Chefty"]

static var result: Dictionary = {}

var _started: bool = false
var _problems: Array[String] = []
var _guardrail: Array[RegEx] = []
var _placeholders: Array[RegEx] = []
var _slot: RegEx


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or get_tree().get_first_node_in_group("world") == null:
		return
	_started = true
	_run()


func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	_compile()
	var counts := _audit_table()
	_coverage()
	_api()
	var inline := _sweep_inline()
	if PHASE_B_LOOK:
		await _phase_b()
	else:
		print("[CastTest] phase B (look, van, beacon) is off until cast:4 and cast:5")
	if PHASE_C_CREW:
		await _phase_c()
	else:
		print("[CastTest] phase C (the crew on a client) is off until cast:4 and cast:6")
	var ok := _problems.is_empty()
	result = {
		"ok": ok, "done": true, "problems": _problems.duplicate(),
		"strings": counts.x, "pools": counts.y, "inline_text": inline,
	}
	print("[CastTest] all ok: %s (%d problems, %d strings, %d pools)" % [ok, _problems.size(), counts.x, counts.y])


## Steps 9-12, filled in by cast:4 (outfit parts and triangle budget) and cast:5
## (van livery, beacon).
func _phase_b() -> void:
	await get_tree().process_frame


## Steps 13-17, filled in by cast:4 (outfits and name tags on a client) and cast:6
## (barks; PHASE_C_BARKS).
func _phase_c() -> void:
	await get_tree().process_frame


func _fail(rule: String, detail: String) -> void:
	_problems.append("%s: %s" % [rule, detail])
	print("[CastTest] FAIL %s: %s" % [rule, detail])


func _compile() -> void:
	var patterns: Array[String] = []
	patterns.append_array(GUARDRAIL_PATTERNS)
	if ResourceLoader.exists(GUARDRAIL_SHARED_PATH):
		var shared: Variant = (load(GUARDRAIL_SHARED_PATH) as Script).get("PATTERNS")
		if shared is Array:
			for pattern: Variant in shared:
				if pattern is String and not patterns.has(pattern):
					patterns.append(pattern)
	for pattern: String in patterns:
		_guardrail.append(_regex(pattern))
	for pattern: String in PLACEHOLDER_PATTERNS:
		_placeholders.append(_regex(pattern))
	_slot = _regex(SLOT_PATTERN)
	# The patterns themselves: each bad sample must trip one, no good sample may.
	for bad: String in ["Here comes ICE.", "the Nice Boys", "Papers, please!", "an ice cream van", "the police"]:
		if not _trips(_guardrail, bad):
			_fail("0 guardrail misses", bad)
	for bad: String in ["Hi [CLERK NAME]", "a stand-in line", "TODO: joke"]:
		if not _trips(_placeholders, bad):
			_fail("0 unfinished misses", bad)
	for good: String in ["the NICE BOYS", "Nice work, nice boys.", "COURTESY NOTICE", "Another happy customer!", "[E]  %s"]:
		if _trips(_guardrail, good) or _trips(_placeholders, good):
			_fail("0 pattern too eager", good)
	if _slots("%s at %d, %.1f%% and 25% more") != 3:
		_fail("0 slot count", "%s at %d, %.1f%% and 25% more")
	print("[CastTest] %d guardrail patterns, checked against samples" % _guardrail.size())


func _trips(patterns: Array[RegEx], text: String) -> bool:
	for regex: RegEx in patterns:
		if regex.search(text) != null:
			return true
	return false


func _regex(pattern: String) -> RegEx:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		_fail("bad pattern", pattern)
	return regex


# ---------------------------------------------------------------- phase A, steps 1-5


## Steps 1-3 and 5 over every string and pool. Returns (strings, pools) checked.
func _audit_table() -> Vector2i:
	var leaves: Array = []
	var pools: Array = []
	var constants := (_Strings as Script).get_script_constant_map()
	for key: String in constants:
		_walk(constants[key], key, leaves, pools)
	for leaf: Array in leaves:
		var path := str(leaf[0])
		var text := str(leaf[1])
		if text.strip_edges() == "":
			_fail("1 empty", path)
			continue
		for regex: RegEx in _placeholders:
			if regex.search(text) != null:
				_fail("2 unfinished", "%s: %s" % [path, text])
		for regex: RegEx in _guardrail:
			if regex.search(text) != null:
				_fail("5 guardrail /%s/" % regex.get_pattern(), "%s: %s" % [path, text])
		var exact: Variant = _Strings.FORMAT_ARGS.get(path)
		if exact is Array and _slots(text) != int(exact[0]):
			_fail("3 slots", "%s wants %d, has %d: %s" % [path, int(exact[0]), _slots(text), text])
	for pool: Array in pools:
		var path := str(pool[0])
		var lines: Array = pool[1]
		var rule := _format_rule(path)
		if lines.size() < int(rule[1]):
			_fail("3 too few lines", "%s has %d, wants %d" % [path, lines.size(), int(rule[1])])
		var seen: Dictionary = {}
		for line: Variant in lines:
			var text := str(line)
			if seen.has(text):
				_fail("3 repeated line", "%s: %s" % [path, text])
			seen[text] = true
			if _slots(text) != int(rule[0]):
				_fail("3 slots", "%s wants %d, has %d: %s" % [path, int(rule[0]), _slots(text), text])
	print("[CastTest] steps 1-3, 5: %d strings and %d pools read" % [leaves.size(), pools.size()])
	return Vector2i(leaves.size(), pools.size())


## Collects every string (path, text) and every pool, an array of strings (path, lines).
func _walk(value: Variant, path: String, leaves: Array, pools: Array) -> void:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			leaves.append([path, str(value)])
		TYPE_DICTIONARY:
			var table: Dictionary = value
			for key: Variant in table:
				_walk(table[key], "%s/%s" % [path, str(key)], leaves, pools)
		TYPE_ARRAY:
			var list: Array = value
			var all_text := true
			for item: Variant in list:
				all_text = all_text and (item is String or item is StringName)
			if all_text:
				pools.append([path, list])
			for index: int in list.size():
				_walk(list[index], "%s/%d" % [path, index], leaves, pools)


## The FORMAT_ARGS entry for a pool: its own, else the nearest one above it.
func _format_rule(path: String) -> Array:
	var probe := path
	while probe != "":
		var rule: Variant = _Strings.FORMAT_ARGS.get(probe)
		if rule is Array:
			return rule
		var cut := probe.rfind("/")
		probe = probe.substr(0, cut) if cut >= 0 else ""
	return DEFAULT_FORMAT


func _slots(text: String) -> int:
	return _slot.search_all(text.replace("%%", "")).size()


# ---------------------------------------------------------------- phase A, step 4


func _coverage() -> void:
	var before := _problems.size()
	var personalities: Array = _Hoods.PERSONALITIES.keys()
	var moods: Array = (_constant("res://npcs/homeowner.gd", "STAGING", {}) as Dictionary).keys()
	_need(not moods.is_empty(), "npcs/homeowner.gd STAGING has moods")
	for personality: Variant in personalities:
		var by_mood: Dictionary = _Strings.PERSONALITY_LINES.get(personality, {})
		for mood: Variant in moods:
			_need(by_mood.has(mood), "PERSONALITY_LINES/%s/%s" % [personality, mood])
		_need(_Strings.PERSONALITY_BLURBS.has(personality), "PERSONALITY_BLURBS/%s" % personality)
		_need((_Strings.TEXT_LINES["request"] as Dictionary).has(personality), "TEXT_LINES/request/%s" % personality)
	for mood: Variant in moods:
		_need(_Strings.HOMEOWNER_LINES.has(mood), "HOMEOWNER_LINES/%s" % mood)
	for pool: String in BILL_POOLS:
		_need(_Strings.HOMEOWNER_LINES.has(pool), "HOMEOWNER_LINES/%s" % pool)
	_need((_Strings.TEXT_LINES["request"] as Dictionary).has("generic"), "TEXT_LINES/request/generic")
	for kind: String in TEXT_KINDS:
		_need(_Strings.TEXT_LINES.has(kind), "TEXT_LINES/%s" % kind)
	var triggers: Array = _constant("res://npcs/store_clerk.gd", "TRIGGERS", DEFAULT_KEEPER_TRIGGERS)
	_need(_Strings.KEEPER_LINES.has("marty"), "KEEPER_LINES/marty")
	for keeper: Variant in _Strings.KEEPER_LINES:
		for trigger: Variant in triggers:
			_need((_Strings.KEEPER_LINES[keeper] as Dictionary).has(trigger), "KEEPER_LINES/%s/%s" % [keeper, trigger])
	for kind: Variant in _constant("res://npcs/crew_member.gd", "BARK_KINDS", DEFAULT_BARK_KINDS):
		_need(_Strings.CREW_BARKS.has(kind), "CREW_BARKS/%s" % kind)
	for kind: String in CUE_KINDS:
		_need(_Strings.CUE_LINES.has(kind), "CUE_LINES/%s" % kind)
	for rank: String in _Ranks.NAMES:
		_need(_Strings.RANK_BLURBS.has(rank), "RANK_BLURBS/%s" % rank)
	_need(_Strings.RANK_BLURBS.has(_Ranks.ENDLESS_NAME), "RANK_BLURBS/%s" % _Ranks.ENDLESS_NAME)
	for bucket: String in _Strings.QUIP_BUCKETS:
		_need(_Strings.SUMMARY_QUIPS.has(bucket), "SUMMARY_QUIPS/%s" % bucket)
	for hood: Dictionary in _Hoods.HOODS:
		_need(_Strings.HOOD_BLURBS.has(str(hood["id"])), "HOOD_BLURBS/%s" % hood["id"])
	_need(_Strings.SEASON_NAMES.size() == 4, "SEASON_NAMES has 4 seasons")
	_need(_Strings.SEASON_ARRIVALS.size() == 4, "SEASON_ARRIVALS has 4 seasons")
	# The NICE BOYS' names: enough of them, and none a homeowner's.
	var unique: Dictionary = {}
	for crew_name: String in _Strings.CREW_NAMES:
		unique[crew_name.to_lower()] = true
	_need(unique.size() >= 8, "CREW_NAMES has 8 different names")
	for first: String in _Hoods.FIRST_NAMES:
		_need(not unique.has(first.to_lower()), "CREW_NAMES leaves out the homeowner name %s" % first)
	# Every unlock reads as words.
	var unlocks: Array = _Ranks.UNLOCKS.duplicate()
	var extra: Variant = (_Ranks as Script).get_script_constant_map().get("EXTRA_UNLOCKS")
	if extra is Dictionary:
		unlocks.append_array((extra as Dictionary).keys())
	elif extra is Array:
		unlocks.append_array(extra)
	# "kind:id" left in the text means the name fell through; "hiring: crew hands" is prose.
	var id_like := _regex("[a-z_]+:[a-z_]+")
	for unlock: Variant in unlocks:
		var id := str(unlock)
		var named := _Strings.unlock_name(id)
		_need(named != id and id_like.search(named) == null, "unlock_name(%s) reads as words, not \"%s\"" % [id, named])
	for task: Variant in Constants.TASK_TOOLS:
		_need(_Strings.UI.has("task_%s" % task), "UI/task_%s" % task)
	for tool: Variant in Constants.TOOL_PRICES:
		_need(_Strings.UI.has("tool_%s" % tool), "UI/tool_%s" % tool)
		_need(_Strings.UI.has("tool_blurb_%s" % tool), "UI/tool_blurb_%s" % tool)
	print("[CastTest] step 4, coverage: %s" % (_problems.size() == before))


func _need(condition: bool, what: String) -> void:
	if not condition:
		_fail("4 missing", what)


## A constant from another script, or the fallback when it has none (yet).
func _constant(path: String, key: String, fallback: Variant) -> Variant:
	if not ResourceLoader.exists(path):
		return fallback
	var value: Variant = (load(path) as Script).get_script_constant_map().get(key)
	return value if value != null else fallback


# ---------------------------------------------------------------- phase A, steps 7-8


func _api() -> void:
	var before := _problems.size()
	# Step 7: pool ids.
	_check(_Strings.homeowner_pool("grumpy/slow") == _Strings.PERSONALITY_LINES["grumpy"]["slow"], "7 homeowner_pool('grumpy/slow') is the grumpy slow pool")
	_check(_Strings.homeowner_pool("bill_hose") == _Strings.HOMEOWNER_LINES["bill_hose"], "7 homeowner_pool('bill_hose') is the hose bill pool")
	_check(_Strings.homeowner_pool("thrilled") == _Strings.HOMEOWNER_LINES["thrilled"], "7 homeowner_pool('thrilled') is the thrilled pool")
	_check(_Strings.homeowner_pool("nobody/nothing") == [""] and _Strings.homeowner_pool("bill_moon") == [""], "7 an unknown pool is ['']")
	# Step 8: the day summary's quip.
	var cases: Array = [
		[{"day": 3, "jobs": 0}, "zero"],
		[{"day": 3, "jobs": 2, "stars": 10.0, "raids": 1}, "raided"],
		[{"day": 3, "jobs": 2, "stars": 9.0}, "great"],
		[{"day": 3, "jobs": 1, "stars": 5.0}, "solid"],
		[{"day": 3, "jobs": 3, "stars": 6.0}, "rough"],
	]
	for row: Array in cases:
		var summary: Dictionary = row[0]
		var bucket := str(row[1])
		var line := _Strings.summary_quip(summary)
		_check(_Strings.quip_bucket(summary) == bucket, "8 %s reads as a %s day" % [JSON.stringify(summary), bucket])
		_check(line == _Strings.summary_quip(summary) and (_Strings.SUMMARY_QUIPS[bucket] as Array).has(line), "8 the %s quip is the same line twice: %s" % [bucket, line])
	# The rest of the API later chunks lean on.
	var tag := _Strings.crew_tag(1, 5)
	_check(tag == _Strings.crew_tag(1, 5) and tag.begins_with("HEAD NICE BOY "), "crew_tag(1, day) is the head NICE BOY: %s" % tag)
	_check(_Strings.crew_tag(2, 5).begins_with("NICE BOY "), "crew_tag(2, day) is a NICE BOY: %s" % _Strings.crew_tag(2, 5))
	_check(_Strings.rank_blurb(0) == _Strings.RANK_BLURBS["Rake Rookie"] and _Strings.rank_blurb(_Ranks.TIERS_PER_RANK) == _Strings.RANK_BLURBS["Leaf Grunt"], "rank_blurb at a rank's tier I is the rank's")
	var endless := _Ranks.NAMES.size() * _Ranks.TIERS_PER_RANK
	_check(_Strings.rank_blurb(endless) == _Strings.RANK_BLURBS[_Ranks.ENDLESS_NAME], "rank_blurb at the first Lawnfather tier is The Lawnfather's")
	_check(_Strings.rank_blurb(1) == _Strings.TIER_BLURBS[0] and _Strings.rank_blurb(4) == _Strings.TIER_BLURBS[3] and _Strings.TIER_BLURBS.has(_Strings.rank_blurb(endless + 3)), "rank_blurb at tiers II to V, and Lawnfather stars, is a tier blurb")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var request: Dictionary = _Strings.TEXT_LINES["request"]
	_check((request["grumpy"] as Array).has(_Strings.client_line("request", "grumpy", rng)), "client_line('request', 'grumpy') is a grumpy request")
	_check((request["generic"] as Array).has(_Strings.client_line("request", "", rng)), "client_line('request', '') is a generic request")
	_check((_Strings.TEXT_LINES["hire_fired"] as Array).has(_Strings.client_line("hire_fired", "grumpy", rng)), "client_line of a kind with one pool uses it")
	_check(_Strings.pick_seeded(["a", "b", "c"], -7) == "c" and _Strings.pick_seeded([], 3) == "", "pick_seeded wraps any seed into the pool")
	print("[CastTest] steps 7-8, the strings API: %s" % (_problems.size() == before))


func _check(condition: bool, what: String) -> void:
	if not condition:
		_fail("api", what)


# ---------------------------------------------------------------- phase A, step 6


## Report only (until cast:3): every sentence game code puts on screen itself.
func _sweep_inline() -> Array[String]:
	var found: Array[String] = []
	var literal := _regex(SWEEP_LITERAL)
	var files: Array[String] = []
	for dir: String in SWEEP_DIRS:
		_list_scripts(dir, files)
	for path: String in files:
		var skip := false
		for prefix: String in SWEEP_SKIP:
			skip = skip or path.begins_with(prefix)
		if skip:
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for number: int in lines.size():
			var line := lines[number]
			if line.strip_edges().begins_with("#") or not _is_text_site(line):
				continue
			for hit: RegExMatch in literal.search_all(line):
				var text := hit.get_string().trim_prefix("\"").trim_suffix("\"")
				if SWEEP_ALLOW.has(text):
					continue
				found.append("%s:%d %s" % [path.trim_prefix("res://"), number + 1, hit.get_string()])
	for entry: String in found:
		print("[CastTest] inline text (report only): %s" % entry)
	print("[CastTest] step 6: %d inline sentences outside ui/strings.gd (report only until cast:3)" % found.size())
	return found


func _is_text_site(line: String) -> bool:
	for site: String in SWEEP_SITES:
		if line.contains(site):
			return true
	return false


func _list_scripts(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		_list_scripts(dir_path.path_join(sub), out)
