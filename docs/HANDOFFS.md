# Handoffs

Requests from one lane to the other. Agents check the Open section at the start of every session for anything addressed to their lane.

How to use it:

- Add a request at the bottom of Open with the template below, commit it with a `[SHARED]` prefix, and push.
- If you can keep working with a stub on your side, do that and describe the stub so it is easy to remove later.
- The receiving lane moves the entry to Done with the commit that resolved it.
- Talk to each other about anything urgent. This file is for the record, not a replacement for a message.

Template:

```
### [FROM → TO] YYYY-MM-DD: short title
- Need:
- Why:
- Stub on my side (if any):
- Blocking? yes/no
```

## Open

_(none)_

## Done

### [NET → PLAY] 2026-10-18: voice output on each head, speaking indicator, voice settings
- Need: the M4 PLAY voice task. For each remote player, an AudioStreamPlayer3D on `Visual/Head` with `attenuation_model` inverse distance, `unit_size = Constants.VOICE_CLEAR_DISTANCE`, and `max_distance = Constants.VOICE_MAX_DISTANCE`, handed to `Net.attach_voice_output(peer_id, player)` once (Net sets the stream and starts it). A speaking indicator over each player and in the lobby from `Net.speaking_changed` or `Net.is_player_speaking()`. A voice settings screen using `Net.set_voice_mode()`, `Net.set_player_volume()`, and `Net.set_player_muted()`, plus a message when `Net.voice_available()` is false.
- Why: NET's half of proximity voice is in `net/voice/voice.gd` and passes an 8-player bot soak.
- Stub on my side: until a head calls `attach_voice_output`, `net/voice/voice.gd` adds its own `VoiceStub` AudioStreamPlayer3D to `Visual/Head` with those settings. Once PLAY attaches its own player, the stub is freed for that peer, and `_attach_stub` can be deleted.
- Blocking? no. Voice plays through the stub today. Push-to-talk is the `push_to_talk` action (V).
- Resolved: Taylan took over PLAY (see DECISIONS.md 2026-10-18). `player/player.gd` attaches a head voice player, `ui/voice_panel.gd` adds voice settings, and the stub is gone.

### [SHARED → driving] 2026-11-03: engine_state() and board_state() are what the sound reads (audio:7)
- Need: nothing new; this records the contracts (gap-specs/critic.md C13) now that the components exist. A vehicle hangs `audio/vehicle_sound.gd` under its drawn body and gives it `state_source` (or the parent answers `engine_state()`): `{on: bool, throttle: -1..1, speed: m/s (optional: read off the body's movement), skidding: bool}`, plus `seat_of(peer_id) -> int` on the vehicle so its own riders hear it at full volume, `profile` (`chefty`, `van`) and `top_speed`. A board hangs `audio/board_sound.gd` on the drawn board and gives it `board_state()`: `{on_board, speed, on_ground, grinding}`; `auto_edges = false` if it plays its own pop and landing.
- Why: chefty_drive.gd, ride.gd and skate_view.gd use them now; driving:F's `nice_van.gd` can attach `vehicle_sound.gd` with `profile = &"van"` instead of building its own loop.
- Stub on my side: none. skate_view.gd's own roll and grind loops and chefty_drive.gd's own engine loop and skid are dead fallbacks now; delete them whenever convenient.
- Blocking? no.
- Resolved: audio:7 (docs/DECISIONS.md "Audio: the engine and the board are components").