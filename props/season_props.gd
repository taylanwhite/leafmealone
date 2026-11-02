extends RefCounted

## Authority: local, cosmetic. What each season adds to the yards (docs/GAME.md,
## "the seasons' looks"): autumn pumpkins, mums, hay and scarecrows; winter
## snowmen (and the block's one sagging inflatable), wreaths, snow piles,
## snowbanks, icicles and string lights; spring tulips and petals; summer beach
## umbrellas, pool floats and the lemonade stand. Built with props/mesh_kit.gd
## through props/prop_parts.gd and registered by props/prop_catalog.gd (ask it,
## not this file). Glowing faces, bulbs, and the stand's sign are added by
## PropCatalog.place(). Every mesh stays under Constants.ART_PROP_MAX_TRIANGLES.
##
## Frame: 1 m units, Y up, origin at the ground center, front facing -Z.
## Sized kinds (SIZED): runs are size.x long (snowbank_run, icicle_run,
## string_lights: 6 m by default), tulip_bed is size.x by size.z.
## icicle_run and string_lights hang from their origin (an eave line) downward.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _P = preload("res://props/prop_parts.gd")

const KINDS: Array[String] = [
	"pumpkin_small", "pumpkin", "pumpkin_big", "jack_o_lantern", "hay_bale", "scarecrow", "mums_pot",
	"snowman", "snowman_inflatable", "wreath", "snow_pile", "snowbank_run", "sled", "icicle_run",
	"string_lights", "holiday_tree_lot", "tulip_bed", "petal_scatter", "beach_umbrella", "pool_float",
	"lemonade_stand",
]
const SIZED: Array[String] = ["snowbank_run", "icicle_run", "string_lights", "tulip_bed"]
const RUN_LENGTH := 6.0

const PUMPKIN := Color(0.95, 0.5, 0.12)
const STEM := Color(0.36, 0.42, 0.2)
const CORD := Color(0.14, 0.22, 0.14)
## How far string lights hang below their line (the bulbs sit on the low points).
const LIGHT_DROOP := 0.12
## The jack-o'-lantern's face, for place(): its center and radius.
const LANTERN_FACE := Vector3(0.0, 0.2, -0.235)
## Bulb colors for string lights (warm white, red, green, blue, amber).
const BULB_COLORS: Array[Color] = [Color(1.0, 0.92, 0.7), Color(0.95, 0.2, 0.18), Color(0.2, 0.85, 0.35), Color(0.25, 0.45, 1.0), Color(1.0, 0.7, 0.15)]


static func build(kind: String, kit: _MeshKit, color: Color, size: Vector3) -> bool:
	match kind:
		"pumpkin_small":
			_pumpkin(kit, _P.tint(color, PUMPKIN), 0.6)
		"pumpkin":
			_pumpkin(kit, _P.tint(color, PUMPKIN), 1.0)
		"pumpkin_big":
			_pumpkin(kit, _P.tint(color, PUMPKIN), 1.6)
		"jack_o_lantern":
			_pumpkin(kit, _P.tint(color, PUMPKIN), 1.1)
		"hay_bale":
			_hay_bale(kit, _P.tint(color, _P.STRAW))
		"scarecrow":
			_scarecrow(kit, _P.tint(color, Color(0.3, 0.42, 0.62)))
		"mums_pot":
			_mums(kit, _P.tint(color, Color(0.92, 0.6, 0.12)))
		"snowman":
			_snowman(kit)
		"snowman_inflatable":
			_inflatable(kit)
		"wreath":
			_wreath(kit, _P.tint(color, Color(0.15, 0.38, 0.2)))
		"snow_pile":
			_snow_pile(kit)
		"snowbank_run":
			_snowbank(kit, _P.dims(size, Vector3(RUN_LENGTH, 0.6, 1.0)))
		"sled":
			_sled(kit, _P.tint(color, Color(0.8, 0.16, 0.12)))
		"icicle_run":
			_icicles(kit, _P.dims(size, Vector3(RUN_LENGTH, 0.4, 0.0)))
		"string_lights":
			_light_cord(kit, _P.dims(size, Vector3(RUN_LENGTH, 0.0, 0.0)))
		"holiday_tree_lot":
			_tree_lot(kit)
		"tulip_bed":
			_tulips(kit, _P.tint(color, Color(0.92, 0.16, 0.2)), _P.dims(size, Vector3(2.0, 0.0, 0.7)))
		"petal_scatter":
			_petals(kit, _P.tint(color, Color(0.98, 0.76, 0.84)))
		"beach_umbrella":
			_beach_umbrella(kit, _P.tint(color, Color(0.92, 0.22, 0.2)))
		"pool_float":
			_pool_float(kit, _P.tint(color, Color(0.98, 0.5, 0.7)))
		"lemonade_stand":
			_lemonade_stand(kit, _P.tint(color, Color(0.98, 0.9, 0.36)))
		_:
			return false
	return true


