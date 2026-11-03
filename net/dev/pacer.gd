extends Node

## Authority: local, dev only. --fixed-step=N (with the engine's --fixed-fps N,
## docs/PLAYTEST.md): the engine then steps exactly 1/N s of game time a frame
## but stops syncing to real time, so it runs as fast as it can. This holds the
## game back to real time, sleeping off whatever it's ahead by. A machine too
## busy to keep up just runs slower than real time (slow motion, still evenly
## stepped): it never races to catch up. Net's clock counts the same game time
## then (net/clock_sync.gd), so rides and raids slow down with everything else.

## Behind by more than this, the game gives up the lost time instead of catching up.
const SLIP_SECONDS: float = 0.1

## Game seconds per real second over the last stretch (1 is real time).
static var realtime_ratio: float = 1.0

var _wall0_usec: int = 0
var _ticks0: int = 0
var _window_game: float = 0.0
var _window_start_usec: int = 0
var _paced_frame: int = -1


func _ready() -> void:
	process_priority = -2000
	process_physics_priority = -2000
	_wall0_usec = Time.get_ticks_usec()
	_ticks0 = Engine.get_physics_frames()
	print("[Pacer] fixed step at %d fps, held to real time" % int(Net.dev_options().get("fixed_step")))


## The wait happens at the first physics tick of each frame, before anything
## in the frame runs, so what the frame does (a sound asked for on a tick)
## happens at the real time its game time says.
func _physics_process(_delta: float) -> void:
	if Engine.get_process_frames() == _paced_frame:
		return
	_paced_frame = Engine.get_process_frames()
	var game := float(Engine.get_physics_frames() - 1 - _ticks0) / float(Engine.physics_ticks_per_second)
	var wall := float(Time.get_ticks_usec() - _wall0_usec) / 1000000.0
	var ahead := game - wall
	if ahead > 0.0:
		OS.delay_usec(int(ahead * 1000000.0))
	elif ahead < -SLIP_SECONDS:
		_wall0_usec += int((-ahead - SLIP_SECONDS) * 1000000.0)


func _process(delta: float) -> void:
	# A running ratio over two game seconds, for the logs.
	_window_game += delta
	if _window_game >= 2.0:
		var now := Time.get_ticks_usec()
		if _window_start_usec > 0:
			realtime_ratio = clampf(_window_game / maxf(float(now - _window_start_usec) / 1000000.0, 0.001), 0.0, 4.0)
		_window_start_usec = now
		_window_game = 0.0
