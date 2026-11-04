extends Node

## Authority: host. --balance-test is the engine half of the balance lab's parity
## check (docs/BALANCE.md). tools/balance_sim.py reads every tuning number out of
## the scripts with its own parser and mirrors core/economy.gd by hand; this test
## gives it the engine's side to compare against:
##   result.constants  every constant of Constants, Balance, Ranks, Seasons, the
##                     neighborhoods and Catalog, as the engine sees them: a JSON
##                     string of {script: {name: value}} (see _run for why a string)
##   result.cases      a fixed grid of Economy, Ranks, Seasons and Catalog calls,
##                     [{fn, args, out}]; the sim calls its mirror with the same args
##   result.invariants in-engine rules about the tables, each {name, ok, detail}
## ok is the invariants (and the save's XP curve) only; the comparison itself is
## balance_sim.py --check --engine-dump <this host.json>, a separate CI step.
## No client, no yard: it runs as soon as the host is up.

const _Economy = preload("res://core/economy.gd")
const _Ranks = preload("res://core/ranks.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")
## For its static crew_xp_from_save (the autoload instance would warn).
const _CampaignScript = preload("res://net/campaign.gd")

## The scripts dumped, by the names balance_sim.py's tables use.
const SCRIPTS: Dictionary = {
	"Constants": "res://core/constants.gd",
	"Balance": "res://core/balance.gd",
	"Ranks": "res://core/ranks.gd",
	"Seasons": "res://core/seasons.gd",
	"Hoods": "res://net/town/neighborhoods.gd",
	"Catalog": "res://core/catalog.gd",
}
## Tiers the grid walks: the whole ladder (40) and a few Lawnfather stars.
const GRID_TIERS: int = 46
## SPINE: every tool is on sale by the end of Hedge Hog (rank 5 of 8).
const LAST_TOOL_TIER: int = 25
## Curves the migration is tried between: today's, the one before saves knew
## theirs, a steeper one, and garbage (which must leave the XP alone).
const OTHER_CURVE_ID: String = "160/28/1500"
const BAD_CURVE_ID: String = "a lot/of/leaves"

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or Net.current_state() == Net.State.OFFLINE:
		return
	_started = true
	_run()


func _run() -> void:
	result = {"ok": false, "done": false, "constants": {}, "cases": [], "invariants": []}
	var constants := {}
	for script_name: String in SCRIPTS:
		var script := load(str(SCRIPTS[script_name])) as Script
		if script == null:
			_fail("could not load %s" % SCRIPTS[script_name])
			return
		constants[script_name] = _dump_map(script.get_script_constant_map())
	# As a JSON string inside the report: tuning tables have keys PowerShell 5.1's
	# ConvertFrom-Json rejects ("" in JUNK_PER_HOOD, and it ignores case), and
	# tools/ci_local.ps1 reads every host.json. balance_sim.py decodes it.
	result["constants"] = JSON.stringify(constants, "", false, true)
	var cases: Array = []
	_add_cases(cases)
	result["cases"] = cases
	var invariants: Array = []
	_check_invariants(invariants)
	result["invariants"] = invariants
	var failed: Array[String] = []
	for row: Variant in invariants:
		var check := row as Dictionary
		if not bool(check["ok"]):
			failed.append(str(check["name"]))
			print("[BalanceTest] FAIL %s: %s" % [check["name"], check["detail"]])
	result["ok"] = failed.is_empty()
	if not failed.is_empty():
		result["error"] = "invariants failed: %s" % ", ".join(failed)
	print("[BalanceTest] %d constants dumped from %d scripts, %d cases, %d invariants, %d failed: %s" % [
		_count_constants(constants), constants.size(), cases.size(), invariants.size(), failed.size(),
		"PASS" if result["ok"] else "FAIL"])
	result["done"] = true


func _fail(why: String) -> void:
	print("[BalanceTest] FAIL %s" % why)
	result["ok"] = false
	result["error"] = why
	result["done"] = true


# ---------------------------------------------------------------- the constant dump

func _dump_map(map: Dictionary) -> Dictionary:
	var out := {}
	for name: Variant in map:
		var value: Variant = map[name]
		# Preloaded scripts, inner classes and the like aren't tuning; the sim's
		# parser skips them too.
		if not _dumpable(value):
			continue
		out[str(name)] = _safe(value)
	return out


