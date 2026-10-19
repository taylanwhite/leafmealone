# Plan

The milestones build Leaf Me Alone in the order that retires the biggest risks first. M1 is a plain multiplayer sandbox, because retrofitting multiplayer later is where projects like this stall. After that, each milestone adds one of the game's hard parts (the leaves, the job loop, the run event, Border Return) as a playable prototype, and M6 turns them into a first vertical slice. Design backlog ids from the workbook (BL-xxx) and open questions (OQ-xxx) are noted where they apply. `docs/GAME.md` explains them.

Each task is tagged with its lane: `[NET]`, `[PLAY]`, or `[SHARED]`. Tasks marked `(human)` need someone to click through the Godot editor, Steam, GitHub, or Apple's tools. An agent should prepare everything around them and then tell the developer exactly what to do. Agents check off tasks in their own lane only, and only after the task's checks have actually been run.

Current milestone: **M6**

---

## M0: Repo, tooling, and Mac setup

Taylan does M0 alone so that only one person creates `project.godot`. His brother clones once M0 is pushed. `docs/PLATFORMS.md` has the details for the Mac and export steps.

- [ ] `[SHARED] (human, Taylan)` Create the GitHub repo, add his brother as a collaborator, copy this kit into it, run `git lfs install`, and make the first commit.
- [x] `[SHARED] (human, Taylan)` Install Godot 4.7 (standard build) in `/Applications`, create a project in the repo root with the Forward+ renderer, and open it once so Godot writes its files. Install the export templates.
- [x] `[SHARED] (human, Taylan)` Install the GodotSteam GDExtension from the Godot Asset Library and enable it.
- [x] `[SHARED]` Verify the GodotSteam install. Write a throwaway script that prints `ClassDB.class_exists("SteamMultiplayerPeer")` and `ClassDB.class_exists("Steam")`, run it through the Godot MCP, then delete it. If `SteamMultiplayerPeer` is missing, stop and tell Taylan. The fallback is GodotSteam's pre-compiled Godot 4.7 editor, which bundles everything, and both of you would switch to it. Log the outcome in `DECISIONS.md`.
- [x] `[SHARED]` Confirm `core/constants.gd` and `core/balance.gd` (both in the kit) load without errors, and that `python3 design/export_balance.py` regenerates `balance.gd` with no diff. Install `openpyxl` if the script asks for it.
- [x] `[SHARED]` Project settings: 3D physics engine "Jolt Physics", 60 physics ticks, window 1280x720, stretch mode `canvas_items` with aspect `expand`. Commit `project.godot` on its own.
- [x] `[SHARED]` Create the folder skeleton from `AGENTS.md` with a `.gitkeep` in each empty folder, plus `assets/LICENSES.md` with an empty table (columns: file, source, license, AI-generated yes/no, tool used).
- [x] `[SHARED]` Create `core/main.tscn` (a Node3D with two empty child nodes, `SessionRoot` and `UIRoot`, as placeholders) and set it as the main scene.
- [x] `[SHARED]` Add all input actions now so neither lane has to touch the input map for a while: `move_forward` (W), `move_back` (S), `move_left` (A), `move_right` (D), `jump` (Space), `sprint` (Shift), `crouch` (C), `interact` (E), `primary` (left mouse), `secondary` (right mouse), `drop` (G), `push_to_talk` (V), `toggle_camera` (F5, debug), `pause` (Escape), `toggle_debug` (F3). Commit `project.godot` on its own.
- [x] `[SHARED]` Create the macOS and Windows export presets as described in `docs/PLATFORMS.md`, export the empty project for both targets once to confirm the templates work, and commit `export_presets.cfg`. Delete the test builds.
- [ ] `[SHARED] (human, brother)` Install the same tools, clone the repo, run `git lfs install` and `git lfs pull`, open the project in Godot once so it imports, open the folder in Cursor, create `.cursor/rules/local-me.mdc` from the example, and confirm the Godot MCP can run the project.

Done when both Macs can open the project, run it through the MCP with no errors, and push a trivial commit that the other pulls cleanly.

---

## M1: Multiplayer sandbox with zones (ENet only)

Two to eight instances on one Mac can join each other, walk around, move between the store zone and the lot zone, and see each other smoothly.

