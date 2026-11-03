extends CharacterBody3D

## Authority: host for decisions and the body; every peer for how it looks.
## A NICE BOY, the fictional enforcement crew (docs/GAME.md; the look, OQ-012, in
## _dress_up). R2 chunk 2 (docs/GAME.md "The NICE BOYS encounter (R2)"): this file
## is the body. It steers with acceleration and a turn rate, senses with a view
## cone, a near sense and hearing, barks, and shows its replicated mode on every
## peer. The decisions are npcs/crew_brain.gd's (host); the catch itself, from the
## wind-up to the van door, is net/run_events/encounter.gd's.
##
## Replicated (MultiplayerSynchronizer, on change, reliable; in the spawn state for
## late joiners): mode, mode_at (server time it began), mode_peer (who it's about)
## and mode_arg (a point or direction). Every peer drives the poses, the footsteps
## and the name tag from them.
##
## Placed, not smoothed: while seated in the van, hopping in or out, winding up,
## lunging, in the gotcha or the cite, every peer places the body itself from the
## same data (the van's pose, the wind-up's RPC), so no lag float shows (craft
## rule: one pose, every screen).

enum Mode { PATROL, NOISE, SPOT, CHASE, INVESTIGATE, SEARCH, INSPECT, WINDUP, LUNGE, WHIFF, GOTCHA, CITE, ESCORT, DOOR, RECALL, SEATED, HOP_OUT, HOP_IN, STUNNED }

## The bark kinds (Strings.CREW_BARKS has a pool for each; cast_test checks).
const BARK_KINDS: Array[String] = ["arrive", "spot", "chase", "lunge", "whiff", "lost", "search", "inspect", "near_miss", "pile", "caught", "cite_wriggle", "bonked", "escort", "door", "buckle", "recall", "ride", "wave", "capacity", "investigate"]
## The modes the brain decides; the rest belong to the Encounter, the van or the director.
const BRAIN_MODES: Array[int] = [Mode.PATROL, Mode.NOISE, Mode.SPOT, Mode.CHASE, Mode.INVESTIGATE, Mode.SEARCH, Mode.INSPECT]
## Modes in which every peer places the body itself.
const PLACED_MODES: Array[int] = [Mode.WINDUP, Mode.LUNGE, Mode.GOTCHA, Mode.CITE, Mode.SEATED, Mode.HOP_OUT, Mode.HOP_IN]

