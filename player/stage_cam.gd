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
##   pivot (Vector3 or Node3D, optional; R2b): who the shot is about. A blend into
##     it swings round the pivot (pulling back first, then round), never straight
##     through someone's head, and the eye's moves are clamped relative to it
##     (max_speed m/s, default STAGE_CAM_MAX_SPEED; STAGE_CAM_MAX_TURN rad/s).
##   collide (bool, optional; R2b, with a pivot): keep the eye clear of the world
##     and the vehicles (player/stage_sweep.gd), pulling in toward the pivot.
## Blends ease in and out (smoothstep) from wherever the outgoing camera was
## really drawn to the new shot, which follows its anchor while it blends: no
## blend starts at full speed (R2b: the cubic ease-out's first frame was a
## 0.7 m jump that read as a cut). Someone else's body within
## STAGE_CAM_BODY_CLEAR of the eye isn't drawn while this camera has the view.
## This camera becomes
## current in the same call that takes current from the old one, and popping the
## last shot blends back to whichever of FirstPerson / OverShoulder the camera
## toggle picks, handing current back in the frame the blend ends: there is
## exactly one current camera on every frame.
##
## It is top_level and updated every rendered frame from the anchors'
## interpolated transforms, so it is never parented under Visual or anything
## whose visibility toggles, and physics interpolation never smears a cut.

const _CartoonBody = preload("res://player/cartoon_body.gd")
const _Sweep = preload("res://player/stage_sweep.gd")
## Presentation: an eye closer than this to your own head doesn't draw your own
## head and body (the head is about 0.27 m across, the shoulders 0.5 m).
const HEAD_CLEAR_METERS: float = 0.6

## For net/dev/probe.gd and stage_test: pushes and pops, frames with no current
## 3D camera while a session runs, and the largest per-frame move of this camera
## outside a blend start (a cut behind a closed iris doesn't count).
static var log: Dictionary = {"pushes": 0, "pops": 0, "null_frames": 0, "max_step_m": 0.0, "cuts": 0, "frames": 0, "stale_reads": 0}

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
## R2b: how far from the pivot the eye may be (the collision sweep's answer,
## eased back out), the last drawn pose and pivot (for the clamp), and the
## bodies hidden because the eye is inside them.
var _clear_dist: float = INF
var _last_drawn := Transform3D()
var _last_pivot := Vector3.INF
var _has_last: bool = false
## The last frame's point on the blend's own arc, before the sweep and the clamp
## (the swing is paced along it).
var _last_arc := Vector3.INF
var _hidden_bodies: Array[Node3D] = []
## R2c: the shot on top started with the eye in or right by your head (out of
## first person, out of a hiding spot): your own body dissolves in as the eye
## clears it (_apply_mask). How see-through it is now, and its meshes.
var _from_inside: bool = false
var _self_fade: float = 0.0
var _self_meshes: Array[GeometryInstance3D] = []
## R2c: bystanders and held things faded out of a shot with subjects:
## node -> {"meshes": Array, "amount": 0..1}.
var _faded: Dictionary = {}


static func reset_log() -> void:
	log = {"pushes": 0, "pops": 0, "null_frames": 0, "max_step_m": 0.0, "cuts": 0, "frames": 0, "stale_reads": 0}


## R2c: a part of someone drawn this far gone (0 solid, 1 gone): the stylized
## material's screen-door dissolve (props/stylized.gd), else the geometry's own
## transparency (a label, a tool with its own material).
static func fade_geometry(geo: GeometryInstance3D, amount: float) -> void:
	if geo == null:
		return
	if geo.has_meta(&"keep_material"):
		geo.set_instance_shader_parameter(&"dissolve", amount)
	else:
		geo.transparency = amount


