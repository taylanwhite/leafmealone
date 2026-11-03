extends Node

## Authority: host. --annex-test (CI port 7830, a client named Target joined, both
## with --sim-lag=150): Satellite Annex B (net/annex/annex.gd, R2 chunk 6) through
## the real requests, the client's own player standing where a person would.
##   1. the schedule: the same 200-sample fingerprint on both peers for three
##      seeds, and the never-wait guarantee over 200 seeds x the three serving
##      windows (no "looking but not serving" stretch over ANNEX_MAX_IDLE, one
##      window always open, each open at least ANNEX_MIN_OPEN_SHARE)
##   2. a visit begins for the client: it's walked in, holds its form, and the
##      host and client agree on the form and the windows
##   3. a served window stamps the next box; the wrong window shakes his head
##      and costs time, no stamp
##   4. a self-stamp while the clerk looks away stamps; one under his eyes adds a
##      carbon box
##   5. a bell turns the clerk to his cabinet and leans his neighbour, on both peers
##   6. Window D fills the form in one volley; the Head NICE BOY approves it
##   7. the big stamp: the client lifts it and approves itself; the host (a
##      visitor through the legacy Courtesy Desk door) approves its friend; seen
##      off its pad it goes back and the holder loses approval and one box
##   8. co-signing fills the rider's next box and counts a rescue
##   9. the turnstile bounces an unapproved form and lets an approved one
##      through; the rider goes home, and the receipt is deterministic and $0.00
##  10. closing time approves everyone AFTER HOURS and gets them out; a finisher
##      waiting for the group goes home when the last rider inside disconnects
##  11. a solo rider played by the schedule (the bot's rules) finishes in under 120 s
##  12. the annex save section reads back the same; a late joiner's snapshot
##      matches and doesn't walk riders who are inside back to the threshold;
##      a disconnect ends the Annex; both peers dress the Annex's
##      players alike (0.4.5's host saw white outfits there)
## The grey-box set (net/annex/annex_greybox.gd) stands in for R2 chunk 5's set
## until it's built; the checks only use the C9 node names. Each step prints an
## [AnnexTest] line.

const _Schedule = preload("res://net/annex/annex_schedule.gd")
const _Form = preload("res://net/annex/form_state.gd")
const _Receipt = preload("res://net/annex/receipt_lines.gd")
const _AnnexScript = preload("res://net/annex/annex.gd")
const SEEDS_TO_CHECK: int = 200
const RAID_SEED: int = 31337
## How long a step waits for the host's answer to come back (150 ms each way, and a resend).
const SETTLE: float = 1.2

static var result: Dictionary = {}

var _started: bool = false
var _problems: Array[String] = []
var _passed: Dictionary = {}


func _process(_delta: float) -> void:
	if _started or not Net.is_host():
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null or get_tree().get_first_node_in_group("annex") == null:
		return
	_started = true
	_run()


