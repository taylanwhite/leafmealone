extends RefCounted

## Authority: local, cosmetic. Front-yard and backyard clutter for the
## neighborhood looks (docs/GAME.md, "the neighborhood looks"): grills, swing
## sets, trampolines, flamingos, bikes, wagons, lawn chairs, laundry, junk, and
## the fence runs and boxwoods between yards. Built with props/mesh_kit.gd
## through props/prop_parts.gd, registered by props/prop_catalog.gd (ask it, not
## this file). Every mesh stays under Constants.ART_PROP_MAX_TRIANGLES.
##
## Frame: 1 m units, Y up, origin at the ground center, front facing -Z. color is
## the main color (Color.WHITE = the kind's default). Sized kinds (SIZED) read
## size as their dimensions: fence runs are size.x long and size.y tall (6 m long
## by default), boxwood fills size.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _P = preload("res://props/prop_parts.gd")

const KINDS: Array[String] = [
	"bbq_kettle", "bbq_gas", "swing_set", "trampoline", "kiddie_pool", "flamingo", "garden_bed_raised",
	"tomato_cage", "kid_bike", "red_wagon", "patio_set", "lawn_chair_plastic", "adirondack", "hammock",
	"porch_swing", "rocking_chair", "birdbath", "bird_feeder", "doghouse", "clothesline", "sprinkler",
	"hose_reel", "compost_bin", "wood_pile", "junk_pile", "tire_stack", "old_couch", "fridge",
	"satellite_dish", "propane_tank", "window_ac", "playhouse", "sandbox", "pinwheel", "landscape_rocks",
	"solar_light", "tire_planter", "staked_sapling_stakes", "fire_pit", "boxwood",
	"privacy_fence_run", "chainlink_run", "split_rail_run", "vinyl_fence_run", "picket_fence_run",
	"weathered_picket_run", "barn", "silo", "gnome",
]
const SIZED: Array[String] = [
	"boxwood", "privacy_fence_run", "chainlink_run", "split_rail_run", "vinyl_fence_run",
	"picket_fence_run", "weathered_picket_run",
]
## Default fence run length, and the fence run kinds.
const RUN_LENGTH := 6.0
const RUNS: Array[String] = ["privacy_fence_run", "chainlink_run", "split_rail_run", "vinyl_fence_run", "picket_fence_run", "weathered_picket_run"]

const PINK := Color(0.98, 0.45, 0.66)
const KID_RED := Color(0.86, 0.18, 0.14)
const PLASTIC_BLUE := Color(0.3, 0.6, 0.9)


static func build(kind: String, kit: _MeshKit, color: Color, size: Vector3) -> bool:
	match kind:
		"bbq_kettle":
			_bbq_kettle(kit, _P.tint(color, _P.BLACK.lightened(0.05)))
		"bbq_gas":
			_bbq_gas(kit, _P.tint(color, Color(0.25, 0.26, 0.28)))
		"swing_set":
			_swing_set(kit, _P.tint(color, Color(0.3, 0.55, 0.32)))
		"trampoline":
			_trampoline(kit, _P.tint(color, Color(0.15, 0.32, 0.6)))
		"kiddie_pool":
			_kiddie_pool(kit, _P.tint(color, PLASTIC_BLUE))
		"flamingo":
			_flamingo(kit, _P.tint(color, PINK))
		"garden_bed_raised":
			_garden_bed(kit, _P.tint(color, _P.WOOD))
		"tomato_cage":
			_tomato_cage(kit)
		"kid_bike":
			_kid_bike(kit, _P.tint(color, Color(0.2, 0.5, 0.9)))
		"red_wagon":
			_red_wagon(kit, _P.tint(color, KID_RED))
		"patio_set":
			_patio_set(kit, _P.tint(color, Color(0.2, 0.5, 0.45)))
		"lawn_chair_plastic":
			_lawn_chair(kit, _P.tint(color, _P.WHITE))
		"adirondack":
			_adirondack(kit, _P.tint(color, Color(0.86, 0.5, 0.22)))
		"hammock":
			_hammock(kit, _P.tint(color, Color(0.86, 0.3, 0.26)))
		"porch_swing":
			_porch_swing(kit, _P.tint(color, _P.WHITE))
		"rocking_chair":
			_rocking_chair(kit, _P.tint(color, _P.WHITE))
		"birdbath":
			_birdbath(kit, _P.tint(color, _P.STONE.lightened(0.1)))
		"bird_feeder":
			_bird_feeder(kit, _P.tint(color, _P.WOOD))
		"doghouse":
			_doghouse(kit, _P.tint(color, KID_RED.darkened(0.1)))
		"clothesline":
			_clothesline(kit)
		"sprinkler":
			_sprinkler(kit, _P.tint(color, Color(0.98, 0.78, 0.15)))
		"hose_reel":
			_hose_reel(kit, _P.tint(color, Color(0.2, 0.58, 0.3)))
		"compost_bin":
			_compost_bin(kit, _P.tint(color, Color(0.16, 0.2, 0.17)))
		"wood_pile":
			_wood_pile(kit)
		"junk_pile":
			_junk_pile(kit)
		"tire_stack":
			_tire_stack(kit)
		"old_couch":
			_old_couch(kit, _P.tint(color, Color(0.55, 0.42, 0.26)), Vector3.ZERO, 0.0)
		"fridge":
			_fridge(kit, _P.tint(color, Color(0.9, 0.88, 0.8)), Vector3.ZERO, Basis.IDENTITY)
		"satellite_dish":
			_satellite_dish(kit, _P.tint(color, _P.WHITE))
		"propane_tank":
			_propane_tank(kit, _P.tint(color, _P.WHITE))
		"window_ac":
			_window_ac(kit, _P.tint(color, Color(0.88, 0.87, 0.83)))
		"playhouse":
			_playhouse(kit, _P.tint(color, Color(0.98, 0.86, 0.5)))
		"sandbox":
			_sandbox(kit, _P.tint(color, _P.WOOD))
		"pinwheel":
			_pinwheel(kit)
		"landscape_rocks":
			_landscape_rocks(kit, _P.tint(color, Color(0.66, 0.6, 0.52)))
		"solar_light":
			_solar_light(kit)
		"tire_planter":
			_tire_planter(kit, _P.tint(color, _P.WHITE))
		"staked_sapling_stakes":
			_sapling(kit)
		"fire_pit":
			_fire_pit(kit)
		"boxwood":
			_boxwood(kit, _P.tint(color, Color(0.2, 0.42, 0.2)), _P.dims(size, Vector3(1.2, 0.9, 1.0)))
		"privacy_fence_run":
			_privacy_run(kit, _P.tint(color, Color(0.72, 0.55, 0.38)), _P.dims(size, Vector3(RUN_LENGTH, 1.8, 0.0)))
		"chainlink_run":
			_chainlink_run(kit, _P.tint(color, _P.STEEL), _P.dims(size, Vector3(RUN_LENGTH, 1.2, 0.0)))
		"split_rail_run":
			_split_rail_run(kit, _P.tint(color, Color(0.6, 0.44, 0.3)), _P.dims(size, Vector3(RUN_LENGTH, 1.1, 0.0)))
		"vinyl_fence_run":
			_vinyl_run(kit, _P.tint(color, Color(0.97, 0.97, 0.96)), _P.dims(size, Vector3(RUN_LENGTH, 1.2, 0.0)))
		"picket_fence_run":
			_picket_run(kit, _P.tint(color, Color(0.96, 0.95, 0.91)), _P.dims(size, Vector3(RUN_LENGTH, 1.0, 0.0)), false)
		"weathered_picket_run":
			_picket_run(kit, _P.tint(color, _P.OLD_WOOD), _P.dims(size, Vector3(RUN_LENGTH, 1.0, 0.0)), true)
		"barn":
			_barn(kit, _P.tint(color, Color(0.68, 0.18, 0.14)))
		"silo":
			_silo(kit, _P.tint(color, Color(0.72, 0.74, 0.74)))
		"gnome":
			_gnome(kit, _P.tint(color, Color(0.85, 0.16, 0.12)))
		_:
			return false
	return true


