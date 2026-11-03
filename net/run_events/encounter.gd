extends Node

## Authority: host decides every catch, free and stage; every peer plays them.
## World/RunDirector/Encounter (group "nice_encounter"), made by the run director
## on every peer, so its RPCs never ride on spawned crew (R2 chunk 2; docs/GAME.md
## "The NICE BOYS encounter (R2)", docs/NETCODE.md "R2: the catch"). It owns each
## caught player's stage, from the wind-up to the van door:
##
##   WINDUP   host_windup: every peer plays the same 0.35 s wind-up (stretched by the
##            target's half round trip, up to 0.15 s) and 2.2 m lunge from the RPC's
##            args; the host's verdict at contact_at, in its own view plus slack,
##            is a catch or a whiff (he sprawls, the target gets a moment's grace)
##   GOTCHA   the hand lands: slap and whistle chirp, both bodies held for the
##            hit-stop, the caught player's camera eases into a low two-shot with a
##            slow push-in, the held grin, "Gotcha! Have a NICE day!"
##   CITE     he writes it up; mashing jump buys time (CATCH_WRIGGLE_*); a friend's
##            bonk or punch on him frees you (host_free)
##   ESCORT   page torn, sticker slapped on, your things out in an itemized row,
##            arm in arm to the van door on his EscortAnchor, on every peer
##   SEATED   at the door: the Shuttle seats you (chunk 4, group "nice_shuttle");
##            without it you wait at the door until the old ride leaves
##   RIDING, ANNEX, RETURNING, FREE   set by the Shuttle and the Annex through
##            host_set_stage (or by the director, without them)
##
## Every staged moment is {stage, at, args}: a peer plays it from server time at;
## late by up to BEAT_SKIP it catches up, later it snaps to where it should be
## without the sound. Game logic runs on host timers from constants, never on
## animation signals. The caught player's body is placed through chunk 1's
## player.set_staged on every peer, the camera through player.stage_push, the
## input through player.set_control_lock (has_method guards; contracts C2, C3).

enum Stage { NONE, WINDUP, GOTCHA, CITE, ESCORT, BOARDING, SEATED, RIDING, ANNEX, RETURNING, FREE }

signal stage_changed(peer_id: int, stage: int)
signal peer_caught(peer_id: int)

const _Crew = preload("res://npcs/crew_member.gd")
## The escort's follow shot hangs off the pair at chest height (m), so its spring
## never catches on the lawn.
const _FOLLOW_HEIGHT: float = 1.2
## The scribble loop's length (s), for repeating it under the cite.
const _SCRIBBLE_LOOP: float = 1.15
const _NiceSeal = preload("res://props/nice_seal.gd")

## Totals for this process, for net/dev/probe.gd and the encounter test.
static var stats: Dictionary = {"windups": 0, "catches": 0, "whiffs": 0, "frees": 0, "wriggles": 0, "escorts": 0, "seated": 0}
## What this peer saw, in order: {"event", "peer", "at", "seen"} (seen: this peer's
## server time when it arrived), for the encounter test's timing checks.
static var log: Array[Dictionary] = []

## peer -> {"stage": int, "at": float, "crew": int (crew index, 0 none), "args": {}}
var _stages: Dictionary = {}
## grab_id -> {"crew": int, "peer": int, "from": Vector3, "dir": Vector3, "contact": float, "spot": bool, "lunged": bool, "travel": float}
var _grabs: Dictionary = {}
var _next_grab: int = 1
## Host: no grab before this server time, per peer (a whiff's grace).
var _grace_until: Dictionary = {}
## Every peer: when each cite ends (the host moves it with wriggles).
var _cite_end: Dictionary = {}
## Host: how much each peer's wriggles have bought.
var _wriggled: Dictionary = {}
## Owner: when the last wriggle went out.
var _last_wriggle: float = -10.0
## Every peer: which timeline beats have played, per peer ("grab", "bark", ...).
var _played: Dictionary = {}
## Every peer: where each caught player is held during the gotcha and the cite,
## and where they wait at the van door (local Node3Ds, the same on every peer).
var _holds: Dictionary = {}
## Every peer: the courtesy notice on each caught player's chest.
var _stickers: Dictionary = {}
## The local player's two-shot camera anchor, and the escort's follow anchor.
var _shot: Node3D
var _follow: Node3D
var _follow_target: Node3D
var _follow_yaw: float = 0.0
var _scribble_next: float = 0.0
var _constants: Dictionary = {}


func _ready() -> void:
	add_to_group("nice_encounter")
	_constants = load("res://core/constants.gd").get_script_constant_map()
	if not Net.player_left.is_connected(_on_player_left):
		Net.player_left.connect(_on_player_left)


func _k(key: String, fallback: Variant) -> Variant:
	return _constants.get(key, fallback)


# ---------------------------------------------------------------- queries (every peer)

func stage_of(peer_id: int) -> int:
	return int((_stages.get(peer_id, {}) as Dictionary).get("stage", Stage.NONE))


func stage_at(peer_id: int) -> float:
	return float((_stages.get(peer_id, {}) as Dictionary).get("at", 0.0))


## The NICE BOY holding this peer (index), or 0.
func crew_of(peer_id: int) -> int:
	return int((_stages.get(peer_id, {}) as Dictionary).get("crew", 0))


## The escorted player's anchor (the NICE BOY's EscortAnchor), or null.
func escort_anchor(peer_id: int) -> Node3D:
	var crew := _crew(crew_of(peer_id))
	return crew.call("escort_anchor") as Node3D if crew != null else null


func cite_end(peer_id: int) -> float:
	return float(_cite_end.get(peer_id, 0.0))


## Peers in this stage now.
func peers_in(stage: int) -> Array[int]:
	var out: Array[int] = []
	for peer_id: int in _stages:
		if stage_of(peer_id) == stage:
			out.append(peer_id)
	return out


## True while a grab on this peer is winding up or lunging.
func is_grabbed(peer_id: int) -> bool:
	for grab: Dictionary in _grabs.values():
		if int(grab["peer"]) == peer_id:
			return true
	return false


# ---------------------------------------------------------------- the host's calls

