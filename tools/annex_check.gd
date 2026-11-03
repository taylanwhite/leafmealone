extends RefCounted

## Dev tool, headless: checks Satellite Annex B's set (levels/annex/annex_b.gd,
## R2 chunk 5) without a game running. Run by tools/mesh_check.gd (the meshcheck
## CI step, no port). For seeds 1 and 77 (and the world's) it builds AnnexSet and
## checks:
## - the node contract (gap-specs nice_boys C9, C10): every name, its type, and
##   the methods R2 chunk 6 calls (set_state, set_held, set_speed, show_number,
##   play, window_icon, window_color, apply_run)
## - budgets: triangles <= Constants.ANNEX_MAX_TRIS and draw calls (visible mesh
##   surfaces, labels, sprites) <= Constants.ANNEX_MAX_DRAWS; the staff are
##   characters, budgeted with the cast, so they don't count
## - every place someone stands (the curb, the side door, the threshold, the
##   counters and their queues, the desk, the tray, the appliances, the forecourt)
##   is on the floor and reachable from the curb by a player's capsule (a flood
##   fill over the colliders, the doors and turnstile open)
## - the budgets hold in the busiest pose chunk 6 drives too (every window
##   closed and on a break, the tray receiving)
## - the closed turnstile seals its passage from the floor to the lintel (no
##   jump-and-crouch over it), and opened it leaves the passage clear
## - no camera anchor (Cam*) sits inside a collider
## - Form 27-B held in someone's hand (attach_hand) is at their left hand
## - every sign passes the humor guardrail (net/dev/guardrail.gd)
## - the same seed builds the same set; another seed dresses the windows differently,
##   and apply_run dresses them for a run
## Prints what it measured. Returns false on any failure.

const _Annex = preload("res://levels/annex/annex_b.gd")
const _Guardrail = preload("res://net/dev/guardrail.gd")
const _Form = preload("res://props/form_27b.gd")

## A player's capsule (player/player.tscn) and the flood fill's grid, in meters.
const RADIUS: float = 0.35
const CELL: float = 0.2
## Body heights that count as "in the way" (feet clear a curb, the head the lintels).
const LOW: float = 0.15
const HIGH: float = 1.75
const SEEDS: Array[int] = [1, 77]


static func run() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Node3D.new()
	holder.name = "AnnexCheck"
	tree.root.add_child(holder)
	var ok := true
	var hashes: Array[int] = []
	var icons: Array[String] = []
	for seed_value: int in SEEDS + [Constants.ANNEX_SET_SEED, Constants.ANNEX_SET_SEED]:
		var zone := Node3D.new()
		zone.name = "BorderZone%d" % hashes.size()
		holder.add_child(zone)
		var made: Node3D = _Annex.build(zone, seed_value)
		await tree.process_frame
		ok = _check_contract(made) and ok
		ok = _check_budget(made, seed_value) and ok
		ok = _check_signs(made) and ok
		ok = _check_seal(made, true) and ok
		# Open the doors and the turnstile, as the Annex does for someone walking in.
		for path: String in ["Entrance", "SideDoor"]:
			made.get_node(path).call("set_state", &"open", -1000.0)
		made.get_node("Turnstile").call("set_state", &"open", -1000.0)
		await tree.physics_frame
		await tree.process_frame
		ok = _check_seal(made, false) and ok
		ok = _check_reach(made, seed_value) and ok
		ok = _check_anchors(made) and ok
		hashes.append(_hash(made))
		icons.append(",".join(PackedStringArray([made.call("window_icon", "A"), made.call("window_icon", "B"), made.call("window_icon", "C")])))
		ok = await _check_busy_budget(made, seed_value) and ok
		zone.queue_free()
	# The same seed, the same set; another seed, other looks.
	var same: bool = hashes[2] == hashes[3]
	var differs := icons[0] != icons[1]
	print("[AnnexCheck] determinism: same seed same set %s, seeds %d and %d dress A-C as %s / %s (differ %s)" % [same, SEEDS[0], SEEDS[1], icons[0], icons[1], differs])
	ok = same and differs and ok
	ok = await _check_apply_run(holder) and ok
	ok = await _check_form_in_hand(holder) and ok
	holder.queue_free()
	print("[AnnexCheck] %s" % ("ok" if ok else "FAIL"))
	return ok


## Every name chunk 6 drives, its type, and its methods.
static func _check_contract(made: Node3D) -> bool:
	var problems := PackedStringArray()
	var markers := ["AnnexCurb", "AnnexSide", "Threshold", "Forecourt", "ForecourtCurb", "HeadDesk/DeskSpot", "HeadDesk/Pad"]
	for window: String in ["A", "B", "C", "D"]:
		for child: String in ["Counter", "QueueSpots/Spot0", "QueueSpots/Spot1", "QueueSpots/Spot2", "StampPad", "Bell", "ClerkSeat", "Cabinet", "BreakSpot0", "BreakSpot1", "BreakSpot2"]:
			markers.append("Windows/%s/%s" % [window, child])
	for path: String in markers:
		if not made.get_node_or_null(path) is Marker3D:
			problems.append("%s is not a Marker3D" % path)
	for path: String in ["GreeterPath", "JanitorPath"]:
		var path_node := made.get_node_or_null(path) as Path3D
		if path_node == null or path_node.curve == null or path_node.curve.point_count < 2:
			problems.append("%s is not a Path3D with a route" % path)
	var methods := {
		"Entrance": ["set_state"], "SideDoor": ["set_state"], "Turnstile": ["set_state"],
		"HeadDesk": ["set_state"], "HeadDesk/BigStamp": ["set_held", "set_state"],
		"Copier": ["set_state"], "Cooler": ["set_state"], "CoffeeMachine": ["set_state"],
		"CoSignSheet": ["set_state"], "OutgoingTray": ["set_state"], "WallClock": ["set_speed"],
		"NowServing": ["show_number"], "Dispenser": [], "Stickies": [],
	}
	for window: String in ["A", "B", "C", "D"]:
		methods["Windows/%s" % window] = ["set_state", "apply_look"]
	for line: String in ["A", "B", "C"]:
		methods["FloorLines/%s" % line] = ["set_state"]
	for row: int in Constants.ANNEX_LIGHT_ROWS:
		methods["LightRows/Row%d" % row] = ["set_state"]
	for staff: String in ["ClerkA", "ClerkB", "ClerkC", "ClerkD", "HeadNiceBoy", "Greeter", "Janitor"]:
		methods["Staff/%s" % staff] = ["play", "bark"]
	for path: String in methods:
		var node := made.get_node_or_null(path)
		if node == null:
			problems.append("%s is missing" % path)
			continue
		for method: String in methods[path]:
			if not node.has_method(method):
				problems.append("%s has no %s()" % [path, method])
	for method: String in ["window_icon", "window_color", "route", "apply_run", "looks_for"]:
		if not made.has_method(method):
			problems.append("AnnexSet has no %s()" % method)
	# Every window state and every clerk state is accepted.
	for state: StringName in [&"lamp_on", &"lamp_off", &"blind_up", &"blind_down", &"clock_sign", &"stamp_lifted", &"stamp_down"]:
		made.get_node("Windows/A").call("set_state", state, -1000.0)
	for state: StringName in [&"on", &"off", &"flicker"]:
		made.get_node("LightRows/Row0").call("set_state", state, -1000.0)
	made.get_node("LightRows/Row0").call("set_state", &"on", -1000.0)
	made.get_node("Windows/A").call("set_state", &"blind_up", -1000.0)
	made.get_node("Windows/A").call("set_state", &"lamp_on", -1000.0)
	var states: Array = (load("res://npcs/clerk.gd") as GDScript).get("STATES")
	for required: String in ["counter_idle", "wave_up", "take_form", "stamp", "hand_back", "peer_form", "head_shake_point", "phone", "telegraph_stretch", "walk_to", "on_break", "hurry_back", "asleep", "wake", "lunch_bite", "lunch_turned", "lean_toward", "turn_to_cabinet", "twitch_turn_back", "notice", "add_carbon", "volley", "head_windup_slam", "gasp_whistle", "walk_hand_out", "take_stamp_back", "greeter_lead", "greeter_offer", "greeter_punch_card", "janitor_mop", "closing_rush"]:
		if not states.has(StringName(required)):
			problems.append("clerk.gd has no state %s" % required)
	if not problems.is_empty():
		for problem: String in problems:
			print("[AnnexCheck] contract FAIL  %s" % problem)
	return problems.is_empty()


