extends RefCounted

## Authority: local, cosmetic. Street furniture and vehicles for the
## neighborhood blocks, built with props/mesh_kit.gd through props/prop_parts.gd
## and drawn with props/stylized.gd. Registered by props/prop_catalog.gd: ask it
## for meshes and nodes, not this file. Every mesh stays under
## Constants.ART_PROP_MAX_TRIANGLES.
##
## Frame: 1 unit = 1 m, Y up, origin at the ground center, the front facing -Z
## (a mailbox door, a sign face, a car's nose, a lamp's arm all point -Z).
## color is the body color (Color.WHITE = the kind's own default); size only
## matters for the kinds that say so.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _P = preload("res://props/prop_parts.gd")

const POLE := Color(0.22, 0.24, 0.26)
const SIGN_GREEN := Color(0.12, 0.42, 0.24)
const SIGN_RED := Color(0.78, 0.12, 0.1)
const SAFETY_YELLOW := Color(0.96, 0.78, 0.12)
const CONE_ORANGE := Color(0.96, 0.42, 0.1)
## Where a power pole's wires hang (the insulators), and their spread across.
const WIRE_HEIGHT := 8.55
const WIRE_SPREAD := 0.8

const KINDS: Array[String] = [
	"mailbox_post", "mailbox_brick", "mailbox_cluster", "mailbox_fancy", "mailbox_lighthouse",
	"wheelie_bin", "lamp_cobra", "lamp_acorn", "lamp_lantern", "lamp_post_lantern", "power_pole",
	"wire_span", "street_sign_post", "stop_sign", "speed_sign", "speed_bump", "bollard", "storm_drain",
	"newspaper_box", "traffic_cone", "bus_bench", "for_sale_sign", "basketball_hoop",
	"car_sedan", "car_hatch", "car_pickup", "car_wagon", "car_minivan", "car_suv", "car_suv_kayak",
	"car_convertible", "car_luxury", "car_on_blocks", "golf_cart", "boat_trailer",
]
## Kinds whose size means something (the rest ignore it).
const SIZED: Array[String] = ["wire_span", "speed_bump"]
const VEHICLES: Array[String] = [
	"car_sedan", "car_hatch", "car_pickup", "car_wagon", "car_minivan", "car_suv", "car_suv_kayak",
	"car_convertible", "car_luxury", "car_on_blocks", "golf_cart", "boat_trailer",
]


static func build(kind: String, kit: _MeshKit, color: Color, size: Vector3) -> bool:
	match kind:
		"mailbox_post":
			_mailbox_post(kit, _P.tint(color, Color(0.18, 0.24, 0.2)))
		"mailbox_brick":
			_mailbox_brick(kit, _P.tint(color, Color(0.8, 0.76, 0.68)))
		"mailbox_cluster":
			_mailbox_cluster(kit, _P.tint(color, Color(0.55, 0.47, 0.36)))
		"mailbox_fancy":
			_mailbox_fancy(kit, _P.tint(color, _P.BLACK))
		"mailbox_lighthouse":
			_mailbox_lighthouse(kit, _P.tint(color, SIGN_RED))
		"wheelie_bin":
			_wheelie_bin(kit, _P.tint(color, Color(0.2, 0.42, 0.28)))
		"lamp_cobra":
			_lamp_cobra(kit, _P.tint(color, POLE))
		"lamp_acorn":
			_lamp_acorn(kit, _P.tint(color, Color(0.12, 0.24, 0.18)))
		"lamp_lantern":
			_lamp_lantern(kit, _P.tint(color, _P.BLACK))
		"lamp_post_lantern":
			_lamp_post_lantern(kit, _P.tint(color, _P.BLACK))
		"power_pole":
			_power_pole(kit, _P.tint(color, Color(0.42, 0.33, 0.24)))
		"wire_span":
			var span := _P.dims(size, Vector3(30.0, 0.7, 0.0))
			wires(kit, [[Vector3.ZERO, Vector3(0.0, 0.0, -span.x)]], WIRE_HEIGHT, span.y, _P.tint(color, Color(0.1, 0.1, 0.1)))
		"street_sign_post":
			_street_sign(kit, _P.tint(color, SIGN_GREEN))
		"stop_sign":
			_stop_sign(kit)
		"speed_sign":
			_speed_sign(kit)
		"speed_bump":
			_speed_bump(kit, _P.dims(size, Vector3(4.4, 0.1, 0.9)))
		"bollard":
			_bollard(kit, _P.tint(color, SAFETY_YELLOW))
		"storm_drain":
			_storm_drain(kit)
		"newspaper_box":
			_newspaper_box(kit, _P.tint(color, Color(0.2, 0.36, 0.62)))
		"traffic_cone":
			_traffic_cone(kit)
		"bus_bench":
			_bus_bench(kit, _P.tint(color, Color(0.3, 0.42, 0.3)))
		"for_sale_sign":
			_for_sale_sign(kit)
		"basketball_hoop":
			_basketball_hoop(kit)
		"car_sedan":
			_car(kit, _P.tint(color, Color(0.36, 0.42, 0.52)), {})
		"car_hatch":
			_car(kit, _P.tint(color, Color(0.62, 0.22, 0.18)), {"length": 3.8, "cabin_z": 0.35, "cabin_len": 1.45, "tail": 0.0})
		"car_wagon":
			_car(kit, _P.tint(color, Color(0.55, 0.5, 0.42)), {"length": 5.0, "cabin_z": 0.55, "cabin_len": 2.35, "wood": true})
		"car_minivan":
			_car(kit, _P.tint(color, Color(0.78, 0.78, 0.8)), {"length": 5.0, "width": 1.95, "body_h": 0.75, "cabin_z": 0.4, "cabin_len": 2.9, "cabin_h": 0.85, "nose": 0.9})
		"car_suv":
			_car(kit, _P.tint(color, Color(0.12, 0.12, 0.13)), {"length": 4.8, "width": 1.95, "body_h": 0.8, "ride": 0.5, "wheel": 0.4, "cabin_z": 0.45, "cabin_len": 2.5, "cabin_h": 0.72})
		"car_suv_kayak":
			_car(kit, _P.tint(color, Color(0.24, 0.36, 0.3)), {"length": 4.8, "width": 1.95, "body_h": 0.8, "ride": 0.5, "wheel": 0.4, "cabin_z": 0.45, "cabin_len": 2.5, "cabin_h": 0.72, "kayak": true})
		"car_convertible":
			_car(kit, _P.tint(color, Color(0.72, 0.1, 0.12)), {"length": 4.5, "body_h": 0.5, "ride": 0.3, "cabin_z": 0.4, "cabin_len": 1.5, "open": true})
		"car_luxury":
			_car(kit, _P.tint(color, Color(0.1, 0.1, 0.11)), {"length": 5.3, "width": 1.95, "body_h": 0.55, "ride": 0.34, "cabin_z": 0.35, "cabin_len": 2.3, "cabin_h": 0.6, "chrome": true})
		"car_pickup":
			_pickup(kit, _P.tint(color, Color(0.62, 0.22, 0.18)))
		"car_on_blocks":
			_car(kit, _P.tint(color, Color(0.55, 0.38, 0.26)), {"length": 4.5, "blocks": true})
		"golf_cart":
			_golf_cart(kit, _P.tint(color, Color(0.93, 0.93, 0.9)))
		"boat_trailer":
			_boat_trailer(kit, _P.tint(color, Color(0.92, 0.92, 0.9)))
		_:
			return false
	return true


