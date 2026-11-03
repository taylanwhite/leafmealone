class_name RakeStroke
extends RefCounted

## Authority: local, cosmetic timeline. One rake swing (docs/GAME.md, "Raking: the
## push-sweep"): lift out, plant, drive forward along the ground, flick, swing back
## in the air. Two field strokes bite in each swing (Constants.RAKE_SWING_BITES).
## Pure static: sample() turns a phase into a pose, and a per-actor registry keeps
## each raker's swing on this peer (players by peer id, hired hands by
## Constants.RAKE_ACTOR_HAND_BASE + N).
##
## Two drivers advance an actor:
## - local_step (the raker's own peer, equipment/rake.gd; and the host for a hired
##   hand, crew_step): a press starts a swing, bite A is committed by the press,
##   bite B needs the button still held at mid-drive, a new swing starts only when
##   the last one ends, letting go finishes the swing, cancel drops a swing that
##   hasn't bitten yet.
## - on_event + remote_step (everyone else): the stroke event IS the bite, so the
##   swing is re-phased at receipt so that now is the bite's phase.
## Phases run 0..1 inside a swing; after a swing nobody continues, a tail (1.0 to
## 1.0 + plant) finishes the swing's way back to the ground and the pose settles to
## idle, so nothing ever snaps.

enum Mode { IDLE, SWING, TAIL, SETTLE }

## Sample keys that blend as numbers (down is a bool, blended as 0/1).
const KEYS: Array[String] = ["head_forward", "head_lateral", "head_yaw", "head_lift", "toe_down", "tine_flex", "lean", "twist", "hip", "crouch", "cam_pitch", "cam_roll", "fov_kick"]

## Share of the full lean the body keeps between drives, ready for the next, and
## while just holding the rake (a slight stoop over the tines).
const READY_LEAN: float = Constants.RAKE_READY_LEAN
const IDLE_LEAN: float = Constants.RAKE_IDLE_LEAN

static var _actors: Dictionary = {}


## How long one swing takes for this player (s): the stroke times the strokes a
## swing, times their snack's stroke buff (Shops.buff(peer, "stroke"): Turbo
## Juice swings 20% quicker). The one tempo hook: the raking retune (R1b, ~1.3x
## slower a job on purpose) stays, a buff only scales it. 0 (and hired hands'
## actor ids, which are no peer) take no buff.
static func cycle_seconds(peer: int) -> float:
	var base := Constants.RAKE_STROKE_SECONDS * float(Constants.RAKE_SWING_STROKES)
	if peer <= 0:
		return base
	var tree := Engine.get_main_loop() as SceneTree
	var shops := tree.get_first_node_in_group("shops") if tree != null else null
	if shops == null:
		return base
	return base * float(shops.call("buff", peer, "stroke"))


## The phase each field stroke bites at, for this kind of swing.
static func bites(crew: bool = false) -> Array[float]:
	return Constants.RAKE_CREW_BITES if crew else Constants.RAKE_SWING_BITES


static func _plant() -> float:
	return float(Constants.RAKE_SWING_PHASES["plant"])


static func _drive_end() -> float:
	return float(Constants.RAKE_SWING_PHASES["drive_end"])


static func _flick_end() -> float:
	return float(Constants.RAKE_SWING_PHASES["flick_end"])


## Standing still with the rake: tines resting on the ground where a swing plants.
static func idle() -> Dictionary:
	return {
		"head_forward": Constants.RAKE_HEAD_NEAR, "head_lateral": Constants.RAKE_HEAD_BASE_X, "head_yaw": 0.0,
		"head_lift": 0.0, "toe_down": Constants.RAKE_HEAD_TOE_DOWN, "tine_flex": 0.0, "lean": Constants.RAKE_LEAN_DRIVE * IDLE_LEAN, "twist": 0.0,
		"hip": 0.0, "crouch": Constants.RAKE_CROUCH_IDLE, "cam_pitch": 0.0, "cam_roll": 0.0, "fov_kick": 0.0, "down": true,
	}


## The pose at a phase of a swing. load (0-1.5) bends the tines and the back,
## never the timing; side (+1/-1) is which way this swing drifts. fresh: the swing
## starts from standing still (it lifts out and plants), else it continues the
## last swing's way back through the air. phase < 0 is idle. Continuous in phase:
## the head never moves more than a few cm per tick at 60 Hz.
## cycle: this swing's length (s; the actor's st["cycle"], which a snack's
## stroke buff shortens), so the camera's nod lands with the real plant;
## <= 0 takes the unbuffed tempo.
static func sample(phase: float, load: float = 0.0, side: float = 1.0, fresh: bool = false, cycle: float = -1.0) -> Dictionary:
	if phase < 0.0:
		return idle()
	var plant := _plant()
	var drive_end := _drive_end()
	var out := idle()
	var lean_share := 0.0
	var lunge_share := 0.0
	var heavy := clampf(load, 0.0, 1.5)
	if phase < plant:
		var t := phase / plant
		if fresh:
			# Lift out ~10 cm, a little forward, sit back into the knees, and plant.
			out["head_forward"] = Constants.RAKE_HEAD_NEAR + Constants.RAKE_HEAD_FOLLOW * sin(PI * t)
			out["head_lift"] = Constants.RAKE_HEAD_LIFT * sin(PI * t)
			lean_share = lerpf(IDLE_LEAN, READY_LEAN, smoothstep(0.0, 1.0, t))
			out["crouch"] = lerpf(Constants.RAKE_CROUCH_IDLE, Constants.RAKE_CROUCH_PLANT, smoothstep(0.0, 1.0, t))
		else:
			out = _air(phase + 1.0, side, load)
			lean_share = float(out["lean_share"])
			lunge_share = float(out["lunge_share"])
		out["head_lateral"] = Constants.RAKE_HEAD_BASE_X + side * Constants.RAKE_HEAD_DRIFT * Constants.RAKE_PLANT_DRIFT_SHARE * smoothstep(0.0, 1.0, t)
		out["twist"] = _twist(side) * Constants.RAKE_PLANT_DRIFT_SHARE * smoothstep(0.0, 1.0, t)
		out["head_yaw"] = 0.0
		out["down"] = false
	elif phase <= drive_end:
		var t := (phase - plant) / (drive_end - plant)
		# The drag: a load bogs the start of the drive down, then it gives and the
		# head surges on (the timing of the bites never changes, only the path).
		var e := smoothstep(0.0, 1.0, pow(t, 1.0 + Constants.RAKE_RESIST * minf(heavy, 1.0)))
		out["head_forward"] = lerpf(Constants.RAKE_HEAD_NEAR, Constants.RAKE_HEAD_FAR, e)
		out["head_lift"] = 0.0
		# Heavy leaves make the tines judder sideways as they scrape.
		var judder := Constants.RAKE_JUDDER * minf(heavy, 1.0) * sin(TAU * Constants.RAKE_JUDDER_HZ * t) * sin(PI * t)
		out["head_lateral"] = Constants.RAKE_HEAD_BASE_X + side * Constants.RAKE_HEAD_DRIFT * lerpf(Constants.RAKE_PLANT_DRIFT_SHARE, 1.0, e) + judder
		out["head_yaw"] = side * Constants.RAKE_HEAD_YAW_MAX * Constants.RAKE_YAW_SHARE * e
		out["twist"] = _twist(side) * lerpf(Constants.RAKE_PLANT_DRIFT_SHARE, 1.0, e)
		# The tines bend back under the leaves, most mid-drive, and a little bounce at the plant.
		out["tine_flex"] = Constants.RAKE_TINE_FLEX * heavy * sin(PI * t) + Constants.RAKE_PLANT_BOUNCE * sin(PI * clampf(t / Constants.RAKE_PLANT_BOUNCE_SPAN, 0.0, 1.0))
		# The body leads the head: the shove starts in the legs and the back.
		var body := smoothstep(0.0, 1.0, clampf(t * Constants.RAKE_BODY_LEAD, 0.0, 1.0))
		lean_share = lerpf(READY_LEAN, 1.0, body)
		lunge_share = body
		out["crouch"] = lerpf(Constants.RAKE_CROUCH_PLANT, Constants.RAKE_CROUCH_DRIVE + Constants.RAKE_LOAD_CROUCH * minf(heavy, 1.0), body)
		out["down"] = true
		out["fov_kick"] = Constants.RAKE_CAM_FOV_KICK * sin(PI * t)
		out["cam_roll"] = Constants.RAKE_CAM_ROLL_DEG * side * sin(PI * t)
	else:
		out = _air(phase, side, load)
		lean_share = float(out["lean_share"])
		lunge_share = float(out["lunge_share"])
		out["down"] = false
	out.erase("lean_share")
	out.erase("lunge_share")
	out["lean"] = (Constants.RAKE_LEAN_DRIVE - Constants.RAKE_LOAD_LEAN * heavy) * lean_share
	# Hips back while the tines come down (the wind-up), then the lunge into the drive.
	var settle := fposmod(phase, 1.0) if phase < 1.0 + plant else phase - 1.0
	var wind_up := sin(PI * clampf(settle / plant, 0.0, 1.0)) if settle < plant else 0.0
	out["hip"] = Constants.RAKE_HIP_SHIFT * wind_up - Constants.RAKE_LUNGE_DRIVE * lunge_share
	# The nod: down fast at the plant, back slowly.
	var since := (phase - plant) * (cycle if cycle > 0.0 else cycle_seconds(0))
	if since >= 0.0:
		var dip := smoothstep(0.0, Constants.RAKE_CAM_DIP_IN, since) * (1.0 - smoothstep(Constants.RAKE_CAM_DIP_IN, Constants.RAKE_CAM_DIP_OUT, since))
		out["cam_pitch"] = -Constants.RAKE_CAM_DIP_DEG * dip
	return out


## The flick and the swing back through the air, u from drive_end to 1 + plant
## (past 1.0 it is the next swing's reach). Ends planted at RAKE_HEAD_NEAR.
static func _air(u: float, side: float, load: float) -> Dictionary:
	var plant := _plant()
	var drive_end := _drive_end()
	var flick_end := _flick_end()
	var out := idle()
	var span := 1.0 + plant - drive_end
	var g := clampf((u - drive_end - 0.02) / (span - 0.02), 0.0, 1.0)
	var flick := sin(PI * clampf((u - drive_end) / ((flick_end - drive_end) * Constants.RAKE_FLICK_STRETCH), 0.0, 1.0))
	out["head_forward"] = lerpf(Constants.RAKE_HEAD_FAR, Constants.RAKE_HEAD_NEAR, smoothstep(0.0, 1.0, g)) + Constants.RAKE_HEAD_FOLLOW * flick
	out["head_lift"] = Constants.RAKE_RESET_LIFT * sin(PI * g) + Constants.RAKE_HEAD_FLICK * flick
	var back := 1.0 - smoothstep(0.0, 1.0, clampf((u - drive_end) / (1.0 - drive_end), 0.0, 1.0))
	out["head_lateral"] = Constants.RAKE_HEAD_BASE_X + side * Constants.RAKE_HEAD_DRIFT * back
	out["head_yaw"] = side * Constants.RAKE_HEAD_YAW_MAX * Constants.RAKE_YAW_SHARE * back
	out["twist"] = _twist(side) * back
	# The wrist flicks the tines up and a few leaves off them.
	out["toe_down"] = Constants.RAKE_HEAD_TOE_DOWN - Constants.RAKE_TINE_FLICK * flick
	out["tine_flex"] = Constants.RAKE_FLICK_FLEX * clampf(load, 0.0, 1.5) * flick
	# The back comes up out of the shove a little past ready and settles back.
	out["lean_share"] = lerpf(1.0, READY_LEAN, smoothstep(0.0, 1.0, g)) - Constants.RAKE_SETTLE_OVERSHOOT * sin(PI * g) * g
	out["lunge_share"] = 1.0 - smoothstep(0.0, 1.0, clampf(g * 1.25, 0.0, 1.0))
	var heavy := minf(clampf(load, 0.0, 1.5), 1.0)
	out["crouch"] = lerpf(Constants.RAKE_CROUCH_DRIVE + Constants.RAKE_LOAD_CROUCH * heavy, Constants.RAKE_CROUCH_PLANT, smoothstep(0.0, 1.0, clampf(g * Constants.RAKE_CROUCH_RISE, 0.0, 1.0)))
	return out


## The shoulders turn so the right one comes forward with the lower hand (the rake
## is held on the right), more on a swing that drifts right.
static func _twist(side: float) -> float:
	return Constants.RAKE_TWIST_Y * (0.65 + 0.35 * side)