const _CHEST := Vector3(0.0, 1.2, 0.0)
const _EYES := Vector3(0.0, 1.55, 0.0)
const _HideSpot = preload("res://net/components/hide_spot.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _CharacterLife = preload("res://player/character_life.gd")
const _LotNav = preload("res://npcs/lot_nav.gd")
const _NiceSeal = preload("res://props/nice_seal.gd")
const _Strings = preload("res://ui/strings.gd")
const _Brain = preload("res://npcs/crew_brain.gd")
const _Gestures = preload("res://npcs/crew_gestures.gd")
## The NICE BOYS' khaki shorts.
const KHAKI := Color(0.8, 0.7, 0.52)

## Totals for this process, read by net/dev/probe.gd and the encounter test.
static var stats: Dictionary = {"barks": 0, "max_turn_step": 0.0, "spots": 0, "hops": 0, "investigations": 0}
## The last barks every peer showed: [{crew, kind, index}], for the encounter test.
static var bark_log: Array[Dictionary] = []

@export var mode: int = Mode.PATROL
@export var mode_at: float = 0.0
@export var mode_peer: int = 0
@export var mode_arg: Vector3 = Vector3.ZERO

var _gravity: float = 9.8
## Seconds this NICE BOY is still reeling from something thrown at them (host).
var _stun_left: float = 0.0
## Host: the brain, the walking speed now, where an owner asked him to walk.
var brain: RefCounted
var _speed_now: float = 0.0
var _walk_goal := Vector3.INF
var _walk_speed: float = 0.0
## Host: last time this NICE BOY saw, heard or inspected anyone (the director's give-up).
var last_contact_at: float = 0.0
var _next_bark_at: float = 0.0
var _bonked_by: int = 0
## Every peer: a pose placed from data, not the network. {"kind": "lunge" | "stand"
## | "seat", ...}; see _place().
var _placed: Dictionary = {}
var _staged_anchor: Node3D
var _staged_offset := Transform3D.IDENTITY
var _staged_blend: float = 0.0
var _staged_from := Transform3D.IDENTITY
var _staged_since: float = 0.0
## Every peer: the mode last shown, the walk distance since the last footstep, the bark on show.
var _shown_mode: int = -1
var _step_distance: float = 0.0
var _last_visual := Vector3.INF
var _bark_left: float = 0.0
var _rng := RandomNumberGenerator.new()
## The last bark this peer showed, "kind:index" (net/dev/probe.gd crew_cast: CI
## compares the host's with a client's).
var last_bark: String = ""


func _ready() -> void:
	set_multiplayer_authority(1)
	add_to_group("crew")
	add_to_group("nice_crew")
	add_to_group("bonkable")
	_dress_up()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_next_bark_at = Net.server_time() + Constants.CREW_BARK_FIRST_DELAY
	if Net.is_host():
		_rng.randomize()
		brain = _Brain.new(_rng)
		last_contact_at = Net.server_time()
		_bake_navmesh()


## The NICE BOYS' look (OQ-012, decided; docs/GAME.md "2026-11-01, the cast"):
## Courtesy Lavender polos, khaki shorts, knee socks, sun visors, gold aviators, a
## clipboard, and a fixed grin under the angry brows. Crew1, the head NICE BOY,
## carries a megaphone and a whistle instead of a clipboard. The look and the name
## tag are pure functions of the node name and the day, so every peer agrees.
func _dress_up() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null or visual.has_node("CartoonBody"):
		return
	var body := _CartoonBody.new()
	body.name = "CartoonBody"
	dress(body, crew_index())
	visual.add_child(body)
	# The crew turns its +Z toward where it walks (see _steer), and bodies face -Z.
	body.rotation.y = PI
	body.build()
	var life := _CharacterLife.new()
	life.name = "Life"
	life.root = self
	life.body = body
	life.role = "crew"
	body.add_child(life)
	var poser := _Gestures.new()
	poser.name = "Poser"
	body.add_child(poser)
	var capsule := visual.get_node_or_null("Body") as Node3D
	if capsule != null:
		capsule.visible = false
	var tag := visual.get_node_or_null("Label") as Label3D
	if tag != null:
		tag.text = _Strings.crew_tag(crew_index(), _day())
		tag.fixed_size = true
		tag.pixel_size = minf(Constants.CREW_TAG_PIXEL_SIZE, Constants.CREW_TAG_MAX_PX)
	var said := visual.get_node_or_null("Bark") as Label3D
	if said != null:
		said.pixel_size = minf(Constants.CREW_BARK_PIXEL_SIZE, Constants.CREW_TAG_MAX_PX)
	var link := visual.get_node_or_null("EscortAnchor") as Node3D
	if link != null:
		link.position = Constants.ESCORT_SIDE_OFFSET


## Dresses an unbuilt CartoonBody as NICE BOY number index (1 is the head NICE
## BOY). Shared by the crew and tools/studio, so the studio shows the real look;
## call body.build() after.
static func dress(body: Node3D, index: int) -> void:
	body.set("shirt", _NiceSeal.LAVENDER)
	body.set("pants", KHAKI)
	body.set("skin", _CartoonBody.SKIN_TONES[absi(hash("Crew%d" % index)) % _CartoonBody.SKIN_TONES.size()])
	body.set("hair", _CartoonBody.HAIR[absi(hash("hair%d" % index)) % _CartoonBody.HAIR.size()])
	body.set("hat_style", "visor")
	body.set("hat_color", _NiceSeal.LAVENDER)
	body.set("shades", true)
	body.set("shades_style", "aviator")
	body.set("grin", true)
	body.set("outfit", "nice_boy_lead" if index == 1 else "nice_boy")


## Which NICE BOY this is, from the node name the director gives it (Crew1 is the lead).
func crew_index() -> int:
	return maxi(1, str(name).trim_prefix("Crew").to_int())


## Today's day number (the day clock replicates it), or 1 without one.
func _day() -> int:
	var clock := get_tree().get_first_node_in_group("day_clock") if is_inside_tree() else null
	return int(clock.get("day")) if clock != null else 1


## Which way he faces (flat, unit): his +Z.
func facing() -> Vector3:
	var forward := global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length() > 0.001 else Vector3.FORWARD


# ---------------------------------------------------------------- senses (host)

## Whether he can see this point now: inside the view cone and range with a clear
## line, or within the all-round near sense with a clear line.
func sees_point(point: Vector3) -> bool:
	var eyes := global_position + _EYES
	var offset := point - eyes
	var flat := Vector3(offset.x, 0.0, offset.z)
	var distance := flat.length()
	if distance > Constants.CREW_VIEW_RANGE:
		return false
	if distance > Constants.CREW_NEAR_SENSE:
		var angle := rad_to_deg(facing().angle_to(flat.normalized())) if distance > 0.01 else 0.0
		if angle > Constants.CREW_VIEW_DEG * 0.5:
			return false
	return _clear_line(eyes, point)


## Whether he can see that player's chest now (cone, near sense, line of sight).
func can_see_peer(peer_id: int) -> bool:
	var body := _player(peer_id)
	if body == null:
		return false
	return sees_point(body.global_position + _CHEST)


## Whether a running tool gives that player away: it ran within the last moment
## and within earshot (net/run_events/heat.gd's per-player noise).
func hears_tool(peer_id: int) -> bool:
	var heat := get_tree().get_first_node_in_group("heat")
	if heat == null or not heat.has_method("noise_point"):
		return false
	if float(heat.call("noise_age", peer_id)) > Constants.CREW_HEAR_FRESH_SECONDS:
		return false
	var at: Vector3 = heat.call("noise_point", peer_id)
	return at.is_finite() and Vector2(at.x - global_position.x, at.z - global_position.z).length() <= Constants.CREW_HEAR_METERS


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 3)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.collider as Node
	return collider != null and (collider.is_in_group("players") or collider.is_in_group("crew"))


