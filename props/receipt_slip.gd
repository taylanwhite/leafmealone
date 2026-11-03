extends RefCounted

## Authority: local, cosmetic. The till slip you get back at the curb (docs/GAME.md
## "Satellite Annex B"): a curling strip of thermal paper fed up into your view
## line by line with the printer's chatter, held for a few seconds, then let go.
##
##   ReceiptSlip.show(lines, total_line, at, seconds := 4.0)   # the local player's, in their current view
##   ReceiptSlip.show_for(player, lines, total_line, at, seconds, first_person)
##
## The words are R2 chunk 6's (net/annex/receipt_lines.gd); the header and
## footer are ui/strings.gd ANNEX_SIGNS. In first person it rides lower centre
## on the FirstPerson camera, drawn over the world; otherwise it sits in the
## body's right hand. It frees itself when it's done.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Props = preload("res://props/office_props.gd")
const _Strings = preload("res://ui/strings.gd")

const WIDTH: float = 0.13
const PAPER := Color(0.99, 0.98, 0.95)
const PRINT := Color(0.2, 0.2, 0.26)
## Texture pixels per line of print.
const LINE_PX: int = 30


## The local player's slip.
static func show(lines: PackedStringArray, total_line: String, at: float, seconds: float = 4.0) -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	var me: Node3D = null
	var net := tree.root.get_node_or_null("Net") if tree != null else null
	var id := str(net.call("local_peer_id")) if net != null else ""
	for node: Node in tree.get_nodes_in_group("players") if tree != null else []:
		if str(node.name) == id:
			me = node as Node3D
	if me == null:
		return null
	# Lower centre of your view in first person; in your hand over the shoulder.
	return show_for(me, lines, total_line, at, seconds, _Props.sees_first_person(me))


static func show_for(player: Node3D, lines: PackedStringArray, total_line: String, at: float, seconds: float = 4.0, first_person: bool = true) -> Node3D:
	var slip := Slip.new()
	slip.name = "ReceiptSlip"
	slip.build(lines, total_line, at, seconds)
	var camera := player.get_node_or_null("Visual/Head/FirstPerson") as Node3D
	if first_person and camera != null:
		camera.add_child(slip)
		slip.position = Constants.RECEIPT_FIRST_PERSON_OFFSET
		slip.rotation = Vector3(0.35, 0.0, 0.0)
		slip.set_on_top(true)
	else:
		var body := player.get_node_or_null("Visual/CartoonBody") as Node3D
		var arms: Array = body.get("_arms") if body != null and "_arms" in body else []
		var hand: Node3D = (arms[1] as Node3D) if arms.size() >= 2 else player
		hand.add_child(slip)
		slip.position = Vector3(0.0, -0.58, -0.06)
		slip.rotation = Vector3(-1.1, 0.0, 0.0)
	# Posed for this moment before its first frame is drawn, and only now that it is in
	# the tree: a slip shown late (after a stall, or a receipt that crossed a laggy
	# link) chatters on its very first pose, and the printer's sound is placed at the
	# slip's global position, which a node outside the tree doesn't have.
	slip.call("_process", 0.0)
	return slip


class Slip extends Node3D:
	var printed: int = 0
	var _start: float
	var _seconds: float
	var _lines := PackedStringArray()
	var _length: float
	var _strip: Node3D
	var _material: StandardMaterial3D
	var _viewport: SubViewport
	var _ticks: int = 0

	func build(lines: PackedStringArray, total_line: String, at: float, seconds: float) -> void:
		_start = at
		_seconds = seconds
		_lines = PackedStringArray()
		for line: String in _Strings.ANNEX_SIGNS["receipt_header"].split("\n"):
			_lines.append(line)
		_lines.append("")
		_lines.append_array(lines)
		_lines.append("")
		_lines.append(total_line)
		var total_index := _lines.size() - 1
		_lines.append("")
		for line: String in _Strings.ANNEX_SIGNS["receipt_footer"].split("\n"):
			_lines.append(line)
		var width_px := Constants.FORM_TEXTURE_PX + Constants.FORM_TEXTURE_PX / 4
		var height_px := LINE_PX * (_lines.size() + 2)
		_length = WIDTH * float(height_px) / float(width_px)
		_viewport = SubViewport.new()
		_viewport.size = Vector2i(width_px, height_px)
		_viewport.disable_3d = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(_viewport)
		var text := Print.new()
		text.lines = _lines
		text.total_index = total_index
		text.size = Vector2(_viewport.size)
		_viewport.add_child(text)
		_material = StandardMaterial3D.new()
		_material.albedo_texture = _viewport.get_texture()
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.roughness = 0.9
		_strip = Node3D.new()
		_strip.name = "Strip"
		add_child(_strip)
		var view := MeshInstance3D.new()
		view.name = "Paper"
		view.mesh = _curled_mesh(_length)
		view.material_override = _material
		view.set_meta("keep_material", true)
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_strip.add_child(view)
		set_process(true)

	func set_on_top(on: bool) -> void:
		_material.no_depth_test = on
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if on else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED
		_material.render_priority = 3 if on else 0

	## A strip from y 0 down to -length, curling back at the top end like fresh
	## thermal paper does, its texture running top to bottom.
	func _curled_mesh(length: float) -> ArrayMesh:
		var segments := 24
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var normals := PackedVector3Array()
		var points: Array[Vector3] = []
		for step: int in segments + 1:
			var k := float(step) / float(segments)
			var y := -k * length
			# The first sixth curls back; the rest has a slight bow.
			var curl := clampf(1.0 - k / 0.16, 0.0, 1.0)
			var z := -curl * curl * WIDTH * 0.6 + sin(k * PI) * 0.006
			points.append(Vector3(0.0, y + curl * curl * WIDTH * 0.25, z))
		for step: int in segments:
			var a := points[step]
			var b := points[step + 1]
			var va := float(step) / float(segments)
			var vb := float(step + 1) / float(segments)
			var quad := [
				[Vector3(-WIDTH * 0.5, a.y, a.z), Vector2(0.0, va)], [Vector3(WIDTH * 0.5, a.y, a.z), Vector2(1.0, va)],
				[Vector3(WIDTH * 0.5, b.y, b.z), Vector2(1.0, vb)], [Vector3(-WIDTH * 0.5, b.y, b.z), Vector2(0.0, vb)],
			]
			for index: int in [0, 1, 2, 0, 2, 3]:
				vertices.append(quad[index][0])
				uvs.append(quad[index][1])
				normals.append(Vector3(0.0, 0.0, 1.0))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh

	## Fed up out of the printer a line at a time, ticking, held, then dropped away.
	func _process(_delta: float) -> void:
		var t := _Props.now() - _start
		var feed := clampf(t / (Constants.RECEIPT_LINE_SECONDS * float(_lines.size())), 0.0, 1.0)
		var lines_out := int(feed * float(_lines.size()))
		if lines_out > _ticks and t >= 0.0:
			# The printer chatters once a burst (every few lines), not per line.
			if _ticks % 6 == 0 and t - float(_ticks) * Constants.RECEIPT_LINE_SECONDS < 0.5:
				_Props._play_sfx(self, "receipt_print", global_position)
			_ticks = lines_out
		var hold_end := Constants.RECEIPT_LINE_SECONDS * float(_lines.size()) + _seconds
		var drop := clampf((t - hold_end) / 0.4, 0.0, 1.0)
		# The strip's top rises from below the view as it feeds.
		_strip.position = Vector3(0.0, -_length + _length * feed - drop * 0.3, 0.0)
		visible = t >= 0.0
		if drop >= 1.0:
			queue_free()


## The slip's print: centered lines in the printer's small type.
class Print extends Control:
	var lines := PackedStringArray()
	## Which line is the total, printed big.
	var total_index: int = -1

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), PAPER)
		var font := ThemeDB.fallback_font
		for index: int in lines.size():
			var y := float(LINE_PX) * (float(index) + 1.5)
			var line := lines[index]
			var big := index == total_index
			draw_string(font, Vector2(6.0, y), line, HORIZONTAL_ALIGNMENT_CENTER, size.x - 12.0, 26 if big else 19, PRINT)
