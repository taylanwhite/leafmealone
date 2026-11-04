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
const _Sweep = preload("res://player/stage_sweep.gd")
const _CaughtPose = preload("res://player/caught_pose.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _StageCam = preload("res://player/stage_cam.gd")
## player.gd AnimState.KNOCKED: flat on the back.
const _KNOCKED: int = 5

## Totals for this process, for net/dev/probe.gd and the encounter test.
static var stats: Dictionary = {"windups": 0, "catches": 0, "whiffs": 0, "frees": 0, "wriggles": 0, "escorts": 0, "seated": 0, "rebased": 0, "hauls": 0, "board_holds": 0}
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
## How fast the follow shot is turning now (rad/s), eased.
var _follow_turn: float = 0.0
## R2c: how far the follow shot is swung off behind the pair to see past the van (rad).
var _follow_bias: float = 0.0
## Host: each escort's way to the door, {"via": Vector3 (INF: straight), "tried":
## Array of vias given up on, "best": distance to the goal, "since": when it last
## got closer, "stuck": seconds stuck in all}.
var _routes: Dictionary = {}
## Every peer: the boarding iris for the local player, {"close_at", "cut_done"}.
var _boarding: Dictionary = {}
var _scribble_next: float = 0.0
var _constants: Dictionary = {}
## Client: how far this peer moved each caught player's catch on its own clock
## (_rebased), so the host's later times for that catch (a wriggle's new cite end)
## move with it.
var _skew: Dictionary = {}
## Host: a haul-up's staging decided at its wind-up (where he ends up beside the
## body, where the two-shot looks from), used again by the catch, per peer.
var _down_staging: Dictionary = {}
## The local player's still view while boarding with nothing staged (P1 catch).
var _board_hold: Node3D


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
	# P1 catch (audit crew-13): someone knocked flat isn't lunged at (his arm and
	# belly filled their lens from above). He steps in beside their hips and reaches
	# down: the haul-up. Their two-shot starts now, from the ground.
	var down := not from_spot and is_down(player)
	# The whole crouch, then the lunge: contact is the wind-up AND the lunge away
	# (R2b: it used to be the wind-up alone, so the lunge ate all but 0.1 s of it).
	var lead := Constants.CREW_FOUND_CONTACT if from_spot else Constants.CREW_LUNGE_WINDUP + Constants.CREW_LUNGE_SECONDS + minf(_rtt_seconds(peer_id) * 0.5, Constants.CREW_LUNGE_WINDUP_LAG_MAX)
	var from := (crew as Node3D).global_position
	var toward := player.global_position - from
	toward.y = 0.0
	var dir := toward.normalized() if toward.length() > 0.05 else (crew.call("facing") as Vector3)
	# His body travels until the hand lands: never into your face (he stops a
	# shoulder's width short of where you stood).
	var travel := clampf(toward.length() - Constants.CATCH_GOTCHA_GAP, 0.0, Constants.CREW_LUNGE_DISTANCE - Constants.CREW_LUNGE_ARM)
	var haul: Dictionary = {}
	if down:
		var points := _down_points(player, from)
		var step: Vector3 = points["reach"] - from
		step.y = 0.0
		if step.length() > 0.05:
			dir = step.normalized()
		# He walks all the way over, however far (a lunge's reach doesn't limit it:
		# stopped short, his hand never got to them).
		travel = step.length()
		lead = haul_lead(travel)
		var stand: Vector3 = points["stand"]
		var crew_at: Vector3 = points["crew_at"]
		# Side on to the two of them as they'll stand once you're up (you where your
		# hips lay, him a step back from where he reached), so both faces read.
		var line := crew_at - stand
		line.y = 0.0
		var across := line.cross(Vector3.UP).normalized() if line.length() > 0.05 else dir.cross(Vector3.UP).normalized()
		var cam_yaw := _clear_side((stand + crew_at) * 0.5 + Vector3.UP * Constants.CATCH_CAM_HEIGHT, across, Constants.CATCH_CAM_DISTANCE)
		haul = {"stand": stand, "crew_at": crew_at, "cam_yaw": cam_yaw, "face": points["face"]}
		_down_staging[peer_id] = haul
	else:
		_down_staging.erase(peer_id)
	var grab_id := _next_grab
	_next_grab += 1
	crew.call("host_set_mode", _Crew.Mode.WINDUP, peer_id, dir)
	if not from_spot and not down:
		crew.call("bark", "lunge", true)
	_rpc_windup.rpc(grab_id, index, peer_id, from, dir, now + lead, from_spot, travel, haul)
	return true


## A haul-up's whole lead (s) for a walk over of `travel` m: the walk, then the
## squat and reach (CATCH_DOWN_BEND). The same on every peer from the wind-up's travel.
static func haul_lead(travel: float) -> float:
	var walk := clampf(travel / Constants.CATCH_DOWN_WALK, Constants.CATCH_DOWN_WALK_SECONDS.x, Constants.CATCH_DOWN_WALK_SECONDS.y)
	return walk + Constants.CATCH_DOWN_BEND


## Knocked flat right now (a heavy bonk, a fall, a punch's dizzy): on the ground,
## stars and all (player.gd AnimState.KNOCKED, replicated from the owner).
static func is_down(player: Node) -> bool:
	return player != null and "anim_state" in player and int(player.get("anim_state")) == _KNOCKED


## Host: a haul-up's places, from someone lying on their back (their feet at their
## origin, the head tipped back along +basis.z, player/cartoon_body.gd _apply_fall):
## reach, where he bends over beside their collar on his own side of them (never
## over the head); stand, where they come up (their hips stay put, the feet swing
## in under them); crew_at, where he ends up after the heave, a short step back
## from there; face, which way he looks down at the collar from reach.
func _down_points(player: Node3D, from: Vector3) -> Dictionary:
	var at := player.global_position
	var back := player.global_basis.z
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	var stand := at + back * Constants.CATCH_DOWN_HIPS_BACK
	var collar := at + back * Constants.CATCH_DOWN_COLLAR_BACK
	var side := back.cross(Vector3.UP).normalized()
	if side.dot(from - collar) < 0.0:
		side = -side
	var reach := collar + side * Constants.CATCH_DOWN_SIDE
	reach.y = from.y
	var off := reach - stand
	off.y = 0.0
	var crew_at := stand + (off.normalized() if off.length() > 0.05 else side) * Constants.CATCH_DOWN_GAP
	crew_at.y = from.y
	var face := collar - reach
	face.y = 0.0
	return {"reach": reach, "stand": stand, "crew_at": crew_at, "face": face.normalized() if face.length() > 0.05 else -side}


## Host: caught, with no lunge (force_capture, a found hider after the inspection,
## a scenario). Without a crew member the player goes straight to the van door.
## land (driving:F): where they're set down for the gotcha, pulled out of a seat
## in the crew's truck onto the road beside it; INF is where they stand.
func host_begin_catch(peer_id: int, crew: Node = null, grab_id: int = 0, land: Vector3 = Vector3.INF) -> void:
	if not Net.is_host() or stage_of(peer_id) != Stage.NONE and stage_of(peer_id) != Stage.WINDUP:
		return
	var director := get_parent()
	var player := _player(peer_id)
	if player == null:
		return
	director.call("note_capture", peer_id)
	var now := Net.server_time()
	var at := now if grab_id != 0 else now + float(_k("BEAT_LEAD", 0.15))
	var victim := player.global_position if not land.is_finite() else land
	# Found in a hiding spot: they're set down at the spot's landing, whatever this
	# peer's copy of their lift shows yet (R2b hide; net/components/hide_spot.gd _pull).
	if player.has_meta(&"hide_pulled_to"):
		var pulled: Variant = player.get_meta(&"hide_pulled_to")
		if pulled is Array and (pulled as Array).size() == 2 and now <= float(pulled[1]) + Constants.HIDE_PULLED_TO_TRUST:
			victim = pulled[0]
		player.remove_meta(&"hide_pulled_to")
	var staged_down: Dictionary = _down_staging.get(peer_id, {}) if grab_id != 0 else {}
	_down_staging.erase(peer_id)
	if crew == null:
		_rpc_catch.rpc(grab_id, 0, peer_id, at, victim, Vector3.INF, 0.0, false)
		# Straight to the door: the itemized row where they stood, then the van.
		_host_itemize(peer_id, victim, Vector3.FORWARD)
		_host_at_door(peer_id)
		return
	var toward := victim - (crew as Node3D).global_position
	toward.y = 0.0
	var dir := toward.normalized() if toward.length() > 0.05 else (crew.call("facing") as Vector3)
	var crew_at := victim - dir * Constants.CATCH_GOTCHA_GAP
	crew_at.y = (crew as Node3D).global_position.y
	var down := not staged_down.is_empty()
	if down:
		# The haul-up: you come up where your hips lay, he steps back with the heave,
		# and the two-shot that started from the ground keeps looking from where it did.
		# Where they lie now (a heavy knock can still be sliding them along at his
		# wind-up), and a step back from where he really is.
		var lying := _down_points(player, (crew as Node3D).global_position)
		victim = lying["stand"]
		var off: Vector3 = (crew as Node3D).global_position - victim
		off.y = 0.0
		crew_at = victim + off.normalized() * Constants.CATCH_DOWN_GAP if off.length() > 0.05 else staged_down["crew_at"]
		crew_at.y = (crew as Node3D).global_position.y
	crew.call("host_set_mode", _Crew.Mode.GOTCHA, peer_id, victim)
	crew.call("host_walk", Vector3.INF, 0.0)
	_cite_end[peer_id] = at + Constants.CATCH_CITE_AT + Constants.CATCH_CITE_SECONDS
	_wriggled[peer_id] = 0.0
	# The host picks where the two-shot looks from (open lawn, no wall, no truck),
	# so every peer turns both bodies toward the same camera.
	var mid := (victim + crew_at) * 0.5
	var cam_yaw := float(staged_down["cam_yaw"]) if down else _clear_side(mid + Vector3.UP * Constants.CATCH_CAM_HEIGHT, dir.cross(Vector3.UP).normalized(), Constants.CATCH_CAM_DISTANCE)
	_rpc_catch.rpc(grab_id, int(crew.call("crew_index")), peer_id, at, victim, crew_at, cam_yaw, down)


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
		var freed := _player(peer_id)
		if freed != null and by_peer != peer_id and (cause == &"bonk" or cause == &"punch"):
			# R2c: he reels back a step off the one he had hold of (his stun slides it
			# out), so the two of them part; knocked toward them, from a bonk behind
			# him, he ended up in the freed friend's face.
			var back := (crew as Node3D).global_position - freed.global_position
			back.y = 0.0
			if back.length() > 0.05:
				(crew as CharacterBody3D).velocity = back.normalized() * Constants.RESCUE_KNOCKBACK_SPEED
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
		var down := bool(grab.get("down", false))
		if not spot and not down and not bool(grab["lunged"]) and now >= float(grab["contact"]) - Constants.CREW_LUNGE_SECONDS:
			grab["lunged"] = true
			crew.call("host_set_mode", _Crew.Mode.LUNGE, int(grab["peer"]), grab["dir"])
		if now < float(grab["contact"]):
			continue
		var peer_id := int(grab["peer"])
		var player := _player(peer_id)
		var director := get_parent()
		var can := player != null and bool(director.call("can_capture", peer_id))
		# Flat on the ground there's no stepping out of it: no verdict on a haul-up.
		if can and not spot and not down:
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
	_down_staging.erase(peer_id)
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
		_routes.erase(peer_id)
		_host_at_door(peer_id)
		return
	var late := walked > Constants.CREW_ESCORT_MAX
	var at := (crew as Node3D).global_position
	# R2b: the way round a hedge or a fence to the door, and no standing about
	# against one (a pair stood 6-9 s facing the yard's hedge).
	var route: Dictionary = _routes.get(peer_id, {})
	if route.is_empty():
		route = {"via": _plan_route(crew, door, []), "tried": [], "best": INF, "since": now, "stuck": 0.0}
		_routes[peer_id] = route
	var via: Vector3 = route["via"]
	if via.is_finite() and Vector2(at.x - via.x, at.z - via.z).length() <= Constants.ESCORT_ROUTE_REACHED:
		route["via"] = Vector3.INF
		route["best"] = INF
		via = Vector3.INF
	var goal := via if via.is_finite() else door
	crew.call("host_walk", goal, Constants.CREW_SPEED_ESCORT_LATE if late else Constants.CREW_SPEED_ESCORT)
	var left := Vector2(at.x - goal.x, at.z - goal.z).length()
	if left < float(route["best"]) - Constants.ESCORT_STUCK_METERS:
		route["best"] = left
		route["since"] = now
	elif now - float(route["since"]) > Constants.ESCORT_STUCK_SECONDS:
		route["stuck"] = float(route["stuck"]) + now - float(route["since"])
		route["since"] = now
		route["best"] = INF
		if float(route["stuck"]) >= Constants.ESCORT_STUCK_HANDOFF:
			# Nowhere to go: you're handed to the door from here (the Shuttle walks
			# you in), and he's back on the chase.
			crew.call("host_walk", Vector3.INF, 0.0)
			_routes.erase(peer_id)
			_host_at_door(peer_id)
			return
		var tried: Array = route["tried"]
		if via.is_finite():
			tried.append(via)
		route["via"] = _plan_route(crew, door, tried, true)
	if Vector2(at.x - door.x, at.z - door.z).length() <= Constants.CATCH_DOOR_REACH:
		_routes.erase(peer_id)
		crew.call("host_walk", Vector3.INF, 0.0)
		crew.call("host_set_mode", _Crew.Mode.DOOR, peer_id)
		crew.call("bark", "door", true)
		_host_at_door(peer_id)
		# Back to the chase once you're handed over.
		get_tree().create_timer(Constants.CATCH_DOOR_HANDOFF_SECONDS).timeout.connect(func() -> void:
			if is_instance_valid(crew) and int(crew.get("mode")) == _Crew.Mode.DOOR:
				crew.call("host_set_mode", _Crew.Mode.CHASE, 0))


## Host: a waypoint on the way to the door when the straight way is walled (INF:
## go straight; the crew's navmesh steering does the rest). Rings round the door,
## nearest first: a point on the lawn (on the navmesh, or in plain line from him)
## with a clear line to the door. forced: he's stuck, so a clear straight line
## isn't proof enough; a point off that line is wanted.
func _plan_route(crew: Node, door: Vector3, tried: Array, forced: bool = false) -> Vector3:
	var body := crew as Node3D
	var world := body.get_world_3d()
	if world == null:
		return Vector3.INF
	var exclude := _Sweep.passable(get_tree())
	var lift := Vector3.UP * Constants.ESCORT_ROUTE_LIFT
	var from := body.global_position + lift
	var to_door := door + lift
	var radius := Constants.ESCORT_ROUTE_SWEEP_RADIUS
	var standoff := Constants.ESCORT_ROUTE_DOOR_STANDOFF
	# Stop short of the door itself: the van's side is right there.
	var short := to_door + (from - to_door).normalized() * standoff
	if not forced and _Sweep.clear(world, from, short, radius, exclude):
		return Vector3.INF
	var agent := crew.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	var nav_map := agent.get_navigation_map() if agent != null else RID()
	var best := Vector3.INF
	var best_cost := INF
	var steps := maxi(4, int(round(360.0 / Constants.ESCORT_ROUTE_STEP_DEG)))
	for ring: float in Constants.ESCORT_ROUTE_RADII:
		for index: int in steps:
			var angle := TAU * float(index) / float(steps)
			var point := door + Vector3(sin(angle), 0.0, cos(angle)) * ring
			point.y = body.global_position.y
			var near_tried := false
			for old: Variant in tried:
				if (old as Vector3).distance_to(point) < Constants.ESCORT_ROUTE_RETRY_APART:
					near_tried = true
			if near_tried or Vector2(point.x - body.global_position.x, point.z - body.global_position.z).length() < Constants.ESCORT_ROUTE_MIN_STEP:
				continue
			var cost := body.global_position.distance_to(point) + point.distance_to(door)
			if cost >= best_cost:
				continue
			if _Sweep.inside(world, point + lift, radius, exclude):
				continue
			if not _Sweep.clear(world, point + lift, to_door + (point - door).normalized() * standoff, radius, exclude):
				continue
			var on_mesh := nav_map.is_valid() and NavigationServer3D.map_get_closest_point(nav_map, point).distance_to(point) < Constants.ESCORT_ROUTE_NAV_SNAP
			if not on_mesh and not _Sweep.clear(world, from, point + lift, radius, exclude):
				continue
			best = point
			best_cost = cost
	return best


## Host: at the van door. The Shuttle seats you (chunk 4); without it you wait at
## the door until the director's fallback ride leaves with you.
func _host_at_door(peer_id: int) -> void:
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if shuttle != null and shuttle.has_method("host_board"):
		# R2c: handed over away from the door (a pinned escort, a catch with no NICE
		# BOY free), they're seated behind their iris, not stepped up from out there.
		# Decided once, here, and sent: each peer's own lagged view of the body sits
		# either side of the line at a normal door arrival, and an observer would
		# dissolve a captive the host is stepping up (review r2c:stage, far boarding).
		var player := _player(peer_id)
		var far := player != null and _from_door(player) > Constants.BOARD_NEAR_METERS
		host_set_stage(peer_id, Stage.BOARDING, {"far": far})
		shuttle.call("host_board", peer_id, far)
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
	# Moved with the catch it belongs to on this peer's clock (_rebased).
	end_at += float(_skew.get(peer_id, 0.0))
	_cite_end[peer_id] = end_at
	_log("wriggle", peer_id, end_at)
	var victim_body := _body_of(_player(peer_id))
	if victim_body != null:
		victim_body.call("gesture", "shuffle")
		var pose := _caught_pose(victim_body, false)
		if pose != null:
			pose.call("wriggle")
	var crew := _crew(crew_of(peer_id))
	var poser := crew.get_node_or_null("Visual/CartoonBody/Poser") if crew != null else null
	if poser != null:
		poser.call("hold", "")
		poser.call("hold", "cite_scribble")


# ---------------------------------------------------------------- RPCs (every peer)

@rpc("authority", "call_local", "reliable")
func _rpc_windup(grab_id: int, crew_index: int, peer_id: int, from: Vector3, dir: Vector3, contact_at: float, from_spot: bool, travel: float, haul: Dictionary) -> void:
	var down := not haul.is_empty()
	var lead := Constants.CREW_FOUND_CONTACT if from_spot else (haul_lead(travel) if down else Constants.CREW_LUNGE_WINDUP + Constants.CREW_LUNGE_SECONDS + minf(Net.clock_rtt_seconds() * 0.5, Constants.CREW_LUNGE_WINDUP_LAG_MAX))
	contact_at = _rebased(contact_at, lead)
	var face: Vector3 = haul.get("face", Vector3.ZERO)
	_grabs[grab_id] = {"crew": crew_index, "peer": peer_id, "from": from, "dir": dir, "contact": contact_at, "spot": from_spot, "lunged": false, "travel": travel, "down": down, "face": face}
	if Net.is_host():
		stats["windups"] = int(stats["windups"]) + 1
	_log("windup", peer_id, contact_at)
	var crew := _crew(crew_index)
	var player := _player(peer_id)
	if crew != null:
		crew.call("play_windup", from, dir, contact_at, from_spot, travel, down, face)
		# The haul-up: his grabbing hand goes to this body's collar, wherever it's drawn.
		var poser := crew.get_node_or_null("Visual/CartoonBody/Poser")
		if poser != null:
			poser.set("reach_body", _body_of(player) if down else null)
	var args := {"contact": contact_at}
	if down:
		# The haul-up's two-shot, the catch's own staging (where you'll stand, where
		# he'll be, where it looks from), on the downed player's screen from the start
		# of his reach.
		args = {"contact": contact_at, "victim": haul["stand"], "crew_at": haul["crew_at"], "cam_yaw": float(haul["cam_yaw"]), "down": true}
	_set_stage_local(peer_id, Stage.WINDUP, Net.server_time(), crew_index, args)
	if down and peer_id == Net.local_peer_id() and player != null:
		_played[peer_id] = {}
		# A cut, on his first step: the swing out of your eyes lying on the grass
		# went over your own body at the lens (audit crew-13 review).
		_push_two_shot(player, true)


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
		# A haul-up spoiled (a friend's can on him): back to your own eyes, slowly.
		if bool((_stages[peer_id]["args"] as Dictionary).get("down", false)) and peer_id == Net.local_peer_id():
			_pop(_player(peer_id), &"gotcha", Constants.RESCUE_CAM_BLEND)
		_stages.erase(peer_id)
		stage_changed.emit(peer_id, Stage.NONE)


@rpc("authority", "call_local", "reliable")
func _rpc_catch(grab_id: int, crew_index: int, peer_id: int, at: float, victim: Vector3, crew_at: Vector3, cam_yaw: float, down: bool) -> void:
	_grabs.erase(grab_id)
	if Net.is_host():
		stats["catches"] = int(stats["catches"]) + 1
	# P1 catch (audit lagduo-2): on this peer's clock. A client whose clock estimate
	# had drifted seconds behind held the whole gotcha and cite "in the future": no
	# two-shot at all, the escort replaced it before it began.
	var sent_at := at
	at = _rebased(at, 0.0 if grab_id != 0 else float(_k("BEAT_LEAD", 0.15)))
	_skew[peer_id] = at - sent_at
	if down:
		stats["hauls"] = int(stats["hauls"]) + 1
	_log("catch", peer_id, at)
	var director := get_parent()
	director.call("mark_caught", peer_id, true)
	_cite_end[peer_id] = at + Constants.CATCH_CITE_AT + Constants.CATCH_CITE_SECONDS
	var crew := _crew(crew_index)
	var player := _player(peer_id)
	if crew_at.is_finite():
		var staging := _staging(victim, crew_at, cam_yaw)
		if crew != null:
			# Held through the hit-stop where his lunge ended, then he turns you
			# both toward the camera while it swings round.
			crew.call("play_stand", crew_at, float(staging["crew_yaw"]), Constants.CATCH_CAM_BLEND, Constants.CATCH_HITSTOP)
			_pair_collisions(player, crew, true)
		if player != null and crew != null:
			# Your body is staged here when the hit-stop thaws (_play_gotcha).
			var hold := _hold_node(peer_id)
			hold.global_transform = Transform3D(Basis.looking_at(staging["victim_face"], Vector3.UP), victim)
	_played[peer_id] = {}
	if peer_id == Net.local_peer_id() and player != null:
		_lock(player, &"nice_cite", true)
		# Out of a pile, off a seat: the gotcha is on your feet.
		if bool(player.get("in_pile")) and player.has_method("set_pile"):
			player.call("set_pile", false)
	_set_stage_local(peer_id, Stage.GOTCHA, at, crew_index, {"victim": victim, "crew_at": crew_at, "cam_yaw": cam_yaw, "down": down})
	peer_caught.emit(peer_id)


## P1 catch (audit lagduo-2): a stage time from the host, on this peer's clock.
## Each stage message says when its moment starts on the host's clock, `lead` s
## after the host sent it; it can't land here before it was sent, nor much later
## than one link delay. A client whose clock estimate has drifted (a starved
## window on a fixed step, a hitch) would hold a catch "in the future" for seconds
## or play it as long past (no hit-stop, the two-shot cut in). More than
## STAGE_CLOCK_TRUST off, the moment starts where the message says it should
## start on this clock. The host's own times are its clock.
func _rebased(at: float, lead: float) -> float:
	# Only a message from the host is moved: a late joiner's snapshot replays its
	# stages here directly (sender 0), and those are as old as they say.
	if Net.is_host() or multiplayer.multiplayer_peer == null or multiplayer.get_remote_sender_id() != 1:
		return at
	var expected := Net.server_time() - Net.clock_rtt_seconds() * 0.5 + lead
	if absf(at - expected) <= Constants.STAGE_CLOCK_TRUST:
		return at
	stats["rebased"] = int(stats["rebased"]) + 1
	return expected


## The gotcha's staging, the same on every peer from the catch's args: the line
## from him to you, the way to the camera (cam_yaw, world yaw from between them),
## and each body turned CATCH_CHEAT_TURN from facing the other toward the camera's
## side (a stage cheat: both faces read).
static func _staging(victim: Vector3, crew_at: Vector3, cam_yaw: float) -> Dictionary:
	var line := victim - crew_at
	line.y = 0.0
	line = line.normalized() if line.length() > 0.01 else Vector3.FORWARD
	var to_cam := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw))
	var perp := line.cross(Vector3.UP).normalized()
	if perp.dot(to_cam) < 0.0:
		perp = -perp
	var turn := Constants.CATCH_CHEAT_TURN
	var crew_face := line * cos(turn) + perp * sin(turn)
	var victim_turn := Constants.CATCH_VICTIM_CHEAT_TURN
	var victim_face := -line * cos(victim_turn) + perp * sin(victim_turn)
	return {"line": line, "perp": perp, "to_cam": to_cam, "crew_yaw": atan2(crew_face.x, crew_face.z), "victim_face": victim_face}


