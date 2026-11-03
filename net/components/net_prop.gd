extends RigidBody3D

const _PropLooks = preload("res://props/prop_looks.gd")
const _MoneyPopup = preload("res://ui/money_popup.gd")
const _WaterSources = preload("res://net/work/water_sources.gd")
const _Hotbar = preload("res://net/components/hotbar.gd")
const _ToolTiers = preload("res://core/tool_tiers.gd")
const _BedToss = preload("res://net/components/bed_toss.gd")
const _BedLoad = preload("res://props/truck_bed_load.gd")
const _Strings = preload("res://ui/strings.gd")
const _CarryView = preload("res://props/carry_view.gd")
const _JunkBed = preload("res://net/components/junk_bed.gd")

## Authority: host
## Clients freeze the body and display the replicated transform. The carrier's own client
## draws the visual at the hand until the host releases it.

@export var color: Color = Color(0.55, 0.42, 0.28, 1):
	set(value):
		color = value
		_apply_color()
## Words shown above the box until it has a real model.
@export var label: String = "":
	set(value):
		label = value
		_refresh_label()
## leaf_bag, wheelbarrow, rake, trash, or gnome. Replicated so a thrown bag knows what it hit.
@export var kind: String = "":
	set(value):
		kind = value
		_refresh_label()
## Bags sitting in a wheelbarrow. The bags themselves are freed. Replicated.
@export var stored_bags: int = 0:
	set(value):
		stored_bags = value
		_refresh_label()
## Peer id holding this prop in hand, or 0. Replicated. Every peer stamps when it
## comes into someone's hands (meta drawn_msec, and drawn_from_pocket when it came
## out of a pocket), which times the draw (props/prop_looks.gd draw_dip, _blend_put).
@export var held_by: int = 0:
	set(value):
		if value != held_by:
			var now := Time.get_ticks_msec()
			if value != 0:
				set_meta("drawn_msec", now)
				set_meta("drawn_from_pocket", pocketed_by != 0 or now - int(get_meta("unpocketed_msec", -100000)) < Constants.HOTBAR_STAMP_FRESH_MS)
			else:
				set_meta("unheld_msec", now)
		held_by = value
## Peer id with this prop in a pocket (not in hand), or 0 (net/components/hotbar.gd).
## Replicated. "Lying free in the world" is is_loose(), never held_by == 0 alone.
## Every peer stamps when it goes in (meta stowed_msec, stowed_from_hand) and puts
## its look back to normal when it comes out (prop_looks.gd unstow).
@export var pocketed_by: int = 0:
	set(value):
		if value != pocketed_by:
			var now := Time.get_ticks_msec()
			if value != 0:
				set_meta("stowed_msec", now)
				set_meta("stowed_from_hand", held_by != 0 or now - int(get_meta("unheld_msec", -100000)) < Constants.HOTBAR_STAMP_FRESH_MS)
			else:
				set_meta("unpocketed_msec", now)
		var was := pocketed_by
		pocketed_by = value
		if was != 0 and value == 0:
			_PropLooks.unstow(self)
## Its hotbar slot while held or pocketed, -1 when it's in nobody's slot (loose,
## or a big item in both hands). Replicated.
@export var pocket_slot: int = -1
## A leaf bag's worth in dollars, set by the host from the leaves that went in. Replicated.
@export var value: int = 0:
	set(new_value):
		value = new_value
		_refresh_label()
## Dollars' worth of the bags sitting in a wheelbarrow. Replicated.
@export var stored_value: int = 0:
	set(new_value):
		stored_value = new_value
		_refresh_label()

## A hose's water: the kind of source it's hooked up to ("chefty", "spigot",
## "hydrant"), or "" when it isn't. Replicated.
@export var hose_source: String = ""
## True while a tool is running: water coming out of a hose or pressure washer,
## a blower blowing, a trimmer or roller working, or a mower's engine on. Replicated.
@export var spraying: bool = false
## A pressure washer's tank, or a paint roller's paint, 0 to 100. Replicated.
@export var water: float = 100.0
## A ladder set up against the house: where its top rests (world space), or zero
## when it isn't set up. Its position is its foot. Replicated.
@export var ladder_top := Vector3.ZERO
## A tool's tier: 0 used, 1 stock, 2 Mk II, 3 Mk III (core/tool_tiers.gd). The
## host sets it from the best one the crew owns. Replicated; the look and
## name follow it.
@export var tier: int = 1:
	set(value):
		tier = value
		_refresh_label()
## A gas tool's tank, 0 to 100 (Constants.GAS_TOOLS). Burns while it runs; at 0
## it sputters and dies until someone fills it from the gas can. Replicated.
@export var fuel: float = 100.0

var _airborne: bool = false
var _spray_left: float = 0.0
var _pulls: int = 0
## Who and what a running mower already hit, and when, so each happens once.
var _mower_hit_at: Dictionary = {}
## A snapped hose's loose end whipping from where it was hooked up: from, how far along, who it hit.
var _whip_from := Vector3.ZERO
var _whip_t: float = -1.0
var _whipped: Array[Node] = []
## Who threw this, and when, so a throw can't bonk its own thrower right away.
var _thrower: int = 0
## A running mower let go of: how long it keeps driving, and which way.
var _runaway_left: float = 0.0
var _runaway_dir := Vector3.FORWARD
var _runaway_stuck: float = 0.0
var _runaway_last := Vector3.INF
var _thrown_at: float = 0.0
## Everyone this throw already hit, so one throw bonks each person once.
var _bonked: Array[Node] = []
## A leaf bag Chefty's bed caught, on its way into its spot in the load (every
## peer, from _rpc_bed_catch). Each peer glides its own look there in the bed's
## space (the host moves the body, a client its drawn look, from wherever it was
## drawn), so it never jumps: the spot, the glide (bed_toss.gd settle_plan(),
## over the rail when it has to go over), how far along, whether it has landed,
## and the crew's reaction to show when it does ([speaker peer, line], or []).
var _settling: bool = false
var _settle_slot: int = -1
var _settle_plan: Dictionary = {}
var _settle_seconds: float = 0.3
var _settle_age: float = 0.0
var _settle_landed: bool = false
var _settle_amount: int = 0
var _settle_quip: Array = []
## How far from its spot this peer last drew it (m), read by props/truck_bed_load.gd
## when the load's bag takes its place: anything but about 0 would be a pop.
var settle_gap_m: float = INF
## Client: where this bag's look was last drawn and how fast it was going, so a
## catch glides on from there.
var _seen_at := Vector3.INF
var _seen_vel := Vector3.ZERO
## Client: its own toss, drawn flying at once instead of a round trip later
## (_predict_toss): where the body would be, how fast, how it tumbles, the
## ground it lands on, how long it has flown, whether it came down, and how long
## it has waited there for the host's bag to catch up.
var _predicting: bool = false
var _pred_pos := Vector3.ZERO
var _pred_vel := Vector3.ZERO
var _pred_basis := Basis.IDENTITY
var _pred_spin := Vector3.ZERO
var _pred_ground: float = 0.0
var _pred_age: float = 0.0
var _pred_done: bool = false
var _pred_wait: float = 0.0
## Client: easing the look from where it drew it onto the host's bag.
var _blend_from := Transform3D.IDENTITY
var _blend_left: float = 0.0
## Client: its own toss went into the bed as it drew it, so it started gliding
## into the load before the host said so; how long it has waited for the word.
var _provisional: bool = false
var _provisional_age: float = 0.0
## Host: where this throw's thrower stood, and when a full bed last batted it out.
var _toss_feet := Vector3.INF
var _refused_at: float = -100.0
## Host: the thrower a tossed bag passes through on its way out, and for how long.
var _cleared_from: Node = null
var _cleared_left: float = 0.0
## Host, junk: its fall speed last tick and when it last landed (the landing thud).
var _junk_last_fall: float = 0.0
var _junk_landed_ms: int = 0
## Host: when a long toss last got the crew's reaction.
static var _long_quip_at: float = -100.0

const GRAB_REACH: float = 2.4
const PUSH_REACH: float = 1.1


func _enter_tree() -> void:
	add_to_group("props")
	# After players (100): a held tool follows its holder's head on the same tick.
	process_physics_priority = 110


func _ready() -> void:
	_apply_color()
	_refresh_label()
	# The host watches what a thrown item actually touches (a set-up ladder, say).
	if multiplayer.multiplayer_peer == null or Net.is_host():
		contact_monitor = true
		max_contacts_reported = 4
	# A fresh bag pops its worth where it was filled.
	if kind == "leaf_bag" and value > 0:
		_MoneyPopup.pop(get_tree(), global_position + Vector3(0.0, 1.0, 0.0), value)
	if multiplayer.multiplayer_peer != null and not Net.is_host():
		freeze = true


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	# A carried prop must not stay solid. Moving a colliding body into the player launches them.
	_set_solid(is_loose())
	if Net.is_host() and ladder_top != Vector3.ZERO:
		freeze = true
	_refresh_label()
	# Your own bag through your own eyes (props/carry_view.gd), from the first
	# time this peer holds it.
	if kind == "leaf_bag" and held_by != 0 and held_by == Net.local_peer_id() and get_node_or_null("CarryView") == null:
		add_child(_CarryView.new())
	if pocketed_by == 0:
		_pose_look()
	else:
		# In someone's pocket: worn on their body (a stowed rake isn't raking, so its
		# head stops counting for the leaves; pose_stowed unpublishes it).
		_PropLooks.pose_stowed(self, _player(pocketed_by), pocketed_by == Net.local_peer_id())
	if Net.is_host():
		_host_step()
	elif kind == "leaf_bag":
		_client_bag_step(get_physics_process_delta_time())
	elif held_by == Net.local_peer_id() and not _settling:
		var player := _player(held_by)
		if player != null:
			%Visual.global_position = _hold_position(player)


