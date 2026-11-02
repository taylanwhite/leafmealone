extends Node3D

## Authority: host spawns players and the job lot. Geometry is the same on every peer.

const JOB_LOT: PackedScene = preload("res://levels/lots/lot_01.tscn")
const BAG_SCENE: PackedScene = preload("res://props/yard_prop.tscn")
const _PlayerDirector: Script = preload("res://net/player_director.gd")
const _Boarding: Script = preload("res://levels/boarding.gd")
const _SharedLook: Script = preload("res://levels/shared_look.gd")
const _StoreDressing = preload("res://levels/dressing/store_dressing.gd")
const _BorderDressing = preload("res://levels/dressing/border_dressing.gd")
const _Surroundings = preload("res://levels/dressing/surroundings.gd")
const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")
const _Pedestrians = preload("res://npcs/pedestrians.gd")
const _JobBoard = preload("res://levels/job_board.gd")
const _Cot = preload("res://props/cot.gd")
const _ToolTiers = preload("res://core/tool_tiers.gd")
## How long a swapped-out yard has to leave every peer before the picked one loads.
const LOT_SWAP_SECONDS: float = 0.4
const _Grass = preload("res://props/grass.gd")
const _StreetLife = preload("res://levels/dressing/street_life.gd")
const GRASS := Color(0.42, 0.52, 0.3)
const SAND := Color(0.78, 0.68, 0.5)
## Gap between players who share a spawn marker, in meters.
const SPAWN_SPACING: float = 1.4
## Spawn slots to check for a free one before giving up and sharing.
const SPAWN_SLOTS_TO_TRY: int = 16

## The connected town (true) or the legacy separate zones (false). The host picks
## it, and net/session_root.gd sets it from the spawn data before _ready, so it is
## the same on every peer and never changes for this world.
var town_map: bool = false

var _lots_loaded: int = 0
var _lot_swap_serial: int = 0
var _bag_serial: int = 0
## The town house whose yard the job site sits on, or -1 (legacy, or no site placed).
var _job_site_house: int = -1


func _ready() -> void:
	add_to_group("world")
	%RuntimeProps.add_to_group("runtime_props")
	_add_chefty()
	# The sun is set up by levels/shared_look.gd.
	var director := preload("res://net/run_events/director.gd").new()
	director.name = "RunDirector"
	add_child(director)
	var crossing := preload("res://net/border_return.gd").new()
	crossing.name = "BorderReturn"
	add_child(crossing)
	# In the connected town people walk and drive out of the store and the yard,
	# so only the border keeps its pad walls.
	if not town_map:
		_add_curb($StoreZone)
		_add_curb($LotZone)
	_add_curb($BorderZone)
	# Sound effects live at UIRoot/Audio/Sfx (audio/audio_root.gd), so menus have sound too.
	var ambience := preload("res://audio/ambience.gd").new()
	ambience.name = "Ambience"
	add_child(ambience)
	# The spine (docs/SPINE.md): the day's clock and the persistent town, before
	# the job board, which offers the town's requests.
	var clock := preload("res://net/day/day_clock.gd").new()
	clock.name = "DayClock"
	add_child(clock)
	var town := preload("res://net/town/town.gd").new()
	town.name = "Town"
	add_child(town)
	var hires := preload("res://net/crew/hires.gd").new()
	hires.name = "Hires"
	add_child(hires)
	# Every shop's buying, stock, and the crew's supplies (net/shops/shops.gd).
	var shops := preload("res://net/shops/shops.gd").new()
	shops.name = "Shops"
	add_child(shops)
	_add_cots()
	var board := preload("res://levels/job_board.gd").new()
	board.name = "JobBoard"
	add_child(board)
	var heat := preload("res://net/run_events/heat.gd").new()
	heat.name = "Heat"
	add_child(heat)
	var brawl := preload("res://net/components/brawl.gd").new()
	brawl.name = "Brawl"
	add_child(brawl)
	# The pockets (net/components/hotbar.gd): what's in whose slots, host-decided.
	var hotbar := preload("res://net/components/hotbar.gd").new()
	hotbar.name = "Hotbar"
	add_child(hotbar)
	_dress()
	_SharedLook.call("apply", self)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	if not Net.is_host():
		return
	# --all-tools: the host owns every tool this session, for tests and trying them out.
	if bool(Net.dev_options().get("all_tools")):
		Campaign.dev_grant_all_tools(Net.local_peer_id())
	# With the town, the yard loads when Chefty sets off (the ride covers the
	# build), so the board can change all day without swapping yards under anyone.
	# Tests that start on the lot, or pin a seed, still get theirs right away.
	if get_node_or_null("Town") == null or int(Net.dev_options().get("job_seed")) != 0 or str(Net.dev_options().get("start_zone")) == "lot":
		_load_job_lot()
	for peer_id: int in Net.peer_ids():
		_spawn_peer(peer_id)
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	Net.player_zone_changed.connect(_on_zone_changed)


