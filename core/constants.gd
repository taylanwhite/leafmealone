class_name Constants
extends RefCounted

## Project-wide constants that are not tuning values. Tuning values live in
## core/balance.gd, which is generated from the design workbook.

## Bump on every build you hand to someone else. Peers on different versions cannot join each other.
const BUILD_VERSION: String = "0.4.1"

## Used to tag Steam lobbies while we share Valve's test app ID with everyone else.
const PROJECT_SLUG: String = "leaf-me-alone"

## ENet port for local development and the smoke test.
const DEFAULT_PORT: int = 7777

## OQ-016 closed 2026-11-01 (Taylan): four, the truck's seats, so nobody is left at the store.
const MAX_PLAYERS: int = 4

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
## A chase with no capture ends after this long: the NICE BOYS give up and drive off.
const RUN_CHASE_SECONDS: float = 75.0
## The crew also leaves once nobody has been on the lot for this long.
const RUN_EMPTY_LOT_SECONDS: float = 3.0

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
	"turf_sign": 2.0,
	"gas_can": 6.0, "fertilizer_bag": 9.0, "rock_salt": 9.0, "grass_seed": 5.0,
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
## Footsteps crunch in leaves at least this thick (leaf field density, 60 is a fresh lot).
const STEP_LEAVES_DENSITY: int = 18
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
	"clear_roof": "ladder", "skim_pool": "",
}
## Task id -> what the homeowner pays for it done completely, in dollars.
const TASK_PAY: Dictionary = {
	"pick_litter": 12, "pull_weeds": 15, "mow_lawn": 45, "clean_gutters": 40,
	"wash_windows": 30, "power_wash": 55, "trim_hedges": 35, "paint_fence": 40,
	"clear_roof": 35, "skim_pool": 25,
}
## How much of a spot or cell each second of work clears, out of 100.
const TASK_WORK_RATE: Dictionary = {
	"pick_litter": 100.0, "pull_weeds": 40.0, "mow_lawn": 450.0, "clean_gutters": 30.0,
	"wash_windows": 55.0, "power_wash": 90.0, "trim_hedges": 50.0, "paint_fence": 60.0,
	"clear_roof": 35.0, "skim_pool": 50.0,
}
## How far from you a tool reaches, in meters.
const TASK_REACH: Dictionary = {
	"pick_litter": 2.0, "pull_weeds": 2.0, "mow_lawn": 0.9, "clean_gutters": 2.6,
	"wash_windows": 40.0, "power_wash": 3.2, "trim_hedges": 2.2, "paint_fence": 2.0,
	"clear_roof": 1.8, "skim_pool": 2.7,
}
## How many tasks a job asks for besides the leaves, at least and at most (three in all).
## Taylan, 2026-10-20: too much at once felt like a chore list.
## How many job offers the board at Homie Depot shows.
const JOB_BOARD_OFFERS: int = 3
## Heat, from Taylan on 2026-10-21 (docs/FUN.md): the noise the crew makes, what
## it breaks, and who it bonks draw the NICE BOYS. 0 to 100; the run director
## rolls against it (net/run_events/heat.gd). TODO(balance): not in the workbook.
const HEAT_NOISE_PER_SECOND: Dictionary = {"lawn_mower": 1.6, "leaf_blower": 1.4, "pressure_washer": 1.0, "hedge_trimmer": 0.9}
const HEAT_HYDRANT: float = 12.0
const HEAT_PER_BILL_DOLLAR: float = 0.15
const HEAT_PEDESTRIAN_BONK: Dictionary = {"light": 4.0, "medium": 8.0, "heavy": 14.0}
const HEAT_CREW_BONK: float = 10.0
const HEAT_COAT_PERSON: float = 6.0
## Cooling: per quiet second on the job, and when a job is paid.
const HEAT_COOL_PER_SECOND: float = 0.25
const HEAT_COOL_PER_JOB: float = 35.0
## What heat drops to once the van leaves.
const HEAT_AFTER_RAID: float = 15.0
## The director rolls this often on the lot; the chance per roll at full heat
## (added to Balance.RUN_EVENT_BASE_CHANCE), and the heat at which a raid is certain.
const HEAT_ROLL_SECONDS: float = 20.0
const HEAT_CHANCE_AT_MAX: float = 0.9
const HEAT_RAID_AT: float = 95.0
## One more NICE BOY for every this much heat, up to the max.
const HEAT_PER_EXTRA_CREW: float = 35.0
const HEAT_MAX_CREW: int = 3
## Heat levels that get a warning caption (ui/strings.gd heat_warn_*).
const HEAT_WARN_AT: Array = [50.0, 80.0]

## Brawling (Taylan, 2026-10-21): wind up a punch with empty hands (hold left
## click; the longer, the harder, until you spin yourself dizzy), whack with
## whatever's held (as hard as it's heavy), grab a friend and carry or throw them.
const PUNCH_REACH: float = 1.8
const WHACK_REACH: float = 1.9
## Wind-up seconds: under the first is a light punch, under the second medium, past it heavy.
const PUNCH_WIND_TIERS: Array = [0.35, 1.1]
## Wind up longer than this and you spin out and fall over.
const PUNCH_DIZZY_SECONDS: float = 3.0
const PUNCH_PUSH: Dictionary = {"light": 2.0, "medium": 3.5, "heavy": 7.0}
const GRAB_PLAYER_REACH: float = 1.6
const CARRY_PLAYER_SPEED_SHARE: float = 0.55
const PLAYER_THROW_SPEED: float = 5.5
const PLAYER_THROW_LIFT: float = 4.0
## Key presses it takes for a carried player to wriggle free.
const STRUGGLE_PRESSES: int = 6
const THROWN_HIT_RADIUS: float = 1.0

## Diving into a pile of leaves to hide: how thick it has to be (leaf units within the radius).
const PILE_HIDE_RADIUS: float = 1.0
const PILE_HIDE_UNITS: int = 2200
## A running mower let go of drives off on its own.
const MOWER_RUNAWAY_SPEED: float = 2.2
const MOWER_RUNAWAY_SECONDS: float = 9.0
## A set-up ladder is knocked down by anything flying at least this fast.
const LADDER_KNOCK_MIN_SPEED: float = 3.0
const LADDER_KNOCK_RADIUS: float = 1.2
## Paint and water on people: how close counts, and how long they wear it.
const COAT_REACH: float = 1.4
const PAINT_SECONDS: float = 60.0
const SOAK_SECONDS: float = 25.0
const SOAK_SLIP_SECONDS: float = 0.7

## How often a yard is small, regular, or big, and how many more tasks each asks for.
## A crew with a better rating gets offered big yards more often (YARD_BIG_PER_STAR
## per star above three). TODO(balance): not in the workbook yet.
const YARD_SIZE_CHANCE: Array = [0.3, 0.45, 0.25]
const YARD_EXTRA_TASKS: Array = [0, 0, 1]
const YARD_BIG_PER_STAR: float = 0.1
## What changes with a yard's size: the house's width range, how many trees, how
## much litter, and how thick the leaves lie (times normal). Big yards have a pool.
const YARD_HOUSE_WIDTH: Array = [Vector2(7.0, 9.0), Vector2(8.0, 12.5), Vector2(11.5, 14.0)]
const YARD_TREES: Array = [Vector2i(1, 3), Vector2i(2, 5), Vector2i(4, 7)]
const YARD_LITTER: Array = [Vector2i(4, 7), Vector2i(6, 11), Vector2i(9, 14)]
const YARD_LEAVES: Array = [0.8, 1.0, 1.25]
## The homeowner's rating by mood, in stars out of five, and how many recent
## jobs the crew's rating averages. TODO(balance): not in the workbook yet.
const MOOD_STARS: Dictionary = {"messy": 1, "slow": 2, "fine": 3, "happy": 4, "thrilled": 5}
const RATING_JOBS: int = 10
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

## The ladder, from Taylan on 2026-10-20: set it against the house, climb it, and
## work the gutters from the top. TODO(balance): not in the workbook yet.
## How close to a gutter you must stand to set the ladder up, and to work from the top.
const LADDER_SET_REACH: float = 3.0
const LADDER_TOP_REACH: float = 1.9
## Seconds to climb all the way up or down.
const LADDER_CLIMB_SECONDS: float = 1.1
## Scooping gutters with a leaf blower goes this many times faster than by hand.
const GUTTER_BLOWER_SPEEDUP: float = 3.0

## Water, from Taylan on 2026-10-20: the hose has to be hooked up to something,
## the homeowner bills you for using theirs, a fire hydrant is way too much, and
## the pressure washer has a tank that runs dry. TODO(balance): not in the workbook yet.
## Water sources: how fast water leaves the nozzle (m/s) when hooked to each.
const WATER_SPEED: Dictionary = {"chefty": 11.0, "spigot": 9.5, "hydrant": 20.0}
## The homeowner's water bill: a fee for hooking up, then per second of spraying.
const SPIGOT_HOOKUP_FEE: int = 5
const SPIGOT_FEE_PER_SECOND: float = 0.6
## How long the hose is. Walk farther than this from where it's hooked up and it snaps loose.
const HOSE_LENGTH: float = 24.0
## How close to a source you must be to hook up or refill.
const WATER_REACH: float = 2.2
## How far a snapping hose's loose end whips, and how close it must pass to knock someone out.
const HOSE_WHIP_SECONDS: float = 0.6
const HOSE_WHIP_RADIUS: float = 1.3
## A hydrant pushes you back and up while you hold on, swinging side to side, up to this fast.
const HYDRANT_PUSH: float = 9.0
const HYDRANT_LIFT: float = 11.5
const HYDRANT_MAX_SPEED: float = 4.5
## Hydrant water cleans this many times faster (it goes everywhere).
const HYDRANT_CLEAN_SPEEDUP: float = 2.5
## The pressure washer's tank, out of 100: what a second of spraying uses.
const WASHER_USE_PER_SECOND: float = 3.0
## How fast the pressure washer's water leaves the wand.
const WASHER_SPEED: float = 14.0

## Roofs and falls, from Taylan on 2026-10-20. TODO(balance): not in the workbook yet.
## Fall farther than this and you hurt yourself: a bounce, knocked out a moment,
## then a limp. How long the limp lasts is never shown to players.
const FALL_HURT_HEIGHT: float = 3.2
const FALL_BOUNCE_SPEED: float = 3.2
const FALL_KNOCKOUT_SECONDS: float = 3.5
const LIMP_SECONDS: float = 75.0
const LIMP_SPEED_SHARE: float = 0.5
## The mower has to be pull-started: the chance the first pull catches, and how
## much better each pull after that gets.
const MOWER_START_CHANCE: float = 0.3
const MOWER_START_GAIN: float = 0.25
## The paint roller holds this many seconds of paint before it needs dipping again.
const ROLLER_PAINT_SECONDS: float = 8.0

