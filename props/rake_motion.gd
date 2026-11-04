class_name RakeMotion
extends RefCounted

## Authority: local, cosmetic. Puts a rake where a swing sample says
## (equipment/rake_stroke.gd): the tines ride on the litter (a "leaf_view" node's
## surface_y when there is one, else the holder's ground), facing ahead and kinked
## toe-down for the push, the fan flexing under the load, and the handle running up
## to the holder's two hands. Every peer poses every rake the same way, from the
## same sample, so a crewmate's rake swings in time with their leaves.
##
## The posed rake's Pose node publishes the head for the leaf movers (contract C4,
## group "rake_heads"): metas actor, head_a, head_b (world tine ends), head_vel
## (m/s), drive_dir, phase, down, half_width; and the two grips for grips().

const _YardModels = preload("res://props/yard_models.gd")
## Tines sit this far above the surface they ride (m), so they read on the leaves.
const SURFACE_GAP: float = 0.02
## How far the hands can be from the shoulders before the lower hand slides up.
const HAND_REACH: float = Constants.RAKE_HAND_REACH
## The handle's top, from the head (yard_models.gd _rake: the grip ends at 1.62).
const HANDLE_TOP: float = 1.6


## Where the head goes through your own eyes for a sample's head_forward: the
## same drive, planted at RAKE_FP_NEAR instead of RAKE_HEAD_NEAR (and a little
## further out at the far end), so the tines clear the hotbar.
static func fp_reach(reach: float) -> float:
	var far := Constants.RAKE_HEAD_FAR + Constants.RAKE_FP_FAR_EXTRA
	return remap(reach, Constants.RAKE_HEAD_NEAR, Constants.RAKE_HEAD_FAR, Constants.RAKE_FP_NEAR, far)


## Poses a held rake prop (props/prop_looks.gd pose_rake): its Visual/Look/Pose,
## in world space. draw_dip is reserved for hotbar:D's stow and draw (added to the
## lift, m). floor_y: the height the tines rest on instead of the leaves (NAN: the
## leaves), for a holder riding in Chefty's bed (prop_looks.pose_rake).
static func pose(prop: Node3D, holder: Node3D, sample: Dictionary, actor: int, draw_dip: float = 0.0, floor_y: float = NAN) -> void:
	var look := prop.get_node_or_null("Visual/Look") as Node3D
	if look == null:
		return
	var pose_node := look.get_node_or_null("Pose") as Node3D
	if pose_node == null or holder == null:
		return
	var frame: Transform3D = load("res://props/prop_looks.gd").holder_frame(holder)
	var eyes := holder.get_node_or_null("Visual/Head/FirstPerson") as Camera3D
	if eyes != null and eyes.current and holder.has_node("Visual/Head/Arms"):
		# Your own rake, seen through your own eyes with your first-person arms.
		pose_frame(pose_node, frame, sample, actor, draw_dip, [], true, floor_y)
		return
	pose_frame(pose_node, frame, sample, actor, draw_dip, shoulders_of(holder.get_node_or_null("Visual/CartoonBody")), false, floor_y)


## A cartoon body's shoulders [right, left] in world space, or [] without one.
static func shoulders_of(body: Node) -> Array:
	if body == null or not body.has_method("shoulder_position"):
		return []
	return [body.call("shoulder_position", 0), body.call("shoulder_position", 1)]


