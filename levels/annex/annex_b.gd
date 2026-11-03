extends Node3D

## Authority: local, cosmetic. Satellite Annex B, the NICE BOYS Regional Field
## Office's paperwork annex (docs/GAME.md "Satellite Annex B"): the room a caught
## crew does Form 27-B in, built in code on every peer the same way from a seed.
##
##   var set: Node3D = AnnexB.build(border_zone, set_seed)   # World/BorderZone/AnnexSet
##   AnnexB.apply_run(set, looks)      # dress windows A..C for a run ([{icon, color}] x3)
##   set.window_icon("B"), set.window_color("B")
##
## It sits in the BORDER zone slot (BorderZone, (0, 0, 1000) in both maps) and is
## always loaded. The street and its curb at +Z, a lavender stucco front that
## matches the town's Field Office (levels/town/town_dressing.gd), glass doors,
## a lobby of chairs and floor lines, four service windows in the counter wall
## (A, B, C and the one that is never open, D), the Head NICE BOY's desk, the
## copier, cooler and coffee machine, the co-signer sheet, the OUTGOING tray and
## the turnstile out to the forecourt where the return shuttle waits.
## No desert, highway, lanes, gantry or bars: doors stand open on the street side,
## the turnstile is the only gate, and nobody here ever touches a visitor.
## The node contract (gap-specs nice_boys C9) is what net/annex/annex.gd drives:
## markers AnnexCurb, AnnexSide, Threshold, Forecourt, ForecourtCurb, Cam*;
## Entrance and SideDoor (open, closed); GreeterPath and JanitorPath (Path3D);
## Windows/A..D (props/office_props.gd ServiceWindow); FloorLines/A..C;
## HeadDesk (DeskSpot, Pad, BigStamp); Copier, Cooler, CoffeeMachine; CoSignSheet;
## OutgoingTray; Turnstile; LightRows/Row0..3; WallClock; NowServing; Dispenser;
## Stickies; Staff/{ClerkA..D, HeadNiceBoy, Greeter, Janitor} (npcs/clerk.gd).
## tools/annex_check.gd checks it, the budgets, reachability and the signs.

