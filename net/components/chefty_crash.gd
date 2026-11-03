extends Node

## Authority: host decides; every peer plays it. Chefty's crash comedy and what
## its driving does to the town (driving chunk C3, docs/GAME.md "Crash comedy";
## docs/DECISIONS.md "Chefty's crashes come from one host event"). A child of the
## drivable Chefty (World/Rides/Chefty/Crash), made in code on every peer, so its
## RPCs have the same path everywhere.
##
## The host checks every tick of the sim (chefty_drive.gd calls host_after_step):
## - a crash (Chefty losing more than CHEFTY_CRASH_MIN_SPEED into something
##   solid): bags fly out of the bed (real leaf bags, their value kept), a hard
##   one throws the bed riders out (the thrown-player path), every crash dents it
##   (up to CHEFTY_MAX_DENTS, each slower), and a very hard one barrel-rolls it on
##   screen with the horn stuck on. One reliable _rpc_crash tells every peer.
## - a drift spills a bag now and then; the Chefty Net halves every spill.
## - anyone standing in its way at speed is Chefty'd (_rpc_runover).
## - loose props it rolls into are shoved (net_prop.gd host_vehicle_push).
## - leaf piles in the job yard get plowed (leaf_field.gd host_plow).
## - parked on the homeowner's lawn, or honking in their yard, they yell (and the
##   horn adds heat).
## - mailboxes it flattens add heat (from TownMap's data: the host may have no
##   town to look at). Every peer knocks over its own drawn mailboxes and bins
##   from where it draws Chefty: cosmetic, a local physics body each.
## Every peer: the barrel roll (tumble_offset(), applied to the drawn Body), the
## sounds, the rolling hubcap, and the Chefty Net over the bed.

const _Vehicles = preload("res://props/vehicles.gd")
const _NetLook = preload("res://props/chefty_net_look.gd")
const _TownDressing = preload("res://levels/town/town_dressing.gd")
const BAG_SCENE: PackedScene = preload("res://props/yard_prop.tscn")
const BAG_COLOR := Color(0.72, 0.48, 0.18, 1)

## The Chefty this belongs to (chefty_drive.gd).
var vehicle: Node3D

## Speed lost into something (m/s) below this in a tick is a scrape, not contact.
const CONTACT_SPEED: float = 0.3

## Host.
var _cool: float = 0.0
## Host: a hit being added up (-1 when none): how long, how much speed lost so
## far, the velocity going in, and the hardest tick's normal.
var _hit_age: float = -1.0
var _hit_sum: float = 0.0
var _hit_best: float = 0.0
var _hit_vel := Vector3.ZERO
var _hit_normal := Vector3.ZERO
var _horn_stuck: float = 0.0
var _rng := RandomNumberGenerator.new()
var _plow_left: float = 0.0
var _lawn_clock: float = 0.0
var _lawn_yelled: bool = false
var _horn_was: bool = false
var _horn_line_at: float = -INF
## Host: peer (or node instance id) -> when they were last Chefty'd (msec).
var _ran_over: Dictionary = {}
## Host: the town's mailboxes and bins [{at, mailbox}], and when each was last hit (s).
var _spots: Array = []
var _spots_built: bool = false
var _knocked: Dictionary = {}
var _spill_serial: int = 0

## Every peer: the barrel roll under way (-1 when not), and which way it rolls.
var _tumble_t: float = -1.0
var _tumble_sign: float = 1.0
## Every peer: knocked-over pieces lying about [{node, body, at}].
var _fallen: Array = []
var _restore_left: float = 0.0
var _net: Node3D
var _net_check: float = 0.0

## For tests and the probe (every peer's own view).
var crashes_seen: int = 0
var tumbles_seen: int = 0
var runovers_seen: int = 0
var runovers_me: int = 0
var spills_seen: int = 0
var knocks_seen: int = 0
## Host only.
var bags_spilled: int = 0
var riders_ejected: int = 0
var plowed: int = 0
var mailboxes_hit: int = 0
var last_crash: Dictionary = {}


func _ready() -> void:
	name = "Crash"
	_rng.randomize()


# ---------------------------------------------------------------- host