## A client draws a leaf bag itself whenever waiting on the host would show:
## in its own hands (where the host hangs it, without the round trip), flying
## from its hands the moment it lets go (_predict_toss), gliding into Chefty's
## load, and easing back onto the host's bag after a flight that missed.
## Otherwise NetSmoother draws it, and this keeps track of how it moves so a
## catch can carry on from there.
func _client_bag_step(delta: float) -> void:
	var visual := %Visual as Node3D
	# While this peer draws it, the look stands on its own: the body under it jumps
	# with every snapshot, and would carry a child along with it.
	var own := is_riding_visual()
	if visual.top_level != own:
		var drawn := visual.global_transform
		visual.top_level = own
		visual.global_transform = drawn
	if _settling:
		_step_settle(delta)
		if _provisional:
			_provisional_age += delta
			if _provisional_age > Constants.BAG_TOSS_PROVISIONAL_SECONDS:
				_abort_provisional()
	elif _predicting:
		_step_predict(delta)
	elif _blend_left > 0.0:
		_blend_left = maxf(_blend_left - delta, 0.0)
		var share := smoothstep(0.0, 1.0, 1.0 - _blend_left / Constants.BAG_TOSS_BLEND_SECONDS)
		visual.global_transform = _blend_from.interpolate_with(global_transform * _visual_rest(), share)
	elif held_by == Net.local_peer_id():
		var player := _player(held_by)
		if player != null:
			# Hung the way the host hangs it (_host_step): its body at the hands, upright.
			visual.global_transform = Transform3D(Basis(Vector3.UP, player.global_rotation.y), _hold_position(player)) * _visual_rest()
	var at := visual.global_position
	if _seen_at.is_finite() and delta > 0.0:
		_seen_vel = _seen_vel.lerp((at - _seen_at) / delta, 0.5)
	_seen_at = at


## A leaf bag in this peer's own hands, as this peer draws it: held by this
## peer and not already flying from them or gliding into the load on its own
## say-so (a client's toss leaves its hands before the host hears of it). For
## props/carry_view.gd and player/first_person_arms.gd.
func fp_carried() -> bool:
	return kind == "leaf_bag" and multiplayer.multiplayer_peer != null and held_by != 0 and held_by == Net.local_peer_id() and pocketed_by == 0 and not _predicting and not _settling


## A leaf bag in the air, as this peer sees it: no price tag, and nobody's
## offered to pick it up (player.gd _best_pickup).
func is_flying() -> bool:
	if kind != "leaf_bag":
		return false
	if multiplayer.multiplayer_peer == null or Net.is_host():
		return linear_velocity.length() > Constants.BAG_TOSS_LABEL_HIDE_SPEED
	return _predicting or _blend_left > 0.0 or _seen_vel.length() > Constants.BAG_TOSS_LABEL_HIDE_SPEED


## Where the look sits on the body (the box's middle, VISUAL_HEIGHT up).
func _visual_rest() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, _PropLooks.VISUAL_HEIGHT, 0.0))


## Every peer: the look follows its holder's hands (props/prop_looks.gd).
func _pose_look() -> void:
	if kind == "rake":
		# Everyone poses it from the holder's swing (equipment/rake_stroke.gd), not
		# from this peer's own input.
		_PropLooks.pose_rake(self, _player(held_by) if held_by != 0 else null, false)
	elif kind == "ladder" and ladder_top != Vector3.ZERO:
		_PropLooks.pose_ladder_up(self, ladder_top)
	elif Constants.TOOL_PRICES.has(kind):
		_PropLooks.pose_tool(self, _player(held_by) if held_by != 0 else null)
	elif not _PropLooks.hold_of(self).is_empty():
		# The gnome, trash can, sign and wheelbarrow (and junk, by its type): held
		# the way the HOLDS table says.
		_PropLooks.pose_held(self, _player(held_by) if held_by != 0 else null)


## Lying free in the world: nobody holds it or has it in a pocket, and it isn't
## a bag settling into Chefty's load. Any check that means "free to pick up, mow
## over, load" uses this.
func is_loose() -> bool:
	return held_by == 0 and pocketed_by == 0 and not _settling


## A leaf bag Chefty's bed caught, on its way into the load (every peer).
func is_settling() -> bool:
	return _settling


## NetSmoother asks: a client places a leaf bag's look itself while it's in its
## own hands, flying from them, settling into the load or easing back onto the
## host's bag (_client_bag_step), so the smoother leaves it alone then.
func is_riding_visual() -> bool:
	if kind != "leaf_bag" or multiplayer.multiplayer_peer == null or Net.is_host():
		return false
	return _settling or _predicting or _blend_left > 0.0 or held_by == Net.local_peer_id()


## Host (net/components/hotbar.gd): into this peer's pocket. It keeps its slot;
## a tool stops running, except a hose, which stays hooked up.
func host_pocket(peer_id: int) -> void:
	held_by = 0
	pocketed_by = peer_id
	if kind != "hose":
		spraying = false
	_airborne = false
	_runaway_left = 0.0
	_set_solid(false)


## Host: out of this peer's pocket into their hands.
func host_draw(peer_id: int) -> void:
	pocketed_by = 0
	held_by = peer_id
	_airborne = false
	_set_solid(false)


## Host: nobody's any more (emptied pockets, a player gone). It lands at `at`,
## solid again, popping off with this velocity.
func host_unown(at: Vector3, pop: Vector3) -> void:
	held_by = 0
	pocketed_by = 0
	pocket_slot = -1
	_airborne = false
	global_position = at
	_set_solid(true)
	linear_velocity = pop
	angular_velocity = Vector3.ZERO


## Whoever carries this, in hand or in a pocket, or 0.
func _carrier_id() -> int:
	return held_by if held_by != 0 else pocketed_by


func _hotbar() -> Node:
	return get_tree().get_first_node_in_group("hotbar")


## What this weighs in kg (Constants.ITEM_WEIGHT_KG). A bag gets heavier with
## its leaves and a wheelbarrow with its bags. Every peer can work it out from
## the replicated kind, value, and stored bags, so the holder's slowdown matches.
func weight_kg() -> float:
	var base := float(Constants.ITEM_WEIGHT_KG.get(kind, 6.0))
	if kind == "leaf_bag":
		return minf(base + float(value) * Constants.LEAF_BAG_KG_PER_DOLLAR, Constants.LEAF_BAG_MAX_KG)
	if kind == "wheelbarrow":
		return base + float(stored_bags) * Constants.WHEELBARROW_KG_PER_BAG
	if kind == "junk":
		# A toilet is heavy and a flamingo is light (shops chunk 5).
		return float((Constants.JUNK_TYPES.get(label, {}) as Dictionary).get("kg", base))
	return base


## "light", "medium", or "heavy", by weight (Constants.BONK_TIER_KG).
func weight_tier() -> String:
	var kg := weight_kg()
	if kg <= float(Constants.BONK_TIER_KG["light"]):
		return "light"
	if kg <= float(Constants.BONK_TIER_KG["medium"]):
		return "medium"
	return "heavy"


## The holder sets the ladder up against the nearest gutter, if one is close.
func request_place_ladder() -> void:
	if Net.is_host():
		_place_ladder(Net.local_peer_id())
	else:
		_rpc_request_place_ladder.rpc_id(1)


func is_set_up() -> bool:
	return ladder_top != Vector3.ZERO


## Host: something hit a set-up ladder hard enough. It falls, and anyone on it
## (player.gd _step_climb) or on the roof is on their own.
func host_knock_down(push: Vector3) -> void:
	if not Net.is_host() or kind != "ladder" or ladder_top == Vector3.ZERO:
		return
	ladder_top = Vector3.ZERO
	freeze = false
	_set_solid(true)
	var flat := Vector3(push.x, 0.0, push.z)
	apply_central_impulse((flat.normalized() if flat.length() > 0.1 else Vector3.BACK) * 30.0 + Vector3.UP * 12.0)
	angular_velocity = Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
	_rpc_mower_fx.rpc("clank", global_position + Vector3.UP)


func _place_ladder(peer_id: int) -> void:
	if kind != "ladder" or held_by != peer_id:
		return
	var player := _player(peer_id)
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	if player == null or tasks == null:
		return
	# The gutter section closest to where they stand.
	var best := -1
	var best_distance := Constants.LADDER_SET_REACH
	for index: int in int(tasks.call("spot_count")):
		var spot: Dictionary = tasks.call("spot", index)
		if str(spot["task"]) != "clean_gutters":
			continue
		var at: Vector3 = spot["at"]
		var distance := Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()
		if distance < best_distance:
			best = index
			best_distance = distance
	if best < 0:
		return
	var gutter: Dictionary = tasks.call("spot", best)
	var top: Vector3 = (gutter["at"] as Vector3) - Vector3(0.0, 0.15, 0.0)
	var out: Vector3 = gutter["normal"]
	held_by = 0
	_set_solid(true)
	freeze = true
	var foot := Vector3(top.x, player.global_position.y, top.z) + out * (0.28 * top.y + 0.3)
	global_position = foot
	rotation = Vector3.ZERO
	ladder_top = top
	# Hands free again: the selected pocket item comes back out.
	var hotbar := _hotbar()
	if hotbar != null:
		hotbar.call("host_settle", peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_place_ladder() -> void:
	if Net.is_host():
		_place_ladder(multiplayer.get_remote_sender_id())


## E by a water source: a hose hooks up there (or unhooks if it already is),
## a pressure washer fills its tank.
func request_hookup() -> void:
	if Net.is_host():
		_hookup(Net.local_peer_id())
	else:
		_rpc_request_hookup.rpc_id(1)


func _hookup(peer_id: int) -> void:
	if held_by != peer_id or (kind != "hose" and kind != "pressure_washer" and kind != "paint_roller"):
		return
	var holder := _player(peer_id)
	if holder == null:
		return
	# A roller dips in the paint bucket.
	if kind == "paint_roller":
		for node: Node in get_tree().get_nodes_in_group("paint_buckets"):
			if (node as Node3D).global_position.distance_to(holder.global_position) < Constants.WATER_REACH + 0.5:
				water = 100.0
		return
	var source := _WaterSources.nearest(get_tree(), holder.global_position, Constants.WATER_REACH)
	if source == null:
		return
	var source_kind := str(source.get_meta("kind"))
	if kind == "hose":
		if hose_source == source_kind:
			hose_source = ""
			return
		hose_source = source_kind
	else:
		water = 100.0
	if source_kind == "spigot":
		var tasks := get_tree().get_first_node_in_group("job_tasks")
		if tasks != null:
			tasks.call("add_water_fee", float(Constants.SPIGOT_HOOKUP_FEE))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_hookup() -> void:
	if Net.is_host():
		_hookup(multiplayer.get_remote_sender_id())


## Host: everything else a running mower rolls over. Leaves get mulched (gone,
## no money); litter is flung across the yard; weeds are mowed down; a hose line
## gets cut (a new one goes on the bill); a leaf bag bursts back into leaves; the
## gnome grinds, flies, and stalls the mower (the bill again); and feet get hurt
## (medical bills). Someone's foot might come clean off.
func _mower_hits(holder: Node3D, heading: Vector3 = Vector3.ZERO) -> void:
	var now := Time.get_ticks_msec()
	var at := global_position
	if heading == Vector3.ZERO and holder != null:
		heading = -holder.global_transform.basis.z
	var radius := Constants.MOWER_HIT_RADIUS
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field != null:
		field.call("host_mulch", at, 0.6)
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	if tasks != null:
		for index: int in (tasks.call("host_run_over", at, radius, heading) as Array):
			_rpc_mower_fx.rpc("clank", at)
	for node: Node in get_tree().get_nodes_in_group("props"):
		var other := node as Node3D
		# Only what lies loose; a hooked-up hose's line can be cut wherever its nozzle is.
		if other == null or other == self or not bool(other.call("is_loose")) and str(other.get("kind")) != "hose":
			continue
		var key := other.get_instance_id()
		if int(_mower_hit_at.get(key, 0)) > now:
			continue
		match str(other.get("kind")):
			"hose":
				if str(other.get("hose_source")) == "" or not _over_hose(other, at):
					continue
				_mower_hit_at[key] = now + 2000
				other.set("hose_source", "")
				other.rpc("_rpc_hose_snap", at)
				if tasks != null:
					tasks.call("add_bill", "hose", Constants.BILL_HOSE)
				_rpc_mower_fx.rpc("chop", at)
			"leaf_bag":
				if other.global_position.distance_to(at) > radius + 0.3:
					continue
				if field != null:
					field.call("host_scatter", other.global_position, 1.8, int(other.get("value")))
				_rpc_mower_fx.rpc("burst", other.global_position)
				other.queue_free()
			"ladder":
				if not bool(other.call("is_set_up")) or other.global_position.distance_to(at) > radius + 0.5:
					continue
				_mower_hit_at[key] = now + 3000
				other.call("host_knock_down", heading * 4.0)
			"gnome":
				if other.global_position.distance_to(at) > radius + 0.3:
					continue
				_mower_hit_at[key] = now + 3000
				(other as RigidBody3D).apply_central_impulse((heading + Vector3.UP * 1.6).normalized() * 70.0)
				spraying = false
				if tasks != null:
					tasks.call("add_bill", "gnome", Constants.BILL_GNOME)
				_rpc_mower_fx.rpc("grind", at)
	var people: Array[Node] = get_tree().get_nodes_in_group("players")
	people.append_array(get_tree().get_nodes_in_group("bonkable"))
	for node: Node in people:
		var person := node as Node3D
		if person == null or person == holder or not person.is_inside_tree():
			continue
		if Vector2(person.global_position.x - at.x, person.global_position.z - at.z).length() > radius or absf(person.global_position.y - at.y) > 0.6:
			continue
		var key := person.get_instance_id()
		if int(_mower_hit_at.get(key, 0)) > now:
			continue
		_mower_hit_at[key] = now + 4000
		var already := int(person.get("foot_hurt")) if "foot_hurt" in person else 0
		var level := 2 if already >= 1 or randf() < Constants.FOOT_OFF_CHANCE else 1
		if already >= 2:
			level = 2
		if tasks != null:
			tasks.call("add_bill", "medical", Constants.BILL_FOOT_OFF if level == 2 else Constants.BILL_FOOT_CUT)
		_rpc_foot.rpc(get_path_to(person), level, heading)
		_rpc_mower_fx.rpc("chop", at)


## Host: a running mower nobody's holding drives straight on, mowing whatever it
## meets, until it runs out of time or into something. Grabbing it stops that.
func _step_runaway(delta: float) -> void:
	if _runaway_left <= 0.0:
		if spraying:
			spraying = false
		return
	_runaway_left -= delta
	linear_velocity = _runaway_dir * Constants.MOWER_RUNAWAY_SPEED + Vector3(0.0, linear_velocity.y, 0.0)
	angular_velocity = Vector3.ZERO
	rotation = Vector3(0.0, atan2(-_runaway_dir.x, -_runaway_dir.z), 0.0)
	_mower_hits(null, _runaway_dir)
	# Into a fence or a wall: it stalls.
	if _runaway_last != Vector3.INF and global_position.distance_to(_runaway_last) < Constants.MOWER_RUNAWAY_SPEED * delta * 0.15:
		_runaway_stuck += delta
	else:
		_runaway_stuck = 0.0
	_runaway_last = global_position
	if _runaway_left <= 0.0 or _runaway_stuck > 1.0:
		_runaway_left = 0.0
		spraying = false
		_rpc_mower_fx.rpc("clank", global_position)


## True when a hooked-up hose runs under this point: it lies across the ground
## from where it's hooked up to the nozzle.
func _over_hose(hose: Node3D, at: Vector3) -> bool:
	var source := _WaterSources.find(get_tree(), str(hose.get("hose_source")))
	if source == null:
		return false
	var a := Vector2(source.global_position.x, source.global_position.z)
	var b := Vector2(hose.global_position.x, hose.global_position.z)
	var p := Vector2(at.x, at.z)
	var along := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a.lerp(b, along)) < 0.45


## Everyone hears and sees what the mower hit.
@rpc("authority", "call_local", "reliable")
func _rpc_mower_fx(what: String, at: Vector3) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", {"chop": "chop", "grind": "grind", "burst": "bag", "clank": "bonk", "runaway": "mower_start", "sputter": "sputter", "glug": "glug"}.get(what, "bonk"), at)
	# Running dry and filling up are only heard: the sputter is the message (x1:text).
	if what == "sputter" or what == "glug":
		return
	var looks := get_tree().get_first_node_in_group("task_looks")
	if looks != null:
		looks.call("work_fx", "pick_litter" if what == "clank" else ("mow_lawn" if what == "chop" else "clean_gutters"), at + Vector3.UP * 0.3)


## Someone's foot went under the mower: 1 is a nasty cut, 2 it came clean off.
@rpc("authority", "call_local", "reliable")
func _rpc_foot(target: NodePath, level: int, heading: Vector3) -> void:
	var person := get_node_or_null(target)
	if person != null and person.has_method("hurt_foot"):
		person.call("hurt_foot", level, heading)


## The holder yanks the mower's pull cord. It might catch.
func request_start() -> void:
	if Net.is_host():
		_pull_cord(Net.local_peer_id())
	else:
		_rpc_request_start.rpc_id(1)


