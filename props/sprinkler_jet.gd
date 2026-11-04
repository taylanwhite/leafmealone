extends Node3D

## Authority: local, cosmetic, the same on every peer. A lawn sprinkler's jet
## (art chunk 9; docs/GAME.md "What each neighborhood sounds like"): an impact
## sprinkler's arcing stream that steps across its arc one tick at a time (the
## arm smacks it, the stream chokes for a moment), then ratchets back to the
## start. It runs during its schedule's hours of the clock
## (Constants.SPRINKLER_HOURS: Oak Hollow's Approved Watering Window, a summer
## lawn's morning), shooting out to full reach when the water comes on and
## sagging back to the nozzle when it goes off.
##
## Where the head points is a pure function of Net.server_time() plus phase, so
## every peer sees it in the same place, and audio/ambience.gd starts this
## emitter's sprinkler_tick_loop at the same point of the loop (meta
## ambient_sync, ambient_phase): the tick you hear is the step you see. Oak
## Hollow's all share phase 0, so the whole street ticks in step.
##
## Group "ambient_emitters" (meta ambient), and ambient_level() (the water
## pressure, 0..1) tells ambience how loud. The jet is only drawn and swung
## within Constants.SPRINKLER_DRAW_DISTANCE of the camera; farther, or off
## hours, it costs a check every half second.

## Constants.SPRINKLER_HOURS key.
var schedule: String = "hoa"
## Seconds added to the server time, so a lone summer sprinkler keeps its own beat.
var phase: float = 0.0
## The water pressure now, 0 (off) to 1 (full).
var pressure: float = 0.0
## Running whatever the hour (the studio's ambience subject).
var always_on: bool = false

var _head: Node3D
var _jet: MeshInstance3D
var _check_left: float = 0.0
var _on: bool = false
## Near the camera (checked every half second; the jet's own visibility range
## culls it till the first check).
var _near: bool = true

static var _mesh: ArrayMesh
static var _material: ShaderMaterial

