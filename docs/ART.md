# Art direction (starting point)

Consistent and funny matters more than pretty. Most of our art will be AI-generated or pulled from free packs, and assets from different sources look like they came from different games unless we hold them to the same rules. This file is those rules. Expect it to change after the first playtest.

## Style

- Low poly with flat colors or very simple textures, drawn from one limited palette. The palette gets decided in M6 and saved as `assets/palette.png`.
- Readable silhouettes beat detail. If something is funny, make sure it reads from 20 meters away.
- Characters are simple and a bit goofy. Physical comedy (wobbly ragdolls, exaggerated stumbles) does more work than facial detail.

## How models are made right now

- Models are built in code, not imported: `props/mesh_kit.gd` makes lumpy blobs, rounded boxes, bent tubes, cones, wheels, and leaf cards, merged into one mesh with shading baked into vertex colors, drawn by `props/stylized.gd`. Buildings and ground keep the procedural surface shader (`props/surfaces.gd`).
- Look at a model before shipping it: `Godot --path . res://tools/studio/studio.tscn -- --subject=trees --out=build/art/trees.png` renders four angles under the game's light. Add a subject in `tools/studio/studio.gd` for anything new.
- Shapes are soft and chunky: rounded edges, lumps that only push outward on hair and hedges, no part floating loose or poking through another. Faces have eyes, brows, and mouths flush with the head.

## Game-specific notes

- **The store is Homie Depot.** Signage, the store zone, and any store UI use that name.
- **Trucks.** Any truck model uses the Chefty logo. Do not invent a second truck brand.
- **Leaves are the star.** They are rendered in bulk from the leaf field, so leaf art means a handful of leaf meshes or cards with color and size variation, not thousands of unique assets. A full lot should read as overwhelming from the truck, and a raked strip should read as satisfying.
- **The enforcement crew is fictional.** Its look, name, and insignia are open design questions. Until they are decided, use clearly placeholder visuals, and never use a real agency's name, logo, insignia, or lettering on uniforms or vehicles.
- **The van has to be countable.** Players must be able to count the captured players inside it at a glance, so plan for windows, an open side door, or an exaggerated cutaway.

## Technical rules

- Scale is 1 unit = 1 meter. A player is about 1.8 meters tall.
- Y is up. Models face -Z, which is Godot's forward direction. The origin sits at the bottom center.
- Models are `.glb`. Short sound effects are `.wav`, and music and ambience are `.ogg`. Textures are `.png`, usually 256 px or smaller, never above 1024 px.
- Budgets: props under 2,000 triangles, characters under 5,000.
- Strip embedded cameras and lights from imported models.

## Sources

- CC0 packs such as Kenney and Quaternius are the first choice for filler.
- Mixamo for character rigging and animation.
- AI image-to-3D or text-to-3D generators for specific props. Generated models nearly always need decimating to the triangle budget, rescaling, and recoloring to the palette before they go in.

## Logging

Every third-party or AI-generated asset gets a row in `assets/LICENSES.md` when it is added: file, source, license, whether it was AI-generated, and which tool made it. This matters for two reasons. We need to honor licenses, and Steam's content survey asks developers to disclose AI-generated content that players see or hear when the game is submitted. AI tools used only during development, such as coding assistants, are not the focus of that disclosure. The log is what we will fill the survey out from, so keep it current.

## Unifying the look (M6)

The planned approach is to render 3D at a reduced internal resolution and apply one shared post-process (for example posterization plus an outline) over everything, along with one shared flat or toon material for most surfaces. A strong shared filter hides a lot of mismatched or rough assets. Try a few variations on lot 1 during M6 and record the winner in `DECISIONS.md`.

## Folders

```
assets/
  models/<category>/      props, characters, environment
  textures/
  materials/
  audio/sfx/
  audio/music/
  fonts/
  LICENSES.md
```

## Audio

Goofy, not realistic. The reference is Schedule I: bouncy, cartoony, a little dumb. Taylan set this on 2026-10-19 after hearing realistic synthesized sounds and not liking any of them.

- Sound effects are cartoon sounds: pomfs, swooshes, boings, honks, slide whistles, brass stabs. Exaggerate them so they read as jokes, not as foley.
- Characters never speak real words. They make short silly noises (ah?, oof, eh?, huh?, hup) and babble gibberish when talking, like the "ewewewew" of Animal Crossing. Each character's pitch differs a little so they can be told apart.
- Every sound is synthesized by `tools/make_sfx.py`, so all audio is a project original with nothing to license or disclose. Change a sound by changing its recipe there and re-running it.
- Proximity voice chat between real players is untouched: that is real people talking.