## Power or phone wires between pole bases: three lines per span at the
## insulators (height above each point, spread across the span), each sagging
## by sag. One mesh for a whole street (StreetBuilder merges a block's spans).
static func wires(kit: _MeshKit, spans: Array, height: float = WIRE_HEIGHT, sag: float = 0.7, color: Color = Color(0.1, 0.1, 0.1)) -> void:
	for span: Array in spans:
		var from: Vector3 = span[0]
		var to: Vector3 = span[1]
		var along := to - from
		along.y = 0.0
		if along.length() < 0.5:
			continue
		var across := along.normalized().cross(Vector3.UP)
		for offset: float in [-WIRE_SPREAD, 0.0, WIRE_SPREAD]:
			var a := from + Vector3(0.0, height, 0.0) + across * offset
			var b := to + Vector3(0.0, height, 0.0) + across * offset
			_P.path(kit, _P.sag(a, b, sag, 8), 0.018, color, 3)


## A whole street's wires as one mesh (see wires()).
static func wire_mesh(spans: Array, height: float = WIRE_HEIGHT, sag: float = 0.7) -> ArrayMesh:
	var kit := _MeshKit.new()
	wires(kit, spans, height, sag)
	var mesh := kit.commit()
	if mesh != null:
		mesh.set_meta("triangles", kit.vertex_count() / 3)
	return mesh


# ---------------------------------------------------------------- mailboxes

## A classic curbside box on a wooden post, red flag up on its side.
static func _mailbox_post(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.52, 0.0), Vector3(0.1, 1.04, 0.1), _P.WOOD)
	_P.slab(kit, Vector3(0.0, 1.02, 0.0), Vector3(0.16, 0.05, 0.42), _P.WOOD.darkened(0.1))
	_P.slab(kit, Vector3(0.0, 1.14, 0.0), Vector3(0.24, 0.18, 0.5), color)
	_P.bar(kit, Vector3(0.0, 1.23, -0.25), Vector3(0.0, 1.23, 0.25), 0.12, color, 8)
	_P.slab(kit, Vector3(0.0, 1.16, -0.255), Vector3(0.22, 0.24, 0.02), color.darkened(0.15))
	_P.slab(kit, Vector3(0.14, 1.3, 0.05), Vector3(0.02, 0.2, 0.06), _P.STEEL.darkened(0.2))
	_P.slab(kit, Vector3(0.14, 1.38, 0.11), Vector3(0.025, 0.08, 0.14), SIGN_RED)


## Oak Hollow's: a brick column in Approved Beige, a stone cap, a slot.
static func _mailbox_brick(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.62, 0.0), Vector3(0.56, 1.24, 0.56), color)
	for course: int in 7:
		var y := 0.12 + float(course) * 0.16
		_P.slab(kit, Vector3(0.0, y, 0.0), Vector3(0.575, 0.018, 0.575), color.darkened(0.12))
	_P.slab(kit, Vector3(0.0, 1.29, 0.0), Vector3(0.66, 0.1, 0.66), _P.STONE.lightened(0.1))
	_P.slab(kit, Vector3(0.0, 1.37, 0.0), Vector3(0.5, 0.06, 0.5), _P.STONE)
	_P.slab(kit, Vector3(0.0, 0.92, -0.285), Vector3(0.34, 0.26, 0.02), _P.BLACK)
	_P.slab(kit, Vector3(0.0, 0.92, -0.297), Vector3(0.22, 0.03, 0.01), _P.STEEL.darkened(0.4))
	_P.slab(kit, Vector3(0.0, 0.58, -0.285), Vector3(0.24, 0.1, 0.02), Color(0.86, 0.72, 0.36))


## Dandelion Acres' cluster box kiosk: a grid of little doors on a pedestal, a
## hood on top. Somebody's door is always hanging open.
static func _mailbox_cluster(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.2, 0.0), Vector3(0.7, 0.4, 0.36), color.darkened(0.25))
	_P.slab(kit, Vector3(0.0, 1.05, 0.0), Vector3(1.3, 1.3, 0.48), color)
	for row: int in 4:
		for column: int in 4:
			var at := Vector3(-0.45 + float(column) * 0.3, 0.6 + float(row) * 0.3, -0.25)
			if row == 1 and column == 2:
				# The one that never shuts.
				_P.slab(kit, at + Vector3(-0.1, 0.0, -0.12), Vector3(0.025, 0.25, 0.24), color.lightened(0.08))
				_P.slab(kit, at + Vector3(0.0, 0.0, 0.01), Vector3(0.25, 0.25, 0.02), _P.BLACK)
			else:
				_P.slab(kit, at, Vector3(0.26, 0.26, 0.02), color.lightened(0.08))
			_P.slab(kit, at + Vector3(0.08, 0.06, -0.012), Vector3(0.03, 0.03, 0.01), _P.CHROME)
	_P.slab(kit, Vector3(0.0, 1.76, 0.0), Vector3(1.42, 0.08, 0.6), color.darkened(0.15))
	_P.slab(kit, Vector3(0.0, 1.84, 0.02), Vector3(1.3, 0.08, 0.5), color.darkened(0.2))


