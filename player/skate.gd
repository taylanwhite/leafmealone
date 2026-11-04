extends Node

## Authority: the owning peer rides (step, toggle, wipeout); every peer reads
## (board_state, seen). The Gutter Shredder (driving chunk G1; docs/GAME.md "The
## Gutter Shredder"): your own skateboard, bought at Homie Depot, ridden through
## your own movement authority like walking. Kept out of player.gd so its hooks
## there stay a few lines; player/skate_view.gd draws it on every peer.
##
## Riding: hold move_forward to kick-push, move_back drags a foot, move_left and
## move_right carve (the mouse turns you too), crouch tucks. jump ollies; in the air
## move_left/move_right spin, primary kickflips, secondary heelflips, and crouch
## grabs. Land within SKATE_LAND_ANGLE of the way you're rolling (forward or fakie)
## and not mid-flip, or you wipe out. Jump onto a curb along it to grind.
## Wipeouts: a bad landing, a wall, a lawn at speed, a bonk, someone in your way.
## A leaf pile at speed dives you in. Points are bragging only.
##
## What everyone sees comes from the player's replicated on_board, skate_trick,
## wipeout, anim_state (SKATE, SKATE_AIR), velocity and body_yaw.

const _Strings = preload("res://ui/strings.gd")

## player.gd's AnimState values (appended to its enum).
const ANIM_KNOCKED: int = 5
const ANIM_SKATE: int = 6
const ANIM_SKATE_AIR: int = 7
## skate_trick (the contract in gap-specs/driving.json): what the board is doing.
const TRICK_NONE: int = 0
const TRICK_OLLIE: int = 1
const TRICK_KICKFLIP: int = 2
const TRICK_HEELFLIP: int = 3
const TRICK_SPIN: int = 4
const TRICK_GRAB: int = 5
const TRICK_GRIND: int = 6
## How often the owner looks at what's in hand (s): a list walk over every prop.
const HELD_CHECK_SECONDS: float = 0.25

enum Mode { ROLL, AIR, GRIND, SKITCH }

## Every peer, per player (by peer id as a string), from the replicated values:
## on_board now, mounted (ever seen on a board), max_trick (the highest
## skate_trick seen), wipeout (ever seen), wipeouts (falls seen). For tests.
static var seen: Dictionary = {}

var player: CharacterBody3D
## Tests: the keys this player presses instead of the keyboard (push, brake,
## steer, tuck, and the one-shots jump, kickflip, heelflip). Empty: the keyboard.
var dev_input: Dictionary = {}

## Owner: what this ride has done, for tests and the popup: tricks landed by name
## (ollie, kickflip, heelflip, spin, grab, grind), wipeouts by reason, the last
## line {names, points, combo, score, clean}, the best score this session, and the
## highest point of the last air (m above where it took off).
var tricks: Dictionary = {}
var wipeouts: Dictionary = {}
var last_line: Dictionary = {}
var best_score: int = 0
var last_air_height: float = 0.0
## Owner: what the last wall bail hit (its node path and where), for tests and logs.
var last_wall: String = ""
## Owner: pushes made (skate_view.gd plays the kick on the owner from it).
var pushes: int = 0

var _mode: Mode = Mode.ROLL
var _push_wait: float = 0.0
var _push_left: float = 0.0
var _flip_left: float = 0.0
var _flip_trick: int = TRICK_NONE
var _air_time: float = 0.0
var _air_from: float = 0.0
var _air_peak: float = 0.0
var _jumped: bool = false
var _spin: float = 0.0
var _flips: Array[String] = []
var _grabbed: bool = false
var _line: Array[String] = []
var _line_points: int = 0
var _combo: int = 0
var _last_land_ms: int = -100000
var _grind_from := Vector3.ZERO
var _grind_to := Vector3.ZERO
var _grind_time: float = 0.0
var _held_wait: float = 0.0
var _too_heavy: bool = false
var _was_on_floor: bool = true
var _climb: float = 0.0
var _last_yaw: float = 0.0
## Owner: how fast the board turned last tick (rad/s), for the lean.
var yaw_rate: float = 0.0

## Owner, skitching (driving G2): the Chefty you hang on to and which side of it
## (1 its right, -1 its left), how it's going as read here (smoothed: its
## velocity, its turn rate), its yaw last tick, the board's yaw as last set, and
## whether it crashed while you held on.
var _tow: Node3D = null
var _tow_solid: PhysicsBody3D = null
## Let go: the truck's Solid you still pass through, and for how long (s).
var _clear_of: PhysicsBody3D = null
var _clear_left: float = 0.0
var _tow_side: float = 1.0
var _tow_vel := Vector3.ZERO
var _tow_turn: float = 0.0
var _tow_accel: float = 0.0
var _tow_last_yaw: float = 0.0
var _tow_set_yaw: float = 0.0
var _tow_bumped: bool = false
## Seconds held on above SKITCH_MAX_SPEED (it drains back below it).
var _tow_strain: float = 0.0
## Owner, for tests and logs: times grabbed on, seconds towed, why you last let go
## (hands, ollie, slipped, lost, off; a bail is a wipeout reason instead), and the
## worst gap to the spot behind Chefty while towed (m).
var skitches: int = 0
var skitch_seconds: float = 0.0
var last_let_go: String = ""
var skitch_gap_max: float = 0.0

static var _curbs: Array = []
static var _curbs_world: int = 0


func _ready() -> void:
	# After the player (100) and the body: the seen dict reads this tick's values.
	process_physics_priority = 105


