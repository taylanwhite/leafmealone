# Leaf Me Alone: Cursor starter kit

This kit sets up the Leaf Me Alone repo so two people can build the game in Godot at the same time, each with their own Cursor agent on a Mac, without the agents stepping on each other or inventing design. It contains no game code yet. It contains the rules, architecture, design summary, and plan the agents follow, plus two small files that already work: `core/constants.gd` and `core/balance.gd`, which is generated from the design workbook.

## What is in here

| File | What it is for |
| --- | --- |
| `AGENTS.md` | The contract every agent reads on every request: stack, lanes, ownership, architecture and design rules, how to verify and commit |
| `.cursor/rules/gdscript.mdc` | Code conventions, applied to `.gd` files |
| `.cursor/rules/godot-scenes.mdc` | How to safely edit `.tscn` and `.tres` files as text |
| `.cursor/rules/networking.mdc` | Multiplayer checklist, applied to networked code |
| `.cursor/rules/local-me.mdc.example` | Template for each person's own identity and lane (the real copy is gitignored) |
| `.cursor/mcp.json` | Godot MCP server, so agents can run the game and read its errors |
| `design/leaf-me-alone-workbook.xlsx` | The design workbook, the source of truth for design and tuning |
| `design/export_balance.py` | Regenerates `core/balance.gd` from the workbook's Balance Lab |
| `core/constants.gd`, `core/balance.gd` | Project constants and generated tuning values, checked in Godot 4.7 |
| `docs/GAME.md` | The workbook's confirmed canon, working assumptions, and open questions, written for agents |
| `docs/PLAN.md` | Milestones M0 to M6 with tasks per lane, workbook backlog ids, and done criteria |
| `docs/NETCODE.md` | The networking design: `Net` and `Campaign` APIs, zones, shared clock, leaf field, rides, captures, Border Return, saves, Steam, voice |
| `docs/PLATFORMS.md` | Developing on Mac, exporting and testing for Mac and Windows |
| `docs/DECISIONS.md` | Log of technical decisions, seeded with the ones made so far |
| `docs/HANDOFFS.md` | Where one lane asks the other for something |
| `docs/ART.md` | Art rules that keep AI-generated and free assets looking like one game |
| `docs/KICKOFF.md` | The prompts to paste into Cursor for setup, daily work, workbook updates, and cross-play tests |

## Lanes

Work is split by folder so the two agents rarely touch the same files.

- **NET** (Taylan by default) owns the session, Steam, zones, the shared clock, the leaf field's data and replication, rides, the run event director, captures, Border Return timing, saves, voice, and the smoke test.
- **PLAY** (Taylan's brother by default) owns the player, equipment, leaf rendering, props, the world and lots, crew behavior, Border Return lanes, and all UI.
- **SHARED** covers `project.godot`, export presets, `core/`, `assets/`, `design/`, and the docs.

Swap or rebalance whenever you like. Update `AGENTS.md` and your `local-me.mdc` files when you do.

## Setup

Both of you install on your Macs: Godot 4.7 (standard build, not .NET) in `/Applications`, Git with Git LFS, Node.js 18 or newer (for the Godot MCP server), Python 3 with `openpyxl` (for the balance script), the Steam client, and Cursor. With Homebrew, `brew install git-lfs node` covers two of those, and `python3 -m pip install --user openpyxl` covers the script.

### Taylan, first

1. Create a private GitHub repo and add your brother as a collaborator.
2. Copy everything in this kit into the repo root, run `git lfs install`, commit, and push.
3. Copy `.cursor/rules/local-me.mdc.example` to `.cursor/rules/local-me.mdc` and check your name, lane, and Godot path.
4. Open the repo folder in Cursor. Enable the `godot` MCP server when Cursor asks, and check that it lists its tools.
5. Paste the M0 prompt from `docs/KICKOFF.md` into a Cursor agent chat and work through M0. A few steps happen in the Godot editor, and the agent will tell you when.

### Your brother, after M0 is pushed

1. Clone the repo and run `git lfs install` and `git lfs pull`.
2. Open the project in Godot once so it imports everything, then close it.
3. Create his own `.cursor/rules/local-me.mdc` from the example, with lane PLAY.
4. Open the folder in Cursor, enable the `godot` MCP server, and paste the onboarding prompt from `docs/KICKOFF.md`.

### If the Godot MCP cannot find Godot

The MCP server looks for Godot in the usual install locations, which on a Mac means `/Applications/Godot.app`. If yours is elsewhere, or if you end up on GodotSteam's pre-compiled editor, add the same server to your user-level Cursor MCP settings with a `GODOT_PATH` environment variable pointing at the Godot executable inside the app bundle, and turn off the project-level one on your machine. Keep the path out of the shared `.cursor/mcp.json`.

## Windows

You both develop on Macs, and the Mac exports the Windows build too. From M3 on you need one real Windows PC with a gaming GPU for cross-play tests. `docs/PLATFORMS.md` explains why a Windows VM on an Apple Silicon Mac isn't a reliable substitute and what to test.

## Working day to day

Start each session with the session-start prompt from `docs/KICKOFF.md` and end it with the session-end prompt. In between, keep tasks small, let the agent run the game through the MCP after each change, and push as soon as a task is done so the other lane gets it quickly. When the workbook changes, use the workbook prompt so `core/balance.gd` and `docs/GAME.md` stay in sync. When you both have a milestone's tasks checked off, play it together before moving on.
