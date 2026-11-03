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
const _Stylized = preload("res://props/stylized.gd")
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
const _LotBuilder = preload("res://levels/town/lot_builder.gd")
const _BlockBuilder = preload("res://levels/town/block_builder.gd")
const _StreetBuilder = preload("res://levels/town/street_builder.gd")
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
	# Where the game's Surroundings ground is (top at -0.02), so parcels' lawns
	# (top at Constants.ART_LAWN_TOP) show over it as they do in the game.
	ground.position.y = -0.02


## Every subject the studio knows. Add one here to iterate on a new model.
func _build(root: Node3D) -> void:
	match _subject:
		"leaves":
			# The leaf look (raking:2): --kind=carpet|pile|species|raked|gpu, --sun=noon|low|dusk.
			var leaves_path := "res://tools/studio/leaves_subject.gd"
			if ResourceLoader.exists(leaves_path):
				load(leaves_path).call("build", root, _options)
		"hide":
			# Hiding (R2b hide): --part=poses|shell (tools/studio/hide_subject.gd).
			load("res://tools/studio/hide_subject.gd").call("build", root, _options)
		"trees":
			var crowns := ["orange", "red", "yellow", "turning", "rust"]
			for index: int in crowns.size():
				_Trees.spawn(root, Vector3(float(index) * 7.0 - 14.0, 0.0, 0.0), 7.0, "broadleaf", crowns[index], index)
			_Trees.spawn(root, Vector3(0.0, 0.0, -9.0), 9.0, "pine", "", 0)
			_Trees.spawn(root, Vector3(-9.0, 0.0, -8.0), 8.0, "pine", "", 1)
		"tree":
			# --far=1 shows the far LOD mesh up close instead.
			if str(_options.get("far", "0")) == "1":
				var kind := str(_options.get("kind", "broadleaf"))
				root.add_child(_Stylized.instance(_Trees.mesh_for(kind, str(_options.get("crown", "orange")), int(_options.get("variant", "0")), _season, true), _Trees.material_options(kind)))
			else:
				_Trees.spawn(root, Vector3.ZERO, 7.0, str(_options.get("kind", "broadleaf")), str(_options.get("crown", "orange")), int(_options.get("variant", "0")))
		"trees_new":
			_trees_new(root)
		"trees_seasons":
			_trees_seasons(root)
		"tree_lod":
			_tree_lod(root)
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
		"tool_tiers":
			_tool_tiers(root)
		"truck":
			var truck := Node3D.new()
			root.add_child(truck)
			truck.rotation.y = PI * 0.8
			preload("res://props/vehicles.gd").build_truck(truck, Color(0.75, 0.22, 0.15))
		"chefty_cab":
			# The drivable Chefty's open cab (driving C1): a driver with hands on the
			# wheel and a passenger sitting, a rider standing in the bed; for head
			# and roof clearance and the steering wheel.
			var vehicles := preload("res://props/vehicles.gd")
			var truck := Node3D.new()
			root.add_child(truck)
			truck.rotation.y = PI * 0.8
			var look: Node3D = vehicles.build_truck(truck, {"color": Color(0.75, 0.22, 0.15), "interior": true})
			vehicles.set_steering(look, float(_options.get("steer", "0.4")))
			for index: int in 3:
				var body: Node3D = _CartoonBody.new()
				body.call("dress_from_seed", 11 + index * 5)
				truck.add_child(body)
				body.position = vehicles.CHEFTY_SEATS[0] if index == 0 else (vehicles.CHEFTY_SEATS[1] if index == 1 else vehicles.CHEFTY_SEATS[3])
				body.call("build")
				body.call("sit", 1 if index < 2 else 2)
				if index == 0 and body.is_inside_tree():
					var grips: Array = vehicles.wheel_grips(look)
					body.call("set_hold", grips[0], grips[1])
			root.set_meta("views", [
				{"from": Vector3(-5.5, 3.6, -4.5), "at": Vector3(0.0, 1.6, 0.0), "fov": 40.0},
				{"from": Vector3(-2.6, 2.4, 2.0), "at": Vector3(-0.6, 1.7, 1.4), "fov": 40.0},
				{"from": Vector3(0.5, 7.0, 1.0), "at": Vector3(0.0, 1.0, 0.0), "fov": 45.0},
			])
		"van", "van_detail":
			_van(root, _subject == "van_detail")
		"beacon":
			_beacon(root)
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
		"rake_stroke":
			# One rake swing frozen at its phases (raking chunk 4).
			if ResourceLoader.exists("res://tools/studio/rake_stroke_subject.gd"):
				load("res://tools/studio/rake_stroke_subject.gd").build(root, _options)
		"annex", "annex_plan":
			# Satellite Annex B (R2 chunk 5): the street front, the lobby from the
			# doors, the windows up close, the desk corner; annex_plan from above
			# with the roof off. --seed=N picks the windows' looks.
			_annex(root, _subject == "annex_plan")
		"clerk":
			# The staff's states (npcs/clerk.gd) in four rows; --page=1 the second set;
			# --state=<name> --times=0.1,0.4,0.8,1.4 one state at four moments.
			if _options.has("state"):
				_clerk_moments(root, str(_options["state"]), str(_options.get("times", "0.1,0.4,0.8,1.4")), str(_options.get("role", "clerk")))
			else:
				_clerks(root, int(_options.get("page", "0")))
		"form27b":
			# Form 27-B (props/form_27b.gd): 2, 3 and 4 boxes, stamped, a carbon, approved.
			_forms(root)
		"holds":
			_holds(root)
		"gestures":
			_gestures(root)
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
		"parcel":
			_parcel(root)
		"hood_lineup":
			_hood_lineup(root)
		"block":
			_block(root)
		"street":
			_streets(root)
		"prop":
			# One catalog prop: --kind=<id> (--color=<html> optional).
			var tint := Color.html(str(_options.get("color", "ffffff")))
			var kind := str(_options.get("kind", "flamingo"))
			var lift := 2.4 if kind in ["icicle_run", "string_lights", "wreath"] else 0.0
			_PropCatalog.place(root, kind, Transform3D(Basis.IDENTITY, Vector3(0.0, lift, 0.0)), tint, {"season": _season, "lights": str(_options.get("lights", "classic"))})
		_:
			push_error("[Studio] no subject called %s" % _subject)


