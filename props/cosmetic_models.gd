extends RefCounted

## Authority: local, cosmetic. How Homie Depot shows its workwear and Chefty's
## paint (docs/GAME.md "Cosmetics"; gap-specs shops chunk 7), for
## props/shelf_stock.gd's slots on the hat rack, the shirt cubby and the paint
## counter (levels/dressing/wardrobe.gd), and the studio:
##   a hat     on a foam display head (player/hats.gd display_mesh)
##   a shirt   folded flat, in its dye (Constants.SHIRT_DYES), or the hi-vis vest
##   a paint   a paint can with the color running down its side and on its lid
##   a decal   a sample card on a little easel: a red Chefty panel wearing it
## Every node's mesh faces -Z and stands on y 0. Cached by item.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Hats = preload("res://player/hats.gd")
## How big a hat's display head stands on the rack (a real head is too big for a peg).
const HAT_DISPLAY_SCALE: float = 0.5
const CAN_METAL := Color(0.72, 0.73, 0.75)
const CARD_RED := Color(0.75, 0.22, 0.15)
const EASEL := Color(0.45, 0.32, 0.2)
const HIVIS := Color(0.82, 0.98, 0.16)
const SILVER := Color(0.86, 0.88, 0.9)

static var _cache: Dictionary = {}


## Whether this catalog item has a display model here.
static func has(item: String) -> bool:
	var kind := str(Catalog.item(item).get("kind", ""))
	return kind == "cosmetic" or kind == "truck_cosmetic"


## A catalog item's display, or null. A hat's node carries the meta
## "display_scale": shelf_stock.gd stands it at that size instead of fitting it.
static func node(item: String) -> MeshInstance3D:
	var mesh := mesh_for(item)
	if mesh == null:
		return null
	var view := _Stylized.instance(mesh, {"roughness": 0.6, "specular": 0.25})
	view.name = "Display"
	if str(Catalog.item(item).get("slot", "")) == "hat":
		view.set_meta("display_scale", HAT_DISPLAY_SCALE)
	return view


static func mesh_for(item: String) -> ArrayMesh:
	if _cache.has(item):
		return _cache[item]
	var entry := Catalog.item(item)
	var mesh: ArrayMesh = null
	match str(entry.get("slot", "")):
		"hat":
			var display := _Hats.display_mesh(str(entry.get("style", "")))
			# Stand it on its neck's foot at y 0.
			mesh = _Hats.merged([[display, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.32, 0.0))]])
		"shirt":
			var which: Variant = entry.get("shirt", 0)
			mesh = folded_shirt(HIVIS if str(which) == "hivis" else Constants.SHIRT_DYES[clampi(int(which), 0, Constants.SHIRT_DYES.size() - 1)], str(which) == "hivis")
		"paint":
			mesh = paint_can(Constants.CHEFTY_PAINTS.get(item, CARD_RED))
		"decal":
			mesh = decal_card(item)
	_cache[item] = mesh
	return mesh


## A shirt folded flat: the body, the collar, the folded-in sleeves; a vest gets
## its reflective bands across instead of sleeves.
static func folded_shirt(color: Color, vest: bool) -> ArrayMesh:
	var kit := _MeshKit.new()
	# Two layers, as a folded shirt is: the folded body and the top fold over it.
	kit.rbox(Vector3(0.0, 0.025, 0.0), Vector3(0.15, 0.025, 0.12), color.darkened(0.08), 6.0, {"detail": 1})
	kit.rbox(Vector3(0.0, 0.058, 0.004), Vector3(0.145, 0.014, 0.115), color, 6.0, {"detail": 1})
	if vest:
		for z: float in [-0.04, 0.05]:
			kit.box(Vector3(0.0, 0.073, z), Vector3(0.28, 0.006, 0.03), SILVER)
		kit.box(Vector3(0.0, 0.074, -0.08), Vector3(0.012, 0.004, 0.07), Color(0.3, 0.32, 0.3))
	else:
		# The collar at the front edge, and the sleeves' fold lines.
		kit.tube(PackedVector3Array([Vector3(-0.055, 0.072, -0.1), Vector3(0.0, 0.078, -0.118), Vector3(0.055, 0.072, -0.1)]), PackedFloat32Array([0.013]), color.darkened(0.18), 6, {"jitter": 0.0})
		for side: float in [-1.0, 1.0]:
			kit.box(Vector3(side * 0.085, 0.073, 0.01), Vector3(0.01, 0.004, 0.2), color.darkened(0.22))
	return kit.commit()


