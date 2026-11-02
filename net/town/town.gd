extends Node

## Authority: host. The persistent town (docs/SPINE.md, "The town"): every
## house in every neighborhood, its homeowner, what they think of the crew, and
## when the crew was last there. Saved with the campaign. Houses are made once
## from the town's seed, so the same address is always the same yard and the
## same person.
##
## Each morning some clients text a job (requests). The job board at Homie Depot
## offers today's requests; Chefty drives to the picked one. When the job is paid
## the client's relationship moves by the review, and a happy client refers a
## neighbor. Neighborhoods open with rank (core/ranks.gd "hood:<id>") and a
## referral into them.
##
## The whole town is small (about 50 houses), so the host sends it all, reliably,
## whenever it changes. Clients only read it.

signal changed
## A new text for the phone (ui/phone.gd).
signal texted(text: Dictionary)

const _Hoods = preload("res://net/town/neighborhoods.gd")
const _JobBoard = preload("res://levels/job_board.gd")
const _Seasons = preload("res://core/seasons.gd")
const _Economy = preload("res://core/economy.gd")
## Texts kept for the phone, newest last.
const MAX_TEXTS: int = 40

var town_seed: int = 0
## Every house: {id, hood, number, street, seed, size, owner: {first, last,
## personality, standards, budget, likes}, known, relationship, last_day, jobs,
## referred}. Index in this array is the house id.
var houses: Array = []
## House ids that texted a job and haven't been done yet.
var requests: Array = []
## Phone texts: {day, hour, from, kind, text, house}.
var texts: Array = []
## The house the crew is working on right now, or -1.
var current_house: int = -1

var _day: int = 1
var _daytime_checked: int = -1


func _ready() -> void:
	add_to_group("town")
	Net.player_joined.connect(_on_player_joined)
	if not Net.is_host():
		if multiplayer.multiplayer_peer != null:
			_rpc_request_state.rpc_id(1)
		return
	var saved := Campaign.save_section("town")
	var clock := get_tree().get_first_node_in_group("day_clock")
	_day = int(clock.get("day")) if clock != null else 1
	if saved.is_empty() or (saved.get("houses", []) as Array).is_empty():
		_new_town()
	else:
		_load_saved(saved)
	Campaign.add_save_hook(_save_section)
	_broadcast()


func _exit_tree() -> void:
	Campaign.remove_save_hook(_save_section)


## The save is JSON, so every number comes back a float: make the ids and
## counters ints again, or has() and erase() stop matching them.
func _load_saved(saved: Dictionary) -> void:
	town_seed = int(saved.get("seed", 1))
	houses.clear()
	for entry: Variant in (saved.get("houses", []) as Array):
		var house_entry := (entry as Dictionary).duplicate(true)
		for key: String in ["id", "number", "seed", "size", "last_day", "jobs"]:
			house_entry[key] = int(house_entry.get(key, -1 if key == "last_day" else 0))
		house_entry["relationship"] = float(house_entry.get("relationship", 0.0))
		house_entry["known"] = bool(house_entry.get("known", false))
		house_entry["referred"] = bool(house_entry.get("referred", false))
		house_entry["poached"] = bool(house_entry.get("poached", false))
		houses.append(house_entry)
	requests.clear()
	for house_id: Variant in (saved.get("requests", []) as Array):
		requests.append(int(house_id))
	texts.clear()
	for entry: Variant in (saved.get("texts", []) as Array):
		var text_entry := (entry as Dictionary).duplicate(true)
		text_entry["day"] = int(text_entry.get("day", 1))
		text_entry["house"] = int(text_entry.get("house", -1))
		texts.append(text_entry)
	_daytime_checked = int(saved.get("daytime_checked", -1))


func _process(_delta: float) -> void:
	if not Net.is_host():
		return
	_watch_signs()
	var clock := get_tree().get_first_node_in_group("day_clock")
	if clock == null:
		return
	# Now and then during the day, a client texts a job.
	var hour := float(clock.call("hour"))
	for slot: int in Constants.TOWN_DAYTIME_TEXT_HOURS.size():
		if slot > _daytime_checked and hour >= Constants.TOWN_DAYTIME_TEXT_HOURS[slot]:
			_daytime_checked = slot
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([town_seed, _day, slot])
			if rng.randf() < Constants.TOWN_DAYTIME_TEXT_CHANCE:
				if _ask_for_jobs(1, rng) > 0:
					_broadcast()


# ---------------------------------------------------------------- reading

