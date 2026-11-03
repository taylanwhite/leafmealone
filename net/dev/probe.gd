extends Node

## Authority: local. Samples this peer once a second and writes a JSON report
## to the --measure path when the run ends. tools/soak_report.py reads the
## reports from every peer and decides pass or fail.

const _SmootherScript = preload("res://net/components/net_smoother.gd")
const _VoiceScript = preload("res://net/voice/voice.gd")
const _RunCuesScript = preload("res://ui/run_cues.gd")
const _HideSpotScript = preload("res://net/components/hide_spot.gd")
## A frame longer than this stalls sending, so hitches can come from a busy
## machine rather than the network. The report counts them so the two can be told apart.
const LONG_FRAME_SECONDS: float = 0.05
## Most stalls (frames over LONG_FRAME_SECONDS) the report lists.
const STALL_LOG_MAX: int = 4000

var _long_frames: int = 0
## Every frame longer than LONG_FRAME_SECONDS since launch, loading included, as
## [start, end] in local seconds (Time.get_ticks_usec). The report gives them in
## host time, so tools/soak_report.py can tell a packet lost while this peer (or the
## host relaying it) wasn't reading from one the network lost.
var _stalls: Array = []
var _last_frame_at: float = -1.0
var _throttle_opened: bool = false
## Lowest ENet throttle seen toward any peer after the first second. 32 is full.
var _throttle_min: int = -1
var _throttle_samples: int = 0
## Throttle toward each linked peer, once a second, for diagnosing drops.
var _throttle_trace: Array[int] = []
## Lowest ENet packet throttle LIMIT seen toward any connected peer, every frame
## from the first connection on (loading included), or -1 before one. 32 is full.
## The limit caps the throttle, and ENet's bandwidth pass dropped it to 1-5 for a
## second after each client joined until Net.host() set bandwidth_limit(0, 0); the
## once-a-second throttle sample above never saw that (docs/DECISIONS.md, 2026-11-03).
var _throttle_limit_min: int = -1

## A join (driving chunk E): the longest frame (ms) in the first JOIN_WINDOW_SECONDS
## after this peer was first linked (connected to the host, or hosting), what
## that frame was, and when (s after the link). Loading the world used to take
## one 2-5 s frame, long enough for ENet to drop the peer (docs/DECISIONS.md).
const JOIN_WINDOW_SECONDS: float = Constants.JOIN_STALL_WINDOW_SECONDS
var _linked_at: float = -1.0
var _join_stall_ms: float = 0.0
var _join_stall_at: float = -1.0
var _started_msec: int = 0
var _session_msec: int = -1
var _wait: float = 0.0
var _rtt_ms: Array[float] = []
var _fps: Array[float] = []
var _players_seen_max: int = 0
var _errors: Array[String] = []


## Godot's own frame timing, sampled once a second, to tell script time from physics time.
var _process_ms: Array[float] = []
var _physics_ms: Array[float] = []
var _active_bodies: int = 0
var _collision_pairs: int = 0
## This peer's own zones in order, for following captures and returns.
var _zones: Array[String] = []
## The host's zones in order as this peer heard them (townmap_test: a client's
## registry follows the host's position-derived zones in the connected town).
var _host_zones: Array[String] = []
## Seconds into the run this peer first reached Annex B (Zone.BORDER), or -1.
var _border_at: float = -1.0


func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	Net.player_zone_changed.connect(func(peer_id: int, zone: Net.Zone) -> void:
		if peer_id == Net.local_peer_id():
			_zones.append(Net.Zone.keys()[zone])
			if zone == Net.Zone.BORDER and _border_at < 0.0:
				_border_at = float(Time.get_ticks_msec() - _started_msec) / 1000.0
		if peer_id == 1:
			_host_zones.append(Net.Zone.keys()[zone])
	)


## Judder: how unevenly the camera moves from one rendered frame to the next
## while it moves at a steady speed. 0 is perfectly even. Rendering more frames
## than physics ticks without interpolation shows up as steps alternating
## between zero and double.
var _cam_last := Vector3.INF
var _cam_step_last: float = -1.0
var _judder_sum: float = 0.0
var _step_sum: float = 0.0
var _judder_frames: int = 0


