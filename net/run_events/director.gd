extends Node

## Authority: host decides when a run event starts, who is caught, how long the van
## waits and when it leaves. OQ-009: the progress rule gates the first roll; after
## that the crew's heat (heat.gd) sets the chance of every roll and how many NICE
## BOYS come. Taylan, 2026-10-21 (docs/FUN.md).
##
## R2 chunk 2 (docs/GAME.md "The NICE BOYS encounter (R2)"):
##   QUIET -> WARNING (8 s; the crew is made at once, seated in the van while it is
##   out of sight, and the van pulls up) -> CHASE (they hop out; the catches are
##   net/run_events/encounter.gd's) -> DEPARTING (the van has waited
##   VAN_HOLD_SECONDS after its first rider, or nobody is left to catch, or the
##   crew gave up; they climb back in) -> QUIET (the van leaves). No NICE BOY is
##   ever freed in view: only once the van carrying him is gone.
## The van is chunk 4's Shuttle (group "nice_shuttle") when it exists; without it
## the cast:5 van that pulls up (net/run_events/van_arrival.gd) seats the crew and
## the old ride (net/components/ride.gd, Rides/Van) takes the riders to the border.

const CREW_SCENE: PackedScene = preload("res://npcs/crew_member.tscn")
const _RideScript: Script = preload("res://net/components/ride.gd")
const _Rules: Script = preload("res://net/run_events/rules.gd")
const _Economy = preload("res://core/economy.gd")
const _Strings = preload("res://ui/strings.gd")
const _Encounter = preload("res://net/run_events/encounter.gd")
const _Crew = preload("res://npcs/crew_member.gd")
const _NiceVan = preload("res://props/nice_van.gd")
## From the lot zone's origin, where the van parks: the street's far lane in front
## of the yard, wheels on the ground. It pulls up there (van_arrival.gd) and leaves
## from there with whoever was caught.
const VAN_PARK_OFFSET := Vector3(-6.0, 0.0, 28.6)
## Chunk 4's Shuttle replaces the cast:5 van_arrival.gd (it keeps a shim of that
## name until the integrator deletes it).
const SHUTTLE_PATH := "res://net/run_events/shuttle.gd"
const VAN_ARRIVAL_PATH := "res://net/run_events/van_arrival.gd"


signal phase_changed(status: String)
signal peer_caught(peer_id: int)

enum Phase { QUIET, WARNING, CHASE, DEPARTING }

var _phase: int = Phase.QUIET
var _phase_started: float = 0.0
var _status: String = ""
var _rolled_lot: int = -1
var _last_event_time: float = -100000.0
var _cohort: Array[int] = []
var _hazard_seed: int = 0
var _safe_until: Dictionary = {}
var _next_roll: float = 0.0
var _empty_lot_for: float = 0.0
## Host, this raid: how many were caught, who was ever spotted, when the first rider
## sat down, when the departure began, and the hop-outs still to start.
var _raid_caught: int = 0
var _last_raid_caught: int = 0
var _spotted: Dictionary = {}
var _first_seat_at: float = -1.0
var _depart_started: float = 0.0
var _hops: Array[Dictionary] = []
var _encounter: Node


func _ready() -> void:
	add_to_group("run_director")
	if not Net.player_left.is_connected(_on_player_left):
		Net.player_left.connect(_on_player_left)
	_encounter = _Encounter.new()
	_encounter.name = "Encounter"
	add_child(_encounter)
	_encounter.connect("peer_caught", func(peer_id: int) -> void: peer_caught.emit(peer_id))
	# The van, on every peer: chunk 4's Shuttle when it exists, else cast:5's pull-up.
	var van_script: Script = load(SHUTTLE_PATH) if ResourceLoader.exists(SHUTTLE_PATH) else load(VAN_ARRIVAL_PATH)
	var van: Node = van_script.new()
	van.name = "Shuttle" if ResourceLoader.exists(SHUTTLE_PATH) else "VanArrival"
	add_child(van)
	# A late joiner asks for the raid under way (phase, cohort, catches, the van).
	if not Net.is_host() and multiplayer.multiplayer_peer != null:
		_ask_for_state.call_deferred()


func _ask_for_state() -> void:
	if multiplayer.multiplayer_peer != null and not Net.is_host():
		_rpc_request_state.rpc_id(1)


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


## The Encounter (World/RunDirector/Encounter).
func encounter() -> Node:
	return _encounter


## Where the crew gets out: the van's door (kept for callers that ask where the
## NICE BOYS arrive).
func crew_arrival_point() -> Vector3:
	var shuttle := _shuttle()
	if shuttle != null and shuttle.has_method("door_step_point"):
		return shuttle.call("door_step_point")
	var parked := _NiceVan.pose(_NiceVan.arrival_curve(van_park_point()), 1.0)
	return parked * Vector3(Constants.CREW_VAN_CURB_X + 0.4, 0.0, 0.9)


## Where the NICE BOYS' van parks at the lot (world space): the Shuttle's clear curb
## spot near the loudest player when it exists, else the fixed curb spot.
func van_park_point() -> Vector3:
	var shuttle := _shuttle()
	if shuttle != null and shuttle.has_method("park_point"):
		return shuttle.call("park_point")
	var lot := get_parent().get_node("LotZone") as Node3D
	return lot.global_position + VAN_PARK_OFFSET


func cohort_size() -> int:
	return _cohort.size()


func is_captured(peer_id: int) -> bool:
	return _cohort.has(peer_id)


func can_capture(peer_id: int) -> bool:
	if _phase != Phase.CHASE:
		return false
	if _cohort.has(peer_id):
		return false
	if float(_safe_until.get(peer_id, 0.0)) > Net.server_time():
		return false
	var stage := int(_encounter.call("stage_of", peer_id)) if _encounter != null else 0
	if stage != _Encounter.Stage.NONE and stage != _Encounter.Stage.WINDUP:
		return false
	return Net.player_zone(peer_id) == Net.Zone.LOT


func cohort_roster() -> Array:
	var copy: Array = []
	for peer_id: int in _cohort:
		copy.append(peer_id)
	return copy


## The seed of the cohort that last left (Border Return's hazards; the Annex's seed later).
func hazard_seed() -> int:
	return _hazard_seed


## How many were caught in the last raid that ended.
func last_raid_caught() -> int:
	return _last_raid_caught


## Host: the player whose tools made the most noise lately (heat.gd), or 0.
func loudest_peer() -> int:
	var heat := get_tree().get_first_node_in_group("heat")
	return int(heat.call("loudest_peer")) if heat != null and heat.has_method("loudest_peer") else 0


## Host: a NICE BOY saw this player (the escape XP goes to spotted, uncaught players).
func note_spotted(peer_id: int) -> void:
	_spotted[peer_id] = true


## Host: out of the cohort, unseizable for immunity seconds, and the Encounter's
## stage over (FREE) on every peer. Border Return and the Annex call this at the end.
func release_peer(peer_id: int, immunity: float = Constants.BORDER_RETURN_IMMUNITY_SECONDS) -> void:
	host_release(peer_id, immunity)
	if _encounter != null:
		_encounter.call("host_set_stage", peer_id, _Encounter.Stage.FREE)


## Host: just the bookkeeping of a release (the Encounter's frees do their own stage).
func host_release(peer_id: int, immunity: float) -> void:
	_cohort.erase(peer_id)
	_safe_until[peer_id] = Net.server_time() + immunity


## Every peer, from the Encounter's catch and free RPCs: the cohort as it stands.
func mark_caught(peer_id: int, caught: bool) -> void:
	if caught and not _cohort.has(peer_id):
		_cohort.append(peer_id)
	elif not caught:
		_cohort.erase(peer_id)


## Riders on the van right now: the Shuttle's seats, or the old ride's.
func van_occupied() -> int:
	var shuttle := _shuttle()
	if shuttle != null and shuttle.has_method("seated_riders"):
		return (shuttle.call("seated_riders") as Array).size()
	var van := get_parent().get_node_or_null("Rides/Van")
	if van == null:
		return 0
	return int(van.call("occupied_count"))


## Host only. Skip the chance roll and warn, then send the crew.
func force_event() -> void:
	if not Net.is_host() or _phase != Phase.QUIET:
		return
	_begin_warning()


## Host only. Caught now, with no lunge: the nearest NICE BOY during a chase (the
## gotcha plays), or straight to the van door when there's none (smoke, scenarios).
func force_capture(peer_id: int) -> void:
	if not Net.is_host() or _cohort.has(peer_id):
		return
	var player := _player(peer_id)
	var crew: Node3D = null
	if _phase == Phase.CHASE and player != null:
		var best := INF
		for node: Node in get_tree().get_nodes_in_group("nice_crew"):
			var member := node as Node3D
			if member == null or not bool(member.call("in_brain_mode")):
				continue
			var distance := member.global_position.distance_to(player.global_position)
			if distance < best:
				best = distance
				crew = member
	_encounter.call("host_begin_catch", peer_id, crew)


## Host: the cohort's bookkeeping when someone is caught (the Encounter calls it):
## out of any vehicle seat, out of any carry both ways, counted for the day.
func note_capture(peer_id: int) -> void:
	if not Net.is_host() or _cohort.has(peer_id):
		return
	_cohort.append(peer_id)
	_raid_caught += 1
	# Caught sitting in Chefty: out of the seat, or they'd stay glued to it.
	for vehicle: Node in get_tree().get_nodes_in_group("vehicles"):
		if vehicle.has_method("drop_rider"):
			vehicle.call("drop_rider", peer_id)
	var brawl := get_tree().get_first_node_in_group("brawl")
	if brawl != null and brawl.has_method("host_drop_carry"):
		brawl.call("host_drop_carry", peer_id)
	Campaign.note_day("caught", 1.0)
	_log("capture", {"peer_id": peer_id})


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	var anyone_on_lot := not Net.players_in_zone(Net.Zone.LOT).is_empty()
	if anyone_on_lot:
		_empty_lot_for = 0.0
	else:
		_empty_lot_for += delta
	match _phase:
		Phase.WARNING:
			if not anyone_on_lot:
				# Everyone left before they arrived: the call is off.
				_end_raid()
			elif Net.server_time() - _phase_started >= Constants.RUN_WARNING_SECONDS:
				_begin_chase()
		Phase.CHASE:
			_step_hops()
			_step_chase()
		Phase.DEPARTING:
			_step_hops()
			_step_departing()
		Phase.QUIET:
			# A forced catch outside a raid: no hold, the van goes.
			if not _seated_riders().is_empty():
				_depart()
			_consider_roll()
	_free_gone_crew()


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
	# The last raid's van is still on its way out.
	if not get_tree().get_nodes_in_group("nice_crew").is_empty():
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
		_begin_warning()


## The crew's heat now, 0 to 100.
func _heat() -> float:
	var heat := get_tree().get_first_node_in_group("heat")
	return float(heat.get("heat")) if heat != null else 0.0


## The call comes in: the crew is made now, seated in the van while it's out of
## sight, and the van starts its way here.
func _begin_warning() -> void:
	_raid_caught = 0
	_spotted.clear()
	_first_seat_at = -1.0
	_hops.clear()
	_set_phase(Phase.WARNING, _Strings.UI["status_crew_coming"])
	_spawn_crew()


func _begin_chase() -> void:
	_last_event_time = Net.server_time()
	_set_phase(Phase.CHASE, _Strings.UI["status_crew_here"])
	# The day summary's "raided" quip (Strings.summary_quip).
	Campaign.note_day("raids", 1.0)
	# The van is parked: they hop out one by one, the head NICE BOY first (the
	# Shuttle does its own, after its door slides open).
	if _shuttle() != null and _shuttle().has_method("host_spawn_crew"):
		return
	var start := Net.server_time() + Constants.CREW_HOP_FIRST_DELAY
	for crew: Node in _crew_list():
		var index := int(crew.call("crew_index"))
		_hops.append({"crew": crew, "at": start + float(index - 1) * Constants.CREW_HOP_GAP})
		crew.set("last_contact_at", start)


func _step_hops() -> void:
	var now := Net.server_time()
	for hop: Dictionary in _hops.duplicate():
		if now < float(hop["at"]):
			continue
		_hops.erase(hop)
		var crew := hop["crew"] as Node
		if is_instance_valid(crew) and int(crew.get("mode")) == _Crew.Mode.SEATED:
			crew.call("host_set_mode", _Crew.Mode.HOP_OUT)


## The chase: the van waits after its first rider, longer only while someone's
## still being walked over; it goes at once when there's nobody left to catch, and
## the crew gives up at the chase's limit or after long enough without a sign of anyone.
func _step_chase() -> void:
	var now := Net.server_time()
	var seated := _seated_riders()
	if not seated.is_empty() and _first_seat_at < 0.0:
		_first_seat_at = now
	var busy := _escorting()
	var free_on_lot := 0
	for peer_id: int in Net.players_in_zone(Net.Zone.LOT):
		if not _cohort.has(peer_id):
			free_on_lot += 1
	if _first_seat_at >= 0.0:
		var held := now - _first_seat_at
		if (held >= Constants.VAN_HOLD_SECONDS and not busy) or held >= Constants.VAN_HOLD_MAX or (free_on_lot == 0 and not busy):
			host_begin_departure()
			return
	var chased_for := now - _phase_started
	if chased_for >= Constants.RUN_CHASE_SECONDS or _empty_lot_for >= Constants.RUN_EMPTY_LOT_SECONDS:
		host_begin_departure()
		return
	if busy or not seated.is_empty() or not _hops.is_empty():
		return
	var latest := _phase_started
	for crew: Node in _crew_list():
		latest = maxf(latest, float(crew.get("last_contact_at")))
	if now - latest >= Constants.CREW_GIVE_UP_UNSEEN:
		_log("crew_gave_up", {"unseen": true})
		host_begin_departure()


## Host: wrap it up. The crew walks back and climbs in; the van goes when they're
## all aboard (or CREW_RECALL_MAX later).
func host_begin_departure() -> void:
	if not Net.is_host() or _phase != Phase.CHASE:
		return
	_depart_started = Net.server_time()
	_set_phase(Phase.DEPARTING, _status)
	var first := true
	for crew: Node in _crew_list():
		if bool(crew.call("in_brain_mode")):
			crew.call("host_set_mode", _Crew.Mode.RECALL)
			if first:
				crew.call("bark", "recall", true)
				first = false


func _step_departing() -> void:
	var now := Net.server_time()
	var door: Vector3 = _encounter.call("_door_point")
	var aboard := true
	for crew: Node in _crew_list():
		var mode := int(crew.get("mode"))
		if mode == _Crew.Mode.SEATED:
			continue
		aboard = false
		if bool(crew.call("in_brain_mode")) or mode == _Crew.Mode.DOOR:
			crew.call("host_set_mode", _Crew.Mode.RECALL)
			mode = _Crew.Mode.RECALL
		if mode != _Crew.Mode.RECALL:
			continue
		var at := (crew as Node3D).global_position
		if Vector2(at.x - door.x, at.z - door.z).length() <= Constants.CREW_BOARD_REACH:
			crew.call("host_walk", Vector3.INF, 0.0)
			var shuttle := _shuttle()
			if shuttle != null and shuttle.has_method("host_crew_board"):
				shuttle.call("host_crew_board", crew)
			else:
				crew.call("host_set_mode", _Crew.Mode.HOP_IN)
		else:
			crew.call("host_walk", door, Constants.CREW_SPEED_RECALL)
	var limit := Constants.CREW_RECALL_MAX * (1.0 if _shuttle() != null else Constants.CREW_RECALL_FALLBACK_SCALE)
	if (aboard or now - _depart_started >= limit) and not _escorting():
		_depart()


## Host: the van leaves with whoever's aboard; the raid is over.
func _depart() -> void:
	var riders := _seated_riders()
	_hazard_seed = randi()
	var shuttle := _shuttle()
	if shuttle != null and shuttle.has_method("host_depart"):
		shuttle.call("host_depart", Net.server_time())
	elif not riders.is_empty():
		_rpc_legacy_ride.rpc(riders, _hazard_seed)
		for peer_id: int in riders:
			_encounter.call("host_set_stage", peer_id, _Encounter.Stage.RIDING)
		var van := get_parent().get_node_or_null("Rides/Van")
		if van != null:
			van.call("depart", riders, Net.Zone.BORDER)
	# A stray left on the lawn (the recall ran out) has to be somewhere: in the van.
	for crew: Node in _crew_list():
		var mode := int(crew.get("mode"))
		if mode != _Crew.Mode.SEATED and mode != _Crew.Mode.HOP_IN:
			crew.call("host_walk", Vector3.INF, 0.0)
			crew.call("host_set_mode", _Crew.Mode.HOP_IN)
	_end_raid()


## The raid is over: the heat settles, the escape XP, and QUIET (the van drives off).
func _end_raid() -> void:
	var was_raid := _phase == Phase.CHASE or _phase == Phase.DEPARTING
	_last_raid_caught = _raid_caught
	var heat := get_tree().get_first_node_in_group("heat")
	if was_raid and heat != null:
		if _raid_caught > 0:
			heat.call("after_raid")
		elif heat.has_method("set_after_evaded"):
			heat.call("set_after_evaded", Constants.HEAT_AFTER_EVADED)
	if was_raid and _raid_caught == 0:
		# Spotted and never caught: that's an escape.
		for peer_id: int in _spotted:
			if not Net.peer_ids().has(peer_id):
				continue
			if Campaign.has_method("award_escape"):
				Campaign.call("award_escape", peer_id)
			else:
				Campaign.add_xp(Constants.XP_ESCAPE, "escape")
	_hops.clear()
	_set_phase(Phase.QUIET, "")


## Host: seated NICE BOYS go once the van carrying them is gone from the yard (out
## of sight by then), and anyone left standing after the van went with it.
func _free_gone_crew() -> void:
	if _phase != Phase.QUIET:
		return
	var park := van_park_point()
	var shuttle := _shuttle()
	for crew: Node in _crew_list():
		var gone := false
		if shuttle != null and shuttle.has_method("is_gone"):
			gone = bool(shuttle.call("is_gone"))
		else:
			var look: Node3D = crew.call("van_anchor")
			gone = look == null or look.global_position.distance_to(park) > Constants.VAN_GONE_METERS
		if gone:
			crew.queue_free()


func _seated_riders() -> Array[int]:
	var out: Array[int] = []
	for peer_id: int in _encounter.call("peers_in", _Encounter.Stage.SEATED):
		out.append(peer_id)
	for peer_id: int in _encounter.call("peers_in", _Encounter.Stage.BOARDING):
		out.append(peer_id)
	return out


## Someone is being caught or walked to the van right now.
func _escorting() -> bool:
	for stage: int in [_Encounter.Stage.WINDUP, _Encounter.Stage.GOTCHA, _Encounter.Stage.CITE, _Encounter.Stage.ESCORT]:
		if not (_encounter.call("peers_in", stage) as Array).is_empty():
			return true
	return false


func _spawn_crew() -> void:
	if not get_tree().get_nodes_in_group("nice_crew").is_empty():
		return
	# More heat, more of them.
	var heat := get_tree().get_first_node_in_group("heat")
	var count := int(heat.call("crew_count")) if heat != null else 1
	var shuttle := _shuttle()
	if shuttle != null and shuttle.has_method("host_spawn_crew"):
		shuttle.call("host_spawn_crew", count)
		return
	var npcs := get_parent().get_node("Npcs")
	# Where the van starts its pull-up, out of sight: nothing jumps when it appears.
	var start := _NiceVan.pose(_NiceVan.arrival_curve(van_park_point()), 0.0).origin
	for index: int in count:
		var crew := CREW_SCENE.instantiate()
		crew.name = "Crew%d" % (index + 1)
		# In their seats from the first frame (the van is still out of sight).
		crew.set("mode", _Crew.Mode.SEATED)
		crew.set("mode_at", Net.server_time())
		crew.position = start
		npcs.add_child(crew, true)


