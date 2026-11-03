extends Camera3D

## Authority: local presentation. The chase camera behind a vehicle you sit in
## (player/seated.gd adds it under your own player; the camera key swaps it with
## your own eyes). It follows the vehicle's rendered body on physics ticks, so
## physics interpolation smooths it with the truck: Constants.CHEFTY_CAMERA_BACK
## behind and CHEFTY_CAMERA_UP over it, looking a little ahead by speed, the field
## of view widening with speed. The mouse swings it round (the seat's look).
##
## NEVER INSIDE ANYTHING (driving chunk E2). The boom runs from a pivot over the
## cab roof (CHEFTY_CAMERA_PIVOT_UP, so pulling all the way in never puts the
## lens in the truck) out to where the camera wants to be, and each tick a sphere
## is swept along it against the world's solids (houses, trunks, lamps, parked
## cars, landmarks: layer 1, the truck's own bodies left out) and against the tree
## crowns (props/view_blockers.gd; crowns have no colliders). When something
## blocks it the boom pulls in, quickly but eased and never faster than
## CHEFTY_CAMERA_PULL_SPEED, starting a little before the blocker reaches the
## lens (the sweep's sphere is CHEFTY_CAMERA_CLEARANCE wide); when the way is
## clear it lets back out slowly (CHEFTY_CAMERA_EASE_OUT). It also sweeps where
## the boom is swinging to (looking round from the seat, a corner), so the pull-in
## starts before the boom reaches a lamp post or a wall rather than sliding the
## lens through it. Only a solid that gets between the truck and the lens faster
## than that (backing into a wall) makes it cut in front of it (`cuts`). People
## (a hired hand in the bed, a walker) never push it in. Pulled in, it looks
## farther ahead, over the hood, instead of down at the roof.
##
## A crown the lens still ends up inside (the truck itself under a low tree, or
## your own eyes in the bed passing under one) fades out with the stylized
## material's screen-door dissolve while the lens is in it, and back in after:
## whichever of this camera or the seat's own eyes is current.

const _ViewBlockers = preload("res://props/view_blockers.gd")

var vehicle: Node3D
var player: Node3D
var _placed: bool = false
## Where the camera would be with nothing in the way (eased toward the wanted spot).
var _free := Vector3.ZERO
## The boom's length now, pivot to lens (m), and whether it is set yet.
var _boom: float = -1.0
## The truck's own physics bodies (left out of the sweep), and its id they're for.
var _exclude: Array[RID] = []
var _exclude_for: int = 0
## Crowns faded out now: instance id -> {node, amount, want}.
var _faded: Dictionary = {}
## The boom's sweep, made once.
var _query: PhysicsShapeQueryParameters3D
## For tests: the last sweep's numbers (boom allowed on its own ray, the target
## with the swing ahead, boom now, free length), and how many times it had to cut.
var last := {"want": 0.0, "target": 0.0, "boom": 0.0, "length": 0.0, "blocked": false, "inside_crowns": 0, "cuts": 0}
var cuts: int = 0


func _ready() -> void:
	# After the vehicle (0), its view (50) and the players (100) have moved.
	process_physics_priority = 120
	fov = Constants.CHEFTY_CAMERA_FOV.x


func _exit_tree() -> void:
	for id: int in _faded.keys():
		_set_fade((_faded[id] as Dictionary)["node"], 0.0)
	_faded.clear()


## Jump straight to the spot behind the vehicle (no swing in from wherever).
func snap() -> void:
	_placed = false


