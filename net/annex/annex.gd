extends Node

## Authority: host for who is at Satellite Annex B, every form, every stamp, the
## big stamp, the turnstile and closing time. World/Annex (group "annex"), made by
## levels/world.gd on every peer. docs/GAME.md "Form 27-B, in Triplicate" is the
## design; gap-specs/nice_boys.json chunk 6 the spec.
##
## Caught players arrive at AnnexCurb (by the Shuttle, R2 chunk 4, which calls
## begin(); without it, world.on_ride_arrived(BORDER) does), follow the Greeter
## in and get a Form 27-B: a row of boxes, each a window's pictogram. Walk onto a
## lit window's counter spot and its clerk stamps your next box. The clerks keep
## routines (net/annex/annex_schedule.gd, a pure function of the seed and time),
## so while one is on the phone or on a break you can stamp your own box (hold
## interact on his stamp), at the risk of a carbon copy if he looks. Ring a bell
## and he turns to his filing cabinet and his neighbour leans over to look. Window
## D opens once. A full form goes to the Head NICE BOY's desk; while he's away
## anyone can lift his big stamp. An approved form goes in the OUTGOING tray, the
## turnstile turns, and you're out, with a receipt for $0.00. Friends still free
## can visit (net/annex/visitor_door.gd), co-sign, ring bells and carry the big
## stamp. At closing time everyone is approved AFTER HOURS and let out.
##
## Networking: every cosmetic thing is a pure function of (seed, begin time,
## ordered overrides, server time) on every peer; the host decides every outcome
## and sends it reliably: _rpc_begin, _rpc_join, _rpc_override(entry), _rpc_form,
## _rpc_big_stamp, _rpc_turnstile, _rpc_cosigned, _rpc_closing, _rpc_through,
## _rpc_end, _rpc_snapshot. Clients only ask: _rpc_request_* (client_t clamped to
## the grace window). The set (World/BorderZone/AnnexSet), the staff bodies, the
## clipboard and the slip are R2 chunk 5's; until those files exist, this uses
## net/annex/annex_greybox.gd and net/annex/annex_paper.gd, which answer the same calls.

const _Schedule = preload("res://net/annex/annex_schedule.gd")
const _Form = preload("res://net/annex/form_state.gd")
const _Receipt = preload("res://net/annex/receipt_lines.gd")
const _Greybox = preload("res://net/annex/annex_greybox.gd")
const _Paper = preload("res://net/annex/annex_paper.gd")
const _VisitorDoor = preload("res://net/annex/visitor_door.gd")
const _Strings = preload("res://ui/strings.gd")
const _Bank = preload("res://audio/sound_bank.gd")
const _Overheads = preload("res://ui/overheads.gd")
## Other chunks' files, reached only through load() behind ResourceLoader.exists.
const SET_SCRIPT := "res://levels/annex/annex_b.gd"
const FORM_SCRIPT := "res://props/form_27b.gd"
const RECEIPT_SCRIPT := "res://props/receipt_slip.gd"
const SERVING := Constants.ANNEX_SERVING_WINDOWS
## The staff bodies' play(state, at, args) (C10): a state, not a sound.
const STAFF_PLAY: StringName = &"play"
## Each serving window's neighbour, for the bell's lean (B leans either way, by bell count).
const NEIGHBOURS: Dictionary = {"A": ["B"], "B": ["A", "C"], "C": ["B"]}
## Where a rider is in their visit.
const STAGE_WALK := "walk"
const STAGE_INSIDE := "inside"
const STAGE_THROUGH := "through"
const STAGE_OUT := "out"
## Chunk 5's sound ids, and what plays until they exist.
const SOUND_FALLBACK: Dictionary = {
	"stamp_kachunk": "ui_stamp", "stamp_smudge": "whoosh", "desk_bell": "ui_pop", "office_ding": "clear",
	"blinds_rattle": "whoosh", "turnstile_clack": "ui_tick", "turnstile_clunk": "thud", "door_chime": "ui_pop",
	"pen_squeak": "ui_tick", "punch_card": "ui_stamp", "copier_beep": "tick", "party_toot": "register",
	"closing_bell": "warning", "lights_off_clunk": "thud", "clerk_snore": "", "receipt_print": "ui_tick",
	"whistle": "warning",
}

signal rider_through_turnstile(peer_id: int)
signal annex_ended

## For the probe, annex_test and the soak: totals since launch, and each visit.
static var stats: Dictionary = {"begun": 0, "riders": 0, "through": 0, "closing_outs": 0, "served": 0, "self_stamps": 0, "carbons": 0, "bells": 0, "wrong_windows": 0, "window_d": 0, "approved": 0, "big_stamps": 0, "spotted": 0, "cosigns": 0, "visitors": 0, "bounces": 0, "ended": 0, "visits": []}

# ---- every peer, from the host's messages
var _active: bool = false
var _trip_id: int = 0
var _seed: int = 0
var _start_at: float = 0.0
var _close_at: float = 0.0
var _roster: Array[int] = []
var _visitors: Array[int] = []
## peer -> form (net/annex/form_state.gd).
var _forms: Dictionary = {}
## peer -> {stage, joined_at, out_at}.
var _stages: Dictionary = {}
var _overrides: Array = []
var _icons: Dictionary = {}
var _quirks: Dictionary = {}
var _d_open_at: float = 0.0
var _big_holder: int = 0
var _closing: bool = false
var _serves_shown: int = 0

# ---- host only
var _queues: Dictionary = {}
var _serving: Dictionary = {}
var _holds: Dictionary = {}
var _bell_last: Dictionary = {}
var _bell_count: int = 0
var _wrong_until: Dictionary = {}
var _redirected: Dictionary = {}
var _cosigned: Dictionary = {}
var _heat_at_catch: Dictionary = {}
var _counts: Dictionary = {}
var _d_used: bool = false
var _spot_wait: float = 0.0
var _pending: Array = []
var _returning: Dictionary = {}
var _visitor_home: Dictionary = {}
var _last_request: Dictionary = {}
## peer -> {w}: the wrong window that already shook his head at them (R2b).
var _wrong_seen: Dictionary = {}
## peers going out through closing's iris, waiting for it to shut.
var _forcing: Dictionary = {}

# ---- local presentation
var _set: Node3D
var _shown: Dictionary = {}
var _form_view: Node3D
var _dwell_window: String = ""
var _dwell: float = 0.0
var _retry: float = 0.0
var _hold_kind: String = ""
var _hold_window: String = ""
## The window whose stamp your hand has out (R2c annex), until it's back.
var _borrow_window: String = ""
## Other players with a window's stamp out of its hatch: peer -> window. Their
## avatar's hands are on it (player.gd reads the body_hands meta) till it's back.
var _remote_borrows: Dictionary = {}
var _urgent_shown: bool = false
var _rows_off: int = 0
var _doors: Array[Node] = []
## The local player may pass the turnstile until then (server time).
var _turnstile_open_until: float = -1.0
var _turnstile_passing: bool = false
## The walk-in behind the Greeter: an anchor per rider that every peer moves the
## same way from the server clock, with the rider staged behind it (R2 chunk 1).
var _walk_anchors: Dictionary = {}
## Closing's dimming: what's shown (1 is untouched) and the light levels it
## scales from (empty when untouched).
var _dim_shown: float = 1.0
var _dim_base: Dictionary = {}
## Each window's BACK IN 5 MINUTES card, up or not (R2b: it never came down).
var _signs: Dictionary = {}
## The local player's ask at a wrong window's counter: once per arrival (R2b).
var _asked_wrong: String = ""
## The local player's turnstile ask: once per walk up to it (and again once
## the form they asked with gets approved).
var _gate_asked: bool = false
var _gate_asked_approved: bool = false
static var _first_visit_quipped: bool = false


func _ready() -> void:
	add_to_group("annex")
	add_to_group("prompt_sources")
	if not Net.player_left.is_connected(_on_player_left):
		Net.player_left.connect(_on_player_left)
	if not Net.player_joined.is_connected(_on_player_joined):
		Net.player_joined.connect(_on_player_joined)


# ---------------------------------------------------------------- public (C13)


func is_active() -> bool:
	return _active


## From ANNEX_URGENT_AT: the clock races, the lights flicker, the escape cue.
func urgent() -> bool:
	return _active and _t() >= _urgent_at()


func roster() -> Array[int]:
	return _roster.duplicate()


func visitors() -> Array[int]:
	return _visitors.duplicate()


func form_of(peer_id: int) -> Dictionary:
	return (_forms.get(peer_id, {}) as Dictionary).duplicate(true)


func stage_of(peer_id: int) -> String:
	return str((_stages.get(peer_id, {}) as Dictionary).get("stage", ""))


func seed_value() -> int:
	return _seed


func overrides() -> Array:
	return _overrides.duplicate(true)


## Seconds since the Annex began (the schedule's clock).
func elapsed() -> float:
	return _t()


## The effective state of a window ("A".."D", or "head") right now, every peer.
func window_now(window: String) -> Dictionary:
	return _Schedule.effective(_seed, window, _t(), _overrides)


func big_stamp_holder() -> int:
	return _big_holder


## For recorder.gd, remote play and the probe.
func status() -> Dictionary:
	if not _active:
		return {"active": false}
	var me := Net.local_peer_id()
	var out := {"active": true, "t": snappedf(_t(), 0.1), "roster": _roster.size(), "visitors": _visitors.size(), "closing": _closing, "urgent": urgent()}
	if _forms.has(me):
		var form: Dictionary = _forms[me]
		out["form"] = "%d/%d%s" % [int(form["stamped"]), (form["boxes"] as PackedStringArray).size(), " approved" if bool(form["approved"]) else ""]
		out["next"] = _Form.next_window(form)
		out["stage"] = stage_of(me)
	return out


## Host. The shuttle's riders reached AnnexCurb: their visit starts at server time at.
func begin(trip_id: int, riders: Array, at: float = -1.0) -> void:
	if not Net.is_host() or riders.is_empty():
		return
	var when := maxf(at, Net.server_time())
	var fresh: Array[int] = []
	for entry: Variant in riders:
		var peer_id := int(entry)
		if not _roster.has(peer_id) and Net.peer_ids().has(peer_id):
			fresh.append(peer_id)
	if fresh.is_empty():
		return
	if _active:
		for peer_id: int in fresh:
			var form := _new_form(peer_id, _roster.size())
			_arrive(peer_id, form)
			_rpc_join.rpc(peer_id, form, when)
		return
	var director := get_tree().get_first_node_in_group("run_director")
	var raid_seed := int(director.call("hazard_seed")) if director != null and director.has_method("hazard_seed") else 0
	if raid_seed == 0:
		raid_seed = randi()
	_trip_id = trip_id
	_seed = absi(raid_seed ^ (trip_id * 7919 + 1))
	_reset_host()
	var forms := {}
	for index: int in fresh.size():
		forms[fresh[index]] = _new_form(fresh[index], index)
	var cap := Constants.ANNEX_CAP_SECONDS_SOAK if float(Net.dev_options().get("run_event_at")) >= 0.0 else Constants.ANNEX_CAP_SECONDS
	var roster_list: Array = []
	for peer_id: int in fresh:
		roster_list.append(peer_id)
	# At the curb first (the zone move goes out before the begin, so every peer
	# stages the walk-in from the curb, not from the yard).
	for peer_id: int in fresh:
		_arrive(peer_id, forms[peer_id])
	_rpc_begin.rpc(trip_id, roster_list, _seed, when, forms, SERVING, _Schedule.quirks(_seed).keys(), _Schedule.d_open_at(_seed), when + cap)
	stats["begun"] = int(stats["begun"]) + 1
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null and telemetry.has_method("mark_annex_start"):
		telemetry.call("mark_annex_start")


## Host. A free friend came in through a visitor door.
func add_visitor(peer_id: int, home: Dictionary = {}) -> void:
	if not Net.is_host() or not _active or _visitors.has(peer_id) or _roster.has(peer_id):
		return
	_visitor_home[peer_id] = home
	var list: Array = []
	for id: int in _visitors:
		list.append(id)
	list.append(peer_id)
	_rpc_visitors.rpc(list)
	stats["visitors"] = int(stats["visitors"]) + 1


## Host. A visitor leaves (back through the door they used).
func remove_visitor(peer_id: int) -> void:
	if not Net.is_host() or not _visitors.has(peer_id):
		return
	_send_visitor_home(peer_id)


## Host, dev tools only (scenarios, annex_test): jump the Annex's clock so it
## reads t seconds since it began, on every peer. Overrides keep their schedule
## times; the walk-in and closing move with the clock.
func dev_retime(t_target: float) -> void:
	if not Net.is_host() or not _active:
		return
	var start := Net.server_time() - t_target
	_rpc_retime.rpc(start, start + (_close_at - _start_at))


@rpc("authority", "call_local", "reliable")
func _rpc_retime(start_at: float, close_at: float) -> void:
	var shift := start_at - _start_at
	_start_at = start_at
	_close_at = close_at
	# P1 catch (annex_test step 7 flake): a jump back in the Annex's day leaves the
	# host's interruptions from later in it lying in the new future, and they played
	# again as the clock reached them (a ghost approval, a ghost walk to the holder).
	# A retime starts the day over from there: nothing from after it happened.
	var t_now := Net.server_time() - start_at
	var kept: Array = []
	for entry: Variant in _overrides:
		if float((entry as Dictionary).get("at", 0.0)) <= t_now:
			kept.append(entry)
	_overrides = kept
	for key: Variant in _stages.keys():
		var entry: Dictionary = _stages[key]
		entry["joined_at"] = float(entry.get("joined_at", start_at)) + shift
	_shown.clear()
	_urgent_shown = false
	_rows_off = 0


## Host, dev tools only: put a rider's form in this state on every peer.
func dev_set_form(peer_id: int, form: Dictionary) -> void:
	if Net.is_host() and _forms.has(peer_id):
		_send_form(peer_id, form, Net.server_time(), "")


## Dev tools only (annex_test): the last report a client sent back.
var dev_report: Dictionary = {}


## Host, dev tools only: have one client do what its player would (the same
## requests its input sends), or report what it sees.
func dev_client(peer_id: int, op: String, args: Array = []) -> void:
	if Net.is_host():
		_rpc_dev_client.rpc_id(peer_id, op, args)


@rpc("authority", "call_local", "reliable")
func _rpc_dev_client(op: String, args: Array) -> void:
	var now := Net.server_time()
	match op:
		"self_stamp":
			_rpc_request_self_stamp.rpc_id(1, str(args[0]), bool(args[1]), now)
		"bell":
			_rpc_request_bell.rpc_id(1, str(args[0]))
		"desk":
			_rpc_request_desk.rpc_id(1)
		"tray":
			_rpc_request_tray.rpc_id(1)
		"big":
			_rpc_request_big_stamp.rpc_id(1, str(args[0]), int(args[1]))
		"report":
			var seeds: Array = args[0] if not args.is_empty() else []
			var hashes := []
			for entry: Variant in seeds:
				hashes.append(_Schedule.hash_samples(int(entry), 200))
			var windows := {}
			if _active:
				for window: String in Constants.ANNEX_WINDOWS + ["head"]:
					windows[window] = int(window_now(window)["state"])
			var looks := {}
			for node: Node in get_tree().get_nodes_in_group("players"):
				var body := node.get_node_or_null("Visual/CartoonBody")
				if body != null and Net.player_zone(str(node.name).to_int()) == Net.Zone.BORDER:
					looks[str(node.name)] = str(hash([body.get("shirt"), body.get("pants"), body.get("skin"), body.get("hair"), body.get("hat_style"), body.get("outfit")]))
			var me := Net.local_peer_id()
			_rpc_dev_report.rpc_id(1, {"hashes": hashes, "windows": windows, "looks": looks, "active": _active, "form": form_of(me), "stage": stage_of(me), "seed": _seed, "t": _t(), "form_view": _form_view != null and is_instance_valid(_form_view)})


@rpc("any_peer", "call_local", "reliable")
func _rpc_dev_report(report: Dictionary) -> void:
	if Net.is_host():
		dev_report = report
		dev_report["received_at"] = Net.server_time()


func snapshot() -> Dictionary:
	if not _active:
		return {"active": false}
	return {"active": true, "trip_id": _trip_id, "seed": _seed, "start_at": _start_at, "close_at": _close_at, "roster": _roster.duplicate(), "visitors": _visitors.duplicate(), "forms": _forms.duplicate(true), "stages": _stages.duplicate(true), "overrides": _overrides.duplicate(true), "big_holder": _big_holder, "closing": _closing}


