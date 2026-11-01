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

## Day number, 1 on a new campaign.
var day: int = 1
## Server time at 7:00 AM of this day.
var day_started_at: float = 0.0
## Peers lying on a cot right now.
var sleepers: Array[int] = []

var _force_hold: float = 0.0
var _ending: bool = false


func _ready() -> void:
	add_to_group("day_clock")
	Net.player_left.connect(_on_player_left)
	Net.player_joined.connect(_on_player_joined)
	if Net.is_host():
		var saved := Campaign.save_section("day")
		day = maxi(1, int(saved.get("number", 1)))
		var minutes := clampf(float(saved.get("minutes", 0.0)), 0.0, _end_minutes())
		var start_hour := float(Net.dev_options().get("start_hour"))
		if start_hour >= 0.0:
			minutes = clampf((start_hour - Constants.DAY_START_HOUR) * 60.0, 0.0, _end_minutes())
		day_started_at = Net.server_time() - minutes * _seconds_per_minute()
		Campaign.add_save_hook(_save_section)
	elif multiplayer.multiplayer_peer != null:
		_rpc_request_state.rpc_id(1)


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


## What a job pays on top, right now: the quiet-hours bonus, with the night-owl perks.
func pay_bonus() -> float:
	if not is_quiet_hours():
		return 0.0
	var bonus := Constants.QUIET_HOURS_PAY_BONUS
	if Campaign.has_perk("night_owl"):
		bonus += Constants.NIGHT_OWL_PAY_BONUS
	if Campaign.has_perk("night_owl_2"):
		bonus += Constants.NIGHT_OWL_PAY_BONUS
	return bonus


## How much faster noise raises heat right now.
func heat_scale() -> float:
	return Constants.QUIET_HOURS_HEAT_SCALE if is_quiet_hours() else 1.0


func is_sleeping(peer_id: int) -> bool:
	return sleepers.has(peer_id)


## The local player lies down or gets up.
func request_sleep(lying_down: bool) -> void:
	if Net.is_host():
		_handle_sleep(Net.local_peer_id(), lying_down)
	else:
		_rpc_request_sleep.rpc_id(1, lying_down)


## Host: end the day now, whoever is in bed (the host held E, or a test).
func force_sleep() -> void:
	if Net.is_host():
		_end_day()


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

func _handle_sleep(peer_id: int, lying_down: bool) -> void:
	if lying_down and not sleepers.has(peer_id):
		# Not while a job is on: the crew has to be back at the store.
		if Net.player_zone(peer_id) != Net.Zone.STORE:
			return
		sleepers.append(peer_id)
	elif not lying_down:
		sleepers.erase(peer_id)
	_rpc_sleepers.rpc(sleepers)
	if not sleepers.is_empty() and sleepers.size() >= Net.peer_ids().size():
		_end_day()


func _end_day() -> void:
	if _ending:
		return
	_ending = true
	var tier_before := Campaign.crew_tier()
	var banked := Campaign.bank_xp()
	var tier_after := Campaign.crew_tier()
	var unlocked: Array = []
	for tier: int in range(tier_before + 1, tier_after + 1):
		unlocked.append({"tier": tier, "title": _Ranks.title(tier), "unlock": _Ranks.unlock_at(tier)})
	var summary := Campaign.take_day_summary()
	summary["day"] = day
	summary["xp_banked"] = banked
	summary["tier"] = tier_after
	summary["title"] = _Ranks.title(tier_after)
	summary["rank_ups"] = unlocked
	var town := get_tree().get_first_node_in_group("town")
	if town != null:
		summary["town"] = town.call("on_new_day", day + 1)
	day += 1
	day_started_at = Net.server_time()
	sleepers.clear()
	Campaign.save_now()
	_rpc_day.rpc(day, day_started_at, summary)
	_ending = false


func _save_section() -> Dictionary:
	return {"day": {"number": day, "minutes": minutes()}}


func _end_minutes() -> float:
	return (Constants.DAY_CLOSE_HOUR - Constants.DAY_START_HOUR) * 60.0


func _seconds_per_minute() -> float:
	return Constants.MINUTES_PER_HOUR * 60.0 / 60.0 * float(Net.dev_options().get("clock_scale"))


func _on_player_left(peer_id: int) -> void:
	if Net.is_host() and sleepers.has(peer_id):
		sleepers.erase(peer_id)
		_rpc_sleepers.rpc(sleepers)


func _on_player_joined(peer_id: int) -> void:
	if Net.is_host() and peer_id != Net.local_peer_id():
		_rpc_state.rpc_id(peer_id, day, day_started_at, sleepers)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if Net.is_host():
		_rpc_state.rpc_id(multiplayer.get_remote_sender_id(), day, day_started_at, sleepers)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_sleep(lying_down: bool) -> void:
	if Net.is_host():
		_handle_sleep(multiplayer.get_remote_sender_id(), lying_down)


@rpc("authority", "call_remote", "reliable")
func _rpc_state(number: int, started_at: float, lying: Array) -> void:
	day = number
	day_started_at = started_at
	sleepers.assign(lying)
	sleepers_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_sleepers(lying: Array) -> void:
	sleepers.assign(lying)
	sleepers_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_day(number: int, started_at: float, summary: Dictionary) -> void:
	day = number
	day_started_at = started_at
	sleepers.clear()
	sleepers_changed.emit()
	day_ended.emit(summary)
	day_started.emit(number)
