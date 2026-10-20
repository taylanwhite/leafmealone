extends Node3D

## Dev tool, local only. Renders one art subject from four angles into a single
## PNG so a model can be judged and iterated on without playing the game:
##
##   Godot --path . res://tools/studio/studio.tscn -- --subject=trees --out=build/art/trees.png
##
## The subject stands on grass under the game's own sky, sun, and post effects
## (levels/shared_look.gd). Views: a hero three-quarter shot, the side, from
## above, and a close-up. Works with the window covered: it forces each draw.
## Subjects are listed in _build().

const _SharedLook = preload("res://levels/shared_look.gd")
const _Surfaces = preload("res://props/surfaces.gd")
const _Trees = preload("res://props/trees.gd")
const VIEW_SIZE := Vector2i(720, 720)

var _subject := "trees"
var _out := "build/art/studio.png"
var _options: Dictionary = {}


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--subject="):
			_subject = argument.trim_prefix("--subject=")
		elif argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--") and argument.contains("="):
			var pair := argument.trim_prefix("--").split("=", true, 1)
			_options[pair[0]] = pair[1]
	_stage()
	var content := Node3D.new()
	content.name = "Subject"
	add_child(content)
	_build(content)
	_SharedLook.apply(self)
	await _render(content)
	get_tree().quit()


func _stage() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = Environment.new()
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ground.mesh = plane
	ground.material_override = _Surfaces.material("grass", Color(0.4, 0.56, 0.24))
	ground.set_meta("keep_material", true)
	add_child(ground)


## Every subject the studio knows. Add one here to iterate on a new model.
func _build(root: Node3D) -> void:
	match _subject:
		"trees":
			var crowns := ["orange", "red", "yellow", "turning", "rust"]
			for index: int in crowns.size():
				_Trees.spawn(root, Vector3(float(index) * 7.0 - 14.0, 0.0, 0.0), 7.0, "broadleaf", crowns[index], index)
			_Trees.spawn(root, Vector3(0.0, 0.0, -9.0), 9.0, "pine", "", 0)
			_Trees.spawn(root, Vector3(-9.0, 0.0, -8.0), 8.0, "pine", "", 1)
		"tree":
			_Trees.spawn(root, Vector3.ZERO, 7.0, str(_options.get("kind", "broadleaf")), str(_options.get("crown", "orange")), int(_options.get("variant", "0")))
		_:
			push_error("[Studio] no subject called %s" % _subject)


func _render(content: Node3D) -> void:
	var bounds := _bounds(content)
	var center := bounds.get_center()
	var reach := maxf(bounds.size.length() * 0.5, 0.5)
	var views := [
		# Hero: three-quarter, a little above eye level.
		{"from": center + Vector3(0.75, 0.25, 1.0).normalized() * reach * 2.3, "at": center, "fov": 40.0},
		# Side.
		{"from": center + Vector3(-1.0, 0.05, 0.0) * reach * 2.4, "at": center, "fov": 40.0},
		# From above.
		{"from": center + Vector3(0.3, 1.2, 0.9).normalized() * reach * 2.6, "at": center, "fov": 40.0},
		# Close-up, toward the upper part where the detail is.
		{"from": center + Vector3(0.6, 0.35, 1.0).normalized() * reach * 0.95 + Vector3(0.0, bounds.size.y * 0.15, 0.0), "at": center + Vector3(0.0, bounds.size.y * 0.15, 0.0), "fov": 45.0},
	]
	var viewports: Array[SubViewport] = []
	for view: Dictionary in views:
		var viewport := SubViewport.new()
		viewport.size = VIEW_SIZE
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var camera := Camera3D.new()
		camera.fov = float(view["fov"])
		viewport.add_child(camera)
		camera.look_at_from_position(view["from"], view["at"], Vector3.UP)
		camera.current = true
		viewports.append(viewport)
	# A few frames so shadows and effects settle.
	for _frame: int in 6:
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	var sheet := Image.create(VIEW_SIZE.x * 2, VIEW_SIZE.y * 2, false, Image.FORMAT_RGBA8)
	for index: int in viewports.size():
		var shot := viewports[index].get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, VIEW_SIZE), Vector2i(index % 2, index / 2) * VIEW_SIZE)
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var error := sheet.save_png(_out)
	print("[Studio] %s -> %s (%s)" % [_subject, _out, error_string(error)])


func _bounds(root: Node3D) -> AABB:
	var total := AABB()
	var first := true
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		var box := visual.global_transform * visual.get_aabb()
		total = box if first else total.merge(box)
		first = false
	return total if not first else AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
