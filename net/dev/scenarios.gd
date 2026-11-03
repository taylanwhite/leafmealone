extends Node

## Authority: host, dev builds only. Scenario jumps (docs/PLAYTEST.md): put the
## host's player at a moment worth judging in a second or two, through the same
## code the game runs (the run director's phases and captures, the van, Annex
## B, hiding spots, the leaf field's rake strokes, Chefty's seats), so what
## gets recorded is what players get. Only the starting position is arranged.
## remote_play.gd's ["scenario", name] step and the --scenario=<name> flag call
## run(); the playtest tools test (net/dev/playtest_tools_test.gd) checks each
## one reaches its state.
##
## Names: rake_fresh, rake_pile, raid_warn, raid_arrive, caught, hide,
## van_ride, annex, annex_break, annex_heist, annex_bigstamp, annex_window_d,
## annex_visit (needs a second player), annex_closing, store, drive (that one
## needs --town-map). border_return is the old name of annex (kept for one wave).

const _Strings = preload("res://ui/strings.gd")
const _Vehicles = preload("res://props/vehicles.gd")
const _Sched = preload("res://net/annex/annex_schedule.gd")
## annex*: the raid seed and trip the visit starts with, so the room is the same every take.
const ANNEX_SEED: int = 271828
const ANNEX_TRIP: int = 1
const NAMES: Array[String] = ["rake_fresh", "rake_pile", "raid_warn", "raid_arrive", "caught", "hide", "border_return", "van_ride", "annex", "annex_break", "annex_heist", "annex_bigstamp", "annex_window_d", "annex_visit", "annex_closing", "store", "drive"]
## raid_arrive: how long before the NICE BOYS show up.
const ARRIVE_LEAD_SECONDS: float = 2.0
## hide: how long the warning still has to run, time enough to get in.
const HIDE_LEAD_SECONDS: float = 3.5
## caught: how far in front of the head NICE BOY you stand.
const CAUGHT_GAP_METERS: float = 5.0
## raid_arrive: where you watch the arrival from, meters from the arrival point.
const WATCH_ARRIVAL_METERS: float = 11.0
## rake_fresh, rake_pile: an untouched strip of leaves this long, and the rake
## strokes that push it into a pile.
const STRIP_STEPS: int = 14
const STRIP_STEP_METERS: float = 0.5
const STRIP_MIN_DENSITY: int = 36
## rake_pile: stand this far short of the pile's middle, so the next stroke hits it.
const PILE_STAND_METERS: float = 2.4
## Looking a little down at the ground, in radians.
const RAKE_PITCH: float = -0.42
## Waits for a state, in seconds, before a scenario gives up.
const SETTLE_SECONDS: float = 15.0

## The --scenario=<name> one at launch has run (or there was none).
var start_done: bool = false
## Its result, for remote play's first report.
var start_result: Dictionary = {}
## The window the last annex_break / annex_heist set up, for its _reached_ check.
var _annex_window: String = ""


func _ready() -> void:
	var wanted := str(Net.dev_options().get("scenario"))
	if wanted == "":
		start_done = true
		return
	_run_at_start(wanted)


func _run_at_start(wanted: String) -> void:
	var waited := 0.0
	while (Net.current_state() != Net.State.IN_SESSION or _me() == null or _world() == null) and waited < 40.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	# Let the yard, its props and the first replication settle.
	await get_tree().create_timer(1.0).timeout
	start_result = await run(wanted)
	print("[Scenario] %s at start: %s" % [wanted, start_result])
	start_done = true


## Jump to a moment. Returns {ok, scenario, note, ...} or {ok: false, error}.
func run(scenario: String) -> Dictionary:
	if scenario == "list":
		return {"ok": true, "scenarios": NAMES}
	if not OS.is_debug_build():
		return {"ok": false, "error": "scenarios are for dev builds only"}
	if not Net.is_host():
		return {"ok": false, "error": "scenarios run on the host (this is a client)"}
	if _me() == null or _world() == null:
		return {"ok": false, "error": "no world or player yet"}
	if not NAMES.has(scenario):
		return {"ok": false, "error": "unknown scenario %s (try %s)" % [scenario, ", ".join(NAMES)]}
	await reset()
	var out: Dictionary = {}
	match scenario:
		"rake_fresh":
			out = await _rake_fresh()
		"rake_pile":
			out = await _rake_pile()
		"raid_warn":
			out = await _raid_warn()
		"raid_arrive":
			out = await _raid_arrive()
		"caught":
			out = await _caught()
		"hide":
			out = await _hide()
		"border_return", "annex":
			out = await _annex()
		"annex_break":
			out = await _annex_break()
		"annex_heist":
			out = await _annex_heist()
		"annex_bigstamp":
			out = await _annex_bigstamp()
		"annex_window_d":
			out = await _annex_window_d()
		"annex_visit":
			out = await _annex_visit()
		"annex_closing":
			out = await _annex_closing()
		"van_ride":
			out = await _van_ride()
		"store":
			out = await _store()
		"drive":
			out = await _drive()
	out["scenario"] = scenario
	if not out.has("ok"):
		out["ok"] = not out.has("error")
	print("[Scenario] %s: %s" % [scenario, out])
	return out


