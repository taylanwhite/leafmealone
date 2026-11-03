extends RefCounted

## Authority: local, cosmetic. Form 27-B: Request To Be Nice, the caught
## player's HUD at Satellite Annex B (docs/GAME.md "Satellite Annex B"). A real
## 3D clipboard, held lower left in your own first-person view and in your hand
## for everyone else: a row of boxes, one per window still to visit, each with
## that window's pictogram in its color, stamped left to right. It never says
## what to do: the next empty box's picture is the window to find.
##
##   var form: Node3D = Form27B.make(boxes, looks)   # boxes: window ids, looks: id -> {icon, color}
##   form.set_progress(stamped, boxes, approved, at) # carbons are boxes on the end
##   form.glow(on); form.fast_pass(on); form.punch_card(visits)
##   form.attach_first_person(player); form.attach_hand(player)
##
## The paper is a SubViewport (Constants.FORM_TEXTURE_PX wide) drawn in 2D:
## the heading, the boxes and their pictograms, the purple ink of a stamp
## punching in, a red smudge wiping a box that was lost, the carbon copies
## (dashed, "complimentary"), and APPROVED, NICELY slammed across it. In first
## person it draws on top of the world, so a counter or a wall never cuts it.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Props = preload("res://props/office_props.gd")
const _Strings = preload("res://ui/strings.gd")

const BOARD := Color(0.55, 0.36, 0.2)
const PAPER := Color(0.98, 0.97, 0.93)
const INK := Color(0.42, 0.2, 0.64)
const SMUDGE := Color(0.8, 0.2, 0.22)
const LINE := Color(0.25, 0.25, 0.3)
const APPROVED := Color(0.85, 0.15, 0.25)
## The board, in meters: width and height (the paper is a little smaller).
const BOARD_SIZE := Vector2(0.23, 0.31)
const PAPER_SIZE := Vector2(0.205, 0.27)


static func make(boxes: PackedStringArray, looks: Dictionary) -> Node3D:
	var form := Form.new()
	form.name = "Form27B"
	form.build(boxes, looks)
	return form