## Chefty, made here on every peer at the same path (World/Rides/Chefty, which its
## RPCs need) before anything looks for it: the drivable one in the connected
## town (net/components/chefty_drive.gd), the server-clock ride in the legacy
## world (net/components/ride.gd).
func _add_chefty() -> void:
	if $Rides.has_node("Chefty"):
		return
	var script: Script = preload("res://net/components/chefty_drive.gd") if town_map else preload("res://net/components/ride.gd")
	var chefty := script.new() as Node3D
	chefty.name = "Chefty"
	$Rides.add_child(chefty)


## Cosmetic set dressing for each zone, the scenery around them, and the shared
## outline. Local on every peer. The angles keep each ride's route clear of trees:
## Chefty leaves the store east, arrives at the lot from the west, and the van
## leaves the lot northwest and arrives at the border from the southeast.
func _dress() -> void:
	_StoreDressing.dress($StoreZone)
	_BorderDressing.dress($BorderZone)
	if town_map:
		_dress_town()
	else:
		_dress_legacy()
	add_child(preload("res://levels/outline_pass.gd").new())
	# Every shop's site, keeper and hours sign, where Constants.SHOP_SITES puts
	# them (Marty behind the counter among them). Local on every peer: nothing
	# about them is shared.
	preload("res://levels/dressing/shop_sites.gd").dress(self)


## The connected town (net/town/town_map.gd, docs/GAME.md "Gutterford"): its
## colliders (the same on every peer), its dressing, and its houses. The store
## keeps its own dressing, grass, and walkers; the legacy lot street, the lot's
## surroundings, and the countryside drive aren't built, since the town is all
## of that.
func _dress_town() -> void:
	var colliders := preload("res://levels/town/town_colliders.gd").new()
	add_child(colliders)
	preload("res://levels/town/town_dressing.gd").dress(self)
	var streamer := preload("res://levels/town/town_streamer.gd").new()
	add_child(streamer)
	_StreetLife.dress_store($StoreZone)
	_Grass.plant($StoreZone, 70.0, 0.52, 11)
	_Pedestrians.populate($StoreZone, [
		[Vector3(21.4, 0.1, -140.0), Vector3(21.4, 0.1, 140.0)],
		[Vector3(32.6, 0.1, -140.0), Vector3(32.6, 0.1, 140.0)],
	], 7, 11)
	_Surroundings.dress($BorderZone, SAND, 33, false, [-PI * 0.25], "dirt")


func _dress_legacy() -> void:
	_Surroundings.dress($StoreZone, GRASS, 11, false, [0.0])
	_Surroundings.dress($LotZone, GRASS, 22, false, [PI * 0.75])
	_Neighborhood.dress($LotZone, 22)
	# People out for a walk on the sidewalks (lot street at z 21.3 and 32.7 in the
	# lot's space; the store's cross street at x 21.3 and 32.7).
	# Grass on every lawn around the yard and the store, short and sparse in the yard itself.
	_StreetLife.dress_lot($LotZone)
	_StreetLife.dress_store($StoreZone)
	_Grass.plant($LotZone, 70.0, 0.48, 22, Constants.PAD_HALF)
	_Grass.plant($StoreZone, 70.0, 0.52, 11)
	_Pedestrians.populate($LotZone, [
		[Vector3(-110.0, 0.1, 21.4), Vector3(110.0, 0.1, 21.4)],
		[Vector3(-110.0, 0.1, 32.6), Vector3(110.0, 0.1, 32.6)],
	], 9, 22)
	_Pedestrians.populate($StoreZone, [
		[Vector3(21.4, 0.1, -140.0), Vector3(21.4, 0.1, 140.0)],
		[Vector3(32.6, 0.1, -140.0), Vector3(32.6, 0.1, 140.0)],
	], 7, 11)
	_Surroundings.dress($BorderZone, SAND, 33, false, [-PI * 0.25], "dirt")
	# The drive from Homie Depot to the town passes country, not a void.
	preload("res://levels/dressing/countryside.gd").dress(self)


## The crew camp's cots by the store's side wall (props/cot.gd). Local on every
## peer: who's asleep is the day clock's business.
func _add_cots() -> void:
	for index: int in Constants.COT_SPOTS.size():
		var cot: Node3D = _Cot.new()
		cot.name = "Cot%d" % index
		cot.set("index", index)
		$StoreZone.add_child(cot)
		cot.position = Constants.COT_SPOTS[index]
	_Cot.dress_camp($StoreZone, Constants.COT_SPOTS)


## An invisible wall around the pad, so a bump cannot walk or jump off it.
## Each zone's dressing shows the edge (fences, hedges, the street curb).
func _add_curb(zone: Node3D) -> void:
	var curb := StaticBody3D.new()
	curb.name = "Curb"
	# Layer 3 holds people in (players and the crew mask it); thrown items fly over.
	curb.collision_layer = Constants.PAD_WALL_LAYER
	curb.collision_mask = 0
	zone.add_child(curb)
	var rect: Rect2 = Constants.PAD_RECTS.get(String(zone.name), Rect2(-20.0, -20.0, 40.0, 40.0))
	var thick := 0.8
	var height := 3.0
	var middle := rect.get_center()
	var spans: Array[Dictionary] = [
		{"at": Vector3(middle.x, height * 0.5, rect.end.y), "size": Vector3(rect.size.x + thick, height, thick)},
		{"at": Vector3(middle.x, height * 0.5, rect.position.y), "size": Vector3(rect.size.x + thick, height, thick)},
		{"at": Vector3(rect.end.x, height * 0.5, middle.y), "size": Vector3(thick, height, rect.size.y)},
		{"at": Vector3(rect.position.x, height * 0.5, middle.y), "size": Vector3(thick, height, rect.size.y)},
	]
	for span: Dictionary in spans:
		var shape := BoxShape3D.new()
		shape.size = span["size"]
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		shape_node.position = span["at"]
		curb.add_child(shape_node)



## Every peer. The connected town is being built in steps (driving chunks A to I);
## until then it plays like the legacy world with zones that can be walked into.
func is_town_map() -> bool:
	return town_map


## Every peer. Moves the one job site (LotZone, and everything yard-relative with
## it) onto a town house's yard, before that yard's lot loads. Yards are never
## rotated: site's basis stays the identity and the yard faces +Z. A no-op in
## the legacy world, where LotZone keeps its place.
func place_job_site(site: Transform3D, house_id: int) -> void:
	if not town_map:
		return
	# The slot the site leaves shows its house again; the one it takes hides its
	# house and colliders, since the job yard builds its own.
	if _job_site_house >= 0 and _job_site_house != house_id:
		_show_slot(_job_site_house, true)
	_job_site_house = house_id
	if house_id >= 0:
		_show_slot(house_id, false)
	var zone := $LotZone as Node3D
	zone.global_transform = Transform3D(Basis.IDENTITY, site.origin)
	zone.reset_physics_interpolation()


## A town slot's dressing house and colliders, on or off.
func _show_slot(house_id: int, on: bool) -> void:
	var colliders := get_node_or_null("TownColliders")
	if colliders != null:
		colliders.call("set_slot_enabled", house_id, on)
	var streamer := get_node_or_null("TownStreamer")
	if streamer != null:
		streamer.call("set_slot_hidden", house_id, not on)


## The town house the job site was placed on, or -1.
func job_site_house() -> int:
	return _job_site_house


## Host. Whether a player may be sent into zone by request (Net._apply_zone_request:
## the debug gates and bots). TOWN only exists in the connected town; there the
## LOT needs a loaded yard, or an automated or bot session, which gets one on demand.
func can_enter_zone(zone: Net.Zone) -> bool:
	match zone:
		Net.Zone.STORE, Net.Zone.BORDER:
			return true
		Net.Zone.LOT:
			if not town_map:
				return true
			return %LotSlot.get_child_count() > 0 or Net.is_automated() or bool(Net.dev_options().get("bot"))
		Net.Zone.TOWN:
			return town_map
		_:
			return false


## World position used when the host teleports a player into a zone.
func get_spawn_transform(zone: Net.Zone, spawn_marker: StringName, peer_id: int) -> Transform3D:
	var points := _spawn_points(zone)
	if spawn_marker != &"" and points.has_node(String(spawn_marker)):
		return points.get_node(String(spawn_marker)).global_transform
	var markers := points.get_children()
	if markers.is_empty():
		return points.global_transform
	# The first slot nobody is standing on, so nobody spawns inside someone else.
	# Peer ids are random, so a slot by id or by sorted order can collide.
	for slot: int in SPAWN_SLOTS_TO_TRY:
		var candidate := _slot_transform(markers, slot)
		if not _someone_near(candidate.origin, peer_id):
			return candidate
	return _slot_transform(markers, posmod(peer_id, markers.size()))


## Slot 0 is the first marker, then the next, then rows behind the markers.
func _slot_transform(markers: Array[Node], slot: int) -> Transform3D:
	var marker := (markers[slot % markers.size()] as Node3D).global_transform
	var row := floori(float(slot) / markers.size())
	marker.origin += marker.basis.z * SPAWN_SPACING * float(row)
	return marker


func _someone_near(point: Vector3, except_peer: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body == null or body.name == str(except_peer):
			continue
		if Vector2(body.global_position.x - point.x, body.global_position.z - point.z).length() < SPAWN_SPACING * 0.8:
			return true
	return false


func request_depart() -> void:
	if Net.is_host():
		_host_depart()
	else:
		_rpc_request_depart.rpc_id(1)


## Host only: the homeowner was paid. Settle the job and drive everyone home.
func finish_with_pay(paid: int, details: Dictionary = {}) -> void:
	if Net.is_host():
		_host_finish(float(paid), details)


func request_finish() -> void:
	if Net.is_host():
		_host_finish()
	else:
		_rpc_request_finish.rpc_id(1)


## Host only. Called by the truck when the path is done.
func on_ride_arrived(destination: int) -> void:
	if destination == Net.Zone.STORE:
		_free_lot()
	elif destination == Net.Zone.LOT and town_map:
		on_crew_arrived()
	elif destination == Net.Zone.LOT:
		# The homeowner's patience starts when the crew shows up, not at the store.
		Campaign.start_job_clock()
		# The hired hands hop off and get to work.
		var hires := get_node_or_null("Hires")
		if hires != null and Campaign.is_job_open():
			hires.call("spawn_on_lot")
	elif destination == Net.Zone.BORDER:
		var crossing := get_node_or_null("BorderReturn")
		var director := get_node_or_null("RunDirector")
		if crossing != null and director != null:
			crossing.call("begin", director.call("cohort_roster"), int(director.call("hazard_seed")))


## Host, the connected town. The crew got to the job's yard: a depart() trip
## arrived, or Chefty parked by its curb (chefty_drive.gd's arrival detection,
## however it was driven there). The homeowner's clock starts and the hired hands
## hop off to work, once per yard: parking there again changes nothing.
func on_crew_arrived() -> void:
	if not Net.is_host() or %LotSlot.get_child_count() == 0:
		return
	var lot := %LotSlot.get_child(0)
	if lot.has_meta("crew_arrived"):
		return
	lot.set_meta("crew_arrived", true)
	Campaign.start_job_clock()
	var hires := get_node_or_null("Hires")
	if hires != null and Campaign.is_job_open():
		hires.call("spawn_on_lot")


func _load_job_lot() -> void:
	if %LotSlot.get_child_count() > 0:
		return
	# Every job is a different yard asking for different work: the offer picked
	# on the job board (levels/job_board.gd), or --job-seed's for tests.
	var offer: Dictionary = $JobBoard.call("current")
	# The town decides where the crew can work; with no requests there's no yard.
	if offer.is_empty() and int(Net.dev_options().get("job_seed")) == 0 and get_node_or_null("Town") != null:
		return
	var lot := JOB_LOT.instantiate()
	# A new name for every yard loaded, so nothing meant for the last one lands on this one.
	_lots_loaded += 1
	lot.name = "Lot%d_%d" % [Campaign.current_lot_index(), _lots_loaded]
	if int(Net.dev_options().get("job_seed")) != 0 or offer.is_empty():
		var job_seed := int(Net.dev_options().get("job_seed"))
		if job_seed == 0:
			job_seed = randi_range(1, 2147483646)
		offer = _JobBoard.make_offer(job_seed)
	lot.set("job_seed", int(offer["seed"]))
	lot.set("tasks", offer["tasks"])
	lot.set("yard_size", int(offer.get("size", 1)))
	# A house in the town (net/town/town.gd) brings its regrowth and neighborhood.
	lot.set("mess", float(offer.get("mess", 1.0)))
	lot.set("hood", str(offer.get("hood", "")))
	lot.set_meta("offer", offer)
	%LotSlot.add_child(lot, true)
	Campaign.mark_job_open()
	var town := get_node_or_null("Town")
	if town != null and offer.has("house_id"):
		town.call("start_job", int(offer["house_id"]))
		_spawn_rival_signs(lot as Node3D, offer)
	_spawn_job_tools()
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null:
		telemetry.call("mark_job_start")
	var field := lot.get_node_or_null("LeafField")
	if field != null and field.has_signal("bag_requested") and not field.bag_requested.is_connected(_spawn_bag):
		field.bag_requested.connect(_spawn_bag)


func _free_lot() -> void:
	var hires := get_node_or_null("Hires")
	if hires != null:
		hires.call("despawn")
	for child: Node in %LotSlot.get_children():
		# Out of the slot now, so a new lot can take its name this frame.
		%LotSlot.remove_child(child)
		child.queue_free()
	_return_job_gas()
	for tool: Node in get_tree().get_nodes_in_group("job_tools"):
		tool.queue_free()
	# Back at the store: new jobs on the board.
	$JobBoard.call("refresh")


## True once the next job is set: Chefty is on the way, or someone's at the yard.
func job_locked() -> bool:
	var ride := get_node_or_null("Rides/Chefty")
	if ride != null and bool(ride.call("is_riding")):
		return true
	if not Net.players_in_zone(Net.Zone.LOT).is_empty():
		return true
	# The town's yard is waiting for the crew (in the van, crossing back) and
	# the job isn't paid: keep it, nobody swaps it out from a phone.
	return get_node_or_null("Town") != null and %LotSlot.get_child_count() > 0 and Campaign.is_job_open()


## Host only. The job board's pick changed while nobody's at the yard: swap the
## waiting yard for the picked one.
func reload_job_lot() -> void:
	if not Net.is_host() or job_locked() or %LotSlot.get_child_count() == 0:
		return
	# Already the picked yard with the same work: leave it be.
	var waiting := %LotSlot.get_child(0)
	var offer: Dictionary = $JobBoard.call("current")
	if offer.is_empty() or int(Net.dev_options().get("job_seed")) != 0:
		return
	if int(waiting.get("job_seed")) == int(offer["seed"]) and (waiting.get("tasks") as PackedStringArray) == (offer["tasks"] as PackedStringArray):
		return
	for child: Node in %LotSlot.get_children():
		%LotSlot.remove_child(child)
		child.queue_free()
	_return_job_gas()
	for tool: Node in get_tree().get_nodes_in_group("job_tools"):
		tool.queue_free()
	_lot_swap_serial += 1
	var serial := _lot_swap_serial
	await get_tree().create_timer(LOT_SWAP_SECONDS).timeout
	# Picked again meanwhile, or Chefty left and loaded it already: that one wins.
	if serial == _lot_swap_serial and %LotSlot.get_child_count() == 0:
		_load_job_lot()


## Host only. TurfMasters™ took clients on this street: their signs are stuck in
## this yard's front lawn, for the crew to pull up (net/town/town.gd).
func _spawn_rival_signs(lot: Node3D, offer: Dictionary) -> void:
	var count := int(offer.get("signs", 0))
	if count <= 0 or lot == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(offer["seed"]), "signs"])
	for index: int in count:
		var sign := BAG_SCENE.instantiate()
		sign.name = "TurfSign%d_%d" % [_lots_loaded, index]
		sign.set("kind", "turf_sign")
		sign.set("label", "TurfMasters™ sign")
		sign.set("color", Color(0.1, 0.55, 0.28))
		sign.add_to_group("job_tools")
		sign.add_to_group("turf_signs")
		sign.set_meta("hood", str(offer.get("hood", "")))
		%RuntimeProps.add_child(sign, true)
		# Out on the front lawn, either side of the driveway.
		var side := -1.0 if index % 2 == 0 else 1.0
		sign.global_position = lot.global_position + Vector3(side * rng.randf_range(4.0, 12.0), 0.6, rng.randf_range(10.0, 17.0))


## Host only. One of each tool the crew owns rides along, laid out by the truck,
## at the best tier anyone here owns. Chefty fills each gas tool's tank out of
## the crew's gas on the way (Constants.GAS_PER_TANK each), and a red gas can
## rides along with whatever spare gas there is (up to GAS_CAN_CARRY). Whatever
## is left in the tanks and the can goes back into the supply after the job
## (_return_job_gas), so the crew only pays for what it burned.
func _spawn_job_tools() -> void:
	var lot := %LotSlot.get_child(0) as Node3D if %LotSlot.get_child_count() > 0 else null
	if lot == null:
		return
	var shops := get_node_or_null("Shops")
	var index := 0
	for tool_id: String in Campaign.crew_tools():
		var tool := BAG_SCENE.instantiate()
		var tier := Campaign.crew_tool_tier(tool_id)
		tool.name = "Tool_%s_%d" % [tool_id, _lots_loaded]
		tool.set("kind", tool_id)
		tool.set("tier", tier)
		tool.set("label", _ToolTiers.tool_name(tool_id, tier))
		tool.set("color", Color(0.8, 0.8, 0.8))
		if _ToolTiers.is_gas_tool(tool_id):
			var filled := shops == null or bool(shops.call("consume", "gas", Constants.GAS_PER_TANK))
			tool.set("fuel", 100.0 if filled else 0.0)
		tool.add_to_group("job_tools")
		%RuntimeProps.add_child(tool, true)
		tool.global_position = _job_tool_spot(lot, index)
		index += 1
	if shops == null:
		return
	var spare := minf(float(shops.call("supply", "gas")), Constants.GAS_CAN_CARRY)
	if spare < Constants.GAS_CAN_MIN_GALLONS or not bool(shops.call("consume", "gas", spare)):
		return
	var can := BAG_SCENE.instantiate()
	can.name = "GasCan_%d" % _lots_loaded
	can.set("kind", "gas_can")
	can.set("water", _ToolTiers.can_water(spare))
	can.set("label", _ToolTiers.can_label(spare))
	can.set("color", Color(0.84, 0.14, 0.1))
	can.add_to_group("job_tools")
	can.add_to_group("gas_cans")
	%RuntimeProps.add_child(can, true)
	can.global_position = _job_tool_spot(lot, index)


