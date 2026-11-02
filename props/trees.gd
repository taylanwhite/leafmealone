extends RefCounted

## Authority: local, cosmetic. Trees for the neighborhood, built in code with
## props/mesh_kit.gd and drawn with props/stylized.gd. A broadleaf tree is a
## flared, leaning trunk that splits into bent limbs, each ending in clumps of
## leaves, with the crown darkened toward its middle so it reads as deep. A pine
## is a thin trunk inside drooping tiers. A birch is a slender white trunk with
## dark marks and a narrow crown of small clumps. A willow is a stout trunk under
## a low dome with long strands hanging nearly to the ground. A cypress is a tall
## dark column of stacked blobs. Crowns sway in the wind (willow strands most).
##
## Seasons (core/seasons.gd): every tree is built per season. seasonal_form()
## says what a tree wears in a season: broadleaf kinds go bare in winter (limbs,
## twigs, and snow tufts on top), blossom or turn fresh green in spring, and turn
## deep green in summer; evergreens keep their needles and get snow caps in
## winter. The same tree keeps the same limbs all year: the shape comes from
## (kind, crown, variant) and only the leaves change. spawn() returns a
## props/tree_node.gd root, in group "seasonal", that swaps its meshes when the
## season turns.
##
## LOD: every tree has a near mesh ("Look") and a cheap far mesh ("LookFar": the
## trunk and a few low-detail blobs, no leaf cards). LookFar draws from
## Constants.ART_TREE_LOD_DISTANCE out, and Look depends on it (Node3D
## visibility_parent, Godot's hierarchical LOD), so exactly one of them draws.
##
## Meshes are cached per kind, crown, variant and form, so a street of trees
## costs a handful. Every mesh records meta "triangles" (budgets:
## Constants.ART_TREE_MAX_TRIANGLES and ART_TREE_FAR_MAX_TRIANGLES, checked by
## tools/mesh_check.gd). Art rules: docs/ART.md. 1 unit = 1 meter, Y up, origin
## at the base.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _TreeNode = preload("res://props/tree_node.gd")

## Every tree is built this tall and scaled to the height asked for.
const BUILD_HEIGHT: float = 7.0
const VARIANTS: int = 4
## Every kind spawn() knows. Anything else builds a broadleaf.
const KINDS: Array[String] = ["broadleaf", "pine", "birch", "willow", "cypress"]
## Kinds that keep their needles all year.
const EVERGREEN: Array[String] = ["pine", "cypress"]
## What a tree can be wearing (meta "form" on its root): "full" (leaves or
## needles), "bare" (a broadleaf kind in winter), "snowy" (an evergreen in winter).
const FORMS: Array[String] = ["full", "bare", "snowy"]
const BARK := Color(0.33, 0.24, 0.18)
const PINE_GREEN := Color(0.2, 0.42, 0.26)
const BIRCH_BARK := Color(0.9, 0.88, 0.83)
const BIRCH_MARK := Color(0.19, 0.17, 0.16)
const CYPRESS_GREEN := Color(0.16, 0.33, 0.2)
## A bare willow's hanging whips.
const WILLOW_TWIG := Color(0.62, 0.54, 0.3)
const SNOW_WHITE := Color(0.94, 0.96, 1.0)
## Crowns: the main color and the one its clumps drift toward. The first six are
## the autumn crowns callers pick from; the rest are what seasons turn them into.
const CROWNS: Dictionary = {
	"orange": [Color(0.92, 0.5, 0.16), Color(0.95, 0.66, 0.24)],
	"red": [Color(0.78, 0.22, 0.14), Color(0.9, 0.4, 0.18)],
	"yellow": [Color(0.93, 0.73, 0.24), Color(0.86, 0.8, 0.33)],
	"rust": [Color(0.66, 0.3, 0.14), Color(0.84, 0.46, 0.18)],
	"turning": [Color(0.55, 0.6, 0.24), Color(0.93, 0.58, 0.2)],
	"green": [Color(0.33, 0.53, 0.22), Color(0.45, 0.6, 0.25)],
	"blossom_pink": [Color(0.98, 0.72, 0.8), Color(1.0, 0.86, 0.9)],
	"blossom_white": [Color(0.98, 0.97, 0.93), Color(0.9, 0.95, 0.8)],
	"spring_green": [Color(0.55, 0.75, 0.32), Color(0.7, 0.85, 0.4)],
	"deep_green": [Color(0.2, 0.42, 0.17), Color(0.3, 0.52, 0.21)],
}
## Spring: a broadleaf that turns red in autumn blossoms pink, a yellow one
## blossoms white, and everything else comes back fresh green.
const SPRING_CROWNS: Dictionary = {"red": "blossom_pink", "yellow": "blossom_white"}
## Summer: the trees that turn warm in autumn are the deep green ones.
const SUMMER_DEEP: Array[String] = ["red", "rust", "orange"]
## Crowns carry their own season colors, so the season_foliage tint is off, and
## snow settles on whatever faces up (bare limbs, pine tiers).
const WIND: Dictionary = {"wind": 0.09, "translucency": 0.35, "snow": 1.0, "seasonal": false}
const WILLOW_WIND: Dictionary = {"wind": 0.14, "translucency": 0.4, "snow": 1.0, "seasonal": false}

## Tip clumps closer than this share of a clump's size merge into one.
const MERGE_SHARE: float = 0.65
## Strands hanging from a leafy willow (eight fewer when bare).
const WILLOW_STRANDS: int = 36
## Leaf cards fill the near budget up to this share of it.
const CARD_BUDGET_SHARE: float = 0.97

## [near, far] per kind|crown|variant|shown crown|form.
static var _cache: Dictionary = {}


## A tree under parent at at. kind is one of KINDS; crown is a key of CROWNS
## (ignored by evergreens), the crown it wears in autumn. variant picks one of a
## few shapes. solid adds a trunk collider. It wears the season showing now
## (Seasons.current()) and follows the season from then on.
static func spawn(parent: Node3D, at: Vector3, height: float, kind: String = "broadleaf", crown: String = "orange", variant: int = 0, solid: bool = false, yaw: float = 0.0) -> Node3D:
	var root: Node3D = _TreeNode.new()
	root.name = "Tree"
	root.set("kind", kind)
	root.set("crown", crown)
	root.set("variant", variant)
	parent.add_child(root)
	root.position = at
	root.rotation.y = yaw
	var scale := height / BUILD_HEIGHT
	root.scale = Vector3.ONE * scale
	var options := material_options(kind)
	var view := _Stylized.instance(mesh_for(kind, crown, variant, Seasons.current()), options)
	view.name = "Look"
	root.add_child(view)
	var far := _Stylized.instance(mesh_for(kind, crown, variant, Seasons.current(), true), options)
	far.name = "LookFar"
	far.visibility_range_begin = Constants.ART_TREE_LOD_DISTANCE
	far.visibility_range_begin_margin = Constants.ART_TREE_LOD_MARGIN
	root.add_child(far)
	# The near mesh draws exactly while the far one is hidden for being too close.
	view.visibility_parent = NodePath("../LookFar")
	root.call("show_season", Seasons.current())
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.35
		cylinder.height = 3.0
		shape.shape = cylinder
		shape.position.y = 1.5
		body.add_child(shape)
		root.add_child(body)
	return root


## The material options a kind is drawn with.
static func material_options(kind: String) -> Dictionary:
	return WILLOW_WIND if kind == "willow" else WIND


## What a tree of kind with this autumn crown wears in season (0 autumn, 1
## winter, 2 spring, 3 summer): [kind, crown shown, form].
static func seasonal_form(kind: String, crown: String, season: int) -> Array:
	if EVERGREEN.has(kind):
		return [kind, crown, "snowy" if posmod(season, 4) == 1 else "full"]
	match posmod(season, 4):
		1:
			return [kind, crown, "bare"]
		2:
			# Only broadleaves blossom; birches and willows come back fresh green.
			if kind == "broadleaf" and SPRING_CROWNS.has(crown):
				return [kind, SPRING_CROWNS[crown], "full"]
			return [kind, "spring_green", "full"]
		3:
			return [kind, "deep_green" if SUMMER_DEEP.has(crown) else "green", "full"]
	return [kind, crown, "full"]


## The mesh a tree of kind, autumn crown and variant wears in season (default:
## the season showing now). far picks the cheap far mesh.
static func mesh_for(kind: String, crown: String, variant: int, season: int = -1, far: bool = false) -> ArrayMesh:
	var shown := Seasons.current() if season < 0 else season
	var form := seasonal_form(kind, crown, shown)
	return form_mesh(kind, crown, variant, str(form[1]), str(form[2]), far)


## The mesh for one exact form: crown is the tree's autumn crown (it fixes the
## shape), shown_crown the colors it wears, form one of FORMS.
static func form_mesh(kind: String, crown: String, variant: int, shown_crown: String, form: String, far: bool = false) -> ArrayMesh:
	var base := "%s|%s|%d" % [kind, crown, variant % VARIANTS]
	var key := "%s|%s|%s" % [base, shown_crown, form]
	if not _cache.has(key):
		var seed_value := hash(base)
		var pair: Array
		match kind:
			"pine":
				pair = _pine(seed_value, form)
			"birch":
				pair = _birch(seed_value, shown_crown, form)
			"willow":
				pair = _willow(seed_value, shown_crown, form)
			"cypress":
				pair = _cypress(seed_value, form)
			_:
				pair = _broadleaf(seed_value, shown_crown, form)
		_cache[key] = pair
	return (_cache[key] as Array)[1 if far else 0]


# ---------------------------------------------------------------- broadleaf

