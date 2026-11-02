extends Node

## Authority: local presentation. How a vehicle this peer doesn't simulate is
## drawn: the host's pose snapshots (chefty_drive.gd _rpc_snap, 30 a second)
## buffered and played back Constants.CHEFTY_VIEW_DELAY behind, on physics ticks.
## Riders are placed on their seats on physics ticks too (player.gd, priority
## 100), so this runs at priority 50, between the vehicle (0) and them: they sit
## on this tick's pose and physics interpolation smooths both the same way
## (docs/DECISIONS.md 2026-10-19). Not NetSmoother: that one works per rendered
## frame, which made riders slide against their seats.
##
## The vehicle passes each snapshot to add_snap(); when active, every tick this
## calls owner.apply_view_pose(position, yaw, velocity, snapped). The arrival
## times are smoothed against the host's clock stamps, so network jitter doesn't
## wobble the playback.

## For the probe and drive_test: snapshots taken in, ticks that ran past the
## newest snapshot by more than CHEFTY_VIEW_EXTRAPOLATE (hitches), the longest
## wait between two snapshots, hard snaps, and the driver's own reconciliations
## (chefty_drive.gd counts corrections and the largest one, in meters).
static var stats: Dictionary = {"samples": 0, "hitches": 0, "max_gap_ms": 0.0, "snaps": 0, "corrections": 0, "max_correction_m": 0.0}

## Drawn by this peer's playback (false on the host and for the driver).
var active: bool = false
## The node whose apply_view_pose() places the rendered body.
var vehicle: Node

## [{at (local seconds, smoothed), pos, yaw, vel}], oldest first.
var _buffer: Array[Dictionary] = []
var _offset: float = NAN
var _last_arrival: float = -1.0
var _last_drawn := Vector3.INF


func _ready() -> void:
	process_physics_priority = 50


static func reset_stats() -> void:
	stats = {"samples": 0, "hitches": 0, "max_gap_ms": 0.0, "snaps": 0, "corrections": 0, "max_correction_m": 0.0}


## A snapshot from the host: its server time t and the pose then.
func add_snap(t: float, pos: Vector3, yaw: float, vel: Vector3) -> void:
	var now := _now()
	if _last_arrival >= 0.0:
		stats["max_gap_ms"] = maxf(float(stats["max_gap_ms"]), (now - _last_arrival) * 1000.0)
	_last_arrival = now
	stats["samples"] = int(stats["samples"]) + 1
	# Arrival minus the host's stamp: take a lower one at once (a fast packet
	# shows the real delay), drift slowly up toward a higher one.
	var seen := now - t
	if is_nan(_offset) or seen < _offset:
		_offset = seen
	else:
		_offset = lerpf(_offset, seen, 0.02)
	var at := t + _offset
	if not _buffer.is_empty() and at <= float(_buffer[_buffer.size() - 1]["at"]):
		return
	_buffer.append({"at": at, "pos": pos, "yaw": yaw, "vel": vel})
	while _buffer.size() > 24:
		_buffer.pop_front()


## Forget the buffer (the vehicle was placed by other means).
func clear() -> void:
	_buffer.clear()
	_last_drawn = Vector3.INF


## The newest snapshot's pose, or {} with none yet.
func latest() -> Dictionary:
	return {} if _buffer.is_empty() else _buffer[_buffer.size() - 1]


func _physics_process(_delta: float) -> void:
	if not active or vehicle == null or _buffer.is_empty():
		return
	var render := _now() - Constants.CHEFTY_VIEW_DELAY
	while _buffer.size() > 2 and float(_buffer[1]["at"]) <= render:
		_buffer.pop_front()
	var pos: Vector3
	var yaw: float
	var vel: Vector3
	var first: Dictionary = _buffer[0]
	var newest: Dictionary = _buffer[_buffer.size() - 1]
	if render <= float(first["at"]):
		pos = first["pos"]
		yaw = first["yaw"]
		vel = first["vel"]
	elif _buffer.size() >= 2 and render <= float(_buffer[1]["at"]):
		var second: Dictionary = _buffer[1]
		var span := maxf(float(second["at"]) - float(first["at"]), 0.0001)
		var share := clampf((render - float(first["at"])) / span, 0.0, 1.0)
		pos = (first["pos"] as Vector3).lerp(second["pos"], share)
		yaw = lerp_angle(float(first["yaw"]), float(second["yaw"]), share)
		vel = (first["vel"] as Vector3).lerp(second["vel"], share)
	else:
		# Past the newest: carry on along its velocity for a moment, then wait.
		var ahead := render - float(newest["at"])
		if ahead > Constants.CHEFTY_VIEW_EXTRAPOLATE:
			stats["hitches"] = int(stats["hitches"]) + 1
		ahead = minf(ahead, Constants.CHEFTY_VIEW_EXTRAPOLATE)
		vel = newest["vel"]
		pos = (newest["pos"] as Vector3) + vel * ahead
		yaw = newest["yaw"]
	var snapped := _last_drawn == Vector3.INF or _last_drawn.distance_to(pos) > Constants.CHEFTY_VIEW_SNAP_METERS
	if snapped and _last_drawn != Vector3.INF:
		stats["snaps"] = int(stats["snaps"]) + 1
	_last_drawn = pos
	vehicle.call("apply_view_pose", pos, yaw, vel, snapped)


func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0
