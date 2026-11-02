class_name Guardrail
extends RefCounted

## The humor guardrail as code: one list of patterns that player-facing text must
## never match (docs/GAME.md, "The humor guardrail"; critic C31). The joke is the
## impossible work, the precarious systems and the enforcement bureaucracy. It is
## never immigrants, ethnicity, nationality or accents, and the NICE BOYS are never
## a real agency or the police.
##
## Used by the string audits (cast_test, art_test) and by tools/guardrail_check.gd:
##   var hits: Array = Guardrail.check("some line")      # [] when clean
##   var hits: Array = Guardrail.sweep(SomeScript.SOME_TABLE, "SOME_TABLE")
##   var hits: Array = Guardrail.sweep_script("res://ui/strings.gd")
## Each hit is a printable String: "<rule>: '<matched text>'", prefixed with
## "<path>: " by the sweeps. Use preload("res://net/dev/guardrail.gd") or the
## class name; both work.
##
## Patterns are PCRE (Godot RegEx). Case-insensitive ones start with (?i); the rest
## are case-sensitive on purpose (ICE the acronym is banned, ice on a frozen lake
## is not). A false positive is fixed by rewording the line, not by loosening a
## pattern: the reword is almost always funnier. Add a pattern when a new risk
## shows up, and add a sample of it to SHOULD_HIT.

const PATTERNS: Array = [
	# ---- Real agencies. The NICE BOYS are a made-up HOA-meets-parking-enforcement crew.
	{"id": "agency", "re": "\\b(ICE|CBP|DHS|USCIS|HSI|ERO|FBI|DEA|ATF|IRS|INS|TSA)\\b",
		"why": "a real agency's acronym"},
	{"id": "agency", "re": "(?i)\\b(N[.\\s-]+)?I[.\\s-]+C[.\\s-]+E\\b",
		"why": "a spelled-out acronym that spells ICE (I.C.E., I-C-E, N.I.C.E., N I C E)"},
	{"id": "agency", "re": "(?i)\\bice\\s+(agents?|officers?|raids?|patrol|squads?|vans?|men|teams?|units?|enforcement|cream)\\b",
		"why": "an 'ICE' pun ('ice cream' is the obvious trap)"},
	{"id": "agency", "re": "(?i)\\b(immigra\\w*|emigra\\w*|homeland|border\\s+patrol|customs|border\\s+protection|la\\s+migra|migra|the\\s+feds|federal\\s+agents?)\\b",
		"why": "names a real enforcement body or its work"},
	{"id": "police", "re": "(?i)\\b(police\\w*|cops?|sheriffs?|state\\s+troopers?|swat|paddy\\s+wagons?)\\b",
		"why": "the NICE BOYS are not police"},
	# ---- Immigration status. Never the subject of a joke, never said about the crew.
	{"id": "status", "re": "(?i)\\b(illegal(s|ly)?|undocumented|aliens?|deport\\w*|visas?|green\\s+cards?|citizen(s|ship)?|asylum|refugees?|migrants?|anchor\\s+bab(y|ies)|chain\\s+migration)\\b",
		"why": "immigration status (say 'unpermitted', not 'illegal')"},
	{"id": "status", "re": "(?i)(papers,?\\s+please|your\\s+papers|show\\s+(me\\s+)?(your|the|some)\\s+papers|build\\s+(the|a|that)\\s+wall|(south\\s+of|across|over)\\s+the\\s+border)",
		"why": "a 'papers' or 'the border' bit"},
	# ---- Where someone is from, how they talk.
	{"id": "origin", "re": "(?i)(go\\s+back\\s+(to\\s+)?(where\\s+(you|they)|(your|their)\\s+(own\\s+)?country)|where\\s+are\\s+you\\s+(really\\s+)?from|speak\\s+english|english,?\\s+please|learn\\s+english|(broken|bad|funny|thick|heavy|fake|foreign)\\s+(english|accent))",
		"why": "origin or language mockery"},
	{"id": "origin", "re": "(?i)\\b(accents?|ethnic\\w*|racial\\w*|racis[mt]\\w*|nationality|foreign(ers?)?|third[-\\s]world|fresh\\s+off\\s+the\\s+boat)\\b",
		"why": "ethnicity, nationality or accent as a subject"},
	{"id": "origin", "re": "(?i)\\b(mexic\\w*|latin[oax]s?|latine|hispanics?|chican[oa]s?|guatemal\\w*|salvadoran\\w*|hondur\\w*|nicaragu\\w*|colombians?|venezuelans?|cubans?|puerto\\s+ric\\w*|dominicans?|peruvians?|ecuadorians?|haitians?)\\b",
		"why": "a nationality or ethnicity named in a joke game about a work crew"},
	# ---- Mock-Spanish, mock accents, stereotype props.
	{"id": "mockery", "re": "(?i)(\\bno\\s+habla\\w*|\\bno\\s+compren\\w*|\\bcompren\\w*|\\bno\\s+problemo|\\bel\\s+cheapo|\\bamigos?\\b|\\bhombres?\\b|\\bse(n|ñ)or(it)?as?\\b|\\bse(n|ñ)ors?\\b|\\bgringos?\\b|\\bcholos?\\b|\\bpinche\\b|\\b(a|á)ndale\\b|\\barriba\\b|\\bmucho\\b|\\bmuchachos?\\b)",
		"why": "mock-Spanish"},
	{"id": "mockery", "re": "(?i)\\b(eet|ees|thees|leetle|meester|beeg|velly|herro|ching\\s+chong)\\b",
		"why": "mock-accent spelling"},
	{"id": "mockery", "re": "(?i)\\b(sombreros?|ponchos?|siestas?|mariachis?|pi(n|ñ)atas?|maracas?|serapes?)\\b",
		"why": "a stereotype prop"},
	# ---- Slurs. Kept as stems; any hit is a hard no, whatever the context.
	{"id": "slur", "re": "(?i)\\b(wet\\s?backs?|beaners?|spics?|greasers?|chinks?|chinam[ae]n|gooks?|ragheads?|towelheads?|redskins?|oriental|gyp(s|ped|ping|sy|sies)?|jew(ed|ing)|indian\\s+givers?|welsh(ed|er|ers|ing)|n[i1]gg\\w*)\\b",
		"why": "an ethnic or national slur (say 'spotless', 'a gap', 'ripped off')"},
	# ---- Canon casing: the crew is always NICE BOYS in caps (lowercase 'nice boys' is the pun, allowed).
	{"id": "canon", "re": "\\bNice\\s+Boys?\\b", "why": "write NICE BOYS in caps"},
]