func _physics_process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var body: Transform3D = vehicle.call("body_transform")
	var look := float(player.get("seat_look")) if player != null else 0.0
	var heading := float(vehicle.call("yaw")) + look
	var behind := Vector3(sin(heading), 0.0, cos(heading))
	var speed := float(vehicle.call("speed"))
	var forward := Vector3(-sin(heading), 0.0, -cos(heading))
	var focus := body.origin + Vector3(0.0, 1.6, 0.0) + forward * speed * Constants.CHEFTY_CAMERA_LEAD
	var want := body.origin + behind * Constants.CHEFTY_CAMERA_BACK + Vector3.UP * Constants.CHEFTY_CAMERA_UP
	var pivot := body.origin + Vector3.UP * Constants.CHEFTY_CAMERA_PIVOT_UP
	if not _placed:
		_free = want
		_boom = -1.0
	else:
		_free = _free.lerp(want, 1.0 - exp(-Constants.CHEFTY_CAMERA_FOLLOW * delta))
	var arm := _free - pivot
	var length := arm.length()
	var direction := arm / length if length > 0.001 else behind
	# x: clear of solids only; y: of solids and crowns.
	var clear := _clear_length(pivot, direction, length)
	var allowed := clear.y
	# Ahead of the swing: the boom also checks where it is swinging to (halfway,
	# and all the way to where it wants to be), so it starts pulling in before it
	# reaches a lamp post or a wall instead of sliding in through it.
	var target := allowed
	var want_arm := want - pivot
	if _placed and want_arm.length() > 0.001:
		var want_dir := want_arm.normalized()
		if want_dir.dot(direction) < Constants.CHEFTY_CAMERA_AHEAD_DOT:
			target = minf(target, _clear_length(pivot, direction.slerp(want_dir, 0.5), length).y)
			target = minf(target, _clear_length(pivot, want_dir, length).y)
	if _boom < 0.0:
		_boom = allowed
	elif target < _boom:
		var step := (_boom - target) * (1.0 - exp(-Constants.CHEFTY_CAMERA_PULL_RATE * delta))
		_boom -= minf(step, Constants.CHEFTY_CAMERA_PULL_SPEED * delta)
	else:
		_boom = minf(target, _boom + (target - _boom) * (1.0 - exp(-Constants.CHEFTY_CAMERA_EASE_OUT * delta)))
	# A solid came between the truck and the lens faster than any pull-in (a
	# wall the truck backed up to): the view is the wall's, so cut in front of it
	# rather than look at its inside. Never otherwise; a crown it ends up in fades.
	if _boom > clear.x + Constants.CHEFTY_CAMERA_CLEARANCE + Constants.CHEFTY_CAMERA_RADIUS:
		_boom = clear.x
		reset_physics_interpolation()
		cuts += 1
	_boom = clampf(_boom, 0.0, length)
	last = {"want": allowed, "target": target, "boom": _boom, "length": length, "blocked": allowed < length - 0.01, "inside_crowns": _faded.size(), "cuts": cuts}
	global_position = pivot + direction * _boom
	if not _placed:
		reset_physics_interpolation()
		_placed = true
	# Pulled in, look on over the hood rather than down at the roof.
	var pulled := clampf(1.0 - _boom / maxf(length, 0.001), 0.0, 1.0)
	focus += forward * pulled * Constants.CHEFTY_CAMERA_PULLED_LOOK_AHEAD + Vector3.UP * pulled * (Constants.CHEFTY_CAMERA_PIVOT_UP - 1.6)
	if global_position.distance_to(focus) > 0.1:
		look_at(focus, Vector3.UP)
	var share := clampf(speed / Constants.CHEFTY_TOP_SPEED, 0.0, 1.0)
	fov = lerpf(Constants.CHEFTY_CAMERA_FOV.x, Constants.CHEFTY_CAMERA_FOV.y, share)
	_fade_crowns(delta)


## How much of the boom (m, from the pivot) is clear, less the clearance kept in
## front of whatever blocks it: x of the world's solids only, y of solids and
## tree crowns.
func _clear_length(pivot: Vector3, direction: Vector3, length: float) -> Vector2:
	var reach := length + Constants.CHEFTY_CAMERA_CLEARANCE
	var tip := pivot + direction * reach
	var crowns := _ViewBlockers.sweep(pivot, tip, Constants.CHEFTY_CAMERA_RADIUS)
	var share := 1.0
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space != null:
		if _query == null:
			var sphere := SphereShape3D.new()
			sphere.radius = Constants.CHEFTY_CAMERA_RADIUS
			_query = PhysicsShapeQueryParameters3D.new()
			_query.shape = sphere
			_query.collision_mask = 1
		var skip: Array[RID] = _vehicle_bodies().duplicate()
		# The sweep goes out from the pivot in legs: people never push the lens
		# in (a hired hand in the bed, a walker on the sidewalk), and a thin solid
		# (a lamp post, a power pole, a trunk) only does when it's at the lens's
		# end of the boom; nearer the truck it just passes between, like a post
		# going by the window, and the next leg starts past it.
		var from := 0.0
		for _try: int in 6:
			_query.transform = Transform3D(Basis.IDENTITY, pivot + direction * from)
			_query.motion = direction * (reach - from)
			_query.exclude = skip
			var fractions := space.cast_motion(_query)
			if fractions.size() != 2 or float(fractions[1]) >= 1.0:
				break
			var contact := from + (reach - from) * float(fractions[0])
			_query.transform = Transform3D(Basis.IDENTITY, pivot + direction * (from + (reach - from) * float(fractions[1])))
			var hit := space.get_rest_info(_query)
			var who: Object = instance_from_id(int(hit.get("collider_id", 0))) if not hit.is_empty() else null
			if who is CharacterBody3D:
				skip.append(hit["rid"])
				continue
			var thin := _thin_extent(who, int(hit.get("shape", 0)))
			if thin > 0.0 and contact < length - Constants.CHEFTY_CAMERA_THIN_NEAR_LENS:
				from = contact + thin + Constants.CHEFTY_CAMERA_RADIUS * 2.0 + 0.05
				if from >= reach:
					break
				continue
			share = contact / reach
			break
	var solids := clampf(share * reach - Constants.CHEFTY_CAMERA_CLEARANCE, 0.0, length)
	return Vector2(solids, minf(solids, clampf(crowns * reach - Constants.CHEFTY_CAMERA_CLEARANCE, 0.0, length)))


