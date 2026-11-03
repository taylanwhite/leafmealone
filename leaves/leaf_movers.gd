class_name LeafMovers
extends RefCounted

## Authority: local presentation. The leaves in the air: a pool of movers kept as
## packed arrays (one slot per leaf), stepped at the physics rate by a small leaf
## simulation (gravity, drag across and along the leaf's face, flutter, tumble,
## bounce, ground friction, the growing pile as the ground) and drawn with one
## MultiMesh per leaf species. Each mover carries whole density units from one
## cell to another (or into a bag, or out of a burst bag): it takes them off the
## view when it launches and gives them back when it lands, so nothing is ever
## counted twice or lost (docs/DECISIONS.md 2026-11-02 "Leaf motion").
## Never touches the leaf field. LeafMotion (leaves/leaf_motion.gd) owns it.

## Mover states.
const WAIT: int = 0
const FLY: int = 1
const SLIDE: int = 2
const PARK: int = 3
const SINK: int = 4
const FADE: int = 5
## Riding in the windrow ahead of the tines while they drive (rakefeel:look).
const RIDE: int = 6
## Mover kinds (how it moves; also for stats and traces).
const K_RAKE: int = 0
const K_HAND: int = 1
const K_BLOWER: int = 2
const K_CREW: int = 3
const K_PLOW: int = 4
const K_BAG: int = 5
const K_MULCH: int = 6
const K_SCATTER: int = 7
const K_DROP: int = 8
const K_KICK: int = 9
const K_EDGE: int = 10
const K_CORRECTION: int = 11
const KIND_NAMES: Array[String] = ["rake", "hand", "blower", "crew_rake", "plow", "bag", "mulch", "scatter", "drop", "kick", "edge", "correction"]
## Launch rules (contract: gap-specs/raking.json, leaf_motion.gd launch rules).
const R_SCHEDULED: int = 0
const R_TINE: int = 1
const R_BESIDE: int = 2
## How a waiting leaf went: its time came, the tines swept past it, the head's
## pressure wave reached it from the end of the drive, or it waited too long.
const HOW_SCHEDULED: int = 0
const HOW_CONTACT: int = 1
const HOW_WAVE: int = 2
const HOW_TIMEOUT: int = 3
## No landing reserved yet.
const NO_SLOT: int = -2
## How close (m) and slow (m/s) a homing leaf must be to land.
const LAND_DIST: float = 0.015
const LAND_SPEED: float = 0.5
## Lift of a lying leaf above the surface (the view's slot lift).
const LIE_LIFT: float = 0.004
## In the last LATE_LAND_WINDOW seconds of its time a leaf lands within LATE_LAND_DIST
## of its slot whatever its speed (the spec's handoff tolerance).
const LATE_LAND_WINDOW: float = 0.25
const LATE_LAND_DIST: float = 0.02
const GRAVITY := Vector3(0.0, -9.8, 0.0)

var cap: int = 0
## Movers alive at most (cap; tests lower it to try a smaller preset's pool).
var limit: int = 0
var view: Object
## One MultiMesh per species, or empty when nothing is drawn (headless).
var meshes: Array[MultiMesh] = []
var grid_w: int = 80
var space: PhysicsDirectSpaceState3D
var rays_per_tick: int = 0

var alive := PackedInt32Array()
var _alive_at := PackedInt32Array()
var _free := PackedInt32Array()
var state := PackedInt32Array()
var kind := PackedInt32Array()
var rule := PackedInt32Array()
var actor := PackedInt32Array()
var units := PackedInt32Array()
var src := PackedInt32Array()
var dst := PackedInt32Array()
var slot := PackedInt32Array()
var homing := PackedInt32Array()
var hurry := PackedInt32Array()
var species := PackedInt32Array()
var render := PackedInt32Array()
var park_frame := PackedInt32Array()
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var rot := PackedVector3Array()
var rot_to := PackedVector3Array()
var spin := PackedVector3Array()
var aim := PackedVector3Array()
var start := PackedVector3Array()
var dir := PackedVector3Array()
var color := PackedColorArray()
var color_to := PackedColorArray()
var custom := PackedColorArray()
var age := PackedFloat32Array()
var life := PackedFloat32Array()
var home_from := PackedFloat32Array()
var wait_until := PackedFloat32Array()
var born := PackedFloat32Array()
var scale := PackedFloat32Array()
var size := PackedFloat32Array()
var size_to := PackedFloat32Array()
var phase := PackedFloat32Array()
var freq := PackedFloat32Array()
var glide := PackedFloat32Array()
var drawn_at := PackedVector3Array()
var how := PackedInt32Array()
## Where the homing target was last tick (it rises as a pile grows under it).
var home_last := PackedVector3Array()
var waited := PackedFloat32Array()
## Highest point of each flight (traces only).
var peak := PackedFloat32Array()
## Riding the windrow (state RIDE): where on the berm ahead of the tines (across
## the head, ahead of it, how high up the stack), how long it rides at most, the
## offset it eases out of from where it was picked up, and whether it spills
## over the top early.
var ride_u := PackedFloat32Array()
var ride_d := PackedFloat32Array()
var ride_h := PackedFloat32Array()
var ride_end := PackedFloat32Array()
var ride_off := PackedVector3Array()
var spill := PackedInt32Array()
## The rake heads this tick (actor -> {mid, fwd, right, half, down, vel}) and
## how many leaves ride each one's windrow.
var _heads_now: Dictionary = {}
var _riders: Dictionary = {}
## Leaves that rode the windrow (stats).
var rode: int = 0

var _render_count := PackedInt32Array()
var _render_owner: Array[PackedInt32Array] = []
var _rng := RandomNumberGenerator.new()
## Cells with kicked flakes alive (cell index -> movers), so launches look only there.
var _kick_cells: Dictionary = {}

## Counters (LeafMotion.stats()).
var launched: int = 0
var landed: int = 0
var sinks_done: int = 0
var snaps: int = 0
## Snaps longer than LEAF_SNAP_MAX: a leaf visibly jumping into place.
var pops: int = 0
var max_step: float = 0.0
var max_snap: float = 0.0
var max_handoff: float = 0.0
var max_age: float = 0.0
## Kicked flakes that went on as a launching leaf; kicks whose slot was gone by
## the time they came down (they shrank into the litter instead).
var handovers: int = 0
var kicks_faded: int = 0
## Launches that took more units than their cell showed (leaves out of nowhere).
var overdrawn: int = 0
var rays: int = 0
var ray_hits: int = 0
## Landings this tick for the settle sounds: [position, destination cell index, units].
var landings: Array = []
## Test traces (LeafMotion.set_trace).
var trace: bool = false
var finished: Array = []
var tine_launches: Array = []