## Mansion Hill's: a black cast post with scrolls, a gold-trimmed box, a finial.
static func _mailbox_fancy(kit: _MeshKit, color: Color) -> void:
	var gold := Color(0.86, 0.7, 0.32)
	_P.slab(kit, Vector3(0.0, 0.05, 0.0), Vector3(0.36, 0.1, 0.36), color)
	_P.taper(kit, Vector3(0.0, 0.1, 0.0), 1.0, 0.07, 0.045, color, 8)
	for side: float in [-1.0, 1.0]:
		_P.path(kit, PackedVector3Array([Vector3(0.0, 0.7, 0.0), Vector3(side * 0.12, 0.82, 0.0), Vector3(side * 0.16, 0.95, 0.0), Vector3(side * 0.1, 1.05, 0.0)]), 0.02, color, 4)
		_P.ball(kit, Vector3(side * 0.1, 1.05, 0.0), Vector3(0.03, 0.03, 0.03), gold, 0)
	_P.slab(kit, Vector3(0.0, 1.2, 0.0), Vector3(0.28, 0.22, 0.54), color)
	_P.bar(kit, Vector3(0.0, 1.31, -0.27), Vector3(0.0, 1.31, 0.27), 0.14, color, 10)
	_P.slab(kit, Vector3(0.0, 1.2, -0.275), Vector3(0.24, 0.26, 0.02), color.lightened(0.06))
	_P.slab(kit, Vector3(0.0, 1.2, -0.29), Vector3(0.08, 0.02, 0.01), gold)
	_P.cone(kit, Vector3(0.0, 1.44, 0.0), 0.05, 0.16, gold, 6)
	_P.ball(kit, Vector3(0.0, 1.62, 0.0), Vector3(0.035, 0.035, 0.035), gold, 0)


## Lakeside's: a little striped lighthouse with the box set into its side.
static func _mailbox_lighthouse(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.08, 0.0), Vector3(0.6, 0.16, 0.6), _P.STONE)
	for band: int in 4:
		var y := 0.16 + float(band) * 0.3
		var r := 0.26 - float(band) * 0.03
		kit.tube(PackedVector3Array([Vector3(0.0, y, 0.0), Vector3(0.0, y + 0.3, 0.0)]), PackedFloat32Array([r, r - 0.03]), color if band % 2 == 0 else _P.WHITE, 10, {"jitter": 0.0, "cap": band == 3, "cap_start": band == 0})
	_P.disc(kit, Vector3(0.0, 1.38, 0.0), 0.2, 0.04, _P.BLACK, 10)
	_P.post(kit, Vector3(0.0, 1.4, 0.0), 0.26, 0.11, Color(0.95, 0.9, 0.6), 8)
	_P.cone(kit, Vector3(0.0, 1.66, 0.0), 0.16, 0.2, _P.BLACK, 8)
	_P.slab(kit, Vector3(0.0, 0.8, -0.2), Vector3(0.22, 0.2, 0.12), _P.STEEL.darkened(0.2))
	_P.slab(kit, Vector3(0.0, 0.8, -0.265), Vector3(0.2, 0.18, 0.02), _P.BLACK)


## A rolling trash bin: lid hinged at the back (+Z), two wheels at the back.
static func _wheelie_bin(kit: _MeshKit, color: Color) -> void:
	_P.soft(kit, Vector3(0.0, 0.5, 0.0), Vector3(0.58, 0.92, 0.68), color, 6.0, 1)
	_P.slab(kit, Vector3(0.0, 0.98, -0.02), Vector3(0.64, 0.06, 0.78), color.darkened(0.12))
	_P.slab(kit, Vector3(0.0, 0.94, -0.4), Vector3(0.4, 0.06, 0.04), color.darkened(0.3))
	_P.bar(kit, Vector3(-0.28, 0.96, 0.4), Vector3(0.28, 0.96, 0.4), 0.025, color.darkened(0.3), 6)
	for side: float in [-1.0, 1.0]:
		_P.wheel(kit, Vector3(side * 0.31, 0.1, 0.3), 0.1, 0.06, _P.TIRE, _P.DARK_STEEL)


# ---------------------------------------------------------------- lamps (heads glow via PropCatalog.place)

## The cobra-head street lamp: a pole, an arm reaching forward (-Z), and the head.
## The lit lens (place()) sits under the head at (0, 4.98, -1.25).
static func _lamp_cobra(kit: _MeshKit, color: Color) -> void:
	_P.taper(kit, Vector3.ZERO, 0.5, 0.17, 0.14, color, 8)
	_P.taper(kit, Vector3(0.0, 0.5, 0.0), 4.7, 0.11, 0.08, color, 8)
	_P.path(kit, PackedVector3Array([Vector3(0.0, 5.0, 0.0), Vector3(0.0, 5.2, -0.3), Vector3(0.0, 5.18, -1.0)]), 0.05, color, 6)
	_P.soft(kit, Vector3(0.0, 5.1, -1.25), Vector3(0.44, 0.2, 0.66), color, 4.0, 1)


## The acorn lamp: a fluted post on a bell base, the glowing acorn globe (place())
## at (0, 3.55, 0), and a crown with a finial.
static func _lamp_acorn(kit: _MeshKit, color: Color) -> void:
	_P.taper(kit, Vector3.ZERO, 0.55, 0.22, 0.12, color, 8)
	_P.disc(kit, Vector3(0.0, 0.58, 0.0), 0.15, 0.05, color, 8)
	_P.taper(kit, Vector3(0.0, 0.6, 0.0), 2.6, 0.08, 0.065, color, 8)
	_P.disc(kit, Vector3(0.0, 3.22, 0.0), 0.14, 0.06, color, 8)
	_P.cone(kit, Vector3(0.0, 3.92, 0.0), 0.2, 0.18, color, 8)
	_P.post(kit, Vector3(0.0, 4.08, 0.0), 0.14, 0.02, color, 4)
	_P.ball(kit, Vector3(0.0, 4.24, 0.0), Vector3(0.04, 0.04, 0.04), color, 0)


