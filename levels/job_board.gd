extends Node3D

## Authority: host. The job board at Homie Depot: a cork board by the checkout
## with a few job offers pinned to it. Each offer is a yard (a seed for
## levels/lots/lot_generator.gd) and the work the homeowner wants done. Anyone
## can walk up, press E, and pick which one Chefty drives to next; the host
## checks the pick and tells everyone. New offers go up each time the crew is
## back at the store, and buying a tool re-reads them, so a job that needed that
## tool can now ask for it.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Strings = preload("res://ui/strings.gd")

signal offers_changed

## Where the board stands in the store zone, and how close counts as at it.
const BOARD_AT := Vector3(-4.6, 0.0, -8.6)
const REACH := 2.4
const CORK := Color(0.72, 0.53, 0.33)
const FRAME := Color(0.42, 0.28, 0.17)
const PAPER := Color(0.98, 0.96, 0.9)
const PIN := Color(0.85, 0.18, 0.15)
## Height of the cards' centers on the board.
const CARD_Y: float = 1.42

## Every offer: {"seed", "tasks", "house", "size"}. Same on every peer.
var offers: Array = []
## Which offer is picked. The first is picked until someone chooses.
var chosen: int = 0

var _cards: Array[Label3D] = []
var _pins: Array[Node3D] = []
var _rating: Label3D


func _ready() -> void:
	add_to_group("job_board")
	add_to_group("prompt_sources")
	var store := get_parent().get_node_or_null("StoreZone") as Node3D
	if store != null:
		global_position = store.to_global(BOARD_AT)
	_build_board()
	Net.player_joined.connect(_on_player_joined)
	if Net.is_host():
		Campaign.unlocks_changed.connect(_on_tools_changed)
		refresh()
	elif multiplayer.multiplayer_peer != null:
		# The host's first offers may have gone out before this board existed.
		_rpc_request_offers.rpc_id(1)


## Host: put new offers up.
func refresh() -> void:
	if not Net.is_host():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var made: Array = []
	for index: int in Constants.JOB_BOARD_OFFERS:
		made.append(make_offer(rng.randi_range(1, 2147483646)))
	_rpc_offers.rpc(made, 0)


## The offer Chefty drives to next.
func current() -> Dictionary:
	if offers.is_empty():
		return {}
	return offers[clampi(chosen, 0, offers.size() - 1)]


## The local player picks an offer.
func request_choose(index: int) -> void:
	if Net.is_host():
		_handle_choose(index)
	else:
		_rpc_request_choose.rpc_id(1, index)


## Host only. One offer from its seed: the yard, its house number, its size,
## and the work. The same seed and the same tools always give the same offer.
## --all-tasks asks for everything (tests).
static func make_offer(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var house := rng.randi_range(12, 4980)
	var size := _pick_size(rng)
	if int(Net.dev_options().get("yard_size")) >= 0:
		size = clampi(int(Net.dev_options().get("yard_size")), 0, 2)
	return {"seed": seed_value, "house": house, "size": size, "tasks": choose_tasks(rng, size)}


## How big the yard is: 0 small, 1 regular, 2 big. Bigger yards ask for more.
static func _pick_size(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	var weights: Array = Constants.YARD_SIZE_CHANCE.duplicate()
	# A crew with a good name gets the big jobs more often.
	var shift := minf(float(weights[1]), Constants.YARD_BIG_PER_STAR * maxf(0.0, Campaign.rating() - 3.0))
	weights[1] = float(weights[1]) - shift
	weights[2] = float(weights[2]) + shift
	var total := 0.0
	for index: int in weights.size():
		total += float(weights[index])
		if roll < total:
			return index
	return 1


## What the homeowner wants done: always the leaves, plus a couple more (more
## for a big yard). Mostly work the crew owns the tool for, now and then
## something they don't (it shows as needing that tool, so it's worth buying),
## and always some bare-hands work.
static func choose_tasks(rng: RandomNumberGenerator, size: int = 1) -> PackedStringArray:
	var chosen_tasks := PackedStringArray(["rake_leaves"])
	var owned := Campaign.crew_tools()
	var possible: Array[String] = []
	var unowned: Array[String] = []
	for task: String in Constants.TASK_TOOLS:
		if task == "rake_leaves":
			continue
		# Only big yards have a pool.
		if task == "skim_pool" and size != 2:
			continue
		var tool := str(Constants.TASK_TOOLS[task])
		if bool(Net.dev_options().get("all_tasks")) or tool == "" or owned.has(tool):
			possible.append(task)
		else:
			unowned.append(task)
	if bool(Net.dev_options().get("all_tasks")):
		chosen_tasks.append_array(PackedStringArray(possible))
		return chosen_tasks
	var count := rng.randi_range(Constants.JOB_EXTRA_TASKS.x, Constants.JOB_EXTRA_TASKS.y) + int(Constants.YARD_EXTRA_TASKS[size])
	# Now and then one of them needs a tool the crew doesn't have yet.
	var wants_unowned := rng.randf() < 0.3
	var pick_unowned := rng.randi()
	if wants_unowned and not unowned.is_empty():
		chosen_tasks.append(unowned[pick_unowned % unowned.size()])
	_shuffle(possible, rng)
	for task: String in possible:
		if chosen_tasks.size() - 1 >= count:
			break
		chosen_tasks.append(task)
	return chosen_tasks


static func _shuffle(items: Array[String], rng: RandomNumberGenerator) -> void:
	for index: int in range(items.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap := items[index]
		items[index] = items[other]
		items[other] = swap


## What the tasks pay at most, not counting the leaves (those pay by the bag).
static func task_pay(offer: Dictionary) -> int:
	var total := 0
	for task: String in (offer.get("tasks", PackedStringArray()) as PackedStringArray):
		total += int(Constants.TASK_PAY.get(task, 0))
	return total


## The prompt while the local player stands at the board, or empty.
func prompt() -> Dictionary:
	if not _local_near():
		return {}
	return {"text": _Strings.UI["prompt_job_board"], "at": global_position + Vector3(0.0, 2.3, 0.4)}


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _local_near():
		return
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null:
		ui.call("open_job_board")
		get_viewport().set_input_as_handled()


func _local_near() -> bool:
	if Net.player_zone(Net.local_peer_id()) != Net.Zone.STORE:
		return false
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			var flat := (node as Node3D).global_position - global_position
			flat.y = 0.0
			return flat.length() < REACH
	return false


# ---------------------------------------------------------------- host

func _handle_choose(index: int) -> void:
	if index < 0 or index >= offers.size() or index == chosen:
		return
	# Once Chefty is on the way, the job is set.
	var lot_slot := get_tree().get_first_node_in_group("world")
	if lot_slot != null and bool(lot_slot.call("job_locked")):
		return
	_rpc_offers.rpc(offers, index)
	lot_slot.call("reload_job_lot")


## Buying a tool can change what a homeowner asks for: re-read every offer from
## its seed, keeping the pick.
func _on_tools_changed() -> void:
	var world := get_tree().get_first_node_in_group("world")
	if offers.is_empty() or (world != null and bool(world.call("job_locked"))):
		return
	var made: Array = []
	var changed := false
	for offer: Dictionary in offers:
		var again := make_offer(int(offer["seed"]))
		changed = changed or (again["tasks"] as PackedStringArray) != (offer["tasks"] as PackedStringArray)
		made.append(again)
	if not changed:
		return
	_rpc_offers.rpc(made, chosen)
	if world != null:
		world.call("reload_job_lot")


func _on_player_joined(peer_id: int) -> void:
	if Net.is_host() and peer_id != Net.local_peer_id():
		_rpc_offers.rpc_id(peer_id, offers, chosen)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_offers() -> void:
	if Net.is_host():
		_rpc_offers.rpc_id(multiplayer.get_remote_sender_id(), offers, chosen)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_choose(index: int) -> void:
	if Net.is_host():
		_handle_choose(index)


@rpc("authority", "call_local", "reliable")
func _rpc_offers(all: Array, pick: int) -> void:
	offers = all
	chosen = pick
	_refresh_cards()
	offers_changed.emit()


# ---------------------------------------------------------------- the board

## A cork board on two legs with a little roof, and a paper card per offer.
func _build_board() -> void:
	var kit := _MeshKit.new()
	for x: float in [-1.25, 1.25]:
		kit.rbox(Vector3(x, 1.0, 0.0), Vector3(0.07, 1.0, 0.07), FRAME, 4.0)
	kit.rbox(Vector3(0.0, 1.55, 0.0), Vector3(1.3, 0.72, 0.06), FRAME, 6.0)
	kit.rbox(Vector3(0.0, 1.55, 0.04), Vector3(1.2, 0.63, 0.04), CORK, 4.0)
	kit.rbox(Vector3(0.0, 2.35, 0.05), Vector3(1.45, 0.06, 0.28), Color(0.93, 0.47, 0.13), 6.0, {"basis": Basis(Vector3.RIGHT, 0.25)})
	for index: int in Constants.JOB_BOARD_OFFERS:
		kit.box(Vector3(_card_x(index), CARD_Y, 0.085), Vector3(0.62, 0.66, 0.012), PAPER, Basis(Vector3.BACK, _card_tilt(index)))
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.85, "specular": 0.1})
	view.name = "Board"
	add_child(view)
	var title := Label3D.new()
	title.text = _Strings.UI["board_title"]
	title.font_size = 48
	title.pixel_size = 0.004
	title.modulate = Color(1.0, 0.97, 0.9)
	title.outline_size = 12
	title.outline_modulate = FRAME
	title.position = Vector3(0.0, 1.98, 0.1)
	add_child(title)
	_rating = Label3D.new()
	_rating.font_size = 32
	_rating.pixel_size = 0.004
	_rating.modulate = Color(1.0, 0.82, 0.25)
	_rating.outline_size = 10
	_rating.outline_modulate = FRAME
	_rating.position = Vector3(0.0, 2.22, 0.14)
	add_child(_rating)
	Campaign.rating_changed.connect(_refresh_cards)
	for index: int in Constants.JOB_BOARD_OFFERS:
		var x := _card_x(index)
		var tilt := _card_tilt(index)
		var card := Label3D.new()
		card.font_size = 30
		card.pixel_size = 0.0026
		card.modulate = Color(0.17, 0.14, 0.11)
		card.outline_size = 0
		card.width = 220.0
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.position = Vector3(x, CARD_Y - 0.03, 0.1)
		card.rotation.z = tilt
		add_child(card)
		_cards.append(card)
		var pin := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.035
		ball.height = 0.07
		pin.mesh = ball
		var red := StandardMaterial3D.new()
		red.albedo_color = PIN
		pin.material_override = red
		pin.position = Vector3(x, CARD_Y + 0.27, 0.12)
		add_child(pin)
		_pins.append(pin)
	_refresh_cards()


func _card_x(index: int) -> float:
	return (float(index) - float(Constants.JOB_BOARD_OFFERS - 1) * 0.5) * 0.78


func _card_tilt(index: int) -> float:
	return [-0.05, 0.03, 0.06][index % 3]


func _refresh_cards() -> void:
	if _rating != null:
		_rating.text = _Strings.stars(Campaign.rating()) if Campaign.rating_count() > 0 else ""
	for index: int in _cards.size():
		var card := _cards[index]
		if index >= offers.size():
			card.text = ""
			continue
		var offer: Dictionary = offers[index]
		var lines := PackedStringArray()
		lines.append(_Strings.UI["board_house"] % int(offer["house"]))
		lines.append(_Strings.UI["board_size_%d" % int(offer.get("size", 1))])
		lines.append(_Strings.UI["board_tasks"] % ((offer["tasks"] as PackedStringArray).size()))
		lines.append(_Strings.UI["board_pay_short"] % task_pay(offer))
		if index == chosen:
			lines.append(_Strings.UI["board_picked"])
		card.text = "\n".join(lines)
		_pins[index].scale = Vector3.ONE * (1.6 if index == chosen else 1.0)
