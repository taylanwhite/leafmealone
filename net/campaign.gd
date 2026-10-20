extends Node

## Authority: host
## Credits, the rake upgrade, payout, and the save between jobs.
## OQ-005, OQ-006: one host function splits the pool with the workbook weights.

signal campaign_loaded
signal credits_changed(peer_id: int, credits: int)
signal unlocks_changed
signal job_stats_changed(peer_id: int)
signal payout_ready(results: Array[Dictionary])

const SAVE_PATH := "user://saves/campaign.json"
const SAVE_VERSION := 1
const RAKE_UPGRADE := &"rake_tier_1"
const WHEELBARROW_UPGRADE := &"wheelbarrow_tier_1"

var _job_stats: Dictionary = {}
var _bank: Dictionary = {}
var _peer_keys: Dictionary = {}
var _lots_completed: int = 0
var _job_open: bool = true
var _job_started_at: float = 0.0
var _last_settlement: Dictionary = {}
var _pending_wallets: Array[Dictionary] = []


func _ready() -> void:
	_load()
	if not Net.player_joined.is_connected(_on_player_joined):
		Net.player_joined.connect(_on_player_joined)
	campaign_loaded.emit()


## Credits currently held by one player.
func credits(peer_id: int) -> int:
	# A peer is bound on its first payout, but its saved credits count from the start.
	var key: String = _peer_keys.get(peer_id, "")
	if key == "" and Net.is_host() and Net.player_name(peer_id) != "":
		key = _key_for(peer_id)
	if key == "":
		return 0
	return int((_bank.get(key, {}) as Dictionary).get("credits", 0))


## Whether this machine's player owns an unlock.
func is_unlocked(unlock_id: StringName) -> bool:
	return peer_has_unlock(Net.local_peer_id(), unlock_id)


## Host and the local rake use this so each player has their own tool.
func peer_has_unlock(peer_id: int, unlock_id: StringName) -> bool:
	var key: String = _peer_keys.get(peer_id, "")
	if key == "":
		return false
	var unlocks: Array = (_bank.get(key, {}) as Dictionary).get("unlocks", [])
	return unlocks.has(String(unlock_id))


## Shared wheelbarrow on the lot. Any player's upgrade raises it for the crew.
func wheelbarrow_capacity() -> int:
	for peer_id: int in Net.peer_ids():
		if peer_has_unlock(peer_id, WHEELBARROW_UPGRADE):
			return Constants.WHEELBARROW_UPGRADED_BAG_CAPACITY
	return Constants.WHEELBARROW_BAG_CAPACITY


## Workbook throughput multiplier for this player's rake. 1 until they buy the tune-up.
func rake_multiplier(peer_id: int) -> float:
	if peer_has_unlock(peer_id, RAKE_UPGRADE):
		return Balance.TOOL_THROUGHPUT_GROWTH_MULTIPLIER
	return 1.0


func lots_completed() -> int:
	return _lots_completed


func current_lot_index() -> int:
	return maxi(_lots_completed + 1, 1)


func job_stats(peer_id: int) -> Dictionary:
	if _job_stats.has(peer_id):
		return (_job_stats[peer_id] as Dictionary).duplicate()
	return _empty_stats()


## Ask the host to buy the rake tune-up.
func request_purchase(item_id: StringName) -> void:
	if Net.is_host():
		_handle_purchase(Net.local_peer_id(), item_id)
	else:
		_rpc_request_purchase.rpc_id(1, String(item_id))


func record_stat(peer_id: int, stat: StringName, amount: float) -> void:
	if not Net.is_host():
		return
	var stats: Dictionary = _empty_stats()
	if _job_stats.has(peer_id):
		stats = (_job_stats[peer_id] as Dictionary).duplicate()
	var key := String(stat)
	stats[key] = float(stats.get(key, 0.0)) + amount
	_job_stats[peer_id] = stats
	job_stats_changed.emit(peer_id)


## Host only. Split this job's pool, pay, save, and tell every peer.
## Host only. paid is what the homeowner handed over; without it, pay comes from
## how much of the lot was cleaned. Either way it's split by contribution (OQ-005).
func finish_job(paid: float = -1.0, details: Dictionary = {}) -> void:
	if not Net.is_host() or not _job_open:
		return
	var fraction := 0.0
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field != null:
		fraction = float(field.call("cleaned_fraction"))
	var pool := float(Balance.CREDITS_PER_1_PERCENT_LOT_CLEANUP) * fraction * 100.0
	if fraction >= 0.999:
		pool *= 1.0 + Balance.FULL_CLEAR_PAYOUT_BONUS
	if paid >= 0.0:
		pool = paid
	var results := _split_pool(pool)
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null:
		telemetry.call("mark_job_finish", fraction, results)
	for row: Dictionary in results:
		_add_credits(int(row["peer_id"]), int(row["credits"]))
	_lots_completed += 1
	_job_open = false
	_job_stats.clear()
	_save()
	_rpc_payout.rpc(results, details)
	_rpc_progress.rpc(_lots_completed)
	for peer_id: int in Net.peer_ids():
		_send_wallet(peer_id)