## A late joiner's copy of the room (they spectate; they're never in the roster).
func apply_snapshot(snap: Dictionary) -> void:
	if not bool(snap.get("active", false)):
		return
	# The host's stages go in before any walk-in is queued: only riders still
	# walking are staged behind the Greeter, the rest stand where they are.
	_rpc_begin_local(int(snap["trip_id"]), snap["roster"], int(snap["seed"]), float(snap["start_at"]), snap["forms"], float(snap["close_at"]), snap["stages"])
	_visitors.clear()
	for entry: Variant in snap["visitors"]:
		_visitors.append(int(entry))
	_overrides = (snap["overrides"] as Array).duplicate(true)
	_big_holder = int(snap["big_holder"])
	_closing = bool(snap["closing"])
	_apply_big_stamp(_big_holder, Net.server_time())


# ---------------------------------------------------------------- host: begin, arrive, finish


func _reset_host() -> void:
	_queues.clear()
	_serving.clear()
	_holds.clear()
	_bell_last.clear()
	_bell_count = 0
	_wrong_until.clear()
	_redirected.clear()
	_cosigned.clear()
	_counts.clear()
	_d_used = false
	_pending.clear()
	_returning.clear()
	_visitor_home.clear()
	_wrong_seen.clear()
	_forcing.clear()
	_spot_wait = 0.0


func _new_form(peer_id: int, index: int) -> Dictionary:
	var heat := float(_heat_at_catch.get(peer_id, _heat_now()))
	var visits_before := int(Campaign.call("annex_visits", peer_id)) if Campaign.has_method("annex_visits") else 0
	var fast := visits_before > 0 and visits_before % Constants.ANNEX_FAST_PASS_EVERY == 0
	var form := _Form.make(_Form.boxes_for(_seed, index, heat, SERVING), fast)
	# The punch card's count travels on the form: the crew save is the host's.
	form["visits"] = visits_before + 1
	_counts[peer_id] = {"heat": heat}
	return form


## Host: a rider is at the curb (moved there if the shuttle didn't), the visit counts.
func _arrive(peer_id: int, _form: Dictionary) -> void:
	var curb := _marker("AnnexCurb")
	var body := _player(peer_id)
	if Net.player_zone(peer_id) != Net.Zone.BORDER or body == null or curb == null or body.global_position.distance_to(curb.global_position) > 4.0:
		Net.move_player_to_zone(peer_id, Net.Zone.BORDER, &"AnnexCurb")
	if Campaign.has_method("note_annex_visit"):
		Campaign.call("note_annex_visit", peer_id)
	_set_encounter_stage(peer_id, "ANNEX")
	stats["riders"] = int(stats["riders"]) + 1


## Host: a rider pushed through the turnstile (or was let out at closing).
func _through(peer_id: int, by_closing: bool) -> void:
	var stage: Dictionary = _stages.get(peer_id, {})
	if str(stage.get("stage", "")) != STAGE_INSIDE:
		return
	var now := Net.server_time()
	var seconds := maxf(now - float(stage.get("joined_at", _start_at)), 0.0)
	var best := float(Campaign.call("annex_best", peer_id)) if Campaign.has_method("annex_best") else 0.0
	var tally: Dictionary = _counts.get(peer_id, {})
	if by_closing:
		tally["closing"] = 1
	tally.merge(_raid_stats(peer_id))
	var lines := _Receipt.lines(hash([_seed, peer_id]), tally, seconds, best)
	var total := _Receipt.total_line(tally)
	if Campaign.has_method("note_annex_time"):
		Campaign.call("note_annex_time", peer_id, seconds)
	Campaign.add_xp(Constants.XP_PAPERWORK, "paperwork")
	stats["through"] = int(stats["through"]) + 1
	if by_closing:
		stats["closing_outs"] = int(stats["closing_outs"]) + 1
	(stats["visits"] as Array).append({"peer": peer_id, "seconds": snappedf(seconds, 0.1), "closing": by_closing, "boxes": (form_of(peer_id).get("boxes", PackedStringArray()) as PackedStringArray).size()})
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null and telemetry.has_method("mark_annex_finish"):
		telemetry.call("mark_annex_finish", peer_id)
	if _big_holder == peer_id:
		_host_return_stamp(now)
	_rpc_through.rpc(peer_id, now, seconds, by_closing, lines, total)
	_maybe_return()


## Host: send the finished riders home, all together (ANNEX_FINISH_AS_GROUP) once
## nobody is still inside, else each as they come out.
##
## R2c van: with the Shuttle, each rider is seated in the ride home as soon as
## their moment on the forecourt is over (straight away when let out at closing
## time), and the van waits for the rest of the cohort with them aboard: nobody
## stands about on the pavement or in its aisle (28 s in the e2e audit).
func _maybe_return() -> void:
	var waiting: Array[int] = []
	var stepping: Array = []
	var inside := 0
	var now := Net.server_time()
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	for peer_id: int in _roster:
		var stage := stage_of(peer_id)
		if stage == STAGE_THROUGH and not _returning.has(peer_id):
			# The forecourt is theirs for a moment first: the receipt prints, is
			# held up and pocketed before the shuttle home takes them (R2b). Let
			# out at closing time there is no forecourt: the door swings shut over
			# the lobby and opens on the seat (R2c van). Walk up to the ride home's
			# open door meanwhile and you step in there (R2c van review).
			var entry: Dictionary = _stages.get(peer_id, {})
			if not bool(entry.get("closing", false)) and now < float(entry.get("out_at", 0.0)) + Constants.ANNEX_FORECOURT_BEAT:
				if shuttle != null and shuttle.has_method("at_return_door") and bool(shuttle.call("at_return_door", peer_id)):
					stepping.append(peer_id)
					_returning[peer_id] = INF
					continue
				inside += 1
				continue
			waiting.append(peer_id)
		elif stage == STAGE_INSIDE or stage == STAGE_WALK:
			inside += 1
	if shuttle != null and shuttle.has_method("host_start_return"):
		var more := Constants.ANNEX_FINISH_AS_GROUP and inside > 0
		if not stepping.is_empty():
			shuttle.call("host_start_return", stepping, _drop_target(), more or not waiting.is_empty(), true)
		if not waiting.is_empty():
			var peers: Array = []
			for id: int in waiting:
				peers.append(id)
				_returning[id] = INF
			shuttle.call("host_start_return", peers, _drop_target(), more)
		elif not more and not _returning.is_empty() and shuttle.has_method("host_release_return"):
			# The last of them left some other way (a disconnect): no more to wait for.
			shuttle.call("host_release_return")
		return
	if waiting.is_empty() or (Constants.ANNEX_FINISH_AS_GROUP and inside > 0):
		return
	var leave_at := Net.server_time() + Constants.ANNEX_RETURN_WAIT
	for peer_id: int in waiting:
		_returning[peer_id] = leave_at
	_pending.append({"at": leave_at, "do": "send_home", "peers": waiting.duplicate()})


## Where riders go back to: the yard if one is waiting, else Homie Depot.
func _drop_target() -> Dictionary:
	var slot := get_parent().get_node_or_null("LotZone/LotSlot")
	var yard_waiting := slot != null and slot.get_child_count() > 0
	return {"zone": Net.Zone.LOT if yard_waiting else Net.Zone.STORE, "marker": ""}


## Host, without the Shuttle: home by the host's teleport, let go with immunity.
func _send_home(peer_id: int) -> void:
	if not Net.peer_ids().has(peer_id):
		return
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and director.has_method("release_peer"):
		# With R2 chunk 2's director the drop-off's own immunity, else its default.
		var takes_immunity := false
		for method: Dictionary in director.get_method_list():
			if str(method["name"]) == "release_peer":
				takes_immunity = (method["args"] as Array).size() >= 2
		if takes_immunity:
			director.call("release_peer", peer_id, Constants.ANNEX_DROP_IMMUNITY)
		else:
			director.call("release_peer", peer_id)
	_set_encounter_stage(peer_id, "FREE")
	Net.move_player_to_zone(peer_id, int(_drop_target()["zone"]) as Net.Zone)
	_rpc_out.rpc(peer_id)


func _send_visitor_home(peer_id: int) -> void:
	var home: Dictionary = _visitor_home.get(peer_id, {})
	_visitor_home.erase(peer_id)
	var zone := int(home.get("zone", Net.Zone.STORE))
	var at: Variant = home.get("at", null)
	if at is Transform3D:
		Net.move_player_to_zone(peer_id, zone as Net.Zone, &"", false)
		_rpc_place.rpc_id(peer_id, at)
	else:
		Net.move_player_to_zone(peer_id, zone as Net.Zone)
	var list: Array = []
	for id: int in _visitors:
		if id != peer_id:
			list.append(id)
	_rpc_visitors.rpc(list)


# ---------------------------------------------------------------- host: the room


func _process(delta: float) -> void:
	if Net.is_host():
		_watch_catches()
		if _active:
			_host_tick(delta)
	if _active:
		_present(delta)
		_local_input(delta)
	if not _remote_borrows.is_empty():
		_hands_on_borrowed()


## Everyone else's self-stamp, as you see it (review: the stamp shot out of the
## hatch and slammed in front of them with no hand on it): their right hand on its
## knob, their left held out flat under where it comes down, while it's out; the
## right hand puts it back on its pad (review: it flew home on its own). Their own
## screen does this with their first-person arms.
func _hands_on_borrowed() -> void:
	for key: Variant in _remote_borrows.keys():
		var peer_id := int(key)
		var body := _player(peer_id)
		var piece := _set_node("Windows/%s" % str(_remote_borrows[key])) if _active else null
		var out := piece != null and piece.has_method("borrowed") and bool(piece.call("borrowed"))
		if body == null or not out:
			_remote_borrows.erase(key)
			if body != null and body.has_meta(&"body_hands"):
				body.remove_meta(&"body_hands")
			continue
		var hands := {"right": piece.call("stamp_knob") as Vector3 + Vector3.UP * Constants.ANNEX_KNOB_GRIP}
		if bool(piece.call("in_hand")):
			hands["left"] = body.global_transform * Constants.ANNEX_BORROW_CARRY - Vector3.UP * Constants.ANNEX_BORROW_PALM_DROP
		body.set_meta(&"body_hands", hands)


## Remember each caught player's heat at the catch (the form's length).
func _watch_catches() -> void:
	var director := get_tree().get_first_node_in_group("run_director")
	if director == null:
		return
	var roster: Array = director.call("cohort_roster")
	for entry: Variant in roster:
		if not _heat_at_catch.has(int(entry)):
			_heat_at_catch[int(entry)] = _heat_now()
	for key: Variant in _heat_at_catch.keys():
		if not roster.has(key) and not _roster.has(int(key)):
			_heat_at_catch.erase(key)


func _host_tick(delta: float) -> void:
	var now := Net.server_time()
	var t := _t()
	# Timed host actions (a serve's stamp, the desk slam, the stamp taken back, the trip home).
	var due: Array = []
	for item: Dictionary in _pending:
		if now >= float(item["at"]):
			due.append(item)
	for item: Dictionary in due:
		_pending.erase(item)
		_do(item)
	# The walk-in ends: the clipboard.
	for peer_id: int in _roster:
		var stage: Dictionary = _stages.get(peer_id, {})
		if str(stage.get("stage", "")) == STAGE_WALK and now >= float(stage.get("joined_at", 0.0)) + Constants.ANNEX_GREETER_WALK and _walked_in(peer_id, now - float(stage.get("joined_at", 0.0))):
			_rpc_stage.rpc(peer_id, STAGE_INSIDE, now)
	_serve_queues(now, t)
	_step_holds(now, t)
	_spot_check(delta, now, t)
	_watch_turnstile(now)
	_forget_wrong_windows()
	if not _closing and now >= _close_at:
		_host_closing(now)
	if _closing and now >= _close_at + Constants.ANNEX_CLOSING_OUT:
		for peer_id: int in _roster:
			if (stage_of(peer_id) == STAGE_INSIDE or stage_of(peer_id) == STAGE_WALK) and not _forcing.has(peer_id):
				_rpc_stage.rpc(peer_id, STAGE_INSIDE, now)
				_force_out(peer_id)
	# Finishers waiting for the group go once nobody is left inside, however the
	# last one left (through the turnstile, out at closing, or a disconnect).
	_maybe_return()
	_maybe_end()


func _do(item: Dictionary) -> void:
	var now := Net.server_time()
	match str(item["do"]):
		"serve_ink":
			# Sent ANNEX_INK_LEAD ahead of the stamp hitting the pad, with the hit's
			# time: every peer inks the box on the KA-CHUNK's frame (R2b).
			var peer_id := int(item["peer"])
			var window := str(item["window"])
			if not _forms.has(peer_id) or _Form.next_window(_forms[peer_id]) != window:
				return
			var form: Dictionary = _Form.stamp(_forms[peer_id])
			if _quirks.get(window, "") == "redirect" and not bool(_redirected.get(peer_id, false)):
				_redirected[peer_id] = true
				form = _Form.redirect(form, _redirect_window(window, form))
				_bump(peer_id, "redirect")
			stats["served"] = int(stats["served"]) + 1
			# The clerk who just served you isn't a wrong window while you're still
			# on his spot watching the hand-back (R2b review: he shook his head at you).
			_wrong_seen[peer_id] = {"w": window}
			_send_form(peer_id, form, float(item["hit"]), window)
		"serve_done":
			_serving.erase(str(item["window"]))
		"approve_done":
			var peer_id := int(item["peer"])
			if _forms.has(peer_id) and not bool(_forms[peer_id]["approved"]):
				stats["approved"] = int(stats["approved"]) + 1
				_send_form(peer_id, _Form.approve(_forms[peer_id]), float(item.get("hit", now)), "head")
		"force_out":
			# The iris has shut: out to the forecourt behind it (R2b: the move used
			# to land before the iris closed).
			var peer_id := int(item["peer"])
			_forcing.erase(peer_id)
			if stage_of(peer_id) == STAGE_INSIDE and _active and Net.peer_ids().has(peer_id):
				var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
				if shuttle == null or not shuttle.has_method("host_start_return"):
					Net.move_player_to_zone(peer_id, Net.Zone.BORDER, &"Forecourt")
				# With the Shuttle they stay where they stand behind the shut door until
				# its seat takes them (_maybe_return, at once for a closing-time out).
				_through(peer_id, true)
		"visitor_out":
			var peer_id := int(item["peer"])
			if _visitors.has(peer_id):
				_send_visitor_home(peer_id)
		"stamp_back":
			_host_return_stamp(now, int(item.get("peer", 0)))
		"send_home":
			for entry: Variant in item["peers"]:
				_send_home(int(entry))
		"visitors_home":
			for peer_id: int in _visitors.duplicate():
				_send_visitor_home(peer_id)
		"visit":
			var peer_id := int(item["peer"])
			if Net.peer_ids().has(peer_id) and _active:
				Net.move_player_to_zone(peer_id, Net.Zone.BORDER, &"AnnexSide")
				add_visitor(peer_id, item["home"])


func _serve_queues(now: float, t: float) -> void:
	for window: String in Constants.ANNEX_WINDOWS:
		if _serving.has(window):
			continue
		var queue: Array = _queues.get(window, [])
		while not queue.is_empty():
			var peer_id := int(queue[0])
			var counter := _window_spot(window, "Counter")
			var body := _player(peer_id)
			var still := body != null and counter != Vector3.INF and _flat(body.global_position, counter) <= Constants.ANNEX_QUEUE_REACH and _forms.has(peer_id) and _Form.next_window(_forms[peer_id]) == window
			if not still:
				queue.pop_front()
				continue
			if bool(_Schedule.effective(_seed, window, t, _overrides)["serving"]):
				queue.pop_front()
				_start_serve(peer_id, window, now)
			break
		_queues[window] = queue


func _start_serve(peer_id: int, window: String, now: float) -> void:
	var until := now + Constants.ANNEX_SERVE_SECONDS
	var hit := now + Constants.ANNEX_SERVE_STAMP_AT + Constants.ANNEX_STAMP_HIT
	_serving[window] = {"peer": peer_id, "until": until}
	_add_override({"kind": "serve", "w": window, "at": now, "until": until, "peer": peer_id})
	_pending.append({"at": hit - Constants.ANNEX_INK_LEAD, "do": "serve_ink", "peer": peer_id, "window": window, "hit": hit})
	_pending.append({"at": until, "do": "serve_done", "peer": peer_id, "window": window})


## A wrong window shakes his head once per visit to his counter: stepping away
## lets him do it again.
func _forget_wrong_windows() -> void:
	for key: Variant in _wrong_seen.keys():
		var window := str((_wrong_seen[key] as Dictionary).get("w", ""))
		var body := _player(int(key))
		var counter := _window_spot(window, "Counter")
		if body == null or counter == Vector3.INF or _flat(body.global_position, counter) > Constants.ANNEX_COUNTER_REACH + Constants.ANNEX_LOOSE_SLACK:
			_wrong_seen.erase(key)


## Self-stamps and co-signing: holds the host times.
func _step_holds(now: float, t: float) -> void:
	for key: Variant in _holds.keys():
		var peer_id := int(key)
		var hold: Dictionary = _holds[key]
		var body := _player(peer_id)
		var window := str(hold.get("window", ""))
		if str(hold["kind"]) == "self_stamp":
			var spot := _window_spot(window, "StampPad")
			if body == null or spot == Vector3.INF or _flat(body.global_position, spot) > Constants.ANNEX_STAMP_REACH + Constants.ANNEX_HOLD_SLACK:
				_holds.erase(key)
				continue
			var state := _Schedule.effective(_seed, window, t, _overrides)
			if bool(state["looking"]):
				# Caught with a hand on his stamp: a carbon copy, a smile, a scribble.
				_holds.erase(key)
				_add_override({"kind": "notice", "w": window, "at": now, "until": now + Constants.ANNEX_NOTICE_SECONDS, "peer": peer_id})
				stats["carbons"] = int(stats["carbons"]) + 1
				_bump(peer_id, "carbon")
				if _forms.has(peer_id):
					_send_form(peer_id, _Form.carbon(_forms[peer_id], window), now, "")
				continue
			if now - float(hold["start"]) >= Constants.ANNEX_SELF_STAMP_HOLD:
				_holds.erase(key)
				var ok := _forms.has(peer_id) and _Form.next_window(_forms[peer_id]) == window and not bool(_forms[peer_id]["approved"])
				_rpc_stamped.rpc(peer_id, window, now, ok)
				if ok:
					stats["self_stamps"] = int(stats["self_stamps"]) + 1
					# The ink lands with the stamp's KA-CHUNK, ANNEX_STAMP_HIT on.
					_send_form(peer_id, _Form.stamp(_forms[peer_id]), now + Constants.ANNEX_STAMP_HIT, "self")
		elif str(hold["kind"]) == "cosign":
			var sheet := _marker("CoSignSheet")
			if body == null or sheet == null or _flat(body.global_position, sheet.global_position) > Constants.ANNEX_SHEET_REACH + Constants.ANNEX_HOLD_SLACK:
				_holds.erase(key)
				continue
			if now - float(hold["start"]) >= Constants.ANNEX_COSIGN_HOLD:
				_holds.erase(key)
				_host_cosign(peer_id, now)


## The Head NICE BOY's view of his big stamp, ANNEX_STAMP_SPOT_HZ times a second.
func _spot_check(delta: float, now: float, t: float) -> void:
	if _big_holder == 0:
		return
	_spot_wait -= delta
	if _spot_wait > 0.0:
		return
	_spot_wait = 1.0 / Constants.ANNEX_STAMP_SPOT_HZ
	var head := _Schedule.effective(_seed, "head", t, _overrides)
	if not bool(head["looking"]) or int(head["state"]) == _Schedule.S.SPOTTED:
		return
	var body := _player(_big_holder)
	var desk := _marker("HeadDesk")
	if body == null or desk == null:
		return
	if not _head_sees(desk, body.global_position + Vector3(0.0, 1.0, 0.0)):
		return
	stats["spotted"] = int(stats["spotted"]) + 1
	_add_override({"kind": "spotted", "w": "head", "at": now, "until": now + Constants.ANNEX_SPOTTED_WALK + 0.6, "peer": _big_holder})
	_pending.append({"at": now + Constants.ANNEX_SPOTTED_WALK, "do": "stamp_back", "peer": _big_holder})


## He looks out across his desk (toward DeskSpot) from his chair: a cone and a clear line.
func _head_sees(desk: Node3D, point: Vector3) -> bool:
	var spot := desk.get_node_or_null("DeskSpot") as Node3D
	var facing := (spot.global_position - desk.global_position) if spot != null else -desk.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var eye := desk.global_position - facing * 0.8 + Vector3(0.0, 1.55, 0.0)
	var to := point - eye
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() < 0.05:
		return true
	if rad_to_deg(facing.angle_to(flat.normalized())) > Constants.ANNEX_CLERK_VIEW_DEG * 0.5:
		return false
	var space := (desk as Node3D).get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, point, 1)
	var hit := space.intersect_ray(query)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(point) < 0.6


func _host_return_stamp(now: float, from_peer: int = 0) -> void:
	if _big_holder == 0:
		return
	var holder := _big_holder
	if from_peer != 0 and from_peer != holder:
		return
	if from_peer != 0 and _forms.has(holder):
		# Taken back: the holder's approval and one box's ink smudge off.
		_send_form(holder, _Form.smudge(_forms[holder]), now, "smudge")
	_big_holder = 0
	_rpc_big_stamp.rpc(0, now)


func _host_cosign(visitor: int, now: float) -> void:
	if bool(_cosigned.get(visitor, false)):
		return
	_cosigned[visitor] = true
	stats["cosigns"] = int(stats["cosigns"]) + 1
	_rpc_cosigned.rpc(visitor, now)
	for peer_id: int in _roster:
		if stage_of(peer_id) != STAGE_INSIDE or not _forms.has(peer_id):
			continue
		var form: Dictionary = _forms[peer_id]
		if bool(form["approved"]) or _Form.is_full(form):
			continue
		_bump(peer_id, "cosigned")
		_send_form(peer_id, _Form.stamp(form), now, "cosign")
		if Campaign.has_method("add_rescue"):
			Campaign.call("add_rescue", visitor, &"cosign")


## Approved riders who pushed through: out. Anyone else at the turnstile bounces
## (the bar's collider already stopped them; the clunk is the host's).
func _watch_turnstile(_now: float) -> void:
	var turnstile := _marker("Turnstile")
	var forecourt := _marker("Forecourt")
	if turnstile == null or forecourt == null:
		return
	var out_dir := forecourt.global_position - turnstile.global_position
	out_dir.y = 0.0
	out_dir = out_dir.normalized()
	for peer_id: int in _roster:
		if stage_of(peer_id) != STAGE_INSIDE:
			continue
		var form: Dictionary = _forms.get(peer_id, {})
		# Through with a form in the tray, or anyone once closing has opened it for all.
		if not bool(form.get("approved", false)) or not (bool(form.get("dropped", false)) or _closing):
			continue
		var body := _player(peer_id)
		if body == null:
			continue
		var offset := body.global_position - turnstile.global_position
		if offset.dot(out_dir) > Constants.ANNEX_TURNSTILE_PASS_DEPTH and Vector3(offset.x, 0.0, offset.z).length() < Constants.ANNEX_TURNSTILE_PASS_WIDTH:
			_through(peer_id, false)


func _host_closing(now: float) -> void:
	_closing = true
	for peer_id: int in _roster:
		if stage_of(peer_id) == STAGE_INSIDE and _forms.has(peer_id) and not bool(_forms[peer_id]["approved"]):
			_forms[peer_id] = _Form.approve(_forms[peer_id], true)
	_rpc_closing.rpc(now, _forms)


## Closing time's stragglers: out through the door-swing iris (R2 chunk 1) to the
## forecourt, counted as let out at closing. The move waits for the door to
## swing shut (ANNEX_DOOR_IRIS_WAIT, as a visit goes in): moved in the same tick,
## the forecourt showed before the door did (R2b annex and van).
func _force_out(peer_id: int) -> void:
	if _forcing.has(peer_id):
		return
	var iris_owner := _player(peer_id)
	if iris_owner == null:
		return
	var now := Net.server_time()
	_forcing[peer_id] = true
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if shuttle != null and shuttle.has_method("host_start_return"):
		# R2c van: one iris. The door swings shut over the lobby and stays shut;
		# behind it they're seated in the ride home, and it opens on the seat (the
		# shuttle opens it). Before, it opened on the forecourt, both riders on one
		# spot, and a second iris took them to the van.
		# Sent a beat ahead, so a client's swish isn't skipped as late (it shuts by
		# now + VAN_PLAN_LEAD + ANNEX_IRIS_CLOSE, before the seat takes them).
		_rpc_closing_iris.rpc_id(peer_id, now + Constants.VAN_PLAN_LEAD)
	else:
		_rpc_door_iris.rpc_id(peer_id, now)
	_pending.append({"at": now + Constants.ANNEX_DOOR_IRIS_WAIT, "do": "force_out", "peer": peer_id})


func _maybe_end() -> void:
	var anyone := false
	for peer_id: int in _roster:
		var stage := stage_of(peer_id)
		if stage != STAGE_OUT and not (stage == STAGE_THROUGH and float(_returning.get(peer_id, 0.0)) == INF):
			anyone = true
	if anyone:
		return
	if not _visitors.is_empty():
		var queued := false
		for item: Dictionary in _pending:
			queued = queued or str(item["do"]) == "visitors_home"
		if not queued:
			_pending.append({"at": Net.server_time() + Constants.ANNEX_RETURN_WAIT, "do": "visitors_home"})
		return
	_rpc_end.rpc()


func _send_form(peer_id: int, form: Dictionary, at: float, source: String) -> void:
	_forms[peer_id] = form
	_rpc_form.rpc(peer_id, form, at, source)


## Overrides travel and are kept in the schedule's clock (seconds since the
## Annex began), like annex_schedule.gd's own segments; callers pass server times.
func _add_override(entry: Dictionary) -> void:
	var rel := entry.duplicate()
	rel["at"] = float(entry["at"]) - _start_at
	rel["until"] = float(entry["until"]) - _start_at
	_rpc_override.rpc(rel)


func _bump(peer_id: int, key: String) -> void:
	var tally: Dictionary = _counts.get(peer_id, {})
	tally[key] = int(tally.get(key, 0)) + 1
	_counts[peer_id] = tally


## The one more window Redirect sticks on: not this one, not the one after it.
func _redirect_window(window: String, form: Dictionary) -> String:
	var after := _Form.next_window(form)
	for other: String in SERVING:
		if other != window and other != after:
			return other
	return SERVING[0] if SERVING[0] != window else SERVING[1]


## What the raid noticed, when the raid side (R2 chunks 2-3) can say.
func _raid_stats(peer_id: int) -> Dictionary:
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and director.has_method("raid_stats"):
		var got: Variant = director.call("raid_stats", peer_id)
		if typeof(got) == TYPE_DICTIONARY:
			return got
	return {}


# ---------------------------------------------------------------- requests (host)


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return Net.local_peer_id() if id == 0 else id


func _client_time(client_t: float) -> float:
	var now := Net.server_time()
	return clampf(client_t, now - Constants.ANNEX_GRACE, now)


func _inside(peer_id: int) -> bool:
	return _active and _roster.has(peer_id) and stage_of(peer_id) == STAGE_INSIDE


func _in_room(peer_id: int) -> bool:
	return _inside(peer_id) or (_active and _visitors.has(peer_id))


## Rate limit for one peer's asks of one kind.
func _allow(peer_id: int, kind: String, gap: float) -> bool:
	var key := "%d:%s" % [peer_id, kind]
	var now := Net.server_time()
	if now - float(_last_request.get(key, -100.0)) < gap:
		return false
	_last_request[key] = now
	return true


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_serve(window: String, client_t: float) -> void:
	if not Net.is_host():
		return
	var peer_id := _sender()
	if not _inside(peer_id) or not _forms.has(peer_id) or not Constants.ANNEX_WINDOWS.has(window):
		return
	var form: Dictionary = _forms[peer_id]
	var body := _player(peer_id)
	var counter := _window_spot(window, "Counter")
	if body == null or counter == Vector3.INF or _flat(body.global_position, counter) > Constants.ANNEX_COUNTER_REACH + Constants.ANNEX_REACH_SLACK:
		return
	var now := Net.server_time()
	var at := _client_time(client_t)
	if bool(form["approved"]):
		return
	if window == "D":
		# Closed, Window D says nothing at all (its clerk is asleep behind the blinds).
		var d_state := _Schedule.effective(_seed, "D", _t_at(at), _overrides)
		if int(d_state["state"]) == _Schedule.S.D_OPEN and not _d_used and not _Form.is_full(form):
			_d_used = true
			stats["window_d"] = int(stats["window_d"]) + 1
			_bump(peer_id, "window_d")
			# He spins round, winds up, and slams every box left, one KA-CHUNK and
			# one box's ink each, CLERK_VOLLEY_GAP apart (R2b: the box just changed).
			var count := (form["boxes"] as PackedStringArray).size() - int(form["stamped"])
			var first := now + Constants.ANNEX_VOLLEY_STAMP_AT + Constants.ANNEX_STAMP_HIT
			var end := first + float(maxi(count - 1, 0)) * Constants.CLERK_VOLLEY_GAP + Constants.ANNEX_VOLLEY_SECONDS
			_add_override({"kind": "volley", "w": "D", "at": now, "until": end, "peer": peer_id, "n": count})
			_add_override({"kind": "shut", "w": "D", "at": end, "until": now + 100000.0})
			_send_form(peer_id, _Form.stamp_all(form), first, "D")
		return
	if _Form.is_full(form):
		return
	var next := _Form.next_window(form)
	if window != next:
		if now < float(_wrong_until.get(peer_id, 0.0)) or _serving.has(window):
			return
		# Once per visit to that counter: he shakes his head and points, then
		# leaves you be until you've stepped away (R2b: it looped every 1.6 s).
		if str((_wrong_seen.get(peer_id, {}) as Dictionary).get("w", "")) == window:
			return
		# Only a clerk at his window can shake his head at you (R2c annex: one on his
		# break lit his lamp, folded his BACK IN 5 card and babbled from the nook).
		if not bool(_Schedule.effective(_seed, window, _t_at(at), _overrides)["looking"]):
			return
		_wrong_seen[peer_id] = {"w": window}
		_wrong_until[peer_id] = now + Constants.ANNEX_WRONG_WINDOW
		stats["wrong_windows"] = int(stats["wrong_windows"]) + 1
		_bump(peer_id, "wrong_window")
		_add_override({"kind": "wrong_window", "w": window, "at": now, "until": now + Constants.ANNEX_WRONG_WINDOW, "peer": peer_id, "right": next})
		return
	for item: Variant in _serving.values():
		if int((item as Dictionary)["peer"]) == peer_id:
			return
	var queue: Array = _queues.get(window, [])
	if _serving.has(window) or not bool(_Schedule.effective(_seed, window, _t_at(at), _overrides)["serving"]) or (not queue.is_empty() and int(queue[0]) != peer_id):
		if not queue.has(peer_id):
			queue.append(peer_id)
		_queues[window] = queue
		return
	queue.erase(peer_id)
	_queues[window] = queue
	_start_serve(peer_id, window, now)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_self_stamp(window: String, down: bool, client_t: float) -> void:
	if not Net.is_host():
		return
	var peer_id := _sender()
	if not down:
		if _holds.has(peer_id) and str((_holds[peer_id] as Dictionary)["kind"]) == "self_stamp":
			_holds.erase(peer_id)
		return
	if not _inside(peer_id) or not SERVING.has(window):
		return
	var body := _player(peer_id)
	var spot := _window_spot(window, "StampPad")
	if body == null or spot == Vector3.INF or _flat(body.global_position, spot) > Constants.ANNEX_STAMP_REACH + Constants.ANNEX_REACH_SLACK:
		return
	_holds[peer_id] = {"kind": "self_stamp", "window": window, "start": _client_time(client_t)}


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_bell(window: String) -> void:
	if not Net.is_host():
		return
	var peer_id := _sender()
	if not _in_room(peer_id) or not SERVING.has(window):
		return
	var body := _player(peer_id)
	var spot := _window_spot(window, "Bell")
	if body == null or spot == Vector3.INF or _flat(body.global_position, spot) > Constants.ANNEX_BELL_REACH + Constants.ANNEX_REACH_SLACK:
		return
	var now := Net.server_time()
	if now - float(_bell_last.get(window, -100.0)) < Constants.ANNEX_BELL_COOLDOWN:
		return
	_bell_last[window] = now
	_bell_count += 1
	stats["bells"] = int(stats["bells"]) + 1
	_bump(peer_id, "bell")
	var t := _t()
	var state := _Schedule.effective(_seed, window, t, _overrides)
	var s := int(state["state"])
	if s == _Schedule.S.BREAK or s == _Schedule.S.JAM:
		# From the copier it's the long way back (R2c annex).
		var walk := Constants.ANNEX_JAM_RETURN_WALK if s == _Schedule.S.JAM else Constants.ANNEX_RETURN_WALK
		_add_override({"kind": "hurry_back", "w": window, "at": now, "until": maxf(_abs(float(state["until"])), now + walk + Constants.ANNEX_OPEN.x), "bell": true, "peer": peer_id, "walk": walk})
	elif s == _Schedule.S.ASLEEP:
		_add_override({"kind": "wake", "w": window, "at": now, "until": maxf(_abs(float(state["until"])), now + Constants.ANNEX_WAKE_SECONDS + Constants.ANNEX_OPEN.x), "bell": true, "peer": peer_id})
	elif s == _Schedule.S.OPEN or s == _Schedule.S.TELEGRAPH or s == _Schedule.S.LUNCH_BITE or s == _Schedule.S.PEER_FORM:
		# PEER_FORM too: chunk 5's bell sits on the counter, so whoever rings it is
		# standing at his window, and a wrong form there has him shaking his head
		# already; the bell still sends him to his cabinet (R2 integration).
		# "One moment!": he turns to his filing cabinet; every third ring he turns back early.
		var turn := Constants.ANNEX_BELL_EARLY_AT if _bell_count % Constants.ANNEX_BELL_EARLY_EVERY == 0 else Constants.ANNEX_BELL_TURN
		_add_override({"kind": "cabinet", "w": window, "at": now, "until": now + turn, "bell": true, "peer": peer_id})
		var options: Array = NEIGHBOURS.get(window, [])
		if not options.is_empty():
			var neighbour := str(options[_bell_count % options.size()])
			var theirs := _Schedule.effective(_seed, neighbour, t, _overrides)
			if bool(theirs["looking"]) and int(theirs["state"]) != _Schedule.S.SERVING:
				_add_override({"kind": "lean", "w": neighbour, "at": now + 0.2, "until": now + turn, "toward": window})
	else:
		_add_override({"kind": "ding", "w": window, "at": now, "until": now, "bell": true, "peer": peer_id})


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_desk() -> void:
	if not Net.is_host():
		return
	var peer_id := _sender()
	if not _inside(peer_id) or not _forms.has(peer_id):
		return
	var form: Dictionary = _forms[peer_id]
	if bool(form["approved"]) or not _Form.is_full(form):
		return
	var desk := _marker("HeadDesk")
	var spot := desk.get_node_or_null("DeskSpot") as Node3D if desk != null else null
	var body := _player(peer_id)
	if spot == null or body == null or _flat(body.global_position, spot.global_position) > Constants.ANNEX_DESK_REACH + Constants.ANNEX_REACH_SLACK:
		return
	var head := _Schedule.effective(_seed, "head", _t(), _overrides)
	if int(head["state"]) != _Schedule.S.DESK or _big_holder != 0:
		return
	# Back in his chair first (R2c annex: he approved from the water cooler, and,
	# review, on his way back from taking the big stamp off someone).
	if _t() - _head_seated_since(head, _t()) < Constants.ANNEX_HEAD_SETTLE:
		return
	var now := Net.server_time()
	# He reads it, raises the big stamp, hesitates, slams: the form's APPROVED,
	# NICELY lands on the stamp's own KA-CHUNK (props/office_props.gd BigStamp).
	var slam := now + Constants.ANNEX_HEAD_READ + OfficeProps.BigStamp.slam_lands_after()
	_add_override({"kind": "approve", "w": "head", "at": now, "until": slam + 0.6, "peer": peer_id})
	_pending.append({"at": slam - Constants.ANNEX_INK_LEAD, "do": "approve_done", "peer": peer_id, "hit": slam})


