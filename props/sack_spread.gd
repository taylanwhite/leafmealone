extends Node3D

## Authority: local, cosmetic (shops:9; docs/GAME.md "Seasonal work"). What a
## seasonal sack of fertilizer, grass seed or rock salt does, drawn the same on
## every peer from its replicated `fuel` (how full it is, 0 to 100) and
## `spraying` (the host's "it's being poured right now", job_tasks.gd _spread):
##   - it slumps as it empties: an empty one stands Constants.SACK_EMPTY_HEIGHT
##     of its full height and bulges a little, so a half-used sack on the rack,
##     in your arms or on the lawn looks half used;
##   - poured, it's flicked out on a beat (SACK_SHAKE_SECONDS): a little lift
##     back (the wind-up), a snap forward that throws a fan of granules out of
##     its mouth to land a couple of metres ahead, where the host works the
##     cells, and a settle back; the shake's sound plays on the frame of the snap;
##   - run dry it folds flat (SACK_FOLD_SECONDS) with a papery crumple, and the
##     host frees it after that (net_prop.gd host_use_sack).
## It moves the model inside the prop's Look, about its HOLDS pivot (props/
## prop_looks.gd), and the hands' grips are read off that model, so the hands
## stay on its sides through the slump and every shake. Chefty's rack draws the
## same slump (slump_scale, net/components/tool_bed.gd).

const _PropLooks = preload("res://props/prop_looks.gd")
## The granules' colors, by sack: blue-white fertilizer prills, straw seed, salt.
const GRANULE_COLORS: Dictionary = {
	"fertilizer_bag": Color(0.86, 0.92, 1.0), "grass_seed": Color(0.9, 0.8, 0.5), "rock_salt": Color(0.97, 0.97, 0.95),
}
## Where the shake is in its beat (0 to 1) when the sack snaps forward and throws.
const SNAP_AT := Constants.SACK_SNAP_AT
## How far it lifts back in the wind-up, as a share of SACK_SHAKE_TILT.
const WINDUP_SHARE := Constants.SACK_WINDUP_SHARE

var _phase: float = 0.0
var _shaking: bool = false
var _fold: float = 0.0
var _folded_sound: bool = false
var _anchor_y: float = NAN


## How a sack this full (0 to 1) and this far folded (0 to 1) is scaled, (wide,
## tall, wide), about its base: shared with Chefty's rack (net/components/
## tool_bed.gd), so a part-used sack keeps its slump as it glides on and off.
static func slump_scale(fill: float, fold: float = 0.0) -> Vector3:
	var height := lerpf(Constants.SACK_EMPTY_HEIGHT, 1.0, clampf(fill, 0.0, 1.0)) * lerpf(1.0, 0.08, ease(clampf(fold, 0.0, 1.0), 0.6))
	var wide := 1.0 + (1.0 - clampf(fill, 0.0, 1.0)) * Constants.SACK_EMPTY_BULGE + clampf(fold, 0.0, 1.0) * Constants.SACK_FOLD_BULGE
	return Vector3(wide, height, wide)


## The sack's shape from the first frame it's drawn (taken off the rack part
## used, it never shows full for a frame).
func _ready() -> void:
	_physics_process.call_deferred(0.0)


func _physics_process(delta: float) -> void:
	var prop := get_parent() as Node3D
	var model := _model()
	if prop == null or model == null:
		return
	var kind := str(prop.get("kind"))
	var fill := clampf(float(prop.get("fuel")) / 100.0, 0.0, 1.0)
	var held := int(prop.get("held_by")) != 0
	var pivot := _pivot(prop)
	if fill <= 0.0:
		_fold = minf(_fold + delta / maxf(Constants.SACK_FOLD_SECONDS, 0.01), 1.0)
		if not _folded_sound:
			_folded_sound = true
			_play("sack_fold", prop.global_position + Vector3.UP * 0.6)
	var scale_now := slump_scale(fill, _fold)
	# Poured: the beat runs; let go, the sack eases back from wherever it was.
	var pouring := bool(prop.get("spraying")) and held and fill > 0.0
	var tilt := 0.0
	if pouring:
		# Each beat starts with the wind-up, so the first throw comes a beat's
		# share after the click, never on it.
		var was := _phase if _shaking else 0.0
		_phase = fposmod(was + delta / maxf(Constants.SACK_SHAKE_SECONDS, 0.05), 1.0)
		if was < SNAP_AT and _phase >= SNAP_AT:
			_throw(prop, kind)
		_shaking = true
		tilt = _beat(_phase)
	else:
		_shaking = false
		_phase = 0.0
	# Scaled about the base when it stands on its own, about the hands when held,
	# easing between the two as it's picked up or let go (a part-used sack would
	# otherwise hop by the slump as it changes hands).
	var anchor_to := pivot.y if held else 0.0
	_anchor_y = anchor_to if is_nan(_anchor_y) else lerpf(_anchor_y, anchor_to, 1.0 - exp(-Constants.SACK_ANCHOR_FOLLOW * delta))
	var anchor := Vector3(0.0, _anchor_y, 0.0)
	var shape := Transform3D(Basis.IDENTITY.scaled(scale_now), Vector3.ZERO)
	var turn := Transform3D(Basis(Vector3.RIGHT, -tilt), Vector3.ZERO)
	model.transform = Transform3D(Basis.IDENTITY, anchor) * turn * shape * Transform3D(Basis.IDENTITY, -anchor)


