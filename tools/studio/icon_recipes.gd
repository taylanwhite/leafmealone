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
##   "draw"   flat, tile and key: the static draw_* func that paints the icon; on a
##            badge, the flat shape under its emblem instead of the disc or shield
##   "color"  flat and tile: the fill the draw func is told to use (star, heart, tile)
##   "label"  key: the text on the cap; "glyph" draws an arrow or backspace instead
##   "wide"   key: twice as wide as tall (Tab, Esc, Space, Shift ...)
##   "mouse"  draw_mouse: which part is lit ("left", "right", "middle", "4", "5",
##            "wheel_up", "wheel_down")
##
## Builders take (root: Node3D, recipe: Dictionary) and add the subject under
## root, 1 unit = 1 meter as in the game; framing is automatic. Draw funcs take
## (canvas: CanvasItem, size: float, recipe: Dictionary) and draw into a canvas
## size px tall (and as wide, or twice as wide for a wide key). Everything is built from the game's own code models
## (props/yard_models.gd, props/vehicles.gd, levels/lots/task_looks.gd ...), so
## an icon changes when its model does: re-run the generator with --only=<id>.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _YardModels = preload("res://props/yard_models.gd")
const _Vehicles = preload("res://props/vehicles.gd")
const _PropLooks = preload("res://props/prop_looks.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _TaskLooks = preload("res://levels/lots/task_looks.gd")
const _ShopModels = preload("res://props/shop_models.gd")

# Palette, copied from the UI's own constants.
const ORANGE := Color(0.93, 0.47, 0.13)
const INK := Color(0.17, 0.14, 0.11)
const PAPER := Color(0.97, 0.93, 0.84)
const GREEN := Color(0.2, 0.6, 0.3)
const RED := Color(0.75, 0.2, 0.15)
const NIGHT := Color(0.16, 0.2, 0.34)
const GOLD := Color(1.0, 0.78, 0.2)
const WHITE := Color(1.0, 1.0, 1.0)
const KRAFT := Color(0.8, 0.6, 0.38)
const HEART_RED := Color(0.9, 0.26, 0.32)
const EMPTY_GREY := Color(0.72, 0.69, 0.64)
const FACE_YELLOW := Color(1.0, 0.8, 0.28)
const LEAF_ORANGE := Color(0.93, 0.5, 0.15)
const TEAR_BLUE := Color(0.45, 0.76, 1.0)

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
## A paint job's can beside Chefty (Chefty's space, faces -Z), and how much bigger
## than life it is so it reads next to a truck.
const PAINT_CAN_AT := Vector3(-1.75, 0.0, -2.2)
const PAINT_CAN_SCALE: float = 4.5
## The chips over a model (draw_chips): where they sit (0..1 of the icon), the tier
## chip's colors (the tier trim's: props/yard_models.gd), and the glyph chip's size.
const CHIP_RECT := Rect2(0.05, 0.7, 0.36, 0.22)
const GLYPH_CHIP_AT := Vector2(0.2, 0.79)
const GLYPH_CHIP_RADIUS: float = 0.14
const TAPE_GREY := Color(0.76, 0.77, 0.78)
const CHIP_RUST := Color(0.55, 0.28, 0.13)
const CHROME_LIGHT := Color(0.97, 0.98, 1.0)
const CHROME_DARK := Color(0.6, 0.63, 0.68)
const MK3_BLACK := Color(0.1, 0.1, 0.11)
const FLAME_RED := Color(0.92, 0.2, 0.08)
const FLAME_YELLOW := Color(1.0, 0.85, 0.25)
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
	# ---- gear (256, 3D; driving G1): yours to keep. The Gutter Shredder rolled toward
	# the camera and laid corner to corner, so the grip and the yellow wheels read at row size.
	"gear_skateboard": {"kind": "model", "px": 256, "build": "build_skateboard", "yaw": 60.0, "tilt": Vector3(0.0, 0.0, 24.0), "roll": -24.0},
	# ---- upgrades: the base model plus the "+" sticker
	"upgrade_wheelbarrow_tier_1":{"kind": "model", "px": 256, "build": "build_model", "model": "wheelbarrow", "color": WHEELBARROW_RED, "yaw": 125.0, "sticker": "plus"},
	# ---- the crew's kit at its tiers (256, 3D; icons:catalog): the stock icon's pose,
	# the model wearing its tier trim (props/yard_models.gd), its tier's chip bottom left
	"item_rake_used": {"kind": "model", "px": 256, "build": "build_kit", "model": "rake", "tier": 0, "yaw": 200.0, "tilt": Vector3(0.0, 0.0, -38.0)},
	"item_rake_mk2": {"kind": "model", "px": 256, "build": "build_kit", "model": "rake", "tier": 2, "yaw": 200.0, "tilt": Vector3(0.0, 0.0, -38.0)},
	"item_rake_mk3": {"kind": "model", "px": 256, "build": "build_kit", "model": "rake", "tier": 3, "yaw": 200.0, "tilt": Vector3(0.0, 0.0, -38.0)},
	"tool_leaf_blower_used": {"kind": "model", "px": 256, "build": "build_kit", "model": "leaf_blower", "tier": 0, "yaw": 120.0, "roll": -30.0},
	"tool_leaf_blower_mk2": {"kind": "model", "px": 256, "build": "build_kit", "model": "leaf_blower", "tier": 2, "yaw": 120.0, "roll": -30.0},
	"tool_leaf_blower_mk3": {"kind": "model", "px": 256, "build": "build_kit", "model": "leaf_blower", "tier": 3, "yaw": 120.0, "roll": -30.0},
	"tool_lawn_mower_used": {"kind": "model", "px": 256, "build": "build_kit", "model": "lawn_mower", "tier": 0, "yaw": 200.0},
	"tool_lawn_mower_mk2": {"kind": "model", "px": 256, "build": "build_kit", "model": "lawn_mower", "tier": 2, "yaw": 200.0},
	"tool_lawn_mower_mk3": {"kind": "model", "px": 256, "build": "build_kit", "model": "lawn_mower", "tier": 3, "yaw": 200.0},
	"tool_ladder_used": {"kind": "model", "px": 256, "build": "build_kit", "model": "ladder", "tier": 0, "yaw": 160.0, "tilt": Vector3(-72.0, 0.0, 0.0), "roll": 40.0},
	"tool_ladder_mk2": {"kind": "model", "px": 256, "build": "build_kit", "model": "ladder", "tier": 2, "yaw": 160.0, "tilt": Vector3(-72.0, 0.0, 0.0), "roll": 40.0},
	"tool_ladder_mk3": {"kind": "model", "px": 256, "build": "build_kit", "model": "ladder", "tier": 3, "yaw": 160.0, "tilt": Vector3(-72.0, 0.0, 0.0), "roll": 40.0},
	"tool_hose_used": {"kind": "model", "px": 256, "build": "build_kit", "model": "hose", "tier": 0, "yaw": 105.0},
	"tool_hose_mk2": {"kind": "model", "px": 256, "build": "build_kit", "model": "hose", "tier": 2, "yaw": 105.0},
	"tool_hose_mk3": {"kind": "model", "px": 256, "build": "build_kit", "model": "hose", "tier": 3, "yaw": 105.0},
	"tool_hedge_trimmer_used": {"kind": "model", "px": 256, "build": "build_kit", "model": "hedge_trimmer", "tier": 0, "yaw": 150.0, "tilt": Vector3(25.0, 0.0, 60.0), "roll": 30.0},
	"tool_hedge_trimmer_mk2": {"kind": "model", "px": 256, "build": "build_kit", "model": "hedge_trimmer", "tier": 2, "yaw": 150.0, "tilt": Vector3(25.0, 0.0, 60.0), "roll": 30.0},
	"tool_hedge_trimmer_mk3": {"kind": "model", "px": 256, "build": "build_kit", "model": "hedge_trimmer", "tier": 3, "yaw": 150.0, "tilt": Vector3(25.0, 0.0, 60.0), "roll": 30.0},
	"tool_pressure_washer_used": {"kind": "model", "px": 256, "build": "build_kit", "model": "pressure_washer", "tier": 0, "yaw": 200.0},
	"tool_pressure_washer_mk2": {"kind": "model", "px": 256, "build": "build_kit", "model": "pressure_washer", "tier": 2, "yaw": 200.0},
	"tool_pressure_washer_mk3": {"kind": "model", "px": 256, "build": "build_kit", "model": "pressure_washer", "tier": 3, "yaw": 200.0},
	"tool_paint_roller_used": {"kind": "model", "px": 256, "build": "build_kit", "model": "paint_roller", "tier": 0, "yaw": 120.0, "tilt": Vector3(-35.0, 0.0, 0.0), "roll": -15.0},
	"tool_paint_roller_mk2": {"kind": "model", "px": 256, "build": "build_kit", "model": "paint_roller", "tier": 2, "yaw": 120.0, "tilt": Vector3(-35.0, 0.0, 0.0), "roll": -15.0},
	"tool_paint_roller_mk3": {"kind": "model", "px": 256, "build": "build_kit", "model": "paint_roller", "tier": 3, "yaw": 120.0, "tilt": Vector3(-35.0, 0.0, 0.0), "roll": -15.0},
	# ---- the tier chips on their own (128, flat)
	"tier_used": {"kind": "flat", "px": 128, "draw": "draw_tier_badge", "tier": 0},
	"tier_2": {"kind": "flat", "px": 128, "draw": "draw_tier_badge", "tier": 2},
	"tier_3": {"kind": "flat", "px": 128, "draw": "draw_tier_badge", "tier": 3},
	# ---- supplies (256, 3D; icons:catalog): the shelf's own boxes, can and sacks
	# (props/shop_models.gd), each with a chip saying what it's for
	"supply_lawn_bags": {"kind": "model", "px": 256, "build": "build_shop_model", "model": "bag_roll", "yaw": 200.0},
	"supply_big_bags": {"kind": "model", "px": 256, "build": "build_shop_model", "model": "bag_roll_big", "yaw": 200.0, "label_chip": "XL", "chip_color": Color(0.95, 0.5, 0.15)},
	"supply_gas": {"kind": "model", "px": 256, "build": "build_shop_model", "model": "gas_can", "yaw": 125.0, "label_chip": "GAS", "chip_color": Color(0.98, 0.82, 0.2)},
	"supply_fertilizer": {"kind": "model", "px": 256, "build": "build_shop_model", "model": "fertilizer_bag", "yaw": 200.0, "glyph_chip": "flower"},
	"supply_grass_seed": {"kind": "model", "px": 256, "build": "build_shop_model", "model": "grass_seed", "yaw": 200.0, "glyph_chip": "sprout"},
	"supply_rock_salt": {"kind": "model", "px": 256, "build": "build_shop_model", "model": "rock_salt", "yaw": 200.0, "glyph_chip": "snowflake"},
	# ---- Rusty's junk (256, 3D; icons:catalog): the yard's own junk models
	"junk_old_tv": {"kind": "model", "px": 256, "build": "build_junk", "junk": "old_tv", "yaw": 200.0},
	"junk_tire": {"kind": "model", "px": 256, "build": "build_junk", "junk": "tire", "yaw": 200.0, "tilt": Vector3(55.0, 0.0, 0.0)},
	"junk_grill": {"kind": "model", "px": 256, "build": "build_junk", "junk": "grill", "yaw": 200.0},
	"junk_toilet": {"kind": "model", "px": 256, "build": "build_junk", "junk": "toilet", "yaw": 210.0},
	"junk_bike": {"kind": "model", "px": 256, "build": "build_junk", "junk": "bike", "yaw": 110.0},
	"junk_flamingo": {"kind": "model", "px": 256, "build": "build_junk", "junk": "flamingo", "yaw": 120.0},
	"junk_mannequin": {"kind": "model", "px": 256, "build": "build_junk", "junk": "mannequin", "yaw": 200.0, "tilt": Vector3(0.0, 0.0, -30.0)},
	"junk_boombox": {"kind": "model", "px": 256, "build": "build_junk", "junk": "boombox", "yaw": 200.0},
	"junk_flamingo_vintage": {"kind": "model", "px": 256, "build": "build_junk", "junk": "flamingo", "yaw": 120.0, "sparkle": true},
	# ---- Chefty's paint jobs (256, 3D; icons:catalog): Chefty in the color, logo and
	# all (DEC-006), and its can of paint at the front wheel
	"paint_classic": {"kind": "model", "px": 256, "build": "build_paint", "paint": "paint_classic", "yaw": 145.0},
	"paint_mint": {"kind": "model", "px": 256, "build": "build_paint", "paint": "paint_mint", "yaw": 145.0},
	"paint_sunset": {"kind": "model", "px": 256, "build": "build_paint", "paint": "paint_sunset", "yaw": 145.0},
	"paint_pink": {"kind": "model", "px": 256, "build": "build_paint", "paint": "paint_pink", "yaw": 145.0},
	"paint_black": {"kind": "model", "px": 256, "build": "build_paint", "paint": "paint_black", "yaw": 145.0},
	"paint_gold": {"kind": "model", "px": 256, "build": "build_paint", "paint": "paint_gold", "yaw": 145.0, "sparkle": true},
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
	# ---- stats (128, flat)
	"cash": {"kind": "flat", "px": 128, "draw": "draw_cash"},
	"star": {"kind": "flat", "px": 128, "draw": "draw_star", "color": GOLD},
	"star_empty": {"kind": "flat", "px": 128, "draw": "draw_star", "color": EMPTY_GREY},
	"xp": {"kind": "flat", "px": 128, "draw": "draw_xp"},
	"heat": {"kind": "flat", "px": 128, "draw": "draw_heat"},
	"clock": {"kind": "flat", "px": 128, "draw": "draw_clock"},
	"day": {"kind": "flat", "px": 128, "draw": "draw_sun"},
	"night": {"kind": "flat", "px": 128, "draw": "draw_night"},
	"cleanup": {"kind": "flat", "px": 128, "draw": "draw_cleanup"},
	"heart": {"kind": "flat", "px": 128, "draw": "draw_heart", "color": HEART_RED},
	"heart_empty": {"kind": "flat", "px": 128, "draw": "draw_heart", "color": EMPTY_GREY},
	"lock": {"kind": "flat", "px": 128, "draw": "draw_lock"},
	"check": {"kind": "flat", "px": 128, "draw": "draw_check"},
	"close": {"kind": "flat", "px": 128, "draw": "draw_close"},
	"warning": {"kind": "flat", "px": 128, "draw": "draw_warning"},
	"bill": {"kind": "flat", "px": 128, "draw": "draw_bill"},
	"water": {"kind": "flat", "px": 128, "draw": "draw_water"},
	"bonus": {"kind": "flat", "px": 128, "draw": "draw_bonus"},
	"medical": {"kind": "flat", "px": 128, "draw": "draw_medical"},
	"split": {"kind": "flat", "px": 128, "draw": "draw_split"},
	"unread": {"kind": "flat", "px": 128, "draw": "draw_unread"},
	"voice": {"kind": "flat", "px": 128, "draw": "draw_voice"},
	"hidden": {"kind": "flat", "px": 128, "draw": "draw_hidden"},
	"phone": {"kind": "flat", "px": 128, "draw": "draw_phone"},
	"perk": {"kind": "flat", "px": 128, "draw": "draw_perk"},
	# ---- phone apps (128): rounded tiles, a white pictogram
	"app_texts": {"kind": "tile", "px": 128, "draw": "draw_app_texts", "color": Color(0.27, 0.7, 0.36)},
	"app_clients": {"kind": "tile", "px": 128, "draw": "draw_app_clients", "color": Color(0.88, 0.42, 0.55)},
	"app_map": {"kind": "tile", "px": 128, "draw": "draw_app_map", "color": Color(0.15, 0.6, 0.62)},
	"app_crew": {"kind": "tile", "px": 128, "draw": "draw_app_crew", "color": Color(0.98, 0.64, 0.12)},
	"app_deliveries": {"kind": "tile", "px": 128, "draw": "draw_app_deliveries", "color": KRAFT},
	"app_closet": {"kind": "tile", "px": 128, "draw": "draw_app_closet", "color": Color(0.88, 0.7, 0.2)},
	"app_hires": {"kind": "tile", "px": 128, "draw": "draw_app_hires", "color": Color(0.55, 0.36, 0.78)},
	"app_shop": {"kind": "tile", "px": 128, "draw": "draw_app_shop", "color": ORANGE},
	"app_properties": {"kind": "tile", "px": 128, "draw": "draw_app_properties", "color": Color(0.3, 0.52, 0.86)},
	# ---- moods (128): five faces
	"mood_thrilled": {"kind": "flat", "px": 128, "draw": "draw_mood_thrilled"},
	"mood_happy": {"kind": "flat", "px": 128, "draw": "draw_mood_happy"},
	"mood_fine": {"kind": "flat", "px": 128, "draw": "draw_mood_fine"},
	"mood_slow": {"kind": "flat", "px": 128, "draw": "draw_mood_slow"},
	"mood_messy": {"kind": "flat", "px": 128, "draw": "draw_mood_messy"},
	# ---- seasons (128)
	"season_autumn": {"kind": "flat", "px": 128, "draw": "draw_season_autumn"},
	"season_winter": {"kind": "flat", "px": 128, "draw": "draw_season_winter"},
	"season_spring": {"kind": "flat", "px": 128, "draw": "draw_season_spring"},
	"season_summer": {"kind": "flat", "px": 128, "draw": "draw_sun", "shades": true},
	# ---- neighborhood pins (128): a map pin in the hood's color, a glyph in its eye
	"hood_maple_row": {"kind": "flat", "px": 128, "draw": "draw_hood_maple_row", "color": Color(0.86, 0.3, 0.17)},
	"hood_dandelion_acres": {"kind": "flat", "px": 128, "draw": "draw_hood_dandelion_acres", "color": Color(0.96, 0.76, 0.18)},
	"hood_birchwood_commons": {"kind": "flat", "px": 128, "draw": "draw_hood_birchwood_commons", "color": Color(0.42, 0.62, 0.44)},
	"hood_oak_hollow": {"kind": "flat", "px": 128, "draw": "draw_hood_oak_hollow", "color": Color(0.55, 0.36, 0.2)},
	"hood_lakeside": {"kind": "flat", "px": 128, "draw": "draw_hood_lakeside", "color": Color(0.24, 0.54, 0.88)},
	"hood_mansion_hill": {"kind": "flat", "px": 128, "draw": "draw_hood_mansion_hill", "color": Color(0.55, 0.33, 0.72)},
	# ---- brands (128)
	"brand_homie_depot": {"kind": "flat", "px": 128, "draw": "draw_brand_homie_depot"},
	"brand_chefty": {"kind": "flat", "px": 128, "draw": "draw_brand_chefty"},
	"brand_turfmasters": {"kind": "flat", "px": 128, "draw": "draw_brand_turfmasters"},
	"brand_rustys": {"kind": "flat", "px": 128, "draw": "draw_brand_rustys"},
	"brand_lunch_money": {"kind": "flat", "px": 128, "draw": "draw_brand_lunch_money"},
	"brand_snak_o_matic": {"kind": "flat", "px": 128, "draw": "draw_brand_snak_o_matic"},
	# ---- snacks (128, flat; shops chunk 6): the shop cards' pictures (snack_<item>)
	# and the HUD's buff icons (buff_<id>, ui/buff_hud.gd): what you ate, and the
	# crash's empty can.
	"snack_hot_dog": {"kind": "flat", "px": 128, "draw": "draw_hot_dog"},
	"snack_turbo_juice": {"kind": "flat", "px": 128, "draw": "draw_turbo_can"},
	"snack_coffee": {"kind": "flat", "px": 128, "draw": "draw_coffee_cup"},
	"snack_vend_sandwich": {"kind": "flat", "px": 128, "draw": "draw_sandwich"},
	"snack_vend_turbo": {"kind": "flat", "px": 128, "draw": "draw_turbo_can", "warm": true},
	"buff_full": {"kind": "flat", "px": 128, "draw": "draw_hot_dog"},
	"buff_turbo": {"kind": "flat", "px": 128, "draw": "draw_turbo_can", "zap": true},
	"buff_crash": {"kind": "flat", "px": 128, "draw": "draw_crash"},
	"buff_coffee": {"kind": "flat", "px": 128, "draw": "draw_coffee_cup"},
	"buff_queasy": {"kind": "flat", "px": 128, "draw": "draw_sandwich", "queasy": true},
	# ---- workwear and Chefty's paint (shops chunk 7): the shop window's cards and
	# the phone's Closet; "shirt" and "paint_swatch" are white, tinted by the caller
	"hat_hd_cap": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "hat_hd_cap", "yaw": 200.0},
	"hat_beanie": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "hat_beanie", "yaw": 200.0},
	"hat_bucket": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "hat_bucket", "yaw": 200.0},
	"hat_hard": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "hat_hard", "yaw": 200.0},
	"hat_cowboy": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "hat_cowboy", "yaw": 200.0},
	"hat_chef": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "hat_chef", "yaw": 200.0},
	"hat_crown": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "hat_crown", "yaw": 200.0},
	"hat_cone": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "hat_cone", "yaw": 200.0},
	"hat_propeller": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "hat_propeller", "yaw": 200.0},
	"hat_viking": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "hat_viking", "yaw": 200.0},
	"hat_trucker": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "hat_trucker", "yaw": 200.0},
	"shirt": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "shirt", "yaw": 180.0, "tilt": Vector3(-50.0, 0.0, 0.0)},
	"paint_swatch": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "paint_swatch", "yaw": 200.0},
	"decal_stripes": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "decal_stripes", "yaw": 180.0},
	"decal_googly": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "decal_googly", "yaw": 180.0},
	"decal_flames": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "decal_flames", "yaw": 180.0},
	"decal_leaves": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "decal_leaves", "yaw": 180.0},
	"decal_rust": {"kind": "model", "px": 256, "build": "build_cosmetic", "cosmetic": "decal_rust", "yaw": 180.0},

	# ---- Chefty's gear and Marty's Body Shop (128, flat; driving C3): the truck tab's
	# cards (gear_<catalog id>, and service_repair for the body shop).
	"gear_chefty_net": {"kind": "flat", "px": 128, "draw": "draw_chefty_net"},
	"service_repair": {"kind": "flat", "px": 128, "draw": "draw_body_repair"},
	# ---- keycaps (64 tall; "wide" ones 128 wide) and mouse glyphs: every key a
	# player can rebind to (critic C5)
	"key_a": {"kind": "key", "px": 64, "draw": "draw_key", "label": "A"},
	"key_b": {"kind": "key", "px": 64, "draw": "draw_key", "label": "B"},
	"key_c": {"kind": "key", "px": 64, "draw": "draw_key", "label": "C"},
	"key_d": {"kind": "key", "px": 64, "draw": "draw_key", "label": "D"},
	"key_e": {"kind": "key", "px": 64, "draw": "draw_key", "label": "E"},
	"key_f": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F"},
	"key_g": {"kind": "key", "px": 64, "draw": "draw_key", "label": "G"},
	"key_h": {"kind": "key", "px": 64, "draw": "draw_key", "label": "H"},
	"key_i": {"kind": "key", "px": 64, "draw": "draw_key", "label": "I"},
	"key_j": {"kind": "key", "px": 64, "draw": "draw_key", "label": "J"},
	"key_k": {"kind": "key", "px": 64, "draw": "draw_key", "label": "K"},
	"key_l": {"kind": "key", "px": 64, "draw": "draw_key", "label": "L"},
	"key_m": {"kind": "key", "px": 64, "draw": "draw_key", "label": "M"},
	"key_n": {"kind": "key", "px": 64, "draw": "draw_key", "label": "N"},
	"key_o": {"kind": "key", "px": 64, "draw": "draw_key", "label": "O"},
	"key_p": {"kind": "key", "px": 64, "draw": "draw_key", "label": "P"},
	"key_q": {"kind": "key", "px": 64, "draw": "draw_key", "label": "Q"},
	"key_r": {"kind": "key", "px": 64, "draw": "draw_key", "label": "R"},
	"key_s": {"kind": "key", "px": 64, "draw": "draw_key", "label": "S"},
	"key_t": {"kind": "key", "px": 64, "draw": "draw_key", "label": "T"},
	"key_u": {"kind": "key", "px": 64, "draw": "draw_key", "label": "U"},
	"key_v": {"kind": "key", "px": 64, "draw": "draw_key", "label": "V"},
	"key_w": {"kind": "key", "px": 64, "draw": "draw_key", "label": "W"},
	"key_x": {"kind": "key", "px": 64, "draw": "draw_key", "label": "X"},
	"key_y": {"kind": "key", "px": 64, "draw": "draw_key", "label": "Y"},
	"key_z": {"kind": "key", "px": 64, "draw": "draw_key", "label": "Z"},
	"key_0": {"kind": "key", "px": 64, "draw": "draw_key", "label": "0"},
	"key_1": {"kind": "key", "px": 64, "draw": "draw_key", "label": "1"},
	"key_2": {"kind": "key", "px": 64, "draw": "draw_key", "label": "2"},
	"key_3": {"kind": "key", "px": 64, "draw": "draw_key", "label": "3"},
	"key_4": {"kind": "key", "px": 64, "draw": "draw_key", "label": "4"},
	"key_5": {"kind": "key", "px": 64, "draw": "draw_key", "label": "5"},
	"key_6": {"kind": "key", "px": 64, "draw": "draw_key", "label": "6"},
	"key_7": {"kind": "key", "px": 64, "draw": "draw_key", "label": "7"},
	"key_8": {"kind": "key", "px": 64, "draw": "draw_key", "label": "8"},
	"key_9": {"kind": "key", "px": 64, "draw": "draw_key", "label": "9"},
	"key_f1": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F1"},
	"key_f2": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F2"},
	"key_f3": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F3"},
	"key_f4": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F4"},
	"key_f5": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F5"},
	"key_f6": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F6"},
	"key_f7": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F7"},
	"key_f8": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F8"},
	"key_f9": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F9"},
	"key_f10": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F10"},
	"key_f11": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F11"},
	"key_f12": {"kind": "key", "px": 64, "draw": "draw_key", "label": "F12"},
	"key_tab": {"kind": "key", "px": 64, "draw": "draw_key", "label": "Tab", "wide": true},
	"key_esc": {"kind": "key", "px": 64, "draw": "draw_key", "label": "Esc", "wide": true},
	"key_space": {"kind": "key", "px": 64, "draw": "draw_key", "label": "Space", "wide": true},
	"key_shift": {"kind": "key", "px": 64, "draw": "draw_key", "label": "Shift", "wide": true},
	"key_ctrl": {"kind": "key", "px": 64, "draw": "draw_key", "label": "Ctrl", "wide": true},
	"key_alt": {"kind": "key", "px": 64, "draw": "draw_key", "label": "Alt", "wide": true},
	"key_enter": {"kind": "key", "px": 64, "draw": "draw_key", "label": "Enter", "wide": true},
	"key_backspace": {"kind": "key", "px": 64, "draw": "draw_key", "glyph": "backspace", "wide": true},
	"key_up": {"kind": "key", "px": 64, "draw": "draw_key", "glyph": "up"},
	"key_down": {"kind": "key", "px": 64, "draw": "draw_key", "glyph": "down"},
	"key_left": {"kind": "key", "px": 64, "draw": "draw_key", "glyph": "left"},
	"key_right": {"kind": "key", "px": 64, "draw": "draw_key", "glyph": "right"},
	"mouse_left": {"kind": "key", "px": 64, "draw": "draw_mouse", "mouse": "left"},
	"mouse_right": {"kind": "key", "px": 64, "draw": "draw_mouse", "mouse": "right"},
	"mouse_middle": {"kind": "key", "px": 64, "draw": "draw_mouse", "mouse": "middle"},
	"mouse_4": {"kind": "key", "px": 64, "draw": "draw_mouse", "mouse": "4"},
	"mouse_5": {"kind": "key", "px": 64, "draw": "draw_mouse", "mouse": "5"},
	"wheel_up": {"kind": "key", "px": 64, "draw": "draw_mouse", "mouse": "wheel_up"},
	"wheel_down": {"kind": "key", "px": 64, "draw": "draw_mouse", "mouse": "wheel_down"},
	# ---- the window and app icon (256): the stuffed leaf bag with the rake
	# leaning on it, on a tile that fades orange to red. A badge, so the 3D pair
	# sits on the tile with its own ink ring like the task vignettes.
	"app_icon": {"kind": "badge", "px": 256, "draw": "draw_app_icon_tile", "build": "build_app_icon", "yaw": 200.0, "emblem_rect": Rect2(0.1, 0.07, 0.8, 0.84)},
}