func _run() -> void:
	var waited := 0.0
	while (_client() == 0 or _player(_client()) == null) and waited < 20.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var client := _client()
	if client == 0:
		_finish(["no client joined"])
		return
	await get_tree().create_timer(1.5).timeout
	var annex := _annex()
	var director := get_tree().get_first_node_in_group("run_director")
	# 1. The schedule.
	var seeds := [1, 77, 4242]
	annex.call("dev_client", client, "report", [seeds])
	var report: Dictionary = await _report(annex)
	var mine := []
	for entry: int in seeds:
		mine.append(_Schedule.hash_samples(entry, 200))
	_check("1 the schedule's fingerprint is the same on both peers", report.get("hashes", []) == mine, "client %s, host %s" % [report.get("hashes", []), mine])
	var guarantee := _never_wait()
	_check("1 the never-wait guarantee over %d seeds" % SEEDS_TO_CHECK, guarantee.is_empty(), "; ".join(guarantee.slice(0, 4)))
	# 2. A visit begins for the client, the way the shuttle starts one.
	director.set("_hazard_seed", RAID_SEED)
	# A hot crew: four boxes on the form, room for every step below.
	var heat := get_tree().get_first_node_in_group("heat")
	if heat != null:
		heat.set("heat", Constants.ANNEX_BOXES_BY_HEAT[1] + 10.0)
	annex.call("begin", 1, [client], Net.server_time())
	var inside := await _until(func() -> bool: return str(annex.call("stage_of", client)) == "inside", Constants.ANNEX_GREETER_WALK + 3.0)
	await get_tree().create_timer(SETTLE).timeout
	annex.call("dev_client", client, "report", [])
	report = await _report(annex)
	var form: Dictionary = annex.call("form_of", client)
	_check("2 the client is walked in with Form 27-B on both peers", inside and Net.player_zone(client) == Net.Zone.BORDER and str(report.get("stage", "")) == "inside" and bool(report.get("form_view", false)) and _same_form(report.get("form", {}), form), "inside %s, zone %s, client sees %s / form view %s" % [inside, Net.Zone.keys()[Net.player_zone(client)], report.get("stage", ""), report.get("form_view", false)])
	_check("2 both peers have the same windows", _same_windows(annex, report), "client %s" % report.get("windows", {}))
	# 3. Served, then the wrong window.
	var window := _Form.next_window(form)
	var stamped := int(form["stamped"])
	_retime_to(annex, window, [_Schedule.S.OPEN], 3.0)
	_stand(client, _spot(annex, "Windows/%s/Counter" % window))
	var served := await _until(func() -> bool: return int((annex.call("form_of", client) as Dictionary)["stamped"]) > stamped, 8.0)
	_check("3 standing on window %s's counter gets the box stamped" % window, served, "stamped %d" % int((annex.call("form_of", client) as Dictionary)["stamped"]))
	form = annex.call("form_of", client)
	window = _Form.next_window(form)
	var wrong := _other_window(window)
	var wrongs := int(_AnnexScript.stats["wrong_windows"])
	stamped = int(form["stamped"])
	_retime_to(annex, wrong, [_Schedule.S.OPEN], 3.0)
	_stand(client, _spot(annex, "Windows/%s/Counter" % wrong))
	var shook := await _until(func() -> bool: return int(_AnnexScript.stats["wrong_windows"]) > wrongs, 4.0)
	await get_tree().create_timer(1.0).timeout
	_check("3 window %s (the wrong one) shakes his head and stamps nothing" % wrong, shook and int((annex.call("form_of", client) as Dictionary)["stamped"]) == stamped, "wrong windows %d, stamped %d" % [int(_AnnexScript.stats["wrong_windows"]), int((annex.call("form_of", client) as Dictionary)["stamped"])])
	# R2b: once per visit to his counter, not on a loop while you stand there.
	var shakes := int(_AnnexScript.stats["wrong_windows"])
	await get_tree().create_timer(Constants.ANNEX_WRONG_WINDOW * 2.5).timeout
	_check("3 still standing at the wrong window, he shakes his head only once", int(_AnnexScript.stats["wrong_windows"]) == shakes, "wrong windows %d -> %d" % [shakes, int(_AnnexScript.stats["wrong_windows"])])
	_stand(client, _spot(annex, "Threshold"))
	await get_tree().create_timer(0.6).timeout
	# 4. Heists.
	form = annex.call("form_of", client)
	window = _Form.next_window(form)
	stamped = int(form["stamped"])
	var away := _retime_to(annex, window, [_Schedule.S.PHONE, _Schedule.S.BREAK, _Schedule.S.ASLEEP, _Schedule.S.LUNCH_TURNED], 2.2)
	_stand(client, _spot(annex, "Windows/%s/StampPad" % window))
	await get_tree().create_timer(0.5).timeout
	annex.call("dev_client", client, "self_stamp", [window, true])
	var heisted := await _until(func() -> bool: return int((annex.call("form_of", client) as Dictionary)["stamped"]) > stamped, 3.0)
	annex.call("dev_client", client, "self_stamp", [window, false])
	_check("4 a self-stamp at window %s while he looks away stamps the box" % window, away and heisted, "found a moment %s, stamped %d" % [away, int((annex.call("form_of", client) as Dictionary)["stamped"])])
	form = annex.call("form_of", client)
	window = _Form.next_window(form)
	var boxes := (form["boxes"] as PackedStringArray).size()
	_retime_to(annex, window, [_Schedule.S.OPEN], 3.0)
	_stand(client, _spot(annex, "Windows/%s/StampPad" % window))
	await get_tree().create_timer(0.5).timeout
	annex.call("dev_client", client, "self_stamp", [window, true])
	var carbon := await _until(func() -> bool: return (((annex.call("form_of", client) as Dictionary)["boxes"]) as PackedStringArray).size() > boxes, 3.0)
	annex.call("dev_client", client, "self_stamp", [window, false])
	_check("4 a self-stamp under his eyes slides in a carbon box", carbon, "boxes %d -> %d" % [boxes, (((annex.call("form_of", client) as Dictionary)["boxes"]) as PackedStringArray).size()])
	# 5. A bell.
	_retime_both_open(annex, "A", "B")
	_stand(client, _spot(annex, "Windows/A/Bell"))
	await get_tree().create_timer(0.5).timeout
	annex.call("dev_client", client, "bell", ["A"])
	var turned := await _until(func() -> bool: return int((annex.call("window_now", "A") as Dictionary)["state"]) == _Schedule.S.CABINET, 3.0)
	await get_tree().create_timer(0.45).timeout
	annex.call("dev_client", client, "report", [])
	report = await _report(annex)
	var lean := int((annex.call("window_now", "B") as Dictionary)["state"]) == _Schedule.S.LEAN
	var client_sees: Dictionary = report.get("windows", {})
	_check("5 a bell turns A to his cabinet and leans B, on both peers", turned and lean and int(client_sees.get("A", -1)) == _Schedule.S.CABINET and int(client_sees.get("B", -1)) == _Schedule.S.LEAN, "host A %s B %s, client A %s B %s" % [_name(annex, "A"), _name(annex, "B"), client_sees.get("A", -1), client_sees.get("B", -1)])
	# 6. Window D, then the desk.
	_reset_form(annex, client, 1)
	var d_at := _Schedule.d_open_at(int(annex.call("seed_value")))
	annex.call("dev_retime", d_at + 0.4)
	_stand(client, _spot(annex, "Windows/D/Counter"))
	var volley := await _until(func() -> bool: return _Form.is_full(annex.call("form_of", client)), 5.0)
	_check("6 Window D stamps every remaining box in one volley", volley and int(_AnnexScript.stats["window_d"]) >= 1, "form %s" % annex.call("form_of", client))
	_retime_head(annex, _Schedule.S.DESK, 4.0)
	_stand(client, _spot(annex, "HeadDesk/DeskSpot"))
	var approved := await _until(func() -> bool: return bool((annex.call("form_of", client) as Dictionary)["approved"]), 5.0)
	_check("6 the Head NICE BOY approves a full form at his desk", approved, "form %s" % annex.call("form_of", client))
	# 7. The big stamp.
	_reset_form(annex, client, 1)
	_retime_head(annex, _Schedule.S.AWAY, 5.0)
	_stand(client, _spot(annex, "HeadDesk/Pad"), 0.7)
	await get_tree().create_timer(0.6).timeout
	annex.call("dev_client", client, "big", ["grab", 0])
	var holding := await _until(func() -> bool: return int(annex.call("big_stamp_holder")) == client, 3.0)
	annex.call("dev_client", client, "big", ["self", 0])
	var self_ok := await _until(func() -> bool: return bool((annex.call("form_of", client) as Dictionary)["approved"]), 3.0)
	_check("7 the client lifts the big stamp while he's away and approves itself", holding and self_ok, "holder %d, form %s" % [int(annex.call("big_stamp_holder")), annex.call("form_of", client)])
	annex.call("dev_client", client, "big", ["drop", 0])
	await _until(func() -> bool: return int(annex.call("big_stamp_holder")) == 0, 3.0)
	# The host visits through the Courtesy Desk (the legacy map's visitor door).
	var host := Net.local_peer_id()
	Net.move_player_to_zone(host, Net.Zone.STORE)
	await get_tree().create_timer(0.4).timeout
	var door: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("annex_doors"):
		door = node as Node3D
	if door != null:
		_player(host).call("apply_network_teleport", door.call("out_transform"))
		await get_tree().physics_frame
		annex.call("request_visit", str(door.name))
	var visiting := await _until(func() -> bool: return (annex.call("visitors") as Array).has(host) and Net.player_zone(host) == Net.Zone.BORDER, 3.0)
	_check("7 a free friend comes in through the visitor door", door != null and visiting, "door %s, visitors %s, zone %s" % [door != null, annex.call("visitors"), Net.Zone.keys()[Net.player_zone(host)]])
	_reset_form(annex, client, 1)
	_retime_head(annex, _Schedule.S.AWAY, 5.0)
	_place_host(_spot(annex, "HeadDesk/Pad"), 0.7)
	await get_tree().create_timer(0.3).timeout
	annex.call("_rpc_request_big_stamp", "grab", 0)
	var pad := _spot(annex, "HeadDesk/Pad")
	_stand(client, pad + Vector3(2.5, 0.0, 0.0), 0.0)
	await get_tree().create_timer(0.8).timeout
	var friend_at := _player(client).global_position
	_place_host(friend_at, 0.9)
	await get_tree().physics_frame
	annex.call("_rpc_request_big_stamp", "friend", client)
	var friend_ok := await _until(func() -> bool: return bool((annex.call("form_of", client) as Dictionary)["approved"]), 2.0)
	_check("7 a visitor holding the big stamp approves a friend's form", int(annex.call("big_stamp_holder")) == host and friend_ok, "holder %d, form %s" % [int(annex.call("big_stamp_holder")), annex.call("form_of", client)])
	_place_host(pad, 0.7)
	await get_tree().physics_frame
	annex.call("_rpc_request_big_stamp", "drop", 0)
	await _until(func() -> bool: return int(annex.call("big_stamp_holder")) == 0, 2.0)
	# Spotted: the client holds it when he comes back to his desk and sees it.
	_reset_form(annex, client, 2)
	_retime_head(annex, _Schedule.S.AWAY, 5.0)
	_stand(client, pad, 0.7)
	await get_tree().create_timer(0.6).timeout
	annex.call("dev_client", client, "big", ["grab", 0])
	await _until(func() -> bool: return int(annex.call("big_stamp_holder")) == client, 3.0)
	var before := int((annex.call("form_of", client) as Dictionary)["stamped"])
	var spotted_before := int(_AnnexScript.stats["spotted"])
	_retime_head(annex, _Schedule.S.DESK, 6.0)
	var desk := _spot(annex, "HeadDesk/DeskSpot")
	var out_dir := (desk - _spot(annex, "HeadDesk")).normalized()
	_stand(client, desk + out_dir * 2.5, 0.0)
	var spotted := await _until(func() -> bool: return int(_AnnexScript.stats["spotted"]) > spotted_before, 3.0)
	var returned := await _until(func() -> bool: return int(annex.call("big_stamp_holder")) == 0, Constants.ANNEX_SPOTTED_WALK + 2.0)
	var after: Dictionary = annex.call("form_of", client)
	_check("7 spotted off its pad, the big stamp goes back and the holder loses one box", spotted and returned and int(after["stamped"]) == before - 1 and not bool(after["approved"]), "spotted %s, back %s, stamped %d -> %d" % [spotted, returned, before, int(after["stamped"])])
	# 8. Co-signing.
	_reset_form(annex, client, 0)
	var rescues_before := float(Campaign.job_stats(host).get("rescues", 0.0))
	_place_host(_spot(annex, "CoSignSheet"), 0.8)
	await get_tree().physics_frame
	annex.call("_rpc_request_cosign", true)
	var cosigned := await _until(func() -> bool: return int((annex.call("form_of", client) as Dictionary)["stamped"]) == 1, Constants.ANNEX_COSIGN_HOLD + 2.0)
	annex.call("_rpc_request_cosign", false)
	_check("8 co-signing fills the rider's next box and counts a rescue", cosigned and float(Campaign.job_stats(host).get("rescues", 0.0)) > rescues_before, "form %s, rescues %s" % [annex.call("form_of", client), Campaign.job_stats(host).get("rescues", 0.0)])
	# 9. The turnstile.
	var bounces := int(_AnnexScript.stats["bounces"])
	_stand(client, _spot(annex, "Turnstile"), -0.6)
	await get_tree().create_timer(0.3).timeout
	annex.call("dev_client", client, "tray", [])
	var bounced := await _until(func() -> bool: return int(_AnnexScript.stats["bounces"]) > bounces, 3.0)
	_check("9 an unapproved form bounces off the turnstile", bounced, "bounces %d" % int(_AnnexScript.stats["bounces"]))
	var done_form: Dictionary = annex.call("form_of", client)
	done_form["stamped"] = (done_form["boxes"] as PackedStringArray).size()
	done_form["approved"] = true
	annex.call("dev_set_form", client, done_form)
	# In front of the tray, on the lobby side (it stands against the front wall).
	_stand(client, _spot(annex, "OutgoingTray"), -0.6)
	var dropped := await _until(func() -> bool: return bool((annex.call("form_of", client) as Dictionary).get("dropped", false)), 4.0)
	var through_before := int(_AnnexScript.stats["through"])
	_stand(client, _spot(annex, "Forecourt"), 0.0)
	var through := await _until(func() -> bool: return int(_AnnexScript.stats["through"]) > through_before, 3.0)
	var home := await _until(func() -> bool: return _going_home(client), Constants.ANNEX_FORECOURT_BEAT + Constants.ANNEX_RETURN_WAIT + 4.0)
	_check("9 an approved form goes in the tray, the turnstile lets the rider through, and they go home", dropped and through and home, "dropped %s, through %s, zone %s" % [dropped, through, Net.Zone.keys()[Net.player_zone(client)]])
	var stats := {"hid": 1, "window_d": 1, "carbon": 1}
	var receipt_a := _Receipt.lines(9, stats, 81.0, 0.0)
	_check("9 the receipt is deterministic, 4-6 lines and the time, $0.00", receipt_a == _Receipt.lines(9, stats, 81.0, 0.0) and receipt_a.size() >= 5 and receipt_a.size() <= 7 and _Receipt.total_line(stats).ends_with("$0.00"), "%s / %s" % [receipt_a, _Receipt.total_line(stats)])
	var ended := await _until(func() -> bool: return not bool(annex.call("is_active")), Constants.ANNEX_RETURN_WAIT + 4.0)
	_check("9 with everyone out and the visitor sent home, the Annex closes up", ended and Net.player_zone(host) != Net.Zone.BORDER, "active %s, host zone %s" % [annex.call("is_active"), Net.Zone.keys()[Net.player_zone(host)]])
	await _clear_return_vans(client)
	# 10. Closing time.
	annex.call("begin", 2, [client], Net.server_time())
	await _until(func() -> bool: return str(annex.call("stage_of", client)) == "inside", Constants.ANNEX_GREETER_WALK + 3.0)
	var outs_before := int(_AnnexScript.stats["closing_outs"])
	annex.call("dev_retime", Constants.ANNEX_CAP_SECONDS - 1.5)
	var after_hours := await _until(func() -> bool: return bool((annex.call("form_of", client) as Dictionary).get("after_hours", false)), 4.0)
	var closed_out := await _until(func() -> bool: return int(_AnnexScript.stats["closing_outs"]) > outs_before, Constants.ANNEX_CLOSING_OUT + 4.0)
	var gone := await _until(func() -> bool: return _going_home(client), Constants.ANNEX_FORECOURT_BEAT + Constants.ANNEX_RETURN_WAIT + 4.0)
	_check("10 closing time approves everyone AFTER HOURS and gets them out", after_hours and closed_out and gone, "after hours %s, let out %s, zone %s" % [after_hours, closed_out, Net.Zone.keys()[Net.player_zone(client)]])
	await _until(func() -> bool: return not bool(annex.call("is_active")), 4.0)
	await _clear_return_vans(client)
	# 10. Finishing as a group: the client is through and waits for the host,
	# who drops while still inside; the client goes home anyway and the Annex ends.
	annex.call("begin", 4, [client, host], Net.server_time())
	await _until(func() -> bool: return str(annex.call("stage_of", client)) == "inside" and str(annex.call("stage_of", host)) == "inside", Constants.ANNEX_GREETER_WALK + 3.0)
	var group_form: Dictionary = annex.call("form_of", client)
	group_form["stamped"] = (group_form["boxes"] as PackedStringArray).size()
	group_form["approved"] = true
	group_form["dropped"] = true
	annex.call("dev_set_form", client, group_form)
	_stand(client, _spot(annex, "Forecourt"), 0.0)
	var waiting := await _until(func() -> bool: return str(annex.call("stage_of", client)) == "through", 3.0)
	await get_tree().create_timer(Constants.ANNEX_RETURN_WAIT + 0.5).timeout
	var held := Net.player_zone(client) == Net.Zone.BORDER
	annex.call("_on_player_left", host)
	var released := await _until(func() -> bool: return _going_home(client), Constants.ANNEX_FORECOURT_BEAT + Constants.ANNEX_RETURN_WAIT + 4.0)
	var group_ended := await _until(func() -> bool: return not bool(annex.call("is_active")), 4.0)
	_check("10 a finisher waiting for the group goes home when the last one inside drops", waiting and held and released and group_ended, "through %s, waited %s, home %s, ended %s" % [waiting, held, released, group_ended])
	Net.move_player_to_zone(host, Net.Zone.STORE)
	await get_tree().create_timer(0.4).timeout
	# 11. A solo rider by the bot's rules.
	var pace := _solo_pace()
	var slowest := float(pace["slowest"])
	_check("11 a solo rider by the bot's rules finishes in under 120 s", slowest < 120.0, "slowest %.1f s" % slowest)
	# R2b: the visit has a pace, not just a ceiling (gap-specs nice_boys: 40-75 s solo).
	var mean := float(pace["mean"])
	_check("11 a solo visit takes %.0f-%.0f s on average" % [Constants.ANNEX_PACE_TARGET.x, Constants.ANNEX_PACE_TARGET.y], mean >= Constants.ANNEX_PACE_TARGET.x and mean <= Constants.ANNEX_PACE_TARGET.y, "mean %.1f s (fastest %.1f)" % [mean, float(pace["fastest"])])
	# 12. The save section, a late joiner, the looks, a disconnect.
	var saved: Dictionary = Campaign.call("_save_data")
	var section: Dictionary = saved.get("annex", {})
	var back: Dictionary = Campaign.call("annex_from_save", section)
	_check("12 the annex save section reads back the same", not section.is_empty() and back.get("visits", {}) == section.get("visits", {}) and is_equal_approx(float(back["best_s"]), float(section["best_s"])) and int(Campaign.call("annex_visits", client)) >= 2, "%s" % section)
	annex.call("begin", 3, [client], Net.server_time())
	await _until(func() -> bool: return str(annex.call("stage_of", client)) == "inside", Constants.ANNEX_GREETER_WALK + 3.0)
	var copy: Node = _AnnexScript.new()
	copy.name = "AnnexCopy"
	add_child(copy)
	copy.remove_from_group("annex")
	copy.remove_from_group("prompt_sources")
	copy.call("apply_snapshot", annex.call("snapshot"))
	await get_tree().create_timer(Constants.ANNEX_WALK_STAGE_DELAY + 0.1).timeout
	var snap_a: Dictionary = annex.call("snapshot")
	var snap_b: Dictionary = copy.call("snapshot")
	_check("12 a late joiner's snapshot rebuilds the same room", snap_a.get("roster") == snap_b.get("roster") and snap_a.get("seed") == snap_b.get("seed") and _same_form(snap_a["forms"].get(client, {}), snap_b["forms"].get(client, {})) and snap_a.get("stages") == snap_b.get("stages"), "%s vs %s" % [snap_a.get("roster"), snap_b.get("roster")])
	# A rider already inside isn't walked in again (staged at the threshold) on the late joiner's copy.
	var copy_walks := (copy.get("_walk_anchors") as Dictionary).size()
	var restaged := bool(_player(client).call("is_staged"))
	_check("12 a late joiner's copy leaves riders who are inside where they stand", copy_walks == 0 and not restaged, "walk anchors %d, client body staged %s" % [copy_walks, restaged])
	if restaged:
		_player(client).call("clear_staged")
	copy.queue_free()
	# The host comes to visit, so both peers dress two players at the Annex.
	Net.move_player_to_zone(host, Net.Zone.BORDER, &"AnnexSide")
	annex.call("add_visitor", host, {"zone": Net.Zone.STORE})
	await get_tree().create_timer(SETTLE).timeout
	annex.call("dev_client", client, "report", [])
	report = await _report(annex)
	var looks := _looks()
	_check("12 both peers dress everyone at the Annex alike", looks.size() == 2 and report.get("looks", {}) == looks, "host %s, client %s" % [looks, report.get("looks", {})])
	annex.call("_on_player_left", client)
	var dropped_out := await _until(func() -> bool: return not (annex.call("roster") as Array).has(client), 2.0)
	annex.call("_on_player_left", host)
	var closed := await _until(func() -> bool: return not bool(annex.call("is_active")), 2.0)
	_check("12 a rider's disconnect drops them, and an empty Annex ends", dropped_out and closed, "roster %s, active %s" % [annex.call("roster"), annex.call("is_active")])
	# Leave both at the Annex's door for the probes' looks (CI compares them).
	_finish(_problems)


