extends Label

## Authority: local. One line near the bottom of the screen that always says what
## to do next on the job: board Chefty, grab the rake, rake a pile and bag it,
## carry bags to Chefty, talk to the homeowner, grab the cash. It reads state
## every peer already has (who holds what, the homeowner's phase, Chefty's load),
## so it never sends anything. It pops a little when the goal changes.

const _Strings = preload("res://ui/strings.gd")
const POP_SECONDS: float = 0.25

var _pop: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	position.y -= 64.0
	add_theme_font_size_override("font_size", 22)
	add_theme_color_override("font_color", Color(1.0, 0.93, 0.62))
	add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.04))
	add_theme_constant_override("outline_size", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var next := ""
	if Net.current_state() == Net.State.IN_SESSION:
		next = goal(get_tree(), Net.local_peer_id())
	if next != text:
		text = next
		_pop = POP_SECONDS
	visible = text != ""
	_pop = maxf(0.0, _pop - delta)
	pivot_offset = size * 0.5
	scale = Vector2.ONE * (1.0 + 0.18 * (_pop / POP_SECONDS))


## The next thing this player should do, or "" when there is nothing to say.
static func goal(tree: SceneTree, peer_id: int) -> String:
	var zone := Net.player_zone(peer_id)
	var chefty := tree.get_first_node_in_group("chefty")
	if zone == Net.Zone.STORE:
		if chefty != null and not bool(chefty.call("is_riding")):
			return _Strings.UI["goal_board"]
		return ""
	if zone != Net.Zone.LOT:
		return ""
	var homeowner := tree.get_first_node_in_group("homeowner")
	# Homeowner phases: 0 waiting, 1 reacting, 2 holding out the cash, 3 paid.
	var phase := int(homeowner.get("_phase")) if homeowner != null else 0
	if phase == 2:
		return _Strings.UI["goal_take_cash"]
	if phase == 1 or phase == 3:
		return ""
	var held := _held_by(tree, peer_id)
	if held == "leaf_bag":
		return _Strings.UI["goal_carry_held"]
	if held == "rake":
		return _Strings.UI["goal_rake"]
	var loose := 0
	var rake_free := false
	for node: Node in tree.get_nodes_in_group("props"):
		var kind := str(node.get("kind"))
		if kind == "leaf_bag" and int(node.get("held_by")) == 0:
			loose += 1
		elif kind == "rake" and int(node.get("held_by")) == 0:
			rake_free = true
	if loose > 0:
		return _Strings.UI["goal_carry_loose"] % loose
	var banked := int(chefty.call("bag_value")) if chefty != null else 0
	if rake_free:
		return _Strings.UI["goal_rake_or_talk"] % banked if banked > 0 else _Strings.UI["goal_grab_rake"]
	if banked > 0:
		return _Strings.UI["goal_talk"] % banked
	return _Strings.UI["goal_no_rake"]


static func _held_by(tree: SceneTree, peer_id: int) -> String:
	for node: Node in tree.get_nodes_in_group("props"):
		if int(node.get("held_by")) == peer_id:
			return str(node.get("kind"))
	return ""