func save_now() -> void:
	if Net.is_host():
		_save()


func mark_job_open() -> void:
	_job_open = true
	_job_stats.clear()
	_job_started_at = Net.server_time()


## How the last job was settled: bags_value, mood, multiplier, and paid. Empty
## when the job ended without the homeowner. Set on every peer before payout_ready.
func last_settlement() -> Dictionary:
	return _last_settlement


## Minutes since this job started, on the host.
func job_minutes() -> float:
	return (Net.server_time() - _job_started_at) / 60.0


func _on_player_joined(peer_id: int) -> void:
	_flush_wallet(peer_id)
	if not Net.is_host():
		return
	_bind_peer(peer_id)
	_send_wallet(peer_id)


func _send_wallet(peer_id: int) -> void:
	_rpc_wallet.rpc(peer_id, credits(peer_id), _unlock_list(peer_id), _lots_completed)


func _unlock_list(peer_id: int) -> PackedStringArray:
	var key: String = _peer_keys.get(peer_id, "")
	var unlocks: Array = (_bank.get(key, {}) as Dictionary).get("unlocks", [])
	var names := PackedStringArray()
	for entry: Variant in unlocks:
		names.append(str(entry))
	return names


func _handle_purchase(peer_id: int, item_id: StringName) -> void:
	if item_id != RAKE_UPGRADE and item_id != WHEELBARROW_UPGRADE:
		return
	_bind_peer(peer_id)
	if peer_has_unlock(peer_id, item_id):
		return
	if credits(peer_id) < Balance.BASELINE_TIER_1_TOOL_COST:
		return
	_add_credits(peer_id, -Balance.BASELINE_TIER_1_TOOL_COST)
	var key: String = _peer_keys[peer_id]
	var record: Dictionary = _bank[key]
	var unlocks: Array = record.get("unlocks", [])
	unlocks.append(String(item_id))
	record["unlocks"] = unlocks
	_bank[key] = record
	_save()
	_send_wallet(peer_id)
	unlocks_changed.emit()


func _split_pool(pool: float) -> Array[Dictionary]:
	var peers := Net.peer_ids()
	var leaves: Dictionary = {}
	var rescues: Dictionary = {}
	var objectives: Dictionary = {}
	var leaf_total := 0.0
	var rescue_total := 0.0
	var objective_total := 0.0
	for peer_id: int in peers:
		var stats := job_stats(peer_id)
		leaves[peer_id] = float(stats["leaves_cleared"])
		rescues[peer_id] = float(stats["rescues"])
		objectives[peer_id] = float(stats["objectives"])
		leaf_total += float(leaves[peer_id])
		rescue_total += float(rescues[peer_id])
		objective_total += float(objectives[peer_id])
	var scores: Dictionary = {}
	var score_total := 0.0
	for peer_id: int in peers:
		var leaf_share := 0.0 if leaf_total <= 0.0 else float(leaves[peer_id]) / leaf_total
		var rescue_share := 0.0 if rescue_total <= 0.0 else float(rescues[peer_id]) / rescue_total
		var objective_share := 0.0 if objective_total <= 0.0 else float(objectives[peer_id]) / objective_total
		var score := leaf_share * Balance.LEAF_CLEARING_SCORE_WEIGHT
		score += rescue_share * Balance.RESCUE_SCORE_WEIGHT
		score += objective_share * Balance.OBJECTIVE_SCORE_WEIGHT
		scores[peer_id] = score
		score_total += score
	var raw: Dictionary = {}
	if score_total <= 0.0:
		var even := 1.0 / float(maxi(peers.size(), 1))
		for peer_id: int in peers:
			raw[peer_id] = even
	else:
		for peer_id: int in peers:
			raw[peer_id] = float(scores[peer_id]) / score_total
	var floored_total := 0.0
	for peer_id: int in peers:
		raw[peer_id] = maxf(float(raw[peer_id]), Balance.MINIMUM_CONTRIBUTION_SHARE)
		floored_total += float(raw[peer_id])
	var results: Array[Dictionary] = []
	for peer_id: int in peers:
		var share := float(raw[peer_id]) / floored_total if floored_total > 0.0 else 0.0
		results.append({
			"peer_id": peer_id,
			"name": Net.player_name(peer_id),
			"leaves": float(leaves[peer_id]),
			"rescues": float(rescues[peer_id]),
			"objectives": float(objectives[peer_id]),
			"share": share,
			"credits": int(round(pool * share)),
		})
	return results


