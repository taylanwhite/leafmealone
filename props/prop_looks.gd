extends RefCounted

## Authority: local, cosmetic. Real shapes for the yard props in
## props/yard_prop.tscn, built inside the prop's smoothed Visual node so they
## move with it, in place of the gray-box cube. The prop's color is the base.
## The wheelbarrow shows the bags it's carrying.

const _LowPoly = preload("res://props/low_poly.gd")
const _YardModels = preload("res://props/yard_models.gd")
## The Visual node sits this high above the prop's base.
const VISUAL_HEIGHT: float = 0.35
## Tools held up in front of the face and aimed with the view, and where they sit
## in the head's space (x right, y up, -z ahead).
const HANDHELD: Dictionary = {
	"hose": Vector3(0.2, -0.24, -0.5),
	"leaf_blower": Vector3(0.24, -0.62, -0.2),
	"hedge_trimmer": Vector3(0.18, -0.5, -0.25),
	"paint_roller": Vector3(0.22, -0.32, -0.42),
}


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
			# Tools and anything else props/yard_models.gd knows how to build.
			look.add_child(_YardModels.node(kind, color, Vector3(0.7, 0.7, 0.7), {"roughness": 0.55, "specular": 0.3}))
	# The cube stays for its color code, but nothing draws it now.
	visual.mesh = null
	# Hoses trail a hose and spray water; washers spray water.
	if kind == "hose" and prop.get_node_or_null("HoseRope") == null:
		var rope: Node3D = load("res://props/hose_rope.gd").new()
		rope.name = "HoseRope"
		prop.add_child(rope)
	if (kind == "hose" or kind == "pressure_washer") and prop.get_node_or_null("WaterStream") == null:
		var stream: Node3D = load("res://props/water_stream.gd").new()
		stream.name = "WaterStream"
		prop.add_child(stream)
	# Tools make their running noise where they are, for everyone nearby.
	if load("res://audio/tool_sound.gd").LOOPS.has(kind) and prop.get_node_or_null("ToolSound") == null:
		var sound: Node = load("res://audio/tool_sound.gd").new()
		sound.name = "ToolSound"
		prop.add_child(sound)


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


## A ladder set up against the house: standing from its foot (the prop) up to
## top, stretched to reach (it's an extension ladder), rungs across the wall.
static func pose_ladder_up(prop: Node3D, top: Vector3) -> void:
	var look := prop.get_node_or_null("Visual/Look") as Node3D
	if look == null:
		return
	var foot := prop.global_position
	var up := top - foot
	var along := up.normalized()
	var across := Vector3.UP.cross(Vector3(up.x, 0.0, up.z)).normalized()
	if across.length() < 0.1:
		across = Vector3.RIGHT
	var face := across.cross(along).normalized()
	# The model lies along Z, 2.4 m long, centered: stretch Z to the length needed.
	var basis := Basis(across, face, along * (up.length() / 2.4))
	look.global_transform = Transform3D(basis, foot + up * 0.5)


## Held tools face the way their holder faces; set down, they sit level.
##
## Handheld tools (HANDHELD) are held up in front of the holder's view and point
## where they look, so you see the nozzle you're aiming. Every peer has the
## holder's head (its pitch replicates), so everyone sees the same aim. A hose
## on a hydrant thrashes in your hands. The pressure washer rolls along the
## ground while you hold its wand.
static func pose_tool(prop: Node3D, holder: Node3D) -> void:
	var look := prop.get_node_or_null("Visual/Look") as Node3D
	if look == null:
		return
	var kind := str(prop.get("kind"))
	var wand := prop.get_node_or_null("Wand") as Node3D
	if holder == null:
		look.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -VISUAL_HEIGHT, 0.0))
		if wand != null:
			wand.visible = false
		return
	var head := holder.get_node_or_null("Visual/Head") as Node3D
	var aimed := HANDHELD.has(kind) and not (kind == "hose" and str(prop.get("hose_source")) == "")
	if head == null or not aimed:
		look.global_rotation = Vector3(0.0, holder.global_rotation.y, 0.0)
		if kind == "pressure_washer" and head != null:
			_pose_wand(prop, holder, head)
		return
	look.global_transform = Transform3D(aim_basis(holder, kind == "hose"), head.global_transform * (HANDHELD[kind] as Vector3))


## Which way a held tool points: where the holder looks, or for a hydrant hose,
## wherever the water drags it.
static func aim_basis(holder: Node3D, thrash: bool) -> Basis:
	var head := holder.get_node_or_null("Visual/Head") as Node3D
	var look := -head.global_basis.z if head != null else -holder.global_basis.z
	if thrash:
		look = load("res://equipment/rake.gd").hose_aim(holder, look)
	return Basis.looking_at(look, Vector3.UP)


## The pressure washer's spray wand, in hand and aimed, while the unit sits on the ground.
static func _pose_wand(prop: Node3D, holder: Node3D, head: Node3D) -> void:
	var wand := prop.get_node_or_null("Wand") as Node3D
	if wand == null:
		wand = _YardModels.node("wand", Color.WHITE, Vector3.ONE, {"roughness": 0.4, "specular": 0.5})
		wand.name = "Wand"
		wand.top_level = true
		prop.add_child(wand)
	wand.visible = true
	wand.global_transform = Transform3D(aim_basis(holder, false), head.global_transform * Vector3(0.2, -0.3, -0.35))


## Where water leaves a held hose or pressure washer, pointing the way it goes;
## or null when it isn't being held up and aimed.
static func spray_tip(prop: Node3D) -> Variant:
	var kind := str(prop.get("kind"))
	if kind == "hose":
		var nozzle := prop.get_node_or_null("Visual/Look/Nozzle") as Node3D
		if nozzle != null and nozzle.is_visible_in_tree():
			return nozzle.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.22))
	elif kind == "pressure_washer":
		var wand := prop.get_node_or_null("Wand") as Node3D
		if wand != null and wand.visible:
			return wand.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.85))
	return null


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
