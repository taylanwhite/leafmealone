extends Node

## Dev tool, local only: the re-runnable generator for every UI icon
## (docs/ART.md, "Icons"). Each recipe in tools/studio/icon_recipes.gd becomes
## assets/icons/<id>.png in one sticker style: the game's own models from a fixed
## hero three-quarter angle under a warm key light and a cool fill, a transparent
## background, a chunky ink outline and a soft drop shadow.
##
##   Godot --path . res://tools/studio/icon_studio.tscn -- [--only=id1,id2] [--out=assets/icons] [--sheet=build/art/icons_sheet.png]
##
## Then run `Godot --headless --path . --import` once so new PNGs get their uid.
## Needs a window (real GPU), like studio.gd: it forces each draw, so a covered
## window is fine, but it can't run headless or in CI. CI only checks the files.
##
## How one icon is made:
## 1. The 3D subject (when the recipe has a builder) is built in its own world
##    and framed from its bounds along ICON_VIEW, rendered at 2x the output size
##    on a transparent background.
## 2. Flat layers (the badge disc or shield underneath, the upgrade sticker on
##    top, or a whole flat icon) are drawn in 2D at the same size.
## 3. POST_SHADER composites them on the GPU, dilates the alpha into the ink
##    outline and adds the drop shadow, then the result is read back and shrunk
##    to the output size with Lanczos.

const _Recipes = preload("res://tools/studio/icon_recipes.gd")
const _Icons = preload("res://ui/icons.gd")
const _SharedLook = preload("res://levels/shared_look.gd")
const _Seasons = preload("res://core/seasons.gd")

## The camera looks at every subject from here (toward the subject): front-right, above.
const ICON_VIEW := Vector3(0.75, 0.55, 1.0)
const FOV: float = 30.0
const KEY_ROTATION := Vector3(-40.0, -30.0, 0.0)
const KEY_ENERGY: float = 1.25
const FILL_ROTATION := Vector3(-25.0, 150.0, 0.0)
const FILL_COLOR := Color(0.75, 0.85, 1.0)
const FILL_ENERGY: float = 0.35
const AMBIENT_COLOR := Color(1.0, 0.94, 0.86)
const AMBIENT_ENERGY: float = 0.55
const EXPOSURE: float = 1.05
## Outline width and shadow drop, as a share of the output size (3 px and 4 px at 256).
const OUTLINE_SHARE: float = 1.0 / 85.0
const SHADOW_SHARE: float = 1.0 / 64.0
const SHADOW_ALPHA: float = 0.25
## Frames each pass is drawn before it is read back.
const SETTLE_FRAMES: int = 4

## Composites a flat base layer, the 3D subject and a flat top layer, then puts
## the ink outline (alpha dilated in 16 directions at two radii) and a drop
## shadow behind them. Inputs are premultiplied (that is how a transparent
## viewport stores them): the 3D layer in linear-ish light, the 2D layers in
## sRGB. Mixing happens in linear light; the output is straight alpha, written
## as-is (blend_disabled), with ink in fully transparent pixels so a later resize
## never pulls dark or white fringes in.
const POST_SHADER := """
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D subject : filter_linear, repeat_disable;
uniform sampler2D base_layer : filter_linear, repeat_disable;
uniform sampler2D top_layer : filter_linear, repeat_disable;
uniform bool has_subject = false;
uniform bool has_base = false;
uniform bool has_top = false;
uniform vec4 subject_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 texel = vec2(0.001953125);
uniform float outline_px = 6.0;
uniform float shadow_px = 8.0;
uniform float shadow_alpha = 0.25;
// Badges: the vignette's own ink ring, as a share of the outer outline (0 = none).
uniform float sticker_share = 0.0;
uniform vec3 sticker_ink = vec3(0.17, 0.14, 0.11);
uniform vec3 ink = vec3(0.17, 0.14, 0.11);

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

vec4 flat_at(sampler2D layer, vec2 uv) {
	vec4 t = texture(layer, uv);
	if (t.a <= 0.0001) {
		return vec4(0.0);
	}
	return vec4(to_linear(clamp(t.rgb / t.a, 0.0, 1.0)) * t.a, t.a);
}

vec4 subject_at(vec2 uv) {
	vec2 s = (uv - subject_rect.xy) / subject_rect.zw;
	if (s.x < 0.0 || s.y < 0.0 || s.x > 1.0 || s.y > 1.0) {
		return vec4(0.0);
	}
	vec4 t = texture(subject, s);
	return vec4(to_linear(t.rgb), t.a);
}

// The 3D layer's own outline, so a badge's vignette sits on its disc like a sticker.
float subject_ring(vec2 uv) {
	float a = 0.0;
	for (int i = 0; i < 16; i++) {
		float angle = 6.2831853 * float(i) / 16.0;
		vec2 dir = vec2(cos(angle), sin(angle)) * texel * outline_px * sticker_share;
		a = max(a, max(subject_at(uv + dir).a, subject_at(uv + dir * 0.5).a));
	}
	return a;
}

vec4 layer_at(vec2 uv, bool ringed) {
	vec4 c = vec4(0.0);
	if (has_base) {
		c = flat_at(base_layer, uv);
	}
	if (has_subject) {
		if (ringed && sticker_share > 0.0) {
			float ring = subject_ring(uv);
			c = vec4(to_linear(sticker_ink) * ring, ring) + c * (1.0 - ring);
		}
		vec4 s = subject_at(uv);
		c = s + c * (1.0 - s.a);
	}
	if (has_top) {
		vec4 t = flat_at(top_layer, uv);
		c = t + c * (1.0 - t.a);
	}
	return c;
}

float dilated(vec2 uv) {
	// The ring never reaches past the outer outline, so alpha skips it here.
	float a = layer_at(uv, false).a;
	for (int i = 0; i < 16; i++) {
		float angle = 6.2831853 * float(i) / 16.0;
		vec2 dir = vec2(cos(angle), sin(angle)) * texel;
		a = max(a, layer_at(uv + dir * outline_px, false).a);
		a = max(a, layer_at(uv + dir * outline_px * 0.5, false).a);
	}
	return a;
}

void fragment() {
	vec4 c = layer_at(UV, true);
	vec3 ink_linear = to_linear(ink);
	float outline = dilated(UV);
	vec3 color = c.rgb + ink_linear * outline * (1.0 - c.a);
	float alpha = c.a + outline * (1.0 - c.a);
	float shadow = dilated(UV - vec2(0.0, shadow_px) * texel) * shadow_alpha;
	color += ink_linear * shadow * (1.0 - alpha);
	alpha += shadow * (1.0 - alpha);
	COLOR = alpha > 0.0001 ? vec4(to_srgb(color / alpha), alpha) : vec4(ink, 0.0);
}
"""

## The minimal import sidecar for a new icon: Godot's --import fills in the uid
## and the rest and keeps these params. Never write a uid by hand.
const IMPORT_SIDECAR := """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
mipmaps/generate=true
detect_3d/compress_to=0
process/fix_alpha_border=true
"""

const SHEET_CELL := Vector2i(116, 150)
const SHEET_COLUMNS: int = 10


## Draws one flat layer through a draw_* func of icon_recipes.gd.
class Drawer extends Node2D:
	var recipes: Script
	var painter := ""
	var px := 0.0
	var recipe: Dictionary = {}

	func _draw() -> void:
		recipes.call(painter, self, px, recipe)