## Triangles and draw calls of everything drawn, the staff aside.
static func _check_budget(made: Node3D, seed_value: int) -> bool:
	var measured := _measure(made)
	var tris: int = measured[0]
	var draws: int = measured[1]
	var ok := tris <= Constants.ANNEX_MAX_TRIS and draws <= Constants.ANNEX_MAX_DRAWS
	if not ok or OS.get_environment("ANNEX_DRAWS") != "":
		_print_draws(made)
	print("[AnnexCheck] seed %d: %d triangles (budget %d), %d draw calls (budget %d) %s" % [seed_value, tris, Constants.ANNEX_MAX_TRIS, draws, Constants.ANNEX_MAX_DRAWS, "ok" if ok else "FAIL"])
	return ok


## The busiest the room gets while chunk 6 drives it: every window closed and
## on a break at once (its lamp off, as both are, blinds down, clock sign up,
## the stamp lifted), the tray catching a form, the copier jamming. The budget
## holds then too. The set is put back as it was built afterwards.
static func _check_busy_budget(made: Node3D, seed_value: int) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var now: float = OfficeProps.now()
	for window: String in ["A", "B", "C", "D"]:
		var node := made.get_node("Windows/%s" % window)
		node.call("set_state", &"blind_down", now - 5.0)
		node.call("set_state", &"lamp_off", now - 5.0)
		node.call("set_state", &"clock_sign", now - 5.0)
		node.call("set_state", &"stamp_lifted", now - 5.0)
	made.get_node("OutgoingTray").call("set_state", &"receive", now - 0.2)
	made.get_node("Copier").call("set_state", &"jam", now - 0.2)
	await tree.process_frame
	var measured := _measure(made)
	var draws: int = measured[1]
	var ok := draws <= Constants.ANNEX_MAX_DRAWS and int(measured[0]) <= Constants.ANNEX_MAX_TRIS
	if not ok or OS.get_environment("ANNEX_DRAWS") != "":
		_print_draws(made)
	print("[AnnexCheck] seed %d busy (lamps off, blinds down, clock signs up, tray receiving): %d draw calls (budget %d) %s" % [seed_value, draws, Constants.ANNEX_MAX_DRAWS, "ok" if ok else "FAIL"])
	for window: String in ["A", "B", "C", "D"]:
		var node := made.get_node("Windows/%s" % window)
		node.call("set_state", &"clock_sign_off", -1000.0)
		node.call("set_state", &"stamp_down", -1000.0)
		node.call("set_state", &"blind_down" if window == "D" else &"blind_up", -1000.0)
		node.call("set_state", &"lamp_off" if window == "D" else &"lamp_on", -1000.0)
	made.get_node("Copier").call("set_state", &"idle", -1000.0)
	await tree.process_frame
	return ok


