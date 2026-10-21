# Fun and replayability plan

Written 2026-10-21 after Taylan asked for every job to be played and judged for
funny factor, and for a path to 8 to 10 hours of play. This is an agent's read,
not the workbook: the design decisions it needs are listed at the end for the
developers. Everything else is proposed build work.

Built since (2026-10-21): heat, throwing at the NICE BOYS, diving into piles,
the runaway mower, the ladder knock-down, and paint and water on people.

## How this was played

Every task was run end to end through the automated tests (`--job-test`,
`--work-test`, `--water-test`, `--mower-test`, `--throw-test`, `--bonk-test`,
`--board-test`) with screenshots every few seconds in first person, plus the
`--tour` close-ups and overhead shots of small, regular, and big yards. That
shows what happens and what it looks like. It can't judge how a stroke feels in
the hand, whether a sound lands, or whether a joke is funny the fifth time. Those
need a person, and the notes below say where.

## What the game is right now, in numbers

- One loop: board Chefty at Homie Depot, ride to a generated yard, rake plus two
  or three tasks (three or four on a big yard), get paid by the homeowner's mood,
  ride back, shop. A job is roughly 6 to 12 minutes with two to four people.
- 11 tasks (rake, litter, weeds, mow, gutters, windows, driveway, hedges, fence,
  roof, pool), 7 tools, 2 upgrades. Every tool and upgrade together costs about
  $1,220. A fully raked yard alone pays several hundred dollars.
- So the whole shop is bought in 3 to 5 jobs. After that nothing new is for
  sale, nothing new shows up, and the only variable is the yard's layout.
- The NICE BOYS run event is the game's identity and the thinnest system in it:
  one trigger rule, one chase, hide spots, the van, Border Return.

Honest estimate of content today: 2 to 3 hours before it's the same evening
again. The target is 8 to 10. The gap is not "more tasks"; it's the lack of a
progression ladder and of pressure that changes how you play.

## Per-job notes: what's funny, what's flat, what to do