## Supersampling: 3D and badge icons render at 2x, flat ones (chunk B) at 4x.
static func supersample(recipe: Dictionary) -> int:
	return 2 if str(recipe.get("kind", "")) in ["model", "badge"] else 4


## The 2D layer under the 3D render ("" for none) and over it. A recipe's own
## "draw" wins, so a badge can sit on any flat shape (the app icon's tile).
static func base_painter(recipe: Dictionary) -> String:
	if recipe.has("draw"):
		return str(recipe["draw"])
	match str(recipe.get("kind", "")):
		"badge":
			return "draw_disc" if str(recipe.get("shape", "disc")) == "disc" else "draw_shield"
		"flat", "tile", "key":
			return str(recipe.get("draw", ""))
	return ""


static func top_painter(recipe: Dictionary) -> String:
	if str(recipe.get("sticker", "")) == "plus":
		return "draw_plus_sticker"
	# A model's chips (icons:catalog): a kit tier, a label, a glyph, a sparkle.
	if str(recipe.get("kind", "")) == "model":
		for key: String in ["tier", "label_chip", "glyph_chip", "sparkle"]:
			if recipe.has(key):
				return "draw_chips"
	return ""


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
## Workwear and Chefty's paint (shops chunk 7, props/cosmetic_models.gd): a hat
## on its own (player/hats.gd, its propeller too), a folded white shirt and a
## white-label paint can (the shop window tints both), a decal's sample card.
static func build_cosmetic(root: Node3D, recipe: Dictionary) -> void:
	var hats := preload("res://player/hats.gd")
	var models := preload("res://props/cosmetic_models.gd")
	var what := str(recipe.get("cosmetic", ""))
	var mesh: ArrayMesh = null
	if what.begins_with("hat_"):
		var hat: Dictionary = hats.build(what.trim_prefix("hat_"), Color(0.3, 0.22, 0.16))
		var parts: Array = [[hat["mesh"], Transform3D.IDENTITY]]
		if hat["spin"] != null:
			parts.append([hat["spin"], Transform3D(Basis(Vector3.UP, 0.6), hat["spin_at"])])
		mesh = hats.merged(parts)
	elif what == "shirt":
		mesh = models.folded_shirt(WHITE, false)
	elif what == "paint_swatch":
		mesh = models.paint_can(WHITE)
	else:
		mesh = models.decal_card(what)
	if mesh != null:
		root.add_child(_Stylized.instance(mesh, MODEL_LOOK))