# ---------------------------------------------------------------- the moments


## A job yard, untouched leaves in front of you, the rake in your hands.
func _rake_fresh() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var strip := _fresh_strip()
	if strip == Vector3.INF:
		return {"error": "no untouched strip of leaves on this yard"}
	_place(strip - Vector3(1.5, 0.0, 0.0), -PI * 0.5, RAKE_PITCH)
	await _ticks(3)
	var held: String = await _hold("rake")
	_place(strip - Vector3(1.5, 0.0, 0.0), -PI * 0.5, RAKE_PITCH)
	if held != "rake":
		return {"error": "couldn't get the rake (holding '%s')" % held}
	return {"note": "facing +x along a strip of untouched leaves; hold primary to rake", "facing": "+x", "strip": _v(strip)}


## A yard half done: a pile raked up just in front of you, the rake in hand.
func _rake_pile() -> Dictionary:
	var fresh: Dictionary = await _rake_fresh()
	if fresh.has("error"):
		return fresh
	var field := _field()
	var strip := Vector3(fresh["strip"][0], 0.1, fresh["strip"][2])
	# The strokes a person would make walking down the strip (gag_test's pile, real strokes).
	for index: int in STRIP_STEPS:
		var at := strip + Vector3(float(index) * STRIP_STEP_METERS, 0.0, 0.0)
		_place(at - Vector3(1.5, 0.0, 0.0), -PI * 0.5, RAKE_PITCH)
		field.call("request_rake", at, Vector3(1.0, 0.0, 0.0), Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH)
		await _ticks(1)
	await _ticks(3)
	var pile := Vector3.INF
	var most := 0
	for ahead: float in [5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5]:
		var at := strip + Vector3(ahead, 0.0, 0.0)
		var units := int(field.call("units_within_world", at, Constants.PILE_HIDE_RADIUS))
		if units > most:
			most = units
			pile = at
	if pile == Vector3.INF:
		return {"error": "the strokes made no pile"}
	_place(pile - Vector3(PILE_STAND_METERS, 0.0, 0.0), -PI * 0.5, RAKE_PITCH)
	await _ticks(3)
	return {"note": "a raked pile %.1f m ahead; hold primary to rake into it, secondary to bag it" % PILE_STAND_METERS, "pile": _v(pile), "pile_units": most, "is_pile": bool(field.call("is_pile_at", pile))}


## The NICE BOYS have been called: the warning starts now.
func _raid_warn() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	director.call("force_event")
	await _ticks(2)
	return {"note": "warning now; they arrive in %.0f s" % Constants.RUN_WARNING_SECONDS, "phase": _phase(), "arrives_in": snappedf(float(director.call("arrival_time")) - Net.server_time(), 0.01)}


## The warning is nearly over: they arrive in ARRIVE_LEAD_SECONDS, and you're
## standing where you can watch the arrival point.
func _raid_arrive() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	var arrival: Vector3 = director.call("crew_arrival_point")
	var lot := _lot_zone()
	var toward := Vector3(arrival.x - lot.global_position.x, 0.0, arrival.z - lot.global_position.z).normalized()
	var stand := arrival - toward * WATCH_ARRIVAL_METERS
	_place(Vector3(stand.x, lot.global_position.y + 0.1, stand.z), _yaw_toward(stand, arrival), -0.05)
	_warn_with(director, ARRIVE_LEAD_SECONDS)
	await _ticks(2)
	return {"note": "they arrive in %.1f s at the point you're facing (the game has no van pulling up: they appear there)" % ARRIVE_LEAD_SECONDS, "phase": _phase(), "arrives_in": snappedf(float(director.call("arrival_time")) - Net.server_time(), 0.01), "arrival": _v(arrival)}


## The chase is on and the head NICE BOY is a few steps away, coming for you.
func _caught() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	director.call("_begin_chase")
	await _ticks(3)
	var crew := _crew()
	if crew == null:
		return {"error": "no NICE BOY spawned"}
	var lot := _lot_zone()
	var toward_lot := Vector3(lot.global_position.x - crew.global_position.x, 0.0, lot.global_position.z - crew.global_position.z).normalized()
	var stand := crew.global_position + toward_lot * CAUGHT_GAP_METERS
	_place(Vector3(stand.x, crew.global_position.y + 0.1, stand.z), _yaw_toward(stand, crew.global_position), -0.05)
	await _ticks(2)
	return {"note": "%s is %.0f m away and coming; stand still to be caught, sprint to get away" % [crew.name, CAUGHT_GAP_METERS], "phase": _phase(), "crew": str(crew.name)}


## A hiding spot right in front of you, the warning counting down.
func _hide() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	var arrival: Vector3 = director.call("crew_arrival_point")
	var spot: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("hide_spots"):
		var candidate := node as Node3D
		if int(candidate.get("occupant")) != 0:
			continue
		if spot == null or candidate.global_position.distance_to(arrival) > spot.global_position.distance_to(arrival):
			spot = candidate
	if spot == null:
		return {"error": "this yard has no free hiding spot"}
	var stand: Vector3 = spot.call("exit_position")
	_place(stand, _yaw_toward(stand, spot.global_position), -0.2)
	_warn_with(director, HIDE_LEAD_SECONDS)
	await _ticks(2)
	return {"note": "facing %s; tap interact to get in, they arrive in %.1f s" % [str(spot.get("label")), HIDE_LEAD_SECONDS], "phase": _phase(), "spot": _v(spot.global_position)}


## Caught: the cohort closes, the van takes you (you're in it now).
func _van_ride() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	director.call("force_capture", Net.local_peer_id())
	var van: Node = await _wait_for(func() -> Variant:
		var ride := _van()
		return ride if ride != null and bool(ride.call("is_riding")) and int(ride.call("seat_of", Net.local_peer_id())) >= 0 else null)
	if van == null:
		return {"error": "the van didn't leave with you in it"}
	return {"note": "in the van, %.0f s from Annex B" % float(van.get("_duration")), "zone": _zone()}


## Satellite Annex B (R2 chunk 6): you're through the door with Form 27-B in your
## hands, a step back from the counter of the window your first box needs. The
## visit starts the way the shuttle starts it (Annex.begin), with a fixed raid
## seed so a recording shows the same room every time.
func _annex() -> Dictionary:
	var started: Dictionary = await _annex_start([Net.local_peer_id()])
	if started.has("error"):
		return started
	var annex := _annex_node()
	var form: Dictionary = annex.call("form_of", Net.local_peer_id())
	var window := str(preload("res://net/annex/form_state.gd").next_window(form))
	_stand_by(_annex_point("Windows/%s/Counter" % window), _annex_point("Windows/%s/ClerkSeat" % window), 1.4)
	await _ticks(3)
	return {"moment": "annex", "note": "Form 27-B in hand, window %s ahead (%d boxes)" % [window, (form["boxes"] as PackedStringArray).size()], "window": window, "zone": _zone(), "annex": annex.call("status")}


func _reached_annex() -> bool:
	var annex := _annex_node()
	return annex != null and bool(annex.call("is_active")) and str(annex.call("stage_of", Net.local_peer_id())) == "inside" and _zone() == "BORDER"


## A clerk about to stand up and stretch for his break: the window your next box
## needs, its telegraph 2 s away.
func _annex_break() -> Dictionary:
	var started: Dictionary = await _annex()
	if started.has("error"):
		return started
	var annex := _annex_node()
	var window := str(started["window"])
	var at := _find_state(annex, window, [_Sched.S.TELEGRAPH], [_Sched.S.BREAK, _Sched.S.JAM, _Sched.S.ASLEEP])
	if at < 0.0:
		return {"error": "no break coming at window %s" % window}
	annex.call("dev_retime", at - 2.0)
	_annex_window = window
	await _ticks(3)
	return {"moment": "annex_break", "note": "window %s's clerk telegraphs his break in 2 s" % window, "window": window}