## Running things over with the mower, from Taylan on 2026-10-20.
## TODO(balance): not in the workbook yet.
## How close to the mower's deck something has to be to get run over.
const MOWER_HIT_RADIUS: float = 0.7
## What the homeowner (or the hospital) bills you, in dollars.
const BILL_HOSE: int = 25
const BILL_GNOME: int = 15
const BILL_FOOT_CUT: int = 40
const BILL_FOOT_OFF: int = 120
## Of feet run over, this share come clean off (the rest are cuts).
const FOOT_OFF_CHANCE: float = 0.3
## Hopping on one foot: this share of walking speed.
const HOP_SPEED_SHARE: float = 0.45


# ---------------------------------------------------------------- the spine
# docs/SPINE.md. First guesses, tuned by playing.

## The work day: one in-game hour is this many real minutes. The day opens at
## 7:00 AM; quiet hours start at 9:00 PM; the clock stops at 2:00 AM (26).
const MINUTES_PER_HOUR: float = 1.25
const DAY_START_HOUR: float = 7.0
const QUIET_HOURS_START: float = 21.0
const DAY_CLOSE_HOUR: float = 26.0
## Quiet hours: jobs pay this much more, and noise heats the crew this many times faster.
const QUIET_HOURS_PAY_BONUS: float = 0.25
const QUIET_HOURS_HEAT_SCALE: float = 2.0
## Each night-owl perk adds this on top.
const NIGHT_OWL_PAY_BONUS: float = 0.1
## The host holds E on a cot this long to put everyone to bed.
const SLEEP_FORCE_SECONDS: float = 3.0
## Where the crew sleeps: cots by Homie Depot's side wall, in the store zone's space.
const COT_SPOTS: Array[Vector3] = [Vector3(-8.0, 0.0, -15.6), Vector3(-8.0, 0.0, -14.2), Vector3(-8.0, 0.0, -12.8), Vector3(-8.0, 0.0, -11.4)]

## XP (core/ranks.gd has the curve): a fully raked yard, each other task done
## completely, each star of the review. Raking counts as full at this much clean.
const XP_LEAVES_FULL: int = 60
const XP_LEAVES_CLEAN_AT: float = 0.9
const XP_PER_TASK: int = 35
const XP_PER_STAR: int = 12
## A new client's first job, a referral, bonking a NICE BOY, getting away from them.
const XP_NEW_CLIENT: int = 50
const XP_CREW_BONK: int = 5
const XP_ESCAPE: int = 40
## Perks.
const SWEET_TALK_PATIENCE: float = 1.25
const BAG_BONUS_PER_PERK: float = 0.1
const COOL_HEADS_COOLING: float = 1.25
const BIG_SPENDERS_BUDGET: float = 0.15

## The town (net/town/town.gd). Leaves regrow this share of a full yard per day
## since the last job there, up to full; a never-done yard starts this full.
const TOWN_REGROW_PER_DAY: float = 0.35
const TOWN_FIRST_MESS: float = 1.0
const TOWN_MIN_MESS: float = 0.25
## Clients who text a job each morning (plus the extra-request perks), and how
## grown back a yard must be before its owner asks again.
const TOWN_REQUESTS_PER_DAY: int = 2
const TOWN_REQUEST_MIN_MESS: float = 0.3
## Relationship, 0 to 100: where a new client starts, what each star of a review
## moves it (3 stars is no change), and the level where they refer a neighbor.
const TOWN_START_RELATIONSHIP: float = 30.0
const TOWN_RELATIONSHIP_PER_STAR: float = 7.0
const TOWN_REFERRAL_AT: float = 60.0
## How many clients you know in Maple Row on day one.
const TOWN_STARTING_CLIENTS: int = 3

## Hired hands (net/crew/hires.gd, npcs/crew_hand.gd): what one costs to sign
## and per day, how often they rake, how many strokes make a pile, how fast they walk.
const HIRE_SIGNING_FEE: int = 150
const HIRE_DAILY_WAGE: int = 40
const HIRE_STROKE_SECONDS: float = 0.55
const HIRE_STROKES_PER_PILE: int = 10
const HIRE_SPEED: float = 3.2

## Seasons (core/seasons.gd): days in each, autumn first.
const SEASON_DAYS: int = 7

## The rival, TurfMasters™ (net/town/town.gd), once the rank brings them to town:
## the chance each morning they poach a client below this relationship, the chance
## a great job wins one back, signs in a yard (at most), and XP per sign pulled.
const RIVAL_POACH_CHANCE: float = 0.35
const RIVAL_POACH_BELOW: float = 55.0
const RIVAL_WIN_BACK_CHANCE: float = 0.5
const RIVAL_MAX_SIGNS: int = 3
const XP_SIGN_PULLED: int = 15

## The cots take sleepers from this hour (6 PM) on; before that the day can't be skipped.
const SLEEP_FROM_HOUR: float = 18.0

## Picking things up (player.gd _best_pickup): how far E reaches, and how many
## meters closer a leaf bag counts than anything else.
const PICKUP_REACH: float = 2.4
const PICKUP_BAG_PREFERENCE: float = 0.8
## The quip about slow progress waits this many seconds after arriving on a yard.
const QUIP_LOW_CLEANUP_AFTER: float = 120.0
## Where right-click looks for the pile ahead (equipment/rake.gd): from this far to this far, in meters.
const PILE_SEARCH_NEAR: float = 1.0
const PILE_SEARCH_FAR: float = 3.2