func house(house_id: int) -> Dictionary:
	if house_id < 0 or house_id >= houses.size():
		return {}
	return houses[house_id]


## The house whose yard has this seed, or -1 (a test yard).
func house_by_seed(seed_value: int) -> int:
	for entry: Dictionary in houses:
		if int(entry["seed"]) == seed_value:
			return int(entry["id"])
	return -1


func known_houses() -> Array:
	var out: Array = []
	for entry: Dictionary in houses:
		if bool(entry.get("known", false)):
			out.append(entry)
	return out


## "Barb Featherstone"
func owner_name(house_id: int) -> String:
	var entry := house(house_id)
	if entry.is_empty():
		return ""
	var owner: Dictionary = entry["owner"]
	return "%s %s" % [owner["first"], owner["last"]]


## "14 Maple Row"
func address(house_id: int) -> String:
	var entry := house(house_id)
	if entry.is_empty():
		return ""
	return "%d %s" % [int(entry["number"]), str(entry["street"])]


## How grown back a yard is today: full the first time, then regrowing each day.
func mess(house_id: int, on_day: int = -1) -> float:
	var entry := house(house_id)
	if entry.is_empty():
		return 1.0
	var today := _day if on_day < 0 else on_day
	var last := int(entry.get("last_day", -1))
	return _Economy.regrow(today - last, last < 0)


func is_hood_open(hood_id: String) -> bool:
	if _Hoods.index_of(hood_id) <= 0:
		return true
	return Campaign.has_unlock("hood:" + hood_id)


## Today's job offers for the board (levels/job_board.gd): one per request.
func offers() -> Array:
	var out: Array = []
	for house_id: Variant in requests:
		out.append(offer_for(int(house_id)))
	return out


## The job at one house today: its yard, its regrowth, and what the owner wants.
func offer_for(house_id: int) -> Dictionary:
	var entry := house(house_id)
	if entry.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(entry["seed"]), _day])
	var size := int(entry["size"])
	var tasks: PackedStringArray = _JobBoard.choose_tasks(rng, size)
	# Their favorite work, if the crew can do it and it isn't asked already.
	var likes := str((entry["owner"] as Dictionary).get("likes", ""))
	if likes != "" and not tasks.has(likes) and _can_do(likes, size):
		tasks.append(likes)
	# And something the season calls for (core/seasons.gd).
	var season := _Seasons.of_day(_day)
	var favored: Array = _Seasons.FAVORED[season]
	var pick := str(favored[rng.randi() % favored.size()])
	if not tasks.has(pick) and _can_do(pick, size):
		tasks.append(pick)
	var hood := _Hoods.get_hood(str(entry["hood"]))
	var owner: Dictionary = entry["owner"]
	return {
		"seed": int(entry["seed"]),
		"house": int(entry["number"]),
		"street": str(entry["street"]),
		"size": size,
		"tasks": tasks,
		"house_id": house_id,
		"client": owner_name(house_id),
		"hood": str(entry["hood"]),
		"hood_name": str(hood["name"]),
		"mess": mess(house_id) * float(_Seasons.LEAVES[_Seasons.of_day(_day)]),
		"budget": budget(house_id),
		"standards": standards(house_id),
		"relationship": float(entry.get("relationship", 0.0)),
		"signs": mini(Constants.RIVAL_MAX_SIGNS, poached_in(str(entry["hood"]))),
	}


## Pay multiplier at a house: the neighborhood's, the owner's, and the crew's perks.
func budget(house_id: int) -> float:
	var entry := house(house_id)
	if entry.is_empty():
		return 1.0
	var value := float(_Hoods.get_hood(str(entry["hood"]))["budget"]) * (1.0 + float((entry["owner"] as Dictionary)["budget"]))
	if Campaign.has_perk("big_spenders"):
		value *= 1.0 + Constants.BIG_SPENDERS_BUDGET
	if Campaign.has_perk("big_spenders_2"):
		value *= 1.0 + Constants.BIG_SPENDERS_BUDGET
	return value


## How picky the owner is, 0 to 1.
func standards(house_id: int) -> float:
	var entry := house(house_id)
	if entry.is_empty():
		return 0.3
	return clampf(float((entry["owner"] as Dictionary)["standards"]), 0.0, 1.0)


## How much faster noise heats the crew at the house being worked.
func heat_scale() -> float:
	var entry := house(current_house)
	if entry.is_empty():
		return 1.0
	return float(_Hoods.get_hood(str(entry["hood"]))["heat"])


# ---------------------------------------------------------------- host hooks

