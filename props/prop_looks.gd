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
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _ShopModels = preload("res://props/shop_models.gd")
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
## Pocketed things worn on the body (hotbar chunk D; docs/GAME.md "the hotbar").
## Per kind: the CartoonBody part that carries it (pose_part: "torso" rides the
## lean, the twist and the walk's bob; "hips" the stride), where the model's
## origin sits in that part's space (x right, y up, -z ahead; both origins are at
## the hips, the shirt's back is at z +0.16 and the shoulders 0.46 up the torso),
## its turn (euler, radians) and its size. The rake is slung across the back with
## its tines up over the right shoulder; the blower is worn like a backpack,
## nozzle down; the trimmer hangs on the right hip, blade down; the roller sticks
## out of the left back pocket; the hose is coiled on the left shoulder blade;
## signs are stuck down the back of the pants, fanned out (fan: roll per sign
## from the middle of the stack, spread: sideways per sign). A kind missing here
## hangs at the left hip (STOWED_OTHER).
const STOWED: Dictionary = {
	"rake": {"part": "torso", "at": Vector3(0.24, 0.72, 0.23), "euler": Vector3(0.0, 0.0, 2.62), "scale": 0.8},
	"leaf_blower": {"part": "torso", "at": Vector3(0.02, 0.36, 0.3), "euler": Vector3(-PI * 0.5, 0.0, 0.0), "scale": 0.8},
	"hedge_trimmer": {"part": "hips", "at": Vector3(0.27, 0.06, 0.0), "euler": Vector3(-PI * 0.5, 0.0, 0.0), "scale": 0.85},
	"paint_roller": {"part": "hips", "at": Vector3(-0.09, 0.16, 0.19), "euler": Vector3(PI * 0.5, 0.0, 0.25), "scale": 0.9},
	"hose": {"part": "torso", "at": Vector3(-0.12, 0.12, 0.26), "euler": Vector3(0.0, PI * 0.5, 0.0), "scale": 0.7},
	"turf_sign": {"part": "hips", "at": Vector3(0.0, -0.14, 0.09), "euler": Vector3(0.22, 0.0, 0.0), "scale": 0.75, "fan": 0.22, "spread": 0.05},
	"gas_can": {"part": "hips", "at": Vector3(-0.29, -0.3, 0.0), "euler": Vector3(0.0, PI * 0.5, 0.0), "scale": 0.8},
}
const STOWED_OTHER: Dictionary = {"part": "hips", "at": Vector3(-0.28, -0.2, 0.02), "euler": Vector3.ZERO, "scale": 0.7}


static func dress(prop: Node3D, kind: String, color: Color) -> void:
	var visual := prop.get_node_or_null("Visual") as MeshInstance3D
	if visual == null:
		return
	# Rebuild only when the kind or a tool's tier changes (either can arrive after
	# the prop is ready). A tier dresses the tool: chrome for Mk II, black and gold
	# for Mk III, rust and tape for a used one (props/yard_models.gd tier trim).
	var tier := int(prop.get("tier")) if "tier" in prop else 1
	# Junk wears its type, which is its label (shops chunk 5), and may arrive after the kind.
	var junk_type := str(prop.get("label")) if kind == "junk" else ""
	var old := visual.get_node_or_null("Look")
	if old != null:
		if str(old.get_meta("kind", "")) == kind and int(old.get_meta("tier", 1)) == tier and str(old.get_meta("junk", "")) == junk_type:
			return
		old.free()
	var look := Node3D.new()
	look.set_meta("kind", kind)
	look.set_meta("tier", tier)
	look.set_meta("junk", junk_type)
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
		"junk":
			# Rusty's junk (props/shop_models.gd); the collision box fits each type.
			if _ShopModels.is_junk(junk_type):
				look.add_child(_ShopModels.junk(junk_type))
				_fit_junk_box(prop, junk_type)
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
	# Every prop sounds like itself when handled: picked up, set up, knocked over.
	if prop.get_node_or_null("PropFoley") == null:
		var foley: Node = load("res://audio/prop_foley.gd").new()
		foley.name = "PropFoley"
		foley.set("prop", prop)
		prop.add_child(foley)


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
	# p2-kit: the head is the rake's own (its tier), whoever holds it.
	RakeMotion.dress(pose, rake_head(int(prop.get("tier"))))
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
		_note_rest(prop, pose)
		return
	var actor := holder.name.to_int()
	var progress := _blend_begin(prop, "hand:%d" % actor, holder)
	if not pose.top_level:
		pose.top_level = true
		pose.reset_physics_interpolation()
	# Drawn: the head comes off the back lifted and plants on the leaves (a
	# negative dip lifts it; props/rake_motion.gd), the hands on the handle all the way.
	# Riding in Chefty's bed (or sitting), the tines rest on the floor under the
	# holder's feet, not on the street a metre below, where they were drawn inside
	# the truck (hotbar:E review: a bot's rake vanished from boarding to racking,
	# rec_honk6_3p frames 74-83), and they rake nothing.
	var riding := _riding(holder)
	RakeMotion.pose(prop, holder, RakeStroke.display(actor), actor, -draw_dip(prop), holder_frame(holder).origin.y if riding else NAN)
	if riding:
		RakeMotion.unpublish(pose)
	var target := pose.global_transform
	if progress < 1.0:
		_carry_grips(pose, _blend_put(prop, pose, target, holder) * target.affine_inverse())
	else:
		prop.set_meta("pose_last", target)