## Host, after every sim step that moved Chefty for real (not a warp):
## result is VehicleSim.step's, pre_vel the velocity it had going in, input the
## controls it drove on.
func host_after_step(result: Dictionary, pre_vel: Vector3, input: Dictionary, delta: float) -> void:
	_cool = maxf(_cool - delta, 0.0)
	_horn_stuck = maxf(_horn_stuck - delta, 0.0)
	_push_soft(result.get("hits", []) as Array, pre_vel)
	# A hit is spread over a tick or two (the tick it touches only loses the speed
	# it had left after reaching the wall): add them up until it's over.
	var impact := float(result.get("impact", 0.0))
	if impact > CONTACT_SPEED:
		if _hit_age < 0.0:
			_hit_age = 0.0
			_hit_sum = 0.0
			_hit_vel = pre_vel
			_hit_normal = result.get("impact_normal", Vector3.ZERO) as Vector3
			_hit_best = 0.0
		_hit_sum += impact
		if impact > _hit_best:
			_hit_best = impact
			_hit_normal = result.get("impact_normal", Vector3.ZERO) as Vector3
	if _hit_age >= 0.0:
		_hit_age += delta
		if impact <= CONTACT_SPEED or _hit_age >= Constants.CHEFTY_CRASH_GATHER_SECONDS:
			var total := _hit_sum
			_hit_age = -1.0
			if total >= Constants.CHEFTY_CRASH_MIN_SPEED and _cool <= 0.0:
				_crash(total, _hit_normal, _hit_vel)
	_drift_spill(input, delta)


## Host, every tick whatever moved Chefty (the sim, the autopilot, a warp): the
## run-overs, the plow, the lawn, the horn, the mailboxes.
func host_every_tick(delta: float, warping: bool) -> void:
	if warping:
		_lawn_clock = 0.0
		return
	_runovers()
	_plow(delta)
	_lawn(delta)
	_horn_heat(delta)
	_knock_host()


## Host: the horn is stuck on (a barrel roll).
func horn_stuck() -> bool:
	return _horn_stuck > 0.0


func _chassis() -> CharacterBody3D:
	return vehicle.get_node("Chassis") as CharacterBody3D


func _crash(impact: float, normal: Vector3, pre_vel: Vector3) -> void:
	_cool = Constants.CHEFTY_CRASH_COOLDOWN
	var chassis := _chassis()
	var flat_normal := Vector3(normal.x, 0.0, normal.z).normalized() if Vector3(normal.x, 0.0, normal.z).length() > 0.01 else -VehicleSim.forward_of(float(vehicle.call("yaw")))
	# Where it hit: the side of the truck the wall pushed back on.
	var at := chassis.global_position - flat_normal * Constants.CHEFTY_HALF_LENGTH + Vector3.UP * 1.0
	var dents := mini(int(vehicle.call("dents")) + 1, Constants.CHEFTY_MAX_DENTS)
	var tumble := impact >= Constants.CHEFTY_TUMBLE_SPEED
	# Bags first, then the riders, then the dent everyone hears: one crash.
	var count := maxi(1, int(floor((impact - Constants.CHEFTY_CRASH_MIN_SPEED) * Constants.CHEFTY_SPILL_PER_MPS + 0.5)))
	if has_net():
		count = int(floor(float(count) * Constants.CHEFTY_NET_SPILL_SHARE))
	var spilled := host_spill(count, pre_vel)
	var ejected := 0
	if impact >= Constants.CHEFTY_EJECT_SPEED:
		ejected = _eject_bed(pre_vel)
	if tumble:
		_horn_stuck = Constants.CHEFTY_HORN_STUCK_SECONDS
	vehicle.call("host_set_dents", dents)
	last_crash = {"impact": impact, "spilled": spilled, "ejected": ejected, "dents": dents, "tumble": tumble}
	print("[Chefty] crash at %.1f m/s: %d bags out, %d riders out, %d dents%s" % [impact, spilled, ejected, dents, ", barrel roll" if tumble else ""])
	_rpc_crash.rpc(at, impact, tumble, dents, -1.0 if _rng.randf() < 0.5 else 1.0)