static func _broadleaf(seed_value: int, crown: String, form: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := _MeshKit.new()
	var far := _MeshKit.new()
	var height := BUILD_HEIGHT
	var colors: Array = CROWNS.get(crown, CROWNS["orange"])
	var trunk_height := height * rng.randf_range(0.3, 0.36)
	var base_radius := height * 0.05
	var lean := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.1, 0.35)
	var trunk := PackedVector3Array()
	var radii := PackedFloat32Array()
	for step: int in 5:
		var t := float(step) / 4.0
		trunk.append(Vector3(0.0, t * trunk_height, 0.0) + lean * t * t * trunk_height * 0.5)
		radii.append(lerpf(base_radius * 1.1, base_radius * 0.7, t))
	kit.tube(trunk, radii, BARK, 9, {"seed": seed_value, "flare": 0.45, "cap": false})
	far.tube(PackedVector3Array([trunk[0], trunk[2], trunk[4]]), PackedFloat32Array([radii[0] * 1.2, radii[2], radii[4]]), BARK, 6, {"seed": seed_value, "cap": false, "jitter": 0.0})
	var top := trunk[trunk.size() - 1]
	var crown_center := top + Vector3(0.0, (height - trunk_height) * 0.4, 0.0)
	var crown_radii := Vector3(height * 0.4, (height - trunk_height) * 0.5, height * 0.4)
	# Limbs fan out from the top of the trunk, each splitting once or twice.
	var tips: Array[Vector3] = []
	var bones: Array = []
	var limbs := rng.randi_range(4, 6)
	var turn := rng.randf_range(0.0, TAU)
	for limb: int in limbs:
		var angle := turn + TAU * float(limb) / float(limbs) + rng.randf_range(-0.35, 0.35)
		var rise := rng.randf_range(0.45, 0.9)
		var direction := Vector3(cos(angle), rise, sin(angle)).normalized()
		var start := top - Vector3(0.0, rng.randf_range(0.0, trunk_height * 0.3), 0.0)
		_limb(kit, rng, start, direction, height * rng.randf_range(0.28, 0.34), base_radius * 0.55, 1, tips, bones)
	# A central leader keeps the crown from looking hollow on top.
	_limb(kit, rng, top, Vector3(rng.randf_range(-0.15, 0.15), 1.0, rng.randf_range(-0.15, 0.15)).normalized(), height * 0.24, base_radius * 0.5, 1, tips, bones)
	if form == "bare":
		_bare_top(kit, far, seed_value, bones, top, BARK, false)
		return _finish(kit, far)
	# Leaf clumps: one on each limb tip, and a few big ones filling the middle.
	var clump := height * 0.18
	var index := 0
	var crown_start := kit.vertex_count()
	var leaf_options := {"detail": 2, "lumps": 0.38, "lump_scale": 0.9, "sway": 1.0, "jitter": 0.015, "soft": 0.8}
	var clumps: Array = []
	for tip: Vector3 in tips:
		index += 1
		var color := _crown_color(rng, colors, (tip.y - top.y) / maxf(crown_radii.y * 2.0, 0.1))
		var size := Vector3.ONE * clump * rng.randf_range(0.8, 1.2)
		size.y *= rng.randf_range(0.7, 0.85)
		# Two tips this close share one clump (the draws above still happen, so
		# every other clump keeps its color and size).
		if _crowded(clumps, tip + Vector3(0.0, clump * 0.2, 0.0), clump * MERGE_SHARE):
			continue
		leaf_options["seed"] = seed_value + index
		kit.blob(tip + Vector3(0.0, clump * 0.2, 0.0), size, color, leaf_options)
		clumps.append([tip + Vector3(0.0, clump * 0.2, 0.0), size, color])
	for filler: int in 3:
		var angle := TAU * float(filler) / 3.0 + rng.randf_range(-0.4, 0.4)
		var offset := Vector3(cos(angle) * 0.35, rng.randf_range(-0.2, 0.3), sin(angle) * 0.35) * crown_radii
		if filler == 0:
			offset = Vector3(0.0, crown_radii.y * 0.35, 0.0)
		var color := _crown_color(rng, colors, 0.5 + offset.y / maxf(crown_radii.y, 0.1) * 0.5)
		var size := Vector3(clump * 1.6, clump * 1.2, clump * 1.6) * rng.randf_range(0.9, 1.1)
		leaf_options["seed"] = seed_value + 100 + filler
		leaf_options["sway"] = 0.7
		kit.blob(crown_center + offset, size, color, leaf_options)
		clumps.append([crown_center + offset, size, color])
	# Loose leaves over every clump's surface break up the silhouette.
	_cards(kit, rng, clumps, colors, _card_count(kit, clumps.size(), 40, 0), clump, Vector2(0.16, 0.24))
	var crown_bottom := crown_center.y - crown_radii.y * 1.1
	var crown_top := crown_center.y + crown_radii.y * 1.2
	kit.grade(crown_start, crown_bottom, crown_top, 0.62, 1.12)
	kit.occlude(crown_center, crown_radii * 1.2, 0.3)
	_far_limbs(far, bones, 1, BARK)
	var far_start := far.vertex_count()
	_far_crown(far, clumps, seed_value, 4)
	far.grade(far_start, crown_bottom, crown_top, 0.62, 1.12)
	far.occlude(crown_center, crown_radii * 1.2, 0.3)
	return _finish(kit, far)


## A bent limb from start toward direction, which splits depth more times.
## Every final tip is added to tips, where leaf clumps go, and every limb to
## bones as [start, end, end radius, depth, heading] (for bare twigs and far LODs).
static func _limb(kit: RefCounted, rng: RandomNumberGenerator, start: Vector3, direction: Vector3, length: float, radius: float, depth: int, tips: Array[Vector3], bones: Array = [], color: Color = BARK) -> void:
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	var heading := direction
	var at := start
	for step: int in 4:
		points.append(at)
		radii.append(lerpf(radius, radius * 0.6, float(step) / 3.0))
		# Limbs curve upward toward the light, with a little wander.
		heading = (heading + Vector3(rng.randf_range(-0.2, 0.2), 0.22, rng.randf_range(-0.2, 0.2))).normalized()
		at += heading * length / 3.0
	kit.call("tube", points, radii, color, 6, {"seed": rng.randi(), "sway_from": 0.0, "sway_to": 0.35, "cap": true})
	var end := points[points.size() - 1]
	bones.append([start, end, radius * 0.6, depth, (end - points[points.size() - 2]).normalized()])
	if depth <= 0:
		tips.append(end)
		return
	var children := 2 if rng.randf() < 0.75 else 3
	for child: int in children:
		var side := heading.cross(Vector3.UP)
		if side.length() < 0.1:
			side = Vector3.RIGHT
		side = side.normalized().rotated(heading, rng.randf_range(0.0, TAU))
		var spread := rng.randf_range(0.35, 0.7)
		var next := (heading * cos(spread) + side * sin(spread)).normalized()
		_limb(kit, rng, end, next, length * rng.randf_range(0.6, 0.75), radius * 0.62, depth - 1, tips, bones, color)


static func _crown_color(rng: RandomNumberGenerator, colors: Array, height_share: float) -> Color:
	var main: Color = colors[0]
	var other: Color = colors[1]
	var color := main.lerp(other, clampf(rng.randf_range(0.0, 0.45) + (height_share - 0.3) * 0.5, 0.0, 1.0))
	# Higher clumps catch more sun.
	return color.lightened(clampf(height_share, 0.0, 1.0) * 0.08)


## Whether a clump at at would sit within reach of one already in clumps.
static func _crowded(clumps: Array, at: Vector3, reach: float) -> bool:
	for entry: Array in clumps:
		if (entry[0] as Vector3).distance_to(at) < reach:
			return true
	return false