func setup(pool_cap: int, leaf_view: Object, species_meshes: Array[MultiMesh], width: int) -> void:
	cap = pool_cap
	limit = pool_cap
	view = leaf_view
	meshes = species_meshes
	grid_w = width
	_rng.seed = 7151
	state.resize(cap)
	kind.resize(cap)
	rule.resize(cap)
	actor.resize(cap)
	units.resize(cap)
	src.resize(cap)
	dst.resize(cap)
	slot.resize(cap)
	homing.resize(cap)
	hurry.resize(cap)
	species.resize(cap)
	render.resize(cap)
	park_frame.resize(cap)
	pos.resize(cap)
	vel.resize(cap)
	rot.resize(cap)
	rot_to.resize(cap)
	spin.resize(cap)
	aim.resize(cap)
	start.resize(cap)
	dir.resize(cap)
	color.resize(cap)
	color_to.resize(cap)
	custom.resize(cap)
	age.resize(cap)
	life.resize(cap)
	home_from.resize(cap)
	wait_until.resize(cap)
	born.resize(cap)
	scale.resize(cap)
	size.resize(cap)
	size_to.resize(cap)
	phase.resize(cap)
	freq.resize(cap)
	glide.resize(cap)
	drawn_at.resize(cap)
	how.resize(cap)
	home_last.resize(cap)
	waited.resize(cap)
	peak.resize(cap)
	ride_u.resize(cap)
	ride_d.resize(cap)
	ride_h.resize(cap)
	ride_end.resize(cap)
	ride_off.resize(cap)
	spill.resize(cap)
	_alive_at.resize(cap)
	_free.resize(cap)
	for index: int in cap:
		_free[index] = cap - 1 - index
		render[index] = -1
	_kick_cells.clear()
	_render_count.resize(meshes.size())
	_render_owner.clear()
	for mesh: MultiMesh in meshes:
		var owners := PackedInt32Array()
		owners.resize(cap)
		_render_owner.append(owners)
		mesh.visible_instance_count = 0


func alive_count() -> int:
	return alive.size()


func free_count() -> int:
	return maxi(0, mini(_free.size(), limit - alive.size()))


func cell_index(cell: Vector2i) -> int:
	return cell.x + cell.y * grid_w


func cell_of_index(index: int) -> Vector2i:
	return Vector2i(index % grid_w, index / grid_w)


## A leaf that will leave src_cell (or a sink/source point) and fly to dst_cell
## (-1: into to_point and gone). Not drawn until it launches. Returns its slot or -1.
func add(kind_id: int, carried: int, src_cell: int, dst_cell: int, from_world: Vector3, to_point: Vector3, stroke_dir: Vector3, who: int, launch_rule: int, launch_at: float, clock: float) -> int:
	if free_count() <= 0:
		return -1
	var i := _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	_alive_at[i] = alive.size()
	alive.append(i)
	state[i] = WAIT
	kind[i] = kind_id
	rule[i] = launch_rule
	actor[i] = who
	units[i] = carried
	src[i] = src_cell
	dst[i] = dst_cell
	slot[i] = NO_SLOT
	homing[i] = 0
	hurry[i] = 0
	render[i] = -1
	park_frame[i] = 0
	start[i] = from_world
	pos[i] = from_world
	aim[i] = to_point
	dir[i] = stroke_dir
	vel[i] = Vector3.ZERO
	spin[i] = Vector3.ZERO
	age[i] = 0.0
	born[i] = clock
	wait_until[i] = launch_at
	glide[i] = 1.0
	scale[i] = 1.0
	how[i] = HOW_SCHEDULED
	waited[i] = 0.0
	return i


## Sends a mover that has not landed to another cell instead (a later batch took
## its destination's leaves away). A reserved landing is handed back by landing
## and taking off again in the same tick, so the view's units stay exact.
func retarget(i: int, new_dst: int, new_aim: Vector3) -> void:
	if slot[i] != NO_SLOT and dst[i] >= 0:
		var old := cell_of_index(dst[i])
		view.call("land", old, units[i], slot[i])
		view.call("take_launch", old, units[i])
	dst[i] = new_dst
	aim[i] = new_aim
	slot[i] = NO_SLOT
	if homing[i] == 1:
		homing[i] = 0
	if state[i] != WAIT:
		# A new leg from where it is, with the speed it has: it curves toward the new cell.
		var flat := Vector3(new_aim.x - pos[i].x, 0.0, new_aim.z - pos[i].z)
		var ft := Constants.LEAF_FLIGHT_TIME
		age[i] = 0.0
		life[i] = clampf(ft.x + ft.y * flat.length(), ft.z, ft.w)
		home_from[i] = minf(Constants.LEAF_HOME_AT * life[i], Constants.LEAF_RETARGET_HOME_MAX)
		hurry[i] = 0


## Splits rest units off this mover into a twin that keeps going where it was going
## (this one keeps the others, for the caller to send on). A waiting mover splits
## before anything is drawn; a flying one's twin grows out of it in mid-air and
## homes into a slot of its own, so nothing lands instantly. Needs a free mover:
## returns the twin, or -1 (and nothing changed) when the pool is full.
func split(i: int, rest: int, clock: float) -> int:
	if free_count() <= 0 or rest <= 0 or rest >= units[i]:
		return -1
	if state[i] == WAIT:
		var waiting := add(kind[i], rest, src[i], dst[i], start[i], aim[i], dir[i], actor[i], rule[i], wait_until[i], clock)
		born[waiting] = born[i]
		units[i] -= rest
		return waiting
	# A reserved landing is handed back; the twin and this one each reserve again.
	if slot[i] != NO_SLOT and dst[i] >= 0:
		var old := cell_of_index(dst[i])
		view.call("land", old, units[i], slot[i])
		view.call("take_launch", old, units[i])
	slot[i] = NO_SLOT
	homing[i] = 0
	var other := add(kind[i], rest, src[i], dst[i], pos[i], aim[i], dir[i], actor[i], rule[i], clock, clock)
	state[other] = state[i]
	vel[other] = vel[i]
	rot[other] = rot[i]
	rot_to[other] = rot_to[i]
	spin[other] = spin[i] * -0.8
	color[other] = color[i]
	color_to[other] = color_to[i]
	custom[other] = custom[i]
	species[other] = species[i]
	age[other] = age[i]
	life[other] = life[i]
	home_from[other] = home_from[i]
	born[other] = born[i]
	size[other] = size[i]
	size_to[other] = size_to[i]
	phase[other] = phase[i] + PI
	freq[other] = freq[i]
	glide[other] = glide[i]
	how[other] = how[i]
	waited[other] = waited[i]
	start[other] = start[i]
	drawn_at[other] = pos[i]
	ride_u[other] = ride_u[i]
	ride_d[other] = ride_d[i] + Constants.RAKE_RIDE_SPLIT_DEPTH
	ride_h[other] = ride_h[i]
	ride_end[other] = ride_end[i]
	ride_off[other] = ride_off[i]
	spill[other] = spill[i]
	# Grows out of the leaf it split from instead of appearing beside it.
	scale[other] = 0.0
	units[i] -= rest
	return other


