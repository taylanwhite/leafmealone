class_name Constants
extends RefCounted

## Project-wide constants that are not tuning values. Tuning values live in
## core/balance.gd, which is generated from the design workbook.

## Bump on every build you hand to someone else. Peers on different versions cannot join each other.
const BUILD_VERSION: String = "0.2.0"

## Used to tag Steam lobbies while we share Valve's test app ID with everyone else.
const PROJECT_SLUG: String = "leaf-me-alone"

## ENet port for local development and the smoke test.
const DEFAULT_PORT: int = 7777

## Provisional. We build and test for up to 8 until the player count (OQ-016) is decided.
const MAX_PLAYERS: int = 8

## Valve's Spacewar test app. Replace with our own app ID once the game is registered in Steamworks.
const STEAM_APP_ID: int = 480

## Gray-box haul sizes Taylan set on 2026-10-12. Move them into the workbook when it has a row for them.
const WHEELBARROW_BAG_CAPACITY: int = 4
const WHEELBARROW_UPGRADED_BAG_CAPACITY: int = 8
const TRUCK_BAG_CAPACITY: int = 50
const BAG_LOAD_RADIUS: float = 1.8
const TRUCK_UNLOAD_RADIUS: float = 4.0

## OQ-025: captures this many seconds apart share one van. Not in the workbook yet.
const CAPTURE_BATCH_SECONDS: float = 3.0
## TODO(balance): forgiving capture distance, crew speed, and how long the warning shows.
const CAPTURE_RADIUS: float = 2.0
const CREW_SPEED: float = 5.5
const RUN_WARNING_SECONDS: float = 8.0

## OQ-010 counterplay v0. TODO(balance): not in the workbook yet.
## How close a player must be to a hiding spot to get in.
const HIDE_REACH: float = 1.8
## After losing sight of everyone, the crew searches this far around the last sighting...
const CREW_SEARCH_RADIUS: float = 8.0
## ...for this long, then patrols the lot.
const CREW_SEARCH_SECONDS: float = 12.0

## Disembark beat before the crossing clock.
## The workbook's full crossing is Balance.BORDER_RETURN_TARGET_DURATION_MINUTES.
## This gray-box run is 60 seconds, set 2026-10-13.
const BORDER_CROSSING_SECONDS: float = 60.0
const BORDER_STAGING_SECONDS: float = 3.0
const BORDER_THROWBACK_SECONDS: float = 0.55
const BORDER_RETURN_IMMUNITY_SECONDS: float = 4.0

## The rake and the homeowner, from Taylan on 2026-10-19 (docs/GAME.md, developer notes).
## TODO(balance): none of these are in the workbook yet.
## One rake per job. Holding it, a stroke moves this much density over this width.
const RAKE_STRENGTH: float = 72.0
const RAKE_WIDTH: float = 3.2
## A rake stroke every this many seconds while the button is held, each one
## shoving the leaves this many cells (0.5 m each) forward.
const RAKE_STROKE_SECONDS: float = 0.3
const RAKE_STROKE_CELLS: int = 3
## Raking with bare hands: goofy and barely useful.
const HAND_RAKE_STRENGTH: float = 9.0
const HAND_RAKE_WIDTH: float = 1.0
## Bagging takes the leaves within this radius, so raking them into a pile first fills a bag.
const BAG_RADIUS: float = 1.6
## A bag needs at least this many fresh-lot cells' worth of leaves, or there is nothing to bag.
const MIN_BAG_CELLS: float = 6.0
## Past this many minutes on a job, the homeowner thinks you took your time.
const HOMEOWNER_PATIENCE_MINUTES: float = 12.0
## The homeowner's pay as a multiple of the bags' value, by mood.
const HOMEOWNER_PAY_BY_MOOD: Dictionary = {"thrilled": 1.25, "happy": 1.1, "fine": 1.0, "slow": 0.9, "messy": 0.8}

## Proximity voice falloff from docs/NETCODE.md: clear within 2 m, gone by about 25 m.
const VOICE_CLEAR_DISTANCE: float = 2.0
const VOICE_MAX_DISTANCE: float = 25.0

## Weight and throwing, from Taylan on 2026-10-20: every item has a weight, and a
## thrown item hits people harder the heavier it is. TODO(balance): not in the workbook yet.
## What each kind of item weighs, in kg.
const ITEM_WEIGHT_KG: Dictionary = {
	"rake": 1.5, "leaf_bag": 3.0, "trash": 10.0, "wheelbarrow": 16.0, "gnome": 7.0,
	"leaf_blower": 4.5, "lawn_mower": 24.0, "ladder": 8.0, "hose": 4.0,
	"pressure_washer": 13.0, "hedge_trimmer": 4.0, "paint_roller": 1.5,
}
## A leaf bag gets heavier with the leaves in it: this much per dollar of value, up to the cap.
const LEAF_BAG_KG_PER_DOLLAR: float = 0.4
const LEAF_BAG_MAX_KG: float = 12.0
## Each bag riding in a wheelbarrow adds this much.
const WHEELBARROW_KG_PER_BAG: float = 4.0
## A throw gives every item the same shove: light things fly, heavy things flop.
const THROW_IMPULSE: float = 42.0
const THROW_SPEED_MIN: float = 2.5
const THROW_SPEED_MAX: float = 15.0
## Carrying slows you by this share per kg, never below the floor.
const CARRY_SLOWDOWN_PER_KG: float = 0.022
const CARRY_SPEED_FLOOR: float = 0.5
## A thrown item moving at least this fast bonks whoever it hits.
const BONK_MIN_SPEED: float = 3.0
## Bonk tiers by weight: up to "light" kg is a flinch, up to "medium" a stagger, heavier knocks you flat.
const BONK_TIER_KG: Dictionary = {"light": 4.0, "medium": 9.5}
## How long each tier takes control away, in seconds, and how hard it shoves (m/s per kg*m/s of hit).
const BONK_STUN_SECONDS: Dictionary = {"light": 0.35, "medium": 0.9, "heavy": 2.4}
const BONK_SHOVE_PER_MOMENTUM: float = 0.09
const BONK_SHOVE_MAX: float = 11.0

