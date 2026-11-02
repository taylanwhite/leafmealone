extends SceneTree

## Runs the humor guardrail (net/dev/guardrail.gd) headless:
##   godot --headless --path . --script res://tools/guardrail_check.gd
## 1. Self-check: every SHOULD_HIT sample is caught and no SHOULD_PASS sample is.
## 2. Sweep: every constant in the player-facing text tables below goes through
##    Guardrail.check. Prints each hit as file:CONST.key: rule: 'match'.
## Exits 1 when the self-check fails or the sweep finds anything. ci_local runs it
## as the "guardrail" step and netcode.yml as "Guardrail".

const _Guardrail: Script = preload("res://net/dev/guardrail.gd")

## Scripts whose constants hold player-facing text. Proper nouns live with their
## data (cast spec), so the name tables are swept too. Add a file here when it
## starts holding text a player reads.
const SOURCES: Array = [
	"res://ui/strings.gd",
	"res://core/ranks.gd",
	"res://core/seasons.gd",
	"res://net/town/neighborhoods.gd",
]
## Scripts that can't load outside the game (they use the Net autoload); their
## string literals are swept as text instead.
const SOURCE_TEXT: Array = [
	"res://net/crew/hires.gd",
]


func _init() -> void:
	var failed := false
	var problems: Array = _Guardrail.call("self_check")
	for p: String in problems:
		print("[Guardrail] self-check FAIL  %s" % p)
	failed = not problems.is_empty()
	print("[Guardrail] self-check %s (%d patterns)" % ["ok" if problems.is_empty() else "FAIL", (_Guardrail.get("PATTERNS") as Array).size()])
	var total := 0
	var swept := 0
	# A listed file that is gone (renamed or moved) is a hit: fix the list, don't skip it.
	for path: String in SOURCES:
		var hits: Array = ["%s: missing (update SOURCES in tools/guardrail_check.gd)" % path]
		if ResourceLoader.exists(path):
			hits = _Guardrail.call("sweep_script", path)
			swept += 1
		for hit: String in hits:
			print("[Guardrail] HIT  %s" % hit)
		total += hits.size()
	for path: String in SOURCE_TEXT:
		var hits: Array = ["%s: missing (update SOURCE_TEXT in tools/guardrail_check.gd)" % path]
		if FileAccess.file_exists(path):
			hits = _Guardrail.call("sweep_source", path)
			swept += 1
		for hit: String in hits:
			print("[Guardrail] HIT  %s" % hit)
		total += hits.size()
	print("[Guardrail] sweep %s: %d hit(s) in %d of %d file(s)" % ["ok" if total == 0 else "FAIL", total, swept, SOURCES.size() + SOURCE_TEXT.size()])
	failed = failed or total > 0
	quit(1 if failed else 0)