## Mansion Hill's lantern lamp: a tall black post with a square lantern on top;
## the lit glass (place()) is the lantern's middle at (0, 3.5, 0).
static func _lamp_lantern(kit: _MeshKit, color: Color) -> void:
	_P.slab(kit, Vector3(0.0, 0.15, 0.0), Vector3(0.34, 0.3, 0.34), color)
	_P.taper(kit, Vector3(0.0, 0.3, 0.0), 2.9, 0.07, 0.055, color, 8)
	_lantern(kit, Vector3(0.0, 3.2, 0.0), color)


## Lakeside's: a fieldstone base with a short wooden post and a lantern; lit
## glass at (0, 2.5, 0).
static func _lamp_post_lantern(kit: _MeshKit, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	_P.slab(kit, Vector3(0.0, 0.5, 0.0), Vector3(0.62, 1.0, 0.62), _P.STONE)
	for index: int in 10:
		var face := index % 4
		var at := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.15, 0.85), 0.315)
		var turned := Basis(Vector3.UP, float(face) * PI * 0.5)
		_P.slab(kit, turned * at, Vector3(0.18, 0.12, 0.02), _P.vary(_P.STONE, rng, 0.14), turned)
	_P.slab(kit, Vector3(0.0, 1.04, 0.0), Vector3(0.7, 0.08, 0.7), _P.STONE.darkened(0.1))
	_P.slab(kit, Vector3(0.0, 1.6, 0.0), Vector3(0.16, 1.1, 0.16), _P.WOOD.darkened(0.2))
	_lantern(kit, Vector3(0.0, 2.2, 0.0), color)


static func _lantern(kit: _MeshKit, base: Vector3, color: Color) -> void:
	_P.slab(kit, base + Vector3(0.0, 0.03, 0.0), Vector3(0.34, 0.06, 0.34), color)
	for x: float in [-0.15, 0.15]:
		for z: float in [-0.15, 0.15]:
			_P.slab(kit, base + Vector3(x, 0.3, z), Vector3(0.035, 0.54, 0.035), color)
	_P.cone(kit, base + Vector3(0.0, 0.57, 0.0), 0.28, 0.24, color, 4, 0.04)
	_P.ball(kit, base + Vector3(0.0, 0.86, 0.0), Vector3(0.04, 0.05, 0.04), color, 0)


## A wooden utility pole: a crossarm with three insulators at WIRE_HEIGHT, a
## transformer can, and climbing spikes.
static func _power_pole(kit: _MeshKit, color: Color) -> void:
	kit.tube(PackedVector3Array([Vector3.ZERO, Vector3(0.0, 9.2, 0.0)]), PackedFloat32Array([0.16, 0.11]), color, 7, {"jitter": 0.0, "cap": true})
	_P.slab(kit, Vector3(0.0, 8.4, 0.0), Vector3(2.0, 0.12, 0.12), color.darkened(0.1))
	for side: float in [-1.0, 1.0]:
		_P.path(kit, PackedVector3Array([Vector3(side * 0.7, 8.38, 0.0), Vector3(0.0, 7.8, 0.0)]), 0.025, _P.DARK_STEEL, 4)
	for x: float in [-WIRE_SPREAD, 0.0, WIRE_SPREAD]:
		var top := 8.46 if x != 0.0 else 9.2
		_P.taper(kit, Vector3(x, top, 0.0), 0.12, 0.05, 0.035, Color(0.36, 0.5, 0.42), 6)
	_P.post(kit, Vector3(0.0, 6.4, 0.24), 0.75, 0.2, Color(0.55, 0.57, 0.58), 8)
	_P.slab(kit, Vector3(0.0, 6.8, 0.12), Vector3(0.08, 0.6, 0.1), _P.DARK_STEEL)
	for step: int in 6:
		var y := 2.4 + float(step) * 0.5
		var side := 1.0 if step % 2 == 0 else -1.0
		_P.bar(kit, Vector3(side * 0.1, y, 0.0), Vector3(side * 0.3, y, 0.0), 0.015, _P.DARK_STEEL, 4)


# ---------------------------------------------------------------- signs (text via PropCatalog.place)

## A street name post: two green blades crossed at the top (labels at
## (0, 2.82, -0.02) and turned 90 degrees at (0.02, 2.6, 0)).
static func _street_sign(kit: _MeshKit, color: Color) -> void:
	_P.post(kit, Vector3.ZERO, 2.95, 0.035, _P.STEEL, 6)
	_P.slab(kit, Vector3(0.0, 2.82, 0.0), Vector3(1.0, 0.2, 0.025), color)
	_P.slab(kit, Vector3(0.0, 2.6, 0.0), Vector3(0.025, 0.2, 1.0), color)
	_P.cone(kit, Vector3(0.0, 2.95, 0.0), 0.05, 0.06, _P.STEEL, 6)


## A stop sign: a red octagon with a white rim (the word via place()).
static func _stop_sign(kit: _MeshKit) -> void:
	_P.post(kit, Vector3(0.0, 0.0, 0.06), 2.3, 0.035, _P.STEEL, 6)
	kit.tube(PackedVector3Array([Vector3(0.0, 2.1, 0.02), Vector3(0.0, 2.1, -0.0)]), PackedFloat32Array([0.4, 0.4]), _P.WHITE, 8, {"jitter": 0.0, "cap": true, "cap_start": true})
	kit.tube(PackedVector3Array([Vector3(0.0, 2.1, -0.0), Vector3(0.0, 2.1, -0.015)]), PackedFloat32Array([0.36, 0.36]), SIGN_RED, 8, {"jitter": 0.0, "cap": true, "cap_start": false})


