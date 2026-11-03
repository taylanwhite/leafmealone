extends Node3D

## Authority: local, cosmetic; the visit itself is the host's (net/annex/annex.gd
## _rpc_request_visit). The way in for friends who are still free while someone
## is at Satellite Annex B: in the connected town, the Field Office's own front
## door on Main Street (TownMap.FIELD_OFFICE; levels/town/town_dressing.gd draws
## the building, this only makes its door work); on the legacy map, a lavender
## Courtesy Desk door that stands by the Homie Depot curb only while the Annex is
## open (driving:I deletes it with the legacy map). Interact at it (the prompt is
## the bare key) and you come in through the Annex's side door as a visitor:
## nothing can happen to you there, and you can co-sign, ring bells and carry
## the big stamp. Placed at runtime by the Annex on every peer, so no other file's
## scene or dressing changes.

const _LowPoly = preload("res://props/low_poly.gd")
const _NiceSeal = preload("res://props/nice_seal.gd")
const _Strings = preload("res://ui/strings.gd")
const DOOR_COLOR := Color(0.62, 0.55, 0.82)

## The zone a visitor comes back to, and where they stand when they do.
var zone: int = Net.Zone.STORE
var annex: Node
var _leaf: Node3D
var _swing_at: float = -100.0


## Every door for this map: [] when there's nowhere to put one.
static func place_all(world: Node, annex_node: Node) -> Array[Node]:
	var out: Array[Node] = []
	var town := world.has_method("is_town_map") and bool(world.call("is_town_map"))
	var script: GDScript = load("res://net/annex/visitor_door.gd")
	var door: Node3D = script.new()
	door.set("annex", annex_node)
	if town:
		door.name = "FieldOfficeDoor"
		door.set("zone", Net.Zone.TOWN)
		world.add_child(door)
		var office: Dictionary = TownMap.landmarks()["field_office"]
		var basis := Basis(Vector3.UP, float(office["yaw"]))
		door.global_transform = Transform3D(basis, (office["at"] as Vector3) + basis * Constants.ANNEX_FIELD_OFFICE_DOOR)
		door.call("_build", false)
	else:
		var store := world.get_node_or_null("StoreZone") as Node3D
		if store == null:
			door.free()
			return out
		door.name = "CourtesyDesk"
		door.set("zone", Net.Zone.STORE)
		store.add_child(door)
		door.position = Constants.ANNEX_STORE_DOOR
		door.rotation.y = Constants.ANNEX_STORE_DOOR_YAW
		door.call("_build", true)
	out.append(door)
	return out


func _ready() -> void:
	add_to_group("prompt_sources")
	add_to_group("annex_doors")


## The legacy desk is a whole little door frame; the Field Office already has its
## door, so it only gets a sticker and a leaf that swings.
func _build(free_standing: bool) -> void:
	if free_standing:
		for side: float in [-1.0, 1.0]:
			_LowPoly.paint(_LowPoly.box(self, Vector3(0.18, 2.5, 0.22), Vector3(side * 0.62, 1.25, 0.0), DOOR_COLOR.darkened(0.2), true), "planks")
		_LowPoly.paint(_LowPoly.box(self, Vector3(1.42, 0.2, 0.24), Vector3(0.0, 2.55, 0.0), DOOR_COLOR.darkened(0.2)), "planks")
		var sign := _LowPoly.text_sign(self, _Strings.ANNEX_UI["courtesy_desk"], Vector3(0.0, 2.95, 0.0), 40, Color(0.36, 0.24, 0.55))
		sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_leaf = Node3D.new()
	_leaf.name = "Leaf"
	add_child(_leaf)
	_leaf.position = Vector3(-0.53, 0.0, 0.06 if not free_standing else 0.0)
	_LowPoly.paint(_LowPoly.box(_leaf, Vector3(1.04, 2.3, 0.06), Vector3(0.52, 1.15, 0.0), DOOR_COLOR), "planks")
	_LowPoly.ball(_leaf, 0.05, Vector3(0.92, 1.05, 0.06), Color(0.88, 0.7, 0.28))
	var seal := _NiceSeal.node(0.16, Vector3.BACK)
	seal.position = Vector3(0.52, 1.7, 0.04)
	_leaf.add_child(seal)


## Interact here, from outside the Annex, not caught.
func prompt() -> Dictionary:
	if not _can_use():
		return {}
	return {"text": "{key:interact}", "plain": true, "at": global_position + Vector3(0.0, 1.9, 0.0) + global_basis.z * 0.3}


func _can_use() -> bool:
	if annex == null or not is_instance_valid(annex) or not bool(annex.call("is_active")):
		return false
	var me_id := Net.local_peer_id()
	if Net.player_zone(me_id) == Net.Zone.BORDER:
		return false
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and bool(director.call("is_captured", me_id)):
		return false
	var me := _me()
	return me != null and Vector2(me.global_position.x - global_position.x, me.global_position.z - global_position.z).length() <= Constants.ANNEX_DOOR_REACH


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and _can_use():
		_swing_at = Net.server_time()
		annex.call("request_visit", str(name))
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _leaf == null:
		return
	var age := Net.server_time() - _swing_at
	var open := 1.25 if age >= 0.0 and age < 1.2 else 0.0
	_leaf.rotation.y = lerp_angle(_leaf.rotation.y, open, clampf(delta * 8.0, 0.0, 1.0))


## Where a visitor stands when they come back out: just in front of the door.
func out_transform() -> Transform3D:
	var facing := global_basis.z
	facing.y = 0.0
	var at := global_position + facing.normalized() * 1.4 + Vector3(0.0, 0.1, 0.0)
	return Transform3D(Basis(Vector3.UP, atan2(-facing.x, -facing.z)), at)


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