## Where string lights' bulbs go along a run of length (local x from -length/2),
## spaced Constants.ART_STRING_LIGHT_SPACING, on the cord's low points.
static func bulb_points(length: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var spacing := Constants.ART_STRING_LIGHT_SPACING
	var count := maxi(1, int(length / spacing))
	for index: int in count:
		var x := -length * 0.5 + (float(index) + 0.5) * length / float(count)
		points.append(Vector3(x, -LIGHT_DROOP - 0.05, 0.0))
	return points


# ---------------------------------------------------------------- autumn

static func _pumpkin(kit: _MeshKit, color: Color, scale: float) -> void:
	var radius := 0.2 * scale
	for index: int in 6:
		var angle := TAU * float(index) / 6.0
		_P.ball(kit, Vector3(cos(angle) * radius * 0.45, radius * 0.85, sin(angle) * radius * 0.45), Vector3(radius * 0.62, radius * 0.82, radius * 0.62), color.darkened(0.05 * float(index % 2)), 1)
	kit.tube(PackedVector3Array([Vector3(0.0, radius * 1.5, 0.0), Vector3(0.02 * scale, radius * 1.9, 0.0), Vector3(0.05 * scale, radius * 2.0, 0.0)]), PackedFloat32Array([0.03 * scale, 0.022 * scale, 0.018 * scale]), STEM, 5, {"jitter": 0.0})


static func _hay_bale(kit: _MeshKit, color: Color) -> void:
	_P.soft(kit, Vector3(0.0, 0.25, 0.0), Vector3(1.0, 0.5, 0.5), color, 7.0, 2)
	for x: float in [-0.25, 0.25]:
		_P.soft(kit, Vector3(x, 0.25, 0.0), Vector3(0.03, 0.51, 0.51), color.darkened(0.3), 7.0, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for index: int in 10:
		var at := Vector3(rng.randf_range(-0.45, 0.45), 0.5, rng.randf_range(-0.2, 0.2))
		_P.leaf(kit, at, Vector3(rng.randf_range(-0.5, 0.5), 1.0, rng.randf_range(-0.5, 0.5)), 0.08, color.lightened(0.1), 0.0, rng.randf() * TAU)


static func _scarecrow(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 1.0, 0.04), Vector3(0.08, 2.0, 0.08), _P.WOOD)
	_P.slab(kit, Vector3(0.0, 1.4, 0.04), Vector3(1.4, 0.07, 0.07), _P.WOOD)
	_P.soft(kit, Vector3(0.0, 1.25, 0.0), Vector3(0.6, 0.6, 0.3), color, 4.0, 1)
	for side: float in [-1.0, 1.0]:
		_P.soft(kit, Vector3(side * 0.45, 1.4, 0.0), Vector3(0.36, 0.18, 0.2), color, 4.0, 0)
		for index: int in 3:
			_P.leaf(kit, Vector3(side * 0.66, 1.38 - float(index) * 0.03, 0.0), Vector3(side, -0.3, -0.4), 0.09, _P.STRAW, 0.3, float(index))
	_P.slab(kit, Vector3(0.12, 1.2, -0.155), Vector3(0.14, 0.14, 0.01), KID_PATCH)
	_P.ball(kit, Vector3(0.0, 1.75, 0.0), Vector3(0.19, 0.2, 0.18), Color(0.86, 0.76, 0.56), 1)
	for side: float in [-0.06, 0.06]:
		_P.slab(kit, Vector3(side, 1.79, -0.175), Vector3(0.04, 0.04, 0.01), _P.BLACK)
	_P.slab(kit, Vector3(0.0, 1.69, -0.172), Vector3(0.12, 0.015, 0.01), _P.BLACK)
	_P.disc(kit, Vector3(0.0, 1.92, 0.0), 0.36, 0.03, Color(0.78, 0.62, 0.34), 10)
	kit.tube(PackedVector3Array([Vector3(0.0, 1.92, 0.0), Vector3(0.0, 2.12, 0.0)]), PackedFloat32Array([0.16, 0.12]), Color(0.78, 0.62, 0.34), 8, {"jitter": 0.0})
	_P.soft(kit, Vector3(0.0, 0.85, 0.0), Vector3(0.36, 0.3, 0.24), Color(0.4, 0.3, 0.22), 4.0, 0)


const KID_PATCH := Color(0.86, 0.3, 0.26)


static func _mums(kit: _MeshKit, color: Color) -> void:
	kit.tube(PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.3, 0.0)]), PackedFloat32Array([0.18, 0.24]), Color(0.66, 0.4, 0.26), 8, {"jitter": 0.0, "cap_start": true})
	_P.lump(kit, Vector3(0.0, 0.42, 0.0), Vector3(0.3, 0.2, 0.3), color, 5, 1, 0.2, 0.2)


