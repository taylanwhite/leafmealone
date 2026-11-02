# Balance: the simulator, the targets, and the numbers

Leaf Me Alone's economy is tuned with code, not by feel alone and not in the workbook. `tools/balance_sim.py` is the balance lab: a Monte Carlo simulator that reads the game's own tuning numbers, plays crews of 1 to 4 players through the town for months of in-game days, and checks the result against the pacing targets in `core/constants.gd`. This file says how it works, how to run it, what it assumes, and what it found. The design decision is in `docs/DECISIONS.md` ("The balance lab is code").

## Running it

Python 3 with the standard library only (`%LOCALAPPDATA%\Programs\Python\Python312\python.exe` here).

| Command | What it does |
| --- | --- |
| `python tools/balance_sim.py` | Simulates crews 1 to 4 over 40 seeds (about 4 s), prints the summary table and every check, writes `build/balance/report.json` and `report.md`. |
| `--check` | Exit 1 when a blocking check fails. |
| `--check --baseline` | Runs and prints the checks; the tuning checks (a) to (e) and (g) don't fail the exit code. Today's numbers fail them on purpose (see the baseline below); CI uses this until the retune (gap balance:E) drops it. Engine parity (f) and the self-test are never excused: a misparsed constant or a drifted mirror exits 1 even with `--baseline`. |
| `--strict` | Warnings block too. |
| `--players 1,4 --seeds 20 --days 120` | Crew sizes, runs per size, and the most days a run plays. With `--check`, `--players` must include 1 and 4 (the blocking checks are for them), or it exits 2. |
| `--set NAME=VALUE` | A what-if, repeatable. NAME is `Script.NAME[.key...]` or a bare constant (looked up in Constants, then Ranks, Balance, Seasons). VALUE is a GDScript expression: `--set TOWN_REGROW_PER_DAY=0.3`, `--set Ranks.XP_FIRST_TIER=160`, `--set Constants.TOOL_PRICES.leaf_blower=400`, `--set "HIRE_SKILL=Vector2(0.5, 0.9)"`. A name, key or index the game doesn't have is a typo and exits 2; only the crew-scale hooks balance:E will add (`CREW_WORK_SCALE`, `CREW_PATIENCE_SCALE`, `XP_CREW_SCALE`) may be new. Nothing in the repo changes. |
| `--html [path]` | Also writes `build/balance/report.html`: hours per tier against the pace targets, and cash per player by day, as inline SVG, plus the tables. |
| `--report`, `--md` | Where the JSON and Markdown go. |
| `--engine-dump host.json` | Compares every constant the simulator reads, and a grid of formula calls, with what the engine computed (`--balance-test`'s probe report, below). Any difference, a case the sim has no mirror for, or a failed engine invariant fails check (f). |
| `--propose` | Searches for values toward the targets (below) and prints a diff; writes `build/balance/proposal.json`. Edits nothing. About a minute; local only, never in CI. |

Exit codes: 0 pass, 1 a blocking check failed, 2 a parse or usage error (a constant the simulator needs is missing or doesn't parse, a bad `--set`, a bad file).

`python tools/balance/gdconst.py` lists every constant it read from the six scripts and anything it couldn't parse.

## How it works

**It reads the game, never a copy.** `tools/balance/gdconst.py` parses the top-level `const` declarations of `core/constants.gd`, `core/balance.gd`, `core/ranks.gd`, `core/seasons.gd`, `net/town/neighborhoods.gd` and `core/catalog.gd` (numbers, strings, arrays, dictionaries, `Vector2`/`Vector2i`/`Vector3`/`Rect2`/`Color`, `&"names"`, `PI`, arithmetic, earlier constants of the same file, and `"%d" % [..]`). Anything it can't read is reported, not guessed, and a constant the simulator needs that doesn't parse stops the run with exit 2. On 2026-11-01 every constant in all six files parses (390 in all), and every one the simulator reads matched an engine dump of the same scripts.

**It mirrors the formulas exactly.** The `Economy` class in `balance_sim.py` is `core/economy.gd` line for line (with Godot's rounding: halves away from zero), and `Ranks`, `Seasons` and `Catalog` mirror `ranks.gd`, `seasons.gd` and `Catalog.price`. The engine's grid of 1,171 calls (`--balance-test`, below) matches the mirror exactly, and CI checks it on every run. Changing a formula in `core/economy.gd` means changing the mirror in the same commit.

**What it mirrors by hand** (keep in step; the parity check can't see these):

- `net/town/town.gd`: the 47 houses and their owners (statistically, not Godot's random numbers), three Maple Row clients on day one, morning requests (`requests_per_day` with the extra-request perks), daytime texts, the request threshold, missed requests, relationship and referrals (with the word-of-mouth perks), Marty's lead when nobody texts, new neighborhoods opening by rank, TurfMasters™ poaching, signs and winning clients back.
- `levels/job_board.gd` `choose_tasks` (owned tools, the unowned-tool task, extra tasks by yard size) and `Town.offer_for` (the owner's favorite task, the season's task, the season's leaves).
- `npcs/homeowner.gd` `_judge` and `_handle_talk`: how done the job is (leaves and every task weighed alike), standards, patience (with sweet talk), the mood odds including the "some days people are just in a mood" rolls, and the pay.
- `Campaign.finish_job` (Lawnfather stars, the season, quiet hours and night owl on top; XP per job; the town's XP; an even split, since the simulator gives every player the same contribution), `Campaign.crew_tools` (tools are shared), `net/crew/hires.gd` `pay_wages` (newest hand quits first when the crew can't pay), `net/day/day_clock.gd` (7 AM to 2 AM, no new job once the clock stops, sleep from 6 PM, XP banked at bedtime), `net/run_events/director.gd` `_consider_roll` (every 20 s once 10% is done, the cooldown that shrinks with heat, a raid at 95 heat) and `heat.gd` (noise by tool, neighborhood and quiet hours; cooling; 35 off per paid job; 15 after a raid).

Some numbers those files still write inline are copied into `tools/balance/model.json` (`homeowner_inline`, `town_inline`) with that source note. They should move into `constants.gd`, at which point the model entries go.

**What it can't read from the game** is in `tools/balance/model.json`: how fast a crew rakes, how long tasks take, how often a tool runs, what a raid costs in minutes, how players pick jobs and spend money. Every entry has a `source`: a guess, a doc, or a game file it mirrors. Today they are all guesses or hand mirrors; gap balance:G calibrates them from bot soaks, and one or two real play sessions' telemetry (`user://logs/session_*.json`) would be better still.

**One day, simulated:**

1. Morning: requests are on the phone. Homie Depot is open 7 AM to 9 PM: the crew buys what it wants (below) and hires a hand if it can.
2. The crew takes the request with the best expected pay per minute, rides out, works, and settles with the homeowner. Work: the leaves at the crew's rate (the one rake, a leaf blower, the rake tune-up for its share, the wheelbarrow, hired hands), the doable tasks split across the players, and nothing for a task the crew has no tool for. If finishing would outlast the homeowner's patience, the crew either finishes ("slow") or wraps up at the patience line with less done, whichever pays more per minute.
3. While they work the heat rises with the loud tools (run in one stretch, as many at once as there are players) and the director rolls; a raid costs the chase and, for each player caught, Border Return.
4. Daytime texts come in at 10, 1, 4 and 7. With nothing to do before 6 PM the crew waits for the next text, then sleeps. With requests waiting they keep working until the clock stops at 2 AM.
5. Bedtime: XP is banked and ranks unlock, wages are paid, the town's new day.

Hours of play are real minutes: the day's clock (jobs and raids run on it, so they cost no extra hours) plus a minute of summary card per day. One in-game hour is `MINUTES_PER_HOUR` (1.25) real minutes.

**Money:** each player has a wallet, pay is split evenly, tools and upgrades are crew-shared (bought by the richest player as soon as they can keep a day of wages), and per-player things are bought by each player. `model.json` `buy_policy` and `hire_policy` say exactly when.

## The targets

`core/constants.gd`, `# ---- balance targets`:

| Rank (tier I) | Hours (median) |
| --- | --- |
| Leaf Grunt | 1.0 |
| Bag Hauler | 2.5 |
| Mulch Mule | 4.5 |
| Hedge Hog | 6.5 (every tool unlocked) |
| Turf Boss | 9.0 (hiring opened at Hedge Hog III, about 7.5 h) |
| Lawn Lord | 11.5 |
| Yard Baron | 14.0 |
| The Lawnfather | 16.0 |

- `ARC_HOURS = Vector2(10, 20)`: the median hours to The Lawnfather for a solo crew and for four players.
- `RANK_PACE_HOURS`: the table above (index 0 is Rake Rookie at 0 h). Within ±35% is on pace.
- `ARC_SOLO_RATIO_MAX = 1.3`: solo may take at most 1.3 times as long as four players.

The other thresholds (what a tool should cost in days of income, raid frequency bands, the endless loop) are in `model.json` `targets`.

## The checks

Blocking (exit 1 with `--check`):

- **(a)** median hours to The Lawnfather inside `ARC_HOURS`, for crews 1 and 4.
- **(b)** the first rank-up is banked on night one (90% of runs), crews 1 and 4.
- **(c)** every tool in `TOOL_PRICES` is bought within 2 days of unlocking (median), and costs 0.5 to 2.0 days of one player's income when it unlocks.
- **(d)** the hiring fee is at most 2 days of a player's income when hiring opens, the crew hires within 2 days, and the hire policy never makes a hand quit.
- **(e)** before The Lawnfather, no tier takes more than 2 days (median).
- **(f)** with `--engine-dump`: every constant the simulator reads equals the engine's (floats to 1e-6), every formula case matches (and has a mirror), and the engine's invariants passed. `--baseline` never excuses it.
- **(g)** with `enforce_endless` in `sinks.json` (gap balance:F): over 20 days past The Lawnfather, recurring sinks (wages, consumables, rent) take 30 to 60% of gross income, and the unbought catalog is worth at least 5 days of net income at The Lawnfather.

Warnings (blocking with `--strict`): each rank within ±35% of its pace target; the solo/quad ratio; p10 and p90 of the arc (10 − 1 h, 20 + 3 h); crews 2 and 3 inside `ARC_HOURS`; raids per job in each band (a quiet daytime Maple Row job 10 to 40%, a job with the mower and the blower 45 to 75%, Mansion Hill in quiet hours 75 to 100%).

The run also checks itself: the same seed gives the same result twice (exit 2 if not), and every sink's price agrees with `Catalog.price` (a blocking check `--baseline` doesn't excuse).

## Baseline, 2026-11-01 (build 0.4.1, today's numbers)

```
                              crew 1    crew 2    crew 3    crew 4    target
hours to tier I of each rank (median)
  Leaf Grunt                     2.2       1.4       1.0       0.9       1.0
  Bag Hauler                     5.5       3.5       3.0       2.6       2.5
  Mulch Mule                     9.5       6.0       5.2       4.7       4.5
  Hedge Hog                     16.2      10.3       8.5       7.9       6.5
  Turf Boss                     24.4      16.0      12.9      11.7       9.0
  Lawn Lord                     33.0      22.3      18.2      16.4      11.5
  Yard Baron                    43.8      29.7      25.1      22.4      14.0
  The Lawnfather                54.1      37.3      31.9      28.8      16.0
Lawnfather p10 (h)              49.9      33.5      28.2      25.5
Lawnfather p90 (h)              61.3      42.3      35.5      31.1
days to The Lawnfather          81.5      61.0      56.0      52.0
jobs to The Lawnfather           130       121       118       118
jobs per day                     1.6       1.9       2.1       2.3
tier after night 1                 2         2         2         3
$/player/day, Rake Rookie        578       379       304       230
$/player/day, Bag Hauler         454       325       267       216
$/player/day, Hedge Hog          732       351       295       240
$/player/day, Lawn Lord         1030       609       511       505
$/player/day, The Lawnfather     964       627       666       587
days of income, blower          0.17      0.23      0.27      0.32
days of income, washer          0.52      0.77      1.02      1.28
hire fee, days of income        0.18      0.43      0.48      0.59
raids per job                   5.21      4.54      4.39      4.21
days bound by clock             0.98      0.96      0.97      0.96
days bound by requests          0.02      0.04      0.03      0.04
jobs past patience              0.81      0.43      0.35      0.27
```

As expected, today's numbers fail `--check`: 12 blocking checks and 37 warnings fail (`--baseline` keeps CI green until the retune).

(Re-recorded after review fixes: the town's morning now runs on the new day, as `DayClock._end_day` does, so a yard has a day more regrowth when it decides whether to text; and a house's offer is drawn once per day, like `Town.offer_for`'s `hash([seed, _day])`, instead of re-rolled every time the crew looks. Both moved the arc by about an hour.)

- **The arc is far too long:** 54 h solo and 29 h for four players, against 10 to 20 h. Solo takes 1.9 times as long as four players (target at most 1.3).
- **The NICE BOYS are the biggest reason.** About 4 to 5 raids per job, and 80 to 95% of quiet daytime Maple Row jobs are raided (target about 25%). The director rolls every 20 s with the workbook's per-lot chance (BAL-14, 10%), rising 5% for every job ever finished to the 65% cap, so after about 11 jobs only the cooldown holds them back; and the cooldown shrinks to nothing as heat rises, while 60 s of mowing reaches 95 heat, a certain raid. Each raid costs the crew about two minutes. With raids switched off (`--set Balance.RUN_EVENT_BASE_CHANCE=0 --set Balance.RUN_CHANCE_ESCALATION_PER_TIER=0 --set HEAT_RAID_AT=1000 --set HEAT_CHANCE_AT_MAX=0`) the arc is 34 h solo, 21 h for two, 16 h for three and 13 h for four, 2.6 times as long solo.
- **Money stops mattering at once.** Every tool costs 0.17 to 1.3 days of one player's income when it unlocks, and is bought the same day; the hiring fee is 0.2 to 0.6 days. Cash piles up to $16,000 (four players) to $55,000 (solo) per player by the night they reach The Lawnfather, with nothing to buy.
- **Every client asks every day** (a yard regrows 0.35 a day and owners ask at 0.3), so the clock binds 96 to 98% of days, almost never the requests.
- **Solo crews run out of patience:** 81% of solo jobs go past the homeowner's 12 minutes.
- The first night banks two or three tiers for every crew size (target: two to four).

**What `--propose` suggested** (12 seeds per crew, starting from the gap spec's candidates; nothing applied): XP curve 111/22 (first/step), `XP_CREW_SCALE` about [2.1, 1.5, 1.29, 1.0], `CREW_WORK_SCALE[0]` about 0.53, tools $300 to $460, the tune-up and wheelbarrow about $460 and $420, a $620 signing fee and a $25 wage. Read it as a direction, not as values: it tunes the XP curve around today's raid storm, which the retune changes first (the director rolls by neighborhood and converts BAL-14 from per job to per roll), and the $25 wage says the model thinks a hand adds only $33 to $48 a day; `hand_leaf_rate` is a guess worth checking before wages are set. Rerun `--propose` after the director change.

## The engine parity test

`--balance-test` (`net/dev/balance_test.gd`, port 7819, host only, about a second) is the engine's half of check (f). Its probe report (`balance_test` in `host.json`) holds:

- `constants`: `get_script_constant_map()` of the six scripts the simulator reads, as `{script: {name: value}}` with vectors and colors as lists. It is a JSON string inside the report, because one table (`JUNK_PER_HOOD`) has a `""` key that PowerShell 5.1's `ConvertFrom-Json` rejects; the simulator decodes it.
- `cases`: `[{fn, args, out}]` for a fixed grid: `Ranks.xp_for_tier`, `xp_to_reach`, `tier_for_xp` and `xp_into_tier` at every tier edge to Lawnfather ★6, `pay_bonus`, `tier_of` for every unlock, `Seasons.of_day` for days 1 to 60 and `year_of`, `Catalog.price` for every item, and every `core/economy.gd` function over its inputs (job XP by cleaned share, tasks, stars and crew; `migrate_xp` between today's curve, the legacy one, a steeper one and a bad id; regrow; relationship; the verdict lines; pay by mood and budget; bag perks; crew scales; the raid roll over heat and progress). The simulator calls its mirror with the same arguments.
- `invariants`, which set `ok`: every `shop:` unlock has a price, every tool unlocks by tier 25, every `hood:` unlock is a neighborhood, the crew-scale tables (once they exist) have one entry above 0 per crew size, `RANK_PACE_HOURS` has a target per rank, rises, and ends inside `ARC_HOURS`, tiers and XP agree at every edge, and a save keeps its tier across an XP-curve change (`Campaign.crew_xp_from_save`, what loading runs) and writes `crew.curve`.

Locally: `tools\ci_local.ps1 -Only balance,balance-sim` (about 10 s). `balance-sim` alone needs no Godot and uses the last `build\soak\local-balance\host.json` if there is one (and says how old it is). In CI it is the "Balance simulator" step. A new function in `core/economy.gd` gets cases in the grid and a mirror in `balance_sim.py` (`mirror_functions`); a case with no mirror fails (f).

**Retuning the rank curve.** Saves keep `crew.curve` (`Ranks.CURVE_ID`, "first/step/endless"). On load, XP banked under another curve (or under `Ranks.LEGACY_CURVE_ID`, "150/25/1200", for saves from before the key) moves onto today's at the same tier and fraction (`Economy.migrate_xp`), so changing `XP_FIRST_TIER`, `XP_PER_TIER_STEP` or `XP_ENDLESS_TIER` never costs a crew its rank. Pending XP is kept as it is; owned items stay owned; hands keep their saved wage.

## Adding a sink

`tools/balance/sinks.json` lists every place money can go. An entry:

```json
{"id": "leaf_blower_mk2", "kind": "tool_tier",
 "price": "const:Constants.TOOL_PRICES.leaf_blower", "price_mult": "const:Constants.TOOL_TIER_PRICE.2",
 "gate": ["unlock:shop:leaf_blower_mk2", "after:leaf_blower"], "per_player": false,
 "effect": {"tool": "leaf_blower", "speed": "const:Constants.TOOL_TIER_SPEED.2", "heat_mult": "const:Constants.TOOL_TIER_NOISE.2"},
 "want": "endless", "status": "planned"}
```

- `kind`: tool, upgrade, tool_tier, consumable, cosmetic, truck, property or wage.
- `price`: never a number; a `const:` path into the game's constants (`const:Constants.SHOP_PRICES.<id>`), optionally times `price_mult`. A list multiplies its parts. A path that doesn't resolve yet skips the entry with a warning, so planned items can be listed before their constants land (properties are, today).
- `gate`: `unlock:<rank unlock>`, `tier:N`, or `after:<sink id>`; a list needs all of them.
- `per_player`: bought by each player (cosmetics) or once for the crew (tools).
- `effect`: `blower`, `rake_mult`, `leaf_rate_mult`, or a tool tier's `tool`, `speed`, `heat_mult`. Values can be `const:` or `model:` references.
- `uses_per_job` or `uses: "bags"` with `per_unit` (consumables), `rent_per_day` (properties, wages).
- `want`: `always` (buy as soon as affordable), `endless` or `cosmetic` (buy only with a couple of days' income to spare).
- `status`: `live` entries are bought in the simulation; `planned` ones are only priced. Today the tools, the three upgrades and hired hands are live; tool tiers, supplies, workwear, truck paint and properties are planned until gap balance:F turns them on with `enforce_endless`.

## The workbook

`core/balance.gd` stays generated from the workbook's Balance Lab, and the simulator reads it (the per-lot cleanup credits, the run-event chances, BAL-06 utilization, BAL-12 throughput). The spine's tuning lives in `constants.gd` and `ranks.gd`, because agents can't edit the workbook and the Balance Lab still models the old eight-lot game. `ARC_HOURS` overrides BAL-01/02 (5 to 10 hours) for the simulator. The workbook update is a request to Taylan once the retune lands (gap balance:E, `docs/HANDOFFS.md`); a read-only "Balance Sim" sheet could be filled from `build/balance/report.json`.

## Still to come

- **balance:E**: the retune, from `--propose` and the checks, with the director change; `--baseline` comes off.
- **balance:F**: sinks from the shops (tool tiers, supplies, workwear, paint, properties) go live, and the endless-loop check blocks.
- **balance:G**: calibrate `model.json` from bot soaks.
- Travel time on the drivable town (`model.json` `travel_minutes_by_hood`, `town` row) is a guess until `TownMap` lands; the legacy map's rides are already in the job overhead.
