# Netcode design

This is the reference for everything that runs in multiplayer. `AGENTS.md` lists the rules, and this file explains the patterns behind them so both lanes implement them the same way. If something here turns out to be wrong in practice, fix it here and log the change in `DECISIONS.md` rather than working around it in code.

Leaf Me Alone has a few needs that most co-op games don't: players are in different places at the same time (the store, a job lot, and Satellite Annex B), a lot holds hundreds of thousands of leaf units, and the Annex needs clerks that every player sees doing the same thing at the same moment. The sections on zones, the leaf field, the shared clock, and the Annex cover those.

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
enum Zone { STORE, LOT, BORDER, TRANSIT, TOWN }  # TOWN: the connected town's streets

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
func players_in_zone(zone: Zone) -> Array[int]  # the crew there: watchers left out
func set_watcher(peer_id: int, watching: bool) -> void  # host only, dev: the playtest observer; host-local
func is_watcher(peer_id: int) -> bool
func move_player_to_zone(peer_id: int, zone: Zone, spawn_marker: StringName = &"", teleport: bool = true) -> void  # host only
func set_player_zone(peer_id: int, zone: Zone) -> void  # host only: re-label, no teleport

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

- The host tracks which zone each player is in. `Net.player_zone()` and `player_zone_changed` are the only source of truth for that. Never infer a player's zone from their position on your own. The one exception is the host in the connected town (`world.is_town_map()`, see DECISIONS 2026-11-01), where people walk and drive between places: the host works the zone out from replicated positions and publishes it with `Net.set_player_zone()`, which changes the registry without a teleport (`_rpc_zone_changed`'s `teleport` flag is false). Everyone else still reads `Net.player_zone()`.
- The world says which zones exist: `world.can_enter_zone(zone)` gates requested moves (debug gates, bots). `TOWN` exists only in the connected town.
- Moving a player between zones is host-ordered. The host calls `Net.move_player_to_zone()`, which updates the registry and tells the owning peer to teleport its character to the marker, using the host-to-owner pattern below. While a player rides the truck or van, their zone is `TRANSIT`.
- Proximity voice needs nothing special. Zones are far apart, so voices from other zones are naturally out of range.
- Start with every synchronized object visible to every peer. With 8 players and small state, bandwidth is fine. Add MultiplayerSynchronizer visibility filtering per zone only if the debug overlay shows it is needed, and log that in `DECISIONS.md`.

## Authority

| State | Authority | How it changes |
| --- | --- | --- |
| A player's position, look direction, animation state | That player's peer | Simulated locally, replicated with a MultiplayerSynchronizer |
| Riding a skateboard (on_board, skate_trick, wipeout, skitch) | That player's peer | `player/skate.gd` simulates it in place of walking; the flags replicate on change with the player; a bump on someone goes to the host as a request (`brawl.request_skate_bonk`) |
| Which zone a player is in | Host | `Net.move_player_to_zone()` |
| Leaf field | Host | Clients send rake and collect requests; the host applies them and broadcasts chunk updates |
| Shared physics bodies (leaf bags, props) | Host | Simulated only on the host; clients freeze them and display the replicated transform |
| Rides (truck, van) and their seating | Host | Host drives them along paths and assigns seats |
| Enforcement crew and run events | Host | AI and the run event director run only on the host |
| Captures and cohorts | Host | Host decides who is captured and which cohort they join |
| Annex B clerks, the Head NICE BOY, Window D | Nobody at runtime | A pure schedule of a seed and the Annex's begin time on the shared clock, plus the host's ordered overrides (`net/annex/annex_schedule.gd`) |
| Annex B forms, stamps, the big stamp, the turnstile | Host | Clients ask (`_rpc_request_*` with their server time, clamped to a grace window); the host stamps and sends the whole form |
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
| 1 | High-frequency input and clock sync, vehicle input and pose snapshots | unreliable_ordered |
| 2 | Voice | unreliable_ordered |

## Replication and smoothing

- Players replicate at about 30 Hz and props, rides, and NPCs at about 20 Hz to start. Measure in the debug overlay before raising either.
- Replicate the minimum: position, a yaw angle on the body, a pitch angle on the head, a small animation state enum, and the current tool for players. Position, rotation, and a sleeping flag for props.
- Use "On Change" replication for anything that rarely changes, such as a prop's held state.

