extends Node

## --hide-test (R2 chunk 3, port 7828, host Tester plus a Target client, both
## with --hide-test). Both peers run this node; the host arranges each step and
## cues the client through this node's own RPCs, the client acts as a player
## would (player._toggle_hiding, the camera's look, holding secondary) and
## reports what its own screen did. Each step prints a [HideTest] line.
##
## 1. hedge: the client dives in. On the client its view is StageCam's hide shot,
##    which turns when it looks (no frozen view), the body moved along a path
##    (no tick over Constants.STAGE_MAX_STEP_METERS), the world is muffled;
##    on both peers its Visual is still in the tree but no body, head or
##    nameplate is drawn, and the host hears its voice through the muffle.
##    It peeks: peeking replicates. It looks hard left and comes out: the exit
##    is where the host said, clear of geometry, on the side it faced (unless
##    that side was blocked), along a path; the muffle is gone.
## 2. shed: the host and the client both get in: it holds two. The host leaves
##    first and the client keeps its place; only the door side lets anyone in.
## 3. bin: the host is in; the client's dive is refused and bonks it back
##    where it started, not hidden. Then the client vaults in itself (a live
##    view under the lid) and back out.
## 4. pile: the host rakes a pile, the client dives in (the hide shot again,
##    nothing drawn, the mound); the host bags the pile and the client is
##    turned out (PENDING_R1 when the leaf field has no bag-out hook).
## 5. the NICE BOYS (a chase, the crew held still and placed by hand): the
##    client hides unseen; peeking with a NICE BOY behind it raises no
##    suspicion, in front of it does; an inspection of an unseen still hider is
##    a near miss with a sticker (on both peers); an immune hider is never
##    found; a poke cut short frees the spot with no outcome; a dive he watches
##    is found, lifted out, and caught (with the R2
##    Encounter: GOTCHA; without it: the director's cohort).

const _HideSpot = preload("res://net/components/hide_spot.gd")
const _HideView = preload("res://player/hide_view.gd")
const CLIENT_WAIT_SECONDS: float = 30.0
const STEP_WAIT_SECONDS: float = 6.0
## The host waits a little longer for a report than the client waits for anything.
const REPORT_WAIT_SECONDS: float = 9.0
## A tick moving the body farther than this is a pop (R2 chunk 1's limit).
const MAX_STEP: float = Constants.STAGE_MAX_STEP_METERS
## The exit must land this close to where the host said.
const EXIT_SLACK: float = 0.45

static var result: Dictionary = {}

var _started: bool = false
var _steps: Dictionary = {}
var _problems: Array[String] = []
## Host: the client's reports by step.
var _reports: Dictionary = {}
## Client: per-tick displacement while tracking.
var _tracking: bool = false
var _last_at := Vector3.INF
var _max_step: float = 0.0


func _physics_process(_delta: float) -> void:
	if _tracking:
		var me := _me()
		if me != null:
			if _last_at != Vector3.INF:
				_max_step = maxf(_max_step, me.global_position.distance_to(_last_at))
			_last_at = me.global_position


func _process(_delta: float) -> void:
	if _started:
		return
	var lot := get_tree().get_first_node_in_group("job_lot")
	if lot == null or not bool(lot.get("is_generated")) or _me() == null or get_tree().get_nodes_in_group("hide_spots").size() < 3:
		return
	_started = true
	if Net.is_host():
		_run_host()
	else:
		# The client's yard is up: the host can start cueing.
		_rpc_report.rpc_id(1, "ready", {"ok": true})


# ---------------------------------------------------------------- host

func _run_host() -> void:
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < CLIENT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if Net.peer_ids().size() < 2:
		_finish_host("the Target client never joined")
		return
	var mate := _mate_id()
	waited = 0.0
	while (_player(mate) == null or Net.player_zone(mate) != Net.Zone.LOT or not _reports.has("ready")) and waited < CLIENT_WAIT_SECONDS * 2.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if not _reports.has("ready"):
		_finish_host("the Target client's yard never came up")
		return
	await get_tree().create_timer(1.5).timeout
	var hedge := _spot("hedge")
	var shed := _spot("shed")
	var bin := _spot("bin")
	if hedge == null or shed == null or bin == null:
		_finish_host("the yard is missing a hedge, shed or bin")
		return
	await _hedge_step(hedge, mate)
	await _shed_step(shed, mate)
	await _bin_step(bin, mate)
	await _pile_step(mate)
	await _crew_step(hedge, mate)
	_finish_host("")


