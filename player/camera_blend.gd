extends Camera3D

## Authority: local presentation. An eased hand-over between two of this peer's
## cameras (fx-chefty: getting into Chefty's driver's seat swings the view from
## your eyes out to the chase camera, and getting out brings it back down to your
## eyes, where both used to cut). For the blend's length this camera is current
## and sits between the two: it starts where `from` was when the blend began
## (frozen there: the view you had) and ends on `to`, wherever `to` has got to by
## then (your eyes mid-hop, or the chase camera following the truck), easing in
## and out, the field of view with it. Then `to` is made current and this goes,
## along with `from` if it was handed over to be freed. If anything else takes the
## view meanwhile (a stage shot, getting straight back in), the blend just ends.

## The camera the view ends on.
var to: Camera3D
## The view it starts from (a world transform, and its field of view).
var from_xform := Transform3D.IDENTITY
var from_fov: float = 75.0
## How long it takes (s), and how far through it is.
var seconds: float = 0.7
var _t: float = 0.0
## Freed when the blend ends (the chase camera you just got out from behind).
var free_after: Node = null
## A point the lens swings out through halfway (world), so it goes round the
## truck's side instead of through its bed and cab; INF for a straight line.
var via := Vector3.INF


## Starts a blend from what `from` shows now to `to`, under parent (the player).
## Returns the blend camera, already current. free_from: free `from` at the end.
## through: the point the lens passes halfway (INF: straight there).
static func start(parent: Node, from: Camera3D, to_camera: Camera3D, length: float, free_from: bool = false, through := Vector3.INF) -> Camera3D:
	var old := parent.get_node_or_null("CameraBlend")
	if old != null:
		old.call("_end", false)
	var blend: Camera3D = load("res://player/camera_blend.gd").new()
	blend.name = "CameraBlend"
	blend.set("to", to_camera)
	blend.set("from_xform", from.get_global_transform_interpolated() if from.is_inside_tree() else from.global_transform)
	blend.set("from_fov", from.fov)
	blend.set("seconds", maxf(length, 0.01))
	if free_from:
		blend.set("free_after", from)
	blend.set("via", through)
	parent.add_child(blend)
	blend.top_level = true
	blend.global_transform = blend.from_xform
	blend.fov = from.fov
	blend.near = to_camera.near
	blend.far = to_camera.far
	blend.cull_mask = to_camera.cull_mask
	blend.make_current()
	return blend


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	if to == null or not is_instance_valid(to) or not to.is_inside_tree():
		_end(false)
		return
	# Something else took the view (a stage shot, back in the seat): we're done.
	if not current:
		_end(false)
		return
	_t = minf(_t + delta / seconds, 1.0)
	var eased := smoothstep(0.0, 1.0, _t)
	var target := to.get_global_transform_interpolated()
	var turn := from_xform.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), eased)
	var at := from_xform.origin.lerp(target.origin, eased)
	if via.is_finite():
		# A curve from where the view was to where it's going that passes through
		# `via` halfway (a quadratic Bezier with its control point set so).
		var control := via * 2.0 - (from_xform.origin + target.origin) * 0.5
		at = from_xform.origin * (1.0 - eased) * (1.0 - eased) + control * 2.0 * eased * (1.0 - eased) + target.origin * eased * eased
	global_transform = Transform3D(Basis(turn), at)
	fov = lerpf(from_fov, to.fov, eased)
	if _t >= 1.0:
		_end(true)


## How far through the blend it is (0..1), for tests.
func progress() -> float:
	return _t


func _end(hand_over: bool) -> void:
	if hand_over and to != null and is_instance_valid(to) and current:
		to.make_current()
	if free_after != null and is_instance_valid(free_after) and not (free_after as Camera3D).current:
		free_after.queue_free()
	free_after = null
	queue_free()
	name = "CameraBlendGone"