# ---------------------------------------------------------------- the schedule checks


## The never-wait guarantee, walked over each seed's raw segments.
func _never_wait() -> Array[String]:
	var bad: Array[String] = []
	var cap := Constants.ANNEX_CAP_SECONDS
	for index: int in SEEDS_TO_CHECK:
		var seed_value := 1000 + index * 7919
		var lists := {}
		for window: String in Constants.ANNEX_SERVING_WINDOWS:
			lists[window] = _Schedule.segments(seed_value, window)
			var idle := 0.0
			var open := 0.0
			for seg: Array in lists[window]:
				var from := float(seg[0])
				var to := minf(float(seg[1]), cap)
				if from >= cap:
					break
				var info: Array = _Schedule.INFO[int(seg[2])]
				if bool(info[0]) and not bool(info[1]):
					idle += to - from
					if idle > Constants.ANNEX_MAX_IDLE + 0.001:
						bad.append("seed %d window %s idle %.2f s at %.1f" % [seed_value, window, idle, from])
				else:
					idle = 0.0
				if int(seg[2]) == _Schedule.S.OPEN:
					open += to - from
			if open / cap < Constants.ANNEX_MIN_OPEN_SHARE:
				bad.append("seed %d window %s open %.0f%%" % [seed_value, window, open / cap * 100.0])
		var t := 0.0
		while t < cap:
			var any := false
			for window: String in Constants.ANNEX_SERVING_WINDOWS:
				for seg: Array in lists[window]:
					if float(seg[0]) <= t and t < float(seg[1]):
						any = any or int(seg[2]) == _Schedule.S.OPEN
						break
			if not any:
				bad.append("seed %d: no window open at %.2f" % [seed_value, t])
				break
			t += 0.25
	return bad


## A solo rider by the bot's rules (net/dev/bot.gd _r2_annex_tick), played on
## the schedule alone: walk to the next box's window; get served when he's open,
## stamp it yourself when he's looking away, else wait; then the desk, then the
## tray. The slowest, fastest and mean of 40 seeds, in seconds from the walk-in,
## over the three heats a catch can come at (a box more each).
func _solo_pace() -> Dictionary:
	var slowest := 0.0
	var fastest := INF
	var total := 0.0
	for index: int in 40:
		var seed_value := 5000 + index * 104729
		var heat: float = [20.0, 50.0, 80.0][index % 3]
		var boxes := _Form.boxes_for(seed_value, 0, heat, Constants.ANNEX_SERVING_WINDOWS)
		# The walk-in and the hand-over, then across the lobby to the first window
		# (about 8 m), between windows about 3 s.
		var t := Constants.ANNEX_GREETER_WALK + Constants.ANNEX_FORM_HANDOFF_AT + Constants.ANNEX_FORM_RISE + 2.0
		for window: String in boxes:
			t += 3.0
			var done := false
			while not done and t < Constants.ANNEX_CAP_SECONDS:
				var state := _Schedule.window_state(seed_value, window, t)
				if bool(state["serving"]):
					t += Constants.ANNEX_SERVE_SECONDS + Constants.ANNEX_COUNTER_DWELL
					done = true
				elif not bool(state["looking"]) and not bool(_Schedule.window_state(seed_value, window, t + Constants.ANNEX_SELF_STAMP_HOLD)["looking"]):
					t += Constants.ANNEX_SELF_STAMP_HOLD + 0.6
					done = true
				else:
					t += 0.25
		t += 4.0
		while int(_Schedule.head_state(seed_value, t)["state"]) != _Schedule.S.DESK and t < Constants.ANNEX_CAP_SECONDS:
			t += 0.25
		t += Constants.ANNEX_HEAD_READ + OfficeProps.BigStamp.slam_lands_after() + 4.0
		slowest = maxf(slowest, t)
		fastest = minf(fastest, t)
		total += t
	var mean := total / 40.0
	print("[AnnexTest] a solo rider by the bot's rules: slowest of 40 seeds %.1f s, fastest %.1f, mean %.1f" % [slowest, fastest, mean])
	return {"slowest": slowest, "fastest": fastest, "mean": mean}


# ---------------------------------------------------------------- helpers


## Jump the Annex's clock to the next moment window is in one of states with at
## least lasting seconds of it left. Returns whether there was one.
func _retime_to(annex: Node, window: String, states: Array, lasting: float) -> bool:
	var seed_value := int(annex.call("seed_value"))
	var t := 4.0
	while t < Constants.ANNEX_CAP_SECONDS - 15.0:
		var state := _Schedule.window_state(seed_value, window, t)
		if states.has(int(state["state"])) and float(state["until"]) - t >= lasting:
			annex.call("dev_retime", t + 0.2)
			return true
		t += 0.25
	return false


func _retime_both_open(annex: Node, a: String, b: String) -> void:
	var seed_value := int(annex.call("seed_value"))
	var t := 4.0
	while t < Constants.ANNEX_CAP_SECONDS - 15.0:
		var sa := _Schedule.window_state(seed_value, a, t)
		var sb := _Schedule.window_state(seed_value, b, t)
		if int(sa["state"]) == _Schedule.S.OPEN and int(sb["state"]) == _Schedule.S.OPEN and float(sa["until"]) - t > 4.0 and float(sb["until"]) - t > 4.0:
			annex.call("dev_retime", t + 0.2)
			return
		t += 0.25


func _retime_head(annex: Node, state_value: int, lasting: float) -> void:
	var seed_value := int(annex.call("seed_value"))
	var t := 4.0
	while t < Constants.ANNEX_CAP_SECONDS - 15.0:
		var state := _Schedule.head_state(seed_value, t)
		if int(state["state"]) == state_value and float(state["until"]) - t >= lasting:
			annex.call("dev_retime", t + 0.2)
			return
		t += 0.25


