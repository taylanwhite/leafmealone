extends RefCounted

## Estimates the host clock on a client from ping samples.
## Authority: host clock, estimated on clients.
##
## Every sample bounds the offset (host minus local): the host read its clock
## somewhere between the ping leaving and the pong coming back, so the offset is
## at least host - received and at most host - sent. Over the window the tightest
## bounds are kept and the estimate is the middle of what's left (fx-net). A
## loaded peer only reads the network once a frame, so a ping or a pong can sit a
## whole frame before anyone sees it: the old "lowest round trip wins" needed one
## sample lucky both ways at once, and was off by half a frame's wait whenever it
## wasn't (the stage test's client body 35 ms off its host's under load). The
## bounds take each side's luckiest sample on its own.
##
## A --fixed-step run counts game ticks, and two starved windows tick at
## different rates, so there the offset itself moves: it's fitted as a line
## (offset at a time, and how fast it changes) and the applied clock carries that
## rate, never snapping a little every few seconds as the stale estimate drifted.

const SAMPLE_WINDOW_SECONDS: float = 10.0
## How fast the client's clock may run fast or slow while it catches up to a new
## estimate, as a share of real time. Corrections used to land as jumps, and a ride
## moving at ride speed jumped meters with every ping.
const SLEW_RATE: float = 0.05
## An error bigger than this snaps instead (the first sample, or a hitch).
const SNAP_SECONDS: float = 0.25

## Dev only (--fixed-step, docs/PLAYTEST.md): count game time, physics ticks,
## instead of the wall clock, so a fixed-step run that falls behind real time
## slows down as a whole instead of its clock running ahead of its physics.
var game_ticks: bool = false
## Dev only (--clock-skew=S, P1 catch): a client's estimate held S s off the host's
## clock, the way a starved window's drifted (crew playtest 1). 0 in every real run.
var dev_skew: float = 0.0
var _origin_usec: int = 0
var _origin_ticks: int = 0
## The estimate: offset _offset_seconds at local time _offset_at, changing by
## _rate seconds a second (0 unless game_ticks).
var _offset_seconds: float = 0.0
var _offset_at: float = 0.0
var _rate: float = 0.0
## The offset actually used: walks toward the estimate, never jumps.
var _applied_offset: float = 0.0
var _applied_at: float = 0.0
var _applied_started: bool = false
## The last server time handed out (a client's never runs backwards).
var _last_served: float = -INF
var _last_rtt_seconds: float = 0.0
var _has_sample: bool = false
## {sent, received, host} (local seconds, local seconds, host seconds).
var _samples: Array[Dictionary] = []
## The last estimate's bounds on the offset (low, high).
var _bounds := Vector2.ZERO
## For the tests and the probe: estimates whose bounds didn't meet (fell back
## to the lowest round trip), and backward snaps held instead of taken.
var stats: Dictionary = {"samples": 0, "crossed": 0, "held_back": 0, "snaps": 0}


func start() -> void:
	_origin_usec = Time.get_ticks_usec()
	_origin_ticks = Engine.get_physics_frames()
	_offset_seconds = 0.0
	_offset_at = 0.0
	_rate = 0.0
	_applied_offset = 0.0
	_applied_started = false
	_last_served = -INF
	_has_sample = false
	_samples.clear()
	stats = {"samples": 0, "crossed": 0, "held_back": 0, "snaps": 0}


## Seconds since the session started on the host. On a client this is the estimate.
func server_seconds(is_host: bool) -> float:
	if is_host:
		return _local_seconds()
	var now := _local_seconds()
	_slew(now)
	# Never backwards (a slew step under float noise): everything scheduled from
	# server time (the van's doors, the Annex's desk, a catch's beats) only ever
	# sees it hold still for a moment. A dev skew is the caller's own jump.
	var served := maxf(now + _applied_offset, _last_served)
	_last_served = served
	return served + dev_skew


## The offset the estimate gives at local time at.
func _target(at: float) -> float:
	return _offset_seconds + _rate * (at - _offset_at)


## Walk the applied offset toward the estimate: it runs at the estimate's rate,
## plus at most SLEW_RATE to close the gap, so time on a client moves smoothly
## and never runs backwards. A gap past SNAP_SECONDS forward snaps; one backward
## is closed at half speed instead (a client clock that jumped back replayed
## things already scheduled).
func _slew(now: float) -> void:
	if not _has_sample:
		return
	var target := _target(now)
	if not _applied_started or int(stats["samples"]) <= Constants.CLOCK_YOUNG_SAMPLES:
		# The first pings of a session (a joiner is still building the world, and
		# they came back through its loading stalls): the bounds narrow fast, and
		# each step is taken at once rather than slewed for seconds
		# (fx-net: a 145 ms improvement still trailed by 70 ms when stage_test began).
		_applied_offset = target
		_applied_started = true
		_applied_at = now
		return
	var dt := maxf(now - _applied_at, 0.0)
	_applied_at = now
	_applied_offset += _rate * dt
	var error := target - _applied_offset
	if error > SNAP_SECONDS:
		_applied_offset = target
		stats["snaps"] = int(stats["snaps"]) + 1
		return
	var step := SLEW_RATE * dt
	if error < -SNAP_SECONDS:
		step = Constants.CLOCK_BACK_SLEW * dt
		stats["held_back"] = int(stats["held_back"]) + 1
	_applied_offset += clampf(error, -step, step)


func local_seconds() -> float:
	return _local_seconds()


## The offset in use now (host minus local, s): what server time is built from.
func offset_seconds() -> float:
	_slew(_local_seconds())
	return _applied_offset


## The estimate now (host minus local, s), which the offset in use walks toward.
func estimate_seconds() -> float:
	return _target(_local_seconds())


## How fast the estimate's offset changes (s a second; 0 off a fixed step).
func rate() -> float:
	return _rate


## For the tests: how far the applied offset trails the estimate now (s), and the
## estimate's bounds' width at the last sample (s; negative when they crossed).
func lag_and_width() -> Vector2:
	return Vector2(estimate_seconds() - offset_seconds(), _bounds.y - _bounds.x)


func last_rtt_seconds() -> float:
	return _last_rtt_seconds


func has_sample() -> bool:
	return _has_sample


func note_sample(sent_local_seconds: float, host_seconds: float, received_local_seconds: float) -> void:
	var rtt := received_local_seconds - sent_local_seconds
	if rtt < 0.0:
		return
	_last_rtt_seconds = rtt
	_has_sample = true
	stats["samples"] = int(stats["samples"]) + 1
	_samples.append({"sent": sent_local_seconds, "received": received_local_seconds, "host": host_seconds})
	var window := Constants.CLOCK_RATE_WINDOW if game_ticks else SAMPLE_WINDOW_SECONDS
	var cutoff := received_local_seconds - window
	var kept: Array[Dictionary] = []
	for sample: Dictionary in _samples:
		if float(sample["received"]) >= cutoff:
			kept.append(sample)
	_samples = kept
	if game_ticks:
		_fit_rate()
	_estimate(received_local_seconds)


## The offset at local time now: the middle of every sample's bounds that still
## overlap (carried to now at the fitted rate); if they don't (a rate change on a
## fixed step, a stall mid-ping), the lowest round trip's middle.
func _estimate(now: float) -> void:
	var low := -INF
	var high := INF
	var best_rtt := INF
	var best := 0.0
	for sample: Dictionary in _samples:
		var sent := float(sample["sent"])
		var received := float(sample["received"])
		var host := float(sample["host"])
		var drift := _rate * (now - (sent + received) * 0.5)
		low = maxf(low, host - received + drift)
		high = minf(high, host - sent + drift)
		if received - sent < best_rtt:
			best_rtt = received - sent
			best = host + (received - sent) * 0.5 - received + drift
	_offset_at = now
	_bounds = Vector2(low, high)
	if low <= high:
		_offset_seconds = (low + high) * 0.5
	else:
		_offset_seconds = best
		stats["crossed"] = int(stats["crossed"]) + 1


## A fixed step only: how fast the offset moves, a line through the window's
## quicker samples' middles (least squares). Too few, or too short a stretch, keeps
## the last rate.
func _fit_rate() -> void:
	var best_rtt := INF
	for sample: Dictionary in _samples:
		best_rtt = minf(best_rtt, float(sample["received"]) - float(sample["sent"]))
	var limit := best_rtt + maxf(Constants.CLOCK_RATE_RTT_SLACK, best_rtt * 0.5)
	var xs: Array[float] = []
	var ys: Array[float] = []
	for sample: Dictionary in _samples:
		var sent := float(sample["sent"])
		var received := float(sample["received"])
		if received - sent > limit:
			continue
		xs.append((sent + received) * 0.5)
		ys.append(float(sample["host"]) - (sent + received) * 0.5)
	if xs.size() < Constants.CLOCK_RATE_MIN_SAMPLES or xs[xs.size() - 1] - xs[0] < Constants.CLOCK_RATE_MIN_SPAN:
		return
	var mean_x := 0.0
	var mean_y := 0.0
	for index: int in xs.size():
		mean_x += xs[index]
		mean_y += ys[index]
	mean_x /= float(xs.size())
	mean_y /= float(xs.size())
	var top := 0.0
	var bottom := 0.0
	for index: int in xs.size():
		top += (xs[index] - mean_x) * (ys[index] - mean_y)
		bottom += (xs[index] - mean_x) * (xs[index] - mean_x)
	if bottom > 0.0:
		_rate = clampf(top / bottom, -Constants.CLOCK_RATE_MAX, Constants.CLOCK_RATE_MAX)


func _local_seconds() -> float:
	if game_ticks:
		return float(Engine.get_physics_frames() - _origin_ticks) / float(Engine.physics_ticks_per_second)
	return float(Time.get_ticks_usec() - _origin_usec) / 1000000.0
