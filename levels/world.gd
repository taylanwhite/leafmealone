extends Node3D

## Authority: host spawns players and the job lot. Geometry is the same on every peer.

const JOB_LOT: PackedScene = preload("res://levels/lots/lot_01.tscn")
const BAG_SCENE: PackedScene = preload("res://props/yard_prop.tscn")
const _PlayerDirector: Script = preload("res://net/player_director.gd")
const _Boarding: Script = preload("res://levels/boarding.gd")
const _SharedLook: Script = preload("res://levels/shared_look.gd")
const _StoreDressing = preload("res://levels/dressing/store_dressing.gd")
const _Surroundings = preload("res://levels/dressing/surroundings.gd")
const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")
const _Pedestrians = preload("res://npcs/pedestrians.gd")
const _JobBoard = preload("res://levels/job_board.gd")
const _JobLot = preload("res://levels/lots/job_lot.gd")
const _Cot = preload("res://props/cot.gd")
const _BuildQueue = preload("res://levels/build_queue.gd")
## Preloaded, so its scripts compile when the world's do (at boot), not in the
## middle of a join.
const _AnnexB = preload("res://levels/annex/annex_b.gd")
const _ToolTiers = preload("res://core/tool_tiers.gd")
## How long a swapped-out yard has to leave every peer before the picked one loads.
const LOT_SWAP_SECONDS: float = 0.4
const _Grass = preload("res://props/grass.gd")
const _StreetLife = preload("res://levels/dressing/street_life.gd")
const GRASS := Color(0.42, 0.52, 0.3)
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
## Host: junk props spawned so far (their names), and the dice for their values.
var _junk_serial: int = 0
var _junk_rng := RandomNumberGenerator.new()
## The town house whose yard the job site sits on, or -1 (legacy, or no site placed).
var _job_site_house: int = -1
## Host: _ready is done (the town's colliders and dressing exist), so the board
## may load a yard.
var _built: bool = false
## Host, the connected town: until the next look at whether a paid yard can go.
var _site_check_wait: float = 0.0


func _ready() -> void:
	add_to_group("world")
	%RuntimeProps.add_to_group("runtime_props")
	_junk_rng.randomize()
	# First, so everything below can hand its building to it (levels/build_queue.gd).
	add_child(_BuildQueue.new())
	_add_chefty()
	# The sun is set up by levels/shared_look.gd and moved by the hour (levels/day_sky.gd).
	var director := preload("res://net/run_events/director.gd").new()
	director.name = "RunDirector"
	add_child(director)
	# Satellite Annex B, where the NICE BOYS' shuttle takes whoever they caught
	# (net/annex/annex.gd, docs/GAME.md "Form 27-B, in Triplicate").
	var annex := preload("res://net/annex/annex.gd").new()
	annex.name = "Annex"
	add_child(annex)
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
	# The crew's kit: every rake and tool is a thing somewhere (net/kit/kit.gd, p2-kit).
	var kit := preload("res://net/kit/kit.gd").new()
	kit.name = "Kit"
	add_child(kit)
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
	# Room to stand: players standing inside each other are eased apart (host).
	var personal_space := preload("res://net/components/personal_space.gd").new()
	personal_space.name = "PersonalSpace"
	add_child(personal_space)
	# The look before the dressing: the dressing is built over the next frames
	# (_dress hands it to the BuildQueue), and every mesh it adds is restyled as
	# it lands, like everything built after _ready always was.
	_SharedLook.call("apply", self)
	# The player's video quality on that look (settings:2): High leaves it as is.
	preload("res://levels/graphics_quality.gd").apply(self)
	# The hour's light on that look: sun, sky, moon, stars and lamps (levels/day_sky.gd).
	var day_sky := preload("res://levels/day_sky.gd").new()
	day_sky.name = "DaySky"
	add_child(day_sky)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	_dress()
	# The host builds its world before anyone can be connected to it, so nobody
	# waits on that frame: it builds it whole, now, and everything on it (tests
	# included) finds the world as it always did. A joiner's ENet link is open
	# while it builds, so its world comes over frames.
	if Net.is_host():
		_BuildQueue.finish(get_tree())
	if town_map:
		_drop_legacy_doors()
	if not Net.is_host():
		return
	if town_map:
		# Who's where, from where they stand (driving chunk D).
		var tracker := preload("res://net/town/zone_tracker.gd").new()
		tracker.name = "ZoneTracker"
		add_child(tracker)
	# --all-tools and --starter-kit (p2-kit): the dev kit is net/kit/kit.gd's, made
	# once the yard and Chefty are up.
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
	# The connected town: the picked job's yard is there from the start, at its
	# house (the board's first offers came in before the town was dressed).
	_built = true
	if town_map:
		reload_job_lot()


## The connected town has no doors between zones: nobody boards Chefty at a sign
## and rides off by itself (you drive it, or a hired hand does), and the debug
## pads that teleported between the store and the yard would skip the town.
func _drop_legacy_doors() -> void:
	for path: String in ["StoreZone/Board", "StoreZone/ToLot", "LotZone/ToStore"]:
		var door := get_node_or_null(path)
		if door != null:
			door.get_parent().remove_child(door)
			door.queue_free()


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
	if chefty.has_signal("hopped_out"):
		chefty.connect("hopped_out", _on_boarder_hopped_out)


## Cosmetic set dressing for each zone, the scenery around them, and the shared
## outline. Local on every peer. The angles keep each ride's route clear of trees:
## Chefty leaves the store east, arrives at the lot from the west, and the van
## leaves the lot northwest and arrives at the border from the southeast.
## Built over the frames after _ready (levels/build_queue.gd), the store first,
## where everyone spawns: a joining peer built all of this in one frame before,
## 2-5 s, long enough for the host to drop it (docs/DECISIONS.md).
func _dress() -> void:
	add_child(preload("res://levels/outline_pass.gd").new())
	# The town's colliders and its streamer's node now: physics needs the whole
	# town solid from the first tick, and the job site hides slots on both.
	if town_map:
		add_child(preload("res://levels/town/town_colliders.gd").new())
		add_child(preload("res://levels/town/town_streamer.gd").new())
	_BuildQueue.later(self, func() -> void: _StoreDressing.dress($StoreZone), "store")
	# Every shop's site, keeper and hours sign, where Constants.SHOP_SITES puts
	# them (Marty behind the counter among them). Local on every peer: nothing
	# about them is shared.
	_BuildQueue.later(self, func() -> void: preload("res://levels/dressing/shop_sites.gd").dress(self), "shop_sites")
	if town_map:
		_dress_town()
	else:
		_dress_legacy()
	_BuildQueue.later(self, _dress_annex, "annex")


## Satellite Annex B in the BORDER zone's slot (levels/annex/annex_b.gd, R2
## chunk 5; docs/GAME.md "Satellite Annex B"): the same in both maps, always
## loaded, with a neighborhood's lawns and trees round it, and the street out
## front kept clear for the shuttle. Until R2 chunk 6 replaces Border Return,
## its lanes still run on this pad, so the set stands but nothing in it is solid.
func _dress_annex() -> void:
	_Surroundings.dress($BorderZone, GRASS, 33, true, [0.15, 0.6, PI - 0.15, PI - 0.6])
	_BuildQueue.later(self, func() -> void:
		var annex_set: Node3D = _AnnexB.build($BorderZone, Constants.ANNEX_SET_SEED)
		if get_node_or_null("BorderReturn") != null:
			# After the set's own build steps, which run first (levels/build_queue.gd).
			_BuildQueue.later(self, func() -> void: annex_set.call("set_solid", false), "annex solid"), "annex set")