## The closed turnstile seals its passage from the floor to the lintel (a jump
## with a crouch at the top must not clear it); open, the passage is clear.
static func _check_seal(made: Node3D, closed: bool) -> bool:
	var shapes: Array = []
	for node: Node in made.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node.shape is BoxShape3D and not shape_node.disabled:
			shapes.append([shape_node.global_transform, (shape_node.shape as BoxShape3D).size * 0.5])
	var z := Constants.ANNEX_SIZE.z * 0.5 + _Annex.WALL * 0.5
	var problems := PackedStringArray()
	for dx: float in ([-0.4, 0.0, 0.4] if closed else [0.0]):
		var y := 0.05
		while y < _Annex.DOOR_HEIGHT + 0.4:
			var at := made.global_transform * Vector3(_Annex.TURNSTILE_X + dx, y, z)
			var inside := false
			for entry: Array in shapes:
				var local: Vector3 = (entry[0] as Transform3D).affine_inverse() * at
				var half: Vector3 = entry[1]
				if absf(local.x) <= half.x + 0.001 and absf(local.y) <= half.y + 0.001 and absf(local.z) <= half.z + 0.001:
					inside = true
					break
			if closed and not inside:
				problems.append("the closed turnstile leaves a gap at x %+.1f, height %.2f m" % [dx, y])
				break
			if not closed and inside and y < _Annex.DOOR_HEIGHT - 0.1:
				problems.append("the open turnstile still blocks its passage at height %.2f m" % y)
				break
			y += 0.1
	for problem: String in problems:
		print("[AnnexCheck] turnstile FAIL  %s" % problem)
	if problems.is_empty():
		print("[AnnexCheck] the turnstile, %s: %s" % ["closed" if closed else "open", "sealed to the lintel" if closed else "its passage clear"])
	return problems.is_empty()


## Form 27-B held by someone else (attach_hand) sits in their left hand, not
## dangling at the shins: within a few cm of where the left arm's hand is.
static func _check_form_in_hand(holder: Node3D) -> bool:
	var player := Node3D.new()
	player.name = "FormHolder"
	holder.add_child(player)
	var visual := Node3D.new()
	visual.name = "Visual"
	player.add_child(visual)
	var body: Node3D = (load("res://player/cartoon_body.gd") as GDScript).new()
	body.name = "CartoonBody"
	visual.add_child(body)
	body.call("build")
	var form: Node3D = _Form.make(PackedStringArray(["A", "B"]), {})
	holder.add_child(form)
	form.call("attach_hand", player)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var arm := body.call("pose_part", "arm_l") as Node3D
	var hand := arm.global_transform * Vector3(0.0, -Constants.FORM_HAND_DROP, 0.0) if arm != null else Vector3.INF
	var at := form.global_position
	var off := at.distance_to(hand) if hand.is_finite() else INF
	var ok := form.get_parent() == arm and off < 0.12 and at.y > 0.5 and at.y < 1.1
	print("[AnnexCheck] Form 27-B in a held hand: %.2f m from the left hand, at height %.2f m %s" % [off, at.y, "ok" if ok else "FAIL"])
	player.queue_free()
	return ok


## [triangles, draw calls] of what is drawn now, the staff aside.
static func _measure(made: Node3D) -> Array:
	var tris := 0
	var draws := 0
	var staff := made.get_node("Staff")
	for node: Node in made.find_children("*", "GeometryInstance3D", true, false):
		if staff.is_ancestor_of(node) or not (node as Node3D).is_visible_in_tree():
			continue
		if node is MeshInstance3D:
			var mesh := (node as MeshInstance3D).mesh
			if mesh == null:
				continue
			draws += mesh.get_surface_count()
			tris += mesh.get_faces().size() / 3
		elif node is Label3D or node is SpriteBase3D:
			draws += 1
			tris += 2
		elif node is MultiMeshInstance3D:
			var multi := (node as MultiMeshInstance3D).multimesh
			draws += 1
			tris += multi.mesh.get_faces().size() / 3 * multi.instance_count if multi != null and multi.mesh != null else 0
	return [tris, draws]


## Every sign's words against the guardrail.
static func _check_signs(made: Node3D) -> bool:
	var hits: Array = []
	var count := 0
	for node: Node in made.find_children("*", "Label3D", true, false):
		var text := (node as Label3D).text
		if text == "":
			continue
		count += 1
		for hit: Variant in _Guardrail.check(text):
			hits.append("%s: %s" % [node.name, hit])
	for hit: Variant in hits:
		print("[AnnexCheck] sign FAIL  %s" % hit)
	return hits.is_empty() and count > 0