## 1. The hedge: in, live view, nothing drawn, peek, out the faced side.
func _hedge_step(hedge: Node3D, mate: int) -> void:
	var client := _player(mate)
	_place(client, hedge, 0)
	await _seconds(0.6)
	_reports.erase("in")
	_rpc_cue.rpc_id(mate, "enter", {})
	var report: Dictionary = await _report("in")
	var inside := bool(hedge.call("is_inside", mate))
	_check("hedge in", inside and bool(report.get("ok", false)), "inside %s; client: %s" % [inside, report])
	# What the host draws for the hider: Visual in the tree, no body, head or nameplate.
	var drawn := _drawn_parts(client)
	_check("hedge not drawn on the host", bool(drawn["visual_in_tree"]) and not bool(drawn["body"]) and not bool(drawn["head"]) and not bool(drawn["nameplate"]) and not bool(client.call("is_body_drawn")), str(drawn))
	var voice := client.get_node_or_null("Visual/Head/Voice") as AudioStreamPlayer3D
	_check("hedge voice muffled", voice == null or voice.bus == _HideView.VOICE_MUFFLED, "voice bus %s" % (voice.bus if voice != null else &"none"))
	_reports.erase("peek")
	_rpc_cue.rpc_id(mate, "peek", {"seconds": 1.2})
	var seen_peek := false
	var peek_waited := 0.0
	while peek_waited < 2.5 and not seen_peek:
		await get_tree().physics_frame
		peek_waited += get_physics_process_delta_time()
		seen_peek = bool(client.get("peeking"))
	await _report("peek")
	_check("hedge peek replicates", seen_peek, "the host saw peeking %s" % seen_peek)
	_reports.erase("out")
	_rpc_cue.rpc_id(mate, "exit", {"look": -2000.0})
	report = await _report("out")
	var out := not bool(hedge.call("is_inside", mate))
	await _seconds(0.3)
	var drawn_after := _drawn_parts(client)
	_check("hedge out", out and bool(report.get("ok", false)) and bool(drawn_after["body"]) and bool(drawn_after["nameplate"]), "out %s, drawn again %s; client: %s" % [out, drawn_after, report])
	var voice_back := voice == null or voice.bus == &"Voice"
	_check("hedge voice back", voice_back, "voice bus %s" % (voice.bus if voice != null else &"none"))


## 2. The shed holds two: the host gets in, then the client.
func _shed_step(shed: Node3D, mate: int) -> void:
	var me := _me()
	var client := _player(mate)
	_place(me, shed, 0)
	_place(client, shed, 0, 1.0)
	await _seconds(0.6)
	me.call("_toggle_hiding")
	await _seconds(0.9)
	_reports.erase("in")
	_rpc_cue.rpc_id(mate, "enter", {})
	var report: Dictionary = await _report("in")
	var both := bool(shed.call("is_inside", me.name.to_int())) and bool(shed.call("is_inside", mate))
	_check("shed holds two", both and bool(report.get("ok", false)), "occupants %s; client: %s" % [shed.call("occupants"), report])
	# The first one out leaves their place free; the one still in keeps theirs.
	var client_slot := int(shed.call("slot_of", mate))
	me.call("_toggle_hiding")
	await _seconds(1.0)
	var kept := int(shed.call("slot_of", mate)) == client_slot and int(shed.call("free_slot")) == 1 - client_slot
	_check("shed places stay put", kept, "client place %d then %d, free %d" % [client_slot, int(shed.call("slot_of", mate)), int(shed.call("free_slot"))])
	_reports.erase("out")
	_rpc_cue.rpc_id(mate, "exit", {"look": 0.0})
	await _report("out")
	await _seconds(0.6)
	_check("shed empty again", (shed.call("occupants") as Array).is_empty(), "occupants %s" % [shed.call("occupants")])
	# Only from before the door: never in through the back or a side wall.
	var door_only := bool(shed.call("can_enter_from", shed.call("entry_point", 0, 0))) and not bool(shed.call("can_enter_from", shed.call("entry_point", 1, 0))) and not bool(shed.call("can_enter_from", shed.call("entry_point", 2, 0)))
	_check("shed by its door only", door_only, "front/side/back: %s %s %s" % [shed.call("can_enter_from", shed.call("entry_point", 0, 0)), shed.call("can_enter_from", shed.call("entry_point", 1, 0)), shed.call("can_enter_from", shed.call("entry_point", 2, 0))])