# ---- balance
# Economy numbers that used to sit inline in the gameplay scripts, moved here with
# the same values (gap balance:A) so tools/balance_sim.py can read every one of
# them from this file. TODO(balance): not in the workbook yet.

## The town (net/town/town.gd): in-game hours when a client may text a job during
## the day, and the chance at each one.
const TOWN_DAYTIME_TEXT_HOURS: Array[float] = [10.0, 13.0, 16.0, 19.0]
const TOWN_DAYTIME_TEXT_CHANCE: float = 0.5
## Relationship a paid job adds on top of the stars, and what a request nobody
## took costs the next morning.
const TOWN_RELATIONSHIP_PER_JOB: float = 2.0
const TOWN_RELATIONSHIP_MISSED: float = 3.0
## Marty's lead in a new neighborhood credits a client at least this share of
## TOWN_REFERRAL_AT.
const TOWN_LEAD_REFERRAL_SHARE: float = 0.75
## XP for meeting a client by referral (or Marty's lead), and for winning one
## back from TurfMasters™.
const XP_REFERRAL: int = 25
const XP_WON_BACK: int = 25

## The homeowner's verdict (npcs/homeowner.gd _judge): how done the job must be
## to be clean enough, and below what it is a mess, for an owner of standards 0.3;
## how much each step of standards above that moves them; and the odds of the
## better mood in each band.
const HOMEOWNER_CLEAN_ENOUGH: float = 0.85
const HOMEOWNER_MESSY_BELOW: float = 0.5
const HOMEOWNER_STANDARDS_CLEAN_SLOPE: float = 0.25
const HOMEOWNER_STANDARDS_MESSY_SLOPE: float = 0.3
const HOMEOWNER_THRILLED_CHANCE: float = 0.6
const HOMEOWNER_HAPPY_CHANCE: float = 0.5
## The standards those two lines are set for, and how far standards can push each
## (core/economy.gd mood_thresholds, gap balance:B; the values the clamps always had,
## as plain floats so they keep full precision).
const HOMEOWNER_STANDARDS_PIVOT: float = 0.3
const HOMEOWNER_CLEAN_ENOUGH_MIN: float = 0.7
const HOMEOWNER_CLEAN_ENOUGH_MAX: float = 0.97
const HOMEOWNER_MESSY_BELOW_MIN: float = 0.3
const HOMEOWNER_MESSY_BELOW_MAX: float = 0.75

## The job board (levels/job_board.gd choose_tasks): the chance a job asks for
## one task that needs a tool the crew doesn't own yet.
const JOB_UNOWNED_TASK_CHANCE: float = 0.3

## Leaves on a fresh yard (levels/lots/lot_generator.gd _shape_leaves): the even
## base cover (a random pick in this range, times YARD_LEAVES), what each tree
## heaps under itself, how far that spreads (meters, a random pick in this range),
## and the most any cell starts with.
const YARD_LEAF_BASE := Vector2(0.45, 0.75)
const YARD_TREE_LEAVES: float = 1.6
const YARD_TREE_SPREAD := Vector2(4.5, 6.5)
const YARD_LEAF_CAP: float = 2.6

## A hired hand's skill (net/crew/hires.gd), a random pick in this range.
const HIRE_SKILL := Vector2(0.55, 0.85)

## A run event only rolls once the job is at least this far along (net/run_events/rules.gd).
const RUN_PROGRESS_FRACTION: float = 0.1

## Every shop price that isn't a base tool (TOOL_PRICES) is SHOP_PRICES, under
## "# ---- shops" below: balance:A started it with the two upgrades and shops:1
## extended it. Catalog.price reads it, and Campaign.price_of delegates to that.

# ---- shops
# The shops (docs/GAME.md, "Shops"). The catalog's ids and shapes are data in
# core/catalog.gd; every number they need is here. First guesses, tuned by playing.

## Where each shop is, in its zone's own space (contract with the drivable town:
## this is the single source of where shops stand). counter/keeper are where you
## buy and who stands there; area is the yard or shelves you can also buy from.
const SHOP_SITES: Dictionary = {
	"homie_depot": {
		"zone": "StoreZone", "counter": Vector3(0.0, 0.0, -8.0), "keeper": Vector3(0.0, 0.0, -9.3),
		"yaw": 0.0, "area": Rect2(8.5, -16.5, 9.0, 7.0),
	},
	"rustys": {
		"zone": "StoreZone", "counter": Vector3(15.2, 0.0, -4.5), "keeper": Vector3(16.4, 0.0, -4.5),
		"yaw": -PI / 2.0, "area": Rect2(12.5, -8.0, 7.5, 12.0),
		"scale": Vector3(14.2, 0.0, -1.8), "rack": Vector3(18.6, 0.0, 0.5),
	},
	"lunch_money": {
		"zone": "StoreZone", "truck": Vector3(3.0, 0.0, 15.6), "counter": Vector3(5.2, 0.0, 15.4),
		"keeper": Vector3(4.2, 0.0, 15.6), "yaw": 0.0, "area": Rect2(4.2, 14.0, 2.4, 3.0),
	},
	"snak_o_matic": {
		"zone": "StoreZone", "counter": Vector3(-11.5, 0.0, 4.5), "keeper": Vector3(-11.5, 0.0, 4.5),
		"yaw": PI / 2.0, "area": Rect2(-11.5, 3.5, 2.0, 2.0),
	},
	"back_room": {"zone": "StoreZone", "counter": Vector3(-10.5, 0.0, -18.4)},
}
## Opening hours, in clock hours (26 is 2 AM): open at x, close at y.
const SHOP_HOURS: Dictionary = {
	"homie_depot": Vector2(7.0, 21.0), "rustys": Vector2(9.0, 18.0),
	"lunch_money": Vector2(11.0, 23.0), "snak_o_matic": Vector2(0.0, 99.0),
}
## Rusty goes fishing every this many days (GONE FISHIN').
const RUSTYS_CLOSED_EVERY: int = 7
## How close you must be to a shop's counter (or inside its area) to buy, plus
## the host's slack for lag.
const SHOP_REACH: float = 3.0
const SHOP_REACH_SLACK: float = 1.5