# ---------------------------------------------------------------- cooking and sitting

static func _bbq_kettle(kit: _MeshKit, color: Color) -> void:
	for index: int in 3:
		var angle := TAU * float(index) / 3.0
		var foot := Vector3(cos(angle) * 0.32, 0.0, sin(angle) * 0.32)
		_P.bar(kit, foot, Vector3(cos(angle) * 0.16, 0.62, sin(angle) * 0.16), 0.016, _P.STEEL, 4)
	_P.wheel(kit, Vector3(0.32, 0.07, 0.0), 0.07, 0.04, _P.TIRE, _P.STEEL)
	_P.ball(kit, Vector3(0.0, 0.78, 0.0), Vector3(0.3, 0.22, 0.3), color, 1)
	_P.ring(kit, Vector3(0.0, 0.8, 0.0), 0.3, 0.018, _P.STEEL, 12, 4)
	_P.bar(kit, Vector3(-0.08, 1.02, 0.0), Vector3(0.08, 1.02, 0.0), 0.022, _P.BLACK.lightened(0.2), 4)
	_P.slab(kit, Vector3(0.0, 0.45, 0.0), Vector3(0.36, 0.02, 0.36), _P.STEEL.darkened(0.2))


static func _bbq_gas(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.42, 0.0), Vector3(0.8, 0.8, 0.5), color)
	_P.slab(kit, Vector3(0.0, 0.42, -0.255), Vector3(0.7, 0.66, 0.02), _P.STEEL)
	_P.soft(kit, Vector3(0.0, 0.95, 0.0), Vector3(0.84, 0.3, 0.52), _P.STEEL.lightened(0.05), 4.0, 1)
	_P.bar(kit, Vector3(-0.3, 1.0, -0.3), Vector3(0.3, 1.0, -0.3), 0.02, _P.CHROME, 4)
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 0.62, 0.82, 0.0), Vector3(0.42, 0.04, 0.44), _P.STEEL.darkened(0.1))
		_P.wheel(kit, Vector3(side * 0.3, 0.06, 0.2), 0.06, 0.04)
	for index: int in 4:
		_P.disc(kit, Vector3(-0.24 + float(index) * 0.16, 0.74, -0.27), 0.03, 0.02, _P.BLACK, 6)
	_P.post(kit, Vector3(0.0, 0.0, 0.0), 0.36, 0.13, _P.WHITE, 8)


## A metal A-frame swing set: two swings and a little slide.
static func _swing_set(kit: _MeshKit, color: Color) -> void:
	for x: float in [-1.4, 1.4]:
		for z: float in [-0.7, 0.7]:
			_P.bar(kit, Vector3(x, 0.0, z), Vector3(x, 2.1, 0.0), 0.04, color, 6)
	_P.bar(kit, Vector3(-1.5, 2.12, 0.0), Vector3(1.5, 2.12, 0.0), 0.05, color.darkened(0.1), 6)
	for x: float in [-0.7, 0.4]:
		for side: float in [-0.22, 0.22]:
			_P.bar(kit, Vector3(x + side, 2.1, 0.0), Vector3(x + side, 0.48, 0.0), 0.008, _P.STEEL, 3)
		_P.slab(kit, Vector3(x, 0.46, 0.0), Vector3(0.5, 0.04, 0.18), Color(0.96, 0.78, 0.15))
	_P.slab(kit, Vector3(1.0, 0.75, -1.15), Vector3(0.5, 0.04, 1.9), Color(0.96, 0.78, 0.15), Basis(Vector3.RIGHT, 0.55))
	for side: float in [-0.27, 0.27]:
		_P.slab(kit, Vector3(1.0 + side, 0.82, -1.15), Vector3(0.04, 0.1, 1.9), Color(0.96, 0.78, 0.15).darkened(0.15), Basis(Vector3.RIGHT, 0.55))


static func _trampoline(kit: _MeshKit, color: Color) -> void:
	var radius := 1.8
	for index: int in 6:
		var angle := TAU * float(index) / 6.0
		var at := Vector3(cos(angle), 0.0, sin(angle)) * radius
		_P.bar(kit, at, at + Vector3(0.0, 0.85, 0.0), 0.03, _P.STEEL, 4)
		_P.bar(kit, at + Vector3(0.0, 0.85, 0.0), at + Vector3(0.0, 2.6, 0.0), 0.025, _P.BLACK.lightened(0.2), 4)
	_P.ring(kit, Vector3(0.0, 0.85, 0.0), radius, 0.05, color, 16, 5)
	_P.ring(kit, Vector3(0.0, 2.6, 0.0), radius, 0.03, color, 16, 4)
	_P.disc(kit, Vector3(0.0, 0.83, 0.0), radius * 0.9, 0.02, _P.BLACK.lightened(0.05), 16)
	# The net: a see-through feel from thin rings between the tops.
	for y: float in [1.3, 1.8, 2.2]:
		_P.ring(kit, Vector3(0.0, y, 0.0), radius, 0.008, _P.BLACK.lightened(0.15), 16, 3)


static func _kiddie_pool(kit: _MeshKit, color: Color) -> void:
	_P.ring(kit, Vector3(0.0, 0.14, 0.0), 0.9, 0.13, color, 16, 6)
	_P.disc(kit, Vector3(0.0, 0.08, 0.0), 0.92, 0.04, color.lightened(0.2), 16)
	_P.disc(kit, Vector3(0.0, 0.14, 0.0), 0.82, 0.03, _P.WATER, 16)
	# The duck.
	_P.ball(kit, Vector3(0.3, 0.2, 0.1), Vector3(0.07, 0.05, 0.09), Color(0.98, 0.84, 0.2), 0)
	_P.ball(kit, Vector3(0.3, 0.27, 0.04), Vector3(0.04, 0.04, 0.04), Color(0.98, 0.84, 0.2), 0)
	_P.slab(kit, Vector3(0.3, 0.27, -0.005), Vector3(0.025, 0.012, 0.03), Color(0.95, 0.5, 0.1))


## A plastic lawn flamingo on two wire legs, head bowed (faces -Z).
static func _flamingo(kit: _MeshKit, color: Color) -> void:
	for side: float in [-0.03, 0.03]:
		_P.bar(kit, Vector3(side, 0.0, 0.0), Vector3(side * 0.5, 0.42, 0.02), 0.006, _P.STEEL.darkened(0.3), 3)
	_P.ball(kit, Vector3(0.0, 0.52, 0.04), Vector3(0.1, 0.11, 0.18), color, 1)
	_P.cone(kit, Vector3(0.0, 0.56, 0.2), 0.06, 0.12, color.darkened(0.08), 5)
	_P.path(kit, PackedVector3Array([Vector3(0.0, 0.56, -0.08), Vector3(0.0, 0.72, -0.12), Vector3(0.0, 0.84, -0.08), Vector3(0.0, 0.84, -0.0)]), 0.022, color, 5)
	_P.ball(kit, Vector3(0.0, 0.84, -0.04), Vector3(0.04, 0.035, 0.05), color, 0)
	_P.bar(kit, Vector3(0.0, 0.83, -0.08), Vector3(0.0, 0.78, -0.13), 0.012, _P.BLACK, 4)