func _pull_cord(peer_id: int) -> void:
	if kind != "lawn_mower" or held_by != peer_id:
		return
	# Running: the same pull switches it off, so you can set it down safely.
	if spraying:
		spraying = false
		_rpc_mower_fx.rpc("clank", global_position)
		return
	# An empty tank never catches: a pull, and the sad little cough.
	if fuel <= 0.0:
		_rpc_pull_fx.rpc(false)
		_rpc_mower_fx.rpc("sputter", global_position)
		return
	# Better tiers catch sooner; a used one fights you; the Mk III always starts.
	var chance := _ToolTiers.start_chance(_ToolTiers.tier_of(self), _pulls)
	_pulls += 1
	var caught := randf() < chance
	if caught:
		spraying = true
		_pulls = 0
	_rpc_pull_fx.rpc(caught)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_start() -> void:
	if Net.is_host():
		_pull_cord(multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func _rpc_pull_fx(caught: bool) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", "pullcord", global_position)
		if caught:
			sfx.call("play_at", "mower_start", global_position)


## Host: the tool ran just now (job_tasks and leaf_field say so on each use).
func mark_spraying() -> void:
	# A gas tool with an empty tank doesn't run, whoever asks.
	if not _ToolTiers.has_fuel(self):
		return
	_spray_left = 0.3
	if not spraying:
		spraying = true


## Host: a running gas tool burns its tank (core/tool_tiers.gd: thirstier used,
## thriftier Mk II and III). Empty, it sputters and dies.
func _step_fuel(delta: float) -> void:
	if not spraying or not _ToolTiers.is_gas_tool(kind) or fuel <= 0.0:
		return
	fuel = maxf(0.0, fuel - _ToolTiers.burn_per_second(kind, _ToolTiers.tier_of(self)) * delta)
	if fuel <= 0.0:
		spraying = false
		_spray_left = 0.0
		_runaway_left = 0.0
		_pulls = 0
		_rpc_mower_fx.rpc("sputter", global_position)


## The holder of the gas can presses E by a gas tool: the host pours what the
## tank needs (Constants.GAS_PER_TANK fills it from empty) out of the can.
func request_refuel() -> void:
	if Net.is_host():
		_refuel(Net.local_peer_id())
	else:
		_rpc_request_refuel.rpc_id(1)


## The gas tool the holder of this gas can would fill: the closest one within
## reach that isn't full, or null. Every peer can ask (the prompt does).
func refuel_target() -> Node3D:
	if kind != "gas_can" or held_by == 0 or _ToolTiers.can_gallons(self) <= 0.0:
		return null
	var holder := _player(held_by)
	if holder == null:
		return null
	var best: Node3D = null
	var best_distance := Constants.PICKUP_REACH
	for node: Node in get_tree().get_nodes_in_group("props"):
		var other := node as Node3D
		if other == null or other == self or not _ToolTiers.is_gas_tool(str(other.get("kind"))) or float(other.get("fuel")) >= 100.0:
			continue
		var distance := other.global_position.distance_to(holder.global_position)
		if distance < best_distance:
			best = other
			best_distance = distance
	return best


func _refuel(peer_id: int) -> void:
	if kind != "gas_can" or held_by != peer_id:
		return
	var target := refuel_target()
	if target == null:
		return
	var needed := (100.0 - float(target.get("fuel"))) / 100.0 * Constants.GAS_PER_TANK
	var poured := minf(needed, _ToolTiers.can_gallons(self))
	if poured <= 0.0:
		return
	water = _ToolTiers.can_water(_ToolTiers.can_gallons(self) - poured)
	target.set("fuel", minf(100.0, float(target.get("fuel")) + poured / maxf(Constants.GAS_PER_TANK, 0.001) * 100.0))
	label = _ToolTiers.can_label(_ToolTiers.can_gallons(self))
	_rpc_mower_fx.rpc("glug", target.global_position)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_refuel() -> void:
	if Net.is_host():
		_refuel(multiplayer.get_remote_sender_id())


## Host: a tool stops running a moment after its last use. A mower's flag is its
## engine instead, which runs until it stalls or is let go.
func _step_spray(delta: float) -> void:
	_spray_left -= delta
	if spraying and _spray_left <= 0.0:
		spraying = false


## Host: a hooked-up hose stretched past its length comes loose and its end whips
## back across the yard; anyone it passes is knocked out.
func _step_hose(delta: float) -> void:
	if _whip_t >= 0.0:
		_whip_t += delta / Constants.HOSE_WHIP_SECONDS
		var t := clampf(_whip_t, 0.0, 1.0)
		# The loose end flies from the source toward the nozzle, bowing out sideways.
		var across := (global_position - _whip_from).cross(Vector3.UP).normalized()
		var tip := _whip_from.lerp(global_position, t * t) + across * sin(t * PI) * 3.0 + Vector3.UP * sin(t * PI) * 1.2
		for node: Node in get_tree().get_nodes_in_group("players"):
			var person := node as Node3D
			if person == null or _whipped.has(person) or person.name == str(_carrier_id()):
				continue
			if (person.global_position + Vector3(0.0, 1.0, 0.0)).distance_to(tip) < Constants.HOSE_WHIP_RADIUS:
				_whipped.append(person)
				_rpc_bonk_fx.rpc(get_path_to(person), "heavy", (tip - _whip_from).normalized() * 6.0 + Vector3.UP * 2.0)
		if _whip_t >= 1.0:
			_whip_t = -1.0
	if kind != "hose" or hose_source == "":
		return
	var source := _WaterSources.find(get_tree(), hose_source)
	if source == null:
		hose_source = ""
		return
	if source.global_position.distance_to(global_position) > _ToolTiers.hose_length(_ToolTiers.tier_of(self)):
		_whip_from = source.global_position
		_whip_t = 0.0
		_whipped.clear()
		hose_source = ""
		_rpc_hose_snap.rpc(_whip_from)
		# The one holding it (or with it over their shoulder) gets yanked too.
		var holder := _player(_carrier_id()) if _carrier_id() != 0 else null
		if holder != null:
			_rpc_bonk_fx.rpc(get_path_to(holder), "light", (_whip_from - holder.global_position).normalized() * 3.0)


## Everyone sees the hose snap loose (props/hose_rope.gd whips it) and hears it.
@rpc("authority", "call_local", "reliable")
func _rpc_hose_snap(from: Vector3) -> void:
	var rope := get_node_or_null("HoseRope")
	if rope != null:
		rope.call("snap", from)
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", "bonk", global_position)


func request_grab() -> void:
	if Net.is_host():
		_handle_grab(Net.local_peer_id())
	else:
		_rpc_request_grab.rpc_id(1)


func request_drop() -> void:
	if Net.is_host():
		_handle_release(Net.local_peer_id(), Vector3.ZERO)
	else:
		_rpc_request_drop.rpc_id(1)


## power is how hard: Constants.THROW_POWER_MIN to THROW_POWER_MAX, 1 for a normal throw.
## from is where the thrower stood as they let go (their own peer knows best; the
## host checks it, Constants.THROW_FROM_TOLERANCE), or INF for wherever the host has them.
## A leaf bag says instead where it left the thrower's hands as they saw it, so
## the flight the host gives it is the one they drew (_predict_toss).
func request_throw(direction: Vector3, power: float = 1.0, from: Vector3 = Vector3.INF) -> void:
	if kind == "leaf_bag" and held_by == Net.local_peer_id() and _player(held_by) != null:
		from = _hold_position(_player(held_by))
	if Net.is_host():
		_handle_release(Net.local_peer_id(), direction, power, from)
	else:
		_rpc_request_throw.rpc_id(1, direction, power, from)
		if kind == "leaf_bag" and held_by == Net.local_peer_id():
			_predict_toss(direction, power)


## Client: its own leaf bag leaves its hands now, not a round trip from now. It
## flies the flight the host will give it (the same math, aim help and all,
## net/components/bed_toss.gd) until the bed takes it, it comes down, or the
## host's bag catches up.
func _predict_toss(direction: Vector3, power: float) -> void:
	var player := _player(Net.local_peer_id())
	var flat := Vector3(direction.x, 0.0, direction.z)
	if player == null or flat.length() < 0.1:
		return
	var truck := get_tree().get_first_node_in_group("chefty")
	_pred_pos = _hold_position(player)
	_pred_ground = player.global_position.y
	_pred_vel = _BedToss.assist(truck, _pred_pos, _BedToss.launch_velocity(kind, weight_kg(), flat, power), _pred_ground)
	_pred_basis = Basis(Vector3.UP, player.global_rotation.y)
	# End over end, as the host spins it (_release), at its middling rate.
	_pred_spin = Vector3(_pred_vel.z, 0.0, -_pred_vel.x).normalized() * (Constants.BAG_TOSS_SPIN_MIN + Constants.BAG_TOSS_SPIN_MAX) * 0.5
	_pred_age = 0.0
	_pred_done = false
	_pred_wait = 0.0
	_blend_left = 0.0
	_predicting = true
	# Right by the bed: it hops in over the side, as the host will have it (_release).
	if _BedToss.close_toss(truck, _pred_pos, _pred_vel, _pred_ground) and int(truck.call("bag_count")) < Constants.TRUCK_BAG_CAPACITY:
		_predicting = false
		var slot := int(truck.call("bag_count"))
		var seconds := _settle_seconds_for(truck, Transform3D(_pred_basis, _pred_pos), slot)
		_begin_settle(truck, slot, seconds, value, [], Transform3D(_pred_basis, _pred_pos), _pred_vel)
		_provisional = true
		_provisional_age = 0.0


## Client, each tick of its own toss's flight.
func _step_predict(delta: float) -> void:
	_pred_age += delta
	# The host never took the throw (it was out of its hands already): back to it.
	if held_by == Net.local_peer_id() and _pred_age > Constants.BAG_TOSS_PROVISIONAL_SECONDS:
		_predicting = false
		return
	var truck := get_tree().get_first_node_in_group("chefty")
	if not _pred_done:
		var next := _BedToss.step(_pred_pos, _pred_vel, delta)
		_pred_pos = next[0]
		_pred_vel = next[1]
		_pred_basis = (Basis(_pred_spin.normalized(), _pred_spin.length() * delta) * _pred_basis).orthonormalized() if _pred_spin.length() > 0.01 else _pred_basis
		var body := Transform3D(_pred_basis, _pred_pos)
		var bottom := body * Vector3(0.0, _PropLooks.VISUAL_HEIGHT, 0.0) - Vector3(0.0, _PropLooks.VISUAL_HEIGHT, 0.0)
		if truck != null and truck.has_method("bed_transform") and _BedToss.catches(truck, bottom, _pred_vel) and int(truck.call("bag_count")) < Constants.TRUCK_BAG_CAPACITY:
			# In, as far as this peer can tell: start into the load now; the host's
			# word follows a round trip later (_rpc_bed_catch).
			(%Visual as Node3D).global_transform = body * _visual_rest()
			_predicting = false
			var slot := int(truck.call("bag_count"))
			var seconds := _settle_seconds_for(truck, body, slot)
			_begin_settle(truck, slot, seconds, value, [], body, _pred_vel)
			_provisional = true
			_provisional_age = 0.0
			return
		var on_heap := truck != null and int(truck.call("bag_count")) >= Constants.TRUCK_BAG_CAPACITY and _BedLoad.in_pile((truck.call("bed_transform") as Transform3D).affine_inverse() * bottom, int(truck.call("bag_count")))
		if on_heap or (truck != null and _BedToss.hits_hull(truck, _pred_pos)) or (_pred_vel.y < 0.0 and _pred_pos.y <= _pred_ground):
			# A full heap, the truck's side or the ground: wait there for the host's bag.
			_pred_done = true
	else:
		# Down (or off the truck): wait for the host's bag to get here, then ease onto it.
		_pred_wait += delta
		if global_position.distance_to(_pred_pos) < Constants.BAG_TOSS_CATCH_UP_M or _pred_wait > Constants.BAG_TOSS_CATCH_UP_SECONDS:
			_predicting = false
			_blend_from = (%Visual as Node3D).global_transform
			_blend_left = Constants.BAG_TOSS_BLEND_SECONDS
			return
	(%Visual as Node3D).global_transform = Transform3D(_pred_basis, _pred_pos) * _visual_rest()


## Client: it glided in on this peer's say-so and the host never caught it: let
## its spot go and ease back onto the host's bag.
func _abort_provisional() -> void:
	_settling = false
	_provisional = false
	var truck := get_tree().get_first_node_in_group("chefty")
	var load_node := truck.call("bed_load") as Node if truck != null and truck.has_method("bed_load") else null
	if load_node != null:
		load_node.call("unhold_slot", _settle_slot, self)
	_blend_from = (%Visual as Node3D).global_transform
	_blend_left = Constants.BAG_TOSS_BLEND_SECONDS
	_refresh_label()


func _host_step() -> void:
	if _cleared_left > 0.0:
		_cleared_left -= get_physics_process_delta_time()
		# Junk lets go of the exception as soon as its box is clear of them.
		if kind == "junk" and Constants.JUNK_CLEAR_MAX_SECONDS - _cleared_left >= Constants.JUNK_CLEAR_MIN_SECONDS and _clear_of(_cleared_from):
			_cleared_left = 0.0
		if _cleared_left <= 0.0 or held_by != 0 or pocketed_by != 0:
			_cleared_left = 0.0
			if is_instance_valid(_cleared_from):
				remove_collision_exception_with(_cleared_from)
			_cleared_from = null
	if _settling:
		_step_settle(get_physics_process_delta_time())
		return
	_step_fuel(get_physics_process_delta_time())
	if kind != "lawn_mower":
		_step_spray(get_physics_process_delta_time())
	elif held_by == 0:
		_step_runaway(get_physics_process_delta_time())
	if kind == "hose":
		_step_hose(get_physics_process_delta_time())
	var kg := weight_kg()
	if not is_equal_approx(mass, kg):
		mass = kg
	# In a pocket: it rides along with its owner, out of everyone's way. A hooked-up
	# hose still snaps if they walk too far (_step_hose ran above).
	if pocketed_by != 0:
		var carrier := _player(pocketed_by)
		if carrier == null:
			host_unown(global_position, Vector3.ZERO)
			return
		global_position = carrier.global_position + Vector3(0.0, Constants.POCKET_FOLLOW_HEIGHT, 0.0)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_runaway_left = 0.0
		return
	if held_by != 0:
		var player := _player(held_by)
		if player == null:
			held_by = 0
			pocket_slot = -1
			_set_solid(true)
			return
		_runaway_left = 0.0
		var was := global_position
		global_position = _hold_position(player)
		# A carried bag hangs upright, facing whoever carries it; so do the things
		# held the HOLDS way (the gnome, the trash can, a sign, the wheelbarrow).
		if kind == "leaf_bag":
			global_rotation = Vector3(0.0, player.global_rotation.y, 0.0)
		elif _held_the_holds_way():
			global_rotation = Vector3(0.0, player.global_rotation.y + float(_PropLooks.hold_of(self).get("yaw", 0.0)), 0.0)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		# A mower being pushed mows whatever it rolls over, once it's running.
		if kind == "lawn_mower" and spraying:
			if Vector2(global_position.x - was.x, global_position.z - was.z).length() > 0.01:
				var tasks := get_tree().get_first_node_in_group("job_tasks")
				if tasks != null:
					# A better mower cuts faster and wider (core/tool_tiers.gd).
					var mower_tier := _ToolTiers.tier_of(self)
					tasks.call("host_work", "mow_lawn", global_position, 0.75 * _ToolTiers.reach(mower_tier), get_physics_process_delta_time() * _ToolTiers.speed(mower_tier), held_by)
			_mower_hits(player)
		return
	for node: Node in get_tree().get_nodes_in_group("players"):
		if not node is CharacterBody3D:
			continue
		var player := node as CharacterBody3D
		var offset := global_position - player.global_position
		if offset.length() > PUSH_REACH or player.velocity.length() < 0.8:
			continue
		apply_central_impulse(player.velocity * mass * 0.15)
	if _airborne:
		_check_bonks()
	_come_back_in()
	if _airborne and linear_velocity.length() < 0.35:
		_airborne = false
		# Thrown and come to rest: a NICE BOY close by comes to have a look (R2 chunk 2).
		get_tree().call_group("nice_crew", "on_prop_landed", global_position, _thrower)
	_try_load_bag()
	_try_load_junk()
	_try_unload_wheelbarrow()


func _handle_grab(peer_id: int) -> void:
	if not is_loose():
		return
	var player := _player(peer_id)
	if player == null or player.global_position.distance_to(global_position) > GRAB_REACH:
		return
	# Caught by the NICE BOYS: hands off everything (R2 chunk 2).
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and bool(director.call("is_captured", peer_id)):
		return
	var hotbar := _hotbar()
	var slot := -1
	if hotbar == null:
		# No pockets (a scene without World/Hotbar): one thing at a time.
		for node: Node in get_tree().get_nodes_in_group("props"):
			if int(node.get("held_by")) == peer_id:
				return
	else:
		# The hotbar decides: a pocket item goes in a slot and comes out into your
		# hands; a big one fills them, after the pocket item in hand goes away.
		slot = int(hotbar.call("host_slot_for_pickup", peer_id, self))
		if slot == _Hotbar.REFUSE:
			hotbar.call("host_refuse", peer_id, hotbar.call("refusal_reason", peer_id))
			return
	_airborne = false
	_runaway_left = 0.0
	# Taking a set-up ladder down: anyone on it falls.
	if ladder_top != Vector3.ZERO:
		ladder_top = Vector3.ZERO
	_set_solid(false)
	if hotbar == null:
		held_by = peer_id
		return
	if slot >= 0:
		pocket_slot = slot
		pocketed_by = peer_id
		hotbar.call("host_select_silently", peer_id, slot)
		hotbar.call("host_settle", peer_id)
	else:
		hotbar.call("host_clear_hands", peer_id)
		pocket_slot = -1
		held_by = peer_id


func _handle_release(peer_id: int, direction: Vector3, power: float = 1.0, from: Vector3 = Vector3.INF) -> void:
	if held_by != peer_id:
		return
	_release(peer_id, direction, power, from)
	# What's next in hand: the next sign of a stack, or the selected pocket item
	# again once a big thing is set down.
	var hotbar := _hotbar()
	if hotbar != null:
		hotbar.call("host_settle", peer_id)


func _release(peer_id: int, direction: Vector3, power: float, from: Vector3 = Vector3.INF) -> void:
	var player := _player(peer_id)
	var held_now := held_by == peer_id
	held_by = 0
	# Out of its slot: the slot stays selected, and empty.
	pocket_slot = -1
	_toss_feet = Vector3.INF
	if player != null:
		var forward := -player.global_transform.basis.z
		forward.y = 0.0
		if forward.length() > 0.001:
			forward = forward.normalized()
		# A throw leaves the way it was thrown, from where the thrower stood as
		# they let go (their own peer's word, if it's close to where the host has them).
		var flat_throw := Vector3(direction.x, 0.0, direction.z)
		if flat_throw.length() >= 0.1:
			forward = flat_throw.normalized()
		var feet := player.global_position
		if kind == "leaf_bag" and held_now:
			# A bag leaves from where it hangs in your hands as you saw it (your
			# own peer's word, if it's close to where the host hangs it), so it
			# doesn't hop as it goes and flies the arc you saw; it can't bump into
			# you on the way out.
			var hands := global_position
			var at := from if from.is_finite() and from.distance_to(hands) <= Constants.THROW_FROM_TOLERANCE else hands
			feet += at - hands
			global_position = at
			add_collision_exception_with(player)
			_cleared_from = player
			_cleared_left = Constants.BAG_TOSS_CLEAR_SECONDS
		else:
			if from.is_finite() and from.distance_to(feet) <= Constants.THROW_FROM_TOLERANCE:
				feet = from
			global_position = _BedToss.release_point(kind, feet, forward)
			# Junk's box is wide: it passes through whoever let go until it's clear of
			# them (_host_step), so turning solid never shoves them back.
			if kind == "junk":
				add_collision_exception_with(player)
				_cleared_from = player
				_cleared_left = Constants.JUNK_CLEAR_MAX_SECONDS
		_toss_feet = feet
		# Let go of a running mower and it drives off on its own (docs/FUN.md).
		if kind == "lawn_mower" and spraying:
			_runaway_left = Constants.MOWER_RUNAWAY_SECONDS
			_runaway_dir = forward
			_runaway_stuck = 0.0
			_runaway_last = Vector3.INF
			_rpc_mower_fx.rpc("runaway", global_position)
	_set_solid(true)
	_refused_at = -100.0
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.1:
		# A leaf bag set down from the hands plops out in front of you, clear of
		# your legs by the time it can bump them.
		if kind == "leaf_bag" and held_now and player != null:
			var ahead := -player.global_transform.basis.z
			ahead.y = 0.0
			linear_velocity = ahead.normalized() * Constants.BAG_SET_DOWN_PUSH + Vector3.UP * Constants.BAG_SET_DOWN_LIFT
		return
	# Every throw is the same shove, so the weight decides how far it goes; a leaf
	# bag is a two-handed lob instead (net/components/bed_toss.gd).
	var velocity_now := _BedToss.launch_velocity(kind, weight_kg(), flat, power)
	var truck := get_tree().get_first_node_in_group("chefty")
	var hop_in := false
	if kind == "leaf_bag":
		# Aimed near Chefty's bed: the light aim help bends a near miss in.
		var ground := _toss_feet.y if _toss_feet.is_finite() else global_position.y - Constants.BAG_TOSS_RELEASE_HEIGHT
		var helped := _BedToss.assist(truck, global_position, velocity_now, ground)
		if not helped.is_equal_approx(velocity_now):
			_BedToss.stats["assisted"] = int(_BedToss.stats["assisted"]) + 1
		velocity_now = helped
		# Right by the bed, it couldn't arc over the rail: heaved in over the side.
		hop_in = _BedToss.close_toss(truck, global_position, velocity_now, ground) and int(truck.call("bag_count")) < Constants.TRUCK_BAG_CAPACITY
		# It tumbles over forward, end over end, the way a heaved sack does.
		angular_velocity = Vector3(velocity_now.z, 0.0, -velocity_now.x).normalized() * randf_range(Constants.BAG_TOSS_SPIN_MIN, Constants.BAG_TOSS_SPIN_MAX) + Vector3(0.0, randf_range(-1.0, 1.0), 0.0)
	else:
		angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)) * (6.0 / weight_kg())
	linear_velocity = velocity_now
	_airborne = true
	_thrower = peer_id
	_thrown_at = Net.server_time()
	_bonked.clear()
	_rpc_throw_fx.rpc()
	if hop_in:
		_BedToss.stats["hopped"] = int(_BedToss.stats.get("hopped", 0)) + 1
		_bed_catch(truck)


