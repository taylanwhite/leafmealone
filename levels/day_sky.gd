extends Node3D

## Authority: local, cosmetic (docs/GAME.md "Day and night"). Turns the day's
## hour (net/day/day_clock.gd, the same on every peer from the server clock) into
## the light: the sun's height, bearing, color and strength, the sky's colors,
## the sky light, the haze, and after sunset the moon, the stars, the street
## lamps, the house windows and the trucks' headlights. One sun and one sky light
## the whole world (Homie Depot, the legacy job lot, the town, Satellite Annex B),
## so every zone keeps the same hour. Nothing is sent: each peer reads its clock.
##
## The look at each hour is Constants.DAY_SKY_KEYS, eased between keys; the
## late-afternoon key is levels/shared_look.gd's own look, the one the art was
## made in. The sun sets toward the west, the moon takes over once the sun's
## light is gone (the light swaps direction while it's dark, so nothing swings).
##
## Night lights:
##   - "street_lamps" (lamp lenses: props/prop_catalog.gd, levels/dressing/
##     neighborhood.gd): their glow is low by day and bright from dusk, and the
##     DAY_SKY_LAMP_LIGHTS lamps nearest the camera cast real light on the street.
##   - "window_glass" (props/house_kit.gd): the houses' windows glow warm at night.
##   - "headlights" (props/vehicles.gd): Chefty's and Lunch Money's beams.
##
## Satellite Annex B dims the room at closing through set_room_dim(), since this
## node owns the sun's and the sky light's strength.

const _Stylized = preload("res://props/stylized.gd")

## The look the last apply showed: hour, energy, night, ... (tests, remote play).
var shown: Dictionary = {}

var _sun: DirectionalLight3D
var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _shown_hour: float = -100.0
var _room_light: float = 1.0
var _room_picture: float = 1.0
var _base_brightness: float = 1.0
var _dirty: bool = true
## Lamp lenses' world positions, and the materials of the lenses, windows and
## headlights this has taken charge of (their strength at full is in meta).
var _lamp_spots: PackedVector3Array = PackedVector3Array()
var _glows: Dictionary = {}
var _glass: Dictionary = {}
var _beams: Array[SpotLight3D] = []
var _scan_wait: float = 0.0
var _pool_wait: float = 0.0
var _pool: Array[OmniLight3D] = []
var _pool_target: PackedFloat32Array = PackedFloat32Array()
var _lit_level: float = -1.0


func _ready() -> void:
	add_to_group("day_sky")
	var world := get_parent()
	_sun = world.get_node_or_null("Sun") as DirectionalLight3D
	var holder := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_environment = holder.environment if holder != null else null
	if _environment != null:
		_sky_material = _environment.sky.sky_material as ProceduralSkyMaterial if _environment.sky != null else null
		if _environment.sky != null:
			# The sky's light is worked out over a few frames, not all in one, each
			# time the colors move on.
			_environment.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		_base_brightness = _environment.adjustment_brightness
		_environment.ambient_light_color = Constants.DAY_SKY_NIGHT_AMBIENT
	if _sky_material != null and not _headless():
		_sky_material.sky_cover = _stars()
		_sky_material.sky_cover_modulate = Color(1.0, 1.0, 1.0, 0.0)
	if not _headless():
		for index: int in Constants.DAY_SKY_LAMP_LIGHTS:
			var light := OmniLight3D.new()
			light.name = "LampLight%d" % index
			light.light_color = Constants.DAY_SKY_LAMP_COLOR
			light.omni_range = Constants.DAY_SKY_LAMP_RANGE
			light.omni_attenuation = 1.4
			light.light_energy = 0.0
			light.shadow_enabled = false
			light.visible = false
			add_child(light)
			_pool.append(light)
		_pool_target.resize(_pool.size())
	_apply(_hour())