## Host: count bags fly out of the bed (from the top of the heap), each a real
## leaf bag worth its share of the load (the bed's value goes down by exactly
## what flew out). carry is Chefty's velocity going in. Returns how many flew.
func host_spill(count: int, carry: Vector3, sideways: Vector3 = Vector3.ZERO) -> int:
	var taken: Array = vehicle.call("host_take_bags", count)
	if taken.is_empty():
		return 0
	var runtime := get_tree().get_first_node_in_group("runtime_props")
	var right := VehicleSim.right_of(float(vehicle.call("yaw")))
	for entry: Dictionary in taken:
		var bag := BAG_SCENE.instantiate() as RigidBody3D
		_spill_serial += 1
		bag.name = "Spill%d_%d" % [vehicle.get_instance_id() % 1000, _spill_serial]
		bag.set("kind", "leaf_bag")
		bag.set("color", BAG_COLOR)
		bag.set("label", "Leaf bag")
		bag.set("value", int(entry["value"]))
		if runtime == null:
			bag.free()
			continue
		runtime.add_child(bag, true)
		var spot: Transform3D = entry["xform"]
		bag.global_position = spot.origin + Vector3.UP * 0.35
		# Over the side rail the bag sat nearest (a drift throws them all to the
		# outside), a little of the truck's own speed, and up and out.
		var local_x := (spot.origin - (vehicle.call("bed_transform") as Transform3D).origin).dot(right)
		var out := sideways.normalized() if sideways.length() > 0.01 else right * (1.0 if local_x > 0.0 or (absf(local_x) < 0.1 and _rng.randf() < 0.5) else -1.0)
		var velocity := Vector3(carry.x, 0.0, carry.z) * Constants.CHEFTY_SPILL_CARRY * _rng.randf_range(0.7, 1.1) \
			+ Vector3.UP * Constants.CHEFTY_SPILL_UP * _rng.randf_range(0.85, 1.15) \
			+ out * Constants.CHEFTY_SPILL_SIDE * _rng.randf_range(0.75, 1.25)
		bag.call("host_spill", velocity, Constants.CHEFTY_SPILL_NO_CATCH)
	bags_spilled += taken.size()
	return taken.size()


## Host: the riders in the bed go flying (the thrown-player path: they land in a
## heap with stars, or dive into a leaf pile).
func _eject_bed(pre_vel: Vector3) -> int:
	# On a depart() trip everyone's buckled in: they arrive together, in a zone.
	if bool(vehicle.call("is_riding")):
		return 0
	var right := VehicleSim.right_of(float(vehicle.call("yaw")))
	var riders: PackedInt32Array = vehicle.call("riders")
	var count := 0
	for seat: int in range(_Vehicles.CHEFTY_CAB_SEATS, riders.size()):
		var peer_id := riders[seat]
		if peer_id == 0:
			continue
		var side := signf(_Vehicles.CHEFTY_SEATS[seat].x)
		var velocity := Vector3(pre_vel.x, 0.0, pre_vel.z) * Constants.CHEFTY_EJECT_SHARE + Vector3.UP * Constants.CHEFTY_EJECT_UP + right * side * Constants.CHEFTY_EJECT_SIDE * _rng.randf_range(0.5, 1.0)
		vehicle.call("host_eject", peer_id, velocity)
		count += 1
	riders_ejected += count
	return count


## Host: a drift fast enough shakes a bag loose now and then, out the far side.
func _drift_spill(input: Dictionary, delta: float) -> void:
	if not bool(input.get("handbrake", false)) or int(vehicle.call("bag_count")) <= 0:
		return
	var state: Dictionary = vehicle.call("sim_state")
	var vel: Vector3 = state.get("vel", Vector3.ZERO)
	if Vector2(vel.x, vel.z).length() < Constants.CHEFTY_DRIFT_SPILL_SPEED or float(state.get("slip", 0.0)) < Constants.CHEFTY_DRIFT_SPILL_SLIP:
		return
	var chance := Constants.CHEFTY_DRIFT_SPILL_CHANCE * delta * (Constants.CHEFTY_NET_SPILL_SHARE if has_net() else 1.0)
	if _rng.randf() >= chance:
		return
	var right := VehicleSim.right_of(float(state.get("yaw", 0.0)))
	var sliding := right * signf(vel.dot(right))
	host_spill(1, vel, sliding)


## Host: loose things it rolled into are shoved off its bumper; a NICE BOY it hits
## is knocked flat like a bonk (and that's heat).
func _push_soft(hits: Array, pre_vel: Vector3) -> void:
	for hit: Variant in hits:
		if not hit is Dictionary or not bool((hit as Dictionary).get("soft", false)):
			continue
		var collider: Variant = (hit as Dictionary).get("collider")
		if not collider is Node3D or not is_instance_valid(collider):
			continue
		var node := collider as Node3D
		var push := Vector3(pre_vel.x, 0.0, pre_vel.z) * Constants.CHEFTY_PUSH_SHARE + Vector3.UP * Constants.CHEFTY_PUSH_UP
		if node.has_method("host_vehicle_push"):
			node.call("host_vehicle_push", push)
		elif node.is_in_group("crew") and node.has_method("on_bonked") and Vector2(pre_vel.x, pre_vel.z).length() >= Constants.CHEFTY_RUNOVER_SPEED:
			_hit(node, push, true)


## Host: whoever's in front of the bumper (behind the tailgate, backing up) at
## speed is Chefty'd: bonked flying, heavy. Riders, the hidden, and anyone
## already flying are left alone.
func _runovers() -> void:
	var state: Dictionary = vehicle.call("sim_state")
	var vel: Vector3 = state.get("vel", Vector3.ZERO)
	var speed := Vector2(vel.x, vel.z).length()
	if speed < Constants.CHEFTY_RUNOVER_SPEED:
		return
	var yaw := float(state.get("yaw", 0.0))
	var forward := VehicleSim.forward_of(yaw)
	var ahead := vel.dot(forward) >= 0.0
	var origin := _chassis().global_position
	var to_local := Basis(Vector3.UP, yaw).inverse()
	var now := Time.get_ticks_msec()
	var targets: Array[Node] = get_tree().get_nodes_in_group("players")
	targets.append_array(get_tree().get_nodes_in_group("crew"))
	for node: Node in targets:
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var key := body.get_instance_id()
		if now - int(_ran_over.get(key, -100000)) < int(Constants.CHEFTY_RUNOVER_COOLDOWN * 1000.0):
			continue
		if body.is_in_group("players"):
			var peer_id := body.name.to_int()
			if int(vehicle.call("seat_of", peer_id)) >= 0 or bool(body.get("thrown")) or int(body.get("carried_by")) != 0:
				continue
			if bool(body.call("is_hidden")) or bool(body.get("in_pile")):
				continue
		var local := to_local * (body.global_position - origin)
		if absf(local.y) > 2.5 or absf(local.x) > Constants.CHEFTY_HALF_WIDTH + Constants.CHEFTY_RUNOVER_SIDE:
			continue
		var reach := Constants.CHEFTY_HALF_LENGTH + Constants.CHEFTY_RUNOVER_REACH
		# The face it's driving into, and the body behind it.
		var hit := (local.z >= -reach and local.z <= 0.5) if ahead else (local.z <= reach and local.z >= -0.5)
		if not hit:
			continue
		_ran_over[key] = now
		var right := VehicleSim.right_of(yaw)
		var away := right * (1.0 if local.x >= 0.0 else -1.0)
		var push := Vector3(vel.x, 0.0, vel.z) * Constants.CHEFTY_RUNOVER_SHARE + Vector3.UP * Constants.CHEFTY_RUNOVER_UP + away * 2.0
		_hit(body, push, body.is_in_group("crew"))


func _hit(body: Node3D, push: Vector3, crew: bool) -> void:
	_ran_over[body.get_instance_id()] = Time.get_ticks_msec()
	_rpc_runover.rpc(get_path_to(body), push)
	if crew:
		var heat := get_tree().get_first_node_in_group("heat")
		if heat != null:
			heat.call("add", Constants.HEAT_CREW_BONK, "chefty_crew")


## Host: rolling through the job yard plows its leaf piles.
func _plow(delta: float) -> void:
	_plow_left -= delta
	if _plow_left > 0.0:
		return
	_plow_left = Constants.CHEFTY_PLOW_SECONDS
	var state: Dictionary = vehicle.call("sim_state")
	var vel: Vector3 = state.get("vel", Vector3.ZERO)
	if Vector2(vel.x, vel.z).length() < Constants.CHEFTY_PLOW_MIN_SPEED:
		return
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field == null or not field.has_method("host_plow"):
		return
	var yaw := float(state.get("yaw", 0.0))
	var forward := VehicleSim.forward_of(yaw)
	var going := forward if vel.dot(forward) >= 0.0 else -forward
	var bumper := _chassis().global_position + going * (Constants.CHEFTY_HALF_LENGTH - 0.6)
	plowed += int(field.call("host_plow", bumper, going, Constants.CHEFTY_PLOW_WIDTH, Constants.CHEFTY_PLOW_STRENGTH))


## The loaded job yard's LotZone, or null.
func _lot_zone() -> Node3D:
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return null
	var slot := world.get_node_or_null("%LotSlot")
	if slot == null or slot.get_child_count() == 0:
		return null
	return world.get_node_or_null("LotZone") as Node3D


func _homeowner() -> Node:
	return get_tree().get_first_node_in_group("homeowner")


## Host: parked on the job yard's lawn (inside the yard, off the drive) long
## enough, the homeowner comes out yelling, and that costs a mood step. Moving it
## off the lawn and back on again does it again.
func _lawn(delta: float) -> void:
	var lot := _lot_zone()
	if lot == null:
		_lawn_clock = 0.0
		_lawn_yelled = false
		return
	var local := lot.global_transform.affine_inverse() * _chassis().global_position
	var yard := Rect2(-Constants.PAD_HALF, -Constants.PAD_HALF, Constants.PAD_HALF * 2.0, Constants.PAD_HALF * 2.0)
	var on_drive := absf(local.x) < Constants.CHEFTY_DRIVE_HALF_WIDTH and local.z > 2.0
	var on_lawn := yard.has_point(Vector2(local.x, local.z)) and not on_drive
	if not on_lawn:
		_lawn_clock = 0.0
		_lawn_yelled = false
		return
	if float(vehicle.call("speed")) > Constants.CHEFTY_PARK_SPEED:
		_lawn_clock = 0.0
		return
	_lawn_clock += delta
	if _lawn_clock >= Constants.CHEFTY_LAWN_PARK_SECONDS and not _lawn_yelled:
		_lawn_yelled = true
		var owner_node := _homeowner()
		if owner_node != null and owner_node.has_method("host_grumble"):
			owner_node.call("host_grumble", "lawn_park", true)


## Host: honking at the job yard: heat while it's held, and the homeowner lets you
## know they've noticed.
func _horn_heat(delta: float) -> void:
	var on := bool(vehicle.call("horn_on"))
	var started := on and not _horn_was
	_horn_was = on
	if not on:
		return
	var lot := _lot_zone()
	if lot == null:
		return
	var at := _chassis().global_position
	if Vector2(at.x - lot.global_position.x, at.z - lot.global_position.z).length() > Constants.CHEFTY_HORN_YARD_METERS:
		return
	var heat := get_tree().get_first_node_in_group("heat")
	if heat != null:
		heat.call("add", Constants.CHEFTY_HORN_HEAT_PER_SECOND * delta, "horn")
	var now := Net.server_time()
	if started and now - _horn_line_at >= Constants.CHEFTY_HORN_LINE_COOLDOWN:
		_horn_line_at = now
		var owner_node := _homeowner()
		if owner_node != null and owner_node.has_method("host_grumble"):
			owner_node.call("host_grumble", "horn", false)


## Every mailbox and bin in the town, from TownMap (the same places the town's
## dressing puts them, levels/town/town_dressing.gd _curbside).
static func knock_spots() -> Array:
	var out: Array = []
	var places: Array = []
	for house_id: int in TownMap.house_count():
		places.append(TownMap.yard_transform(house_id))
	for slot: Dictionary in TownMap.dressing_slots():
		places.append(slot["xform"])
	for index: int in places.size():
		var xform: Transform3D = places[index]
		out.append({"at": xform * _TownDressing.MAILBOX_AT, "mailbox": true})
		if index % 2 == 0:
			out.append({"at": xform * _TownDressing.BIN_AT, "mailbox": false})
	return out


## Host: a mailbox Chefty flattens draws attention (HEAT_MAILBOX).
func _knock_host() -> void:
	if not TownMap.enabled(get_tree()):
		return
	if not _spots_built:
		_spots_built = true
		_spots = knock_spots()
	var state: Dictionary = vehicle.call("sim_state")
	var vel: Vector3 = state.get("vel", Vector3.ZERO)
	if Vector2(vel.x, vel.z).length() < Constants.CHEFTY_KNOCK_MIN_SPEED:
		return
	var origin := _chassis().global_position
	var to_local := Basis(Vector3.UP, float(state.get("yaw", 0.0))).inverse()
	var now := Net.server_time()
	for index: int in _spots.size():
		var at: Vector3 = (_spots[index] as Dictionary)["at"]
		if absf(at.x - origin.x) > 5.0 or absf(at.z - origin.z) > 5.0:
			continue
		if not _in_footprint(to_local * (at - origin)):
			continue
		if now - float(_knocked.get(index, -INF)) < Constants.CHEFTY_KNOCK_RESTORE_SECONDS:
			continue
		_knocked[index] = now
		if bool((_spots[index] as Dictionary)["mailbox"]):
			mailboxes_hit += 1
			var heat := get_tree().get_first_node_in_group("heat")
			if heat != null:
				heat.call("add", Constants.HEAT_MAILBOX, "mailbox")


static func _in_footprint(local: Vector3) -> bool:
	return absf(local.x) <= Constants.CHEFTY_HALF_WIDTH + Constants.CHEFTY_KNOCK_PAD and absf(local.z) <= Constants.CHEFTY_HALF_LENGTH + Constants.CHEFTY_KNOCK_PAD


## Whether the crew owns the Chefty Net (World/Shops crew_owned; every peer).
func has_net() -> bool:
	var shops := get_tree().get_first_node_in_group("shops")
	return shops != null and shops.has_method("owns") and bool(shops.call("owns", 0, "chefty_net"))


# ---------------------------------------------------------------- every peer

## Every physics tick on every peer, before Chefty's body is drawn: the barrel
## roll moves on, the drawn mailboxes it passes go flying, and the net shows.
func physics(delta: float) -> void:
	if _tumble_t >= 0.0:
		_tumble_t += delta / Constants.CHEFTY_TUMBLE_SECONDS
		if _tumble_t >= 1.0:
			_tumble_t = -1.0
	_knock_local()
	_restore_left -= delta
	if _restore_left <= 0.0:
		_restore_left = 1.0
		_restore_fallen()
	_net_check -= delta
	if _net_check <= 0.0:
		_net_check = 0.5
		_show_net()


## The drawn body's offset for the barrel roll (identity when not rolling): a
## hop, and a full turn about its length through its middle.
func tumble_offset() -> Transform3D:
	if _tumble_t < 0.0:
		return Transform3D.IDENTITY
	var t := clampf(_tumble_t, 0.0, 1.0)
	# Up fast, a hang at the top, down hard: the turn follows the same curve.
	var spin := smoothstep(0.0, 1.0, t)
	var hop := Constants.CHEFTY_TUMBLE_HOP * sin(PI * t)
	var pivot := Vector3(0.0, Constants.CHEFTY_TUMBLE_PIVOT_Y, 0.0)
	return Transform3D(Basis.IDENTITY, pivot + Vector3.UP * hop) * Transform3D(Basis(Vector3.BACK, TAU * spin * _tumble_sign), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)


func is_tumbling() -> bool:
	return _tumble_t >= 0.0


## Every peer: the drawn mailboxes and bins Chefty's drawn body runs through fly.
func _knock_local() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var speed := float(vehicle.call("speed"))
	if speed < Constants.CHEFTY_KNOCK_MIN_SPEED:
		return
	var body: Transform3D = vehicle.call("body_transform")
	var flat := Transform3D(Basis(Vector3.UP, float(vehicle.call("yaw"))), body.origin)
	var to_local := flat.affine_inverse()
	for node: Node in get_tree().get_nodes_in_group("town_knockables"):
		var piece := node as Node3D
		if piece == null or not piece.visible:
			continue
		var at := piece.global_position
		if absf(at.x - body.origin.x) > 5.0 or absf(at.z - body.origin.z) > 5.0:
			continue
		if not _in_footprint(to_local * at):
			continue
		_knock_over(piece)


