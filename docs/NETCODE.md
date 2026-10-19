# Netcode design

This is the reference for everything that runs in multiplayer. `AGENTS.md` lists the rules, and this file explains the patterns behind them so both lanes implement them the same way. If something here turns out to be wrong in practice, fix it here and log the change in `DECISIONS.md` rather than working around it in code.

Leaf Me Alone has a few needs that most co-op games don't: players are in different places at the same time (the store, a job lot, and Border Return Mode), a lot holds hundreds of thousands of leaf units, and Border Return needs hazards that every player sees in the same place at the same moment. The sections on zones, the leaf field, the shared clock, and Border Return cover those.

## Topology

The game uses a listen server. One player hosts, and their game instance is the server (peer id 1) as well as a player. Up to seven more players join as clients (`Constants.MAX_PLAYERS` is 8 while the player count is undecided). There is no dedicated server, no backend, and no host migration. If the host leaves, the session ends and everyone returns to the main menu with the campaign saved on the host's machine.

There are two transports behind one API:

| Transport | Used for | How players connect |
| --- | --- | --- |
| ENet | Local development and the smoke test | `--host` and `--join=127.0.0.1` command-line flags, or the dev section of the main menu |
| Steam (SteamMultiplayerPeer from GodotSteam) | Real sessions | The host creates a friends-only Steam lobby, and friends join through invites or the Steam friends list |

Steam handles NAT traversal and relays traffic through Valve's network, so nobody needs port forwarding. ENet is only used on localhost or a LAN. Both transports work the same on macOS and Windows, and a Mac can host Windows players and the reverse, as long as everyone runs the same `BUILD_VERSION`.

## Autoloads

Two autoloads, both owned by NET, are the only way game code touches networking or persistent state.

### `Net` (`net/net.gd`): the session

```gdscript
enum Transport { ENET, STEAM }
enum State { OFFLINE, CONNECTING, IN_SESSION }
enum Zone { STORE, LOT, BORDER, TRANSIT }

signal state_changed(new_state: State)
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal session_ended(reason: String)          # host left, kicked, version mismatch, connection failed
signal player_zone_changed(peer_id: int, zone: Zone)

func host(transport: Transport) -> Error
func join_enet(address: String, port: int = Constants.DEFAULT_PORT) -> Error
func join_steam_lobby(lobby_id: int) -> Error
func leave() -> void
func invite_friends() -> void                 # Steam only; opens the overlay invite dialog

func is_host() -> bool
func local_peer_id() -> int
func peer_ids() -> Array[int]                 # every connected player, including the local one
func player_name(peer_id: int) -> String
func player_steam_id(peer_id: int) -> int     # 0 in ENet sessions
func current_transport() -> Transport
func current_state() -> State

# Zones (see "Zones")
func player_zone(peer_id: int) -> Zone
func players_in_zone(zone: Zone) -> Array[int]
func move_player_to_zone(peer_id: int, zone: Zone, spawn_marker: StringName = &"") -> void  # host only

# Shared clock (see "Shared clock")
func server_time() -> float                   # seconds on the host's clock, valid on every peer

# Added in M2 (lobby readiness, both transports)
signal ready_changed(peer_id: int, is_ready: bool)
func set_ready(value: bool) -> void
func is_player_ready(peer_id: int) -> bool

# Added in M4 (voice, Steam sessions only)
enum VoiceMode { PUSH_TO_TALK, VOICE_ACTIVATION }
signal speaking_changed(peer_id: int, is_speaking: bool)
func set_voice_mode(mode: VoiceMode) -> void
func set_player_volume(peer_id: int, volume_linear: float) -> void
func set_player_muted(peer_id: int, muted: bool) -> void
```

`Net` keeps a player registry (peer id to name and Steam id). The host owns it. When a client connects, it sends a hello RPC with its build version and display name. The host refuses mismatched versions with a reason, adds the player, sends the full registry to the newcomer, and broadcasts the new entry to everyone else. `player_joined` fires only after this handshake, never on the raw `peer_connected` signal.

### `Campaign` (`net/campaign.gd`): persistent game state