## Prices for everything that isn't a tool tier (tools are TOOL_PRICES x
## TOOL_TIER_PRICE). Snak-o-Matic prices here are before VENDING_PRICE_SCALE.
const SHOP_PRICES: Dictionary = {
	# Upgrades. The first two match Balance.BASELINE_TIER_1_TOOL_COST.
	"rake_tier_1": 120, "wheelbarrow_tier_1": 120, "rake_tier_2": 1200,
	# Supplies.
	"lawn_bags": 8, "big_bags": 14, "gas_can": 12, "fertilizer": 18, "grass_seed": 15, "rock_salt": 10,
	# Food: Lunch Money, then the Snak-o-Matic.
	"hot_dog": 6, "turbo_juice": 9, "coffee": 4,
	"vend_bags": 4, "vend_sandwich": 3, "vend_turbo": 9,
	# Hats and shirts.
	"hat_hd_cap": 25, "hat_beanie": 40, "hat_bucket": 60, "hat_hard": 90, "hat_cowboy": 180,
	"hat_chef": 250, "hat_lunch_money": 45, "hat_cone": 35, "hat_propeller": 75, "hat_viking": 300,
	"hat_crown": 2500,
	"shirt_0": 30, "shirt_1": 30, "shirt_2": 30, "shirt_3": 30,
	"shirt_4": 30, "shirt_5": 30, "shirt_6": 30, "shirt_7": 30, "shirt_hivis": 120,
	# Chefty: paint and decals. Factory red is free, so you can always go back.
	"paint_classic": 0, "paint_mint": 400, "paint_sunset": 400, "paint_pink": 500,
	"paint_black": 800, "paint_gold": 5000,
	"decal_stripes": 250, "decal_googly": 350, "decal_flames": 600, "decal_leaves": 900, "decal_rust": 50,
}
## What each shop puts out every morning; an item not listed never runs out.
const SHOP_DAILY_STOCK: Dictionary = {
	"homie_depot": {"lawn_bags": 12, "big_bags": 6, "gas_can": 10, "fertilizer": 6, "grass_seed": 6, "rock_salt": 8},
	"rustys": {},
	"lunch_money": {},
	"snak_o_matic": {"vend_bags": 4, "vend_sandwich": 6, "vend_turbo": 6},
}

## Tool tiers, indexed by tier: 0 used, 1 stock, 2 Mk II, 3 Mk III.
## Price, work speed, noise heat, fuel use, reach, engine volume (dB), and how
## much easier a pull-start catches.
const TOOL_TIER_PRICE: Array[float] = [0.55, 1.0, 3.5, 10.0]
const TOOL_TIER_SPEED: Array[float] = [0.85, 1.0, 1.35, 1.8]
const TOOL_TIER_NOISE: Array[float] = [1.35, 1.0, 0.7, 0.4]
const TOOL_TIER_FUEL: Array[float] = [1.3, 1.0, 0.8, 0.6]
const TOOL_TIER_REACH: Array[float] = [1.0, 1.0, 1.15, 1.3]
const TOOL_TIER_VOLUME_DB: Array[float] = [3.0, 0.0, -5.0, -10.0]
const TOOL_TIER_START_BONUS: Array[float] = [-0.1, 0.0, 0.2, 0.35]
## Each Mk III's one silly perk: the mower's start chance (always), the hose's
## length in m, the washer tank lasting this many times longer, the ladder
## climbing this many times faster, the trimmer's width and the roller's paint
## times this, and the blower shoving leaves this many times farther.
const MK3_PERKS: Dictionary = {
	"lawn_mower": 1.0, "hose": 40.0, "pressure_washer": 2.0, "ladder": 2.0,
	"hedge_trimmer": 2.0, "paint_roller": 3.0, "leaf_blower": 1.5,
}

## Supplies are the crew's, not a player's. What one catalog item adds to its
## supply (bags in a roll, gallons in a can, sacks).
const SUPPLY_PER_ITEM: Dictionary = {
	"lawn_bags": 25, "big_bags": 15, "gas_can": 5.0, "fertilizer": 1, "grass_seed": 1, "rock_salt": 1,
	"vend_bags": 10,
}
## A new crew's supplies. Timed test runs (other than --shop-test) never run out.
const STARTER_SUPPLIES: Dictionary = {
	"lawn_bags": 40, "big_bags": 0, "gas": 6.0, "fertilizer": 0, "grass_seed": 0, "rock_salt": 0,
}
const TEST_STARTER_SUPPLIES: Dictionary = {
	"lawn_bags": 9999, "big_bags": 9999, "gas": 9999.0, "fertilizer": 9999, "grass_seed": 9999, "rock_salt": 9999,
}
## Each morning a crew with fewer bags than this gets topped up to it (Marty's
## "found a few behind the paint mixer").
const EMERGENCY_BAGS: int = 5
## Contractor bags scoop this much wider.
const BIG_BAG_RADIUS_SCALE: float = 1.3