const _HouseKit = preload("res://props/house_kit.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Surfaces = preload("res://props/surfaces.gd")
const _Props = preload("res://props/office_props.gd")
const _Clerk = preload("res://npcs/clerk.gd")
const _Strings = preload("res://ui/strings.gd")
const _NiceSeal = preload("res://props/nice_seal.gd")
const _Surroundings = preload("res://levels/dressing/surroundings.gd")

## The windows a run can ask for, and the pictograms and colors they can wear
## (the icons are the tools' own, ui/icons.gd, so the form's boxes match).
const WINDOWS: Array[String] = ["A", "B", "C", "D"]
const PICTOGRAMS: Array[String] = [
	"item_rake", "item_leaf_bag", "tool_lawn_mower", "tool_hedge_trimmer",
	"tool_leaf_blower", "item_wheelbarrow", "tool_hose", "item_gnome",
]
const COLORS: Array[Color] = [
	Color(0.15, 0.62, 0.6), Color(0.93, 0.45, 0.36), Color(0.94, 0.73, 0.18), Color(0.48, 0.52, 0.92),
	Color(0.5, 0.75, 0.3),
]
## Where the windows stand along the counter wall (x, m) and the wall's line (z).
const WINDOW_X: Array[float] = [-7.0, -3.6, -0.2, 3.2]
const COUNTER_Z: float = -4.4
const STAFF_DOOR_X: Vector2 = Vector2(5.8, 6.8)
const ENTRANCE_X: float = -4.0
const ENTRANCE_WIDTH: float = 2.0
const EXIT_X: Vector2 = Vector2(5.2, 6.6)
const TURNSTILE_X: float = 6.0
const TURNSTILE_PASSAGE: float = 0.9
const SIDE_DOOR_Z: float = 1.0
const SIDE_DOOR_WIDTH: float = 1.2
const DOOR_HEIGHT: float = 2.3
const WALL: float = 0.25
const PARAPET: float = 4.4
const SIDEWALK_END: float = 12.0
const STREET_END: float = 20.0
const PLANTER_X: float = 2.0
const LIGHT_ROW_Z: Array[float] = [-5.45, -2.7, 0.3, 3.3]
const LAVENDER := Color(0.72, 0.66, 0.86)
const INSIDE_WALL := Color(0.84, 0.8, 0.7)
const WAINSCOT := Color(0.55, 0.5, 0.66)
const CEILING := Color(0.82, 0.81, 0.78)
const FLOOR := Color(0.78, 0.76, 0.7)
const CONCRETE := Color(0.7, 0.69, 0.66)
const ASPHALT := Color(0.24, 0.24, 0.26)
const LAWN := Color(0.42, 0.52, 0.3)
const HEDGE := Color(0.25, 0.45, 0.22)
const CHAIR := Color(0.36, 0.42, 0.62)
const STEEL := Color(0.62, 0.65, 0.7)
const WOOD := Color(0.6, 0.45, 0.3)
const DARK := Color(0.16, 0.16, 0.19)

## Studio only (tools/studio annex_plan): build without the roof and ceiling.
static var cutaway: bool = false

## The seed this set was built with, and each window's look {icon, color}.
var set_seed: int = 0
var looks: Dictionary = {}
var _far: bool = false
var _staff: Node3D
var _lamps_checked: int = -1


## Builds the set under parent (World/BorderZone) and returns it, named AnnexSet.
## The same seed always builds the same room; the seed picks the default looks.
static func build(parent: Node3D, seed_value: int) -> Node3D:
	var made: Node3D = (load("res://levels/annex/annex_b.gd") as GDScript).new()
	made.name = "AnnexSet"
	made.set("set_seed", seed_value)
	parent.add_child(made)
	made.call("_build")
	return made


## The room's looks for windows A, B and C before a run dresses them: three of
## the Annex's pictograms (Constants.ANNEX_WINDOW_ICONS), each in the one color it
## always wears (Constants.ANNEX_ICON_COLORS), so no two windows read alike and a
## pictogram never changes color between visits (R2b). D keeps its own.
static func looks_for(seed_value: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var icons: Array = Constants.ANNEX_WINDOW_ICONS.duplicate()
	var out: Array[Dictionary] = []
	for index: int in 3:
		var icon: String = icons.pop_at(rng.randi() % icons.size())
		out.append({"icon": icon, "color": _Props.icon_color(icon)})
	return out


## Dress windows A, B and C (their plaques, boards and floor lines) for a run.
## looks: three {icon, color} dictionaries, or three icon ids (colors stay).
static func apply_run(set_node: Node3D, run_looks: Array) -> void:
	if set_node == null:
		return
	for index: int in mini(run_looks.size(), 3):
		var id: String = WINDOWS[index]
		var entry: Variant = run_looks[index]
		var look: Dictionary = (set_node.get("looks") as Dictionary).get(id, {}).duplicate()
		if entry is Dictionary:
			look.merge(entry as Dictionary, true)
		else:
			look["icon"] = str(entry)
		(set_node.get("looks") as Dictionary)[id] = look
		var window := set_node.get_node_or_null("Windows/%s" % id)
		if window != null:
			window.call("apply_look", look)
		var line := set_node.get_node_or_null("FloorLines/%s" % id)
		if line != null and line.has_method("apply_look"):
			line.call("apply_look", look)
		elif line != null:
			line.call("recolor", look.get("color", Color.WHITE))


func window_icon(window: String) -> String:
	return str((looks.get(window, {}) as Dictionary).get("icon", ""))


func window_color(window: String) -> Color:
	return (looks.get(window, {}) as Dictionary).get("color", Color(0.6, 0.6, 0.65))


## The way a staff member walks from one point to another (set space): through
## the staff door when it crosses the counter wall, never through it.
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var behind_from := from.z < COUNTER_Z
	var behind_to := to.z < COUNTER_Z
	if behind_from != behind_to:
		var door_x := (STAFF_DOOR_X.x + STAFF_DOOR_X.y) * 0.5
		var staff_side := Vector3(door_x, 0.0, COUNTER_Z - 0.9)
		var lobby_side := Vector3(door_x, 0.0, COUNTER_Z + 0.9)
		if behind_from:
			out.append(Vector3(from.x, 0.0, staff_side.z))
			out.append(staff_side)
			out.append(lobby_side)
		else:
			out.append(lobby_side)
			out.append(staff_side)
			out.append(Vector3(to.x, 0.0, staff_side.z))
	out.append(to)
	return out


## Every collider in the set on or off (the legacy Border Return's lanes run
## through this pad until R2 chunk 6 replaces them; world.gd turns it off then).
func set_solid(on: bool) -> void:
	for node: Node in find_children("*", "CollisionShape3D", true, false):
		(node as CollisionShape3D).disabled = not on
	set_meta("solid", on)


func _process(_delta: float) -> void:
	# Out of sight (the whole crew on the yard 1,000 m away), the staff stop
	# breathing and the room stops drawing.
	# With no camera at all (a headless host, a bot) nobody watches the staff, so
	# they don't run; the room stays "visible" there so the headless checks count it.
	# Their play() still records state and state_at for when they run again.
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var far := camera != null and camera.global_position.distance_to(global_position) > Constants.ANNEX_CULL_DISTANCE
	if far != _far:
		_far = far
		visible = not far
	var staff_off := far or camera == null
	if _staff != null and staff_off != (_staff.process_mode == Node.PROCESS_MODE_DISABLED):
		_staff.process_mode = Node.PROCESS_MODE_DISABLED if staff_off else Node.PROCESS_MODE_INHERIT
	_update_lamp_shadows()


## Ceiling lights cast shadows only at the top Settings shadow level.
func _update_lamp_shadows() -> void:
	var settings := get_tree().root.get_node_or_null("Settings") if is_inside_tree() else null
	var level := 0
	if settings != null and settings.has_method("get_value"):
		level = int(settings.call("get_value", "video", "shadows"))
	if level == _lamps_checked:
		return
	_lamps_checked = level
	var top := Constants.SHADOW_LEVELS.size() - 1
	for light: Node in find_children("*", "OmniLight3D", true, false):
		(light as OmniLight3D).shadow_enabled = level >= top


# ---------------------------------------------------------------- the build

func _build() -> void:
	var defaults := looks_for(set_seed)
	for index: int in 3:
		looks[WINDOWS[index]] = defaults[index]
	looks["D"] = {"icon": "", "color": Color(0.55, 0.52, 0.5)}
	_hide_pad_floor()
	var shell := _HouseKit.new()
	var furniture := _MeshKit.new()
	_ground(shell, furniture)
	_outside(shell, furniture)
	_room(shell, furniture)
	_lobby(shell, furniture)
	shell.call("commit", self, "Shell")
	var furnished := _Stylized.instance(furniture.commit(), {"roughness": 0.85})
	furnished.name = "Furniture"
	add_child(furnished)
	var glass := _glass()
	_colliders()
	_windows()
	_floor_lines()
	_desk()
	_appliances()
	_fixtures()
	_doors()
	_markers()
	_paths()
	_staff = Node3D.new()
	_staff.name = "Staff"
	add_child(_staff)
	_staff_bodies()
	add_child(_Props.staff_door(STAFF_DOOR_X.y - STAFF_DOOR_X.x, _staff))
	(get_node("StaffDoor") as Node3D).position = Vector3((STAFF_DOOR_X.x + STAFF_DOOR_X.y) * 0.5, 0.0, COUNTER_Z)
	_bake(furnished, "bake")
	_bake(glass, "bake_glass")
	set_meta("solid", true)


## The zone's own pad floor (world.tscn) is a sand-colored box: the set lays its
## own floors, sidewalks and street over it, so the old one stays hidden.
func _hide_pad_floor() -> void:
	var pad := get_parent().get_node_or_null("Floor/Mesh") as Node3D if get_parent() != null else null
	if pad != null:
		pad.visible = false


## Lawn round the building, the sidewalk, the curb and the street out front.
func _ground(shell: RefCounted, furniture: RefCounted) -> void:
	var half := 20.0
	var back := -half
	# Lawn behind and beside the building, out to the pad's edge.
	shell.call("box", Vector3(half * 2.0, 0.04, 6.75 - back), Vector3(0.0, -0.02, (back + 6.75) * 0.5), LAWN, "grass")
	# The sidewalk and forecourt, then the curb, then the street.
	shell.call("box", Vector3(half * 2.0, 0.04, SIDEWALK_END - 6.75), Vector3(0.0, -0.015, (6.75 + SIDEWALK_END) * 0.5), CONCRETE, "concrete", Basis.IDENTITY, {"snow": 1.0})
	furniture.call("box", Vector3(0.0, 0.02, SIDEWALK_END - 0.1), Vector3(half * 2.0, 0.05, 0.2), CONCRETE.lightened(0.15))
	# The street is its own mesh: a road's painted lines are laid out round its
	# own middle (props/surfaces.gd), so it sits centered on the street.
	var street := Node3D.new()
	street.name = "Street"
	add_child(street)
	street.position = Vector3(0.0, 0.0, (SIDEWALK_END + STREET_END) * 0.5)
	var road := _HouseKit.new()
	# Out into the haze both ways (R2c van): the Courtesy Shuttle comes down it from
	# Constants.VAN_ANNEX_RETURN_FROM off and drives away along it.
	road.call("box", Vector3(half * 2.0 + Constants.VAN_ANNEX_STREET_EXTRA, 0.04, STREET_END - SIDEWALK_END), Vector3(0.0, -0.02, 0.0), ASPHALT, "road", Basis.IDENTITY, {"params": _Surfaces.road_params("double_yellow_edges", (STREET_END - SIDEWALK_END) * 0.5 - 0.3, 3.0)})
	road.call("commit", street, "Road")


## The building's outside: lavender stucco walls, the parapet with its signs, the
## storefront glass, the awning over the doors, the planter that splits the walk
## in from the forecourt out, the flag with nothing on it.
func _outside(shell: RefCounted, furniture: RefCounted) -> void:
	var w := Constants.ANNEX_SIZE.x * 0.5
	var d := Constants.ANNEX_SIZE.z * 0.5
	var outer_w := w + WALL
	var outer_d := d + WALL
	var height := PARAPET
	# Back and side walls, outside skin.
	shell.call("box", Vector3(outer_w * 2.0, height, 0.12), Vector3(0.0, height * 0.5, -outer_d + 0.06), LAVENDER, "stucco")
	for side: float in [-1.0, 1.0]:
		var x := side * (outer_w - 0.06)
		if side < 0.0:
			# The west wall has the visitors' side door.
			_wall_with_gaps(shell, Vector3(x, 0.0, 0.0), outer_d * 2.0, height, 0.12, LAVENDER, "stucco", true, [Vector3(SIDE_DOOR_Z, SIDE_DOOR_WIDTH, DOOR_HEIGHT)])
		else:
			shell.call("box", Vector3(0.12, height, outer_d * 2.0), Vector3(x, height * 0.5, 0.0), LAVENDER, "stucco")
	# The front: the doors, the turnstile's passage and two storefront windows.
	var front_z := outer_d - 0.06
	var gaps := [
		Vector3(ENTRANCE_X, ENTRANCE_WIDTH + 0.2, DOOR_HEIGHT + 0.1),
		Vector3((EXIT_X.x + EXIT_X.y) * 0.5, EXIT_X.y - EXIT_X.x, DOOR_HEIGHT + 0.1),
	]
	_wall_with_gaps(shell, Vector3(0.0, 0.0, front_z), outer_w * 2.0, height, 0.12, LAVENDER, "stucco", false, gaps, [Vector4(-8.4, 2.7, 0.6, 2.5), Vector4(-1.2, 5.8, 0.6, 2.5)])
	# A darker band at the base and the parapet's cap, all round.
	_wall_with_gaps(shell, Vector3(0.0, 0.0, front_z + 0.075), outer_w * 2.0 + 0.02, 0.35, 0.03, LAVENDER.darkened(0.3), "stucco", false, gaps)
	# Thresholds across the wall's thickness in each doorway (the lawn under the
	# pad would show between the lobby floor and the sidewalk).
	for gap: Vector3 in gaps:
		shell.call("box", Vector3(gap.y, 0.03, WALL + 0.06), Vector3(gap.x, 0.004, d_inner_front() + WALL * 0.5), CONCRETE.darkened(0.1), "concrete")
	shell.call("box", Vector3(WALL + 0.06, 0.03, SIDE_DOOR_WIDTH), Vector3(-w - WALL * 0.5, 0.004, SIDE_DOOR_Z), CONCRETE.darkened(0.1), "concrete")
	if not cutaway:
		shell.call("box", Vector3(outer_w * 2.0 + 0.3, 0.22, outer_d * 2.0 + 0.3), Vector3(0.0, height + 0.11, 0.0), LAVENDER.darkened(0.25), "concrete")
	# Storefront frames.
	for span: Vector4 in [Vector4(-8.4, 2.7, 0.6, 2.5), Vector4(-1.2, 5.8, 0.6, 2.5)]:
		var cx := span.x + span.y * 0.5
		shell.call("box", Vector3(span.y + 0.12, 0.08, 0.16), Vector3(cx, span.z, front_z + 0.02), DARK, "metal")
		shell.call("box", Vector3(span.y + 0.12, 0.08, 0.16), Vector3(cx, span.w, front_z + 0.02), DARK, "metal")
		for step: int in int(span.y / 1.6) + 1:
			var x := span.x + minf(float(step) * 1.6, span.y)
			shell.call("box", Vector3(0.07, span.w - span.z, 0.14), Vector3(x, (span.z + span.w) * 0.5, front_z + 0.02), DARK, "metal")
		# Blinds half down behind the glass, as every office has them.
		for slat: int in 9:
			furniture.call("box", Vector3(cx, span.w - 0.06 - float(slat) * 0.075, front_z - 0.12), Vector3(span.y - 0.1, 0.012, 0.04), Color(0.92, 0.9, 0.84), Basis(Vector3.RIGHT, 0.4))
	# Door frames for the entrance and the exit.
	for gap: Vector3 in gaps:
		for side: float in [-1.0, 1.0]:
			shell.call("box", Vector3(0.1, gap.z, 0.2), Vector3(gap.x + side * (gap.y * 0.5 - 0.05), gap.z * 0.5, front_z), DARK, "metal")
		shell.call("box", Vector3(gap.y, 0.12, 0.2), Vector3(gap.x, gap.z - 0.06, front_z), DARK, "metal")
	# A lavender awning over the entrance, and the sign boards.
	shell.call("box", Vector3(3.6, 0.1, 1.4), Vector3(ENTRANCE_X, 2.75, front_z + 0.7), LAVENDER.darkened(0.15), "fabric", Basis(Vector3.RIGHT, 0.12), {"snow": 1.0})
	# The name across the parapet, the form by the door, the banner over the glass.
	shell.call("box", Vector3(6.4, 1.05, 0.08), Vector3(-1.2, 3.72, front_z + 0.08), Color(0.98, 0.97, 0.94), "fabric")
	_sign(_Strings.TOWN_SIGNS["field_office_sign"], Vector3(-1.2, 3.72, front_z + 0.125), 48, Color(0.36, 0.24, 0.55), 0.0062)
	furniture.call("box", Vector3(-2.05, 1.5, front_z + 0.08), Vector3(1.2, 0.8, 0.04), Color(0.97, 0.97, 0.95))
	_sign(_Strings.TOWN_SIGNS["field_office_form"], Vector3(-2.05, 1.5, front_z + 0.105), 22, Color(0.2, 0.2, 0.24), 0.0042)
	shell.call("box", Vector3(3.4, 0.5, 0.05), Vector3(2.4, 2.86, front_z + 0.08), Color(0.98, 0.97, 0.94), "fabric")
	_sign(_Strings.TOWN_SIGNS["field_office_banner"], Vector3(2.4, 2.86, front_z + 0.112), 44, Color(0.36, 0.24, 0.55), 0.0058)
	# The planter between the walk in and the forecourt out: a low box, a hedge in it.
	shell.call("box", Vector3(0.7, 0.55, SIDEWALK_END - 0.6 - (outer_d)), Vector3(PLANTER_X, 0.275, (outer_d + SIDEWALK_END - 0.6) * 0.5), CONCRETE.darkened(0.15), "concrete")
	for step: int in 7:
		var z := outer_d + 0.5 + float(step) * 0.7
		furniture.call("blob", Vector3(PLANTER_X, 0.8, z), Vector3(0.42, 0.38, 0.45), HEDGE.lightened(0.04 * float(step % 3)), {"detail": 1, "lumps": 0.3, "seed": 70 + step})
	# The flag: a pole and a lavender flag with nothing on it.
	furniture.call("tube", PackedVector3Array([Vector3(-8.4, 0.0, 9.6), Vector3(-8.4, 6.0, 9.6)]), PackedFloat32Array([0.05, 0.04]), STEEL, 6, {"jitter": 0.0})
	furniture.call("box", Vector3(-7.75, 5.55, 9.6), Vector3(1.3, 0.8, 0.02), LAVENDER, Basis(Vector3.UP, 0.15))
	# A bench and a bin at the curb, for whoever is waiting for the shuttle back.
	furniture.call("box", Vector3(6.0, 0.45, 10.4), Vector3(1.8, 0.06, 0.45), WOOD)
	for x: float in [5.3, 6.7]:
		furniture.call("box", Vector3(x, 0.22, 10.4), Vector3(0.06, 0.44, 0.4), DARK)
	furniture.call("cone", Vector3(8.0, 0.0, 10.6), 0.28, 0.85, Color(0.3, 0.42, 0.36), 10)


## The front wall's inside face (z).
func d_inner_front() -> float:
	return Constants.ANNEX_SIZE.z * 0.5


## A wall along x (or along z when along_z) through at, with doorway gaps
## [Vector3(center, width, height)] cut from the floor up, and window holes
## [Vector4(start, width, bottom, top)] cut through it.
func _wall_with_gaps(shell: RefCounted, at: Vector3, length: float, height: float, thick: float, color: Color, surface: String, along_z: bool, gaps: Array, holes: Array = []) -> void:
	var cuts: Array = []
	for gap: Vector3 in gaps:
		cuts.append(Vector4(gap.x - gap.y * 0.5, gap.y, 0.0, gap.z))
	for hole: Vector4 in holes:
		cuts.append(hole)
	cuts.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.x < b.x)
	var start := -length * 0.5
	for cut: Vector4 in cuts:
		if cut.x > start:
			_wall_piece(shell, at, start, cut.x, 0.0, height, thick, color, surface, along_z)
		# Below and above the cut.
		if cut.z > 0.0:
			_wall_piece(shell, at, cut.x, cut.x + cut.y, 0.0, cut.z, thick, color, surface, along_z)
		_wall_piece(shell, at, cut.x, cut.x + cut.y, cut.w, height, thick, color, surface, along_z)
		start = cut.x + cut.y
	if start < length * 0.5:
		_wall_piece(shell, at, start, length * 0.5, 0.0, height, thick, color, surface, along_z)


func _wall_piece(shell: RefCounted, at: Vector3, from: float, to: float, bottom: float, top: float, thick: float, color: Color, surface: String, along_z: bool) -> void:
	if to - from < 0.01 or top - bottom < 0.01:
		return
	var mid := (from + to) * 0.5
	var size := Vector3(thick, top - bottom, to - from) if along_z else Vector3(to - from, top - bottom, thick)
	var center := Vector3(at.x, (bottom + top) * 0.5, mid) if along_z else Vector3(mid, (bottom + top) * 0.5, at.z)
	shell.call("box", size, center, color, surface)


## The room: the inside skin of every wall with a wainscot, the tiled floor, the
## drop ceiling, and the counter wall with a hole for each service window.
func _room(shell: RefCounted, furniture: RefCounted) -> void:
	var w := Constants.ANNEX_SIZE.x * 0.5
	var d := Constants.ANNEX_SIZE.z * 0.5
	var h := Constants.ANNEX_SIZE.y
	var thick := WALL - 0.12
	var inner := {"snow": 0.0}
	shell.call("box", Vector3(w * 2.0, 0.03, d * 2.0), Vector3(0.0, 0.0, 0.0), FLOOR, "tile_floor", Basis.IDENTITY, inner)
	if not cutaway:
		shell.call("box", Vector3(w * 2.0, 0.06, d * 2.0), Vector3(0.0, h + 0.03, 0.0), CEILING, "plain", Basis.IDENTITY, inner)
	# The drop ceiling's grid.
	for step: int in 0 if cutaway else 12:
		var x := -w + float(step + 1) * (w * 2.0) / 13.0
		furniture.call("box", Vector3(x, h - 0.005, 0.0), Vector3(0.03, 0.01, d * 2.0), Color(0.8, 0.79, 0.75))
	for step: int in 0 if cutaway else 8:
		var z := -d + float(step + 1) * (d * 2.0) / 9.0
		furniture.call("box", Vector3(0.0, h - 0.005, z), Vector3(w * 2.0, 0.01, 0.03), Color(0.8, 0.79, 0.75))
	# The inside skins.
	shell.call("box", Vector3(w * 2.0, h, thick), Vector3(0.0, h * 0.5, -d - thick * 0.5), INSIDE_WALL, "plain", Basis.IDENTITY, inner)
	shell.call("box", Vector3(thick, h, d * 2.0), Vector3(w + thick * 0.5, h * 0.5, 0.0), INSIDE_WALL, "plain", Basis.IDENTITY, inner)
	_wall_with_gaps(shell, Vector3(-w - thick * 0.5, 0.0, 0.0), d * 2.0, h, thick, INSIDE_WALL, "plain", true, [Vector3(SIDE_DOOR_Z, SIDE_DOOR_WIDTH, DOOR_HEIGHT)])
	var front_gaps := [
		Vector3(ENTRANCE_X, ENTRANCE_WIDTH + 0.2, DOOR_HEIGHT + 0.1),
		Vector3((EXIT_X.x + EXIT_X.y) * 0.5, EXIT_X.y - EXIT_X.x, DOOR_HEIGHT + 0.1),
	]
	_wall_with_gaps(shell, Vector3(0.0, 0.0, d + thick * 0.5), w * 2.0, h, thick, INSIDE_WALL, "plain", false, front_gaps, [Vector4(-8.4, 2.7, 0.6, 2.5), Vector4(-1.2, 5.8, 0.6, 2.5)])
	# A wainscot band round the lobby, and a rubber base.
	for z: float in [-d + 0.01, d - 0.01]:
		furniture.call("box", Vector3(0.0, 0.05, z), Vector3(w * 2.0, 0.1, 0.02), DARK)
	for x: float in [-w + 0.01, w - 0.01]:
		furniture.call("box", Vector3(x, 0.05, 0.0), Vector3(0.02, 0.1, d * 2.0), DARK)
		furniture.call("box", Vector3(x, 0.95, (COUNTER_Z + d) * 0.5), Vector3(0.025, 0.08, d - COUNTER_Z), WAINSCOT)
	# The counter wall: solid up to the counter, the windows' holes, solid above,
	# and the staff door's gap; its lobby face lavender up to the plaques' rail.
	var holes: Array = []
	for x: float in WINDOW_X:
		holes.append(Vector4(x - 0.83, 1.66, 0.98, 2.33))
	var counter_gaps := [Vector3((STAFF_DOOR_X.x + STAFF_DOOR_X.y) * 0.5, STAFF_DOOR_X.y - STAFF_DOOR_X.x, DOOR_HEIGHT)]
	_wall_with_gaps(shell, Vector3(0.0, 0.0, COUNTER_Z - 0.1), w * 2.0, h, 0.2, INSIDE_WALL.darkened(0.04), "plain", false, counter_gaps, holes)
	furniture.call("box", Vector3(-w * 0.5 + (STAFF_DOOR_X.x) * 0.5, 0.49, COUNTER_Z + 0.005), Vector3(STAFF_DOOR_X.x + w, 0.96, 0.02), WAINSCOT)
	furniture.call("box", Vector3(0.0, 3.05, COUNTER_Z + 0.005), Vector3(w * 2.0, 0.12, 0.02), WAINSCOT)
	# The staff side: carpet tiles and a corkboard nobody reads.
	shell.call("box", Vector3(w * 2.0, 0.01, COUNTER_Z - 0.2 + d), Vector3(0.0, 0.02, (-d + COUNTER_Z - 0.2) * 0.5), Color(0.38, 0.36, 0.42), "fabric", Basis.IDENTITY, inner)
	furniture.call("box", Vector3(-1.9, 1.6, -d + 0.03), Vector3(2.4, 1.0, 0.04), Color(0.7, 0.55, 0.35))
	for note: int in 7:
		furniture.call("box", Vector3(-2.9 + float(note) * 0.32, 1.55 + 0.18 * float(note % 3 - 1), -d + 0.055), Vector3(0.18, 0.22, 0.01), [Color(1.0, 0.92, 0.45), Color(0.75, 0.9, 1.0), Color(1.0, 0.75, 0.8)][note % 3])


## The lobby: the waiting chairs facing the windows, ficus trees, the greeter's
## podium with the co-signer sheet and the empty number dispenser, posters.
func _lobby(shell: RefCounted, furniture: RefCounted) -> void:
	var inner := {"snow": 0.0}
	for row: int in 2:
		var z := 1.9 + float(row) * 1.1
		# A steel beam with five seats bolted on.
		furniture.call("box", Vector3(-4.0, 0.32, z + 0.05), Vector3(4.6, 0.06, 0.08), STEEL.darkened(0.2))
		for leg: float in [-6.0, -2.0]:
			furniture.call("box", Vector3(leg, 0.16, z + 0.05), Vector3(0.06, 0.32, 0.4), STEEL.darkened(0.2))
		for seat: int in 6:
			var x := -5.9 + float(seat) * 0.76
			shell.call("box", Vector3(0.56, 0.07, 0.46), Vector3(x, 0.44, z), CHAIR, "fabric", Basis.IDENTITY, inner)
			shell.call("box", Vector3(0.56, 0.42, 0.06), Vector3(x, 0.72, z + 0.25), CHAIR, "fabric", Basis(Vector3.RIGHT, -0.12), inner)
			# The steel arm between seats.
			furniture.call("box", Vector3(x + 0.38, 0.6, z + 0.02), Vector3(0.05, 0.04, 0.4), STEEL.darkened(0.2))
			furniture.call("box", Vector3(x + 0.38, 0.5, z - 0.15), Vector3(0.04, 0.2, 0.04), STEEL.darkened(0.2))
	# Ficus trees in pots in the corners.
	for spot: Vector3 in [Vector3(-8.3, 0.0, 5.7), Vector3(-8.3, 0.0, -3.7), Vector3(1.1, 0.0, 5.7), Vector3(8.3, 0.0, 5.6)]:
		furniture.call("cone", spot, 0.28, 0.5, Color(0.72, 0.42, 0.28), 10)
		furniture.call("tube", PackedVector3Array([spot + Vector3(0.0, 0.4, 0.0), spot + Vector3(0.05, 1.3, 0.02)]), PackedFloat32Array([0.035, 0.025]), Color(0.42, 0.3, 0.2), 5, {"jitter": 0.0})
		for puff: int in 4:
			var angle := float(puff) * 1.7
			furniture.call("blob", spot + Vector3(cos(angle) * 0.22, 1.25 + float(puff % 2) * 0.28, sin(angle) * 0.22), Vector3(0.32, 0.26, 0.32), Color(0.22, 0.48, 0.24).lightened(0.05 * float(puff)), {"detail": 1, "lumps": 0.35, "seed": int(spot.x * 10.0) + puff})
	# The greeter's podium by the doors, the sheet on its chain, the dispenser.
	shell.call("box", Vector3(1.2, 1.0, 0.6), Vector3(-6.5, 0.5, 4.5), WOOD, "planks", Basis.IDENTITY, inner)
	shell.call("box", Vector3(1.3, 0.05, 0.7), Vector3(-6.5, 1.025, 4.5), WOOD.darkened(0.2), "planks", Basis.IDENTITY, inner)
	furniture.call("box", Vector3(-6.5, 0.6, 4.81), Vector3(1.0, 0.5, 0.02), LAVENDER)
	_NiceSeal.add(furniture, Vector3(-6.5, 0.6, 4.825), 0.18, Vector3(0.0, 0.0, 1.0))
	# The number dispenser on a post: red, empty, and sorry about it.
	furniture.call("tube", PackedVector3Array([Vector3(-5.5, 0.0, 5.3), Vector3(-5.5, 1.15, 5.3)]), PackedFloat32Array([0.03, 0.03]), STEEL, 6, {"jitter": 0.0})
	furniture.call("blob", Vector3(-5.5, 1.25, 5.3), Vector3(0.14, 0.12, 0.12), Color(0.86, 0.18, 0.16), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	# Posters: boards on the walls, their words as labels.
	furniture.call("box", Vector3(-8.985, 1.9, 2.6), Vector3(0.02, 1.0, 0.8), Color(0.98, 0.95, 0.85))
	furniture.call("box", Vector3(8.985, 1.95, 4.4), Vector3(0.02, 0.9, 1.1), Color(0.86, 0.94, 0.98))


## The see-through glass: the storefront windows (and, baked in at the end, the
## service windows' panes), one mesh.
func _glass() -> MeshInstance3D:
	var kit := _MeshKit.new()
	var front_z := Constants.ANNEX_SIZE.z * 0.5 + 0.12
	for span: Vector4 in [Vector4(-8.4, 2.7, 0.6, 2.5), Vector4(-1.2, 5.8, 0.6, 2.5)]:
		kit.box(Vector3(span.x + span.y * 0.5, (span.z + span.w) * 0.5, front_z), Vector3(span.y, span.w - span.z, 0.02), Color.WHITE)
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = kit.commit()
	glass.material_override = _Props.glass_material()
	glass.set_meta("keep_material", true)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)
	return glass


## One body for the room's walls, ceiling and the lobby's solid furniture. The
## windows, doors, desk, appliances and turnstile carry their own.
func _colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	var w := Constants.ANNEX_SIZE.x * 0.5
	var d := Constants.ANNEX_SIZE.z * 0.5
	var h := PARAPET
	var t := WALL
	var boxes: Array = [
		# Back, east, the ceiling.
		[Vector3(w * 2.0 + t * 2.0, h, t), Vector3(0.0, h * 0.5, -d - t * 0.5)],
		[Vector3(t, h, d * 2.0 + t * 2.0), Vector3(w + t * 0.5, h * 0.5, 0.0)],
		[Vector3(w * 2.0, 0.2, d * 2.0), Vector3(0.0, Constants.ANNEX_SIZE.y + 0.1, 0.0)],
		# The west wall round the side door.
		[Vector3(t, h, SIDE_DOOR_Z - SIDE_DOOR_WIDTH * 0.5 + d + t), Vector3(-w - t * 0.5, h * 0.5, (-d - t + SIDE_DOOR_Z - SIDE_DOOR_WIDTH * 0.5) * 0.5)],
		[Vector3(t, h, d + t - SIDE_DOOR_Z - SIDE_DOOR_WIDTH * 0.5), Vector3(-w - t * 0.5, h * 0.5, (d + t + SIDE_DOOR_Z + SIDE_DOOR_WIDTH * 0.5) * 0.5)],
		[Vector3(t, h - DOOR_HEIGHT, SIDE_DOOR_WIDTH), Vector3(-w - t * 0.5, (h + DOOR_HEIGHT) * 0.5, SIDE_DOOR_Z)],
		# The planter, the podium, the chair rows.
		[Vector3(0.7, 1.0, SIDEWALK_END - 0.6 - d - t), Vector3(PLANTER_X, 0.5, (d + t + SIDEWALK_END - 0.6) * 0.5)],
		[Vector3(1.2, 1.05, 0.6), Vector3(-6.5, 0.525, 4.5)],
		[Vector3(4.9, 0.9, 0.7), Vector3(-4.0, 0.45, 2.0)],
		[Vector3(4.9, 0.9, 0.7), Vector3(-4.0, 0.45, 3.1)],
	]
	# The front wall, round the entrance and the exit.
	var front_z := d + t * 0.5
	var spans: Array[Vector2] = []
	var cursor := -w - t
	for gap: Vector2 in [Vector2(ENTRANCE_X - ENTRANCE_WIDTH * 0.5 - 0.1, ENTRANCE_X + ENTRANCE_WIDTH * 0.5 + 0.1), EXIT_X]:
		spans.append(Vector2(cursor, gap.x))
		boxes.append([Vector3(gap.y - gap.x, h - DOOR_HEIGHT - 0.1, t), Vector3((gap.x + gap.y) * 0.5, (h + DOOR_HEIGHT + 0.1) * 0.5, front_z)])
		cursor = gap.y
	spans.append(Vector2(cursor, w + t))
	for span: Vector2 in spans:
		boxes.append([Vector3(span.y - span.x, h, t), Vector3((span.x + span.y) * 0.5, h * 0.5, front_z)])
	# The counter wall: below the counters and above the glass, and between windows.
	var cut := 0.83
	var pieces: Array[Vector2] = []
	cursor = -w
	for x: float in WINDOW_X:
		pieces.append(Vector2(cursor, x - cut))
		cursor = x + cut
	pieces.append(Vector2(cursor, STAFF_DOOR_X.x))
	pieces.append(Vector2(STAFF_DOOR_X.y, w))
	for piece: Vector2 in pieces:
		boxes.append([Vector3(piece.y - piece.x, Constants.ANNEX_SIZE.y, 0.2), Vector3((piece.x + piece.y) * 0.5, Constants.ANNEX_SIZE.y * 0.5, COUNTER_Z - 0.1)])
	for x: float in WINDOW_X:
		boxes.append([Vector3(cut * 2.0, 0.98, 0.2), Vector3(x, 0.49, COUNTER_Z - 0.1)])
		boxes.append([Vector3(cut * 2.0, Constants.ANNEX_SIZE.y - 2.33, 0.2), Vector3(x, (Constants.ANNEX_SIZE.y + 2.33) * 0.5, COUNTER_Z - 0.1)])
	boxes.append([Vector3(STAFF_DOOR_X.y - STAFF_DOOR_X.x, Constants.ANNEX_SIZE.y - DOOR_HEIGHT, 0.2), Vector3((STAFF_DOOR_X.x + STAFF_DOOR_X.y) * 0.5, (Constants.ANNEX_SIZE.y + DOOR_HEIGHT) * 0.5, COUNTER_Z - 0.1)])
	for entry: Array in boxes:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = entry[0]
		shape.shape = box
		shape.position = entry[1]
		body.add_child(shape)


## The four service windows in the counter wall, the clerks' stools behind them.
func _windows() -> void:
	var holder := Node3D.new()
	holder.name = "Windows"
	add_child(holder)
	for index: int in WINDOWS.size():
		var id := WINDOWS[index]
		var window: Node3D = _Props.service_window(id, looks[id])
		holder.add_child(window)
		window.position = Vector3(WINDOW_X[index], 0.0, COUNTER_Z)
		# Break spots: where this window's clerk goes on a break (by the cooler,
		# the coffee machine, the copier; a little apart per window).
		var spots: Array[Vector3] = [
			Vector3(7.7, 0.0, -0.4), Vector3(7.65, 0.0, 2.6), Vector3(7.5, 0.0, 1.2),
		]
		for spot: int in 3:
			var marker := window.get_node("BreakSpot%d" % spot) as Node3D
			marker.global_position = to_global(spots[spot] + Vector3(0.0, 0.0, 0.32 * float(index) - 0.5))
			marker.global_rotation.y = PI * 0.5
	# Window D is shut: blinds down, lamp off, its clock on the sill.
	var d_window := holder.get_node("D")
	d_window.call("set_state", &"blind_down", -1000.0)
	d_window.call("set_state", &"lamp_off", -1000.0)
	# A, B and C start lit and serving.
	for id: String in ["A", "B", "C"]:
		holder.get_node(id).call("set_state", &"lamp_on", -1000.0)


## The colored lines from the chairs to windows A, B and C.
func _floor_lines() -> void:
	var holder := Node3D.new()
	holder.name = "FloorLines"
	add_child(holder)
	for index: int in 3:
		var id := WINDOWS[index]
		var x := WINDOW_X[index]
		# Each from its own place along the chairs' front, none crossing another.
		var start_x := -5.6 + float(index) * 1.4
		var lane_z := 0.6 - float(index) * 0.35
		var points := PackedVector3Array([
			Vector3(start_x, 0.0, 1.45),
			Vector3(start_x, 0.0, lane_z),
			Vector3(x + 0.35, 0.0, lane_z),
			Vector3(x + 0.35, 0.0, COUNTER_Z + 3.4),
		])
		# The window's footprints are painted in its line's color (R2b).
		var feet := PackedVector3Array()
		for spot: int in 4:
			for side: float in [-1.0, 1.0]:
				feet.append(Vector3(x + side * 0.12, 0.0, COUNTER_Z + _Props.FOOT_Z + float(spot) * _Props.FOOT_STEP))
		var line: Node3D = _Props.floor_line(points, looks[id]["color"], feet)
		line.name = id
		holder.add_child(line)
		line.call("apply_look", looks[id])


## The Head NICE BOY's desk in the lobby's back corner: a wide desk, his chair,
## the velvet pad and the big stamp on it, the nameplate, an IN tray.
func _desk() -> void:
	var desk: Node3D = _Props.Prop.new()
	desk.name = "HeadDesk"
	add_child(desk)
	desk.position = Vector3(7.2, 0.0, -2.4)
	var kit := _MeshKit.new()
	kit.box(Vector3(0.0, 0.76, 0.0), Vector3(0.9, 0.06, 1.8), WOOD.darkened(0.1))
	kit.box(Vector3(-0.42, 0.38, 0.0), Vector3(0.05, 0.74, 1.75), WOOD.darkened(0.3))
	for z: float in [-0.85, 0.85]:
		kit.box(Vector3(0.0, 0.38, z), Vector3(0.85, 0.74, 0.05), WOOD.darkened(0.3))
	# His chair behind it, a big one.
	kit.cone(Vector3(0.95, 0.0, 0.0), 0.28, 0.04, DARK, 8)
	kit.box(Vector3(0.95, 0.25, 0.0), Vector3(0.05, 0.42, 0.05), STEEL)
	kit.box(Vector3(0.95, 0.5, 0.0), Vector3(0.55, 0.1, 0.55), Color(0.3, 0.12, 0.16))
	kit.box(Vector3(1.22, 0.95, 0.0), Vector3(0.1, 0.85, 0.55), Color(0.3, 0.12, 0.16))
	# The velvet pad, the nameplate's block, the IN tray, a framed photo of a stamp.
	kit.box(Vector3(0.0, 0.8, 0.45), Vector3(0.5, 0.025, 0.4), Color(0.62, 0.12, 0.2))
	kit.box(Vector3(-0.35, 0.83, -0.2), Vector3(0.08, 0.08, 0.6), Color(0.88, 0.7, 0.28))
	kit.box(Vector3(0.1, 0.8, -0.55), Vector3(0.4, 0.03, 0.32), STEEL)
	kit.box(Vector3(0.25, 0.92, -0.2), Vector3(0.04, 0.22, 0.18), DARK, Basis(Vector3.FORWARD, 0.15))
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.7})
	view.name = "Look"
	view.set_meta("bake", true)
	desk.add_child(view)
	_sign(_Strings.ANNEX_SIGNS["head_desk"], Vector3(-0.395, 0.83, -0.2), 26, DARK, 0.0035, desk, -PI * 0.5)
	_spot(desk, "DeskSpot", Vector3(-1.15, 0.0, 0.2), -PI * 0.5)
	_spot(desk, "Pad", Vector3(0.0, 0.815, 0.45))
	var stamp: Node3D = _Props.big_stamp()
	desk.add_child(stamp)
	stamp.call("set_rest", Vector3(0.0, 0.815, 0.45))
	var body := StaticBody3D.new()
	body.name = "Body"
	desk.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.8, 1.8)
	shape.shape = box
	shape.position = Vector3(0.0, 0.4, 0.0)
	body.add_child(shape)