```gdscript
signal campaign_loaded()
signal credits_changed(peer_id: int, credits: int)
signal unlocks_changed()
signal job_stats_changed(peer_id: int)
signal payout_ready(results: Array[Dictionary])   # one entry per player: stats, share, credits earned

func credits(peer_id: int) -> int
func is_unlocked(unlock_id: StringName) -> bool  # unlock ids match the workbook's Unlocks sheet (UN-xx)
func lots_completed() -> int
func current_lot_index() -> int
func job_stats(peer_id: int) -> Dictionary        # leaves_cleared, rescues, objectives during the current job

func request_purchase(item_id: StringName) -> void   # any peer; host validates credits and unlock gates
func record_stat(peer_id: int, stat: StringName, amount: float) -> void  # host only
func finish_job() -> void                         # host only; computes payout and saves
func save_now() -> void                           # host only
```

If PLAY needs something that is not in these APIs, request it in `HANDOFFS.md` instead of reaching into `net/`.

## World layout

The whole campaign happens in one persistent world scene. Instead of loading a new level for each place, the world contains zones spaced far apart, and every peer has every zone loaded. Moving between places is a teleport.

```
core/main.tscn                       (SHARED, rarely changes)
├─ SessionRoot   instance of net/session_root.tscn     (NET)
│  ├─ WorldRoot (Node3D)
│  └─ WorldSpawner (MultiplayerSpawner, spawn_path = ../WorldRoot, spawnable = levels/world.tscn)
└─ UIRoot        instance of ui/ui_root.tscn           (PLAY)

levels/world.tscn                    (PLAY)
├─ StoreZone (Node3D at the origin)
│  ├─ geometry, store counter, truck loading area
│  └─ SpawnPoints (Marker3D children)
├─ LotZone (Node3D about 1,000 m away)
│  ├─ LotSlot (Node3D) + LotSpawner (MultiplayerSpawner, spawnable = every lot scene)
│  └─ the current lot scene is spawned here by the host for each job
├─ BorderZone (Node3D about 1,000 m away in another direction)
│  ├─ lanes, staging area, exit
│  └─ SpawnPoints
├─ Players (Node3D) + PlayerSpawner (MultiplayerSpawner, spawnable = player/player.tscn)
├─ Rides (Node3D) + RideSpawner      (truck and van)
├─ Npcs (Node3D) + NpcSpawner        (enforcement crew)
└─ RuntimeProps (Node3D) + PropSpawner

levels/lots/lot_01.tscn ... lot_08.tscn   (PLAY)
├─ geometry, hazards, client house
├─ LeafField (net/leaf_field/leaf_field.gd, configured with bounds and cell size)
├─ Props (hand-placed props)
└─ SpawnPoints, TruckStop marker
```

Zones about 1,000 meters apart are far enough that players never see or hear each other across zones, and close enough to the origin that single-precision floats stay accurate.

Session flow:

1. The host calls `Net.host()`. `Campaign` loads or creates the host's save, then the host instances `levels/world.tscn` under `WorldRoot` with `add_child(world, true)`. `WorldSpawner` replicates it to every client, including late joiners.
2. The world script, running on the host, spawns one player per peer in the store zone and listens to `Net.player_joined` and `Net.player_left` to spawn and despawn players during the session.
3. For each job, the host spawns the lot scene for `Campaign.current_lot_index()` into `LotSlot`, and frees it after the job.
4. Clients sit on a "Connecting" screen until the world arrives.

## Zones

- The host tracks which zone each player is in. `Net.player_zone()` and `player_zone_changed` are the only source of truth for that. Never infer a player's zone from their position.
- Moving a player between zones is host-ordered. The host calls `Net.move_player_to_zone()`, which updates the registry and tells the owning peer to teleport its character to the marker, using the host-to-owner pattern below. While a player rides the truck or van, their zone is `TRANSIT`.
- Proximity voice needs nothing special. Zones are far apart, so voices from other zones are naturally out of range.
- Start with every synchronized object visible to every peer. With 8 players and small state, bandwidth is fine. Add MultiplayerSynchronizer visibility filtering per zone only if the debug overlay shows it is needed, and log that in `DECISIONS.md`.

## Authority