# ---------------------------------------------------------------- modes (host)

## Host: switch mode, about peer_id, with a point or direction.
func host_set_mode(new_mode: int, peer_id: int = 0, arg: Vector3 = Vector3.ZERO) -> void:
	if not Net.is_host():
		return
	if new_mode == Mode.SPOT:
		stats["spots"] = int(stats["spots"]) + 1
	mode = new_mode
	mode_at = Net.server_time()
	mode_peer = peer_id
	mode_arg = arg
	_walk_goal = Vector3.INF
	if new_mode != Mode.LUNGE:
		_speed_now = minf(_speed_now, Constants.CREW_SPEED_CHASE)


## Host: walk here at this speed (an escort, a recall); INF stops.
func host_walk(goal: Vector3, speed: float) -> void:
	_walk_goal = goal
	_walk_speed = speed


func in_brain_mode() -> bool:
	return BRAIN_MODES.has(mode)


func is_stunned() -> bool:
	return _stun_left > 0.0


## Where the escorted player walks, arm in arm (every peer, under Visual so it
## moves with the drawn body).
func escort_anchor() -> Node3D:
	return get_node_or_null("Visual/EscortAnchor") as Node3D


# ---------------------------------------------------------------- staging

## Every peer, from the caller's reliable RPC (contract C3/C8): the body follows
## anchor * offset every tick, blending in over blend seconds from where it is.
## pose: &"sit_buckled" sits (the van's benches), &"stand" stands.
func set_staged(anchor: Node3D, offset: Transform3D, blend: float, pose: StringName = &"stand") -> void:
	_staged_from = _drawn_transform()
	_staged_anchor = anchor
	_staged_offset = offset
	_staged_blend = blend
	_staged_since = _now()
	_placed = {"kind": "staged", "pose": pose}
	_set_solid(false)


func clear_staged() -> void:
	if _placed.get("kind", "") != "staged":
		return
	_staged_anchor = null
	_placed = {}
	_set_solid(true)
	_settle_visual()


func is_staged() -> bool:
	return _placed.get("kind", "") == "staged"


