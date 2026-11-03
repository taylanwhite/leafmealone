extends RefCounted

## Authority: local, cosmetic. Where Homie Depot shows what you wear and what
## Chefty wears (docs/GAME.md "Cosmetics"; gap-specs shops chunk 7), built by
## levels/dressing/store_dressing.gd in the store zone:
##   In the fitting nook south of the orange entrance block: on the store's front
##   wall (Constants.WARDROBE_WALL_X) a pegboard hat rack (every Homie Depot hat
##   on a display head, three rows) and a shirt cubby (the eight dyes and the
##   hi-vis vest, folded); on the block's side (Constants.MIRROR_AT) a
##   full-length mirror (props/mirror.gd), so you try a hat on in front of it.
##   By Chefty's loading bay: the paint counter (Constants.PAINT_COUNTER_AT),
##   paint cans on the counter and decal sample cards on a low riser behind them,
##   so you choose looking over them at the truck.
## The goods are props/shelf_stock.gd slots (group "wardrobe_stock"): price tags,
## OWNED / WEARING / ON CHEFTY, the tarp over a rank's crown, and E opens the
## catalog on the thing you look at. Shops._near_site counts all three as places
## you can buy from (SHOP_SITES homie_depot "spots"). Every piece is solid.

const _LowPoly = preload("res://props/low_poly.gd")
const _ShelfStock = preload("res://props/shelf_stock.gd")
const _Mirror = preload("res://props/mirror.gd")
const _Strings = preload("res://ui/strings.gd")
const ORANGE := Color(0.95, 0.5, 0.15)
const PEGBOARD := Color(0.78, 0.66, 0.48)
const WOOD := Color(0.5, 0.36, 0.24)
const DARK := Color(0.16, 0.17, 0.2)
const COUNTER := Color(0.62, 0.44, 0.28)
## The rack's three rows of hats (slot floor heights) and three columns (z
## offsets from Constants.HAT_RACK_Z); the bottom row only uses its middle.
const HAT_ROWS: Array[float] = [1.74, 1.13, 0.52]
const HAT_COLUMNS: Array[float] = [-0.6, 0.0, 0.6]
const HAT_SLOT := Vector3(0.46, 0.56, 0.56)
## The tags' letters here (m per pixel), smaller than the garden shelves'.
const TAG_PIXEL: float = 0.0022
## The cubby: three levels, three columns.
const CUBBY_ROWS: Array[float] = [1.42, 0.96, 0.5]
const CUBBY_COLUMNS: Array[float] = [-0.4, 0.0, 0.4]
const CUBBY_SLOT := Vector3(0.42, 0.34, 0.38)
## The cubby stands this far out from the wall (m): in front of a display
## window, clear of its sill (props/low_poly.gd window: 0.22 deep).
const CUBBY_OFF_WALL: float = 0.27
## The paint counter: five columns, the cans along the counter's front (y 0.95,
## z CANS_Z), the decal cards on a low riser along its back (y RISER_TOP, z RISER_Z).
const COUNTER_COLUMNS: Array[float] = [-1.0, -0.5, 0.0, 0.5, 1.0]
const COUNTER_TOP: float = 0.95
const RISER_TOP: float = 1.13
const CANS_Z: float = -0.12
const RISER_Z: float = 0.18
## The name board over the counter (its middle, m): high, so you see Chefty under it.
const COUNTER_SIGN_Y: float = 2.25
const COUNTER_SLOT := Vector3(0.42, 0.42, 0.46)


static func build(root: Node3D) -> void:
	_wall(root)
	_paint_counter(root)


