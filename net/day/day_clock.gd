extends Node

## Authority: host. The work day (docs/SPINE.md, "Work days"). The host owns the
## day number and the server time the day began; every peer works out the hour
## from Net.server_time(), so the clock reads the same everywhere with nothing
## sent per frame. The day starts at 7:00 AM and the clock stops at 2:00 AM
## until the crew sleeps on the cots at the store (props/cot.gd). Sleeping
## banks the day's XP (Campaign), regrows the town (net/town/town.gd), saves,
## and shows the day's summary.

signal day_started(day: int)
signal day_ended(summary: Dictionary)
signal sleepers_changed

const _Ranks = preload("res://core/ranks.gd")
const _Seasons = preload("res://core/seasons.gd")
const _Strings = preload("res://ui/strings.gd")

## Day number, 1 on a new campaign.
var day: int = 1
## Server time at 7:00 AM of this day.
var day_started_at: float = 0.0
## Peers lying on a cot right now, and which cot each one has (peer -> 0..3).
var sleepers: Array[int] = []
var cots: Dictionary = {}

var _force_hold: float = 0.0
var _ending: bool = false


func _ready() -> void:
	add_to_group("day_clock")
	Net.player_left.connect(_on_player_left)
	Net.player_joined.connect(_on_player_joined)
	if Net.is_host():
		var saved := Campaign.save_section("day")
		day = maxi(1, int(saved.get("number", 1)))
		if int(Net.dev_options().get("start_day")) > 0:
			day = int(Net.dev_options().get("start_day"))
		var minutes := clampf(float(saved.get("minutes", 0.0)), 0.0, _end_minutes())
		var start_hour := float(Net.dev_options().get("start_hour"))
		if start_hour >= 0.0:
			minutes = clampf((start_hour - Constants.DAY_START_HOUR) * 60.0, 0.0, _end_minutes())
		day_started_at = Net.server_time() - minutes * _seconds_per_minute()
		Campaign.add_save_hook(_save_section)
		_Seasons.apply_look(day)
	elif multiplayer.multiplayer_peer != null:
		_rpc_request_state.rpc_id(1)


func _exit_tree() -> void:
	Campaign.remove_save_hook(_save_section)


## In-game minutes since 7:00 AM, stopped at 2:00 AM.
func minutes() -> float:
	var elapsed := (Net.server_time() - day_started_at) / _seconds_per_minute()
	return clampf(elapsed, 0.0, _end_minutes())


## The hour of the clock face, 7.0 to 26.0 (26 is 2:00 AM).
func hour() -> float:
	return Constants.DAY_START_HOUR + minutes() / 60.0


## "7:45 AM"
func clock_text() -> String:
	var total := int(minutes()) + int(Constants.DAY_START_HOUR * 60.0)
	var hours := (total / 60) % 24
	var mins := total % 60
	# Quarter hours, so the face doesn't flicker every real second.
	mins = mins - mins % 15
	var suffix := "AM" if hours < 12 else "PM"
	var face := hours % 12
	if face == 0:
		face = 12
	return "%d:%02d %s" % [face, mins, suffix]


func is_quiet_hours() -> bool:
	return hour() >= Constants.QUIET_HOURS_START


## Past 2:00 AM: no new jobs until the crew sleeps.
func is_closed() -> bool:
	return minutes() >= _end_minutes()


## The season today (core/seasons.gd): 0 autumn, 1 winter, 2 spring, 3 summer.
func season() -> int:
	return _Seasons.of_day(day)


## What a job pays on top, right now: the season's bonus, and the quiet-hours
## bonus with the night-owl perks.
func pay_bonus() -> float:
	var seasonal := float(_Seasons.PAY_BONUS[season()])
	if not is_quiet_hours():
		return seasonal
	var bonus := seasonal + Constants.QUIET_HOURS_PAY_BONUS
	if Campaign.has_perk("night_owl"):
		bonus += Constants.NIGHT_OWL_PAY_BONUS
	if Campaign.has_perk("night_owl_2"):
		bonus += Constants.NIGHT_OWL_PAY_BONUS
	return bonus


## How much faster noise raises heat right now.
func heat_scale() -> float:
	return Constants.QUIET_HOURS_HEAT_SCALE if is_quiet_hours() else 1.0


## Bedtime: from Constants.SLEEP_FROM_HOUR (6 PM) until the clock stops.
func can_sleep_now() -> bool:
	return hour() >= Constants.SLEEP_FROM_HOUR


func is_sleeping(peer_id: int) -> bool:
	return sleepers.has(peer_id)


## The cot this sleeper has, or -1.
func cot_of(peer_id: int) -> int:
	return int(cots.get(peer_id, -1))


## The local player lies down on a cot (the one pressed, if it's free) or gets up.
func request_sleep(lying_down: bool, cot: int = -1) -> void:
	if Net.is_host():
		_handle_sleep(Net.local_peer_id(), lying_down, cot)
	else:
		_rpc_request_sleep.rpc_id(1, lying_down, cot)


## Host: end the day now, whoever is in bed (the host held E, or a test).
func force_sleep() -> void:
	if Net.is_host():
		_end_day()


## Host, tests only: set the clock to this hour (7 to 26) of the same day and
## tell every peer, through the same state RPC a late joiner gets.
func set_hour_for_tests(target_hour: float) -> void:
	if not Net.is_host():
		return
	var at := clampf((target_hour - Constants.DAY_START_HOUR) * 60.0, 0.0, _end_minutes())
	day_started_at = Net.server_time() - at * _seconds_per_minute()
	_rpc_state.rpc(day, day_started_at, sleepers, cots)


## Host, every frame the host holds E on a cot: three seconds drags everyone to bed.
func hold_force(delta: float) -> float:
	if not Net.is_host():
		return 0.0
	_force_hold += delta
	if _force_hold >= Constants.SLEEP_FORCE_SECONDS:
		_force_hold = 0.0
		_end_day()
	return _force_hold / Constants.SLEEP_FORCE_SECONDS


func release_force() -> void:
	_force_hold = 0.0


# ---------------------------------------------------------------- host

func _handle_sleep(peer_id: int, lying_down: bool, cot: int = -1) -> void:
	if lying_down and not sleepers.has(peer_id):
		# Not while a job is on: the crew has to be back at the store.
		if Net.player_zone(peer_id) != Net.Zone.STORE:
			return
		# And not before evening, or a crew could skip days to reroll the jobs.
		if not can_sleep_now():
			return
		var taken: Array = cots.values()
		if cot < 0 or cot >= Constants.COT_SPOTS.size() or taken.has(cot):
			cot = -1
			for index: int in Constants.COT_SPOTS.size():
				if not taken.has(index):
					cot = index
					break
		if cot < 0:
			return
		sleepers.append(peer_id)
		cots[peer_id] = cot
	elif not lying_down:
		sleepers.erase(peer_id)
		cots.erase(peer_id)
	_rpc_sleepers.rpc(sleepers, cots)
	if not sleepers.is_empty() and sleepers.size() >= Net.peer_ids().size():
		_end_day()


## Everyone is back at the store: nobody's mid-job, in the van, or crossing.
func everyone_home() -> bool:
	for peer_id: int in Net.peer_ids():
		if Net.player_zone(peer_id) != Net.Zone.STORE:
			return false
	return true


func _end_day() -> void:
	if _ending or not everyone_home():
		return
	_ending = true
	_tow_chefty()
	var tier_before := Campaign.crew_tier()
	var banked := Campaign.bank_xp()
	var tier_after := Campaign.crew_tier()
	var unlocked: Array = []
	for tier: int in range(tier_before + 1, tier_after + 1):
		# extras: what else the tier brings (core/ranks.gd EXTRA_UNLOCKS).
		var extras: Array = Array(_Ranks.unlocks_at(tier))
		extras.erase(_Ranks.unlock_at(tier))
		unlocked.append({"tier": tier, "title": _Ranks.title(tier), "unlock": _Ranks.unlock_at(tier), "extras": extras})
	var summary := Campaign.take_day_summary()
	summary["day"] = day
	summary["xp_banked"] = banked
	summary["tier"] = tier_after
	summary["title"] = _Ranks.title(tier_after)
	summary["rank_ups"] = unlocked
	if _Seasons.turns_on(day + 1):
		summary["season"] = _Strings.SEASON_ARRIVALS[_Seasons.of_day(day + 1)]
	# Payroll first, so a hand who quits isn't counted on tomorrow.
	var hires := get_tree().get_first_node_in_group("hires")
	if hires != null:
		summary["wages"] = hires.call("pay_wages")
	var town := get_tree().get_first_node_in_group("town")
	if town != null:
		summary["town"] = town.call("on_new_day", day + 1)
	day += 1
	day_started_at = Net.server_time()
	sleepers.clear()
	cots.clear()
	Campaign.save_now()
	_rpc_day.rpc(day, day_started_at, summary)
	_ending = false


## Host, at bedtime in the connected town: Chefty was left out in town, so Marty
## tows it back to the TruckPad for Constants.CHEFTY_TOW_FEE, split across the
## crew like wages (each pays their share, or what they have), and texts about it.
func _tow_chefty() -> void:
	var chefty := get_tree().get_first_node_in_group("chefty")
	if chefty == null or not chefty.has_method("host_tow_home") or not bool(chefty.call("host_tow_home")):
		return
	var peers := Net.peer_ids()
	if peers.is_empty():
		return
	var share := ceili(float(Constants.CHEFTY_TOW_FEE) / float(peers.size()))
	for peer_id: int in peers:
		Campaign.charge(peer_id, mini(share, Campaign.credits(peer_id)))
	var town := get_tree().get_first_node_in_group("town")
	if town != null and not _Strings.TOW_TEXTS.is_empty():
		var line := _Strings.TOW_TEXTS[posmod(day, _Strings.TOW_TEXTS.size())] % Constants.CHEFTY_TOW_FEE
		town.call("_text", _Strings.UI["clerk_name"], "tow", line, -1)


func _save_section() -> Dictionary:
	return {"day": {"number": day, "minutes": minutes()}}


func _end_minutes() -> float:
	return (Constants.DAY_CLOSE_HOUR - Constants.DAY_START_HOUR) * 60.0


func _seconds_per_minute() -> float:
	return Constants.MINUTES_PER_HOUR * 60.0 / 60.0 * float(Net.dev_options().get("clock_scale"))


func _on_player_left(peer_id: int) -> void:
	if not Net.is_host():
		return
	if sleepers.has(peer_id):
		sleepers.erase(peer_id)
		cots.erase(peer_id)
		_rpc_sleepers.rpc(sleepers, cots)
	# The last one awake left: everyone still here is asleep.
	_check_all_asleep.call_deferred()


func _check_all_asleep() -> void:
	if not sleepers.is_empty() and sleepers.size() >= Net.peer_ids().size():
		_end_day()


func _on_player_joined(peer_id: int) -> void:
	if Net.is_host() and peer_id != Net.local_peer_id():
		_rpc_state.rpc_id(peer_id, day, day_started_at, sleepers, cots)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if Net.is_host():
		_rpc_state.rpc_id(multiplayer.get_remote_sender_id(), day, day_started_at, sleepers, cots)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_sleep(lying_down: bool, cot: int) -> void:
	if Net.is_host():
		_handle_sleep(multiplayer.get_remote_sender_id(), lying_down, cot)


@rpc("authority", "call_remote", "reliable")
func _rpc_state(number: int, started_at: float, lying: Array, cot_map: Dictionary) -> void:
	day = number
	_Seasons.apply_look(day)
	day_started_at = started_at
	sleepers.assign(lying)
	cots = cot_map
	sleepers_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_sleepers(lying: Array, cot_map: Dictionary) -> void:
	sleepers.assign(lying)
	cots = cot_map
	sleepers_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_day(number: int, started_at: float, summary: Dictionary) -> void:
	day = number
	_Seasons.apply_look(day)
	day_started_at = started_at
	sleepers.clear()
	cots.clear()
	sleepers_changed.emit()
	day_ended.emit(summary)
	day_started.emit(number)