Remote objects are smoothed with one shared component, `net/components/net_smoother.gd` (owned by NET). It buffers received snapshots with their local arrival time and renders the object about 100 ms in the past, interpolating between the two snapshots around that time. If a gap is longer than the buffer, it extrapolates for at most 100 ms and then holds. If the error grows past 3 meters (a teleport, for example), it snaps. The delay and snap distance are exported so they can be tuned per object.

The collision body follows the latest snapshot, and only the visual child follows the smoothed transform. PLAY attaches `NetSmoother` to remote players, props, rides, and NPCs, and never writes its own interpolation.

## Shared clock

The Annex's clerks, ride progress, and run event timers need every peer to agree on the time. `Net.server_time()` returns the host's clock in seconds on every peer.

- On the host it is simply the host's monotonic clock since the session started.
- Each client estimates its offset from the host. Every second it sends a ping on channel 1 with its own send time, the host replies with its current time, and the client computes `offset = host_time + round_trip / 2 - local_receive_time`. Keep the samples from the last 10 seconds and use the offset from the sample with the lowest round trip, which is the least distorted by jitter.
- Clients should agree with the host to within roughly 20 ms on a normal connection. The debug overlay shows each client's current offset estimate and round trip.

## Leaf field

A lot holds up to hundreds of thousands of leaf units, so leaves are never individual nodes or physics objects. They are a grid owned by the host.

**Data.** `net/leaf_field/leaf_field.gd` (owned by NET) sits in each lot scene. PLAY configures its bounds and cell size (start at 0.5 m). Each cell stores a leaf density from 0 to 255 in a `PackedByteArray`. The grid is split into chunks of 16 by 16 cells, each with a version number. Converting density to the workbook's abstract leaf units is one scale factor, set so the lot's starting total matches its leaf volume from `Balance`.

**Operations.** All changes go through two host-side operations, which together cover both answers to OQ-004:

