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

### Houses and the kit

- **Architecture goes through HouseKit** (`props/house_kit.gd`): `box`, `prism` (a gable along local z, like PrismMesh), `hip`, `cylinder` (with `top_radius` and `turn`), `window`, `glow`, then `commit(parent, name)` makes one MeshInstance3D per material, painted by the surface shader. A shape's last argument is a style dict (`params`, `accent`, `snow`); surface `"glass"` is window glass. Set `kit.frame` to build a part in its own frame. Never build a house from one MeshInstance3D per box again.
- **Houses come from `HouseBuilder.build(parent, at, req)`** (`levels/town/house_builder.gd`) in one of the archetypes in `levels/town/house_archetypes.gd`, facing +Z with the origin at the footprint's ground center. The returned `House` carries HouseSpec metas (windows, the climbable roof, gutters, solids, roof blockers, porch depth, door, spigot, eaves, footprint, triangles): hang gameplay on those, never on the archetype. Anything new that stands on the main roof or reaches its eaves (a dormer, a cross-gable, a hood, a chimney) is recorded as a roof blocker (`_blocker`, or `"blocker": true` on a `_gable`), and gutters and eaves split around it.
- **Footprint contract:** everything within x +-(width/2 + 0.6) and z from -depth/2 - 0.7 to depth/2 + 2.6 (`Constants.ART_HOUSE_*_REACH`), and every job archetype's main roof is a climbable gable along x. Budget: `Constants.ART_HOUSE_MAX_TRIANGLES` (6000).
- **A neighborhood's look is data** in `levels/town/hood_styles.gd`: which archetypes, palettes with their surfaces, fences, trees, ground, street, props, set pieces, and signs. Add to the data before adding code.
- Check new archetypes with `godot --headless --path . --script res://tools/mesh_check.gd` (face orientation per shape, footprint, spec metas, gutter and eave clearance, budget for every archetype at the smallest and largest yard widths) and look at them in the studio.

### Surfaces (props/surfaces.gd)

- Say what a mesh is made of with `LowPoly.paint(node, surface, params, accent)`; `levels/shared_look.gd` paints it from the mesh metas `surface`, `surface_base`, `surface_params` (Vector4) and `surface_accent` (Color). Patterns are measured in meters in the mesh's own space: walls use the vertical plane, floors and roofs use x and z.
- Patterns: plain, grass, asphalt, concrete, brick, siding, shingles, planks, bark, fabric, metal, dirt, foliage, skin, stucco, stone (fieldstone; `params.x` 1 = cut ashlar), roof_tiles (clay barrel rows), corrugated (vertical ribs and rust streaks, walls or roofs), shakes (cedar), board_batten, gravel, pavers (`params.x` 1 = herringbone), lawn_stripes (`params.x` = contrast), cinderblock, tile_floor (polished), road.
- **Road markings are painted, not modeled.** The `road` pattern is asphalt plus lines on the top face, in local space (along = local x, across = local z). `params`: x = line style, y = half the road's width, z = dash length, w = dash period (0 = twice the dash). Styles (`Surfaces.ROAD_LINES`): 0 none, 1 dashed double yellow, 2 white edges, 3 both, 4 parking stalls every 3 m, 5 an intersection patch with crosswalk bars along each edge (y = half the patch, z = band depth), 6 single dashed yellow (country roads). `Surfaces.road_params(style, half_width, dash, period)` builds the Vector4. A whole street is one mesh.
- Lawns: `params.z` on grass or lawn_stripes is a flower floor that stays all year (Dandelion Acres).

### Seasons in the art

- `Seasons.apply_look(day)` runs on every peer and sets three shader globals: `season_foliage` (the old crown and grass tint), `season_snow` (0.85 in winter) and `season_bloom` (0.8 in spring, 0.15 in summer). Declare any new global in `project.godot` `[shader_globals]` in the same commit as the shader that reads it, or every material fails to compile.
- Every surface (props/surfaces.gd) gets snow on faces that point up, in soft drifts; asphalt, roads and gravel only get a grey slush; skin and tile_floor never do. Lawns get flower dots from the bloom.
- **Indoors opts out.** Surfaces snow is on by default and turned down per mesh: `Surfaces.material(pattern, color, accent, params, snow)` (0-1, default 1), set from the mesh meta `surface_snow` or `LowPoly.paint(node, surface, params, accent, snow)`. Pass 0 for anything under a roof (the Homie Depot lobby, garage floors, porches).
- Vertex-color meshes (`props/stylized.gd`) only get snow when their material opts in: option `snow` (0-1, default 0), so characters, the first-person arms and held things never turn white. Nothing opts in yet: YardModels' fences, hedges, sheds and cars stay clear until a later art chunk passes `snow: 1.0` for its outdoor kinds. Option `seasonal: false` stops the foliage tint for meshes that are built per season (tree crowns).
- When the season changes (and once at start), every node in group `seasonal` gets `apply_season(season)` to rebuild or swap itself. `Seasons.current()` is the season showing; `Seasons.first_day_of(season)` is a day in it.

### The studio

