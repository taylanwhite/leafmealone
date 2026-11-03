extends Node

## Authority: host
## Credits, the rake upgrade, payout, and the save between jobs.
## OQ-005, OQ-006: one host function splits the pool with the workbook weights.

signal campaign_loaded
signal credits_changed(peer_id: int, credits: int)
signal unlocks_changed
signal job_stats_changed(peer_id: int)
signal payout_ready(results: Array[Dictionary])
signal rating_changed
## The crew's banked or pending XP changed (docs/SPINE.md, "Crew rank").
signal rank_changed

const _Ranks = preload("res://core/ranks.gd")
const _Economy = preload("res://core/economy.gd")
## The player's real save. Only a player's session (no dev, test or automation
## flag; net/command_line.gd is_dev_session()) ever reads or writes it.
const SAVE_PATH := "user://saves/campaign.json"
## Dev sessions keep their own save, so they never touch the real crew's cash,
## progress, or rating: one per port, so tests can run side by side
## (tools/ci_local.ps1), and DEV_SAVE_PATH when no --port was given.
const TEST_SAVE_PATH := "user://saves/campaign_test_%d.json"
const DEV_SAVE_PATH := "user://saves/campaign_dev.json"
const SAVE_VERSION := 1
const RAKE_UPGRADE := &"rake_tier_1"
const WHEELBARROW_UPGRADE := &"wheelbarrow_tier_1"
const RAKE_UPGRADE_2 := &"rake_tier_2"

var _job_stats: Dictionary = {}
var _bank: Dictionary = {}
var _peer_keys: Dictionary = {}
var _lots_completed: int = 0
var _job_open: bool = true
var _job_started_at: float = 0.0
var _last_settlement: Dictionary = {}
var _pending_wallets: Array[Dictionary] = []
## The homeowners' reviews of the last Constants.RATING_JOBS jobs, in stars.
var _ratings: Array = []
## The crew's rank: XP banked by sleeping, and XP earned today, banked tonight.
var _crew_xp: int = 0
var _pending_xp: int = 0
## Today so far, for the summary at bedtime: jobs, cash, stars, XP by reason.
var _day_tally: Dictionary = {}


func _ready() -> void:
	_load()
	if not Net.player_joined.is_connected(_on_player_joined):
		Net.player_joined.connect(_on_player_joined)
	if not Net.state_changed.is_connected(_on_net_state):
		Net.state_changed.connect(_on_net_state)
	campaign_loaded.emit()


## Back at the menu: forget whatever another host told us and reload our own
## save, so a crew joined as a client never ends up in this machine's save.
func _on_net_state(new_state: int) -> void:
	if new_state != Net.State.OFFLINE:
		return
	_job_stats.clear()
	_bank.clear()
	_peer_keys.clear()
	_pending_wallets.clear()
	_save_hooks.clear()
	_ratings.clear()
	_lots_completed = 0
	_crew_xp = 0
	_pending_xp = 0
	_day_tally = {}
	_job_open = true
	_last_settlement = {}
	_load()
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


## Workbook throughput multiplier for this player's rake. 1 until they buy the
## tune-up; The Leafinator (rake_tier_2) applies it again.
func rake_multiplier(peer_id: int) -> float:
	if peer_has_unlock(peer_id, RAKE_UPGRADE_2):
		return Balance.TOOL_THROUGHPUT_GROWTH_MULTIPLIER * Balance.TOOL_THROUGHPUT_GROWTH_MULTIPLIER
	if peer_has_unlock(peer_id, RAKE_UPGRADE):
		return Balance.TOOL_THROUGHPUT_GROWTH_MULTIPLIER
	return 1.0


## The crew's rating: the average of the homeowners' recent reviews, 0 to 5 stars,
## or 0 with no reviews yet.
func rating() -> float:
	if _ratings.is_empty():
		return 0.0
	var total := 0.0
	for stars: Variant in _ratings:
		total += float(stars)
	return total / float(_ratings.size())


## How many reviews the rating is built from.
func rating_count() -> int:
	return _ratings.size()


func lots_completed() -> int:
	return _lots_completed


func current_lot_index() -> int:
	return maxi(_lots_completed + 1, 1)


func job_stats(peer_id: int) -> Dictionary:
	if _job_stats.has(peer_id):
		return (_job_stats[peer_id] as Dictionary).duplicate()
	return _empty_stats()


## ---------------------------------------------------------------- crew rank

## The crew's tier from banked XP (core/ranks.gd). 0 is Rake Rookie I.
func crew_tier() -> int:
	var tier := _Ranks.tier_for_xp(_crew_xp)
	var floor_tier := int(Net.dev_options().get("rank"))
	return maxi(tier, floor_tier)


func crew_xp() -> int:
	return _crew_xp


func pending_xp() -> int:
	return _pending_xp


## Whether the crew's rank has reached this unlock ("shop:ladder", "hood:lakeside", ...).
func has_unlock(unlock: String) -> bool:
	return _Ranks.tier_of(unlock) <= crew_tier()


func has_perk(perk_id: String) -> bool:
	return _Ranks.tier_of("perk:" + perk_id) > 0 and has_unlock("perk:" + perk_id)


func is_feature_on(feature_id: String) -> bool:
	return _Ranks.tier_of("feature:" + feature_id) > 0 and has_unlock("feature:" + feature_id)


## Whether the shops sell this to the crew yet: the item's rank gate
## (core/catalog.gd gate_of, "shop:<id>" unless it says otherwise).
func is_for_sale(item_id: StringName) -> bool:
	return has_unlock(Catalog.gate_of(String(item_id)))


## Host only. XP earned now, banked when the crew sleeps.
func add_xp(amount: int, reason: String) -> void:
	if not Net.is_host() or amount <= 0:
		return
	_pending_xp += amount
	var by_reason: Dictionary = _day_tally.get("xp", {})
	by_reason[reason] = int(by_reason.get(reason, 0)) + amount
	_day_tally["xp"] = by_reason
	_rpc_rank.rpc(_crew_xp, _pending_xp)


## Host only, at bedtime: pending XP becomes banked. Returns how much.
func bank_xp() -> int:
	if not Net.is_host():
		return 0
	var banked := _pending_xp
	_crew_xp += _pending_xp
	_pending_xp = 0
	_rpc_rank.rpc(_crew_xp, _pending_xp)
	return banked


## Host only: what today added up to, then start a fresh tally.
func take_day_summary() -> Dictionary:
	var tally := _day_tally.duplicate(true)
	_day_tally = {}
	return tally


## Host only: add to one of today's day-summary counters ("raids", "caught", ...).
## The one entry point for counters kept outside this file (critic C18); the
## summary card and its quip read them (ui/day_summary.gd, Strings.summary_quip).
func note_day(key: String, amount: float) -> void:
	if Net.is_host():
		_tally(key, amount)


func _tally(key: String, amount: float) -> void:
	_day_tally[key] = float(_day_tally.get(key, 0.0)) + amount


# ---- nice boys: rescues, escapes and Annex B (R2 chunk 6; docs/GAME.md
# "Form 27-B, in Triplicate"). Host only; the save keeps visits and the best time.

## Visits to Annex B by player key, and the crew's best time out (0 = none yet).
var _annex: Dictionary = {"visits": {}, "best_s": 0.0}


## Host only. A friend got someone out: a bonk during the cite, an unbuckle, a
## co-signature at the Annex. Counts the rescues stat (BAL-20) and today's tally,
## and earns the crew XP_RESCUE (R2 chunk 2's constant; nothing until it exists).
func add_rescue(peer_id: int, cause: StringName) -> void:
	if not Net.is_host():
		return
	record_stat(peer_id, &"rescues", 1.0)
	_tally("rescues", 1.0)
	add_xp(int(_constant("XP_RESCUE", 0)), "rescue_%s" % String(cause))