- `request_rake(origin: Vector3, direction: Vector3, width: float, strength: float, bite := 0, tempo := 0.0) -> int` gathers the density the rake's tines crossed into a berm just ahead of them (the windrow rule, rakefeel:field: `_stroke_cells`), which builds piles. `bite` also sets how far a rake's stroke drives (`RAKE_FIELD_BITE_FRONT`), and each stroke sweeps back over the ground the raker's head was dragged across since their previous request (`_stroke_drag`); the host and the raking client both count every request in order, so the drag, like the rest of the rule, needs nothing new on the wire. It returns the density moved (on a client, what it predicted; 0 when it couldn't). `bite` (0 the plant bite, 1 mid-drive) and `tempo` (the swing's seconds) only ride along on the stroke event, for the rake swing (raking:4).
- `request_collect(origin: Vector3, radius: float) -> int` removes density from cells around a point, for bagging, blowing into a truck, or anything else that takes leaves away.
- Host only: `host_hand_rake(origin, direction, skill, actor := 0, tempo := 0.0) -> int` (`tempo`: the hand's swing seconds for its stroke event; 0 means `HIRE_STROKE_SECONDS / skill`) and `host_hand_collect(origin, actor := 0) -> int` (hired hands; `actor` is `RAKE_ACTOR_HAND_BASE + N` for "HandN"), `host_mulch(at, radius) -> int` (a running mower), `host_scatter(at, radius, dollars)` (a burst bag). Callers of the old forms keep working.

What counts as "cleaned" is one function on the leaf field that the design can change, for example density below a threshold inside the lawn area. The host credits removed or moved leaf units to the requesting peer through `Campaign.record_stat()`, which is what payout uses.

The density rules (`_apply_rake`'s in-place loop and 8-way rounding, `_stroke_cells`, `_apply_collect`, `host_scatter`'s maths) are frozen by `net/dev/leaf_golden.gd`: 40 scripted ops on a scratch field must give the hash, `leaf_units`, `cleaned_fraction` and per-op results recorded from 0.4.5. A rule change on purpose (R1-F) re-records them.

**Stroke events (raking:1, contract C1).** `signal stroke_event(ev: Dictionary)` fires once per stroke on every peer, in the frame the density changes, empty strokes (moved 0) included; out-of-reach requests and refused bags make none. Keys: `kind` (`rake`, `hand`, `blower`, `crew_rake`, `bag`, `crew_bag`, `mulch`, `scatter`, `plow`), `actor` (peer id, `RAKE_ACTOR_HAND_BASE + N` for a hand, 0 for mower, scatter, plow), `seq`, `bite`, `at`, `dir` (flat unit; +Z for undirected kinds), `step` (the field's 8-way step), `width` (the disc's diameter), `cells`, `moved`, `tempo`, `t` (`Net.server_time()` at the apply), `ack_tick`, `local`. Who emits it:

- The host emits every stroke it applies, with `local` true for its own player's, and sends `_rpc_stroke_event(packed)` (authority, call_remote, reliable, channel 0, 36 bytes from `net/leaf_field/stroke_event.gd`) in the same frame, so it reaches clients before the batch that carries its density. `_emit_stroke(kind, actor, at, dir, width, cells, moved, seq, bite, tempo)` is the one helper; driving:C3's `host_plow` uses it with kind `plow`.
- The raking client emits its own predicted stroke (`local` true) and treats the host's echo only as an ack, never as a second event. Its own request it couldn't predict (out of reach as it saw it, a thin bag the host took anyway) is emitted when the echo arrives.
- Everyone else emits on receipt (`local` false). The 0.4.5 `stroke_visual(at)` signal is gone (removed at the R1 merge): the rake, the hired hands, the leaf motion layer, the sounds and the playtest recorder all read `stroke_event`.
- A running mower calls `host_mulch` every physics tick; its event is coalesced to one per send tick per mower (summed, at the last spot), emitted at the send tick just before the batch, with that batch as its `ack_tick`. So every bit of mulch reaches a client after the event that tells it, in exactly the batch the event names, and none is left untold when the mower stops. Mulch peaks at about 10 events a second instead of 60 reliable RPCs (`SEND_INTERVAL` must stay at least `LEAF_EVENT_MULCH_SECONDS`; `_ready` asserts it). This is the one kind that is not emitted in its density's frame: on the host the mulch from the frames between send ticks has already been flushed to `leaves_changed` when its event fires.

**field_reset and leaves_changed.** `field_reset(hard)` says the whole field was replaced: hard at the end of `shape_initial` (a new lot) and for a join or new-lot snapshot (and the first snapshot a client ever applies, whatever its reason); soft for the resyncs after an out-of-reach stroke or a refused bag, which a view may animate. `leaves_changed(chunk_index)` is deferred, once a frame, for each chunk whose bytes on this peer really changed since the last one (host applies, predictions, ledger recomposes, batches, snapshots), so a view reacts the same frame and a confirmation that matches the prediction says nothing. `chunk_changed` keeps its 0.4.5 timing (the host's at the send tick, a client's on its predictions and corrections, all chunks on a snapshot) for anything still on it.

**Replication.** The host marks touched chunks dirty and, about ten times a second, sends all of them in one `_rpc_chunk_batch(tick, indices, versions, data, compressed)` (reliable, channel 0; deflated above `LEAF_BATCH_COMPRESS_BYTES`), so a stroke's chunks never arrive split. `tick` counts batches. A chunk older than the client's version is skipped. A player arriving at the lot, or joining late, gets `_rpc_snapshot(compressed, versions, removed_units, tick, hard, upto_seq)`. A resync's `upto_seq` is the refused request's seq; a hard snapshot sends -1.

**Prediction ledger.** The raking client predicts with the host's exact numbers: `_stroke_params(peer, width, strength)` (rake, bare hands, blower tier reach, speed and cells, times `Campaign.rake_multiplier`) is the one function both use, so a blower puff no longer snaps back, and a bag predicts with the bag type's real scoop. Each request carries a u16 `seq`; the client keeps `_confirmed` (the host's bytes as the batches left them) and `_pending` (its own unconfirmed strokes). The host's echo gives the pending stroke its `ack_tick` (the next batch tick, -1 when nothing changed, which drops it at once). On a batch with tick T, its chunks go into `_confirmed`, every pending stroke with `0 <= ack_tick <= T` is done, and the field is recomposed: the whole of `_confirmed` plus the remaining strokes replayed in order with the same rule code (a cascade crosses chunks, so never a region). Only chunks that come out different are marked. A snapshot replaces `_confirmed`. A hard one clears the ledger. A resync (soft, after an out-of-reach stroke or a refused bag) drops only the strokes up to the refused request's seq (u16, wrap aware), which the host had already applied. Strokes sent after it are still on their way to the host, so they stay and are replayed over the new bytes. Otherwise raking on through a refused stroke would revert and then reappear. Pending strokes older than `LEAF_PREDICT_TIMEOUT` are dropped, and at most `LEAF_PREDICT_MAX` are kept. With the ledger empty, the client's bytes are the host's, so the smoke test's exact comparison holds. At 150 ms and 2% loss the ledger peaks at 3 and empties about 0.2 s after the last stroke (`--rake-net-test`), and no cell ever falls back. `ledger_stats()` (probe `leaf_ledger`) has the counters.

**Bandwidth.** About 30 stroke events a second at worst (four rakers at 3.3 strokes a second, hands, mulch at 10 Hz), roughly 1.5 KB/s, plus the batches, which carry the same bytes the old per-chunk RPCs did in fewer, bigger RPCs (the test's 41 s run: 91 events and 84 batches of 105 chunks, 28 KB of batch payload, from the host).

**Rendering (PLAY).** `leaves/` draws the field. Since raking:1 a view listens to `leaves_changed` and `field_reset` (and falls back to `chunk_changed` without them), and the motion layer reads `stroke_event`. Everything drawn is local and cosmetic and never writes the field. The probe's `leaf_instances` counts every MultiMeshInstance3D under the field: hero flakes (and fading ones) once raking:2 lands, about a third of 0.4.5's count; it is reported, never asserted. The probe's `leaf_view` merges the view's and the motion layer's `stats()`.

## Physics props

- Every networked prop, including leaf bags, is a RigidBody3D using `net/components/net_prop.gd` (owned by NET).
- On the host the prop simulates normally. On clients it is frozen in kinematic mode and moved to the replicated transform.
- Pushing is computed on the host. For every player character, the host applies impulses to props the character is moving into, using that character's replicated velocity. Clients never send push RPCs.
- Grabbing and throwing go through request RPCs. The host attaches the prop to the carrier's replicated hold point and simulates it.
- The carrier's own client draws the held prop's visual at the hand until it is released, to hide one round trip of lag. This is an approved cosmetic prediction.
- When a player disconnects or is captured, the host releases anything that player was holding.
- Pockets (`net/components/hotbar.gd`): a prop with `pocketed_by` set is in that peer's pocket, in hotbar slot `pocket_slot`. It is non-solid, follows its owner on the host, and is never pushed, mown, loaded or brought back in. "Free on the ground" is `is_loose()`, never `held_by == 0`. `World/Hotbar.host_settle(peer)` is the only place that moves pocket items between hand and pocket: at most one held per peer, pocket before draw. Clients ask with `request_select(slot)` (the owner predicts the selection for `HOTBAR_PREDICT_SECONDS`; `_rpc_selected` corrects it after a refusal). A capture empties the pockets onto the yard in an itemized row, and a disconnect drops everything. Leaving the yard mid-job drops the job's own things (bags, signs, the gas can) but keeps the crew's kit (p2-kit); in the connected town that only fires past `PROP_LEASH_METERS` from the site (critic C23). Bots flick `slot_next` on their way to a rake run and draw the rake back (`net/dev/bot_job.gd`: `FIDGET_CHANCE` 0.1 per run for crew bots, `SOAK_FIDGET_CHANCE` 0.4 for soak bots; each bot prints its count on exit). The soaks cover this only partly: the store soak has no rake since p2-kit, and in the event soak only whichever peer holds the yard's one dev rake fidgets, so the client-side select RPC under `--sim-lag` runs only when a client bot has it (one local run: the host, no RPC; another: Bot1, once). The client path under lag is checked by hand in crew sessions (`tools\play.ps1 -Bots N` with `--sim-lag`).

## Rides: the truck and the van

Players never walk around inside a moving vehicle. That is the hardest problem in this genre and the design doesn't need it. Rides are seated.

- A ride is a host-owned node using `net/components/ride.gd` (owned by NET). It follows a Path3D, and its progress along the path is a deterministic function of its start time on the shared clock and its duration, so every peer positions it smoothly without per-frame replication.
- Seats are Marker3D children. The host assigns peers to seats and tells each owner to sit using the host-to-owner pattern. A seated character attaches to its seat, disables movement, and keeps mouse look. Its zone becomes `TRANSIT`.
- On arrival the host unseats everyone and moves them to the destination zone's markers.
- The van fills seats from the captured roster, so its visible occupants always equal the number of captured players [DEC-018]. A captured player who disconnects is removed from the roster and their seat empties on every peer.
- Whether the trip is visible or a short fade is a presentation choice for PLAY. The netcode is the same either way.

**Drivable Chefty (the connected town, driving chunk C1; `net/components/chefty_drive.gd`).** Still seated: nobody walks inside it. In `--town-map` worlds `World/Rides/Chefty` is made in code on every peer (`levels/world.gd _add_chefty`) and is driven, not pathed. It keeps the ride contract above (`seat_of`, `seat_transform`, `depart`, the bags), so nothing that uses Chefty changes.

- **Authority:** the host simulates it (`net/components/vehicle_sim.gd`, a pure step function over a CharacterBody3D chassis on `Constants.VEHICLE_LAYER`) and owns the 8 seats, the bags and the horn. Clients ask: `_rpc_request_enter(kind)`, `_rpc_request_exit()`, `_rpc_request_swap()`; the host answers with `_rpc_seats(riders, driver)` (reliable, the whole seat list), `_rpc_horn(on)`, `_rpc_bags(job_bags, job_value, spent_bags)`. A late joiner asks `_rpc_request_state()` and gets `_rpc_state(...)`.
- **Input:** the driver's own peer sends `_rpc_input(seq, throttle, steer, flags)` every physics tick on channel 1, unreliable_ordered. The host uses one per tick (two when more than `CHEFTY_INPUT_QUEUE_CATCHUP` are queued), in sequence: every tick of a client's drive stands for one input (`_sim_seq`). When the next input is late (a long frame on either peer sends a burst after a gap) or lost, the host drives on the last one and that tick stands in for it, up to `CHEFTY_STAND_IN_MAX_SECONDS` ahead; the input, when it comes, only becomes the held one. It brakes after `CHEFTY_INPUT_TIMEOUT` with nothing, and those ticks stand for nothing.
- **Snapshots:** `_rpc_snap(t, pos, yaw, vel, yaw_rate, steer, ack)` from the host 30 times a second on channel 1, unreliable_ordered, with `ack` the driver input its pose is after (`_sim_seq`: the last one used, or the last one a stand-in tick drove for). An explicit RPC, not a synchronizer: Chefty is a static node, and the snapshot needs its own timestamp and ack.
- **Prediction:** the driver's peer runs the same sim on its own inputs at once; on a snapshot it puts the chassis at the host's pose, replays the inputs after `ack`, and fades the jump out of what it draws (`CHEFTY_CORRECTION_HALF_LIFE`; past `CHEFTY_SNAP_ERROR` it snaps). The snapshot is only stored when it arrives; the replay runs at the start of the next physics tick, because `move_and_slide` moves by the physics step only inside a physics frame (in the RPC callback it used the render frame's delta, and every replay fell short). Everyone else draws the snapshots `CHEFTY_VIEW_DELAY` behind with `net/components/vehicle_view.gd` on physics ticks (priority 50, between the vehicle and the riders), not with NetSmoother, so riders stay glued to their seats.
- **The autopilot (driving chunk C2):** a depart() trip or a hired hand's chauffeuring is host-only input generation (`net/components/vehicle_autopilot.gd`) fed to the same sim, so the pose replicates through the same snapshots. `_rpc_autopilot(kind, zone, label, quip)` (reliable, call_local) tells every peer a trip started or ended, for `is_riding()`, who's drawn at the wheel and the quip; while a trip runs nobody predicts (a seated driver's peer draws the view) and the driver's seat is closed. Clients ask for the chauffeur with `_rpc_request_chauffeur()`. Automated runs and `--warp-rides` move the chassis along the route kinematically instead (warp mode). A depart() trip's riders are in `TRANSIT` and arrive with the usual host-ordered teleport; a chauffeur's stay seated.
- **Zones:** riders keep their zone while they ride. Getting out in the town re-labels the player with `Net.set_player_zone()` from where they stand (the store's lot, the job site, else `TOWN`) until driving chunk D's zone tracker does it for everyone.
- **Bails and captures:** a bail sends `_rpc_seats`, the teleport and `_rpc_thrown` back to back on reliable channel 0, so they land in order, usually in one poll; `player.set_thrown` catches the seat up first (`_seat_on_ride`), or the fling would be dropped as if still seated. A capture (`director.note_capture`) calls `drop_rider` on every vehicle, so a rider caught in the bed leaves the seat before the van seats them.

## Enforcement crew and run events

- A host-side run event director (`net/run_events/director.gd`, owned by NET) decides when a run event starts. Triggers are pluggable rule objects, one per trigger family in the workbook's Run Events sheet (progress threshold, time pressure, tool noise, random escalation, player action), with chances, escalation, cooldown, and cap from `Balance`. Which rules are active is configuration, since OQ-009 is open.
- Each phase of a run event (foreshadow, arrival, chase, capture, resolution) is broadcast to all peers as an event RPC with its start time on the shared clock, so warnings and music line up everywhere.
- Crew members are host-owned CharacterBody3D nodes spawned by `NpcSpawner`. Their behavior (navigation, chasing, searching) is PLAY's code in `npcs/`, and it only runs on the host. Clients display them with `NetSmoother`.
- Captures are decided on the host. Because a remote player's position on the host lags by about half a round trip, capture checks use a slightly forgiving radius, tuned so being caught feels fair from the player's side.

## Capture cohorts

- When the host captures a player, it opens a batching window (tunable, a few seconds, since OQ-025 is open). Everyone captured within the window joins the same cohort.
- When the window closes, the host freezes the roster, fills the van's seats from it, and starts the van ride to the border zone.
- A cohort has an id, a roster, a hazard seed, and a start time. These are broadcast to every peer, so even players on the lot can show who was taken.

## Satellite Annex B (Form 27-B)

Border Return (the lane crossing) is gone (R2 chunk 6, 2026-11-02). Caught players do a paperwork errand at Satellite Annex B, in the BORDER zone's slot (`Net.Zone.BORDER` now means the Annex). `World/Annex` (`net/annex/annex.gd`, group `annex`) runs it; docs/GAME.md has the design.

- **Pure schedule plus host overrides.** Every clerk's routine, the Head NICE BOY's desk-and-away, Window D's one opening and the run's quirks and pictograms are a pure function of the Annex's seed and the seconds since it began (`annex_schedule.gd`). Interruptions (a serve, a bell, a head shake, a noticed heist, the big stamp spotted, closing time) are host overrides `{kind, w, at, until, ...}` in the same clock, sent reliably in order and applied newest-first (`effective()`). Every peer draws the same room without replicating a body; the host judges "is he looking" from the schedule, never from the cosmetic bodies.
- **Outcomes are the host's.** Clients ask (`_rpc_request_serve(window, client_t)`, `_self_stamp`, `_bell`, `_desk`, `_big_stamp`, `_cosign`, `_tray`, `_leave`, `_visit`), with `client_t` clamped to `[now - ANNEX_GRACE, now]`; the host checks reach and state and sends the whole form back (`_rpc_form`). Owners predict only the stamp lifting; the KA-CHUNK waits for the host.
- **The never-wait guarantee** is a property of the generator (annex_test checks 200 seeds): no "looking but not serving" stretch over `ANNEX_MAX_IDLE`, a serving window always open, each open at least `ANNEX_MIN_OPEN_SHARE`.
- **The turnstile** turns for one player: their own peer disables its bar's shapes while it's open for them (each peer simulates only its own player, so that lets exactly them through); the host sees them reach the forecourt.
- **Late joiners** get `_rpc_snapshot(snapshot())` from the host on `player_joined` (and from the director's state request once R2 chunk 2 sends one); they spectate and are never in the roster. **Disconnects** leave the roster, queues and holds; a held big stamp goes back to its pad; an empty Annex with no visitors ends (`_rpc_end`).
- **Without the other R2 chunks** (each guarded by group + has_method or `ResourceLoader.exists`): no Shuttle, so `world.on_ride_arrived(BORDER)` calls `begin()` and the finishers go home by the host's teleport; no AnnexSet, clerks, clipboard or slip, so `annex_greybox.gd` and `annex_paper.gd` stand in with the same node names and calls; no Encounter, so no stage changes; no iris, so a cut.
- While a cohort is at the Annex, the lot keeps running for everyone else (OQ-023).
- RPCs (World/Annex): `_rpc_begin(trip_id, roster, seed, start_at, forms, windows, quirk_windows, d_open_at, close_at)`, `_rpc_join(peer, form, at)`, `_rpc_stage(peer, stage, at)`, `_rpc_override(entry)`, `_rpc_form(peer, form, at, source)`, `_rpc_stamped(peer, window, at, ok)`, `_rpc_big_stamp(holder, at)`, `_rpc_big_slam(holder, target, at)`, `_rpc_turnstile(peer, at, open)`, `_rpc_cosigned(visitor, at)`, `_rpc_visitors(list)`, `_rpc_closing(at, forms)`, `_rpc_through(peer, at, seconds, by_closing, lines, total)`, `_rpc_out(peer)`, `_rpc_left(peer)`, `_rpc_end()`, `_rpc_snapshot(snap)`, `_rpc_place(at)` and `_rpc_door_iris(at)` to one peer, `_rpc_retime(start_at, close_at)` (dev), and the `_rpc_request_*` asks above. The smoke test's `_rpc_hazard_probe/_sample` became `_rpc_schedule_probe/_sample` (the schedule's 200-sample fingerprint).

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
| `--start-zone=<store\|lot\|border\|town>` | Host only: start everyone in that zone, for testing (`town` needs the connected town; the legacy world starts them at the store) |
| `--town-map` / `--legacy-map` | Host only: build the connected town, or the legacy separate zones (default `Constants.TOWN_MAP_DEFAULT`). Clients get the host's choice with the world's spawn data |
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
| `--rake-net-test` | The leaf field's stroke events, batches and prediction ledger at 150 ms / 2% loss, and the golden density rules (`net/dev/rake_net_test.gd`, port 7821; host and client both pass it) |
| `--leaf-motion-test` | Leaves flying between cells: conservation, no teleports, quiescence (`net/dev/leaf_motion_test.gd`, raking:3, port 7822) |
| `--leaf-motion-headless` | Keep the leaf view's and motion's state (no GPU objects) in a headless run; read by `leaves/leaf_renderer.gd` from the user args |
| `--rake-stroke-test` | The rake swing's bite timing, a remote swing and a hired hand's rake (`net/dev/rake_stroke_test.gd`, raking:4, port 7823) |

The three R1 tests are loaded by path (`net/dev/dev_tools.gd _add_by_path`); one that isn't built yet prints `[Dev] <Test> not built`, and the probe reports `{done: true, ok: false, why: "not built"}` for it.

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

A hitch is a gap between position updates from a moving player that is longer than `NetSmoother`'s 100 ms buffer, which shows on screen as a freeze and a jump. Under 2 percent of updates is a pass. Hitches and lost voice packets are judged on the network's share: each peer logs its stalls (frames over 50 ms), and a hitch or a run of lost voice that lines up with a stall on its way (the receiver, the host relaying it, or the mover) is counted apart, as the machine's (columns `+stall` and `v loss`; `hitch` and `v net` are judged). On a busy machine a stall also lines up with some of the network's own problems by chance, so each peer's odds of that are measured (`h odds`, `v odds`) and the judged share is divided by 1 minus them; a check that fails with odds over half is inconclusive. A peer whose ENet throttle limit ever falls below full fails, and so does a peer that exits non-zero (docs/DECISIONS.md, 2026-11-03). Player position, rotation, and velocity replicate as Always (unreliable, every 33 ms), so a lost update costs one interval. On Change replicates reliably, and a lost packet then holds up everything behind it for a resend, so keep it for values that change rarely.

## Debug overlay

F3 toggles a small overlay (owned by NET) that shows the transport, session state, local peer id, whether this instance is the host, each player's name, peer id, zone, and ping where the transport exposes it, the clock offset estimate, the frame rate, bandwidth in and out, and the number of synchronized nodes. Every networking bug report should include a screenshot of it.

## R2: the catch (Encounter and director)

The NICE BOYS encounter (gap-specs/nice_boys.json). Host-authoritative; every cosmetic timeline is a pure function of replicated state and `Net.server_time()`. All reliable on channel 0, so they arrive in order across nodes; consumers still check state (a crew `mode` can arrive through the Synchronizer before or after the Encounter's RPC: the camera, control lock and staging key off the Encounter's stage, the gestures off the crew's mode). Chunk 4 (Shuttle) and chunk 6 (Annex) append their tables below.

| Node | RPC / property | Direction | What |
| --- | --- | --- | --- |
| RunDirector | `_rpc_phase(phase, started_at, status)` | host -> all | QUIET 0, WARNING 1, CHASE 2, DEPARTING 3 |
| RunDirector | `_rpc_request_state()` / `_rpc_state(state)` | client -> host -> that client | late join: phase, cohort, Encounter / Shuttle / Annex snapshots |
| RunDirector | `_rpc_drop_rider(peer)` | host -> all | kept |
| Encounter | `_rpc_windup(grab_id, crew, peer, from, dir, contact_at, from_spot, travel)` | host -> all | the wind-up and lunge, played from these args everywhere |
| Encounter | `_rpc_whiff(grab_id, peer_id, crew_index, at)` | host -> all | missed or spoiled (carries who, so the host's own call and a late joiner find them) |
| Encounter | `_rpc_catch(grab_id, crew, peer, at, victim, crew_at)` | host -> all | caught: cohort, hold anchors, the gotcha timeline |
| Encounter | `_rpc_request_wriggle()` | owner -> host | at most `CATCH_WRIGGLE_RATE`/s |
| Encounter | `_rpc_cite_end(peer, end_at)` | host -> all | the cite runs longer |
| Encounter | `_rpc_stage(peer, stage, at, crew, args)` | host -> all | ESCORT, BOARDING, SEATED, RIDING, ANNEX, RETURNING, FREE |
| Encounter | `_rpc_freed(peer, by_peer, cause, at)` | host -> all | bonk, unbuckle, wriggle, gone |
| CrewMember | `mode`, `mode_at`, `mode_peer`, `mode_arg` | Synchronizer, ON_CHANGE, spawn | what each NICE BOY is doing |
| CrewMember | `_rpc_bark(kind, index)` | host -> all | a bark line |
| Hotbar | `_rpc_itemized(at, index)` | host -> all | one item out of the itemized row (its tick) |

Lag: the wind-up's lead (0.35 s + up to 0.15 s of the target's half round trip) doubles as network lead, so a 150 ms client sees all of it; reach is judged in the host's view plus `CREW_GRAB_SLACK`. The gotcha and the escort place both bodies from anchors on every peer (chunk 1's `set_staged` for the player; the crew's own placement), so the pair never tears apart. Disconnects: a target mid-windup cancels the grab; a caught player who leaves frees the NICE BOY back to the chase (`_rpc_freed(..., "gone")`).

## The Courtesy Shuttle (R2:4, net/run_events/shuttle.gd)

One van per trip. Its pose is a pure function of the trip's legs and `Net.server_time()`; the host only sends the plan when it grows, each new leg `VAN_PLAN_LEAD` ahead. Everything is reliable on channel 0 and lives on `World/RunDirector/Shuttle` (a stable path, created on every peer by the director).

| RPC | Direction | What |
| --- | --- | --- |
| `_rpc_plan(trip_id, legs, info)` | host to all | the whole leg list and the trip's info (purpose, park, drop, zone, beats) |
| `_rpc_info(trip_id, info)` | host to all | info changed (a return trip's drop) |
| `_rpc_raid(trip_id)` | host to all | which trip is the raid's van |
| `_rpc_door(trip_id, which, open, at)` | host to all | the sliding door (`side`) or the back doors slide or swing at server time `at` |
| `_rpc_seat(trip_id, peer, seat, at, mode, from)` | host to all | a rider boards: walk in, step up, or at once; every peer stages the body from its anchor |
| `_rpc_unseat(trip_id, peer, exit, at)` | host to all | a rider unbuckles and steps down to `exit` |
| `_rpc_release_riders(trip_id, at, handed_on)` | host to all | the Annex (handed_on: it re-stages them from the seats) or Border Return (unstaged at once, before its lane teleport) has the riders now |
| `_rpc_crew_seat(trip_id, crew_index, seat, at, mode, from)` | host to all | a NICE BOY sits, climbs out, climbs in, or hops on the bumper |
| `_rpc_beat(trip_id, kind, at)` | host to all | cosmetic beats: the blinker, the whistle, the driver's wave, a honk |
| `_rpc_knock(trip_id, peer, at)` | host to all | a rider's knock on the glass |
| `_rpc_end_trip(trip_id)` | host to all | the trip is over; each peer frees its van once it can't see it |
| `_rpc_request_knock()` | client to host | a seated rider pressed primary |
| `_rpc_request_unbuckle(target, start)` | client to host | a hold on the door begins (`start`) or claims it was held long enough; the host times it itself |
| `_rpc_request_snapshot()` / `_rpc_snapshot(data)` | client to host / back | a late joiner's trips, until the R2 director's `_rpc_state` carries `snapshot()` |

Host checks: an unbuckle needs the rescuer free and within `VAN_DOOR_REACH` of the door step, the rider settled in a parked van with its door open, no mirror check at the start, the end or in between, no NICE BOY who can see the rescuer within `VAN_GUARD_RADIUS`, and a hold of at least `VAN_UNBUCKLE_HOLD - 0.15` s by the host's clock. Mirror checks are a pure function of the trip id and the time since the hold began, so every peer sees the same glints.