## One mailbox or bin goes flying: the drawn one hides, and a copy in a physics
## body of its own (nothing collides with it, it lands on the ground) takes off
## with Chefty's speed, spinning.
func _knock_over(piece: Node3D) -> void:
	knocks_seen += 1
	var mailbox := str(piece.get_meta("kind", "")) == "mailbox"
	var size := Vector3(0.45, 1.45, 0.66) if mailbox else Vector3(0.66, 1.1, 0.76)
	var flier := RigidBody3D.new()
	flier.name = "Knocked%d" % knocks_seen
	flier.collision_layer = 0
	flier.collision_mask = 1
	flier.mass = 6.0 if mailbox else 9.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	flier.add_child(shape)
	var copy := piece.duplicate(0) as Node3D
	copy.transform = Transform3D.IDENTITY
	copy.visible = true
	for child: Node in piece.get_children():
		copy.add_child(child.duplicate())
	flier.add_child(copy)
	var holder := piece.get_parent()
	holder.add_child(flier)
	flier.global_transform = piece.global_transform
	piece.visible = false
	var vel: Vector3 = vehicle.call("drawn_velocity")
	var right := VehicleSim.right_of(float(vehicle.call("yaw")))
	var side := right * signf((piece.global_position - vehicle.call("body_position")).dot(right))
	flier.linear_velocity = Vector3(vel.x, 0.0, vel.z) * Constants.CHEFTY_KNOCK_CARRY + Vector3.UP * Constants.CHEFTY_KNOCK_UP + side * 1.5
	flier.angular_velocity = Vector3(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-3.0, 3.0), _rng.randf_range(-7.0, 7.0))
	_fallen.append({"node": piece, "body": flier, "at": Time.get_ticks_msec()})
	_play_at("bonk", piece.global_position + Vector3.UP)


## Knocked-over pieces stand back up once nobody's been near for a while, out
## of sight: the town fixes it while you're not looking.
func _restore_fallen() -> void:
	if _fallen.is_empty():
		return
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	var now := Time.get_ticks_msec()
	for index: int in range(_fallen.size() - 1, -1, -1):
		var entry: Dictionary = _fallen[index]
		var piece := entry["node"] as Node3D
		var flier := entry["body"] as Node3D
		if not is_instance_valid(piece):
			if is_instance_valid(flier):
				flier.queue_free()
			_fallen.remove_at(index)
			continue
		if now - int(entry["at"]) < int(Constants.CHEFTY_KNOCK_RESTORE_SECONDS * 1000.0):
			continue
		var near := INF
		if camera != null:
			near = minf(camera.global_position.distance_to(piece.global_position), flier.global_position.distance_to(camera.global_position) if is_instance_valid(flier) else INF)
		if near < Constants.CHEFTY_KNOCK_RESTORE_METERS:
			continue
		if is_instance_valid(flier):
			flier.queue_free()
		piece.visible = true
		_fallen.remove_at(index)


## The Chefty Net over the bed, once the crew owns it.
func _show_net() -> void:
	var owned := has_net()
	var body := vehicle.get_node_or_null("Body") as Node3D
	if body == null:
		return
	if not owned:
		if _net != null:
			_net.queue_free()
			_net = null
		return
	if _net == null:
		_net = _NetLook.new()
		body.add_child(_net)
	_net.call("show_over", int(vehicle.call("bag_count")))


