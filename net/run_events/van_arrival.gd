extends Node3D

## Authority: local, cosmetic only. The NICE BOYS pull up in their van (docs/GAME.md,
## "2026-11-02, the Courtesy Shuttle"). Every peer runs one, made by the run
## director, and times it from the director's replicated phase and the shared
## server clock, so it needs no network traffic of its own:
##   - over the warning's last Constants.VAN_ARRIVE_SECONDS the van drives in down
##     the street's far lane (props/nice_van.gd arrival_curve), honks, brakes with
##     its nose dipping and its brake lights on, and stops at the curb as the crew
##     arrives, with a door slam
##   - it stays parked through the chase, dome pulsing
##   - if someone is caught, the ride (net/components/ride.gd, Rides/Van) starts
##     from exactly where and how it is parked, and this one steps aside
##   - if the crew gives up, it pulls away down the street and is gone
## Where it parks is the director's van_park_point(), where the ride starts.

const _NiceVan = preload("res://props/nice_van.gd")
const _Strings = preload("res://ui/strings.gd")
## The director's phases (net/run_events/director.gd Phase).
const QUIET: int = 0
const WARNING: int = 1
const CHASE: int = 2

enum Show { NONE, ARRIVING, PARKED, LEAVING }

var _holder: Node3D
var _look: Node3D
var _show: int = Show.NONE
var _curve: Curve3D
var _park_pose: Transform3D
var _arrive_start: float = 0.0
var _leave_start: float = 0.0
var _leave_from: Transform3D
var _leave_speed: float = 0.0
var _played: Dictionary = {}
var _solid_layers: Vector2i = Vector2i(1, 1)


func _ready() -> void:
	add_to_group("van_arrival")
	# A Node3D under the plain-Node director: its own transform is its global one.
	top_level = true


## The van as shown now (VanLook), or null when none is out. For tests.
func van_look() -> Node3D:
	return _look if _show != Show.NONE else null


## "arriving", "parked", "leaving" or "".
func state_name() -> String:
	match _show:
		Show.ARRIVING:
			return "arriving"
		Show.PARKED:
			return "parked"
		Show.LEAVING:
			return "leaving"
	return ""


func _physics_process(_delta: float) -> void:
	var director := get_parent()
	if director == null or not director.has_method("phase") or Net.current_state() != Net.State.IN_SESSION:
		return
	var phase := int(director.call("phase"))
	var now := Net.server_time()
	if _ride_took_over(director):
		_clear()
		return
	match phase:
		WARNING:
			var start := float(director.call("arrival_time")) - Constants.VAN_ARRIVE_SECONDS
			if now >= start:
				_arrive(director, start, now)
		CHASE:
			# The chase starts when the van parks (a client that joined mid-chase
			# finds it parked).
			_arrive(director, float(director.call("phase_started_at")) - Constants.VAN_ARRIVE_SECONDS, now)
		_:
			if _show == Show.ARRIVING or _show == Show.PARKED:
				# From wherever it is (the call can be off before it parks), at the
				# speed it had, on down the street.
				_leave_from = _holder.global_transform
				var motion := _look.get_node_or_null("Motion")
				_leave_speed = maxf(0.0, float(motion.get("speed"))) if motion != null and _show == Show.ARRIVING else 0.0
				_show = Show.LEAVING
				_leave_start = now
				_set_solid(false)
				_sound("van", "leave", now, _leave_start)
			if _show == Show.LEAVING:
				_leave(now)


## Pulling up: started at server time start, now is now.
func _arrive(director: Node, start: float, now: float) -> void:
	if _show == Show.LEAVING:
		_clear()
	if _show == Show.NONE:
		_make(director)
		_arrive_start = start
		_played.clear()
		_show = Show.ARRIVING
		_set_solid(false)
	var t := now - _arrive_start
	var along := _NiceVan.arrive_progress(t)
	_place(_NiceVan.pose(_curve, along), _show == Show.ARRIVING and t <= 0.05)
	_sound("van", "honk", now, _arrive_start)
	_sound("skid", "brake", now, _arrive_start + _NiceVan.brake_time(), -8.0)
	if t >= Constants.VAN_ARRIVE_SECONDS and _show == Show.ARRIVING:
		_show = Show.PARKED
		_set_solid(true)
		_sound("door_slam", "door", now, _arrive_start + Constants.VAN_ARRIVE_SECONDS)


func _leave(now: float) -> void:
	var t := now - _leave_start
	if t >= Constants.VAN_LEAVE_SECONDS:
		_clear()
		return
	var distance := _leave_speed * t + 0.5 * Constants.VAN_LEAVE_ACCEL * t * t
	_place(Transform3D(_leave_from.basis, _leave_from.origin + _NiceVan.STREET_DIR * distance), false)


## Someone was caught: the ride's van, built where this one is parked, leaves with
## them. Once it has started (or stands right here), this one is not needed.
func _ride_took_over(director: Node) -> bool:
	if _show == Show.NONE:
		return false
	var ride := director.get_parent().get_node_or_null("Rides/Van")
	if ride == null:
		return false
	if bool(ride.call("is_riding")):
		return true
	return _show == Show.PARKED and ride.call("body_position").distance_to(_park_pose.origin) < 0.5


func _make(director: Node) -> void:
	var park: Vector3 = director.call("van_park_point")
	_curve = _NiceVan.arrival_curve(park)
	_park_pose = _NiceVan.pose(_curve, 1.0)
	if _holder == null:
		_holder = Node3D.new()
		_holder.name = "ArrivingVan"
		add_child(_holder)
	_look = _NiceVan.build(_holder)
	# The same floating name the ride's van wears (ride.gd), so nothing changes
	# when the ride takes over.
	var label := Label3D.new()
	label.name = "Label"
	label.text = str(_Strings.UI["van_label"])
	label.font_size = 72
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 3.9, 0.0)
	_look.add_child(label)
	var solid := _look.get_node_or_null("Solid") as CollisionObject3D
	if solid != null:
		_solid_layers = Vector2i(solid.collision_layer, solid.collision_mask)
	_holder.visible = true


func _place(pose: Transform3D, snap: bool) -> void:
	_holder.global_transform = pose
	if snap:
		_holder.reset_physics_interpolation()
		var motion := _look.get_node_or_null("Motion")
		if motion != null:
			motion.call("settle")


## Driving, it passes through people rather than shoving them; parked, it is solid.
func _set_solid(solid: bool) -> void:
	var body := _look.get_node_or_null("Solid") as CollisionObject3D if _look != null else null
	if body == null:
		return
	body.collision_layer = _solid_layers.x if solid else 0
	body.collision_mask = _solid_layers.y if solid else 0


## Plays a sound on the van once, when its moment (server time at) comes, unless
## that moment is long past (a client that joined late hears nothing stale).
func _sound(id: String, key: String, now: float, at: float, db: float = 0.0) -> void:
	if _played.has(key) or now < at:
		return
	_played[key] = true
	if now - at > 0.5 or _look == null:
		return
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_on", id, _look, db)


func _clear() -> void:
	_show = Show.NONE
	_played.clear()
	if _look != null:
		# Out of the holder now, so the next pull-up builds a fresh VanLook there.
		_holder.remove_child(_look)
		_look.queue_free()
		_look = null
	if _holder != null:
		_holder.visible = false
