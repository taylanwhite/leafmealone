extends RefCounted

## Authority: local, cosmetic. Modeled meshes for things in and around the yard,
## built with props/mesh_kit.gd and drawn with props/stylized.gd: the rake, leaf
## bags, trash cans, the wheelbarrow, the gnome, hiding spots (a shed, a wheelie
## dumpster, a hedge), cars, and fence runs. Each returns a node to add where it
## goes; meshes are cached per kind and color, so many copies cost one build.
## Art rules: docs/ART.md. 1 unit = 1 meter, Y up, faces -Z, origin at the base.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
## The shops' models (the gas can lives there now; gap-specs shops chunk 4).
const _ShopModels = preload("res://props/shop_models.gd")

const WOOD := Color(0.66, 0.48, 0.3)
const STEEL := Color(0.62, 0.64, 0.66)
const KRAFT := Color(0.72, 0.55, 0.34)
const LEAVES: Array[Color] = [Color(0.9, 0.48, 0.15), Color(0.93, 0.72, 0.22), Color(0.75, 0.25, 0.14)]
const SMOOTH := {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0}
## Where each tool's tier trim goes: the main body boxes of its model below, as
## [center, half extents] (tool space, faces -Z). Mk II gets a chrome stripe
## over each; Mk III a black shell, a gold stripe and flames down the sides; a
## used one rust blotches and a strip of duct tape.
const TIER_TRIM: Dictionary = {
	"leaf_blower": [[Vector3(0.0, 0.2, 0.08), Vector3(0.14, 0.16, 0.18)]],
	"lawn_mower": [[Vector3(0.0, 0.2, 0.0), Vector3(0.3, 0.08, 0.32)]],
	"ladder": [[Vector3(-0.22, 0.0, 0.0), Vector3(0.025, 0.05, 1.2)], [Vector3(0.22, 0.0, 0.0), Vector3(0.025, 0.05, 1.2)]],
	"hose": [[Vector3(0.0, 0.3, 0.0), Vector3(0.17, 0.035, 0.035)]],
	"pressure_washer": [[Vector3(0.0, 0.38, 0.0), Vector3(0.22, 0.24, 0.18)]],
	"hedge_trimmer": [[Vector3(0.0, 0.15, 0.12), Vector3(0.09, 0.09, 0.16)]],
	"paint_roller": [[Vector3(0.0, 0.0, 0.15), Vector3(0.024, 0.024, 0.15)]],
}
const CHROME := Color(0.86, 0.88, 0.92)
const GOLD := Color(0.93, 0.74, 0.22)
const MK3_BLACK := Color(0.1, 0.1, 0.11)
const RUST := Color(0.5, 0.27, 0.12)
const TAPE := Color(0.6, 0.62, 0.64)
const FLAMES: Array[Color] = [Color(0.92, 0.2, 0.08), Color(0.98, 0.52, 0.1), Color(1.0, 0.85, 0.25)]
## Trim pieces stay low-poly: a tool is small and there are seven of them.
const TRIM_DETAIL := {"detail": 1}
const TRIM_BLOB := {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0}

static var _cache: Dictionary = {}


## tier dresses one of the seven tools (TIER_TRIM): 0 used, 1 stock (none), 2 Mk
## II, 3 Mk III. Anything else ignores it.
static func node(kind: String, color: Color = Color.WHITE, size: Vector3 = Vector3.ONE, options: Dictionary = {}, tier: int = 1) -> MeshInstance3D:
	# The rake wears its tier too (fx-chefty: on Chefty's rack a Mk II and The
	# Leafinator looked like stock rakes): its head, tines and handle (_rake).
	var trim := tier if (TIER_TRIM.has(kind) or kind == "rake") and tier != 1 else 1
	var key := "%s|%s|%s" % [kind, color.to_html(), size]
	if trim != 1:
		key += "|tier%d" % trim
	if not _cache.has(key):
		_cache[key] = _build(kind, color, size, trim)
	return _Stylized.instance(_cache[key], options if not options.is_empty() else {"roughness": 0.8, "specular": 0.15})


static func _build(kind: String, color: Color, size: Vector3, tier: int = 1) -> ArrayMesh:
	var kit := _MeshKit.new()
	if kind == "rake":
		var head := rake_head_of(tier)
		_rake(kit, "", Constants.RAKE_HEAD_WIDTHS[head], Constants.RAKE_TINES[head], head, tier)
		return kit.commit()
	_build_kind(kit, kind, color, size)
	if tier != 1 and TIER_TRIM.has(kind):
		_tier_trim(kit, kind, tier)
	return kit.commit()


static func _build_kind(kit: RefCounted, kind: String, color: Color, size: Vector3) -> void:
	match kind:
		"rake":
			_rake(kit)
		"leaf_bag":
			_leaf_bag(kit)
		"trash":
			_trash_can(kit, color)
		"wheelbarrow":
			_wheelbarrow(kit, color)
		"gnome":
			_gnome(kit)
		"shed":
			_shed(kit, color, size)
		"dumpster":
			_dumpster(kit, color, size)
		"hedge":
			_hedge(kit, color, size)
		"car":
			_car(kit, color)
		"fence":
			_fence(kit, color, size)
		"leaf_blower":
			_leaf_blower(kit)
		"lawn_mower":
			_lawn_mower(kit)
		"ladder":
			_ladder(kit)
		"hose":
			_hose(kit)
		"pressure_washer":
			_pressure_washer(kit)
		"hedge_trimmer":
			_hedge_trimmer(kit)
		"paint_roller":
			_paint_roller(kit)
		"hydrant":
			_hydrant(kit)
		"spigot":
			_spigot(kit)
		"water_tank":
			_water_tank(kit)
		"nozzle":
			_nozzle(kit)
		"wand":
			_wand(kit)
		"paint_bucket":
			_paint_bucket(kit)
		"gas_can":
			_ShopModels.gas_can(kit)
		_:
			kit.call("rbox", Vector3(0.0, size.y * 0.5, 0.0), size * 0.5, color, 6.0)


