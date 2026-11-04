extends Node

## Authority: host drives, the Target client watches and reports. --encounter-test
## (R2 chunk 2; docs/GAME.md "The NICE BOYS encounter (R2)") checks the catch from
## the van to the escort, under --sim-lag=150 --sim-loss=2 on both peers:
##   1. force_event: the crew is made at once, SEATED, and on the client never more
##      than 1.5 m from its seat in the van once the van is in sight (PENDING_SHUTTLE:
##      the cast:5 van's fallback seats until chunk 4's Shuttle seats them)
##   2. they hop out after the van parks (every one, on the client too); no NICE BOY
##      ever turns faster than CREW_TURN_RATE per tick
##   3. the client stands still on the lawn with a running tool's noise: a NICE BOY
##      gets to them within 15 s, winds up and lunges; _rpc_windup reaches the client
##      at least 0.25 s before contact_at, contact_at is the same on both, GOTCHA on
##      both, is_captured true on the client within 0.3 s of contact
##   4. the client mashes jump in the cite: each press adds CATCH_WRIGGLE_ADD, up to
##      CATCH_WRIGGLE_MAX; then a thrown can on him frees the client (immunity, a
##      rescue counted, XP_RESCUE)
##   5. caught again (force_capture): through the cite to the escort; the client
##      stays within 0.3 m of its anchor on both peers (PENDING_STAGE until chunk 1's
##      set_staged), a captured client's grab is refused, and a can on him frees them
##   6. a carried client caught: the carry ends both ways
##  6b. P1 catch: the client knocked flat is hauled up: no lunge, the two-shot up
##      before the hand lands, up off their back after (run in step 10's raid)
##   7. a can landing near a NICE BOY without hitting him: INVESTIGATE
##   8. barks: the client saw the same kinds and lines, in order; the name tag and
##      the bark line keep a fixed, clamped size on the client
## (The turn check in 2 is sampled from outside the steering, every tick, on the
## host's bodies; the client's drawn turn is reported as a note.)
##  8b. a sidestep out of a wind-up: the verdict is a whiff, WHIFF on both peers,
##      and the grace refuses the next grab; 8c. a stun mid wind-up spoils it
##      (no sprawl, no catch)
##   9. a raid with nobody caught: heat drops to HEAT_AFTER_EVADED, XP_ESCAPE to the
##      spotted, never-caught player
##  10. caught with the client's clock estimate held SKEW_SECONDS behind the host's,
##      its two-shot still comes up at once (P1 catch); then the client disconnects
##      mid-escort: the NICE BOY goes back to the chase and the stage is gone, with no errors
## (A third peer joining mid-escort, the spec's late-join check, needs a second
## client, which ci_local runs don't start: covered by apply_snapshot's code path
## only. Noted in the result.)

static var result: Dictionary = {}

const _Encounter = preload("res://net/run_events/encounter.gd")
const _Crew = preload("res://npcs/crew_member.gd")
const _Sweep = preload("res://player/stage_sweep.gd")
## No grabbing the host's player, ever (it's the one throwing things).
const HOST_SAFE_SECONDS: float = 100000.0
const CLIENT_WAIT_SECONDS: float = 20.0
## Step 9: how long the Courtesy Shuttle may take to drive out of the yard's sight.
const VAN_GONE_SECONDS: float = 40.0
## Step 5 (P1 catch): how far behind the host's clock the client's estimate is held
## for the second catch (s; the playtest's starved window was 2.8 s behind).
const SKEW_SECONDS: float = -2.5
## Steps that need another R2 chunk skip with a note while its API is missing.
var PENDING_STAGE: bool = false
var PENDING_SHUTTLE: bool = false

var _started: bool = false
var _steps: Array[Dictionary] = []
var _ok: bool = true
var _client: int = 0
var _report: Dictionary = {}
## Client side: what it sampled.
var _sampled: Dictionary = {"seat_max": 0.0, "seat_samples": 0, "hops": 0, "anchor_max": 0.0, "anchor_samples": 0, "whiff_seen": false, "yaw_max": 0.0}
var _client_caught_at: float = -1.0
var _wriggling: bool = false
var _wriggle_down: bool = false
var _client_carried_seen: int = -1
## Every peer: each NICE BOY's yaw last physics tick (instance id -> rad), the
## largest one-tick turn seen on his own feet, and ticks to skip after the test
## teleports one (_put_crew).
var _yaw_prev: Dictionary = {}
var _yaw_max: float = 0.0
var _yaw_where: String = ""
var _yaw_skip: int = 0
## The physics tick of a client's last per-frame yaw sample.
var _yaw_tick: int = 0
## Client (step 5, P1 catch): its clock estimate held this far off the host's (s),
## from this base offset.
var _skew_by: float = 0.0
var _skew_base: float = 0.0


func _ready() -> void:
	result = {}
	# After every NICE BOY's own tick, so each sample is that tick's pose.
	process_physics_priority = 100
	# R2c: and after everything that places a drawn pose in a frame (the smoother,
	# a placement), so a client samples the pose that frame draws, never a
	# network update applied to the body before the smoother has put the Visual
	# back where it's drawn.
	process_priority = 4096


func _process(_delta: float) -> void:
	if multiplayer.multiplayer_peer != null and not Net.is_host():
		# R2c: a client draws a NICE BOY once per rendered frame (the smoother), so its
		# turn is sampled per frame, per physics tick that frame covered. Only the
		# ticks the frame really ran: a frame drawn after a stall shows its turn in
		# one picture, so wall time never softens it (review r2c:stage).
		var ticks := Engine.get_physics_frames() - _yaw_tick
		_yaw_tick = Engine.get_physics_frames()
		if ticks > 0:
			_sample_yaw(ticks)
	if _started or multiplayer.multiplayer_peer == null:
		return
	if Net.is_host():
		if _own() == null or get_tree().get_first_node_in_group("job_lot") == null:
			return
		_started = true
		_run()


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if Net.is_host():
		_sample_yaw(1)
	else:
		_client_sample()


