extends Node

## Authority: each peer for its own voice. Every peer plays everyone else's.
## Proximity voice from docs/NETCODE.md. In Steam sessions it captures with
## Steam, sends compressed packets to every other peer on channel 2, and plays
## each speaker through an AudioStreamPlayer3D on their head, so distance does
## the mixing. ENet sessions have no voice, except the synthetic --voice-test
## tone that tools/soak.sh uses to test this whole path without a microphone.

enum Codec { STEAM, PCM16 }

## Steam decodes at any rate from 11025 to 48000 Hz. 16 kHz is clear speech and
## keeps the per-sample conversion loop cheap with eight players talking.
const SAMPLE_RATE: int = 16000
## Largest raw PCM packet, an even number of bytes well under ENet's 1392-byte MTU.
const MAX_PCM_PACKET_BYTES: int = 1024
## How often captured audio is sent.
const SEND_INTERVAL: float = 0.04
## Audio held back before a speaker starts playing, to ride out network jitter.
const PREBUFFER_SECONDS: float = 0.08
## Most audio held per speaker. Past this the oldest is dropped so delay can't build up.
const MAX_QUEUE_SECONDS: float = 0.4
## Playback buffer on each speaker's AudioStreamGenerator.
const GENERATOR_SECONDS: float = 0.5
## A speaker counts as speaking until this long after their last packet.
const SPEAKING_HOLD_SECONDS: float = 0.3

const _ToneScript = preload("res://net/dev/voice_tone.gd")

## Totals for this process, read by net/dev/probe.gd.
static var stats: Dictionary = {}

var _mode: int = 0
var _recording: bool = false
var _send_wait: float = 0.0
var _seq: int = 0
var _outgoing := PackedByteArray()
var _tone: RefCounted
var _local_speaking: bool = false
var _local_last_sent: float = -INF
var _speakers: Dictionary = {}
var _volume: Dictionary = {}
var _muted: Dictionary = {}
var _latency_ms: Array[float] = []


func _ready() -> void:
	stats = {
		"sent_packets": 0, "sent_bytes": 0, "received_packets": 0, "lost_packets": 0,
		"decode_failures": 0, "underruns": 0, "dropped_seconds": 0.0, "speaking_changes": 0,
		"heard_from": {},
	}
	if bool(Net.dev_options().get("voice_test")):
		_tone = _ToneScript.new(SAMPLE_RATE)
		print("[Voice] sending a test tone instead of a microphone")
	Net.player_left.connect(_on_player_left)


## True when this session can carry voice: Steam, or the --voice-test tone.
func is_available() -> bool:
	return _tone != null or (Net.current_transport() == Net.Transport.STEAM and _bridge_ready())


func set_mode(mode: int) -> void:
	_mode = mode


func mode() -> int:
	return _mode


func set_volume(peer_id: int, volume_linear: float) -> void:
	_volume[peer_id] = maxf(volume_linear, 0.0)


func volume(peer_id: int) -> float:
	return float(_volume.get(peer_id, 1.0))


func set_muted(peer_id: int, muted: bool) -> void:
	_muted[peer_id] = muted


func is_muted(peer_id: int) -> bool:
	return bool(_muted.get(peer_id, false))


func is_speaking(peer_id: int) -> bool:
	if peer_id == Net.local_peer_id():
		return _local_speaking
	return _speakers.has(peer_id) and bool(_speakers[peer_id]["speaking"])


## Play one remote player's voice through this player, the AudioStreamPlayer3D
## that player.gd puts on their head. Called again when the player respawns.
func attach_output(peer_id: int, player: AudioStreamPlayer3D) -> void:
	var speaker := _speaker(peer_id)
	var generator := AudioStreamGenerator.new()
	generator.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = GENERATOR_SECONDS
	player.stream = generator
	player.play()
	speaker["player"] = player
	speaker["playback"] = player.get_stream_playback()
	speaker["started"] = false