static func _garden_bed(kit: _MeshKit, color: Color) -> void:
	var size := Vector2(2.2, 1.0)
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(0.0, 0.16, side * size.y * 0.5), Vector3(size.x, 0.32, 0.06), color)
		_P.slab(kit, Vector3(side * size.x * 0.5, 0.16, 0.0), Vector3(0.06, 0.32, size.y), color)
	_P.slab(kit, Vector3(0.0, 0.26, 0.0), Vector3(size.x - 0.08, 0.04, size.y - 0.08), _P.SOIL)
	for index: int in 6:
		var x := -0.85 + float(index) * 0.34
		_P.lump(kit, Vector3(x, 0.38, -0.2 + float(index % 2) * 0.35), Vector3(0.14, 0.12, 0.14), _P.LEAF.lightened(0.05 * float(index % 3)), index, 0, 0.3, 0.3)


static func _tomato_cage(kit: _MeshKit) -> void:
	for index: int in 3:
		var angle := TAU * float(index) / 3.0
		_P.bar(kit, Vector3(cos(angle) * 0.14, 0.0, sin(angle) * 0.14), Vector3(cos(angle) * 0.24, 1.0, sin(angle) * 0.24), 0.006, _P.STEEL, 3)
	for y: float in [0.35, 0.65, 0.95]:
		_P.ring(kit, Vector3(0.0, y, 0.0), 0.16 + y * 0.08, 0.006, _P.STEEL, 10, 3)
	_P.lump(kit, Vector3(0.0, 0.55, 0.0), Vector3(0.22, 0.38, 0.22), _P.LEAF, 3, 1, 0.3, 0.3)
	for index: int in 4:
		_P.ball(kit, Vector3(0.12 * cos(float(index) * 1.7), 0.4 + float(index) * 0.12, 0.12 * sin(float(index) * 1.7) - 0.1), Vector3(0.04, 0.04, 0.04), KID_RED, 0)


## A kid's bike left lying on the lawn (on its left side).
static func _kid_bike(kit: _MeshKit, color: Color) -> void:
	var lie := Basis(Vector3.FORWARD, PI * 0.5 - 0.15)
	var tilt := Transform3D(lie, Vector3(0.0, 0.06, 0.0))
	for z: float in [-0.42, 0.42]:
		_P.ring(kit, tilt * Vector3(0.0, 0.0, z), 0.25, 0.03, _P.TIRE, 14, 4, lie * Basis(Vector3.FORWARD, PI * 0.5))
	_P.bar(kit, tilt * Vector3(0.0, 0.0, -0.42), tilt * Vector3(0.0, 0.3, -0.1), 0.02, color, 4)
	_P.bar(kit, tilt * Vector3(0.0, 0.3, -0.1), tilt * Vector3(0.0, 0.33, 0.25), 0.02, color, 4)
	_P.bar(kit, tilt * Vector3(0.0, 0.0, 0.42), tilt * Vector3(0.0, 0.33, 0.25), 0.02, color, 4)
	_P.bar(kit, tilt * Vector3(0.0, 0.0, 0.42), tilt * Vector3(0.0, 0.0, 0.05), 0.02, color, 4)
	_P.bar(kit, tilt * Vector3(0.0, 0.0, 0.05), tilt * Vector3(0.0, 0.3, -0.1), 0.02, color, 4)
	_P.bar(kit, tilt * Vector3(-0.2, 0.42, -0.36), tilt * Vector3(0.2, 0.42, -0.36), 0.015, _P.CHROME, 4)
	_P.bar(kit, tilt * Vector3(0.0, 0.3, -0.36), tilt * Vector3(0.0, 0.42, -0.36), 0.015, _P.CHROME, 4)
	_P.soft(kit, tilt * Vector3(0.0, 0.4, 0.2), Vector3(0.1, 0.05, 0.2), _P.BLACK, 3.0, 0, lie)
	for side: float in [-0.2, 0.2]:
		_P.path(kit, PackedVector3Array([tilt * Vector3(side, 0.42, -0.36), tilt * Vector3(side * 1.2, 0.4, -0.38), tilt * Vector3(side * 1.4, 0.38, -0.38)]), 0.006, PINK, 3, 0.5, 0.8)


static func _red_wagon(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.3, 0.0), Vector3(0.5, 0.04, 0.9), color.darkened(0.1))
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 0.25, 0.4, 0.0), Vector3(0.03, 0.18, 0.9), color)
		_P.slab(kit, Vector3(0.0, 0.4, side * 0.45), Vector3(0.5, 0.18, 0.03), color)
		for z: float in [-0.32, 0.32]:
			_P.wheel(kit, Vector3(side * 0.27, 0.11, z), 0.11, 0.05, _P.BLACK, _P.WHITE)
	_P.bar(kit, Vector3(0.0, 0.2, -0.48), Vector3(0.0, 0.35, -1.05), 0.014, _P.BLACK, 4)
	_P.bar(kit, Vector3(-0.08, 0.35, -1.05), Vector3(0.08, 0.35, -1.05), 0.018, _P.BLACK, 4)


static func _patio_set(kit: _MeshKit, color: Color) -> void:
	_P.disc(kit, Vector3(0.0, 0.72, 0.0), 0.55, 0.04, _P.WHITE, 12)
	_P.post(kit, Vector3.ZERO, 0.7, 0.03, _P.DARK_STEEL, 4)
	_P.disc(kit, Vector3(0.0, 0.02, 0.0), 0.25, 0.04, _P.DARK_STEEL, 8)
	_P.post(kit, Vector3(0.0, 0.7, 0.0), 1.5, 0.02, _P.WHITE, 4)
	kit.cone(Vector3(0.0, 2.0, 0.0), 1.15, 0.4, color, 8, {"lumps": 0.0, "droop": 0.05})
	_P.ball(kit, Vector3(0.0, 2.42, 0.0), Vector3(0.04, 0.04, 0.04), _P.WHITE, 0)
	for index: int in 4:
		var angle := TAU * float(index) / 4.0 + PI * 0.25
		var turn := Basis(Vector3.UP, -angle - PI * 0.5)
		_chair(kit, Vector3(cos(angle), 0.0, sin(angle)) * 0.85, turn, _P.WHITE.darkened(0.05))


static func _chair(kit: _MeshKit, at: Vector3, turn: Basis, color: Color) -> void:
	for x: float in [-0.2, 0.2]:
		for z: float in [-0.2, 0.2]:
			_P.bar(kit, at + turn * Vector3(x, 0.0, z), at + turn * Vector3(x, 0.44, z), 0.018, color, 4)
	_P.slab(kit, at + turn * Vector3(0.0, 0.45, 0.0), Vector3(0.46, 0.04, 0.46), color, turn)
	_P.slab(kit, at + turn * Vector3(0.0, 0.72, 0.22), Vector3(0.46, 0.5, 0.04), color, turn * Basis(Vector3.RIGHT, -0.12))


