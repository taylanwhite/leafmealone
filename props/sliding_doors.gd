extends Node3D

## Authority: local, cosmetic. Homie Depot's automatic sliding doors (art chunk
## 8): two glass leaves that part when anyone in group "players" comes within
## Constants.ART_DOOR_OPEN_DISTANCE of them, from either side, and close again
## once everyone has been clear for ART_DOOR_HOLD_SECONDS (while anyone further
## out, within ART_DOOR_WATCH_MARGIN more, is still walking at them, open doors
## stay open). Each peer runs its own
## from the bodies it already sees, so nothing goes over the network; the doors
## have no collider (they are always open by the time anyone reaches them).
##
## The leaves move like the real thing: a beat of hesitation as the sensor
## notices you, then a quick slide that eases into its stop (a smootherstep
## skewed early, over ART_DOOR_OPEN_SECONDS), with a pneumatic hiss ("door_whoosh") as they start.
## A change of mind mid-slide carries on from where the leaves are, so they never
## jump.
##
## Frame: the doors' center on the floor, the opening along local Z (width), the
## outside at +X. Build with setup(width, height) before adding to the tree.

const _LowPoly = preload("res://props/low_poly.gd")
const FRAME := Color(0.72, 0.74, 0.76)
const HANDLE := Color(0.25, 0.26, 0.28)

## Width and height of the opening, and how far each leaf slides.
var opening_width: float = 5.0
var opening_height: float = 3.0
## 0 shut, 1 open: what the leaves show now.
var amount: float = 0.0

var _leaves: Array[Node3D] = []
var _target: float = 0.0
var _from: float = 0.0
var _since: float = 0.0
var _clear_for: float = 0.0
var _sensed_for: float = 0.0
var _time: float = 0.0


## Builds the two leaves (glass in a metal frame, a rubber seal where they meet).
func setup(width: float, height: float) -> void:
	opening_width = width
	opening_height = height
	var leaf_width := width * 0.5 + 0.05
	for side: float in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.name = "LeafL" if side < 0.0 else "LeafR"
		add_child(leaf)
		leaf.set_meta("side", side)
		var glass := _LowPoly.box(leaf, Vector3(0.03, height - 0.12, leaf_width - 0.1), Vector3(0.0, height * 0.5, 0.0), Color(0.55, 0.7, 0.82)) as MeshInstance3D
		glass.material_override = _glass()
		glass.set_meta("keep_material", true)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for z: float in [-leaf_width * 0.5 + 0.03, leaf_width * 0.5 - 0.03]:
			_LowPoly.paint(_LowPoly.box(leaf, Vector3(0.06, height, 0.06), Vector3(0.0, height * 0.5, z), FRAME), "metal", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
		for y: float in [0.03, height - 0.03]:
			_LowPoly.paint(_LowPoly.box(leaf, Vector3(0.06, 0.06, leaf_width), Vector3(0.0, y, 0.0), FRAME), "metal", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
		# A push bar at hand height on both faces, near the meeting edge.
		for face: float in [-1.0, 1.0]:
			_LowPoly.box(leaf, Vector3(0.03, 0.05, leaf_width * 0.55), Vector3(face * 0.05, 1.05, side * -leaf_width * 0.15), HANDLE)
		# The seal along the meeting edge.
		_LowPoly.box(leaf, Vector3(0.05, height - 0.1, 0.03), Vector3(0.0, height * 0.5, -side * (leaf_width * 0.5 - 0.005)), Color(0.12, 0.12, 0.13))
		_leaves.append(leaf)
	_place_leaves()


func _ready() -> void:
	add_to_group("store_doors")


func _process(delta: float) -> void:
	_time += delta
	var sensed := _sense(delta)
	var near := sensed == _NEAR
	if near:
		_clear_for = 0.0
		_sensed_for += delta
	else:
		_sensed_for = 0.0
		# Someone still walking up holds open doors open: a crew strung out across
		# the lot never sees them shut and part again in its face.
		_clear_for = 0.0 if sensed == _COMING and _target > 0.5 else _clear_for + delta
	var wanted := _target
	if near and _sensed_for >= Constants.ART_DOOR_SENSE_SECONDS:
		wanted = 1.0
	elif not near and _clear_for >= Constants.ART_DOOR_HOLD_SECONDS:
		wanted = 0.0
	if wanted != _target:
		_from = amount
		_target = wanted
		_since = _time
		_hiss(wanted > 0.5)
	var span := maxf(Constants.ART_DOOR_OPEN_SECONDS * absf(_target - _from), 0.05)
	var t := clampf((_time - _since) / span, 0.0, 1.0)
	# Opening gets going quickly (the curve skewed early) and eases into its stop;
	# closing is an even ease in and out.
	if _target > _from:
		t = pow(t, Constants.ART_DOOR_OPEN_SKEW)
	amount = lerpf(_from, _target, t * t * t * (t * (t * 6.0 - 15.0) + 10.0))
	_place_leaves()


## True while the doors are opening or open.
func is_open() -> bool:
	return _target > 0.5


func _place_leaves() -> void:
	var travel := opening_width * 0.5 - 0.05
	for leaf: Node3D in _leaves:
		var side := float(leaf.get_meta("side"))
		var closed := side * (opening_width * 0.25 + 0.025)
		# The leaves ride a hair apart in x, so they never touch while passing the sidelights.
		leaf.position = Vector3(-0.04 * side, 0.0, closed + side * travel * amount)


## What the sensor sees: nobody, someone walking up from further out, or someone
## close enough to open for.
const _CLEAR := 0
const _COMING := 1
const _NEAR := 2


## Each player's last spot (in the doors' space) and smoothed velocity, by
## instance id. Velocity is taken from how they moved, not body.velocity, which a
## remote player's copy doesn't carry.
var _tracks: Dictionary = {}


func _sense(delta: float) -> int:
	if not is_inside_tree():
		return _CLEAR
	var reach := Constants.ART_DOOR_OPEN_DISTANCE
	var watch := reach + Constants.ART_DOOR_WATCH_MARGIN
	var out := _CLEAR
	var seen := {}
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body == null or not body.is_visible_in_tree():
			continue
		var local := to_local(body.global_position)
		var id := body.get_instance_id()
		var velocity := Vector3.ZERO
		if _tracks.has(id) and delta > 0.0:
			var track: Array = _tracks[id]
			var moved: Vector3 = (local - (track[0] as Vector3)) / delta
			# A teleport (a zone move, a respawn) isn't anyone walking.
			if moved.length() > Constants.ART_DOOR_TRACK_MAX_SPEED:
				moved = Vector3.ZERO
			velocity = (track[1] as Vector3).lerp(moved, clampf(delta * Constants.ART_DOOR_TRACK_RATE, 0.0, 1.0))
		seen[id] = [local, velocity]
		if absf(local.y) >= 3.0:
			continue
		# Measured to the doorway itself (a slot as wide as the opening), not its middle,
		# so someone walking in at the edge of the crowd counts as soon as the middle one.
		var to_door := Vector2(-local.x, clampf(local.z, -opening_width * 0.5, opening_width * 0.5) - local.z)
		var distance := to_door.length()
		# How fast they're closing on the doorway, from any angle.
		var closing := 0.0
		if distance > 0.01:
			closing = maxf(Vector2(velocity.x, velocity.z).dot(to_door / distance), 0.0)
		# Someone running at the doors is seen a little sooner (the sensor's lead),
		# so a sprint never reaches half-open glass.
		if distance <= reach + closing * Constants.ART_DOOR_LEAD_SECONDS:
			out = _NEAR
		# Further out, someone who'd be in range within ART_DOOR_HOLD_AHEAD_SECONDS at
		# the pace they're coming is coming.
		elif distance <= minf(watch, reach + closing * Constants.ART_DOOR_HOLD_AHEAD_SECONDS) and closing >= Constants.ART_DOOR_APPROACH_SPEED:
			out = maxi(out, _COMING)
	_tracks = seen
	return out


func _hiss(opening: bool) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx") if is_inside_tree() else null
	if sfx != null:
		sfx.call("play_at", "door_whoosh", global_position + Vector3(0.0, opening_height * 0.9, 0.0), 0.0 if opening else Constants.ART_DOOR_CLOSE_DB, false, 0, 1.0 if opening else 0.92)


static func _glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.62, 0.78, 0.86, 0.32)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.3
	glass.roughness = 0.06
	glass.metallic_specular = 0.9
	return glass