var _only: PackedStringArray = []
var _out := "res://assets/icons/"
var _sheet := ""
var _made := 0
var _failed := 0


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			_only = argument.trim_prefix("--only=").split(",", false)
		elif argument.begins_with("--out="):
			_out = _res_path(argument.trim_prefix("--out="))
			if not _out.ends_with("/"):
				_out += "/"
		elif argument.begins_with("--sheet="):
			_sheet = _res_path(argument.trim_prefix("--sheet="))
	# Autumn, the home season: no snow or spring tint on anything (critic C26).
	_Seasons.apply_look(1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	for id: String in _only:
		if not _Recipes.RECIPES.has(id):
			push_error("[IconStudio] no recipe called %s" % id)
			_failed += 1
	for id: String in _Recipes.RECIPES:
		if not _only.is_empty() and not _only.has(id):
			continue
		await _make(id, _Recipes.RECIPES[id])
	if _sheet != "":
		await _contact_sheet()
	print("[IconStudio] done: %d made, %d failed" % [_made, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _make(id: String, recipe: Dictionary) -> void:
	var px := int(recipe.get("px", 128))
	# Wide keycaps (chunk B) are twice as wide as tall; everything else is square.
	var output := Vector2i(px * (2 if bool(recipe.get("wide", false)) else 1), px)
	var render := output * _Recipes.supersample(recipe)
	# The same vignette every run: task_looks' meshes use the global randf.
	seed(hash(id))
	var subject: Image = null
	if recipe.has("build"):
		subject = await _render_subject(recipe, render)
		if subject == null:
			push_error("[IconStudio] %s: the builder %s made nothing" % [id, recipe["build"]])
			_failed += 1
			return
	var base := await _render_flat(_Recipes.base_painter(recipe), recipe, render)
	var top := await _render_flat(_Recipes.top_painter(recipe), recipe, render)
	var image := await _post(subject, base, top, recipe, render, px)
	image.resize(output.x, output.y, Image.INTERPOLATE_LANCZOS)
	var file := _out + id + ".png"
	var error := image.save_png(ProjectSettings.globalize_path(file))
	if error == OK:
		_write_sidecar(file)
		_made += 1
	else:
		_failed += 1
	print("[IconStudio] %s -> %s (%s)" % [id, file, error_string(error)])


# ---------------------------------------------------------------- the 3D pass

func _render_subject(recipe: Dictionary, render: Vector2i) -> Image:
	var viewport := _viewport(render, true)
	_stage(viewport)
	var yaw := Node3D.new()
	yaw.name = "Subject"
	yaw.rotation_degrees.y = float(recipe.get("yaw", 0.0))
	viewport.add_child(yaw)
	var pose := Node3D.new()
	pose.rotation_degrees = recipe.get("tilt", Vector3.ZERO)
	yaw.add_child(pose)
	# Through a plain Script so the builder is looked up by name (static funcs).
	var recipes: Script = _Recipes
	recipes.call(str(recipe["build"]), pose, recipe)
	# Plain meshes (the window frame, say) get the game's painted surfaces.
	_SharedLook.apply(pose)
	var bounds := _bounds(yaw)
	if bounds.size == Vector3.ZERO:
		viewport.queue_free()
		return null
	var camera := Camera3D.new()
	camera.fov = FOV
	camera.near = 0.01
	camera.far = 200.0
	viewport.add_child(camera)
	_frame(camera, bounds, _corners(yaw), float(recipe.get("pad", _Recipes.padding(recipe))), float(recipe.get("roll", 0.0)))
	camera.current = true
	var image := await _capture(viewport)
	viewport.queue_free()
	return image


## A transparent stage with its own world: one warm key light, a cool fill from
## the other side and flat warm ambient light. No sky, fog, SSAO, glow or shadows.
func _stage(viewport: SubViewport) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = EXPOSURE
	environment.glow_enabled = false
	environment.ssao_enabled = false
	environment.fog_enabled = false
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.rotation_degrees = KEY_ROTATION
	key.light_color = _SharedLook.SUN_COLOR
	key.light_energy = KEY_ENERGY
	key.shadow_enabled = false
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = FILL_ROTATION
	fill.light_color = FILL_COLOR
	fill.light_energy = FILL_ENERGY
	fill.shadow_enabled = false
	viewport.add_child(fill)


## Puts the camera on ICON_VIEW so the subject's corners (each mesh's own box, so
## a long tool posed on the diagonal isn't framed by its much bigger world box)
## fill the frame less the padding, centered on what the camera sees. roll turns
## the camera about its view axis, degrees: it lays a long, thin subject corner
## to corner so it still reads at SIZE_ROW (docs/ART.md, "Icons").
func _frame(camera: Camera3D, bounds: AABB, points: Array[Vector3], padding: float, roll: float) -> void:
	var back := ICON_VIEW.normalized()
	var level := Vector3.UP.cross(back).normalized()
	var right := level.rotated(back, deg_to_rad(roll))
	var up := back.cross(right).normalized()
	var center := bounds.get_center()
	var corners: Array[Vector3] = []
	for point: Vector3 in points:
		corners.append(point - center)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Vector3 in corners:
		var flat := Vector2(corner.dot(right), corner.dot(up))
		low = Vector2(minf(low.x, flat.x), minf(low.y, flat.y))
		high = Vector2(maxf(high.x, flat.x), maxf(high.y, flat.y))
	var middle := (low + high) * 0.5
	var reach := tan(deg_to_rad(FOV * 0.5)) * (1.0 - padding * 2.0)
	var distance := 0.0
	for corner: Vector3 in corners:
		var across := maxf(absf(corner.dot(right) - middle.x), absf(corner.dot(up) - middle.y))
		distance = maxf(distance, across / reach + corner.dot(back))
	var at := center + right * middle.x + up * middle.y + back * distance
	camera.global_transform = Transform3D(Basis(right, up, back), at)


## The world-space corners of every visible mesh's own bounds under root.
func _corners(root: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if not visual.visible or visual is Light3D:
			continue
		var box := visual.get_aabb()
		for index: int in 8:
			out.append(visual.global_transform * box.get_endpoint(index))
	return out


func _bounds(root: Node3D) -> AABB:
	var total := AABB()
	var first := true
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if not visual.visible or visual is Light3D:
			continue
		var box := visual.global_transform * visual.get_aabb()
		total = box if first else total.merge(box)
		first = false
	return total


# ---------------------------------------------------------------- the 2D passes

## One flat layer drawn by painter, or null for none.
func _render_flat(painter: String, recipe: Dictionary, render: Vector2i) -> Image:
	if painter == "":
		return null
	var viewport := _viewport(render, false)
	var drawer := Drawer.new()
	drawer.recipes = _Recipes
	drawer.painter = painter
	drawer.px = float(render.y)
	drawer.recipe = recipe
	viewport.add_child(drawer)
	var image := await _capture(viewport)
	viewport.queue_free()
	return image


func _post(subject: Image, base: Image, top: Image, recipe: Dictionary, render: Vector2i, px: int) -> Image:
	var rect := _Recipes.subject_rect(recipe)
	var viewport := _viewport(render, false)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = POST_SHADER
	material.shader = shader
	var blank := Image.create(render.x, render.y, false, Image.FORMAT_RGBA8)
	var blank_texture := ImageTexture.create_from_image(blank)
	material.set_shader_parameter("has_subject", subject != null)
	material.set_shader_parameter("has_base", base != null)
	material.set_shader_parameter("has_top", top != null)
	material.set_shader_parameter("subject", ImageTexture.create_from_image(subject) if subject != null else blank_texture)
	material.set_shader_parameter("base_layer", ImageTexture.create_from_image(base) if base != null else blank_texture)
	material.set_shader_parameter("top_layer", ImageTexture.create_from_image(top) if top != null else blank_texture)
	material.set_shader_parameter("subject_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	material.set_shader_parameter("texel", Vector2.ONE / Vector2(render))
	var scale := float(render.y) / float(px)
	material.set_shader_parameter("outline_px", float(px) * OUTLINE_SHARE * scale)
	material.set_shader_parameter("shadow_px", float(px) * SHADOW_SHARE * scale)
	material.set_shader_parameter("shadow_alpha", SHADOW_ALPHA)
	material.set_shader_parameter("sticker_share", _Recipes.sticker_share(recipe))
	var ring: Color = recipe.get("ring", _Recipes.INK)
	material.set_shader_parameter("sticker_ink", Vector3(ring.r, ring.g, ring.b))
	var ink := _Recipes.INK
	material.set_shader_parameter("ink", Vector3(ink.r, ink.g, ink.b))
	var canvas := TextureRect.new()
	canvas.texture = blank_texture
	canvas.material = material
	canvas.size = Vector2(render)
	viewport.add_child(canvas)
	var image := await _capture(viewport)
	viewport.queue_free()
	return image


# ---------------------------------------------------------------- plumbing

func _viewport(render: Vector2i, three_d: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = render
	viewport.transparent_bg = true
	viewport.disable_3d = not three_d
	viewport.own_world_3d = three_d
	viewport.msaa_3d = Viewport.MSAA_4X if three_d else Viewport.MSAA_DISABLED
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	return viewport


func _capture(viewport: SubViewport) -> Image:
	for _frame_index: int in SETTLE_FRAMES:
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _write_sidecar(file: String) -> void:
	var sidecar := ProjectSettings.globalize_path(file + ".import")
	if FileAccess.file_exists(sidecar):
		return
	var handle := FileAccess.open(sidecar, FileAccess.WRITE)
	if handle != null:
		handle.store_string(IMPORT_SIDECAR)
		handle.close()


func _res_path(value: String) -> String:
	if value.begins_with("res://") or value.is_absolute_path():
		return value
	return "res://" + value


# ---------------------------------------------------------------- contact sheet

## Every icon in the output folder at 96 px and at 20 px with its id, on paper
## (left) and on a dark panel (right), to judge outlines and legibility.
func _contact_sheet() -> void:
	var entries: Array = []
	for id: String in _Icons.IDS:
		var file := ProjectSettings.globalize_path(_out + id + ".png")
		if not FileAccess.file_exists(file):
			continue
		var image := Image.load_from_file(file)
		if image != null:
			entries.append([id, ImageTexture.create_from_image(image)])
	if entries.is_empty():
		push_warning("[IconStudio] no icons in %s for a sheet" % _out)
		return
	var rows := int(ceil(float(entries.size()) / float(SHEET_COLUMNS)))
	var panel_size := Vector2i(SHEET_COLUMNS * SHEET_CELL.x + 16, rows * SHEET_CELL.y + 16)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(panel_size.x * 2, panel_size.y)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	for half: int in 2:
		var background := ColorRect.new()
		background.color = _Recipes.PAPER if half == 0 else Color(0.11, 0.11, 0.13)
		background.position = Vector2(half * panel_size.x, 0)
		background.size = Vector2(panel_size)
		viewport.add_child(background)
		var text_color := _Recipes.INK if half == 0 else Color(0.92, 0.9, 0.86)
		for index: int in entries.size():
			var cell := Vector2(half * panel_size.x + 8 + (index % SHEET_COLUMNS) * SHEET_CELL.x, 8 + (index / SHEET_COLUMNS) * SHEET_CELL.y)
			var texture: Texture2D = entries[index][1]
			var aspect := float(texture.get_width()) / float(texture.get_height())
			var big := TextureRect.new()
			big.texture = texture
			big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			big.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			big.position = cell + Vector2(10, 0)
			big.size = Vector2(96, 96)
			viewport.add_child(big)
			var small := TextureRect.new()
			small.texture = texture
			small.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			small.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			small.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			small.position = cell + Vector2(10, 100)
			small.size = Vector2(20.0 * aspect, 20)
			viewport.add_child(small)
			var label := Label.new()
			label.text = str(entries[index][0])
			label.add_theme_font_size_override("font_size", 10)
			label.add_theme_color_override("font_color", text_color)
			label.position = cell + Vector2(0, 124)
			label.size = Vector2(SHEET_CELL.x - 4, 20)
			label.clip_text = true
			viewport.add_child(label)
	var image := await _capture(viewport)
	viewport.queue_free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_sheet).get_base_dir())
	var error := image.save_png(ProjectSettings.globalize_path(_sheet))
	print("[IconStudio] sheet -> %s (%s)" % [_sheet, error_string(error)])