## Where a node is drawn this frame (R2c stage). Its interpolated transform is the
## physics interpolation's cache from the LAST rendered frame, so a node placed
## somewhere new since then (the escort's follow anchor, last left beside the
## head NICE BOY at Annex B, ~1,414 m from the yard) still reads where it was. A
## shot pushed on that frame swept its eye from there, and the speed clamp then
## kept the camera filming an empty field across the map for the whole escort
## (audit r2b c1-escort-cam-teleport-flash, escort-cam-1400m-away). An
## interpolated pose further than STAGE_CAM_STALE_METERS from the real one is a
## stale cache, not motion (nothing the stage films moves that far in one tick):
## the real pose wins, and the log counts it.
static func drawn_pose(node: Node3D) -> Transform3D:
	var real := node.global_transform
	if not node.is_physics_interpolated_and_enabled():
		return real
	var drawn := node.get_global_transform_interpolated()
	if drawn.origin.distance_to(real.origin) > Constants.STAGE_CAM_STALE_METERS:
		log["stale_reads"] = int(log.get("stale_reads", 0)) + 1
		return real
	return drawn


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
	_self_meshes.clear()
	var head := player.get_node_or_null("Visual/Head") as Node3D if player != null else null
	if head != null and outgoing.origin.distance_to(drawn_pose(head).origin) < Constants.STAGE_SELF_REVEAL_NEAR:
		_from_inside = true
	if next != _top:
		_yaw = 0.0
		_pitch = 0.0
		_smoothed = Vector3.INF
		_clear_dist = INF
	_top = next
	_returning = false
	_start_blend(outgoing, outgoing_fov, blend_seconds)
	if not current and _rig_active():
		# make_current takes current from the old camera in the same call: never a
		# frame with none.
		make_current()
	if not was_live:
		_last_origin = Vector3.INF
	# _update places the eye, then masks from where it really is (R2c: masking
	# first judged the swing out of your head from wherever this camera was left).
	_update(0.0)


func _start_blend(from: Transform3D, from_fov: float, seconds: float) -> void:
	_from = from
	_from_fov = from_fov
	# The new arc starts exactly where the view is drawn now.
	_last_arc = from.origin
	_blend_seconds = Constants.STAGE_BLEND_DEFAULT if seconds < 0.0 else seconds
	_blend_t = 0.0 if _blend_seconds > 0.0 else 1.0
	if _blend_seconds <= 0.0:
		log["cuts"] = int(log["cuts"]) + 1
		_last_origin = Vector3.INF
		_has_last = false
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
		return drawn_pose(base)
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
	_frame_out(delta)
	if _top == &"" and not _returning:
		_show_bodies()
		return
	_update(delta)


## R2c: a shot with "subjects" (the gotcha two-shot: you and him) is about them
## alone. Anyone else (another NICE BOY, a hired hand, a homeowner) who comes
## into its frame nearer than the subjects' far side fades out (a teammate, or
## another caught pair named by "frame_out_partner", only when blocking the view:
## _team_blocks), and so does whatever a subject is holding ("frame_out_held": the trimmer across
## his chest); they fade back in once the shot lets go. The audit saw three NICE
## BOYS in a row in the two-shot and a half-face cut by its left edge.
func _frame_out(delta: float) -> void:
	var shot: Dictionary = _shots.get(_top, {}) if _top != &"" else {}
	var subjects: Array = shot.get("subjects", [])
	var want: Dictionary = {}
	if not subjects.is_empty() and current:
		var eye := global_position
		var reach := 0.0
		for subject: Variant in subjects:
			if is_instance_valid(subject):
				reach = maxf(reach, eye.distance_to((subject as Node3D).global_position))
		reach += Constants.STAGE_FRAME_OUT_BEYOND
		# "frame_out_partner": the other half of a caught pair (the Encounter: a
		# NICE BOY holding someone else, that someone's captor). A NICE BOY with a
		# partner goes by the teammate rule, and a pair fades together or not at
		# all: another caught pair never walks past as a captive held by nobody.
		var partner_of: Callable = shot.get("frame_out_partner", Callable())
		for group: StringName in Constants.STAGE_FRAME_OUT_GROUPS:
			for node: Node in get_tree().get_nodes_in_group(group):
				if node == player or subjects.has(node) or not (node is Node3D) or want.has(node):
					continue
				var at := _feet(node as Node3D)
				# Their middle and both flanks: a body at the frame's edge, its middle
				# just out, still showed a shoulder and flickered in and out (rec_g_two_fr
				# 179-257, a teammate 0.9 m off the lens).
				var in_frame := false
				var side := global_basis.x * Constants.STAGE_FRAME_OUT_HALF_WIDTH
				for height: float in [0.4, 1.2, 1.7]:
					for across: Vector3 in [Vector3.ZERO, side, -side]:
						if is_position_in_frustum(at + Vector3.UP * height + across):
							in_frame = true
				if not in_frame or eye.distance_to(at) >= reach:
					continue
				var partner: Node3D = partner_of.call(node) as Node3D if partner_of.is_valid() else null
				if partner != null and not is_instance_valid(partner):
					partner = null
				if node.is_in_group(&"players") or partner != null:
					var blocks := _team_blocks(eye, node as Node3D, subjects)
					if not blocks and partner != null:
						blocks = _team_blocks(eye, partner, subjects)
					if not blocks:
						continue
					if partner != null and not subjects.has(partner) and partner != player:
						want[partner] = true
				want[node] = true
		if bool(shot.get("frame_out_held", false)):
			for node: Node in get_tree().get_nodes_in_group("props"):
				var holder := int(node.get("held_by")) if "held_by" in node else 0
				for subject: Variant in subjects:
					if holder != 0 and is_instance_valid(subject) and str((subject as Node).name) == str(holder):
						want[node] = true
	for node: Variant in want:
		if not _faded.has(node):
			_faded[node] = {"meshes": (node as Node).find_children("*", "GeometryInstance3D", true, false), "amount": 0.0}
	var step := delta / maxf(Constants.STAGE_FRAME_OUT_SECONDS, 0.01)
	for node: Variant in _faded.keys():
		var entry: Dictionary = _faded[node]
		if not is_instance_valid(node):
			_faded.erase(node)
			continue
		var amount := move_toward(float(entry["amount"]), 1.0 if want.has(node) else 0.0, step)
		entry["amount"] = amount
		for mesh: Variant in entry["meshes"]:
			if is_instance_valid(mesh):
				fade_geometry(mesh as GeometryInstance3D, amount)
		if amount <= 0.0:
			_faded.erase(node)


## A teammate stays in the shot: they're who comes to get you out (a punch is
## thrown from PUNCH_REACH of him, a throw from close by), and a NICE BOY reeling
## from nobody was the rescue's payoff gone from the one view it matters in. One
## fades only when standing in the lens (flat, nearer the eye than
## STAGE_FRAME_OUT_TEAM_LENS: a shirt filled a third of the frame, rec_f_two_fr
## 172-263), or in front of you or him: nearer the eye and overlapping one of
## you on screen (a bystander the walk passed hid the pair, rec_j_two_fr
## 277-295). A rescuer swinging at him from beside him stays. Once faded, both
## tests have STAGE_FRAME_OUT_TEAM_SLACK of give, so nobody flickers on a line.
func _team_blocks(eye: Vector3, body: Node3D, subjects: Array) -> bool:
	var at := _feet(body)
	var slack := Constants.STAGE_FRAME_OUT_TEAM_SLACK if _faded.has(body) and float((_faded[body] as Dictionary)["amount"]) > 0.0 else 0.0
	if Vector2(at.x - eye.x, at.z - eye.z).length() < Constants.STAGE_FRAME_OUT_TEAM_LENS + slack:
		return true
	var middle := at + Vector3.UP * 1.0
	if is_position_behind(middle):
		return false
	var look := -global_basis.z
	var depth := (middle - eye).dot(look)
	if depth <= 0.05:
		return false
	# Pixels per meter at depth 1: the vertical field of view across the viewport.
	var focal := get_viewport().get_visible_rect().size.y * 0.5 / tan(deg_to_rad(fov) * 0.5)
	var half := Constants.STAGE_FRAME_OUT_HALF_WIDTH
	var on_screen := unproject_position(middle)
	for subject: Variant in subjects:
		if not is_instance_valid(subject):
			continue
		var theirs := _feet(subject as Node3D) + Vector3.UP * 1.0
		var their_depth := (theirs - eye).dot(look)
		if their_depth <= 0.05 or depth > their_depth - Constants.STAGE_FRAME_OUT_TEAM_IN_FRONT:
			continue
		var apart := absf(on_screen.x - unproject_position(theirs).x)
		if apart < focal * (half / depth + half / their_depth) * (1.0 + slack):
			return true
	return false


## Where a body is drawn (its Visual, smoothed on a client), at its feet.
static func _feet(body: Node3D) -> Vector3:
	var visual := body.get_node_or_null("Visual") as Node3D
	return visual.global_position if visual != null else body.global_position