## Ride wobble: how far the camera moves relative to the vehicle per frame while
## seated, in meters. 0 means you sit perfectly still in your seat.
var _wobble_sum: float = 0.0
var _wobble_frames: int = 0
var _ride_rel_last := Vector3.INF
var _ride_body_last := Vector3.INF
var _ride_step_last: float = -1.0
var _ride_judder_sum: float = 0.0
var _ride_step_sum: float = 0.0


func _measure_ride_wobble(camera_at: Vector3) -> void:
	var ride_body: Node3D = null
	for ride: Node in get_tree().get_nodes_in_group("rides"):
		if int(ride.call("seat_of", Net.local_peer_id())) >= 0:
			ride_body = ride.get_node_or_null("Body") as Node3D
	if ride_body == null:
		_ride_rel_last = Vector3.INF
		return
	var body_at := ride_body.get_global_transform_interpolated().origin
	var rel := ride_body.get_global_transform_interpolated().affine_inverse() * camera_at
	if _ride_rel_last != Vector3.INF:
		_wobble_sum += rel.distance_to(_ride_rel_last)
		_wobble_frames += 1
		# How evenly the vehicle itself moves from frame to frame.
		var step := body_at.distance_to(_ride_body_last)
		if _ride_step_last >= 0.0:
			_ride_judder_sum += absf(step - _ride_step_last)
			_ride_step_sum += step
		_ride_step_last = step
	_ride_rel_last = rel
	_ride_body_last = body_at


func _measure_judder() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := camera.get_global_transform_interpolated().origin
	# The driver's chase camera (player/vehicle_camera.gd) trails the truck on
	# purpose; wobble is about sitting still in your seat, so it doesn't count.
	if camera.name == "VehicleCamera":
		_ride_rel_last = Vector3.INF
	else:
		_measure_ride_wobble(at)
	var walking := false
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()) and node is CharacterBody3D:
			var velocity := (node as CharacterBody3D).velocity
			walking = Vector2(velocity.x, velocity.z).length() > 1.0
	if _cam_last != Vector3.INF:
		var step := Vector2(at.x - _cam_last.x, at.z - _cam_last.z).length()
		# Only steady walking counts. Frames that don't move at all while walking
		# are the judder, so they count too. Teleports and rides don't.
		if walking and step < 0.5 and _cam_step_last >= 0.0 and _cam_step_last < 0.5:
			_judder_sum += absf(step - _cam_step_last)
			_step_sum += step
			_judder_frames += 1
		_cam_step_last = step
	_cam_last = at


