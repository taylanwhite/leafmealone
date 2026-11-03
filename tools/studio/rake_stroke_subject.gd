extends RefCounted

## Dev tool, local only. Studio subject "rake_stroke" (tools/studio/studio.gd):
## one swing of the rake (equipment/rake_stroke.gd, props/rake_motion.gd) frozen at
## four of its eight phases, one cartoon body per view, posed the way the game
## poses it (RakeMotion on the prop, the arms on its grips, the body leaning).
##
##   Godot --path . res://tools/studio/studio.tscn -- --subject=rake_stroke --view=side --page=0 --tier=0 --out=build/r1/rake/side_0.png
##
## --view=side|front|back|fp (fp: from the eyes, the body hidden and the rake held
## the first-person way, as in the game), --page=0 (lift, plant, early drive, bite B) or 1 (late drive, flick,
## swing back, reach), --tier=0|1|2 (starter, Tune-Up, The Leafinator), --load=0.8.
## Prints each body's grip gap and hand reach, for judging numbers.

const _CartoonBody = preload("res://player/cartoon_body.gd")
const _PropLooks = preload("res://props/prop_looks.gd")
## The eight phases: [phase, fresh] (fresh: the swing starts from standing still).
const PHASES: Array = [[0.1, true], [0.2, false], [0.33, false], [0.5, false], [0.66, false], [0.78, false], [0.92, false], [0.1, false]]
const SPACING: float = 30.0


## A stand-in for a yard prop: just what the looks read.
class StrokeProp extends Node3D:
	var kind := "rake"
	var held_by := 1


static func build(root: Node3D, options: Dictionary) -> void:
	var view := str(options.get("view", "side"))
	var page := clampi(int(options.get("page", "0")), 0, 1)
	var tier := clampi(int(options.get("tier", "0")), 0, 2)
	var load := float(options.get("load", "0.8"))
	var views: Array = []
	for slot: int in 4:
		var entry: Array = PHASES[page * 4 + slot]
		var x := float(slot) * SPACING
		var holder := Node3D.new()
		holder.name = "Holder%d" % slot
		root.add_child(holder)
		holder.position = Vector3(x, 0.0, 0.0)
		var visual := Node3D.new()
		visual.name = "Visual"
		holder.add_child(visual)
		var head := Node3D.new()
		head.name = "Head"
		visual.add_child(head)
		head.position.y = 1.6
		var body: Node3D = _CartoonBody.new()
		body.name = "CartoonBody"
		body.call("dress_from_seed", 11 + slot * 5)
		visual.add_child(body)
		body.call("build", head)
		var prop := StrokeProp.new()
		prop.name = "Rake%d" % slot
		root.add_child(prop)
		var mesh := MeshInstance3D.new()
		mesh.name = "Visual"
		mesh.position.y = _PropLooks.VISUAL_HEIGHT
		prop.add_child(mesh)
		_PropLooks.dress(prop, "rake", Color.WHITE)
		var pose := prop.get_node("Visual/Look/Pose") as Node3D
		RakeMotion.dress(pose, tier)
		pose.top_level = true
		prop.global_position = holder.global_position + Vector3(0.3, 0.75, -0.9)
		var sample := RakeStroke.sample(float(entry[0]), load, 1.0, bool(entry[1]))
		# Run the body long enough for its lean and reach to settle. From the eyes the
		# rake is posed the first-person way (props/rake_motion.gd first_person).
		var first_person := view == "fp"
		for _step: int in 40:
			_pose(prop, holder, sample, first_person)
			var grips := RakeMotion.grips(prop)
			body.call("set_hold", grips[0], grips[1])
			body.call("set_work_pose", float(sample["lean"]), float(sample["twist"]), float(sample["hip"]), float(sample.get("crouch", 0.0)))
			body.call("_physics_process", 1.0 / 60.0)
		_pose(prop, holder, sample, first_person)
		var grips := RakeMotion.grips(prop)
		var reach := ""
		for side: int in 2:
			var shoulder: Vector3 = body.call("shoulder_position", side)
			reach += " %s %.2f" % ["right" if side == 0 else "left", shoulder.distance_to(grips[side])]
		# How close the handle comes to the head and the torso (negative: through them).
		var clear := INF
		var base := pose.global_transform
		for index: int in 21:
			var point := base * Vector3(0.0, 0.2 + 1.42 * float(index) / 20.0, 0.0)
			var local := holder.global_transform.affine_inverse() * point
			clear = minf(clear, local.distance_to(Vector3(0.0, 1.62, 0.0)) - 0.28)
			var spine := Vector3(0.0, clampf(local.y, 0.85, 1.35), 0.0)
			clear = minf(clear, local.distance_to(spine) - 0.21)
		print("[Studio] rake_stroke phase %.2f%s: grips %.2f m apart, reach%s, head %.2f m out, handle clears the body by %.2f m" % [float(entry[0]), " fresh" if bool(entry[1]) else "", grips[0].distance_to(grips[1]), reach, float(sample["head_forward"]), clear])
		_label(root, "%.2f%s" % [float(entry[0]), " fresh" if bool(entry[1]) else ""], holder.global_position + Vector3(0.0, 2.3, 0.0))
		match view:
			"front":
				views.append({"from": Vector3(x + 1.2, 1.3, -4.6), "at": Vector3(x, 0.75, -0.6), "fov": 40.0})
			"back":
				# Over the left shoulder from behind: where the handle's top goes.
				views.append({"from": Vector3(x - 1.6, 2.2, 2.2), "at": Vector3(x, 0.9, -0.5), "fov": 45.0})
			"fp":
				# From the eyes, looking down at the leaves the way you rake; no body.
				body.visible = false
				head.visible = false
				views.append({"from": Vector3(x + 0.03, 1.6, -0.08), "at": Vector3(x + 0.05, 0.75, -1.9), "fov": 75.0})
			_:
				views.append({"from": Vector3(x + 4.2, 1.15, -0.95), "at": Vector3(x, 0.75, -0.95), "fov": 42.0})
	root.set_meta("views", views)


static func _pose(prop: Node3D, holder: Node3D, sample: Dictionary, first_person: bool) -> void:
	if first_person:
		var pose := prop.get_node("Visual/Look/Pose") as Node3D
		RakeMotion.pose_frame(pose, _PropLooks.holder_frame(holder), sample, 0, 0.0, [], true)
	else:
		RakeMotion.pose(prop, holder, sample, 0)


static func _label(root: Node3D, text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.004
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)
	label.position = at
