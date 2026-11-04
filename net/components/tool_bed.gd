extends Node3D

## Authority: host. The crew's kit riding on Chefty (p2-kit; docs/GAME.md "The
## crew's kit"), the junk bed's pattern (net/components/junk_bed.gd). Both
## Chefties (the legacy ride, net/components/ride.gd, and the drivable one,
## chefty_drive.gd) make one under their Body, so it rides along.
##
## What's aboard is shown by the truck itself, never a list on screen: long
## tools lie on their sides on the ladder rack over the cab (two crossbars, one
## spot each across the truck, rake heads standing up like fins), the ladder on
## top of them, and the pushed ones (mower, washer) on the bed floor by the
## tailgate. Holding a tool by the bed, E loads it ("[E] Load"); a tool thrown
## into the bed that comes to rest there is loaded too. Either way the prop
## goes, and the same model glides from where it was onto its spot on every
## peer, so nothing jumps. Looking at one on the rack, E takes it ("[E] Take"):
## it becomes a prop on its spot and comes into your hands the way a pickup
## does. Gas tools aboard are topped up from the crew's gas when Chefty leaves
## the store (Shops' supply). Every peer draws the load from _rpc_tools (the
## whole list on every change; a dozen entries at most), and a late joiner gets
## it from its Chefty's state request.

