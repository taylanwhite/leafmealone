# Platforms: developing on Mac, shipping on Mac and Windows

Both developers work on macOS. The game ships on Steam for macOS and Windows. This file covers what that means for setup, exporting, signing, and testing. It is owned by NET, but both lanes should read the gotchas section.

## Development on macOS

- Install the standard Godot 4.7 build for macOS (not the .NET build) in `/Applications`, so the Godot MCP server finds it without extra configuration.
- Install the export templates once, from the editor's Manage Export Templates screen. The same templates export both macOS and Windows builds, so neither of you needs a Windows machine to build.
- Godot 4.7's default rendering driver on macOS is Metal. If either of you is on an Intel Mac, check early that Forward+ runs well there, since most testing and tuning will happen on Apple Silicon.
- Everything in the day-to-day loop works on a Mac: several instances on one machine through Debug > Customize Run Instances, the headless smoke test, and Steam sessions between your two Macs.
- If you ever switch to GodotSteam's pre-compiled editor (the M0 fallback), macOS will quarantine it because it is not notarized. Clear that once with `xattr -dr com.apple.quarantine /path/to/the.app`, and point the Godot MCP at it with `GODOT_PATH`.

## Export presets

Both presets are created in M0 and committed in `export_presets.cfg`. The export script in `tools/` (an M3 task) builds both from a Mac in one command.

**macOS**

- Architecture: universal. Godot's official templates only include universal binaries, so the one build runs natively on Apple Silicon and Intel.
- Entitlements:
  - Disable library validation: on. Godot's documentation says to enable it when using GDExtension add-ons or ad-hoc signing, and GodotSteam is both.
  - Allow DYLD environment variables: on. GodotSteam's macOS export guide recommends it, with users reporting they need it for Steamworks to load and for the overlay.
  - Audio input: on, for proximity voice, along with a microphone usage description in the privacy settings (for example "Leaf Me Alone uses your microphone for proximity voice chat with your crew."). Without both, voice fails on Macs.
- Signing: ad-hoc for now. GodotSteam's guide says code signing and notarization are not strictly required for games launched through Steam, since Steam takes responsibility for launching them. Signing with a Developer ID and notarizing need a paid Apple Developer account, so decide on that before the public release. If you do sign with a Developer ID later, the GodotSteam framework in `addons/godotsteam/` has to be re-signed every time GodotSteam is updated.

**Windows**

- Windows Desktop, x86_64.
- Godot's Forward+ renderer needs a GPU with Vulkan or Direct3D 12 on Windows. Vulkan is Godot's default there.
- Code signing is not needed for builds launched through Steam.

## Testing

| When | What | Where |
| --- | --- | --- |
| Every change | Smoke test and multiple instances on one Mac | Your own Mac |
| Every networked feature | 150 ms and 2% loss, plus a late join | Your own Mac with the dummynet script, or two Macs with Network Link Conditioner |
| From M2, every milestone | Real Steam session between your houses | Both Macs, exported builds |
| From M3, every milestone | Cross-play: Mac hosting a Windows player, and Windows hosting Mac players | One Mac and one real Windows PC, exported builds |
| Before any public build | A low-end Windows machine and the oldest Mac you want to support | Borrowed or bought hardware |

### The Windows test machine

Plan on one real Windows PC with a gaming GPU from M3 onward. A modest desktop or laptop is enough. It needs Steam signed in to a third account (or one of yours, logged out of your Mac for that session).

Running Windows in Parallels on an Apple Silicon Mac is not a substitute. Parallels lists DirectX 11 support, and users on its forum report that DirectX 12 is still not fully supported as of October 2026, so a Forward+ Windows build is not a reliable test there. It is fine for checking that an installer or a launch script runs.

### Sharing builds before the game is on Steam

While you are on app ID 480, builds are shared as zip files. A Mac build downloaded from the internet is quarantined by Gatekeeper, so testers need to right-click the app and choose Open the first time. Once the game has its own Steam app, use a private beta branch instead, and this problem goes away because Steam launches the game.

## Cross-platform gotchas

- **File name case.** macOS and Windows file systems ignore case by default, but exported builds do not. A script that loads `res://Props/Box.tscn` when the file is `res://props/box.tscn` works in the editor and breaks in the shipped game. Name every file and folder in lowercase snake_case and match paths exactly.
- **Line endings.** `.gitattributes` forces LF for all text files, so Godot files and scripts diff the same on every machine.
- **Floating point.** Apple Silicon and x86 can produce slightly different results when a simulation is stepped frame by frame. Anything that must match on every peer is host-owned and replicated, or a pure function of seed and server time. See `NETCODE.md`.
- **Keyboard.** Do not bind gameplay to the Command key. Use Input Map actions only, so keys can be rebound later.
- **Screen sizes.** Mac players are usually on Retina displays and Windows players often on 1080p. The project uses the `canvas_items` stretch mode with `expand` aspect, so UI scales the same on both. Check menus at both sizes.
- **Paths.** Always use `res://` and `user://` paths with forward slashes. `user://` maps to different folders on each OS, which is fine because the game never needs to know where.
- **Microphone permission.** macOS asks the player for microphone access the first time voice starts. Handle a denied permission gracefully with a message instead of failing silently.

## Shipping on Steam

When the game has its own app ID (end of M6):

- Create one depot for macOS and one for Windows, with a launch option for each OS in Steamworks.
- Upload builds with Valve's SteamPipe tools, which run on macOS.
- Fill in Steam's content survey, including the AI-generated content disclosure. `assets/LICENSES.md` is the record for that.
- Linux and Steam Deck are not planned yet. Godot exports Linux builds easily, and Steam Deck can also run the Windows build through Proton, so this is a cheap addition later if you want it.