## The seven tools at every tier (props/yard_models.gd tier trim): a row per
## tool, used, stock, Mk II and Mk III left to right, and the gas can at the end.
## --tool=<id> shows just that tool's four, close up.
func _tool_tiers(root: Node3D) -> void:
	var models := preload("res://props/yard_models.gd")
	var tools: Array = Catalog.TOOLS.duplicate()
	var only := str(_options.get("tool", ""))
	if only != "":
		tools = [only]
	for row: int in tools.size():
		for tier: int in 4:
			var model: Node3D = models.node(tools[row], Color(0.8, 0.8, 0.8), Vector3(0.7, 0.7, 0.7), {"roughness": 0.55, "specular": 0.3}, tier)
			root.add_child(model)
			# Tiers across (x), tools down the rows (z), each turned side-on to the camera.
			model.position = Vector3((float(tier) - 1.5) * 2.8, 0.05 if tools[row] != "ladder" else 0.08, float(row) * 1.4 - float(tools.size() - 1) * 0.7)
			model.rotation.y = PI * 0.5
	if only == "":
		var can: Node3D = models.node("gas_can")
		root.add_child(can)
		can.position = Vector3(6.2, 0.0, 0.0)
		can.rotation.y = -0.6
		root.set_meta("views", [
			{"from": Vector3(3.0, 9.0, 11.0), "at": Vector3(0.6, 0.0, 0.0), "fov": 48.0},
			{"from": Vector3(-2.8, 2.6, 5.2), "at": Vector3(-2.8, 0.2, 1.2), "fov": 50.0},
			{"from": Vector3(2.8, 2.6, 5.2), "at": Vector3(2.8, 0.2, 1.2), "fov": 50.0},
			{"from": Vector3(6.2, 0.9, 1.4), "at": Vector3(6.2, 0.22, 0.0), "fov": 35.0},
		])
	else:
		root.set_meta("views", [
			{"from": Vector3(0.0, 3.5, 6.5), "at": Vector3(0.0, 0.25, 0.0), "fov": 50.0},
			{"from": Vector3(-4.2, 1.2, 1.8), "at": Vector3(-4.2, 0.25, 0.0), "fov": 40.0},
			{"from": Vector3(1.4, 1.2, 1.8), "at": Vector3(1.4, 0.25, 0.0), "fov": 40.0},
			{"from": Vector3(4.2, 1.2, 1.8), "at": Vector3(4.2, 0.25, 0.0), "fov": 40.0},
		])


## The new tree kinds and forms (props/trees.gd). Front row, spawned so they
## wear --season: birch, willow and cypress in two crowns each. Back row, fixed
## forms whatever the season: bare broadleaf, birch and willow, the snowy pine,
## and the spring and summer crowns.
func _trees_new(root: Node3D) -> void:
	var front: Array = [["birch", "yellow"], ["birch", "orange"], ["willow", "yellow"], ["willow", "turning"], ["cypress", ""], ["cypress", "", 2]]
	for index: int in front.size():
		var entry: Array = front[index]
		var at := Vector3(float(index) * 8.0 - 20.0, 0.0, 0.0)
		_Trees.spawn(root, at, 7.0, entry[0], entry[1], int(entry[2]) if entry.size() > 2 else index)
		_label(root, "%s %s" % [entry[0], entry[1]], at + Vector3(0.0, 8.2, 0.0), 0.012)
	var back: Array = [["broadleaf", "red", "red", "bare"], ["birch", "yellow", "yellow", "bare"], ["willow", "yellow", "yellow", "bare"], ["pine", "", "", "snowy"], ["broadleaf", "red", "blossom_pink", "full"], ["broadleaf", "yellow", "blossom_white", "full"], ["broadleaf", "orange", "spring_green", "full"], ["broadleaf", "rust", "deep_green", "full"]]
	for index: int in back.size():
		var entry: Array = back[index]
		var at := Vector3(float(index) * 8.0 - 28.0, 0.0, -14.0)
		var mesh := _Trees.form_mesh(entry[0], entry[1], index, entry[2], entry[3])
		_tree_mesh(root, mesh, entry[0], at, 7.0)
		_label(root, "%s %s" % [entry[0], entry[3] if entry[3] != "full" else entry[2]], at + Vector3(0.0, 8.2, 0.0), 0.012)
	root.set_meta("views", [
		{"from": Vector3(4.0, 9.0, 34.0), "at": Vector3(-2.0, 3.5, -6.0), "fov": 55.0},
		{"from": Vector3(-12.0, 4.0, 13.0), "at": Vector3(-12.0, 3.6, 0.0), "fov": 50.0},
		{"from": Vector3(10.0, 4.0, 13.0), "at": Vector3(10.0, 3.6, 0.0), "fov": 50.0},
		{"from": Vector3(-8.0, 7.0, 4.0), "at": Vector3(-8.0, 3.6, -14.0), "fov": 55.0},
	])