## Host: crew winds up to grab peer_id. from_spot (a found hider): no lunge, the
## hand lands CREW_FOUND_CONTACT s from now, no verdict. False when the grab isn't
## allowed (can't be caught, grace, already grabbed, airborne).
func host_windup(crew: Node, peer_id: int, from_spot: bool = false) -> bool:
	if not Net.is_host() or crew == null:
		return false
	var director := get_parent()
	var player := _player(peer_id)
	if player == null:
		return false
	# Carried by a friend: he goes for the one doing the carrying.
	var carrier := int(player.get("carried_by"))
	if carrier != 0 and not from_spot:
		peer_id = carrier
		player = _player(carrier)
		if player == null:
			return false
	if not bool(director.call("can_capture", peer_id)):
		return false
	if float(_grace_until.get(peer_id, 0.0)) > Net.server_time() or is_grabbed(peer_id) or stage_of(peer_id) != Stage.NONE:
		return false
	if bool(player.get("thrown")) and not from_spot:
		return false
	var index := int(crew.call("crew_index"))
	for grab: Dictionary in _grabs.values():
		if int(grab["crew"]) == index:
			return false
	var now := Net.server_time()
	var lead := Constants.CREW_FOUND_CONTACT if from_spot else Constants.CREW_LUNGE_WINDUP + minf(_rtt_seconds(peer_id) * 0.5, Constants.CREW_LUNGE_WINDUP_LAG_MAX)
	var from := (crew as Node3D).global_position
	var toward := player.global_position - from
	toward.y = 0.0
	var dir := toward.normalized() if toward.length() > 0.05 else (crew.call("facing") as Vector3)
	var grab_id := _next_grab
	_next_grab += 1
	crew.call("host_set_mode", _Crew.Mode.WINDUP, peer_id, dir)
	if not from_spot:
		crew.call("bark", "lunge", true)
	# His body travels until the hand lands: never into your face (he stops a
	# shoulder's width short of where you stood).
	var travel := clampf(toward.length() - Constants.CATCH_GOTCHA_GAP, 0.0, Constants.CREW_LUNGE_DISTANCE - Constants.CREW_LUNGE_ARM)
	_rpc_windup.rpc(grab_id, index, peer_id, from, dir, now + lead, from_spot, travel)
	return true


## Host: caught, with no lunge (force_capture, a found hider after the inspection,
## a scenario). Without a crew member the player goes straight to the van door.
func host_begin_catch(peer_id: int, crew: Node = null, grab_id: int = 0) -> void:
	if not Net.is_host() or stage_of(peer_id) != Stage.NONE and stage_of(peer_id) != Stage.WINDUP:
		return
	var director := get_parent()
	var player := _player(peer_id)
	if player == null:
		return
	director.call("note_capture", peer_id)
	var now := Net.server_time()
	var at := now if grab_id != 0 else now + float(_k("BEAT_LEAD", 0.15))
	var victim := player.global_position
	if crew == null:
		_rpc_catch.rpc(grab_id, 0, peer_id, at, victim, Vector3.INF)
		# Straight to the door: the itemized row where they stood, then the van.
		_host_itemize(peer_id, victim, Vector3.FORWARD)
		_host_at_door(peer_id)
		return
	var toward := victim - (crew as Node3D).global_position
	toward.y = 0.0
	var dir := toward.normalized() if toward.length() > 0.05 else (crew.call("facing") as Vector3)
	var crew_at := victim - dir * Constants.CATCH_GOTCHA_GAP
	crew_at.y = (crew as Node3D).global_position.y
	crew.call("host_set_mode", _Crew.Mode.GOTCHA, peer_id, victim)
	crew.call("host_walk", Vector3.INF, 0.0)
	_cite_end[peer_id] = at + Constants.CATCH_CITE_AT + Constants.CATCH_CITE_SECONDS
	_wriggled[peer_id] = 0.0
	_rpc_catch.rpc(grab_id, int(crew.call("crew_index")), peer_id, at, victim, crew_at)


## Host: let a caught player go (a friend's bonk or punch during the cite or the
## escort, an unbuckle at the van, a wriggle). by_peer gets the rescue.
func host_free(peer_id: int, by_peer: int, cause: StringName) -> bool:
	if not Net.is_host():
		return false
	var stage := stage_of(peer_id)
	if stage == Stage.NONE or stage == Stage.FREE or stage == Stage.RIDING or stage == Stage.ANNEX or stage == Stage.RETURNING:
		return false
	var crew := _crew(crew_of(peer_id))
	_rpc_freed.rpc(peer_id, by_peer, String(cause), Net.server_time())
	var director := get_parent()
	director.call("host_release", peer_id, Constants.RESCUE_IMMUNITY)
	if crew != null:
		crew.set("_stun_left", Constants.RESCUE_STUN)
		crew.call("host_walk", Vector3.INF, 0.0)
		crew.call("host_set_mode", _Crew.Mode.CHASE, 0)
	if by_peer != 0 and by_peer != peer_id:
		if Campaign.has_method("add_rescue"):
			Campaign.call("add_rescue", by_peer, cause)
		else:
			Campaign.add_xp(Constants.XP_RESCUE, "rescue")
			Campaign.note_day("rescues", 1.0)
	return true


## Host: another chunk moves a caught player on (the Shuttle: BOARDING, SEATED,
## RIDING, RETURNING, FREE; the Annex: ANNEX; the director: RIDING, FREE).
func host_set_stage(peer_id: int, stage: int, args: Dictionary = {}) -> void:
	if not Net.is_host():
		return
	if stage == Stage.FREE and stage_of(peer_id) == Stage.NONE:
		return
	# Let go of mid-catch (released by the director, a reset): he's back on the chase.
	var holder := _crew(crew_of(peer_id))
	if holder != null and stage != Stage.ESCORT and stage != Stage.CITE and [_Crew.Mode.GOTCHA, _Crew.Mode.CITE, _Crew.Mode.ESCORT].has(int(holder.get("mode"))):
		holder.call("host_walk", Vector3.INF, 0.0)
		holder.call("host_set_mode", _Crew.Mode.CHASE, 0)
	var crew := crew_of(peer_id)
	if stage != Stage.ESCORT and stage != Stage.GOTCHA and stage != Stage.CITE:
		crew = 0
	_rpc_stage.rpc(peer_id, stage, Net.server_time(), crew, args)


## Host, from crew_member.gd: a NICE BOY was hit by something thrown or a punch
## (by_peer, 0 when unknown). A wind-up is spoiled; a caught player is let go.
func host_crew_bonked(crew: Node, by_peer: int) -> void:
	if not Net.is_host() or crew == null:
		return
	var index := int(crew.call("crew_index"))
	for grab_id: int in _grabs.keys():
		if int(_grabs[grab_id]["crew"]) == index:
			_host_whiff(grab_id, false)
	for peer_id: int in _stages.keys():
		var stage := stage_of(peer_id)
		if crew_of(peer_id) == index and (stage == Stage.GOTCHA or stage == Stage.CITE or stage == Stage.ESCORT) and by_peer != peer_id:
			host_free(peer_id, by_peer, &"bonk")


# ---------------------------------------------------------------- the host's tick

func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if Net.is_host():
		_host_grabs()
		_host_stages()
	_local_wriggle()