func _reset_form(annex: Node, client: int, stamped: int) -> void:
	var form: Dictionary = annex.call("form_of", client)
	form["stamped"] = clampi(stamped, 0, (form["boxes"] as PackedStringArray).size())
	form["approved"] = false
	form["dropped"] = false
	annex.call("dev_set_form", client, form)


func _other_window(window: String) -> String:
	for other: String in Constants.ANNEX_SERVING_WINDOWS:
		if other != window:
			return other
	return "A"


## The client stands back from spot by back meters (toward the room), on the floor.
func _stand(client: int, spot: Vector3, back: float = 0.0) -> void:
	var body := _player(client)
	if body == null or spot == Vector3.INF:
		return
	var at := spot + Vector3(0.0, 0.1, back)
	body.call("send_teleport", Transform3D(Basis.IDENTITY, at))


func _place_host(spot: Vector3, back: float) -> void:
	var me := _player(Net.local_peer_id())
	if me != null and spot != Vector3.INF:
		me.call("apply_network_teleport", Transform3D(Basis.IDENTITY, spot + Vector3(0.0, 0.1, back)))


func _spot(annex: Node, path: String) -> Vector3:
	var set_root := get_tree().get_first_node_in_group("world").get_node_or_null("BorderZone/AnnexSet")
	var node := set_root.get_node_or_null(path) as Node3D if set_root != null else null
	if node == null:
		_problems.append("the set has no %s" % path)
		return Vector3.INF
	return node.global_position


func _report(annex: Node) -> Dictionary:
	var asked := Net.server_time()
	var waited := 0.0
	while waited < 4.0:
		var got: Dictionary = annex.get("dev_report")
		if float(got.get("received_at", -1.0)) >= asked:
			return got
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return {}


## On the way home: out of the BORDER zone, or (with chunk 4's Courtesy Shuttle)
## aboard the return van at the forecourt curb, which drives them home out of
## sight later (R2 integration).
func _going_home(peer_id: int) -> bool:
	if Net.player_zone(peer_id) != Net.Zone.BORDER:
		return true
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	return shuttle != null and not (shuttle.call("seat_info", peer_id) as Dictionary).is_empty()


## Between steps: a return van still carrying a rider home would move them out of
## the BORDER zone in the middle of the next step; it's sent away and they're put
## back at the store, the way they'd get home.
func _clear_return_vans(peer_id: int) -> void:
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if shuttle != null and shuttle.has_method("dev_reset"):
		shuttle.call("dev_reset")
	if Net.player_zone(peer_id) == Net.Zone.BORDER:
		Net.move_player_to_zone(peer_id, Net.Zone.STORE)
	await get_tree().create_timer(0.4).timeout


func _until(check: Callable, seconds: float) -> bool:
	var waited := 0.0
	while waited < seconds:
		if bool(check.call()):
			return true
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return bool(check.call())