## Every tree kind through the year: one row per kind (broadleaf red and orange,
## pine, birch, willow, cypress), one column per season (autumn, winter, spring,
## summer, left to right), each a spawned tree turned with apply_season. Render
## with --season=1 to see the snow settle too. Past ART_TREE_LOD_DISTANCE from the
## camera (the back rows of the first view) trees show their far mesh, as in game.
func _trees_seasons(root: Node3D) -> void:
	var rows: Array = [["broadleaf", "red"], ["broadleaf", "orange"], ["pine", ""], ["birch", "yellow"], ["willow", "yellow"], ["cypress", ""]]
	# --row=N builds just that row (in its place), to single one out.
	var only := int(_options.get("row", "-1"))
	for row: int in rows.size():
		if only >= 0 and row != only:
			continue
		var entry: Array = rows[row]
		for season: int in 4:
			var at := Vector3((float(season) - 1.5) * 9.0, 0.0, -float(row) * 9.0)
			# Spawned and turned with apply_season, the path the game takes at a turn.
			var tree: Node3D = _Trees.spawn(root, at, 7.0, entry[0], entry[1], row)
			tree.call("apply_season", season)
			if row == 0:
				_label(root, Seasons.IDS[season], at + Vector3(0.0, 8.4, 3.0), 0.02)
	root.set_meta("views", [
		{"from": Vector3(0.0, 24.0, 30.0), "at": Vector3(0.0, 2.0, -20.0), "fov": 55.0},
		{"from": Vector3(-9.0, 6.0, 14.0), "at": Vector3(-9.0, 3.5, -6.0), "fov": 55.0},
		{"from": Vector3(9.0, 6.0, 14.0), "at": Vector3(9.0, 3.5, -6.0), "fov": 55.0},
		{"from": Vector3(0.0, 6.0, -20.0), "at": Vector3(0.0, 3.5, -40.0), "fov": 60.0},
	])


## Near and far LOD side by side for every kind in --season (near on the left
## of each pair), seen from Constants.ART_TREE_LOD_DISTANCE, where the game swaps
## them: the swap is invisible when each pair reads as twins.
func _tree_lod(root: Node3D) -> void:
	var kinds: Array = [["broadleaf", "red"], ["broadleaf", "yellow"], ["pine", ""], ["birch", "yellow"], ["willow", "yellow"], ["cypress", ""]]
	for index: int in kinds.size():
		var entry: Array = kinds[index]
		var x := (float(index) - 2.5) * 14.0
		var height := 8.5
		_tree_mesh(root, _Trees.mesh_for(entry[0], entry[1], index, _season), entry[0], Vector3(x - 3.4, 0.0, 0.0), height)
		_tree_mesh(root, _Trees.mesh_for(entry[0], entry[1], index, _season, true), entry[0], Vector3(x + 3.4, 0.0, 0.0), height)
	var distance := Constants.ART_TREE_LOD_DISTANCE
	root.set_meta("views", [
		{"from": Vector3(0.0, 3.0, distance + 20.0), "at": Vector3(0.0, 4.0, 0.0), "fov": 70.0},
		{"from": Vector3(-28.0, 2.0, distance), "at": Vector3(-28.0, 4.0, 0.0), "fov": 32.0},
		{"from": Vector3(0.0, 2.0, distance), "at": Vector3(0.0, 4.0, 0.0), "fov": 32.0},
		{"from": Vector3(28.0, 2.0, distance), "at": Vector3(28.0, 4.0, 0.0), "fov": 32.0},
	])


## One tree mesh as a plain instance (no LOD switching), height meters tall.
func _tree_mesh(root: Node3D, mesh: Mesh, kind: String, at: Vector3, height: float) -> void:
	var view := _Stylized.instance(mesh, _Trees.material_options(kind))
	root.add_child(view)
	view.position = at
	view.scale = Vector3.ONE * height / _Trees.BUILD_HEIGHT


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


## The NICE BOYS' Courtesy Shuttle (props/nice_van.gd) with --riders=N (default 2)
## players buckled into its rider seats (net/run_events/shuttle.gd), the driver and
## the head NICE BOY up front, to check they can be counted through the open side;
## --door=shut and --back=open move the doors. "van": the open side three
## quarters, the left side's livery, the back, and from above. "van_detail": the
## nose and cab, the interior through the open side, the back's lettering close,
## and the roof's dome and loudspeaker.
func _van(root: Node3D, detail: bool) -> void:
	var van := Node3D.new()
	van.name = "Van"
	root.add_child(van)
	var look: Node3D = preload("res://props/vehicles.gd").build_van(van, preload("res://props/vehicles.gd").VAN_PAINT)
	# --door=shut / --back=open: the sliding and back doors (nice_boys:4).
	if str(_options.get("door", "open")) == "shut":
		look.get_node("Shell/SideDoor").call("set_open_now", false)
	if str(_options.get("back", "shut")) == "open":
		look.get_node("Shell/BackDoors").call("set_open_now", true)
	for index: int in clampi(int(_options.get("riders", "2")), 0, 4):
		var body: Node3D = _CartoonBody.new()
		body.call("dress_from_seed", 5 + index * 9)
		# Buckled in on the Shuttle's rider seats, facing the open side.
		look.get_node("Shell/Seats/Seat%d" % index).add_child(body)
		body.call("build")
		body.call("sit", 1)
	# The driver at the wheel and the head NICE BOY riding shotgun.
	for seat: String in ["DriverSeat", "CrewSeats/Seat0"]:
		var crew: Node3D = _CartoonBody.new()
		preload("res://npcs/crew_member.gd").dress(crew, 4 if seat == "DriverSeat" else 1)
		look.get_node("Shell/" + seat).add_child(crew)
		crew.call("build")
		crew.call("sit", 1)
	if detail:
		root.set_meta("views", [
			{"from": Vector3(-3.2, 2.2, -7.5), "at": Vector3(0.0, 1.6, -2.6), "fov": 42.0},
			{"from": Vector3(4.2, 2.1, -0.6), "at": Vector3(0.0, 1.8, 0.2), "fov": 55.0},
			{"from": Vector3(1.5, 2.0, 7.2), "at": Vector3(0.0, 1.7, 3.0), "fov": 38.0},
			{"from": Vector3(2.6, 5.0, -4.6), "at": Vector3(0.0, 3.0, -0.6), "fov": 42.0},
		])
	else:
		root.set_meta("views", [
			{"from": Vector3(8.5, 3.6, -7.5), "at": Vector3(0.0, 1.5, 0.0), "fov": 40.0},
			{"from": Vector3(-10.5, 2.6, 3.5), "at": Vector3(0.0, 1.6, 0.4), "fov": 40.0},
			{"from": Vector3(-5.0, 3.0, 9.5), "at": Vector3(0.0, 1.5, 0.5), "fov": 40.0},
			{"from": Vector3(6.0, 12.0, 4.0), "at": Vector3(0.0, 1.0, 0.0), "fov": 45.0},
		])