func _process(delta: float) -> void:
	_measure_judder()
	if _session_msec >= 0 and delta > LONG_FRAME_SECONDS:
		_long_frames += 1
	# By the wall clock rather than delta, which the engine may smooth.
	var now := local_seconds()
	if _last_frame_at >= 0.0 and now - _last_frame_at > LONG_FRAME_SECONDS and _stalls.size() < STALL_LOG_MAX:
		_stalls.append([_last_frame_at, now])
	_track_join(now)
	_last_frame_at = now
	if _session_msec < 0 and Net.current_state() == Net.State.IN_SESSION:
		_session_msec = Time.get_ticks_msec()
	_track_throttle_limit()
	_wait += delta
	if _wait < 1.0:
		return
	_wait = 0.0
	_track_throttle()
	_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_active_bodies = maxi(_active_bodies, int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)))
	_collision_pairs = maxi(_collision_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
	_fps.append(Engine.get_frames_per_second())
	_players_seen_max = maxi(_players_seen_max, Net.peer_ids().size())
	if not Net.is_host() and Net.has_clock_sample():
		_rtt_ms.append(Net.clock_rtt_seconds() * 1000.0)


## The clock the stall and hitch logs are kept on, in seconds.
static func local_seconds() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


## Local seconds (local_seconds) to host time (Net.server_time), with this peer's
## clock estimate as it stands now, the best one it had. -INF before a client has
## its first clock sample, when there is nothing to convert with.
func _to_host_time() -> float:
	if not Net.is_host() and not Net.has_clock_sample():
		return -INF
	return Net.server_time() - local_seconds()


## A log's entries with their first `times` fields (local seconds) moved to host
## time, to the millisecond.
func _in_host_time(entries: Array, offset: float, times: int = 2) -> Array:
	var out: Array = []
	if offset == -INF:
		return out
	for entry: Array in entries:
		var moved := entry.duplicate()
		for index: int in times:
			moved[index] = snappedf(float(entry[index]) + offset, 0.001)
		out.append(moved)
	return out


func write_report() -> void:
	var path := str(Net.dev_options().get("measure_path"))
	var session_seconds := 0.0
	if _session_msec >= 0:
		session_seconds = float(Time.get_ticks_msec() - _session_msec) / 1000.0
	var totals := Net.bandwidth_totals()
	var link := multiplayer.multiplayer_peer
	var dropped := int(link.get("packets_dropped")) if link != null and "packets_dropped" in link else 0
	var host_offset := _to_host_time()
	var smoother: Dictionary = _SmootherScript.stats.duplicate()
	smoother["hitch_log"] = _in_host_time(_SmootherScript.hitch_log, host_offset, 1)
	var report := {
		"peer_id": Net.local_peer_id(),
		"name": Net.player_name(Net.local_peer_id()),
		"is_host": Net.is_host(),
		"state": Net.State.keys()[Net.current_state()],
		"zone": Net.Zone.keys()[Net.player_zone(Net.local_peer_id())],
		"simulated_lag_ms": Net.simulated_lag_ms(),
		"session_seconds": session_seconds,
		"players_seen_max": _players_seen_max,
		"players_seen_final": Net.peer_ids().size(),
		"player_nodes_final": get_tree().get_nodes_in_group("players").size(),
		"rtt_ms_median": _percentile(_rtt_ms, 0.5),
		"rtt_ms_p95": _percentile(_rtt_ms, 0.95),
		"bytes_in": totals.x,
		"bytes_out": totals.y,
		"bytes_in_per_second": float(totals.x) / session_seconds if session_seconds > 0.0 else 0.0,
		"bytes_out_per_second": float(totals.y) / session_seconds if session_seconds > 0.0 else 0.0,
		"packets_dropped": dropped,
		"smoother": smoother,
		"voice": _voice_report(),
		# Frames over LONG_FRAME_SECONDS since launch, as [start, end] in host time,
		# and when this peer's session started, in host time (-1 if unknown).
		"stalls": _in_host_time(_stalls, host_offset),
		"session_started_at": snappedf(float(_session_msec) / 1000.0 + host_offset, 0.001) if _session_msec >= 0 and host_offset != -INF else -1.0,
		"run_cues": _RunCuesScript.log.duplicate(),
		"stage_cam": preload("res://player/stage_cam.gd").log.duplicate(),
		"stage_body": preload("res://player/stage_body.gd").log.duplicate(),
		"stage_test": preload("res://net/dev/stage_test.gd").result.duplicate(),
		"hud_test": preload("res://net/dev/hud_test.gd").result.duplicate(),
		"job_test": preload("res://net/dev/job_test.gd").result.duplicate(),
		"bonk_test": preload("res://net/dev/bonk_test.gd").result.duplicate(),
		"work_test": preload("res://net/dev/work_test.gd").result.duplicate(),
		"throw_test": preload("res://net/dev/throw_test.gd").result.duplicate(),
		"water_test": preload("res://net/dev/water_test.gd").result.duplicate(),
		"mower_test": preload("res://net/dev/mower_test.gd").result.duplicate(),
		"board_test": preload("res://net/dev/board_test.gd").result.duplicate(),
		"gag_test": preload("res://net/dev/gag_test.gd").result.duplicate(),
		"brawl_test": preload("res://net/dev/brawl_test.gd").result.duplicate(),
		"day_test": preload("res://net/dev/day_test.gd").result.duplicate(),
		"town_test": preload("res://net/dev/town_test.gd").result.duplicate(),
		"layout_test": preload("res://net/dev/layout_test.gd").result.duplicate(),
		"hire_test": preload("res://net/dev/hire_test.gd").result.duplicate(),
		"rival_test": preload("res://net/dev/rival_test.gd").result.duplicate(),
		"cast_test": preload("res://net/dev/cast_test.gd").result.duplicate(),
		"crew_cast": _crew_cast(),
		"audio_test": preload("res://net/dev/audio_test.gd").result.duplicate(true),
		"settings_test": preload("res://net/dev/settings_test.gd").result.duplicate(true),
		"audio": _audio(),
		"shop_test": preload("res://net/dev/shop_test.gd").result.duplicate(true),
		"shops": _shops(),
		"hotbar_test": preload("res://net/dev/hotbar_test.gd").result.duplicate(true),
		"hotbar": preload("res://net/components/hotbar.gd").snapshot(get_tree()),
		"crew_hands": get_tree().get_nodes_in_group("crew_hands").size(),
		"day": _day(),
		"town": _town(),
		"townmap_test": preload("res://net/dev/townmap_test.gd").result.duplicate(true),
		"icons_test": preload("res://net/dev/icons_test.gd").result.duplicate(true),
		"balance_test": preload("res://net/dev/balance_test.gd").result.duplicate(true),
		"town_site": _town_site(),
		"streamer": preload("res://levels/town/town_streamer.gd").stats.duplicate(),
		"drive_test": preload("res://net/dev/drive_test.gd").result.duplicate(true),
		"skate_test": preload("res://net/dev/skate_test.gd").result.duplicate(true),
		"skate_seen": preload("res://player/skate.gd").seen.duplicate(true),
		"playtest_tools_test": preload("res://net/dev/playtest_tools_test.gd").result.duplicate(true),
		"toss_test": preload("res://net/dev/toss_test.gd").result.duplicate(true),
		"annex": _annex(),
		"annex_test": preload("res://net/dev/annex_test.gd").result.duplicate(true),
		"drive": _drive(),
		"rake_net_test": _test_result_by_path("res://net/dev/rake_net_test.gd"),
		"leaf_motion_test": _test_result_by_path("res://net/dev/leaf_motion_test.gd"),
		"rake_stroke_test": _test_result_by_path("res://net/dev/rake_stroke_test.gd"),
		"shuttle_test": _test_result_by_path("res://net/dev/shuttle_test.gd"),
		"shuttle": _shuttle(),
		"leaf_view": _leaf_view(),
		"leaf_ledger": _leaf_ledger(),
		"vehicle_view": preload("res://net/components/vehicle_view.gd").stats.duplicate(),
		"heat": _heat(),
		# R2 chunk 2: the catches this peer saw, and the encounter test's result.
		"encounter": preload("res://net/run_events/encounter.gd").stats.duplicate(),
		"encounter_test": preload("res://net/dev/encounter_test.gd").result.duplicate(),
		"board": _board(),
		"rating": {"stars": Campaign.rating(), "reviews": Campaign.rating_count()},
		"lot_layout": _lot_layout(),
		"art_test": preload("res://net/dev/art_test.gd").result.duplicate(true),
		"lot_art": _lot_art(),
		"job_progress": _job_progress(),
		"hide_spots": _HideSpotScript.stats.duplicate(),
		"hide_test": preload("res://net/dev/hide_test.gd").result.duplicate(),
		"zones": _zones,
		"host_zones": _host_zones,
		"audio_driver": AudioServer.get_driver_name(),
		"leaf_instances": _leaf_instances(),
		"lot_work": _lot_work(),
		"judder": _judder_sum / maxf(_step_sum, 0.0001),
		"judder_frames": _judder_frames,
		"ride_wobble_m": _wobble_sum / maxf(float(_wobble_frames), 1.0),
		"ride_frames": _wobble_frames,
		"ride_judder": _ride_judder_sum / maxf(_ride_step_sum, 0.0001),
		"process_ms_median": _percentile(_process_ms, 0.5),
		"physics_ms_median": _percentile(_physics_ms, 0.5),
		"physics_active_bodies_max": _active_bodies,
		"physics_collision_pairs_max": _collision_pairs,
		"long_frames": _long_frames,
		"join_stall_ms": snappedf(_join_stall_ms, 0.1),
		"join_stall_at": snappedf(_join_stall_at, 0.01),
		"build_queue": preload("res://levels/build_queue.gd").stats.duplicate(),
		"enet_throttle_min": _throttle_min,
		"enet_throttle_trace": _throttle_trace,
		"enet_throttle_limit_min": _throttle_limit_min,
		"fps_median": _percentile(_fps, 0.5),
		"fps_min": _fps.min() if not _fps.is_empty() else 0.0,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[Probe] cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[Probe] wrote %s" % path)


## The day and the crew's rank as this peer sees them (net/day/day_clock.gd).
func _day() -> Dictionary:
	var clock := get_tree().get_first_node_in_group("day_clock")
	if clock == null:
		return {}
	return {"day": int(clock.get("day")), "xp": Campaign.crew_xp(), "pending": Campaign.pending_xp(), "tier": Campaign.crew_tier()}


## The town as this peer sees it: a hash of every house and the open requests.
func _town() -> Dictionary:
	var town := get_tree().get_first_node_in_group("town")
	if town == null:
		return {}
	return {"houses": hash(JSON.stringify(town.get("houses"))), "requests": town.get("requests"), "known": (town.call("known_houses") as Array).size()}


## The connected town as this peer built it (net/town/town_map.gd): the layout,
## the solid town (TownColliders), the job site's house and where the yard
## stands, and the slots hidden for it. CI compares the host's with a client's
## (net/dev/townmap_test.gd). {} in the legacy world.
func _town_site() -> Dictionary:
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not bool(world.call("is_town_map")):
		return {}
	var colliders := world.get_node_or_null("TownColliders")
	var streamer := world.get_node_or_null("TownStreamer")
	var lot_zone := world.get_node_or_null("LotZone") as Node3D
	var origin := lot_zone.global_position.snappedf(0.01) if lot_zone != null else Vector3.ZERO
	var lot := get_tree().get_first_node_in_group("job_lot")
	return {
		# The pick lock and the yard's stage (job_lot.gd): a client must read the
		# same as the host (driving chunk D review).
		"job_locked": bool(world.call("job_locked")),
		"job_stage": int(lot.get("stage")) if lot != null else -1,
		"layout": TownMap.LAYOUT_VERSION,
		"map": TownMap.layout_hash(),
		"house_id": int(world.call("job_site_house")),
		"lot_origin": [origin.x, origin.y, origin.z],
		"house_shapes": int(colliders.call("house_shapes_enabled")) if colliders != null else -1,
		"colliders": int(colliders.call("layout_hash")) if colliders != null else 0,
		"slot_hidden": streamer.call("hidden_slots") if streamer != null else [],
	}


## The drivable Chefty as this peer sees it (chefty_drive.gd dev_report: riders,
## driver, prediction error, horn, ...). {} in the legacy world.
func _drive() -> Dictionary:
	var chefty := get_tree().get_first_node_in_group("chefty")
	if chefty == null or not chefty.has_method("dev_report"):
		return {}
	return chefty.call("dev_report")


## The NICE BOYS as this peer sees them, by node name: name tag, last bark, outfit.
## CI compares the host's with a client's (net/dev/cast_test.gd).
func _crew_cast() -> Array:
	var crew: Array = []
	for node: Node in get_tree().get_nodes_in_group("crew"):
		var label := node.get_node_or_null("Visual/Label") as Label3D
		var body := node.get_node_or_null("Visual/CartoonBody")
		var bark: Variant = node.get("last_bark")
		var outfit: Variant = body.get("outfit") if body != null else null
		crew.append({
			"node": str(node.name),
			"tag": label.text if label != null else "",
			"bark": str(bark) if bark != null else "",
			"outfit": str(outfit) if outfit != null else "",
		})
	crew.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["node"]) < str(b["node"]))
	return crew


