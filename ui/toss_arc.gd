extends Node3D

## Authority: local, cosmetic. While you wind up a throw with a leaf bag in your
## hands (player.gd _step_wind_up), a faint dotted arc shows where it will go and
## a small ring where it comes down: the same flight the host will give it, aim
## help and all (net/components/bed_toss.gd), so what you see is what you get.
## The dots slide along the arc toward the ring. Over Chefty's bed with room in
## it, the arc warms to gold and the ring sits on the spot in the pile the bag
## will land in. No words: the arc is the hint (docs/GAME.md "Tossing bags into
## Chefty"). Only this player sees it.

const _BedToss = preload("res://net/components/bed_toss.gd")
## Presentation: the dots' size and colors, how fast they slide along, the
## ring's size, how long it takes to fade in, and how much of the arc nearest
## your face is left out (s of flight).
const DOT_RADIUS: float = 0.035
const DOT_COLOR := Color(1.0, 0.96, 0.85, 0.5)
const DOT_IN_COLOR := Color(1.0, 0.8, 0.32, 0.75)
const SLIDE_PER_SECOND: float = 0.5
const RING_RADIUS: float = 0.3
const RING_WIDTH: float = 0.05
const FADE_IN_SECONDS: float = 0.15
const SKIP_NEAR_SECONDS: float = 0.08
const MAX_DOTS: int = 64
## How much softer and harder a throw may be and still go in for the arc to turn gold.
const SURE_SHARE: float = 0.04
## The dots trace the bag's middle; the flight is worked out for its bottom.
const CENTER_UP := Vector3(0.0, 0.35, 0.0)

## What the preview last showed, for the toss test and net/dev/probe.gd.
static var stats: Dictionary = {"shown_frames": 0, "caught_frames": 0, "last_end": Vector3.ZERO, "last_caught": false}

var _dots: MultiMeshInstance3D
var _ring: MeshInstance3D
var _dot_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _slide: float = 0.0


func _ready() -> void:
	name = "TossArc"
	top_level = true
	_dot_material = _material(DOT_COLOR)
	var sphere := SphereMesh.new()
	sphere.radius = DOT_RADIUS
	sphere.height = DOT_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = _dot_material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.instance_count = MAX_DOTS
	multi.visible_instance_count = 0
	multi.mesh = sphere
	_dots = MultiMeshInstance3D.new()
	_dots.name = "Dots"
	_dots.multimesh = multi
	_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dots)
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - RING_WIDTH
	torus.outer_radius = RING_RADIUS
	torus.rings = 24
	torus.ring_segments = 6
	_ring_material = _material(DOT_COLOR)
	torus.material = _ring_material
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = torus
	_ring.scale = Vector3(1.0, 0.25, 1.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	visible = false


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.no_depth_test = false
	return material


func _process(delta: float) -> void:
	var player := _own_player()
	var bag := _held_bag(player)
	var seconds := float(player.call("wind_up_seconds")) if player != null else -1.0
	if bag == null or seconds < Constants.THROW_TAP_SECONDS or bool(player.get("straining")):
		visible = false
		return
	visible = true
	_slide = fposmod(_slide + delta * SLIDE_PER_SECOND, 1.0)
	var truck := get_tree().get_first_node_in_group("chefty")
	var forward := -player.global_basis.z
	forward.y = 0.0
	var feet := player.global_position
	# It leaves from where it hangs in your hands (net_prop.gd _release).
	var from: Vector3 = bag.call("_hold_position", player)
	var power := _BedToss.power_for_seconds(seconds)
	var vel := _BedToss.launch_velocity("leaf_bag", float(bag.call("weight_kg")), forward, power)
	vel = _BedToss.assist(truck, from, vel, feet.y)
	var step := Constants.TOSS_ARC_STEP_SECONDS
	var path := _BedToss.flight(from, vel, feet.y, truck, -1.0, step * (1.0 - _slide))
	# Gold only when it's sure: a throw a touch softer or harder goes in too. The
	# catch itself is kinder than that, so an arc left plain can still sneak in.
	var caught := bool(path["caught"]) and bool(_BedToss.flight(from, vel * (1.0 - SURE_SHARE), feet.y, truck)["caught"]) and bool(_BedToss.flight(from, vel * (1.0 + SURE_SHARE), feet.y, truck)["caught"])
	var room := truck != null and int(truck.call("bag_count")) < Constants.TRUCK_BAG_CAPACITY
	if room and _BedToss.close_toss(truck, from, vel, feet.y):
		# Right by the bed it hops in over the side (net_prop.gd): the dots follow the hop.
		caught = true
		path = _hop_path(truck, from, vel, step)
	else:
		# The arc stops at whatever's in the way: a mailbox, a fence, a tree.
		var hit := _blocked(path["points"] as PackedVector3Array, [bag, player, truck])
		if not hit.is_empty():
			caught = false
			path = {"points": hit["points"], "end": hit["at"]}
	var warm := caught and room
	var fade := clampf((seconds - Constants.THROW_TAP_SECONDS) / FADE_IN_SECONDS, 0.0, 1.0)
	var color := DOT_IN_COLOR if warm else DOT_COLOR
	_dot_material.albedo_color = Color(color, color.a * fade)
	_ring_material.albedo_color = Color(color, color.a * fade)
	var points: PackedVector3Array = path["points"]
	var shown := 0
	var multi := _dots.multimesh
	for index: int in points.size():
		var age := (float(index) + 1.0 - _slide) * step
		if age < SKIP_NEAR_SECONDS or shown >= MAX_DOTS:
			continue
		# Smaller toward the end, so the arc reads as going away from you.
		var shrink := lerpf(1.0, 0.6, float(index) / maxf(float(points.size()), 1.0))
		multi.set_instance_transform(shown, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * shrink), points[index] + CENTER_UP))
		shown += 1
	multi.visible_instance_count = shown
	var end: Vector3 = path["end"]
	if warm:
		# On the spot in the pile it will land in (props/truck_bed_load.gd).
		end = (truck.call("bed_slot", int(truck.call("bag_count"))) as Transform3D).origin
	_ring.global_position = end + Vector3(0.0, 0.03, 0.0)
	var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.5)
	_ring.scale = Vector3(pulse, 0.25, pulse)
	stats["shown_frames"] = int(stats["shown_frames"]) + 1
	stats["caught_frames"] = int(stats["caught_frames"]) + (1 if warm else 0)
	stats["last_end"] = end
	stats["last_caught"] = warm


