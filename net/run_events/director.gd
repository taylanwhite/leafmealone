extends Node

## Authority: host decides when a run event starts, who is captured, and when the van leaves.
## OQ-009: the progress rule gates the first roll; after that the crew's heat
## (heat.gd) sets the chance of every roll and how many NICE BOYS come. Taylan,
## 2026-10-21 (docs/FUN.md).

const CREW_SCENE: PackedScene = preload("res://npcs/crew_member.tscn")
const _RideScript: Script = preload("res://net/components/ride.gd")
const _Rules: Script = preload("res://net/run_events/rules.gd")
const _Economy = preload("res://core/economy.gd")
const _Strings = preload("res://ui/strings.gd")
## From the lot zone's origin, where the crew appears.
const CREW_ARRIVAL_OFFSET := Vector3(16.0, 0.1, 0.0)
## From the lot zone's origin, where the van parks: the street's far lane in front
## of the yard, wheels on the ground. It pulls up there (van_arrival.gd) and leaves
## from there with whoever was caught.
const VAN_PARK_OFFSET := Vector3(-6.0, 0.0, 28.6)
const _VanArrival: Script = preload("res://net/run_events/van_arrival.gd")

signal phase_changed(status: String)

enum Phase { QUIET, WARNING, CHASE }

var _phase: int = Phase.QUIET
var _phase_started: float = 0.0
var _status: String = ""
var _rolled_lot: int = -1
var _last_event_time: float = -100000.0
var _cohort: Array[int] = []
var _cohort_id: int = 0
var _hazard_seed: int = 0
var _batching: bool = false
var _batch_left: float = 0.0
var _safe_until: Dictionary = {}
var _next_roll: float = 0.0
var _empty_lot_for: float = 0.0
## Clients: cohort members seen riding off or at the crossing. The host's
## release_peer() runs only on the host, so a client lets a member go when the
## replicated zone brings them back from there.
var _cohort_away: Dictionary = {}


func _ready() -> void:
	add_to_group("run_director")
	if not Net.player_left.is_connected(_on_player_left):
		Net.player_left.connect(_on_player_left)
	if not Net.player_zone_changed.is_connected(_on_zone_changed):
		Net.player_zone_changed.connect(_on_zone_changed)
	# The van pulling up, on every peer, timed from the phases (cosmetic).
	var arrival: Node = _VanArrival.new()
	arrival.name = "VanArrival"
	add_child(arrival)


func status_line() -> String:
	return _status


## Phase as a Phase value, for the cues in ui/run_cues.gd.
func phase() -> int:
	return _phase


## Server time the current phase began.
func phase_started_at() -> float:
	return _phase_started


## Server time the crew arrives, during the warning. -1 at any other time.
func arrival_time() -> float:
	if _phase != Phase.WARNING:
		return -1.0
	return _phase_started + Constants.RUN_WARNING_SECONDS


## Where the crew appears on the lot.
func crew_arrival_point() -> Vector3:
	var lot := get_parent().get_node("LotZone") as Node3D
	return lot.position + CREW_ARRIVAL_OFFSET


## Where the NICE BOYS' van parks at the lot, and where its ride starts (world space).
func van_park_point() -> Vector3:
	var lot := get_parent().get_node("LotZone") as Node3D
	return lot.global_position + VAN_PARK_OFFSET


func cohort_size() -> int:
	return _cohort.size()


func is_captured(peer_id: int) -> bool:
	return _cohort.has(peer_id)


## Goes up by one for every cohort the NICE BOYS take (on clients, when the
## cohort's RPC lands). A raid that ends with it unchanged caught nobody.
func cohort_id() -> int:
	return _cohort_id


func can_capture(peer_id: int) -> bool:
	if _phase != Phase.CHASE:
		return false
	if _cohort.has(peer_id):
		return false
	if float(_safe_until.get(peer_id, 0.0)) > Net.server_time():
		return false
	return Net.player_zone(peer_id) == Net.Zone.LOT


func cohort_roster() -> Array:
	var copy: Array = []
	for peer_id: int in _cohort:
		copy.append(peer_id)
	return copy


func hazard_seed() -> int:
	return _hazard_seed


func release_peer(peer_id: int) -> void:
	_cohort.erase(peer_id)
	_safe_until[peer_id] = Net.server_time() + Constants.BORDER_RETURN_IMMUNITY_SECONDS