## Every peer, from net/run_events/encounter.gd's wind-up RPC: from where, which
## way, and when the hand lands. He winds up there and lunges along dir.
func play_windup(from: Vector3, dir: Vector3, contact_at: float, from_spot: bool) -> void:
	_placed = {"kind": "lunge", "from": from, "dir": dir, "contact": contact_at, "spot": from_spot, "blend_from": _drawn_transform(), "since": _now()}
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null and not from_spot:
		sfx.call("play_on", "lunge_whoosh", self, -6.0)


## Every peer: stand here facing yaw (the gotcha and the cite), blending in.
func play_stand(at: Vector3, yaw: float, blend: float) -> void:
	_placed = {"kind": "stand", "at": at, "yaw": yaw, "blend": blend, "blend_from": _drawn_transform(), "since": _now()}


## Every peer: back to the network's pose (the host's body is where the placement left it).
func release_placement() -> void:
	if _placed.is_empty() or is_staged():
		return
	_placed = {}
	_settle_visual()


## For net/components/net_smoother.gd: while placed, it leaves the visual alone.
func is_riding_visual() -> bool:
	return not _placed.is_empty()


func _drawn_transform() -> Transform3D:
	var visual := get_node_or_null("Visual") as Node3D
	return visual.global_transform if visual != null else global_transform


## The smoother left the Visual somewhere behind the body: put it back on it.
func _settle_visual() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.transform = Transform3D.IDENTITY
		visual.reset_physics_interpolation()


func _set_solid(solid: bool) -> void:
	var shape := get_node_or_null("Collision") as CollisionShape3D
	if shape != null:
		shape.disabled = not solid


# ---------------------------------------------------------------- hits

## Something thrown hit this NICE BOY (net/components/net_prop.gd, every peer), or
## a punch (brawl.gd): a flinch, a stumble, or flat on their back with stars. The
## host stops them for the tier's stun time, which also spoils a wind-up, and a
## hit during the cite or the escort lets the caught player go (encounter.gd).
func on_bonked(push: Vector3, tier: String) -> void:
	var body := get_node_or_null("Visual/CartoonBody")
	match tier:
		"light":
			if body != null:
				body.call("gesture", "startle")
		"medium":
			if body != null:
				body.call("gesture", "stumble")
		_:
			if body != null:
				body.call("dizzy", float(Constants.BONK_STUN_SECONDS["heavy"]))
	if not Net.is_host():
		return
	_stun_left = maxf(_stun_left, float(Constants.BONK_STUN_SECONDS.get(tier, 0.35)))
	if _placed.is_empty():
		velocity = Vector3(push.x, 0.0, push.z) * 0.6
	bark("bonked")
	# Who did it arrives right after (host_bonked_by), in the same frame.
	call_deferred("_after_bonk")


## Host: the thrower or puncher behind the bonk just reported (net_prop.gd, brawl.gd).
func host_bonked_by(peer_id: int) -> void:
	_bonked_by = peer_id


func _after_bonk() -> void:
	var by := _bonked_by
	_bonked_by = 0
	var encounter := _encounter()
	if encounter != null:
		encounter.call("host_crew_bonked", self, by)


## Host, group "nice_crew": something thrown came to rest here. Close by and not
## busy: he goes and has a look.
func on_prop_landed(at: Vector3, _by_peer: int) -> void:
	if not Net.is_host() or not in_brain_mode() or mode == Mode.CHASE or mode == Mode.SPOT:
		return
	if Vector2(at.x - global_position.x, at.z - global_position.z).length() > Constants.CREW_INVESTIGATE_RADIUS:
		return
	stats["investigations"] = int(stats["investigations"]) + 1
	host_set_mode(Mode.INVESTIGATE, 0, at)
	bark("investigate")


# ---------------------------------------------------------------- barks

## Host: say a line of this kind, unless he spoke too recently (force skips the
## gap: the wind-up's "Ah-ah-ah!", the gotcha's line).
func bark(kind: String, force: bool = false, index: int = -1) -> void:
	if not Net.is_host() or not _Strings.CREW_BARKS.has(kind):
		return
	var now := Net.server_time()
	if not force and now < _next_bark_at:
		return
	_next_bark_at = now + Constants.CREW_BARK_MIN_GAP
	var pool: Array = _Strings.CREW_BARKS[kind]
	var pick := index if index >= 0 else _rng.randi_range(0, pool.size() - 1)
	_rpc_bark.rpc(kind, clampi(pick, 0, pool.size() - 1))


## Every peer: the line over his head, its subtitle (captions on, within earshot),
## his megaphone voice and the kind's gesture.
@rpc("authority", "call_local", "reliable")
func _rpc_bark(kind: String, index: int) -> void:
	show_bark(kind, index)


## Every peer: show a bark without the network (the gotcha's line is timed by the
## catch's own RPC, so it lands on the same frame everywhere).
func show_bark(kind: String, index: int) -> void:
	var pool: Array = _Strings.CREW_BARKS.get(kind, [])
	if pool.is_empty():
		return
	var text := str(pool[clampi(index, 0, pool.size() - 1)])
	last_bark = "%s:%d" % [kind, index]
	stats["barks"] = int(stats["barks"]) + 1
	bark_log.append({"crew": str(name), "kind": kind, "index": index})
	if bark_log.size() > 64:
		bark_log.pop_front()
	var label := get_node_or_null("Visual/Bark") as Label3D
	if label != null:
		label.text = text
		label.visible = true
		_bark_left = Constants.CREW_BARK_SECONDS
	var body := get_node_or_null("Visual/CartoonBody")
	if body != null:
		body.call("talk", minf(1.4, 0.35 + 0.045 * float(text.length())))
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_on", "bark", self)
	_subtitle(text)


## The caption stack's subtitle line (chunk 1, group "caption_stack"; it honors the
## Settings captions toggle and scale itself), for a local player within earshot.
func _subtitle(text: String) -> void:
	var stack := get_tree().get_first_node_in_group("caption_stack")
	if stack == null or not stack.has_method("push"):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_to(global_position) > Constants.CREW_BARK_HEAR_METERS:
		return
	stack.call("push", &"subtitle", text, Constants.CREW_BARK_SECONDS)


# ---------------------------------------------------------------- the host's tick

func _physics_process(delta: float) -> void:
	_auto_stage()
	if not _placed.is_empty():
		_place()
		if Net.is_host():
			velocity = Vector3.ZERO
			_speed_now = 0.0
			_step_hop_and_seat()
		return
	if not Net.is_host():
		return
	if _stun_left > 0.0:
		_stun_left -= delta
		_speed_now = 0.0
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
		move_and_slide()
		return
	var goal := global_position
	var speed := 0.0
	var face := Vector3.INF
	if _walk_goal.is_finite():
		goal = _walk_goal
		speed = _walk_speed
	elif in_brain_mode() and brain != null:
		var plan: Dictionary = brain.call("tick", self, delta)
		goal = plan.get("goal", global_position)
		speed = float(plan.get("speed", 0.0))
		face = plan.get("face", Vector3.INF)
	elif mode == Mode.WHIFF:
		if Net.server_time() - mode_at >= Constants.CREW_WHIFF_SECONDS:
			host_set_mode(Mode.CHASE, mode_peer)
	_steer(goal, speed, face, delta)


## Host: hop-outs and hop-ins end on their own clock; then he's on his feet (or seated).
func _step_hop_and_seat() -> void:
	var kind := str(_placed.get("kind", ""))
	if kind != "staged" or (mode != Mode.HOP_OUT and mode != Mode.HOP_IN):
		return
	if Net.server_time() - mode_at < Constants.CREW_HOP_SECONDS:
		return
	if mode == Mode.HOP_OUT:
		host_set_mode(Mode.NOISE)
		_auto_stage()
		if crew_index() == 1:
			# The head NICE BOY points his megaphone at whoever's loudest and says hello.
			bark("arrive", true)
	else:
		host_set_mode(Mode.SEATED)


## Every peer: seated, hopping out or in, with no Shuttle to seat him (it calls
## set_staged itself), he rides the fallback van's seat for his index; out of
## those modes, he's on his own feet where the hop ended (the mode replicates,
## so a client lets go when the host does).
func _auto_stage() -> void:
	var seated := mode == Mode.SEATED or mode == Mode.HOP_OUT or mode == Mode.HOP_IN
	if seated and _placed.is_empty():
		set_staged(null, fallback_seat(crew_index()), 0.0, &"sit_buckled")
	elif not seated and is_staged() and _staged_anchor == null:
		var at := _drawn_transform()
		clear_staged()
		if Net.is_host():
			global_transform = Transform3D(Basis(Vector3.UP, at.basis.get_euler().y), at.origin)
			reset_physics_interpolation()