## Whether a holder is on a seat: in Chefty's bed (the ride or its honk-and-wait,
## where the body keeps standing), a drivable vehicle's seat (a sit pose), or staged.
static func _riding(holder: Node3D) -> bool:
	if holder.has_method("is_riding_visual") and bool(holder.call("is_riding_visual")):
		return true
	var body := holder.get_node_or_null("Visual/CartoonBody")
	return body != null and int(body.get("_sit_pose")) != 0


## Which rake head a rake of this tier has (p2-kit: the tier is the rake's, not
## its holder's upgrades): 0 the plain head (used and stock), 1 the Mk II's, 2
## The Leafinator's (Constants.KIT_RAKE_HEAD_BY_TIER, RAKE_HEAD_WIDTHS).
static func rake_head(tier: int) -> int:
	var heads := Constants.KIT_RAKE_HEAD_BY_TIER
	return heads[clampi(tier, 0, heads.size() - 1)]


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
	# Taken down, it comes off the wall into the hands from here.
	prop.set_meta("pose_mode", "rest")
	prop.set_meta("pose_last", look.global_transform)


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
		_note_rest(prop, look)
		return
	var head := holder.get_node_or_null("Visual/Head") as Node3D
	if head == null or not is_aimed(prop):
		# Carried, not aimed: a hose that isn't hooked up is held by its reel.
		var entry: Dictionary = HOLDS.get(kind, {})
		if entry.has("at"):
			_place_held(prop, look, holder, entry)
			return
		if look.top_level:
			_unhold(look)
			look.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -VISUAL_HEIGHT, 0.0))
		look.global_rotation = Vector3(0.0, holder.global_rotation.y, 0.0)
		if kind == "pressure_washer" and head != null:
			_pose_wand(prop, holder, head)
		prop.set_meta("pose_mode", "carry:%s" % holder.name)
		prop.set_meta("pose_last", look.global_transform)
		return
	# Placed in world space, so the prop's smoothed Visual can't drag it off the
	# hands; drawn, it glides there from wherever it was (_blend_put).
	_blend_begin(prop, "hand:%s" % holder.name, holder)
	_blend_put(prop, look, Transform3D(aim_basis(holder, kind == "hose"), head.global_transform * (HANDHELD[kind] as Vector3)), holder)


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
	var entry := hold_of(prop)
	if holder == null or not entry.has("at"):
		var rest := Transform3D(Basis.IDENTITY, Vector3(0.0, -VISUAL_HEIGHT, 0.0))
		if look.top_level:
			var from := look.global_transform
			_unhold(look)
			look.transform = rest
			# Junk is set down, not teleported: its look eases from your arms to
			# where the body landed (shops chunk 5; a toilet popping onto the
			# scale in one frame read as a glitch).
			if str(prop.get("kind")) == "junk":
				look.set_meta("ease_from", from)
				look.set_meta("ease_left", Constants.JUNK_SET_DOWN_SECONDS)
		if look.has_meta("ease_left"):
			var left := float(look.get_meta("ease_left")) - prop.get_physics_process_delta_time()
			var target := (look.get_parent() as Node3D).global_transform * rest
			if left <= 0.0:
				look.remove_meta("ease_left")
				look.remove_meta("ease_from")
				look.transform = rest
			else:
				look.set_meta("ease_left", left)
				var share := smoothstep(0.0, 1.0, 1.0 - left / Constants.JUNK_SET_DOWN_SECONDS)
				look.global_transform = (look.get_meta("ease_from") as Transform3D).interpolate_with(target, share)
		if holder == null:
			_note_rest(prop, look)
		return
	if look.has_meta("ease_left"):
		look.remove_meta("ease_left")
		look.remove_meta("ease_from")
	_place_held(prop, look, holder, entry)