## When the Head NICE BOY last set off for his chair (Annex time): his desk time's
## start, or the end of his latest walk off to take the big stamp back (a SPOTTED
## override drops him back into DESK with that segment's old start), whichever
## is later.
func _head_seated_since(head: Dictionary, t: float) -> float:
	var since := float(head["since"])
	for entry: Variant in _overrides:
		var o: Dictionary = entry
		if str(o.get("w", "")) != "head" or str(o.get("kind", "")) != "spotted":
			continue
		var until := float(o.get("until", 0.0))
		if until <= t:
			since = maxf(since, until)
	return since


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_big_stamp(op: String, target: int) -> void:
	if not Net.is_host():
		return
	var peer_id := _sender()
	if not _in_room(peer_id):
		return
	var now := Net.server_time()
	var body := _player(peer_id)
	var pad := _marker("HeadDesk/Pad")
	match op:
		"grab":
			if _big_holder != 0 or body == null or pad == null or _flat(body.global_position, pad.global_position) > Constants.ANNEX_DESK_REACH + Constants.ANNEX_HOLD_SLACK:
				return
			var head := _Schedule.effective(_seed, "head", _t(), _overrides)
			if bool(head["looking"]):
				return
			_big_holder = peer_id
			stats["big_stamps"] = int(stats["big_stamps"]) + 1
			_rpc_big_stamp.rpc(peer_id, now)
		"drop":
			if _big_holder == peer_id and body != null and pad != null and _flat(body.global_position, pad.global_position) <= Constants.ANNEX_DESK_REACH + Constants.ANNEX_LOOSE_SLACK:
				_host_return_stamp(now)
		"self", "friend":
			if _big_holder != peer_id:
				return
			var who := peer_id if op == "self" else target
			if not _inside(who) or not _forms.has(who) or bool(_forms[who]["approved"]):
				return
			var other := _player(who)
			if who != peer_id and (other == null or body == null or other.global_position.distance_to(body.global_position) > Constants.ANNEX_BIG_STAMP_REACH + Constants.ANNEX_HOLD_SLACK):
				return
			_bump(who, "big_stamp")
			stats["approved"] = int(stats["approved"]) + 1
			_rpc_big_slam.rpc(peer_id, who, now)
			# Raised in the holder's hands and slammed: the approval lands with it.
			_send_form(who, _Form.approve(_forms[who]), now + OfficeProps.BigStamp.slam_lands_after(Constants.ANNEX_BIG_STAMP_HOLDER_HESITATE), "big_stamp")


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_cosign(down: bool) -> void:
	if not Net.is_host():
		return
	var peer_id := _sender()
	if not down:
		if _holds.has(peer_id) and str((_holds[peer_id] as Dictionary)["kind"]) == "cosign":
			_holds.erase(peer_id)
		return
	if not _visitors.has(peer_id) or bool(_cosigned.get(peer_id, false)):
		return
	_holds[peer_id] = {"kind": "cosign", "start": Net.server_time()}


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_tray() -> void:
	if not Net.is_host():
		return
	var peer_id := _sender()
	if not _inside(peer_id):
		return
	var body := _player(peer_id)
	var tray := _marker("OutgoingTray")
	var turnstile := _marker("Turnstile")
	if body == null or tray == null:
		return
	var near_tray := _flat(body.global_position, tray.global_position) <= Constants.ANNEX_TRAY_REACH + Constants.ANNEX_HOLD_SLACK
	var near_gate := turnstile != null and _flat(body.global_position, turnstile.global_position) <= Constants.ANNEX_GATE_REACH + Constants.ANNEX_REACH_SLACK
	# Out of reach (as the host sees them) costs no turn of the rate limit.
	if (not near_tray and not near_gate) or not _allow(peer_id, "tray", Constants.ANNEX_TRAY_ASK_GAP):
		return
	var form: Dictionary = _forms.get(peer_id, {})
	var now := Net.server_time()
	if bool(form.get("approved", false)):
		if not bool(form.get("dropped", false)):
			form = form.duplicate(true)
			form["dropped"] = true
			_send_form(peer_id, form, now, "tray")
		_rpc_turnstile.rpc(peer_id, now, true)
	elif near_gate:
		stats["bounces"] = int(stats["bounces"]) + 1
		_rpc_turnstile.rpc(peer_id, now, false)


## A visitor door was used (net/annex/visitor_door.gd, on the user's own peer).
func request_visit(door_name: String) -> void:
	_rpc_request_visit.rpc_id(1, door_name)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_visit(door_name: String) -> void:
	if not Net.is_host() or not _active:
		return
	var peer_id := _sender()
	if _roster.has(peer_id) or _visitors.has(peer_id) or Net.player_zone(peer_id) == Net.Zone.BORDER:
		return
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and bool(director.call("is_captured", peer_id)):
		return
	var door: Node3D = null
	for node: Node in _doors:
		if is_instance_valid(node) and str(node.name) == door_name:
			door = node as Node3D
	var body := _player(peer_id)
	if door == null or body == null or _flat(body.global_position, door.global_position) > Constants.ANNEX_DOOR_REACH + Constants.ANNEX_LOOSE_SLACK:
		return
	var home := {"zone": Net.player_zone(peer_id), "at": door.call("out_transform")}
	_rpc_door_iris.rpc_id(peer_id, Net.server_time())
	# Through the door behind the iris (R2 chunk 1) when there is one, else a cut.
	var wait := Constants.ANNEX_DOOR_IRIS_WAIT if get_tree().get_first_node_in_group("iris") != null else 0.0
	_pending.append({"at": Net.server_time() + wait, "do": "visit", "peer": peer_id, "home": home})


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_leave() -> void:
	if not Net.is_host():
		return
	var peer_id := _sender()
	if not _visitors.has(peer_id) or not _allow(peer_id, "leave", Constants.ANNEX_LEAVE_ASK_GAP):
		return
	# Out the way they came in: through the door-swing iris, the move behind it
	# (R2b: a hard cut of 983 m).
	var now := Net.server_time()
	_rpc_door_iris.rpc_id(peer_id, now)
	var wait := Constants.ANNEX_DOOR_IRIS_WAIT if get_tree().get_first_node_in_group("iris") != null else 0.0
	_pending.append({"at": now + wait, "do": "visitor_out", "peer": peer_id})


# ---------------------------------------------------------------- every peer: the messages


@rpc("authority", "call_local", "reliable")
func _rpc_begin(trip_id: int, roster_in: Array, seed_in: int, start_at: float, forms: Dictionary, _windows: Array, _quirk_windows: Array, _d_at: float, close_at: float) -> void:
	_rpc_begin_local(trip_id, roster_in, seed_in, start_at, forms, close_at)
	# Free players learn who was taken there, a line per rider.
	if not _roster.has(Net.local_peer_id()):
		for peer_id: int in _roster:
			_quip("teammate_inside", [_name_of(peer_id)], peer_id)


## stages_in: a late joiner's copy of the host's stages (apply_snapshot); empty at a begin.
func _rpc_begin_local(trip_id: int, roster_in: Array, seed_in: int, start_at: float, forms: Dictionary, close_at: float, stages_in: Dictionary = {}) -> void:
	_active = true
	_trip_id = trip_id
	_seed = seed_in
	_start_at = start_at
	_close_at = close_at
	_roster.clear()
	_forms.clear()
	_stages.clear()
	_overrides.clear()
	_visitors.clear()
	_shown.clear()
	_big_holder = 0
	_closing = false
	_urgent_shown = false
	_rows_off = 0
	_serves_shown = 0
	_signs.clear()
	_icons = _Schedule.window_icons(_seed)
	_quirks = _Schedule.quirks(_seed)
	_d_open_at = _Schedule.d_open_at(_seed)
	for entry: Variant in roster_in:
		var peer_id := int(entry)
		_roster.append(peer_id)
		_forms[peer_id] = (forms.get(peer_id, forms.get(str(peer_id), {})) as Dictionary).duplicate(true)
		var given: Variant = stages_in.get(peer_id, stages_in.get(str(peer_id), null))
		_stages[peer_id] = (given as Dictionary).duplicate(true) if given is Dictionary else {"stage": STAGE_WALK, "joined_at": start_at}
	_ensure_set()
	_park_old_van(true)
	var sheet := _set_node("CoSignSheet")
	if sheet != null:
		sheet.remove_meta("signed_by_me")
	_dress_set()
	_open_doors()
	for peer_id: int in _roster:
		if stage_of(peer_id) == STAGE_WALK:
			_queue_walk(peer_id, float((_stages[peer_id] as Dictionary).get("joined_at", start_at)))


@rpc("authority", "call_local", "reliable")
func _rpc_join(peer_id: int, form: Dictionary, at: float) -> void:
	if not _roster.has(peer_id):
		_roster.append(peer_id)
	_forms[peer_id] = form.duplicate(true)
	_stages[peer_id] = {"stage": STAGE_WALK, "joined_at": at}
	_greeter_walk(at)
	_queue_walk(peer_id, at)
	if not _roster.has(Net.local_peer_id()):
		_quip("teammate_inside", [_name_of(peer_id)], peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_stage(peer_id: int, stage: String, at: float) -> void:
	var entry: Dictionary = _stages.get(peer_id, {"joined_at": at})
	if str(entry.get("stage", "")) == stage:
		return
	entry["stage"] = stage
	_stages[peer_id] = entry
	if stage != STAGE_WALK:
		_end_walk(peer_id)
	if stage == STAGE_INSIDE:
		# The hand-over (R2b: the clipboard popped into your hand in one frame):
		# the Greeter steps aside, turns to you and holds Form 27-B out; it leaves
		# his hands and rises into yours with the punch card's click, then he goes
		# back to his post.
		var handoff := at + Constants.ANNEX_FORM_HANDOFF_AT
		var offer := {}
		var threshold := _marker("Threshold")
		var rider := _player(peer_id)
		if threshold != null and _set != null:
			offer["to"] = _set.to_global(_set.to_local(threshold.global_position) + Constants.ANNEX_GREETER_OFFER_SPOT)
		if rider != null:
			offer["face"] = rider.global_position
			# Held out from past arm's length, not from in their face (review: his
			# sunglasses filled a third of the view at the hand-over).
			if offer.has("to"):
				var to: Vector3 = offer["to"]
				var gap := Vector3(to.x - rider.global_position.x, 0.0, to.z - rider.global_position.z)
				if gap.length() < Constants.ANNEX_GREETER_OFFER_GAP:
					var dir := gap.normalized() if gap.length() > 0.05 else (threshold.global_basis.x if threshold != null else Vector3.RIGHT)
					offer["to"] = Vector3(rider.global_position.x, to.y, rider.global_position.z) + dir * Constants.ANNEX_GREETER_OFFER_GAP
		_staff_play("Greeter", &"greeter_offer", at, offer)
		_later(handoff, func() -> void: _sound_at("punch_card", _staff_pos("Greeter")))
		_later(at + Constants.ANNEX_GREETER_BACK_AT, func() -> void:
			if _active:
				_staff_play("Greeter", &"walk_to", at + Constants.ANNEX_GREETER_BACK_AT, {}))
		if peer_id == Net.local_peer_id():
			_show_form(handoff)
			if not _first_visit_quipped:
				_first_visit_quipped = true
				_quip("first_visit", [])


@rpc("authority", "call_local", "reliable")
func _rpc_override(entry: Dictionary) -> void:
	_overrides.append(entry)
	_overrides.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["at"]) < float(b["at"]))
	# Old ones that ended long ago can go.
	var t := _t()
	while _overrides.size() > 64 and float((_overrides[0] as Dictionary)["until"]) < t - 30.0:
		_overrides.pop_front()
	if str(entry.get("kind", "")) == "wrong_window" and int(entry.get("peer", 0)) == Net.local_peer_id():
		# He's shaken his head at us here: no more asking till we step off (R2b).
		_asked_wrong = str(entry.get("w", ""))
	_present_override(entry)


## at: when the change lands (a stamp's ink lands on its KA-CHUNK, so it can be
## a little ahead). The stamps that made it play their own KA-CHUNK on that
## frame (a window's, Window D's volley, the big stamp); only a co-sign's distant
## one and a smudge are played from here (R2b).
@rpc("authority", "call_local", "reliable")
func _rpc_form(peer_id: int, form: Dictionary, at: float, source: String) -> void:
	var before: Dictionary = _forms.get(peer_id, {})
	_forms[peer_id] = form.duplicate(true)
	var where := _form_sound_spot(source, peer_id)
	var gained := int(form.get("stamped", 0)) > int(before.get("stamped", 0)) or (bool(form.get("approved", false)) and not bool(before.get("approved", false)))
	if gained and (source == "cosign" or source == ""):
		_later(at, func() -> void: _sound_at("stamp_kachunk", where, -4.0 if source == "cosign" else 0.0))
	elif source == "smudge":
		_sound_at("stamp_smudge", where)
	if source == "tray":
		# The form flies out of your hand into the OUTGOING tray, on every peer.
		var tray := _set_node("OutgoingTray")
		var body := _player(peer_id)
		if tray != null and tray.has_method("set_state"):
			tray.call("set_state", &"receive", at, {"from": body.global_position + Vector3(0.0, 1.2, 0.0)} if body != null else {})
	if peer_id == Net.local_peer_id():
		if SERVING.has(source) and _dwell_window == source:
			# Served here: no asking this window again till we step off its spot.
			_asked_wrong = source
		_update_form_view(at, Constants.CLERK_VOLLEY_GAP if source == "D" else 0.0)


@rpc("authority", "call_local", "reliable")
func _rpc_stamped(peer_id: int, window: String, at: float, ok: bool) -> void:
	var piece := _set_node("Windows/%s" % window)
	if piece != null and piece.has_method("set_state"):
		var slam: Dictionary = {}
		if piece.has_method("borrow"):
			# It comes down on the form in their hand: yours already there; anyone
			# else's shoots out of the hatch to them as it slams (R2c annex).
			if peer_id != Net.local_peer_id() or not bool(piece.call("borrowed")):
				var body := _player(peer_id)
				piece.call("borrow", func() -> Vector3: return body.global_transform * Constants.ANNEX_BORROW_CARRY if is_instance_valid(body) else Vector3.INF, at, true, false)
				# Their hands on it, as everyone else sees them (review: it slammed
				# in front of them with no hand on it): _hands_on_borrowed.
				if peer_id != Net.local_peer_id():
					_remote_borrows[peer_id] = window
			slam["lift"] = Constants.ANNEX_BORROW_SLAM_LIFT
		piece.call("set_state", &"stamp_down", at, slam)
	if peer_id == Net.local_peer_id():
		# Done: letting go of interact now doesn't slam it a second time (R2b).
		_hold_kind = ""
	if ok:
		return
	# Down on the wrong box: a dry thump, no ink.
	_sound_at("turnstile_clunk", _window_spot(window, "StampPad"), -6.0)


@rpc("authority", "call_local", "reliable")
func _rpc_big_stamp(holder: int, at: float) -> void:
	_big_holder = holder
	_apply_big_stamp(holder, at)
	if holder == 0:
		_sound_at("stamp_smudge", _set_point("HeadDesk/Pad"), -6.0)


## The holder raises the big stamp and slams it: its own KA-CHUNK and party toot
## play from it on the frame it lands (R2b: three sounds played here and from the
## form as well, the approval cue twice).
@rpc("authority", "call_local", "reliable")
func _rpc_big_slam(_holder: int, _target: int, at: float) -> void:
	var stamp := _set_node("HeadDesk/BigStamp")
	if stamp != null and stamp.has_method("set_state"):
		stamp.call("set_state", &"slam", at, {"hesitate": Constants.ANNEX_BIG_STAMP_HOLDER_HESITATE})


@rpc("authority", "call_local", "reliable")
func _rpc_turnstile(peer_id: int, at: float, open: bool) -> void:
	var turnstile := _set_node("Turnstile")
	if turnstile == null:
		return
	# Its sounds are its own (R2b): the clunk of a bounce, and one ratchet clack
	# when someone pushes the arms round, not one per unlock.
	if turnstile.has_method("set_state"):
		if open:
			# Unlocked for the opener's push only, for as long as their pass takes.
			turnstile.call("set_state", &"open", at, {"seconds": Constants.ANNEX_TURNSTILE_OPEN + Constants.ANNEX_TURNSTILE_PASS_SLACK, "who": [str(peer_id)]})
		else:
			turnstile.call("set_state", &"bounce", at)
	if peer_id == Net.local_peer_id():
		_gate_asked = true
	if not open or peer_id != Net.local_peer_id():
		return
	# Only the opener's own body passes: their own peer simulates it (_step_turnstile).
	_turnstile_open_until = maxf(_turnstile_open_until, Net.server_time() + Constants.ANNEX_TURNSTILE_OPEN + Constants.ANNEX_TURNSTILE_PASS_SLACK)
	_set_form_shown(false)


@rpc("authority", "call_local", "reliable")
func _rpc_cosigned(visitor: int, at: float) -> void:
	var sheet := _set_node("CoSignSheet")
	if sheet != null and sheet.has_method("set_state"):
		sheet.call("set_state", &"signing", at)
	_sound_at("pen_squeak", _set_point("CoSignSheet"))
	if visitor == Net.local_peer_id():
		_hold_kind = ""
		if sheet != null:
			sheet.set_meta("signed_by_me", true)


@rpc("authority", "call_local", "reliable")
func _rpc_visitors(list: Array) -> void:
	_visitors.clear()
	for entry: Variant in list:
		_visitors.append(int(entry))


@rpc("authority", "call_local", "reliable")
func _rpc_closing(at: float, forms: Dictionary) -> void:
	_closing = true
	for key: Variant in forms.keys():
		_forms[int(key)] = (forms[key] as Dictionary).duplicate(true)
	for window: String in Constants.ANNEX_WINDOWS:
		_overrides.append({"kind": "closing", "w": window, "at": at - _start_at, "until": at - _start_at + 100000.0})
	_sound("closing_bell")
	# The turnstile turns for everyone now.
	var turnstile := _set_node("Turnstile")
	if turnstile != null and turnstile.has_method("set_state"):
		var who: Array = []
		for peer_id: int in _roster:
			who.append(str(peer_id))
		turnstile.call("set_state", &"open", at, {"who": who})
	# The rush (R2b): every hatch slams AFTER HOURS stamps in a volley, every
	# clerk pumping (AFTER_HOURS), your empty boxes inking one per slam; AFTER
	# HOURS lands across your form; then the blinds drop and the rows clunk off.
	var rush := at + Constants.ANNEX_CLOSING_RUSH_AT
	# The hatches slam at least once per empty box on any form closing approves,
	# so no box inks after they've stopped (R2b review: 6-box forms inked silently).
	var slams := Constants.ANNEX_CLOSING_SLAMS
	for key: Variant in forms.keys():
		var each: Dictionary = forms[key]
		if bool(each.get("after_hours", false)):
			slams = maxi(slams, (each["boxes"] as PackedStringArray).size() - int(each["stamped"]))
	var rush_end := rush + Constants.ANNEX_STAMP_HIT + float(slams) * Constants.ANNEX_CLOSING_RUSH_GAP
	for window: String in Constants.ANNEX_WINDOWS:
		var piece := _set_node("Windows/%s" % window)
		if piece != null and piece.has_method("set_state"):
			if SERVING.has(window):
				piece.call("set_state", &"stamp_down", rush, {"volley": slams, "gap": Constants.ANNEX_CLOSING_RUSH_GAP, "lift": Constants.ANNEX_RUSH_LIFT})
			piece.call("set_state", &"blind_down", rush_end + Constants.ANNEX_BLINDS_AFTER_RUSH)
	_staff_play("Janitor", &"janitor_mop", at, {"path": _path_points("JanitorPath")})
	var mine: Dictionary = _forms.get(Net.local_peer_id(), {})
	if not mine.is_empty():
		_update_form_view(rush + Constants.ANNEX_STAMP_HIT, Constants.ANNEX_CLOSING_RUSH_GAP)
		# AFTER HOURS only lands on a form this closing approved; one approved
		# earlier is already stamped (R2b review: a KA-CHUNK on the bell, no stamp).
		if bool(mine.get("after_hours", false)) and _form_view != null and is_instance_valid(_form_view) and _form_view.has_method("approved_at"):
			var slam := float(_form_view.call("approved_at"))
			_later(slam, func() -> void:
				if _active:
					_sound("stamp_kachunk"))


@rpc("authority", "call_local", "reliable")
func _rpc_through(peer_id: int, at: float, seconds: float, by_closing: bool, lines: PackedStringArray, total: String) -> void:
	var entry: Dictionary = _stages.get(peer_id, {})
	entry["stage"] = STAGE_THROUGH
	entry["out_at"] = at
	entry["closing"] = by_closing
	_stages[peer_id] = entry
	rider_through_turnstile.emit(peer_id)
	if peer_id != Net.local_peer_id():
		return
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if by_closing and shuttle != null and shuttle.has_method("host_start_return"):
		# Let out at closing time you're seated behind the shut door (R2c van): the
		# slip prints in your hands in the seat once it has opened.
		# The clipboard goes once the door has swung shut over it.
		_later(at + Constants.ANNEX_DOOR_IRIS_WAIT, _hide_form)
		at += Constants.VAN_CLOSING_RECEIPT_AFTER
		_later(at, func() -> void: _show_receipt(lines, total, at))
		var kind_late := "closing"
		var slip_late := Constants.RECEIPT_LINE_SECONDS * float(lines.size() + 11) + Constants.ANNEX_RECEIPT_SECONDS + Constants.ANNEX_RECEIPT_POCKET
		if ResourceLoader.exists(RECEIPT_SCRIPT):
			slip_late = float(load(RECEIPT_SCRIPT).call("duration", lines, Constants.ANNEX_RECEIPT_SECONDS))
		_later(at + slip_late, func() -> void: _quip(kind_late, []))
		return
	# Out into daylight: the stinger (chunk 5's cue_hooks plays it when it listens).
	if rider_through_turnstile.get_connections().is_empty():
		var music := get_tree().get_first_node_in_group("music_director")
		if music != null:
			music.call("stinger", &"st_made_it")
	_hide_form()
	_show_receipt(lines, total, at)
	# The quip waits until the slip is pocketed: a caption over it hid its total (R2b).
	var slip_seconds := Constants.RECEIPT_LINE_SECONDS * float(lines.size() + 11) + Constants.ANNEX_RECEIPT_SECONDS + Constants.ANNEX_RECEIPT_POCKET
	if ResourceLoader.exists(RECEIPT_SCRIPT):
		slip_seconds = float(load(RECEIPT_SCRIPT).call("duration", lines, Constants.ANNEX_RECEIPT_SECONDS))
	var after_slip := at + slip_seconds
	var kind := "closing" if by_closing else ("fast" if seconds < Constants.ANNEX_FAST_SECONDS else "")
	if kind != "":
		_later(after_slip, func() -> void: _quip(kind, []))


@rpc("authority", "call_local", "reliable")
func _rpc_out(peer_id: int) -> void:
	var entry: Dictionary = _stages.get(peer_id, {})
	entry["stage"] = STAGE_OUT
	_stages[peer_id] = entry


@rpc("authority", "call_local", "reliable")
func _rpc_left(peer_id: int) -> void:
	_end_walk(peer_id)
	_roster.erase(peer_id)
	_visitors.erase(peer_id)
	_forms.erase(peer_id)
	_stages.erase(peer_id)
	if _big_holder == peer_id:
		_big_holder = 0
		_apply_big_stamp(0, Net.server_time())


@rpc("authority", "call_local", "reliable")
func _rpc_end() -> void:
	for peer_id: Variant in _walk_anchors.keys():
		_end_walk(int(peer_id))
	_active = false
	_roster.clear()
	_visitors.clear()
	_forms.clear()
	_stages.clear()
	_overrides.clear()
	_big_holder = 0
	_closing = false
	_hide_form()
	_apply_big_stamp(0, Net.server_time())
	_dim_room(Net.server_time())
	_signs.clear()
	_close_doors()
	_reset_set()
	_park_old_van(false)
	_turnstile_open_until = -1.0
	_step_turnstile()
	stats["ended"] = int(stats["ended"]) + 1
	annex_ended.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(snap: Dictionary) -> void:
	apply_snapshot(snap)


## To one player: put yourself here (a visitor back at their door).
@rpc("authority", "call_local", "reliable")
func _rpc_place(at: Transform3D) -> void:
	var me := _player(Net.local_peer_id())
	if me != null and me.has_method("apply_network_teleport"):
		me.call("apply_network_teleport", at)


## To one player: the closing door-swing iris (R2 chunk 1's group "iris").
@rpc("authority", "call_local", "reliable")
func _rpc_door_iris(at: float) -> void:
	var iris := get_tree().get_first_node_in_group("iris")
	if iris != null and iris.has_method("close"):
		# Shut over ANNEX_IRIS_CLOSE, the host's move lands behind it at
		# ANNEX_DOOR_IRIS_WAIT, open again at ANNEX_IRIS_OPEN_AT: all server time,
		# so lag shifts none of it.
		iris.call("close", at, Constants.ANNEX_IRIS_CLOSE, &"door")
		if iris.has_method("open"):
			iris.call("open", at + Constants.ANNEX_IRIS_OPEN_AT)


## To one player let out at closing time (R2c van): the door swings shut over the
## lobby and stays shut; the Shuttle seats them behind it and opens it on the seat
## (shuttle.gd _local_rider_beats), one iris from the lobby to the ride home.
@rpc("authority", "call_local", "reliable")
func _rpc_closing_iris(at: float) -> void:
	var iris := get_tree().get_first_node_in_group("iris")
	if iris != null and iris.has_method("close"):
		iris.call("close", at, Constants.ANNEX_IRIS_CLOSE, &"door")
		# Never left shut: if no seat takes them (the van full, gone), it opens anyway.
		# The seat's own iris boarding carries the shut over and cancels this.
		if iris.has_method("open"):
			iris.call("open", at + Constants.VAN_CLOSING_IRIS_CAP)


func _on_player_joined(peer_id: int) -> void:
	if Net.is_host() and _active and peer_id != Net.local_peer_id():
		_rpc_snapshot.rpc_id(peer_id, snapshot())


func _on_player_left(peer_id: int) -> void:
	_heat_at_catch.erase(peer_id)
	if not Net.is_host() or not _active:
		return
	_holds.erase(peer_id)
	for window: Variant in _queues.keys():
		(_queues[window] as Array).erase(peer_id)
	for window: Variant in _serving.keys():
		if int((_serving[window] as Dictionary)["peer"]) == peer_id:
			_serving.erase(window)
	_visitor_home.erase(peer_id)
	if _roster.has(peer_id) or _visitors.has(peer_id):
		_rpc_left.rpc(peer_id)
	if _roster.is_empty() and _visitors.is_empty():
		_rpc_end.rpc()
		return
	_maybe_return()


# ---------------------------------------------------------------- every peer: presentation


func _t() -> float:
	return Net.server_time() - _start_at


func _t_at(at: float) -> float:
	return at - _start_at


func _urgent_at() -> float:
	return (_close_at - _start_at) - (Constants.ANNEX_CAP_SECONDS - Constants.ANNEX_URGENT_AT)


func _abs(t_value: float) -> float:
	return _start_at + t_value


## Every peer (world.get_spawn_transform): the set's markers exist before a zone
## move to one of them, even when that move arrives ahead of the begin.
func ensure_set() -> void:
	if _set == null or not is_instance_valid(_set):
		_ensure_set()


## The set: chunk 5's AnnexSet when it's there, else the grey box.
func _ensure_set() -> void:
	var zone := get_parent().get_node_or_null("BorderZone") as Node3D
	if zone == null:
		return
	# The world builds the set over its first frames (levels/build_queue.gd):
	# a visit that comes sooner gets the rest of the build now.
	var built := zone.get_node_or_null("AnnexSet")
	if built == null or not built.has_meta("built"):
		preload("res://levels/build_queue.gd").finish(get_tree())
	_set = zone.get_node_or_null("AnnexSet") as Node3D
	if _set == null and not ResourceLoader.exists(SET_SCRIPT):
		_set = _Greybox.build(zone, _seed)
	if _set != null:
		_set.add_to_group("annex_set")


func _dress_set() -> void:
	if _set == null:
		return
	if ResourceLoader.exists(SET_SCRIPT) and not bool(_set.get_meta("greybox", false)):
		var script: Script = load(SET_SCRIPT)
		if script.has_method("apply_run"):
			# The run's one looks table: the plaques, the floor lines and the
			# clipboard's boxes all draw from it (R2b; before, the set got the
			# window letters as icons and its own colors).
			var looks := _run_looks()
			var ordered: Array = []
			for window: String in SERVING:
				ordered.append(looks[window])
			script.call("apply_run", _set, ordered)
	else:
		_Greybox.apply_run(_set, _icons)
	# A new day at the counters: last closing's blinds are up again (R2b: they
	# stayed down through the next visit), already up, without a rattle.
	for window: String in SERVING:
		var piece := _set.get_node_or_null("Windows/%s" % window)
		if piece != null and piece.has_method("set_state") and piece.get("blind_down") == true:
			piece.call("set_state", &"blind_up", _start_at - 10.0)
	var lines := _set.get_node_or_null("LightRows")
	if lines != null:
		for row: Node in lines.get_children():
			if row.has_method("set_state"):
				row.call("set_state", &"on", _start_at)
	var clock := _set.get_node_or_null("WallClock")
	if clock != null and clock.has_method("set_speed"):
		clock.call("set_speed", 1.0)
	var entrance := _set.get_node_or_null("Entrance")
	if entrance != null and entrance.has_method("set_state"):
		# The doors stay open: nobody is kept in, the turnstile is the way home.
		entrance.call("set_state", &"open", _start_at)
	_greeter_walk(_start_at)


## The run's looks, one table for the room and the clipboard (R2b): each serving
## window's pictogram (seeded, annex_schedule.gd) in the one color that pictogram
## always wears (Constants.ANNEX_ICON_COLORS). The grey box keeps its own colors.
func _run_looks() -> Dictionary:
	var greybox := _set != null and is_instance_valid(_set) and bool(_set.get_meta("greybox", false))
	var out := {}
	for window: String in SERVING:
		var icon := str(_icons.get(window, ""))
		var color: Color = _Greybox.window_color(window) if greybox else Constants.ANNEX_ICON_COLORS.get(icon, _Greybox.window_color(window))
		out[window] = {"icon": icon, "icon_id": icon, "color": color}
	return out