## The hat rack, the mirror and the shirt cubby, and their stock.
static func _wall(root: Node3D) -> void:
	var face := Constants.WARDROBE_WALL_X
	var aisle := -PI * 0.5
	var slots: Array[Dictionary] = []
	# The pegboard: a tan board in an orange frame, a header, and a little shelf under each hat.
	var rack_z := Constants.HAT_RACK_Z
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.04, 1.85, 1.9), Vector3(face + 0.02, 1.32, rack_z), PEGBOARD, true), "planks")
	for edge: float in [-0.97, 0.97]:
		_LowPoly.paint(_LowPoly.box(root, Vector3(0.07, 1.95, 0.06), Vector3(face + 0.035, 1.3, rack_z + edge), ORANGE), "metal")
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.07, 0.3, 2.0), Vector3(face + 0.035, 2.38, rack_z), ORANGE), "metal")
	_LowPoly.text_sign(root, str(_Strings.SHOP_UI["sign_workwear"]), Vector3(face + 0.08, 2.38, rack_z), 64, Color.WHITE, PI * 0.5)
	for row: int in HAT_ROWS.size():
		for column: int in HAT_COLUMNS.size():
			if row == HAT_ROWS.size() - 1 and column != 1:
				continue
			var at := Vector3(face + 0.04 + HAT_SLOT.x * 0.5, HAT_ROWS[row], rack_z + HAT_COLUMNS[column])
			_LowPoly.paint(_LowPoly.box(root, Vector3(HAT_SLOT.x, 0.03, 0.42), at - Vector3(0.0, 0.015, 0.0), WOOD), "planks")
			slots.append({"at": at, "size": HAT_SLOT, "face": aisle})
	# The cubby: a box of nine holes on legs, standing in front of the display
	# window (its sill came through the holes when it stood against the wall).
	var cubby_z := Constants.SHIRT_CUBBY_Z
	var depth := CUBBY_SLOT.x
	var back := face + CUBBY_OFF_WALL
	var cubby_x := back + 0.02 + depth * 0.5
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.03, 1.5, 1.28), Vector3(back + 0.015, 1.18, cubby_z), WOOD.darkened(0.2), true), "planks")
	for level: float in [0.48, 0.94, 1.4, 1.86]:
		_LowPoly.paint(_LowPoly.box(root, Vector3(depth, 0.04, 1.28), Vector3(cubby_x, level, cubby_z), WOOD, true), "planks")
	for edge: float in [-0.62, -0.2, 0.2, 0.62]:
		_LowPoly.paint(_LowPoly.box(root, Vector3(depth, 1.42, 0.04), Vector3(cubby_x, 1.17, cubby_z + edge), WOOD, true), "planks")
	# The cubby's legs down to the walk.
	for edge: float in [-0.6, 0.6]:
		_LowPoly.paint(_LowPoly.box(root, Vector3(depth, 0.46, 0.05), Vector3(cubby_x, 0.23, cubby_z + edge), WOOD.darkened(0.2), true), "planks")
	for row: int in CUBBY_ROWS.size():
		for column: int in CUBBY_COLUMNS.size():
			slots.append({"at": Vector3(cubby_x, CUBBY_ROWS[row], cubby_z + CUBBY_COLUMNS[column]), "size": CUBBY_SLOT, "face": aisle})
	var stock := _ShelfStock.new()
	stock.name = "WorkwearStock"
	stock.set("shop_id", "homie_depot")
	stock.set("tabs", ["workwear"] as Array[String])
	stock.set("slots", slots)
	stock.set("stock_group", "wardrobe_stock")
	stock.set("tag_pixel", TAG_PIXEL)
	root.add_child(stock)
	# The mirror on the entrance block's south side, in a dark frame (the block is
	# orange already), facing south down the walk: the rack is at your elbow.
	var glass_middle := Vector3(Constants.MIRROR_AT.x, Constants.MIRROR_BOTTOM + Constants.MIRROR_SIZE.y * 0.5, Constants.MIRROR_AT.z - 0.03)
	var frame := Constants.MIRROR_SIZE + Vector2(0.12, 0.12)
	_LowPoly.paint(_LowPoly.box(root, Vector3(frame.x, frame.y, 0.04), glass_middle + Vector3(0.0, 0.0, 0.012), DARK, true), "metal")
	var mirror := _Mirror.new()
	mirror.name = "Mirror"
	root.add_child(mirror)
	mirror.position = glass_middle - Vector3(0.0, 0.0, 0.01)
	# The glass faces +Z; turned round to face -Z, down the walk.
	mirror.rotation.y = PI


## The paint counter by the loading bay: a counter with a riser shelf over its
## back edge, the cans and cards on them, and the name over it.
static func _paint_counter(root: Node3D) -> void:
	var at := Constants.PAINT_COUNTER_AT
	var width := 2.6
	_LowPoly.paint(_LowPoly.box(root, Vector3(width, COUNTER_TOP, 0.62), at + Vector3(0.0, COUNTER_TOP * 0.5, 0.0), COUNTER, true), "planks")
	_LowPoly.paint(_LowPoly.box(root, Vector3(width + 0.06, 0.04, 0.68), at + Vector3(0.0, COUNTER_TOP - 0.02, 0.0), ORANGE.darkened(0.1)), "metal")
	# Two posts up the back edge carry the name board, high, and a low riser
	# shelf behind the cans (W8: at 1.47 m its cards hid the truck you paint).
	for side: float in [-1.0, 1.0]:
		_LowPoly.paint(_LowPoly.cylinder(root, 0.03, COUNTER_SIGN_Y - COUNTER_TOP, at + Vector3(side * (width * 0.5 - 0.06), (COUNTER_SIGN_Y + COUNTER_TOP) * 0.5, RISER_Z + 0.09), DARK, false, 8), "metal")
	_LowPoly.paint(_LowPoly.box(root, Vector3(width, RISER_TOP - COUNTER_TOP, 0.24), at + Vector3(0.0, (COUNTER_TOP + RISER_TOP) * 0.5, RISER_Z), WOOD, true), "planks")
	_LowPoly.paint(_LowPoly.box(root, Vector3(width, 0.32, 0.05), at + Vector3(0.0, COUNTER_SIGN_Y, RISER_Z + 0.09), ORANGE), "metal")
	_LowPoly.text_sign(root, str(_Strings.SHOP_UI["sign_paint_counter"]), at + Vector3(0.0, COUNTER_SIGN_Y, RISER_Z + 0.06), 56, Color.WHITE, PI)
	var slots: Array[Dictionary] = []
	for level: float in [COUNTER_TOP, RISER_TOP]:
		for column: float in COUNTER_COLUMNS:
			slots.append({"at": at + Vector3(column, level, CANS_Z if level == COUNTER_TOP else RISER_Z), "size": COUNTER_SLOT, "face": 0.0})
	var stock := _ShelfStock.new()
	stock.name = "PaintStock"
	stock.set("shop_id", "homie_depot")
	stock.set("tabs", ["truck"] as Array[String])
	stock.set("slots", slots)
	stock.set("stock_group", "wardrobe_stock")
	stock.set("tag_pixel", TAG_PIXEL)
	# Until Bag Hauler III the whole counter waits under tarps, with one sign.
	stock.set("lock_tag_at", at + Vector3(0.0, COUNTER_TOP * 0.55, -0.33))
	stock.set("lock_tag_yaw", PI)
	root.add_child(stock)