# ---------------------------------------------------------------- winter

static func _snowman(kit: _MeshKit) -> void:
	_P.lump(kit, Vector3(0.0, 0.32, 0.0), Vector3(0.4, 0.34, 0.4), _P.SNOW, 1, 1, 0.08)
	_P.lump(kit, Vector3(0.0, 0.86, 0.0), Vector3(0.29, 0.26, 0.29), _P.SNOW, 2, 1, 0.08)
	_P.ball(kit, Vector3(0.0, 1.27, 0.0), Vector3(0.2, 0.19, 0.2), _P.SNOW, 1)
	kit.tube(PackedVector3Array([Vector3(0.0, 1.27, -0.18), Vector3(0.0, 1.25, -0.4)]), PackedFloat32Array([0.035, 0.005]), Color(0.95, 0.5, 0.12), 5, {"jitter": 0.0, "cap_start": true})
	for side: float in [-0.07, 0.07]:
		_P.ball(kit, Vector3(side, 1.33, -0.18), Vector3(0.025, 0.025, 0.02), _P.BLACK, 0)
	for index: int in 3:
		_P.ball(kit, Vector3(0.0, 0.78 + float(index) * 0.1, -0.27 + float(index) * 0.01), Vector3(0.025, 0.025, 0.02), _P.BLACK, 0)
	for side: float in [-1.0, 1.0]:
		_P.path(kit, PackedVector3Array([Vector3(side * 0.25, 0.92, 0.0), Vector3(side * 0.5, 1.1, 0.0), Vector3(side * 0.62, 1.25, 0.05)]), 0.018, Color(0.36, 0.26, 0.18), 4)
	_P.ring(kit, Vector3(0.0, 1.1, 0.0), 0.2, 0.05, Color(0.8, 0.2, 0.18), 10, 5)
	_P.slab(kit, Vector3(0.12, 0.98, -0.2), Vector3(0.1, 0.24, 0.04), Color(0.8, 0.2, 0.18), Basis(Vector3.FORWARD, 0.2))
	_P.disc(kit, Vector3(0.0, 1.44, 0.0), 0.2, 0.02, _P.BLACK, 10)
	_P.post(kit, Vector3(0.0, 1.44, 0.0), 0.22, 0.13, _P.BLACK, 10)