## Accelerate toward the goal along the navmesh, turning at most CREW_TURN_RATE.
func _steer(goal: Vector3, speed: float, face: Vector3, delta: float) -> void:
	var next := goal
	var agent := get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent != null and speed > 0.0:
		agent.target_position = goal
		var path := agent.get_current_navigation_path()
		if not path.is_empty():
			var end := path[path.size() - 1]
			# Off the mesh (the van at the curb, the street): straight there from its edge.
			if Vector2(end.x - goal.x, end.z - goal.z).length() < 1.5 or Vector2(end.x - global_position.x, end.z - global_position.z).length() > 1.0:
				next = agent.get_next_path_position()
	var flat := Vector3(next.x - global_position.x, 0.0, next.z - global_position.z)
	var want := Vector3.ZERO
	if speed > 0.0 and flat.length() > 0.45:
		want = flat.normalized()
	var look := want if want != Vector3.ZERO else (Vector3(face.x - global_position.x, 0.0, face.z - global_position.z) if face.is_finite() else Vector3.ZERO)
	if look.length() > 0.05:
		_turn_toward(look.normalized(), delta)
	var align := clampf(facing().dot(want), 0.0, 1.0) if want != Vector3.ZERO else 0.0
	var target_speed := speed * (0.25 + 0.75 * align) if want != Vector3.ZERO else 0.0
	# Slow down to arrive rather than overshoot.
	target_speed = minf(target_speed, flat.length() * 2.5)
	_speed_now = move_toward(_speed_now, target_speed, (Constants.CREW_ACCEL if target_speed > _speed_now else Constants.CREW_DECEL) * delta)
	var move := facing() * _speed_now
	velocity.x = move.x
	velocity.z = move.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()


func _turn_toward(dir: Vector3, delta: float) -> void:
	var want := atan2(dir.x, dir.z)
	var step := wrapf(want - rotation.y, -PI, PI)
	var most := Constants.CREW_TURN_RATE * delta
	var turned := clampf(step, -most, most)
	rotation.y = wrapf(rotation.y + turned, -PI, PI)
	stats["max_turn_step"] = maxf(float(stats["max_turn_step"]), absf(turned))


# ---------------------------------------------------------------- placement (every peer)

func _now() -> float:
	return Net.server_time()


## Puts the body where the placement says, on every peer, this tick.
func _place() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	var kind := str(_placed.get("kind", ""))
	var now := _now()
	var want := global_transform
	match kind:
		"staged":
			var anchor := _staged_anchor if is_instance_valid(_staged_anchor) else van_anchor()
			if visual != null:
				visual.visible = anchor != null
			if anchor == null:
				return
			want = anchor.global_transform * _staged_offset
			if _staged_blend > 0.0 and now - _staged_since < _staged_blend:
				var share := clampf((now - _staged_since) / _staged_blend, 0.0, 1.0)
				want = _staged_from.interpolate_with(want, ease(share, -2.0))
			want = _staged_motion(want, now)
		"lunge":
			var from: Vector3 = _placed["from"]
			var dir: Vector3 = _placed["dir"]
			var contact := float(_placed["contact"])
			var yaw := atan2(dir.x, dir.z)
			var along := 0.0
			if not bool(_placed.get("spot", false)):
				along = clampf((now - (contact - Constants.CREW_LUNGE_SECONDS)) / Constants.CREW_LUNGE_SECONDS, 0.0, 1.0)
			var at := from + dir * Constants.CREW_LUNGE_DISTANCE * ease(along, 0.6)
			want = Transform3D(Basis(Vector3.UP, yaw), at)
			want = _blend_in(want, 0.18, now)
		"stand":
			want = Transform3D(Basis(Vector3.UP, float(_placed["yaw"])), _placed["at"])
			want = _blend_in(want, float(_placed.get("blend", 0.12)), now)
	# The host moves the real body; a client draws it (the body stays the network's,
	# so the synchronizer and the placement never fight).
	if Net.is_host():
		global_transform = want
		if visual != null:
			visual.transform = Transform3D.IDENTITY
	elif visual != null:
		visual.global_transform = want


