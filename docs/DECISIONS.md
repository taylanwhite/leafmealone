# Technical decisions

A running log of decisions that shape the architecture, conventions, or tools. Game design decisions live in the workbook's Decisions & Log sheet instead, so the two logs never compete. Add new entries at the bottom. When a decision is reversed, add a new entry that says so instead of editing the old one.

Format: date, the decision, why, what else was considered, and when to revisit.

---

### 2026-10-12: Godot 4.7 with statically typed GDScript

- **Why:** Scripts, scenes, and resources are all text, which lets AI agents read and edit the whole project and keeps Git merges sane. Godot has built-in high-level multiplayer, and GodotSteam covers Steam lobbies, relay, and voice.
- **Considered:** Unity with Netcode for GameObjects and the Facepunch Steam transport (what Lethal Company shipped on), and Unreal (what RV There Yet? was built in). Unity scenes and prefabs merge poorly and Unreal Blueprints are binary, both of which hurt a two-person, agent-driven workflow.
- **Revisit if:** Jolt physics or Godot's multiplayer tooling blocks a core feature we cannot work around.

### 2026-10-12: Develop on macOS, ship on macOS and Windows

- **Why:** Both developers use Macs. Windows is most of the Steam audience for this genre, and Godot exports Windows builds from a Mac with the same export templates.
- **Consequence:** A real Windows PC is needed for cross-play testing from M3 onward. Parallels on Apple Silicon doesn't fully support Direct3D 12, so it isn't a reliable test for Forward+ builds. See `docs/PLATFORMS.md`.
- **Revisit:** Linux and Steam Deck after the first vertical slice.

### 2026-10-12: Listen server with host authority

- **Why:** Co-op with friends needs no cheat protection and no servers to pay for. The host owns shared state, and each player owns their own movement so controls feel instant.
- **Considered:** Dedicated servers (cost and operations for no benefit at this stage) and fully peer-to-peer state (much harder to keep consistent).
- **Revisit if:** We ever want public matchmaking with strangers.

### 2026-10-12: No host migration

- **Why:** It is a large amount of work for a rare case. If the host leaves, the session ends, and the campaign is safe in the host's save.

### 2026-10-12: Steam only, ENet for development

- **Why:** We ship on Steam, and Steam lobbies, invites, and relay solve matchmaking and NAT traversal. ENet on localhost keeps day-to-day testing and the smoke test free of Steam.
- **Considered:** A transport abstraction for other storefronts or console cross-play. Not worth it now.

### 2026-10-12: Steam app ID 480 until the game is registered

- **Why:** We can build and test Steam features before paying the Steam Direct fee. Lobbies are friends-only and tagged with `game_id` because 480 is shared with every other developer testing on it.
- **Revisit:** End of M6.

### 2026-10-12: Up to 8 players, provisional

- **Why:** The design has a truck taking a subset of the players to each job, with four on the truck as the working assumption, which implies more than four players in a session. The player count is still an open design question (OQ-016), so we build and test for up to 8, and `Constants.MAX_PLAYERS` is the only place the number lives.
- **Revisit:** When OQ-016 is decided.

### 2026-10-12: One persistent world with zones

- **Why:** Players are in the store, on a lot, and in Border Return at the same time. Loading one level for everyone can't represent that. Keeping every zone loaded on every peer, spaced about 1,000 m apart, keeps replication simple and makes moving between places a teleport. Distance also keeps proximity voice separate per zone for free.
- **Considered:** Separate physics worlds or sub-scenes per zone. More isolation, much more complexity.
- **Revisit if:** Memory or bandwidth becomes a problem, starting with per-zone synchronizer visibility.

### 2026-10-12: Leaves are a host-owned density grid

- **Why:** Lots hold up to hundreds of thousands of leaf units. A grid of density cells in chunks replicates cheaply, supports both raking into piles and bagging, and renders with MultiMesh. Individual leaf nodes or physics bodies would not scale.
- **Revisit:** After the M2 raking playtest.

### 2026-10-12: Rides are seated, on paths, driven by the shared clock

- **Why:** Letting players walk around inside a moving vehicle is the hardest problem in this genre, and the design doesn't need it. Seats also make the van's visible headcount match the captured roster by construction.

### 2026-10-12: Border Return hazards are deterministic

- **Why:** Hazards as a pure function of seed and server time look identical on every peer, including Apple Silicon and x86, with nothing replicated per frame. The player who gets hit detects it on their own client, so hits feel fair at any ping.

### 2026-10-12: Two autoloads, `Net` and `Campaign`

- **Why:** `Net` owns the session (players, zones, time, transport). `Campaign` owns persistent state (credits, unlocks, job stats, saves). Both are host-authoritative and owned by NET. Gameplay code talks to these two and nothing else in `net/`.

### 2026-10-12: Balance values are generated from the workbook

- **Why:** The workbook's Balance Lab is where tuning happens. `design/export_balance.py` turns it into `core/balance.gd`, with every constant keeping its BAL id, so code and design stay in sync and nobody hand-edits numbers in two places.

### 2026-10-12: Jolt for 3D physics, Forward+ renderer

- **Why:** Jolt is built into Godot and is the more robust choice for physics-heavy comedy. Forward+ is the default renderer and uses Metal on macOS and Vulkan on Windows.
- **Note:** GodotSteam's overlay does not work when running from the editor with Forward+, so test overlay features in exported builds.

### 2026-10-12: Camera is swappable until OQ-001 is decided

- **Why:** First-person versus over-the-shoulder changes how raking and physical comedy read. Building the camera as a swappable rig lets us decide by playing in M2 instead of guessing now.

### 2026-10-12: Two lanes, NET and PLAY

- **Why:** Two developers each running agents in the same files at the same time causes conflicts and inconsistent architecture. Splitting ownership by folder keeps the agents apart, and `HANDOFFS.md` handles cross-lane requests.
- **Assignment:** Taylan owns NET, his brother owns PLAY. Swap whenever you want, and update `AGENTS.md` and your `local-me.mdc` files when you do.

### 2026-10-12: GodotSteam 4.23.1 GDExtension on the standard Godot 4.7.2 editor

- **Why:** The kit named GodotSteam 4.20. The GDExtension published for Godot 4.4 and newer, including 4.7.2, is 4.23.1. Installed from the Godot 4.7 Asset Store into `addons/godotsteam/`.
- **Check:** A throwaway script run with `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script` printed `Steam=true` and `SteamMultiplayerPeer=true`. The script was deleted. The Godot MCP server is not connected in Cursor yet, so this check used the Godot executable directly.
- **Considered:** GodotSteam's precompiled editor, which bundles the extension. Not needed, because `SteamMultiplayerPeer` loads in the standard editor.
- **Note:** Enabling the editor plugin only turns on GodotSteam's updater dock. The Steam classes load from the GDExtension without that plugin.

### 2026-10-13: First shared look is flat unshaded color snapped to one palette

- **Why:** ART.md asks M6 to try one shared treatment so the store, the lot, and the border read as the same game. The current meshes are boxes, so a toon shader and an outline would not show much. Unshaded materials snapped to `assets/palette.png` keep every surface in the same set of colors.
- **Considered:** Posterization plus an outline in a compositor pass. Worth trying again when real models replace the boxes.
- **Revisit:** After the first friend playtest, if the flat look feels too bare.

### 2026-10-18: Player movement replicates unreliably, rare state reliably

- **Why:** Position, yaw, pitch, and velocity were On Change, which Godot 4.7 sends reliably every frame. One lost packet held up every later update for a resend, longer than `NetSmoother`'s 100 ms buffer, and remote players hitched. They are now Always (unreliable, every 33 ms), and `anim_state` and `equipment_id` are On Change. Made from the NET lane in `player/player.tscn` with Taylan's confirmation.
- **Rule:** Values that change every frame use Always. On Change is for values that change rarely.

### 2026-10-18: ENet's packet throttle stays fully open

- **Why:** ENet drops unreliable packets when round-trip times vary, and with its defaults it recovers over about 20 seconds. Measured on one Mac: a client's throttle toward the host started at 1 of 32, so about 97 percent of movement updates were dropped after joining, and it fell again on any hiccup. Our traffic is about 13 KB/s per client, so congestion dropping buys nothing. `Net` calls `throttle_configure(5000, PACKET_THROTTLE_SCALE, 0)` on every ENet link when it connects. Steam sessions are not affected.
- **Revisit:** If bandwidth per client grows past a few hundred KB/s.

### 2026-10-18: Netcode is tested by bots, not by hand

- **Why:** Checking smoothness and bandwidth by watching two windows does not scale to eight players or to every change. `--bot`, `--measure`, `--sim-lag`, `--sim-loss`, and `--screenshot` (in `net/dev/`) plus `tools/soak.sh` run a whole session unattended and give a verdict, and the `netcode` GitHub workflow runs it on Linux and Windows for every push. People still judge feel and fun by playing.
- **Considered:** `tools/lag.sh` (dummynet) alone. It needs `sudo` and only works on macOS, so it stays for hand tests and the flags cover automation.
- **First 8-player result:** 150 ms and 2 percent loss with a late joiner: about 160 ms measured round trip, host about 70 KB/s in and out, each client about 13 KB/s each way, remote players hitching on 0.2 to 0.3 percent of updates.

### 2026-10-18: Voice is tested with a synthetic tone over ENet

- **Why:** Real voice needs Steam on two machines and a person talking, so it can't run in CI or in a bot soak. `--voice-test` replaces the microphone with a quiet tone in talk bursts, sent as raw 16-bit PCM over the same RPC, buffer, and AudioStreamPlayer3D path as Steam voice. Only Steam capture and `decompressVoice` are left out, and those still need a hand test in exported builds on both platforms. Players on ENet still get no voice.
- **Also:** GodotSteam 4.23.1 has no `SteamVoice` node, so voice uses the raw functions through `net/steam_bridge.gd`. Voice decodes at 16 kHz to keep the per-sample loop cheap with eight players.
- **First 8-player result:** 150 ms and 2 percent loss, real macOS audio muted: every peer heard all seven others, about 159 ms between two clients through the host, 3 to 4 percent of packets lost across two lossy hops, and playback running dry about 1.5 points more often than packets were lost.

### 2026-10-18: Taylan works both lanes for now

- **Why:** Taylan's brother isn't working on the game at the moment, so PLAY tasks would otherwise wait indefinitely. Taylan owns NET and PLAY until his brother returns. Commits keep the prefix of the folder they touch, so the history still reads by lane, and `HANDOFFS.md` is only for requests while both are active.
- **Revisit:** When his brother comes back. Hand PLAY back by updating `AGENTS.md` and each `local-me.mdc`.

### 2026-10-18: Shared look is flat palette color plus a depth outline and distance fog

- **Why:** The first art pass replaced gray boxes with low-poly primitives built in code (`props/low_poly.gd`, `levels/dressing/`), all snapped to `assets/palette.png`. A full-screen outline pass (`levels/outline_pass.gd`) draws a dark line wherever depth jumps, which keeps silhouettes readable from 20 m as `ART.md` asks, and depth fog fades the scenery into the sky so the ground never ends in a hard line. No downloaded or AI-generated assets are involved yet.
- **Considered:** Posterization in a compositor effect. Not needed while every surface is already a flat palette color.
- **Also:** Leaves had not been drawn since the renderer started asking the field for its chunks before the field was ready. They render again, in palette colors with small shade and size variation, and a full lot now reads as a carpet.
- **Revisit:** After the first friend playtest, and when real models arrive.

### 2026-10-19: Shared look is lit low-poly in late-afternoon light

- **Why:** Taylan wants the game to feel like Schedule I (`docs/FEEL.md`), which is lit, not flat. `levels/shared_look.gd` (was `flat_look.gd`) now gives every surface real shading, a low warm sun with soft shadows, a procedural sky, sky ambient light, ambient occlusion, a little glow, and warm depth fog. The outline stays, lighter.
- **Reverses:** the 2026-10-13 and 2026-10-18 flat-look entries. Colors are no longer snapped to the 12-swatch palette, which made everything samey. The palette is now a guide for picking colors.

### 2026-10-19: Surfaces are painted by one procedural shader, not image textures

- **Why:** Everything was untextured and read as plain. `props/surfaces.gd` paints brick, siding, shingles, planks, asphalt, concrete, grass, bark, fabric, painted metal, dirt, foliage, and skin straight onto any mesh, measured in meters in the mesh's own space, with every brick, board, and shingle varying a little. No image files to make, license, or disclose, sharp at any distance, and one material per surface and color. Meshes say what they are with `set_meta("surface", ...)` or `LowPoly.paint()`; scene-built meshes are mapped by node name in `levels/shared_look.gd`.
- **Considered:** Generated PNG tiles. More work to keep consistent and they blur up close.
- **Revisit:** If hand-made hero models arrive with their own textures, they opt out with `keep_material`.

### 2026-10-19: Physics interpolation is on, and moving things move on physics ticks

- **Why:** Rendering at 120 fps with 60 physics ticks made every other frame stand still. Measured with `--walk-straight`, camera judder (0 is perfectly even) went from 1.93 to 0.12 with `physics/common/physics_interpolation` on.
- **Rules that come with it:** Anything that moves in the world moves in `_physics_process` (the player, rides, seated riders, the shoulder camera), so interpolation smooths it all together. Every teleport calls `reset_physics_interpolation()`, or it smears across the map for a frame.
- **Also:** Client clocks slew toward new estimates at up to 5 percent instead of jumping (`net/clock_sync.gd`), because a ride at ride speed jumped meters with every ping. Riders are placed on their seat on every peer from the ride's rider list instead of through the network smoother's delay. On a client under 150 ms and 2 percent loss, the vehicle's frame-to-frame judder is 0.06 and riders stay within about 1 cm of their seat per frame.

### 2026-10-20: Models are built in code with a mesh kit, and judged in a studio

- **Why:** Taylan called the look half-baked: lollipop trees, box props, paper-square leaves, clipping characters, and a yard floating in a field. Primitive meshes can't get past that. `props/mesh_kit.gd` builds organic low-poly meshes (lumpy blobs with true normals, rounded boxes, tapered bent tubes, cones, wheels, leaf cards) into one mesh with baked shading in the vertex colors, and `props/stylized.gd` draws them with soft wrapped light and wind sway from vertex alpha. Trees, characters, vehicles, yard props, and hiding spots use it (`props/trees.gd`, `player/cartoon_body.gd`, `props/vehicles.gd`, `props/yard_models.gd`). Architecture keeps the procedural surface shader. Still no image files, downloads, or AI-generated assets, so nothing to license or disclose.
- **How we judge art:** `tools/studio/studio.tscn -- --subject=<name> --out=<png>` renders one subject from four angles under the game's own lighting, with the window covered or not. In-game `--screenshot` forces a draw when macOS won't, so shots also work in the background.
- **Also:** The lot sits on a real street (`levels/dressing/neighborhood.gd`) and the store on a street corner, Chefty drives down the street and up the driveway, the pad's dark curb is an invisible wall, the ground is level with the yard, cameras stop at 400 m, and the sky has fog-free clouds.
- **Revisit:** If hand-made or bought models arrive, they replace kit builders one at a time; anything with its own textures opts out of the shared look with `keep_material`.

### 2026-10-20: Pad walls hold people, not items; pedestrians run on the shared clock

- **Why:** Taylan wants to throw things at people, including passersby on the sidewalk outside the yard. The invisible pad walls now sit on physics layer 3 (`Constants.PAD_WALL_LAYER`), which players and the crew mask and props don't, so items sail into the street. The street has ground to land on, and anything that settles outside the pad or falls through the world pops back inside (`net_prop.gd _come_back_in`), so the job's one rake can't be lost.
- **Pedestrians** (`npcs/pedestrian.gd`) are local nodes on every peer, placed by their seed and `Net.server_time()` like the rule for shared visuals says, so they cost no network traffic. The host detects thrown items reaching players or pedestrians and broadcasts one reliable `_rpc_bonk_fx` on the prop; each peer plays the reaction, and only a player's own peer applies the shove and stun. `--bonk-test` covers both, and CI runs it.
- **Revisit:** If pedestrians ever matter to gameplay (blocking, reacting to the crew), they become host-owned and replicated instead.