## A white monobloc lawn chair.
static func _lawn_chair(kit: _MeshKit, color: Color) -> void:
	for x: float in [-0.24, 0.24]:
		for z: float in [-0.22, 0.22]:
			kit.tube(PackedVector3Array([Vector3(x * 1.1, 0.0, z * 1.1), Vector3(x, 0.4, z)]), PackedFloat32Array([0.03, 0.025]), color, 5, {"jitter": 0.0, "cap_start": true})
	_P.soft(kit, Vector3(0.0, 0.42, 0.0), Vector3(0.56, 0.05, 0.5), color, 4.0, 1)
	_P.soft(kit, Vector3(0.0, 0.72, 0.26), Vector3(0.54, 0.6, 0.05), color, 4.0, 1, Basis(Vector3.RIGHT, -0.2))
	for side: float in [-1.0, 1.0]:
		_P.soft(kit, Vector3(side * 0.28, 0.6, 0.02), Vector3(0.05, 0.05, 0.48), color, 3.0, 0)


static func _adirondack(kit: _MeshKit, color: Color) -> void:
	var lean := Basis(Vector3.RIGHT, -0.45)
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 0.3, 0.2, 0.0), Vector3(0.05, 0.4, 0.8), color.darkened(0.1))
		_P.slab(kit, Vector3(side * 0.36, 0.6, -0.05), Vector3(0.16, 0.03, 0.8), color)
		_P.slab(kit, Vector3(side * 0.36, 0.3, -0.38), Vector3(0.05, 0.6, 0.06), color.darkened(0.1))
	for index: int in 5:
		_P.slab(kit, Vector3(0.0, 0.36 - float(index) * 0.015, -0.3 + float(index) * 0.13), Vector3(0.6, 0.025, 0.1), color)
	for index: int in 5:
		var x := -0.24 + float(index) * 0.12
		_P.slab(kit, Vector3(x, 0.78, 0.38), Vector3(0.1, 0.9 + (0.08 if index == 2 else 0.0), 0.025), color, lean)


## A hammock on its own steel stand, the fabric sagging between (sways).
static func _hammock(kit: _MeshKit, color: Color) -> void:
	_P.bar(kit, Vector3(-1.9, 0.04, 0.0), Vector3(1.9, 0.04, 0.0), 0.04, _P.DARK_STEEL, 4)
	for side: float in [-1.0, 1.0]:
		_P.bar(kit, Vector3(side * 1.4, 0.04, 0.0), Vector3(side * 2.0, 1.1, 0.0), 0.035, _P.DARK_STEEL, 4)
		_P.bar(kit, Vector3(side * 1.6, 0.04, -0.3), Vector3(side * 1.6, 0.04, 0.3), 0.03, _P.DARK_STEEL, 4)
	var stripes: Array[Color] = [color, _P.WHITE, Color(0.2, 0.5, 0.7)]
	for index: int in 3:
		var z := -0.24 + float(index) * 0.24
		_P.path(kit, _P.sag(Vector3(-1.95, 1.05, z * 0.3), Vector3(1.95, 1.05, z * 0.3), 0.55, 8), 0.012, _P.WHITE, 3)
		var points := _P.sag(Vector3(-1.4, 0.75, z), Vector3(1.4, 0.75, z), 0.28, 6)
		for step: int in points.size() - 1:
			_P.slab(kit, (points[step] + points[step + 1]) * 0.5, Vector3(points[step].distance_to(points[step + 1]) + 0.02, 0.02, 0.24), stripes[index], Basis(Vector3.BACK, atan2(points[step + 1].y - points[step].y, points[step + 1].x - points[step].x)), 0.5)
	for side: float in [-1.0, 1.0]:
		_P.path(kit, PackedVector3Array([Vector3(side * 1.95, 1.05, 0.0), Vector3(side * 1.4, 0.75, 0.0)]), 0.01, _P.WHITE, 3)


## A porch swing hanging on chains from a beam 2.4 m up (place it under a porch roof).
static func _porch_swing(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.48, 0.0), Vector3(1.5, 0.06, 0.55), color)
	_P.slab(kit, Vector3(0.0, 0.78, 0.26), Vector3(1.5, 0.5, 0.05), color, Basis(Vector3.RIGHT, -0.15))
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 0.74, 0.66, 0.0), Vector3(0.06, 0.04, 0.55), color.darkened(0.1))
		_P.slab(kit, Vector3(side * 0.74, 0.57, -0.24), Vector3(0.05, 0.18, 0.05), color.darkened(0.1))
		for z: float in [-0.24, 0.26]:
			_P.bar(kit, Vector3(side * 0.72, 0.5, z), Vector3(side * 0.6, 2.4, 0.0), 0.008, _P.STEEL.darkened(0.2), 3)
	for index: int in 3:
		_P.soft(kit, Vector3(-0.5 + float(index) * 0.5, 0.6, 0.12), Vector3(0.4, 0.3, 0.12), [Color(0.86, 0.36, 0.3), Color(0.95, 0.85, 0.5), Color(0.4, 0.6, 0.72)][index], 3.0, 0)


static func _rocking_chair(kit: _MeshKit, color: Color) -> void:
	for side: float in [-0.24, 0.24]:
		var rocker := PackedVector3Array()
		for step: int in 7:
			var t := float(step) / 6.0
			rocker.append(Vector3(side, 0.03 + pow((t - 0.5) * 2.0, 2.0) * 0.08, lerpf(-0.42, 0.42, t)))
		_P.path(kit, rocker, 0.025, color, 4)
		for z: float in [-0.2, 0.2]:
			_P.bar(kit, Vector3(side, 0.04, z), Vector3(side, 0.45, z * 0.9), 0.02, color, 4)
		_P.bar(kit, Vector3(side, 0.45, 0.2), Vector3(side * 0.95, 1.05, 0.32), 0.02, color, 4)
		_P.slab(kit, Vector3(side * 1.1, 0.66, -0.02), Vector3(0.06, 0.03, 0.42), color)
	_P.slab(kit, Vector3(0.0, 0.46, 0.0), Vector3(0.5, 0.04, 0.44), color)
	for index: int in 4:
		_P.slab(kit, Vector3(-0.15 + float(index) * 0.1, 0.78, 0.27), Vector3(0.04, 0.6, 0.02), color, Basis(Vector3.RIGHT, -0.2))
	_P.slab(kit, Vector3(0.0, 1.06, 0.33), Vector3(0.5, 0.06, 0.03), color, Basis(Vector3.RIGHT, -0.2))


static func _birdbath(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.05, 0.0), Vector3(0.36, 0.1, 0.36), color.darkened(0.08))
	kit.tube(PackedVector3Array([Vector3(0.0, 0.1, 0.0), Vector3(0.0, 0.4, 0.0), Vector3(0.0, 0.66, 0.0)]), PackedFloat32Array([0.1, 0.06, 0.1]), color, 8, {"jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0.0, 0.66, 0.0), Vector3(0.0, 0.78, 0.0)]), PackedFloat32Array([0.14, 0.34]), color, 12, {"jitter": 0.0, "cap": false, "cap_start": true})
	_P.disc(kit, Vector3(0.0, 0.76, 0.0), 0.31, 0.02, _P.WATER, 12)
	# A sparrow on the rim.
	_P.ball(kit, Vector3(0.3, 0.81, 0.05), Vector3(0.04, 0.035, 0.06), Color(0.5, 0.38, 0.26), 0)
	_P.ball(kit, Vector3(0.3, 0.855, 0.0), Vector3(0.025, 0.025, 0.025), Color(0.5, 0.38, 0.26), 0)


static func _bird_feeder(kit: _MeshKit, color: Color) -> void:
	_P.post(kit, Vector3.ZERO, 1.6, 0.03, _P.DARK_STEEL, 4)
	_P.slab(kit, Vector3(0.0, 1.62, 0.0), Vector3(0.3, 0.03, 0.3), color)
	_P.slab(kit, Vector3(0.0, 1.76, 0.0), Vector3(0.18, 0.26, 0.18), Color(0.8, 0.86, 0.9).darkened(0.1))
	_P.slab(kit, Vector3(0.0, 1.7, 0.0), Vector3(0.16, 0.12, 0.16), Color(0.72, 0.6, 0.38))
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 0.11, 1.95, 0.0), Vector3(0.24, 0.025, 0.32), color.darkened(0.1), Basis(Vector3.BACK, -side * 0.6))