## His stretch is on now or within 3 s, and a break (or jam, or nap) follows it.
func _reached_annex_break() -> bool:
	if not _reached_annex() or _annex_window == "":
		return false
	var annex := _annex_node()
	var seed_value := int(annex.call("seed_value"))
	var now: Dictionary = annex.call("window_now", _annex_window)
	var telegraph := now
	if int(now["state"]) != _Sched.S.TELEGRAPH:
		var wait := float(now["until"]) - float(annex.call("elapsed"))
		if wait <= 0.0 or wait > 3.0:
			return false
		telegraph = _Sched.window_state(seed_value, _annex_window, float(now["until"]) + 0.01)
		if int(telegraph["state"]) != _Sched.S.TELEGRAPH:
			return false
	var after := int(_Sched.window_state(seed_value, _annex_window, float(telegraph["until"]) + 0.01)["state"])
	return [_Sched.S.BREAK, _Sched.S.JAM, _Sched.S.ASLEEP].has(after)


## A heist: your next box's clerk is on the phone or away, and you're at his stamp.
func _annex_heist() -> Dictionary:
	var started: Dictionary = await _annex()
	if started.has("error"):
		return started
	var annex := _annex_node()
	var window := str(started["window"])
	var at := _find_state(annex, window, [_Sched.S.PHONE, _Sched.S.BREAK], [])
	if at < 0.0:
		return {"error": "window %s never looks away" % window}
	annex.call("dev_retime", at + 0.3)
	_annex_window = window
	_stand_by(_annex_point("Windows/%s/StampPad" % window), _annex_point("Windows/%s/ClerkSeat" % window), 0.25)
	await _ticks(3)
	return {"moment": "annex_heist", "note": "window %s's clerk is looking away; hold interact on his stamp" % window, "window": window}


## His clerk is looking away right now.
func _reached_annex_heist() -> bool:
	if not _reached_annex() or _annex_window == "":
		return false
	return not bool((_annex_node().call("window_now", _annex_window) as Dictionary)["looking"])


## The Head NICE BOY just went to the copier: a full form, and his big stamp on its pad in front of you.
func _annex_bigstamp() -> Dictionary:
	var started: Dictionary = await _annex()
	if started.has("error"):
		return started
	var annex := _annex_node()
	var at := _find_state(annex, "head", [_Sched.S.AWAY], [])
	if at < 0.0:
		return {"error": "the Head NICE BOY never leaves his desk"}
	annex.call("dev_retime", at + 1.5)
	var form: Dictionary = annex.call("form_of", Net.local_peer_id())
	form["stamped"] = (form["boxes"] as PackedStringArray).size() - 1
	annex.call("dev_set_form", Net.local_peer_id(), form)
	_stand_by(_annex_point("HeadDesk/Pad"), _annex_point("HeadDesk"), 0.9)
	await _ticks(3)
	return {"moment": "annex_bigstamp", "note": "he's away; interact lifts his big stamp, primary stamps"}


## He's away from his desk, and his big stamp is still on its pad.
func _reached_annex_bigstamp() -> bool:
	if not _reached_annex():
		return false
	var annex := _annex_node()
	return int((annex.call("window_now", "head") as Dictionary)["state"]) == _Sched.S.AWAY and int(annex.call("big_stamp_holder")) == 0


## Window D's blinds go up in 2 s; you're halfway across the room.
func _annex_window_d() -> Dictionary:
	var started: Dictionary = await _annex()
	if started.has("error"):
		return started
	var annex := _annex_node()
	var d_at := float(preload("res://net/annex/annex_schedule.gd").d_open_at(int(annex.call("seed_value"))))
	annex.call("dev_retime", d_at - 2.0)
	_stand_by(_annex_point("Windows/D/Counter"), _annex_point("Windows/D/ClerkSeat"), 4.0)
	await _ticks(3)
	return {"moment": "annex_window_d", "note": "Window D opens in 2 s"}


## Window D's blinds go up within 3 s.
func _reached_annex_window_d() -> bool:
	if not _reached_annex():
		return false
	var annex := _annex_node()
	var wait := _Sched.d_open_at(int(annex.call("seed_value"))) - float(annex.call("elapsed"))
	return wait > 0.0 and wait <= 3.0


