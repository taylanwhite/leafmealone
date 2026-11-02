extends RefCounted

## Authority: local, cosmetic. Estate, HOA, and waterfront pieces for the
## neighborhood looks: pools, docks and boats, fountains, topiaries (one of them
## a giant rake), lions, iron fences and gates, the HOA gatehouse and its
## violation flags, monument signs, the Dandelion Acres arch, retaining walls,
## and the winter fishing shanty. Built with props/mesh_kit.gd through
## props/prop_parts.gd and registered by props/prop_catalog.gd (ask it, not this
## file). Water, labels, and moving fountain sheets are added by
## PropCatalog.place(); the meshes here are the dry parts. Every mesh stays under
## Constants.ART_PROP_MAX_TRIANGLES.
##
## Frame: 1 m units, Y up, origin at the ground center, front facing -Z. color is
## the main color (Color.WHITE = the kind's default). Sized kinds (SIZED) read
## size as dimensions: pool_inground's water is size.x by size.z, a dock is size.x
## wide and size.z long (reaching out toward -Z from its shore end at the
## origin), wall and fence runs are size.x long and size.y tall.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _P = preload("res://props/prop_parts.gd")
const _Street = preload("res://props/street_props.gd")

const KINDS: Array[String] = [
	"pool_inground", "hot_tub", "pool_lounger", "pool_umbrella", "dock", "boat_row", "boat_motor",
	"kayak_rack", "buoy", "boathouse", "swim_platform", "life_ring", "fountain_tiered", "topiary_ball",
	"topiary_spiral", "topiary_rake", "lion_statue", "urn_planter", "gate_pillar", "iron_fence_run",
	"iron_gate", "column", "balustrade_run", "putting_green", "gazebo", "tennis_court", "gatehouse",
	"hoa_flag", "monument_sign", "entrance_arch", "retaining_wall_run", "fishing_shanty",
]
const SIZED: Array[String] = ["pool_inground", "dock", "iron_fence_run", "balustrade_run", "retaining_wall_run"]

const POOL_SIZE := Vector3(8.0, 0.0, 4.0)
const DOCK_SIZE := Vector3(2.0, 0.0, 10.0)
## A pool's coping width, and its water's height above the ground.
const POOL_COPING := 0.4
const POOL_WATER_Y := 0.05
## The hot tub's water: its top and its half size.
const TUB_WATER_Y := 0.86
const TUB_HALF := 0.92
## A dock's deck top above the ground at its shore end.
const DOCK_DECK_Y := 0.28
## Fountain tiers, bottom to top: [water radius, water height]. place() fills
## each with water and runs a falling sheet from each upper rim to the tier below.
const FOUNTAIN_TIERS: Array = [[1.55, 0.46], [0.78, 1.42], [0.38, 2.12]]
const BOAT_LENGTHS: Dictionary = {"boat_row": 3.6, "boat_motor": 5.6}
const BOAT_BEAMS: Dictionary = {"boat_row": 1.3, "boat_motor": 2.0}
const BOAT_DEPTHS: Dictionary = {"boat_row": 0.55, "boat_motor": 0.8}

const MARBLE := Color(0.92, 0.9, 0.86)
const TOPIARY := Color(0.18, 0.4, 0.2)
const IRON := Color(0.08, 0.08, 0.09)
const HOA_RED := Color(0.86, 0.12, 0.12)


static func build(kind: String, kit: _MeshKit, color: Color, size: Vector3) -> bool:
	match kind:
		"pool_inground":
			_pool(kit, _P.tint(color, Color(0.86, 0.84, 0.8)), _P.dims(size, POOL_SIZE))
		"hot_tub":
			_hot_tub(kit, _P.tint(color, Color(0.5, 0.36, 0.24)))
		"pool_lounger":
			_lounger(kit, _P.tint(color, _P.WHITE))
		"pool_umbrella":
			_umbrella(kit, _P.tint(color, Color(0.2, 0.42, 0.62)))
		"dock":
			_dock(kit, _P.tint(color, Color(0.62, 0.5, 0.38)), _P.dims(size, DOCK_SIZE))
		"boat_row":
			_boat_row(kit, _P.tint(color, Color(0.86, 0.32, 0.2)))
		"boat_motor":
			_boat_motor(kit, _P.tint(color, _P.WHITE))
		"kayak_rack":
			_kayak_rack(kit)
		"buoy":
			_buoy(kit, _P.tint(color, HOA_RED))
		"boathouse":
			_boathouse(kit, _P.tint(color, Color(0.55, 0.38, 0.28)))
		"swim_platform":
			_swim_platform(kit, _P.tint(color, Color(0.62, 0.5, 0.38)))
		"life_ring":
			_life_ring(kit)
		"fountain_tiered":
			_fountain(kit, _P.tint(color, MARBLE))
		"topiary_ball":
			_topiary_ball(kit, _P.tint(color, TOPIARY))
		"topiary_spiral":
			_topiary_spiral(kit, _P.tint(color, TOPIARY))
		"topiary_rake":
			_topiary_rake(kit, _P.tint(color, TOPIARY))
		"lion_statue":
			_lion(kit, _P.tint(color, Color(0.78, 0.76, 0.72)))
		"urn_planter":
			_urn(kit, _P.tint(color, Color(0.82, 0.8, 0.74)))
		"gate_pillar":
			_gate_pillar(kit, _P.tint(color, Color(0.74, 0.7, 0.62)))
		"iron_fence_run":
			_iron_run(kit, _P.tint(color, IRON), _P.dims(size, Vector3(6.0, 1.6, 0.0)))
		"iron_gate":
			_iron_gate(kit, _P.tint(color, IRON))
		"column":
			_column(kit, _P.tint(color, MARBLE))
		"balustrade_run":
			_balustrade(kit, _P.tint(color, MARBLE), _P.dims(size, Vector3(6.0, 0.95, 0.0)))
		"putting_green":
			_putting_green(kit)
		"gazebo":
			_gazebo(kit, _P.tint(color, _P.WHITE))
		"tennis_court":
			_tennis_court(kit)
		"gatehouse":
			_gatehouse(kit, _P.tint(color, Color(0.86, 0.82, 0.74)))
		"hoa_flag":
			_hoa_flag(kit)
		"monument_sign":
			_monument(kit, _P.tint(color, _P.BRICK))
		"entrance_arch":
			_arch(kit, _P.tint(color, _P.OLD_WOOD))
		"retaining_wall_run":
			_retaining_wall(kit, _P.tint(color, _P.STONE), _P.dims(size, Vector3(6.0, 3.0, 0.0)))
		"fishing_shanty":
			_shanty(kit, _P.tint(color, Color(0.36, 0.5, 0.62)))
		_:
			return false
	return true