## Where the index-th thing that rides along is laid out: rows of three by the truck.
func _job_tool_spot(lot: Node3D, index: int) -> Vector3:
	return lot.global_position + Vector3(-5.5 - float(index % 3) * 1.4, 0.6, 13.5 + float(index / 3) * 1.6)


## Host only. The job's over (or swapped out): the gas left in the tools' tanks
## and in the gas can goes back into the crew's supply before they're freed.
func _return_job_gas() -> void:
	var shops := get_node_or_null("Shops")
	if shops == null or not Net.is_host():
		return
	# Saves made meanwhile already counted this gas (Shops.supplies_to_save), so
	# the save doesn't change here and needs no write of its own.
	var gallons := _ToolTiers.gas_out(get_tree().get_nodes_in_group("job_tools"))
	if gallons > 0.0:
		shops.call("add_supply", "gas", gallons)


func _host_depart() -> void:
	var ride := get_node_or_null("Rides/Chefty")
	if ride == null or bool(ride.call("is_riding")):
		return
	var party: Array = _Boarding.call("choose_party", _players_near(%TruckPad.global_position))
	if party.is_empty():
		return
	# No job to go to: nobody texted, or it's past 2 AM and the crew needs sleep.
	if not can_depart():
		return
	_load_job_lot()
	ride.call("depart", party, Net.Zone.LOT)


