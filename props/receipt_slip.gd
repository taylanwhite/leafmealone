extends RefCounted

## Authority: local, cosmetic. The till slip you get back at the curb (docs/GAME.md
## "Satellite Annex B"): a curling strip of thermal paper fed up into your view
## line by line with the printer's chatter, held up for a few seconds, then
## pocketed.
##
##   ReceiptSlip.show(lines, total_line, at, seconds := 4.0)   # the local player's, in their current view
##   ReceiptSlip.show_for(player, lines, total_line, at, seconds, first_person)
##
## The words are R2 chunk 6's (net/annex/receipt_lines.gd); the header and
## footer are ui/strings.gd ANNEX_SIGNS. In first person it is held up lower
## centre on the FirstPerson camera (Constants.ANNEX_RECEIPT_HOLD), the whole slip
## in view and drawn over the world; otherwise it sits in the body's right hand.
## It frees itself when it's done.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Props = preload("res://props/office_props.gd")
const _Strings = preload("res://ui/strings.gd")

const WIDTH: float = 0.2
const PAPER := Color(0.99, 0.98, 0.95)
const PRINT := Color(0.2, 0.2, 0.26)
## Texture pixels per line of print, and across.
const LINE_PX: int = 30
const WIDTH_PX: int = 448
## Blank paper above the header: the curl at the top end takes it (R2b: the
## header used to curl away out of sight).
const TOP_BLANK_LINES: int = 2


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
	# Held up in front of you in first person; in your hand over the shoulder.
	return show_for(me, lines, total_line, at, seconds, _Props.sees_first_person(me))


## How many rows the slip prints for these lines: blank lead, header, a gap, the
## lines, a gap, the total, a gap, footer (as Slip.build lays them out).
static func row_count(lines: PackedStringArray) -> int:
	var header := str(_Strings.ANNEX_SIGNS["receipt_header"]).split("\n").size()
	var footer := str(_Strings.ANNEX_SIGNS["receipt_footer"]).split("\n").size()
	return TOP_BLANK_LINES + header + 1 + lines.size() + 3 + footer


## Seconds from `at` until the slip is pocketed and gone.
static func duration(lines: PackedStringArray, seconds: float = 4.0) -> float:
	return Constants.RECEIPT_LINE_SECONDS * float(row_count(lines)) + seconds + Constants.ANNEX_RECEIPT_POCKET


static func show_for(player: Node3D, lines: PackedStringArray, total_line: String, at: float, seconds: float = 4.0, first_person: bool = true) -> Node3D:
	var slip := Slip.new()
	slip.name = "ReceiptSlip"
	# R2b: the caption stack's lines wait while you read it (ui/caption_stack.gd).
	slip.add_to_group("caption_blockers")
	slip.build(lines, total_line, at, seconds)
	var camera := player.get_node_or_null("Visual/Head/FirstPerson") as Node3D
	# Seated in the shuttle home (let out at closing time, R2c van), your view is the
	# stage camera's: the slip is held up in front of that one instead.
	var stage := player.get_node_or_null("CameraRig/StageCam") as Camera3D
	if stage != null and stage.current and player.is_multiplayer_authority():
		camera = stage
		first_person = true
	if first_person and camera != null:
		camera.add_child(slip)
		# Its middle at the hold point: the whole strip, top to bottom, in view.
		slip.position = Constants.ANNEX_RECEIPT_HOLD + Vector3(0.0, slip.length() * 0.5, 0.0)
		slip.rotation = Vector3(Constants.ANNEX_RECEIPT_TILT, 0.0, 0.0)
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
	slip.remember_rest()
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
	var _rest_position := Vector3.ZERO
	var _rest_rotation := Vector3.ZERO

	func build(lines: PackedStringArray, total_line: String, at: float, seconds: float) -> void:
		_start = at
		_seconds = seconds
		_lines = PackedStringArray()
		for blank: int in TOP_BLANK_LINES:
			_lines.append("")
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
		var height_px := LINE_PX * (_lines.size() + 1)
		_length = WIDTH * float(height_px) / float(WIDTH_PX)
		_viewport = SubViewport.new()
		_viewport.size = Vector2i(WIDTH_PX, height_px)
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

	func length() -> float:
		return _length

	func remember_rest() -> void:
		_rest_position = position
		_rest_rotation = rotation
		_process(0.0)

	func set_on_top(on: bool) -> void:
		_material.no_depth_test = on
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if on else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED
		_material.render_priority = 3 if on else 0

	## A strip from y 0 down to -length, curling back at the top end like fresh
	## thermal paper does, its texture running top to bottom. The curl stays
	## within the blank lead at the top, so every printed line lies flat.
	func _curled_mesh(length: float) -> ArrayMesh:
		var segments := 28
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var normals := PackedVector3Array()
		var points: Array[Vector3] = []
		var curl_share := float(LINE_PX * TOP_BLANK_LINES) / float(LINE_PX * (_lines.size() + 1))
		for step: int in segments + 1:
			var k := float(step) / float(segments)
			var y := -k * length
			var curl := clampf(1.0 - k / maxf(curl_share, 0.02), 0.0, 1.0)
			var z := -curl * curl * WIDTH * 0.35 + sin(k * PI) * 0.004
			points.append(Vector3(0.0, y + curl * curl * WIDTH * 0.12, z))
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

	## Fed up out of the printer a line at a time, ticking; held up to read;
	## then pocketed, down and to the right, and gone.
	func _process(_delta: float) -> void:
		if not is_inside_tree():
			return
		var t := _Props.now() - _start
		var feed_time := Constants.RECEIPT_LINE_SECONDS * float(_lines.size())
		var feed := clampf(t / feed_time, 0.0, 1.0)
		var lines_out := int(feed * float(_lines.size()))
		if lines_out > _ticks and t >= 0.0:
			# The printer chatters once a burst (every few lines), not per line.
			if _ticks % 6 == 0 and t - float(_ticks) * Constants.RECEIPT_LINE_SECONDS < 0.5:
				_Props._play_sfx(self, "receipt_print", global_position)
			_ticks = lines_out
		var hold_end := feed_time + _seconds
		var pocket := clampf((t - hold_end) / Constants.ANNEX_RECEIPT_POCKET, 0.0, 1.0)
		var away := pocket * pocket
		# The strip's top rises from below the view as it feeds.
		_strip.position = Vector3(0.0, -_length + _length * (1.0 - pow(1.0 - feed, 2.0)), 0.0)
		position = _rest_position + Vector3(0.22 * away, -0.32 * away, 0.04 * away)
		rotation = _rest_rotation + Vector3(-0.5 * away, 0.0, -0.7 * away)
		visible = t >= 0.0
		if pocket >= 1.0:
			queue_free()


## The slip's print: centered lines in the printer's small type, each shrunk
## until it fits the paper's width (R2b: long lines ran off the edge).
class Print extends Control:
	var lines := PackedStringArray()
	## Which line is the total, printed big.
	var total_index: int = -1

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), PAPER)
		var font := ThemeDB.fallback_font
		var room := size.x - 28.0
		for index: int in lines.size():
			var y := float(LINE_PX) * (float(index) + 1.0)
			var line := lines[index]
			var big := index == total_index
			var font_size := 26 if big else 20
			while font_size > 11 and font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > room:
				font_size -= 1
			draw_string(font, Vector2(14.0, y), line, HORIZONTAL_ALIGNMENT_CENTER, room, font_size, PRINT)