# ---------------------------------------------------------------- pools

## An in-ground pool: the coping around the water (the water itself is
## place()'s), a ladder, and a diving board on a long pool.
static func _pool(kit: _MeshKit, color: Color, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var c := POOL_COPING
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(0.0, 0.04, side * (hz + c * 0.5)), Vector3(size.x + c * 2.0, 0.08, c), color)
		_P.slab(kit, Vector3(side * (hx + c * 0.5), 0.04, 0.0), Vector3(c, 0.08, size.z), color)
	# The pool's inner wall, a lighter tile band just under the rim.
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(0.0, -0.05, side * (hz - 0.02)), Vector3(size.x, 0.18, 0.04), Color(0.4, 0.7, 0.82))
		_P.slab(kit, Vector3(side * (hx - 0.02), -0.05, 0.0), Vector3(0.04, 0.18, size.z), Color(0.4, 0.7, 0.82))
	for x: float in [-0.25, 0.25]:
		_P.path(kit, PackedVector3Array([Vector3(hx - 1.0 + x, -0.3, -hz + 0.12), Vector3(hx - 1.0 + x, 0.75, -hz - 0.12), Vector3(hx - 1.0 + x, 0.75, -hz - 0.4), Vector3(hx - 1.0 + x, 0.08, -hz - 0.45)]), 0.025, _P.CHROME, 5)
	if size.x >= 6.0:
		_P.slab(kit, Vector3(-hx - 0.1, 0.3, 0.0), Vector3(0.5, 0.45, 0.5), color.darkened(0.1))
		_P.slab(kit, Vector3(-hx + 0.8, 0.52, 0.0), Vector3(2.4, 0.07, 0.5), Color(0.25, 0.55, 0.85))


static func _hot_tub(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.42, 0.0), Vector3(2.1, 0.84, 2.1), color)
	for index: int in 9:
		var x := -0.96 + float(index) * 0.24
		for side: float in [-1.0, 1.0]:
			_P.slab(kit, Vector3(x, 0.42, side * 1.055), Vector3(0.02, 0.8, 0.01), color.darkened(0.2))
	_P.slab(kit, Vector3(0.0, 0.87, 0.0), Vector3(2.16, 0.06, 2.16), color.darkened(0.1))
	_P.slab(kit, Vector3(0.0, 0.2, -1.25), Vector3(1.2, 0.4, 0.4), color.darkened(0.05))


static func _lounger(kit: _MeshKit, color: Color) -> void:
	for x: float in [-0.3, 0.3]:
		for z: float in [-0.8, 0.8]:
			_P.post(kit, Vector3(x, 0.0, z), 0.28, 0.02, _P.CHROME, 4)
	_P.slab(kit, Vector3(0.0, 0.3, 0.2), Vector3(0.66, 0.06, 1.3), color)
	_P.slab(kit, Vector3(0.0, 0.52, -0.66), Vector3(0.66, 0.06, 0.62), color, Basis(Vector3.RIGHT, -0.75))
	_P.slab(kit, Vector3(0.0, 0.34, 0.2), Vector3(0.6, 0.03, 1.24), Color(0.25, 0.55, 0.75))


static func _umbrella(kit: _MeshKit, color: Color) -> void:
	_P.disc(kit, Vector3(0.0, 0.05, 0.0), 0.3, 0.1, _P.DARK_STEEL, 8)
	_P.post(kit, Vector3(0.0, 0.1, 0.0), 2.3, 0.025, _P.WHITE, 4)
	kit.cone(Vector3(0.0, 2.1, 0.0), 1.5, 0.45, color, 8, {"lumps": 0.0, "droop": 0.08})
	_P.ball(kit, Vector3(0.0, 2.58, 0.0), Vector3(0.05, 0.05, 0.05), _P.WHITE, 0)


# ---------------------------------------------------------------- waterfront

## A dock: planks across, posts down into the water, a cleat or two. The shore
## end is at the origin; it reaches size.z out toward -Z, size.x wide.
static func _dock(kit: _MeshKit, color: Color, size: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(size.z * 10.0)
	var planks := int(size.z / 0.22)
	for index: int in planks:
		var z := -(float(index) + 0.5) * size.z / float(planks)
		_P.slab(kit, Vector3(0.0, DOCK_DECK_Y - 0.03, z), Vector3(size.x, 0.06, 0.2), _P.vary(color, rng, 0.1))
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * (size.x * 0.5 - 0.05), DOCK_DECK_Y - 0.14, -size.z * 0.5), Vector3(0.1, 0.16, size.z), color.darkened(0.25))
		var count := maxi(2, int(size.z / 2.5) + 1)
		for index: int in count:
			var z := -float(index) * size.z / float(count - 1)
			_P.post(kit, Vector3(side * (size.x * 0.5 + 0.06), -1.6, z), 1.6 + DOCK_DECK_Y + 0.25, 0.09, color.darkened(0.35), 6)
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * (size.x * 0.5 - 0.2), DOCK_DECK_Y + 0.04, -size.z + 0.6), Vector3(0.08, 0.06, 0.3), _P.DARK_STEEL)