## How many leaf cards each of clumps clumps can have (at most most) so the near
## mesh stays inside Constants.ART_TREE_MAX_TRIANGLES, with reserve triangles
## still to come. A card is 4 triangles.
static func _card_count(kit: RefCounted, clumps: int, most: int, reserve: int) -> int:
	var room := int(float(Constants.ART_TREE_MAX_TRIANGLES) * CARD_BUDGET_SHARE) - int(kit.call("vertex_count")) / 3 - reserve
	return clampi(room / maxi(clumps * 4, 1), 0, most)


## Loose leaf cards over each clump in clumps ([center, size, color]): count per
## clump, sized clump times a random share of card_range.
static func _cards(kit: RefCounted, rng: RandomNumberGenerator, clumps: Array, colors: Array, count: int, clump: float, card_range: Vector2) -> void:
	for entry: Array in clumps:
		var at: Vector3 = entry[0]
		var size: Vector3 = entry[1]
		var color: Color = entry[2]
		for card: int in count:
			var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.4, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
			var spot := at + direction * size * rng.randf_range(1.0, 1.1)
			var tint := color.lerp(colors[1], rng.randf_range(0.0, 0.3))
			# Cards lie along the surface, tipped outward, lit like the clump under them.
			var facing := (direction + Vector3(0.0, 0.6, 0.0)).normalized()
			kit.call("leaf_card", spot, facing, clump * rng.randf_range(card_range.x, card_range.y), tint, 1.0, rng.randf_range(0.0, TAU))


# ---------------------------------------------------------------- winter

## A bare crown: twigs off every limb tip, snow tufts sitting on top of most of
## them and in the main fork, and on the far mesh the main limbs, thickened so
## they still read from across the street. droop hangs the twigs (birches).
static func _bare_top(kit: RefCounted, far: RefCounted, seed_value: int, bones: Array, fork: Vector3, color: Color, droop: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	var tuft := 0
	for bone: Array in bones:
		var start: Vector3 = bone[0]
		var end: Vector3 = bone[1]
		var radius: float = bone[2]
		var depth: int = bone[3]
		var heading: Vector3 = bone[4]
		var length := start.distance_to(end)
		far.call("tube", PackedVector3Array([start, end]), PackedFloat32Array([radius * 2.2, radius * 1.4]), color, 4 if depth > 0 else 3, {"seed": seed_value + tuft, "cap": true, "jitter": 0.0, "sway_to": 0.35})
		if depth > 0:
			continue
		for twig: int in 3:
			var out := (heading + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.2, 0.5), rng.randf_range(-0.7, 0.7))).normalized()
			if droop:
				out = (out + Vector3(0.0, -1.1, 0.0)).normalized()
			var twig_length := length * rng.randf_range(0.3, 0.45)
			var middle := end + out * twig_length * 0.5 + Vector3(0.0, (-0.12 if droop else 0.06) * twig_length, 0.0)
			var tip := end + out * twig_length + Vector3(0.0, (-0.3 if droop else 0.1) * twig_length, 0.0)
			kit.call("tube", PackedVector3Array([end, middle, tip]), PackedFloat32Array([radius * 0.7, radius * 0.4, radius * 0.15]), color, 4, {"seed": rng.randi(), "sway_from": 0.35, "sway_to": 0.55, "cap": true})
		if rng.randf() < 0.65:
			tuft += 1
			_snow_tuft(kit, end, maxf(radius * 2.6, 0.12), 0.35, seed_value + 300 + tuft)
	_snow_tuft(kit, fork, BUILD_HEIGHT * 0.04, 0.0, seed_value + 299)
	_snow_tuft(far, fork, BUILD_HEIGHT * 0.05, 0.0, seed_value + 298)


## A soft lump of snow sitting on top of at.
static func _snow_tuft(kit: RefCounted, at: Vector3, size: float, sway: float, seed_value: int) -> void:
	# Smooth-shaded: snow is soft, unlike the faceted leaf clumps.
	kit.call("blob", at + Vector3(0.0, size * 0.3, 0.0), Vector3(size, size * 0.42, size), SNOW_WHITE, {"detail": 1, "lumps": 0.3, "outward": true, "flat": false, "sway": sway, "seed": seed_value, "jitter": 0.02})


# ---------------------------------------------------------------- far LOD

## A crown for far away: a few big detail-1 blobs over the near crown's clumps
## ([center, size, color]) in their average color, no cards. A crown much taller
## than it is wide stacks its blobs; the rest get one in the middle and a ring.
static func _far_crown(kit: RefCounted, clumps: Array, seed_value: int, count: int) -> void:
	if clumps.is_empty():
		return
	var low := Vector3(INF, INF, INF)
	var high := -low
	var red := 0.0
	var green := 0.0
	var blue := 0.0
	for entry: Array in clumps:
		var at: Vector3 = entry[0]
		var size: Vector3 = entry[1]
		var color: Color = entry[2]
		low = low.min(at - size * 1.05)
		high = high.max(at + size * 1.05)
		red += color.r
		green += color.g
		blue += color.b
	var share := 1.0 / float(clumps.size())
	var tint := Color(red * share, green * share, blue * share)
	var center := (low + high) * 0.5
	var half := (high - low) * 0.5
	var options := {"detail": 1, "lumps": 0.22, "outward": true, "jitter": 0.03, "soft": 0.6, "sway": 0.8}
	if half.y > maxf(half.x, half.z) * 1.4:
		# Tall and narrow: overlapping blobs up the crown, stepping side to side
		# so it doesn't read as a stack of balls.
		var turn := float(seed_value % 13)
		for index: int in count:
			var t := (float(index) + 0.5) / float(count)
			options["seed"] = seed_value + 500 + index
			var taper := lerpf(1.0, 0.6, t)
			var side := Vector3(cos(turn + float(index) * 2.4), 0.0, sin(turn + float(index) * 2.4)) * half.x * 0.22
			kit.call("blob", Vector3(center.x, lerpf(low.y + half.y * 0.15, high.y - half.y * 0.12, t), center.z) + side, Vector3(half.x * 0.8 * taper, half.y / float(count) * 1.6, half.z * 0.8 * taper), tint.lightened(t * 0.06), options)
		return
	options["seed"] = seed_value + 500
	kit.call("blob", center + Vector3(0.0, half.y * 0.15, 0.0), half * Vector3(0.74, 0.72, 0.74), tint.lightened(0.04), options)
	for index: int in count - 1:
		var angle := TAU * float(index) / float(count - 1) + float(seed_value % 7)
		options["seed"] = seed_value + 501 + index
		var at := center + Vector3(cos(angle) * half.x * 0.4, -half.y * 0.12, sin(angle) * half.z * 0.4)
		kit.call("blob", at, half * Vector3(0.58, 0.62, 0.58), tint, options)