func _physics_process(delta: float) -> void:
	if player == null or multiplayer.multiplayer_peer == null:
		return
	_note_seen()
	if not player.is_multiplayer_authority():
		return
	# Down after a wipeout until the stun runs out (player.gd _step_stunned moves you).
	if bool(player.get("wipeout")) and float(player.get("_stun_left")) <= 0.0:
		player.set("wipeout", false)
	_ease_look_back(delta)
	if _clear_of != null:
		_clear_left -= delta
		if _clear_left <= 0.0 or not is_instance_valid(_clear_of):
			if is_instance_valid(_clear_of) and _clear_of != _tow_solid:
				player.remove_collision_exception_with(_clear_of)
			_clear_of = null
	if not bool(player.get("on_board")):
		return
	var why := _must_get_off()
	if why != "":
		dismount(why == "hands")
	_held_wait -= delta


# ---------------------------------------------------------------- every peer

## Audio's contract (gap-specs/critic.md C13): audio/board_sound.gd reads this.
## {on_board, speed (m/s along the ground), on_ground, grinding}.
func board_state() -> Dictionary:
	var on := player != null and bool(player.get("on_board"))
	var flat := Vector2(player.velocity.x, player.velocity.z).length() if player != null else 0.0
	return {
		"on_board": on,
		"speed": flat if on else 0.0,
		"on_ground": on and int(player.get("anim_state")) != ANIM_SKATE_AIR,
		"grinding": on and int(player.get("skate_trick")) == TRICK_GRIND,
	}


func _note_seen() -> void:
	var key := str(player.name)
	var entry: Dictionary = seen.get(key, {"on_board": false, "mounted": false, "max_trick": 0, "wipeout": false, "wipeouts": 0})
	var on := bool(player.get("on_board"))
	var falling := bool(player.get("wipeout"))
	if falling and not bool(entry.get("_falling", false)):
		entry["wipeouts"] = int(entry["wipeouts"]) + 1
	entry["_falling"] = falling
	entry["on_board"] = on
	entry["mounted"] = bool(entry["mounted"]) or on
	entry["wipeout"] = bool(entry["wipeout"]) or falling
	entry["max_trick"] = maxi(int(entry["max_trick"]), int(player.get("skate_trick")))
	# driving G2: seen hanging on behind Chefty, and how far over the flop went here.
	entry["skitch"] = bool(entry.get("skitch", false)) or bool(player.get("skitch"))
	var body := player.get_node_or_null("Visual/CartoonBody")
	if body != null and "flop_max_angle" in body:
		entry["flop"] = maxf(float(entry.get("flop", 0.0)), float(body.get("flop_max_angle")))
	seen[key] = entry


# ---------------------------------------------------------------- owner: on and off

## The board key. True when it did something (got on, got off, or refused with a
## wobble). Without a board it does nothing at all.
func toggle() -> bool:
	if not _owns_board():
		return false
	if bool(player.get("on_board")):
		dismount(false)
		return true
	if not can_mount():
		# The world says no: a wobble and an "eh", no words.
		var body := player.get_node_or_null("Visual/CartoonBody")
		if body != null and not bool(body.call("is_gesturing")):
			body.call("gesture", "stumble")
		player.call("say", "vo_eh")
		return true
	mount()
	return true


func _owns_board() -> bool:
	return Campaign.peer_has_unlock(player.name.to_int(), &"skateboard")


## Whether this player could hop on right now: owns the board, feet on the
## ground, hands not full of something heavy, and free to move.
func can_mount() -> bool:
	return why_not() == ""


## Why the board key wouldn't get you on right now ("" when it would): no_board,
## airborne, hands, or what _blocked() says (seat, busy, zone). For tools and tests.
func why_not() -> String:
	if not _owns_board():
		return "no_board"
	if not player.is_on_floor():
		return "airborne"
	var blocked := _blocked()
	if blocked != "":
		return blocked
	return "hands" if _hands_too_full() else ""


func mount() -> void:
	player.set("on_board", true)
	player.set("skate_trick", TRICK_NONE)
	player.set("anim_state", ANIM_SKATE)
	_mode = Mode.ROLL
	_reset_air()
	_push_wait = 0.0
	_push_left = 0.0
	_last_yaw = float(player.get("body_yaw"))
	_was_on_floor = true
	_climb = 0.0
	_held_wait = HELD_CHECK_SECONDS
	_too_heavy = false
	# Standing up straight on it (a crouch's short capsule would stay short).
	player.call("_apply_stance", false)
	# A running start carries on: the walk's speed is now the board's.


## Step off. hands: because of what's in hand (picked up something heavy).
func dismount(_hands: bool = false) -> void:
	if not bool(player.get("on_board")):
		return
	_release_tow("off")
	_settle_line(true)
	player.set("on_board", false)
	player.set("skate_trick", TRICK_NONE)
	_mode = Mode.ROLL
	var flat := Vector2(player.velocity.x, player.velocity.z)
	# Stepping off fast is a few running steps, not a stop on a dime.
	if flat.length() > Constants.SKATE_STEP_OFF_SPEED:
		flat = flat.normalized() * Constants.SKATE_STEP_OFF_SPEED
		var body := player.get_node_or_null("Visual/CartoonBody")
		if body != null and not bool(body.call("is_gesturing")):
			body.call("gesture", "stumble")
	player.velocity = Vector3(flat.x, player.velocity.y, flat.y)


## Why the rider has to come off right now, or "".
func _must_get_off() -> String:
	var blocked := _blocked()
	if blocked != "":
		return blocked
	if _held_wait <= 0.0:
		_held_wait = HELD_CHECK_SECONDS
		_too_heavy = _hands_too_full()
	return "hands" if _too_heavy else ""


func _blocked() -> String:
	if bool(player.call("in_vehicle")) or player.call("seat_ride") != null:
		return "seat"
	if bool(player.call("is_hidden")) or bool(player.call("is_staged")) or bool(player.call("is_control_locked")):
		return "busy"
	if int(player.get("carried_by")) != 0 or int(player.get("carrying")) != 0 or bool(player.get("thrown")):
		return "busy"
	if player.get("_ladder") != null or bool(player.call("is_sleeping")) or float(player.get("_stun_left")) > 0.0:
		return "busy"
	var zone := Net.player_zone(player.name.to_int())
	if zone != Net.Zone.STORE and zone != Net.Zone.LOT and zone != Net.Zone.TOWN:
		return "zone"
	return ""


func _hands_too_full() -> bool:
	var held := player.call("_held_prop") as Node
	if held == null:
		return false
	if Constants.SKATE_CARRY_ANY_WEIGHT.has(str(held.get("kind"))):
		return false
	return held.has_method("weight_kg") and float(held.call("weight_kg")) > Constants.SKATE_MAX_CARRY_KG


# ---------------------------------------------------------------- owner: riding

## Owner, every physics tick on the board, in place of walking (player.gd).
func step(delta: float) -> void:
	var input := _read_input()
	match _mode:
		Mode.AIR:
			_step_air(delta, input)
		Mode.GRIND:
			_step_grind(delta, input)
		Mode.SKITCH:
			_step_skitch(delta, input)
		_:
			_step_roll(delta, input)
	if not bool(player.get("on_board")):
		return
	var now_yaw := float(player.get("body_yaw"))
	yaw_rate = angle_difference(_last_yaw, now_yaw) / maxf(delta, 0.0001) if _mode != Mode.AIR else 0.0
	_last_yaw = now_yaw
	player.set("anim_state", ANIM_SKATE_AIR if _mode == Mode.AIR else ANIM_SKATE)
	player.call("_stay_on_the_pad")


func _step_roll(delta: float, input: Dictionary) -> void:
	var forward := _forward()
	var flat := Vector2(player.velocity.x, player.velocity.z)
	var speed := flat.length()
	var along := flat.dot(forward)
	# Carve: the board turns; the wheels drag the roll round after it.
	var steer := float(input.get("steer", 0.0))
	if steer != 0.0:
		var share := lerpf(Constants.SKATE_CARVE_STILL_SHARE, 1.0, clampf(speed / Constants.SKATE_CARVE_FULL_AT, 0.0, 1.0))
		player.set("body_yaw", float(player.get("body_yaw")) - steer * Constants.SKATE_CARVE_RATE * share * delta)
		forward = _forward()
	var travel := forward if along >= 0.0 else -forward
	if speed > 0.01:
		var dir := flat / speed
		var off := dir.angle_to(travel)
		dir = dir.rotated(clampf(off, -Constants.SKATE_GRIP_RATE * delta, Constants.SKATE_GRIP_RATE * delta))
		speed = maxf(0.0, speed - Constants.SKATE_SLIDE_SCRUB * absf(sin(off)) * speed * delta)
		travel = dir
	var surface := surface_under()
	var soft := surface == &"grass" or surface == &"water"
	if soft and speed > Constants.SKATE_LAWN_BAIL_SPEED:
		wipeout("lawn")
		return
	# Push, brake, coast.
	_push_wait -= delta
	if bool(input.get("push", false)) and _push_wait <= 0.0 and speed < Constants.SKATE_MAX_PUSH_SPEED and not soft:
		_push_wait = Constants.SKATE_PUSH_SECONDS
		_push_left = Constants.SKATE_PUSH_EASE
		pushes += 1
		if speed < 0.05:
			travel = forward
	if _push_left > 0.0 and not soft:
		var share := minf(delta, _push_left) / Constants.SKATE_PUSH_EASE
		_push_left -= delta
		speed = minf(speed + Constants.SKATE_PUSH_SPEED * share, maxf(speed, Constants.SKATE_MAX_PUSH_SPEED))
	var drag := Constants.SKATE_COAST_DECEL
	if bool(input.get("tuck", false)):
		drag *= Constants.SKATE_TUCK_DRAG_SHARE
	if soft:
		drag = Constants.SKATE_GRASS_DECEL
	if bool(input.get("brake", false)):
		drag = maxf(drag, Constants.SKATE_BRAKE_DECEL)
	speed = minf(move_toward(speed, 0.0, drag * delta), Constants.SKATE_TOP_SPEED)
	flat = travel * speed
	var vy := player.velocity.y if player.is_on_floor() else player.velocity.y - _gravity() * delta
	if player.is_on_floor() and bool(input.get("jump", false)):
		vy = Constants.SKATE_OLLIE_SPEED
		_take_off(true)
	player.velocity = Vector3(flat.x, vy, flat.y)
	var before := player.velocity
	var lifted_from := player.global_position.y
	player.move_and_slide()
	if _walls(before):
		return
	if _bumped_someone(before):
		return
	if speed > Constants.SKATE_PILE_SPEED and bool(player.call("_on_pile")):
		_dive_in_pile()
		return
	if _mode == Mode.ROLL and not player.is_on_floor():
		# Rolled off something (the ramp's lip, a porch step): airborne without a
		# pop. Going up a slope as you leave it, you leave going up it (the slide
		# keeps the speed level), and the ramp's kicker adds a little more.
		# (How fast the wheels were climbing, from where they actually went: the
		# lip's edge reads as flat floor for a tick.)
		if _climb > Constants.SKATE_RAMP_CLIMB_MIN:
			player.velocity.y = maxf(player.velocity.y, _climb) + Constants.SKATE_RAMP_POP
		_take_off(false)
	elif player.is_on_floor():
		var rise := (player.global_position.y - lifted_from) / maxf(delta, 0.0001)
		# The best of the last few ticks' climb, fading.
		_climb = maxf(rise, _climb - Constants.SKATE_RAMP_CLIMB_FADE * delta)
	_was_on_floor = player.is_on_floor()


func _step_air(delta: float, input: Dictionary) -> void:
	_air_time += delta
	_air_peak = maxf(_air_peak, player.global_position.y)
	# Every turn in the air is spin: the keys' and the mouse's.
	_spin += angle_difference(_last_yaw, float(player.get("body_yaw")))
	var steer := float(input.get("steer", 0.0))
	if steer != 0.0:
		var turn := -steer * Constants.SKATE_SPIN_RATE * delta
		player.set("body_yaw", float(player.get("body_yaw")) + turn)
		_spin += turn
	_flip_left = maxf(0.0, _flip_left - delta)
	if _flip_left <= 0.0:
		if bool(input.get("kickflip", false)):
			_start_flip(TRICK_KICKFLIP, "kickflip")
		elif bool(input.get("heelflip", false)):
			_start_flip(TRICK_HEELFLIP, "heelflip")
	var grabbing := bool(input.get("tuck", false)) and _air_time > Constants.SKATE_GRAB_DELAY
	_grabbed = _grabbed or grabbing
	# What the board is doing, for everyone: a flip, else a grab, else a spin.
	var trick := TRICK_OLLIE if _jumped else TRICK_NONE
	if _flip_left > 0.0:
		trick = _flip_trick
	elif grabbing:
		trick = TRICK_GRAB
	elif absf(_spin) > Constants.SKATE_SPIN_SHOW_RAD:
		trick = TRICK_SPIN
	player.set("skate_trick", trick)
	player.velocity.y -= _gravity() * delta
	var before := player.velocity
	player.move_and_slide()
	if _walls(before):
		return
	if player.is_on_floor():
		_land()


func _start_flip(trick: int, name_id: String) -> void:
	_flip_left = Constants.SKATE_FLIP_SECONDS
	_flip_trick = trick
	_flips.append(name_id)
	player.set("skate_trick", trick)


func _take_off(jumped: bool) -> void:
	_mode = Mode.AIR
	_reset_air()
	_jumped = jumped
	_air_from = player.global_position.y
	_air_peak = _air_from
	player.set("skate_trick", TRICK_OLLIE if jumped else TRICK_NONE)
	player.set("anim_state", ANIM_SKATE_AIR)


func _reset_air() -> void:
	_air_time = 0.0
	_spin = 0.0
	_flips.clear()
	_grabbed = false
	_flip_left = 0.0
	_jumped = false


func _land() -> void:
	_mode = Mode.ROLL
	last_air_height = _air_peak - _air_from
	var flat := Vector2(player.velocity.x, player.velocity.z)
	var speed := flat.length()
	var forward := _forward()
	# Most of the way round, the feet catch it; any more left is a board landing on its edge.
	if _flip_left > Constants.SKATE_FLIP_CATCH_SECONDS:
		wipeout("landing")
		return
	_flip_left = 0.0
	if speed > Constants.SKATE_LAND_ANY_SPEED:
		var off := absf((flat / speed).angle_to(forward))
		if off > Constants.SKATE_LAND_ANGLE and off < PI - Constants.SKATE_LAND_ANGLE:
			wipeout("landing")
			return
	player.set("skate_trick", TRICK_NONE)
	if _try_grind():
		return
	if _air_time < Constants.SKATE_MIN_AIR_SECONDS and _flips.is_empty() and not _jumped:
		return
	_score_air()
	_settle_line(false)


## What this air was worth: an ollie, each flip, each half turn, a grab.
func _score_air() -> void:
	var points: Dictionary = Constants.SKATE_TRICK_POINTS
	var names: Array[String] = []
	var total := 0
	if _jumped:
		_count("ollie")
		total += int(points["ollie"])
	for flip: String in _flips:
		_count(flip)
		names.append(str(_Strings.UI["trick_" + flip]))
		total += int(points[flip])
	var halves := roundi(absf(_spin) / PI)
	if halves > 0:
		_count("spin", halves)
		names.append(str(_Strings.UI["trick_spin"]) % (halves * 180))
		total += int(points["spin"]) * halves
	if _grabbed:
		_count("grab")
		names.append(str(_Strings.UI["trick_grab"]))
		total += int(points["grab"])
	if names.is_empty() and _jumped:
		names.append(str(_Strings.UI["trick_ollie"]))
	_line.append_array(names)
	_line_points += total
	_reset_air()


## A line ends: on a clean landing (scored, combo'd and shown) or on a bail.
func _settle_line(bailed: bool) -> void:
	if _line.is_empty() and not bailed:
		return
	var now := Time.get_ticks_msec()
	if bailed:
		if not _line.is_empty():
			last_line = {"names": _line.duplicate(), "points": _line_points, "combo": _combo, "score": 0, "clean": false}
		_line.clear()
		_line_points = 0
		_combo = 0
		return
	_combo = _combo + 1 if now - _last_land_ms <= int(Constants.SKATE_COMBO_WINDOW * 1000.0) and _combo > 0 else 1
	_last_land_ms = now
	var score := _line_points * _combo
	best_score = maxi(best_score, score)
	last_line = {"names": _line.duplicate(), "points": _line_points, "combo": _combo, "score": score, "clean": true}
	var text := str(_Strings.UI["trick_join"]).join(PackedStringArray(_line))
	if _combo > 1:
		text += str(_Strings.UI["trick_combo"]) % _combo
	text += str(_Strings.UI["trick_score"]) % score
	# A plain ollie on its own says nothing; anything more gets the popup.
	var plain := _line.size() == 1 and _line[0] == str(_Strings.UI["trick_ollie"]) and _combo == 1
	_line.clear()
	_line_points = 0
	if not plain:
		_popup(text, true)


func _count(trick: String, amount: int = 1) -> void:
	tricks[trick] = int(tricks.get(trick, 0)) + amount


# ---------------------------------------------------------------- owner: grinds

## Landing on a curb along it: grind. True when it caught.
func _try_grind() -> bool:
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return false
	if _curbs_world != world.get_instance_id():
		_curbs_world = world.get_instance_id()
		_curbs = _curb_list()
	if _curbs.is_empty():
		return false
	var at := player.global_position
	var flat := Vector2(player.velocity.x, player.velocity.z)
	if flat.length() < Constants.SKATE_GRIND_MIN_SPEED:
		return false
	var forward := _forward()
	for curb: Array in _curbs:
		var a: Vector3 = curb[0]
		var b: Vector3 = curb[1]
		var line := Vector2(b.x - a.x, b.z - a.z)
		var length := line.length()
		if length < 1.0:
			continue
		var dir := line / length
		var rel := Vector2(at.x - a.x, at.z - a.z)
		var t := rel.dot(dir)
		if t < Constants.SKATE_GRIND_END_MARGIN or t > length - Constants.SKATE_GRIND_END_MARGIN:
			continue
		if absf(rel.dot(Vector2(-dir.y, dir.x))) > Constants.SKATE_GRIND_SNAP:
			continue
		var off := absf(forward.angle_to(dir))
		if off > Constants.SKATE_GRIND_ANGLE and off < PI - Constants.SKATE_GRIND_ANGLE:
			continue
		var going := dir if flat.dot(dir) >= 0.0 else -dir
		_grind_from = a if going == dir else b
		_grind_to = b if going == dir else a
		_mode = Mode.GRIND
		_grind_time = 0.0
		_score_air()
		player.set("skate_trick", TRICK_GRIND)
		var on := Vector2(a.x, a.z) + dir * t
		player.global_position = Vector3(on.x, player.global_position.y, on.y)
		player.velocity = Vector3(going.x * flat.length(), 0.0, going.y * flat.length())
		return true
	return false


func _step_grind(delta: float, input: Dictionary) -> void:
	var line := Vector2(_grind_to.x - _grind_from.x, _grind_to.z - _grind_from.z)
	var dir := line.normalized()
	var speed := maxf(0.0, Vector2(player.velocity.x, player.velocity.z).length() - Constants.SKATE_GRIND_DECEL * delta)
	_grind_time += delta
	var at := player.global_position
	var t := Vector2(at.x - _grind_from.x, at.z - _grind_from.z).dot(dir)
	var ended := speed < Constants.SKATE_GRIND_MIN_SPEED or t >= line.length() - Constants.SKATE_GRIND_RUN_OUT
	var jump := bool(input.get("jump", false))
	if ended or jump or not player.is_on_floor():
		_end_grind()
		if jump and player.is_on_floor():
			player.velocity.y = Constants.SKATE_OLLIE_SPEED
			_take_off(true)
			player.move_and_slide()
		elif not ended and not player.is_on_floor():
			_take_off(false)
		else:
			_settle_line(false)
		return
	# Steering off the curb drops you off it, onto the road.
	var steer := float(input.get("steer", 0.0))
	if steer != 0.0:
		player.set("body_yaw", float(player.get("body_yaw")) - steer * Constants.SKATE_CARVE_RATE * delta)
		if absf(_forward().angle_to(dir)) > Constants.SKATE_GRIND_ANGLE and absf(_forward().angle_to(dir)) < PI - Constants.SKATE_GRIND_ANGLE:
			_end_grind()
			_settle_line(false)
			return
	player.velocity = Vector3(dir.x * speed, Constants.SKATE_GRIND_HOLD_DOWN, dir.y * speed)
	player.move_and_slide()


func _end_grind() -> void:
	_mode = Mode.ROLL
	var seconds := _grind_time
	if seconds > Constants.SKATE_GRIND_MIN_SECONDS:
		_count("grind")
		var tenths := roundi(seconds * 10.0)
		_line.append(str(_Strings.UI["trick_grind"]))
		_line_points += roundi(float(Constants.SKATE_TRICK_POINTS["grind"]) * float(tenths) / 10.0)
	player.set("skate_trick", TRICK_NONE)


## Every curb a board can grind: the connected town's (TownMap.curb_segments).
## The legacy pads have none.
func _curb_list() -> Array:
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not bool(world.call("is_town_map")):
		return []
	return TownMap.curb_segments()


# ---------------------------------------------------------------- owner: skitching (driving G2)

## Where a skater here could grab on behind Chefty right now: {chefty, side, at}
## (at: the spot the board is towed on), or {} when there's nowhere. On the board,
## rolling, in reach of a free side's spot, and going about Chefty's speed.
func skitch_spot() -> Dictionary:
	if not bool(player.get("on_board")) or bool(player.get("skitch")) or _mode != Mode.ROLL or not player.is_on_floor():
		return {}
	var me := player.global_position
	for truck: Node in get_tree().get_nodes_in_group("vehicles"):
		var chefty := truck as Node3D
		if chefty == null or not chefty.is_in_group("chefty") or not chefty.has_method("tow_point"):
			continue
		var rel := (chefty.call("drawn_velocity") as Vector3) - player.velocity
		if Vector2(rel.x, rel.z).length() > Constants.SKITCH_GRAB_REL_SPEED:
			continue
		var local := (chefty.call("tow_point") as Transform3D).affine_inverse() * me
		var near := 1.0 if local.x >= 0.0 else -1.0
		for side: float in [near, -near]:
			if _side_taken(chefty, side):
				continue
			var at := hold_spot(chefty, side)
			if Vector2(at.x - me.x, at.z - me.z).length() <= Constants.SKITCH_GRAB_REACH:
				return {"chefty": chefty, "side": side, "at": at}
	return {}


## The spot behind Chefty a towed board rides on (world), on its side (1 right, -1 left).
static func hold_spot(chefty: Node3D, side: float) -> Vector3:
	var tow: Transform3D = chefty.call("tow_point")
	return tow * Vector3(side * Constants.SKITCH_SIDE, 0.0, -Constants.SKITCH_IN)


## Where the towed skater's hand is on Chefty's rear bumper (world).
static func grip_point(chefty: Node3D, side: float) -> Vector3:
	var grip := Constants.SKITCH_GRIP
	return (chefty.call("body_transform") as Transform3D) * Vector3(side * grip.x, grip.y, grip.z)


## Someone else already hanging on to that side.
func _side_taken(chefty: Node3D, side: float) -> bool:
	for node: Node in get_tree().get_nodes_in_group("players"):
		var other := node as Node3D
		if other == null or other == player or not bool(other.get("skitch")):
			continue
		var local := (chefty.call("tow_point") as Transform3D).affine_inverse() * other.global_position
		if (local.x >= 0.0) == (side > 0.0):
			return true
	return false


## E's prompt at Chefty's tailgate on the board: {text, at, source}, or {}.
func skitch_hint() -> Dictionary:
	var spot := skitch_spot()
	if spot.is_empty():
		return {}
	var at := grip_point(spot["chefty"] as Node3D, float(spot["side"])) + Vector3.UP * 0.6
	return {"text": _Strings.UI["prompt_skitch"], "at": at, "source": "skitch"}


## E at Chefty's tailgate on the board: grab on. True when you did.
func grab_on() -> bool:
	var spot := skitch_spot()
	if spot.is_empty():
		return false
	_tow = spot["chefty"] as Node3D
	_tow_side = float(spot["side"])
	_tow_vel = _tow.call("drawn_velocity") as Vector3
	_tow_turn = 0.0
	_tow_accel = 0.0
	_tow_last_yaw = float(_tow.call("yaw"))
	_tow_set_yaw = float(player.get("body_yaw"))
	_tow_bumped = false
	_tow_strain = 0.0
	if not _tow.is_connected("crashed", _on_tow_crashed):
		_tow.connect("crashed", _on_tow_crashed)
	# Hanging on, you don't bump the truck you hold: its Solid moves with the drawn
	# truck a tick behind the physics (the transform flush), and at 9 m/s and up
	# that tick put its tail into the board and stopped it dead.
	_tow_solid = _tow.call("solid_body") as PhysicsBody3D
	if _tow_solid != null:
		player.add_collision_exception_with(_tow_solid)
	_mode = Mode.SKITCH
	player.set("skitch", true)
	player.set("skate_trick", TRICK_NONE)
	skitches += 1
	return true


## Let go of Chefty on purpose (E, an ollie) or not (slipped off the spot, Chefty
## gone): you roll on at the speed you had.
func let_go(why: String) -> void:
	if _tow == null and not bool(player.get("skitch")):
		return
	_release_tow(why)
	_mode = Mode.ROLL


func _release_tow(why: String) -> void:
	if _tow == null and not bool(player.get("skitch")):
		return
	if _tow != null and is_instance_valid(_tow) and _tow.is_connected("crashed", _on_tow_crashed):
		_tow.disconnect("crashed", _on_tow_crashed)
	# The truck's Solid stays out of your way a moment longer: it's drawn ahead of
	# where the physics has it, and let go at speed its tail is right there.
	if _tow_solid != null and is_instance_valid(_tow_solid):
		_clear_of = _tow_solid
		_clear_left = Constants.SKITCH_CLEAR_SECONDS
	_tow_solid = null
	_tow = null
	last_let_go = why
	player.set("skitch", false)
	if _mode == Mode.SKITCH:
		_mode = Mode.ROLL


func _on_tow_crashed(_strength: float, _at: Vector3) -> void:
	_tow_bumped = true


