extends Node

## --depart-test (p1-depart, docs/GAME.md "Leaving together"; port 7837, host
## plus a Target client, both with --depart-test --job-seed=777 --yard-size=1,
## starting at Homie Depot). How a crew leaves together and how a job ends,
## checked in the running game:
##   verdict   homeowner.verdict: a yard 1% done with no tasks done is "messy"
##             on every roll (crew-08: the mood swing made it "thrilled" and five
##             stars about one time in sixteen); a "fine" yard is never thrilled;
##             a clean one can be.
##   split     Economy.split_shares/split_dollars: one bagger and three friends
##             on a $40 job: every friend gets at least CREW_SPLIT_EVEN_SHARE's
##             even part, the dollars add up to the pool (missed-03).
##   hop_out   the host presses E at the pad: Chefty honks and the host climbs in
##             (seated, still at the store); jumping hops back out over the
##             tailgate and, with nobody left aboard, the trip's off.
##   wait      E again with the client ~10 m off: Chefty waits (still parked after
##             2 s); the client walks up and climbs in; with everyone aboard it
##             goes after CHEFTY_BOARD_ALL_ABOARD_SECONDS, well before the window
##             is out, both riding (crew-02).
##   early     at the yard with a bag in Chefty: the first ask gets a look at the
##             yard and no cash; the second holds out the cash with "Call it a
##             day ($N)"; another bag mid-offer is counted in (NB-01).
##   beat      the cash taken: the job isn't settled yet; Chefty honks and waits.
##             The host walks up and climbs in, the client stays off on the yard;
##             it goes when the window runs out (not before), gathers the client,
##             and the job settles as it pulls away, the client paid at least the
##             crew's even part (crew-09, missed-03).
##   hold      back at the store, the host boards with the client off by the
##             store: holding E sends Chefty off at once with just the host.
## The client reports what it saw by its own probe: seated while Chefty waited,
## its climb drawn as a hop (not a pop), the honks heard.

const _Homeowner = preload("res://npcs/homeowner.gd")
const _Economy = preload("res://core/economy.gd")
const _Strings = preload("res://ui/strings.gd")
const JOIN_WAIT_SECONDS: float = 30.0
const RIDE_WAIT_SECONDS: float = 20.0
const STEPS: Array[String] = ["verdict", "split", "hop_out", "wait", "early", "beat", "hold"]

static var result: Dictionary = {}

var _started: bool = false
var _steps: Dictionary = {}
## Client: what it saw.
var _seen_seated: bool = false
var _seen_climb: bool = false
var _gathered_home: bool = false
var _was_on_lot: bool = false


func _process(_delta: float) -> void:
	if Net.is_host():
		if not _started and _own_player() != null and _chefty() != null:
			_started = true
			_run()
		return
	_watch_client()


# ---------------------------------------------------------------- client

func _watch_client() -> void:
	if bool(result.get("done", false)):
		return
	var chefty := _chefty()
	var me := Net.local_peer_id()
	if chefty == null or _own_player() == null:
		return
	if bool(chefty.call("is_boarding")):
		var seat := int(chefty.call("seat_of", me))
		if seat >= 0 and seat < int(chefty.call("seat_count")):
			_seen_seated = true
			# The climb: where it puts you this frame against the seat itself.
			var seat_node := chefty.get_node_or_null("Body/Seats/Seat%d" % seat) as Node3D
			if seat_node != null and (chefty.call("seat_transform", seat) as Transform3D).origin.distance_to(seat_node.global_position) > 0.15:
				_seen_climb = true
	if Net.player_zone(me) == Net.Zone.LOT:
		_was_on_lot = true
	if _was_on_lot and Net.player_zone(me) == Net.Zone.STORE:
		_gathered_home = true
	# Done once home from the yard and the host has left again without us (hold).
	if _gathered_home and bool(chefty.call("is_riding")) and int(chefty.call("seat_of", me)) < 0:
		var honks := int(chefty.get("honks"))
		result = {"ok": _seen_seated and _seen_climb and honks >= 3, "seated": _seen_seated, "climb": _seen_climb, "honks": honks, "done": true}
		print("[DepartTest] client: seated %s, climb drawn %s, honks %d" % [_seen_seated, _seen_climb, honks])