static func _boat_row(kit: _MeshKit, color: Color) -> void:
	var length := float(BOAT_LENGTHS["boat_row"])
	var beam := float(BOAT_BEAMS["boat_row"])
	var depth := float(BOAT_DEPTHS["boat_row"])
	_Street._hull(kit, Vector3.ZERO, length, beam, depth, _P.WHITE, color)
	for z: float in [-0.4, 0.5, 1.3]:
		_P.slab(kit, Vector3(0.0, depth * 0.75, z), Vector3(beam * 0.88, 0.04, 0.24), _P.WOOD)
	for side: float in [-1.0, 1.0]:
		_P.bar(kit, Vector3(side * 0.3, depth + 0.05, 0.6), Vector3(side * 0.9, depth * 0.5, -0.9), 0.025, _P.WOOD.lightened(0.1), 4)
		_P.slab(kit, Vector3(side * 0.92, depth * 0.48, -0.95), Vector3(0.04, 0.12, 0.42), _P.WOOD.lightened(0.1), Basis(Vector3.UP, side * 0.35))


static func _boat_motor(kit: _MeshKit, color: Color) -> void:
	var length := float(BOAT_LENGTHS["boat_motor"])
	var beam := float(BOAT_BEAMS["boat_motor"])
	var depth := float(BOAT_DEPTHS["boat_motor"])
	_Street._hull(kit, Vector3.ZERO, length, beam, depth, color, Color(0.18, 0.36, 0.62))
	_P.slab(kit, Vector3(0.0, depth + 0.25, -0.2), Vector3(0.9, 0.5, 0.6), color.darkened(0.05))
	_P.slab(kit, Vector3(0.0, depth + 0.62, -0.42), Vector3(1.3, 0.45, 0.05), _P.GLASS, Basis(Vector3.RIGHT, 0.4))
	for side: float in [-0.45, 0.45]:
		_P.soft(kit, Vector3(side, depth + 0.2, 0.8), Vector3(0.6, 0.3, 0.6), _P.WHITE.darkened(0.08), 3.0, 1)
	_P.slab(kit, Vector3(0.0, depth + 0.2, length * 0.5 + 0.12), Vector3(0.36, 0.6, 0.4), _P.BLACK.lightened(0.12))
	_P.slab(kit, Vector3(0.0, depth - 0.3, length * 0.5 + 0.2), Vector3(0.12, 0.6, 0.18), _P.BLACK.lightened(0.2))


static func _kayak_rack(kit: _MeshKit) -> void:
	for x: float in [-1.4, 1.4]:
		for z: float in [-0.5, 0.5]:
			_P.slab(kit, Vector3(x, 0.8, z * 0.6), Vector3(0.1, 1.6, 0.1), _P.WOOD, Basis(Vector3.RIGHT, -z * 0.5))
	for y: float in [0.6, 1.2]:
		for z: float in [-0.35, 0.35]:
			_P.slab(kit, Vector3(0.0, y, z * (1.4 - y) * 0.5), Vector3(3.0, 0.07, 0.07), _P.WOOD.darkened(0.1))
	var colors: Array[Color] = [Color(0.98, 0.56, 0.12), Color(0.2, 0.62, 0.72), Color(0.95, 0.85, 0.2)]
	for index: int in 3:
		var y := 0.72 + float(index) * 0.35
		kit.tube(PackedVector3Array([Vector3(-1.8, y, 0.0), Vector3(-0.9, y + 0.04, 0.0), Vector3(0.9, y + 0.04, 0.0), Vector3(1.8, y, 0.0)]), PackedFloat32Array([0.02, 0.16, 0.16, 0.02]), colors[index], 6, {"jitter": 0.0})


static func _buoy(kit: _MeshKit, color: Color) -> void:
	_P.ball(kit, Vector3(0.0, 0.1, 0.0), Vector3(0.4, 0.38, 0.4), color, 1)
	_P.post(kit, Vector3(0.0, 0.36, 0.0), 0.15, 0.405, _P.WHITE, 10)
	_P.post(kit, Vector3(0.0, 0.48, 0.0), 0.7, 0.03, _P.DARK_STEEL, 4)
	_P.ball(kit, Vector3(0.0, 1.2, 0.0), Vector3(0.07, 0.09, 0.07), Color(0.98, 0.9, 0.5), 0)


## A boathouse on the shore, its open end over the water (-Z).
static func _boathouse(kit: _MeshKit, color: Color) -> void:
	var w := 5.0
	var d := 7.0
	var wall := 3.0
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * w * 0.5, wall * 0.5 - 0.5, 0.0), Vector3(0.16, wall + 1.0, d), color)
	_P.slab(kit, Vector3(0.0, wall * 0.5 - 0.5, d * 0.5), Vector3(w, wall + 1.0, 0.16), color)
	_P.slab(kit, Vector3(0.0, wall - 0.25, -d * 0.5), Vector3(w, 0.5, 0.16), color)
	_P.slab(kit, Vector3(0.0, -0.3, 0.0), Vector3(w - 0.2, 0.05, d - 0.2), Color(0.12, 0.18, 0.2))
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * w * 0.27, wall + 0.85, 0.0), Vector3(w * 0.6, 0.14, d + 0.6), Color(0.22, 0.38, 0.28), Basis(Vector3.BACK, -side * 0.62))
		_P.slab(kit, Vector3(side * (w * 0.5 - 0.6), 0.05, 0.0), Vector3(1.0, 0.1, d - 0.3), _P.WOOD)
	for z: float in [-d * 0.5, d * 0.5]:
		_P.poly(kit, [Vector3(-w * 0.5, wall, z), Vector3(w * 0.5, wall, z), Vector3(0.0, wall + 1.6, z)], Vector3(0.0, wall + 0.5, 0.0), color)