func _reset_set() -> void:
	if _set == null or not is_instance_valid(_set):
		return
	for window: String in Constants.ANNEX_WINDOWS:
		var piece := _set.get_node_or_null("Windows/%s" % window)
		if piece != null and piece.has_method("set_state"):
			piece.call("set_state", &"clock_sign_off", Net.server_time())
			piece.call("set_state", &"blind_down" if window == "D" else &"lamp_off", Net.server_time())
	# Locked again for the next visit (R2b review: closing left it turning for anyone).
	var turnstile := _set.get_node_or_null("Turnstile")
	if turnstile != null and turnstile.has_method("set_state"):
		turnstile.call("set_state", &"closed", Net.server_time())
	var staff := _set.get_node_or_null("Staff")
	if staff != null:
		for member: Node in staff.get_children():
			if member.has_method("play"):
				member.call(STAFF_PLAY, &"counter_idle", Net.server_time(), {})


func _greeter_walk(at: float) -> void:
	# He waves the riders over from the doors, then leads them in.
	_staff_play("Greeter", &"wave_up", at, {"stay": true})
	_later(at + Constants.ANNEX_WALK_LEAD_DELAY, func() -> void:
		if _active:
			_staff_play("Greeter", &"greeter_lead", at + Constants.ANNEX_WALK_LEAD_DELAY, {"path": _path_points("GreeterPath")})
			_sound_at("door_chime", _set_point("Entrance")))


## Every peer: a rider's walk-in starts a moment after the begin (the zone move
## that puts them at the curb arrives first), staged behind its anchor.
func _queue_walk(peer_id: int, joined_at: float) -> void:
	_later(joined_at + Constants.ANNEX_WALK_STAGE_DELAY, func() -> void:
		if _active and stage_of(peer_id) == STAGE_WALK:
			_start_walk(peer_id, joined_at))


func _start_walk(peer_id: int, joined_at: float) -> void:
	var body := _player(peer_id)
	var path := _walk_path()
	if body == null or not body.has_method("set_staged") or path.size() < 2 or _walk_anchors.has(peer_id):
		return
	var anchor := Node3D.new()
	anchor.name = "Walk%d" % peer_id
	add_child(anchor)
	anchor.set_meta("joined_at", joined_at)
	anchor.set_meta("path", path)
	_place_walk_anchor(anchor)
	var index := maxi(_roster.find(peer_id), 0)
	var lateral := -0.45 if index % 2 == 0 else 0.45
	var behind := 0.9 + float(floori(index / 2.0)) * 1.1
	body.call("set_staged", anchor, Transform3D(Basis.IDENTITY, Vector3(lateral, 0.0, behind)), Constants.STAGE_BLEND_DEFAULT, &"walk_behind")
	if peer_id == Net.local_peer_id() and body.has_method("set_control_lock"):
		body.call("set_control_lock", &"stage_walk", true)
	_walk_anchors[peer_id] = anchor


func _end_walk(peer_id: int) -> void:
	var anchor: Node3D = _walk_anchors.get(peer_id, null)
	_walk_anchors.erase(peer_id)
	var body := _player(peer_id)
	if body != null and anchor != null and body.has_method("clear_staged"):
		body.call("clear_staged")
	if body != null and peer_id == Net.local_peer_id() and body.has_method("set_control_lock"):
		body.call("set_control_lock", &"stage_walk", false)
	if anchor != null and is_instance_valid(anchor):
		anchor.queue_free()


## Curb, doors, threshold: the walk-in's line.
func _walk_path() -> Array:
	var out: Array = []
	for marker: String in ["AnnexCurb", "Entrance", "Threshold"]:
		var at := _set_point(marker)
		if at != Vector3.INF:
			out.append(Vector3(at.x, at.y, at.z))
	# Riders walk up to 2 m behind the anchor (_start_walk); started on the curb
	# marker, the last of them stood inside the Courtesy Shuttle's side, parked
	# right there. The line starts as far up the walk as the deepest of them, so
	# nobody is placed further out than the curb (R2 integration).
	if out.size() >= 2:
		var deepest := 0.9 + float(floori(maxi(_roster.size() - 1, 0) / 2.0)) * 1.1
		var first: Vector3 = out[0]
		var second: Vector3 = out[1]
		out[0] = first + (second - first).normalized() * minf(deepest, first.distance_to(second) * 0.8)
	return out


## Where a walk anchor is now: eased along its line by the server clock,
## facing the way it goes. The same on every peer.
func _place_walk_anchor(anchor: Node3D) -> void:
	var path: Array = anchor.get_meta("path")
	var p := clampf((Net.server_time() - float(anchor.get_meta("joined_at"))) / Constants.ANNEX_GREETER_WALK, 0.0, 1.0)
	p = p * p * (3.0 - 2.0 * p)
	var total := 0.0
	for index: int in range(1, path.size()):
		total += (path[index] as Vector3).distance_to(path[index - 1])
	var want := p * total
	var at: Vector3 = path[0]
	var heading := Vector3.FORWARD
	for index: int in range(1, path.size()):
		var a: Vector3 = path[index - 1]
		var b: Vector3 = path[index]
		var length := a.distance_to(b)
		heading = Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		if want <= length or index == path.size() - 1:
			at = a.lerp(b, clampf(want / maxf(length, 0.001), 0.0, 1.0))
			break
		want -= length
	anchor.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP), at)


func _physics_process(_delta: float) -> void:
	_keep_walking()
	for anchor: Variant in _walk_anchors.values():
		if is_instance_valid(anchor):
			_place_walk_anchor(anchor as Node3D)


## Every peer (P1 catch, audit r3): every rider still in the walk-in is on it. A
## second rider stepping down from the Shuttle after the walk began was let go by
## the van's own unstaging (or wasn't there yet when it began) and stood on the
## forecourt, then got the clipboard out there. Off their walk, they're put back
## on it, a fresh one from where they stand behind the Greeter's line.
func _keep_walking() -> void:
	if not _active:
		return
	var now := Net.server_time()
	for peer_id: int in _roster:
		if stage_of(peer_id) != STAGE_WALK:
			continue
		var joined := float((_stages.get(peer_id, {}) as Dictionary).get("joined_at", now))
		if now < joined + Constants.ANNEX_WALK_STAGE_DELAY:
			continue
		var body := _player(peer_id)
		if body == null or Net.player_zone(peer_id) != Net.Zone.BORDER:
			continue
		var anchor: Node3D = _walk_anchors.get(peer_id, null)
		if anchor != null and is_instance_valid(anchor) and _on_anchor(body, anchor):
			continue
		# Held by something else (still in a van seat, on the van's step down): it
		# lets go first.
		var stage_body := body.get_node_or_null("StageBody")
		if stage_body == null or bool(stage_body.call("is_staged")):
			continue
		if anchor != null:
			_walk_anchors.erase(peer_id)
			if is_instance_valid(anchor):
				anchor.queue_free()
		# Late: their own walk from the start of the line, from now.
		_start_walk(peer_id, joined if now - joined < Constants.ANNEX_WALK_STAGE_DELAY * 2.0 else now)


## Host (P1 catch, audit r3): a rider is through the doors (the clipboard comes)
## once their body is at the threshold, or ANNEX_WALK_LATE_MAX after the walk
## should have ended, whatever held them up.
func _walked_in(peer_id: int, walked: float) -> bool:
	if walked >= Constants.ANNEX_GREETER_WALK + Constants.ANNEX_WALK_LATE_MAX:
		return true
	var body := _player(peer_id)
	var threshold := _set_point("Threshold")
	if body == null or threshold == Vector3.INF:
		return true
	# Where the rider's own peer has them (the owner stages its own body on the
	# walk and the position replicates): this peer's drawn copy may still be easing
	# in from wherever it last drew them.
	return _flat(body.global_position, threshold) <= Constants.ANNEX_INSIDE_REACH


func _on_anchor(body: Node3D, anchor: Node3D) -> bool:
	var stage_body := body.get_node_or_null("StageBody")
	return stage_body != null and stage_body.has_method("staged_anchor") and stage_body.call("staged_anchor") == anchor


## The room, every frame: each window's clerk, lamp and blind from its effective
## state, the head's desk routine, Window D, urgency and closing.
func _present(_delta: float) -> void:
	_step_turnstile()
	if _set == null or not is_instance_valid(_set):
		_ensure_set()
		if _set == null:
			return
	var t := _t()
	var now := Net.server_time()
	for window: String in Constants.ANNEX_WINDOWS + ["head"]:
		var state := _Schedule.effective(_seed, window, t, _overrides)
		var key := "%d@%.3f" % [int(state["state"]), float(state["since"])]
		if str(_shown.get(window, "")) == key:
			continue
		_shown[window] = key
		_show_state(window, state)
	if urgent() and not _urgent_shown:
		_urgent_shown = true
		var clock := _set.get_node_or_null("WallClock")
		if clock != null and clock.has_method("set_speed"):
			clock.call("set_speed", 8.0)
		_set_rows(&"flicker", now)
	if _closing:
		# The rows clunk off from the back of the room, ANNEX_LIGHT_ROW_OFF_GAP apart.
		var since := now - (_close_at + Constants.ANNEX_LIGHTS_OFF_DELAY)
		var due := clampi(floori(since / Constants.ANNEX_LIGHT_ROW_OFF_GAP) + 1, 0, 4) if since >= 0.0 else 0
		while _rows_off < due:
			var row := _set.get_node_or_null("LightRows/Row%d" % _rows_off)
			if row != null and row.has_method("set_state"):
				row.call("set_state", &"off", now)
			_sound_at("lights_off_clunk", (row as Node3D).global_position if row is Node3D else _set_point("Threshold"), -4.0)
			_rows_off += 1
	_dim_room(now)
	var board := _set.get_node_or_null("NowServing")
	if board != null and board.has_method("show_number"):
		var serves := 0
		for entry: Dictionary in _overrides:
			if str(entry.get("kind", "")) == "serve" and float(entry["at"]) <= t:
				serves += 1
		if serves != _serves_shown:
			_serves_shown = serves
			board.call("show_number", serves)


## Closing's dark (R2b: the rows went dark and the room stayed as bright): while
## you're inside, the sky light and the sun ease down with each row's clunk, to
## ANNEX_CLOSING_DIM of themselves; outside, or once it's over, they're back.
## Local and cosmetic (the room's light is only ever this peer's view).
func _dim_room(now: float) -> void:
	var me := Net.local_peer_id()
	var inside := _active and _closing and Net.player_zone(me) == Net.Zone.BORDER and (stage_of(me) == STAGE_INSIDE or _visitors.has(me))
	var dim := 1.0
	if inside:
		var off := 0.0
		for row: int in Constants.ANNEX_LIGHT_ROWS:
			var at := _close_at + Constants.ANNEX_LIGHTS_OFF_DELAY + float(row) * Constants.ANNEX_LIGHT_ROW_OFF_GAP
			off += clampf((now - at) / Constants.ANNEX_ROW_DIM_SECONDS, 0.0, 1.0)
		dim = lerpf(1.0, Constants.ANNEX_CLOSING_DIM, off / float(Constants.ANNEX_LIGHT_ROWS))
	if is_equal_approx(dim, _dim_shown):
		return
	_dim_shown = dim
	var holder := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment if get_parent() != null else null
	var environment: Environment = holder.environment if holder != null else null
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D if get_parent() != null else null
	if _dim_base.is_empty():
		_dim_base = {"ambient": environment.ambient_light_energy if environment != null else -1.0, "sun": sun.light_energy if sun != null else -1.0,
			"brightness": environment.adjustment_brightness if environment != null and environment.adjustment_enabled else -1.0}
	if environment != null and float(_dim_base["ambient"]) >= 0.0:
		environment.ambient_light_energy = float(_dim_base["ambient"]) * dim
	if sun != null and float(_dim_base["sun"]) >= 0.0:
		sun.light_energy = float(_dim_base["sun"]) * dim
	# The lobby's look barely follows its lights (the sky light and the sun are
	# small parts of it), so the picture itself is brought down too.
	if environment != null and float(_dim_base.get("brightness", -1.0)) >= 0.0:
		environment.adjustment_brightness = float(_dim_base["brightness"]) * lerpf(Constants.ANNEX_CLOSING_PICTURE, 1.0, (dim - Constants.ANNEX_CLOSING_DIM) / (1.0 - Constants.ANNEX_CLOSING_DIM))
	if is_equal_approx(dim, 1.0):
		_dim_base = {}


func _show_state(window: String, state: Dictionary) -> void:
	var s := int(state["state"])
	var since := _abs(float(state["since"]))
	var args: Dictionary = state.get("args", {})
	if window == "head":
		_show_head(s, since, args)
		return
	var piece := _set.get_node_or_null("Windows/%s" % window)
	var clerk := "Clerk%s" % window
	if piece != null and piece.has_method("set_state"):
		var lit := [_Schedule.S.OPEN, _Schedule.S.D_OPEN, _Schedule.S.SERVING, _Schedule.S.PEER_FORM, _Schedule.S.NOTICE, _Schedule.S.TELEGRAPH, _Schedule.S.VOLLEY].has(s)
		piece.call("set_state", &"lamp_on" if lit else &"lamp_off", since)
		# BACK IN 5 MINUTES stands from the break's start until he's sat back
		# down, and folds away then (R2b: it stayed up on an open window).
		var away := s == _Schedule.S.BREAK or s == _Schedule.S.JAM or s == _Schedule.S.RETURN
		if away != bool(_signs.get(window, false)):
			_signs[window] = away
			piece.call("set_state", &"clock_sign" if away else &"clock_sign_off", since)
		if window == "D":
			# The blinds' rattle and the lamp's bing are the window's own sounds.
			var up := s == _Schedule.S.D_OPEN or s == _Schedule.S.VOLLEY
			var shown_up := not bool(piece.get("blind_down"))
			if up != shown_up:
				piece.call("set_state", &"blind_up" if up else &"blind_down", since)
	var play_args := {}
	var name_now: StringName = state["name"]
	match s:
		_Schedule.S.BREAK, _Schedule.S.JAM:
			var spot := _window_spot(window, "BreakSpot%d" % int(args.get("spot", 0)))
			if s == _Schedule.S.JAM:
				spot = _set_point("Copier/Spot")
				var copier := _set_node("Copier")
				if copier != null and copier.has_method("set_state"):
					copier.call("set_state", &"jam", since)
				_sound_at("copier_beep", spot)
			var copier_node := _set_node("Copier") as Node3D
			if s == _Schedule.S.JAM and spot != Vector3.INF and copier_node != null:
				# Beside the copier, not where the Head NICE BOY stands at it.
				spot += copier_node.global_basis * Vector3(Constants.ANNEX_JAM_SPOT_SIDE, 0.0, 0.0)
			if spot != Vector3.INF:
				play_args["to"] = spot
			play_args["path"] = _gate_path(window, true)
			# There part way in, then the coffee (R2c annex: he arrived late, if at all).
			play_args["arrive_in"] = (float(state["until"]) - float(state["since"])) * Constants.CLERK_BREAK_ARRIVE_SHARE
		_Schedule.S.RETURN:
			play_args["path"] = _gate_path(window, false)
			# Seated when RETURN ends and the lamp comes on (R2c annex).
			play_args["seconds"] = float(state["until"]) - float(state["since"])
		_Schedule.S.LEAN:
			var toward := str(args.get("toward", "A"))
			play_args["dir"] = _window_spot(toward, "ClerkSeat") - _window_spot(window, "ClerkSeat")
		_Schedule.S.PEER_FORM:
			var right_id := str(args.get("right", ""))
			play_args["right"] = right_id
			var right := _window_spot(right_id, "Counter")
			if right != Vector3.INF:
				play_args["face"] = right
			# He points at the right window's plaque, its badge the one on your box.
			var right_piece := _set_node("Windows/%s" % right_id) as Node3D
			if right_piece != null:
				play_args["to"] = right_piece.global_position + Vector3(0.0, Constants.ANNEX_POINT_RISE, 0.0)
			var line := _set_node("FloorLines/%s" % right_id)
			if line != null and line.has_method("set_state"):
				line.call("set_state", &"pulse", since)
			_sound_at("babble", _window_spot(window, "Counter"), -3.0)
		_Schedule.S.SERVING:
			# The beats: he waves you up, takes the form, reads it, lifts his
			# stamp, brings it down (ink and KA-CHUNK together, ANNEX_STAMP_HIT on),
			# hands it back.
			var lift := since + Constants.ANNEX_SERVE_LIFT_AT
			var land := since + Constants.ANNEX_SERVE_STAMP_AT
			_later(lift, func() -> void: _window_state(window, &"stamp_lifted", lift))
			_later(land, func() -> void: _window_state(window, &"stamp_down", land))
			name_now = &"wave_up"
		_Schedule.S.VOLLEY:
			# Window D: he spins round, winds the stamp up high and slams every box
			# left on the form, paper flying (R2b: silent, and he never moved).
			_window_state_args(window, &"stamp_down", since, {"volley": maxi(int(args.get("n", 1)), 1), "first": Constants.ANNEX_VOLLEY_STAMP_AT + Constants.ANNEX_STAMP_HIT, "lift": Constants.ANNEX_VOLLEY_LIFT, "gap": Constants.CLERK_VOLLEY_GAP})
		_Schedule.S.NOTICE:
			_sound_at("babble", _window_spot(window, "Counter"), -3.0)
			# Caught with his stamp out: it goes back on his pad and your hold is
			# over (review: it stayed on your clipboard while he added the carbon).
			if int(args.get("peer", 0)) == Net.local_peer_id() and _hold_window == window:
				_hold_kind = ""
				_hold_window = ""
			if piece != null and piece.has_method("in_hand") and bool(piece.call("in_hand")):
				piece.call("set_state", &"stamp_rest", since)
		_Schedule.S.ASLEEP:
			_sound_at("clerk_snore", _window_spot(window, "ClerkSeat"), -8.0)
	_staff_play(clerk, name_now, since, play_args)
	if s == _Schedule.S.SERVING:
		var take := since + Constants.ANNEX_SERVE_TAKE_AT
		var read := since + Constants.ANNEX_SERVE_READ_AT
		var stamp := since + Constants.ANNEX_SERVE_STAMP_AT
		var hand := since + Constants.ANNEX_SERVE_HAND_AT
		_later(take, func() -> void: _staff_play(clerk, &"take_form", take, {}))
		_later(read, func() -> void: _staff_play(clerk, &"peer_form", read, {}))
		_later(stamp, func() -> void: _staff_play(clerk, &"stamp", stamp, {}))
		_later(hand, func() -> void: _staff_play(clerk, &"hand_back", hand, {}))
	elif s == _Schedule.S.NOTICE:
		var slide := since + Constants.ANNEX_NOTICE_CARBON_AT
		_later(slide, func() -> void: _staff_play(clerk, &"add_carbon", slide, {}))
	elif s == _Schedule.S.CABINET:
		_later(since + Constants.ANNEX_BELL_TWITCH_AT, func() -> void:
			if _active and int(_Schedule.effective(_seed, window, _t(), _overrides)["state"]) == _Schedule.S.CABINET:
				_staff_play(clerk, &"twitch_turn_back", since + Constants.ANNEX_BELL_TWITCH_AT, {}))