# ---------------------------------------------------------------- host

func _run() -> void:
	_check_verdict()
	_check_split()
	var waited := 0.0
	while _client_id() == 0 and waited < JOIN_WAIT_SECONDS:
		await _seconds(0.25)
		waited += 0.25
	if _client_id() == 0:
		_finish("no client joined")
		return
	# A moment for the client's world and Chefty to settle.
	await _seconds(3.0)
	if not await _check_hop_out():
		return _finish("hop_out")
	if not await _check_wait():
		return _finish("wait")
	if not await _check_early():
		return _finish("early")
	if not await _check_beat():
		return _finish("beat")
	if not await _check_hold():
		return _finish("hold")
	_finish("")


func _check_verdict() -> void:
	var rng := RandomNumberGenerator.new()
	var enough := _Economy.clean_enough_at(0.3)
	var messy_below := _Economy.messy_below_at(0.3)
	var bad := 0
	var fine_thrilled := 0
	var clean_thrilled := 0
	for roll: int in 2000:
		rng.seed = roll + 1
		# 1% of the leaves, no tasks done (two tasks asked): done 1/3 of 1%/enough.
		var done := (0.01 / enough + 0.0 + 0.0) / 3.0
		if _Homeowner.verdict(done * enough, enough, messy_below, false, 0, rng) != "messy":
			bad += 1
		rng.seed = roll + 7001
		if _Homeowner.verdict((enough + messy_below) * 0.5, enough, messy_below, false, 0, rng) == "thrilled":
			fine_thrilled += 1
		rng.seed = roll + 9001
		if _Homeowner.verdict(enough, enough, messy_below, false, 0, rng) == "thrilled":
			clean_thrilled += 1
	_step("verdict", bad == 0 and fine_thrilled == 0 and clean_thrilled > 0, "1%% done not messy %d/2000, a fine yard thrilled %d/2000, a clean one thrilled %d/2000" % [bad, fine_thrilled, clean_thrilled])


func _check_split() -> void:
	# The bagger did everything; three friends came along.
	var shares := _Economy.split_shares([Balance.LEAF_CLEARING_SCORE_WEIGHT, 0.0, 0.0, 0.0])
	var dollars := _Economy.split_dollars(40.0, shares)
	var floor_dollars := int(floor(40.0 * Constants.CREW_SPLIT_EVEN_SHARE / 4.0))
	var sum := 0
	var friends_ok := true
	for index: int in dollars.size():
		sum += dollars[index]
		if index > 0 and dollars[index] < floor_dollars:
			friends_ok = false
	var three := _Economy.split_dollars(3.0, _Economy.split_shares([1.0, 0.0, 0.0, 0.0]))
	var three_sum := 0
	for value: int in three:
		three_sum += value
	_step("split", sum == 40 and friends_ok and dollars[0] > dollars[1] and three_sum == 3, "$40 split %s (friends at least $%d), $3 split %s" % [dollars, floor_dollars, three])


