class_name Constants
extends RefCounted

## Project-wide constants that are not tuning values. Tuning values live in
## core/balance.gd, which is generated from the design workbook.

## Bump on every build you hand to someone else. Peers on different versions cannot join each other.
const BUILD_VERSION: String = "0.4.16"

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

## Immunity after being let go (director.release_peer's default).
const BORDER_RETURN_IMMUNITY_SECONDS: float = 4.0

## The rake and the homeowner, from Taylan on 2026-10-19 (docs/GAME.md, developer notes).
## TODO(balance): none of these are in the workbook yet.
## One rake per job. Holding it, a stroke pushes at most this much density (times
## RAKE_FIELD_LOAD per 0.5 m lane) across this width: the ground the starter's
## 0.95 m head (RAKE_HEAD_WIDTHS[0]) covers, drifting RAKE_HEAD_DRIFT to either
## side swing to swing. A better rake's wider head is wider on the field by the
## same ratio (leaf_field.gd _stroke_params). rakefeel:field narrowed it from the
## 3.2 m disc that erased a wedge (OQ-R1c).
const RAKE_STRENGTH: float = 72.0
const RAKE_WIDTH: float = 1.2
## A rake stroke every this many seconds while the button is held. RAKE_STROKE_CELLS
## (0.5 m each) is the stroke's reach in the old units: the blower throws its
## leaves (its cells - this) cells beyond the tines (rakefeel:field).
const RAKE_STROKE_SECONDS: float = 0.3
const RAKE_STROKE_CELLS: int = 3
## Raking with bare hands: goofy and barely useful (a strength of 0.8 pushes about
## 10 units a lane a stroke under the windrow rule; the rake pushes up to 864).
const HAND_RAKE_STRENGTH: float = 0.8
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
	# shops:9: seasonal work, done with a sack you bought (SEASONAL_TASKS).
	"fertilize_lawn": "fertilizer_bag", "seed_lawn": "grass_seed", "salt_walk": "rock_salt",
}
## Task id -> what the homeowner pays for it done completely, in dollars.
const TASK_PAY: Dictionary = {
	"pick_litter": 12, "pull_weeds": 15, "mow_lawn": 45, "clean_gutters": 40,
	"wash_windows": 30, "power_wash": 55, "trim_hedges": 35, "paint_fence": 40,
	"clear_roof": 35, "skim_pool": 25,
	# shops:9: each pays about twice its sack's price (SHOP_PRICES), so a sack is
	# worth buying for one job and a part-used one is a head start on the next.
	"fertilize_lawn": 40, "seed_lawn": 32, "salt_walk": 24,
}
## How much of a spot or cell each second of work clears, out of 100.
const TASK_WORK_RATE: Dictionary = {
	"pick_litter": 100.0, "pull_weeds": 40.0, "mow_lawn": 450.0, "clean_gutters": 30.0,
	"wash_windows": 55.0, "power_wash": 90.0, "trim_hedges": 50.0, "paint_fence": 60.0,
	"clear_roof": 35.0, "skim_pool": 50.0,
	# shops:9: one walking pass covers a cell (it sits under the swath ~1 s).
	"fertilize_lawn": 160.0, "seed_lawn": 140.0, "salt_walk": 180.0,
}
## How far from you a tool reaches, in meters.
const TASK_REACH: Dictionary = {
	"pick_litter": 2.0, "pull_weeds": 2.0, "mow_lawn": 0.9, "clean_gutters": 2.6,
	"wash_windows": 40.0, "power_wash": 3.2, "trim_hedges": 2.2, "paint_fence": 2.0,
	"clear_roof": 1.8, "skim_pool": 2.7,
	# shops:9: how far ahead of your feet the throw lands (SACK_SWATH is its radius).
	"fertilize_lawn": 2.2, "seed_lawn": 1.6, "salt_walk": 1.8,
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


# ---- raking: field events (R1 chunk 1)
# The leaf field's stroke events, chunk batches and the raking client's prediction
# ledger (net/leaf_field/leaf_field.gd, net/leaf_field/stroke_event.gd).
## A running mower's mulch is told to everyone as one 'mulch' stroke event at most
## this often (its leaves summed, at the last spot), not one per physics tick. The
## events ride the leaf field's send tick (LeafField.SEND_INTERVAL, asserted >= this)
## so each goes out just ahead of the batch carrying its leaves.
const LEAF_EVENT_MULCH_SECONDS: float = 0.1
## A stroke event's tempo (the rake swing's length in seconds) travels in steps of this.
const LEAF_EVENT_TEMPO_STEP: float = 0.01
## A predicted stroke the host never confirms is dropped (and the field recomposed) after this long.
const LEAF_PREDICT_TIMEOUT: float = 2.0
## At most this many unconfirmed predicted strokes are kept; the oldest goes first.
const LEAF_PREDICT_MAX: int = 6
## A send tick's chunk batch is deflated when its raw bytes are more than this.
const LEAF_BATCH_COMPRESS_BYTES: int = 512


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

# ---- raking: leaf look (R1 chunk 2)
# The leaf view (leaves/leaf_renderer.gd; docs/ART.md "Leaves"): a heightfield
# litter skin that mounds into piles, chunky curled hero leaves riding it, grass
# pressed flat under it, colours from the tree overhead. Cosmetic and local: it
# draws the host's density grid and never writes it.

## Hero leaf length range in meters (each leaf is LeafMeshes' unit leaf scaled).
const LEAF_SIZE := Vector2(0.17, 0.26)
## How far a leaf's tips curl up, in unit-leaf lengths (times r squared).
const LEAF_CURL: float = 0.06
## Light through a leaf from behind (BACKLIGHT share of its albedo).
const LEAF_TRANSLUCENCY: float = 0.45
## Hero leaves per 0.5 m cell: LEAF_HERO_MAX * (density / 255) ^ LEAF_HERO_CURVE,
## rounded up (at least one past the clean line). One on a fresh lawn (the skin
## carries the carpet), two or three in a drift, six on a raked pile. (One per
## 22 units, the first plan, put about 20,000 on a medium yard: twice the
## LEAF_MAX_HEROES_NEAR budget. Seven per pile cell, the spec's eight less one,
## passed on the fresh carpet but not half raked into piles, the worst case
## mid-job: leafcheck measures both.)
const LEAF_HERO_MAX: int = 6
const LEAF_HERO_CURVE: float = 1.6
## Hero leaves draw out to this far (the skin carries the look past it), fading
## over the last LEAF_HERO_FADE meters.
const LEAF_HERO_RANGE: float = 28.0
const LEAF_HERO_FADE: float = 4.0
## A hero leaf's lift above the skin: x for the bottom slot, plus y per slot up.
const LEAF_HERO_LIFT := Vector2(0.004, 0.004)
## How far each slot's leaf may sit from its cell's centre (the top ones nearer).
const LEAF_HERO_SPREAD: float = 0.3
## Where the litter lies, relative to the field's grid_origin (0.05 m above the
## lot floor): a centimetre above the lawn, so it never fights the floor.
const LEAF_GROUND_OFFSET: float = -0.04
## Skin height for a cell's 3x3 [1 2 1]-blurred density b: LEAF_MOUND_BASE *
## min(b, 60) / 60 + LEAF_MOUND_HEIGHT * pow(max(b - 60, 0) / 195, LEAF_MOUND_EXP).
## A raked pile (255) stands about 0.77 m, a drift under a tree about a quarter.
const LEAF_MOUND_BASE: float = 0.015
const LEAF_MOUND_HEIGHT: float = 0.75
const LEAF_MOUND_EXP: float = 1.35
## The mound follows its density on a spring (rad/s, damping ratio): about a
## 10% overshoot, the "puff" as leaves land on a pile.
const LEAF_MOUND_SPRING_W: float = 18.0
const LEAF_MOUND_SPRING_Z: float = 0.6
## Below this density (plus up to 14 of edge noise) the skin is bare lawn.
const LEAF_SKIN_CLEAN: int = 10
## The skin's leaf tiles, in meters (each painted leaf is 1.2-1.9 tiles long).
const LEAF_TILE: float = 0.11
## The skin's leaves cover the lawn fully from this density up (sparser below).
const LEAF_SKIN_FULL: int = 70
## Grass under leaves presses flat between these densities (smoothstep), by up
## to LEAF_GRASS_PRESS_MAX of its height; it springs back over LEAF_GRASS_SPRING
## seconds when the leaves go and presses in LEAF_GRASS_SETTLE when they land.
## (rakefeel:look: a raked strip stays combed flat a while and slowly stands up,
## so the stroke reads as a pressed path, not an eraser's hole.)
const LEAF_GRASS_PRESS := Vector2(8, 45)
const LEAF_GRASS_PRESS_MAX: float = 0.85
const LEAF_GRASS_SPRING: float = 2.5
const LEAF_GRASS_SETTLE: float = 0.1
## Changes no mover claims ease in over this long; each hero leaf the ease adds
## or takes scales in or out over LEAF_FADE_SECONDS (at most LEAF_FADE_MAX at once).
const LEAF_MORPH_SECONDS: float = 0.35
const LEAF_FADE_SECONDS: float = 0.15
const LEAF_FADE_MAX: int = 256
## Hero buffer rebuild time per frame, in ms (chunks with launches or landings
## this frame always rebuild; the rest queue).
const LEAF_REBUILD_BUDGET_MS: float = 1.0
## How far a tree's leaves reach (meters); past every tree a cell takes the
## yard's mix. Shares of hero leaves that are another tree's colour (strays) and
## that are dry and brown.
const LEAF_SOURCE_REACH: float = 9.0
const LEAF_SOURCE_SPREAD: float = 3.5
const LEAF_STRAY_SHARE: float = 0.12
const LEAF_DRY_SHARE: float = 0.15
## Past every tree's pull, at least this much of a cell's look is the yard's
## open-lawn mix (LeafPalette.cell_looks: share = this / the trees' total weight).
const LEAF_OPEN_LAWN_SHARE: float = 0.08
## Each leaf takes the look of a cell up to this many cells away (hero leaves
## and the litter skin alike), so tree colours blend leaf by leaf.
const LEAF_LOOK_JITTER_CELLS: float = 1.6
## A leaf's brightness, times its palette colour (random in this range).
const LEAF_VALUE_JITTER := Vector2(0.88, 1.10)
## Leaf age (0 fresh .. 1 dry brown) by season, autumn, winter, spring, summer:
## the range fresh leaves fall in (the skin uses it as is).
const LEAF_SEASON_AGES: Array[Vector2] = [Vector2(0.0, 0.35), Vector2(0.8, 1.0), Vector2(0.0, 0.3), Vector2(0.0, 0.2)]
## An autumn dry leaf's age; spring hero leaves' age (x fresh, y dry).
const LEAF_DRY_AGE: float = 0.6
const LEAF_SPRING_AGES := Vector2(0.1, 0.4)
## Spring: share of a blossoming tree's leaves that are petals, and a petal's
## size (of a leaf). Summer: share of yellow among the greens.
const LEAF_PETAL_SHARE: float = 0.1
const LEAF_PETAL_SCALE: float = 0.5
const LEAF_SUMMER_YELLOW_SHARE: float = 0.2
## A willow leaf is an oval this narrow (of its length).
const LEAF_WILLOW_WIDTH: float = 0.42
## Share of hero leaves lying loose (lift in a gust; looseness in
## LEAF_LOOSE_RANGE); the rest have looseness 0 .. LEAF_SETTLED_LOOSE_MAX.
const LEAF_LOOSE_SHARE: float = 0.3
const LEAF_LOOSE_RANGE := Vector2(0.65, 1.0)
const LEAF_SETTLED_LOOSE_MAX: float = 0.5
## A leaf that leaves or arrives without a hero slot of its own (the skin) sits
## within this share of a cell's size of its centre, so always inside the cell.
const LEAF_SKIN_POINT_SPREAD: float = 0.45
## Leaf colours by crown (props/trees.gd CROWNS): [centre, rim]. The rest are
## what seasons turn fallen leaves into. No olive: it read as dead grass.
const LEAF_PALETTES: Dictionary = {
	"orange": [Color(0.96, 0.66, 0.20), Color(0.82, 0.30, 0.10)],
	"red": [Color(0.90, 0.36, 0.15), Color(0.58, 0.11, 0.10)],
	"yellow": [Color(0.96, 0.82, 0.30), Color(0.88, 0.56, 0.12)],
	"rust": [Color(0.84, 0.48, 0.18), Color(0.52, 0.22, 0.10)],
	"turning": [Color(0.80, 0.74, 0.26), Color(0.92, 0.52, 0.18)],
	"last_year": [Color(0.64, 0.59, 0.51), Color(0.48, 0.43, 0.37)],
	"green": [Color(0.42, 0.62, 0.24), Color(0.30, 0.48, 0.16)],
	"deep_green": [Color(0.28, 0.48, 0.18), Color(0.18, 0.34, 0.12)],
	"blossom_pink": [Color(0.99, 0.80, 0.86), Color(0.94, 0.60, 0.72)],
	"blossom_white": [Color(0.99, 0.98, 0.94), Color(0.92, 0.90, 0.80)],
}
## Most triangles per leaf species (maple, oak, oval); tools/leaf_look_check.gd.
const LEAF_MESH_MAX_TRIS: Array[int] = [46, 44, 34]
## Leaf budgets on a medium yard: triangles drawn, draw calls, GPU time (ms).
const LEAF_MAX_TRIS_VISIBLE: int = 450000
const LEAF_MAX_DRAWS: int = 60
const LEAF_GPU_MS: float = 1.0
## Hero leaves draw one MultiMesh per species per block of this many chunks a
## side (2: nine blocks on a lot), which keeps the leaf draw calls in LEAF_MAX_DRAWS.
const LEAF_HERO_BLOCK_CHUNKS: int = 2
## Hero leaves within LEAF_HERO_RANGE of one camera, at most (leafcheck).
const LEAF_MAX_HEROES_NEAR: int = 9000
## The leaf budgets are a medium yard's; a big yard (more trees, more leaves) may use this many times them.
const LEAF_BIG_YARD_BUDGET: float = 1.5
## Neighbour yards' autumn leaf patches (levels/town/season_dressing.gd): leaves
## per patch, how far a patch reaches (meters) and how much a leaf tilts (radians).
const LEAF_NEIGHBOR_PATCH_LEAVES: int = 26
const LEAF_NEIGHBOR_PATCH_REACH: float = 1.7
const LEAF_NEIGHBOR_TILT: float = 0.2

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
		# Where the hat rack, the shirt cubby and the paint counter's customers stand
		# (shops chunk 7, levels/dressing/wardrobe.gd): you buy there like at the counter.
		"spots": [
			Vector3(WARDROBE_WALL_X + WARDROBE_SPOT_OUT, 0.0, HAT_RACK_Z),
			Vector3(WARDROBE_WALL_X + WARDROBE_SPOT_OUT, 0.0, SHIRT_CUBBY_Z),
			PAINT_COUNTER_AT - Vector3(0.0, 0.0, PAINT_COUNTER_SPOT_BACK),
		],

		# The walk-in lobby (art chunk 8): its tool endcaps sell from inside it too.
		"lobby": Rect2(-20.0, -7.0, 10.0, 10.0),
	},
	"rustys": {
		"zone": "StoreZone", "counter": Vector3(15.2, 0.0, -4.5), "keeper": Vector3(16.4, 0.0, -4.5),
		"yaw": -PI / 2.0, "area": Rect2(12.5, -8.0, 7.5, 12.0),
		# The scale stands well off the counter, so E at the counter never grabs the junk on it.
		"scale": Vector3(14.4, 0.0, 0.5), "rack": Vector3(18.6, 0.0, 0.5),
	},
	"lunch_money": {
		"zone": "StoreZone", "truck": Vector3(3.0, 0.0, 15.6), "counter": Vector3(5.2, 0.0, 15.4),
		# Dot stands in the truck (props/vehicles.gd build_food_truck), on a sunk floor so the hatch frames her.
		"keeper": Vector3(3.55, 0.32, 15.65), "yaw": 0.0, "area": Rect2(4.2, 14.0, 2.4, 3.0),
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
	# Upgrades. The first two match Balance.BASELINE_TIER_1_TOOL_COST. Since p2-kit
	# rake_tier_1 and rake_tier_2 are rakes you buy (the Mk II and Mk III), next to
	# the plain rake ($50 buys one with change for bags) and Rusty's bent one.
	"rake_tier_1": 120, "wheelbarrow_tier_1": 120, "rake_tier_2": 1200,
	"rake": 25, "rake_used": 12,
	# Gear (driving G1): the Gutter Shredder, Marty's nephew's old board.
	"skateboard": 60,
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
	# Chefty's gear and Marty's Body Shop (driving chunk C3): the Chefty Net, and a
	# repair, priced per dent (a repair buys as many as Chefty has).
	"chefty_net": 120, "chefty_repair": 25,
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
## No contractor bags in them: those scoop wider, and the older tests measure
## piles with plain lawn bags.
const TEST_STARTER_SUPPLIES: Dictionary = {
	"lawn_bags": 9999, "big_bags": 0, "gas": 9999.0, "fertilizer": 9999, "grass_seed": 9999, "rock_salt": 9999,
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
## Chefty's junk slots, and how far from the scale's middle (each way, along its
## sides) a piece's base may lie and count as on it: half its platform (1.24 m).
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
const JUNK_SCALE_HALF: float = 0.62
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


# ---- nice boys: stage (R2 chunk 1)
## The beat clock (net/run_events/beat.gd): a staged moment without its own
## anticipation is sent this far ahead of now, so every peer plays it on time;
## one that arrives later than BEAT_SKIP is snapped to its end pose, silently.
const BEAT_LEAD: float = 0.15
const BEAT_SKIP: float = 0.5
## StageCam (player/stage_cam.gd): the blend in and out when a shot names none,
## in seconds.
const STAGE_BLEND_DEFAULT: float = 0.35
## A staged body (player/stage_body.gd) moving more than this in one physics
## tick is a pop; the probe counts them.
const STAGE_MAX_STEP_METERS: float = 0.5
## Released, another peer's view of a staged body eases back onto the network
## pose over this long, which still trails the owner by the link's delay.
const STAGE_RELEASE_BLEND: float = 0.3
## What each control lock (player.set_control_lock) still lets through. Held
## back otherwise: moving, jump, sprint, crouch, the pockets, interact, primary,
## secondary, drop and take. look_deg limits how far you can turn from where the
## lock started (only when no stage shot has the view; a shot clamps its own).
const STAGE_LOCK_ALLOW: Dictionary = {
	&"nice_cite": {"jump": true, "look": true, "look_deg": 40.0},
	&"escort": {"look": true},
	&"van_seat": {"primary": true, "look": true},
	&"stage_walk": {"look": true},
	&"annex_closing": {},
}
## The iris (ui/iris.gd): closing and opening seconds, and the shortest it stays
## shut, so a cut behind it is never a flicker.
const IRIS_CLOSE: float = 0.35
const IRIS_OPEN: float = 0.35
const IRIS_HOLD_MIN: float = 0.4
## The caption stack (ui/caption_stack.gd) shows at most this many lines at once.
const CAPTION_STACK_MAX: int = 3
## A teammate this close (with a line of sight) saw the catch and needs no line
## about it (ui/quip_player.gd).
const TEAMMATE_SEEN_METERS: float = 25.0
## balance:E0, pulled forward by R2 (core/economy.gd run_roll_chance): the raid
## formula's chance is per lot of about this many minutes, spread over the
## director's HEAT_ROLL_SECONDS rolls.
const RAID_LOT_MINUTES: float = 8.0


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
## cast:2, the lines in the game. How often a homeowner with a personality speaks
## from their own pool (Strings.PERSONALITY_LINES) instead of the generic mood one.
const HOMEOWNER_PERSONALITY_LINE_CHANCE: float = 0.65
## When the crew owes the homeowner only for water, how often they mention it
## (Strings.HOMEOWNER_LINES.bill_water).
const HOMEOWNER_WATER_LINE_CHANCE: float = 0.5
## How often TurfMasters™ text a taunt after poaching a client, and a complaint
## when one of their signs is pulled (net/town/town.gd).
const RIVAL_TAUNT_CHANCE: float = 0.5
const RIVAL_SIGN_TEXT_CHANCE: float = 0.35
## How long a shopkeeper's caption stays over their head (npcs/store_clerk.gd).
const CLERK_CAPTION_SECONDS: float = 4.0
## Before this hour, a shopkeeper's first greet of the day is a "morning" line.
const CLERK_MORNING_UNTIL_HOUR: float = 12.0
## How often a homeowner the crew owes for breakage brings the bill up first
## (npcs/homeowner.gd choose_pool; it was an inline 0.7).
const HOMEOWNER_BILL_LINE_CHANCE: float = 0.7
## How long the homeowner's goodbye (HOMEOWNER_LINES.paid) stays up after the cash
## is grabbed. Longer than the old "Thanks!", so it can be read.
const HOMEOWNER_PAID_CAPTION_SECONDS: float = 3.5


# ---- nice boys: crew and the catch (R2 chunk 2)
## npcs/crew_member.gd, npcs/crew_brain.gd, net/run_events/encounter.gd and the
## director (docs/GAME.md "The NICE BOYS encounter (R2)"). TODO(balance): none of
## these are in the workbook.
## Steering: how fast a NICE BOY speeds up, slows down (m/s per second) and turns
## (rad/s). No one-frame about-faces.
const CREW_ACCEL: float = 9.0
const CREW_DECEL: float = 14.0
const CREW_TURN_RATE: float = 6.5
## Walking speeds by what he's doing (m/s). Players sprint at 8: the crew wins by
## spreading out and listening, not by running anyone down.
const CREW_SPEED_PATROL: float = 2.8
const CREW_SPEED_SEARCH: float = 3.2
const CREW_SPEED_CHASE: float = 5.5
const CREW_SPEED_ESCORT: float = 3.2
const CREW_SPEED_RECALL: float = 5.5
## An escort that has taken this long (s) speeds up to CREW_SPEED_ESCORT_LATE.
const CREW_ESCORT_MAX: float = 14.0
const CREW_SPEED_ESCORT_LATE: float = 4.0
## Senses: a cone (degrees, meters, to the chest), an all-round near sense, and
## hearing a running tool within CREW_HEAR_METERS.
const CREW_VIEW_DEG: float = 110.0
const CREW_VIEW_RANGE: float = 26.0
const CREW_NEAR_SENSE: float = 3.0
const CREW_HEAR_METERS: float = 16.0
## A tool that ran within this long (s) still gives its user away.
const CREW_HEAR_FRESH_SECONDS: float = 0.75
## For the first CREW_NOISE_SEEK_SECONDS of a chase, unspotted crew walk to the noise.
const CREW_NOISE_SEEK_SECONDS: float = 10.0
## Patrol re-picks a point every CREW_PATROL_REPICK s within CREW_PATROL_RADIUS m
## of a lot player, by sector (crew index -> front yard, left, right).
const CREW_PATROL_REPICK: float = 6.0
const CREW_PATROL_RADIUS: float = 6.0
## Spotted: he freezes this long (head snap, whistle, point, bark) before the chase.
const CREW_SPOT_FREEZE: float = 0.6
## The lunge: within range and inside the front cone (degrees) he winds up for
## CREW_LUNGE_WINDUP s, stretched by up to CREW_LUNGE_WINDUP_LAG_MAX for the
## target's half round trip, then covers CREW_LUNGE_DISTANCE m in CREW_LUNGE_SECONDS.
const CREW_LUNGE_RANGE: float = 2.6
const CREW_LUNGE_CONE_DEG: float = 60.0
const CREW_LUNGE_WINDUP: float = 0.4
const CREW_LUNGE_WINDUP_LAG_MAX: float = 0.15
const CREW_LUNGE_DISTANCE: float = 2.2
const CREW_LUNGE_SECONDS: float = 0.25
## Every peer eases him into the wind-up's spot over this long (s): a client drew
## him a little behind the host, and that gap closes during the crouch.
const CREW_WINDUP_BLEND: float = 0.3
## Of the lunge's reach, this much is his arm (m): his body travels the rest, at
## most, and never closer than arm's length to where you stood.
const CREW_LUNGE_ARM: float = 0.75
## The host's verdict at contact: the target's chest within reach plus slack of
## the hand's path as every peer draws it (from his start to from + dir x (body
## travel + CREW_LUNGE_ARM), up 1.2), in the host's view.
const CREW_GRAB_REACH: float = 0.95
const CREW_GRAB_SLACK: float = 0.35
## A found hider is grabbed this long (s) after the inspection says so (no lunge):
## once the reveal and the pull out have set them on their feet (R2b hide).
const CREW_FOUND_CONTACT: float = HIDE_FOUND_REVEAL + HIDE_PULL_SECONDS + HIDE_FOUND_SETTLE
## A whiff: he sprawls this long, and the target can't be grabbed for the grace.
const CREW_WHIFF_SECONDS: float = 0.9
const CREW_WHIFF_GRACE: float = 1.0
## Nobody seen and nothing inspected for this long (s): they give up and pack up.
const CREW_GIVE_UP_UNSEEN: float = 30.0
## A thrown thing that lands this close (m) without hitting him: he walks over and
## peers at it for CREW_INVESTIGATE_SECONDS.
const CREW_INVESTIGATE_RADIUS: float = 4.0
const CREW_INVESTIGATE_SECONDS: float = 4.0
## Hop out of / into the van (the fallback when no Shuttle drives it): one NICE BOY
## every CREW_HOP_GAP s, CREW_HOP_SECONDS each, from the seat to the curb.
const CREW_HOP_GAP: float = 0.5
const CREW_HOP_SECONDS: float = 1.15
## Seats in the cast:5 van (props/nice_van.gd VanLook space: x right, -z the nose,
## floor at y 1.0) for the fallback without chunk 4's CrewSeats markers: the
## driver, then the left bench and the back bench. [position, yaw].
const CREW_VAN_SEATS: Array = [
	[Vector3(-0.5, 0.95, -1.98), 0.0],
	[Vector3(-0.78, 1.0, 0.75), -PI * 0.5],
	[Vector3(-0.78, 1.0, 1.85), -PI * 0.5],
	[Vector3(0.45, 1.0, 2.52), 0.0],
]
## Where a NICE BOY steps out: the sill of the open side, then the curb beside it.
const CREW_VAN_SILL_X: float = 1.12
const CREW_VAN_CURB_X: float = 2.0
## The gotcha, from the moment his hand lands (s): the hit-stop, the camera's
## ease into the two-shot, the held grin, the bark, then the cite.
const CATCH_HITSTOP: float = 0.12
const CATCH_CAM_BLEND: float = 0.6
const CATCH_HOLD_END: float = 0.95
const CATCH_BARK_AT: float = 0.95
const CATCH_CITE_AT: float = 1.0
const CATCH_CITE_SECONDS: float = 2.0
## The two-shot: low, side-on, this far from the pair (m), looking at this height
## between them (m; the eye sits CATCH_CAM_EYE_DROP lower), pushing in by this share.
const CATCH_CAM_DISTANCE: float = 3.0
const CATCH_CAM_HEIGHT: float = 1.38
const CATCH_PUSH_IN: float = 0.03
## Its field of view (degrees): tighter than the player's, so the two faces fill it.
const CATCH_CAM_FOV: float = 40.0
## Mashing jump during the cite: each press buys this much (s), up to the max, at
## most this many presses a second.
const CATCH_WRIGGLE_ADD: float = 0.15
const CATCH_WRIGGLE_MAX: float = 1.5
const CATCH_WRIGGLE_RATE: float = 8.0
## The itemized row: one item every CATCH_ITEM_GAP s, CATCH_ROW_SPACING m apart.
const CATCH_ITEM_GAP: float = 0.12
const CATCH_ROW_SPACING: float = 0.6
## Each one arcs out of your hands onto its spot in this long (s).
const CATCH_ITEM_FLIGHT: float = 0.42
## From the end of the cite to the arm link and the stroll to the van (s).
const CATCH_ESCORT_AFTER: float = 0.6
## The escorted player walks arm in arm on his right, in his own space (x right, +z ahead).
const ESCORT_SIDE_OFFSET := Vector3(-0.62, 0.0, 0.0)
## Stepping to his side for the arm link (and off it at the van door), in seconds.
const ESCORT_LINK_BLEND: float = 0.55
## The follow shot during the escort: behind and above (m), orbit (degrees).
const ESCORT_CAM_BACK: float = 4.0
const ESCORT_CAM_UP: float = 2.2
const ESCORT_CAM_ORBIT_DEG: float = 40.0
## How fast the follow shot turns to where the pair walks (rad/s).
const ESCORT_CAM_TURN: float = 1.4
## A friend's bonk during the cite or the escort: he's stunned this long, and the
## freed player can't be grabbed for RESCUE_IMMUNITY s.
const RESCUE_STUN: float = 2.5
const RESCUE_IMMUNITY: float = 5.0
## The van waits VAN_HOLD_SECONDS after the first rider is seated (never past
## VAN_HOLD_MAX), longer only while an escort is walking in; the crew then has
## CREW_RECALL_MAX s to climb back in before it goes.
const VAN_HOLD_SECONDS: float = 12.0
const VAN_HOLD_MAX: float = 20.0
const CREW_RECALL_MAX: float = 8.0
## After a raid nobody was caught in, the heat drops to this (not HEAT_AFTER_RAID).
const HEAT_AFTER_EVADED: float = 35.0
## XP for freeing a friend (bonk, unbuckle, co-sign).
const XP_RESCUE: int = 25
## Heat's per-player noise memory (s): where each one's tool last ran.
const HEAT_NOISE_WINDOW: float = 30.0
## Name tags: a fixed on-screen size (pixel_size, at most CREW_TAG_MAX_PX), faded
## out closer than CREW_TAG_FADE_NEAR m and farther than CREW_TAG_FADE_FAR m.
const CREW_TAG_PIXEL_SIZE: float = 0.0009
const CREW_TAG_MAX_PX: float = 0.0014
const CREW_TAG_FADE_NEAR: float = 1.4
const CREW_TAG_FADE_FAR: float = 22.0
## Barks: one NICE BOY speaks at most every CREW_BARK_MIN_GAP s, not before
## CREW_BARK_FIRST_DELAY s after he spawns; the line hangs over him for
## CREW_BARK_SECONDS, and the subtitle reaches players within CREW_BARK_HEAR_METERS.
const CREW_BARK_MIN_GAP: float = 3.5
const CREW_BARK_FIRST_DELAY: float = 1.0
const CREW_BARK_SECONDS: float = 2.2
const CREW_BARK_HEAR_METERS: float = 28.0
## The line over his head: a fixed on-screen size (pixel_size).
const CREW_BARK_PIXEL_SIZE: float = 0.0012
## Sound gaps (ms, audio/sound_bank.gd): several NICE BOYS' steps overlap, and the
## itemized row pops every CATCH_ITEM_GAP.
const CREW_STEP_GAP_MS: int = 70
const ITEMIZE_POP_GAP_MS: int = 40
## A NICE BOY's stride (m per footstep sound) and how much louder (dB) his steps get
## than a player's: heavy cartoon sneakers.
const CREW_STRIDE_METERS: float = 0.85
## The bark's pitch range per NICE BOY (each one keeps his own voice).
const CREW_VOICE_PITCH := Vector2(0.92, 1.12)
## The brain (npcs/crew_brain.gd): out of sight this long (s), a chased player is
## lost; close enough to a waypoint (m) to pick the next; patrol points stay this
## far inside the lot's edge (m), within CREW_PATROL_SECTOR_SPREAD m of his sector
## (by crew index: the front yard, the left, the right, lot space).
const CREW_LOST_AFTER: float = 0.8
const CREW_WAYPOINT_REACHED: float = 1.5
const CREW_PATROL_HALF_EXTENT: float = 16.0
const CREW_PATROL_SECTORS: Array[Vector3] = [Vector3(0.0, 0.0, 9.0), Vector3(-10.0, 0.0, -2.0), Vector3(10.0, 0.0, -2.0)]
const CREW_PATROL_SECTOR_SPREAD: float = 6.0
## After an investigation he goes back to searching if he saw someone within this
## long (s), else to patrol; a search bark comes with this share of new waypoints.
const CREW_SEARCH_MEMORY: float = 20.0
const CREW_SEARCH_BARK_CHANCE: float = 0.3
## Hearing a tool counts as this much farther (m) than seeing someone, picking
## whom to go for.
const CREW_HEARD_PENALTY: float = 5.0
## The gotcha (net/run_events/encounter.gd), from the hand landing (s): he swaps the
## grab for the held grin; he stands this far from you (m), hand on your shoulder;
## the sticker slaps on this long after the page tears (s).
const CATCH_GRIN_AT: float = 0.45
const CATCH_GOTCHA_GAP: float = 1.05
const CATCH_SLAP_AFTER: float = 0.35
## The music dips this far (dB) under your own gotcha.
const CATCH_MUSIC_DUCK_DB: float = -14.0
## Close enough to the van door (m) to hand you over; he goes back to the chase
## this long (s) after.
const CATCH_DOOR_REACH: float = 1.1
const CATCH_DOOR_HANDOFF_SECONDS: float = 1.2
## An escort still walking this long (s) past CREW_ESCORT_MAX (pinned on a fence,
## off the navmesh) gives up walking: you're handed to the door from where you are.
const CREW_ESCORT_GIVE_UP: float = 10.0
## The director: the first hop-out this long (s) after the chase starts; a NICE BOY
## this close to the door (m) climbs in; without a Shuttle the recall gets this many
## times CREW_RECALL_MAX (the old van's door is a longer walk); the fallback van is
## gone once it's this far from where it parked (m).
const CREW_HOP_FIRST_DELAY: float = 0.3
const CREW_BOARD_REACH: float = 1.0
const CREW_RECALL_FALLBACK_SCALE: float = 2.0
const VAN_GONE_METERS: float = 90.0


# ---- driving
## The connected town (docs/DECISIONS.md 2026-11-01): the host builds the town map
## when true, and the legacy separate zones when false. --town-map and --legacy-map
## override it. False until the cut-over (driving chunk H).
const TOWN_MAP_DEFAULT: bool = false
## Homie Depot's lot in the connected town, in world x and z (the store sits at the
## origin): inside it a player counts as at the store (driving chunk D), and its
## STORE_LAYOUT reservations below live in the same space.
const STORE_AREA := Rect2(-24.0, -24.0, 48.0, 48.0)
## Town dressing (levels/town/town_dressing.gd): small things stop drawing past
## these distances, in meters.
const TOWN_LAMP_VISIBLE_METERS: float = 220.0
const TOWN_SMALL_VISIBLE_METERS: float = 120.0
## Street lamps along every town street, one every this many meters, alternating sides.
const TOWN_LAMP_SPACING: float = 36.0
## People out walking on each town street's sidewalks.
const TOWN_PEDESTRIANS_PER_STREET: int = 3
## Country trees scattered on the open land between the store and the streets.
const TOWN_COUNTRY_TREES: int = 90
## The town's grass runs this many meters past TOWN_BOUNDS on every side (only
## up to the border's own ground on the +Z side).
const TOWN_GROUND_MARGIN: float = 250.0

## Homie Depot's lot, reserved by whoever builds there (gap-specs/critic.md C28), in
## StoreZone space (x, z), so shops, art and driving never stack two things on one
## spot. SHOP_SITES above stays the shops' own source of counters and buy areas;
## each shop's reservation here covers its SHOP_SITES area and counter (the
## garden center's and Rusty's are that area itself), and the townmap test
## checks both, that no two reservations overlap, and that the store's fixed
## pieces (levels/dressing/store_dressing.gd's cars, lamps, tree islands and
## cart corral, and the job board) sit inside "store" reservations and clear of
## everyone else's. "at" and "yaw" place the thing; rects with no "at" are
## keep-clear zones. Owners: store (the base dressing), shops, art, driving.
const STORE_LAYOUT: Dictionary = {
	"building": {"owner": "store", "rect": Rect2(-34.0, -19.0, 14.0, 34.0)},
	"lobby": {"owner": "art", "rect": Rect2(-20.0, -19.0, 8.0, 34.0)},
	"checkout": {"owner": "store", "rect": Rect2(-2.5, -10.6, 5.0, 4.2)},
	"job_board": {"owner": "store", "rect": Rect2(-6.0, -9.1, 2.8, 1.0)},
	"lot_gate": {"owner": "store", "rect": Rect2(-2.0, -18.0, 4.0, 4.0)},
	"crew_camp": {"owner": "store", "rect": Rect2(-9.2, -16.8, 2.4, 6.6)},
	# The delivery pallet's cage, and in front of it where ordered tools land
	# (shops chunk 8, DELIVERY_KIT_*).
	"back_room": {"owner": "shops", "rect": Rect2(-11.6, -19.4, 4.1, 2.5)},
	"snak_o_matic": {"owner": "shops", "rect": Rect2(-12.0, 3.0, 3.0, 3.0)},
	"garden_center": {"owner": "shops", "rect": SHOP_SITES["homie_depot"]["area"]},
	"rustys": {"owner": "shops", "rect": SHOP_SITES["rustys"]["area"]},
	"lunch_money": {"owner": "shops", "rect": Rect2(0.6, 13.5, 6.4, 4.5)},
	# Last session's unsold junk, back in a grid by the TruckPad (Constants.JUNK_LEFT_*).
	"junk_drop": {"owner": "shops", "rect": Rect2(3.9, 4.6, 3.8, 4.6)},
	# Workwear on the entrance's south wall, and Chefty's paint by the loading bay
	# (shops chunk 7, levels/dressing/wardrobe.gd; WARDROBE_*, PAINT_COUNTER_AT).
	"wardrobe": {"owner": "shops", "rect": Rect2(-12.0, -10.5, 0.6, 3.5)},
	"paint_counter": {"owner": "shops", "rect": Rect2(8.6, 2.1, 2.8, 1.2)},
	"spawns": {"owner": "store", "rect": Rect2(-1.5, 4.5, 5.0, 3.0)},
	"cart_corral": {"owner": "store", "rect": Rect2(-8.4, 7.6, 1.8, 4.8)},
	# Three parked cars, a lamp and a tree island.
	"parking_west": {"owner": "store", "rect": Rect2(-11.6, 13.0, 12.0, 7.2)},
	"lamp_lunch": {"owner": "store", "rect": Rect2(7.4, 16.6, 0.8, 0.8)},
	# The corner tree islands, each with a lamp at its inner corner.
	"corner_ne": {"owner": "store", "rect": Rect2(16.6, 16.6, 3.6, 3.6)},
	"corner_se": {"owner": "store", "rect": Rect2(16.6, -20.2, 3.6, 3.6)},
	"truck_pad": {"owner": "driving", "rect": Rect2(7.9, 4.4, 4.2, 7.2)},
	# Chefty's way out to the road: nothing may stand here.
	"chefty_exit": {"owner": "driving", "rect": Rect2(12.2, 4.4, 8.3, 7.4)},
	# Marty's ramp (driving G1): in the open middle of the lot, rising toward +X, with
	# about 5 m of run-up from the store's walk and 8 m of open lot to land in before
	# Rusty's fence
	# (it used to launch you into the corner tree island).
	"marty_ramp": {"owner": "driving", "rect": Rect2(-4.2, -3.3, 3.6, 3.6), "at": Vector3(-2.4, 0.0, -1.5), "yaw": 0.0},
	"depot_safe_sign": {"owner": "driving", "rect": Rect2(18.6, 12.4, 1.6, 1.4), "at": Vector3(19.4, 0.0, 13.1), "yaw": PI * 0.5},
	"mulch_bin": {"owner": "driving", "rect": Rect2(4.9, 9.4, 2.6, 2.6), "at": Vector3(6.2, 0.0, 10.7), "yaw": 0.0},
	"pylon": {"owner": "art", "rect": Rect2(18.0, -14.5, 2.0, 2.0), "at": Vector3(19.0, 0.0, -13.5), "yaw": PI * 0.5},
	# Faces the lot (+X), its back to the store wall.
	"propane_cage": {"owner": "art", "rect": Rect2(-9.6, -9.8, 2.0, 2.6), "at": Vector3(-8.6, 0.0, -8.5), "yaw": -PI * 0.5},
	# The walk-in lobby's front (art chunk 8): the orange entrance block the doors
	# are in, its canopy on two posts, and the bollards before the sidelights.
	"store_entrance": {"owner": "art", "rect": Rect2(-12.0, -7.0, 4.8, 10.0)},
	# Mulch, soil and the season's pallets beside the garden center.
	"garden_yard": {"owner": "art", "rect": Rect2(3.0, -19.6, 5.2, 4.6)},
	# The season's stock along the store front (pumpkins and hay, the holiday-tree
	# lot and SNOW-B-GONE, flower flats, kiddie pools and grills).
	"seasonal_display": {"owner": "art", "rect": Rect2(-12.0, 6.4, 2.8, 6.4)},
	"cart_corral_east": {"owner": "art", "rect": Rect2(8.6, -6.0, 1.8, 4.8), "at": Vector3(9.5, 0.0, -3.6), "yaw": 0.0},
	# p2-kit: the crew's kit waits here, beside the entrance (KIT_DOOR_*).
	"kit_door": {"owner": "shops", "rect": Rect2(-7.1, -0.3, 1.8, 6.2)},
}

# ---- driving: Chefty (driving chunk C1, net/components/chefty_drive.gd and
# vehicle_sim.gd; docs/DECISIONS.md "Chefty is a host-simulated arcade vehicle").
# First guesses, tuned by driving it. TODO(balance): not in the workbook.
## Physics layer 5 (bit value 16): vehicle chassis. A chassis masks the world (1)
## and other chassis (16); players never touch it, they bump the rendered truck.
const VEHICLE_LAYER: int = 16
## Where Chefty waits in the connected town: on the TruckPad, nose to the road (+X).
const CHEFTY_PARK_SPOT := Vector3(10.0, 0.0, 8.0)
const CHEFTY_PARK_YAW: float = -PI * 0.5
## Speeds in m/s, rates in m/s^2. Reverse is capped at its own speed.
const CHEFTY_TOP_SPEED: float = 19.0
const CHEFTY_REVERSE_SPEED: float = 6.0
const CHEFTY_ACCEL: float = 6.5
const CHEFTY_BRAKE: float = 14.0
## Slowing with no throttle (m/s^2), and drag that grows with speed squared.
const CHEFTY_COAST_DRAG: float = 1.2
const CHEFTY_AIR_DRAG: float = 0.012
## The handbrake slows the wheels this hard (m/s^2) and lets the tail out.
const CHEFTY_HANDBRAKE_DECEL: float = 4.0
## Steering: radians per second of turn at full lock, reached from this speed up;
## at top speed only this share of it is left, so it can't spin on a dime at 19.
const CHEFTY_STEER_RATE: float = 1.9
const CHEFTY_STEER_FULL_AT: float = 4.0
const CHEFTY_STEER_HIGH_SPEED_SHARE: float = 0.45
## How fast the turn rate follows the wheel (rad/s^2), and the handbrake's extra bite.
const CHEFTY_YAW_RESPONSE: float = 9.0
const CHEFTY_DRIFT_STEER_SHARE: float = 1.35
## Sideways grip: how fast a slide dies away, per second (gripping, drifting).
const CHEFTY_GRIP: float = 9.0
const CHEFTY_DRIFT_GRIP: float = 1.6
## Suspension: wheel radius over the ground, how far below a hub a ray looks for
## ground, how fast the body settles onto it, and gravity with no ground (m/s^2).
const CHEFTY_RIDE_HEIGHT: float = 0.46
const CHEFTY_SUSPENSION_RAY: float = 1.2
const CHEFTY_SUSPENSION_RATE: float = 14.0
const CHEFTY_GRAVITY: float = 18.0
## The hub positions of the four wheels in Chefty's own space (x, z).
const CHEFTY_WHEELS: Array[Vector2] = [Vector2(-1.08, -1.85), Vector2(1.08, -1.85), Vector2(-1.08, 1.85), Vector2(1.08, 1.85)]
## The chassis box (what hits walls): its size and its center over the ground.
const CHEFTY_CHASSIS_SIZE := Vector3(2.2, 1.5, 5.8)
const CHEFTY_CHASSIS_CENTER := Vector3(0.0, 1.2, -0.1)
## How much the body leans with the throttle and in turns (radians per m/s^2).
const CHEFTY_LEAN_PITCH: float = 0.006
const CHEFTY_LEAN_ROLL: float = 0.008
const CHEFTY_LEAN_MAX: float = 0.09
## The steering wheel turns this far at full lock (radians).
const CHEFTY_WHEEL_TURN: float = 2.2
## perk:chefty_tuneup (Hedge Hog IV) raises the top speed by this share; each dent
## takes this share off it.
const CHEFTY_TUNEUP_SHARE: float = 1.08
const CHEFTY_DENT_SPEED_SHARE: float = 0.03
const CHEFTY_MAX_DENTS: int = 3
## Bumping something soft (a prop, a crew member) keeps this share of the speed,
## and the chassis ignores it for this long, so it never stops dead on a gnome.
const CHEFTY_SOFT_HIT_KEEP: float = 0.9
const CHEFTY_SOFT_HIT_SECONDS: float = 0.3
## Seats: the driver, shotgun, and six in the bed (two across, three deep).
const CHEFTY_SEATS: int = 8
## Getting in: how close to the door or tailgate (m), and the driver's seat only
## while Chefty is slower than this (m/s). Getting out: a normal exit under this
## speed, a bail (flung out with this share of Chefty's velocity) above it.
const CHEFTY_ENTER_RADIUS: float = 3.0
const CHEFTY_ENTER_MAX_SPEED: float = 3.0
const CHEFTY_EXIT_MAX_SPEED: float = 4.0
const CHEFTY_BAIL_SHARE: float = 0.6
const CHEFTY_SEAT_SWAP_MAX_SPEED: float = 3.0
## Netcode (docs/NETCODE.md, "Rides"): the host holds the driver's last input this
## long before it brakes; pose snapshots per second; how far behind real time the
## other peers draw Chefty; past this much prediction error the driver snaps; and
## the half-life the driver's smaller corrections fade over.
const CHEFTY_INPUT_TIMEOUT: float = 0.5
const CHEFTY_SNAP_HZ: int = 30
const CHEFTY_VIEW_DELAY: float = 0.1
const CHEFTY_VIEW_EXTRAPOLATE: float = 0.1
const CHEFTY_VIEW_SNAP_METERS: float = 3.0
const CHEFTY_SNAP_ERROR: float = 5.0
const CHEFTY_CORRECTION_HALF_LIFE: float = 0.12
## The host eats at most this many queued driver inputs per tick (two when the
## queue runs longer than CHEFTY_INPUT_QUEUE_CATCHUP).
const CHEFTY_INPUT_QUEUE_CATCHUP: int = 3
## How a stopped Chefty with nobody driving parks: under this speed it's parked.
const CHEFTY_PARK_SPEED: float = 0.6
## The driver's chase camera (player/vehicle_camera.gd): how far back and up,
## how far ahead it looks per m/s, its field of view from standstill to top speed,
## and how fast it swings round behind.
const CHEFTY_CAMERA_BACK: float = 7.5
const CHEFTY_CAMERA_UP: float = 3.2
const CHEFTY_CAMERA_LEAD: float = 0.12
const CHEFTY_CAMERA_FOV := Vector2(70.0, 82.0)
const CHEFTY_CAMERA_FOLLOW: float = 5.0
## Looking around from a seat: how far the head turns either way (radians).
const CHEFTY_SEAT_LOOK_YAW: float = 2.0
## The horn: the one-shot "bwah-BWAAH" first, then this long held before the loop.
const CHEFTY_HORN_LOOP_AFTER: float = 0.45
## The engine's pitch from idle to top speed, and the skid when sliding faster
## than this sideways (m/s).
const CHEFTY_ENGINE_PITCH := Vector2(0.8, 1.9)
const CHEFTY_SKID_SLIP: float = 3.0
## Chefty's own engine loop (until audio/vehicle_sound.gd): extra pitch at full
## throttle, its volume from idle to top speed (dB), the horn loop's volume, and
## how far away either is heard (m).
const CHEFTY_ENGINE_THROTTLE_PITCH: float = 0.08
const CHEFTY_ENGINE_DB := Vector2(-14.0, -4.0)
const CHEFTY_HORN_LOOP_DB: float = -2.0
const CHEFTY_SOUND_MAX_DISTANCE: float = 70.0
## The skid one-shot (critic C12: audio's `skid`): only above this share of top
## speed, and fired again this often while the slide lasts (s).
const CHEFTY_SKID_MIN_SPEED_SHARE: float = 0.2
const CHEFTY_SKID_REPEAT: float = 0.55
## How fast the front wheels follow the stick (full lock per second x this).
const CHEFTY_STEER_SPEED: float = 6.0
## Under this speed (m/s) the gas against the way you're rolling stops braking
## and starts driving the other way.
const CHEFTY_REVERSE_SWITCH_SPEED: float = 0.3
## Suspension: more than this far above the ground (m) and not rising faster
## than this (m/s), Chefty falls onto it instead of being held up.
const CHEFTY_LAND_GAP: float = 0.08
const CHEFTY_LAND_RISE_SPEED: float = 0.5
## How quickly the body's lean follows the throttle and the turn (per second).
const CHEFTY_LEAN_PITCH_RATE: float = 8.0
const CHEFTY_LEAN_ROLL_RATE: float = 6.0
## A bail (getting out above CHEFTY_EXIT_MAX_SPEED) adds this much upward speed (m/s).
const CHEFTY_BAIL_UP: float = 3.0
## The host keeps at most this many of the driver's inputs queued (a stalled link).
const CHEFTY_INPUT_QUEUE_MAX: int = 30
## Where someone getting out stands, in Chefty's space: this far to the side of
## their seat, else the other side, else this far behind the tailgate, else on the
## roof. A spot counts as clear when a player-sized capsule fits there.
const CHEFTY_EXIT_SIDE: float = 1.9
const CHEFTY_EXIT_BEHIND: float = 3.6
const CHEFTY_EXIT_ROOF := Vector3(0.0, 2.6, -2.0)
const CHEFTY_EXIT_CAPSULE := Vector2(0.35, 1.6)

# ---- driving: the autopilot and the chauffeur (driving chunk C2,
# net/components/vehicle_autopilot.gd; docs/DECISIONS.md "The autopilot").
# First guesses, tuned by watching it drive. TODO(balance): not in the workbook.
## Pure pursuit: aim this far ahead along the route (m), and look this far ahead
## of where the truck got when finding where it is on the route.
const AUTOPILOT_LOOKAHEAD: float = 8.0
const AUTOPILOT_PROJECT_AHEAD: float = 40.0
## Speeds (m/s): cruising, round a sharp corner (sharper than CORNER_ANGLE
## radians), while the nose points more than TURN_ANGLE off the route, and the
## least it creeps at until the stop.
const AUTOPILOT_CRUISE: float = 14.0
const AUTOPILOT_CORNER_SPEED: float = 6.0
const AUTOPILOT_CORNER_ANGLE: float = 0.5
const AUTOPILOT_TURN_ANGLE: float = 0.9
const AUTOPILOT_TURN_SPEED: float = 4.0
const AUTOPILOT_CREEP_SPEED: float = 1.5
## Slowing for corners and the stop is planned at this rate (m/s^2), looking
## this far ahead for corners, and reaching corner speed this far before the
## corner (pure pursuit starts turning a lookahead early).
const AUTOPILOT_BRAKE_DECEL: float = 5.0
const AUTOPILOT_CORNER_SCAN: float = 40.0
const AUTOPILOT_CORNER_EARLY: float = 6.0
## The stop: parked once stopped within STOP_RADIUS, or stopped within
## SETTLE_RADIUS for SETTLE_SECONDS.
const AUTOPILOT_STOP_RADIUS: float = 1.5
const AUTOPILOT_SETTLE_RADIUS: float = 4.0
const AUTOPILOT_SETTLE_SECONDS: float = 2.0
## Steering per radian of heading error; the throttle (and the brakes) reach full
## at this many m/s off the speed it wants, never under MIN_THROTTLE once used,
## and nothing within COAST_BAND over it.
const AUTOPILOT_STEER_GAIN: float = 2.2
const AUTOPILOT_THROTTLE_BAND: float = 3.0
const AUTOPILOT_MIN_THROTTLE: float = 0.25
const AUTOPILOT_COAST_BAND: float = 0.6
## Backing up: when the route is more than REVERSE_ANGLE behind the nose, or the
## truck pushed slower than STUCK_SPEED for STUCK_SECONDS; for up to
## REVERSE_SECONDS at this throttle, until it points within REVERSE_EXIT.
const AUTOPILOT_REVERSE_ANGLE: float = 2.1
const AUTOPILOT_REVERSE_EXIT: float = 0.9
const AUTOPILOT_REVERSE_SECONDS: float = 3.0
const AUTOPILOT_REVERSE_THROTTLE: float = 0.7
const AUTOPILOT_STUCK_SPEED: float = 0.5
const AUTOPILOT_STUCK_SECONDS: float = 1.5
## Only counts as stuck while it wants to go at least this many times STUCK_SPEED
## (creeping up to the stop on purpose isn't stuck).
const AUTOPILOT_STUCK_WANT_FACTOR: float = 2.0
## The brakes (a negative throttle) only above CHEFTY_REVERSE_SWITCH_SPEED plus
## this margin (m/s); slower, the brake input, so it never backs up by mistake.
const AUTOPILOT_BRAKE_MARGIN: float = 0.2
## Slowing to a stop aims this share of STOP_RADIUS short of the stop point.
const AUTOPILOT_STOP_AIM_SHARE: float = 0.5
## A corner counts as still ahead until the truck is this far past it (m).
const AUTOPILOT_CORNER_BEHIND: float = 1.0
## Planning: road points closer than this to the last are skipped (m), and the
## route lines up in the stop's lane this far before it (at most LEAD_SHARE of
## the last leg, so a short last leg still points the right way).
const AUTOPILOT_MIN_STEP: float = 3.0
const AUTOPILOT_LANE_LEAD: float = 10.0
const AUTOPILOT_LEAD_SHARE: float = 0.9
## Warp mode (automated runs and --warp-rides): the truck follows the route at
## this many times cruise speed, with no driving.
const AUTOPILOT_TEST_WARP: float = 4.0
## How fast a warping truck swings round to face along the route (per second).
const AUTOPILOT_WARP_TURN_RATE: float = 12.0
## A trip still going after its route's length at GIVE_UP_SPEED, plus
## GIVE_UP_EXTRA seconds, warps the rest of the way: nobody is ever stranded.
const AUTOPILOT_GIVE_UP_SPEED: float = 3.0
const AUTOPILOT_GIVE_UP_EXTRA: float = 30.0
## Chefty counts as at a yard when it parks within this many meters of its curb
## point (TownMap.CURB_POINT): the homeowner's clock starts.
const CHEFTY_ARRIVE_RADIUS: float = 14.0
## The chauffeur's quip floats over the cab this long (s), and the hands riding
## in the bed wave every so often (a random wait in this range, s; the first wave
## after a hand sits down comes sooner, from CHEFTY_HAND_FIRST_WAVE to the range's
## low end).
const CHAUFFEUR_QUIP_SECONDS: float = 4.5
const CHEFTY_HAND_WAVE_SECONDS := Vector2(3.0, 9.0)
const CHEFTY_HAND_FIRST_WAVE: float = 0.5

# ---- driving: the job at the client's house (driving chunk D, net/town/zone_tracker.gd,
# levels/world.gd; docs/DECISIONS.md "One job site that moves"). First guesses.
# TODO(balance): not in the workbook.
## The host works out who is where this often (s), from where they stand: the
## store's lot, the job yard (its PAD_RECTS["LotZone"], this many meters bigger
## while already in it, so the curb doesn't flicker), or the town.
const ZONE_TRACK_SECONDS: float = 0.1
const ZONE_EXIT_MARGIN: float = 3.0
## A paid job's yard stays until every player and Chefty are this far from it (m).
const SITE_FREE_DISTANCE: float = 90.0
## The job's tools (and the yard's own rake, gnome, ...) come back to the yard when
## they settle farther away than this (m), and walking or driving this far off the
## yard mid-job leaves what's in your pockets there (gap-specs/critic.md C23).
const PROP_LEASH_METERS: float = 45.0
## Chefty not at Homie Depot at bedtime: Marty tows it back for this much ($),
## split across the crew like wages.
const CHEFTY_TOW_FEE: int = 20
## The beacon over the job's curb (levels/lots/site_marker.gd): how tall and wide
## (m), and it fades out between these distances (m) as you get close.
const SITE_BEACON_HEIGHT: float = 30.0
const SITE_BEACON_RADIUS: float = 0.85
const SITE_BEACON_FADE := Vector2(22.0, 40.0)
## How fast the beacon's light breathes (cycles per second) and by how much.
const SITE_BEACON_PULSE_HZ: float = 0.6
const SITE_BEACON_PULSE: float = 0.25
## Farther than this from the camera (m; inside its 400 m reach) the beacon is
## drawn pulled in and scaled down so it still shows, and from this far (m) it
## gets wider with distance so it never thins to a hairline.
const SITE_BEACON_DRAW_METERS: float = 300.0
## Once the homeowner pays, the beacon and the chalk PARK HERE box fade out over
## this long (s), rather than blinking off.
const SITE_PAID_FADE_SECONDS: float = 1.5
const SITE_BEACON_WIDEN_FROM: float = 120.0
## Its name is drawn at most this far from the camera (m), along the same line of
## sight, so the fog never swallows it.
const SITE_BEACON_LABEL_METERS: float = 60.0
## Coming home to the TruckPad nose-first, the autopilot swings Chefty round to
## face the road (a handbrake turn): it starts this far from the stop (m), when the
## nose is more than this far off the parking heading (rad), takes this long (s),
## and the tail swings out this far (m).
const CHEFTY_HOME_SWING_METERS: float = 7.5
const CHEFTY_HOME_SWING_MIN_ANGLE: float = 1.6
const CHEFTY_HOME_SWING_SECONDS: float = 1.25
const CHEFTY_HOME_SWING_BULGE: float = 1.8
## Turning faster than this (rad/s) as drawn counts as skidding (the skid sound).
const CHEFTY_SKID_YAW_RATE: float = 2.4
## How quickly that drawn turn rate follows the truck (per second).
const CHEFTY_SKID_YAW_SMOOTHING: float = 12.0
## The hands hop off the tailgate: they start this far behind Chefty's tow point,
## this far apart and this high (m), and drop to the street.
const CHEFTY_HAND_DROP_BEHIND: float = 0.4
const CHEFTY_HAND_DROP_SPACING: float = 0.9
const CHEFTY_HAND_DROP_HEIGHT: float = 1.0
## Paid, the hands walk back to Chefty to climb in; past this many seconds of
## walking they're just in (s).
const HIRE_BOARD_SECONDS: float = 12.0


# ---- nice boys: hiding (R2 chunk 3)
# net/components/hide_spot.gd, props/hide_spot.gd, player/hide_view.gd and the
# pile half of player/player.gd (docs/GAME.md "Hiding", gap-specs/nice_boys.json).
# TODO(balance): none of these are in the workbook yet; tuned by feel from recordings.

## How many fit in each kind of spot (a shed holds two, a bin or a hedge one).
const HIDE_SHED_CAPACITY: int = 2
const HIDE_CAPACITY: int = 1
## Getting in: the dive, vault or step, from where you stood to inside (s). The
## body follows the curve on your own screen at once; the host confirms.
const HIDE_ENTER_SECONDS: float = 0.55
## Getting out: the burst from inside to the clear side you faced (s).
const HIDE_EXIT_SECONDS: float = 0.45
## A refused dive (full, too far): you bounce off the outside and land back here (s).
const HIDE_BONK_SECONDS: float = 0.45
## How long an owner waits for the host's word on a dive before treating it as refused (s).
const HIDE_CONFIRM_TIMEOUT: float = 1.5
## How far out a player standing just past the box still counts, in meters past
## its edge (HIDE_REACH, measured from the box's nearest point now).
const HIDE_REACH_EDGE: float = 1.1
## Inside, the eye turns this far either way from the spot's facing (radians, 75 degrees).
const HIDE_YAW_CLAMP: float = 1.309
## ...and looks this far down and up (radians).
const HIDE_PITCH_CLAMP: Vector2 = Vector2(-0.55, 0.35)
## Peeking (hold secondary): the eye rises this far (m) and the view widens by this many degrees.
const HIDE_PEEK_RISE: float = 0.16
const HIDE_PEEK_FOV: float = 8.0
## The peek eases in and out over this long (s).
const HIDE_PEEK_EASE: float = 0.22
## Third person orbits the spot this far out (m), at this height over its top.
const HIDE_ORBIT: float = 4.5
const HIDE_ORBIT_RISE: float = 1.2
## How fast the view moves into the hide shot and back out (s).
const HIDE_CAM_BLEND: float = 0.3
## While hidden the world is muffled through this low-pass (Hz); NICE BOYS this
## close stay clear (their steps and barks are what you listen for).
const HIDE_MUFFLE_HZ: float = 950.0
const HIDE_CLEAR_CREW_METERS: float = 12.0
## The hider's voice chat, heard by everyone, through this low-pass (Hz).
const HIDE_VOICE_MUFFLE_HZ: float = 700.0
## Tells: turning faster than this (rad/s, smoothed over HIDE_TREMBLE_SMOOTH) inside
## a hedge or pile shakes it.
const HIDE_TREMBLE_TURN_RATE: float = 2.2
## A shake lasts this long (s) and the hedge squash-wobbles this much.
const HIDE_TREMBLE_SECONDS: float = 0.5
const HIDE_TREMBLE_AMOUNT: float = 0.06
## An occupied hedge or pile lets a leaf drop every this many seconds (min, max).
const HIDE_LEAF_DROP_EVERY: Vector2 = Vector2(6.0, 10.0)
## After you climb out, a leaf rides on your head for this long (s).
const HIDE_LEAF_HAT_SECONDS: float = 4.0
## The occupied pile stands this much taller and darker than a plain one.
const HIDE_PILE_MOUND_SCALE: Vector3 = Vector3(1.25, 1.35, 1.25)
const HIDE_PILE_MOUND_DARKEN: float = 0.22
## Climbing out picks the clear side nearest where you look: each side's spot is
## this far out from the box edge (m), checked with a capsule this size.
const HIDE_EXIT_GAP: float = 0.55
const HIDE_EXIT_RADIUS: float = 0.34
const HIDE_EXIT_HEIGHT: float = 1.7
## An inspection: a NICE BOY pokes the spot for this long (s) (from
## HIDE_INSPECT_REACH out, under "# ---- R2c hide").
const HIDE_INSPECT_SECONDS: float = 2.0
## A spot just inspected isn't picked again for this long (s).
const HIDE_INSPECT_COOLDOWN: float = 20.0
## A searching NICE BOY inspects at most this many spots per search, and only
## ones scoring at least this (inspect_score: suspicion + HIDE_INSPECT_BASE -
## meters / HIDE_INSPECT_METERS_PER_POINT).
const HIDE_INSPECT_PER_SEARCH: int = 2
const HIDE_INSPECT_MIN_SCORE: float = 0.05
const HIDE_INSPECT_BASE: float = 0.15
const HIDE_INSPECT_METERS_PER_POINT: float = 40.0
## A poke never resolved (the NICE BOY bonked, stunned or sent home) frees the
## spot for another look this long after it should have ended (s).
const HIDE_INSPECT_STALE_SLACK: float = 3.0
## The host accepts a dive this much farther out than HIDE_REACH_EDGE (m): the
## asker's position reaches it a little late.
const HIDE_REACH_SLACK: float = 0.6
## Settling in after a dive turns the body round once; no tell or rustle counts
## for this long after getting in (s).
const HIDE_SETTLE_SECONDS: float = 1.2
## Found: the hider is set down this far short of the NICE BOY (m).
const HIDE_PULL_STANDOFF: float = 0.9
## The NICE BOY's shrug after a near miss and his "Upsy-daisy!" lift (s).
const HIDE_SHRUG_SECONDS: float = 1.2
const HIDE_UPSY_DAISY_SECONDS: float = 0.9
## Suspicion at or over this when the poke ends: found.
const HIDE_FOUND_AT: float = 0.6
## Found: after the reveal (HIDE_FOUND_REVEAL) he lifts you out toward him over
## this long (s), sets you on your feet, then the gotcha.
const HIDE_PULL_SECONDS: float = 0.55
## Courtesy Notice stickers a spot shows at most (one per near miss, all day).
const HIDE_NOTICE_MAX: int = 5

## Suspicion (0..1 per spot, host only). What raises it: being seen going in;
## peeking or rustling where a NICE BOY could see it (inside SUSPICION_CONE_METERS),
## per second; having just been used; being near where someone was last seen.
const SUSPICION_SEEN_ENTERING: float = 0.8
const SUSPICION_PEEK_PER_S: float = 0.22
const SUSPICION_RUSTLE: float = 0.18
const SUSPICION_RECENT_USE: float = 0.2
const SUSPICION_RECENT_SECONDS: float = 30.0
const SUSPICION_NEAR_LAST_SEEN: float = 0.25
const SUSPICION_NEAR_METERS: float = 6.0
const SUSPICION_CONE_METERS: float = 15.0
## A NICE BOY's view cone for the fallback check (degrees either side of facing),
## used only while the crew has no sees_point() of its own (chunk 2 adds one).
const SUSPICION_CONE_HALF_DEG: float = 55.0
## Suspicion fades by this much a second.
const SUSPICION_DECAY_PER_S: float = 0.02


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
## Where a looping music track goes back to, past the end of its intro: every
## .ogg tools/encode_ogg.py writes ends with one extra 20 ms frame of its own
## loop start, so playing to the end and jumping to intro + this is seamless.
## (Godot's Movie Maker records whole frames and starts 66 samples late, and
## Godot plays an .ogg to its last packet; docs/DECISIONS.md, "Audio: the music
## pipeline".) It is half a sample over 0.02 s because Godot truncates a seek
## time to a whole sample, and 9.6 + 0.02 lands a hair under 9.62 in floating
## point. audio/music_tracks.gd's loop_offset adds it; encode_ogg.py checks it.
const MUSIC_ENCODE_LEAD_SECONDS: float = 0.0200113

## The neighborhood's background (audio/ambience.gd): the wind, in decibels; it
## drops this much more in transit and at the border.
const AMBIENCE_WIND_DB: float = -14.0
const AMBIENCE_WIND_AWAY_DB: float = -8.0
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

## The music director (audio/music_director.gd, audio/music_schedule.gd). A
## track plays this loud (dB, before the Music bus); a stinger a little louder.
const MUSIC_TRACK_DB: float = -6.0
const MUSIC_STINGER_DB: float = -3.0
## Crossfade seconds for a normal change, and for a raid or the crossing.
const MUSIC_FADE_SECONDS: float = 2.5
const MUSIC_FADE_URGENT_SECONDS: float = 0.4
## A calm mood has to hold this long before the music follows (a teleport doesn't flap it).
const MUSIC_MOOD_HOLD_SECONDS: float = 1.5
## How often the director looks at the game, in seconds.
const MUSIC_TICK_SECONDS: float = 0.25
## Calm music plays a track this many loops, then rests this long (random in
## the range) with ambience only, then plays the mood's next track.
const MUSIC_LOOPS_BEFORE_REST: int = 2
const MUSIC_REST_SECONDS: Vector2 = Vector2(45.0, 120.0)
## Hot Yard on the lot from this much heat, until it cools below the exit.
const MUSIC_HOT_HEAT: float = 65.0
const MUSIC_HOT_HEAT_EXIT: float = 55.0
## The yard's evening music from this hour (quiet hours, Constants.QUIET_HOURS_START, take over later).
const MUSIC_GOLDEN_HOUR: float = 17.0
## Music ducks this many dB under a stinger, over this many seconds each way.
const MUSIC_STINGER_DUCK_DB: float = -14.0
const MUSIC_DUCK_FADE_SECONDS: float = 0.25
## The game cues (audio/cue_hooks.gd): one phone buzz at most this often (seconds),
## how long a text waits to see whether the day summary is coming with it, and how
## often the task list is checked for a task just done.
const PHONE_BUZZ_GAP_SECONDS: float = 1.2
const CUE_TEXT_SETTLE_SECONDS: float = 0.3
const CUE_TASK_POLL_SECONDS: float = 0.5
## A task counts as done at this many percent (the task list turns it green).
const TASK_DONE_PERCENT: int = 95

# ---- nice boys: Annex set and sound (R2 chunk 5)
# Satellite Annex B (levels/annex/annex_b.gd, props/office_props.gd, npcs/clerk.gd,
# props/form_27b.gd, props/receipt_slip.gd; docs/GAME.md "Satellite Annex B").
# Everything here is local and cosmetic; what happens there is chunk 6's.
## The interior, in meters: 18 wide (x), 3.2 to the ceiling, 13 deep (z).
const ANNEX_SIZE: Vector3 = Vector3(18.0, 3.2, 13.0)
## The seed the world builds the set with (its default window looks; a run
## dresses its own over them). Form 27-B, so 27.
const ANNEX_SET_SEED: int = 27
## Budgets for the whole set (the staff's bodies are characters, budgeted with
## the cast): triangles and draw calls (one per visible mesh surface, label and sprite).
const ANNEX_MAX_TRIS: int = 60000
const ANNEX_MAX_DRAWS: int = 60
## Ceiling light rows, back to front; at closing they clunk off this far apart (seconds).
const ANNEX_LIGHT_ROWS: int = 4
const ANNEX_LIGHT_ROW_GAP: float = 0.3
## Each row's warm fill light: energy and reach (m). Rows cast shadows only at the
## top Settings shadow level.
const ANNEX_LAMP_ENERGY: float = 0.75
const ANNEX_LAMP_RANGE: float = 9.0
## A window's own lamp (lit = serving) and how fast props move, in seconds: the
## blinds, the hatch, a window stamp's lift and slam (the KA-CHUNK lands at the
## end of the slam), the entrance doors, the side door, the turnstile's turn.
const ANNEX_WINDOW_LAMP_ENERGY: float = 2.4
const ANNEX_BLIND_SECONDS: float = 0.55
const ANNEX_HATCH_SECONDS: float = 0.3
const ANNEX_STAMP_LIFT_SECONDS: float = 0.22
const ANNEX_STAMP_SLAM_SECONDS: float = 0.09
const ANNEX_DOOR_SECONDS: float = 0.7
const ANNEX_TURNSTILE_TURN_SECONDS: float = 0.8
const ANNEX_TURNSTILE_BOUNCE_SECONDS: float = 0.35
## A floor line's pulse (it brightens and fades twice), and the bell's wobble.
const ANNEX_PULSE_SECONDS: float = 1.2
const ANNEX_BELL_WOBBLE_SECONDS: float = 0.5
## The big APPROVED, NICELY stamp: raised this high (m) and held for the
## hesitation before the slam, its slam time, and how high a holder carries it.
const ANNEX_BIG_STAMP_RAISE: float = 0.55
const ANNEX_BIG_STAMP_HESITATE: float = 0.6
const ANNEX_BIG_STAMP_SLAM_SECONDS: float = 0.12
## How long the big stamp takes to rise off its pad before the hesitation (s).
## The KA-CHUNK lands LIFT + HESITATE + SLAM after the slam starts
## (OfficeProps.BigStamp.slam_lands_after()).
const ANNEX_BIG_STAMP_LIFT_SECONDS: float = 0.25
## Past this far from the camera (m) the set stops drawing and its staff stop
## moving; a peer with no camera (a headless host, a bot) never runs the staff.
const ANNEX_CULL_DISTANCE: float = 160.0
## The staff (npcs/clerk.gd): walking pace and the hurry back (m/s), how fast they
## turn (radians a second), the head shake's rate, how loud and how often the asleep
## clerk snores (seconds between snores), and how far apart the closing volley's stamps fall.
const CLERK_WALK_SPEED: float = 1.6
const CLERK_HURRY_SPEED: float = 3.0
const CLERK_TURN_RATE: float = 6.0
const CLERK_SHAKE_HZ: float = 3.2
const CLERK_SNORE_EVERY: float = 2.6
const CLERK_VOLLEY_GAP: float = 0.22
## A clerk's bark caption (the caption stack's subtitle line), in seconds.
const CLERK_BARK_SECONDS: float = 2.2
## A clerk hands his arms over to a body gesture (the scribble) and takes them
## back over this long (s).
const CLERK_GESTURE_BLEND: float = 0.2
## The clipboard (props/form_27b.gd): its paper texture's width in pixels (the
## height is FORM_ASPECT times that), where it sits in a first-person view
## (camera space, m) and its tilt (radians), and how long a smudge takes to wipe a box off.
const FORM_TEXTURE_PX: int = 256
const FORM_ASPECT: float = 1.32
const FORM_FIRST_PERSON_OFFSET: Vector3 = Vector3(-0.2, -0.17, -0.42)
const FORM_FIRST_PERSON_TILT: Vector3 = Vector3(0.55, 0.32, 0.12)
const FORM_SMUDGE_SECONDS: float = 0.8
## Held in a body's left hand (Form.attach_hand): this far down the arm from
## the shoulder pivot (m), where the hand is.
const FORM_HAND_DROP: float = 0.56
## A stamp landing on the form: the ink's punch-in (seconds).
const FORM_STAMP_SECONDS: float = 0.18
## The receipt slip (props/receipt_slip.gd): seconds per printed line, where it
## sits in a first-person view (camera space, m).
const RECEIPT_LINE_SECONDS: float = 0.12
const RECEIPT_FIRST_PERSON_OFFSET: Vector3 = Vector3(0.06, -0.06, -0.34)
## The lobby muzak's mood priority (audio/music_tracks.gd MOODS "annex_hold"; the
## escape cue it switches to is 80). The switch waits for the next bar line of
## the muzak (both tracks are the same tempo and form), then cuts in at the same bar.
const ANNEX_HOLD_PRIORITY: int = 70
## The longest the director waits for that bar line before switching anyway (s).
const MUSIC_BAR_SWITCH_MAX_WAIT: float = 1.8
## A cut at a bar line crossfades this fast (s).
const MUSIC_BAR_SWITCH_FADE: float = 0.06
## Closing time's dying record (MusicDirector.slowdown): the pitch it sinks to.
const MUSIC_SLOWDOWN_PITCH: float = 0.45
## A rider's cab (MusicDirector.set_ambience &"van_cab"): the music through the van's walls.
const MUSIC_CAB_CUTOFF_HZ: float = 1200.0
## The office bed (audio/ambience.gd in the Annex): the typewriters' loop (dB), a
## distant phone and the water cooler's glug, seconds apart as a random range.
const AMBIENCE_OFFICE_DB: float = -16.0
const AMBIENCE_OFFICE_PHONE_GAP: Vector2 = Vector2(14.0, 32.0)
const AMBIENCE_OFFICE_GLUG_GAP: Vector2 = Vector2(20.0, 30.0)
## How fast the office bed fades in and out at the Annex's door (dB a second).
const AMBIENCE_OFFICE_FADE_DB_PER_SECOND: float = 120.0
## Busted plays this long after the hand lands when CATCH_BARK_AT (the catch's
## bark, R2 chunk 2) isn't in this build yet (s).
const CUE_BUSTED_AFTER_FALLBACK: float = 0.95

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
## the sun's shadow distance in meters, and the soft-shadow filter quality
## (RenderingServer.ShadowQuality: 0 hard, 1 soft very low, 2 soft low, 3 soft medium).
## Level 3 (High) is exactly levels/shared_look.gd's sun and the engine's defaults.
## Low is hard-edged (settings:2): the cheapest filter, and its edges stay clean
## under FSR, where the very-low soft filter's grain was sharpened into speckle.
const SHADOW_LEVELS: Array[Dictionary] = [
	{},
	{"atlas": 2048, "distance": 50.0, "soft": 0},
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
## Outline line width in pixels for video.outline 0 (off), 1 (on), 2 (bold). The
## pass samples depth that many pixels out (nearest), so a width rounds to whole
## pixels: Bold is 3 (settings:2: 1.6 sampled 2 px out and read the same as On).
const OUTLINE_WIDTHS: Array[float] = [0.0, 1.0, 3.0]
## RenderingServer SSAO quality used whenever ambient occlusion is on.
const SSAO_QUALITY_HIGH: int = 2
## The quality presets. Each sets these video keys; changing any one of them
## afterwards turns video.preset to "custom". "high" is the shipped look.
## aa: 0 off, 1 FXAA, 2 MSAA 2x, 3 MSAA 4x. upscaler: 0 bilinear, 1 FSR 1.0.
## Low renders at 75% and upscales with FSR (settings:2: bilinear at 75% smeared
## Chefty's lettering and the grass; FSR keeps them crisp for next to nothing).
## Ultra's MSAA 4x leaves the depth outline intact (checked in windowed shots).
const GRAPHICS_PRESETS: Dictionary = {
	"low": {"shadows": 1, "ssao": false, "glow": false, "outline": 1, "grass": 1, "aa": 0, "render_scale": 0.75, "upscaler": 1},
	"medium": {"shadows": 2, "ssao": false, "glow": true, "outline": 1, "grass": 2, "aa": 1, "render_scale": 1.0, "upscaler": 0},
	"high": {"shadows": 3, "ssao": true, "glow": true, "outline": 1, "grass": 3, "aa": 0, "render_scale": 1.0, "upscaler": 0},
	"ultra": {"shadows": 4, "ssao": true, "glow": true, "outline": 1, "grass": 4, "aa": 3, "render_scale": 1.0, "upscaler": 0},
}
## Actions that are held down rather than tapped. The mouse wheel has no held
## state, so it can never be bound to one of these. A feature adding a held
## action adds it here (gap-specs/critic.md C14, C15).
const HOLD_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"crouch",
	&"primary", &"secondary", &"drop", &"push_to_talk", &"honk",
]
## Bindings per action (two slots: a main key and an alternate).
const BINDING_SLOTS: int = 2
## The Settings window (ui/settings_window.gd): its card size at 100% UI scale,
## the least gap it keeps to the screen edge when a bigger UI scale shrinks the
## screen, and the shortest time between two slider ticks, in milliseconds.
const SETTINGS_WINDOW_SIZE: Vector2 = Vector2(820.0, 580.0)
const SETTINGS_WINDOW_MARGIN: float = 20.0
const SETTINGS_TICK_GAP_MS: int = 60
## How the Keys tab groups actions, in order. Any other non-ui_ action is listed
## under "other" automatically. A feature adding an action may add it to a group here.
const KEYBIND_GROUPS: Array[Dictionary] = [
	{"id": "moving", "actions": [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"crouch", &"board"]},
	{"id": "working", "actions": [&"primary", &"secondary", &"interact", &"take", &"drop"]},
	{"id": "pockets", "actions": [&"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5", &"slot_next", &"slot_prev"]},
	{"id": "crew","actions": [&"phone", &"push_to_talk", &"honk", &"toggle_camera", &"toggle_music", &"pause"]},
]

# ---- raking: leaf motion (R1 chunk 3)
# Leaves you see travelling between cells (leaves/leaf_motion.gd, leaf_movers.gd,
# leaf_flow.gd, leaf_chaff.gd; docs/DECISIONS.md 2026-11-02 "Leaf motion"). All of
# it is cosmetic and local: the host's density grid stays the only truth.
## Mover pool cap and simulation range (m) per video preset: [cap, range].
const LEAF_DETAIL: Dictionary = {"low": [300, 18.0], "medium": [600, 24.0], "high": [900, 32.0], "ultra": [1500, 40.0]}
## Density units one mover carries: one hero flake's worth (raking:2's
## LEAF_HERO_UNITS), so a flake that leaves a cell is the flake you see fly.
const LEAF_MOVER_UNITS: int = 22
## Most movers one batch spawns before units per mover grow instead.
const LEAF_MOVERS_PER_BATCH_MAX: int = 140
## Full detail within this distance of the camera; fewer movers out to LEAF_MOTION_RANGE.
const LEAF_MOTION_NEAR: float = 22.0
const LEAF_MOTION_RANGE: float = 32.0
## Mover share between NEAR and RANGE.
const LEAF_MOTION_FAR_SHARE: float = 0.35
## Simulation budget per physics tick (ms); over it, new batches get fewer, heavier
## movers. GDScript runs a mover in about 3.5 us (i9 bench, 2026-11-02): one raker
## is about 0.5 ms, four rakers and two hands about 1.7 ms.
const LEAF_MOTION_MS: float = 2.0
## How long a stroke event stays a hint for the changes it explains (s).
const LEAF_HINT_SECONDS: float = 0.4
## Leftover losses and gains pair up within this distance (m). At least the
## windrow's longest carry (rakefeel:field): a dragged stroke takes leaves from
## RAKE_FIELD_BACK + RAKE_FIELD_DRAG_MAX behind its point to its berm, up to
## RAKE_FIELD_BERM_REACH cells past RAKE_FIELD_BITE_FRONT[1], about 6.1 m along
## an axis and 5.9 m along a diagonal (the berm's reach is in metres; a drag needs
## a walk of at most RAKE_FIELD_DRAG_MAX since the last stroke).
const LEAF_FLOW_MAX_DIST: float = 6.5
## A batch bigger than this (cells) or an unhinted one bigger than this (flakes) is morphed.
const LEAF_FLOW_MAX_CELLS: int = 600
const LEAF_RESYNC_ANIMATE_MAX: int = 300
## Speed of the leaves' pressure wave ahead of a rake or blower (m/s).
const LEAF_SWEEP_SPEED: float = 5.0
## Longest a leaf waits for the rake head before it goes anyway (s).
const LEAF_MOVER_WAIT_MAX: float = 0.4
## An event this late (s) skips waiting for the head.
const LEAF_LATE_EVENT: float = 0.25
## Air drag across the leaf's face and along it (per s): a flat leaf falls at about
## 1.4 m/s, a tilted one glides sideways (the falling-leaf zigzag).
const LEAF_DRAG_NORMAL: float = 7.0
const LEAF_DRAG_TANGENT: float = 0.5
## Flutter: the restoring torque about the leaf's long axis.
const LEAF_FLUTTER_K: float = 14.0
## Flutter wobble frequency range (Hz) and strength (rad/s^2).
const LEAF_FLUTTER_HZ := Vector2(2.2, 3.6)
const LEAF_FLUTTER_KICK: float = 22.0
## Faster than this (m/s) a leaf tumbles end over end.
const LEAF_TUMBLE_SPEED: float = 2.5
## The homing spring that skids a leaf into its resting place (rad/s).
const LEAF_SPRING: float = 14.0
## Share of a flight after which the homing spring starts, and how long it blends in (s).
const LEAF_HOME_AT: float = 0.6
const LEAF_HOME_BLEND: float = 0.15
## Bounce and ground friction.
const LEAF_RESTITUTION: float = 0.15
const LEAF_BOUNCE_SPEED: float = 0.6
const LEAF_FRICTION: float = 6.0
## Leaves within the head's half width plus this (m) ride the tines.
const LEAF_HEAD_SIDE: float = 0.25
## A flight ends by this age (s), with at most this last jump (m).
const LEAF_SETTLE_MAX: float = 1.4
const LEAF_SNAP_MAX: float = 0.15
## Most a mover moves in one physics tick (m).
const LEAF_MAX_STEP: float = 0.35
## A landed leaf keeps drawing at its slot until the view draws it (ticks).
const LEAF_PARK_TICKS: int = 2
## Flight time for a leaf going dist metres: clamp(base + per_m * dist, min, max) (s),
## and the launch speed over-shoot that makes up for drag.
const LEAF_FLIGHT_TIME := Vector4(0.32, 0.1, 0.3, 0.8)
const LEAF_AIM_BOOST: float = 1.25
## A leaf the rake throws: hop speed (m/s), spin (rad/s), extra push along the stroke (m/s).
const LEAF_RAKE_HOP := Vector2(0.7, 1.7)
const LEAF_RAKE_SPIN := Vector2(6.0, 14.0)
const LEAF_RAKE_PUSH := Vector2(0.4, 1.2)
## Leaves beside the head go at this share of the speed and hop (the bow wave).
const LEAF_BESIDE_SPEED: float = 0.6
const LEAF_BESIDE_HOP: float = 0.5
## Bare hands hop leaves this much of a rake's.
const LEAF_HAND_HOP: float = 0.4
## A blower puff: speed along the stroke and hop (m/s); drag along the leaf is this share.
const LEAF_BLOWER_SPEED := Vector2(5.0, 8.0)
const LEAF_BLOWER_HOP := Vector2(0.8, 2.0)
const LEAF_BLOWER_GLIDE: float = 0.5
## Bagging: leaves spiral up into the bag mouth (this high above the pile, m) over this long (s).
const LEAF_BAG_MOUTH: float = 0.7
const LEAF_BAG_SECONDS: float = 0.45
const LEAF_BAG_STAGGER: float = 0.08
const LEAF_BAG_SHRINK: float = 0.6
## A mower pulls leaves into its deck this fast (s).
const LEAF_MULCH_SECONDS: float = 0.15
## A burst bag's fountain: up and outward speed (m/s).
const LEAF_SCATTER_UP := Vector2(2.0, 4.0)
const LEAF_SCATTER_OUT := Vector2(1.0, 2.5)
## Leaves that turn up with no stroke to explain them fall from this high (m).
const LEAF_DROP_HEIGHT: float = 0.35
## Scale-in when a leaf comes out of the litter skin, shrink when it dives into it (s).
const LEAF_SKIN_IN_SECONDS: float = 0.08
const LEAF_SKIN_OUT_SECONDS: float = 0.12
## Leaves pushed off the yard's edge slide on and fade over this long (s).
const LEAF_EDGE_FADE_SECONDS: float = 0.3
## Running through deep leaves: faster than this (m/s) through cells this thick
## kicks up this many leaves a second; a dive throws up this many.
const LEAF_KICK_SPEED: float = 2.0
const LEAF_KICK_DENSITY: int = 120
const LEAF_KICK_PER_SEC: int = 16
const LEAF_DIVE_LEAVES: int = 40
## Players farther than this (m) from the camera kick nothing up.
const LEAF_KICK_RANGE: float = 20.0
## A kicked leaf's hop (m/s) and flight time (s).
const LEAF_KICK_HOP := Vector2(1.2, 2.4)
const LEAF_KICK_TIME := Vector2(0.45, 0.8)
## Kicks stop once the pool is this full.
const LEAF_KICK_POOL_SHARE: float = 0.8
## Ray checks per tick against walls and fences for fast leaves (0 turns them off).
const LEAF_WORLD_RAYS_PER_TICK: int = 48
const LEAF_RAY_SPEED: float = 1.5
## Landings are heard in bins this big (m) gathered over this long (s); a landing on
## a cell at least this thick is onto a pile (contract C5, audio/leaf_audio.gd).
const LEAF_SETTLE_WINDOW: float = 0.08
const LEAF_SETTLE_AREA: float = 2.0
const LEAF_PILE_WHUMP_DENSITY: int = 180
## At most this many kick sounds per player per second.
const LEAF_KICK_SOUNDS_PER_SEC: float = 4.0
## Pooled chaff emitters: leaf bits, dust, grass and mower shreds at each bite.
const LEAF_CHAFF_EMITTERS: int = 6
## Chaff per stroke: fragments scale with the leaves moved, from to (count), at full load (units).
const LEAF_CHAFF_BITS := Vector2i(12, 40)
const LEAF_CHAFF_FULL_UNITS: float = 3000.0
const LEAF_CHAFF_EMPTY_BITS: int = 4
## The chaff pool: [type (0 bits, 1 dust, 2 grass, 3 shreds), particles] per emitter.
## A light and a heavy bits emitter cover LEAF_CHAFF_BITS.
const LEAF_CHAFF_POOL: Array = [[0, 14], [0, 36], [1, 8], [1, 8], [2, 5], [3, 24]]
## The bag's spiral: start radius (m), turns, lift at mid-flight (m).
const LEAF_BAG_SPIRAL := Vector3(0.35, 1.5, 0.12)
## A burst bag's leaves start this far round its mouth: sideways (m), up from..to (m);
## they fly this long (s), homing from this age (s).
const LEAF_SCATTER_SPAWN := Vector3(0.15, 0.2, 0.45)
const LEAF_SCATTER_LIFE := Vector2(1.0, 0.55)
## A leaf nothing explains: flight time and home age (s); it starts this far round
## its cell (m).
const LEAF_DROP_LIFE := Vector2(0.5, 0.2)
const LEAF_DROP_SPREAD: float = 0.2
## A redirected leaf starts homing on its new cell by this age (s) at the latest.
const LEAF_RETARGET_HOME_MAX: float = 0.12
## A dive throws up leaves within this distance (m); a player moving faster than
## this (m/s) is teleporting, not running, and kicks nothing.
const LEAF_DIVE_RADIUS: float = 1.1
const LEAF_KICK_SPEED_MAX: float = 15.0
## A gust tries this many flakes per unit of strength, at most the cap.
const LEAF_GUST_TRIES := Vector2(20.0, 120.0)

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

# ---- hotbar holds
# Hands on what you hold, first and third person (props/prop_looks.gd HOLDS and
# grip_points, player/cartoon_body.gd set_hold).
## How long a body's arm takes to reach for a held thing, or let go of it (s).
const HOLD_BLEND_SECONDS: float = 0.15
## A body's arm from the shoulder to the middle of the mitten (m). A grip closer
## than this shortens the arm (a cartoon foreshortening), down to HOLD_ARM_SHORTEST
## of its length; a farther one stretches it, up to HOLD_ARM_LONGEST, and past
## that is reached for and missed a little.
const HOLD_ARM_REACH: float = 0.5
const HOLD_ARM_SHORTEST: float = 0.78
const HOLD_ARM_LONGEST: float = 1.15
## A grip farther than this from its shoulder (m) doesn't count as held (the
## probe's grip_ok, hotbar_test step 9).
const HOLD_GRIP_REACH: float = 0.62

# ---- raking: rake stroke (R1 chunk 4)
# One push-sweep swing everyone sees (equipment/rake_stroke.gd, props/rake_motion.gd;
# docs/GAME.md "Raking: the push-sweep"). Phases are fractions of one swing.
## Field strokes per swing: a swing lasts RAKE_STROKE_SECONDS x this (0.6 s), so
## holding the button keeps today's 3.33 strokes a second.
const RAKE_SWING_STROKES: int = 2
## OQ-R1-1: "push" (leaves go away from you, the field's rule). Only the head path
## would change for "pull".
const RAKE_SWING_STYLE: String = "push"
## When each field stroke bites, as a fraction of the swing (0.12 s and 0.30 s).
const RAKE_SWING_BITES: Array[float] = [0.2, 0.5]
## The plant (tines touch down), the end of the drive, and the end of the flick.
const RAKE_SWING_PHASES: Dictionary = {"plant": 0.2, "drive_end": 0.74, "flick_end": 0.87}

## A hired hand's swing (HIRE_STROKE_SECONDS / skill long) bites once, here. A
## swing's first bite is never after its plant (RAKE_SWING_PHASES): the bite is
## when the plant sounds on every peer (audio/leaf_audio.gd; audio_test "sync").
const RAKE_CREW_BITES: Array[float] = [0.2]
## How far ahead of the feet the tines plant, and where the drive ends (m). The
## hands hold the 1.6 m handle near its top, so the plant can't come closer than
## this without the hands going up past the face; the far end needs the lunge.
## (R1b rakefeel:look: the drive starts close in, the handle nearly upright, and
## the lunge carries it out to the far end, 1.25 m of drag; the upper hand may sit
## lower on the handle, RAKE_HAND_SLIDE_MAX, so the top clears the face.)
const RAKE_HEAD_NEAR: float = 0.85
const RAKE_HEAD_FAR: float = 2.1
## The head sits a little to the right of center (a right-handed hold), drifts
## sideways at most this much during a drive, alternating sides swing to swing,
## and is never further than RAKE_HEAD_LATERAL off center (m).
const RAKE_HEAD_BASE_X: float = 0.12
const RAKE_HEAD_DRIFT: float = 0.13
const RAKE_HEAD_LATERAL: float = 0.25
## How far the head turns off straight ahead with the drift (rad, 15 degrees).
const RAKE_HEAD_YAW_MAX: float = 0.26
## The return arc's height, the wrist flick's extra height at the end of the drive,
## and how far the head follows through forward in the flick (m).
const RAKE_HEAD_LIFT: float = 0.11
const RAKE_HEAD_FLICK: float = 0.12
const RAKE_HEAD_FOLLOW: float = 0.06
## The tines are kinked this far toe-down from the handle (rad), and bend back by up
## to RAKE_TINE_FLEX x load while they push leaves; the flick tips them up.
const RAKE_HEAD_TOE_DOWN: float = 0.45
const RAKE_TINE_FLEX: float = 0.3
const RAKE_TINE_FLICK: float = 0.35
## Leaves moved by one stroke that count as a full load (look only, never timing).
const RAKE_LOAD_FULL: float = 5000.0
## The hands on the handle: the upper (left) hand near the top, the lower (right)
## one this far below it, or as close as RAKE_HAND_SPAN_MIN when the arm can't
## reach (the hands come together at full stretch). The upper hand aims for the
## chest with the head close in and the belly at full stretch, from the
## shoulders (RAKE_GRIP_NEAR/FAR); it slides at most RAKE_HAND_SLIDE_MAX down
## from the top.
const RAKE_HAND_SPAN: float = 0.48
const RAKE_HAND_SPAN_MIN: float = 0.24
const RAKE_HAND_SLIDE_MAX: float = 0.5
## Your own rake while you look through your eyes (your body is hidden then, and
## the camera doesn't lunge): both hands at the handle's top, this far apart, and
## your first-person arms may stretch to this times their length to hold on.
const RAKE_HAND_SPAN_FP: float = 0.3
const RAKE_FP_ARM_STRETCH: float = 1.9
## Where the handle aims then, in body space: just past your right shoulder.
const RAKE_FP_HANDLE_AIM: Vector3 = Vector3(0.3, 1.25, 0.0)
## The handle slides this far through the hands over a drive (m).
const RAKE_HANDLE_SLIDE: float = 0.1
## The body twists with the drift and sticks its hips back as the tines plant
## (m); how far it leans and lunges into the drive is RAKE_LEAN_DRIVE and
## RAKE_LUNGE_DRIVE (rakefeel: look).
const RAKE_TWIST_Y: float = 0.2
const RAKE_HIP_SHIFT: float = 0.06
## First person: the camera nods down this far at the plant (in 0.06 s, back over
## 0.25 s), rolls a touch with the drift, and narrows the view during the drive.
const RAKE_CAM_DIP_DEG: float = 1.6
const RAKE_CAM_ROLL_DEG: float = 0.5
const RAKE_CAM_FOV_KICK: float = -1.0
const RAKE_CAM_ENABLED: bool = true
## Rake heads by tier (starter, Tune-Up, The Leafinator): width (m) and tines.
const RAKE_HEAD_WIDTHS: Array[float] = [0.95, 1.15, 1.35]
const RAKE_TINES: Array[int] = [15, 17, 19]
## Hired hand "HandN" is actor RAKE_ACTOR_HAND_BASE + N in stroke events.
const RAKE_ACTOR_HAND_BASE: int = 1000
## Someone else's swing: blend into a re-phased swing over this long, and back to
## standing still after a swing nobody followed up (s).
const RAKE_PLANT_BLEND: float = 0.06
const RAKE_REMOTE_IDLE_BLEND: float = 0.15
## The swing's feel (equipment/rake_stroke.gd sample): the share of the full lean
## kept between drives, and while just holding the rake; the share of the drift and
## twist already in by the plant; the share of RAKE_HEAD_YAW_MAX the head turns.
const RAKE_READY_LEAN: float = 0.5
const RAKE_IDLE_LEAN: float = 0.25
const RAKE_PLANT_DRIFT_SHARE: float = 0.3
const RAKE_YAW_SHARE: float = 0.6
## The tines' bounce at the plant (rad) over this first share of the drive.
const RAKE_PLANT_BOUNCE: float = 0.06
const RAKE_PLANT_BOUNCE_SPAN: float = 0.15
## The body leads the head into the drive: its lean and lunge run this many times
## faster than the head's travel.
const RAKE_BODY_LEAD: float = 1.4
## A full load bends the back this much more (rad of lean per load).
const RAKE_LOAD_LEAN: float = 0.05
## The camera nod at the plant: down within this many seconds, back up by the second.
const RAKE_CAM_DIP_IN: float = 0.06
const RAKE_CAM_DIP_OUT: float = 0.31
## The flick lasts this many times the drive_end-to-flick_end span, and lets a full
## load's tines spring forward by this (rad).
const RAKE_FLICK_STRETCH: float = 1.6
const RAKE_FLICK_FLEX: float = -0.05
## The body in the work pose (player/cartoon_body.gd set_work_pose): the hips turn
## this share of the twist the other way, the shoulders this share of it with;
## the face tilts down this share of the lean. (The feet: RAKE_STANCE_*.)
const WORK_HIP_COUNTER: float = 0.1
const WORK_TWIST_SHARE: float = 1.1
const WORK_FACE_TILT: float = 0.6
## How far a hand can be from its shoulder before the lower hand slides up the
## handle (props/rake_motion.gd, m).
const RAKE_HAND_REACH: float = 0.58
## Your rake's grips in first person, nudged in head space so the mitts sit on the
## handle rather than inside it (player/first_person_arms.gd, m).
const RAKE_FP_GRIP_OFFSET: Vector3 = Vector3(0.0, 0.025, 0.0)
## How fast a hired hand turns to face the way it rakes (rad/s).
const HIRE_TURN_SPEED: float = 7.0
## Before raking:1 the field doesn't say how much a stroke moved: the leaves under
## the head times this stand in for it (equipment/rake.gd, look only).
const RAKE_LOAD_GUESS: float = 1.5

# ---- rakefeel: look (R1b; docs/GAME.md "Raking feel: the look")
# The swing with weight (equipment/rake_stroke.gd, props/rake_motion.gd,
# player/cartoon_body.gd, player/stroke_cam.gd) and the leaves it pushes
# (leaves/leaf_movers.gd ride, leaves/leaf_shaders.gd edges).
## How far the hips sink (m): just holding the rake, sitting back into the plant,
## and at the bottom of the lunge (more under a full load, RAKE_LOAD_CROUCH a load).
const RAKE_CROUCH_IDLE: float = 0.04
const RAKE_CROUCH_PLANT: float = 0.06
const RAKE_CROUCH_DRIVE: float = 0.12
const RAKE_LOAD_CROUCH: float = 0.04
## The hips rise out of the drive's crouch this many times faster than the
## return runs (they are back up a little before the head resets).
const RAKE_CROUCH_RISE: float = 1.15
## The work stance (body space x, z; -Z ahead, m): the left foot a half step
## forward, the right one back, while the rake works and the body stands or
## shuffles (slower than RAKE_STANCE_SPEED m/s; faster, the walk cycle takes
## over); stepping into it or out takes RAKE_STANCE_SECONDS. The knees take up
## the hips' sink and lunge.
const RAKE_STANCE_FRONT := Vector2(-0.13, -0.26)
const RAKE_STANCE_BACK := Vector2(0.13, 0.09)
const RAKE_STANCE_SECONDS: float = 0.25
const RAKE_STANCE_SPEED: float = 0.75
## In the stance each foot stays put on the ground (world space) until the body
## has carried its spot more than RAKE_STEP_DRIFT (m) away; then it steps, one
## foot at a time, over RAKE_STEP_SECONDS, lifting RAKE_STEP_LIFT (m), landing
## RAKE_STEP_LEAD seconds of the body's motion ahead. A foot the leg comes
## within -RAKE_STEP_STRETCH (m) of not reaching (the lunge carried the hips past
## it) steps up at once, before it can drag; otherwise a foot steps only while the hips are within
## RAKE_STEP_LUNGE_MAX (m) of upright. A foot further off than RAKE_STEP_LOST (a
## teleport, a ride) is put back without a step.
const RAKE_STEP_STRETCH: float = -0.008
## A foot about to be out of reach may start its step once the other foot is this
## far through its own (R1b integration: waiting for it to land let the back foot
## drag a tick, 6 mm, as the lunge came on).
const RAKE_STEP_OVERLAP: float = 0.75
const RAKE_STEP_LUNGE_MAX: float = 0.08
const RAKE_STEP_DRIFT: float = 0.14
const RAKE_STEP_SECONDS: float = 0.17
const RAKE_STEP_LIFT: float = 0.07
const RAKE_STEP_LEAD: float = 0.12
const RAKE_STEP_LOST: float = 0.6
## Leg bones (m): hip to knee, knee to the middle of the shoe; and how far the
## knee flexes as a walking leg swings through (rad at a full stride).
const BODY_THIGH: float = 0.36
const BODY_SHIN: float = 0.4
const BODY_WALK_KNEE: float = 0.55
## A heavy load drags: the head's progress through the drive is slowed at the
## start by up to this power (pow(t, 1 + this x load)), and the tines judder
## sideways by up to RAKE_JUDDER m at RAKE_JUDDER_HZ cycles a drive.
const RAKE_RESIST: float = 0.35
const RAKE_JUDDER: float = 0.012
const RAKE_JUDDER_HZ: float = 7.0
## The return through the air: how high the head lifts (m) to reset.
const RAKE_RESET_LIFT: float = 0.17
## The forward lean at the bottom of the shove (rad, negative is forward) and
## how far the hips go forward into the lunge (m).
const RAKE_LEAN_DRIVE: float = -0.62
const RAKE_LUNGE_DRIVE: float = 0.28
## Secondary motion: the head lags the torso's lean by this share of its
## velocity (s), and the torso overshoots its return by this share.
const RAKE_HEAD_LAG: float = 0.05
const RAKE_SETTLE_OVERSHOOT: float = 0.18
## The head's lag is at most this (rad) and follows over this long (s).
const RAKE_HEAD_LAG_MAX: float = 0.2
const RAKE_HEAD_LAG_SECONDS: float = 0.06
## The knees out of work (player/cartoon_body.gd, rad, negative bends): the
## footless leg tucked up behind while hopping, the front and back shins tucked
## in a jump, and the shins of a body on the ground.
const BODY_HOP_THIGH: float = 0.5
const BODY_HOP_SHIN: float = -1.4
const BODY_JUMP_SHINS := Vector2(-0.75, -0.35)
const BODY_FALLEN_SHIN: float = -0.25
## Third person: the upper hand's spot is this far from the shoulders' middle
## (body space, x right, y up, -z ahead) with the head close in, and at full stretch.
const RAKE_GRIP_NEAR := Vector3(-0.2, -0.12, -0.3)
const RAKE_GRIP_FAR := Vector3(0.08, -0.22, -0.2)
## First person: the head plants this far out (instead of RAKE_HEAD_NEAR) so it
## clears the hotbar, and drives to RAKE_HEAD_FAR + RAKE_FP_FAR_EXTRA.
const RAKE_FP_NEAR: float = 1.45
const RAKE_FP_FAR_EXTRA: float = 0.25
## First person: the eyes go with the lunge (this share of the hips' travel, m,
## and this share of the crouch), and look this far further down (degrees) while
## the rake works, easing in and out over RAKE_FP_LOOK_SECONDS.
const RAKE_FP_LUNGE_SHARE: float = 0.45
const RAKE_FP_CROUCH_SHARE: float = 0.6
const RAKE_FP_LOOK_DEG: float = 7.0
const RAKE_FP_LOOK_SECONDS: float = 0.35
## The windrow (leaves/leaf_movers.gd): a leaf the tines reach rides ahead of
## them while they drive, bunched up to RAKE_RIDE_DEPTH ahead and stacked up to
## RAKE_RIDE_STACK high (more as more ride), rolling; a share spill over the top
## early. Released at the end of the drive (or once its own cell is behind the
## tines), it carries on with RAKE_RIDE_CARRY of the head's speed (the rest its
## own aimed flight; RAKE_RIDE_CARRY_UP of that flight's climb).
const RAKE_RIDE_DEPTH := Vector2(0.04, 0.3)
const RAKE_RIDE_STACK: float = 0.2
const RAKE_RIDE_FULL: int = 60
const RAKE_RIDE_SPILL: float = 0.18
const RAKE_RIDE_STIFF: float = 26.0
## A leaf the tines swept from behind them slides up to the berm at most this
## fast (m/s), along the lawn.
const RAKE_RIDE_SLIDE: float = 3.0
## Leaves already behind the tines when their stroke lands go over this long (s).
const RAKE_SWEEP_STAGGER: float = 0.15
const RAKE_RIDE_CARRY: float = 0.275
const RAKE_RIDE_CARRY_UP: float = 0.5
const RAKE_RIDE_MAX: float = 0.7
## A rider keeps at least this share of its sideways offset across the head; a
## spilling one rides this long (s) before hopping over the top at
## RAKE_RIDE_SPILL_HOP (m/s up), the rest leave at most RAKE_RIDE_SETTLE_HOP up.
## It drops off once its own landing spot is within RAKE_RIDE_DROP_MARGIN (m)
## ahead of it; a rider split in two puts its twin RAKE_RIDE_SPLIT_DEPTH deeper.
const RAKE_RIDE_SPREAD: float = 0.75
const RAKE_RIDE_SPILL_SECONDS := Vector2(0.05, 0.16)
const RAKE_RIDE_SPILL_HOP := Vector2(1.3, 2.1)
const RAKE_RIDE_SETTLE_HOP := Vector2(0.3, 0.8)
const RAKE_RIDE_DROP_MARGIN: float = 0.06
const RAKE_RIDE_SPLIT_DEPTH: float = 0.03
## Riders roll like a leaf this round (m) under the head's speed, rock side to
## side (rad/s, rad a second), and take at most RAKE_RIDE_HEAD_SPEED_MAX m/s of
## the head's speed with them.
const RAKE_RIDE_ROLL_RADIUS: float = 0.07
const RAKE_RIDE_WOBBLE := Vector2(9.0, 0.6)
const RAKE_RIDE_HEAD_SPEED_MAX: float = 9.0
## The head's speed (C4 head_vel, leaves/leaf_motion.gd) counts as zero once its
## pose is older than this (s), or when it is faster than RAKE_HEAD_VEL_JUMP m/s
## (a teleport, not a shove).
const RAKE_HEAD_VEL_STALE: float = 0.1
const RAKE_HEAD_VEL_JUMP: float = 20.0
## Leaves' edges on the lawn (leaves/leaf_shaders.gd litter): each skin leaf reads
## the density this far (m) off its middle, by a slow noise, so a raked edge is
## ragged, not a cell staircase; and a straggler share of skin leaves read their
## neighbours up to LEAF_STRAY_REACH away (each way) at LEAF_STRAY_WEIGHT. The
## shader clamps both reaches to a cell (0.5 m) less two LEAF_TILEs, so every
## read stays inside the 5x5 cells it checks and no leaf is ever cut in two.
const LEAF_EDGE_WARP: float = 0.22
const LEAF_STRAY_SHARE_EDGE: float = 0.07
const LEAF_STRAY_REACH: float = 0.27
const LEAF_STRAY_WEIGHT: float = 0.45

# ---- hotbar hud
# The bar along the bottom of the screen (ui/hotbar_hud.gd; docs/GAME.md "the
# hotbar"). Pixels are at the 1280x720 design size. The bar owns the bottom
# center from the edge up to the job goal line (ui/job_goal.gd, its bottom at
# HOTBAR_GOAL_LINE_Y); the throw meter sits above that (HOTBAR_THROW_METER_Y).
## A slot's size and the gap between slots (px).
const HOTBAR_SLOT_PX: float = 68.0
const HOTBAR_SLOT_GAP: float = 6.0
## How far the slots sit above the bottom edge (px).
const HOTBAR_BOTTOM_MARGIN: float = 8.0
## The selected slot rises this far (px) and grows this much, over this long (s).
const HOTBAR_SELECT_RAISE: float = 8.0
const HOTBAR_SELECT_SCALE: float = 1.06
const HOTBAR_SELECT_SECONDS: float = 0.12
## A refusal ("eh?"): the bar shakes this long (s), this far (px), this fast (Hz).
const HOTBAR_SHAKE_SECONDS: float = 0.25
const HOTBAR_SHAKE_PX: float = 6.0
const HOTBAR_SHAKE_HZ: float = 22.0
## How long the emptied-pockets notice stays up (s). A refusal has no toast
## since x1:text, only the shake.
const HOTBAR_NOTICE_SECONDS: float = 3.0
## Arms full: the slots shrink to this and fade to this, and the hands card
## slides up over this long (s).
const HOTBAR_ARMS_SLOT_SCALE: float = 0.55
const HOTBAR_ARMS_DIM: float = 0.45
const HOTBAR_CARD_SECONDS: float = 0.15
## The job goal line's bottom and the throw meter's top, above the bottom edge (px).
const HOTBAR_GOAL_LINE_Y: float = 122.0
const HOTBAR_THROW_METER_Y: float = 168.0

# ---- raking: sounds (R1 chunk 5)
# audio/leaf_audio.gd plays the rake and leaf sounds from the leaf field's stroke
# events (gap-specs/raking.json contract C6; docs/ART.md "Rake and leaf sounds").
## Rake and leaf one-shots are close sounds: full volume inside this many meters
## and gone past this many (a crewmate raking 10 m away is about 9 dB down).
const RAKE_SFX_UNIT_SIZE: float = 3.5
const RAKE_SFX_MAX_DISTANCE: float = 30.0
## Each play's pitch lands within +-this of normal, and its volume within +-this dB.
const RAKE_SFX_WOBBLE: float = 0.035
const RAKE_SFX_DB_JITTER: float = 1.5
## The least time between two plays of one leaf sound from one source (ms).
const LEAF_SFX_GAP_MS: int = 60
## Density units a stroke moves for a full-strength leaf layer, the tier edges as
## fractions of that (light, medium, heavy), and the least it moves to be heard.
const LEAF_SFX_REF_UNITS: float = 5000.0
const LEAF_SFX_TIERS: Vector2 = Vector2(0.3, 0.9)
const LEAF_SFX_MIN_UNITS: int = 150
## The leaf layer's gain: from this many dB at nothing moved up to 0 at the
## reference, never over the cap.
const LEAF_SFX_GAIN_FLOOR_DB: float = -8.0
const LEAF_SFX_GAIN_CAP_DB: float = 2.0
## Leaves landing and kicked: a landing starts this many dB down (a kick starts
## at LEAF_SFX_GAIN_FLOOR_DB), and both get this many dB louder each time the
## count of leaves doubles, never over 0.
const LEAF_SETTLE_BASE_DB: float = -10.0
const LEAF_SFX_DB_PER_DOUBLING: float = 3.0
## How long the scrape file is (s): its pitch stretches it over the drive (the
## swing's plant to drive_end), within this range.
const RAKE_SCRAPE_SECONDS: float = 0.30
const RAKE_SCRAPE_PITCH: Vector2 = Vector2(0.9, 1.15)
## A swing's length when an event doesn't say (s): two strokes.
const LEAF_SFX_DEFAULT_TEMPO: float = RAKE_STROKE_SECONDS * 2.0
## Where the sounds sit along the stroke: the plant this far behind the request
## origin (where the head lands, m), the flick this far ahead (the end of the
## drive). When they play comes from the swing's phases (LeafAudio.after_bite).
const LEAF_SFX_PLANT_BACK: float = 0.5
const LEAF_SFX_FLICK_AHEAD: float = 0.75
## Leaves landing: at least this many in one place to be heard, at most this many
## settle sounds a second, a whump at most once per this long per 2 m area (s),
## and the least a landing must be to whump.
const LEAF_SETTLE_MIN: int = 3
const LEAF_SETTLE_PER_SECOND: int = 3
const PILE_WHUMP_GAP: float = 0.25
const PILE_WHUMP_MIN: int = 6
const PILE_WHUMP_AREA: float = 2.0
## A bag: the stuffing this long after the bag opens (as the leaves fly in), and
## the tie this long (s): once they're all in, after the stuffing's second whump,
## never on top of it. Then the units of leaves for a full-strength stuffing.
const BAG_STUFF_DELAY: float = 0.15
const BAG_TIE_DELAY: float = 0.7
const BAG_STUFF_REF_UNITS: float = 4000.0
## Footsteps by leaf depth (LeafAudio.step_id): deeper than this is "deep", and
## than this a pile.
const LEAF_STEP_DEEP_DENSITY: int = 60
const LEAF_STEP_PILE_DENSITY: int = 150

# ---- raking: sound sync and mix (R1b rakefeel:sound)
# Where the rake and leaf sounds sit in the mix (docs/GAME.md "Raking: what you
# hear, and when"; audio/sound_bank.gd near_db and muffle_db; audio/sfx.gd).
## Each id's trim (dB) on top of its file's RMS target (tools/sfx_leaves.py),
## set against the yard's music and wind in R1b's recordings: the work is the
## loudest thing in a yard, the crackle sits over the scrape, and the bag's three
## beats land level with each other.
const LEAF_SFX_MIX_DB: Dictionary = {
	"rake_plant": 2.0, "rake_scrape": 1.0, "rake_empty": 0.0,
	"rake_leaves_light": 4.0, "rake_leaves_med": 3.0, "rake_leaves_heavy": 2.0,
	"leaf_flick": 2.0, "hand_scoop": 2.0,
	"bag_open": 2.5, "bag_stuff": -1.0, "bag_tie": 4.5,
	"leaf_settle": 6.0, "pile_whump": 2.0, "leaf_kick": 3.0,
}
## Up close, a rake or leaf sound is at most this many dB over its own volume
## (your own rake is about 1.9 m from your ears: +5 dB at RAKE_SFX_UNIT_SIZE).
const RAKE_SFX_NEAR_DB: float = 6.0
## Distance takes at most this much off their highs (dB at 5 kHz, Godot's
## attenuation filter; its -24 default buried the crackle for anyone not raking).
const RAKE_SFX_MUFFLE_DB: float = -6.0
## The stuffing of the thinnest bag is this many dB under a full one.
const BAG_STUFF_FLOOR_DB: float = -8.0
## A swing this peer is drawing counts as the one a stroke event is about when it
## is within this much of the bite's phase (LeafAudio.after_bite times the rest
## of the swing from it; a stale one, about to be re-phased, is ignored).
const LEAF_SFX_LIVE_PHASE_SLACK: float = 0.05

# ---- balance targets
# What tools/balance_sim.py holds the economy to (docs/BALANCE.md). The game never
# reads these; the simulator's --check does, and the retune (gap balance:E) sets
# the real tuning numbers above so the simulated arc lands inside them.

## Median real hours of play to reach The Lawnfather (tier 40), for a solo crew
## and for four players alike: x at least, y at most.
const ARC_HOURS := Vector2(10.0, 20.0)
## Cumulative real hours to tier I of each rank, the median across seeds; index is
## the rank (0 Rake Rookie, 8 The Lawnfather). Within +-35% is on pace.
const RANK_PACE_HOURS: Array[float] = [0.0, 1.0, 2.5, 4.5, 6.5, 9.0, 11.5, 14.0, 16.0]
## A solo crew's arc may take at most this many times a four-player crew's.
const ARC_SOLO_RATIO_MAX: float = 1.3

# ---- nice boys: Form 27-B (R2 chunk 6)
# Satellite Annex B (net/annex/annex.gd, docs/GAME.md "Form 27-B, in Triplicate"):
# the paperwork errand that replaced Border Return. Times are seconds of server time
# since the Annex began (annex_schedule.gd is a pure function of the seed and these).
## The Annex closes this long after the first walk-in: everyone still inside is
## approved AFTER HOURS and let out. urgent() (the clock speeds up, the lights
## flicker, the escape cue) from ANNEX_URGENT_AT.
const ANNEX_CAP_SECONDS: float = 150.0
const ANNEX_URGENT_AT: float = 120.0
## The event soak's shorter day (--run-event-at), so bot runs end inside the soak.
const ANNEX_CAP_SECONDS_SOAK: float = 50.0
## Boxes on a caught player's form by heat at the catch: ANNEX_BOXES_MIN under
## the first, one more under the second, two more at or over it.
const ANNEX_BOXES_BY_HEAT: Array[float] = [35.0, 70.0]
## Window ids on the back wall: A-C serve every form, D opens once.
const ANNEX_WINDOWS: Array[String] = ["A", "B", "C", "D"]
const ANNEX_SERVING_WINDOWS: Array[String] = ["A", "B", "C"]
## The pictograms the three serving windows draw from (ui/icons.gd ids), three per run.
const ANNEX_WINDOW_ICONS: Array[String] = ["item_rake", "item_leaf_bag", "tool_lawn_mower", "tool_hedge_trimmer"]
const ANNEX_WINDOW_COLORS: Array[Color] = [Color(0.95, 0.55, 0.25), Color(0.36, 0.62, 0.92), Color(0.45, 0.78, 0.4), Color(0.86, 0.42, 0.74)]
## A clerk taking the form, reading it, stamping it and handing it back (R2b:
## 3.4 s, from 2, for the pace and so each beat reads).
const ANNEX_SERVE_SECONDS: float = 3.4
## Standing on a window's counter spot this long asks to be served.
const ANNEX_COUNTER_DWELL: float = 0.4
## Holding interact on a window's stamp this long stamps your own form.
const ANNEX_SELF_STAMP_HOLD: float = 1.0
## A clerk's view cone, in degrees (the host judges with the schedule, not the bodies).
const ANNEX_CLERK_VIEW_DEG: float = 100.0
## A desk bell: the clerk turns to his filing cabinet this long, twitches at
## ANNEX_BELL_TWITCH_AT, and every ANNEX_BELL_EARLY_EVERY-th ring turns back early
## at ANNEX_BELL_EARLY_AT. One ring per window per cooldown.
const ANNEX_BELL_TURN: float = 3.0
const ANNEX_BELL_TWITCH_AT: float = 1.2
const ANNEX_BELL_EARLY_EVERY: int = 3
const ANNEX_BELL_EARLY_AT: float = 1.8
const ANNEX_BELL_COOLDOWN: float = 4.0
## A clerk's routine, (min, max) seconds per segment: open, then a phone call or a
## break (telegraphed first, then the walk back is ANNEX_RETURN_WALK of it).
const ANNEX_OPEN := Vector2(5.0, 9.0)
const ANNEX_PHONE := Vector2(2.0, 4.0)
const ANNEX_BREAK := Vector2(6.0, 10.0)
const ANNEX_TELEGRAPH: float = 0.8
const ANNEX_RETURN_WALK: float = 2.5
## The never-wait guarantee: no clerk is "looking but not serving" longer than this.
const ANNEX_MAX_IDLE: float = 4.0
## Each serving window is open at least this share of the day (annex_test checks).
const ANNEX_MIN_OPEN_SHARE: float = 0.45
## Quirks per run (min, max), on distinct serving windows.
const ANNEX_QUIRKS := Vector2i(1, 2)
## Asleep: his breaks are naps this many times longer, at the counter.
const ANNEX_ASLEEP_SCALE: float = 1.4
## Waking from a bell, before he's serving again.
const ANNEX_WAKE_SECONDS: float = 1.0
## Lunch: on his phone slots he eats, turning round for a bite of this long, then
## chewing with his back turned for ANNEX_LUNCH_CHEW.
const ANNEX_LUNCH_BITE: float = 1.0
const ANNEX_LUNCH_CHEW: float = 2.2
## Copier jam: one break this long at the copier (R2c annex: 20, was 12; the
## walk there and back through the staff door is honest now, about 16 s of it).
const ANNEX_JAM_SECONDS: float = 20.0
## Window D: blinds up once, at a seeded moment in this window, for ANNEX_D_OPEN.
const ANNEX_D_WINDOW := Vector2(35.0, 90.0)
const ANNEX_D_OPEN: float = 8.0
## The Head NICE BOY: at his desk, then away with his back turned (min, max).
const ANNEX_HEAD_DESK := Vector2(12.0, 18.0)
const ANNEX_HEAD_AWAY := Vector2(6.0, 9.0)
## The approval: the big stamp up, a hesitation, then the slam.
const ANNEX_HEAD_WINDUP: float = 0.6
const ANNEX_HEAD_SLAM: float = 0.3
## Carrying the big stamp: move speed scale, and how close a friend must be.
const ANNEX_BIG_STAMP_SLOW: float = 0.7
const ANNEX_BIG_STAMP_REACH: float = 1.5
## The host's check of the Head NICE BOY's view of a lifted stamp, per second.
const ANNEX_STAMP_SPOT_HZ: float = 5.0
## Spotted: he walks over with his hand out this long, and the escape cue plays.
const ANNEX_SPOTTED_WALK: float = 2.0
const ANNEX_SPOTTED_ESCAPE: float = 6.0
## The co-signer sheet: hold interact this long (visitors only).
const ANNEX_COSIGN_HOLD: float = 1.5
## The turnstile turns this long for an approved form.
const ANNEX_TURNSTILE_OPEN: float = 2.0
## Requests carry the client's server time, clamped to now minus this.
const ANNEX_GRACE: float = 0.25
## A wrong window's head shake costs this long before he looks at you again.
const ANNEX_WRONG_WINDOW: float = 1.5
## OQ-027: the return shuttle waits for the whole cohort.
const ANNEX_FINISH_AS_GROUP: bool = true
## Out faster than this (seconds from the walk-in) earns the fast quip.
const ANNEX_FAST_SECONDS: float = 60.0
## XP for a finished form (the paperwork), banked at bedtime like other XP.
const XP_PAPERWORK: int = 15
## Every this many visits the Greeter hands over a Fast Pass: the first box comes pre-stamped.
const ANNEX_FAST_PASS_EVERY: int = 5
## BAL-28: a catch costs only time. Kept as constants for Taylan; never shown as a
## charge while both are 0.
const ANNEX_FEE_BASE: int = 0
const ANNEX_FEE_PER_HEAT: float = 0.0
## The walk-in behind the Greeter, curb to threshold, before the clipboard; the
## riders are staged behind him this long after the begin (after the zone move),
## and he turns to lead them in this long after it, once he's waved them over.
const ANNEX_GREETER_WALK: float = 5.0
const ANNEX_WALK_STAGE_DELAY: float = 0.25
const ANNEX_WALK_LEAD_DELAY: float = 1.6
## Reach to each spot (meters, to the player's feet): a counter spot (measured to
## the capsule edge, the spec's 0.6 m), the queue behind it, a stamp, a bell, the
## desk, the tray, the co-signer sheet, a door.
const ANNEX_COUNTER_REACH: float = 0.9
const ANNEX_QUEUE_REACH: float = 2.6
const ANNEX_STAMP_REACH: float = 1.1
const ANNEX_BELL_REACH: float = 1.3
const ANNEX_DESK_REACH: float = 1.6
const ANNEX_TRAY_REACH: float = 1.3
const ANNEX_SHEET_REACH: float = 1.3
const ANNEX_DOOR_REACH: float = 2.0
## The host's slack on those reaches, for a client's lag: a one-off ask
## (ANNEX_REACH_SLACK), a hold kept going or the big stamp lifted or used
## (ANNEX_HOLD_SLACK), the big stamp put back or a visitor door (ANNEX_LOOSE_SLACK).
## So a counter ask is honoured to 1.25 m from the feet: the spec's 0.6 m capsule
## edge is the local spot, the slack is for the 150 ms the ask spends travelling.
const ANNEX_REACH_SLACK: float = 0.35
const ANNEX_HOLD_SLACK: float = 0.4
const ANNEX_LOOSE_SLACK: float = 0.6
## The turnstile: walking within ANNEX_GATE_REACH of it asks it to turn (the host
## allows ANNEX_REACH_SLACK more); a rider is through once ANNEX_TURNSTILE_PASS_DEPTH
## past it on the forecourt side, within ANNEX_TURNSTILE_PASS_WIDTH of it; the bar
## stays out of the opener's way ANNEX_TURNSTILE_PASS_SLACK past its turn.
const ANNEX_GATE_REACH: float = 1.0
const ANNEX_TURNSTILE_PASS_DEPTH: float = 0.45
const ANNEX_TURNSTILE_PASS_WIDTH: float = 4.0
const ANNEX_TURNSTILE_PASS_SLACK: float = 0.6
## One tray ask per player per this long.
const ANNEX_TRAY_ASK_GAP: float = 0.8
## A clerk's notice of a hand on his stamp (the smile, the carbon slid in this far into it).
const ANNEX_NOTICE_SECONDS: float = 1.4
const ANNEX_NOTICE_CARBON_AT: float = 0.5
## Window D's volley: he spins round and winds up (ANNEX_VOLLEY_STAMP_AT, the
## stamp starting down), then one slam per box CLERK_VOLLEY_GAP apart, and the
## blinds drop ANNEX_VOLLEY_SECONDS after the last.
const ANNEX_VOLLEY_SECONDS: float = 0.9
const ANNEX_VOLLEY_STAMP_AT: float = 0.55
## A serve's beats, seconds into ANNEX_SERVE_SECONDS: he takes the form, peers at
## it (ANNEX_SERVE_READ_AT), lifts his stamp, brings it down (ANNEX_SERVE_STAMP_AT:
## the ink and the KA-CHUNK land ANNEX_STAMP_HIT later), hands it back.
const ANNEX_SERVE_TAKE_AT: float = 0.4
const ANNEX_SERVE_READ_AT: float = 0.85
const ANNEX_SERVE_LIFT_AT: float = 1.95
const ANNEX_SERVE_STAMP_AT: float = 2.3
const ANNEX_SERVE_HAND_AT: float = 2.85
## A visitor goes through the door this long into the door-swing iris.
const ANNEX_DOOR_IRIS_WAIT: float = 0.4
## The first light row goes off this long after closing.
const ANNEX_LIGHTS_OFF_DELAY: float = 2.9
## A waiting client asks again this often.
const ANNEX_RETRY_SECONDS: float = 0.5
## After closing, anyone still inside goes out this long later.
const ANNEX_CLOSING_OUT: float = 8.0
## The light rows clunk off this far apart, back of the room first.
const ANNEX_LIGHT_ROW_OFF_GAP: float = 0.3
## The receipt in your hands after the turnstile.
const ANNEX_RECEIPT_SECONDS: float = 4.0
## Without the Shuttle (chunk 4): the finishers wait this long in the forecourt
## before going back (the group waits for the last one first).
const ANNEX_RETURN_WAIT: float = 2.0
## Immunity after the drop-off without the Shuttle.
const ANNEX_DROP_IMMUNITY: float = 6.0
## The schedule is generated this far ahead (seconds), then repeats its last day.
const ANNEX_SCHEDULE_HORIZON: float = 240.0
## The legacy map's Courtesy Desk door, in StoreZone space, by the Homie Depot
## curb (outside every STORE_LAYOUT reservation), and the way it faces.
const ANNEX_STORE_DOOR := Vector3(-16.0, 0.0, 17.0)
const ANNEX_STORE_DOOR_YAW: float = 0.0
## The town's Field Office front door, in the office's own space (town_dressing.gd).
const ANNEX_FIELD_OFFICE_DOOR := Vector3(0.0, 0.0, 5.0)
## A player body spawned before its name reached this peer waits this long for
## it before dressing anyway (player.gd _dress_up: looks come from the name).
const DRESS_NAME_WAIT_SECONDS: float = 2.0

# ---- art
# The neighborhood looks (docs/ART.md "Houses and the kit", docs/DECISIONS.md
# "Houses are batched by HouseKit"). Budgets are triangle counts, checked from
# the "triangles" metas the builders record (headless safe).
const ART_PROP_MAX_TRIANGLES: int = 2000
const ART_HOUSE_MAX_TRIANGLES: int = 6000
const ART_TREE_MAX_TRIANGLES: int = 7000
const ART_TREE_FAR_MAX_TRIANGLES: int = 900
## Trees swap to their far mesh past this many meters (with this much fade margin).
const ART_TREE_LOD_DISTANCE: float = 55.0
const ART_TREE_LOD_MARGIN: float = 6.0
## The day before a season turns, trees build their next season's meshes ahead,
## spending at most about this many milliseconds a frame (one build always fits).
const ART_TREE_PREWARM_MS_PER_FRAME: float = 4.0
## Props shorter than this are "small": they fade out sooner and cast no shadow.
const ART_SMALL_PROP_HEIGHT: float = 0.7
const ART_SMALL_PROP_RANGE: float = 60.0
const ART_MEDIUM_PROP_RANGE: float = 140.0
## Props fade out over this many meters at the end of their range
## (props/prop_catalog.gd fade()); props this long on any side never fade.
const ART_PROP_FADE_MARGIN: float = 6.0
const ART_LARGE_PROP_SIZE: float = 8.0
## Repeated props are batched into MultiMeshes per square chunk this many meters wide.
const ART_PROP_CHUNK: float = 32.0
## Draw-call proxies: GeometryInstance3Ds under a street block and under a yard's
## dressing, about 1.15x the most --art-test measured over every hood, size and
## season (art chunk 7: a block 567, Dandelion Acres in winter; a yard 154, Oak
## Hollow's big yard in spring, its house's own season decor included). Every tree
## draws two meshes (its near Look and its far LookFar), so a tree counts twice.
const ART_BLOCK_MAX_VISUALS: int = 652
const ART_YARD_MAX_VISUALS: int = 177
const ART_NEIGHBOR_LEAF_PATCHES: int = 3
const ART_STRING_LIGHT_SPACING: float = 0.45
const ART_GRASS_WINTER_SPACING_SCALE: float = 1.6
## The sliding doors part for anyone this close to the doorway (m), over this
## long (s). Walking (5 m/s) from a standstill just outside, you meet them open.
const ART_DOOR_OPEN_DISTANCE: float = 4.2
const ART_DOOR_OPEN_SECONDS: float = 0.5
## Chefty's lane in lot space (x, z, width, depth), kept clear of props.
const ART_CHEFTY_LANE: Rect2 = Rect2(-75.0, 22.6, 83.0, 4.4)
## The house footprint contract (levels/town/house_builder.gd): how far past the
## width/2 and depth/2 box a house may reach to the sides, the back (the roof's
## overhang), and the front (porch and steps). The lot generator reserves
## x +-(w/2 + 0.6) and z -d/2-0.6 .. d/2+3.0 around its house.
const ART_HOUSE_SIDE_REACH: float = 0.6
const ART_HOUSE_BACK_REACH: float = 0.7
const ART_HOUSE_FRONT_REACH: float = 2.6
## How far a HouseSpec gutter or eave line keeps from a wall solid or a roof
## blocker (levels/town/house_archetypes.gd _clear_lines), and the shortest
## piece of one worth keeping after it is split around them, in meters.
const ART_HOUSE_LINE_CLEARANCE: float = 0.1
const ART_HOUSE_MIN_LINE: float = 0.4

# ---- art:8 Homie Depot's walk-in lobby and lot, and the country road
# (levels/dressing/store_dressing.gd, store_interior.gd, props/sliding_doors.gd,
# levels/dressing/countryside.gd; docs/GAME.md "Homie Depot, inside and out").
## The sliding doors: how long someone must be near before they part (the
## sensor's beat), how long everyone must be clear before they close, how far
## ahead a runner is seen (s of their speed), and how much quieter the closing
## hiss is than the opening one (dB). Distance and slide time are ART_DOOR_* above.
const ART_DOOR_SENSE_SECONDS: float = 0.06
## The opening slide's curve is skewed this early (t^skew into a smootherstep):
## under 1 it gets going sooner and still eases into its stop.
const ART_DOOR_OPEN_SKEW: float = 0.7
const ART_DOOR_HOLD_SECONDS: float = 1.1
const ART_DOOR_LEAD_SECONDS: float = 0.35
const ART_DOOR_CLOSE_DB: float = -5.0
## Open doors stay open while anyone up to this much further out than
## ART_DOOR_OPEN_DISTANCE (m) is closing on the doorway at this speed or more
## (m/s) and would be in range within this many seconds at that pace, so
## stragglers never see them shut and part again in their face.
const ART_DOOR_WATCH_MARGIN: float = 9.0
const ART_DOOR_APPROACH_SPEED: float = 1.0
const ART_DOOR_HOLD_AHEAD_SECONDS: float = 2.0
## The sensor tracks each player's velocity from how they moved, smoothed at this
## rate (1/s); a jump faster than this (m/s) is a teleport, not a walk.
const ART_DOOR_TRACK_RATE: float = 10.0
const ART_DOOR_TRACK_MAX_SPEED: float = 14.0
## The vehicle-only stop just outside the doors (store_dressing.gd): Chefty's
## chassis (Constants.VEHICLE_LAYER) meets it, people never do. Its bottom and
## top (m); the chassis rides 0.45 to 1.95 m.
const ART_DOOR_VEHICLE_STOP_Y := Vector2(0.35, 1.15)
## The doorway: its width (four abreast fit through) and height (m).
const ART_DOOR_WIDTH: float = 5.0
const ART_DOOR_HEIGHT: float = 3.0
## The lobby's ceiling lights: how far they reach (m) and how bright.
const ART_LOBBY_LIGHT_RANGE: float = 7.0
const ART_LOBBY_LIGHT_ENERGY: float = 1.1
## How bright the ceiling's glow panels are.
const ART_LOBBY_PANEL_ENERGY: float = 1.4
## The country road's power line: a pole every this many meters this far off the
## road's middle, the wires merged into one mesh per this many meters of road.
const ART_COUNTRY_POLE_SPACING: float = 40.0
const ART_COUNTRY_POLE_OFFSET: float = 6.5
const ART_COUNTRY_WIRE_RUN: float = 200.0

# ---- shops: tiers and consumables in play
# Tool tiers and the crew's bags and gas at work (gap shops chunk 3; the rest of
# the shop numbers are under "# ---- shops" above; core/tool_tiers.gd reads them).

## A running engine's pitch by tier (0 used, 1 stock, 2 Mk II, 3 Mk III): used
## rattles high, Mk III purrs low. Volume per tier is TOOL_TIER_VOLUME_DB.
const TOOL_TIER_PITCH: Array[float] = [1.08, 1.0, 1.0, 0.92]
## How long an out-of-bags or out-of-gas notice stays over your head (s).
const SUPPLY_NOTICE_SECONDS: float = 3.0
## The least spare gas (gallons, after every tank is filled) worth sending the
## red gas can along with (levels/world.gd _spawn_job_tools).
const GAS_CAN_MIN_GALLONS: float = 1.0

# ---- shops: UI, keepers and shelves
# The shop window, the shopkeepers and the stock you can see (gap shops chunk 4:
# ui/shop_window.gd, npcs/store_clerk.gd, props/shelf_stock.gd,
# levels/dressing/shop_sites.gd). Where each shop stands is SHOP_SITES above.
## How long the shop window's answer to a buy ("Sold out", "Bought: ...") stays up (s).
const SHOP_TOAST_SECONDS: float = 2.6
## The quantity buttons on a supply's card.
const SHOP_QTY_STEPS: Array[int] = [1, 5]
## A shopkeeper turns to look at, and greets, anyone this close (m). You shop
## from SHOP_REACH.
const KEEPER_NOTICE_RANGE: float = 7.0
## How long before a keeper greets the same player again (s).
const KEEPER_GREET_COOLDOWN_SECONDS: float = 8.0
## Each keeper's babble pitch: Rusty low and slow, Dot high and chirpy.
const KEEPER_VOICE_PITCH: Dictionary = {"marty": 1.0, "rusty": 0.75, "dot": 1.3}
## How close to a shelf slot you look at it, and E opens the catalog on it (m).
const SHELF_LOOK_REACH: float = 1.6
## Slots whose front spots are this close to the nearest one count as the same
## stack (one shelving unit's levels); among them you look at the level your
## head points at (m).
const SHELF_STACK_TOLERANCE: float = 0.3
## Eye height above the feet when a player has no Head node to measure (m).
const SHELF_EYE_HEIGHT: float = 1.55
## The most boxes of a supply a shelf slot shows: one per unit left today.
const SHELF_MAX_UNITS: int = 12
## How long after the register the cash drawer slams shut (s).
const SHOP_DRAWER_DELAY_SECONDS: float = 0.35

# ---- art blocks
# The parcel, street and block builders (levels/town/lot_builder.gd,
# street_builder.gd, block_builder.gd, set_pieces.gd, season_dressing.gd; art chunk 5).
## A parcel's depth, street edge to back edge (the job yard's 40 m: its front is at +20).
const ART_PARCEL_DEPTH: float = 40.0
## How far a parcel's lawn, drive and walk boxes sit above (top) its origin, so the
## lawn never fights the Surroundings ground (top -0.02) or the job yard's floor (0).
const ART_LAWN_TOP: float = -0.005
const ART_DRIVE_TOP: float = 0.05
const ART_WALK_TOP: float = 0.04
## Draw calls one house may make (levels/town/house_builder.gd; HouseKit paints per vertex).
const ART_HOUSE_MAX_DRAW_CALLS: int = 10
## Tries per prop when a parcel looks for a free spot on its lawn.
const ART_PARCEL_SPOT_TRIES: int = 16
## How many violation flags on a block show their NOTICE OF VIOLATION words, nearest
## the job first (levels/town/block_builder.gd _labels; the rest batch). The rebel
## flamingo's three always do, on top of these.
const ART_VIOLATION_LABELS: int = 3
## A far-side parcel whose house would sit within this many meters of the NICE BOYS
## van's way out (the lot's PI * 0.75 corridor, levels/world.gd) is left a vacant lot.
const ART_VAN_CORRIDOR_HALF: float = 13.0
const ART_VAN_ANGLE: float = PI * 0.75
## Mansion Hill's far side sits up on a terrace this tall (levels/town/set_pieces.gd).
const ART_TERRACE_HEIGHT: float = 3.0
## Where Lakeside's shore is (lot z) and how far the lake reaches past it.
const ART_LAKE_SHORE_Z: float = -30.0
const ART_LAKE_LENGTH: float = 230.0
## The back boundary wall or fence behind the yards (lot z).
const ART_BACK_BOUNDARY_Z: float = -24.0
## Street trees and lamps keep this far from each other along the street, in meters.
const ART_STREET_TREE_SPACING: float = 24.0
## Cars parked along a block's street (the far lane; the near lane only past
## where Chefty parks, x > ART_NEAR_PARKING_FROM_X).
const ART_STREET_CARS: int = 3
const ART_NEAR_PARKING_FROM_X: float = 12.0
## Speed bumps only where Chefty never drives (lot x > this).
const ART_SPEED_BUMP_FROM_X: float = 12.0
## Grass across a block: the square's half size and the tuft spacing (props/grass.gd).
const ART_BLOCK_GRASS_HALF: float = 70.0
const ART_BLOCK_GRASS_SPACING: float = 0.48

# ---- settings:4
## How long a quip caption stays up at the bottom left (ui/quip_player.gd).
const QUIP_CAPTION_SECONDS: float = 4.5

# ---- icons
# The catalog windows' icon motion (ui/catalog_look.gd; icons chunk D).
## Hovering a shop card bounces its shelf icon up to this scale, over this long.
const ICONS_HOVER_SCALE: float = 1.08
const ICONS_HOVER_SECONDS: float = 0.12
## A confirmed buy squash-pops the item's icon: this much wider then taller, over this long.
const ICONS_POP_STRETCH: float = 0.22
const ICONS_POP_SECONDS: float = 0.3
# The phone's and the HUD's icon motion (ui/phone.gd, ui/day_hud.gd, ui/task_list.gd,
# ui/heat_meter.gd, ui/ui_root.gd; icons chunk E).
## A tapped phone dock tile dips to this scale, then springs back with an overshoot.
const ICONS_DOCK_PRESS_SCALE: float = 0.86
const ICONS_DOCK_PRESS_SECONDS: float = 0.06
const ICONS_DOCK_SETTLE_SECONDS: float = 0.24
## Above this heat share the heat meter's siren rocks, up to this many radians,
## at this many radians of phase per second (the same pulse as its bar). The
## rock fades in over ICONS_SIREN_RAMP of share, so it never snaps on.
const ICONS_SIREN_FROM: float = 0.8
const ICONS_SIREN_RAMP: float = 0.06
const ICONS_SIREN_ROCK_RAD: float = 0.14
const ICONS_SIREN_SPEED: float = 8.0
## How fast the job list glides to sit under the HUD rows when they grow or
## shrink (1/s; an exponential approach, never a snap).
const ICONS_HUD_FOLLOW_RATE: float = 12.0
## The day HUD's rank block fades out over this long when the phone comes out
## over it, and back in when it's put away.
const ICONS_HUD_FADE_SECONDS: float = 0.15
# The interaction prompt pill and the money popup's coin (ui/interaction_prompt.gd,
# ui/money_popup.gd; icons chunk F).
## The pill fades in over this long when something can be done, and out over
## this long (where it was) when nothing can.
const ICONS_PROMPT_FADE_IN: float = 0.12
const ICONS_PROMPT_FADE_OUT: float = 0.1
## It grows in from this scale as it fades in, overshooting a touch before it settles.
const ICONS_PROMPT_APPEAR_SCALE: float = 0.82
## New words while it's up bump it to 1 + this, settling at this rate (1/s).
const ICONS_PROMPT_BUMP: float = 0.07
const ICONS_PROMPT_BUMP_RATE: float = 14.0
## When the thing it's over changes (its point moves more than this many meters
## in one frame) it glides over to the new one at this rate (1/s), never jumps.
const ICONS_PROMPT_RETARGET_M: float = 0.5
const ICONS_PROMPT_GLIDE_RATE: float = 16.0
## The pill keeps this many pixels inside the screen's edges.
const ICONS_PROMPT_EDGE_PX: float = 12.0
## ...and this many pixels clear of words over someone's head (a NICE BOY's
## bubble, a keeper's caption or name), stepping up out of their way.
const ICONS_PROMPT_AVOID_GAP_PX: float = 6.0
## The "Hide" pill floats this far (m) over the top of a hiding spot, above the
## part of it nearest you (this far in from its edges), and never higher than
## this over the ground: a shed's door, not its roof (net/components/hide_spot.gd
## prompt_point).
const ICONS_PROMPT_HIDE_ABOVE: float = 0.12
const ICONS_PROMPT_HIDE_INSET: float = 0.3
const ICONS_PROMPT_HIDE_MAX_Y: float = 1.9
## The "+$9" popup's coin: its height in the label's own pixels, the gap between
## it and the text, how fast it spins (rad/s), and how thin it gets edge-on (a
## coin has a rim; it never vanishes to a line).
const ICONS_COIN_PX: float = 40.0
const ICONS_COIN_GAP_PX: float = 8.0
const ICONS_COIN_SPIN: float = 10.0
const ICONS_COIN_EDGE_WIDTH: float = 0.14

# ---- art: the job yard
# The job yard in its neighborhood's style (levels/lots/lot_generator.gd; art chunk 6).
## The yard's own trees are never shorter than this (m), whatever the hood's trees are:
## they are what buries the lawn in leaves.
const ART_YARD_TREE_MIN_HEIGHT: float = 6.5
## The fewest clear_roof spots a job house of each yard size (small, regular,
## big) may have, whatever its archetype: about the old box house's 12 and 20,
## since the task pays the same flat rate. --layout-test checks it.
const ART_YARD_ROOF_SPOTS_MIN: Array[int] = [10, 10, 16]
## How close two roof-leaf spots on one slope may sit (m), when spots blocked by
## a dormer or chimney slide to free roof.
const ART_YARD_ROOF_SPOT_GAP: float = 0.9
## How far past the house's rectangle the flower beds may reach (m): the deepest
## porch (ART_HOUSE_FRONT_REACH) plus a bed and its tire edging. Always kept
## clear in front of every house, so where a hood's door puts the beds never
## changes where a tree, a hiding spot or litter lands.
const ART_YARD_BED_STRIP: float = 1.5
## The front walk's width (m), and how far a bed's inner edge stays from the
## walk's middle (0.45 m of lawn between them).
const ART_YARD_WALK_WIDTH: float = 1.3
const ART_YARD_BED_FROM_WALK: float = 1.1
## Beds side by side keep this much lawn between them (m).
const ART_YARD_BED_GAP: float = 0.4
## The least room a side of the walk needs to hold a (shortened) bed of its own (m).
const ART_YARD_BED_MIN_LENGTH: float = 1.2
## The job house's autumn mums pot stands in its bed, at the back by the porch:
## its center this far in from the bed's back and side edges (m), and at least
## this far (xz) from every weed, so it never hides one. No clear spot, no pot.
const ART_JOB_MUMS_INSET: float = 0.32
const ART_JOB_MUMS_WEED_CLEAR: float = 0.45
## The job yard's winter snow piles, from the house end of its drive (parcel
## space): on the drive's edges, clear of the lawn's litter, the tools by the
## drive and the homeowner's spot at the curb.
const ART_JOB_SNOW_PILES: Array[Vector3] = [Vector3(-2.45, 0.0, 6.0), Vector3(2.45, 0.0, 10.5)]

# ---- cast: the van and the beacon
# The NICE BOYS' Courtesy Shuttle (props/nice_van.gd) and Courtesy Flare
# (npcs/arrival_beacon.gd); cast chunk 5, docs/GAME.md "2026-11-02, the Courtesy Shuttle".
## The van pulls up over the last this many seconds of the warning, parking as the
## crew arrives (net/run_events/van_arrival.gd)...
const VAN_ARRIVE_SECONDS: float = 5.0
## ...from this far down the street (m)...
const VAN_ARRIVE_DISTANCE: float = 60.0
## ...cruising for this share of the time, then braking evenly to the curb.
const VAN_ARRIVE_CRUISE_SHARE: float = 0.55
## Leaving without anyone (the crew gave up): it pulls away at this (m/s^2), and is
## gone after this many seconds.
const VAN_LEAVE_ACCEL: float = 4.0
const VAN_LEAVE_SECONDS: float = 7.0
## The ride leaving with riders (net/components/ride.gd) pulls out from the curb at
## this (m/s^2) for this long (s) before making up the ride's distance, instead of
## popping to speed.
const VAN_PULL_ACCEL: float = 6.0
const VAN_PULL_SECONDS: float = 1.6
## It drives straight along the curb this far (m) before bending away toward the border.
const VAN_LEAD_OUT: float = 8.0
## The body sways on its springs: radians of lean per m/s^2, at most this much, with
## this spring stiffness and damping (one overshoot when it stops).
const VAN_SWAY_PER_ACCEL: float = 0.005
const VAN_SWAY_MAX: float = 0.035
const VAN_SWAY_STIFFNESS: float = 140.0
const VAN_SWAY_DAMPING: float = 9.0
## Braking harder than this (m/s^2) lights the brake lights; the taillights' glow
## when cruising and when braking.
const VAN_BRAKE_LIGHT_ACCEL: float = 1.5
const VAN_TAIL_GLOW: float = 1.2
const VAN_BRAKE_GLOW: float = 5.0
## The amber dome's pulse, per second.
const VAN_DOME_PULSE_HZ: float = 1.1
## A van moving farther than this in one physics tick was placed, not driven: its
## wheels and springs ignore it.
const VAN_TELEPORT_METERS: float = 6.0
## The arrival beacon's Daisy Seal spins this fast (rad/s) when the warning starts
## and when the crew arrives.
const BEACON_SPIN_MIN: float = 0.6
const BEACON_SPIN_MAX: float = 5.0
## Its ring of traffic cones (m), the courtesy notices fluttering down around it,
## from how high (m) and how long each fall takes (s, from..to).
const BEACON_CONE_RING: float = 1.6
const BEACON_NOTICES: int = 8
const BEACON_NOTICE_HEIGHT: float = 10.0
const BEACON_NOTICE_FALL := Vector2(3.0, 5.0)
## When the crew arrives the beacon folds away over this long (s) instead of vanishing.
const BEACON_DISMISS_SECONDS: float = 0.6

# ---- bags: throw into Chefty
# Tossing leaf bags into Chefty's bed with G (net/components/bed_toss.gd,
# net_prop.gd, props/truck_bed_load.gd, ui/toss_arc.gd; docs/GAME.md "Tossing
# bags into Chefty"). Bed heights are in the bed's own space (its floor's top at
# 1.05, the rails at 1.65). No words anywhere: the arc, the thump and the pile say it.
## A leaf bag is lobbed two-handed, not flung, from where it hangs in your hands
## (when nobody holds it, its bottom from this high, this far in front of you, m);
## it passes through you for this long (s) on its way out.
const BAG_TOSS_RELEASE_HEIGHT: float = 0.85
const BAG_TOSS_RELEASE_FORWARD: float = 0.55
const BAG_TOSS_CLEAR_SECONDS: float = 0.35
## Set down (a tap of G), it plops out of your hands this fast forward and up (m/s).
const BAG_SET_DOWN_PUSH: float = 1.6
const BAG_SET_DOWN_LIFT: float = 1.0
## A client draws its own toss flying at once (net_prop.gd _predict_toss). If it
## drew it going in and the host hasn't said so this long after (s), it lets go
## of the guess; easing back onto the host's bag takes this long (s).
const BAG_TOSS_PROVISIONAL_SECONDS: float = 0.8
const BAG_TOSS_BLEND_SECONDS: float = 0.2
## A bag's price tag hides while it moves faster than this (m/s): thrown, not lying.
const BAG_TOSS_LABEL_HIDE_SPEED: float = 1.5
## Its speed along the ground at no wind-up and at a full one (m/s); a full
## (LEAF_BAG_MAX_KG) bag goes this share as fast as an empty one.
const BAG_TOSS_SPEED_MIN: float = 1.6
const BAG_TOSS_SPEED_MAX: float = 7.5
const BAG_TOSS_HEAVY_SHARE: float = 0.72
## Its speed upward: this much, plus this share of its speed along the ground,
## so a soft toss is a high lob and a full wind-up carries about 10 m. From the
## bed's middle: 2 m goes in at any wind-up (a hop over the side), 3 m from a
## tap to about 1.0 s, 4 m from 0.4 s, 6 m from 0.7 s up (toss survey, 2026-11-02).
const BAG_TOSS_LIFT: float = 3.9
const BAG_TOSS_LIFT_PER_SPEED: float = 0.33
## A client says where it stood when it let go (for a leaf bag, where the bag
## left its hands); the host believes it within this far of where it has them
## (m), so a throw at 150 ms leaves from where the thrower saw it leave.
const THROW_FROM_TOLERANCE: float = 2.0
## The catch (bed_toss.gd catches()): the bed's box, and on the way down
## everything over the open bed up to this high; plus this far past the side
## walls and the tailgate (a tumbling bag's side meets the wall about there),
## there only with the bag's bottom at least this high, on its way down or
## heading in over the rail. Lower than that it bonks the wall. The margin is a
## tumbling bag's corner past the wall's outside (its box's half diagonal, 0.5,
## plus the wall, 0.13, plus a hair): with less, a bag turned corner-first
## caught the rail before the catch and bonked off a toss that looked in.
const BED_CATCH_TOP_Y: float = 3.9
const BED_CATCH_SIDE_MARGIN: float = 0.68
const BED_CATCH_RAIL_Y: float = 1.4
## A bag tossed with its middle this close past a side wall or the tailgate (m)
## can't arc over the rail from there, so one that would bonk the side hops in
## over it instead. Out to here: from closer than about 2.8 m to the bed's middle
## no lob clears the rail (toss survey, 2026-11-02), so with less there was a
## band where no wind-up went in.
const BED_CLOSE_REACH: float = 1.4
## Aim help for a near miss (bed_toss.gd assist()): the smallest nudge that puts
## it in, turned by at most this much (rad) toward the bed's middle and thrown
## at most this share softer or harder. A throw aimed more than
## BED_ASSIST_WINDOW times the turn away is left alone.
const BED_ASSIST_MAX_YAW: float = 0.14
const BED_ASSIST_MAX_SPEED_SHARE: float = 0.15
const BED_ASSIST_WINDOW: float = 2.0
## A caught bag glides into its spot in the load in this long (s): this much
## per meter it has to go, within these bounds. It lands moving down this fast
## (m/s), and sits there this long before it is part of the stack.
const BED_SETTLE_SECONDS_PER_M: float = 0.25
const BED_SETTLE_MIN_SECONDS: float = 0.22
const BED_SETTLE_MAX_SECONDS: float = 0.65
const BED_SETTLE_LAND_SPEED: float = 2.5
const BED_SETTLE_HOLD_SECONDS: float = 0.35
## A bag that has to go over the rail (heaved in from beside the truck, or
## caught just past a wall) clears it, and the cab, by this much (m).
const BED_SETTLE_CLEARANCE: float = 0.08
## Walking up and pressing E: the bag leaves your hands this fast upward (m/s)
## on its little hop into the bed.
const BED_HAND_IN_LIFT: float = 3.2
## A full Chefty bats a bag back out: this fast back the way it came and this
## fast up (m/s), at most this often (s) for one bag.
const BED_REFUSE_PUSH: float = 3.2
const BED_REFUSE_LIFT: float = 4.0
const BED_REFUSE_EVERY_SECONDS: float = 0.8
## A toss from at least this far (m) that goes in gets a crew reaction now and
## then: this share of the time, at most once in this long (s).
const BED_LONG_TOSS_METERS: float = 5.0
const BED_LONG_TOSS_QUIP_CHANCE: float = 0.4
const BED_LONG_TOSS_QUIP_SECONDS: float = 20.0
## A crewmate reacts only if they're this close to the bed (m), in the same zone.
const BED_LONG_TOSS_WITNESS_METERS: float = 25.0
## A tossed bag tumbles end over end this fast (rad/s, picked between the two;
## a throwing client draws its own at the middle). A full bed bats one back out
## spinning this fast.
const BAG_TOSS_SPIN_MIN: float = 2.5
const BAG_TOSS_SPIN_MAX: float = 4.0
const BED_REFUSE_SPIN_MIN: float = 3.0
const BED_REFUSE_SPIN_MAX: float = 5.0
## A throwing client's drawn toss, once down, waits for the host's bag to come
## within this far (m), or this long (s), before easing onto it.
const BAG_TOSS_CATCH_UP_M: float = 0.35
const BAG_TOSS_CATCH_UP_SECONDS: float = 1.0
## A client seeing a bag caught while it moves slower than this (m/s) takes it
## as heaved in from someone's hands (E by the bed).
const BED_HEAVE_SPEED: float = 1.0
## The arc preview while winding up (ui/toss_arc.gd): a dot this often along
## the flight (s), and the longest flight it draws (s).
const TOSS_ARC_STEP_SECONDS: float = 0.06
const TOSS_ARC_MAX_SECONDS: float = 2.5
# ---- niceboys:4 the Courtesy Shuttle
# One van per trip from pull-up to drop-off (net/run_events/shuttle.gd, props/nice_van.gd,
# props/van_gestures.gd; docs/GAME.md "The Courtesy Shuttle, door to door").
## The sliding door's slide, a rider's step up into (or down out of) a seat, the buckle.
const VAN_DOOR_SLIDE: float = 0.6
const VAN_STEP_SECONDS: float = 0.6
const VAN_BUCKLE_SECONDS: float = 0.5
## The back doors' swing, for a straggler (s).
const VAN_BACK_DOOR_SWING: float = 0.5
## Pulling out with riders: up to a lawful cruise (m/s) at this (m/s^2), after
## cast:5's pull from the curb (VAN_PULL_SECONDS at VAN_PULL_ACCEL).
const VAN_CRUISE: float = 12.0
const VAN_CRUISE_ACCEL: float = 3.0
## Nothing anyone can see ever moves faster than this (m/s); the arrival cruises
## just under it and brakes at VAN_BRAKE_DECEL (m/s^2) to the curb.
const VAN_MAX_SCREEN_SPEED: float = 14.0
const VAN_ARRIVE_SPEED: float = 13.5
const VAN_BRAKE_DECEL: float = 4.5
## Every leg of a trip is scheduled this far ahead (s), so a 150 ms client never
## sees one start late and rewind.
const VAN_PLAN_LEAD: float = 0.3
## Riders: the cab shot (VAN_RIDE_MONTAGE_AT) for VAN_RIDE_MONTAGE (s), then the
## iris (VAN_IRIS_SECONDS).
const VAN_RIDE_MONTAGE: float = 3.0
const VAN_IRIS_SECONDS: float = 0.35
## A van this far from someone (m) is out of their sight whatever's between; routes
## start and end at least this far from everyone on the yard.
const VAN_HIDE_METERS: float = 90.0
## A route end nobody's looked away from in this long (s) is left anyway: the van
## stays drawn there for whoever still sees it (each peer hides its own copy).
const VAN_HIDDEN_CAP: float = 8.0
## Where it parks: a box this big (m, x y z in the van's space) must be clear,
## sliding along the curb up to VAN_PARK_SLIDE_MAX (m) to find one.
const VAN_PARK_CLEARANCE := Vector3(2.4, 2.9, 6.2)
const VAN_PARK_SLIDE_MAX: float = 12.0
## The legacy and town job street in the yard's space: where the van's middle is
## when parked at the near curb, door to the sidewalk (z; the street is 22.6..31.4,
## levels/dressing/neighborhood.gd), the near lane it drives in (z), the lane change
## between them (m), and the spacing of a route's ground-checked points (m).
## R2b van: it used to park in the far lane, so riders stepped down into the road.
## R2c van: 0.25 m further out, so its door-side wheels and mirror stand clear of
## the curb (the street starts at 22.6; it's 1.29 m from its middle to its side).
const VAN_CURB_Z: float = 24.3
const VAN_LANE_Z: float = 24.85
const VAN_MERGE_METERS: float = 14.0
const VAN_ROUTE_STEP: float = 2.0
## Freeing a rider: hold interact this long (s) on the door within VAN_DOOR_REACH (m)
## of its step, while the driver isn't checking his mirror and no NICE BOY who can
## see you is within VAN_GUARD_RADIUS (m). Each one costs HEAT_UNBUCKLE heat.
const VAN_UNBUCKLE_HOLD: float = 1.5
const VAN_DOOR_REACH: float = 1.8
const VAN_GUARD_RADIUS: float = 5.0
const HEAT_UNBUCKLE: float = 5.0
## The driver checks the door-side mirror every so often (s, from..to, seeded per
## trip) for this long (s), the mirror glinting VAN_GLINT_LEAD (s) before.
const VAN_MIRROR_EVERY := Vector2(5.0, 7.0)
const VAN_MIRROR_SECONDS: float = 1.5
const VAN_GLINT_LEAD: float = 0.3
## A rider's knock on the glass: heard this far (m); the face press lasts this long (s).
const VAN_KNOCK_HEAR: float = 15.0
const VAN_KNOCK_SECONDS: float = 0.6
## A straggler: the van creeps on at this (m/s) with its back doors open, for at
## most VAN_CREEP_MAX (s), and they hop onto the bumper over VAN_HOP_SECONDS (s).
const VAN_CREEP_SPEED: float = 1.5
const VAN_CREEP_MAX: float = 6.0
const VAN_HOP_SECONDS: float = 0.7
## The crew climb out one by one, this far apart (s), once the door is open.
const CREW_UNLOAD_STAGGER: float = 0.5
## Leaving: the door shuts, the blinker ticks this long (s), then it pulls out.
const VAN_BLINKER_SECONDS: float = 1.2
## At Annex B: it rolls up to the curb over this long (s); at the drop curb back home
## the iris opens at least RETURN_PULL_UP (s) before it stops. The return shuttle
## waits RETURN_WAIT (s) after its last rider sits; riders get DROP_IMMUNITY (s).
const ANNEX_ROLL_IN_SECONDS: float = 2.5
const RETURN_WAIT: float = 6.0
const RETURN_PULL_UP: float = 5.0
const DROP_IMMUNITY: float = 6.0
## Without the Annex set (nice_boys:5) the van pulls up here, BorderZone space.
const VAN_ANNEX_CURB := Vector3(-4.0, 0.0, 24.0)
## Home after the job's done: the Homie Depot curb (StoreZone space), facing +z in
## the cross street's near lane, door to the store's sidewalk.
const SHUTTLE_STORE_STOP := Vector3(24.05, 0.0, 6.0)
## Caught with no raid going on (dev and test captures): walked to the door at
## this pace (m/s), and the van leaves this long (s) after the last one sits.
const VAN_WALK_IN_SPEED: float = 3.2
const VAN_FALLBACK_HOLD: float = 2.0
## How it feels to ride: a pothole's kick, the front wheels' steer (most radians,
## how fast they follow), the steering wheel's ratio to them, and the air
## freshener's swing (push per m/s^2, spring, damping).
const VAN_BUMP_KICK: float = 0.9
const VAN_STEER_MAX: float = 0.55
const VAN_STEER_RATE: float = 8.0
const VAN_STEERING_RATIO: float = 6.0
const VAN_FRESHENER_PUSH: float = 0.08
const VAN_FRESHENER_STIFFNESS: float = 30.0
const VAN_FRESHENER_DAMPING: float = 2.5
## Something standing in the street (a tree, a parked car): the route swerves round
## it, the slice of road checked being this big (m, across, up, along), never
## farther than this off the curb line (m, out into the oncoming lane, toward the
## sidewalk: never up a curb), eased in and out over this many meters either side.
const VAN_ROUTE_CLEARANCE := Vector3(3.0, 2.5, 2.2)
const VAN_SWERVE_RANGE := Vector2(5.0, 0.1)
const VAN_SWERVE_EASE: float = 10.0
## A tree's crown, from above, reaches this share of its height from the trunk
## (evergreens, broadleaves): the van parks and drives clear of it.
const VAN_TREE_SPREAD := Vector2(0.3, 0.2)
## The cab shot's field of view (degrees): the daisy, the driver and the road.
const VAN_FRESHENER_FOV: float = 54.0
## On the legacy yard the van parks at least this far (m) inside the pad's ends, so
## its door and the curb its riders step onto are where people can walk.
const VAN_PAD_INSET: float = 3.0
## An ended trip is forgotten on the host this long (s) after it ends, once its van
## is gone from the host's own view too.
const VAN_TRIP_FORGET: float = 2.0
## Annex B's roll-in speed (m/s) as it starts braking to the curb.
const VAN_ANNEX_ROLL_SPEED: float = 8.0
## After the door opens at the Annex: the van leaves this long (s) later when the
## Annex walks the riders off, or when the legacy crossing has teleported them.
const VAN_ANNEX_HANDOFF_LEAVE: float = 3.0
const VAN_ANNEX_LEGACY_LEAVE: float = 1.5
## A NICE BOY getting out: up off the seat into the aisle (s), then along it to the
## sill (s); walking back to the door to climb in (m/s).
const VAN_CREW_RISE_SECONDS: float = 0.35
const VAN_CREW_AISLE_SECONDS: float = 0.9
const VAN_CREW_WALK_SPEED: float = 4.0
## At the drop curb: the door opens this long (s) after it stops, riders step down
## this far apart (s, and m along the curb), the driver waves this long (s) after
## the last one is down and it leaves this long (s) after.
const VAN_DROP_DOOR_DELAY: float = 0.2
const VAN_DROP_STAGGER: float = 0.45
const VAN_DROP_SPACING: float = 0.75
const VAN_DROP_WAVE_AFTER: float = 0.2
const VAN_DROP_LEAVE_AFTER: float = 1.6
## The driver: his lines are heard within this (m); paperwork comes round every this (s).
const VAN_DRIVER_HEAR: float = 18.0
const VAN_PAPERWORK_EVERY: float = 7.0
## The seat camera's look-around: yaw either way (degrees), pitch down..up (radians).
const VAN_SEAT_LOOK_YAW: float = 60.0
const VAN_SEAT_LOOK_PITCH := Vector2(-0.6, 0.45)
## The park point never slides past this (m, either way along the curb, yard space).
const VAN_PARK_X_MAX: float = 40.0
## A route's end is searched for up to this far (m), in steps this long (m).
const VAN_ROUTE_SEARCH_MAX: float = 200.0
const VAN_ROUTE_SEARCH_STEP: float = 10.0
## The cab radio during the ride, under the bank's own level (dB).
const VAN_RADIO_DB: float = -6.0

# ---- nice boys: integration (R2 merge)
# Where R2's chunks meet: the catch (2), the Courtesy Shuttle (4) and Annex B
# (5, 6) (docs/DECISIONS.md, "R2 integration").
## A NICE BOY's name tag fades out over this long (s) while he barks, and back
## after: the bark line sits where the tag does.
const CREW_TAG_HUSH_SECONDS: float = 0.15
## The Courtesy Shuttle faces along its route looking this far (m) ahead of and
## behind where it is: a whole VAN_ROUTE_STEP, so its heading turns smoothly between
## route points (net/run_events/shuttle.gd _route_pose).
const VAN_HEADING_LOOK: float = 2.0
## The Courtesy Shuttle parks at Annex B with its door step on the curb marker: the
## van's middle this far (m) from it, into the street (props/nice_van.gd DoorStep).
## R2c van: from 1.75, which put its side 0.24 m over Annex B's sidewalk.
const VAN_ANNEX_DOOR_TO_CURB: float = 2.3

# ---- R2b van
# The Courtesy Shuttle finished (docs/GAME.md "The Courtesy Shuttle, door to door",
# the R2b notes): the road only, seen coming, doors before feet, a window to look
# out of, and a van that drives away out of sight instead of stopping in it.
## No scenery tree stands within this (m) of the legacy streets' sidewalks.
const VAN_STREET_TREE_MARGIN: float = 0.7
## A door keeps this many of its timed opens and shuts (net/run_events/shuttle.gd).
const VAN_DOOR_EVENTS_KEPT: int = 8
## The sliding door's levels (dB): its roll, and the slam as it shuts, which lands
## this long (s) before the slide's end, as the last panel meets the post.
const VAN_DOOR_SLIDE_DB: float = 2.0
const VAN_DOOR_SLAM_DB: float = 1.0
const VAN_SLAM_EARLY: float = 0.06
## Pulling up: the horn as you first see it coming, no sooner than this (s) into
## its approach, and this long (s) before it brakes whatever; the brakes' squeal (dB).
const VAN_HONK_EARLIEST: float = 1.0
const VAN_HONK_BEFORE_BRAKE: float = 0.4
## ... and in view within this (m), near enough to make it out and hear it.
const VAN_HONK_NEAR: float = 50.0
## R2c van review: from -10 (on the borrowed skid, 13 dB under its own engine).
const VAN_BRAKE_DB: float = 0.0
## The putt-putt (it opens on a clutch clunk) starts this long (s) before it moves.
const VAN_PULL_SOUND_LEAD: float = 0.03
## The ride: the cab shot starts this long (s) after it pulls out, the pothole this
## long (s) into it, and the dolly from the seat to it takes this long (s).
const VAN_RIDE_MONTAGE_AT: float = 4.5
const VAN_BUMP_AFTER_MONTAGE: float = 1.4
## p1-van: from 1.2, as the dolly now leans out into the aisle before it goes up it.
const VAN_FRESHENER_BLEND: float = 1.6
## Stepping down: the seat camera hands to your own eyes over this long (s).
const VAN_SEAT_POP_BLEND: float = 0.5
## Boarding the ride home behind your iris: it shuts this much (s) before you're
## seated, and opens this long (s) after.
const VAN_BOARD_IRIS_MARGIN: float = 0.1
const VAN_BOARD_IRIS_HOLD: float = 0.35
## Riders step down this far (m) past the door step, out on the sidewalk, each
## straight out from their own seat (p1-van; it used to be a slot along the curb
## per turn, so the second one out walked the aisle past the first's eyes).
const VAN_EXIT_OUT: float = 0.35
## Leaving a curb: the blinker ticks this long (s) after the door is shut.
const VAN_LEAVE_BLINK: float = 0.8
## Driving away it never brakes: past the end of its planned road (VAN_HIDE_METERS
## from everyone) a watcher's copy carries straight on at a cruise until it's this
## far (m) from their camera, deep in the fog (levels/shared_look.gd FOG_END 260),
## never stopping in the street.
const VAN_VANISH_METERS: float = 200.0
## Someone standing in the road: the route passes them, and it parks, this far (m)
## clear of the van's sides.
const VAN_PERSON_CLEARANCE: float = 0.5
## Who counts as standing in the road: within this height (m) of the road there.
const VAN_PERSON_HEIGHT: float = 3.0
## The engine, heard coming down the street: its loop's reach (m), level from idle
## to cruise (dB), the cut inside the cabin (dB), and pitch from idle to cruise.
const VAN_ENGINE_UNIT_SIZE: float = 16.0
const VAN_ENGINE_MAX_DISTANCE: float = 120.0
const VAN_ENGINE_DB := Vector2(-12.0, 1.0)
const VAN_ENGINE_RIDER_DB: float = -7.0
const VAN_ENGINE_PITCH := Vector2(0.7, 1.45)
## The loop's level before it first plays (dB, silent), and below this (dB) it
## jumps straight to its level instead of easing up from silence.
const VAN_ENGINE_SILENT_DB: float = -80.0
const VAN_ENGINE_EASE_FLOOR_DB: float = -60.0
## How fast its level eases toward the speed's (per second, exponential).
const VAN_ENGINE_SMOOTH: float = 12.0
## Its pitch keeps climbing a little past cruise (a drive-on downhill): speed's
## share of VAN_CRUISE is capped here.
const VAN_ENGINE_SHARE_MAX: float = 1.2

# ---- R2c van (the Courtesy Shuttle's seams; docs/GAME.md "The Courtesy Shuttle, seams")
## The straggler: a NICE BOY still on the lawn when the van pulls out sprints after
## it (m/s; it creeps at VAN_CREEP_SPEED) along the yard's navmesh, round the house
## and the hedges, never longer than VAN_STRAGGLER_RUN_MAX s (a very long way off,
## he runs faster), ending VAN_STRAGGLER_BEHIND m behind the bumper, where the back
## doors swinging shut just clear him; then he hops on. The van creeps for as long
## as his run takes. He gets up to speed, and pulls up at the end, over
## VAN_STRAGGLER_RAMP s, and looks VAN_STRAGGLER_LOOKAHEAD m along his way, so he
## turns into a corner instead of snapping round it.
const VAN_STRAGGLER_RUN_SPEED: float = 6.5
const VAN_STRAGGLER_RUN_MIN: float = 0.6
const VAN_STRAGGLER_RUN_MAX: float = 10.0
const VAN_STRAGGLER_BEHIND: float = 1.15
const VAN_STRAGGLER_RAMP: float = 0.35
const VAN_STRAGGLER_LOOKAHEAD: float = 1.2
## ... he's never at the bumper sooner than this after the back doors swung open and
## shut again (they swing through where he'd stand); the creep's closing speed is
## never taken as less than VAN_STRAGGLER_MIN_CLOSING m/s.
const VAN_STRAGGLER_DOOR_MARGIN: float = 0.1
const VAN_STRAGGLER_MIN_CLOSING: float = 1.0
## An unbuckled friend steps down this far beside their rescuer (along the van),
## shoulder to shoulder, inside the open side's span (z in the van's space). R2c van
## review: from 0.9, where the step down still brushed past the rescuer's cap.
const VAN_UNBUCKLE_BESIDE: float = 1.15
const VAN_DOORWAY_Z := Vector2(-1.4, 2.5)
## Stepping down out of a seat, a rider who lands somewhere along the curb from
## their seat (an unbuckle beside the rescuer, a spot slid clear of a lamp post)
## shuffles along the aisle's far side first, curving out through the door past
## this x (van space; the seats are at -0.78, the doorway at 1.16: p1-van, from 0.7,
## so the shuffle passes the other riders' eyes 1.6 m off, not 1.4), with this
## little hop (m) as they step down.
const VAN_STEP_OUT_TURN_X: float = 0.9
const VAN_STEP_OUT_LIFT: float = 0.2
## Annex B's ride home parks this far up the curb from the turnstile (m), so the
## way out of the turnstile is open pavement and the receipt beat plays there:
## its nose (3.1 m ahead of its middle) is well clear of the walk straight out to
## the street, off at the edge of your view (R2c van review: at 4.5 its nose sat
## in the turnstile's line and you walked along its open side).
const VAN_RETURN_CURB_SHIFT: float = 9.0
## Walk up to its open door (within this of its step, m) during that beat and you
## step up into your seat there and then, no iris.
const VAN_RETURN_STEP_REACH: float = 1.7
## ... and it comes down the street from this far off, deep in the haze, while
## the riders are inside.
const VAN_ANNEX_RETURN_FROM: float = 150.0
## Riders' iris opens for the last this-many seconds of a long way in to Annex B
## (taken only when someone there could watch the van come).
const VAN_ANNEX_PULL_UP: float = 4.0
## The cohort all aboard the ride home, it goes this soon after the last one sits
## (RETURN_WAIT is the wait when the cohort doesn't ride together).
const VAN_RETURN_GO: float = 1.0
## Let out at closing time, the receipt starts printing this long after the door
## swung shut over the lobby: as it opens again on the seat.
const VAN_CLOSING_RECEIPT_AFTER: float = 1.3
## ... and the door iris opens by itself this long after it started to shut if no
## seat has taken them (it never stays shut).
const VAN_CLOSING_IRIS_CAP: float = 4.0
## Where a rider steps down: a spot with nothing standing within this much of it
## (a lamp post, a mailbox, a hydrant), slid along the curb up to
## VAN_EXIT_SLIDE_MAX m to find one (R2c van: the step-down at the yard landed
## with a lamp post in the lens).
const VAN_EXIT_CLEAR: float = 0.85
const VAN_EXIT_SLIDE_MAX: float = 2.4
## ... in steps of this (m), the clearance a cylinder this tall (m) standing this
## high off the ground (m: over the curb's lip, under a lamp's arm).
const VAN_EXIT_SLIDE_STEP: float = 0.3
const VAN_EXIT_CLEAR_HEIGHT: float = 1.6
const VAN_EXIT_CLEAR_LIFT: float = 0.3
## The Courtesy Flare stands this far ahead of the raid van's park point (its
## half length, the cones' ring and a step), in the road where it stops.
const VAN_FLARE_AHEAD: float = 5.4
## Annex B's street runs this much (m) past its 40 m pad, half each way.
const VAN_ANNEX_STREET_EXTRA: float = 340.0
## The brakes' last squeal, this long before it stops at the curb, this loud (dB).
const VAN_BRAKE_SETTLE_BEFORE: float = 0.5
const VAN_BRAKE_SETTLE_DB: float = -6.0
## Its brakes (audio's van_brake) keep full volume out to this far (m), as the
## engine does (VAN_ENGINE_UNIT_SIZE): a squeal carries.
const VAN_BRAKE_UNIT_SIZE: float = 16.0

# ---- toss: polish
# Your own leaf bag through your own eyes (props/carry_view.gd, docs/GAME.md
# "Tossing bags into Chefty"), and Chefty's floating label up close
# (ui/near_label.gd). Presentation only: nobody else sees any of it, and the
# host's flight (net/components/bed_toss.gd) is untouched.
## Carried, the bag sits in the lower third of your view, both hands on its
## rolled top: the middle of its rim this far from your eyes (view space: x
## right, y up, -z ahead, m), its top tipped toward you this much (rad) so you
## see into it. It follows the view's pitch this share, within these limits (rad).
const FP_BAG_RIM := Vector3(0.0, -0.23, -0.6)
const FP_BAG_TILT: float = 0.22
const FP_BAG_PITCH_FOLLOW: float = 0.7
const FP_BAG_PITCH_MIN: float = -0.7
const FP_BAG_PITCH_MAX: float = 0.45
## Picking one up, it eases from where the world has it into that spot this fast (s).
const FP_BAG_ENTER_SECONDS: float = 0.15
## The wind-up dips it: down and back toward you by this much (m) and its top
## tipped further back (rad), all the way in this long (s), then it trembles as
## your arms do (first_person_arms.gd), harder when you strain (m).
const FP_BAG_WIND_PULL := Vector3(0.0, -0.06, 0.07)
const FP_BAG_WIND_TILT: float = 0.2
const FP_BAG_WIND_SECONDS: float = 0.35
const FP_BAG_SHAKE: float = 0.006
const FP_BAG_STRAIN_SHAKE: float = 0.02
## The tremble's wobble on each view axis (x, y, z): rad of shake phase per second
## of game time, unlike each other so it never settles into a loop you can see.
const FP_BAG_SHAKE_RATE := Vector3(37.0, 41.0, 29.0)
## Let go, it leaves your hands for the real flight over this long (s), and
## while it's up near your eye line it never looks wider than this (rad, its
## full width seen from your eyes): it shrinks the way something flung away
## from you does, instead of passing through your face. The cap comes on over
## the first seconds and is gone by the end (s, a flight that never landed); it
## counts fully with the bag's middle this far below your eyes or higher (m),
## and not at all this far below (a bag set down at your feet stays its size). A
## bag gliding into the load is its own size again by this share of the glide,
## before it lands.
const FP_THROW_EASE_SECONDS: float = 0.16
const FP_THROW_MAX_ANGLE: float = 0.36
const FP_THROW_CAP_IN_SECONDS: float = 0.07
const FP_THROW_CAP_HOLD_SECONDS: float = 1.0
const FP_THROW_CAP_END_SECONDS: float = 1.4
const FP_THROW_CAP_HIGH_M: float = 0.15
const FP_THROW_CAP_LOW_M: float = 0.55
const FP_THROW_SETTLE_DONE: float = 0.8
## The cap starts letting go this share of the glide before FP_THROW_SETTLE_DONE.
const FP_THROW_SETTLE_FADE: float = 0.3
## How far a bag reaches from its middle (m), for how big it looks.
const FP_BAG_RADIUS: float = 0.42
## Your arms follow through after a toss: up and out in front (the right hand
## here in head space, m; the left mirrors it), this share of the way in, then
## back down, over this long (s). Holding a bag out in the lower third, they
## stretch to this times their length to keep both hands on it.
const FP_ARMS_FOLLOW_SECONDS: float = 0.45
const FP_ARMS_FOLLOW_REACH := Vector3(0.17, 0.02, -0.5)
const FP_ARMS_FOLLOW_PEAK: float = 0.3
const FP_BAG_ARM_STRETCH: float = 1.5
## Chefty's floating name and load: it never stands taller on screen than this
## share of the view's height per line, and fades out as you come within these
## distances of it (m, gone at the first, whole at the second). Up close the
## heap in the bed and the floating dollars say what it would.
const CHEFTY_LABEL_MAX_SCREEN: float = 0.034
const CHEFTY_LABEL_GONE_M: float = 3.0
const CHEFTY_LABEL_FULL_M: float = 4.3
## It shrinks no smaller than this share of its own size, so it never vanishes
## into a dot before the fade takes it.
const CHEFTY_LABEL_MIN_SCALE: float = 0.2
## The toss arc's dots leave out anything closer to your eyes than this (m):
## a hop over Chefty's side climbs right past your face.
const TOSS_ARC_NEAR_M: float = 1.1

# ---- rakefeel: the windrow (R1b field rules, net/leaf_field/leaf_field.gd _stroke_cells)
## A stroke gathers the leaves its tine line passes over, along lanes parallel to
## the stroke, and drops them in a berm just ahead of the tines; the next stroke
## picks the berm up and pushes it on, so it grows into a pile (docs/GAME.md
## "Raking: the windrow"). Metres along the stroke from its origin, which is
## equipment/rake.gd REACH (1.5 m) ahead of the raker; the field works 1.25..1.95 m
## out, so the plant line is 0.25 m behind the origin and the drive ends 0.45 m past
## it. (R1b integration: rakefeel:look then drew the head 0.85..2.1 m out for others
## and 1.45..2.35 m in your own view; the field sits between the two and was left
## as is. See docs/DECISIONS.md "R1b integration".)
const RAKE_FIELD_BACK: float = 0.25
## Where each bite's tine line has got to: the plant bite (0) carries leaves to
## just past 0.1 m, the mid-drive bite (1) to just past 0.45 m. Every stroke that
## isn't a rake's own bite (hands, the blower, hired hands) is a whole drive.
const RAKE_FIELD_BITE_FRONT: Array[float] = [0.1, 0.45]
## The head is dragged over the ground between strokes: a stroke also sweeps the
## ground its tine line crossed since the same raker's last stroke, up to this far
## (5 m/s walking puts 2.1 m between one swing's last bite and the next's first).
## Farther than this since the last stroke, the raker walked or ran on with the head
## up (a pause, a walk to the next lane, a sprint at 8 m/s: 3.4 m), and there's no drag.
const RAKE_FIELD_DRAG_MAX: float = 2.4
## No drag either if the raker side-stepped more than this, walked back, or turned
## (the head came up).
const RAKE_FIELD_DRAG_SIDESTEP: float = 0.6
## Grip: full across the stroke's width (the rake's head), fading to nothing this
## far past each end, so a raked lane has soft edges instead of a cut.
const RAKE_FIELD_EDGE: float = 0.5
## A heap (density over a fresh lawn's) is pushed with the edge's grip times this,
## at most whole: whole over the inner half of the edge, so the head's own berm
## leaves no trail, fading to nothing at its end, so a pile 1 m off your line keeps
## most of itself (rake_field_rules.gd "width beside a heap").
const RAKE_FIELD_HEAP_GRIP: float = 2.0
## What the tines leave behind in a cell they cross: this share of it, at most
## RAKE_FIELD_RESIDUE_MAX, so one full-grip pass leaves a fresh lawn clean (<= 8).
const RAKE_FIELD_RESIDUE_SHARE: float = 0.1
const RAKE_FIELD_RESIDUE_MAX: int = 3
## How much one stroke can push along each 0.5 m of the head: strength x this.
## A berm heavier than that slips under the tines in part (diminishing returns),
## so one run can't haul a whole yard.
const RAKE_FIELD_LOAD: float = 12.0
## The berm: shares of a lane's load in the cells just ahead of the tine line.
const RAKE_FIELD_BERM: Array[float] = [0.6, 0.3, 0.1]
## A full cell (255) passes the rest on to the next, at most this many cells
## ahead along an axis (as far in metres along a diagonal: 4 cells); whatever
## still doesn't fit stays under the tines.
const RAKE_FIELD_BERM_REACH: int = 6
## A hired hand walks its berm along this far after each stroke (npcs/crew_hand.gd;
## 0.18 before the windrow, when a 3.2 m stroke covered more ground standing still).
## A pile is HIRE_STROKES_PER_PILE strokes, so about 5.5 m of lane: as many leaves
## a bag as a hand bagged before (tools/rake_pace.gd: 4,550 units, 0.4.7 4,430-4,550;
## 4,213-4,231 since the soft edge keeps part of a heap, and 0.45-0.65 all bag less).
const HIRE_STEP_AFTER_STROKE: float = 0.55

# ---- R2b stage
# The catch on camera and in the bodies (docs/GAME.md "The catch, staged (R2b)";
# player/stage_cam.gd, player/stage_sweep.gd, player/caught_pose.gd,
# net/run_events/encounter.gd, npcs/crew_member.gd). Presentation and the escort's
# route; the verdicts and their timing are R2's.
## The two-shot cheats both bodies toward the camera: each turns this far (rad)
## from facing the other, so both faces read side-on. The eye sits this far (m)
## under the look point between them: a low shot looking a little up.
const CATCH_CHEAT_TURN: float = 0.5
const CATCH_CAM_EYE_DROP: float = 0.14
## Your own grab sound, played flat at you (dB over its bank level).
const CATCH_GRAB_DB: float = 3.0
## StageCam with a pivot (a shot about someone): the eye stays this far (m, a
## sphere's radius) clear of the world and vehicles, pulls in at once when
## something is in the way and eases back out at this speed (m/s).
const STAGE_CAM_RADIUS: float = 0.22
const STAGE_CAM_RELEASE_SPEED: float = 2.5
## ... and never moves faster than this relative to its pivot (m/s) or turns
## faster than this (rad/s), whatever its anchor does, outside a closed iris.
const STAGE_CAM_MAX_SPEED: float = 7.0
const STAGE_CAM_MAX_TURN: float = 3.5
## Someone else's body this close (m) to the stage camera isn't drawn for you
## (R2:1 skips only your own head): a camera passing a head never fills the
## screen with the inside of a face.
const STAGE_CAM_BODY_CLEAR: float = 0.6
## The escort's follow shot eases its turn toward where the pair walks at this
## rate (1/s), never faster than ESCORT_CAM_TURN.
const ESCORT_CAM_TURN_EASE: float = 1.6
## The escort's route to the van door: when the straight way out is walled (a
## hedge, a fence), a way round is looked for at these distances from the door
## (m), every ESCORT_ROUTE_STEP_DEG degrees. Making less than ESCORT_STUCK_METERS
## of progress in ESCORT_STUCK_SECONDS counts as stuck: he looks for another way;
## stuck this long in all (s), he hands you over at the door from where you are.
const ESCORT_ROUTE_RADII: Array[float] = [2.5, 5.0, 8.0, 11.0]
const ESCORT_ROUTE_STEP_DEG: float = 15.0
const ESCORT_STUCK_SECONDS: float = 0.5
const ESCORT_STUCK_METERS: float = 0.25
const ESCORT_STUCK_HANDOFF: float = 2.5
## Boarding: you see him hand you up for this long (s) before the iris closes
## (the seat view opens behind it).
const BOARD_IRIS_DELAY: float = 0.45
## Out of the van, he straightens his visor and looks left and right for this
## long (s) before his eyes count; then the spot is its own beat (CREW_SPOT_FREEZE).
const CREW_LAND_LOOK_SECONDS: float = 0.9
## His spot_take point holds this much longer (s) than the freeze, so the arm is
## still out as he starts after you.
const CREW_SPOT_HOLD_EXTRA: float = 0.25
## A shot's pivot (the pair it's about) is followed no faster than this (m/s,
## above the escort's late pace): an anchor read from a stale pose glides in, it
## never carries the camera with it in one frame (outside a closed iris).
const STAGE_CAM_PIVOT_MAX_SPEED: float = 6.0
## A swing out of first person rises this far (m) at its middle, over a shoulder
## rather than past the back of a head.
const STAGE_CAM_ARC_LIFT: float = 0.3
## The escort's route search: the pair's sweep is a sphere this big (m) this high
## (m) off the lawn, aiming this far (m) short of the door (the van's side is
## right there). A waypoint within ESCORT_ROUTE_RETRY_APART of one already tried,
## or closer to him than ESCORT_ROUTE_MIN_STEP, isn't a way round; one within
## ESCORT_ROUTE_NAV_SNAP of the navmesh counts as on it; within
## ESCORT_ROUTE_REACHED of it, it's reached.
const ESCORT_ROUTE_SWEEP_RADIUS: float = 0.32
const ESCORT_ROUTE_LIFT: float = 0.7
const ESCORT_ROUTE_DOOR_STANDOFF: float = 0.6
const ESCORT_ROUTE_RETRY_APART: float = 1.5
const ESCORT_ROUTE_MIN_STEP: float = 1.0
const ESCORT_ROUTE_NAV_SNAP: float = 0.6
const ESCORT_ROUTE_REACHED: float = 0.8
## The escort's follow shot swings in from the two-shot over this long (s).
const ESCORT_CAM_BLEND_IN: float = 1.1
## The escort anchor's interpolated pose is trusted within this far (m) of its
## real one; past it (a stale pose from before a teleport), the real one wins.
const ESCORT_ANCHOR_TRUST_M: float = 1.0

# ---- R2b hud
# What's on screen during the encounter (docs/GAME.md, "What's on screen during
# the encounter"): the cinematic HUD mode (ui/hud_mode.gd), the caption stack,
# the NICE BOYS' bubbles and everyone's name tags (ui/overheads.gd).
## The yard HUD eases out over R2B_HUD_FADE_OUT s when the moment takes you, and
## back over R2B_HUD_FADE_IN s once you've been back in control for
## R2B_HUD_RETURN_DELAY s (so a one-frame gap between two holds never flashes it).
const R2B_HUD_FADE_OUT: float = 0.35
const R2B_HUD_FADE_IN: float = 0.6
const R2B_HUD_RETURN_DELAY: float = 0.6
## In the cinematic mode the caption stack shows at most this many lines, its
## bottom this far (px) above the screen's bottom, film-subtitle style.
const R2B_HUD_CINEMATIC_LINES: int = 2
const R2B_HUD_CINEMATIC_BOTTOM: float = 44.0
## A spoken line (subtitle) is readable this fast (s) after its sound starts:
## its slot opens and it fades in together.
const R2B_HUD_SUBTITLE_ONSET: float = 0.06
## The soft plate behind every caption line when the dark caption backdrop is
## off: its darkness, padding round the words (px) and feathered edge (px).
const R2B_HUD_PLATE_ALPHA: float = 0.4
const R2B_HUD_PLATE_PAD := Vector2(16.0, 4.0)
const R2B_HUD_PLATE_FEATHER: int = 12
## A NICE BOY's bubble wraps at this many font pixels (a line, not a column),
## stays this far (px) inside the screen's edges, glides back inside at this
## rate (1/s), and is only used when his head is at least this far (m) from
## the camera; closer (the two-shot) the line is a subtitle instead.
const R2B_HUD_BUBBLE_WIDTH: float = 820.0
const R2B_HUD_SAFE_MARGIN: float = 16.0
const R2B_HUD_BUBBLE_GLIDE: float = 14.0
const R2B_HUD_BUBBLE_MIN_M: float = 3.2
## Name tags fade over this long (s) when something solid comes between you and
## them, when they'd sit on another tag or a bubble, or when he sits in the van.
const R2B_HUD_TAG_FADE: float = 0.18
## Two tags this close on screen (px, between their rects) count as stacked.
const R2B_HUD_TAG_GAP: float = 4.0
## The Annex window's [E] sits this far (m) over its stamp's knob.
const R2B_HUD_STAMP_PROMPT_LIFT: float = 0.2
## The raid's edge vignette (ui/run_cues.gd) starts this far out (0 the middle,
## 1 the screen's edge, a rounded rectangle), so the middle of the view is never tinted.
const R2B_HUD_VIGNETTE_INNER: float = 0.7

# ---- R2b hide
# Being found, peering in, the view from inside and the tells (player/hide_view.gd,
# player/hide_frame.gd, props/hide_spot.gd, net/components/hide_spot.gd; docs/GAME.md
# "Hiding", R2b). Presentation tuning except where marked host.
## Found (host timing): the spot comes open and his grinning face and hands are in
## the gap for this long (s) before he pulls you out; his hands close on you this
## long (s) before the pull starts; the gotcha lands this long (s) after you're
## back on your feet (CREW_FOUND_CONTACT adds the three).
const HIDE_FOUND_REVEAL: float = 0.55
const HIDE_FOUND_GRAB_LEAD: float = 0.12
const HIDE_FOUND_SETTLE: float = 0.12
## Pulled out, you're set down on your feet this far out from the spot's face (m)
## (and HIDE_FOUND_LAND_SIDE along it, under "# ---- R2c hide"), on a hop this
## high (m).
const HIDE_FOUND_LAND_OUT: float = 0.5
const HIDE_FOUND_HOP: float = 0.28
## A NICE BOY peering into each kind of spot: torso lean (rad, negative is
## forward), how far his hips drop (m), his face tilt (rad, negative looks down).
const HIDE_PEER_POSE: Dictionary = {
	"hedge": Vector3(-0.45, 0.1, 0.0),
	"bin": Vector3(-0.6, 0.04, -0.3),
	"shed": Vector3(-0.32, 0.0, 0.0),
	"pile": Vector3(-0.95, 0.3, -0.45),
}
## He leans in over this long (s) once the poke starts, and back out over this long.
const HIDE_PEER_IN_SECONDS: float = 0.4
const HIDE_PEER_OUT_SECONDS: float = 0.35
## From inside, your view is drawn to his face while he peers in: all the way over
## this long (s), never turned more than this (rad), and your own look offset
## eases back toward him at no more than this (rad/s, under the tremble rate).
const HIDE_PEER_AIM_SECONDS: float = 0.35
const HIDE_PEER_AIM_MAX: float = 0.9
## ...and never tipped up or down more than this (rad): it stays in the gap.
const HIDE_PEER_AIM_PITCH_MAX: float = 0.28
const HIDE_PEER_LOOK_RETURN: float = 1.2
## The world through the wall: the low-pass sweeps down from this (Hz) to
## HIDE_MUFFLE_HZ over this long (s) once you're in, so your own lid's clang and
## the hedge settling around you are heard before the world goes dull.
const HIDE_MUFFLE_FROM_HZ: float = 9000.0
const HIDE_MUFFLE_SWEEP_SECONDS: float = 0.4
## Your own spot's sounds (the lid, the clang, the door) play this much louder
## on your own machine (dB), and the music ducks this much (dB) for this long (s).
const HIDE_OWN_SOUND_DB: float = 4.0
const HIDE_DIVE_DUCK_DB: float = -6.0
const HIDE_DIVE_DUCK_SECONDS: float = 0.9
## Tells: the turn speed is smoothed over this long (s), so the steps of a
## replicated or stepped look never read as a jerk; a rustle comes at most every
## (min, max) seconds and is louder the harder you turn (dB per rad/s over the
## threshold, up to the cap).
const HIDE_TREMBLE_SMOOTH: float = 0.16
const HIDE_TREMBLE_COOL: Vector2 = Vector2(0.65, 1.2)
const HIDE_TREMBLE_DB_PER_RATE: float = 2.0
const HIDE_TREMBLE_DB_CAP: float = 6.0
## Inside a hedge, a shell of leaves around your eye (you see this, not the
## hedge's own outside): its radius (m) and the opening ahead (half-angles, rad).
const HIDE_SHELL_RADIUS: float = 0.42
const HIDE_SHELL_OPENING: Vector2 = Vector2(0.62, 0.36)
## A shed's eye sits this far inside the door (m), at the knot holes, this far
## either side of the middle for its two places (m).
const HIDE_SHED_EYE_IN: float = 0.16
const HIDE_SHED_EYE_SIDE: float = 0.22
## The pile: the mound grows from this share of its size as you land, over this
## long (s), while your body sinks this far (m) into it.
const HIDE_PILE_MOUND_FROM: float = 0.3
const HIDE_PILE_MOUND_GROW: float = 0.3
const HIDE_PILE_SINK: float = 0.9
## A find holds you (no climb-out, no peek) only for its reveal, pull and settle
## plus this slack (s, for the pull to arrive over a slow link); after that the
## spot's find is old news and whoever dives in next is free to leave.
const HIDE_FOUND_HOLD_SLACK: float = 0.5
## After a find the lid or door drops shut this long (s) after you're out; a bin's
## clang follows the drop by this long (s), this loud (dB).
const HIDE_FOUND_SHUT_DELAY: float = 0.35
const HIDE_FOUND_CLANG_DELAY: float = 0.14
const HIDE_FOUND_CLANG_DB: float = -6.0
## Host: a shed's door swings out on its hinge side, so its two climb-out places
## step this far toward the latch side (m): base, plus this per second place.
const HIDE_SHED_EXIT_ALONG: float = 0.1
const HIDE_SHED_EXIT_SLOT_STEP: float = 0.45
## Host: pulled out of a shed, you land off the latch side, this far (m) along
## from the door's middle (where R2b put it, clear of the door's swing).
const HIDE_FOUND_LAND_SHED: float = 0.3
## Host: the gotcha trusts a found hider's landing (meta hide_pulled_to) for this
## long (s) after they're down; older than that and it stands them where they are.
const HIDE_PULLED_TO_TRUST: float = 2.0
## The shed's shape, shared by its model and the hider's eye (host: the eye is the
## peek anchor): walls are this share of its height, the door stops this far (m)
## under the wall top, and the knot holes (the eye) are this far (m) under the door's top.
const HIDE_SHED_WALL_SHARE: float = 0.72
const HIDE_SHED_DOOR_HEADROOM: float = 0.26
const HIDE_SHED_KNOT_DROP: float = 0.22
## A NICE BOY's poke, shared by the spot (props/hide_spot.gd _poke) and the
## hider's view of it (player/hide_view.gd): a hedge's two pushes (s in), each
## parting it this much (0..1) for a beat; a bin lid lifted a crack at this time
## (s), this far open; a shed's three knocks, the first at x (s), then every y (s);
## a pile's pats part it this much.
const HIDE_POKE_HEDGE_PUSHES: Array[float] = [0.2, 0.9]
const HIDE_POKE_HEDGE_PART: float = 0.28
const HIDE_POKE_BIN_CRACK_AT: float = 0.3
const HIDE_POKE_BIN_PART: float = 0.22
const HIDE_POKE_SHED_KNOCKS: Vector2 = Vector2(0.25, 0.3)
const HIDE_POKE_PILE_PART: float = 0.12
## Gestures outlast their moves by this long (s) so the landing reads: a
## climb-out, and being pulled out.
const HIDE_EXIT_GESTURE_TAIL: float = 0.4
const HIDE_PULL_GESTURE_TAIL: float = 0.15

# ---- R2b annex
# Satellite Annex B, the motion pass (docs/GAME.md "Form 27-B, in Triplicate":
# "The room teaches itself"). The room's one language, the stamps' timing, the
# closing beat, the turnstile, the receipt and the pace.
## Each pictogram always wears one color, everywhere it appears: its window's
## plaque, its box on Form 27-B, its floor line, its footprints and the sticker
## at the line's start (ui/icons.gd ids). Four hues no two of which read alike
## under the lobby's warm light.
const ANNEX_ICON_COLORS: Dictionary = {
	"item_rake": Color(0.98, 0.62, 0.1),
	"item_leaf_bag": Color(0.24, 0.66, 0.3),
	"tool_lawn_mower": Color(0.86, 0.2, 0.24),
	"tool_hedge_trimmer": Color(0.2, 0.46, 0.95),
}
## The badge that pictogram and color make (a colored board, a white disc, the
## icon), drawn once per pair, this many pixels square.
const ANNEX_BADGE_PX: int = 160
## The fewest boxes on a form; ANNEX_BOXES_BY_HEAT adds one per threshold (R2b:
## 4 to 6, from 2 to 4, so a solo visit lands in ANNEX_PACE_TARGET: a bot
## that knows the room did one in 27 s with 3 boxes, a person in about 40).
const ANNEX_BOXES_MIN: int = 4
## A solo visit by the bot's rules should take this long on average (s, from the
## walk-in to the turnstile; annex_test checks it). gap-specs nice_boys "40-75 s solo".
const ANNEX_PACE_TARGET := Vector2(40.0, 75.0)
## A window's stamp, sent down at some moment, hits the pad (KA-CHUNK, and the
## ink in the box) this long after: its lift plus its slam.
const ANNEX_STAMP_HIT: float = ANNEX_STAMP_LIFT_SECONDS + ANNEX_STAMP_SLAM_SECONDS
## The host sends a stamped form this long before its ink lands, so the ink
## arrives ahead of the stamp under lag and waits for it (s).
const ANNEX_INK_LEAD: float = 0.35
## The Head NICE BOY reads a full form this long before he raises the big stamp (s).
const ANNEX_HEAD_READ: float = 1.1
## Closing: this long after the bell the clerks start their rush, every hatch
## slamming ANNEX_CLOSING_SLAMS times CLOSING_RUSH_GAP apart; each box still
## empty on your form inks with a slam, then AFTER HOURS lands across it.
const ANNEX_CLOSING_RUSH_AT: float = 0.7
const ANNEX_CLOSING_SLAMS: int = 5
const ANNEX_CLOSING_RUSH_GAP: float = 0.2
## The room's sky light while the rows go off: this share of itself once all
## are off, eased over each row's clunk (local, cosmetic, only while you're inside).
const ANNEX_CLOSING_DIM: float = 0.15
const ANNEX_ROW_DIM_SECONDS: float = 0.25
## ... and the picture's brightness with them, to this share once all are off.
const ANNEX_CLOSING_PICTURE: float = 0.55
## Out through the door-swing iris: it shuts over ANNEX_IRIS_CLOSE, the move
## happens ANNEX_DOOR_IRIS_WAIT in (fully shut), and it opens again this long in.
const ANNEX_IRIS_CLOSE: float = 0.35
const ANNEX_IRIS_OPEN_AT: float = 0.85
## Through the turnstile, the forecourt is yours for this long (s) before the
## shuttle home takes you: the receipt prints, is held up and pocketed.
const ANNEX_FORECOURT_BEAT: float = 6.8
## The receipt in first person: held up lower centre this far from your eyes
## (view space, m), tipped back this much (rad), then pocketed down and right
## over ANNEX_RECEIPT_POCKET seconds.
const ANNEX_RECEIPT_HOLD := Vector3(0.0, -0.03, -0.3)
const ANNEX_RECEIPT_TILT: float = 0.12
const ANNEX_RECEIPT_POCKET: float = 0.4
## The clipboard comes up into your hand from the Greeter's: it starts rising
## this long into his offer, over ANNEX_FORM_RISE seconds, from this far below.
const ANNEX_FORM_HANDOFF_AT: float = 0.65
const ANNEX_FORM_RISE: float = 0.4
const ANNEX_FORM_RISE_DROP: float = 0.3
## The Greeter hands it over from beside the threshold (set space offset from
## Threshold, m), then walks back to his post this long after the offer.
const ANNEX_GREETER_OFFER_SPOT := Vector3(0.75, 0.0, -0.6)
const ANNEX_GREETER_BACK_AT: float = 1.8
## The turnstile: its arms turn with the body pushing through, from this far
## before the bar to this far past it (m along the passage), one clack each push.
const ANNEX_TURNSTILE_PUSH := Vector2(-0.55, 0.55)
## Staff step round people: a staff body walking within this far (m) of a
## player eases sideways out of the way (R2c annex: standing too, and from 1.25,
## was 0.85: walked into, he held his ground with his face in your camera).
const CLERK_STAND_OFF: float = 1.25
## A clerk's head turns ease this fast (1/s): no one-frame snap.
const CLERK_FACE_EASE: float = 14.0
## A player slamming the big stamp holds it up only this long (s).
const ANNEX_BIG_STAMP_HOLDER_HESITATE: float = 0.12
## The visitors' side door answers interact only this close (m).
const ANNEX_SIDE_DOOR_REACH: float = 1.1
## Staff ease out of people's way this fast (1/s).
const CLERK_STAND_OFF_EASE: float = 8.0
## How high (m) the hatch stamp winds up: Window D's volley, and closing's rush.
const ANNEX_VOLLEY_LIFT: float = 0.45
const ANNEX_RUSH_LIFT: float = 0.3
## The blinds come down this long (s) after closing's last rush slam.
const ANNEX_BLINDS_AFTER_RUSH: float = 0.3
## A wrong-window clerk points this high (m) above the right window.
const ANNEX_POINT_RISE: float = 2.5
## A visitor's asks to leave: at most one this often (s).
const ANNEX_LEAVE_ASK_GAP: float = 1.0

# ---- flakes:play (the gameplay tests' flakes, docs/DECISIONS.md "Flaky gameplay tests")
## Chefty (net/components/chefty_drive.gd _host_input): how far ahead of a client
## driver's inputs the host may drive on its last one while the next are late or
## lost (s). Each of those ticks stands in for the input that comes later, so a
## hitch on either peer doesn't yank the driver's truck forward; past this, the
## extra ticks stand for nothing and the driver is corrected, as before.
const CHEFTY_STAND_IN_MAX_SECONDS: float = 0.4
## Leaf bags into Chefty (net/components/bed_toss.gd sure_catch): a toss is sure
## to go in when one this share softer and harder goes in too. The arc preview
## turns gold on it (it was ui/toss_arc.gd SURE_SHARE), and the aim help aims for
## it: its smallest nudge used to scrape in by a millimetre, and a real bag,
## stepped by Jolt in its own float precision, missed that 29 times in 30 and
## bounced off the rail.
const TOSS_SURE_SHARE: float = 0.04

# ---- hotbar: stowed looks and the draw (hotbar chunk D, props/prop_looks.gd
# pose_stowed, _blend_put; HOTBAR_DRAW_SECONDS and HOTBAR_JANGLE_AT are above)
## Putting something in a pocket: how long it takes to get from the hands to its
## spot on the body (s).
const HOTBAR_STOW_SECONDS: float = 0.2
## A draw or a stow travels round the body, not through it: at the middle of the
## glide it bows this far out from the holder's middle and this far up (m).
const HOTBAR_DRAW_ARC: float = 0.22
const HOTBAR_DRAW_RISE: float = 0.1
## Through your own eyes, a drawn thing comes up from (and a stowed one drops to)
## this far from its spot in hand, in the body's frame (x right, y up, +z back):
## down at the right hip, out of the bottom of the view.
const HOTBAR_FP_DRAW_FROM := Vector3(0.16, -0.6, 0.12)
## (Not the rake: its head is on the leaves well ahead. Drawn through your own
## eyes, it comes off your back the way everyone sees it, but bowed this much
## wider (m) and this much lower, round your right side, so it never sweeps across
## your face on the way past the camera.)
const HOTBAR_FP_RAKE_ARC: float = 0.5
const HOTBAR_FP_RAKE_DROP: float = 0.3
## Put away through your own eyes, the rake keeps its angle and slides this far
## (body frame: x right, y up, +z back, m) off the leaves, out past the right edge
## of the view, before it cuts onto your back.
const HOTBAR_FP_RAKE_STOW_TO := Vector3(1.5, 0.25, 1.0)
## A stack worn fanned (the signs down your back): when one leaves, the rest ease
## over to their new places at this rate (per second; about 0.17 s to settle).
const HOTBAR_FAN_SETTLE: float = 18.0
## A drawn rake's head comes off the back this much higher (m) than the swing
## puts it, and plants on the leaves as the draw ends (RakeMotion's draw_dip); a
## stowed one lifts this much off the leaves on its way over the shoulder.
const HOTBAR_RAKE_DRAW_LIFT: float = 0.45
## A replicated drawn/stowed stamp younger than this (ms) starts the glide's clock,
## so a pose that runs a tick late doesn't lengthen it.
const HOTBAR_STAMP_FRESH_MS: int = 250
## Footsteps jangle on every this-many-th step with HOTBAR_JANGLE_AT or more
## things in your pockets, this loud (dB).
const HOTBAR_JANGLE_EVERY: int = 2
const HOTBAR_JANGLE_DB: float = -6.0
## How fast (per second) your first-person hands chase a drawn or stowed thing's
## grips: a little behind it, so they reach down for it, then pull it up.
const HOTBAR_FP_DRAW_FOLLOW: float = 22.0

# ---- shops: Rusty's (shops chunk 5; docs/GAME.md "Rusty's Salvage & Pawn")
## Junk in Chefty's bed (net/components/junk_bed.gd): it's loaded once it has
## settled on the bed floor (moving slower than this, m/s); a bed already full of
## junk tips the next piece back out with this much lift (m/s).
const JUNK_BED_REST_SPEED: float = 0.6
const JUNK_BED_REFUSE_LIFT: float = 3.5
## E by the bed with junk in your arms heaves it in: the top of its arc is this
## far over the bed's rail (m, BED_CATCH_RAIL_Y), so it clears the tailgate.
const JUNK_HEAVE_CLEARANCE: float = 0.5
## ... turning a little as it goes, up to this fast about each axis (rad/s).
const JUNK_HEAVE_SPIN := Vector3(1.0, 1.5, 1.0)
## Set down, a piece of junk's look eases from your arms onto where it landed over this long (s).
const JUNK_SET_DOWN_SECONDS: float = 0.22
## Unloading at the store: one piece hops out every this many seconds, straight
## up at this speed (m/s), landing this far behind the bed's origin (m, bed
## space +Z, past the tailgate), and passing through the truck's walls for the
## start of its hop (s).
const JUNK_UNLOAD_GAP_SECONDS: float = 0.45
const JUNK_UNLOAD_LIFT: float = 4.5
const JUNK_UNLOAD_LAND_Z: float = 4.6
const JUNK_UNLOAD_THROUGH_SECONDS: float = 0.9
## ... and spreads out sideways this many times as far again as it lay from the
## bed's middle line, so the pieces don't land in one heap.
const JUNK_UNLOAD_SPREAD: float = 0.9
## A piece of junk falling faster than this (m/s) that stops is a landing: a
## thud for the heavy ones, a lighter knock for the rest (dB).
const JUNK_LAND_SPEED: float = 2.0
const JUNK_LAND_DB: float = -3.0
const JUNK_LAND_LIGHT_DB: float = -9.0
## How far apart junk lies in a yard (m). A yard's junk goes on the front lawn
## band (the TurfMasters signs' band): this far out to either side of the lot's
## middle (m) and this far toward the street (m), up to this many tries a piece.
const JUNK_SPACING: float = 1.6
const JUNK_LAWN_ACROSS := Vector2(3.0, 12.5)
const JUNK_LAWN_ALONG := Vector2(8.5, 17.0)
const JUNK_LAWN_TRIES: int = 16
## Last session's unsold junk, back on load (Shops._respawn_junk_left): what
## was in Chefty's bed goes back in the bed, laid in JUNK_BED_SPOTS (bed space,
## on its floor); what was left on the lot goes in a grid in STORE_LAYOUT's
## "junk_drop" reservation (StoreZone space: the first spot, the step across
## in x and along in z, the columns), at most JUNK_LEFT_MAX pieces.
const JUNK_BED_SPOTS: Array[Vector3] = [
	Vector3(-0.5, 0.9, 2.1), Vector3(0.5, 0.9, 2.1), Vector3(-0.5, 0.9, 1.15), Vector3(0.5, 0.9, 1.15),
	Vector3(-0.5, 0.9, 0.2), Vector3(0.5, 0.9, 0.2), Vector3(-0.5, 0.9, -0.75), Vector3(0.5, 0.9, -0.75),
]
const JUNK_LEFT_FIRST := Vector3(4.6, 0.02, 5.4)
const JUNK_LEFT_STEP := Vector2(1.2, 1.6)
const JUNK_LEFT_COLUMNS: int = 3
const JUNK_LEFT_MAX: int = 9
## How high above the scale's base a piece may sit and still count as on it (m),
## and the platform's top: a piece's base below it (less a little slack) is on
## the gravel beside it, not on it.
const JUNK_ON_SCALE_HEIGHT: float = 0.6
const JUNK_SCALE_TOP: float = 0.12
const JUNK_SCALE_TOP_SLACK: float = 0.06
## Hopping out at the store: it tumbles end over end this fast (rad/s, bed
## space, plus a random yaw spin up to JUNK_UNLOAD_YAW_SPIN either way), and a
## piece from the bed's front lands this share of the extra way to the tailgate
## farther back. A heave into the bed aims for this point (bed space).
const JUNK_UNLOAD_TUMBLE: float = -2.5
const JUNK_UNLOAD_YAW_SPIN: float = 1.0
const JUNK_UNLOAD_FRONT_SHARE: float = 0.3
const JUNK_HEAVE_AIM := Vector3(0.0, 1.1, 0.75)
## E at Chefty's tailgate with nothing in your arms and junk in the bed unloads
## it (gap-specs critic C22): within this far of the tailgate's middle (m).
const JUNK_TAILGATE_REACH: float = 1.8
## Someone standing behind the tailgate (out to this far past where the junk
## lands, m) has it land this far over to the side away from them (m).
const JUNK_UNLOAD_WATCH_BEYOND: float = 1.5
const JUNK_UNLOAD_SIDE: float = 2.6
## A landing thud plays at most this often for one piece (ms), when it was
## falling faster than JUNK_LAND_SPEED and this tick it falls at less than this
## share of that (it hit something).
const JUNK_LAND_DEBOUNCE_MS: int = 250
const JUNK_LAND_STOP_SHARE: float = 0.4
## Set down or thrown, a piece of junk passes through whoever let go of it until
## its box is clear of them (their capsule's radius plus this margin, m), or
## this long at most (s): its box is wide, and turning solid against your legs
## shoved you back (rec_setdown_1p frame 13).
const JUNK_CLEAR_MARGIN: float = 0.1
const JUNK_CLEAR_MAX_SECONDS: float = 3.0
## ... and never for less than this (s): a few physics steps, so the step that
## turns it solid has it where it was put down.
const JUNK_CLEAR_MIN_SECONDS: float = 0.1
## Rusty holds his gate for anyone still in the yard at closing: someone within
## this far outside the yard (m, so the gateway counts) keeps it open.
const RUSTY_GATE_HOLD_MARGIN: float = 0.8
## Rusty's dial scale reads full at this many kg; its needle swings like a
## spring: stiffness (1/s^2) and damping (1/s).
const RUSTY_SCALE_FULL_KG: float = 60.0
const RUSTY_SCALE_STIFFNESS: float = 55.0
const RUSTY_SCALE_DAMPING: float = 5.0
## A haggle: Rusty hums it over this long (s) before he answers.
const RUSTY_HAGGLE_THINK_SECONDS: float = 1.1
## His gate swings open or shut over this long (s) as the yard opens and closes.
const RUSTY_GATE_SWING_SECONDS: float = 1.4

# ---- shops: Lunch Money, the Snak-o-Matic and snacks (gap shops chunk 6)
# The food truck, the vending machine and what eating looks like (props/vehicles.gd
# build_food_truck, props/vending_machine.gd, player/snack_eater.gd,
# player/snack_gestures.gd, ui/buff_hud.gd). What each snack does is BUFFS under
# "# ---- shops" above; prices are SHOP_PRICES.
## Eating something (the "eat" gesture): how long it takes, hand up to stowed,
## and when each bite lands (s from the start). The munch plays on each bite.
const SNACK_EAT_SECONDS: float = 2.3
const SNACK_EAT_BITES: Array[float] = [0.62, 1.12, 1.62]
## Drinking (the "drink" gesture): how long, and the sip: the cup tipped to the
## lips from x to y (s). The slurp runs the sip; the "ahh" comes off the lip.
const SNACK_DRINK_SECONDS: float = 2.2
const SNACK_DRINK_SIP := Vector2(0.55, 1.45)
## A snack handed over this long ago (server s) is still eaten on screen by a
## peer that only hears of it now (a late snapshot); older ones are not.
const SNACK_SHOW_WINDOW: float = 4.0
## How long the hand-over takes before you start eating, by shop (s from the
## sale to the food in your hand): Dot reaching it out through the hatch, the
## machine dropping it to the tray and it hopping out of the flap.
const SNACK_HANDOVER_SECONDS: Dictionary = {"lunch_money": 1.1, "snak_o_matic": 1.3}
## The pass at the end of a hand-over, by shop: how long the food takes from the
## giver (Dot's hand, the machine's tray) to yours (s), and how high it arcs on
## the way (m). The machine's flap spits it out; you catch it.
const SNACK_PASS: Dictionary = {"lunch_money": Vector2(0.25, 0.05), "snak_o_matic": Vector2(0.3, 0.3)}
## How long before the food reaches you your hand starts out to meet it (s).
const SNACK_REACH_SECONDS: float = 0.45
## Dot's arm out through the hatch toward the buyer: how long it takes to come
## out and to go back after the pass (s), and how far toward them she aims (m;
## past her arm's length, so it stretches all the way).
const SNACK_GIVER_OUT_SECONDS: float = 0.45
const SNACK_GIVER_BACK_SECONDS: float = 0.4
const SNACK_GIVER_REACH: float = 0.75
## What a buff looks like on you while it runs (player/snack_eater.gd): Turbo's
## jitter (m) and wide eyes (eye height share); the crash's heavy lids (share)
## and nodding head (rad); coffee's twitch, one every x to y s; queasy's green face.
const BUFF_TURBO_JITTER: float = 0.007
const BUFF_TURBO_EYES: float = 1.25
const BUFF_CRASH_EYES: float = 0.35
const BUFF_CRASH_NOD: float = 0.16
const BUFF_COFFEE_TWITCH := Vector2(1.6, 3.2)
const BUFF_QUEASY_TINT := Color(0.42, 0.78, 0.28, 0.3)
## How long queasy's green takes to come on, and to drain off (s).
const BUFF_QUEASY_FADE_SECONDS: float = 0.8
## The Snak-o-Matic (props/vending_machine.gd): how long a snack takes to fall
## from its coil to the tray (s), the sad trombone's wait after the clunk when it
## keeps your money (s), and how long its screen holds a line after it has
## scrolled past (s).
const VEND_DROP_SECONDS: float = 0.42
const VEND_EAT_TROMBONE_DELAY: float = 0.55
const VEND_SCREEN_LINE_SECONDS: float = 5.0
## The machine stands on the store's front walk, whose top is this high (m).
const VEND_STAND_HEIGHT: float = 0.125
## Lunch Money's hatch: how long its awning takes to swing up or down (s), and
## how far up it props open (rad from shut: past level, so it shades the hatch
## and not the customer's eyes).
const FOOD_TRUCK_HATCH_SECONDS: float = 0.9
const FOOD_TRUCK_HATCH_OPEN: float = 1.9
## The HUD's snack icons (ui/buff_hud.gd): size (px) and gap, and when the last
## seconds of one start to blink (s).
const BUFF_HUD_PX: int = 30
const BUFF_HUD_GAP: int = 6
const BUFF_HUD_BLINK_SECONDS: float = 8.0

# ---- driving: streaming and spread-out builds (driving chunk E; levels/build_queue.gd,
# levels/town/town_streamer.gd; docs/DECISIONS.md "Builds are spread over frames")
## The world's dressing (levels/build_queue.gd): at most this much of a frame
## (ms) goes to building before the frame is let go. A joining peer built its
## whole world in one 2-5 s frame before, long enough for ENet to drop it.
const BUILD_MS_PER_FRAME: float = 8.0
## The town streamer (levels/town/town_streamer.gd): chunks of houses draw full
## (LOD 0) nearer the camera than this (m), simpler (LOD 1) nearer than
## STREAM_LOD1_METERS, only as the neighborhood's skyline beyond that, and not
## at all past STREAM_CULL_METERS.
const STREAM_LOD0_METERS: float = 110.0
const STREAM_LOD1_METERS: float = 260.0
const STREAM_CULL_METERS: float = 420.0
## A chunk only changes LOD this far (m) past the line it crossed, so one parked
## at a boundary doesn't swap back and forth.
const STREAM_HYSTERESIS_METERS: float = 12.0
## The streamer's build budget per frame (ms) once the town is up, and how often
## (s) it looks at where the camera is.
const STREAM_BUILD_MS_PER_FRAME: float = 3.0
const STREAM_TICK_SECONDS: float = 0.25
## Yard slots per streamed chunk, along one side of one street.
const STREAM_SLOTS_PER_CHUNK: int = 3
## The far skyline (one merged mesh per neighborhood) starts drawing this far
## out (m), under the LOD 1 houses it stands in for.
const STREAM_SKYLINE_BEGIN_METERS: float = 240.0
## A LOD swap fades the new look in and the old one out over this long (s), so
## a house never pops.
const STREAM_FADE_SECONDS: float = 0.6
## ENet (net/net.gd): a peer that hasn't acknowledged anything for this long (ms)
## is dropped, never sooner than the minimum. ENet's own 5 s minimum dropped a
## player whose machine stalled loading the world (docs/DECISIONS.md).
const ENET_TIMEOUT_LIMIT: int = 32
const ENET_TIMEOUT_MIN_MS: int = 12000
const ENET_TIMEOUT_MAX_MS: int = 30000
## The probe's join stall (net/dev/probe.gd join_stall_ms): the longest frame in
## this long (s) after a peer first links.
const JOIN_STALL_WINDOW_SECONDS: float = 30.0
## What the streamed town says (levels/town/town_streamer.gd). A grown-back
## lawn's leaves: up to this many drifts (a thin ragged bed of leaf colors with
## this many sides, and this many loose leaf cards over and around it), plus
## strays strewn over the rest of the front lawn, all scaled by the yard's mess.
## Each card is this long (m, min/max); a drift spreads this far (m, radius
## min/max) and rises this high (m) in its middle.
const STREAM_LEAF_DRIFTS_MAX: int = 12
const STREAM_LEAF_BED_SIDES: int = 13
const STREAM_LEAVES_PER_DRIFT: int = 64
const STREAM_LEAF_STRAYS: int = 120
const STREAM_LEAF_SIZE := Vector2(0.1, 0.18)
const STREAM_LEAF_DRIFT_RADIUS := Vector2(0.8, 1.8)
const STREAM_LEAF_HEAP_METERS: float = 0.05
## A drift's bed edge (and a stray leaf) sits this high (m), over the lawn's top
## (ART_LAWN_TOP) and its grass; the cards lie on it.
const STREAM_LEAF_BED_Y: float = 0.03
## How much darker a drift's bed is than its leaves (the shaded under-layer).
const STREAM_LEAF_BED_SHADE: float = 0.15
## LOD 1 (far) lawns: this share of the leaves, each this many times bigger, so
## they still read 110-260 m off without shimmering.
const STREAM_LEAF_FAR_SHARE: float = 0.25
const STREAM_LEAF_FAR_SCALE: float = 2.2
## The front lawn the leaves lie on, parcel space: x within this half width,
## z out to this (the curb side), and clear of the drive and walk within this x.
const STREAM_LEAF_LAWN_HALF_WIDTH: float = 17.0
const STREAM_LEAF_LAWN_FRONT_Z: float = 18.5
const STREAM_LEAF_CLEAR_X: float = 3.0
## TurfMasters™' sign on a poached lawn: this far either side of the drive (m,
## min/max) at this z (by the curb), turned up to this much (rad).
const STREAM_SIGN_SIDE_METERS := Vector2(6.0, 12.0)
const STREAM_SIGN_Z: float = 18.2
const STREAM_SIGN_TURN: float = 0.25
## A homeowner waiting on the porch for a crew waves at Chefty or a player that
## comes within this far (m), at most once per cooldown (s, plus a per-house
## jitter of up to this much), looking every STREAM_WAVE_LOOK_SECONDS.
const STREAM_WAVE_METERS: float = 28.0
const STREAM_WAVE_COOLDOWN_SECONDS: float = 5.0
const STREAM_WAVE_JITTER_SECONDS: float = 1.8
const STREAM_WAVE_LOOK_SECONDS: float = 0.3

# ---- R2c stage (the catch camera and bodies, docs/GAME.md "R2c: the catch's seams")
## StageCam.drawn_pose: an interpolated pose this far (m) from the real one is the
## physics interpolation's stale cache of a node placed somewhere new since the
## last frame, never motion (the fastest thing the stage films, a van, moves well
## under a meter a tick): the real pose is used.
const STAGE_CAM_STALE_METERS: float = 3.0
## StageCam: a shot that starts with the eye in your head (out of first person,
## out of a hiding spot) dissolves your own body in as the eye clears it: hidden
## until the eye is this far from your head (m), whole from STAGE_SELF_REVEAL_FAR.
## The same on the way back in. At 0.7 m your cap filled a third of the frame,
## at 1.2 m still a quarter (rec_r_gotcha_1p 120-126, before the dissolve).
const STAGE_SELF_REVEAL_NEAR: float = 1.4
const STAGE_SELF_REVEAL_FAR: float = 2.3
## StageCam "subjects" (the gotcha two-shot): anyone else in these groups who
## comes into the frame nearer than the subjects' far side plus this (m) fades
## out over STAGE_FRAME_OUT_SECONDS, and back in when the shot lets go.
const STAGE_FRAME_OUT_GROUPS: Array[StringName] = [&"players", &"nice_crew", &"crew_hands", &"homeowner", &"bonkable"]
const STAGE_FRAME_OUT_BEYOND: float = 1.5
const STAGE_FRAME_OUT_SECONDS: float = 0.25
## A teammate (or another caught pair) is never framed out for being in the shot:
## they're who comes to punch or throw at him, and the rescue plays in your own
## shot. Only one standing in the lens (flat, nearer the eye than
## STAGE_FRAME_OUT_TEAM_LENS m) fades, or one in front of you or him: at least
## STAGE_FRAME_OUT_TEAM_IN_FRONT m nearer the eye and overlapping on screen
## (bodies STAGE_FRAME_OUT_HALF_WIDTH wide each side). Once faded, the lens
## gets STAGE_FRAME_OUT_TEAM_SLACK m more and the overlap that share wider.
const STAGE_FRAME_OUT_TEAM_LENS: float = 1.4
const STAGE_FRAME_OUT_TEAM_IN_FRONT: float = 0.6
const STAGE_FRAME_OUT_TEAM_SLACK: float = 0.4
## Frame-out tests a body's flanks too, this far (m) either side of its middle.
const STAGE_FRAME_OUT_HALF_WIDTH: float = 0.4
## The gotcha's stage cheat for the caught player (rad): turned this far from
## facing him toward the camera (his own is CATCH_CHEAT_TURN), so your face reads
## three-quarters on, not in profile; your eyes stay on him.
const CATCH_VICTIM_CHEAT_TURN: float = 0.85
## A friend's rescue (encounter.gd _rpc_freed, R2c): the NICE BOY is knocked back
## at this speed (m/s; his stun's slide takes it to about 0.75 m) with stars for
## RESCUE_DIZZY_SECONDS; the freed player stumbles this far (m) out of his reach
## over RESCUE_STEP_SECONDS, turning to the rescuer, while their view eases back
## to first person over RESCUE_CAM_BLEND (s).
const RESCUE_KNOCKBACK_SPEED: float = 3.5
const RESCUE_DIZZY_SECONDS: float = 1.8
const RESCUE_STEP_METERS: float = 1.3
const RESCUE_STEP_SECONDS: float = 0.5
const RESCUE_CAM_BLEND: float = 0.9
## StageBody (R2c): a staged body's first blend that goes round someone keeps at
## least this far (m) from his middle (two bodies' half-widths).
const STAGE_BODY_CLEAR: float = 0.55
## Boarding (R2c): handed to the van further than this (m) from its door step, the
## body fades out over BOARD_FADE_SECONDS where it stands and back in
## BOARD_FADE_BACK s later, seated (the Shuttle's step up from there went through
## the van's side or slid metres in a blink); the rider's iris shuts at once.
const BOARD_NEAR_METERS: float = 1.6
const BOARD_FADE_SECONDS: float = 0.15
const BOARD_FADE_BACK: float = 1.15
## The itemized row (net/components/hotbar.gd _lay_flat, R2c): a thing whose
## longest side is this many times its shortest goes in lying down.
const CATCH_ROW_LAY_FLAT_RATIO: float = 3.0
## The escort's follow shot (R2c): the yaw offsets (rad) it may swing to, behind
## the pair, to see them past the van or a hedge, and how fast it swings (rad/s).
const ESCORT_CAM_BIASES: Array[float] = [0.0, 0.5, -0.5, 1.0, -1.0]
const ESCORT_CAM_BIAS_RATE: float = 0.9
## The escort's follow eye wants this much room (m) round it: closer to the van's
## side or a hedge, it swings to another of ESCORT_CAM_BIASES.
const ESCORT_CAM_ROOM: float = 1.2

# ---- audio:5 (UI, store, phone and day sounds; audio/ui_sounds.gd, tools/sfx_ui.py)
## A button's click, back or tab sound plays at most this often (ms): two quick
## clicks on two buttons both sound, one press's echo doesn't.
const UI_CLICK_GAP_MS: int = 50
## The pointer crossing buttons ticks at most this often (ms), so a sweep over a
## row of them is a few ticks, not a rattle.
const UI_HOVER_GAP_MS: int = 60
## A '+$' popping up pings a coin at most this often (ms): a bag-filling spree is
## a few pings, not a slot machine.
const COIN_GAP_MS: int = 90
## Getting up off a cot creaks this much softer (dB) than lying down on it.
const COT_CREAK_UP_DB: float = -5.0
## A cot's creak carries this far (m): the camp, not the whole store lot.
const COT_CREAK_MAX_DISTANCE: float = 25.0
## The phone comes up out of the pocket from this far below (px) over this long (s),
## landing with its chime (ui/phone.gd _slide_in).
const PHONE_SLIDE_PX: float = 120.0
const PHONE_SLIDE_SECONDS: float = 0.18
## It is fully opaque after this share of the slide, so it reads before it lands.
const PHONE_SLIDE_FADE_SHARE: float = 0.6
## Put away, it drops back the same way over this long (s), with its swish
## (ui/phone.gd close_phone), and only then stops being drawn.
const PHONE_PUTAWAY_SECONDS: float = 0.14
## Its fade starts this share of PHONE_PUTAWAY_SECONDS into the drop (and runs
## PHONE_PUTAWAY_SECONDS), so it visibly falls before it goes.
const PHONE_PUTAWAY_FADE_DELAY_SHARE: float = 0.4
## The payout card's printer starts this long (s) after the card shows: the cash
## is snatched the same moment (npcs/homeowner.gd), and that sound goes first.
const RECEIPT_PRINT_DELAY: float = 0.3
## The card then feeds up out of the printer from this far below (px) over this
## long (s): the receipt sound's 'brrrt' (tools/sfx_ui.py receipt, feed 0.42 s),
## settling as the paper tears.
const RECEIPT_FEED_PX: float = 70.0
const RECEIPT_FEED_SECONDS: float = 0.42
## The paper fades in over this share of the feed, under the first of the 'brrrt'.
const RECEIPT_FEED_FADE_SHARE: float = 0.25
## The morning's held phone buzz waits for Rise and Rake (and New Client) to finish,
## plus this long (s) (audio/cue_hooks.gd).
const CUE_BUZZ_AFTER_STINGERS: float = 0.25

# ---- audio:6 foley, task work, ambience and the horn (audio/player_foley.gd,
# audio/prop_foley.gd, levels/lots/task_looks.gd TASK_SOUNDS, audio/ambience.gd,
# tools/sfx_foley.py; docs/GAME.md "Foley: what the crew sounds like").
## Footsteps come off each drawn body's stride (CartoonBody's walk cycle): one
## where each foot comes down. Never two closer than this (s) from one body, so
## a sprint's quick feet sound every other step instead of a drum roll.
const FOLEY_STEP_MIN_SECONDS: float = 0.22
## The bank's own throttle on one body's footsteps (ms), under that.
const FOLEY_STEP_GAP_MS: int = 200
## Footstep trims (dB): every step, a teammate's on top of that (four crews' feet
## stay under the work), crouched (sneaking is quiet) and sprinting. At +4 your
## own steps in leaves peaked at -8 dBFS over music at -28 (rec_yardwalk_1p): a
## drum over everything. At 0 they peak near -12, under the rake and the horn.
const FOLEY_STEP_DB: float = 0.0
## The pavement step (a thin heel click) peaked 6 dB under a step in leaves on the
## store's lot (rec_walk_store_1p), and still 8 dB under at +4 on the yard's
## sidewalk (rec_crew_litter_1p): this evens it out.
const FOLEY_STEP_HARD_DB: float = 9.0
const FOLEY_STEP_OTHER_DB: float = -4.0
const FOLEY_STEP_CROUCH_DB: float = -9.0
const FOLEY_STEP_SPRINT_DB: float = 1.5
## Footsteps are close sounds: full volume inside this (m), gone past this.
const FOLEY_STEP_UNIT_SIZE: float = 2.5
const FOLEY_STEP_MAX_DISTANCE: float = 24.0
## How much a far footstep's distance low-pass takes off (dB; Godot's default is
## -24): a teammate's steps across the yard go soft, not muddy.
const FOLEY_STEP_MUFFLE_DB: float = -8.0
## A body whose stride moves slower than this (m/s) is shuffling, not stepping.
const FOLEY_STEP_MIN_SPEED: float = 1.0
## A landing thumps when the body came down faster than this (m/s).
const LAND_THUMP_SPEED: float = 6.0
## ...after at least this long in the air (s): a hop off a curb never thumps. A
## thrown body (it flies knocked flat) thumps the tick its fall, once faster than
## FOLEY_THROWN_FALLING (m/s), drops under FOLEY_THROWN_LANDED.
const FOLEY_LAND_MIN_AIR_SECONDS: float = 0.15
const FOLEY_THROWN_FALLING: float = 1.5
const FOLEY_THROWN_LANDED: float = 0.3
## A knocked-over ladder (audio/prop_foley.gd) crashes when its tumble turns less
## than this (rad) over FOLEY_LADDER_WINDOW (s), no sooner than the first of
## FOLEY_LADDER_FALL_SECONDS after it was knocked and no later than the second.
const FOLEY_LADDER_SETTLE_RAD: float = 0.06
const FOLEY_LADDER_WINDOW: float = 0.1
const FOLEY_LADDER_FALL_SECONDS: Vector2 = Vector2(0.25, 1.1)
## The punch wind-up's windmill whir: its level (dB) and how fast it fades in
## and out (dB per second).
const FOLEY_WINDUP_DB: float = -3.0
const FOLEY_LOOP_FADE_DB_PER_SECOND: float = 120.0
## The horn on Chefty's ride to and from a job (H): at most once per this (s).
const HORN_COOLDOWN_SECONDS: float = 0.6
## Task work heard at the spot (task_looks.gd TASK_SOUNDS): a held tool's sound
## (the shears, the squeegee, the pool net, the goop) at most once per this
## many ms from one 2 m patch; a hand task (litter, weeds) is one per press,
## and the roof's 'rake' is a whole stroke.
const TASK_SFX_GAP_MS: Dictionary = {
	"snip": 260, "rake": 450, "squeegee": 480, "gutter_gloop": 380, "splash_small": 420,
	"litter_crinkle": 160, "weed_pluck": 160,
}
## The patch (m, square) that TASK_SFX_GAP_MS counts per, and how many patches
## task_looks.gd remembers before it forgets the ones whose gap has run out.
const TASK_SFX_PATCH_METERS: float = 2.0
const TASK_SFX_PATCH_MEMORY: int = 64
## Night (audio/ambience.gd): from this hour the birds stop and the crickets
## fade in over AMBIENCE_NIGHT_FADE_HOURS; they sit this loud (dB).
const AMBIENCE_NIGHT_FROM_HOUR: float = 19.5
const AMBIENCE_NIGHT_FADE_HOURS: float = 0.5
## At -15 the chirps sat 10 dB under the night's breeze, which itself sat at
## -39 dBFS (rec_night_1p): no night at all. At -7 they're the top of the bed.
const AMBIENCE_CRICKETS_DB: float = -7.0
## How fast the crickets follow you in and out of doors (dB per second).
const AMBIENCE_CRICKETS_FADE_DB_PER_SECOND: float = 30.0
## An owl a few yards over at night: seconds between, how far (m) and how high.
const AMBIENCE_OWL_GAP: Vector2 = Vector2(25.0, 60.0)
const AMBIENCE_OWL_RANGE: Vector2 = Vector2(25.0, 45.0)
const AMBIENCE_OWL_HEIGHT: Vector2 = Vector2(5.0, 10.0)
## Homie Depot's hum through its sliding doors (StoreZone space), how loud (dB),
## and its reach: full inside this (m), gone past that.
const AMBIENCE_STORE_DOORS: Vector3 = Vector3(-10.0, 2.0, -2.0)
const AMBIENCE_STORE_HUM_DB: float = -6.0
const AMBIENCE_STORE_HUM_UNIT_SIZE: float = 3.0
const AMBIENCE_STORE_HUM_MAX_DISTANCE: float = 28.0
## The store PA's ding-dong (while Homie Depot is open), heard from its doors.
const AMBIENCE_PA_GAP: Vector2 = Vector2(40.0, 90.0)
const AMBIENCE_PA_FIRST: Vector2 = Vector2(12.0, 30.0)
## A shopping cart rattling somewhere across the store's lot, and how far off (m).
const AMBIENCE_CART_GAP: Vector2 = Vector2(20.0, 50.0)
const AMBIENCE_CART_RANGE: Vector2 = Vector2(10.0, 22.0)
## A neighbor mowing a few yards over, by day only (until this hour), how far
## off (m) and how loud (dB); heard to AMBIENCE_FAR_MAX_DISTANCE.
const AMBIENCE_MOWER_GAP: Vector2 = Vector2(35.0, 90.0)
const AMBIENCE_MOWER_UNTIL_HOUR: float = 19.0
const AMBIENCE_MOWER_RANGE: Vector2 = Vector2(45.0, 70.0)
const AMBIENCE_MOWER_DB: float = -3.0
const AMBIENCE_FAR_MAX_DISTANCE: float = 130.0

# ---- driving: crash comedy and the bed (driving chunk C3, net/components/chefty_drive.gd
# and chefty_crash.gd; docs/GAME.md "Crash comedy"). First guesses, tuned by
# crashing it with a crew aboard. TODO(balance): not in the workbook.
## A crash is Chefty losing at least this much speed into something solid (m/s,
## the speed it hit with, square on); none again for this long (s).
const CHEFTY_CRASH_MIN_SPEED: float = 6.0
const CHEFTY_CRASH_COOLDOWN: float = 0.8
## A hit's lost speed is added up over the ticks it takes, at most this long (s).
const CHEFTY_CRASH_GATHER_SECONDS: float = 0.1
## Harder than this (m/s), the riders in the bed fly out; harder than this, Chefty
## barrel-rolls on screen (the chassis never flips) and the horn sticks.
const CHEFTY_EJECT_SPEED: float = 11.0
const CHEFTY_TUMBLE_SPEED: float = 16.0
## Bags out of the bed per m/s over CHEFTY_CRASH_MIN_SPEED (at least one), and the
## Chefty Net's share of every spill.
const CHEFTY_SPILL_PER_MPS: float = 0.5
const CHEFTY_NET_SPILL_SHARE: float = 0.5
## A drift (handbrake, sliding) faster than this (m/s) spills a bag with this chance
## per second, sliding sideways faster than CHEFTY_DRIFT_SPILL_SLIP (m/s).
const CHEFTY_DRIFT_SPILL_SPEED: float = 10.0
const CHEFTY_DRIFT_SPILL_CHANCE: float = 0.25
const CHEFTY_DRIFT_SPILL_SLIP: float = 3.0
## A spilled bag keeps this share of Chefty's speed from before the hit, goes up
## this fast (m/s), out over its side rail about this fast (m/s), and the bed
## won't catch it again for this long (s).
## (Played with a crew: at a third of the speed and 5 m/s up, the bags hit the back
## of the cab and dropped straight back into the bed, which caught them again.)
const CHEFTY_SPILL_CARRY: float = 0.12
const CHEFTY_SPILL_UP: float = 6.0
const CHEFTY_SPILL_SIDE: float = 3.8
const CHEFTY_SPILL_NO_CATCH: float = 3.0
## Bags and riders thrown out of the bed pass through the truck (and the bags
## through each other) this long (s), long enough to clear its rails and cab.
const CHEFTY_SPILL_CLEAR_SECONDS: float = 0.45
## A rider thrown out of the bed keeps this share of Chefty's speed, plus this much
## up (m/s) and up to CHEFTY_EJECT_SIDE out to their side.
const CHEFTY_EJECT_SHARE: float = 0.7
const CHEFTY_EJECT_UP: float = 7.0
## (Little sideways: the bags go out over the side rails, the riders forward over
## the cab, so nobody lands under a bag.)
const CHEFTY_EJECT_SIDE: float = 0.8
## The barrel roll: how long it takes (s), how high it hops (m), and the height it
## rolls about (m, Chefty's middle). The stuck horn blares this long (s).
const CHEFTY_TUMBLE_SECONDS: float = 1.15
const CHEFTY_TUMBLE_HOP: float = 1.7
const CHEFTY_TUMBLE_PIVOT_Y: float = 1.1
const CHEFTY_HORN_STUCK_SECONDS: float = 3.0
## Being Chefty'd: someone standing within this far (m) ahead of the bumper (or
## behind the tailgate, backing up), across the truck's width plus
## CHEFTY_RUNOVER_SIDE, at more than CHEFTY_RUNOVER_SPEED (m/s), is bonked flying
## with this share of Chefty's speed and this much up (m/s); once per person per
## CHEFTY_RUNOVER_COOLDOWN (s).
const CHEFTY_RUNOVER_SPEED: float = 4.0
const CHEFTY_RUNOVER_REACH: float = 1.0
const CHEFTY_RUNOVER_SIDE: float = 0.35
const CHEFTY_RUNOVER_SHARE: float = 0.9
const CHEFTY_RUNOVER_UP: float = 4.5
const CHEFTY_RUNOVER_COOLDOWN: float = 1.5
## Chefty's half-length and half-width over the ground (m), for run-overs and knock-overs.
const CHEFTY_HALF_LENGTH: float = 3.0
const CHEFTY_HALF_WIDTH: float = 1.15
## Mailboxes and curbside bins (levels/town/town_dressing.gd "town_knockables")
## go flying when Chefty's body passes within this much of them (m) faster than
## CHEFTY_KNOCK_MIN_SPEED (m/s); each mailbox adds HEAT_MAILBOX. The flying one
## keeps this share of Chefty's speed, goes up this fast (m/s), lies where it
## lands, and the town stands it back up once nobody's within
## CHEFTY_KNOCK_RESTORE_METERS for CHEFTY_KNOCK_RESTORE_SECONDS (s). Knocking the
## same one again only heats things up after CHEFTY_KNOCK_RESTORE_SECONDS.
const CHEFTY_KNOCK_PAD: float = 0.35
const CHEFTY_KNOCK_MIN_SPEED: float = 2.0
const CHEFTY_KNOCK_CARRY: float = 0.75
const CHEFTY_KNOCK_UP: float = 4.0
const CHEFTY_KNOCK_RESTORE_SECONDS: float = 45.0
const CHEFTY_KNOCK_RESTORE_METERS: float = 70.0
const HEAT_MAILBOX: float = 2.0
## Leaf piles in a job yard: Chefty rolling faster than CHEFTY_PLOW_MIN_SPEED (m/s)
## plows a stroke this wide (m) at this strength (a rake's is RAKE_STRENGTH) every
## CHEFTY_PLOW_SECONDS (leaf_field.gd host_plow).
const CHEFTY_PLOW_MIN_SPEED: float = 1.5
const CHEFTY_PLOW_WIDTH: float = 2.2
const CHEFTY_PLOW_STRENGTH: float = 140.0
const CHEFTY_PLOW_SECONDS: float = 0.12
## Parked on the job yard's lawn (inside the yard, off the drive's strip this wide
## each side of x 0, m) for CHEFTY_LAWN_PARK_SECONDS: the homeowner yells and
## their mood drops a step (npcs/homeowner.gd host_grumble).
const CHEFTY_LAWN_PARK_SECONDS: float = 6.0
const CHEFTY_DRIVE_HALF_WIDTH: float = 2.6
## The horn within this far (m) of the job yard's middle: heat per second held,
## and the homeowner's "Yes, I SEE you." at most once per this long (s).
const CHEFTY_HORN_YARD_METERS: float = 34.0
const CHEFTY_HORN_HEAT_PER_SECOND: float = 0.6
const CHEFTY_HORN_LINE_COOLDOWN: float = 10.0
## Soft things Chefty hits (props, a NICE BOY): pushed with this share of
## Chefty's speed and this much up (m/s), host only (net_prop.gd host_vehicle_push).
const CHEFTY_PUSH_SHARE: float = 0.8
const CHEFTY_PUSH_UP: float = 2.0
## A dent's looks: how far the front bumper droops at each dent count (rad), and
## the hubcap that rolls off at the second dent: how fast it rolls (m/s) and how
## long it stays before it's gone (s).
const CHEFTY_DENT_BUMPER_DROOP: Array[float] = [0.0, 0.22, 0.38, 0.55]
const CHEFTY_HUBCAP_SPEED: float = 5.5
const CHEFTY_HUBCAP_SECONDS: float = 9.0
## A crash's jolt on every peer (one that doesn't barrel-roll): the drawn body
## pitches back end up about its front bumper (CHEFTY_JOLT_PIVOT, Chefty's space;
## the tailgate's for a hit backing up) by up to CHEFTY_JOLT_PITCH rad at a
## CHEFTY_TUMBLE_SPEED hit, then rocks back and settles, a swing at
## CHEFTY_JOLT_RATE rad/s damped by CHEFTY_JOLT_DAMP per s, over CHEFTY_JOLT_SECONDS.
const CHEFTY_JOLT_SECONDS: float = 0.9
const CHEFTY_JOLT_PITCH: float = 0.16
const CHEFTY_JOLT_RATE: float = 13.0
const CHEFTY_JOLT_DAMP: float = 5.5
const CHEFTY_JOLT_PIVOT := Vector3(0.0, 0.35, -2.95)
## The view shakes for whoever rides along, or stands within CHEFTY_SHAKE_NEAR (m):
## up to CHEFTY_SHAKE_METERS_MAX (m, the camera's own offsets) at a
## CHEFTY_TUMBLE_SPEED hit, fading out over CHEFTY_SHAKE_SECONDS (s).
const CHEFTY_SHAKE_SECONDS: float = 0.6
const CHEFTY_SHAKE_METERS_MAX: float = 0.14
const CHEFTY_SHAKE_NEAR: float = 14.0
## Standing in Chefty's bed your first-person eye sits this much higher (m). It was
## 0.75 to see over the cab-over's roof when its back wall was solid; with the rear
## window (p1-dash) a standing eye sees the far road over the roof and, through the
## window and the windshield, the backs of the cab's heads and the road ahead.
const CHEFTY_BED_EYE_LIFT: float = 0.1
## It eases on and off this fast (m/s): about a third of a second each way.
const CHEFTY_BED_EYE_EASE: float = 2.2
## Thrown (a toss, a crash or a bail out of Chefty): the first this many seconds
## count as lifting off even on the ground; after that, touching down is landing,
## and that's when you go flat with stars (player.gd _step_stunned).
const THROWN_LIFTOFF_SECONDS: float = 0.15
## A throw's clock starts at this (s); it ends on the ground once under 1.2 s are
## left (player.gd).
const THROWN_SECONDS: float = 1.5
## Host: speed lost into something (m/s) below this in a tick is a scrape, not
## contact, and doesn't start adding up a crash.
const CHEFTY_CONTACT_SPEED: float = 0.3
## Host: a rider who just left Chefty flying (thrown out of the bed in a crash, or
## a bail) can't be Chefty'd by it for this long (s): the host's copy of them still
## stands on their seat, inside its footprint, until their flight comes back.
## (Played with a crew: the front bed row was bonked sideways off its own truck
## instead of sailing over the cab.)
const CHEFTY_EJECT_SPARE_SECONDS: float = 1.5
## Run-overs only look this far above or below Chefty's chassis (m); anyone whose
## feet are higher than CHEFTY_RUNOVER_ON_TOP_Y over it, within its length, is
## standing on it (the bed, the hood), not in its way. Who's Chefty'd is also
## pushed this fast (m/s) out to the side they stood on.
const CHEFTY_RUNOVER_TALL: float = 2.5
const CHEFTY_RUNOVER_ON_TOP_Y: float = 0.8
const CHEFTY_RUNOVER_ASIDE: float = 2.0
## Mailboxes and bins further than this from Chefty along x or z (m) aren't
## checked against its footprint at all (a cheap first cut).
const CHEFTY_NEAR_BOX: float = 5.0
## A knocked mailbox or bin also flies out this fast (m/s) to the side it was
## on, and weighs this much (kg; it only falls and tumbles).
const CHEFTY_KNOCK_SIDE: float = 1.5
const CHEFTY_KNOCK_MASS_MAILBOX: float = 6.0
const CHEFTY_KNOCK_MASS_BIN: float = 9.0
## The rolling hubcap keeps this share of Chefty's speed and hops up this fast (m/s).
const CHEFTY_HUBCAP_CARRY: float = 0.3
const CHEFTY_HUBCAP_UP: float = 0.8
## A crash's camera shake: the side-to-side wobble's two rates (x, z: rad/s,
## multiplied) and the up-and-down one (y), uneven so it never reads as a loop.
const CHEFTY_SHAKE_RATES := Vector3(53.0, 41.0, 17.0)
## A vehicle chassis this far (m) under the ground it should stand on is sunk, and
## is stood back up on it, found by a ray from this far over its wheels (m)
## (net/components/vehicle_sim.gd; a crash's shove out of a car can sink it).
const VEHICLE_SUNK_MARGIN: float = 0.3
const VEHICLE_SUNK_LOOK_UP: float = 2.2
## A homeowner's yell about Chefty (npcs/homeowner.gd host_grumble) stays over
## their head this long (s).
const HOMEOWNER_YELL_SECONDS: float = 4.5

# ---- driving: the Gutter Shredder (driving chunk G1; player/skate.gd, player/skate_view.gd,
# docs/GAME.md "The Gutter Shredder"). First guesses, tuned by riding it. TODO(balance): not
# in the workbook. Its price is SHOP_PRICES["skateboard"].
## A kick-push adds this much speed (m/s), eased in over SKATE_PUSH_EASE seconds, at
## most one every SKATE_PUSH_SECONDS while move_forward is held, never past
## SKATE_MAX_PUSH_SPEED (rolling faster than that, a push does nothing).
const SKATE_PUSH_SPEED: float = 2.4
const SKATE_PUSH_SECONDS: float = 0.42
const SKATE_PUSH_EASE: float = 0.16
const SKATE_MAX_PUSH_SPEED: float = 9.0
## Nothing rolls faster than this (off the ramp, a long tuck).
const SKATE_TOP_SPEED: float = 13.0
## Rolling with nothing pressed: speed lost per second on pavement (m/s per s);
## tucked down (crouch held), only this share of it.
const SKATE_COAST_DECEL: float = 0.45
const SKATE_TUCK_DRAG_SHARE: float = 0.5
## move_back: dragging a foot (m/s per s).
const SKATE_BRAKE_DECEL: float = 5.0
## Grass and water: their drag (m/s per s), and rolling onto them faster than this is a lawn bail.
const SKATE_GRASS_DECEL: float = 7.0
const SKATE_LAWN_BAIL_SPEED: float = 5.0
## Carving on move_left/move_right: turn rate (rad/s) from SKATE_CARVE_FULL_AT m/s up;
## slower below it, down to SKATE_CARVE_STILL_SHARE of it standing still (a kick turn).
const SKATE_CARVE_RATE: float = 2.4
const SKATE_CARVE_FULL_AT: float = 3.0
const SKATE_CARVE_STILL_SHARE: float = 0.55
## How fast the wheels drag the way you're rolling round to the way the board
## points (rad/s), and how much of the speed a sideways slide scrubs off per second
## (times the slide's sine).
const SKATE_GRIP_RATE: float = 6.0
const SKATE_SLIDE_SCRUB: float = 2.5
## Ollie: the pop (m/s up). Leaving the ramp's lip going up, the board adds this
## much more (m/s), so Marty's ramp throws you.
const SKATE_OLLIE_SPEED: float = 4.6
const SKATE_RAMP_POP: float = 0.6
## In the air: spinning on move_left/move_right (rad/s); a kickflip or heelflip takes this long.
const SKATE_SPIN_RATE: float = 7.5
const SKATE_FLIP_SECONDS: float = 0.45
## Landing with this little of a flip left (s), the feet catch the board: it lands clean.
const SKATE_FLIP_CATCH_SECONDS: float = 0.12
## A landing is clean within this angle (rad) of the way you're rolling, forward or fakie.
## Slower than SKATE_LAND_ANY_SPEED, any landing is clean.
const SKATE_LAND_ANGLE: float = 0.6
const SKATE_LAND_ANY_SPEED: float = 1.5
## Air shorter than this (s) is a bump, not a jump: nothing is scored.
const SKATE_MIN_AIR_SECONDS: float = 0.15
## Hitting a wall faster than this (m/s straight into it) is a bail.
const SKATE_WALL_BAIL_SPEED: float = 3.5
## A wipeout: down this long, thrown along the way you were going with this share
## of the speed, and this much up (m/s).
const SKATE_WIPEOUT_SECONDS: float = 2.2
const SKATE_WIPEOUT_THROW_SHARE: float = 0.55
const SKATE_WIPEOUT_THROW_UP: float = 2.4
## The heaviest thing in hand you can ride with (kg): a rake yes, a trash can no.
## Leaf bags ride whatever they weigh: a stuffed bag is floppy enough to hug.
const SKATE_MAX_CARRY_KG: float = 4.0
const SKATE_CARRY_ANY_WEIGHT: Array[String] = ["leaf_bag"]
## Curb grinds: landing within this far (m) of a curb's line, the board within this
## angle (rad) of it. Grinding loses this much speed per second, and below
## SKATE_GRIND_MIN_SPEED you drop off. The curb's top (m), where the board rides
## (levels/town/street_builder.gd's curb is 0.2 tall, centred on the ground).
const SKATE_GRIND_SNAP: float = 0.6
const SKATE_GRIND_ANGLE: float = 0.44
const SKATE_GRIND_DECEL: float = 0.8
const SKATE_GRIND_MIN_SPEED: float = 1.5
const SKATE_CURB_TOP: float = 0.1
## A clean landing this soon (s) after the last adds to the combo (x2, x3 ...).
const SKATE_COMBO_WINDOW: float = 1.6
## Points (bragging only): each trick in a line, spins per half turn, grinds per second.
const SKATE_TRICK_POINTS: Dictionary = {"ollie": 100, "kickflip": 200, "heelflip": 200, "spin": 150, "grab": 150, "grind": 120}
## Rolling into someone (a crewmate, a passer-by, a NICE BOY) faster than this
## (m/s), this close (m): they get a light bonk and you go down.
const SKATE_BONK_SPEED: float = 3.0
const SKATE_BONK_RADIUS: float = 0.8
## The host takes a skater's word for a bump within this much more distance (m), for lag.
const SKATE_BONK_SLACK: float = 1.5
## Rolling into a leaf pile faster than this (m/s) dives you into it.
const SKATE_PILE_SPEED: float = 2.0
## The board (props/gear_models.gd): how high its deck's top is (m), where the rider stands.
const SKATE_DECK_HEIGHT: float = 0.12
## Stepping off faster than this (m/s) leaves you running at it, with a stumble.
const SKATE_STEP_OFF_SPEED: float = 8.0
## Hopping on and stepping off (s): the board drops under you, or flicks up into your hand.
const SKATE_MOUNT_SECONDS: float = 0.22
## A bail: the board clatters off on its own for this long (s), this fast (share of your speed).
const SKATE_BOARD_FLY_SECONDS: float = 1.2
const SKATE_BOARD_FLY_SHARE: float = 0.8
## The rolling sound (player/skate_view.gd, until audio/board_sound.gd exists): its
## volume at a crawl and at SKATE_MAX_PUSH_SPEED (dB), its pitch over the same,
## and how far it carries (m).
const SKATE_ROLL_DB := Vector2(-20.0, -5.0)
const SKATE_ROLL_PITCH := Vector2(0.75, 1.3)
const SKATE_SOUND_MAX_DISTANCE: float = 40.0
## The rider's lean into a carve (rad per rad/s of turning), at most SKATE_LEAN_MAX.
const SKATE_LEAN_PER_TURN: float = 0.16
const SKATE_LEAN_MAX: float = 0.45
## The trick popup (ui/trick_popup.gd): how long a line stays up (s).
const SKATE_POPUP_SECONDS: float = 1.8
## Rolling off a lip while the wheels were climbing faster than this (m/s) leaves
## you going up it; the climb remembered fades this fast (m/s per s).
const SKATE_RAMP_CLIMB_MIN: float = 0.5
const SKATE_RAMP_CLIMB_FADE: float = 20.0
## Holding tuck in the air grabs the board once you've been up this long (s).
const SKATE_GRAB_DELAY: float = 0.08
## Turned this far in the air (rad), the board shows as a spin to everyone.
const SKATE_SPIN_SHOW_RAD: float = 1.2
## Grinds: a landing this near a curb's end (m) doesn't catch it; the grind ends
## this near the far end (m); the board is held down on the curb at this (m/s);
## a grind shorter than this (s) scores nothing.
const SKATE_GRIND_END_MARGIN: float = 0.3
const SKATE_GRIND_RUN_OUT: float = 0.1
const SKATE_GRIND_HOLD_DOWN: float = -0.5
const SKATE_GRIND_MIN_SECONDS: float = 0.15
## Run into a NICE BOY or a passer-by this square on (the dot of your way and the
## way to them), and it's a bump, not a scrape past.
const SKATE_BONK_FACING: float = 0.3
## A skate bonk lifts its target this much (m/s) on top of the light punch's shove.
const SKATE_BONK_LIFT: float = 1.2
## The loose board after a bail (player/skate_view.gd): it pops up this fast (m/s)
## and falls at this (m/s^2); hitting the ground faster than SKATE_BOARD_CLACK_SPEED
## (m/s) clacks, and each bounce keeps SKATE_BOARD_BOUNCE_KEEP of its slide.
const SKATE_BOARD_FLY_UP: float = 2.6
const SKATE_BOARD_FLY_GRAVITY: float = 9.8
const SKATE_BOARD_CLACK_SPEED: float = 1.2
const SKATE_BOARD_BOUNCE_KEEP: float = 0.6
## It finds the ground under it each tick: a ray from this far above it (m) down
## this far (m). Still above the ground when its tumble is over, it keeps falling
## for up to SKATE_BOARD_FALL_MAX more seconds.
const SKATE_BOARD_GROUND_ABOVE: float = 0.15
const SKATE_BOARD_GROUND_BELOW: float = 30.0
const SKATE_BOARD_FALL_MAX: float = 1.5
## The rider's lean follows the carve at this rate (1/s).
const SKATE_LEAN_RATE: float = 8.0
## The grind's scrape (player/skate_view.gd): its volume at a crawl and at
## SKATE_MAX_PUSH_SPEED (dB).
const SKATE_GRIND_DB := Vector2(-8.0, 0.0)

# ---- driving:G2 the wipeout flop and skitching (player/cartoon_body.gd flop(),
# player/skate.gd, player/skate_view.gd; docs/GAME.md "The Gutter Shredder").
# First guesses, tuned by riding it. TODO(balance): not in the workbook.
## The flop: the tumble lasts this long (s), turning head over heels about the
## body's middle (FLOP_CENTER_Y m up) this many whole turns before it settles onto
## its back; the settle starts this far into it (share of the tumble).
const FLOP_TUMBLE_SECONDS: float = 0.95
const FLOP_TURNS: int = 1
const FLOP_CENTER_Y: float = 0.9
const FLOP_SETTLE_FROM: float = 0.3
## How sharply the tumble slows (the exponent on 1 - t: bigger, more of it early).
const FLOP_SPIN_EASE: float = 2.2
## The bounces after it lands: the first this high (m), each next one keeping
## FLOP_BOUNCE_KEEP of it, FLOP_BOUNCE_SECONDS apart. It lands FLOP_FIRST_HIT_SECONDS in
## (the throw's own arc, SKATE_WIPEOUT_THROW_UP under gravity, comes down about then).
const FLOP_BOUNCE_HEIGHT: float = 0.22
const FLOP_BOUNCE_KEEP: float = 0.45
const FLOP_BOUNCE_SECONDS: float = 0.26
const FLOP_FIRST_HIT_SECONDS: float = 0.42
## Nothing of the tumbling body goes below the ground: its head (this round), its
## hips, hands and feet, with this much room to spare until it settles (m).
const FLOP_HEAD_RADIUS: float = 0.2
const FLOP_GROUND_ROOM: float = 0.03
## Your own eyes in a flop (the first-person camera rides the head): they dip
## toward the ground this far (rad) halfway through, then end up at the sky the
## way a knock leaves them.
const FLOP_LOOK_DIP: float = 0.9
## Your own eyes never go into a wall, a fence or a truck on the way over: they
## stop this far (m) short of whatever is between the body's middle and the head.
const FLOP_EYE_ROOM: float = 0.3
## A wall bail bounces you back off it at this share of the speed you hit it with.
const SKATE_WALL_REBOUND: float = 0.35
## Up again: woozy for this long (s), swaying this far (rad) at this rate (Hz),
## your own view rolling FLOP_WOOZY_VIEW_SHARE of the sway. The stars stay till then.
const FLOP_WOOZY_SECONDS: float = 1.1
const FLOP_WOOZY_SWAY: float = 0.16
const FLOP_WOOZY_HZ: float = 1.6
const FLOP_WOOZY_VIEW_SHARE: float = 0.25
## The head lolls this share of the body's sway.
const FLOP_WOOZY_FACE_SHARE: float = 0.8
## The stars outlast the knock by this long (s): they're still circling as you get up.
const FLOP_STARS_GET_UP: float = 0.4
## On someone else's peer a wipeout's knock waits at most this long (s) for its
## flop (drawn a beat later there) before the body goes down the plain way.
const FLOP_WAIT_MAX: float = 0.4
## Mid-flop flailing: the legs kick, the arms wave and windmill at these rates
## (rad/s: legs, arms out, arms forward), swinging this far (rad, same order), the
## arms thrown this far up (rad) around which they wave.
const FLOP_FLAIL_RATE := Vector3(19.0, 23.0, 17.0)
const FLOP_FLAIL_SWING := Vector3(0.9, 0.6, 0.7)
const FLOP_FLAIL_ARMS_UP: float = 2.0
## The flop's landing: the thud's level (dB), and each smaller bounce's on top of
## its own strength (dB).
const FLOP_THUD_DB: float = -2.0
const FLOP_BOUNCE_DB: float = -3.0
## The loose board after a bail dissolves near a camera: starting this near (m, x)
## and all but gone (SKATE_BOARD_LENS_MAX_FADE) this near (m, y).
const SKATE_BOARD_LENS := Vector2(0.8, 0.35)
const SKATE_BOARD_LENS_MAX_FADE: float = 0.9
## Skitching: E at Chefty's tail on the board grabs on beside it, this far to
## the side of chefty.tow_point() (m) and this far nearer the truck (m), if you're
## within SKITCH_GRAB_REACH of that spot and rolling within SKITCH_GRAB_REL_SPEED of
## Chefty. The towed board follows that spot with a spring (1/s), its pull
## correcting at most SKITCH_PULL_MAX (m/s) on top of Chefty's own speed.
const SKITCH_SIDE: float = 1.6
const SKITCH_IN: float = 0.7
const SKITCH_GRAB_REACH: float = 1.8
const SKITCH_GRAB_REL_SPEED: float = 4.0
const SKITCH_SPRING: float = 9.0
const SKITCH_PULL_MAX: float = 4.0
## Only the spot on your own side of the truck is offered. A Chefty slower than
## SKITCH_PARKED_SPEED (m/s) is parked: its tailgate is the bed's (E hops in), so
## you grab on only from beside its corner, at least this share of SKITCH_SIDE out.
const SKITCH_PARKED_SPEED: float = 1.0
const SKITCH_PARKED_SIDE_SHARE: float = 0.6
## On everyone else's peer a skater's side is put right while they're towed once
## their replicated position is this share of SKITCH_SIDE out on the other side.
const SKITCH_SIDE_SURE: float = 0.4
## E's "Hang on" sits this far (m) over the hand's spot on the bumper.
const SKITCH_HINT_RISE: float = 0.6
## Towed: knees bent this share of a tuck, the torso bent this much more (rad)
## toward the bumper, your own first-person arm stretching up to this share of its
## length to keep its hand on it, and the slap of the grab at this level (dB).
const SKITCH_TOW_CROUCH: float = 0.5
const SKITCH_TOW_LEAN: float = 0.45
const SKITCH_FP_GRIP_STRETCH: float = 1.6
const SKITCH_GRAB_DB: float = -4.0
## The board turns with Chefty at this rate (1/s); your head looks round at most
## CHEFTY_SEAT_LOOK_YAW either way while you hang on, like a seat, and comes back
## round to the board at SKITCH_LOOK_BACK_RATE (rad/s) once you let go.
const SKITCH_YAW_RATE: float = 10.0
const SKITCH_LOOK_BACK_RATE: float = 4.0
## Letting go, whether you meant to or not: Chefty faster than SKITCH_MAX_SPEED (m/s)
## tears the tailgate out of your hand; turning harder than SKITCH_TURN_RATE (rad/s)
## above SKITCH_TURN_MIN_SPEED (m/s) flings you wide (SKITCH_FLING_SHARE of the
## speed, outward); braking harder than SKITCH_BRAKE_DECEL (m/s^2) above
## SKITCH_BRAKE_MIN_SPEED tears the bumper out of your hand: a flop off its corner,
## thrown SKITCH_SLAM_BACK m/s slower than you were going (the collision exception
## keeps you out of the tailgate); a crash shakes you off; drifting SKITCH_BREAK_METERS off the spot, you've let go.
const SKITCH_MAX_SPEED: float = 15.0
## ... after this long above it, all told (s; it drains back while you're under).
const SKITCH_STRAIN_SECONDS: float = 1.2
const SKITCH_TURN_RATE: float = 1.2
const SKITCH_TURN_MIN_SPEED: float = 8.0
const SKITCH_FLING_SHARE: float = 0.35
const SKITCH_BRAKE_DECEL: float = 9.0
const SKITCH_BRAKE_MIN_SPEED: float = 4.0
const SKITCH_SLAM_BACK: float = 3.0
const SKITCH_BREAK_METERS: float = 1.6
## Let go (or shaken off), you still pass through Chefty's tail for this long (s):
## its collision runs a tick or two behind the truck you see, right where you were.
const SKITCH_CLEAR_SECONDS: float = 0.6
## Chefty's turn rate and braking are read smoothed over this long (s), so one
## jolt of the sim's reconciliation isn't a fling.
const SKITCH_READ_SMOOTH: float = 0.12
## Everyone else sees the skater drawn on the spot behind their own Chefty, eased
## onto it and off it over this long (s).
const SKITCH_PIN_BLEND: float = 0.3
## The hand on Chefty's rear bumper (props/vehicles.gd: chrome at y 0.74, its back
## face at z 2.88, 1.18 either side), in Chefty's space for a skater on its right
## (x is mirrored on the left): crouched low, one hand on the chrome.
const SKITCH_GRIP := Vector3(1.05, 0.8, 2.86)

# ---- R2c hide
# The seams between hiding's beats (docs/GAME.md "Hiding, R2c"): the find as a
# physical grab, heads riding the body's hide moves, the insides of a pile and a
# bin, the shed's knot hole. Presentation tuning except where marked host.
## Host: a NICE BOY stands this far out from the face he pokes (m): close enough
## to reach in with both hands (it was 1.2 m, which put him in the picket fence a
## metre off the hedge).
const HIDE_INSPECT_REACH: float = 0.68
## Host: a found hider is set down this far along the face from its middle (m),
## clear of him now that he stands closer (it was 0.4). A shed has its own,
## HIDE_FOUND_LAND_SHED.
const HIDE_FOUND_LAND_SIDE: float = 0.8
## His hands close on the hider's collar this far out in front of their eye (m),
## this far under it (m), this far either side of the middle (m).
const HIDE_GRIP_OUT: float = 0.3
const HIDE_GRIP_DROP: float = 0.13
const HIDE_GRIP_SPREAD: float = 0.15
## Bodies in spots: crouched this far down (m) in a hedge and in a bin, so diving in
## sinks them under the crown or the rim before they stop being drawn, and climbing
## or being hauled out comes up out of it.
const HIDE_HEDGE_CROUCH: float = 0.6
const HIDE_BIN_CROUCH: float = 0.85
## The head rides the torso through the hide moves, easing on and off over this
## long (s).
const HIDE_HEAD_CARRY_EASE: float = 0.12
## Other peers: a diver stops being drawn once this far along the arc (0..1), or
## this long (s) past HIDE_ENTER_SECONDS whatever happens (and a climb-out's low
## start lets go as late).
const HIDE_REMOTE_DIVE_IN: float = 0.97
const HIDE_REMOTE_DIVE_SLACK: float = 0.8
## A pile's mound face is this far ahead of the hider (m); their eye looks out of
## it this high (m), and its shell's opening is this wide and tall (half-angles,
## rad), centred this far under the eye's level (rad): ground level.
const HIDE_PILE_FACE: float = 0.72
const HIDE_PILE_EYE_HEIGHT: float = 0.34
const HIDE_PILE_SHELL_OPENING: Vector2 = Vector2(0.78, 0.24)
const HIDE_PILE_SHELL_OPENING_DIP: float = 0.1
## Shed: the door you're behind stops being drawn this far into the step in (share
## of the eye's move), before it can swing across the view; the knot hole lets you
## turn this far either way (rad) and look this far down and up (rad).
const HIDE_SHED_DOOR_HIDE_AT: float = 0.4
const HIDE_SHED_YAW_CLAMP: float = 0.35
const HIDE_SHED_PITCH_CLAMP: Vector2 = Vector2(-0.22, 0.14)
## Leaving a spot, its inside is swept open off the edges of the view over this
## long (s), spreading this many times its size; it's only gone once the eye is
## this far (m) clear of the spot's box, when the spot's outside comes back.
const HIDE_SHELL_OPEN_SECONDS: float = 0.22
const HIDE_SHELL_OPEN_SPREAD: float = 3.5
const HIDE_SHELL_CLEAR: float = 0.25
## Found: the inside is torn open over this share of HIDE_FOUND_REVEAL.
const HIDE_FOUND_TEAR_SHARE: float = 0.65
## Peeking from a hedge parts the leaves at the mouth by this much (x, y scale).
const HIDE_PEEK_PART: Vector2 = Vector2(0.55, 0.45)
## ...and the whole tangle spreads this much more (share of its size) as you peek.
const HIDE_PEEK_SPREAD: float = 0.45
## Peering in, his face stops this far (m) from the hider's eye (he bends only to
## get there) and his hips drop at most this far (m) to bring his eyes to theirs.
const HIDE_PEER_FACE_GAP: float = 0.74
const HIDE_PEER_SQUAT_MAX: float = 0.45
## A pile: the mound sits this far (m) down into the raked heap under the hider,
## the eye this far (m) under the heap's surface at the mound's face; a NICE BOY
## bent over it (HIDE_PILE_STAND out) has his face end this far (m) above the
## hider's eye (HIDE_PEER_PILE_FACE_UP).
const HIDE_PILE_MOUND_SEAT: float = 0.3
const HIDE_PILE_EYE_UNDER: float = 0.1
## ...looking out where the heap is no taller than the eye, at most this far (m)
## out from the hider: inside the mound everyone else sees over them (R2c hide
## fixes: it walked up to 2 m out, so the NICE BOY bent over bare leaves well off
## the mound and his hands never reached it).
const HIDE_PILE_FACE_MAX: float = 0.85
const HIDE_PEER_PILE_FACE_UP: float = 0.3
## Host: over a pile a NICE BOY stands this far (m) out from the hider's eye, down
## on his haunches with his hands at the mound's face and his grin still in the
## hider's view (R2c hide fixes: it was HIDE_INSPECT_REACH plus a 0.7 m "bend
## reach", and his hands closed on air well short of the leaves; at 0.55 his face
## was over the top of the hider's view); a found hider is set down this far (m) from him, his
## hands still on their shoulders (a spot's is HIDE_PULL_STANDOFF).
const HIDE_PILE_STAND: float = 0.75
const HIDE_PILE_PULL_STANDOFF: float = 0.6
## Into a deep heap, the cannonball carries up to this much farther (m) than its
## usual 0.25 m hop, landing where the heap's face is HIDE_PILE_FACE ahead: the
## hider, the mound, the eye and the NICE BOY's hands all meet at one place.
const HIDE_PILE_DIVE_REACH: float = 1.2
## On the way into a pile the first-person eye stays this far (m) over the heap's
## skin (under it, the lawn under the heap showed as a flat green band), and the
## heap's leaf cards within this far (m) of the lens fold away (a hand-sized maple
## a third of the screen wide); the dive's burst keeps this far (m) off the lens.
const HIDE_PILE_EYE_OVER: float = 0.08
const HIDE_PILE_LENS_CLEAR: float = 0.55
const HIDE_PILE_BURST_CLEAR: float = 0.35
## Sunk into a hedge or a bin, the legs hang straight once the body is this share
## of the way down (other peers see no shoes kicking out of the hedge's foot).
const HIDE_LEGS_HANG_FROM: float = 0.35
## A pile's mound flattens into the heap over this long (s) as its hider bursts out.
const HIDE_PILE_MOUND_FLATTEN: float = 0.2
## Sinking into a pile, its leaves rise round the first-person eye from this far
## below (m) and close over it, over this long (s).
const HIDE_PILE_SHELL_RISE: float = 0.7
const HIDE_PILE_SHELL_RISE_SECONDS: float = 0.3
# ---- R2c annex (inside Satellite Annex B: the people, docs/GAME.md "The people in the room")
## A clerk's stool is a tall drafting stool: seated, his hips drop only this far
## (m) from standing, so head and shoulders clear the hatch from the line (the
## Head NICE BOY's big chair keeps npcs/clerk.gd SIT_DROP).
const CLERK_STOOL_DROP: float = 0.16
## The behind-the-counter corridor clerks walk on (m behind the counter wall's
## line): behind the stools, in front of the filing cabinets, never through a
## seated colleague.
const CLERK_CORRIDOR_BACK: float = 1.45
## A staff member asked to be at his seat or post while somewhere else walks there
## first at this speed (m/s), never posing his state in mid-air.
const CLERK_HOME_SPEED: float = 2.2
## Hurrying back from a break he walks at whatever speed gets him seated by the
## end of RETURN, but never slower than CLERK_WALK_SPEED nor faster than this (m/s).
const CLERK_RUSH_MAX: float = 4.5
## On a break he arrives at his spot this share of the way into it (the rest he
## stands there with his coffee).
const CLERK_BREAK_ARRIVE_SHARE: float = 0.75
## Standing staff keep this far apart (m, body centers); seated ones are left be.
const CLERK_STAFF_GAP: float = 0.62
## Each staff body is solid to players: a capsule this wide and tall (m) on the
## pad-wall layer (people mask it, thrown things don't), so nobody walks into a
## NICE BOY's head.
const CLERK_SOLID_RADIUS: float = 0.45
const CLERK_SOLID_HEIGHT: float = 1.75
## The Copier Jam's walk back from the lobby copier through the staff door (s):
## the longest walk any clerk has (window A, about 23 m at a hurry).
const ANNEX_JAM_RETURN_WALK: float = 8.0
## The Head NICE BOY is back in his chair this long (s) after his desk time
## starts: the host waits for it before he reads a form (he walks back from the
## copier or the cooler first; the desk approval never starts at an empty chair).
## Counted from the later of his desk time's start and the end of his last walk
## off to take the big stamp back (SPOTTED): never on his way back from a holder.
const ANNEX_HEAD_SETTLE: float = 3.0
## At the approval he stands and steps this far (m) to his desk's edge, so both
## hands reach the big stamp on its pad; the pad sits on his side of the desk.
const ANNEX_HEAD_DESK_STEP: float = 0.3
const ANNEX_BIG_PAD := Vector3(0.18, 0.815, 0.22)
## When, in his read (share of ANNEX_HEAD_READ), he lays the form down on the
## pad and reaches for the stamp's knob.
const ANNEX_HEAD_LAY_AT: float = 0.62
## After the slam he holds the stamp down on the form this long (s), then lets go.
const ANNEX_HEAD_SLAM_HOLD: float = 0.35
## He raises it this high over the pad (m), this far back toward himself and this
## far to his right (m):
## over his head, his face clear of it, so the wind-up reads from the visitor spot.
const ANNEX_HEAD_RAISE: float = 1.12
const ANNEX_HEAD_RAISE_BACK: float = 0.2
const ANNEX_HEAD_RAISE_SIDE: float = 0.24
## His arms may stretch to this many times their length to hold it up there.
const ANNEX_HEAD_ARM_STRETCH: float = 1.75
## A self-stamp (the heist) in hand: your arm reaches through the hatch (s), drags
## the stamp across the sill to the lip (s), lifts it over your form (s); the slam
## lifts it this high (m) first; after it the stamp goes back to its pad (s).
const ANNEX_BORROW_REACH: float = 0.25
const ANNEX_BORROW_SLIDE: float = 0.35
const ANNEX_BORROW_LIFT: float = 0.3
const ANNEX_BORROW_SLAM_LIFT: float = 0.05
const ANNEX_BORROW_RETURN: float = 0.45
## How far your first-person arm may stretch (x its length) for a stamp across
## the counter.
const ANNEX_BORROW_STRETCH: float = 2.4
## Someone else's self-stamp, seen from outside: the stamp shoots out of the hatch
## to them in this long (s), and comes down on this point in front of their chest
## (m, in the player's own space, -Z ahead: a little to their left), over their
## left hand held out flat this far under it (m), as if on the form in it; their
## right hand is on its knob while it's out.
const ANNEX_BORROW_QUICK: float = 0.22
const ANNEX_BORROW_CARRY := Vector3(-0.18, 1.0, -0.42)
const ANNEX_BORROW_PALM_DROP: float = 0.04
## A hand on a stamp's knob holds it this high over the knob's center (m).
const ANNEX_KNOB_GRIP: float = 0.03
## The slam's last stamp lets go this long (s) after it lands, then flies home,
## arcing this high (m) over the sill on the way.
const ANNEX_BORROW_LET_GO: float = 0.3
const ANNEX_BORROW_RETURN_ARC: float = 0.08
## Your own stamp comes down on your form here (m, in the form's space): a touch
## right, down and toward you of its middle.
const ANNEX_FORM_SLAM_SPOT := Vector3(0.03, -0.02, -0.04)
## The Copier Jam: the clerk waits this far (m) to the copier's side, not where the
## Head NICE BOY stands at it.
const ANNEX_JAM_SPOT_SIDE: float = 0.7
## The big stamp in your hands: one hand this far (m) to each side of its block,
## gripping this high over its center.
const ANNEX_BIG_GRIP_SPREAD: float = 0.15
const ANNEX_BIG_GRIP_UP: float = 0.05
## Keycaps (the [E] over a thing): a desk bell's sits this far over the bell's
## marker (m), just over its plunger; the big stamp's this much higher (m) than
## R2B_HUD_STAMP_PROMPT_LIFT over its pad, over the stamp's knob.
const ANNEX_BELL_KEYCAP_LIFT: float = 0.06
const ANNEX_BIG_KEYCAP_EXTRA: float = 0.25
## The receipt in your hands (props/receipt_slip.gd): held at its bottom corners,
## this share of its half width out from the middle and this far (m) under its end.
const RECEIPT_GRIP_SPREAD: float = 0.42
const RECEIPT_GRIP_UNDER: float = 0.012
## A staff body's head is solid this wide (m) at head height, wider than the
## capsule (R2c annex review: walking into a NICE BOY, his face still filled the
## view from 0.4 m), so a camera stops this far off a face.
const CLERK_SOLID_HEAD_RADIUS: float = 0.62
const CLERK_SOLID_HEAD_Y: float = 1.5
## The Greeter holds Form 27-B out from at least this far (m) from the rider (body
## centers): out past arm's length, not in their face.
const ANNEX_GREETER_OFFER_GAP: float = 1.15
# ---- R2c hud
# What's on screen, between the beats (docs/GAME.md "What's on screen, between
# the beats"; ui/caption_stack.gd, ui/overheads.gd, ui/interaction_prompt.gd,
# ui/quip_player.gd, ui/near_label.gd). Presentation only.
## Words floating in the world keep a readable size on screen whatever the lens
## (a 40 degree two-shot doubles a fixed-size label) and however close: one line
## of a NICE BOY's bubble stands between these shares of the view's height,
## a name tag between these, and a floating count (the wheelbarrow's, a bag's
## price) at most this.
const R2C_HUD_BUBBLE_LINE_MIN: float = 0.026
const R2C_HUD_BUBBLE_LINE_MAX: float = 0.04
const R2C_HUD_TAG_LINE_MIN: float = 0.017
const R2C_HUD_TAG_LINE_MAX: float = 0.032
const R2C_HUD_COUNT_LINE_MAX: float = 0.03
## A player's name tag and a floating count fade out as you come close: fully
## shown from FULL m, gone at GONE m (up close you know who it is, and the bag in
## the barrow says the count).
const R2C_HUD_TAG_NEAR_FULL_M: float = 2.6
const R2C_HUD_TAG_NEAR_GONE_M: float = 1.6
const R2C_HUD_COUNT_NEAR_FULL_M: float = 2.4
const R2C_HUD_COUNT_NEAR_GONE_M: float = 1.3
## Two bubbles keep this far apart on screen (px); a farther one steps up (or
## down) out of a nearer one's way, gliding there.
const R2C_HUD_BUBBLE_GAP: float = 6.0
## Of two name tags that would sit on each other, the one already up keeps its
## place until the other head is this much nearer (m).
const R2C_HUD_TAG_KEEP_M: float = 0.8
## A tag steps aside once it comes this close (px) to a nearer tag or a bubble,
## so its fade is done before the two would touch.
const R2C_HUD_TAG_CLEAR: float = 24.0
## A tag that stepped aside comes back only after this long (s) in the clear.
const R2C_HUD_TAG_DWELL: float = 0.3
## Prompts and name tags come back this long (s) after the moment lets you go and
## the camera is home, so nothing pops on during a swing back to your eyes: with
## the yard HUD (R2B_HUD_RETURN_DELAY), so everything comes back together.
const R2C_HUD_OVERLAY_DELAY: float = 0.6
## The interact prompt fades in and out over this long (s).
const R2C_HUD_PROMPT_FADE: float = 0.12
## A spoken line older than this (s) when the moment takes you was about the chase,
## not the catch: it goes with the yard's lines.
const R2C_HUD_STALE_SPOKEN: float = 0.25
## While you're hidden the job panel dims to this (0..1) over this long (s): the
## leaves are the picture, the job is still yours.
const R2C_HUD_HIDDEN_PANEL_ALPHA: float = 0.28
const R2C_HUD_HIDDEN_PANEL_FADE: float = 0.3
## A corner quip triggered while the moment has you waits for it to end, up to
## this long (s); older, it's about something long gone and is dropped.
const R2C_HUD_QUIP_WAIT_MAX: float = 20.0
## The corner quip keeps this far (px) above the goal line when they'd share a band,
## gliding there at this rate (1/s).
const R2C_HUD_QUIP_GOAL_GAP: float = 8.0
const R2C_HUD_QUIP_GLIDE: float = 12.0
## A bubble already up goes (fading) once the point over his head leaves the
## picture or he comes closer than this (m): it no longer hangs pinned in a
## corner. Across a camera cut it's gone at once. The view counts as cut when the
## camera changes, or moves more than CUT_MOVE_M or turns more than CUT_TURN
## (rad) in one frame.
const R2C_HUD_BUBBLE_KEEP_M: float = 2.0
const R2C_HUD_CUT_MOVE_M: float = 1.5
const R2C_HUD_CUT_TURN: float = 0.8
## A tag closing on another steps aside this much earlier for each px/s they
## close at (times R2B_HUD_TAG_FADE), up to this many px more.
const R2C_HUD_TAG_CLEAR_MAX: float = 120.0
## The interact prompt isn't drawn within this far (px) of the screen's edge.
const R2C_HUD_PROMPT_EDGE: float = R2B_HUD_SAFE_MARGIN * 2.0
## A corner panel's piece bigger than this share of the screen is a holder, not
## something drawn: the prompt doesn't count it as covered.
const R2C_HUD_PANEL_HOLDER_SHARE: float = 0.25
## A floating label's pixel size is only changed when it moves by more than this
## share of its own (a new pixel size rebuilds its text's mesh).
const R2C_HUD_FIT_STEP: float = 0.02
## Balancing wrapped text: the narrowest width tried is this share of an even
## split, and the width found gets this many px of slack (rounding).
const R2C_HUD_BALANCE_FLOOR: float = 0.8
const R2C_HUD_BALANCE_PAD: float = 2.0
# ---- x1:text (the plain-text sweep, docs/GAME.md "Writing for players")
## The homeowner waves you over (npcs/homeowner.gd) once Chefty has bags in it
## and they haven't been asked yet: the world's "come get paid" in place of a
## goal line. While you're between TALK_REACH and this far away (m) from them,
## the first wave comes soon (NOTICE_SECONDS), the next this many seconds (s) later, and each
## gap after that is BACKOFF times the last, up to MAX_SECONDS (recorded at a
## flat 6 s it was a wave every 7 s through minutes of raking: nagging). A new
## bag landing in Chefty starts the gaps over: they noticed.
const HOMEOWNER_BECKON_SECONDS: float = 6.0
const HOMEOWNER_BECKON_METERS: float = 30.0
const HOMEOWNER_BECKON_BACKOFF: float = 2.0
const HOMEOWNER_BECKON_MAX_SECONDS: float = 48.0
## A bag counts in Chefty's value while it's still flying in (props/truck_bed_load.gd
## thumps it down on landing), so the wave it sets off waits this long (s): the
## babble came half a second before the thump in rec_x1fix_beckon4_1p.
const HOMEOWNER_BECKON_NOTICE_SECONDS: float = 1.2
## A free player hears the radio about a teammate at Annex B (ui/quip_player.gd):
## the first this long (s) after this player starts listening (the visit's start,
## or when they come out of the room or join), then every gap (s) while
## anyone they know is still inside, at most this many per visit. Then one line
## when each teammate's form goes through.
const ANNEX_DISPATCH_FIRST: float = 30.0
const ANNEX_DISPATCH_GAP: float = 40.0
const ANNEX_DISPATCH_MAX: int = 4

# ---- shops: cosmetics (shops chunk 7; docs/GAME.md "Cosmetics", player/hats.gd,
# levels/dressing/wardrobe.gd, net/components/chefty_paint.gd)
## Shirt dyes, in Catalog's shirt_0..shirt_7 order (ui/strings.gd names them):
## red, orange, yellow, green, teal, blue, purple, gray.
const SHIRT_DYES: Array[Color] = [
	Color(0.84, 0.18, 0.16), Color(0.96, 0.52, 0.14), Color(0.97, 0.82, 0.22), Color(0.3, 0.66, 0.3),
	Color(0.16, 0.66, 0.66), Color(0.22, 0.45, 0.85), Color(0.55, 0.32, 0.75), Color(0.55, 0.56, 0.58),
]
## The hi-vis vest's neon (the vest on a body, its folded stack, its icons).
const HIVIS_NEON := Color(0.82, 0.98, 0.16)
## Where Homie Depot shows its workwear, in StoreZone space: the fitting nook
## just south of the orange entrance block, where the store's front wall (its
## face at x WARDROBE_WALL_X) meets the block's south side (z MIRROR_AT.z). The
## hat rack and the shirt cubby hang on the front wall, each centered on its z
## (the cubby's middle divider covers the wall's panel seam at z -10); the
## mirror is on the block's side, facing south down the walk, so you stand in
## front of it with the rack at your elbow. (W8: they were on the block's own
## face, the cubby and the mirror across the glass doors.) The paint counter
## stands by Chefty's loading bay, its customers on its -z side, looking over it
## at the truck. All are in STORE_LAYOUT ("wardrobe", "paint_counter").
const WARDROBE_WALL_X: float = -12.0
const HAT_RACK_Z: float = -8.05
const SHIRT_CUBBY_Z: float = -9.8
const MIRROR_AT := Vector3(-11.0, 0.0, -7.0)
const PAINT_COUNTER_AT := Vector3(10.0, 0.0, 2.75)
## Where you stand to buy (SHOP_SITES.homie_depot.spots): this far (m) out from
## the front wall at the rack and the cubby, and this far on the paint counter's
## -z side.
const WARDROBE_SPOT_OUT: float = 1.0
const PAINT_COUNTER_SPOT_BACK: float = 1.05
## The paint cloud's puffs, in Chefty's body space (m): spread across, how high
## (low, high) and front to back (min, max); each flies out at (min, max) m/s and
## up at (min, max) m/s.
const REPAINT_SPREAD_X: float = 1.3
const REPAINT_SPREAD_Y := Vector2(0.5, 2.4)
const REPAINT_SPREAD_Z := Vector2(-3.0, 2.8)
const REPAINT_PUFF_OUT := Vector2(0.6, 1.6)
const REPAINT_PUFF_UP := Vector2(0.3, 0.9)
## Each puff's full size (m, min and max), and how late (s, at most) it starts.
const REPAINT_PUFF_SIZE := Vector2(0.35, 0.65)
const REPAINT_PUFF_STAGGER: float = 0.12
## The mist is the paint lightened toward white by (min, max), plus up to
## REPAINT_MIST_DARK more for a dark paint (a black job's cloud read as smoke, W8).
const REPAINT_MIST := Vector2(0.1, 0.3)
const REPAINT_MIST_DARK: float = 0.3
## The googly eyes ignore a jump in Chefty's acceleration over this (m/s^2): a
## teleport or a new trip, not a shove.
const GOOGLY_TELEPORT_ACCEL: float = 200.0
## The mirror's glass (m: width, height), how high its bottom edge is, and its
## picture (pixels; the reflection is drawn only while a camera is within
## MIRROR_RANGE m of it and in front). Wearing something new within
## MIRROR_CLOSE_RANGE m of it puts the shop window away, so you see it go on.
const MIRROR_SIZE := Vector2(0.95, 1.75)
const MIRROR_BOTTOM: float = 0.3
const MIRROR_PIXELS := Vector2i(300, 552)
const MIRROR_RANGE: float = 7.0
const MIRROR_CLOSE_RANGE: float = 4.0
## A new hat goes on (player/cartoon_body.gd rebuild): the old one is flicked off
## back over the head over HAT_FLY_SECONDS, rising at most HAT_FLY_RISE (m) and
## landing HAT_FLY_BACK (m) behind as it shrinks away; the new one grows in from HAT_DROP_GROW_FROM
## of its size over HAT_DROP_DELAY, HAT_DROP_HEIGHT (m) above the head and
## HAT_DROP_AHEAD (m) in front of it (clear of the old one's arc: W8 review, two
## hats stacked on a friend's head), drops over HAT_DROP_SECONDS, lands squashed
## to HAT_SQUASH and springs back over HAT_SETTLE_SECONDS. A new shirt puffs the
## torso by SHIRT_PUFF over SHIRT_PUFF_SECONDS. The hands come up for both (the
## dress_up gestures, HAT_ON_SECONDS and SHIRT_TUG_SECONDS long).
const HAT_FLY_SECONDS: float = 0.24
const HAT_FLY_RISE: float = 0.14
const HAT_FLY_BACK: float = 0.6
const HAT_DROP_DELAY: float = 0.14
const HAT_DROP_HEIGHT: float = 0.5
const HAT_DROP_AHEAD: float = 0.12
const HAT_DROP_GROW_FROM: float = 0.35
const HAT_DROP_SECONDS: float = 0.2
const HAT_SQUASH := Vector3(1.16, 0.74, 1.16)
const HAT_SETTLE_SECONDS: float = 0.26
const SHIRT_PUFF: float = 0.12
const SHIRT_PUFF_SECONDS: float = 0.36
const HAT_ON_SECONDS: float = 0.8
const SHIRT_TUG_SECONDS: float = 0.7
## A look that lands within this long of a body being dressed (a late joiner's
## first snapshot) goes straight on, without the show.
const DRESS_ANIMATE_AFTER_SECONDS: float = 2.0
## The propeller beanie's blades (rad/s): idling, plus this much per m/s you run.
const PROPELLER_IDLE_SPIN: float = 1.2
const PROPELLER_SPIN_PER_SPEED: float = 6.5
## Chefty's new paint or decal (chefty_paint.gd): only while it stands still. A
## cloud of REPAINT_PUFFS puffs in the new color bursts round it and clears over
## REPAINT_SECONDS; the look swaps REPAINT_SWAP_AT s in, inside the cloud.
const REPAINT_PUFFS: int = 28
const REPAINT_SECONDS: float = 1.3
const REPAINT_SWAP_AT: float = 0.32
## Buying or applying a paint or decal within this far (m) of Chefty puts the
## shop window away, so you watch it go on (ui/shop_window.gd).
const PAINT_WATCH_RANGE: float = 14.0
## Googly eyes on Chefty's nose: each pupil is a spring (stiffness, damping) the
## truck's acceleration shoves (GOOGLY_SHOVE, m per m/s^2), inside GOOGLY_RANGE m
## of the eye's middle (the pupil's edge stays on the white).
const GOOGLY_STIFFNESS: float = 90.0
const GOOGLY_DAMPING: float = 4.5
const GOOGLY_SHOVE: float = 0.012
const GOOGLY_RANGE: float = 0.1


# ---- driving:E2 (Chefty's chase camera never inside anything, the outskirts,
# full houses up close; docs/GAME.md "Gutterford from the road", docs/DECISIONS.md
# "driving:E2")
## Tree crowns for cameras (props/view_blockers.gd): the grid's cell (m); where a
## kind's leaves start, as a share of its height; how much of the near mesh's
## width the crown ellipsoid takes (the box's corners are air).
const VIEW_BLOCKER_CELL: float = 16.0
const VIEW_CROWN_FROM: Dictionary = {"broadleaf": 0.4, "birch": 0.42, "willow": 0.2, "pine": 0.15, "cypress": 0.1}
const VIEW_CROWN_WIDTH_SHARE: float = 0.85
## Chefty's chase camera (player/vehicle_camera.gd): the boom's pivot over the
## truck (m, above the cab roof, so a boom pulled all the way in is never inside
## the truck); the swept sphere's radius and the clearance kept in front of a
## blocker (m); pulling in: the share of the gap closed per second and a top
## speed (m/s, so a pull-in is never a snap); easing back out (share per second);
## and how far ahead it looks (m) when pulled all the way in.
const CHEFTY_CAMERA_PIVOT_UP: float = 3.0
const CHEFTY_CAMERA_RADIUS: float = 0.35
const CHEFTY_CAMERA_CLEARANCE: float = 0.6
const CHEFTY_CAMERA_PULL_RATE: float = 12.0
const CHEFTY_CAMERA_PULL_SPEED: float = 28.0
const CHEFTY_CAMERA_EASE_OUT: float = 1.6
const CHEFTY_CAMERA_PULLED_LOOK_AHEAD: float = 8.0
## The boom also sweeps where it is swinging to once its way and the wanted
## way differ by more than this (a dot product: about 1.4 degrees).
const CHEFTY_CAMERA_AHEAD_DOT: float = 0.9997
## A solid no wider than this (m: a lamp post, a power pole, a trunk) doesn't pull
## the boom in unless it is within this far (m) of the lens's end of the boom;
## nearer the truck it just passes between, like a post going by the window.
const CHEFTY_CAMERA_THIN_SOLID: float = 1.0
const CHEFTY_CAMERA_THIN_NEAR_LENS: float = 1.5
## A crown the lens is inside anyway fades (screen-door dissolve): grown by this
## pad (m) to start before the lens touches leaves, this much dissolve per unit
## of depth, at most this much, changing at this rate (per second).
const CHEFTY_CAMERA_CROWN_PAD: float = 0.5
const CHEFTY_CAMERA_CROWN_FADE_DEPTH: float = 2.5
const CHEFTY_CAMERA_CROWN_FADE_MAX: float = 0.85
const CHEFTY_CAMERA_CROWN_FADE_RATE: float = 4.0
## The outskirts (levels/town/outskirts.gd): the power poles' spacing (m), the
## trees along the back fences between neighborhoods (m apart), a field's
## furrows (m apart), round bales per hay field, and the PropBatch chunk (m) for
## the outskirts' fences and poles and the town streets' storm drains (bigger
## than art's 32 m: a long fence line in a few draw calls).
const OUTSKIRTS_POLE_SPACING: float = 38.0
const OUTSKIRTS_BACK_ROW_SPACING: float = 24.0
const OUTSKIRTS_FURROW_SPACING: float = 1.6
const OUTSKIRTS_BALES_PER_FIELD: int = 14
const OUTSKIRTS_PROP_CHUNK: float = 128.0
## Main Street's trees, each side of the avenue: this far apart (m).
const OUTSKIRTS_BOULEVARD_SPACING: float = 17.0
const TOWN_STREET_PROP_CHUNK: float = 256.0
## The join frame (levels/build_queue.gd): when this long (ms) has passed since
## the queue's last turn, the frame is already a long one (the job yard arriving
## on a joiner) and the queue sits it out (never two frames running).
const BUILD_SKIP_FRAME_OVER_MS: float = 60.0

# ---- near-lens dissolve (P1 lens: player/cartoon_body.gd _lens_net, docs/GAME.md
# "Nobody's face at the lens")
## Any CartoonBody but your own fades out (the stylized material's screen-door
## dissolve, its own lens_fade channel) as its head or torso comes this close (m,
## from the camera to the part's surface) to whichever camera is drawing: solid
## at LENS_FADE_START_METERS, gone by LENS_FADE_GONE_METERS.
const LENS_FADE_START_METERS: float = 0.6
const LENS_FADE_GONE_METERS: float = 0.2
## The head and torso as the net measures them: a ball this wide (m, the head and
## hair or a hat), its center this high over the face pivot; the chest a capsule
## this wide, from the hips' pivot up this far (m, to the collar).
const LENS_HEAD_RADIUS: float = 0.3
const LENS_HEAD_CENTER_Y: float = 0.04
const LENS_TORSO_RADIUS: float = 0.21
const LENS_TORSO_HEIGHT: float = 0.55
## How fast it fades: out (0 to 1) over this long at the most, back in over this
## long (s). Out is quick so a camera dollying through a head never shows it; in
## is slower, so a friend stepping back from you settles in rather than blinks.
const LENS_FADE_OUT_SECONDS: float = 0.08
const LENS_FADE_IN_SECONDS: float = 0.3
## A camera that moves this far (m) in one frame, or a different camera taking
## over, is a cut: the fade lands at once, since the whole picture changed.
const LENS_CUT_METERS: float = 1.0
## Bodies further than this (m) from the camera, and solid, aren't measured.
const LENS_CHECK_METERS: float = 3.0
## The net also goes by how big the head looks (P1 lens review: riding in
## Chefty's bed, the two riders opposite sat 0.9 m off, each face 40% of the
## picture's height for the whole ride, and stayed solid; a band any wider left
## them a see-through ghost all ride long; at a 60 degree FOV a
## head looks bigger still): the head ball's width as a share of the picture's
## height (or width, if narrower). Solid below LENS_SCREEN_START, gone by
## LENS_SCREEN_GONE (75 degrees: about 1.15 m and 0.98 m from the head's center;
## a friend you stop 1.2 m from stays solid). Only within LENS_SCREEN_METERS
## of the lens, and only on the player's own cameras: a StageCam shot is framed on
## purpose (the van's two heads either side of the road) and keeps the distance
## rule alone.
const LENS_SCREEN_START: float = 0.34
const LENS_SCREEN_GONE: float = 0.4
const LENS_SCREEN_METERS: float = 1.6
## ... and only once it's looked that big this long (s), or from a cut onto it: a
## face you're stuck with goes, one there for a moment (a NICE BOY's lunge
## landing a beat before the shot swings out) doesn't blink see-through.
const LENS_SCREEN_DWELL_SECONDS: float = 0.4
## Arms count too, as a sleeve this wide (m) from the shoulder to the hand (this
## long), but only once they're this close (m from the sleeve): a hand reaching
## toward you doesn't ghost the whole person, a sleeve at the lens does.
const LENS_ARM_RADIUS: float = 0.08
const LENS_ARM_LENGTH: float = 0.52
const LENS_ARM_START_METERS: float = 0.3
## Homeowners (npcs/homeowner.gd): solid to people like the Annex staff (a capsule
## this wide and tall, and a head ball, on the pad-wall layer); they keep this far
## (m) from the nearest player, and when they react to a talk they step round to
## this far in front of the talker's eyes (into view, not off the edge), within
## HOMEOWNER_STAGE_RADIUS of where they wait (m), walking at this speed (m/s, with
## this long to get going). A player this far off (m) lets them drift back home.
const HOMEOWNER_SOLID_RADIUS: float = 0.4
const HOMEOWNER_SOLID_HEIGHT: float = 1.75
const HOMEOWNER_SOLID_HEAD_RADIUS: float = 0.55
const HOMEOWNER_SOLID_HEAD_Y: float = 1.6
const HOMEOWNER_KEEP_METERS: float = 1.8
## Someone closer than this share of HOMEOWNER_KEEP_METERS makes them step back.
const HOMEOWNER_KEEP_TRIGGER: float = 0.88
## While they step round into the talker's view, only someone this close (m).
const HOMEOWNER_KEEP_STAGED_METERS: float = 1.1
const HOMEOWNER_FACE_METERS: float = 1.8
const HOMEOWNER_STAGE_RADIUS: float = 2.4
const HOMEOWNER_WALK_SPEED: float = 1.4
const HOMEOWNER_WALK_EASE_SECONDS: float = 0.35
const HOMEOWNER_HOME_AFTER_METERS: float = 4.0
## Steps shorter than this (m) aren't worth taking (no shuffling on the spot).
const HOMEOWNER_STEP_MIN_METERS: float = 0.25
## The host sends where they're walking to at most this often (s) while someone
## keeps crowding them (the latest destination always goes out).
const HOMEOWNER_WALK_SHARE_SECONDS: float = 0.2
## The take-the-cash pill sits under the offered handful, so the cash itself
## stays in sight: this far down (m) for every meter between the camera and the
## cash (about the pill's own height on screen; up close it stays in the picture).
const HOMEOWNER_PROMPT_DROP: float = 0.09
## The cash's price while they hold it out: over their head (m), this small
## (Label3D font size and meters per pixel), so the offered handful still reads.
const HOMEOWNER_PRICE_Y: float = 2.04
const HOMEOWNER_PRICE_FONT: int = 40
const HOMEOWNER_PRICE_PIXEL: float = 0.0035

# ---- p1-arrive: stepping off a seat, and room to stand (docs/GAME.md "Stepping
# off Chefty"; net/components/step_down.gd, player.gd step_down_to, personal_space.gd)
## The legacy Chefty's bed places (net/components/ride.gd), in the truck's space
## (the cab is at -Z), by seat: on opposite rails, facing out over the side, so
## two riders stand back to back (lagduo-7: side by side, the friend's head
## filled half your view the whole ride). 0 left, 1 right, 2 left by the
## tailgate, 3 right by the cab.
const CHEFTY_RIDE_SEATS: Array[Vector3] = [
	Vector3(-0.62, 1.0, 0.35), Vector3(0.62, 1.0, 0.35),
	Vector3(-0.62, 1.0, 1.75), Vector3(0.62, 1.0, -0.75),
]
## Each seat's facing (yaw about +Y, in the truck's space): +90 deg looks out the
## left side, -90 deg out the right.
const CHEFTY_RIDE_SEAT_YAWS: Array[float] = [1.5708, -1.5708, 1.5708, -1.5708]
## Where each legacy seat's rider lands when Chefty arrives (truck space, the
## ground): bed left, bed right, the tailgate, by the cab on the right. Each is
## straight out over its own wall: a hop to the shotgun door (z -2.0) went over
## the cab's back corner (review, p1-arrive).
const CHEFTY_STEP_DOWN_SLOTS: Array[Vector3] = [
	Vector3(-1.85, 0.0, 0.35), Vector3(1.85, 0.0, 0.35),
	Vector3(0.0, 0.0, 3.6), Vector3(1.85, 0.0, -0.9),
]
## A rider whose own spot is blocked (a lamp post, a hedge, a parked car) or
## taken takes the first of these that's clear, in order.
const CHEFTY_STEP_DOWN_SPARE: Array[Vector3] = [
	Vector3(-1.85, 0.0, -0.9), Vector3(-1.85, 0.0, 1.9), Vector3(1.85, 0.0, 1.9),
	Vector3(-1.1, 0.0, 3.7), Vector3(1.1, 0.0, 3.7), Vector3(0.0, 0.0, 4.9),
]
## A client whose truck is still short of the curb when the host says it arrived
## (its clock trails the host's) drives the rest first (ride.gd _step_catchup):
## more than this many meters left, at about this average speed (m/s), taking
## between these many seconds.
const CHEFTY_RIDE_CATCHUP_MIN_METERS: float = 0.05
const CHEFTY_RIDE_CATCHUP_SPEED: float = 35.0
const CHEFTY_RIDE_CATCHUP_SECONDS := Vector2(0.2, 1.2)
## Two landing spots closer than this (m) count as one.
const STEP_DOWN_SPACING: float = 1.1
## The space a landing spot needs (radius, height in m), checked against the
## world's solids only (props move, so peers could disagree about them).
const STEP_DOWN_CAPSULE := Vector2(0.4, 1.6)
## You never land facing a solid closer than this (m; nb3, the lamp post at arm's
## length): the facing turns by these steps (radians) until it's clear.
const STEP_DOWN_FACE_CLEAR: float = 1.6
const STEP_DOWN_FACE_TURNS: Array[float] = [0.45, -0.45, 0.9, -0.9, 1.35, -1.35, 1.8, -1.8]
## The middle of the view that has to be clear: this far either side (radians).
const STEP_DOWN_FACE_CONE: float = 0.45
## A drawn prop with no collider (a lamp post, a hydrant, a mailbox: world.gd
## arrival_obstacles) is never closer than this (m, to its edge) to where you
## land (play: the host landed with a pole at 0.6 m and a hydrant at his foot);
## one lower than this (m) over the ground (a doormat, chalk) doesn't count.
const STEP_DOWN_POST_ROOM: float = 1.0
const STEP_DOWN_PROP_MIN_HEIGHT: float = 0.3
## How far round the truck (m) those props are gathered.
const STEP_DOWN_PROP_REACH: float = 10.0
## You land facing at most this far (radians) off straight away from the truck,
## turned toward what you'd look at (the house, the store's doors).
const STEP_DOWN_FACE_FROM_TRUCK: float = 0.9
## At Homie Depot you land looking at the store's doors (StoreZone space).
const ARRIVE_LOOK_STORE := Vector3(-10.0, 0.0, -2.0)
## The hop off a seat (player.gd step_down_to): how long it takes (s); the knees
## bend for the first share (anticipation), the body flies, and the last share
## is the landing (contact, knees taking it, then standing).
const STEP_DOWN_SECONDS: float = 0.85
const STEP_DOWN_CROUCH_SHARE: float = 0.16
const STEP_DOWN_LAND_SHARE: float = 0.22
## How far the knees take the body down first (m), and the hop: its curve bends
## through a point twice this (m) over the higher of the seat and the ground.
const STEP_DOWN_CROUCH: float = 0.08
const STEP_DOWN_HOP: float = 0.3
## The turn to the landing's facing is done this early in the hop (1 = at the end).
const STEP_DOWN_TURN_DONE: float = 0.75
## Riders get off one after another: each seat this much (s) after the one before.
const STEP_DOWN_STAGGER: float = 0.15
## Further than this (m) isn't a step down, it's a teleport (the legacy crossing).
const STEP_DOWN_MAX_METERS: float = 7.0
## The falling speed the hop reports (m/s, replicated) is held under the hard
## landing's thump (LAND_THUMP_SPEED): stepping off a truck is a soft landing.
const STEP_DOWN_MAX_FALL: float = 4.5
## A landing from the air between this and LAND_THUMP_SPEED (m/s) is a soft one:
## the ground's footstep, a little louder (dB over FOLEY_STEP_DB).
const FOLEY_SOFT_LAND_SPEED: float = 2.0
const FOLEY_SOFT_LAND_DB: float = 3.0
## Bailing out of a moving Chefty: you leave from your seat (no hop to the door
## first, which was a 1.9 m pop) and get this much sideways speed (m/s) away from it.
const CHEFTY_BAIL_SIDE: float = 3.5
## Room to stand (net/components/personal_space.gd, host): two players on foot
## closer than this (m) for longer than this (s) are eased apart at this speed
## (m/s), checked this often (s); each nudge lasts this long on the owner (s).
const PERSONAL_SPACE_RADIUS: float = 0.45
const PERSONAL_SPACE_AFTER: float = 0.3
const PERSONAL_SPACE_SPEED: float = 1.6
const PERSONAL_SPACE_TICK: float = 0.1
const PERSONAL_SPACE_NUDGE_SECONDS: float = 0.15
## Two players further apart than this up or down (m) aren't in each other's
## space (one on a roof, one under it).
const PERSONAL_SPACE_HEIGHT: float = 1.2
## The push is full at or inside this share of PERSONAL_SPACE_RADIUS and falls to
## PERSONAL_SPACE_MIN_PUSH of PERSONAL_SPACE_SPEED at its edge.
const PERSONAL_SPACE_FULL_PUSH_AT: float = 0.5
const PERSONAL_SPACE_MIN_PUSH: float = 0.5
## The ground under a landing spot is looked for this far up and down (m).
const STEP_DOWN_GROUND_REACH: float = 1.5
## A landing spot's capsule starts this far over the ground (m), so a curb's lip
## doesn't count as a wall.
const STEP_DOWN_CAPSULE_LIFT: float = 0.12
## The landing's view check (step_down.gd view_clear): from this high (m, the
## eyes), again this much lower (a hedge's top), and along the ground every this
## many meters, where a drawn prop over the knees (this high, m) within this
## much (m) of the line counts as in the way.
const STEP_DOWN_VIEW_EYE: float = 1.5
const STEP_DOWN_VIEW_LOW: float = 0.8
const STEP_DOWN_VIEW_STEP: float = 0.3
const STEP_DOWN_VIEW_KNEE: float = 0.5
const STEP_DOWN_VIEW_HIT: float = 0.12
## With nothing to look at, you land looking this far (m) along the truck's nose.
const STEP_DOWN_LOOK_AHEAD: float = 10.0
## The hop's height comes from how far down it goes, held between these (m).
const STEP_DOWN_DROP_RANGE := Vector2(0.25, 1.0)
## Of the landing's share, the knees stay bent for this much, then you stand.
const STEP_DOWN_LAND_CROUCH: float = 0.6
## Over the bed's rails or tailgate (step_down.gd hop_path): the feet clear their
## top by this much (m), from this far (m) before the wall to this far past it
## (the shins aren't a point), checked at this many places along the way.
const STEP_DOWN_WALL_CLEAR: float = 0.12
const STEP_DOWN_LEG_REACH: float = 0.05
const STEP_DOWN_WALL_SAMPLES: int = 6
## That jump rises and falls under this gravity (m/s^2, a little snappier than
## the world's), and rises at least this much (m) over the higher end.
const STEP_DOWN_GRAVITY: float = 14.0
const STEP_DOWN_MIN_RISE: float = 0.15
## Out of a cab seat you slide out through the door still sitting until you're
## this far (m) past the cab's side (your own width), then drop off the sill.
const STEP_DOWN_DOOR_CLEAR: float = 0.4
## Another peer's view of a rider leaving a seat (net_smoother.gd): drawn on the
## seat while that rider's own peer still has them on one (their truck can trail
## this one by a second), but never longer than this (s); then it blends from
## where it was drawn into the replicated stream over this long (s), so a hop
## already under way on the rider's peer is caught up, never jumped.
const SMOOTHER_SEAT_HOLD_MAX: float = 3.0
const SMOOTHER_RESUME_BLEND: float = 0.3

# ---- p1-van (the Courtesy Shuttle with a crew aboard; docs/GAME.md "The Courtesy Shuttle, crewed")
## The cab shot's dolly takes over from wherever you were looking in the seat over
## this long (s), the lens closing in to the cab shot's FOV with it; the dolly
## starts at your seat's eye and only leans out into the aisle in this time, so the
## blend can't cut the corner back past the next rider's head.
const VAN_DOLLY_BLEND_IN: float = 0.6
## Which seat a rider gets (props/nice_van.gd RIDER_SEAT_Z, front to back): each
## one walks along the curb to their own seat's spot and steps straight in, so a
## seat with a rider either side costs this much (m of walk), and one past the
## NICE BOY who brought you (he stands beside you at the door) this much more, so
## nobody is walked through him (playtest r1).
const VAN_SEAT_CROWD_COST: float = 3.0
const VAN_SEAT_ESCORT_COST: float = 5.0
## ... he counts as beside you within this (m).
const VAN_SEAT_ESCORT_NEAR: float = 1.6
## A walk to your seat's spot longer than this (m) is walked facing the way you
## go; shorter, you shuffle along the door still facing the van.
const VAN_SHUFFLE_FACE_METERS: float = 1.0
## A step up from further than this (m) from its seat's spot isn't a shuffle
## along the door (an escort hands you over at the door step): it goes straight.
const VAN_STEP_SHUFFLE_MAX: float = 2.6
## With nobody to walk past, the seats fill in this order: by the door first, then
## the far ends, so two riders sit 1.4 m apart.
const VAN_SEAT_ORDER: Array[int] = [2, 0, 3, 1]
## Where you step down you face away from the van. A spot along the curb with no
## lamp post, trunk, mailbox or person within this (m) inside this half-angle
## (degrees) of that is taken first; failing one, you're turned the least of these
## (degrees, either way) that clears it (playtest nb3: back in control facing a
## pole at arm's length; a pole 1.8 m ahead still split the view, so 2 m).
const VAN_EXIT_FACE_CLEAR: float = 2.0
const VAN_EXIT_FACE_CONE: float = 45.0
const VAN_EXIT_FACE_TURNS: Array[float] = [0.0, 30.0, -30.0, 55.0, -55.0, 80.0, -80.0]
## ... and nobody (a teammate, a NICE BOY, a rider already given the next spot)
## stands within this (m) of where you land: under the seats' spacing, so riders
## sat side by side still step straight down side by side.
const VAN_EXIT_PERSON_CLEAR: float = 0.65
## A watcher's van driving away keeps carrying on down its road while it was in
## view this recently (s): a frame where a trunk hides it no longer drops it back
## onto the host's plan 20 m behind (playtest nb6).
const VAN_GHOST_GRACE: float = 0.75
## ... and the host's plan landing more than this (m) behind the van this peer is
## drawing driving away is never taken while it's in view: it drives on.
const VAN_GHOST_BEHIND: float = 0.5
## A watcher's van that would be drawn more than this (m) behind where it was last
## frame waits there for its plan instead (a van never backs up).
const VAN_BACKSTEP_TOLERANCE: float = 0.02
## The crew's way in and out of the side door (van space z): shotgun's at the
## front of the opening, the back bench's just ahead of the stacked door panels,
## and through the aisle at this x, on its door side, clear of the riders' bench;
## the back bench's aisle point this far (m) on toward it from its way in.
const VAN_CREW_DOOR_Z := Vector2(-1.55, 1.2)
const VAN_CREW_AISLE_X: float = 0.75
const VAN_CREW_AISLE_ALONG: float = 0.8
## Someone out for a walk counts as standing everywhere their route has them
## from the moment you unbuckle until this long (s) after your feet touch the
## sidewalk, sampled this often (s): the step-down keeps clear of where a passer-by
## is about to be, not where they were when the door opened (p1-van review: one
## strolled into a landing rider's face from 0.5 m).
const VAN_EXIT_PASSER_AFTER: float = 1.5
const VAN_EXIT_PASSER_STEP: float = 0.25
## A passer-by doesn't walk within this (m) of the sidewalk outside a NICE van's
## side door while it stands at the curb, is this close (s) to stopping there, or
## has the door open: they stop at the edge and watch, then catch up on their
## walk once it's gone (npcs/pedestrian.gd, Shuttle.keep_clear). Past the door's
## opening, so the one waiting is off to the side of every step-down's view.
const VAN_PASSER_KEEP: float = 3.0
const VAN_PASSER_LEAD: float = 3.0

# ---- p1-depart (how a crew leaves together and how a job ends; docs/GAME.md
# "Leaving together", levels/world.gd _tick_boarding, net/components/ride.gd)
## Chefty's honk-and-wait: the first boarder sits, Chefty honks, and the truck
## goes this long after (s), or sooner once the whole crew there is aboard. The
## same window after the homeowner's cash, before the ride home.
const CHEFTY_BOARD_WAIT_SECONDS: float = 6.0
## Everyone aboard: the beat (s) before it pulls away, so the last one in lands
## in the bed and hears the engine before the road moves.
const CHEFTY_BOARD_ALL_ABOARD_SECONDS: float = 1.0
## The last-call honk, this long (s) before the window runs out.
const CHEFTY_BOARD_LAST_CALL_SECONDS: float = 1.6
## Walking up to Chefty in the window seats you: within this far (m, flat) of
## the bed's middle (the store's Board pad counts too). Crew bots wait at
## net/dev/bot.gd CREW_WAIT_SLOTS, the farthest 3.3 m out.
const CHEFTY_BOARD_WALKUP_METERS: float = 3.6
## A seated boarder holds E this long (s) to leave right now.
const CHEFTY_BOARD_HOLD_SECONDS: float = 0.6
## Climbing into the bed (or hopping out over the tailgate): how long (s) and how
## high the hop arcs (m). From farther than CHEFTY_BOARD_CLIMB_FROM_MAX (m) (a
## straggler gathered off the yard) there is no climb: they're just aboard.
const CHEFTY_BOARD_CLIMB_SECONDS: float = 0.45
const CHEFTY_BOARD_CLIMB_HOP: float = 0.55
## Climbs from farther than this (m) take longer in proportion (the Board pad's
## edge is about 5 m from a seat).
const CHEFTY_BOARD_CLIMB_REACH: float = 2.6
const CHEFTY_BOARD_CLIMB_FROM_MAX: float = 9.0
## Where a boarder hopping out lands, behind the tailgate (m along the bed's +Z
## from the truck's origin).
const CHEFTY_BOARD_STEP_DOWN_Z: float = 3.6
## The homeowner settles up only for a job this done (the share of the leaves
## and every task asked for, the measure _judge uses, 0..1): she waves the crew
## over only past it, and below it the first talk gets a look at the yard and
## no cash; ask again and she'll call it a day anyway (npcs/homeowner.gd).
const HOMEOWNER_SETTLE_DONE: float = 0.25
## "Some days people are just in a mood" (homeowner.verdict): a roll under this
## lifts the mood a step, over this drops it a step. A mess stays a mess, and
## only a job that's clean enough can be lifted to thrilled.
const HOMEOWNER_MOOD_SWING_UP_BELOW: float = 0.12
const HOMEOWNER_MOOD_SWING_DOWN_ABOVE: float = 0.9
## The crew's split (core/economy.gd split_shares): this share of the pool goes
## to the whole crew evenly, the rest by contribution (Balance weights and
## MINIMUM_CONTRIBUTION_SHARE), so nobody who came along reads $0.
const CREW_SPLIT_EVEN_SHARE: float = 0.5

# ---- P1 catch (fix wave P1: the second catch, the haul-up, the Annex desk and walk-in,
# the pile dive seen by others; docs/GAME.md "P1: the catch, again")
## A stage message's time (encounter.gd _rebased) trusted on a client within this
## much (s) of when it should land on the client's own clock; further off (a clock
## estimate gone stale in a starved window, a hitch) the moment starts on arrival.
const STAGE_CLOCK_TRUST: float = 0.35
## The haul-up (a NICE BOY on someone knocked flat): no lunge. He walks over beside
## them at this pace (m/s; the walk takes at least the first and at most the second
## many s), then squats and reaches down over this long (s): the hand lands on their
## collar at its end.
const CATCH_DOWN_WALK: float = 4.0
const CATCH_DOWN_WALK_SECONDS: Vector2 = Vector2(0.3, 1.0)
const CATCH_DOWN_BEND: float = 0.35
## Where he bends over them: this far (m) to the side of their collar, on his own
## side of them, never over the head that tipped back behind them.
const CATCH_DOWN_SIDE: float = 0.5
## Someone flat on their back (player/cartoon_body.gd FALL_ANGLE): their hips and
## their collar lie this far (m) back from their feet along the ground. They come up
## where their hips lay; he reaches for the collar.
const CATCH_DOWN_HIPS_BACK: float = 0.8
const CATCH_DOWN_COLLAR_BACK: float = 1.25
## After the heave he stands this far (m) from them, a short step back from his reach.
const CATCH_DOWN_GAP: float = 0.9
## The two-shot comes up as a cut, not a swing, when the camera would have to turn
## more than this (degrees) to reach it: a swing that far crosses empty lawn first.
const CATCH_CAM_CUT_TURN: float = 125.0
## The haul-up's two-shot starts from the ground: its look point this much lower
## (m) and its eye this much lower while you lie there, rising to the usual
## two-shot over this long (s) after the hit-stop as he heaves you up.
const CATCH_DOWN_LOOK_DROP: float = 0.8
const CATCH_DOWN_EYE_DROP: float = 0.1
const CATCH_DOWN_RISE: float = 0.6
## ...facing the way they lay until this share of the rise, then turned to face him.
const CATCH_DOWN_TURN_FROM: float = 0.55
## The low shot is also this much further off (a share of CATCH_CAM_DISTANCE) while you
## lie there, so your own head on the grass doesn't fill it.
const CATCH_DOWN_PULL_BACK: float = 0.35
## Boarding with nothing staged (your own eyes): the view holds still where it is
## while the iris shuts at once, then cuts to the seat behind it.
const BOARD_HOLD_PRIORITY: int = 45
## ...taken over this short a blend (s) from exactly where it is: no cut, no move.
const BOARD_HOLD_BLEND: float = 0.05
## Annex B (audit r2): after he slams APPROVED the Head NICE BOY sits back in his
## chair, pleased with himself, this long (s) before any walk off; the walk starts
## from his chair then, never part way along.
const ANNEX_HEAD_PLEASED: float = 2.4
## Annex B's walk-in (audit r3): a rider is let inside (the clipboard) only once
## their body is this near the threshold (m, flat), or this long (s) after the walk
## should have ended, whatever happened to it.
const ANNEX_INSIDE_REACH: float = 2.2
const ANNEX_WALK_LATE_MAX: float = 6.0
## Annex B (audit nb10): a keycap this near (px) the clipboard in your hand on screen
## is behind it, and waits until it isn't.
const ANNEX_FORM_PROMPT_PAD: float = 18.0
## The pile dive seen by others (audit nb7): a cannonball announced by its owner is
## played this long (s) past the dive's own length waiting on the host's word that
## they're in; no word by then, the body stands back up out of the leaves.
const HIDE_REMOTE_PILE_WAIT: float = 0.9
## ...it lands (the whump, the burst, the mound starting to grow) as the body drawn
## on that screen comes within this share of its way to the owner's landing, or this
## long (s) after it should have landed, wherever it is; the landing is this share
## of the cannonball's HIDE_ENTER_SECONDS.
const HIDE_REMOTE_PILE_NEAR: float = 0.15
const HIDE_REMOTE_PILE_LAND_LATE: float = 0.6
const HIDE_PILE_LANDING: float = 0.6
## The haul-up's rise (player/cartoon_body.gd haul_up): the thighs come up this far
## and the knees bend this far (rad) at its middle, as the feet swing in under the
## hips; a knock replicated from before it is ignored for up to this long (s).
const BODY_HAUL_THIGH: float = 0.9
const BODY_HAUL_SHIN: float = -1.4
const BODY_HAUL_KNOCK_STALE: float = 2.0

# ---- p1-hands (crew playtest 1: what your hands do; docs/GAME.md "What E does",
# player/player.gd e_choice, the sleep pose, the bag, the fence, the wheelbarrow)
## E acts on a thing you're looking at when your line of sight passes this
## close to it (m, square to the look; a prop's middle, the junk's tailgate).
const E_LOOK_MISS: float = 0.42
## A teammate is grabbed only from this close (m, flat; the host accepts up to
## GRAB_PLAYER_REACH) and only while the look passes this close to their body (m).
const E_GRAB_REACH: float = 1.3
const E_GRAB_LOOK_MISS: float = 0.3
## Where on a teammate's body (m over their feet: knees, chest, head) the look
## may pass to count as looking at them.
const E_GRAB_LOOK_HEIGHTS: Array[float] = [0.5, 1.0, 1.5]
## How much farther than its reach (m) a thing may be from your eye and still
## be looked at (the eye is up at head height, the reach is measured flat):
## a teammate or a pick-up, and the junk at Chefty's tailgate.
const E_LOOK_REACH_SLACK: float = 1.6
const E_LOOK_JUNK_SLACK: float = 1.0
## A pick-up's foot (m over its origin), the lowest point a look may catch it.
const E_LOOK_PROP_FOOT: float = 0.1
## Lying on a cot (player.gd _step_sleep, cartoon_body.gd sleep pose): the
## body's feet go this far (m) along the cot from its middle toward its foot,
## the climb on takes this long (s), the body tips back this far (radians) and
## rides this high (m) over the canvas so its back lies on it, not in it. The
## head may turn this far (radians) either way from the cot's line, and a
## sleeper is drawn lying down once within this far (m) of the cot.
const SLEEP_FOOT_OFFSET: float = 0.8
const SLEEP_CLIMB_SECONDS: float = 0.55
const SLEEP_LIE_ANGLE: float = 1.52
const SLEEP_LIE_LIFT: float = 0.13
const SLEEP_YAW_CLAMP: float = 0.7
const SLEEP_ON_COT_NEAR: float = 0.45
## The climb on hops this high (m) at its middle; getting up steps off the cot's
## foot this far (m) past the heels; lying there, the eyes turn this share of
## the mouse's pitch.
const SLEEP_CLIMB_HOP: float = 0.18
const SLEEP_GET_UP_SIDE: float = 0.75
const SLEEP_LOOK_SHARE: float = 0.6
## Getting up (the step off the cot, and the body sitting up) takes this share
## of the climb on: up is quicker than down.
const SLEEP_GET_UP_SHARE: float = 0.8
const SLEEP_SIT_UP_SHARE: float = 0.7
## Lying there, the eyes' pitch stays between these (radians: just off the
## canvas toward your feet .. back over the pillow).
const SLEEP_HEAD_PITCH_MIN: float = 0.2
const SLEEP_HEAD_PITCH_MAX: float = 2.6
## The sleep pose (cartoon_body.gd): arms folded on the belly (shoulder pitch
## and the inward swing, radians), legs together with the feet this far apart
## (radians), the toes pointed up (radians), and the eyes shut to this share
## once the body is past this far down.
const SLEEP_ARM_PITCH: float = -0.62
const SLEEP_ARM_IN: float = -0.32
const SLEEP_LEG_SPLAY: float = 0.05
const SLEEP_TOE_PITCH: float = -0.5
const SLEEP_EYES_SHUT: float = 0.06
const SLEEP_EYES_SHUT_FROM: float = 0.6
## Sleeping breath: this many breaths a second, the chest rising this share.
const SLEEP_BREATHE_RATE: float = 0.28
const SLEEP_BREATHE_DEPTH: float = 0.05
## A fresh bag (world.gd _spawn_bag_for) sits at least this far (m, flat) in
## front of whoever bagged it, so it lands in view, not under the hotbar, and
## grows from the pile to full size over this long (s), from this share of it.
const BAG_SPAWN_AHEAD_MIN: float = 1.35
const BAG_GROW_SECONDS: float = 0.32
const BAG_GROW_FROM: float = 0.3
## With no bagger named (tests), the nearest player within this far (m, flat)
## of the pile stands in; a pile's middle is this high (m) over the ground; the
## bag sets down this far (m) over the ground; and a bagger standing within this
## far (m) of the pile's middle pushes it out the way they face.
const BAG_SPAWN_NEAREST_REACH: float = 4.05
const BAG_SPAWN_PILE_HEIGHT: float = 0.2
const BAG_SPAWN_GROUND_LIFT: float = 0.02
const BAG_SPAWN_ON_TOP: float = 0.2
## The grow overshoots full size by this share at its middle, as it fills.
const BAG_GROW_OVERSHOOT: float = 0.08
## Leaves stop at the yard's fence (leaf_field.gd): a stroke's berm never lands
## past a fence line; what doesn't fit banks up on the yard side.
## The wheelbarrow rights itself (net_prop.gd): tipped more than this (radians)
## and at rest, it rolls back upright at this rate (1/s).
const WHEELBARROW_STEADY_TILT: float = 0.04
const WHEELBARROW_RIGHTING_RATE: float = 5.0
## Your own dizzy stars in first person (cartoon_body.gd dizzy): this much of
## their size, this much closer round and this much lower over the eye (m),
## so they ring the top of the view instead of filling it.
const STARS_OWN_SCALE: float = 0.4
const STARS_OWN_RISE: float = 0.5

# ---- p1-ui (windows and world labels, docs/GAME.md "Windows sit in the middle of
# the screen" and "Words hung in the world"). Presentation only.
## A window (ui/window_fit.gd) keeps at least this far (px) inside every screen
## edge; bigger than that, it's drawn smaller.
const UI_WINDOW_MARGIN_PX: float = 24.0
## A world sign (Chefty's name and load, a gate pad's words; ui/overheads.gd
## SIGNS) is never taller than this share of the view's height per line.
const P1_SIGN_LINE_MAX: float = 0.034
## A sign behind someone (a player, a keeper, a NICE BOY, a homeowner) steps aside
## when the line to it passes this close (m) to their body, from knee to crown:
## "To the lot" printed on Marty's face.
const P1_SIGN_BODY_RADIUS_M: float = 0.45
const P1_SIGN_BODY_SPAN_M := Vector2(0.5, 1.9)
## A tag or sign fades out once its words come within this many px of a screen
## edge (it never shows cut off), or of a HUD panel (it never prints over one).
const P1_LABEL_EDGE_PX: float = 12.0
const P1_LABEL_HUD_GAP_PX: float = 8.0
## ... or where it's heading (its screen speed times the fade) for this many
## frames running (one jerk of the view mustn't blink it).
const P1_LABEL_AHEAD_FRAMES: int = 2
## ... and over the last this many px before that margin it is already fading, by
## where it is, so one creeping up on a panel or an edge is gone as it arrives
## (it went 1.0 to gone in one frame over the heat bar).
const P1_LABEL_FADE_PX: float = 24.0
## At a shop counter (npcs/store_clerk.gd frame_for): your view eases round onto
## the keeper's face over this long (s) when his window opens, looking at most
## this far (rad) up or down from level.
const P1_COUNTER_FRAME_SECONDS: float = 0.45
const P1_COUNTER_PITCH_MAX: float = 0.12

# ---- p1-dash: Chefty's instruments, its rear window and the seat prompts
# (props/chefty_dash.gd, net/components/chefty_drive.gd; docs/GAME.md "Chefty's dash")
## Chefty's ground speed (how fast it really goes over the road: the drawn body's
## travel each tick, smoothed at this rate per second) is what the needle shows
## and what the seat swap, getting in and bailing out go by. A tick that moved it
## faster than CHEFTY_GROUND_TELEPORT_MPS (m/s) was a teleport (placed, towed
## home), not driving: it counts for neither the speed nor the miles.
const CHEFTY_GROUND_SPEED_RATE: float = 10.0
const CHEFTY_GROUND_TELEPORT_MPS: float = 70.0
## The speedometer: m/s to MPH, the top of the dial (MPH), the needle's spring
## (stiffness per s^2, damping per s: a little overshoot, then it settles) and
## where its top stop pin is (share of the dial).
const CHEFTY_DASH_MPH_PER_MPS: float = 2.23694
const CHEFTY_DASH_MAX_MPH: float = 50.0
const CHEFTY_DASH_NEEDLE_STIFFNESS: float = 110.0
const CHEFTY_DASH_NEEDLE_DAMPING: float = 15.0
const CHEFTY_DASH_NEEDLE_PEG: float = 1.04
## The lamps light this long (s) when someone takes the wheel (the bulb check);
## the check-engine lamp blinks this fast (Hz) at CHEFTY_MAX_DENTS.
const CHEFTY_DASH_BULB_CHECK_SECONDS: float = 1.3
const CHEFTY_DASH_CEL_BLINK_HZ: float = 1.6
## The dash's parts are drawn only within this far (m) of the camera.
const CHEFTY_DASH_VISIBLE_M: float = 9.0
## The odometer: Chefty came to the crew with this many miles on it; the crew's
## own meters are in the save's "vehicle" section (odometer_m). The host tells
## everyone its count every CHEFTY_ODOMETER_SYNC_M (m) driven; a peer that has
## drifted further than CHEFTY_ODOMETER_RESYNC_M from it takes the host's.
const CHEFTY_ODOMETER_START_MILES: float = 186427.0
const CHEFTY_METERS_PER_MILE: float = 1609.344
const CHEFTY_ODOMETER_SYNC_M: float = 16.0
const CHEFTY_ODOMETER_RESYNC_M: float = 40.0
## Seated in Chefty, a key's prompt shows over a seat (or the hired hand) you're
## looking at with your own eyes: within this angle (radians) of the view's
## center, within reach (m). A seat's prompt sits this high over its marker:
## x in the cab (sitting), y in the bed (standing).
const CHEFTY_SEAT_PROMPT_CONE: float = 0.3
const CHEFTY_SEAT_PROMPT_REACH: float = 4.0
const CHEFTY_SEAT_PROMPT_UP := Vector2(1.25, 1.75)

# ---- p1-world: day and night (levels/day_sky.gd, docs/GAME.md "Day and night")
## The light at each hour of the clock (7 to 26; 26 is 2 AM), eased between keys:
## the sky's top and horizon colors (the haze takes the horizon's), the light's
## color and strength, its pitch and yaw (degrees, rotation_degrees: the sun is
## up when pitch is below 0, and sets toward yaw -75), the sky light's strength,
## how much of it comes from the sky (the rest is DAY_SKY_NIGHT_AMBIENT), and how
## far night has come (the stars, the windows) and the lamps (on at dusk). The
## 16:30 key is levels/shared_look.gd's own late afternoon, the light the art was
## made in (art_test checks they match). The clouds, which take no light of their
## own, are tinted by clouds. From 19.4 to 19.6 the light is dark
## while it swaps from the setting sun to the moon.
const DAY_SKY_KEYS: Array = [
	{"hour": 7.0, "top": Color(0.42, 0.58, 0.8), "horizon": Color(0.98, 0.8, 0.66), "light": Color(1.0, 0.8, 0.62), "energy": 0.85, "pitch": -9.0, "yaw": 112.0, "ambient": 0.6, "sky_share": 1.0, "night": 0.0, "lamps": 0.15, "clouds": Color(1.0, 0.88, 0.82)},
	{"hour": 8.5, "top": Color(0.36, 0.57, 0.85), "horizon": Color(0.9, 0.85, 0.76), "light": Color(1.0, 0.9, 0.78), "energy": 1.2, "pitch": -24.0, "yaw": 85.0, "ambient": 0.72, "sky_share": 1.0, "night": 0.0, "lamps": 0.0, "clouds": Color(1.0, 1.0, 1.0)},
	{"hour": 12.5, "top": Color(0.3, 0.54, 0.87), "horizon": Color(0.84, 0.86, 0.84), "light": Color(1.0, 0.96, 0.9), "energy": 1.45, "pitch": -52.0, "yaw": 20.0, "ambient": 0.8, "sky_share": 1.0, "night": 0.0, "lamps": 0.0, "clouds": Color(1.0, 1.0, 1.0)},
	{"hour": 16.5, "top": Color(0.33, 0.55, 0.82), "horizon": Color(0.96, 0.82, 0.64), "light": Color(1.0, 0.87, 0.7), "energy": 1.35, "pitch": -32.0, "yaw": -38.0, "ambient": 0.75, "sky_share": 1.0, "night": 0.0, "lamps": 0.0, "clouds": Color(1.0, 1.0, 1.0)},
	{"hour": 18.0, "top": Color(0.34, 0.46, 0.72), "horizon": Color(1.0, 0.68, 0.44), "light": Color(1.0, 0.68, 0.42), "energy": 1.1, "pitch": -14.0, "yaw": -60.0, "ambient": 0.66, "sky_share": 1.0, "night": 0.0, "lamps": 0.0, "clouds": Color(1.0, 0.9, 0.8)},
	{"hour": 18.8, "top": Color(0.26, 0.28, 0.52), "horizon": Color(0.98, 0.48, 0.34), "light": Color(1.0, 0.46, 0.26), "energy": 0.5, "pitch": -4.0, "yaw": -72.0, "ambient": 0.52, "sky_share": 0.85, "night": 0.1, "lamps": 0.35, "clouds": Color(1.0, 0.66, 0.55)},
	{"hour": 19.4, "top": Color(0.1, 0.12, 0.3), "horizon": Color(0.42, 0.3, 0.42), "light": Color(0.7, 0.45, 0.45), "energy": 0.0, "pitch": -2.0, "yaw": -78.0, "ambient": 0.48, "sky_share": 0.6, "night": 0.6, "lamps": 0.9, "clouds": Color(0.45, 0.38, 0.5)},
	{"hour": 19.6, "top": Color(0.07, 0.09, 0.24), "horizon": Color(0.3, 0.25, 0.4), "light": Color(0.6, 0.7, 1.0), "energy": 0.0, "pitch": -42.0, "yaw": 150.0, "ambient": 0.52, "sky_share": 0.5, "night": 0.75, "lamps": 1.0, "clouds": Color(0.3, 0.3, 0.42)},
	{"hour": 20.3, "top": Color(0.02, 0.035, 0.1), "horizon": Color(0.1, 0.13, 0.24), "light": Color(0.62, 0.72, 1.0), "energy": 0.32, "pitch": -42.0, "yaw": 150.0, "ambient": 0.56, "sky_share": 0.35, "night": 1.0, "lamps": 1.0, "clouds": Color(0.16, 0.19, 0.3)},
	{"hour": 26.0, "top": Color(0.015, 0.025, 0.08), "horizon": Color(0.08, 0.1, 0.2), "light": Color(0.6, 0.7, 1.0), "energy": 0.3, "pitch": -50.0, "yaw": 175.0, "ambient": 0.54, "sky_share": 0.35, "night": 1.0, "lamps": 1.0, "clouds": Color(0.13, 0.16, 0.26)},
]
## The hour whose key is shared_look's look (a world with no clock shows it).
const DAY_SKY_ART_HOUR: float = 16.5
## The look moves on each time the clock has gone this far (hours; 0.01 is under
## a real second), so the sky's light isn't reworked every frame.
const DAY_SKY_STEP_HOURS: float = 0.01
## The night's sky light where it doesn't come from the dark sky: moonlit blue.
const DAY_SKY_NIGHT_AMBIENT := Color(0.34, 0.4, 0.56)
## How often (s) the lamps, windows and headlights are looked for again.
const DAY_SKY_SCAN_SECONDS: float = 2.0
## The street lamps nearest the camera that cast real light: how many, their
## color, reach (m) and strength, how long one takes to fade in or out (s), how
## often (s) they're moved to the nearest lamps, how far from the camera (m) a
## lamp can have one (it fades out over the last 40%), and where under the lens.
const DAY_SKY_LAMP_LIGHTS: int = 8
const DAY_SKY_LAMP_COLOR := Color(1.0, 0.82, 0.55)
const DAY_SKY_LAMP_RANGE: float = 13.0
const DAY_SKY_LAMP_ENERGY: float = 2.2
const DAY_SKY_LAMP_FADE_SECONDS: float = 0.6
const DAY_SKY_POOL_SECONDS: float = 0.25
const DAY_SKY_POOL_REACH: float = 55.0
const DAY_SKY_LAMP_DROP := Vector3(0.0, -0.5, 0.0)
## The lamp lenses' glow by day and at night, times what each was built with.
const DAY_SKY_LAMP_DAY: float = 0.15
const DAY_SKY_LAMP_NIGHT: float = 2.5
## The houses' windows at night: their glow's color and strength.
const DAY_SKY_WINDOW_COLOR := Color(1.0, 0.76, 0.42)
const DAY_SKY_WINDOW_ENERGY: float = 0.9
## Chefty's (and Lunch Money's) headlight beams at night: strength, reach (m),
## half-angle (degrees), and how far they tip down (degrees).
const DAY_SKY_HEADLIGHT_ENERGY: float = 3.0
const DAY_SKY_HEADLIGHT_RANGE: float = 28.0
const DAY_SKY_HEADLIGHT_ANGLE: float = 34.0
const DAY_SKY_HEADLIGHT_TILT: float = 7.0
## The stars: the map's size (equirectangular), how many, and their seed.
const DAY_SKY_STAR_MAP := Vector2i(2048, 1024)
const DAY_SKY_STARS: int = 1500
const DAY_SKY_STAR_SEED: int = 2718

# ---- p1-world: the town line (levels/town/town_line.gd, docs/GAME.md "The edge of town")
## Gutterford's hedgerow runs round this rect (x, z), inside TownMap.TOWN_BOUNDS
## and outside every road, yard, house and the lake (townmap_test checks).
const TOWN_LINE_RECT := Rect2(-135.0, -510.0, 1020.0, 1020.0)
## The hedge's solid wall: how high and how deep (m), its inside face this far
## inside the line (m). The split-rail fence stands a hand inside that face, so
## whatever reaches the hedge stops just short of the rails, never through them.
## The wall breaks at each farm gate, which is solid itself.
const TOWN_LINE_WALL_HEIGHT: float = 4.0
const TOWN_LINE_WALL_DEPTH: float = 3.4
const TOWN_LINE_WALL_INSIDE: float = 1.9
## The hedge's lumps this far apart (m), drawn in stretches this long (m, one
## mesh each), with a field tree standing out of this share of the lumps, and
## drawn out to this far (m; the haze has it long before).
const TOWN_LINE_HEDGE_STEP: float = 3.0
const TOWN_LINE_SEGMENT: float = 64.0
const TOWN_LINE_TREE_SHARE: float = 0.22
const TOWN_LINE_VISIBLE_METERS: float = 420.0
## The hills past the hedge: between these distances out (m), about this far apart.
const TOWN_LINE_HILLS_OUT := Vector2(70.0, 150.0)
const TOWN_LINE_HILL_SPACING: float = 55.0
## A closed road: the barricade stands this far past the asphalt's end (m), the
## gravel track is this wide (m) and runs this far past the gate (m), and the
## gate in the hedge is twice this wide (m).
const TOWN_LINE_BARRICADE_OUT: float = 2.5
const TOWN_LINE_TRACK_WIDTH: float = 4.2
const TOWN_LINE_TRACK_PAST: float = 45.0
const TOWN_LINE_GATE_HALF: float = 2.6
## Depot Road's asphalt runs this far each way from the store (store_dressing.gd
## draws it past TownMap.DEPOT_Z), so its barricades stand past that.
const TOWN_LINE_DEPOT_ASPHALT_END: float = 160.0

# ---- p2-kit: crew equipment is physical (docs/GAME.md "The crew's kit";
# net/kit/kit.gd, net/components/tool_bed.gd). Taylan, 2026-11-03: "You gotta buy
# the equipment and load it up on the Chefty. Everyone spawns in with $50."
## Every new player's cash: a new campaign, or a player joining a save for the
## first time (Campaign._bind_peer). tools/balance_sim.py starts its wallets here too.
const STARTING_CASH: int = 50
## The kinds of prop that are crew kit: bought, owned by the crew, saved, and
## carried to jobs in Chefty's bed or in pockets (the rake first, then the tools).
const KIT_KINDS: Array[String] = [
	"rake", "leaf_blower", "lawn_mower", "ladder", "hose", "hedge_trimmer", "pressure_washer", "paint_roller",
	# shops:9: the seasonal sacks are kit too (a sack's fill is its `fuel`).
	"fertilizer_bag", "grass_seed", "rock_salt",
]
## A rake's raking strength by its tier (0 used, 1 stock, 2 Mk II, 3 Mk III):
## Rusty's used rake is a little bent; Mk II and Mk III are the old Tune-Up and
## The Leafinator's Balance.TOOL_THROUGHPUT_GROWTH_MULTIPLIER, once and twice
## (net/kit/kit.gd rake_multiplier). The head index RakeMotion draws, by tier.
const KIT_USED_RAKE_SCALE: float = 0.85
const KIT_RAKE_HEAD_BY_TIER: Array[int] = [0, 0, 1, 2]
## Where kit waits by Homie Depot's front door (bought big tools roll out here;
## anything left at a yard leans here the next morning), in StoreZone space:
## the first spot and the step along the wall to the next (each lies along x),
## and how many spots there are (more go on the last one). Inside STORE_LAYOUT's
## "kit_door", beside the entrance.
const KIT_DOOR_FIRST := Vector3(-6.2, 0.35, 0.1)
const KIT_DOOR_STEP := Vector3(0.0, 0.0, 0.5)
const KIT_DOOR_MAX: int = 12
## Chefty's tool rack over the cab (truck space; the cab is at -Z): long tools lie
## along the truck on two crossbars, on their sides, one per rack spot across x,
## at this height (their lowest point); the ladder rides on top of them all.
const KIT_RACK_SLOTS_X: Array[float] = [-0.84, -0.6, -0.36, -0.12, 0.12, 0.36, 0.6, 0.84]
const KIT_RACK_Y: float = 2.64
const KIT_RACK_Z: float = -1.95
## (fx-chefty: the front bar moved back from -2.6 to stand on the drivable
## Chefty's shorter open-cab roof, props/vehicles.gd CHEFTY_ROOF_FRONT_Z.)
const KIT_RACK_BARS_Z: Array[float] = [-1.3, -2.38]
const KIT_LADDER_ON_RACK := Vector3(0.0, 3.0, -1.6)
## The bed's floor spots for the big pushed tools (mower, washer), truck space,
## with their yaw: up the ramp by the tailgate, clear of the rail riders.
const KIT_BED_FLOOR_SLOTS: Array[Vector3] = [Vector3(0.32, 1.05, 2.0), Vector3(-0.2, 1.05, 1.05)]
const KIT_BED_FLOOR_YAW: float = PI
## Loading a tool into the bed glides it from where it was to its spot over this
## long (s), rising this much over the arc's middle (m).
const KIT_LOAD_GLIDE_SECONDS: float = 0.45
const KIT_LOAD_GLIDE_LIFT: float = 0.6
## Taking one out: the tool you look at in the bed (within this reach of your eye,
## and this close to your line of sight, m) comes into your hands after it's
## been a prop for this long (s), so every peer sees it lift off its spot.
const KIT_TAKE_REACH: float = 4.2
const KIT_TAKE_LOOK_MISS: float = 0.5
const KIT_TAKE_HANDOFF_SECONDS: float = 0.12
## A tool lying still in the bed this slow (m/s) is put on the rack.
const KIT_BED_REST_SPEED: float = 0.6
## How near Chefty you hold a tool for "[E] Load" (m from the bed's middle).
const KIT_LOAD_REACH: float = 3.0
## Dev and tests: a session that starts on the yard (--start-zone=lot) finds this
## many rakes lying where the yard's own rake used to (lot space), the first there
## and the rest beside it; --starter-kit=N puts N rakes in Chefty's bed instead.
const KIT_DEV_RAKE_AT := Vector3(-2.5, 0.2, 12.0)
const KIT_DEV_RAKE_STEP := Vector3(0.0, 0.0, -1.0)
## The legacy store's pad, grown by this much (m), still counts as at the store
## (kit left there isn't swept to the door in the morning).
const KIT_STORE_SLACK: float = 2.0
## How full a bought gas tool's tank comes (%): Rusty's used ones half full,
## Marty fills a new one.
const KIT_USED_FUEL: float = 50.0
const KIT_NEW_FUEL: float = 100.0
## The host takes a "[E] Take" from this much farther (m) than the prompt's
## reach (KIT_TAKE_REACH, measured from the eye), for lag and feet-vs-eye.
const KIT_TAKE_HOST_SLACK: float = 1.5
## A bought pocket tool with no pocket free lands this far ahead of the buyer (m)
## and this high over their feet (m), so it drops in front of them.
const KIT_DROP_AHEAD: float = 0.7
const KIT_DROP_LIFT: float = 0.4
## Past KIT_DOOR_MAX, more kit by the door stacks on the last spot this much higher each (m).
const KIT_DOOR_STACK_STEP: float = 0.3


# ---- driving:F (the NICE BOYS in town: the pursuit, the pull-over, the ram and the
# getaway; net/run_events/pursuit.gd, the Courtesy Shuttle's CHASE leg in
# net/run_events/shuttle.gd; docs/GAME.md "The pursuit")
## In the connected town a player off the yard can still be caught this close (m)
## to the job site, or to where the van pulled Chefty over.
const CREW_LEASH_METERS: float = 35.0
## Chefty going this fast (m/s), this far from the site (CREW_LEASH_METERS), with
## someone catchable aboard during the chase: the crew piles back in and the van gives chase.
const PURSUIT_START_SPEED: float = 6.0
## The van's sim (VehicleSim, the same arcade model as Chefty): top speed (m/s;
## Chefty's is 19, and every dent costs it 3%), how hard it pulls and brakes
## (m/s^2), its steering rate (rad/s at full lock), and its four hubs (x, z; the
## van faces -Z like every vehicle).
const NICE_VAN_TOP_SPEED: float = 17.0
const NICE_VAN_ACCEL: float = 5.5
const NICE_VAN_BRAKE: float = 11.0
const NICE_VAN_STEER_RATE: float = 1.7
const NICE_VAN_WHEELS: Array[Vector2] = [Vector2(-1.02, -2.1), Vector2(1.02, -2.1), Vector2(-1.02, 2.1), Vector2(1.02, 2.1)]
## The van's chassis box (what the sim moves into walls) and its middle (van space).
const NICE_VAN_CHASSIS_SIZE := Vector3(2.2, 1.5, 6.2)
const NICE_VAN_CHASSIS_CENTER := Vector3(0.0, 1.15, 0.0)
## It aims this far ahead of Chefty along Chefty's velocity (s), drives straight at
## it inside this range (m) with a clear line, and otherwise takes the roads
## (TownMap.route), planned again every PURSUIT_REPLAN_SECONDS.
const PURSUIT_LEAD_SECONDS: float = 0.5
const PURSUIT_DIRECT_METERS: float = 50.0
const PURSUIT_REPLAN_SECONDS: float = 0.5
## Chefty more than this far round from the van's nose (rad) while the van is slower
## than PURSUIT_UTURN_SPEED (m/s): it swings a U-turn on full lock at this
## throttle; stuck at it for PURSUIT_UTURN_STUCK (s), the autopilot backs it up.
const PURSUIT_UTURN_ANGLE: float = 1.75
const PURSUIT_UTURN_SPEED: float = 6.0
const PURSUIT_UTURN_THROTTLE: float = 0.85
const PURSUIT_UTURN_STUCK: float = 1.0
## Chefty stopped (or slower than PULLOVER_SPEED): the van pulls in this far
## behind it (m), and a crawl this slow (m/s) still counts as stopped.
const PULLOVER_BEHIND: float = 7.5
const PULLOVER_SPEED: float = 3.0
## The pull-over: Chefty under PULLOVER_SPEED with the van within PULLOVER_RADIUS
## (m, middle to middle) for PULLOVER_SECONDS (s): the van stops and they climb out.
const PULLOVER_RADIUS: float = 9.0
const PULLOVER_SECONDS: float = 2.0
## Someone sitting in Chefty is pulled out when a NICE BOY gets this close (m,
## on the ground, to their seat).
const SEAT_GRAB_RADIUS: float = 2.5
## Pulled over: Chefty driving off this fast (m/s) and this far from the van (m)
## sends the crew back in and the chase on.
const PULLOVER_DRIVE_OFF_METERS: float = 13.0
## Pulled over, a NICE BOY walks up to the truck on the side whoever he's after gets
## out on, this far (m) from its middle and this far behind their seat (so they hop
## down in front of him), and has them out once he's within PULLOVER_STAND_REACH of
## that spot; he catches them PULLOUT_CATCH_SLACK after their hop down (s).
const PULLOVER_STAND_SIDE: float = 2.2
const PULLOVER_STAND_BACK: float = 1.3
const PULLOVER_STAND_REACH: float = 0.8
const PULLOUT_CATCH_SLACK: float = 0.15
## ...or, kept off that spot (the van, a post), once he's been within SEAT_GRAB_RADIUS
## of the seat this long (s).
const PULLOVER_REACH_WAIT: float = 1.2
## The head NICE BOY yells out of the van's window at most this often (s) in a chase.
const PURSUIT_BARK_SECONDS: float = 6.0
## Pulled over with nobody left to catch near it for this long (s): they wrap it up.
const PULLOVER_IDLE_SECONDS: float = 4.0
## The crew has this long (s) to pile back into the van; still out after that, the
## chase is off.
const PURSUIT_BOARD_MAX: float = 9.0
## The getaway: stay this far from the van (m) for this long (s), or outlast this
## much chasing (s, pull-overs not counted), or reach Homie Depot's lot
## (STORE_AREA: no niceness on premises).
const PURSUIT_LOSE_DISTANCE: float = 150.0
const PURSUIT_LOSE_SECONDS: float = 6.0
const PURSUIT_MAX_SECONDS: float = 60.0
## Lost them: the heat settles here, not at the raid's 15 ("they know your truck
## now"), and the crew gets XP_ESCAPE once.
const HEAT_AFTER_ESCAPE: float = 40.0
## Ramming the van: Chefty closing on it faster than this (m/s) spins it out for
## VAN_STUN_SECONDS and adds HEAT_VAN_RAM (assault on a vehicle of niceness). The
## spin starts at VAN_SPIN_RATE (rad/s) and winds down over VAN_SPIN_SECONDS; the
## van is shoved along Chefty's way at this share of the closing speed.
const VAN_RAM_SPEED: float = 9.0
const VAN_STUN_SECONDS: float = 3.0
const HEAT_VAN_RAM: float = 15.0
const VAN_SPIN_RATE: float = 9.0
const VAN_SPIN_SECONDS: float = 1.5
const VAN_RAM_PUSH_SHARE: float = 0.55
## A crash of Chefty's counts as a ram when it hit within this much (m) of the van's box.
const VAN_RAM_SLACK: float = 1.2
## The van's pose during a chase reaches clients as samples (PURSUIT_SNAP_HZ),
## drawn at least PURSUIT_VIEW_DELAY behind the host (more when the link is
## slower: the arrival lag plus PURSUIT_VIEW_MARGIN, up to PURSUIT_VIEW_DELAY_MAX),
## carried on along its last velocity for at most PURSUIT_VIEW_EXTRAPOLATE (s).
## The host keeps PURSUIT_TRACK_SECONDS of them.
const PURSUIT_SNAP_HZ: int = 30
const PURSUIT_VIEW_DELAY: float = 0.1
const PURSUIT_VIEW_MARGIN: float = 0.05
const PURSUIT_VIEW_DELAY_MAX: float = 0.4
const PURSUIT_VIEW_EXTRAPOLATE: float = 0.15
const PURSUIT_TRACK_SECONDS: float = 4.0
## The kazoo siren on the van while it chases (sound_bank kazoo_siren): how loud
## (dB), how far it carries (m) and its unit size; the pursuit engine
## (nice_van_loop) pitched from idle to flat out by speed share.
const VAN_SIREN_DB: float = -2.0
const VAN_SIREN_UNIT_SIZE: float = 18.0
const VAN_SIREN_MAX_DISTANCE: float = 220.0
const VAN_PURSUIT_ENGINE_DB := Vector2(-10.0, 0.0)
const VAN_PURSUIT_ENGINE_PITCH := Vector2(0.75, 1.5)
## The amber dome pulses this fast (Hz) and this much brighter while it chases (the
## lights in Chefty's mirror; cast guardrail: one dome, never a bar).
const VAN_DOME_CHASE_HZ: float = 3.2
const VAN_DOME_CHASE_ENERGY: float = 2.2
const VAN_DOME_CHASE_RANGE: float = 14.0
## Off the yard's navmesh (farther than this from the yard's middle, m), a NICE BOY
## walks straight at where he's going.
const CREW_NAV_REACH: float = 32.0
## Back to a van parked out in the town, a NICE BOY comes at its door from this far (m)
## out beside it, never along its flank (already this share of it out beside the
## door, he walks straight in).
const CREW_DOOR_APPROACH_OUT: float = 1.6
const CREW_DOOR_APPROACH_SHARE: float = 0.7
## The head NICE BOY's first bark out of the window comes this long (s) after the
## van pulls away.
const PURSUIT_FIRST_BARK_DELAY: float = 1.0
## A U-turn counts as stuck only after this long at it (s), and is over once Chefty
## is within this share of PURSUIT_UTURN_ANGLE of the van's nose.
const PURSUIT_UTURN_SETTLE: float = 0.6
const PURSUIT_UTURN_DONE_SHARE: float = 0.5
## The van's clear-line check (straight at Chefty or by the roads) is a ray at this
## height (m, about a windshield).
const PURSUIT_SIGHT_HEIGHT: float = 1.4
## Rammed: the van keeps this share of its own speed before the shove, and its body
## bucks this hard (NiceVan Motion.bump) if the hit reached this peer within
## VAN_RAM_BUMP_WINDOW (s).
const VAN_RAM_KEEP_SPEED_SHARE: float = 0.3
const VAN_RAM_BUMP: float = 2.0
const VAN_RAM_BUMP_WINDOW: float = 0.5
## Where the kazoo siren sits on the van (van space, m: on the roof by the dome).
const VAN_SIREN_AT := Vector3(0.0, 3.3, 0.3)

# ---- audio:7 vehicles and the board (audio/vehicle_sound.gd, audio/board_sound.gd;
# docs/DECISIONS.md "Audio: the engine and the board are components")

## Each vehicle's engine: the idle loop's volume (dB) and its pitch from a
## standstill to where the rev loop has taken over, the rev loop's volume and
## pitch from a crawl to top speed, how many gears the rev climbs through, and
## its reach (full volume inside unit_size m, gone past max_distance m).
const ENGINE_PROFILES: Dictionary = {
	"chefty": {"idle_db": -13.0, "idle_pitch": Vector2(1.0, 1.3), "rev_db": Vector2(-14.0, -6.0), "rev_pitch": Vector2(0.8, 1.6), "gears": 3, "unit_size": 8.0, "max_distance": 70.0},
	"van": {"idle_db": -7.0, "idle_pitch": Vector2(0.8, 1.05), "rev_db": Vector2(-9.0, 0.0), "rev_pitch": Vector2(0.65, 1.25), "gears": 2, "unit_size": 16.0, "max_distance": 120.0},
}
## The share of top speed by which the rev loop has fully taken over from the
## idle, and how far a floored pedal pushes that crossfade on its own (revving
## at the lights), plus its extra pitch.
const ENGINE_REV_FULL_SHARE: float = 0.35
const ENGINE_THROTTLE_SHARE: float = 0.15
const ENGINE_THROTTLE_PITCH: float = 0.08
## Inside one gear the rev sweeps this share of its pitch range (the rest follows
## speed), so it drops a step at each shift: vrrRM, vrrRRM, vrrRRRM.
const ENGINE_GEAR_SPAN: float = 0.5
## How fast the loops' volume and pitch follow (per second), and how fast the
## speed read off a moving body settles; a body that moved faster than this
## (m/s) was put somewhere, not driven.
const ENGINE_SMOOTH: float = 8.0
const ENGINE_SPEED_SMOOTH: float = 10.0
const ENGINE_TELEPORT_SPEED: float = 300.0
## Switching off: the idle sags to this share of its pitch while it fades, over this long (s).
const ENGINE_STOP_SECONDS: float = 0.7
const ENGINE_STOP_PITCH: float = 0.55
## No second engine_start within this long of the last (s); the loops come in
## this long after the crank starts, where it coughs and catches.
const ENGINE_START_GAP_SECONDS: float = 2.0
const ENGINE_START_CATCH_SECONDS: float = 0.62
## Aboard (sitting in it), the engine is at full volume within this many meters
## and not muffled by distance: it's your truck, wherever the camera hangs.
const ENGINE_ABOARD_UNIT_SIZE: float = 20.0
## Where the engine sits on a truck's body (its hood; -Z is forward).
const ENGINE_SOUND_AT := Vector3(0.0, 1.0, -2.2)
## Chefty's legacy ride (net/components/ride.gd): the engine starts this long
## after the honk that calls the crew in (the honk has the stage first), keeps
## idling this long after it parks, and reads its speed against this top (m/s;
## the 8 s ride peaks near 190). It screeches from this far through the trip
## (smoothstep: the last stretch is the hard braking), and arrive() screeches
## unless a skid played within ENGINE_ARRIVE_SKID_GAP seconds.
const ENGINE_START_AFTER_HONK: float = 1.1
const ENGINE_IDLE_LINGER_SECONDS: float = 4.0
const ENGINE_RIDE_TOP_SPEED: float = 160.0
const ENGINE_RIDE_SKID_FROM: float = 0.92
const ENGINE_ARRIVE_SKID_GAP: float = 1.0

## The board (audio/board_sound.gd): the roll is heard from this speed (m/s);
## the roll and grind fade in and out this fast (per second: quick enough that
## leaving the ground cuts the roll on the frame, slow enough not to click), and
## are stopped under BOARD_SILENT_DB. A landing's volume from a hop to a big air
## (dB), and how long in the air (s) counts as big.
const BOARD_ROLL_MIN_SPEED: float = 0.3
const BOARD_LOOP_FADE: float = 30.0
const BOARD_SILENT_DB: float = -60.0
const BOARD_LAND_DB := Vector2(-7.0, 0.0)
const BOARD_LAND_FULL_AIR: float = 0.6

# ---- shops chunk 8: deliveries and pay a crewmate (net/shops/shops.gd,
# levels/dressing/delivery_pallet.gd, player/cash_toss.gd, ui/phone.gd)
## How often the host looks for orders that are due (s; a poll, not tuning).
const DELIVERY_CHECK_SECONDS: float = 1.0
## The delivery van backs up to the store's loading dock, out of sight behind the
## lobby wall the pallet's cage stands against: where its honk comes from (from
## the back room's pallet, StoreZone space) and how loud.
const DELIVERY_HONK_FROM := Vector3(-5.0, 1.2, 0.0)
const DELIVERY_HONK_DB: float = 0.0
## The pass-through hatch in that wall, behind the cage: its middle (from the
## pallet; the wall's cinder-block face is at about x -1.4), its width along the wall and height (m).
## Its shutter rolls up this long after the honk (s), taking this long (s).
const DELIVERY_HATCH := Vector3(-1.37, 0.95, 0.0)
const DELIVERY_HATCH_SIZE := Vector2(0.9, 0.8)
const DELIVERY_SHUTTER_DELAY: float = 0.45
const DELIVERY_SHUTTER_SECONDS: float = 0.35
## Then someone inside shoves the order out through it: the first thing goes this
## long after the honk (s), the rest this far apart; a crate is in the air this
## long (s); a tool is through the hatch well within this long (s; the shutter
## waits for it).
const DELIVERY_TOSS_DELAY: float = 1.1
const DELIVERY_TOSS_GAP: float = 0.45
const DELIVERY_TOSS_SECONDS: float = 0.55
const DELIVERY_TOOL_FLIGHT: float = 1.1
## A tool turns about up this fast as it flies (radians/s).
const DELIVERY_TOOL_SPIN: float = 0.5
## An ordered tool waits this far behind the hatch (m, inside the building, out of
## sight) from the moment it lands until it's thrown; it's shoved out lengthwise
## along a line tipped up this much (radians) through the hatch's middle, from
## this far behind the wall's face (m) until its tail is this far out of it, then
## lobbed on. It's let go this high over its spot (m), dropping at this speed (m/s).
const DELIVERY_TOOL_HIDE_BACK: float = 2.7
const DELIVERY_TOOL_PITCH: float = 0.7
const DELIVERY_TOOL_HIDE_MARGIN: float = 0.08
const DELIVERY_TOOL_LAND_LIFT: float = 0.04
const DELIVERY_TOOL_LAND_SPEED: float = 0.6
## Its thud waits this long on a client (s): NetSmoother draws props about this
## far behind the host, so the sound lands with the rake you see.
const DELIVERY_TOOL_THUD_CLIENT_DELAY: float = 0.1
## Orders land on the quarter hour (minutes), like the HUD clock reads.
const DELIVERY_ROUND_MINUTES: float = 15.0
## A crate starts this far back inside the hatch (hidden in the dark), along the
## way out (m).
const DELIVERY_CRATE_START_BACK: float = 0.3
## The shutter comes back down this long after the last thing lands (s).
const DELIVERY_SHUTTER_HOLD: float = 0.5
## The crates on the pallet (supplies; tools come as themselves): two a layer,
## this far either side of the middle, layers this tall from the pallet's top,
## and at most this many shown (a busy day's extra crates are "in the back").
const DELIVERY_CRATE_SIDE: float = 0.31
const DELIVERY_CRATE_LAYER: float = 0.5
const DELIVERY_PALLET_TOP: float = 0.13
const DELIVERY_CRATES_MAX: int = 6
## How many crates one supply order puts on the pallet: one a unit, at most this many.
const DELIVERY_CRATES_PER_ORDER: int = 2
## A crate landing: how flat it squashes (y scale at contact), how long it takes
## to spring back (s), how far it may turn off square (radians), and its thud.
const DELIVERY_CRATE_SQUASH: float = 0.8
const DELIVERY_CRATE_SETTLE: float = 0.24
const DELIVERY_CRATE_YAW: float = 0.12
const DELIVERY_THUD_DB: float = -2.0
## Ordered tools land in front of the cage (its open side): the first spot (from
## the pallet), the step to the next, how many spots before they stack, and how
## much higher each stacked one goes (m).
const DELIVERY_KIT_FIRST := Vector3(2.1, 0.45, -0.6)
const DELIVERY_KIT_STEP := Vector3(0.0, 0.0, 0.5)
const DELIVERY_KIT_MAX: int = 5
const DELIVERY_KIT_STACK_STEP: float = 0.3
## Pay a crewmate: the payer holds the bill out (the "offer" gesture) for this
## long before it leaves the hand (s), it flies this long (s) on an arc this high
## over the straight line (m), and only between crewmates this close (m); farther
## apart it just lands in their wallet. The payee's "+$20 · Sam" line under the
## wallet stays this long (s), fading over the last FADE.
const PAY_TOSS_LEAD: float = 0.3
const PAY_TOSS_SECONDS: float = 0.6
const PAY_TOSS_ARC: float = 0.55
const PAY_TOSS_MAX_METERS: float = 14.0
const PAY_NOTICE_SECONDS: float = 4.0
const PAY_NOTICE_FADE: float = 1.0
## The paper bill: its size (m; a cartoon bill, half again a real one, so it reads
## across a lot) and how many flutter turns it makes in the air.
const PAY_BILL_SIZE := Vector2(0.24, 0.11)
const PAY_BILL_SPINS: float = 1.5
## The bill's arc peaks early (the lift is sin(PI * t^SKEW); under 1 moves the
## top forward), so it drops into the hands rather than arriving at head height.
const PAY_TOSS_ARC_SKEW: float = 0.6
## Through the payee's eyes, their hand is all the way out by this share of the
## flight; once caught, the bill folds into it over this long (s) as it drops.
const PAY_CATCH_REACH_SHARE: float = 0.6
const PAY_CATCH_HOLD: float = 0.22
## Where that first-person hand catches it, in head space (m: right, up, ahead):
## low and a little right in the view, at arm's length.
const PAY_FP_CATCH_AT := Vector3(0.12, -0.24, -0.55)

# ---- fx-chefty: getting in and out of Chefty, its pillars, stragglers, the rack (docs/GAME.md "Getting in and out of Chefty")
## Climbing into the drivable Chefty (net/components/seat_moves.gd): the steps to
## the door or the rail go at this pace (m/s); shorter than this (m) and there's
## no step at all. From farther than CHEFTY_CLIMB_FROM_MAX (m) you're just aboard.
const CHEFTY_CLIMB_WALK_SPEED: float = 3.2
const CHEFTY_CLIMB_WALK_MIN: float = 0.2
const CHEFTY_CLIMB_FROM_MAX: float = 6.0
## Into the bed you hop from this far outside the rails' outer edge (m): any
## closer and the arc over the rail has to start nearly straight up (the hop off a
## seat's physics, played backward), a leap higher than the cab.
const CHEFTY_CLIMB_RAIL_GAP: float = 0.8
## A hired hand going round between the bed and the cab stands this far out from
## Chefty's middle (m), beside their seat, as they climb out or in over the rail.
const CHEFTY_CLIMB_RAIL_OUT: float = 1.75
## Seat to seat inside the truck: a slide along the bench takes this long (s) for
## this far (m), longer or shorter in proportion; across the bed it's a hop this high (m).
const CHEFTY_SEAT_SLIDE_SECONDS: float = 0.5
const CHEFTY_SEAT_SLIDE_SPAN: float = 0.9
const CHEFTY_SEAT_SHUFFLE_HOP: float = 0.18
## A hand seen working the yard this recently (s) climbs in from where they were.
const CHEFTY_HAND_SEEN_SECONDS: float = 1.5
## The view between the chase camera and your own eyes when you get into the
## driver's seat and out of it (s): eased, never a cut (player/camera_blend.gd).
const CHEFTY_ENTER_CAMERA_SECONDS: float = 0.7
const CHEFTY_EXIT_CAMERA_SECONDS: float = 0.8
## A cartoon body sits down or stands up over this long (s), not in a frame.
const BODY_SIT_EASE_SECONDS: float = 0.22
## The point (Chefty's space, x mirrored to your side) the view swings out
## through on the way between your eyes and the chase camera: beside the bed,
## up over the rail, so it never passes through the truck.
const CHEFTY_CAMERA_SWING_OUT := Vector3(2.8, 2.6, 1.5)
## Walking round from one side of the truck to the other, a hand goes across in
## front of the nose here (z, Chefty's space; the bumper is at -3.0).
const CHEFTY_CLIMB_ROUND_FRONT_Z: float = -3.7
## ... and behind the tailgate here (z). Beside the truck means past this far
## out from its middle (m). Bed seats back of this z (the back row) are got into
## over the tailgate when you're behind the truck.
const CHEFTY_CLIMB_ROUND_BACK_Z: float = 3.5
const CHEFTY_CLIMB_SIDE_X: float = 1.25
const CHEFTY_CLIMB_TAILGATE_ROW_Z: float = 1.4
## Sat down in the legacy ride's bed, you turn to face your seat's way over this
## long (s), the length of a climb in, never in one frame.
const CHEFTY_BOARD_TURN_SECONDS: float = 1.0
## A client that hears the legacy ride leave later than this (s) starts it from
## the curb anyway, so the truck never jumps on its first frame; it makes the
## time up over the trip's first CHEFTY_RIDE_LATE_MAKEUP_SECONDS (s), running a
## little quick, so it reaches the far curb with the host (made up at the curb,
## it lurched 3-5 m into it).
const CHEFTY_RIDE_LATE_START_MAX: float = 0.05
const CHEFTY_RIDE_LATE_MAKEUP_SECONDS: float = 3.0
## After the cash, Chefty waits longer for the crew still out on the yard: when
## its window has this little left (s) and someone's still coming, it goes on
## this much longer (s, a last-call honk each time), up to this long in all (s).
const CHEFTY_BOARD_STRAGGLER_LEAD: float = 0.2
const CHEFTY_BOARD_STRAGGLER_STEP: float = 4.0
const CHEFTY_BOARD_STRAGGLER_WAIT: float = 24.0
## When it does go, whoever's within this of the bed (m, flat) climbs in; farther
## off they're left on the yard (never pulled into the bed from across it).
const CHEFTY_BOARD_GATHER_REACH: float = 7.5
## Asked for while on its way out to the yard, Chefty turns round for the
## straggler at the pad this long (s) after it drops the crew off.
const CHEFTY_FETCH_TURNAROUND_SECONDS: float = 1.5
## Walking to the door or the rail on the way in, the body turns to the way it
## goes over this long (s), never in a frame.
const CHEFTY_CLIMB_TURN_SECONDS: float = 0.4
## A walk on the way in shorter than this (m) is a sidestep: the body keeps facing
## where it looked rather than swinging round (and your view with it).
const CHEFTY_CLIMB_FACE_WALK_MIN: float = 1.5
## The legacy ride parks facing the way it came; leaving the other way it pulls a
## U-turn over this share of the trip's time (its first second, while it's still
## pulling away: the trip eases out).
const CHEFTY_RIDE_UTURN_SHARE: float = 0.12
## A climb into the legacy ride still being drawn when it pulls away finishes as
## a hop onto the seat this long (s); the host also waits this much past its own
## view of the last climb before it goes (a client hears of it a ping later).
const CHEFTY_BOARD_CLIMB_FINISH_SECONDS: float = 0.25
const CHEFTY_BOARD_CLIMB_MARGIN: float = 0.25

# ---- fx-yard: the yard and the people on it (docs/GAME.md "The yard's edges and
# the people on it"). The fence, the town's edge, the homeowner's framing, a
# teammate's catch-up after a network gap, and the rake bin under your look.
## The job yard's fence is solid (levels/lots/lot_generator.gd _fence_body): a box
## this thick (m) per run, this tall (m) by the hood's fence kind (a hand over the
## tallest picket or rail), reaching back this far (m) past each run's start so
## the back corners close, like the leaf field's fence line.
const YARD_FENCE_SOLID_THICK: float = 0.14
const YARD_FENCE_SOLID_HEIGHT: Dictionary = {
	"picket": 1.0, "weathered_picket": 1.0, "vinyl": 1.3, "split_rail": 1.15, "privacy": 1.7, "iron": 1.4,
}
const YARD_FENCE_SOLID_OVERLAP: float = 1.0
## The town line gives (levels/town/town_line.gd, net/components/vehicle_sim.gd).
## The hedge takes Chefty in a band this deep (m) in front of the hedge wall's
## inside face: its speed toward the hedge is held under what would stop it at
## this deceleration (m/s^2) by the face, so it noses into the leaves and stops
## there (under CHEFTY_CRASH_MIN_SPEED, never a crash); past the face it's pushed
## back out at this speed (m/s), turned away from the hedge at up to this rate
## (rad/s), and the leaves drag its sliding along the hedge (1/s) over the last
## TOWN_EDGE_LEAVES_DEEP (m).
const TOWN_EDGE_BAND: float = 9.0
const TOWN_EDGE_DECEL: float = 34.0
const TOWN_EDGE_PUSH_BACK: float = 1.4
const TOWN_EDGE_TURN_RATE: float = 0.9
const TOWN_EDGE_SIDE_DRAG: float = 2.2
const TOWN_EDGE_LEAVES_DEEP: float = 2.2
## A ROAD CLOSED barricade is for people (layer PAD_WALL_LAYER: they stop at it,
## Chefty doesn't): Chefty drives through, tipping the sawhorses and bowling the
## barrels, and loses this share of its speed per meter it spends among them.
const TOWN_EDGE_BARRICADE_DRAG_PER_M: float = 0.035
## The barricade's pieces, knocked (net/components/chefty_crash.gd _knock_over):
## how heavy (kg); a sawhorse tips over its feet (carried at this share of
## Chefty's speed, this much lift, m/s, turning at up to this rate, rad/s) and a
## barrel bowls away (this share, this lift). Struck, a sawhorse leaves a little faster than the bumper (it's
## light), so it flies ahead and off to the side instead of going under the truck.
const TOWN_EDGE_SAWHORSE_MASS: float = 7.0
const TOWN_EDGE_SAWHORSE_CARRY: float = 1.15
const TOWN_EDGE_SAWHORSE_UP: float = 2.4
## ... and off the side it was on at this speed (m/s), clear of the truck.
const TOWN_EDGE_SAWHORSE_SIDE: float = 3.5
const TOWN_EDGE_SAWHORSE_TIP: float = 6.0
const TOWN_EDGE_BARREL_MASS: float = 11.0
const TOWN_EDGE_BARREL_CARRY: float = 0.65
const TOWN_EDGE_BARREL_UP: float = 2.2
## Every peer, from where it draws Chefty: in the hedge's leaves faster than this
## (m/s) the hedge thrashes (leaves fly, hedge_plow), at most this often (s); the
## view of anyone riding along or this close (m) gets a little shake.
const TOWN_EDGE_PLOW_MIN_SPEED: float = 1.5
const TOWN_EDGE_PLOW_EVERY: float = 0.22
const TOWN_EDGE_PLOW_LEAVES: int = 24
## The thrashed hedge's leaves (m across): bigger than a pile's, so they read from the cab.
const TOWN_EDGE_PLOW_LEAF_SIZE := Vector2(0.1, 0.18)
## The homeowner, answering a talk (npcs/homeowner.gd host_stage_for): her spot
## is on the talker's line of sight, this far out (m), searched along it and to
## either side up to this angle (rad) for one inside her stage radius and clear
## of solids; if she still ends up more than this angle (rad) off the middle of
## the talker's view, the talker's view eases round onto her
## (P1_COUNTER_FRAME_SECONDS), at most this many degrees up or down (rad).
const HOMEOWNER_FRAME_SEARCH: float = 1.1
const HOMEOWNER_FRAME_OFF_CENTER: float = 0.26
const HOMEOWNER_FRAME_PITCH_MAX: float = 0.2
## Her face's height over her feet (m), what the view eases onto, and how long
## after she answers (s) a stop still frames her (later, your look is your own).
const HOMEOWNER_FRAME_FACE_Y: float = 1.5
const HOMEOWNER_FRAME_WINDOW: float = 4.0
## Walking round into the talker's view she keeps this far off them (m), never
## across their face.
const HOMEOWNER_ROUND_TALKER: float = 1.75
## Already this far off you (m, from..to) and more than this far (rad) off where you're looking,
## she answers from where she stands and your view turns to her instead.
const HOMEOWNER_FRAME_STAY_METERS := Vector2(1.4, 2.8)
const HOMEOWNER_FRAME_TURN_AT: float = 0.85
## A teammate's drawn body never jumps (net/components/net_smoother.gd): after a
## gap in their updates, the visual catches up to where the stream says at no
## more than this many times their own speed plus this much (m/s), so a burst
## after a stall glides in over a few frames instead of popping.
const SMOOTHER_CATCH_UP_SPEED_SHARE: float = 1.6
const SMOOTHER_CATCH_UP_SPEED_MIN: float = 2.5
## Off by more than this (m) after the gap, it's a move of its own (a short
## host-ordered hop), drawn as the stream has it.
const SMOOTHER_CATCH_UP_MAX: float = 1.5
## A player's drawn body is always held to that pace, judged by their replicated
## speed or how far the stream went over this long (s), whichever is more.
const SMOOTHER_SPEED_WINDOW: float = 0.25
## 2 AM while Chefty honks and waits for a trip out: everyone hops back out this
## long (s) after the day closes (levels/world.gd _tick_boarding), a beat after the yawn.
const CHEFTY_BOARD_CLOSED_BEAT: float = 0.9
## The night passing (levels/day_sky.gd): a clock jump this big (h) is worked out
## whole on its frame; the sleepers' eyes open on the morning, a veil of this
## color fading over this long (s), on this canvas layer (under the HUD's).
const DAY_SKY_JUMP_HOURS: float = 2.0
const DAY_SKY_WAKE_SECONDS: float = 0.9
const DAY_SKY_WAKE_COLOR := Color(0.03, 0.03, 0.06, 1.0)
const DAY_SKY_WAKE_LAYER: int = 0
## The last of the crew to lie down gets this long (s) on the cot before the night
## passes (net/day/day_clock.gd): the climb, a round trip, and a breath.
const SLEEP_LAST_ONE_BEAT: float = 1.6

# ---- fx-net (W9: trustworthy tests, the clock under load; docs/DECISIONS.md "fx-net")
## A client pings the host for its clock this often (s). Each ping bounds the
## offset; more of them give each bound more chances at a frame with no wait
## (net/clock_sync.gd). Two floats each way.
const CLOCK_PING_SECONDS: float = 0.25
## A client clock whose estimate fell back more than ClockSync.SNAP_SECONDS walks
## back at this share of real time (time runs at half speed) instead of jumping
## back: scheduled beats never replay.
const CLOCK_BACK_SLEW: float = 0.5
## A session's first this-many pongs (a joiner's, mostly through its loading
## stalls) set the clock straight to the estimate instead of slewing toward it.
const CLOCK_YOUNG_SAMPLES: int = 20
## A --fixed-step run's clock (game ticks): the window the offset's rate is
## fitted over (s), the samples it needs and how long a stretch they must span
## (s), how far over the quickest round trip a sample may be to count (s), and
## the fastest the offset may move (s a second: a window at 0.2 of real time
## beside a host at full speed is 4).
const CLOCK_RATE_WINDOW: float = 5.0
const CLOCK_RATE_MIN_SAMPLES: int = 4
const CLOCK_RATE_MIN_SPAN: float = 1.5
const CLOCK_RATE_RTT_SLACK: float = 0.03
const CLOCK_RATE_MAX: float = 4.0
## Chefty's driver: a frame that drops at least this many physics ticks has
## them stepped on the held input, as the host stood in for them
## (chefty_drive.gd _lost_ticks); fewer is the step counter's own jitter.
const CHEFTY_LOST_TICKS_MIN: int = 2
## NetSmoother: two updates are played back at least this far apart (s), a hair
## under the synchronizers' 0.033 s replication interval, so updates a loaded
## peer reads in consecutive ticks still take their interval each.
const SMOOTHER_MIN_SPACING: float = 0.03
## The gotcha two-shot's side (encounter.gd _clear_side) also keeps clear of the
## things the physics can't see (street lamps and scenery trees have no
## collider): a sight line from either face to the eye passes no post nearer
## than its radius plus this (m), and no post stands within STAGE_POST_LENS_CLEAR
## of the eye (one there fills half the frame: rec_fx_raid_1p 244-284).
const STAGE_POST_SIGHT_CLEAR: float = 0.3
const STAGE_POST_LENS_CLEAR: float = 1.1
## A street lamp's post radius (m) for that test, and a scenery tree's trunk as a
## share of its height (an evergreen's skirt goes by VAN_TREE_SPREAD.x instead).
const STAGE_LAMP_POST_RADIUS: float = 0.12
const STAGE_TRUNK_SHARE: float = 0.045


# ---- shops:9 seasonal supplies as work (docs/GAME.md "Seasonal work"; net/work/job_tasks.gd,
# props/sack_spread.gd, levels/lots/task_looks.gd). The sacks Homie Depot sells in
# season are crew kit (KIT_KINDS): bought into your arms, loaded on Chefty's rack,
# spread across the yard by holding left click. A sack's fill is its `fuel`.
## The tasks a sack does (TASK_TOOLS names the sack). A homeowner asks for one
## only while its sack is in season (Catalog "seasons", Seasons.FAVORED); the
## job board's general pick (job_board.gd choose_tasks) never draws them.
const SEASONAL_TASKS: Array[String] = ["fertilize_lawn", "seed_lawn", "salt_walk"]
## How many seconds of spreading a full sack holds, by sack kind: fertilizer
## covers about one lawn, seed and salt a couple of yards' patches or drives.
const SACK_SPREAD_SECONDS: Dictionary = {"fertilizer_bag": 100.0, "grass_seed": 34.0, "rock_salt": 34.0}
## The throw's radius where it lands (m), by task: a broadcast of fertilizer is
## wide, seed goes on a patch, salt on a strip of drive.
const SACK_SWATH: Dictionary = {"fertilize_lawn": 2.3, "seed_lawn": 1.4, "salt_walk": 1.5}
## The task grids' cell sizes (m): the whole lawn, the bare patches, the drive and walk.
const SEASONAL_GRID_CELL: Dictionary = {"fertilize_lawn": 2.0, "seed_lawn": 0.75, "salt_walk": 0.5}
## The bare patches a spring lawn has for overseeding: how many (at least, at
## most) and how big (radius, m), from the job's seed (never the yard's own rng).
const SEED_PATCHES := Vector2i(5, 8)
const SEED_PATCH_RADIUS := Vector2(0.9, 1.7)
## The shake: one flick of the sack this often while spreading (s), tipping it
## this far forward at the flick (rad), and the throw leaving the mouth this
## fast (m/s) at this many granules a flick.
const SACK_SHAKE_SECONDS: float = 0.42
const SACK_SHAKE_TILT: float = 0.42
const SACK_THROW_SPEED: float = 4.2
const SACK_GRANULES: int = 36
## Through your own eyes the throw is drawn starting this far ahead of the sack's
## mouth (m) and this much lower (m), clear of your face (props/sack_spread.gd).
const SACK_OWN_VIEW_AHEAD: float = 0.55
const SACK_OWN_VIEW_DROP: float = 0.2
## A sack slumps as it empties: an empty one stands this share of its full
## height (and bulges a little wider). Run dry, it folds flat over this long
## (s) and is gone, the hands free again.
const SACK_EMPTY_HEIGHT: float = 0.45
const SACK_FOLD_SECONDS: float = 0.55
## A sack bought at the counter comes into your arms: it waits this far ahead of
## you (m), at this height (m), for KIT_TAKE_HANDOFF_SECONDS, then you have it.
const SACK_HANDOFF_AHEAD: float = 0.55
const SACK_HANDOFF_HEIGHT: float = 0.9
## The shake's sound (tools/make_sfx.py "sack_shake") at this volume (dB).
const SACK_SHAKE_DB: float = -6.0