# The spine: days, rank, the town, the phone

Written 2026-11-01 from Taylan's direction: play like Schedule I (a small crew that
grows from nothing into the biggest outfit in town), keep a persistent town, four
players, early access. This is the design every agent builds toward. It is ours to
change: when something here turns out wrong in play, change it here in the same
commit as the code.

Schedule I research behind it is summarized at the end.

## The shape in one paragraph

You start with a rake, a beat-up Chefty, and three neighbors who'll pay. Every work
day runs on a clock. Clients text you jobs; you pick which yards to hit, ride out,
do the work, get paid by a homeowner whose mood you earned. At night you sleep at
the crew's place, the day's experience is banked, the crew ranks up, and new things
unlock. Happy clients refer their neighbors. Each neighborhood up the hill pays more,
expects more, and has more NICE BOYS around. Later you hire crew to do the dull
work, rent bigger places, fight a rival outfit for the town, and the seasons turn.

## 1. Work days

- **The clock.** One in-game hour is `Constants.MINUTES_PER_HOUR` real minutes
  (1.25). The day starts at 7:00 AM. Work hours run to 9:00 PM.
- **Quiet hours,** 9:00 PM to 2:00 AM: jobs pay `QUIET_HOURS_PAY_BONUS` more, and
  noisy tools raise heat `QUIET_HOURS_HEAT_SCALE` times faster. Risk for money,
  like Schedule I's curfew deals.
- **2:00 AM.** The clock stops until the crew sleeps. Nobody is forced; you just
  can't start a new job.
- **Sleeping.** Everyone in the store zone lies down on a cot in the crew room at
  the back of Homie Depot ("the back room": the store manager lets you crash
  there for a cut, a joke the clerk makes). When every player is on a cot (or the
  host holds E for three seconds to drag everyone to bed), the day ends.
- **The day's end** shows a summary card: jobs done, cash earned, stars, XP banked,
  rank-ups and what they unlocked. Then the save is written, yards regrow, and the
  next morning's texts arrive.
- The clock is host-owned: the host sends the day number and the server time the
  day started; every peer computes the hour from `Net.server_time()`.

## 2. Crew rank

