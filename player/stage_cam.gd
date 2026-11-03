extends Camera3D

## Authority: local (the owning peer's view only). StageCam, R2's one extra
## camera: CameraRig/StageCam on the local player. Every view that isn't your own
## first-person or over-the-shoulder camera goes through it (the gotcha two-shot,
## the escort, the van seat, the hide peek, the Annex walk-in), so no camera ever
## freezes under a hidden node or cuts without cover (docs/DECISIONS.md, R2).
##
## A stack of shots keyed by id. The top one (highest priority, newest on ties)
## drives the camera. A shot is a Dictionary:
##   anchor (Node3D, required): what the shot hangs off.
##   offset (Transform3D): where the eye sits in the anchor's space (looks down -Z).
##   blend_in, blend_out (float): seconds; < 0 or missing = STAGE_BLEND_DEFAULT,
##     0 = a cut (only ever behind a closed iris).
##   yaw_clamp (Vector2): radians of mouse look around the anchor's facing, as
##     (min, max); ZERO = no mouse look.
##   pitch_clamp (Vector2): the same for up and down.
##   orbit (bool): the mouse orbits the eye around the anchor instead of turning it.
##   spring (bool): pull the eye in toward the anchor when a wall (mask 1) is in the way.
##   fov (float): 0 = the player's FOV setting.
##   lag (float): seconds of position smoothing (0 = rigid).
##   priority (int).
##   hide_self (bool, optional): skip your own head and body (an eye inside your head).
## Blends ease out (cubic) from wherever the outgoing camera was really drawn to
## the new shot, which follows its anchor while it blends. This camera becomes
## current in the same call that takes current from the old one, and popping the
## last shot blends back to whichever of FirstPerson / OverShoulder the camera
## toggle picks, handing current back in the frame the blend ends: there is
## exactly one current camera on every frame.
##
## It is top_level and updated every rendered frame from the anchors'
## interpolated transforms, so it is never parented under Visual or anything
## whose visibility toggles, and physics interpolation never smears a cut.

const _CartoonBody = preload("res://player/cartoon_body.gd")

## For net/dev/probe.gd and stage_test: pushes and pops, frames with no current
## 3D camera while a session runs, and the largest per-frame move of this camera
## outside a blend start (a cut behind a closed iris doesn't count).
static var log: Dictionary = {"pushes": 0, "pops": 0, "null_frames": 0, "max_step_m": 0.0, "cuts": 0, "frames": 0}

## The player whose view this is (set by player.gd).
var player: Node3D

var _shots: Dictionary = {}
var _order: int = 0
var _top: StringName = &""
## The blend in progress: where it started, how long, how far.
var _from := Transform3D()
var _from_fov: float = 75.0
var _blend_seconds: float = 0.0
var _blend_t: float = 1.0
## Blending back to the base camera after the last pop.
var _returning: bool = false
## Mouse look inside the top shot, radians.
var _yaw: float = 0.0
var _pitch: float = 0.0
var _smoothed := Vector3.INF
var _last_origin := Vector3.INF


static func reset_log() -> void:
	log = {"pushes": 0, "pops": 0, "null_frames": 0, "max_step_m": 0.0, "cuts": 0, "frames": 0}


func _ready() -> void:
	top_level = true
	far = 400.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Late in the frame, after everything an anchor can ride on has moved.
	process_priority = 120
	process_physics_priority = 120


## Push or replace a shot. Returns false (and changes nothing) without an anchor.
func push(id: StringName, shot: Dictionary) -> bool:
	var anchor := shot.get("anchor") as Node3D
	if anchor == null or not is_instance_valid(anchor):
		push_warning("[StageCam] shot %s has no anchor" % id)
		return false
	var entry := shot.duplicate()
	_order += 1
	entry["_order"] = _order
	_shots[id] = entry
	log["pushes"] = int(log["pushes"]) + 1
	_retop(float(entry.get("blend_in", -1.0)))
	return true


## Pop a shot. blend_out < 0 uses the shot's own blend_out.
func pop(id: StringName, blend_out: float = -1.0) -> void:
	if not _shots.has(id):
		return
	var shot: Dictionary = _shots[id]
	_shots.erase(id)
	log["pops"] = int(log["pops"]) + 1
	var seconds := blend_out if blend_out >= 0.0 else float(shot.get("blend_out", -1.0))
	if id == _top or _shots.is_empty():
		_retop(seconds)


## The id of the shot driving the camera, or &"" when the base camera has it.
func top() -> StringName:
	return _top


func has_shot(id: StringName) -> bool:
	return _shots.has(id)


## Whether a shot is on top or the camera is still blending back from one.
func is_live() -> bool:
	return _top != &"" or _returning


## Mouse look while a shot is on top (player.gd routes it here). Returns false
## when the top shot takes no look, so the caller drops it.
func add_look(relative: Vector2) -> bool:
	if _top == &"":
		return false
	var shot: Dictionary = _shots[_top]
	var yaw_clamp: Vector2 = shot.get("yaw_clamp", Vector2.ZERO)
	var pitch_clamp: Vector2 = shot.get("pitch_clamp", Vector2.ZERO)
	if yaw_clamp == Vector2.ZERO and pitch_clamp == Vector2.ZERO:
		return true
	var turn := Settings.look_scale()
	_yaw = clampf(_yaw - relative.x * turn.x, yaw_clamp.x, yaw_clamp.y)
	_pitch = clampf(_pitch - relative.y * turn.y, pitch_clamp.x, pitch_clamp.y)
	return true


func look_angles() -> Vector2:
	return Vector2(_yaw, _pitch)


## The camera the stage hands back to: the rig's choice of first person or over
## the shoulder.
func base_camera() -> Camera3D:
	var rig := get_parent()
	if rig != null and rig.has_method("current_base_camera"):
		return rig.call("current_base_camera") as Camera3D
	return null


func _retop(blend_seconds: float) -> void:
	var next := _pick_top()
	var outgoing := _drawn_transform()
	var outgoing_fov := _drawn_fov()
	if next == &"":
		if _top == &"" and not _returning:
			return
		_top = &""
		_start_blend(outgoing, outgoing_fov, blend_seconds)
		_returning = true
		return
	var was_live := is_live()
	if next != _top:
		_yaw = 0.0
		_pitch = 0.0
		_smoothed = Vector3.INF
	_top = next
	_returning = false
	_start_blend(outgoing, outgoing_fov, blend_seconds)
	if not current:
		# make_current takes current from the old camera in the same call: never a
		# frame with none.
		make_current()
	if not was_live:
		_last_origin = Vector3.INF
	_apply_mask()
	_update(0.0)


func _start_blend(from: Transform3D, from_fov: float, seconds: float) -> void:
	_from = from
	_from_fov = from_fov
	_blend_seconds = Constants.STAGE_BLEND_DEFAULT if seconds < 0.0 else seconds
	_blend_t = 0.0 if _blend_seconds > 0.0 else 1.0
	if _blend_seconds <= 0.0:
		log["cuts"] = int(log["cuts"]) + 1
		_last_origin = Vector3.INF
		reset_physics_interpolation()


func _pick_top() -> StringName:
	var best: StringName = &""
	var best_priority: int = -1000000
	var best_order := -1
	for id: StringName in _shots:
		var shot: Dictionary = _shots[id]
		var anchor := shot.get("anchor") as Node3D
		if anchor == null or not is_instance_valid(anchor):
			continue
		var priority := int(shot.get("priority", 0))
		var order := int(shot["_order"])
		if priority > best_priority or (priority == best_priority and order > best_order):
			best = id
			best_priority = priority
			best_order = order
	return best


## Where the view is really drawn from right now: this camera while it's current,
## else the base camera's interpolated transform.
func _drawn_transform() -> Transform3D:
	if current:
		return global_transform
	var base := base_camera()
	if base != null and base.is_inside_tree():
		return base.get_global_transform_interpolated()
	return global_transform


func _drawn_fov() -> float:
	if current:
		return fov
	var base := base_camera()
	return base.fov if base != null else Settings.fov()


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if Net.current_state() == Net.State.IN_SESSION and get_viewport().get_camera_3d() == null:
		log["null_frames"] = int(log["null_frames"]) + 1
	# An anchor freed under a shot (a van gone, a spot removed) drops the shot.
	if _top != &"" and not is_instance_valid(_shots[_top].get("anchor")):
		_shots.erase(_top)
		_retop(Constants.STAGE_BLEND_DEFAULT)
	if _top == &"" and not _returning:
		return
	_update(delta)


func _update(delta: float) -> void:
	var target := Transform3D()
	var target_fov := Settings.fov()
	if _top != &"":
		var shot: Dictionary = _shots[_top]
		target = _shot_transform(shot, delta)
		if float(shot.get("fov", 0.0)) > 0.0:
			target_fov = float(shot["fov"])
	else:
		var base := base_camera()
		if base == null:
			_finish_return()
			return
		target = base.get_global_transform_interpolated()
		target_fov = base.fov
	if _blend_t < 1.0 and _blend_seconds > 0.0:
		_blend_t = minf(1.0, _blend_t + delta / _blend_seconds)
	var eased := 1.0 - pow(1.0 - _blend_t, 3.0)
	var drawn := _from.interpolate_with(target, eased) if eased < 1.0 else target
	drawn.basis = drawn.basis.orthonormalized()
	global_transform = drawn
	fov = lerpf(_from_fov, target_fov, eased)
	_note_step(drawn.origin)
	if _returning and _blend_t >= 1.0:
		_finish_return()


func _finish_return() -> void:
	_returning = false
	var base := base_camera()
	if base != null:
		# Current goes straight to the base camera in this one call.
		base.make_current()
	_last_origin = Vector3.INF


func _shot_transform(shot: Dictionary, delta: float) -> Transform3D:
	var anchor := shot["anchor"] as Node3D
	var frame := anchor.get_global_transform_interpolated()
	frame.basis = frame.basis.orthonormalized()
	var offset: Transform3D = shot.get("offset", Transform3D.IDENTITY)
	var eye := Transform3D()
	if bool(shot.get("orbit", false)):
		# The eye swings round the anchor, still looking at it.
		var turn := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
		var local := Transform3D(turn, Vector3.ZERO) * offset
		eye = frame * local
	else:
		eye = frame * offset
		eye.basis = eye.basis * Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	if bool(shot.get("spring", false)):
		eye.origin = _spring(frame.origin, eye.origin)
	var lag := float(shot.get("lag", 0.0))
	if lag > 0.0 and delta > 0.0 and _smoothed != Vector3.INF:
		_smoothed = _smoothed.lerp(eye.origin, 1.0 - exp(-delta / lag))
		eye.origin = _smoothed
	else:
		_smoothed = eye.origin
	return eye


## Pull the eye toward the anchor when the world (mask 1) is between them.
func _spring(from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state if get_world_3d() != null else null
	if space == null:
		return to
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	if player is CollisionObject3D:
		query.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return to
	var point: Vector3 = hit["position"]
	return point + (from - point).normalized() * 0.25


func _note_step(origin: Vector3) -> void:
	log["frames"] = int(log["frames"]) + 1
	if _last_origin != Vector3.INF:
		var iris := get_tree().get_first_node_in_group("iris")
		var covered := iris != null and bool(iris.call("is_closed"))
		if not covered:
			log["max_step_m"] = maxf(float(log["max_step_m"]), origin.distance_to(_last_origin))
	_last_origin = origin


## Your own head and body are on HEAD_LAYER (player/cartoon_body.gd): a shot
## from outside shows them, an eye inside your head (hide_self) skips them.
func _apply_mask() -> void:
	var head_bit := 1 << (_CartoonBody.HEAD_LAYER - 1)
	if _top != &"" and bool((_shots[_top] as Dictionary).get("hide_self", false)):
		cull_mask = 0xFFFFF & ~head_bit
	else:
		cull_mask = 0xFFFFF
