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
- **Quick checks:** `-Only smoke` (about 30 s) for anything networked.
- **Script errors after edits:** `& $G --headless --path . --quit` and read stderr. Run `--import` once after adding files or classes.
- **Looking at the game:** windowed runs with `--screenshot=<dir> --tour` (see `net/dev/capture.gd`), or the studio: `& $G --path . res://tools/studio/studio.tscn -- --subject=<name> --out=build/art/<name>.png`. Read the PNGs with the Read tool. Look for clipping, z-fighting, floating or sunk objects, and wrong lighting.
- **Multiplayer by hand:** one instance with `-- --host --no-steam`, others with `-- --join=127.0.0.1 --no-steam --name=Bot1 --bot`. Add `--sim-lag=150 --sim-loss=2` to every instance for a bad network.
- **Voice:** `--voice-test` exercises the whole voice path with a tone over ENet. Real Steam voice needs a second machine and Steam account.

### Adding a test

New gameplay gets an automated test, like everything since M1: a `net/dev/<x>_test.gd` node with a static `result` dict that gets `"done": true` at every place the test ends, pass or fail (that is what lets the run quit early, and a test that never sets it runs out its `--run-seconds` ceiling), a flag in `net/command_line.gd` (and its `wants_dev_tools()` list), an `_add()` branch in `net/dev/dev_tools.gd`, the result key in `net/dev/probe.gd`, a step in `.github/workflows/netcode.yml` on the next free port, and the same entry in `tools/ci_local.ps1`'s `$Tests` table.

## Versioning

`Constants.BUILD_VERSION` must match exactly between host and clients. Bump it whenever an RPC, a replicated property, or the save format changes.

## Git

- Work happens on a branch; commit small, with the lane prefix (`[NET]`, `[PLAY]`, `[SHARED]`) and the Co-Authored-By trailer.
- Push the branch when a task is done. Never force-push `main`.
- Commit the `.uid` files Godot generates next to new scripts.