## The connected town (net/town/town_map.gd, docs/GAME.md "Gutterford"): its
## colliders (the same on every peer), its dressing, and its houses. The store
## keeps its own dressing, grass, and walkers; the legacy lot street, the lot's
## surroundings, and the countryside drive aren't built, since the town is all
## of that.
## Steps on the BuildQueue (levels/build_queue.gd); the colliders and the
## streamer's node are made in _dress itself.
func _dress_town() -> void:
	_BuildQueue.later(self, func() -> void: _StreetLife.dress_store($StoreZone), "store street life")
	_BuildQueue.later(self, func() -> void: _Grass.plant($StoreZone, 70.0, 0.52, 11), "store grass")
	_BuildQueue.later(self, func() -> void: _Pedestrians.populate($StoreZone, [
		[Vector3(21.4, 0.1, -140.0), Vector3(21.4, 0.1, 140.0)],
		[Vector3(32.6, 0.1, -140.0), Vector3(32.6, 0.1, 140.0)],
	], 7, 11), "store walkers")
	_BuildQueue.later(self, func() -> void: preload("res://levels/town/town_dressing.gd").dress(self), "town dressing")


## Steps on the BuildQueue (levels/build_queue.gd).
func _dress_legacy() -> void:
	# No scenery tree in either street or on its sidewalks (R2b van: two pines stood
	# in the lot street's far lane, and the Courtesy Shuttle swerved onto the lawn).
	var near := _Neighborhood.SIDEWALK_NEAR.x - Constants.VAN_STREET_TREE_MARGIN
	var across := _Neighborhood.SIDEWALK_FAR.y - _Neighborhood.SIDEWALK_NEAR.x + Constants.VAN_STREET_TREE_MARGIN * 2.0
	# Their ground (solid, and what a job's block tints) now; their trees are steps.
	_Surroundings.dress($StoreZone, GRASS, 11, false, [0.0], "grass", [Rect2(near, -400.0, across, 800.0)] as Array[Rect2])
	_Surroundings.dress($LotZone, GRASS, 22, false, [PI * 0.75], "grass", [Rect2(-400.0, near, 800.0, across)] as Array[Rect2])
	# The lot's street, neighbors, street life and grass come with each job yard:
	# its block is built in the yard's neighborhood style (levels/lots/lot_generator.gd,
	# levels/town/block_builder.gd).
	# People out for a walk on the sidewalks (lot street at z 21.3 and 32.7 in the
	# lot's space; the store's cross street at x 21.3 and 32.7).
	# Grass on every lawn around the store.
	_BuildQueue.later(self, func() -> void: _StreetLife.dress_store($StoreZone), "store street life")
	_BuildQueue.later(self, func() -> void: _Grass.plant($StoreZone, 70.0, 0.52, 11), "store grass")
	_BuildQueue.later(self, func() -> void: _Pedestrians.populate($StoreZone, [
		[Vector3(21.4, 0.1, -140.0), Vector3(21.4, 0.1, 140.0)],
		[Vector3(32.6, 0.1, -140.0), Vector3(32.6, 0.1, 140.0)],
	], 7, 11), "store walkers")
	_BuildQueue.later(self, func() -> void: _Pedestrians.populate($LotZone, [
		[Vector3(-110.0, 0.1, 21.4), Vector3(110.0, 0.1, 21.4)],
		[Vector3(-110.0, 0.1, 32.6), Vector3(110.0, 0.1, 32.6)],
	], 9, 22), "lot walkers")
	# The drive from Homie Depot to the town passes country, not a void.
	_BuildQueue.later(self, func() -> void: preload("res://levels/dressing/countryside.gd").dress(self), "countryside")


## The crew camp's cots by the store's side wall (props/cot.gd). Local on every
## peer: who's asleep is the day clock's business.
func _add_cots() -> void:
	for index: int in Constants.COT_SPOTS.size():
		var cot: Node3D = _Cot.new()
		cot.name = "Cot%d" % index
		cot.set("index", index)
		$StoreZone.add_child(cot)
		cot.position = Constants.COT_SPOTS[index]
	var store := $StoreZone as Node3D
	_BuildQueue.later(store, func() -> void: _Cot.dress_camp(store, Constants.COT_SPOTS), "cot camp")


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


## Every peer: the job's yard at this house went away (job_lot.gd _exit_tree), so
## its slot shows its own house again. LotZone stays where it is until the next
## yard is placed. A different house's release changes nothing.
func release_job_site(house_id: int) -> void:
	if not town_map or house_id < 0 or house_id != _job_site_house:
		return
	_show_slot(house_id, true)
	_job_site_house = -1


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
	# Sent into the town itself: the sidewalk nearest where they are.
	if zone == Net.Zone.TOWN and town_map:
		var near := Vector3.ZERO
		for node: Node in get_tree().get_nodes_in_group("players"):
			if node.name == str(peer_id):
				near = (node as Node3D).global_position
		return Transform3D(Basis.IDENTITY, TownMap.respawn_point(near))
	var points := _spawn_points(zone)
	if spawn_marker != &"" and points.has_node(String(spawn_marker)):
		return points.get_node(String(spawn_marker)).global_transform
	# A marker the zone's set builds at runtime (the Annex's AnnexCurb, AnnexSide,
	# Forecourt, Threshold), found under the zone itself.
	if spawn_marker != &"" and points.get_parent() != null:
		# A client's zone move to the Annex lands before its begin, so the set
		# may not be built here yet: build it now, or this falls back to Spawn0.
		var annex := get_node_or_null("Annex")
		if zone == Net.Zone.BORDER and annex != null and annex.has_method("ensure_set"):
			annex.call("ensure_set")
		var built :=points.get_parent().find_child(String(spawn_marker), true, false) as Node3D
		if built != null:
			return built.global_transform
	var markers := points.get_children()
	if markers.is_empty():
		return points.global_transform
	# The first slot nobody is standing on, so nobody spawns inside someone else.
	# Peer ids are random, so a slot by id or by sorted order can collide.
	# Each peer starts looking at its own place in the session's (sorted) roster:
	# a whole crew stepping off Chefty is placed by each owner at the same moment,
	# while everyone else still sits in the bed, so a search from slot 0 put two
	# riders on one spot (tools:crew, the host's camera inside the Friend's head).
	var first := maxi(0, Net.peer_ids().find(peer_id))
	for index: int in SPAWN_SLOTS_TO_TRY:
		var slot := first + index
		var candidate := _slot_transform(markers, slot)
		if not _someone_near(candidate.origin, peer_id):
			return candidate
	return _slot_transform(markers, posmod(peer_id, markers.size()))


## Every peer: what a crew stepping off Chefty looks at (p1-arrive): the client's
## house at a job yard, Homie Depot's doors at the store, else the zone's middle.
## The same answer on every peer (the yard's house is built from its seed).
func arrival_look_point(zone: int) -> Vector3:
	if zone == Net.Zone.LOT and %LotSlot.get_child_count() > 0:
		var house := %LotSlot.get_child(0).find_child("HouseBody", true, false) as Node3D
		if house != null:
			return house.global_position
		return ($LotZone as Node3D).global_position
	if zone == Net.Zone.STORE:
		return ($StoreZone as Node3D).global_transform * Constants.ARRIVE_LOOK_STORE
	return _spawn_points(zone as Net.Zone).global_position