static func _swim_platform(kit: _MeshKit, color: Color) -> void:
	for x: float in [-0.9, 0.9]:
		_P.bar(kit, Vector3(x, -0.05, -1.1), Vector3(x, -0.05, 1.1), 0.24, _P.WHITE, 8)
	for index: int in 11:
		_P.slab(kit, Vector3(0.0, 0.22, -1.25 + float(index) * 0.25), Vector3(2.5, 0.06, 0.22), color)
	for x: float in [-0.25, 0.25]:
		_P.path(kit, PackedVector3Array([Vector3(x, -0.6, -1.35), Vector3(x, 0.8, -1.35), Vector3(x, 0.8, -1.15), Vector3(x, 0.25, -1.1)]), 0.025, _P.CHROME, 5)


static func _life_ring(kit: _MeshKit) -> void:
	_P.slab(kit, Vector3(0.0, 0.8, 0.05), Vector3(0.1, 1.6, 0.1), _P.WOOD)
	var face := Basis(Vector3.RIGHT, PI * 0.5)
	for index: int in 4:
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		for step: int in 4:
			var angle := TAU * (float(index) + float(step) / 3.0) / 4.0
			points.append(Vector3(0.0, 1.25, 0.0) + face * Vector3(cos(angle) * 0.3, 0.0, sin(angle) * 0.3))
			radii.append(0.07)
		kit.tube(points, radii, HOA_RED if index % 2 == 0 else _P.WHITE, 6, {"jitter": 0.0, "cap": false})


# ---------------------------------------------------------------- estates

## A tiered fountain: a wide basin, two raised tiers, a spout. place() adds the
## water in each tier (FOUNTAIN_TIERS) and the falling sheets.
static func _fountain(kit: _MeshKit, color: Color) -> void:
	var lower: Array = FOUNTAIN_TIERS[0]
	var lower_r := float(lower[0]) + 0.12
	kit.tube(PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.56, 0.0)]), PackedFloat32Array([lower_r + 0.1, lower_r]), color, 16, {"jitter": 0.0, "cap": false})
	_P.ring(kit, Vector3(0.0, 0.56, 0.0), lower_r, 0.1, color.lightened(0.04), 16, 5)
	_P.disc(kit, Vector3(0.0, 0.2, 0.0), lower_r - 0.05, 0.4, Color(0.3, 0.42, 0.46), 16)
	kit.tube(PackedVector3Array([Vector3(0.0, 0.2, 0.0), Vector3(0.0, 0.5, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.3, 0.0)]), PackedFloat32Array([0.32, 0.18, 0.14, 0.2]), color, 10, {"jitter": 0.0})
	var middle: Array = FOUNTAIN_TIERS[1]
	kit.tube(PackedVector3Array([Vector3(0.0, 1.22, 0.0), Vector3(0.0, 1.5, 0.0)]), PackedFloat32Array([0.24, float(middle[0]) + 0.08]), color, 14, {"jitter": 0.0, "cap": false, "cap_start": true})
	_P.ring(kit, Vector3(0.0, 1.5, 0.0), float(middle[0]) + 0.06, 0.05, color.lightened(0.04), 14, 4)
	kit.tube(PackedVector3Array([Vector3(0.0, 1.45, 0.0), Vector3(0.0, 1.9, 0.0), Vector3(0.0, 2.0, 0.0)]), PackedFloat32Array([0.12, 0.08, 0.12]), color, 8, {"jitter": 0.0})
	var top: Array = FOUNTAIN_TIERS[2]
	kit.tube(PackedVector3Array([Vector3(0.0, 1.98, 0.0), Vector3(0.0, 2.18, 0.0)]), PackedFloat32Array([0.14, float(top[0]) + 0.06]), color, 12, {"jitter": 0.0, "cap": false, "cap_start": true})
	_P.ring(kit, Vector3(0.0, 2.18, 0.0), float(top[0]) + 0.05, 0.04, color.lightened(0.04), 12, 4)
	kit.tube(PackedVector3Array([Vector3(0.0, 2.15, 0.0), Vector3(0.0, 2.4, 0.0), Vector3(0.0, 2.5, 0.0)]), PackedFloat32Array([0.06, 0.04, 0.0]), color, 8, {"jitter": 0.0, "cap": false})


static func _pot(kit: _MeshKit, height: float, radius: float) -> void:
	kit.tube(PackedVector3Array([Vector3.ZERO, Vector3(0.0, height, 0.0)]), PackedFloat32Array([radius * 0.8, radius]), Color(0.72, 0.42, 0.28), 10, {"jitter": 0.0, "cap_start": true})
	_P.ring(kit, Vector3(0.0, height, 0.0), radius, 0.04, Color(0.72, 0.42, 0.28).darkened(0.1), 10, 4)
	_P.disc(kit, Vector3(0.0, height - 0.03, 0.0), radius - 0.02, 0.02, _P.SOIL, 10)


static func _topiary_ball(kit: _MeshKit, color: Color) -> void:
	_pot(kit, 0.5, 0.36)
	_P.post(kit, Vector3(0.0, 0.45, 0.0), 0.6, 0.04, Color(0.4, 0.3, 0.22), 5)
	_P.lump(kit, Vector3(0.0, 1.35, 0.0), Vector3(0.5, 0.48, 0.5), color, 4, 2, 0.08)