| Job | Funny now | Flat | Do |
| --- | --- | --- | --- |
| Rake and bag | Bare-hands raking; bag value popups; tossing bags into Chefty | The pile is invisible as a thing: you can't tell a good pile from a bad one, and raking the whole yard is a grind with no payoff curve | Piles become objects: a big pile shows its value, you can **dive into a pile to hide** from the NICE BOYS (and get raked out), a bag from a huge pile pays a visible bonus, and a full truck bed is a visible mountain |
| Leaf blower | Scatters leaves fast | It's a bigger rake; nothing it does is a joke | Blowing at a person shoves them and knocks their hat off; blowing a pile at the homeowner ruins the mood; the blower's recoil pushes you backward on ice/leaves; **blowing at the NICE BOYS pushes them back** (counterplay) |
| Mower | Run-overs: confetti, flung cans, cut hose, the gnome, feet | Nothing after you've seen each run-over once | A **runaway mower** when you let go while it's running (it drives off and mows whatever's ahead, including the neighbor's lawn, which is a complaint); mowing a stripe pattern pays a style bonus |
| Ladder, gutters, roof | Falling off: bounce, knockout, limp | Gutters are a click-and-wait | A thrown object (or a mower bump) **knocks the ladder down** while someone's up it: they're stranded on the roof until someone sets it back; jumping off the roof into a big pile is a safe landing; a bird's nest in a gutter section |
| Hose and windows | Hooking up, the water bill, the hydrant launch, the snap and whip | Washing is aim-and-hold | Spraying a player makes them slip for a second; spraying a pedestrian makes them chase you; spraying the homeowner drops the mood; water through an open window is a bill |
| Pressure washer | Running dry and refilling | Stains are abstract | Wash the sidewalk chalk off (the kids' drawings: a mood hit if the homeowner sees); the washer knocks shoes off at close range |
| Hedge trimmer | The buzz | Trimming is hold-and-wait; nothing happens | Trim shapes: a hedge can be cut into a gnome or a duck for a bonus; trimming near a person shaves their hair or hat off |
| Paint roller | Dipping and running dry | Same | Paint sticks to people (a painted player is white until hosed); painting over a window is a bill; the gnome can be painted |
| Litter and weeds | The scratch gesture | Filler | One weed in every bed is a **monster root** that yanks you around; one can has a raccoon in it that chases the picker |
| Pool | New; scooping | Nothing yet | Fall in: soaked and slow, leaves stick to you; underwater you're invisible to the NICE BOYS while your breath holds; a thrown bag in the pool is a bill |
| Homeowner | The new lines; stars | They stand still until you talk | They watch from a window and react live (a thumbs up, a frown, a shout when something breaks); they come out when the mower hits the gnome |
| Throws and bonks | Weight tiers; knockouts | Only players and pedestrians react | **Throw things at the NICE BOYS** to stun them (the one counterplay that's a joke); bags thrown into Chefty from far away pay a trick-shot bonus |
| NICE BOYS | The warning, the chase, the van, Border Return | Nothing you did caused it; nothing you do changes it except hiding | See Heat below. Also: decoys (a gnome in your shirt), disguises (a homeowner's hat from a clothesline), and being carried off in a pile of your friends |

The column "Do" is build work with no design decisions in it, except the
NICE BOYS row (see decisions).

## What gets this to 8 to 10 hours

Ranked by hours of play per hour of work. Each one multiplies the jobs that
already exist instead of adding one more task.

1. **Heat.** Noise (mower, blower, shouting, the hydrant), damage (bills), and
   bonked pedestrians raise the crew's heat; heat sets the run-event chance and
   how many NICE BOYS come. Heat cools over jobs. Big yards pay more and make
   more noise, so the money is where the danger is. This turns every tool into
   a risk and makes the NICE BOYS *your fault*, which is funnier. Built on the
   director's existing rules. About a day of work.
2. **Job modifiers on the board.** Each offer rolls zero to two: Rush (a timer),
   Windy (gusts move piles), Night (flashlights, the NICE BOYS have lights),
   HOA inspection (pays double, nothing under 100%), Homeowner home (quiet
   hours: noise is a mood hit), Rain (heavy leaves, slips), Dog (a loose dog
   steals bags). Each is a flag the generator and the sim read. Two days.
3. **Neighborhood tiers, unlocked by stars.** Suburb (now) → cul-de-sac with an
   HOA → the hill (mansions, pools, fountains, hedges to sculpt) → downtown lots
   (parking lots, bus stops, mostly litter and power washing, lots of
   pedestrians) → the estate. Each tier is new dressing, a new task mix, bigger
   pay, and more heat. The generator already does most of this with parameters.
   Three to four days. Names are a design decision (placeholders until then).
4. **Tool tiers and bigger money sinks.** Three tiers per tool, the third one
   absurd (a blower that lifts you, a mower you ride, a hose that reaches the
   roof). Chefty upgrades: a bigger bed, a trailer, a horn that scatters
   pedestrians. Total shop around $6,000 to $8,000, so the economy lasts 30 to
   40 jobs. Two days, mostly numbers and models.
5. **A season with an ending.** The campaign is one autumn: N days, two or
   three jobs a day, the board shows the date, a final tally. This is the
   8-to-10-hour shape. The ending is a design decision.
6. **Daily seeded yard and a leaderboard** (best pay, best stars, fastest
   clear) for after the season. One day; Steam leaderboards later.
7. **Cosmetics** bought with stars: hats, shirts, truck paint. For friends to
   laugh at. Half a day.

Rough total: two to three weeks of agent work for 1 through 4, which is where
the hours come from. 5 through 7 are the shape and the tail.

## Order

Heat first (one day, changes every job), then modifiers (every job different),
then neighborhood tiers (new places to be), then tool tiers (something to want),
then the season. The per-job "Do" items get folded in alongside, biggest laughs
first: piles you can hide in, throwing at the NICE BOYS, the runaway mower, the
ladder knock-down, paint and water on people.

## Decisions needed from the developers

- **The ending.** What does a crew that makes it through the season get? This is
  the win condition and the campaign's length (DEC-003 says 5 to 10 hours).
- **How far the NICE BOYS joke goes.** Stunning them with a thrown gnome, decoys,
  and disguises are proposed above. The workbook owns their identity and tone
  (GV-07, GV-11, DEC-015).
- **Neighborhood names and the homeowner cast.** Placeholders until then.
- **Whether the crew can hire help** (bots that work, for solo play). Bots only
  rake today.