## The shops as this peer sees them (net/shops/shops.gd): the crew's supplies,
## a hash of today's stock, everyone's looks (by save key), Chefty's look,
## the truck paint the crew owns, and whose buffs are running. CI compares the
## host's with a client's (net/dev/shop_test.gd). Later shop chunks add each
## body's hat and Chefty's built color.
func _shops() -> Dictionary:
	var shops := get_tree().get_first_node_in_group("shops")
	if shops == null:
		return {}
	var supplies: Dictionary = shops.get("supplies")
	var sorted_supplies := {}
	var ids := supplies.keys()
	ids.sort()
	for id: Variant in ids:
		sorted_supplies[str(id)] = snappedf(float(supplies[id]), 0.01)
	var buff_ids := {}
	var buffs: Dictionary = shops.get("buffs")
	for peer_id: Variant in buffs:
		var running: Array = (buffs[peer_id] as Dictionary).keys()
		running.sort()
		buff_ids[Net.player_name(int(peer_id))] = running
	var owned: Array = (shops.get("crew_owned") as Array).duplicate()
	owned.sort()
	# The tools out on the yard as this peer sees them: "tier fuel%" per kind (and
	# the gas can's fill), so a client proves tier and fuel replicate.
	var tools := {}
	for node: Node in get_tree().get_nodes_in_group("props"):
		var kind := str(node.get("kind"))
		if node.is_queued_for_deletion() or not (Constants.TOOL_PRICES.has(kind) or kind == "gas_can"):
			continue
		tools[kind] = "%d %d%%" % [int(node.get("tier")), roundi(float(node.get("water") if kind == "gas_can" else node.get("fuel")))]
	var tool_kinds := tools.keys()
	tool_kinds.sort()
	var sorted_tools := {}
	for kind: Variant in tool_kinds:
		sorted_tools[kind] = tools[kind]
	# The garden shelves' boxes per item (props/shelf_stock.gd): built from the
	# replicated stock on each peer, so a client's must match the host's.
	var shelf := get_tree().get_first_node_in_group("shelf_stock")
	var shelf_units := {}
	if shelf != null:
		var units: Dictionary = shelf.call("units_by_item")
		var items := units.keys()
		items.sort()
		for item: Variant in items:
			shelf_units[str(item)] = int(units[item])
	# Each player's last snack (shops chunk 6: every peer plays it from this), and
	# the Snak-o-Matic's shelf as this peer built it (front snacks left, stuck).
	var by_name := {}
	var snacks: Dictionary = shops.get("snacks")
	for peer_id: Variant in snacks:
		var snack: Dictionary = snacks[peer_id]
		by_name[Net.player_name(int(peer_id))] = "%s %s" % [str(snack.get("item", "")), str(snack.get("buff", ""))]
	var names := by_name.keys()
	names.sort()
	var snack_names := {}
	for player_name: Variant in names:
		snack_names[player_name] = by_name[player_name]
	var machine := get_tree().get_first_node_in_group("vending_machines")
	var vending := "%d %d" % [int(machine.call("front_count")), (shops.get("vending_stuck") as Array).size()] if machine != null else ""
	return {
		"tools": sorted_tools,
		"shelf_units": shelf_units,
		"snacks": snack_names,
		"vending": vending,
		"supplies": sorted_supplies,
		"stock_day": int(shops.get("stock_day")),
		"stock_hash": hash(JSON.stringify(shops.get("stock"), "", true)),
		"looks_hash": hash(JSON.stringify(shops.get("looks"), "", true)),
		"truck": JSON.stringify(shops.get("truck"), "", true),
		"crew_owned": owned,
		"buffs": buff_ids,
		"rusty": _rusty(shops),
	}


## Rusty's day as this peer sees it (shops chunk 5): his mood, the used tools on
## his rack (and what its pallets show here), and the junk in Chefty's bed.
func _rusty(shops: Node) -> Dictionary:
	var rack: Array = (shops.get("used_today") as Array).duplicate()
	rack.sort()
	var shown: Array = []
	var stand := get_tree().get_first_node_in_group("rusty_rack")
	if stand != null:
		for index: int in (stand.get("slots") as Array).size():
			shown.append(str((stand.call("slot_state", "used_slot_%d" % index) as Dictionary).get("item", "")))
	var chefty := get_tree().get_first_node_in_group("chefty")
	return {
		"mood": snappedf(float(shops.get("rusty_mood")), 0.01),
		"used_today": rack,
		"rack": shown,
		"haggled": (shops.get("haggled") as Dictionary).size(),
		"junk_in_bed": int(chefty.call("junk_count")) if chefty != null and chefty.has_method("junk_count") else -1,
	}


## The crew's heat as this peer sees it.
func _heat() -> float:
	var heat := get_tree().get_first_node_in_group("heat")
	return float(heat.get("heat")) if heat != null else -1.0


## The Courtesy Shuttle's own measurements on this peer (net/run_events/shuttle.gd
## stats: trips, the fastest and longest step it was seen to make, park slides,
## seats, knocks, unbuckles, stragglers, zone moves, drops).
func _shuttle() -> Dictionary:
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	return (shuttle.get("stats") as Dictionary).duplicate(true) if shuttle != null else {}