## A doghouse with a dark doorway and a bowl. (The "BEWARE OF DOG" sign is a
## set-piece label; the dog is about the size of a loaf of bread.)
static func _doghouse(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.35, 0.0), Vector3(0.9, 0.7, 1.0), color)
	_P.slab(kit, Vector3(0.0, 0.28, -0.505), Vector3(0.36, 0.44, 0.02), _P.BLACK)
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 0.27, 0.9, 0.0), Vector3(0.62, 0.05, 1.12), Color(0.36, 0.3, 0.28), Basis(Vector3.BACK, -side * 0.62))
	_P.poly(kit, [Vector3(-0.45, 0.7, -0.5), Vector3(0.45, 0.7, -0.5), Vector3(0.0, 1.05, -0.5)], Vector3(0.0, 0.8, 0.0), color)
	_P.poly(kit, [Vector3(-0.45, 0.7, 0.5), Vector3(0.45, 0.7, 0.5), Vector3(0.0, 1.05, 0.5)], Vector3(0.0, 0.8, 0.0), color)
	_P.disc(kit, Vector3(0.45, 0.04, -0.75), 0.1, 0.06, Color(0.2, 0.4, 0.75), 8)


## A clothesline: two T-posts, three lines, and laundry that sways.
static func _clothesline(kit: _MeshKit) -> void:
	var span := 4.0
	for x: float in [-span * 0.5, span * 0.5]:
		_P.post(kit, Vector3(x, 0.0, 0.0), 1.9, 0.035, _P.STEEL, 4)
		_P.bar(kit, Vector3(x, 1.85, -0.45), Vector3(x, 1.85, 0.45), 0.025, _P.STEEL, 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var colors: Array[Color] = [_P.WHITE, Color(0.4, 0.6, 0.86), Color(0.9, 0.4, 0.4), Color(0.96, 0.84, 0.4), Color(0.5, 0.75, 0.5), PINK]
	for z: float in [-0.4, 0.0, 0.4]:
		var line := _P.sag(Vector3(-span * 0.5, 1.84, z), Vector3(span * 0.5, 1.84, z), 0.12, 6)
		_P.path(kit, line, 0.006, _P.WHITE, 3)
		if z == 0.0:
			continue
		var x := -1.5
		while x < 1.5:
			var width := rng.randf_range(0.35, 0.7)
			var height := rng.randf_range(0.35, 0.8)
			var t := (x + width * 0.5 + span * 0.5) / span
			var top := 1.84 - 0.12 * 4.0 * t * (1.0 - t)
			_P.card(kit, Vector3(x + width * 0.5, top - height, z), width, height, colors[rng.randi() % colors.size()], Basis.IDENTITY, 0.9, 0.15)
			x += width + rng.randf_range(0.12, 0.35)


static func _sprinkler(kit: _MeshKit, color: Color) -> void:
	_P.disc(kit, Vector3(0.0, 0.02, 0.0), 0.12, 0.04, Color(0.2, 0.58, 0.3), 8)
	_P.post(kit, Vector3(0.0, 0.04, 0.0), 0.14, 0.025, color, 6)
	_P.bar(kit, Vector3(-0.16, 0.2, 0.0), Vector3(0.16, 0.2, 0.0), 0.015, color, 4)
	_P.path(kit, PackedVector3Array([Vector3(0.0, 0.03, 0.1), Vector3(0.1, 0.02, 0.6), Vector3(-0.2, 0.02, 1.1)]), 0.018, Color(0.2, 0.58, 0.3), 4)


static func _hose_reel(kit: _MeshKit, color: Color) -> void:
	for side: float in [-0.25, 0.25]:
		_P.disc(kit, Vector3(side, 0.42, 0.0), 0.32, 0.02, Color(0.35, 0.35, 0.37), 10)
	for index: int in 4:
		_P.ring(kit, Vector3(-0.15 + float(index) * 0.1, 0.42, 0.0), 0.2, 0.03, color.darkened(0.06 * float(index % 2)), 12, 4, Basis(Vector3.BACK, PI * 0.5))
	for side: float in [-1.0, 1.0]:
		_P.bar(kit, Vector3(side * 0.28, 0.0, 0.25), Vector3(side * 0.28, 0.85, 0.25), 0.02, _P.DARK_STEEL, 4)
	_P.bar(kit, Vector3(-0.28, 0.85, 0.25), Vector3(0.28, 0.85, 0.25), 0.02, _P.DARK_STEEL, 4)
	_P.wheel(kit, Vector3(0.0, 0.1, -0.2), 0.1, 0.62, _P.TIRE, _P.DARK_STEEL)


static func _compost_bin(kit: _MeshKit, color: Color) -> void:
	kit.tube(PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.9, 0.0)]), PackedFloat32Array([0.42, 0.34]), color, 8, {"jitter": 0.0, "cap_start": true})
	_P.cone(kit, Vector3(0.0, 0.9, 0.0), 0.38, 0.12, color.lightened(0.05), 8)
	_P.slab(kit, Vector3(0.0, 0.2, -0.4), Vector3(0.3, 0.2, 0.04), color.darkened(0.2))


static func _wood_pile(kit: _MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for row: int in 4:
		for index: int in 6 - row:
			var x := -0.55 + float(index) * 0.22 + float(row) * 0.11
			var y := 0.1 + float(row) * 0.18
			_P.bar(kit, Vector3(x, y, -0.4), Vector3(x, y, 0.4), 0.09, _P.vary(_P.WOOD.darkened(0.15), rng, 0.15), 6)
	for x: float in [-0.7, 0.7]:
		_P.slab(kit, Vector3(x, 0.4, 0.0), Vector3(0.06, 0.8, 0.06), _P.WOOD.darkened(0.3))


## Dandelion Acres' junk pile: a stack of tires, an old fridge on its back, a
## couch, a bike wheel, and a traffic cone nobody remembers taking.
static func _junk_pile(kit: _MeshKit) -> void:
	for index: int in 3:
		_P.ring(kit, Vector3(-0.9, 0.12 + float(index) * 0.22, 0.4), 0.3, 0.11, _P.TIRE, 10, 5)
	_P.ring(kit, Vector3(-0.5, 0.2, -0.3), 0.3, 0.11, _P.TIRE, 10, 5, Basis(Vector3.BACK, 1.2))
	_fridge(kit, Color(0.86, 0.84, 0.74), Vector3(0.6, 0.0, 0.2), Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, 0.3))
	_old_couch(kit, Color(0.5, 0.56, 0.36), Vector3(-0.1, 0.0, -0.9), 0.4)
	_P.ring(kit, Vector3(0.5, 0.95, 0.15), 0.25, 0.02, _P.STEEL, 10, 3, Basis(Vector3.BACK, 0.4))
	kit.tube(PackedVector3Array([Vector3(1.2, 0.0, -0.6), Vector3(1.2, 0.5, -0.6)]), PackedFloat32Array([0.14, 0.03]), Color(0.96, 0.42, 0.1), 6, {"jitter": 0.0, "cap_start": true})
	_P.slab(kit, Vector3(-0.2, 0.06, 0.6), Vector3(0.8, 0.12, 0.6), _P.OLD_WOOD, Basis(Vector3.UP, 0.5))