@rpc("authority", "call_local", "reliable")
func _rpc_stage(peer_id: int, stage: int, at: float, crew_index: int, args: Dictionary) -> void:
	# On this peer's clock (_rebased): the escort's walk starts CATCH_ESCORT_AFTER
	# after its page is torn, every other stage when it's sent.
	var sent_at := at
	at = _rebased(at, Constants.CATCH_ESCORT_AFTER if stage == Stage.ESCORT else 0.0)
	if not is_equal_approx(at, sent_at) and args.has("tear_at"):
		args = args.duplicate()
		args["tear_at"] = float(args["tear_at"]) + at - sent_at
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
			_drop_caught_pose(player)
			if player != null and peer_id == Net.local_peer_id():
				# Boarding behind the iris: the cut waits for it to shut (_step_boarding).
				if _boarding.is_empty():
					_pop_shots(player)
				_lock(player, &"nice_cite", false)
				_lock(player, &"escort", false)
				_lock(player, &"van_seat", true)
		Stage.BOARDING:
			var crew_was := _crew(crew_of(peer_id))
			if crew_was != null:
				crew_was.call("release_placement")
				_pair_collisions(player, crew_was, false)
			_drop_caught_pose(player)
			# R2c: handed over away from the door (an escort pinned by a hedge, a
			# catch beside the van's flank), the Shuttle's step up would carry the body
			# through the van's side or slide it metres in a blink (audit m1,
			# second-rider-slides-18m). Nobody sees that: the body fades out where it
			# stands and is back once seated, and your own iris shuts at once. The
			# host's call, never this peer's own view of the body (_host_at_door).
			var far := player != null and bool(args.get("far", false))
			if far:
				_fade_body(player, 1.0, Constants.BOARD_FADE_SECONDS)
				get_tree().create_timer(Constants.BOARD_FADE_BACK).timeout.connect(_fade_back.bind(peer_id))
			if player != null and peer_id == Net.local_peer_id():
				_board_behind_iris(player, 0.0 if far else Constants.BOARD_IRIS_DELAY)
				_lock(player, &"nice_cite", false)
				_lock(player, &"escort", false)
		Stage.RIDING, Stage.ANNEX, Stage.RETURNING:
			if player != null and _holds.has(peer_id):
				_unstage_body(player)
			if player != null and peer_id == Net.local_peer_id():
				if _boarding.is_empty():
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


## The local player at the van door (R2b): the escort's follow shot holds while
## he hands you up, the iris closes, and the seat view takes over behind it (a
## blend from out here to the bench passed through his head and the van wall).
## Without an iris, the old way: back to your own camera.
func _board_behind_iris(player: Node3D, delay: float = Constants.BOARD_IRIS_DELAY) -> void:
	var iris := get_tree().get_first_node_in_group("iris")
	if iris == null or not iris.has_method("close") or not player.has_method("stage_top"):
		_pop_shots(player)
		return
	if StringName(player.call("stage_top")) == &"":
		# P1 catch (audit lagduo-2): boarded with nothing staged on this screen (your
		# own eyes: the catch and the escort never got going here). The iris is the
		# host's BOARDING message's, and it always plays: the view holds still where
		# it is and the iris shuts on it at once, then the seat is cut to behind it
		# (it used to blend from your eyes 11 m into the van, no iris).
		_hold_view(player)
		delay = 0.0
	var close_at := Net.server_time() + delay
	iris.call("close", close_at, Constants.IRIS_CLOSE, &"seal")
	_boarding = {"player": player, "close_at": close_at, "cut": false}


## Every frame while boarding: once the iris is shut, cut the shots behind it and
## open on the seat.
func _step_boarding() -> void:
	if _boarding.is_empty():
		return
	var raw: Variant = _boarding.get("player")
	var iris := get_tree().get_first_node_in_group("iris")
	if not is_instance_valid(raw) or iris == null:
		_release_boarding_iris()
		return
	var player := raw as Node3D
	if bool(_boarding["cut"]) or not bool(iris.call("is_closed")):
		return
	_boarding["cut"] = true
	_pop(player, &"gotcha", 0.0)
	_pop(player, &"escort", 0.0)
	_pop(player, &"board_hold", 0.0)
	iris.call("open", Net.server_time() + 0.05, Constants.IRIS_OPEN)
	_boarding.clear()


## The local player's view, held still where it's drawn now (a shot on a marker
## left where the camera is), above anything the van pushes, until the iris shuts.
func _hold_view(player: Node3D) -> void:
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null:
		return
	if _board_hold == null:
		_board_hold = Node3D.new()
		_board_hold.name = "BoardHold"
		_placed_by_hand(_board_hold)
		add_child(_board_hold)
		_board_hold.top_level = true
	_board_hold.global_transform = _StageCam.drawn_pose(camera)
	stats["board_holds"] = int(stats["board_holds"]) + 1
	_push(player, &"board_hold", {"anchor": _board_hold, "offset": Transform3D.IDENTITY, "blend_in": Constants.BOARD_HOLD_BLEND, "blend_out": 0.0,
		"yaw_clamp": Vector2.ZERO, "pitch_clamp": Vector2.ZERO, "fov": camera.fov, "priority": Constants.BOARD_HOLD_PRIORITY, "hide_self": true})


## Freed, unbuckled or reset while boarding: the iris this asked to close is let
## go (a close not yet started never shows; one under way opens again), so it
## never stays shut with nothing left to open it.
func _release_boarding_iris() -> void:
	if _boarding.is_empty():
		return
	_boarding.clear()
	var iris := get_tree().get_first_node_in_group("iris")
	if iris != null and iris.has_method("release"):
		iris.call("release", Net.server_time(), Constants.IRIS_OPEN)


func director_mark(peer_id: int, caught: bool) -> void:
	get_parent().call("mark_caught", peer_id, caught)


@rpc("authority", "call_local", "reliable")
func _rpc_freed(peer_id: int, by_peer: int, cause: String, at: float) -> void:
	at = _rebased(at, 0.0)
	_skew.erase(peer_id)
	_log("freed_" + cause, peer_id, at)
	if Net.is_host():
		stats["frees"] = int(stats["frees"]) + 1
	var crew := _crew(crew_of(peer_id))
	var player := _player(peer_id)
	# R2c: a rescue is a payoff, not a state change (audit c4-bonk-no-reaction:
	# nobody moved). He reels back a step with his arms flung up, the clipboard
	# flying and stars round his visor; you shake loose, a stumble out of his
	# reach, and turn to whoever got you out.
	var rescued := cause == "bonk" or cause == "punch"
	var crew_at := (crew as Node3D).global_position if crew != null else Vector3.INF
	if crew != null and cause != "gone":
		# The clipboard goes flying and the forms flutter down.
		var body := _body_of(crew)
		var poser := crew.get_node_or_null("Visual/CartoonBody/Poser")
		if poser != null and rescued:
			poser.call("shot", "bonked")
		elif body != null:
			body.call("gesture", "flail")
		if body != null and rescued:
			body.call("dizzy", Constants.RESCUE_DIZZY_SECONDS)
		_flutter_forms(crew_at + Vector3.UP * 1.4)
		var sfx := get_tree().get_first_node_in_group("sfx")
		if sfx != null and _plays_sound(at):
			sfx.call("play_on", "paper_tear", crew, -4.0)
	if player != null and cause != "gone":
		var body := _body_of(player)
		if body != null:
			body.call("gesture", "stumble")
		if rescued and peer_id == Net.local_peer_id():
			# Back to your own eyes slowly, while you stumble clear (no whip).
			_pop(player, &"gotcha", Constants.RESCUE_CAM_BLEND)
			_pop(player, &"escort", Constants.RESCUE_CAM_BLEND)
	_peel_sticker(peer_id)
	_clear_peer(peer_id)
	if rescued and player != null and crew_at.is_finite():
		_shake_loose(peer_id, player, crew_at, _player(by_peer))
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
	_step_boarding()
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
		# The contact sound plays while the grab is still on screen here, not only
		# within BEAT_SKIP (R2c hide: a lagged observer never heard it).
		if (_plays_sound(at) or t <= Constants.CATCH_HOLD_END) and sfx != null and player != null:
			# Yours lands flat and loud on the contact frame; everyone else hears it
			# where it happened.
			if peer_id == Net.local_peer_id():
				sfx.call("play", "gotcha_grab", Constants.CATCH_GRAB_DB)
			else:
				sfx.call("play_on", "gotcha_grab", player, 0.0, false)
		if victim_body != null:
			victim_body.call("gesture", "startle")
			var pose := _caught_pose(victim_body, true)
			if pose != null:
				pose.call("flinch")
				# R2c: the caught body acts: eyes on him, a glance at the camera.
				pose.set("captor", crew)
				pose.set("camera_point", _two_shot_eye(entry["args"]))
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
		# The hit-stop held you where the hand landed; now he turns you to face him
		# (and the camera), over the camera's swing.
		var hauled := bool((entry["args"] as Dictionary).get("down", false))
		var hold := _holds.get(peer_id) as Node3D
		if hauled:
			# Up the way they lay, and only then turned to him: turning while still
			# half down swept their legs and head through him (crew-13 review).
			var visual := player.get_node_or_null("Visual") as Node3D if player != null else null
			if visual != null and hold != null and is_instance_valid(hold):
				var lay := visual.global_basis.z
				var face := hold.global_basis.z
				played["haul_yaw"] = Vector2(atan2(lay.x, lay.z), atan2(face.x, face.z))
				played["haul_from"] = now
				_turn_haul_hold(peer_id, now)
		if player != null and hold != null and is_instance_valid(hold) and not bool(player.call("is_staged") if player.has_method("is_staged") else false):
			# A haul-up's rise is its own length: the body is carried in from its feet
			# to where its hips lay while it sits up and stands (CartoonBody.haul_up).
			_stage_body(player, hold, Transform3D.IDENTITY, Constants.CATCH_DOWN_RISE if hauled else Constants.CATCH_CAM_BLEND, &"stand")
		if peer_id == Net.local_peer_id() and player != null:
			# The haul-up's shot is already up (from his first step): it just rises.
			_push_two_shot(player, t > 0.5 or hauled)
		if hauled:
			# The haul-up: he heaves you up off the grass by the collar, his hand on it
			# the whole way, and you sit up and come up onto your feet under your hips
			# (every peer, on this timeline; the owner's knock ends here too).
			var hauler := crew.get_node_or_null("Visual/CartoonBody/Poser") if crew != null else null
			if hauler != null:
				hauler.call("shot", "haul_up", true)
			if victim_body != null and victim_body.has_method("haul_up"):
				victim_body.call("haul_up", Constants.CATCH_DOWN_RISE)
			if peer_id == Net.local_peer_id() and player != null and player.has_method("end_knockdown"):
				player.call("end_knockdown")
				player.call("say_to_all", "vo_oof")
	if played.has("haul_yaw"):
		_turn_haul_hold(peer_id, now)
	if not played.has("grin") and t >= Constants.CATCH_GRIN_AT:
		played["grin"] = true
		var poser := crew.get_node_or_null("Visual/CartoonBody/Poser") if crew != null else null
		if poser != null and int(crew.get("mode")) != _Crew.Mode.CITE:
			poser.call("hold", "grin_hold")
	if not played.has("bark") and t >= Constants.CATCH_BARK_AT:
		played["bark"] = true
		if crew != null and t < Constants.CATCH_BARK_AT + float(_k("BEAT_SKIP", 0.5)):
			crew.call("show_bark", "caught", 0)
			# The megaphone in your face: you recoil from it.
			var pose := _caught_pose(victim_body, false)
			if pose != null:
				pose.call("react")
	if t >= Constants.CATCH_CITE_AT:
		if int(entry["stage"]) == Stage.GOTCHA:
			entry["stage"] = Stage.CITE
			stage_changed.emit(peer_id, Stage.CITE)
		if now >= _scribble_next and crew != null and sfx != null and now < cite_end(peer_id):
			_scribble_next = now + _SCRIBBLE_LOOP
			sfx.call("play_on", "scribble", crew)


## Every peer, through a haul-up's rise: the hold (where the hauled body is staged)
## keeps the way they lay until they're mostly up, then turns them to face him.
func _turn_haul_hold(peer_id: int, now: float) -> void:
	var played: Dictionary = _played.get(peer_id, {})
	var hold := _holds.get(peer_id) as Node3D
	if hold == null or not is_instance_valid(hold) or not played.has("haul_yaw"):
		return
	var yaws: Vector2 = played["haul_yaw"]
	var u := (now - float(played.get("haul_from", now))) / maxf(Constants.CATCH_DOWN_RISE, 0.05)
	var turn := smoothstep(Constants.CATCH_DOWN_TURN_FROM, 1.0, u)
	hold.global_basis = Basis(Vector3.UP, lerp_angle(yaws.x, yaws.y, turn))
	if u >= 1.0:
		played.erase("haul_yaw")


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
		# Slapped on: you flinch and look down at it.
		var stuck := _caught_pose(_body_of(player), false)
		if stuck != null:
			stuck.call("flinch", true)
		if sfx != null and player != null and _plays_sound(tear_at + Constants.CATCH_SLAP_AFTER):
			# On your own chest: flat and close, like the grab (R2b).
			if peer_id == Net.local_peer_id():
				sfx.call("play", "sticker_slap", 0.0)
			else:
				sfx.call("play_on", "sticker_slap", player)
	var anchor := crew.call("escort_anchor") as Node3D if crew != null else null
	if not played.has("link") and now >= float(entry["at"]) and player != null and anchor != null:
		played["link"] = true
		# He walks on his own feet now (the host's body, smoothed like any walk).
		crew.call("release_placement")
		# Round to his side, never through him (R2c).
		_stage_body(player, anchor, Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), Constants.ESCORT_LINK_BLEND, &"escorted", crew)
		var pose := _caught_pose(_body_of(player), true)
		if pose != null:
			pose.call("set_mode", &"escorted")
		if peer_id == Net.local_peer_id():
			_lock(player, &"nice_cite", false)
			_lock(player, &"escort", true)
			_start_follow(anchor)
			# From the two-shot, round the pair (the pivot) to behind them, never a
			# cut (R2b): the follow anchor starts facing the way the two-shot looks.
			_push(player, &"escort", {
				"anchor": _follow,
				"offset": Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -0.38), Vector3(0.3, Constants.ESCORT_CAM_UP - _FOLLOW_HEIGHT, -Constants.ESCORT_CAM_BACK)),
				"blend_in": Constants.ESCORT_CAM_BLEND_IN, "blend_out": 0.5, "orbit": true, "spring": false,
				"yaw_clamp": Vector2(-deg_to_rad(Constants.ESCORT_CAM_ORBIT_DEG), deg_to_rad(Constants.ESCORT_CAM_ORBIT_DEG)),
				"pitch_clamp": Vector2(-0.5, 0.3), "lag": 0.12, "priority": 40,
				"pivot": _follow, "collide": true,
				# R2c: nobody else stands between you and the walk (a passer-by filled it).
				"subjects": [player, crew], "frame_out_partner": _pair_partner,
			})
			_pop(player, &"gotcha", Constants.ESCORT_CAM_BLEND_IN)


# ---------------------------------------------------------------- the two-shot

## The caught player's camera: low and side-on, 3 m off, both faces in frame,
## pushing in a little through the hold (chunk 1's StageCam, priority 50).
func _push_two_shot(player: Node3D, late: bool) -> void:
	if _shot == null:
		_shot = Node3D.new()
		_shot.name = "TwoShot"
		_placed_by_hand(_shot)
		add_child(_shot)
		_shot.top_level = true
	_aim_two_shot(Net.server_time())
	# Looking away from the pair (more than CATCH_CAM_CUT_TURN off the shot), the
	# swing round whipped across empty lawn for a second before either of you was in
	# it (audit lagduo-2 review, the second catch): a cut on the hit-stop instead.
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if not late and camera != null:
		var was := -_StageCam.drawn_pose(camera).basis.z
		var to := -_shot.global_basis.z
		was.y = 0.0
		to.y = 0.0
		if was.length() > 0.01 and to.length() > 0.01 and was.normalized().dot(to.normalized()) < cos(deg_to_rad(Constants.CATCH_CAM_CUT_TURN)):
			late = true
	# Out of first person from exactly where you looked, back and round the pair
	# (the pivot) to the side, kept clear of walls and trucks (R2b).
	_push(player, &"gotcha", {"anchor": _shot, "offset": Transform3D.IDENTITY, "blend_in": 0.0 if late else Constants.CATCH_CAM_BLEND, "blend_out": 0.6, "fov": Constants.CATCH_CAM_FOV, "yaw_clamp": Vector2(-0.7, 0.7), "pitch_clamp": Vector2(-0.35, 0.35), "priority": 50,
		"pivot": _two_shot_mid(), "collide": true,
		# R2c: about the two of you: anyone else in frame fades out, and so does the
		# tool in your hands.
		"subjects": _two_shot_subjects(), "frame_out_held": true, "frame_out_partner": _pair_partner})


## Frame-out (StageCam "frame_out_partner"): the other half of another caught pair
## (a NICE BOY's captive, a captive's NICE BOY), or null. The pair fades together
## or not at all: a captive led by nobody (rec_h_two_fr 276-316) looked worse
## than a pair walking past.
func _pair_partner(node: Node) -> Node3D:
	var me := Net.local_peer_id()
	for peer_id: int in _stages:
		if peer_id == me or crew_of(peer_id) == 0:
			continue
		var crew := _crew(crew_of(peer_id))
		if crew == null:
			continue
		if crew == node:
			return _player(peer_id)
		if str(node.name) == str(peer_id):
			return crew
	return null


## Who the local player's two-shot is about: you and the NICE BOY holding you.
func _two_shot_subjects() -> Array:
	var me := Net.local_peer_id()
	var out: Array = []
	var player := _player(me)
	var crew := _crew(crew_of(me))
	if player != null:
		out.append(player)
	if crew != null:
		out.append(crew)
	return out


## Where the two-shot films from for this catch, the same on every peer (the
## caught player glances at it now and then).
static func _two_shot_eye(args: Dictionary) -> Vector3:
	var victim: Vector3 = args.get("victim", Vector3.ZERO)
	var crew_at: Vector3 = args.get("crew_at", Vector3.INF)
	if not crew_at.is_finite():
		return Vector3.INF
	var staging := _staging(victim, crew_at, float(args.get("cam_yaw", 0.0)))
	var mid := (victim + crew_at) * 0.5 + Vector3.UP * Constants.CATCH_CAM_HEIGHT
	return mid + (staging["to_cam"] as Vector3) * Constants.CATCH_CAM_DISTANCE - Vector3.UP * Constants.CATCH_CAM_EYE_DROP


## Between the two of them at the look height, for the local caught player.
func _two_shot_mid() -> Vector3:
	var me := Net.local_peer_id()
	var args: Dictionary = (_stages.get(me, {}) as Dictionary).get("args", {})
	var victim: Vector3 = args.get("victim", Vector3.ZERO)
	var crew_at: Vector3 = args.get("crew_at", victim + Vector3.FORWARD)
	if not crew_at.is_finite():
		crew_at = victim + Vector3.FORWARD
	return (victim + crew_at) * 0.5 + Vector3.UP * Constants.CATCH_CAM_HEIGHT


func _aim_two_shot(now: float) -> void:
	var me := Net.local_peer_id()
	if _shot == null or (stage_of(me) != Stage.GOTCHA and stage_of(me) != Stage.CITE and not _hauling(me)):
		return
	var entry: Dictionary = _stages[me]
	var args: Dictionary = entry["args"]
	var victim: Vector3 = args.get("victim", Vector3.ZERO)
	var crew_at: Vector3 = args.get("crew_at", victim + Vector3.FORWARD)
	if not crew_at.is_finite():
		crew_at = victim + Vector3.FORWARD
	var staging := _staging(victim, crew_at, float(args.get("cam_yaw", 0.0)))
	var mid := _two_shot_mid()
	var push := clampf((now - float(entry["at"]) - Constants.CATCH_GRIN_AT) / (Constants.CATCH_HOLD_END - Constants.CATCH_GRIN_AT + Constants.CATCH_CITE_SECONDS), 0.0, 1.0)
	var distance := Constants.CATCH_CAM_DISTANCE * (1.0 - Constants.CATCH_PUSH_IN * 3.0 * push)
	var eye := mid + (staging["to_cam"] as Vector3) * distance - Vector3.UP * Constants.CATCH_CAM_EYE_DROP
	# The haul-up starts from the ground (audit crew-13): low over you lying there
	# (your hips are where you'll stand) and him bent over you, rising with you as
	# he heaves you up.
	var low := _haul_low(me, now)
	if low > 0.0:
		mid -= Vector3.UP * Constants.CATCH_DOWN_LOOK_DROP * low
		# ...and a little further off, so your own head on the grass doesn't fill it.
		eye += (staging["to_cam"] as Vector3) * Constants.CATCH_CAM_DISTANCE * Constants.CATCH_DOWN_PULL_BACK * low
		eye -= Vector3.UP * Constants.CATCH_DOWN_EYE_DROP * low
	_shot.global_transform = Transform3D(Basis.looking_at(mid - eye, Vector3.UP), eye)


## How low the haul-up's two-shot is now (1 on the ground, 0 standing).
func _haul_low(peer_id: int, now: float) -> float:
	if _hauling(peer_id):
		return 1.0
	var entry: Dictionary = _stages.get(peer_id, {})
	if not bool((entry.get("args", {}) as Dictionary).get("down", false)):
		return 0.0
	# With the body's rise (CartoonBody.haul_up), from the thaw.
	var thaw := float((_played.get(peer_id, {}) as Dictionary).get("thaw_at", float(entry.get("at", now)) + Constants.CATCH_HITSTOP))
	return 1.0 - smoothstep(thaw, thaw + Constants.CATCH_DOWN_RISE, now)


## A haul-up's reach on this peer: wound up on while knocked flat (the two-shot is
## already up).
func _hauling(peer_id: int) -> bool:
	return stage_of(peer_id) == Stage.WINDUP and bool(((_stages[peer_id] as Dictionary).get("args", {}) as Dictionary).get("down", false))


## Host: where the two-shot looks from, as a world yaw from between them. Side on
## first, the yard side before the street side (the curb is lined with trees and
## trucks, the yard is open lawn), then swung up to 50 degrees toward either of
## them, until a sphere swept from between them out past the eye touches nothing:
## no wall, no hedge, no Chefty, no van (player/stage_sweep.gd). With nowhere
## clear, the one with the most room.
func _clear_side(mid: Vector3, side: Vector3, distance: float) -> float:
	var world := get_viewport().world_3d if get_viewport() != null else null
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var first := 1.0
	if lot != null:
		var toward := lot.global_position - mid
		toward.y = 0.0
		first = 1.0 if side.dot(toward) >= 0.0 else -1.0
	var tries: Array[Vector3] = []
	for swing: float in [0.0, 0.45, -0.45, 0.85, -0.85]:
		for sign: float in [first, -first]:
			tries.append((side * sign).rotated(Vector3.UP, swing))
	var best := tries[0]
	if world != null:
		var exclude := _Sweep.passable(get_tree())
		var best_reach := -1.0
		for to_cam: Vector3 in tries:
			var eye := mid + to_cam * (distance + 0.4) - Vector3.UP * Constants.CATCH_CAM_EYE_DROP
			var reach := _Sweep.reach(world, mid, eye, Constants.STAGE_CAM_RADIUS + 0.1, exclude)
			if reach >= 0.999:
				best = to_cam
				break
			if reach > best_reach + 0.05:
				best_reach = reach
				best = to_cam
	return atan2(best.x, best.z)


## The escort's follow shot hangs off this: on the pair, but turning slowly toward
## where they walk (he turns round in a step; the camera shouldn't whip round with him).
func _start_follow(anchor: Node3D) -> void:
	if _follow == null:
		_follow = Node3D.new()
		_follow.name = "EscortFollow"
		_placed_by_hand(_follow)
		add_child(_follow)
		_follow.top_level = true
	_follow_target = anchor
	var camera := get_viewport().get_camera_3d()
	var look := -camera.global_basis.z if camera != null else -anchor.global_basis.z
	look.y = 0.0
	_follow_yaw = atan2(look.x, look.z) if look.length() > 0.01 else anchor.global_rotation.y
	_follow_turn = 0.0
	_follow_bias = 0.0
	_follow.global_transform = Transform3D(Basis(Vector3.UP, _follow_yaw), _anchor_point(anchor) + Vector3.UP * _FOLLOW_HEIGHT)


## Where the escort anchor is drawn now. Its interpolated transform can lag a
## teleport by a tick or more (R2b: the anchor had been still all through the
## cite, and the first escort frames read a pose from before the scenario or the
## hop put him there: a 13-16 m whip); past a step away, the real one wins.
func _anchor_point(anchor: Node3D) -> Vector3:
	var drawn := anchor.get_global_transform_interpolated().origin
	var real := anchor.global_position
	return drawn if drawn.distance_to(real) < Constants.ESCORT_ANCHOR_TRUST_M else real


func _move_follow(delta: float) -> void:
	if _follow == null or not is_instance_valid(_follow_target) or not _follow_target.is_inside_tree():
		return
	var forward := _follow_target.global_basis.z
	forward.y = 0.0
	if forward.length() > 0.01:
		var want := atan2(forward.x, forward.z)
		var step := wrapf(want - _follow_yaw, -PI, PI)
		# Ease into the turn and out of it (he turns round in a step; the camera
		# takes its time and never starts a swing at full speed).
		var wanted_rate := clampf(step * Constants.ESCORT_CAM_TURN_EASE, -Constants.ESCORT_CAM_TURN, Constants.ESCORT_CAM_TURN)
		_follow_turn = move_toward(_follow_turn, wanted_rate, Constants.ESCORT_CAM_TURN * 2.0 * delta)
		_follow_yaw += _follow_turn * delta
	var at := _anchor_point(_follow_target) + Vector3.UP * _FOLLOW_HEIGHT
	# R2c: the follow eye swings round to a side it can see the pair from, never
	# pulled in against the van's flank or a hedge (audit stagecam-hugs-van-bumper,
	# van-wheel-near-camera: the sweep pulled it in until the van's side and wheel
	# filled half the frame). Eased like the turn: no whip.
	var me_stage := stage_of(Net.local_peer_id())
	var want_bias := _clear_follow_bias(at) if me_stage == Stage.ESCORT or me_stage == Stage.BOARDING else _follow_bias
	_follow_bias = move_toward(_follow_bias, want_bias, Constants.ESCORT_CAM_BIAS_RATE * delta)
	_follow.global_transform = Transform3D(Basis(Vector3.UP, _follow_yaw + _follow_bias), at)