## Physics layer 3 (bit value 4): the invisible walls around each zone's pad. People
## mask it; thrown items don't, so they can sail into the street.
const PAD_WALL_LAYER: int = 4
## Half the size of every zone's pad, in meters. An item that lands outside it comes back in.
const PAD_HALF: float = 20.0
## Where people can go in each zone, in the zone's own x and z. The lot reaches out
## past the sidewalk into the near lane, where Chefty parks (Taylan, 2026-10-20).
const PAD_RECTS: Dictionary = {
	"StoreZone": Rect2(-20.0, -20.0, 40.0, 40.0),
	"LotZone": Rect2(-20.0, -20.0, 40.0, 49.0),
	"BorderZone": Rect2(-20.0, -20.0, 40.0, 40.0),
}

## Tools and tasks, from Taylan on 2026-10-20: buying a tool unlocks the task it
## does, and every job asks for a different mix (docs/GAME.md, developer notes).
## TODO(balance): prices, pay, weights, and work rates are not in the workbook yet.
## Tool id -> price at Homie Depot, in dollars.
const TOOL_PRICES: Dictionary = {
	"leaf_blower": 110, "lawn_mower": 180, "ladder": 140, "hose": 70,
	"pressure_washer": 260, "hedge_trimmer": 130, "paint_roller": 90,
}
## Task id -> the tool it needs ("" for bare hands). Raking is paid by the bag.
const TASK_TOOLS: Dictionary = {
	"rake_leaves": "", "pick_litter": "", "pull_weeds": "",
	"mow_lawn": "lawn_mower", "clean_gutters": "ladder", "wash_windows": "hose",
	"power_wash": "pressure_washer", "trim_hedges": "hedge_trimmer", "paint_fence": "paint_roller",
}
## Task id -> what the homeowner pays for it done completely, in dollars.
const TASK_PAY: Dictionary = {
	"pick_litter": 12, "pull_weeds": 15, "mow_lawn": 45, "clean_gutters": 40,
	"wash_windows": 30, "power_wash": 55, "trim_hedges": 35, "paint_fence": 40,
}
## How much of a spot or cell each second of work clears, out of 100.
const TASK_WORK_RATE: Dictionary = {
	"pick_litter": 100.0, "pull_weeds": 40.0, "mow_lawn": 450.0, "clean_gutters": 45.0,
	"wash_windows": 55.0, "power_wash": 90.0, "trim_hedges": 50.0, "paint_fence": 60.0,
}
## How far from you a tool reaches, in meters.
const TASK_REACH: Dictionary = {
	"pick_litter": 2.0, "pull_weeds": 2.0, "mow_lawn": 0.9, "clean_gutters": 2.6,
	"wash_windows": 8.0, "power_wash": 3.2, "trim_hedges": 2.2, "paint_fence": 2.0,
}
## How many tasks a job asks for besides the leaves, at least and at most (three in all).
## Taylan, 2026-10-20: too much at once felt like a chore list.
const JOB_EXTRA_TASKS := Vector2i(2, 2)
## A leaf blower pushes leaves this far each puff, this wide, this often.
const BLOWER_STRENGTH: float = 45.0
const BLOWER_WIDTH: float = 2.4
const BLOWER_CELLS: int = 6
const BLOWER_PUFF_SECONDS: float = 0.15

## Things with wheels: carrying them slows you only this share as much as their weight says.
const ROLLING_KINDS: Array[String] = ["lawn_mower", "wheelbarrow", "pressure_washer"]
const ROLLING_WEIGHT_SHARE: float = 0.3

## Throwing with G, from Taylan on 2026-10-20: hold to wind up, release to throw.
## TODO(balance): not in the workbook yet.
## A tap shorter than this just sets the item down.
const THROW_TAP_SECONDS: float = 0.18
## Holding this long winds up a full-power throw.
const THROW_CHARGE_SECONDS: float = 1.2
## Throw speed at no wind-up and at full wind-up, as a share of a normal throw.
const THROW_POWER_MIN: float = 0.35
const THROW_POWER_MAX: float = 1.5
## Still holding after this long, you start straining; after this long, you faint.
const THROW_STRAIN_SECONDS: float = 5.0
const THROW_FAINT_SECONDS: float = 7.0
const FAINT_SECONDS: float = 2.5
