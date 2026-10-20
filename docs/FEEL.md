# Feel reference: Schedule I

Taylan, 2026-10-19: Schedule I is "the entire way I want this game to function" in how it feels: the graphics, the sounds, the art style, how characters play, and how characters deal with shops. We are not copying anything from it: no names, characters, places, art, sounds, or systems lifted as they are. This file records what makes it feel the way it does, and how each piece could carry over to Leaf Me Alone.

Everything under "Observed" comes from Schedule I's Steam page and screenshots, its community wiki, reviews, and player discussions (sources at the end). Nobody here has watched gameplay video through an agent, so play it yourself before trusting any detail. Everything under "For us" is a proposal. Only Confirmed items in `GAME.md` are canon; anything here that changes design goes into the workbook first.

## Why people say it's fun

Observed:
- A tight loop of short satisfying tasks repeated, with steady growth from nothing to an empire.
- It never takes itself seriously. Reviews call the art and writing silly, and the silliness against a "serious" premise is the joke.
- Co-op with friends is where most of the fun is. Solo is called thin.
- It looks crude at first glance and charming after an hour, because the style is consistent.
- Complaints: NPCs walking into walls, and repetitive micromanagement later on.

For us: the same shape already fits. Impossible leaf jobs are the loop, the crew is the comic threat, and co-op is the point. Protect the consistency of the style above polish, and keep the crew from looking dumb in the wrong way (we already bake navigation from the lot's real geometry).

## Look

Observed in the screenshots:
- Low-poly, but **lit**: smooth shading, soft shadows, warm sun and lamp light, colored light sources (grow lights, headlights, neon), haze over distant mountains, and a day and night cycle.
- Simple textures on big shapes: brick, wood planks, concrete, painted metal.
- Characters are cartoon people: big round heads, big eyes, simple faces, thin limbs, plain clothes in solid colors.
- Props are chunky and slightly oversized so they read instantly: cash bundles, jars, tables, an old computer.

For us:
- Switch the shared look from flat unshaded color to lit low-poly: smooth shading, soft shadows, a warm autumn sun low in the sky, ambient occlusion, a little glow. Keep the palette and the outline, but let light do the work. This reverses the 2026-10-13 and 2026-10-18 look decisions, so record it in `DECISIONS.md` when it's done.
- Replace the capsule players with cartoon characters: a big head with big eyes, a small body, and goofy procedural motion (bounce when walking, arms swinging, a wobble on landing). Clothing color can tell players apart.
- Leaves stay the star and get the most visual love.
- Day and night (golden hour on the lot, lit store at night) would sell the mood. It touches pacing, so it's a design question for the workbook first.

## Sound

Observed:
- No voice acting. NPCs mumble in an undertone, compared by players to Animal Crossing, and some lines are almost understandable, which players love (the pawn shop owner's mumble sounds like "alright partner").
- No source documents the sound effects in detail.

For us (already decided by Taylan, see `ART.md`, "Audio"):
- Characters make silly noises (ah?, oof, eh?, huh?, hup) and babble gibberish. The best babble is almost words.
- Sound effects are goofy and cartoony.
- Real proximity voice between players stays as it is.

## How characters play

Observed:
- First person. Hands-on actions instead of menus: you pour, mix, package, and place things yourself, with close-up "station" views for the fiddly ones.
- A hotbar of carried items along the bottom of the screen, and small floating prompts next to people and objects for what you can do.
- Movement is part of the fun, for example skateboarding across town.
- Bought things are physical objects: you carry them, place them, and arrange them.

For us:
- Show the rake in your hands and make raking a physical motion with a satisfying swoosh and leaf spray. Bags, the wheelbarrow, and tools are things you hold, with a hotbar for what you carry.
- Small world-space prompts ("E  Hide", "E  Talk", "E  Buy") instead of HUD instructions. The current four lines of instructions in the top-left corner go away.
- Tools bought at the store should be objects you pick up and use, not only multipliers.
- A movement toy (a skateboard, a leaf blower you can ride, whatever is funny) is a design idea for the workbook, not something to build unasked.

## How characters deal with shops

Observed:
- Each store has a named owner standing in it. You walk up and talk to them, sometimes with dialogue choices that can have small consequences.
- Stores have opening hours.
- Stock unlocks as your reputation rank goes up.
- Ordering by phone app with a delivery van to a loading dock exists for later in the game.
- Vending and cash machines sit outside stores.

For us:
- Homie Depot gets a clerk standing behind the counter who babbles when you walk up. Pressing E opens a shop window styled like a store catalog with item cards, prices, and what you can afford. Their name and personality are design decisions: use `[CLERK NAME]` until the workbook has one.
- Tools appear on the shelves as physical items you can see before you buy them.
- Opening hours, reputation ranks, and phone ordering all need design decisions first. They'd fit the structure (`Campaign` already gates unlocks), but don't build them unasked.

## Order to build in

Taylan agreed on 2026-10-19. Items 1 to 4 are built: `levels/shared_look.gd`, `player/cartoon_body.gd` (players, crew, and clerk), `ui/interaction_prompt.gd`, `npcs/store_clerk.gd`, and `ui/shop_window.gd`. The rake in your hands and a hotbar are not built yet.

1. Lit look: lighting, shadows, ambient occlusion, warm autumn sun. Cheap, and it changes the feel most.
2. Cartoon characters with goofy procedural motion and their silly voice noises.
3. Interaction prompts in the world and the rake in your hands.
4. The Homie Depot clerk and a catalog-style shop window.
5. Anything that changes design (day and night, opening hours, ranks, phone, movement toys) after it is in the workbook.

## Sources

- [Schedule I on Steam](https://store.steampowered.com/app/3164500/Schedule_I/) (description and screenshots)
- [Schedule 1 Wiki: Hardware Store](https://schedule-1.fandom.com/wiki/Hardware_Store) and [Stores](https://schedule-1.fandom.com/wiki/Stores)
- [Steam discussion on NPC voices](https://steamcommunity.com/app/3164500/discussions/1/599651626189382468)
- [Steam discussion: why is this game so good?](https://steamcommunity.com/app/3164500/discussions/1/599649070605141907/)
- [Lords of Gaming: 6 reasons to play Schedule I](https://lordsofgaming.net/2025/04/6-reasons-why-you-should-play-schedule-i-right-now/)
- [Games.gg: is Schedule I worth playing?](https://games.gg/news/schedule-i-worth-playing-special-customers/)
- [The Gameslayer: loading dock deliveries](https://thegameslayer.com/guides/how-to-unlock-a-loading-dock-get-deliveries-in-schedule-i/)
- [GameGeeker review](https://gamegeeker.com/it/games/schedule-i-3164500/review)