## A tool's tier, worn on its body boxes (TIER_TRIM): Mk II a chrome racing
## stripe and pinstripes, Mk III a black shell with a gold stripe and flames
## licking back from the front, a used one rust blotches and duct tape. Thin
## bodies (ladder rails, the hose reel's axle, the roller's handle) get rings
## instead of stripes.
static func _tier_trim(kit: RefCounted, kind: String, tier: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([kind, tier])
	for body: Array in (TIER_TRIM[kind] as Array):
		var center: Vector3 = body[0]
		var half: Vector3 = body[1]
		var thin := minf(half.x, half.y) < 0.06
		match tier:
			Catalog.TIER_MK2:
				_trim_stripes(kit, center, half, thin, CHROME)
			Catalog.TIER_MK3:
				kit.call("rbox", center, half + Vector3(0.012, 0.012, 0.012), MK3_BLACK, 5.0, {"detail": 2})
				_trim_stripes(kit, center, half + Vector3(0.012, 0.012, 0.012), thin, GOLD)
				if not thin:
					_trim_flames(kit, center, half + Vector3(0.012, 0.012, 0.012))
			Catalog.TIER_USED:
				# A strip of duct tape slapped round the middle, a bit crooked, and
				# rust where it scraped.
				kit.call("rbox", center, Vector3(half.x + 0.012, half.y + 0.012, maxf(0.03, half.z * 0.16)), TAPE, 4.0, {"detail": 2, "basis": Basis(Vector3.RIGHT, 0.22)})
				for index: int in 3:
					var side := -1.0 if index % 2 == 0 else 1.0
					var along := rng.randf_range(-0.7, 0.7) * half.z
					var up := rng.randf_range(-0.5, 0.5) * half.y
					var size := Vector3(0.008, maxf(half.y * 0.25, 0.01), maxf(half.z * 0.18, 0.012))
					kit.call("blob", center + Vector3(side * (half.x + 0.004), up, along), size, RUST.darkened(rng.randf_range(0.0, 0.2)), TRIM_BLOB)


## Racing stripes on a body box: one down the middle of the top and a pinstripe
## along each side. A thin body gets three rings instead.
static func _trim_stripes(kit: RefCounted, center: Vector3, half: Vector3, thin: bool, color: Color) -> void:
	if thin:
		for t: float in [-0.55, 0.0, 0.55]:
			kit.call("rbox", center + Vector3(0.0, 0.0, t * half.z), Vector3(half.x + 0.006, half.y + 0.006, 0.012), color, 4.0, TRIM_DETAIL)
		return
	# Kept short of the rounded ends, so nothing sticks out past the body.
	kit.call("rbox", center + Vector3(0.0, half.y + 0.002, 0.0), Vector3(half.x * 0.2, 0.008, half.z * 0.72), color, 3.0, TRIM_DETAIL)
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", center + Vector3(side * (half.x + 0.002), half.y * 0.35, 0.0), Vector3(0.007, half.y * 0.07, half.z * 0.72), color, 3.0, TRIM_DETAIL)


## Hot-rod flames down both sides of a body box: three tongues streaming back
## from the front (-Z) at different heights and lengths, red with a yellow core.
static func _trim_flames(kit: RefCounted, center: Vector3, half: Vector3) -> void:
	var tongues: Array[Vector2] = [Vector2(-0.45, 0.75), Vector2(-0.05, 1.0), Vector2(0.35, 0.6)]
	for side: float in [-1.0, 1.0]:
		for tongue: Vector2 in tongues:
			var length := half.z * 0.42 * tongue.y
			var front := -half.z * 0.78
			var at := center + Vector3(side * (half.x + 0.003), half.y * tongue.x, front + length)
			kit.call("blob", at, Vector3(0.006, half.y * 0.16, length), FLAMES[0], TRIM_BLOB)
			kit.call("blob", at + Vector3(side * 0.003, 0.0, -length * 0.25), Vector3(0.005, half.y * 0.08, length * 0.6), FLAMES[2], TRIM_BLOB)


## The rake's head bar, where the tine fan pivots (the "Tines" node of rake()).
const RAKE_TINES_PIVOT := Vector3(0.0, 0.1, 0.0)
## The middle tine's curled tip, in the Tines node's space: what touches the leaves.
const RAKE_TINE_TIP := Vector3(0.0, -0.355, -0.115)
## Each rake tier's colors (Constants.RAKE_HEAD_WIDTHS, RAKE_TINES): the starter's
## green tines, the Tune-Up's orange tines and ferrule, The Leafinator's chrome.
const RAKE_TIER_LOOKS: Array[Dictionary] = [
	{"tines": Color(0.25, 0.6, 0.32), "collar": STEEL, "grip": Color(0.85, 0.3, 0.15), "wire": Color(0.53, 0.54, 0.56)},
	{"tines": Color(0.95, 0.52, 0.14), "collar": Color(0.95, 0.52, 0.14), "grip": Color(0.18, 0.18, 0.2), "wire": Color(0.53, 0.54, 0.56)},
	{"tines": CHROME, "collar": CHROME, "grip": Color(0.1, 0.1, 0.11), "wire": GOLD},
]


## The job's one rake, standing up: a wooden handle with a rubber grip, a metal
## collar, and a fan of springy tines curling forward at the tips. part "handle"
## or "tines" builds only that half (the tines about RAKE_TINES_PIVOT, for rake()),
## "" both; width and tines give the tier's head (Constants.RAKE_HEAD_WIDTHS).
static func _rake(kit: RefCounted, part: String = "", width: float = 0.95, tines: int = 15, tier: int = 0, kit_tier: int = 1) -> void:
	var look: Dictionary = RAKE_TIER_LOOKS[clampi(tier, 0, RAKE_TIER_LOOKS.size() - 1)]
	if part != "tines":
		var handle := WOOD.darkened(0.3) if kit_tier == Catalog.TIER_USED else (MK3_BLACK if kit_tier == Catalog.TIER_MK3 else WOOD)
		kit.call("tube", PackedVector3Array([Vector3(0, 0.14, 0), Vector3(0, 0.9, 0), Vector3(0, 1.58, 0)]), PackedFloat32Array([0.022, 0.022, 0.021]), handle, 8, {"jitter": 0.0})
		kit.call("tube", PackedVector3Array([Vector3(0, 1.42, 0), Vector3(0, 1.62, 0)]), PackedFloat32Array([0.03, 0.03]), look["grip"], 8, {"jitter": 0.0, "cap_start": true})
		kit.call("tube", PackedVector3Array([Vector3(0, 0.1, 0), Vector3(0, 0.2, 0)]), PackedFloat32Array([0.03, 0.026]), look["collar"], 8, {"jitter": 0.0, "cap_start": true})
		_rake_handle_trim(kit, kit_tier)
	if part == "handle":
		return
	var shift := -RAKE_TINES_PIVOT if part == "tines" else Vector3.ZERO
	var half := width * 0.5 - 0.02
	var rng := RandomNumberGenerator.new()
	rng.seed = 27
	for index: int in tines:
		var spread := lerpf(-1.0, 1.0, float(index) / float(tines - 1))
		var mid := Vector3(spread * half * 0.5, -0.02, 0.0)
		# A nearly straight tip line, so the whole fan meets flat ground.
		var tip := Vector3(spread * half, -0.22 + absf(spread) * 0.02, -0.05)
		var curl := tip + Vector3(spread * 0.01, -0.035, -0.065)
		# A used rake: three tines straight, the rest have opinions (docs/GAME.md).
		if kit_tier == Catalog.TIER_USED and index % 5 != 2:
			var bend := Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(0.0, 0.04), rng.randf_range(-0.05, 0.05))
			tip += bend
			curl += bend * 1.6
		kit.call("tube", PackedVector3Array([Vector3(spread * 0.02, 0.11, 0.0) + shift, mid + shift, tip + shift, curl + shift]), PackedFloat32Array([0.012, 0.012, 0.011, 0.01]), look["tines"], 5, {"jitter": 0.0})
	# The cross wire that holds the fan in shape.
	var wire := PackedVector3Array()
	var radii := PackedFloat32Array()
	for step: int in 9:
		var spread := lerpf(-1.0, 1.0, float(step) / 8.0)
		wire.append(Vector3(spread * half * 0.74, -0.1 + absf(spread) * 0.012, -0.01) + shift)
		radii.append(0.011)
	kit.call("tube", wire, radii, (look["wire"] as Color).darkened(0.15), 4, {"jitter": 0.0})