const _YardModels = preload("res://props/yard_models.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _Hotbar = preload("res://net/components/hotbar.gd")
const _KitRules = preload("res://core/kit_rules.gd")
const _ToolTiers = preload("res://core/tool_tiers.gd")
## The rack's color: galvanized steel.
const RACK_COLOR := Color(0.55, 0.57, 0.6)
## The bed's middle (its space), what "[E] Load" measures from.
const BED_MIDDLE := Vector3(0.0, 1.2, 0.7)

## The load on every peer: [{kind, tier, fuel, slot}]. slot is "rack:<i>",
## "ladder" or "floor:<i>".
var tools: Array = []
## Local: models gliding onto their spots: slot -> {from (bed space), age}.
var _glides: Dictionary = {}
## Host: whether Chefty was at the store when last looked (the top-up on leaving).
var _was_at_store: bool = true
## Host: a take on its way into someone's hands (the slot), so it isn't taken twice.
var _taking: Dictionary = {}
## Every model's bounds, by kind and tier (props/yard_models.gd builds them once).
static var _boxes: Dictionary = {}


## Named before it's added: its RPCs need the same path on every peer.
func _init() -> void:
	name = "ToolBed"


func _ready() -> void:
	_build_rack()
	_was_at_store = _at_store()


func count() -> int:
	return tools.size()


## How many of this kind are aboard.
func count_of(kind: String) -> int:
	var out := 0
	for entry: Dictionary in tools:
		if str(entry["kind"]) == kind:
			out += 1
	return out


# ---------------------------------------------------------------- where things go

## The spot a tool of this kind takes, given the spots taken: the ladder on top
## of the rack, the pushed tools on the floor, everything else on the rack; ""
## when its place is full.
static func slot_for(kind: String, taken: Array) -> String:
	if kind == "ladder":
		return "ladder" if not taken.has("ladder") else ""
	if _Hotbar.carry_class(kind) == "push":
		for index: int in Constants.KIT_BED_FLOOR_SLOTS.size():
			if not taken.has("floor:%d" % index):
				return "floor:%d" % index
		return ""
	# The rack fills from the middle out, so a few tools sit over the cab's middle.
	for index: int in _rack_order():
		if not taken.has("rack:%d" % index):
			return "rack:%d" % index
	return ""


## The rack spots, middle out: 4, 3, 5, 2, 6, 1, 7, 0 for eight.
static func _rack_order() -> Array[int]:
	var out: Array[int] = []
	var size := Constants.KIT_RACK_SLOTS_X.size()
	var middle := size / 2
	out.append(middle)
	for step: int in range(1, size):
		var left := middle - step
		var right := middle + step
		if left >= 0:
			out.append(left)
		if right < size:
			out.append(right)
	return out


func _taken() -> Array:
	var out: Array = []
	for entry: Dictionary in tools:
		out.append(str(entry["slot"]))
	return out


## Whether a tool of this kind would fit aboard now.
func has_room_for(kind: String) -> bool:
	return slot_for(kind, _taken()) != ""


## Where a tool of this kind and tier lies on its spot, in the bed's space (the
## model's own origin, as props/yard_models.gd builds it).
static func slot_pose(kind: String, tier: int, slot: String) -> Transform3D:
	var box := model_box(kind, tier)
	var size := box.size
	if slot.begins_with("floor:"):
		var spot: Vector3 = Constants.KIT_BED_FLOOR_SLOTS[clampi(int(slot.trim_prefix("floor:")), 0, Constants.KIT_BED_FLOOR_SLOTS.size() - 1)]
		var basis := Basis(Vector3.UP, Constants.KIT_BED_FLOOR_YAW)
		var turned := Transform3D(basis, Vector3.ZERO) * box
		return Transform3D(basis, spot - Vector3(turned.get_center().x, turned.position.y, turned.get_center().z))
	# On the rack: the longest side along the truck; on the rack's spots the
	# middle side stands up (a rake's head like a fin), the ladder lies flat on top.
	var axes: Array[int] = [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]
	axes.sort_custom(func(a: int, b: int) -> bool: return size[a] > size[b])
	var longest := axes[0]
	var middle := axes[1]
	var shortest := axes[2]
	var up_axis := middle if slot != "ladder" else shortest
	var across_axis := shortest if slot != "ladder" else middle
	var columns: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	columns[longest] = Vector3(0.0, 0.0, 1.0)
	columns[up_axis] = Vector3(0.0, 1.0, 0.0)
	columns[across_axis] = Vector3(1.0, 0.0, 0.0)
	var basis := Basis(columns[0], columns[1], columns[2])
	if basis.determinant() < 0.0:
		columns[across_axis] = Vector3(-1.0, 0.0, 0.0)
		basis = Basis(columns[0], columns[1], columns[2])
	# Every other spot lies the other way round (heads to the front, then to the
	# back), the way tools go on a real rack: the rake heads stand up at both
	# ends, so you can count them.
	if slot.begins_with("rack:") and int(slot.trim_prefix("rack:")) % 2 == 1:
		basis = Basis(Vector3.UP, PI) * basis
	var turned := Transform3D(basis, Vector3.ZERO) * box
	var spot := Constants.KIT_LADDER_ON_RACK if slot == "ladder" else Vector3(Constants.KIT_RACK_SLOTS_X[clampi(int(slot.trim_prefix("rack:")), 0, Constants.KIT_RACK_SLOTS_X.size() - 1)], Constants.KIT_RACK_Y, Constants.KIT_RACK_Z)
	return Transform3D(basis, spot - Vector3(turned.get_center().x, turned.position.y, turned.get_center().z))


## A kit model's bounds, in its own space (cached).
static func model_box(kind: String, tier: int) -> AABB:
	var key := "%s|%d" % [kind, tier]
	if not _boxes.has(key):
		var view := _model(kind, tier)
		_boxes[key] = view.get_aabb() if view != null else AABB(Vector3(-0.2, 0.0, -0.8), Vector3(0.4, 0.3, 1.6))
		if view != null:
			view.free()
	return _boxes[key]


static func _model(kind: String, tier: int) -> MeshInstance3D:
	return _YardModels.node(kind, Color.WHITE, Vector3.ONE, {}, tier)


# ---------------------------------------------------------------- host

## Host: take in a kit prop (from someone's hands by the bed, or lying still in
## the bed). False when its place aboard is full or it isn't kit.
func accept(prop: Node3D) -> bool:
	if not Net.is_host() or prop == null or not _KitRules.is_kit(prop):
		return false
	var kind := str(prop.get("kind"))
	var slot := slot_for(kind, _taken())
	if slot == "":
		return false
	var look := prop.get_node_or_null("Visual") as Node3D
	var seen := look.global_transform if look != null else prop.global_transform
	var from := global_transform.affine_inverse() * seen
	from.basis = from.basis.orthonormalized()
	tools.append({"kind": kind, "tier": int(prop.get("tier")), "fuel": float(prop.get("fuel")), "slot": slot})
	_send(slot, from)
	prop.queue_free()
	return true


## Host, loading a save or a dev kit: these go aboard ([{kind, tier, fuel}]), each
## on its spot. Returns the ones that didn't fit.
func restore(entries: Array) -> Array:
	var left: Array = []
	if not Net.is_host():
		return entries
	for entry: Dictionary in entries:
		var slot := slot_for(str(entry["kind"]), _taken())
		if slot == "":
			left.append(entry)
			continue
		tools.append({"kind": str(entry["kind"]), "tier": int(entry["tier"]), "fuel": float(entry.get("fuel", 100.0)), "slot": slot})
	_send()
	return left


## Every peer: the tool aboard the local player is looking right at, within
## reach: {index, at (world)}, or {} for none.
func looked_at(player: Node3D) -> Dictionary:
	if player == null or tools.is_empty():
		return {}
	var head := player.get_node_or_null("Visual/Head") as Node3D
	var eye := head.global_position if head != null else player.global_position + Vector3(0.0, 1.6, 0.0)
	var aim := -(head.global_basis.z if head != null else player.global_basis.z).normalized()
	var best := {}
	var best_miss := Constants.KIT_TAKE_LOOK_MISS
	for index: int in tools.size():
		var entry: Dictionary = tools[index]
		if _taking.has(str(entry["slot"])):
			continue
		var at := _world_middle(entry)
		var to := at - eye
		var along := to.dot(aim)
		if along <= 0.0 or to.length() > Constants.KIT_TAKE_REACH:
			continue
		# How far the look passes from the tool, along its length (a long tool is
		# looked at anywhere from end to end).
		var miss := _miss_along(entry, eye, aim)
		if miss < best_miss:
			best_miss = miss
			best = {"index": index, "at": at, "slot": str(entry["slot"])}
	return best


## The local player presses E looking at a tool aboard: the host hands it over.
func request_take(index: int) -> void:
	if index < 0 or index >= tools.size():
		return
	var slot := str((tools[index] as Dictionary)["slot"])
	if Net.is_host():
		_host_take(Net.local_peer_id(), slot)
	else:
		_rpc_request_take.rpc_id(1, slot)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_take(slot: String) -> void:
	if Net.is_host():
		_host_take(multiplayer.get_remote_sender_id(), slot)


## Host: peer takes the tool on this spot: it becomes a prop where it lay, held
## still, and a beat later comes into their hands (a pocket tool into a pocket
## and out, a big one into both arms), the way a pickup goes. Full pockets or
## full arms: the bar shakes and it stays aboard.
func _host_take(peer_id: int, slot: String) -> void:
	var index := -1
	for at: int in tools.size():
		if str((tools[at] as Dictionary)["slot"]) == slot:
			index = at
	if index < 0 or _taking.has(slot):
		return
	var player := _player(peer_id)
	if player == null or player.global_position.distance_to(_world_middle(tools[index])) > Constants.KIT_TAKE_REACH + 1.5:
		return
	var entry: Dictionary = tools[index]
	var kind := str(entry["kind"])
	var hotbar := get_tree().get_first_node_in_group("hotbar")
	if hotbar != null:
		var refuse := _Hotbar.arms_item(get_tree(), peer_id) != null or (_Hotbar.is_pocketable(kind) and not _Hotbar.has_room(get_tree(), peer_id, kind))
		if refuse:
			hotbar.call("host_refuse", peer_id, hotbar.call("refusal_reason", peer_id))
			return
	var kit := get_tree().get_first_node_in_group("kit")
	if kit == null:
		return
	tools.remove_at(index)
	_send()
	var pose := global_transform * slot_pose(kind, int(entry["tier"]), slot)
	var prop := kit.call("spawn_item", kind, int(entry["tier"]), float(entry["fuel"]), pose) as RigidBody3D
	if prop == null:
		return
	# Held still on its spot for a beat, so every peer has it there before it moves.
	prop.freeze = true
	prop.call("_set_solid", false)
	_taking[slot] = true
	await get_tree().create_timer(Constants.KIT_TAKE_HANDOFF_SECONDS).timeout
	_taking.erase(slot)
	if not is_instance_valid(prop):
		return
	prop.freeze = false
	prop.call("host_hand_to", peer_id)


## Host: whether this peer's player is close enough to the bed to load a tool.
func can_load_from(player: Node3D) -> bool:
	if player == null:
		return false
	var middle := global_transform * BED_MIDDLE
	return Vector2(player.global_position.x - middle.x, player.global_position.z - middle.z).length() <= Constants.KIT_LOAD_REACH


## The point over the bed a "[E] Load" prompt stands on (world).
func load_point() -> Vector3:
	return global_transform * (BED_MIDDLE + Vector3(0.0, 0.9, 0.0))


func _physics_process(delta: float) -> void:
	if not _glides.is_empty():
		_step_glides(delta)
	if not Net.is_host():
		return
	var at_store := _at_store()
	if _was_at_store and not at_store:
		top_up()
	_was_at_store = at_store


## Host: Chefty just left the store: every gas tool aboard gets its tank filled
## from the crew's gas (as much as there is).
func top_up() -> void:
	var shops := get_tree().get_first_node_in_group("shops")
	if shops == null or not Net.is_host():
		return
	var changed := false
	for entry: Dictionary in tools:
		if not _ToolTiers.is_gas_tool(str(entry["kind"])):
			continue
		var want := (100.0 - float(entry["fuel"])) / 100.0 * Constants.GAS_PER_TANK
		if want <= 0.001:
			continue
		var have := minf(want, float(shops.call("supply", "gas")))
		if have <= 0.0 or not bool(shops.call("consume", "gas", have)):
			continue
		entry["fuel"] = minf(100.0, float(entry["fuel"]) + have / Constants.GAS_PER_TANK * 100.0)
		changed = true
	if changed:
		_send()


## Whether Chefty stands at Homie Depot: the legacy ride parked at the store end,
## the drivable one on the store's lot.
func _at_store() -> bool:
	var chefty := get_parent().get_parent() if get_parent() != null else null
	if chefty == null:
		return true
	if chefty.has_method("parked_at_store"):
		return bool(chefty.call("parked_at_store"))
	return Constants.STORE_AREA.has_point(Vector2(global_position.x, global_position.z))


# ---------------------------------------------------------------- the wire

func _send(glide_slot: String = "", glide_from: Transform3D = Transform3D.IDENTITY) -> void:
	if multiplayer.multiplayer_peer == null:
		_rpc_tools(_wire(), glide_slot, glide_from)
		return
	_rpc_tools.rpc(_wire(), glide_slot, glide_from)


## Host: a late joiner's copy of the load.
func send_to(peer_id: int) -> void:
	if Net.is_host() and multiplayer.multiplayer_peer != null:
		_rpc_tools.rpc_id(peer_id, _wire(), "", Transform3D.IDENTITY)


func _wire() -> Array:
	var out: Array = []
	for entry: Dictionary in tools:
		out.append([str(entry["kind"]), int(entry["tier"]), float(entry["fuel"]), str(entry["slot"])])
	return out


## Every peer: the load as it is now. The models are redrawn whole (a dozen at
## most, their meshes cached), each on its spot; the one just loaded (glide_slot)
## starts where it was and glides there.
@rpc("authority", "call_local", "reliable")
func _rpc_tools(list: Array, glide_slot: String, glide_from: Transform3D) -> void:
	if not Net.is_host():
		tools = []
		for item: Variant in list:
			var parts: Array = item
			tools.append({"kind": str(parts[0]), "tier": int(parts[1]), "fuel": float(parts[2]), "slot": str(parts[3])})
	var holder := get_node_or_null("Load") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "Load"
		add_child(holder)
	for child: Node in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	for entry: Dictionary in tools:
		var view := _model(str(entry["kind"]), int(entry["tier"]))
		if view == null:
			continue
		var slot := str(entry["slot"])
		view.name = slot.replace(":", "_")
		view.set_meta("slot", slot)
		view.transform = slot_pose(str(entry["kind"]), int(entry["tier"]), slot)
		holder.add_child(view)
		view.reset_physics_interpolation()
	if glide_slot != "":
		_glides[glide_slot] = {"from": glide_from, "age": 0.0}
		_step_glides(0.0)
		var sfx := get_tree().get_first_node_in_group("sfx")
		if sfx != null:
			sfx.call("play_at", "pocket", global_transform * slot_pose_of(glide_slot).origin)


## The pose of whatever's on this spot now (identity when nothing is).
func slot_pose_of(slot: String) -> Transform3D:
	for entry: Dictionary in tools:
		if str(entry["slot"]) == slot:
			return slot_pose(str(entry["kind"]), int(entry["tier"]), slot)
	return Transform3D.IDENTITY


## Local: each gliding model moves along an arc from where it was to its spot,
## turning on the way, and lands with a small settle.
func _step_glides(delta: float) -> void:
	var holder := get_node_or_null("Load") as Node3D
	for slot: Variant in _glides.keys():
		var glide: Dictionary = _glides[slot]
		glide["age"] = float(glide["age"]) + delta
		var view := holder.get_node_or_null(str(slot).replace(":", "_")) as Node3D if holder != null else null
		var t := clampf(float(glide["age"]) / Constants.KIT_LOAD_GLIDE_SECONDS, 0.0, 1.0)
		if view == null or t >= 1.0:
			if view != null:
				view.transform = slot_pose_of(str(slot))
			_glides.erase(slot)
			continue
		var to := slot_pose_of(str(slot))
		var from: Transform3D = glide["from"]
		var eased := t * t * (3.0 - 2.0 * t)
		var at := from.origin.lerp(to.origin, eased) + Vector3.UP * Constants.KIT_LOAD_GLIDE_LIFT * 4.0 * t * (1.0 - t)
		var turn := from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), eased)
		view.transform = Transform3D(Basis(turn), at)


