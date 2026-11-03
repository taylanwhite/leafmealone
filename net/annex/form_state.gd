extends RefCounted

## Authority: none (pure). One caught player's Form 27-B: a row of boxes, each a
## serving window's id ("A", "B", "C"), stamped left to right, then approved at
## the Head NICE BOY's desk (or by the big stamp, or AFTER HOURS at closing).
## The host owns every form (net/annex/annex.gd) and sends the whole thing to
## every peer when it changes, so these helpers only ever run on plain data:
## {boxes: PackedStringArray, stamped: int, approved: bool, carbons: int,
##  redirected: bool, after_hours: bool, fast_pass: bool}.
##
## Preload it (no class_name).


## A fresh form: 2, 3 or 4 boxes by the heat at the catch (ANNEX_BOXES_BY_HEAT),
## in a seeded order that never asks for the same window twice in a row. Two
## caught players (peer_index 0, 1, ...) get different orders, so a cohort spreads out.
static func boxes_for(seed_value: int, peer_index: int, heat_at_catch: float, windows: Array) -> PackedStringArray:
	var count := 2
	for threshold: float in Constants.ANNEX_BOXES_BY_HEAT:
		if heat_at_catch >= threshold:
			count += 1
	var out := PackedStringArray()
	if windows.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "form"])
	# A seeded rotation per run, then each player starts one window further on.
	var order: Array = windows.duplicate()
	for index: int in range(order.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held: Variant = order[index]
		order[index] = order[swap]
		order[swap] = held
	var start := posmod(peer_index, order.size())
	var step := 1 if posmod(floori(float(peer_index) / float(order.size())), 2) == 0 else order.size() - 1
	var at := start
	for box: int in count:
		out.append(str(order[at]))
		at = posmod(at + step, order.size())
	return out


static func make(boxes: PackedStringArray, fast_pass: bool = false) -> Dictionary:
	var form := {"boxes": boxes, "stamped": 0, "approved": false, "carbons": 0, "redirected": false, "after_hours": false, "fast_pass": fast_pass}
	if fast_pass and not boxes.is_empty():
		form["stamped"] = 1
	return form


## The window the next box needs, or "" when every box is stamped.
static func next_window(form: Dictionary) -> String:
	var boxes: PackedStringArray = form.get("boxes", PackedStringArray())
	var stamped := int(form.get("stamped", 0))
	return boxes[stamped] if stamped < boxes.size() else ""


static func is_full(form: Dictionary) -> bool:
	return int(form.get("stamped", 0)) >= (form.get("boxes", PackedStringArray()) as PackedStringArray).size()


## The next box stamped. Returns the new form.
static func stamp(form: Dictionary) -> Dictionary:
	var out := form.duplicate(true)
	out["stamped"] = mini(int(out["stamped"]) + 1, (out["boxes"] as PackedStringArray).size())
	return out


## Every remaining box stamped at once (Window D's volley).
static func stamp_all(form: Dictionary) -> Dictionary:
	var out := form.duplicate(true)
	out["stamped"] = (out["boxes"] as PackedStringArray).size()
	return out


## A carbon copy slid in: one more box at the end, for that window ("complimentary").
static func carbon(form: Dictionary, window: String) -> Dictionary:
	var out := form.duplicate(true)
	var boxes: PackedStringArray = (out["boxes"] as PackedStringArray).duplicate()
	boxes.append(window)
	out["boxes"] = boxes
	out["carbons"] = int(out.get("carbons", 0)) + 1
	return out


## The Redirect quirk: one more box for another window, stuck on the end.
static func redirect(form: Dictionary, window: String) -> Dictionary:
	var out := carbon(form, window)
	out["carbons"] = int(form.get("carbons", 0))
	out["redirected"] = true
	return out


## The big stamp taken back: approval gone and one box's ink smudged off.
static func smudge(form: Dictionary) -> Dictionary:
	var out := form.duplicate(true)
	out["approved"] = false
	out["stamped"] = maxi(int(out["stamped"]) - 1, 0)
	return out


static func approve(form: Dictionary, after_hours: bool = false) -> Dictionary:
	var out := form.duplicate(true)
	out["approved"] = true
	if after_hours:
		out["after_hours"] = true
	return out
