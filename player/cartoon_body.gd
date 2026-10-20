extends Node3D

## Authority: local, cosmetic. A goofy low-poly cartoon person (docs/FEEL.md,
## "Look"): a big round head with big blinking eyes, a small body, and bouncy
## procedural motion. Used for players, the crew, and the store clerk.
##
## Put it under the node that moves on screen (a player's smoothed Visual), with
## its origin at the feet, facing -Z. Motion comes from how fast that node really
## moves, so it animates the same for local players, remote players, and NPCs.
## If the parent body has an anim_state like player.gd's, jumping and crouching
## show too. Call talk() to flap the mouth while a sound plays.

## Matches player.gd's AnimState: IDLE, WALK, SPRINT, CROUCH, AIR.
const STATE_CROUCH: int = 3
const STATE_AIR: int = 4
const SKIN_TONES: Array[Color] = [
	Color(0.98, 0.82, 0.68), Color(0.87, 0.67, 0.5), Color(0.72, 0.52, 0.36),
	Color(0.55, 0.37, 0.25), Color(0.4, 0.27, 0.18),
]
const SHIRTS: Array[Color] = [
	Color(0.92, 0.35, 0.2), Color(0.25, 0.55, 0.85), Color(0.95, 0.75, 0.2),
	Color(0.35, 0.7, 0.35), Color(0.65, 0.35, 0.75), Color(0.95, 0.5, 0.6),
	Color(0.2, 0.7, 0.7), Color(0.85, 0.85, 0.82),
]
const PANTS: Array[Color] = [Color(0.25, 0.3, 0.45), Color(0.35, 0.3, 0.25), Color(0.2, 0.2, 0.22), Color(0.45, 0.42, 0.35)]
const HAIR: Array[Color] = [Color(0.15, 0.1, 0.07), Color(0.45, 0.28, 0.12), Color(0.85, 0.7, 0.35), Color(0.6, 0.2, 0.1), Color(0.3, 0.3, 0.32)]
const EYE_WHITE := Color(0.97, 0.97, 0.95)
const PUPIL := Color(0.06, 0.05, 0.06)
## Stride length in radians of swing per meter walked.
const STRIDE: float = 2.4
## Render layer the head is drawn on, so a player's own first-person camera can skip it.
const HEAD_LAYER: int = 2

@export var skin := SKIN_TONES[0]
@export var shirt := SHIRTS[0]
@export var pants := PANTS[0]
@export var hair := HAIR[0]
## "cap", "hair", or "none".
@export var hat_style := "hair"
@export var hat_color := Color(0.2, 0.2, 0.22)
## Dark glasses over the eyes, for the crew's placeholder look.
@export var shades := false

var _head_root: Node3D
var _face: Node3D
var _torso: Node3D
var _hips: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _eyes: Array[Node3D] = []
var _mouth: Node3D
var _brows: Array[Node3D] = []
var _phase: float = 0.0
var _last_position := Vector3.INF
var _speed: float = 0.0
var _blink_in: float = 2.0
var _blink_left: float = 0.0
var _talk_left: float = 0.0
var _squash: float = 0.0
var _was_air: bool = false
var _time: float = 0.0
var _head_base_y: float = 1.6
## How far the hips and head drop when crouching, in meters.
const CROUCH_DROP: float = 0.3
## Share of a player's look up and down that the visible head shows.
const HEAD_TILT_SHARE: float = 0.35