| State | Authority | How it changes |
| --- | --- | --- |
| A player's position, look direction, animation state | That player's peer | Simulated locally, replicated with a MultiplayerSynchronizer |
| Which zone a player is in | Host | `Net.move_player_to_zone()` |
| Leaf field | Host | Clients send rake and collect requests; the host applies them and broadcasts chunk updates |
| Shared physics bodies (leaf bags, props) | Host | Simulated only on the host; clients freeze them and display the replicated transform |
| Rides (truck, van) and their seating | Host | Host drives them along paths and assigns seats |
| Enforcement crew and run events | Host | AI and the run event director run only on the host |
| Captures and cohorts | Host | Host decides who is captured and which cohort they join |
| Border Return hazards | Nobody at runtime | Deterministic from a seed and a start time on the shared clock |
| Border Return hits | The player who got hit | The owning client detects its own hits and reports them |
| Credits, unlocks, payout, saves | Host | Inside `Campaign` |
| Cosmetic effects (leaf particles, ragdolls, sounds, screen shake) | Each peer locally | Triggered by events, never read back into gameplay |

Player nodes are named with their peer id (for example `"2"`), and each player sets its own authority as soon as it enters the tree:

```gdscript
func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
```

The camera, input handling, and movement simulation run only where `is_multiplayer_authority()` is true. On every other peer the player is a puppet that displays replicated state.

## RPC patterns

Use these three patterns. They avoid the edge cases around `call_local` and `get_remote_sender_id()` by never relying on the host sending an RPC to itself.

### Client asks the host to do something

```gdscript
## Ask the host to grab a prop. Safe to call from any peer, including the host.
func request_grab(prop_name: StringName) -> void:
	if multiplayer.is_server():
		_handle_grab(multiplayer.get_unique_id(), prop_name)
	else:
		_rpc_request_grab.rpc_id(1, prop_name)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_grab(prop_name: StringName) -> void:
	if not multiplayer.is_server():
		return
	_handle_grab(multiplayer.get_remote_sender_id(), prop_name)

func _handle_grab(sender_id: int, prop_name: StringName) -> void:
	# Validate everything: the sender is a known player, the prop exists,
	# it is within reach of that player's character, and nobody else holds it.
	pass
```

### Host tells everyone something happened

```gdscript
## Runs on every peer. Only the host (the authority of this host-owned node) may call it.
@rpc("authority", "call_local", "reliable")
func play_impact(at: Vector3, strength: float) -> void:
	pass  # spawn particles and sound locally
```

Use this only on host-owned nodes. On a player node, "authority" means the owning client, not the host.

### Host tells one player's character to do something

Each character is owned by its client, so the host cannot move it directly. It asks the owner. Teleports, knockback, seating, and capture all use this pattern.

```gdscript
## Host only. Teleports the character on whichever peer owns it.
func send_teleport(target: Transform3D) -> void:
	assert(multiplayer.is_server())
	var owner_id := get_multiplayer_authority()
	if owner_id == multiplayer.get_unique_id():
		_apply_teleport(target)
	else:
		_rpc_teleport.rpc_id(owner_id, target)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_teleport(target: Transform3D) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_apply_teleport(target)
```

After a teleport, `NetSmoother` on other peers sees a jump larger than its snap distance and snaps instead of sliding the character across the map.

### Channels

| Channel | Use | Mode |
| --- | --- | --- |
| 0 | Gameplay RPCs, leaf field chunk updates | reliable |
| 1 | High-frequency input and clock sync | unreliable_ordered |
| 2 | Voice | unreliable_ordered |

## Replication and smoothing

- Players replicate at about 30 Hz and props, rides, and NPCs at about 20 Hz to start. Measure in the debug overlay before raising either.
- Replicate the minimum: position, a yaw angle on the body, a pitch angle on the head, a small animation state enum, and the current tool for players. Position, rotation, and a sleeping flag for props.
- Use "On Change" replication for anything that rarely changes, such as a prop's held state.

Remote objects are smoothed with one shared component, `net/components/net_smoother.gd` (owned by NET). It buffers received snapshots with their local arrival time and renders the object about 100 ms in the past, interpolating between the two snapshots around that time. If a gap is longer than the buffer, it extrapolates for at most 100 ms and then holds. If the error grows past 3 meters (a teleport, for example), it snaps. The delay and snap distance are exported so they can be tuned per object.

