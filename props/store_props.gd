extends RefCounted

## Authority: local, cosmetic. Homie Depot's own props (art chunk 8, docs/GAME.md
## "Homie Depot, inside and out"): the lot's mulch, soil and salt pallets, the
## flower flats, the propane cage, and the walk-in lobby's orange racking, paint
## pyramid, tool endcaps, the PRO DESK, the forklift and the restock wall at the
## back, and the wet-floor sign. Built with props/mesh_kit.gd through
## props/prop_parts.gd and registered by props/prop_catalog.gd (ask it, not this
## file). The words on them (aisle signs, SNOW-B-GONE, the restock tape) are
## Label3Ds the store builders add from Strings.SIGNS; the prices on the endcaps
## come only from Shops (props/shelf_stock.gd). Every mesh stays under
## Constants.ART_PROP_MAX_TRIANGLES.
##
## Frame: 1 m units, Y up, origin at the ground center, front facing -Z.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _P = preload("res://props/prop_parts.gd")

const KINDS: Array[String] = [
	"shipping_pallet", "mulch_pallet", "soil_pallet", "salt_pallet", "flower_flats", "paint_pyramid",
	"rack_bay", "forklift", "restock_wall", "propane_cage", "endcap", "pro_desk", "wet_floor_sign",
]
const SIZED: Array[String] = []

const ORANGE := Color(0.95, 0.5, 0.15)
const CARDBOARD := Color(0.72, 0.56, 0.38)
const TAPE := Color(0.96, 0.82, 0.18)
const FORKLIFT := Color(0.98, 0.76, 0.12)
## A pallet's footprint (x by z) and height.
const PALLET := Vector3(1.2, 0.14, 1.0)
## The endcap's top, where its ShelfSlot sits (levels/dressing/store_interior.gd).
const ENDCAP_TOP: float = 0.5
const ENDCAP_SIZE := Vector3(1.1, 0.5, 0.7)
## A rack bay: width along x, depth along z, height, and its beam levels.
const RACK_SIZE := Vector3(2.6, 3.4, 1.0)
const RACK_LEVELS: Array[float] = [0.18, 1.15, 2.15, 3.05]
## The restock wall: two pallets wide, three high.
const RESTOCK_SIZE := Vector3(2.6, 3.4, 1.2)
## How high the tape band (and the lobby's "restock" words on it) runs: over
## the PRO DESK's monitor.
const RESTOCK_BAND: float = 2.15


static func build(kind: String, kit: _MeshKit, color: Color, _size: Vector3) -> bool:
	match kind:
		"shipping_pallet":
			_pallet(kit, Vector3.ZERO)
		"mulch_pallet":
			_bag_pallet(kit, _P.tint(color, Color(0.55, 0.2, 0.14)), ORANGE, 3, 11)
		"soil_pallet":
			_bag_pallet(kit, _P.tint(color, Color(0.18, 0.36, 0.2)), Color(0.86, 0.76, 0.5), 3, 23)
		"salt_pallet":
			_bag_pallet(kit, _P.tint(color, Color(0.22, 0.44, 0.78)), _P.WHITE, 4, 37)
		"flower_flats":
			_flower_flats(kit)
		"paint_pyramid":
			_paint_pyramid(kit)
		"rack_bay":
			_rack_bay(kit, _P.tint(color, ORANGE))
		"forklift":
			_forklift(kit, _P.tint(color, FORKLIFT))
		"restock_wall":
			_restock_wall(kit)
		"propane_cage":
			_propane_cage(kit)
		"endcap":
			_endcap(kit, _P.tint(color, ORANGE))
		"pro_desk":
			_pro_desk(kit, _P.tint(color, ORANGE))
		"wet_floor_sign":
			_wet_floor(kit)
		_:
			return false
	return true


# ---------------------------------------------------------------- pallets and bags

## A wooden pallet with its bottom at base: three runners and five deck boards.
static func _pallet(kit: _MeshKit, base: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base.y * 100.0) + 5
	for x: float in [-0.52, 0.0, 0.52]:
		_P.slab(kit, base + Vector3(x, 0.05, 0.0), Vector3(0.1, 0.1, PALLET.z), _P.vary(_P.WOOD.darkened(0.08), rng, 0.05))
	for index: int in 5:
		var z := -PALLET.z * 0.5 + 0.07 + float(index) * (PALLET.z - 0.14) / 4.0
		_P.slab(kit, base + Vector3(0.0, 0.115, z), Vector3(PALLET.x, 0.03, 0.14), _P.vary(_P.WOOD, rng, 0.06))


