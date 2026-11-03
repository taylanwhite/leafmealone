# Claude Code guide

Read `AGENTS.md` first; it holds the architecture and multiplayer rules, and they all still apply. This file covers what is specific to Claude Code on Taylan's Windows machine, and the direction set on 2026-11-01. Where this file and AGENTS.md disagree, this file wins.

## Direction (2026-11-01, Taylan)

- **Development is mostly AI-driven.** Claude builds, tests, and judges the game for long stretches, and Taylan plays it. There is one developer; lanes are a commit prefix, not an ownership rule.
- **Creative freedom.** Agents may name things, write jokes and lines, and design systems. Write what you decide into `docs/GAME.md` (and `docs/DECISIONS.md` for architecture) in the same commit, so the next agent builds on it instead of re-inventing it. The humor guardrail still applies: punch up at impossible work, precarious systems, and enforcement bureaucracy, never at immigrants, ethnicity, nationality, or accents. Never use "ICE" or a real agency's name in player-facing content.
- **Schedule I is the model** for the look, the sound, how characters play, how shops work, and the progression loop (`docs/FEEL.md`, `docs/SPINE.md`). Lethal Company is not.
- **Persistent town.** Neighborhoods, houses, and homeowners persist and recur; each yard's mess regenerates. One-off generated yards are being replaced.
- **Four players**, not eight (`Constants.MAX_PLAYERS`).
- **Early access.** No ending is needed yet; the game needs a 10 to 20 hour progression arc and a loop that keeps people coming back.
- Tuning numbers still live in `core/constants.gd` or `core/balance.gd`, never inline. New tuning goes in `constants.gd`; `balance.gd` stays generated from the workbook.
- **The end sequence is Form 27-B at Satellite Annex B** (R2, `net/annex/`), which replaced Border Return's lane crossing; the Border zone's slot holds the Annex.

## Writing for players

Taylan (2026-11-02): "Let's not hold our players hand through everything. Text like that screams it was made by AI. Our players are not idiots." The full rule and the first-session walk-through are in `docs/GAME.md`, "Writing for players". In short:

- Keep prices, names, requests, things the player can't see from where they stand (where the job is, where a teammate was taken), and flavor lines with personality.
- Cut status and refusals that restate what the world shows (no "Chefty's full", "Out of gas", "Pockets full"), control tutorials the player finds by pressing keys, and step-by-step goal lines. Let sound, animation and the world say it.
- An interact prompt is a keycap and a verb ("[E] Talk"), never the name of what's in front of you.
- At most one short first-time cue, and only for a control nothing else shows (today: the bag key on a pile's price, until the first bag).
- When in doubt, cut the text.

## Tools on this machine

| What | Where |
| --- | --- |
| Godot 4.7.2 (console build, for stdout) | `%USERPROFILE%\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe` |
| Godot editor / windowed runs | `%USERPROFILE%\Tools\Godot\Godot_v4.7.2-stable_win64.exe` |
| Python 3.12 (with openpyxl) | `%LOCALAPPDATA%\Programs\Python\Python312\python.exe` (`python` on PATH may be the Store stub) |
| Git (+ LFS), Git Bash | `C:\Program Files\Git\cmd\git.exe`, `C:\Program Files\Git\bin\bash.exe` |
| User data (saves, logs) | `%APPDATA%\Godot\app_userdata\Leaf Me Alone\` |

The shell is Windows PowerShell 5.1: no `&&`, and use the full Git path if `git` isn't on PATH.

## Testing

Every change gets run, and you report what you ran.

- **Everything CI runs:** `powershell -ExecutionPolicy Bypass -File tools\ci_local.ps1`. Feature tests run side by side (`-Jobs N`, default 8 here) and each quits as soon as its test is done; the two bot soaks then run together and set the floor (about 3 minutes, since the run-event soak lasts 170 s). `-Only smoke,work` runs some, `-SkipSoak` skips the bot soaks (about 1 to 2 minutes), `-List` lists names, `-PortOffset 100` shifts every port and test save so runs in two worktrees at once don't collide. Logs and JSON reports land in `build\soak\local-<name>\`. Each test starts from a clean test save of its own (`campaign_test_<port>.json`).
- **Never touch Taylan's real save.** Any flag besides `--host`, `--join=`, `--name=`, `--no-steam` and `--town-map` (`--port=` included, or a headless run) is a dev session and plays on `campaign_test_<port>.json` (`campaign_dev.json` without `--port=`); the real save refuses dev writes, and `ci_local.ps1` fails `real-save` if it changes. A new flag is a dev flag unless it is added to `PLAYER_FLAGS` in `net/command_line.gd`, which only a real player-facing option should be. Engine flags before `--` (`--fixed-fps`, `--quit-after`, `--script`) never reach scripts and don't count, so a windowed run you launch by hand needs a dev user flag (`--port=` will do).
- **Quick checks:** `-Only smoke` (about 30 s) for anything networked.
- **Script errors after edits:** `& $G --headless --path . --quit` and read stderr. Run `--import` once after adding files or classes.
- **Looking at the game:** windowed runs with `--screenshot=<dir> --tour` (see `net/dev/capture.gd`), or the studio: `& $G --path . res://tools/studio/studio.tscn -- --subject=<name> --out=build/art/<name>.png`. Read the PNGs with the Read tool. Look for clipping, z-fighting, floating or sunk objects, and wrong lighting.
- **Playtesting a moment** (anything a player does or sees happen; the full guide and the detail checklist are `docs/PLAYTEST.md`): a still can't show motion, so record it.
  1. `tools\play.ps1 -Start -Observer -Scenario <moment>`: a windowed host on a fixed step, already at the moment (`rake_fresh`, `rake_pile`, `raid_warn`, `raid_arrive`, `caught`, `hide`, `van_ride`, `annex`, `store`, `drive`; `scenario list` has them all), and a second window watching it.
  2. `tools\play.ps1 -Instance observer 'follow host 4 1.6 80; record_start 30 x_3p'`, then `tools\play.ps1 'record_start 30 x_1p; hold primary 1.3; wait 0.5; record_stop'` (or `'record 4 30 x_1p'` while it plays out), then `tools\play.ps1 -Instance observer record_stop`.
  3. Read `build\play\rec_x_1p\sheet.png` (frames stamped with number and game time), `audio.png` (thumbnails, waveform, bands, picture change, every sound and event on one time axis), `events.json` (per frame: player, camera, HUD text, what fired; flags for pops, snaps and frozen views), `sync.json` (each sound's lag), and the observer's copies; `tools\frames.ps1 <rec dir> "40..46"` puts frames side by side.
  4. Walk the checklist in `docs/PLAYTEST.md` with frame numbers, then `tools\play.ps1 -Stop` (it closes only this worktree's windows).
- **Driving a game by hand:** `tools\play.ps1 -Start`, then `tools\play.ps1 'hold move_forward 1.5; look 200 0; tap interact'` (net/dev/remote_play.gd lists the steps); each call prints what's on screen and a screenshot path.
- **Multiplayer by hand:** one instance with `-- --host --no-steam`, others with `-- --join=127.0.0.1 --no-steam --name=Bot1 --bot`. Add `--sim-lag=150 --sim-loss=2` to every instance for a bad network.
- **Voice:** `--voice-test` exercises the whole voice path with a tone over ENet. Real Steam voice needs a second machine and Steam account.

### Adding a test

New gameplay gets an automated test, like everything since M1: a `net/dev/<x>_test.gd` node with a static `result` dict that gets `"done": true` at every place the test ends, pass or fail (that is what lets the run quit early, and a test that never sets it runs out its `--run-seconds` ceiling), a flag in `net/command_line.gd` (and its `wants_dev_tools()` list), an `_add()` branch in `net/dev/dev_tools.gd`, the result key in `net/dev/probe.gd`, and a port. Use the next port in the "CI ports" table in `docs/DECISIONS.md` (or the one that table already reserves for your test), set it explicitly as `Port = 78xx` in the test's `tools/ci_local.ps1` `$Tests` entry, and use the same port in its `.github/workflows/netcode.yml` step; never rely on the table position. Extra args both sides need (say `--sim-lag=120`) go in the entry's `Extra` key and on both lines of the CI step. `tools\ci_local.ps1 -CheckPorts` confirms every port matches `netcode.yml`. Any new player-facing text must pass `net/dev/guardrail.gd`; a new table of it goes in `tools/guardrail_check.gd`'s `SOURCES`.

## Versioning

`Constants.BUILD_VERSION` must match exactly between host and clients. Bump it whenever an RPC, a replicated property, or the save format changes.

## Git

- Work happens on a branch; commit small, with the lane prefix (`[NET]`, `[PLAY]`, `[SHARED]`) and the Co-Authored-By trailer.
- Push the branch when a task is done. Never force-push `main`.
- Commit the `.uid` files Godot generates next to new scripts.