## Measured from outside the steering: how far each NICE BOY's drawn yaw moved in
## one tick while he was on his own feet (no hop, lunge or stand placement), the
## hand-backs from those included. The host's body is the drawn one; a client
## draws Visual (the network's pose, smoothed) once per rendered frame: there the
## turn since the last frame is shared over the physics ticks that frame covered
## (R2c: sampled per tick, a frame that covered four ticks under load read as a
## four-tick turn in one, the step 2 flake's 0.41-0.48 rad).
func _sample_yaw(ticks: int) -> void:
	var skip := _yaw_skip > 0
	_yaw_skip = maxi(0, _yaw_skip - ticks)
	var alive: Dictionary = {}
	for member: Node in get_tree().get_nodes_in_group("nice_crew"):
		if member.is_queued_for_deletion():
			continue
		var drawn := member as Node3D if Net.is_host() else member.get_node_or_null("Visual") as Node3D
		if drawn == null:
			continue
		var id := member.get_instance_id()
		var yaw := drawn.global_rotation.y
		var at := drawn.global_position
		if _yaw_prev.has(id) and not skip and not bool(member.call("is_riding_visual")):
			var last: Array = _yaw_prev[id]
			# The test's own teleports (_put_crew) reach a client a lag later, as a jump.
			if at.distance_to(last[1]) < 1.0:
				var turn := absf(wrapf(yaw - float(last[0]), -PI, PI)) / float(maxi(1, ticks))
				if turn > _yaw_max:
					_yaw_max = turn
					_yaw_where = "%s mode %d at %.2f over %d tick(s)" % [member.name, int(member.get("mode")), Net.server_time(), ticks]
		_yaw_prev[id] = [yaw, at]
		alive[id] = true
	for id: Variant in _yaw_prev.keys():
		if not alive.has(id):
			_yaw_prev.erase(id)


# ---------------------------------------------------------------- the host

func _run() -> void:
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < CLIENT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if Net.peer_ids().size() < 2:
		_finish_with("no client joined")
		return
	for peer_id: int in Net.peer_ids():
		if peer_id != Net.local_peer_id():
			_client = peer_id
	await get_tree().create_timer(2.0).timeout
	var probe_player := _own()
	PENDING_STAGE = not probe_player.has_method("set_staged")
	PENDING_SHUTTLE = get_tree().get_first_node_in_group("nice_shuttle") == null
	var director := _director()
	var encounter := _encounter()
	var heat := get_tree().get_first_node_in_group("heat")
	_safe(Net.local_peer_id(), HOST_SAFE_SECONDS)
	# Two NICE BOYS (one for the catches, one to watch).
	heat.call("add", Constants.HEAT_PER_EXTRA_CREW * 1.5 - float(heat.get("heat")), "test")
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	_move_to(lot.global_position + Vector3(-8.0, 0.1, 10.0), 0.0)
	_teleport(_client, lot.global_position + Vector3(4.0, 0.1, 6.0))
	# 1. Seated at the call.
	director.call("force_event")
	await _ticks(3)
	var crew := _crew_all()
	var seated := not crew.is_empty()
	for member: Node in crew:
		seated = seated and int(member.get("mode")) == _Crew.Mode.SEATED
	_step("1 the call makes %d NICE BOYS at once, all SEATED" % crew.size(), seated)
	# 2. They hop out after the van parks.
	var out: bool = await _wait(func() -> bool:
		for member: Node in _crew_all():
			if [_Crew.Mode.SEATED, _Crew.Mode.HOP_OUT].has(int(member.get("mode"))):
				return false
		return int(director.call("phase")) == 2, Constants.RUN_WARNING_SECONDS + 6.0)
	_step("2 every NICE BOY is out of the van once it's parked", out)
	# 3. The noisy client, standing still, gets a visit and a lunge.
	var client_body := _player(_client)
	var noise_until := Net.server_time() + 15.0
	var windup_seen: bool = await _wait(func() -> bool:
		if Net.server_time() < noise_until and client_body != null:
			heat.call("note_noise", _client, client_body.global_position, 0.05)
		return int(encounter.call("stage_of", _client)) >= _Encounter.Stage.GOTCHA, 15.0)
	var host_windup := _last_log("windup", _client)
	var host_catch := _last_log("catch", _client)
	_step("3 a noisy, still client is reached and caught within 15 s (wind-up %s, catch %s)" % [not host_windup.is_empty(), not host_catch.is_empty()], windup_seen and not host_windup.is_empty())
	# Give the client a moment to see it.
	await get_tree().create_timer(0.6).timeout
	_report = {}
	_rpc_ask_report.rpc_id(_client)
	await _wait(func() -> bool: return not _report.is_empty(), 4.0)
	var client_windup: Dictionary = _report.get("windup", {})
	var lead := float(client_windup.get("at", 0.0)) - float(client_windup.get("seen", 0.0))
	# R2b: the whole crouch plays before the lunge (contact is the wind-up plus the
	# lunge away), so even a resent RPC under 2% loss leaves the client a crouch to see.
	var host_lead := float(host_windup.get("at", 0.0)) - float(host_windup.get("seen", 0.0))
	_step("3 the wind-up reached the client %.2f s before contact (>= %.2f, the lunge plus some crouch; the host sent it %.2f s before)" % [lead, Constants.CREW_LUNGE_SECONDS + 0.05, host_lead], lead >= Constants.CREW_LUNGE_SECONDS + 0.05)
	_step("3 the host's contact is the full wind-up and the lunge away (%.2f s, want >= %.2f)" % [host_lead, Constants.CREW_LUNGE_WINDUP + Constants.CREW_LUNGE_SECONDS], host_lead >= Constants.CREW_LUNGE_WINDUP + Constants.CREW_LUNGE_SECONDS - 0.02)
	_step("3 contact_at is the same on both (%.3f vs %.3f)" % [float(host_windup.get("at", -1.0)), float(client_windup.get("at", -2.0))], absf(float(host_windup.get("at", -1.0)) - float(client_windup.get("at", -2.0))) < 0.001)
	var caught_lag := float(_report.get("caught_seen", 99.0)) - float(host_catch.get("at", 0.0))
	_step("3 GOTCHA on the client (stage %d) and is_captured %.2f s after contact (<= 0.3)" % [int(_report.get("stage", 0)), caught_lag], int(_report.get("stage", 0)) >= _Encounter.Stage.GOTCHA and caught_lag <= 0.3)
	_step("2 the client saw %d hop-outs" % int(_report.get("hops", 0)), int(_report.get("hops", 0)) >= crew.size())
	if PENDING_SHUTTLE:
		_step("1 on the client every seated NICE BOY stayed within %.2f m of its seat (%d samples)" % [float(_report.get("seat_max", 9.0)), int(_report.get("seat_samples", 0))], float(_report.get("seat_max", 9.0)) <= 1.5 and int(_report.get("seat_samples", 0)) > 0)
	# 4. Wriggles, then a can frees them.
	var catch_at := float(host_catch.get("at", Net.server_time()))
	await _until(catch_at + Constants.CATCH_CITE_AT + 0.05)
	var base_end := float(encounter.call("cite_end", _client))
	_rpc_wriggle.rpc_id(_client, true)
	await get_tree().create_timer(1.0).timeout
	_rpc_wriggle.rpc_id(_client, false)
	await get_tree().create_timer(0.3).timeout
	var bought := float(encounter.call("cite_end", _client)) - base_end
	var presses := int(_Encounter.stats["wriggles"])
	_step("4 %d wriggles bought %.2f s (each %.2f, at most %.2f)" % [presses, bought, Constants.CATCH_WRIGGLE_ADD, Constants.CATCH_WRIGGLE_MAX], presses > 0 and absf(bought - minf(float(presses) * Constants.CATCH_WRIGGLE_ADD, Constants.CATCH_WRIGGLE_MAX)) < 0.02)
	var holder := _holder(_client)
	var rescues_before := _tally("rescues")
	var xp_before := _xp("rescue")
	var freed: bool = await _bean(holder, _client)
	var safe_left := float((director.get("_safe_until") as Dictionary).get(_client, 0.0)) - Net.server_time()
	_step("4 a can on %s during the cite frees the client (free %s, immunity %.1f s)" % [holder.name if holder != null else "nobody", freed, safe_left], freed and safe_left > Constants.RESCUE_IMMUNITY - 1.0)
	var rescue_text := "4 the rescue counts (+%d rescue, +%d XP, want +%d)" % [int(_tally("rescues") - rescues_before), _xp("rescue") - xp_before, Constants.XP_RESCUE]
	if Campaign.has_method("add_rescue"):
		# Chunk 6 counts it its own way: its tally is the check to make strict here.
		_note("pending chunk 6's Campaign.add_rescue tally: " + rescue_text)
	else:
		_step(rescue_text, _tally("rescues") - rescues_before >= 1.0 and _xp("rescue") - xp_before >= Constants.XP_RESCUE)
	# 5. Caught again: the cite, then the escort.
	await get_tree().create_timer(Constants.RESCUE_IMMUNITY + 0.3).timeout
	var catcher := _nearest_crew(client_body.global_position)
	if catcher != null:
		_put_crew(catcher, client_body.global_position + Vector3(0.0, 0.0, -1.1), client_body.global_position)
	await _ticks(3)
	director.call("force_capture", _client)
	# R2b: the gotcha's staging: arm's length apart, both turned toward the camera.
	await get_tree().create_timer(Constants.CATCH_HITSTOP + Constants.CATCH_CAM_BLEND + 0.25).timeout
	var holding := _holder(_client)
	if holding != null and int(encounter.call("stage_of", _client)) in [_Encounter.Stage.GOTCHA, _Encounter.Stage.CITE]:
		var apart := Vector2(holding.global_position.x - client_body.global_position.x, holding.global_position.z - client_body.global_position.z).length()
		var args: Dictionary = (encounter.get("_stages") as Dictionary).get(_client, {}).get("args", {})
		var staging: Dictionary = _Encounter._staging(args.get("victim", client_body.global_position), args.get("crew_at", holding.global_position), float(args.get("cam_yaw", 0.0)))
		var crew_face: Vector3 = holding.call("facing")
		var victim_face := -client_body.global_basis.z
		victim_face.y = 0.0
		var to_cam: Vector3 = staging["to_cam"]
		var turned := crew_face.dot(to_cam) > 0.2 and victim_face.normalized().dot(to_cam) > 0.2
		_step("5 the gotcha stands them %.2f m apart (want %.2f), both turned toward the two-shot (%s)" % [apart, Constants.CATCH_GOTCHA_GAP, turned], absf(apart - Constants.CATCH_GOTCHA_GAP) < 0.15 and turned)
	else:
		_step("5 the gotcha's staging: no holder (%s) or past the cite (stage %d)" % [holding != null, int(encounter.call("stage_of", _client))], false)
	var escorting: bool = await _wait(func() -> bool: return int(encounter.call("stage_of", _client)) == _Encounter.Stage.ESCORT and Net.server_time() > encounter.call("stage_at", _client) + 0.5, 8.0)
	_step("5 caught again (no lunge) and walked off arm in arm", escorting)
	var trash := _prop("trash")
	if trash != null:
		trash.global_position = client_body.global_position + Vector3(0.5, 0.4, 0.0)
		trash.set("linear_velocity", Vector3.ZERO)
		await _ticks(2)
		trash.call("_handle_grab", _client)
		await _ticks(2)
		_step("5 a captured client's grab is refused", int(trash.get("held_by")) != _client)
	var anchor_ok := true
	var anchor_max := 0.0
	var anchor_samples := 0
	for _sample: int in 40:
		await get_tree().physics_frame
		if int(encounter.call("stage_of", _client)) != _Encounter.Stage.ESCORT:
			break
		var anchor: Node3D = encounter.call("escort_anchor", _client)
		if anchor != null:
			var drawn := client_body.get_node("Visual") as Node3D
			anchor_max = maxf(anchor_max, Vector2(drawn.global_position.x - anchor.global_position.x, drawn.global_position.z - anchor.global_position.z).length())
			anchor_samples += 1
	if PENDING_STAGE:
		_note("5 pending: the escorted body on its anchor needs chunk 1's set_staged (host saw %.2f m)" % anchor_max)
	else:
		anchor_ok = anchor_max <= 0.3 and anchor_samples > 0
		_step("5 on the host the escorted client stays within %.2f m of its anchor" % anchor_max, anchor_ok)
	holder = _holder(_client)
	freed = await _bean(holder, _client)
	_step("5 a can on %s during the escort frees the client" % (holder.name if holder != null else "nobody"), freed)
	_report = {}
	_rpc_ask_report.rpc_id(_client)
	await _wait(func() -> bool: return not _report.is_empty(), 4.0)
	if not PENDING_STAGE:
		_step("5 on the client the escorted body stayed within %.2f m of its anchor (%d samples)" % [float(_report.get("anchor_max", 9.0)), int(_report.get("anchor_samples", 0))], float(_report.get("anchor_max", 9.0)) <= 0.3 and int(_report.get("anchor_samples", 0)) > 0)
	# 6. Carried, then caught: the carry ends both ways.
	await get_tree().create_timer(Constants.RESCUE_IMMUNITY + 0.3).timeout
	var brawl := get_tree().get_first_node_in_group("brawl")
	_move_to(client_body.global_position + Vector3(0.0, 0.0, 1.0), 0.0)
	await _ticks(4)
	brawl.call("_handle_grab", Net.local_peer_id(), _client)
	var carrying: bool = await _wait(func() -> bool: return int(_own().get("carrying")) == _client, 3.0)
	director.call("force_capture", _client)
	await get_tree().create_timer(0.8).timeout
	_report = {}
	_rpc_ask_report.rpc_id(_client)
	await _wait(func() -> bool: return not _report.is_empty(), 4.0)
	_step("6 carried (%s) then caught: the host carries %d, the client is carried by %d" % [carrying, int(_own().get("carrying")), int(_report.get("carried_by", -1))], carrying and int(_own().get("carrying")) == 0 and int(_report.get("carried_by", -1)) == 0)
	director.call("release_peer", _client, 3.0)
	await get_tree().create_timer(0.5).timeout
	# 7. A can landing near (not on) a NICE BOY: he investigates.
	var idle := _nearest_crew(_own().global_position)
	var investigated := false
	if idle != null and trash != null:
		_safe(_client, 30.0)
		await _wait(func() -> bool: return bool(idle.call("in_brain_mode")) and int(idle.get("mode")) != _Crew.Mode.CHASE and int(idle.get("mode")) != _Crew.Mode.SPOT, 6.0)
		# A can come down out of the air beside him, as if lobbed (net_prop's own
		# landing hook tells the crew when it comes to rest).
		var near := idle.global_position + idle.global_basis.x * 2.5 + Vector3.UP * 1.2
		_drop_all()
		await _ticks(2)
		trash.global_position = near
		trash.set("linear_velocity", Vector3(0.0, -1.0, 0.0))
		trash.set("_thrower", Net.local_peer_id())
		trash.set("_airborne", true)
		investigated = await _wait(func() -> bool: return int(idle.get("mode")) == _Crew.Mode.INVESTIGATE, 4.0)
	_step("7 a can landing near %s: he investigates (%s)" % [idle.name if idle != null else "nobody", investigated], investigated)
	# 8. Barks.
	_report = {}
	_rpc_ask_report.rpc_id(_client)
	await _wait(func() -> bool: return not _report.is_empty(), 4.0)
	var client_barks: Array = _report.get("barks", [])
	var host_barks: Array = _Crew.bark_log.slice(maxi(0, _Crew.bark_log.size() - 6))
	var tail: Array = client_barks.slice(maxi(0, client_barks.size() - host_barks.size()))
	_step("8 the client saw the same last %d barks (kinds and lines) as the host" % host_barks.size(), host_barks.size() > 0 and JSON.stringify(host_barks) == JSON.stringify(tail))
	_step("8 on the client the name tags and bark lines keep a fixed, clamped size", bool(_report.get("tags_ok", false)))
	# 8b. A sidestep during the wind-up: the verdict is a whiff, he sprawls, and the
	# target has a moment's grace. The host's own player dodges (its position is the
	# host's at once; a client's sidestep reaches the host a lag later, which the
	# wind-up's lead already pays for).
	await _dodge_steps(director, encounter)
	await _route_step(encounter)
	# 9. A raid nobody's caught in.
	director.call("dev_reset")
	await get_tree().create_timer(1.0).timeout
	heat.call("add", 80.0 - float(heat.get("heat")), "test")
	var escape_before := _xp("escape")
	director.call("force_event")
	await _wait(func() -> bool: return int(director.call("phase")) == 2, Constants.RUN_WARNING_SECONDS + 3.0)
	director.call("note_spotted", Net.local_peer_id())
	director.call("host_begin_departure")
	var quiet: bool = await _wait(func() -> bool: return int(director.call("phase")) == 0, Constants.CREW_RECALL_MAX * 2.0 + 4.0)
	heat.call("sync_now")
	_step("9 nobody caught: the heat settles at %.0f (want %.0f)" % [float(heat.get("heat")), Constants.HEAT_AFTER_EVADED], quiet and absf(float(heat.get("heat")) - Constants.HEAT_AFTER_EVADED) < 1.5)
	var escape_text := "9 the spotted, never-caught host gets XP_ESCAPE (+%d, want +%d)" % [_xp("escape") - escape_before, Constants.XP_ESCAPE]
	if Campaign.has_method("award_escape"):
		_note("pending chunk 6's Campaign.award_escape tally: " + escape_text)
	else:
		_step(escape_text, _xp("escape") - escape_before >= Constants.XP_ESCAPE)
	# The Courtesy Shuttle drives its whole route out of the yard's sight before it
	# counts as gone (R2 integration: VAN_GONE_SECONDS); the crew must ride it all
	# the way (seated, never freed in view) and be freed once it's gone.
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	var freed_early := false
	var freed_crew: bool = await _wait(func() -> bool:
		if _crew_all().is_empty():
			return true
		if shuttle != null and not bool(shuttle.call("is_gone")):
			for member: Node in _crew_all():
				if int(member.get("mode")) != _Crew.Mode.SEATED and int(member.get("mode")) != _Crew.Mode.HOP_IN:
					freed_early = true
		return false, Constants.VAN_LEAVE_SECONDS + 4.0 if shuttle == null else VAN_GONE_SECONDS)
	_step("9 the crew left with the van, seated all the way (freed once it's gone)", freed_crew and not freed_early)
	# 6b, on a raid of its own (a haul ends a raid with only the client to catch).
	director.call("dev_reset")
	await get_tree().create_timer(1.0).timeout
	director.call("force_event")
	await _wait(func() -> bool:
		if int(director.call("phase")) != 2:
			return false
		for member: Node in _crew_all():
			if not bool(member.call("in_brain_mode")):
				return false
		return true, Constants.RUN_WARNING_SECONDS + 6.0)
	await _haul_step(director, encounter, client_body)
	director.call("dev_reset")
	await get_tree().create_timer(1.0).timeout
	# 10. Disconnect mid-escort.
	director.call("force_event")
	await _wait(func() -> bool:
		if int(director.call("phase")) != 2:
			return false
		for member: Node in _crew_all():
			if not bool(member.call("in_brain_mode")):
				return false
		return true, Constants.RUN_WARNING_SECONDS + 6.0)
	_safe(_client, 0.0)
	(director.get("_safe_until") as Dictionary).erase(_client)
	catcher = _nearest_crew(client_body.global_position)
	if catcher != null:
		_put_crew(catcher, client_body.global_position + Vector3(0.0, 0.0, -1.1), client_body.global_position)
	await _ticks(3)
	# P1 catch (audit lagduo-2): a catch on a client whose clock estimate has
	# drifted SKEW_SECONDS behind the host's (a starved window's fixed step did it in
	# the playtest: the second catch after a rescue got no gotcha at all). It stays
	# skewed: the client leaves at the end of this step.
	_rpc_skew.rpc_id(_client, SKEW_SECONDS)
	await get_tree().create_timer(0.3).timeout
	director.call("force_capture", _client)
	await get_tree().create_timer(Constants.CATCH_HITSTOP + Constants.CATCH_CAM_BLEND + 0.25).timeout
	_report = {}
	_rpc_ask_report.rpc_id(_client)
	await _wait(func() -> bool: return not _report.is_empty(), 4.0)
	var skew_top := str(_report.get("stage_top", ""))
	_step("10 caught with the client's clock %.1f s behind the host's: its two-shot is up all the same (top '%s', stage %d, rebased %d)" % [SKEW_SECONDS, skew_top, int(_report.get("stage", 0)), int(_report.get("rebased", 0))],
		skew_top == "gotcha" and int(_report.get("stage", 0)) in [_Encounter.Stage.GOTCHA, _Encounter.Stage.CITE] and int(_report.get("rebased", 0)) > 0)
	await _wait(func() -> bool: return int(encounter.call("stage_of", _client)) == _Encounter.Stage.ESCORT, 8.0)
	var walker := _holder(_client)
	_rpc_leave.rpc_id(_client)
	var back: bool = await _wait(func() -> bool:
		return not Net.peer_ids().has(_client) and int(encounter.call("stage_of", _client)) == 0 and walker != null and is_instance_valid(walker) and bool(walker.call("in_brain_mode")), 6.0)
	_step("10 the client left mid-escort: %s is back on the chase, the stage gone" % (walker.name if walker != null else "nobody"), back)
	_note("late join mid-escort: needs a second client (not in ci_local); apply_snapshot covers it")
	var most := Constants.CREW_TURN_RATE * get_physics_process_delta_time() + 0.01
	_step("2 on the host the largest one-tick turn of a NICE BOY on his feet was %.3f rad (at most %.3f; %s)" % [_yaw_max, most, _yaw_where], _yaw_max <= most)
	# The client draws the network's pose through the smoother, a frame at a time:
	# a frame can carry two ticks of turning, and a lost update bunches a little
	# more, but never a swing (a turn on the spot used to arrive all at once when
	# he walked off).
	var client_turn := float(_report.get("yaw_max", 9.0))
	_step("2 on the client the largest one-tick turn drawn was %.3f rad (at most %.3f; %s)" % [client_turn, most * 3.0, str(_report.get("yaw_where", ""))], client_turn <= most * 3.0)
	_finish()


## 8d (R2b): the escort's way to the van door goes round a wall put across the
## straight line, through a point with a clear line on to the door.
func _route_step(encounter: Node) -> void:
	var walker: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("nice_crew"):
		walker = node as Node3D
		break
	var door: Vector3 = encounter.call("_door_point") if walker != null else Vector3.INF
	if walker == null or not door.is_finite():
		_step("8d a NICE BOY and a door to route to", false)
		return
	var line := door - walker.global_position
	line.y = 0.0
	if line.length() < 4.0:
		_note("8d skipped: he's already %.1f m from the door" % line.length())
		return
	var mid := walker.global_position + line * 0.5
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 2.5, 0.4)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_transform = Transform3D(Basis.looking_at(line.normalized(), Vector3.UP), mid + Vector3.UP * 1.25)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var via: Vector3 = encounter.call("_plan_route", walker, door, [])
	var world := walker.get_world_3d()
	var exclude := _Sweep.passable(get_tree())
	var onward := via.is_finite() and _Sweep.clear(world, via + Vector3.UP * 0.7, door + Vector3.UP * 0.7 + (via - door).normalized() * 0.6, 0.3, exclude)
	wall.queue_free()
	_step("8d with a wall across the way out, the escort goes by %s, clear on to the door (%s)" % [via, onward], via.is_finite() and onward)


## 8b and 8c: a sidestep whiffs (WHIFF on both peers, grace refuses the next grab);
## a stun cancels a wind-up (no sprawl). The host's player is grabbable only
## between each wind-up and its verdict.
func _dodge_steps(director: Node, encounter: Node) -> void:
	var me := Net.local_peer_id()
	var body := _own()
	_safe(_client, 60.0)
	var lunger := _nearest_crew(body.global_position)
	if lunger == null:
		_step("8b a NICE BOY to dodge", false)
		return
	await _wait(func() -> bool: return bool(lunger.call("in_brain_mode")) and not bool(lunger.call("is_stunned")), 6.0)
	var here := body.global_position
	_put_crew(lunger, here + Vector3(0.0, 0.0, -1.6), here)
	await _ticks(2)
	var whiffs := int(_Encounter.stats["whiffs"])
	var safe: Dictionary = director.get("_safe_until")
	safe.erase(me)
	var wound := bool(encounter.call("host_windup", lunger, me, false))
	# Straight out of the lunge's path, sideways.
	_move_to(here + Vector3(2.5, 0.0, 0.0), 0.0)
	var whiffed: bool = await _wait(func() -> bool: return int(_Encounter.stats["whiffs"]) > whiffs or int(encounter.call("stage_of", me)) >= _Encounter.Stage.GOTCHA, 2.0)
	await _ticks(2)
	var sprawled := int(lunger.get("mode")) == _Crew.Mode.WHIFF
	var caught := bool(director.call("is_captured", me))
	# Let go of on the host too: no stage left, and he's off the lunge's placement.
	var let_go := int(encounter.call("stage_of", me)) == _Encounter.Stage.NONE and not bool(lunger.call("is_riding_visual"))
	# Still in the grace: the next grab is refused.
	var refused := not bool(encounter.call("host_windup", lunger, me, false))
	_safe(me, HOST_SAFE_SECONDS)
	_step("8b a sidestep out of the lunge whiffs (wound up %s, whiff %s, caught %s, WHIFF %s, let go %s)" % [wound, whiffed, caught, sprawled, let_go], wound and whiffed and not caught and sprawled and let_go)
	_step("8b the whiff's grace refuses the next grab", refused)
	await get_tree().create_timer(0.5).timeout
	_report = {}
	_rpc_ask_report.rpc_id(_client)
	await _wait(func() -> bool: return not _report.is_empty(), 4.0)
	_step("8b the client saw the whiff on the host's player and the sprawl (%s, %s)" % [(_report.get("whiff_peers", []) as Array).has(me), bool(_report.get("whiff_seen", false))], (_report.get("whiff_peers", []) as Array).has(me) and bool(_report.get("whiff_seen", false)))
	# 8c. A stun mid wind-up: spoiled, no sprawl, no catch.
	await get_tree().create_timer(Constants.CREW_WHIFF_GRACE + 0.2).timeout
	await _wait(func() -> bool: return bool(lunger.call("in_brain_mode")) and not bool(lunger.call("is_stunned")), 4.0)
	here = body.global_position
	_put_crew(lunger, here + Vector3(0.0, 0.0, -1.6), here)
	await _ticks(2)
	whiffs = int(_Encounter.stats["whiffs"])
	safe.erase(me)
	wound = bool(encounter.call("host_windup", lunger, me, false))
	await _ticks(3)
	lunger.set("_stun_left", 1.0)
	var spoiled: bool = await _wait(func() -> bool: return int(_Encounter.stats["whiffs"]) > whiffs or int(encounter.call("stage_of", me)) >= _Encounter.Stage.GOTCHA, 2.0)
	await _ticks(2)
	caught = bool(director.call("is_captured", me))
	sprawled = int(lunger.get("mode")) == _Crew.Mode.WHIFF
	let_go = int(encounter.call("stage_of", me)) == _Encounter.Stage.NONE and not bool(lunger.call("is_riding_visual"))
	_safe(me, HOST_SAFE_SECONDS)
	_step("8c a stun cancels a wind-up (wound up %s, spoiled %s, caught %s, sprawled %s, let go %s)" % [wound, spoiled, caught, sprawled, let_go], wound and spoiled and not caught and not sprawled and let_go)
	lunger.set("_stun_left", 0.0)


## 6b (P1 catch, audit crew-13): the client knocked flat, a NICE BOY close by winds
## up on them: no lunge, their two-shot is up before the hand lands (from the
## ground), the catch is a haul-up, and they're off their back after it.
func _haul_step(director: Node, encounter: Node, client_body: Node3D) -> void:
	# Nobody else's grab first: the client is safe until the test's own wind-up.
	_safe(_client, 30.0)
	await get_tree().create_timer(1.0).timeout
	var hauler := _nearest_crew(client_body.global_position)
	if hauler == null:
		_step("6b a NICE BOY to haul the client up", false)
		return
	await _wait(func() -> bool: return bool(hauler.call("in_brain_mode")) and not bool(hauler.call("is_stunned")), 4.0)
	_rpc_knock.rpc_id(_client)
	var down: bool = await _wait(func() -> bool: return _Encounter.is_down(client_body), 2.0)
	var at := client_body.global_position
	_put_crew(hauler, at + Vector3(1.8, 0.0, 0.0), at)
	await _ticks(2)
	(director.get("_safe_until") as Dictionary).erase(_client)
	var hauls := int(_Encounter.stats["hauls"])
	var wound := bool(encounter.call("host_windup", hauler, _client, false))
	await get_tree().create_timer(Constants.CATCH_DOWN_REACH * 0.6).timeout
	_report = {}
	_rpc_ask_report.rpc_id(_client)
	await _wait(func() -> bool: return not _report.is_empty(), 2.0)
	var reach_top := str(_report.get("stage_top", ""))
	var reaching := bool(_report.get("hauling", false))
	var lunged := [false]
	var caught: bool = await _wait(func() -> bool:
		if int(hauler.get("mode")) == _Crew.Mode.LUNGE:
			lunged[0] = true
		return int(encounter.call("stage_of", _client)) >= _Encounter.Stage.GOTCHA, 3.0)
	await get_tree().create_timer(Constants.CATCH_HITSTOP + 0.9).timeout
	_report = {}
	_rpc_ask_report.rpc_id(_client)
	await _wait(func() -> bool: return not _report.is_empty(), 2.0)
	var up := not bool(_report.get("down", true))
	_step("6b knocked flat (%s) and wound up on (%s): the client's two-shot is up mid-reach (top '%s', reaching %s), no lunge (%s), a haul-up catch (%s, +%d), up off their back after (%s)" % [down, wound, reach_top, reaching, not lunged[0], caught, int(_Encounter.stats["hauls"]) - hauls, up],
		down and wound and reach_top == "gotcha" and reaching and not lunged[0] and caught and int(_Encounter.stats["hauls"]) > hauls and up)
	director.call("release_peer", _client, 3.0)
	# He's back on his feet and free for whatever comes next.
	await _wait(func() -> bool: return bool(hauler.call("in_brain_mode")) and not bool(hauler.call("is_stunned")), 6.0)
	await get_tree().create_timer(0.5).timeout


## Throw the trash can at whoever holds this peer, from point blank; true once freed.
func _bean(crew: Node3D, peer_id: int) -> bool:
	if crew == null:
		return false
	var encounter := _encounter()
	var trash := _prop("trash")
	if trash == null:
		return false
	for _attempt: int in 3:
		var toward := crew.global_basis.x
		toward.y = 0.0
		var stand := crew.global_position + toward.normalized() * 1.8
		stand.y = crew.global_position.y + 0.1
		var at := crew.global_position - stand
		_move_to(stand, atan2(-at.x, -at.z))
		await _grab(trash)
		trash.global_position = _own().global_position + Vector3(0.0, 0.9, 0.0) + at.normalized() * 0.6
		trash.call("request_throw", at.normalized(), 1.3)
		var waited := 0.0
		while waited < 1.5:
			await get_tree().physics_frame
			waited += get_physics_process_delta_time()
			if int(encounter.call("stage_of", peer_id)) == _Encounter.Stage.NONE:
				return true
	return false


# ---------------------------------------------------------------- the client

func _client_sample() -> void:
	_hold_skew()
	var director := _director()
	var me := Net.local_peer_id()
	if director == null:
		return
	if _client_caught_at < 0.0 and bool(director.call("is_captured", me)):
		_client_caught_at = Net.server_time()
	elif not bool(director.call("is_captured", me)):
		_client_caught_at = -1.0 if _client_caught_at < 0.0 else _client_caught_at
	for member: Node in get_tree().get_nodes_in_group("nice_crew"):
		if int(member.get("mode")) == _Crew.Mode.WHIFF:
			_sampled["whiff_seen"] = true
		if int(member.get("mode")) == _Crew.Mode.SEATED and int(director.call("phase")) == 1:
			var look: Node3D = member.call("van_anchor")
			if look != null and (member.get_node("Visual") as Node3D).visible:
				var seat: Transform3D = look.global_transform * _Crew.fallback_seat(int(member.call("crew_index")))
				var drawn := member.get_node("Visual") as Node3D
				_sampled["seat_max"] = maxf(float(_sampled["seat_max"]), drawn.global_position.distance_to(seat.origin))
				_sampled["seat_samples"] = int(_sampled["seat_samples"]) + 1
	var encounter := _encounter()
	var player := _own()
	if encounter != null and player != null and int(encounter.call("stage_of", me)) == _Encounter.Stage.ESCORT and Net.server_time() > float(encounter.call("stage_at", me)) + Constants.ESCORT_LINK_BLEND + 0.1:
		var anchor: Node3D = encounter.call("escort_anchor", me)
		if anchor != null:
			_sampled["anchor_max"] = maxf(float(_sampled["anchor_max"]), Vector2(player.global_position.x - anchor.global_position.x, player.global_position.z - anchor.global_position.z).length())
			_sampled["anchor_samples"] = int(_sampled["anchor_samples"]) + 1
	if _wriggling:
		_wriggle_down = not _wriggle_down
		if _wriggle_down:
			Input.action_press(&"jump")
		else:
			Input.action_release(&"jump")


@rpc("authority", "call_remote", "reliable")
func _rpc_ask_report() -> void:
	var me := Net.local_peer_id()
	var encounter := _encounter()
	var windup: Dictionary = {}
	var caught_seen := 99.0
	var whiff_peers: Array = []
	for entry: Dictionary in _Encounter.log:
		if str(entry["event"]) == "whiff":
			whiff_peers.append(int(entry["peer"]))
		if int(entry["peer"]) == me and str(entry["event"]) == "windup":
			windup = entry
		if int(entry["peer"]) == me and str(entry["event"]) == "catch":
			caught_seen = float(entry["seen"])
	var tags_ok := true
	for member: Node in get_tree().get_nodes_in_group("nice_crew"):
		for label_name: String in ["Label", "Bark"]:
			var label := member.get_node_or_null("Visual/" + label_name) as Label3D
			tags_ok = tags_ok and label != null and label.fixed_size and label.pixel_size <= Constants.CREW_TAG_MAX_PX
	var player := _own()
	_rpc_report.rpc_id(1, {
		"windup": windup, "caught_seen": caught_seen,
		"stage": int(encounter.call("stage_of", me)) if encounter != null else 0,
		"hops": int(_Crew.stats["hops"]),
		"seat_max": _sampled["seat_max"], "seat_samples": _sampled["seat_samples"],
		"anchor_max": _sampled["anchor_max"], "anchor_samples": _sampled["anchor_samples"],
		"carried_by": int(player.get("carried_by")) if player != null else -1,
		"barks": _Crew.bark_log.slice(maxi(0, _Crew.bark_log.size() - 12)),
		"tags_ok": tags_ok,
		"whiff_peers": whiff_peers, "whiff_seen": _sampled["whiff_seen"], "yaw_max": _yaw_max, "yaw_where": _yaw_where,
		# P1 catch: the shot on this client's own screen, how many stage times it
		# moved onto its own clock, and whether its body is down.
		"stage_top": str(player.call("stage_top")) if player != null and player.has_method("stage_top") else "",
		"rebased": int(_Encounter.stats["rebased"]),
		"down": _Encounter.is_down(player),
		"hauling": encounter != null and bool(encounter.call("_hauling", me)),
	})


@rpc("any_peer", "call_remote", "reliable")
func _rpc_report(report: Dictionary) -> void:
	if Net.is_host():
		_report = report


@rpc("authority", "call_remote", "reliable")
func _rpc_wriggle(on: bool) -> void:
	_wriggling = on
	if not on:
		Input.action_release(&"jump")


## Client: hold its clock estimate `by` seconds off the host's (0: let it go), the
## way a starved window's drifts (net/clock_sync.gd: both its offsets, every tick,
## over whatever the pings fold in).
@rpc("authority", "call_remote", "reliable")
func _rpc_skew(by: float) -> void:
	var clock: RefCounted = Net.get("_clock")
	if clock == null:
		return
	var samples: Array = clock.get("_samples")
	for sample: Variant in samples.duplicate():
		if bool((sample as Dictionary).get("skew", false)):
			samples.erase(sample)
	if is_zero_approx(by):
		if not is_zero_approx(_skew_by):
			clock.set("_offset_seconds", _skew_base)
			clock.set("_applied_offset", _skew_base)
		_skew_by = 0.0
		return
	if is_zero_approx(_skew_by):
		_skew_base = float(clock.call("offset_seconds"))
	_skew_by = by
	# A sample no ping beats (no round trip, and it never ages out): every pong
	# folded in meanwhile keeps the skewed offset.
	samples.append({"rtt": 0.0, "offset": _skew_base + by, "at": 1.0e12, "skew": true})
	_hold_skew()


func _hold_skew() -> void:
	if is_zero_approx(_skew_by):
		return
	var clock: RefCounted = Net.get("_clock")
	if clock != null:
		clock.set("_offset_seconds", _skew_base + _skew_by)
		clock.set("_applied_offset", _skew_base + _skew_by)


## Client: the next ticks' turns are the test's own teleport, not the game's.
@rpc("authority", "call_remote", "reliable")
func _rpc_yaw_skip(ticks: int) -> void:
	_yaw_skip = maxi(_yaw_skip, ticks)
	_yaw_prev.clear()


## Client: knocked flat, as by a heavy throw (step 6b).
@rpc("authority", "call_remote", "reliable")
func _rpc_knock() -> void:
	var me := _own()
	if me != null:
		me.call("on_bonked", Vector3.ZERO, "heavy")


@rpc("authority", "call_remote", "reliable")
func _rpc_leave() -> void:
	get_tree().create_timer(0.1).timeout.connect(func() -> void: get_tree().quit())


# ---------------------------------------------------------------- helpers

func _step(text: String, passed: bool) -> void:
	_steps.append({"step": text, "ok": passed})
	_ok = _ok and passed
	print("[EncounterTest] %s %s" % ["ok  " if passed else "FAIL", text])


func _note(text: String) -> void:
	_steps.append({"step": text, "ok": true, "note": true})
	print("[EncounterTest] note %s" % text)


func _finish() -> void:
	result = {"ok": _ok, "steps": _steps, "pending_stage": PENDING_STAGE, "pending_shuttle": PENDING_SHUTTLE, "stats": _Encounter.stats.duplicate(), "done": true}
	print("[EncounterTest] all ok: %s" % _ok)


func _finish_with(problem: String) -> void:
	_step(problem, false)
	_finish()


func _last_log(event: String, peer_id: int) -> Dictionary:
	var found: Dictionary = {}
	for entry: Dictionary in _Encounter.log:
		if str(entry["event"]) == event and int(entry["peer"]) == peer_id:
			found = entry
	return found


func _wait(check: Callable, seconds: float) -> bool:
	var waited := 0.0
	while waited < seconds:
		if bool(check.call()):
			return true
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	return bool(check.call())


func _until(at: float) -> void:
	while Net.server_time() < at:
		await get_tree().physics_frame


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _safe(peer_id: int, seconds: float) -> void:
	var safe: Dictionary = _director().get("_safe_until")
	safe[peer_id] = Net.server_time() + seconds


func _tally(key: String) -> float:
	return float((Campaign.get("_day_tally") as Dictionary).get(key, 0.0))


func _xp(reason: String) -> int:
	return int(((Campaign.get("_day_tally") as Dictionary).get("xp", {}) as Dictionary).get(reason, 0))


func _holder(peer_id: int) -> Node3D:
	var encounter := _encounter()
	var index := int(encounter.call("crew_of", peer_id))
	for member: Node in _crew_all():
		if int(member.call("crew_index")) == index:
			return member as Node3D
	return null


func _nearest_crew(at: Vector3) -> Node3D:
	var best: Node3D = null
	var distance := INF
	for member: Node in _crew_all():
		var body := member as Node3D
		if body.global_position.distance_to(at) < distance and bool(member.call("in_brain_mode")):
			distance = body.global_position.distance_to(at)
			best = body
	return best


func _put_crew(crew: Node3D, at: Vector3, facing: Vector3) -> void:
	# The test's own teleport isn't a turn (and the client sees it a lag later, its
	# smoother drawing the jump over a few frames: P1 catch, the haul step's).
	_yaw_skip = maxi(_yaw_skip, 30)
	if _client != 0 and Net.peer_ids().has(_client):
		_rpc_yaw_skip.rpc_id(_client, 45)
	crew.global_position = at
	var look := facing - at
	crew.rotation.y = atan2(look.x, look.z)
	crew.reset_physics_interpolation()


func _grab(item: Node3D) -> void:
	var me := _own()
	await get_tree().physics_frame
	item.global_position = me.global_position + Vector3(0.0, 0.4, 0.0) + (-me.global_basis.z) * 0.8
	item.set("linear_velocity", Vector3.ZERO)
	await _ticks(2)
	item.call("request_grab")
	await _ticks(3)


func _drop_all() -> void:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == Net.local_peer_id():
			node.call("request_drop")


func _move_to(at: Vector3, yaw: float) -> void:
	var me := _own()
	me.call("apply_network_teleport", Transform3D(Basis(Vector3.UP, yaw), at))
	me.set("body_yaw", yaw)


func _teleport(peer_id: int, at: Vector3) -> void:
	var body := _player(peer_id)
	if body != null:
		body.call("send_teleport", Transform3D(Basis.IDENTITY, at))


func _crew_all() -> Array[Node]:
	var out: Array[Node] = []
	for member: Node in get_tree().get_nodes_in_group("nice_crew"):
		if not member.is_queued_for_deletion():
			out.append(member)
	return out


func _prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null


func _director() -> Node:
	return get_tree().get_first_node_in_group("run_director")


func _encounter() -> Node:
	return get_tree().get_first_node_in_group("nice_encounter")


func _own() -> Node3D:
	return _player(Net.local_peer_id())


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null
