extends RefCounted

## Authority: local, cosmetic. Real shapes for the yard props in
## props/yard_prop.tscn, built inside the prop's smoothed Visual node so they
## move with it, in place of the gray-box cube. The prop's color is the base.
## The wheelbarrow shows the bags it's carrying.

const _LowPoly = preload("res://props/low_poly.gd")
const _YardModels = preload("res://props/yard_models.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Strings = preload("res://ui/strings.gd")
## The Visual node sits this high above the prop's base.
const VISUAL_HEIGHT: float = 0.35
## Tools held up in front of the face and aimed with the view, and where they sit
## in the head's space (x right, y up, -z ahead).
const HANDHELD: Dictionary = {
	"hose": Vector3(0.2, -0.2, -0.5),
	"leaf_blower": Vector3(0.26, -0.46, -0.38),
	"hedge_trimmer": Vector3(0.2, -0.34, -0.42),
	"paint_roller": Vector3(0.22, -0.17, -0.45),
}
## A carried leaf bag hangs by its rolled top from both hands: the middle of the
## hands in the holder's head space, and the hand spots on the rim in the bag's
## own space [right, left] (yard_models.gd: rim 0.74-0.8 up, radius 0.25; +Z toward the holder).
const BAG_HANDS: Vector3 = Vector3(0.0, -0.27, -0.4)
const BAG_RIM: Array[Vector3] = [Vector3(0.2, 0.78, 0.15), Vector3(-0.2, 0.78, 0.15)]
## Where the hands go on each aimed tool, in its Look space: [right, left]
## (props/yard_models.gd). One grip table for your own first-person arms and for
## everyone else's view of your body (grip_points).
const TOOL_GRIPS: Dictionary = {
	"hose": [Vector3(0.0, -0.09, 0.06), Vector3(-0.05, -0.02, -0.12)],
	"leaf_blower": [Vector3(0.0, 0.29, 0.07), Vector3(-0.06, 0.1, -0.28)],
	"hedge_trimmer": [Vector3(0.0, 0.2, 0.09), Vector3(-0.05, 0.12, -0.06)],
	"paint_roller": [Vector3(0.0, 0.0, 0.16), Vector3(-0.09, -0.05, 0.02)],
}
## How everything else is held (docs/GAME.md, "2026-11-01, holds"). Per kind:
## - at: where the model's base sits in the holder's body space (origin at the
##   feet, x right, -z ahead); yaw: its turn on top of the holder's; roll (about
##   z) and tilt (about x): turns through pivot (model space). Kinds with "at" are
##   placed by pose_held (tools by pose_tool, when they aren't aimed), and the
##   non-tools' bodies by net_prop._hold_position on the host; the rest keep
##   their own pose.
## - grips: [right, left] hand spots in the model's space, INF for a free hand.
## The gnome is hugged under its little arms facing ahead; the trash can by its
## side handles; the TurfMasters sign by its inner wire, just under the panel,
## turned so the holder reads it; the wheelbarrow by its handle ends, tipped up
## onto its wheel; a hose that isn't hooked up by the reel's frame; the ladder on
## its side on the right shoulder, clear of the head, a hand through a rung.
const HOLDS: Dictionary = {
	"gnome": {"at": Vector3(0.0, 0.62, -0.42), "tilt": -0.12, "pivot": Vector3(0.0, 0.2, 0.0), "grips": [Vector3(0.155, 0.3, -0.01), Vector3(-0.155, 0.3, -0.01)]},
	"trash": {"at": Vector3(0.0, 0.6, -0.47), "grips": [Vector3(0.335, 0.55, 0.0), Vector3(-0.335, 0.55, 0.0)]},
	"turf_sign": {"at": Vector3(0.36, 0.46, -0.5), "yaw": 0.35, "grips": [Vector3(-0.22, 0.49, 0.0), Vector3.INF]},
	"wheelbarrow": {"at": Vector3(0.0, 0.0, -1.12), "tilt": -0.176, "pivot": Vector3(0.0, 0.19, -0.62), "grips": [Vector3(0.25, 0.525, 0.97), Vector3(-0.25, 0.525, 0.97)]},
	"hose": {"at": Vector3(0.0, 0.7, -0.42), "grips": [Vector3(0.15, 0.27, 0.0), Vector3(-0.15, 0.27, 0.0)]},
	# The gas can hangs at your right side by its top handle (yard_models.gd _gas_can).
	"gas_can": {"at": Vector3(0.3, 0.5, -0.22), "grips": [Vector3(0.0, 0.4, 0.0), Vector3.INF]},
	"lawn_mower": {"grips": [Vector3(0.19, 0.95, 0.95), Vector3(-0.19, 0.95, 0.95)]},
	"ladder": {"at": Vector3(0.33, 1.59, 0.0), "roll": PI * 0.5, "tilt": -0.08, "grips": [Vector3(0.0, 0.0, -0.35), Vector3.INF]},
}
## The pressure washer's wand grips, in the wand's space: [right, left].
const WAND_GRIPS: Array[Vector3] = [Vector3(0.0, -0.11, 0.1), Vector3(-0.03, -0.02, -0.3)]


static func dress(prop: Node3D, kind: String, color: Color) -> void:
	var visual := prop.get_node_or_null("Visual") as MeshInstance3D
	if visual == null:
		return
	# Rebuild only when the kind or a tool's tier changes (either can arrive after
	# the prop is ready). A tier dresses the tool: chrome for Mk II, black and gold
	# for Mk III, rust and tape for a used one (props/yard_models.gd tier trim).
	var tier := int(prop.get("tier")) if "tier" in prop else 1
	var old := visual.get_node_or_null("Look")
	if old != null:
		if str(old.get_meta("kind", "")) == kind and int(old.get_meta("tier", 1)) == tier:
			return
		old.free()
	var look := Node3D.new()
	look.set_meta("kind", kind)
	look.set_meta("tier", tier)
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
		"turf_sign":
			_turf_sign(look)
		_:
			# Tools and anything else props/yard_models.gd knows how to build.
			look.add_child(_YardModels.node(kind, color, Vector3(0.7, 0.7, 0.7), {"roughness": 0.55, "specular": 0.3}, tier))
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


## The rake lies flat when nobody has it. In hand it is posed by its holder's swing
## (equipment/rake_stroke.gd, props/rake_motion.gd) on every peer: tines on the
## leaves, the handle up to both hands. The bool is unused (hotbar:D keeps the
## signature); nothing here reads the local input any more.
static func pose_rake(prop: Node3D, holder: Node3D, _raking: bool = false) -> void:
	var look := prop.get_node_or_null("Visual/Look") as Node3D
	if look == null or str(look.get_meta("kind", "")) != "rake":
		return
	var pose := look.get_node_or_null("Pose") as Node3D
	if pose == null:
		return
	if holder != null:
		prop.set_meta("last_holder", holder.name.to_int())
	RakeMotion.dress(pose, rake_tier(int(prop.get_meta("last_holder", 0))))
	if holder == null:
		RakeMotion.unpublish(pose)
		if pose.top_level:
			pose.top_level = false
			pose.reset_physics_interpolation()
		look.rotation = Vector3.ZERO
		pose.rotation = Vector3(0.0, 0.0, PI * 0.5)
		pose.position = Vector3(0.0, 0.1, 0.0)
		var tines := pose.get_node_or_null("Rake/Tines") as Node3D
		if tines != null:
			tines.rotation = Vector3.ZERO
		return
	if not pose.top_level:
		pose.top_level = true
		pose.reset_physics_interpolation()
	var actor := holder.name.to_int()
	RakeMotion.pose(prop, holder, RakeStroke.display(actor), actor)


## Which rake head a peer's upgrades give it: 0 the starter, 1 the Tune-Up, 2 The
## Leafinator (Campaign RAKE_UPGRADE, RAKE_UPGRADE_2).
## Looked up at run time, so tools that load this script without the autoloads
## (--script checks) still compile it.
static func rake_tier(peer_id: int) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var campaign := tree.root.get_node_or_null("Campaign") if tree != null else null
	if peer_id == 0 or campaign == null:
		return 0
	if bool(campaign.call("peer_has_unlock", peer_id, &"rake_tier_2")):
		return 2
	if bool(campaign.call("peer_has_unlock", peer_id, &"rake_tier_1")):
		return 1
	return 0


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
		_unhold(look)
		look.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -VISUAL_HEIGHT, 0.0))
		if wand != null:
			wand.visible = false
		return
	var head := holder.get_node_or_null("Visual/Head") as Node3D
	if head == null or not is_aimed(prop):
		# Carried, not aimed: a hose that isn't hooked up is held by its reel.
		var entry: Dictionary = HOLDS.get(kind, {})
		if entry.has("at"):
			_place_held(look, holder, entry)
			return
		if look.top_level:
			_unhold(look)
			look.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -VISUAL_HEIGHT, 0.0))
		look.global_rotation = Vector3(0.0, holder.global_rotation.y, 0.0)
		if kind == "pressure_washer" and head != null:
			_pose_wand(prop, holder, head)
		return
	# Placed in world space, so the prop's smoothed Visual can't drag it off the hands.
	look.top_level = true
	look.global_transform = Transform3D(aim_basis(holder, kind == "hose"), head.global_transform * (HANDHELD[kind] as Vector3))