func _update(delta: float) -> void:
	var target := Transform3D()
	var target_fov := Settings.fov()
	var pivot := Vector3.INF
	var max_speed := 0.0
	var collide := false
	if _top != &"":
		var shot: Dictionary = _shots[_top]
		target = _shot_transform(shot, delta)
		if float(shot.get("fov", 0.0)) > 0.0:
			target_fov = float(shot["fov"])
		pivot = _pivot_of(shot)
		if pivot.is_finite():
			max_speed = float(shot.get("max_speed", Constants.STAGE_CAM_MAX_SPEED))
			collide = bool(shot.get("collide", false))
	else:
		var base := base_camera()
		if base == null:
			_finish_return()
			return
		target = drawn_pose(base)
		target_fov = base.fov
	var was_t := _blend_t
	if _blend_t < 1.0 and _blend_seconds > 0.0:
		_blend_t = minf(1.0, _blend_t + delta / _blend_seconds)
	if pivot.is_finite() and max_speed > 0.0 and delta > 0.0 and was_t < 1.0:
		_blend_t = _paced(was_t, _blend_t, target, pivot, max_speed, delta)
	# Ease in and out: no blend leaves at full speed.
	var eased := smoothstep(0.0, 1.0, _blend_t)
	var drawn := target
	if eased < 1.0:
		drawn = _arc(_from, target, pivot, _blend_t) if pivot.is_finite() else _from.interpolate_with(target, eased)
	_last_arc = drawn.origin
	drawn.basis = drawn.basis.orthonormalized()
	# The eye actually drawn is what's kept clear, every frame of the swing too
	# (R2b: a swing out of first person pulls back behind you first; caught with
	# your back to a hedge, it went through it).
	if collide:
		drawn.origin = _keep_clear(pivot, drawn.origin, delta)
	if max_speed > 0.0 and delta > 0.0:
		drawn = _clamped(drawn, pivot, max_speed, delta)
		if collide:
			# The clamp lands between last frame and this one: still never in a wall.
			drawn.origin = _clear_now(pivot, drawn.origin)
	_last_drawn = drawn
	_last_pivot = pivot
	_has_last = true
	global_transform = drawn
	_apply_mask()
	fov = lerpf(_from_fov, target_fov, eased)
	_note_step(drawn.origin)
	if _returning and _blend_t >= 1.0:
		_finish_return()


## The shot's pivot in world space, or INF without one.
func _pivot_of(shot: Dictionary) -> Vector3:
	var pivot: Variant = shot.get("pivot")
	if pivot is Node3D and is_instance_valid(pivot) and (pivot as Node3D).is_inside_tree():
		return drawn_pose(pivot as Node3D).origin
	if pivot is Vector3:
		return pivot
	return Vector3.INF


## A blend about a pivot: round it, not through it. The eye's distance from the
## pivot eases a little ahead of its angle (it pulls back, then swings round), and
## it looks from where the old view looked to where the new one does, so the
## first frame is exactly the old view and the last exactly the new one.
func _arc(a: Transform3D, b: Transform3D, pivot: Vector3, u: float) -> Transform3D:
	var ra := a.origin - pivot
	var rb := b.origin - pivot
	var flat_a := Vector2(ra.x, ra.z).length()
	var flat_b := Vector2(rb.x, rb.z).length()
	var angle_b := atan2(rb.x, rb.z)
	var angle_a := atan2(ra.x, ra.z) if flat_a > 0.05 else angle_b
	var swing := smoothstep(0.0, 1.0, u)
	var pull := smoothstep(0.0, 1.0, minf(1.0, u * 1.5))
	var angle := angle_a + wrapf(angle_b - angle_a, -PI, PI) * swing
	var flat := lerpf(flat_a, flat_b, pull)
	# A little lift on the way (it rises over a shoulder rather than sliding past
	# the back of a head).
	var lift := Constants.STAGE_CAM_ARC_LIFT * sin(PI * swing) if flat_a < flat_b else 0.0
	var eye := pivot + Vector3(sin(angle) * flat, lerpf(ra.y, rb.y, swing) + lift, cos(angle) * flat)
	var look_a := a.origin - a.basis.z.normalized() * maxf(0.5, ra.length())
	var look_b := b.origin - b.basis.z.normalized() * maxf(0.5, rb.length())
	var look := look_a.lerp(look_b, swing) - eye
	if look.length() < 0.01 or absf(look.normalized().dot(Vector3.UP)) > 0.999:
		var fallback := a.interpolate_with(b, swing)
		fallback.origin = eye
		return fallback
	return Transform3D(Basis.looking_at(look, Vector3.UP), eye)