## Which head a rake of this kit tier has (0 used and stock, 1 the Mk II's, 2 The
## Leafinator's: Constants.KIT_RAKE_HEAD_BY_TIER).
static func rake_head_of(kit_tier: int) -> int:
	var heads := Constants.KIT_RAKE_HEAD_BY_TIER
	return clampi(heads[clampi(kit_tier, 0, heads.size() - 1)], 0, Constants.RAKE_HEAD_WIDTHS.size() - 1)


## The rake's tier on its handle (fx-chefty), so you can tell them apart in a
## hand, on the rack and lying on a lawn: a used one's handle is dark old wood
## with two wraps of duct tape; the Mk II's has two chrome bands; The
## Leafinator's is black with gold bands and flames licking up from the head.
## Stock is plain wood.
static func _rake_handle_trim(kit: RefCounted, kit_tier: int) -> void:
	match kit_tier:
		Catalog.TIER_USED:
			for wrap: Vector2 in [Vector2(0.62, 0.07), Vector2(1.08, 0.05)]:
				kit.call("tube", PackedVector3Array([Vector3(0.002, wrap.x - wrap.y * 0.5, 0.0), Vector3(-0.002, wrap.x + wrap.y * 0.5, 0.0)]), PackedFloat32Array([0.027, 0.027]), TAPE, 8, {"jitter": 0.0, "cap_start": true})
		Catalog.TIER_MK2:
			for y: float in [0.4, 1.2]:
				kit.call("tube", PackedVector3Array([Vector3(0, y - 0.03, 0), Vector3(0, y + 0.03, 0)]), PackedFloat32Array([0.028, 0.028]), CHROME, 8, {"jitter": 0.0, "cap_start": true})
		Catalog.TIER_MK3:
			for y: float in [0.6, 1.3]:
				kit.call("tube", PackedVector3Array([Vector3(0, y - 0.015, 0), Vector3(0, y + 0.015, 0)]), PackedFloat32Array([0.027, 0.027]), GOLD, 8, {"jitter": 0.0, "cap_start": true})
			# Three tongues of flame up the handle from the collar, all the way round.
			for turn: int in 3:
				var angle := TAU * float(turn) / 3.0
				var out := Vector3(cos(angle), 0.0, sin(angle)) * 0.021
				kit.call("blob", Vector3(0.0, 0.32, 0.0) + out, Vector3(0.012, 0.11, 0.012), FLAMES[0], TRIM_BLOB)
				kit.call("blob", Vector3(0.0, 0.29, 0.0) + out * 1.08, Vector3(0.008, 0.06, 0.008), FLAMES[2], TRIM_BLOB)


## A posable rake for a tier (0 starter, 1 Tune-Up, 2 The Leafinator): the handle,
## and its tine fan as a child "Tines" pivoting at the head bar so it can flex
## (props/rake_motion.gd). Its head (the collar) is at the origin, handle up +Y.
## kit_tier (Catalog.TIER_*, the rake's own) dresses the handle and, used, bends
## the tines (_rake_handle_trim); -1 is the head's own look.
static func rake(tier: int = 0, options: Dictionary = {"roughness": 0.6, "specular": 0.3}, kit_tier: int = -1) -> Node3D:
	tier = clampi(tier, 0, Constants.RAKE_HEAD_WIDTHS.size() - 1)
	var dress := kit_tier if kit_tier >= 0 else Catalog.TIER_STOCK
	var root := Node3D.new()
	root.name = "Rake"
	for part: String in ["handle", "tines"]:
		var key := "rake_%s|tier%d|kit%d" % [part, tier, dress]
		if not _cache.has(key):
			var kit := _MeshKit.new()
			_rake(kit, part, Constants.RAKE_HEAD_WIDTHS[tier], Constants.RAKE_TINES[tier], tier, dress)
			_cache[key] = kit.commit()
		var view := _Stylized.instance(_cache[key], options)
		if part == "tines":
			view.name = "Tines"
			view.position = RAKE_TINES_PIVOT
		else:
			view.name = "Handle"
		root.add_child(view)
	root.set_meta("tier", tier)
	return root


## A brown paper lawn bag, stuffed full, rim rolled over, leaves poking out.
static func _leaf_bag(kit: RefCounted) -> void:
	kit.call("blob", Vector3(0.0, 0.38, 0.0), Vector3(0.27, 0.38, 0.23), KRAFT, {"detail": 2, "lumps": 0.12, "lump_scale": 1.6, "flat": false, "jitter": 0.0, "seed": 3})
	kit.call("rbox", Vector3(0.0, 0.42, 0.0), Vector3(0.25, 0.36, 0.21), KRAFT, 4.0)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.74, 0), Vector3(0, 0.8, 0)]), PackedFloat32Array([0.25, 0.25]), KRAFT.darkened(0.12), 14, {"jitter": 0.0})
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for index: int in 9:
		var at := Vector3(rng.randf_range(-0.16, 0.16), 0.8 + rng.randf_range(0.0, 0.06), rng.randf_range(-0.13, 0.13))
		kit.call("leaf_card", at, Vector3(rng.randf_range(-0.6, 0.6), 1.0, rng.randf_range(-0.6, 0.6)), rng.randf_range(0.07, 0.1), LEAVES[index % LEAVES.size()], 0.0, rng.randf() * TAU)
	# A printed band so it reads as a lawn bag from across the yard.
	kit.call("tube", PackedVector3Array([Vector3(0, 0.3, 0), Vector3(0, 0.38, 0)]), PackedFloat32Array([0.262, 0.262]), Color(0.3, 0.45, 0.22), 14, {"jitter": 0.0, "cap": false})


static func _trash_can(kit: RefCounted, color: Color) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0, 0.66, 0)]), PackedFloat32Array([0.27, 0.31]), color, 16, {"jitter": 0.0, "cap_start": true, "cap": false})
	for y: float in [0.16, 0.36, 0.56]:
		kit.call("tube", PackedVector3Array([Vector3(0, y - 0.015, 0), Vector3(0, y + 0.015, 0)]), PackedFloat32Array([0.285 + y * 0.06, 0.285 + y * 0.06]), color.darkened(0.15), 16, {"jitter": 0.0, "cap": false})
	kit.call("blob", Vector3(0.0, 0.68, 0.0), Vector3(0.34, 0.07, 0.34), color.lightened(0.05), SMOOTH)
	kit.call("rbox", Vector3(0.0, 0.77, 0.0), Vector3(0.11, 0.025, 0.03), color.darkened(0.3), 4.0)
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * 0.33, 0.55, 0.0), Vector3(0.03, 0.025, 0.08), color.darkened(0.3), 4.0)


## Tray up top, one wheel at the front (-Z), handles and legs at the back.
static func _wheelbarrow(kit: RefCounted, color: Color) -> void:
	var tilt := Basis(Vector3.RIGHT, 0.0)
	kit.call("rbox", Vector3(0.0, 0.43, 0.0), Vector3(0.3, 0.035, 0.4), color, 6.0)
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * 0.36, 0.56, 0.0), Vector3(0.03, 0.15, 0.43), color, 6.0, {"basis": Basis(Vector3.FORWARD, side * 0.3)})
	kit.call("rbox", Vector3(0.0, 0.56, -0.46), Vector3(0.36, 0.15, 0.03), color, 6.0, {"basis": Basis(Vector3.RIGHT, -0.35)})
	kit.call("rbox", Vector3(0.0, 0.56, 0.44), Vector3(0.36, 0.15, 0.03), color, 6.0, {"basis": tilt})
	# A rolled rim along the top edge.
	kit.call("rbox", Vector3(0.0, 0.71, 0.45), Vector3(0.42, 0.025, 0.025), color.darkened(0.15), 4.0)
	kit.call("rbox", Vector3(0.0, 0.71, -0.52), Vector3(0.42, 0.025, 0.025), color.darkened(0.15), 4.0)
	for side: float in [-1.0, 1.0]:
		kit.call("tube", PackedVector3Array([Vector3(side * 0.12, 0.3, -0.62), Vector3(side * 0.2, 0.38, 0.0), Vector3(side * 0.24, 0.48, 0.75), Vector3(side * 0.25, 0.52, 0.95)]), PackedFloat32Array([0.022, 0.022, 0.022, 0.026]), WOOD.darkened(0.1), 6, {"jitter": 0.0})
		kit.call("blob", Vector3(side * 0.25, 0.525, 0.98), Vector3(0.03, 0.03, 0.07), Color(0.15, 0.15, 0.16), SMOOTH)
		kit.call("tube", PackedVector3Array([Vector3(side * 0.22, 0.4, 0.35), Vector3(side * 0.24, 0.0, 0.42)]), PackedFloat32Array([0.018, 0.018]), STEEL.darkened(0.3), 6, {"jitter": 0.0})
	kit.call("wheel", Vector3(0.0, 0.19, -0.62), 0.19, 0.1, Color(0.12, 0.12, 0.13), Color(0.8, 0.75, 0.2))