### 2026-10-20: Job yards are generated from a seed; tasks live in one host-owned node

- **Why:** Taylan wants progression and variety: tools that unlock work, and never the same yard twice. The host picks a job seed and the task list before spawning the lot, and both reach every peer with the spawn (`levels/lots/job_lot.gd`, a spawn-only `MultiplayerSynchronizer`). Every peer then builds the same yard (`levels/lots/lot_generator.gd`): house, trees, hedges, fences, beds, litter, hiding spots, and the leaf density, with colliders, so the crew's navmesh follows. Tests compare a layout hash across peers.
- **Work** is in `net/work/job_tasks.gd`: spots for one-at-a-time work and grids for areas, defined in the same order on every peer and owned by the host after that. Clients call `request_work` while using a tool; the host checks the tool and the distance, applies it, and sends only changed spots and cells. `levels/lots/task_looks.gd` draws it all. `--work-test` with `--all-tools --all-tasks` finishes every task and checks a client agrees; CI runs it.
- **Also:** the crew's navmesh bake is limited to the yard, since the street's ground collider would make it bake hundreds of meters.
- **Revisit:** if more than one lot template is needed (a corner lot, an apartment), add scenes to the lot spawner and let the seed pick one.

### 2026-10-20: Zones have their own play areas; water and ladders are host-checked physics

- **Why:** Taylan wants jobs to make physical sense. The lot's play area (`Constants.PAD_RECTS`) now reaches past the sidewalk into the near lane where Chefty parks; walls, item return, and the edge rescue all read it. Chefty and the van have collision that moves with them.
- **Water:** the hose's source, whether it's spraying, and the washer's tank replicate on the prop. The host snaps an over-stretched hose and runs the whip's knockouts, traces each spray's ballistic arc (`JobTasks.water_arc`) against windows, runs up the spigot bill, and drains the washer. The rope (`props/hose_rope.gd`) and the drops (`props/water_stream.gd`) are local and use the same arc. The hydrant's push is applied by the holder's own peer, like all player movement.
- **Ladders:** a set-up ladder's top replicates; whether someone is up one is worked out from their position, so the host can check gutter work for anyone without new state.
- **Tests:** `--water-test` and `--work-test` cover it; CI runs them.

### 2026-10-20: Job board offers, yard sizes, ratings, and a separate test save

- **Offers:** `levels/job_board.gd` (a node under World) holds the host's job offers. Each offer is a seed plus the tasks and yard size derived from it, and it replicates by RPC, including to late joiners. The job lot is built from the picked offer, and its yard size spawn-syncs on `JobSync` next to the seed and tasks. The pick locks once Chefty is riding or anyone is on the lot. Each loaded yard gets a new node name, so messages still in flight for a swapped-out yard never land on the new one.
- **Ratings:** `Campaign` keeps the homeowners' recent reviews, saves them, and replicates them with the progress RPC.
- **Test save:** timed test runs (`--run-seconds`, and the smoke test) read and write `user://saves/campaign_test_<port>.json`, so tests never change the real crew's cash, progress, or rating. (The port was added on 2026-11-01 so tests can run side by side.)
- **Tests:** `--board-test` runs in CI, and the work test now has 120 seconds, since it outgrew 45.

### 2026-10-21: First person is the camera; your own arms are a local view model

- **Camera:** OQ-001 is closed: first person. The over-the-shoulder camera stays on `toggle_camera` for debugging only.
- **Arms:** `player/first_person_arms.gd` draws the local player's arms as a child of their Head, only for the owning peer and only while the first-person camera is current. Each arm is two bones solved toward a hand target in head space; targets come from what the player holds (grip points per tool model), the rake's stroke, the throw wind-up, climbing, gestures, and knockouts. Nothing here replicates: other peers see the full cartoon body as before.
- **Why not show the body's own arms:** they're posed for a third-person view and swing through the camera; a view model that reaches for the actual tool reads better and is cheap.
- **Crew name:** `[CREW NAME]` placeholders are gone; the text says "the NICE BOYS".

### 2026-10-21: Heat is the run-event trigger; gags are host-checked physics with replicated flags

- **Heat:** `net/run_events/heat.gd` (a node under World) is host-owned and replicated by RPC, throttled to four updates a second. The director rolls every `HEAT_ROLL_SECONDS` once the progress rule is met, with the chance and the cooldown scaled by heat, and spawns `crew_count()` NICE BOYS. OQ-009 is closed by Taylan's decision in docs/FUN.md.
- **Pile hiding and coats** are new replicated player flags (`in_pile`, `coat`, on-change). The host decides both (the leaf field checks the pile; job tasks check who paint and water reach) and tells the owning peer, which sets its own flag, following the host-to-owner pattern. Visuals are local to each peer from the flag.
- **The runaway mower** is the host moving an unheld running mower; **ladder knock-down** clears `ladder_top`, which already meant "not set up" everywhere. **Crew stuns** are a host timer on the crew member, with the same bonk tiers as players.
- **Tint:** the stylized shader gained an `instance uniform` tint, so paint and water on a body cost no new materials.
- **Tests:** `--gag-test` covers all of it with a client; CI runs it.