func _host_grabs() -> void:
	var now := Net.server_time()
	for grab_id: int in _grabs.keys():
		var grab: Dictionary = _grabs[grab_id]
		var crew := _crew(int(grab["crew"]))
		if crew == null or bool(crew.call("is_stunned")):
			_host_whiff(grab_id, false)
			continue
		var spot := bool(grab["spot"])
		if not spot and not bool(grab["lunged"]) and now >= float(grab["contact"]) - Constants.CREW_LUNGE_SECONDS:
			grab["lunged"] = true
			crew.call("host_set_mode", _Crew.Mode.LUNGE, int(grab["peer"]), grab["dir"])
		if now < float(grab["contact"]):
			continue
		var peer_id := int(grab["peer"])
		var player := _player(peer_id)
		var director := get_parent()
		var can := player != null and bool(director.call("can_capture", peer_id))
		if can and not spot:
			can = _hand_reaches(grab, player.global_position)
		if can:
			_grabs.erase(grab_id)
			host_begin_catch(peer_id, crew, grab_id)
		else:
			_host_whiff(grab_id, true)


## The verdict on the lunge every peer drew: his hand sweeps from where he wound up
## to his body's travel plus his arm along dir (crew_member.gd's "lunge"
## placement), and the target's chest has to be within reach plus slack of that
## path. Someone who ran into the lunge is caught as surely as one at its end;
## someone who stepped back out of it is not.
func _hand_reaches(grab: Dictionary, target: Vector3) -> bool:
	var from: Vector3 = grab["from"]
	var dir: Vector3 = grab["dir"]
	var reach := float(grab.get("travel", Constants.CREW_LUNGE_DISTANCE - Constants.CREW_LUNGE_ARM)) + Constants.CREW_LUNGE_ARM
	var along := clampf((target - from).dot(dir), 0.0, reach)
	var hand := from + dir * along + Vector3.UP * 1.2
	var chest := target + Vector3.UP * 1.2
	return hand.distance_to(chest) <= Constants.CREW_GRAB_REACH + Constants.CREW_GRAB_SLACK


## Host: the grab missed (or was spoiled, sheepish = false: no sprawl, a bonk did it).
func _host_whiff(grab_id: int, sheepish: bool) -> void:
	var grab: Dictionary = _grabs.get(grab_id, {})
	if grab.is_empty():
		return
	_grabs.erase(grab_id)
	var crew := _crew(int(grab["crew"]))
	var peer_id := int(grab["peer"])
	_grace_until[peer_id] = Net.server_time() + Constants.CREW_WHIFF_GRACE
	if crew != null and sheepish:
		crew.call("host_set_mode", _Crew.Mode.WHIFF, peer_id)
		crew.call("bark", "whiff", true)
	elif crew != null:
		crew.call("host_set_mode", _Crew.Mode.CHASE, peer_id)
	# Who and by whom ride along: the host has already let go of the grab, and a
	# late joiner may never have had it.
	_rpc_whiff.rpc(grab_id, peer_id, int(grab["crew"]), Net.server_time())


func _host_stages() -> void:
	var now := Net.server_time()
	for peer_id: int in _stages.keys():
		var entry: Dictionary = _stages[peer_id]
		var stage := int(entry["stage"])
		var crew := _crew(int(entry["crew"]))
		match stage:
			Stage.GOTCHA:
				if now >= float(entry["at"]) + Constants.CATCH_CITE_AT and crew != null and int(crew.get("mode")) == _Crew.Mode.GOTCHA:
					crew.call("host_set_mode", _Crew.Mode.CITE, peer_id)
			Stage.CITE:
				pass
		if (stage == Stage.GOTCHA or stage == Stage.CITE) and now >= cite_end(peer_id) and crew != null:
			_host_end_cite(peer_id, crew, entry)
		elif stage == Stage.ESCORT and crew != null:
			_host_escort(peer_id, crew, entry, now)
		elif (stage == Stage.GOTCHA or stage == Stage.CITE or stage == Stage.ESCORT) and crew == null:
			# He's gone (a disconnect, a reset): straight to the door.
			_host_at_door(peer_id)


## Host: the cite is written. Page torn, sticker on, things out in a row, and arm
## in arm toward the van CATCH_ESCORT_AFTER s later.
func _host_end_cite(peer_id: int, crew: Node, entry: Dictionary) -> void:
	var now := Net.server_time()
	var args: Dictionary = entry["args"]
	var victim: Vector3 = args.get("victim", (crew as Node3D).global_position)
	var crew_at: Vector3 = args.get("crew_at", (crew as Node3D).global_position)
	var facing := victim - crew_at
	facing.y = 0.0
	facing = facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	_rpc_stage.rpc(peer_id, Stage.ESCORT, now + Constants.CATCH_ESCORT_AFTER, int(crew.call("crew_index")), {"tear_at": now, "victim": victim, "crew_at": crew_at})
	_host_itemize(peer_id, victim, facing)
	stats["escorts"] = int(stats["escorts"]) + 1


## Host: the held tool and the pockets, out in a row beside the pair.
func _host_itemize(peer_id: int, victim: Vector3, facing: Vector3) -> void:
	var hotbar := get_tree().get_first_node_in_group("hotbar")
	var side := facing.cross(Vector3.UP).normalized()
	var origin := victim + side * 0.9 - facing * 0.3
	origin.y = victim.y
	if hotbar != null and hotbar.has_method("host_empty_pockets"):
		hotbar.call("host_empty_pockets", peer_id, "itemized", origin, facing)
		return
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == peer_id and node.has_method("force_release"):
			node.call("force_release")


## Host: walking you to the van door; at it, the Shuttle takes over.
func _host_escort(peer_id: int, crew: Node, entry: Dictionary, now: float) -> void:
	if now < float(entry["at"]):
		return
	if int(crew.get("mode")) != _Crew.Mode.ESCORT:
		crew.call("host_set_mode", _Crew.Mode.ESCORT, peer_id)
		crew.call("bark", "escort", true)
	var door := _door_point()
	var walked := now - float(entry["at"])
	if walked > Constants.CREW_ESCORT_MAX + Constants.CREW_ESCORT_GIVE_UP:
		# Pinned somewhere (a fence, off the navmesh): you're handed to the door
		# from here, and he's back on the chase (host_set_stage lets him go).
		crew.call("host_walk", Vector3.INF, 0.0)
		_host_at_door(peer_id)
		return
	var late := walked > Constants.CREW_ESCORT_MAX
	crew.call("host_walk", door, Constants.CREW_SPEED_ESCORT_LATE if late else Constants.CREW_SPEED_ESCORT)
	var at := (crew as Node3D).global_position
	if Vector2(at.x - door.x, at.z - door.z).length() <= Constants.CATCH_DOOR_REACH:
		crew.call("host_walk", Vector3.INF, 0.0)
		crew.call("host_set_mode", _Crew.Mode.DOOR, peer_id)
		crew.call("bark", "door", true)
		_host_at_door(peer_id)
		# Back to the chase once you're handed over.
		get_tree().create_timer(Constants.CATCH_DOOR_HANDOFF_SECONDS).timeout.connect(func() -> void:
			if is_instance_valid(crew) and int(crew.get("mode")) == _Crew.Mode.DOOR:
				crew.call("host_set_mode", _Crew.Mode.CHASE, 0))


## Host: at the van door. The Shuttle seats you (chunk 4); without it you wait at
## the door until the director's fallback ride leaves with you.
func _host_at_door(peer_id: int) -> void:
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if shuttle != null and shuttle.has_method("host_board"):
		host_set_stage(peer_id, Stage.BOARDING)
		shuttle.call("host_board", peer_id)
		return
	var door := _door_point()
	host_set_stage(peer_id, Stage.SEATED, {"door": door, "facing": _door_facing()})
	stats["seated"] = int(stats["seated"]) + 1


## Where escorts end: the Shuttle's door step, else beside the fallback van's open
## side (net/run_events/van_arrival.gd), else the director's park point.
func _door_point() -> Vector3:
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if shuttle != null and shuttle.has_method("door_step_point"):
		return shuttle.call("door_step_point")
	var look := _fallback_van()
	if look != null:
		return look.global_transform * Vector3(Constants.CREW_VAN_CURB_X + 0.4, 0.0, 0.9)
	return get_parent().call("van_park_point")


func _door_facing() -> Vector3:
	var look := _fallback_van()
	if look != null:
		return -look.global_basis.x
	return Vector3.FORWARD


func _fallback_van() -> Node3D:
	var arrival := get_tree().get_first_node_in_group("van_arrival")
	if arrival != null and arrival.has_method("van_look"):
		return arrival.call("van_look") as Node3D
	return null


# ---------------------------------------------------------------- wriggling

## The caught player's own peer: mashing jump during the cite asks for time.
func _local_wriggle() -> void:
	var me := Net.local_peer_id()
	if stage_of(me) != Stage.CITE and stage_of(me) != Stage.GOTCHA:
		return
	if Net.server_time() < stage_at(me) + Constants.CATCH_CITE_AT:
		return
	if not Input.is_action_just_pressed("jump"):
		return
	var now := Net.server_time()
	if now - _last_wriggle < 1.0 / Constants.CATCH_WRIGGLE_RATE:
		return
	_last_wriggle = now
	if Net.is_host():
		_host_wriggle(me)
	else:
		_rpc_request_wriggle.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_wriggle() -> void:
	if Net.is_host():
		_host_wriggle(multiplayer.get_remote_sender_id())


func _host_wriggle(peer_id: int) -> void:
	var stage := stage_of(peer_id)
	if stage != Stage.CITE and stage != Stage.GOTCHA:
		return
	var bought := float(_wriggled.get(peer_id, 0.0))
	if bought >= Constants.CATCH_WRIGGLE_MAX:
		return
	var add := minf(Constants.CATCH_WRIGGLE_ADD, Constants.CATCH_WRIGGLE_MAX - bought)
	_wriggled[peer_id] = bought + add
	stats["wriggles"] = int(stats["wriggles"]) + 1
	var crew := _crew(crew_of(peer_id))
	if crew != null:
		crew.call("bark", "cite_wriggle")
	_rpc_cite_end.rpc(peer_id, cite_end(peer_id) + add)


## Every peer: the cite runs longer; he rubs the line out and starts again, you twist.
@rpc("authority", "call_local", "reliable")
func _rpc_cite_end(peer_id: int, end_at: float) -> void:
	_cite_end[peer_id] = end_at
	_log("wriggle", peer_id, end_at)
	var victim_body := _body_of(_player(peer_id))
	if victim_body != null:
		victim_body.call("gesture", "shuffle")
	var crew := _crew(crew_of(peer_id))
	var poser := crew.get_node_or_null("Visual/CartoonBody/Poser") if crew != null else null
	if poser != null:
		poser.call("hold", "")
		poser.call("hold", "cite_scribble")


# ---------------------------------------------------------------- RPCs (every peer)

@rpc("authority", "call_local", "reliable")
func _rpc_windup(grab_id: int, crew_index: int, peer_id: int, from: Vector3, dir: Vector3, contact_at: float, from_spot: bool, travel: float) -> void:
	_grabs[grab_id] = {"crew": crew_index, "peer": peer_id, "from": from, "dir": dir, "contact": contact_at, "spot": from_spot, "lunged": false, "travel": travel}
	if Net.is_host():
		stats["windups"] = int(stats["windups"]) + 1
	_log("windup", peer_id, contact_at)
	var crew := _crew(crew_index)
	if crew != null:
		crew.call("play_windup", from, dir, contact_at, from_spot, travel)
	_set_stage_local(peer_id, Stage.WINDUP, Net.server_time(), crew_index, {"contact": contact_at})


@rpc("authority", "call_local", "reliable")
func _rpc_whiff(grab_id: int, peer_id: int, crew_index: int, at: float) -> void:
	_grabs.erase(grab_id)
	if Net.is_host():
		stats["whiffs"] = int(stats["whiffs"]) + 1
	_log("whiff", peer_id, at)
	var crew := _crew(crew_index)
	if crew != null:
		crew.call("release_placement")
	if stage_of(peer_id) == Stage.WINDUP:
		_stages.erase(peer_id)
		stage_changed.emit(peer_id, Stage.NONE)


@rpc("authority", "call_local", "reliable")
func _rpc_catch(grab_id: int, crew_index: int, peer_id: int, at: float, victim: Vector3, crew_at: Vector3) -> void:
	_grabs.erase(grab_id)
	if Net.is_host():
		stats["catches"] = int(stats["catches"]) + 1
	_log("catch", peer_id, at)
	var director := get_parent()
	director.call("mark_caught", peer_id, true)
	_cite_end[peer_id] = at + Constants.CATCH_CITE_AT + Constants.CATCH_CITE_SECONDS
	var crew := _crew(crew_index)
	var player := _player(peer_id)
	if crew != null and crew_at.is_finite():
		var toward := victim - crew_at
		crew.call("play_stand", crew_at, atan2(toward.x, toward.z), Constants.CATCH_HITSTOP)
		_pair_collisions(player, crew, true)
	if player != null and crew != null and crew_at.is_finite():
		var hold := _hold_node(peer_id)
		var face := crew_at - victim
		face.y = 0.0
		hold.global_transform = Transform3D(Basis.looking_at(face.normalized() if face.length() > 0.01 else Vector3.FORWARD, Vector3.UP), victim)
		_stage_body(player, hold, Transform3D.IDENTITY, Constants.CATCH_CAM_BLEND, &"stand")
	_played[peer_id] = {}
	if peer_id == Net.local_peer_id() and player != null:
		_lock(player, &"nice_cite", true)
		# Out of a pile, off a seat: the gotcha is on your feet.
		if bool(player.get("in_pile")) and player.has_method("set_pile"):
			player.call("set_pile", false)
	_set_stage_local(peer_id, Stage.GOTCHA, at, crew_index, {"victim": victim, "crew_at": crew_at})
	peer_caught.emit(peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_stage(peer_id: int, stage: int, at: float, crew_index: int, args: Dictionary) -> void:
	_log("stage_%d" % stage, peer_id, at)
	var player := _player(peer_id)
	var was := stage_of(peer_id)
	match stage:
		Stage.ESCORT:
			# The pair walks as one: you on his EscortAnchor, on every peer.
			var crew := _crew(crew_index)
			_played[peer_id] = (_played.get(peer_id, {}) as Dictionary)
			if crew != null and player != null:
				_pair_collisions(player, crew, true)
		Stage.SEATED:
			var crew_was := _crew(crew_of(peer_id))
			if crew_was != null:
				crew_was.call("release_placement")
				_pair_collisions(player, crew_was, false)
			if player != null and args.has("door"):
				var hold := _hold_node(peer_id)
				var facing: Vector3 = args.get("facing", Vector3.FORWARD)
				hold.global_transform = Transform3D(Basis.looking_at(facing, Vector3.UP), args["door"])
				_stage_body(player, hold, Transform3D.IDENTITY, Constants.ESCORT_LINK_BLEND, &"stand")
			if player != null and peer_id == Net.local_peer_id():
				_pop_shots(player)
				_lock(player, &"nice_cite", false)
				_lock(player, &"escort", false)
				_lock(player, &"van_seat", true)
		Stage.BOARDING:
			var crew_was := _crew(crew_of(peer_id))
			if crew_was != null:
				crew_was.call("release_placement")
				_pair_collisions(player, crew_was, false)
			if player != null and peer_id == Net.local_peer_id():
				_pop_shots(player)
				_lock(player, &"nice_cite", false)
				_lock(player, &"escort", false)
		Stage.RIDING, Stage.ANNEX, Stage.RETURNING:
			if player != null and _holds.has(peer_id):
				_unstage_body(player)
			if player != null and peer_id == Net.local_peer_id():
				_pop_shots(player)
				for reason: StringName in [&"nice_cite", &"escort"]:
					_lock(player, reason, false)
				if was == Stage.SEATED and not get_tree().get_first_node_in_group("nice_shuttle"):
					_lock(player, &"van_seat", false)
		Stage.FREE:
			_clear_peer(peer_id)
			director_mark(peer_id, false)
			_stages.erase(peer_id)
			stage_changed.emit(peer_id, Stage.FREE)
			return
	_set_stage_local(peer_id, stage, at, crew_index, args)


func director_mark(peer_id: int, caught: bool) -> void:
	get_parent().call("mark_caught", peer_id, caught)


@rpc("authority", "call_local", "reliable")
func _rpc_freed(peer_id: int, by_peer: int, cause: String, at: float) -> void:
	_log("freed_" + cause, peer_id, at)
	if Net.is_host():
		stats["frees"] = int(stats["frees"]) + 1
	var crew := _crew(crew_of(peer_id))
	var player := _player(peer_id)
	if crew != null and cause != "gone":
		# The clipboard goes flying and the forms flutter down.
		var body := _body_of(crew)
		if body != null:
			body.call("gesture", "flail")
		_flutter_forms((crew as Node3D).global_position + Vector3.UP * 1.4)
		var sfx := get_tree().get_first_node_in_group("sfx")
		if sfx != null and _plays_sound(at):
			sfx.call("play_on", "paper_tear", crew, -4.0)
	if player != null and cause != "gone":
		var body := _body_of(player)
		if body != null:
			body.call("gesture", "stumble")
	_peel_sticker(peer_id)
	_clear_peer(peer_id)
	director_mark(peer_id, false)
	_stages.erase(peer_id)
	stage_changed.emit(peer_id, Stage.FREE)
	if by_peer != 0:
		_log("rescued_by_%d" % by_peer, peer_id, at)


# ---------------------------------------------------------------- the timeline (every peer)

func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_move_follow(delta)
	var now := Net.server_time()
	for peer_id: int in _stages.keys():
		var entry: Dictionary = _stages[peer_id]
		var stage := int(entry["stage"])
		if stage == Stage.GOTCHA or stage == Stage.CITE:
			_play_gotcha(peer_id, entry, now)
		elif stage == Stage.ESCORT:
			_play_escort(peer_id, entry, now)
	_aim_two_shot(now)


## The gotcha and the cite, from the catch's server time, on every peer.
func _play_gotcha(peer_id: int, entry: Dictionary, now: float) -> void:
	var at := float(entry["at"])
	var t := now - at
	if t < 0.0:
		return
	var played: Dictionary = _played.get(peer_id, {})
	_played[peer_id] = played
	var crew := _crew(int(entry["crew"]))
	var player := _player(peer_id)
	var crew_body := _body_of(crew)
	var victim_body := _body_of(player)
	var sfx := get_tree().get_first_node_in_group("sfx")
	if not played.has("grab"):
		played["grab"] = true
		if _plays_sound(at) and sfx != null and player != null:
			sfx.call("play_on", "gotcha_grab", player, 0.0, false)
		if victim_body != null:
			victim_body.call("gesture", "startle")
		# The hit-stop runs its full length from when this peer hears of the catch
		# (a lunge's catch is sent at contact, so it lands one latency late), with
		# the slap; one later than BEAT_SKIP skips it, like any late beat.
		played["thaw_at"] = minf(now + Constants.CATCH_HITSTOP, at + Constants.CATCH_HITSTOP + float(_k("BEAT_SKIP", 0.5)))
		if now < float(played["thaw_at"]):
			_anim_speed(crew_body, 0.0)
			_anim_speed(victim_body, 0.0)
		if peer_id == Net.local_peer_id():
			var music := get_tree().get_first_node_in_group("music_director")
			if music != null and music.has_method("duck"):
				music.call("duck", Constants.CATCH_MUSIC_DUCK_DB, Constants.CATCH_HOLD_END)
	if not played.has("unfreeze") and now >= float(played.get("thaw_at", at + Constants.CATCH_HITSTOP)):
		played["unfreeze"] = true
		_anim_speed(crew_body, 1.0)
		_anim_speed(victim_body, 1.0)
		if peer_id == Net.local_peer_id() and player != null:
			_push_two_shot(player, t > 0.5)
	if not played.has("grin") and t >= Constants.CATCH_GRIN_AT:
		played["grin"] = true
		var poser := crew.get_node_or_null("Visual/CartoonBody/Poser") if crew != null else null
		if poser != null and int(crew.get("mode")) != _Crew.Mode.CITE:
			poser.call("hold", "grin_hold")
	if not played.has("bark") and t >= Constants.CATCH_BARK_AT:
		played["bark"] = true
		if crew != null and t < Constants.CATCH_BARK_AT + float(_k("BEAT_SKIP", 0.5)):
			crew.call("show_bark", "caught", 0)
	if t >= Constants.CATCH_CITE_AT:
		if int(entry["stage"]) == Stage.GOTCHA:
			entry["stage"] = Stage.CITE
			stage_changed.emit(peer_id, Stage.CITE)
		if now >= _scribble_next and crew != null and sfx != null and now < cite_end(peer_id):
			_scribble_next = now + _SCRIBBLE_LOOP
			sfx.call("play_on", "scribble", crew)


## The escort's start on every peer: the page torn, the sticker slapped on, then
## arm in arm on his EscortAnchor.
func _play_escort(peer_id: int, entry: Dictionary, now: float) -> void:
	var args: Dictionary = entry["args"]
	var played: Dictionary = _played.get(peer_id, {})
	_played[peer_id] = played
	var crew := _crew(int(entry["crew"]))
	var player := _player(peer_id)
	var sfx := get_tree().get_first_node_in_group("sfx")
	var tear_at := float(args.get("tear_at", entry["at"]))
	# Each beat waits for the nodes it needs (a late joiner's crew or player can
	# spawn after the stage arrives).
	if not played.has("tear") and now >= tear_at and crew != null:
		played["tear"] = true
		var poser := crew.get_node_or_null("Visual/CartoonBody/Poser")
		if poser != null:
			poser.call("hold", "grin_hold")
			poser.call("shot", "tear_page")
		if sfx != null and crew != null and _plays_sound(tear_at):
			sfx.call("play_on", "paper_tear", crew)
	if not played.has("slap") and now >= tear_at + Constants.CATCH_SLAP_AFTER and crew != null and player != null:
		played["slap"] = true
		var poser := crew.get_node_or_null("Visual/CartoonBody/Poser") if crew != null else null
		if poser != null:
			poser.call("shot", "slap_sticker")
		_add_sticker(peer_id, player)
		if sfx != null and player != null and _plays_sound(tear_at + Constants.CATCH_SLAP_AFTER):
			sfx.call("play_on", "sticker_slap", player)
	var anchor := crew.call("escort_anchor") as Node3D if crew != null else null
	if not played.has("link") and now >= float(entry["at"]) and player != null and anchor != null:
		played["link"] = true
		# He walks on his own feet now (the host's body, smoothed like any walk).
		crew.call("release_placement")
		_stage_body(player, anchor, Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), Constants.ESCORT_LINK_BLEND, &"escorted")
		if peer_id == Net.local_peer_id():
			_lock(player, &"nice_cite", false)
			_lock(player, &"escort", true)
			_start_follow(anchor)
			_push(player, &"escort", {
				"anchor": _follow,
				"offset": Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -0.38), Vector3(0.3, Constants.ESCORT_CAM_UP - _FOLLOW_HEIGHT, -Constants.ESCORT_CAM_BACK)),
				"blend_in": 0.6, "blend_out": 0.5, "orbit": true, "spring": false,
				"yaw_clamp": Vector2(-deg_to_rad(Constants.ESCORT_CAM_ORBIT_DEG), deg_to_rad(Constants.ESCORT_CAM_ORBIT_DEG)),
				"pitch_clamp": Vector2(-0.5, 0.3), "lag": 0.12, "priority": 40,
			})
			_pop(player, &"gotcha", 0.6)


# ---------------------------------------------------------------- the two-shot

## The caught player's camera: low and side-on, 3 m off, both faces in frame,
## pushing in a little through the hold (chunk 1's StageCam, priority 50).
func _push_two_shot(player: Node3D, late: bool) -> void:
	if _shot == null:
		_shot = Node3D.new()
		_shot.name = "TwoShot"
		add_child(_shot)
		_shot.top_level = true
	_aim_two_shot(Net.server_time())
	_push(player, &"gotcha", {"anchor": _shot, "offset": Transform3D.IDENTITY, "blend_in": 0.0 if late else Constants.CATCH_CAM_BLEND, "blend_out": 0.6, "fov": Constants.CATCH_CAM_FOV, "yaw_clamp": Vector2(-0.7, 0.7), "pitch_clamp": Vector2(-0.35, 0.35), "priority": 50})


func _aim_two_shot(now: float) -> void:
	var me := Net.local_peer_id()
	if _shot == null or (stage_of(me) != Stage.GOTCHA and stage_of(me) != Stage.CITE):
		return
	var entry: Dictionary = _stages[me]
	var args: Dictionary = entry["args"]
	var victim: Vector3 = args.get("victim", Vector3.ZERO)
	var crew_at: Vector3 = args.get("crew_at", victim + Vector3.FORWARD)
	var line := victim - crew_at
	line.y = 0.0
	line = line.normalized() if line.length() > 0.01 else Vector3.FORWARD
	var mid := (victim + crew_at) * 0.5 + Vector3.UP * Constants.CATCH_CAM_HEIGHT
	var push := clampf((now - float(entry["at"]) - Constants.CATCH_GRIN_AT) / (Constants.CATCH_HOLD_END - Constants.CATCH_GRIN_AT + Constants.CATCH_CITE_SECONDS), 0.0, 1.0)
	var distance := Constants.CATCH_CAM_DISTANCE * (1.0 - Constants.CATCH_PUSH_IN * 3.0 * push)
	var side := line.cross(Vector3.UP).normalized()
	# The side with room: whichever isn't a wall.
	if not args.has("shot_side"):
		args["shot_side"] = _clear_side(mid, side, distance)
	var eye := mid + side * float(args["shot_side"]) * distance - Vector3.UP * 0.2
	_shot.global_transform = Transform3D(Basis.looking_at(mid - eye, Vector3.UP), eye)


## Which side of the pair the two-shot sits on: the yard side first (the curb is
## lined with trees, and the yard is open lawn), unless a wall is in the way.
func _clear_side(mid: Vector3, side: Vector3, distance: float) -> float:
	var world := get_viewport().world_3d if get_viewport() != null else null
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var first := 1.0
	if lot != null:
		var toward := lot.global_position - mid
		toward.y = 0.0
		first = 1.0 if side.dot(toward) >= 0.0 else -1.0
	if world == null:
		return first
	for sign: float in [first, -first]:
		var query := PhysicsRayQueryParameters3D.create(mid, mid + side * sign * (distance + 0.3), 1)
		if world.direct_space_state.intersect_ray(query).is_empty():
			return sign
	return first


## The escort's follow shot hangs off this: on the pair, but turning slowly toward
## where they walk (he turns round in a step; the camera shouldn't whip round with him).
func _start_follow(anchor: Node3D) -> void:
	if _follow == null:
		_follow = Node3D.new()
		_follow.name = "EscortFollow"
		add_child(_follow)
		_follow.top_level = true
	_follow_target = anchor
	var camera := get_viewport().get_camera_3d()
	var look := -camera.global_basis.z if camera != null else -anchor.global_basis.z
	look.y = 0.0
	_follow_yaw = atan2(look.x, look.z) if look.length() > 0.01 else anchor.global_rotation.y
	_follow.global_transform = Transform3D(Basis(Vector3.UP, _follow_yaw), anchor.global_position + Vector3.UP * _FOLLOW_HEIGHT)


func _move_follow(delta: float) -> void:
	if _follow == null or not is_instance_valid(_follow_target) or not _follow_target.is_inside_tree():
		return
	var forward := _follow_target.global_basis.z
	forward.y = 0.0
	if forward.length() > 0.01:
		var want := atan2(forward.x, forward.z)
		var step := wrapf(want - _follow_yaw, -PI, PI)
		_follow_yaw += clampf(step, -Constants.ESCORT_CAM_TURN * delta, Constants.ESCORT_CAM_TURN * delta)
	_follow.global_transform = Transform3D(Basis(Vector3.UP, _follow_yaw), _follow_target.get_global_transform_interpolated().origin + Vector3.UP * _FOLLOW_HEIGHT)


# ---------------------------------------------------------------- stickers and forms

