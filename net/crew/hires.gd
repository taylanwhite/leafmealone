extends Node

## Authority: host. Hired hands (docs/SPINE.md, "Hiring"). Hiring opens at
## Hedge Hog III ("feature:hiring" in core/ranks.gd); one slot, and the
## hire_slot perks add more. A hand costs a signing fee from whoever hires them
## and a daily wage at bedtime, split across the crew. If the crew can't cover
## the wages, the hand quits with a text. Hands ride along on every job
## (npcs/crew_hand.gd) and rake, bag, and haul. Saved with the campaign.

signal changed

const HAND_SCENE: PackedScene = preload("res://npcs/crew_hand.tscn")
## Nicknames, because nobody on a leaf crew goes by their real name.
const NAMES: Array[String] = [
	"Big Sal", "Tiny Dom", "Moose", "Lefty", "Squints", "Dutch", "Pep", "Bunny",
	"Hambone", "Socks", "Noodles", "Biscuit", "Shades", "Rooster", "Pickles", "Boots",
]

## Every hand: {name, skill, wage, look, hired_day, bags, earned}.
var hands: Array = []

var _next_look: int = 1


func _ready() -> void:
	add_to_group("hires")
	Net.player_joined.connect(_on_player_joined)
	if not Net.is_host():
		if multiplayer.multiplayer_peer != null:
			_rpc_request_state.rpc_id(1)
		return
	var saved := Campaign.save_section("hires")
	for entry: Variant in (saved.get("hands", []) as Array):
		var hand := (entry as Dictionary).duplicate()
		hand["skill"] = float(hand.get("skill", 0.7))
		hand["wage"] = int(hand.get("wage", Constants.HIRE_DAILY_WAGE))
		hand["look"] = int(hand.get("look", 1))
		hand["bags"] = int(hand.get("bags", 0))
		hand["earned"] = int(hand.get("earned", 0))
		hands.append(hand)
	_next_look = int(saved.get("next_look", hands.size() + 1))
	Campaign.add_save_hook(_save_section)
	_broadcast()


func _exit_tree() -> void:
	Campaign.remove_save_hook(_save_section)


## How many hands the crew can have now.
func slots() -> int:
	if not Campaign.is_feature_on("hiring"):
		return 0
	var count := 1
	for perk: String in ["hire_slot_2", "hire_slot_3", "hire_slot_4"]:
		if Campaign.has_perk(perk):
			count += 1
	return count


func can_hire() -> bool:
	return hands.size() < slots()


## The local player hires the next hand (signing fee from their own cash).
func request_hire() -> void:
	if Net.is_host():
		_handle_hire(Net.local_peer_id())
	else:
		_rpc_request_hire.rpc_id(1)


## Let a hand go.
func request_fire(hand_name: String) -> void:
	if Net.is_host():
		_handle_fire(hand_name)
	else:
		_rpc_request_fire.rpc_id(1, hand_name)


## Host: the crew reached a yard. Every hand hops off Chefty and gets to work.
func spawn_on_lot() -> void:
	if not Net.is_host():
		return
	despawn()
	var world := get_tree().get_first_node_in_group("world")
	var truck := get_tree().get_first_node_in_group("chefty")
	if world == null or truck == null:
		return
	var npcs := world.get_node("Npcs")
	var at: Vector3 = truck.call("body_position")
	for index: int in hands.size():
		var hand: Dictionary = hands[index]
		var node: CharacterBody3D = HAND_SCENE.instantiate()
		node.name = "Hand%d" % (index + 1)
		node.set("hand_name", str(hand["name"]))
		node.set("look_seed", int(hand["look"]))
		node.set("skill", float(hand["skill"]))
		npcs.add_child(node, true)
		node.global_position = Vector3(at.x - 1.5 + float(index) * 1.0, at.y + 0.2, at.z - 2.6)


## Host: the job's over (paid, or the yard went away). Back on the truck.
func despawn() -> void:
	if not Net.is_host():
		return
	for node: Node in get_tree().get_nodes_in_group("crew_hands"):
		node.queue_free()


## A hand loaded a bag into Chefty (npcs/crew_hand.gd).
func note_bag(hand_name: String, value: int) -> void:
	for hand: Dictionary in hands:
		if str(hand["name"]) == hand_name:
			hand["bags"] = int(hand.get("bags", 0)) + 1
			hand["earned"] = int(hand.get("earned", 0)) + value


## Host, at bedtime (net/day/day_clock.gd): pay everyone. Returns what happened.
func pay_wages() -> Dictionary:
	if not Net.is_host() or hands.is_empty():
		return {}
	var peers := Net.peer_ids()
	var total := 0
	for hand: Dictionary in hands:
		total += int(hand["wage"])
	var cash := 0
	for peer_id: int in peers:
		cash += Campaign.credits(peer_id)
	var quit: Array = []
	# Can't make payroll: the newest hands walk first.
	while total > cash and not hands.is_empty():
		var leaving: Dictionary = hands.pop_back()
		total -= int(leaving["wage"])
		quit.append(str(leaving["name"]))
		_text(str(leaving["name"]), "No pay, no rake. I'm out. Tell %s I said bye." % _random_other())
	if total > 0 and not peers.is_empty():
		# Split evenly; anyone short leaves the rest to the others.
		var owed := total
		var share := int(ceil(float(total) / float(peers.size())))
		for peer_id: int in peers:
			var paid := mini(share, mini(owed, Campaign.credits(peer_id)))
			Campaign.call("_add_credits", peer_id, -paid)
			owed -= paid
		for peer_id: int in peers:
			if owed <= 0:
				break
			var paid := mini(owed, Campaign.credits(peer_id))
			Campaign.call("_add_credits", peer_id, -paid)
			owed -= paid
		for peer_id: int in peers:
			Campaign.call("_send_wallet", peer_id)
	_broadcast()
	return {"wages": total, "quit": quit}


# ---------------------------------------------------------------- host

func _handle_hire(peer_id: int) -> void:
	if not can_hire():
		return
	if Campaign.credits(peer_id) < Constants.HIRE_SIGNING_FEE:
		return
	Campaign.call("_add_credits", peer_id, -Constants.HIRE_SIGNING_FEE)
	Campaign.call("_send_wallet", peer_id)
	var taken := {}
	for hand: Dictionary in hands:
		taken[str(hand["name"])] = true
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pick := ""
	for attempt: int in 40:
		pick = NAMES[rng.randi() % NAMES.size()]
		if not taken.has(pick):
			break
	var clock := get_tree().get_first_node_in_group("day_clock")
	var hand := {
		"name": pick,
		"skill": rng.randf_range(Constants.HIRE_SKILL.x, Constants.HIRE_SKILL.y),
		"wage": Constants.HIRE_DAILY_WAGE,
		"look": _next_look * 7907 + 13,
		"hired_day": int(clock.get("day")) if clock != null else 1,
		"bags": 0,
		"earned": 0,
	}
	_next_look += 1
	hands.append(hand)
	_text(pick, "Thanks for the gig, boss. I'll be on the truck. I bring my own rake (it's yours now).")
	Campaign.save_now()
	_broadcast()


func _handle_fire(hand_name: String) -> void:
	for index: int in hands.size():
		if str((hands[index] as Dictionary)["name"]) == hand_name:
			hands.remove_at(index)
			_text(hand_name, "Fine. FINE. I'm keeping the gloves.")
			Campaign.save_now()
			_broadcast()
			return


func _random_other() -> String:
	return str(NAMES[randi() % NAMES.size()])


func _text(from: String, body: String) -> void:
	var town := get_tree().get_first_node_in_group("town")
	if town != null:
		town.call("_text", from, "hire", body, -1)


func _save_section() -> Dictionary:
	return {"hires": {"hands": hands, "next_look": _next_look}}


func _broadcast() -> void:
	_rpc_state.rpc(hands)


func _on_player_joined(peer_id: int) -> void:
	if Net.is_host() and peer_id != Net.local_peer_id():
		_rpc_state.rpc_id(peer_id, hands)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if Net.is_host():
		_rpc_state.rpc_id(multiplayer.get_remote_sender_id(), hands)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_hire() -> void:
	if Net.is_host():
		_handle_hire(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_fire(hand_name: String) -> void:
	if Net.is_host():
		_handle_fire(hand_name)


@rpc("authority", "call_local", "reliable")
func _rpc_state(all: Array) -> void:
	hands = all
	changed.emit()