static func build_chefty(root: Node3D, _recipe: Dictionary) -> void:
	_Vehicles.build_truck(root, CHEFTY_RED)


## The NICE BOYS Courtesy Shuttle in its own cream paint and lavender band.
static func build_van(root: Node3D, _recipe: Dictionary) -> void:
	_Vehicles.build_van(root, _Vehicles.VAN_PAINT)


## A kit thing at its tier, as the rack and your hands show it (props/yard_models.gd
## tier trim: duct tape and rust, chrome stripes, black and gold with flames).
static func build_kit(root: Node3D, recipe: Dictionary) -> void:
	root.add_child(_YardModels.node(str(recipe.get("model", "")), Color.WHITE, Vector3.ONE, MODEL_LOOK, int(recipe.get("tier", 1))))


## One of the shops' models (props/shop_models.gd): a box of bags, the gas can, a sack.
static func build_shop_model(root: Node3D, recipe: Dictionary) -> void:
	_add_shop_node(root, _ShopModels.node(str(recipe.get("model", ""))))


## A piece of junk off a yard, the model Rusty weighs (props/shop_models.gd junk).
static func build_junk(root: Node3D, recipe: Dictionary) -> void:
	_add_shop_node(root, _ShopModels.junk(str(recipe.get("junk", ""))))


## A shop model's mesh, lit like every other icon's model.
static func _add_shop_node(root: Node3D, node: MeshInstance3D) -> void:
	var mesh := node.mesh
	node.free()
	root.add_child(_Stylized.instance(mesh, MODEL_LOOK))


## A paint job: Chefty in the color (logo and all, DEC-006), and the can it came
## in by the front wheel, toy-sized up so it reads next to a truck.
static func build_paint(root: Node3D, recipe: Dictionary) -> void:
	var color: Color = Constants.CHEFTY_PAINTS.get(str(recipe.get("paint", "")), CHEFTY_RED)
	_Vehicles.build_truck(root, {"color": color})
	var can: ArrayMesh = preload("res://props/cosmetic_models.gd").paint_can(color)
	if can != null:
		_add_mesh(root, can, PAINT_CAN_AT, Basis(Vector3.UP, 0.5), PAINT_CAN_SCALE)


## Marty's nephew's board (props/gear_models.gd), as you ride it.
static func build_skateboard(root: Node3D, _recipe: Dictionary) -> void:
	root.add_child(preload("res://props/gear_models.gd").build_skateboard())


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