## What this peer heard: the music director's mood, track and stingers
## (audio/music_director.gd) and any unregistered sound ids.
func _audio() -> Dictionary:
	var director := get_tree().get_first_node_in_group("music_director")
	var report := {"mood": "", "track": "", "stingers": [], "unknown_sfx": preload("res://audio/sfx.gd").unknown.duplicate()}
	if director != null:
		report["mood"] = str(director.call("current_mood"))
		report["track"] = str(director.call("current_track"))
		report["stingers"] = (director.call("stingers") as Array).duplicate()
	return report


## The job board's offers (their seeds) and the pick, as this peer sees them.
func _board() -> Dictionary:
	var board := get_tree().get_first_node_in_group("job_board")
	if board == null:
		return {}
	var seeds: Array = []
	for offer: Dictionary in (board.get("offers") as Array):
		seeds.append(int(offer["seed"]))
	return {"seeds": seeds, "chosen": int(board.get("chosen"))}


## The job yard's layout hash (levels/lots/lot_generator.gd), the same on every peer.
func _lot_layout() -> int:
	var lot := get_tree().get_first_node_in_group("job_lot")
	return int(lot.get_meta("layout_hash", 0)) if lot != null else 0


## The job yard's art hash (its look and its street block's, from the replicated
## hood, seed and the day's season; levels/town/block_builder.gd), 0 until the
## block is done. CI compares the host's with a client's (net/dev/art_test.gd).
func _lot_art() -> int:
	var lot := get_tree().get_first_node_in_group("job_lot")
	if lot == null or not bool(lot.get_meta("art_done", false)):
		return 0
	return int(lot.get_meta("art_hash", 0))