func _process(delta: float) -> void:
	var hour := _hour()
	# fx-yard: the night passing (everyone in bed, the clock jumps to 7 AM) is a
	# cut, and the sky's light caught up with it a few frames at a time, so the
	# morning showed dim and then jumped bright eight frames later (rec_night_3p
	# frames 148-156). Worked out whole on that frame instead; and if you slept
	# through it, your eyes open on the morning.
	var jumped := _shown_hour > -50.0 and absf(hour - _shown_hour) >= Constants.DAY_SKY_JUMP_HOURS
	if _dirty or absf(hour - _shown_hour) >= Constants.DAY_SKY_STEP_HOURS:
		_apply(hour)
	if _headless():
		return
	if jumped:
		_whole_sky_frames = 2
		if _was_asleep:
			_open_eyes()
	if _environment != null and _environment.sky != null:
		_environment.sky.process_mode = Sky.PROCESS_MODE_QUALITY if _whole_sky_frames > 0 else Sky.PROCESS_MODE_INCREMENTAL
	_whole_sky_frames = maxi(_whole_sky_frames - 1, 0)
	_was_asleep = _local_asleep()
	_step_eyes(delta)
	_scan_wait -= delta
	if _scan_wait <= 0.0:
		_scan_wait = Constants.DAY_SKY_SCAN_SECONDS
		_scan()
		_light_things(float(shown.get("lamps", 0.0)), float(shown.get("night", 0.0)), true)
	else:
		_light_things(float(shown.get("lamps", 0.0)), float(shown.get("night", 0.0)))
	_light_pool(delta, float(shown.get("lamps", 0.0)))


## The look at an hour of the clock (7 to 26; 26 is 2 AM): the keys either side
## of it, eased. {top, horizon, light, energy, pitch, yaw, ambient, sky_share,
## night, lamps, hour}.
static func look_for(hour: float) -> Dictionary:
	var keys: Array = Constants.DAY_SKY_KEYS
	var first: Dictionary = keys[0]
	if hour <= float(first["hour"]):
		return _with_hour(first, hour)
	for index: int in range(1, keys.size()):
		var after: Dictionary = keys[index]
		if hour <= float(after["hour"]):
			var before: Dictionary = keys[index - 1]
			var t := (hour - float(before["hour"])) / maxf(float(after["hour"]) - float(before["hour"]), 0.001)
			t = smoothstep(0.0, 1.0, t)
			var out := {}
			for key: Variant in before:
				var a: Variant = before[key]
				var b: Variant = after[key]
				if a is Color:
					out[key] = (a as Color).lerp(b as Color, t)
				else:
					out[key] = lerpf(float(a), float(b), t)
			return _with_hour(out, hour)
	return _with_hour(keys[keys.size() - 1], hour)


static func _with_hour(look: Dictionary, hour: float) -> Dictionary:
	var out := look.duplicate()
	out["hour"] = hour
	return out


## Satellite Annex B, at closing (net/annex/annex.gd _dim_room): the sun and the
## sky light at light times their strength, the picture's brightness at picture
## times. 1, 1 is back to normal.
func set_room_dim(light: float, picture: float) -> void:
	if is_equal_approx(light, _room_light) and is_equal_approx(picture, _room_picture):
		return
	_room_light = light
	_room_picture = picture
	_dirty = true


## The player's Brightness setting (levels/graphics_quality.gd): the picture's
## brightness before the Annex's closing dim.
func set_base_brightness(value: float) -> void:
	if is_equal_approx(value, _base_brightness):
		return
	_base_brightness = value
	_dirty = true


var _whole_sky_frames: int = 0
var _was_asleep: bool = false
## Your eyes opening on the morning: a dark veil over the screen fading out.
var _eyes: ColorRect
var _eyes_left: float = 0.0


func _local_asleep() -> bool:
	var clock := get_parent().get_node_or_null("DayClock")
	return clock != null and clock.has_method("is_sleeping") and bool(clock.call("is_sleeping", Net.local_peer_id()))


func _open_eyes() -> void:
	if _eyes == null:
		var layer := CanvasLayer.new()
		layer.name = "WakeEyes"
		# Under the HUD and the day's card, over the world.
		layer.layer = Constants.DAY_SKY_WAKE_LAYER
		add_child(layer)
		_eyes = ColorRect.new()
		_eyes.color = Constants.DAY_SKY_WAKE_COLOR
		_eyes.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_eyes.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_eyes)
	_eyes_left = Constants.DAY_SKY_WAKE_SECONDS
	_eyes.visible = true
	_eyes.modulate.a = 1.0
	wakes_seen += 1


## How many times this peer's eyes opened on a morning (tests).
var wakes_seen: int = 0


