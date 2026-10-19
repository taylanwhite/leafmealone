extends RefCounted

## Authority: local. A stand-in microphone for --voice-test. Produces 16-bit mono
## PCM of a quiet sine tone in talk bursts, so voice can be tested end to end in
## ENet sessions and by bots. The pitch differs per process so speakers can be
## told apart by ear.

const TALK_SECONDS := Vector2(1.5, 3.0)
const QUIET_SECONDS := Vector2(1.0, 2.5)
const AMPLITUDE: float = 0.2

var _rate: int
var _rng := RandomNumberGenerator.new()
var _pitch: float
var _phase: float = 0.0
var _talking: bool = false
var _left: float = 0.0
var _carry: float = 0.0


func _init(sample_rate: int) -> void:
	_rate = sample_rate
	_rng.seed = hash(OS.get_process_id()) + 7
	_pitch = _rng.randf_range(180.0, 420.0)
	_left = _rng.randf_range(QUIET_SECONDS.x, QUIET_SECONDS.y)


## PCM for the last delta seconds, or nothing during a quiet spell.
func take(delta: float) -> PackedByteArray:
	_left -= delta
	if _left <= 0.0:
		_talking = not _talking
		var span := TALK_SECONDS if _talking else QUIET_SECONDS
		_left = _rng.randf_range(span.x, span.y)
	if not _talking:
		_carry = 0.0
		return PackedByteArray()
	var exact := delta * _rate + _carry
	var count := int(exact)
	_carry = exact - count
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var step := TAU * _pitch / _rate
	for index: int in count:
		pcm.encode_s16(index * 2, int(sin(_phase) * AMPLITUDE * 32767.0))
		_phase = fmod(_phase + step, TAU)
	return pcm