## A friend at the Annex (the second player is the rider), and you at the visitor
## door: the Field Office's in the town, the Courtesy Desk by Homie Depot otherwise.
func _annex_visit() -> Dictionary:
	var friend := 0
	for peer_id: int in Net.peer_ids():
		if peer_id != Net.local_peer_id():
			friend = peer_id
			break
	if friend == 0:
		return {"error": "annex_visit needs a second player to be the one at the Annex (tools\\play.ps1 -Observer)"}
	if not bool(_world().call("is_town_map")):
		Net.move_player_to_zone(Net.local_peer_id(), Net.Zone.STORE)
		await _wait_for(func() -> Variant: return true if Net.player_zone(Net.local_peer_id()) == Net.Zone.STORE else null)
	var started: Dictionary = await _annex_start([friend])
	if started.has("error"):
		return started
	await _ticks(3)
	var door: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("annex_doors"):
		door = node as Node3D
	if door == null:
		return {"error": "no visitor door"}
	var out: Transform3D = door.call("out_transform")
	_place(out.origin, out.basis.get_euler().y + PI, -0.05)
	await _ticks(3)
	return {"moment": "annex_visit", "note": "%s is at Annex B; the door in front of you lets you in" % Net.player_name(friend)}


func _reached_annex_visit() -> bool:
	var annex := _annex_node()
	return annex != null and bool(annex.call("is_active")) and not get_tree().get_nodes_in_group("annex_doors").is_empty()


## Closing time in 10 s: the clock races, the lights flicker.
func _annex_closing() -> Dictionary:
	var started: Dictionary = await _annex()
	if started.has("error"):
		return started
	var annex := _annex_node()
	var status: Dictionary = annex.call("status")
	annex.call("dev_retime", Constants.ANNEX_CAP_SECONDS - 10.0)
	await _ticks(3)
	return {"moment": "annex_closing", "note": "closing time in 10 s", "was": status}


func _reached_annex_closing() -> bool:
	var annex := _annex_node()
	return _reached_annex() and bool(annex.call("urgent"))


## Begin a visit for these riders the way the shuttle does, and wait for the walk-in.
func _annex_start(riders: Array) -> Dictionary:
	var annex := _annex_node()
	var director := _director()
	if annex == null or director == null:
		return {"error": "no Annex (net/annex/annex.gd) in this world"}
	if bool(annex.call("is_active")):
		annex.rpc("_rpc_end")
		await _ticks(2)
	director.set("_hazard_seed", ANNEX_SEED)
	annex.call("begin", ANNEX_TRIP, riders, Net.server_time())
	var first := int(riders[0])
	var inside: Variant = await _wait_for(func() -> Variant:
		return true if str(annex.call("stage_of", first)) == "inside" else null)
	if inside == null:
		return {"error": "the walk-in never finished (stage %s)" % annex.call("stage_of", first)}
	return {}


## The schedule's first moment from now on where the window enters one of states
## (followed by one of then, when given). -1 when there's none in the day.
func _find_state(annex: Node, window: String, states: Array, then: Array) -> float:
	var seed_value := int(annex.call("seed_value"))
	var t := float(annex.call("elapsed")) + 1.0
	while t < Constants.ANNEX_CAP_SECONDS - 12.0:
		var state := _Sched.window_state(seed_value, window, t)
		if states.has(int(state["state"])):
			if then.is_empty() or then.has(int(_Sched.window_state(seed_value, window, float(state["until"]) + 0.01)["state"])):
				return float(state["since"])
			t = float(state["until"]) + 0.01
			continue
		t = float(state["until"]) + 0.01
	return -1.0


## Stand back from a spot, facing what it faces (toward look_at), on the floor.
func _stand_by(spot: Vector3, look_at: Vector3, back: float) -> void:
	if spot == Vector3.INF:
		return
	var away := Vector3(spot.x - look_at.x, 0.0, spot.z - look_at.z).normalized() if look_at != Vector3.INF else Vector3.BACK
	var at := spot + away * back
	_place(Vector3(at.x, spot.y + 0.1, at.z), _yaw_toward(at, spot - away * 2.0), -0.12)


func _annex_node() -> Node:
	return get_tree().get_first_node_in_group("annex")


func _annex_point(path: String) -> Vector3:
	var set_root := _world().get_node_or_null("BorderZone/AnnexSet")
	var node := set_root.get_node_or_null(path) as Node3D if set_root != null else null
	return node.global_position if node != null else Vector3.INF