## How wide (m) the shape that was hit is across, when it's thin enough to look
## past (Constants.CHEFTY_CAMERA_THIN_SOLID: posts, poles, trunks); 0 otherwise.
static func _thin_extent(body: Object, shape_index: int) -> float:
	var solid := body as CollisionObject3D
	if solid == null:
		return 0.0
	var owner_id := solid.shape_find_owner(shape_index)
	if owner_id < 0 or solid.shape_owner_get_shape_count(owner_id) == 0:
		return 0.0
	var shape := solid.shape_owner_get_shape(owner_id, 0)
	var across := INF
	if shape is CylinderShape3D:
		across = (shape as CylinderShape3D).radius * 2.0
	elif shape is CapsuleShape3D:
		across = (shape as CapsuleShape3D).radius * 2.0
	elif shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		across = maxf(size.x, size.z)
	return across if across <= Constants.CHEFTY_CAMERA_THIN_SOLID else 0.0


## The truck's own collision bodies (its look's Solid, the chassis), found once.
func _vehicle_bodies() -> Array[RID]:
	var id := vehicle.get_instance_id()
	if _exclude_for != id or _exclude.is_empty():
		_exclude_for = id
		_exclude.clear()
		_collect(vehicle)
	return _exclude


func _collect(node: Node) -> void:
	var body := node as CollisionObject3D
	if body != null:
		_exclude.append(body.get_rid())
	for child: Node in node.get_children():
		_collect(child)


## Fades the crowns the current view's lens is inside (this camera, or the seat's
## own eyes when they're the current camera), and brings back the ones it left.
func _fade_crowns(delta: float) -> void:
	var view := get_viewport().get_camera_3d() if is_inside_tree() else null
	var lens := Vector3.INF
	if view == self or (view != null and player != null and player.is_ancestor_of(view)):
		lens = view.global_position
	for id: int in _faded:
		(_faded[id] as Dictionary)["want"] = 0.0
	if lens != Vector3.INF:
		for hit: Array in _ViewBlockers.inside(lens, Constants.CHEFTY_CAMERA_CROWN_PAD):
			var tree: Node3D = hit[0]
			var id := tree.get_instance_id()
			if not _faded.has(id):
				_faded[id] = {"node": tree, "amount": 0.0, "want": 0.0}
			_faded[id]["want"] = clampf(float(hit[1]) * Constants.CHEFTY_CAMERA_CROWN_FADE_DEPTH, 0.0, Constants.CHEFTY_CAMERA_CROWN_FADE_MAX)
	for id: int in _faded.keys():
		var fade: Dictionary = _faded[id]
		if not is_instance_valid(fade["node"]):
			_faded.erase(id)
			continue
		var amount := move_toward(float(fade["amount"]), float(fade["want"]), Constants.CHEFTY_CAMERA_CROWN_FADE_RATE * delta)
		fade["amount"] = amount
		_set_fade(fade["node"], amount)
		if amount <= 0.0 and float(fade["want"]) <= 0.0:
			_faded.erase(id)


static func _set_fade(tree: Variant, amount: float) -> void:
	if not is_instance_valid(tree):
		return
	for part: String in ["Look", "LookFar"]:
		var mesh := (tree as Node).get_node_or_null(part) as GeometryInstance3D
		if mesh != null:
			mesh.set_instance_shader_parameter(&"dissolve", amount)
