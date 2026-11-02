extends RefCounted

## Authority: local, cosmetic. The registry for every placeable prop mesh in
## the neighborhood looks: street furniture and vehicles (props/street_props.gd),
## yard clutter and fence runs (props/yard_extras.gd), estate, HOA and
## waterfront pieces (props/estate_props.gd), and seasonal decor
## (props/season_props.gd), with props/yard_models.gd as the fallback for the
## older kinds (gnome, hedge, shed, ...). Nothing here is networked: every peer
## builds the same meshes from the same kind, color and size.
##
##   var mesh := PropCatalog.mesh("flamingo")                       # cached ArrayMesh
##   var view := PropCatalog.node("car_sedan", Color.RED)           # one MeshInstance3D
##   PropCatalog.place(root, "lamp_acorn", xform)                   # with its glow
##   PropCatalog.place(root, "monument_sign", xform, Color.WHITE, {"sign": "birchwood_entrance"})
##   var batch := PropBatch.new(block)                              # many of the SIMPLE kinds
##
## Meshes are cached by kind, color and size (size rounded to 0.1 m, and only
## for the kinds that read it). Each mesh carries meta "triangles" (counted when
## built, so it works headless), "height" and "aabb". Every mesh is under
## Constants.ART_PROP_MAX_TRIANGLES; tools/prop_check.gd checks.
##
## SIMPLE lists the kinds a PropBatch may MultiMesh. The rest need place(),
## which adds what a mesh can't carry: lamp glows (group "street_lamps"), water
## (props/water_surface.gd), fountain sheets, glowing faces and bulbs, boat
## names, and sign words (Strings.SIGNS). Signature kinds join group
## "art_signature:<id>" (SIGNATURE) with meta "prop_instances" for the art test.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _YardModels = preload("res://props/yard_models.gd")
const _Street = preload("res://props/street_props.gd")
const _Yard = preload("res://props/yard_extras.gd")
const _Estate = preload("res://props/estate_props.gd")
const _Season = preload("res://props/season_props.gd")
const _Water = preload("res://props/water_surface.gd")
const _Strings = preload("res://ui/strings.gd")
const _Neighborhoods = preload("res://net/town/neighborhoods.gd")

const BUILDERS: Array = [_Street, _Yard, _Estate, _Season]

## Kinds that only look right through place() (they carry a glow, water, a
## required label, or bulbs). Everything else is SIMPLE.
const COMPLEX: Array[String] = [
	"lamp_cobra", "lamp_acorn", "lamp_lantern", "lamp_post_lantern", "wire_span", "street_sign_post",
	"stop_sign", "speed_sign", "for_sale_sign", "pool_inground", "hot_tub", "fountain_tiered", "boat_motor",
	"monument_sign", "entrance_arch", "gatehouse", "jack_o_lantern", "string_lights", "lemonade_stand",
]
## The older YardModels kinds a hood style may name (its fallback).
const FALLBACK_KINDS: Array[String] = ["hedge", "shed", "dumpster", "trash", "wheelbarrow", "fence", "hydrant", "leaf_bag"]
const FALLBACK_SIZED: Array[String] = ["hedge", "shed", "dumpster", "fence"]

## Which art-test signature group a kind counts toward (levels/town/hood_styles.gd
## "signature"); the rest count under their own kind name only.
const SIGNATURE: Dictionary = {
	"junk_pile": "junk_pile", "power_pole": "power_pole", "entrance_arch": "entrance_arch",
	"pool_inground": "pool_inground", "trampoline": "trampoline", "monument_sign": "monument_sign",
	"hoa_flag": "violation_flag", "speed_bump": "speed_bump", "gatehouse": "gatehouse", "dock": "dock",
	"boat_row": "boat", "boat_motor": "boat", "fountain_tiered": "fountain", "iron_gate": "estate_gate",
	"topiary_rake": "topiary_rake", "porch_swing": "porch_swing", "pumpkin_small": "pumpkin",
	"pumpkin": "pumpkin", "pumpkin_big": "pumpkin", "jack_o_lantern": "pumpkin",
}

## Materials: vehicles and metal props are shinier; these kinds sway.
const SHINY: Array[String] = ["bollard", "golf_cart", "bbq_gas", "fridge", "propane_tank", "boat_motor", "boat_row", "satellite_dish", "mailbox_fancy", "iron_fence_run", "iron_gate", "kiddie_pool", "pool_float", "fountain_tiered"]
const WINDY: Array[String] = ["clothesline", "hoa_flag", "putting_green", "pinwheel", "snowman_inflatable", "hammock", "tulip_bed", "kid_bike", "garden_bed_raised", "tomato_cage", "tire_planter", "mums_pot", "urn_planter"]
const WIND := 0.06

## Where a kind's words go: at (local), yaw (0 reads from +Z, PI from -Z, the
## front), font size, pixel size, text color, wrap width (m, 0 = none), and the
## default sign key (Strings.SIGNS) when place() is given none.
const LABELS: Dictionary = {
	"stop_sign": {"at": Vector3(0.0, 2.1, -0.02), "yaw": PI, "font": 64, "pixel": 0.0045, "color": Color(0.98, 0.98, 0.96), "sign": "stop"},
	"speed_sign": {"at": Vector3(0.0, 1.95, -0.02), "yaw": PI, "font": 40, "pixel": 0.0042, "color": Color(0.06, 0.06, 0.07), "sign": "speed_limit", "outline": 0},
	"for_sale_sign": {"at": Vector3(-0.4, 0.95, -0.028), "yaw": PI, "font": 32, "pixel": 0.003, "color": Color(0.72, 0.1, 0.08), "sign": "for_sale", "width": 0.5, "outline": 0},
	"monument_sign": {"at": Vector3(0.0, 0.8, -0.31), "yaw": PI, "font": 56, "pixel": 0.0042, "color": Color(0.16, 0.2, 0.18), "sign": "maple_entrance", "width": 2.6, "outline": 0},
	"entrance_arch": {"at": Vector3(0.0, 3.06, -0.09), "yaw": PI, "font": 48, "pixel": 0.0045, "color": Color(0.22, 0.4, 0.24), "sign": "dandelion_entrance", "width": 2.9, "outline": 0},
	"gatehouse": {"at": Vector3(-2.3, 1.25, -0.95), "yaw": PI, "font": 36, "pixel": 0.0036, "color": Color(0.18, 0.26, 0.2), "sign": "hoa_gate", "width": 1.6, "outline": 0},
	"hoa_flag": {"at": Vector3(0.11, 0.505, -0.006), "yaw": PI, "font": 20, "pixel": 0.0018, "color": Color(1.0, 0.96, 0.9), "sign": "hoa_violation", "width": 0.21, "outline": 0},
	"lemonade_stand": {"at": Vector3(0.0, 0.5, -0.32), "yaw": PI, "font": 40, "pixel": 0.0035, "color": Color(0.85, 0.3, 0.1), "sign": "lemonade", "width": 1.05, "outline": 0},
	"bus_bench": {"at": Vector3(0.0, 0.95, 0.285), "yaw": 0.0, "font": 40, "pixel": 0.0036, "color": Color(0.14, 0.18, 0.3), "sign": "", "width": 1.8, "outline": 0},
}

## Lamp lenses: where the lit part sits, its size, and how bright.
const LAMP_GLOWS: Dictionary = {
	"lamp_cobra": {"at": Vector3(0.0, 4.98, -1.25), "size": Vector3(0.34, 0.04, 0.52), "energy": 0.6},
	"lamp_acorn": {"at": Vector3(0.0, 3.57, 0.0), "size": Vector3(0.36, 0.62, 0.36), "energy": 0.9, "round": true},
	"lamp_lantern": {"at": Vector3(0.0, 3.5, 0.0), "size": Vector3(0.24, 0.48, 0.24), "energy": 1.0},
	"lamp_post_lantern": {"at": Vector3(0.0, 2.5, 0.0), "size": Vector3(0.24, 0.48, 0.24), "energy": 1.0},
}
const LAMP_LIGHT := Color(1.0, 0.9, 0.7)

static var SIMPLE: PackedStringArray = _simple()

static var _cache: Dictionary = {}
static var _glows: Dictionary = {}
static var _bulb_material: ShaderMaterial


## Every kind the catalog builds itself (not the YardModels fallbacks).
static func kinds() -> PackedStringArray:
	var all := PackedStringArray()
	for builder: Variant in BUILDERS:
		for kind: String in builder.KINDS:
			all.append(kind)
	return all


