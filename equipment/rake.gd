extends Node

## Authority: owning peer sends the request. The leaf field decides what changes.
## Primary rakes. Secondary bags leaves, which is what currently counts as cleaned.
##
## The rake swings (docs/GAME.md, "Raking: the push-sweep"; equipment/rake_stroke.gd):
## a press starts a 0.6 s swing whose two bites are the field strokes, on the
## raker's own peer. Everyone else's copy of this node replays that swing from the
## field's stroke events, so the rake, the leaves and the sound arrive together.
## The look comes from props/rake_motion.gd, the leaves from leaves/, the sounds
## from audio/ (raking:2, 3 and 5): nothing here draws or plays anything.

## Emitted on the raker's own peer each time a swing bites (0 = the plant, 1 =
## mid-drive), with the leaves it moved (0 when the field doesn't say).
signal stroke_bite(bite: int, moved: int)
## Emitted on everyone else's peer when a stroke event drives this player's swing.
signal remote_bite(bite: int)

## Strength, width, and bag radius live in Constants (RAKE_*, HAND_RAKE_*, BAG_RADIUS),
## because the host checks them too. TODO(balance): move them into the workbook.
const REACH: float = 1.5
const _Strings = preload("res://ui/strings.gd")
const _StrokeCam = preload("res://player/stroke_cam.gd")
## Hand raking: a stroke at most this often, so flailing doesn't turn into a fast rake.
const HAND_STROKE_SECONDS: float = 0.35

var _hand_wait: float = 0.0
var _rake_wait: float = 0.0
var _work_wait: float = 0.0
var _spray: CPUParticles3D
var _hooked_field: Node
var _events_field: Node


func _physics_process(delta: float) -> void:
	var player := get_parent() as CharacterBody3D
	if player == null or multiplayer.multiplayer_peer == null:
		return
	if not player.is_multiplayer_authority():
		# Someone else's swing, replayed from their stroke events.
		RakeStroke.remote_step(player.name.to_int(), delta)
		return
	_hook_refusal()
	_show_pile(player, delta)
	_hand_wait = maxf(0.0, _hand_wait - delta)
	_rake_wait = maxf(0.0, _rake_wait - delta)
	_work_wait = maxf(0.0, _work_wait - delta)
	var held: Node = player.call("_held_prop")
	var has_rake := held != null and str(held.get("kind")) == "rake"
	var held_kind := str(held.get("kind")) if held != null else ""
	if has_rake:
		_ensure_stroke_cam(player)
	# Clicking around the phone or a window isn't working the yard.
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and ui.visible and bool(ui.call("any_window_open")):
		_set_spray(player, "")
		_swing(player, delta, false)
		return
	# R2:3 hidden in a spot or a pile, the hands are tucked in: secondary peeks.
	if bool(player.call("is_hidden")):
		_set_spray(player, "")
		_swing(player, delta, false)
		return
	_set_spray(player, held_kind if Input.is_action_pressed("primary") else "")
	var up_high := bool(player.call("is_up_high"))
	# The rake swings on a 0.6 s rhythm, two strokes a swing (rake_stroke.gd).
	_swing(player, delta, has_rake and not up_high)
	# Up a ladder or on the roof: left click works the gutters and the roof's
	# leaves, by hand or with the leaf blower.
	if up_high and held_kind != "hose" and held_kind != "pressure_washer":
		if Input.is_action_pressed("primary") and _work_wait <= 0.0:
			_work_wait = 0.15
			var tasks := get_tree().get_first_node_in_group("job_tasks")
			if tasks != null:
				var reach_to := player.global_position + Vector3(0.0, 1.0, 0.0) - player.global_basis.z * 0.6
				tasks.call("request_work", "clean_gutters", player.global_position + Vector3(0.0, 1.5, 0.0) - player.global_basis.z * 0.4, -player.global_basis.z)
				tasks.call("request_work", "clear_roof", reach_to, -player.global_basis.z)
			var body := player.get_node_or_null("Visual/CartoonBody")
			if body != null and held_kind == "" and not bool(body.call("is_gesturing")):
				body.call("gesture", "scratch")
		return
	# A ladder in hand: left click sets it up against the house.
	if held_kind == "ladder":
		if Input.is_action_just_pressed("primary"):
			held.call("request_place_ladder")
		return
	# A tool: left click uses it. G throws anything (player.gd).
	if Constants.TOOL_PRICES.has(held_kind):
		if Input.is_action_pressed("primary"):
			_use_tool(player, held_kind)
		return
	if held != null and not has_rake:
		return
	if Input.is_action_pressed("primary"):
		# With the rake, _swing does the strokes.
		if not has_rake and _hand_wait <= 0.0 and not bool(player.get("winding")) and not bool(player.call("wants_punch")):
			_hand_wait = HAND_STROKE_SECONDS
			_hand_rake(player)
	elif Input.is_action_just_pressed("secondary"):
		_stroke(player, true, 0.0, 0.0)


