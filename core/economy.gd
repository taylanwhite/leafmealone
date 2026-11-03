extends RefCounted

## The economy's formulas (docs/DECISIONS.md, "Economy formulas live in
## core/economy.gd"). Pure static math, the same on every peer: no nodes, no
## randomness, no state. Callers read the game (stars, crew size, perks) and pass
## it in; the numbers come from core/constants.gd, core/ranks.gd and core/balance.gd.
##
## A new economy formula goes in this file. tools/balance_sim.py mirrors every
## function here line for line (its Economy class, docs/BALANCE.md), so changing a
## formula here means changing its mirror in the same commit. The engine parity
## test (--balance-test, net/dev/balance_test.gd) runs a grid of calls here, and
## balance_sim.py --check --engine-dump fails when the two disagree (CI and the
## balance-sim step of tools/ci_local.ps1). A new function here gets cases in that
## grid and a mirror in the sim, or the check fails on an unmirrored case.
##
## No class_name, so it can't clash with anything: preload it.
##   const _Economy = preload("res://core/economy.gd")

const _Ranks = preload("res://core/ranks.gd")


# ---------------------------------------------------------------- XP

## XP for a finished job (Campaign._award_job_xp): flat per piece of work, never
## per dollar, so a windfall can't skip ranks. cleaned is the yard's cleaned
## fraction 0..1; task_done holds how much of each task asked for got done, 0..1;
## stars is the homeowner's review (0 when there was none); crew is the number of
## players on the job.
static func job_xp(cleaned: float, task_done: Array, stars: int, crew: int) -> int:
	var xp := float(Constants.XP_LEAVES_FULL) * clampf(cleaned / Constants.XP_LEAVES_CLEAN_AT, 0.0, 1.0)
	for done: Variant in task_done:
		xp += float(Constants.XP_PER_TASK) * clampf(float(done), 0.0, 1.0)
	xp += float(Constants.XP_PER_STAR) * float(stars)
	return int(round(xp * xp_crew_scale(crew)))


## Banked XP carried from one XP curve to another (a retune): the crew keeps its
## tier and how far into it they were. Curve ids are Ranks.CURVE_ID strings,
## "first/step/endless". An id that doesn't parse leaves the XP as it is.
static func migrate_xp(xp: int, from_id: String, to_id: String) -> int:
	if from_id == to_id:
		return xp
	var from := _parse_curve(from_id)
	var to := _parse_curve(to_id)
	if from.is_empty() or to.is_empty():
		return xp
	var tier := 0
	var left := xp
	while left >= _curve_tier_xp(from, tier):
		left -= _curve_tier_xp(from, tier)
		tier += 1
	var frac := float(left) / float(_curve_tier_xp(from, tier))
	var reach := 0
	for below: int in tier:
		reach += _curve_tier_xp(to, below)
	return reach + int(floor(frac * float(_curve_tier_xp(to, tier))))


## [first, step, endless] from "150/25/1200", or [] when it isn't one.
static func _parse_curve(curve_id: String) -> Array[int]:
	var parts := curve_id.split("/")
	var out: Array[int] = []
	if parts.size() != 3:
		return out
	for part: String in parts:
		if not part.is_valid_int() or int(part) <= 0:
			out.clear()
			return out
		out.append(int(part))
	return out


## Ranks.xp_for_tier under another curve.
static func _curve_tier_xp(curve: Array[int], tier: int) -> int:
	if tier >= _Ranks.NAMES.size() * _Ranks.TIERS_PER_RANK:
		return curve[2]
	return curve[0] + curve[1] * tier


# ---------------------------------------------------------------- the town

## How grown back a yard is (Town.mess): full the first time, then regrowing a
## share each day since the crew last worked it.
static func regrow(days_since: int, never_done: bool) -> float:
	if never_done:
		return Constants.TOWN_FIRST_MESS
	return clampf(float(days_since) * Constants.TOWN_REGROW_PER_DAY, Constants.TOWN_MIN_MESS, 1.0)


