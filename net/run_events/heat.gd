extends Node

## Authority: host. The crew's heat, 0 to 100 (Taylan, 2026-10-21, docs/FUN.md):
## running tools, the hydrant, bills for what got broken, and bonking passersby
## all raise it; it cools slowly while the job is quiet and a lot when a job is
## paid. The run director (director.gd) rolls against it, and the hotter the
## crew the more NICE BOYS show up. Replicated to every peer for the HUD meter.

signal heat_changed(value: float)

const SYNC_SECONDS: float = 0.25
const _ToolTiers = preload("res://core/tool_tiers.gd")

var heat: float = 0.0
var _dirty: bool = false
var _sync_left: float = 0.0
## Host only (R2 chunk 2): who made noise, where and when, for the NICE BOYS'
## hearing and the van's parking spot. peer -> {"at": Vector3, "time": float,
## "amount": float (heat made over the last HEAT_NOISE_WINDOW s, decaying)}.
var _noise: Dictionary = {}


func _ready() -> void:
	add_to_group("heat")
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(func(peer_id: int) -> void: _noise.erase(peer_id))
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


## Host: the van left empty-handed; the heat settles here instead (never rises).
func set_after_evaded(value: float) -> void:
	add(minf(0.0, value - heat), "raid_evaded")


## Host: this player's running tool made noise at this point now (amount is the
## heat it made this tick).
func note_noise(peer_id: int, at: Vector3, amount: float = 0.0) -> void:
	if not Net.is_host() or peer_id <= 0:
		return
	var now := Net.server_time()
	var entry: Dictionary = _noise.get(peer_id, {"at": at, "time": now, "amount": 0.0})
	entry["amount"] = _decayed(entry, now) + amount
	entry["at"] = at
	entry["time"] = now
	_noise[peer_id] = entry


## Host: where this player last made noise within Constants.HEAT_NOISE_WINDOW, or
## Vector3.INF.
func noise_point(peer_id: int) -> Vector3:
	var entry: Dictionary = _noise.get(peer_id, {})
	if entry.is_empty() or Net.server_time() - float(entry["time"]) > Constants.HEAT_NOISE_WINDOW:
		return Vector3.INF
	return entry["at"]


## Host: seconds since this player's tool last made noise (INF if never).
func noise_age(peer_id: int) -> float:
	var entry: Dictionary = _noise.get(peer_id, {})
	return INF if entry.is_empty() else Net.server_time() - float(entry["time"])


## Host: the player who made the most noise over the window, or 0 for nobody.
func loudest_peer() -> int:
	var now := Net.server_time()
	var best := 0
	var most := 0.0
	for peer_id: int in _noise:
		var amount := _decayed(_noise[peer_id], now)
		if amount > most and now - float(_noise[peer_id]["time"]) <= Constants.HEAT_NOISE_WINDOW:
			most = amount
			best = peer_id
	return best


## A noise total fades out linearly across the window.
func _decayed(entry: Dictionary, now: float) -> float:
	var age := now - float(entry.get("time", now))
	return float(entry.get("amount", 0.0)) * clampf(1.0 - age / Constants.HEAT_NOISE_WINDOW, 0.0, 1.0)


## The heat a running tool of this kind and tier makes per second, before the
## hour's and the hood's scale: Constants.HEAT_NOISE_PER_SECOND times its tier's
## TOOL_TIER_NOISE. For tests and for any UI that says "quieter: -30% heat".
static func noise_for(kind: String, tier: int) -> float:
	return float(Constants.HEAT_NOISE_PER_SECOND.get(kind, 0.0)) * _ToolTiers.noise(tier)


## How many NICE BOYS this much heat brings.
func crew_count() -> int:
	return clampi(1 + int(floor(heat / Constants.HEAT_PER_EXTRA_CREW)), 1, Constants.HEAT_MAX_CREW)


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	# Noise: every running tool on the lot, by kind and tier (a Mk III whispers).
	var noise := 0.0
	for node: Node in get_tree().get_nodes_in_group("props"):
		if bool(node.get("spraying")):
			var made := noise_for(str(node.get("kind")), _ToolTiers.tier_of(node))
			noise += made
			# Whose it is, for the NICE BOYS' ears (a runaway mower is nobody's).
			var user := int(node.get("held_by"))
			if user > 0 and node is Node3D:
				note_noise(user, (node as Node3D).global_position, made * delta)
	if noise > 0.0:
		# Louder after 9 PM, and fancier neighborhoods call it in faster (docs/SPINE.md).
		add(noise * delta * _noise_scale())
	elif not Net.players_in_zone(Net.Zone.LOT).is_empty():
		add(-Constants.HEAT_COOL_PER_SECOND * delta * _cooling_scale())
	_sync_left -= delta
	if _dirty and _sync_left <= 0.0:
		_dirty = false
		_sync_left = SYNC_SECONDS
		_rpc_heat.rpc(heat)


## Host: send the heat now instead of at the next sync (tests do this before
## comparing every peer's heat).
func sync_now() -> void:
	if not Net.is_host():
		return
	_dirty = false
	_sync_left = SYNC_SECONDS
	_rpc_heat.rpc(heat)


func _noise_scale() -> float:
	var scale := 1.0
	var clock := get_tree().get_first_node_in_group("day_clock")
	if clock != null:
		scale *= float(clock.call("heat_scale"))
	var town := get_tree().get_first_node_in_group("town")
	if town != null:
		scale *= float(town.call("heat_scale"))
	return scale


func _cooling_scale() -> float:
	var scale := 1.0
	if Campaign.has_perk("cool_heads"):
		scale *= Constants.COOL_HEADS_COOLING
	if Campaign.has_perk("cool_heads_2"):
		scale *= Constants.COOL_HEADS_COOLING
	return scale


func _on_player_joined(peer_id: int) -> void:
	if Net.is_host() and peer_id != Net.local_peer_id():
		_rpc_heat.rpc_id(peer_id, heat)


@rpc("authority", "call_local", "reliable")
func _rpc_heat(value: float) -> void:
	heat = value
	heat_changed.emit(value)