## Host only. A flying item that reaches a person bonks them: everyone sees and
## hears it, and a player is shoved and stunned by how heavy and fast it was.
func _check_bonks() -> void:
	var speed := linear_velocity.length()
	if speed < Constants.BONK_MIN_SPEED:
		return
	# A set-up ladder in the way comes down, with whoever's on it: anything that
	# touches its body or passes close to its rungs this fast.
	if speed >= Constants.LADDER_KNOCK_MIN_SPEED:
		var touching := get_colliding_bodies()
		for node: Node in get_tree().get_nodes_in_group("props"):
			var ladder := node as Node3D
			if ladder == null or ladder == self or _bonked.has(ladder) or str(ladder.get("kind")) != "ladder" or not bool(ladder.call("is_set_up")):
				continue
			var top: Vector3 = ladder.get("ladder_top")
			var along := clampf((global_position - ladder.global_position).dot(top - ladder.global_position) / maxf((top - ladder.global_position).length_squared(), 0.01), 0.0, 1.0)
			if not touching.has(ladder) and global_position.distance_to(ladder.global_position.lerp(top, along)) > Constants.LADDER_KNOCK_RADIUS:
				continue
			_bonked.append(ladder)
			ladder.call("host_knock_down", linear_velocity)
			linear_velocity = -linear_velocity * 0.3 + Vector3.UP * 1.5
	var targets: Array[Node] = get_tree().get_nodes_in_group("players")
	targets.append_array(get_tree().get_nodes_in_group("bonkable"))
	for node: Node in targets:
		var target := node as Node3D
		if target == null or _bonked.has(target) or not target.is_inside_tree():
			continue
		if target.name == str(_thrower) and Net.server_time() - _thrown_at < 0.5:
			continue
		var center := target.global_position + Vector3(0.0, 0.95, 0.0)
		var offset := center - global_position
		if absf(offset.y) > 1.2 or Vector2(offset.x, offset.z).length() > 0.85:
			continue
		_bonked.append(target)
		var flat := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		var shove_speed := minf(weight_kg() * speed * Constants.BONK_SHOVE_PER_MOMENTUM, Constants.BONK_SHOVE_MAX)
		var push := (flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD) * shove_speed + Vector3.UP * shove_speed * 0.35
		_rpc_bonk_fx.rpc(get_path_to(target), weight_tier(), push)
		# Bonking a passerby draws attention; bonking a NICE BOY draws a lot.
		var heat := get_tree().get_first_node_in_group("heat")
		if heat != null:
			if target.is_in_group("crew"):
				heat.call("add", Constants.HEAT_CREW_BONK, "crew_bonk")
				# R2 chunk 2: who did it (a bonk during the cite or the escort is a
				# rescue), and the XP for beaning a NICE BOY.
				if target.has_method("host_bonked_by"):
					target.call("host_bonked_by", _thrower)
				Campaign.add_xp(Constants.XP_CREW_BONK, "crew_bonk")
			elif not target.is_in_group("players"):
				heat.call("add", float(Constants.HEAT_PEDESTRIAN_BONK.get(weight_tier(), 4.0)), "pedestrian_bonk")
		# It bounces off them.
		linear_velocity = -linear_velocity * 0.25 + Vector3.UP * 1.5