## Every peer: the drawn things standing near a point in a zone that have no
## collider (the street's lamp posts, hydrants, mailboxes, benches: every
## props/prop_catalog.gd prop, placed alone or batched), as [global transform,
## local AABB] boxes, so step_down.gd never lands a crew stepping off Chefty
## inside one or nose to one (play, p1-arrive: a lamp post at 0.6 m and a
## hydrant at your foot). Built from the yard's seed, so the same on every peer;
## anything under a moving body (props, people) is left out.
func arrival_obstacles(zone: int, near: Vector3, reach: float) -> Array:
	var out: Array = []
	# Out on the connected town's streets (the drivable Chefty's E-exit, zone TOWN
	# most of the time) it's wherever near is: both zones' dressing (the reach keeps
	# only what's close) and the town's own mailboxes and bins.
	var roots: Array[Node] = []
	if zone == Net.Zone.LOT or zone == Net.Zone.STORE:
		roots.append($LotZone if zone == Net.Zone.LOT else $StoreZone)
	else:
		roots.append_array([$LotZone, $StoreZone])
		for node: Node in get_tree().get_nodes_in_group("town_knockables"):
			var piece := node as Node3D
			if piece != null and piece.is_visible_in_tree() and _flat_near(piece.global_position, near, reach):
				var box := _drawn_box(piece)
				if box.size != Vector3.ZERO:
					out.append([piece.global_transform, box])
	for root: Node in roots:
		_gather_props(root, near, reach, out)
	if zone != Net.Zone.LOT:
		# Homie Depot's lot lamps (levels/dressing/neighborhood.gd lamp).
		var radius := _Neighborhood.LAMP_BASE_RADIUS
		for lamp: Vector3 in _StoreDressing.LOT_LAMPS:
			var xform := ($StoreZone as Node3D).global_transform * Transform3D(Basis.IDENTITY, lamp)
			if zone == Net.Zone.STORE or _flat_near(xform.origin, near, reach):
				out.append([xform, AABB(Vector3(-radius, 0.0, -radius), Vector3(radius * 2.0, _Neighborhood.LAMP_HEIGHT, radius * 2.0))])
	return out


## arrival_obstacles: every placed prop under root within reach of near.
func _gather_props(root: Node, near: Vector3, reach: float, out: Array) -> void:
	for node: Node in root.find_children("*", "Node3D", true, false):
		if not node.has_meta("prop_kind") or _under_mover(node, root):
			continue
		var view := node as Node3D
		if view is MultiMeshInstance3D and view.has_meta("instance_xforms"):
			var multimesh := (view as MultiMeshInstance3D).multimesh
			if multimesh == null or multimesh.mesh == null:
				continue
			var box := multimesh.mesh.get_aabb()
			for local: Transform3D in view.get_meta("instance_xforms") as Array:
				var xform := view.global_transform * local
				if _flat_near(xform.origin, near, reach):
					out.append([xform, box])
		elif _flat_near(view.global_position, near, reach):
			var box := _drawn_box(view)
			if box.size != Vector3.ZERO:
				out.append([view.global_transform, box])


func _flat_near(at: Vector3, near: Vector3, reach: float) -> bool:
	return Vector2(at.x - near.x, at.z - near.z).length() <= reach


## A placed prop's drawn box in its own space (its meshes', merged).
func _drawn_box(prop: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var to_local := prop.global_transform.affine_inverse()
	for child: Node in prop.find_children("*", "VisualInstance3D", true, false):
		var visual := child as VisualInstance3D
		var local := to_local * visual.global_transform * visual.get_aabb()
		box = local if first else box.merge(local)
		first = false
	return box


func _under_mover(node: Node, stop: Node) -> bool:
	var at := node.get_parent()
	while at != null and at != stop:
		if at is RigidBody3D or at is CharacterBody3D:
			return true
		at = at.get_parent()
	return false


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
		_host_depart(Net.local_peer_id())
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
	var chefty := get_node_or_null("Rides/Chefty")
	if destination == Net.Zone.STORE and _fetching and not town_map:
		# Back for a straggler (fx-chefty): the yard and its job carry on.
		_fetch_arrived(chefty)
	elif destination == Net.Zone.STORE and _home_after_trip and not town_map and not Net.players_in_zone(Net.Zone.LOT).is_empty():
		# Paid while it was on the road: back out for the crew still on the yard.
		_after_turnaround(chefty, func() -> void:
			if _home_after_trip:
				chefty.call("drive_empty", Net.Zone.LOT)
		)
	elif destination == Net.Zone.STORE:
		_free_lot_when_empty()
		# Back at the store with junk in the bed: it hops out for Rusty's.
		if chefty != null and chefty.has_method("unload_junk"):
			chefty.call("unload_junk")
	elif destination == Net.Zone.LOT and town_map:
		on_crew_arrived()
	elif destination == Net.Zone.LOT and _home_after_trip:
		# Paid while Chefty was out on a trip (fx-chefty review): it's back at the
		# yard for the crew, and after a beat (whoever rode out is off) it honks
		# and waits to take them home, like any job's end.
		_home_after_trip = false
		_fetch_for.clear()
		_after_turnaround(chefty, func() -> void:
			if Net.players_in_zone(Net.Zone.LOT).is_empty():
				_free_lot_when_empty()
			else:
				_open_boarding(chefty, Net.Zone.STORE)
		)
	elif destination == Net.Zone.LOT:
		# The homeowner's patience starts when the crew shows up, not at the store.
		Campaign.start_job_clock()
		# The hired hands hop off and get to work, once: Chefty coming back out
		# with a straggler (fx-chefty) doesn't round them up again.
		var hires := get_node_or_null("Hires")
		var lot := %LotSlot.get_child(0) if %LotSlot.get_child_count() > 0 else null
		if hires != null and Campaign.is_job_open() and (lot == null or not lot.has_meta("hands_off")):
			hires.call("spawn_on_lot")
			if lot != null:
				lot.set_meta("hands_off", true)
		# Someone at the pad asked for it while it was on its way: it turns round
		# for them after a beat (the crew's off and clear of it).
		if not _fetch_for.is_empty() and chefty != null:
			_after_turnaround(chefty, func() -> void:
				if not _fetch_for.is_empty():
					_start_fetch(chefty)
			)
	elif destination == Net.Zone.BORDER:
		# The Shuttle (R2 chunk 4) starts the Annex itself; the old ride lands here.
		var annex := get_node_or_null("Annex")
		var director := get_node_or_null("RunDirector")
		if annex != null and director != null and get_tree().get_first_node_in_group("nice_shuttle") == null:
			annex.call("begin", 0, director.call("cohort_roster"), Net.server_time())


## Host, the connected town. The crew got to the job's yard: someone walked (or
## drove) into it (net/town/zone_tracker.gd), a depart() trip arrived, or Chefty
## parked by its curb (chefty_drive.gd's arrival detection, however it was driven
## there). The homeowner's clock starts, once per yard. The hired hands hop off
## once Chefty is parked by the curb (they ride in the bed, so a crew that
## walked over gets them when the truck turns up).
func on_crew_arrived() -> void:
	if not Net.is_host() or %LotSlot.get_child_count() == 0 or not Campaign.is_job_open():
		return
	var lot := %LotSlot.get_child(0)
	if not lot.has_meta("crew_arrived"):
		lot.set_meta("crew_arrived", true)
		Campaign.start_job_clock()
		# Every peer reads the lock from this (job_locked).
		lot.set("stage", _JobLot.STAGE_ARRIVED)
	if lot.has_meta("hands_off"):
		return
	var chefty := get_node_or_null("Rides/Chefty")
	if chefty == null or bool(chefty.call("is_moving")):
		return
	var at: Vector3 = chefty.call("body_position")
	var curb := ($LotZone as Node3D).global_transform * TownMap.CURB_POINT
	if Vector2(at.x - curb.x, at.z - curb.z).length() > Constants.CHEFTY_ARRIVE_RADIUS:
		return
	lot.set_meta("hands_off", true)
	var hires := get_node_or_null("Hires")
	if hires != null:
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
	# --hood=<id>: every yard is in that neighborhood (tests, screenshots). Clients
	# get it with the lot like any hood.
	if str(Net.dev_options().get("hood")) != "":
		lot.set("hood", str(Net.dev_options().get("hood")))
	lot.set_meta("offer", offer)
	if town_map:
		# The yard is the client's real one, at their house's slot in Gutterford
		# (net/town/town_map.gd). Placed before it's added, so the host builds it
		# there; every client places it from the lot's spawn data (job_lot.gd).
		var house := _site_house_for(offer)
		var site := TownMap.yard_transform(house)
		place_job_site(site, house)
		lot.set("site", site)
		lot.set("house_id", house)
	%LotSlot.add_child(lot, true)
	Campaign.mark_job_open()
	var town := get_node_or_null("Town")
	if town != null and offer.has("house_id"):
		town.call("start_job", int(offer["house_id"]))
		_spawn_rival_signs(lot as Node3D, offer)
	_spawn_job_tools()
	_spawn_junk(lot as Node3D, offer)
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null:
		telemetry.call("mark_job_start")
	var field := lot.get_node_or_null("LeafField")
	if field != null and field.has_signal("bag_requested") and not field.bag_requested.is_connected(_spawn_bag):
		field.bag_requested.connect(_spawn_bag)


func _free_lot() -> void:
	_home_after_trip = false
	var hires := get_node_or_null("Hires")
	if hires != null:
		hires.call("despawn")
	for child: Node in %LotSlot.get_children():
		# p2-kit: kit left lying on the yard goes with it, by the store's door in the morning.
		_kit_yard_freed(child as Node3D)
		# Out of the slot now, so a new lot can take its name this frame.
		%LotSlot.remove_child(child)
		child.queue_free()
	_return_job_gas()
	for tool: Node in get_tree().get_nodes_in_group("job_tools"):
		tool.queue_free()
	# Back at the store: new jobs on the board.
	$JobBoard.call("refresh")


## The town house a yard goes on: the offer's house, else the house whose yard
## has the offer's seed, else the test yard (--job-seed's, and offers with no
## house: TownMap.test_site_house()).
func _site_house_for(offer: Dictionary) -> int:
	if offer.has("house_id") and int(offer["house_id"]) >= 0:
		return int(offer["house_id"])
	var town := get_node_or_null("Town")
	if town != null and offer.has("seed"):
		var by_seed := int(town.call("house_by_seed", int(offer["seed"])))
		if by_seed >= 0:
			return by_seed
	return TownMap.test_site_house()


## True once the next job is set: Chefty is on the way, or someone's at the yard.
## In the connected town it reads the yard's replicated stage (job_lot.gd), so
## the host and every client agree: locked once the crew got there and until the
## homeowner pays. A paid yard can be swapped for the next pick from anywhere,
## standing in it or sitting in Chefty at its curb included (chaining jobs
## straight from the truck); untouched, it goes by itself once everyone is
## SITE_FREE_DISTANCE away.
func job_locked() -> bool:
	var ride := get_node_or_null("Rides/Chefty")
	if ride != null and (bool(ride.call("is_riding")) or _is_boarding(ride)):
		return true
	if town_map:
		if %LotSlot.get_child_count() == 0:
			return false
		var stage := int(%LotSlot.get_child(0).get("stage"))
		# Someone in a yard the tracker hasn't marked yet (a frame, or a test
		# that sets zones by hand) still counts as there.
		return stage == _JobLot.STAGE_ARRIVED or (stage == _JobLot.STAGE_WAITING and not Net.players_in_zone(Net.Zone.LOT).is_empty())
	if not Net.players_in_zone(Net.Zone.LOT).is_empty():
		return true
	# The town's yard is waiting for the crew (in the van, crossing back) and
	# the job isn't paid: keep it, nobody swaps it out from a phone.
	return get_node_or_null("Town") != null and %LotSlot.get_child_count() > 0 and Campaign.is_job_open()


## Host only. The job board's pick changed while nobody's at the yard: swap the
## waiting yard for the picked one. picked: a player picked it (the board, the
## phone), not the board refreshing by itself.
##
## In the connected town the pick is where the job is, so an empty site loads
## the picked yard right away (the goal line and the beacon point at it), and a
## paid yard the crew is still near only goes when someone picks the next job.
func reload_job_lot(picked: bool = false) -> void:
	if not Net.is_host() or job_locked() or not _built:
		return
	if %LotSlot.get_child_count() == 0:
		if town_map and int(Net.dev_options().get("job_seed")) == 0 and not ($JobBoard.call("current") as Dictionary).is_empty():
			_load_job_lot()
		return
	# Already the picked yard with the same work: leave it be.
	var waiting := %LotSlot.get_child(0)
	var offer: Dictionary = $JobBoard.call("current")
	if offer.is_empty() or int(Net.dev_options().get("job_seed")) != 0:
		return
	if int(waiting.get("job_seed")) == int(offer["seed"]) and (waiting.get("tasks") as PackedStringArray) == (offer["tasks"] as PackedStringArray):
		return
	if town_map and not picked and not Campaign.is_job_open():
		return
	for child: Node in %LotSlot.get_children():
		_kit_yard_freed(child as Node3D)
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


## Host only. Rusty's junk in this yard (shops chunk 5; docs/GAME.md "Rusty's
## Salvage & Pawn"): how many by the hood (Constants.JUNK_PER_HOOD, Dandelion
## Acres has the most), which types, and where, all from the offer's seed. Only
## once Rusty's is open (feature:salvage), so nobody hauls junk with nowhere to
## sell it, and not in the timed tests other than --shop-test, whose yards stay
## as they were. On the lot's free spots when the lot can say where those are
## (free_spots, the lot agent's contract), else spread over the front lawn,
## clear of each other, the signs and the tools.
func _spawn_junk(lot: Node3D, offer: Dictionary) -> void:
	if lot == null or not _junk_wanted():
		return
	var hood := str(lot.get("hood"))
	var range_of: Vector2i = Constants.JUNK_PER_HOOD.get(hood, Constants.JUNK_PER_HOOD[""])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(offer.get("seed", 0)), "junk"])
	var count := rng.randi_range(range_of.x, range_of.y)
	if count <= 0:
		return
	var spots: Array = []
	if lot.has_method("free_spots"):
		spots = lot.call("free_spots", count, int(rng.seed))
	var taken: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group("job_tools"):
		taken.append((node as Node3D).global_position)
	var types: Array = Constants.JUNK_TYPES.keys()
	for index: int in count:
		var at: Vector3 = spots[index] if index < spots.size() else _junk_lawn_spot(lot, rng, taken)
		if not at.is_finite():
			continue
		taken.append(at)
		var junk := spawn_junk(str(types[rng.randi() % types.size()]), at, -1, true)
		if junk != null:
			junk.rotation.y = rng.randf_range(-PI, PI)


## A spot on the front lawn (the band the TurfMasters signs stand in,
## Constants.JUNK_LAWN_*), at least JUNK_SPACING from everything already
## placed; INF after JUNK_LAWN_TRIES tries.
func _junk_lawn_spot(lot: Node3D, rng: RandomNumberGenerator, taken: Array[Vector3]) -> Vector3:
	for _attempt: int in Constants.JUNK_LAWN_TRIES:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var at := lot.global_position + Vector3(side * rng.randf_range(Constants.JUNK_LAWN_ACROSS.x, Constants.JUNK_LAWN_ACROSS.y), 0.02, rng.randf_range(Constants.JUNK_LAWN_ALONG.x, Constants.JUNK_LAWN_ALONG.y))
		if taken.all(func(other: Vector3) -> bool: return Vector2(other.x - at.x, other.z - at.z).length() >= Constants.JUNK_SPACING):
			return at
	return Vector3.INF