## The copier (it jams), the cooler (it glugs), the coffee machine (it brews).
func _appliances() -> void:
	for entry: Array in [["copier", Vector3(8.45, 0.0, 1.2)], ["cooler", Vector3(8.65, 0.0, -0.4)], ["coffee", Vector3(8.6, 0.0, 2.6)]]:
		var made: Node3D = _Props.appliance(entry[0])
		add_child(made)
		made.position = entry[1]
		made.rotation.y = -PI * 0.5


## The ceiling's light rows, the wall clock, the NOW SERVING board, the co-signer
## sheet, the OUTGOING tray, the turnstile, the dispenser and the sticky notes.
func _fixtures() -> void:
	var rows := Node3D.new()
	rows.name = "LightRows"
	add_child(rows)
	for index: int in Constants.ANNEX_LIGHT_ROWS:
		var row: Node3D = _Props.light_row(index, Constants.ANNEX_SIZE.x - 3.0, 5)
		rows.add_child(row)
		row.position = Vector3(0.0, Constants.ANNEX_SIZE.y - 0.015, LIGHT_ROW_Z[index])
	var clock: Node3D = _Props.wall_clock()
	add_child(clock)
	clock.position = Vector3(-Constants.ANNEX_SIZE.x * 0.5 + 0.04, 2.45, -1.6)
	clock.rotation.y = PI * 0.5
	var board: Node3D = _Props.now_serving()
	add_child(board)
	board.position = Vector3(-1.9, 2.7, COUNTER_Z + 0.04)
	var sheet: Node3D = _Props.cosign_sheet()
	add_child(sheet)
	sheet.position = Vector3(-6.7, 1.05, 4.45)
	sheet.rotation.y = -0.2
	_sign(_Strings.ANNEX_SIGNS["cosign"], Vector3(-6.5, 0.6, 4.84), 24, Color(0.25, 0.18, 0.4), 0.0045, self, 0.0)
	# Against the front wall beside the turnstile, its label to the lobby: out of
	# the way of the arms and of anyone walking up to them (R2b).
	var tray: Node3D = _Props.outgoing_tray()
	add_child(tray)
	tray.position = Vector3(4.7, 0.0, Constants.ANNEX_SIZE.z * 0.5 - 0.3)
	tray.rotation.y = PI
	var gate: Node3D = _Props.turnstile(TURNSTILE_PASSAGE, DOOR_HEIGHT + 0.1)
	add_child(gate)
	gate.position = Vector3(TURNSTILE_X, 0.0, Constants.ANNEX_SIZE.z * 0.5 + WALL * 0.5)
	var dispenser := Node3D.new()
	dispenser.name = "Dispenser"
	add_child(dispenser)
	dispenser.position = Vector3(-5.5, 1.25, 5.3)
	_sign(_Strings.ANNEX_SIGNS["dispenser"], Vector3(0.0, 0.0, 0.125), 20, Color(1.0, 0.95, 0.85), 0.003, dispenser, 0.0)
	var stickies := Node3D.new()
	stickies.name = "Stickies"
	add_child(stickies)
	for index: int in WINDOWS.size():
		_spot(stickies, WINDOWS[index], Vector3(WINDOW_X[index] + 0.55, 1.0, COUNTER_Z + 0.32))
	_sign(_Strings.ANNEX_SIGNS["poster_nice"], Vector3(-8.97, 1.9, 2.6), 40, Color(0.36, 0.24, 0.55), 0.005, self, PI * 0.5)
	_sign(_Strings.ANNEX_SIGNS["poster_days"], Vector3(8.97, 1.95, 4.4), 30, Color(0.15, 0.3, 0.45), 0.005, self, -PI * 0.5)