## Host only. Something thrown into the street or a neighbor's yard comes back
## into the pad once it settles, so the job's one rake can't be lost.
func _come_back_in() -> void:
	if TownMap.enabled(get_tree()):
		_come_back_in_town()
		return
	var zone_name := _zone_name()
	var zone := _zone_center()
	var local := global_position - zone
	var rect: Rect2 = Constants.PAD_RECTS.get(zone_name, Rect2(-20.0, -20.0, 40.0, 40.0))
	var outside := not rect.grow(0.3).has_point(Vector2(local.x, local.z))
	if global_position.y < -5.0 or (outside and linear_velocity.length() < 0.5):
		var inner := rect.grow(-1.5)
		var back := Vector3(clampf(local.x, inner.position.x, inner.end.x), 1.2, clampf(local.z, inner.position.y, inner.end.y))
		global_position = zone + back
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_airborne = false


## Host only, the connected town (driving chunk D): there are no pads, people
## carry and throw things all over town. The job's own things (the tools that
## rode along, and the yard's rake, gnome, trash can and wheelbarrow) come back
## to the yard once they settle more than PROP_LEASH_METERS from it; anything
## that falls out of the world comes back to the nearest sidewalk (or the yard).
func _come_back_in_town() -> void:
	var fell := global_position.y < -5.0
	var lot := _job_lot()
	var belongs := lot != null and (is_in_group("job_tools") or lot.is_ancestor_of(self))
	if belongs:
		var center := (lot.get_parent() as Node3D).global_position
		var away := Vector2(global_position.x - center.x, global_position.z - center.z).length()
		if not fell and (away <= Constants.PROP_LEASH_METERS or linear_velocity.length() >= 0.5):
			return
		# Back on the yard, toward where it left, inside the edge.
		var rect: Rect2 = Constants.PAD_RECTS.get("LotZone", Rect2(-20.0, -20.0, 40.0, 40.0))
		var inner := Rect2(rect.position, Vector2(rect.size.x, Constants.PAD_HALF * 2.0)).grow(-1.5)
		var local := global_position - center
		_put_back(center + Vector3(clampf(local.x, inner.position.x, inner.end.x), 1.2, clampf(local.z, inner.position.y, inner.end.y)))
		return
	if fell:
		_put_back(TownMap.respawn_point(global_position) + Vector3(0.0, 1.1, 0.0))


## The loaded job yard (LotZone/LotSlot's child, which sits at the site), or null.
func _job_lot() -> Node:
	var world := get_tree().get_first_node_in_group("world")
	var slot := world.get_node_or_null("LotZone/LotSlot") if world != null else null
	if slot == null or slot.get_child_count() == 0:
		return null
	return slot.get_child(0)


func _put_back(at: Vector3) -> void:
	global_position = at
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_airborne = false
	reset_physics_interpolation()


## Which zone node this prop is nearest.
func _zone_name() -> String:
	var world := get_tree().get_first_node_in_group("world")
	var best := "LotZone"
	var best_distance := INF
	if world == null:
		return best
	for zone_name: String in ["StoreZone", "LotZone", "BorderZone"]:
		var zone := world.get_node_or_null(zone_name) as Node3D
		if zone != null and zone.global_position.distance_to(global_position) < best_distance:
			best_distance = zone.global_position.distance_to(global_position)
			best = zone_name
	return best


## The middle of whichever zone this prop is nearest: the store, the lot, or the border.
func _zone_center() -> Vector3:
	var world := get_tree().get_first_node_in_group("world")
	var best := Vector3.ZERO
	var best_distance := INF
	if world == null:
		return best
	for zone_name: String in ["StoreZone", "LotZone", "BorderZone"]:
		var zone := world.get_node_or_null(zone_name) as Node3D
		if zone == null:
			continue
		var distance := zone.global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = zone.global_position
	return best


## Everyone plays the throw's whoosh.
@rpc("authority", "call_local", "reliable")
func _rpc_throw_fx() -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", "whoosh", global_position)


## Everyone sees and hears a bonk; the person hit reacts (player.gd on_bonked,
## or a pedestrian's bonk). target is relative to this prop, the same on every peer.
@rpc("authority", "call_local", "reliable")
func _rpc_bonk_fx(target: NodePath, tier: String, push: Vector3) -> void:
	var node := get_node_or_null(target)
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		var at := (node as Node3D).global_position if node is Node3D else global_position
		sfx.call("play_at", "thud" if tier == "heavy" else "bonk", at)
		if tier == "heavy":
			sfx.call("play_at", "dizzy", at)
	if node != null and node.has_method("on_bonked"):
		node.call("on_bonked", push, tier)


func _player(peer_id: int) -> CharacterBody3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id) and node is CharacterBody3D:
			return node as CharacterBody3D
	return null


func _set_solid(solid: bool) -> void:
	collision_layer = 1 if solid else 0
	collision_mask = 1 if solid else 0
	if Net.is_host():
		freeze = not solid
	else:
		freeze = true


## Host only. Drop the prop if this peer is still holding it.
func force_release() -> void:
	if Net.is_host() and held_by != 0:
		_handle_release(held_by, Vector3.ZERO)


## Press E while holding a leaf bag next to this wheelbarrow.
func request_load_held() -> void:
	if kind != "wheelbarrow":
		return
	if Net.is_host():
		_load_held(Net.local_peer_id())
	else:
		_rpc_request_load.rpc_id(1)


## The holder presses E by Chefty: a bag is tossed in, a wheelbarrow dumped.
func request_load_truck() -> void:
	if Net.is_host():
		_load_truck(Net.local_peer_id())
	else:
		_rpc_request_load_truck.rpc_id(1)


## True when this prop, held, is close enough to Chefty to load it.
func near_truck() -> bool:
	var truck := get_tree().get_first_node_in_group("chefty")
	if truck == null:
		return false
	var at: Vector3 = truck.call("body_position")
	# Measure from the holder: a carried prop catches up to their hands a tick late.
	var holder := _player(held_by) if held_by != 0 else null
	var from := holder.global_position if holder != null else global_position
	return Vector2(from.x - at.x, from.z - at.z).length() <= Constants.TRUCK_UNLOAD_RADIUS + 1.0


func _load_truck(peer_id: int) -> void:
	if held_by != peer_id or not near_truck():
		return
	var truck := get_tree().get_first_node_in_group("chefty")
	if kind == "leaf_bag":
		# Heaved over the side from your hands: a little hop into its spot. A full
		# Chefty has no spot, and the bag stays in your hands.
		if int(truck.call("bag_count")) >= Constants.TRUCK_BAG_CAPACITY:
			return
		held_by = 0
		pocket_slot = -1
		_toss_feet = Vector3.INF
		var hotbar := _hotbar()
		if hotbar != null:
			hotbar.call("host_settle", peer_id)
		linear_velocity = Vector3.UP * Constants.BED_HAND_IN_LIFT
		_bed_catch(truck)
	elif kind == "junk":
		# Heaved over the side: out of your hands in a short hop that lands it on
		# the bed floor, where it's loaded once it settles (_try_load_junk).
		var player := _player(peer_id)
		held_by = 0
		pocket_slot = -1
		_toss_feet = Vector3.INF
		var hotbar := _hotbar()
		if hotbar != null:
			hotbar.call("host_settle", peer_id)
		_set_solid(true)
		if player != null:
			add_collision_exception_with(player)
			_cleared_from = player
			_cleared_left = Constants.BAG_TOSS_CLEAR_SECONDS
		var bed: Transform3D = truck.call("bed_transform")
		var junk_bed := truck.get_node_or_null("Body/JunkBed")
		if junk_bed != null:
			junk_bed.call("let_through", self, _JunkBed.heave_rise_seconds(global_position, bed))
		linear_velocity = _JunkBed.heave_velocity(global_position, bed)
		var spin := Constants.JUNK_HEAVE_SPIN
		angular_velocity = Vector3(randf_range(-spin.x, spin.x), randf_range(-spin.y, spin.y), randf_range(-spin.z, spin.z))
		_airborne = true
		_thrower = peer_id
		# A fresh flight: it never bonks whoever heaved it (it leaves their hands
		# inside their reach; a stale _thrown_at had it bean them on the spot,
		# rec_heave2_1p frame 11).
		_thrown_at = Net.server_time()
		_bonked.clear()
		if player != null:
			_bonked.append(player)
	elif kind == "wheelbarrow" and stored_bags > 0:
		var taken := int(truck.call("accept_bags", stored_bags, stored_value))
		if taken > 0:
			var moved_value := int(round(float(stored_value) * float(taken) / float(stored_bags)))
			stored_bags -= taken
			stored_value = maxi(0, stored_value - moved_value)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_load_truck() -> void:
	if Net.is_host():
		_load_truck(multiplayer.get_remote_sender_id())