## How far along each task on this job is, as this peer sees it.
func _job_progress() -> Dictionary:
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	var progress: Dictionary = {}
	if tasks != null:
		for task: String in (tasks.get("active") as PackedStringArray):
			progress[task] = snappedf(float(tasks.call("progress", task)), 0.01)
	return progress


## What got done on the lot: how clean it is, bags lying around, and what Chefty
## holds. Bots work the job, so a soak shows whether the loop still runs.
func _lot_work() -> Dictionary:
	var field := get_tree().get_first_node_in_group("leaf_field")
	var chefty := get_tree().get_first_node_in_group("chefty")
	var loose := 0
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == "leaf_bag":
			loose += 1
	return {
		"cleaned_fraction": float(field.call("cleaned_fraction")) if field != null else 0.0,
		"loose_bags": loose,
		"truck_bags": int(chefty.call("bag_count")) if chefty != null else 0,
		"truck_value": int(chefty.call("bag_value")) if chefty != null else 0,
	}


## An R1 raking test's result, loaded by path (each chunk adds its own file);
## a test that isn't built yet reports so.
func _test_result_by_path(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {"done": true, "ok": false, "why": "not built"}
	var script := load(path) as Script
	if script == null:
		return {"done": true, "ok": false, "why": "not built"}
	return (script.get("result") as Dictionary).duplicate(true)


## The leaf view's and the leaf motion layer's counters (raking R1), {} when absent.
func _leaf_view() -> Dictionary:
	var out: Dictionary = {}
	var view := get_tree().get_first_node_in_group("leaf_view")
	if view != null and view.has_method("stats"):
		out.merge(view.call("stats"))
	var motion := get_tree().get_first_node_in_group("leaf_motion")
	if motion != null and motion.has_method("stats"):
		var stats: Dictionary = motion.call("stats")
		out.merge(stats)
		# Both define morph_units and merge keeps the view's: the motion layer's
		# (units it could not fly because the pool was full) under its own name.
		out["motion_morph_units"] = stats.get("morph_units", 0)
	return out


## The leaf field's event, batch and prediction-ledger counters (raking:1).
func _leaf_ledger() -> Dictionary:
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field == null or not field.has_method("ledger_stats"):
		return {}
	return field.call("ledger_stats")


## Leaf flakes drawn by every leaf renderer on this peer, and where the first one sits.
func _leaf_instances() -> Dictionary:
	var total := 0
	var views := 0
	var first := Vector3.INF
	for field: Node in get_tree().get_nodes_in_group("leaf_field"):
		for child: Node in field.find_children("*", "MultiMeshInstance3D", true, false):
			var view := child as MultiMeshInstance3D
			views += 1
			if view.multimesh == null:
				continue
			total += view.multimesh.instance_count
			if first == Vector3.INF and view.multimesh.instance_count > 0:
				first = view.global_transform * view.multimesh.get_instance_transform(0).origin
	return {"total": total, "views": views, "first_at": str(first)}


func _voice_report() -> Dictionary:
	var voice := Net.get_node_or_null("Voice")
	if voice == null or not bool(voice.call("is_available")):
		return {}
	var stats: Dictionary = _VoiceScript.stats
	var latency: Array[float] = voice.call("latency_samples")
	var received := int(stats["received_packets"])
	var lost := int(stats["lost_packets"])
	return {
		"sent_packets": stats["sent_packets"],
		"sent_bytes": stats["sent_bytes"],
		"received_packets": received,
		"lost_packets": lost,
		"loss_rate": float(lost) / float(maxi(received + lost, 1)),
		"heard_from": (stats["heard_from"] as Dictionary).size(),
		"decode_failures": stats["decode_failures"],
		"underruns": stats["underruns"],
		"dropped_seconds": stats["dropped_seconds"],
		"speaking_changes": stats["speaking_changes"],
		"latency_ms_median": _percentile(latency, 0.5),
		"latency_ms_p95": _percentile(latency, 0.95),
		# Each run of lost packets as [sent after, sent before, sender, how many], the
		# times the senders' own (host time).
		"gap_log": (stats["gap_log"] as Array).duplicate(),
	}


## The join's longest frame (see JOIN_WINDOW_SECONDS).
func _track_join(now: float) -> void:
	var link := multiplayer.multiplayer_peer
	if _linked_at < 0.0:
		if link != null and not (link is OfflineMultiplayerPeer) and link.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_linked_at = now
		return
	if _last_frame_at < _linked_at or now - _linked_at > JOIN_WINDOW_SECONDS:
		return
	var frame_ms := (now - _last_frame_at) * 1000.0
	if frame_ms > _join_stall_ms:
		_join_stall_ms = frame_ms
		_join_stall_at = _last_frame_at - _linked_at


func _track_throttle() -> void:
	var enet := Net.enet_peer()
	if enet == null or Net.current_state() != Net.State.IN_SESSION:
		return
	_throttle_samples += 1
	for packet_peer: ENetPacketPeer in enet.host.get_peers():
		if packet_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
			continue
		var value := int(packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE))
		if _throttle_trace.size() < 600:
			_throttle_trace.append(value)
		# ENet only raises the throttle on its first round-trip measurement after
		# Net opens it, which can take a few seconds while a session loads. What
		# matters is it falling again once it has been full.
		if value >= ENetPacketPeer.PACKET_THROTTLE_SCALE:
			_throttle_opened = true
		if _throttle_opened:
			_throttle_min = value if _throttle_min < 0 else mini(_throttle_min, value)


func _track_throttle_limit() -> void:
	var enet := Net.enet_peer()
	# A closed peer's host getter logs an engine error, so ask only while it's open.
	if enet == null or enet.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	for packet_peer: ENetPacketPeer in enet.host.get_peers():
		if packet_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
			continue
		var value := int(packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT))
		_throttle_limit_min = value if _throttle_limit_min < 0 else mini(_throttle_limit_min, value)


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return -1.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(round(fraction * (sorted.size() - 1))), 0, sorted.size() - 1)]

## Satellite Annex B (R2 chunk 6): its totals since launch, this peer's view of
## the visit now, and every BORDER player's look as this peer dresses them (the
## host and a client must agree: 0.4.5's host saw white outfits there).
func _annex() -> Dictionary:
	var annex := get_tree().get_first_node_in_group("annex")
	var out := {"stats": preload("res://net/annex/annex.gd").stats.duplicate(true), "first_at_s": _border_at}
	if annex != null:
		out["status"] = annex.call("status")
	var found := {}
	for node: Node in get_tree().get_nodes_in_group("players"):
		if Net.player_zone(str(node.name).to_int()) != Net.Zone.BORDER:
			continue
		var body := node.get_node_or_null("Visual/CartoonBody")
		if body != null:
			found[str(node.name)] = str(hash([body.get("shirt"), body.get("pants"), body.get("skin"), body.get("hair"), body.get("hat_style"), body.get("outfit")]))
	# In name order, so two peers' reports compare as JSON.
	var names := found.keys()
	names.sort()
	var looks := {}
	for key: Variant in names:
		looks[key] = found[key]
	out["looks"] = looks
	return out