## Whether yards get junk: Rusty's is open, and this isn't a timed test other
## than --shop-test (Shops._unlimited_supplies' rule).
func _junk_wanted() -> bool:
	if not Campaign.is_feature_on("salvage"):
		return false
	var options := Net.dev_options()
	var timed := float(options.get("run_seconds")) > 0.0 or Net.is_automated()
	return not timed or bool(options.get("shop_test"))


## Host only. A piece of junk for Rusty's at `at` (its base on the ground there):
## a yard prop of kind "junk", its type in label (Constants.JUNK_TYPES) and its
## base appraisal in value; -1 rolls one from the type's range, with the vintage
## flamingo now and then (Constants.JUNK_JACKPOT). on_yard: it goes with the
## job's things when the yard does. Returns the prop.
func spawn_junk(type: String, at: Vector3, value: int = -1, on_yard: bool = false) -> RigidBody3D:
	if not Net.is_host() or not Constants.JUNK_TYPES.has(type):
		return null
	if value < 0:
		value = roll_junk_value(type, _junk_rng)
	_junk_serial += 1
	var junk := BAG_SCENE.instantiate() as RigidBody3D
	junk.name = "Junk%d" % _junk_serial
	junk.set("kind", "junk")
	junk.set("label", type)
	junk.set("value", value)
	junk.set("color", Color(0.5, 0.45, 0.4))
	junk.mass = float((Constants.JUNK_TYPES[type] as Dictionary)["kg"])
	junk.add_to_group("junk")
	if on_yard:
		junk.add_to_group("job_tools")
	%RuntimeProps.add_child(junk, true)
	junk.global_position = at
	return junk


## A junk type's base appraisal: a roll in its value range, and a flamingo is
## now and then the vintage one.
static func roll_junk_value(type: String, rng: RandomNumberGenerator) -> int:
	var range_of: Vector2i = (Constants.JUNK_TYPES[type] as Dictionary)["value"]
	if type == "flamingo" and rng.randf() < float(Constants.JUNK_JACKPOT["chance"]):
		return int(Constants.JUNK_JACKPOT["value"])
	return rng.randi_range(range_of.x, range_of.y)


## Host only. p2-kit: the crew's tools are its own kit now, and come to a job
## only in Chefty's bed or in pockets (net/kit/kit.gd; the bed tops their tanks
## up as Chefty leaves the store). What still rides along with every job is the
## red gas can, with whatever spare gas there is (up to GAS_CAN_CARRY), laid by
## the truck; what's left in it goes back into the supply after the job
## (_return_job_gas), so the crew only pays for what it burned.
func _spawn_job_tools() -> void:
	var lot := %LotSlot.get_child(0) as Node3D if %LotSlot.get_child_count() > 0 else null
	if lot == null:
		return
	var shops := get_node_or_null("Shops")
	# Past where --all-tools lays its tools out (net/kit/kit.gd _seed_dev).
	var index := Catalog.TOOLS.size()
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


## Host: the crew's kit lying on this yard goes away with it (net/kit/kit.gd).
func _kit_yard_freed(lot: Node3D) -> void:
	var kit := get_node_or_null("Kit")
	if kit != null and Net.is_host():
		kit.call("host_yard_freed", lot)


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


## Host. peer_id pressed E at Chefty's pad: they climb in, Chefty honks, and the
## crew has CHEFTY_BOARD_WAIT_SECONDS to walk up and climb in too (p1-depart,
## crew-02: one E used to leave at once with whoever stood near and strand the
## rest). peer_id 0 is a test or dev call: everyone near the pad, right now.
## Chefty parked out at the yard (a teammate who missed the window) has no bed
## here to climb into: it comes back for whoever's at the pad and goes, as it
## always did (the window would honk on the yard and seat them a kilometre off).
func _host_depart(peer_id: int = 0) -> void:
	var ride := get_node_or_null("Rides/Chefty")
	if ride == null:
		return
	if bool(ride.call("is_riding")):
		# fx-chefty: missed it, and it's on its way out to the yard: it turns
		# round for you once it's dropped the crew off.
		if peer_id != 0 and ride.has_method("trip_destination") and int(ride.call("trip_destination")) == Net.Zone.LOT and _players_near(%TruckPad.global_position).has(peer_id):
			_fetch_for[peer_id] = true
		return
	# A yard that's paid for is done with: whoever Chefty left on it comes home
	# now, and the next trip goes to the next job (fx-chefty review: a teammate
	# left behind kept the paid yard loaded, and E here drove the crew back to it).
	if not _is_boarding(ride) and (peer_id == 0 or _players_near(%TruckPad.global_position).has(peer_id)):
		_release_paid_lot()
	# No job to go to: nobody texted, or it's past 2 AM and the crew needs sleep.
	if not can_depart():
		return
	var away := not _is_boarding(ride) and ride.has_method("parked_at_store") and not bool(ride.call("parked_at_store"))
	# fx-chefty: Chefty's out at the yard. It comes back down the road for you (the
	# crew there hears it pull away), honks and waits here like any trip, and you
	# climb in; it used to vanish from the curb and seat you on the spot.
	if away and peer_id != 0 and ride.has_method("drive_empty") and _players_near(%TruckPad.global_position).has(peer_id):
		_fetch_for[peer_id] = true
		_start_fetch(ride)
		return
	if peer_id == 0 or not ride.has_method("open_boarding") or away:
		var party: Array = _Boarding.call("choose_party", _players_near(%TruckPad.global_position))
		if party.is_empty():
			return
		_load_job_lot()
		ride.call("depart", party, Net.Zone.LOT)
		return
	var body := _player_node(peer_id)
	if body == null or Net.is_watcher(peer_id) or not _players_near(%TruckPad.global_position).has(peer_id) or _is_down(body):
		return
	if _is_boarding(ride):
		# Late to the honk: in you get (the window's own walk-up does the same).
		if int(ride.call("boarding_destination")) == Net.Zone.LOT:
			ride.call("board", peer_id, body.global_position)
		return
	_open_boarding(ride, Net.Zone.LOT)
	_board_opener = peer_id
	ride.call("board", peer_id, body.global_position)


## Host (fx-chefty): Chefty drives back from the yard, empty, for whoever's
## waiting at the pad (_fetch_for); on_ride_arrived opens the honk-and-wait here.
func _start_fetch(ride: Node) -> void:
	if _fetching or ride == null or bool(ride.call("is_riding")) or _is_boarding(ride):
		return
	_fetching = true
	ride.call("drive_empty", Net.Zone.STORE)


## Host (fx-chefty): back at Homie Depot for the stragglers. Whoever's still at
## the pad climbs in and Chefty honks and waits like any trip to the yard; if
## they've wandered off it goes back out to the crew empty.
func _fetch_arrived(ride: Node) -> void:
	_fetching = false
	if _home_after_trip:
		# The homeowner paid while it was on its way here (fx-chefty review): the
		# job's done, so nobody's going out to it. It turns round for the crew on
		# the yard instead, and takes them home.
		_fetch_for.clear()
		_after_turnaround(ride, func() -> void:
			if _home_after_trip and not bool(ride.call("is_riding")) and not _is_boarding(ride):
				ride.call("drive_empty", Net.Zone.LOT)
		)
		return
	_release_paid_lot()
	var waiting: Array[int] = []
	for peer_id: Variant in _fetch_for.keys():
		if _players_near(%TruckPad.global_position).has(int(peer_id)):
			waiting.append(int(peer_id))
	_fetch_for.clear()
	if waiting.is_empty() or not can_depart():
		# Back out to the crew on the yard; with nobody out there it stays put.
		if not Net.players_in_zone(Net.Zone.LOT).is_empty():
			ride.call("drive_empty", Net.Zone.LOT)
		return
	_open_boarding(ride, Net.Zone.LOT)
	_board_opener = waiting[0]
	for peer_id: int in waiting:
		var body := _player_node(peer_id)
		# fx-w9 review: flat on the pad as it pulls in, you aren't lifted into the
		# bed with stars round your head. The window holds for you (_tick_boarding)
		# and you climb in once you're up, like any walk-up.
		if body != null and not _is_down(body):
			ride.call("board", peer_id, body.global_position)