func _crew_list() -> Array[Node]:
	var out: Array[Node] = []
	for crew: Node in get_tree().get_nodes_in_group("nice_crew"):
		if not crew.is_queued_for_deletion():
			out.append(crew)
	return out


func _shuttle() -> Node:
	return get_tree().get_first_node_in_group("nice_shuttle")


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


## Dev only (net/dev/scenarios.gd reset, tests): no raid, no catches, no crew.
func dev_reset() -> void:
	if not Net.is_host():
		return
	_encounter.call("host_reset")
	for peer_id: int in _cohort.duplicate():
		_rpc_drop_rider.rpc(peer_id)
	for crew: Node in _crew_list():
		crew.queue_free()
	_hops.clear()
	_safe_until.clear()
	_raid_caught = 0
	if _phase != Phase.QUIET:
		_set_phase(Phase.QUIET, "")


func _log(event_name: String, data: Dictionary) -> void:
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null:
		telemetry.call("event", event_name, data)


func _on_player_left(peer_id: int) -> void:
	if Net.is_host():
		_rpc_drop_rider.rpc(peer_id)
		_spotted.erase(peer_id)


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


## Every peer, without a Shuttle: the old ride's van, built where the van is parked,
## takes the riders to the border (the integrator drops this with chunk 4).
@rpc("authority", "call_local", "reliable")
func _rpc_legacy_ride(riders: Array, hazard_seed: int) -> void:
	_hazard_seed = hazard_seed
	for entry: Variant in riders:
		mark_caught(int(entry), true)
	var rides := get_parent().get_node("Rides")
	var van := rides.get_node_or_null("Van")
	if van == null:
		van = _RideScript.new()
		van.name = "Van"
		rides.add_child(van)
	if van.has_method("setup_as_van"):
		var border := get_parent().get_node("BorderZone") as Node3D
		van.call("setup_as_van", van_park_point(), border.global_position)


@rpc("authority", "call_local", "reliable")
func _rpc_drop_rider(peer_id: int) -> void:
	_cohort.erase(peer_id)
	var van := get_parent().get_node_or_null("Rides/Van")
	if van != null and van.has_method("drop_rider"):
		van.call("drop_rider", peer_id)


## A late joiner asks for the raid under way.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if not Net.is_host():
		return
	var shuttle := _shuttle()
	var annex := get_tree().get_first_node_in_group("annex")
	var state := {
		"phase": _phase, "started_at": _phase_started, "status": _status, "cohort": cohort_roster(),
		"encounter": _encounter.call("snapshot"),
		"shuttle": shuttle.call("snapshot") if shuttle != null and shuttle.has_method("snapshot") else {},
		"annex": annex.call("snapshot") if annex != null and annex.has_method("snapshot") else {},
	}
	_rpc_state.rpc_id(multiplayer.get_remote_sender_id(), state)


@rpc("authority", "call_remote", "reliable")
func _rpc_state(state: Dictionary) -> void:
	_phase = int(state.get("phase", Phase.QUIET))
	_phase_started = float(state.get("started_at", 0.0))
	_status = str(state.get("status", ""))
	_cohort.clear()
	for entry: Variant in state.get("cohort", []):
		_cohort.append(int(entry))
	phase_changed.emit(_status)
	_encounter.call("apply_snapshot", state.get("encounter", {}))
	var shuttle := _shuttle()
	if shuttle != null and shuttle.has_method("apply_snapshot") and not (state.get("shuttle", {}) as Dictionary).is_empty():
		shuttle.call("apply_snapshot", state["shuttle"])
	var annex := get_tree().get_first_node_in_group("annex")
	if annex != null and annex.has_method("apply_snapshot") and not (state.get("annex", {}) as Dictionary).is_empty():
		annex.call("apply_snapshot", state["annex"])