## Held up in front of the face and pointed where the holder looks (HANDHELD), as
## opposed to just carried. A hose is only aimed while it's hooked up.
static func is_aimed(prop: Node3D) -> bool:
	var kind := str(prop.get("kind"))
	return HANDHELD.has(kind) and not (kind == "hose" and str(prop.get("hose_source")) == "")


## The gnome, trash can, TurfMasters sign and wheelbarrow (HOLDS kinds with "at")
## in their holder's hands, from the holder's smoothed Visual, so everyone sees the
## same hold the holder's arms reach for. holder null: back to resting on the prop.
static func pose_held(prop: Node3D, holder: Node3D) -> void:
	var look := prop.get_node_or_null("Visual/Look") as Node3D
	if look == null:
		return
	var entry: Dictionary = HOLDS.get(str(prop.get("kind")), {})
	if holder == null or not entry.has("at"):
		if look.top_level:
			_unhold(look)
			look.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -VISUAL_HEIGHT, 0.0))
		return
	_place_held(look, holder, entry)


## A HOLDS entry's pose in the holder's body space: at, turned by yaw, then
## rolled onto its side by roll (about z) and tipped by tilt (about x), both
## about pivot.
static func hold_transform(entry: Dictionary) -> Transform3D:
	var held := Transform3D(Basis(Vector3.UP, float(entry.get("yaw", 0.0))), entry.get("at", Vector3.ZERO) as Vector3)
	var tilt := float(entry.get("tilt", 0.0))
	var roll := float(entry.get("roll", 0.0))
	if tilt != 0.0 or roll != 0.0:
		var pivot: Vector3 = entry.get("pivot", Vector3.ZERO)
		var turn := Basis(Vector3.RIGHT, tilt) * Basis(Vector3.BACK, roll)
		held = held * Transform3D(Basis.IDENTITY, pivot) * Transform3D(turn, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)
	return held