func _bind_peer(peer_id: int) -> void:
	var key := _key_for(peer_id)
	_peer_keys[peer_id] = key
	if not _bank.has(key):
		_bank[key] = {"credits": 0, "unlocks": []}


func _key_for(peer_id: int) -> String:
	var steam_id := Net.player_steam_id(peer_id)
	if steam_id != 0:
		return "steam:%d" % steam_id
	return "name:%s" % Net.player_name(peer_id)


func _add_credits(peer_id: int, amount: int) -> void:
	_bind_peer(peer_id)
	var key: String = _peer_keys[peer_id]
	var record: Dictionary = _bank[key]
	record["credits"] = maxi(int(record.get("credits", 0)) + amount, 0)
	_bank[key] = record
	credits_changed.emit(peer_id, int(record["credits"]))


func _save() -> void:
	var directory := DirAccess.open("user://")
	if directory != null and not directory.dir_exists("saves"):
		var make_error := directory.make_dir("saves")
		if make_error != OK:
			push_error("[Campaign] could not create saves folder: %s" % error_string(make_error))
			return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[Campaign] could not write save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"lots_completed": _lots_completed,
		"players": _bank,
	}))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("[Campaign] could not read save: %s" % error_string(FileAccess.get_open_error()))
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data := parsed as Dictionary
	_lots_completed = int(data.get("lots_completed", 0))
	var players: Variant = data.get("players", {})
	if typeof(players) == TYPE_DICTIONARY:
		_bank = players


func _empty_stats() -> Dictionary:
	return {"leaves_cleared": 0.0, "rescues": 0.0, "objectives": 0.0}


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_purchase(item_id: String) -> void:
	if Net.is_host():
		_handle_purchase(multiplayer.get_remote_sender_id(), StringName(item_id))


@rpc("authority", "call_local", "reliable")
func _rpc_payout(results: Array, details: Dictionary) -> void:
	_last_settlement = details
	var typed: Array[Dictionary] = []
	for row: Variant in results:
		typed.append(row as Dictionary)
	payout_ready.emit(typed)


@rpc("authority", "call_local", "reliable")
func _rpc_progress(lots_completed: int) -> void:
	_lots_completed = lots_completed


@rpc("authority", "call_local", "reliable")
func _rpc_wallet(peer_id: int, amount: int, unlocks: PackedStringArray, lots_completed: int) -> void:
	# The wallet can arrive before the roster, and the save key needs the name or Steam id.
	if Net.player_name(peer_id) == "" and Net.player_steam_id(peer_id) == 0:
		_pending_wallets.append({
			"peer_id": peer_id,
			"amount": amount,
			"unlocks": Array(unlocks),
			"lots_completed": lots_completed,
		})
		return
	_apply_wallet(peer_id, amount, unlocks, lots_completed)


func _flush_wallet(peer_id: int) -> void:
	if Net.player_name(peer_id) == "" and Net.player_steam_id(peer_id) == 0:
		return
	var kept: Array[Dictionary] = []
	for row: Dictionary in _pending_wallets:
		if int(row["peer_id"]) != peer_id:
			kept.append(row)
			continue
		var pending_unlocks := PackedStringArray()
		for entry: Variant in row["unlocks"]:
			pending_unlocks.append(str(entry))
		_apply_wallet(peer_id, int(row["amount"]), pending_unlocks, int(row["lots_completed"]))
	_pending_wallets = kept


func _apply_wallet(peer_id: int, amount: int, unlocks: PackedStringArray, lots_completed: int) -> void:
	_lots_completed = lots_completed
	_bind_peer(peer_id)
	var key: String = _peer_keys[peer_id]
	var record: Dictionary = _bank.get(key, {"credits": 0, "unlocks": []})
	record["credits"] = amount
	var stored: Array = []
	for entry: String in unlocks:
		stored.append(entry)
	record["unlocks"] = stored
	_bank[key] = record
	credits_changed.emit(peer_id, amount)
	unlocks_changed.emit()
