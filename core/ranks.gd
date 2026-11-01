class_name Ranks
extends RefCounted

## The crew's rank (docs/SPINE.md, "Crew rank"). Pure data and math, the same
## on every peer: a tier index (0 = Rake Rookie I) comes from total banked XP.
## Eight ranks of five tiers, then The Lawnfather, which never ends.
## Every tier unlocks something, so no rank-up is ever empty.

const NAMES: Array[String] = [
	"Rake Rookie", "Leaf Grunt", "Bag Hauler", "Mulch Mule",
	"Hedge Hog", "Turf Boss", "Lawn Lord", "Yard Baron",
]
const ENDLESS_NAME := "The Lawnfather"
const TIERS_PER_RANK: int = 5
const ROMAN: Array[String] = ["I", "II", "III", "IV", "V"]

## XP for tier t to t+1 is FIRST + STEP * t: about one job a tier at the start,
## three to four by Yard Baron. 25,500 XP through Yard Baron V, roughly 150 jobs
## or 15 to 20 hours.
const XP_FIRST_TIER: int = 150
const XP_PER_TIER_STEP: int = 25
## Each Lawnfather star after that.
const XP_ENDLESS_TIER: int = 1200
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


## XP needed to go from this tier to the next.
static func xp_for_tier(tier: int) -> int:
	if tier >= NAMES.size() * TIERS_PER_RANK:
		return XP_ENDLESS_TIER
	return XP_FIRST_TIER + XP_PER_TIER_STEP * tier


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


## Every unlock reached by this tier.
static func unlocks_through(tier: int) -> PackedStringArray:
	var out := PackedStringArray()
	for index: int in mini(tier, UNLOCKS.size()):
		out.append(UNLOCKS[index])
	return out


## The tier that unlocks this (e.g. "shop:ladder"), or 0 if it's open from the start.
static func tier_of(unlock: String) -> int:
	var index := UNLOCKS.find(unlock)
	return index + 1 if index >= 0 else 0


## Lawnfather stars add a little to every payout.
static func pay_bonus(tier: int) -> float:
	# The first Lawnfather tier is star 1, the way title() counts it.
	var stars := tier - NAMES.size() * TIERS_PER_RANK + 1
	if stars <= 0:
		return 0.0
	return minf(float(stars) * ENDLESS_PAY_PER_STAR, ENDLESS_PAY_CAP)