## Lines each pattern family must catch, and clean lines nothing may catch.
## self_check() runs both; tools/guardrail_check.gd prints the result.
const SHOULD_HIT: Array = [
	"ICE is on the way", "An I.C.E. van", "N.I.C.E. compliance", "N-I-C-E", "I-C-E", "N I C E",
	"N. I. C. E.", "Free ice cream truck",
	"Homeland Security notice", "Call the police!", "Two cops and a sheriff", "Border Patrol",
	"Customs paperwork", "the feds are here", "Illegally parked rake", "Show me your papers",
	"Papers, please", "Deportation notice", "green card", "Go back where you came from", "Thanks, amigo",
	"Where are you from?", "Speak English", "a funny accent", "Mexican food truck",
	"No habla", "no problemo", "Gracias, señor", "a sombrero on the gnome", "eet ees done",
	"wetback", "spic and span", "you got gypped", "Nice Boys incoming",
]
const SHOULD_PASS: Array = [
	"The NICE BOYS are here. Run. Hide. Break line of sight.", "nice boys finish last",
	"Watch the ice on the driveway", "The lake froze solid", "Border Return",
	"RADIO: the NICE BOYS are on the way to this address", "Homie Depot", "Chefty",
	"Unpermitted wheelbarrow parking, ma'am", "Paperwork Incoming", "Office of Curb Appeal",
	"Spotless. Spick-and-span would be a stretch.", "a custom paint job", "Notice of Niceness",
	"Pulled the TurfMasters sign", "Go back to the truck", "Raid warning", "The save migration ran", "Rake It Easy",
]