## A one-gallon can: steel, a label band in the paint's color, the lid with a
## puddle of it, and a drip running down the side.
static func paint_can(color: Color) -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.tube(PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.17, 0.0)]), PackedFloat32Array([0.1, 0.1]), CAN_METAL, 14, {"jitter": 0.0, "cap": true, "cap_start": true, "wobble": 0.0})
	kit.tube(PackedVector3Array([Vector3(0.0, 0.035, 0.0), Vector3(0.0, 0.135, 0.0)]), PackedFloat32Array([0.102, 0.102]), color, 14, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	kit.tube(PackedVector3Array([Vector3(0.0, 0.17, 0.0), Vector3(0.0, 0.18, 0.0)]), PackedFloat32Array([0.098, 0.095]), CAN_METAL.darkened(0.15), 14, {"jitter": 0.0, "cap": true, "wobble": 0.0})
	kit.blob(Vector3(0.02, 0.183, -0.01), Vector3(0.06, 0.006, 0.05), color, {"detail": 1, "lumps": 0.3, "flat": false, "jitter": 0.0, "shade": false})
	kit.tube(PackedVector3Array([Vector3(0.03, 0.18, -0.097), Vector3(0.032, 0.15, -0.102), Vector3(0.03, 0.12, -0.102)]), PackedFloat32Array([0.009, 0.008, 0.011]), color, 6, {"jitter": 0.0})
	# The wire handle, lying back over the lid.
	kit.tube(PackedVector3Array([Vector3(-0.1, 0.15, 0.0), Vector3(-0.07, 0.19, 0.06), Vector3(0.0, 0.2, 0.08), Vector3(0.07, 0.19, 0.06), Vector3(0.1, 0.15, 0.0)]), PackedFloat32Array([0.004]), CAN_METAL.darkened(0.3), 4, {"jitter": 0.0})
	return kit.commit()


## A sample card on an easel: a red panel (Chefty's factory paint) wearing the decal.
static func decal_card(item: String) -> ArrayMesh:
	var kit := _MeshKit.new()
	var tilt := Basis(Vector3.RIGHT, -0.25)
	var middle := Vector3(0.0, 0.17, 0.0)
	kit.box(middle, Vector3(0.3, 0.22, 0.014), CARD_RED, tilt)
	# The easel: two legs in front, one behind.
	for side: float in [-1.0, 1.0]:
		kit.tube(PackedVector3Array([Vector3(side * 0.1, 0.0, -0.04), Vector3(side * 0.1, 0.28, 0.03)]), PackedFloat32Array([0.008]), EASEL, 5, {"jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0.0, 0.0, 0.12), Vector3(0.0, 0.26, 0.03)]), PackedFloat32Array([0.008]), EASEL, 5, {"jitter": 0.0})
	kit.box(Vector3(0.0, 0.06, -0.05), Vector3(0.26, 0.012, 0.03), EASEL)
	var front := func(x: float, y: float, out: float) -> Vector3: return middle + tilt * Vector3(x, y, -0.008 - out)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(item)
	match item:
		"decal_stripes":
			for x: float in [-0.04, 0.04]:
				kit.box(front.call(x, 0.0, 0.002), Vector3(0.05, 0.22, 0.004), Color(0.95, 0.94, 0.9), tilt)
		"decal_googly":
			for x: float in [-0.065, 0.065]:
				kit.blob(front.call(x, 0.0, 0.006), Vector3(0.05, 0.05, 0.012), Color(0.98, 0.98, 0.96), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
				kit.blob(front.call(x + 0.01, -0.02, 0.018), Vector3(0.022, 0.022, 0.006), Color(0.06, 0.05, 0.06), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
		"decal_flames":
			for index: int in 4:
				var x := -0.11 + float(index) * 0.065
				var tall := 0.09 + 0.04 * float(index % 2)
				for layer: int in 2:
					var shrink := 1.0 if layer == 0 else 0.55
					var color := Color(0.98, 0.4, 0.08) if layer == 0 else Color(1.0, 0.85, 0.2)
					var a: Vector3 = front.call(x - 0.03 * shrink, -0.09, 0.003 + 0.002 * layer)
					var b: Vector3 = front.call(x + 0.03 * shrink, -0.09, 0.003 + 0.002 * layer)
					var tip: Vector3 = front.call(x + 0.03, -0.09 + tall * shrink, 0.003 + 0.002 * layer)
					var normal := tilt * Vector3.FORWARD
					if ((tip - a).cross(b - a)).dot(normal) < 0.0:
						kit.triangle(a, tip, b, normal, color)
					else:
						kit.triangle(a, b, tip, normal, color)
		"decal_leaves":
			var autumn: Array[Color] = [Color(0.93, 0.48, 0.12), Color(0.96, 0.76, 0.2), Color(0.62, 0.3, 0.12)]
			for index: int in 9:
				kit.leaf_card(front.call(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.08, 0.08), 0.004), tilt * Vector3.FORWARD, 0.035, autumn[index % autumn.size()], 0.0, rng.randf_range(0.0, TAU))
		"decal_rust":
			for index: int in 6:
				kit.blob(front.call(rng.randf_range(-0.11, 0.11), rng.randf_range(-0.08, 0.08), 0.003), Vector3(rng.randf_range(0.02, 0.04), rng.randf_range(0.02, 0.035), 0.004), Color(0.5, 0.27, 0.12), {"detail": 1, "lumps": 0.35, "flat": true, "jitter": 0.1, "shade": false, "seed": index})
	return kit.commit()