# ---------------------------------------------------------------- helpers

## A tool's middle in the world (its model's bounds' center on its spot).
func _world_middle(entry: Dictionary) -> Vector3:
	var pose := slot_pose(str(entry["kind"]), int(entry["tier"]), str(entry["slot"]))
	return global_transform * (pose * model_box(str(entry["kind"]), int(entry["tier"])).get_center())


## How far a look from eye along aim passes from this tool's long middle line.
func _miss_along(entry: Dictionary, eye: Vector3, aim: Vector3) -> float:
	var pose := global_transform * slot_pose(str(entry["kind"]), int(entry["tier"]), str(entry["slot"]))
	var box := model_box(str(entry["kind"]), int(entry["tier"]))
	var center := box.get_center()
	var long_axis := Vector3.AXIS_X if box.size.x >= box.size.y and box.size.x >= box.size.z else (Vector3.AXIS_Y if box.size.y >= box.size.z else Vector3.AXIS_Z)
	var half := Vector3.ZERO
	half[long_axis] = box.size[long_axis] * 0.4
	var a := pose * (center - half)
	var b := pose * (center + half)
	var best := INF
	for step: int in 9:
		var point := a.lerp(b, float(step) / 8.0)
		var to := point - eye
		var along := to.dot(aim)
		if along <= 0.0:
			continue
		best = minf(best, (to - aim * along).length())
	return best


## The rack over the cab: a crossbar behind the cab on two posts up from the
## bed's front corners, and one at the cab's nose on short feet on its roof.
func _build_rack() -> void:
	var rack := Node3D.new()
	rack.name = "Rack"
	add_child(rack)
	var bar_y := Constants.KIT_RACK_Y - 0.03
	for z: float in Constants.KIT_RACK_BARS_Z:
		_LowPoly.paint(_LowPoly.box(rack, Vector3(2.16, 0.06, 0.07), Vector3(0.0, bar_y, z), RACK_COLOR), "metal")
	var back := Constants.KIT_RACK_BARS_Z[0]
	var front := Constants.KIT_RACK_BARS_Z[Constants.KIT_RACK_BARS_Z.size() - 1]
	for side: float in [-1.0, 1.0]:
		# Up from the bed rail's front corner (its top at 1.6) to the bar.
		_LowPoly.paint(_LowPoly.box(rack, Vector3(0.06, bar_y - 1.6, 0.06), Vector3(side * 1.05, (bar_y + 1.6) * 0.5, back), RACK_COLOR), "metal")
		# Feet on the cab roof (2.45) to the front bar.
		_LowPoly.paint(_LowPoly.box(rack, Vector3(0.06, bar_y - 2.42, 0.06), Vector3(side * 1.0, (bar_y + 2.42) * 0.5, front), RACK_COLOR), "metal")
		# A rail along each side, so the rack reads as one piece.
		_LowPoly.paint(_LowPoly.box(rack, Vector3(0.05, 0.05, absf(front - back) + 0.07), Vector3(side * 1.05, bar_y, (front + back) * 0.5), RACK_COLOR), "metal")


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null