## A sink leaf redirected from mid-air, or launched from a cell farther out than
## the sink's own, takes long enough that no tick moves it more than LEAF_MAX_STEP
## (the scripted paths peak at about twice their average speed).
func _bound_sink_life(i: int) -> void:
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	var far := pos[i].distance_to(aim[i])
	life[i] = maxf(life[i], 2.0 * far * tick / (Constants.LEAF_MAX_STEP * 0.7))


## Sends only take of this mover's units on to new_dst; the rest still reaches its
## old destination in a twin (split). Returns the twin, or -1 when the pool had no
## room to split (then nothing changed: the caller must not have claimed yet).
func retarget_part(i: int, take: int, new_dst: int, new_aim: Vector3, clock: float) -> int:
	var rest := units[i] - take
	if rest <= 0:
		retarget(i, new_dst, new_aim)
		return -1
	var other := split(i, rest, clock)
	if other < 0:
		return -1
	retarget(i, new_dst, new_aim)
	return other


## A mover that has not landed goes into a sink instead (a bag, a mower deck, off
## the yard's edge) because a later batch emptied the cell it was flying into. A
## waiting one will launch straight into it; a flying one turns from where it is,
## keeping its speed into the first part of the slurp.
func to_sink(i: int, sink_kind: int, point: Vector3) -> void:
	if slot[i] != NO_SLOT and dst[i] >= 0:
		var old := cell_of_index(dst[i])
		view.call("land", old, units[i], slot[i])
		view.call("take_launch", old, units[i])
	slot[i] = NO_SLOT
	homing[i] = 0
	hurry[i] = 0
	dst[i] = -1
	kind[i] = sink_kind
	aim[i] = point
	if state[i] == WAIT:
		rule[i] = R_SCHEDULED
		return
	start[i] = pos[i]
	age[i] = 0.0
	match sink_kind:
		K_EDGE:
			state[i] = FADE
			life[i] = Constants.LEAF_EDGE_FADE_SECONDS
		K_MULCH:
			state[i] = SINK
			life[i] = Constants.LEAF_MULCH_SECONDS
		_:
			state[i] = SINK
			life[i] = Constants.LEAF_BAG_SECONDS
	if state[i] == SINK:
		_bound_sink_life(i)
		spin[i] = Vector3(_rng.randf_range(-6.0, 6.0), _rng.randf_range(4.0, 9.0), _rng.randf_range(-6.0, 6.0))
	# It shrinks from the size it is now (it may still be growing out of the skin).
	size[i] = maxf(scale[i], 0.01)


## Lands this mover soon (the pool is full): a stiffer spring and an early home.
func rush(i: int) -> void:
	if state[i] == RIDE:
		_end_ride(i)
	if state[i] == FLY or state[i] == SLIDE:
		hurry[i] = 1
		home_from[i] = minf(home_from[i], age[i])


## Drops every mover without telling the view (a hard reset rebuilt it), except
## kicked flakes, which are handed back when asked.
func clear(return_kicks: bool) -> void:
	for index: int in range(alive.size() - 1, -1, -1):
		var i := alive[index]
		if return_kicks and kind[i] == K_KICK and slot[i] >= 0:
			view.call("return_slot", cell_of_index(src[i]), slot[i])
		_release(i)


## Takes the leaf off the view and sends it on its way.
func launch(i: int, beside: bool) -> void:
	var info: Dictionary = {}
	var k := kind[i]
	if k == K_SCATTER or k == K_DROP:
		# Out of a burst bag, or a change nothing explains: it appears (scales in).
		info = view.call("reserve_landing", cell_of_index(dst[i]), units[i])
		_adopt_landing(i, info)
		var spawn := start[i]
		_take_look(i, info, Transform3D(Basis.from_euler(Vector3(0.0, _rng.randf() * TAU, 0.0)), spawn))
		scale[i] = 0.0
	else:
		var cell := cell_of_index(src[i])
		# A flake kicked up from a slot this launch empties is in the air already:
		# it goes on as this leaf (its slot handed back first, then taken with the
		# launch), so the slot's look isn't drawn twice and the kick never lands on
		# a slot that is gone.
		if int(view.call("displayed_units", cell)) < units[i]:
			# Taking leaves the cell does not show yet (they are still flying in).
			overdrawn += 1
		var kicks := _kicks_in_way(src[i], units[i])
		for kick: int in kicks:
			view.call("return_slot", cell, slot[kick])
		info = view.call("take_launch", cell, units[i])
		var xform: Transform3D = info.get("xform", Transform3D(Basis(), start[i]))
		if not kicks.is_empty():
			var kick := int(kicks[0])
			xform = Transform3D(Basis.from_euler(rot[kick]).scaled(Vector3.ONE * maxf(scale[kick], 0.001)), pos[kick])
			info = {"xform": xform, "color": color[kick], "custom": custom[kick], "species": species[kick], "slot": 0}
		_take_look(i, info, xform)
		if not kicks.is_empty():
			# The kicked flake's own draw slot and motion carry over: no frame of two.
			var kick := int(kicks[0])
			_hand_over_draw(kick, i)
			vel[i] = vel[kick]
			spin[i] = spin[kick]
			handovers += 1
			# More than one of the slots this launch empties was in the air: each of
			# those flakes carries a share of the units on from where it is.
			var share := units[i] / kicks.size()
			for index: int in range(1, kicks.size()):
				if share > 0:
					_kick_joins(int(kicks[index]), i, share, beside)
			_release(kick)
		elif int(info.get("slot", -1)) < 0:
			scale[i] = 0.0
	launched += 1
	start[i] = pos[i]
	drawn_at[i] = pos[i]
	_start_flight(i, beside)


