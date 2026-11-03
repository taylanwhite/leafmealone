extends Node

## Authority: local, cosmetic. Your own leaf bag through your own eyes
## (docs/GAME.md "Tossing bags into Chefty", toss:polish). Only the drawn bag
## (the prop's Visual/Look) moves; the bag's body, its Visual node, the flight
## the host gives it (net/components/bed_toss.gd) and what everyone else sees
## stay exactly as they were.
##
## - Carried: the bag sits in the lower third of your view with both hands on
##   its rolled top, its open top tipped toward you, instead of a sliver of
##   rim under the HUD (Constants.FP_BAG_RIM).
## - Wound up: it dips, down and back toward you, and trembles while you hold
##   it (the anticipation before the lob).
## - Let go: it leaves your hands for the real flight over a few frames, and
##   while it's close it never looks wider than Constants.FP_THROW_MAX_ANGLE.
##   It shrinks about its middle, which from your eyes is the same picture as
##   being flung further away, so it rises out of your hands small and clear of
##   your face instead of passing up through it. A bag gliding into Chefty's
##   load is its own size again well before it lands (no pop at the thump).
##
## net_prop.gd adds one to a leaf bag the first time this peer holds it. It runs
## after the prop (process_physics_priority) so it draws over where the prop
## just put its look, and it is idle (touches nothing) unless this peer's
## player is looking through their own eyes at a bag they hold or just threw.

const _PropLooks = preload("res://props/prop_looks.gd")
const _BedToss = preload("res://net/components/bed_toss.gd")

enum Mode { IDLE, HELD, THROWN }

## Where the look sits on the Visual node when nobody moves it (prop_looks.gd dress).
const REST := Vector3(0.0, -_PropLooks.VISUAL_HEIGHT, 0.0)

## What happened on this peer, for the toss test (H10, and its client half):
## ticks a bag was drawn in your hands, throws drawn, the biggest jump of the
## drawn bag from one tick to the next (m), and what the drawn mesh really
## covered on your screen (seen_from: its box on screen, clipped to the view, as
## a share of the view; 1 when it straddles your eyes): the most a bag in your
## hands covered once it was framed, the most a thrown one covered at any tick
## from the release to the landing (and how many seconds after the release, and
## its middle's height above your eyes, m), the most after the hand-off ease,
## and the widest it looked then (rad, corner to corner from your eyes).
static var stats: Dictionary = {"held_ticks": 0, "throws": 0, "max_step_m": 0.0, "held_share": 0.0, "thrown_share": 0.0, "thrown_share_at": [], "flight_share": 0.0, "flight_wide": 0.0, "thrown_ticks": 0}

var _prop: Node3D
var _mode: int = Mode.IDLE
var _age: float = 0.0
var _enter: float = 0.0
var _wind: float = 0.0
var _time: float = 0.0
## The look as this drew it last tick (world), and where the bag's own look was
## then (the offset between them eases out after a release).
var _drawn := Transform3D()
var _from := Transform3D()
var _from_rest := Transform3D()
## The look's meshes' box in the look's own space (for stats), once found.
var _extent := AABB()
var _extent_found: bool = false


func _enter_tree() -> void:
	# After the prop (110), which places its Visual this tick.
	process_physics_priority = 115


func _ready() -> void:
	name = "CarryView"
	_prop = get_parent() as Node3D


func _physics_process(delta: float) -> void:
	if _prop == null or multiplayer.multiplayer_peer == null:
		return
	var carried := bool(_prop.call("fp_carried"))
	if _mode == Mode.IDLE and not carried:
		return
	var look := _prop.get_node_or_null("Visual/Look") as Node3D
	var visual := _prop.get_node_or_null("Visual") as Node3D
	var player := _local_player()
	var eyes := _eyes(player)
	if look == null or visual == null or eyes == null:
		_stop(look)
		return
	_time += delta
	var rest := visual.global_transform * Transform3D(Basis.IDENTITY, REST)
	if carried:
		if _mode != Mode.HELD:
			_mode = Mode.HELD
			_enter = 0.0
			_wind = 0.0
		_enter = minf(_enter + delta / Constants.FP_BAG_ENTER_SECONDS, 1.0)
		var winding := float(player.get("_wind_up")) >= 0.0
		_wind = move_toward(_wind, 1.0 if winding else 0.0, delta / (Constants.FP_BAG_WIND_SECONDS if winding else Constants.FP_BAG_ENTER_SECONDS))
		var framed := held_transform(eyes.global_transform, smoothstep(0.0, 1.0, _wind), _shake(player))
		_draw(look, rest.interpolate_with(framed, smoothstep(0.0, 1.0, _enter)))
		stats["held_ticks"] = int(stats["held_ticks"]) + 1
		if _enter >= 1.0:
			var held := seen_from(eyes, look.global_transform, _look_extent(look))
			stats["held_share"] = maxf(float(stats["held_share"]), held.x)
		return
	if _mode == Mode.HELD:
		# Out of your hands this tick: from here on it eases onto the bag's own path.
		_mode = Mode.THROWN
		_age = 0.0
		_from = _drawn
		_from_rest = rest
		stats["throws"] = int(stats["throws"]) + 1
	_age += delta
	var settle := _settle_share()
	if settle >= Constants.FP_THROW_SETTLE_DONE or bool(_prop.get("_settle_landed")) or (_age >= maxf(Constants.FP_THROW_EASE_SECONDS, Constants.FP_THROW_CAP_END_SECONDS) and settle < 0.0):
		_stop(look)
		return
	var drawn := thrown_transform(rest, _from, _from_rest, _age, settle, eyes.global_position)
	_draw(look, drawn)
	# What the camera really gets, every tick from the release to the landing, at
	# every height: the look's meshes as drawn, projected through these eyes.
	var seen := seen_from(eyes, look.global_transform, _look_extent(look))
	stats["thrown_ticks"] = int(stats["thrown_ticks"]) + 1
	if seen.x > float(stats["thrown_share"]):
		stats["thrown_share"] = seen.x
		stats["thrown_share_at"] = [snappedf(_age, 0.001), snappedf((drawn * _BedToss.LOOK_MIDDLE).y - eyes.global_position.y, 0.01)]
	if _age > Constants.FP_THROW_EASE_SECONDS:
		stats["flight_share"] = maxf(float(stats["flight_share"]), seen.x)
		stats["flight_wide"] = maxf(float(stats["flight_wide"]), seen.y)


## How much of camera's view a look drawn at `at` covers, with its meshes in
## `extent` (its own space): x, the box projected to the screen (cut off at the
## camera's near plane, so a bag passing overhead counts only the part in front
## of you), the rectangle around it clipped to the view, as a share of the
## view's area (1 with the camera inside the box); y, the widest it looks from
## the camera (rad, the biggest angle between two corners; PI inside it).
static func seen_from(camera: Camera3D, at: Transform3D, extent: AABB) -> Vector2:
	var eye := camera.global_position
	if extent.has_point(at.affine_inverse() * eye):
		return Vector2(1.0, PI)
	var view := camera.get_viewport().get_visible_rect().size
	var to_camera := camera.global_transform.affine_inverse()
	var near := -camera.near * 1.01
	var points: Array[Vector3] = []
	var wide := 0.0
	for index: int in 8:
		points.append(to_camera * (at * extent.get_endpoint(index)))
		for other: int in index:
			wide = maxf(wide, points[index].angle_to(points[other]))
	# What's in front of the near plane: the corners there, and where the box's
	# edges cross it.
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var seen := 0
	for index: int in 8:
		var corner := points[index]
		if corner.z <= near:
			var on_screen := camera.unproject_position(camera.global_transform * corner)
			low = low.min(on_screen)
			high = high.max(on_screen)
			seen += 1
		for bit: int in 3:
			var other := index ^ (1 << bit)
			if other < index:
				continue
			var end := points[other]
			if (corner.z <= near) != (end.z <= near):
				var cut := corner.lerp(end, (near - corner.z) / (end.z - corner.z))
				var on_screen := camera.unproject_position(camera.global_transform * cut)
				low = low.min(on_screen)
				high = high.max(on_screen)
				seen += 1
	if seen == 0 or view.x <= 0.0 or view.y <= 0.0:
		return Vector2(0.0, wide)
	low = low.clamp(Vector2.ZERO, view)
	high = high.clamp(Vector2.ZERO, view)
	return Vector2((high.x - low.x) * (high.y - low.y) / (view.x * view.y), wide)


## The look's meshes' box in the look's own space (the bag model never changes).
func _look_extent(look: Node3D) -> AABB:
	if _extent_found:
		return _extent
	var inverse := look.global_transform.affine_inverse()
	for node: Node in look.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := (inverse * mesh.global_transform) * mesh.get_aabb()
		_extent = box if not _extent_found else _extent.merge(box)
		_extent_found = true
	return _extent


## The carried bag's look (world) for eyes at `view`: framed in the lower third,
## dipped by `dip` (0..1, the wind-up), shaken by `shake` (view space, m).
static func held_transform(view: Transform3D, dip: float, shake: Vector3 = Vector3.ZERO) -> Transform3D:
	var ahead := -view.basis.z
	var yaw := atan2(-ahead.x, -ahead.z)
	var pitch := asin(clampf(ahead.y, -1.0, 1.0))
	var level := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, clampf(pitch * Constants.FP_BAG_PITCH_FOLLOW, Constants.FP_BAG_PITCH_MIN, Constants.FP_BAG_PITCH_MAX))
	var rim := view.origin + level * (Constants.FP_BAG_RIM + Constants.FP_BAG_WIND_PULL * dip + shake)
	var turn := level * Basis(Vector3.RIGHT, Constants.FP_BAG_TILT + Constants.FP_BAG_WIND_TILT * dip)
	var rim_local := (_PropLooks.BAG_RIM[0] + _PropLooks.BAG_RIM[1]) * 0.5
	return Transform3D(turn, rim - turn * rim_local)


## The thrown bag's look (world), age seconds after it left the hands: the bag's
## own look `rest` now, plus what's left of where this drew it at the release
## (`from`, when its own look was at `from_rest`), shrunk about its middle so it
## looks no wider than Constants.FP_THROW_MAX_ANGLE from `eye` while it's close and up
## by the eye line.
## settle is how far through a glide into the load it is (0..1), or -1.
static func thrown_transform(rest: Transform3D, from: Transform3D, from_rest: Transform3D, age: float, settle: float, eye: Vector3) -> Transform3D:
	var left := 1.0 - smoothstep(0.0, Constants.FP_THROW_EASE_SECONDS, age)
	var origin := rest.origin + (from.origin - from_rest.origin) * left
	var turn := Basis(from.basis.get_rotation_quaternion().slerp(rest.basis.get_rotation_quaternion(), 1.0 - left))
	var middle := origin + turn * _BedToss.LOOK_MIDDLE
	var far := eye.distance_to(middle)
	var fits := clampf(far * tan(Constants.FP_THROW_MAX_ANGLE * 0.5) / Constants.FP_BAG_RADIUS, 0.0, 1.0)
	var weight := smoothstep(0.0, Constants.FP_THROW_CAP_IN_SECONDS, age) * (1.0 - smoothstep(Constants.FP_THROW_CAP_HOLD_SECONDS, Constants.FP_THROW_CAP_END_SECONDS, age))
	# Only up by your eye line, where it would fill the view: low in front of you a
	# bag is in your hands or at your feet, and looks it.
	weight *= smoothstep(eye.y - Constants.FP_THROW_CAP_LOW_M, eye.y - Constants.FP_THROW_CAP_HIGH_M, middle.y)
	if settle >= 0.0:
		weight *= 1.0 - smoothstep(Constants.FP_THROW_SETTLE_DONE - Constants.FP_THROW_SETTLE_FADE, Constants.FP_THROW_SETTLE_DONE, settle)
	var size := lerpf(1.0, fits, weight)
	return Transform3D(turn * Basis.from_scale(Vector3.ONE * size), middle - turn * (_BedToss.LOOK_MIDDLE * size))


func _draw(look: Node3D, at: Transform3D) -> void:
	if _drawn != Transform3D() and _mode != Mode.IDLE:
		stats["max_step_m"] = maxf(float(stats["max_step_m"]), _drawn.origin.distance_to(at.origin))
	look.global_transform = at
	_drawn = at


## Back to the look's own place on the Visual node; a squash the load gave it
## as it landed keeps its scale.
func _stop(look: Node3D) -> void:
	if _mode == Mode.IDLE:
		return
	_mode = Mode.IDLE
	_drawn = Transform3D()
	if look == null:
		return
	look.position = REST
	look.rotation = Vector3.ZERO
	if not bool(_prop.get("_settle_landed")):
		look.scale = Vector3.ONE


## How far through its glide into Chefty's load the bag is (0..1), or -1.
func _settle_share() -> float:
	if not bool(_prop.call("is_settling")):
		return -1.0
	return clampf(float(_prop.get("_settle_age")) / maxf(float(_prop.get("_settle_seconds")), 0.01), 0.0, 1.0)


## The tremble of a held wind-up, in view space: a little, more the longer you
## hold it, a lot when you strain.
func _shake(player: Node) -> Vector3:
	var wound := float(player.get("_wind_up"))
	if wound < 0.0:
		return Vector3.ZERO
	var share := clampf(wound / Constants.THROW_CHARGE_SECONDS, 0.0, 1.0)
	var amount := Constants.FP_BAG_SHAKE * share + (Constants.FP_BAG_STRAIN_SHAKE if bool(player.get("straining")) else 0.0)
	var rate := Constants.FP_BAG_SHAKE_RATE
	return Vector3(sin(_time * rate.x), cos(_time * rate.y), sin(_time * rate.z)) * amount


func _local_player() -> Node3D:
	var me := str(Net.local_peer_id())
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == me:
			return node as Node3D
	return null


## This peer's first-person camera while it's the one drawing, else null.
static func _eyes(player: Node3D) -> Camera3D:
	if player == null:
		return null
	var camera := player.get_node_or_null("Visual/Head/FirstPerson") as Camera3D
	return camera if camera != null and camera.current else null