func van_occupied() -> int:
	var van := get_parent().get_node_or_null("Rides/Van")
	if van == null:
		return 0
	return int(van.call("occupied_count"))


## Host only. Skip the chance roll and warn, then send the crew.
func force_event() -> void:
	if not Net.is_host() or _phase != Phase.QUIET:
		return
	_set_phase(Phase.WARNING, _Strings.UI["status_crew_coming"])


## Host only. Put this peer in the open cohort. The smoke test uses a short window.
func force_capture(peer_id: int) -> void:
	if not Net.is_host():
		return
	note_capture(peer_id)
	_batch_left = 0.15


func note_capture(peer_id: int) -> void:
	if not Net.is_host() or _cohort.has(peer_id):
		return
	_cohort.append(peer_id)
	_release_held(peer_id)
	# Caught sitting in Chefty: out of the seat, or they'd stay glued to it (the
	# first ride with them in a seat wins) while the van takes them away.
	for vehicle: Node in get_tree().get_nodes_in_group("vehicles"):
		if vehicle.has_method("drop_rider"):
			vehicle.call("drop_rider", peer_id)
	_log("capture", {"peer_id": peer_id})
	if _batching:
		return
	_batching = true
	_batch_left = Constants.CAPTURE_BATCH_SECONDS
	_cohort_id += 1
	_hazard_seed = randi()


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	if _batching:
		_batch_left -= delta
		if _batch_left <= 0.0:
			_close_cohort()
	var anyone_on_lot := not Net.players_in_zone(Net.Zone.LOT).is_empty()
	if anyone_on_lot:
		_empty_lot_for = 0.0
	else:
		_empty_lot_for += delta
	if _phase == Phase.WARNING and not anyone_on_lot:
		# Everyone left before they arrived: the call is off.
		_set_phase(Phase.QUIET, "")
	elif _phase == Phase.WARNING and Net.server_time() - _phase_started >= Constants.RUN_WARNING_SECONDS:
		_begin_chase()
	elif _phase == Phase.CHASE and not _batching:
		var chased_for := Net.server_time() - _phase_started
		if chased_for >= Constants.RUN_CHASE_SECONDS or _empty_lot_for >= Constants.RUN_EMPTY_LOT_SECONDS:
			_give_up()
	elif _phase == Phase.QUIET:
		_consider_roll()


## Nobody caught in time, or nobody left to catch: the NICE BOYS drive off.
func _give_up() -> void:
	_log("crew_gave_up", {"empty_lot": _empty_lot_for >= Constants.RUN_EMPTY_LOT_SECONDS})
	_dismiss_crew()


func _consider_roll() -> void:
	var slot := get_parent().get_node_or_null("LotZone/LotSlot")
	if slot == null or slot.get_child_count() == 0:
		return
	# Nobody on the yard (riding home, all in Border Return): nobody to raid.
	if Net.players_in_zone(Net.Zone.LOT).is_empty():
		return
	# The connected town keeps a paid yard up while the crew heads off: the job's
	# done, so there's nothing to call in.
	if not Campaign.is_job_open() and TownMap.enabled(get_tree()):
		return
	var field := get_tree().get_first_node_in_group("leaf_field")
	var fraction := 0.0
	if field != null:
		fraction = float(field.call("cleaned_fraction"))
	if not bool(_Rules.call("progress_ready", fraction)):
		return
	if Net.server_time() < _next_roll:
		return
	_next_roll = Net.server_time() + Constants.HEAT_ROLL_SECONDS
	_rolled_lot = Campaign.current_lot_index()
	var heat := _heat()
	# The hotter the crew, the sooner they can be raided again, and the likelier each roll.
	var since := Net.server_time() - _last_event_time
	if since < Balance.RUN_EVENT_COOLDOWN_MINUTES * 60.0 * (1.0 - heat / 100.0):
		return
	var chance := _Economy.run_roll_chance(heat, Campaign.lots_completed())
	if heat >= Constants.HEAT_RAID_AT or randf() < chance:
		_set_phase(Phase.WARNING, _Strings.UI["status_crew_coming"])


## The crew's heat now, 0 to 100.
func _heat() -> float:
	var heat := get_tree().get_first_node_in_group("heat")
	return float(heat.get("heat")) if heat != null else 0.0


func _begin_chase() -> void:
	_last_event_time = Net.server_time()
	_set_phase(Phase.CHASE, _Strings.UI["status_crew_here"])
	# The day summary's "raided" quip (Strings.summary_quip).
	Campaign.note_day("raids", 1.0)
	_spawn_crew()


