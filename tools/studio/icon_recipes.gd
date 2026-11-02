extends RefCounted

## Dev tool data: how every icon in ui/icons.gd IDS is made, read by
## tools/studio/icon_studio.gd. RECIPES maps id -> a recipe:
##
##   "kind"   "model" (a 3D model on its own), "badge" (a flat disc or shield with
##            a 3D emblem over it), or, for the flat families, "flat" | "tile" | "key"
##   "px"     output size: 256 for 3D icons and badges, 128 flat, 64-tall keys
##   "yaw"    degrees the subject turns about Y before it is framed (models face
##            -Z and the camera looks from +Z, so 180 shows a model's front)
##   "tilt"   optional Vector3 degrees, the subject's pose before the yaw
##   "roll"   optional degrees the camera turns about its view axis: long, thin
##            tools lie corner to corner so they still read at SIZE_ROW (20 px)
##   "pad"    optional margin share, overriding MODEL_PADDING / BADGE_PADDING
##   "sticker_color" optional fill of the "plus" sticker (gold for a second tier)
##   "build"  model and badge: the static builder below that makes the subject,
##            with "model" / "color" / "size" read by build_model
##   "sticker" optional: "plus" puts the orange upgrade sticker in the corner
##   "shape"  badge: "disc" or "shield"; "color" its fill; "rim" its edge
##   "emblem_rect" badge: where the 3D render sits, in 0..1 of the icon
##   "draw"   flat, tile and key: a static draw_* func (chunk B)
##
## Builders take (root: Node3D, recipe: Dictionary) and add the subject under
## root, 1 unit = 1 meter as in the game; framing is automatic. Draw funcs take
## (canvas: CanvasItem, size: float, recipe: Dictionary) and draw into a square
## canvas size px wide. Everything is built from the game's own code models
## (props/yard_models.gd, props/vehicles.gd, levels/lots/task_looks.gd ...), so
## an icon changes when its model does: re-run the generator with --only=<id>.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _YardModels = preload("res://props/yard_models.gd")
const _Vehicles = preload("res://props/vehicles.gd")
const _PropLooks = preload("res://props/prop_looks.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _TaskLooks = preload("res://levels/lots/task_looks.gd")

# Palette, copied from the UI's own constants.
const ORANGE := Color(0.93, 0.47, 0.13)
const INK := Color(0.17, 0.14, 0.11)
const PAPER := Color(0.97, 0.93, 0.84)
const GREEN := Color(0.2, 0.6, 0.3)
const RED := Color(0.75, 0.2, 0.15)
const NIGHT := Color(0.16, 0.2, 0.34)
const GOLD := Color(1.0, 0.78, 0.2)
const WHITE := Color(1.0, 1.0, 1.0)

## Task badge disc colors, by work family (docs/GAME.md, "Icons").
const FAMILY_COLORS: Dictionary = {
	"leaves": Color(0.93, 0.52, 0.18),
	"lawn": Color(0.42, 0.7, 0.3),
	"water": Color(0.32, 0.62, 0.9),
	"heights": Color(0.62, 0.44, 0.28),
	"paint": Color(0.96, 0.88, 0.7),
	"hedges": Color(0.18, 0.44, 0.26),
	"by_hand": Color(0.98, 0.8, 0.28),
}
## Rank shield fill and rim, Rake Rookie (0) to The Lawnfather (8): wood, orange,
## kraft, bronze, green, silver, gold, purple, then black and gold.
const RANK_COLORS: Array[Color] = [
	Color(0.66, 0.47, 0.3), Color(0.93, 0.52, 0.18), Color(0.8, 0.64, 0.42),
	Color(0.74, 0.46, 0.24), Color(0.28, 0.62, 0.34), Color(0.78, 0.8, 0.84),
	Color(0.98, 0.77, 0.22), Color(0.52, 0.32, 0.72), Color(0.13, 0.12, 0.13),
]
const RANK_RIMS: Array[Color] = [
	Color(0.42, 0.28, 0.16), Color(0.66, 0.3, 0.08), Color(0.52, 0.38, 0.22),
	Color(0.48, 0.27, 0.12), Color(0.14, 0.38, 0.2), Color(0.5, 0.53, 0.58),
	Color(0.74, 0.5, 0.08), Color(0.32, 0.17, 0.48), Color(1.0, 0.78, 0.2),
]

const MODEL_LOOK := {"roughness": 0.7, "specular": 0.2}
const LITTER_CAN_SEED: int = 1
const WHEELBARROW_RED := Color(0.55, 0.22, 0.18)
const TRASH_GREY := Color(0.25, 0.28, 0.3)
const CHEFTY_RED := Color(0.75, 0.22, 0.15)
const VAN_GREY := Color(0.16, 0.17, 0.2)
const HEDGE_GREEN := Color(0.2, 0.42, 0.22)

## Where a task vignette sits over its disc: a bit low, poking over the rim.
const TASK_RECT := Rect2(0.07, 0.1, 0.88, 0.88)
const RANK_RECT := Rect2(0.15, 0.1, 0.7, 0.72)
## Margin around a 3D subject's bounds, as a share of its frame on each side:
## the whole icon for models, the emblem rect for badges (they sit tighter).
const MODEL_PADDING: float = 0.08
const BADGE_PADDING: float = 0.03
## A badge's vignette gets its own ink ring this wide, against the outer outline.
const STICKER_SHARE: float = 0.8

const RECIPES: Dictionary = {
	# ---- tools (256, 3D)
	"tool_leaf_blower": {"kind": "model", "px": 256, "build": "build_model", "model": "leaf_blower", "yaw": 120.0, "roll": -30.0},
	"tool_lawn_mower": {"kind": "model", "px": 256, "build": "build_model", "model": "lawn_mower", "yaw": 200.0},
	"tool_ladder": {"kind": "model", "px": 256, "build": "build_model", "model": "ladder", "yaw": 160.0, "tilt": Vector3(-72.0, 0.0, 0.0), "roll": 40.0},
	"tool_hose": {"kind": "model", "px": 256, "build": "build_model", "model": "hose", "yaw": 105.0},
	"tool_pressure_washer": {"kind": "model", "px": 256, "build": "build_model", "model": "pressure_washer", "yaw": 200.0},
	"tool_hedge_trimmer": {"kind": "model", "px": 256, "build": "build_model", "model": "hedge_trimmer", "yaw": 150.0, "tilt": Vector3(25.0, 0.0, 60.0), "roll": 30.0},
	"tool_paint_roller": {"kind": "model", "px": 256, "build": "build_model", "model": "paint_roller", "yaw": 120.0, "tilt": Vector3(-35.0, 0.0, 0.0), "roll": -15.0},
	# ---- items (256, 3D)
	"item_rake": {"kind": "model", "px": 256, "build": "build_model", "model": "rake", "yaw": 200.0, "tilt": Vector3(0.0, 0.0, -38.0)},
	"item_leaf_bag": {"kind": "model", "px": 256, "build": "build_model", "model": "leaf_bag", "yaw": 200.0},
	"item_wheelbarrow": {"kind": "model", "px": 256, "build": "build_model", "model": "wheelbarrow", "color": WHEELBARROW_RED, "yaw": 125.0},
	"item_gnome": {"kind": "model", "px": 256, "build": "build_model", "model": "gnome", "yaw": 200.0},
	"item_trash": {"kind": "model", "px": 256, "build": "build_model", "model": "trash", "color": TRASH_GREY, "yaw": 200.0},
	"item_hydrant": {"kind": "model", "px": 256, "build": "build_model", "model": "hydrant", "yaw": 200.0},
	"item_paint_bucket": {"kind": "model", "px": 256, "build": "build_model", "model": "paint_bucket", "yaw": 20.0},
	"item_water_tank": {"kind": "model", "px": 256, "build": "build_model", "model": "water_tank", "yaw": 30.0},
	"item_turf_sign": {"kind": "model", "px": 256, "build": "build_turf_sign", "yaw": 15.0},
	"item_chefty": {"kind": "model", "px": 256, "build": "build_chefty", "yaw": 145.0},
	"item_van": {"kind": "model", "px": 256, "build": "build_van", "yaw": 145.0},
	# ---- upgrades: the base model plus the "+" sticker
	"upgrade_rake_tier_1": {"kind": "model", "px": 256, "build": "build_model", "model": "rake", "yaw": 200.0, "tilt": Vector3(0.0, 0.0, -38.0), "sticker": "plus"},
	"upgrade_rake_tier_2": {"kind": "model", "px": 256, "build": "build_model", "model": "rake", "yaw": 200.0, "tilt": Vector3(0.0, 0.0, -38.0), "sticker": "plus", "sticker_color": GOLD},
	"upgrade_wheelbarrow_tier_1":{"kind": "model", "px": 256, "build": "build_model", "model": "wheelbarrow", "color": WHEELBARROW_RED, "yaw": 125.0, "sticker": "plus"},
	# ---- task badges (256): a disc in the family color, a vignette over its rim
	"task_rake_leaves": {"kind": "badge", "px": 256, "shape": "disc", "family": "leaves", "build": "build_task_rake_leaves", "yaw": 200.0},
	"task_pick_litter": {"kind": "badge", "px": 256, "shape": "disc", "family": "by_hand", "build": "build_task_pick_litter", "yaw": 160.0},
	"task_pull_weeds": {"kind": "badge", "px": 256, "shape": "disc", "family": "by_hand", "build": "build_task_pull_weeds", "yaw": 0.0},
	"task_mow_lawn": {"kind": "badge", "px": 256, "shape": "disc", "family": "lawn", "build": "build_task_mow_lawn", "yaw": 200.0},
	"task_clean_gutters": {"kind": "badge", "px": 256, "shape": "disc", "family": "heights", "build": "build_task_clean_gutters", "yaw": 20.0},
	"task_wash_windows": {"kind": "badge", "px": 256, "shape": "disc", "family": "water", "build": "build_task_wash_windows", "yaw": 0.0},
	"task_power_wash": {"kind": "badge", "px": 256, "shape": "disc", "family": "water", "build": "build_task_power_wash", "yaw": 10.0},
	"task_trim_hedges": {"kind": "badge", "px": 256, "shape": "disc", "family": "hedges", "build": "build_task_trim_hedges", "yaw": 10.0},
	"task_paint_fence": {"kind": "badge", "px": 256, "shape": "disc", "family": "paint", "build": "build_task_paint_fence", "yaw": 0.0},
	"task_clear_roof": {"kind": "badge", "px": 256, "shape": "disc", "family": "heights", "build": "build_task_clear_roof", "yaw": 0.0},
	"task_skim_pool": {"kind": "badge", "px": 256, "shape": "disc", "family": "water", "build": "build_task_skim_pool", "yaw": 0.0},
	# ---- rank badges (256): a shield climbing wood to black-and-gold, an emblem on it
	"rank_0": {"kind": "badge", "px": 256, "shape": "shield", "rank": 0, "build": "build_model", "model": "rake", "yaw": 200.0, "tilt": Vector3(0.0, 0.0, -38.0)},
	"rank_1": {"kind": "badge", "px": 256, "shape": "shield", "rank": 1, "build": "build_leaf", "yaw": 0.0},
	"rank_2": {"kind": "badge", "px": 256, "shape": "shield", "rank": 2, "build": "build_model", "model": "leaf_bag", "yaw": 200.0},
	"rank_3": {"kind": "badge", "px": 256, "shape": "shield", "rank": 3, "build": "build_model", "model": "wheelbarrow", "color": WHEELBARROW_RED, "yaw": 125.0},
	"rank_4": {"kind": "badge", "px": 256, "shape": "shield", "rank": 4, "build": "build_model", "model": "hedge", "color": HEDGE_GREEN, "size": Vector3(1.1, 0.85, 0.85), "yaw": 0.0},
	"rank_5": {"kind": "badge", "px": 256, "shape": "shield", "rank": 5, "build": "build_model", "model": "lawn_mower", "yaw": 200.0},
	"rank_6": {"kind": "badge", "px": 256, "shape": "shield", "rank": 6, "build": "build_gnome_crown", "yaw": 200.0},
	"rank_7": {"kind": "badge", "px": 256, "shape": "shield", "rank": 7, "build": "build_gnome_top_hat", "yaw": 200.0},
	"rank_8": {"kind": "badge", "px": 256, "shape": "shield", "rank": 8, "build": "build_gnome_fedora", "yaw": 200.0, "ring": GOLD},
}


## Supersampling: 3D and badge icons render at 2x, flat ones (chunk B) at 4x.
static func supersample(recipe: Dictionary) -> int:
	return 2 if str(recipe.get("kind", "")) in ["model", "badge"] else 4


## The 2D layer under the 3D render ("" for none) and over it.
static func base_painter(recipe: Dictionary) -> String:
	match str(recipe.get("kind", "")):
		"badge":
			return "draw_disc" if str(recipe.get("shape", "disc")) == "disc" else "draw_shield"
		"flat", "tile", "key":
			return str(recipe.get("draw", ""))
	return ""


static func top_painter(recipe: Dictionary) -> String:
	return "draw_plus_sticker" if str(recipe.get("sticker", "")) == "plus" else ""


static func padding(recipe: Dictionary) -> float:
	return BADGE_PADDING if str(recipe.get("kind", "")) == "badge" else MODEL_PADDING


static func sticker_share(recipe: Dictionary) -> float:
	return STICKER_SHARE if str(recipe.get("kind", "")) == "badge" else 0.0


## Where the 3D render sits in the icon, in 0..1.
static func subject_rect(recipe: Dictionary) -> Rect2:
	if recipe.has("emblem_rect"):
		return recipe["emblem_rect"]
	if str(recipe.get("kind", "")) == "badge":
		return TASK_RECT if str(recipe.get("shape", "disc")) == "disc" else RANK_RECT
	return Rect2(0.0, 0.0, 1.0, 1.0)


# ---------------------------------------------------------------- generic builders

## Any props/yard_models.gd kind, as the game draws it.
static func build_model(root: Node3D, recipe: Dictionary) -> void:
	var color: Color = recipe.get("color", Color.WHITE)
	var size: Vector3 = recipe.get("size", Vector3.ONE)
	root.add_child(_YardModels.node(str(recipe.get("model", "")), color, size, MODEL_LOOK))


## The rival's lawn sign, dressed the way a yard prop is.
static func build_turf_sign(root: Node3D, _recipe: Dictionary) -> void:
	var prop := Node3D.new()
	root.add_child(prop)
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.position.y = _PropLooks.VISUAL_HEIGHT
	prop.add_child(visual)
	_PropLooks.dress(prop, "turf_sign", Color.WHITE)


## Chefty, logo and all (DEC-006).
static func build_chefty(root: Node3D, _recipe: Dictionary) -> void:
	_Vehicles.build_truck(root, CHEFTY_RED)


static func build_van(root: Node3D, _recipe: Dictionary) -> void:
	_Vehicles.build_van(root, VAN_GREY)


static func _add_mesh(root: Node3D, mesh: Mesh, at: Vector3, basis: Basis = Basis.IDENTITY, scale: float = 1.0) -> MeshInstance3D:
	var node := _Stylized.instance(mesh, MODEL_LOOK)
	node.transform = Transform3D(basis.scaled(Vector3.ONE * scale), at)
	root.add_child(node)
	return node


static func _add_model(root: Node3D, kind: String, at: Vector3, basis: Basis = Basis.IDENTITY, color: Color = Color.WHITE, scale: float = 1.0) -> MeshInstance3D:
	var node := _YardModels.node(kind, color, Vector3.ONE, MODEL_LOOK)
	node.transform = Transform3D(basis.scaled(Vector3.ONE * scale), at)
	root.add_child(node)
	return node


static func _commit(root: Node3D, kit: RefCounted, at: Vector3 = Vector3.ZERO, basis: Basis = Basis.IDENTITY) -> void:
	var mesh: ArrayMesh = kit.call("commit")
	if mesh != null:
		_add_mesh(root, mesh, at, basis)


# ---------------------------------------------------------------- task vignettes

## A heap of leaves with the rake leaning into it.
static func build_task_rake_leaves(root: Node3D, _recipe: Dictionary) -> void:
	var kit := _MeshKit.new()
	kit.blob(Vector3(0.0, 0.16, 0.0), Vector3(0.5, 0.26, 0.42), Color(0.86, 0.46, 0.16), {"detail": 2, "lumps": 0.3, "lump_scale": 2.2, "flat": true, "soft": 0.5, "outward": true, "jitter": 0.08, "seed": 4})
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for index: int in 34:
		var angle := rng.randf() * TAU
		var lift := rng.randf_range(0.2, 1.0)
		var at := Vector3(cos(angle) * 0.46 * (1.0 - lift * 0.5), 0.12 + lift * 0.28, sin(angle) * 0.38 * (1.0 - lift * 0.5))
		kit.leaf_card(at, (at - Vector3(0.0, -0.1, 0.0)).normalized(), rng.randf_range(0.08, 0.12), _YardModels.LEAVES[index % _YardModels.LEAVES.size()], 0.0, rng.randf() * TAU)
	_commit(root, kit)
	# The rake leans on the pile, tines in the leaves.
	_add_model(root, "rake", Vector3(0.48, 0.18, 0.12), Basis(Vector3.BACK, 0.62) * Basis(Vector3.UP, 0.4), Color.WHITE, 0.85)


## A can, crumpled paper and a bottle, the litter the yard leaves behind.
static func build_task_pick_litter(root: Node3D, _recipe: Dictionary) -> void:
	# The can's color is a randi() pick inside task_looks; this seed lands on red,
	# so it stands apart from the green bottle.
	seed(LITTER_CAN_SEED)
	_add_mesh(root, _TaskLooks.mesh("can"), Vector3(0.16, 0.0, 0.18), Basis(Vector3.UP, 0.9), 2.6)
	_add_mesh(root, _TaskLooks.mesh("paper"), Vector3(-0.2, 0.0, -0.06), Basis.IDENTITY, 1.9)
	_add_mesh(root, _TaskLooks.mesh("bottle"), Vector3(0.06, 0.0, -0.12), Basis(Vector3.UP, -0.5), 1.8)


## A weed, dandelion and all, on a little mound of dirt.
static func build_task_pull_weeds(root: Node3D, _recipe: Dictionary) -> void:
	var kit := _MeshKit.new()
	kit.blob(Vector3(0.0, 0.0, 0.0), Vector3(0.24, 0.06, 0.24), Color(0.42, 0.3, 0.2), {"detail": 2, "lumps": 0.3, "lump_scale": 3.0, "flat": true, "jitter": 0.05, "seed": 2})
	_commit(root, kit)
	_add_mesh(root, _TaskLooks.mesh("weed"), Vector3(0.0, 0.03, 0.0))


## The mower on a striped tuft of lawn.
static func build_task_mow_lawn(root: Node3D, _recipe: Dictionary) -> void:
	var kit := _MeshKit.new()
	for stripe: int in 4:
		var shade := Color(0.38, 0.62, 0.26) if stripe % 2 == 0 else Color(0.3, 0.52, 0.22)
		kit.rbox(Vector3(-0.42 + float(stripe) * 0.28, 0.03, 0.0), Vector3(0.14, 0.04, 0.52), shade, 6.0, {"detail": 2})
	_commit(root, kit)
	_add_model(root, "lawn_mower", Vector3(0.05, 0.06, 0.05), Basis(Vector3.UP, 0.15), Color.WHITE, 0.95)


## A gutter run stuffed with gunk, and the top of the ladder leaning on it.
static func build_task_clean_gutters(root: Node3D, _recipe: Dictionary) -> void:
	var kit := _MeshKit.new()
	var white := Color(0.9, 0.9, 0.87)
	kit.rbox(Vector3(0.0, 0.0, 0.0), Vector3(0.55, 0.02, 0.1), white, 6.0, {"detail": 2})
	kit.rbox(Vector3(0.0, 0.08, 0.1), Vector3(0.55, 0.09, 0.015), white, 6.0, {"detail": 2})
	kit.rbox(Vector3(0.0, 0.1, -0.1), Vector3(0.55, 0.11, 0.015), white.darkened(0.1), 6.0, {"detail": 2})
	for side: float in [-1.0, 1.0]:
		kit.rbox(Vector3(side * 0.55, 0.08, 0.0), Vector3(0.015, 0.09, 0.11), white.darkened(0.05), 6.0, {"detail": 2})
	# The ladder's top two rungs, leaning in from the front.
	var metal := Color(0.78, 0.8, 0.82)
	var lean := Basis(Vector3.RIGHT, -0.32)
	for side: float in [-1.0, 1.0]:
		kit.rbox(Vector3(side * 0.2 + 0.18, -0.25, 0.28), Vector3(0.02, 0.4, 0.035), metal, 8.0, {"basis": lean})
	for rung: int in 2:
		var y := -0.12 - float(rung) * 0.3
		var z := 0.24 + float(rung) * 0.1
		kit.tube(PackedVector3Array([Vector3(-0.02, y, z), Vector3(0.38, y, z)]), PackedFloat32Array([0.016, 0.016]), metal.darkened(0.1), 6, {"jitter": 0.0})
	_commit(root, kit)
	_add_mesh(root, _TaskLooks.mesh("gunk"), Vector3(0.0, 0.04, 0.0), Basis.IDENTITY, 1.15)


## A window in a bit of siding, with the hose nozzle aimed at it.
static func build_task_wash_windows(root: Node3D, _recipe: Dictionary) -> void:
	var kit := _MeshKit.new()
	kit.rbox(Vector3(0.0, 0.5, -0.06), Vector3(0.62, 0.55, 0.05), Color(0.62, 0.72, 0.8), 8.0, {"detail": 2})
	_commit(root, kit)
	_LowPoly.window(root, 0.7, 0.6, Vector3(0.0, 0.52, 0.0), Color(0.96, 0.95, 0.9))
	var drops := _MeshKit.new()
	for index: int in 5:
		drops.blob(Vector3(0.12 + float(index) * 0.07, 0.36 + float(index % 2) * 0.05, 0.22 - float(index) * 0.04), Vector3(0.025, 0.035, 0.025), Color(0.7, 0.88, 1.0), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
	_commit(root, drops)
	_add_model(root, "nozzle", Vector3(0.52, 0.3, 0.42), Basis(Vector3.UP, -0.9) * Basis(Vector3.RIGHT, 0.2), Color.WHITE, 1.6)


## The spray wand over a slab that is half grimy, half clean.
static func build_task_power_wash(root: Node3D, _recipe: Dictionary) -> void:
	var kit := _MeshKit.new()
	kit.rbox(Vector3(-0.25, 0.0, 0.0), Vector3(0.26, 0.05, 0.42), Color(0.44, 0.4, 0.34), 7.0, {"detail": 2})
	kit.rbox(Vector3(0.25, 0.0, 0.0), Vector3(0.26, 0.05, 0.42), Color(0.86, 0.84, 0.8), 7.0, {"detail": 2})
	for index: int in 6:
		kit.blob(Vector3(-0.02 + float(index % 3) * 0.05, 0.08 + float(index / 3) * 0.04, -0.1 + float(index) * 0.04), Vector3(0.03, 0.03, 0.03), Color(0.75, 0.9, 1.0), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
	_commit(root, kit)
	_add_model(root, "wand", Vector3(0.38, 0.42, 0.3), Basis(Vector3.UP, 0.75) * Basis(Vector3.RIGHT, -0.22), Color.WHITE, 1.05)


## A shaggy hedge and the trimmer that's about to fix it.
static func build_task_trim_hedges(root: Node3D, _recipe: Dictionary) -> void:
	_add_mesh(root, _TaskLooks.mesh("shaggy"), Vector3(0.0, 0.0, 0.0))
	_add_model(root, "hedge_trimmer", Vector3(0.3, 0.12, 0.75), Basis(Vector3.UP, 0.75) * Basis(Vector3.BACK, 0.9) * Basis(Vector3.RIGHT, 0.35), Color.WHITE, 1.5)


## Three fence boards, one freshly white, and the roller.
static func build_task_paint_fence(root: Node3D, _recipe: Dictionary) -> void:
	var kit := _MeshKit.new()
	for board: int in 3:
		var color := _TaskLooks.FRESH_PAINT if board == 2 else _TaskLooks.FADED_PAINT.darkened(0.05 * float(board))
		kit.rbox(Vector3(-0.3 + float(board) * 0.3, 0.45, 0.0), Vector3(0.13, 0.45, 0.025), color, 8.0, {"detail": 2})
		kit.cone(Vector3(-0.3 + float(board) * 0.3, 0.9, 0.0), 0.13, 0.12, color, 4, {"lumps": 0.0})
	for y: float in [0.25, 0.7]:
		kit.rbox(Vector3(0.0, y, -0.05), Vector3(0.48, 0.04, 0.025), _TaskLooks.FADED_PAINT.darkened(0.2), 8.0, {"detail": 2})
	_commit(root, kit)
	_add_model(root, "paint_roller", Vector3(0.42, 0.42, 0.2), Basis(Vector3.UP, -0.4) * Basis(Vector3.RIGHT, 1.0), Color.WHITE, 1.4)


## A slab of shingles buried in leaves.
static func build_task_clear_roof(root: Node3D, _recipe: Dictionary) -> void:
	var slope := Basis(Vector3.RIGHT, 0.45)
	var kit := _MeshKit.new()
	var shingle := Color(0.46, 0.3, 0.27)
	for row: int in 4:
		kit.rbox(Vector3(0.0, 0.0, -0.4 + float(row) * 0.24), Vector3(0.62, 0.035, 0.14), shingle.darkened(0.06 * float(row % 2)), 7.0, {"detail": 2, "basis": Basis.IDENTITY})
	_commit(root, kit, Vector3.ZERO, slope)
	_add_mesh(root, _TaskLooks.mesh("roof_leaves"), slope * Vector3(0.0, 0.04, 0.0), slope)


## A curve of pool rim, blue water, and leaves floating on it.
static func build_task_skim_pool(root: Node3D, _recipe: Dictionary) -> void:
	var kit := _MeshKit.new()
	kit.rbox(Vector3(0.0, -0.02, 0.0), Vector3(0.6, 0.03, 0.55), Color(0.35, 0.7, 0.88), 8.0, {"detail": 2, "shade": false})
	var stone := Color(0.86, 0.82, 0.74)
	for step: int in 7:
		var angle := lerpf(-0.7, 0.7, float(step) / 6.0)
		var at := Vector3(sin(angle) * 0.75, 0.04, -cos(angle) * 0.75 + 0.35)
		kit.rbox(at, Vector3(0.12, 0.05, 0.09), stone.darkened(0.04 * float(step % 2)), 7.0, {"detail": 2, "basis": Basis(Vector3.UP, -angle)})
	_commit(root, kit)
	_add_mesh(root, _TaskLooks.mesh("pool_leaves"), Vector3(0.05, 0.02, 0.15), Basis.IDENTITY, 0.9)


# ---------------------------------------------------------------- rank emblems

## One big autumn leaf: a broad blade, two side lobes and a stem.
static func build_leaf(root: Node3D, _recipe: Dictionary) -> void:
	var kit := _MeshKit.new()
	var orange := Color(0.92, 0.5, 0.15)
	kit.leaf_card(Vector3(0.0, 0.36, 0.0), Vector3(0.0, 0.0, 1.0), 0.36, orange, 0.0, 0.0)
	kit.leaf_card(Vector3(-0.12, 0.26, -0.01), Vector3(0.0, 0.0, 1.0), 0.24, orange.darkened(0.08), 0.0, 0.95)
	kit.leaf_card(Vector3(0.12, 0.26, -0.01), Vector3(0.0, 0.0, 1.0), 0.24, orange.darkened(0.08), 0.0, -0.95)
	kit.tube(PackedVector3Array([Vector3(0.0, 0.26, 0.012), Vector3(0.0, 0.1, 0.012), Vector3(0.03, 0.0, 0.012)]), PackedFloat32Array([0.012, 0.012, 0.01]), Color(0.5, 0.3, 0.14), 5, {"jitter": 0.0})
	# Veins, so it reads as a leaf and not a kite.
	for side: float in [-1.0, 1.0]:
		kit.tube(PackedVector3Array([Vector3(0.0, 0.3, 0.014), Vector3(side * 0.13, 0.42, 0.014)]), PackedFloat32Array([0.006, 0.004]), orange.darkened(0.3), 4, {"jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0.0, 0.24, 0.014), Vector3(0.0, 0.6, 0.014)]), PackedFloat32Array([0.007, 0.004]), orange.darkened(0.3), 4, {"jitter": 0.0})
	_commit(root, kit)


## Lawn Lord: the gnome in a gold crown, his pointy hat poking out the top.
static func build_gnome_crown(root: Node3D, _recipe: Dictionary) -> void:
	_add_model(root, "gnome", Vector3.ZERO)
	var kit := _MeshKit.new()
	var gold := Color(1.0, 0.78, 0.22)
	kit.tube(PackedVector3Array([Vector3(0, 0.49, 0), Vector3(0, 0.6, 0)]), PackedFloat32Array([0.172, 0.176]), gold, 16, {"jitter": 0.0, "cap": false})
	for point: int in 6:
		var angle := TAU * float(point) / 6.0
		var at := Vector3(cos(angle) * 0.166, 0.59, sin(angle) * 0.166)
		kit.cone(at, 0.045, 0.1, gold, 5, {"lumps": 0.0})
		kit.blob(at + Vector3(0.0, 0.11, 0.0), Vector3(0.018, 0.018, 0.018), gold.lightened(0.2), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	for gem: int in 3:
		var angle := -PI * 0.5 + float(gem - 1) * 0.7
		kit.blob(Vector3(cos(angle) * 0.178, 0.545, sin(angle) * 0.178), Vector3(0.024, 0.024, 0.014), [Color(0.85, 0.15, 0.2), Color(0.2, 0.45, 0.9), Color(0.2, 0.7, 0.35)][gem], {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	_commit(root, kit)


## Yard Baron: the gnome in a tall top hat (it hides his own hat) and a monocle.
static func build_gnome_top_hat(root: Node3D, _recipe: Dictionary) -> void:
	_add_model(root, "gnome", Vector3.ZERO)
	var kit := _MeshKit.new()
	var black := Color(0.12, 0.11, 0.13)
	kit.tube(PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0, 0.53, 0)]), PackedFloat32Array([0.27, 0.27]), black, 18, {"jitter": 0.0, "cap_start": true})
	kit.tube(PackedVector3Array([Vector3(0, 0.52, 0), Vector3(0, 0.98, 0)]), PackedFloat32Array([0.16, 0.19]), black, 18, {"jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0, 0.56, 0), Vector3(0, 0.62, 0)]), PackedFloat32Array([0.17, 0.172]), Color(0.6, 0.12, 0.14), 18, {"jitter": 0.0, "cap": false})
	# The monocle, over his right eye, on a little gold chain.
	var ring := PackedVector3Array()
	var radii := PackedFloat32Array()
	for step: int in 17:
		var angle := TAU * float(step) / 16.0
		ring.append(Vector3(-0.05 + cos(angle) * 0.04, 0.47 + sin(angle) * 0.04, -0.135))
		radii.append(0.007)
	kit.tube(ring, radii, Color(1.0, 0.8, 0.3), 5, {"jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(-0.09, 0.46, -0.13), Vector3(-0.13, 0.36, -0.12), Vector3(-0.12, 0.28, -0.14)]), PackedFloat32Array([0.004, 0.004, 0.004]), Color(1.0, 0.8, 0.3), 4, {"jitter": 0.0})
	_commit(root, kit)


## The Lawnfather: the gnome in a black fedora, a rose in his lapel.
static func build_gnome_fedora(root: Node3D, _recipe: Dictionary) -> void:
	_add_model(root, "gnome", Vector3.ZERO)
	var kit := _MeshKit.new()
	var black := Color(0.13, 0.12, 0.14)
	var hat := _MeshKit.new()
	# A wide brim that dips at the front, and a crown that tapers to a pinched,
	# creased top (tall enough to hide his own pointy hat).
	hat.blob(Vector3(0.0, 0.56, 0.0), Vector3(0.27, 0.02, 0.25), black, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	hat.blob(Vector3(0.0, 0.55, -0.17), Vector3(0.17, 0.02, 0.08), black, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	hat.tube(PackedVector3Array([Vector3(0, 0.55, 0), Vector3(0, 0.72, 0), Vector3(0, 0.84, 0)]), PackedFloat32Array([0.17, 0.158, 0.12]), black, 18, {"jitter": 0.0})
	hat.blob(Vector3(0.0, 0.845, 0.0), Vector3(0.125, 0.03, 0.12), black, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	for side: float in [-1.0, 1.0]:
		hat.blob(Vector3(side * 0.1, 0.8, -0.07), Vector3(0.035, 0.05, 0.04), black.darkened(0.4), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	hat.blob(Vector3(0.0, 0.875, 0.01), Vector3(0.03, 0.012, 0.09), black.darkened(0.4), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	hat.tube(PackedVector3Array([Vector3(0, 0.58, 0), Vector3(0, 0.64, 0)]), PackedFloat32Array([0.182, 0.176]), Color(0.55, 0.1, 0.12), 18, {"jitter": 0.0, "cap": false})
	# Tipped down over one eye, the way it's worn.
	var tip := Basis(Vector3.BACK, 0.12) * Basis(Vector3.RIGHT, -0.06)
	var pivot := Vector3(0.0, 0.56, 0.0)
	_commit(root, hat, pivot - tip * pivot, tip)
	# A red rose and two leaves on his coat.
	var rose := Vector3(-0.09, 0.27, -0.15)
	kit.blob(rose, Vector3(0.04, 0.035, 0.035), Color(0.85, 0.12, 0.16), {"detail": 2, "lumps": 0.35, "lump_scale": 4.0, "flat": true, "jitter": 0.04, "seed": 9})
	kit.leaf_card(rose + Vector3(-0.04, -0.03, -0.01), Vector3(0.0, 0.3, -1.0), 0.04, Color(0.2, 0.5, 0.22), 0.0, 1.0)
	kit.leaf_card(rose + Vector3(0.04, -0.03, -0.01), Vector3(0.0, 0.3, -1.0), 0.04, Color(0.2, 0.5, 0.22), 0.0, -1.0)
	_commit(root, kit)


# ---------------------------------------------------------------- 2D layers

## A task badge: a flat disc in the work family's color, a darker rim, a soft
## highlight top-left and a thin inner ring.
static func draw_disc(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe.get("color", FAMILY_COLORS.get(str(recipe.get("family", "")), ORANGE))
	var center := Vector2(0.5, 0.48) * size
	var radius := 0.4 * size
	canvas.draw_circle(center, radius, color.darkened(0.28), true, -1.0, true)
	canvas.draw_circle(center, radius * 0.9, color, true, -1.0, true)
	canvas.draw_circle(center + Vector2(-0.09, -0.11) * size, radius * 0.5, color.lightened(0.14), true, -1.0, true)
	canvas.draw_circle(center + Vector2(-0.06, -0.07) * size, radius * 0.58, color.lightened(0.07), true, -1.0, true)
	canvas.draw_arc(center, radius * 0.8, 0.0, TAU, 96, color.lightened(0.22), size * 0.012, true)


## A rank badge: a heater shield in the rank's color, rim and bevel, a lighter left
## half, and gold studs across the top for the three highest ranks.
static func draw_shield(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var rank := clampi(int(recipe.get("rank", 0)), 0, RANK_COLORS.size() - 1)
	var fill := RANK_COLORS[rank]
	var rim := RANK_RIMS[rank]
	var outer := shield_points(size, 0.0)
	var inner := shield_points(size, 0.055 * size)
	canvas.draw_colored_polygon(outer, rim)
	canvas.draw_polyline(_closed(outer), rim, 1.5, true)
	canvas.draw_colored_polygon(inner, fill)
	canvas.draw_polyline(_closed(inner), fill, 1.5, true)
	# The left half catches the light.
	var half := PackedVector2Array()
	for point: Vector2 in inner:
		half.append(Vector2(minf(point.x, size * 0.5), point.y))
	canvas.draw_colored_polygon(half, fill.lightened(0.12 if rank != 8 else 0.08))
	canvas.draw_polyline(_closed(shield_points(size, 0.09 * size)), rim.lightened(0.15) if rank == 8 else fill.lightened(0.25), size * 0.01, true)
	if rank >= 6:
		for stud: int in rank - 5:
			var x := size * (0.5 + (float(stud) - float(rank - 6) * 0.5) * 0.1)
			canvas.draw_circle(Vector2(x, size * 0.155), size * 0.022, GOLD.lightened(0.2), true, -1.0, true)
			canvas.draw_circle(Vector2(x, size * 0.155), size * 0.022, GOLD.darkened(0.35), false, size * 0.006, true)


## The heater shield's outline, inset by inset pixels.
static func shield_points(size: float, inset: float) -> PackedVector2Array:
	var left := 0.15 * size + inset
	var right := 0.85 * size - inset
	var top := 0.1 * size + inset
	var shoulder := 0.52 * size
	var tip := Vector2(0.5 * size, 0.94 * size - inset * 1.4)
	var points := PackedVector2Array()
	# A gentle dip across the top edge.
	for step: int in 9:
		var t := float(step) / 8.0
		points.append(Vector2(lerpf(left, right, t), top + sin(t * PI) * 0.025 * size))
	points.append(Vector2(right, shoulder))
	for step: int in range(1, 13):
		var t := float(step) / 12.0
		points.append(_quad(Vector2(right, shoulder), Vector2(right, shoulder + 0.26 * size), tip, t))
	for step: int in range(1, 13):
		var t := float(step) / 12.0
		points.append(_quad(tip, Vector2(left, shoulder + 0.26 * size), Vector2(left, shoulder), t))
	return points


## The upgrade sticker: an orange disc with a fat white "+", top-right.
## "sticker_color" recolors it: a second upgrade tier wears gold.
static func draw_plus_sticker(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var center := Vector2(0.79, 0.21) * size
	var radius := 0.16 * size
	var fill: Color = recipe.get("sticker_color", ORANGE)
	canvas.draw_circle(center, radius, INK, true, -1.0, true)
	canvas.draw_circle(center, radius * 0.84, fill, true, -1.0, true)
	canvas.draw_circle(center + Vector2(-0.03, -0.035) * size, radius * 0.45, fill.lightened(0.15), true, -1.0, true)
	var arm := radius * 0.52
	var thick := radius * 0.34
	canvas.draw_rect(Rect2(center - Vector2(arm, thick * 0.5), Vector2(arm * 2.0, thick)), WHITE)
	canvas.draw_rect(Rect2(center - Vector2(thick * 0.5, arm), Vector2(thick, arm * 2.0)), WHITE)


static func _quad(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out
