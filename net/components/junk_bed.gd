extends Node3D

## Authority: host. The junk riding in Chefty's bed for Rusty's (docs/GAME.md
## "Rusty's Salvage & Pawn"; gap-specs shops chunk 5). Both Chefties (the legacy
## ride, net/components/ride.gd, and the drivable one, chefty_drive.gd) make one
## under their Body, so its space is the bed's and the junk rides along; they
## hand accept_junk, junk_count and unload_junk to it (critic C22's Chefty
## contract).
##
## Junk you throw or heave into the bed lands on the bed floor as a prop; once
## it settles there (net_prop.gd _try_load_junk) the host takes it in here: the
## prop goes, and the same model is drawn exactly where it came to rest, so
## nothing jumps. Up to Constants.TRUCK_JUNK_CAPACITY pieces, apart from the bags.
## At the store (the legacy ride arriving, or the drivable Chefty parking on the
## lot) the host unloads it: each piece hops out over the tailgate in turn, back
## row first, as a prop again, onto the asphalt where you haul it to Rusty's scale.
##
## Every peer draws the load from _rpc_junk (the whole list, on every change;
## at most eight entries), and a late joiner gets it from its Chefty's state request.

const _ShopModels = preload("res://props/shop_models.gd")
## The tailgate's line in the bed's space (props/vehicles.gd builds it at z 2.66).
const TAILGATE_Z: float = 2.66
## The load on every peer: [{type, value, at}], at is the piece's pose in the bed's space.
var junk: Array = []
## Host: unloading right now.
var _unloading: bool = false


## Named before it's added: its RPCs need the same path on every peer.
func _init() -> void:
	name = "JunkBed"


func count() -> int:
	return junk.size()


## Host: take in a piece of junk lying in the bed (a prop of kind "junk"): false
## when the bed already holds Constants.TRUCK_JUNK_CAPACITY.
func accept(prop: Node3D) -> bool:
	if not Net.is_host() or junk.size() >= Constants.TRUCK_JUNK_CAPACITY or _unloading:
		return false
	var type := str(prop.get("label"))
	if not _ShopModels.is_junk(type):
		return false
	var at := global_transform.affine_inverse() * prop.global_transform
	at.basis = at.basis.orthonormalized()
	junk.append({"type": type, "value": int(prop.get("value")), "at": at})
	_send()
	prop.queue_free()
	return true


## Host: everything in the bed hops out over the tailgate, one piece every
## Constants.JUNK_UNLOAD_GAP_SECONDS, back row first, as props in the world
## (world.spawn_junk). Each starts exactly where its model was.
func unload() -> void:
	if not Net.is_host() or junk.is_empty() or _unloading:
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("spawn_junk"):
		return
	_unloading = true
	while not junk.is_empty() and is_inside_tree():
		var index := _rearmost()
		var entry: Dictionary = junk[index]
		junk.remove_at(index)
		var pose: Transform3D = global_transform * (entry["at"] as Transform3D)
		var prop := world.call("spawn_junk", str(entry["type"]), pose.origin, int(entry["value"])) as RigidBody3D
		if prop != null:
			prop.global_transform = pose
			_let_through(prop)
			prop.linear_velocity = hop_velocity(entry["at"] as Transform3D, global_basis)
			prop.angular_velocity = global_basis * Vector3(-2.5, randf_range(-1.0, 1.0), 0.0)
			prop.set("_airborne", true)
		_send(pose.origin)
		await get_tree().create_timer(Constants.JUNK_UNLOAD_GAP_SECONDS).timeout
	_unloading = false


## The velocity (world space) that hops a piece of junk lying at `at` (bed
## space) up off the floor and out over the tailgate, landing behind the truck.
static func hop_velocity(at: Transform3D, bed_basis: Basis) -> Vector3:
	var lift := Constants.JUNK_UNLOAD_LIFT
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var rise := at.origin.y
	# How long until it comes back down to the ground (the bed's y 0).
	var flight := (lift + sqrt(lift * lift + 2.0 * gravity * rise)) / gravity
	# Pieces from the front of the bed land a little farther back, and each lands
	# out to its own side, so they don't end up in one heap.
	var land_z := Constants.JUNK_UNLOAD_LAND_Z + (TAILGATE_Z - at.origin.z) * 0.3
	var back := (land_z - at.origin.z) / maxf(flight, 0.1)
	var across := at.origin.x * Constants.JUNK_UNLOAD_SPREAD / maxf(flight, 0.1)
	return bed_basis * Vector3(across, lift, back)


## The velocity (world space) that heaves a piece of junk from your hands at
## `from` into the middle of a bed whose pose is `bed`, landing in about
## Constants.JUNK_HEAVE_SECONDS.
static func heave_velocity(from: Vector3, bed: Transform3D) -> Vector3:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var target := bed * Vector3(0.0, 1.1, 0.75)
	var flight := Constants.JUNK_HEAVE_SECONDS
	var flat := Vector3(target.x - from.x, 0.0, target.z - from.z) / flight
	var up := (target.y - from.y + 0.5 * gravity * flight * flight) / flight
	return flat + Vector3.UP * up


## The piece nearest the tailgate (+Z in the bed's space).
func _rearmost() -> int:
	var best := 0
	for index: int in junk.size():
		if ((junk[index] as Dictionary)["at"] as Transform3D).origin.z > ((junk[best] as Dictionary)["at"] as Transform3D).origin.z:
			best = index
	return best


## A hopping piece passes through the truck's walls for the start of its hop
## (its arc clears the tailgate; the walls would snag a corner of its box).
func _let_through(prop: RigidBody3D) -> void:
	var solid := _truck_solid()
	if solid == null:
		return
	prop.add_collision_exception_with(solid)
	get_tree().create_timer(Constants.JUNK_UNLOAD_THROUGH_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(prop) and is_instance_valid(solid):
			prop.remove_collision_exception_with(solid)
	)


func _truck_solid() -> PhysicsBody3D:
	var look := get_parent().get_node_or_null("TruckLook") if get_parent() != null else null
	return look.get_node_or_null("Solid") as PhysicsBody3D if look != null else null


## Host: the load to everyone (and where a piece just hopped out, for its sound).
func _send(hopped_at: Vector3 = Vector3.INF) -> void:
	if multiplayer.multiplayer_peer == null:
		_rpc_junk(_wire(), hopped_at)
		return
	_rpc_junk.rpc(_wire(), hopped_at)


## Host: a late joiner's copy of the load.
func send_to(peer_id: int) -> void:
	if Net.is_host() and multiplayer.multiplayer_peer != null:
		_rpc_junk.rpc_id(peer_id, _wire(), Vector3.INF)


func _wire() -> Array:
	var out: Array = []
	for entry: Dictionary in junk:
		out.append([str(entry["type"]), int(entry["value"]), entry["at"]])
	return out


## Every peer: the load as it is now. The models are redrawn whole (eight at
## most, their meshes cached), each exactly where its piece lies in the bed.
@rpc("authority", "call_local", "reliable")
func _rpc_junk(list: Array, hopped_at: Vector3) -> void:
	if not Net.is_host():
		junk = []
		for item: Variant in list:
			var parts: Array = item
			junk.append({"type": str(parts[0]), "value": int(parts[1]), "at": parts[2] as Transform3D})
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for entry: Dictionary in junk:
		var model := _ShopModels.junk(str(entry["type"]))
		model.transform = entry["at"]
		add_child(model)
		# Physics interpolation would slide a fresh model in from the bed's origin.
		model.reset_physics_interpolation()
	if hopped_at.is_finite():
		var sfx := get_tree().get_first_node_in_group("sfx")
		if sfx != null:
			sfx.call("play_at", "whoosh", hopped_at)