The collision body follows the latest snapshot, and only the visual child follows the smoothed transform. PLAY attaches `NetSmoother` to remote players, props, rides, and NPCs, and never writes its own interpolation.

## Shared clock

Border Return hazards, ride progress, and run event timers need every peer to agree on the time. `Net.server_time()` returns the host's clock in seconds on every peer.

- On the host it is simply the host's monotonic clock since the session started.
- Each client estimates its offset from the host. Every second it sends a ping on channel 1 with its own send time, the host replies with its current time, and the client computes `offset = host_time + round_trip / 2 - local_receive_time`. Keep the samples from the last 10 seconds and use the offset from the sample with the lowest round trip, which is the least distorted by jitter.
- Clients should agree with the host to within roughly 20 ms on a normal connection. The debug overlay shows each client's current offset estimate and round trip.

## Leaf field

A lot holds up to hundreds of thousands of leaf units, so leaves are never individual nodes or physics objects. They are a grid owned by the host.

**Data.** `net/leaf_field/leaf_field.gd` (owned by NET) sits in each lot scene. PLAY configures its bounds and cell size (start at 0.5 m). Each cell stores a leaf density from 0 to 255 in a `PackedByteArray`. The grid is split into chunks of 16 by 16 cells, each with a version number. Converting density to the workbook's abstract leaf units is one scale factor, set so the lot's starting total matches its leaf volume from `Balance`.

**Operations.** All changes go through two host-side operations, which together cover both answers to OQ-004:

- `request_rake(origin: Vector3, direction: Vector3, width: float, strength: float)` moves density from cells under the rake to the cells ahead of it, which builds piles.
- `request_collect(origin: Vector3, radius: float)` removes density from cells around a point, for bagging, blowing into a truck, or anything else that takes leaves away.

What counts as "cleaned" is one function on the leaf field that the design can change, for example density below a threshold inside the lawn area. The host credits removed or moved leaf units to the requesting peer through `Campaign.record_stat()`, which is what payout uses.

**Replication.** The host marks touched chunks dirty and, about ten times a second, sends each dirty chunk's bytes and version as a reliable RPC on channel 0. A player arriving at the lot, or joining late, receives every chunk at once, compressed with `PackedByteArray.compress()`.

**Prediction.** The raking player's own client applies the same operation to its local copy immediately, so the rake feels instant, and accepts the host's chunk when it arrives. Small corrections are fine because leaves are noisy anyway.

**Rendering (PLAY).** `leaves/` renders each chunk with a MultiMeshInstance3D (or a ground shader) whose instance count follows the chunk's density, and rebuilds only chunks whose version changed. Flying leaves from a rake stroke are local, cosmetic particles. The leaf field emits `chunk_changed(chunk_index: int)` for rendering to listen to.

## Physics props

- Every networked prop, including leaf bags, is a RigidBody3D using `net/components/net_prop.gd` (owned by NET).
- On the host the prop simulates normally. On clients it is frozen in kinematic mode and moved to the replicated transform.
- Pushing is computed on the host. For every player character, the host applies impulses to props the character is moving into, using that character's replicated velocity. Clients never send push RPCs.
- Grabbing and throwing go through request RPCs. The host attaches the prop to the carrier's replicated hold point and simulates it.
- The carrier's own client draws the held prop's visual at the hand until it is released, to hide one round trip of lag. This is an approved cosmetic prediction.
- When a player disconnects or is captured, the host releases anything that player was holding.

## Rides: the truck and the van

Players never walk around inside a moving vehicle. That is the hardest problem in this genre and the design doesn't need it. Rides are seated.

- A ride is a host-owned node using `net/components/ride.gd` (owned by NET). It follows a Path3D, and its progress along the path is a deterministic function of its start time on the shared clock and its duration, so every peer positions it smoothly without per-frame replication.
- Seats are Marker3D children. The host assigns peers to seats and tells each owner to sit using the host-to-owner pattern. A seated character attaches to its seat, disables movement, and keeps mouse look. Its zone becomes `TRANSIT`.
- On arrival the host unseats everyone and moves them to the destination zone's markers.
- The van fills seats from the captured roster, so its visible occupants always equal the number of captured players [DEC-018]. A captured player who disconnects is removed from the roster and their seat empties on every peer.
- Whether the trip is visible or a short fade is a presentation choice for PLAY. The netcode is the same either way.