## The far mesh's main limbs: every bone at least depth deep ([start, end,
## radius, depth, heading] from _limb), as one straight stick each, so a forked
## trunk still reads under the crown.
static func _far_limbs(far: RefCounted, bones: Array, depth: int, color: Color) -> void:
	for bone: Array in bones:
		if int(bone[3]) < depth:
			continue
		far.call("tube", PackedVector3Array([bone[0], bone[1]]), PackedFloat32Array([float(bone[2]) * 1.6, float(bone[2])]), color, 4, {"seed": 0, "cap": true, "jitter": 0.0, "sway_to": 0.35})


static func _finish(kit: RefCounted, far: RefCounted) -> Array:
	var near_mesh: ArrayMesh = kit.call("commit")
	var far_mesh: ArrayMesh = far.call("commit")
	near_mesh.set_meta("triangles", int(kit.call("vertex_count")) / 3)
	far_mesh.set_meta("triangles", int(far.call("vertex_count")) / 3)
	return [near_mesh, far_mesh]


# ---------------------------------------------------------------- evergreens

static func _pine(seed_value: int, form: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := _MeshKit.new()
	var far := _MeshKit.new()
	var height := BUILD_HEIGHT * rng.randf_range(0.95, 1.1)
	var trunk := PackedVector3Array([Vector3.ZERO, Vector3(0.0, height * 0.5, 0.0), Vector3(0.0, height * 0.95, 0.0)])
	kit.tube(trunk, PackedFloat32Array([0.24, 0.15, 0.05]), BARK.darkened(0.1), 7, {"seed": seed_value, "flare": 0.3})
	far.tube(PackedVector3Array([trunk[0], trunk[1]]), PackedFloat32Array([0.24, 0.15]), BARK.darkened(0.1), 5, {"seed": seed_value, "jitter": 0.0})
	var tiers := rng.randi_range(6, 7)
	var bottom := height * 0.16
	var shapes: Array = []
	for tier: int in tiers:
		var t := float(tier) / float(tiers - 1)
		var base_y := lerpf(bottom, height * 0.8, t)
		var radius := lerpf(height * 0.3, height * 0.08, t) * rng.randf_range(0.92, 1.08)
		var tall := lerpf(height * 0.32, height * 0.24, t)
		var color := PINE_GREEN.lightened(t * 0.12 + rng.randf_range(-0.03, 0.03))
		kit.cone(Vector3(0.0, base_y, 0.0), radius, tall, color, 9, {"seed": seed_value + tier, "sway": lerpf(0.5, 1.0, t), "droop": radius * 0.22, "lumps": 0.14})
		far.cone(Vector3(0.0, base_y, 0.0), radius, tall, color, 6, {"seed": seed_value + tier, "sway": lerpf(0.5, 1.0, t), "droop": radius * 0.22, "lumps": 0.1})
		shapes.append([base_y, radius, tall, lerpf(0.5, 1.0, t)])
	kit.occlude(Vector3(0.0, height * 0.45, 0.0), Vector3(height * 0.3, height * 0.55, height * 0.3), 0.2)
	if form == "snowy":
		# Snow caps: a white cone just over the top of every tier.
		for index: int in shapes.size():
			var shape: Array = shapes[index]
			var base_y: float = shape[0]
			var radius: float = shape[1]
			var tall: float = shape[2]
			var cap := {"seed": seed_value + 40 + index, "sway": float(shape[3]), "droop": radius * 0.08, "lumps": 0.08}
			kit.cone(Vector3(0.0, base_y + tall * 0.3, 0.0), radius * 0.78, tall * 0.72, SNOW_WHITE, 9, cap)
			far.cone(Vector3(0.0, base_y + tall * 0.3, 0.0), radius * 0.78, tall * 0.72, SNOW_WHITE, 6, cap)
	return _finish(kit, far)


static func _cypress(seed_value: int, form: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := _MeshKit.new()
	var far := _MeshKit.new()
	var height := BUILD_HEIGHT * rng.randf_range(1.0, 1.12)
	var trunk := PackedVector3Array([Vector3.ZERO, Vector3(0.0, height * 0.18, 0.0), Vector3(0.0, height * 0.4, 0.0)])
	var radii := PackedFloat32Array([height * 0.035, height * 0.028, height * 0.02])
	kit.tube(trunk, radii, BARK.darkened(0.05), 7, {"seed": seed_value, "flare": 0.3})
	far.tube(PackedVector3Array([trunk[0], trunk[2]]), PackedFloat32Array([radii[0], radii[2]]), BARK.darkened(0.05), 5, {"seed": seed_value, "jitter": 0.0})
	# A column of stacked blobs, widest a third of the way up, to a soft point.
	var crown_start := kit.vertex_count()
	var stacks := 7
	var clumps: Array = []
	var colors: Array = [CYPRESS_GREEN, CYPRESS_GREEN.lightened(0.12)]
	var leaf_options := {"detail": 2, "lumps": 0.32, "lump_scale": 1.1, "jitter": 0.02, "soft": 0.75}
	for stack: int in stacks:
		var t := float(stack) / float(stacks - 1)
		var y := lerpf(height * 0.16, height * 0.84, t)
		var bulge := 1.0 + 0.18 * sin(clampf(t * 1.6, 0.0, 1.0) * PI)
		var radius := height * lerpf(0.105, 0.04, pow(t, 1.3)) * bulge * rng.randf_range(0.94, 1.06)
		var wobble := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * radius * 0.12
		var size := Vector3(radius, height * 0.1, radius)
		var color := CYPRESS_GREEN.lightened(t * 0.1 + rng.randf_range(-0.02, 0.03))
		leaf_options["seed"] = seed_value + stack
		leaf_options["sway"] = lerpf(0.25, 0.75, t)
		kit.blob(Vector3(0.0, y, 0.0) + wobble, size, color, leaf_options)
		clumps.append([Vector3(0.0, y, 0.0) + wobble, size, color])
	var tip := Vector3(0.0, height * 0.95, 0.0)
	leaf_options["seed"] = seed_value + 50
	leaf_options["sway"] = 0.85
	kit.blob(tip, Vector3(height * 0.028, height * 0.06, height * 0.028), CYPRESS_GREEN.lightened(0.12), leaf_options)
	clumps.append([tip, Vector3(height * 0.028, height * 0.06, height * 0.028), CYPRESS_GREEN.lightened(0.12)])
	_cards(kit, rng, clumps, colors, 16, height * 0.12, Vector2(0.14, 0.2))
	kit.grade(crown_start, height * 0.1, height, 0.7, 1.08)
	kit.occlude(Vector3(0.0, height * 0.45, 0.0), Vector3(height * 0.12, height * 0.5, height * 0.12), 0.25)
	var far_start := far.vertex_count()
	_far_crown(far, clumps, seed_value, 3)
	far.grade(far_start, height * 0.1, height, 0.7, 1.08)
	if form == "snowy":
		# A little snow on the point and on two of the bulges.
		_snow_tuft(kit, tip + Vector3(0.0, height * 0.02, 0.0), height * 0.03, 0.85, seed_value + 60)
		_snow_tuft(far, tip + Vector3(0.0, height * 0.02, 0.0), height * 0.035, 0.85, seed_value + 60)
		for index: int in 2:
			var clump: Array = clumps[1 + index * 2]
			var at: Vector3 = clump[0]
			var size: Vector3 = clump[1]
			var angle := rng.randf_range(0.0, TAU)
			_snow_tuft(kit, at + Vector3(cos(angle) * size.x * 0.55, size.y * 0.55, sin(angle) * size.z * 0.55), size.x * 0.5, 0.5, seed_value + 61 + index)
	return _finish(kit, far)


# ---------------------------------------------------------------- birch

static func _birch(seed_value: int, crown: String, form: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := _MeshKit.new()
	var far := _MeshKit.new()
	var height := BUILD_HEIGHT
	var colors: Array = CROWNS.get(crown, CROWNS["yellow"])
	# A slender white trunk that runs nearly to the top, with a gentle lean.
	var trunk_height := height * rng.randf_range(0.84, 0.9)
	var radius := height * 0.03
	var lean := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.2, 0.5)
	var trunk := PackedVector3Array()
	var radii := PackedFloat32Array()
	for step: int in 6:
		var t := float(step) / 5.0
		trunk.append(Vector3(0.0, t * trunk_height, 0.0) + lean * t * t)
		radii.append(lerpf(radius * 1.15, radius * 0.3, t))
	kit.tube(trunk, radii, BIRCH_BARK, 8, {"seed": seed_value, "flare": 0.25, "jitter": 0.02, "sway_from": 0.0, "sway_to": 0.25})
	far.tube(PackedVector3Array([trunk[0], trunk[3], trunk[5]]), PackedFloat32Array([radii[0], radii[3], radii[5]]), BIRCH_BARK, 5, {"seed": seed_value, "jitter": 0.0, "sway_to": 0.25})
	# Dark marks: short horizontal dashes and a few knots, sunk into the bark.
	for mark: int in 16:
		var t := rng.randf_range(0.04, 0.8)
		var at := _along(trunk, t)
		var mark_radius := _along_radius(radii, t)
		var angle := rng.randf_range(0.0, TAU)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		# Right-handed (across, up, outward), so the mark isn't turned inside out.
		var across := Vector3.UP.cross(outward).normalized()
		var basis := Basis(across, Vector3.UP, outward)
		var wide := mark_radius * rng.randf_range(0.35, 0.75)
		var tall := height * rng.randf_range(0.005, 0.011) * (2.2 if mark % 5 == 0 else 1.0)
		kit.rbox(at + outward * mark_radius * 0.92, Vector3(wide, tall, mark_radius * 0.18), BIRCH_MARK, 4.0, {"detail": 0, "basis": basis, "shade": false, "sway": t * 0.25})
	# Thin limbs climb off the upper half of the trunk, spiralling round it,
	# longest low down so the crown is an upright oval.
	var tips: Array[Vector3] = []
	var bones: Array = []
	var limbs := rng.randi_range(9, 11)
	var turn := rng.randf_range(0.0, TAU)
	for limb: int in limbs:
		var t := lerpf(0.4, 0.95, float(limb) / float(limbs - 1)) + rng.randf_range(-0.03, 0.03)
		var angle := turn + float(limb) * 2.4 + rng.randf_range(-0.3, 0.3)
		var direction := Vector3(cos(angle), rng.randf_range(0.6, 1.2), sin(angle)).normalized()
		var start := _along(trunk, t)
		_limb(kit, rng, start, direction, height * rng.randf_range(0.15, 0.22) * (1.0 - t * 0.45), _along_radius(radii, t) * 0.55, 0, tips, bones, BARK.darkened(0.2))
	var top := trunk[trunk.size() - 1]
	tips.append(top)
	if form == "bare":
		_bare_top(kit, far, seed_value, bones, _along(trunk, 0.6), BARK.darkened(0.2), true)
		return _finish(kit, far)
	# A narrow, airy crown of small clumps hung off the limbs, with gaps the
	# white trunk shows through, and two small ones against the trunk to fill it.
	var crown_start := kit.vertex_count()
	var clump := height * 0.085
	var clumps: Array = []
	var leaf_options := {"detail": 2, "lumps": 0.42, "lump_scale": 1.1, "sway": 1.0, "jitter": 0.02, "soft": 0.8}
	var index := 0
	var crown_low := _along(trunk, 0.4).y
	for tip: Vector3 in tips:
		index += 1
		var share := (tip.y - crown_low) / maxf(height - crown_low, 0.1)
		var color := _crown_color(rng, colors, share)
		var size := Vector3.ONE * clump * rng.randf_range(0.75, 1.15)
		size.y *= rng.randf_range(0.7, 0.9)
		var at := tip + Vector3(0.0, clump * 0.1, 0.0)
		if _crowded(clumps, at, clump * MERGE_SHARE):
			continue
		leaf_options["seed"] = seed_value + index
		kit.blob(at, size, color, leaf_options)
		clumps.append([at, size, color])
	for filler: int in 2:
		var t := lerpf(0.62, 0.82, float(filler))
		var angle := turn + PI * float(filler) + rng.randf_range(-0.5, 0.5)
		var at := _along(trunk, t) + Vector3(cos(angle), 0.0, sin(angle)) * clump * 0.7
		var color := _crown_color(rng, colors, (at.y - crown_low) / maxf(height - crown_low, 0.1))
		var size := Vector3(clump, clump * 1.2, clump) * rng.randf_range(0.9, 1.1)
		leaf_options["seed"] = seed_value + 100 + filler
		leaf_options["sway"] = 0.7
		kit.blob(at, size, color, leaf_options)
		clumps.append([at, size, color])
	_cards(kit, rng, clumps, colors, _card_count(kit, clumps.size(), 22, 0), clump, Vector2(0.2, 0.3))
	kit.grade(crown_start, crown_low - clump, height + clump, 0.66, 1.12)
	var crown_center := Vector3(top.x * 0.7, (crown_low + height) * 0.5, top.z * 0.7)
	var crown_radii := Vector3(height * 0.16, (height - crown_low) * 0.6, height * 0.16)
	kit.occlude(crown_center, crown_radii * 1.2, 0.28)
	var far_start := far.vertex_count()
	_far_crown(far, clumps, seed_value, 4)
	far.grade(far_start, crown_low - clump, height + clump, 0.66, 1.12)
	far.occlude(crown_center, crown_radii * 1.2, 0.28)
	return _finish(kit, far)


## The point a share t (0-1) of the way along a polyline, by index.
static func _along(points: PackedVector3Array, t: float) -> Vector3:
	var at := clampf(t, 0.0, 1.0) * float(points.size() - 1)
	var index := mini(int(at), points.size() - 2)
	return points[index].lerp(points[index + 1], at - float(index))


static func _along_radius(radii: PackedFloat32Array, t: float) -> float:
	var at := clampf(t, 0.0, 1.0) * float(radii.size() - 1)
	var index := mini(int(at), radii.size() - 2)
	return lerpf(radii[index], radii[index + 1], at - float(index))


# ---------------------------------------------------------------- willow

static func _willow(seed_value: int, crown: String, form: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := _MeshKit.new()
	var far := _MeshKit.new()
	var height := BUILD_HEIGHT
	var colors: Array = CROWNS.get(crown, CROWNS["yellow"])
	var bare := form == "bare"
	# A short, stout, leaning trunk.
	var trunk_height := height * rng.randf_range(0.26, 0.32)
	var base_radius := height * 0.065
	var lean := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.2, 0.45)
	var trunk := PackedVector3Array()
	var radii := PackedFloat32Array()
	for step: int in 4:
		var t := float(step) / 3.0
		trunk.append(Vector3(0.0, t * trunk_height, 0.0) + lean * t * t)
		radii.append(lerpf(base_radius * 1.1, base_radius * 0.75, t))
	kit.tube(trunk, radii, BARK.darkened(0.08), 9, {"seed": seed_value, "flare": 0.5, "cap": false})
	far.tube(PackedVector3Array([trunk[0], trunk[3]]), PackedFloat32Array([radii[0] * 1.2, radii[3]]), BARK.darkened(0.08), 6, {"seed": seed_value, "cap": false, "jitter": 0.0})
	var top := trunk[trunk.size() - 1]
	# A few heavy limbs arch up and out, splitting once.
	var tips: Array[Vector3] = []
	var bones: Array = []
	var limbs := rng.randi_range(3, 4)
	var turn := rng.randf_range(0.0, TAU)
	for limb: int in limbs:
		var angle := turn + TAU * float(limb) / float(limbs) + rng.randf_range(-0.3, 0.3)
		var direction := Vector3(cos(angle), rng.randf_range(0.9, 1.4), sin(angle)).normalized()
		_limb(kit, rng, top, direction, height * rng.randf_range(0.22, 0.28), base_radius * 0.5, 1, tips, bones, BARK.darkened(0.08))
	var crown_start := kit.vertex_count()
	var clump := height * 0.17
	var clumps: Array = []
	var middle := Vector3.ZERO
	var crown_top := 0.0
	for tip: Vector3 in tips:
		middle += tip / float(tips.size())
		crown_top = maxf(crown_top, tip.y + clump)
	if not bare:
		# The dome: a clump on each limb tip and two on top.
		var leaf_options := {"detail": 2, "lumps": 0.36, "lump_scale": 0.9, "sway": 0.8, "jitter": 0.02, "soft": 0.8}
		var index := 0
		for tip: Vector3 in tips:
			index += 1
			var color := _crown_color(rng, colors, 0.3 + (tip.y - middle.y) / maxf(clump * 2.0, 0.1))
			var size := Vector3(clump, clump * 0.78, clump) * rng.randf_range(0.85, 1.15)
			# The farther out, the lower: the dome weeps at its rim.
			var out_by := Vector2(tip.x - middle.x, tip.z - middle.z).length()
			var at := tip + Vector3(0.0, clump * 0.1 - out_by * 0.35, 0.0)
			if _crowded(clumps, at, clump * MERGE_SHARE):
				continue
			leaf_options["seed"] = seed_value + index
			kit.blob(at, size, color, leaf_options)
			clumps.append([at, size, color])
		for filler: int in 2:
			var angle := turn + PI * float(filler) + rng.randf_range(-0.4, 0.4)
			var at := middle + Vector3(cos(angle) * clump * 0.5, clump * 0.55, sin(angle) * clump * 0.5)
			var size := Vector3(clump * 1.25, clump * 0.75, clump * 1.25)
			leaf_options["seed"] = seed_value + 100 + filler
			leaf_options["sway"] = 0.6
			var color := _crown_color(rng, colors, 0.85)
			kit.blob(at, size, color, leaf_options)
			clumps.append([at, size, color])
		# Room for the strands and their cards (about 56 triangles each) first.
		_cards(kit, rng, clumps, colors, _card_count(kit, clumps.size(), 16, WILLOW_STRANDS * 56), clump, Vector2(0.14, 0.2))
	# Strands hang nearly to the ground from the rims of the dome's clumps (from
	# the limbs themselves when bare), so none starts out in the air.
	var strands := WILLOW_STRANDS if not bare else WILLOW_STRANDS - 8
	var strand_color: Color = WILLOW_TWIG if bare else (colors[0] as Color).darkened(0.08)
	var hangers: Array = []
	if bare:
		for bone: Array in bones:
			if int(bone[3]) == 0:
				hangers.append([bone[0], bone[1]])
	else:
		for entry: Array in clumps:
			# Only clumps out on the limbs, not the two on top.
			var at: Vector3 = entry[0]
			if Vector2(at.x - middle.x, at.z - middle.z).length() > clump * 0.4:
				hangers.append(entry)
		if hangers.is_empty():
			hangers = clumps
	for strand: int in strands:
		var start: Vector3
		if bare:
			var hanger: Array = hangers[strand % hangers.size()]
			start = (hanger[0] as Vector3).lerp(hanger[1], rng.randf_range(0.45, 1.0))
		else:
			# Evenly round the tree: from the clump that reaches farthest that
			# way, at its rim, so the strands make one curtain.
			var spin := TAU * float(strand) / float(strands) + rng.randf_range(-0.08, 0.08)
			var way := Vector3(cos(spin), 0.0, sin(spin))
			var hanger: Array = hangers[0]
			var best := -INF
			for entry: Array in hangers:
				var reach := ((entry[0] as Vector3) - middle).dot(way) + (entry[1] as Vector3).x
				if reach > best:
					best = reach
					hanger = entry
			var center: Vector3 = hanger[0]
			var size: Vector3 = hanger[1]
			start = center + way * size.x * 0.85 + Vector3(0.0, -size.y * 0.25, 0.0)
		var out := Vector3(start.x - middle.x, 0.0, start.z - middle.z)
		out = out.normalized() if out.length() > 0.05 else Vector3.RIGHT
		var drop := start.y - height * rng.randf_range(0.07, 0.22)
		var points := PackedVector3Array()
		for step: int in 4:
			var t := float(step) / 3.0
			points.append(start + out * (sin(t * PI * 0.5) * height * 0.07) + Vector3(0.0, -drop * t, 0.0))
		kit.tube(points, PackedFloat32Array([0.04, 0.03, 0.022, 0.012]), strand_color, 4, {"seed": seed_value + 200 + strand, "sway_from": 0.45, "sway_to": 1.0, "cap": true, "jitter": 0.05})
		# Far, every strand is one thicker stick, so the curtain still reads.
		far.tube(PackedVector3Array([points[0], points[3]]), PackedFloat32Array([0.09, 0.05]), strand_color.darkened(0.12), 3, {"seed": seed_value + 200 + strand, "sway_from": 0.45, "sway_to": 1.0, "jitter": 0.0})
		if bare:
			continue
		for card: int in 7:
			var t := (float(card) + rng.randf_range(0.2, 0.8)) / 7.0
			var spot := _along(points, t)
			var facing := (out + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.6, 0.6))).normalized()
			var tint := strand_color.lerp(colors[1], rng.randf_range(0.0, 0.4)).lightened(rng.randf_range(0.0, 0.08))
			kit.leaf_card(spot, facing, height * rng.randf_range(0.03, 0.042), tint, lerpf(0.5, 1.0, t), rng.randf_range(-0.5, 0.5))
	if bare:
		_bare_top(kit, far, seed_value, bones, top, BARK.darkened(0.08), false)
		return _finish(kit, far)
	kit.grade(crown_start, height * 0.1, crown_top, 0.6, 1.12)
	var dome_radii := Vector3(clump * 2.4, crown_top - height * 0.1, clump * 2.4) * 0.6
	kit.occlude(Vector3(middle.x, (crown_top + height * 0.1) * 0.5, middle.z), dome_radii * 1.3, 0.3)
	# Far: the limbs and the dome over the strand sticks.
	_far_limbs(far, bones, 1, BARK.darkened(0.08))
	var far_start := far.vertex_count()
	_far_crown(far, clumps, seed_value, 3)
	far.grade(far_start, height * 0.1, crown_top, 0.6, 1.12)
	return _finish(kit, far)