## The glass doors in, the visitors' side door, both closed until the Annex opens them.
func _doors() -> void:
	var entrance: Node3D = _Props.slide_door("Entrance", ENTRANCE_WIDTH, true)
	add_child(entrance)
	entrance.position = Vector3(ENTRANCE_X, 0.0, Constants.ANNEX_SIZE.z * 0.5 + WALL * 0.5)
	var side: Node3D = _Props.slide_door("SideDoor", SIDE_DOOR_WIDTH - 0.1, false)
	add_child(side)
	side.position = Vector3(-Constants.ANNEX_SIZE.x * 0.5 - WALL * 0.5, 0.0, SIDE_DOOR_Z)
	side.rotation.y = PI * 0.5


## Where people stand: the curb the shuttle lets riders out at, the visitors'
## arrival outside the side door, the threshold, the forecourt, and the camera
## anchors (Cam*) a staged shot can use.
func _markers() -> void:
	var d := Constants.ANNEX_SIZE.z * 0.5
	_spot(self, "AnnexCurb", Vector3(ENTRANCE_X, 0.0, SIDEWALK_END - 0.7), PI)
	# A visitor comes in through the side door: they land inside, a few steps in,
	# facing the lobby (R2b: outside, they faced a shut door from the grass).
	_spot(self, "AnnexSide", Vector3(-Constants.ANNEX_SIZE.x * 0.5 + 2.2, 0.0, SIDE_DOOR_Z), -PI * 0.5)
	_spot(self, "Threshold", Vector3(ENTRANCE_X, 0.0, d - 0.9), 0.0)
	_spot(self, "Forecourt", Vector3(TURNSTILE_X, 0.0, d + 1.9), PI)
	_spot(self, "ForecourtCurb", Vector3(TURNSTILE_X, 0.0, SIDEWALK_END - 0.7), PI)
	_spot(self, "CamLobby", Vector3(-7.6, 2.7, 5.4))
	_spot(self, "CamDesk", Vector3(4.6, 2.4, 0.6))
	_spot(self, "CamTurnstile", Vector3(3.2, 2.2, 3.6))
	_spot(self, "CamCurb", Vector3(-1.2, 2.6, 15.5))