## Poses a rake's Pose node for a holder whose body frame (feet, -Z ahead, level)
## is frame. Hired hands call this with their own frame. shoulders: the holder's
## body's [right, left] shoulders (last tick's), else they're estimated from the sample.
static func pose_frame(pose_node: Node3D, frame: Transform3D, sample: Dictionary, actor: int, draw_dip: float = 0.0, shoulders: Array = [], first_person: bool = false, floor_y: float = NAN) -> void:
	var forward := -frame.basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var reach := float(sample.get("head_forward", Constants.RAKE_HEAD_NEAR))
	var extend := clampf(inverse_lerp(Constants.RAKE_HEAD_NEAR, Constants.RAKE_HEAD_FAR, reach), 0.0, 1.0)
	if first_person:
		# Through your own eyes the plant would be under your feet, behind the
		# hotbar: the same drive, planted further out where you can see the tines.
		reach = fp_reach(reach)
	var lateral := clampf(float(sample.get("head_lateral", 0.0)), -Constants.RAKE_HEAD_LATERAL, Constants.RAKE_HEAD_LATERAL)
	var contact := frame.origin + forward * reach + right * lateral
	var ground := floor_y if not is_nan(floor_y) else surface_y(pose_node, contact, frame.origin.y)
	contact.y = ground + SURFACE_GAP + float(sample.get("head_lift", 0.0)) - draw_dip
	var heading := forward.rotated(Vector3.UP, -float(sample.get("head_yaw", 0.0)))
	var across := heading.cross(Vector3.UP).normalized()
	# The body's hips move with the wind-up and the lunge (sample hip, + is back)
	# and sink into the knees (crouch); in first person the camera stays put, so
	# the hands do too.
	var hip := 0.0 if first_person else float(sample.get("hip", 0.0))
	var crouch := 0.0 if first_person else float(sample.get("crouch", 0.0))
	var lean := float(sample.get("lean", 0.0))
	var torso := Vector3.UP * cos(lean) + forward * -sin(lean)
	var hips := frame.origin + Vector3.UP * (0.82 - crouch) - forward * hip
	var twist := float(sample.get("twist", 0.0))
	var shoulder_r := hips + (right * 0.25 + torso * 0.46).rotated(Vector3.UP, twist)
	var shoulder_l := hips + (-right * 0.25 + torso * 0.46).rotated(Vector3.UP, twist)
	if shoulders.size() == 2:
		shoulder_r = shoulders[0]
		shoulder_l = shoulders[1]
	# The upper hand's spot, from the shoulders: up at the chest with the head
	# close in, down at the belly and out at full stretch (the body leans into it).
	var grip_local := Constants.RAKE_GRIP_NEAR.lerp(Constants.RAKE_GRIP_FAR, smoothstep(0.0, 1.0, extend))
	var chest := (shoulder_r + shoulder_l) * 0.5
	var anchor := chest + right * grip_local.x + Vector3.UP * grip_local.y - forward * grip_local.z
	if first_person:
		# The handle aims past your right shoulder: in close its top is just out of
		# view bottom right, and the drive brings it (and your hands) into view.
		var hand_local := Constants.RAKE_FP_HANDLE_AIM
		anchor = frame.origin + right * hand_local.x + Vector3.UP * hand_local.y + forward * -hand_local.z
	# The tines' kink at the head bar.
	var tines := pose_node.get_node_or_null("Rake/Tines") as Node3D
	var kink := float(sample.get("toe_down", Constants.RAKE_HEAD_TOE_DOWN)) + float(sample.get("tine_flex", 0.0))
	var tip_local := _YardModels.RAKE_TINES_PIVOT + Basis(Vector3.RIGHT, kink) * _YardModels.RAKE_TINE_TIP
	# The head (the Pose origin, at the collar) sits where that tip lands on contact,
	# with the handle aimed at the hands: two passes settle it.
	var head := contact + Vector3.UP * 0.3 - heading * 0.1
	var basis := Basis.IDENTITY
	for _pass: int in 3:
		basis = _handle_basis(anchor - head, heading)
		head = contact - basis * tip_local
	pose_node.top_level = true
	pose_node.global_transform = Transform3D(basis, head)
	if tines != null:
		tines.rotation = Vector3(kink, 0.0, 0.0)
	# The hands: the upper (left) one where the handle passes the anchor, sliding up
	# the handle as the drive stretches out; the lower (right) one a span below it,
	# the span shrinking to RAKE_HAND_SPAN_MIN when the right arm can't reach. Where
	# even that is too far, both slide along the handle to share the stretch.
	var lowest := HANDLE_TOP - Constants.RAKE_HAND_SLIDE_MAX
	var along := clampf((anchor - head).dot(basis.y), lowest, HANDLE_TOP - 0.05)
	along = minf(along + Constants.RAKE_HANDLE_SLIDE * extend, HANDLE_TOP - 0.05)
	var span := Constants.RAKE_HAND_SPAN
	while span > Constants.RAKE_HAND_SPAN_MIN and (head + basis.y * (along - span)).distance_to(shoulder_r) > HAND_REACH:
		span -= 0.01
	var best := along
	var worst := INF
	for step: int in 13:
		var try_along := clampf(along + (float(step) - 6.0) * 0.03, lowest, HANDLE_TOP - 0.05)
		var miss := maxf((head + basis.y * try_along).distance_to(shoulder_l), (head + basis.y * (try_along - span)).distance_to(shoulder_r))
		# The anchor is where the look wants the hand: only move off it to reach.
		miss = maxf(miss, HAND_REACH) + absf(try_along - along) * 0.2
		if miss < worst:
			worst = miss
			best = try_along
	along = best
	if first_person:
		# From your own eyes: both hands up at the top, the left one capping it.
		along = HANDLE_TOP - 0.04
		span = Constants.RAKE_HAND_SPAN_FP
	var upper := head + basis.y * along
	var lower := head + basis.y * (along - span)
	var tier := clampi(int(pose_node.get_meta("tier", 0)), 0, Constants.RAKE_HEAD_WIDTHS.size() - 1)
	var half_width := Constants.RAKE_HEAD_WIDTHS[tier] * 0.5
	var down := bool(sample.get("down", false))
	# The head for the leaf movers (contract C4).
	var now := Time.get_ticks_usec()
	var last_at: Vector3 = pose_node.get_meta("head_at", contact)
	var last_usec := int(pose_node.get_meta("head_usec", 0))
	var velocity := Vector3.ZERO
	if last_usec > 0 and now > last_usec:
		velocity = (contact - last_at) / (float(now - last_usec) / 1000000.0)
	if not pose_node.is_in_group("rake_heads"):
		pose_node.add_to_group("rake_heads")
	pose_node.set_meta("actor", actor)
	pose_node.set_meta("head_at", contact)
	pose_node.set_meta("head_usec", now)
	pose_node.set_meta("head_a", contact - across * half_width)
	pose_node.set_meta("head_b", contact + across * half_width)
	pose_node.set_meta("head_vel", velocity)
	pose_node.set_meta("drive_dir", heading)
	pose_node.set_meta("phase", RakeStroke.phase_of(actor))
	pose_node.set_meta("down", down)
	pose_node.set_meta("half_width", half_width)
	pose_node.set_meta("head_yaw", float(sample.get("head_yaw", 0.0)))
	pose_node.set_meta("grip_right", lower)
	pose_node.set_meta("grip_left", upper)
	pose_node.set_meta("grip", along)