static func _topiary_spiral(kit: _MeshKit, color: Color) -> void:
	_pot(kit, 0.5, 0.4)
	_P.post(kit, Vector3(0.0, 0.45, 0.0), 2.1, 0.035, Color(0.4, 0.3, 0.22), 5)
	for index: int in 12:
		var t := float(index) / 11.0
		var angle := t * TAU * 2.5
		var radius := lerpf(0.42, 0.1, t)
		_P.lump(kit, Vector3(cos(angle) * radius * 0.6, 0.7 + t * 1.9, sin(angle) * radius * 0.6), Vector3(radius + 0.06, 0.16, radius + 0.06), color.lightened(0.04 * float(index % 2)), index, 1, 0.12)


## Mansion Hill's masterpiece: a hedge clipped into a giant leaf rake standing
## on its tines, the fan spread wide at the bottom and the handle reaching up
## past the second floor. (docs/GAME.md: the rake topiary.)
static func _topiary_rake(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.12, 0.0), Vector3(3.6, 0.24, 1.1), _P.STONE.lightened(0.08))
	# The fan: tines spreading from the neck down to the ground.
	var neck := Vector3(0.0, 2.1, 0.0)
	for index: int in 9:
		var spread := lerpf(-1.0, 1.0, float(index) / 8.0)
		var tip := Vector3(spread * 1.6, 0.34, -0.15 * (1.0 - absf(spread)))
		var root := neck + Vector3(spread * 0.22, -0.1, 0.0)
		var bend := tip + Vector3(0.0, 0.25, -0.05)
		kit.tube(PackedVector3Array([root, root.lerp(bend, 0.5), bend, tip + Vector3(0.0, 0.0, -0.22)]), PackedFloat32Array([0.14, 0.15, 0.14, 0.11]), color.lightened(0.03 * float(index % 3)), 7, {"jitter": 0.05, "seed": index, "cap": true, "cap_start": true})
	# The crossbar across the fan, and the collar at the neck.
	_P.lump(kit, Vector3(0.0, 1.25, 0.0), Vector3(0.95, 0.13, 0.15), color.darkened(0.04), 60, 1, 0.1)
	_P.lump(kit, neck + Vector3(0.0, 0.05, 0.0), Vector3(0.3, 0.2, 0.2), color, 61, 1, 0.1)
	# The handle, one clipped ball after another, and the grip.
	for index: int in 7:
		var y := 2.45 + float(index) * 0.42
		_P.lump(kit, Vector3(0.0, y, 0.0), Vector3(0.17, 0.25, 0.17), color.lightened(0.03 * float(index % 2)), 70 + index, 1, 0.1)
	_P.lump(kit, Vector3(0.0, 5.5, 0.0), Vector3(0.24, 0.3, 0.24), color.lightened(0.06), 80, 1, 0.1)

## A stone lion on a plinth, lying with its head up, facing -Z.
static func _lion(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.45, 0.0), Vector3(0.8, 0.9, 1.4), color.darkened(0.06))
	_P.slab(kit, Vector3(0.0, 0.93, 0.0), Vector3(0.9, 0.06, 1.5), color.lightened(0.04))
	_P.ball(kit, Vector3(0.0, 1.22, 0.15), Vector3(0.3, 0.26, 0.55), color, 1)
	for side: float in [-1.0, 1.0]:
		_P.soft(kit, Vector3(side * 0.18, 1.04, -0.42), Vector3(0.16, 0.14, 0.42), color, 3.0, 0)
		_P.ball(kit, Vector3(side * 0.22, 1.1, 0.48), Vector3(0.12, 0.14, 0.2), color, 0)
	_P.lump(kit, Vector3(0.0, 1.48, -0.3), Vector3(0.3, 0.32, 0.26), color.darkened(0.08), 3, 1, 0.3)
	_P.ball(kit, Vector3(0.0, 1.5, -0.46), Vector3(0.17, 0.18, 0.17), color, 1)
	_P.ball(kit, Vector3(0.0, 1.45, -0.6), Vector3(0.09, 0.07, 0.08), color.lightened(0.05), 0)
	_P.path(kit, PackedVector3Array([Vector3(0.0, 1.1, 0.68), Vector3(0.2, 0.98, 0.78), Vector3(0.32, 0.97, 0.6)]), 0.03, color, 4)
	_P.ball(kit, Vector3(0.32, 0.98, 0.58), Vector3(0.06, 0.06, 0.06), color.darkened(0.08), 0)


static func _urn(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.08, 0.0), Vector3(0.4, 0.16, 0.4), color.darkened(0.06))
	kit.tube(PackedVector3Array([Vector3(0.0, 0.16, 0.0), Vector3(0.0, 0.3, 0.0), Vector3(0.0, 0.55, 0.0), Vector3(0.0, 0.8, 0.0), Vector3(0.0, 0.9, 0.0)]), PackedFloat32Array([0.1, 0.08, 0.26, 0.3, 0.36]), color, 12, {"jitter": 0.0, "cap": false, "cap_start": true})
	_P.ring(kit, Vector3(0.0, 0.9, 0.0), 0.36, 0.03, color, 12, 4)
	_P.lump(kit, Vector3(0.0, 1.0, 0.0), Vector3(0.36, 0.2, 0.36), Color(0.2, 0.44, 0.2), 6, 1, 0.3, 0.3)
	for index: int in 5:
		var angle := TAU * float(index) / 5.0
		_P.ball(kit, Vector3(cos(angle) * 0.25, 1.08, sin(angle) * 0.25), Vector3(0.06, 0.05, 0.06), Color(0.96, 0.44, 0.52) if index % 2 == 0 else _P.WHITE, 0, 0.35)


static func _gate_pillar(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 1.1, 0.0), Vector3(0.7, 2.2, 0.7), color)
	for course: int in 5:
		_P.slab(kit, Vector3(0.0, 0.3 + float(course) * 0.42, 0.0), Vector3(0.72, 0.03, 0.72), color.darkened(0.12))
	_P.slab(kit, Vector3(0.0, 2.26, 0.0), Vector3(0.86, 0.12, 0.86), color.lightened(0.06))
	_P.slab(kit, Vector3(0.0, 2.36, 0.0), Vector3(0.6, 0.08, 0.6), color)
	_P.ball(kit, Vector3(0.0, 2.6, 0.0), Vector3(0.22, 0.22, 0.22), color.lightened(0.04), 1)