## The hop over the side into the next spot in the load, as dots (the glide
## net_prop.gd _step_settle draws), in the same shape flight() gives.
func _hop_path(truck: Node, from: Vector3, vel: Vector3, step: float) -> Dictionary:
	var bed: Transform3D = truck.call("bed_transform")
	var spot: Transform3D = truck.call("bed_slot", int(truck.call("bag_count")))
	var seconds := clampf(from.distance_to(spot.origin) * Constants.BED_SETTLE_SECONDS_PER_M, Constants.BED_SETTLE_MIN_SECONDS, Constants.BED_SETTLE_MAX_SECONDS)
	var p0 := bed.affine_inverse() * from
	var p1 := bed.affine_inverse() * spot.origin
	var v0 := bed.basis.inverse() * vel
	var points := PackedVector3Array()
	var t := step * (1.0 - _slide)
	while t < seconds:
		points.append(bed * _BedToss.glide(p0, v0, p1, Vector3.DOWN * Constants.BED_SETTLE_LAND_SPEED, seconds, t / seconds))
		t += step
	return {"points": points, "end": spot.origin, "caught": true, "hull": false}


## The first thing in the world (not the bag, its thrower or the truck, which
## the flight already knows) the arc's middle runs into: {points up to it, at},
## or {} when the way is clear.
func _blocked(points: PackedVector3Array, skip: Array) -> Dictionary:
	if points.size() < 2:
		return {}
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for node: Variant in skip:
		_collect_bodies(node as Node, exclude)
	# Anyone it would bonk on the way (net_prop.gd _check_bonks' reach): a
	# homeowner by the curb, a crewmate, a NICE BOY.
	var people: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("bonkable"):
		if node is Node3D and not skip.has(node):
			people.append(node as Node3D)
	for index: int in range(1, points.size()):
		for person: Node3D in people:
			var offset := person.global_position + Vector3(0.0, 0.95, 0.0) - points[index]
			if absf(offset.y) <= 1.2 and Vector2(offset.x, offset.z).length() <= 0.85:
				return {"points": points.slice(0, index), "at": points[index]}
		var query := PhysicsRayQueryParameters3D.create(points[index - 1] + CENTER_UP, points[index] + CENTER_UP, 1, exclude)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var kept := points.slice(0, index)
			return {"points": kept, "at": (hit["position"] as Vector3) - CENTER_UP}
	return {}


static func _collect_bodies(node: Node, into: Array[RID]) -> void:
	if node == null:
		return
	if node is CollisionObject3D:
		into.append((node as CollisionObject3D).get_rid())
	for child: Node in node.get_children():
		_collect_bodies(child, into)


func _held_bag(player: Node) -> Node:
	if player == null:
		return null
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == Net.local_peer_id() and str(node.get("kind")) == "leaf_bag":
			return node
	return null


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