func _dumpable(value: Variant) -> bool:
	match typeof(value):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
	return true


## A value JSON can carry and balance_sim.py compares: vectors and colors become
## lists, names become strings, dictionary keys become strings.
func _safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			var number := float(value)
			if is_nan(number) or is_inf(number):
				return str(number)
			return number
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_VECTOR4, TYPE_VECTOR4I:
			return [value.x, value.y, value.z, value.w]
		TYPE_RECT2, TYPE_RECT2I:
			return [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_DICTIONARY:
			var out := {}
			for key: Variant in value:
				if _dumpable(value[key]):
					out[str(key)] = _safe(value[key])
			return out
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
				TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
				TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, \
				TYPE_PACKED_VECTOR4_ARRAY:
			var out: Array = []
			for item: Variant in value:
				out.append(_safe(item) if _dumpable(item) else str(item))
			return out
	return str(value)


func _count_constants(constants: Dictionary) -> int:
	var total := 0
	for script_name: Variant in constants:
		total += (constants[script_name] as Dictionary).size()
	return total


# ---------------------------------------------------------------- the case grid

func _case(cases: Array, fn: String, args: Array, out: Variant) -> void:
	cases.append({"fn": fn, "args": _safe(args), "out": _safe(out)})


func _add_cases(cases: Array) -> void:
	# Ranks: the ladder, the edges of every tier, the Lawnfather's pay.
	for tier: int in GRID_TIERS:
		_case(cases, "Ranks.xp_for_tier", [tier], _Ranks.xp_for_tier(tier))
		var reach := _Ranks.xp_to_reach(tier)
		_case(cases, "Ranks.xp_to_reach", [tier], reach)
		for xp: int in [reach - 1, reach, reach + 1]:
			if xp < 0:
				continue
			_case(cases, "Ranks.tier_for_xp", [xp], _Ranks.tier_for_xp(xp))
			_case(cases, "Ranks.xp_into_tier", [xp], _Ranks.xp_into_tier(xp))
	for tier: int in range(0, 61, 3):
		_case(cases, "Ranks.pay_bonus", [tier], _Ranks.pay_bonus(tier))
	var unlocks: Array[String] = ["shop:not_a_thing"]
	unlocks.append_array(_Ranks.UNLOCKS)
	for tier: Variant in _Ranks.EXTRA_UNLOCKS:
		for unlock: Variant in (_Ranks.EXTRA_UNLOCKS[tier] as Array):
			unlocks.append(str(unlock))
	for unlock: String in unlocks:
		_case(cases, "Ranks.tier_of", [unlock], _Ranks.tier_of(unlock))
	# Seasons by day, across more than one year.
	for day: int in range(1, 61):
		_case(cases, "Seasons.of_day", [day], Seasons.of_day(day))
	for day: int in [1, 28, 29, 56, 57, 120, 400]:
		_case(cases, "Seasons.year_of", [day], Seasons.year_of(day))
	# Catalog: every price, and one nobody sells.
	var ids: Array[String] = ["not_for_sale"]
	for id: Variant in Catalog.ITEMS:
		ids.append(str(id))
	for id: String in ids:
		_case(cases, "Catalog.price", [id], Catalog.price(id))
	# Economy: XP for a job.
	for cleaned: float in [0.0, 0.25, 0.5, 0.8, 0.95, 1.0]:
		for tasks: Array in [[], [1.0], [0.5, 1.0], [1.0, 1.0, 0.25]]:
			for stars: int in [0, 1, 3, 5]:
				for crew: int in [1, 4]:
					_case(cases, "Economy.job_xp", [cleaned, tasks, stars, crew], _Economy.job_xp(cleaned, tasks, stars, crew))
	# XP carried across curves: every tier edge, both ways, and a bad id.
	var curves: Array[String] = [_Ranks.CURVE_ID, _Ranks.LEGACY_CURVE_ID, OTHER_CURVE_ID, BAD_CURVE_ID]
	for tier: int in range(0, GRID_TIERS, 5):
		var xp := _Ranks.xp_to_reach(tier) + 37
		for from_id: String in curves:
			for to_id: String in curves:
				_case(cases, "Economy.migrate_xp", [xp, from_id, to_id], _Economy.migrate_xp(xp, from_id, to_id))
	# The town.
	for days: int in 6:
		for never_done: bool in [false, true]:
			_case(cases, "Economy.regrow", [days, never_done], _Economy.regrow(days, never_done))
	for rel: float in [0.0, 50.0, 97.0, 100.0]:
		for stars: int in 6:
			_case(cases, "Economy.relationship_after", [rel, stars], _Economy.relationship_after(rel, stars))
	# The homeowner.
	for step: int in 11:
		var standards := float(step) / 10.0
		_case(cases, "Economy.mood_thresholds", [standards], _Economy.mood_thresholds(standards))
		_case(cases, "Economy.clean_enough_at", [standards], _Economy.clean_enough_at(standards))
		_case(cases, "Economy.messy_below_at", [standards], _Economy.messy_below_at(standards))
	var moods: Array[String] = ["nothing", "unheard_of"]
	for mood: Variant in Constants.HOMEOWNER_PAY_BY_MOOD:
		moods.append(str(mood))
	for mood: String in moods:
		for budget: float in [0.8, 1.0, 1.25, 1.6]:
			for money: Array in [[0, 0, 0, 0], [180, 45, 0, 0], [333, 120, 6, 0], [90, 0, 25, 120]]:
				var args := [int(money[0]), int(money[1]), mood, budget, int(money[2]), int(money[3])]
				_case(cases, "Economy.job_pay", args, _Economy.job_pay(args[0], args[1], mood, budget, args[4], args[5]))
	for perks: int in 5:
		_case(cases, "Economy.bag_bonus", [perks], _Economy.bag_bonus(perks))
	# The crew's split (p1-depart).
	for scores: Array in [[], [0.0], [1.0], [0.7, 0.0, 0.0, 0.0], [0.4, 0.3, 0.3], [0.0, 0.0, 0.0, 0.0], [0.55, 0.15, 0.3, 0.0]]:
		var shares := _Economy.split_shares(scores)
		_case(cases, "Economy.split_shares", [scores], shares)
		for pool: float in [0.0, 3.0, 40.0, 117.6]:
			_case(cases, "Economy.split_dollars", [pool, shares], _Economy.split_dollars(pool, shares))
	# Crew size (0 and one past the most for the clamps).
	for players: int in range(0, Constants.MAX_PLAYERS + 2):
		_case(cases, "Economy.crew_work_scale", [players], _Economy.crew_work_scale(players))
		_case(cases, "Economy.crew_patience_scale", [players], _Economy.crew_patience_scale(players))
		_case(cases, "Economy.xp_crew_scale", [players], _Economy.xp_crew_scale(players))
	# The NICE BOYS' roll, by heat and the job's neighborhood (balance:E; -1 and 9
	# for the clamps).
	for heat: float in [0.0, 25.0, 50.0, 75.0, 100.0]:
		for hood: int in [-1, 0, 1, 2, 3, 4, 5, 9]:
			_case(cases, "Economy.run_roll_chance", [heat, hood], _Economy.run_roll_chance(heat, hood))
	# balance:E0 (R2 chunk 1): the per-lot chance and its per-roll share.
	for heat: float in [0.0, 50.0, 94.0, 100.0]:
		for hood: int in [0, 3, 5]:
			_case(cases, "Economy.run_lot_chance", [heat, hood], _Economy.run_lot_chance(heat, hood))
			_case(cases, "Economy.run_roll_chance", [heat, hood], _Economy.run_roll_chance(heat, hood))


# ---------------------------------------------------------------- invariants

func _check(invariants: Array, name: String, ok: bool, detail: Variant = "") -> void:
	invariants.append({"name": name, "ok": ok, "detail": _safe(detail)})


func _check_invariants(invariants: Array) -> void:
	var constants: Dictionary = (load(str(SCRIPTS["Constants"])) as Script).get_script_constant_map()
	# Every shop unlock (UNLOCKS and EXTRA_UNLOCKS) is something with a price.
	var unpriced: Array[String] = []
	var shop_unlocks: Array[String] = []
	for tier: int in range(1, _Ranks._last_unlock_tier() + 1):
		for unlock: String in _Ranks.unlocks_at(tier):
			if unlock.begins_with("shop:"):
				shop_unlocks.append(unlock)
				if Campaign.price_of(StringName(unlock.trim_prefix("shop:"))) < 0:
					unpriced.append(unlock)
	_check(invariants, "every shop unlock has a price", unpriced.is_empty() and not shop_unlocks.is_empty(),
			{"shop_unlocks": shop_unlocks.size(), "unpriced": unpriced})
	# Every tool is on sale by Turf Boss I.
	var late: Array[String] = []
	for tool: Variant in Constants.TOOL_PRICES:
		var tier := _Ranks.tier_of("shop:%s" % tool)
		if tier > LAST_TOOL_TIER:
			late.append("%s (tier %d)" % [tool, tier])
	_check(invariants, "every tool unlocks by tier %d" % LAST_TOOL_TIER, late.is_empty(), late)
	# balance:E0: a lot's worth of rolls adds up to the per-lot chance, and one roll is smaller.
	var e0_rolls := Constants.RAID_LOT_MINUTES * 60.0 / Constants.HEAT_ROLL_SECONDS
	var e0_off: Array[String] = []
	for heat: float in [0.0, 50.0, 94.0, 100.0]:
		for hood: int in [0, 3, 5]:
			var p_lot := _Economy.run_lot_chance(heat, hood)
			var p_roll := _Economy.run_roll_chance(heat, hood)
			if absf((1.0 - pow(1.0 - p_roll, e0_rolls)) - p_lot) > 0.0001 or (p_lot > 0.0 and p_roll >= p_lot):
				e0_off.append("heat %d hood %d: lot %.4f roll %.4f" % [heat, hood, p_lot, p_roll])
	_check(invariants, "a lot's raid rolls compound to the per-lot chance (balance:E0)", e0_off.is_empty(), e0_off)
	# Every neighborhood a rank opens exists.
	var hood_ids: Array[String] = []
	for hood: Dictionary in _Hoods.HOODS:
		hood_ids.append(str(hood.get("id", "")))
	var missing_hoods: Array[String] = []
	for unlock: String in _Ranks.unlocks_through(_Ranks._last_unlock_tier()):
		if unlock.begins_with("hood:") and not hood_ids.has(unlock.trim_prefix("hood:")):
			missing_hoods.append(unlock)
	_check(invariants, "every hood unlock is a neighborhood", missing_hoods.is_empty(), missing_hoods)
	# The crew-size tables (balance:E): one entry per crew size, each above 0.
	for table_name: String in ["CREW_WORK_SCALE", "CREW_PATIENCE_SCALE", "XP_CREW_SCALE"]:
		if not constants.has(table_name):
			_check(invariants, "%s has an entry per crew size" % table_name, false, "missing from core/constants.gd")
			continue
		var table: Array = constants[table_name]
		var good := table.size() == Constants.MAX_PLAYERS and table.all(func(entry: Variant) -> bool: return float(entry) > 0.0)
		_check(invariants, "%s has an entry per crew size" % table_name, good, table)
	_check_crew_drifts(invariants)
	# The pacing targets: one per rank and The Lawnfather, never going down, ending inside the arc.
	var pace: Array = Constants.RANK_PACE_HOURS
	var rising := true
	for index: int in range(1, pace.size()):
		if float(pace[index]) < float(pace[index - 1]):
			rising = false
	var last := float(pace[pace.size() - 1]) if not pace.is_empty() else -1.0
	_check(invariants, "RANK_PACE_HOURS: a target per rank, rising, ending inside ARC_HOURS",
			pace.size() == _Ranks.NAMES.size() + 1 and rising and last >= Constants.ARC_HOURS.x and last <= Constants.ARC_HOURS.y,
			{"entries": pace.size(), "wanted": _Ranks.NAMES.size() + 1, "rising": rising, "last": last, "arc": Constants.ARC_HOURS})
	# xp_to_reach and tier_for_xp agree on every tier edge.
	var off: Array[String] = []
	for tier: int in GRID_TIERS:
		var reach := _Ranks.xp_to_reach(tier)
		if _Ranks.tier_for_xp(reach) != tier or (reach > 0 and _Ranks.tier_for_xp(reach - 1) != tier - 1):
			off.append(str(tier))
	_check(invariants, "tier_for_xp(xp_to_reach(k)) == k", off.is_empty(), off)
	_check_migration(invariants)


## A small crew's yard is smaller in area (levels/lots/crew_drifts.gd, balance:E):
## on a yard-shaped 80 x 80 field (trees, a house with no leaves) the drifts leave
## CREW_WORK_SCALE of the leafy cells leafy, within a percent, for every crew size
## and a few seeds, and a whole crew's yard is untouched.
func _check_crew_drifts(invariants: Array) -> void:
	var drifts: Script = load("res://levels/lots/crew_drifts.gd")
	var points := PackedVector2Array()
	var amounts := PackedFloat32Array()
	var trees: Array[Vector2] = [Vector2(-11.0, 6.0), Vector2(9.0, 10.0), Vector2(12.0, -14.0)]
	for z: int in 80:
		for x: int in 80:
			var at := Vector2(-20.0 + (float(x) + 0.5) * 0.5, -20.0 + (float(z) + 0.5) * 0.5)
			var amount := 0.5
			for tree: Vector2 in trees:
				amount += 1.2 * exp(-at.distance_squared_to(tree) / 18.0)
			if Rect2(-6.0, -12.0, 12.0, 9.0).has_point(at):
				amount = 0.0
			points.append(at)
			amounts.append(amount)
	var off: Array[String] = []
	for seed_value: int in [7, 1000, 4242]:
		var noise: FastNoiseLite = drifts.call("noise_for", hash([seed_value, "crew_drifts"]))
		var counts: Array[int] = []
		for players: int in range(1, Constants.MAX_PLAYERS + 1):
			var keep := _Economy.crew_work_scale(players)
			var cut := float(drifts.call("cut_for", noise, points, amounts, keep))
			var leafy := 0
			for index: int in points.size():
				var value := clampi(int(round(60.0 * amounts[index] * float(drifts.call("weight", noise, cut, points[index])))), 0, 255)
				if value > 8:
					leafy += 1
			counts.append(leafy)
		var whole := counts[counts.size() - 1]
		for index: int in counts.size():
			var share := float(counts[index]) / float(maxi(1, whole))
			if absf(share - _Economy.crew_work_scale(index + 1)) > 0.01:
				off.append("seed %d crew %d: %.3f" % [seed_value, index + 1, share])
	_check(invariants, "a small crew's drifts cover CREW_WORK_SCALE of the leafy lawn", off.is_empty(), off)


## A crew never loses its tier when the XP curve changes: a pre-curve save loads
## onto today's curve at the same tier (Campaign.crew_xp_from_save, what _load
## runs), a trip to another curve and back keeps it too, a save on today's curve
## is untouched, a bad id leaves the XP alone, and the save writes today's curve.
func _check_migration(invariants: Array) -> void:
	var legacy := _Economy._parse_curve(_Ranks.LEGACY_CURVE_ID)
	var lost: Array[String] = []
	for tier: int in GRID_TIERS:
		var reach := 0
		for below: int in tier:
			reach += _Economy._curve_tier_xp(legacy, below)
		var step := _Economy._curve_tier_xp(legacy, tier)
		for into: int in [0, int(step * 0.5), step - 1]:
			var xp := reach + into
			var loaded := _CampaignScript.crew_xp_from_save({"xp": xp, "pending": 30})
			if _Ranks.tier_for_xp(loaded) != tier:
				lost.append("legacy %d (tier %d) -> %d (tier %d)" % [xp, tier, loaded, _Ranks.tier_for_xp(loaded)])
			var there := _Economy.migrate_xp(loaded, _Ranks.CURVE_ID, OTHER_CURVE_ID)
			var back := _CampaignScript.crew_xp_from_save({"xp": there, "curve": OTHER_CURVE_ID})
			if _Ranks.tier_for_xp(back) != tier:
				lost.append("round trip %d -> %d -> %d (tier %d)" % [loaded, there, back, _Ranks.tier_for_xp(back)])
	_check(invariants, "a pre-curve save keeps its tier on today's curve (migrate_xp)", lost.is_empty(), lost.slice(0, 8))
	var today := _Ranks.xp_to_reach(7) + 11
	_check(invariants, "a save on today's curve loads unchanged",
			_CampaignScript.crew_xp_from_save({"xp": today, "curve": _Ranks.CURVE_ID}) == today, today)
	_check(invariants, "a curve id that doesn't parse leaves the XP alone",
			_Economy.migrate_xp(today, BAD_CURVE_ID, _Ranks.CURVE_ID) == today and _Economy.migrate_xp(today, _Ranks.CURVE_ID, BAD_CURVE_ID) == today, today)
	var saved: Dictionary = Campaign.call("_save_data").get("crew", {})
	_check(invariants, "the save writes crew.curve", str(saved.get("curve", "")) == _Ranks.CURVE_ID, saved)
