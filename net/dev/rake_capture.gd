extends Node

## Dev tool, local only. Frame sequences of the rake swing (raking chunk 4), to
## judge it in motion rather than from single shots. Started by
## net/dev/rake_stroke_test.gd when --rake-capture=<dir> is on the command line
## (windowed, not headless):
##
##   host:     -- --host --no-steam --start-zone=lot --job-seed=777 --yard-size=1 --rake-stroke-test --rake-capture=build/r1/rake/seq
##   observer: -- --join=127.0.0.1 --no-steam --rake-stroke-test --rake-capture=build/r1/rake/seq --sim-lag=150
##
## The host rakes two swings three times, slowed down so every frame is saved:
## from the eyes looking down at the leaves (fp), over the shoulder (tp), and from a
## camera 3.5 m to the side (side). The observer client watches the host from its
## own side camera at real speed (observer). Frames are <dir>/<view>/<ms>.png,
## named by game time since the press, so a sequence reads in order.

## Game time runs this much slower while the host captures.
const SLOW: float = 0.15
## Each capture holds the button this long (two swings) and keeps filming after (s,
## game time).
const HOLD: float = 1.2
const AFTER: float = 0.5

var dir: String = ""
var done: bool = false
var _view: String = ""
var _start_usec: int = 0
var _filming: bool = false
var _camera: Camera3D
var _count: int = 0


func _process(_delta: float) -> void:
	# Two windows fight over focus, and losing it opens the pause menu (which stops
	# the rake): keep the mouse free and the menu shut while filming.
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and bool(ui.call("any_window_open")):
		ui.call("close_pause")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _filming or _view == "":
		return
	var shot := get_viewport().get_texture().get_image()
	var ms := int(float(Time.get_ticks_usec() - _start_usec) / 1000.0 * Engine.time_scale)
	DirAccess.make_dir_recursive_absolute(dir.path_join(_view))
	shot.save_png(dir.path_join(_view).path_join("%05d.png" % ms))
	_count += 1


## Host: the three takes. me holds the rake already.
func run_host(me: Node3D) -> void:
	var rig := me.get_node_or_null("CameraRig")
	# First two swings at full speed, filmed by nobody here: the observer's take.
	Input.action_press(&"primary")
	await get_tree().create_timer(HOLD).timeout
	Input.action_release(&"primary")
	await get_tree().create_timer(4.0).timeout
	for view: String in ["fp", "tp", "side"]:
		if view == "tp" and rig != null:
			rig.call("toggle")
		if view == "side":
			if rig != null:
				rig.call("toggle")
			_camera = Camera3D.new()
			_camera.fov = 55.0
			_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			get_tree().current_scene.add_child(_camera)
			var ahead := -me.global_basis.z
			var right := ahead.cross(Vector3.UP)
			_camera.look_at_from_position(me.global_position + right * 3.2 + ahead * 0.9 + Vector3.UP * 1.0, me.global_position + ahead * 0.9 + Vector3.UP * 0.8, Vector3.UP)
			_camera.make_current()
		# Looking down at the leaves the way you rake.
		me.set("head_pitch", -0.4)
		await _ticks(20)
		Engine.time_scale = SLOW
		_view = view
		_start_usec = Time.get_ticks_usec()
		_filming = true
		Input.action_press(&"primary")
		await get_tree().create_timer(HOLD).timeout
		Input.action_release(&"primary")
		await get_tree().create_timer(AFTER).timeout
		_filming = false
		Engine.time_scale = 1.0
		print("[RakeCapture] %s: %d frames to %s" % [view, _count, dir.path_join(view)])
		_count = 0
		await _ticks(30)
	me.set("head_pitch", 0.0)
	await _film_hand(me)
	if _camera != null:
		_camera.queue_free()
	done = true


## Gravy, the hired hand, at work: from the side, half speed, a few swings.
func _film_hand(me: Node3D) -> void:
	var hires := get_tree().get_first_node_in_group("hires")
	if hires == null:
		return
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	me.call("apply_network_teleport", Transform3D(Basis.IDENTITY, lot.global_position + Vector3(0.0, 0.1, 16.0)))
	hires.call("dev_add_hand", "Gravy")
	await get_tree().create_timer(0.3).timeout
	hires.call("spawn_on_lot")
	var hand: Node3D = null
	var waited := 0.0
	while waited < 25.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var hands := get_tree().get_nodes_in_group("crew_hands")
		if not hands.is_empty() and str((hands[0] as Node).get("action")) == "rake":
			hand = hands[0] as Node3D
			break
	if hand == null:
		print("[RakeCapture] hand: never started raking")
		return
	if _camera == null:
		_camera = Camera3D.new()
		_camera.fov = 55.0
		_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		get_tree().current_scene.add_child(_camera)
	_camera.make_current()
	Engine.time_scale = 0.5
	_view = "hand"
	_start_usec = Time.get_ticks_usec()
	_filming = true
	var filmed := 0.0
	while filmed < 6.0:
		await get_tree().process_frame
		filmed += get_process_delta_time()
		var ahead := hand.global_basis.z
		ahead = Vector3(ahead.x, 0.0, ahead.z).normalized()
		var right := ahead.cross(Vector3.UP)
		_camera.look_at_from_position(hand.global_position + right * 3.2 + ahead * 0.9 + Vector3.UP * 1.0, hand.global_position + ahead * 0.9 + Vector3.UP * 0.8, Vector3.UP)
	_filming = false
	Engine.time_scale = 1.0
	print("[RakeCapture] hand: %d frames to %s" % [_count, dir.path_join("hand")])


## Observer client: a side camera on the host, filming while the host's rake moves.
func run_observer(host: Node3D) -> void:
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_tree().current_scene.add_child(_camera)
	_camera.make_current()
	_view = "observer"
	var waited := 0.0
	var idle := 0.0
	var started := false
	while waited < 40.0:
		await get_tree().process_frame
		var delta := get_process_delta_time()
		waited += delta
		var ahead := -host.global_basis.z
		ahead = Vector3(ahead.x, 0.0, ahead.z).normalized()
		var right := ahead.cross(Vector3.UP)
		_camera.look_at_from_position(host.global_position + right * 3.2 + ahead * 0.9 + Vector3.UP * 1.0, host.global_position + ahead * 0.9 + Vector3.UP * 0.8, Vector3.UP)
		var moving := RakeStroke.is_moving(host.name.to_int())
		if moving and not started:
			started = true
			_start_usec = Time.get_ticks_usec()
			_filming = true
			print("[RakeCapture] observer: the host's rake moves, filming")
		if started:
			idle = 0.0 if moving else idle + delta
			if idle > 3.0:
				break
	_filming = false
	print("[RakeCapture] observer: %d frames to %s" % [_count, dir.path_join(_view)])
	done = true


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame
