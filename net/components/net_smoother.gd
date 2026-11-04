class_name NetSmoother
extends Node

## Authority: owning peer for the latest snapshot, local for the rendered pose.
## Renders a visual about 100 ms behind the replicated body. The body itself stays
## on the latest snapshot so collisions match the network pose. A jump past
## snap_distance (a zone teleport) snaps instead of sliding across the map.

const MAX_EXTRAPOLATION_SECONDS: float = 0.1
## Horizontal speed above which a gap in updates counts as a hitch, in m/s.
const MOVING_SPEED: float = 0.5
## Unchanged this long counts as stopped (s): past a sync interval (0.033 s) with
## room for jitter, and inside delay_seconds so the visual never extrapolates
## past a stop.
const STOP_AFTER_SECONDS: float = 0.07

## Totals across every smoother in this process, read by net/dev/probe.gd.
## A hitch is a gap between updates longer than delay_seconds while the body was
## moving, which shows as a freeze and a jump. Assumes the mover never stands still,
## which holds for --bot players.
static var stats: Dictionary = {"samples": 0, "hitches": 0, "max_gap_ms": 0.0, "snaps": 0}
## Each hitch as [when it ended (local seconds, _now), the gap in seconds, the
## mover's authority peer], so tools/soak_report.py can set it against stalls.
static var hitch_log: Array = []
const HITCH_LOG_MAX: int = 4000

## How far behind the newest snapshot the visual is rendered, in seconds.
@export var delay_seconds: float = 0.1
## Distance from the latest snapshot at which the visual snaps, in meters.
@export var snap_distance: float = 3.0
## Child that is drawn. The parent is the replicated body.
@export var visual_path: NodePath

var _visual: Node3D
var _samples: Array[Dictionary] = []
var _last_recorded := Vector3(INF, INF, INF)
var _last_basis := Basis.IDENTITY
## When the replicated pose last changed (an update arrived) and how fast it
## was going then, and whether the one stop copy after it is in.
var _last_change_at: float = 0.0
var _last_change_speed: float = 0.0
var _stop_recorded: bool = false


func _ready() -> void:
	_visual = get_node_or_null(visual_path) as Node3D
	if _visual == null:
		push_error("[NetSmoother] visual_path does not point at a Node3D")
		set_physics_process(false)
		set_process(false)
		return
	# Where the visual sits on its body (a yard prop's is 0.35 m up), kept when smoothing.
	_rest = _visual.transform


func _physics_process(_delta: float) -> void:
	if _is_local_authority() or _visual == null:
		return
	if _parent_places_visual():
		_samples.clear()
		_was_placed = true
		return
	var body := get_parent() as Node3D
	if body == null:
		return
	if _was_placed:
		resume_from_drawn()
	var origin := body.global_position
	var now := _now()
	var basis := body.global_basis
	if _held:
		var unchanged := origin.distance_squared_to(_last_recorded) < 0.0000001 and basis.is_equal_approx(_last_basis)
		var waited := now - _hold_since
		# Still on a seat on its own peer (its truck can trail this one's, or it
		# waits its turn to hop down): what it replicates is that seat, not where
		# it's drawn here, so it stays drawn on this one's.
		var seated := int(body.get(&"seat_state")) == SEAT_STATE_SEATED if "seat_state" in body else false
		if (seated and waited < Constants.SMOOTHER_SEAT_HOLD_MAX) or (unchanged and waited < HOLD_MAX_SECONDS):
			return
		# Off it now (or nothing new came: the replicated pose was right all
		# along): blend from where it's drawn into the stream from here on.
		_held = false
		_blend_from = _samples[0]["xform"] if not _samples.is_empty() else body.global_transform
		_blend_at = now
		_samples.clear()
		_last_recorded = Vector3.INF
	# Turning on the spot counts as a change too (a hired hand stops, then faces its
	# pile; a player turns while raking in place; a NICE BOY turning on a spot or a
	# stand): only a body that neither moved nor turned is unchanged.
	if origin.distance_squared_to(_last_recorded) < 0.0000001 and basis.is_equal_approx(_last_basis) and not _samples.is_empty():
		# Unchanged. Updates arrive at the sync interval, slower than physics, so
		# most of these are just the gap between two updates: record nothing.
		# Unchanged for longer than an update gap means it stopped: one copy where
		# it stopped, so the visual doesn't stay extrapolated past the stop (a dive
		# into a hedge left it 0.5 m underground).
		if _stop_recorded or now - _last_change_at < STOP_AFTER_SECONDS:
			return
		_stop_recorded = true
		# After the last update's playback time (it can be spaced a little ahead).
		_samples.append({"at": maxf(now, float(_samples[_samples.size() - 1]["at"]) + 0.001), "xform": body.global_transform, "speed": 0.0})
		_trim(now)
		return
	# Gaps are measured between updates, not to a stop copy.
	if not _samples.is_empty() and _last_change_speed > MOVING_SPEED:
		var gap := now - _last_change_at
		stats["max_gap_ms"] = maxf(float(stats["max_gap_ms"]), gap * 1000.0)
		if gap > delay_seconds:
			stats["hitches"] = int(stats["hitches"]) + 1
			if hitch_log.size() < HITCH_LOG_MAX:
				hitch_log.append([now, snappedf(gap, 0.001), body.get_multiplayer_authority()])
	# After a gap longer than the delay (a stall on either peer, updates bunched on
	# the way, or a body setting off after standing still), the rendered time is
	# already past the last update, so the new one would be drawn most of the way
	# there in one frame: a NICE BOY who turned through a host's stall snapped
	# 0.6 rad at once on a client (encounter_test step 2). Carry on from where it's
	# drawn: a sample of that, at the rendered time, so the catch-up takes
	# delay_seconds like any other stretch (fx-net).
	if not _samples.is_empty() and now - _last_change_at > delay_seconds:
		var drawn_at := now - delay_seconds
		if drawn_at > float(_samples[_samples.size() - 1]["at"]):
			_samples.append({"at": drawn_at, "xform": _sample_at(drawn_at), "speed": 0.0})
	stats["samples"] = int(stats["samples"]) + 1
	var velocity: Vector3 = body.get("velocity") if "velocity" in body else Vector3.ZERO
	_last_recorded = origin
	_last_basis = basis
	_last_change_at = now
	_last_change_speed = Vector2(velocity.x, velocity.z).length()
	_stop_recorded = false
	# Updates are sent at least a replication interval apart, but a loaded peer
	# reads the network once a frame, so two can land a tick apart: played back on
	# their arrival times, the second interval's motion took one tick (a NICE BOY
	# drawn turning 0.4-0.8 rad in a tick he turned over three). Each is played at
	# least SMOOTHER_MIN_SPACING after the last, never more than half the delay
	# ahead of its arrival (fx-net).
	var at := now
	if not _samples.is_empty():
		var spaced := float(_samples[_samples.size() - 1]["at"]) + Constants.SMOOTHER_MIN_SPACING
		at = clampf(spaced, now, now + delay_seconds * 0.5)
	_samples.append({"at": at, "xform": body.global_transform, "speed": _last_change_speed})
	_trim(now)


func _trim(now: float) -> void:
	var cutoff := now - delay_seconds - 1.0
	while _samples.size() > 2 and float(_samples[0]["at"]) < cutoff:
		_samples.remove_at(0)


func _process(_delta: float) -> void:
	if _is_local_authority() or _visual == null or _parent_places_visual():
		return
	# Off a seat or a stage since the last physics tick: from where it's drawn now.
	if _was_placed:
		resume_from_drawn()
	if _samples.is_empty():
		return
	var body := get_parent() as Node3D
	if body == null:
		return
	var rendered := _sample_at(_now() - delay_seconds)
	if _blend_at >= 0.0:
		var blend := (_now() - _blend_at) / maxf(maxf(Constants.SMOOTHER_RESUME_BLEND, delay_seconds), 0.001)
		if blend >= 1.0:
			_blend_at = -1.0
		else:
			rendered = _blend_from.interpolate_with(rendered, smoothstep(0.0, 1.0, blend))
	# Held where the seat or stage drew it: the replicated pose is from before the
	# hand-over (a ride at speed left it metres back up the road), so no snap to it.
	if not _held and rendered.origin.distance_to(body.global_position) > snap_distance:
		rendered = body.global_transform
		_blend_at = -1.0
		stats["snaps"] = int(stats["snaps"]) + 1
		_visual.reset_physics_interpolation()
		_samples.clear()
		_samples.append({"at": _now(), "xform": rendered, "speed": 0.0})
		_last_recorded = rendered.origin
		_last_basis = rendered.basis
		_last_change_at = _now()
		_last_change_speed = 0.0
		_stop_recorded = true
	_visual.global_transform = rendered * _rest


var _rest := Transform3D.IDENTITY
## The parent placed the visual itself last tick (a seat, a stage).
var _was_placed: bool = false
## Since that ended: drawing from where the seat or stage left the visual, while
## the body's own peer still has it seated (player.gd seat_state, up to
## Constants.SMOOTHER_SEAT_HOLD_MAX), then until the replicated pose next changes
## (or HOLD_MAX_SECONDS go by without one). Then, from _blend_at, it blends from
## where it was held (_blend_from) into the stream over SMOOTHER_RESUME_BLEND:
## releasing straight into it slid a rider back up the road at seat height (their
## own truck trailing), or skipped a hop already under way in one frame (review,
## p1-arrive). _blend_at is -1 when not blending.
var _held: bool = false
var _hold_since: float = 0.0
var _blend_from := Transform3D.IDENTITY
var _blend_at: float = -1.0
## For the tests: hand-overs from a seat or stage back to the smoother.
static var resumes: int = 0
const HOLD_MAX_SECONDS: float = 0.5
## player.gd SEAT_STATE_SEATED (the smoother runs on bodies that aren't players).
const SEAT_STATE_SEATED: int = 1


## The parent just stopped placing the visual (off a seat, out of a stage;
## p1-arrive): carry on from where it was drawn, never from the last replicated
## pose, which is from before the hand-over (riding at speed, metres back along
## the road: every peer saw a rider pop 2-4 m backwards as they stepped down).
## It stays there while the body's own peer still has it seated, then blends
## into the replicated stream (the owner's own step down). player.gd calls it the
## moment a seat lets go; otherwise it runs on the next tick or frame.
func resume_from_drawn() -> void:
	var body := get_parent() as Node3D
	if body == null or _visual == null or _is_local_authority():
		return
	_was_placed = false
	resumes += 1
	var drawn := _visual.global_transform * _rest.affine_inverse()
	_samples.clear()
	_samples.append({"at": _now(), "xform": drawn, "speed": 0.0})
	_last_recorded = body.global_position
	_last_basis = body.global_basis
	_last_change_at = _now()
	_last_change_speed = 0.0
	_stop_recorded = true
	_held = true
	_hold_since = _now()
	_blend_at = -1.0


func _sample_at(target_time: float) -> Transform3D:
	if _samples.size() == 1:
		return _samples[0]["xform"]
	var first_at := float(_samples[0]["at"])
	if target_time <= first_at:
		return _samples[0]["xform"]
	for index: int in range(_samples.size() - 1):
		var older: Dictionary = _samples[index]
		var newer: Dictionary = _samples[index + 1]
		var older_at := float(older["at"])
		var newer_at := float(newer["at"])
		if target_time <= newer_at:
			var span := newer_at - older_at
			var weight := 0.0 if span <= 0.0 else (target_time - older_at) / span
			var from: Transform3D = older["xform"]
			var to: Transform3D = newer["xform"]
			return from.interpolate_with(to, clampf(weight, 0.0, 1.0))
	var newest: Dictionary = _samples[_samples.size() - 1]
	var previous: Dictionary = _samples[_samples.size() - 2]
	var newest_at := float(newest["at"])
	var previous_at := float(previous["at"])
	var extra := minf(target_time - newest_at, MAX_EXTRAPOLATION_SECONDS)
	var step := newest_at - previous_at
	var from_xform: Transform3D = previous["xform"]
	var to_xform: Transform3D = newest["xform"]
	if step <= 0.0 or extra <= 0.0:
		return to_xform
	var velocity := (to_xform.origin - from_xform.origin) / step
	var held := to_xform
	held.origin = to_xform.origin + velocity * extra
	return held


## Riders are placed on their seat by player.gd, not smoothed behind the vehicle.
func _parent_places_visual() -> bool:
	var body := get_parent()
	return body != null and body.has_method("is_riding_visual") and bool(body.call("is_riding_visual"))


func _is_local_authority() -> bool:
	# After the host leaves, the peer is cleared before the world is freed.
	if multiplayer.multiplayer_peer == null:
		return true
	var body := get_parent()
	return body != null and body.is_multiplayer_authority()


func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0