## The shake's tilt forward (rad) at a point in its beat: a lift back to the
## wind-up, a snap to full tilt at SNAP_AT, and an ease back.
func _beat(phase: float) -> float:
	var full := Constants.SACK_SHAKE_TILT
	if phase < SNAP_AT * 0.7:
		return -full * WINDUP_SHARE * sin(phase / (SNAP_AT * 0.7) * PI * 0.5)
	if phase < SNAP_AT:
		var t := (phase - SNAP_AT * 0.7) / (SNAP_AT * 0.3)
		return lerpf(-full * WINDUP_SHARE, full, t * t)
	var back := (phase - SNAP_AT) / (1.0 - SNAP_AT)
	return full * (1.0 - smoothstep(0.0, 1.0, back))


## The snap: a fan of granules out of the sack's mouth, ahead and a little up,
## and the shake's sound there.
func _throw(prop: Node3D, kind: String) -> void:
	var model := _model()
	if model == null:
		return
	var box: AABB = (model as VisualInstance3D).get_aabb() if model is VisualInstance3D else AABB(Vector3(-0.2, 0.0, -0.1), Vector3(0.4, 0.6, 0.2))
	var mouth := model.global_transform * Vector3(0.0, box.end.y, box.get_center().z)
	# Ahead is the way the sack faces (its front, -Z), as its holder's hold turns
	# it: a player's body node doesn't turn with them, their drawn Visual does.
	var ahead := -model.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	# Through your own eyes the mouth is a hand's breadth from your face: the
	# throw is drawn from a little way out, so it's a fan you watch land, not a
	# handful in your eye.
	var holder := _holder(prop)
	if holder != null and int(prop.get("held_by")) == Net.local_peer_id():
		mouth += ahead * Constants.SACK_OWN_VIEW_AHEAD + Vector3.DOWN * Constants.SACK_OWN_VIEW_DROP
	# A fresh handful each throw, in the world, not on the sack (thrown granules
	# don't follow it), gone once it has landed: the last throw's granules finish
	# their flight while the next one leaves the mouth.
	var burst := _make_burst(kind)
	var world := get_tree().get_first_node_in_group("world")
	if world != null:
		world.add_child(burst)
	else:
		get_tree().current_scene.add_child(burst)
	burst.global_position = mouth
	burst.direction = (ahead + Vector3.UP * Constants.SACK_THROW_LIFT).normalized()
	burst.emitting = true
	get_tree().create_timer(Constants.SACK_GRANULE_SECONDS + Constants.SACK_SHAKE_SECONDS).timeout.connect(burst.queue_free)
	_play("sack_shake", mouth)


func _make_burst(kind: String) -> CPUParticles3D:
	var burst := CPUParticles3D.new()
	burst.name = "SackGranules"
	burst.one_shot = true
	burst.emitting = false
	burst.explosiveness = 0.85
	burst.amount = Constants.SACK_GRANULES
	burst.lifetime = Constants.SACK_GRANULE_SECONDS
	burst.local_coords = false
	burst.spread = Constants.SACK_THROW_SPREAD_DEG
	burst.flatness = Constants.SACK_THROW_FLATNESS
	burst.initial_velocity_min = Constants.SACK_THROW_SPEED * Constants.SACK_THROW_SLOW_SHARE
	burst.initial_velocity_max = Constants.SACK_THROW_SPEED
	burst.gravity = Vector3(0.0, -9.8, 0.0)
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 0.06
	var mesh := SphereMesh.new()
	mesh.radius = 0.024
	mesh.height = 0.048
	mesh.radial_segments = 4
	mesh.rings = 2
	burst.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = GRANULE_COLORS.get(kind, Color.WHITE)
	# Unshaded: a granule in shadow is still a speck you can see fly.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	burst.material_override = material
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return burst


## The sack's model: the mesh inside the prop's Look (props/prop_looks.gd dress).
func _model() -> Node3D:
	var look := get_parent().get_node_or_null("Visual/Look") as Node3D if get_parent() != null else null
	if look == null or look.get_child_count() == 0:
		return null
	return look.get_child(0) as Node3D


## The line the hands hold it by (HOLDS pivot): where it shakes and slumps about.
func _pivot(prop: Node3D) -> Vector3:
	return _PropLooks.hold_of(prop).get("pivot", Vector3.ZERO) as Vector3


func _holder(prop: Node3D) -> Node3D:
	var peer := int(prop.get("held_by"))
	if peer == 0:
		return null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer):
			return node as Node3D
	return null


func _play(id: String, at: Vector3) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", id, at)