## A client's relationship after a reviewed job (Town.on_job_finished): three
## stars holds steady, each star above or below moves it, and any paid job adds a
## little on top. A job with no review (stars 0) leaves it alone.
static func relationship_after(rel: float, stars: int) -> float:
	if stars <= 0:
		return rel
	return clampf(rel + float(stars - 3) * Constants.TOWN_RELATIONSHIP_PER_STAR + Constants.TOWN_RELATIONSHIP_PER_JOB, 0.0, 100.0)


# ---------------------------------------------------------------- the homeowner

## The homeowner's verdict lines (homeowner._judge) for an owner this picky (0..1):
## x is how done the job must be to count as clean enough, y is the share below
## which it is a mess. Picky owners want it cleaner and call it a mess sooner.
## A Vector2 holds 32-bit floats, so the homeowner itself reads the two halves
## below, which keep full precision; this pair is for tools and tests.
static func mood_thresholds(standards: float) -> Vector2:
	return Vector2(clean_enough_at(standards), messy_below_at(standards))


## mood_thresholds().x at full precision.
static func clean_enough_at(standards: float) -> float:
	return clampf(Constants.HOMEOWNER_CLEAN_ENOUGH + (standards - Constants.HOMEOWNER_STANDARDS_PIVOT) * Constants.HOMEOWNER_STANDARDS_CLEAN_SLOPE,
			Constants.HOMEOWNER_CLEAN_ENOUGH_MIN, Constants.HOMEOWNER_CLEAN_ENOUGH_MAX)


## mood_thresholds().y at full precision.
static func messy_below_at(standards: float) -> float:
	return clampf(Constants.HOMEOWNER_MESSY_BELOW + (standards - Constants.HOMEOWNER_STANDARDS_PIVOT) * Constants.HOMEOWNER_STANDARDS_MESSY_SLOPE,
			Constants.HOMEOWNER_MESSY_BELOW_MIN, Constants.HOMEOWNER_MESSY_BELOW_MAX)


## What the homeowner hands over (homeowner._handle_talk): the bags in Chefty and
## the tasks' share of TASK_PAY, times their mood and budget, less their water and
## whatever the crew broke. Nothing for "nothing", and never below zero.
static func job_pay(bag_value: int, task_value: int, mood: String, budget: float, water_fee: int, bills: int) -> int:
	if mood == "nothing":
		return 0
	var by_mood := float(Constants.HOMEOWNER_PAY_BY_MOOD.get(mood, 1.0))
	return maxi(0, int(round(float(bag_value + task_value) * by_mood * budget)) - water_fee - bills)


## The multiplier on a bag's worth from the crew's bag perks (leaf_field.dollars_for).
static func bag_bonus(perk_count: int) -> float:
	# Added one perk at a time, the way the game always summed it, so the float is
	# bit for bit what it was.
	var bonus := 1.0
	for _perk: int in maxi(0, perk_count):
		bonus += Constants.BAG_BONUS_PER_PERK
	return bonus


# ---------------------------------------------------------------- the split

## Each crew member's share of a job's pool (Campaign._split_pool, p1-depart):
## CREW_SPLIT_EVEN_SHARE of it evenly, the rest by contribution. scores holds
## each member's contribution score (the Balance weights over their share of the
## crew's leaves, rescues and objectives); each contribution share is floored at
## MINIMUM_CONTRIBUTION_SHARE before it is normalized. With no scores at all the
## contribution part is even too. The shares sum to 1.
static func split_shares(scores: Array) -> Array[float]:
	var shares: Array[float] = []
	var count := scores.size()
	if count == 0:
		return shares
	var total := 0.0
	for score: Variant in scores:
		total += maxf(0.0, float(score))
	var raw: Array[float] = []
	var floored := 0.0
	for score: Variant in scores:
		var part := 1.0 / float(count) if total <= 0.0 else maxf(0.0, float(score)) / total
		part = maxf(part, Balance.MINIMUM_CONTRIBUTION_SHARE)
		raw.append(part)
		floored += part
	var even := clampf(Constants.CREW_SPLIT_EVEN_SHARE, 0.0, 1.0)
	for part: float in raw:
		shares.append(even / float(count) + (1.0 - even) * part / floored)
	return shares


