class_name Ranks
extends RefCounted

## The crew's rank (docs/SPINE.md, "Crew rank"). Pure data and math, the same
## on every peer: a tier index (0 = Rake Rookie I) comes from total banked XP.
## Eight ranks of five tiers, then The Lawnfather, which never ends.
## Every tier unlocks something (some tiers more, EXTRA_UNLOCKS), so no rank-up is ever empty.

const NAMES: Array[String] = [
	"Rake Rookie", "Leaf Grunt", "Bag Hauler", "Mulch Mule",
	"Hedge Hog", "Turf Boss", "Lawn Lord", "Yard Baron",
]
const ENDLESS_NAME := "The Lawnfather"
const TIERS_PER_RANK: int = 5
const ROMAN: Array[String] = ["I", "II", "III", "IV", "V"]

## XP for tier t to t+1 is FIRST + STEP * t: two tiers on the first night, about
## one a day by Yard Baron. 30,100 XP through Yard Baron V: about 16 to 19 hours
## for four players or solo, 125 jobs for four and 60 alone (a small crew earns
## more a job, Constants.XP_CREW_SCALE). Tuned by tools/balance_sim.py (balance:E,
## docs/BALANCE.md); saves on the old curve keep their tier (crew.curve).
const XP_FIRST_TIER: int = 265
const XP_PER_TIER_STEP: int = 25
## Each Lawnfather star after that.
const XP_ENDLESS_TIER: int = 1500
## The curve's name, "first/step/endless" ("265/25/1500"). A save remembers it
## (crew.curve, gap balance:E) so banked XP can follow a retune of the three
## numbers above (core/economy.gd migrate_xp).
const CURVE_ID: String = "%d/%d/%d" % [XP_FIRST_TIER, XP_PER_TIER_STEP, XP_ENDLESS_TIER]
## The curve a save without crew.curve was banked under: every save made before
## the key existed. Never change it; it is history, not tuning.
const LEGACY_CURVE_ID: String = "150/25/1200"
## Each Lawnfather star adds this to every payout, up to the cap.
const ENDLESS_PAY_PER_STAR: float = 0.01
const ENDLESS_PAY_CAP: float = 0.25

## What each tier unlocks, in order from tier 1 (tier 0 is the start). Kinds:
##   shop:<item>   the item can be bought at Homie Depot
##   hood:<id>     the neighborhood opens (Town also wants a referral there)
##   perk:<id>     a standing bonus, read with Campaign.has_perk()
##   feature:<id>  a whole system turns on (hiring, the rival, properties)
const UNLOCKS: Array[String] = [
	"shop:rake_tier_1",          # Rake Rookie II
	"shop:leaf_blower",          # III
	"perk:extra_request",        # IV
	"shop:wheelbarrow_tier_1",   # V
	"hood:dandelion_acres",      # Leaf Grunt I
	"shop:lawn_mower",           # II
	"perk:sweet_talk",           # III
	"shop:ladder",               # IV
	"perk:bag_bonus",            # V
	"shop:hose",                 # Bag Hauler I
	"perk:night_owl",            # II
	"hood:birchwood_commons",    # III
	"shop:hedge_trimmer",        # IV
	"perk:cool_heads",           # V
	"shop:pressure_washer",      # Mulch Mule I
	"perk:extra_request_2",      # II
	"feature:rival",             # III
	"shop:paint_roller",         # IV
	"hood:oak_hollow",           # V
	"perk:word_of_mouth",        # Hedge Hog I
	"perk:bag_bonus_2",          # II
	"feature:hiring",            # III
	"perk:chefty_tuneup",        # IV
	"hood:lakeside",             # V
	"feature:garage",            # Turf Boss I
	"perk:hire_slot_2",          # II
	"perk:big_spenders",         # III
	"perk:extra_request_3",      # IV
	"perk:hire_slot_3",          # V
	"hood:mansion_hill",         # Lawn Lord I
	"feature:barn",              # II
	"perk:bag_bonus_3",          # III
	"perk:night_owl_2",          # IV
	"perk:hire_slot_4",          # V
	"feature:warehouse",         # Yard Baron I
	"perk:cool_heads_2",         # II
	"perk:word_of_mouth_2",      # III
	"perk:big_spenders_2",       # IV
	"feature:lawnfather",        # V: the endless rank begins
]