## A kicked flake whose slot a launch emptied becomes one of that launch's leaves
## (share units of mover i's), flying on from where it is.
func _kick_joins(j: int, i: int, share: int, beside: bool) -> void:
	if _kick_cells.has(src[j]):
		var left := int(_kick_cells[src[j]]) - 1
		if left <= 0:
			_kick_cells.erase(src[j])
		else:
			_kick_cells[src[j]] = left
	kind[j] = kind[i]
	units[j] = share
	units[i] -= share
	src[j] = src[i]
	dst[j] = dst[i]
	aim[j] = aim[i]
	dir[j] = dir[i]
	actor[j] = actor[i]
	rule[j] = rule[i]
	how[j] = how[i]
	born[j] = born[i]
	waited[j] = waited[i]
	slot[j] = NO_SLOT
	homing[j] = 0
	hurry[j] = 0
	start[j] = pos[j]
	handovers += 1
	_start_flight(j, beside)


## The flight a just-launched leaf starts on, by its kind.
func _start_flight(i: int, beside: bool) -> void:
	var k := kind[i]
	age[i] = 0.0
	phase[i] = _rng.randf() * TAU
	freq[i] = TAU * _rng.randf_range(Constants.LEAF_FLUTTER_HZ.x, Constants.LEAF_FLUTTER_HZ.y)
	peak[i] = pos[i].y
	var flat := dir[i]
	match k:
		K_BAG, K_MULCH:
			state[i] = SINK
			life[i] = Constants.LEAF_BAG_SECONDS * _rng.randf_range(0.85, 1.0) if k == K_BAG else Constants.LEAF_MULCH_SECONDS
			_bound_sink_life(i)
			spin[i] = Vector3(_rng.randf_range(-6.0, 6.0), _rng.randf_range(4.0, 9.0), _rng.randf_range(-6.0, 6.0))
		K_EDGE:
			state[i] = FADE
			life[i] = Constants.LEAF_EDGE_FADE_SECONDS
			vel[i] = flat * _rng.randf_range(1.2, 2.2) + Vector3(0.0, 0.6, 0.0)
		K_SCATTER:
			state[i] = FLY
			var out := aim[i] - pos[i]
			out.y = 0.0
			out = out.normalized() if out.length() > 0.01 else Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
			vel[i] = Vector3(0.0, _rng.randf_range(Constants.LEAF_SCATTER_UP.x, Constants.LEAF_SCATTER_UP.y), 0.0) + out * _rng.randf_range(Constants.LEAF_SCATTER_OUT.x, Constants.LEAF_SCATTER_OUT.y)
			spin[i] = Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-3.0, 3.0), _rng.randf_range(-8.0, 8.0))
			life[i] = Constants.LEAF_SCATTER_LIFE.x
			home_from[i] = Constants.LEAF_SCATTER_LIFE.y
		K_DROP:
			state[i] = FLY
			life[i] = Constants.LEAF_DROP_LIFE.x
			home_from[i] = Constants.LEAF_DROP_LIFE.y
			spin[i] = Vector3(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-2.0, 2.0), _rng.randf_range(-3.0, 3.0))
		_:
			state[i] = FLY
			if not beside and (k == K_RAKE or k == K_CREW) and _begin_ride(i):
				return
			_aim_launch(i, beside)


## A leaf the tines just reached while they drive rides ahead of them in the
## windrow instead of flying off on its own: it bunches against the tines, the
## berm stacking higher the more leaves ride it, rolls over and over, and is let
## go at the end of the drive (or once its own landing spot is behind the tines,
## or early, spilling over the top). False when there is no lowered head to ride
## or its landing spot is already behind the tines.
func _begin_ride(i: int) -> bool:
	var head: Dictionary = _heads_now.get(actor[i], {})
	if head.is_empty() or not bool(head["down"]):
		return false
	var fwd: Vector3 = head["fwd"]
	var mid: Vector3 = head["mid"]
	if (aim[i] - mid).dot(fwd) < Constants.RAKE_RIDE_DEPTH.y:
		return false
	var right: Vector3 = head["right"]
	var half := float(head["half"])
	ride_u[i] = clampf((pos[i] - mid).dot(right), -half, half) * _rng.randf_range(Constants.RAKE_RIDE_SPREAD, 1.0)
	ride_d[i] = _rng.randf_range(Constants.RAKE_RIDE_DEPTH.x, Constants.RAKE_RIDE_DEPTH.y)
	ride_h[i] = _rng.randf() * Constants.RAKE_RIDE_STACK
	spill[i] = 1 if _rng.randf() < Constants.RAKE_RIDE_SPILL else 0
	ride_end[i] = _rng.randf_range(Constants.RAKE_RIDE_SPILL_SECONDS.x, Constants.RAKE_RIDE_SPILL_SECONDS.y) if spill[i] == 1 else Constants.RAKE_RIDE_MAX
	ride_off[i] = pos[i] - _ride_point(i, head)
	state[i] = RIDE
	spin[i] = Vector3(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-2.0, 2.0), _rng.randf_range(-3.0, 3.0))
	rode += 1
	return true


## Where on the berm ahead of the head a riding leaf sits now.
func _ride_point(i: int, head: Dictionary) -> Vector3:
	var fwd: Vector3 = head["fwd"]
	var right: Vector3 = head["right"]
	var at: Vector3 = (head["mid"] as Vector3) + fwd * ride_d[i] + right * ride_u[i]
	var fill := clampf(float(_riders.get(actor[i], 0)) / float(Constants.RAKE_RIDE_FULL), 0.3, 1.0)
	# Deeper in the berm (nearer the tines) sits higher: leaves pile against them.
	var lean := 1.0 - (ride_d[i] - Constants.RAKE_RIDE_DEPTH.x) / maxf(Constants.RAKE_RIDE_DEPTH.y - Constants.RAKE_RIDE_DEPTH.x, 0.01)
	at.y = float(view.call("surface_y", Vector2(at.x, at.z))) + LIE_LIFT + ride_h[i] * fill * (0.4 + 0.6 * lean)
	return at


## One tick of a riding leaf: locked to its spot on the berm (easing out of where
## it was picked up), tumbling, until it is let go.
func _ride(i: int, dt: float) -> void:
	var a := age[i] + dt
	age[i] = a
	var head: Dictionary = _heads_now.get(actor[i], {})
	if head.is_empty() or not bool(head["down"]) or a >= ride_end[i]:
		_end_ride(i)
		return
	var point := _ride_point(i, head)
	var fwd: Vector3 = head["fwd"]
	if (aim[i] - point).dot(fwd) < Constants.RAKE_RIDE_DROP_MARGIN:
		# Its own spot in the windrow: dropped off the tines there.
		_end_ride(i)
		return
	# Closing on its spot: quickly when close, but a leaf the tines swept from
	# farther back slides there along the lawn, never faster than RAKE_RIDE_SLIDE.
	var off := ride_off[i]
	var gap := off.length()
	if gap > 0.0001:
		var close := minf(gap * (1.0 - exp(-Constants.RAKE_RIDE_STIFF * dt)), Constants.RAKE_RIDE_SLIDE * dt)
		ride_off[i] = off * ((gap - close) / gap)
	var p := point + ride_off[i]
	var step := p - pos[i]
	if step.length() > Constants.LEAF_MAX_STEP:
		p = pos[i] + step.normalized() * Constants.LEAF_MAX_STEP
	var head_vel: Vector3 = head.get("vel", Vector3.ZERO)
	vel[i] = (p - pos[i]) / maxf(dt, 0.0001)
	# Rolled over and over by the shove, flipping its pale side up now and then.
	var roll := Vector2(head_vel.x, head_vel.z).length() / Constants.RAKE_RIDE_ROLL_RADIUS
	var r := rot[i] + spin[i] * dt
	r.x += roll * dt
	r.z += sin(phase[i] + a * Constants.RAKE_RIDE_WOBBLE.x) * Constants.RAKE_RIDE_WOBBLE.y * dt
	rot[i] = r
	pos[i] = p
	if scale[i] < size[i]:
		scale[i] = minf(size[i], scale[i] + size[i] * dt / Constants.LEAF_SKIN_IN_SECONDS)
	else:
		scale[i] = size[i]
	_draw(i)


## Lets a riding leaf go: it carries on with some of the head's speed and the
## flight it would have had from here (a spill hops up over the top).
func _end_ride(i: int) -> void:
	var head: Dictionary = _heads_now.get(actor[i], {})
	var head_vel: Vector3 = head.get("vel", Vector3.ZERO) if not head.is_empty() else Vector3.ZERO
	head_vel.y = 0.0
	if head_vel.length() > Constants.RAKE_RIDE_HEAD_SPEED_MAX:
		head_vel = head_vel.normalized() * Constants.RAKE_RIDE_HEAD_SPEED_MAX
	state[i] = FLY
	age[i] = 0.0
	_aim_launch(i, false)
	var carry := Constants.RAKE_RIDE_CARRY
	var aimed := vel[i]
	vel[i] = Vector3(lerpf(aimed.x, head_vel.x, carry), aimed.y * Constants.RAKE_RIDE_CARRY_UP, lerpf(aimed.z, head_vel.z, carry))
	if spill[i] == 1:
		vel[i].y = _rng.randf_range(Constants.RAKE_RIDE_SPILL_HOP.x, Constants.RAKE_RIDE_SPILL_HOP.y)
	else:
		vel[i].y = minf(vel[i].y, _rng.randf_range(Constants.RAKE_RIDE_SETTLE_HOP.x, Constants.RAKE_RIDE_SETTLE_HOP.y))


## The airborne kicks holding slots that taking units off this cell empties,
## highest slot first (usually none, at most a few).
func _kicks_in_way(cell: int, taking: int) -> Array:
	var found: Array = []
	if not _kick_cells.has(cell):
		return found
	var shown := int(view.call("displayed_units", cell_of_index(cell)))
	var before := int(view.call("hero_count", shown))
	var after := int(view.call("hero_count", shown - taking))
	if after >= before:
		return found
	for j: int in alive:
		if kind[j] != K_KICK or src[j] != cell or state[j] == PARK or state[j] == FADE:
			continue
		if slot[j] >= after and slot[j] < before:
			found.append(j)
	var slots := slot
	found.sort_custom(func(a: int, b: int) -> bool: return slots[a] > slots[b])
	return found


## Mover to takes over mover from's instance in the species MultiMesh (the same flake).
func _hand_over_draw(from: int, to: int) -> void:
	render[to] = render[from]
	species[to] = species[from]
	if render[from] >= 0 and not meshes.is_empty():
		_render_owner[clampi(species[from], 0, meshes.size() - 1)][render[from]] = to
	render[from] = -1


## The kicked flake k of a cell hops up and comes back to the same slot.
func add_kick(cell: Vector2i, k: int, push: Vector3, clock: float) -> int:
	var i := add(K_KICK, 0, cell_index(cell), cell_index(cell), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 0, R_SCHEDULED, clock, clock)
	if i < 0:
		return -1
	_kick_cells[src[i]] = int(_kick_cells.get(src[i], 0)) + 1
	var info: Dictionary = view.call("take_slot", cell, k)
	var xform: Transform3D = info.get("xform", Transform3D())
	_take_look(i, info, xform)
	color_to[i] = color[i]
	size_to[i] = size[i]
	rot_to[i] = rot[i]
	slot[i] = k
	state[i] = FLY
	start[i] = xform.origin
	drawn_at[i] = xform.origin
	var flat := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)) * 0.6 + Vector3(push.x, 0.0, push.z) * 0.25
	vel[i] = flat + Vector3(0.0, _rng.randf_range(Constants.LEAF_KICK_HOP.x, Constants.LEAF_KICK_HOP.y), 0.0)
	spin[i] = Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-4.0, 4.0), _rng.randf_range(-6.0, 6.0))
	life[i] = _rng.randf_range(Constants.LEAF_KICK_TIME.x, Constants.LEAF_KICK_TIME.y)
	home_from[i] = Constants.LEAF_HOME_AT * life[i]
	phase[i] = _rng.randf() * TAU
	freq[i] = TAU * _rng.randf_range(Constants.LEAF_FLUTTER_HZ.x, Constants.LEAF_FLUTTER_HZ.y)
	launched += 1
	return i


## Airborne kicked flakes (each one is a flake hidden from the view).
func kick_count() -> int:
	var count := 0
	for i: int in alive:
		if kind[i] == K_KICK and state[i] != PARK and state[i] != FADE:
			count += 1
	return count


func count_state(which: int) -> int:
	var count := 0
	for i: int in alive:
		if state[i] == which:
			count += 1
	return count


## Units each cell will still receive from movers, less what waiting movers will
## still take out of it: the view's pending claims, cell index -> units.
func ledger() -> Dictionary:
	var out: Dictionary = {}
	for i: int in alive:
		if kind[i] == K_KICK:
			continue
		if state[i] == WAIT and src[i] >= 0 and kind[i] != K_SCATTER and kind[i] != K_DROP:
			out[src[i]] = int(out.get(src[i], 0)) - units[i]
		if dst[i] >= 0 and (state[i] == WAIT or state[i] == FLY or state[i] == SLIDE or state[i] == RIDE):
			out[dst[i]] = int(out.get(dst[i], 0)) + units[i]
	return out