static func has(kind: String) -> bool:
	return kinds().has(kind) or FALLBACK_KINDS.has(kind)


## True when a PropBatch may MultiMesh kind.
static func is_simple(kind: String) -> bool:
	return SIMPLE.has(kind)


## True when kind reads its size (fence runs, docks, pools, ...).
static func is_sized(kind: String) -> bool:
	if FALLBACK_SIZED.has(kind):
		return true
	for builder: Variant in BUILDERS:
		if (builder.SIZED as Array).has(kind):
			return true
	return false


## The kind's mesh in color at size, built once and cached. Unknown kinds warn
## and come back as a plain rounded box of size, so a typo is visible.
static func mesh(kind: String, color: Color = Color.WHITE, size: Vector3 = Vector3.ONE) -> ArrayMesh:
	var used := size.snapped(Vector3(0.1, 0.1, 0.1)) if is_sized(kind) else Vector3.ONE
	var key := "%s|%s|%s" % [kind, color.to_html(), used]
	if _cache.has(key):
		return _cache[key]
	var kit := _MeshKit.new()
	var built := false
	for builder: Variant in BUILDERS:
		if builder.build(kind, kit, color, used):
			built = true
			break
	var made: ArrayMesh = null
	if built:
		made = kit.commit()
		if made != null:
			made.set_meta("triangles", kit.vertex_count() / 3)
			made.set_meta("aabb", _bounds(kit._vertices))
	if made == null:
		if not built and not FALLBACK_KINDS.has(kind):
			push_warning("[PropCatalog] no prop called %s; drawing a box" % kind)
		made = _YardModels._build(kind, color, size if is_sized(kind) else Vector3.ONE)
		made.set_meta("triangles", made.surface_get_array_len(0) / 3 if made.get_surface_count() > 0 else 0)
		made.set_meta("aabb", made.get_aabb())
	var box: AABB = made.get_meta("aabb")
	made.set_meta("height", box.size.y)
	_cache[key] = made
	return made


## The stylized material settings for kind (props/stylized.gd): outdoor props
## take the season's snow, none follow the foliage tint (they are built per
## season), some sway, vehicles and metal shine.
static func options(kind: String) -> Dictionary:
	var made := {"roughness": 0.8, "specular": 0.15, "snow": 1.0, "seasonal": false}
	if SHINY.has(kind) or _Street.VEHICLES.has(kind):
		made["roughness"] = 0.5
		made["specular"] = 0.3
	if WINDY.has(kind):
		made["wind"] = WIND
	return made