## Owner, every tick towed: the board rides the spot behind Chefty (a spring on
## top of Chefty's own speed), turning with it, your head free to look round like
## a seat's. Let go, or be let go of: see SKITCH_* in core/constants.gd.
func _step_skitch(delta: float, input: Dictionary) -> void:
	var truck := _tow
	if truck == null or not is_instance_valid(truck) or not truck.is_inside_tree():
		let_go("lost")
		_step_roll(delta, input)
		return
	# Space: let go with a pop.
	if bool(input.get("jump", false)):
		let_go("ollie")
		_step_roll(delta, input)
		return
	var vel := truck.call("drawn_velocity") as Vector3
	vel.y = 0.0
	var smooth := 1.0 - exp(-delta / Constants.SKITCH_READ_SMOOTH)
	var forward := -(truck.call("body_transform") as Transform3D).basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var before_vel := _tow_vel
	_tow_vel = _tow_vel.lerp(vel, smooth)
	_tow_accel = lerpf(_tow_accel, (_tow_vel - before_vel).dot(forward) / maxf(delta, 0.0001), smooth)
	var yaw_now := float(truck.call("yaw"))
	_tow_turn = lerpf(_tow_turn, angle_difference(_tow_last_yaw, yaw_now) / maxf(delta, 0.0001), smooth)
	_tow_last_yaw = yaw_now
	var speed := Vector2(_tow_vel.x, _tow_vel.z).length()
	# Being let go of.
	if _tow_bumped:
		wipeout("skitch_crash")
		return
	# Too fast: your grip goes after a moment of it (the needle past the line a
	# beat is a thrill; staying there tears the bumper out of your hand).
	_tow_strain = maxf(0.0, _tow_strain + (delta if speed > Constants.SKITCH_MAX_SPEED else -delta))
	if _tow_strain > Constants.SKITCH_STRAIN_SECONDS:
		wipeout("skitch_fast")
		return
	if absf(_tow_turn) > Constants.SKITCH_TURN_RATE and speed > Constants.SKITCH_TURN_MIN_SPEED:
		var outward := forward.cross(Vector3.UP) * signf(_tow_turn)
		wipeout("skitch_turn", outward * speed * Constants.SKITCH_FLING_SHARE)
		return
	if _tow_accel < -Constants.SKITCH_BRAKE_DECEL and speed > Constants.SKITCH_BRAKE_MIN_SPEED:
		wipeout("skitch_brake", -forward * Constants.SKITCH_SLAM_BACK)
		return
	var spot := hold_spot(truck, _tow_side)
	var at := player.global_position
	var gap := Vector3(spot.x - at.x, 0.0, spot.z - at.z)
	skitch_gap_max = maxf(skitch_gap_max, gap.length())
	if gap.length() > Constants.SKITCH_BREAK_METERS:
		let_go("slipped")
		_step_roll(delta, input)
		return
	var want := vel + (gap * Constants.SKITCH_SPRING).limit_length(Constants.SKITCH_PULL_MAX)
	var surface := surface_under()
	if (surface == &"grass" or surface == &"water") and Vector2(want.x, want.z).length() > Constants.SKATE_LAWN_BAIL_SPEED:
		wipeout("lawn")
		return
	var vy := player.velocity.y if player.is_on_floor() else player.velocity.y - _gravity() * delta
	player.velocity = Vector3(want.x, vy, want.z)
	var before := player.velocity
	player.move_and_slide()
	if _walls(before):
		return
	if _bumped_someone(before):
		return
	if Vector2(want.x, want.z).length() > Constants.SKATE_PILE_SPEED and bool(player.call("_on_pile")):
		_dive_in_pile()
		return
	_steer_towed(delta, truck)
	skitch_seconds += delta


## The board turns with Chefty; whatever the mouse turned this tick goes to your
## head instead (seat_look and the Head's yaw, as in a seat), so you can look
## round at the crew without the board turning off the spot.
func _steer_towed(delta: float, truck: Node3D) -> void:
	var looked := angle_difference(_tow_set_yaw, float(player.get("body_yaw")))
	var limit := Constants.CHEFTY_SEAT_LOOK_YAW
	var look := clampf(float(player.get("seat_look")) + looked, -limit, limit)
	var board := lerp_angle(_tow_set_yaw, float(truck.call("yaw")), 1.0 - exp(-delta * Constants.SKITCH_YAW_RATE))
	player.set("body_yaw", board)
	_tow_set_yaw = board
	player.set("seat_look", look)
	var head := player.get_node_or_null("Visual/Head") as Node3D
	if head != null:
		head.rotation.y = look


## Let go: the head comes back round to the board over a moment (it may have been
## looking back at the crew), never in one frame. A seat has its own (seated.gd).
func _ease_look_back(delta: float) -> void:
	if bool(player.get("skitch")) or bool(player.call("in_vehicle")):
		return
	var look := float(player.get("seat_look"))
	if look == 0.0:
		return
	var step := move_toward(look, 0.0, delta * Constants.SKITCH_LOOK_BACK_RATE)
	player.set("seat_look", step)
	var head := player.get_node_or_null("Visual/Head") as Node3D
	if head != null:
		head.rotation.y = step


# ---------------------------------------------------------------- owner: wipeouts

## Hitting something hard: true when it put you down.
func _walls(before: Vector3) -> bool:
	for index: int in player.get_slide_collision_count():
		var hit := player.get_slide_collision(index)
		var normal := hit.get_normal()
		if normal.y > 0.6:
			continue
		var into := -Vector2(before.x, before.z).dot(Vector2(normal.x, normal.z).normalized())
		if into <= Constants.SKATE_WALL_BAIL_SPEED:
			continue
		# The legacy pads' invisible edges stop you; they don't throw you.
		var thing := hit.get_collider() as CollisionObject3D
		if thing != null and thing.collision_layer == Constants.PAD_WALL_LAYER:
			continue
		# Someone, not something: a NICE BOY or a hired hand is solid (layer 1)
		# and stops the board like a wall, but that's a bump (_bumped_someone).
		if _is_person(thing):
			continue
		last_wall = "%s @ %s" % [thing.get_path() if thing != null else NodePath("?"), hit.get_position()]
		# Bounced back off it: the flop goes away from the wall, not into it.
		wipeout("wall", Vector3(normal.x, 0.0, normal.z).normalized() * into * Constants.SKATE_WALL_REBOUND)
		return true
	return false