## A garden gnome: red pointy hat, white beard, round nose, blue coat, boots.
static func _gnome(kit: RefCounted) -> void:
	kit.call("blob", Vector3(-0.07, 0.04, -0.03), Vector3(0.07, 0.04, 0.1), Color(0.3, 0.2, 0.15), SMOOTH)
	kit.call("blob", Vector3(0.07, 0.04, -0.03), Vector3(0.07, 0.04, 0.1), Color(0.3, 0.2, 0.15), SMOOTH)
	kit.call("blob", Vector3(0.0, 0.2, 0.0), Vector3(0.17, 0.17, 0.15), Color(0.25, 0.42, 0.78), SMOOTH)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.15, 0), Vector3(0, 0.19, 0)]), PackedFloat32Array([0.175, 0.17]), Color(0.25, 0.2, 0.15), 14, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.43, 0.0), Vector3(0.13, 0.12, 0.12), Color(0.96, 0.8, 0.68), SMOOTH)
	kit.call("blob", Vector3(0.0, 0.33, -0.07), Vector3(0.13, 0.14, 0.08), Color(0.97, 0.97, 0.95), {"detail": 2, "lumps": 0.2, "lump_scale": 3.0, "outward": true, "flat": false, "jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.42, -0.125), Vector3(0.04, 0.035, 0.035), Color(0.95, 0.55, 0.5), SMOOTH)
	for side: float in [-1.0, 1.0]:
		kit.call("blob", Vector3(side * 0.05, 0.47, -0.11), Vector3(0.016, 0.02, 0.01), Color(0.05, 0.05, 0.06), SMOOTH)
		kit.call("blob", Vector3(side * 0.16, 0.24, -0.02), Vector3(0.05, 0.08, 0.05), Color(0.25, 0.42, 0.78), SMOOTH)
	kit.call("cone", Vector3(0.0, 0.5, 0.01), 0.15, 0.36, Color(0.85, 0.16, 0.12), 14, {"lumps": 0.0})


## A garden shed filling size: plank walls, a pitched roof with overhangs, a
## door with a handle, and a little window.
static func _shed(kit: RefCounted, color: Color, size: Vector3) -> void:
	var half := size * 0.5
	var wall_height := size.y * 0.72
	kit.call("rbox", Vector3(0.0, wall_height * 0.5, 0.0), Vector3(half.x, wall_height * 0.5, half.z), color, 14.0)
	# Vertical board seams on the front and sides.
	for index: int in int(size.x / 0.25):
		var x := -half.x + 0.125 + float(index) * 0.25
		kit.call("rbox", Vector3(x, wall_height * 0.5, -half.z - 0.005), Vector3(0.008, wall_height * 0.48, 0.008), color.darkened(0.25), 4.0)
	var roof_color := Color(0.32, 0.27, 0.25)
	var rise := size.y - wall_height
	var slope := atan2(rise, half.x)
	var panel := Vector2(half.x + 0.25, rise).length()
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * (half.x * 0.5 + 0.06), wall_height + rise * 0.5, 0.0), Vector3(panel * 0.5 + 0.06, 0.05, half.z + 0.25), roof_color, 6.0, {"basis": Basis(Vector3.BACK, -side * slope)})
	# Gable ends, door, handle, and window.
	kit.call("cone", Vector3(0.0, wall_height, -half.z + 0.02), half.x, rise * 0.98, color, 4, {"lumps": 0.0, "top_radius": 0.0})
	kit.call("rbox", Vector3(0.0, wall_height * 0.42, -half.z - 0.03), Vector3(0.42, wall_height * 0.42, 0.03), color.darkened(0.18), 6.0)
	kit.call("rbox", Vector3(0.3, wall_height * 0.42, -half.z - 0.07), Vector3(0.03, 0.05, 0.03), STEEL, 4.0)
	kit.call("rbox", Vector3(half.x + 0.01, wall_height * 0.62, 0.0), Vector3(0.03, 0.22, 0.3), Color(0.22, 0.28, 0.34), 6.0, {"shade": false})


## A wheelie dumpster filling size: a rounded bin with a lid hinged at the back,
## a front lip, and wheels.
static func _dumpster(kit: RefCounted, color: Color, size: Vector3) -> void:
	var half := size * 0.5
	kit.call("rbox", Vector3(0.0, half.y * 0.95, 0.0), Vector3(half.x, half.y * 0.85, half.z), color, 5.0)
	kit.call("rbox", Vector3(0.0, size.y * 0.93, 0.03), Vector3(half.x + 0.04, 0.05, half.z + 0.05), color.darkened(0.2), 5.0, {"basis": Basis(Vector3.RIGHT, 0.04)})
	kit.call("rbox", Vector3(0.0, size.y * 0.84, -half.z - 0.03), Vector3(half.x * 0.85, 0.04, 0.04), color.darkened(0.3), 4.0)
	for side: float in [-1.0, 1.0]:
		for z: float in [-half.z * 0.6, half.z * 0.6]:
			kit.call("wheel", Vector3(side * (half.x - 0.12), 0.1, z), 0.1, 0.08, Color(0.12, 0.12, 0.13), STEEL)
	# Pockets in the sides, the way molded bins have them.
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * (half.x + 0.005), half.y, 0.0), Vector3(0.02, half.y * 0.45, half.z * 0.7), color.darkened(0.12), 6.0)


## A clipped hedge filling size: lumpy, with lighter tips on top.
static func _hedge(kit: RefCounted, color: Color, size: Vector3) -> void:
	var half := size * 0.5
	var long_axis_x := size.x >= size.z
	var length := size.x if long_axis_x else size.z
	var count := maxi(1, int(ceil(length / 0.9)))
	for index: int in count:
		var t := (float(index) + 0.5) / float(count) - 0.5
		var at := Vector3(t * length, half.y, 0.0) if long_axis_x else Vector3(0.0, half.y, t * length)
		var lump := maxf(length / float(count) * 0.7, 0.45)
		var radius := Vector3(lump, half.y * 1.02, half.z * 1.05) if long_axis_x else Vector3(half.x * 1.05, half.y * 1.02, lump)
		kit.call("blob", at, radius, color.lightened(0.04 * float(index % 2)), {"detail": 2, "lumps": 0.22, "lump_scale": 2.6, "flat": true, "soft": 0.7, "jitter": 0.03, "seed": index})
	kit.call("grade", 0, 0.0, size.y, 0.65, 1.12)