## Keep the eye clear of the world and the vehicles: a sphere swept from the
## pivot; in at once when something's in the way, back out at a walk.
func _keep_clear(pivot: Vector3, eye: Vector3, delta: float) -> Vector3:
	var full := pivot.distance_to(eye)
	if full < 0.01:
		return eye
	var exclude := _Sweep.passable(get_tree())
	var allowed := full * _Sweep.reach(get_world_3d(), pivot, eye, Constants.STAGE_CAM_RADIUS, exclude)
	if allowed < _clear_dist or not is_finite(_clear_dist):
		_clear_dist = allowed
	else:
		_clear_dist = minf(allowed, _clear_dist + Constants.STAGE_CAM_RELEASE_SPEED * maxf(delta, 0.0))
	return pivot + (eye - pivot) / full * minf(full, _clear_dist)


## A swing faster than max_speed is slowed, not cut short: the blend only gets
## as far along its arc this frame as max_speed allows (R2b: clamping the eye
## after the fact chased the arc point in straight lines, through the pivot).
## It always gets a quarter of its normal step, so a moving shot can't stall it.
func _paced(from_u: float, to_u: float, target: Transform3D, pivot: Vector3, max_speed: float, delta: float) -> float:
	if not _has_last or not _last_arc.is_finite() or _iris_closed():
		return to_u
	var start := _last_arc + _carried(pivot, delta)
	var most := max_speed * delta
	if _arc_origin(target, pivot, to_u).distance_to(start) <= most:
		return to_u
	var lo := from_u
	var hi := to_u
	for _i: int in 10:
		var mid := (lo + hi) * 0.5
		if _arc_origin(target, pivot, mid).distance_to(start) <= most:
			lo = mid
		else:
			hi = mid
	return maxf(lo, from_u + (to_u - from_u) * 0.25)


func _arc_origin(target: Transform3D, pivot: Vector3, u: float) -> Vector3:
	return target.origin if u >= 1.0 else _arc(_from, target, pivot, u).origin


## How far the pivot carries the eye this frame: its own move, no faster than
## STAGE_CAM_PIVOT_MAX_SPEED.
func _carried(pivot: Vector3, delta: float) -> Vector3:
	if not pivot.is_finite() or not _last_pivot.is_finite():
		return Vector3.ZERO
	return (pivot - _last_pivot).limit_length(Constants.STAGE_CAM_PIVOT_MAX_SPEED * delta)


## The same sweep with no memory and only the near plane's size: the speed
## clamp's eye (between last frame's and this one's, both clear) is pulled in
## only if the near plane itself would be in something (a wall's corner).
func _clear_now(pivot: Vector3, eye: Vector3) -> Vector3:
	var full := pivot.distance_to(eye)
	if full < 0.01:
		return eye
	var reach := _Sweep.reach(get_world_3d(), pivot, eye, maxf(near, 0.02), _Sweep.passable(get_tree()))
	return pivot + (eye - pivot) * reach


## No faster than max_speed relative to the pivot (it may ride a walking pair),
## no faster a turn than STAGE_CAM_MAX_TURN, and the pivot itself carries the eye
## no faster than STAGE_CAM_PIVOT_MAX_SPEED (an anchor read from a stale pose
## glides the camera over, never jumps it), unless the iris covers it.
func _clamped(drawn: Transform3D, pivot: Vector3, max_speed: float, delta: float) -> Transform3D:
	if not _has_last or _iris_closed():
		return drawn
	var start := _last_drawn.origin + _carried(pivot, delta)
	var step := drawn.origin - start
	var most := max_speed * delta
	var out := drawn
	if step.length() > most:
		out.origin = start + step.normalized() * most
	var from_q := _last_drawn.basis.orthonormalized().get_rotation_quaternion()
	var to_q := drawn.basis.orthonormalized().get_rotation_quaternion()
	var angle := from_q.angle_to(to_q)
	var turn := Constants.STAGE_CAM_MAX_TURN * delta
	if angle > turn:
		out.basis = Basis(from_q.slerp(to_q, turn / angle))
	return out


func _iris_closed() -> bool:
	var iris := get_tree().get_first_node_in_group("iris")
	return iris != null and bool(iris.call("is_closed"))


func _finish_return() -> void:
	_returning = false
	_has_last = false
	_from_inside = false
	_set_self_fade(0.0)
	_show_bodies()
	var base := base_camera()
	if not _rig_active():
		# Something else has the view (the crossing camera): leave it there.
		current = false
	elif base != null:
		# Current goes straight to the base camera in this one call.
		base.make_current()
	_last_origin = Vector3.INF


