extends RefCounted

## Authority: local, cosmetic. Pay a crewmate, in the world (shops chunk 8;
## docs/GAME.md "Shops", pay a crewmate). Every peer hears of a payment from the
## host (Shops.gave, from _rpc_gave) and, when the two stand within
## Constants.PAY_TOSS_MAX_METERS of each other in the same zone, plays it: the
## payer winds back and flicks a bill off their fingers ("flick_cash": the
## anticipation, the snap, the follow-through), the bill flutters across on an
## arc with a paper snap as it leaves, and the payee's hands come up for it
## ("catch_cash") and it goes into their pocket. Farther apart, the money just
## lands in their wallet (ui/pay_notice.gd says who sent it). Nothing here feeds
## back into the game; the cash moved on the host before any of it plays.

const _CartoonBody = preload("res://player/cartoon_body.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
## The gestures' lengths (s): the payer's flick and the payee's reach for it.
const FLICK_SECONDS: float = 0.75
const CATCH_SECONDS: float = 1.0
## Where in the flick the bill leaves the fingers (share of FLICK_SECONDS).
const FLICK_RELEASE: float = 0.4
## A bill's colors: the paper and its printed middle.
const BILL_GREEN := Color(0.45, 0.66, 0.4)
const BILL_INK := Color(0.24, 0.42, 0.24)
## Where on the payee the bill goes (m above their feet): about the hands' height
## when they reach for it.
const CATCH_HEIGHT: float = 1.15

static var _registered: bool = false
static var _bill_mesh: Mesh
## Tests: how many bills this peer has flown and seen caught.
static var flown: int = 0
static var caught: int = 0


static func register() -> void:
	if _registered:
		return
	_registered = true
	_CartoonBody.register_gesture("flick_cash", FLICK_SECONDS, _pose_flick)
	_CartoonBody.register_gesture("catch_cash", CATCH_SECONDS, _pose_catch)


## Plays one payment between two players, if they're close enough to see it.
## Returns whether a bill flew.
static func toss(tree: SceneTree, from_peer: int, to_peer: int) -> bool:
	register()
	var payer := _player(tree, from_peer)
	var payee := _player(tree, to_peer)
	if payer == null or payee == null or Net.player_zone(from_peer) != Net.player_zone(to_peer):
		return false
	if payer.global_position.distance_to(payee.global_position) > Constants.PAY_TOSS_MAX_METERS:
		return false
	var payer_body := payer.get_node_or_null("Visual/CartoonBody")
	var payee_body := payee.get_node_or_null("Visual/CartoonBody")
	if payer_body != null:
		payer_body.call("gesture", "flick_cash")
	var lead := Constants.PAY_TOSS_LEAD
	tree.create_timer(lead).timeout.connect(func() -> void:
		if not is_instance_valid(payer) or not is_instance_valid(payee):
			return
		_fly(tree, payer, payer_body, payee, payee_body)
	)
	return true


## The bill, from the payer's right hand to the payee's: a lob over the
## straight line, fluttering end over end, following the payee if they move.
static func _fly(tree: SceneTree, payer: Node3D, payer_body: Node, payee: Node3D, payee_body: Node) -> void:
	var hand := payer_body.call("pose_part", "prop_hand") as Node3D if payer_body != null else null
	var from := hand.global_position if hand != null else payer.global_position + Vector3.UP * 1.3
	var bill := _Stylized.instance(_bill(), {"roughness": 0.9, "specular": 0.05})
	bill.name = "CashBill"
	var parent := payer.get_parent()
	parent.add_child(bill)
	bill.global_position = from
	# The payee's hands come up as it's on its way.
	if payee_body != null:
		payee_body.call("gesture", "catch_cash")
	_sound(tree, "cash_flick", from)
	flown += 1
	var seconds := Constants.PAY_TOSS_SECONDS
	var spin_axis := Vector3(1.0, 0.3, 0.2).normalized()
	var flight := bill.create_tween()
	flight.tween_method(func(t: float) -> void:
		if not is_instance_valid(payee):
			return
		var to := payee.global_position + Vector3.UP * CATCH_HEIGHT
		# Eased out a touch: it slows as it drops into the hands.
		var along := 1.0 - pow(1.0 - t, 1.5)
		var at := from.lerp(to, along) + Vector3.UP * Constants.PAY_TOSS_ARC * sin(PI * t)
		bill.global_position = at
		bill.basis = Basis(spin_axis, TAU * Constants.PAY_BILL_SPINS * t) * Basis(Vector3.UP, 0.4 * sin(t * 9.0))
	, 0.0, 1.0, seconds)
	flight.tween_callback(func() -> void:
		if is_instance_valid(payee):
			_sound(tree, "pocket", payee.global_position + Vector3.UP * CATCH_HEIGHT)
			caught += 1
		bill.queue_free()
	)


## A paper bill: a thin green slip with a darker middle, flat in XZ.
static func _bill() -> Mesh:
	if _bill_mesh == null:
		var kit := _MeshKit.new()
		var half := Vector3(Constants.PAY_BILL_SIZE.x * 0.5, 0.002, Constants.PAY_BILL_SIZE.y * 0.5)
		kit.box(Vector3.ZERO, half * 2.0, BILL_GREEN)
		kit.box(Vector3.ZERO, Vector3(half.x * 1.1, half.y * 3.2, half.z * 1.2), BILL_INK)
		_bill_mesh = kit.commit()
	return _bill_mesh


## The flick: the right arm draws back (anticipation), snaps forward and up
## (the bill leaves at FLICK_RELEASE), holds out a beat, and drops back.
static func _pose_flick(body: Node3D, t: float, _delta: float) -> void:
	var arm := body.call("pose_part", "arm_r") as Node3D
	var torso := body.call("pose_part", "torso") as Node3D
	if arm == null:
		return
	var swing := 0.0
	if t < 0.25:
		swing = -0.5 * _ease(t / 0.25)
	elif t < FLICK_RELEASE:
		swing = lerpf(-0.5, 1.5, _ease((t - 0.25) / (FLICK_RELEASE - 0.25)))
	elif t < 0.7:
		swing = 1.5
	else:
		swing = lerpf(1.5, 0.0, _ease((t - 0.7) / 0.3))
	arm.rotation.x = swing
	arm.rotation.z = 0.15 * clampf(swing, 0.0, 1.0)
	if torso != null:
		torso.rotation.y = -0.18 * sin(PI * clampf(t / 0.7, 0.0, 1.0))


## The catch: both hands come up in front, cupped, as the bill arrives; then down.
static func _pose_catch(body: Node3D, t: float, _delta: float) -> void:
	var left := body.call("pose_part", "arm_l") as Node3D
	var right := body.call("pose_part", "arm_r") as Node3D
	if left == null or right == null:
		return
	var up := _ease(clampf(t / 0.45, 0.0, 1.0)) * (1.0 - _ease(clampf((t - 0.7) / 0.3, 0.0, 1.0)))
	for arm: Node3D in [left, right]:
		arm.rotation.x = 1.2 * up
	left.rotation.z = -0.25 * up
	right.rotation.z = 0.25 * up


static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func _player(tree: SceneTree, peer_id: int) -> Node3D:
	for node: Node in tree.get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


static func _sound(tree: SceneTree, id: String, at: Vector3) -> void:
	var sfx := tree.get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", id, at)