## A rounded little sedan, facing -Z.
static func _car(kit: RefCounted, color: Color) -> void:
	var glass := Color(0.2, 0.26, 0.32)
	kit.call("rbox", Vector3(0.0, 0.62, 0.0), Vector3(0.95, 0.32, 2.15), color, 5.0)
	kit.call("rbox", Vector3(0.0, 1.12, 0.2), Vector3(0.85, 0.33, 1.15), color, 4.0)
	kit.call("rbox", Vector3(0.0, 1.13, 0.2), Vector3(0.87, 0.24, 1.0), glass, 5.0, {"shade": false})
	kit.call("rbox", Vector3(0.0, 1.13, 0.2), Vector3(0.05, 0.25, 1.02), color, 6.0)
	kit.call("rbox", Vector3(0.0, 0.42, -2.18), Vector3(0.95, 0.09, 0.08), Color(0.85, 0.85, 0.83), 4.0)
	kit.call("rbox", Vector3(0.0, 0.42, 2.18), Vector3(0.95, 0.09, 0.08), Color(0.85, 0.85, 0.83), 4.0)
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * 0.62, 0.7, -2.12), Vector3(0.18, 0.08, 0.04), Color(1.0, 0.95, 0.8), 4.0, {"shade": false})
		kit.call("rbox", Vector3(side * 0.66, 0.72, 2.13), Vector3(0.16, 0.07, 0.03), Color(0.85, 0.15, 0.1), 4.0, {"shade": false})
		for z: float in [-1.35, 1.35]:
			kit.call("wheel", Vector3(side * 0.88, 0.34, z), 0.34, 0.24, Color(0.12, 0.12, 0.13), Color(0.75, 0.75, 0.74))


## A wooden privacy fence run filling size along its longer axis: boards with
## dog-eared tops, two rails, and posts.
static func _fence(kit: RefCounted, color: Color, size: Vector3) -> void:
	var along_x := size.x >= size.z
	var length := size.x if along_x else size.z
	var boards := int(length / 0.16)
	var rng := RandomNumberGenerator.new()
	rng.seed = boards
	for index: int in boards:
		var t := -length * 0.5 + (float(index) + 0.5) * length / float(boards)
		var tint := color.darkened(rng.randf_range(0.0, 0.12))
		var at := Vector3(t, size.y * 0.5, 0.0) if along_x else Vector3(0.0, size.y * 0.5, t)
		var half := Vector3(0.07, size.y * 0.5, 0.012) if along_x else Vector3(0.012, size.y * 0.5, 0.07)
		kit.call("rbox", at, half, tint, 8.0, {"detail": 1})
	for y: float in [size.y * 0.25, size.y * 0.75]:
		var at := Vector3(0.0, y, 0.04) if along_x else Vector3(0.04, y, 0.0)
		var half := Vector3(length * 0.5, 0.04, 0.025) if along_x else Vector3(0.025, 0.04, length * 0.5)
		kit.call("rbox", at, half, color.darkened(0.2), 8.0, {"detail": 1})
	# At least one span: a run shorter than a post spacing divided by zero
	# (NaN positions, which glow smears into white blobs).
	var spans := maxi(1, int(length / 2.4))
	for post: int in spans + 1:
		var t := -length * 0.5 + float(post) * length / float(spans)
		var at := Vector3(t, size.y * 0.52, 0.05) if along_x else Vector3(0.05, size.y * 0.52, t)
		kit.call("rbox", at, Vector3(0.06, size.y * 0.53, 0.06), color.darkened(0.25), 8.0, {"detail": 1})


# ---------------------------------------------------------------- tools (face -Z)

## A handheld blower: a chunky orange motor, a top handle, and a long nozzle.
static func _leaf_blower(kit: RefCounted) -> void:
	var orange := Color(0.95, 0.5, 0.12)
	kit.call("rbox", Vector3(0.0, 0.2, 0.08), Vector3(0.14, 0.16, 0.18), orange, 4.0)
	kit.call("rbox", Vector3(0.0, 0.2, 0.08), Vector3(0.145, 0.07, 0.12), Color(0.2, 0.2, 0.22), 6.0)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.36, 0.0), Vector3(0, 0.44, 0.08), Vector3(0, 0.36, 0.2)]), PackedFloat32Array([0.025, 0.025, 0.025]), Color(0.15, 0.15, 0.16), 6, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.16, -0.08), Vector3(0, 0.13, -0.4), Vector3(0, 0.1, -0.75)]), PackedFloat32Array([0.07, 0.055, 0.045]), orange.lightened(0.1), 10, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.1, -0.74), Vector3(0, 0.1, -0.8)]), PackedFloat32Array([0.05, 0.05]), Color(0.15, 0.15, 0.16), 10, {"jitter": 0.0})


## A push mower: a red deck on four wheels, a motor on top, a grass bag at the
## back, and the handle rising behind (+Z) where you push.
static func _lawn_mower(kit: RefCounted) -> void:
	var red := Color(0.82, 0.18, 0.14)
	kit.call("rbox", Vector3(0.0, 0.2, 0.0), Vector3(0.3, 0.08, 0.32), red, 5.0)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.26, -0.02), Vector3(0, 0.42, -0.02)]), PackedFloat32Array([0.13, 0.11]), Color(0.2, 0.2, 0.22), 12, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.45, -0.02), Vector3(0.1, 0.04, 0.1), Color(0.75, 0.75, 0.72), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	for side: float in [-1.0, 1.0]:
		for z: float in [-0.26, 0.26]:
			kit.call("wheel", Vector3(side * 0.31, 0.1, z), 0.1, 0.06, Color(0.12, 0.12, 0.13), Color(0.8, 0.8, 0.78))
		kit.call("tube", PackedVector3Array([Vector3(side * 0.18, 0.25, 0.3), Vector3(side * 0.2, 0.7, 0.75), Vector3(side * 0.2, 0.95, 0.95)]), PackedFloat32Array([0.018, 0.018, 0.018]), Color(0.25, 0.25, 0.27), 6, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(-0.21, 0.95, 0.95), Vector3(0.21, 0.95, 0.95)]), PackedFloat32Array([0.025, 0.025]), Color(0.12, 0.12, 0.13), 8, {"jitter": 0.0, "cap_start": true})
	kit.call("blob", Vector3(0.0, 0.3, 0.45), Vector3(0.2, 0.14, 0.16), Color(0.25, 0.45, 0.28), {"detail": 2, "lumps": 0.1, "flat": false, "jitter": 0.0})