## One physics tick. heads: actor -> {mid, fwd, right, half, down}; fars: actor ->
## {mid, fwd, t} (where and when that actor's head reached the end of its drive).
func step(dt: float, clock: float, heads: Dictionary, fars: Dictionary) -> void:
	landings.clear()
	_heads_now = heads
	_riders.clear()
	for i: int in alive:
		if state[i] == RIDE:
			_riders[actor[i]] = int(_riders.get(actor[i], 0)) + 1
	var frame := Engine.get_physics_frames()
	var omega := Constants.LEAF_SPRING
	var ray_budget := rays_per_tick if space != null else 0
	var index := 0
	while index < alive.size():
		var i := alive[index]
		var s := state[i]
		if s == RIDE:
			_ride(i, dt)
			index += 1
			continue
		if s == WAIT:
			if _wait_done(i, clock, heads, fars):
				waited[i] = clock - born[i]
				launch(i, rule[i] == R_BESIDE)
				_draw(i)
			index += 1
			continue
		if s == PARK:
			if frame >= park_frame[i]:
				_release(i)
				continue
			if slot[i] >= 0:
				var cell := cell_of_index(src[i] if kind[i] == K_KICK else dst[i])
				var at: Transform3D = view.call("slot_world", cell, slot[i])
				pos[i] = at.origin
				rot[i] = at.basis.get_euler()
				scale[i] = at.basis.get_scale().x
				size[i] = scale[i]
			_draw(i)
			index += 1
			continue
		var a := age[i] + dt
		age[i] = a
		max_age = maxf(max_age, a)
		if s == SINK or s == FADE:
			if _scripted(i, dt, a):
				if s == SINK or kind[i] == K_EDGE:
					_finish(i, pos[i])
				_release(i)
				continue
			_draw(i)
			index += 1
			continue
		# FLY or SLIDE: the leaf simulation.
		var p := pos[i]
		var v := vel[i]
		var r := rot[i]
		var w := spin[i]
		var target := Vector3.INF
		var target_vel := Vector3.ZERO
		var blend := 0.0
		if homing[i] == 0 and (a >= home_from[i] or a >= Constants.LEAF_SETTLE_MAX):
			_begin_home(i)
			home_last[i] = _home_point(i)
		if homing[i] == 1:
			target = _home_point(i)
			# Track the target's own motion (the mound rising) so the leaf doesn't lag it.
			target_vel = (target - home_last[i]) / maxf(dt, 0.0001)
			home_last[i] = target
			blend = clampf((a - home_from[i]) / Constants.LEAF_HOME_BLEND, 0.0, 1.0)
			if hurry[i] == 1:
				blend = 1.0
		var basis := Basis.from_euler(r)
		var n := basis.y
		var vn := v.dot(n)
		var acc := GRAVITY - n * (Constants.LEAF_DRAG_NORMAL * vn) - (v - n * vn) * (Constants.LEAF_DRAG_TANGENT * glide[i])
		if blend > 0.0:
			var stiff := omega * (2.5 if hurry[i] == 1 else 1.0)
			var spring := (target - p) * (stiff * stiff) + (target_vel - v) * (2.0 * stiff)
			acc = acc.lerp(spring, blend)
		v += acc * dt
		var speed := v.length()
		if s == FLY:
			# Flutter about the long axis: a pendulum the air keeps nudging.
			var tilt := wrapf(r.z, -PI * 0.5, PI * 0.5)
			phase[i] += freq[i] * dt
			w.z += (-Constants.LEAF_FLUTTER_K * tilt - 2.0 * w.z + Constants.LEAF_FLUTTER_KICK * sin(phase[i])) * dt
			if speed < Constants.LEAF_TUMBLE_SPEED:
				var pitch := wrapf(r.x, -PI * 0.5, PI * 0.5)
				w.x += (-Constants.LEAF_FLUTTER_K * 0.7 * pitch - 3.0 * w.x) * dt
		var move := v * dt
		var length := move.length()
		if length > Constants.LEAF_MAX_STEP:
			move *= Constants.LEAF_MAX_STEP / length
		# Walls and fences: a fast leaf that would go through one stops against it.
		# (Not while homing: the spring delivers it, even to a cell against a wall.)
		if ray_budget > 0 and homing[i] == 0 and speed > Constants.LEAF_RAY_SPEED and length > 0.001:
			ray_budget -= 1
			rays += 1
			var query := PhysicsRayQueryParameters3D.create(p, p + move)
			query.collide_with_areas = false
			var hit := space.intersect_ray(query)
			if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.5:
				ray_hits += 1
				var normal: Vector3 = hit["normal"]
				move = (hit["position"] as Vector3) + normal * 0.02 - p
				v = (v - normal * (2.0 * v.dot(normal))) * 0.25
		p += move
		var ground := float(view.call("surface_y", Vector2(p.x, p.z))) + LIE_LIFT
		if p.y <= ground:
			p.y = ground
			if v.y < -Constants.LEAF_BOUNCE_SPEED and s == FLY:
				v.y = -v.y * Constants.LEAF_RESTITUTION
				v.x *= 0.7
				v.z *= 0.7
				w *= 0.5
			else:
				v.y = maxf(v.y, 0.0)
				s = SLIDE
				var grip := exp(-Constants.LEAF_FRICTION * dt * (1.0 - blend))
				v.x *= grip
				v.z *= grip
				var flat_rate := 1.0 - exp(-12.0 * dt)
				r.x = lerp_angle(r.x, 0.0 if absf(wrapf(r.x, -PI, PI)) < PI * 0.5 else PI, flat_rate)
				r.z = lerp_angle(r.z, 0.0 if absf(wrapf(r.z, -PI, PI)) < PI * 0.5 else PI, flat_rate)
				w *= exp(-8.0 * dt)
		elif s == SLIDE and p.y > ground + 0.05:
			s = FLY
		# Never more than LEAF_MAX_STEP a tick, the ground's push included (a leaf
		# meeting the side of a pile climbs it over a few ticks).
		var total := p - pos[i]
		if total.length() > Constants.LEAF_MAX_STEP:
			p = pos[i] + total.normalized() * Constants.LEAF_MAX_STEP
		r += w * dt
		if blend > 0.0:
			var turn := blend * (1.0 - exp(-12.0 * dt))
			var goal := rot_to[i]
			r = Vector3(lerp_angle(r.x, goal.x, turn), lerp_angle(r.y, goal.y, turn), lerp_angle(r.z, goal.z, turn))
			color[i] = color[i].lerp(color_to[i], turn)
			size[i] = lerpf(size[i], size_to[i], turn)
		if scale[i] < size[i]:
			scale[i] = minf(size[i], scale[i] + size[i] * dt / Constants.LEAF_SKIN_IN_SECONDS)
		else:
			scale[i] = size[i]
		pos[i] = p
		vel[i] = v
		if trace:
			peak[i] = maxf(peak[i], p.y)
		rot[i] = r
		spin[i] = w
		state[i] = s
		if homing[i] == 1:
			var gap := p.distance_to(target)
			# A rushed leaf (the pool is full) may land a little farther out, never
			# more than the handoff tolerance.
			var settled := blend >= 1.0 and gap < (LATE_LAND_DIST if hurry[i] == 1 else LAND_DIST) and (v - target_vel).length() < LAND_SPEED
			# Near the end of its time a leaf close enough lands even if its slot is
			# still moving (a mound rising frame by frame under it).
			if not settled and a >= Constants.LEAF_SETTLE_MAX - LATE_LAND_WINDOW and gap < LATE_LAND_DIST:
				settled = true
			if settled or a >= Constants.LEAF_SETTLE_MAX:
				if not settled:
					snaps += 1
					max_snap = maxf(max_snap, gap)
					if gap > Constants.LEAF_SNAP_MAX:
						pops += 1
				max_handoff = maxf(max_handoff, gap)
				if _land(i, target, frame):
					index += 1
				continue
		_draw(i)
		index += 1