## A placement eases in from wherever the body was drawn, so nothing pops.
func _blend_in(want: Transform3D, seconds: float, now: float) -> Transform3D:
	var since := float(_placed.get("since", now))
	if seconds <= 0.0 or now - since >= seconds:
		return want
	var from: Transform3D = _placed.get("blend_from", want)
	return from.interpolate_with(want, ease(clampf((now - since) / seconds, 0.0, 1.0), -2.0))


## Seated, hopping out, hopping in: the path between the seat and the curb, a pure
## function of mode_at and the van's pose.
func _staged_motion(seat: Transform3D, now: float) -> Transform3D:
	if mode != Mode.HOP_OUT and mode != Mode.HOP_IN:
		return seat
	var anchor := _staged_anchor if is_instance_valid(_staged_anchor) else van_anchor()
	if anchor == null:
		return seat
	var share := clampf((now - mode_at) / Constants.CREW_HOP_SECONDS, 0.0, 1.0)
	if mode == Mode.HOP_IN:
		share = 1.0 - share
	var local_seat := anchor.global_transform.affine_inverse() * seat
	var sill := Vector3(Constants.CREW_VAN_SILL_X, 1.0, local_seat.origin.z)
	var curb := Vector3(Constants.CREW_VAN_CURB_X, 0.0, clampf(local_seat.origin.z, -0.6, 1.6))
	var point := Vector3.ZERO
	if share < 0.4:
		point = local_seat.origin.lerp(sill, ease(share / 0.4, -1.6))
	else:
		var hop := (share - 0.4) / 0.6
		point = sill.lerp(curb, hop) + Vector3.UP * sin(hop * PI) * 0.35
	# Facing the open side as he goes (+X in the van's space), from the seat's facing.
	var out_basis := Basis(Vector3.UP, PI * 0.5)
	var basis := local_seat.basis.slerp(out_basis, clampf(share * 2.5, 0.0, 1.0))
	return anchor.global_transform * Transform3D(basis, point)


## The van the crew rides when no Shuttle seats them (the fallback): the cast:5 van
## pulling up (net/run_events/van_arrival.gd), or the legacy ride's van once it
## leaves with riders (net/components/ride.gd, Rides/Van). Both are a VanLook.
func van_anchor() -> Node3D:
	var arrival := get_tree().get_first_node_in_group("van_arrival")
	if arrival != null and arrival.has_method("van_look"):
		var look := arrival.call("van_look") as Node3D
		if look != null:
			return look
	var world := get_tree().get_first_node_in_group("world")
	var ride := world.get_node_or_null("Rides/Van/Body/VanLook") as Node3D if world != null else null
	return ride


## A seat in the fallback van: Constants.CREW_VAN_SEATS, the driver first.
static func fallback_seat(index: int) -> Transform3D:
	var seat: Array = Constants.CREW_VAN_SEATS[clampi(index - 1, 0, Constants.CREW_VAN_SEATS.size() - 1)]
	# Seat yaw is which way he faces in the van's space; bodies face their -Z (the
	# crew node turns its +Z), so a 0 seat looks out the windshield.
	return Transform3D(Basis(Vector3.UP, float(seat[1]) + PI), seat[0])


# ---------------------------------------------------------------- how it looks (every peer)

func _process(delta: float) -> void:
	var body := get_node_or_null("Visual/CartoonBody")
	var poser := get_node_or_null("Visual/CartoonBody/Poser")
	if mode != _shown_mode:
		_show_mode(body, poser)
	if poser != null:
		var moving := 0.0
		if body != null:
			moving = clampf((float(body.call("speed")) - 3.4) / 1.6, 0.0, 1.0)
		poser.set("gait", moving if (mode == Mode.CHASE or mode == Mode.RECALL) else 0.0)
	if body != null:
		body.call("sit", 1 if mode == Mode.SEATED else 0)
	_footsteps()
	_fade_tag()
	if _bark_left > 0.0:
		_bark_left -= delta
		if _bark_left <= 0.0:
			var label := get_node_or_null("Visual/Bark") as Label3D
			if label != null:
				label.visible = false