## How a prop is held: its HOLDS entry, or for junk its type's
## (props/shop_models.gd JUNK_HOLDS: a toilet isn't carried like a flamingo).
## {} for a kind with no hold.
static func hold_of(prop: Node) -> Dictionary:
	var kind := str(prop.get("kind"))
	if kind == "junk":
		return _ShopModels.JUNK_HOLDS.get(str(prop.get("label")), {}) as Dictionary
	return HOLDS.get(kind, {}) as Dictionary


## A junk prop's collision box fits its type (props/shop_models.gd JUNK_BOX),
## its base on the ground at the prop's origin like the model's. Its own shape,
## so the scene's shared one is left alone.
static func _fit_junk_box(prop: Node3D, junk_type: String) -> void:
	var collision := prop.get_node_or_null("Collision") as CollisionShape3D
	if collision == null:
		return
	var size: Vector3 = _ShopModels.JUNK_BOX[junk_type]
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position = Vector3(0.0, size.y * 0.5, 0.0)


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


static func _place_held(prop: Node3D, look: Node3D, holder: Node3D, entry: Dictionary) -> void:
	_blend_begin(prop, "hand:%s" % holder.name, holder)
	_blend_put(prop, look, holder_frame(holder) * hold_transform(entry), holder)


## Back under the prop's Visual (the caller sets the resting transform).
static func _unhold(look: Node3D) -> void:
	if look.top_level:
		look.top_level = false
		look.reset_physics_interpolation()


# ---------------------------------------------------------------- stowed looks and the draw (hotbar chunk D)

## The node that's posed: the rake's Pose (its model hangs off it), else the Look.
static func posed_node(prop: Node3D) -> Node3D:
	if str(prop.get("kind")) == "rake":
		return prop.get_node_or_null("Visual/Look/Pose") as Node3D
	return prop.get_node_or_null("Visual/Look") as Node3D


## A pocketed prop worn on its holder's body (STOWED), every peer, from the
## holder's animated CartoonBody, so it bobs, leans and strides with them. own:
## it's this peer's player, so it goes on CartoonBody.HEAD_LAYER, which their
## first-person camera skips (it would sit in their face); every other camera sees
## it. Hidden with the body: in a hiding spot or a pile, asleep, sitting in a
## seat, or not drawn at all (player.is_body_drawn). Going in, it travels from the
## hands to its spot (_blend_put); through your own eyes it leaves the view (out
## of the bottom, or the rake out past the right edge) instead of swinging
## through your head.
static func pose_stowed(prop: Node3D, holder: Node3D, own: bool) -> void:
	var look := prop.get_node_or_null("Visual/Look") as Node3D
	var node := posed_node(prop)
	if look == null or node == null:
		return
	if str(prop.get("kind")) == "rake":
		RakeMotion.unpublish(node)
	var shown := holder != null and stowed_shown(holder)
	look.visible = shown
	if holder == null:
		return
	var mode := "stowed:%s" % holder.name
	if str(prop.get_meta("pose_mode", "")).begins_with("hand") and str(prop.get_meta("pose_mode", "")) != mode:
		# Just put away: the hands' spots on it as it was in hand (its look hasn't
		# moved yet), in its own space, so they ride along while it goes.
		var local: Array = []
		var kind := str(prop.get("kind"))
		var grips: Array[Vector3] = [Vector3.INF, Vector3.INF]
		if kind != "rake":
			grips = _hand_grips(prop, look, kind)
		for grip: Vector3 in grips:
			local.append(node.global_transform.affine_inverse() * grip if grip.is_finite() else Vector3.INF)
		prop.set_meta("stow_grips", local)
	var progress := _blend_begin(prop, mode, holder)
	var target := stowed_transform(prop, holder)
	var fp := own and _first_person(holder)
	var going := progress < 1.0 and str(prop.get_meta("blend_was", "")).begins_with("hand")
	var rake_from := Transform3D.IDENTITY
	var live_rake := going and str(prop.get("kind")) == "rake"
	if going:
		var from := _blend_from(prop, holder)
		if live_rake:
			# The rake comes up off the leaves before it goes over the shoulder: the
			# swing's own pose, lifted more and more (RakeMotion's draw_dip), with
			# the hands on its handle the whole way.
			var actor := holder.name.to_int()
			RakeMotion.pose(prop, holder, RakeStroke.display(actor), actor, -Constants.HOTBAR_RAKE_DRAW_LIFT * sin(progress * PI * 0.5))
			RakeMotion.unpublish(node)
			from = node.global_transform
			rake_from = from
			_set_blend_from(prop, from, holder)
		if fp:
			# Through your own eyes: out of the view, then a cut onto your back (below).
			# A small tool drops toward the hip; the rake keeps its angle and lifts off
			# the leaves out past the right edge (its way to your back as everyone sees
			# it would swing the handle up through the middle of the view).
			var away := Constants.HOTBAR_FP_RAKE_STOW_TO if live_rake else Constants.HOTBAR_FP_DRAW_FROM
			target = Transform3D(from.basis, from.origin + holder_frame(holder).basis * away)
	var hid := _own_layers(look, own and not (fp and going))
	var put := _blend_put(prop, node, target, holder)
	if hid and fp:
		# Off your screen at the hip, onto your back: a cut, never a sweep through the view.
		node.reset_physics_interpolation()
	if live_rake:
		_carry_grips(node, put * rake_from.affine_inverse())


## Whether a holder's stowed things show: their body is drawn and they aren't
## hiding, asleep or sitting.
static func stowed_shown(holder: Node3D) -> bool:
	if not holder.is_visible_in_tree():
		return false
	if holder.has_method("is_body_drawn") and not bool(holder.call("is_body_drawn")):
		return false
	if holder.has_method("is_hidden") and bool(holder.call("is_hidden")):
		return false
	if holder.has_method("is_sleeping") and bool(holder.call("is_sleeping")):
		return false
	var body := holder.get_node_or_null("Visual/CartoonBody") as Node3D
	if body == null or not body.is_visible_in_tree():
		return false
	return int(body.get("_sit_pose")) == 0


## Where a pocketed prop sits on its holder's body, world space (STOWED).
static func stowed_transform(prop: Node3D, holder: Node3D) -> Transform3D:
	var entry: Dictionary = STOWED.get(str(prop.get("kind")), STOWED_OTHER)
	var body := holder.get_node_or_null("Visual/CartoonBody")
	var part: Node3D = body.call("pose_part", str(entry["part"])) if body != null else null
	var frame := part.global_transform if part != null else holder_frame(holder) * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.82, 0.0))
	var at: Vector3 = entry["at"]
	var euler: Vector3 = entry["euler"]
	if entry.has("fan"):
		var place := stack_place(prop)
		var fan := _fan_shown(prop, Vector2(float(place.x) - float(place.y - 1) * 0.5, float(place.x)))
		euler.z += float(entry["fan"]) * fan.x
		at.x += float(entry["spread"]) * fan.x
		# Each one a little further out, so the fan doesn't z-fight.
		at.z += 0.012 * fan.y
	return frame * Transform3D(Basis.from_euler(euler).scaled(Vector3.ONE * float(entry["scale"])), at)


## A stacked thing's place in its fan as shown, (offset from the middle, index):
## eased toward where the stack puts it now (HOTBAR_FAN_SETTLE), so the rest
## shuffle over when one is drawn or thrown instead of snapping. Straight there
## when it wasn't worn a moment ago (it glides in on its own).
static func _fan_shown(prop: Node3D, aim: Vector2) -> Vector2:
	var now := Time.get_ticks_msec()
	var last := int(prop.get_meta("fan_msec", -100000))
	prop.set_meta("fan_msec", now)
	var shown := aim
	if now - last <= 250 and prop.has_meta("fan_shown"):
		var was: Vector2 = prop.get_meta("fan_shown")
		shown = was.lerp(aim, 1.0 - exp(-float(now - last) / 1000.0 * Constants.HOTBAR_FAN_SETTLE))
	prop.set_meta("fan_shown", shown)
	return shown


## A pocketed prop's place in its stack and the stack's size, as (index, count):
## the props in the same slot of the same pocket, by name (Hotbar.slots_of's order).
static func stack_place(prop: Node3D) -> Vector2i:
	var owner_id := int(prop.get("pocketed_by"))
	var slot := int(prop.get("pocket_slot"))
	var names: Array[String] = []
	for node: Node in prop.get_tree().get_nodes_in_group("props"):
		if int(node.get("pocketed_by")) == owner_id and int(node.get("pocket_slot")) == slot and str(node.get("kind")) == str(prop.get("kind")) and not node.is_queued_for_deletion():
			names.append(str(node.name))
	names.sort()
	return Vector2i(maxi(0, names.find(str(prop.name))), maxi(1, names.size()))


## Out of a pocket (net_prop's pocketed_by setter, every peer): back on the
## normal layers and shown. The next pose puts it in hand or on the ground.
static func unstow(prop: Node3D) -> void:
	var look := prop.get_node_or_null("Visual/Look") as Node3D
	if look == null:
		return
	_own_layers(look, false)
	look.visible = true


## How far (m) a just-drawn rake's head still rides above where the swing puts
## it: HOTBAR_RAKE_DRAW_LIFT at the draw, easing to nothing over
## HOTBAR_DRAW_SECONDS from the drawn_msec stamp (net_prop's held_by setter). Only
## for a draw out of a pocket; 0 otherwise. pose_rake passes it to RakeMotion as
## a negative dip (a lift).
static func draw_dip(prop: Node3D) -> float:
	if not prop.has_meta("drawn_msec") or not bool(prop.get_meta("drawn_from_pocket", false)):
		return 0.0
	var t := float(Time.get_ticks_msec() - int(prop.get_meta("drawn_msec"))) / 1000.0 / Constants.HOTBAR_DRAW_SECONDS
	if t >= 1.0 or t < 0.0:
		return 0.0
	return Constants.HOTBAR_RAKE_DRAW_LIFT * (1.0 - _ease_out(t))


## Going into a pocket right now (every peer): pocketed out of someone's hands
## within the last HOTBAR_STOW_SECONDS. The hands stay on it till it's put away.
static func is_stowing(prop: Node) -> bool:
	if prop == null or not is_instance_valid(prop) or int(prop.get("pocketed_by")) == 0:
		return false
	if not bool(prop.get_meta("stowed_from_hand", false)):
		return false
	return Time.get_ticks_msec() - int(prop.get_meta("stowed_msec", -100000)) < int(Constants.HOTBAR_STOW_SECONDS * 1000.0)


## Being drawn right now: out of a pocket into the hands within the last
## HOTBAR_DRAW_SECONDS.
static func is_drawing(prop: Node) -> bool:
	if prop == null or not is_instance_valid(prop) or int(prop.get("held_by")) == 0 or not bool(prop.get_meta("drawn_from_pocket", false)):
		return false
	return Time.get_ticks_msec() - int(prop.get_meta("drawn_msec", -100000)) < int(Constants.HOTBAR_DRAW_SECONDS * 1000.0)


static func _first_person(holder: Node3D) -> bool:
	var eyes := holder.get_node_or_null("Visual/Head/FirstPerson") as Camera3D
	return eyes != null and eyes.current


## Starts a glide when what's posing the prop changes (mode: "hand:<peer>",
## "stowed:<peer>", "rest"), from wherever it was drawn last (meta pose_last), and
## returns how far along the current glide is, 0 to 1 (1: none). The clock starts
## at the replicated change's stamp (drawn_msec / stowed_msec) when it's fresh, so a
## late pose doesn't lengthen it.
static func _blend_begin(prop: Node3D, mode: String, holder: Node3D = null) -> float:
	var was := str(prop.get_meta("pose_mode", ""))
	if was != mode:
		prop.set_meta("pose_mode", mode)
		prop.set_meta("blend_was", was)
		var now := Time.get_ticks_msec()
		var stowing := mode.begins_with("stowed")
		var stamp := int(prop.get_meta("stowed_msec" if stowing else "drawn_msec", -100000))
		var start := stamp if now - stamp >= 0 and now - stamp < Constants.HOTBAR_STAMP_FRESH_MS else now
		var glide := was != "" and prop.has_meta("pose_last") and (stowing or mode.begins_with("hand") or was.begins_with("stowed"))
		prop.set_meta("blend_msec", start if glide else -100000)
		prop.set_meta("blend_secs", Constants.HOTBAR_STOW_SECONDS if stowing or mode == "rest" else Constants.HOTBAR_DRAW_SECONDS)
		if glide:
			# Off someone's body it moves with them; off the ground it starts where it lay.
			var on_body := was.begins_with("hand") or was.begins_with("stowed") or was.begins_with("carry")
			_set_blend_from(prop, prop.get_meta("pose_last"), holder if on_body else null)
			prop.set_meta("blend_fp_from", mode.begins_with("hand") and was.begins_with("stowed"))
	return _blend_progress(prop)


## Where the current glide started. Kept in the holder's body frame when there
## is a holder, so it walks along with them (a glide that started where they
## stood would trail behind someone walking).
static func _set_blend_from(prop: Node3D, world: Transform3D, holder: Node3D) -> void:
	prop.set_meta("blend_from", holder_frame(holder).affine_inverse() * world if holder != null else world)
	prop.set_meta("blend_from_body", holder != null)


static func _blend_from(prop: Node3D, holder: Node3D) -> Transform3D:
	var from: Transform3D = prop.get_meta("blend_from", Transform3D.IDENTITY)
	if bool(prop.get_meta("blend_from_body", false)):
		return holder_frame(holder) * from if holder != null else from
	return from


static func _blend_progress(prop: Node3D) -> float:
	var seconds := maxf(float(prop.get_meta("blend_secs", Constants.HOTBAR_DRAW_SECONDS)), 0.001)
	return clampf(float(Time.get_ticks_msec() - int(prop.get_meta("blend_msec", -100000))) / 1000.0 / seconds, 0.0, 1.0)


## Puts the posed node at target in world space, part way along the current glide
## from blend_from: eased (a draw is quick off the mark and settles; going away
## eases in and out), bowed out from the holder's middle and up a little so it
## travels round the body, not through it. A draw out of your own pocket seen
## through your own eyes comes up from below the view at the hip (it was on your
## back, behind the camera). Returns the transform it got.
static func _blend_put(prop: Node3D, node: Node3D, target: Transform3D, holder: Node3D) -> Transform3D:
	if not node.top_level:
		node.top_level = true
		node.reset_physics_interpolation()
	var t := _blend_progress(prop)
	var put := target
	var cut := false
	if t < 1.0 and prop.has_meta("blend_from"):
		if bool(prop.get_meta("blend_fp_from", false)):
			prop.set_meta("blend_fp_from", false)
			if holder != null and holder.is_multiplayer_authority() and _first_person(holder) and str(prop.get("kind")) != "rake":
				_set_blend_from(prop, Transform3D(target.basis, target.origin + holder_frame(holder).basis * Constants.HOTBAR_FP_DRAW_FROM), holder)
				# From your back (never on your screen) to your hip: a cut, not a
				# sweep through the camera between two ticks.
				cut = true
		var from := _blend_from(prop, holder)
		var going := str(prop.get_meta("pose_mode", "")).begins_with("stowed")
		# Off at once either way (a key press gets an answer the same frame);
		# a draw settles into the hands, a stow a little more briskly onto the body.
		var s := 1.0 - (1.0 - t) * (1.0 - t) if going else _ease_out(t)
		put = from.interpolate_with(target, s)
		if holder != null:
			var out := put.origin - holder.global_position
			out.y = 0.0
			# Bowed along the travel (its eased share), so it never swings back out
			# after it's nearly there.
			var bow := sin(s * PI)
			var arc := Constants.HOTBAR_DRAW_ARC
			var rise := Constants.HOTBAR_DRAW_RISE
			if str(prop.get("kind")) == "rake" and holder.is_multiplayer_authority() and _first_person(holder):
				# Your own rake: drawn round your right side low and wide, never across
				# your face; put away straight out past the right edge (pose_stowed's
				# target), no bow to pull it back into view.
				arc = 0.0 if going else Constants.HOTBAR_FP_RAKE_ARC
				rise = 0.0 if going else -Constants.HOTBAR_FP_RAKE_DROP
			if out.length() > 0.01:
				put.origin += out.normalized() * arc * bow
			put.origin += Vector3.UP * rise * bow
	node.global_transform = put
	if cut:
		node.reset_physics_interpolation()
	prop.set_meta("pose_last", put)
	return put


## A prop at rest (on the ground, or a set-up ladder): remembered as drawn, and,
## coming straight out of a pocket (emptied pockets), gliding from the body to
## where it lies instead of popping there. The caller has set the resting pose.
static func _note_rest(prop: Node3D, node: Node3D) -> void:
	var progress := _blend_begin(prop, "rest")
	if progress < 1.0 and str(prop.get_meta("blend_was", "")).begins_with("stowed"):
		_blend_put(prop, node, node.global_transform, null)
		return
	prop.set_meta("pose_last", node.global_transform)


## The rake's hand spots (Pose metas from RakeMotion) moved with its pose by fix,
## so the hands stay on the handle while it glides.
static func _carry_grips(pose: Node3D, fix: Transform3D) -> void:
	for key: String in ["grip_right", "grip_left"]:
		if pose.has_meta(key):
			pose.set_meta(key, fix * (pose.get_meta(key) as Vector3))


static func _ease_out(t: float) -> float:
	var left := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - left * left * left


## Every drawn part of a stowed look on this peer's HEAD_LAYER (own) or back on
## the layers it was built with. Re-checked each tick: a hose's nozzle is added
## later. True when it just went onto the head layer.
static func _own_layers(look: Node3D, own: bool) -> bool:
	var count := look.get_child_count()
	var was := bool(look.get_meta("own_layers", false))
	if was == own and int(look.get_meta("own_layers_children", -1)) == count:
		return false
	look.set_meta("own_layers", own)
	look.set_meta("own_layers_children", count)
	var head_layer := 1 << (_CartoonBody.HEAD_LAYER - 1)
	for found: Node in look.find_children("*", "VisualInstance3D", true, false):
		var part := found as VisualInstance3D
		if not part.has_meta("built_layers"):
			part.set_meta("built_layers", part.layers)
		part.layers = head_layer if own else int(part.get_meta("built_layers"))
	return own and not was


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
	if int(prop.get("pocketed_by")) != 0:
		# Being put away, the hands go with it (the grips it had in hand, carried
		# along with its glide); once it's away, they're free.
		if not is_stowing(prop):
			return free
		if kind == "rake":
			return RakeMotion.grips(prop, holder)
		var node := posed_node(prop)
		var local: Array = prop.get_meta("stow_grips", [])
		if node == null or local.size() != 2:
			return free
		var carried: Array[Vector3] = []
		for grip: Vector3 in local:
			carried.append(node.global_transform * grip if grip.is_finite() else Vector3.INF)
		return carried
	return _hand_grips(prop, look, kind)


## grip_points for a prop in hand, its look already posed.
static func _hand_grips(prop: Node3D, look: Node3D, kind: String) -> Array[Vector3]:
	var free: Array[Vector3] = [Vector3.INF, Vector3.INF]
	match kind:
		"rake":
			# On the handle where the swing put them (props/rake_motion.gd): the left
			# hand on top, the right one a span further down.
			return RakeMotion.grips(prop)
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
	elif not hold_of(prop).is_empty():
		grips = hold_of(prop)["grips"]
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
