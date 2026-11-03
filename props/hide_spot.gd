extends "res://net/components/hide_spot.gd"

## Authority: local look for a hiding spot (R2 chunk 3, docs/GAME.md "Hiding").
## A solid box the crew can't see through or walk through, drawn as what it is:
## planks make a garden shed with a hinged Door, metal a wheelie BigBin with a
## hinged Lid, foliage a clipped Hedge with loose leaf cards. Each build stays
## under 1.5k triangles. Who is inside is decided by the host in
## net/components/hide_spot.gd; everything here is cosmetic and runs on every
## peer from the replicated occupants, their body_yaw and their peeking.
##
## Nodes: Body (the collider), Look (the model; Door or Lid inside it),
## Entry0..3 (where a dive starts on each side), PeekAnchor (made by the base),
## InspectPoint (where a NICE BOY stands to poke it), EyeGlint (two small
## glints in the dark while someone peeks), Tells (falling leaves), Notices
## (the Courtesy Notice stickers left by near misses, all day).
## set_state(&"enter" | &"exit" | &"peek" | &"tremble" | &"inspect" | &"near_miss"
## | &"found", at, args) plays a moment from server time at.
## No "Occupied" sign: the world tells you (the lid's down, the door's shut).

const _YardModels = preload("res://props/yard_models.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _NiceSeal = preload("res://props/nice_seal.gd")
const KIND_BY_SURFACE: Dictionary = {"planks": "shed", "metal": "bin", "foliage": "hedge"}
const LEAF_COLORS: Array[Color] = [Color(0.9, 0.48, 0.15), Color(0.93, 0.72, 0.22), Color(0.75, 0.25, 0.14), Color(0.55, 0.6, 0.2)]
const HEDGE_LEAF_COLORS: Array[Color] = [Color(0.24, 0.48, 0.22), Color(0.3, 0.55, 0.25), Color(0.2, 0.4, 0.2), Color(0.55, 0.6, 0.2)]
const STEEL := Color(0.6, 0.62, 0.64)
const PAPER := Color(0.97, 0.96, 0.92)
## How far the shed door and the bin lid swing, fully open and when peeking (radians).
const DOOR_OPEN: float = 1.35
const DOOR_PEEK: float = 0.14
const LID_OPEN: float = 1.9
const LID_PEEK: float = 0.2
const LID_POKE: float = 0.28

@export var size := Vector3(1.6, 2.0, 1.6)
@export var color := Color(0.42, 0.36, 0.3)
@export var label := "Hiding spot"
## What it is made of, from props/surfaces.gd.
@export var surface := "planks"

static var _mesh_cache: Dictionary = {}

var _look: Node3D
## The shed's door or the bin's lid (a hinge pivot), or null for a hedge.
var _hinge: Node3D
var _hinge_target: float = 0.0
var _hinge_angle: float = 0.0
var _hinge_speed: float = 6.0
## The hedge's squash-wobble: how much is left and its phase.
var _wobble: float = 0.0
var _wobble_time: float = 0.0
var _glint: Node3D
var _tells: Node3D
var _notices_node: Node3D
var _rng := RandomNumberGenerator.new()
var _next_leaf: float = 0.0
var _yaw_seen: Dictionary = {}
var _tremble_cool: Dictionary = {}
var _peek_shown: Dictionary = {}
## Owner-predicted entries: peer -> local msec until which the confirmation's
## repeat of the same dive is skipped (the owner already played it).
var _predicted: Dictionary = {}
var _poking: float = 0.0
var _poke_kind: StringName = &""
## When each occupant got in (local msec), so settling in isn't read as a tremble.
var _entered_ms: Dictionary = {}


func _ready() -> void:
	spot_kind = str(KIND_BY_SURFACE.get(surface, "shed"))
	box_size = size
	capacity = Constants.HIDE_SHED_CAPACITY if spot_kind == "shed" else Constants.HIDE_CAPACITY
	super()
	# The NICE BOYS poke and shrug with gestures from player/hide_gestures.gd.
	preload("res://player/hide_gestures.gd").register()
	_rng.seed = hash(str(get_path())) if is_inside_tree() else 7
	var body := StaticBody3D.new()
	body.name = "Body"
	body.position.y = size.y * 0.5
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	_build_look()
	for side: int in SIDES.size():
		var entry := Marker3D.new()
		entry.name = "Entry%d" % side
		add_child(entry)
		entry.global_position = entry_point(side)
	var inspect := Marker3D.new()
	inspect.name = "InspectPoint"
	add_child(inspect)
	inspect.global_position = inspect_point()
	peek_anchor(0, 0)
	_glint = _make_glint()
	_tells = Node3D.new()
	_tells.name = "Tells"
	add_child(_tells)
	_notices_node = Node3D.new()
	_notices_node.name = "Notices"
	add_child(_notices_node)
	_next_leaf = _rng.randf_range(Constants.HIDE_LEAF_DROP_EVERY.x, Constants.HIDE_LEAF_DROP_EVERY.y)


# ---------------------------------------------------------------- the builds

func _build_look() -> void:
	var key := "%s|%s|%s" % [spot_kind, color.to_html(), size]
	match spot_kind:
		"shed":
			_look = Node3D.new()
			_look.name = "Look"
			add_child(_look)
			_look.add_child(_mesh_node(key + "|shell", _build_shed_shell))
			_hinge = Node3D.new()
			_hinge.name = "Door"
			# Hinged on the door's left edge (seen from outside, facing +Z... the
			# front is -Z), so it swings out into the yard.
			_hinge.position = Vector3(-0.42, 0.0, -size.z * 0.5 - 0.035)
			_look.add_child(_hinge)
			var door := _mesh_node(key + "|door", _build_shed_door)
			door.position = Vector3(0.42, 0.0, 0.0)
			_hinge.add_child(door)
		"bin":
			_look = Node3D.new()
			_look.name = "Look"
			add_child(_look)
			_look.add_child(_mesh_node(key + "|tub", _build_bin_tub))
			_hinge = Node3D.new()
			_hinge.name = "Lid"
			# Hinged along the back top edge (+Z), so it flips up and back.
			_hinge.position = Vector3(0.0, size.y * 0.94, size.z * 0.5 + 0.02)
			_look.add_child(_hinge)
			var lid := _mesh_node(key + "|lid", _build_bin_lid)
			lid.position = Vector3(0.0, 0.0, -size.z * 0.5 - 0.02)
			_hinge.add_child(lid)
		_:
			_look = _mesh_node(key + "|hedge", _build_hedge)
			_look.name = "Look"
			add_child(_look)


## One cached mesh per kind, color and size (every lot reuses them).
func _mesh_node(key: String, builder: Callable) -> MeshInstance3D:
	if not _mesh_cache.has(key):
		var kit := _MeshKit.new()
		builder.call(kit)
		_mesh_cache[key] = kit.commit()
	var options := {"roughness": 0.85, "specular": 0.15, "snow": 1.0}
	if spot_kind == "hedge":
		options = {"roughness": 0.9, "specular": 0.1, "snow": 1.0, "wind": 0.04, "translucency": 0.3, "double_sided": true}
	return _Stylized.instance(_mesh_cache[key], options)


## The shed without its door: plank walls (boards painted on as seams), a gable
## roof with overhangs, a window on the right side, a dark doorway behind the door.
func _build_shed_shell(kit: RefCounted) -> void:
	var half := size * 0.5
	var wall_h := size.y * 0.72
	var rise := size.y - wall_h
	var plank := color
	var seam := color.darkened(0.28)
	# Four walls, each a slab, leaving the doorway in the front.
	kit.call("box", Vector3(0.0, wall_h * 0.5, half.z - 0.04), Vector3(size.x, wall_h, 0.08), plank)
	for side: float in [-1.0, 1.0]:
		kit.call("box", Vector3(side * (half.x - 0.04), wall_h * 0.5, 0.0), Vector3(0.08, wall_h, size.z - 0.16), plank)
		# The front wall either side of the doorway.
		var jamb := (half.x - 0.46) * 0.5
		kit.call("box", Vector3(side * (0.46 + jamb), wall_h * 0.5, -half.z + 0.04), Vector3(jamb * 2.0, wall_h, 0.08), plank)
	kit.call("box", Vector3(0.0, wall_h - 0.12, -half.z + 0.04), Vector3(0.92, 0.24, 0.08), plank)
	# A dark interior behind the doorway, so an open door shows shadow, not sky.
	kit.call("box", Vector3(0.0, wall_h * 0.42, -half.z + 0.2), Vector3(0.9, wall_h * 0.84, 0.02), Color(0.08, 0.07, 0.06))
	# Board seams: thin dark strips on the outside faces.
	var boards := int(size.x / 0.3)
	for index: int in boards:
		var x := -half.x + (float(index) + 0.5) * size.x / float(boards)
		if absf(x) > 0.5:
			kit.call("box", Vector3(x, wall_h * 0.5, -half.z - 0.002), Vector3(0.025, wall_h * 0.96, 0.01), seam)
		kit.call("box", Vector3(x, wall_h * 0.5, half.z + 0.002), Vector3(0.025, wall_h * 0.96, 0.01), seam)
	var deep := int(size.z / 0.3)
	for index: int in deep:
		var z := -half.z + (float(index) + 0.5) * size.z / float(deep)
		for side: float in [-1.0, 1.0]:
			kit.call("box", Vector3(side * (half.x + 0.002), wall_h * 0.5, z), Vector3(0.01, wall_h * 0.96, 0.025), seam)
	# Corner posts and a skirt board.
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			kit.call("box", Vector3(x * (half.x - 0.02), wall_h * 0.5, z * (half.z - 0.02)), Vector3(0.1, wall_h, 0.1), color.darkened(0.15))
	# The roof: two slabs meeting at the ridge, overhanging all round, and the gable triangles.
	var roof_color := Color(0.33, 0.27, 0.25)
	var slope := atan2(rise, half.x)
	var panel := Vector2(half.x + 0.22, rise).length()
	for side: float in [-1.0, 1.0]:
		var basis := Basis(Vector3.BACK, -side * slope)
		kit.call("box", Vector3(side * (half.x * 0.5 + 0.05), wall_h + rise * 0.5 + 0.04, 0.0), Vector3(panel, 0.08, size.z + 0.4), roof_color, basis)
	for z: float in [-1.0, 1.0]:
		var face := Vector3(0.0, 0.0, z)
		var a := Vector3(-half.x, wall_h, z * (half.z - 0.01))
		var b := Vector3(half.x, wall_h, z * (half.z - 0.01))
		var c := Vector3(0.0, size.y - 0.04, z * (half.z - 0.01))
		if z < 0.0:
			kit.call("triangle", a, c, b, face, plank)
		else:
			kit.call("triangle", a, b, c, face, plank)
	# A small window on the right wall.
	kit.call("box", Vector3(half.x + 0.02, wall_h * 0.62, 0.1), Vector3(0.04, 0.42, 0.56), Color(0.24, 0.3, 0.36))
	kit.call("box", Vector3(half.x + 0.03, wall_h * 0.62, 0.1), Vector3(0.04, 0.05, 0.62), color.darkened(0.2))
	kit.call("box", Vector3(half.x + 0.03, wall_h * 0.62, 0.1), Vector3(0.04, 0.48, 0.05), color.darkened(0.2))


## The shed door, drawn from its hinge side: boards, a Z brace, a handle, and
## three knot holes at eye height (what a hider looks through).
func _build_shed_door(kit: RefCounted) -> void:
	var wall_h := size.y * 0.72
	var door_h := wall_h - 0.26
	var plank := color.darkened(0.12)
	kit.call("box", Vector3(0.0, door_h * 0.5, 0.0), Vector3(0.84, door_h, 0.05), plank)
	for x: float in [-0.28, 0.0, 0.28]:
		kit.call("box", Vector3(x + 0.14, door_h * 0.5, -0.027), Vector3(0.02, door_h * 0.98, 0.01), plank.darkened(0.25))
	for y: float in [0.25, door_h - 0.25]:
		kit.call("box", Vector3(0.0, y, -0.035), Vector3(0.8, 0.1, 0.02), plank.lightened(0.05))
	var brace_len := Vector2(0.7, door_h - 0.5).length()
	kit.call("box", Vector3(0.0, door_h * 0.5, -0.04), Vector3(0.08, brace_len, 0.02), plank.lightened(0.05), Basis(Vector3.BACK, atan2(0.7, door_h - 0.5)))
	kit.call("box", Vector3(0.3, door_h * 0.48, -0.06), Vector3(0.04, 0.12, 0.04), STEEL)
	for index: int in 3:
		kit.call("box", Vector3(-0.25 + 0.25 * float(index), 1.5, -0.028), Vector3(0.035, 0.03, 0.012), Color(0.05, 0.04, 0.03))


## The wheelie bin's tub: a slightly tapered box, a rim, molded pockets, the
## handle bar at the back and two wheels.
func _build_bin_tub(kit: RefCounted) -> void:
	var half := size * 0.5
	var body := color
	var top := size.y * 0.93
	kit.call("rbox", Vector3(0.0, top * 0.5 + 0.08, 0.0), Vector3(half.x * 0.96, top * 0.5 - 0.06, half.z * 0.94), body, 7.0, {"detail": 2})
	kit.call("box", Vector3(0.0, top, 0.0), Vector3(size.x, 0.06, size.z), body.darkened(0.15))
	for side: float in [-1.0, 1.0]:
		kit.call("box", Vector3(side * (half.x * 0.96 + 0.01), top * 0.55, 0.0), Vector3(0.02, top * 0.45, size.z * 0.62), body.darkened(0.12))
	kit.call("box", Vector3(0.0, top * 0.55, -half.z * 0.94 - 0.01), Vector3(size.x * 0.7, top * 0.45, 0.02), body.darkened(0.12))
	# The handle bar and its brackets.
	kit.call("tube", PackedVector3Array([Vector3(-half.x * 0.8, top - 0.05, half.z + 0.1), Vector3(half.x * 0.8, top - 0.05, half.z + 0.1)]), PackedFloat32Array([0.035, 0.035]), body.darkened(0.3), 6, {"jitter": 0.0, "cap_start": true})
	for side: float in [-1.0, 1.0]:
		kit.call("box", Vector3(side * half.x * 0.8, top - 0.1, half.z + 0.04), Vector3(0.05, 0.12, 0.14), body.darkened(0.3))
		# Wheels at the back corners, on an axle.
		kit.call("tube", PackedVector3Array([Vector3(side * (half.x - 0.05), 0.12, half.z * 0.8), Vector3(side * (half.x + 0.05), 0.12, half.z * 0.8)]), PackedFloat32Array([0.12, 0.12]), Color(0.12, 0.12, 0.13), 10, {"jitter": 0.0, "cap_start": true})
	kit.call("tube", PackedVector3Array([Vector3(-half.x, 0.12, half.z * 0.8), Vector3(half.x, 0.12, half.z * 0.8)]), PackedFloat32Array([0.025, 0.025]), STEEL, 6, {"jitter": 0.0})
	# A dark inside, seen when the lid's up.
	kit.call("box", Vector3(0.0, top - 0.03, 0.0), Vector3(size.x * 0.9, 0.02, size.z * 0.86), Color(0.06, 0.06, 0.07))


## The lid, from its back hinge: a flat slab with a lip at the front and a grip.
func _build_bin_lid(kit: RefCounted) -> void:
	var lid := color.darkened(0.06)
	kit.call("rbox", Vector3(0.0, 0.03, 0.0), Vector3(size.x * 0.52, 0.04, size.z * 0.52 + 0.02), lid, 6.0, {"detail": 1})
	kit.call("box", Vector3(0.0, -0.02, -size.z * 0.52 - 0.02), Vector3(size.x * 0.96, 0.08, 0.04), lid.darkened(0.15))
	kit.call("box", Vector3(0.0, -0.02, -size.z * 0.52 - 0.06), Vector3(0.3, 0.04, 0.05), lid.darkened(0.3))


## A clipped hedge: a few faceted lumps along its length, lit on top, and loose
## leaf cards over the surface so the silhouette reads soft and can shiver.
func _build_hedge(kit: RefCounted) -> void:
	var half := size * 0.5
	# A clipped hedge is a soft box: a rounded core a hair inside the collider,
	# a couple of low lumps along the top where the clippers missed...
	var core := Vector3(half.x * 0.96, half.y * 0.97, half.z * 0.94)
	kit.call("rbox", Vector3(0.0, core.y, 0.0), core, color, 3.2, {"detail": 2, "sway": 0.08})
	var long_x := size.x >= size.z
	var length := size.x if long_x else size.z
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for index: int in 3:
		var t := (float(index) + 0.5) / 3.0 - 0.5 + rng.randf_range(-0.08, 0.08)
		var top := Vector3(t * length * 0.8, size.y * 0.9, 0.0) if long_x else Vector3(0.0, size.y * 0.9, t * length * 0.8)
		var lump := Vector3(length * 0.2, half.y * 0.22, minf(half.x, half.z) * 0.8)
		if not long_x:
			lump = Vector3(lump.z, lump.y, lump.x)
		kit.call("blob", top, lump, color.lightened(0.06), {"detail": 1, "lumps": 0.25, "lump_scale": 3.0, "flat": false, "jitter": 0.04, "seed": index, "sway": 0.2})
	# ...and a coat of leaves on every face, tipped a little every which way, so
	# the edge reads leafy and the hedge can shiver.
	var faces: Array = [
		[Vector3.UP, Vector3(half.x, 0.0, half.z), size.y],
		[Vector3.FORWARD, Vector3(half.x, half.y, 0.0), half.z],
		[Vector3.BACK, Vector3(half.x, half.y, 0.0), half.z],
		[Vector3.LEFT, Vector3(0.0, half.y, half.z), half.x],
		[Vector3.RIGHT, Vector3(0.0, half.y, half.z), half.x],
	]
	var areas: Array[float] = []
	var total := 0.0
	for face: Array in faces:
		var extent: Vector3 = face[1]
		var area := (extent.x if extent.x > 0.0 else 1.0) * (extent.y if extent.y > 0.0 else 1.0) * (extent.z if extent.z > 0.0 else 1.0)
		areas.append(area)
		total += area
	for index: int in 110:
		var pick := rng.randf() * total
		var which := 0
		while which < faces.size() - 1 and pick > areas[which]:
			pick -= areas[which]
			which += 1
		var normal: Vector3 = faces[which][0]
		var extent: Vector3 = faces[which][1]
		var out: float = faces[which][2]
		var at := Vector3(rng.randf_range(-1.0, 1.0) * extent.x * 0.92, half.y + rng.randf_range(-1.0, 1.0) * extent.y * 0.88, rng.randf_range(-1.0, 1.0) * extent.z * 0.92)
		if normal == Vector3.UP:
			at.y = out - 0.01 + rng.randf_range(0.0, 0.05)
		else:
			at += normal * (out - 0.02 + rng.randf_range(0.0, 0.04))
		var tipped := (normal + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.3, 0.6), rng.randf_range(-0.6, 0.6))).normalized()
		var leaf := HEDGE_LEAF_COLORS[rng.randi() % HEDGE_LEAF_COLORS.size()].lerp(color, 0.35).lightened(rng.randf_range(-0.08, 0.1))
		kit.call("leaf_card", at, tipped, rng.randf_range(0.08, 0.12), leaf, 0.7, rng.randf() * TAU)
	kit.call("grade", 0, 0.0, size.y, 0.6, 1.12)