static func _tire_stack(kit: _MeshKit) -> void:
	for index: int in 4:
		_P.ring(kit, Vector3(0.0 + (0.04 if index % 2 == 0 else -0.03), 0.12 + float(index) * 0.22, 0.0), 0.3, 0.11, _P.TIRE, 10, 5)


static func _old_couch(kit: _MeshKit, color: Color, at: Vector3, yaw: float) -> void:
	var turn := Basis(Vector3.UP, yaw)
	_P.soft(kit, at + turn * Vector3(0.0, 0.25, 0.0), Vector3(1.9, 0.4, 0.85), color, 4.0, 1, turn)
	_P.soft(kit, at + turn * Vector3(0.0, 0.62, 0.34), Vector3(1.9, 0.6, 0.22), color.darkened(0.06), 4.0, 1, turn)
	for side: float in [-1.0, 1.0]:
		_P.soft(kit, at + turn * Vector3(side * 0.9, 0.5, 0.0), Vector3(0.22, 0.42, 0.85), color.darkened(0.04), 4.0, 1, turn)
	for index: int in 2:
		_P.soft(kit, at + turn * Vector3(-0.4 + float(index) * 0.8, 0.5, -0.05), Vector3(0.76, 0.14, 0.7), color.lightened(0.05) if index == 0 else color.darkened(0.12), 4.0, 1, turn * Basis(Vector3.FORWARD, 0.08 * float(index)))


static func _fridge(kit: _MeshKit, color: Color, at: Vector3, turn: Basis) -> void:
	_P.soft(kit, at + turn * Vector3(0.0, 0.85, 0.0), Vector3(0.75, 1.7, 0.7), color, 6.0, 1, turn)
	_P.slab(kit, at + turn * Vector3(0.0, 1.15, -0.355), Vector3(0.7, 0.02, 0.02), color.darkened(0.2), turn)
	_P.slab(kit, at + turn * Vector3(0.3, 1.0, -0.37), Vector3(0.04, 0.4, 0.04), _P.CHROME, turn)
	_P.slab(kit, at + turn * Vector3(0.3, 1.45, -0.37), Vector3(0.04, 0.2, 0.04), _P.CHROME, turn)


static func _satellite_dish(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.03, 0.0), Vector3(0.3, 0.06, 0.3), _P.DARK_STEEL)
	_P.post(kit, Vector3(0.0, 0.06, 0.0), 0.5, 0.03, _P.DARK_STEEL, 4)
	var aim := Basis(Vector3.RIGHT, -0.9)
	kit.tube(PackedVector3Array([Vector3(0.0, 0.62, 0.0), Vector3(0.0, 0.62, 0.0) + aim * Vector3(0.0, 0.12, 0.0)]), PackedFloat32Array([0.05, 0.42]), color, 12, {"jitter": 0.0, "cap": true, "cap_start": true})
	_P.bar(kit, Vector3(0.0, 0.62, 0.0) + aim * Vector3(0.0, 0.1, 0.0), Vector3(0.0, 0.62, 0.0) + aim * Vector3(0.0, 0.55, 0.0), 0.012, _P.DARK_STEEL, 3)
	_P.slab(kit, Vector3(0.0, 0.62, 0.0) + aim * Vector3(0.0, 0.56, 0.0), Vector3(0.06, 0.06, 0.08), _P.DARK_STEEL, aim)


## A white propane tank on legs, a dome over the valve.
static func _propane_tank(kit: _MeshKit, color: Color) -> void:
	for x: float in [-0.5, 0.5]:
		_P.slab(kit, Vector3(x, 0.12, 0.0), Vector3(0.12, 0.24, 0.5), _P.DARK_STEEL)
	kit.tube(PackedVector3Array([Vector3(-0.95, 0.55, 0.0), Vector3(-0.75, 0.55, 0.0), Vector3(0.75, 0.55, 0.0), Vector3(0.95, 0.55, 0.0)]), PackedFloat32Array([0.15, 0.36, 0.36, 0.15]), color, 12, {"jitter": 0.0, "cap": true, "cap_start": true})
	kit.tube(PackedVector3Array([Vector3(0.0, 0.88, 0.0), Vector3(0.0, 1.02, 0.0)]), PackedFloat32Array([0.15, 0.12]), color.darkened(0.05), 8, {"jitter": 0.0})


## A window AC unit, its grille facing -Z (stick it out of a wall).
static func _window_ac(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.0, -0.2), Vector3(0.66, 0.42, 0.52), color)
	_P.slab(kit, Vector3(0.0, 0.0, -0.465), Vector3(0.6, 0.36, 0.02), color.darkened(0.15))
	for index: int in 6:
		_P.slab(kit, Vector3(0.0, -0.15 + float(index) * 0.06, -0.48), Vector3(0.58, 0.015, 0.02), color.darkened(0.35))
	_P.slab(kit, Vector3(0.0, -0.26, -0.3), Vector3(0.7, 0.06, 0.32), _P.DARK_STEEL)


static func _playhouse(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.65, 0.0), Vector3(1.4, 1.3, 1.2), color)
	_P.slab(kit, Vector3(0.0, 0.45, -0.605), Vector3(0.5, 0.9, 0.02), Color(0.25, 0.5, 0.8))
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 0.42, 0.85, -0.605), Vector3(0.3, 0.3, 0.02), _P.GLASS)
		_P.slab(kit, Vector3(side * 0.38, 1.55, 0.0), Vector3(0.95, 0.06, 1.4), KID_RED, Basis(Vector3.BACK, -side * 0.7))
	_P.poly(kit, [Vector3(-0.7, 1.3, -0.6), Vector3(0.7, 1.3, -0.6), Vector3(0.0, 1.9, -0.6)], Vector3(0.0, 1.5, 0.0), color)
	_P.poly(kit, [Vector3(-0.7, 1.3, 0.6), Vector3(0.7, 1.3, 0.6), Vector3(0.0, 1.9, 0.6)], Vector3(0.0, 1.5, 0.0), color)


static func _sandbox(kit: _MeshKit, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(0.0, 0.12, side * 0.8), Vector3(1.7, 0.24, 0.1), color)
		_P.slab(kit, Vector3(side * 0.8, 0.12, 0.0), Vector3(0.1, 0.24, 1.7), color)
	_P.slab(kit, Vector3(0.0, 0.14, 0.0), Vector3(1.5, 0.06, 1.5), Color(0.92, 0.84, 0.62))
	_P.lump(kit, Vector3(0.3, 0.2, 0.2), Vector3(0.25, 0.1, 0.25), Color(0.9, 0.82, 0.6), 2, 0, 0.3)
	kit.tube(PackedVector3Array([Vector3(-0.35, 0.17, -0.3), Vector3(-0.35, 0.33, -0.3)]), PackedFloat32Array([0.07, 0.1]), KID_RED, 8, {"jitter": 0.0, "cap_start": true, "cap": false})


