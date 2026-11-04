extends Control

## Authority: local. The phone's Map app in the connected town (driving chunk K;
## docs/GAME.md "The phone's map"): Gutterford from above, north up, the way a
## phone's map app draws a place. Roads (Main Street a little wider and warmer),
## the lake, Homie Depot's lot with its mark, every yard slot on every street
## (the houses across the street faint), and over that what this peer knows:
##   - clients you work for are warm yards, a client with an open request
##     breathes orange, a yard TurfMasters poached is their green, and a street
##     your rank hasn't opened yet is faded;
##   - the job's pin at its curb, and the way there along the roads (TownMap.route)
##     from you, or from Chefty when you're in it, with the address and how far by
##     road along the bottom;
##   - your crewmates as dots in their shirts' colors, you as an arrow the way you
##     look, Chefty as a little red truck pointing the way it faces (anyone aboard
##     rides inside it; when it's you, it wears your ring).
## The NICE BOYS' van is never on it: you hear it and see it (gap-specs, W10).
## It opens framing you and the pin (the whole town with no job). The wheel
## zooms in on the pointer (yards wear their house numbers close in), a drag
## pans, a double click goes back to that first view; pointing at a yard puts its address (and its owner, if you
## know them) along the bottom. Everything it shows is state every peer already
## has (the town's houses and requests, the board's pick, the players' and
## Chefty's replicated poses), so it never sends anything.

const _Hoods = preload("res://net/town/neighborhoods.gd")
const _Strings = preload("res://ui/strings.gd")
const _Icons = preload("res://ui/icons.gd")

const LAND := Color(0.8, 0.87, 0.74)
const LAKE := Color(0.58, 0.76, 0.9)
const LAKE_EDGE := Color(0.45, 0.63, 0.8)
const LOT := Color(0.79, 0.79, 0.77)
const ROAD := Color(1.0, 1.0, 1.0)
const MAIN := Color(1.0, 0.94, 0.72)
const ROAD_EDGE := Color(0.66, 0.66, 0.63)
const YARD := Color(0.9, 0.94, 0.85)
const YARD_EDGE := Color(0.66, 0.74, 0.6)
const YARD_KNOWN := Color(1.0, 0.85, 0.58)
const YARD_POACHED := Color(0.36, 0.66, 0.4)
const HOUSE := Color(0.55, 0.5, 0.47)
const HOUSE_FAINT := Color(0.7, 0.75, 0.66)
const ORANGE := Color(0.93, 0.47, 0.13)
const ROUTE_CASING := Color(1.0, 1.0, 1.0, 0.95)
const YOU := Color(0.18, 0.45, 0.95)
const CHEFTY := Color(0.75, 0.22, 0.15)
const CHEFTY_CAB := Color(0.45, 0.12, 0.08)
const INK := Color(0.15, 0.15, 0.17)
const SOFT := Color(0.42, 0.44, 0.42)
const CAPTION_BACK := Color(1.0, 1.0, 1.0, 0.88)
## A locked street's yards and name are drawn at this alpha.
const LOCKED_ALPHA: float = 0.4
## Pixel sizes on the map (at any zoom): the narrowest a road is drawn, the
## dots, the arrow, Chefty, the pin, the labels and the caption strip.
const ROAD_MIN_PX: float = 2.6
const ROAD_EDGE_PX: float = 1.0
const DOT_PX: float = 5.0
const ARROW_PX: float = 8.5
const CHEFTY_PX := Vector2(5.5, 12.0)
const PIN_PX: float = 6.5
const PIN_RISE_PX: float = 11.0
const ROUTE_PX: float = 3.0
const LABEL_FONT: int = 10
const CAPTION_FONT: int = 13
const CAPTION_PX: float = 22.0
const STORE_ICON_PX: float = 13.0
## Homie Depot's mark sits on its building, at the back of the lot (world x, z).
const STORE_MARK := Vector3(-17.0, 0.0, -2.0)
## Zoomed in this far (px a meter), each yard wears its house number.
const NUMBERS_FROM_PX: float = 0.75
## Framing you and the pin, the map leaves this much room round them (px).
const FRAME_MARGIN_PX: float = 34.0
## The house on a yard, in yard space (x, z): at the back of the lot.
const HOUSE_RECT := Rect2(-7.0, -18.0, 14.0, 11.0)

## Zoom (1 is the whole town) and the world point (x, z) at the map's middle.
var _zoom: float = 1.0
var _center := Constants.PHONE_MAP_FRAME.get_center()
var _dragging: bool = false
## The yard under the pointer, or -1.
var _hover: int = -1
var _time: float = 0.0
## The way to the pin, worked out each frame it's shown.
var _route := PackedVector3Array()
var _route_meters: float = 0.0
var _model: Dictionary = {}
## Whether this showing has picked its first view yet (_frame_view), and whether
## the player has zoomed or panned since (then it stays put).
var _framed: bool = false
var _touched: bool = false


func _ready() -> void:
	add_to_group("town_map_view")
	custom_minimum_size = Constants.PHONE_MAP_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_exited.connect(func() -> void: _hover = -1)


## Back to the first view (the phone does this each time it comes out): you and
## the job's pin, framed together; the whole town when there's no job.
func reset_view() -> void:
	_zoom = 1.0
	_center = Constants.PHONE_MAP_FRAME.get_center()
	_framed = false
	_touched = false


## Frames you (or Chefty, aboard) and the pin, as near as fits; the whole town
## without a pin. Until the player zooms or pans it keeps doing so as you move,
## easing there (PHONE_MAP_FOLLOW_RATE), so a crewmate holding the map in the bed
## watches Chefty go and the map open out or close in round it; the first frame
## it's shown it snaps there. Needs the map's size, so it runs from _process.
func _frame_view(delta: float, snap: bool) -> void:
	_framed = true
	var pin := int(_model.get("pin", -1))
	var from: Vector3 = _model.get("from", Vector3.INF)
	var zoom := 1.0
	var center := Constants.PHONE_MAP_FRAME.get_center()
	if pin >= 0 and from != Vector3.INF and size.x > FRAME_MARGIN_PX * 2.0:
		var curb := TownMap.curb_point(pin)
		var box := Rect2(Vector2(from.x, from.z), Vector2.ZERO).expand(Vector2(curb.x, curb.z))
		var frame := Constants.PHONE_MAP_FRAME
		var fit := minf(size.x / frame.size.x, size.y / frame.size.y)
		var room := size - Vector2(FRAME_MARGIN_PX, FRAME_MARGIN_PX + CAPTION_PX) * 2.0
		var want := minf(room.x / maxf(box.size.x, 1.0), room.y / maxf(box.size.y, 1.0))
		zoom = clampf(want / fit, 1.0, Constants.PHONE_MAP_MAX_ZOOM)
		center = box.get_center()
	var share := 1.0 if snap else clampf(delta * Constants.PHONE_MAP_FOLLOW_RATE, 0.0, 1.0)
	# Zoom eases in proportion (a doubling takes as long either way).
	_zoom = exp(lerpf(log(_zoom), log(zoom), share))
	_center = _center.lerp(center, share)
	_clamp_center()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	_model = model(get_tree(), Net.local_peer_id())
	if size.x > 0.0 and (not _framed or not _touched):
		_frame_view(delta, not _framed)
	# Every frame: a way worked out a beat ago starts behind a moving Chefty, and
	# the line doubled back on itself there (rec_k_lag_friend 300-305). It's a
	# few dozen edges and a small A*.
	_refresh_route()
	queue_redraw()


# ---------------------------------------------------------------- what's on it

## What the map shows for this peer, as data (the view draws it; tests and the
## probe read it): {pin (house id or -1), yards (how many), requests, known,
## poached (house ids, sorted), locked (hood ids), chefty ({at, yaw} or {}),
## me_in_chefty, players ([{peer, at, yaw, color, name}], not anyone aboard
## Chefty, not the observer), from (where the way to the pin starts)}.
static func model(tree: SceneTree, me: int) -> Dictionary:
	var out := {"pin": job_house(tree), "yards": TownMap.house_count(), "requests": [], "known": [], "poached": [], "locked": [], "chefty": {}, "me_in_chefty": false, "players": [], "from": Vector3.INF}
	var town := tree.get_first_node_in_group("town")
	if town != null:
		var requests: Array = []
		for house_id: Variant in (town.get("requests") as Array):
			requests.append(int(house_id))
		requests.sort()
		out["requests"] = requests
		var known: Array = []
		var poached: Array = []
		for entry: Variant in (town.get("houses") as Array):
			var house := entry as Dictionary
			if bool(house.get("known", false)):
				known.append(int(house["id"]))
			if bool(house.get("poached", false)):
				poached.append(int(house["id"]))
		out["known"] = known
		out["poached"] = poached
		var locked: Array = []
		for hood: Dictionary in _Hoods.HOODS:
			if not bool(town.call("is_hood_open", str(hood["id"]))):
				locked.append(str(hood["id"]))
		out["locked"] = locked
	var chefty := tree.get_first_node_in_group("chefty") as Node3D
	if chefty != null and chefty.has_method("seat_of"):
		var at: Vector3 = chefty.call("body_position")
		out["chefty"] = {"at": at, "yaw": float(chefty.call("yaw"))}
		out["me_in_chefty"] = int(chefty.call("seat_of", me)) >= 0
		if bool(out["me_in_chefty"]):
			out["from"] = at
	var players: Array = []
	for node: Node in tree.get_nodes_in_group("players"):
		var body := node as Node3D
		var peer_id := int(str(node.name)) if str(node.name).is_valid_int() else 0
		if body == null or peer_id == 0 or Net.player_name(peer_id) == Net.OBSERVER_NAME:
			continue
		if not Net.player_zone(peer_id) in [Net.Zone.STORE, Net.Zone.LOT, Net.Zone.TOWN]:
			continue
		if chefty != null and chefty.has_method("seat_of") and int(chefty.call("seat_of", peer_id)) >= 0:
			continue
		var yaw := float(body.get("body_yaw")) if "body_yaw" in body else body.global_rotation.y
		if peer_id == me:
			out["from"] = body.global_position
			var camera := tree.root.get_camera_3d()
			if camera != null:
				var ahead := -camera.global_basis.z
				if Vector2(ahead.x, ahead.z).length() > 0.01:
					yaw = atan2(-ahead.x, -ahead.z)
		var look := body.get_node_or_null("Visual/CartoonBody")
		var shirt: Color = look.get("shirt") if look != null and look.get("shirt") is Color else YOU
		players.append({"peer": peer_id, "at": body.global_position, "yaw": yaw, "color": shirt, "name": Net.player_name(peer_id)})
	out["players"] = players
	return out


## What every peer's map should agree on, for the probe (CI compares the host's
## with a client's): the pin and the town's yards, not where anyone stands.
static func summary(tree: SceneTree) -> Dictionary:
	if not TownMap.enabled(tree):
		return {}
	var all := model(tree, Net.local_peer_id())
	return {"pin": all["pin"], "yards": all["yards"], "requests": all["requests"], "known": all["known"], "poached": all["poached"], "locked": all["locked"]}


## The house the crew's job is at: the yard that's loaded (until it's paid), or
## a pick whose yard is still on its way in; -1 for none.
static func job_house(tree: SceneTree) -> int:
	var world := tree.get_first_node_in_group("world")
	var house := int(world.call("job_site_house")) if world != null and world.has_method("job_site_house") else -1
	var lot := tree.get_first_node_in_group("job_lot")
	if house < 0 or lot == null:
		var board := tree.get_first_node_in_group("job_board")
		return int((board.call("current") as Dictionary).get("house_id", -1)) if board != null else -1
	if _site_paid(lot):
		return -1
	return house


## The loaded job yard has been paid for: its replicated stage (job_lot.gd), or
## the homeowner's paid phase (3) on a peer that saw the payment.
static func _site_paid(lot: Node) -> bool:
	if lot.has_method("is_paid") and bool(lot.call("is_paid")):
		return true
	var homeowner := lot.get_node_or_null("Homeowner")
	return homeowner != null and int(homeowner.get("_phase")) == 3


## "14 Maple Row": the house's number and street, from the town's houses.
static func address_of(tree: SceneTree, house_id: int) -> String:
	var town := tree.get_first_node_in_group("town")
	var entry: Dictionary = town.call("house", house_id) if town != null else {}
	if entry.is_empty():
		return TownMap.hood_id_of(house_id).capitalize()
	return _Strings.UI["site_address"] % [int(entry.get("number", 0)), str(entry.get("street", ""))]


## The way to the pin along the roads, and how long it is (m): from the road
## nearest you, through the junctions, to the curb.
static func route_to(from: Vector3, house_id: int) -> Dictionary:
	if house_id < 0 or from == Vector3.INF:
		return {"points": PackedVector3Array(), "meters": 0.0}
	var curb := TownMap.curb_point(house_id)
	var points := TownMap.route(from, curb)
	var meters := 0.0
	var last := Vector3(from.x, 0.0, from.z)
	for point: Vector3 in points:
		meters += last.distance_to(point)
		last = point
	meters += last.distance_to(curb)
	points.append(curb)
	return {"points": points, "meters": meters}


## The bottom line: the yard under the pointer (its owner too, if you know them),
## else the pin's address and how far it is by road; "" for nothing.
func caption() -> String:
	var tree := get_tree()
	if _hover >= 0:
		var known: Array = _model.get("known", [])
		var town := tree.get_first_node_in_group("town")
		var where := address_of(tree, _hover)
		if known.has(_hover) and town != null:
			return _Strings.UI["phone_map_client"] % [str(town.call("owner_name", _hover)), where]
		return where
	var pin := int(_model.get("pin", -1))
	if pin < 0:
		return ""
	return _Strings.UI["phone_map_pin"] % [address_of(tree, pin), roundi(_route_meters)]


## For tests: the model, the route and the caption as drawn now.
func report() -> Dictionary:
	var out := model(get_tree(), Net.local_peer_id())
	_model = out
	_refresh_route()
	out["route_points"] = _route.size()
	out["route_from"] = _route[0] if not _route.is_empty() else Vector3.INF
	out["route_to"] = _route[_route.size() - 1] if not _route.is_empty() else Vector3.INF
	out["route_meters"] = _route_meters
	out["caption"] = caption()
	out["zoom"] = _zoom
	return out


func _refresh_route() -> void:
	var way := route_to(_model.get("from", Vector3.INF), int(_model.get("pin", -1)))
	_route = way["points"]
	_route_meters = float(way["meters"])


# ---------------------------------------------------------------- map space

func _scale() -> float:
	var frame := Constants.PHONE_MAP_FRAME
	return minf(size.x / frame.size.x, size.y / frame.size.y) * _zoom


func to_map(world: Vector3) -> Vector2:
	return size * 0.5 + (Vector2(world.x, world.z) - _center) * _scale()


## The world point (x, z) under a point on the map.
func to_world(point: Vector2) -> Vector2:
	return _center + (point - size * 0.5) / _scale()


## Keeps the town on the map: the middle can't go past where the frame's edge
## would leave the screen.
func _clamp_center() -> void:
	var frame := Constants.PHONE_MAP_FRAME
	var half := size * 0.5 / _scale()
	# A little past the frame's edges, so whatever sits by an edge (Homie Depot,
	# the lake) can still be framed with room round it.
	var slack := Vector2.ONE * FRAME_MARGIN_PX / _scale()
	var low := frame.position + half - slack
	var high := frame.end - half + slack
	_center.x = clampf(_center.x, minf(low.x, frame.get_center().x), maxf(high.x, frame.get_center().x))
	_center.y = clampf(_center.y, minf(low.y, frame.get_center().y), maxf(high.y, frame.get_center().y))


func zoom_at(point: Vector2, zoom: float) -> void:
	var under := to_world(point)
	_zoom = clampf(zoom, 1.0, Constants.PHONE_MAP_MAX_ZOOM)
	_center = under - (point - size * 0.5) / _scale()
	_clamp_center()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var step := Constants.PHONE_MAP_ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / Constants.PHONE_MAP_ZOOM_STEP
			zoom_at(button.position, _zoom * step)
			_touched = true
			# The phone's list would scroll on the same wheel otherwise.
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			if button.pressed and button.double_click:
				reset_view()
			accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _dragging:
			_center -= motion.relative / _scale()
			_touched = true
			_clamp_center()
		_hover = _yard_under(motion.position)


func _yard_under(point: Vector2) -> int:
	var at := to_world(point)
	return TownMap.yard_at(Vector3(at.x, 0.0, at.y))


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if _model.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), LAND)
	_draw_ground()
	_draw_yards()
	_draw_roads()
	_draw_labels()
	_draw_route()
	_draw_pin()
	_draw_people()
	_draw_caption()


func _world_rect(rect: Rect2) -> Rect2:
	var from := to_map(Vector3(rect.position.x, 0.0, rect.position.y))
	var to := to_map(Vector3(rect.end.x, 0.0, rect.end.y))
	return Rect2(from, to - from)


func _draw_ground() -> void:
	var lake := _world_rect(TownMap.LAKE)
	draw_rect(lake, LAKE)
	draw_rect(lake, LAKE_EDGE, false, 1.0)
	draw_rect(_world_rect(Constants.STORE_AREA), LOT)
	var mark := _Icons.texture("brand_homie_depot")
	if mark != null:
		var at := to_map(STORE_MARK)
		var px := STORE_ICON_PX * sqrt(_zoom)
		draw_texture_rect(mark, Rect2(at - Vector2(px, px) * 0.5, Vector2(px, px)), false)


func _draw_yards() -> void:
	var locked: Array = _model.get("locked", [])
	for slot: Dictionary in TownMap.dressing_slots():
		var at: Vector3 = (slot["xform"] as Transform3D).origin
		var faint := Color(HOUSE_FAINT, LOCKED_ALPHA if locked.has(str(slot["hood"])) else 1.0)
		# Facing back across the street: its house is on the far side.
		draw_rect(_world_rect(Rect2(at.x - HOUSE_RECT.end.x, at.z - HOUSE_RECT.end.y, HOUSE_RECT.size.x, HOUSE_RECT.size.y)), faint)
	var known: Array = _model.get("known", [])
	var poached: Array = _model.get("poached", [])
	var requests: Array = _model.get("requests", [])
	var breathe := 0.5 + 0.5 * sin(_time * TAU * Constants.PHONE_MAP_PULSE_HZ)
	for house_id: int in TownMap.house_count():
		var fill := YARD
		if poached.has(house_id):
			fill = YARD_POACHED
		elif requests.has(house_id):
			fill = YARD_KNOWN.lerp(ORANGE, 0.35 + 0.5 * breathe)
		elif known.has(house_id):
			fill = YARD_KNOWN
		if locked.has(TownMap.hood_id_of(house_id)):
			fill.a = LOCKED_ALPHA
		var rect := _world_rect(TownMap.yard_rect(house_id)).grow(-0.5)
		draw_rect(rect, fill)
		draw_rect(rect, Color(YARD_EDGE, fill.a), false, 1.0)
		if house_id == _hover:
			draw_rect(rect.grow(0.5), INK, false, 1.5)
		var at := TownMap.yard_transform(house_id).origin
		draw_rect(_world_rect(Rect2(at.x + HOUSE_RECT.position.x, at.z + HOUSE_RECT.position.y, HOUSE_RECT.size.x, HOUSE_RECT.size.y)), Color(HOUSE, fill.a))
	_draw_numbers()


## Zoomed in, each yard wears its house number on the lawn, as on a street map.
func _draw_numbers() -> void:
	var font := get_theme_default_font()
	var town := get_tree().get_first_node_in_group("town")
	if font == null or town == null or _scale() < NUMBERS_FROM_PX:
		return
	for house_id: int in TownMap.house_count():
		var entry: Dictionary = town.call("house", house_id)
		if entry.is_empty():
			continue
		var at := to_map(TownMap.yard_transform(house_id).origin + Vector3(0.0, 0.0, 9.0))
		var number := str(int(entry.get("number", 0)))
		var wide := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT).x
		draw_string(font, at + Vector2(-wide * 0.5, LABEL_FONT * 0.35), number, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT, SOFT)


func _draw_roads() -> void:
	var scale_now := _scale()
	var edges := TownMap.road_edges()
	# Every edge's casing first, then every fill, so junctions join clean.
	for pass_index: int in 2:
		for edge: Array in edges:
			var a := to_map(TownMap.edge_from(edge))
			var b := to_map(TownMap.edge_to(edge))
			var width := maxf(float(edge[2]) * scale_now, ROAD_MIN_PX * (1.3 if str(edge[3]) == "main" else 1.0))
			if pass_index == 0:
				width += ROAD_EDGE_PX * 2.0
			var color := ROAD_EDGE if pass_index == 0 else (MAIN if str(edge[3]) == "main" else ROAD)
			draw_line(a, b, color, width, true)
			draw_circle(a, width * 0.5, color, true, -1.0, true)
			draw_circle(b, width * 0.5, color, true, -1.0, true)


## Each street's name just under it, east of Main Street, on the side of the
## houses across from the yards (faded while locked); Main Street's up its
## length, north of the square, and County Road 9's along it.
func _draw_labels() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var locked: Array = _model.get("locked", [])
	for hood_index: int in _Hoods.HOODS.size():
		var hood := _Hoods.HOODS[hood_index]
		var color := Color(SOFT, LOCKED_ALPHA if locked.has(str(hood["id"])) else 1.0)
		var start := to_map(Vector3(TownMap.MAIN_X + 10.0, 0.0, TownMap.STREET_Z[hood_index]))
		# In capitals, as a map names an area: a neighborhood's houses carry its few
		# street names in their addresses ("128 Sycamore Lane" is on Maple Row).
		_label(font, start + Vector2(0.0, maxf(float(TownMap.STREET_WIDTH) * _scale() * 0.5, ROAD_MIN_PX) + LABEL_FONT), str(hood["name"]).to_upper(), color)
	var main_at := to_map(Vector3(TownMap.MAIN_X, 0.0, (TownMap.SQUARE.z + TownMap.STREET_Z[0]) * 0.5))
	var main_text: String = _Strings.UI["map_main_street"]
	var main_wide := font.get_string_size(main_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT).x
	draw_set_transform(main_at + Vector2(-maxf(TownMap.MAIN_WIDTH * _scale() * 0.5, ROAD_MIN_PX) - 3.0, main_wide * 0.5), -PI * 0.5)
	_label(font, Vector2.ZERO, main_text, SOFT)
	draw_set_transform(Vector2.ZERO)
	_label(font, to_map(Vector3(110.0, 0.0, TownMap.COUNTY_BEND.z)) + Vector2(0.0, -maxf(TownMap.STREET_WIDTH * _scale() * 0.5, ROAD_MIN_PX) - 3.0), _Strings.UI["map_county_road"], SOFT)


func _label(font: Font, at: Vector2, text: String, color: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT, 3, Color(LAND, color.a))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT, color)


func _draw_route() -> void:
	if _route.size() < 2 or int(_model.get("pin", -1)) < 0:
		return
	var points := PackedVector2Array()
	var from: Vector3 = _model.get("from", Vector3.INF)
	if from != Vector3.INF:
		points.append(to_map(from))
	for point: Vector3 in _route:
		points.append(to_map(point))
	draw_polyline(points, ROUTE_CASING, ROUTE_PX + 2.0, true)
	draw_polyline(points, ORANGE, ROUTE_PX, true)


func _draw_pin() -> void:
	var pin := int(_model.get("pin", -1))
	if pin < 0:
		return
	var at := to_map(TownMap.curb_point(pin))
	# A ring going out from the spot, like a phone's "it's here".
	var ring := fmod(_time * Constants.PHONE_MAP_PULSE_HZ, 1.0)
	draw_arc(at, PIN_PX * (0.6 + 1.6 * ring), 0.0, TAU, 24, Color(ORANGE, 0.8 * (1.0 - ring)), 1.5, true)
	var head := at + Vector2(0.0, -PIN_RISE_PX)
	draw_colored_polygon(PackedVector2Array([at, head + Vector2(-PIN_PX * 0.8, PIN_PX * 0.45), head + Vector2(PIN_PX * 0.8, PIN_PX * 0.45)]), ORANGE)
	draw_circle(head, PIN_PX, ORANGE, true, -1.0, true)
	draw_circle(head, PIN_PX, Color(1.0, 1.0, 1.0), false, 1.2, true)
	draw_circle(head, PIN_PX * 0.38, Color(1.0, 1.0, 1.0), true, -1.0, true)


func _draw_people() -> void:
	var chefty: Dictionary = _model.get("chefty", {})
	if not chefty.is_empty():
		_draw_chefty(to_map(chefty["at"]), float(chefty["yaw"]), bool(_model.get("me_in_chefty", false)))
	var font := get_theme_default_font()
	var me := Net.local_peer_id()
	var mine: Dictionary = {}
	for entry: Variant in (_model.get("players", []) as Array):
		var player := entry as Dictionary
		if int(player["peer"]) == me:
			mine = player
			continue
		var at := to_map(player["at"])
		draw_circle(at, DOT_PX + 1.2, Color(1.0, 1.0, 1.0), true, -1.0, true)
		draw_circle(at, DOT_PX, player["color"], true, -1.0, true)
		if font != null:
			var initial := str(player["name"]).left(1).to_upper()
			_label(font, at + Vector2(DOT_PX + 2.0, 3.5), initial, INK)
	# You on top of everyone.
	if not mine.is_empty():
		_draw_arrow(to_map(mine["at"]), float(mine["yaw"]))


## Which way a yaw points on the map (north up: world -Z is up the screen).
static func _ahead(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


func _draw_arrow(at: Vector2, yaw: float) -> void:
	var ahead := _ahead(yaw)
	var side := Vector2(-ahead.y, ahead.x)
	var tip := at + ahead * ARROW_PX
	var back := at - ahead * ARROW_PX * 0.55
	var shape := PackedVector2Array([tip, back + side * ARROW_PX * 0.7, at - ahead * ARROW_PX * 0.2, back - side * ARROW_PX * 0.7])
	draw_circle(at, ARROW_PX * 1.25, Color(YOU, 0.18), true, -1.0, true)
	draw_colored_polygon(shape, YOU)
	shape.append(tip)
	draw_polyline(shape, Color(1.0, 1.0, 1.0), 1.4, true)


func _draw_chefty(at: Vector2, yaw: float, mine: bool) -> void:
	var ahead := _ahead(yaw)
	var side := Vector2(-ahead.y, ahead.x)
	var grow := sqrt(_zoom)
	var length := CHEFTY_PX.y * grow
	var width := CHEFTY_PX.x * grow
	if mine:
		draw_circle(at, length * 0.85, Color(YOU, 0.22), true, -1.0, true)
		draw_arc(at, length * 0.85, 0.0, TAU, 28, YOU, 1.5, true)
	var body := PackedVector2Array([
		at + ahead * length * 0.5 + side * width * 0.5,
		at + ahead * length * 0.5 - side * width * 0.5,
		at - ahead * length * 0.5 - side * width * 0.5,
		at - ahead * length * 0.5 + side * width * 0.5,
	])
	draw_colored_polygon(body, CHEFTY)
	# The cab, at the nose, darker: which end is the front reads at a glance.
	var cab := PackedVector2Array([
		at + ahead * length * 0.5 + side * width * 0.42,
		at + ahead * length * 0.5 - side * width * 0.42,
		at + ahead * length * 0.12 - side * width * 0.42,
		at + ahead * length * 0.12 + side * width * 0.42,
	])
	draw_colored_polygon(cab, CHEFTY_CAB)
	body.append(body[0])
	draw_polyline(body, Color(1.0, 1.0, 1.0), 1.2, true)


func _draw_caption() -> void:
	var text := caption()
	var font := get_theme_default_font()
	if text == "" or font == null:
		return
	var strip := Rect2(0.0, size.y - CAPTION_PX, size.x, CAPTION_PX)
	draw_rect(strip, CAPTION_BACK)
	var pin := int(_model.get("pin", -1))
	var color := ORANGE.darkened(0.25) if _hover < 0 and pin >= 0 else INK
	draw_string(font, Vector2(8.0, size.y - CAPTION_PX * 0.5 + CAPTION_FONT * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, CAPTION_FONT, color)