const SPRAY_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 water : source_color = vec4(0.84, 0.93, 1.0, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// UV.y runs out along the stream, UV.x across it. Near the nozzle it's a
	// glassy white rope; farther out it breaks into fat cartoon drops flying
	// outward, thinning to a mist where it lands.
	float along = UV.y;
	float across = abs(UV.x - 0.5) * 2.0;
	float drops = noise(vec2(UV.x * 6.0, along * 20.0 - TIME * 9.0));
	float fine = noise(vec2(UV.x * 15.0 + 3.0, along * 44.0 - TIME * 13.0));
	float breakup = smoothstep(0.15, 0.85, along);
	float core = 1.0 - smoothstep(mix(0.5, 0.95, breakup), 1.0, across);
	float rope = 0.82 + drops * 0.18;
	float spray = max(smoothstep(0.5, 0.62, drops), smoothstep(0.62, 0.72, fine) * 0.7);
	float a = core * mix(rope, spray, breakup) * (1.0 - smoothstep(0.9, 1.0, along) * 0.7);
	ALBEDO = mix(water.rgb, vec3(1.0), 0.45 + drops * 0.4);
	EMISSION = vec3(0.12, 0.16, 0.2);
	ALPHA = clamp(a, 0.0, 0.95);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
"""


func _ready() -> void:
	name = "SprinklerJet"
	add_to_group("ambient_emitters")
	set_meta("ambient", "sprinkler_tick_loop")
	set_meta("ambient_sync", loop_seconds())
	set_meta("ambient_phase", phase)
	_head = Node3D.new()
	_head.name = "Head"
	# The nozzle on top of the head (props/yard_extras.gd _sprinkler).
	_head.position = Vector3(0.0, 0.2, 0.0)
	add_child(_head)
	_jet = MeshInstance3D.new()
	_jet.name = "Jet"
	_jet.mesh = jet_mesh()
	_jet.material_override = spray_material()
	_jet.set_meta("keep_material", true)
	_jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jet.visibility_range_end = Constants.SPRINKLER_DRAW_DISTANCE
	_jet.visible = false
	_head.add_child(_jet)
	# A yard that loads mid-window finds the water already on.
	_on = always_on or running(schedule, _hour())
	pressure = 1.0 if _on else 0.0
	# Spread the checks over frames (no global rng in anything a block builds).
	_check_left = float(posmod(get_instance_id(), 50)) * 0.01


## How loud ambience plays this emitter: the water pressure.
func ambient_level() -> float:
	return pressure


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = 0.5
		_on = always_on or running(schedule, _hour())
		_near = always_on or _camera_near()
	var target := 1.0 if _on else 0.0
	if not is_equal_approx(pressure, target):
		var seconds := Constants.SPRINKLER_RAMP_UP_SECONDS if target > pressure else Constants.SPRINKLER_RAMP_DOWN_SECONDS
		pressure = move_toward(pressure, target, delta / seconds)
	var shown := pressure > 0.001 and _near
	if _jet.visible != shown:
		_jet.visible = shown
	if not shown:
		return
	var t := fposmod(Net.server_time() + phase, loop_seconds())
	_head.rotation.y = head_angle(t)
	# Coming on it shoots out to its reach; going off it sags back to the nozzle.
	var reach := smoothstep(0.0, 1.0, pressure) * choke(t)
	_jet.scale = Vector3(lerpf(0.5, 1.0, pressure), reach * lerpf(0.6, 1.0, pressure), reach)


## True while the schedule's water is on at this hour of the clock.
static func running(schedule_id: String, hour: float) -> bool:
	var hours: Vector2 = Constants.SPRINKLER_HOURS.get(schedule_id, Vector2.ZERO)
	return hour >= hours.x and hour < hours.y


## The loop's length: the sweep's ticks, then the ratchet back (s).
static func loop_seconds() -> float:
	return float(Constants.SPRINKLER_TICKS) * Constants.SPRINKLER_TICK_SECONDS + Constants.SPRINKLER_RETURN_SECONDS


## Where the head points t seconds into the loop (radians about +Y, 0 is -Z):
## each tick at k * TICK kicks it one step over in a few hundredths of a second,
## and after the last it sweeps smoothly back to where it started.
static func head_angle(t: float) -> float:
	var half := Constants.SPRINKLER_ARC * 0.5
	var sweep := float(Constants.SPRINKLER_TICKS) * Constants.SPRINKLER_TICK_SECONDS
	if t < sweep:
		var k := floorf(t / Constants.SPRINKLER_TICK_SECONDS)
		var since := t - k * Constants.SPRINKLER_TICK_SECONDS
		var step := Constants.SPRINKLER_ARC / float(Constants.SPRINKLER_TICKS)
		return -half + (k + smoothstep(0.0, 0.045, since)) * step
	var back := clampf((t - sweep) / Constants.SPRINKLER_RETURN_SECONDS, 0.0, 1.0)
	return half - Constants.SPRINKLER_ARC * smoothstep(0.0, 1.0, back)


## The stream's length share t seconds into the loop: it dips as the arm breaks it.
static func choke(t: float) -> float:
	var sweep := float(Constants.SPRINKLER_TICKS) * Constants.SPRINKLER_TICK_SECONDS
	if t >= sweep:
		return 1.0
	var since := fposmod(t, Constants.SPRINKLER_TICK_SECONDS)
	return 1.0 - Constants.SPRINKLER_CHOKE * (1.0 - smoothstep(0.0, 0.09, since))


## Two crossed ribbons along the stream's arc, out along -Z from the nozzle,
## widening as it breaks up; UV.y runs out along it. Built once.
static func jet_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var steps := 14
	var reach := Constants.SPRINKLER_REACH
	var rise := Constants.SPRINKLER_RISE
	var points: Array[Vector3] = []
	for index: int in steps + 1:
		var u := float(index) / float(steps)
		# Up and out, landing a little below the nozzle (on the lawn).
		points.append(Vector3(0.0, rise * 4.0 * u * (1.0 - u) - 0.2 * u * u, -reach * u))
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for ribbon: int in 2:
		for index: int in steps:
			var corners: Array = []
			for end: int in 2:
				var at := points[index + end]
				var u := float(index + end) / float(steps)
				var width := lerpf(0.06, 0.75, u * u)
				var along := (points[mini(index + end + 1, steps)] - points[maxi(index + end - 1, 0)]).normalized()
				var side := Vector3.RIGHT if ribbon == 0 else along.cross(Vector3.RIGHT).normalized()
				corners.append([at - side * width * 0.5, at + side * width * 0.5, u])
			var a: Array = corners[0]
			var b: Array = corners[1]
			for corner: Array in [[a[0], 0.0, a[2]], [a[1], 1.0, a[2]], [b[1], 1.0, b[2]], [a[0], 0.0, a[2]], [b[1], 1.0, b[2]], [b[0], 0.0, b[2]]]:
				vertices.append(corner[0])
				uvs.append(Vector2(float(corner[1]), float(corner[2])))
				normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh


static func spray_material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SPRAY_SHADER
		_material = ShaderMaterial.new()
		_material.shader = shader
	return _material


func _hour() -> float:
	var clock := get_tree().get_first_node_in_group("day_clock") if is_inside_tree() else null
	return float(clock.call("hour")) if clock != null else Constants.DAY_SKY_ART_HOUR


func _camera_near() -> bool:
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	return camera != null and camera.global_position.distance_to(global_position) < Constants.SPRINKLER_DRAW_DISTANCE
