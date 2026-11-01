extends Node

## Authority: host. --day-test checks the work day and the crew's rank
## (docs/SPINE.md): the clock starts at 7 AM, XP waits until bedtime, one
## sleeper of two doesn't end the day, two do, banked XP ranks the crew up with
## the unlocks it brings, rank gates the shop, quiet hours pay more, 2 AM closes
## the day, and the day and the XP are saved. A joined client named Target
## should report the same day and XP at the end ("day" in the probe report).
## Each step prints a [DayTest] line.

const _Ranks = preload("res://core/ranks.gd")

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _clock() == null or _own_player() == null:
		return
	_started = true
	_run()


func _run() -> void:
	var clock := _clock()
	var world := get_tree().get_first_node_in_group("world")
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < 8.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	await get_tree().create_timer(1.0).timeout
	var ok := true
	var two := Net.peer_ids().size() == 2
	print("[DayTest] a second player joined: %s" % two)
	ok = ok and two
	var morning := str(clock.call("clock_text")).begins_with("7:") and int(clock.get("day")) == 1
	print("[DayTest] day 1 starts at %s: %s" % [clock.call("clock_text"), morning])
	ok = ok and morning
	# XP earned during the day waits for bedtime.
	Campaign.add_xp(400, "test")
	var pending := Campaign.pending_xp() == 400 and Campaign.crew_tier() == 0
	print("[DayTest] 400 XP is pending, rank still %s: %s" % [_Ranks.title(Campaign.crew_tier()), pending])
	ok = ok and pending
	var blower_locked := not Campaign.is_for_sale(&"leaf_blower")
	print("[DayTest] the leaf blower isn't for sale at Rake Rookie I: %s" % blower_locked)
	ok = ok and blower_locked
	# Quiet hours pay more; 2 AM closes the day.
	_set_hour(clock, 22.0)
	var quiet := bool(clock.call("is_quiet_hours")) and absf(float(clock.call("pay_bonus")) - Constants.QUIET_HOURS_PAY_BONUS) < 0.001
	print("[DayTest] at %s it's quiet hours, +%d%% pay: %s" % [clock.call("clock_text"), int(float(clock.call("pay_bonus")) * 100.0), quiet])
	ok = ok and quiet
	_set_hour(clock, 26.5)
	var closed := bool(clock.call("is_closed")) and not bool(world.call("can_depart"))
	print("[DayTest] at %s the day is closed and Chefty stays put: %s" % [clock.call("clock_text"), closed])
	ok = ok and closed
	# One of two in bed doesn't end the day; both do.
	var summaries: Array = []
	clock.connect("day_ended", func(summary: Dictionary) -> void: summaries.append(summary))
	clock.call("request_sleep", true)
	await get_tree().create_timer(0.3).timeout
	var one_down := int(clock.get("day")) == 1 and bool(clock.call("is_sleeping", Net.local_peer_id()))
	print("[DayTest] one of two asleep, still day 1: %s" % one_down)
	ok = ok and one_down
	var other := _other_peer()
	clock.call("_handle_sleep", other, true)
	await get_tree().create_timer(0.5).timeout
	var next_day := int(clock.get("day")) == 2 and summaries.size() == 1 and (clock.get("sleepers") as Array).is_empty()
	print("[DayTest] both asleep: day %d, %d summary: %s" % [int(clock.get("day")), summaries.size(), next_day])
	ok = ok and next_day
	var tier := Campaign.crew_tier()
	var banked := Campaign.crew_xp() == 400 and Campaign.pending_xp() == 0 and tier == _Ranks.tier_for_xp(400) and tier == 2
	print("[DayTest] XP banked: %d, rank now %s: %s" % [Campaign.crew_xp(), _Ranks.title(tier), banked])
	ok = ok and banked
	var ups: Array = (summaries[0] as Dictionary).get("rank_ups", []) if not summaries.is_empty() else []
	var summary_ok := ups.size() == 2 and str((ups[1] as Dictionary).get("unlock", "")) == "shop:leaf_blower"
	print("[DayTest] the summary lists %d rank-ups, the last unlocking %s: %s" % [ups.size(), (ups[1] as Dictionary).get("unlock", "") if ups.size() > 1 else "?", summary_ok])
	ok = ok and summary_ok
	var blower_open := Campaign.is_for_sale(&"leaf_blower") and not Campaign.is_for_sale(&"lawn_mower")
	print("[DayTest] now the leaf blower is for sale and the mower isn't yet: %s" % blower_open)
	ok = ok and blower_open
	var morning_again := str(clock.call("clock_text")).begins_with("7:") and not bool(clock.call("is_closed"))
	print("[DayTest] day 2 starts at %s: %s" % [clock.call("clock_text"), morning_again])
	ok = ok and morning_again
	var saved: Dictionary = Campaign.call("_save_data")
	var save_ok := int((saved.get("day", {}) as Dictionary).get("number", 0)) == 2 and int((saved.get("crew", {}) as Dictionary).get("xp", 0)) == 400
	print("[DayTest] the save has day 2 and 400 XP: %s" % save_ok)
	ok = ok and save_ok
	# Give the client a moment to hear about the new day before the reports.
	await get_tree().create_timer(1.0).timeout
	result = {"ok": ok}
	print("[DayTest] all ok: %s" % ok)


## Host: move the clock to this hour of the day (7 to 26) by moving its start.
func _set_hour(clock: Node, hour: float) -> void:
	var seconds_per_minute := Constants.MINUTES_PER_HOUR * float(Net.dev_options().get("clock_scale"))
	clock.set("day_started_at", Net.server_time() - (hour - Constants.DAY_START_HOUR) * 60.0 * seconds_per_minute)


func _clock() -> Node:
	return get_tree().get_first_node_in_group("day_clock")


func _other_peer() -> int:
	for peer_id: int in Net.peer_ids():
		if peer_id != Net.local_peer_id():
			return peer_id
	return 0


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