func _same_form(a: Variant, b: Variant) -> bool:
	if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
		return false
	var fa: Dictionary = a
	var fb: Dictionary = b
	return int(fa.get("stamped", -1)) == int(fb.get("stamped", -2)) and Array(fa.get("boxes", [])) == Array(fb.get("boxes", [])) and bool(fa.get("approved", false)) == bool(fb.get("approved", false))


func _same_windows(annex: Node, report: Dictionary) -> bool:
	var theirs: Dictionary = report.get("windows", {})
	for window: String in Constants.ANNEX_WINDOWS:
		if int(theirs.get(window, -1)) != int((annex.call("window_now", window) as Dictionary)["state"]):
			# A boundary can fall between the report and now: look a little either side.
			var t := float(annex.call("elapsed"))
			var close := false
			for dt: float in [-0.4, -0.2, 0.2]:
				close = close or int(_Schedule.effective(int(annex.call("seed_value")), window, t + dt, annex.call("overrides"))["state"]) == int(theirs.get(window, -1))
			if not close:
				return false
	return true


func _name(annex: Node, window: String) -> String:
	return _Schedule.state_name(int((annex.call("window_now", window) as Dictionary)["state"]))


func _looks() -> Dictionary:
	var looks := {}
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node.get_node_or_null("Visual/CartoonBody")
		if body != null and Net.player_zone(str(node.name).to_int()) == Net.Zone.BORDER:
			looks[str(node.name)] = str(hash([body.get("shirt"), body.get("pants"), body.get("skin"), body.get("hair"), body.get("hat_style"), body.get("outfit")]))
	return looks


func _check(label: String, ok: bool, detail: String) -> void:
	_passed[label] = ok
	print("[AnnexTest] %s: %s (%s)" % [label, "ok" if ok else "FAIL", detail])
	if not ok:
		_problems.append("%s: %s" % [label, detail])


func _finish(problems: Array) -> void:
	result = {"ok": problems.is_empty(), "done": true, "steps": _passed.duplicate()}
	if not problems.is_empty():
		result["error"] = "; ".join(problems)
	print("[AnnexTest] all ok: %s" % problems.is_empty())


func _annex() -> Node:
	return get_tree().get_first_node_in_group("annex")


func _client() -> int:
	for peer_id: int in Net.peer_ids():
		if peer_id != Net.local_peer_id():
			return peer_id
	return 0


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null
