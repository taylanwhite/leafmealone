extends Node

## Authority: host decides when a run event starts, who is captured, and when the van leaves.
## OQ-009: only the progress rule is active. The other families live in rules.gd and stay off.

const CREW_SCENE: PackedScene = preload("res://npcs/crew_member.tscn")
const _RideScript: Script = preload("res://net/components/ride.gd")
const _Rules: Script = preload("res://net/run_events/rules.gd")
## From the lot zone's origin, where the crew appears.
const CREW_ARRIVAL_OFFSET := Vector3(16.0, 0.1, 0.0)

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


func _ready() -> void:
	add_to_group("run_director")
	if not Net.player_left.is_connected(_on_player_left):
		Net.player_left.connect(_on_player_left)


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
	_set_phase(Phase.WARNING, "The NICE BOYS are on the way")


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
	if _phase == Phase.WARNING and Net.server_time() - _phase_started >= Constants.RUN_WARNING_SECONDS:
		_begin_chase()
	elif _phase == Phase.QUIET:
		_consider_roll()


func _consider_roll() -> void:
	var slot := get_parent().get_node_or_null("LotZone/LotSlot")
	if slot == null or slot.get_child_count() == 0:
		return
	if _rolled_lot == Campaign.current_lot_index():
		return
	var field := get_tree().get_first_node_in_group("leaf_field")
	var fraction := 0.0
	if field != null:
		fraction = float(field.call("cleaned_fraction"))
	if not bool(_Rules.call("progress_ready", fraction)):
		return
	_rolled_lot = Campaign.current_lot_index()
	var since := Net.server_time() - _last_event_time
	if since < Balance.RUN_EVENT_COOLDOWN_MINUTES * 60.0:
		return
	var chance := Balance.RUN_EVENT_BASE_CHANCE
	chance += Balance.RUN_CHANCE_ESCALATION_PER_TIER * float(Campaign.lots_completed())
	chance = minf(chance, Balance.MAXIMUM_RUN_EVENT_CHANCE)
	if randf() < chance:
		_set_phase(Phase.WARNING, "The NICE BOYS are on the way")


func _begin_chase() -> void:
	_last_event_time = Net.server_time()
	_set_phase(Phase.CHASE, "The NICE BOYS are here")
	_spawn_crew()


func _spawn_crew() -> void:
	var npcs := get_parent().get_node("Npcs")
	if npcs.get_node_or_null("Crew1") != null:
		return
	var crew := CREW_SCENE.instantiate()
	crew.name = "Crew1"
	crew.position = crew_arrival_point()
	npcs.add_child(crew, true)


func _close_cohort() -> void:
	_batching = false
	var roster: Array = []
	for peer_id: int in _cohort:
		roster.append(peer_id)
	if roster.is_empty():
		return
	_rpc_cohort.rpc(_cohort_id, roster, _hazard_seed, Net.server_time())
	var van := get_parent().get_node_or_null("Rides/Van")
	if van != null:
		van.call("depart", roster, Net.Zone.BORDER)
	_dismiss_crew()


## The chase ends when the van leaves. They do not wait on the lot for the crossing to finish.
func _dismiss_crew() -> void:
	var crew := get_parent().get_node_or_null("Npcs/Crew1")
	if crew != null:
		crew.queue_free()
	if _phase != Phase.QUIET:
		_set_phase(Phase.QUIET, "")


func _build_van() -> void:
	var rides := get_parent().get_node("Rides")
	var van := rides.get_node_or_null("Van")
	if van == null:
		van = _RideScript.new()
		van.name = "Van"
		rides.add_child(van)
	var lot := get_parent().get_node("LotZone") as Node3D
	var border := get_parent().get_node("BorderZone") as Node3D
	van.call(
		"setup_as_van",
		# From the street's far lane in front of the yard, wheels on the ground.
		lot.global_position + Vector3(-6.0, 0.0, 28.6),
		border.global_position + Vector3(0.0, 0.0, 0.0)
	)


func _release_held(peer_id: int) -> void:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == peer_id and node.has_method("force_release"):
			node.call("force_release")


func _log(event_name: String, data: Dictionary) -> void:
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null:
		telemetry.call("event", event_name, data)


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
