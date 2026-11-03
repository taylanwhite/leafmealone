extends Label

## Authority: local. One line near the bottom of the screen that says where the
## job is when you can't see it: the address, how far, and which way. It used to
## say what to do next at every step (board Chefty, grab the rake, bag it, carry
## it, talk to the homeowner); x1:text cut all of that (Taylan: "Our players are
## not idiots"), so the yard, Chefty, the homeowner and the prompts teach the
## loop (docs/GAME.md "Writing for players"). It reads state every peer already
## has, so it never sends anything. It pops a little when the line changes.

const _Strings = preload("res://ui/strings.gd")
const POP_SECONDS: float = 0.25

var _pop: float = 0.0


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
	if next != text:
		text = next
		_pop = POP_SECONDS
	visible = text != ""
	_pop = maxf(0.0, _pop - delta)
	pivot_offset = size * 0.5
	scale = Vector2.ONE * (1.0 + 0.18 * (_pop / POP_SECONDS))


## What the line says for this player right now, or "" when there is nothing
## they can't already see: on the yard, at a store without a picked job, at
## bedtime (the clock and Marty's welcome text cover it), and parked at the chalk
## box (PARK HERE says it).
static func goal(tree: SceneTree, peer_id: int) -> String:
	var zone := Net.player_zone(peer_id)
	if (zone == Net.Zone.STORE or zone == Net.Zone.TOWN) and TownMap.enabled(tree):
		return _town_goal(tree, peer_id)
	return ""


## The connected town (driving chunk D), at the store or out in town: the job is
## at the client's house, so the line says where it is, how far, and which way
## (an arrow from where this peer's camera looks).
static func _town_goal(tree: SceneTree, peer_id: int) -> String:
	var clock := tree.get_first_node_in_group("day_clock")
	if clock != null and bool(clock.call("is_closed")):
		return ""
	var world := tree.get_first_node_in_group("world")
	var board := tree.get_first_node_in_group("job_board")
	var house := int(world.call("job_site_house")) if world != null else -1
	var lot := tree.get_first_node_in_group("job_lot")
	if house < 0 or lot == null:
		# A pick whose yard is on its way in (the host swaps a paid yard for it):
		# point at the house already.
		house = int((board.call("current") as Dictionary).get("house_id", -1)) if board != null else -1
		if house < 0:
			return ""
	elif _site_paid(tree):
		return ""
	var player := _player_node(tree, peer_id) as Node3D
	if player == null:
		return ""
	var curb := TownMap.curb_point(house)
	var meters := Vector2(curb.x - player.global_position.x, curb.z - player.global_position.z).length()
	# At the curb: the chalk box, the beacon and the homeowner say the rest.
	if meters <= Constants.CHEFTY_ARRIVE_RADIUS:
		return ""
	return _Strings.UI["goal_drive_to"] % [_address(tree, house), int(meters), _arrow(tree, player.global_position, curb)]


## The loaded job yard has been paid for: its replicated stage (job_lot.gd), or
## the homeowner's paid phase (3) on a peer that saw the payment.
static func _site_paid(tree: SceneTree) -> bool:
	var lot := tree.get_first_node_in_group("job_lot")
	if lot == null:
		return false
	if lot.has_method("is_paid") and bool(lot.call("is_paid")):
		return true
	var homeowner := lot.get_node_or_null("Homeowner")
	return homeowner != null and int(homeowner.get("_phase")) == 3


## "14 Maple Row": the house's number and street, from the town's houses.
static func _address(tree: SceneTree, house_id: int) -> String:
	var town := tree.get_first_node_in_group("town")
	var entry: Dictionary = town.call("house", house_id) if town != null else {}
	if entry.is_empty():
		return TownMap.hood_id_of(house_id).capitalize()
	return _Strings.UI["site_address"] % [int(entry.get("number", 0)), str(entry.get("street", ""))]


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
	return ARROWS[posmod(roundi(turn / (TAU / 8.0)), 8)]


## Ahead, then clockwise: ahead-right, right, behind-right, behind, ...
const ARROWS: Array[String] = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]


static func _player_node(tree: SceneTree, peer_id: int) -> Node:
	for node: Node in tree.get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node
	return null