## An aluminum step ladder, carried flat: two rails along Z and rungs between.
static func _ladder(kit: RefCounted) -> void:
	var metal := Color(0.78, 0.8, 0.82)
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * 0.22, 0.0, 0.0), Vector3(0.025, 0.05, 1.2), metal, 8.0)
	for rung: int in 7:
		kit.call("tube", PackedVector3Array([Vector3(-0.21, 0.0, -1.05 + float(rung) * 0.35), Vector3(0.21, 0.0, -1.05 + float(rung) * 0.35)]), PackedFloat32Array([0.018, 0.018]), metal.darkened(0.1), 6, {"jitter": 0.0})
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * 0.22, 0.0, 1.22), Vector3(0.035, 0.06, 0.04), Color(0.15, 0.15, 0.16), 4.0)


## A garden hose coiled on a little reel, with a spray nozzle.
static func _hose(kit: RefCounted) -> void:
	var green := Color(0.2, 0.58, 0.3)
	for loop: int in 4:
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		for step: int in 17:
			var angle := TAU * float(step) / 16.0
			points.append(Vector3(-0.09 + float(loop) * 0.06, 0.3 + sin(angle) * 0.2, cos(angle) * 0.2))
			radii.append(0.022)
		kit.call("tube", points, radii, green.darkened(float(loop % 2) * 0.1), 6, {"jitter": 0.0})
	for side: float in [-1.0, 1.0]:
		kit.call("tube", PackedVector3Array([Vector3(side * 0.16, 0.3, 0.0), Vector3(side * 0.14, 0.0, 0.0)]), PackedFloat32Array([0.02, 0.025]), Color(0.3, 0.3, 0.32), 6, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.3, -0.2), Vector3(0, 0.25, -0.35), Vector3(0, 0.25, -0.5)]), PackedFloat32Array([0.022, 0.022, 0.022]), green, 6, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.25, -0.5), Vector3(0, 0.25, -0.62)]), PackedFloat32Array([0.03, 0.02]), Color(0.85, 0.75, 0.2), 8, {"jitter": 0.0})


## A yellow pressure washer on wheels, with its long spray wand clipped on.
static func _pressure_washer(kit: RefCounted) -> void:
	var yellow := Color(0.98, 0.78, 0.15)
	kit.call("rbox", Vector3(0.0, 0.38, 0.0), Vector3(0.22, 0.24, 0.18), yellow, 4.0)
	kit.call("rbox", Vector3(0.0, 0.42, -0.19), Vector3(0.14, 0.1, 0.02), Color(0.15, 0.15, 0.16), 6.0)
	for side: float in [-1.0, 1.0]:
		kit.call("wheel", Vector3(side * 0.25, 0.1, 0.1), 0.1, 0.06, Color(0.12, 0.12, 0.13), Color(0.7, 0.7, 0.7))
	kit.call("tube", PackedVector3Array([Vector3(-0.16, 0.6, 0.12), Vector3(-0.16, 0.95, 0.18), Vector3(0.16, 0.95, 0.18), Vector3(0.16, 0.6, 0.12)]), PackedFloat32Array([0.018, 0.018, 0.018, 0.018]), Color(0.2, 0.2, 0.22), 6, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0.24, 0.3, -0.05), Vector3(0.26, 0.75, -0.15), Vector3(0.26, 0.9, -0.5)]), PackedFloat32Array([0.014, 0.014, 0.012]), Color(0.2, 0.2, 0.22), 6, {"jitter": 0.0})


## A hedge trimmer: a red motor body with a handle and a long toothed blade forward.
static func _hedge_trimmer(kit: RefCounted) -> void:
	kit.call("rbox", Vector3(0.0, 0.15, 0.12), Vector3(0.09, 0.09, 0.16), Color(0.85, 0.22, 0.15), 4.0)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.25, 0.04), Vector3(0, 0.32, 0.12), Vector3(0, 0.25, 0.22)]), PackedFloat32Array([0.02, 0.02, 0.02]), Color(0.15, 0.15, 0.16), 6, {"jitter": 0.0})
	kit.call("rbox", Vector3(0.0, 0.14, -0.35), Vector3(0.035, 0.012, 0.33), Color(0.8, 0.82, 0.85), 6.0)
	for tooth: int in 12:
		for side: float in [-1.0, 1.0]:
			kit.call("rbox", Vector3(side * 0.045, 0.14, -0.07 - float(tooth) * 0.05), Vector3(0.012, 0.008, 0.01), Color(0.75, 0.77, 0.8), 4.0, {"detail": 1})


## A paint roller: a handle, a bent frame, and a roller loaded with white paint.
static func _paint_roller(kit: RefCounted) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, 0.3), Vector3(0, 0.0, 0.0)]), PackedFloat32Array([0.022, 0.02]), Color(0.3, 0.45, 0.8), 8, {"jitter": 0.0, "cap_start": true})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, 0.0), Vector3(0, 0.0, -0.12), Vector3(0.1, 0.0, -0.18)]), PackedFloat32Array([0.008, 0.008, 0.008]), Color(0.75, 0.75, 0.75), 5, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0.1, 0.0, -0.18), Vector3(-0.12, 0.0, -0.18)]), PackedFloat32Array([0.045, 0.045]), Color(0.97, 0.96, 0.93), 12, {"jitter": 0.0, "cap_start": true})


# ---------------------------------------------------------------- water