## Wrought iron along local x: bars with spear finials, two rails, posts with caps.
static func _iron_run(kit: _MeshKit, color: Color, size: Vector3) -> void:
	var bars := int(size.x / 0.16)
	for index: int in bars:
		var x := -size.x * 0.5 + (float(index) + 0.5) * size.x / float(bars)
		_P.bar(kit, Vector3(x, 0.05, 0.0), Vector3(x, size.y, 0.0), 0.012, color, 4)
		_P.cone(kit, Vector3(x, size.y, 0.0), 0.03, 0.1, color, 4)
	for y: float in [0.15, size.y - 0.15]:
		_P.slab(kit, Vector3(0.0, y, 0.0), Vector3(size.x, 0.04, 0.03), color)
	for x: float in [-size.x * 0.5, size.x * 0.5]:
		_P.slab(kit, Vector3(x, size.y * 0.55, 0.0), Vector3(0.08, size.y * 1.1, 0.08), color)
		_P.ball(kit, Vector3(x, size.y * 1.12, 0.0), Vector3(0.06, 0.06, 0.06), color, 0)


## A double iron gate, closed, for a gap 3.4 m wide (pillars go at x +-2.05).
static func _iron_gate(kit: _MeshKit, color: Color) -> void:
	var gold := Color(0.86, 0.7, 0.32)
	for side: float in [-1.0, 1.0]:
		for index: int in 10:
			var x := side * (0.08 + float(index) * 0.17)
			var height := 2.0 + 0.4 * cos(absf(x) / 1.7 * PI * 0.5)
			_P.bar(kit, Vector3(x, 0.05, 0.0), Vector3(x, height, 0.0), 0.014, color, 4)
			_P.cone(kit, Vector3(x, height, 0.0), 0.035, 0.12, gold, 4)
		_P.slab(kit, Vector3(side * 0.86, 0.2, 0.0), Vector3(1.66, 0.05, 0.04), color)
		_P.slab(kit, Vector3(side * 0.86, 1.7, 0.0), Vector3(1.66, 0.05, 0.04), color)
		_P.ring(kit, Vector3(side * 0.86, 0.95, 0.0), 0.32, 0.02, gold, 12, 3, Basis(Vector3.RIGHT, PI * 0.5))
	_P.slab(kit, Vector3(0.0, 1.0, 0.0), Vector3(0.05, 2.0, 0.05), color)


static func _column(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.1, 0.0), Vector3(0.62, 0.2, 0.62), color.darkened(0.04))
	_P.disc(kit, Vector3(0.0, 0.26, 0.0), 0.26, 0.12, color, 12)
	kit.tube(PackedVector3Array([Vector3(0.0, 0.3, 0.0), Vector3(0.0, 1.6, 0.0), Vector3(0.0, 2.9, 0.0)]), PackedFloat32Array([0.22, 0.215, 0.19]), color, 12, {"jitter": 0.0})
	_P.disc(kit, Vector3(0.0, 2.95, 0.0), 0.24, 0.1, color, 12)
	_P.slab(kit, Vector3(0.0, 3.06, 0.0), Vector3(0.6, 0.14, 0.6), color.lightened(0.03))


static func _balustrade(kit: _MeshKit, color: Color, size: Vector3) -> void:
	var count := int(size.x / 0.26)
	for index: int in count:
		var x := -size.x * 0.5 + (float(index) + 0.5) * size.x / float(count)
		kit.tube(PackedVector3Array([Vector3(x, 0.12, 0.0), Vector3(x, 0.3, 0.0), Vector3(x, 0.55, 0.0), Vector3(x, size.y - 0.08, 0.0)]), PackedFloat32Array([0.05, 0.08, 0.05, 0.045]), color, 6, {"jitter": 0.0})
	_P.slab(kit, Vector3(0.0, 0.06, 0.0), Vector3(size.x, 0.12, 0.24), color.darkened(0.04))
	_P.slab(kit, Vector3(0.0, size.y - 0.04, 0.0), Vector3(size.x, 0.1, 0.26), color.lightened(0.03))
	for x: float in [-size.x * 0.5, size.x * 0.5]:
		_P.slab(kit, Vector3(x, size.y * 0.5, 0.0), Vector3(0.3, size.y + 0.04, 0.3), color)


static func _putting_green(kit: _MeshKit) -> void:
	kit.blob(Vector3(0.0, 0.0, 0.0), Vector3(3.2, 0.04, 2.2), Color(0.3, 0.62, 0.28), {"detail": 2, "lumps": 0.2, "lump_scale": 0.8, "flat": true, "jitter": 0.0, "seed": 4, "shade": false})
	_P.disc(kit, Vector3(1.1, 0.04, -0.3), 0.07, 0.01, _P.BLACK, 8)
	_P.post(kit, Vector3(1.1, 0.0, -0.3), 1.7, 0.01, _P.WHITE, 4)
	_P.card(kit, Vector3(1.1 + 0.25, 1.38, -0.3), 0.5, 0.3, Color(0.96, 0.84, 0.15), Basis.IDENTITY, 0.6, 0.6, 0.0)
	_P.ball(kit, Vector3(0.3, 0.06, 0.4), Vector3(0.03, 0.03, 0.03), _P.WHITE, 0)


