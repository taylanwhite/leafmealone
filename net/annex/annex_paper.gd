extends RefCounted

## Authority: local, cosmetic. Plain stand-ins for the Form 27-B clipboard and the
## till slip (props/form_27b.gd and props/receipt_slip.gd, R2 chunk 5), with the
## same calls (gap-specs/nice_boys.json contract C11), used only while those
## files aren't in the build. The clipboard rides in the lower left of whatever
## camera is current, drawn over the world: a row of boxes, each in its window's
## color with the window's pictogram, inked red as they're stamped, and the
## green APPROVED, NICELY across it when it's done. No text tells you what to
## do: the boxes and the room's pictograms are the instructions.

const _Icons = preload("res://ui/icons.gd")
const _Strings = preload("res://ui/strings.gd")
const BOARD := Color(0.55, 0.36, 0.2)
const PAPER := Color(0.97, 0.96, 0.91)
const INK := Color(0.82, 0.12, 0.16)
const GREEN := Color(0.16, 0.6, 0.26)
const GLOW := Color(1.0, 0.86, 0.4)
## Where the clipboard rests in the camera's space, and how it's tilted.
const REST := Vector3(-0.27, -0.19, -0.52)
const TILT := Vector3(-0.42, 0.32, 0.08)
## Off the bottom of the view, where it slides in from.
const AWAY := Vector3(-0.27, -0.55, -0.52)
const BOX_SIZE: float = 0.036
const BOX_GAP: float = 0.01
const PER_ROW: int = 4


static func make(boxes: PackedStringArray, looks: Dictionary) -> Node3D:
	var form := Clipboard.new()
	form.name = "Form27B"
	form.looks = looks
	form.boxes = boxes
	form.build()
	return form


static func make_receipt() -> Node3D:
	var slip := Slip.new()
	slip.name = "ReceiptSlip"
	return slip


## Drawing helpers, shared by the outer script and its inner classes.
class Ink:
	static func flat_material(color: Color, priority: int, glow_energy: float = 0.0) -> StandardMaterial3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.render_priority = priority
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if glow_energy > 0.0:
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = glow_energy
		return material

	static func quad(parent: Node3D, size: Vector2, at: Vector3, color: Color, priority: int) -> MeshInstance3D:
		var mesh := QuadMesh.new()
		mesh.size = size
		var view := MeshInstance3D.new()
		view.mesh = mesh
		view.material_override = Ink.flat_material(color, priority)
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.position = at
		view.set_meta("keep_material", true)
		parent.add_child(view)
		return view

	static func label(parent: Node3D, text: String, at: Vector3, font_size: int, color: Color, priority: int) -> Label3D:
		var out := Label3D.new()
		out.text = text
		out.font_size = font_size
		out.pixel_size = 0.00035
		out.modulate = color
		out.outline_size = 0
		out.no_depth_test = true
		out.render_priority = priority
		out.double_sided = true
		out.shaded = false
		out.position = at
		parent.add_child(out)
		return out


## Follows the current camera: parented to it, eased toward its resting spot.
class Follower extends Node3D:
	var rest := REST
	var tilt := TILT
	var shown: bool = true
	var _camera: Camera3D

	func _process(delta: float) -> void:
		var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
		if camera != null and camera != _camera:
			_camera = camera
			var keep := transform
			if get_parent() != null:
				get_parent().remove_child(self)
			camera.add_child(self)
			transform = keep
		var want := rest if shown else AWAY
		position = position.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
		rotation = tilt