## Whether Chefty can head out: a yard is waiting (or a test seed), and the
## clock hasn't run out. Every peer can ask, for the prompt at the truck.
func can_depart() -> bool:
	if int(Net.dev_options().get("job_seed")) != 0:
		return true
	var clock := get_node_or_null("DayClock")
	if clock != null and bool(clock.call("is_closed")):
		return false
	if %LotSlot.get_child_count() > 0:
		return true
	return not ($JobBoard.call("current") as Dictionary).is_empty()


## Host only. paid is the homeowner's cash; without it, Campaign falls back to cleanup.
func _host_finish(paid: float = -1.0, details: Dictionary = {}) -> void:
	Campaign.finish_job(paid, details)
	# Paid: the hands climb back on the truck.
	var hires := get_node_or_null("Hires")
	if hires != null:
		hires.call("despawn")
	var chefty := get_node_or_null("Rides/Chefty")
	if chefty != null:
		chefty.call("clear_bags")
	var ride := get_node_or_null("Rides/Chefty")
	if ride == null or bool(ride.call("is_riding")):
		return
	var party: Array = _Boarding.call("choose_party", Net.players_in_zone(Net.Zone.LOT))
	var riding: Array[int] = []
	for peer_id: Variant in party:
		riding.append(int(peer_id))
	for peer_id: int in Net.players_in_zone(Net.Zone.LOT):
		if not riding.has(peer_id):
			Net.move_player_to_zone(peer_id, Net.Zone.STORE)
	if riding.is_empty():
		_free_lot()
		return
	ride.call("depart", riding, Net.Zone.STORE)


func _players_near(point: Vector3) -> Array[int]:
	var ids: Array[int] = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		if not node is Node3D:
			continue
		if (node as Node3D).global_position.distance_to(point) <= _Boarding.BOARD_RADIUS_METERS:
			ids.append(int(node.name))
	return ids


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_depart() -> void:
	if Net.is_host():
		_host_depart()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_finish() -> void:
	if Net.is_host():
		_host_finish()


func _on_node_added(node: Node) -> void:
	_SharedLook.call("restyle", node)


func _play_sfx(sound_name: String, at: Vector3) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", sound_name, at)


func _on_player_joined(peer_id: int) -> void:
	_spawn_peer(peer_id)


## Host: someone reached the lot some other way than Chefty (a debug gate, the
## smoke test): give them the picked yard if none is there.
func _on_zone_changed(_peer_id: int, zone: Net.Zone) -> void:
	# Only for test and dev paths; in play, the yard comes with Chefty, and a
	# straggler back from the border with no yard left goes to the store
	# (net/border_return.gd).
	# In the connected town, bot sessions get theirs on demand too (can_enter_zone).
	var on_demand := Net.is_automated() or (town_map and bool(Net.dev_options().get("bot")))
	if Net.is_host() and on_demand and zone == Net.Zone.LOT and %LotSlot.get_child_count() == 0:
		_load_job_lot()


func _on_player_left(peer_id: int) -> void:
	_PlayerDirector.despawn(%Players, peer_id)


func _spawn_bag(at: Vector3, units: int) -> void:
	_bag_serial += 1
	var bag := BAG_SCENE.instantiate()
	bag.name = "Bag%d" % _bag_serial
	bag.set("kind", "leaf_bag")
	bag.set("color", Color(0.72, 0.48, 0.18, 1))
	bag.set("label", "Leaf bag")
	var field := get_tree().get_first_node_in_group("leaf_field")
	bag.set("value", int(field.call("dollars_for", units)) if field != null else 0)
	_play_sfx("bag", at)
	%RuntimeProps.add_child(bag, true)
	bag.global_position = at + Vector3(0.0, 0.6, 0.0)


func _spawn_peer(peer_id: int) -> void:
	var zone := Net.player_zone(peer_id)
	_PlayerDirector.spawn(%Players, peer_id, get_spawn_transform(zone, &"", peer_id))


func _spawn_points(zone: Net.Zone) -> Node3D:
	match zone:
		Net.Zone.LOT:
			return %LotSpawnPoints
		Net.Zone.BORDER:
			return %BorderSpawnPoints
		# STORE, and TOWN until driving chunk B gives the town its own respawn points.
		_:
			return %StoreSpawnPoints