static func _gazebo(kit: _MeshKit, color: Color) -> void:
	var radius := 1.9
	_P.disc(kit, Vector3(0.0, 0.15, 0.0), radius + 0.15, 0.3, _P.WOOD.lightened(0.1), 8)
	for index: int in 8:
		var angle := TAU * float(index) / 8.0 + PI / 8.0
		var at := Vector3(cos(angle), 0.0, sin(angle)) * radius
		_P.slab(kit, at + Vector3(0.0, 1.5, 0.0), Vector3(0.12, 2.4, 0.12), color, Basis(Vector3.UP, -angle))
		if index != 6:
			var next := Vector3(cos(angle + TAU / 8.0), 0.0, sin(angle + TAU / 8.0)) * radius
			_P.slab(kit, (at + next) * 0.5 + Vector3(0.0, 0.9, 0.0), Vector3(at.distance_to(next), 0.07, 0.06), color, Basis(Vector3.UP, -(angle + TAU / 16.0) - PI * 0.5))
	kit.cone(Vector3(0.0, 2.7, 0.0), radius + 0.45, 1.3, Color(0.3, 0.42, 0.36), 8, {"lumps": 0.0, "droop": 0.0})
	_P.cone(kit, Vector3(0.0, 3.98, 0.0), 0.08, 0.4, color, 6)


static func _tennis_court(kit: _MeshKit) -> void:
	var court := Vector2(10.97, 23.77)
	_P.slab(kit, Vector3(0.0, 0.01, 0.0), Vector3(court.x + 6.0, 0.02, court.y + 6.0), Color(0.64, 0.32, 0.24))
	_P.slab(kit, Vector3(0.0, 0.025, 0.0), Vector3(court.x, 0.02, court.y), Color(0.24, 0.48, 0.36))
	var line := Color(0.95, 0.95, 0.93)
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * court.x * 0.5, 0.04, 0.0), Vector3(0.06, 0.01, court.y), line)
		_P.slab(kit, Vector3(side * 4.115, 0.04, 0.0), Vector3(0.06, 0.01, court.y), line)
		_P.slab(kit, Vector3(0.0, 0.04, side * court.y * 0.5), Vector3(court.x, 0.01, 0.06), line)
		_P.slab(kit, Vector3(0.0, 0.04, side * 6.4), Vector3(8.23, 0.01, 0.06), line)
		_P.post(kit, Vector3(side * (court.x * 0.5 + 0.9), 0.0, 0.0), 1.07, 0.04, _P.DARK_STEEL, 5)
	_P.slab(kit, Vector3(0.0, 0.04, 0.0), Vector3(0.06, 0.01, 12.8), line)
	_P.slab(kit, Vector3(0.0, 0.55, 0.0), Vector3(court.x + 1.8, 0.9, 0.02), Color(0.12, 0.12, 0.13))
	_P.slab(kit, Vector3(0.0, 1.0, 0.0), Vector3(court.x + 1.8, 0.07, 0.04), _P.WHITE)


## Oak Hollow's gatehouse: a booth with windows on every side, a flat roof
## with an overhang, a striped barrier arm down across the lane to +x, and a sign
## board beside the booth (sign face at (-2.3, 1.25, -0.95)).
static func _gatehouse(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.1, 0.0), Vector3(2.6, 0.2, 3.0), _P.STONE)
	_P.slab(kit, Vector3(0.0, 0.6, 0.0), Vector3(2.0, 0.8, 2.4), color)
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 0.95, 1.65, 0.0), Vector3(0.1, 1.3, 2.4), color)
		_P.slab(kit, Vector3(0.0, 1.65, side * 1.15), Vector3(2.0, 1.3, 0.1), color)
		_P.slab(kit, Vector3(side * 1.005, 1.6, 0.0), Vector3(0.02, 0.9, 1.9), _P.GLASS)
		_P.slab(kit, Vector3(0.0, 1.6, side * 1.205), Vector3(1.5, 0.9, 0.02), _P.GLASS)
	_P.slab(kit, Vector3(0.0, 2.4, 0.0), Vector3(2.0, 0.2, 2.4), color)
	_P.slab(kit, Vector3(0.0, 2.6, 0.0), Vector3(3.0, 0.16, 3.4), Color(0.42, 0.34, 0.28))
	_P.slab(kit, Vector3(0.0, 2.72, 0.0), Vector3(2.6, 0.1, 3.0), Color(0.42, 0.34, 0.28).darkened(0.1))
	# The barrier: a post with a counterweight, the arm striped red and white.
	_P.slab(kit, Vector3(1.5, 0.5, -1.0), Vector3(0.4, 1.0, 0.4), Color(0.85, 0.85, 0.82))
	_P.slab(kit, Vector3(1.2, 1.0, -1.0), Vector3(0.5, 0.25, 0.2), _P.DARK_STEEL)
	for index: int in 8:
		_P.slab(kit, Vector3(1.9 + float(index) * 0.5, 1.0, -1.0), Vector3(0.5, 0.1, 0.08), HOA_RED if index % 2 == 0 else _P.WHITE)
	_P.slab(kit, Vector3(5.8, 0.5, -1.0), Vector3(0.08, 1.0, 0.08), _P.DARK_STEEL)
	# The sign beside the booth (its words via place(): RESIDENTS & APPROVED VENDORS ONLY).
	for x: float in [-3.0, -1.6]:
		_P.slab(kit, Vector3(x, 0.75, -0.9), Vector3(0.1, 1.5, 0.1), _P.WHITE)
	_P.slab(kit, Vector3(-2.3, 1.25, -0.9), Vector3(1.8, 0.7, 0.06), Color(0.24, 0.32, 0.26))
	_P.slab(kit, Vector3(-2.3, 1.25, -0.935), Vector3(1.66, 0.56, 0.02), Color(0.94, 0.92, 0.86))


## A small red flag on a wire stake: the HOA's NOTICE OF VIOLATION (the label
## goes on the nearest few through place()). It flutters.
static func _hoa_flag(kit: _MeshKit) -> void:
	_P.post(kit, Vector3.ZERO, 0.62, 0.005, _P.STEEL, 3)
	_P.card(kit, Vector3(0.11, 0.42, 0.0), 0.22, 0.17, HOA_RED, Basis.IDENTITY, 0.6, 0.6, 0.0)


