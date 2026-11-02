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


## The next thing this player should do, or "" when there is nothing to say.
static func goal(tree: SceneTree, peer_id: int) -> String:
	var zone := Net.player_zone(peer_id)
	var chefty := tree.get_first_node_in_group("chefty")
	if zone == Net.Zone.STORE:
		var clock := tree.get_first_node_in_group("day_clock")
		if clock != null and bool(clock.call("is_closed")):
			return _Strings.UI["goal_sleep"]
		var board := tree.get_first_node_in_group("job_board")
		if board != null and tree.get_first_node_in_group("town") != null and (board.get("offers") as Array).is_empty():
			return _Strings.UI["goal_no_jobs"]
		# Texts waiting: that's where the jobs come from.
		var phone := tree.get_first_node_in_group("phone")
		var ui := tree.get_first_node_in_group("game_ui")
		var board_seen := ui != null and bool(ui.get("board_seen"))
		if phone != null and int(phone.call("unread")) > 0 and not board_seen and int(Net.dev_options().get("job_seed")) == 0:
			return _Strings.UI["goal_texts"]
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
	var player := _player_node(tree, peer_id)
	if player != null and bool(player.call("is_climbing")):
		return _Strings.UI["goal_gutters"]
	if player != null and bool(player.call("is_up_high")):
		return _Strings.UI["goal_roof"]
	if held == "ladder":
		return _Strings.UI["goal_set_ladder"]
	var held_node := _held_node(tree, peer_id)
	if held == "hose" and held_node != null and str(held_node.get("hose_source")) == "":
		return _Strings.UI["goal_hook_hose"]
	if held == "lawn_mower" and held_node != null:
		return _Strings.UI["goal_start_mower"] if not bool(held_node.get("spraying")) else _Strings.UI["goal_mower_running"]
	if held == "paint_roller" and held_node != null and float(held_node.get("water")) <= 0.0:
		return _Strings.UI["goal_dip_roller"]
	if held == "pressure_washer" and held_node != null:
		if float(held_node.get("water")) <= 0.0:
			return _Strings.UI["goal_refill"]
		return _Strings.UI["goal_washer_tank"] % int(float(held_node.get("water")))
	# Holding a tool: say what it's for, if that work is still open.
	if held != "" and Constants.TOOL_PRICES.has(held):
		var for_task := _task_for_tool(held)
		var tasks := tree.get_first_node_in_group("job_tasks")
		if for_task != "" and tasks != null and (tasks.get("active") as PackedStringArray).has(for_task) and float(tasks.call("progress", for_task)) < 0.95:
			return _Strings.UI["goal_task"] % _Strings.UI["task_" + for_task]
	if held == "leaf_bag":
		return _Strings.UI["goal_carry_held"]
	if held == "rake":
		return _Strings.UI["goal_rake"]
	# The rake in your own pocket and nothing in hand: it's one key away.
	if held == "" and player != null:
		var pockets := player.get_node_or_null("Pockets")
		var slot := int(pockets.call("slot_of_kind", "rake")) if pockets != null else -1
		if slot >= 0:
			return _Strings.UI["goal_draw_rake"] % _Strings.keyed("{key:slot_%d}" % (slot + 1))
	var loose := 0
	var rake_free := false
	for node: Node in tree.get_nodes_in_group("props"):
		var kind := str(node.get("kind"))
		# Loose means nobody holds it or has it in a pocket (net_prop.gd is_loose).
		if kind == "leaf_bag" and bool(node.call("is_loose")):
			loose += 1
		elif kind == "rake" and bool(node.call("is_loose")):
			rake_free = true
	if loose > 0:
		return _Strings.UI["goal_carry_loose"] % loose
	var banked := int(chefty.call("bag_value")) if chefty != null else 0
	if rake_free:
		return _Strings.UI["goal_rake_or_talk"] % banked if banked > 0 else _Strings.UI["goal_grab_rake"]
	if banked > 0:
		return _Strings.UI["goal_talk"] % banked
	return _Strings.UI["goal_no_rake"]


static func _player_node(tree: SceneTree, peer_id: int) -> Node:
	for node: Node in tree.get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node
	return null


static func _task_for_tool(tool: String) -> String:
	for task: String in Constants.TASK_TOOLS:
		if str(Constants.TASK_TOOLS[task]) == tool:
			return task
	return ""


static func _held_node(tree: SceneTree, peer_id: int) -> Node:
	for node: Node in tree.get_nodes_in_group("props"):
		if int(node.get("held_by")) == peer_id:
			return node
	return null


static func _held_by(tree: SceneTree, peer_id: int) -> String:
	for node: Node in tree.get_nodes_in_group("props"):
		if int(node.get("held_by")) == peer_id:
			return str(node.get("kind"))
	return ""