## Colliders as 2D boxes on the floor plan: [center (x, z), half extents, angle].
static func _footprints(made: Node3D) -> Array:
	var boxes: Array = []
	for node: Node in made.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node.disabled or shape_node.shape == null:
			continue
		var xform := made.global_transform.affine_inverse() * shape_node.global_transform
		var half := Vector3.ZERO
		if shape_node.shape is BoxShape3D:
			half = (shape_node.shape as BoxShape3D).size * 0.5
		elif shape_node.shape is CylinderShape3D:
			var cylinder := shape_node.shape as CylinderShape3D
			half = Vector3(cylinder.radius, cylinder.height * 0.5, cylinder.radius)
		else:
			continue
		var scale := xform.basis.get_scale()
		half *= scale
		var bottom := xform.origin.y - half.y
		var top := xform.origin.y + half.y
		if top < LOW or bottom > HIGH:
			continue
		var x_axis := xform.basis.x.normalized()
		boxes.append([Vector2(xform.origin.x, xform.origin.z), Vector2(half.x, half.z), atan2(-x_axis.z, x_axis.x)])
	return boxes


static func _blocked(point: Vector2, boxes: Array) -> bool:
	for box: Array in boxes:
		var local := (point - (box[0] as Vector2)).rotated(float(box[2]))
		var half: Vector2 = box[1]
		var nearest := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
		if local.distance_to(nearest) < RADIUS:
			return true
	return false


## A flood fill from the curb over the pad (Constants.PAD_RECTS BorderZone).
static func _check_reach(made: Node3D, seed_value: int) -> bool:
	var boxes := _footprints(made)
	var pad: Rect2 = Constants.PAD_RECTS.get("BorderZone", Rect2(-20.0, -20.0, 40.0, 40.0))
	var columns := int(pad.size.x / CELL)
	var rows := int(pad.size.y / CELL)
	var start := _cell_of(_flat(made, "AnnexCurb"), pad)
	var reached := {}
	var queue: Array[Vector2i] = [start]
	reached[start] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cell + step
			if next.x < 1 or next.y < 1 or next.x >= columns - 1 or next.y >= rows - 1 or reached.has(next):
				continue
			if _blocked(_center(next, pad), boxes):
				continue
			reached[next] = true
			queue.append(next)
	var spots := ["AnnexCurb", "AnnexSide", "Threshold", "Forecourt", "ForecourtCurb", "HeadDesk/DeskSpot", "OutgoingTray/Spot", "Copier/Spot", "Cooler/Spot", "CoffeeMachine/Spot"]
	for window: String in ["A", "B", "C", "D"]:
		spots.append("Windows/%s/Counter" % window)
		for spot: int in 3:
			spots.append("Windows/%s/QueueSpots/Spot%d" % [window, spot])
	var problems := PackedStringArray()
	for path: String in spots:
		var node := made.get_node_or_null(path) as Node3D
		if node == null:
			problems.append("%s missing" % path)
			continue
		var local := made.to_local(node.global_position)
		if absf(local.y) > 0.05:
			problems.append("%s floats at y %.2f" % [path, local.y])
		if not _near_reached(_cell_of(Vector2(local.x, local.z), pad), reached):
			problems.append("%s can't be reached from the curb" % path)
	# The staff's side of the counters is closed to the lobby.
	for window: String in ["A", "B", "C", "D"]:
		var seat := made.to_local((made.get_node("Windows/%s/ClerkSeat" % window) as Node3D).global_position)
		if reached.has(_cell_of(Vector2(seat.x, seat.z), pad)):
			problems.append("window %s's clerk can be walked up to from the lobby" % window)
	# The co-signer sheet: someone can stand at the podium in front of it.
	var sheet := made.to_local((made.get_node("CoSignSheet") as Node3D).global_position)
	if not _near_reached(_cell_of(Vector2(sheet.x, sheet.z + 0.9), pad), reached):
		problems.append("nobody can stand at the co-signer sheet")
	for problem: String in problems:
		print("[AnnexCheck] reach FAIL  seed %d: %s" % [seed_value, problem])
	print("[AnnexCheck] seed %d: %d colliders, %d floor cells reachable from the curb, %d spots checked" % [seed_value, boxes.size(), reached.size(), spots.size() + 1])
	return problems.is_empty()