## A rake nobody is swinging any more (dropped, pocketed, or a hand's rake while
## it hauls a bag): out of "rake_heads" and marked up and idle, so the leaf movers
## never keep pushing with a head frozen where it was last drawn (contract C4: only
## posed rakes publish a head). Cheap to call every tick.
static func unpublish(pose_node: Node3D) -> void:
	if pose_node == null or not pose_node.is_in_group("rake_heads"):
		return
	pose_node.remove_from_group("rake_heads")
	pose_node.set_meta("phase", -1.0)
	pose_node.set_meta("down", false)
	pose_node.set_meta("head_vel", Vector3.ZERO)
	pose_node.remove_meta("head_usec")


## The handle's frame: +Y up the handle toward the hands, -Z (the way the tines
## curl) back toward the holder, so the fan's back pushes the leaves ahead.
static func _handle_basis(up_handle: Vector3, heading: Vector3) -> Basis:
	var y := up_handle.normalized() if up_handle.length() > 0.001 else Vector3.UP
	var z := heading - y * heading.dot(y)
	if z.length() < 0.001:
		z = Vector3.UP.cross(y)
	z = z.normalized()
	return Basis(y.cross(z), y, z).orthonormalized()


## The ground under the tines: the leaves' surface where the leaf view knows it
## (raking:2's contract C3), else the holder's ground.
static func surface_y(node: Node, at: Vector3, fallback: float) -> float:
	if node == null or not node.is_inside_tree():
		return fallback
	var view := node.get_tree().get_first_node_in_group("leaf_view")
	if view != null and view.has_method("surface_y"):
		return float(view.call("surface_y", Vector2(at.x, at.z)))
	return fallback


## Where the two hands go on a posed rake, world space: [right, left] (the right
## hand low, the left on top). INF for both when it isn't posed in hand.
static func grips(prop: Node3D, _holder: Node3D = null, _sample: Dictionary = {}) -> Array[Vector3]:
	var free: Array[Vector3] = [Vector3.INF, Vector3.INF]
	var pose_node := prop.get_node_or_null("Visual/Look/Pose") as Node3D if prop != null else null
	return grips_of(pose_node) if pose_node != null else free


static func grips_of(pose_node: Node3D) -> Array[Vector3]:
	if pose_node == null or not pose_node.top_level or not pose_node.has_meta("grip_right"):
		return [Vector3.INF, Vector3.INF]
	return [pose_node.get_meta("grip_right") as Vector3, pose_node.get_meta("grip_left") as Vector3]


## Builds (or rebuilds, when the tier changed) the rake model under a Pose node.
static func dress(pose_node: Node3D, tier: int) -> void:
	var old := pose_node.get_node_or_null("Rake")
	if old != null:
		if int(pose_node.get_meta("tier", -1)) == tier:
			return
		old.free()
	pose_node.set_meta("tier", tier)
	pose_node.add_child(_YardModels.rake(tier))