## The raker's own swing, every tick (bots press the same buttons, so they swing
## too). can_rake: the rake is in hand and in use; false cancels a swing that
## hasn't bitten yet. Each bite is one field stroke, exactly today's request.
func _swing(player: CharacterBody3D, delta: float, can_rake: bool) -> void:
	var actor := player.name.to_int()
	var pressed := can_rake and (Input.is_action_pressed("primary") or Input.is_action_just_pressed("primary"))
	var fired := RakeStroke.local_step(actor, delta, pressed, not can_rake)
	for bite: int in fired:
		_rake_bite(player, bite)


## One bite of the swing: a field stroke from where the rake reaches, the way you face.
func _rake_bite(player: CharacterBody3D, bite: int) -> void:
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return
	forward = forward.normalized()
	var origin := player.global_position + forward * REACH + Vector3(0.0, 0.2, 0.0)
	var field := _field_near(origin)
	if field == null:
		return
	var actor := player.name.to_int()
	var moved := 0
	if field.has_signal("stroke_event"):
		# raking:1: the bite and the swing's tempo ride along, and the field says
		# how much it moved (predicted on a client).
		var result: Variant = field.call("request_rake", origin, forward, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH, bite, RakeStroke.cycle_seconds(actor))
		moved = int(result) if typeof(result) == TYPE_INT else 0
	else:
		# Before raking:1 the field doesn't say: the leaves under the head will do.
		moved = int(float(field.call("units_within_world", origin, Constants.RAKE_WIDTH * 0.5)) * Constants.RAKE_LOAD_GUESS)
		field.call("request_rake", origin, forward, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH)
	RakeStroke.set_load(actor, moved)
	stroke_bite.emit(bite, moved)


## Where this player is in a swing, on every peer: 0..1, or -1 when not swinging.
func stroke_phase() -> float:
	var player := get_parent()
	return RakeStroke.phase_of(player.name.to_int()) if player != null else -1.0


## Every peer: hooks the current field's stroke events (each job is a new field)
## and leans this player's body into their swing.
func _process(_delta: float) -> void:
	var player := get_parent() as Node3D
	if player == null or multiplayer.multiplayer_peer == null:
		return
	_hook_events()
	var body := player.get_node_or_null("Visual/CartoonBody")
	if body == null or not body.has_method("set_work_pose"):
		return
	var held: Node = player.call("_held_prop") if player.has_method("_held_prop") else null
	if held != null and str(held.get("kind")) == "rake":
		var shown := RakeStroke.display(player.name.to_int())
		body.call("set_work_pose", float(shown["lean"]), float(shown["twist"]), float(shown["hip"]), float(shown.get("crouch", 0.0)))
	else:
		body.call("set_work_pose", 0.0, 0.0, 0.0)


func _hook_events() -> void:
	var field := _field_near(Vector3.ZERO)
	if field == null or field == _events_field:
		return
	_events_field = field
	if field.has_signal("stroke_event"):
		field.connect("stroke_event", _on_stroke_event)