## The crew picked this house's job and is heading out.
func start_job(house_id: int) -> void:
	if not Net.is_host():
		return
	current_house = house_id
	_broadcast()


## Campaign.finish_job: the homeowner paid (or didn't). Move the relationship by
## the review, mark the visit, maybe a referral.
func on_job_finished(_fraction: float, details: Dictionary) -> int:
	if not Net.is_host() or current_house < 0:
		return 0
	var bonus_xp := 0
	var entry: Dictionary = houses[current_house]
	var stars := int(details.get("stars", 0))
	var first_time := int(entry.get("jobs", 0)) == 0
	if stars > 0:
		entry["relationship"] = _Economy.relationship_after(float(entry.get("relationship", 0.0)), stars)
	entry["jobs"] = int(entry.get("jobs", 0)) + 1
	entry["last_day"] = _day
	houses[current_house] = entry
	requests.erase(current_house)
	if first_time:
		Campaign.add_xp(Constants.XP_NEW_CLIENT, "new_client")
		bonus_xp += Constants.XP_NEW_CLIENT
	_maybe_refer(current_house)
	# Word gets around: a great job wins back a neighbor TurfMasters™ took.
	if stars >= 4 and poached_in(str(entry["hood"])) > 0 and randf() < Constants.RIVAL_WIN_BACK_CHANCE:
		_win_back(str(entry["hood"]), owner_name(current_house))
	current_house = -1
	_broadcast()
	return bonus_xp


## DayClock at bedtime: a new day. Returns what happened, for the summary card.
func on_new_day(new_day: int) -> Dictionary:
	if not Net.is_host():
		return {}
	_day = new_day
	_daytime_checked = -1
	# Yesterday's requests nobody took: they went with someone else. The one the
	# crew is working on stays theirs.
	var missed := 0
	for house_id: Variant in requests:
		if int(house_id) == current_house:
			continue
		missed += 1
		var entry: Dictionary = houses[int(house_id)]
		entry["relationship"] = maxf(0.0, float(entry.get("relationship", 0.0)) - Constants.TOWN_RELATIONSHIP_MISSED)
	requests.clear()
	if current_house >= 0:
		requests.append(current_house)
	var opened := _open_new_hoods()
	var poached := _rival_morning()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([town_seed, _day, "morning"])
	var asked := _ask_for_jobs(requests_per_day(), rng)
	# Never a morning with nothing to do: Marty passes on a lead from the store.
	if requests.is_empty():
		for hood: Dictionary in _Hoods.HOODS:
			if not is_hood_open(str(hood["id"])):
				continue
			var lead := _unknown_in(str(hood["id"]))
			if lead >= 0:
				_text("Marty", "lead", "Somebody came by the store asking for a leaf crew. I gave them your number. You're welcome.", -1)
				_meet(lead, "")
				asked += 1
				break
	_broadcast()
	return {"requests": asked, "missed": missed, "opened": opened, "poached": poached}


## How many clients text a job each morning.
func requests_per_day() -> int:
	var count := Constants.TOWN_REQUESTS_PER_DAY
	for perk: String in ["extra_request", "extra_request_2", "extra_request_3"]:
		if Campaign.has_perk(perk):
			count += 1
	return count


## Tests and dev: TurfMasters™ take this client now.
func dev_poach(house_id: int) -> void:
	if not Net.is_host() or house(house_id).is_empty():
		return
	houses[house_id]["poached"] = true
	requests.erase(house_id)
	_text(owner_name(house_id), "poached", "TurfMasters™ came by with a coupon. Sorry, hon.", house_id)
	_broadcast()


## Tests and dev: make sure there's a job to go to.
func dev_request(house_id: int) -> void:
	if Net.is_host() and not requests.has(house_id):
		requests.append(house_id)
		_broadcast()


# ---------------------------------------------------------------- making the town

func _new_town() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	town_seed = rng.randi_range(1, 2147483646)
	if Net.is_automated() or float(Net.dev_options().get("run_seconds")) > 0.0:
		# Tests get the same town every run.
		town_seed = 20261101
	rng.seed = town_seed
	houses.clear()
	var used_names := {}
	for hood_index: int in _Hoods.count():
		var hood: Dictionary = _Hoods.HOODS[hood_index]
		var streets: Array = hood["streets"]
		var numbers := {}
		for index: int in int(hood["houses"]):
			var street := str(streets[index % streets.size()])
			var number := 0
			while number == 0 or numbers.has("%s %d" % [street, number]):
				number = rng.randi_range(2, 98) * 2 + (index % 2)
			numbers["%s %d" % [street, number]] = true
			houses.append(_make_house(houses.size(), hood, number, street, rng, used_names))
	# Day one: a few neighbors in Maple Row already know you.
	var starters: Array = []
	for entry: Dictionary in houses:
		if str(entry["hood"]) == "maple_row":
			starters.append(int(entry["id"]))
	for pick: int in mini(Constants.TOWN_STARTING_CLIENTS, starters.size()):
		var house_id := int(starters[pick])
		houses[house_id]["known"] = true
		houses[house_id]["relationship"] = Constants.TOWN_START_RELATIONSHIP
	requests.clear()
	texts.clear()
	_text("Marty", "intro", "Welcome to the crew. Three of your neighbors want their leaves gone. Check the board by the checkout. The cots by the side wall are yours after 6 PM. Tab to check your phone.", -1)
	# On day one everybody you know wants you.
	for house_id: Variant in starters.slice(0, Constants.TOWN_STARTING_CLIENTS):
		_add_request(int(house_id), rng)


func _make_house(house_id: int, hood: Dictionary, number: int, street: String, rng: RandomNumberGenerator, used_names: Dictionary) -> Dictionary:
	var sizes: Array = hood["sizes"]
	var roll := rng.randf()
	var size := 2
	if roll < float(sizes[0]):
		size = 0
	elif roll < float(sizes[0]) + float(sizes[1]):
		size = 1
	var first := ""
	var last := ""
	for attempt: int in 20:
		first = _Hoods.FIRST_NAMES[rng.randi() % _Hoods.FIRST_NAMES.size()]
		last = _Hoods.LAST_NAMES[rng.randi() % _Hoods.LAST_NAMES.size()]
		if not used_names.has(first + last):
			break
	used_names[first + last] = true
	var kinds: Array = _Hoods.PERSONALITIES.keys()
	var personality := str(kinds[rng.randi() % kinds.size()])
	var nudge: Dictionary = _Hoods.PERSONALITIES[personality]
	var range_of: Vector2 = hood["standards"]
	var likes_from: Array[String] = ["", "mow_lawn", "trim_hedges", "wash_windows", "clean_gutters", "power_wash", "paint_fence", "pull_weeds"]
	return {
		"id": house_id,
		"hood": str(hood["id"]),
		"number": number,
		"street": street,
		"seed": rng.randi_range(1, 2147483646),
		"size": size,
		"owner": {
			"first": first,
			"last": last,
			"personality": personality,
			"standards": clampf(rng.randf_range(range_of.x, range_of.y) + float(nudge["standards"]), 0.0, 1.0),
			"budget": float(nudge["budget"]),
			"likes": likes_from[rng.randi() % likes_from.size()],
		},
		"known": false,
		"relationship": 0.0,
		"last_day": -1,
		"jobs": 0,
		"referred": false,
		"poached": false,
	}


# ---------------------------------------------------------------- requests and referrals

## Up to count known clients with grown-back yards text a job. Returns how many did.
func _ask_for_jobs(count: int, rng: RandomNumberGenerator) -> int:
	var candidates: Array = []
	for entry: Dictionary in houses:
		var house_id := int(entry["id"])
		if not bool(entry.get("known", false)) or bool(entry.get("poached", false)) or requests.has(house_id) or house_id == current_house:
			continue
		if not is_hood_open(str(entry["hood"])):
			continue
		if mess(house_id) < Constants.TOWN_REQUEST_MIN_MESS:
			continue
		# Messier yards and happier clients ask first, with some luck mixed in.
		var weight := mess(house_id) + float(entry.get("relationship", 0.0)) / 100.0 + rng.randf() * 0.6
		candidates.append([weight, house_id])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var asked := 0
	for pair: Array in candidates:
		if asked >= count:
			break
		_add_request(int(pair[1]), rng)
		asked += 1
	return asked


func _add_request(house_id: int, rng: RandomNumberGenerator) -> void:
	if requests.has(house_id):
		return
	requests.append(house_id)
	var entry: Dictionary = houses[house_id]
	var lines := [
		"Leaves are back. You know where I live. %s.",
		"Can your crew come by today? %s. Bring the good rake.",
		"It's a jungle out here again. %s, whenever you can.",
		"Hi it's me. The yard. %s. Please.",
		"My spouse says the yard is \"a disgrace\". %s. Help.",
	]
	var line := str(lines[rng.randi() % lines.size()]) % address(house_id)
	_text(owner_name(house_id), "request", line, house_id)


## A client happy enough sends a neighbor your way: someone unknown in an open
## neighborhood, theirs first.
func _maybe_refer(from_house: int) -> void:
	var entry: Dictionary = houses[from_house]
	var needed := Constants.TOWN_REFERRAL_AT
	if Campaign.has_perk("word_of_mouth"):
		needed -= 10.0
	if Campaign.has_perk("word_of_mouth_2"):
		needed -= 10.0
	if bool(entry.get("referred", false)) or float(entry.get("relationship", 0.0)) < needed:
		return
	var target := _unknown_in(str(entry["hood"]))
	if target < 0:
		# Their street is all yours already: someone in the next open neighborhood.
		for hood: Dictionary in _Hoods.HOODS:
			if is_hood_open(str(hood["id"])):
				target = _unknown_in(str(hood["id"]))
				if target >= 0:
					break
	if target < 0:
		return
	entry["referred"] = true
	houses[from_house] = entry
	_meet(target, owner_name(from_house))


func _unknown_in(hood_id: String) -> int:
	for entry: Dictionary in houses:
		if str(entry["hood"]) == hood_id and not bool(entry.get("known", false)):
			return int(entry["id"])
	return -1


## A new client: known now, starting relationship, and they text right away.
func _meet(house_id: int, referred_by: String) -> void:
	var entry: Dictionary = houses[house_id]
	entry["known"] = true
	entry["relationship"] = Constants.TOWN_START_RELATIONSHIP
	houses[house_id] = entry
	var hood := _Hoods.name_of(str(entry["hood"]))
	var how := "%s says you're good with a rake." % referred_by if referred_by != "" else "Saw your truck around."
	_text(owner_name(house_id), "referral", "Hi! %s I'm at %s in %s. Got leaves?" % [how, address(house_id), hood], house_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([town_seed, _day, house_id])
	_add_request(house_id, rng)
	Campaign.add_xp(Constants.XP_REFERRAL, "referral")


## A neighborhood the rank just opened, with nobody there yet: the best client
## next door refers someone, or the clerk passes on a lead, so the town never stalls.
func _open_new_hoods() -> Array:
	var opened: Array = []
	for hood_index: int in range(1, _Hoods.count()):
		var hood_id := str(_Hoods.HOODS[hood_index]["id"])
		if not is_hood_open(hood_id):
			continue
		var anyone := false
		for entry: Dictionary in houses:
			if str(entry["hood"]) == hood_id and bool(entry.get("known", false)):
				anyone = true
				break
		if anyone:
			continue
		var target := _unknown_in(hood_id)
		if target < 0:
			continue
		var best := -1
		var best_relationship := -1.0
		for entry: Dictionary in houses:
			if bool(entry.get("known", false)) and float(entry.get("relationship", 0.0)) > best_relationship:
				best_relationship = float(entry.get("relationship", 0.0))
				best = int(entry["id"])
		_meet(target, owner_name(best) if best >= 0 and best_relationship >= Constants.TOWN_REFERRAL_AT * Constants.TOWN_LEAD_REFERRAL_SHARE else "")
		opened.append(_Hoods.name_of(hood_id))
	return opened


# ---------------------------------------------------------------- the rival

## Clients TurfMasters™ has taken in a neighborhood.
func poached_in(hood_id: String) -> int:
	var count := 0
	for entry: Dictionary in houses:
		if str(entry["hood"]) == hood_id and bool(entry.get("poached", false)):
			count += 1
	return count


## Host, each morning once the rival is in town (core/ranks.gd "feature:rival"):
## now and then they poach a client who isn't thrilled with you. Returns names.
func _rival_morning() -> Array:
	var taken: Array = []
	if not Campaign.is_feature_on("rival"):
		return taken
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([town_seed, _day, "rival"])
	if rng.randf() >= Constants.RIVAL_POACH_CHANCE:
		return taken
	var candidates: Array = []
	for entry: Dictionary in houses:
		if bool(entry.get("known", false)) and not bool(entry.get("poached", false)) and int(entry["id"]) != current_house and float(entry.get("relationship", 0.0)) < Constants.RIVAL_POACH_BELOW:
			candidates.append(int(entry["id"]))
	if candidates.is_empty():
		return taken
	var house_id := int(candidates[rng.randi() % candidates.size()])
	houses[house_id]["poached"] = true
	requests.erase(house_id)
	var lines := [
		"TurfMasters™ came by with a coupon. Sorry, hon. It's just business.",
		"A man in a TurfMasters™ polo said you people \"lack synergy\". I'm trying them.",
		"TurfMasters™ does my lawn now. They have a jingle. Do YOU have a jingle?",
	]
	_text(owner_name(house_id), "poached", str(lines[rng.randi() % lines.size()]), house_id)
	taken.append(owner_name(house_id))
	return taken


## Host: a client TurfMasters™ took comes back.
func _win_back(hood_id: String, because_of: String) -> void:
	for entry: Dictionary in houses:
		if str(entry["hood"]) == hood_id and bool(entry.get("poached", false)):
			entry["poached"] = false
			entry["relationship"] = maxf(float(entry.get("relationship", 0.0)), Constants.TOWN_START_RELATIONSHIP)
			var why := "Saw what you did for %s. TurfMasters™ mulched my petunias." % because_of if because_of != "" else "Somebody pulled the TurfMasters™ signs. Was that you? Come back?"
			_text(owner_name(int(entry["id"])), "won_back", why + " I'm back, if you'll have me.", int(entry["id"]))
			Campaign.add_xp(Constants.XP_WON_BACK, "won_back")
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([town_seed, _day, int(entry["id"]), "back"])
			_add_request(int(entry["id"]), rng)
			return


## Host: a sign someone picked up for the first time has been pulled. Picked up
## means in hand or in a pocket (a sign that joins a stack goes straight into
## the pocket, net/components/hotbar.gd), so this asks is_loose, not held_by.
func _watch_signs() -> void:
	var signs := get_tree().get_nodes_in_group("turf_signs")
	if signs.is_empty():
		return
	for node: Node in signs:
		var loose := bool(node.call("is_loose")) if node.has_method("is_loose") else int(node.get("held_by")) == 0
		if node.get_meta("pulled", false) or loose:
			continue
		node.set_meta("pulled", true)
		var left := 0
		for other: Node in signs:
			if not other.get_meta("pulled", false):
				left += 1
		on_sign_pulled(str(node.get_meta("hood", "")), left)


## Host: a player pulled up one of TurfMasters™'s signs in a yard. Every sign
## pulled is a little XP; pulling them all wins a client back.
func on_sign_pulled(hood_id: String, signs_left: int) -> void:
	if not Net.is_host():
		return
	Campaign.add_xp(Constants.XP_SIGN_PULLED, "signs")
	if signs_left <= 0 and poached_in(hood_id) > 0:
		_win_back(hood_id, "")
	_broadcast()


func _can_do(task: String, size: int) -> bool:
	if task == "skim_pool" and size != 2:
		return false
	var tool := str(Constants.TASK_TOOLS.get(task, ""))
	return tool == "" or Campaign.crew_tools().has(tool)


func _text(from: String, kind: String, body: String, house_id: int) -> void:
	var clock := get_tree().get_first_node_in_group("day_clock")
	var entry := {
		"day": _day,
		"time": str(clock.call("clock_text")) if clock != null else "",
		"from": from,
		"kind": kind,
		"text": body,
		"house": house_id,
	}
	texts.append(entry)
	while texts.size() > MAX_TEXTS:
		texts.pop_front()
	texted.emit(entry)
	_rpc_text.rpc(entry)


# ---------------------------------------------------------------- saving and sending

func _save_section() -> Dictionary:
	return {"town": {
		"seed": town_seed,
		"houses": houses,
		"requests": requests,
		"texts": texts,
		"daytime_checked": _daytime_checked,
	}}


func _broadcast() -> void:
	_rpc_state.rpc(town_seed, houses, requests, texts, current_house, _day)
	var board := get_tree().get_first_node_in_group("job_board")
	if board != null and board.has_method("refresh"):
		board.call("refresh")


func _on_player_joined(peer_id: int) -> void:
	if Net.is_host() and peer_id != Net.local_peer_id():
		_rpc_state.rpc_id(peer_id, town_seed, houses, requests, texts, current_house, _day)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if Net.is_host():
		_rpc_state.rpc_id(multiplayer.get_remote_sender_id(), town_seed, houses, requests, texts, current_house, _day)


@rpc("authority", "call_local", "reliable")
func _rpc_state(seed_value: int, all_houses: Array, open_requests: Array, all_texts: Array, working: int, today: int) -> void:
	town_seed = seed_value
	houses = all_houses
	requests = open_requests
	texts = all_texts
	current_house = working
	_day = today
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_text(entry: Dictionary) -> void:
	texts.append(entry)
	while texts.size() > MAX_TEXTS:
		texts.pop_front()
	texted.emit(entry)