NET
- [x] `[NET]` Do this first, in the first session: push `net/net.gd` (registered as the `Net` autoload), `net/campaign.gd` (registered as `Campaign`), and `net/components/net_smoother.gd` as stubs with the final signatures from `NETCODE.md`, including the later-milestone additions, so PLAY can build against them the same day.
- [x] `[NET]` `Net` for the ENet transport: host, join, leave, the hello handshake with version check, the player registry, and the signals.
- [x] `[NET]` Command-line flags from `NETCODE.md`.
- [x] `[NET]` `net/session_root.tscn` with `WorldRoot` and `WorldSpawner` and the session flow from `NETCODE.md`. Replace the `SessionRoot` placeholder in `core/main.tscn` with it.
- [x] `[NET]` Player spawning helper the world calls on the host: one player per peer in the store zone, despawn on leave.
- [x] `[NET]` Zones: `Net.player_zone()`, `players_in_zone()`, `move_player_to_zone()` with host-ordered teleports, and `player_zone_changed`.
- [x] `[NET]` Shared clock: `Net.server_time()` as specified in `NETCODE.md`.
- [x] `[NET]` `NetSmoother` as specified, with exported delay and snap distance.
- [x] `[NET]` Host leaving ends the session for clients, who return to the main menu with the reason shown.
- [x] `[NET]` Debug overlay on F3.
- [x] `[NET]` `tools/lag.sh` for macOS that adds delay and packet loss to the dev port on localhost using `dnctl` and `pfctl` (dummynet), with `on` and `off` commands. Verify it with the ping shown in the debug overlay.
- [x] `[NET]` Smoke test covering connection, handshake, player replication, and a host-ordered zone move.

PLAY
- [x] `[PLAY]` `levels/world.tscn` with the layout from `NETCODE.md`: a gray-box store zone (counter, truck loading area, spawn points), a lot zone with a `LotSlot`, and an empty border zone. Include the `Players`, `Rides`, `Npcs`, and `RuntimeProps` nodes with their spawners.
- [x] `[PLAY]` `levels/lots/lot_test.tscn`: a flat gray-box yard with a house, fences, and spawn points, loaded into the lot slot when `--start-zone=lot` is used.
- [x] `[PLAY]` `player/player.tscn`: CharacterBody3D with a visible body and a separate head, walk, sprint, jump, crouch, and mouse look, active only on the authority. MultiplayerSynchronizer for position, body yaw, head pitch, animation state, and current equipment. `NetSmoother` on remote players.
- [x] `[PLAY]` Swappable camera rig for OQ-001: first-person and over-the-shoulder, toggled with `toggle_camera`. The rest of the player script must not care which one is active.
- [x] `[PLAY]` A debug interaction in the store that asks the host to move you to the lot zone, and one on the lot that brings you back.
- [x] `[PLAY]` `ui/ui_root.tscn` with a main menu (name field, Host and Join with an address field, Quit), mouse capture on play and release on Escape. Replace the `UIRoot` placeholder in `core/main.tscn` with it.
- [x] `[PLAY]` Simple nameplates above remote players using `Net.player_name()`.

Done when:
- Instance 1 with `--host` and instance 2 with `--join=127.0.0.1` see each other walk, jump, crouch, and look up and down smoothly.
- Up to eight instances can join, including after the others have been playing for a minute.
- Moving between the store and the lot works for every player and looks right on every other instance.
- Closing a client despawns its player cleanly, and closing the host returns everyone to the menu with "Host left".
- Remote players still look smooth with `tools/lag.sh` set to 150 ms round trip and 2 percent loss.
- The smoke test passes.

---

## M2: The leaves, and playing together over Steam

The core of the game is raking, so it gets prototyped right away (BL-002, OQ-004). Steam lands in the same milestone so the two of you can play from your own houses from here on.