## Two small cold glints in the dark (the hider's eyes), shown while someone peeks.
func _make_glint() -> Node3D:
	var root := Node3D.new()
	root.name = "EyeGlint"
	root.visible = false
	add_child(root)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.98, 0.9)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.035, 0.03)
		eye.mesh = quad
		eye.material_override = material
		eye.position = Vector3(side * 0.06, 0.0, 0.0)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(eye)
	return root


# ---------------------------------------------------------------- moments

## Plays a moment from server time at (every peer; cosmetic). args: side, slot,
## on (peek), crew (inspect).
func set_state(state: StringName, at: float, args: Dictionary = {}) -> void:
	var late := maxf(0.0, Net.server_time() - at)
	var stale := late > Constants.BEAT_SKIP
	match state:
		&"enter":
			if stale:
				_hinge_to(0.0, true)
				return
			_enter_or_exit(int(args.get("side", 0)), late, true)
		&"exit":
			if stale:
				_hinge_to(0.0, true)
				return
			_enter_or_exit(int(args.get("side", 0)), late, false)
		&"peek":
			_show_peek(bool(args.get("on", false)), int(args.get("side", 0)), int(args.get("slot", 0)))
		&"tremble":
			_tremble(not stale)
		&"inspect":
			_poke(args.get("crew") as Node3D, late)
		&"near_miss":
			_poking = 0.0
			_hinge_to(0.0)
			if not stale:
				_sound("notice_slap", inspect_point() + Vector3(0.0, size.y * 0.6, 0.0))
		&"found":
			_poking = 0.0
			match spot_kind:
				"shed":
					_hinge_to(DOOR_OPEN, false, 9.0)
					_later(0.9, func() -> void: _hinge_to(0.0))
				"bin":
					_hinge_to(LID_OPEN, false, 10.0)
					_later(0.9, func() -> void: _hinge_to(0.0))
				_:
					_wobble = 1.6
					_burst(top_point(), 14, HEDGE_LEAF_COLORS, 3.2)
			if not stale:
				_sound(_open_sound(), top_point())