## A white regulatory sign on a post (SPEED LIMIT, via place()).
static func _speed_sign(kit: _MeshKit) -> void:
	_P.post(kit, Vector3(0.0, 0.0, 0.05), 2.3, 0.035, _P.STEEL, 6)
	_P.slab(kit, Vector3(0.0, 1.95, 0.0), Vector3(0.62, 0.78, 0.025), _P.BLACK)
	_P.slab(kit, Vector3(0.0, 1.95, -0.006), Vector3(0.57, 0.73, 0.02), _P.WHITE)


## A speed bump across the road along local x: yellow and black stripes over a
## low hump. size: x = length across the road, y = height, z = depth.
static func _speed_bump(kit: _MeshKit, size: Vector3) -> void:
	var stripes := maxi(4, int(size.x / 0.45))
	var step := size.x / float(stripes)
	for index: int in stripes:
		var x := -size.x * 0.5 + (float(index) + 0.5) * step
		var color := SAFETY_YELLOW if index % 2 == 0 else _P.BLACK.lightened(0.1)
		# A low hump: a flat top and two sloped sides.
		_P.slab(kit, Vector3(x, size.y * 0.5, 0.0), Vector3(step, size.y, size.z * 0.4), color)
		for side: float in [-1.0, 1.0]:
			var a := Vector3(x - step * 0.5, size.y, side * size.z * 0.2)
			var b := Vector3(x + step * 0.5, size.y, side * size.z * 0.2)
			var c := Vector3(x + step * 0.5, 0.0, side * size.z * 0.5)
			var d := Vector3(x - step * 0.5, 0.0, side * size.z * 0.5)
			_P.poly(kit, [a, b, c, d], Vector3(x, 0.0, 0.0), color.darkened(0.08))


static func _bollard(kit: _MeshKit, color: Color) -> void:
	_P.post(kit, Vector3.ZERO, 0.95, 0.11, color, 10)
	_P.ball(kit, Vector3(0.0, 0.95, 0.0), Vector3(0.11, 0.07, 0.11), color, 1)
	_P.post(kit, Vector3(0.0, 0.7, 0.0), 0.08, 0.114, _P.WHITE, 10)


## A curb drain grate (lies in the gutter, top at y 0.03).
static func _storm_drain(kit: _MeshKit) -> void:
	_P.slab(kit, Vector3(0.0, 0.01, 0.0), Vector3(0.9, 0.02, 0.5), _P.STONE.darkened(0.25))
	for index: int in 7:
		_P.slab(kit, Vector3(-0.36 + float(index) * 0.12, 0.025, 0.0), Vector3(0.05, 0.02, 0.44), _P.DARK_STEEL.darkened(0.3))


static func _newspaper_box(kit: _MeshKit, color: Color) -> void:
	for x: float in [-0.18, 0.18]:
		for z: float in [-0.16, 0.16]:
			_P.post(kit, Vector3(x, 0.0, z), 0.42, 0.02, _P.DARK_STEEL, 4)
	_P.slab(kit, Vector3(0.0, 0.8, 0.0), Vector3(0.5, 0.8, 0.44), color)
	_P.slab(kit, Vector3(0.0, 0.92, -0.225), Vector3(0.38, 0.3, 0.02), _P.GLASS)
	_P.slab(kit, Vector3(0.0, 0.62, -0.225), Vector3(0.12, 0.05, 0.03), _P.CHROME)
	_P.slab(kit, Vector3(0.0, 1.22, 0.0), Vector3(0.54, 0.04, 0.48), color.darkened(0.2))


static func _traffic_cone(kit: _MeshKit) -> void:
	_P.slab(kit, Vector3(0.0, 0.02, 0.0), Vector3(0.38, 0.04, 0.38), CONE_ORANGE.darkened(0.2))
	kit.tube(PackedVector3Array([Vector3(0.0, 0.04, 0.0), Vector3(0.0, 0.3, 0.0)]), PackedFloat32Array([0.15, 0.1]), CONE_ORANGE, 10, {"jitter": 0.0, "cap": false})
	kit.tube(PackedVector3Array([Vector3(0.0, 0.3, 0.0), Vector3(0.0, 0.42, 0.0)]), PackedFloat32Array([0.1, 0.075]), _P.WHITE, 10, {"jitter": 0.0, "cap": false})
	kit.tube(PackedVector3Array([Vector3(0.0, 0.42, 0.0), Vector3(0.0, 0.68, 0.0)]), PackedFloat32Array([0.075, 0.025]), CONE_ORANGE, 10, {"jitter": 0.0, "cap": true})


## A bus bench with an ad board for a backrest (the ad text via place()).
static func _bus_bench(kit: _MeshKit, color: Color) -> void:
	for x: float in [-0.85, 0.85]:
		_P.slab(kit, Vector3(x, 0.22, 0.0), Vector3(0.1, 0.44, 0.5), _P.STONE)
	_P.slab(kit, Vector3(0.0, 0.47, 0.0), Vector3(2.0, 0.08, 0.5), _P.WOOD)
	_P.slab(kit, Vector3(0.0, 0.95, 0.24), Vector3(2.0, 0.66, 0.08), color)
	_P.slab(kit, Vector3(0.0, 0.95, 0.195), Vector3(1.86, 0.54, 0.02), _P.WHITE)


## A realtor's yard sign: a white post with an arm and a swinging sign.
static func _for_sale_sign(kit: _MeshKit) -> void:
	_P.slab(kit, Vector3(0.0, 0.7, 0.0), Vector3(0.08, 1.4, 0.08), _P.WHITE)
	_P.slab(kit, Vector3(-0.35, 1.32, 0.0), Vector3(0.78, 0.07, 0.07), _P.WHITE)
	for x: float in [-0.62, -0.18]:
		_P.bar(kit, Vector3(x, 1.28, 0.0), Vector3(x, 1.18, 0.0), 0.008, _P.STEEL, 3)
	_P.slab(kit, Vector3(-0.4, 0.95, 0.0), Vector3(0.62, 0.46, 0.03), SIGN_RED, Basis.IDENTITY, 0.0)
	_P.slab(kit, Vector3(-0.4, 0.95, -0.017), Vector3(0.54, 0.38, 0.01), _P.WHITE)