func _try_load_bag() -> void:
	if kind != "leaf_bag" or not is_loose():
		return
	# Tossed into Chefty's bed, or dropping into it from over it: caught
	# (net/components/bed_toss.gd catches()), or batted back out of a full one.
	var truck := get_tree().get_first_node_in_group("chefty")
	if truck != null and truck.has_method("bed_transform"):
		var count := int(truck.call("bag_count"))
		if count >= Constants.TRUCK_BAG_CAPACITY:
			# Full: it bounces off the heap where it meets a drawn bag, not before.
			if _BedLoad.in_pile((truck.call("bed_transform") as Transform3D).affine_inverse() * _bottom(), count):
				_bed_refuse(truck)
				return
		elif _BedToss.catches(truck, _bottom(), linear_velocity):
			_bed_catch(truck)
			return
	var closest: Node = null
	var closest_distance := Constants.BAG_LOAD_RADIUS
	for node: Node in get_tree().get_nodes_in_group("props"):
		if node == self or str(node.get("kind")) != "wheelbarrow":
			continue
		var distance := global_position.distance_to((node as Node3D).global_position)
		if distance < closest_distance:
			closest = node
			closest_distance = distance
	if closest == null or not bool(closest.call("receive_bag", value)):
		return
	queue_free()


## Host: junk lying in Chefty's bed is loaded (net/components/junk_bed.gd, shops
## chunk 5): once it has settled on the bed floor it becomes part of the load,
## drawn exactly where it came to rest, so nothing jumps. A bed already holding
## Constants.TRUCK_JUNK_CAPACITY tips the next one back out over the side.
func _try_load_junk() -> void:
	if kind != "junk" or not is_loose():
		return
	# It hit something (falling fast one tick, stopped the next): everyone hears it land.
	var falling := linear_velocity.y
	var now_ms := Time.get_ticks_msec()
	if _junk_last_fall < -Constants.JUNK_LAND_SPEED and falling > _junk_last_fall * Constants.JUNK_LAND_STOP_SHARE and now_ms - _junk_landed_ms > Constants.JUNK_LAND_DEBOUNCE_MS:
		_junk_landed_ms = now_ms
		_rpc_junk_land.rpc(global_position, weight_kg())
	_junk_last_fall = falling
	if linear_velocity.length() > Constants.JUNK_BED_REST_SPEED:
		return
	var truck := get_tree().get_first_node_in_group("chefty")
	if truck == null or not truck.has_method("accept_junk") or not bool(truck.call("in_bed", global_position + Vector3.UP * 0.1)):
		return
	if bool(truck.call("accept_junk", self)):
		return
	# Full: over the nearest side wall, away from the bed's middle.
	var now := Net.server_time()
	if now - _refused_at < Constants.BED_REFUSE_EVERY_SECONDS:
		return
	_refused_at = now
	var bed: Transform3D = truck.call("bed_transform")
	var away := global_position - bed * _BedToss.BED_MIDDLE
	away = Vector3(away.x, 0.0, away.z)
	if away.length() < 0.1:
		away = bed.basis.x
	linear_velocity = away.normalized() * Constants.BED_REFUSE_PUSH + Vector3.UP * Constants.JUNK_BED_REFUSE_LIFT
	_airborne = true


## Every peer: a piece of junk landed (on the ground, in Chefty's bed, on
## Rusty's scale): a thud, deeper and louder the heavier it is.
@rpc("authority", "call_local", "reliable")
func _rpc_junk_land(at: Vector3, kg: float) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx == null:
		return
	var heavy := kg >= float(Constants.BONK_TIER_KG["medium"])
	sfx.call("play_at", "thud" if heavy else "bonk", at, Constants.JUNK_LAND_DB if heavy else Constants.JUNK_LAND_LIGHT_DB)


## What a player calls this, for the pickup prompt: junk by its type's name
## ("Toilet"), anything else by its label.
func display_name() -> String:
	if kind == "junk":
		return str(_Strings.SHOP_UI.get("junk_" + label, label))
	return label


## Junk: whether its box (however it has tumbled: its whole diagonal) is clear
## of this player's capsule, with Constants.JUNK_CLEAR_MARGIN to spare.
func _clear_of(player: Node) -> bool:
	var body := player as CharacterBody3D
	if body == null or not is_instance_valid(body):
		return true
	var collision := get_node_or_null("Collision") as CollisionShape3D
	if collision == null:
		return true
	var shape := collision.shape as BoxShape3D
	var reach := (shape.size.length() * 0.5 if shape != null else 0.5) + Constants.JUNK_CLEAR_MARGIN
	var capsule := 0.35
	for child: Node in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CapsuleShape3D:
			capsule = ((child as CollisionShape3D).shape as CapsuleShape3D).radius
			break
	var middle := collision.global_position
	return Vector2(middle.x - body.global_position.x, middle.z - body.global_position.z).length() > reach + capsule


## The middle of the bag's bottom face however it has tumbled (its box is
## VISUAL_HEIGHT tall each way from its middle).
func _bottom() -> Vector3:
	return global_transform * Vector3(0.0, _PropLooks.VISUAL_HEIGHT, 0.0) - Vector3(0.0, _PropLooks.VISUAL_HEIGHT, 0.0)


## Host: Chefty's bed caught this bag (a toss, or E from beside it). It's loaded
## now, counted once, here; every peer then glides it into its spot in the load
## (_rpc_bed_catch) and it goes, with the load's own bag showing in its place.
func _bed_catch(truck: Node) -> void:
	var slot := int(truck.call("bag_count"))
	var seconds := _settle_seconds_for(truck, global_transform, slot)
	var stats: Dictionary = _BedToss.stats
	stats["caught"] = int(stats["caught"]) + 1
	var reaction := [0, -1]
	if _toss_feet.is_finite():
		# How far you stood from the bed's middle, the way a player sizes up a toss.
		var middle: Vector3 = (truck.call("bed_transform") as Transform3D) * _BedToss.BED_MIDDLE
		var toss_m := Vector2(middle.x - _toss_feet.x, middle.z - _toss_feet.z).length()
		stats["longest_m"] = maxf(float(stats["longest_m"]), snappedf(toss_m, 0.01))
		if toss_m >= Constants.BED_LONG_TOSS_METERS:
			stats["long"] = int(stats["long"]) + 1
			var now := Net.server_time()
			if now - _long_quip_at >= Constants.BED_LONG_TOSS_QUIP_SECONDS and randf() < Constants.BED_LONG_TOSS_QUIP_CHANCE:
				_long_quip_at = now
				reaction = _long_toss_reaction()
	# Before the count goes up, so every peer holds the spot for this bag first.
	_rpc_bed_catch.rpc(slot, seconds, value, int(reaction[0]), int(reaction[1]))
	truck.call("accept_bags", 1, value)


## How long a bag whose body is at `body` (world) takes into load spot slot
## (bed_toss.gd settle_seconds()).
func _settle_seconds_for(truck: Node, body: Transform3D, slot: int) -> float:
	var bed: Transform3D = truck.call("bed_transform")
	return _BedToss.settle_seconds(bed.affine_inverse() * body, _BedLoad.slot(slot))


## Who reacts to a long toss and with what (Strings.TOSS_QUIPS, then TOSS_BRAGS
## counted on after it): a crewmate who was there to see it (in the thrower's
## zone, within Constants.BED_LONG_TOSS_WITNESS_METERS), else the thrower.
func _long_toss_reaction() -> Array:
	var others: Array[int] = []
	var zone := Net.player_zone(_thrower)
	for node: Node in get_tree().get_nodes_in_group("players"):
		var peer := node.name.to_int()
		if peer == _thrower or peer <= 0 or Net.player_zone(peer) != zone or Net.is_watcher(peer):
			continue
		if (node as Node3D).global_position.distance_to(global_position) <= Constants.BED_LONG_TOSS_WITNESS_METERS:
			others.append(peer)
	if not others.is_empty():
		return [others[randi() % others.size()], randi() % _Strings.TOSS_QUIPS.size()]
	return [_thrower, _Strings.TOSS_QUIPS.size() + randi() % _Strings.TOSS_BRAGS.size()]


## Host: a full Chefty bats the bag back out the way it came, off the pile, at
## most every BED_REFUSE_EVERY_SECONDS.
func _bed_refuse(truck: Node) -> void:
	var now := Net.server_time()
	if now - _refused_at < Constants.BED_REFUSE_EVERY_SECONDS:
		return
	_refused_at = now
	var bed: Transform3D = truck.call("bed_transform")
	var middle := bed * _BedToss.BED_MIDDLE
	var away := (_toss_feet - middle) if _toss_feet.is_finite() else -linear_velocity
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(global_position.x - middle.x, 0.0, global_position.z - middle.z)
	if away.length() < 0.1:
		away = bed.basis.x
	away = away.normalized()
	linear_velocity = away * Constants.BED_REFUSE_PUSH + Vector3.UP * Constants.BED_REFUSE_LIFT
	angular_velocity = Vector3(-away.z, 0.0, away.x) * randf_range(Constants.BED_REFUSE_SPIN_MIN, Constants.BED_REFUSE_SPIN_MAX)
	_airborne = true
	_BedToss.stats["refused"] = int(_BedToss.stats["refused"]) + 1
	_rpc_bed_refuse.rpc(global_position)


## Every peer: the bed caught this bag for load spot slot. Hold the spot, and
## glide from wherever this peer draws the bag (moving as it was) into it over
## seconds. amount is its dollars, popped when it lands; speaker and line are a
## crew reaction to show then (line -1 for none).
@rpc("authority", "call_local", "reliable")
func _rpc_bed_catch(slot: int, seconds: float, amount: int, speaker: int, line: int) -> void:
	var truck := get_tree().get_first_node_in_group("chefty")
	if truck == null or not truck.has_method("bed_transform"):
		return
	_BedToss.stats["catch_seen"] = int(_BedToss.stats["catch_seen"]) + 1
	var quip: Array = [speaker, line] if line >= 0 else []
	if _settling and _provisional and slot == _settle_slot:
		# This client's own toss, already gliding in on its say-so: carry on.
		_provisional = false
		_settle_amount = amount
		_settle_quip = quip
		if _settle_landed:
			_say_reaction()
		return
	if _settling and _provisional:
		# Its own guess took a spot someone else's bag got first.
		_abort_provisional()
	var drawn := global_transform
	var moving := linear_velocity
	if not Net.is_host():
		# What this peer sees: the look as drawn, not the newest snapshot.
		drawn = (%Visual as Node3D).global_transform * _visual_rest().affine_inverse()
		moving = _seen_vel
		# Barely moving: heaved in from someone's hands (E by the bed), as the host has it.
		if moving.length() < Constants.BED_HEAVE_SPEED:
			moving = Vector3.UP * Constants.BED_HAND_IN_LIFT
	_predicting = false
	_blend_left = 0.0
	_provisional = false
	_begin_settle(truck, slot, seconds, amount, quip, drawn, moving)
	if Net.is_host():
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_airborne = false
		_set_solid(false)