## a and b mixed by w (0 = a).
static func blend(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := {}
	for key: String in KEYS:
		out[key] = lerpf(float(a.get(key, 0.0)), float(b.get(key, 0.0)), w)
	out["down"] = (lerpf(1.0 if bool(a.get("down", false)) else 0.0, 1.0 if bool(b.get("down", false)) else 0.0, w)) > 0.5
	return out


static func load_for(moved: int) -> float:
	return clampf(float(moved) / Constants.RAKE_LOAD_FULL, 0.0, 1.5)


# ---- the registry


static func _state(actor: int) -> Dictionary:
	if not _actors.has(actor):
		_actors[actor] = {
			"mode": Mode.IDLE, "phase": 0.0, "side": -1.0, "load": 0.0, "cycle": cycle_seconds(actor),
			"fresh": false, "bitten": 0, "crew": false, "from": {}, "blend_left": 0.0, "blend_len": 0.0,
			"settle_left": 0.0, "last_event_msec": -1, "events": 0,
		}
	return _actors[actor]


## Forget everyone (a test's fresh start).
static func reset() -> void:
	_actors.clear()


## Where this actor is in a swing: 0..1, or -1 when not swinging (the tail and
## the settle after a finished swing count as not swinging).
static func phase_of(actor: int) -> float:
	if not _actors.has(actor):
		return -1.0
	var st: Dictionary = _actors[actor]
	return float(st["phase"]) if int(st["mode"]) == Mode.SWING else -1.0


static func side_of(actor: int) -> float:
	return float(_state(actor)["side"]) if _actors.has(actor) else 1.0


static func load_of(actor: int) -> float:
	return float(_state(actor)["load"]) if _actors.has(actor) else 0.0


static func set_load(actor: int, moved: int) -> void:
	_state(actor)["load"] = load_for(moved)


## What this actor's rake looks like right now: the swing's sample with any
## re-phase blend and the settle to idle applied.
static func display(actor: int) -> Dictionary:
	if not _actors.has(actor):
		return idle()
	return _shown(_actors[actor] as Dictionary)


static func _raw(st: Dictionary) -> Dictionary:
	match int(st["mode"]):
		Mode.SWING:
			return sample(float(st["phase"]), float(st["load"]), float(st["side"]), bool(st["fresh"]), float(st["cycle"]))
		Mode.TAIL:
			# Finishing the way back down (phase 1 to 1 + plant), with no next swing.
			return sample(float(st["phase"]), float(st["load"]), float(st["side"]), false, float(st["cycle"]))
		Mode.SETTLE:
			var length := maxf(Constants.RAKE_REMOTE_IDLE_BLEND, 0.001)
			var w := smoothstep(0.0, 1.0, 1.0 - float(st["settle_left"]) / length)
			return blend(sample(1.0 + _plant(), float(st["load"]), float(st["side"]), false), idle(), w)
	return idle()


## Cross-fades from whatever is showing now to wherever the swing goes next.
static func _begin_blend(st: Dictionary, seconds: float) -> void:
	st["from"] = _shown(st)
	st["blend_len"] = seconds
	st["blend_left"] = seconds


static func _shown(st: Dictionary) -> Dictionary:
	var raw := _raw(st)
	var left := float(st["blend_left"])
	if left > 0.0 and float(st["blend_len"]) > 0.0:
		return blend(st["from"] as Dictionary, raw, smoothstep(0.0, 1.0, 1.0 - left / float(st["blend_len"])))
	return raw


static func _start(st: Dictionary, cycle: float) -> void:
	var from_mode := int(st["mode"])
	st["cycle"] = cycle
	st["side"] = -float(st["side"])
	st["bitten"] = 0
	if from_mode == Mode.TAIL:
		# Pressed again on the way back: carry straight on into this swing's reach.
		st["phase"] = float(st["phase"]) - 1.0
		st["fresh"] = false
	else:
		if from_mode == Mode.SETTLE:
			_begin_blend(st, Constants.RAKE_PLANT_BLEND)
		st["phase"] = 0.0
		st["fresh"] = true
	st["mode"] = Mode.SWING


## Ends a swing: into the tail (and the settle) or straight to idle.
static func _finish(st: Dictionary) -> void:
	st["mode"] = Mode.TAIL
	st["phase"] = maxf(float(st["phase"]), 1.0)


## Advances the tail, settle and blends of any actor by delta.
static func _age(st: Dictionary, delta: float) -> void:
	st["blend_left"] = maxf(0.0, float(st["blend_left"]) - delta)
	match int(st["mode"]):
		Mode.TAIL:
			st["phase"] = float(st["phase"]) + delta / maxf(float(st["cycle"]), 0.05)
			if float(st["phase"]) >= 1.0 + _plant():
				st["mode"] = Mode.SETTLE
				st["settle_left"] = Constants.RAKE_REMOTE_IDLE_BLEND
		Mode.SETTLE:
			st["settle_left"] = float(st["settle_left"]) - delta
			if float(st["settle_left"]) <= 0.0:
				st["mode"] = Mode.IDLE
				st["phase"] = 0.0


## The raker's own driver, once per physics tick. held: the button is down (or
## was pressed since the last tick); cancel: a window opened or the rake was put
## away. Returns the bites (0 = A, 1 = B) that fire on this tick.
static func local_step(actor: int, delta: float, held: bool, cancel: bool, cycle: float = -1.0, crew: bool = false) -> Array[int]:
	var st := _state(actor)
	st["crew"] = crew
	var fired: Array[int] = []
	if cycle <= 0.0:
		cycle = cycle_seconds(actor)
	var mode := int(st["mode"])
	if cancel:
		if mode == Mode.SWING and int(st["bitten"]) & 1 == 0:
			_begin_blend(st, Constants.RAKE_REMOTE_IDLE_BLEND)
			st["mode"] = Mode.IDLE
			st["phase"] = 0.0
		elif mode == Mode.SWING:
			_finish(st)
		_age(st, delta)
		return fired
	if mode != Mode.SWING:
		if held:
			_start(st, cycle)
		else:
			_age(st, delta)
			return fired
	else:
		st["blend_left"] = maxf(0.0, float(st["blend_left"]) - delta)
		var step := delta / maxf(float(st["cycle"]), 0.05)
		st["phase"] = float(st["phase"]) + step
		if float(st["phase"]) >= 1.0 - 0.000001:
			if held:
				st["phase"] = float(st["phase"]) - 1.0
				st["side"] = -float(st["side"])
				st["bitten"] = 0
				st["fresh"] = false
				st["cycle"] = cycle
			else:
				_finish(st)
				return fired
	# A bite fires on the tick nearest its phase.
	var half := 0.5 * delta / maxf(float(st["cycle"]), 0.05)
	var list := bites(crew)
	for index: int in list.size():
		var bit := 1 << index
		if int(st["bitten"]) & bit != 0:
			continue
		if float(st["phase"]) + half >= list[index]:
			st["bitten"] = int(st["bitten"]) | bit
			# Bite B (and any after it) needs the button still held.
			if index == 0 or held:
				fired.append(index)
	return fired


## A hired hand's swing on the host (npcs/crew_hand.gd): working keeps it swinging
## at its own cycle. Returns true on the tick it bites.
static func crew_step(actor: int, delta: float, cycle: float, working: bool) -> bool:
	return not local_step(actor, delta, working, false, cycle, true).is_empty()


## Someone else's stroke (a field stroke_event, or a stand-in before raking:1):
## the bite is happening now on this peer.
static func on_event(actor: int, ev: Dictionary) -> void:
	var st := _state(actor)
	var crew := str(ev.get("kind", "rake")) == "crew_rake"
	st["crew"] = crew
	var now := Time.get_ticks_msec()
	var bite := int(ev.get("bite", 0))
	var tempo := float(ev.get("tempo", 0.0))
	if tempo <= 0.0:
		tempo = float(st["cycle"]) if crew else cycle_seconds(actor)
		# No tempo on the event: a hand's cycle is the gap between its strokes.
		if crew and int(st["last_event_msec"]) >= 0:
			var gap := float(now - int(st["last_event_msec"])) / 1000.0
			if gap > 0.3 and gap < 2.5:
				tempo = gap
	if ev.has("moved"):
		st["load"] = load_for(int(ev["moved"]))
	st["last_event_msec"] = now
	st["events"] = int(st["events"]) + 1
	var list := bites(crew)
	var at := list[clampi(bite, 0, list.size() - 1)]
	var mode := int(st["mode"])
	if bite == 0 or mode != Mode.SWING:
		# A new swing, anchored so now is the bite. A swing already on its way back
		# down lands here nearly where it is: blend whatever is left.
		_begin_blend(st, Constants.RAKE_PLANT_BLEND)
		st["side"] = -float(st["side"])
		st["mode"] = Mode.SWING
		st["phase"] = at
		st["fresh"] = false
		st["cycle"] = tempo
		st["bitten"] = (1 << (bite + 1)) - 1
		return
	# Bite B of the swing that's running: only nudge it if it drifted.
	if absf(float(st["phase"]) - at) > 0.05:
		_begin_blend(st, Constants.RAKE_PLANT_BLEND)
		st["phase"] = at
	st["bitten"] = int(st["bitten"]) | (1 << bite)
	st["cycle"] = tempo


## Someone else's swing, once per physics tick: it runs on at its tempo and, if no
## new bite comes, finishes on its way back down and settles.
static func remote_step(actor: int, delta: float) -> void:
	if not _actors.has(actor):
		return
	var st: Dictionary = _actors[actor]
	if int(st["mode"]) == Mode.SWING:
		st["blend_left"] = maxf(0.0, float(st["blend_left"]) - delta)
		st["phase"] = float(st["phase"]) + delta / maxf(float(st["cycle"]), 0.05)
		if float(st["phase"]) >= 1.0:
			_finish(st)
		return
	_age(st, delta)


## The remote and local drivers both: true while this actor is mid-swing or still
## settling back (the pose is changing).
static func is_moving(actor: int) -> bool:
	return _actors.has(actor) and int((_actors[actor] as Dictionary)["mode"]) != Mode.IDLE