## The lavender Daisy Seal courtesy notice on the caught player's chest, for
## everyone to see (a friend across the yard knows).
func _add_sticker(peer_id: int, player: Node3D) -> void:
	var body := _body_of(player)
	if body == null or _stickers.has(peer_id):
		return
	var torso := body.get("_torso") as Node3D if "_torso" in body else null
	var sticker := _NiceSeal.node(0.085, Vector3.FORWARD)
	sticker.name = "CourtesyNotice"
	(torso if torso != null else body).add_child(sticker)
	sticker.position = Vector3(0.05, 0.3, -0.19)
	sticker.scale = Vector3.ONE * 0.2
	var grow := sticker.create_tween()
	grow.tween_property(sticker, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_stickers[peer_id] = sticker


## Freed: the notice peels off and flutters to the grass.
func _peel_sticker(peer_id: int) -> void:
	var sticker := _stickers.get(peer_id) as Node3D
	_stickers.erase(peer_id)
	if sticker == null or not is_instance_valid(sticker):
		return
	var at := sticker.global_transform
	sticker.get_parent().remove_child(sticker)
	add_child(sticker)
	sticker.top_level = true
	sticker.global_transform = at
	var fall := sticker.create_tween().set_parallel(true)
	fall.tween_property(sticker, "global_position", at.origin + Vector3(randf_range(-0.4, 0.4), -at.origin.y + 0.03 + _ground_y(at.origin), randf_range(-0.4, 0.4)), 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fall.tween_property(sticker, "rotation", Vector3(-PI * 0.5, randf_range(-PI, PI), 0.0), 1.1)
	fall.chain().tween_interval(4.0)
	fall.chain().tween_callback(sticker.queue_free)


func _ground_y(at: Vector3) -> float:
	var lot := get_tree().get_first_node_in_group("world")
	var zone := lot.get_node_or_null("LotZone") as Node3D if lot != null else null
	return zone.global_position.y if zone != null else at.y - 1.3


## A handful of forms off the clipboard, fluttering down.
func _flutter_forms(at: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.98, 0.97, 0.92)
	paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	for index: int in 4:
		var sheet := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.16, 0.21)
		sheet.mesh = quad
		sheet.material_override = paper
		add_child(sheet)
		sheet.top_level = true
		sheet.global_position = at + Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.3), randf_range(-0.2, 0.2))
		var land := Vector3(at.x + randf_range(-1.4, 1.4), _ground_y(at) + 0.02, at.z + randf_range(-1.4, 1.4))
		var drift := sheet.create_tween().set_parallel(true)
		drift.tween_property(sheet, "global_position:x", land.x, 1.6).set_trans(Tween.TRANS_SINE)
		drift.tween_property(sheet, "global_position:z", land.z, 1.6).set_trans(Tween.TRANS_SINE)
		drift.tween_property(sheet, "global_position:y", sheet.global_position.y + 0.6, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		drift.chain().tween_property(sheet, "global_position:y", land.y, 1.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		drift.tween_property(sheet, "rotation", Vector3(-PI * 0.5, randf_range(-PI, PI), randf_range(-0.3, 0.3)), 1.6)
		drift.chain().tween_interval(3.0)
		drift.chain().tween_callback(sheet.queue_free)


# ---------------------------------------------------------------- chunk 1's seams

## The caught player's body follows anchor * offset on every peer (chunk 1's
## player.set_staged). Without it, the owner holds still and others see the network.
func _stage_body(player: Node3D, anchor: Node3D, offset: Transform3D, blend: float, pose: StringName) -> void:
	if player != null and player.has_method("set_staged"):
		player.call("set_staged", anchor, offset, blend, pose)


func _unstage_body(player: Node3D) -> void:
	if player != null and player.has_method("clear_staged") and player.has_method("is_staged") and bool(player.call("is_staged")):
		player.call("clear_staged")


func _lock(player: Node3D, reason: StringName, on: bool) -> void:
	if player != null and player.has_method("set_control_lock"):
		player.call("set_control_lock", reason, on)


func _push(player: Node3D, id: StringName, shot: Dictionary) -> void:
	if player != null and player.has_method("stage_push"):
		player.call("stage_push", id, shot)


func _pop(player: Node3D, id: StringName, blend_out: float = -1.0) -> void:
	if player != null and player.has_method("stage_pop"):
		player.call("stage_pop", id, blend_out)


func _pop_shots(player: Node3D) -> void:
	_pop(player, &"gotcha", 0.5)
	_pop(player, &"escort", 0.5)


## Hit-stop: per-character animation speed (chunk 1's set_anim_speed), never
## Engine.time_scale. Without it, the body's own tick is paused.
func _anim_speed(body: Node, scale: float) -> void:
	if body == null:
		return
	if body.has_method("set_anim_speed"):
		body.call("set_anim_speed", scale)
	else:
		body.set_physics_process(scale > 0.0)
		var poser := body.get_node_or_null("Poser")
		if poser != null:
			poser.set_physics_process(scale > 0.0)


## The pair doesn't shove each other while he has hold of you.
func _pair_collisions(player: Node3D, crew: Node, apart: bool) -> void:
	var a := player as PhysicsBody3D
	var b := crew as PhysicsBody3D
	if a == null or b == null:
		return
	if apart:
		a.add_collision_exception_with(b)
		b.add_collision_exception_with(a)
	else:
		a.remove_collision_exception_with(b)
		b.remove_collision_exception_with(a)


## Every peer: everything about this peer's stage undone (freed, gone, reset).
func _clear_peer(peer_id: int) -> void:
	var player := _player(peer_id)
	var crew := _crew(crew_of(peer_id))
	if crew != null:
		crew.call("release_placement")
		_pair_collisions(player, crew, false)
		_anim_speed(_body_of(crew), 1.0)
	if player != null:
		_anim_speed(_body_of(player), 1.0)
		_unstage_body(player)
		if peer_id == Net.local_peer_id():
			_pop_shots(player)
			for reason: StringName in [&"nice_cite", &"escort", &"van_seat"]:
				_lock(player, reason, false)
	var hold := _holds.get(peer_id) as Node3D
	if hold != null and is_instance_valid(hold):
		hold.queue_free()
	_holds.erase(peer_id)
	_played.erase(peer_id)
	_cite_end.erase(peer_id)
	if not _stickers.has(peer_id):
		return
	_peel_sticker(peer_id)


func _hold_node(peer_id: int) -> Node3D:
	var hold := _holds.get(peer_id) as Node3D
	if hold == null or not is_instance_valid(hold):
		hold = Node3D.new()
		hold.name = "Hold%d" % peer_id
		add_child(hold)
		hold.top_level = true
		_holds[peer_id] = hold
	return hold


func _set_stage_local(peer_id: int, stage: int, at: float, crew_index: int, args: Dictionary) -> void:
	_stages[peer_id] = {"stage": stage, "at": at, "crew": crew_index, "args": args}
	stage_changed.emit(peer_id, stage)


# ---------------------------------------------------------------- late join and disconnects

## Host: everything a late joiner needs to see the catches under way.
func snapshot() -> Dictionary:
	var stages: Dictionary = {}
	for peer_id: int in _stages:
		var entry: Dictionary = _stages[peer_id]
		stages[peer_id] = {"stage": entry["stage"], "at": entry["at"], "crew": entry["crew"], "args": entry["args"], "cite_end": cite_end(peer_id)}
	# The grabs under way too: a whiff that follows finds its peer through them.
	return {"stages": stages, "grabs": _grabs.duplicate(true)}


## A late joiner: put every caught player where they are now, without the sounds.
func apply_snapshot(data: Dictionary) -> void:
	var grabs: Dictionary = data.get("grabs", {})
	for key: Variant in grabs:
		var grab: Dictionary = grabs[key]
		_grabs[int(key)] = grab
		var lunger := _crew(int(grab.get("crew", 0)))
		if lunger != null:
			lunger.call("play_windup", grab["from"], grab["dir"], float(grab["contact"]), bool(grab["spot"]), float(grab.get("travel", Constants.CREW_LUNGE_DISTANCE - Constants.CREW_LUNGE_ARM)))
	var stages: Dictionary = data.get("stages", {})
	for key: Variant in stages:
		var peer_id := int(key)
		var entry: Dictionary = stages[key]
		var stage := int(entry["stage"])
		var at := float(entry["at"])
		var crew_index := int(entry["crew"])
		var args: Dictionary = entry["args"]
		_cite_end[peer_id] = float(entry.get("cite_end", 0.0))
		get_parent().call("mark_caught", peer_id, true)
		_played[peer_id] = {"grab": true, "unfreeze": true, "bark": true, "tear": true, "slap": stage != Stage.ESCORT}
		if stage == Stage.GOTCHA or stage == Stage.CITE:
			_rpc_catch_local(peer_id, crew_index, args)
		if stage == Stage.ESCORT:
			_played[peer_id].erase("link")
			_add_sticker(peer_id, _player(peer_id))
		if stage == Stage.SEATED or stage == Stage.BOARDING:
			_rpc_stage(peer_id, stage, at, crew_index, args)
			continue
		_set_stage_local(peer_id, stage, at, crew_index, args)


func _rpc_catch_local(peer_id: int, crew_index: int, args: Dictionary) -> void:
	var crew := _crew(crew_index)
	var player := _player(peer_id)
	var victim: Vector3 = args.get("victim", Vector3.ZERO)
	var crew_at: Vector3 = args.get("crew_at", Vector3.INF)
	if crew != null and crew_at.is_finite():
		var toward := victim - crew_at
		crew.call("play_stand", crew_at, atan2(toward.x, toward.z), 0.0)
	if player != null and crew_at.is_finite():
		var hold := _hold_node(peer_id)
		var face := crew_at - victim
		face.y = 0.0
		hold.global_transform = Transform3D(Basis.looking_at(face.normalized() if face.length() > 0.01 else Vector3.FORWARD, Vector3.UP), victim)
		_stage_body(player, hold, Transform3D.IDENTITY, 0.0, &"stand")


func _on_player_left(peer_id: int) -> void:
	if not Net.is_host():
		return
	for grab_id: int in _grabs.keys():
		if int(_grabs[grab_id]["peer"]) == peer_id:
			_host_whiff(grab_id, false)
	_grace_until.erase(peer_id)
	_wriggled.erase(peer_id)
	if stage_of(peer_id) == Stage.NONE:
		return
	var crew := _crew(crew_of(peer_id))
	if crew != null:
		crew.call("host_walk", Vector3.INF, 0.0)
		crew.call("host_set_mode", _Crew.Mode.CHASE, 0)
	_rpc_freed.rpc(peer_id, 0, "gone", Net.server_time())


## Dev and tests (scenarios reset): every stage and grab dropped, on every peer.
func host_reset() -> void:
	if not Net.is_host():
		return
	for peer_id: int in _stages.keys():
		_rpc_freed.rpc(peer_id, 0, "gone", Net.server_time())
	for grab_id: int in _grabs.keys():
		_host_whiff(grab_id, false)
	_grace_until.clear()


# ---------------------------------------------------------------- helpers

func _plays_sound(at: float) -> bool:
	return Net.server_time() - at <= float(_k("BEAT_SKIP", 0.5))


func _log(event: String, peer_id: int, at: float) -> void:
	log.append({"event": event, "peer": peer_id, "at": at, "seen": Net.server_time()})
	if log.size() > 200:
		log.pop_front()


## The host's estimate of this peer's round trip (s): ENet's, plus any --sim-lag.
func _rtt_seconds(peer_id: int) -> float:
	if peer_id == Net.local_peer_id():
		return 0.0
	var ping := maxi(0, Net.peer_ping_ms(peer_id))
	return float(ping + Net.simulated_lag_ms()) / 1000.0


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _crew(index: int) -> Node3D:
	if index <= 0:
		return null
	for node: Node in get_tree().get_nodes_in_group("nice_crew"):
		if int(node.call("crew_index")) == index and not node.is_queued_for_deletion():
			return node as Node3D
	return null


func _body_of(node: Node) -> Node:
	return node.get_node_or_null("Visual/CartoonBody") if node != null else null