## The arrival beacon, the Courtesy Flare (npcs/arrival_beacon.gd), at --urgency
## (default 0.6), with its notices partway down: the whole column, the seal up top,
## the cones, and the label.
func _beacon(root: Node3D) -> void:
	var beacon: Node3D = preload("res://npcs/arrival_beacon.gd").new()
	root.add_child(beacon)
	beacon.call("set_urgency", float(_options.get("urgency", "0.6")))
	beacon.call("advance", float(_options.get("time", "1.7")))
	root.set_meta("views", [
		{"from": Vector3(9.0, 6.0, 22.0), "at": Vector3(0.0, 7.5, 0.0), "fov": 50.0},
		{"from": Vector3(2.0, 15.6, 5.0), "at": Vector3(0.0, 15.2, 0.0), "fov": 45.0},
		{"from": Vector3(3.2, 1.6, 4.0), "at": Vector3(0.0, 0.4, 0.0), "fov": 50.0},
		{"from": Vector3(-6.0, 4.0, 9.0), "at": Vector3(0.0, 3.0, 0.0), "fov": 55.0},
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


## A stand-in for a yard prop (net/components/net_prop.gd): just the fields the
## looks read, so props/prop_looks.gd can dress and pose it like the real thing.
class StudioProp extends Node3D:
	var kind := ""
	var hose_source := ""
	var held_by := 0
	var spraying := false
	var water := 100.0
	var ladder_top := Vector3.ZERO


## Holds (docs/GAME.md, "2026-11-01, holds"): a row of cartoon bodies, each
## holding one thing the way the game poses it (prop_looks.gd pose_rake, pose_tool,
## pose_held) with their arms on its grips (grip_points -> CartoonBody.set_hold).
## --kinds=gnome,trash picks which; with one kind the views close in on it.
func _holds(root: Node3D) -> void:
	var all := ["rake", "leaf_bag", "gnome", "trash", "turf_sign", "wheelbarrow", "lawn_mower", "ladder", "leaf_blower", "hedge_trimmer", "paint_roller", "hose", "pressure_washer"]
	var kinds: Array = all
	if _options.has("kinds"):
		kinds = str(_options["kinds"]).split(",", false)
	var looks := preload("res://props/prop_looks.gd")
	var holders: Array[Node3D] = []
	var props: Array[Node3D] = []
	for index: int in kinds.size():
		var kind := str(kinds[index])
		# A mini holder like a player: Visual at the feet facing -Z, Head at 1.6 m.
		var holder := Node3D.new()
		holder.name = "Holder_%s" % kind
		root.add_child(holder)
		holder.position = Vector3((float(index) - float(kinds.size() - 1) * 0.5) * 1.9, 0.0, 0.0)
		var visual := Node3D.new()
		visual.name = "Visual"
		holder.add_child(visual)
		var head := Node3D.new()
		head.name = "Head"
		visual.add_child(head)
		head.position.y = 1.6
		var body: Node3D = _CartoonBody.new()
		body.name = "CartoonBody"
		body.call("dress_from_seed", 11 + index * 5)
		visual.add_child(body)
		body.call("build", head)
		var prop := StudioProp.new()
		prop.name = "Prop_%s" % kind
		prop.kind = kind
		prop.held_by = 1
		root.add_child(prop)
		var mesh := MeshInstance3D.new()
		mesh.name = "Visual"
		mesh.position.y = looks.VISUAL_HEIGHT
		prop.add_child(mesh)
		looks.dress(prop, kind, _prop_color(kind))
		prop.global_transform = Transform3D(holder.global_basis, _hold_spot(holder, kind))
		holders.append(holder)
		props.append(prop)
	# Pose, aim the arms, and run the bodies long enough for the reach to blend in.
	for _step: int in 30:
		for index: int in holders.size():
			var prop := props[index]
			var kind := str(prop.get("kind"))
			if kind == "rake":
				looks.pose_rake(prop, holders[index], false)
			elif Constants.TOOL_PRICES.has(kind):
				looks.pose_tool(prop, holders[index])
			else:
				looks.pose_held(prop, holders[index])
			if kind == "wheelbarrow":
				looks.show_bags(prop, 3)
			var grips: Array[Vector3] = looks.grip_points(prop, holders[index])
			var body := holders[index].get_node("Visual/CartoonBody")
			body.call("set_hold", grips[0], grips[1])
			body.call("_physics_process", 1.0 / 60.0)
	# Reports how far each hand landed from its grip, for judging numbers.
	for index: int in holders.size():
		var grips: Array[Vector3] = looks.grip_points(props[index], holders[index])
		var body := holders[index].get_node("Visual/CartoonBody")
		var report := ""
		for side: int in 2:
			if grips[side].is_finite():
				var shoulder: Vector3 = body.call("shoulder_position", side)
				report += " %s %.2f m" % ["right" if side == 0 else "left", shoulder.distance_to(grips[side])]
		print("[Studio] holds %s:%s" % [str(props[index].get("kind")), report])
	if kinds.size() == 1:
		root.set_meta("views", [
			{"from": Vector3(1.5, 1.55, -2.2), "at": Vector3(0.0, 1.0, -0.4), "fov": 45.0},
			{"from": Vector3(-2.6, 1.3, -0.4), "at": Vector3(0.0, 1.0, -0.4), "fov": 45.0},
			{"from": Vector3(1.2, 2.0, 2.1), "at": Vector3(0.0, 1.0, -0.4), "fov": 45.0},
			{"from": Vector3(0.9, 2.05, 0.35), "at": Vector3(0.0, 0.9, -0.6), "fov": 55.0},
		])
	else:
		var half := float(kinds.size() - 1) * 0.5 * 1.9
		root.set_meta("views", [
			{"from": Vector3(-half * 0.5, 1.8, -5.2), "at": Vector3(-half * 0.5, 1.0, 0.0), "fov": 48.0},
			{"from": Vector3(half * 0.5, 1.8, -5.2), "at": Vector3(half * 0.5, 1.0, 0.0), "fov": 48.0},
			{"from": Vector3(-half * 0.5 - 2.0, 1.6, -2.2), "at": Vector3(-half * 0.5, 1.0, -0.3), "fov": 55.0},
			{"from": Vector3(half * 0.5 + 2.0, 2.2, 3.4), "at": Vector3(half * 0.5, 1.0, -0.3), "fov": 55.0},
		])


## Where the game puts a held prop's body (net_prop.gd _hold_position), for the
## kinds whose look is posed relative to it.
func _hold_spot(holder: Node3D, kind: String) -> Vector3:
	var looks := preload("res://props/prop_looks.gd")
	var forward := -holder.global_basis.z
	var right := holder.global_basis.x
	match kind:
		"lawn_mower":
			return holder.global_position + forward * 1.15
		"pressure_washer":
			return holder.global_position + right * 0.85 + forward * 0.2
		"ladder":
			return holder.global_position + Vector3(0.0, 1.45, 0.0) + right * 0.3
		"leaf_blower", "hedge_trimmer", "hose", "paint_roller":
			return holder.global_position + Vector3(0.0, 0.8, 0.0) + forward * 0.55 + right * 0.25
		"leaf_bag":
			var at := holder.global_transform * (Vector3(0.0, 1.6, 0.0) + looks.BAG_HANDS)
			return at - holder.global_basis * ((looks.BAG_RIM[0] + looks.BAG_RIM[1]) * 0.5)
		"rake":
			return holder.global_position + Vector3(0.0, 0.75, 0.0) + forward * 0.9 + right * 0.35
	var entry: Dictionary = looks.HOLDS.get(kind, {})
	return holder.global_transform * (entry.get("at", Vector3(0.0, 1.2, -1.15)) as Vector3)


func _prop_color(kind: String) -> Color:
	match kind:
		"trash":
			return Color(0.25, 0.28, 0.3)
		"wheelbarrow":
			return Color(0.55, 0.22, 0.18)
		"turf_sign":
			return Color(0.1, 0.55, 0.28)
	return Color(0.7, 0.7, 0.7)


## The gestures that move the arms, frozen where they read, every body in profile
## facing +X: offer, punch, watch, rake, point and wave, then a hired hand raking
## with their rake and one hauling a bag (npcs/crew_hand.gd builds both).
func _gestures(root: Node3D) -> void:
	var lineup: Array = [["offer", 18], ["punch", 9], ["watch", 30], ["rake", 30], ["point", 30], ["wave", 30]]
	for index: int in lineup.size():
		var body: Node3D = _CartoonBody.new()
		body.call("dress_from_seed", 3 + index * 7)
		root.add_child(body)
		# In profile, facing +X (image right in every view), so ahead and behind read.
		body.position = Vector3(float(index) * 1.3 - 3.25, 0.0, 0.0)
		body.rotation.y = -PI * 0.5
		body.call("build")
		body.call("gesture", lineup[index][0])
		for _step: int in int(lineup[index][1]):
			body.call("_physics_process", 1.0 / 60.0)
		# Frozen there for the render.
		body.set_physics_process(false)
	# A hired hand, built the way npcs/crew_hand.gd builds one (its Visual faces +Z).
	var hand := Node3D.new()
	hand.name = "CrewHand"
	root.add_child(hand)
	hand.position = Vector3(4.6, 0.0, 0.0)
	hand.rotation.y = PI * 0.5
	var body: Node3D = _CartoonBody.new()
	body.call("dress_from_seed", 5)
	body.set("shirt", Color(0.93, 0.5, 0.18))
	hand.add_child(body)
	body.rotation.y = PI
	body.call("build")
	preload("res://npcs/crew_hand.gd").add_hand_rake(hand)
	body.call("gesture", "rake")
	for _step: int in 30:
		body.call("_physics_process", 1.0 / 60.0)
	body.set_physics_process(false)
	# And one hauling a bag.
	var hauler := Node3D.new()
	hauler.name = "CrewHauler"
	root.add_child(hauler)
	hauler.position = Vector3(6.0, 0.0, 0.0)
	hauler.rotation.y = PI * 0.5
	var hauler_body: Node3D = _CartoonBody.new()
	hauler_body.call("dress_from_seed", 9)
	hauler_body.set("shirt", Color(0.93, 0.5, 0.18))
	hauler.add_child(hauler_body)
	hauler_body.rotation.y = PI
	hauler_body.call("build")
	preload("res://npcs/crew_hand.gd").add_hand_bag(hauler)
	root.set_meta("views", [
		{"from": Vector3(0.6, 1.4, 9.0), "at": Vector3(0.6, 1.0, 0.0), "fov": 50.0},
		{"from": Vector3(-2.6, 1.3, 3.6), "at": Vector3(-2.6, 1.0, 0.0), "fov": 45.0},
		{"from": Vector3(1.3, 1.3, 3.6), "at": Vector3(1.3, 1.0, 0.0), "fov": 45.0},
		{"from": Vector3(5.3, 1.2, 4.0), "at": Vector3(5.3, 0.8, 0.0), "fov": 45.0},
	])


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
			var opts := {"season": _season}
			# A violation flag's words are opt-in (only the nearest few get them).
			if items[index] == "hoa_flag":
				opts["sign"] = "hoa_violation"
			_PropCatalog.place(root, items[index], Transform3D(Basis.IDENTITY, at), Color.WHITE, opts)
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


## One parcel (levels/town/lot_builder.gd) at the origin: --hood, --size,
## --seed, --season. The street edge is at +z 20.
func _parcel(root: Node3D) -> void:
	var parcel := _LotBuilder.build(root, Transform3D.IDENTITY, {"hood": _hood, "seed": _seed, "size": _size, "season": _season})
	var at: Vector3 = parcel.get_meta("house_at", Vector3.ZERO)
	root.set_meta("views", [
		{"from": Vector3(at.x + 22.0, 12.0, 42.0), "at": at + Vector3(0.0, 2.5, 6.0), "fov": 50.0},
		{"from": Vector3(at.x - 8.0, 2.0, 26.0), "at": at + Vector3(0.0, 3.0, 0.0), "fov": 55.0},
		{"from": Vector3(0.0, 70.0, 22.0), "at": Vector3(0.0, 0.0, 0.0), "fov": 50.0},
		{"from": at + Vector3(-18.0, 9.0, -26.0), "at": at + Vector3(0.0, 2.0, -6.0), "fov": 55.0},
	])


## One parcel per neighborhood side by side, 64 m apart, the same seed and size,
## each labeled: does each read as its own place?
func _hood_lineup(root: Node3D) -> void:
	var ids := _HoodStyles.ids()
	for index: int in ids.size():
		var x := (float(index) - float(ids.size() - 1) * 0.5) * 64.0
		_LotBuilder.build(root, Transform3D(Basis.IDENTITY, Vector3(x, 0.0, 0.0)), {"hood": ids[index], "seed": _seed + index, "size": _size, "season": _season, "frontage": 44.0})
		_label(root, ids[index], Vector3(x, 16.0, 0.0), 0.04)
	root.set_meta("views", [
		{"from": Vector3(-96.0, 30.0, 70.0), "at": Vector3(-96.0, 2.0, 0.0), "fov": 60.0},
		{"from": Vector3(0.0, 30.0, 70.0), "at": Vector3(0.0, 2.0, 0.0), "fov": 60.0},
		{"from": Vector3(96.0, 30.0, 70.0), "at": Vector3(96.0, 2.0, 0.0), "fov": 60.0},
		{"from": Vector3(0.0, 150.0, 60.0), "at": Vector3(0.0, 0.0, 0.0), "fov": 65.0},
	])


## The job's street block for --hood in --season (levels/town/block_builder.gd),
## built all at once, the job yard's slot left as bare lawn with Chefty's lane
## (Constants.ART_CHEFTY_LANE) outlined in red. Views: down the street the way
## Chefty comes in, the lane from overhead, a neighbor's yard, and across the
## street (Lakeside: the lake behind the yards).
func _block(root: Node3D) -> void:
	_BlockBuilder.build(root, Transform3D.IDENTITY, _hood, _seed, _season, {"job": {}, "async": false})
	var lane := Constants.ART_CHEFTY_LANE
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.95, 0.1, 0.1)
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for edge: Array in [[Vector3(lane.get_center().x, 0.2, lane.position.y), Vector3(lane.size.x, 0.04, 0.12)], [Vector3(lane.get_center().x, 0.2, lane.end.y), Vector3(lane.size.x, 0.04, 0.12)], [Vector3(lane.position.x, 0.2, lane.get_center().y), Vector3(0.12, 0.04, lane.size.y)], [Vector3(lane.end.x, 0.2, lane.get_center().y), Vector3(0.12, 0.04, lane.size.y)]]:
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = edge[1]
		line.mesh = box
		line.material_override = red
		line.set_meta("keep_material", true)
		line.position = edge[0]
		root.add_child(line)
	var fourth := {"from": Vector3(6.0, 7.0, 14.0), "at": Vector3(-4.0, 4.0, 62.0), "fov": 62.0}
	if _hood == "lakeside":
		fourth = {"from": Vector3(10.0, 12.0, -14.0), "at": Vector3(-10.0, 0.0, -46.0), "fov": 62.0}
	root.set_meta("views", [
		{"from": Vector3(14.0, 4.5, 27.0), "at": Vector3(-50.0, 2.5, 22.0), "fov": 62.0},
		{"from": Vector3(-30.0, 78.0, 30.0), "at": Vector3(-30.0, 0.0, 24.0), "fov": 62.0},
		{"from": Vector3(70.0, 12.0, 34.0), "at": Vector3(44.0, 3.0, 0.0), "fov": 55.0},
		fourth,
	])


## A street segment in every neighborhood's style, side by side along z.
func _streets(root: Node3D) -> void:
	var ids := _HoodStyles.ids()
	for index: int in ids.size():
		var z := float(index) * 18.0
		_StreetBuilder.segment(root, Vector3(-40.0, 0.0, z), Vector3(40.0, 0.0, z), _HoodStyles.style(ids[index]), {"hood": ids[index]})
		_label(root, ids[index], Vector3(-44.0, 2.0, z), 0.02)
	root.set_meta("views", [
		{"from": Vector3(30.0, 30.0, -20.0), "at": Vector3(0.0, 0.0, 30.0), "fov": 55.0},
		{"from": Vector3(-20.0, 6.0, -10.0), "at": Vector3(0.0, 2.0, 18.0), "fov": 55.0},
		{"from": Vector3(-20.0, 6.0, 44.0), "at": Vector3(0.0, 2.0, 72.0), "fov": 55.0},
		{"from": Vector3(0.0, 120.0, 45.0), "at": Vector3(0.0, 0.0, 45.0), "fov": 55.0},
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


# ---- R2:5 Satellite Annex B, its staff and Form 27-B

func _annex(root: Node3D, plan: bool) -> void:
	var annex := load("res://levels/annex/annex_b.gd") as GDScript
	annex.set("cutaway", plan)
	var built: Node3D = annex.call("build", root, _seed if _options.has("seed") else Constants.ANNEX_SET_SEED)
	annex.set("cutaway", false)
	# The run's doors stand open (the Annex opens them when someone arrives).
	built.get_node("Entrance").call("set_state", &"open", -1000.0)
	# --windows=break: A and B on a break (lamp off, clock sign up), C closed (blinds down, lamp off).
	if str(_options.get("windows", "")) == "break":
		for id: String in ["A", "B"]:
			built.get_node("Windows/%s" % id).call("set_state", &"lamp_off", -1000.0)
			built.get_node("Windows/%s" % id).call("set_state", &"clock_sign", -1000.0)
		built.get_node("Windows/C").call("set_state", &"blind_down", -1000.0)
		built.get_node("Windows/C").call("set_state", &"lamp_off", -1000.0)
	# --head_t=<s>: the Head NICE BOY that far into approving a form (R2c annex),
	# seen from the desk's visitor spot, from the side, and from above.
	if _options.has("head_t"):
		var held := float(_options["head_t"])
		var now := float(Time.get_ticks_msec()) / 1000.0
		# A direct call: the audio test's source scan reads call("play", "...") as a sound id.
		var head: Variant = built.get_node("Staff/HeadNiceBoy")
		head.play(&"head_windup_slam", now - held, {"read": Constants.ANNEX_HEAD_READ})
		head.set("hold_t", held)
		var raise := now - held + Constants.ANNEX_HEAD_READ
		built.get_node("HeadDesk/BigStamp").call("set_state", &"slam", raise, {"puppet": true})
		root.set_meta("views", [
			{"from": Vector3(5.9, 1.6, -2.2), "at": Vector3(7.6, 1.2, -2.3), "fov": 70.0},
			{"from": Vector3(7.4, 1.5, 0.2), "at": Vector3(7.6, 1.2, -2.3), "fov": 55.0},
			{"from": Vector3(6.2, 2.2, -4.0), "at": Vector3(7.6, 1.1, -2.2), "fov": 55.0},
			{"from": Vector3(4.6, 1.7, -0.6), "at": Vector3(7.6, 1.3, -2.3), "fov": 50.0},
		])
		return
	# --view=line: the clerks from where you stand in their lines (R2c annex).
	if str(_options.get("view", "")) == "line":
		root.set_meta("views", [
			{"from": Vector3(-7.0, 1.6, -2.9), "at": Vector3(-7.0, 1.3, -5.4), "fov": 70.0},
			{"from": Vector3(-3.6, 1.6, -3.5), "at": Vector3(-3.6, 1.2, -5.4), "fov": 70.0},
			{"from": Vector3(-1.8, 1.65, 1.4), "at": Vector3(-1.8, 1.4, -4.4), "fov": 70.0},
			{"from": Vector3(-0.2, 1.6, -2.0), "at": Vector3(-0.2, 1.3, -5.4), "fov": 70.0},
		])
		return
	if plan:
		(built.get_node("LightRows") as Node3D).visible = false
		root.set_meta("views", [
			{"from": Vector3(0.0, 26.0, 9.0), "at": Vector3(0.0, 0.0, 1.5), "fov": 50.0},
			{"from": Vector3(-6.0, 9.0, 8.0), "at": Vector3(-2.5, 0.5, -2.0), "fov": 55.0},
			{"from": Vector3(8.0, 9.0, 6.0), "at": Vector3(5.0, 0.5, -1.0), "fov": 55.0},
			{"from": Vector3(0.0, 12.0, -1.0), "at": Vector3(0.0, 0.0, -4.4), "fov": 60.0},
		])
		return
	root.set_meta("views", [
		{"from": Vector3(7.0, 2.4, 22.0), "at": Vector3(-1.0, 2.0, 6.5), "fov": 55.0},
		{"from": Vector3(-4.0, 1.65, 5.4), "at": Vector3(-1.6, 1.3, -4.4), "fov": 72.0},
		{"from": Vector3(-2.2, 1.6, -0.9), "at": Vector3(-2.2, 1.5, -4.4), "fov": 70.0},
		{"from": Vector3(7.4, 1.8, -3.7), "at": Vector3(1.0, 1.0, 5.0), "fov": 75.0},
	])


## A lineup of the staff's states, each held a moment in, on stools where they sit.
func _clerks(root: Node3D, page: int) -> void:
	var clerk_script := load("res://npcs/clerk.gd") as GDScript
	var pages: Array = [
		[["counter_idle", 2.0], ["wave_up", 0.6], ["take_form", 0.5], ["stamp", 0.2],
			["head_shake_point", 0.3], ["head_shake_point", 1.4], ["phone", 1.0], ["telegraph_stretch", 0.4],
			["peer_form", 1.0], ["asleep", 1.0], ["wake", 0.2], ["lunch_bite", 0.3],
			["lunch_turned", 1.0], ["lean_toward", 1.0], ["turn_to_cabinet", 1.0], ["volley", 0.1]],
		[["on_break", 1.5], ["notice", 0.3], ["add_carbon", 0.5], ["gasp_whistle", 0.2],
			["gasp_whistle", 0.8], ["walk_hand_out", 0.5], ["take_stamp_back", 0.3], ["head_windup_slam", 0.5],
			["greeter_lead", 0.5], ["greeter_offer", 0.6], ["greeter_punch_card", 0.45], ["janitor_mop", 0.6],
			["closing_rush", 0.3], ["idle", 1.0], ["hurry_back", 0.5], ["twitch_turn_back", 0.2]],
	]
	var lineup: Array = pages[clampi(page, 0, pages.size() - 1)]
	var views: Array = []
	var now := float(Time.get_ticks_msec()) / 1000.0
	for index: int in lineup.size():
		var entry: Array = lineup[index]
		var state := StringName(entry[0])
		var row := index / 4
		var column := index % 4
		var at := Vector3(float(column) * 1.6 - 2.4, 0.0, float(row) * -6.0)
		var role := "clerk"
		if str(entry[0]).begins_with("greeter"):
			role = "greeter"
		elif str(entry[0]).begins_with("janitor"):
			role = "janitor"
		elif str(entry[0]) in ["head_windup_slam", "gasp_whistle", "walk_hand_out", "take_stamp_back"]:
			role = "head"
		var clerk: Node3D = clerk_script.call("make", "Clerk%d" % index, role, 2 + index)
		root.add_child(clerk)
		clerk.call("set_home", at, 0.0)
		var args := {}
		if state == &"head_shake_point":
			args["to"] = root.to_global(at + Vector3(-2.0, 1.4, 1.5))
		elif state == &"lean_toward":
			args["dir"] = Vector3(-1.0, 0.0, 0.0)
		elif state == &"notice":
			args["at"] = root.to_global(at + Vector3(0.5, 1.5, 2.0))
		elif state == &"on_break":
			args["to"] = root.to_global(at)
		clerk.call("play", state, now - float(entry[1]), args)
		clerk.set("hold_t", float(entry[1]))
		if (clerk_script.get("SEATED") as Array).has(state) and role != "greeter" and role != "janitor":
			_LowPoly.box(root, Vector3(0.4, 0.46, 0.4), at + Vector3(0.0, 0.23, 0.0), Color(0.3, 0.3, 0.34))
			_LowPoly.box(root, Vector3(1.0, 0.05, 0.5), at + Vector3(0.0, 0.76, 0.5), Color(0.6, 0.45, 0.3))
		_label(root, "%s %.1f" % [entry[0], entry[1]], at + Vector3(0.0, 2.25, 0.0), 0.004)
	for row: int in 4:
		views.append({"from": Vector3(0.0, 1.7, float(row) * -6.0 + 5.2), "at": Vector3(0.0, 1.0, float(row) * -6.0), "fov": 55.0})
	root.set_meta("views", views)


## Form 27-B on an easel: two, three and four boxes, part stamped, a carbon, approved.
func _forms(root: Node3D) -> void:
	var form_script := load("res://props/form_27b.gd") as GDScript
	var annex := load("res://levels/annex/annex_b.gd") as GDScript
	var looks_list: Array = annex.call("looks_for", _seed)
	var looks := {"A": looks_list[0], "B": looks_list[1], "C": looks_list[2]}
	var now := float(Time.get_ticks_msec()) / 1000.0
	var forms: Array = [
		[PackedStringArray(["A", "B"]), 0, false, -1],
		[PackedStringArray(["B", "C", "A"]), 1, false, -1],
		[PackedStringArray(["C", "A", "B", "A"]), 2, false, -1],
		[PackedStringArray(["A", "B", "C", "B"]), 4, false, 3],
		[PackedStringArray(["B", "A", "C"]), 3, true, -1],
		[PackedStringArray(["A", "C"]), 2, true, -1],
	]
	for index: int in forms.size():
		var entry: Array = forms[index]
		var form: Node3D = form_script.call("make", entry[0], looks)
		root.add_child(form)
		form.position = Vector3(float(index % 3) * 0.3 - 0.3, 1.25 - float(index / 3) * 0.36, 0.0)
		if int(entry[3]) >= 0:
			form.call("set_carbon_boxes", range(int(entry[3]), (entry[0] as PackedStringArray).size()))
		form.call("set_progress", int(entry[1]), entry[0], bool(entry[2]), now - 2.0)
		if index == 5:
			form.call("glow", true)
			form.call("fast_pass", true)
			form.call("punch_card", 3)
	_LowPoly.box(root, Vector3(1.0, 0.8, 0.02), Vector3(0.0, 1.07, -0.03), Color(0.3, 0.26, 0.24))
	root.set_meta("views", [
		{"from": Vector3(0.0, 1.07, 1.25), "at": Vector3(0.0, 1.07, 0.0), "fov": 40.0},
		{"from": Vector3(-0.3, 1.25, 0.45), "at": Vector3(-0.3, 1.25, 0.0), "fov": 40.0},
		{"from": Vector3(0.3, 1.25, 0.45), "at": Vector3(0.3, 1.25, 0.0), "fov": 40.0},
		{"from": Vector3(0.15, 0.89, 0.6), "at": Vector3(0.15, 0.89, 0.0), "fov": 40.0},
	])

## One staff state at four moments side by side, each with its own camera.
func _clerk_moments(root: Node3D, state: String, times: String, role: String) -> void:
	var clerk_script := load("res://npcs/clerk.gd") as GDScript
	var now := float(Time.get_ticks_msec()) / 1000.0
	var moments := times.split(",")
	var views: Array = []
	for index: int in mini(moments.size(), 4):
		var at := Vector3(float(index) * 3.0 - 4.5, 0.0, 0.0)
		var clerk: Node3D = clerk_script.call("make", "ClerkA", role, 3)
		root.add_child(clerk)
		clerk.call("set_home", at, 0.0)
		var args := {"to": root.to_global(at + Vector3(-2.0, 1.4, 1.2)), "dir": Vector3(-1.0, 0.0, 0.2), "at": root.to_global(at + Vector3(0.6, 1.5, 2.0)), "from": root.to_global(at + Vector3(0.0, 0.0, 1.0))}
		if state in ["walk_to", "on_break", "walk_hand_out"]:
			args["to"] = root.to_global(at)
		clerk.call("play", StringName(state), now - moments[index].to_float(), args)
		clerk.set("hold_t", moments[index].to_float())
		if (clerk_script.get("SEATED") as Array).has(StringName(state)) and role in ["clerk", "head"]:
			_LowPoly.box(root, Vector3(0.4, 0.46, 0.4), at + Vector3(0.0, 0.23, 0.0), Color(0.3, 0.3, 0.34))
			_LowPoly.box(root, Vector3(1.2, 0.05, 0.55), at + Vector3(0.0, 0.76, 0.55), Color(0.6, 0.45, 0.3))
		_label(root, "%s %s" % [state, moments[index]], at + Vector3(0.0, 2.3, 0.0), 0.003)
		views.append({"from": at + Vector3(1.0, 1.6, 2.9), "at": at + Vector3(0.0, 1.05, 0.0), "fov": 45.0})
	root.set_meta("views", views)
