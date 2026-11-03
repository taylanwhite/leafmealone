extends RefCounted

## Authority: none (pure). Satellite Annex B's day, as a function of the Annex's
## seed and the seconds since it began: what each window's clerk is doing (open,
## a telegraphed phone call or break, a quirk), the Head NICE BOY's desk and away
## routine, and Window D's one opening. Every peer computes the same thing, so
## the clerks' bodies, lamps and blinds agree everywhere without replication; the
## host judges "is he looking" from this too, never from a body.
##
## Overrides are the host's interruptions on top (a serve, a bell, a head shake,
## the big stamp spotted, closing time), each {kind, w, at, until, ...}, sent to
## every peer in order (net/annex/annex.gd _rpc_override). effective() applies
## them: the newest override covering t wins.
##
## The never-wait guarantee (annex_test checks it over 200 seeds): no clerk is
## "looking but not serving" for longer than Constants.ANNEX_MAX_IDLE, at least
## one serving window is open at every moment, and each one is open at least
## Constants.ANNEX_MIN_OPEN_SHARE of the day. So whatever box a player needs next,
## its window is open or its stamp is unwatched within a few seconds.
##
## Preload it (no class_name).

enum S {
	OPEN, TELEGRAPH, PHONE, BREAK, RETURN, ASLEEP, LUNCH_BITE, LUNCH_TURNED, JAM, CLOSED, D_OPEN,
	SERVING, PEER_FORM, CABINET, LEAN, WAKE, NOTICE, VOLLEY, AFTER_HOURS,
	DESK, AWAY, APPROVE, SPOTTED,
}

## Per state: [looking, serving (free to start a serve), the clerk body's play() state].
const INFO: Dictionary = {
	S.OPEN: [true, true, &"counter_idle"],
	S.TELEGRAPH: [true, false, &"telegraph_stretch"],
	S.PHONE: [false, false, &"phone"],
	S.BREAK: [false, false, &"on_break"],
	S.RETURN: [true, false, &"hurry_back"],
	S.ASLEEP: [false, false, &"asleep"],
	S.LUNCH_BITE: [true, false, &"lunch_bite"],
	S.LUNCH_TURNED: [false, false, &"lunch_turned"],
	S.JAM: [false, false, &"on_break"],
	S.CLOSED: [false, false, &"counter_idle"],
	S.D_OPEN: [true, true, &"counter_idle"],
	S.SERVING: [true, false, &"take_form"],
	S.PEER_FORM: [true, false, &"head_shake_point"],
	S.CABINET: [false, false, &"turn_to_cabinet"],
	S.LEAN: [false, false, &"lean_toward"],
	S.WAKE: [true, false, &"wake"],
	S.NOTICE: [true, false, &"notice"],
	S.VOLLEY: [true, false, &"volley"],
	S.AFTER_HOURS: [false, false, &"closing_rush"],
	S.DESK: [true, false, &"counter_idle"],
	S.AWAY: [false, false, &"walk_to"],
	S.APPROVE: [true, false, &"head_windup_slam"],
	S.SPOTTED: [true, false, &"gasp_whistle"],
}

const QUIRKS: Array[StringName] = [&"asleep", &"redirect", &"lunch", &"jam"]

## seed -> the generated day (cleared when it grows, so a long session can't hoard).
static var _cache: Dictionary = {}


## The clerk at a window, t seconds after the Annex began, before overrides:
## {state, since, until, looking, serving, name}. "D" is Window D; "head" is the
## Head NICE BOY (DESK or AWAY; args.spot 0 copier, 1 cooler).
static func window_state(seed_value: int, window: String, t: float) -> Dictionary:
	var day := _day(seed_value)
	var segments: Array = day.get(window, [])
	if segments.is_empty():
		return _entry(S.CLOSED, 0.0, INF, {})
	var tt := clampf(t, 0.0, Constants.ANNEX_SCHEDULE_HORIZON - 0.001)
	# Binary search for the segment holding tt.
	var low := 0
	var high := segments.size() - 1
	while low < high:
		var mid := (low + high + 1) >> 1
		if float(segments[mid][0]) <= tt:
			low = mid
		else:
			high = mid - 1
	var seg: Array = segments[low]
	return _entry(int(seg[2]), float(seg[0]), float(seg[1]), seg[3] if seg.size() > 3 else {})


static func head_state(seed_value: int, t: float) -> Dictionary:
	return window_state(seed_value, "head", t)


## When Window D's blinds go up, seconds after the Annex began.
static func d_open_at(seed_value: int) -> float:
	return float(_day(seed_value)["d_open_at"])


## The run's quirks: {window id: quirk id}, one or two serving windows.
static func quirks(seed_value: int) -> Dictionary:
	return (_day(seed_value)["quirks"] as Dictionary).duplicate()


## The three serving windows' pictograms this run: {window id: icon id}.
static func window_icons(seed_value: int) -> Dictionary:
	return (_day(seed_value)["icons"] as Dictionary).duplicate()


## window_state with the host's overrides on top (overrides sorted by "at").
static func effective(seed_value: int, window: String, t: float, overrides: Array) -> Dictionary:
	for index: int in range(overrides.size() - 1, -1, -1):
		var o: Dictionary = overrides[index]
		if str(o.get("w", "")) != window:
			continue
		var at := float(o.get("at", 0.0))
		var until := float(o.get("until", at))
		if t < at or t >= until:
			continue
		var kind := StringName(str(o.get("kind", "")))
		match kind:
			&"serve":
				return _entry(S.SERVING, at, until, o)
			&"wrong_window":
				return _entry(S.PEER_FORM, at, until, o)
			&"cabinet":
				return _entry(S.CABINET, at, until, o)
			&"lean":
				return _entry(S.LEAN, at, until, o)
			&"hurry_back":
				var back := at + Constants.ANNEX_RETURN_WALK
				return _entry(S.RETURN, at, back, o) if t < back else _entry(S.OPEN, back, until, o)
			&"wake":
				var up := at + Constants.ANNEX_WAKE_SECONDS
				return _entry(S.WAKE, at, up, o) if t < up else _entry(S.OPEN, up, until, o)
			&"notice":
				return _entry(S.NOTICE, at, until, o)
			&"volley":
				return _entry(S.VOLLEY, at, until, o)
			&"closing":
				return _entry(S.AFTER_HOURS, at, until, o)
			&"approve":
				return _entry(S.APPROVE, at, until, o)
			&"spotted":
				return _entry(S.SPOTTED, at, until, o)
			&"shut":
				return _entry(S.CLOSED, at, until, o)
	return window_state(seed_value, window, t)


## A determinism fingerprint: n samples of every window and the head.
static func hash_samples(seed_value: int, n: int) -> int:
	var parts: Array = []
	for index: int in n:
		var t := float(index) * Constants.ANNEX_CAP_SECONDS / float(maxi(n, 1))
		for window: String in Constants.ANNEX_WINDOWS + ["head"]:
			var state := window_state(seed_value, window, t)
			parts.append([window, int(state["state"]), snappedf(float(state["until"]), 0.001)])
	parts.append(d_open_at(seed_value))
	parts.append(quirks(seed_value))
	parts.append(window_icons(seed_value))
	return hash(parts)


## The day's raw segments for a window, [[from, to, state, args], ...] (for annex_test).
static func segments(seed_value: int, window: String) -> Array:
	return (_day(seed_value).get(window, []) as Array).duplicate(true)


static func is_looking(state: Dictionary) -> bool:
	return bool(state.get("looking", false))


static func state_name(state_value: int) -> String:
	return S.keys()[state_value]


static func _entry(state_value: int, since: float, until: float, args: Dictionary) -> Dictionary:
	var info: Array = INFO[state_value]
	return {"state": state_value, "since": since, "until": until, "looking": bool(info[0]), "serving": bool(info[1]), "name": info[2], "args": args}


# ---------------------------------------------------------------- generation


static func _day(seed_value: int) -> Dictionary:
	if _cache.has(seed_value):
		return _cache[seed_value]
	if _cache.size() > 64:
		_cache.clear()
	var day := _generate(seed_value)
	_cache[seed_value] = day
	return day