## A mode just changed (here or by replication): the pose and sound that go with it.
func _show_mode(body: Node, poser: Node) -> void:
	var was := _shown_mode
	_shown_mode = mode
	var sfx := get_tree().get_first_node_in_group("sfx")
	var late := _now() - mode_at
	var fresh := late <= 0.5
	if poser == null or body == null:
		return
	match mode:
		Mode.SEATED:
			poser.call("hold", "driver_wheel" if crew_index() == 1 else "sit_bench")
		Mode.HOP_OUT, Mode.HOP_IN:
			poser.call("hold", "hop_out" if mode == Mode.HOP_OUT else "hop_in", Constants.CREW_HOP_SECONDS, late)
			stats["hops"] = int(stats["hops"]) + 1
			if sfx != null and fresh and mode == Mode.HOP_OUT:
				get_tree().create_timer(maxf(0.0, Constants.CREW_HOP_SECONDS * 0.9 - late)).timeout.connect(func() -> void:
					if is_inside_tree():
						sfx.call("play_on", "hop_land", self))
		Mode.SPOT:
			poser.call("hold", "")
			# Head snap, whistle, point.
			body.set("face_turn", 0.0)
			body.call("gesture", "point")
			if sfx != null and fresh:
				sfx.call("play_on", "whistle", self)
		Mode.WINDUP:
			poser.call("hold", "lunge_windup")
		Mode.LUNGE:
			poser.call("hold", "lunge")
		Mode.WHIFF:
			poser.call("hold", "whiff_sprawl", Constants.CREW_WHIFF_SECONDS, late)
		Mode.GOTCHA:
			poser.call("hold", "collar_grab")
		Mode.CITE:
			poser.call("hold", "cite_scribble")
		Mode.ESCORT:
			if was == Mode.CITE:
				poser.call("shot", "tear_page")
			poser.call("hold", "arm_link")
		Mode.DOOR:
			poser.call("hold", "wave_off", 1.2)
		Mode.SEARCH:
			poser.call("hold", "")
			body.call("gesture", "look_around")
		Mode.INVESTIGATE:
			poser.call("hold", "investigate_peer")
		_:
			poser.call("hold", "")


## Heavy cartoon footsteps, on every peer, from how far the drawn body walked.
func _footsteps() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null or not visual.visible:
		_last_visual = Vector3.INF
		return
	var at := visual.global_position
	if _last_visual.is_finite() and (mode != Mode.SEATED):
		var moved := Vector2(at.x - _last_visual.x, at.z - _last_visual.z).length()
		if moved < 2.0:
			_step_distance += moved
	_last_visual = at
	if _step_distance >= Constants.CREW_STRIDE_METERS:
		_step_distance = 0.0
		var sfx := get_tree().get_first_node_in_group("sfx")
		if sfx != null:
			sfx.call("play_at", "crew_step", at)


## The name tag stays a readable size on screen and fades out up close and far off.
func _fade_tag() -> void:
	var tag := get_node_or_null("Visual/Label") as Label3D
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if tag == null or camera == null:
		return
	var distance := camera.global_position.distance_to(tag.global_position)
	var alpha := clampf((distance - Constants.CREW_TAG_FADE_NEAR) / 0.8, 0.0, 1.0) * clampf((Constants.CREW_TAG_FADE_FAR - distance) / 4.0, 0.0, 1.0)
	tag.modulate.a = alpha
	tag.outline_modulate.a = alpha
	tag.visible = alpha > 0.01


# ---------------------------------------------------------------- helpers

func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _encounter() -> Node:
	return get_tree().get_first_node_in_group("nice_encounter")


func _lot_zone() -> Node3D:
	var world := get_tree().get_first_node_in_group("world")
	return world.get_node_or_null("LotZone") as Node3D if world != null else null


## Bake a fresh navigation mesh from the lot's static colliders, so the crew paths
## around the house, fences, cover, and hide spots of whichever lot is loaded.
func _bake_navmesh() -> void:
	# Shared with the hired hands: one bake per yard (npcs/lot_nav.gd).
	_LotNav.ensure(_lot_zone())