## A pallet stacked layers high with soft bags in body color, a printed band
## across each, the top bag slumped a little. Rows run two by two, each layer
## nudged off the one under it, so the stack looks handled.
static func _bag_pallet(kit: _MeshKit, body: Color, band: Color, layers: int, seed_value: int) -> void:
	_pallet(kit, Vector3.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bag := Vector3(0.56, 0.13, 0.46)
	for layer: int in layers:
		var y := PALLET.y + bag.y * 0.5 + float(layer) * (bag.y - 0.01)
		for row: int in 2:
			for column: int in 2:
				var at := Vector3((float(column) - 0.5) * 0.59 + rng.randf_range(-0.03, 0.03), y, (float(row) - 0.5) * 0.48 + rng.randf_range(-0.025, 0.025))
				var turn := Basis(Vector3.UP, rng.randf_range(-0.06, 0.06))
				if layer == layers - 1 and row == 0 and column == 1:
					turn = turn * Basis(Vector3.FORWARD, 0.05)
				_P.soft(kit, at, bag, _P.vary(body, rng, 0.05), 6.0, 1, turn)
				# The printed band on the bag's face, toward the aisle.
				_P.slab(kit, at + turn * Vector3(0.0, 0.004, -bag.z * 0.5 + 0.004), Vector3(bag.x * 0.86, bag.y * 0.42, 0.012), band, turn)


## A two-step wooden stand of flower flats: black trays packed with blooms.
static func _flower_flats(kit: _MeshKit) -> void:
	var wood := _P.WOOD.darkened(0.05)
	for x: float in [-0.95, 0.95]:
		for z: float in [-0.35, 0.35]:
			_P.slab(kit, Vector3(x, 0.4 if z < 0.0 else 0.6, z), Vector3(0.07, 0.8 if z < 0.0 else 1.2, 0.07), wood)
	_P.slab(kit, Vector3(0.0, 0.42, -0.2), Vector3(2.0, 0.04, 0.42), wood)
	_P.slab(kit, Vector3(0.0, 0.82, 0.2), Vector3(2.0, 0.04, 0.42), wood)
	var colors: Array[Color] = [Color(0.95, 0.3, 0.45), Color(0.98, 0.85, 0.25), Color(0.6, 0.35, 0.85), Color(0.98, 0.55, 0.2), Color(0.95, 0.95, 0.92)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	for step: int in 2:
		var y := 0.46 if step == 0 else 0.86
		var z := -0.2 if step == 0 else 0.2
		for flat: int in 4:
			var x := -0.72 + float(flat) * 0.48
			_P.slab(kit, Vector3(x, y + 0.03, z), Vector3(0.44, 0.06, 0.36), Color(0.1, 0.1, 0.11))
			# The leaves as one green mat in the tray, the blooms in two rows of three on it.
			_P.slab(kit, Vector3(x, y + 0.085, z), Vector3(0.4, 0.05, 0.32), _P.LEAF.lightened(0.05))
			var bloom := colors[(flat + step * 2) % colors.size()]
			for plant: int in 6:
				var at := Vector3(x - 0.13 + float(plant % 3) * 0.13 + rng.randf_range(-0.02, 0.02), y + 0.125, z - 0.075 + float(plant / 3) * 0.15)
				_P.ball(kit, at, Vector3(0.06, 0.035, 0.06), _P.vary(bloom, rng, 0.06), 0)


## Paint cans in a four-three-two-one pyramid on a pallet, in a run of colors,
## each with a white lid and the store's orange label.
static func _paint_pyramid(kit: _MeshKit) -> void:
	_pallet(kit, Vector3.ZERO)
	var colors: Array[Color] = [Color(0.92, 0.92, 0.88), Color(0.25, 0.45, 0.8), Color(0.95, 0.8, 0.25), Color(0.8, 0.25, 0.2), Color(0.35, 0.65, 0.4)]
	var radius := 0.1
	var height := 0.2
	var index := 0
	for layer: int in 4:
		var count := 4 - layer
		var y := PALLET.y + float(layer) * (height + 0.01)
		for row: int in count:
			for column: int in count:
				var at := Vector3((float(column) - float(count - 1) * 0.5) * 0.215, y, (float(row) - float(count - 1) * 0.5) * 0.215)
				var tint := colors[index % colors.size()]
				_P.bar(kit, at, at + Vector3(0.0, height * 0.72, 0.0), radius, tint, 7)
				_P.bar(kit, at + Vector3(0.0, height * 0.72, 0.0), at + Vector3(0.0, height, 0.0), radius, ORANGE, 7)
				index += 1


# ---------------------------------------------------------------- the lobby

## A bay of orange pallet racking: two upright frames, a pair of beams a level,
## wire decks, and cardboard stock on every level (the floor level too).
static func _rack_bay(kit: _MeshKit, color: Color) -> void:
	var half := RACK_SIZE * 0.5
	var blue := Color(0.2, 0.32, 0.55)
	for x: float in [-half.x + 0.05, half.x - 0.05]:
		for z: float in [-half.z + 0.05, half.z - 0.05]:
			_P.slab(kit, Vector3(x, half.y, z), Vector3(0.08, RACK_SIZE.y, 0.08), blue)
		# The frame's cross bracing.
		for y: float in [0.7, 1.7, 2.7]:
			_P.slab(kit, Vector3(x, y, 0.0), Vector3(0.04, 0.05, RACK_SIZE.z - 0.1), blue.lightened(0.1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for level: int in RACK_LEVELS.size():
		var y := RACK_LEVELS[level]
		if level > 0:
			for z: float in [-half.z + 0.05, half.z - 0.05]:
				_P.slab(kit, Vector3(0.0, y - 0.06, z), Vector3(RACK_SIZE.x - 0.1, 0.12, 0.06), color)
			_P.slab(kit, Vector3(0.0, y - 0.005, 0.0), Vector3(RACK_SIZE.x - 0.12, 0.01, RACK_SIZE.z - 0.1), _P.STEEL)
		if level == RACK_LEVELS.size() - 1:
			# The top: overstock, one big box a side, nearly to the ceiling.
			for x: float in [-0.62, 0.62]:
				_carton(kit, Vector3(x, y, rng.randf_range(-0.05, 0.05)), Vector3(1.1, 0.55, 0.8), rng)
			continue
		var x := -half.x + 0.16
		while x < half.x - 0.5:
			var wide := rng.randf_range(0.45, 0.8)
			var tall := rng.randf_range(0.35, 0.7)
			if x + wide > half.x - 0.12:
				break
			_carton(kit, Vector3(x + wide * 0.5, y, rng.randf_range(-0.08, 0.08)), Vector3(wide, tall, rng.randf_range(0.6, 0.82)), rng)
			x += wide + 0.04


## A cardboard carton standing at base, tape across the top and an orange
## "HD" patch on the front.
static func _carton(kit: _MeshKit, base: Vector3, size: Vector3, rng: RandomNumberGenerator) -> void:
	var center := base + Vector3(0.0, size.y * 0.5, 0.0)
	_P.slab(kit, center, size, _P.vary(CARDBOARD, rng, 0.06))
	_P.slab(kit, center + Vector3(0.0, size.y * 0.5 + 0.002, 0.0), Vector3(size.x * 0.18, 0.006, size.z + 0.01), CARDBOARD.lightened(0.2))
	_P.slab(kit, center + Vector3(0.0, 0.0, -size.z * 0.5 - 0.004), Vector3(size.x * 0.3, size.y * 0.25, 0.008), ORANGE)


## The yellow forklift, parked for good: the forks up at chest height holding an
## empty pallet, a cobweb of caution tape on the mast. Faces -Z (forks forward).
static func _forklift(kit: _MeshKit, color: Color) -> void:
	var dark := _P.DARK_STEEL
	# The body and the counterweight at the back.
	_P.soft(kit, Vector3(0.0, 0.62, 0.25), Vector3(1.08, 0.7, 1.5), color, 7.0, 1)
	_P.soft(kit, Vector3(0.0, 0.72, 1.05), Vector3(1.1, 0.8, 0.45), dark, 6.0, 1)
	# The seat and the steering wheel.
	_P.soft(kit, Vector3(0.0, 1.12, 0.45), Vector3(0.5, 0.14, 0.45), _P.BLACK, 5.0, 1)
	_P.soft(kit, Vector3(0.0, 1.36, 0.66), Vector3(0.5, 0.42, 0.12), _P.BLACK, 5.0, 1)
	_P.bar(kit, Vector3(0.0, 0.95, -0.22), Vector3(0.0, 1.35, -0.06), 0.03, dark, 5)
	_P.ring(kit, Vector3(0.0, 1.37, -0.05), 0.15, 0.022, _P.BLACK, 10, 4, Basis(Vector3.RIGHT, 0.5))
	# The overhead guard on four posts.
	for x: float in [-0.48, 0.48]:
		_P.bar(kit, Vector3(x, 0.95, -0.35), Vector3(x, 2.15, -0.25), 0.035, dark, 5)
		_P.bar(kit, Vector3(x, 1.05, 0.88), Vector3(x, 2.15, 0.78), 0.035, dark, 5)
	_P.slab(kit, Vector3(0.0, 2.17, 0.27), Vector3(1.04, 0.05, 1.12), dark)
	for z: float in [-0.05, 0.27, 0.59]:
		_P.slab(kit, Vector3(0.0, 2.2, z), Vector3(1.04, 0.03, 0.05), color)
	# The wheels.
	for x: float in [-0.5, 0.5]:
		_P.wheel(kit, Vector3(x, 0.3, -0.25), 0.3, 0.24)
		_P.wheel(kit, Vector3(x, 0.24, 0.9), 0.24, 0.2)
	# The mast at the front and the carriage, the forks up a meter.
	for x: float in [-0.36, 0.36]:
		_P.slab(kit, Vector3(x, 1.25, -0.62), Vector3(0.09, 2.5, 0.1), dark)
	_P.slab(kit, Vector3(0.0, 2.48, -0.62), Vector3(0.82, 0.08, 0.1), dark)
	var lift := 1.0
	_P.slab(kit, Vector3(0.0, lift + 0.35, -0.7), Vector3(0.9, 0.6, 0.06), dark.lightened(0.1))
	for x: float in [-0.25, 0.25]:
		_P.slab(kit, Vector3(x, lift + 0.03, -1.25), Vector3(0.12, 0.05, 1.1), dark)
		_P.slab(kit, Vector3(x, lift + 0.3, -0.73), Vector3(0.12, 0.6, 0.05), dark)
	_pallet(kit, Vector3(0.0, lift + 0.055, -1.25))
	# Caution tape wound round the mast, ends hanging.
	_P.slab(kit, Vector3(0.0, 1.9, -0.68), Vector3(0.9, 0.07, 0.02), TAPE, Basis(Vector3.FORWARD, 0.18))
	_P.slab(kit, Vector3(0.0, 1.75, -0.68), Vector3(0.9, 0.07, 0.02), TAPE, Basis(Vector3.FORWARD, -0.22))
	_P.slab(kit, Vector3(0.47, 1.45, -0.69), Vector3(0.07, 0.5, 0.015), TAPE, Basis(Vector3.FORWARD, 0.1))


## The back of the lobby: shrink-wrapped stock two pallets wide and three high
## (the pad's edge runs behind it), and caution tape across it in an X and a
## band, so nobody wonders why you can't go further. The words are a Label3D
## (Strings.SIGNS "restock") the lobby hangs on the band.
static func _restock_wall(kit: _MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2019
	var wrap := Color(0.82, 0.84, 0.86)
	for column: int in 2:
		var x := (float(column) - 0.5) * 1.3
		for level: int in 3:
			var y := float(level) * 1.12
			_pallet(kit, Vector3(x, y, 0.0))
			var tall := rng.randf_range(0.82, 0.96)
			var center := Vector3(x, y + PALLET.y + tall * 0.5, 0.0)
			_P.slab(kit, center, Vector3(1.18, tall, 0.98), _P.vary(CARDBOARD, rng, 0.07))
			# The shrink wrap's sheen as a slightly bigger pale skin on the front.
			_P.slab(kit, center + Vector3(0.0, 0.0, -0.495), Vector3(1.2, tall, 0.01), wrap.darkened(rng.randf_range(0.0, 0.08)))
			for band: int in 3:
				_P.slab(kit, center + Vector3(0.0, (float(band) - 1.0) * tall * 0.3, -0.502), Vector3(1.21, 0.03, 0.012), wrap.lightened(0.1))
	var front := -RESTOCK_SIZE.z * 0.5 - 0.03
	for turn: float in [-0.62, 0.62]:
		_P.slab(kit, Vector3(0.0, 1.8, front), Vector3(3.1, 0.1, 0.012), TAPE, Basis(Vector3.FORWARD, turn))
	_P.slab(kit, Vector3(0.0, RESTOCK_BAND, front - 0.01), Vector3(2.62, 0.3, 0.012), TAPE)


## A tool endcap: an orange plinth the tool stands on (its ShelfSlot is the
## plinth's top) and a pegboard back panel with an orange header. Customers
## stand at -Z.
static func _endcap(kit: _MeshKit, color: Color) -> void:
	var half := ENDCAP_SIZE * 0.5
	_P.slab(kit, Vector3(0.0, ENDCAP_TOP * 0.5, 0.0), Vector3(ENDCAP_SIZE.x, ENDCAP_TOP, ENDCAP_SIZE.z), color)
	_P.slab(kit, Vector3(0.0, 0.04, -half.z - 0.01), Vector3(ENDCAP_SIZE.x + 0.02, 0.08, 0.04), _P.BLACK)
	_P.slab(kit, Vector3(0.0, ENDCAP_TOP + 0.01, 0.0), Vector3(ENDCAP_SIZE.x + 0.04, 0.02, ENDCAP_SIZE.z + 0.04), color.darkened(0.15))
	var board := Color(0.62, 0.48, 0.32)
	_P.slab(kit, Vector3(0.0, ENDCAP_TOP + 0.8, half.z - 0.03), Vector3(ENDCAP_SIZE.x, 1.6, 0.04), board)
	# Pegboard holes, a sparse grid of dark dots.
	for row: int in 5:
		for column: int in 6:
			_P.slab(kit, Vector3(-0.42 + float(column) * 0.168, ENDCAP_TOP + 0.3 + float(row) * 0.26, half.z - 0.052), Vector3(0.025, 0.025, 0.004), board.darkened(0.45))
	_P.slab(kit, Vector3(0.0, ENDCAP_TOP + 1.72, half.z - 0.06), Vector3(ENDCAP_SIZE.x + 0.06, 0.24, 0.1), color)
	for x: float in [-half.x + 0.02, half.x - 0.02]:
		_P.slab(kit, Vector3(x, ENDCAP_TOP + 0.8, half.z - 0.03), Vector3(0.04, 1.64, 0.06), color.darkened(0.1))


## The PRO DESK: an orange counter with a laminate top, a dead monitor, a desk
## bell nobody answers, and a clipboard. Customers stand at -Z.
static func _pro_desk(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.7), color)
	_P.slab(kit, Vector3(0.0, 0.05, -0.33), Vector3(2.02, 0.1, 0.06), _P.BLACK)
	_P.slab(kit, Vector3(0.0, 1.03, -0.03), Vector3(2.12, 0.06, 0.82), Color(0.86, 0.84, 0.78))
	_P.slab(kit, Vector3(0.0, 0.6, -0.355), Vector3(1.4, 0.3, 0.01), color.lightened(0.15))
	# The monitor, turned toward whoever was behind it.
	_P.slab(kit, Vector3(0.55, 1.08, 0.12), Vector3(0.22, 0.04, 0.16), _P.DARK_STEEL)
	_P.slab(kit, Vector3(0.55, 1.18, 0.12), Vector3(0.05, 0.18, 0.05), _P.DARK_STEEL)
	_P.soft(kit, Vector3(0.55, 1.42, 0.12), Vector3(0.52, 0.34, 0.06), _P.BLACK, 6.0, 1, Basis(Vector3.UP, 0.25))
	# The bell.
	_P.disc(kit, Vector3(-0.35, 1.07, -0.18), 0.07, 0.015, _P.DARK_STEEL, 10)
	_P.ball(kit, Vector3(-0.35, 1.09, -0.18), Vector3(0.06, 0.05, 0.06), _P.CHROME, 1)
	_P.post(kit, Vector3(-0.35, 1.13, -0.18), 0.03, 0.008, _P.CHROME, 5)
	# A clipboard with a sign-up sheet (no names on it).
	_P.slab(kit, Vector3(-0.75, 1.07, -0.12), Vector3(0.24, 0.012, 0.32), Color(0.55, 0.4, 0.26), Basis(Vector3.UP, 0.2))
	_P.slab(kit, Vector3(-0.75, 1.078, -0.11), Vector3(0.2, 0.004, 0.26), _P.WHITE, Basis(Vector3.UP, 0.2))


## A propane exchange cage: a steel frame with mesh doors and two rows of white
## tanks inside, a red header panel on top (its words are a Label3D).
static func _propane_cage(kit: _MeshKit) -> void:
	var size := Vector3(1.9, 1.7, 0.9)
	var half := size * 0.5
	var steel := Color(0.78, 0.8, 0.82)
	_P.slab(kit, Vector3(0.0, 0.05, 0.0), Vector3(size.x, 0.1, size.z), steel.darkened(0.25))
	_P.slab(kit, Vector3(0.0, size.y, 0.0), Vector3(size.x, 0.06, size.z), steel)
	for x: float in [-half.x, 0.0, half.x]:
		for z: float in [-half.z, half.z]:
			_P.slab(kit, Vector3(x, half.y, z), Vector3(0.05, size.y, 0.05), steel.darkened(0.1))
	# The mesh: thin bars on the front and sides.
	for index: int in 16:
		var x := -half.x + 0.06 + float(index) * (size.x - 0.12) / 15.0
		_P.slab(kit, Vector3(x, half.y, -half.z), Vector3(0.012, size.y - 0.12, 0.012), steel)
	for y: float in [0.45, 0.9, 1.35]:
		_P.slab(kit, Vector3(0.0, y, -half.z), Vector3(size.x, 0.015, 0.015), steel)
		for x: float in [-half.x, half.x]:
			_P.slab(kit, Vector3(x, y, 0.0), Vector3(0.015, 0.015, size.z), steel)
	# The tanks: two rows of four on the floor of the cage.
	for row: int in 2:
		for column: int in 4:
			var at := Vector3(-0.66 + float(column) * 0.44, 0.1, -0.18 + float(row) * 0.38)
			_P.bar(kit, at, at + Vector3(0.0, 0.42, 0.0), 0.15, _P.WHITE, 8)
			_P.ball(kit, at + Vector3(0.0, 0.42, 0.0), Vector3(0.15, 0.06, 0.15), _P.WHITE, 0)
			_P.post(kit, at + Vector3(0.0, 0.46, 0.0), 0.08, 0.035, _P.DARK_STEEL, 6)
	_P.slab(kit, Vector3(0.0, size.y + 0.2, -half.z + 0.03), Vector3(1.4, 0.34, 0.05), Color(0.82, 0.16, 0.12))


## The yellow A-frame wet-floor sign, the stick figure mid-slip. Its words are
## a Label3D (Strings.SIGNS "wet_floor").
static func _wet_floor(kit: _MeshKit) -> void:
	for side: float in [-1.0, 1.0]:
		# Each panel stands on its foot WET_SPREAD out and leans in to meet the other at the top.
		var lean := wet_panel(side)
		var foot := Vector3(0.0, 0.0, side * WET_SPREAD)
		_P.slab(kit, lean * Vector3(0.0, 0.33, 0.0) + foot, Vector3(0.3, 0.66, 0.02), TAPE, lean)
		# The slipping figure, up top on the outer face: a head and a body going over.
		_P.slab(kit, lean * Vector3(-0.03, 0.52, side * 0.012) + foot, Vector3(0.03, 0.12, 0.004), _P.BLACK, lean * Basis(Vector3.FORWARD, 0.7))
		_P.slab(kit, lean * Vector3(0.02, 0.6, side * 0.012) + foot, Vector3(0.04, 0.04, 0.004), _P.BLACK, lean)
	_P.slab(kit, Vector3(0.0, 0.645, 0.0), Vector3(0.3, 0.03, 0.06), TAPE.darkened(0.1))


## How far a wet-floor sign's feet stand from its middle, and the lean of the
## panel on side (-1 the front, at -Z): its words go on that panel's outer face.
const WET_SPREAD: float = 0.16


static func wet_panel(side: float) -> Basis:
	return Basis(Vector3.RIGHT, -side * 0.24)