# ---- shops
## More unlocks at a tier, on top of UNLOCKS (which is never reordered: tests and
## saves depend on it). Other systems add theirs here too. tier -> ids.
const EXTRA_UNLOCKS: Dictionary = {
	2: ["feature:lunch_money"],          # Rake Rookie III: Lunch Money parks at Homie Depot
	5: ["feature:salvage"],              # Leaf Grunt I: Rusty's opens with Dandelion Acres
	7: ["shop:leaf_blower_mk2"],         # Leaf Grunt III
	9: ["shop:big_bags"],                # Leaf Grunt V: contractor bags
	11: ["shop:lawn_mower_mk2"],         # Bag Hauler II
	12: ["feature:truck_paint"],         # Bag Hauler III: Chefty paint and decals
	14: ["shop:ladder_mk2"],             # Bag Hauler V
	16: ["feature:deliveries"],          # Mulch Mule II: the phone's Orders app
	17: ["shop:hose_mk2"],               # Mulch Mule III
	19: ["shop:hedge_trimmer_mk2"],      # Mulch Mule V
	20: ["shop:pressure_washer_mk2"],    # Hedge Hog I
	21: ["shop:rake_tier_2"],            # Hedge Hog II: The Leafinator
	22: ["shop:paint_roller_mk2"],       # Hedge Hog III
	25: ["shop:leaf_blower_mk3"],        # Turf Boss I
	26: ["shop:lawn_mower_mk3"],         # Turf Boss II
	27: ["shop:ladder_mk3"],             # Turf Boss III
	28: ["shop:hose_mk3"],               # Turf Boss IV
	29: ["shop:hedge_trimmer_mk3"],      # Turf Boss V
	30: ["shop:pressure_washer_mk3"],    # Lawn Lord I
	31: ["shop:paint_roller_mk3"],       # Lawn Lord II
	33: ["shop:paint_gold"],             # Lawn Lord IV: GOLD
	39: ["shop:hat_crown"],              # Yard Baron V: the crown, with The Lawnfather
}


## XP needed to go from this tier to the next.
static func xp_for_tier(tier: int) -> int:
	if tier >= NAMES.size() * TIERS_PER_RANK:
		return XP_ENDLESS_TIER
	return XP_FIRST_TIER + XP_PER_TIER_STEP * tier


## Total banked XP it takes to reach this tier from the start (tier 0 is 0).
## Tests use it instead of writing XP numbers that a retune would break.
static func xp_to_reach(tier: int) -> int:
	var total := 0
	for below: int in maxi(0, tier):
		total += xp_for_tier(below)
	return total


## The tier reached with this much banked XP.
static func tier_for_xp(xp: int) -> int:
	var tier := 0
	var left := xp
	while left >= xp_for_tier(tier):
		left -= xp_for_tier(tier)
		tier += 1
	return tier


## XP banked past the start of this tier.
static func xp_into_tier(xp: int) -> int:
	var left := xp
	var tier := 0
	while left >= xp_for_tier(tier):
		left -= xp_for_tier(tier)
		tier += 1
	return left


## "Leaf Grunt III", or "The Lawnfather ★4".
static func title(tier: int) -> String:
	var last := NAMES.size() * TIERS_PER_RANK
	if tier >= last:
		return "%s ★%d" % [ENDLESS_NAME, tier - last + 1]
	return "%s %s" % [NAMES[tier / TIERS_PER_RANK], ROMAN[tier % TIERS_PER_RANK]]


## The unlock a tier brings, or "" (tier 0, and Lawnfather stars past the first).
static func unlock_at(tier: int) -> String:
	if tier <= 0 or tier > UNLOCKS.size():
		return ""
	return UNLOCKS[tier - 1]


## Everything a tier brings: its UNLOCKS entry first, then EXTRA_UNLOCKS.
static func unlocks_at(tier: int) -> PackedStringArray:
	var out := PackedStringArray()
	var primary := unlock_at(tier)
	if primary != "":
		out.append(primary)
	for extra: Variant in (EXTRA_UNLOCKS.get(tier, []) as Array):
		out.append(str(extra))
	return out


## Every unlock reached by this tier, in tier order.
static func unlocks_through(tier: int) -> PackedStringArray:
	var out := PackedStringArray()
	for reached: int in range(1, mini(tier, _last_unlock_tier()) + 1):
		out.append_array(unlocks_at(reached))
	return out


## The tier that unlocks this (e.g. "shop:ladder"), or 0 if it's open from the start.
static func tier_of(unlock: String) -> int:
	var index := UNLOCKS.find(unlock)
	if index >= 0:
		return index + 1
	for tier: Variant in EXTRA_UNLOCKS:
		if (EXTRA_UNLOCKS[tier] as Array).has(unlock):
			return int(tier)
	return 0


## The highest tier that unlocks anything.
static func _last_unlock_tier() -> int:
	var last := UNLOCKS.size()
	for tier: Variant in EXTRA_UNLOCKS:
		last = maxi(last, int(tier))
	return last


## Lawnfather stars add a little to every payout.
static func pay_bonus(tier: int) -> float:
	# The first Lawnfather tier is star 1, the way title() counts it.
	var stars := tier - NAMES.size() * TIERS_PER_RANK + 1
	if stars <= 0:
		return 0.0
	return minf(float(stars) * ENDLESS_PAY_PER_STAR, ENDLESS_PAY_CAP)