## 3. A full bin: the client bonks off.
func _bin_step(bin: Node3D, mate: int) -> void:
	var me := _me()
	var client := _player(mate)
	_place(me, bin, 0)
	await _seconds(0.5)
	me.call("_toggle_hiding")
	await _seconds(0.9)
	var host_in := bool(bin.call("is_inside", me.name.to_int()))
	var refused_before := int(_HideSpot.stats["refused"])
	_place(client, bin, 2 if bin.call("side_toward", me.global_position) != 2 else 0)
	await _seconds(0.6)
	_reports.erase("bonk")
	_rpc_cue.rpc_id(mate, "bonk", {})
	var report: Dictionary = await _report("bonk")
	var refused := int(_HideSpot.stats["refused"]) > refused_before
	_check("bin refuses a second", host_in and refused and not bool(bin.call("is_inside", mate)) and bool(report.get("ok", false)), "host in %s, refused %s; client: %s" % [host_in, refused, report])
	me.call("_toggle_hiding")
	await _seconds(1.0)
	# Now it's free: the client vaults in, and its view under the lid is live.
	_place(client, bin, 0)
	await _seconds(0.6)
	_reports.erase("in")
	_rpc_cue.rpc_id(mate, "enter", {})
	report = await _report("in")
	_check("bin in", bool(bin.call("is_inside", mate)) and bool(report.get("ok", false)), "client: %s" % report)
	_reports.erase("out")
	_rpc_cue.rpc_id(mate, "exit", {"look": 0.0})
	report = await _report("out")
	_check("bin out", not bool(bin.call("is_inside", mate)) and bool(report.get("ok", false)), "client: %s" % report)


## 4. The pile: rake one, the client dives in, bagging it turns them out.
func _pile_step(mate: int) -> void:
	var field := get_tree().get_first_node_in_group("leaf_field")
	var pile: Vector3 = await _rake_pile(field)
	if not pile.is_finite():
		_check("pile raked", false, "no pile could be raked on this yard")
		return
	var client := _player(mate)
	client.call("send_teleport", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(pile.x, 0.1, pile.z)))
	await _seconds(0.8)
	_reports.erase("pile")
	_rpc_cue.rpc_id(mate, "pile", {})
	var report: Dictionary = await _report("pile")
	var hidden := bool(client.get("in_pile"))
	await _seconds(0.4)
	var view := client.get_node_or_null("HideView")
	var mound := view != null and view.get("_mound") != null
	var drawn := _drawn_parts(client)
	_check("pile in", hidden and bool(report.get("ok", false)) and mound and not bool(drawn["body"]) and bool(drawn["visual_in_tree"]), "in_pile %s, mound %s, drawn %s; client: %s" % [hidden, mound, drawn, report])
	# Bag it from beside it: whoever's inside is turned out.
	var me := _me()
	_drop_held(me)
	me.call("apply_network_teleport", Transform3D(Basis.IDENTITY, Vector3(pile.x - 1.2, 0.1, pile.z)))
	await _seconds(0.3)
	var bagged := int(field.call("request_collect", pile, Constants.BAG_RADIUS))
	var turned_out := false
	var waited := 0.0
	while waited < 2.0 and not turned_out:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		turned_out = not bool(client.get("in_pile"))
	_check("bagging the pile turns them out", bagged > 0 and turned_out, "bagged %d units, turned out %s" % [bagged, turned_out])
	await _seconds(1.0)


## 5. Suspicion, the near miss, immunity, and the found pull-out.
func _crew_step(hedge: Node3D, mate: int) -> void:
	var director := get_tree().get_first_node_in_group("run_director")
	var me := _me()
	# Both players safe while the crew spawns; the host stays safe and out of the way.
	var safe: Dictionary = director.get("_safe_until")
	safe[me.name.to_int()] = Net.server_time() + 120.0
	safe[mate] = Net.server_time() + 2.0
	# R2: the call makes the crew, seated in the Courtesy Shuttle; the test takes
	# them off it (placed by hand below) and holds the raid's clocks still, so the
	# chase can't give up and send the crew home mid-step.
	if int(director.call("phase")) == 0:
		director.call("force_event")
	director.call("_begin_chase")
	await _seconds(0.5)
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if shuttle != null and shuttle.has_method("dev_reset"):
		shuttle.call("dev_reset")
	director.set_process(false)
	var crew := _crew()
	if crew == null:
		director.set_process(true)
		_check("a NICE BOY", false, "none spawned")
		return
	for each: Node in get_tree().get_nodes_in_group("crew"):
		if each.has_method("host_set_mode"):
			each.call("host_set_mode", 0)
	for each: Node in get_tree().get_nodes_in_group("crew"):
		# Held still and placed by hand: this test is the spots', not the crew's.
		each.set_physics_process(false)
		(each as Node3D).global_position = hedge.global_position + Vector3(0.0, 0.0, 40.0)
	me.call("apply_network_teleport", Transform3D(Basis.IDENTITY, hedge.global_position + Vector3(0.0, 0.1, -30.0)))
	await _seconds(1.6)
	# The side of the hedge with a clear view 8 m out (a tree or the house may block one).
	var side := 0
	for candidate: int in [0, 2, 1, 3]:
		var out: Vector3 = hedge.call("side_direction", candidate)
		var query := PhysicsRayQueryParameters3D.create(hedge.global_position + out * 8.0 + Vector3(0.0, 1.4, 0.0), hedge.call("top_point"), 1)
		query.exclude = hedge.call("_own_rids")
		if me.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			side = candidate
			break
	var front: Vector3 = hedge.call("side_direction", side)
	var behind := hedge.global_position - front * 9.0
	# Behind the hedge, facing away from it.
	_park(crew, behind, -front)
	var client := _player(mate)
	_place(client, hedge, side)
	await _seconds(0.5)
	_reports.erase("in")
	_rpc_cue.rpc_id(mate, "enter", {})
	await _report("in")
	await _seconds(1.4)
	var calm := float(hedge.call("suspicion"))
	_check("unseen dive is not suspicious", calm < Constants.HIDE_FOUND_AT, "suspicion %.2f" % calm)
	_reports.erase("peek")
	_rpc_cue.rpc_id(mate, "peek", {"seconds": 1.5})
	await _report("peek")
	var after_unseen_peek := float(hedge.call("suspicion"))
	# In front of the hedge, 8 m out, looking at it.
	_park(crew, hedge.global_position + front * 8.0, -front)
	await _seconds(0.3)
	_reports.erase("peek")
	_rpc_cue.rpc_id(mate, "peek", {"seconds": 1.5})
	await _report("peek")
	var after_seen_peek := float(hedge.call("suspicion"))
	_check("peeking is suspicious only in his cone", after_unseen_peek <= calm + 0.02 and after_seen_peek >= after_unseen_peek + 0.2, "%.2f -> %.2f behind him, -> %.2f in front" % [calm, after_unseen_peek, after_seen_peek])
	# An unseen, still hider: the poke is a near miss and a sticker.
	hedge.set("_suspicion", 0.0)
	_park(crew, hedge.call("inspect_point"), -front)
	var notices_before := int(hedge.get("notices"))
	hedge.call("host_inspect_begin", crew)
	await _seconds(Constants.HIDE_INSPECT_SECONDS)
	var miss: Dictionary = hedge.call("host_inspect_resolve", crew)
	await _seconds(0.6)
	_reports.erase("notices")
	_rpc_cue.rpc_id(mate, "notices", {})
	var report: Dictionary = await _report("notices")
	_check("near miss and a sticker", miss["outcome"] == &"near_miss" and int(hedge.get("notices")) == notices_before + 1 and int(report.get("notices", -1)) == notices_before + 1 and bool(hedge.call("is_inside", mate)), "outcome %s, notices %d (client %s), still inside %s" % [miss["outcome"], int(hedge.get("notices")), report.get("notices", -1), bool(hedge.call("is_inside", mate))])
	# Immune: never found, however it looks.
	safe[mate] = Net.server_time() + 30.0
	hedge.set("_suspicion", 1.0)
	hedge.call("host_inspect_begin", crew)
	var immune: Dictionary = hedge.call("host_inspect_resolve", crew)
	_check("an immune hider isn't found", immune["outcome"] == &"near_miss" and bool(hedge.call("is_inside", mate)), "outcome %s" % immune["outcome"])
	safe.erase(mate)
	hedge.set("_suspicion", 0.0)
	# A poke cut short (he's bonked mid-poke) frees the spot: no outcome, no sticker.
	hedge.set("_inspected_at", -1000.0)
	var notices_now := int(hedge.get("notices"))
	hedge.call("host_inspect_begin", crew)
	var held := float(hedge.call("inspect_score", crew.global_position, Vector3.INF)) < 0.0
	hedge.call("host_inspect_cancel", crew)
	var freed := float(hedge.call("inspect_score", crew.global_position, Vector3.INF)) >= 0.0
	_check("a cut-short poke frees the spot", held and freed and int(hedge.get("notices")) == notices_now and bool(hedge.call("is_inside", mate)), "held %s, freed %s, notices %d -> %d" % [held, freed, notices_now, int(hedge.get("notices"))])
	# Out, then back in while he watches: found, lifted out toward him, caught.
	_reports.erase("out")
	_rpc_cue.rpc_id(mate, "exit", {"look": 0.0})
	await _report("out")
	_park(crew, hedge.global_position + front * 5.0, -front)
	await _seconds(0.4)
	_place(client, hedge, side)
	await _seconds(0.5)
	_reports.erase("in")
	_rpc_cue.rpc_id(mate, "enter", {})
	await _report("in")
	var seen := float(hedge.call("suspicion"))
	_park(crew, hedge.call("inspect_point"), -front)
	hedge.set("_inspected_at", -1000.0)
	hedge.call("host_inspect_begin", crew)
	await _seconds(Constants.HIDE_INSPECT_SECONDS)
	_reports.erase("pulled")
	_rpc_cue.rpc_id(mate, "watch_pull", {"crew": crew.global_position})
	var found: Dictionary = hedge.call("host_inspect_resolve", crew)
	var encounter := get_tree().get_first_node_in_group("nice_encounter")
	# What the crew brain does with a found hider (npcs/crew_brain.gd): the gotcha
	# from the spot, no lunge (R2 integration: the brain is held still here).
	if encounter != null and encounter.has_method("host_windup") and StringName(found.get("outcome", &"")) == &"found":
		encounter.call("host_windup", crew, int(found.get("peer", 0)), true)
	var pull_report: Dictionary = await _report("pulled")
	var caught := false
	var waited := 0.0
	while waited < 2.0 and not caught:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		if encounter != null and encounter.has_method("stage_of"):
			# PENDING_ENCOUNTER: with R2 chunk 2 the crew brain hands a found hider to the gotcha.
			caught = int(encounter.call("stage_of", mate)) != 0
		else:
			caught = bool(director.call("is_captured", mate))
	director.set_process(true)
	_check("a watched dive is found and caught", seen >= Constants.HIDE_FOUND_AT and found["outcome"] == &"found" and int(found["peer"]) == mate and caught and bool(pull_report.get("ok", false)), "suspicion %.2f, outcome %s, caught %s; client: %s" % [seen, found["outcome"], caught, pull_report])


# ---------------------------------------------------------------- client

## From the host: do the next thing a player would.
@rpc("authority", "call_remote", "reliable")
func _rpc_cue(step: String, args: Dictionary) -> void:
	match step:
		"enter":
			_client_enter()
		"peek":
			_client_peek(float(args.get("seconds", 1.0)))
		"exit":
			_client_exit(float(args.get("look", 0.0)))
		"bonk":
			_client_bonk()
		"pile":
			_client_pile()
		"notices":
			var spot := _HideSpot.spot_of(get_tree(), Net.local_peer_id())
			_rpc_report.rpc_id(1, "notices", {"notices": int(spot.get("notices")) if spot != null else -1})
		"watch_pull":
			_client_watch_pull(args.get("crew", Vector3.ZERO))


func _client_enter() -> void:
	var me := _me()
	_start_tracking()
	me.call("_toggle_hiding")
	var spot: Node3D = await _wait_for(func() -> Variant: return _HideSpot.spot_of(get_tree(), Net.local_peer_id()))
	await _seconds(Constants.HIDE_ENTER_SECONDS + 0.3)
	_tracking = false
	var report: Dictionary = await _view_report()
	report["in"] = spot != null
	report["max_step"] = snappedf(_max_step, 0.01)
	report["ok"] = spot != null and bool(report["live"]) and bool(report["visual_in_tree"]) and not bool(report["body"]) and not bool(report["head"]) and bool(report["muffled"]) and _max_step <= MAX_STEP
	_send("in", report)


func _client_peek(seconds: float) -> void:
	Input.action_press(&"secondary")
	await _seconds(seconds)
	var me := _me()
	var peeking := bool(me.get("peeking"))
	Input.action_release(&"secondary")
	await _seconds(0.3)
	_send("peek", {"ok": peeking, "peeking": peeking})


## Look (relative mouse x, through the stage camera) then come out.
func _client_exit(look: float) -> void:
	var me := _me()
	var cam := me.call("stage_cam") as Camera3D
	if cam != null and look != 0.0:
		cam.call("add_look", Vector2(look, 0.0))
		await _ticks(3)
	var spot := _HideSpot.spot_of(get_tree(), Net.local_peer_id())
	var ahead := -cam.global_basis.z if cam != null else -me.global_basis.z
	ahead.y = 0.0
	var faced := int(spot.call("side_toward", spot.global_position + ahead.normalized() * 10.0)) if spot != null else -1
	_start_tracking()
	me.call("_toggle_hiding")
	await _wait_for(func() -> Variant: return true if _HideSpot.spot_of(get_tree(), Net.local_peer_id()) == null else null)
	await _seconds(Constants.HIDE_EXIT_SECONDS + 0.3)
	_tracking = false
	var report := {"faced": faced, "max_step": snappedf(_max_step, 0.01)}
	var landed := me.global_position
	var exit_side := -1
	var best := INF
	if spot != null:
		for side: int in 4:
			var distance := landed.distance_to(spot.call("entry_point", side, 0))
			for slot: int in 2:
				distance = minf(distance, landed.distance_to(spot.call("entry_point", side, slot)))
			if distance < best:
				best = distance
				exit_side = side
		var faced_clear := bool(spot.call("_exit_clear", faced, 0)) if faced >= 0 else true
		report["exit_side"] = exit_side
		report["faced_clear"] = faced_clear
		report["on_side"] = exit_side == faced or not faced_clear or str(spot.get("spot_kind")) == "shed"
	report["landed_off_by"] = snappedf(best, 0.01)
	report["clear"] = _clear_at(landed)
	report["muffled"] = _HideView.world_muffled()
	report["body"] = bool(me.call("is_body_drawn"))
	report["ok"] = spot != null and best <= EXIT_SLACK and bool(report.get("on_side", false)) and bool(report["clear"]) and not bool(report["muffled"]) and bool(report["body"]) and _max_step <= MAX_STEP
	_send("out", report)


## Diving into a spot someone else just took (the race two friends lose): the
## host says no and the dive bonks off. Straight at the spot, past this peer's
## own has-room check, the way a late replica would.
func _client_bonk() -> void:
	var me := _me()
	var start := me.global_position
	var spot: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("hide_spots"):
		if spot == null or float(node.call("reach_distance", start)) < float(spot.call("reach_distance", start)):
			spot = node as Node3D
	_start_tracking()
	me.call("_hide_view").call("predict_enter", spot)
	spot.call("request_enter")
	await _seconds(Constants.HIDE_ENTER_SECONDS + Constants.HIDE_BONK_SECONDS + 0.6)
	_tracking = false
	var back := me.global_position.distance_to(start)
	var report := {"hidden": bool(me.call("is_hidden")), "back_by": snappedf(back, 0.01), "max_step": snappedf(_max_step, 0.01), "drawn": bool(me.call("is_body_drawn")), "shot": str(me.call("stage_top"))}
	report["ok"] = not bool(report["hidden"]) and back <= 0.6 and _max_step <= MAX_STEP and bool(report["drawn"])
	_send("bonk", report)


func _client_pile() -> void:
	var me := _me()
	_start_tracking()
	me.call("_toggle_hiding")
	await _wait_for(func() -> Variant: return true if bool(me.get("in_pile")) else null)
	await _seconds(Constants.HIDE_ENTER_SECONDS + 0.3)
	_tracking = false
	var report: Dictionary = await _view_report()
	report["in_pile"] = bool(me.get("in_pile"))
	report["max_step"] = snappedf(_max_step, 0.01)
	report["ok"] = bool(report["in_pile"]) and bool(report["live"]) and bool(report["visual_in_tree"]) and not bool(report["body"]) and bool(report["muffled"]) and _max_step <= MAX_STEP
	_send("pile", report)


