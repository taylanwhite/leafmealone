extends RefCounted

## Authority: local, cosmetic. Real shapes for the yard props in
## props/yard_prop.tscn, built inside the prop's smoothed Visual node so they
## move with it, in place of the gray-box cube. The prop's color is the base.
## The wheelbarrow shows the bags it's carrying.

const _LowPoly = preload("res://props/low_poly.gd")
const _YardModels = preload("res://props/yard_models.gd")
## The Visual node sits this high above the prop's base.
const VISUAL_HEIGHT: float = 0.35


static func dress(prop: Node3D, kind: String, color: Color) -> void:
	var visual := prop.get_node_or_null("Visual") as MeshInstance3D
	if visual == null:
		return
	# Rebuild only when the kind changes (it can arrive after the prop is ready).
	var old := visual.get_node_or_null("Look")
	if old != null:
		if str(old.get_meta("kind", "")) == kind:
			return
		old.free()
	var look := Node3D.new()
	look.set_meta("kind", kind)
	look.name = "Look"
	look.position.y = -VISUAL_HEIGHT
	visual.add_child(look)
	match kind:
		"trash":
			_trash_can(look, color)
		"wheelbarrow":
			_wheelbarrow(look, color)
		"gnome":
			_gnome(look)
		"leaf_bag":
			_leaf_bag(look)
		"rake":
			_rake(look)
		_:
			_LowPoly.paint(_LowPoly.box(look, Vector3(0.7, 0.7, 0.7), Vector3(0, 0.35, 0), color), "planks")
	# The cube stays for its color code, but nothing draws it now.
	visual.mesh = null


## The rake lies flat when nobody has it. In hand it angles down in front of the
## holder with the tines on the leaves, and sweeps while its holder rakes.
static func pose_rake(prop: Node3D, holder: Node3D, raking: bool) -> void:
	var look := prop.get_node_or_null("Visual/Look") as Node3D
	if look == null or str(look.get_meta("kind", "")) != "rake":
		return
	var pose := look.get_node_or_null("Pose") as Node3D
	if pose == null:
		return
	if holder == null:
		look.rotation = Vector3.ZERO
		pose.rotation = Vector3(0.0, 0.0, PI * 0.5)
		pose.position = Vector3(0.0, 0.1, 0.0)
		return
	# Face the way the holder faces, handle up toward them, tines down ahead.
	look.global_rotation = Vector3(0.0, holder.global_rotation.y, 0.0)
	# Reach out, then drag back, once per stroke.
	var phase := fmod(Time.get_ticks_msec() / 1000.0, Constants.RAKE_STROKE_SECONDS) / Constants.RAKE_STROKE_SECONDS
	var sweep := (0.3 - 0.6 * phase) if raking else 0.0
	pose.rotation = Vector3(-0.85, 0.0, 0.0)
	pose.position = Vector3(0.0, -0.1, sweep)


## Show this many bags in the wheelbarrow's tray.
static func show_bags(prop: Node3D, count: int) -> void:
	var bags := prop.get_node_or_null("Visual/Look/Bags") as Node3D
	if bags == null:
		return
	for index: int in bags.get_child_count():
		(bags.get_child(index) as Node3D).visible = index < count


static func _trash_can(look: Node3D, color: Color) -> void:
	look.add_child(_YardModels.node("trash", color))


static func _wheelbarrow(look: Node3D, color: Color) -> void:
	look.add_child(_YardModels.node("wheelbarrow", color))
	# Bags ride in the tray, shown as many as it carries.
	var bags := Node3D.new()
	bags.name = "Bags"
	look.add_child(bags)
	for index: int in 8:
		var spot := Vector3(-0.13 + float(index % 2) * 0.26, 0.47 + floorf(float(index) / 4.0) * 0.26, -0.22 + float(index / 2 % 2) * 0.36)
		var bag := _YardModels.node("leaf_bag")
		bags.add_child(bag)
		bag.position = spot
		bag.rotation.y = float(index) * 1.3
		bag.scale = Vector3.ONE * 0.5
		bag.visible = false


static func _gnome(look: Node3D) -> void:
	look.add_child(_YardModels.node("gnome"))


static func _leaf_bag(look: Node3D) -> void:
	look.add_child(_YardModels.node("leaf_bag"))


## The job's one rake, built standing with its head at the Pose origin.
static func _rake(look: Node3D) -> void:
	var pose := Node3D.new()
	pose.name = "Pose"
	look.add_child(pose)
	pose.add_child(_YardModels.node("rake", Color.WHITE, Vector3.ONE, {"roughness": 0.6, "specular": 0.3}))