## A freestanding hoop on a weighted base: a backboard facing -Z and an orange rim.
static func _basketball_hoop(kit: _MeshKit) -> void:
	_P.soft(kit, Vector3(0.0, 0.2, 0.25), Vector3(0.8, 0.4, 1.0), _P.BLACK.lightened(0.15), 4.0, 1)
	_P.path(kit, PackedVector3Array([Vector3(0.0, 0.35, 0.3), Vector3(0.0, 2.6, 0.15), Vector3(0.0, 3.05, -0.05)]), 0.06, _P.DARK_STEEL, 6)
	_P.slab(kit, Vector3(0.0, 3.25, -0.15), Vector3(1.4, 0.9, 0.05), _P.WHITE)
	_P.slab(kit, Vector3(0.0, 3.1, -0.18), Vector3(0.5, 0.36, 0.02), SIGN_RED)
	_P.slab(kit, Vector3(0.0, 3.1, -0.187), Vector3(0.42, 0.28, 0.02), _P.WHITE)
	_P.ring(kit, Vector3(0.0, 3.05, -0.42), 0.23, 0.014, CONE_ORANGE, 12, 4)
	kit.tube(PackedVector3Array([Vector3(0.0, 3.04, -0.42), Vector3(0.0, 2.7, -0.42)]), PackedFloat32Array([0.22, 0.13]), Color(0.96, 0.96, 0.94), 8, {"jitter": 0.0, "cap": false})


# ---------------------------------------------------------------- vehicles (nose at -Z)

## One car body: a soft lower body, a cabin with glass, wheels, bumpers, and
## lights. spec keys (all optional): length, width, body_h, ride (body bottom
## height), wheel (radius), cabin_z (cabin center offset toward the back),
## cabin_len, cabin_h, tail, nose, wood (wagon side panels), open (a
## convertible: seats, no roof), chrome (grille and trim), kayak (roof rack and
## a kayak), blocks (no wheels, on cinder blocks, rusty, hood up).
static func _car(kit: _MeshKit, color: Color, spec: Dictionary) -> void:
	var length := float(spec.get("length", 4.5))
	var width := float(spec.get("width", 1.85))
	var body_h := float(spec.get("body_h", 0.62))
	var wheel := float(spec.get("wheel", 0.34))
	var ride := float(spec.get("ride", 0.32))
	var blocks := bool(spec.get("blocks", false))
	if blocks:
		ride = 0.42
	var cabin_len := float(spec.get("cabin_len", 2.2))
	var cabin_h := float(spec.get("cabin_h", 0.62))
	var cabin_z := float(spec.get("cabin_z", 0.2))
	var top := ride + body_h
	var half_l := length * 0.5
	var half_w := width * 0.5
	_P.soft(kit, Vector3(0.0, ride + body_h * 0.5, 0.0), Vector3(width, body_h, length), color, 5.0, 2)
	if bool(spec.get("open", false)):
		for z: float in [cabin_z - 0.45, cabin_z + 0.35]:
			for side: float in [-0.42, 0.42]:
				_P.soft(kit, Vector3(side, top + 0.05, z), Vector3(0.6, 0.2, 0.55), Color(0.55, 0.36, 0.24), 4.0, 1)
				_P.soft(kit, Vector3(side, top + 0.32, z + 0.24), Vector3(0.56, 0.5, 0.14), Color(0.55, 0.36, 0.24), 4.0, 1)
		_P.slab(kit, Vector3(0.0, top + 0.22, cabin_z - cabin_len * 0.5 - 0.15), Vector3(width * 0.86, 0.4, 0.04), _P.GLASS, Basis(Vector3.RIGHT, -0.35))
	else:
		_cabin(kit, Vector3(0.0, top, cabin_z), Vector3(width * 0.86, cabin_h, cabin_len), color)
	# Bumpers and lights.
	var trim := _P.CHROME if bool(spec.get("chrome", false)) else Color(0.25, 0.25, 0.26)
	_P.slab(kit, Vector3(0.0, ride + 0.1, -half_l - 0.02), Vector3(width * 0.96, 0.16, 0.14), trim)
	_P.slab(kit, Vector3(0.0, ride + 0.1, half_l + 0.02), Vector3(width * 0.96, 0.16, 0.14), trim)
	_P.slab(kit, Vector3(0.0, ride + body_h * 0.45, -half_l - 0.01), Vector3(width * 0.36, body_h * 0.32, 0.04), _P.CHROME if bool(spec.get("chrome", false)) else Color(0.14, 0.14, 0.15))
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * half_w * 0.68, ride + body_h * 0.62, -half_l - 0.005), Vector3(0.34, 0.12, 0.04), Color(1.0, 0.95, 0.8))
		_P.slab(kit, Vector3(side * half_w * 0.7, ride + body_h * 0.62, half_l + 0.005), Vector3(0.3, 0.12, 0.04), Color(0.85, 0.15, 0.1))
		# Door seams and handles.
		_P.slab(kit, Vector3(side * (half_w + 0.004), ride + body_h * 0.55, cabin_z - cabin_len * 0.1), Vector3(0.02, body_h * 0.7, 0.03), color.darkened(0.25))
		_P.slab(kit, Vector3(side * (half_w + 0.01), ride + body_h * 0.72, cabin_z - cabin_len * 0.3), Vector3(0.02, 0.04, 0.14), _P.CHROME)
		if bool(spec.get("wood", false)):
			_P.slab(kit, Vector3(side * (half_w + 0.006), ride + body_h * 0.5, 0.0), Vector3(0.02, body_h * 0.55, length * 0.82), Color(0.55, 0.36, 0.2))
			_P.slab(kit, Vector3(side * (half_w + 0.012), ride + body_h * 0.5, 0.0), Vector3(0.02, body_h * 0.6, 0.05), Color(0.86, 0.78, 0.6))
		for z: float in [-half_l * 0.62, half_l * 0.62]:
			if blocks:
				_P.slab(kit, Vector3(side * half_w * 0.7, 0.21, z), Vector3(0.4, 0.42, 0.2), Color(0.62, 0.62, 0.6))
				_P.slab(kit, Vector3(side * half_w * 0.7, 0.42 + 0.0, z), Vector3(0.36, 0.02, 0.36), Color(0.5, 0.5, 0.48))
			else:
				_P.wheel(kit, Vector3(side * (half_w - 0.12), wheel, z), wheel, 0.24)
	if blocks:
		# Hood up, a missing wheel's spare leaning on a block.
		_P.slab(kit, Vector3(0.0, top + 0.45, -half_l + 0.55), Vector3(width * 0.84, 0.05, 1.1), color.darkened(0.15), Basis(Vector3.RIGHT, -1.0))
		_P.slab(kit, Vector3(0.0, top - 0.02, -half_l + 0.6), Vector3(width * 0.7, 0.12, 0.9), Color(0.2, 0.2, 0.21))
		_P.wheel(kit, Vector3(half_w + 0.3, 0.33, 0.6), 0.32, 0.22)
	if bool(spec.get("kayak", false)):
		var roof := top + cabin_h * 0.95
		for z: float in [cabin_z - 0.6, cabin_z + 0.6]:
			_P.slab(kit, Vector3(0.0, roof + 0.04, z), Vector3(width * 0.95, 0.05, 0.06), _P.BLACK)
		kit.tube(PackedVector3Array([Vector3(0.3, roof + 0.16, cabin_z - 1.9), Vector3(0.3, roof + 0.2, cabin_z - 1.0), Vector3(0.3, roof + 0.2, cabin_z + 1.0), Vector3(0.3, roof + 0.16, cabin_z + 1.9)]),
			PackedFloat32Array([0.02, 0.17, 0.17, 0.02]), Color(0.98, 0.56, 0.12), 6, {"jitter": 0.0})
		kit.tube(PackedVector3Array([Vector3(-0.35, roof + 0.16, cabin_z - 1.8), Vector3(-0.35, roof + 0.2, cabin_z - 0.9), Vector3(-0.35, roof + 0.2, cabin_z + 0.9), Vector3(-0.35, roof + 0.16, cabin_z + 1.8)]),
			PackedFloat32Array([0.02, 0.16, 0.16, 0.02]), Color(0.2, 0.62, 0.72), 6, {"jitter": 0.0})