static func _pinwheel(kit: _MeshKit) -> void:
	_P.post(kit, Vector3.ZERO, 0.75, 0.01, Color(0.2, 0.55, 0.3), 4)
	var colors: Array[Color] = [KID_RED, Color(0.98, 0.84, 0.2), Color(0.25, 0.55, 0.9), Color(0.4, 0.75, 0.4)]
	for index: int in 4:
		var turn := Basis(Vector3.FORWARD, float(index) * PI * 0.5 + 0.3)
		_P.card(kit, Vector3(0.0, 0.78, -0.02), 0.08, 0.16, colors[index], turn, 0.8, 1.0)


static func _landscape_rocks(kit: _MeshKit, color: Color) -> void:
	_P.lump(kit, Vector3(0.0, 0.18, 0.0), Vector3(0.45, 0.3, 0.35), color, 1, 1, 0.3)
	_P.lump(kit, Vector3(0.55, 0.1, 0.2), Vector3(0.25, 0.16, 0.22), color.darkened(0.08), 2, 1, 0.3)
	_P.lump(kit, Vector3(-0.45, 0.08, 0.3), Vector3(0.2, 0.12, 0.18), color.lightened(0.06), 3, 0, 0.3)
	_P.slab(kit, Vector3(0.1, 0.01, 0.1), Vector3(1.8, 0.02, 1.2), Color(0.42, 0.28, 0.2))


static func _solar_light(kit: _MeshKit) -> void:
	_P.post(kit, Vector3.ZERO, 0.32, 0.012, _P.BLACK, 4)
	_P.slab(kit, Vector3(0.0, 0.36, 0.0), Vector3(0.1, 0.08, 0.1), Color(0.86, 0.86, 0.8))
	_P.slab(kit, Vector3(0.0, 0.41, 0.0), Vector3(0.12, 0.02, 0.12), Color(0.15, 0.2, 0.35))


static func _tire_planter(kit: _MeshKit, color: Color) -> void:
	_P.ring(kit, Vector3(0.0, 0.11, 0.0), 0.32, 0.11, color, 10, 5)
	_P.disc(kit, Vector3(0.0, 0.16, 0.0), 0.3, 0.04, _P.SOIL, 10)
	var colors: Array[Color] = [Color(0.95, 0.4, 0.5), Color(0.98, 0.84, 0.2), Color(0.95, 0.55, 0.15)]
	for index: int in 6:
		var angle := TAU * float(index) / 6.0
		var at := Vector3(cos(angle) * 0.16, 0.24, sin(angle) * 0.16)
		_P.lump(kit, at, Vector3(0.07, 0.08, 0.07), _P.LEAF, index, 0, 0.2, 0.3)
		_P.ball(kit, at + Vector3(0.0, 0.08, 0.0), Vector3(0.04, 0.03, 0.04), colors[index % 3], 0, 0.4)


## A new street tree's stakes and ties (the sapling itself is a small tree
## planted next to it; this adds a skinny trunk so it reads on its own).
static func _sapling(kit: _MeshKit) -> void:
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 0.35, 0.8, 0.0), Vector3(0.05, 1.6, 0.05), _P.WOOD.lightened(0.1))
		_P.bar(kit, Vector3(side * 0.35, 1.2, 0.0), Vector3(0.0, 1.2, 0.0), 0.015, Color(0.2, 0.45, 0.25), 3)
	kit.tube(PackedVector3Array([Vector3.ZERO, Vector3(0.0, 2.0, 0.0)]), PackedFloat32Array([0.035, 0.02]), Color(0.42, 0.32, 0.24), 5, {"jitter": 0.0})
	_P.disc(kit, Vector3(0.0, 0.02, 0.0), 0.45, 0.04, Color(0.42, 0.26, 0.16), 10)