## Draws every drawn mover where it is now (headless: nothing).
func _draw(i: int) -> void:
	var moved := pos[i].distance_to(drawn_at[i])
	max_step = maxf(max_step, moved)
	drawn_at[i] = pos[i]
	if meshes.is_empty():
		return
	var species_id := clampi(species[i], 0, meshes.size() - 1)
	var mesh := meshes[species_id]
	var fresh := render[i] < 0
	if fresh:
		var count := _render_count[species_id]
		render[i] = count
		_render_owner[species_id][count] = i
		_render_count[species_id] = count + 1
		mesh.visible_instance_count = count + 1
	var basis := Basis.from_euler(rot[i]).scaled(Vector3.ONE * maxf(scale[i], 0.001))
	mesh.set_instance_transform(render[i], Transform3D(basis, pos[i]))
	mesh.set_instance_color(render[i], color[i])
	if fresh:
		mesh.set_instance_custom_data(render[i], custom[i])
		mesh.reset_instance_physics_interpolation(render[i])


## When a waiting leaf goes: its time came, or the rake head swept past it.
func _wait_done(i: int, clock: float, heads: Dictionary, fars: Dictionary) -> bool:
	if clock >= wait_until[i]:
		if rule[i] != R_SCHEDULED and how[i] != HOW_WAVE:
			how[i] = HOW_TIMEOUT
		return true
	if rule[i] == R_SCHEDULED:
		return false
	var who := actor[i]
	if heads.has(who):
		var head: Dictionary = heads[who]
		if bool(head["down"]):
			var ahead := (start[i] - (head["mid"] as Vector3)).dot(head["fwd"] as Vector3)
			if ahead <= 0.0:
				how[i] = HOW_CONTACT
				if trace and rule[i] == R_TINE:
					tine_launches.append({"t": clock, "at": start[i], "actor": who})
				return true
	if fars.has(who):
		var far: Dictionary = fars[who]
		if float(far["t"]) >= born[i] - 0.05:
			# The head finished its drive short of this leaf: the pressure wave takes it.
			var beyond := maxf(0.0, (start[i] - (far["mid"] as Vector3)).dot(far["fwd"] as Vector3))
			wait_until[i] = minf(wait_until[i], float(far["t"]) + beyond / Constants.LEAF_SWEEP_SPEED)
			how[i] = HOW_WAVE
			return clock >= wait_until[i]
	return false


## Launch velocity aimed to land near the destination after a flight of T seconds.
func _aim_launch(i: int, beside: bool) -> void:
	var p := pos[i]
	var goal := aim[i]
	var flat := Vector3(goal.x - p.x, 0.0, goal.z - p.z)
	var dist := flat.length()
	var ft := Constants.LEAF_FLIGHT_TIME
	var t := clampf(ft.x + ft.y * dist, ft.z, ft.w)
	var k := kind[i]
	var horizontal := flat / t * Constants.LEAF_AIM_BOOST if dist > 0.001 else Vector3.ZERO
	var stroke := dir[i]
	var up := _rng.randf_range(Constants.LEAF_RAKE_HOP.x, Constants.LEAF_RAKE_HOP.y)
	match k:
		K_HAND:
			up *= Constants.LEAF_HAND_HOP
		K_BLOWER:
			horizontal += stroke * _rng.randf_range(Constants.LEAF_BLOWER_SPEED.x, Constants.LEAF_BLOWER_SPEED.y) * 0.25
			up = _rng.randf_range(Constants.LEAF_BLOWER_HOP.x, Constants.LEAF_BLOWER_HOP.y)
			glide[i] = Constants.LEAF_BLOWER_GLIDE
		K_CORRECTION:
			up *= 0.3
		_:
			horizontal += stroke * _rng.randf_range(Constants.LEAF_RAKE_PUSH.x, Constants.LEAF_RAKE_PUSH.y) * 0.5
	if beside:
		horizontal *= Constants.LEAF_BESIDE_SPEED
		up *= Constants.LEAF_BESIDE_HOP
	vel[i] = horizontal + Vector3(0.0, up, 0.0)
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var tumble := _rng.randf_range(Constants.LEAF_RAKE_SPIN.x, Constants.LEAF_RAKE_SPIN.y) * (0.4 if k == K_HAND or k == K_CORRECTION else 1.0)
	# Tumbling end over end along the stroke, so the pale underside flashes.
	spin[i] = Vector3(tumble * side, _rng.randf_range(-2.5, 2.5), _rng.randf_range(-4.0, 4.0))
	life[i] = t
	home_from[i] = Constants.LEAF_HOME_AT * t


## Asks the view where this leaf will lie, and starts steering it there.
func _begin_home(i: int) -> void:
	homing[i] = 1
	if kind[i] == K_KICK:
		return
	if slot[i] == NO_SLOT and dst[i] >= 0:
		var info: Dictionary = view.call("reserve_landing", cell_of_index(dst[i]), units[i])
		_adopt_landing(i, info)


func _adopt_landing(i: int, info: Dictionary) -> void:
	slot[i] = int(info.get("slot", -1))
	var xform: Transform3D = info.get("xform", Transform3D(Basis(), aim[i]))
	if slot[i] < 0:
		aim[i] = xform.origin
	rot_to[i] = xform.basis.orthonormalized().get_euler()
	size_to[i] = xform.basis.get_scale().x
	color_to[i] = info.get("color", color[i])