func _step_eyes(delta: float) -> void:
	if _eyes == null or not _eyes.visible:
		return
	_eyes_left = maxf(_eyes_left - delta, 0.0)
	_eyes.modulate.a = smoothstep(0.0, 1.0, _eyes_left / Constants.DAY_SKY_WAKE_SECONDS)
	if _eyes_left <= 0.0:
		_eyes.visible = false


func _hour() -> float:
	var clock := get_parent().get_node_or_null("DayClock")
	if clock == null:
		return Constants.DAY_SKY_ART_HOUR
	return float(clock.call("hour"))


func _apply(hour: float) -> void:
	_dirty = false
	_shown_hour = hour
	var look := look_for(hour)
	shown = look
	if _sun != null:
		_sun.rotation_degrees = Vector3(float(look["pitch"]), float(look["yaw"]), 0.0)
		_sun.light_color = look["light"]
		# Shadows stay whatever the shared look and the settings' quality made them.
		_sun.light_energy = float(look["energy"]) * _room_light
	if _environment != null:
		_environment.ambient_light_energy = float(look["ambient"]) * _room_light
		_environment.ambient_light_sky_contribution = float(look["sky_share"])
		_environment.fog_light_color = look["horizon"]
		if _environment.adjustment_enabled:
			_environment.adjustment_brightness = _base_brightness * _room_picture
	if _sky_material != null:
		var horizon: Color = look["horizon"]
		_sky_material.sky_top_color = look["top"]
		_sky_material.sky_horizon_color = horizon
		_sky_material.ground_horizon_color = horizon
		_sky_material.ground_bottom_color = horizon.darkened(0.08)
		_sky_material.sky_cover_modulate = Color(1.0, 1.0, 1.0, clampf(float(look["night"]), 0.0, 1.0))
	var clouds: Color = look["clouds"]
	_Stylized.cloud_material().set_shader_parameter("light", Vector3(clouds.r, clouds.g, clouds.b))


# ---------------------------------------------------------------- night lights

## Every few seconds: where the lamps are, and any lens, window or headlight
## that came in since (the town streams its houses and lamps in and out).
func _scan() -> void:
	_lamp_spots = PackedVector3Array()
	for node: Node in get_tree().get_nodes_in_group("street_lamps"):
		var lens := node as MeshInstance3D
		if lens == null or not lens.is_inside_tree():
			continue
		_lamp_spots.append(lens.global_position)
		_take_glow(lens)
	for node: Node in get_tree().get_nodes_in_group("window_glass"):
		var pane := node as MeshInstance3D
		if pane == null:
			continue
		var material := pane.material_override as StandardMaterial3D
		if material != null and not _glass.has(material.get_instance_id()):
			_glass[material.get_instance_id()] = weakref(material)
			material.emission_enabled = true
			material.emission = Constants.DAY_SKY_WINDOW_COLOR
			material.emission_energy_multiplier = 0.0
			_lit_level = -1.0
	_beams.clear()
	for node: Node in get_tree().get_nodes_in_group("headlights"):
		if node is SpotLight3D:
			_beams.append(node as SpotLight3D)


func _take_glow(lens: MeshInstance3D) -> void:
	var material := lens.material_override as StandardMaterial3D
	if material == null or not material.emission_enabled:
		return
	var id := material.get_instance_id()
	if _glows.has(id):
		return
	if not material.has_meta("day_sky_energy"):
		material.set_meta("day_sky_energy", material.emission_energy_multiplier)
	_glows[id] = weakref(material)
	_lit_level = -1.0


## The lamps' glow, the windows and the headlights, for how far into the evening
## it is (lamps 0 by day to 1 at night, night the same for the windows).
func _light_things(lamps: float, night: float, force: bool = false) -> void:
	var level := snappedf(lamps, 0.02) + snappedf(night, 0.02) * 10.0
	if not force and is_equal_approx(level, _lit_level):
		return
	_lit_level = level
	var lamp_scale := lerpf(Constants.DAY_SKY_LAMP_DAY, Constants.DAY_SKY_LAMP_NIGHT, lamps)
	for id: Variant in _glows.keys():
		var material := (_glows[id] as WeakRef).get_ref() as StandardMaterial3D
		if material == null:
			_glows.erase(id)
			continue
		material.emission_energy_multiplier = float(material.get_meta("day_sky_energy", 1.0)) * lamp_scale
	for id: Variant in _glass.keys():
		var material := (_glass[id] as WeakRef).get_ref() as StandardMaterial3D
		if material == null:
			_glass.erase(id)
			continue
		material.emission_energy_multiplier = Constants.DAY_SKY_WINDOW_ENERGY * night
	for beam: SpotLight3D in _beams:
		if not is_instance_valid(beam):
			continue
		beam.visible = lamps > 0.02
		beam.light_energy = Constants.DAY_SKY_HEADLIGHT_ENERGY * lamps


