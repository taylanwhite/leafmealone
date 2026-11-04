extends RefCounted

## Authority: local, cosmetic (the tool endcaps' stock is props/shelf_stock.gd,
## which draws Shops' replicated state). Homie Depot's walk-in lobby (art chunk 8;
## docs/GAME.md "Homie Depot, inside and out"): you walk through sliding glass
## doors into a lit room 10 m deep under a ceiling of glowing panels, a polished
## tile floor, orange racking down both walls with the aisle signs hung over
## them, the tool endcaps in front of the racking (each tool on its plinth with
## Shops' price tag; E on one opens the catalog on it, and you can buy right
## there), the PRO DESK facing the doors, a paint-can pyramid in the corner,
## Marty as Homie of the Month on the left wall, the RETURNS window shuttered on
## the right, and at the back the yellow forklift and a shrink-wrapped pallet
## wall taped off "AISLE CLOSED FOR RESTOCK SINCE 2019". That wall is where the
## store pad ends, so the end reads as a real place and not an invisible wall;
## it has its own collider, so it holds in the connected town too (no pad wall
## there).
##
## In StoreZone space: the doors at x DOOR_X across z DOOR_Z +- ART_DOOR_WIDTH/2,
## the room x ROOM.x .. DOOR_X, z ROOM.y .. ROOM.end.y, the walk-in lane down its
## middle kept clear for four abreast (net/dev/art_test.gd A14 sweeps it).
## Nothing here is networked. The shell around it (walls, roof, the orange
## entrance block and the sidelights) is levels/dressing/store_dressing.gd's.

const _LowPoly = preload("res://props/low_poly.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")
const _StoreProps = preload("res://props/store_props.gd")
const _ShelfStock = preload("res://props/shelf_stock.gd")
const _SlidingDoors = preload("res://props/sliding_doors.gd")
const _Strings = preload("res://ui/strings.gd")

## The room's floor plan (x, z, width, depth) from the back wall to the doors.
const ROOM := Rect2(-20.0, -7.0, 10.0, 10.0)
const DOOR_X: float = -10.08
const DOOR_Z: float = -2.0
const CEILING: float = 4.5
## The back wall's front face (the restock pallets stand on the pad's edge).
const BACK_FACE: float = -18.8
## The racking down both walls: from x RACK_FROM to RACK_TO, a meter deep.
const RACK_FROM: float = -17.2
const RACK_TO: float = -12.0
const RACK_LEFT_Z: float = -6.5
const RACK_RIGHT_Z: float = 2.5
## The tool endcaps in front of the racking: x centers, and each side's z.
const ENDCAPS_LEFT: Array[float] = [-16.6, -15.3, -14.0, -12.7]
const ENDCAPS_RIGHT: Array[float] = [-16.6, -15.3, -14.0]
const ENDCAP_LEFT_Z: float = -5.65
const ENDCAP_RIGHT_Z: float = 1.65
## A ShelfSlot on an endcap: depth across, height, width along (m).
const SLOT_SIZE := Vector3(0.62, 1.1, 1.0)
## p2-kit: the rake bin inside the doors, right of the mat, clear of the lane.
const RAKE_BIN_AT := Vector3(-11.1, 0.02, 1.85)
const RAKE_BIN_SIZE := Vector3(0.6, 1.4, 0.6)
const RAKE_BIN_TAG_PIXEL: float = 0.006
## The walk-in lane between the endcaps, from the doors to the back fixtures.
const LANE := Rect2(-17.4, -5.2, 7.4, 6.4)
## Where the shell's front wall stands (store_dressing.gd FRONT_X); the room
## past it, to the doors, is the orange entrance block.
const SHELL_FRONT_X: float = -12.0
const WALL_COLOR := Color(0.84, 0.84, 0.81)
const FLOOR_COLOR := Color(0.9, 0.88, 0.83)
const CEILING_COLOR := Color(0.93, 0.93, 0.9)
const LIGHT_COLOR := Color(1.0, 0.96, 0.88)
const ORANGE := Color(0.95, 0.5, 0.15)
const SIGN_FACE := Color(0.98, 0.97, 0.93)
const DARK := Color(0.16, 0.17, 0.2)


static func dress(root: Node3D, _zone: Node3D) -> void:
	var lobby := Node3D.new()
	lobby.name = "Lobby"
	root.add_child(lobby)
	_floor_and_ceiling(lobby)
	_racking(lobby)
	_endcaps(lobby)
	_back(lobby)
	_signs(lobby)
	_walls(lobby)
	var doors: Node3D = _SlidingDoors.new()
	doors.name = "SlidingDoors"
	doors.call("setup", Constants.ART_DOOR_WIDTH, Constants.ART_DOOR_HEIGHT)
	lobby.add_child(doors)
	doors.position = Vector3(DOOR_X, 0.0, DOOR_Z)