## Host only. Spotted in a raid and never caught (driving:F reuses it for a lost pursuit).
func award_escape(_peer_id: int) -> void:
	if Net.is_host():
		add_xp(Constants.XP_ESCAPE, "escape")


## Host only. Another visit to Annex B; returns the visits after this one.
func note_annex_visit(peer_id: int) -> int:
	if not Net.is_host():
		return 0
	var visits: Dictionary = _annex.get("visits", {})
	var key := _key_for(peer_id)
	visits[key] = int(visits.get(key, 0)) + 1
	_annex["visits"] = visits
	_tally("annex_visits", 1.0)
	return int(visits[key])


## How many times this player has been to Annex B (saved).
func annex_visits(peer_id: int) -> int:
	return int((_annex.get("visits", {}) as Dictionary).get(_key_for(peer_id), 0))


## Host only. Out through the turnstile after this many seconds: today's best
## ("annex_best") and the crew's best ever.
func note_annex_time(_peer_id: int, seconds: float) -> void:
	if not Net.is_host() or seconds <= 0.0:
		return
	var today := float(_day_tally.get("annex_best", 0.0))
	if today <= 0.0 or seconds < today:
		_day_tally["annex_best"] = seconds
	var best := float(_annex.get("best_s", 0.0))
	if best <= 0.0 or seconds < best:
		_annex["best_s"] = seconds


## The crew's best time out of Annex B, 0 when nobody has been yet.
func annex_best(_peer_id: int = 0) -> float:
	return float(_annex.get("best_s", 0.0))