### 2026-10-21: Player-on-player play goes through one host node

- **Brawl:** `net/components/brawl.gd` (under World, host authority) takes every ask (punch, whack, grab, release, break free), checks reach and state on the host, broadcasts the hit (one call_local RPC: swing on the attacker, bonk on the target, the sound), and tells each owner what they're now doing. `carrying`, `carried_by`, `thrown`, and `winding` are owner-set replicated flags on the player, like the other host-to-owner flags; a carried player positions itself at its carrier each physics tick from the carrier's replicated transform, so nothing new is interpolated.
- **Why one node:** punches and throws involve two players whose movement belongs to two peers; the host is the only place both are known, and one RPC hub keeps the rules in one file.
- **Tests:** `--brawl-test` with a client runs in CI.

### 2026-11-01: Claude Code on Windows is the main developer

- **Why:** Taylan is moving to mostly AI-driven development, on a Windows 11 machine. `CLAUDE.md` holds the Windows tool paths and the test commands; `tools/ci_local.ps1` runs exactly what `netcode.yml` runs, so an agent can get a CI verdict before pushing. Lanes stay as commit prefixes only.
- **Also:** agents now have creative freedom (names, lines, systems) and record what they decide in `docs/GAME.md`. Work happens on branches and is pushed when a task is done.
- **Considered:** keeping the Cursor and MCP setup. It still works for Cursor users and is left in place.

### 2026-11-01: Four players, a persistent town, early access

- **Why:** Taylan's calls. Four matches the truck's seats, so nobody is stranded at the store; `Constants.MAX_PLAYERS` is 4. The town persists like Schedule I's (`docs/SPINE.md`), so homeowners, referrals, and neighborhoods can carry progression. The game ships in early access, so no ending is built yet.

### 2026-11-01: Tests quit when they finish, and run side by side

- **Why:** every test ran out a fixed `--run-seconds` timer even when it finished early, one after another, so the full local suite took about 20 minutes and CI about the same. Waiting that long made agents test less often.
- **How:** each `net/dev/*_test.gd` sets `result["done"] = true` wherever it ends. `net/dev/dev_tools.gd` on the host watches for that, waits a moment for replication to land, pushes the heat once more, writes its report, and tells clients (`_rpc_finish`) to write theirs and quit; then it quits. `--run-seconds` is now only a ceiling for a hung test. Each test port gets its own test save, so `tools/ci_local.ps1` runs several tests at once; the bot soaks run together afterwards on a quiet machine, because they judge smoothness. In CI each OS runs a "features" job and a "soaks" job side by side.
- **Considered:** shortening the timers instead. That only trades speed for flakiness, and the timers would still be wrong whenever a test changes.

### 2026-11-01: CI ports are fixed per test, and the humor guardrail is one checked list

- **Why ports:** `tools/ci_local.ps1` gave each test `7794 + its position` in `$Tests`, so nine features merged in parallel would each have taken 7808 and reshuffled every port after them (critic C1). Now each `$Tests` entry names its `Port`; an entry without one still falls back to its position, so old entries keep their ports. The runner refuses to start when two tests share a port or a test takes a smoke or soak port, and it warns (and `-CheckPorts` fails) when a port differs from the `--port=` of the `netcode.yml` step that runs the same `--<x>-test` flag. `-PortOffset` still shifts every port, explicit ones included. An optional `Extra` key is appended to both the host and the client args, for network conditions such as `--sim-lag=120`; CI puts the same args on both lines of its step.
- **CI ports.** A new test takes the next free port here, sets `Port` in `$Tests`, and uses the same port in `netcode.yml`:

  | Port | Test | Port | Test |
  | --- | --- | --- | --- |
  | 7791 | smoke | 7806 | hire |
  | 7792 | soak (bots) | 7807 | rival |
  | 7793 | event-soak | 7808 | settings |
  | 7794 | job | 7809 | hotbar |
  | 7795 | bonk | 7810 | icons |
  | 7796 | work | 7811 | audio |
  | 7797 | throw | 7812 | cast |
  | 7798 | water | 7813 | art |
  | 7799 | mower | 7814 | shop |
  | 7800 | board | 7815 | drive (`Extra = '--sim-lag=120'`) |
  | 7801 | gag | 7816 | townmap |
  | 7802 | brawl | 7817 | skate |
  | 7803 | day | 7818 | pursuit |
  | 7804 | town | 7819 | balance |
  | 7805 | layout | 7820 | next free |

  `guardrail` (a `--script` run) and `balance-sim` (Python only) have no port. Probe result keys are `<name>_test`.
