extends Node3D

## Authority: local, cosmetic. The Chefty Net (driving chunk C3, docs/GAME.md
## "Crash comedy"): once the crew owns it, a dark green cargo net rides on
## Chefty's bed, drawn on every peer from the crew's gear and the bag count every
## peer already has. With no bags it's rolled up and strapped along the front
## wall; with bags it's thrown over the heap (props/truck_bed_load.gd's spots),
## hugging the bags and strapped down to the side rails, so it bulges as the
## load grows. A child of Chefty's Body, in the bed's space.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _BedLoad = preload("res://props/truck_bed_load.gd")
const ROPE := Color(0.16, 0.3, 0.2)
const HOOK := Color(0.85, 0.66, 0.2)
## The bed's rail tops (y), its walls' inside (x), its front and back (z).
const RAIL_Y: float = 1.64
const WALL_X: float = 1.04
const FRONT_Z: float = -1.15
const BACK_Z: float = 2.58
## The net's mesh: ropes this far apart across and along the bed, sampled this finely.
const CROSS_STEP: float = 0.36
const ALONG_STEP: float = 0.42
const SAMPLE: float = 0.14
const ROPE_RADIUS: float = 0.022
## How far a rope clears a bag's top (m), and how far a bag's crown reaches out.
const CLEAR: float = 0.05
const CROWN_REACH: float = 0.42

static var _cache: Dictionary = {}

var _shown: int = -1


func _ready() -> void:
	name = "CheftyNet"


## Draw it over count bags (0: rolled up).
func show_over(count: int) -> void:
	count = clampi(count, 0, Constants.TRUCK_BAG_CAPACITY)
	if count == _shown:
		return
	_shown = count
	for child: Node in get_children():
		child.queue_free()
	if not _cache.has(count):
		_cache[count] = _mesh(count)
	var mesh: ArrayMesh = _cache[count]
	if mesh != null:
		add_child(_Stylized.instance(mesh, {"roughness": 0.9, "specular": 0.05}))


static func _mesh(count: int) -> ArrayMesh:
	var kit := _MeshKit.new()
	if count <= 0:
		# Rolled up along the front wall's top, with two hooks.
		kit.tube(PackedVector3Array([Vector3(-0.95, RAIL_Y + 0.05, FRONT_Z + 0.02), Vector3(0.95, RAIL_Y + 0.05, FRONT_Z + 0.02)]), PackedFloat32Array([0.075, 0.075]), ROPE, 9, {"jitter": 0.0, "cap": true, "cap_start": true})
		for x: float in [-0.7, 0.7]:
			kit.tube(PackedVector3Array([Vector3(x, RAIL_Y + 0.12, FRONT_Z), Vector3(x, RAIL_Y - 0.12, FRONT_Z - 0.06)]), PackedFloat32Array([0.016, 0.014]), HOOK, 5, {"jitter": 0.0})
		return kit.commit()
	var tops: Array[Vector3] = []
	for index: int in count:
		var spot := _BedLoad.slot(index).origin
		tops.append(Vector3(spot.x, spot.y + _BedLoad.BAG_HEIGHT, spot.z))
	# Ropes across the bed (along x), one every ALONG_STEP of its length, over the
	# bags and hooked to both rails.
	var z := FRONT_Z + 0.2
	while z <= BACK_Z - 0.1:
		_rope(kit, tops, Vector3(-WALL_X, 0.0, z), Vector3(WALL_X, 0.0, z))
		z += ALONG_STEP
	# Ropes along it (along z), over the bags only.
	var x := -WALL_X + 0.3
	while x <= WALL_X - 0.25:
		_rope(kit, tops, Vector3(x, 0.0, FRONT_Z), Vector3(x, 0.0, BACK_Z), false)
		x += CROSS_STEP
	return kit.commit()


## How high the net lies at (x, z): over a bag's crown, else NAN (no bag here).
static func _height(tops: Array[Vector3], at: Vector2) -> float:
	var best := NAN
	for top: Vector3 in tops:
		var away := Vector2(top.x - at.x, top.z - at.y).length()
		if away > CROWN_REACH:
			continue
		# A bag's top is a dome: lower toward its edge.
		var y := top.y + CLEAR - 0.18 * (away / CROWN_REACH) * (away / CROWN_REACH)
		best = y if is_nan(best) else maxf(best, y)
	return best


## One rope from a to b (bed space, y ignored), laid over the bags. Where it runs
## off the heap it either drops to the rail it's hooked to (hooked) or stops.
static func _rope(kit: RefCounted, tops: Array[Vector3], a: Vector3, b: Vector3, hooked: bool = true) -> void:
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(2, int(ceil(length / SAMPLE)))
	var runs: Array = []
	var run := PackedVector3Array()
	for step: int in steps + 1:
		var t := float(step) / float(steps)
		var at := a.lerp(b, t)
		var y := _height(tops, Vector2(at.x, at.z))
		if is_nan(y):
			if run.size() >= 2:
				runs.append(run)
			run = PackedVector3Array()
			continue
		run.append(Vector3(at.x, maxf(y, RAIL_Y), at.z))
	if run.size() >= 2:
		runs.append(run)
	if runs.is_empty():
		return
	if hooked:
		# One run from rail to rail: the heap's span, strapped down at each end.
		var first: PackedVector3Array = runs[0]
		var last: PackedVector3Array = runs[runs.size() - 1]
		var whole := PackedVector3Array([Vector3(a.x, RAIL_Y, a.z)])
		for piece: PackedVector3Array in runs:
			whole.append_array(piece)
		whole.append(Vector3(b.x, RAIL_Y, b.z))
		if first.size() > 0 and last.size() > 0:
			runs = [whole]
		kit.tube(PackedVector3Array([Vector3(a.x, RAIL_Y + 0.04, a.z), Vector3(a.x * 1.05, RAIL_Y - 0.1, a.z)]), PackedFloat32Array([0.014, 0.012]), HOOK, 5, {"jitter": 0.0})
		kit.tube(PackedVector3Array([Vector3(b.x, RAIL_Y + 0.04, b.z), Vector3(b.x * 1.05, RAIL_Y - 0.1, b.z)]), PackedFloat32Array([0.014, 0.012]), HOOK, 5, {"jitter": 0.0})
	for piece: PackedVector3Array in runs:
		var radii := PackedFloat32Array()
		radii.resize(piece.size())
		radii.fill(ROPE_RADIUS)
		kit.tube(piece, radii, ROPE, 5, {"jitter": 0.0, "cap": false})