# ---------------------------------------------------------------- the room

static func _floor_and_ceiling(lobby: Node3D) -> void:
	# The tiles stop just under the doors, where the apron outside starts.
	var floor_to := DOOR_X + 0.02
	var tiles := _LowPoly.box(lobby, Vector3(floor_to - ROOM.position.x, 0.04, ROOM.size.y), Vector3((floor_to + ROOM.position.x) * 0.5, 0.0, ROOM.get_center().y), FLOOR_COLOR)
	tiles.name = "TileFloor"
	_LowPoly.paint(tiles, "tile_floor", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
	# A rubber mat inside the doors.
	_LowPoly.paint(_LowPoly.box(lobby, Vector3(1.6, 0.012, Constants.ART_DOOR_WIDTH + 0.4), Vector3(-11.0, 0.026, DOOR_Z), Color(0.2, 0.2, 0.22)), "fabric", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
	# The walls inside, a pale gray over the shell's metal, with an orange band.
	var wall_x := Vector2(ROOM.position.x, SHELL_FRONT_X)
	for z: float in [ROOM.position.y + 0.05, ROOM.end.y - 0.05]:
		_LowPoly.paint(_LowPoly.box(lobby, Vector3(wall_x.y - wall_x.x, CEILING, 0.02), Vector3((wall_x.x + wall_x.y) * 0.5, CEILING * 0.5, z), WALL_COLOR), "plain", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
		_LowPoly.paint(_LowPoly.box(lobby, Vector3(wall_x.y - wall_x.x, 0.3, 0.03), Vector3((wall_x.x + wall_x.y) * 0.5, CEILING - 0.45, z), ORANGE), "plain", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
	_LowPoly.paint(_LowPoly.box(lobby, Vector3(0.02, CEILING, ROOM.size.y), Vector3(ROOM.position.x + 0.05, CEILING * 0.5, ROOM.get_center().y), WALL_COLOR), "plain", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
	var ceiling := _LowPoly.box(lobby, Vector3(DOOR_X - 0.2 - ROOM.position.x, 0.2, ROOM.size.y), Vector3((DOOR_X - 0.2 + ROOM.position.x) * 0.5, CEILING + 0.1, ROOM.get_center().y), CEILING_COLOR)
	ceiling.name = "Ceiling"
	ceiling.add_to_group("store_roof")
	_LowPoly.paint(ceiling, "plain", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
	(ceiling as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Glowing ceiling panels in two rows, and two lights that do the real work.
	for x: float in [-17.4, -14.6, -11.8]:
		for z: float in [-4.4, 0.4]:
			var panel := _LowPoly.glow(lobby, Vector3(1.4, 0.03, 1.8), Vector3(x, CEILING - 0.01, z), LIGHT_COLOR, Constants.ART_LOBBY_PANEL_ENERGY)
			(panel as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			panel.add_to_group("store_roof")
	for x: float in [-16.6, -12.6]:
		var light := OmniLight3D.new()
		light.name = "LobbyLight"
		light.light_color = LIGHT_COLOR
		light.light_energy = Constants.ART_LOBBY_LIGHT_ENERGY
		light.omni_range = Constants.ART_LOBBY_LIGHT_RANGE
		light.shadow_enabled = false
		lobby.add_child(light)
		light.position = Vector3(x, CEILING - 0.4, DOOR_Z)


## A catalog prop as a plain mesh with no snow (it's under a roof), at xform.
static func _indoor(parent: Node3D, kind: String, xform: Transform3D, color: Color = Color.WHITE) -> MeshInstance3D:
	var mesh := _PropCatalog.mesh(kind, color)
	var options := _PropCatalog.options(kind)
	options["snow"] = 0.0
	var view := _Stylized.instance(mesh, options)
	view.name = kind.to_pascal_case()
	view.set_meta("prop_kind", kind)
	view.transform = xform
	parent.add_child(view)
	return view


## A solid box (a collider, no mesh) of size centered at center.
static func _solid(parent: Node3D, name: String, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	parent.add_child(body)
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.add_to_group("store_art_solid")
	return body


static func _racking(lobby: Node3D) -> void:
	var bays := int(round((RACK_TO - RACK_FROM) / _StoreProps.RACK_SIZE.x))
	for index: int in bays:
		var x := RACK_FROM + _StoreProps.RACK_SIZE.x * (float(index) + 0.5)
		# The left run faces the room (+Z), the right run faces it (-Z).
		_indoor(lobby, "rack_bay", Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0.0, RACK_LEFT_Z)))
		_indoor(lobby, "rack_bay", Transform3D(Basis.IDENTITY, Vector3(x, 0.0, RACK_RIGHT_Z)))
	var length := RACK_TO - RACK_FROM
	var middle := (RACK_FROM + RACK_TO) * 0.5
	_solid(lobby, "RackLeft", Vector3(middle, _StoreProps.RACK_SIZE.y * 0.5, RACK_LEFT_Z), Vector3(length, _StoreProps.RACK_SIZE.y, _StoreProps.RACK_SIZE.z))
	_solid(lobby, "RackRight", Vector3(middle, _StoreProps.RACK_SIZE.y * 0.5, RACK_RIGHT_Z), Vector3(length, _StoreProps.RACK_SIZE.y, _StoreProps.RACK_SIZE.z))


## The tool endcaps, each with a ShelfSlot marker on its plinth (group
## "shop_shelf_slot"; gap-specs/critic.md C28): shops' props/shelf_stock.gd
## fills them with the tools (one each, Catalog order) and their price tags,
## and Shops sells from the lobby (Constants.SHOP_SITES "lobby").
static func _endcaps(lobby: Node3D) -> void:
	var slots: Array[Dictionary] = []
	var index := 0
	var rows: Array = [[ENDCAPS_LEFT, ENDCAP_LEFT_Z, PI], [ENDCAPS_RIGHT, ENDCAP_RIGHT_Z, 0.0]]
	for row: Array in rows:
		var face := float(row[2])
		for x: float in row[0]:
			var at := Vector3(x, 0.0, float(row[1]))
			_indoor(lobby, "endcap", Transform3D(Basis(Vector3.UP, face), at))
			_solid(lobby, "Endcap%d" % index, at + Vector3(0.0, 1.15, 0.0), Vector3(_StoreProps.ENDCAP_SIZE.x, 2.3, _StoreProps.ENDCAP_SIZE.z))
			var marker := Marker3D.new()
			marker.name = "ShelfSlot%d" % index
			marker.position = Vector3(x, _StoreProps.ENDCAP_TOP + 0.02, float(row[1]))
			marker.set_meta("shop", "homie_depot")
			marker.set_meta("tab", "tools")
			marker.set_meta("size", SLOT_SIZE)
			marker.set_meta("face", face)
			marker.add_to_group("shop_shelf_slot")
			lobby.add_child(marker)
			slots.append({"at": marker.position, "size": SLOT_SIZE, "face": face})
			index += 1
	# p2-kit: the rake bin, just inside the doors on the right ("Rakes are by the
	# door", Marty's day-one text): the first thing a new crew can buy, and the
	# first thing it walks past. Its own stock, one slot, the plain rake.
	var bin := _ShelfStock.new()
	bin.name = "RakeBin"
	bin.set("shop_id", "homie_depot")
	bin.set("tabs", ["tools"] as Array[String])
	bin.set("items", PackedStringArray(["rake"]))
	bin.set("slots", [{"at": RAKE_BIN_AT, "size": RAKE_BIN_SIZE, "face": 0.0, "bin": true, "tag_y": RAKE_BIN_SIZE.y * 0.45}] as Array[Dictionary])
	# Its own group: "lobby_stock" is the endcaps' (art_test A14 reads that one).
	bin.set("stock_group", "rake_bin")
	# A bigger tag than the endcaps': the price a new crew reads first.
	bin.set("tag_pixel", RAKE_BIN_TAG_PIXEL)
	lobby.add_child(bin)
	var stock := _ShelfStock.new()
	stock.name = "LobbyStock"
	stock.set("shop_id", "homie_depot")
	stock.set("tabs", ["tools"] as Array[String])
	stock.set("slots", slots)
	# "shelf_stock" is the garden center's shelves (tests and the probe read that
	# one); the lobby's endcaps are their own group.
	stock.ready.connect(func() -> void:
		stock.remove_from_group("shelf_stock")
		stock.add_to_group("lobby_stock"), CONNECT_ONE_SHOT)
	lobby.add_child(stock)


## The back: the restock wall across the pad's edge, the forklift parked in the
## left corner with its forks up, the PRO DESK facing the doors, the paint
## pyramid in the right corner, and the wet-floor sign by the doors.
static func _back(lobby: Node3D) -> void:
	var depth := _StoreProps.RESTOCK_SIZE.z
	var wall_x := BACK_FACE - depth * 0.5
	var units := 4
	for index: int in units:
		var z := ROOM.position.y + 1.25 + float(index) * 2.5
		_indoor(lobby, "restock_wall", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(wall_x, 0.0, z)))
	_solid(lobby, "RestockWall", Vector3(wall_x, 2.0, ROOM.get_center().y), Vector3(depth, 4.0, ROOM.size.y))
	_words(lobby, _sign("restock"), Vector3(BACK_FACE + 0.06, _StoreProps.RESTOCK_BAND, DOOR_Z), PI * 0.5, 32, 0.0042, DARK, 4.6)
	_indoor(lobby, "forklift", Transform3D(Basis.IDENTITY, Vector3(-18.15, 0.0, -5.15)))
	_solid(lobby, "Forklift", Vector3(-18.15, 1.1, -5.1), Vector3(1.15, 2.2, 3.1))
	_indoor(lobby, "pro_desk", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-18.0, 0.0, -2.0)))
	_solid(lobby, "ProDesk", Vector3(-18.0, 0.55, -2.0), Vector3(0.82, 1.1, 2.12))
	_indoor(lobby, "paint_pyramid", Transform3D(Basis(Vector3.UP, 0.3), Vector3(-18.1, 0.0, 1.55)))
	_solid(lobby, "PaintPyramid", Vector3(-18.1, 0.5, 1.55), Vector3(1.3, 1.0, 1.3))
	# By the doors, in the empty endcap's spot, where it's always wet.
	var wet := Node3D.new()
	wet.name = "WetFloor"
	lobby.add_child(wet)
	wet.transform = Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.35), Vector3(-12.5, 0.02, 1.35))
	_indoor(wet, "wet_floor_sign", Transform3D.IDENTITY)
	# The words on the front panel's outer face, leaning with it.
	var lean := _StoreProps.wet_panel(-1.0)
	var words := _words(wet, _sign("wet_floor"), lean * Vector3(0.0, 0.3, -0.013) + Vector3(0.0, 0.0, -_StoreProps.WET_SPREAD), 0.0, 20, 0.0024, DARK, 0.27)
	words.basis = lean * Basis(Vector3.UP, PI)


## The hanging aisle signs over the racking (facing the room), and the PRO DESK's.
static func _signs(lobby: Node3D) -> void:
	var aisles: Array = [["aisle_1", -15.9, RACK_LEFT_Z + 0.9, 0.0], ["aisle_2", -13.3, RACK_LEFT_Z + 0.9, 0.0], ["aisle_5", -15.9, RACK_RIGHT_Z - 0.9, PI], ["aisle_7", -13.3, RACK_RIGHT_Z - 0.9, PI]]
	for aisle: Array in aisles:
		_hanging(lobby, _sign(str(aisle[0])), Vector3(float(aisle[1]), CEILING - 0.55, float(aisle[2])), float(aisle[3]), Vector2(2.1, 0.5))
	_hanging(lobby, _sign("pro_desk"), Vector3(-18.2, 2.9, DOOR_Z), -PI * 0.5 + PI, Vector2(2.4, 0.62))


## Marty on the vestibule's left wall, the RETURNS window on its right.
static func _walls(lobby: Node3D) -> void:
	_homie_of_the_month(lobby, Vector3(-11.0, 1.55, ROOM.position.y + 0.42))
	_returns_window(lobby, Vector3(-11.0, 0.0, ROOM.end.y - 0.42))


## A sign board hung from the ceiling on two rods: orange with a white face,
## words on the side facing yaw (0 reads from +Z).
static func _hanging(lobby: Node3D, words: String, at: Vector3, yaw: float, size: Vector2) -> void:
	var holder := Node3D.new()
	holder.name = "HangingSign"
	lobby.add_child(holder)
	holder.position = at
	holder.rotation.y = yaw
	var kit := _MeshKit.new()
	kit.box(Vector3.ZERO, Vector3(size.x + 0.08, size.y + 0.08, 0.05), ORANGE)
	kit.box(Vector3(0.0, 0.0, 0.03), Vector3(size.x, size.y, 0.012), SIGN_FACE)
	kit.box(Vector3(0.0, 0.0, -0.03), Vector3(size.x, size.y, 0.012), ORANGE.lightened(0.1))
	for x: float in [-size.x * 0.4, size.x * 0.4]:
		kit.box(Vector3(x, (CEILING - at.y) * 0.5 + size.y * 0.25, 0.0), Vector3(0.025, CEILING - at.y - size.y * 0.5, 0.025), DARK)
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.8, "specular": 0.1, "snow": 0.0})
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(view)
	_words(holder, words, Vector3(0.0, 0.0, 0.04), 0.0, 40, 0.0042, DARK, size.x - 0.12)