## The yaw offset (rad, from ESCORT_CAM_BIASES, the nearest to the one in use
## first) at which the escort's eye has a clear line to the pair; with none clear,
## the one with the most room.
func _clear_follow_bias(at: Vector3) -> float:
	var world := _follow.get_world_3d()
	if world == null:
		return 0.0
	var exclude := _Sweep.passable(get_tree())
	var eye_local := Vector3(0.3, Constants.ESCORT_CAM_UP - _FOLLOW_HEIGHT, -Constants.ESCORT_CAM_BACK)
	var tries: Array = Constants.ESCORT_CAM_BIASES.duplicate()
	tries.sort_custom(func(a: float, b: float) -> bool: return absf(a - _follow_bias) < absf(b - _follow_bias))
	var best := _follow_bias
	var best_reach := -1.0
	for bias: float in tries:
		var eye := at + Basis(Vector3.UP, _follow_yaw + bias) * eye_local
		var reach := _Sweep.reach(world, at, eye, Constants.STAGE_CAM_RADIUS + 0.15, exclude)
		# Room round the eye too: a clear line that runs along the van's flank still
		# fills half the frame with its side and wheel.
		if reach >= 0.999 and _Sweep.inside(world, eye, Constants.ESCORT_CAM_ROOM, exclude):
			reach = 0.95
		if reach >= 0.999:
			return bias
		if reach > best_reach + 0.05:
			best_reach = reach
			best = bias
	return best


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
	if peer_id == Net.local_peer_id():
		# R2c: your own, like your own body, is on the layer your first-person and
		# seat views skip: the daisy filled the bottom of the view in the van seat
		# and at the Annex step-down. Everyone else (and your two-shot) sees it.
		for node: Node in sticker.find_children("*", "GeometryInstance3D", true, false):
			(node as GeometryInstance3D).layers = 1 << (_CartoonBody.HEAD_LAYER - 1)
		if sticker is GeometryInstance3D:
			(sticker as GeometryInstance3D).layers = 1 << (_CartoonBody.HEAD_LAYER - 1)
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
func _stage_body(player: Node3D, anchor: Node3D, offset: Transform3D, blend: float, pose: StringName, clear_of: Node3D = null) -> void:
	if player != null and player.has_method("set_staged"):
		player.call("set_staged", anchor, offset, blend, pose, clear_of)


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
	_pop(player, &"board_hold", 0.5)


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
		_drop_caught_pose(player)
		if peer_id == Net.local_peer_id():
			_release_boarding_iris()
			_pop_shots(player)
			for reason: StringName in [&"nice_cite", &"escort", &"van_seat"]:
				_lock(player, reason, false)
	var hold := _holds.get(peer_id) as Node3D
	if hold != null and is_instance_valid(hold):
		hold.queue_free()
	_holds.erase(peer_id)
	_played.erase(peer_id)
	_cite_end.erase(peer_id)
	_routes.erase(peer_id)
	_skew.erase(peer_id)
	if not _stickers.has(peer_id):
		return
	_peel_sticker(peer_id)


## How far this player's drawn body is from the van's door step (flat, m).
func _from_door(player: Node3D) -> float:
	var visual := player.get_node_or_null("Visual") as Node3D
	var at := player.global_position if player.is_multiplayer_authority() or visual == null else visual.global_position
	var door := _door_point()
	return Vector2(at.x - door.x, at.z - door.z).length()


## Every peer: a player's whole drawn body (and what's on it) to this see-through
## amount (1 = gone) over seconds.
func _fade_body(player: Node3D, amount: float, seconds: float) -> void:
	var visual := player.get_node_or_null("Visual") as Node3D
	if visual == null:
		return
	var from := float(player.get_meta(&"board_fade", 0.0))
	var tween := player.create_tween()
	tween.tween_method(func(value: float) -> void:
		if not is_instance_valid(visual):
			return
		player.set_meta(&"board_fade", value)
		for node: Node in visual.find_children("*", "GeometryInstance3D", true, false):
			_StageCam.fade_geometry(node as GeometryInstance3D, value), from, amount, maxf(seconds, 0.01))


## Seated now: the boarded body fades back in.
func _fade_back(peer_id: int) -> void:
	var player := _player(peer_id)
	if player != null and float(player.get_meta(&"board_fade", 0.0)) > 0.0:
		_fade_body(player, 0.0, Constants.BOARD_FADE_SECONDS)


## Every peer, freed by a friend: a stumble out of his reach (RESCUE_STEP_METERS
## straight away from him, less if a wall is closer), turning to face whoever
## got you out (else away from him), then your own feet again. The freed
## player's view eases back to first person over it, so it ends on the friend
## and the reeling NICE BOY, not nose to nose with him (audit c5, m3).
func _shake_loose(peer_id: int, player: Node3D, crew_at: Vector3, rescuer: Node3D) -> void:
	var visual := player.get_node_or_null("Visual") as Node3D
	var from := player.global_position if player.is_multiplayer_authority() or visual == null else visual.global_position
	var away := from - crew_at
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else -player.global_basis.z
	var meters := Constants.RESCUE_STEP_METERS
	var world := player.get_world_3d()
	if world != null:
		var lift := Vector3.UP * 0.9
		meters *= _Sweep.reach(world, from + lift, from + lift + away * meters, 0.3, _Sweep.passable(get_tree()))
	var to := from + away * meters
	var face := away
	if rescuer != null and rescuer != player:
		var toward := rescuer.global_position - to
		toward.y = 0.0
		if toward.length() > 0.3:
			face = toward.normalized()
	var hold := _hold_node(peer_id)
	hold.global_transform = Transform3D(Basis.looking_at(face, Vector3.UP), to)
	_stage_body(player, hold, Transform3D.IDENTITY, Constants.RESCUE_STEP_SECONDS, &"stand")
	get_tree().create_timer(Constants.RESCUE_STEP_SECONDS).timeout.connect(_end_shake_loose.bind(peer_id, hold.get_instance_id()))


func _end_shake_loose(peer_id: int, hold_id: int) -> void:
	var hold := instance_from_id(hold_id) as Node3D
	var player := _player(peer_id)
	if player != null and hold != null and player.has_method("is_staged") and bool(player.call("is_staged")):
		var stage_body := player.get_node_or_null("StageBody")
		if stage_body != null and stage_body.call("staged_anchor") == hold:
			_unstage_body(player)
	if hold != null and _holds.get(peer_id) == hold and stage_of(peer_id) == Stage.NONE:
		_holds.erase(peer_id)
		hold.queue_free()


## The stage's own markers (the two-shot's eye, the escort's follow anchor, each
## hold) are placed by hand every frame or on an RPC, never stepped by physics:
## physics interpolation stays off on them, so a read of where one is drawn is
## where it is now, not where the last frame left it (R2c stage: the follow
## anchor, left at Annex B with the head NICE BOY after a ride, was read there on
## the next escort's first frame).
static func _placed_by_hand(node: Node3D) -> void:
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _hold_node(peer_id: int) -> Node3D:
	var hold := _holds.get(peer_id) as Node3D
	if hold == null or not is_instance_valid(hold):
		hold = Node3D.new()
		hold.name = "Hold%d" % peer_id
		_placed_by_hand(hold)
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
			lunger.call("play_windup", grab["from"], grab["dir"], float(grab["contact"]), bool(grab["spot"]), float(grab.get("travel", Constants.CREW_LUNGE_DISTANCE - Constants.CREW_LUNGE_ARM)), bool(grab.get("down", false)), grab.get("face", Vector3.ZERO))
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
	if not crew_at.is_finite():
		return
	var staging := _staging(victim, crew_at, float(args.get("cam_yaw", 0.0)))
	if crew != null:
		crew.call("play_stand", crew_at, float(staging["crew_yaw"]), 0.0)
	if player != null:
		var hold := _hold_node(peer_id)
		hold.global_transform = Transform3D(Basis.looking_at(staging["victim_face"], Vector3.UP), victim)
		_stage_body(player, hold, Transform3D.IDENTITY, 0.0, &"stand")
		_caught_pose(_body_of(player), true)


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


## The caught player's CaughtPose (player/caught_pose.gd) under their
## CartoonBody, made when make is true.
func _caught_pose(body: Node, make: bool) -> Node:
	if body == null:
		return null
	var pose := body.get_node_or_null("CaughtPose")
	if pose == null and make:
		pose = _CaughtPose.new()
		pose.name = "CaughtPose"
		body.add_child(pose)
	return pose


## Let the caught pose go (it eases out and frees itself).
func _drop_caught_pose(player: Node) -> void:
	var pose := _caught_pose(_body_of(player), false)
	if pose != null:
		pose.name = "CaughtPoseOut"
		pose.call("release")