## Rolling into someone: they get a light bonk (the host decides, net/components/
## brawl.gd), and you go down. True when it happened.
func _bumped_someone(before: Vector3) -> bool:
	var flat := Vector2(before.x, before.z)
	var speed := flat.length()
	if speed < Constants.SKATE_BONK_SPEED:
		return false
	var dir := flat / speed
	# Ran square into someone solid (a NICE BOY, a hired hand): the slide stopped on them.
	for index: int in player.get_slide_collision_count():
		var hit := player.get_slide_collision(index)
		var thing := hit.get_collider() as Node3D
		var normal := Vector2(hit.get_normal().x, hit.get_normal().z)
		if _is_person(thing) and normal.length() > 0.01 and -normal.normalized().dot(dir) >= Constants.SKATE_BONK_FACING:
			_bump(thing, dir, speed)
			return true
	# Someone you pass through (a crewmate, a passer-by): close and ahead of you.
	var people: Array[Node] = get_tree().get_nodes_in_group("players")
	people.append_array(get_tree().get_nodes_in_group("bonkable"))
	for node: Node in people:
		var person := node as Node3D
		if person == null or person == player or not person.is_inside_tree():
			continue
		if person.is_in_group("players") and (bool(person.call("is_hidden")) or bool(person.call("in_vehicle")) or bool(person.get("on_board"))):
			continue
		var offset := person.global_position - player.global_position
		if absf(offset.y) > 1.2:
			continue
		var gap := Vector2(offset.x, offset.z)
		if gap.length() > Constants.SKATE_BONK_RADIUS or (gap.length() > 0.2 and gap.normalized().dot(dir) < Constants.SKATE_BONK_FACING):
			continue
		_bump(person, dir, speed)
		return true
	return false


## A crewmate, a passer-by, a NICE BOY or a hired hand: someone a board bumps
## into rather than crashes into.
func _is_person(thing: Node) -> bool:
	return thing != null and (thing.is_in_group("players") or thing.is_in_group("bonkable") or thing.is_in_group("crew_hands"))


## You go down, and whoever you hit gets the host's light bonk (and the heat that
## goes with it) if they're someone a bonk lands on: not a hired hand.
func _bump(person: Node3D, dir: Vector2, speed: float) -> void:
	if person.is_in_group("players") or person.is_in_group("bonkable"):
		var brawl := get_tree().get_first_node_in_group("brawl")
		if brawl != null and brawl.has_method("request_skate_bonk"):
			brawl.call("request_skate_bonk", person.get_path(), Vector3(dir.x, 0.0, dir.y) * speed)
	wipeout("bump")


func _dive_in_pile() -> void:
	dismount(false)
	player.velocity = Vector3.ZERO
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field != null:
		field.call("request_pile_hide")
	_count_wipeout("pile")


## Down you go: off the board, thrown along the way you were going, flat on
## your back for SKATE_WIPEOUT_SECONDS. Every peer sees the board fly off
## (skate_view.gd, from the replicated wipeout flag). reason: landing, wall,
## lawn, bonk, bump.
func wipeout(reason: String, push := Vector3.ZERO) -> void:
	if not bool(player.get("on_board")) or not player.is_multiplayer_authority():
		return
	var flat := Vector2(player.velocity.x, player.velocity.z)
	_release_tow(reason)
	_settle_line(true)
	_count_wipeout(reason)
	player.set("on_board", false)
	player.set("skate_trick", TRICK_NONE)
	player.set("wipeout", true)
	_mode = Mode.ROLL
	_reset_air()
	player.set("_stun_left", Constants.SKATE_WIPEOUT_SECONDS)
	player.set("_knocked", true)
	var thrown := Vector3(flat.x, 0.0, flat.y) * Constants.SKATE_WIPEOUT_THROW_SHARE + push
	player.velocity = Vector3(thrown.x, Constants.SKATE_WIPEOUT_THROW_UP, thrown.z)
	player.set("anim_state", ANIM_KNOCKED)
	if player.call("_held_prop") != null:
		player.call("_release_held", false)
	player.call("say_to_all", "vo_oof")
	var quips: Array[String] = _Strings.WIPEOUT_QUIPS
	_popup(quips[randi() % quips.size()], false)


func _count_wipeout(reason: String) -> void:
	wipeouts[reason] = int(wipeouts.get(reason, 0)) + 1


# ---------------------------------------------------------------- owner: helpers

func _read_input() -> Dictionary:
	if not dev_input.is_empty():
		var out := dev_input.duplicate()
		# One-shots fire once.
		for once: String in ["jump", "kickflip", "heelflip"]:
			dev_input.erase(once)
		return out
	var playing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not playing:
		# A window has the mouse (the phone, a shop, settings): your foot drags the
		# board to a stop instead of it rolling on without you.
		return {"brake": true}
	return {
		"push": Input.is_action_pressed("move_forward"),
		"brake": Input.is_action_pressed("move_back"),
		"steer": Input.get_axis("move_left", "move_right"),
		"tuck": Settings.is_held(&"crouch"),
		"jump": Input.is_action_just_pressed("jump"),
		"kickflip": Input.is_action_just_pressed("primary"),
		"heelflip": Input.is_action_just_pressed("secondary"),
	}


## The way the board points, on the ground (x, z).
func _forward() -> Vector2:
	var yaw := float(player.get("body_yaw"))
	return Vector2(-sin(yaw), -cos(yaw))


func _gravity() -> float:
	return float(player.get("_gravity"))


## What the wheels are on: asphalt, concrete, grass or water. The connected town
## knows its ground (TownMap.surface_at); the legacy yard is lawn where the job's
## mowing grid says so, and the store's lot is asphalt. Anything raised (the
## ramp, a porch) is hard.
func surface_under() -> StringName:
	var at := player.global_position
	if at.y > 0.3:
		return &"concrete"
	var world := get_tree().get_first_node_in_group("world")
	if world != null and bool(world.call("is_town_map")):
		return TownMap.surface_at(at)
	if Net.player_zone(player.name.to_int()) == Net.Zone.LOT:
		var tasks := get_tree().get_first_node_in_group("job_tasks")
		if tasks != null and bool(tasks.call("is_lawn", at)):
			return &"grass"
		return &"concrete"
	return &"asphalt"


func _popup(text: String, good: bool) -> void:
	var popup := get_tree().get_first_node_in_group("trick_popup")
	if popup != null:
		popup.call("show_line", text, good)

