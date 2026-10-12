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