## A car's greenhouse sitting on the body at bottom: a boxy rounded cabin with a
## windshield, a rear window, and two side windows split by a pillar.
static func _cabin(kit: _MeshKit, bottom: Vector3, size: Vector3, color: Color) -> void:
	var center := bottom + Vector3(0.0, size.y * 0.5 - 0.02, 0.0)
	_P.soft(kit, center, size, color, 7.0, 2)
	var glass_h := size.y * 0.62
	var y := center.y + size.y * 0.02
	_P.slab(kit, Vector3(0.0, y, center.z - size.z * 0.5 + 0.01), Vector3(size.x * 0.82, glass_h, 0.05), _P.GLASS, Basis(Vector3.RIGHT, 0.18))
	_P.slab(kit, Vector3(0.0, y, center.z + size.z * 0.5 - 0.01), Vector3(size.x * 0.78, glass_h * 0.9, 0.05), _P.GLASS, Basis(Vector3.RIGHT, -0.18))
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * (size.x * 0.5 - 0.005), y, center.z), Vector3(0.05, glass_h * 0.92, size.z * 0.8), _P.GLASS)
		_P.slab(kit, Vector3(side * (size.x * 0.5 + 0.01), y, center.z + size.z * 0.05), Vector3(0.04, glass_h, 0.1), color)

## A pickup: a cab, a hood, an open bed with a tailgate.
static func _pickup(kit: _MeshKit, color: Color) -> void:
	var ride := 0.48
	_P.soft(kit, Vector3(0.0, ride + 0.32, -1.25), Vector3(1.95, 0.64, 2.2), color, 5.0, 2)
	_cabin(kit, Vector3(0.0, ride + 0.6, -0.5), Vector3(1.8, 0.78, 1.45), color)
	_P.slab(kit, Vector3(0.0, ride + 0.25, 1.2), Vector3(1.95, 0.5, 2.3), color.darkened(0.06))
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * 0.93, ride + 0.62, 1.2), Vector3(0.09, 0.3, 2.3), color)
		_P.slab(kit, Vector3(side * 0.7, ride + 0.5, -2.36), Vector3(0.34, 0.12, 0.04), Color(1.0, 0.95, 0.8))
		_P.slab(kit, Vector3(side * 0.82, ride + 0.6, 2.36), Vector3(0.16, 0.24, 0.04), Color(0.85, 0.15, 0.1))
		for z: float in [-1.5, 1.4]:
			_P.wheel(kit, Vector3(side * 0.85, 0.4, z), 0.4, 0.28)
	_P.slab(kit, Vector3(0.0, ride + 0.62, 2.33), Vector3(1.86, 0.32, 0.08), color)
	_P.slab(kit, Vector3(0.0, ride + 0.52, 0.03), Vector3(1.8, 0.04, 0.04), color.darkened(0.2))
	_P.slab(kit, Vector3(0.0, ride + 0.12, -2.38), Vector3(1.9, 0.18, 0.14), _P.CHROME)
	_P.slab(kit, Vector3(0.0, ride + 0.12, 2.42), Vector3(1.9, 0.16, 0.12), _P.CHROME)
	_P.slab(kit, Vector3(0.0, ride + 0.42, -2.37), Vector3(0.9, 0.24, 0.04), Color(0.14, 0.14, 0.15))


