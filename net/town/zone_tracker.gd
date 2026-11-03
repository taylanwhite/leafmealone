extends Node

## Authority: host, the connected town only (driving chunk D; docs/DECISIONS.md
## "In the connected town the host infers zones"). Nobody teleports between the
## store, the yard and the streets any more, so the host works out each player's
## zone from where they are, every Constants.ZONE_TRACK_SECONDS, and tells
## everyone through Net.set_player_zone (no teleport). Net stays the one place
## zones live; everything that reads Net.player_zone() works as before.
##
## Inside Constants.STORE_AREA is STORE. With a job yard loaded, inside its
## PAD_RECTS["LotZone"] (the yard plus the near lane, where Chefty parks) is LOT,
## grown by ZONE_EXIT_MARGIN while already in it so standing on the edge doesn't
## flicker. Anywhere else is TOWN. Someone in a Chefty seat is wherever Chefty is.
## BORDER and TRANSIT belong to the van and the rides, and the caught belong to
## the NICE BOYS: those are left alone.
##
## Two more host rules ride on the same tick:
## - the first time anyone reaches an open job's yard, the crew has arrived
##   (world.on_crew_arrived(): the homeowner's clock starts);
## - walking or driving more than PROP_LEASH_METERS off the yard mid-job leaves
##   what's in your pockets on it (critic C23: in the town the yard's edge is
##   crossed all the time, so it's distance, not zone changes).

var _wait: float = 0.0
## peer id -> the yard (lot node name) they've been on, so leaving it empties
## their pockets once.
var _on_site: Dictionary = {}


func _ready() -> void:
	add_to_group("zone_tracker")
	if not Net.player_left.is_connected(_on_player_left):
		Net.player_left.connect(_on_player_left)


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not Net.is_host():
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = Constants.ZONE_TRACK_SECONDS
	track()


## One pass over every player (tests call it to skip the wait).
func track() -> void:
	var world := get_parent() as Node3D
	if world == null:
		return
	var lot := _lot(world)
	var site := world.get_node("LotZone") as Node3D
	var chefty := world.get_node_or_null("Rides/Chefty")
	var director := get_tree().get_first_node_in_group("run_director")
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player := node as Node3D
		var peer_id := node.name.to_int()
		if player == null or peer_id <= 0 or not Net.peer_ids().has(peer_id):
			continue
		var zone := Net.player_zone(peer_id)
		if zone == Net.Zone.BORDER or zone == Net.Zone.TRANSIT:
			continue
		if director != null and bool(director.call("is_captured", peer_id)):
			continue
		var at := player.global_position
		if chefty != null and int(chefty.call("seat_of", peer_id)) >= 0:
			at = chefty.call("body_position")
		var now := zone_at(at, lot != null, site, zone == Net.Zone.LOT)
		if now != zone:
			Net.set_player_zone(peer_id, now)
		if lot != null:
			_check_site(world, lot, site, peer_id, at, now)


## Which zone a point is in: STORE, LOT (only with a yard loaded) or TOWN.
static func zone_at(at: Vector3, has_lot: bool, site: Node3D, in_lot: bool) -> Net.Zone:
	if Constants.STORE_AREA.has_point(Vector2(at.x, at.z)):
		return Net.Zone.STORE
	if has_lot and site != null:
		var local := site.global_transform.affine_inverse() * at
		var rect: Rect2 = Constants.PAD_RECTS.get("LotZone", Rect2(-20.0, -20.0, 40.0, 40.0))
		if in_lot:
			rect = rect.grow(Constants.ZONE_EXIT_MARGIN)
		if rect.has_point(Vector2(local.x, local.z)):
			return Net.Zone.LOT
	return Net.Zone.TOWN


## The crew's arrival and the walked-off-with-it rule for one player.
func _check_site(world: Node, lot: Node, site: Node3D, peer_id: int, at: Vector3, zone: Net.Zone) -> void:
	if zone == Net.Zone.LOT:
		_on_site[peer_id] = String(lot.name)
		if Campaign.is_job_open() and not lot.has_meta("crew_arrived"):
			world.call("on_crew_arrived")
		return
	if str(_on_site.get(peer_id, "")) != String(lot.name) or not Campaign.is_job_open():
		return
	var away := Vector2(at.x - site.global_position.x, at.z - site.global_position.z).length()
	if away <= Constants.PROP_LEASH_METERS:
		return
	_on_site.erase(peer_id)
	var hotbar := get_tree().get_first_node_in_group("hotbar")
	if hotbar != null and hotbar.has_method("host_empty_pockets"):
		hotbar.call("host_empty_pockets", peer_id, "left")


static func _lot(world: Node) -> Node:
	var slot := world.get_node_or_null("LotZone/LotSlot")
	if slot == null or slot.get_child_count() == 0:
		return null
	return slot.get_child(0)


func _on_player_left(peer_id: int) -> void:
	_on_site.erase(peer_id)