## Enforcement crew and run events

- A host-side run event director (`net/run_events/director.gd`, owned by NET) decides when a run event starts. Triggers are pluggable rule objects, one per trigger family in the workbook's Run Events sheet (progress threshold, time pressure, tool noise, random escalation, player action), with chances, escalation, cooldown, and cap from `Balance`. Which rules are active is configuration, since OQ-009 is open.
- Each phase of a run event (foreshadow, arrival, chase, capture, resolution) is broadcast to all peers as an event RPC with its start time on the shared clock, so warnings and music line up everywhere.
- Crew members are host-owned CharacterBody3D nodes spawned by `NpcSpawner`. Their behavior (navigation, chasing, searching) is PLAY's code in `npcs/`, and it only runs on the host. Clients display them with `NetSmoother`.
- Captures are decided on the host. Because a remote player's position on the host lags by about half a round trip, capture checks use a slightly forgiving radius, tuned so being caught feels fair from the player's side.

## Capture cohorts

- When the host captures a player, it opens a batching window (tunable, a few seconds, since OQ-025 is open). Everyone captured within the window joins the same cohort.
- When the window closes, the host freezes the roster, fills the van's seats from it, and starts the van ride to the border zone.
- A cohort has an id, a roster, a hazard seed, and a start time. These are broadcast to every peer, so even players on the lot can show who was taken.

## Border Return Mode

- Hazards are deterministic. Each lane's hazards are a pure function of the cohort's seed, the lane, and `Net.server_time() - start_time`. Never accumulate hazard motion frame by frame. A pure function of time gives the same positions on every peer, including Apple Silicon Macs and x86 Windows PCs, without replicating any hazard.
- Each player's own client checks its character against the hazards. On a hit, it plays the throwback immediately and tells the host with a request RPC so the host can track stats. In a co-op game, trusting the owner here is what makes hits feel fair at any ping.
- Reaching the exit is also reported by the owner. The host does a loose position check, then moves the player back to the lot zone.
- Two open design questions are flags in the cohort config: whether a miss resets one player or the whole cohort (OQ-011, default one player) and whether players finish individually or as a group (OQ-027, default individually).
- While a cohort is in Border Return, the lot keeps running for everyone else (OQ-023).

## Campaign saves

- The host owns the save. It lives in the host's `user://saves/` folder as one file per campaign, written as JSON with a version number so old saves can be migrated.
- Per-player state (credits, owned tools) is keyed by Steam id in Steam sessions and by display name in ENet sessions. When a known player rejoins, the host restores their state. A new player gets starting values.
- Saves happen between jobs, at the store. Saving a lot in progress, including its leaf field, is not built until OQ-014 is decided. The leaf field's chunk data is already a compact format if that becomes necessary.
- Steam Cloud for host saves comes after we have our own app ID.

## Disconnects, versions, and names

- On a client, `multiplayer.server_disconnected` means the session is over. `Net` frees the world, sets state to `OFFLINE`, and emits `session_ended("Host left")`.
- On the host, `multiplayer.peer_disconnected` removes the player from the registry, despawns their character, releases anything they held, removes them from any ride or cohort, and emits `player_left`. Their campaign state stays in the save.
- The build version lives in `core/constants.gd` as `BUILD_VERSION`. Joining with a different version is refused with a clear reason.
- In Steam sessions, player names come from Steam. In ENet sessions they come from `--name=` or the dev menu, with `Player <peer id>` as the fallback.

## Command-line flags

User arguments come after `--` and are read with `OS.get_cmdline_user_args()`.