## Latency of received voice in milliseconds, from the sender's server time.
func latency_samples() -> Array[float]:
	return _latency_ms


func _process(delta: float) -> void:
	if Net.current_state() != Net.State.IN_SESSION or multiplayer.multiplayer_peer == null:
		_set_recording(false)
		return
	if is_available():
		_capture(delta)
	_play()
	_update_speaking()


func _capture(delta: float) -> void:
	_send_wait += delta
	if _tone != null:
		_outgoing.append_array(_tone.call("take", delta))
		if _send_wait >= SEND_INTERVAL:
			_send_wait = 0.0
			if not _outgoing.is_empty():
				_send(Codec.PCM16, _outgoing)
				_outgoing = PackedByteArray()
		return
	_set_recording(_wants_to_transmit())
	if _send_wait < SEND_INTERVAL:
		return
	_send_wait = 0.0
	# Keep reading after recording stops, so the end of a sentence still goes out.
	var data: PackedByteArray = _bridge().call("voice_read")
	if not data.is_empty():
		_send(Codec.STEAM, data)


func _wants_to_transmit() -> bool:
	if _mode == Net.VoiceMode.VOICE_ACTIVATION:
		# Steam only returns data while it hears speech, so recording all the time is fine.
		return true
	return Input.is_action_pressed(&"push_to_talk")


func _set_recording(value: bool) -> void:
	if value == _recording:
		return
	_recording = value
	if not _bridge_ready():
		return
	_bridge().call("voice_start" if value else "voice_stop")