## The dive in or the burst out: the door or lid opens and shuts around it, the
## hedge squashes and puffs leaves, each with its sound on the moment of contact.
func _enter_or_exit(side: int, late: float, entering: bool) -> void:
	var contact := maxf(0.0, (Constants.HIDE_ENTER_SECONDS * 0.6 if entering else Constants.HIDE_EXIT_SECONDS * 0.3) - late)
	var where := entry_point(side).lerp(top_point(), 0.5)
	match spot_kind:
		"shed":
			_hinge_to(DOOR_OPEN, false, 8.0)
			_sound("shed_door", where)
			_later(contact + 0.45, func() -> void: _hinge_to(0.0, false, 5.0))
		"bin":
			_hinge_to(LID_OPEN, false, 12.0)
			_sound("bin_lid", where)
			_later(contact + 0.25, func() -> void:
				_hinge_to(0.0, false, 14.0)
				_later(0.12, func() -> void: _sound("bin_clang", top_point())))
		_:
			_later(contact, func() -> void:
				_wobble = 1.0
				_wobble_time = 0.0
				_burst(entry_point(side).lerp(top_point(), 0.7), 10, HEDGE_LEAF_COLORS, 2.0)
				_sound("hedge_rustle", where))


func _show_peek(on: bool, side: int, slot: int) -> void:
	match spot_kind:
		"shed":
			_hinge_to(DOOR_PEEK if on else 0.0, false, 3.0)
		"bin":
			_hinge_to(LID_PEEK if on else 0.0, false, 4.0)
	_glint.visible = on and spot_kind != "bin"
	if on:
		var eye := peek_transform(side, slot)
		_glint.global_position = eye.origin - eye.basis.z * 0.03
		_sound("bin_lid" if spot_kind == "bin" else "peek_rustle", eye.origin, -6.0)


## A hider turned too fast: the hedge shivers, and maybe a leaf comes loose.
func _tremble(audible: bool) -> void:
	if spot_kind != "hedge":
		return
	_wobble = maxf(_wobble, Constants.HIDE_TREMBLE_AMOUNT / 0.08)
	_wobble_time = 0.0
	if _rng.randf() < 0.5:
		_drop_leaf()
	if audible:
		_sound("hedge_rustle", top_point(), -8.0)


## A NICE BOY pokes: parts the hedge, lifts the lid a crack (his face in the
## slit), knocks on the shed. Sounds on each poke.
func _poke(crew: Node3D, late: float) -> void:
	_poking = maxf(0.0, Constants.HIDE_INSPECT_SECONDS - late)
	_poke_kind = StringName(spot_kind)
	match spot_kind:
		"bin":
			_later(0.3, func() -> void:
				if _poking > 0.0:
					_hinge_to(LID_POKE, false, 5.0)
					_sound("bin_lid", top_point(), -4.0))
		"shed":
			for knock: int in 3:
				_later(0.25 + 0.3 * float(knock), func() -> void:
					if _poking > 0.0:
						_wobble = 0.5
						_sound("hide_bonk", inspect_point() + Vector3(0.0, 1.2, 0.0), -6.0))
		_:
			for push: int in 2:
				_later(0.2 + 0.7 * float(push), func() -> void:
					if _poking > 0.0:
						_wobble = 1.2
						_wobble_time = 0.0
						_burst(inspect_point().lerp(top_point(), 0.6), 5, HEDGE_LEAF_COLORS, 1.4)
						_sound("hedge_rustle", top_point(), -2.0))
	crew_gesture(crew, {"bin": "lid_peer", "shed": "shed_knock"}.get(spot_kind, "inspect_poke") as String, "scribble")


## Plays a NICE BOY gesture by name (player/hide_gestures.gd registers them),
## or the fallback when this build has no such gesture.
static func crew_gesture(crew: Node3D, wanted: String, fallback: String) -> void:
	if crew == null:
		return
	var body := crew.get_node_or_null("Visual/CartoonBody")
	if body == null:
		return
	body.call("gesture", wanted if preload("res://player/cartoon_body.gd").has_gesture(wanted) else fallback)


func _open_sound() -> String:
	return {"shed": "shed_door", "bin": "bin_lid"}.get(spot_kind, "hedge_rustle")


func _on_entered(peer_id: int, side: int, at: float) -> void:
	_entered_ms[peer_id] = Time.get_ticks_msec()
	if int(_predicted.get(peer_id, 0)) > Time.get_ticks_msec():
		return
	set_state(&"enter", at, {"side": side})


func _on_exited(peer_id: int, side: int, at: float) -> void:
	_peek_shown.erase(peer_id)
	_glint.visible = false
	if side >= 0:
		set_state(&"exit", at, {"side": side})


## The owner plays its own dive at once; the host's confirmation then skips it.
func predict_enter(peer_id: int, side: int) -> void:
	_predicted[peer_id] = Time.get_ticks_msec() + int(Constants.HIDE_CONFIRM_TIMEOUT * 1000.0)
	_entered_ms[peer_id] = Time.get_ticks_msec()
	set_state(&"enter", Net.server_time(), {"side": side})


func _on_inspect(crew: Node3D, phase: StringName, at: float) -> void:
	match phase:
		&"begin":
			set_state(&"inspect", at, {"crew": crew})
		&"found":
			set_state(&"found", at, {"crew": crew})
		_:
			set_state(&"near_miss", at, {"crew": crew})


## Stickers: one more slapped on, popping into place; a late joiner just sees them.
func _on_notices(before: int, count: int) -> void:
	for child: Node in _notices_node.get_children():
		child.queue_free()
	for index: int in count:
		var sticker := _sticker(index)
		_notices_node.add_child(sticker)
		if index >= before and before >= 0 and is_inside_tree():
			sticker.scale = Vector3.ONE * 1.6
			var tween := create_tween()
			tween.tween_property(sticker, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A Courtesy Notice: a paper slip with the Daisy Seal and a few lines of
## print, stuck on the front at a slight angle, stacked one over another.
func _sticker(index: int) -> Node3D:
	var key := "notice"
	if not _mesh_cache.has(key):
		var kit := _MeshKit.new()
		kit.box(Vector3.ZERO, Vector3(0.2, 0.26, 0.004), PAPER)
		_NiceSeal.add(kit, Vector3(0.0, 0.05, -0.003), 0.055, Vector3.FORWARD)
		for line: int in 4:
			kit.box(Vector3(0.0, -0.04 - 0.03 * float(line), -0.0025), Vector3(0.14 - 0.02 * float(line % 2), 0.008, 0.002), Color(0.3, 0.28, 0.4))
		_mesh_cache[key] = kit.commit()
	var node := _Stylized.instance(_mesh_cache[key], {"roughness": 0.7})
	node.name = "Notice%d" % index
	var front := SIDES[0]
	var half := size * 0.5
	var y := clampf(size.y * 0.55 + 0.12 * float(index % 3), 0.3, size.y - 0.2)
	var x := -0.35 + 0.28 * float(index % 3) + 0.06 * floorf(float(index) / 3.0)
	var face_z := -half.z - (0.06 if spot_kind == "hedge" else 0.04)
	if spot_kind == "shed":
		x += 0.75
	node.position = Vector3(x, y, face_z) + front * 0.0
	node.rotation.z = (float(index % 5) - 2.0) * 0.12
	return node


# ---------------------------------------------------------------- every frame

func _process(delta: float) -> void:
	if _hinge != null:
		_hinge_angle = move_toward(_hinge_angle, _hinge_target, delta * _hinge_speed)
		if spot_kind == "shed":
			_hinge.rotation.y = _hinge_angle
		else:
			_hinge.rotation.x = -_hinge_angle
	if _wobble > 0.0 and _look != null:
		_wobble_time += delta
		_wobble = maxf(0.0, _wobble - delta * 2.2)
		var shake := sin(_wobble_time * 26.0) * 0.08 * _wobble
		_look.scale = Vector3(1.0 + shake * 0.6, 1.0 - shake, 1.0 + shake * 0.6)
		_look.rotation.z = sin(_wobble_time * 19.0) * 0.02 * _wobble
		if _wobble <= 0.0:
			_look.scale = Vector3.ONE
			_look.rotation.z = 0.0
	if _poking > 0.0:
		_poking = maxf(0.0, _poking - delta)
		if _poking <= 0.0 and spot_kind == "bin":
			_hinge_to(0.0)
	_watch_occupants(delta)


## Tells from what every peer already has: an occupant turning fast shakes the
## hedge, peeking shows the glint or the lifted lid, and an occupied hedge drops
## a leaf now and then.
func _watch_occupants(delta: float) -> void:
	var inside := occupants()
	if inside.is_empty():
		return
	if spot_kind == "hedge":
		_next_leaf -= delta
		if _next_leaf <= 0.0:
			_next_leaf = _rng.randf_range(Constants.HIDE_LEAF_DROP_EVERY.x, Constants.HIDE_LEAF_DROP_EVERY.y)
			_drop_leaf()
	for peer_id: int in inside:
		var body := _player(peer_id)
		if body == null:
			continue
		var yaw := float(body.get("body_yaw"))
		# Settling in after the dive turns the body round once: that's no tell.
		if Time.get_ticks_msec() - int(_entered_ms.get(peer_id, 0)) < 1200:
			_yaw_seen[peer_id] = yaw
			continue
		if _yaw_seen.has(peer_id) and delta > 0.0:
			var rate := absf(angle_difference(float(_yaw_seen[peer_id]), yaw)) / delta
			_tremble_cool[peer_id] = maxf(0.0, float(_tremble_cool.get(peer_id, 0.0)) - delta)
			if rate > Constants.HIDE_TREMBLE_TURN_RATE and float(_tremble_cool[peer_id]) <= 0.0:
				_tremble_cool[peer_id] = Constants.HIDE_TREMBLE_SECONDS
				set_state(&"tremble", Net.server_time())
		_yaw_seen[peer_id] = yaw
		var peeking := bool(body.get("peeking"))
		if bool(_peek_shown.get(peer_id, false)) != peeking:
			_peek_shown[peer_id] = peeking
			set_state(&"peek", Net.server_time(), {"on": peeking, "side": side_of(peer_id), "slot": slot_of(peer_id)})


func _hinge_to(angle: float, instant: bool = false, speed: float = 6.0) -> void:
	_hinge_target = angle
	_hinge_speed = speed
	if instant:
		_hinge_angle = angle


## One leaf works loose from the top and flutters down beside the hedge.
func _drop_leaf() -> void:
	if not is_inside_tree():
		return
	var half := size * 0.5
	var start := global_transform * Vector3(_rng.randf_range(-half.x, half.x) * 0.8, size.y * 0.95, _rng.randf_range(-half.z, half.z) * 0.8)
	var out := side_direction(_rng.randi() % 4) * _rng.randf_range(0.2, 0.6)
	var leaf := _leaf_mesh(HEDGE_LEAF_COLORS[_rng.randi() % HEDGE_LEAF_COLORS.size()], 0.08)
	_tells.add_child(leaf)
	leaf.global_position = start
	var land := Vector3(start.x + out.x, global_position.y + 0.02, start.z + out.z)
	var fall := 1.6 + _rng.randf_range(0.0, 0.8)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(leaf):
			var sway := sin(t * TAU * 1.5) * 0.15 * (1.0 - t)
			leaf.global_position = start.lerp(land, t) + side_direction(1) * sway
			leaf.rotation = Vector3(sin(t * 9.0) * 0.8, t * 6.0, cos(t * 7.0) * 0.6 * (1.0 - t)), 0.0, 1.0, fall)
	tween.chain().tween_interval(6.0)
	tween.chain().tween_property(leaf, "scale", Vector3.ONE * 0.01, 0.6)
	tween.chain().tween_callback(leaf.queue_free)


## A puff of leaves flying out from at and settling (dives, bursts, pokes).
func _burst(at: Vector3, count: int, colors: Array[Color], speed: float) -> void:
	burst(self, at, count, colors, speed, _rng)


## A puff of leaves from at under parent, cosmetic: each flies on its own arc,
## spins, lands and shrinks away. Shared with the pile dive (player/hide_view.gd).
static func burst(parent: Node, at: Vector3, count: int, colors: Array[Color], speed: float, rng: RandomNumberGenerator) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	for index: int in count:
		var leaf := _leaf_mesh(colors[index % colors.size()], rng.randf_range(0.05, 0.09))
		parent.add_child(leaf)
		leaf.global_position = at
		var angle := rng.randf() * TAU
		var velocity := Vector3(cos(angle), rng.randf_range(0.8, 1.6), sin(angle)) * speed * rng.randf_range(0.5, 1.0)
		var life := rng.randf_range(0.7, 1.1)
		var spin := Vector3(rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0))
		var floor_y := at.y - 2.5
		var tween := leaf.create_tween()
		tween.tween_method(func(t: float) -> void:
			if not is_instance_valid(leaf):
				return
			var seconds := t * life
			var drag := 1.0 - 0.45 * t
			var p := at + Vector3(velocity.x * seconds * drag, velocity.y * seconds - 4.5 * seconds * seconds, velocity.z * seconds * drag)
			p.y = maxf(p.y, floor_y)
			leaf.global_position = p
			leaf.rotation = spin * seconds
			leaf.scale = Vector3.ONE * clampf((1.0 - t) * 2.5, 0.01, 1.0), 0.0, 1.0, life)
		tween.tween_callback(leaf.queue_free)


static func _leaf_mesh(leaf_color: Color, leaf_size: float) -> MeshInstance3D:
	var key := "leaf|%s|%.2f" % [leaf_color.to_html(), leaf_size]
	if not _mesh_cache.has(key):
		var kit := _MeshKit.new()
		kit.leaf_card(Vector3.ZERO, Vector3.UP, leaf_size, leaf_color, 0.0)
		_mesh_cache[key] = kit.commit()
	var node := _Stylized.instance(_mesh_cache[key], {"roughness": 0.9, "double_sided": true})
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _sound(id: String, at: Vector3, db: float = 0.0) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx") if is_inside_tree() else null
	if sfx != null:
		sfx.call("play_at", id, at, db)


func _later(seconds: float, what: Callable) -> void:
	if not is_inside_tree():
		return
	if seconds <= 0.0:
		what.call()
		return
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(self) and is_inside_tree():
			what.call())