| Flag | Effect |
| --- | --- |
| `--host` | Start hosting over ENet as soon as the game launches |
| `--join=<address>` | Join an ENet host as soon as the game launches |
| `--port=<n>` | ENet port (default `Constants.DEFAULT_PORT`) |
| `--name=<text>` | Display name for ENet sessions |
| `--start-zone=<store\|lot\|border>` | Host only: start everyone in that zone, for testing |
| `--lot=<n>` | Host only: which lot to load into the lot slot, for testing |
| `--no-steam` | Skip Steam initialization entirely |
| `--smoke-test` | Run the automated smoke test and exit (implies `--no-steam`) |
| `--sim-lag=<ms>` | Add this round trip to incoming packets, half on each peer, so pass it to every instance |
| `--sim-loss=<percent>` | Drop this share of unreliable packets. Reliable ones arrive one round trip late instead, like a resend |
| `--bot` | Drive this peer's own player with input actions: always moving, turning, jumping, and hopping between the store and the lot |
| `--measure=<file>` | Write a JSON report of round trip, bandwidth, hitches, frame times, and ENet throttle when the run ends |
| `--run-seconds=<n>` | Quit after this many seconds, writing the `--measure` report first |
| `--voice-test` | Send a quiet test tone in talk bursts as this peer's voice, over ENet too |
| `--mute-audio` | Mute the master bus. Voice still plays, so playback gaps are measured, but nothing is heard |
| `--screenshot=<dir>` | Save a first-person and an overhead PNG with the F3 overlay showing, every `--screenshot-every=<s>` seconds (default 5). Needs a window |

The last eight live in `net/dev/` and `net/voice/` and do nothing unless a flag asks for them. `--sim-lag`, `--sim-loss`, and `--measure` wrap the ENet peer in `net/dev/link_peer.gd`, which also lets the F3 overlay show bandwidth.

In the editor, use Debug > Customize Run Instances to launch several instances with different flags, for example instance 1 with `--host --name=Host --start-zone=lot` and the others with `--join=127.0.0.1`.

## Smoke test

`godot --headless --path . -- --smoke-test` must exit with code 0 before any multiplayer change is committed. It is implemented in `net/smoke_test.gd`:

1. The process hosts over ENet on a test port and loads the world.
2. It launches a second headless instance of itself with `OS.create_process(OS.get_executable_path(), [...])`, passing `--headless`, `--path`, the project directory, and `-- --join=127.0.0.1 --smoke-client`.
3. It waits up to 20 seconds for the checks below. The client reports what it observed back to the host with an RPC.
4. It kills the child process with `OS.kill()` and quits with code 0 on success, or code 1 with a printed reason on failure.

Checks are added milestone by milestone: connection and handshake, player replication, and a host-ordered zone move (M1); clock agreement within 50 ms, a leaf field change on the host matching on the client, and a moved prop matching (M2); a ride seating and arriving (M3); a capture producing a cohort whose van seat count matches (M4); identical hazard positions at the same server time on host and client (M5).

## Steam

All of this lives in `net/`, and nothing else touches GodotSteam.