static func _fire_pit(kit: _MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for index: int in 10:
		var angle := TAU * float(index) / 10.0
		_P.lump(kit, Vector3(cos(angle) * 0.55, 0.14, sin(angle) * 0.55), Vector3(0.16, 0.14, 0.13), _P.vary(_P.STONE, rng, 0.15), index, 0, 0.25)
	_P.disc(kit, Vector3(0.0, 0.04, 0.0), 0.45, 0.04, Color(0.22, 0.2, 0.2), 10)
	for index: int in 3:
		var angle := TAU * float(index) / 3.0
		_P.bar(kit, Vector3(cos(angle) * 0.3, 0.06, sin(angle) * 0.3), Vector3(0.0, 0.3, 0.0), 0.05, _P.WOOD.darkened(0.3), 5)


## A clipped boxwood: a soft box filling size, lighter on top.
static func _boxwood(kit: _MeshKit, color: Color, size: Vector3) -> void:
	var count := maxi(1, int(round(maxf(size.x, size.z) / 1.4)))
	var along_x := size.x >= size.z
	for index: int in count:
		var t := (float(index) + 0.5) / float(count) - 0.5
		var at := Vector3(t * size.x, size.y * 0.5, 0.0) if along_x else Vector3(0.0, size.y * 0.5, t * size.z)
		var piece := Vector3(size.x / float(count) + 0.08, size.y, size.z) if along_x else Vector3(size.x, size.y, size.z / float(count) + 0.08)
		_P.soft(kit, at, piece, color.lightened(0.03 * float(index % 2)), 3.5, 2)
	kit.grade(0, 0.0, size.y, 0.7, 1.12)


# ---------------------------------------------------------------- fence runs (along local x, centered)

static func _posts(length: float, spacing: float) -> PackedFloat32Array:
	var count := maxi(1, int(round(length / spacing)))
	var xs := PackedFloat32Array()
	for index: int in count + 1:
		xs.append(-length * 0.5 + float(index) * length / float(count))
	return xs


static func _privacy_run(kit: _MeshKit, color: Color, size: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(size.x * 10.0)
	var boards := int(size.x / 0.15)
	for index: int in boards:
		var x := -size.x * 0.5 + (float(index) + 0.5) * size.x / float(boards)
		_P.slab(kit, Vector3(x, size.y * 0.5, 0.0), Vector3(0.14, size.y, 0.02), _P.vary(color, rng, 0.07))
	for y: float in [0.3, size.y - 0.3]:
		_P.slab(kit, Vector3(0.0, y, 0.035), Vector3(size.x, 0.09, 0.04), color.darkened(0.18))
	for x: float in _posts(size.x, 2.4):
		_P.slab(kit, Vector3(x, size.y * 0.52, 0.06), Vector3(0.1, size.y * 1.04, 0.1), color.darkened(0.25))


static func _chainlink_run(kit: _MeshKit, color: Color, size: Vector3) -> void:
	for x: float in _posts(size.x, 3.0):
		_P.post(kit, Vector3(x, 0.0, 0.0), size.y + 0.05, 0.03, color, 5)
	_P.bar(kit, Vector3(-size.x * 0.5, size.y, 0.0), Vector3(size.x * 0.5, size.y, 0.0), 0.02, color, 4)
	# The mesh: a diagonal lattice of thin wires, coarse enough to stay cheap.
	var step := 0.3
	var x := -size.x * 0.5
	while x < size.x * 0.5:
		var top := minf(x + size.y, size.x * 0.5)
		_P.bar(kit, Vector3(x, 0.03, 0.0), Vector3(top, 0.03 + (top - x), 0.0), 0.004, color.darkened(0.1), 3)
		var back := maxf(x + step - size.y, -size.x * 0.5)
		_P.bar(kit, Vector3(x + step, 0.03, 0.0), Vector3(back, 0.03 + (x + step - back), 0.0), 0.004, color.darkened(0.1), 3)
		x += step


static func _split_rail_run(kit: _MeshKit, color: Color, size: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for x: float in _posts(size.x, 3.0):
		_P.slab(kit, Vector3(x, size.y * 0.5, 0.0), Vector3(0.14, size.y, 0.14), _P.vary(color.darkened(0.12), rng, 0.08))
	for y: float in [size.y * 0.42, size.y * 0.85]:
		_P.bar(kit, Vector3(-size.x * 0.5, y, 0.0), Vector3(size.x * 0.5, y + rng.randf_range(-0.03, 0.03), 0.0), 0.055, _P.vary(color, rng, 0.08), 5)


static func _vinyl_run(kit: _MeshKit, color: Color, size: Vector3) -> void:
	for x: float in _posts(size.x, 2.4):
		_P.slab(kit, Vector3(x, size.y * 0.52, 0.0), Vector3(0.12, size.y * 1.04, 0.12), color)
		_P.slab(kit, Vector3(x, size.y * 1.06, 0.0), Vector3(0.15, 0.05, 0.15), color)
	_P.slab(kit, Vector3(0.0, size.y * 0.92, 0.0), Vector3(size.x, 0.08, 0.06), color)
	_P.slab(kit, Vector3(0.0, size.y * 0.2, 0.0), Vector3(size.x, 0.08, 0.06), color)
	var pickets := int(size.x / 0.14)
	for index: int in pickets:
		var x := -size.x * 0.5 + (float(index) + 0.5) * size.x / float(pickets)
		_P.slab(kit, Vector3(x, size.y * 0.52, 0.0), Vector3(0.05, size.y * 0.72, 0.04), color.darkened(0.02))


static func _picket_run(kit: _MeshKit, color: Color, size: Vector3, weathered: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(size.x * 10.0) + (7 if weathered else 0)
	var pickets := int(size.x / 0.16)
	for index: int in pickets:
		# Dandelion Acres' fence is missing one every few.
		if weathered and index % 5 == 3:
			continue
		var x := -size.x * 0.5 + (float(index) + 0.5) * size.x / float(pickets)
		var tint := _P.vary(color, rng, 0.14 if weathered else 0.03)
		var height := size.y * (rng.randf_range(0.88, 1.02) if weathered else 1.0)
		var lean := Basis(Vector3.BACK, rng.randf_range(-0.07, 0.07)) if weathered else Basis.IDENTITY
		_P.slab(kit, Vector3(x, height * 0.45, 0.0), Vector3(0.09, height * 0.9, 0.02), tint, lean)
		_P.poly(kit, [Vector3(x - 0.045, height * 0.9, -0.01), Vector3(x + 0.045, height * 0.9, -0.01), Vector3(x, height, -0.01)], Vector3(x, height * 0.9, 0.5), tint)
	for y: float in [size.y * 0.25, size.y * 0.7]:
		_P.slab(kit, Vector3(0.0, y, 0.025), Vector3(size.x, 0.06, 0.03), color.darkened(0.15))
	for x: float in _posts(size.x, 2.4):
		_P.slab(kit, Vector3(x, size.y * 0.5, 0.04), Vector3(0.09, size.y, 0.09), color.darkened(0.12))


# ---------------------------------------------------------------- country (countryside, art chunk 8)

static func _barn(kit: _MeshKit, color: Color) -> void:
	var w := 9.0
	var d := 12.0
	var wall := 5.0
	_P.slab(kit, Vector3(0.0, wall * 0.5, 0.0), Vector3(w, wall, d), color)
	# A gambrel roof: two pitches a side.
	var roof := Color(0.32, 0.32, 0.34)
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 3.72, wall + 1.22, 0.0), Vector3(2.95, 0.14, d + 0.6), roof, Basis(Vector3.BACK, -side * 1.0))
		_P.slab(kit, Vector3(side * 1.47, wall + 2.88, 0.0), Vector3(3.15, 0.14, d + 0.6), roof, Basis(Vector3.BACK, -side * 0.3))
	for z: float in [-d * 0.5, d * 0.5]:
		_P.poly(kit, [Vector3(-w * 0.5, wall, z), Vector3(-2.95, wall + 2.4, z), Vector3(0.0, wall + 3.3, z), Vector3(2.95, wall + 2.4, z), Vector3(w * 0.5, wall, z)], Vector3(0.0, wall + 1.0, 0.0), color)
	# Big doors with the white X, a hay loft door.
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 1.1, 1.8, -d * 0.5 - 0.02), Vector3(2.1, 3.6, 0.05), color.darkened(0.12))
		for turn: float in [-0.97, 0.97]:
			_P.slab(kit, Vector3(side * 1.1, 1.8, -d * 0.5 - 0.06), Vector3(0.14, 4.0, 0.03), _P.WHITE, Basis(Vector3.FORWARD, turn * 0.52))
	_P.slab(kit, Vector3(0.0, 6.4, -d * 0.5 - 0.02), Vector3(1.6, 1.4, 0.05), _P.WHITE)
	_P.slab(kit, Vector3(0.0, 6.4, -d * 0.5 - 0.04), Vector3(1.3, 1.1, 0.05), color.darkened(0.25))


static func _silo(kit: _MeshKit, color: Color) -> void:
	_P.post(kit, Vector3.ZERO, 12.0, 2.2, color, 14)
	for index: int in 5:
		_P.ring(kit, Vector3(0.0, 2.0 + float(index) * 2.2, 0.0), 2.22, 0.05, color.darkened(0.15), 14, 3)
	_P.ball(kit, Vector3(0.0, 12.0, 0.0), Vector3(2.25, 1.4, 2.25), Color(0.8, 0.82, 0.84), 1)
	_P.slab(kit, Vector3(0.0, 6.0, -2.22), Vector3(0.4, 11.0, 0.1), _P.DARK_STEEL)


## A garden gnome for the blocks (props/yard_models.gd's is the close-up one):
## pointy hat in color, white beard, round nose, blue coat, about 450 triangles.
static func _gnome(kit: _MeshKit, color: Color) -> void:
	var coat := Color(0.25, 0.42, 0.78)
	for side: float in [-0.07, 0.07]:
		_P.ball(kit, Vector3(side, 0.04, -0.03), Vector3(0.07, 0.04, 0.1), Color(0.3, 0.2, 0.15), 0)
	_P.ball(kit, Vector3(0.0, 0.2, 0.0), Vector3(0.17, 0.17, 0.15), coat, 1)
	_P.post(kit, Vector3(0.0, 0.15, 0.0), 0.04, 0.17, Color(0.25, 0.2, 0.15), 10)
	_P.ball(kit, Vector3(0.0, 0.43, 0.0), Vector3(0.13, 0.12, 0.12), Color(0.96, 0.8, 0.68), 1)
	_P.lump(kit, Vector3(0.0, 0.33, -0.07), Vector3(0.13, 0.14, 0.08), Color(0.97, 0.97, 0.95), 2, 1, 0.2)
	_P.ball(kit, Vector3(0.0, 0.42, -0.125), Vector3(0.04, 0.035, 0.035), Color(0.95, 0.55, 0.5), 0)
	for side: float in [-1.0, 1.0]:
		_P.ball(kit, Vector3(side * 0.05, 0.47, -0.11), Vector3(0.016, 0.02, 0.01), _P.BLACK, 0)
		_P.ball(kit, Vector3(side * 0.16, 0.24, -0.02), Vector3(0.05, 0.08, 0.05), coat, 0)
	_P.cone(kit, Vector3(0.0, 0.5, 0.01), 0.15, 0.36, color, 10)