## Found: lifted out toward the NICE BOY along a path, not hidden after.
func _client_watch_pull(crew_at: Vector3) -> void:
	var me := _me()
	var start := me.global_position
	_start_tracking()
	await _wait_for(func() -> Variant: return true if _HideSpot.spot_of(get_tree(), Net.local_peer_id()) == null else null)
	await _seconds(Constants.HIDE_PULL_SECONDS + 0.2)
	_tracking = false
	var closer := Vector2(me.global_position.x - crew_at.x, me.global_position.z - crew_at.z).length() < Vector2(start.x - crew_at.x, start.z - crew_at.z).length()
	var report := {"hidden": _HideSpot.spot_of(get_tree(), Net.local_peer_id()) != null, "toward_him": closer, "max_step": snappedf(_max_step, 0.01)}
	report["ok"] = not bool(report["hidden"]) and closer and _max_step <= MAX_STEP
	_send("pulled", report)
	result = {"ok": _problems.is_empty(), "done": true, "problems": _problems}


## The client's own screen while hidden: the camera, whether it turns, what's drawn.
func _view_report() -> Dictionary:
	var me := _me()
	var cam := me.call("stage_cam") as Camera3D
	var current := get_viewport().get_camera_3d()
	var top := str(me.call("stage_top"))
	var before := current.global_basis if current != null else Basis.IDENTITY
	var yaw_before := float(me.get("body_yaw"))
	if cam != null:
		cam.call("add_look", Vector2(-180.0, 30.0))
	for _frame: int in 4:
		await get_tree().process_frame
	await get_tree().physics_frame
	var after := get_viewport().get_camera_3d()
	var turned := rad_to_deg((-before.z).angle_to(-after.global_basis.z)) if after != null else 0.0
	var drawn := _drawn_parts(me)
	return {
		"camera": str(current.name) if current != null else "none",
		"shot": top,
		"live": current == cam and top in ["hide_peek", "hide_orbit"] and turned > 3.0,
		"turned_deg": snappedf(turned, 0.1),
		"body_turned": absf(angle_difference(yaw_before, float(me.get("body_yaw")))) > 0.05,
		"visual_in_tree": drawn["visual_in_tree"],
		"body": drawn["body"],
		"head": drawn["head"],
		"muffled": _HideView.world_muffled(),
	}


## Client: tell the host, and remember a failure for this peer's own result.
func _send(step: String, report: Dictionary) -> void:
	print("[HideTest] client %s: %s" % [step, report])
	if not bool(report.get("ok", false)):
		_problems.append("%s: %s" % [step, report])
	_rpc_report.rpc_id(1, step, report)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_report(step: String, report: Dictionary) -> void:
	_reports[step] = report


# ---------------------------------------------------------------- helpers

## Stand a player just outside a spot's side, facing it (host-ordered teleport).
func _place(player: Node3D, spot: Node3D, side: int, along: float = 0.0) -> void:
	var at: Vector3 = spot.call("entry_point", side, 0)
	var out: Vector3 = spot.call("side_direction", side)
	at += Vector3(-out.z, 0.0, out.x) * along
	var yaw := atan2(out.x, out.z)
	var transform := Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0.0, 0.05, 0.0))
	if player == _me():
		player.call("apply_network_teleport", transform)
	else:
		player.call("send_teleport", transform)


## Hold a NICE BOY at a point, his +Z (where he walks) facing `facing`.
func _park(crew: Node3D, at: Vector3, facing: Vector3) -> void:
	crew.global_position = Vector3(at.x, crew.global_position.y, at.z)
	crew.rotation.y = atan2(facing.x, facing.z)


func _drawn_parts(player: Node3D) -> Dictionary:
	var visual := player.get_node_or_null("Visual") as Node3D
	var body := player.get_node_or_null("Visual/CartoonBody") as Node3D
	var head := player.get_node_or_null("Visual/Head/CartoonHead") as Node3D
	var plate := player.get_node_or_null("Visual/Nameplate") as Node3D
	return {
		"visual_in_tree": visual != null and visual.is_visible_in_tree(),
		"body": body != null and body.is_visible_in_tree(),
		"head": head != null and head.is_visible_in_tree(),
		"nameplate": plate != null and plate.is_visible_in_tree() if not player.is_multiplayer_authority() else true,
	}