- Steam initializes at startup unless `--no-steam` is set. If Steam is not running, the game still starts, the Steam host button is disabled, and the menu says why.
- The app ID is `Constants.STEAM_APP_ID`, which is 480 (Valve's Spacewar test app) until the game has its own. Configure it in exactly one place, using whichever mechanism the installed GodotSteam version documents.
- Callbacks must run every frame, either through GodotSteam's embedded callbacks option or by calling `Steam.run_callbacks()` from `Net._process()`. Check the docs for the installed version.
- Hosting creates a friends-only lobby with `Constants.MAX_PLAYERS` slots. When the lobby is created, the host sets lobby data `game_id` to `Constants.PROJECT_SLUG` and `build` to `BUILD_VERSION`, then calls `host_with_lobby()` on a new SteamMultiplayerPeer and assigns it to `multiplayer.multiplayer_peer`.
- Joining happens when a friend accepts an invite or clicks Join Game in the Steam friends list, which fires GodotSteam's join-requested signal. `Net` joins the lobby, checks the `build` lobby data, and calls `connect_to_lobby()`.
- If the game was not running when the friend clicked Join, Steam launches it with `+connect_lobby <id>` on the command line. Read that from `OS.get_cmdline_args()` (not the user args) at startup.
- App ID 480 is shared by every developer testing Steam, which is why lobbies are friends-only and tagged with `game_id`. Never rely on public lobby search while on 480.
- Rich presence display strings need localization tokens configured in our own Steamworks app, so skip them until we have our own app ID.
- GodotSteam notes that the Steam overlay does not work when running from the editor with the Forward+ renderer. Test invites and the overlay in exported builds.
- Testing Steam needs two Steam accounts on two machines, because one account cannot be online twice.

## Voice (M4)

- Voice only runs in Steam sessions. ENet sessions have no voice, except the `--voice-test` tone used by `tools/soak.sh` to test the whole path without a microphone.
- Capture and compression use GodotSteam's voice functions, called only from `net/steam_bridge.gd`. GodotSteam 4.23.1 has no `SteamVoice` node, so `net/voice/voice.gd` uses `startVoiceRecording`, `stopVoiceRecording`, `getVoice`, and `decompressVoice`, checked against the installed extension.
- Compressed voice packets go to every other peer on channel 2 as unreliable ordered RPCs, every 40 ms while someone talks, carrying a sequence number and the sender's server time.
- Each receiver decodes to 16 kHz mono and plays it through an AudioStreamPlayer3D on the speaker's head, fed by an AudioStreamGenerator, which gives positional audio and distance falloff. It is clear within `Constants.VOICE_CLEAR_DISTANCE` (2 m) and fades out by `Constants.VOICE_MAX_DISTANCE` (25 m). Each burst waits for 80 ms of audio before it starts, and at most 400 ms is held so delay can't build up.
- Push-to-talk sends while `push_to_talk` is held. Voice activation records all the time and lets Steam send only when it hears speech.

```gdscript
# Added in M4 (voice)
func voice_available() -> bool
func voice_mode() -> VoiceMode
func attach_voice_output(peer_id: int, player: AudioStreamPlayer3D) -> void
func is_player_speaking(peer_id: int) -> bool
func set_player_volume(peer_id: int, volume_linear: float) -> void
func player_volume(peer_id: int) -> float
func set_player_muted(peer_id: int, muted: bool) -> void
func is_player_muted(peer_id: int) -> bool
```
- macOS needs the microphone entitlement and a usage description in the export preset, or voice silently fails there. `docs/PLATFORMS.md` has the settings. Test voice in exported builds on both macOS and Windows.

## Cross-platform

`docs/PLATFORMS.md` covers building and testing for macOS and Windows. For netcode, the rules are short. Never depend on two machines computing the same floating-point result by stepping a simulation, since Apple Silicon and x86 can differ in the last bits. Anything that must match on every peer is either host-owned and replicated, or a pure function of seed and server time.

## Testing with latency

A feature is not done until it holds up with 150 ms round trip and 2 percent packet loss. Between two Macs, use Network Link Conditioner (from Apple's Additional Tools for Xcode). It may not affect traffic between instances on the same Mac over localhost, so for that case use `tools/lag.sh on` (dummynet, needs `sudo`) or the `--sim-lag` and `--sim-loss` flags (no `sudo`, works on every platform). Always include a late join in the test, where one instance joins after the others have been playing for a while, because that is where spawn and "On Change" replication bugs show up.

`tools/soak.sh` does all of that without anyone at the keyboard. It starts a host and up to seven `--bot` clients with 150 ms and 2 percent loss, brings the last one in late, collects every peer's `--measure` report, and has `tools/soak_report.py` print a table and a verdict: pass, fail, or inconclusive when the machine was too busy for the timing to mean anything. `-w 2` gives the first two peers windows that take screenshots. Reports and screenshots land in `build/soak/`. The `netcode` GitHub workflow runs the smoke test and a short soak on Linux and Windows for every push.

A hitch is a gap between position updates from a moving player that is longer than `NetSmoother`'s 100 ms buffer, which shows on screen as a freeze and a jump. Under 2 percent of updates is a pass. Player position, rotation, and velocity replicate as Always (unreliable, every 33 ms), so a lost update costs one interval. On Change replicates reliably, and a lost packet then holds up everything behind it for a resend, so keep it for values that change rarely.

## Debug overlay

F3 toggles a small overlay (owned by NET) that shows the transport, session state, local peer id, whether this instance is the host, each player's name, peer id, zone, and ping where the transport exposes it, the clock offset estimate, the frame rate, bandwidth in and out, and the number of synchronized nodes. Every networking bug report should include a screenshot of it.