## A red fire hydrant: a domed body, side caps, and a chain.
static func _hydrant(kit: RefCounted) -> void:
	var red := Color(0.85, 0.15, 0.12)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0, 0.12, 0)]), PackedFloat32Array([0.2, 0.2]), red.darkened(0.2), 12, {"jitter": 0.0, "cap_start": true})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.1, 0), Vector3(0, 0.62, 0)]), PackedFloat32Array([0.15, 0.14]), red, 12, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.64, 0.0), Vector3(0.16, 0.12, 0.16), red.lightened(0.05), {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.74, 0), Vector3(0, 0.82, 0)]), PackedFloat32Array([0.05, 0.04]), Color(0.75, 0.7, 0.3), 8, {"jitter": 0.0})
	for side: float in [-1.0, 1.0]:
		kit.call("tube", PackedVector3Array([Vector3(side * 0.12, 0.42, 0), Vector3(side * 0.24, 0.42, 0)]), PackedFloat32Array([0.06, 0.06]), red.darkened(0.1), 10, {"jitter": 0.0})
		kit.call("tube", PackedVector3Array([Vector3(side * 0.24, 0.42, 0), Vector3(side * 0.27, 0.42, 0)]), PackedFloat32Array([0.07, 0.07]), Color(0.75, 0.7, 0.3), 10, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.42, -0.12), Vector3(0, 0.42, -0.2)]), PackedFloat32Array([0.08, 0.08]), Color(0.75, 0.7, 0.3), 10, {"jitter": 0.0})


## A brass spigot on the wall (facing -Z out of it), with a little round handle.
static func _spigot(kit: RefCounted) -> void:
	var brass := Color(0.8, 0.62, 0.25)
	kit.call("tube", PackedVector3Array([Vector3(0, 0, 0.0), Vector3(0, 0, -0.1), Vector3(0, -0.04, -0.15), Vector3(0, -0.1, -0.16)]), PackedFloat32Array([0.022, 0.02, 0.02, 0.02]), brass, 8, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0, -0.06), Vector3(0, 0.07, -0.06)]), PackedFloat32Array([0.008, 0.008]), brass.darkened(0.2), 6, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.08, -0.06), Vector3(0.04, 0.012, 0.04), Color(0.25, 0.45, 0.75), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.call("rbox", Vector3(0.0, 0.0, 0.01), Vector3(0.06, 0.06, 0.012), brass.darkened(0.3), 4.0)


## A blue water barrel with a valve, strapped in Chefty's bed.
static func _water_tank(kit: RefCounted) -> void:
	var blue := Color(0.22, 0.48, 0.82)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0, 0.75, 0)]), PackedFloat32Array([0.32, 0.32]), blue, 14, {"jitter": 0.0, "cap_start": true})
	for y: float in [0.2, 0.55]:
		kit.call("tube", PackedVector3Array([Vector3(0, y - 0.02, 0), Vector3(0, y + 0.02, 0)]), PackedFloat32Array([0.335, 0.335]), blue.darkened(0.25), 14, {"jitter": 0.0, "cap": false})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.12, 0.3), Vector3(0, 0.12, 0.42)]), PackedFloat32Array([0.035, 0.03]), Color(0.75, 0.75, 0.72), 8, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.18, 0.4), Vector3(0.05, 0.015, 0.05), Color(0.85, 0.2, 0.15), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})


## The hose's spray nozzle, held when the hose is hooked up (points -Z).
static func _nozzle(kit: RefCounted) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0, 0, 0.15), Vector3(0, 0, -0.05)]), PackedFloat32Array([0.03, 0.03]), Color(0.2, 0.58, 0.3), 8, {"jitter": 0.0, "cap_start": true})
	kit.call("tube", PackedVector3Array([Vector3(0, 0, -0.05), Vector3(0, 0, -0.2)]), PackedFloat32Array([0.035, 0.022]), Color(0.85, 0.72, 0.2), 10, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0, 0.02), Vector3(0, -0.12, 0.06)]), PackedFloat32Array([0.018, 0.018]), Color(0.15, 0.15, 0.16), 6, {"jitter": 0.0})


## The pressure washer's spray wand: a pistol grip with a trigger, a long metal
## lance, and a tip, pointing -Z.
static func _wand(kit: RefCounted) -> void:
	var black := Color(0.15, 0.15, 0.16)
	kit.call("rbox", Vector3(0.0, 0.0, 0.05), Vector3(0.035, 0.05, 0.09), Color(0.98, 0.78, 0.15), 4.0)
	kit.call("tube", PackedVector3Array([Vector3(0, -0.03, 0.08), Vector3(0, -0.15, 0.12)]), PackedFloat32Array([0.022, 0.024]), black, 8, {"jitter": 0.0, "cap_start": true})
	kit.call("tube", PackedVector3Array([Vector3(0, -0.05, 0.0), Vector3(0, -0.09, 0.02)]), PackedFloat32Array([0.008, 0.008]), black, 5, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, -0.04), Vector3(0, 0.0, -0.8)]), PackedFloat32Array([0.012, 0.012]), Color(0.75, 0.76, 0.78), 8, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, -0.78), Vector3(0, 0.0, -0.86)]), PackedFloat32Array([0.02, 0.016]), black, 8, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, -0.12, 0.13), Vector3(0, -0.3, 0.2)]), PackedFloat32Array([0.012, 0.012]), black, 6, {"jitter": 0.0})


## A gallon of white paint with the lid off and a drip down the side.
static func _paint_bucket(kit: RefCounted) -> void:
	var tin := Color(0.78, 0.78, 0.76)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0, 0.34, 0)]), PackedFloat32Array([0.17, 0.17]), tin, 14, {"jitter": 0.0, "cap_start": true, "cap": false})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.3, 0), Vector3(0, 0.31, 0)]), PackedFloat32Array([0.16, 0.16]), Color(0.97, 0.96, 0.92), 14, {"jitter": 0.0})
	kit.call("rbox", Vector3(0.0, 0.17, 0.171), Vector3(0.1, 0.07, 0.004), Color(0.35, 0.55, 0.85), 6.0, {"shade": false})
	kit.call("tube", PackedVector3Array([Vector3(0.16, 0.33, 0), Vector3(0.17, 0.2, 0.0), Vector3(0.172, 0.12, 0.0)]), PackedFloat32Array([0.018, 0.014, 0.012]), Color(0.97, 0.96, 0.92), 6, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(-0.17, 0.34, 0), Vector3(0.0, 0.5, 0.0), Vector3(0.17, 0.34, 0)]), PackedFloat32Array([0.006, 0.006, 0.006]), Color(0.4, 0.4, 0.42), 5, {"jitter": 0.0})
