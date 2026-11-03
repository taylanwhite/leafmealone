extends Node3D

## Authority: local presentation. The bits that fly at each rake bite: leaf
## fragments, a puff of dust, a few blades of grass on bare lawn, and shreds out
## of a mower deck. A small pool of CPUParticles3D built once (one material each)
## and reused round-robin; replaces the old per-stroke bursts that spawned new
## meshes every stroke and appeared at the parent's origin for a frame under
## physics interpolation. Lives under LeafMotion (leaves/leaf_motion.gd).

const BITS: int = 0
const DUST: int = 1
const GRASS: int = 2
const SHREDS: int = 3
## The pool: [type, particles] (Constants.LEAF_CHAFF_EMITTERS of them). Each keeps
## its particle count for life: changing CPUParticles3D.amount reallocates its
## instances, and under physics interpolation the fresh ones flash black at the
## world origin for a frame. A light and a heavy bits emitter cover 12-40 bits.
const POOL: Array = [[BITS, 14], [BITS, 36], [DUST, 8], [DUST, 8], [GRASS, 5], [SHREDS, 24]]
const LEAF_TONES: Array[Color] = [
	Color(0.96, 0.66, 0.20), Color(0.82, 0.30, 0.10), Color(0.96, 0.82, 0.30), Color(0.62, 0.36, 0.16),
]

var _emitters: Array[CPUParticles3D] = []
var _types := PackedInt32Array()
var _amounts := PackedInt32Array()
var _next: Dictionary = {}
var bursts: int = 0


## Builds the pool and fires each emitter once at warm_at (under the yard), so the
## first real bite has no shader-compile hitch.
func build(warm_at: Vector3) -> void:
	var count := mini(Constants.LEAF_CHAFF_EMITTERS, POOL.size())
	for index: int in count:
		var type := int(POOL[index][0])
		var emitter := _make(type)
		emitter.amount = int(POOL[index][1])
		emitter.name = "Chaff%d" % index
		add_child(emitter)
		_emitters.append(emitter)
		_types.append(type)
		_amounts.append(emitter.amount)
		emitter.global_transform = Transform3D(Basis(), warm_at)
		emitter.restart()
		emitter.reset_physics_interpolation()


## One stroke event's chaff (contract C1 keys); head is the actor's rake head
## from LeafMotion ({} when none), view the leaf view.
func burst(ev: Dictionary, head: Dictionary, view: Object) -> void:
	var kind := str(ev.get("kind", ""))
	var moved := int(ev.get("moved", 0))
	var at: Vector3 = ev.get("at", Vector3.ZERO)
	var dir: Vector3 = ev.get("dir", Vector3.FORWARD)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var width := clampf(float(ev.get("width", 1.0)) * 0.4, 0.4, 1.4)
	var spot := at - dir * 0.4
	if not head.is_empty():
		spot = head["mid"]
		width = float(head["half"]) * 2.0
	if view != null:
		spot.y = float(view.call("surface_y", Vector2(spot.x, spot.z))) + 0.03
	var load := clampf(float(moved) / Constants.LEAF_CHAFF_FULL_UNITS, 0.0, 1.0)
	var bits := int(lerpf(float(Constants.LEAF_CHAFF_BITS.x), float(Constants.LEAF_CHAFF_BITS.y), load))
	match kind:
		"rake", "crew_rake", "hand", "blower", "plow":
			if moved <= 0:
				_fire(GRASS, spot, dir, width, Constants.LEAF_CHAFF_EMPTY_BITS)
				return
			_fire(BITS, spot, dir, width, bits if kind != "hand" else bits / 3)
			_fire(DUST, spot, dir, width, 4 + int(load * 6.0))
		"mulch":
			_fire(SHREDS, at, dir, 0.6, 24)
		"bag", "crew_bag":
			_fire(DUST, at, dir, 1.2, 6)
			_fire(BITS, at + Vector3(0.0, 0.3, 0.0), dir, 1.0, 12)
		"scatter":
			_fire(BITS, at + Vector3(0.0, 0.4, 0.0), Vector3.UP, 0.8, 36)
			_fire(DUST, at, dir, 1.4, 8)


