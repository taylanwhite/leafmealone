class_name NetSmoother
extends Node

## Authority: owning peer for the latest snapshot, local for the rendered pose.
## Renders a visual about 100 ms behind the replicated body. The body itself stays
## on the latest snapshot so collisions match the network pose. A jump past
## snap_distance (a zone teleport) snaps instead of sliding across the map.

const MAX_EXTRAPOLATION_SECONDS: float = 0.1
## Horizontal speed above which a gap in updates counts as a hitch, in m/s.
const MOVING_SPEED: float = 0.5

## Totals across every smoother in this process, read by net/dev/probe.gd.
## A hitch is a gap between updates longer than delay_seconds while the body was
## moving, which shows as a freeze and a jump. Assumes the mover never stands still,
## which holds for --bot players.
static var stats: Dictionary = {"samples": 0, "hitches": 0, "max_gap_ms": 0.0, "snaps": 0}

## How far behind the newest snapshot the visual is rendered, in seconds.
@export var delay_seconds: float = 0.1
## Distance from the latest snapshot at which the visual snaps, in meters.
@export var snap_distance: float = 3.0
## Child that is drawn. The parent is the replicated body.
@export var visual_path: NodePath

var _visual: Node3D
var _samples: Array[Dictionary] = []
var _last_recorded := Vector3(INF, INF, INF)


func _ready() -> void:
	_visual = get_node_or_null(visual_path) as Node3D
	if _visual == null:
		push_error("[NetSmoother] visual_path does not point at a Node3D")
		set_physics_process(false)
		set_process(false)


func _physics_process(_delta: float) -> void:
	if _is_local_authority() or _visual == null:
		return
	var body := get_parent() as Node3D
	if body == null:
		return
	var origin := body.global_position
	if origin.distance_squared_to(_last_recorded) < 0.0000001 and not _samples.is_empty():
		return
	_last_recorded = origin
	var now := _now()
	if not _samples.is_empty():
		var previous: Dictionary = _samples[_samples.size() - 1]
		var gap := now - float(previous["at"])
		if float(previous.get("speed", 0.0)) > MOVING_SPEED:
			stats["max_gap_ms"] = maxf(float(stats["max_gap_ms"]), gap * 1000.0)
			if gap > delay_seconds:
				stats["hitches"] = int(stats["hitches"]) + 1
	stats["samples"] = int(stats["samples"]) + 1
	var velocity: Vector3 = body.get("velocity") if "velocity" in body else Vector3.ZERO
	_samples.append({"at": now, "xform": body.global_transform, "speed": Vector2(velocity.x, velocity.z).length()})
	var cutoff := _now() - delay_seconds - 1.0
	while _samples.size() > 2 and float(_samples[0]["at"]) < cutoff:
		_samples.remove_at(0)


func _process(_delta: float) -> void:
	if _is_local_authority() or _visual == null or _samples.is_empty():
		return
	var body := get_parent() as Node3D
	if body == null:
		return
	var rendered := _sample_at(_now() - delay_seconds)
	if rendered.origin.distance_to(body.global_position) > snap_distance:
		rendered = body.global_transform
		stats["snaps"] = int(stats["snaps"]) + 1
		_samples.clear()
		_samples.append({"at": _now(), "xform": rendered, "speed": 0.0})
		_last_recorded = rendered.origin
	_visual.global_transform = rendered


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


func _is_local_authority() -> bool:
	# After the host leaves, the peer is cleared before the world is freed.
	if multiplayer.multiplayer_peer == null:
		return true
	var body := get_parent()
	return body != null and body.is_multiplayer_authority()


func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0