## Gas: which tools burn it, how much of a tank each burns per second running
## (out of 100), the gallons in a tank, and the most a gas can carries.
const GAS_TOOLS: Array[String] = ["lawn_mower", "leaf_blower", "hedge_trimmer", "pressure_washer"]
const FUEL_BURN_PER_SECOND: Dictionary = {
	"lawn_mower": 0.5, "leaf_blower": 0.6, "hedge_trimmer": 0.4, "pressure_washer": 0.35,
}
const GAS_PER_TANK: float = 1.0
const GAS_CAN_CARRY: float = 5.0

## Deliveries: a flat fee plus a share of the price, how many clock hours they
## take, when after-hours orders land, and how many can be open at once.
const DELIVERY_FEE: int = 15
const DELIVERY_FEE_SHARE: float = 0.1
const DELIVERY_HOURS: float = 2.0
const DELIVERY_AFTER_HOURS_ARRIVE: float = 9.0
const DELIVERY_MAX_OPEN: int = 3

## Snacks: how long each buff lasts and what it multiplies (speed: walking,
## carry: the slowdown from weight, strain: how long you can hold a throw,
## stroke: the time between rake strokes). "then" chains into another buff.
const BUFFS: Dictionary = {
	"full": {"seconds": 360.0, "carry": 0.5},
	"turbo": {"seconds": 240.0, "speed": 1.2, "stroke": 0.8, "then": "crash"},
	"crash": {"seconds": 20.0, "speed": 0.75},
	"coffee": {"seconds": 480.0, "strain": 1.6},
	"queasy": {"seconds": 20.0, "speed": 0.8},
}
## The Snak-o-Matic: its markup, how often it eats your money, and how often
## its sandwich makes you queasy instead of full.
const VENDING_PRICE_SCALE: float = 1.5
const VENDING_EAT_CHANCE: float = 0.1
const VENDING_QUEASY_CHANCE: float = 0.5

## Junk for Rusty's: weight in kg and base value range per type, the vintage
## flamingo jackpot, how many a yard has by hood ("" is every other hood),
## Chefty's junk slots, and how close to the scale junk counts as on it.
const JUNK_TYPES: Dictionary = {
	"old_tv": {"kg": 18.0, "value": Vector2i(15, 30)},
	"tire": {"kg": 10.0, "value": Vector2i(6, 12)},
	"grill": {"kg": 20.0, "value": Vector2i(20, 40)},
	"toilet": {"kg": 28.0, "value": Vector2i(25, 45)},
	"bike": {"kg": 12.0, "value": Vector2i(15, 35)},
	"flamingo": {"kg": 1.5, "value": Vector2i(4, 10)},
	"mannequin": {"kg": 9.0, "value": Vector2i(10, 25)},
	"boombox": {"kg": 5.0, "value": Vector2i(12, 30)},
}
const JUNK_JACKPOT: Dictionary = {"chance": 0.05, "value": 120}
const JUNK_PER_HOOD: Dictionary = {"dandelion_acres": Vector2i(3, 6), "": Vector2i(0, 2)}
const TRUCK_JUNK_CAPACITY: int = 8
const JUNK_SCALE_RADIUS: float = 1.8
## Rusty's mood multiplies every offer (rolled each morning), and where his
## chalkboard turns from GRUMPY to so-so to PAYING GOOD.
const RUSTY_MOOD := Vector2(0.8, 1.25)
const RUSTY_MOOD_BANDS: Array[float] = [0.95, 1.1]
## Haggling: the chance it works, what a win adds, and what offending him takes off for good.
const HAGGLE_WIN_CHANCE: float = 0.5
const HAGGLE_WIN: float = 0.3
const HAGGLE_LOSE: float = 0.25
## Used tools on Rusty's rack each day, at least and at most.
const USED_TOOLS_PER_DAY := Vector2i(1, 2)

## Chefty's paint jobs.
const CHEFTY_PAINTS: Dictionary = {
	"paint_classic": Color(0.75, 0.22, 0.15), "paint_mint": Color(0.55, 0.86, 0.72),
	"paint_sunset": Color(0.96, 0.52, 0.24), "paint_pink": Color(0.96, 0.42, 0.7),
	"paint_black": Color(0.12, 0.12, 0.13), "paint_gold": Color(0.9, 0.72, 0.22),
}
## The phone's "Pay a crewmate" buttons, in dollars.
const PAY_CREWMATE_STEPS: Array[int] = [20, 100]
## The most of one consumable a single buy can take (net/shops/shops.gd).
const SHOP_MAX_QTY: int = 25


# ---- cast
## The cast's lines (ui/strings.gd, docs/GAME.md "2026-11-01, the cast").
## A workbook quip (ui/quip_player.gd) waits this long before it can play again.
## Moved from ui/strings.gd; the workbook's cooldown minutes are still open.
const QUIP_COOLDOWN_SECONDS: float = 90.0
## docs/ART.md's budget for one character, in triangles. The plain cartoon body is
## already over it (measured by --cast-test; docs/DECISIONS.md 2026-11-01), so the
## test reports the total and budgets only what an outfit adds.
const CHARACTER_TRIANGLE_BUDGET: int = 5000
## The most triangles the NICE BOYS' outfit (visor, aviators, grin, uniform, props)
## may add over a plain body (player/cartoon_body.gd, net/dev/cast_test.gd).
const CREW_OUTFIT_TRIANGLE_BUDGET: int = 1200