static func _generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "annex_b"])
	var horizon := Constants.ANNEX_SCHEDULE_HORIZON
	var windows: Array[String] = Constants.ANNEX_SERVING_WINDOWS.duplicate()
	# Pictograms: three of the four, in a seeded order.
	var icons: Array[String] = Constants.ANNEX_WINDOW_ICONS.duplicate()
	_shuffle(icons, rng)
	var icon_of := {}
	for index: int in windows.size():
		icon_of[windows[index]] = icons[index]
	# Quirks on distinct serving windows.
	var quirk_ids: Array[StringName] = QUIRKS.duplicate()
	_shuffle(quirk_ids, rng)
	var picks: Array[String] = windows.duplicate()
	_shuffle(picks, rng)
	var quirk_count := rng.randi_range(Constants.ANNEX_QUIRKS.x, Constants.ANNEX_QUIRKS.y)
	var quirk_of := {}
	for index: int in quirk_count:
		quirk_of[picks[index]] = quirk_ids[index]
	# Each window: an open stretch, then an off block, round and round. The windows
	# are generated together, earliest decision first, so a window only goes off
	# while another is open (the "one is always open" half of the guarantee).
	var segments := {}
	var open_end := {}
	var open_total := {}
	var off_total := {}
	var jammed := {}
	for index: int in windows.size():
		var window := windows[index]
		segments[window] = []
		# Staggered first stretches, so the three never telegraph together.
		var first := rng.randf_range(Constants.ANNEX_OPEN.x, Constants.ANNEX_OPEN.y) + float(index) * 2.6
		(segments[window] as Array).append([0.0, first, S.OPEN, {}])
		open_end[window] = first
		open_total[window] = first
		off_total[window] = 0.0
		jammed[window] = false
	var guard := 0
	while guard < 4000:
		guard += 1
		var window := ""
		var earliest := INF
		for candidate: String in windows:
			if float(open_end[candidate]) < earliest:
				earliest = float(open_end[candidate])
				window = candidate
		if earliest >= horizon:
			break
		var at := earliest
		var block := _off_block(window, str(quirk_of.get(window, "")), rng, open_total, off_total, jammed)
		var length := 0.0
		for piece: Array in block:
			length += float(piece[1])
		if not _covered(window, at, at + length, windows, segments, open_end):
			# Someone else is off right now: stay open a little longer and look again.
			var waiting: Array = segments[window]
			var last: Array = waiting[waiting.size() - 1]
			last[1] = float(last[1]) + 1.0
			open_end[window] = float(last[1])
			open_total[window] = float(open_total[window]) + 1.0
			continue
		var list: Array = segments[window]
		var t := at
		for piece: Array in block:
			list.append([t, t + float(piece[1]), int(piece[0]), piece[2] if piece.size() > 2 else {}])
			t += float(piece[1])
			if int(piece[0]) == S.JAM:
				jammed[window] = true
		off_total[window] = float(off_total[window]) + length
		var open_for := rng.randf_range(Constants.ANNEX_OPEN.x, Constants.ANNEX_OPEN.y)
		list.append([t, t + open_for, S.OPEN, {}])
		open_end[window] = t + open_for
		open_total[window] = float(open_total[window]) + open_for
	# Window D: closed but for one stretch.
	var d_at := snappedf(rng.randf_range(Constants.ANNEX_D_WINDOW.x, Constants.ANNEX_D_WINDOW.y), 0.01)
	segments["D"] = [
		[0.0, d_at, S.CLOSED, {}],
		[d_at, d_at + Constants.ANNEX_D_OPEN, S.D_OPEN, {}],
		[d_at + Constants.ANNEX_D_OPEN, horizon + 1.0, S.CLOSED, {}],
	]
	# The Head NICE BOY: at his desk, then off to the copier (0) or the cooler (1).
	var head: Array = []
	var ht := 0.0
	while ht < horizon:
		var desk := rng.randf_range(Constants.ANNEX_HEAD_DESK.x, Constants.ANNEX_HEAD_DESK.y)
		head.append([ht, ht + desk, S.DESK, {}])
		ht += desk
		var away := rng.randf_range(Constants.ANNEX_HEAD_AWAY.x, Constants.ANNEX_HEAD_AWAY.y)
		head.append([ht, ht + away, S.AWAY, {"spot": rng.randi_range(0, 1)}])
		ht += away
	segments["head"] = head
	# The last segment of every list runs on past the horizon.
	for key: String in segments.keys():
		var list: Array = segments[key]
		(list[list.size() - 1] as Array)[1] = maxf(float((list[list.size() - 1] as Array)[1]), horizon + 1.0)
	return {"d_open_at": d_at, "quirks": quirk_of, "icons": icon_of}.merged(segments)


## One off block for a window: [[state, seconds, args?], ...], telegraphed first.
static func _off_block(window: String, quirk: String, rng: RandomNumberGenerator, open_total: Dictionary, off_total: Dictionary, jammed: Dictionary) -> Array:
	var block: Array = [[S.TELEGRAPH, Constants.ANNEX_TELEGRAPH]]
	var phone := rng.randf_range(Constants.ANNEX_PHONE.x, Constants.ANNEX_PHONE.y)
	var rest := rng.randf_range(Constants.ANNEX_BREAK.x, Constants.ANNEX_BREAK.y)
	var opened := float(open_total[window])
	var off := float(off_total[window])
	# A break only while the window stays comfortably over its open share.
	var break_ok := opened / maxf(opened + off + Constants.ANNEX_TELEGRAPH + rest * Constants.ANNEX_ASLEEP_SCALE, 0.001) >= Constants.ANNEX_MIN_OPEN_SHARE + 0.05
	var take_break := break_ok and rng.randf() < 0.5
	if quirk == "jam" and not bool(jammed[window]) and opened >= Constants.ANNEX_JAM_SECONDS * 0.9:
		block.append([S.JAM, Constants.ANNEX_JAM_SECONDS - Constants.ANNEX_RETURN_WALK, {"spot": 0}])
		block.append([S.RETURN, Constants.ANNEX_RETURN_WALK])
		return block
	if take_break:
		if quirk == "asleep":
			block.append([S.ASLEEP, rest * Constants.ANNEX_ASLEEP_SCALE])
			return block
		block.append([S.BREAK, rest - Constants.ANNEX_RETURN_WALK, {"spot": rng.randi_range(0, 2)}])
		block.append([S.RETURN, Constants.ANNEX_RETURN_WALK])
		return block
	if quirk == "lunch":
		var bites := maxi(1, int(round(phone / (Constants.ANNEX_LUNCH_BITE + Constants.ANNEX_LUNCH_CHEW) * 1.6)))
		for _bite: int in bites:
			block.append([S.LUNCH_TURNED, Constants.ANNEX_LUNCH_CHEW])
			block.append([S.LUNCH_BITE, Constants.ANNEX_LUNCH_BITE])
		block.append([S.LUNCH_TURNED, Constants.ANNEX_LUNCH_CHEW * 0.5])
		return block
	block.append([S.PHONE, phone])
	return block


## True when, all through [from, to], some other serving window is open (a window
## whose plan doesn't reach that far yet counts: it checks this window when it
## decides).
static func _covered(window: String, from: float, to: float, windows: Array[String], segments: Dictionary, open_end: Dictionary) -> bool:
	var t := from
	while t < to:
		var ok := false
		for other: String in windows:
			if other == window:
				continue
			if t >= float(open_end[other]):
				ok = true
				break
			# The newest segments are the ones near t: look from the end.
			var list: Array = segments[other]
			for index: int in range(list.size() - 1, -1, -1):
				var seg: Array = list[index]
				if float(seg[0]) <= t and t < float(seg[1]):
					if int(seg[2]) == S.OPEN:
						ok = true
					break
			if ok:
				break
		if not ok:
			return false
		t += 0.25
	return true


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(list.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held: Variant = list[index]
		list[index] = list[swap]
		list[swap] = held