## Pick colors from a seed so each character looks different but stays the same every session.
func dress_from_seed(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	skin = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	shirt = SHIRTS[rng.randi() % SHIRTS.size()]
	pants = PANTS[rng.randi() % PANTS.size()]
	hair = HAIR[rng.randi() % HAIR.size()]
	hat_style = "cap" if rng.randf() < 0.35 else "hair"
	hat_color = SHIRTS[rng.randi() % SHIRTS.size()].darkened(0.2)


## Build the body. head_parent is where the head goes (a player's Head node, so
## looking up and down nods it), or null to give the body its own head.
func build(head_parent: Node3D = null) -> void:
	_hips = _pivot(self, Vector3(0.0, 0.82, 0.0))
	_torso = _pivot(_hips, Vector3.ZERO)
	_part(_torso, _capsule(0.21, 0.62), Vector3(0.0, 0.26, 0.0), shirt).scale = Vector3(1.0, 1.0, 0.8)
	_part(_torso, _capsule(0.2, 0.3), Vector3(0.0, -0.02, 0.0), pants).scale = Vector3(1.0, 1.0, 0.8)
	for side: float in [-1.0, 1.0]:
		var leg := _pivot(_hips, Vector3(side * 0.1, 0.0, 0.0))
		_part(leg, _capsule(0.085, 0.7), Vector3(0.0, -0.4, 0.0), pants)
		_part(leg, _box(Vector3(0.15, 0.09, 0.27)), Vector3(0.0, -0.78, -0.05), Color(0.15, 0.13, 0.12))
		_legs.append(leg)
		var arm := _pivot(_torso, Vector3(side * 0.27, 0.47, 0.0))
		arm.rotation.z = side * 0.12
		_part(arm, _capsule(0.06, 0.5), Vector3(0.0, -0.24, 0.0), shirt)
		_part(arm, _sphere(0.075), Vector3(0.0, -0.5, 0.0), skin)
		_arms.append(arm)
	_head_root = head_parent if head_parent != null else _pivot(self, Vector3(0.0, 1.6, 0.0))
	_head_base_y = _head_root.position.y
	_build_head(_head_root)


## Flap the mouth for this long, and raise the brows a little.
func talk(seconds: float) -> void:
	_talk_left = maxf(_talk_left, seconds)


func _build_head(root: Node3D) -> void:
	var face := Node3D.new()
	face.name = "CartoonHead"
	root.add_child(face)
	_face = face
	_on_head_layer(_part(face, _sphere(0.27), Vector3(0.0, 0.02, 0.0), skin))
	for side: float in [-1.0, 1.0]:
		var eye := _pivot(face, Vector3(side * 0.095, 0.06, -0.21))
		var white := _part(eye, _sphere(0.075), Vector3.ZERO, EYE_WHITE)
		white.scale = Vector3(1.0, 1.15, 0.6)
		_on_head_layer(white)
		_on_head_layer(_part(eye, _sphere(0.036), Vector3(side * -0.008, -0.005, -0.04), PUPIL))
		_eyes.append(eye)
		var brow := _pivot(face, Vector3(side * 0.1, 0.16, -0.235))
		_on_head_layer(_part(brow, _box(Vector3(0.09, 0.022, 0.02)), Vector3.ZERO, hair.darkened(0.3)))
		brow.rotation.z = side * -0.12
		_brows.append(brow)
		_on_head_layer(_part(face, _sphere(0.055), Vector3(side * 0.265, 0.0, 0.0), skin.darkened(0.06)))
	_on_head_layer(_part(face, _sphere(0.045), Vector3(0.0, -0.02, -0.27), skin.darkened(0.1)))
	_mouth = _pivot(face, Vector3(0.0, -0.11, -0.235))
	_on_head_layer(_part(_mouth, _box(Vector3(0.1, 0.025, 0.02)), Vector3.ZERO, Color(0.35, 0.1, 0.1)))
	if shades:
		_on_head_layer(_part(face, _box(Vector3(0.3, 0.07, 0.03)), Vector3(0.0, 0.06, -0.255), PUPIL))
	match hat_style:
		"cap":
			var crown := _part(face, _sphere(0.28), Vector3(0.0, 0.1, 0.0), hat_color)
			crown.scale = Vector3(1.0, 0.62, 1.0)
			_on_head_layer(crown)
			_on_head_layer(_part(face, _box(Vector3(0.3, 0.025, 0.2)), Vector3(0.0, 0.14, -0.3), hat_color))
		"hair":
			var mop := _part(face, _sphere(0.285), Vector3(0.0, 0.11, 0.03), hair)
			mop.scale = Vector3(1.02, 0.6, 1.0)
			_on_head_layer(mop)


func _process(delta: float) -> void:
	if _hips == null:
		return
	_time += delta
	var now := global_position
	if _last_position != Vector3.INF and delta > 0.0:
		var moved := Vector2(now.x - _last_position.x, now.z - _last_position.z).length()
		# Teleports and rides would read as sprinting at hundreds of m/s. Ignore those.
		if moved / delta < 20.0:
			_speed = lerpf(_speed, moved / delta, clampf(delta * 10.0, 0.0, 1.0))
			_phase += moved * STRIDE
	_last_position = now
	var state := int(get_parent().get_parent().get("anim_state")) if get_parent() != null and get_parent().get_parent() != null and "anim_state" in get_parent().get_parent() else 0
	var in_air := state == STATE_AIR
	var crouching := state == STATE_CROUCH
	if _was_air and not in_air:
		_squash = 1.0
	_was_air = in_air
	_squash = maxf(0.0, _squash - delta * 5.0)
	var walk := clampf(_speed / 5.0, 0.0, 1.4)
	var swing := sin(_phase) * 0.65 * walk
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	_arms[0].rotation.x = -swing * 0.9
	_arms[1].rotation.x = swing * 0.9
	var bounce := absf(sin(_phase)) * 0.06 * walk
	var breathe := sin(_time * 2.2) * 0.012 * (1.0 - walk)
	var drop := CROUCH_DROP if crouching else 0.0
	_hips.position.y = 0.82 + bounce - drop - _squash * 0.08
	# The head rides with the body, and a player's camera with it.
	_head_root.position.y = lerpf(_head_root.position.y, _head_base_y - drop + bounce * 0.6 - _squash * 0.06, clampf(delta * 12.0, 0.0, 1.0))
	_torso.rotation.x = -0.12 * walk
	_torso.scale = Vector3(1.0 + _squash * 0.15, 1.0 + breathe - _squash * 0.12, 1.0 + _squash * 0.15)
	for index: int in _legs.size():
		if crouching:
			_legs[index].rotation.x = -0.9
		if in_air:
			_legs[index].rotation.x = 0.5 if index == 0 else -0.25
	for index: int in _arms.size():
		var side := -1.0 if index == 0 else 1.0
		# Flailing up when airborne, the way cartoon people jump.
		_arms[index].rotation.z = side * (2.4 if in_air else 0.12 + 0.05 * sin(_time * 1.7 + index))
	# A player's Head node tilts fully with where they look, for the camera. A real
	# head tips much less, so the visible head only follows part of it.
	_face.rotation.x = -_head_root.rotation.x * (1.0 - HEAD_TILT_SHARE)
	_animate_face(delta)


func _animate_face(delta: float) -> void:
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_left = 0.12
		_blink_in = randf_range(1.8, 4.5)
	_blink_left = maxf(0.0, _blink_left - delta)
	for eye: Node3D in _eyes:
		eye.scale.y = 0.12 if _blink_left > 0.0 else 1.0
	_talk_left = maxf(0.0, _talk_left - delta)
	var open := 0.0
	if _talk_left > 0.0:
		open = absf(sin(_time * 24.0))
	_mouth.scale = Vector3(1.0 - open * 0.3, 1.0 + open * 3.5, 1.0)
	for index: int in _brows.size():
		_brows[index].position.y = 0.16 + (0.03 if _talk_left > 0.0 else 0.0)


func _on_head_layer(node: Node3D) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null:
		mesh.layers = 1 << (HEAD_LAYER - 1)


func _pivot(parent: Node3D, at: Vector3) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	node.position = at
	return node


func _part(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = material
	parent.add_child(view)
	view.position = at
	return view


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 10
	mesh.rings = 4
	return mesh


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 8
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh
