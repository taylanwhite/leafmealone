extends Label

## Authority: local. One line near the bottom of the screen that says where the
## job is when you can't see it: the address, how far by road, and which way to
## go. It used to say what to do next at every step (board Chefty, grab the
## rake, bag it, carry it, talk to the homeowner); x1:text cut all of that
## (Taylan: "Our players are not idiots"), so the yard, Chefty, the homeowner and
## the prompts teach the loop (docs/GAME.md "Writing for players"). Driving
## chunk K polished what's left: the meters are by road and the arrow points the
## way along the road, both the same way the phone's map works them out
## (ui/town_map_view.gd), from Chefty when you're aboard; and the line steps
## aside while the Map app is out, since the map's own strip says the same. It
## reads state every peer already has, so it never sends anything. It pops a
## little when it starts saying a new place (not on every meter counted down).

const _Strings = preload("res://ui/strings.gd")
const _TownMapView = preload("res://ui/town_map_view.gd")
const POP_SECONDS: float = 0.25

var _pop: float = 0.0
## The house the line last named (-1 when quiet): a new one pops it.
var _named: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Its bottom sits just above the hotbar's band (ui/hotbar_hud.gd), and it
	# grows upward, so a taller line never runs down into the bar.
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -Constants.HOTBAR_GOAL_LINE_Y
	offset_top = offset_bottom
	add_theme_font_size_override("font_size", 22)
	add_theme_color_override("font_color", Color(1.0, 0.93, 0.62))
	add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.04))
	add_theme_constant_override("outline_size", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var next := ""
	if Net.current_state() == Net.State.IN_SESSION:
		# goal() gives the string as written; its {key:} tokens become the player's keys here.
		next = _Strings.keyed(goal(get_tree(), Net.local_peer_id()))
	var named := _TownMapView.job_house(get_tree()) if next != "" else -1
	if named != _named:
		_named = named
		if named >= 0:
			_pop = POP_SECONDS
	text = next
	visible = text != ""
	_pop = maxf(0.0, _pop - delta)
	pivot_offset = size * 0.5
	scale = Vector2.ONE * (1.0 + 0.18 * (_pop / POP_SECONDS))


## What the line says for this player right now, or "" when there is nothing
## they can't already see: on the yard, at a store without a picked job, at
## bedtime (the clock and Marty's welcome text cover it), at the curb (the chalk
## box, the beacon and the homeowner say the rest), once the job's paid, and
## while the phone's Map app is out (its strip says it).
static func goal(tree: SceneTree, peer_id: int) -> String:
	var zone := Net.player_zone(peer_id)
	if (zone == Net.Zone.STORE or zone == Net.Zone.TOWN) and TownMap.enabled(tree):
		return _town_goal(tree, peer_id)
	return ""


## The connected town (driving chunk D, polished in K), at the store or out in
## town: "22 Sycamore Lane · 615 m ↗", the meters along the roads and the arrow
## toward the road a little way ahead on that route, from where this peer's
## camera looks. From Chefty when aboard, as the map does.
static func _town_goal(tree: SceneTree, peer_id: int) -> String:
	var clock := tree.get_first_node_in_group("day_clock")
	if clock != null and bool(clock.call("is_closed")):
		return ""
	var phone := tree.get_first_node_in_group("phone")
	if phone != null and peer_id == Net.local_peer_id() and phone.has_method("is_out") and bool(phone.call("is_out")) and str(phone.get("_app")) == "map":
		return ""
	var house := _TownMapView.job_house(tree)
	if house < 0:
		return ""
	var from := _from(tree, peer_id)
	if from == Vector3.INF:
		return ""
	var curb := TownMap.curb_point(house)
	if Vector2(curb.x - from.x, curb.z - from.z).length() <= Constants.CHEFTY_ARRIVE_RADIUS:
		return ""
	var way := _TownMapView.route_to(from, house)
	return _Strings.UI["goal_drive_to"] % [_TownMapView.address_of(tree, house), roundi(float(way["meters"])), _arrow(tree, from, _ahead_on(from, way["points"]))]


## Where the way starts for this peer: Chefty when they're aboard it, else
## where they stand (the map's model "from"); Vector3.INF for no body.
static func _from(tree: SceneTree, peer_id: int) -> Vector3:
	var chefty := tree.get_first_node_in_group("chefty") as Node3D
	if chefty != null and chefty.has_method("seat_of") and int(chefty.call("seat_of", peer_id)) >= 0:
		return chefty.call("body_position")
	for node: Node in tree.get_nodes_in_group("players"):
		if node.name == str(peer_id) and node is Node3D:
			return (node as Node3D).global_position
	return Vector3.INF


## The point GOAL_ARROW_LOOKAHEAD meters along the way from here, so the arrow
## follows the road (out of the lot, round the next corner), not a straight
## line through the houses.
static func _ahead_on(from: Vector3, points: PackedVector3Array) -> Vector3:
	var left := Constants.GOAL_ARROW_LOOKAHEAD
	var last := Vector3(from.x, 0.0, from.z)
	for point: Vector3 in points:
		var step := last.distance_to(point)
		if step >= left:
			return last.lerp(point, left / step)
		left -= step
		last = point
	return last


## Which way the place is from here, as one of eight arrows, relative to where
## this peer's camera faces (up is straight ahead).
static func _arrow(tree: SceneTree, from: Vector3, to: Vector3) -> String:
	var camera := tree.root.get_camera_3d()
	var ahead := -camera.global_basis.z if camera != null else Vector3.FORWARD
	var forward := Vector2(ahead.x, ahead.z)
	var toward := Vector2(to.x - from.x, to.z - from.z)
	if forward.length() < 0.01 or toward.length() < 0.01:
		return ARROWS[0]
	# Clockwise from straight ahead, seen from above (+x right of -z).
	var turn := wrapf(forward.angle_to(toward), 0.0, TAU)
	var sector := posmod(roundi(turn / (TAU / 8.0)), 8)
	# Through a turn the bearing sits on a sector's edge and the arrow flickered
	# (↑ ↖ ↑ ↖ in rec_r_drive_1p 893-898): it keeps the last one until the way is
	# GOAL_ARROW_HYSTERESIS past the edge.
	if _last_sector >= 0 and sector != _last_sector:
		var off := absf(wrapf(turn - _last_sector * (TAU / 8.0), -PI, PI))
		if off < TAU / 16.0 + deg_to_rad(Constants.GOAL_ARROW_HYSTERESIS):
			sector = _last_sector
	_last_sector = sector
	return ARROWS[sector]


## The arrow the line showed last (-1 before any), for _arrow's hysteresis.
static var _last_sector: int = -1


## Ahead, then clockwise: ahead-right, right, behind-right, behind, ...
const ARROWS: Array[String] = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
