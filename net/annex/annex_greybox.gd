extends RefCounted

## Authority: local, cosmetic. A plain stand-in for Satellite Annex B's set, used
## only while the real one (levels/annex/annex_b.gd, R2 chunk 5) isn't in the
## build: net/annex/annex.gd builds this when World/BorderZone/AnnexSet is missing
## and annex_b.gd doesn't exist, and net/dev/annex_test.gd builds it for its
## checks. It has the same node names and set_state()/play() calls as the real set
## (gap-specs/nice_boys.json contracts C9 and C10), so the Annex drives either
## the same way: windows, lamps, blinds, stamps, bells, the Head NICE BOY's desk
## and big stamp, the co-signer sheet, the OUTGOING tray, the turnstile, light
## rows, the wall clock, and seven NICE BOY staff bodies (clerks A-D, the Head
## NICE BOY, the Greeter, the Janitor) that walk, turn and gesture per state.
##
## Layout, in BorderZone space (the room faces +Z, its street in front):
## interior x -9..9, z -5.5..7.5, the windows on the back wall at x -6, -2, 2, 6
## (A, B, C, D), the entrance at x -2 and the turnstile at x 5 on the front wall,
## the visitors' side door on the right wall at z 4.

const _LowPoly = preload("res://props/low_poly.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _CrewMember = preload("res://npcs/crew_member.gd")
const _NiceSeal = preload("res://props/nice_seal.gd")
const _Strings = preload("res://ui/strings.gd")
const _Icons = preload("res://ui/icons.gd")

const WALL := Color(0.80, 0.77, 0.90)
const TRIM := Color(0.52, 0.45, 0.70)
const FLOOR := Color(0.86, 0.84, 0.78)
const COUNTER := Color(0.62, 0.52, 0.42)
const METAL := Color(0.72, 0.74, 0.78)
const PAPER := Color(0.97, 0.96, 0.92)
const INK := Color(0.82, 0.12, 0.16)
const APPROVED_INK := Color(0.16, 0.55, 0.24)
const ASPHALT := Color(0.24, 0.24, 0.27)
const CONCRETE := Color(0.72, 0.71, 0.68)
const HEIGHT: float = 3.2
const WINDOW_X: Dictionary = {"A": -6.0, "B": -2.0, "C": 2.0, "D": 6.0}
const BACK_Z: float = -5.5
const FRONT_Z: float = 7.5
const ENTRANCE_X: float = -2.0
const TURNSTILE_X: float = 5.0
const SIDE_DOOR_Z: float = 4.0
## Staff walk speed (m/s) and turn rate (rad/s).
const STAFF_WALK: float = 1.7
const STAFF_TURN: float = 6.0
## How close staff let a person get before they step round them, in meters.
const STAFF_PERSONAL_SPACE: float = 1.1


## Builds the set under zone and returns it (named "AnnexSet").
static func build(zone: Node3D, set_seed: int) -> Node3D:
	var root := Node3D.new()
	root.name = "AnnexSet"
	root.set_meta("greybox", true)
	root.set_meta("seed", set_seed)
	zone.add_child(root)
	# The old desert course's dressing (border_dressing.gd, deleted by chunk 5) would
	# stand inside the room: keep it out of sight while this stand-in is up.
	var old := zone.get_node_or_null("Dressing") as Node3D
	if old != null:
		old.visible = false
	_shell(root)
	_street(root)
	_markers(root)
	var windows := Node3D.new()
	windows.name = "Windows"
	root.add_child(windows)
	for id: String in Constants.ANNEX_WINDOWS:
		_window(windows, id)
	_floor_lines(root)
	_head_desk(root)
	_appliances(root)
	_lobby(root)
	_lights(root)
	_staff(root)
	return root


## The three plaques dressed with this run's pictograms (C9's AnnexB.apply_run).
static func apply_run(set_root: Node3D, icons: Dictionary) -> void:
	for id: String in icons.keys():
		var plaque := set_root.get_node_or_null("Windows/%s/Plaque" % id) as Sprite3D
		if plaque != null and _Icons.has(str(icons[id])):
			plaque.texture = _Icons.texture(str(icons[id]))


static func window_color(window: String) -> Color:
	var index := Constants.ANNEX_WINDOWS.find(window)
	return Constants.ANNEX_WINDOW_COLORS[index] if index >= 0 else METAL


# ---------------------------------------------------------------- the room


static func _shell(root: Node3D) -> void:
	var shell := Node3D.new()
	shell.name = "Shell"
	root.add_child(shell)
	var mid_z := (BACK_Z + FRONT_Z) * 0.5
	var depth := FRONT_Z - BACK_Z
	_LowPoly.paint(_LowPoly.box(shell, Vector3(18.0, 0.02, depth), Vector3(0.0, 0.011, mid_z), FLOOR), "tile_floor", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
	# Walls: back, left, right (a gap for the side door), front (gaps for the entrance and the turnstile).
	_wall(shell, Vector3(18.6, HEIGHT, 0.3), Vector3(0.0, HEIGHT * 0.5, BACK_Z - 0.15))
	_wall(shell, Vector3(0.3, HEIGHT, depth), Vector3(-9.15, HEIGHT * 0.5, mid_z))
	var door_lo := SIDE_DOOR_Z - 1.0
	var door_hi := SIDE_DOOR_Z + 1.0
	_wall(shell, Vector3(0.3, HEIGHT, door_lo - BACK_Z), Vector3(9.15, HEIGHT * 0.5, (BACK_Z + door_lo) * 0.5))
	_wall(shell, Vector3(0.3, HEIGHT, FRONT_Z - door_hi), Vector3(9.15, HEIGHT * 0.5, (door_hi + FRONT_Z) * 0.5))
	_wall(shell, Vector3(0.3, HEIGHT - 2.3, 2.0), Vector3(9.15, 2.3 + (HEIGHT - 2.3) * 0.5, SIDE_DOOR_Z))
	var spans: Array = [[-9.3, ENTRANCE_X - 1.0], [ENTRANCE_X + 1.0, TURNSTILE_X - 0.6], [TURNSTILE_X + 0.6, 9.3]]
	for span: Array in spans:
		var a := float(span[0])
		var b := float(span[1])
		_wall(shell, Vector3(b - a, HEIGHT, 0.3), Vector3((a + b) * 0.5, HEIGHT * 0.5, FRONT_Z + 0.15))
	# Lintels over the entrance and the turnstile.
	_wall(shell, Vector3(2.0, HEIGHT - 2.4, 0.3), Vector3(ENTRANCE_X, 2.4 + (HEIGHT - 2.4) * 0.5, FRONT_Z + 0.15))
	_wall(shell, Vector3(1.2, HEIGHT - 2.2, 0.3), Vector3(TURNSTILE_X, 2.2 + (HEIGHT - 2.2) * 0.5, FRONT_Z + 0.15))
	# Trim along the top, outside and in.
	_LowPoly.paint(_LowPoly.box(shell, Vector3(18.8, 0.18, 0.4), Vector3(0.0, HEIGHT + 0.09, FRONT_Z + 0.15), TRIM), "concrete")
	# The facade's sign and the Daisy Seal over the door.
	var sign := _LowPoly.text_sign(shell, _Strings.ANNEX_UI["annex_sign"], Vector3(0.0, HEIGHT - 0.35, FRONT_Z + 0.32), 64, Color(0.36, 0.24, 0.55))
	sign.name = "FacadeSign"
	var seal := _NiceSeal.node(0.45, Vector3.BACK)
	seal.position = Vector3(ENTRANCE_X, 2.85, FRONT_Z + 0.33)
	shell.add_child(seal)
	# Glass doors at the entrance (the Entrance part swings them).
	var entrance := Part.new()
	entrance.name = "Entrance"
	entrance.kind = "door"
	root.add_child(entrance)
	entrance.position = Vector3(ENTRANCE_X, 0.0, FRONT_Z + 0.15)
	var blocker := _LowPoly.box(entrance, Vector3(2.0, 2.4, 0.12), Vector3(0.0, 1.2, 0.0), Color(0.55, 0.7, 0.82), true)
	blocker.name = "Blocker"
	for side: float in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.name = "Leaf%d" % (0 if side < 0.0 else 1)
		entrance.add_child(leaf)
		leaf.position = Vector3(side * 1.0, 0.0, 0.0)
		var glass := _LowPoly.box(leaf, Vector3(0.96, 2.3, 0.05), Vector3(-side * 0.5, 1.17, 0.0), Color(0.55, 0.7, 0.82)) as MeshInstance3D
		glass.material_override = _clear_glass()
		glass.set_meta("keep_material", true)
		_LowPoly.box(leaf, Vector3(0.06, 2.3, 0.07), Vector3(-side * 0.97, 1.17, 0.0), METAL)
	(blocker.get_child(1) as Node3D).visible = false
	# The visitors' side door, always shut until a visitor leaves through it.
	var side_door := Part.new()
	side_door.name = "SideDoor"
	side_door.kind = "door"
	root.add_child(side_door)
	side_door.position = Vector3(9.15, 0.0, SIDE_DOOR_Z)
	side_door.rotation.y = PI * 0.5
	var side_block := _LowPoly.box(side_door, Vector3(2.0, 2.3, 0.1), Vector3(0.0, 1.15, 0.0), Color(0.62, 0.55, 0.78), true)
	side_block.name = "Blocker"
	(side_block.get_child(1) as Node3D).visible = false
	for side: float in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.name = "Leaf%d" % (0 if side < 0.0 else 1)
		side_door.add_child(leaf)
		leaf.position = Vector3(side * 1.0, 0.0, 0.0)
		_LowPoly.paint(_LowPoly.box(leaf, Vector3(0.96, 2.25, 0.06), Vector3(-side * 0.5, 1.13, 0.0), Color(0.62, 0.55, 0.78)), "planks")


## Counter glass you can see the clerk through (the street windows' glass is a mirror).
static func _clear_glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.7, 0.8, 0.07)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 0.8
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return glass


static func _wall(parent: Node3D, size: Vector3, at: Vector3) -> void:
	_LowPoly.paint(_LowPoly.box(parent, size, at, WALL, true), "stucco", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)


## The sidewalk, the curb and a stretch of street in front, where the shuttle pulls up.
static func _street(root: Node3D) -> void:
	var street := Node3D.new()
	street.name = "Street"
	root.add_child(street)
	_LowPoly.paint(_LowPoly.box(street, Vector3(30.0, 0.04, 4.6), Vector3(0.0, 0.02, FRONT_Z + 2.6), CONCRETE), "concrete")
	_LowPoly.paint(_LowPoly.box(street, Vector3(30.0, 0.03, 7.0), Vector3(0.0, 0.015, FRONT_Z + 8.4), ASPHALT), "asphalt")
	_LowPoly.box(street, Vector3(30.0, 0.16, 0.25), Vector3(0.0, 0.08, FRONT_Z + 4.9), CONCRETE.lightened(0.1))
	# The forecourt behind the turnstile: a short fenced pen of daylight to the curb.
	for side: float in [-1.0, 1.0]:
		_LowPoly.paint(_LowPoly.box(street, Vector3(0.08, 0.9, 4.4), Vector3(TURNSTILE_X + side * 1.3, 0.45, FRONT_Z + 2.4), METAL, true), "metal")


static func _markers(root: Node3D) -> void:
	_marker(root, "AnnexCurb", Vector3(ENTRANCE_X, 0.1, FRONT_Z + 6.2), 0.0)
	_marker(root, "AnnexSide", Vector3(7.9, 0.1, SIDE_DOOR_Z), PI * 0.5)
	_marker(root, "Threshold", Vector3(ENTRANCE_X, 0.1, FRONT_Z - 1.0), 0.0)
	_marker(root, "Forecourt", Vector3(TURNSTILE_X, 0.1, FRONT_Z + 2.0), PI)
	_marker(root, "ForecourtCurb", Vector3(TURNSTILE_X, 0.1, FRONT_Z + 6.2), PI)
	var greeter := Path3D.new()
	greeter.name = "GreeterPath"
	greeter.curve = Curve3D.new()
	# He waits just outside the doors, waves the van's riders over and leads them in.
	greeter.curve.add_point(Vector3(ENTRANCE_X + 0.7, 0.0, FRONT_Z + 1.4))
	greeter.curve.add_point(Vector3(ENTRANCE_X + 0.6, 0.0, FRONT_Z - 0.4))
	greeter.curve.add_point(Vector3(ENTRANCE_X + 1.3, 0.0, FRONT_Z - 1.6))
	root.add_child(greeter)
	var janitor := Path3D.new()
	janitor.name = "JanitorPath"
	janitor.curve = Curve3D.new()
	janitor.curve.add_point(Vector3(7.5, 0.0, BACK_Z + 2.4))
	janitor.curve.add_point(Vector3(0.0, 0.0, 1.0))
	janitor.curve.add_point(Vector3(ENTRANCE_X + 1.2, 0.0, FRONT_Z - 1.4))
	root.add_child(janitor)


static func _marker(parent: Node3D, marker_name: String, at: Vector3, yaw: float) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	parent.add_child(marker)
	marker.position = at
	marker.rotation.y = yaw
	return marker


## One service window: the counter, the glass with its hatch, the booth walls,
## the lamp, the blind, the bell and the stamp, the plaque, and its markers. The
## window's +Z faces the room.
static func _window(parent: Node3D, id: String) -> void:
	var window := Part.new()
	window.name = id
	window.kind = "window"
	parent.add_child(window)
	window.position = Vector3(float(WINDOW_X[id]), 0.0, BACK_Z)
	var color := window_color(id)
	_LowPoly.paint(_LowPoly.box(window, Vector3(2.6, 1.1, 0.5), Vector3(0.0, 0.55, 1.25), COUNTER, true), "planks", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
	_LowPoly.box(window, Vector3(2.7, 0.06, 0.6), Vector3(0.0, 1.13, 1.25), color.lightened(0.35))
	# Glass above the hatch (a gap at counter height to pass the form through).
	var glass := _LowPoly.box(window, Vector3(2.6, HEIGHT - 1.48, 0.06), Vector3(0.0, 1.48 + (HEIGHT - 1.48) * 0.5, 1.25), Color(0.55, 0.7, 0.82), true)
	var glass_mesh := glass.get_child(1) as MeshInstance3D
	glass_mesh.material_override = _clear_glass()
	glass_mesh.set_meta("keep_material", true)
	# Booth walls between windows and a low swing gate either side of the counter.
	for side: float in [-1.0, 1.0]:
		_LowPoly.paint(_LowPoly.box(window, Vector3(0.12, HEIGHT, 1.5), Vector3(side * 1.95, HEIGHT * 0.5, 0.75), WALL, true), "stucco", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
		# The right gate is shut; the left one swings for him (people still can't
		# get round: an invisible bar at the gate holds them, clerks aren't solid).
		_LowPoly.paint(_LowPoly.box(window, Vector3(0.62, 1.1, 0.06), Vector3(side * 1.62, 0.55, 1.25), COUNTER.darkened(0.15), side > 0.0), "planks")
		if side < 0.0:
			var bar := StaticBody3D.new()
			bar.collision_layer = Constants.PAD_WALL_LAYER
			bar.collision_mask = 0
			window.add_child(bar)
			bar.position = Vector3(-1.62, 1.0, 1.25)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.62, 2.0, 0.1)
			shape.shape = box
			bar.add_child(shape)
	# The window's color band and pictogram over the glass.
	_LowPoly.glow(window, Vector3(2.6, 0.14, 0.04), Vector3(0.0, HEIGHT - 0.12, 1.29), color, 0.6)
	var plaque := Sprite3D.new()
	plaque.name = "Plaque"
	plaque.pixel_size = 0.0022
	plaque.position = Vector3(-0.8, HEIGHT - 0.45, 1.3)
	window.add_child(plaque)
	var letter := _LowPoly.text_sign(window, id, Vector3(0.7, HEIGHT - 0.45, 1.3), 96, color.darkened(0.35))
	letter.name = "Letter"
	# The lamp: lit while he's serving.
	var lamp := _LowPoly.glow(window, Vector3(0.26, 0.26, 0.12), Vector3(0.0, HEIGHT - 0.45, 1.32), Color(1.0, 0.86, 0.35), 2.4)
	lamp.name = "Lamp"
	# The blind behind the glass; up it sits rolled under the band.
	var blind := _LowPoly.box(window, Vector3(2.5, 1.7, 0.03), Vector3(0.0, 2.33, 1.2), Color(0.9, 0.88, 0.8))
	blind.name = "Blind"
	# The bell and the stamp on the counter, the back-in-5 sign between them.
	var bell := _LowPoly.box(window, Vector3(0.16, 0.06, 0.16), Vector3(-0.9, 1.19, 1.3), METAL)
	bell.name = "BellLook"
	_LowPoly.ball(bell, 0.07, Vector3(0.0, 0.05, 0.0), Color(0.92, 0.8, 0.38))
	var stamp := Node3D.new()
	stamp.name = "StampLook"
	window.add_child(stamp)
	stamp.position = Vector3(0.9, 1.16, 1.25)
	_LowPoly.box(stamp, Vector3(0.22, 0.02, 0.16), Vector3.ZERO, Color(0.3, 0.12, 0.14))
	var handle := Node3D.new()
	handle.name = "Handle"
	stamp.add_child(handle)
	_LowPoly.cylinder(handle, 0.045, 0.1, Vector3(0.0, 0.07, 0.0), Color(0.15, 0.15, 0.17))
	_LowPoly.ball(handle, 0.05, Vector3(0.0, 0.15, 0.0), color)
	var clock_sign := _LowPoly.text_sign(window, _Strings.ANNEX_UI["back_soon"], Vector3(0.0, 1.3, 1.53), 22, Color(0.2, 0.2, 0.24))
	clock_sign.name = "ClockSign"
	clock_sign.visible = false
	var zzz := Label3D.new()
	zzz.name = "Zzz"
	zzz.text = _Strings.ANNEX_UI["snore"]
	zzz.font_size = 40
	zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	zzz.modulate = Color(0.9, 0.9, 1.0)
	zzz.position = Vector3(0.0, 2.2, 0.5)
	zzz.visible = false
	window.add_child(zzz)
	# The filing cabinet behind him.
	_LowPoly.paint(_LowPoly.box(window, Vector3(0.5, 1.3, 0.45), Vector3(1.3, 0.65, 0.25), METAL, true), "metal")
	# Markers (C9): where you stand to be served, the queue, the stamp and bell
	# spots, his seat, the cabinet, his three break spots (coffee, cooler, copier).
	_marker(window, "Counter", Vector3(0.0, 0.0, 2.05), 0.0)
	var queue := Node3D.new()
	queue.name = "QueueSpots"
	window.add_child(queue)
	for index: int in 3:
		_marker(queue, "Q%d" % index, Vector3(0.0, 0.0, 2.75 + float(index) * 0.7), 0.0)
	_marker(window, "StampPad", Vector3(0.95, 0.0, 1.9), 0.0)
	_marker(window, "Bell", Vector3(-0.95, 0.0, 1.9), 0.0)
	_marker(window, "ClerkSeat", Vector3(0.0, 0.0, 0.55), 0.0)
	_marker(window, "Cabinet", Vector3(0.9, 0.0, 0.3), PI * 0.5)
	# His way out of the booth: the swing gate left of the counter (bell side).
	_marker(window, "GateIn", Vector3(-1.62, 0.0, 0.55), 0.0)
	_marker(window, "GateOut", Vector3(-1.62, 0.0, 2.3), 0.0)
	# ...and round behind whoever is standing at the counters and in the queues.
	_marker(window, "Aisle", Vector3(-1.9, 0.0, 5.4), 0.0)
	var origin := window.position
	var spots := [Vector3(7.6, 0.0, 0.8), Vector3(7.6, 0.0, -2.0), Vector3(-7.6, 0.0, 0.5)]
	for index: int in spots.size():
		_marker(window, "BreakSpot%d" % index, (spots[index] as Vector3) - origin, 0.0)
	# Footprints on the floor at the counter spot and the queue.
	for index: int in 4:
		_LowPoly.box(window, Vector3(0.5, 0.01, 0.28), Vector3(0.0, 0.025, 2.05 + float(index) * 0.7), color.lightened(0.2) if index == 0 else FLOOR.darkened(0.12))
	window.refresh()


## A colored line on the floor from the chairs to each serving window's counter.
static func _floor_lines(root: Node3D) -> void:
	var lines := Node3D.new()
	lines.name = "FloorLines"
	root.add_child(lines)
	for id: String in Constants.ANNEX_SERVING_WINDOWS:
		var line := Part.new()
		line.name = id
		line.kind = "line"
		lines.add_child(line)
		var x := float(WINDOW_X[id])
		var start := Vector3(x * 0.35, 0.0, 3.6)
		var finish := Vector3(x, 0.0, BACK_Z + 2.9)
		var length := start.distance_to(finish)
		line.position = (start + finish) * 0.5
		line.rotation.y = atan2(finish.x - start.x, finish.z - start.z)
		var strip := _LowPoly.glow(line, Vector3(0.18, 0.012, length), Vector3(0.0, 0.03, 0.0), window_color(id), 0.15)
		strip.name = "Strip"


static func _head_desk(root: Node3D) -> void:
	var desk := Part.new()
	desk.name = "HeadDesk"
	desk.kind = "desk"
	root.add_child(desk)
	desk.position = Vector3(-7.3, 0.0, 4.0)
	# He sits at -X facing +X across the desk.
	_LowPoly.paint(_LowPoly.box(desk, Vector3(0.9, 0.78, 1.9), Vector3(0.0, 0.39, 0.0), COUNTER.darkened(0.2), true), "planks", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
	_marker(desk, "DeskSpot", Vector3(1.35, 0.0, 0.0), -PI * 0.5)
	var pad := _marker(desk, "Pad", Vector3(0.1, 0.8, 0.55), 0.0)
	_LowPoly.box(pad, Vector3(0.36, 0.02, 0.3), Vector3.ZERO, Color(0.42, 0.2, 0.55))
	var nameplate := _LowPoly.text_sign(desk, _Strings.ANNEX_UI["approved"], Vector3(0.46, 0.62, 0.0), 18, Color(0.2, 0.2, 0.24), PI * 0.5)
	nameplate.name = "Nameplate"
	var stamp := BigStamp.new()
	stamp.name = "BigStamp"
	desk.add_child(stamp)
	stamp.position = pad.position
	stamp.home = pad


static func _appliances(root: Node3D) -> void:
	var pieces := [["Copier", Vector3(-8.45, 0.0, 0.5), Vector3(0.9, 1.1, 1.0), METAL], ["Cooler", Vector3(8.5, 0.0, -2.0), Vector3(0.5, 1.3, 0.5), Color(0.55, 0.75, 0.95)], ["CoffeeMachine", Vector3(8.5, 0.0, 0.8), Vector3(0.55, 1.4, 0.6), Color(0.25, 0.22, 0.22)]]
	for piece: Array in pieces:
		var part := Part.new()
		part.name = str(piece[0])
		part.kind = "appliance"
		root.add_child(part)
		part.position = piece[1]
		var size: Vector3 = piece[2]
		_LowPoly.paint(_LowPoly.box(part, size, Vector3(0.0, size.y * 0.5, 0.0), piece[3], true), "metal")
		var inward := 1.0 if (piece[1] as Vector3).x < 0.0 else -1.0
		_marker(part, "Spot", Vector3(inward * 0.85, 0.0, 0.0), -inward * PI * 0.5)
		var light := _LowPoly.glow(part, Vector3(0.08, 0.08, 0.08), Vector3(inward * size.x * 0.5, size.y - 0.15, 0.2), Color(0.3, 1.0, 0.4), 1.5)
		light.name = "Light"
	# The copier's jam light is red.
	var jam := root.get_node("Copier/Light") as MeshInstance3D
	(jam.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.25, 0.2)
	(jam.material_override as StandardMaterial3D).emission = Color(1.0, 0.25, 0.2)


## Chairs, the ticket dispenser, the co-signer sheet, the OUTGOING tray and the turnstile.
static func _lobby(root: Node3D) -> void:
	var lobby := Node3D.new()
	lobby.name = "Lobby"
	root.add_child(lobby)
	for row: int in 2:
		var z := 3.6 + float(row) * 1.3
		_LowPoly.paint(_LowPoly.box(lobby, Vector3(4.6, 0.45, 0.5), Vector3(-0.6, 0.225, z), Color(0.45, 0.55, 0.7), true), "fabric")
		_LowPoly.box(lobby, Vector3(4.6, 0.5, 0.08), Vector3(-0.6, 0.7, z + 0.24), Color(0.45, 0.55, 0.7))
	_LowPoly.paint(_LowPoly.box(lobby, Vector3(0.4, 1.2, 0.4), Vector3(-3.6, 0.6, FRONT_Z - 0.9), Color(0.85, 0.2, 0.2), true), "metal")
	var dispenser := Node3D.new()
	dispenser.name = "Dispenser"
	root.add_child(dispenser)
	dispenser.position = Vector3(-3.6, 0.0, FRONT_Z - 0.9)
	var stickies := Node3D.new()
	stickies.name = "Stickies"
	root.add_child(stickies)
	stickies.position = Vector3(0.0, 1.2, BACK_Z + 0.05)
	# The co-signer sheet: a clipboard on a chain on a lectern by the side door.
	var sheet := Part.new()
	sheet.name = "CoSignSheet"
	sheet.kind = "sheet"
	root.add_child(sheet)
	sheet.position = Vector3(6.5, 0.0, 5.7)
	_LowPoly.paint(_LowPoly.box(sheet, Vector3(0.5, 1.05, 0.4), Vector3(0.0, 0.525, 0.0), COUNTER, true), "planks")
	var board := _LowPoly.box(sheet, Vector3(0.3, 0.02, 0.4), Vector3(0.0, 1.08, 0.0), Color(0.55, 0.36, 0.2))
	board.name = "Board"
	_LowPoly.box(board, Vector3(0.26, 0.012, 0.34), Vector3(0.0, 0.012, 0.0), PAPER)
	# The tray, on a little table left of the turnstile.
	var tray := Marker3D.new()
	tray.name = "OutgoingTray"
	root.add_child(tray)
	tray.position = Vector3(TURNSTILE_X - 1.25, 0.0, FRONT_Z - 0.55)
	_LowPoly.paint(_LowPoly.box(tray, Vector3(0.7, 0.85, 0.5), Vector3(0.0, 0.425, 0.0), COUNTER, true), "planks")
	_LowPoly.box(tray, Vector3(0.42, 0.06, 0.32), Vector3(0.0, 0.88, 0.0), Color(0.3, 0.3, 0.33))
	_LowPoly.text_sign(tray, _Strings.ANNEX_UI["outgoing"], Vector3(0.0, 0.62, -0.26), 22, Color(0.2, 0.2, 0.24), PI)
	# The turnstile: a post and three arms, and a bar to the lintel so nobody hops it.
	var turnstile := Part.new()
	turnstile.name = "Turnstile"
	turnstile.kind = "turnstile"
	root.add_child(turnstile)
	turnstile.position = Vector3(TURNSTILE_X, 0.0, FRONT_Z + 0.15)
	_LowPoly.paint(_LowPoly.cylinder(turnstile, 0.08, 1.0, Vector3(-0.5, 0.5, 0.0), METAL), "metal")
	var arms := Node3D.new()
	arms.name = "Arms"
	turnstile.add_child(arms)
	arms.position = Vector3(-0.5, 0.9, 0.0)
	for index: int in 3:
		var arm := Node3D.new()
		arms.add_child(arm)
		arm.rotation.y = TAU * float(index) / 3.0
		_LowPoly.paint(_LowPoly.cylinder(arm, 0.03, 0.9, Vector3(0.45, 0.0, 0.0), METAL), "metal").rotation.z = PI * 0.5
	var bar := _LowPoly.box(turnstile, Vector3(1.2, 2.2, 0.3), Vector3(0.0, 1.1, 0.0), METAL, true)
	bar.name = "Blocker"
	(bar.get_child(1) as Node3D).visible = false


## LightRows/Row0..3, back of the room first (Row0 by the windows).
static func _lights(root: Node3D) -> void:
	var rows := Node3D.new()
	rows.name = "LightRows"
	root.add_child(rows)
	for index: int in 4:
		var row := Part.new()
		row.name = "Row%d" % index
		row.kind = "light_row"
		rows.add_child(row)
		row.position = Vector3(0.0, HEIGHT - 0.05, BACK_Z + 1.6 + float(index) * 3.1)
		var panel := _LowPoly.glow(row, Vector3(14.0, 0.05, 0.4), Vector3.ZERO, Color(1.0, 0.97, 0.88), 1.2)
		panel.name = "Panel"
		var light := OmniLight3D.new()
		light.name = "Light"
		light.omni_range = 7.0
		light.light_energy = 0.7
		light.position = Vector3(0.0, -0.3, 0.0)
		row.add_child(light)
		row.refresh()
	var clock := Part.new()
	clock.name = "WallClock"
	clock.kind = "clock"
	root.add_child(clock)
	clock.position = Vector3(-8.98, 2.35, -1.6)
	clock.rotation.y = PI * 0.5
	_LowPoly.cylinder(clock, 0.32, 0.04, Vector3.ZERO, PAPER).rotation.x = PI * 0.5
	var hand := Node3D.new()
	hand.name = "Hand"
	clock.add_child(hand)
	hand.position = Vector3(0.0, 0.0, 0.03)
	_LowPoly.box(hand, Vector3(0.025, 0.26, 0.01), Vector3(0.0, 0.11, 0.0), Color(0.1, 0.1, 0.12))
	var serving := Part.new()
	serving.name = "NowServing"
	serving.kind = "board"
	root.add_child(serving)
	serving.position = Vector3(-8.98, 2.6, 1.4)
	serving.rotation.y = PI * 0.5
	_LowPoly.box(serving, Vector3(1.0, 0.36, 0.04), Vector3.ZERO, Color(0.1, 0.1, 0.12))
	var digits := _LowPoly.text_sign(serving, "00", Vector3(0.0, 0.0, 0.03), 64, Color(1.0, 0.35, 0.2))
	digits.name = "Digits"


## Seven local NICE BOY bodies (C10's names), each at its home spot.
static func _staff(root: Node3D) -> void:
	var staff := Node3D.new()
	staff.name = "Staff"
	root.add_child(staff)
	var index := 2
	# Bodies face -Z: a yaw of PI faces the room (+Z), -PI/2 faces +X.
	for id: String in Constants.ANNEX_WINDOWS:
		var seat := root.get_node("Windows/%s/ClerkSeat" % id) as Node3D
		_add_staff(staff, "Clerk%s" % id, index, seat.global_position, PI)
		index += 1
	_add_staff(staff, "HeadNiceBoy", 1, root.to_global(Vector3(-8.1, 0.0, 4.0)), -PI * 0.5)
	_add_staff(staff, "Greeter", 7, root.to_global(Vector3(ENTRANCE_X + 0.7, 0.0, FRONT_Z + 1.4)), PI)
	_add_staff(staff, "Janitor", 8, root.to_global(Vector3(8.0, 0.0, BACK_Z + 2.0)), PI)


## home is in world space (the set is in the tree while it's built).
static func _add_staff(parent: Node3D, staff_name: String, look: int, home: Vector3, yaw: float) -> void:
	var member := Staff.new()
	member.name = staff_name
	parent.add_child(member)
	member.global_position = home
	member.home = home
	member.home_yaw = yaw
	member.target = home
	member.target_yaw = yaw
	member.rotation.y = yaw
	var body := _CartoonBody.new()
	body.name = "CartoonBody"
	_CrewMember.dress(body, look)
	member.add_child(body)
	body.build()
	member.body = body


# ---------------------------------------------------------------- moving parts


## One set piece with cosmetic states (C9's set_state), timed from server time.
class Part extends Node3D:
	var kind: String = ""
	var state: StringName = &""
	var since: float = 0.0
	var speed_scale: float = 1.0
	var number: int = 0
	var _angle: float = 0.0
	## A window keeps its lamp, blind and stamp apart: one call changes one of them.
	var blind_down: bool = false
	var stamp_up: bool = false
	var stamp_since: float = 0.0

	func set_state(new_state: StringName, at: float, _args: Dictionary = {}) -> void:
		if kind == "window":
			match new_state:
				&"blind_up", &"blind_down":
					blind_down = new_state == &"blind_down"
					return
				&"stamp_lifted", &"stamp_down":
					stamp_up = new_state == &"stamp_lifted"
					stamp_since = at
					return
		state = new_state
		since = at
		refresh()

	func set_speed(scale: float) -> void:
		speed_scale = scale

	func show_number(value: int) -> void:
		number = value
		var digits := get_node_or_null("Digits") as Label3D
		if digits != null:
			digits.text = "%02d" % (value % 100)

	func refresh() -> void:
		match kind:
			"window":
				var lamp := get_node_or_null("Lamp") as Node3D
				if lamp != null and (state == &"lamp_on" or state == &"lamp_off"):
					lamp.visible = state == &"lamp_on"
				var sign := get_node_or_null("ClockSign") as Node3D
				if sign != null and (state == &"clock_sign" or state == &"lamp_on"):
					sign.visible = state == &"clock_sign"
			"door":
				var blocker := get_node_or_null("Blocker") as StaticBody3D
				if blocker != null:
					var shape := blocker.get_child(0) as CollisionShape3D
					shape.disabled = state == &"open"
			"turnstile":
				pass
			"light_row":
				var light := get_node_or_null("Light") as OmniLight3D
				var panel := get_node_or_null("Panel") as Node3D
				var on := state != &"off"
				if light != null:
					light.visible = on
				if panel != null:
					panel.visible = on

	func _process(delta: float) -> void:
		var age := Net.server_time() - since
		match kind:
			"window":
				_step_window(age, delta)
			"door":
				var open := state == &"open"
				for leaf_name: String in ["Leaf0", "Leaf1"]:
					var leaf := get_node_or_null(leaf_name) as Node3D
					if leaf == null:
						continue
					var side := -1.0 if leaf_name == "Leaf0" else 1.0
					leaf.rotation.y = lerp_angle(leaf.rotation.y, side * (1.35 if open else 0.0), clampf(delta * 6.0, 0.0, 1.0))
			"turnstile":
				var arms := get_node_or_null("Arms") as Node3D
				if arms == null:
					return
				if state == &"open" and age < Constants.ANNEX_TURNSTILE_OPEN:
					arms.rotation.y = TAU / 3.0 * clampf(age / Constants.ANNEX_TURNSTILE_OPEN, 0.0, 1.0)
				elif state == &"bounce" and age < 0.4:
					arms.rotation.y = sin(age / 0.4 * PI) * 0.12
				else:
					arms.rotation.y = 0.0
			"line":
				var strip := get_node_or_null("Strip") as MeshInstance3D
				if strip != null:
					var pulse := 0.0
					if state == &"pulse" and age < 1.6:
						pulse = absf(sin(age * PI * 2.5)) * (1.0 - age / 1.6)
					(strip.material_override as StandardMaterial3D).emission_energy_multiplier = 0.15 + pulse * 3.0
			"light_row":
				if state == &"flicker":
					var light := get_node_or_null("Light") as OmniLight3D
					var flick := fmod(age * 7.3 + float(get_index()) * 0.37, 1.0) > 0.86
					if light != null:
						light.visible = not flick
					var panel := get_node_or_null("Panel") as Node3D
					if panel != null:
						panel.visible = not flick
			"clock":
				_angle += delta * TAU / 60.0 * speed_scale
				var hand := get_node_or_null("Hand") as Node3D
				if hand != null:
					hand.rotation.z = -_angle
			"sheet":
				var board := get_node_or_null("Board") as Node3D
				if board != null:
					board.rotation.x = sin(age * 18.0) * 0.06 if state == &"signing" and age < Constants.ANNEX_COSIGN_HOLD else 0.0
			"appliance":
				var light := get_node_or_null("Light") as Node3D
				if light != null and state == &"jam":
					light.visible = fmod(age, 0.6) < 0.3

	func _step_window(_age: float, delta: float) -> void:
		var blind := get_node_or_null("Blind") as Node3D
		if blind != null:
			var want := 1.0 if blind_down else 0.06
			blind.scale.y = lerpf(blind.scale.y, want, clampf(delta * 9.0, 0.0, 1.0))
			blind.position.y = 3.18 - 0.85 * blind.scale.y
		var handle := get_node_or_null("StampLook/Handle") as Node3D
		if handle != null:
			# Up while held; slammed down fast (the contact frame), then still.
			var lift := 0.16 if stamp_up else 0.0
			var rate := 10.0 if stamp_up else 40.0
			handle.position.y = lerpf(handle.position.y, lift, clampf(delta * rate, 0.0, 1.0))
		var zzz := get_node_or_null("Zzz") as Node3D
		if zzz != null and zzz.visible:
			zzz.position.y = 2.2 + fmod(Time.get_ticks_msec() / 1000.0, 2.0) * 0.15


## The Head NICE BOY's big stamp: on its pad, held by a player (it rides in front
## of them, two-handed), or slamming down.
class BigStamp extends Node3D:
	var home: Node3D
	var holder: Node3D
	var state: StringName = &"on_pad"
	var since: float = 0.0
	var _head: Node3D

	func _ready() -> void:
		var handle := _LowPoly.cylinder(self, 0.05, 0.22, Vector3(0.0, 0.2, 0.0), Color(0.36, 0.2, 0.12))
		handle.name = "Handle"
		_LowPoly.ball(self, 0.08, Vector3(0.0, 0.33, 0.0), Color(0.88, 0.7, 0.28))
		_head = _LowPoly.box(self, Vector3(0.3, 0.09, 0.22), Vector3(0.0, 0.05, 0.0), Color(0.16, 0.55, 0.24))

	func set_held(player: Node3D) -> void:
		holder = player

	func set_state(new_state: StringName, at: float, _args: Dictionary = {}) -> void:
		state = new_state
		since = at

	func _process(_delta: float) -> void:
		var age := Net.server_time() - since
		if holder != null and is_instance_valid(holder):
			var forward := -holder.global_basis.z
			var right := holder.global_basis.x
			# Two-handed at the belly, a little right: in view, not in the way.
			global_position = holder.global_position + Vector3(0.0, 0.82, 0.0) + forward * 0.5 + right * 0.16
			global_rotation = Vector3(0.0, holder.global_rotation.y, 0.0)
			if state == &"slam" and age < 0.5:
				global_position.y += (0.35 - absf(age - 0.15) * 1.2) if age < 0.3 else 0.0
			return
		if home != null:
			global_transform = home.global_transform
			if state == &"slam" and age < 0.9:
				var lift := Constants.ANNEX_HEAD_WINDUP
				var y := 0.0
				if age < lift:
					y = 0.45 * clampf(age / 0.25, 0.0, 1.0)
				elif age < lift + 0.08:
					y = 0.45 * (1.0 - (age - lift) / 0.08)
				global_position.y += y


## A cosmetic NICE BOY behind the counters (C10's play(state, at, args)): walks
## to where the state wants him (world space), turns, and gestures. Nothing reads
## him back: the host judges from the schedule, so his drift can't change outcomes.
class Staff extends Node3D:
	var body: Node3D
	var home: Vector3
	var home_yaw: float = 0.0
	var target: Vector3
	var target_yaw: float = 0.0
	var state: StringName = &"counter_idle"
	var since: float = 0.0
	var args: Dictionary = {}
	var hurry: float = 1.0
	var _path: Array = []

	## Bodies face -Z: the yaw that faces a direction.
	static func yaw_toward(direction: Vector3) -> float:
		return atan2(-direction.x, -direction.z)

	func play(new_state: StringName, at: float, new_args: Dictionary = {}) -> void:
		state = new_state
		since = at
		args = new_args
		hurry = 1.0
		_path = []
		target = home
		target_yaw = home_yaw
		var to: Variant = new_args.get("to", null)
		match new_state:
			&"wave_up":
				_gesture("wave")
			&"take_form", &"hand_back", &"lunch_bite", &"take_stamp_back", &"greeter_offer", &"greeter_punch_card":
				_gesture("offer")
			&"stamp", &"head_windup_slam":
				_gesture("punch")
			&"peer_form", &"head_shake_point", &"notice":
				_gesture("point")
			&"phone":
				target_yaw = home_yaw + 1.3
				_gesture("watch")
			&"telegraph_stretch":
				_gesture("stretch")
			&"walk_to", &"on_break":
				if to is Vector3:
					target = to
			&"hurry_back":
				hurry = 1.6
			&"wake", &"gasp_whistle":
				_gesture("startle")
			&"lunch_turned":
				target_yaw = home_yaw + PI * 0.85
			&"lean_toward":
				var dir: Vector3 = new_args.get("dir", Vector3.RIGHT)
				target = home + Vector3(dir.x, 0.0, dir.z).normalized() * 0.45
				target_yaw = yaw_toward(dir)
			&"turn_to_cabinet":
				target_yaw = home_yaw + PI * 0.65
				_gesture("look_around")
			&"twitch_turn_back":
				target_yaw = home_yaw + PI * 0.4
				_gesture("startle")
			&"add_carbon":
				_gesture("scribble")
			&"volley", &"closing_rush":
				_gesture("windmill")
			&"walk_hand_out":
				if to is Vector3:
					target = to
				hurry = 1.5
				_gesture("offer")
			&"greeter_lead", &"janitor_mop":
				if new_args.get("path", null) is Array:
					_path = (new_args["path"] as Array).duplicate()
				hurry = 0.55 if new_state == &"janitor_mop" else 1.0
				_gesture("wave" if new_state == &"greeter_lead" else "")
		# Waypoints first (out through his booth's gate, or back in), then the target.
		if _path.is_empty() and new_args.get("path", null) is Array:
			_path = (new_args["path"] as Array).duplicate()
		# A path with nowhere else to go ends where it ends (he stays there).
		if not _path.is_empty() and not (to is Vector3) and new_state != &"hurry_back" and new_state != &"counter_idle":
			target = _path[_path.size() - 1]
		# Where he is is where he stays (handing over a clipboard, waving people over).
		if bool(new_args.get("stay", false)) or new_state == &"greeter_offer" or new_state == &"greeter_punch_card":
			target = global_position
		var face: Variant = new_args.get("face", null)
		if face is Vector3:
			var flat: Vector3 = (face as Vector3) - target
			if Vector2(flat.x, flat.z).length() > 0.05:
				target_yaw = yaw_toward(flat)
		var zzz := _zzz()
		if zzz != null:
			zzz.visible = new_state == &"asleep"

	func _zzz() -> Node3D:
		if not str(name).begins_with("Clerk") or get_parent() == null or get_parent().get_parent() == null:
			return null
		return get_parent().get_parent().get_node_or_null("Windows/%s/Zzz" % str(name).trim_prefix("Clerk")) as Node3D

	func _gesture(gesture_name: String) -> void:
		if gesture_name != "" and body != null and body.has_method("gesture"):
			body.call("gesture", gesture_name)

	func _process(delta: float) -> void:
		var goal := target
		if not _path.is_empty():
			goal = _path[0]
			if Vector2(goal.x - global_position.x, goal.z - global_position.z).length() < 0.15:
				_path.pop_front()
		var flat := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
		var step := STAFF_WALK * hurry * delta
		var yaw_goal := target_yaw
		if flat.length() > 0.05:
			var heading := flat.normalized()
			# Step round people instead of through them (nobody here touches a player).
			for node: Node in get_tree().get_nodes_in_group("players"):
				var person := node as Node3D
				var away := Vector3(global_position.x - person.global_position.x, 0.0, global_position.z - person.global_position.z)
				var gap := away.length()
				if gap < STAFF_PERSONAL_SPACE and gap > 0.01 and heading.dot(-away / gap) > -0.2:
					var side := Vector3(-heading.z, 0.0, heading.x)
					side *= 1.0 if side.dot(away) >= 0.0 else -1.0
					heading = (heading + side * (STAFF_PERSONAL_SPACE - gap) * 2.5 + away / gap * maxf(0.6 - gap, 0.0) * 4.0).normalized()
			global_position += heading * minf(step, flat.length())
			yaw_goal = yaw_toward(heading)
		rotation.y = lerp_angle(rotation.y, yaw_goal, clampf(delta * STAFF_TURN, 0.0, 1.0))
		if body != null:
			# Asleep: slumped forward over the counter.
			var slump := 0.3 if state == &"asleep" else 0.0
			body.rotation.x = lerpf(body.rotation.x, slump, clampf(delta * 3.0, 0.0, 1.0))