NET
- [x] `[NET]` Leaf field (`net/leaf_field/`): host-owned density grid in chunks, `request_rake` and `request_collect`, the "cleaned" function, chunk replication, full snapshot on arrival or late join, local prediction for the raking player, and contribution credited through `Campaign.record_stat()`. Scale density to the lot's leaf units from `Balance`.
- [x] `[NET]` `net/components/net_prop.gd` for host-authoritative RigidBody3D props, host-side pushing from replicated player velocities, and grab, carry, throw, and drop request RPCs with validation.
- [x] `[NET]` Steam: initialization with app ID 480, callbacks every frame, a clean fallback when Steam isn't running, friends-only lobbies tagged with `game_id` and `build`, `host_with_lobby()` and `connect_to_lobby()`, joining through invites and the friends list, cold start through `+connect_lobby`, `Net.invite_friends()`, and player names from Steam.
- [x] `[NET]` Ready flags in the host's player registry, replicated on both transports.
- [x] `[NET]` Extend the smoke test: clock agreement, a leaf field change matching on the client, and a moved prop matching.

PLAY
- [x] `[PLAY]` Leaf rendering in `leaves/`: one MultiMeshInstance3D per chunk driven by density, rebuilt only when a chunk changes, plus cosmetic leaf particles on rake strokes. Hold 60 fps on both Macs with lot 1's full leaf volume.
- [x] `[PLAY]` A rake in `equipment/` that calls `request_rake` with a satisfying stroke, and a way to bag leaves that calls `request_collect` and produces a leaf bag prop.
- [x] `[PLAY]` Leaf bags and a few yard props (trash can, wheelbarrow, garden gnome) using `NetProp`, with carry, throw, and drop.
- [x] `[PLAY]` A cleanup percentage on the HUD from the leaf field.
- [x] `[PLAY]` Lobby screen (player list, ready toggle, Invite Friends, Start for the host), Steam host as the main menu button with ENet moved to a dev-only section, and a pause menu with Leave Session.
- [ ] `[SHARED] (human)` Play the lot together for 30 minutes in both camera modes. Record the camera decision for OQ-001 in `DECISIONS.md` and note what felt good or bad about raking.

Done when the two of you, in your own houses, can rake the same lot over Steam, the cleanup percentage matches on both screens, raking feels worth iterating on, and the smoke test passes.

---

## M3: One complete job loop, on Mac and Windows

Store, truck, lot, payout, upgrade, and back (BL-001, BL-003, BL-004, BL-006). This is also when Windows builds start getting tested.

NET
- [x] `[NET]` `net/components/ride.gd`: seated rides along a Path3D driven by the shared clock, host-assigned seats, `TRANSIT` zone while riding, unseat and move on arrival.
- [x] `[NET]` `Campaign`: credits per player, job stats, `finish_job()` computing payout from the `Balance` weights (OQ-005, OQ-006), `payout_ready`, `request_purchase()` with unlock gates, and saves between jobs keyed by Steam id.
- [x] `[NET]` Lot loading: the host spawns the lot scene for `Campaign.current_lot_index()` into the lot slot for each job and frees it afterward.
- [x] `[NET]` `tools/export.sh` that exports the macOS and Windows builds from a Mac in one command into `build/`.
- [ ] `[NET] (human)` First cross-play test on a real Windows PC, following `docs/PLATFORMS.md`: a Mac hosting a Windows player and the Windows PC hosting a Mac player.
- [x] `[NET]` Extend the smoke test: a ride seats players and arrives.

PLAY
- [x] `[PLAY]` Store zone: a counter or attendant (UI-only is fine), a store screen, and one tool upgrade that raises raking throughput by the `Balance` multiplier (BL-004).
- [x] `[PLAY]` The truck: boarding at the loading area, seats up to `Balance.EXPECTED_TRAVELING_PARTY_SIZE`, the ride to the lot and back. Keep the boarding rule in one replaceable function (OQ-002). Players who don't board stay in the store (OQ-003).
- [x] `[PLAY]` Ending a job: a way to call it done on the lot, the truck back, and a payout screen that shows each player's contribution breakdown so it reads as fair.
- [x] `[PLAY]` `levels/lots/lot_01.tscn`: the first real lot layout in gray box with a leaf field sized to lot 1's volume.

Done when four players, including one on Windows, can play store to lot to payout to upgrade to the next job over Steam, quit, and resume from the save.

---

## M4: The enforcement run event and proximity voice

The threat arrives (BL-005, BL-012). Proximity voice lands here because this is where it starts to matter.