static func _near_reached(cell: Vector2i, reached: Dictionary) -> bool:
	for dx: int in range(-2, 3):
		for dy: int in range(-2, 3):
			if reached.has(cell + Vector2i(dx, dy)):
				return true
	return false


static func _flat(made: Node3D, path: String) -> Vector2:
	var local := made.to_local((made.get_node(path) as Node3D).global_position)
	return Vector2(local.x, local.z)


static func _cell_of(point: Vector2, pad: Rect2) -> Vector2i:
	return Vector2i(int((point.x - pad.position.x) / CELL), int((point.y - pad.position.y) / CELL))


static func _center(cell: Vector2i, pad: Rect2) -> Vector2:
	return pad.position + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


## Camera anchors (Marker3D named Cam*) in the open, not inside a wall or a desk.
static func _check_anchors(made: Node3D) -> bool:
	var problems := PackedStringArray()
	var shapes: Array = []
	for node: Node in made.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node.shape is BoxShape3D and not shape_node.disabled:
			shapes.append([shape_node.global_transform, (shape_node.shape as BoxShape3D).size * 0.5])
	var count := 0
	for node: Node in made.find_children("Cam*", "Marker3D", true, false):
		count += 1
		var at := (node as Node3D).global_position
		for entry: Array in shapes:
			var local: Vector3 = (entry[0] as Transform3D).affine_inverse() * at
			var half: Vector3 = entry[1]
			if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
				problems.append("%s is inside a collider" % node.name)
				break
	for problem: String in problems:
		print("[AnnexCheck] anchor FAIL  %s" % problem)
	return problems.is_empty() and count > 0


## Node paths, rounded transforms, mesh sizes and words: equal for equal sets.
static func _hash(made: Node3D) -> int:
	var digest := 0
	var staff := made.get_node("Staff")
	for node: Node in made.find_children("*", "Node3D", true, false):
		if staff.is_ancestor_of(node):
			continue
		var node_3d := node as Node3D
		var entry: Array = [_index_path(made, node), node.get_class(), made.to_local(node_3d.global_position).snapped(Vector3(0.001, 0.001, 0.001))]
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			entry.append((node as MeshInstance3D).mesh.get_faces().size())
		if node is Label3D:
			entry.append((node as Label3D).text)
		digest = [digest, entry].hash()
	return digest


## Where a node sits by child indices (unnamed nodes get engine-made names that
## differ from build to build).
static func _index_path(root: Node, node: Node) -> String:
	var steps := PackedStringArray()
	while node != root and node != null:
		steps.append(str(node.get_index()))
		node = node.get_parent()
	return "/".join(steps)


## apply_run dresses windows A-C (and their lines) with a run's looks.
static func _check_apply_run(holder: Node3D) -> bool:
	var zone := Node3D.new()
	holder.add_child(zone)
	var made: Node3D = _Annex.build(zone, 5)
	var run_looks: Array = _Annex.looks_for(99)
	_Annex.apply_run(made, run_looks)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var ok := true
	for index: int in 3:
		var id: String = ["A", "B", "C"][index]
		ok = ok and made.call("window_icon", id) == str((run_looks[index] as Dictionary)["icon"])
		ok = ok and made.call("window_color", id) == (run_looks[index] as Dictionary)["color"]
	print("[AnnexCheck] apply_run dresses A-C for a run: %s" % ok)
	zone.queue_free()
	return ok

## Draw calls by the set's top-level parts, when over budget (or ANNEX_DRAWS set).
static func _print_draws(made: Node3D) -> void:
	var staff := made.get_node("Staff")
	var by_part := {}
	for node: Node in made.find_children("*", "GeometryInstance3D", true, false):
		if staff.is_ancestor_of(node) or not (node as Node3D).is_visible_in_tree():
			continue
		var part := node
		while part.get_parent() != made:
			part = part.get_parent()
		var count := 1
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			count = (node as MeshInstance3D).mesh.get_surface_count()
		by_part[str(part.name)] = int(by_part.get(str(part.name), 0)) + count
	print("[AnnexCheck] draws by part: %s" % str(by_part))