## Host (fx-chefty): the yard goes once nobody's left on it. Someone Chefty
## left behind after the cash (they never came over) still stands on it until
## they walk off (the curb's gate home): it's freed then (_physics_process).
func _free_lot_when_empty() -> void:
	for peer_id: int in Net.players_in_zone(Net.Zone.LOT):
		if not Net.is_watcher(peer_id):
			_lot_free_pending = true
			return
	_lot_free_pending = false
	_free_lot()


## Host, the legacy map: the yard in the slot is paid for and settled (the
## job's closed), but still loaded: someone Chefty left on it hasn't walked off.
func _paid_lot_loaded() -> bool:
	return not town_map and %LotSlot.get_child_count() > 0 and not Campaign.is_job_open()


## Host (fx-chefty review): the crew moves on from a paid yard (E at the pad,
## or Chefty back at the store for a straggler). Whoever's still standing on it
## comes home to the store, as everyone left over did before the stragglers'
## wait, and the yard goes, so the next trip loads the next job instead of
## driving back to the paid one. Not while Chefty is fetching the crew home.
func _release_paid_lot() -> void:
	if not _paid_lot_loaded() or _home_after_trip:
		return
	for peer_id: int in Net.peer_ids():
		if Net.player_zone(peer_id) == Net.Zone.LOT:
			Net.move_player_to_zone(peer_id, Net.Zone.STORE)
	_lot_free_pending = false
	_free_lot()


## Host: then() after CHEFTY_FETCH_TURNAROUND_SECONDS, if Chefty's still here and
## parked (whoever just rode in is off and clear of it first).
func _after_turnaround(ride: Node, then: Callable) -> void:
	if ride == null:
		return
	get_tree().create_timer(Constants.CHEFTY_FETCH_TURNAROUND_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(ride) and not bool(ride.call("is_riding")) and not _is_boarding(ride):
			then.call()
	)


## Host: Chefty starts its honk-and-wait toward destination.
func _open_boarding(ride: Node, destination: int) -> void:
	_board_left.clear()
	_all_aboard_at = -1.0
	_go_now = false
	_board_opener = 0
	_board_opened_at = Net.server_time()
	ride.call("open_boarding", destination, Constants.CHEFTY_BOARD_WAIT_SECONDS)


## Host, while Chefty honks and waits (p1-depart, docs/GAME.md "Leaving
## together"): anyone of the crew who walks up to it climbs in; once everyone in
## its zone who can come is aboard it goes after a beat, and otherwise when the
## window runs out. Captured, carried or buried crew aren't waited for.
func _tick_boarding() -> void:
	var ride := get_node_or_null("Rides/Chefty")
	if not _is_boarding(ride):
		_all_aboard_at = -1.0
		return
	var going_to := int(ride.call("boarding_destination"))
	# fx-yard: 2 AM came while Chefty honked and waited for a trip out. The day's
	# over, so is the wait: a beat after the closing yawn everyone hops back out,
	# with no last-call honk for a trip that isn't happening and no "hit the road"
	# for five more seconds (rec_close2am_1p: it waited out the window first).
	if going_to == Net.Zone.LOT and not can_depart():
		var now_closed := Net.server_time()
		if _closed_wait_at < 0.0:
			_closed_wait_at = now_closed
		elif now_closed - _closed_wait_at >= Constants.CHEFTY_BOARD_CLOSED_BEAT:
			_closed_wait_at = -1.0
			_go_now = false
			_all_aboard_at = -1.0
			ride.call("close_boarding")
		return
	_closed_wait_at = -1.0
	var zone: int = Net.Zone.STORE if going_to == Net.Zone.LOT else Net.Zone.LOT
	var director := get_node_or_null("RunDirector")
	var waiting := 0
	# Still walking over (not at the truck, and not someone who hopped back out).
	var coming := 0
	# Knocked flat at the truck: waited for, and the store's window stays open
	# for them even with nobody aboard yet (a fetch that pulls in on a downed crew).
	var down_here := 0
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		var peer_id := int(str(node.name))
		if body == null or Net.is_watcher(peer_id) or int(Net.player_zone(peer_id)) != zone:
			continue
		if (ride.call("boarders") as Array).has(peer_id):
			continue
		if director != null and bool(director.call("is_captured", peer_id)):
			continue
		if int(body.get("carried_by")) != 0 or bool(body.get("in_pile")):
			continue
		if not _at_chefty(body, ride, zone):
			# Walked off after hopping out: walking back up counts again.
			_board_left.erase(peer_id)
			waiting += 1
			coming += 1
			continue
		# fx-w9: knocked flat beside the truck, you get up first; then you climb in.
		if _is_down(body):
			waiting += 1
			down_here += 1
			continue
		if _board_left.has(peer_id) or not bool(ride.call("board", peer_id, body.global_position)):
			waiting += 1
	var now := Net.server_time()
	var aboard := (ride.call("boarders") as Array).size()
	if aboard == 0 and zone == Net.Zone.STORE and down_here == 0:
		# Everyone hopped back out: no trip.
		ride.call("close_boarding")
		return
	if waiting == 0 and aboard > 0:
		if _all_aboard_at < 0.0:
			_all_aboard_at = now
		elif now - _all_aboard_at >= Constants.CHEFTY_BOARD_ALL_ABOARD_SECONDS:
			_host_leave()
			return
	else:
		_all_aboard_at = -1.0
	# fx-chefty: after the cash, Chefty waits for the crew still out on the yard,
	# a last-call honk every CHEFTY_BOARD_STRAGGLER_STEP, up to
	# CHEFTY_BOARD_STRAGGLER_WAIT in all (holding E still goes at once). It used
	# to go when the window ran out and gather a straggler 30 m off straight into
	# the bed.
	var leave_at := float(ride.call("leave_at"))
	if not _go_now and zone == Net.Zone.LOT and coming > 0 and now >= leave_at - Constants.CHEFTY_BOARD_STRAGGLER_LEAD and now - _board_opened_at < Constants.CHEFTY_BOARD_STRAGGLER_WAIT and ride.has_method("extend_boarding"):
		ride.call("extend_boarding", Constants.CHEFTY_BOARD_STRAGGLER_STEP)
		return
	if now >= leave_at or _go_now:
		_host_leave()


## Host: a boarder held E (net/components/ride.gd): go now.
func boarding_go_now() -> void:
	if Net.is_host() and _is_boarding(get_node_or_null("Rides/Chefty")):
		_go_now = true
		_host_leave()


## Host: the honk-and-wait is over. To the yard, or (after the cash) settle up
## and take everyone home. Never with someone still in mid-hop into the bed
## (the truck pulled the last one in from 50 m down the road, rec_crew_fr
## frames 550-558): the next tick tries again once they've landed.
func _host_leave() -> void:
	var ride := get_node_or_null("Rides/Chefty")
	if not _is_boarding(ride):
		return
	if int(ride.call("boarding_destination")) == Net.Zone.LOT:
		if not can_depart():
			_go_now = false
			ride.call("close_boarding")
			return
		if bool(ride.call("climbing")):
			return
		_all_aboard_at = -1.0
		_go_now = false
		_load_job_lot()
		ride.call("leave_now")
		return
	_gather_lot(ride)
	if bool(ride.call("climbing")):
		return
	_all_aboard_at = -1.0
	_go_now = false
	if _pending_finish.is_empty() and not Campaign.is_job_open():
		# Settled already (paid while Chefty was out fetching, fx-chefty review):
		# this window was just the ride home.
		_host_take_home()
		return
	var pending := _pending_finish
	_pending_finish = {}
	var paid := float(pending.get("paid", -1.0))
	# Bags tossed in during the wait are paid for too (she updates the receipt's
	# details in place; the cash already handed over was the rest of it).
	var homeowner := get_tree().get_first_node_in_group("homeowner")
	if homeowner != null and paid >= 0.0 and homeowner.has_method("host_count_late_bags"):
		var repriced := int(homeowner.call("host_count_late_bags"))
		if repriced >= 0:
			paid = float(repriced)
	_host_settle(paid, pending.get("details", {}) as Dictionary)


## Host, the window after the cash is up: whoever's still on the lot climbs in
## too (the crew first, then a watcher, as seats allow); whoever doesn't fit
## goes to the store as before. Close by, they hop in; from across the yard
## they're just aboard (Constants.CHEFTY_BOARD_CLIMB_FROM_MAX).
func _gather_lot(ride: Node) -> void:
	var lot_peers: Array[int] = Net.players_in_zone(Net.Zone.LOT)
	lot_peers.sort_custom(func(a: int, b: int) -> bool: return int(Net.is_watcher(a)) < int(Net.is_watcher(b)))
	var bed: Vector3 = (ride.call("bed_transform") as Transform3D) * Vector3(0.0, 0.0, 0.7)
	for peer_id: int in lot_peers:
		if (ride.call("boarders") as Array).has(peer_id):
			continue
		var body := _player_node(peer_id)
		# fx-chefty: too far off to climb in (they never came over in all that
		# waiting): left on the yard, never pulled into the bed from 30 m. The
		# yard stays until they walk off it (the gate home at the curb).
		if body != null and not Net.is_watcher(peer_id) and Vector2(body.global_position.x - bed.x, body.global_position.z - bed.z).length() > Constants.CHEFTY_BOARD_GATHER_REACH:
			continue
		# fx-w9: flat on the grass as it goes: left on the yard like a straggler,
		# never lifted into the bed with stars round their head.
		if body != null and _is_down(body):
			continue
		if body == null or not bool(ride.call("board", peer_id, body.global_position)):
			Net.move_player_to_zone(peer_id, Net.Zone.STORE)


## Whether this body is at Chefty for the walk-up: the store's Board pad, or
## within CHEFTY_BOARD_WALKUP_METERS of the bed.
func _at_chefty(body: Node3D, ride: Node, zone: int) -> bool:
	if zone == Net.Zone.STORE:
		var pad := get_node_or_null("StoreZone/Board") as Area3D
		if pad != null and pad.overlaps_body(body):
			return true
	var bed: Vector3 = (ride.call("bed_transform") as Transform3D) * Vector3(0.0, 0.0, 0.7)
	return Vector2(body.global_position.x - bed.x, body.global_position.z - bed.z).length() <= Constants.CHEFTY_BOARD_WALKUP_METERS


## fx-w9: knocked flat, thrown or bailed (player.gd is_down), from the replicated pose.
static func _is_down(body: Node) -> bool:
	return body != null and body.has_method("is_down") and bool(body.call("is_down"))


static func _is_boarding(ride: Node) -> bool:
	return ride != null and ride.has_method("is_boarding") and bool(ride.call("is_boarding"))


func _player_node(peer_id: int) -> Node3D:
	return %Players.get_node_or_null(str(peer_id)) as Node3D


func _on_boarder_hopped_out(peer_id: int) -> void:
	_board_left[peer_id] = true
	# Whoever called the trip hopped back out: it's off, and whoever climbed in
	# for it hops out too (crew bots waiting by the truck sit down at any honk,
	# and drove off without the one who'd honked, play: rec_hop_1p).
	var ride := get_node_or_null("Rides/Chefty")
	if peer_id == _board_opener and _is_boarding(ride) and int(ride.call("boarding_destination")) == Net.Zone.LOT:
		ride.call("cancel_boarding")


## Host: someone left the game while Chefty waited. Their seat empties (no hop:
## there's nobody to draw), and if they'd called the trip it's off, as if
## they'd hopped out (else Chefty drove a ghost to the yard, loaded it, and
## stranded the crew at the store: review of p1-depart).
func _drop_departed_boarder(peer_id: int) -> void:
	_board_left.erase(peer_id)
	var ride := get_node_or_null("Rides/Chefty")
	if not Net.is_host() or not _is_boarding(ride) or not ride.has_method("drop_boarder"):
		return
	ride.call("drop_boarder", peer_id)
	if peer_id == _board_opener:
		_board_opener = 0
		if int(ride.call("boarding_destination")) == Net.Zone.LOT:
			ride.call("cancel_boarding")


## Host: who hopped out of the waiting truck and hasn't walked away since.
var _board_left: Dictionary = {}
## Host: when everyone was first aboard (server time), or -1.
var _all_aboard_at: float = -1.0
## Host: the homeowner's cash, settled when Chefty leaves for home.
var _pending_finish: Dictionary = {}
## Host: a boarder asked to go now (it goes once nobody's mid-hop).
var _go_now: bool = false
## Host: who pressed E to call this trip (0 for the ride home).
var _board_opener: int = 0
## Host: when this honk-and-wait opened (server time), for the stragglers' wait.
var _board_opened_at: float = 0.0
## Host (fx-chefty): who pressed E at the pad while Chefty was out at the yard or
## on its way there (peer -> true), and whether it's driving back for them.
var _fetch_for: Dictionary = {}
var _fetching: bool = false
## Host: the yard is paid for and Chefty's home, but someone's still standing on it.
var _lot_free_pending: bool = false
## Host (fx-chefty review): the job settled while Chefty was away from the yard
## (on the road, or honking at the store for a straggler): it goes back out for
## the crew and takes them home.
var _home_after_trip: bool = false

## Host: when a wait for a trip out found the day closed (server time), or -1.
var _closed_wait_at: float = -1.0


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
## With the cash (p1-depart, crew-09) the crew gets a beat first: Chefty honks
## and waits for them to walk over and climb in, and the job settles (and the
## receipt prints) as it pulls away (_host_leave).
func _host_finish(paid: float = -1.0, details: Dictionary = {}) -> void:
	if town_map:
		_host_finish_in_town(paid, details)
		return
	var waiting_ride := get_node_or_null("Rides/Chefty")
	if paid >= 0.0 and waiting_ride != null and waiting_ride.has_method("open_boarding") and not bool(waiting_ride.call("is_riding")) and not _is_boarding(waiting_ride):
		_pending_finish = {"paid": paid, "details": details}
		_open_boarding(waiting_ride, Net.Zone.STORE)
		return
	_host_settle(paid, details)


## Host: settle the job and drive everyone on the lot home. Whoever didn't make
## it to the truck in the window is gathered up (the yard goes once Chefty's home).
func _host_settle(paid: float, details: Dictionary) -> void:
	Campaign.finish_job(paid, details)
	# Paid: the hands climb back on the truck.
	var hires := get_node_or_null("Hires")
	if hires != null:
		hires.call("despawn")
	var chefty := get_node_or_null("Rides/Chefty")
	if chefty != null:
		chefty.call("clear_bags")
	_host_take_home()