NET
- [x] `[NET]` Run event director: pluggable trigger rules for the families in the workbook's Run Events sheet, chances, escalation, cap, and cooldown from `Balance`, and phase events broadcast with server-time starts (OQ-009).
- [x] `[NET]` NPC sync: host-owned crew members spawned by `NpcSpawner`, smoothed on clients.
- [x] `[NET]` Captures and cohorts: host-side capture checks with a tunable forgiving radius, the batching window (OQ-025), roster freeze, and the van ride with seats filled from the roster.
- [ ] `[NET]` Proximity voice as specified in `NETCODE.md`, including the macOS microphone entitlement check in an exported build on both platforms. Built and passing the bot soak with a test tone. Still needs a hand test over Steam with real microphones on two machines.
- [x] `[NET]` Extend the smoke test: a capture produces a cohort whose van seat count matches.

PLAY
- [x] `[PLAY]` Crew behavior in `npcs/`: arrival, chasing with NavigationAgent3D, searching, and capturing, using placeholder visuals and the placeholder name `[CREW NAME]` until the design names them (OQ-012).
- [x] `[PLAY]` Warning and foreshadow cues (sound, radio, visual) for each phase, timed to the phase events.
- [x] `[PLAY]` Counterplay version zero: running, hiding behind or inside things, and breaking line of sight (OQ-010).
- [x] `[PLAY]` The van with visible occupants that always match the captured roster for 1 to 8 captured players (OQ-026).
- [x] `[PLAY]` Voice: AudioStreamPlayer3D on each head, a speaking indicator over each player and in the lobby, and a voice settings screen.

Done when a run event can fire, players can escape or be caught, the van always shows exactly the captured players, voices fade with distance, and it all works across Mac and Windows.

---

## M5: Border Return Mode

Captured players cross back together (BL-011).

NET
- [x] `[NET]` Cohort instances in the border zone: staging, the deterministic hazard timeline (pure functions of seed and server time), owner-reported hits and finishes, and the return to the lot zone.
- [x] `[NET]` Flags for OQ-011 (individual or cohort reset) and OQ-027 (individual or group finish), both defaulting to individual.
- [x] `[NET]` Extend the smoke test: hazard positions at the same server time match on host and client.

PLAY
- [x] `[PLAY]` Lane layouts and hazards as data in `border/`, scaled by a difficulty value (OQ-022). Mechanics and presentation must be original.
- [x] `[PLAY]` A camera for the crossing and the comic throwback on failure.
- [x] `[PLAY]` The disembark beat from the van, the crossing, and the return transition to the yard.

Done when cohorts of one to four players cross at the same time, hazards line up identically on a Mac and a Windows PC, failure is funny and immediate, and a crossing takes roughly `Balance.BORDER_RETURN_TARGET_DURATION_MINUTES`.

---

## M6: First vertical slice and playtest

Lot 1 from start to finish, good enough to put in front of friends (BL-007, BL-008, BL-009, BL-010).

NET
- [x] `[NET]` Telemetry version zero: local JSON logs per session with job durations, cleanup percentages, payouts, run events, captures, and Border Return times (BL-009).
- [x] `[NET]` Bandwidth and ping checked with eight players in the debug overlay.

PLAY
- [x] `[PLAY]` Art pass on the store, lot 1, and the border zone following `ART.md`, including the shared post-process look.
- [x] `[PLAY]` Quip playback with cooldowns and per-session limits, using draft lines from the workbook with their Q ids, from one strings file (BL-008).
- [x] `[PLAY]` Sound pass: footsteps, raking, bags, the truck, the van, and run event audio.

SHARED
- [ ] `[SHARED] (human)` Playtest with friends on both Mac and Windows. Write `docs/PLAYTEST-01.md` with what made people laugh, what broke, and measured times.
- [ ] `[SHARED] (human)` Put measured values back into the workbook's Balance Lab, regenerate `core/balance.gd`, and update `docs/GAME.md` with any decisions.
- [ ] `[SHARED] (human)` Register the game in Steamworks, replace app ID 480, set up macOS and Windows depots, and add the next milestones to this file.

Done when friends who weren't involved can play lot 1 start to finish without help and want to play again.