func _send(codec: Codec, data: PackedByteArray) -> void:
	# Raw PCM can be cut anywhere on a sample, so keep each packet under the MTU.
	# Steam's compressed voice is already small and can't be cut.
	if codec == Codec.PCM16 and data.size() > MAX_PCM_PACKET_BYTES:
		var offset := 0
		while offset < data.size():
			_send(codec, data.slice(offset, offset + MAX_PCM_PACKET_BYTES))
			offset += MAX_PCM_PACKET_BYTES
		return
	_seq += 1
	stats["sent_packets"] = int(stats["sent_packets"]) + 1
	stats["sent_bytes"] = int(stats["sent_bytes"]) + data.size()
	_local_last_sent = _now()
	_rpc_voice.rpc(int(codec), _seq, Net.server_time(), data)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _rpc_voice(codec: int, seq: int, sent_at: float, data: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == Net.local_peer_id():
		return
	var speaker := _speaker(sender)
	var last_seq := int(speaker["seq"])
	if last_seq > 0 and seq > last_seq + 1:
		stats["lost_packets"] = int(stats["lost_packets"]) + seq - last_seq - 1
	speaker["seq"] = seq
	stats["received_packets"] = int(stats["received_packets"]) + 1
	var heard: Dictionary = stats["heard_from"]
	heard[sender] = int(heard.get(sender, 0)) + 1
	if Net.has_clock_sample() or Net.is_host():
		if _latency_ms.size() < 5000:
			_latency_ms.append((Net.server_time() - sent_at) * 1000.0)
	var pcm := data
	if codec == Codec.STEAM:
		pcm = _bridge().call("voice_decode", data, SAMPLE_RATE) if _bridge_ready() else PackedByteArray()
	if pcm.size() < 2:
		stats["decode_failures"] = int(stats["decode_failures"]) + 1
		return
	_count_underrun(speaker)
	speaker["last_packet"] = _now()
	_queue_pcm(sender, speaker, pcm)


## The generator skips whenever it runs dry, including after every burst ends.
## Only a skip between two packets of the same burst is an audible gap.
func _count_underrun(speaker: Dictionary) -> void:
	var playback := speaker["playback"] as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var skips := playback.get_skips()
	var mid_burst := _now() - float(speaker["last_packet"]) < SPEAKING_HOLD_SECONDS
	if bool(speaker["started"]) and mid_burst and skips > int(speaker["skips"]):
		stats["underruns"] = int(stats["underruns"]) + 1
	speaker["skips"] = skips


func _queue_pcm(peer_id: int, speaker: Dictionary, pcm: PackedByteArray) -> void:
	var gain := 0.0 if is_muted(peer_id) else volume(peer_id)
	var count := pcm.size() / 2
	var frames := PackedVector2Array()
	frames.resize(count)
	for index: int in count:
		var sample := float(pcm.decode_s16(index * 2)) / 32768.0 * gain
		frames[index] = Vector2(sample, sample)
	var queue: PackedVector2Array = speaker["queue"]
	queue.append_array(frames)
	var limit := int(MAX_QUEUE_SECONDS * SAMPLE_RATE)
	if queue.size() > limit:
		var excess := queue.size() - limit
		stats["dropped_seconds"] = float(stats["dropped_seconds"]) + float(excess) / SAMPLE_RATE
		queue = queue.slice(excess)
	speaker["queue"] = queue


func _play() -> void:
	var now := _now()
	for peer_id: int in _speakers.keys():
		var speaker: Dictionary = _speakers[peer_id]
		var queue: PackedVector2Array = speaker["queue"]
		if queue.is_empty():
			continue
		var playback := speaker["playback"] as AudioStreamGeneratorPlayback
		if playback == null or not is_instance_valid(speaker["player"]):
			# No head to play from yet (or it was freed). Keep only the newest audio.
			continue
		if not bool(speaker["started"]):
			# Hold the start of each burst until there is enough to ride out jitter.
			if queue.size() < int(PREBUFFER_SECONDS * SAMPLE_RATE):
				continue
			speaker["started"] = true
			speaker["skips"] = playback.get_skips()
		var count := mini(playback.get_frames_available(), queue.size())
		if count > 0:
			playback.push_buffer(queue.slice(0, count))
			queue = queue.slice(count)
			speaker["queue"] = queue
	for peer_id: int in _speakers.keys():
		var speaker: Dictionary = _speakers[peer_id]
		var talking := now - float(speaker["last_packet"]) < SPEAKING_HOLD_SECONDS
		if bool(speaker["started"]) and not talking and (speaker["queue"] as PackedVector2Array).is_empty():
			speaker["started"] = false


func _update_speaking() -> void:
	var now := _now()
	var local_now := now - _local_last_sent < SPEAKING_HOLD_SECONDS
	if local_now != _local_speaking:
		_local_speaking = local_now
		_announce(Net.local_peer_id(), local_now)
	for peer_id: int in _speakers.keys():
		var speaker: Dictionary = _speakers[peer_id]
		var speaking := now - float(speaker["last_packet"]) < SPEAKING_HOLD_SECONDS
		if speaking != bool(speaker["speaking"]):
			speaker["speaking"] = speaking
			_announce(peer_id, speaking)


func _announce(peer_id: int, speaking: bool) -> void:
	stats["speaking_changes"] = int(stats["speaking_changes"]) + 1
	Net.speaking_changed.emit(peer_id, speaking)


func _speaker(peer_id: int) -> Dictionary:
	if not _speakers.has(peer_id):
		_speakers[peer_id] = {
			"queue": PackedVector2Array(), "player": null, "playback": null,
			"started": false, "skips": 0, "seq": 0, "last_packet": -INF, "speaking": false,
		}
	return _speakers[peer_id]


func _on_player_left(peer_id: int) -> void:
	if not _speakers.has(peer_id):
		return
	if bool(_speakers[peer_id]["speaking"]):
		_announce(peer_id, false)
	_speakers.erase(peer_id)


func _bridge() -> Node:
	return get_parent().get_node_or_null("SteamBridge")


func _bridge_ready() -> bool:
	var bridge := _bridge()
	return bridge != null and bool(bridge.get("available"))


func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0
