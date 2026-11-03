class_name Constants
extends RefCounted

## Project-wide constants that are not tuning values. Tuning values live in
## core/balance.gd, which is generated from the design workbook.

## Bump on every build you hand to someone else. Peers on different versions cannot join each other.
const BUILD_VERSION: String = "0.4.9"

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
const LEAF_GRASS_PRESS := Vector2(8, 45)
const LEAF_GRASS_PRESS_MAX: float = 0.85
const LEAF_GRASS_SPRING: float = 0.4
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
const CREW_SPOT_FREEZE: float = 0.35
## The lunge: within range and inside the front cone (degrees) he winds up for
## CREW_LUNGE_WINDUP s, stretched by up to CREW_LUNGE_WINDUP_LAG_MAX for the
## target's half round trip, then covers CREW_LUNGE_DISTANCE m in CREW_LUNGE_SECONDS.
const CREW_LUNGE_RANGE: float = 2.6
const CREW_LUNGE_CONE_DEG: float = 60.0
const CREW_LUNGE_WINDUP: float = 0.35
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
## A found hider is grabbed this long (s) after the inspection says so (no lunge).
const CREW_FOUND_CONTACT: float = 0.3
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
const CATCH_CAM_BLEND: float = 0.35
const CATCH_HOLD_END: float = 0.95
const CATCH_BARK_AT: float = 0.95
const CATCH_CITE_AT: float = 1.0
const CATCH_CITE_SECONDS: float = 2.0
## The two-shot: low, side-on, this far from the pair (m), pushing in by this share.
const CATCH_CAM_DISTANCE: float = 2.6
const CATCH_CAM_HEIGHT: float = 1.25
const CATCH_PUSH_IN: float = 0.03
## Its field of view (degrees): tighter than the player's, so the two faces fill it.
const CATCH_CAM_FOV: float = 55.0
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
const CATCH_GOTCHA_GAP: float = 0.78
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
	"back_room": {"owner": "shops", "rect": Rect2(-11.6, -19.4, 2.2, 2.2)},
	"snak_o_matic": {"owner": "shops", "rect": Rect2(-12.0, 3.0, 3.0, 3.0)},
	"garden_center": {"owner": "shops", "rect": SHOP_SITES["homie_depot"]["area"]},
	"rustys": {"owner": "shops", "rect": SHOP_SITES["rustys"]["area"]},
	"lunch_money": {"owner": "shops", "rect": Rect2(0.6, 13.5, 6.4, 4.5)},
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
	"marty_ramp": {"owner": "driving", "rect": Rect2(12.4, 14.4, 3.6, 3.6), "at": Vector3(14.2, 0.0, 16.2), "yaw": 0.0},
	"depot_safe_sign": {"owner": "driving", "rect": Rect2(18.6, 12.4, 1.6, 1.4), "at": Vector3(19.4, 0.0, 13.1), "yaw": PI * 0.5},
	"mulch_bin": {"owner": "driving", "rect": Rect2(4.9, 9.4, 2.6, 2.6), "at": Vector3(6.2, 0.0, 10.7), "yaw": 0.0},
	"pylon": {"owner": "art", "rect": Rect2(18.0, -14.5, 2.0, 2.0), "at": Vector3(19.0, 0.0, -13.5), "yaw": PI * 0.5},
	"propane_cage": {"owner": "art", "rect": Rect2(-9.6, -9.8, 2.0, 2.6), "at": Vector3(-8.6, 0.0, -8.5), "yaw": PI * 0.5},
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
## The goal line says "go to" instead of "get in Chefty" within this many meters
## of the yard's curb.
const GOAL_WALK_METERS: float = 45.0
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
## Tells: turning faster than this (rad/s) inside a hedge or pile shakes it.
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
## An inspection: a NICE BOY pokes the spot for this long (s), from this far out (m).
const HIDE_INSPECT_SECONDS: float = 2.0
const HIDE_INSPECT_STAND: float = 1.2
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
## Found: he lifts you out toward him over this long (s), then the gotcha.
const HIDE_PULL_SECONDS: float = 0.5
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
	{"id": "moving", "actions": [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"crouch"]},
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
## Leftover losses and gains pair up within this distance (m).
const LEAF_FLOW_MAX_DIST: float = 4.5
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
const RAKE_SWING_PHASES: Dictionary = {"plant": 0.2, "drive_end": 0.7, "flick_end": 0.85}
## A hired hand's swing (HIRE_STROKE_SECONDS / skill long) bites once, here.
const RAKE_CREW_BITES: Array[float] = [0.25]
## How far ahead of the feet the tines plant, and where the drive ends (m). The
## hands hold the 1.6 m handle near its top, so the plant can't come closer than
## this without the hands going up past the face; the far end needs the lunge.
const RAKE_HEAD_NEAR: float = 1.25
const RAKE_HEAD_FAR: float = 1.95
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
## reach. The upper hand aims for the chest with the head close in and out over
## the belly at full stretch, in the holder's body space (x right, y up, -z ahead),
## before the lunge; it slides at most RAKE_HAND_SLIDE_MAX down from the top.
const RAKE_HAND_SPAN: float = 0.48
const RAKE_HAND_SPAN_MIN: float = 0.35
const RAKE_HAND_NEAR: Vector3 = Vector3(0.16, 1.3, -0.3)
const RAKE_HAND_FAR: Vector3 = Vector3(0.12, 1.0, -0.6)
const RAKE_HAND_SLIDE_MAX: float = 0.3
## Your own rake while you look through your eyes (your body is hidden then, and
## the camera doesn't lunge): both hands at the handle's top, this far apart, and
## your first-person arms may stretch to this times their length to hold on.
const RAKE_HAND_SPAN_FP: float = 0.3
const RAKE_FP_ARM_STRETCH: float = 1.9
## Where the handle aims then, in body space: just past your right shoulder.
const RAKE_FP_HANDLE_AIM: Vector3 = Vector3(0.3, 1.25, 0.0)
## The handle slides this far through the hands over a drive (m).
const RAKE_HANDLE_SLIDE: float = 0.1
## The body leans into the shove (torso x, negative is forward), twists with the
## drift, sticks its hips back as the tines plant (m) and then lunges forward
## into the drive, the left foot stepping out (m).
const RAKE_LEAN_X: float = -0.36
const RAKE_TWIST_Y: float = 0.2
const RAKE_HIP_SHIFT: float = 0.06
const RAKE_LUNGE: float = 0.3
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
## this share of the twist the other way, the shoulders this share of it with; the
## front foot steps out this share of the lunge; the face tilts down this share of
## the lean.
const WORK_HIP_COUNTER: float = 0.1
const WORK_TWIST_SHARE: float = 1.1
const WORK_FRONT_STEP: float = 0.6
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
## How long a refusal's toast stays up, and the emptied-pockets notice (s).
const HOTBAR_TOAST_SECONDS: float = 1.8
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
const LEAF_SFX_GAIN_FLOOR_DB: float = -12.0
const LEAF_SFX_GAIN_CAP_DB: float = 2.0
## Leaves landing and kicked: a landing starts this many dB down (a kick starts
## at LEAF_SFX_GAIN_FLOOR_DB), and both get this many dB louder each time the
## count of leaves doubles, never over 0.
const LEAF_SETTLE_BASE_DB: float = -10.0
const LEAF_SFX_DB_PER_DOUBLING: float = 3.0
## How long the scrape file is (s): its pitch stretches it over half a swing.
const RAKE_SCRAPE_SECONDS: float = 0.30
const RAKE_SCRAPE_PITCH: Vector2 = Vector2(0.9, 1.15)
## The scrape starts this long after the plant (s).
const RAKE_SCRAPE_DELAY: float = 0.015
## A swing's length when an event doesn't say (s): two strokes.
const LEAF_SFX_DEFAULT_TEMPO: float = RAKE_STROKE_SECONDS * 2.0
## Where the sounds sit along the stroke: the plant this far behind the request
## origin (where the head lands, m), the flick this far ahead (the end of the
## drive), and the flick this fraction of a swing after the mid-drive bite.
const LEAF_SFX_PLANT_BACK: float = 0.5
const LEAF_SFX_FLICK_AHEAD: float = 0.75
const LEAF_SFX_FLICK_PHASE: float = 0.2
## Leaves landing: at least this many in one place to be heard, at most this many
## settle sounds a second, a whump at most once per this long per 2 m area (s),
## and the least a landing must be to whump.
const LEAF_SETTLE_MIN: int = 3
const LEAF_SETTLE_PER_SECOND: int = 3
const PILE_WHUMP_GAP: float = 0.25
const PILE_WHUMP_MIN: int = 6
const PILE_WHUMP_AREA: float = 2.0
## A bag: the stuffing this long after the bag opens, the tie this long (s), and
## the units of leaves for a full-strength stuffing.
const BAG_STUFF_DELAY: float = 0.15
const BAG_TIE_DELAY: float = 0.45
const BAG_STUFF_REF_UNITS: float = 4000.0
## Footsteps by leaf depth (LeafAudio.step_id): deeper than this is "deep", and
## than this a pile.
const LEAF_STEP_DEEP_DENSITY: int = 60
const LEAF_STEP_PILE_DENSITY: int = 150

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
## Copier jam: one break this long at the copier.
const ANNEX_JAM_SECONDS: float = 12.0
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
const ART_BLOCK_PARCELS_PER_FRAME: int = 2
const ART_NEIGHBOR_LEAF_PATCHES: int = 3
const ART_STRING_LIGHT_SPACING: float = 0.45
const ART_GRASS_WINTER_SPACING_SCALE: float = 1.6
const ART_DOOR_OPEN_DISTANCE: float = 3.2
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
## Riders: a pothole and the air freshener this long into the drive (s), the
## freshener close-up for VAN_RIDE_MONTAGE (s), then the iris (VAN_IRIS_SECONDS).
const VAN_RIDE_IRIS_AT: float = 5.0
const VAN_RIDE_MONTAGE: float = 1.8
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
## The legacy and town job street in the yard's space: the far curb the van parks
## on and the lane it drives in (z), the lane change between them (m), and the
## spacing of a route's ground-checked points (m).
const VAN_CURB_Z: float = 28.6
const VAN_LANE_Z: float = 27.4
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
const RETURN_PULL_UP: float = 3.0
const DROP_IMMUNITY: float = 6.0
## Without the Annex set (nice_boys:5) the van pulls up here, BorderZone space.
const VAN_ANNEX_CURB := Vector3(-4.0, 0.0, 24.0)
## Home after the job's done: the Homie Depot curb (StoreZone space), facing -z.
const SHUTTLE_STORE_STOP := Vector3(23.8, 0.0, 6.0)
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
## farther than this off the curb line (m, toward the far sidewalk, toward the near
## one: up a curb if it must), eased in and out over this many meters either side.
const VAN_ROUTE_CLEARANCE := Vector3(3.0, 2.5, 2.2)
const VAN_SWERVE_RANGE := Vector2(3.9, 7.1)
const VAN_SWERVE_EASE: float = 10.0
## A tree's crown, from above, reaches this share of its height from the trunk
## (evergreens, broadleaves): the van parks and drives clear of it.
const VAN_TREE_SPREAD := Vector2(0.3, 0.2)
## The air freshener close-up's field of view (degrees), tight on the daisy.
const VAN_FRESHENER_FOV: float = 38.0
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
const VAN_ANNEX_DOOR_TO_CURB: float = 1.75

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
## player eases sideways out of the way.
const CLERK_STAND_OFF: float = 0.85
## A clerk's head turns ease this fast (1/s): no one-frame snap.
const CLERK_FACE_EASE: float = 14.0
## A player slamming the big stamp holds it up only this long (s).
const ANNEX_BIG_STAMP_HOLDER_HESITATE: float = 0.12
## The visitors' side door answers interact only this close (m).
const ANNEX_SIDE_DOOR_REACH: float = 1.1