class Clipboard extends Follower:
	var looks: Dictionary = {}
	var boxes: PackedStringArray = PackedStringArray()
	var stamped: int = 0
	var approved: bool = false
	## Approved by closing time, not the Head NICE BOY: a different stamp.
	var after_hours: bool = false
	var _boxes_root: Node3D
	var _approved_mark: Label3D
	var _glow: MeshInstance3D
	var _fast_tab: MeshInstance3D
	var _stamp_at: float = -100.0

	func build() -> void:
		position = AWAY
		_glow = Ink.quad(self, Vector2(0.236, 0.31), Vector3(0.0, 0.0, -0.002), GLOW, 1)
		_glow.visible = false
		Ink.quad(self, Vector2(0.22, 0.294), Vector3.ZERO, BOARD, 2)
		Ink.quad(self, Vector2(0.196, 0.25), Vector3(0.0, -0.012, 0.001), PAPER, 3)
		Ink.quad(self, Vector2(0.07, 0.022), Vector3(0.0, 0.14, 0.002), Color(0.7, 0.7, 0.74), 4)
		Ink.label(self, _Strings.ANNEX_UI["form_title"], Vector3(0.0, 0.098, 0.003), 72, Color(0.2, 0.18, 0.24), 6)
		Ink.label(self, _Strings.ANNEX_UI["form_sub"], Vector3(0.0, 0.074, 0.003), 36, Color(0.35, 0.32, 0.4), 6)
		_boxes_root = Node3D.new()
		_boxes_root.name = "Boxes"
		add_child(_boxes_root)
		_approved_mark = Ink.label(self, _Strings.ANNEX_UI["approved"], Vector3(0.0, -0.075, 0.006), 64, GREEN, 9)
		_approved_mark.rotation.z = 0.28
		_approved_mark.visible = false
		_fast_tab = Ink.quad(self, Vector2(0.03, 0.05), Vector3(0.118, 0.08, 0.0), Color(0.42, 0.33, 0.74), 2)
		_fast_tab.visible = false
		_layout()

	func set_progress(new_stamped: int, new_boxes: PackedStringArray, new_approved: bool, at: float) -> void:
		var more := new_stamped > stamped or (new_approved and not approved)
		stamped = new_stamped
		boxes = new_boxes
		approved = new_approved
		if more:
			_stamp_at = at
		_layout()

	func glow(on: bool) -> void:
		_glow.visible = on

	func fast_pass(on: bool) -> void:
		_fast_tab.visible = on

	func punch_card(_visits: int) -> void:
		pass

	func attach_first_person(_player: Node3D) -> void:
		shown = true

	func attach_hand(_player: Node3D) -> void:
		shown = true

	func _process(delta: float) -> void:
		super(delta)
		# A little bump when a stamp lands.
		var age := Net.server_time() - _stamp_at
		if age >= 0.0 and age < 0.25:
			position.y += sin(age / 0.25 * PI) * -0.012

	func _layout() -> void:
		for child: Node in _boxes_root.get_children():
			child.queue_free()
		var count := boxes.size()
		for index: int in count:
			var row := floori(float(index) / PER_ROW)
			var in_row := mini(count - row * PER_ROW, PER_ROW)
			var col := index - row * PER_ROW
			var width := float(in_row) * BOX_SIZE + float(in_row - 1) * BOX_GAP
			var x := -width * 0.5 + BOX_SIZE * 0.5 + float(col) * (BOX_SIZE + BOX_GAP)
			var y := 0.03 - float(row) * (BOX_SIZE + BOX_GAP + 0.004)
			var look: Dictionary = looks.get(boxes[index], {})
			var color: Color = look.get("color", Color(0.6, 0.6, 0.6))
			Ink.quad(_boxes_root, Vector2(BOX_SIZE, BOX_SIZE), Vector3(x, y, 0.004), color, 5)
			Ink.quad(_boxes_root, Vector2(BOX_SIZE - 0.006, BOX_SIZE - 0.006), Vector3(x, y, 0.005), PAPER.lerp(color, 0.12), 6)
			var icon_id := str(look.get("icon_id", ""))
			if _Icons.has(icon_id):
				var icon := Sprite3D.new()
				icon.texture = _Icons.texture(icon_id)
				icon.pixel_size = (BOX_SIZE - 0.008) / maxf(float(icon.texture.get_width()), 1.0)
				icon.no_depth_test = true
				icon.render_priority = 7
				icon.shaded = false
				icon.double_sided = true
				icon.position = Vector3(x, y, 0.006)
				_boxes_root.add_child(icon)
			if index < stamped:
				var ink := Ink.quad(_boxes_root, Vector2(BOX_SIZE * 0.9, BOX_SIZE * 0.9), Vector3(x + 0.002, y - 0.002, 0.007), Color(INK, 0.78), 8)
				ink.rotation.z = 0.35 + float(index) * 0.7
		_approved_mark.visible = approved
		_approved_mark.text = _Strings.ANNEX_UI["after_hours" if after_hours else "approved"]
		_approved_mark.modulate = Color(0.75, 0.2, 0.2) if after_hours else GREEN


## The till slip: prints line by line, held low in the middle of the view, then
## drops away.
class Slip extends Follower:
	var _text: Label3D
	var _lines: PackedStringArray = PackedStringArray()
	var _total: String = ""
	var _at: float = 0.0
	var _seconds: float = 4.0
	var _paper: MeshInstance3D
	var _printed: int = -1

	func show_slip(lines: PackedStringArray, total_line: String, at: float, seconds: float = 4.0) -> void:
		rest = Vector3(0.02, -0.12, -0.46)
		tilt = Vector3(-0.3, -0.05, -0.04)
		position = Vector3(0.02, -0.5, -0.46)
		_lines = lines
		_total = total_line
		_at = at
		_seconds = seconds
		_paper = Ink.quad(self, Vector2(0.15, 0.2), Vector3(0.0, 0.0, 0.0), Color(0.98, 0.97, 0.93), 2)
		_text = Ink.label(self, "", Vector3(0.0, 0.0, 0.002), 30, Color(0.18, 0.18, 0.22), 6)
		_text.width = 400.0
		_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_text.position = Vector3(0.0, 0.09, 0.002)

	func _process(delta: float) -> void:
		super(delta)
		if _text == null:
			return
		var age := Net.server_time() - _at
		var all := PackedStringArray([_Strings.RECEIPT_FORMAT["header"], ""])
		all.append_array(_lines)
		all.append("")
		all.append(_total)
		all.append(_Strings.RECEIPT_FORMAT["waived"])
		var show_count := clampi(int(age / 0.18) + 1, 1, all.size())
		if show_count != _printed:
			_printed = show_count
			_text.text = "\n".join(all.slice(0, show_count))
			var sfx := get_tree().get_first_node_in_group("sfx")
			if sfx != null and show_count > 1 and show_count <= all.size():
				sfx.call("play", "ui_tick")
		if age > _seconds:
			shown = false
		if age > _seconds + 0.6:
			queue_free()