static var _compiled: Array = []


## Every guardrail hit in `text`, as "<rule>: '<match>'" Strings. Empty when clean.
static func check(text: String) -> Array:
	var hits: Array = []
	if text.strip_edges().is_empty():
		return hits
	for entry: Dictionary in _rules():
		var re: RegEx = entry["regex"]
		for m: RegExMatch in re.search_all(text):
			hits.append("%s: '%s'" % [entry["id"], m.get_string()])
	return hits


## True when `text` has no hits.
static func is_clean(text: String) -> bool:
	return check(text).is_empty()


## Walks a String, Array or Dictionary (values only; keys are ids) and returns every
## hit as "<path>: <rule>: '<match>'".
static func sweep(value: Variant, path: String = "") -> Array:
	var hits: Array = []
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			for hit: String in check(String(value)):
				hits.append("%s: %s" % [path, hit])
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var i := 0
			for item: Variant in value:
				hits.append_array(sweep(item, "%s[%d]" % [path, i]))
				i += 1
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			for key: Variant in dict:
				hits.append_array(sweep(dict[key], "%s.%s" % [path, str(key)]))
	return hits


## Sweeps every constant of a script (for example res://ui/strings.gd). Paths look
## like "strings.gd:UI.status_crew_here". A script that doesn't compile has no constants
## to read, so it counts as a hit of its own (never a silent pass) and its string
## literals are swept as text instead; move it to SOURCE_TEXT in
## tools/guardrail_check.gd if it can only compile inside the game.
static func sweep_script(script_path: String) -> Array:
	var script: Script = load(script_path)
	if script == null:
		return ["%s: could not load" % script_path]
	if not script.can_instantiate():
		var fallback: Array = ["%s: did not compile, so its constants could not be swept (literals swept as text)" % script_path]
		fallback.append_array(sweep_source(script_path))
		return fallback
	var hits: Array = []
	var constants: Dictionary = script.get_script_constant_map()
	for const_name: String in constants:
		hits.append_array(sweep(constants[const_name], "%s:%s" % [script_path.get_file(), const_name]))
	return hits


## Sweeps every double-quoted string literal in a source file, read as text, so it
## works on scripts that can't load outside the game (they use the Net autoload).
## Comment lines are skipped. Paths look like "hires.gd:14".
static func sweep_source(file_path: String) -> Array:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ["%s: could not open" % file_path]
	var literal := RegEx.new()
	literal.compile("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
	var hits: Array = []
	var line_number := 0
	while not file.eof_reached():
		var line := file.get_line()
		line_number += 1
		if line.strip_edges().begins_with("#"):
			continue
		for m: RegExMatch in literal.search_all(line):
			for hit: String in check(m.get_string(1)):
				hits.append("%s:%d: %s" % [file_path.get_file(), line_number, hit])
	return hits


## Runs SHOULD_HIT and SHOULD_PASS through check(). Returns the failures (empty = ok).
static func self_check() -> Array:
	var failures: Array = []
	if _rules().size() != PATTERNS.size():
		failures.append("a pattern failed to compile")
	for line: String in SHOULD_HIT:
		if check(line).is_empty():
			failures.append("missed: \"%s\"" % line)
	for line: String in SHOULD_PASS:
		var hits := check(line)
		if not hits.is_empty():
			failures.append("false hit: \"%s\" -> %s" % [line, ", ".join(hits)])
	return failures


static func _rules() -> Array:
	if _compiled.is_empty():
		for entry: Dictionary in PATTERNS:
			var re := RegEx.new()
			if re.compile(String(entry["re"])) != OK:
				push_error("Guardrail: pattern did not compile: %s" % entry["re"])
				continue
			_compiled.append({"id": entry["id"], "why": entry["why"], "regex": re})
	return _compiled
