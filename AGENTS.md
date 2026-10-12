# Agent guide

This repo is Leaf Me Alone, an online co-op comedy game built by two developers who each work with their own Cursor agent, often at the same time. The biggest risks in that setup are two agents making conflicting changes, drifting into two different architectures, or quietly inventing game design. Most of the rules below exist to prevent those three things. Read this file fully before your first change in a session.

## What the game is

Players take impossible leaf-cleanup jobs, ride a truck from a store to job lots, rake absurd amounts of leaves for pay, buy better tools, and scramble when a fictional enforcement crew shows up. Captured players play a shared lane-crossing mode to get back. `docs/GAME.md` summarizes the design, and the workbook in `design/` is the source of truth for it.

## Stack and platforms

- Godot 4.7, standard build (not .NET). GDScript only, statically typed.
- GodotSteam 4.20 GDExtension in `addons/godotsteam/`. Treat it as vendored code and never edit it.
- Networking uses Godot's high-level multiplayer (RPCs, MultiplayerSpawner, MultiplayerSynchronizer) over ENet during local development and SteamMultiplayerPeer in real sessions.
- Listen server: one player hosts and is authoritative for shared state. No dedicated servers, no backend. Up to 8 players for now.
- 3D physics engine is Jolt.
- Both developers work on macOS. The game ships on Steam for macOS and Windows. Read `docs/PLATFORMS.md` before touching exports or anything platform-specific.
- Git and GitHub, with Git LFS for binary assets.

## Before you start a task

1. Read `.cursor/rules/local-me.mdc` to learn which developer you are working for and which lane they own. If that file is missing, ask the developer before doing anything else.
2. Make sure the working tree is current with `git pull --rebase`. If the pull conflicts, stop and tell the developer instead of resolving it on your own.
3. Read the current milestone in `docs/PLAN.md` and check `docs/HANDOFFS.md` for open requests addressed to your lane.
4. Work only on tasks in your lane. If the developer asks for something in the other lane, say so and get explicit confirmation before touching those files.

## Lanes and file ownership

| Lane | Default owner | Owns |
| --- | --- | --- |
| NET | Taylan | `net/` (the `Net` and `Campaign` autoloads, transports, Steam, zones, shared clock, leaf field data and replication, net components, rides, run event director, captures and cohorts, Border Return timing, saves, voice, debug overlay, smoke test), `tools/` |
| PLAY | Taylan's brother | `player/`, `equipment/` (rake, bags, and other in-game tools), `leaves/` (leaf rendering and effects), `props/`, `levels/` (the world and all lots), `npcs/` (crew behavior), `border/` (lane layouts and hazards as data), `ui/` |
| SHARED | Both | `project.godot`, `export_presets.cfg`, `core/`, `assets/`, `design/`, `docs/`, `AGENTS.md`, `.cursor/rules/` |

Rules for shared files:

- `project.godot` and `export_presets.cfg` are the most likely files to conflict. NET adds autoloads and network settings. PLAY adds input actions, rendering, and physics settings. Keep each change small, commit it by itself, and push right away.
- `core/` holds constants, the main scene, and small utilities. `core/balance.gd` is generated, so never edit it by hand.
- `assets/` is add-only for both lanes. Add new files freely, but only modify assets your lane added.
- `design/` holds the workbook. Agents never edit the workbook. The developers do.
- `docs/PLAN.md` belongs to both lanes, but only check off tasks in your own lane.

If you need something from the other lane, such as a new signal on `Net`, a new field on the leaf field, or a change to the player scene, do not make the change yourself. Add an entry to `docs/HANDOFFS.md`, stub around it on your side if you can, and tell the developer.

## Architecture rules

These are the non-negotiables. The full patterns are in `docs/NETCODE.md`, which you must read before writing anything that runs in multiplayer.

- The host (peer id 1) is authoritative for all shared state: the leaf field, props, rides, the crew, run events, captures, credits, unlocks, and saves.
- Each player's own character movement is owned by that player's peer.
- Clients never change shared state directly. They call a `request_*` RPC on the host, the host validates and applies it, and the result replicates out.
- Every networked node is spawned by a MultiplayerSpawner on the host. Never instance a networked scene on a client.
- Which zone a player is in is decided by the host through `Net`. Moving between the store, the lot, and the border is a host-ordered teleport.
- Anything that must look identical on every peer is either host-owned and replicated, or a pure function of a seed and `Net.server_time()`. Never step a shared simulation frame by frame on every peer.
- Leaves are a host-owned grid, never individual nodes or physics bodies.
- Randomness that affects gameplay runs on the host only.
- Cosmetic effects run locally on each peer and never feed back into gameplay state.
- If the host leaves, the session ends for everyone. There is no host migration.
- Game code talks to `Net` and `Campaign` only. Nothing outside `net/` calls GodotSteam or ENet directly.

## Design rules

- Only Confirmed items in `docs/GAME.md` are canon. Do not treat working assumptions or open questions as decided.
- When a task depends on an open question, build it so the answer can change without a rewrite (a `Balance` value, a flag, or one replaceable function), and name the OQ id in a comment.
- Every tuning number comes from `core/balance.gd` (generated from the workbook) or `core/constants.gd`. Never hardcode balance values in gameplay code.
- Do not invent names, lore, characters, or jokes for the game. Use obvious placeholders such as `[CREW NAME]` and tell the developer. Never use "ICE" or any real agency's name in player-facing content.

## Verify before you commit

- Run the project through the Godot MCP (`run_project`, then `get_debug_output`) and fix every error and warning your change introduced.
- For anything that touches multiplayer, run the smoke test once it exists (M1): `godot --headless --path . -- --smoke-test` must exit with code 0. On macOS the `godot` command is `/Applications/Godot.app/Contents/MacOS/Godot` unless the developer's `local-me.mdc` says otherwise.
- For changes to feel or visuals, tell the developer exactly what to check by hand with multiple instances (Debug > Customize Run Instances, one with `--host` and the rest with `--join=127.0.0.1`).
- Report what you actually ran. Do not say something works if you only reasoned about it.

## Commits

- Keep commits small, one logical change each.
- Prefix the message with the lane: `[NET] add leaf field chunk replication`, `[PLAY] rake stroke feel pass`, `[SHARED] add export presets`.
- Pull with rebase before pushing, and push at the end of every completed task so the other lane sees it.
- Never force-push to `main`. Never commit anything matched by `.gitignore`, especially `.godot/` and `build/`.

## Editing Godot files

- Scripts, scenes, and resources are text, and you may edit `.tscn` and `.tres` files directly. Follow `.cursor/rules/godot-scenes.mdc` when you do.
- Name every file and folder in lowercase snake_case, and match path case exactly. Exported builds are case-sensitive even though the Mac's file system is not.
- Prefer small scenes composed together over one large scene. Every scene has exactly one owning lane.
- Never invent `uid://` values.

## Third-party APIs

GodotSteam's API has changed between versions, and models often guess its function names and signatures wrong. Before writing any GodotSteam call, check the documentation at godotsteam.com for the installed version and match it exactly. Do the same for any Godot API you are not certain exists in 4.7: check the class reference instead of guessing.

## Decisions

When you make a decision, or are told one, that changes the architecture, conventions, or tooling, add a dated entry to `docs/DECISIONS.md` in the same commit. Game design decisions go in the workbook instead, which the developers update.

## Assets

Follow `docs/ART.md`. Log the source and license of every third-party or AI-generated asset in `assets/LICENSES.md` when you add it.