## Whether the rig this hangs under has the view (CameraRig.set_active).
func _rig_active() -> bool:
	var rig := get_parent()
	return rig == null or not rig.has_method("is_active") or bool(rig.call("is_active"))


func _shot_transform(shot: Dictionary, delta: float) -> Transform3D:
	var anchor := shot["anchor"] as Node3D
	var frame := drawn_pose(anchor)
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
## from outside shows them, an eye inside your head (hide_self) skips them, and
## so does any eye still within HEAD_CLEAR_METERS of your head (a blend out of
## first person starts inside it: it used to flash your own face for a frame).
func _apply_mask() -> void:
	var head_bit := 1 << (_CartoonBody.HEAD_LAYER - 1)
	var hide := _top != &"" and bool((_shots[_top] as Dictionary).get("hide_self", false))
	var head := player.get_node_or_null("Visual/Head") as Node3D if player != null else null
	var away := global_position.distance_to(drawn_pose(head).origin) if head != null else INF
	if away < HEAD_CLEAR_METERS:
		hide = true
	# R2c: an eye that leaves your head (a swing out of first person, the hide's
	# pull) or comes back into it brings your own body in and out as a dissolve
	# by how far the eye is from your head: hidden until the eye has cleared it by
	# STAGE_SELF_REVEAL_NEAR, whole by STAGE_SELF_REVEAL_FAR. Your own cap, beak
	# and mitts used to fill a third of the frame as the swing passed them.
	var fade := 0.0
	if not hide and away < Constants.STAGE_SELF_REVEAL_FAR and (_returning or _from_inside):
		fade = 1.0 - smoothstep(Constants.STAGE_SELF_REVEAL_NEAR, Constants.STAGE_SELF_REVEAL_FAR, away)
		if fade >= 0.98:
			hide = true
	if _from_inside and (away >= Constants.STAGE_SELF_REVEAL_FAR or (_blend_t >= 1.0 and not _returning)):
		# Cleared it (or a shot that stays close settled): whole from here on.
		_from_inside = false
	_set_self_fade(0.0 if hide else fade)
	cull_mask = (0xFFFFF & ~head_bit) if hide else 0xFFFFF
	_hide_near_bodies()


## Your own body's meshes (HEAD_LAYER, under your Visual) drawn this transparent:
## only this peer draws them on that layer, so nobody else's view changes.
func _set_self_fade(amount: float) -> void:
	if is_equal_approx(amount, _self_fade):
		return
	_self_fade = amount
	if player == null:
		return
	if _self_meshes.is_empty() or not is_instance_valid(_self_meshes[0]):
		_self_meshes.clear()
		var visual := player.get_node_or_null("Visual")
		if visual == null:
			return
		var head_bit := 1 << (_CartoonBody.HEAD_LAYER - 1)
		for node: Node in visual.find_children("*", "GeometryInstance3D", true, false):
			if ((node as GeometryInstance3D).layers & head_bit) != 0:
				_self_meshes.append(node as GeometryInstance3D)
	for mesh: GeometryInstance3D in _self_meshes:
		if is_instance_valid(mesh):
			fade_geometry(mesh, amount)


## R2b: anyone else's body (a teammate, a NICE BOY) with the eye inside or right
## against it isn't drawn while this camera has the view: a blend past his head
## never fills the screen with the inside of a face.
func _hide_near_bodies() -> void:
	if not current:
		_show_bodies()
		return
	var eye := global_position
	var near: Array[Node3D] = []
	for group: StringName in [&"players", &"nice_crew"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node == player or not (node is Node3D):
				continue
			var body := node.get_node_or_null("Visual/CartoonBody") as Node3D
			if body == null:
				continue
			var feet := body.global_position
			# The closest point on his middle line, from the hips to the top of the head.
			var low := feet + Vector3.UP * 0.6
			var high := feet + Vector3.UP * 1.95
			var along := clampf((eye - low).dot(high - low) / (high - low).length_squared(), 0.0, 1.0)
			if eye.distance_to(low.lerp(high, along)) < Constants.STAGE_CAM_BODY_CLEAR:
				near.append(body)
	for body: Node3D in _hidden_bodies:
		if is_instance_valid(body) and not near.has(body):
			body.visible = true
	for body: Node3D in near:
		body.visible = false
	_hidden_bodies = near


func _show_bodies() -> void:
	for body: Node3D in _hidden_bodies:
		if is_instance_valid(body):
			body.visible = true
	_hidden_bodies.clear()