## The greeter's walk from the curb to just inside, and the janitor's mopping
## route from the back of the lobby to the doors.
func _paths() -> void:
	var d := Constants.ANNEX_SIZE.z * 0.5
	# R2b van: he used to walk out to the curb into the riders stepping down, then
	# stop a step in front of their faces inside. Now he waves from his post by the
	# doors and walks in ahead of them, to stand aside a few meters into the lobby.
	_path("GreeterPath", [Vector3(ENTRANCE_X + 1.6, 0.0, d - 2.0), Vector3(ENTRANCE_X + 2.0, 0.0, d - 3.0)])
	_path("JanitorPath", [Vector3(4.0, 0.0, -2.8), Vector3(-6.5, 0.0, -2.8), Vector3(-6.5, 0.0, -0.6), Vector3(4.0, 0.0, -0.6), Vector3(4.0, 0.0, 0.9), Vector3(-1.0, 0.0, 0.9), Vector3(ENTRANCE_X, 0.0, d - 1.0)])


## The staff: four clerks on their stools, the Head NICE BOY at his desk, the
## greeter by the doors, the janitor by the copier with his mop.
func _staff_bodies() -> void:
	var seats: Array[Dictionary] = []
	for index: int in WINDOWS.size():
		var window := get_node("Windows/%s" % WINDOWS[index]) as Node3D
		var seat := window.get_node("ClerkSeat") as Node3D
		seats.append({"name": "Clerk%s" % WINDOWS[index], "role": "clerk", "at": seat.global_position, "yaw": 0.0, "index": 2 + index})
	var desk := get_node("HeadDesk") as Node3D
	seats.append({"name": "HeadNiceBoy", "role": "head", "at": desk.to_global(Vector3(0.95, 0.0, 0.0)), "yaw": -PI * 0.5, "index": 1})
	seats.append({"name": "Greeter", "role": "greeter", "at": to_global(Vector3(ENTRANCE_X + 1.3, 0.0, Constants.ANNEX_SIZE.z * 0.5 - 1.4)), "yaw": 0.0, "index": 6})
	seats.append({"name": "Janitor", "role": "janitor", "at": to_global(Vector3(7.4, 0.0, 4.2)), "yaw": -PI * 0.75, "index": 7})
	for entry: Dictionary in seats:
		var clerk: Node3D = _Clerk.make(str(entry["name"]), str(entry["role"]), int(entry["index"]))
		_staff.add_child(clerk)
		clerk.global_position = entry["at"]
		clerk.rotation.y = float(entry["yaw"])
		clerk.call("set_home", clerk.position, clerk.rotation.y)
		clerk.set("annex_set", self)
		var start: StringName = &"counter_idle"
		match str(entry["role"]):
			"head":
				start = &"counter_idle"
			"greeter":
				start = &"idle"
			"janitor":
				start = &"idle"
		clerk.call("play", start, -1000.0)
	# Window D's clerk dozes behind his blinds. (A direct call: the audio test's
	# source scan reads call("play", "...") as a sound id.)
	var dozer: Variant = _staff.get_node("ClerkD")
	dozer.play(&"asleep", -1000.0)