## Every peer: start gliding from drawn (moving at moving) into load spot slot
## over seconds, and hold that spot in the load for this bag.
func _begin_settle(truck: Node, slot: int, seconds: float, amount: int, quip: Array, drawn: Transform3D, moving: Vector3) -> void:
	_settling = true
	_settle_slot = slot
	_settle_seconds = maxf(seconds, 0.05)
	_settle_age = 0.0
	_settle_landed = false
	_settle_amount = amount
	_settle_quip = quip
	var bed: Transform3D = truck.call("bed_transform")
	_settle_plan = _BedToss.settle_plan(bed.affine_inverse() * drawn, bed.basis.inverse() * moving, _BedLoad.slot(slot), _settle_seconds)
	_refresh_label()
	var load_node := truck.call("bed_load") as Node
	if load_node != null:
		load_node.call("hold_slot", slot, self, amount)


## Every peer, each frame (the host on physics ticks): the glide into the spot,
## in the bed's space, so it rides along if Chefty moves. It lands moving down,
## sits a moment, and the host lets it go; the load's bag shows the same frame.
func _step_settle(delta: float) -> void:
	var truck := get_tree().get_first_node_in_group("chefty")
	if truck == null or not truck.has_method("bed_transform"):
		if Net.is_host():
			queue_free()
		return
	_settle_age += delta
	var t := clampf(_settle_age / _settle_seconds, 0.0, 1.0)
	var spot := _BedLoad.slot(_settle_slot)
	var bed: Transform3D = truck.call("bed_transform")
	var world := bed * _BedToss.settle_at(_settle_plan, _settle_age)
	settle_gap_m = world.origin.distance_to(bed * spot.origin)
	if Net.is_host():
		global_transform = world
	else:
		(%Visual as Node3D).global_transform = world * Transform3D(Basis.IDENTITY, Vector3(0.0, _PropLooks.VISUAL_HEIGHT, 0.0))
	if t >= 1.0 and not _settle_landed:
		_settle_landed = true
		_land(truck, world)
	if Net.is_host() and _settle_age >= _settle_seconds + Constants.BED_SETTLE_HOLD_SECONDS and not is_queued_for_deletion():
		queue_free()


## Every peer: it hit the pile. A thump, a puff of leaves, its dollars, a squash,
## and the crew's reaction if the host picked one.
func _land(truck: Node, where: Transform3D) -> void:
	_BedToss.stats["land_seen"] = int(_BedToss.stats["land_seen"]) + 1
	var load_node := truck.call("bed_load") as Node
	if load_node != null:
		load_node.call("land_fx", where.origin, _settle_amount)
	_BedLoad.squash(%Visual.get_node_or_null("Look") as Node3D)
	_say_reaction()


## The crew's reaction the host picked for this toss, if any, as a caption.
func _say_reaction() -> void:
	if _settle_quip.size() != 2:
		return
	var speaker := int(_settle_quip[0])
	var line := int(_settle_quip[1])
	_settle_quip = []
	var text := _Strings.TOSS_QUIPS[line] if line < _Strings.TOSS_QUIPS.size() else _Strings.TOSS_BRAGS[(line - _Strings.TOSS_QUIPS.size()) % _Strings.TOSS_BRAGS.size()]
	_BedToss.stats["reactions_seen"] = int(_BedToss.stats.get("reactions_seen", 0)) + 1
	var quips := get_tree().root.find_child("Quips", true, false)
	if quips != null:
		quips.call("show_caption", _Strings.TOSS_UI["quip_said"] % [Net.player_name(speaker), text])


## Every peer: a full Chefty batted a bag back out. The pile gives and springs
## back, with a floomp and a few leaves.
@rpc("authority", "call_local", "reliable")
func _rpc_bed_refuse(at: Vector3) -> void:
	_BedToss.stats["full_seen"] = int(_BedToss.stats["full_seen"]) + 1
	var truck := get_tree().get_first_node_in_group("chefty")
	var load_node := truck.call("bed_load") as Node if truck != null and truck.has_method("bed_load") else null
	if load_node != null:
		load_node.call("refuse_fx", at)


## Host only. Returns true when the bag fits. bag_value is that bag's dollars.
func receive_bag(bag_value: int = 0) -> bool:
	if kind != "wheelbarrow" or stored_bags >= Campaign.wheelbarrow_capacity():
		return false
	stored_bags += 1
	stored_value += bag_value
	return true


func _try_unload_wheelbarrow() -> void:
	if kind != "wheelbarrow" or not is_loose() or stored_bags <= 0 or not _airborne:
		return
	var truck := get_tree().get_first_node_in_group("chefty")
	if truck == null:
		return
	var truck_at: Vector3 = truck.call("body_position")
	if global_position.distance_to(truck_at) > Constants.TRUCK_UNLOAD_RADIUS:
		return
	# If only some bags fit, the truck takes that share of the value.
	var taken := int(truck.call("accept_bags", stored_bags, stored_value))
	if taken > 0:
		var moved_value := int(round(float(stored_value) * float(taken) / float(stored_bags)))
		stored_bags -= taken
		stored_value = maxi(0, stored_value - moved_value)
	_airborne = false


func _load_held(peer_id: int) -> void:
	if kind != "wheelbarrow" or stored_bags >= Campaign.wheelbarrow_capacity():
		return
	var player := _player(peer_id)
	if player == null or player.global_position.distance_to(global_position) > GRAB_REACH:
		return
	for node: Node in get_tree().get_nodes_in_group("props"):
		if node == self or str(node.get("kind")) != "leaf_bag":
			continue
		if int(node.get("held_by")) != peer_id:
			continue
		stored_bags += 1
		stored_value += int(node.get("value"))
		node.queue_free()
		return


func _apply_color() -> void:
	if not is_node_ready():
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	%Visual.material_override = material


func _refresh_label() -> void:
	if not is_node_ready():
		return
	# Real shapes from props/prop_looks.gd. The prompt names things, so only the
	# wheelbarrow keeps a floating count.
	_PropLooks.dress(self, kind, color)
	# Bags show what they're worth, so a fat bag from a big pile reads as a prize.
	# Not while it flies or settles into Chefty's load: the price would pop up in
	# your face as it leaves your hands, and the load pops its own.
	%Label.visible = kind == "wheelbarrow" or (kind == "leaf_bag" and value > 0 and not _settling and not is_flying())
	# Not on the thing in your own hands: it would sit in the middle of your view.
	if held_by != 0 and held_by == Net.local_peer_id() or pocketed_by != 0:
		%Label.visible = false
	if kind == "wheelbarrow":
		var capacity := Campaign.wheelbarrow_capacity()
		# A count at its cap already says it's full.
		%Label.text = "%d/%d  $%d" % [stored_bags, capacity, stored_value]
		_PropLooks.show_bags(self, stored_bags)
	elif kind == "leaf_bag":
		%Label.text = "$%d" % value
	else:
		%Label.text = label if label != "" else name


## A held kind placed by props/prop_looks.gd HOLDS (its entry has "at"), and not
## a tool, which pose_tool places.
func _held_the_holds_way() -> bool:
	return not Constants.TOOL_PRICES.has(kind) and _PropLooks.hold_of(self).has("at")


func _hold_position(player: CharacterBody3D) -> Vector3:
	# The rake is held low and close, tines on the leaves. Everything else at chest height.
	var forward := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	if _held_the_holds_way():
		# Where its look is held (prop_looks.gd pose_held), in the holder's body
		# space: the body rides with it, so a set-down starts from the hands.
		var level := Basis(Vector3.UP, player.global_rotation.y)
		return player.global_position + level * (_PropLooks.hold_of(self)["at"] as Vector3)
	match kind:
		"lawn_mower":
			# Pushed along the ground in front.
			return player.global_position + forward * 1.15
		"pressure_washer":
			# Rolled along at your side while you hold its wand.
			return player.global_position + right * 0.85 + forward * 0.2
		"ladder":
			# On the shoulder.
			return player.global_position + Vector3(0.0, 1.45, 0.0) + right * 0.3
		"leaf_blower", "hedge_trimmer", "hose", "paint_roller":
			return player.global_position + Vector3(0.0, 0.8, 0.0) + forward * 0.55 + right * 0.25
		"leaf_bag":
			# Hung low in front from both hands by its rolled top, where your arms reach it.
			var head := player.get_node_or_null("Visual/Head") as Node3D
			if head != null:
				# Follows the view's pitch only a little, so it neither rides up over
				# your face looking up nor sinks into your belly looking down.
				var pitch := clampf(head.rotation.x, -0.35, 0.25)
				var at := (head.get_parent() as Node3D).global_transform * Transform3D(Basis(Vector3.RIGHT, pitch), head.position) * _PropLooks.BAG_HANDS
				return at - player.global_basis * ((_PropLooks.BAG_RIM[0] + _PropLooks.BAG_RIM[1]) * 0.5)
	if kind == "rake":
		# A little to the right, so the handle doesn't split a first-person view in half.
		return player.global_position + Vector3(0.0, 0.75, 0.0) + (-player.global_transform.basis.z) * 0.9 + player.global_transform.basis.x * 0.35
	return player.global_position + Vector3(0.0, 1.2, 0.0) + (-player.global_transform.basis.z) * 1.15


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_grab() -> void:
	if Net.is_host():
		_handle_grab(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_drop() -> void:
	if Net.is_host():
		_handle_release(multiplayer.get_remote_sender_id(), Vector3.ZERO)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_throw(direction: Vector3, power: float, from: Vector3) -> void:
	if Net.is_host():
		_handle_release(multiplayer.get_remote_sender_id(), direction, power, from)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_load() -> void:
	if Net.is_host():
		_load_held(multiplayer.get_remote_sender_id())