## The block's one inflatable snowman, half deflated and leaning on its own
## fan, swaying a little in the breeze.
static func _inflatable(kit: _MeshKit) -> void:
	_P.slab(kit, Vector3(0.0, 0.1, 0.0), Vector3(0.4, 0.2, 0.3), _P.DARK_STEEL)
	var lean := Basis(Vector3.FORWARD, 0.35) * Basis(Vector3.RIGHT, -0.2)
	_P.lump(kit, Vector3(0.1, 0.55, 0.0), Vector3(0.6, 0.48, 0.55), _P.WHITE, 1, 1, 0.12, 0.1)
	_P.lump(kit, lean * Vector3(0.0, 1.3, 0.0) + Vector3(0.1, 0.0, 0.0), Vector3(0.42, 0.36, 0.4), _P.WHITE, 2, 1, 0.14, 0.4)
	var head := lean * Vector3(0.0, 1.85, -0.05) + Vector3(0.1, -0.15, 0.0)
	_P.lump(kit, head, Vector3(0.3, 0.26, 0.3), _P.WHITE, 3, 1, 0.12, 0.6)
	_P.soft(kit, head + Vector3(0.0, 0.22, 0.0), Vector3(0.4, 0.36, 0.4), Color(0.85, 0.2, 0.18), 3.0, 1, lean * Basis(Vector3.FORWARD, 0.6), 0.7)
	_P.ball(kit, head + Vector3(0.0, 0.0, -0.3), Vector3(0.05, 0.05, 0.12), Color(0.95, 0.5, 0.12), 0, 0.6)
	for side: float in [-0.1, 0.1]:
		_P.ball(kit, head + Vector3(side, 0.08, -0.26), Vector3(0.04, 0.05, 0.02), _P.BLACK, 0, 0.6)
	for index: int in 2:
		_P.bar(kit, Vector3(0.5 * (1.0 if index == 0 else -1.0), 0.02, -0.6), Vector3(0.2 * (1.0 if index == 0 else -1.0), 1.1, -0.05), 0.006, _P.WHITE.darkened(0.2), 3, 0.0, 0.3)


static func _wreath(kit: _MeshKit, color: Color) -> void:
	for index: int in 12:
		var angle := TAU * float(index) / 12.0
		_P.lump(kit, Vector3(cos(angle) * 0.24, 0.0, 0.0) + Vector3(0.0, sin(angle) * 0.24, 0.0), Vector3(0.09, 0.09, 0.05), color.lightened(0.04 * float(index % 2)), index, 0, 0.3)
	for index: int in 5:
		var angle := TAU * float(index) / 5.0 + 0.4
		_P.ball(kit, Vector3(cos(angle) * 0.26, sin(angle) * 0.26, -0.05), Vector3(0.025, 0.025, 0.025), Color(0.85, 0.12, 0.12), 0)
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 0.07, -0.24, -0.06), Vector3(0.12, 0.08, 0.03), Color(0.85, 0.12, 0.12), Basis(Vector3.FORWARD, side * 0.4))
		_P.slab(kit, Vector3(side * 0.05, -0.34, -0.06), Vector3(0.04, 0.16, 0.02), Color(0.85, 0.12, 0.12), Basis(Vector3.FORWARD, side * 0.25))


static func _snow_pile(kit: _MeshKit) -> void:
	_P.lump(kit, Vector3(0.0, 0.0, 0.0), Vector3(0.9, 0.5, 0.7), _P.SNOW, 4, 1, 0.25)
	_P.lump(kit, Vector3(0.5, 0.0, 0.3), Vector3(0.5, 0.3, 0.45), _P.SNOW.darkened(0.03), 5, 1, 0.25)


static func _snowbank(kit: _MeshKit, size: Vector3) -> void:
	var count := maxi(1, int(round(size.x / 1.5)))
	for index: int in count:
		var x := -size.x * 0.5 + (float(index) + 0.5) * size.x / float(count)
		_P.lump(kit, Vector3(x, 0.0, 0.0), Vector3(size.x / float(count) * 0.62, size.y, size.z * 0.5), _P.SNOW.darkened(0.04 * float(index % 2)), index, 1, 0.22)


static func _sled(kit: _MeshKit, color: Color) -> void:
	_P.soft(kit, Vector3(0.0, 0.12, 0.0), Vector3(0.5, 0.05, 1.1), color, 4.0, 1)
	_P.slab(kit, Vector3(0.0, 0.2, -0.56), Vector3(0.5, 0.18, 0.05), color, Basis(Vector3.RIGHT, -0.5))
	for side: float in [-0.22, 0.22]:
		_P.path(kit, PackedVector3Array([Vector3(side, 0.02, 0.55), Vector3(side, 0.02, -0.45), Vector3(side, 0.1, -0.62), Vector3(side, 0.22, -0.6)]), 0.015, _P.STEEL, 4)
	_P.path(kit, PackedVector3Array([Vector3(-0.2, 0.25, -0.58), Vector3(0.0, 0.3, -0.9), Vector3(0.2, 0.25, -0.58)]), 0.01, _P.WHITE, 3)