## The saved "annex" section as read (visits by key, best time), with defaults.
static func annex_from_save(section: Dictionary) -> Dictionary:
	var visits := {}
	var saved: Variant = section.get("visits", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for key: Variant in saved:
			visits[str(key)] = int(saved[key])
	return {"visits": visits, "best_s": maxf(float(section.get("best_s", 0.0)), 0.0)}


## A constant another chunk may add (core/constants.gd), or fallback until it does.
static func _constant(constant_name: String, fallback: Variant) -> Variant:
	return (Constants as Script).get_script_constant_map().get(constant_name, fallback)


## Ask the host to buy a stock tool or an upgrade at Homie Depot's counter. Kept
## for the old callers: with the Shops node (net/shops/shops.gd) it is a buy of
## one at Homie Depot, with all of Shops' checks (hours, distance, rank, cash).
## Only tools and upgrades, as the old counter sold; everything else goes
## through Shops.request_buy.
func request_purchase(item_id: StringName) -> void:
	var kind := str(Catalog.item(String(item_id)).get("kind", ""))
	if kind != "tool" and kind != "upgrade":
		return
	var shops := get_tree().get_first_node_in_group("shops")
	if shops != null:
		shops.call("request_buy", "homie_depot", String(item_id), 1)
	elif Net.is_host():
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
	# The homeowner's review, if they settled up.
	if details.has("mood"):
		var stars := int(Constants.MOOD_STARS.get(str(details["mood"]), 0))
		if stars > 0:
			details["stars"] = stars
			_ratings.append(stars)
			while _ratings.size() > Constants.RATING_JOBS:
				_ratings.pop_front()
	# On top: the quiet-hours bonus and the Lawnfather's stars (docs/SPINE.md).
	var bonus := _Ranks.pay_bonus(crew_tier())
	var clock := get_tree().get_first_node_in_group("day_clock")
	if clock != null:
		bonus += float(clock.call("pay_bonus"))
	if bonus > 0.0 and pool > 0.0:
		details["bonus"] = bonus
		pool *= 1.0 + bonus
	details["xp"] = _award_job_xp(fraction, details)
	_tally("jobs", 1.0)
	_tally("cash", pool)
	_tally("stars", float(details.get("stars", 0)))
	var town := get_tree().get_first_node_in_group("town")
	if town != null:
		# A first job for a new client pays extra XP; the receipt shows it all.
		details["xp"] = int(details["xp"]) + int(town.call("on_job_finished", fraction, details))
	var results := _split_pool(pool)
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null:
		telemetry.call("mark_job_finish", fraction, results)
	for row: Dictionary in results:
		_add_credits(int(row["peer_id"]), int(row["credits"]))
	_lots_completed += 1
	_job_open = false
	var heat := get_tree().get_first_node_in_group("heat")
	if heat != null:
		heat.call("on_job_finished")
	_job_stats.clear()
	_save()
	_rpc_payout.rpc(results, details)
	_rpc_progress.rpc(_lots_completed, _ratings)
	for peer_id: int in Net.peer_ids():
		_send_wallet(peer_id)


## Host: XP for a finished job, flat per piece of work, never per dollar, so a
## windfall can't skip ranks. Returns what was awarded.
func _award_job_xp(fraction: float, details: Dictionary) -> int:
	# Each task line is [task, percent done, pay] (homeowner._handle_talk).
	var task_done: Array = []
	for line: Variant in (details.get("tasks", []) as Array):
		if typeof(line) == TYPE_ARRAY and (line as Array).size() >= 2:
			task_done.append(float(line[1]) / 100.0)
	var amount := _Economy.job_xp(fraction, task_done, int(details.get("stars", 0)), Net.peer_ids().size())
	add_xp(amount, "jobs")
	return amount


func save_now() -> void:
	if Net.is_host():
		_save()


func mark_job_open() -> void:
	_job_open = true
	_job_stats.clear()
	_job_started_at = Net.server_time()
	_job_clock_started = false


## The crew reached the yard: the job's clock starts now, once per job (later
## arrivals, like a straggler's, don't reset the homeowner's patience).
func start_job_clock() -> void:
	if _job_clock_started:
		return
	_job_clock_started = true
	_job_started_at = Net.server_time()


var _job_clock_started: bool = false


func is_job_open() -> bool:
	return _job_open


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
	if peer_id != Net.local_peer_id():
		# Everyone already here, to the newcomer only: their unlocks show on every
		# peer (a crewmate's upgraded rake head, props/prop_looks.gd rake_tier).
		for other: int in Net.peer_ids():
			if other != peer_id and _peer_keys.has(other):
				_rpc_wallet.rpc_id(peer_id, other, credits(other), _unlock_list(other), _lots_completed)
		_rpc_progress.rpc_id(peer_id, _lots_completed, _ratings)
		_rpc_rank.rpc_id(peer_id, _crew_xp, _pending_xp)


func _send_wallet(peer_id: int) -> void:
	_rpc_wallet.rpc(peer_id, credits(peer_id), _unlock_list(peer_id), _lots_completed)


func _unlock_list(peer_id: int) -> PackedStringArray:
	var key: String = _peer_keys.get(peer_id, "")
	var unlocks: Array = (_bank.get(key, {}) as Dictionary).get("unlocks", [])
	var names := PackedStringArray()
	for entry: Variant in unlocks:
		names.append(str(entry))
	return names


## What an item costs (core/catalog.gd price: base tools from TOOL_PRICES times
## TOOL_TIER_PRICE, everything else from Constants.SHOP_PRICES). -1 for something
## nobody sells.
func price_of(item_id: StringName) -> int:
	return Catalog.price(String(item_id))


## Host: every tool someone in this session owns, at any tier (a used one
## counts). The crew brings them all to the job.
func crew_tools() -> PackedStringArray:
	var tools := PackedStringArray()
	for peer_id: int in Net.peer_ids():
		_bind_peer(peer_id)
		for tool_id: String in Constants.TOOL_PRICES:
			if tool_tier(peer_id, tool_id) >= Catalog.TIER_USED and not tools.has(tool_id):
				tools.append(tool_id)
	return tools


# ---- shops: the public wallet API. Every system that moves money or grants an
# owned item uses these (net/crew/hires.gd, net/shops/shops.gd), never the
# private _add_credits / _send_wallet.

## Host: take amount from a player and tell everyone. False (and nothing taken)
## when they're short, the amount is negative, or this isn't the host.
func charge(peer_id: int, amount: int) -> bool:
	if not Net.is_host() or amount < 0:
		return false
	_bind_peer(peer_id)
	if credits(peer_id) < amount:
		return false
	if amount > 0:
		_add_credits(peer_id, -amount)
		_send_wallet(peer_id)
	return true


## Host: give a player money and tell everyone.
func pay(peer_id: int, amount: int) -> void:
	if not Net.is_host() or amount <= 0:
		return
	_add_credits(peer_id, amount)
	_send_wallet(peer_id)


## Host: a player now owns this (a tool, a tier, a hat). Saves and tells everyone.
func grant_unlock(peer_id: int, unlock_id: String) -> void:
	if not Net.is_host() or unlock_id == "":
		return
	_bind_peer(peer_id)
	var key: String = _peer_keys[peer_id]
	var record: Dictionary = _bank[key]
	var unlocks: Array = record.get("unlocks", [])
	if not unlocks.has(unlock_id):
		unlocks.append(unlock_id)
	record["unlocks"] = unlocks
	_bank[key] = record
	_save()
	_send_wallet(peer_id)
	unlocks_changed.emit()


## The best tier of a tool this player owns: Catalog.TIER_NONE (-1), TIER_USED
## (0), TIER_STOCK (1), TIER_MK2 (2), or TIER_MK3 (3).
func tool_tier(peer_id: int, tool: String) -> int:
	for tier: int in [Catalog.TIER_MK3, Catalog.TIER_MK2, Catalog.TIER_STOCK, Catalog.TIER_USED]:
		if peer_has_unlock(peer_id, StringName(Catalog.tool_item(tool, tier))):
			return tier
	return Catalog.TIER_NONE


## The save key a player's cash and unlocks are kept under ("steam:<id>" or
## "name:<name>"). The same on every peer, from the roster, so other saved
## per-player state (Shops' looks) can key on it.
func key_of(peer_id: int) -> String:
	return _key_for(peer_id)


## The best tier of a tool anyone in this session owns: the crew brings the best one.
func crew_tool_tier(tool: String) -> int:
	var best := Catalog.TIER_NONE
	for peer_id: int in Net.peer_ids():
		best = maxi(best, tool_tier(peer_id, tool))
	return best


## Dev and tests only: give this peer every tool, as if bought.
func dev_grant_all_tools(peer_id: int) -> void:
	if not Net.is_host():
		return
	_bind_peer(peer_id)
	var key: String = _peer_keys[peer_id]
	var record: Dictionary = _bank[key]
	var unlocks: Array = record.get("unlocks", [])
	for tool_id: String in Constants.TOOL_PRICES:
		if not unlocks.has(tool_id):
			unlocks.append(tool_id)
	record["unlocks"] = unlocks
	_bank[key] = record
	_send_wallet(peer_id)
	unlocks_changed.emit()


## The old Homie Depot counter: stock tools and upgrades only. Tiers, supplies,
## snacks, and cosmetics go through the Shops node (net/shops/shops.gd).
func _handle_purchase(peer_id: int, item_id: StringName) -> void:
	var id := String(item_id)
	var kind := str(Catalog.item(id).get("kind", ""))
	if kind != "tool" and kind != "upgrade":
		return
	var price := price_of(item_id)
	if price < 0 or not is_for_sale(item_id):
		return
	_bind_peer(peer_id)
	if peer_has_unlock(peer_id, item_id):
		return
	var needs: Array = Catalog.item(id).get("needs", [])
	if not needs.is_empty() and not needs.any(func(need: Variant) -> bool: return peer_has_unlock(peer_id, StringName(str(need)))):
		return
	if not charge(peer_id, price):
		return
	grant_unlock(peer_id, id)


func _split_pool(pool: float) -> Array[Dictionary]:
	# Only the crew is paid: a dev session's observer (a watcher) took a floor
	# share of the job before (tools:crew, "Observer $3" on the payday card).
	var peers: Array[int] = []
	for peer_id: int in Net.peer_ids():
		if not Net.is_watcher(peer_id):
			peers.append(peer_id)
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


## Host only. Writes a temp file, keeps the last good save as .bak, then swaps
## the new one in, so a crash mid-write never loses the crew's progress.
func _save() -> void:
	if not Net.is_host():
		return
	var directory := DirAccess.open("user://")
	if directory != null and not directory.dir_exists("saves"):
		var make_error := directory.make_dir("saves")
		if make_error != OK:
			push_error("[Campaign] could not create saves folder: %s" % error_string(make_error))
			return
	var path := _save_path()
	if _refuse_write(path):
		return
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("[Campaign] could not write save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(_save_data()))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
		DirAccess.remove_absolute(path)
	var swap_error := DirAccess.rename_absolute(temp_path, path)
	if swap_error != OK:
		push_error("[Campaign] could not replace save: %s" % error_string(swap_error))


func _save_data() -> Dictionary:
	# Start from what was loaded, so sections this build doesn't know (a newer
	# build's, or a system that isn't running right now) survive the save.
	var data := _loaded.duplicate(true)
	data.merge({
		"version": maxi(SAVE_VERSION, int(_loaded.get("version", SAVE_VERSION))),
		"lots_completed": _lots_completed,
		"ratings": _ratings,
		"players": _bank,
		# curve: which XP curve the banked XP is counted on, so a retune of
		# core/ranks.gd can carry it over on the next load (crew_xp_from_save).
		"crew": {"xp": _crew_xp, "pending": _pending_xp, "curve": _Ranks.CURVE_ID},
		# R2 chunk 6: Annex B visits by player key and the crew's best time out.
		"annex": _annex.duplicate(true),
	}, true)
	_save_hooks = _save_hooks.filter(func(hook: Callable) -> bool: return hook.is_valid())
	for extra: Callable in _save_hooks:
		var piece: Variant = extra.call()
		if typeof(piece) == TYPE_DICTIONARY:
			data.merge(piece as Dictionary, true)
	# What's written now is what a later load (and the next save) builds on.
	_loaded = data.duplicate(true)
	return data


## Other host systems (the town, the clock, the crew's rank) add their part of
## the save here; on load they read it back with save_section().
var _save_hooks: Array[Callable] = []
var _loaded: Dictionary = {}


func add_save_hook(hook: Callable) -> void:
	if not _save_hooks.has(hook):
		_save_hooks.append(hook)


## The world's systems take their hook with them when they leave (DayClock, Town).
func remove_save_hook(hook: Callable) -> void:
	_save_hooks.erase(hook)


## A top-level section of the loaded save, or an empty dictionary.
func save_section(key: String) -> Dictionary:
	var section: Variant = _loaded.get(key, {})
	return section as Dictionary if typeof(section) == TYPE_DICTIONARY else {}


## The save this run reads and writes. Any dev, test or automation session (any
## user flag but --host, --join=, --name=, --no-steam and --town-map, a headless
## display or a Movie Maker run) gets a test save; only a player's session, debug
## build or not, gets the real one. Engine-only flags such as --fixed-fps or
## --quit-after are invisible to scripts and don't count (command_line.gd).
func save_path() -> String:
	var options := Net.dev_options()
	return resolve_save_path(bool(options.call("is_dev_session")), bool(options.get("port_given")), int(options.get("port")))


func _save_path() -> String:
	return save_path()


static func resolve_save_path(dev_session: bool, port_given: bool, port: int) -> String:
	if not dev_session:
		return SAVE_PATH
	return TEST_SAVE_PATH % port if port_given else DEV_SAVE_PATH


## True when a write to this path must not happen: a dev session aimed at the
## real save (or its .tmp or .bak).
static func write_forbidden(path: String, dev_session: bool) -> bool:
	if not dev_session:
		return false
	var real := ProjectSettings.globalize_path(SAVE_PATH).simplify_path().to_lower()
	return ProjectSettings.globalize_path(path).simplify_path().to_lower().begins_with(real)


## The loud guard: a dev session that ever resolves the real save refuses to write it.
func _refuse_write(path: String) -> bool:
	var options := Net.dev_options()
	if not write_forbidden(path, bool(options.call("is_dev_session"))):
		return false
	push_error("[Campaign] REFUSED to write the player's real save (%s) from a dev session (%s). Dev and test runs use %s." % [
		path, ", ".join(options.call("dev_session_reasons")), resolve_save_path(true, bool(options.get("port_given")), int(options.get("port")))])
	return true


func _load() -> void:
	_loaded = {}
	_annex = annex_from_save({})
	var data := _read_save(_save_path())
	if data.is_empty():
		# A missing or broken save falls back to the last good copy.
		data = _read_save(_save_path() + ".bak")
	if data.is_empty():
		return
	if int(data.get("version", 1)) > SAVE_VERSION:
		push_warning("[Campaign] save is from a newer build (version %s); reading what this build knows" % str(data.get("version")))
	_loaded = data
	_lots_completed = int(data.get("lots_completed", 0))
	var ratings: Variant = data.get("ratings", [])
	if typeof(ratings) == TYPE_ARRAY:
		_ratings.clear()
		for stars: Variant in ratings:
			_ratings.append(int(stars))
	var players: Variant = data.get("players", {})
	if typeof(players) == TYPE_DICTIONARY:
		_bank = players
	var crew := save_section("crew")
	_crew_xp = crew_xp_from_save(crew)
	if _crew_xp != int(crew.get("xp", 0)):
		print("[Campaign] banked XP moved from curve %s to %s: %d -> %d, still %s" % [
			str(crew.get("curve", _Ranks.LEGACY_CURVE_ID)), _Ranks.CURVE_ID, int(crew.get("xp", 0)), _crew_xp,
			_Ranks.title(_Ranks.tier_for_xp(_crew_xp))])
	# Pending XP is today's, not yet banked on any curve's tiers: kept as it is.
	_pending_xp = int(crew.get("pending", 0))
	_annex = annex_from_save(save_section("annex"))


## The banked XP a saved "crew" section holds, on today's XP curve. A save banked
## under another curve (crew.curve; a save from before the key is on
## Ranks.LEGACY_CURVE_ID) keeps its tier and how far into it the crew was
## (core/economy.gd migrate_xp), so a retune never costs anyone a rank. The next
## save writes today's curve.
static func crew_xp_from_save(crew: Dictionary) -> int:
	var xp := int(crew.get("xp", 0))
	var curve := str(crew.get("curve", _Ranks.LEGACY_CURVE_ID))
	return _Economy.migrate_xp(xp, curve, _Ranks.CURVE_ID)


func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[Campaign] could not read save: %s" % error_string(FileAccess.get_open_error()))
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[Campaign] save at %s is unreadable" % path)
		return {}
	return parsed as Dictionary


func _empty_stats() -> Dictionary:
	return {"leaves_cleared": 0.0, "rescues": 0.0, "objectives": 0.0}


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_purchase(item_id: String) -> void:
	if not Net.is_host():
		return
	var shops := get_tree().get_first_node_in_group("shops")
	if shops != null:
		shops.call("host_buy", multiplayer.get_remote_sender_id(), "homie_depot", item_id, 1)
	else:
		_handle_purchase(multiplayer.get_remote_sender_id(), StringName(item_id))


@rpc("authority", "call_local", "reliable")
func _rpc_payout(results: Array, details: Dictionary) -> void:
	_last_settlement = details
	var typed: Array[Dictionary] = []
	for row: Variant in results:
		typed.append(row as Dictionary)
	payout_ready.emit(typed)


@rpc("authority", "call_local", "reliable")
func _rpc_rank(xp: int, pending: int) -> void:
	_crew_xp = xp
	_pending_xp = pending
	rank_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_progress(lots_completed: int, ratings: Array) -> void:
	_lots_completed = lots_completed
	_ratings = ratings.duplicate()
	rating_changed.emit()


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
