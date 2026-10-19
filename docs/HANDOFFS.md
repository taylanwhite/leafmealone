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

### [NET → PLAY] 2026-10-18: voice output on each head, speaking indicator, voice settings
- Need: the M4 PLAY voice task. For each remote player, an AudioStreamPlayer3D on `Visual/Head` with `attenuation_model` inverse distance, `unit_size = Constants.VOICE_CLEAR_DISTANCE`, and `max_distance = Constants.VOICE_MAX_DISTANCE`, handed to `Net.attach_voice_output(peer_id, player)` once (Net sets the stream and starts it). A speaking indicator over each player and in the lobby from `Net.speaking_changed` or `Net.is_player_speaking()`. A voice settings screen using `Net.set_voice_mode()`, `Net.set_player_volume()`, and `Net.set_player_muted()`, plus a message when `Net.voice_available()` is false.
- Why: NET's half of proximity voice is in `net/voice/voice.gd` and passes an 8-player bot soak.
- Stub on my side: until a head calls `attach_voice_output`, `net/voice/voice.gd` adds its own `VoiceStub` AudioStreamPlayer3D to `Visual/Head` with those settings. Once PLAY attaches its own player, the stub is freed for that peer, and `_attach_stub` can be deleted.
- Blocking? no. Voice plays through the stub today. Push-to-talk is the `push_to_talk` action (V).

## Done

_(none yet)_