## The hubcap that rolls off at the second dent: a chrome disc rolling away from
## the front right wheel, local to this peer, gone after a while.
func _roll_hubcap() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var body: Transform3D = vehicle.call("body_transform")
	var cap := RigidBody3D.new()
	cap.name = "Hubcap"
	cap.collision_layer = 0
	cap.collision_mask = 1
	cap.mass = 1.0
	var shape := CollisionShape3D.new()
	var disc := CylinderShape3D.new()
	disc.radius = _Vehicles.HUBCAP_RADIUS
	disc.height = 0.06
	shape.shape = disc
	# The cylinder stands on Y; the hubcap's axis is X.
	shape.rotation = Vector3(0.0, 0.0, PI * 0.5)
	cap.add_child(shape)
	cap.add_child(_Vehicles.stylized(_Vehicles.hubcap_mesh()))
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	world.add_child(cap)
	var yaw := float(vehicle.call("yaw"))
	var right := VehicleSim.right_of(yaw)
	var forward := VehicleSim.forward_of(yaw)
	# Off the wheel and away, out to the side and back the way it came, rolling
	# on its edge: its axle across the way it rolls.
	var away := (right - forward * 0.8).normalized()
	var axle := away.cross(Vector3.UP).normalized()
	cap.global_transform = Transform3D(Basis(axle, Vector3.UP, axle.cross(Vector3.UP)), body * (_Vehicles.HUBCAP_AT + Vector3(0.08, 0.0, 0.0)))
	var vel: Vector3 = vehicle.call("drawn_velocity")
	cap.linear_velocity = away * Constants.CHEFTY_HUBCAP_SPEED + Vector3(vel.x, 0.0, vel.z) * 0.3 + Vector3.UP * 0.8
	cap.angular_velocity = Vector3.UP.cross(away) * (Constants.CHEFTY_HUBCAP_SPEED / _Vehicles.HUBCAP_RADIUS)
	get_tree().create_timer(Constants.CHEFTY_HUBCAP_SECONDS).timeout.connect(func() -> void:
		if not is_instance_valid(cap):
			return
		var tween := cap.create_tween()
		tween.tween_property(cap, "scale", Vector3.ONE * 0.01, 0.4)
		tween.tween_callback(cap.queue_free))


func _play_at(id: String, at: Vector3) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", id, at)


## For the probe and drive_test, this peer's view.
func report() -> Dictionary:
	return {
		"crashes_seen": crashes_seen, "tumbles_seen": tumbles_seen, "runovers_seen": runovers_seen,
		"runovers_me": runovers_me, "spills_seen": spills_seen, "knocks_seen": knocks_seen,
		"bags_spilled": bags_spilled, "riders_ejected": riders_ejected, "plowed": plowed,
		"mailboxes_hit": mailboxes_hit, "last_crash": last_crash.duplicate(),
	}


# ---------------------------------------------------------------- RPCs

## Every peer: Chefty hit something at strength m/s at `at`. The sound (crash, or
## crash_big for one that throws riders), its new dent count (the logo letters,
## the bumper, the hubcap rolling off at the second), and the barrel roll.
@rpc("authority", "call_local", "reliable")
func _rpc_crash(at: Vector3, strength: float, tumble: bool, dents: int, roll_sign: float) -> void:
	crashes_seen += 1
	var before := int(vehicle.call("dents"))
	vehicle.call("apply_dents", dents)
	_play_at("crash_big" if strength >= Constants.CHEFTY_EJECT_SPEED else "crash", at)
	if before < 2 and dents >= 2:
		_roll_hubcap()
	if tumble:
		tumbles_seen += 1
		_tumble_t = 0.0
		_tumble_sign = roll_sign
	vehicle.emit_signal("crashed", strength, at)


## Every peer: someone was Chefty'd (or a NICE BOY was). Everyone sees the flop
## and hears it; the target's own peer is flung (player.gd on_bonked).
@rpc("authority", "call_local", "reliable")
func _rpc_runover(target: NodePath, push: Vector3) -> void:
	var body := get_node_or_null(target) as Node3D
	if body == null:
		return
	runovers_seen += 1
	if body.is_in_group("players") and body.name.to_int() == Net.local_peer_id():
		runovers_me += 1
	if body.has_method("on_bonked"):
		body.call("on_bonked", push, "heavy")
	_play_at("bonk", body.global_position + Vector3.UP)


## Every peer: bags just flew out of the bed (the counts are the bed's new ones).
func note_spill(at: Vector3) -> void:
	spills_seen += 1
	_play_at("bag_spill", at)