- **Why one guardrail list:** the art spec's sign check and the cast spec's string audit each had their own regex, and they disagreed (art banned lowercase "ice", which winter needs; cast banned "go back to", which instructions need). `net/dev/guardrail.gd` (`class_name Guardrail`, also preloadable) holds the one `PATTERNS` list; `check(text)` returns printable hits, `sweep(value, path)` walks arrays and dictionaries, `sweep_script(path)` walks a script's constants, and `sweep_source(path)` reads string literals as text for scripts that need the `Net` autoload to load. `self_check()` runs the `SHOULD_HIT` and `SHOULD_PASS` samples. `tools/guardrail_check.gd` runs the self-check and sweeps the text tables headless; it is the `guardrail` step in `ci_local` and `netcode.yml`. What the patterns mean for writing is in `docs/GAME.md`.
- **The guardrail never passes by not looking.** A script in `SOURCES` that doesn't compile (say it starts using an autoload) is a hit of its own, and its literals are swept as text instead; move it to `SOURCE_TEXT` if it only compiles inside the game. A listed file that no longer exists is a hit too, and the summary counts the files actually swept. Spelled-out acronyms are caught with any separator (I.C.E., I-C-E, N I C E). `ci_local` kills the step after 60 s (a script error before `quit()` leaves headless Godot running). In `netcode.yml` the Guardrail step has `continue-on-error` and a 2-minute timeout, and a "Guardrail verdict" step after every feature test fails the job, so a wording hit doesn't skip the netcode results; new feature-test steps go above the verdict.
- **Considered:** a word list without regex (misses "papers, please" and dotted acronyms), and a guardrail dev test inside the game (needs a port and a host, for a check that needs neither).

### 2026-11-01: No economy number is written inline; one table for shop prices

- **What:** the economy numbers that sat inline in `town.gd`, `homeowner.gd`, `job_board.gd`, `lot_generator.gd`, `hires.gd` and `run_events/rules.gd` moved to a `# ---- balance` section of `core/constants.gd` with the same values, and the callers read them from there. `Constants.SHOP_PRICES` holds every price that isn't a base tool (`TOOL_PRICES`): it starts with `rake_tier_1` and `wheelbarrow_tier_1` at 120, replacing `Balance.BASELINE_TIER_1_TOOL_COST` in `Campaign.price_of`, and `shop_window.gd` asks `Campaign.price_of` instead of reading the workbook constant. The shops work (`Catalog.price`) extends the same table.
- **Why:** `tools/balance_sim.py` (gap balance:C) reads the tuning straight out of `constants.gd`, and the engine parity test checks it against the game, so a number the game uses has to be a top-level constant there. The workbook's tier-1 tool cost described the old 8-lot model; the upgrades are spine prices now.
- **Detail:** the ranges (`YARD_LEAF_BASE`, `YARD_TREE_SPREAD`, `HIRE_SKILL`) are `Vector2`s, which are 32-bit floats, so 0.45, 0.55 and 0.85 are off by about 1e-8 from the old double literals. The random draws and their order are unchanged, and the work test's layout hash is the same as before.
- **Rule from here:** a new economy number goes in `constants.gd` under its feature's banner, never inline (the formulas get the same treatment in `core/economy.gd`, balance:B).

### 2026-11-01: Economy formulas live in core/economy.gd

