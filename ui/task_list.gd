extends PanelContainer

## Authority: local. "Today's job": the work this yard's homeowner asked for,
## each with how much is done, under the cash in the corner while you're on the
## lot. A task the crew has no tool for says what it needs (that's what the
## store is for). Reads the replicated job (net/work/job_tasks.gd) and the
## leaf field, so it sends nothing.
## Each row is [task badge] words [check] (icons chunk E): a finished task's check
## pops in; a task the crew can't do yet has a faded badge and the missing tool's
## icon. Rows are kept and updated in place, rebuilt only when the task set changes.

const _Strings = preload("res://ui/strings.gd")
const _Icons = preload("res://ui/icons.gd")
const DONE := Color(0.55, 0.95, 0.5)
const OPEN := Color(1.0, 0.97, 0.88)
const LOCKED := Color(0.8, 0.75, 0.7)
const CHECK_PX: float = 18.0
const TOOL_PX: float = 20.0
## A task the crew can't do yet shows its badge this faint, and the missing tool a
## little less (it's the thing to go and buy).
const LOCKED_ALPHA: float = 0.5
const TOOL_ALPHA: float = 0.8

var _rows: VBoxContainer
var _wait: float = 0.0
## The tasks the rows show now, in order, and each task's row.
var _shown: PackedStringArray = PackedStringArray()
var _lines: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.08, 0.06, 0.55)
	box.set_corner_radius_all(8)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	add_theme_stylebox_override("panel", box)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	add_child(_rows)
	_rows.add_child(_label(_Strings.UI["tasks_title"], 17, Color(1.0, 0.8, 0.45)))
	position = Vector2(16, 104)
	visible = false


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 0.25
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	var on_lot := Net.current_state() == Net.State.IN_SESSION and Net.player_zone(Net.local_peer_id()) == Net.Zone.LOT
	visible = tasks != null and on_lot
	if not visible:
		return
	var order := PackedStringArray(["rake_leaves"])
	for task: String in (tasks.get("active") as PackedStringArray):
		if task != "rake_leaves":
			order.append(task)
	if order != _shown:
		for task: String in _lines:
			(_lines[task] as Node).queue_free()
		_lines.clear()
		_shown = order
	var field := get_tree().get_first_node_in_group("leaf_field")
	for task: String in order:
		var done := float(field.call("cleaned_fraction")) if field != null else 0.0
		if task != "rake_leaves":
			done = float(tasks.call("progress", task))
		if _lines.has(task):
			_update_line(_lines[task], task, done)
		else:
			var line := _task_line(task, done)
			_rows.add_child(line)
			_lines[task] = line


## One task's row, filled in for how much of it is done (0 to 1).
func _task_line(task: String, done: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := _Icons.rect(_Icons.for_task(task), _Icons.SIZE_HUD)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var words := _label("", 15, OPEN)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(words)
	var check := _Icons.rect("check", CHECK_PX)
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.visible = false
	row.add_child(check)
	var tool := str(Constants.TASK_TOOLS.get(task, ""))
	var tool_icon := _Icons.rect(_Icons.for_tool(tool) if tool != "" else "", TOOL_PX)
	tool_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tool_icon.modulate = Color(1.0, 1.0, 1.0, TOOL_ALPHA)
	tool_icon.visible = false
	row.add_child(tool_icon)
	row.set_meta("parts", [badge, words, check, tool_icon])
	_update_line(row, task, done)
	return row


func _update_line(row: Control, task: String, done: float) -> void:
	var parts: Array = row.get_meta("parts")
	var badge := parts[0] as Control
	var words := parts[1] as Label
	var check := parts[2] as Control
	var tool_icon := parts[3] as Control
	var name := str(_Strings.UI["task_" + task])
	var tool := str(Constants.TASK_TOOLS.get(task, ""))
	var locked := tool != "" and not _crew_has(tool)
	var percent := int(round(done * 100.0))
	var finished := not locked and percent >= Constants.TASK_DONE_PERCENT
	var text: String = _Strings.UI["task_needs"] % [name, str(_Strings.UI["tool_" + tool]).to_lower()] if locked else _Strings.UI["task_line"] % [name, percent]
	if words.text != text:
		words.text = text
	words.add_theme_color_override("font_color", LOCKED if locked else (DONE if finished else OPEN))
	badge.modulate = Color(1.0, 1.0, 1.0, LOCKED_ALPHA if locked else 1.0)
	tool_icon.visible = locked
	if finished and not check.visible:
		check.visible = true
		# Ticked off while you watch: the check grows in from nothing and overshoots
		# a little (not on a fresh row). Its laid-out size is its minimum size, so
		# the pivot is known before the row sorts. from(): the row's sort resets a
		# child's scale to 1 after this, so the start value can't be set here.
		if row.is_inside_tree():
			check.pivot_offset = check.custom_minimum_size * 0.5
			check.scale = Vector2.ZERO
			check.create_tween().tween_property(check, "scale", Vector2.ONE, Constants.ICONS_POP_SECONDS).from(Vector2.ZERO).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif not finished:
		check.visible = false


## Whether a tool for this came along on the job (a prop of that kind exists).
func _crew_has(tool: String) -> bool:
	if not is_inside_tree():
		return false
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == tool:
			return true
	return false


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label