## A stroke somebody made (contract C1). Only this player's, and only ones this
## peer didn't make itself (its own swing already played them).
func _on_stroke_event(ev: Dictionary) -> void:
	var player := get_parent() as Node3D
	if player == null or int(ev.get("actor", 0)) != player.name.to_int():
		return
	# This machine's player really bagged a pile (a refused one never gets here):
	# the pile's price stops showing the bag key.
	if str(ev.get("kind", "")) == "bag" and int(ev.get("moved", 0)) > 0 and player.name.to_int() == Net.local_peer_id():
		bagged_once = true
	if bool(ev.get("local", false)):
		return
	match str(ev.get("kind", "")):
		"rake":
			RakeStroke.on_event(int(ev["actor"]), ev)
			remote_bite.emit(int(ev.get("bite", 0)))
		"hand":
			var body := player.get_node_or_null("Visual/CartoonBody")
			if body != null and not bool(body.call("is_gesturing")):
				body.call("gesture", "flail")


## Your own first-person camera nods with the plant (player/stroke_cam.gd).
func _ensure_stroke_cam(player: CharacterBody3D) -> void:
	if not Constants.RAKE_CAM_ENABLED:
		return
	var camera := player.get_node_or_null("Visual/Head/FirstPerson") as Camera3D
	if camera == null or camera.has_node("StrokeCam"):
		return
	var cam: Node = _StrokeCam.new()
	cam.name = "StrokeCam"
	cam.set("actor", player.name.to_int())
	camera.add_child(cam)


## Using a tool: the leaf blower puffs leaves along like a super rake; the rest
## send their work to the job's tasks (net/work/job_tasks.gd), aimed where you look.
func _use_tool(player: CharacterBody3D, tool_kind: String) -> void:
	if tool_kind == "leaf_blower":
		if _rake_wait <= 0.0:
			_rake_wait = Constants.BLOWER_PUFF_SECONDS
			_stroke(player, false, Constants.BLOWER_STRENGTH, Constants.BLOWER_WIDTH)
		return
	if tool_kind == "lawn_mower":
		# Left click pulls the cord; once it's running it mows by being pushed
		# around, and another pull switches it off (let go while it runs and it drives away).
		if Input.is_action_just_pressed("primary"):
			_held_prop(player).call("request_start")
			var body := player.get_node_or_null("Visual/CartoonBody")
			if body != null:
				body.call("gesture", "startle")
		return
	if _work_wait > 0.0:
		return
	_work_wait = 0.15
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	if tasks == null:
		return
	var task := ""
	for task_id: String in Constants.TASK_TOOLS:
		if str(Constants.TASK_TOOLS[task_id]) == tool_kind:
			task = task_id
	if task == "":
		return
	var head := player.get_node_or_null("Visual/Head") as Node3D
	var eye := head.global_position if head != null else player.global_position + Vector3(0.0, 1.6, 0.0)
	var look := -head.global_basis.z if head != null else -player.global_basis.z
	var forward := -player.global_basis.z
	var origin := player.global_position
	match task:
		"wash_windows":
			if str(_held_prop(player).get("hose_source")) == "":
				return
			origin = eye
			look = hose_aim(player, look)
			# The water leaves the nozzle you're holding, the way it points.
			var tip: Variant = load("res://props/prop_looks.gd").spray_tip(_held_prop(player))
			if tip != null:
				origin = (tip as Transform3D).origin
				look = -(tip as Transform3D).basis.z.normalized()
		"power_wash":
			# Where the look meets the ground, within reach.
			var reach := float(Constants.TASK_REACH["power_wash"])
			var distance := reach * 0.6
			if look.y < -0.05:
				distance = clampf((eye.y - 0.05) / -look.y, 0.6, reach)
			origin = eye + look * distance
			origin.y = player.global_position.y + 0.05
		"clean_gutters":
			origin = player.global_position
		"trim_hedges":
			origin = player.global_position + forward * 0.9 + Vector3(0.0, 1.2, 0.0)
		"paint_fence":
			origin = player.global_position + forward * 0.9 + Vector3(0.0, 0.5, 0.0)
	if (task == "power_wash" or task == "paint_fence") and float(_held_prop(player).get("water")) <= 0.0:
		return
	tasks.call("request_work", task, origin, look)