# ---- driving
## The connected town (docs/DECISIONS.md 2026-11-01): the host builds the town map
## when true, and the legacy separate zones when false. --town-map and --legacy-map
## override it. False until the cut-over (driving chunk H).
const TOWN_MAP_DEFAULT: bool = false


# ---- audio
# audio/ (docs/DECISIONS.md, "Audio: buses, a sound bank, positional sounds").

## Sound effects (audio/sfx.gd): the least time between two plays of one sound,
## in milliseconds, unless audio/sound_bank.gd gives it its own; footsteps get longer.
const SFX_DEFAULT_GAP_MS: int = 160
const SFX_STEP_GAP_MS: int = 380
## Each play's pitch lands in this range, as a multiple of normal.
const SFX_PITCH_WOBBLE: Vector2 = Vector2(0.93, 1.07)
## Positional one-shots (Sfx.play_at): full volume inside this many meters, and
## not heard at all past this many, so a bonk on the yard stays on the yard.
const SFX_UNIT_SIZE: float = 8.0
const SFX_MAX_DISTANCE: float = 60.0
## The low-pass on the Music bus (audio/buses.gd) for "heard from another room".
const MUSIC_MUFFLE_CUTOFF_HZ: float = 900.0

## The neighborhood's background (audio/ambience.gd): wind and the old music loop,
## in decibels; the wind drops this much more in transit and at the border.
const AMBIENCE_WIND_DB: float = -14.0
const AMBIENCE_WIND_AWAY_DB: float = -8.0
const AMBIENCE_MUSIC_DB: float = -15.0
## Seconds between one-shots, as a random range; the first bird comes this soon.
const AMBIENCE_BIRD_GAP: Vector2 = Vector2(3.0, 9.0)
const AMBIENCE_FIRST_BIRD: Vector2 = Vector2(1.0, 4.0)
const AMBIENCE_DOG_GAP: Vector2 = Vector2(25.0, 70.0)
const AMBIENCE_CAR_GAP: Vector2 = Vector2(14.0, 35.0)
const AMBIENCE_FIRST_CAR: Vector2 = Vector2(4.0, 35.0)
## Birds sing this far from the listener (meters) and this high up; the dog is this far off.
const AMBIENCE_BIRD_RANGE: Vector2 = Vector2(8.0, 22.0)
const AMBIENCE_BIRD_HEIGHT: Vector2 = Vector2(4.0, 9.0)
const AMBIENCE_DOG_RANGE: Vector2 = Vector2(25.0, 40.0)
## How far along the street a passing car starts and ends, either side of the
## lot, and how long it takes.
const AMBIENCE_CAR_RUN: float = 55.0
const AMBIENCE_CAR_SECONDS: float = 4.0
## One-shots out in the neighborhood: full volume inside this, gone past that (meters).
const AMBIENCE_UNIT_SIZE: float = 12.0
const AMBIENCE_MAX_DISTANCE: float = 90.0

# ---- settings
## Player settings (core/settings.gd, user://settings.cfg; docs/DECISIONS.md
## "Player settings"). Local to each machine, never replicated.
## Radians of turn per pixel of mouse motion at 1.00x sensitivity (the old player.gd value).
const MOUSE_SENSITIVITY_BASE: float = 0.003
## Mouse sensitivity multiplier range (x min, y max) and its default.
const SENSITIVITY_RANGE: Vector2 = Vector2(0.1, 3.0)
## Field of view in degrees; 75 is Godot's Camera3D default, which the game always used.
const FOV_DEFAULT: float = 75.0
const FOV_RANGE: Vector2 = Vector2(60.0, 110.0)
## The root window's content_scale_factor range (UI scale). 125% is the most the
## anchored HUD fits at 1280x720.
const UI_SCALE_RANGE: Vector2 = Vector2(0.75, 1.25)
const RENDER_SCALE_RANGE: Vector2 = Vector2(0.5, 1.0)
const BRIGHTNESS_RANGE: Vector2 = Vector2(0.7, 1.3)
## Frame caps offered, in frames per second; 0 is unlimited. video.max_fps is an index here.
const FPS_CAPS: Array[int] = [0, 30, 60, 120, 144, 240]
## Seconds a new display mode waits for "Keep" before it reverts.
const DISPLAY_REVERT_SECONDS: float = 10.0
## Changes are written this many seconds after the last one, so a dragged slider saves once.
const SETTINGS_SAVE_DELAY: float = 0.4
## Caption size multipliers: small, medium, large (interface.caption_size is an index).
const CAPTION_SCALES: Array[float] = [0.8, 1.0, 1.3]
## Shadow quality levels 0 (off) to 4 (ultra): the directional shadow atlas size,
## the sun's shadow distance in meters, and the soft-shadow filter quality.
## Level 3 (High) is exactly levels/shared_look.gd's sun.
const SHADOW_LEVELS: Array[Dictionary] = [
	{},
	{"atlas": 2048, "distance": 50.0, "soft": 1},
	{"atlas": 4096, "distance": 70.0, "soft": 1},
	{"atlas": 4096, "distance": 90.0, "soft": 2},
	{"atlas": 8192, "distance": 120.0, "soft": 3},
]
## Cosmetic lawn grass levels 0 (off) to 4 (ultra): the share of tufts drawn and
## how far away they fade, in meters. Level 3 (High) is props/grass.gd as built.
## Mowable task grass is gameplay and never thinned.
const GRASS_LEVELS: Array[Dictionary] = [
	{"density": 0.0, "range": 0.0},
	{"density": 0.35, "range": 28.0},
	{"density": 0.65, "range": 36.0},
	{"density": 1.0, "range": 45.0},
	{"density": 1.0, "range": 62.0},
]
## Outline line width in pixels for video.outline 0 (off), 1 (on), 2 (bold).
const OUTLINE_WIDTHS: Array[float] = [0.0, 1.0, 1.6]
## RenderingServer SSAO quality used whenever ambient occlusion is on.
const SSAO_QUALITY_HIGH: int = 2
## The quality presets. Each sets these video keys; changing any one of them
## afterwards turns video.preset to "custom". "high" is the shipped look.
## aa: 0 off, 1 FXAA, 2 MSAA 2x, 3 MSAA 4x (settings:2 may swap Ultra to FXAA
## if MSAA fights the outline shader).
const GRAPHICS_PRESETS: Dictionary = {
	"low": {"shadows": 1, "ssao": false, "glow": false, "outline": 1, "grass": 1, "aa": 0, "render_scale": 0.75},
	"medium": {"shadows": 2, "ssao": false, "glow": true, "outline": 1, "grass": 2, "aa": 1, "render_scale": 1.0},
	"high": {"shadows": 3, "ssao": true, "glow": true, "outline": 1, "grass": 3, "aa": 0, "render_scale": 1.0},
	"ultra": {"shadows": 4, "ssao": true, "glow": true, "outline": 1, "grass": 4, "aa": 3, "render_scale": 1.0},
}
## Actions that are held down rather than tapped. The mouse wheel has no held
## state, so it can never be bound to one of these. A feature adding a held
## action adds it here (gap-specs/critic.md C14, C15).
const HOLD_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"crouch",
	&"primary", &"secondary", &"drop", &"push_to_talk",
]
## Bindings per action (two slots: a main key and an alternate).
const BINDING_SLOTS: int = 2
## How the Keys tab groups actions, in order. Any other non-ui_ action is listed
## under "other" automatically. A feature adding an action may add it to a group here.
const KEYBIND_GROUPS: Array[Dictionary] = [
	{"id": "moving", "actions": [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"crouch"]},
	{"id": "working", "actions": [&"primary", &"secondary", &"interact", &"take", &"drop"]},
	{"id": "crew", "actions": [&"phone", &"push_to_talk", &"toggle_camera", &"toggle_music", &"pause"]},
]

