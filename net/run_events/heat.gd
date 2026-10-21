extends Node

## Authority: host. The crew's heat, 0 to 100 (Taylan, 2026-10-21, docs/FUN.md):
## running tools, the hydrant, bills for what got broken, and bonking passersby
## all raise it; it cools slowly while the job is quiet and a lot when a job is
## paid. The run director (director.gd) rolls against it, and the hotter the
## crew the more NICE BOYS show up. Replicated to every peer for the HUD meter.

signal heat_changed(value: float)

const SYNC_SECONDS: float = 0.25

var heat: float = 0.0
var _dirty: bool = false
var _sync_left: float = 0.0


func _ready() -> void:
	add_to_group("heat")
	Net.player_joined.connect(_on_player_joined)
	if Net.is_host():
		heat = clampf(float(Net.dev_options().get("heat")), 0.0, 100.0)


## Host: raise (or lower) the heat. reason is for the telemetry log.
func add(amount: float, reason: String = "") -> void:
	if not Net.is_host() or amount == 0.0:
		return
	var before := heat
	heat = clampf(heat + amount, 0.0, 100.0)
	if heat != before:
		_dirty = true
		if amount > 1.0:
			var telemetry := get_tree().get_first_node_in_group("telemetry")
			if telemetry != null:
				telemetry.call("event", "heat", {"amount": amount, "reason": reason, "heat": heat})


## Host: a job was paid; the crew moved on and things calmed down.
func on_job_finished() -> void:
	add(-Constants.HEAT_COOL_PER_JOB, "job_done")


## Host: the van just left with whoever it caught.
func after_raid() -> void:
	add(minf(0.0, Constants.HEAT_AFTER_RAID - heat), "raid")


## How many NICE BOYS this much heat brings.
func crew_count() -> int:
	return clampi(1 + int(floor(heat / Constants.HEAT_PER_EXTRA_CREW)), 1, Constants.HEAT_MAX_CREW)


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	# Noise: every running tool on the lot, by kind.
	var noise := 0.0
	for node: Node in get_tree().get_nodes_in_group("props"):
		if bool(node.get("spraying")):
			noise += float(Constants.HEAT_NOISE_PER_SECOND.get(str(node.get("kind")), 0.0))
	if noise > 0.0:
		add(noise * delta)
	elif not Net.players_in_zone(Net.Zone.LOT).is_empty():
		add(-Constants.HEAT_COOL_PER_SECOND * delta)
	_sync_left -= delta
	if _dirty and _sync_left <= 0.0:
		_dirty = false
		_sync_left = SYNC_SECONDS
		_rpc_heat.rpc(heat)


func _on_player_joined(peer_id: int) -> void:
	if Net.is_host() and peer_id != Net.local_peer_id():
		_rpc_heat.rpc_id(peer_id, heat)


@rpc("authority", "call_local", "reliable")
func _rpc_heat(value: float) -> void:
	heat = value
	heat_changed.emit(value)
