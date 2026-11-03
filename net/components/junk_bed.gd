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
	# A haggle's result rides along (host-only; the wire carries type, value, pose).
	var shops := get_tree().get_first_node_in_group("shops")
	var haggle := float(shops.call("host_take_haggle", prop)) if shops != null else 1.0
	junk.append({"type": type, "value": int(prop.get("value")), "at": at, "haggle": haggle})
	_send()
	prop.queue_free()
	return true


## Host, loading a save: last session's bed load back in the bed, laid in
## Constants.JUNK_BED_SPOTS on its floor ([{type, value, haggle?}]).
func restore(entries: Array) -> void:
	if not Net.is_host():
		return
	for entry: Dictionary in entries:
		if junk.size() >= mini(Constants.TRUCK_JUNK_CAPACITY, Constants.JUNK_BED_SPOTS.size()):
			break
		var spot: Vector3 = Constants.JUNK_BED_SPOTS[junk.size()]
		junk.append({"type": str(entry["type"]), "value": int(entry.get("value", 0)), "at": Transform3D(Basis.IDENTITY, spot), "haggle": float(entry.get("haggle", 1.0))})
	_send()


## The middle of the tailgate, in the world, on the ground (E here with junk in
## the bed unloads it, gap-specs critic C22).
func tailgate_point() -> Vector3:
	return global_transform * Vector3(0.0, 0.0, TAILGATE_Z)


## Whether this peer's player stands at the tailgate with junk in the bed to unload.
func can_unload_from(player: Node3D) -> bool:
	if player == null or junk.is_empty() or _unloading:
		return false
	var chefty := get_parent().get_parent() if get_parent() != null else null
	if chefty != null and chefty.has_method("junk_unload_allowed") and not bool(chefty.call("junk_unload_allowed")):
		return false
	var gate := tailgate_point()
	return Vector2(player.global_position.x - gate.x, player.global_position.z - gate.z).length() <= Constants.JUNK_TAILGATE_REACH


## The local player presses E at the tailgate: the host unloads the bed.
func request_unload() -> void:
	if Net.is_host():
		_host_request_unload(Net.local_peer_id())
	else:
		_rpc_request_unload.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_unload() -> void:
	if Net.is_host():
		_host_request_unload(multiplayer.get_remote_sender_id())


func _host_request_unload(peer_id: int) -> void:
	var player: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			player = node as Node3D
	if can_unload_from(player):
		unload()


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
			let_through(prop, Constants.JUNK_UNLOAD_THROUGH_SECONDS)
			prop.linear_velocity = hop_velocity(entry["at"] as Transform3D, global_basis, _landing_side())
			prop.angular_velocity = global_basis * Vector3(Constants.JUNK_UNLOAD_TUMBLE, randf_range(-Constants.JUNK_UNLOAD_YAW_SPIN, Constants.JUNK_UNLOAD_YAW_SPIN), 0.0)
			prop.set("_airborne", true)
			var shops := get_tree().get_first_node_in_group("shops")
			if shops != null:
				shops.call("host_keep_haggle", prop, float(entry.get("haggle", 1.0)))
		_send(pose.origin)
		await get_tree().create_timer(Constants.JUNK_UNLOAD_GAP_SECONDS).timeout
	_unloading = false


## Host: how far to one side (bed space x) the pieces land, clear of whoever
## stands behind the tailgate (the one who pressed E stands right where they'd
## land, and a tire landed on their feet and shoved them, rec_tailgate_1p
## frames 50-54): Constants.JUNK_UNLOAD_SIDE to the side away from them, 0 with
## nobody there.
func _landing_side() -> float:
	var inverse := global_transform.affine_inverse()
	var nearest := INF
	var their_x := 0.0
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body == null or not body.is_visible_in_tree():
			continue
		var local := inverse * body.global_position
		if local.z < TAILGATE_Z - 0.5 or local.z > Constants.JUNK_UNLOAD_LAND_Z + Constants.JUNK_UNLOAD_WATCH_BEYOND or absf(local.x) > Constants.JUNK_UNLOAD_SIDE + 1.0:
			continue
		if absf(local.x) < nearest:
			nearest = absf(local.x)
			their_x = local.x
	if nearest == INF:
		return 0.0
	return -Constants.JUNK_UNLOAD_SIDE if their_x > 0.0 else Constants.JUNK_UNLOAD_SIDE


## The velocity (world space) that hops a piece of junk lying at `at` (bed
## space) up off the floor and out over the tailgate, landing behind the truck
## (side meters over to one side, bed space x).
static func hop_velocity(at: Transform3D, bed_basis: Basis, side: float = 0.0) -> Vector3:
	var lift := Constants.JUNK_UNLOAD_LIFT
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var rise := at.origin.y
	# How long until it comes back down to the ground (the bed's y 0).
	var flight := (lift + sqrt(lift * lift + 2.0 * gravity * rise)) / gravity
	# Pieces from the front of the bed land a little farther back, and each lands
	# out to its own side, so they don't end up in one heap.
	var land_z := Constants.JUNK_UNLOAD_LAND_Z + (TAILGATE_Z - at.origin.z) * Constants.JUNK_UNLOAD_FRONT_SHARE
	var back := (land_z - at.origin.z) / maxf(flight, 0.1)
	var across := (at.origin.x * Constants.JUNK_UNLOAD_SPREAD + side) / maxf(flight, 0.1)
	return bed_basis * Vector3(across, lift, back)


## The velocity (world space) that heaves a piece of junk from your hands at
## `from` into the bed whose pose is `bed`, landing on Constants.JUNK_HEAVE_AIM:
## an arc whose top is Constants.JUNK_HEAVE_CLEARANCE over the bed's rail, so
## its base clears the tailgate or a side wall even from right behind it (a
## flatter heave from there hit the tailgate and fell back on you, rec_heave_1p
## frames 15-23).
static func heave_velocity(from: Vector3, bed: Transform3D) -> Vector3:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var target := bed * Constants.JUNK_HEAVE_AIM
	var rail := (bed * Vector3(0.0, Constants.BED_CATCH_RAIL_Y, 0.0)).y
	var top := maxf(rail + Constants.JUNK_HEAVE_CLEARANCE, maxf(from.y, target.y) + 0.1)
	var up := sqrt(2.0 * gravity * (top - from.y))
	var flight := up / gravity + sqrt(2.0 * (top - target.y) / gravity)
	var flat := Vector3(target.x - from.x, 0.0, target.z - from.z) / flight
	return flat + Vector3.UP * up


## How long a heave from `from` takes to reach the top of its arc (s): it
## passes through the truck's walls until then (let_through).
static func heave_rise_seconds(from: Vector3, bed: Transform3D) -> float:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	return heave_velocity(from, bed).y / gravity


## The piece nearest the tailgate (+Z in the bed's space).
func _rearmost() -> int:
	var best := 0
	for index: int in junk.size():
		if ((junk[index] as Dictionary)["at"] as Transform3D).origin.z > ((junk[best] as Dictionary)["at"] as Transform3D).origin.z:
			best = index
	return best


## A hopping (or heaved) piece passes through the truck's walls for the start
## of its arc, this long (its arc clears the rail; the walls would snag a
## corner of its tumbling box).
func let_through(prop: RigidBody3D, seconds: float) -> void:
	var solid := _truck_solid()
	if solid == null:
		return
	prop.add_collision_exception_with(solid)
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
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