## Where a homing leaf is steering to right now (the pile under it may be growing).
func _home_point(i: int) -> Vector3:
	if slot[i] >= 0:
		var cell := cell_of_index(src[i] if kind[i] == K_KICK else dst[i])
		var at: Transform3D = view.call("slot_world", cell, slot[i])
		return at.origin
	var point := aim[i]
	point.y = float(view.call("surface_y", Vector2(point.x, point.z))) + LIE_LIFT
	return point


## Hands the leaf back to the view. True when the mover stays (parked or diving).
func _land(i: int, at: Vector3, frame: int) -> bool:
	pos[i] = at
	if kind[i] == K_KICK:
		var home := cell_of_index(src[i])
		view.call("return_slot", home, slot[i])
		if slot[i] >= int(view.call("hero_count", int(view.call("displayed_units", home)))):
			# The view eased its flakes away under it (a morph): into the litter.
			kicks_faded += 1
			state[i] = FADE
			age[i] = 0.0
			life[i] = Constants.LEAF_SKIN_OUT_SECONDS
			vel[i] = Vector3(0.0, -0.02 / Constants.LEAF_SKIN_OUT_SECONDS, 0.0)
			_draw(i)
			return true
		state[i] = PARK
		park_frame[i] = frame + 1
		_draw(i)
		return true
	var cell := cell_of_index(dst[i])
	var drawn_from := int(view.call("land", cell, units[i], slot[i]))
	landed += 1
	landings.append([at, dst[i], units[i]])
	_finish(i, at)
	if slot[i] >= 0:
		state[i] = PARK
		park_frame[i] = mini(drawn_from, frame + Constants.LEAF_PARK_TICKS)
		var exact: Transform3D = view.call("slot_world", cell, slot[i])
		pos[i] = exact.origin
		rot[i] = exact.basis.get_euler()
		scale[i] = exact.basis.get_scale().x
		_draw(i)
		return true
	# Into the litter skin: it sinks a little and shrinks away.
	state[i] = FADE
	age[i] = 0.0
	life[i] = Constants.LEAF_SKIN_OUT_SECONDS
	vel[i] = Vector3(0.0, -0.02 / Constants.LEAF_SKIN_OUT_SECONDS, 0.0)
	start[i] = at
	units[i] = 0
	dst[i] = -1
	_draw(i)
	return true


## Scripted motion: into a bag or a mower deck, off the yard's edge, into the skin.
## True when it is over.
func _scripted(i: int, dt: float, a: float) -> bool:
	var t := clampf(a / maxf(life[i], 0.001), 0.0, 1.0)
	var k := kind[i]
	# A leaf that was flying when it was sent here carries its speed into the first
	# part of the slurp (zero at both ends, so it still starts and ends exactly).
	var carry := vel[i] * (t * life[i]) * (1.0 - t) * (1.0 - t)
	if state[i] == SINK and k == K_BAG:
		var ease := t * t * (3.0 - 2.0 * t)
		var center := start[i].lerp(aim[i], ease)
		var spiral := Constants.LEAF_BAG_SPIRAL
		var angle := phase[i] + t * TAU * spiral.y
		# The spiral's offset is measured from where it starts, so the leaf leaves its
		# slot without a jump and closes on the mouth.
		var round_now := Vector3(cos(angle), 0.0, sin(angle)) * spiral.x * (1.0 - t)
		var round_start := Vector3(cos(phase[i]), 0.0, sin(phase[i])) * spiral.x * (1.0 - ease)
		pos[i] = center + round_now - round_start + Vector3(0.0, sin(t * PI) * spiral.z, 0.0) + carry
		scale[i] = size[i] * (1.0 - (1.0 - Constants.LEAF_BAG_SHRINK) * t)
	elif state[i] == SINK:
		pos[i] = start[i].lerp(aim[i], t * t) + carry
		scale[i] = size[i] * (1.0 - t)
	else:
		pos[i] += vel[i] * dt
		vel[i] *= exp(-3.0 * dt)
		scale[i] = size[i] * (1.0 - t)
	rot[i] += spin[i] * dt
	if t >= 1.0:
		if state[i] == SINK:
			sinks_done += 1
		return true
	return false


func _take_look(i: int, info: Dictionary, xform: Transform3D) -> void:
	pos[i] = xform.origin
	rot[i] = xform.basis.orthonormalized().get_euler()
	var flake_size := xform.basis.get_scale().x
	if flake_size < 0.01:
		flake_size = 0.2
	size[i] = flake_size
	scale[i] = flake_size
	color[i] = info.get("color", Color(0.9, 0.5, 0.2))
	custom[i] = info.get("custom", Color(0.6, 0.2, 0.1))
	species[i] = clampi(int(info.get("species", 0)), 0, 2)
	if not info.has("slot") or int(info["slot"]) >= 0:
		color_to[i] = color[i]
		size_to[i] = size[i]
		rot_to[i] = rot[i]


func _finish(i: int, at: Vector3) -> void:
	if not trace:
		return
	finished.append({"kind": KIND_NAMES[kind[i]], "start": start[i], "end": at, "dir": dir[i], "age": age[i], "rule": rule[i], "how": how[i], "waited": waited[i], "peak": peak[i], "dst": dst[i], "units": units[i], "src": src[i]})


func _release(i: int) -> void:
	if render[i] >= 0 and not meshes.is_empty():
		var species_id := clampi(species[i], 0, meshes.size() - 1)
		var mesh := meshes[species_id]
		var last := _render_count[species_id] - 1
		var at := render[i]
		if at != last:
			var mover := _render_owner[species_id][last]
			_render_owner[species_id][at] = mover
			render[mover] = at
			mesh.set_instance_transform(at, mesh.get_instance_transform(last))
			mesh.set_instance_color(at, mesh.get_instance_color(last))
			mesh.set_instance_custom_data(at, mesh.get_instance_custom_data(last))
			mesh.reset_instance_physics_interpolation(at)
		_render_count[species_id] = last
		mesh.visible_instance_count = last
	render[i] = -1
	if kind[i] == K_KICK and _kick_cells.has(src[i]):
		var left := int(_kick_cells[src[i]]) - 1
		if left <= 0:
			_kick_cells.erase(src[i])
		else:
			_kick_cells[src[i]] = left
	state[i] = WAIT
	var spot := _alive_at[i]
	var tail := alive[alive.size() - 1]
	alive[spot] = tail
	_alive_at[tail] = spot
	alive.resize(alive.size() - 1)
	_free.append(i)