## A golf cart: a white canopy on posts, a bench, a bag on the back.
static func _golf_cart(kit: _MeshKit, color: Color) -> void:
	_P.soft(kit, Vector3(0.0, 0.42, 0.0), Vector3(1.2, 0.36, 2.3), color, 5.0, 1)
	_P.soft(kit, Vector3(0.0, 0.62, -0.85), Vector3(1.1, 0.3, 0.6), color, 4.0, 1)
	_P.soft(kit, Vector3(0.0, 0.72, 0.15), Vector3(1.0, 0.18, 0.55), Color(0.4, 0.28, 0.2), 4.0, 1)
	_P.slab(kit, Vector3(0.0, 1.02, 0.42), Vector3(1.0, 0.5, 0.1), Color(0.4, 0.28, 0.2))
	for x: float in [-0.52, 0.52]:
		for z: float in [-0.65, 0.45]:
			_P.post(kit, Vector3(x, 0.6, z), 1.15, 0.025, _P.DARK_STEEL, 4)
		_P.wheel(kit, Vector3(x, 0.2, -0.7), 0.2, 0.18)
		_P.wheel(kit, Vector3(x, 0.2, 0.75), 0.2, 0.18)
	_P.slab(kit, Vector3(0.0, 1.8, -0.1), Vector3(1.24, 0.06, 1.6), color)
	_P.slab(kit, Vector3(0.0, 1.2, -0.66), Vector3(0.95, 0.5, 0.03), _P.GLASS, Basis(Vector3.RIGHT, 0.12))
	kit.tube(PackedVector3Array([Vector3(0.0, 0.62, 1.05), Vector3(0.0, 1.35, 1.12)]), PackedFloat32Array([0.16, 0.16]), Color(0.2, 0.36, 0.6), 8, {"jitter": 0.0, "cap_start": true})
	for x: float in [-0.06, 0.04, 0.1]:
		_P.bar(kit, Vector3(x, 1.3, 1.12), Vector3(x * 1.4, 1.62, 1.16), 0.025, _P.CHROME, 4)
		_P.soft(kit, Vector3(x * 1.4, 1.65, 1.16), Vector3(0.08, 0.06, 0.1), _P.BLACK, 3.0, 0)


## A boat on its trailer: a rowboat-sized hull on rails, two wheels, a tongue.
static func _boat_trailer(kit: _MeshKit, color: Color) -> void:
	for side: float in [-0.55, 0.55]:
		_P.slab(kit, Vector3(side, 0.45, 0.2), Vector3(0.08, 0.08, 3.6), _P.DARK_STEEL)
	_P.wheel(kit, Vector3(-0.85, 0.3, 0.6), 0.3, 0.2)
	_P.wheel(kit, Vector3(0.85, 0.3, 0.6), 0.3, 0.2)
	_P.slab(kit, Vector3(0.0, 0.45, 0.6), Vector3(1.8, 0.07, 0.07), _P.DARK_STEEL)
	_P.bar(kit, Vector3(0.0, 0.4, -1.6), Vector3(0.0, 0.42, -3.0), 0.04, _P.DARK_STEEL, 6)
	_P.ball(kit, Vector3(0.0, 0.42, -3.05), Vector3(0.06, 0.06, 0.06), _P.CHROME, 0)
	_hull(kit, Vector3(0.0, 0.5, 0.2), 4.0, 1.5, 0.62, color, Color(0.18, 0.4, 0.62))
	_P.slab(kit, Vector3(0.0, 0.85, 1.9), Vector3(0.24, 0.5, 0.3), _P.BLACK.lightened(0.1))


## A boat hull with its keel at bottom, bow forward (-Z): a flat-bottomed hull of
## five stations with a transom at the stern, a gunwale stripe, and a deck rim.
## Shared with props/estate_props.gd.
static func _hull(kit: _MeshKit, bottom: Vector3, length: float, beam: float, depth: float, color: Color, stripe: Color) -> void:
	var half := length * 0.5
	# Per station: z, half-width at the gunwale, half-width at the bottom, bottom height.
	var stations: Array = [[-half, 0.02, 0.0, depth * 0.62], [-half * 0.62, beam * 0.36, beam * 0.08, depth * 0.2], [-half * 0.1, beam * 0.5, beam * 0.24, 0.0], [half * 0.55, beam * 0.48, beam * 0.24, 0.0], [half, beam * 0.42, beam * 0.22, depth * 0.08]]
	var inside := bottom + Vector3(0.0, depth * 0.5, 0.0)
	for index: int in stations.size() - 1:
		var s0: Array = stations[index]
		var s1: Array = stations[index + 1]
		for side: float in [-1.0, 1.0]:
			var top0 := bottom + Vector3(side * float(s0[1]), depth, float(s0[0]))
			var top1 := bottom + Vector3(side * float(s1[1]), depth, float(s1[0]))
			var low0 := bottom + Vector3(side * float(s0[2]), float(s0[3]), float(s0[0]))
			var low1 := bottom + Vector3(side * float(s1[2]), float(s1[3]), float(s1[0]))
			var band0 := top0.lerp(low0, 0.22)
			var band1 := top1.lerp(low1, 0.22)
			_P.poly(kit, [top0, top1, band1, band0], inside, stripe)
			_P.poly(kit, [band0, band1, low1, low0], inside, color)
		var b0l := bottom + Vector3(-float(s0[2]), float(s0[3]), float(s0[0]))
		var b0r := bottom + Vector3(float(s0[2]), float(s0[3]), float(s0[0]))
		var b1l := bottom + Vector3(-float(s1[2]), float(s1[3]), float(s1[0]))
		var b1r := bottom + Vector3(float(s1[2]), float(s1[3]), float(s1[0]))
		_P.poly(kit, [b0l, b0r, b1r, b1l], inside, color.darkened(0.25))
	var stern: Array = stations[stations.size() - 1]
	var z := float(stern[0])
	_P.poly(kit, [bottom + Vector3(-float(stern[1]), depth, z), bottom + Vector3(float(stern[1]), depth, z), bottom + Vector3(float(stern[2]), float(stern[3]), z), bottom + Vector3(-float(stern[2]), float(stern[3]), z)], inside, color.darkened(0.1))
	# The inside floor and the gunwale rim, so it reads open from above.
	_P.slab(kit, bottom + Vector3(0.0, depth * 0.45, half * 0.15), Vector3(beam * 0.7, 0.03, length * 0.66), _P.WOOD.lightened(0.05))
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, bottom + Vector3(side * beam * 0.47, depth + 0.02, half * 0.18), Vector3(0.06, 0.05, length * 0.62), stripe.darkened(0.2))