func _check_hop_out() -> bool:
	var chefty := _chefty()
	var world := _world()
	var host := Net.local_peer_id()
	_teleport(host, _pad() + Vector3(0.0, 0.5, 3.2))
	_teleport(_client_id(), _store_far())
	await _seconds(1.0)
	var honks := int(chefty.get("honks"))
	world.call("request_depart")
	await _ticks(3)
	var boarding := bool(chefty.call("is_boarding")) and (chefty.call("boarders") as Array).has(host) and Net.player_zone(host) == Net.Zone.STORE
	var honked := int(chefty.get("honks")) > honks
	await _seconds(Constants.CHEFTY_BOARD_CLIMB_SECONDS * 3.0)
	var seated_at := (chefty.call("seat_transform", int(chefty.call("seat_of", host))) as Transform3D).origin
	var in_bed := _own_player().global_position.distance_to(seated_at) < 0.3
	# The client walks up and sits down too.
	_teleport(_client_id(), (chefty.call("bed_transform") as Transform3D) * Vector3(2.4, 0.5, 0.8))
	var client_in := await _until(func() -> bool: return (chefty.call("boarders") as Array).has(_client_id()), 3.0)
	# (Before everyone-aboard's beat sends it off.)
	await _seconds(Constants.CHEFTY_BOARD_ALL_ABOARD_SECONDS * 0.4)
	# Jump: over the tailgate and out; the one who called the trip leaving calls it off.
	Input.action_press(&"jump")
	await _ticks(2)
	Input.action_release(&"jump")
	await _seconds(Constants.CHEFTY_BOARD_CLIMB_SECONDS * 3.0)
	var off := not bool(chefty.call("is_boarding")) and not bool(chefty.call("is_riding")) and int(chefty.call("seat_of", host)) < 0
	var behind := (chefty.call("bed_transform") as Transform3D).affine_inverse() * _own_player().global_position
	var landed := behind.z > 2.6 and absf(behind.x) < 1.5
	var client_out := int(chefty.call("seat_of", _client_id())) < 0 and Net.player_zone(_client_id()) == Net.Zone.STORE
	_teleport(_client_id(), _store_far())
	return _step("hop_out", boarding and honked and in_bed and client_in and off and client_out and landed and Net.player_zone(host) == Net.Zone.STORE, "boarding %s, honked %s, in the bed %s, the client sat down too %s, hopped out and the trip's off %s, the client out too %s, landed behind the tailgate %s (%.1f, %.1f)" % [boarding, honked, in_bed, client_in, off, client_out, landed, behind.x, behind.z])


func _check_wait() -> bool:
	var chefty := _chefty()
	var host := Net.local_peer_id()
	var client := _client_id()
	_teleport(host, _pad() + Vector3(0.0, 0.5, 3.2))
	await _seconds(0.5)
	var started := Net.server_time()
	_world().call("request_depart")
	await _seconds(2.0)
	var waiting := bool(chefty.call("is_boarding")) and not bool(chefty.call("is_riding")) and Net.player_zone(client) == Net.Zone.STORE
	# The client walks up beside the bed (where a crew bot waits).
	var beside := (chefty.call("bed_transform") as Transform3D) * Vector3(2.4, 0.5, 0.8)
	_teleport(client, beside)
	var joined := await _until(func() -> bool: return (chefty.call("boarders") as Array).has(client), 3.0)
	var went := await _until(func() -> bool: return bool(chefty.call("is_riding")), Constants.CHEFTY_BOARD_WAIT_SECONDS)
	var took := Net.server_time() - started
	var both := Net.player_zone(host) == Net.Zone.TRANSIT and Net.player_zone(client) == Net.Zone.TRANSIT
	var early := took < Constants.CHEFTY_BOARD_WAIT_SECONDS - 0.5
	var arrived := await _until(func() -> bool: return Net.player_zone(host) == Net.Zone.LOT and Net.player_zone(client) == Net.Zone.LOT, RIDE_WAIT_SECONDS)
	return _step("wait", waiting and joined and went and both and early and arrived, "still waiting after 2 s %s, the client climbed in %s, went with everyone aboard %s after %.1f s (window %.0f s), both riding %s, at the yard %s" % [waiting, joined, went, took, Constants.CHEFTY_BOARD_WAIT_SECONDS, both, arrived])


func _check_early() -> bool:
	await _seconds(1.5)
	var chefty := _chefty()
	var owner_node := get_tree().get_first_node_in_group("homeowner") as Node3D
	if owner_node == null:
		return _step("early", false, "no homeowner on the yard")
	var host := Net.local_peer_id()
	chefty.call("accept_bags", 1, 12)
	_teleport(host, owner_node.global_position + Vector3(0.0, 0.5, 1.5))
	await _seconds(0.4)
	owner_node.call("_handle_talk", host)
	await _ticks(3)
	var looked := int(owner_node.get("_phase")) == 0 and _Strings.HOMEOWNER_LINES["not_done"].has(str((owner_node.get_node("Caption") as Label3D).text))
	owner_node.call("_handle_talk", host)
	var offered := await _until(func() -> bool: return int(owner_node.get("_phase")) == 2, 6.0)
	var prompt := str((owner_node.call("prompt") as Dictionary).get("text", ""))
	var named := prompt == _Strings.UI["prompt_take_cash"] % int(owner_node.get("_amount"))
	# Another bag lands mid-offer: she counts it in, still holding out the cash.
	var before := int(owner_node.get("_amount"))
	chefty.call("accept_bags", 1, 8)
	await _until(func() -> bool: return int(owner_node.get("_amount")) != before, 1.5)
	var after := int(owner_node.get("_amount"))
	var counted := int(owner_node.get("_phase")) == 2 and after > before and int((owner_node.get("_settlement") as Dictionary).get("bags_value", 0)) == int(chefty.call("bag_value")) \
			and str((owner_node.call("prompt") as Dictionary).get("text", "")) == _Strings.UI["prompt_take_cash"] % after
	return _step("early", looked and offered and named and counted, "first ask: a look at the yard and no cash %s; then the cash %s as \"%s\" %s; a new bag counted in, $%d -> $%d, still offered %s" % [looked, offered, prompt, named, before, after, counted])


func _check_beat() -> bool:
	var chefty := _chefty()
	var owner_node := get_tree().get_first_node_in_group("homeowner")
	var host := Net.local_peer_id()
	var client := _client_id()
	# The bagger did the work; the client did nothing.
	Campaign.record_stat(host, &"leaves_cleared", 500.0)
	_teleport(client, _lot_far())
	await _seconds(0.5)
	var credits_before := Campaign.credits(client)
	var offered := int(owner_node.get("_amount"))
	owner_node.call("_handle_take", host)
	var taken_at := Net.server_time()
	await _ticks(3)
	var held := Campaign.is_job_open() and bool(chefty.call("is_boarding")) and Campaign.credits(client) == credits_before
	# The host walks over and climbs in; the client stays out on the yard.
	_teleport(host, (chefty.call("bed_transform") as Transform3D) * Vector3(0.0, 0.5, 3.4))
	var aboard := await _until(func() -> bool: return (chefty.call("boarders") as Array).has(host), 2.0)
	var went := await _until(func() -> bool: return bool(chefty.call("is_riding")), Constants.CHEFTY_BOARD_WAIT_SECONDS + 2.0)
	var took := Net.server_time() - taken_at
	var waited := took >= Constants.CHEFTY_BOARD_WAIT_SECONDS - 0.3
	var gathered := Net.player_zone(client) == Net.Zone.TRANSIT and int(chefty.call("seat_of", client)) >= 0
	await _ticks(3)
	var settled := not Campaign.is_job_open() and str(Campaign.last_settlement().get("mood", "")) == "messy"
	var paid := Campaign.credits(client) - credits_before
	var fair := paid >= int(floor(float(offered) * Constants.CREW_SPLIT_EVEN_SHARE / 2.0))
	var home := await _until(func() -> bool: return Net.player_zone(host) == Net.Zone.STORE and Net.player_zone(client) == Net.Zone.STORE, RIDE_WAIT_SECONDS)
	return _step("beat", held and aboard and went and waited and gathered and settled and fair and home, "after the cash: unsettled and waiting %s, the host climbed in %s, went %s after %.1f s (window %.0f s) %s, the client gathered %s, settled as it left (messy) %s, the client paid $%d of $%d %s, home %s" % [held, aboard, went, took, Constants.CHEFTY_BOARD_WAIT_SECONDS, waited, gathered, settled, paid, offered, fair, home])


func _check_hold() -> bool:
	await _seconds(1.5)
	var chefty := _chefty()
	var host := Net.local_peer_id()
	var client := _client_id()
	_teleport(client, _store_far())
	_teleport(host, _pad() + Vector3(0.0, 0.5, 3.2))
	await _seconds(0.8)
	_world().call("request_depart")
	await _seconds(Constants.CHEFTY_BOARD_CLIMB_SECONDS + 0.2)
	var seated := (chefty.call("boarders") as Array).has(host) and not bool(chefty.call("is_riding"))
	var prompt := str((chefty.call("prompt") as Dictionary).get("text", ""))
	var started := Net.server_time()
	Input.action_press(&"interact")
	var went := await _until(func() -> bool: return bool(chefty.call("is_riding")), Constants.CHEFTY_BOARD_HOLD_SECONDS + 1.0)
	Input.action_release(&"interact")
	var took := Net.server_time() - started
	var alone := Net.player_zone(host) == Net.Zone.TRANSIT and Net.player_zone(client) == Net.Zone.STORE
	# Give the client a moment to see it go without it, and report.
	await _seconds(1.5)
	return _step("hold", seated and prompt == _Strings.UI["prompt_go_now"] and went and took < Constants.CHEFTY_BOARD_WAIT_SECONDS - 2.0 and alone, "seated %s with \"%s\", holding E went %s after %.1f s, just the host %s" % [seated, prompt, went, took, alone])


# ---------------------------------------------------------------- helpers

func _step(id: String, ok: bool, text: String) -> bool:
	_steps[id] = ok
	print("[DepartTest] %s %s: %s" % [id, "ok" if ok else "FAILED", text])
	return ok


func _finish(failed: String) -> void:
	var ok := failed == ""
	for id: String in STEPS:
		ok = ok and bool(_steps.get(id, false))
	result = {"ok": ok, "steps": _steps.duplicate(), "error": failed, "done": true}
	print("[DepartTest] all ok: %s%s" % [ok, "" if failed == "" else " (stopped at %s)" % failed])


func _teleport(peer_id: int, at: Vector3) -> void:
	var node := _world().get_node_or_null("%Players/" + str(peer_id)) as Node3D
	if node == null:
		return
	var xf := Transform3D(node.global_basis, at)
	if peer_id == Net.local_peer_id():
		node.call("apply_network_teleport", xf)
	else:
		node.rpc_id(peer_id, "_rpc_teleport", xf)


func _pad() -> Vector3:
	return (_world().get_node("StoreZone/TruckPad") as Node3D).global_position


## Off by the store's door, out of Chefty's walk-up.
func _store_far() -> Vector3:
	return (_world().get_node("StoreZone/StoreSpawnPoints/Spawn0") as Node3D).global_position + Vector3(0.0, 0.4, 0.0)


## Out on the yard, well away from the curb.
func _lot_far() -> Vector3:
	return (_world().get_node("LotZone") as Node3D).global_position + Vector3(-8.0, 0.6, -6.0)


func _client_id() -> int:
	for peer_id: int in Net.peer_ids():
		if peer_id != Net.local_peer_id() and not Net.is_watcher(peer_id):
			return peer_id
	return 0


func _world() -> Node:
	return get_tree().get_first_node_in_group("world")


func _chefty() -> Node:
	return get_tree().get_first_node_in_group("chefty")


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _until(check: Callable, limit_seconds: float) -> bool:
	var waited := 0.0
	while waited < limit_seconds:
		if bool(check.call()):
			return true
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return bool(check.call())