# ---------------------------------------------------------------- helpers

func _spot(parent: Node3D, spot_name: String, at: Vector3, yaw: float = 0.0) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = spot_name
	parent.add_child(marker)
	marker.position = at
	marker.rotation.y = yaw
	return marker


func _path(path_name: String, points: Array) -> void:
	var path := Path3D.new()
	path.name = path_name
	var curve := Curve3D.new()
	for point: Vector3 in points:
		curve.add_point(point)
	path.curve = curve
	add_child(path)


## Painted words on a surface (a Label3D facing +Z turned by yaw), no outline.
func _sign(text: String, at: Vector3, font_size: int, color: Color, pixel: float, parent: Node3D = null, yaw: float = 0.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = color
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(parent if parent != null else self).add_child(label)
	label.position = at
	label.rotation.y = yaw
	return label

## Every static look in the set (props/office_props.gd marks them with meta
## key) merged into into's mesh, in the set's space, and the originals freed:
## the whole room's furniture is one draw call, its glass another.
func _bake(into: MeshInstance3D, key: String) -> void:
	var to_set := global_transform.affine_inverse()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var baked: Array[Node] = []
	var mine := into.mesh.surface_get_arrays(0)
	_append(mine, Transform3D.IDENTITY, vertices, normals, colors)
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var view := node as MeshInstance3D
		if not view.has_meta(key) or view.mesh == null or _staff.is_ancestor_of(view):
			continue
		_append(view.mesh.surface_get_arrays(0), to_set * view.global_transform, vertices, normals, colors)
		baked.append(view)
	for view: Node in baked:
		view.get_parent().remove_child(view)
		view.free()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	into.mesh = mesh
	into.transform = Transform3D.IDENTITY
	into.set_meta("baked", baked.size())


## One surface's triangles (indexed or not) moved by xform onto the lists.
func _append(arrays: Array, xform: Transform3D, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var source_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var order := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null and (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
		order = arrays[Mesh.ARRAY_INDEX]
	else:
		order.resize(source.size())
		for index: int in source.size():
			order[index] = index
	var turn := xform.basis.inverse().transposed()
	for index: int in order:
		vertices.append(xform * source[index])
		normals.append((turn * source_normals[index]).normalized() if index < source_normals.size() else Vector3.UP)
		colors.append(source_colors[index] if index < source_colors.size() else Color.WHITE)