## What the paper shows, drawn into the SubViewport whenever it changes.
class Paper extends Control:
	var boxes := PackedStringArray()
	var looks: Dictionary = {}
	var stamped: int = 0
	var approved: bool = false
	var carbon_from: int = 999
	var stamp_at: float = -1000.0
	var stamp_box: int = -1
	var smudge_at: float = -1000.0
	var smudge_box: int = -1
	var approved_at: float = -1000.0
	var fast: bool = false
	var visits: int = 0
	var after_hours: bool = false

	func _draw() -> void:
		var size_px := size
		var font := ThemeDB.fallback_font
		var t := Form.clock()
		draw_rect(Rect2(Vector2.ZERO, size_px), PAPER)
		# Ruled lines faint across the bottom, a margin down the left.
		for line: int in 6:
			var y := size_px.y * (0.82 + float(line) * 0.03)
			draw_line(Vector2(size_px.x * 0.08, y), Vector2(size_px.x * 0.92, y), Color(0.75, 0.82, 0.92), 1.0)
		draw_line(Vector2(size_px.x * 0.05, 0.0), Vector2(size_px.x * 0.05, size_px.y), Color(0.95, 0.65, 0.65), 1.0)
		var title := _Strings.ANNEX_SIGNS["form_title"]
		draw_string(font, Vector2(0.0, size_px.y * 0.1), title, HORIZONTAL_ALIGNMENT_CENTER, size_px.x, int(size_px.x * 0.13), LINE)
		draw_string(font, Vector2(0.0, size_px.y * 0.155), _Strings.ANNEX_SIGNS["form_subtitle"], HORIZONTAL_ALIGNMENT_CENTER, size_px.x, int(size_px.x * 0.065), LINE)
		draw_string(font, Vector2(0.0, size_px.y * 0.195), _Strings.ANNEX_SIGNS["form_triplicate"], HORIZONTAL_ALIGNMENT_CENTER, size_px.x, int(size_px.x * 0.05), Color(0.45, 0.45, 0.5))
		# The boxes: two columns, as many rows as it takes.
		var count := boxes.size()
		var columns := 2
		var rows := maxi(1, int(ceil(float(count) / float(columns))))
		var top := size_px.y * 0.23
		var area := Vector2(size_px.x * 0.84, size_px.y * 0.56)
		var cell := Vector2(area.x / float(columns), minf(area.y / float(rows), area.x / float(columns)))
		var left := (size_px.x - cell.x * float(columns)) * 0.5
		for index: int in count:
			var at := Vector2(left + cell.x * float(index % columns), top + cell.y * float(index / columns))
			var box := Rect2(at + cell * 0.07, cell * 0.86)
			_draw_box(index, box, t)
		if fast:
			var badge := Rect2(Vector2(size_px.x * 0.62, size_px.y * 0.02), Vector2(size_px.x * 0.34, size_px.y * 0.05))
			draw_rect(badge, Color(0.15, 0.55, 0.85))
			draw_string(font, badge.position + Vector2(0.0, badge.size.y * 0.8), _Strings.ANNEX_SIGNS["form_fast_pass"], HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, int(badge.size.y * 0.75), Color.WHITE)
		# The punch card's holes along the bottom: one per visit, five to a card.
		if visits > 0:
			for hole: int in 5:
				var center := Vector2(size_px.x * (0.3 + 0.1 * float(hole)), size_px.y * 0.955)
				draw_circle(center, size_px.x * 0.025, LINE if hole < (visits - 1) % 5 + 1 else Color(0.85, 0.85, 0.85))
		if approved:
			_draw_approved(t)

	func _draw_box(index: int, box: Rect2, t: float) -> void:
		var id := boxes[index]
		var look: Dictionary = looks.get(id, {})
		var color: Color = look.get("color", Color(0.5, 0.5, 0.55))
		var carbon := index >= carbon_from
		# A carbon copy is a dashed outline in carbon blue; a box, solid in its color.
		var outline := Color(0.25, 0.3, 0.6) if carbon else color
		if carbon:
			var steps := 10
			for side: int in 4:
				var a: Vector2 = [box.position, box.position + Vector2(box.size.x, 0.0), box.end, box.position + Vector2(0.0, box.size.y)][side]
				var b: Vector2 = [box.position + Vector2(box.size.x, 0.0), box.end, box.position + Vector2(0.0, box.size.y), box.position][side]
				for step: int in steps:
					if step % 2 == 0:
						draw_line(a.lerp(b, float(step) / float(steps)), a.lerp(b, float(step + 1) / float(steps)), outline, 2.0)
		else:
			draw_rect(Rect2(box.position, box.size), Color(color.r, color.g, color.b, 0.16))
			draw_rect(box, outline, false, 3.0)
		var icon := Form.flat_icon(str(look.get("icon", "")))
		var inset := box.grow(-box.size.x * 0.07)
		if icon != null:
			draw_texture_rect(icon, inset, false, Color(1, 1, 1, 0.9))
		else:
			draw_circle(box.get_center(), box.size.x * 0.25, color)
		if carbon:
			draw_string(ThemeDB.fallback_font, Vector2(box.position.x, box.end.y - box.size.y * 0.05), _Strings.ANNEX_SIGNS["form_carbon"], HORIZONTAL_ALIGNMENT_CENTER, box.size.x, int(box.size.x * 0.13), Color(0.25, 0.3, 0.6))
		# The ink: stamped boxes get the purple seal; the newest one punches in.
		var inked := index < stamped
		var smudging := index == smudge_box and t - smudge_at < Constants.FORM_SMUDGE_SECONDS
		if inked or smudging:
			var scale := 1.0
			var alpha := 0.85
			if index == stamp_box and t - stamp_at < Constants.FORM_STAMP_SECONDS:
				var k := clampf((t - stamp_at) / Constants.FORM_STAMP_SECONDS, 0.0, 1.0)
				scale = lerpf(1.6, 1.0, k)
				alpha = lerpf(0.2, 0.85, k)
			if smudging:
				var k := clampf((t - smudge_at) / Constants.FORM_SMUDGE_SECONDS, 0.0, 1.0)
				alpha = 0.85 * (1.0 - k)
				# Rubbed off sideways: the seal drags out into a red streak.
				draw_rect(Rect2(box.get_center() - Vector2(box.size.x * 0.4, box.size.y * 0.08), Vector2(box.size.x * 0.8 * k, box.size.y * 0.16)), Color(SMUDGE.r, SMUDGE.g, SMUDGE.b, 0.6 * (1.0 - k * 0.5)))
			_draw_seal(box.get_center(), box.size.x * 0.36 * scale, Color(INK.r, INK.g, INK.b, alpha), after_hours)

	## The Daisy Seal stamp: a ring with petals and a check through it.
	func _draw_seal(center: Vector2, radius: float, color: Color, hours: bool) -> void:
		for petal: int in 10:
			var angle := TAU * float(petal) / 10.0
			draw_circle(center + Vector2(cos(angle), sin(angle)) * radius * 0.82, radius * 0.24, color)
		draw_circle(center, radius * 0.7, Color(1.0, 1.0, 1.0, 0.0))
		draw_arc(center, radius * 0.62, 0.0, TAU, 24, color, radius * 0.16)
		draw_polyline(PackedVector2Array([center + Vector2(-0.32, 0.02) * radius, center + Vector2(-0.08, 0.28) * radius, center + Vector2(0.36, -0.3) * radius]), color, radius * 0.16)
		if hours:
			draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius * 1.15), _Strings.ANNEX_SIGNS["after_hours"], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, int(radius * 0.32), color)

	func _draw_approved(t: float) -> void:
		var k := clampf((t - approved_at) / Constants.FORM_STAMP_SECONDS, 0.0, 1.0)
		var scale := lerpf(1.8, 1.0, k)
		var size_px := size
		var center := Vector2(size_px.x * 0.5, size_px.y * 0.52)
		draw_set_transform(center, -0.35, Vector2(scale, scale))
		var plate := Rect2(Vector2(-size_px.x * 0.42, -size_px.y * 0.1), Vector2(size_px.x * 0.84, size_px.y * 0.2))
		var color := Color(APPROVED.r, APPROVED.g, APPROVED.b, lerpf(0.0, 0.9, k))
		draw_rect(plate, color, false, 5.0)
		var lines := _Strings.ANNEX_SIGNS["form_approved"].split("\n")
		for index: int in lines.size():
			draw_string(ThemeDB.fallback_font, Vector2(plate.position.x, plate.position.y + plate.size.y * (0.45 + 0.42 * float(index))), lines[index], HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, int(plate.size.y * 0.38), color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The clipboard itself.
class Form extends Node3D:
	static var _flat: Dictionary = {}
	var paper: Paper
	var _viewport: SubViewport
	var _paper_mesh: MeshInstance3D
	var _paper_material: StandardMaterial3D
	var _board: MeshInstance3D
	var _glow: bool = false
	var _animating_until: float = -1000.0
	var _first_person: bool = false

	static func clock() -> float:
		return _Props.now()

	## The pictogram as a plain image texture: the icons are imported for 3D
	## (compressed), and the paper's 2D canvas drew those as blank squares.
	static func flat_icon(id: String) -> Texture2D:
		if _flat.has(id):
			return _flat[id]
		var source := _Props.pictogram_texture(id)
		var made: Texture2D = null
		if source != null:
			var image := source.get_image()
			if image != null:
				if image.is_compressed():
					image.decompress()
				made = ImageTexture.create_from_image(image)
		_flat[id] = made
		return made

	func build(boxes: PackedStringArray, looks: Dictionary) -> void:
		var width := Constants.FORM_TEXTURE_PX
		_viewport = SubViewport.new()
		_viewport.name = "Paper"
		_viewport.size = Vector2i(width, int(float(width) * Constants.FORM_ASPECT))
		_viewport.transparent_bg = false
		_viewport.disable_3d = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(_viewport)
		paper = Paper.new()
		paper.size = Vector2(_viewport.size)
		paper.boxes = boxes
		paper.looks = looks
		_viewport.add_child(paper)
		var kit := _MeshKit.new()
		kit.box(Vector3.ZERO, Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.012), BOARD)
		kit.box(Vector3(0.0, BOARD_SIZE.y * 0.5 - 0.012, 0.012), Vector3(0.09, 0.035, 0.016), Color(0.78, 0.8, 0.84))
		_board = _Stylized.instance(kit.commit(), {"roughness": 0.7})
		_board.name = "Board"
		_board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_board)
		var quad := QuadMesh.new()
		quad.size = PAPER_SIZE
		_paper_mesh = MeshInstance3D.new()
		_paper_mesh.name = "Sheet"
		_paper_mesh.mesh = quad
		_paper_material = StandardMaterial3D.new()
		_paper_material.albedo_texture = _viewport.get_texture()
		_paper_material.roughness = 0.9
		_paper_material.emission_enabled = true
		_paper_material.emission = Color(1.0, 0.85, 0.35)
		_paper_material.emission_energy_multiplier = 0.0
		_paper_mesh.material_override = _paper_material
		_paper_mesh.set_meta("keep_material", true)
		_paper_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_paper_mesh.position = Vector3(0.0, -0.012, 0.0065)
		add_child(_paper_mesh)
		set_process(false)

	## stamped boxes of boxes are inked; boxes may have grown (carbons, a redirect).
	## Losing a stamp smudges it off; gaining one punches it in at at.
	func set_progress(stamped: int, boxes: PackedStringArray, approved: bool, at: float) -> void:
		var before := paper.stamped
		var had := paper.boxes.size()
		if boxes.size() > had and had > 0 and paper.carbon_from > had:
			paper.carbon_from = had
		paper.boxes = boxes
		if stamped > before:
			paper.stamp_box = stamped - 1
			paper.stamp_at = at
		elif stamped < before:
			paper.smudge_box = before - 1
			paper.smudge_at = at
		paper.stamped = clampi(stamped, 0, boxes.size())
		if approved and not paper.approved:
			paper.approved_at = at
		paper.approved = approved
		_animate_for(at + maxf(Constants.FORM_SMUDGE_SECONDS, Constants.FORM_STAMP_SECONDS) + 0.1)

	## Which boxes are carbon copies (from index on), when the caller knows.
	func set_carbons_from(index: int) -> void:
		paper.carbon_from = index
		_redraw()

	## Closing time's stamps say AFTER HOURS in the seal.
	func set_after_hours(on: bool) -> void:
		paper.after_hours = on
		_redraw()

	func glow(on: bool) -> void:
		_glow = on
		set_process(true)

	func fast_pass(on: bool) -> void:
		paper.fast = on
		_redraw()

	func punch_card(visit_count: int) -> void:
		paper.visits = visit_count
		_redraw()

	func _animate_for(until: float) -> void:
		_animating_until = maxf(_animating_until, until)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		paper.queue_redraw()
		set_process(true)

	func _redraw() -> void:
		paper.queue_redraw()
		if _viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	func _process(_delta: float) -> void:
		var t := clock()
		paper.queue_redraw()
		# An approved form glows warm, breathing, until it goes in the tray.
		_paper_material.emission_energy_multiplier = (0.35 + 0.25 * sin(t * 4.0)) if _glow else 0.0
		if t > _animating_until and not _glow:
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			set_process(false)

	## In your own first-person view: lower left, tilted up toward you, drawn over
	## the world (no counter, door or wall ever cuts it), never under a node that
	## hides (the camera is the FirstPerson one, not the body).
	func attach_first_person(player: Node3D) -> void:
		var camera := player.get_node_or_null("Visual/Head/FirstPerson") as Node3D if player != null else null
		if camera == null:
			camera = get_viewport().get_camera_3d() if is_inside_tree() else null
		if camera == null:
			return
		_reparent(camera)
		position = Constants.FORM_FIRST_PERSON_OFFSET
		rotation = Constants.FORM_FIRST_PERSON_TILT
		_first_person = true
		_on_top(true)

	## In the body's left hand, for everyone else and for your third-person view.
	func attach_hand(player: Node3D) -> void:
		var body := player.get_node_or_null("Visual/CartoonBody") as Node3D if player != null else null
		if body == null:
			body = player
		var arms: Array = body.get("_arms") if body != null and "_arms" in body else []
		var hand: Node3D = (arms[0] as Node3D) if arms.size() >= 2 else body
		if body != null and body.has_method("pose_part"):
			var prop_hand: Node3D = body.call("pose_part", "prop_hand")
			if prop_hand != null:
				hand = prop_hand
		_reparent(hand)
		position = Vector3(0.0, -0.56, -0.08)
		rotation = Vector3(-1.2, 0.0, 0.0)
		_first_person = false
		_on_top(false)

	func _reparent(parent: Node) -> void:
		if get_parent() != null:
			get_parent().remove_child(self)
		parent.add_child(self)

	## Drawn after everything, through walls: a view model's materials.
	func _on_top(on: bool) -> void:
		_paper_material.no_depth_test = on
		_paper_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if on else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_paper_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED
		_paper_material.render_priority = 2 if on else 0
		# A flat brown: the kit's vertex alpha is its sway (0), which would make a
		# see-through board.
		var board := StandardMaterial3D.new()
		board.albedo_color = BOARD
		board.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		board.no_depth_test = on
		board.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED
		board.render_priority = 1 if on else 0
		board.roughness = 0.7
		if on:
			_board.material_override = board
		else:
			_board.material_override = _Stylized.material({"roughness": 0.7})