## The holder's body frame: the smoothed Visual (what everyone sees), level.
static func holder_frame(holder: Node3D) -> Transform3D:
	var visual := holder.get_node_or_null("Visual") as Node3D
	var frame := visual.global_transform if visual != null else holder.global_transform
	var ahead := -frame.basis.z
	ahead = Vector3(ahead.x, 0.0, ahead.z)
	if ahead.length() < 0.001:
		ahead = Vector3.FORWARD
	return Transform3D(Basis.looking_at(ahead.normalized(), Vector3.UP), frame.origin)


static func _place_held(look: Node3D, holder: Node3D, entry: Dictionary) -> void:
	if not look.top_level:
		look.top_level = true
		look.reset_physics_interpolation()
	look.global_transform = holder_frame(holder) * hold_transform(entry)


## Back under the prop's Visual (the caller sets the resting transform).
static func _unhold(look: Node3D) -> void:
	if look.top_level:
		look.top_level = false
		look.reset_physics_interpolation()


## Where the holder's hands go on a held prop, in world space: [right, left],
## Vector3.INF for a hand that's free. Read the same way by the holder's own
## first-person arms (player/first_person_arms.gd) and by everyone's view of the
## holder's body (CartoonBody.set_hold, from player.gd), so the two can't disagree.
## Call it after the prop's look has been posed for this holder.
static func grip_points(prop: Node3D, holder: Node3D) -> Array[Vector3]:
	var free: Array[Vector3] = [Vector3.INF, Vector3.INF]
	if prop == null or holder == null:
		return free
	var kind := str(prop.get("kind"))
	var look := prop.get_node_or_null("Visual/Look") as Node3D
	if look == null:
		return free
	match kind:
		"rake":
			# On the handle where the swing put them (props/rake_motion.gd): the left
			# hand on top, the right one a span further down.
			return RakeMotion.grips(prop, holder)
		"leaf_bag":
			return [look.global_transform * BAG_RIM[0], look.global_transform * BAG_RIM[1]]
		"pressure_washer":
			var wand := prop.get_node_or_null("Wand") as Node3D
			if wand == null or not wand.visible:
				return free
			return [wand.global_transform * WAND_GRIPS[0], wand.global_transform * WAND_GRIPS[1]]
	var grips: Array = []
	if TOOL_GRIPS.has(kind) and is_aimed(prop):
		grips = TOOL_GRIPS[kind]
	elif HOLDS.has(kind):
		grips = (HOLDS[kind] as Dictionary)["grips"]
	else:
		return free
	var points: Array[Vector3] = []
	for grip: Vector3 in grips:
		points.append(look.global_transform * grip if grip.is_finite() else Vector3.INF)
	return points


## Whether a held prop's grips resolve on this peer: at least one hand on it, and
## every hand on it within reach of the holder's shoulder (CartoonBody). What
## net/components/hotbar.gd snapshot reports as grip_ok, so a client proves it sees
## the same hold the host does.
static func grips_ok(prop: Node3D, holder: Node3D) -> bool:
	var points := grip_points(prop, holder)
	var body := holder.get_node_or_null("Visual/CartoonBody") if holder != null else null
	var any := false
	for side: int in points.size():
		if not points[side].is_finite():
			continue
		any = true
		if body != null:
			var shoulder: Vector3 = body.call("shoulder_position", side)
			if shoulder.distance_to(points[side]) > Constants.HOLD_GRIP_REACH:
				return false
	return any


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
	wand.global_transform = Transform3D(aim_basis(holder, false), head.global_transform * Vector3(0.2, -0.12, -0.45))


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


## The rival's lawn sign (net/town/town.gd): a wire stake and a glossy green
## panel with their name on it. Pull it up, throw it somewhere funny.
static func _turf_sign(look: Node3D) -> void:
	var kit := _MeshKit.new()
	for x: float in [-0.22, 0.22]:
		kit.tube(PackedVector3Array([Vector3(x, 0.0, 0.0), Vector3(x, 0.55, 0.0)]), PackedFloat32Array([0.012, 0.012]), Color(0.55, 0.56, 0.58), 5, {"jitter": 0.0})
	kit.rbox(Vector3(0.0, 0.72, 0.0), Vector3(0.32, 0.2, 0.015), Color(0.1, 0.55, 0.28), 8.0, {"shade": false})
	kit.rbox(Vector3(0.0, 0.72, 0.0), Vector3(0.335, 0.215, 0.012), Color(0.97, 0.97, 0.94), 8.0, {"shade": false})
	look.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.35, "specular": 0.45}))
	for side: float in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = _Strings.UI["rival_sign_text"]
		label.font_size = 28
		# Narrow enough to stay on the panel, and one-sided: each face has its own
		# label, so neither shows through mirrored past the edges (now that the sign
		# is held up in front of people, hotbar chunk C).
		label.pixel_size = 0.003
		label.double_sided = false
		label.modulate = Color(1.0, 1.0, 0.95)
		label.outline_size = 0
		label.position = Vector3(0.0, 0.72, 0.03 * side)
		label.rotation.y = 0.0 if side > 0.0 else PI
		look.add_child(label)


static func _gnome(look: Node3D) -> void:
	look.add_child(_YardModels.node("gnome"))


static func _leaf_bag(look: Node3D) -> void:
	look.add_child(_YardModels.node("leaf_bag"))


## The job's one rake, built standing with its head at the Pose origin, with the
## tier's head (props/yard_models.gd rake: wider, more tines, starter green,
## Tune-Up orange, Leafinator chrome). pose_rake rebuilds it only when the tier changes.
static func _rake(look: Node3D, tier: int = 0) -> void:
	var pose := Node3D.new()
	pose.name = "Pose"
	look.add_child(pose)
	RakeMotion.dress(pose, tier)