## One MeshInstance3D of kind, with its material, fade distance and shadow
## setting, meta "prop_kind". For a prop with extras, use place().
static func node(kind: String, color: Color = Color.WHITE, size: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var made := mesh(kind, color, size)
	var view := _Stylized.instance(made, options(kind))
	view.name = kind.to_pascal_case()
	view.set_meta("prop_kind", kind)
	fade(view, made.get_meta("aabb", made.get_aabb()))
	return view


## Sets how far a prop of this size stays visible and whether it casts a
## shadow: small props (shorter than ART_SMALL_PROP_HEIGHT) fade at
## ART_SMALL_PROP_RANGE and cast none, the rest fade at ART_MEDIUM_PROP_RANGE,
## and big ones (ART_LARGE_PROP_SIZE across) never fade.
static func fade(view: GeometryInstance3D, box: AABB) -> void:
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	view.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	view.visibility_range_end_margin = Constants.ART_PROP_FADE_MARGIN
	if longest >= Constants.ART_LARGE_PROP_SIZE:
		view.visibility_range_end = 0.0
	elif box.size.y < Constants.ART_SMALL_PROP_HEIGHT:
		view.visibility_range_end = Constants.ART_SMALL_PROP_RANGE
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		view.visibility_range_end = Constants.ART_MEDIUM_PROP_RANGE


## A prop with everything it needs, as a Node3D at xform under parent: the mesh,
## plus the kind's glow, water, sheets, bulbs, names, or words. opts:
##   size (Vector3, sized kinds), season (default Seasons.current()),
##   sign (a Strings.SIGNS key) or text (literal words) for labeled kinds,
##   label (false: no words even where the kind has a default),
##   texts ([a, b]) or hood (a neighborhoods.gd id) for street_sign_post,
##   name or seed for a boat's name (Strings.BOAT_NAMES),
##   to (Vector3, parent space: the next pole's base; wires hang at the insulators,
##   StreetProps.WIRE_HEIGHT) for wire_span, lights ("classic", "homemade",
##   "approved", "pro") for string_lights.
## The root has metas prop_kind and prop_instances (1) and joins the kind's
## signature group.
static func place(parent: Node3D, kind: String, xform: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE, opts: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = kind.to_pascal_case()
	root.transform = xform
	root.set_meta("prop_kind", kind)
	root.set_meta("prop_instances", 1)
	parent.add_child(root)
	tag(root, kind)
	var size: Vector3 = opts.get("size", Vector3.ONE)
	if kind == "wire_span":
		_wire(root, xform, opts)
		return root
	var view := node(kind, color, size)
	root.add_child(view)
	var season := int(opts.get("season", Seasons.current()))
	if LAMP_GLOWS.has(kind):
		_lamp_glow(root, LAMP_GLOWS[kind])
	match kind:
		"pool_inground":
			var water := _Estate.POOL_SIZE if size.is_equal_approx(Vector3.ONE) else size
			var surface := _Water.plane(Vector2(water.x, water.z), "frozen" if season == 1 else "pool")
			surface.position = Vector3(0.0, _Estate.POOL_WATER_Y, 0.0)
			root.add_child(surface)
		"hot_tub":
			var tub := _Water.plane(Vector2(_Estate.TUB_HALF * 2.0, _Estate.TUB_HALF * 2.0), "pool")
			tub.position = Vector3(0.0, _Estate.TUB_WATER_Y, 0.0)
			root.add_child(tub)
		"fountain_tiered":
			_fountain_water(root, season)
		"jack_o_lantern":
			_lantern_face(root)
		"string_lights":
			_bulbs(root, size, str(opts.get("lights", "classic")), int(opts.get("seed", 0)))
		"street_sign_post":
			_street_names(root, opts)
		"boat_row", "boat_motor":
			_boat_names(root, kind, xform, opts)
	if LABELS.has(kind) and bool(opts.get("label", true)):
		var spec: Dictionary = LABELS[kind]
		var words := str(opts.get("text", ""))
		if words == "":
			var sign_key := str(opts.get("sign", spec.get("sign", "")))
			words = sign_text(sign_key)
		if words != "":
			label(root, words, spec)
	return root


## Joins node to the groups the art test and later features look for: the
## kind's signature group, and "ambient_emitters" (meta "ambient", the loop id
## in audio's list) for a fountain.
static func tag(node: Node, kind: String) -> void:
	if SIGNATURE.has(kind):
		node.add_to_group("art_signature:%s" % SIGNATURE[kind])
	if kind == "fountain_tiered":
		node.add_to_group("ambient_emitters")
		node.set_meta("ambient", "fountain_loop")


## A sign's words (Strings.SIGNS), or "" for an unknown or empty key.
static func sign_text(key: String) -> String:
	if key == "":
		return ""
	return str(_Strings.SIGNS.get(key, ""))


## A Label3D under root laid out by spec (a LABELS entry, or the same keys).
static func label(root: Node3D, words: String, spec: Dictionary) -> Label3D:
	var made := Label3D.new()
	made.name = "Words"
	made.text = words
	made.font_size = int(spec.get("font", 40))
	made.pixel_size = float(spec.get("pixel", 0.004))
	made.modulate = spec.get("color", Color.WHITE)
	var outline := int(spec.get("outline", maxi(4, int(spec.get("font", 40)) / 8)))
	made.outline_size = outline
	made.outline_modulate = Color(0.08, 0.08, 0.1)
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	made.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	made.double_sided = false
	var width := float(spec.get("width", 0.0))
	if width > 0.0:
		made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		made.width = width / made.pixel_size
	made.position = spec.get("at", Vector3.ZERO)
	made.rotation.y = float(spec.get("yaw", 0.0))
	made.visibility_range_end = Constants.ART_SMALL_PROP_RANGE
	made.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(made)
	return made


## The emissive material for something lit (shared per color and energy).
static func glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(), energy]
	if not _glows.has(key):
		var made := StandardMaterial3D.new()
		made.albedo_color = color
		made.emission_enabled = true
		made.emission = color
		made.emission_energy_multiplier = energy
		_glows[key] = made
	return _glows[key]


static func _simple() -> PackedStringArray:
	var found := PackedStringArray()
	for kind: String in kinds():
		if not COMPLEX.has(kind):
			found.append(kind)
	for kind: String in FALLBACK_KINDS:
		found.append(kind)
	return found


static func _bounds(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var box := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		box = box.expand(point)
	return box


static func _lamp_glow(root: Node3D, spec: Dictionary) -> void:
	var lens := MeshInstance3D.new()
	lens.name = "Lens"
	if bool(spec.get("round", false)):
		var globe := SphereMesh.new()
		var size: Vector3 = spec["size"]
		globe.radius = size.x * 0.5
		globe.height = size.y
		globe.radial_segments = 10
		globe.rings = 5
		lens.mesh = globe
	else:
		var box := BoxMesh.new()
		box.size = spec["size"]
		lens.mesh = box
	lens.material_override = glow_material(LAMP_LIGHT, float(spec.get("energy", 0.8)))
	lens.set_meta("keep_material", true)
	lens.position = spec["at"]
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lens.visibility_range_end = Constants.ART_MEDIUM_PROP_RANGE
	lens.add_to_group("street_lamps")
	root.add_child(lens)


static func _wire(root: Node3D, xform: Transform3D, opts: Dictionary) -> void:
	var to: Vector3 = opts.get("to", xform.origin + xform.basis * Vector3(0.0, 0.0, -30.0))
	var kit := _MeshKit.new()
	_Street.wires(kit, [[Vector3.ZERO, xform.affine_inverse() * to]], _Street.WIRE_HEIGHT, float(opts.get("sag", 0.7)))
	var made := kit.commit()
	if made == null:
		return
	made.set_meta("triangles", kit.vertex_count() / 3)
	var view := _Stylized.instance(made, options("wire_span"))
	view.name = "Wires"
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(view)


static func _fountain_water(root: Node3D, season: int) -> void:
	var tiers: Array = _Estate.FOUNTAIN_TIERS
	var frozen := season == 1
	for index: int in tiers.size():
		var tier: Array = tiers[index]
		var water := _Water.disc(float(tier[0]), "frozen" if frozen else "pool", 16)
		water.name = "Water%d" % index
		water.position = Vector3(0.0, float(tier[1]), 0.0)
		root.add_child(water)
	if frozen:
		return
	# Sheets fall from each upper tier's rim into the one below, and the spout
	# into the top tier.
	for index: int in range(1, tiers.size()):
		var upper: Array = tiers[index]
		var lower: Array = tiers[index - 1]
		var sheet := _Water.view(_Water.sheet(float(upper[0]) + 0.08, float(upper[1]) + 0.06, float(upper[0]) + 0.28, float(lower[1]), 16), "fountain")
		sheet.name = "Sheet%d" % index
		root.add_child(sheet)
	var top: Array = tiers[tiers.size() - 1]
	var spout := _Water.view(_Water.sheet(0.03, float(top[1]) + 0.42, float(top[0]) * 0.7, float(top[1]), 10), "fountain")
	spout.name = "Spout"
	root.add_child(spout)


static func _lantern_face(root: Node3D) -> void:
	var face: Vector3 = _Season.LANTERN_FACE
	var light := Color(1.0, 0.72, 0.25)
	var parts: Array = [[Vector3(-0.065, 0.05, 0.0), Vector3(0.05, 0.045, 0.03)], [Vector3(0.065, 0.05, 0.0), Vector3(0.05, 0.045, 0.03)], [Vector3(0.0, -0.06, 0.0), Vector3(0.15, 0.035, 0.03)], [Vector3(0.0, 0.0, 0.0), Vector3(0.025, 0.03, 0.03)]]
	for part: Array in parts:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[1]
		piece.mesh = box
		piece.material_override = glow_material(light, 2.2)
		piece.set_meta("keep_material", true)
		piece.position = face + (part[0] as Vector3)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(piece)


## String-light bulbs: one MultiMesh of small glowing blobs along the cord, the
## colors set per bulb. lights: "classic" (cycling colors), "approved" (warm
## white, every bulb the same, Oak Hollow), "homemade" (mismatched, a few dead),
## "pro" (bigger bulbs, Mansion Hill).
static func _bulbs(root: Node3D, size: Vector3, lights: String, seed_value: int) -> void:
	var length := _Season.RUN_LENGTH if size.is_equal_approx(Vector3.ONE) else size.x
	var points := _Season.bulb_points(length)
	var bulb := SphereMesh.new()
	var radius := 0.065 if lights == "pro" else 0.045
	bulb.radius = radius
	bulb.height = radius * 2.6
	bulb.radial_segments = 6
	bulb.rings = 3
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = bulb
	multimesh.instance_count = points.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var colors: Array[Color] = _Season.BULB_COLORS
	for index: int in points.size():
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, points[index]))
		var tint: Color = colors[index % colors.size()]
		match lights:
			"approved":
				tint = colors[0]
			"homemade":
				tint = colors[rng.randi() % colors.size()]
				if rng.randf() < 0.12:
					tint = Color(0.2, 0.2, 0.2)
		multimesh.set_instance_color(index, tint)
	var view := MultiMeshInstance3D.new()
	view.name = "Bulbs"
	view.multimesh = multimesh
	view.material_override = _bulb_shader()
	view.set_meta("keep_material", true)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.visibility_range_end = Constants.ART_MEDIUM_PROP_RANGE
	root.add_child(view)