## Room to stand: no collider (world or props) overlapping a body-sized capsule.
func _clear_at(at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.95, 0.0))
	query.collision_mask = 5
	var rids: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
	query.exclude = rids
	return _me().get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## A raked pile on an untouched strip (gag_test's way), with the host's own rake.
func _rake_pile(field: Node) -> Vector3:
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var me := _me()
	var strip := Vector3.INF
	for z: float in [-6.0, -10.0, 2.0, 6.0, -14.0, 10.0]:
		for x: float in [-15.0, -9.0, 3.0, 9.0]:
			var fine := true
			for step: int in 14:
				if int(field.call("sample_world", lot.global_position + Vector3(x + float(step) * 0.5, 0.2, z))) < 36:
					fine = false
			if fine:
				strip = lot.global_position + Vector3(x, 0.1, z)
				break
		if strip != Vector3.INF:
			break
	if strip == Vector3.INF:
		return Vector3.INF
	var rake: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == "rake":
			rake = node as Node3D
	if rake != null and int(rake.get("held_by")) != me.name.to_int():
		_drop_held(me)
		rake.global_position = strip - Vector3(1.0, -0.4, 0.0)
		me.call("apply_network_teleport", Transform3D(Basis(Vector3.UP, -PI * 0.5), strip - Vector3(1.5, 0.0, 0.0)))
		await _ticks(2)
		rake.call("request_grab")
		await _ticks(4)
	for index: int in 14:
		var at := strip + Vector3(float(index) * 0.5, 0.1, 0.0)
		me.call("apply_network_teleport", Transform3D(Basis(Vector3.UP, -PI * 0.5), at - Vector3(1.5, 0.0, 0.0)))
		field.call("request_rake", at, Vector3(1.0, 0.0, 0.0), Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH)
		await _ticks(1)
	await _ticks(3)
	var pile := Vector3.INF
	var most := 0
	for ahead: float in [5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0]:
		var at := strip + Vector3(ahead, 0.0, 0.0)
		var units := int(field.call("units_within_world", at, Constants.PILE_HIDE_RADIUS))
		if units > most:
			most = units
			pile = at
	print("[HideTest] raked a pile of %d units at %s" % [most, pile])
	return pile if pile.is_finite() and bool(field.call("is_pile_at", pile)) else Vector3.INF


func _drop_held(player: Node3D) -> void:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == player.name.to_int():
			node.call("request_drop")


func _start_tracking() -> void:
	_tracking = true
	_last_at = Vector3.INF
	_max_step = 0.0


func _report(step: String) -> Dictionary:
	var waited := 0.0
	while not _reports.has(step) and waited < REPORT_WAIT_SECONDS:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return _reports.get(step, {"ok": false, "why": "no report"})


func _check(step: String, ok: bool, detail: String) -> void:
	_steps[step] = ok
	print("[HideTest] %s: %s (%s)" % [step, "ok" if ok else "FAIL", detail])
	if not ok:
		_problems.append("%s: %s" % [step, detail])


func _finish_host(why: String) -> void:
	if why != "":
		_problems.append(why)
		print("[HideTest] %s" % why)
	result = {"ok": _problems.is_empty(), "done": true, "steps": _steps, "problems": _problems, "stats": _HideSpot.stats.duplicate()}
	print("[HideTest] all ok: %s" % result["ok"])
	# The client's last cue is the pull; make sure it finishes even if that step never ran.
	if Net.peer_ids().size() >= 2:
		_rpc_done.rpc_id(_mate_id())


@rpc("authority", "call_remote", "reliable")
func _rpc_done() -> void:
	if not bool(result.get("done", false)):
		result = {"ok": _problems.is_empty(), "done": true}


func _spot(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("hide_spots"):
		if str(node.get("spot_kind")) == kind:
			return node as Node3D
	return null


func _crew() -> Node3D:
	var crew := get_tree().get_nodes_in_group("crew")
	return crew[0] as Node3D if not crew.is_empty() else null


func _wait_for(check: Callable) -> Variant:
	var waited := 0.0
	while waited < STEP_WAIT_SECONDS:
		var value: Variant = check.call()
		if value != null:
			return value
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	return null


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _mate_id() -> int:
	for peer_id: int in Net.peer_ids():
		if peer_id != Net.local_peer_id():
			return peer_id
	return 0


func _me() -> Node3D:
	return _player(Net.local_peer_id())


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null
