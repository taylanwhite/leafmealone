extends HBoxContainer

## Authority: local. Your snacks at work, as icons in the HUD's top-left rows
## (docs/GAME.md "Shops", "Snacks: what you see"; gap shops chunk 6): one icon
## per buff running on you (ui/icons.gd buff_<id>: the hot dog for full, the
## can for Turbo, the cup for coffee, the drained can for the crash, the green
## sandwich for queasy), each with a ring that drains as it runs out and a blink
## in its last seconds. No words: the icon and your body say it (the jitter, the
## heavy lids, the green face; player/snack_eater.gd). An icon pops in when the
## buff starts and shrinks away when it ends. Reads World/Shops.buffs_left for
## the local player, which every peer has.

const _Icons = preload("res://ui/icons.gd")
## How long an icon takes to pop in or shrink away (s).
const POP_SECONDS: float = 0.22

## The buff ids on show, in order (tests read it).
var shown: Array[String] = []

var _cells: Dictionary = {}
var _time: float = 0.0


func _ready() -> void:
	name = "BuffRow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", Constants.BUFF_HUD_GAP)
	visible = false


func _process(delta: float) -> void:
	_time += delta
	var shops := get_tree().get_first_node_in_group("shops")
	var running: Dictionary = shops.call("buffs_left", Net.local_peer_id()) if shops != null else {}
	for buff_id: Variant in running:
		if not _cells.has(buff_id):
			_add(str(buff_id))
	for buff_id: Variant in _cells.keys():
		if not running.has(buff_id):
			_remove(str(buff_id))
	for buff_id: Variant in _cells:
		var cell: Control = _cells[buff_id]
		var left := float(running.get(buff_id, 0.0))
		var seconds := float((Constants.BUFFS.get(str(buff_id), {}) as Dictionary).get("seconds", 1.0))
		var ring := cell.get_node("Ring") as BuffRing
		ring.share = clampf(left / maxf(seconds, 0.01), 0.0, 1.0)
		ring.queue_redraw()
		var icon := cell.get_node("Icon") as Control
		icon.modulate.a = 0.45 + 0.55 * absf(cos(_time * 5.0)) if left < Constants.BUFF_HUD_BLINK_SECONDS else 1.0
	shown.clear()
	for buff_id: Variant in _cells:
		shown.append(str(buff_id))
	visible = not _cells.is_empty() or get_child_count() > 0


func _add(buff_id: String) -> void:
	var px := float(Constants.BUFF_HUD_PX)
	var cell := Control.new()
	cell.name = "Buff_" + buff_id
	cell.custom_minimum_size = Vector2(px, px)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.pivot_offset = Vector2(px, px) * 0.5
	var ring := BuffRing.new()
	ring.name = "Ring"
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(ring)
	var icon := _Icons.rect("buff_" + buff_id, px * 0.78)
	icon.name = "Icon"
	icon.position = Vector2(px, px) * 0.11
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	add_child(cell)
	_cells[buff_id] = cell
	cell.scale = Vector2.ZERO
	var tween := cell.create_tween()
	tween.tween_property(cell, "scale", Vector2.ONE * 1.18, POP_SECONDS * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(cell, "scale", Vector2.ONE, POP_SECONDS * 0.4)


func _remove(buff_id: String) -> void:
	var cell: Control = _cells[buff_id]
	_cells.erase(buff_id)
	var tween := cell.create_tween()
	tween.tween_property(cell, "scale", Vector2.ZERO, POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(cell.queue_free)


## A ring round the icon that drains clockwise from the top as the buff runs out.
class BuffRing extends Control:
	var share: float = 1.0

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(center, radius + 1.5, Color(0.08, 0.07, 0.06, 0.55))
		draw_arc(center, radius, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.18), 2.5, true)
		if share > 0.0:
			draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * share, 32, Color(1.0, 0.82, 0.3), 2.5, true)
