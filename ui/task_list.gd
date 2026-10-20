extends PanelContainer

## Authority: local. "Today's job": the work this yard's homeowner asked for,
## each with how much is done, under the cash in the corner while you're on the
## lot. A task the crew has no tool for says what it needs (that's what the
## store is for). Reads the replicated job (net/work/job_tasks.gd) and the
## leaf field, so it sends nothing.

const _Strings = preload("res://ui/strings.gd")
const DONE := Color(0.55, 0.95, 0.5)
const OPEN := Color(1.0, 0.97, 0.88)
const LOCKED := Color(0.8, 0.75, 0.7)

var _rows: VBoxContainer
var _wait: float = 0.0


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
	for child: Node in _rows.get_children():
		child.queue_free()
	_rows.add_child(_label(_Strings.UI["tasks_title"], 17, Color(1.0, 0.8, 0.45)))
	var field := get_tree().get_first_node_in_group("leaf_field")
	var leaves := float(field.call("cleaned_fraction")) if field != null else 0.0
	_rows.add_child(_task_line("rake_leaves", leaves))
	for task: String in (tasks.get("active") as PackedStringArray):
		if task != "rake_leaves":
			_rows.add_child(_task_line(task, float(tasks.call("progress", task))))


func _task_line(task: String, done: float) -> Label:
	var name := str(_Strings.UI["task_" + task])
	var tool := str(Constants.TASK_TOOLS.get(task, ""))
	if tool != "" and not _crew_has(tool):
		return _label(_Strings.UI["task_needs"] % [name, str(_Strings.UI["tool_" + tool]).to_lower()], 15, LOCKED)
	var percent := int(round(done * 100.0))
	var check := "✓ " if percent >= 95 else "• "
	return _label(check + _Strings.UI["task_line"] % [name, percent], 15, DONE if percent >= 95 else OPEN)


## Whether a tool for this came along on the job (a prop of that kind exists).
func _crew_has(tool: String) -> bool:
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