## A clerk's way out of his booth (or back in): the set's gate markers when it
## has them, else straight there.
func _gate_path(window: String, out: bool) -> Array:
	var inside := _window_spot(window, "GateIn")
	var outside := _window_spot(window, "GateOut")
	if inside == Vector3.INF or outside == Vector3.INF:
		return []
	var path := [inside, outside]
	var aisle := _window_spot(window, "Aisle")
	if aisle != Vector3.INF:
		path.append(aisle)
	if not out:
		path.reverse()
	return path


## Run do at server time at (now if that's past): a beat inside a state.
func _later(at: float, do: Callable) -> void:
	var wait := at - Net.server_time()
	if wait <= 0.0:
		do.call()
		return
	get_tree().create_timer(wait).timeout.connect(do)


func _window_state(window: String, state: StringName, at: float) -> void:
	_window_state_args(window, state, at, {})


func _window_state_args(window: String, state: StringName, at: float, args: Dictionary) -> void:
	var piece := _set_node("Windows/%s" % window)
	if piece != null and piece.has_method("set_state"):
		piece.call("set_state", state, at, args)


func _show_head(s: int, since: float, args: Dictionary) -> void:
	match s:
		_Schedule.S.AWAY:
			var to_cooler := int(args.get("spot", 0)) != 0
			var spot := _set_point("Cooler/Spot" if to_cooler else "Copier/Spot")
			var walk := {"to": spot} if spot != Vector3.INF else {}
			if to_cooler and bool(_set.get_meta("greybox", false)):
				# Across the room between the queues and the chairs, not through them.
				walk["path"] = [_set.to_global(Vector3(-6.4, 0.0, 2.3)), _set.to_global(Vector3(6.4, 0.0, 2.3))]
			_staff_play("HeadNiceBoy", &"walk_to", since, walk)
		_Schedule.S.APPROVE:
			# He reads it first (ANNEX_HEAD_READ), then the big stamp goes up.
			_staff_play("HeadNiceBoy", &"head_windup_slam", since, {"read": Constants.ANNEX_HEAD_READ})
			var raise := since + Constants.ANNEX_HEAD_READ
			# The stamp is his to raise: it goes where his hands take it (npcs/clerk.gd
			# _approve_pose), and only its KA-CHUNK and toot are its own (R2c annex).
			_later(raise, func() -> void:
				var stamp := _set_node("HeadDesk/BigStamp")
				if stamp != null and stamp.has_method("set_state") and _big_holder == 0:
					stamp.call("set_state", &"slam", raise, {"puppet": true}))
		_Schedule.S.PLEASED:
			# P1 catch (audit r2): the slam's done; he stays, sits back and admires it.
			_staff_play("HeadNiceBoy", &"head_pleased", since, {})
		_Schedule.S.SPOTTED:
			_staff_play("HeadNiceBoy", &"gasp_whistle", since, {})
			_sound_at("whistle", _staff_pos("HeadNiceBoy"))
			var holder := _player(int(args.get("peer", 0)))
			if holder != null:
				get_tree().create_timer(0.5).timeout.connect(func() -> void:
					if is_instance_valid(holder):
						_staff_play("HeadNiceBoy", &"walk_hand_out", since + 0.5, {"to": holder.global_position}))
			var music := get_tree().get_first_node_in_group("music_director")
			if music != null and music.has_method("push_mood"):
				music.call("push_mood", &"annex_spotted", &"escape", 80)
				get_tree().create_timer(Constants.ANNEX_SPOTTED_ESCAPE).timeout.connect(func() -> void:
					if is_instance_valid(music):
						music.call("pop_mood", &"annex_spotted"))
		_:
			var back := {}
			var head_body := _set_node("Staff/HeadNiceBoy") as Node3D
			if head_body != null and bool(_set.get_meta("greybox", false)) and _set.to_local(head_body.global_position).x > 0.0:
				back["path"] = [_set.to_global(Vector3(6.4, 0.0, 2.3)), _set.to_global(Vector3(-6.4, 0.0, 2.3))]
			_staff_play("HeadNiceBoy", &"counter_idle", since, back)


## The turnstile lets the local player's body through while it's turning for
## them (or at closing), and stops it again after.
func _step_turnstile() -> void:
	var turnstile := _set_node("Turnstile")
	if turnstile == null:
		return
	var open := Net.server_time() < _turnstile_open_until or (_closing and _roster.has(Net.local_peer_id()))
	if open == _turnstile_passing:
		return
	_turnstile_passing = open
	# Its bar's shapes, on this peer only: the one body here that collides with
	# it is the local player's (everyone simulates their own), so this lets
	# exactly them through.
	for node: Node in turnstile.find_children("*", "CollisionShape3D", true, false):
		(node as CollisionShape3D).set_deferred("disabled", open)


## A newly arrived override's sound (the state changes play through _present).
func _present_override(entry: Dictionary) -> void:
	if bool(entry.get("bell", false)):
		_sound_at("desk_bell", _window_spot(str(entry["w"]), "Bell"))


func _set_rows(state: StringName, at: float) -> void:
	var rows := _set.get_node_or_null("LightRows") if _set != null else null
	if rows == null:
		return
	for row: Node in rows.get_children():
		if row.has_method("set_state"):
			row.call("set_state", state, at)


func _apply_big_stamp(holder: int, at: float) -> void:
	var stamp := _set_node("HeadDesk/BigStamp")
	if stamp == null:
		return
	var body := _player(holder) if holder != 0 else null
	if stamp.has_method("set_held"):
		stamp.call("set_held", body)
	if stamp.has_method("set_state"):
		stamp.call("set_state", &"held" if body != null else &"on_pad", at)
	# Two-handed and heavy: the holder walks slower (player.gd carry_speed_scale).
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(holder) and holder != 0:
			node.set_meta(&"speed_share", Constants.ANNEX_BIG_STAMP_SLOW)
		elif node.has_meta(&"speed_share"):
			node.remove_meta(&"speed_share")


## Without the Shuttle (R2 chunk 4), the old ride's van ends its trip at the
## BorderZone's origin, which is the middle of the Annex: out of sight while the
## Annex is open (local, cosmetic), back for the next raid's ride.
func _park_old_van(hide: bool) -> void:
	if get_tree().get_first_node_in_group("nice_shuttle") != null:
		return
	var van := get_parent().get_node_or_null("Rides/Van") as Node3D
	if van == null:
		return
	van.visible = not hide
	# Nor anything to walk into.
	for node: Node in van.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if hide and not body.has_meta("annex_layer"):
			body.set_meta("annex_layer", body.collision_layer)
			body.collision_layer = 0
		elif not hide and body.has_meta("annex_layer"):
			body.collision_layer = int(body.get_meta("annex_layer"))
			body.remove_meta("annex_layer")


func _open_doors() -> void:
	_close_doors()
	var world := get_parent()
	for door: Node in _VisitorDoor.place_all(world, self):
		_doors.append(door)


func _close_doors() -> void:
	for door: Node in _doors:
		if is_instance_valid(door):
			door.queue_free()
	_doors.clear()


# ---------------------------------------------------------------- local player


func _local_input(delta: float) -> void:
	var me_id := Net.local_peer_id()
	var me := _player(me_id)
	if me == null or Net.player_zone(me_id) != Net.Zone.BORDER:
		_end_hold()
		if me != null and _borrow_window != "":
			_borrow_window = ""
			me.remove_meta(&"fp_hands")
		return
	var pos := me.global_position
	_retry -= delta
	_hand_on_stamp(me)
	var form: Dictionary = _forms.get(me_id, {})
	if _inside(me_id) and not form.is_empty() and not bool(form.get("approved", false)):
		# Standing on a counter spot asks to be served (the wrong one gets a head shake).
		var on := ""
		for window: String in Constants.ANNEX_WINDOWS:
			var counter := _window_spot(window, "Counter")
			if counter != Vector3.INF and _flat(pos, counter) <= Constants.ANNEX_COUNTER_REACH:
				on = window
				break
		if on != _dwell_window:
			_dwell_window = on
			_dwell = 0.0
			_asked_wrong = ""
		elif on != "":
			_dwell += delta
		# Your own window asks again until he's free; any other asks once per
		# arrival on its spot (R2b: a wrong window shook his head on a loop),
		# and Window D only while its blinds are up.
		var mine := on == _Form.next_window(form)
		var d_shut := on == "D" and int(window_now("D")["state"]) != _Schedule.S.D_OPEN
		if on != "" and not d_shut and (mine or _asked_wrong != on) and _dwell >= Constants.ANNEX_COUNTER_DWELL and _retry <= 0.0:
			_retry = Constants.ANNEX_RETRY_SECONDS
			_rpc_request_serve.rpc_id(1, on, Net.server_time())
		# A full form at the desk.
		var spot := _set_point("HeadDesk/DeskSpot")
		if _Form.is_full(form) and spot != Vector3.INF and _flat(pos, spot) <= Constants.ANNEX_DESK_REACH and _retry <= 0.0:
			_retry = Constants.ANNEX_RETRY_SECONDS
			_rpc_request_desk.rpc_id(1)
	if _inside(me_id) and not form.is_empty():
		# At the tray, or walking into the turnstile.
		var tray := _set_point("OutgoingTray")
		var gate := _set_point("Turnstile")
		var near := (tray != Vector3.INF and _flat(pos, tray) <= Constants.ANNEX_TRAY_REACH and bool(form.get("approved", false))) or (gate != Vector3.INF and _flat(pos, gate) <= Constants.ANNEX_GATE_REACH)
		# Once per walk up to it (R2b: it clacked or clunked every second you
		# stood there); an unlocked turnstile that timed out may be asked again.
		var open_for_me := Net.server_time() < _turnstile_open_until
		if not near or (_gate_asked and bool(form.get("approved", false)) and not _gate_asked_approved):
			_gate_asked = false
		elif not _gate_asked and not open_for_me and _retry <= 0.0:
			# Asked again until the host answers (an ask that beat our body there,
			# under lag, gets none); answered, it's quiet till you walk away.
			_retry = Constants.ANNEX_RETRY_SECONDS * 2.0
			_gate_asked_approved = bool(form.get("approved", false))
			_rpc_request_tray.rpc_id(1)
		elif _gate_asked and bool(form.get("approved", false)) and not open_for_me and _turnstile_open_until > 0.0:
			_gate_asked = false
	# A hold ends when interact comes up or you walk off (review: the host dropped
	# a hold you walked off with, and the stamp stayed on your clipboard across
	# the lobby). Out of reach is the host's own test, from your side.
	var walked_off := false
	if _hold_kind == "self_stamp":
		var pad := _window_spot(_hold_window, "StampPad")
		walked_off = pad == Vector3.INF or _flat(pos, pad) > Constants.ANNEX_STAMP_REACH + Constants.ANNEX_HOLD_SLACK
	elif _hold_kind == "cosign":
		var sheet := _set_point("CoSignSheet")
		walked_off = sheet == Vector3.INF or _flat(pos, sheet) > Constants.ANNEX_SHEET_REACH + Constants.ANNEX_HOLD_SLACK
	if _hold_kind != "" and (walked_off or not Input.is_action_pressed(&"interact")):
		_end_hold()


func _unhandled_input(event: InputEvent) -> void:
	if not _active or not event.is_action_type():
		return
	var me_id := Net.local_peer_id()
	var me := _player(me_id)
	if me == null or Net.player_zone(me_id) != Net.Zone.BORDER or not _in_room(me_id):
		return
	if event.is_action_pressed(&"interact"):
		if _press_interact(me):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"primary") and _big_holder == me_id:
		var friend := _friend_in_front(me)
		if friend != 0:
			_rpc_request_big_stamp.rpc_id(1, "friend", friend)
		else:
			_rpc_request_big_stamp.rpc_id(1, "self", 0)
		get_viewport().set_input_as_handled()


## What interact does here, nearest thing first. True when it did something.
func _press_interact(me: Node3D) -> bool:
	var me_id := Net.local_peer_id()
	var pos := me.global_position
	var target := _interact_target(pos)
	match str(target.get("kind", "")):
		"stamp":
			_hold_kind = "self_stamp"
			_hold_window = str(target["window"])
			var piece := _set_node("Windows/%s" % _hold_window)
			if piece != null and piece.has_method("set_state"):
				piece.call("set_state", &"stamp_lifted", Net.server_time())
			# Your hand reaches through the hatch, drags it over and lifts it to
			# your form (R2c annex: it inked from 1.5 m away with no hand on it).
			if piece != null and piece.has_method("borrow"):
				piece.call("borrow", _form_slam_point, Net.server_time(), false, true)
			_rpc_request_self_stamp.rpc_id(1, _hold_window, true, Net.server_time())
			return true
		"bell":
			_rpc_request_bell.rpc_id(1, str(target["window"]))
			return true
		"big_stamp":
			_rpc_request_big_stamp.rpc_id(1, "drop" if _big_holder == me_id else "grab", 0)
			return true
		"sheet":
			_hold_kind = "cosign"
			_rpc_request_cosign.rpc_id(1, true)
			return true
		"side_door":
			_rpc_request_leave.rpc_id(1)
			return true
	return false


## Where a stamp you hold comes down: on the form in your hand, a little toward
## you (INF with no form shown).
func _form_slam_point() -> Vector3:
	if _form_view == null or not is_instance_valid(_form_view) or not _form_view.is_visible_in_tree():
		return Vector3.INF
	return _form_view.global_transform * Constants.ANNEX_FORM_SLAM_SPOT