## A model's chips (icons:catalog), over the 3D render: "tier" a kit tier's chip,
## "label_chip" a word on a colored label ("chip_color"), "glyph_chip" a round
## paper chip with a little picture, "sparkle" three gold twinkles top right.
static func draw_chips(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	if recipe.has("tier"):
		_tier_chip(canvas, size, CHIP_RECT, int(recipe["tier"]))
	if recipe.has("label_chip"):
		_label_chip(canvas, size, CHIP_RECT, str(recipe["label_chip"]), recipe.get("chip_color", GOLD))
	if recipe.has("glyph_chip"):
		_glyph_chip(canvas, size, GLYPH_CHIP_AT, GLYPH_CHIP_RADIUS, str(recipe["glyph_chip"]))
	if bool(recipe.get("sparkle", false)):
		_sparkle(canvas, size, Vector2(0.8, 0.17), 0.09, GOLD.lightened(0.25))
		_sparkle(canvas, size, Vector2(0.91, 0.31), 0.05, GOLD.lightened(0.4))
		_sparkle(canvas, size, Vector2(0.67, 0.09), 0.045, GOLD.lightened(0.4))


## A tier chip alone, big, for tier_used / tier_2 / tier_3.
static func draw_tier_badge(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	_tier_chip(canvas, size, Rect2(0.07, 0.25, 0.86, 0.5), int(recipe.get("tier", 1)))


## A kit tier's chip in rect (units), dressed like the tier's trim on the model
## (props/yard_models.gd): a used thing's strip of duct tape with USED on it and
## a rust spot, Mk II's chrome plate with II, Mk III's black plate with a gold rim,
## a lick of flame and a gold III. Stock has none.
static func _tier_chip(canvas: CanvasItem, size: float, rect: Rect2, tier: int) -> void:
	var center := rect.get_center()
	var em := rect.size.y * 0.7
	match tier:
		0:
			# Torn ends, a little crooked, the way it got slapped on.
			var tape := PackedVector2Array()
			var teeth := 4
			for step: int in teeth + 1:
				var t := float(step) / float(teeth)
				tape.append(Vector2(rect.position.x + (0.025 if step % 2 == 0 else 0.0) * rect.size.y * 4.0, lerpf(rect.position.y, rect.end.y, t)))
			for step: int in teeth + 1:
				var t := float(step) / float(teeth)
				tape.append(Vector2(rect.end.x - (0.025 if step % 2 == 1 else 0.0) * rect.size.y * 4.0, lerpf(rect.end.y, rect.position.y, t)))
			var crooked := PackedVector2Array()
			for point: Vector2 in tape:
				crooked.append(center + (point - center).rotated(-0.09))
			var pixels := _xf(crooked, size)
			canvas.draw_colored_polygon(pixels, TAPE_GREY)
			canvas.draw_polyline(_closed(pixels), INK, FLAT_INK * size, true)
			_disc(canvas, size, center + Vector2(rect.size.x * 0.36, rect.size.y * 0.22), rect.size.y * 0.12, CHIP_RUST)
			_text(canvas, size, center, "USED", em * 0.78, INK, rect.size.x * 0.78)
		2:
			var plate := _xf(_rrect_pts(rect, rect.size.y * 0.3, 6), size)
			_fill_gradient(canvas, plate, CHROME_LIGHT, CHROME_DARK)
			canvas.draw_polyline(_closed(plate), INK, FLAT_INK * size, true)
			# The glint across the chrome.
			_line(canvas, size, rect.position + Vector2(rect.size.x * 0.12, rect.size.y * 0.3), rect.position + Vector2(rect.size.x * 0.3, rect.size.y * 0.3), rect.size.y * 0.1, WHITE)
			_text(canvas, size, center, "II", em, INK, rect.size.x * 0.7)
		3:
			var plate := _xf(_rrect_pts(rect, rect.size.y * 0.3, 6), size)
			_inked(canvas, plate, MK3_BLACK, size)
			canvas.draw_polyline(_closed(_xf(_rrect_pts(rect.grow(-rect.size.y * 0.11), rect.size.y * 0.2, 6), size)), GOLD, rect.size.y * 0.07 * size, true)
			# Two tongues of flame licking in from the left end.
			for tongue: Vector2 in [Vector2(0.26, -0.12), Vector2(0.18, 0.14)]:
				var base := Vector2(rect.position.x + rect.size.y * 0.2, center.y + tongue.y * rect.size.y)
				_fill(canvas, _xf(_ellipse_pts(Vector2.ZERO, rect.size.y * tongue.x, rect.size.y * 0.075, 16), size, base + Vector2(rect.size.y * tongue.x * 0.6, 0.0)), FLAME_RED)
				_fill(canvas, _xf(_ellipse_pts(Vector2.ZERO, rect.size.y * tongue.x * 0.5, rect.size.y * 0.035, 12), size, base + Vector2(rect.size.y * tongue.x * 0.45, 0.0)), FLAME_YELLOW)
			_text(canvas, size, center + Vector2(rect.size.x * 0.13, 0.0), "III", em, GOLD.lightened(0.15), rect.size.x * 0.55, 0.12)


## A word on a colored label (the gas can's GAS), in rect (units).
static func _label_chip(canvas: CanvasItem, size: float, rect: Rect2, word: String, color: Color) -> void:
	var plate := _xf(_rrect_pts(rect, rect.size.y * 0.25, 6), size)
	_fill_gradient(canvas, plate, color.lightened(0.18), color.darkened(0.08))
	canvas.draw_polyline(_closed(plate), INK, FLAT_INK * size, true)
	_text(canvas, size, rect.get_center(), word, rect.size.y * 0.66, INK, rect.size.x * 0.8)


## A round paper chip with a little picture: "flower" (fertilizer), "sprout"
## (grass seed, the spring icon), "snowflake" (rock salt, the winter icon).
static func _glyph_chip(canvas: CanvasItem, size: float, at: Vector2, radius: float, glyph: String) -> void:
	_disc(canvas, size, at, radius, INK)
	_disc(canvas, size, at, radius * 0.86, PAPER)
	# The glyph funcs draw a whole 0..1 icon: scale it into the chip.
	var scale := radius * 1.55
	canvas.draw_set_transform((at - Vector2(0.5, 0.5) * scale) * size, 0.0, Vector2.ONE * scale)
	match glyph:
		"snowflake":
			draw_season_winter(canvas, size, {})
		"sprout":
			draw_season_spring(canvas, size, {})
		"flower":
			_flower(canvas, size)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Five petals round a yellow middle, filling the unit square.
static func _flower(canvas: CanvasItem, size: float) -> void:
	_stroke(canvas, size, PackedVector2Array([Vector2(0.5, 0.55), Vector2(0.52, 0.92)]), 0.07, GREEN)
	for petal: int in 5:
		var angle := TAU * float(petal) / 5.0
		_inked(canvas, _xf(_ellipse_pts(Vector2(0.0, -0.2), 0.12, 0.19, 20), size, Vector2(0.5, 0.45), 1.0, angle), Color(0.98, 0.55, 0.68), size)
	_inked(canvas, _xf(_ellipse_pts(Vector2.ZERO, 0.12, 0.12, 20), size, Vector2(0.5, 0.45)), Color(1.0, 0.82, 0.25), size)


static func _quad(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out


# ---------------------------------------------------------------- the app icon

## The window icon's subject: the stuffed leaf bag, the rake leaning on it from
## behind, and a few leaves that got away.
static func build_app_icon(root: Node3D, _recipe: Dictionary) -> void:
	_add_model(root, "leaf_bag", Vector3.ZERO)
	# Local -X is screen right at this yaw, and the rake's top leans back over the bag.
	_add_model(root, "rake", Vector3(-0.42, 0.0, 0.26), Basis(Vector3.BACK, -0.6))
	var kit := _MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for index: int in 7:
		var at := Vector3(rng.randf_range(-0.5, 0.45), 0.02, rng.randf_range(-0.42, -0.12))
		kit.leaf_card(at, Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized(), rng.randf_range(0.07, 0.1), _YardModels.LEAVES[index % _YardModels.LEAVES.size()], 0.0, rng.randf() * TAU)
	_commit(root, kit)


## The app icon's tile: rounded, fading Homie orange at the top to brick red, with
## a few pale leaves blowing across it.
static func draw_app_icon_tile(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	_fill(canvas, _xf(_rrect_pts(Rect2(0.04, 0.04, 0.92, 0.92), 0.2, 10), size), Color(0.6, 0.15, 0.1))
	_fill_gradient(canvas, _xf(_rrect_pts(Rect2(0.04, 0.04, 0.92, 0.885), 0.2, 10), size), Color(1.0, 0.64, 0.22), Color(0.86, 0.24, 0.14))
	var pale := Color(1.0, 0.8, 0.5, 0.45)
	for leaf: Array in [[Vector2(0.18, 0.2), 0.08, -0.5], [Vector2(0.84, 0.18), 0.06, 0.6], [Vector2(0.15, 0.78), 0.06, 1.2], [Vector2(0.86, 0.8), 0.07, -0.3]]:
		_fill(canvas, _xf(_maple_pts(), size, leaf[0], leaf[1], leaf[2]), pale)


# ---------------------------------------------------------------- flat icons
#
# Draw funcs work in units of the canvas height: (0, 0) is the top left and
# (1, 1) the bottom right of a square icon, and a wide keycap runs to x = 2.
# Shapes stay inside about 0.06..0.92 so the outer outline and the drop shadow
# fit. Inner ink lines are FLAT_INK wide, a little heavier than the outer
# outline, so they still separate shapes at 20 px.

const FLAT_INK: float = 0.02
## Where a line of caps sits: its baseline is this many font sizes below the
## line's center (the fallback font's cap height is about 0.72 em).
const CAP_CENTER: float = 0.36
const RED_LEAF := Color(0.84, 0.26, 0.15)
const YELLOW_LEAF := Color(0.98, 0.78, 0.22)

static var _bold: Font


## The fallback font, emboldened: the one face every drawn label uses.
static func _font() -> Font:
	if _bold == null:
		var variation := FontVariation.new()
		variation.base_font = ThemeDB.fallback_font
		variation.variation_embolden = 1.0
		_bold = variation
	return _bold


## Unit points, moved to at, scaled and turned (radians), in canvas pixels.
## With size 1.0 it stays in units (for building a stroke path).
static func _xf(points: PackedVector2Array, size: float, at: Vector2 = Vector2.ZERO, scale: float = 1.0, angle: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in points:
		out.append((at + point.rotated(angle) * scale) * size)
	return out


static func _fill(canvas: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	canvas.draw_colored_polygon(points, color)
	canvas.draw_polyline(_closed(points), color, 1.0, true)


## A fill with an ink edge, for a shape that has to stand apart from what's under it.
static func _inked(canvas: CanvasItem, points: PackedVector2Array, color: Color, size: float, ink: Color = INK, width: float = FLAT_INK) -> void:
	canvas.draw_colored_polygon(points, color)
	canvas.draw_polyline(_closed(points), ink, width * size, true)


## A vertical gradient fill, top color at the shape's top.
static func _fill_gradient(canvas: CanvasItem, points: PackedVector2Array, top: Color, bottom: Color) -> void:
	var low := INF
	var high := -INF
	for point: Vector2 in points:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	var colors := PackedColorArray()
	for point: Vector2 in points:
		colors.append(top.lerp(bottom, (point.y - low) / maxf(1.0, high - low)))
	canvas.draw_polygon(points, colors)


static func _disc(canvas: CanvasItem, size: float, at: Vector2, radius: float, color: Color) -> void:
	canvas.draw_circle(at * size, radius * size, color, true, -1.0, true)


## A round-capped, round-jointed line through unit points.
static func _stroke(canvas: CanvasItem, size: float, points: PackedVector2Array, width: float, color: Color) -> void:
	var pixels := _xf(points, size)
	canvas.draw_polyline(pixels, color, width * size, true)
	for point: Vector2 in pixels:
		canvas.draw_circle(point, width * size * 0.5, color, true, -1.0, true)


static func _line(canvas: CanvasItem, size: float, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	_stroke(canvas, size, PackedVector2Array([from, to]), width, color)


## A round-capped arc (radians; y points down, so PI..TAU is the top half).
static func _arc(canvas: CanvasItem, size: float, center: Vector2, radius: float, from: float, to: float, width: float, color: Color) -> void:
	_stroke(canvas, size, _arc_pts(center, radius, from, to, 32), width, color)


## Text centered on at, em font sizes tall, squeezed to fit units wide when fit
## is set. outline (a share of the font size) draws a rim of outline_color first.
static func _text(canvas: CanvasItem, size: float, at: Vector2, text: String, em: float, color: Color, fit: float = 0.0, outline: float = 0.0, outline_color: Color = INK) -> void:
	var font := _font()
	var font_size := maxi(1, int(em * size))
	if fit > 0.0:
		var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if wide > fit * size:
			font_size = maxi(1, int(float(font_size) * fit * size / wide))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var base := Vector2(at.x * size - width * 0.5, at.y * size + float(font_size) * CAP_CENTER)
	if outline > 0.0:
		canvas.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(1, int(outline * float(font_size))), outline_color)
	canvas.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## A four-point twinkle.
static func _sparkle(canvas: CanvasItem, size: float, at: Vector2, radius: float, color: Color) -> void:
	_fill(canvas, _xf(_star_pts(4, radius, radius * 0.3), size, at), color)


# ---- shapes, in units around the origin unless they take a center

static func _arc_pts(center: Vector2, radius: float, from: float, to: float, steps: int = 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for step: int in steps + 1:
		out.append(center + Vector2.from_angle(lerpf(from, to, float(step) / float(steps))) * radius)
	return out


static func _ellipse_pts(center: Vector2, rx: float, ry: float, steps: int = 48) -> PackedVector2Array:
	var out := PackedVector2Array()
	for step: int in steps:
		var angle := TAU * float(step) / float(steps)
		out.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	return out


## The top half of an ellipse, flat side down on center.
static func _dome_pts(center: Vector2, rx: float, ry: float, steps: int = 32) -> PackedVector2Array:
	var out := PackedVector2Array()
	for step: int in steps + 1:
		var angle := PI + PI * float(step) / float(steps)
		out.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	return out


## The bottom half of an ellipse, flat side up on center.
static func _bowl_pts(center: Vector2, rx: float, ry: float, steps: int = 32) -> PackedVector2Array:
	var out := PackedVector2Array()
	for step: int in steps + 1:
		var angle := PI * float(step) / float(steps)
		out.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	return out


static func _rect_pts(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


static func _rrect_pts(rect: Rect2, radius: float, steps: int = 6) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.499)
	var out := PackedVector2Array()
	var corners: Array = [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	for corner: Array in corners:
		for step: int in steps + 1:
			out.append(corner[0] + Vector2.from_angle(corner[1] + PI * 0.5 * float(step) / float(steps)) * r)
	return out


static func _star_pts(points: int, outer: float, inner: float, turn: float = -PI * 0.5) -> PackedVector2Array:
	var out := PackedVector2Array()
	for index: int in points * 2:
		out.append(Vector2.from_angle(turn + PI * float(index) / float(points)) * (outer if index % 2 == 0 else inner))
	return out


## The classic heart curve, about 1.9 wide and 1.7 tall, its tip at (0, 0.88).
static func _heart_pts(steps: int = 72) -> PackedVector2Array:
	var out := PackedVector2Array()
	for step: int in steps:
		var t := TAU * float(step) / float(steps)
		var s := sin(t)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		out.append(Vector2(16.0 * s * s * s, -y) / 17.0 + Vector2(0.0, -0.12))
	return out


## A drop: a circle of radius 0.62 on the origin that comes to a point at (0, -1).
## Turned by PI it is a map pin.
static func _drop_pts(steps: int = 40) -> PackedVector2Array:
	var radius := 0.62
	var half := PI * 0.5 - asin(radius)
	var out := PackedVector2Array([Vector2(0.0, -1.0)])
	var from := -PI * 0.5 + half
	var to := -PI * 0.5 - half + TAU
	for step: int in steps + 1:
		out.append(Vector2.from_angle(lerpf(from, to, float(step) / float(steps))) * radius)
	return out


## A plain leaf pointing up, 2 long, its stem end at (0, 1).
static func _leaf_pts(steps: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for step: int in steps + 1:
		var t := float(step) / float(steps)
		out.append(Vector2(sin(t * PI) * 0.46 * (1.0 - t * 0.3), -1.0 + 2.0 * t))
	for step: int in range(steps - 1, 0, -1):
		var t := float(step) / float(steps)
		out.append(Vector2(-sin(t * PI) * 0.46 * (1.0 - t * 0.3), -1.0 + 2.0 * t))
	return out


## The right half of the maple leaf, top tip to stem; mirrored for the left.
const MAPLE_HALF: Array[Vector2] = [
	Vector2(0.0, -1.0), Vector2(0.13, -0.62), Vector2(0.34, -0.76), Vector2(0.29, -0.36),
	Vector2(0.8, -0.6), Vector2(0.68, -0.32), Vector2(0.94, -0.2), Vector2(0.56, 0.06),
	Vector2(0.66, 0.34), Vector2(0.3, 0.25), Vector2(0.07, 0.5),
]


## The maple leaf, about 1.9 wide, its top tip at (0, -1) and stem end at (0, 0.5).
static func _maple_pts() -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in MAPLE_HALF:
		out.append(point)
	for index: int in range(MAPLE_HALF.size() - 1, 0, -1):
		out.append(Vector2(-MAPLE_HALF[index].x, MAPLE_HALF[index].y))
	return out


## The part of the big circle the small one doesn't cover: a crescent moon.
static func _crescent_pts(big_center: Vector2, big: float, cut_center: Vector2, cut: float, steps: int = 40) -> PackedVector2Array:
	var gap := big_center.distance_to(cut_center)
	var axis := (cut_center - big_center) / gap
	var along := (big * big - cut * cut + gap * gap) / (2.0 * gap)
	var high := sqrt(maxf(0.0, big * big - along * along))
	var across := Vector2(-axis.y, axis.x)
	var one := big_center + axis * along + across * high
	var two := big_center + axis * along - across * high
	var away := (-axis).angle()
	var out := _arc_through(big_center, big, (one - big_center).angle(), (two - big_center).angle(), away, steps)
	var inner := _arc_through(cut_center, cut, (two - cut_center).angle(), (one - cut_center).angle(), away, steps)
	for index: int in range(1, inner.size() - 1):
		out.append(inner[index])
	return out


## An arc from one angle to another, the way round that passes through via.
static func _arc_through(center: Vector2, radius: float, from: float, to: float, via: float, steps: int) -> PackedVector2Array:
	var sweep := wrapf(to - from, 0.0, TAU)
	if wrapf(via - from, 0.0, TAU) > sweep:
		sweep -= TAU
	return _arc_pts(center, radius, from, from + sweep, steps)


## Two overlapping shapes as one outline (the biggest piece of the merge).
static func _union(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var best := a
	var best_area := 0.0
	for piece: PackedVector2Array in Geometry2D.merge_polygons(a, b):
		var area := absf(_area(piece))
		if area > best_area:
			best = piece
			best_area = area
	return best


static func _area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index: int in points.size():
		var next := points[(index + 1) % points.size()]
		total += points[index].x * next.y - next.x * points[index].y
	return total * 0.5


## Shrinks or grows points toward center.
static func _scaled_about(points: PackedVector2Array, center: Vector2, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in points:
		out.append(center + (point - center) * scale)
	return out


# ---- reusable pieces

## The maple leaf with its stem and veins, scale units from tip to center.
static func _maple(canvas: CanvasItem, size: float, at: Vector2, scale: float, color: Color, angle: float = 0.0) -> void:
	var vein := color.darkened(0.32)
	_stroke(canvas, size, _xf(PackedVector2Array([Vector2(0.0, 0.3), Vector2(0.02, 0.96)]), 1.0, at, scale, angle), 0.13 * scale, vein)
	_fill(canvas, _xf(_maple_pts(), size, at, scale, angle), color)
	_fill(canvas, _xf(_scaled_about(_maple_pts(), Vector2(0.0, -0.1), 0.62), size, at + Vector2(-0.03, -0.03) * scale, scale, angle), color.lightened(0.1))
	for tip: Vector2 in [Vector2(0.0, -0.72), Vector2(0.62, -0.42), Vector2(-0.62, -0.42), Vector2(0.48, 0.14), Vector2(-0.48, 0.14)]:
		_stroke(canvas, size, _xf(PackedVector2Array([Vector2(0.0, 0.42), tip]), 1.0, at, scale, angle), 0.06 * scale, vein)


## A plain leaf with a midrib.
static func _leaf(canvas: CanvasItem, size: float, at: Vector2, scale: float, angle: float, color: Color, inked: bool = true) -> void:
	if inked:
		_inked(canvas, _xf(_leaf_pts(), size, at, scale, angle), color, size, INK, FLAT_INK * 0.7)
	else:
		_fill(canvas, _xf(_leaf_pts(), size, at, scale, angle), color)
	_stroke(canvas, size, _xf(PackedVector2Array([Vector2(0.0, 0.9), Vector2(0.0, -0.6)]), 1.0, at, scale, angle), 0.1 * scale, color.darkened(0.3))


## The flat app tile: a rounded square with a darker lip and a soft top-down sheen.
static func _tile(canvas: CanvasItem, size: float, color: Color) -> void:
	_fill(canvas, _xf(_rrect_pts(Rect2(0.06, 0.06, 0.88, 0.88), 0.19, 8), size), color.darkened(0.25))
	_fill_gradient(canvas, _xf(_rrect_pts(Rect2(0.06, 0.06, 0.88, 0.845), 0.19, 8), size), color.lightened(0.2), color)


## A neighborhood pin: a map pin in the hood's color with a round eye for its glyph,
## centered on (0.5, 0.4), 0.2 across.
static func _pin(canvas: CanvasItem, size: float, color: Color, eye: Color = PAPER) -> void:
	_fill(canvas, _xf(_drop_pts(), size, Vector2(0.5, 0.4), 0.52, PI), color.darkened(0.28))
	_fill(canvas, _xf(_drop_pts(), size, Vector2(0.5, 0.39), 0.45, PI), color)
	_disc(canvas, size, Vector2(0.44, 0.3), 0.1, color.lightened(0.15))
	_disc(canvas, size, Vector2(0.5, 0.4), 0.215, color.darkened(0.28))
	_disc(canvas, size, Vector2(0.5, 0.4), 0.195, eye)


## A mood face's disc.
static func _face(canvas: CanvasItem, size: float, color: Color = FACE_YELLOW) -> void:
	_disc(canvas, size, Vector2(0.5, 0.52), 0.42, color.darkened(0.24))
	_disc(canvas, size, Vector2(0.49, 0.505), 0.39, color)
	_fill(canvas, _xf(_ellipse_pts(Vector2.ZERO, 0.17, 0.1), size, Vector2(0.38, 0.3), 1.0, -0.5), color.lightened(0.18))


## A crew member from the chest up: shirt, head, hard hat.
static func _crew_head(canvas: CanvasItem, size: float, head: Vector2, radius: float, shirt: Color, hat: Color) -> void:
	_inked(canvas, _xf(_dome_pts(head + Vector2(0.0, radius * 2.35), radius * 1.5, radius * 1.15), size), shirt, size)
	_inked(canvas, _xf(_ellipse_pts(head, radius, radius), size), Color(0.96, 0.78, 0.6), size)
	for side: float in [-1.0, 1.0]:
		_disc(canvas, size, head + Vector2(side * 0.36, 0.22) * radius, 0.12 * radius, INK)
	_inked(canvas, _xf(_dome_pts(head + Vector2(0.0, -radius * 0.12), radius * 1.02, radius * 0.95), size), hat, size)
	_inked(canvas, _xf(_rrect_pts(Rect2(head.x - radius * 1.25, head.y - radius * 0.24, radius * 2.5, radius * 0.3), radius * 0.15), size), hat.darkened(0.12), size)


## A head-and-shoulders silhouette, ringed in ring so it cuts out of a crowd.
static func _person(canvas: CanvasItem, size: float, head: Vector2, radius: float, color: Color, ring: Color) -> void:
	# The shoulders' top tucks under the chin so the merge is one outline.
	var body := _union(_dome_pts(head + Vector2(0.0, radius * 2.45), radius * 1.65, radius * 1.6), _ellipse_pts(head, radius * 1.0, radius * 1.0))
	_inked(canvas, _xf(body, size), color, size, ring, 0.035)


# ---- stats

## A bundle of bills, a fat "$" on the front one.
static func draw_cash(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var bill := Color(0.52, 0.78, 0.42)
	var dark := Color(0.12, 0.4, 0.2)
	var shape := _rrect_pts(Rect2(-0.4, -0.21, 0.8, 0.42), 0.05)
	for back: int in [2, 1]:
		_inked(canvas, _xf(shape, size, Vector2(0.52 + 0.02 * float(back), 0.6 - 0.09 * float(back)), 1.0, -0.1 * float(back)), bill.darkened(0.1 * float(back)), size)
	var at := Vector2(0.48, 0.64)
	_inked(canvas, _xf(shape, size, at), bill, size)
	canvas.draw_polyline(_closed(_xf(_rrect_pts(Rect2(-0.33, -0.15, 0.66, 0.3), 0.03), size, at)), dark.lightened(0.25), size * 0.014, true)
	_fill(canvas, _xf(_ellipse_pts(Vector2.ZERO, 0.15, 0.13), size, at), bill.lightened(0.3))
	for corner: Vector2 in [Vector2(-0.27, -0.09), Vector2(0.27, -0.09), Vector2(-0.27, 0.09), Vector2(0.27, 0.09)]:
		_disc(canvas, size, at + corner, 0.025, dark.lightened(0.25))
	_text(canvas, size, at, "$", 0.34, dark)


## A five-point star; "color" makes the empty one grey.
static func draw_star(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe.get("color", GOLD)
	var at := Vector2(0.5, 0.53)
	_fill(canvas, _xf(_star_pts(5, 0.46, 0.22), size, at), color.darkened(0.3))
	_fill(canvas, _xf(_star_pts(5, 0.37, 0.18), size, at + Vector2(0.0, -0.01)), color)
	_fill(canvas, _xf(_star_pts(5, 0.15, 0.07), size, at + Vector2(-0.06, -0.08)), color.lightened(0.4))


## An orange burst that says XP.
static func draw_xp(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var at := Vector2(0.5, 0.5)
	_fill(canvas, _xf(_star_pts(12, 0.46, 0.36, 0.0), size, at), ORANGE.darkened(0.25))
	_fill(canvas, _xf(_star_pts(12, 0.4, 0.31, 0.0), size, at), ORANGE)
	_disc(canvas, size, at + Vector2(-0.05, -0.06), 0.2, ORANGE.lightened(0.1))
	_text(canvas, size, at, "XP", 0.36, WHITE, 0.62, 0.2)


## Heat: a red siren dome throwing light. Generic: no badge, insignia or lettering.
static func draw_heat(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var glow := Color(1.0, 0.8, 0.25)
	var center := Vector2(0.5, 0.67)
	for index: int in 5:
		var direction := Vector2.from_angle(-PI * 0.85 + PI * 0.7 * float(index) / 4.0)
		_line(canvas, size, center + direction * 0.37, center + direction * 0.47, 0.075, glow)
	_inked(canvas, _xf(_rrect_pts(Rect2(0.18, 0.66, 0.64, 0.18), 0.04), size), Color(0.36, 0.34, 0.38), size)
	_fill(canvas, _xf(_rrect_pts(Rect2(0.23, 0.69, 0.54, 0.04), 0.02), size), Color(0.55, 0.53, 0.58))
	_inked(canvas, _xf(_dome_pts(center, 0.27, 0.3), size), RED.lightened(0.08), size)
	_fill(canvas, _xf(_dome_pts(center, 0.14, 0.19), size), Color(1.0, 0.56, 0.42))
	_arc(canvas, size, center, 0.2, PI * 1.18, PI * 1.42, 0.04, Color(1.0, 0.95, 0.9))


## An alarm clock with two bells.
static func draw_clock(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var center := Vector2(0.5, 0.56)
	_line(canvas, size, Vector2(0.33, 0.8), Vector2(0.25, 0.9), 0.06, INK)
	_line(canvas, size, Vector2(0.67, 0.8), Vector2(0.75, 0.9), 0.06, INK)
	_arc(canvas, size, Vector2(0.5, 0.32), 0.2, PI * 1.25, PI * 1.75, 0.045, INK)
	for side: float in [-1.0, 1.0]:
		_inked(canvas, _xf(_dome_pts(Vector2.ZERO, 0.14, 0.13), size, Vector2(0.5 + side * 0.25, 0.27), 1.0, side * 0.6), GOLD, size)
	_disc(canvas, size, center, 0.35, INK)
	_disc(canvas, size, center, 0.325, RED)
	_disc(canvas, size, center, 0.25, PAPER)
	for tick: int in 12:
		var direction := Vector2.from_angle(TAU * float(tick) / 12.0)
		if tick % 3 == 0:
			_line(canvas, size, center + direction * 0.17, center + direction * 0.21, 0.035, INK)
		else:
			_disc(canvas, size, center + direction * 0.195, 0.014, INK)
	_line(canvas, size, center, center + Vector2(0.0, -0.15), 0.045, INK)
	_line(canvas, size, center, center + Vector2(0.11, 0.05), 0.045, INK)
	_disc(canvas, size, center, 0.035, RED)


## The sun (day). "shades": the summer sun, in sunglasses.
static func draw_sun(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var shades := bool(recipe.get("shades", false))
	var center := Vector2(0.5, 0.5)
	var ray := Color(1.0, 0.56, 0.12) if shades else Color(1.0, 0.68, 0.18)
	for index: int in 12:
		var angle := TAU * float(index) / 12.0 - PI * 0.5
		var reach := 0.46 if index % 2 == 0 else 0.39
		_fill(canvas, _xf(PackedVector2Array([Vector2.from_angle(angle) * reach, Vector2.from_angle(angle + 0.18) * 0.27, Vector2.from_angle(angle - 0.18) * 0.27]), size, center), ray)
	_disc(canvas, size, center, 0.3, ray.darkened(0.2))
	_disc(canvas, size, center, 0.27, Color(1.0, 0.84, 0.28))
	_disc(canvas, size, center + Vector2(-0.07, -0.08), 0.12, Color(1.0, 0.93, 0.6))
	if not shades:
		return
	for side: float in [-1.0, 1.0]:
		var lens := center + Vector2(side * 0.11, -0.03)
		_fill(canvas, _xf(_rrect_pts(Rect2(-0.09, -0.06, 0.18, 0.13), 0.05), size, lens), INK)
		_line(canvas, size, lens + Vector2(-0.05, -0.025), lens + Vector2(-0.015, -0.025), 0.022, Color(1.0, 1.0, 1.0, 0.85))
	_line(canvas, size, center + Vector2(-0.03, -0.05), center + Vector2(0.03, -0.05), 0.03, INK)
	_arc(canvas, size, center + Vector2(0.0, 0.0), 0.15, PI * 0.25, PI * 0.75, 0.035, INK)


## Night: a crescent moon, snoring.
static func draw_night(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var moon := Color(1.0, 0.88, 0.5)
	_fill(canvas, _xf(_crescent_pts(Vector2(0.42, 0.54), 0.36, Vector2(0.6, 0.4), 0.3), size), moon)
	_disc(canvas, size, Vector2(0.2, 0.56), 0.035, moon.darkened(0.15))
	_disc(canvas, size, Vector2(0.32, 0.77), 0.028, moon.darkened(0.15))
	var zzz := Color(0.8, 0.88, 1.0)
	_text(canvas, size, Vector2(0.72, 0.64), "Z", 0.27, zzz, 0.0, 0.22)
	_text(canvas, size, Vector2(0.82, 0.43), "z", 0.21, zzz, 0.0, 0.24)
	_text(canvas, size, Vector2(0.88, 0.25), "z", 0.16, zzz, 0.0, 0.26)


## Cleanup: a maple leaf with a sparkle.
static func draw_cleanup(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	_maple(canvas, size, Vector2(0.45, 0.52), 0.4, LEAF_ORANGE)
	_sparkle(canvas, size, Vector2(0.8, 0.2), 0.15, Color(1.0, 0.96, 0.62))
	_sparkle(canvas, size, Vector2(0.87, 0.44), 0.075, WHITE)


## A heart; "color" makes the empty one grey.
static func draw_heart(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe.get("color", HEART_RED)
	var at := Vector2(0.5, 0.5)
	_fill(canvas, _xf(_heart_pts(), size, at, 0.44), color.darkened(0.28))
	_fill(canvas, _xf(_heart_pts(), size, at + Vector2(0.0, -0.015), 0.37), color)
	_fill(canvas, _xf(_ellipse_pts(Vector2.ZERO, 0.075, 0.045), size, at + Vector2(-0.17, -0.18), 1.0, -0.6), color.lightened(0.45))


## A padlock.
static func draw_lock(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var steel := Color(0.74, 0.76, 0.8)
	var shackle := PackedVector2Array([Vector2(0.31, 0.56)])
	shackle.append_array(_arc_pts(Vector2(0.5, 0.4), 0.19, PI, TAU, 24))
	shackle.append(Vector2(0.69, 0.56))
	_stroke(canvas, size, shackle, 0.1, INK)
	_stroke(canvas, size, shackle, 0.06, steel)
	_inked(canvas, _xf(_rrect_pts(Rect2(0.18, 0.47, 0.64, 0.44), 0.09), size), GOLD, size)
	_fill(canvas, _xf(_rrect_pts(Rect2(0.24, 0.52, 0.52, 0.07), 0.035), size), GOLD.lightened(0.35))
	_disc(canvas, size, Vector2(0.5, 0.66), 0.065, INK)
	_fill(canvas, _xf(PackedVector2Array([Vector2(0.47, 0.68), Vector2(0.53, 0.68), Vector2(0.555, 0.82), Vector2(0.445, 0.82)]), size), INK)


## Done: a fat white check on green.
static func draw_check(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	_disc(canvas, size, Vector2(0.5, 0.5), 0.43, GREEN.darkened(0.25))
	_disc(canvas, size, Vector2(0.5, 0.485), 0.385, GREEN.lightened(0.12))
	_stroke(canvas, size, PackedVector2Array([Vector2(0.29, 0.5), Vector2(0.44, 0.65), Vector2(0.72, 0.35)]), 0.11, WHITE)


## Close: a white X on red.
static func draw_close(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	_disc(canvas, size, Vector2(0.5, 0.5), 0.43, RED.darkened(0.25))
	_disc(canvas, size, Vector2(0.5, 0.485), 0.385, RED.lightened(0.1))
	_line(canvas, size, Vector2(0.34, 0.33), Vector2(0.66, 0.65), 0.11, WHITE)
	_line(canvas, size, Vector2(0.66, 0.33), Vector2(0.34, 0.65), 0.11, WHITE)


## A rounded yellow warning triangle.
static func draw_warning(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var outer := PackedVector2Array([Vector2(0.5, 0.15), Vector2(0.88, 0.83), Vector2(0.12, 0.83)])
	var rim := Color(0.88, 0.6, 0.1)
	_stroke(canvas, size, _closed(outer), 0.11, rim)
	_fill(canvas, _xf(outer, size), rim)
	var inner := _scaled_about(outer, Vector2(0.5, 0.6), 0.8)
	var yellow := Color(1.0, 0.82, 0.26)
	_stroke(canvas, size, _closed(inner), 0.06, yellow)
	_fill(canvas, _xf(inner, size), yellow)
	_line(canvas, size, Vector2(0.5, 0.4), Vector2(0.5, 0.6), 0.09, INK)
	_disc(canvas, size, Vector2(0.5, 0.72), 0.05, INK)


## A bill: a torn-off receipt with a red minus.
static func draw_bill(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var paper := PackedVector2Array([Vector2(0.2, 0.08), Vector2(0.8, 0.08), Vector2(0.8, 0.86)])
	for tooth: int in range(1, 7):
		paper.append(Vector2(0.8 - 0.1 * float(tooth), 0.92 if tooth % 2 == 1 else 0.86))
	_inked(canvas, _xf(paper, size), PAPER, size)
	var line := INK.lightened(0.4)
	for row: Array in [[0.22, 0.7], [0.34, 0.62], [0.46, 0.66], [0.58, 0.48]]:
		_line(canvas, size, Vector2(0.3, row[0]), Vector2(row[1], row[0]), 0.035, line)
	_disc(canvas, size, Vector2(0.7, 0.72), 0.17, INK)
	_disc(canvas, size, Vector2(0.7, 0.72), 0.145, RED)
	_line(canvas, size, Vector2(0.63, 0.72), Vector2(0.77, 0.72), 0.055, WHITE)


## Water: a drop.
static func draw_water(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var blue := Color(0.3, 0.6, 0.94)
	var at := Vector2(0.5, 0.6)
	_fill(canvas, _xf(_drop_pts(), size, at, 0.48), blue.darkened(0.25))
	_fill(canvas, _xf(_drop_pts(), size, at + Vector2(0.0, -0.012), 0.41), blue)
	_arc(canvas, size, at, 0.17, PI * 0.62, PI * 0.95, 0.045, Color(1.0, 1.0, 1.0, 0.9))


## Bonus: a green up arrow with sparkles.
static func draw_bonus(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var arrow := PackedVector2Array([Vector2(0.5, 0.1), Vector2(0.84, 0.46), Vector2(0.64, 0.46), Vector2(0.64, 0.88), Vector2(0.36, 0.88), Vector2(0.36, 0.46), Vector2(0.16, 0.46)])
	_fill(canvas, _xf(arrow, size), GREEN.darkened(0.25))
	_fill(canvas, _xf(_scaled_about(arrow, Vector2(0.5, 0.52), 0.78), size), GREEN.lightened(0.15))
	_sparkle(canvas, size, Vector2(0.18, 0.2), 0.12, GOLD)
	_sparkle(canvas, size, Vector2(0.85, 0.74), 0.09, GOLD)
	_sparkle(canvas, size, Vector2(0.16, 0.7), 0.065, WHITE)


## Medical: a band-aid, never a red cross (a protected emblem).
static func draw_medical(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var at := Vector2(0.5, 0.5)
	var turn := -PI * 0.25
	var tan_color := Color(0.93, 0.74, 0.55)
	_inked(canvas, _xf(_rrect_pts(Rect2(-0.47, -0.17, 0.94, 0.34), 0.17), size, at, 1.0, turn), tan_color, size)
	_fill(canvas, _xf(_rrect_pts(Rect2(-0.15, -0.12, 0.3, 0.24), 0.04), size, at, 1.0, turn), Color(0.99, 0.93, 0.84))
	for x: float in [-0.34, -0.25, 0.25, 0.34]:
		for y: float in [-0.055, 0.055]:
			_disc(canvas, size, at + Vector2(x, y).rotated(turn), 0.018, tan_color.darkened(0.25))


## Split: two little crew heads.
static func draw_split(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	_crew_head(canvas, size, Vector2(0.66, 0.38), 0.15, Color(0.36, 0.55, 0.85), Color(0.98, 0.66, 0.14))
	_crew_head(canvas, size, Vector2(0.37, 0.5), 0.165, Color(0.27, 0.6, 0.36), ORANGE)


## Unread: a speech bubble with a red dot.
static func draw_unread(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var bubble := _union(_rrect_pts(Rect2(0.08, 0.22, 0.74, 0.5), 0.18), PackedVector2Array([Vector2(0.2, 0.62), Vector2(0.4, 0.66), Vector2(0.16, 0.86)]))
	_inked(canvas, _xf(bubble, size), Color(0.98, 0.97, 0.94), size)
	for x: float in [0.29, 0.45, 0.61]:
		_disc(canvas, size, Vector2(x, 0.47), 0.05, INK.lightened(0.3))
	_disc(canvas, size, Vector2(0.8, 0.24), 0.155, INK)
	_disc(canvas, size, Vector2(0.8, 0.24), 0.13, RED.lightened(0.1))
	_disc(canvas, size, Vector2(0.76, 0.2), 0.04, RED.lightened(0.45))


## Voice: a microphone on a stand.
static func draw_voice(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var metal := Color(0.76, 0.79, 0.84)
	var dark := Color(0.4, 0.43, 0.5)
	_stroke(canvas, size, _arc_pts(Vector2(0.5, 0.42), 0.25, 0.0, PI, 24), 0.06, dark)
	_line(canvas, size, Vector2(0.5, 0.67), Vector2(0.5, 0.82), 0.06, dark)
	_line(canvas, size, Vector2(0.34, 0.85), Vector2(0.66, 0.85), 0.07, dark)
	_inked(canvas, _xf(_rrect_pts(Rect2(0.35, 0.1, 0.3, 0.5), 0.15), size), metal, size)
	for y: float in [0.22, 0.3, 0.38]:
		_line(canvas, size, Vector2(0.42, y), Vector2(0.58, y), 0.025, dark)
	_line(canvas, size, Vector2(0.4, 0.44), Vector2(0.4, 0.52), 0.025, WHITE)


## Hidden: two eyes peeking out of a leaf pile, looking for the van.
static func draw_hidden(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	for side: float in [-1.0, 1.0]:
		var eye := Vector2(0.5 + side * 0.11, 0.47)
		_inked(canvas, _xf(_ellipse_pts(eye, 0.085, 0.1), size), WHITE, size)
		_disc(canvas, size, eye + Vector2(-0.03, 0.005), 0.045, INK)
		_disc(canvas, size, eye + Vector2(-0.045, -0.015), 0.013, WHITE)
	var pile := _dome_pts(Vector2(0.5, 0.88), 0.43, 0.36)
	_inked(canvas, _xf(pile, size), Color(0.86, 0.45, 0.15), size)
	var leaves: Array = [
		[Vector2(0.37, 0.57), 0.08, 1.3, YELLOW_LEAF], [Vector2(0.62, 0.56), 0.08, -1.2, RED_LEAF],
		[Vector2(0.22, 0.74), 0.07, -0.9, RED_LEAF], [Vector2(0.5, 0.7), 0.07, 0.2, YELLOW_LEAF],
		[Vector2(0.78, 0.74), 0.07, 1.1, YELLOW_LEAF], [Vector2(0.38, 0.81), 0.06, 1.7, RED_LEAF],
		[Vector2(0.64, 0.8), 0.06, -1.4, LEAF_ORANGE.lightened(0.15)],
	]
	for leaf: Array in leaves:
		_leaf(canvas, size, leaf[0], leaf[1], leaf[2], leaf[3])


## Phone: an old handset.
static func draw_phone(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var body := ORANGE
	var turn := -0.4
	var grow := 1.22
	var center := Vector2(0.5, 0.72)
	# One outline: the curved grip, and an ear cup and a mouth cup that point in
	# toward the curve's center at each end, like the old desk phone's handset.
	var shape := PackedVector2Array()
	shape.append_array(_arc_pts(Vector2.ZERO, 0.38, PI * 1.18, PI * 1.82, 24))
	var inner := _arc_pts(Vector2.ZERO, 0.27, PI * 1.82, PI * 1.18, 24)
	shape.append_array(inner)
	for end: float in [PI * 1.2, PI * 1.8]:
		var cup := _xf(_rrect_pts(Rect2(-0.15, -0.1, 0.3, 0.2), 0.09), 1.0, Vector2.from_angle(end) * 0.27, 1.0, end)
		shape = _union(shape, cup)
	_inked(canvas, _xf(shape, size, center, grow, turn), body, size)
	_stroke(canvas, size, _xf(_arc_pts(Vector2.ZERO, 0.345, PI * 1.32, PI * 1.62, 12), 1.0, center, grow, turn), 0.03, body.lightened(0.35))
	for end: float in [PI * 1.2, PI * 1.8]:
		var face := Vector2.from_angle(end) * 0.15
		_fill(canvas, _xf(_rrect_pts(Rect2(-0.035, -0.08, 0.07, 0.16), 0.03), size, center + face.rotated(turn) * grow, grow, end + turn), body.darkened(0.3))


## Perk: a gold rosette with a leaf on it and two ribbon tails.
static func draw_perk(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var tail := Color(0.86, 0.3, 0.2)
	_inked(canvas, _xf(PackedVector2Array([Vector2(0.36, 0.52), Vector2(0.5, 0.58), Vector2(0.42, 0.92), Vector2(0.35, 0.84), Vector2(0.26, 0.88)]), size), tail, size)
	_inked(canvas, _xf(PackedVector2Array([Vector2(0.64, 0.52), Vector2(0.74, 0.88), Vector2(0.65, 0.84), Vector2(0.58, 0.92), Vector2(0.5, 0.58)]), size), tail.darkened(0.12), size)
	var at := Vector2(0.5, 0.42)
	_inked(canvas, _xf(_star_pts(16, 0.35, 0.3), size, at), GOLD.darkened(0.15), size)
	_disc(canvas, size, at, 0.26, GOLD)
	_disc(canvas, size, at, 0.2, GOLD.lightened(0.25))
	_leaf(canvas, size, at, 0.14, 0.5, Color(0.86, 0.52, 0.1), false)


# ---- phone apps

static func draw_app_texts(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe["color"]
	_tile(canvas, size, color)
	var bubble := _union(_rrect_pts(Rect2(0.2, 0.24, 0.6, 0.42), 0.17), PackedVector2Array([Vector2(0.3, 0.6), Vector2(0.46, 0.62), Vector2(0.24, 0.79)]))
	_fill(canvas, _xf(bubble, size), WHITE)
	for x: float in [0.36, 0.5, 0.64]:
		_disc(canvas, size, Vector2(x, 0.45), 0.05, color)


## Clients: a homeowner peeking over the fence, mug in hand.
static func draw_app_clients(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe["color"]
	_tile(canvas, size, color)
	var edge := color.darkened(0.3)
	_disc(canvas, size, Vector2(0.44, 0.46), 0.15, WHITE)
	_fill(canvas, _xf(_dome_pts(Vector2(0.44, 0.4), 0.15, 0.1), size), color.lightened(0.55))
	for x: float in [0.39, 0.5]:
		_disc(canvas, size, Vector2(x, 0.47), 0.025, edge)
	for x: float in [0.18, 0.34, 0.5, 0.66]:
		_inked(canvas, _xf(PackedVector2Array([Vector2(x, 0.62), Vector2(x + 0.07, 0.55), Vector2(x + 0.14, 0.62), Vector2(x + 0.14, 0.86), Vector2(x, 0.86)]), size), WHITE, size, edge, 0.016)
	_inked(canvas, _xf(_rrect_pts(Rect2(0.62, 0.42, 0.13, 0.13), 0.02), size), WHITE, size, edge, 0.016)
	_arc(canvas, size, Vector2(0.77, 0.485), 0.035, -PI * 0.5, PI * 0.5, 0.022, WHITE)
	_stroke(canvas, size, PackedVector2Array([Vector2(0.66, 0.38), Vector2(0.68, 0.33), Vector2(0.66, 0.28)]), 0.018, Color(1.0, 1.0, 1.0, 0.85))
	_stroke(canvas, size, PackedVector2Array([Vector2(0.71, 0.38), Vector2(0.73, 0.33), Vector2(0.71, 0.28)]), 0.018, Color(1.0, 1.0, 1.0, 0.85))


## Map: a folded map with a pin in it.
static func draw_app_map(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe["color"]
	_tile(canvas, size, color)
	var edge := color.darkened(0.3)
	var panels: Array = [
		[PackedVector2Array([Vector2(0.18, 0.3), Vector2(0.4, 0.24), Vector2(0.4, 0.78), Vector2(0.18, 0.84)]), WHITE],
		[PackedVector2Array([Vector2(0.4, 0.24), Vector2(0.6, 0.3), Vector2(0.6, 0.84), Vector2(0.4, 0.78)]), Color(0.84, 0.93, 0.92)],
		[PackedVector2Array([Vector2(0.6, 0.3), Vector2(0.82, 0.24), Vector2(0.82, 0.78), Vector2(0.6, 0.84)]), WHITE],
	]
	for panel: Array in panels:
		_inked(canvas, _xf(panel[0], size), panel[1], size, edge, 0.016)
	for dash: Array in [[Vector2(0.24, 0.72), Vector2(0.3, 0.66)], [Vector2(0.36, 0.62), Vector2(0.43, 0.6)], [Vector2(0.49, 0.6), Vector2(0.55, 0.56)]]:
		_line(canvas, size, dash[0], dash[1], 0.03, color)
	_fill(canvas, _xf(_drop_pts(), size, Vector2(0.64, 0.4), 0.18, PI), RED)
	_disc(canvas, size, Vector2(0.64, 0.4), 0.045, WHITE)


## Crew: a hard hat with a leaf stuck on it.
static func draw_app_crew(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe["color"]
	_tile(canvas, size, color)
	_fill(canvas, _xf(_dome_pts(Vector2(0.5, 0.63), 0.28, 0.3), size), WHITE)
	_fill(canvas, _xf(_rrect_pts(Rect2(0.14, 0.6, 0.72, 0.09), 0.045), size), WHITE)
	_line(canvas, size, Vector2(0.24, 0.6), Vector2(0.76, 0.6), 0.02, color.lightened(0.45))
	_line(canvas, size, Vector2(0.5, 0.36), Vector2(0.5, 0.58), 0.07, color.lightened(0.55))
	_leaf(canvas, size, Vector2(0.64, 0.45), 0.11, 0.8, Color(0.84, 0.3, 0.14))


## Orders (deliveries): a taped box.
static func draw_app_deliveries(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe["color"]
	_tile(canvas, size, color)
	var edge := color.darkened(0.45)
	_inked(canvas, _xf(PackedVector2Array([Vector2(0.2, 0.44), Vector2(0.4, 0.32), Vector2(0.8, 0.32), Vector2(0.6, 0.44)]), size), Color(1.0, 0.95, 0.82), size, edge, 0.016)
	_inked(canvas, _xf(PackedVector2Array([Vector2(0.6, 0.44), Vector2(0.8, 0.32), Vector2(0.8, 0.7), Vector2(0.6, 0.82)]), size), Color(0.9, 0.76, 0.54), size, edge, 0.016)
	_inked(canvas, _xf(_rect_pts(Rect2(0.2, 0.44, 0.4, 0.38)), size), Color(0.99, 0.9, 0.72), size, edge, 0.016)
	var tape := Color(0.7, 0.5, 0.28)
	_fill(canvas, _xf(PackedVector2Array([Vector2(0.36, 0.44), Vector2(0.44, 0.44), Vector2(0.64, 0.32), Vector2(0.56, 0.32)]), size), tape)
	_fill(canvas, _xf(_rect_pts(Rect2(0.36, 0.44, 0.08, 0.16)), size), tape)
	_line(canvas, size, Vector2(0.25, 0.72), Vector2(0.33, 0.72), 0.02, edge)
	_line(canvas, size, Vector2(0.25, 0.76), Vector2(0.3, 0.76), 0.02, edge)


## Closet: a shirt on a hanger.
static func draw_app_closet(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe["color"]
	_tile(canvas, size, color)
	var shirt := PackedVector2Array([
		Vector2(0.3, 0.57), Vector2(0.42, 0.55), Vector2(0.5, 0.61), Vector2(0.58, 0.55), Vector2(0.7, 0.57),
		Vector2(0.84, 0.68), Vector2(0.76, 0.76), Vector2(0.7, 0.72), Vector2(0.7, 0.87), Vector2(0.3, 0.87),
		Vector2(0.3, 0.72), Vector2(0.24, 0.76), Vector2(0.16, 0.68),
	])
	_inked(canvas, _xf(shirt, size), Color(0.18, 0.56, 0.62), size, color.darkened(0.4), 0.016)
	_arc(canvas, size, Vector2(0.5, 0.22), 0.065, PI, PI * 2.5, 0.045, WHITE)
	_line(canvas, size, Vector2(0.5, 0.285), Vector2(0.5, 0.34), 0.045, WHITE)
	_stroke(canvas, size, PackedVector2Array([Vector2(0.5, 0.34), Vector2(0.84, 0.55), Vector2(0.16, 0.55), Vector2(0.5, 0.34)]), 0.05, WHITE)


## Hires: two heads and a plus.
static func draw_app_hires(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe["color"]
	_tile(canvas, size, color)
	_person(canvas, size, Vector2(0.6, 0.34), 0.1, WHITE.darkened(0.12), color)
	_person(canvas, size, Vector2(0.4, 0.43), 0.115, WHITE, color)
	_disc(canvas, size, Vector2(0.72, 0.7), 0.145, color)
	_disc(canvas, size, Vector2(0.72, 0.7), 0.12, GREEN.lightened(0.15))
	_line(canvas, size, Vector2(0.66, 0.7), Vector2(0.78, 0.7), 0.045, WHITE)
	_line(canvas, size, Vector2(0.72, 0.64), Vector2(0.72, 0.76), 0.045, WHITE)


## Shop: a Homie Depot shopping bag with a house on it.
static func draw_app_shop(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe["color"]
	_tile(canvas, size, color)
	_arc(canvas, size, Vector2(0.5, 0.4), 0.13, PI, TAU, 0.05, WHITE)
	_fill(canvas, _xf(PackedVector2Array([Vector2(0.24, 0.4), Vector2(0.76, 0.4), Vector2(0.8, 0.85), Vector2(0.2, 0.85)]), size), WHITE)
	var house := _union(PackedVector2Array([Vector2(0.5, 0.48), Vector2(0.67, 0.61), Vector2(0.33, 0.61)]), _rect_pts(Rect2(0.38, 0.6, 0.24, 0.16)))
	_fill(canvas, _xf(house, size), color)
	_fill(canvas, _xf(_rect_pts(Rect2(0.46, 0.66, 0.08, 0.1)), size), WHITE)


## Properties: a garage.
static func draw_app_properties(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe["color"]
	_tile(canvas, size, color)
	_fill(canvas, _xf(PackedVector2Array([Vector2(0.5, 0.18), Vector2(0.86, 0.46), Vector2(0.86, 0.85), Vector2(0.14, 0.85), Vector2(0.14, 0.46)]), size), WHITE)
	_fill(canvas, _xf(_rect_pts(Rect2(0.27, 0.5, 0.46, 0.35)), size), color.darkened(0.15))
	for y: float in [0.58, 0.66, 0.74]:
		_line(canvas, size, Vector2(0.31, y), Vector2(0.69, y), 0.02, color.lightened(0.3))
	_disc(canvas, size, Vector2(0.5, 0.37), 0.05, color)


# ---- moods

## Thrilled: tears of joy.
static func draw_mood_thrilled(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	_face(canvas, size)
	for x: float in [0.36, 0.64]:
		_arc(canvas, size, Vector2(x, 0.46), 0.07, PI * 1.1, PI * 1.9, 0.045, INK)
	var mouth := _bowl_pts(Vector2(0.5, 0.58), 0.22, 0.21)
	_fill(canvas, _xf(mouth, size), INK)
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(mouth, _ellipse_pts(Vector2(0.5, 0.76), 0.1, 0.07)):
		_fill(canvas, _xf(piece, size), Color(0.92, 0.36, 0.38))
	_fill(canvas, _xf(_rrect_pts(Rect2(0.31, 0.58, 0.38, 0.05), 0.02), size), WHITE)
	for side: float in [-1.0, 1.0]:
		_inked(canvas, _xf(_drop_pts(), size, Vector2(0.5 + side * 0.32, 0.58), 0.1, side * 0.6), TEAR_BLUE, size, INK, 0.014)


static func draw_mood_happy(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	_face(canvas, size)
	for x: float in [0.37, 0.63]:
		_fill(canvas, _xf(_ellipse_pts(Vector2(x, 0.42), 0.045, 0.07), size), INK)
		_disc(canvas, size, Vector2(x + (-0.12 if x < 0.5 else 0.12), 0.6), 0.06, FACE_YELLOW.lerp(Color(1.0, 0.5, 0.45), 0.55))
	_arc(canvas, size, Vector2(0.5, 0.52), 0.21, PI * 0.18, PI * 0.82, 0.05, INK)


## Fine: a flat mouth.
static func draw_mood_fine(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	_face(canvas, size, FACE_YELLOW.lerp(PAPER, 0.25))
	for x: float in [0.37, 0.63]:
		_fill(canvas, _xf(_ellipse_pts(Vector2(x, 0.43), 0.042, 0.065), size), INK)
	_line(canvas, size, Vector2(0.37, 0.67), Vector2(0.63, 0.67), 0.05, INK)


## Impatient ("slow"): an eye-roll and a sweat drop.
static func draw_mood_slow(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var skin := Color(1.0, 0.7, 0.3)
	_face(canvas, size, skin)
	for x: float in [0.37, 0.63]:
		_inked(canvas, _xf(_ellipse_pts(Vector2(x, 0.45), 0.085, 0.1), size), WHITE, size)
		_disc(canvas, size, Vector2(x + 0.01, 0.38), 0.042, INK)
	_line(canvas, size, Vector2(0.27, 0.3), Vector2(0.44, 0.27), 0.035, INK)
	_line(canvas, size, Vector2(0.38, 0.71), Vector2(0.62, 0.67), 0.05, INK)
	_inked(canvas, _xf(_drop_pts(), size, Vector2(0.8, 0.32), 0.1, 0.3), TEAR_BLUE, size, INK, 0.014)


## Unimpressed ("messy"): half-lidded, with a leaf stuck to the forehead.
static func draw_mood_messy(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var skin := Color(0.98, 0.78, 0.32)
	_face(canvas, size, skin)
	for x: float in [0.37, 0.63]:
		var eye := Vector2(x, 0.47)
		_inked(canvas, _xf(_ellipse_pts(eye, 0.085, 0.085), size), WHITE, size)
		_disc(canvas, size, eye + Vector2(0.0, 0.03), 0.04, INK)
		_fill(canvas, _xf(_dome_pts(eye, 0.095, 0.095), size), skin.darkened(0.08))
		_line(canvas, size, eye + Vector2(-0.095, 0.0), eye + Vector2(0.095, 0.0), 0.035, INK)
	_stroke(canvas, size, PackedVector2Array([Vector2(0.38, 0.73), Vector2(0.5, 0.7), Vector2(0.62, 0.71)]), 0.045, INK)
	_leaf(canvas, size, Vector2(0.6, 0.22), 0.13, 1.15, LEAF_ORANGE)


# ---- seasons

static func draw_season_autumn(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	_maple(canvas, size, Vector2(0.5, 0.5), 0.42, Color(0.88, 0.36, 0.14), 0.15)


static func draw_season_winter(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var ice := Color(0.55, 0.8, 1.0)
	var center := Vector2(0.5, 0.5)
	for pass_index: int in 2:
		var color := ice if pass_index == 0 else WHITE
		var width := 0.08 if pass_index == 0 else 0.03
		for arm: int in 6:
			var direction := Vector2.from_angle(TAU * float(arm) / 6.0 - PI * 0.5)
			_line(canvas, size, center, center + direction * 0.4, width, color)
			for reach: float in [0.2, 0.3]:
				for side: float in [-1.0, 1.0]:
					var branch := center + direction * reach
					_line(canvas, size, branch, branch + direction.rotated(side * 0.8) * (0.11 if reach < 0.25 else 0.08), width * 0.8, color)
	_fill(canvas, _xf(_star_pts(6, 0.1, 0.08, 0.0), size, center), ice)


static func draw_season_spring(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	_inked(canvas, _xf(_dome_pts(Vector2(0.5, 0.88), 0.32, 0.14), size), Color(0.5, 0.34, 0.2), size)
	_stroke(canvas, size, PackedVector2Array([Vector2(0.5, 0.79), Vector2(0.5, 0.62), Vector2(0.52, 0.49)]), 0.06, GREEN)
	_leaf(canvas, size, Vector2(0.37, 0.41), 0.17, -1.0, Color(0.45, 0.78, 0.3))
	_leaf(canvas, size, Vector2(0.7, 0.36), 0.2, 1.0, Color(0.38, 0.72, 0.28))


# ---- neighborhood pins

static func draw_hood_maple_row(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	_pin(canvas, size, recipe["color"])
	_maple(canvas, size, Vector2(0.5, 0.42), 0.15, Color(0.88, 0.36, 0.14))


## Dandelion Acres: a dandelion puff.
static func draw_hood_dandelion_acres(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	_pin(canvas, size, recipe["color"])
	var seed_grey := Color(0.56, 0.6, 0.7)
	var center := Vector2(0.5, 0.36)
	_stroke(canvas, size, PackedVector2Array([center, Vector2(0.52, 0.48), Vector2(0.5, 0.57)]), 0.025, GREEN)
	for index: int in 16:
		var direction := Vector2.from_angle(TAU * float(index) / 16.0)
		_line(canvas, size, center + direction * 0.025, center + direction * 0.115, 0.01, seed_grey)
		_disc(canvas, size, center + direction * 0.125, 0.018, seed_grey)
	_disc(canvas, size, center, 0.03, seed_grey.darkened(0.2))


## Birchwood Commons: a striped birch trunk.
static func draw_hood_birchwood_commons(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	_pin(canvas, size, recipe["color"], Color(0.86, 0.93, 0.84))
	_line(canvas, size, Vector2(0.54, 0.33), Vector2(0.62, 0.27), 0.022, Color(0.45, 0.36, 0.28))
	_leaf(canvas, size, Vector2(0.64, 0.25), 0.04, 1.0, GREEN, false)
	_inked(canvas, _xf(_rrect_pts(Rect2(0.45, 0.24, 0.1, 0.35), 0.03), size), WHITE, size, INK, 0.012)
	for mark: Array in [[0.46, 0.5, 0.31], [0.5, 0.54, 0.4], [0.46, 0.49, 0.48], [0.51, 0.54, 0.54]]:
		_line(canvas, size, Vector2(mark[0], mark[2]), Vector2(mark[1], mark[2]), 0.02, INK)


## Oak Hollow: an acorn with a tiny HOA clipboard.
static func draw_hood_oak_hollow(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	_pin(canvas, size, recipe["color"])
	var brown := Color(0.42, 0.26, 0.14)
	_inked(canvas, _xf(_ellipse_pts(Vector2(0.45, 0.45), 0.075, 0.095), size), Color(0.86, 0.62, 0.34), size, INK, 0.012)
	_line(canvas, size, Vector2(0.45, 0.31), Vector2(0.47, 0.27), 0.02, brown)
	_inked(canvas, _xf(_dome_pts(Vector2(0.45, 0.39), 0.095, 0.07), size), brown, size, INK, 0.012)
	_disc(canvas, size, Vector2(0.43, 0.45), 0.012, INK)
	_disc(canvas, size, Vector2(0.47, 0.45), 0.012, INK)
	_inked(canvas, _xf(_rrect_pts(Rect2(0.52, 0.37, 0.12, 0.16), 0.015), size), Color(0.62, 0.42, 0.24), size, INK, 0.012)
	_fill(canvas, _xf(_rect_pts(Rect2(0.54, 0.4, 0.08, 0.11)), size), WHITE)
	_fill(canvas, _xf(_rrect_pts(Rect2(0.555, 0.355, 0.05, 0.03), 0.01), size), Color(0.6, 0.62, 0.66))
	for y: float in [0.43, 0.46, 0.49]:
		_line(canvas, size, Vector2(0.555, y), Vector2(0.605, y), 0.008, INK)


## Lakeside: waves.
static func draw_hood_lakeside(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var color: Color = recipe["color"]
	_pin(canvas, size, color)
	for row: float in [0.35, 0.45]:
		var wave := PackedVector2Array()
		for step: int in 17:
			var t := float(step) / 16.0
			wave.append(Vector2(lerpf(0.36, 0.64, t), row + sin(t * TAU * 1.5) * 0.022))
		_stroke(canvas, size, wave, 0.035, color)


## Mansion Hill: a columned portico.
static func draw_hood_mansion_hill(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	_pin(canvas, size, recipe["color"])
	var stone := Color(0.42, 0.34, 0.52)
	_fill(canvas, _xf(PackedVector2Array([Vector2(0.5, 0.25), Vector2(0.67, 0.33), Vector2(0.33, 0.33)]), size), stone)
	_fill(canvas, _xf(_rect_pts(Rect2(0.34, 0.335, 0.32, 0.03)), size), stone)
	for x: float in [0.37, 0.465, 0.56]:
		_fill(canvas, _xf(_rect_pts(Rect2(x, 0.38, 0.07, 0.15)), size), stone)
	_fill(canvas, _xf(_rect_pts(Rect2(0.33, 0.54, 0.34, 0.035)), size), stone)


# ---- brands

## Homie Depot: an orange circle with a white house in a backwards cap. Never an
## orange square with stencil type: it must not read as any real store's mark.
static func draw_brand_homie_depot(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	_disc(canvas, size, Vector2(0.5, 0.5), 0.44, ORANGE.darkened(0.25))
	_disc(canvas, size, Vector2(0.5, 0.5), 0.4, ORANGE)
	_arc(canvas, size, Vector2(0.5, 0.5), 0.35, 0.0, TAU, 0.012, ORANGE.lightened(0.3))
	var house := _union(PackedVector2Array([Vector2(0.5, 0.3), Vector2(0.77, 0.53), Vector2(0.23, 0.53)]), _rect_pts(Rect2(0.31, 0.5, 0.38, 0.27)))
	_fill(canvas, _xf(house, size), WHITE)
	_fill(canvas, _xf(_rect_pts(Rect2(0.45, 0.61, 0.1, 0.16)), size), ORANGE)
	_fill(canvas, _xf(_rect_pts(Rect2(0.35, 0.57, 0.07, 0.07)), size), ORANGE)
	_fill(canvas, _xf(_rect_pts(Rect2(0.58, 0.57, 0.07, 0.07)), size), ORANGE)
	# The cap, on backwards: the brim pokes out behind, the strap gap faces us.
	var navy := Color(0.18, 0.24, 0.42)
	var apex := Vector2(0.5, 0.31)
	var tip := -0.14
	_fill(canvas, _xf(PackedVector2Array([Vector2(-0.06, -0.035), Vector2(-0.27, -0.1), Vector2(-0.29, -0.04), Vector2(-0.08, 0.0)]), size, apex, 1.0, tip), navy.darkened(0.2))
	_inked(canvas, _xf(_dome_pts(Vector2.ZERO, 0.13, 0.12), size, apex, 1.0, tip), navy, size, INK, 0.012)
	_fill(canvas, _xf(_dome_pts(Vector2.ZERO, 0.04, 0.045), size, apex, 1.0, tip), WHITE)
	_disc(canvas, size, apex + Vector2(0.0, -0.12).rotated(tip), 0.02, navy.lightened(0.3))


## Chefty: a red chef's hat over a truck grille (DEC-006, on every truck).
static func draw_brand_chefty(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var grey := Color(0.3, 0.3, 0.33)
	_inked(canvas, _xf(_rrect_pts(Rect2(0.16, 0.5, 0.68, 0.36), 0.08), size), grey, size)
	_fill(canvas, _xf(_rrect_pts(Rect2(0.3, 0.55, 0.4, 0.24), 0.04), size), Color(0.8, 0.82, 0.85))
	for y: float in [0.61, 0.67, 0.73]:
		_line(canvas, size, Vector2(0.33, y), Vector2(0.67, y), 0.025, grey)
	for x: float in [0.235, 0.765]:
		_disc(canvas, size, Vector2(x, 0.62), 0.045, Color(1.0, 0.92, 0.6))
	_line(canvas, size, Vector2(0.21, 0.82), Vector2(0.79, 0.82), 0.04, Color(0.66, 0.68, 0.72))
	var red := CHEFTY_RED
	var hat := _rrect_pts(Rect2(0.3, 0.3, 0.4, 0.18), 0.03)
	for puff: Array in [[Vector2(0.34, 0.31), 0.125], [Vector2(0.5, 0.25), 0.155], [Vector2(0.66, 0.31), 0.125]]:
		hat = _union(hat, _ellipse_pts(puff[0], puff[1], puff[1] * 0.92))
	_inked(canvas, _xf(hat, size), red, size)
	_fill(canvas, _xf(_rect_pts(Rect2(0.31, 0.39, 0.38, 0.08)), size), red.darkened(0.18))
	_disc(canvas, size, Vector2(0.45, 0.2), 0.05, red.lightened(0.3))


## TurfMasters: a glossy green ribbon that says TM, with its own little TM.
static func draw_brand_turfmasters(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var green := Color(0.15, 0.58, 0.3)
	for side: float in [-1.0, 1.0]:
		var tail := PackedVector2Array()
		for point: Vector2 in [Vector2(0.06, 0.46), Vector2(0.24, 0.46), Vector2(0.24, 0.72), Vector2(0.06, 0.72), Vector2(0.13, 0.59)]:
			tail.append(Vector2(0.5 + (point.x - 0.5) * side, point.y))
		_inked(canvas, _xf(tail, size), green.darkened(0.25), size)
		var fold := PackedVector2Array()
		for point: Vector2 in [Vector2(0.16, 0.64), Vector2(0.24, 0.64), Vector2(0.24, 0.72)]:
			fold.append(Vector2(0.5 + (point.x - 0.5) * side, point.y))
		_fill(canvas, _xf(fold, size), green.darkened(0.55))
	var band := _rect_pts(Rect2(0.16, 0.35, 0.68, 0.29))
	_fill_gradient(canvas, _xf(band, size), green.lightened(0.32), green.darkened(0.05))
	canvas.draw_polyline(_closed(_xf(band, size)), INK, FLAT_INK * size, true)
	_fill(canvas, _xf(_rrect_pts(Rect2(0.2, 0.38, 0.6, 0.06), 0.03), size), Color(1.0, 1.0, 1.0, 0.3))
	for y: float in [0.385, 0.605]:
		_line(canvas, size, Vector2(0.19, y), Vector2(0.81, y), 0.012, GOLD)
	_text(canvas, size, Vector2(0.47, 0.5), "TM", 0.22, WHITE, 0.0, 0.16, green.darkened(0.55))
	_text(canvas, size, Vector2(0.67, 0.43), "TM", 0.07, WHITE)


## Rusty's: a riveted rust-red disc with a big R.
static func draw_brand_rustys(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var rust := Color(0.66, 0.32, 0.15)
	_disc(canvas, size, Vector2(0.5, 0.5), 0.44, rust.darkened(0.32))
	_disc(canvas, size, Vector2(0.5, 0.5), 0.4, rust)
	for spot: Array in [[Vector2(0.3, 0.68), 0.05], [Vector2(0.7, 0.3), 0.04], [Vector2(0.67, 0.72), 0.03], [Vector2(0.27, 0.36), 0.03]]:
		_disc(canvas, size, spot[0], spot[1], rust.darkened(0.15))
	for index: int in 10:
		var at := Vector2(0.5, 0.5) + Vector2.from_angle(TAU * float(index) / 10.0 + 0.3) * 0.35
		_disc(canvas, size, at, 0.024, Color(0.86, 0.76, 0.62))
		_disc(canvas, size, at + Vector2(0.006, 0.006), 0.01, rust.darkened(0.3))
	_text(canvas, size, Vector2(0.5, 0.5), "R", 0.46, Color(0.98, 0.9, 0.72), 0.0, 0.14)
	_stroke(canvas, size, PackedVector2Array([Vector2(0.74, 0.56), Vector2(0.77, 0.6), Vector2(0.75, 0.64)]), 0.014, rust.darkened(0.45))


## Lunch Money: a brown paper lunch bag with a "$" on it.
static func draw_brand_lunch_money(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var kraft := Color(0.82, 0.62, 0.4)
	_inked(canvas, _xf(PackedVector2Array([Vector2(0.24, 0.32), Vector2(0.76, 0.32), Vector2(0.78, 0.88), Vector2(0.22, 0.88)]), size), kraft, size)
	var top := PackedVector2Array([Vector2(0.26, 0.33), Vector2(0.74, 0.33), Vector2(0.74, 0.14)])
	for tooth: int in range(1, 9):
		top.append(Vector2(0.74 - 0.06 * float(tooth), 0.18 if tooth % 2 == 1 else 0.14))
	_inked(canvas, _xf(top, size), kraft.darkened(0.12), size)
	_line(canvas, size, Vector2(0.3, 0.38), Vector2(0.28, 0.84), 0.012, kraft.darkened(0.2))
	_text(canvas, size, Vector2(0.51, 0.62), "$", 0.4, GREEN, 0.0, 0.1)


## The Snak-o-Matic: a vending machine with its snacks lined up.
static func draw_brand_snak_o_matic(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var body := Color(0.15, 0.55, 0.62)
	_inked(canvas, _xf(_rrect_pts(Rect2(0.22, 0.08, 0.56, 0.84), 0.06), size), body, size)
	_fill(canvas, _xf(_rrect_pts(Rect2(0.26, 0.11, 0.48, 0.07), 0.02), size), Color(1.0, 0.82, 0.25))
	_inked(canvas, _xf(_rect_pts(Rect2(0.27, 0.22, 0.31, 0.49)), size), Color(0.18, 0.24, 0.3), size, INK, 0.012)
	var snacks: Array[Color] = [ORANGE, Color(1.0, 0.85, 0.25), RED, GREEN, Color(0.6, 0.4, 0.8), Color(0.35, 0.6, 0.95)]
	for row: int in 3:
		for column: int in 3:
			var at := Vector2(0.3 + 0.09 * float(column), 0.26 + 0.14 * float(row))
			_fill(canvas, _xf(_rrect_pts(Rect2(at, Vector2(0.07, 0.09)), 0.015), size), snacks[(row * 3 + column + row) % snacks.size()])
		_line(canvas, size, Vector2(0.29, 0.36 + 0.14 * float(row)), Vector2(0.56, 0.36 + 0.14 * float(row)), 0.01, Color(0.6, 0.62, 0.66))
	_line(canvas, size, Vector2(0.32, 0.64), Vector2(0.52, 0.27), 0.02, Color(1.0, 1.0, 1.0, 0.3))
	_fill(canvas, _xf(_rrect_pts(Rect2(0.61, 0.22, 0.13, 0.3), 0.02), size), Color(0.75, 0.78, 0.8))
	_line(canvas, size, Vector2(0.675, 0.27), Vector2(0.675, 0.33), 0.016, INK)
	for at: Vector2 in [Vector2(0.65, 0.41), Vector2(0.7, 0.41), Vector2(0.65, 0.47), Vector2(0.7, 0.47)]:
		_disc(canvas, size, at, 0.015, INK.lightened(0.3))
	_fill(canvas, _xf(_rrect_pts(Rect2(0.29, 0.76, 0.27, 0.09), 0.02), size), INK)


# ---- snacks (shops chunk 6)

## A hot dog in its bun, lying a little tilted, a mustard zigzag along it.
static func draw_hot_dog(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var angle := -0.38
	var at := Vector2(0.5, 0.55)
	var bun := Color(0.93, 0.68, 0.38)
	_inked(canvas, _xf(_ellipse_pts(Vector2(0.0, 0.07), 0.42, 0.15), size, at, 1.0, angle), bun.darkened(0.08), size)
	_inked(canvas, _xf(_ellipse_pts(Vector2(0.0, -0.01), 0.45, 0.085), size, at, 1.0, angle), Color(0.76, 0.3, 0.2), size)
	_inked(canvas, _xf(_ellipse_pts(Vector2(0.0, 0.1), 0.4, 0.1), size, at, 1.0, angle), bun, size)
	var zig := PackedVector2Array()
	for step: int in 9:
		zig.append(Vector2(-0.3 + float(step) * 0.075, -0.03 + (0.035 if step % 2 == 0 else -0.035)))
	_stroke(canvas, size, _xf(zig, 1.0, at, 1.0, angle), 0.03, Color(1.0, 0.82, 0.12))


## A can of Turbo Juice with its lightning bolt. "warm": the machine's, paler,
## with heat wobbling off it. "zap": sparks off the top (the buff).
static func draw_turbo_can(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var warm := bool(recipe.get("warm", false))
	var body := Color(0.4, 0.72, 0.5) if warm else Color(0.12, 0.75, 0.35)
	var can := Rect2(0.32, 0.16, 0.36, 0.72)
	_inked(canvas, _xf(_rrect_pts(can, 0.06), size), body, size)
	_fill(canvas, _xf(_rect_pts(Rect2(can.position.x, 0.44, can.size.x, 0.14)), size), Color(1.0, 0.86, 0.15))
	_fill(canvas, _xf(_rrect_pts(Rect2(0.36, 0.12, 0.28, 0.06), 0.02), size), Color(0.8, 0.82, 0.85))
	var bolt := PackedVector2Array([Vector2(0.53, 0.25), Vector2(0.42, 0.53), Vector2(0.5, 0.53), Vector2(0.46, 0.76), Vector2(0.6, 0.44), Vector2(0.52, 0.44), Vector2(0.57, 0.25)])
	_inked(canvas, _xf(bolt, size), WHITE, size, INK, 0.012)
	_line(canvas, size, Vector2(0.38, 0.22), Vector2(0.38, 0.8), 0.022, Color(1.0, 1.0, 1.0, 0.35))
	if warm:
		for index: int in 2:
			var x := 0.22 + float(index) * 0.56
			_stroke(canvas, size, PackedVector2Array([Vector2(x, 0.62), Vector2(x - 0.03, 0.52), Vector2(x + 0.02, 0.42), Vector2(x - 0.02, 0.32)]), 0.025, Color(0.95, 0.5, 0.2, 0.8))
	if bool(recipe.get("zap", false)):
		for index: int in 3:
			var direction := Vector2.from_angle(-PI * 0.5 + (float(index) - 1.0) * 0.7)
			_line(canvas, size, Vector2(0.5, 0.12) + direction * 0.04, Vector2(0.5, 0.12) + direction * 0.12, 0.035, GOLD)


## A paper cup of burnt coffee: white, a brown sleeve, a black lid, steam.
static func draw_coffee_cup(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	_inked(canvas, _xf(PackedVector2Array([Vector2(0.3, 0.32), Vector2(0.7, 0.32), Vector2(0.64, 0.88), Vector2(0.36, 0.88)]), size), Color(0.97, 0.96, 0.92), size)
	_fill(canvas, _xf(PackedVector2Array([Vector2(0.315, 0.48), Vector2(0.685, 0.48), Vector2(0.665, 0.68), Vector2(0.335, 0.68)]), size), Color(0.55, 0.36, 0.22))
	_inked(canvas, _xf(_rrect_pts(Rect2(0.26, 0.24, 0.48, 0.1), 0.03), size), Color(0.2, 0.18, 0.18), size)
	for index: int in 2:
		var x := 0.43 + float(index) * 0.14
		_stroke(canvas, size, PackedVector2Array([Vector2(x, 0.2), Vector2(x - 0.04, 0.14), Vector2(x + 0.02, 0.08), Vector2(x - 0.02, 0.03)]), 0.03, Color(0.82, 0.82, 0.86, 0.9))


## A plastic-wedge sandwich, white bread and a frill of lettuce. "queasy":
## gone a little green, with stink lines.
static func draw_sandwich(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var queasy := bool(recipe.get("queasy", false))
	var bread := Color(0.82, 0.88, 0.62) if queasy else Color(0.97, 0.92, 0.78)
	var wedge := PackedVector2Array([Vector2(0.16, 0.82), Vector2(0.84, 0.82), Vector2(0.24, 0.26)])
	_inked(canvas, _xf(wedge, size), bread.darkened(0.12), size)
	_fill(canvas, _xf(PackedVector2Array([Vector2(0.2, 0.74), Vector2(0.78, 0.74), Vector2(0.25, 0.36)]), size), Color(0.45, 0.72, 0.3) if not queasy else Color(0.5, 0.62, 0.25))
	_fill(canvas, _xf(PackedVector2Array([Vector2(0.24, 0.7), Vector2(0.7, 0.7), Vector2(0.27, 0.42)]), size), Color(0.92, 0.6, 0.55) if not queasy else Color(0.7, 0.72, 0.45))
	_inked(canvas, _xf(PackedVector2Array([Vector2(0.27, 0.66), Vector2(0.64, 0.66), Vector2(0.29, 0.46)]), size), bread, size, INK, 0.012)
	if queasy:
		for index: int in 3:
			var x := 0.5 + float(index) * 0.12
			_stroke(canvas, size, PackedVector2Array([Vector2(x, 0.4), Vector2(x - 0.03, 0.3), Vector2(x + 0.02, 0.2), Vector2(x - 0.02, 0.1)]), 0.025, Color(0.45, 0.75, 0.25))


## The crash: an empty Turbo can tipped over, dented, a little "z" off it.
static func draw_crash(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var at := Vector2(0.46, 0.66)
	var angle := PI * 0.5 - 0.15
	var can := PackedVector2Array([Vector2(-0.16, -0.32), Vector2(0.16, -0.32), Vector2(0.16, 0.05), Vector2(0.08, 0.1), Vector2(0.16, 0.16), Vector2(0.16, 0.32), Vector2(-0.16, 0.32)])
	_inked(canvas, _xf(can, size, at, 1.0, angle), Color(0.45, 0.6, 0.5), size)
	_fill(canvas, _xf(_rect_pts(Rect2(-0.155, -0.06, 0.31, 0.11)), size, at, 1.0, angle), Color(0.85, 0.75, 0.3))
	_text(canvas, size, Vector2(0.72, 0.3), "z", 0.22, WHITE, 0.0, 0.18)
	_text(canvas, size, Vector2(0.84, 0.14), "z", 0.15, WHITE, 0.0, 0.18)


## The Chefty Net: two stuffed leaf bags with an orange cargo net strapped over
## them, hooked down at both ends.
static func draw_chefty_net(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	for bag: Array in [[Vector2(0.33, 0.6), -0.12], [Vector2(0.65, 0.58), 0.1]]:
		var at: Vector2 = bag[0]
		var angle: float = bag[1]
		var sack := _union(_rrect_pts(Rect2(-0.18, -0.2, 0.36, 0.42), 0.12), _ellipse_pts(Vector2(0.0, -0.22), 0.06, 0.05))
		_inked(canvas, _xf(sack, size, at, 1.0, angle), KRAFT, size)
		_line(canvas, size, at + Vector2(-0.05, -0.17).rotated(angle), at + Vector2(0.05, -0.17).rotated(angle), 0.03, KRAFT.darkened(0.35))
	var net := Color(1.0, 0.55, 0.12)
	var center := Vector2(0.49, 0.8)
	var radii := Vector2(0.41, 0.47)
	# The mesh: diagonals both ways, only where they lie inside the dome.
	for way: float in [1.0, -1.0]:
		for step: int in range(-5, 6):
			var inside := PackedVector2Array()
			for sample: int in 41:
				var along := -0.7 + float(sample) * 0.035
				var point := center + Vector2(float(step) * 0.15 + along * 0.7071 * way, -0.24 - along * 0.7071)
				var rel := (point - center) / radii
				if rel.length() <= 1.0 and point.y <= center.y:
					inside.append(point)
			if inside.size() >= 2:
				_stroke(canvas, size, inside, 0.017, net)
	_stroke(canvas, size, _dome_pts(center, radii.x, radii.y, 24), 0.03, net)
	_line(canvas, size, Vector2(0.06, 0.8), Vector2(0.92, 0.8), 0.045, net.darkened(0.25))
	for x: float in [0.09, 0.89]:
		_arc(canvas, size, Vector2(x, 0.86), 0.04, PI, TAU + 0.6, 0.03, Color(0.8, 0.82, 0.85))


## Marty's Body Shop: a dented red Chefty panel, a wrench across it, and a twinkle
## where the dent used to be.
static func draw_body_repair(canvas: CanvasItem, size: float, _recipe: Dictionary) -> void:
	var panel := PackedVector2Array([Vector2(0.12, 0.3), Vector2(0.82, 0.24), Vector2(0.86, 0.78), Vector2(0.55, 0.8), Vector2(0.47, 0.7), Vector2(0.4, 0.82), Vector2(0.14, 0.84)])
	_inked(canvas, _xf(panel, size), CHEFTY_RED, size)
	_line(canvas, size, Vector2(0.2, 0.42), Vector2(0.76, 0.37), 0.025, CHEFTY_RED.lightened(0.35))
	_line(canvas, size, Vector2(0.47, 0.7), Vector2(0.44, 0.6), 0.02, CHEFTY_RED.darkened(0.4))
	var steel := Color(0.78, 0.8, 0.84)
	var at := Vector2(0.5, 0.5)
	var angle := -0.75
	var handle := _rrect_pts(Rect2(-0.04, -0.06, 0.08, 0.42), 0.04)
	var head := _union(_ellipse_pts(Vector2(0.0, -0.18), 0.12, 0.12), _rrect_pts(Rect2(-0.045, -0.15, 0.09, 0.2), 0.02))
	_inked(canvas, _xf(_union(head, handle), size, at, 1.0, angle), steel, size)
	_fill(canvas, _xf(_rect_pts(Rect2(-0.035, -0.32, 0.07, 0.12)), size, at, 1.0, angle), CHEFTY_RED)
	_sparkle(canvas, size, Vector2(0.78, 0.2), 0.09, GOLD)

# ---- keycaps and mouse glyphs

## A paper keycap with a darker lip and a bold ink label ("label"), or an arrow
## or backspace "glyph". A "wide" cap is twice as wide as tall.
static func draw_key(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var width := 2.0 if bool(recipe.get("wide", false)) else 1.0
	_fill(canvas, _xf(_rrect_pts(Rect2(0.06, 0.08, width - 0.12, 0.82), 0.16), size), PAPER.darkened(0.34))
	_fill_gradient(canvas, _xf(_rrect_pts(Rect2(0.1, 0.1, width - 0.2, 0.66), 0.13), size), PAPER.lightened(0.5), PAPER)
	var center := Vector2(width * 0.5, 0.43)
	var glyph := str(recipe.get("glyph", ""))
	if glyph == "backspace":
		var shape := PackedVector2Array([Vector2(-0.3, 0.0), Vector2(-0.14, -0.16), Vector2(0.28, -0.16), Vector2(0.28, 0.16), Vector2(-0.14, 0.16)])
		_stroke(canvas, size, _closed(_xf(shape, 1.0, center)), 0.05, INK)
		_line(canvas, size, center + Vector2(0.0, -0.07), center + Vector2(0.14, 0.07), 0.045, INK)
		_line(canvas, size, center + Vector2(0.14, -0.07), center + Vector2(0.0, 0.07), 0.045, INK)
	elif glyph != "":
		var turn: float = {"up": 0.0, "right": PI * 0.5, "down": PI, "left": -PI * 0.5}.get(glyph, 0.0)
		_fill(canvas, _xf(PackedVector2Array([Vector2(0.0, -0.17), Vector2(0.16, 0.11), Vector2(-0.16, 0.11)]), size, center, 1.0, turn), INK)
	else:
		var label := str(recipe.get("label", ""))
		var em := 0.5 if label.length() == 1 else 0.4
		_text(canvas, size, center, label, em, INK, width - 0.36)


## A mouse with the button in use lit orange ("mouse": left, right, middle, 4, 5,
## wheel_up, wheel_down).
static func draw_mouse(canvas: CanvasItem, size: float, recipe: Dictionary) -> void:
	var mode := str(recipe.get("mouse", "left"))
	for index: int in 2:
		var lit := (mode == "5" and index == 0) or (mode == "4" and index == 1)
		_inked(canvas, _xf(_rrect_pts(Rect2(0.17, 0.44 + 0.15 * float(index), 0.13, 0.11), 0.03), size), ORANGE if lit else PAPER.darkened(0.2), size)
	_fill(canvas, _xf(_rrect_pts(Rect2(0.25, 0.07, 0.5, 0.85), 0.25, 10), size), PAPER.darkened(0.34))
	var face := _rrect_pts(Rect2(0.27, 0.08, 0.46, 0.8), 0.23, 10)
	_fill_gradient(canvas, _xf(face, size), PAPER.lightened(0.5), PAPER)
	if mode == "left" or mode == "right":
		var half := Rect2(0.2, 0.0, 0.3, 0.4) if mode == "left" else Rect2(0.5, 0.0, 0.3, 0.4)
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(face, _rect_pts(half)):
			_fill(canvas, _xf(piece, size), ORANGE)
	_line(canvas, size, Vector2(0.5, 0.1), Vector2(0.5, 0.4), 0.025, INK)
	_line(canvas, size, Vector2(0.28, 0.4), Vector2(0.72, 0.4), 0.025, INK)
	var wheel_lit := mode in ["middle", "wheel_up", "wheel_down"]
	_inked(canvas, _xf(_rrect_pts(Rect2(0.455, 0.15, 0.09, 0.19), 0.045), size), ORANGE if wheel_lit else Color(0.55, 0.55, 0.58), size, INK, 0.015)
	if mode == "wheel_up" or mode == "wheel_down":
		var turn := 0.0 if mode == "wheel_up" else PI
		_inked(canvas, _xf(PackedVector2Array([Vector2(0.0, -0.11), Vector2(0.11, 0.06), Vector2(-0.11, 0.06)]), size, Vector2(0.5, 0.63), 1.0, turn), ORANGE, size, INK, 0.015)
	elif mode == "4" or mode == "5":
		_text(canvas, size, Vector2(0.5, 0.63), mode, 0.28, INK)