## A monument sign: a low wall with a cap and a lighter face panel (the words via
## place(), a sign key or text).
static func _monument(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.7, 0.0), Vector3(3.2, 1.4, 0.55), color)
	for course: int in 6:
		_P.slab(kit, Vector3(0.0, 0.12 + float(course) * 0.22, 0.0), Vector3(3.22, 0.02, 0.57), color.darkened(0.12))
	_P.slab(kit, Vector3(0.0, 1.46, 0.0), Vector3(3.4, 0.12, 0.7), _P.STONE.lightened(0.1))
	_P.slab(kit, Vector3(0.0, 0.8, -0.285), Vector3(2.7, 0.9, 0.04), Color(0.9, 0.88, 0.82))
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 1.8, 0.85, 0.0), Vector3(0.45, 1.7, 0.7), color.darkened(0.06))
		_P.slab(kit, Vector3(side * 1.8, 1.75, 0.0), Vector3(0.55, 0.1, 0.8), _P.STONE.lightened(0.1))
		_P.lump(kit, Vector3(side * 0.9, 0.18, -0.6), Vector3(0.6, 0.2, 0.25), Color(0.2, 0.44, 0.2), 7 + int(side), 1, 0.25)


## Dandelion Acres' hand-made entrance: two log posts, a plank arch across, and
## a hanging board (its painted words via place()).
static func _arch(kit: _MeshKit, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		kit.tube(PackedVector3Array([Vector3(side * 3.0, 0.0, 0.0), Vector3(side * 3.0, 4.2, 0.0)]), PackedFloat32Array([0.16, 0.13]), color.darkened(0.1), 7, {"jitter": 0.0})
		_P.slab(kit, Vector3(side * 3.0, 0.15, 0.0), Vector3(0.6, 0.3, 0.6), Color(0.62, 0.62, 0.6))
	var points := PackedVector3Array()
	for step: int in 9:
		var t := float(step) / 8.0
		points.append(Vector3(lerpf(-3.15, 3.15, t), 3.9 + sin(t * PI) * 0.45, 0.0))
	for step: int in points.size() - 1:
		var a := points[step]
		var b := points[step + 1]
		_P.slab(kit, (a + b) * 0.5, Vector3(a.distance_to(b) + 0.04, 0.32, 0.08), color.darkened(0.04 * float(step % 2)), Basis(Vector3.BACK, atan2(b.y - a.y, b.x - a.x)))
	for x: float in [-1.0, 1.0]:
		_P.bar(kit, Vector3(x, 3.9 + 0.35, -0.05), Vector3(x, 3.4, -0.05), 0.01, _P.STEEL, 3)
	_P.slab(kit, Vector3(0.0, 3.05, -0.05), Vector3(3.0, 0.8, 0.06), Color(0.92, 0.88, 0.74), Basis(Vector3.BACK, 0.03))
	# Hand-painted daisies on the posts.
	for side: float in [-1.0, 1.0]:
		_P.ball(kit, Vector3(side * 3.0, 2.0, -0.15), Vector3(0.12, 0.12, 0.02), Color(0.98, 0.86, 0.2), 0)


## A stone retaining wall along local x, size.x long and size.y tall, its face
## toward -Z, with a cap. Stairs and the raised ground behind are set pieces.
static func _retaining_wall(kit: _MeshKit, color: Color, size: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(size.x * 10.0 + size.y)
	_P.slab(kit, Vector3(0.0, size.y * 0.5, 0.25), Vector3(size.x, size.y, 0.5), color.darkened(0.15))
	var rows := maxi(1, int(size.y / 0.45))
	for row: int in rows:
		var y := (float(row) + 0.5) * size.y / float(rows)
		var x := -size.x * 0.5 + (0.0 if row % 2 == 0 else 0.4)
		while x < size.x * 0.5 - 0.1:
			var width := minf(rng.randf_range(0.6, 1.1), size.x * 0.5 - x)
			_P.slab(kit, Vector3(x + width * 0.5, y, -0.03), Vector3(width - 0.05, size.y / float(rows) - 0.05, 0.08), _P.vary(color, rng, 0.12))
			x += width
	_P.slab(kit, Vector3(0.0, size.y + 0.06, 0.2), Vector3(size.x + 0.1, 0.12, 0.7), color.lightened(0.08))


## The fishing shanty out on the frozen lake (winter): a little shack on skids,
## a door, a window, a stovepipe. Never labeled.
static func _shanty(kit: _MeshKit, color: Color) -> void:
	for x: float in [-0.75, 0.75]:
		_P.slab(kit, Vector3(x, 0.06, 0.0), Vector3(0.12, 0.12, 2.6), _P.WOOD.darkened(0.2))
	_P.slab(kit, Vector3(0.0, 1.12, 0.0), Vector3(1.8, 2.0, 2.2), color)
	_P.slab(kit, Vector3(0.0, 2.2, 0.1), Vector3(2.0, 0.1, 2.6), Color(0.4, 0.4, 0.42), Basis(Vector3.RIGHT, -0.12))
	_P.slab(kit, Vector3(0.0, 1.0, -1.105), Vector3(0.7, 1.6, 0.02), color.darkened(0.2))
	_P.slab(kit, Vector3(0.905, 1.4, 0.3), Vector3(0.02, 0.4, 0.5), _P.GLASS)
	_P.post(kit, Vector3(0.5, 2.2, 0.6), 0.8, 0.07, _P.DARK_STEEL, 6)
	_P.cone(kit, Vector3(0.5, 3.0, 0.6), 0.14, 0.1, _P.DARK_STEEL, 6)