func _fire(type: int, at: Vector3, dir: Vector3, width: float, amount: int) -> void:
	if amount <= 0:
		return
	var emitter := _take(type, amount)
	if emitter == null:
		return
	bursts += 1
	var right := dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.9 else Vector3.RIGHT
	# Local -Z points along the stroke, local X along the tine line.
	var basis := Basis(right, Vector3.UP, -dir if absf(dir.y) < 0.9 else Vector3.BACK)
	emitter.emission_box_extents = Vector3(width * 0.5, 0.03, 0.12)
	# Placed first, then restarted, then told not to interpolate from where it was.
	emitter.global_transform = Transform3D(basis.orthonormalized(), at)
	emitter.restart()
	emitter.reset_physics_interpolation()


## The emitter of this type whose particle count is nearest amount (round-robin
## between equals).
func _take(type: int, amount: int) -> CPUParticles3D:
	var found: Array[int] = []
	var nearest := 1 << 30
	for index: int in _types.size():
		if _types[index] != type:
			continue
		var gap := absi(_amounts[index] - amount)
		if gap < nearest:
			nearest = gap
			found.clear()
		if gap == nearest:
			found.append(index)
	if found.is_empty():
		return null
	var turn := int(_next.get(type, 0))
	_next[type] = turn + 1
	return _emitters[found[turn % found.size()]]


func _make(type: int) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.one_shot = true
	emitter.emitting = false
	emitter.local_coords = false
	# Everything at once: with one_shot, particles still waiting to be emitted after
	# restart() draw as black quads at the emitter (Godot 4.7.2, seen in build/r1).
	emitter.explosiveness = 1.0
	emitter.randomness = 0.5
	emitter.lifetime_randomness = 0.35
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emitter.emission_box_extents = Vector3(0.5, 0.03, 0.12)
	emitter.gravity = Vector3(0.0, -9.8, 0.0)
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var quad := QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.roughness = 0.9
	var tones := Gradient.new()
	match type:
		BITS, SHREDS:
			quad.size = Vector2(0.03, 0.022) if type == BITS else Vector2(0.02, 0.014)
			tones.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
			tones.colors = PackedColorArray(LEAF_TONES if type == BITS else [Color(0.55, 0.38, 0.2), Color(0.42, 0.5, 0.18), Color(0.7, 0.45, 0.2), Color(0.35, 0.28, 0.16)])
			emitter.direction = Vector3(0.0, 1.0, -0.7) if type == BITS else Vector3(0.0, 1.0, 0.8)
			emitter.spread = 35.0
			emitter.initial_velocity_min = 1.0 if type == BITS else 2.0
			emitter.initial_velocity_max = 2.6 if type == BITS else 4.2
			emitter.damping_min = 1.5
			emitter.damping_max = 3.5
			emitter.lifetime = 0.8
			emitter.angle_min = 0.0
			emitter.angle_max = 360.0
			emitter.angular_velocity_min = -540.0
			emitter.angular_velocity_max = 540.0
			emitter.scale_amount_min = 0.6
			emitter.scale_amount_max = 1.5
		DUST:
			quad.size = Vector2(0.4, 0.4)
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_texture = _soft_dot()
			tones.offsets = PackedFloat32Array([0.0, 1.0])
			tones.colors = PackedColorArray([Color(0.62, 0.52, 0.38, 0.22), Color(0.55, 0.47, 0.36, 0.16)])
			var fade := Gradient.new()
			fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
			fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
			emitter.color_ramp = fade
			emitter.direction = Vector3(0.0, 1.0, -0.4)
			emitter.spread = 60.0
			emitter.initial_velocity_min = 0.25
			emitter.initial_velocity_max = 0.7
			emitter.gravity = Vector3(0.0, 0.15, 0.0)
			emitter.damping_min = 0.8
			emitter.damping_max = 1.4
			emitter.lifetime = 1.1
			var grow := Curve.new()
			grow.add_point(Vector2(0.0, 0.5))
			grow.add_point(Vector2(1.0, 1.6))
			emitter.scale_amount_curve = grow
		GRASS:
			quad.size = Vector2(0.012, 0.06)
			tones.offsets = PackedFloat32Array([0.0, 1.0])
			tones.colors = PackedColorArray([Color(0.36, 0.55, 0.2), Color(0.5, 0.66, 0.26)])
			emitter.direction = Vector3(0.0, 1.0, -0.5)
			emitter.spread = 30.0
			emitter.initial_velocity_min = 0.8
			emitter.initial_velocity_max = 1.6
			emitter.lifetime = 0.6
			emitter.angle_min = 0.0
			emitter.angle_max = 360.0
			emitter.angular_velocity_min = -360.0
			emitter.angular_velocity_max = 360.0
	emitter.color_initial_ramp = tones
	quad.material = material
	emitter.mesh = quad
	return emitter


static func _soft_dot() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture
