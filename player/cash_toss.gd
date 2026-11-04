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
## About the hands' height when they reach for it (m above their feet): where the
## bill goes when a body has no hands to aim at, and where a flick is aimed.
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
	# Through your own eyes the flick is your first-person hand going out toward
	# them and back (the bill leaves it on the way).
	var payer_arms := _fp_arms(payer)
	if payer_arms != null:
		tree.create_tween().tween_method(func(t: float) -> void:
			if is_instance_valid(payee) and is_instance_valid(payer_arms):
				_reach(payer_arms, payee.global_position + Vector3.UP * CATCH_HEIGHT, sin(PI * t))
			if t >= 1.0 and is_instance_valid(payer_arms):
				payer_arms.set("reach_weight", 0.0)
		, 0.0, 1.0, FLICK_SECONDS)
	var lead := Constants.PAY_TOSS_LEAD
	tree.create_timer(lead).timeout.connect(func() -> void:
		if not is_instance_valid(payer) or not is_instance_valid(payee):
			return
		_fly(tree, payer, payer_body, payee, payee_body)
	)
	return true


## The bill, from the payer's right hand to the payee's: a lob over the
## straight line, fluttering end over end, into the payee's hands wherever they
## are by then. Through the payee's own eyes it's their first-person hand that
## comes out for it and takes it, low in the view (the body you see others
## catch with isn't drawn for you: rec_pay2_friend frame 49 had the bill fly into
## the camera); through the payer's, it leaves their first-person hand.
static func _fly(tree: SceneTree, payer: Node3D, payer_body: Node, payee: Node3D, payee_body: Node) -> void:
	var payer_arms := _fp_arms(payer)
	var from := _hand_point(payer, payer_body, payer_arms, false)
	var bill := _Stylized.instance(_bill(), {"roughness": 0.9, "specular": 0.05})
	bill.name = "CashBill"
	var parent := payer.get_parent()
	parent.add_child(bill)
	bill.global_position = from
	# The payee's hands come up as it's on its way.
	if payee_body != null:
		payee_body.call("gesture", "catch_cash")
	var payee_arms := _fp_arms(payee)
	_sound(tree, "cash_flick", from)
	flown += 1
	var seconds := Constants.PAY_TOSS_SECONDS
	var spin_axis := Vector3(1.0, 0.3, 0.2).normalized()
	var flight := bill.create_tween()
	flight.tween_method(func(t: float) -> void:
		if not is_instance_valid(payee):
			return
		# Your own hand comes up to a catching spot low in front of you (not at the
		# bill: chasing it, the hand and the bill climbed out of the top of the view
		# together, rec_pay3_friend 39-48), and the bill comes down into it.
		var own_view := payee_arms != null and payee_arms.visible
		if own_view:
			_reach(payee_arms, payee_arms.to_global(Constants.PAY_FP_CATCH_AT), smoothstep(0.0, Constants.PAY_CATCH_REACH_SHARE, t))
		var to := _hand_point(payee, payee_body, payee_arms, true)
		# Eased out a touch: it slows as it drops into the hands (not through your
		# own eyes, where that held it big just over your head). The lift dies off
		# faster than it grows, so it comes down into them, not across at head height.
		var along := t if own_view else 1.0 - pow(1.0 - t, 1.5)
		var lift := Constants.PAY_TOSS_ARC * sin(PI * pow(t, Constants.PAY_TOSS_ARC_SKEW))
		bill.global_position = from.lerp(to, along) + Vector3.UP * lift
		var settle := smoothstep(0.75, 1.0, t)
		var flutter := Basis(spin_axis, TAU * Constants.PAY_BILL_SPINS * t) * Basis(Vector3.UP, 0.4 * sin(t * 9.0))
		bill.basis = Basis(flutter.get_rotation_quaternion().slerp(_held_basis(payee, payee_arms).get_rotation_quaternion(), settle))
	, 0.0, 1.0, seconds)
	# Caught: the pocket sound on contact, the bill folds away into the hand as
	# the hand drops back.
	flight.tween_callback(func() -> void:
		if is_instance_valid(payee):
			_sound(tree, "pocket", bill.global_position)
			caught += 1
	)
	flight.tween_method(func(t: float) -> void:
		if not is_instance_valid(payee):
			return
		bill.global_position = _hand_point(payee, payee_body, payee_arms, true)
		bill.basis = _held_basis(payee, payee_arms).scaled(Vector3.ONE * maxf(1.0 - t, 0.01))
		if payee_arms != null:
			_reach(payee_arms, bill.global_position, 1.0 - t)
	, 0.0, 1.0, Constants.PAY_CATCH_HOLD)
	flight.tween_callback(func() -> void:
		if payee_arms != null and is_instance_valid(payee_arms):
			payee_arms.set("reach_weight", 0.0)
			payee_arms.set("reach_at", Vector3.INF)
		bill.queue_free()
	)


## Where a player's catching (or flicking) hand is, in the world: your own
## first-person hand when it's you looking (arms drawn), else the body's hands
## (both, cupped, for a catch; the right for a flick).
static func _hand_point(player: Node3D, body: Node, arms: Node3D, catching: bool) -> Vector3:
	if arms != null and arms.visible:
		return arms.to_global(arms.call("hand_point", 1) as Vector3)
	var right := body.call("pose_part", "prop_hand") as Node3D if body != null else null
	if right == null:
		return player.global_position + Vector3.UP * CATCH_HEIGHT
	if not catching:
		return right.global_position
	var left := body.call("pose_part", "prop_hand_l") as Node3D
	return right.global_position if left == null else right.global_position.lerp(left.global_position, 0.5)


## The way a bill lies in the hand that has it: flat, across the palm.
static func _held_basis(player: Node3D, arms: Node3D) -> Basis:
	if arms != null and arms.visible:
		return arms.global_basis.orthonormalized()
	return Basis(Vector3.UP, player.global_rotation.y)


## Your first-person arms (only on your own peer), or null.
static func _fp_arms(player: Node3D) -> Node3D:
	if player == null or not player.is_multiplayer_authority():
		return null
	var arms := player.get_node_or_null("%Head/Arms") as Node3D
	return arms if arms != null and arms.has_method("hand_point") else null


## A first-person hand out toward a point (first_person_arms.gd's reach).
static func _reach(arms: Node3D, at: Vector3, weight: float) -> void:
	if not is_instance_valid(arms):
		return
	arms.set("reach_side", 1)
	arms.set("reach_at", at)
	arms.set("reach_weight", clampf(weight, 0.0, 1.0))


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