func _held_prop(player: CharacterBody3D) -> Node:
	return player.call("_held_prop")


## Where the water goes: where you look, except a hydrant's hose has a mind of
## its own and thrashes around.
static func hose_aim(player: Node3D, look: Vector3) -> Vector3:
	var held: Node = player.call("_held_prop")
	if held == null or str(held.get("hose_source")) != "hydrant":
		return look
	var t := Time.get_ticks_msec() / 1000.0
	var thrash := look.rotated(Vector3.UP, sin(t * 2.1) * 0.7 + sin(t * 5.3) * 0.15)
	return thrash.rotated(thrash.cross(Vector3.UP).normalized(), sin(t * 1.6) * 0.35).normalized()


## The holder sees their own hose or washer spraying; everyone else sees the
## host's splashes where the water lands.
func _set_spray(player: CharacterBody3D, tool_kind: String) -> void:
	# The hose and the washer draw their own water (props/water_stream.gd); only the blower puffs here.
	var spraying := tool_kind == "leaf_blower"
	if not spraying:
		if _spray != null:
			_spray.emitting = false
		return
	if _spray == null:
		_spray = CPUParticles3D.new()
		_spray.amount = 60
		_spray.lifetime = 0.5
		var mesh := SphereMesh.new()
		mesh.radius = 0.035
		mesh.height = 0.07
		_spray.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.7, 0.85, 1.0, 0.7)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spray.material_override = material
		_spray.spread = 6.0
		_spray.gravity = Vector3(0.0, -6.0, 0.0)
		_spray.local_coords = false
		player_parent().add_child(_spray)
	var head := player.get_node_or_null("Visual/Head") as Node3D
	var look := -head.global_basis.z if head != null else -player.global_basis.z
	_spray.global_position = player.global_position + Vector3(0.0, 1.0, 0.0) + (-player.global_basis.z) * 0.8 + player.global_basis.x * 0.25
	_spray.direction = look
	var speed := 9.0 if tool_kind == "hose" else (14.0 if tool_kind == "pressure_washer" else 6.0)
	_spray.initial_velocity_min = speed * 0.8
	_spray.initial_velocity_max = speed
	(_spray.material_override as StandardMaterial3D).albedo_color = Color(0.85, 0.75, 0.55, 0.0) if tool_kind == "leaf_blower" else Color(0.7, 0.85, 1.0, 0.7)
	_spray.emitting = true


## The thickest spot just ahead: where the pile is. Raking shoves leaves a few
## cells forward each stroke, so the pile ends up a little way out in front.
func _pile_spot(player: CharacterBody3D, field: Node) -> Vector3:
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best := player.global_position + forward * REACH + Vector3(0.0, 0.2, 0.0)
	var best_units := -1
	var distance := Constants.PILE_SEARCH_NEAR
	while distance <= Constants.PILE_SEARCH_FAR + 0.001:
		var spot := player.global_position + forward * distance + Vector3(0.0, 0.2, 0.0)
		var units := int(field.call("units_within_world", spot, Constants.BAG_RADIUS))
		if units > best_units:
			best_units = units
			best = spot
		distance += 0.4
	return best


## The local player with the rake sees what the pile ahead would bag for, over
## the pile itself: gold once it's big enough to bag, gray while it's too thin.
var _pile_label: Label3D
## Has this machine's player bagged a pile yet (the field's "bag" stroke event)? Then
## the pile's label drops the bag key for the rest of this run of the game.
static var bagged_once: bool = false
var _pile_wait: float = 0.0


