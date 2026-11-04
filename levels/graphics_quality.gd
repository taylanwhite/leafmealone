extends RefCounted

## Authority: local, cosmetic (settings:2, docs/DECISIONS.md "Graphics quality").
## The one place the player's video quality (core/settings.gd, [video]) reaches a
## world: the sun's shadows, ambient occlusion, glow, the picture's brightness,
## the outline's width and the lawn grass. It runs right after
## levels/shared_look.gd builds the look (levels/world.gd), again whenever a
## video setting changes, and on each grass chunk as it is grown (props/grass.gd),
## since lawns stream in long after the world's _ready.
##
## The "high" preset is exactly the shipped look: every value here at High equals
## what shared_look.gd sets. Lower presets only take things away or thin them;
## Ultra reaches further. Nothing here is gameplay: mowable task grass
## (levels/lots/task_looks.gd) is never in the "lawn_grass" group, so it is never
## thinned. The engine-wide render options (render scale, anti-aliasing, the
## shadow atlas, the frame cap) are Settings' own (_apply_render).
##
## Reads Settings through the tree (the autoload may be missing in a --script run
## or a tool), and falls back to the High values without it.

## The group and meta props/grass.gd puts on each cosmetic grass chunk.
const GRASS_GROUP: StringName = &"lawn_grass"
const FULL_COUNT_META: StringName = &"full_count"
## Shadow, grass and outline levels when no Settings autoload is there: High.
const HIGH_SHADOWS: int = 3
const HIGH_GRASS: int = 3
const HIGH_OUTLINE: int = 1


## Puts the current video settings on world (levels/world.tscn's root).
static func apply(world: Node) -> void:
	if world == null or not world.is_inside_tree():
		return
	_sun(world)
	_environment(world)
	var outline := world.get_node_or_null("OutlinePass")
	if outline != null and outline.has_method("set_width"):
		outline.call("set_width", outline_width())
	for node: Node in world.get_tree().get_nodes_in_group(GRASS_GROUP):
		if world.is_ancestor_of(node):
			apply_grass(node as MultiMeshInstance3D)


## One cosmetic grass chunk at the grass level: a share of its tufts (the first
## ones; they were planted in random order, so any prefix is an even thinning of
## the whole chunk and the seeded layout is untouched) out to the level's range.
static func apply_grass(view: MultiMeshInstance3D) -> void:
	if view == null or view.multimesh == null:
		return
	var level: Dictionary = Constants.GRASS_LEVELS[_level("grass", HIGH_GRASS, Constants.GRASS_LEVELS.size())]
	var density := float(level["density"])
	view.visible = density > 0.0
	var full := int(view.get_meta(FULL_COUNT_META, view.multimesh.instance_count))
	view.multimesh.visible_instance_count = -1 if density >= 1.0 else int(float(full) * density)
	if density > 0.0:
		view.visibility_range_end = float(level["range"])


## The outline's line width in pixels at the outline setting (0 hides it).
static func outline_width() -> float:
	return Constants.OUTLINE_WIDTHS[_level("outline", HIGH_OUTLINE, Constants.OUTLINE_WIDTHS.size())]


## The picture's brightness (Environment adjustment) the settings ask for.
static func brightness() -> float:
	var settings := _settings()
	if settings == null:
		return 1.0
	return float(settings.call("get_value", "video", "brightness"))


static func _sun(world: Node) -> void:
	var sun := world.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	var index := _level("shadows", HIGH_SHADOWS, Constants.SHADOW_LEVELS.size())
	var level: Dictionary = Constants.SHADOW_LEVELS[index]
	sun.shadow_enabled = index > 0
	if index > 0:
		sun.directional_shadow_max_distance = float(level["distance"])


static func _environment(world: Node) -> void:
	var holder := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if holder == null or holder.environment == null:
		return
	var environment := holder.environment
	var settings := _settings()
	environment.ssao_enabled = bool(settings.call("get_value", "video", "ssao")) if settings != null else true
	environment.glow_enabled = bool(settings.call("get_value", "video", "glow")) if settings != null else true
	# The hour's light (levels/day_sky.gd) owns the brightness once it is there:
	# the Annex's closing dims on top of the player's brightness.
	var day_sky := world.get_node_or_null("DaySky")
	if day_sky != null and day_sky.has_method("set_base_brightness"):
		day_sky.call("set_base_brightness", brightness())
	elif environment.adjustment_enabled:
		environment.adjustment_brightness = brightness()


## A level setting's index, clamped to count; fallback without Settings.
static func _level(key: String, fallback: int, count: int) -> int:
	var settings := _settings()
	var value := int(settings.call("get_value", "video", key)) if settings != null else fallback
	return clampi(value, 0, count - 1)


static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Settings")