static func _bulb_shader() -> ShaderMaterial:
	if _bulb_material == null:
		var shader := Shader.new()
		shader.code = "shader_type spatial;\nrender_mode diffuse_burley;\nvoid fragment() {\n\tALBEDO = COLOR.rgb;\n\tEMISSION = COLOR.rgb * 4.0;\n\tROUGHNESS = 0.3;\n}\n"
		_bulb_material = ShaderMaterial.new()
		_bulb_material.shader = shader
	return _bulb_material


static func _street_names(root: Node3D, opts: Dictionary) -> void:
	var names: Array = opts.get("texts", [])
	if names.is_empty() and opts.has("hood"):
		names = (_Neighborhoods.get_hood(str(opts["hood"])).get("streets", []) as Array).slice(0, 2)
	if names.is_empty():
		names = ["Maple Row", "Acorn Court"]
	var spec := {"font": 40, "pixel": 0.0035, "color": Color(0.98, 0.98, 0.96), "width": 0.95, "outline": 0}
	var faces: Array = [[Vector3(0.0, 2.82, -0.015), PI], [Vector3(0.0, 2.82, 0.015), 0.0], [Vector3(0.015, 2.6, 0.0), PI * 0.5], [Vector3(-0.015, 2.6, 0.0), -PI * 0.5]]
	for index: int in faces.size():
		var face: Array = faces[index]
		var words := str(names[mini(index / 2, names.size() - 1)]).to_upper()
		var placed := spec.duplicate()
		placed["at"] = face[0]
		placed["yaw"] = face[1]
		label(root, words, placed)


## A boat's name on both sides of its hull: opts name, else one of
## Strings.BOAT_NAMES picked by opts seed (default: from where it sits).
static func _boat_names(root: Node3D, kind: String, xform: Transform3D, opts: Dictionary) -> void:
	if not bool(opts.get("label", true)):
		return
	var words := str(opts.get("name", ""))
	if words == "":
		var names: Array = _Strings.BOAT_NAMES
		var seed_value := int(opts.get("seed", hash([snappedf(xform.origin.x, 0.1), snappedf(xform.origin.z, 0.1)])))
		words = str(names[posmod(seed_value, names.size())])
	var beam := float(_Estate.BOAT_BEAMS[kind])
	var depth := float(_Estate.BOAT_DEPTHS[kind])
	var length := float(_Estate.BOAT_LENGTHS[kind])
	for side: float in [-1.0, 1.0]:
		label(root, words, {"at": Vector3(side * (beam * 0.44 + 0.012), depth * 0.74, length * 0.12), "yaw": side * PI * 0.5, "font": 40, "pixel": 0.0042, "color": Color(0.12, 0.2, 0.36), "outline": 0})
