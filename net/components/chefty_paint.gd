extends Node

## Authority: local, cosmetic. Chefty's paint job and decal (docs/GAME.md
## "Cosmetics"; gap-specs shops chunk 7, critic C22). A child of either Chefty
## (the drivable one, net/components/chefty_drive.gd, or the legacy ride,
## net/components/ride.gd) on every peer. The look comes from World/Shops'
## replicated truck ({paint, decal}, Shops.truck_look), so it needs no traffic
## of its own.
##
## A new paint or decal is put on only while Chefty stands still (critic C22:
## below park speed, never on the road with riders in the bed): a cloud of
## paint puffs in the new color bursts round the truck with a rattle-can hiss,
## and the look swaps inside the cloud, so nothing pops. The first look a peer
## learns (a save with mint paint, a late joiner) goes straight on.
##
## Googly eyes: each pupil is a little spring the truck's acceleration shoves,
## so they roll round their eyes when Chefty brakes, turns or hits a bump.

const _Stylized = preload("res://props/stylized.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Vehicles = preload("res://props/vehicles.gd")

## The Chefty this paints (set before adding it): it has apply_paint(color,
## decal), and is_moving() (drivable) or is_riding() (legacy).
var vehicle: Node3D
## The look on the truck now ({color, decal}), and what's waiting to go on.
var shown: Dictionary = {}
var _wanted: Dictionary = {}
var _shops: Node
## A repaint under way: seconds into it (-1 for none), the look it puts on,
## whether its swap moment has passed (the look went on, or Chefty was moving
## and it waits for the next show), and its puffs [{node, velocity, life}].
var _repaint: float = -1.0
var _repaint_look: Dictionary = {}
var _swapped: bool = false
var _puffs: Array[Dictionary] = []
## How many repaints this peer has played (tests).
var repaints: int = 0
## Googly pupils: offset in the eye (m, x and y) and velocity, per eye; the
## body's last position and velocity, for its acceleration.
var _pupil_offset: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _pupil_velocity: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _last_at := Vector3.INF
var _last_velocity := Vector3.ZERO


func _ready() -> void:
	name = "Paint"


func _process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if _shops == null or not is_instance_valid(_shops):
		_shops = get_tree().get_first_node_in_group("shops")
		if _shops != null and not _shops.is_connected("truck_changed", _on_truck_changed):
			_shops.connect("truck_changed", _on_truck_changed)
	# Until this peer knows the look: a client's first snapshot only says
	# truck_changed when the look differs from the defaults, and a Chefty that
	# never learned its first look would put the next one on with no show (W8:
	# the observer's Chefty went black in a frame while the host's sprayed).
	if _wanted.is_empty() and _shops != null:
		_on_truck_changed()
	if _repaint >= 0.0:
		_step_repaint(delta)
	elif not _wanted.is_empty() and not _same(_wanted, shown) and _standing_still():
		if shown.is_empty():
			# The first look this peer learns: straight on, no show.
			_apply(_wanted)
		else:
			_start_repaint(_wanted)
	_jiggle(delta)


## Whether the truck shows the look Shops has (tests): nothing waiting.
func is_settled() -> bool:
	return _repaint < 0.0 and (_wanted.is_empty() or _same(_wanted, shown))


func _on_truck_changed() -> void:
	if _shops == null:
		return
	# A client's Shops holds defaults until its first snapshot: wait for it.
	if not Net.is_host() and not bool(_shops.get("synced")):
		return
	_wanted = _shops.call("truck_look")


func _standing_still() -> bool:
	if vehicle.has_method("is_moving"):
		return not bool(vehicle.call("is_moving"))
	if vehicle.has_method("is_riding"):
		return not bool(vehicle.call("is_riding"))
	return true


func _apply(look: Dictionary) -> void:
	shown = look.duplicate()
	vehicle.call("apply_paint", look["color"], str(look["decal"]))
	_pupil_offset = [Vector2.ZERO, Vector2.ZERO]
	_pupil_velocity = [Vector2.ZERO, Vector2.ZERO]


static func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	return (a["color"] as Color).is_equal_approx(b["color"]) and str(a["decal"]) == str(b["decal"])


# ---------------------------------------------------------------- the repaint

func _start_repaint(look: Dictionary) -> void:
	_repaint = 0.0
	_repaint_look = look.duplicate()
	_swapped = false
	repaints += 1
	var body := _body()
	if body == null:
		_apply(look)
		_repaint = -1.0
		return
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_on", "spray_can", body)
	var rng := RandomNumberGenerator.new()
	rng.seed = repaints * 7919 + hash(str(look["decal"]))
	var color: Color = look["color"]
	var kit := _MeshKit.new()
	kit.blob(Vector3.ZERO, Vector3.ONE, Color.WHITE, {"detail": 1, "lumps": 0.3, "lump_scale": 2.0, "outward": true, "flat": false, "jitter": 0.0, "shade": false})
	var mesh := kit.commit()
	for index: int in Constants.REPAINT_PUFFS:
		var puff := _Stylized.instance(mesh, {"roughness": 0.95, "specular": 0.0})
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.top_level = true
		add_child(puff)
		# Round the truck's body, low and high, front to back.
		var local := Vector3(rng.randf_range(-Constants.REPAINT_SPREAD_X, Constants.REPAINT_SPREAD_X), rng.randf_range(Constants.REPAINT_SPREAD_Y.x, Constants.REPAINT_SPREAD_Y.y), rng.randf_range(Constants.REPAINT_SPREAD_Z.x, Constants.REPAINT_SPREAD_Z.y))
		puff.global_position = body.global_transform * local
		# Paint mist, lighter than the paint (a black job's cloud read as smoke, W8).
		var tint := color.lerp(Color.WHITE, rng.randf_range(Constants.REPAINT_MIST.x, Constants.REPAINT_MIST.y) + Constants.REPAINT_MIST_DARK * (1.0 - color.get_luminance()))
		puff.set_instance_shader_parameter("tint", Color(tint.r, tint.g, tint.b, 1.0))
		var away := (body.global_basis * Vector3(local.x, 0.3, 0.0)).normalized()
		_puffs.append({
			"node": puff,
			"velocity": away * rng.randf_range(Constants.REPAINT_PUFF_OUT.x, Constants.REPAINT_PUFF_OUT.y) + Vector3.UP * rng.randf_range(Constants.REPAINT_PUFF_UP.x, Constants.REPAINT_PUFF_UP.y),
			"size": rng.randf_range(Constants.REPAINT_PUFF_SIZE.x, Constants.REPAINT_PUFF_SIZE.y),
			"delay": rng.randf_range(0.0, Constants.REPAINT_PUFF_STAGGER),
		})
		puff.scale = Vector3.ONE * 0.01


func _step_repaint(delta: float) -> void:
	_repaint += delta
	# Pulled away before the swap: the cloud stays behind and the old paint drives
	# off in it; the show plays again once Chefty parks (critic C22: never on the
	# road, W8 review).
	if not _swapped and _repaint >= Constants.REPAINT_SWAP_AT:
		_swapped = true
		if _standing_still():
			_apply(_repaint_look)
	var life := Constants.REPAINT_SECONDS
	for puff: Dictionary in _puffs:
		var node := puff["node"] as Node3D
		if not is_instance_valid(node):
			continue
		var t := clampf((_repaint - float(puff["delay"])) / life, 0.0, 1.0)
		node.global_position += (puff["velocity"] as Vector3) * delta * (1.0 - t)
		# Bursts out fast to full size, then thins away.
		var grow := clampf(t / 0.18, 0.0, 1.0)
		var size := float(puff["size"]) * (grow * (2.0 - grow)) * (1.0 - t * t * 0.6)
		node.scale = Vector3.ONE * maxf(size * (1.0 - smoothstep(0.7, 1.0, t)), 0.001)
	if _repaint >= life + 0.15:
		for puff: Dictionary in _puffs:
			if is_instance_valid(puff["node"]):
				(puff["node"] as Node).queue_free()
		_puffs.clear()
		_repaint = -1.0


# ---------------------------------------------------------------- googly eyes

func _jiggle(delta: float) -> void:
	var body := _body()
	if body == null or delta <= 0.0:
		return
	var look := body.get_node_or_null("TruckLook")
	var eyes: Array[Node3D] = []
	for index: int in 2:
		var eye := look.get_node_or_null("GooglyEye%d/Pupil" % index) as Node3D if look != null else null
		if eye != null:
			eyes.append(eye)
	var at := body.global_position
	var velocity := Vector3.ZERO if not _last_at.is_finite() else (at - _last_at) / delta
	var accel := (velocity - _last_velocity) / delta
	_last_at = at
	_last_velocity = velocity
	if eyes.is_empty():
		return
	# Teleports and new trips aren't a shove.
	if accel.length() > Constants.GOOGLY_TELEPORT_ACCEL:
		accel = Vector3.ZERO
	# In the truck's own space: braking (+z accel) flings the pupils up (a cartoon
	# double take), turning throws them to the outside, a bump bounces them.
	var local := body.global_basis.inverse() * accel
	var shove := Vector2(-local.x, local.z - local.y) * Constants.GOOGLY_SHOVE * Constants.GOOGLY_STIFFNESS
	# At rest they hang at the bottom of the eye.
	var rest := Vector2(0.0, -(_Vehicles.GOOGLY_RADIUS - _Vehicles.GOOGLY_PUPIL) * 0.9)
	for index: int in eyes.size():
		var offset := _pupil_offset[index] if _pupil_offset[index] != Vector2.ZERO else rest
		var spring := -Constants.GOOGLY_STIFFNESS * (offset - rest) - Constants.GOOGLY_DAMPING * _pupil_velocity[index]
		_pupil_velocity[index] += (spring + shove) * delta
		offset += _pupil_velocity[index] * delta
		if offset.length() > Constants.GOOGLY_RANGE:
			offset = offset.normalized() * Constants.GOOGLY_RANGE
			_pupil_velocity[index] *= -0.4
		_pupil_offset[index] = offset
		eyes[index].position = Vector3(offset.x, offset.y, 0.0)


func _body() -> Node3D:
	return vehicle.get_node_or_null("Body") as Node3D if vehicle != null else null
