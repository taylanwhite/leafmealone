extends Node3D

## Dev tool, local only. Renders one art subject from four angles into a single
## PNG so a model can be judged and iterated on without playing the game:
##
##   Godot --path . res://tools/studio/studio.tscn -- --subject=trees --out=build/art/trees.png
##
## The subject stands on grass under the game's own sky, sun, and post effects
## (levels/shared_look.gd). Views: a hero three-quarter shot, the side, from
## above, and a close-up. Works with the window covered: it forces each draw.
## Subjects are listed in _build(). A subject can pick its own views by setting
## meta "views" on the subject root: an Array of {from, at, fov}, up to four.
##
## Options, after the "--":
## - --season=N: 0 autumn, 1 winter, 2 spring, 3 summer. The season's look
##   (snow, flowers, foliage tint; core/seasons.gd) is set before the subject is
##   built, so seasonal subjects build their season too. Default autumn.
## - --hood=<id>, --size=N, --seed=N, --archetype=<id>: what the neighborhood
##   subjects build (net/town/neighborhoods.gd ids; yard size 0-2).
## - anything else as --key=value, read by the subject (_options).

const _SharedLook = preload("res://levels/shared_look.gd")
const _Surfaces = preload("res://props/surfaces.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _Trees = preload("res://props/trees.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _HouseBuilder = preload("res://levels/town/house_builder.gd")
const _Archetypes = preload("res://levels/town/house_archetypes.gd")
const _HoodStyles = preload("res://levels/town/hood_styles.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")
const _StreetProps = preload("res://props/street_props.gd")
const _YardExtras = preload("res://props/yard_extras.gd")
const _EstateProps = preload("res://props/estate_props.gd")
const _SeasonProps = preload("res://props/season_props.gd")
const _WaterSurface = preload("res://props/water_surface.gd")
const VIEW_SIZE := Vector2i(720, 720)

var _subject := "trees"
var _out := "build/art/studio.png"
var _options: Dictionary = {}
var _season := 0
var _hood := "maple_row"
var _size := 1
var _seed := 1
var _archetype := ""


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--subject="):
			_subject = argument.trim_prefix("--subject=")
		elif argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--") and argument.contains("="):
			var pair := argument.trim_prefix("--").split("=", true, 1)
			_options[pair[0]] = pair[1]
	_season = posmod(int(_options.get("season", "0")), 4)
	_hood = str(_options.get("hood", _hood))
	_size = clampi(int(_options.get("size", str(_size))), 0, 2)
	_seed = int(_options.get("seed", str(_seed)))
	_archetype = str(_options.get("archetype", _archetype))
	Seasons.apply_look(Seasons.first_day_of(_season))
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
		"characters":
			for index: int in 5:
				var body: Node3D = _CartoonBody.new()
				body.call("dress_from_seed", int(_options.get("seed", "1")) * 31 + index * 7)
				root.add_child(body)
				body.position = Vector3(float(index) * 1.1 - 2.2, 0.0, 0.0)
				body.rotation.y = PI + float(index - 2) * 0.25
				body.call("build")
		"character":
			var body: Node3D = _CartoonBody.new()
			body.call("dress_from_seed", int(_options.get("seed", "3")))
			root.add_child(body)
			body.rotation.y = PI * 0.85
			body.call("build")
		"props":
			var models := preload("res://props/yard_models.gd")
			var lineup: Array = [["rake", Color.WHITE, Vector3.ONE], ["leaf_bag", Color.WHITE, Vector3.ONE], ["trash", Color(0.25, 0.28, 0.3), Vector3.ONE], ["wheelbarrow", Color(0.55, 0.22, 0.18), Vector3.ONE], ["gnome", Color.WHITE, Vector3.ONE], ["dumpster", Color(0.25, 0.3, 0.32), Vector3(1.4, 1.3, 1.0)], ["shed", Color(0.5, 0.4, 0.3), Vector3(2.4, 2.4, 2.0)], ["hedge", Color(0.2, 0.42, 0.22), Vector3(3.0, 1.6, 1.2)], ["car", Color(0.3, 0.42, 0.62), Vector3.ONE]]
			var x := -7.0
			for entry: Array in lineup:
				var model: Node3D = models.node(entry[0], entry[1], entry[2])
				root.add_child(model)
				model.position = Vector3(x, 0.0, 0.0)
				x += maxf((entry[2] as Vector3).x, 1.0) + 0.6
		"small_props":
			var models := preload("res://props/yard_models.gd")
			var kinds := ["rake", "leaf_bag", "trash", "wheelbarrow", "gnome"]
			for index: int in kinds.size():
				var color := Color(0.55, 0.22, 0.18) if kinds[index] == "wheelbarrow" else Color(0.25, 0.28, 0.3)
				var model: Node3D = models.node(kinds[index], color)
				root.add_child(model)
				model.position = Vector3(float(index) * 1.0 - 2.0, 0.0, 0.0)
				model.rotation.y = PI + 0.5
		"truck":
			var truck := Node3D.new()
			root.add_child(truck)
			truck.rotation.y = PI * 0.8
			preload("res://props/vehicles.gd").build_truck(truck, Color(0.75, 0.22, 0.15))
		"van":
			var van := Node3D.new()
			root.add_child(van)
			van.rotation.y = PI * 0.8
			preload("res://props/vehicles.gd").build_van(van, Color(0.16, 0.17, 0.2))
		"nice_boys":
			_nice_boys(root)
		"nice_boy":
			# One NICE BOY close up: --index=1 is the head NICE BOY, --gesture=<name>
			# holds a gesture mid-way.
			var body := _nice_boy(root, int(_options.get("index", "2")), Vector3.ZERO, PI * 0.85)
			_hold_gesture(body, str(_options.get("gesture", "")))
			root.set_meta("views", [
				{"from": Vector3(1.6, 1.6, 3.0), "at": Vector3(0.0, 1.0, 0.0), "fov": 40.0},
				{"from": Vector3(-3.0, 1.3, 0.6), "at": Vector3(0.0, 1.0, 0.0), "fov": 40.0},
				{"from": Vector3(0.45, 1.85, 1.45), "at": Vector3(0.0, 1.62, 0.0), "fov": 38.0},
				{"from": Vector3(1.1, 2.6, 1.3), "at": Vector3(0.0, 1.4, 0.0), "fov": 40.0},
			])
		"surfaces":
			_surfaces(root)
		"houses":
			_houses(root)
		"house":
			var archetype := _archetype if _archetype != "" else str(_HoodStyles.archetypes_for(_hood, _stories())[0])
			_HouseBuilder.build(root, Vector3.ZERO, _house_req(archetype, _seed))
		"street_props":
			var street: Array[String] = []
			for kind: String in _StreetProps.KINDS:
				if not _StreetProps.VEHICLES.has(kind):
					street.append(kind)
			_catalog_lineup(root, street, 6)
		"cars":
			_catalog_lineup(root, _StreetProps.VEHICLES, 3)
		"yard_extras":
			_catalog_lineup(root, _YardExtras.KINDS, 5)
		"estate":
			_catalog_lineup(root, _EstateProps.KINDS, 5)
		"seasonal_props":
			_catalog_lineup(root, _SeasonProps.KINDS, 6)
		"water":
			_water(root)
		"prop":
			# One catalog prop: --kind=<id> (--color=<html> optional).
			var tint := Color.html(str(_options.get("color", "ffffff")))
			var kind := str(_options.get("kind", "flamingo"))
			var lift := 2.4 if kind in ["icicle_run", "string_lights", "wreath"] else 0.0
			_PropCatalog.place(root, kind, Transform3D(Basis.IDENTITY, Vector3(0.0, lift, 0.0)), tint, {"season": _season, "lights": str(_options.get("lights", "classic"))})
		_:
			push_error("[Studio] no subject called %s" % _subject)


## The NICE BOYS in a row (docs/ART.md, "The NICE BOYS"): the head NICE BOY with
## his megaphone, one writing a citation, one more, and at the ends a player and a
## Marty-dressed body, so the lavender reads apart from everyone else. Dressed the
## way npcs/crew_member.gd dresses them.
func _nice_boys(root: Node3D) -> void:
	var player: Node3D = _CartoonBody.new()
	player.call("dress_from_seed", 3)
	root.add_child(player)
	player.position = Vector3(-2.6, 0.0, 0.0)
	player.rotation.y = PI + 0.3
	player.call("build")
	_nice_boy(root, 1, Vector3(-1.3, 0.0, 0.0), PI + 0.15)
	_hold_gesture(_nice_boy(root, 2, Vector3(0.0, 0.0, 0.0), PI), "scribble")
	_nice_boy(root, 3, Vector3(1.3, 0.0, 0.0), PI - 0.15)
	var clerk: Node3D = _CartoonBody.new()
	clerk.set("shirt", Color(0.93, 0.47, 0.13))
	clerk.set("pants", Color(0.28, 0.3, 0.38))
	clerk.set("skin", _CartoonBody.SKIN_TONES[2])
	clerk.set("hat_style", "cap")
	clerk.set("hat_color", Color(0.93, 0.47, 0.13).darkened(0.2))
	root.add_child(clerk)
	clerk.position = Vector3(2.6, 0.0, 0.0)
	clerk.rotation.y = PI - 0.3
	clerk.call("build")
	root.set_meta("views", [
		{"from": Vector3(1.8, 2.3, 8.4), "at": Vector3(0.0, 0.95, 0.0), "fov": 40.0},
		{"from": Vector3(-0.6, 1.6, 2.6), "at": Vector3(-0.65, 1.2, 0.0), "fov": 45.0},
		{"from": Vector3(0.0, 1.5, 2.2), "at": Vector3(0.0, 1.15, 0.0), "fov": 45.0},
		{"from": Vector3(-5.5, 1.6, -2.5), "at": Vector3(0.0, 1.0, 0.0), "fov": 40.0},
	])


func _nice_boy(root: Node3D, index: int, at: Vector3, yaw: float) -> Node3D:
	var body: Node3D = _CartoonBody.new()
	preload("res://npcs/crew_member.gd").dress(body, index)
	root.add_child(body)
	body.position = at
	body.rotation.y = yaw
	body.call("build")
	# The crew's CharacterLife keeps them angry: a furious grin.
	body.set("mood", "angry")
	return body


## Starts a gesture and runs the body's animation a little way into it, so the
## render catches it held.
func _hold_gesture(body: Node3D, gesture_name: String) -> void:
	if gesture_name == "":
		return
	body.call("gesture", gesture_name)
	for _step: int in 30:
		body.call("_physics_process", 1.0 / 60.0)


## Every surface pattern (props/surfaces.gd): a 2 m cube of each with its name,
## big flat swatches of the ground patterns, and a strip of road in each line
## style. Render it per season to see snow and flowers.
func _surfaces(root: Node3D) -> void:
	# Newest patterns first, so they fill the two front rows the close-ups look at.
	var samples: Array = []
	var names: Array = _Surfaces.PATTERNS.keys()
	names.reverse()
	for pattern: String in names:
		samples.append([pattern, pattern, Vector4.ZERO])
	samples.insert(names.find("stone") + 1, ["stone (ashlar)", "stone", Vector4(1, 0, 0, 0)])
	samples.insert(names.find("pavers") + 1, ["pavers (herringbone)", "pavers", Vector4(1, 0, 0, 0)])
	samples.insert(names.find("lawn_stripes") + 1, ["grass (dandelions)", "grass", Vector4(0, 0, 0.6, 0)])
	for index: int in samples.size():
		var sample: Array = samples[index]
		var at := Vector3(float(index % 8) * 3.0 - 10.5, 1.0, -3.0 - floorf(index / 8.0) * 3.0)
		_LowPoly.paint(_LowPoly.box(root, Vector3(2.0, 2.0, 2.0), at, _sample_color(sample[1])), sample[1], sample[2])
		_label(root, sample[0], at + Vector3(0.0, 1.35, 0.0))
	# Ground swatches, flat, where floor patterns read at their real scale.
	var grounds: Array = [["grass", Vector4.ZERO], ["lawn_stripes", Vector4.ZERO], ["gravel", Vector4.ZERO], ["pavers", Vector4.ZERO], ["pavers", Vector4(1, 0, 0, 0)], ["tile_floor", Vector4.ZERO], ["concrete", Vector4.ZERO], ["dirt", Vector4.ZERO]]
	for index: int in grounds.size():
		var at := Vector3(float(index) * 5.0 - 17.5, 0.02, 3.0)
		_LowPoly.paint(_LowPoly.box(root, Vector3(4.6, 0.04, 4.6), at, _sample_color(grounds[index][0])), grounds[index][0], grounds[index][1])
	# Roads: one strip per line style, 16 m long, three to a row.
	var styles: Array = _Surfaces.ROAD_LINES.keys()
	for index: int in styles.size():
		var style: String = styles[index]
		var half_width := 6.0 if style in ["parking", "crosswalk"] else 4.4
		var length := 12.0 if style == "crosswalk" else 16.0
		var at := Vector3(float(index % 3) * 19.0 - 19.0, 0.0, 16.0 + floorf(index / 3.0) * 15.0)
		_LowPoly.paint(_LowPoly.box(root, Vector3(length, 0.1, half_width * 2.0), at, Color(0.3, 0.3, 0.32)), "road", _Surfaces.road_params(style, half_width))
		_label(root, style, at + Vector3(0.0, 1.2, -half_width - 0.6), 0.025)
	root.set_meta("views", [
		# Everything: cubes and swatches.
		{"from": Vector3(14.0, 13.0, 13.0), "at": Vector3(0.0, 0.5, -5.0), "fov": 50.0},
		# Close-ups on the two front rows, left half then right half.
		{"from": Vector3(-6.0, 6.5, 6.5), "at": Vector3(-6.0, 0.4, -5.5), "fov": 55.0},
		{"from": Vector3(6.0, 6.5, 6.5), "at": Vector3(6.0, 0.4, -5.5), "fov": 55.0},
		# The roads from above.
		{"from": Vector3(0.0, 44.0, 52.0), "at": Vector3(0.0, 0.0, 33.0), "fov": 55.0},
	])


## Every house archetype in a lineup, four to a row, each in the palette of a
## neighborhood that builds it. --width=min|max|<m> (default: the middle of
## --size's yard house widths), --depth=<m>, --stories=1|2, --detail=far.
func _houses(root: Node3D) -> void:
	var names := _Archetypes.ALL
	var rows := ceili(float(names.size()) / 4.0)
	for index: int in names.size():
		var at := Vector3((float(index % 4) - 1.5) * 19.0, 0.0, -float(index / 4) * 52.0)
		_HouseBuilder.build(root, at, _house_req(names[index], _seed + index))
		_label(root, names[index], at + Vector3(0.0, 13.0, 0.0), 0.03)
	var views: Array = []
	for row: int in mini(rows, 4):
		var z := -float(row) * 52.0
		views.append({"from": Vector3(4.0, 11.0, z + 40.0), "at": Vector3(0.0, 4.5, z), "fov": 72.0})
	root.set_meta("views", views)


## What a studio house is built from: the archetype at --width/--depth/--stories,
## colored from a neighborhood that builds it (--hood if it does).
func _house_req(archetype: String, seed_value: int) -> Dictionary:
	var hood := _hood
	if not _builds(hood, archetype):
		for id: String in _HoodStyles.ids():
			if _builds(id, archetype):
				hood = id
				break
	var look: Dictionary = _HoodStyles.style(hood)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var wall: Array = look["walls"][rng.randi() % (look["walls"] as Array).size()]
	var roof: Array = look["roofs"][rng.randi() % (look["roofs"] as Array).size()]
	var widths: Vector2 = Constants.YARD_HOUSE_WIDTH[_size]
	var width := (widths.x + widths.y) * 0.5
	match str(_options.get("width", "")):
		"min":
			width = (Constants.YARD_HOUSE_WIDTH[0] as Vector2).x
		"max":
			width = (Constants.YARD_HOUSE_WIDTH[2] as Vector2).y
		"":
			pass
		var given:
			width = float(given)
	return {
		"archetype": archetype, "width": width, "depth": float(_options.get("depth", "8.0")), "stories": _stories(),
		"wall": wall[0], "wall_surface": wall[1], "roof": roof[0], "roof_surface": roof[1],
		"trim": look["trims"][rng.randi() % (look["trims"] as Array).size()],
		"door": look["doors"][rng.randi() % (look["doors"] as Array).size()],
		"accent": look["accents"][rng.randi() % (look["accents"] as Array).size()],
		"garage": rng.randf() < 0.5, "seed": seed_value, "detail": str(_options.get("detail", "full")),
	}


func _builds(hood: String, archetype: String) -> bool:
	for stories: int in [1, 2]:
		for entry: Array in _HoodStyles.neighbor_archetype_weights(hood, stories):
			if str(entry[0]) == archetype:
				return true
	return false


func _stories() -> int:
	return clampi(int(_options.get("stories", "2" if _size == 2 else "1")), 1, 2)


## A prop catalog lineup (props/prop_catalog.gd): kinds in rows of columns,
## each placed with its extras (glows, water, words) and labeled with its kind.
## Every view looks at one row from the front (-Z), four rows to a page
## (--page=1 for rows 5-8); rows sit 40 m apart so no view sees another row.
## --view=back looks at the backs. Render with --season=1 to check snow on top and none underneath.
func _catalog_lineup(root: Node3D, kinds: Array[String], columns: int) -> void:
	var page := int(_options.get("page", "0"))
	var back := str(_options.get("view", "")) == "back"
	var rows := ceili(float(kinds.size()) / float(columns))
	var views: Array = []
	for row: int in rows:
		var offset := Vector3((float(row) - float(rows - 1) * 0.5) * 40.0, 0.0, 0.0)
		var items := kinds.slice(row * columns, mini((row + 1) * columns, kinds.size()))
		var boxes: Array[AABB] = []
		var total := 0.0
		var tallest := 0.6
		for kind: String in items:
			var box: AABB = _PropCatalog.mesh(kind).get_meta("aabb")
			boxes.append(box)
			total += maxf(box.size.x, 0.8) + 1.2
			tallest = maxf(tallest, box.size.y)
		var x := -total * 0.5
		for index: int in items.size():
			var box := boxes[index]
			var width := maxf(box.size.x, 0.8)
			# Things that hang (icicles, lights, wreaths) are lifted so they show.
			var lift := -box.position.y + 0.4 if items[index] in ["icicle_run", "string_lights", "wreath"] else 0.0
			var at := offset + Vector3(x + 0.6 + width * 0.5 - box.get_center().x, lift, -box.get_center().z)
			_PropCatalog.place(root, items[index], Transform3D(Basis.IDENTITY, at), Color.WHITE, {"season": _season})
			_label(root, items[index], offset + Vector3(x + 0.6 + width * 0.5, box.end.y + lift + 0.45, 0.0), 0.006)
			x += width + 1.2
		var distance := maxf((total * 0.5) / tan(deg_to_rad(25.0)), tallest * 2.0)
		var side := 1.0 if back else -1.0
		views.append({"from": offset + Vector3(0.0, tallest * 0.6 + distance * 0.22, side * distance), "at": offset + Vector3(0.0, tallest * 0.38, 0.0), "fov": 50.0})
	var shown := views.slice(page * 4, page * 4 + 4)
	# A short page fills its other views with three-quarter shots of the same rows.
	var count := shown.size()
	for index: int in range(count, 4):
		if count == 0:
			break
		var view: Dictionary = (shown[index % count] as Dictionary).duplicate()
		var at: Vector3 = view["at"]
		var from: Vector3 = view["from"]
		view["from"] = at + Basis(Vector3.UP, 0.7 if index % 2 == 0 else -0.7) * (from - at) * 0.7
		shown.append(view)
	root.set_meta("views", shown)


## Water (props/water_surface.gd): a pool, a hot tub, a fountain, a kiddie pool
## and a birdbath on the lawn; a lake with a dock, boats, a swim platform and a
## buoy behind them (frozen, with the fishing shanty, at --season=1).
func _water(root: Node3D) -> void:
	var opts := {"season": _season}
	var lake := _WaterSurface.plane(Vector2(44.0, 26.0), _WaterSurface.lake_kind(_season), 44)
	lake.position = Vector3(0.0, 0.1, -16.0)
	root.add_child(lake)
	_PropCatalog.place(root, "pool_inground", Transform3D(Basis.IDENTITY, Vector3(-10.0, 0.0, 6.0)), Color.WHITE, opts)
	_PropCatalog.place(root, "hot_tub", Transform3D(Basis.IDENTITY, Vector3(-3.0, 0.0, 6.0)), Color.WHITE, opts)
	_PropCatalog.place(root, "fountain_tiered", Transform3D(Basis.IDENTITY, Vector3(3.5, 0.0, 6.5)), Color.WHITE, opts)
	_PropCatalog.place(root, "kiddie_pool", Transform3D(Basis.IDENTITY, Vector3(8.5, 0.0, 6.0)), Color.WHITE, opts)
	_PropCatalog.place(root, "birdbath", Transform3D(Basis.IDENTITY, Vector3(11.0, 0.0, 6.0)), Color.WHITE, opts)
	_PropCatalog.place(root, "dock", Transform3D(Basis.IDENTITY, Vector3(6.0, 0.0, -3.0)), Color.WHITE, opts)
	_PropCatalog.place(root, "boat_row", Transform3D(Basis(Vector3.UP, 0.2), Vector3(8.6, -0.22, -8.5)), Color.WHITE, {"seed": 0})
	_PropCatalog.place(root, "boat_motor", Transform3D(Basis(Vector3.UP, -0.1), Vector3(3.0, -0.3, -10.0)), Color.WHITE, {"seed": 3})
	_PropCatalog.place(root, "swim_platform", Transform3D(Basis.IDENTITY, Vector3(-6.0, -0.05, -12.0)), Color.WHITE, opts)
	_PropCatalog.place(root, "buoy", Transform3D(Basis.IDENTITY, Vector3(-1.0, -0.15, -20.0)), Color.WHITE, opts)
	if _season == 1:
		_PropCatalog.place(root, "fishing_shanty", Transform3D(Basis(Vector3.UP, 0.4), Vector3(-12.0, 0.03, -18.0)), Color.WHITE, opts)
	root.set_meta("views", [
		{"from": Vector3(14.0, 11.0, 20.0), "at": Vector3(0.0, 0.0, -2.0), "fov": 55.0},
		{"from": Vector3(-6.5, 3.2, 12.0), "at": Vector3(-7.0, 0.2, 6.0), "fov": 50.0},
		{"from": Vector3(6.0, 2.8, 11.5), "at": Vector3(4.0, 1.2, 6.5), "fov": 45.0},
		{"from": Vector3(12.0, 3.5, 2.0), "at": Vector3(5.0, 0.0, -9.0), "fov": 50.0},
	])


func _sample_color(pattern: String) -> Color:
	match pattern:
		"grass", "lawn_stripes", "foliage":
			return Color(0.36, 0.55, 0.24)
		"brick":
			return Color(0.6, 0.32, 0.26)
		"roof_tiles":
			return Color(0.72, 0.38, 0.24)
		"shakes", "bark", "planks", "board_batten":
			return Color(0.6, 0.42, 0.28)
		"stucco":
			return Color(0.9, 0.84, 0.72)
		"corrugated":
			return Color(0.66, 0.78, 0.82)
		"skin":
			return Color(0.85, 0.66, 0.52)
		"dirt":
			return Color(0.5, 0.38, 0.26)
		"pavers":
			return Color(0.66, 0.4, 0.3)
		"tile_floor":
			return Color(0.88, 0.86, 0.82)
		"shingles":
			return Color(0.36, 0.3, 0.3)
		"siding":
			return Color(0.62, 0.72, 0.8)
		"fabric":
			return Color(0.7, 0.3, 0.3)
		_:
			return Color(0.66, 0.65, 0.62)


func _label(root: Node3D, text: String, at: Vector3, pixel_size: float = 0.008) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = pixel_size
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)
	label.position = at


func _render(content: Node3D) -> void:
	var bounds := _bounds(content)
	var center := bounds.get_center()
	var reach := maxf(bounds.size.length() * 0.5, 0.5)
	var views: Array = [
		# Hero: three-quarter, a little above eye level.
		{"from": center + Vector3(0.75, 0.25, 1.0).normalized() * reach * 2.3, "at": center, "fov": 40.0},
		# Side.
		{"from": center + Vector3(-1.0, 0.05, 0.0) * reach * 2.4, "at": center, "fov": 40.0},
		# From above.
		{"from": center + Vector3(0.3, 1.2, 0.9).normalized() * reach * 2.6, "at": center, "fov": 40.0},
		# Close-up, toward the upper part where the detail is.
		{"from": center + Vector3(0.6, 0.35, 1.0).normalized() * reach * 0.95 + Vector3(0.0, bounds.size.y * 0.15, 0.0), "at": center + Vector3(0.0, bounds.size.y * 0.15, 0.0), "fov": 45.0},
	]
	# A subject that knows where to look says so; the rest keep the default four.
	var custom: Array = content.get_meta("views", [])
	for index: int in mini(custom.size(), views.size()):
		views[index] = custom[index]
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