## The Homie of the Month board: a cork board with Marty's photo (his cap, his
## orange apron, the grin) and the plaque. Hung on the wall at z, facing +Z.
static func _homie_of_the_month(lobby: Node3D, at: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "HomieOfTheMonth"
	lobby.add_child(holder)
	holder.position = at
	var kit := _MeshKit.new()
	kit.box(Vector3(0.0, 0.0, 0.0), Vector3(1.3, 1.25, 0.04), Color(0.5, 0.34, 0.2))
	kit.box(Vector3(0.0, 0.0, 0.025), Vector3(1.2, 1.15, 0.01), Color(0.75, 0.6, 0.42))
	# The photo, its white border, and Marty in it.
	kit.box(Vector3(0.0, 0.17, 0.035), Vector3(0.62, 0.66, 0.01), Color(0.97, 0.97, 0.95))
	kit.box(Vector3(0.0, 0.18, 0.042), Vector3(0.54, 0.56, 0.006), Color(0.55, 0.7, 0.8))
	var skin := Color(0.72, 0.52, 0.36)
	kit.box(Vector3(0.0, -0.02, 0.046), Vector3(0.44, 0.17, 0.004), Color(0.93, 0.47, 0.13))
	kit.blob(Vector3(0.0, 0.2, 0.05), Vector3(0.14, 0.16, 0.012), skin, {"detail": 1, "lumps": 0.0, "jitter": 0.0, "flat": false})
	kit.box(Vector3(0.0, 0.335, 0.056), Vector3(0.3, 0.07, 0.006), Color(0.74, 0.38, 0.1))
	kit.box(Vector3(0.06, 0.31, 0.058), Vector3(0.22, 0.025, 0.004), Color(0.6, 0.3, 0.08))
	for x: float in [-0.05, 0.05]:
		kit.box(Vector3(x, 0.23, 0.062), Vector3(0.025, 0.03, 0.004), DARK)
	kit.box(Vector3(0.0, 0.135, 0.062), Vector3(0.14, 0.035, 0.004), Color(0.98, 0.98, 0.96))
	kit.box(Vector3(0.0, 0.165, 0.063), Vector3(0.12, 0.02, 0.004), Color(0.32, 0.22, 0.14))
	# Thumbtacks in the corners.
	for x: float in [-0.29, 0.29]:
		for y: float in [-0.14, 0.48]:
			kit.box(Vector3(x, y, 0.045), Vector3(0.03, 0.03, 0.012), Color(0.85, 0.15, 0.12))
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.8, "specular": 0.1, "snow": 0.0})
	holder.add_child(view)
	_words(holder, _sign("homie_month"), Vector3(0.0, -0.36, 0.05), 0.0, 36, 0.0034, DARK, 1.1)


## The RETURNS window in the wall at z, facing -Z: a frame, its shutter pulled
## down (padlocked), and the sign over it.
static func _returns_window(lobby: Node3D, at: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "ReturnsWindow"
	lobby.add_child(holder)
	holder.position = at
	holder.rotation.y = PI
	var kit := _MeshKit.new()
	kit.box(Vector3(0.0, 1.45, 0.0), Vector3(1.3, 1.1, 0.06), DARK)
	for index: int in 9:
		kit.box(Vector3(0.0, 1.0 + float(index) * 0.11, 0.035), Vector3(1.14, 0.09, 0.02), Color(0.72, 0.74, 0.76).darkened(0.04 * float(index % 2)))
	kit.box(Vector3(0.0, 0.92, 0.12), Vector3(1.4, 0.06, 0.26), Color(0.86, 0.84, 0.78))
	kit.box(Vector3(0.0, 0.46, 0.04), Vector3(1.3, 0.92, 0.08), ORANGE.darkened(0.1))
	kit.box(Vector3(0.0, 1.02, 0.06), Vector3(0.08, 0.1, 0.03), Color(0.85, 0.7, 0.2))
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.7, "specular": 0.2, "snow": 0.0})
	holder.add_child(view)
	_words(holder, _sign("returns"), Vector3(0.0, 2.25, 0.05), 0.0, 40, 0.0045, ORANGE, 1.3)


static func _sign(key: String) -> String:
	return str(_Strings.SIGNS.get(key, ""))


## A Label3D of words at, turned yaw (0 reads from +Z), wrapped to width (m).
static func _words(parent: Node3D, words: String, at: Vector3, yaw: float, font: int, pixel: float, color: Color, width: float) -> Label3D:
	var label := Label3D.new()
	label.name = "Words"
	label.text = words
	label.font_size = font
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.double_sided = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = width / pixel
	label.position = at
	label.rotation.y = yaw
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(label)
	return label