## Host: the job's settled; Chefty takes whoever's on the yard home.
func _host_take_home() -> void:
	var ride := get_node_or_null("Rides/Chefty")
	if ride == null:
		return
	if bool(ride.call("is_riding")):
		# fx-chefty review: paid while Chefty was on the road (fetching a
		# straggler): it comes back for the crew once this trip's done
		# (on_ride_arrived, _fetch_arrived). It used to just never come.
		_home_after_trip = true
		return
	if _is_boarding(ride) and int(ride.call("boarding_destination")) == Net.Zone.LOT:
		# Honking at the store for a straggler when the cash came: nobody's going
		# out to a finished job. Whoever's aboard hops out, and Chefty goes out
		# empty for the crew instead.
		ride.call("cancel_boarding")
		_fetch_for.clear()
		_home_after_trip = true
		_after_turnaround(ride, func() -> void:
			if _home_after_trip:
				ride.call("drive_empty", Net.Zone.LOT)
		)
		return
	if _is_boarding(ride):
		_gather_lot(ride)
		if (ride.call("boarders") as Array).is_empty():
			ride.call("close_boarding")
			_free_lot_when_empty()
			return
		ride.call("leave_now")
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


## Host, the connected town: settle up, and nobody gets driven anywhere. The
## hands climb back into Chefty's bed, its bags come off (they're paid for), and
## the yard stays put until the crew is SITE_FREE_DISTANCE away or picks the
## next job (_maybe_free_site, reload_job_lot). Chaining jobs straight from the
## truck is the point.
func _host_finish_in_town(paid: float, details: Dictionary) -> void:
	Campaign.finish_job(paid, details)
	if %LotSlot.get_child_count() > 0:
		# Unlocks the next pick on every peer, and late joiners see it paid.
		%LotSlot.get_child(0).set("stage", _JobLot.STAGE_PAID)
	var hires := get_node_or_null("Hires")
	if hires != null:
		hires.call("despawn", true)
	var chefty := get_node_or_null("Rides/Chefty")
	if chefty != null:
		chefty.call("on_job_paid")


func _physics_process(delta: float) -> void:
	if not Net.is_host() or multiplayer.multiplayer_peer == null:
		return
	if not town_map:
		_tick_boarding()
		if _lot_free_pending:
			_free_lot_when_empty()
		return
	_site_check_wait -= delta
	if _site_check_wait > 0.0:
		return
	_site_check_wait = Constants.ZONE_TRACK_SECONDS * 5.0
	_maybe_free_site()


## Host, the connected town: a paid job's yard goes once every player and Chefty
## are more than SITE_FREE_DISTANCE from it, and the next pick's yard loads.
func _maybe_free_site() -> void:
	if %LotSlot.get_child_count() == 0 or Campaign.is_job_open():
		return
	var site := ($LotZone as Node3D).global_position
	var spots: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		spots.append((node as Node3D).global_position)
	var chefty := get_node_or_null("Rides/Chefty")
	if chefty != null:
		spots.append(chefty.call("body_position"))
	for spot: Vector3 in spots:
		if Vector2(spot.x - site.x, spot.z - site.z).length() <= Constants.SITE_FREE_DISTANCE:
			return
	_free_lot()
	reload_job_lot()


func _players_near(point: Vector3) -> Array[int]:
	var ids: Array[int] = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		# A watcher (the playtest observer) never takes a seat from the crew.
		if not node is Node3D or Net.is_watcher(int(str(node.name))):
			continue
		if (node as Node3D).global_position.distance_to(point) <= _Boarding.BOARD_RADIUS_METERS:
			ids.append(int(node.name))
	return ids


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_depart() -> void:
	if Net.is_host():
		_host_depart(multiplayer.get_remote_sender_id())


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
	# straggler back from Annex B with no yard left goes to the store
	# (net/annex/annex.gd).
	# In the connected town, bot sessions get theirs on demand too (can_enter_zone).
	var on_demand := Net.is_automated() or (town_map and bool(Net.dev_options().get("bot")))
	if Net.is_host() and on_demand and zone == Net.Zone.LOT and %LotSlot.get_child_count() == 0:
		_load_job_lot()


func _on_player_left(peer_id: int) -> void:
	_drop_departed_boarder(peer_id)
	_PlayerDirector.despawn(%Players, peer_id)


func _spawn_bag(at: Vector3, units: int, peer_id: int = 0) -> void:
	_spawn_bag_for(get_tree().get_first_node_in_group("leaf_field"), at, units, peer_id)


## A bag of field's leaves (field prices it and decides who ties it; --audio-test
## passes a stand-in field). peer_id bagged it (0: nobody in particular).
func _spawn_bag_for(field: Node, at: Vector3, units: int, peer_id: int = 0) -> void:
	_bag_serial += 1
	var bag := BAG_SCENE.instantiate()
	bag.name = "Bag%d" % _bag_serial
	bag.set("kind", "leaf_bag")
	bag.set("color", Color(0.72, 0.48, 0.18, 1))
	bag.set("label", "Leaf bag")
	bag.set("value", int(field.call("dollars_for", units)) if field != null else 0)
	# Once the field tells its strokes, LeafAudio ties the bag after it opens and
	# stuffs it (this runs before the stroke is told, so tying here comes first).
	if not LeafAudio.owns_bag_tie(field):
		_play_sfx("bag", at)
	%RuntimeProps.add_child(bag, true)
	# crew-16: the bag sits on the ground where the pile was (it grows there,
	# net_prop.gd), and at least a step in front of whoever bagged it, so it's in
	# view, not dropped at their feet under the hotbar. A test's bag (no leaves)
	# goes exactly where it was asked for.
	var spot := at + Vector3(0.0, 0.6, 0.0)
	if units > 0:
		spot = _bag_spot(at, peer_id)
	bag.global_position = spot


## Where a fresh bag of leaves goes: on the ground at the pile, pushed out to
## BAG_SPAWN_AHEAD_MIN from whoever bagged it (peer_id), never from a teammate
## who happens to stand closer to the pile. With no bagger given (tests), the
## nearest player within BAG_SPAWN_NEAREST_REACH stands in.
func _bag_spot(at: Vector3, peer_id: int = 0) -> Vector3:
	var bagger: Node3D = null
	var nearest := Constants.BAG_SPAWN_NEAREST_REACH
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player := node as Node3D
		if player == null or Net.is_watcher(player.name.to_int()):
			continue
		if peer_id != 0:
			if player.name.to_int() == peer_id:
				bagger = player
				break
			continue
		var flat := Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()
		if flat < nearest:
			nearest = flat
			bagger = player
	if bagger == null:
		return Vector3(at.x, at.y - Constants.BAG_SPAWN_PILE_HEIGHT + Constants.BAG_SPAWN_GROUND_LIFT, at.z)
	var ground := bagger.global_position.y
	var out := Vector3(at.x - bagger.global_position.x, 0.0, at.z - bagger.global_position.z)
	if out.length() < Constants.BAG_SPAWN_ON_TOP:
		out = -bagger.global_basis.z
		out.y = 0.0
	out = out.normalized() * maxf(out.length(), Constants.BAG_SPAWN_AHEAD_MIN)
	return Vector3(bagger.global_position.x + out.x, ground + Constants.BAG_SPAWN_GROUND_LIFT, bagger.global_position.z + out.z)


func _spawn_peer(peer_id: int) -> void:
	var zone := Net.player_zone(peer_id)
	_PlayerDirector.spawn(%Players, peer_id, get_spawn_transform(zone, &"", peer_id))


func _spawn_points(zone: Net.Zone) -> Node3D:
	match zone:
		Net.Zone.LOT:
			return %LotSpawnPoints
		Net.Zone.BORDER:
			return %BorderSpawnPoints
		# STORE (TOWN is the nearest sidewalk, get_spawn_transform).
		_:
			return %StoreSpawnPoints