## Whole dollars for each share of a pool, summing to the pool rounded: each
## gets the floor of their share, and the dollars left go to the biggest
## remainders (ties to the earlier member), so a $3 job split four ways reads
## $1, $1, $1, $0 instead of everyone's rounding making it $4.
static func split_dollars(pool: float, shares: Array) -> Array[int]:
	var out: Array[int] = []
	var whole := maxi(0, int(round(pool)))
	var given := 0
	var rests: Array = []
	for index: int in shares.size():
		var exact := float(whole) * float(shares[index])
		var dollars := int(floor(exact + 1e-9))
		out.append(dollars)
		given += dollars
		rests.append([exact - float(dollars), index])
	rests.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]) or (is_equal_approx(float(a[0]), float(b[0])) and int(a[1]) < int(b[1])))
	var left := whole - given
	for entry: Array in rests:
		if left <= 0:
			break
		out[int(entry[1])] += 1
		left -= 1
	return out


# ---------------------------------------------------------------- crew size

## How much of a yard's mess a crew this size gets (levels/world.gd, gap balance:E).
## 1.0 for every size until the retune lands CREW_WORK_SCALE.
static func crew_work_scale(players: int) -> float:
	return _scale_for(players)


## How much longer the homeowner waits for a crew this size (gap balance:E).
## 1.0 for every size until the retune lands CREW_PATIENCE_SCALE.
static func crew_patience_scale(players: int) -> float:
	return _scale_for(players)


## The XP multiplier for a crew this size, so small crews keep pace (gap balance:E).
## 1.0 for every size until the retune lands XP_CREW_SCALE.
static func xp_crew_scale(players: int) -> float:
	return _scale_for(players)


static func _scale_for(_players: int) -> float:
	return 1.0


# ---------------------------------------------------------------- run events

## The chance one director roll (net/run_events/director.gd, every
## HEAT_ROLL_SECONDS) sends the NICE BOYS: the workbook's base chance, rising with
## each finished job, plus the crew's heat (0..100), capped. Reaching HEAT_RAID_AT
## sends them whatever the roll; the director checks that itself.
## balance:E0 (pulled forward by R2 chunk 1): that formula is the chance per lot
## (BAL-14 is per job), so it is spread over the rolls of a lot of
## RAID_LOT_MINUTES: per roll 1 - (1 - p_lot)^(HEAT_ROLL_SECONDS / lot seconds).
## Before it, every 20 s roll took the whole per-lot chance, about 4-5 raids a job.
## gap balance:E still replaces lots_completed with the neighborhood index.
static func run_roll_chance(heat: float, lots_completed: int) -> float:
	var p_lot := run_lot_chance(heat, lots_completed)
	return 1.0 - pow(1.0 - p_lot, Constants.HEAT_ROLL_SECONDS / (Constants.RAID_LOT_MINUTES * 60.0))


## The chance the NICE BOYS come during one lot: the workbook's base, rising with
## each finished job, plus the crew's heat (0..100), capped.
static func run_lot_chance(heat: float, lots_completed: int) -> float:
	var chance := Balance.RUN_EVENT_BASE_CHANCE
	chance += Balance.RUN_CHANCE_ESCALATION_PER_TIER * float(lots_completed)
	chance += Constants.HEAT_CHANCE_AT_MAX * heat / 100.0
	return minf(chance, Balance.MAXIMUM_RUN_EVENT_CHANCE)