# ---- hotbar
# The pockets (docs/GAME.md, "2026-11-01, the hotbar"; net/components/hotbar.gd,
# player/pockets.gd). Inventory lives on the props themselves (pocketed_by, pocket_slot).

## Pocket slots on keys 1 to 5. Read through Hotbar.capacity(peer), never directly,
## so a future Tool Belt can add some.
const HOTBAR_SLOTS: int = 5
## How each prop kind is carried. "pocket" items go in a slot and come out into
## your hands; "arms" (hugged), "shoulder" and "push" (rolled) fill both hands and
## can't be pocketed. A kind missing here counts as "arms": never pocketable.
## Leaf bags stay out of pockets on purpose, so the wheelbarrow keeps its job.
const ITEM_CARRY: Dictionary = {
	"rake": "pocket", "leaf_blower": "pocket", "hedge_trimmer": "pocket",
	"paint_roller": "pocket", "hose": "pocket", "turf_sign": "pocket", "gas_can": "pocket",
	"leaf_bag": "arms", "gnome": "arms", "trash": "arms",
	"fertilizer_bag": "arms", "rock_salt": "arms", "grass_seed": "arms", "junk": "arms",
	"ladder": "shoulder",
	"lawn_mower": "push", "wheelbarrow": "push", "pressure_washer": "push",
}
## Kinds that stack in one slot, and how many fit. Everything else is one per slot.
const HOTBAR_STACK: Dictionary = {"turf_sign": 5}
## Pocketed things count for this share of their weight when walking.
const POCKET_WEIGHT_SHARE: float = 0.25
## How long drawing an item from a pocket takes to look like (the dip and rise).
const HOTBAR_DRAW_SECONDS: float = 0.22
## How long the item's name stays up over the bar after a switch.
const HOTBAR_NAME_SECONDS: float = 1.6
## After a local slot pick, the owner trusts its own predicted selection over the
## replicated state for this long.
const HOTBAR_PREDICT_SECONDS: float = 0.5
## Emptied pockets (a capture, leaving the yard): items land this far apart (m),
## start this high above the spot (m), and pop up at this speed (m/s), each one
## this share faster than the last, so they land one after another, itemized.
## A height stagger rather than a timed one (docs/DECISIONS.md): everything changes
## hands in the same tick, so nothing is half-owned while it waits its turn.
const CONFISCATE_SPREAD: float = 0.6
const CONFISCATE_DROP_HEIGHT: float = 0.5
const CONFISCATE_POP: float = 2.5
const CONFISCATE_POP_STEP: float = 0.2
## Emptied pockets land at least this far inside the yard's pad (m), unless the
## spot is more than CONFISCATE_NEAR_YARD_METERS from it (the yard moved, or
## that's the store), where they're left where they are.
const CONFISCATE_PAD_INSET: float = 2.0
const CONFISCATE_NEAR_YARD_METERS: float = 200.0
## Steps jangle with at least this many things in your pockets.
const HOTBAR_JANGLE_AT: int = 3
## A pocketed prop's body rides along this high above its owner's feet, out of
## everyone's way (collision off); its look is posed on the body (chunk D).
const POCKET_FOLLOW_HEIGHT: float = 0.9
