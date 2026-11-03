extends RefCounted

## Authority: local, cosmetic. The Courtesy Shuttle's gestures (nice_boys:4), put
## into player/cartoon_body.gd's gesture registry (register_gesture, nice_boys:1)
## the first time a van is built, so riders, the crew and the driver can play them
## by name on every peer:
##   step_up        a knee up onto the sill, arms out for balance
##   buckle_lean    leaning across to buckle someone in
##   roof_pat       two pats on the roof: "she's good to go"
##   driver_wheel   hands on the wheel, a little sway with the road (loops)
##   mirror_check   a lean and a squint at the door-side mirror
##   manifest_read  the clipboard up on the wheel, lips moving
##   knock_glass    a rider leaning out, rapping on the glass
##   wave_driver    the driver's two-finger wave off the wheel
##   straggler_hop  a jump onto the bumper, one arm grabbing the door frame
## Each pose names the stock gesture it falls back to when the body has no
## registry (FALLBACK), so a merge in any order still plays something.

const _CartoonBody = preload("res://player/cartoon_body.gd")

const SECONDS: Dictionary = {
	"step_up": 0.6, "buckle_lean": 0.5, "roof_pat": 0.7, "driver_wheel": 2.0,
	"mirror_check": 1.5, "manifest_read": 2.4, "knock_glass": 0.6, "wave_driver": 1.1,
	"straggler_hop": 0.7,
}
const FALLBACK: Dictionary = {
	"step_up": "startle", "buckle_lean": "offer", "roof_pat": "wave", "driver_wheel": "",
	"mirror_check": "look_around", "manifest_read": "scribble", "knock_glass": "flail",
	"wave_driver": "wave", "straggler_hop": "startle",
}

static var _registered: bool = false


## Once per process: hand every pose to the body's registry, if it has one.
static func register() -> void:
	if _registered:
		return
	_registered = true
	var found := false
	for method: Dictionary in (_CartoonBody as Script).get_script_method_list():
		if str(method.get("name", "")) == "register_gesture":
			found = true
	if not found:
		return
	var registry: Object = _CartoonBody
	for gesture_name: String in SECONDS.keys():
		registry.call("register_gesture", gesture_name, float(SECONDS[gesture_name]), _pose_for(gesture_name))


## Play one on a CartoonBody: the registered pose, else its stock fallback.
static func play(body: Node, gesture_name: String) -> void:
	if body == null or not body.has_method("gesture"):
		return
	register()
	if body.has_method("has_gesture") and bool(body.call("has_gesture", gesture_name)):
		body.call("gesture", gesture_name)
		return
	var fallback := str(FALLBACK.get(gesture_name, ""))
	if fallback != "":
		body.call("gesture", fallback)


static func _pose_for(gesture_name: String) -> Callable:
	match gesture_name:
		"step_up":
			return _step_up
		"buckle_lean":
			return _buckle_lean
		"roof_pat":
			return _roof_pat
		"driver_wheel":
			return _driver_wheel
		"mirror_check":
			return _mirror_check
		"manifest_read":
			return _manifest_read
		"knock_glass":
			return _knock_glass
		"wave_driver":
			return _wave_driver
		_:
			return _straggler_hop


## The pivot the body poses by name (cartoon_body.pose_part), trying the names
## the registry might use; null when there's none.
static func _part(body: Node, names: Array) -> Node3D:
	if not body.has_method("pose_part"):
		return null
	for part_name: String in names:
		var node: Variant = body.call("pose_part", part_name)
		if node is Node3D:
			return node
	return null


static func _arm(body: Node, right: bool) -> Node3D:
	return _part(body, ["arm_r", "right_arm", "arm_right"] if right else ["arm_l", "left_arm", "arm_left"])


## In and out over the gesture: 0 at both ends, 1 in the middle.
static func _fade(t: float) -> float:
	return clampf(minf(t * 5.0, (1.0 - t) * 5.0), 0.0, 1.0)


static func _step_up(body: Node, t: float, _delta: float) -> void:
	var lift := sin(clampf(t, 0.0, 1.0) * PI)
	var leg := _part(body, ["leg_r", "right_leg", "leg_right"])
	if leg != null:
		leg.rotation.x = 1.1 * lift
	for right: bool in [true, false]:
		var arm := _arm(body, right)
		if arm != null:
			arm.rotation.z = (1.0 if right else -1.0) * 0.9 * lift


static func _buckle_lean(body: Node, t: float, _delta: float) -> void:
	var fade := _fade(t)
	var torso := _part(body, ["torso"])
	if torso != null:
		torso.rotation.x = -0.45 * fade
	for right: bool in [true, false]:
		var arm := _arm(body, right)
		if arm != null:
			arm.rotation.x = 1.25 * fade
			arm.rotation.z = (-0.3 if right else 0.3) * fade


static func _roof_pat(body: Node, t: float, _delta: float) -> void:
	var arm := _arm(body, true)
	if arm != null:
		# Up overhead, two pats.
		arm.rotation.z = 2.6 * _fade(t)
		arm.rotation.x = 0.25 * absf(sin(t * TAU * 2.0)) * _fade(t)


static func _driver_wheel(body: Node, t: float, _delta: float) -> void:
	var torso := _part(body, ["torso"])
	if torso != null:
		torso.rotation.z = 0.04 * sin(t * TAU)
	for right: bool in [true, false]:
		var arm := _arm(body, right)
		if arm != null:
			arm.rotation.x = 1.15
			arm.rotation.z = -0.22 if right else 0.22


static func _mirror_check(body: Node, t: float, _delta: float) -> void:
	var fade := _fade(t)
	var torso := _part(body, ["torso"])
	if torso != null:
		torso.rotation.y = -0.3 * fade
		torso.rotation.z = -0.08 * fade
	var face := _part(body, ["face", "head"])
	if face != null:
		face.rotation.y = -0.9 * fade


static func _manifest_read(body: Node, t: float, _delta: float) -> void:
	var fade := _fade(t)
	var left := _arm(body, false)
	if left != null:
		left.rotation.x = 1.2 * fade
		left.rotation.z = 0.45 * fade
	var face := _part(body, ["face", "head"])
	if face != null:
		face.rotation.x = 0.3 * fade
		face.rotation.y = 0.05 * sin(t * 18.0) * fade


static func _knock_glass(body: Node, t: float, _delta: float) -> void:
	var arm := _arm(body, true)
	var rap := absf(sin(t * TAU * 3.0))
	if arm != null:
		arm.rotation.x = 1.4 + 0.25 * rap
		arm.rotation.z = 0.2
	var torso := _part(body, ["torso"])
	if torso != null:
		torso.rotation.x = -0.35 * _fade(t)


static func _wave_driver(body: Node, t: float, _delta: float) -> void:
	var arm := _arm(body, false)
	if arm != null:
		arm.rotation.x = 1.0 * _fade(t)
		arm.rotation.z = (0.9 + 0.25 * sin(t * 20.0)) * _fade(t)


static func _straggler_hop(body: Node, t: float, _delta: float) -> void:
	var hop := sin(clampf(t, 0.0, 1.0) * PI)
	var arm := _arm(body, true)
	if arm != null:
		arm.rotation.z = 2.5 * clampf(t * 3.0, 0.0, 1.0)
	for right: bool in [true, false]:
		var leg := _part(body, ["leg_r", "right_leg", "leg_right"] if right else ["leg_l", "left_leg", "leg_left"])
		if leg != null:
			leg.rotation.x = (0.8 if right else -0.3) * hop