func _show_pile(player: CharacterBody3D, delta: float) -> void:
	_pile_wait -= delta
	if _pile_wait > 0.0:
		return
	_pile_wait = 0.15
	var held: Node = player.call("_held_prop")
	var show := held != null and str(held.get("kind")) == "rake" and Net.player_zone(Net.local_peer_id()) == Net.Zone.LOT
	var field: Node = _field_near(player.global_position) if show else null
	if field == null:
		if _pile_label != null:
			_pile_label.visible = false
		return
	if _pile_label == null:
		_pile_label = Label3D.new()
		_pile_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_pile_label.fixed_size = true
		_pile_label.pixel_size = 0.0011
		_pile_label.font_size = 26
		_pile_label.outline_size = 8
		_pile_label.no_depth_test = true
		player_parent().add_child(_pile_label)
	var spot := _pile_spot(player, field)
	var units := int(field.call("units_within_world", spot, Constants.BAG_RADIUS))
	var enough := units >= int(Constants.MIN_BAG_CELLS * 60)
	# Plain leafy ground isn't a pile yet: only show one that's on its way.
	if units < int(Constants.MIN_BAG_CELLS * 60 * 0.5):
		_pile_label.visible = false
		return
	_pile_label.visible = true
	_pile_label.global_position = spot + Vector3(0.0, 0.5, 0.0)
	# x1:text: the price, grey until it's a pile, gold once it bags. The bag key
	# rides along until this player's first bag of the session.
	var dollars := int(field.call("dollars_for", units))
	var with_key := enough and not bagged_once
	_pile_label.text = _Strings.keyed(_Strings.UI["pile_value"] % dollars) if with_key else _Strings.UI["pile_cash"] % dollars
	_pile_label.modulate = Color(1.0, 0.85, 0.3) if enough else Color(0.8, 0.8, 0.8, 0.8)


## No rake: scoop at the leaves with your hands. It barely does anything, and
## it looks it.
func _hand_rake(player: CharacterBody3D) -> void:
	_stroke(player, false, Constants.HAND_RAKE_STRENGTH, Constants.HAND_RAKE_WIDTH)
	var body := player.get_node_or_null("Visual/CartoonBody")
	if body != null and not bool(body.call("is_gesturing")):
		body.call("gesture", "flail")
	if randf() < 0.25:
		player.call("say", ["vo_hup", "vo_huh", "vo_eh"][randi() % 3])


func _stroke(player: CharacterBody3D, bag: bool, strength: float, width: float) -> void:
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return
	forward = forward.normalized()
	var origin := player.global_position + forward * REACH + Vector3(0.0, 0.2, 0.0)
	var field := _field_near(origin)
	if field == null:
		return
	if bag:
		# Bag the pile, wherever the strokes pushed it, not a fixed spot.
		field.call("request_collect", _pile_spot(player, field), Constants.BAG_RADIUS)
	else:
		# Hands and the blower; the leaves fly and sound from the field's events.
		field.call("request_rake", origin, forward, width, strength)


## A refused bag (too few leaves) gets a puzzled "eh?" from you; out of bags,
## "Out of bags." too, since the supply shows nowhere on the yard (x1:text).
## Each job loads a new lot and leaf field, so hook whichever one is current.
func _hook_refusal() -> void:
	var field := _field_near(Vector3.ZERO)
	if field == null or field == _hooked_field or not field.has_signal("bag_refused"):
		return
	_hooked_field = field
	field.connect("bag_refused", func(peer_id: int, reason: String) -> void:
		var player := get_parent()
		if player != null and peer_id == player.name.to_int():
			player.call("say", "vo_eh")
			if reason == "no_bags" and player.has_method("flash_hint"):
				player.call("flash_hint", preload("res://ui/strings.gd").SHOP_UI["hud_out_of_bags"])
	)


func _field_near(_origin: Vector3) -> Node:
	var fields := get_tree().get_nodes_in_group("leaf_field")
	if fields.is_empty():
		return null
	return fields[0] as Node


func player_parent() -> Node:
	return get_parent()