- **What:** `core/economy.gd` (no `class_name`; callers `preload` it as `_Economy`) holds the economy's math as pure static functions: `job_xp` (Campaign's job XP), `regrow` (Town.mess), `relationship_after` (a reviewed job's relationship), `mood_thresholds` (the homeowner's clean-enough and messy lines, plus `clean_enough_at` and `messy_below_at`, which return the halves at full precision because a `Vector2` is 32-bit), `job_pay` (what the homeowner hands over), `bag_bonus` (the bag perks' multiplier), `crew_work_scale`, `crew_patience_scale` and `xp_crew_scale` (all 1.0 until the retune, balance:E), `run_roll_chance` (the director's chance per roll) and `migrate_xp` (banked XP carried from one XP curve to another, keeping the tier and the fraction into it). `Ranks` gains `xp_to_reach(tier)` and `CURVE_ID` ("150/25/1200", first/step/endless). Campaign, Town, the homeowner, the leaf field and the run director call these instead of doing the math inline; no number or result changed (the homeowner's clamp bounds became `HOMEOWNER_STANDARDS_PIVOT` and `HOMEOWNER_CLEAN_ENOUGH_MIN/MAX`, `HOMEOWNER_MESSY_BELOW_MIN/MAX` in the `# ---- balance` section, plain floats with the old values).
- **Why:** `tools/balance_sim.py` (balance:C) mirrors these functions in Python, and the engine parity test (`--balance-test`, balance:D) runs a grid of calls here and checks the mirror gives the same answers. One file of pure functions is something both can follow; formulas spread through gameplay nodes are not.
- **Rule from here:** any new economy formula goes in `core/economy.gd` and nowhere else, and whoever changes one also changes its mirror in `tools/balance_sim.py` once that exists. The functions read no nodes and roll no dice: the caller looks up crew size (`Net.peer_ids().size()`, host), stars and perks and passes them in. `run_roll_chance(heat, lots_completed)` keeps today's escalation by jobs finished; balance:E changes its second argument to the neighborhood index. Tests compute expected values through these functions (and `Ranks.xp_to_reach`) instead of writing the numbers, so a retune doesn't break them.

### 2026-11-01: Shops are one host node over a data catalog; Campaign has a public wallet API

- **Catalog:** every shop item is data in `core/catalog.gd` (class `Catalog`): its shop and tab, its kind (tool, tier, upgrade, used_tool, consumable, snack, cosmetic, truck_cosmetic), prerequisites (`needs`, any one), seasons, and rank gate. It holds no numbers: `Catalog.price(id)` is the only price lookup (tools are `Constants.TOOL_PRICES` x `TOOL_TIER_PRICE[tier]`, everything else `Constants.SHOP_PRICES`, Snak-o-Matic items x `VENDING_PRICE_SCALE`), and `Campaign.price_of` delegates to it. `Catalog.gate_of(id)` is the item's rank gate (default `"shop:<id>"`), and `Campaign.is_for_sale` checks it. An item's `seasons` are ids from `Seasons.IDS` (`core/seasons.gd`, the same order as `Seasons.NAMES` and `of_day()`), the one season id list every system keys on; Catalog keeps no copy.
- **Tool tiers are ints everywhere:** -1 none, 0 used, 1 stock, 2 Mk II, 3 Mk III. Owning a tier is an unlock id in the player's existing unlock list (`hose_used`, `hose`, `hose_mk2`, `hose_mk3`); the old stock ids are unchanged, so old saves keep their tools. `Campaign.tool_tier(peer, tool)` is a player's best, `crew_tool_tier(tool)` the best anyone present owns (the crew brings the best one, like the wheelbarrow), and `crew_tools()` counts a tool at any tier, used included.
- **Wallet API:** `Campaign.charge(peer, amount) -> bool` (refuses when short), `pay(peer, amount)`, and `grant_unlock(peer, id)` are the only way other systems move money or grant owned items; each sends the wallet through the existing `_rpc_wallet`, and `grant_unlock` saves. `net/crew/hires.gd` was moved onto them from its private `_add_credits` / `_send_wallet` calls. No Campaign RPC changed. The old counter (`request_purchase` / `_handle_purchase`) now only sells kind tool and upgrade, checks `needs`, and goes through charge and grant_unlock; the Shops node (`net/shops/shops.gd`, next chunk) takes over everything else. `--hire-test` checks the wallet API and these counter rules after its hire steps (a short or negative charge changes nothing, a consumable and The Leafinator without the tune-up are refused, both rake tiers sell and square the multiplier, a used tool is tier 0 and the crew brings it, tier and vending markups).
- **Rank extras:** `Ranks.EXTRA_UNLOCKS` (tier -> ids) lets a tier unlock more than one thing without reordering `UNLOCKS`, which tests and saves depend on. `tier_of` and `unlocks_through` search both; `unlocks_at(tier)` returns the primary plus extras; `unlock_at` still returns only the primary. The day summary's `rank_ups` entries gain `extras`. Other systems add their unlocks to `EXTRA_UNLOCKS` the same way.
- **Strings:** shop text is in `ui/strings.gd` `SHOP_UI` (`item_<id>`, `item_blurb_<id>`, `shop_title_<shop>`, `shop_tab_<tab>`, `shop_result_<code>`, ...), a dictionary of its own beside `UI` so parallel work doesn't edit the same lines, read with `shop_item_name(id)` / `shop_item_blurb(id)`. `unlock_name` falls back to the item's name at its shop. Keeper lines are `KEEPER_LINES[keeper][trigger]`.
- **Numbers:** everything the shops need is in `core/constants.gd` under `# ---- shops`, including `SHOP_SITES` (placement as data, so the drivable town can move shops) and `SHOP_HOURS`.
- **Considered:** crew-shared cash (rejected: per-player cash already exists, matches Schedule I co-op, and keeps the split meaningful); purchases inside Campaign (rejected: it already owns saves and payouts); one node per shop (rejected: one validation path and one test is simpler).

### 2026-11-01: All player-facing sentences live in ui/strings.gd, audited by --cast-test

- **Decision:** every sentence a player reads is a constant in `ui/strings.gd`. Proper nouns that are also data ids or canon names stay with their data: rank names in `core/ranks.gd`, neighborhood, street, and homeowner names in `net/town/neighborhoods.gd`, hire nicknames in `net/crew/hires.gd`, and the Chefty and HOMIE DEPOT brand signs. Lines come in pools (arrays), so variety never needs code.
- **The audit:** `--cast-test` (`net/dev/cast_test.gd`, CI port 7812) walks every constant in `ui/strings.gd` and fails on empty text; unfinished text (`[SOME NAME]`, todo, tbd, placeholder, stand-in); a pool with too few lines, a repeated line, or the wrong number of `%s`/`%d`/`%.Nf` slots (the `FORMAT_ARGS` contract; a pool with no entry needs three lines and no slots); a missing pool for any personality and mood, bill, text kind, shopkeeper trigger, bark kind, run cue, rank, day bucket, neighborhood, season, unlock, task, or tool; and anything matching `GUARDRAIL_PATTERNS` (real agencies, "ICE", words about immigration, papers, accents or nationality, police words, "ice cream", and "Nice Boys" cased wrong; canon is "NICE BOYS"). It also lists sentences still written inline in game code (report only until cast:3 moves them, then it fails). A feature that adds a personality, mood, rank, trigger, or the like must add its lines, or the test fails; that is intended.
- **Shared text choice is seeded or indexed.** Text every peer must agree on is either picked by the host and sent (as the final string, or a pool id plus an index) or derived from a seed every peer already has: `Strings.pick_seeded()`, `crew_tag(index, day)`, `summary_quip(summary)` (seeded by the day and bucket), and `rank_blurb(tier)`. Phone texts stay host-composed and are saved as final strings. Line picks use their own rng, never a gameplay rng, so a pool growing never shifts gameplay.
- **Crew names don't repeat within a raid.** The cast spec's `crew_tag` hashed `[day, index]` per crew member, so names often repeated (17 of the first 100 days with three crew, and day 17 was three BRENTs). Instead the day picks a start in `CREW_NAMES` (`hash(day)`) and each crew member steps one along: still the same on every peer, new each day, and distinct for up to `CREW_NAMES.size()` crew. `--cast-test` checks days 1-100.
- **Unlock names:** the audit runs every `Ranks.UNLOCKS` id and every id in `Ranks.EXTRA_UNLOCKS` (tier -> ids) through `Strings.unlock_name()`, and fails when the result is the raw id, still has a `kind:id`, or has an underscore (a tool with no `UI.tool_<id>` leaks as "the leaf_blower_mk2 at Homie Depot").
- **Also:** the quip cooldown moved to `Constants.QUIP_COOLDOWN_SECONDS` (tuning numbers live in constants). Shopkeeper lines are one table, `KEEPER_LINES[keeper][trigger]`.
- **Considered:** a translation-style key file (CSV or `.po`). Not yet: there is one language, and constants keep the lines type-checked and greppable. Revisit if the game is localized.

### 2026-11-01: Two world modes during the move to a drivable town; zones can be walked into

- **World mode:** the host picks the connected town or the legacy separate zones (`--town-map`, `--legacy-map`, else `Constants.TOWN_MAP_DEFAULT`, false until driving chunk H). `net/session_root.gd` spawns the world through `WorldSpawner.spawn({town_map})` with a `spawn_function`, so every client builds the same mode inside the spawn packet, before `world._ready`. Clients need no flag and there is no handshake change. `world.is_town_map()` is the one place code asks. Legacy goes away after the cut-over (driving chunk I).
- **Zones in the town:** `Net.Zone.TOWN` (appended, value 4) is the streets. In the connected town people walk and drive between the store, the streets and the job site, so the host may work a player's zone out from replicated positions (a host-only zone tracker, driving chunk D) and publish it with `Net.set_player_zone()`, which updates the registry and sends `_rpc_zone_changed(peer, zone, marker, teleport = false)`. Net is still the only source of truth; nobody else reads zones from positions. `move_player_to_zone` still teleports, as before.
- **Requests:** `Net._apply_zone_request` asks `world.can_enter_zone(zone)`. Legacy allows the store, the lot and the border as before; the town also allows `TOWN`, and the lot only with a yard loaded or in automated or bot sessions (which get one on demand).
- **One moving job site:** `world.place_job_site(site, house_id)` moves `LotZone` (and everything yard-relative under it) to a house's yard before its lot loads; yards are never rotated. It is a no-op in legacy.
- **Considered:** a client flag for the mode (clients would have to match the host by hand), and a handshake field (a protocol change for something the world's spawn already carries). Inferring zones on every peer was rejected: membership stays host-decided.
- **Tests:** the smoke test checks the client's world mode matches the host's, that `set_player_zone` re-labels the client without moving it, and that the lot arrival is measured from wherever `LotZone` is.

### 2026-11-01: Audio: buses, a sound bank, positional sounds

- **Buses** are made at runtime by `audio/buses.gd` (`ensure()`, idempotent, called by `ui/ui_root.gd` in every run and by `audio/audio_root.gd`), not by a `default_bus_layout.tres`: Master, Music, Sfx, Ambience (sends to Sfx), UI (sends to Sfx), Chatter, Voice. Music carries a disabled low-pass (`Constants.MUSIC_MUFFLE_CUTOFF_HZ`, `Buses.set_muffled`) for the phone and pause menu. NPC babble, `vo_*`, the player's mouth and crew barks go on Chatter; proximity voice chat on Voice; the HUD's run cues on UI. This is the one bus list every feature uses (gap-specs/critic.md, C2); the Settings feature owns the volumes and the settings file.
- **One sound bank:** `audio/sound_bank.gd` `SOUNDS` registers every sound id (variants, bus, gap_ms, voice, loop, max_seconds, db). Every AudioStreamPlayer that plays a bank id takes its `.bus` from it. `--audio-test` (`net/dev/audio_test.gd`, port 7811) checks each id's files and lengths and scans every script for sound ids passed to the sfx group's methods, `say`, `stinger` and the sound helpers (not `AnimationPlayer.play()`), and for `res://assets/audio/` paths, so an unregistered or misspelled sound fails CI.
- **Sfx moved** from World to `UIRoot/Audio/Sfx` (group "sfx", alive for the whole app, so menus can have sound). API: `play(id, db)` 2D, `play_at(id, at, db, wobble)` positional (`Constants.SFX_UNIT_SIZE`, `SFX_MAX_DISTANCE` 60 m; falls back to 2D without a world), `play_on(id, node, db)` positional and moving with a node (Chefty's departure), `static looped(id_or_path)`, `static log` (last 200 ids), `static placed` (the last 200 positional plays: id, kind "at" or "on", position, and the node path a play_on rides on) and `static unknown` (ids missing from the bank). Headless runs make no players but still log, so tests can assert sounds, and `--audio-test` uses `placed` to fail if the bag, throw, bonk or Chefty sounds slip back to 2D.
- **Gameplay sounds are positional:** net_prop's mower, pull-cord, hose-snap, throw and bonk effects, brawl hits, the leaf bag, and the ride's truck and van now play where they happen, so zones don't leak into each other. Same RPCs with the same arguments; only the local playback changed.
- **Considered:** a `.tres` bus layout (another shared file to merge, and the menu-time setup is a few lines anyway); keeping Sfx under World (no sound in menus, and it dies with every session).