## The street lamps nearest the camera light the street under them: a few lights
## moved from lamp to lamp as the camera goes, each fading in where it lands and
## out toward the edge of the pool's reach, so none pops on or off.
func _light_pool(delta: float, lamps: float) -> void:
	if _pool.is_empty():
		return
	_pool_wait -= delta
	if _pool_wait <= 0.0:
		_pool_wait = Constants.DAY_SKY_POOL_SECONDS
		_place_pool(lamps)
	for index: int in _pool.size():
		var light := _pool[index]
		light.light_energy = move_toward(light.light_energy, _pool_target[index], Constants.DAY_SKY_LAMP_ENERGY * delta / Constants.DAY_SKY_LAMP_FADE_SECONDS)
		light.visible = light.light_energy > 0.005


func _place_pool(lamps: float) -> void:
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null or lamps <= 0.0:
		for index: int in _pool.size():
			_pool_target[index] = 0.0
		return
	var eye := camera.global_position
	var reach := Constants.DAY_SKY_POOL_REACH
	var near: Array = []
	for spot: Vector3 in _lamp_spots:
		var distance := spot.distance_to(eye)
		if distance < reach:
			near.append([distance, spot + Constants.DAY_SKY_LAMP_DROP])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	near = near.slice(0, _pool.size())
	# A light already on a chosen lamp stays there; any other fades out where it
	# is, and once dark it may move to a chosen lamp that has none yet.
	var lit: Array[int] = []
	var dark: Array[int] = []
	for index: int in _pool.size():
		var light := _pool[index]
		var on := -1
		for pick: int in near.size():
			if not lit.has(pick) and (near[pick][1] as Vector3).distance_to(light.position) < 0.05:
				on = pick
				break
		if on >= 0:
			lit.append(on)
			_pool_target[index] = _pool_energy(float(near[on][0]), lamps)
		else:
			_pool_target[index] = 0.0
			if light.light_energy <= 0.01:
				dark.append(index)
	for pick: int in near.size():
		if lit.has(pick) or dark.is_empty():
			continue
		var index: int = dark.pop_front()
		_pool[index].position = near[pick][1]
		_pool_target[index] = _pool_energy(float(near[pick][0]), lamps)


func _pool_energy(distance: float, lamps: float) -> float:
	var reach := Constants.DAY_SKY_POOL_REACH
	return Constants.DAY_SKY_LAMP_ENERGY * lamps * (1.0 - smoothstep(reach * 0.6, reach, distance))


# ---------------------------------------------------------------- the stars

static var _star_texture: ImageTexture


## The night sky's stars: points on the upper half of an equirectangular map,
## brighter near the top, none down at the horizon where the haze is. The sky
## adds it in by the night's share (sky_cover_modulate's alpha).
static func _stars() -> ImageTexture:
	if _star_texture != null:
		return _star_texture
	var size := Constants.DAY_SKY_STAR_MAP
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = Constants.DAY_SKY_STAR_SEED
	for _star: int in Constants.DAY_SKY_STARS:
		var x := rng.randi_range(0, size.x - 1)
		# Up to 70 degrees from the zenith, thinning toward the horizon.
		var y := int(pow(rng.randf(), 1.4) * float(size.y) * 0.39)
		var bright := rng.randf_range(0.35, 1.0)
		var tint := Color(1.0, 1.0, 1.0).lerp(Color(0.75, 0.85, 1.0) if rng.randf() < 0.5 else Color(1.0, 0.9, 0.75), rng.randf() * 0.6)
		image.set_pixel(x, y, Color(tint.r, tint.g, tint.b, bright))
		if bright > 0.85:
			for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var at := Vector2i(x, y) + step
				if at.x < size.x and at.y < size.y:
					image.set_pixelv(at, Color(tint.r, tint.g, tint.b, bright * 0.5))
	_star_texture = ImageTexture.create_from_image(image)
	return _star_texture


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"
