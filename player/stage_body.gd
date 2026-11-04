extends Node

## Authority: every peer places the body itself (R2, docs/DECISIONS.md "Staged
## bodies"). Player/StageBody: while a player is staged (walked arm in arm to the
## van, buckled into a seat, led into the Annex) their body follows an anchor on
## EVERY peer, the owner included, from the same anchor and offset, so the pair
## never tears apart under lag and nothing waits on the synchronizer.
##
## set_staged() is called on every peer by the caller's reliable RPC handler.
## The first placement blends over `blend` seconds from wherever the body was, so
## it never pops; clear_staged() leaves the body exactly where it is (the owner
## already holds that pose, so release never pops either), and the other peers
## go back to the replicated pose after one fresh sample.
##
## On the owner the CharacterBody3D itself is placed each physics tick, after the
## player (100) and the anchors have moved. On other peers the network smoother
## is told to keep off (player.is_riding_visual) and the Visual is placed every
## frame from the anchor's interpolated transform, so a synchronizer update
## landing mid-frame can't shake it.

const _StageCam = preload("res://player/stage_cam.gd")
const POSES: Array[StringName] = [&"stand", &"escorted", &"sit_buckled", &"walk_behind"]

## For net/dev/probe.gd and the tests: the largest per-tick move of a staged
## body outside a closed iris, and how many ticks went over STAGE_MAX_STEP_METERS.
static var log: Dictionary = {"max_step_m": 0.0, "steps_over": 0, "staged": 0}

## The player this belongs to (set by player.gd).
var player: CharacterBody3D

var _anchor: Node3D
var _offset := Transform3D.IDENTITY
var _pose: StringName = &"stand"
var _blend: float = 0.0
var _blend_t: float = 1.0
var _from := Transform3D()
var _last_origin := Vector3.INF
var _excepted: PhysicsBody3D
var _excepted_rid := RID()
## The last placement, so clear_staged can leave the body there.
var _placed := Transform3D()
## Another peer's release ease (STAGE_RELEASE_BLEND): from where, how far.
var _release_from := Transform3D()
var _release_t: float = 1.0
## Staged and not yet released. Separate from _anchor, which can be freed under
## us (a van left) and must still get a proper release.
var _active: bool = false
## R2c: someone the first placement's blend goes round, not through (the link).
var _clear_of: Node3D


static func reset_log() -> void:
	log = {"max_step_m": 0.0, "steps_over": 0, "staged": 0}


func _ready() -> void:
	process_physics_priority = 110
	process_priority = 110


func set_staged(anchor: Node3D, offset: Transform3D, blend: float, pose: StringName, clear_of: Node3D = null) -> void:
	if player == null or anchor == null:
		return
	var was_staged := is_staged()
	_clear_of = clear_of
	_active = true
	_anchor = anchor
	_offset = offset
	_pose = pose if POSES.has(pose) else &"stand"
	_blend = maxf(0.0, blend)
	# From the pose this peer is drawing now: the body on the owner, the visual elsewhere.
	_from = _drawn_transform() if not was_staged else _placed
	_blend_t = 0.0 if _blend > 0.0 else 1.0
	_last_origin = Vector3.INF
	_release_t = 1.0
	log["staged"] = int(log["staged"]) + 1
	_set_exception(anchor)
	if not _is_owner():
		var visual := player.get_node_or_null("Visual") as Node3D
		if visual != null:
			visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	player.velocity = Vector3.ZERO
	_apply_pose()
	if _is_owner():
		_place(0.0)
	else:
		_place_visual(_target(_anchor.global_transform))


func clear_staged() -> void:
	if not _active:
		return
	_release()


## Let go: the pose back to standing, the collision exception off, and on other
## peers the ease back onto the network pose. Runs whether or not the anchor
## still exists.
func _release() -> void:
	_active = false
	_anchor = null
	_set_exception(null)
	if player == null:
		return
	if _is_owner():
		# The body stays put, facing the way it was placed.
		player.global_position = _placed.origin
		player.set("body_yaw", _placed.basis.get_euler().y)
	else:
		# The network pose trails the owner by the link's delay: ease onto it from
		# where the body was drawn instead of jumping back along the path.
		_release_from = _placed
		_release_t = 0.0
	_pose = &"stand"
	_apply_pose()


func is_staged() -> bool:
	return _anchor != null and is_instance_valid(_anchor)


func staged_anchor() -> Node3D:
	return _anchor if is_staged() else null


func pose() -> StringName:
	return _pose if is_staged() else &""


## Where the body is being placed now (world space), for the tests.
func placed() -> Transform3D:
	return _placed


## Where the body should be on this peer right now (world space).
func target() -> Transform3D:
	if not is_staged():
		return Transform3D()
	return _target(_anchor.global_transform)


func _target(frame: Transform3D) -> Transform3D:
	var xform := frame * _offset
	# Upright: the anchor may tip (a van's nose dips), a person stands straight.
	var forward := xform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		forward = Vector3.BACK
	var yaw := atan2(forward.x, forward.z)
	return Transform3D(Basis(Vector3.UP, yaw), xform.origin)


func _physics_process(delta: float) -> void:
	if _active and not is_instance_valid(_anchor):
		# The anchor was freed (a van left): let go from where we were.
		_release()
		return
	if not is_staged() or player == null:
		return
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + delta / _blend)
	if _is_owner():
		_place(delta)


func _process(delta: float) -> void:
	if player == null or _is_owner():
		return
	if _active and not is_instance_valid(_anchor):
		_release()
	if is_staged():
		_place_visual(_target(_StageCam.drawn_pose(_anchor)))
	elif _release_t < 1.0:
		_ease_release(delta)


## Another peer, just released: the network smoother has placed the Visual this
## frame (it runs first); draw it between where the stage left it and there.
func _ease_release(delta: float) -> void:
	var visual := player.get_node_or_null("Visual") as Node3D
	if visual == null:
		_release_t = 1.0
		return
	_release_t = minf(1.0, _release_t + delta / maxf(Constants.STAGE_RELEASE_BLEND, 0.001))
	var eased := 1.0 - pow(1.0 - _release_t, 3.0)
	var smoothed := visual.global_transform
	var drawn := _release_from.interpolate_with(smoothed, eased)
	drawn.basis = drawn.basis.orthonormalized()
	_note_step(drawn.origin)
	visual.global_transform = drawn
	if _release_t >= 1.0:
		visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
		visual.reset_physics_interpolation()
		_last_origin = Vector3.INF


## The owner's body, on physics ticks: the anchor's pose, blended in at first.
func _place(_delta: float) -> void:
	var goal := _blended(_target(_anchor.global_transform))
	_note_step(goal.origin)
	_placed = goal
	player.global_position = goal.origin
	player.velocity = Vector3.ZERO
	player.set("body_yaw", goal.basis.get_euler().y)
	player.rotation.y = goal.basis.get_euler().y


## Another peer's view of the body, every frame.
func _place_visual(goal: Transform3D) -> void:
	var placed_now := _blended(goal)
	_note_step(placed_now.origin)
	_placed = placed_now
	var visual := player.get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.global_transform = placed_now


func _blended(goal: Transform3D) -> Transform3D:
	if _blend_t >= 1.0:
		return goal
	# Ease in and out: a body that starts at full speed reads as a pop.
	var eased := smoothstep(0.0, 1.0, _blend_t)
	var out := _from.interpolate_with(goal, eased)
	out.basis = out.basis.orthonormalized()
	if _clear_of != null and is_instance_valid(_clear_of) and _clear_of.is_inside_tree():
		out.origin = _round(_from.origin, goal.origin, eased)
	return out


## R2c: the blend goes round _clear_of (his drawn body), never through it: the
## way from in front of him to his side was a straight line through his chest
## (audit m2-escort-start-bodies-merge). Angle and distance about him blend
## separately, the distance never under STAGE_BODY_CLEAR.
func _round(from: Vector3, to: Vector3, u: float) -> Vector3:
	var visual := _clear_of.get_node_or_null("Visual") as Node3D
	var center := visual.global_position if visual != null else _clear_of.global_position
	var ra := Vector2(from.x - center.x, from.z - center.z)
	var rb := Vector2(to.x - center.x, to.z - center.z)
	if ra.length() < 0.01 or rb.length() < 0.01:
		return from.lerp(to, u)
	var angle := ra.angle() + wrapf(rb.angle() - ra.angle(), -PI, PI) * u
	var reach := maxf(lerpf(ra.length(), rb.length(), u), minf(Constants.STAGE_BODY_CLEAR, minf(ra.length(), rb.length())))
	var flat := Vector2.from_angle(angle) * reach
	return Vector3(center.x + flat.x, lerpf(from.y, to.y, u), center.z + flat.y)


func _drawn_transform() -> Transform3D:
	if _is_owner():
		return player.global_transform
	var visual := player.get_node_or_null("Visual") as Node3D
	return visual.global_transform if visual != null else player.global_transform


func _note_step(origin: Vector3) -> void:
	if _last_origin != Vector3.INF:
		var step := origin.distance_to(_last_origin)
		var iris := get_tree().get_first_node_in_group("iris") if _is_owner() else null
		var covered := iris != null and bool(iris.call("is_closed"))
		if not covered:
			log["max_step_m"] = maxf(float(log["max_step_m"]), step)
			if step > Constants.STAGE_MAX_STEP_METERS:
				log["steps_over"] = int(log["steps_over"]) + 1
	_last_origin = origin


## Poses on the cartoon body: sitting buckled, the reluctant escorted shuffle,
## or the plain walk cycle (driven by how fast the anchor carries the body).
func _apply_pose() -> void:
	if player != null and player.has_method("set_body_pose"):
		player.call("set_body_pose", _pose)


## The staged body and whatever carries its anchor don't push each other.
func _set_exception(anchor: Node3D) -> void:
	if _excepted != null and is_instance_valid(_excepted):
		player.remove_collision_exception_with(_excepted)
		_excepted.remove_collision_exception_with(player)
	elif _excepted_rid.is_valid():
		# The carrier was freed (a van left): drop the exception by its RID, or
		# the player keeps a dangling one.
		PhysicsServer3D.body_remove_collision_exception(player.get_rid(), _excepted_rid)
	_excepted = null
	_excepted_rid = RID()
	var node: Node = anchor
	while node != null:
		if node is PhysicsBody3D and node != player:
			_excepted = node as PhysicsBody3D
			_excepted_rid = _excepted.get_rid()
			player.add_collision_exception_with(_excepted)
			_excepted.add_collision_exception_with(player)
			return
		node = node.get_parent()


func _is_owner() -> bool:
	# No peer (the session just ended, the world not yet freed): nobody's, quietly.
	if player == null or player.multiplayer.multiplayer_peer == null:
		return false
	return player.is_multiplayer_authority()