static func _icicles(kit: _MeshKit, size: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(size.x * 10.0)
	var x := -size.x * 0.5 + 0.1
	while x < size.x * 0.5:
		var length := rng.randf_range(0.08, size.y)
		kit.tube(PackedVector3Array([Vector3(x, 0.0, 0.0), Vector3(x, -length, 0.0)]), PackedFloat32Array([rng.randf_range(0.025, 0.05), 0.003]), Color(0.86, 0.94, 1.0), 5, {"jitter": 0.0, "cap_start": true})
		x += rng.randf_range(0.12, 0.3)


static func _light_cord(kit: _MeshKit, size: Vector3) -> void:
	var count := maxi(1, int(size.x / 1.2))
	for index: int in count:
		var a := Vector3(-size.x * 0.5 + float(index) * size.x / float(count), 0.0, 0.0)
		var b := Vector3(-size.x * 0.5 + float(index + 1) * size.x / float(count), 0.0, 0.0)
		_P.path(kit, _P.sag(a, b, LIGHT_DROOP, 4), 0.006, CORD, 3)


## Homie Depot's winter lot: a low pen and a crowd of netted trees leaning on it.
static func _tree_lot(kit: _MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(0.0, 0.5, side * 1.6), Vector3(4.6, 0.08, 0.06), _P.WOOD)
		_P.slab(kit, Vector3(side * 2.3, 0.5, 0.0), Vector3(0.06, 0.08, 3.2), _P.WOOD)
		for x: float in [-2.3, 0.0, 2.3]:
			_P.slab(kit, Vector3(x, 0.4, side * 1.6), Vector3(0.08, 0.8, 0.08), _P.WOOD.darkened(0.15))
	for index: int in 9:
		var at := Vector3(-1.6 + float(index % 3) * 1.6 + rng.randf_range(-0.2, 0.2), 0.0, -1.0 + float(index / 3) * 1.0)
		var height := rng.randf_range(1.6, 2.3)
		var lean := rng.randf_range(-0.15, 0.15)
		var top := at + Vector3(lean, height, 0.0)
		_P.bar(kit, at, at + Vector3(0.0, 0.3, 0.0), 0.04, _P.WOOD.darkened(0.3), 4)
		kit.tube(PackedVector3Array([at + Vector3(0.0, 0.25, 0.0), at.lerp(top, 0.5), top]), PackedFloat32Array([0.3, 0.22, 0.04]), Color(0.18, 0.36, 0.22).darkened(rng.randf_range(0.0, 0.15)), 6, {"jitter": 0.04, "seed": index})
		for band: int in 3:
			var y := 0.5 + float(band) * height * 0.28
			_P.ring(kit, at + Vector3(lean * y / height, y, 0.0), 0.28 - float(band) * 0.06, 0.008, _P.WHITE.darkened(0.1), 6, 3)


# ---------------------------------------------------------------- spring

## A bed of tulips size.x by size.z: stems and cups that sway a little.
static func _tulips(kit: _MeshKit, color: Color, size: Vector3) -> void:
	_P.slab(kit, Vector3(0.0, 0.01, 0.0), Vector3(size.x, 0.02, size.z), _P.SOIL)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(size.x * 13.0 + size.z * 7.0)
	var colors: Array[Color] = [color, color, Color(0.98, 0.84, 0.2), Color(0.98, 0.6, 0.72), _P.WHITE]
	var count := clampi(int(size.x * size.z * 18.0), 6, 60)
	for index: int in count:
		var at := Vector3(rng.randf_range(-size.x, size.x) * 0.45, 0.0, rng.randf_range(-size.z, size.z) * 0.45)
		var height := rng.randf_range(0.28, 0.4)
		_P.bar(kit, at, at + Vector3(0.0, height, 0.0), 0.008, _P.LEAF, 3, 0.0, 0.35)
		_P.leaf(kit, at + Vector3(0.0, 0.08, 0.0), Vector3(rng.randf_range(-1, 1), 0.3, rng.randf_range(-1, 1)), 0.09, _P.LEAF.lightened(0.1), 0.15, rng.randf() * TAU)
		kit.cone(at + Vector3(0.0, height - 0.01, 0.0), 0.035, 0.07, colors[rng.randi() % colors.size()], 5, {"lumps": 0.0, "top_radius": 0.045, "sway": 0.4})


static func _petals(kit: _MeshKit, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for index: int in 60:
		var radius := sqrt(rng.randf()) * 1.6
		var angle := rng.randf() * TAU
		var at := Vector3(cos(angle) * radius, 0.012, sin(angle) * radius)
		var tint := color if rng.randf() < 0.7 else _P.WHITE
		_P.leaf(kit, at, Vector3(rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(-0.2, 0.2)), 0.03, tint, 0.0, rng.randf() * TAU)


# ---------------------------------------------------------------- summer

## A beach umbrella with alternating stripes, tilted a little.
static func _beach_umbrella(kit: _MeshKit, color: Color) -> void:
	var tilt := Basis(Vector3.BACK, 0.18)
	_P.bar(kit, Vector3.ZERO, tilt * Vector3(0.0, 2.2, 0.0), 0.02, _P.WHITE, 4)
	var top := tilt * Vector3(0.0, 2.3, 0.0)
	var sides := 10
	for index: int in sides:
		var a0 := TAU * float(index) / float(sides)
		var a1 := TAU * float(index + 1) / float(sides)
		var p0 := tilt * Vector3(cos(a0) * 1.2, 1.95, sin(a0) * 1.2)
		var p1 := tilt * Vector3(cos(a1) * 1.2, 1.95, sin(a1) * 1.2)
		var tint := color if index % 2 == 0 else _P.WHITE
		_P.poly(kit, [p0, p1, top], tilt * Vector3(0.0, 1.0, 0.0), tint)
		_P.poly(kit, [p0, top, p1], tilt * Vector3(0.0, 3.0, 0.0), tint.darkened(0.2))


## A donut pool float with sprinkles. Floats on the water or leans on a fence.
static func _pool_float(kit: _MeshKit, color: Color) -> void:
	_P.ring(kit, Vector3(0.0, 0.14, 0.0), 0.42, 0.15, color, 12, 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var sprinkles: Array[Color] = [_P.WHITE, Color(0.98, 0.84, 0.2), Color(0.3, 0.6, 0.9), Color(0.4, 0.8, 0.4)]
	for index: int in 14:
		var angle := rng.randf() * TAU
		var at := Vector3(cos(angle) * 0.42, 0.29, sin(angle) * 0.42)
		_P.slab(kit, at, Vector3(0.06, 0.012, 0.015), sprinkles[index % sprinkles.size()], Basis(Vector3.UP, rng.randf() * TAU))


## A kid's lemonade stand: a table with a skirt, a striped roof, a pitcher
## (the price sign via place()).
static func _lemonade_stand(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.42, 0.0), Vector3(1.4, 0.84, 0.6), color)
	_P.slab(kit, Vector3(0.0, 0.86, 0.0), Vector3(1.5, 0.05, 0.7), _P.WOOD.lightened(0.1))
	for x: float in [-0.7, 0.7]:
		_P.slab(kit, Vector3(x, 1.2, 0.25), Vector3(0.06, 0.7, 0.06), _P.WOOD)
	for index: int in 6:
		_P.slab(kit, Vector3(-0.625 + float(index) * 0.25, 1.6, 0.0), Vector3(0.25, 0.04, 0.9), Color(0.92, 0.22, 0.2) if index % 2 == 0 else _P.WHITE, Basis(Vector3.RIGHT, 0.2))
	kit.tube(PackedVector3Array([Vector3(0.35, 0.89, 0.05), Vector3(0.35, 1.12, 0.05)]), PackedFloat32Array([0.07, 0.06]), Color(0.98, 0.92, 0.5), 8, {"jitter": 0.0, "cap_start": true})
	for x: float in [-0.2, 0.0]:
		kit.tube(PackedVector3Array([Vector3(x, 0.89, -0.1), Vector3(x, 0.99, -0.1)]), PackedFloat32Array([0.03, 0.035]), _P.WHITE, 6, {"jitter": 0.0, "cap_start": true})
	_P.slab(kit, Vector3(0.0, 0.5, -0.305), Vector3(1.1, 0.5, 0.02), _P.WHITE)