- `Godot --path . res://tools/studio/studio.tscn -- --subject=<name> --out=build/art/<name>.png`, with the windowed (or console, not headless) build, since the dummy renderer compiles no shaders. Grep its output for `SHADER ERROR`.
- Options: `--season=0..3` (autumn, winter, spring, summer; set before the subject is built), `--hood=<id>`, `--size=0..2`, `--seed=N`, `--archetype=<id>` for the neighborhood subjects, and any `--key=value` a subject reads.
- Subjects: trees, tree (`--kind --crown --variant`), characters, character, props, small_props, truck, van, surfaces (every pattern as a labeled cube, ground swatches, and a road strip per line style; render it in all four seasons after touching the shader), houses (every archetype in a labeled lineup, each in a palette from a neighborhood that builds it) and house (one: `--archetype`, else the first of `--hood`'s). Both take `--width=min|max|<m>`, `--depth=<m>`, `--stories=1|2`, `--detail=far`, `--seed`, `--size`. Render houses at `--width=min` and `--width=max`, autumn and winter, after touching an archetype.
- A subject picks its own camera by setting meta `views` on its root: an Array of `{from, at, fov}`, replacing the default four views in order.

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

## Icons

Every UI icon is a committed PNG in `assets/icons/<id>.png`, generated from the game's own code models and code-drawn shapes by `tools/studio/icon_studio.gd`. Never hand-edit one: change its recipe and regenerate it. `ui/icons.gd` is the only loader (`texture`, `rect`, `row`, `bbcode`, `rich`, `plain` and the `for_*` id helpers); a missing icon comes back as null or an empty spacer, never an error.

- **Sizes.** 256 px square for 3D items, tools, upgrades, task badges and rank badges; 128 px for flat icons; keycaps 64 px tall (128 wide for Tab, Esc, Space and Shift). Nothing is ever larger than 256 px on a side (`Icons.MAX_PX`).
- **Camera and light.** The camera looks along (0.75, 0.55, 1.0) toward the subject (front-right, a little above), FOV 30, framed to the corners of each of the subject's meshes (not one world box, which would frame a diagonal tool far too loosely) with 8% padding (3% inside a badge's emblem area). Long, thin tools (ladder, hedge trimmer, paint roller, leaf blower) also carry a `roll` that turns the camera about its view axis so they lie corner to corner: a tool icon is used at 16 to 20 px, and a long axis laid flat across the square shrinks to a smear there. Models face -Z, so a recipe's `yaw` of about 180 shows the front. One warm key light (`SharedLook.SUN_COLOR`, rotation (-40, -30, 0), energy 1.25), a cool fill from the other side (Color(0.75, 0.85, 1.0), 0.35), flat warm ambient light (0.55), filmic tonemap at exposure 1.05. No sky, fog, SSAO, glow or shadows. The season globals are set to autumn first.
- **Sticker finish.** 3D renders at 2x and flat drawing at 4x, then a GPU pass composites the layers (badge disc or shield, the 3D render, the upgrade sticker) and dilates the alpha into an ink outline (Color(0.17, 0.14, 0.11), size / 85: 3 px at 256) with a drop shadow (down size / 64, 25% alpha), and the result is shrunk with Lanczos. A badge's 3D vignette also gets its own ink ring (0.8 of the outline) so it sits on the disc like a sticker; The Lawnfather's ring is gold.
- **Generate.** `Godot --path . res://tools/studio/icon_studio.tscn -- [--only=id1,id2] [--out=assets/icons] [--sheet=build/art/icons_sheet.png]`, then `Godot --headless --path . --import` once. It needs a window (it can't run headless or in CI) and forces each draw, so a covered window is fine. Use `--only` when changing one icon, so GPU or driver differences never churn the others. A new PNG gets a minimal `.import` sidecar (mipmaps on, detect 3D off, no uid) and `--import` fills in the uid; commit both.
- **Judge it.** `--sheet` writes every icon at 96 px and 20 px with its id, on paper and on a dark panel. Read the PNG and check outline consistency, legibility at 20 px on both halves, clipped silhouettes and dark fringes.
- **Add an icon.** Put the id in `ui/icons.gd` `IDS` (following the naming rules there) and a recipe with the same key in `tools/studio/icon_recipes.gd` `RECIPES` (a builder for 3D, a draw func for flat), run the generator with `--only=<id>`, import, look at the sheet, commit the PNG and its `.import`.
- **In the game.** Shop, phone, HUD and prompt screenshots: `Godot --path . -- --host --no-steam --rank=40 --open-shop --screenshot=build/shots/icons_shop --screenshot-every=2 --run-seconds=6` (likewise `--open-board`, `--open-phone=crew|map|texts`, `--end-day-at=3`, and `--start-zone=lot --all-tasks --job-seed=777` for the lot HUD), once the UI chunks wire the icons in.

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
- Every sound id is registered in `audio/sound_bank.gd` (its variants, bus, gap, length limit, and volume trim). `--audio-test` checks that each id's files exist and load, and scans the code for sound ids and `res://assets/audio/` paths that aren't registered or don't exist. A new sound is a recipe in `tools/make_sfx.py` or `tools/make_loops.py` plus a bank entry.
- Gameplay sounds are positional (`Sfx.play_at`, 60 m reach); only interface sounds and the HUD's cues are 2D (`Sfx.play`).
- Musical guardrail: no Latin-American or regional genre signifiers in any cue (no mariachi trumpets, bossa, salsa, cumbia, ranchera, or guiro- or maraca-led grooves). Jokes in sound punch up at work, systems, and bureaucracy.