## Your first-person right hand on a window stamp you've taken out of its hatch
## (player/first_person_arms.gd reads the meta), and off it once it's back.
func _hand_on_stamp(me: Node3D) -> void:
	var held: Node3D = null
	for window: String in SERVING:
		var piece := _set_node("Windows/%s" % window)
		if piece != null and piece.has_method("borrowed") and bool(piece.call("borrowed")) and (window == _hold_window or window == _borrow_window):
			# Putting it back, your hand goes with it only while it's in reach
			# (review: walked off with it, your arm stretched 2 m after it).
			if not bool(piece.call("in_hand")) and _flat(me.global_position, piece.call("stamp_knob")) > Constants.ANNEX_STAMP_REACH + Constants.ANNEX_HOLD_SLACK:
				continue
			held = piece as Node3D
			_borrow_window = window
	var big := _set_node("HeadDesk/BigStamp") as Node3D
	if held != null:
		me.set_meta(&"fp_hands", {"right": held.call("stamp_knob") as Vector3 + Vector3.UP * Constants.ANNEX_KNOB_GRIP, "stretch": Constants.ANNEX_BORROW_STRETCH})
	elif _big_holder == Net.local_peer_id() and big != null:
		# The big stamp is two-handed (R2c annex: it hovered between your hands):
		# one on each end of its block, through the swing and the slam.
		var block := big.global_position + Vector3.UP * Constants.ANNEX_BIG_GRIP_UP
		var side := me.global_basis.x * Constants.ANNEX_BIG_GRIP_SPREAD
		me.set_meta(&"fp_hands", {"left": block - side, "right": block + side, "stretch": Constants.ANNEX_BORROW_STRETCH})
		_borrow_window = "big"
	elif _borrow_window != "":
		_borrow_window = ""
		if me.has_meta(&"fp_hands"):
			me.remove_meta(&"fp_hands")


func _end_hold() -> void:
	if _hold_kind == "self_stamp":
		# Let go before it counted: set back down, quietly (R2b: it slammed with a
		# KA-CHUNK and no ink).
		var piece := _set_node("Windows/%s" % _hold_window)
		if piece != null and piece.has_method("set_state"):
			piece.call("set_state", &"stamp_rest", Net.server_time())
		_rpc_request_self_stamp.rpc_id(1, _hold_window, false, Net.server_time())
	elif _hold_kind == "cosign":
		_rpc_request_cosign.rpc_id(1, false)
	_hold_kind = ""
	_hold_window = ""


## The nearest thing interact can act on from here: {kind, window, at}.
func _interact_target(pos: Vector3) -> Dictionary:
	var me_id := Net.local_peer_id()
	var best := {}
	var best_d := INF
	var rider := _inside(me_id)
	var visitor := _visitors.has(me_id)
	# A stamp in your hand has the counter's bells out of mind (review: the bell's
	# keycap sat on screen through the whole heist), and a bell you can't see
	# can't be rung: its keycap would hang over nothing.
	var stamping := _hold_kind == "self_stamp" or _borrow_window != ""
	for window: String in SERVING:
		var piece := _set_node("Windows/%s" % window)
		# A stamp already in your hand has no keycap over it (R2c annex).
		if rider and not (piece != null and piece.has_method("borrowed") and bool(piece.call("borrowed"))):
			var stamp := _window_spot(window, "StampPad")
			var d := _flat(pos, stamp) if stamp != Vector3.INF else INF
			if d <= Constants.ANNEX_STAMP_REACH and d < best_d:
				best_d = d
				best = {"kind": "stamp", "window": window, "at": _stamp_point(window)}
		var bell := _window_spot(window, "Bell")
		var db := _flat(pos, bell) if bell != Vector3.INF and not stamping and _in_view(bell) else INF
		if db <= Constants.ANNEX_BELL_REACH and db < best_d:
			best_d = db
			# The keycap sits on the bell, just over its plunger (R2c annex: 1.35 m
			# over it, it floated at the top edge of the screen; review: 0.2 m over
			# it, looking down from the counter it still drew off to the side).
			best = {"kind": "bell", "window": window, "at": bell + Vector3(0.0, Constants.ANNEX_BELL_KEYCAP_LIFT, 0.0)}
	var pad := _set_point("HeadDesk/Pad")
	# His stamp is only yours to lift while he's away (R2c annex: its keycap hung
	# beside the pad while he raised it himself).
	var head_away := not bool(_Schedule.effective(_seed, "head", _t(), _overrides)["looking"])
	if pad != Vector3.INF and ((_big_holder == 0 and head_away) or _big_holder == me_id):
		var dp := _flat(pos, pad)
		if dp <= Constants.ANNEX_DESK_REACH and dp < best_d:
			best_d = dp
			# Just over its knob on the pad, or on the empty pad to put it back.
			best = {"kind": "big_stamp", "at": pad + Vector3(0.0, Constants.R2B_HUD_STAMP_PROMPT_LIFT + (0.0 if _big_holder == me_id else Constants.ANNEX_BIG_KEYCAP_EXTRA), 0.0)}
	if visitor:
		var sheet := _set_point("CoSignSheet")
		var ds := _flat(pos, sheet) if sheet != Vector3.INF else INF
		if ds <= Constants.ANNEX_SHEET_REACH and ds < best_d and not bool(_cosigned_local()):
			best_d = ds
			best = {"kind": "sheet", "at": sheet + Vector3(0.0, 1.4, 0.0)}
		var door := _set_point("SideDoor")
		var dd := _flat(pos, door) if door != Vector3.INF else INF
		# Only right at the door (R2b: brushing past it sent you home).
		if dd <= Constants.ANNEX_SIDE_DOOR_REACH and dd < best_d:
			best_d = dd
			best = {"kind": "side_door", "at": door + Vector3(0.0, 1.6, 0.0)}
	return best


## On screen in the local camera (true with no camera: a headless peer).
func _in_view(point: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return true
	if not _Overheads.in_front(camera, point):
		return false
	var at := camera.unproject_position(point)
	return get_viewport().get_visible_rect().has_point(at)


func _cosigned_local() -> bool:
	var sheet := _set_node("CoSignSheet")
	return sheet != null and bool(sheet.get_meta("signed_by_me", false))


## The prompt for interaction_prompt.gd: just the key over the thing.
func prompt() -> Dictionary:
	if not _active:
		return {}
	var me_id := Net.local_peer_id()
	var me := _player(me_id)
	if me == null or Net.player_zone(me_id) != Net.Zone.BORDER or not _in_room(me_id):
		return {}
	var target := _interact_target(me.global_position)
	if target.is_empty():
		return {}
	# P1 catch (audit nb10): a keycap whose point is behind the clipboard in your
	# hand would be drawn on the form's first box: it waits until you can see it.
	if _behind_form(target["at"] as Vector3):
		return {}
	return {"text": "{key:interact}", "plain": true, "at": target["at"]}


## Whether a world point is drawn behind the local player's Form 27-B on screen
## (its on-screen box, grown by a keycap's half size).
func _behind_form(point: Vector3) -> bool:
	if _form_view == null or not is_instance_valid(_form_view) or not _form_view.is_visible_in_tree():
		return false
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or not _Overheads.in_front(camera, point):
		return false
	var box := Rect2()
	var has := false
	for node: Node in [_form_view] + _form_view.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		if geo == null or not geo.is_visible_in_tree():
			continue
		var aabb := geo.get_aabb()
		for corner: int in 8:
			var world := geo.global_transform * aabb.get_endpoint(corner)
			if not _Overheads.in_front(camera, world):
				continue
			var at := camera.unproject_position(world)
			box = box.expand(at) if has else Rect2(at, Vector2.ZERO)
			has = true
	if not has:
		return false
	return box.grow(Constants.ANNEX_FORM_PROMPT_PAD).has_point(camera.unproject_position(point))


## While holding the big stamp, a friend within reach in front of you.
func _friend_in_front(me: Node3D) -> int:
	var forward := -me.global_basis.z
	var best := 0
	var best_d := INF
	for peer_id: int in _roster:
		if peer_id == Net.local_peer_id() or not _inside(peer_id):
			continue
		var body := _player(peer_id)
		if body == null:
			continue
		var to := body.global_position - me.global_position
		var d := to.length()
		if d <= Constants.ANNEX_BIG_STAMP_REACH and forward.dot(to.normalized()) > 0.3 and d < best_d:
			best = peer_id
			best_d = d
	return best


## rise_at: when it comes up into your hand from the Greeter's (now if past).
func _show_form(rise_at: float = -1.0) -> void:
	_hide_form()
	var me := Net.local_peer_id()
	var form: Dictionary = _forms.get(me, {})
	if form.is_empty():
		return
	var looks := _run_looks()
	var boxes: PackedStringArray = form["boxes"]
	if ResourceLoader.exists(FORM_SCRIPT):
		var script: Script = load(FORM_SCRIPT)
		_form_view = script.call("make", boxes, looks)
	else:
		_form_view = _Paper.make(boxes, looks)
	if _form_view == null:
		return
	add_child(_form_view)
	var player := _player(me)
	# Chunk 5's form follows the view: lower left in first person, in the left
	# hand over the shoulder.
	if _form_view.has_method("attach_auto") and player != null:
		_form_view.call("attach_auto", player)
	elif _form_view.has_method("attach_first_person") and player != null:
		_form_view.call("attach_first_person", player)
	if _form_view.has_method("punch_card"):
		_form_view.call("punch_card", int(form.get("visits", 1)))
	if _form_view.has_method("fast_pass"):
		_form_view.call("fast_pass", bool(form.get("fast_pass", false)))
	if _form_view.has_method("rise") and rise_at > Net.server_time() - Constants.ANNEX_FORM_RISE:
		# It comes from the Greeter's hands, his very clipboard (R2c annex: ours
		# rose from the screen's bottom while he kept his).
		var greeter := _set_node("Staff/Greeter")
		var from: Node3D = greeter.call("held_prop", "form") if greeter != null and greeter.has_method("held_prop") else null
		_form_view.call("rise", rise_at, from)
	_update_form_view(maxf(Net.server_time(), rise_at + Constants.ANNEX_FORM_RISE))


## at: when the change lands; gap: a volley's boxes ink this far apart.
func _update_form_view(at: float, gap: float = 0.0) -> void:
	if _form_view == null or not is_instance_valid(_form_view):
		return
	var form: Dictionary = _forms.get(Net.local_peer_id(), {})
	if form.is_empty():
		return
	var hours := bool(form.get("after_hours", false))
	# Chunk 5's Form27B takes setters; the grey-box clipboard, properties.
	if _form_view.has_method("set_carbon_boxes"):
		# Exactly the boxes that were slid in as carbons (a redirect's isn't one).
		_form_view.call("set_carbon_boxes", form.get("carbon_idx", []))
	if _form_view.has_method("set_progress") and _form_view.has_method("set_carbon_boxes"):
		_form_view.call("set_progress", int(form["stamped"]), form["boxes"], bool(form["approved"]), at, gap, hours)
	else:
		if "after_hours" in _form_view:
			_form_view.set("after_hours", hours)
		if _form_view.has_method("set_progress"):
			_form_view.call("set_progress", int(form["stamped"]), form["boxes"], bool(form["approved"]), at)
	if _form_view.has_method("glow"):
		_form_view.call("glow", bool(form["approved"]))
	if bool(form.get("dropped", false)):
		_set_form_shown(false)


## The form in hand goes away (into the tray): the grey box's clipboard eases out
## with its shown flag; chunk 5's Form27B is simply hidden.
func _set_form_shown(on: bool) -> void:
	if _form_view == null or not is_instance_valid(_form_view):
		return
	if "shown" in _form_view:
		_form_view.set("shown", on)
	else:
		_form_view.visible = on


func _hide_form() -> void:
	if _form_view != null and is_instance_valid(_form_view):
		_form_view.queue_free()
	_form_view = null


func _show_receipt(lines: PackedStringArray, total: String, at: float) -> void:
	var slip: Node3D = null
	if ResourceLoader.exists(RECEIPT_SCRIPT):
		# Chunk 5's ReceiptSlip is static (it extends RefCounted): show() builds the
		# slip in the local player's view or hand and frees it when it's done.
		var script: Script = load(RECEIPT_SCRIPT)
		script.call("show", lines, total, at, Constants.ANNEX_RECEIPT_SECONDS)
		return
	else:
		slip = _Paper.make_receipt()
	if slip == null:
		return
	add_child(slip)
	if slip.has_method("show_slip"):
		slip.call("show_slip", lines, total, at, Constants.ANNEX_RECEIPT_SECONDS)
	elif slip.has_method("print_slip"):
		slip.call("print_slip", lines, total, at, Constants.ANNEX_RECEIPT_SECONDS)


func _quip(kind: String, args: Array, salt: int = 0) -> void:
	var pool: Array = _Strings.ANNEX_QUIPS.get(kind, [])
	if pool.is_empty():
		return
	var line := str(pool[absi(hash([_seed, kind, Net.local_peer_id(), salt])) % pool.size()])
	if not args.is_empty():
		line = line % args
	var stack := get_tree().get_first_node_in_group("caption_stack")
	if stack != null and stack.has_method("push"):
		stack.call("push", &"quip", line, Constants.QUIP_CAPTION_SECONDS)
		return
	var quips := get_tree().root.find_child("Quips", true, false)
	if quips != null and quips.has_method("show_caption"):
		quips.call("show_caption", line)


# ---------------------------------------------------------------- helpers


func _staff_play(staff_name: String, state: StringName, at: float, args: Dictionary) -> void:
	var member := _set_node("Staff/%s" % staff_name)
	if member != null and member.has_method("play"):
		member.call(STAFF_PLAY, state, at, args)


func _staff_pos(staff_name: String) -> Vector3:
	var member := _set_node("Staff/%s" % staff_name) as Node3D
	return member.global_position + Vector3(0.0, 1.5, 0.0) if member != null else _set_point("Threshold")


func _set_node(path: String) -> Node:
	if _set == null or not is_instance_valid(_set):
		return null
	return _set.get_node_or_null(path)


func _set_point(path: String) -> Vector3:
	var node := _set_node(path) as Node3D
	return node.global_position if node != null else Vector3.INF


func _marker(path: String) -> Node3D:
	if _set == null or not is_instance_valid(_set):
		_ensure_set()
	return _set_node(path) as Node3D


func _window_spot(window: String, spot: String) -> Vector3:
	return _set_point("Windows/%s/%s" % [window, spot])


func _stamp_point(window: String) -> Vector3:
	# R2b: the [E] sits just over the window's stamp itself, not in mid-booth.
	var knob := _set_node("Windows/%s/Stamp" % window) as Node3D
	if knob != null:
		return knob.global_position + Vector3(0.0, Constants.R2B_HUD_STAMP_PROMPT_LIFT, 0.0)
	var pad := _window_spot(window, "StampPad")
	var seat := _window_spot(window, "ClerkSeat")
	if pad == Vector3.INF:
		return Vector3.INF
	# Over the counter between the spot and his seat, at counter height.
	var mid := pad.lerp(seat, 0.45) if seat != Vector3.INF else pad
	return mid + Vector3(0.0, 1.45, 0.0)


func _form_sound_spot(source: String, peer_id: int) -> Vector3:
	if Constants.ANNEX_WINDOWS.has(source):
		return _window_spot(source, "Counter") + Vector3(0.0, 1.2, -0.6)
	if source == "head":
		return _set_point("HeadDesk/Pad")
	if source == "cosign":
		# Distant: from the windows.
		return _window_spot("B", "ClerkSeat") + Vector3(0.0, 1.2, 0.0)
	var body := _player(peer_id)
	return body.global_position + Vector3(0.0, 1.2, 0.0) if body != null else _set_point("Threshold")


func _path_points(path_name: String) -> Array:
	var path := _set_node(path_name) as Path3D
	var out: Array = []
	if path == null or path.curve == null:
		return out
	for index: int in path.curve.point_count:
		out.append(path.to_global(path.curve.get_point_position(index)))
	return out


func _sound(id: String) -> void:
	var real := _sound_id(id)
	if real == "":
		return
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", real)


func _sound_at(id: String, at: Vector3, db: float = 0.0) -> void:
	var real := _sound_id(id)
	if real == "" or at == Vector3.INF:
		return
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", real, at, db)


## The id to play: chunk 5's when the sound bank has it, else its stand-in.
func _sound_id(id: String) -> String:
	if _Bank.has(id):
		return id
	var stand_in := str(SOUND_FALLBACK.get(id, ""))
	return stand_in if stand_in != "" and _Bank.has(stand_in) else ""


func _set_encounter_stage(peer_id: int, stage_name: String) -> void:
	var encounter := get_tree().get_first_node_in_group("nice_encounter")
	if encounter == null or not encounter.has_method("host_set_stage"):
		return
	var stages: Variant = encounter.get_script().get_script_constant_map().get("Stage", {})
	if typeof(stages) == TYPE_DICTIONARY and (stages as Dictionary).has(stage_name):
		encounter.call("host_set_stage", peer_id, int(stages[stage_name]), {})


func _heat_now() -> float:
	var heat := get_tree().get_first_node_in_group("heat")
	return float(heat.get("heat")) if heat != null else 0.0


func _name_of(peer_id: int) -> String:
	var name_text := Net.player_name(peer_id)
	return name_text if name_text != "" else str(_Strings.UI.get("player_unnamed", "%d")) % peer_id


func _player(peer_id: int) -> Node3D:
	if peer_id == 0:
		return null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id) and node is Node3D:
			return node as Node3D
	return null


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