func _spawn_crew() -> void:
	var npcs := get_parent().get_node("Npcs")
	if npcs.get_node_or_null("Crew1") != null:
		return
	# More heat, more of them, fanned out along the arrival side.
	var heat := get_tree().get_first_node_in_group("heat")
	var count := int(heat.call("crew_count")) if heat != null else 1
	for index: int in count:
		var crew := CREW_SCENE.instantiate()
		crew.name = "Crew%d" % (index + 1)
		crew.position = crew_arrival_point() + Vector3(0.0, 0.0, (float(index) - float(count - 1) * 0.5) * 3.0)
		npcs.add_child(crew, true)


func _close_cohort() -> void:
	_batching = false
	var roster: Array = []
	for peer_id: int in _cohort:
		roster.append(peer_id)
	if roster.is_empty():
		return
	Campaign.note_day("caught", float(roster.size()))
	_rpc_cohort.rpc(_cohort_id, roster, _hazard_seed, Net.server_time())
	var van := get_parent().get_node_or_null("Rides/Van")
	if van != null:
		van.call("depart", roster, Net.Zone.BORDER)
	_dismiss_crew()


## The chase ends when the van leaves. They do not wait on the lot for the crossing to finish.
func _dismiss_crew() -> void:
	for crew: Node in get_parent().get_node("Npcs").get_children():
		if crew.name.begins_with("Crew"):
			crew.queue_free()
	var heat := get_tree().get_first_node_in_group("heat")
	if heat != null:
		heat.call("after_raid")
	if _phase != Phase.QUIET:
		_set_phase(Phase.QUIET, "")


func _build_van() -> void:
	var rides := get_parent().get_node("Rides")
	var van := rides.get_node_or_null("Van")
	if van == null:
		van = _RideScript.new()
		van.name = "Van"
		rides.add_child(van)
	var border := get_parent().get_node("BorderZone") as Node3D
	# From where the van pulled up and parked (van_arrival.gd).
	van.call("setup_as_van", van_park_point(), border.global_position)


func _release_held(peer_id: int) -> void:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == peer_id and node.has_method("force_release"):
			node.call("force_release")
	# And they empty your pockets, right there on the yard (net/components/hotbar.gd).
	var hotbar := get_tree().get_first_node_in_group("hotbar")
	if hotbar != null:
		hotbar.call("host_empty_pockets", peer_id, "confiscated")


func _log(event_name: String, data: Dictionary) -> void:
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null:
		telemetry.call("event", event_name, data)


## Clients: a cohort member who rode off and is now back on the yard or at the
## store is home (the host already let them go in release_peer).
func _on_zone_changed(peer_id: int, zone: int) -> void:
	if Net.is_host() or not _cohort.has(peer_id):
		return
	if zone == Net.Zone.TRANSIT or zone == Net.Zone.BORDER:
		_cohort_away[peer_id] = true
	elif _cohort_away.has(peer_id):
		_cohort_away.erase(peer_id)
		_cohort.erase(peer_id)


func _on_player_left(peer_id: int) -> void:
	if Net.is_host():
		_rpc_drop_rider.rpc(peer_id)


func _set_phase(phase: int, status: String) -> void:
	_rpc_phase.rpc(phase, Net.server_time(), status)


@rpc("authority", "call_local", "reliable")
func _rpc_phase(phase: int, started_at: float, status: String) -> void:
	_phase = phase
	_phase_started = started_at
	_status = status
	phase_changed.emit(status)
	if Net.is_host():
		_log("run_phase", {"phase": phase, "status": status})
	# Sounds and visuals for each phase are in ui/run_cues.gd, timed from started_at.


@rpc("authority", "call_local", "reliable")
func _rpc_cohort(cohort_id: int, roster: Array, hazard_seed: int, _started_at: float) -> void:
	_cohort.clear()
	_cohort_away.clear()
	for entry: Variant in roster:
		_cohort.append(int(entry))
	_cohort_id = cohort_id
	_hazard_seed = hazard_seed
	_build_van()


@rpc("authority", "call_local", "reliable")
func _rpc_drop_rider(peer_id: int) -> void:
	_cohort.erase(peer_id)
	var van := get_parent().get_node_or_null("Rides/Van")
	if van != null and van.has_method("drop_rider"):
		van.call("drop_rider", peer_id)