## Back at the store (Homie Depot), the way the debug zone gates send you.
func _store() -> Dictionary:
	Net.move_player_to_zone(Net.local_peer_id(), Net.Zone.STORE)
	var there: Variant = await _wait_for(func() -> Variant:
		return true if Net.player_zone(Net.local_peer_id()) == Net.Zone.STORE else null)
	await _ticks(3)
	return {"zone": _zone()} if there != null else {"error": "never got to the store"}


## In Chefty's driver's seat, parked at Homie Depot (the connected town only).
func _drive() -> Dictionary:
	var world := _world()
	if not bool(world.call("is_town_map")):
		return {"error": "drive needs the connected town: start with --town-map (tools\\play.ps1 -Start -Scenario drive adds it)"}
	var chefty := get_tree().get_first_node_in_group("chefty")
	if chefty == null or not chefty.has_method("request_enter"):
		return {"error": "no drivable Chefty"}
	chefty.call("dev_place", Constants.CHEFTY_PARK_SPOT, Constants.CHEFTY_PARK_YAW)
	await get_tree().create_timer(0.3).timeout
	var me := _me()
	for attempt: int in 4:
		if int(chefty.call("driver")) == Net.local_peer_id():
			break
		var at: Transform3D = chefty.call("body_transform")
		var door: Vector3 = at * _Vehicles.CHEFTY_DRIVER_DOOR
		me.call("apply_network_teleport", Transform3D(Basis.IDENTITY, door + Vector3(0.0, 0.1, 0.0)))
		await _ticks(3)
		chefty.call("request_enter", 0)
		await get_tree().create_timer(0.5).timeout
	if int(chefty.call("driver")) != Net.local_peer_id():
		return {"error": "couldn't get in the driver's seat"}
	return {"note": "driving: move_forward/back throttle, move_left/right steer, interact gets out", "zone": _zone()}


# ---------------------------------------------------------------- reset


## Undo whatever an earlier moment left behind (a raid, a capture, a ride, a
## visit to Annex B, a hiding spot, a seat), so each scenario starts clean.
func reset() -> void:
	var me_id := Net.local_peer_id()
	var me := _me()
	var director := _director()
	var annex := _annex_node()
	if me != null:
		var spot := preload("res://net/components/hide_spot.gd").spot_of(get_tree(), me_id)
		if spot != null:
			spot.call("request_exit")
		if bool(me.get("in_pile")):
			me.call("set_pile", false)
	for vehicle: Node in get_tree().get_nodes_in_group("vehicles"):
		if vehicle.has_method("seat_of") and int(vehicle.call("seat_of", me_id)) >= 0 and vehicle.has_method("request_exit"):
			vehicle.call("request_exit")
	if director != null:
		director.set("_batching", false)
		if bool(director.call("is_captured", me_id)) or _van() != null:
			# Off the van and out of the cohort, on every peer (the director's own message).
			director.rpc("_rpc_drop_rider", me_id)
		if int(director.call("phase")) != 0:
			director.call("_dismiss_crew")
		var safe: Dictionary = director.get("_safe_until")
		safe.erase(me_id)
	if annex != null and bool(annex.call("is_active")):
		# Closed up, and everyone it held back where the game would send them.
		var held: Array = annex.call("roster")
		held.append_array(annex.call("visitors"))
		annex.rpc("_rpc_end")
		for peer_id: Variant in held:
			if Net.player_zone(int(peer_id)) == Net.Zone.BORDER:
				Net.move_player_to_zone(int(peer_id), Net.Zone.STORE)
	# A van still on its way (empty now) finishes its trip, or it can't leave again
	# (the host's start time only: other peers see it jump
	# to the route's end when it arrives; start an observer recording after this).
	var van := _van()
	if van != null and bool(van.call("is_riding")):
		van.set("_start_time", Net.server_time() - float(van.get("_duration")))
		await _wait_for(func() -> Variant: return true if not bool(van.call("is_riding")) else null)
	await _ticks(3)


# ---------------------------------------------------------------- helpers


## On a job yard: load one if none is waiting, and send the player there the
## way the game does (a host-ordered teleport). Returns "" or why not.
func _to_lot() -> String:
	var world := _world()
	if get_tree().get_first_node_in_group("job_lot") == null:
		world.call("_load_job_lot")
		await _ticks(5)
	if get_tree().get_first_node_in_group("job_lot") == null or _field() == null:
		return "no job yard (start with --start-zone=lot --job-seed=777, which tools\\play.ps1 -Scenario adds)"
	if Net.player_zone(Net.local_peer_id()) != Net.Zone.LOT:
		Net.move_player_to_zone(Net.local_peer_id(), Net.Zone.LOT)
		var there: Variant = await _wait_for(func() -> Variant:
			return true if Net.player_zone(Net.local_peer_id()) == Net.Zone.LOT else null)
		if there == null:
			return "couldn't get to the yard"
		await get_tree().create_timer(0.5).timeout
	return ""


## The first strip of untouched leaves, gag_test's way: STRIP_STEPS samples along +x.
func _fresh_strip() -> Vector3:
	var field := _field()
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	for z: float in [-6.0, -10.0, 2.0, 6.0, -14.0, 10.0, -2.0, 14.0]:
		for x: float in [-15.0, -9.0, 3.0, 9.0, -3.0]:
			var fine := true
			for step: int in STRIP_STEPS:
				if int(field.call("sample_world", lot.global_position + Vector3(x + float(step) * STRIP_STEP_METERS, 0.2, z))) < STRIP_MIN_DENSITY:
					fine = false
					break
			if fine:
				return lot.global_position + Vector3(x, 0.1, z)
	return Vector3.INF


## Get one of these into the player's hands, the way E does. Returns what's held.
func _hold(kind: String) -> String:
	var me := _me()
	var pockets := me.get_node_or_null("Pockets")
	if _held(me) == kind:
		return kind
	if pockets != null and int(pockets.call("slot_of_kind", kind)) >= 0:
		pockets.call("select", int(pockets.call("slot_of_kind", kind)))
		await _ticks(4)
		if _held(me) == kind:
			return kind
	var item: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion() and bool(node.call("is_loose")):
			item = node as Node3D
			break
	if item == null:
		return _held(me)
	item.global_position = me.global_position + Vector3(0.0, 0.4, 0.0) + (-me.global_basis.z) * 0.8
	item.set("linear_velocity", Vector3.ZERO)
	await _ticks(2)
	item.call("request_grab")
	await _ticks(4)
	if _held(me) != kind and pockets != null and int(pockets.call("slot_of_kind", kind)) >= 0:
		pockets.call("select", int(pockets.call("slot_of_kind", kind)))
		await _ticks(4)
	return _held(me)


func _held(me: Node) -> String:
	var held: Node = me.call("_held_prop")
	return str(held.get("kind")) if held != null else ""


## Stand here, facing yaw (radians; 0 faces -z), looking pitch radians up.
func _place(at: Vector3, yaw: float, pitch: float) -> void:
	var me := _me()
	me.call("apply_network_teleport", Transform3D(Basis(Vector3.UP, yaw), at))
	me.set("body_yaw", yaw)
	me.set("head_pitch", pitch)


func _yaw_toward(from: Vector3, to: Vector3) -> float:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return atan2(-flat.x, -flat.z)


## The warning, through the director's own phase message to every peer, started
## as if the call came in a while ago: the crew arrives in lead seconds.
func _warn_with(director: Node, lead: float) -> void:
	director.rpc("_rpc_phase", 1, Net.server_time() - (Constants.RUN_WARNING_SECONDS - lead), _Strings.UI["status_crew_coming"])


func _wait_for(check: Callable) -> Variant:
	var waited := 0.0
	while waited < SETTLE_SECONDS:
		var value: Variant = check.call()
		if value != null:
			return value
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return null


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _world() -> Node:
	return get_tree().get_first_node_in_group("world")


func _director() -> Node:
	return get_tree().get_first_node_in_group("run_director")


func _field() -> Node:
	return get_tree().get_first_node_in_group("leaf_field")


func _lot_zone() -> Node3D:
	return _world().get_node_or_null("LotZone") as Node3D


func _van() -> Node:
	return _world().get_node_or_null("Rides/Van")


func _crew() -> Node3D:
	var crew := get_tree().get_nodes_in_group("crew")
	return crew[0] as Node3D if not crew.is_empty() else null


func _phase() -> String:
	return ["QUIET", "WARNING", "CHASE"][clampi(int(_director().call("phase")), 0, 2)]


func _zone() -> String:
	return Net.Zone.keys()[Net.player_zone(Net.local_peer_id())]


func _v(at: Vector3) -> Array:
	return [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]