- The crew shares one rank (it's co-op). XP is earned per job: a flat amount per
  task finished, a bonus per star, a bonus for a new client, and small amounts for
  bonking a NICE BOY or getting away from them. XP is **pending** until you sleep,
  like Schedule I, so a night's sleep is a payoff moment.
- XP is flat per action, never per dollar, so a windfall can't skip ranks.
- **Ranks**, five tiers each (I to V):
  1. Rake Rookie
  2. Leaf Grunt
  3. Bag Hauler
  4. Mulch Mule
  5. Hedge Hog
  6. Turf Boss
  7. Lawn Lord
  8. Yard Baron
  9. **The Lawnfather**: endless; each tier past V adds a star and a little pay.
- **Every tier unlocks something** (Schedule I's back half has empty "wall" ranks;
  we don't). The table lives in `core/ranks.gd`. Tools unlock in roughly this order:
  leaf blower, push mower, ladder, hose, hedge trimmer, pressure washer, paint
  roller. Then the upgrades and new neighborhoods take over. Every tool is
  unlocked by the end of rank 5. After that, the unlocks are neighborhoods,
  hiring, properties, and tool tiers.
- Shop items show **"Rank X"** until you reach it.

## 3. The town

The town persists. Houses, homeowners, and what they think of you are saved. Each
yard's mess regrows over the days since you last did it.

- **Neighborhoods,** in order. Each one has 6 to 9 houses, its own look, richer
  clients, higher standards, and more NICE BOYS heat per noise.
  1. **Maple Row**: the starter suburb, bungalows and small lots.
  2. **Dandelion Acres**: a mobile-home park with big shared lawns and junk to haul.
  3. **Birchwood Commons**: newer two-story houses, pools start appearing.
  4. **Oak Hollow**: the HOA. Inspections and fines, and fussy clients.
  5. **Lakeside**: pools, docks, and very long hedges.
  6. **Mansion Hill**: estates, fountains, and celebrity clients.
- **Clients** are the homeowners. Each has a name, a personality (the lines they
  say), standards (how picky the mood is), a budget, favorite work, and a
  **relationship** from 0 to 100. Good jobs raise it; broken gnomes, missed
  leaves, and bills lower it.
- **Referrals.** A client at 60 or more relationship refers a neighbor: you get a
  text, and the neighbor becomes a client. Every neighborhood after the first also
  needs its rank. That's how the town opens up: rank **and** people, like Schedule
  I's regions.
- **Requests.** Each morning every client whose yard has grown back enough may
  text a job. You accept from the phone. Accepted jobs show on the board at Homie
  Depot and Chefty can drive to any of them.
- **The mess.** Leaves come back with the days since you were last there:
  `TOWN_REGROW_PER_DAY` of a full yard per day, up to a full yard. A client you
  visit every day pays less per visit; one you leave for a week is a mountain.
- The legacy world draws each job's yard in one lot zone with its street around
  it; the house, its layout, its homeowner, and its neighbors are the same every
  visit.
- **The town loop** (Gutterford, `--town-map`, the default from driving chunk H):
  pick a job (the board, or Take job on a text; the morning's first request is
  picked already) and the yard is there at the client's real house, with a
  beacon over its curb. Drive Chefty there (or let a hired hand drive), park in
  the chalk box, work, get paid. The yard stays until the crew is 90 m away or
  takes the next job, so jobs chain straight from the truck; nobody is driven
  home. Drive back to Homie Depot to shop or sleep; a Chefty left out at bedtime
  gets towed home by Marty for $20. Drive time is in-game time: a trip to Maple
  Row is about 45 s, about 45 in-game minutes.
- **perk:chefty_tuneup** (Hedge Hog IV) gives Chefty +8% top speed.

## 4. The phone

Tab takes out the phone, held in your hand in first person. Apps:

- **Texts:** job requests (accept or decline), referrals, the rival, the clerk.
- **Clients:** everyone you work for, with their relationship, standards,
  favorite work, and the days since their last job.
- **Map:** the neighborhoods, which are open, and what each one needs to open.
- **Crew:** Pay a crewmate ($20 or $100 to anyone in the session, nearest
  first; the bill flies across if they're close), then rank, XP to the next
  tier, banked and pending XP, what the next tier unlocks, and the hired hands.
- **Orders** (app id `deliveries`, built in shops chunk 8; opens at Mulch Mule
  II): Homie Depot's supplies and tools from anywhere, price + $15 + 10%,
  landing two clock hours later (9 AM if ordered after closing) on the back
  room's pallet: crates for supplies, the tools themselves in front of the cage.
  Three orders on the way at most.
- **Closet** (shops chunk 7): the hats and shirts you own, with Wear.

Later apps: Hires (today inside Crew), Properties.

## 5. After the spine (step 4 of the plan)

Built 2026-11-01: hiring (`net/crew/hires.gd`, `npcs/crew_hand.gd`), the rival
(in `net/town/town.gd`), and seasons (`core/seasons.gd`, a global foliage tint in
`props/stylized.gd`). Built 2026-11-02: each neighborhood's own look (the data in
`levels/town/hood_styles.gd`; the house, parcel, street and block builders in
`levels/town/`), and the seasons change that look (snow, blossoms, bare trees,
season decor on every house, the job's too), checked by `--art-test`. Not built
yet: properties and winter's own work.

- **Hiring.** At Turf Boss, crew hands can be hired from the job board. They come
  along on Chefty and rake, bag, and haul (the bot that already rakes is their
  start). They cost a signing fee and a daily wage. Players keep the chaos jobs.
- **Properties.** The back room, then a rented garage, a barn, a warehouse. Each
  holds more cots, more hires, a tool wall, and a second truck later.
- **The rival.** A franchise lawn company, **TurfMasters™**, moves into town at
  Mulch Mule. They poach clients, put up yard signs, and send their crew to
  sabotage yours. Pulling their signs, winning clients back, and brawling their
  crew pushes them out of a neighborhood.
- **Seasons.** Autumn is leaves. Winter brings snow to shovel, roofs to clear,
  and lights to hang. Spring brings weeds and planting. Summer brings mowing and
  pools. A season lasts `SEASON_DAYS` days. Seasons are the endless loop: the
  town keeps needing different work, and each season brings its own tools.

## Numbers to start from

All in `core/constants.gd` under "Spine". They are first guesses to tune in play.

## What we took from Schedule I, and what we didn't

Took: a day clock that ends in sleep, XP banked at sleep, flat XP per action, rank
tiers that each unlock something, regions gated by rank and relationships,
referrals, clients with standards and budgets, a phone for jobs and contacts,
hands-on work, low-cost failure, co-op role splitting.

Didn't take: the 4 AM freeze applied to only the player, empty late ranks,
micromanaging deliveries, money that stops mattering. Sinks (cosmetics, truck
upgrades, properties) come before the money gets silly.
