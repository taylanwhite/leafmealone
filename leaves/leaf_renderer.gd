extends Node3D

## Authority: local, cosmetic. The leaf VIEW (contract C3 in the raking spec;
## docs/ART.md "Leaves"): draws the host's density grid (the LeafField it is a
## child of) as a lawn under leaves, and never writes it. Three layers:
## - the litter skin (leaves/leaf_litter.gd): a grid per chunk lifted by a
##   height map into drifts and piles and painted with overlapping leaf shapes;
##   it casts the leaves' shadows
## - hero leaves: up to Constants.LEAF_HERO_MAX chunky curled leaves per cell
##   (LeafMeshes, LeafPalette), one MultiMesh per chunk and species, riding the
##   height map in their shader so a growing mound carries them with no CPU work
## - grass pressed flat under the leaves (leaves/grass_press.gd), from the
##   cover map this view keeps
##
## Per cell it keeps the field's density at the last flush (target), the units
## it draws (displayed), the units a listener (leaves/leaf_motion.gd) has
## claimed and will deliver (pending) and a spring-animated height. Once a
## frame it diffs the changed chunks and emits targets_changed(changes, false)
## (flat x, z, delta triples); listeners may claim() during that emission. Every
## unit nobody claimed eases in (morphs) over Constants.LEAF_MORPH_SECONDS, and
## each hero leaf the ease adds or takes scales in or out on a small fading
## MultiMesh, so even with no listener a leaf never pops. A hard reset (a new
## lot, the first snapshot) snaps everything in one frame.
##
## Listens to the field's leaves_changed and field_reset when it has them
## (raking:1), else to chunk_changed, treating a refresh of every chunk at once
## as a hard reset. Headless it builds nothing unless the command line has
## --leaf-motion-headless (then it keeps its state, with no GPU objects), or
## keep_state_headless is set before it enters the tree (tools/leaf_look_check.gd).

signal targets_changed(changes: PackedInt32Array, hard: bool)

const _LeafShaders = preload("res://leaves/leaf_shaders.gd")
const MOTION_SCRIPT := "res://leaves/leaf_motion.gd"
const HEADLESS_FLAG := "--leaf-motion-headless"
## Floats per hero instance in a MultiMesh buffer: transform 12, colour 4, custom 4.
const STRIDE: int = 20
const CHUNK_CELLS: int = 16
const SPECIES: int = 3
## Why a cell's displayed units changed.
const CAUSE_MORPH: int = 0
const CAUSE_HANDOFF: int = 1
const CAUSE_RESET: int = 2
const LOG_MAX: int = 20000

## Keep the view's state (cells, heights, slots) even in a headless run.
var keep_state_headless: bool = false

var _field: Node3D
var _width: int = 0
var _depth: int = 0
var _cell: float = 0.5
var _grid_origin := Vector3.ZERO
var _ground_local: float = 0.0
var _chunks_x: int = 0
var _chunks_z: int = 0
var _stateful := false
var _gpu := false
var _built := false
var _has_reset := false

var _target := PackedInt32Array()
var _displayed := PackedInt32Array()
var _pending := PackedInt32Array()
var _reserved := PackedInt32Array()
## Per cell: slots hidden by a kick (bit k), and slots still fading in (bit k).
var _hidden := PackedInt32Array()
var _fading := PackedInt32Array()
var _height := PackedFloat32Array()
var _height_vel := PackedFloat32Array()
var _height_goal := PackedFloat32Array()
var _press := PackedFloat32Array()
var _morph_rate := PackedFloat32Array()
var _morph_acc := PackedFloat32Array()
var _cell_look := PackedByteArray()
var _looks: Array = []
var _mix: Array = []
var _sources_key := ""
var _season: int = 0

var _queued: Dictionary = {}
var _hard_pending := false
var _flush_scheduled := false
var _claiming := false
var _moving: Dictionary = {}
var _morphing: Dictionary = {}
var _pressing: Dictionary = {}
## Fading hero leaves: key cell * 16 + slot -> [t 0..1, direction +1 in / -1 out].
var _fades: Dictionary = {}
var _cell_dirty: Dictionary = {}
## Chunks waiting for a hero rebuild: index -> true when it must happen this frame.
var _chunk_queue: Dictionary = {}
## Per cell: every slot's instance floats and species, built on first use.
var _slot_floats: Array = []
var _slot_species: Array = []
## Per cell: [maple, oak, oval] instance floats of the slots drawn now.
var _slices: Array = []
var _chunk_cells: Array = []
## Per chunk: [maple, oak, oval] instance floats of its drawn hero leaves.
var _chunk_buffers: Array = []
## Hero blocks (Constants.LEAF_HERO_BLOCK_CHUNKS squared chunks): their chunks, boxes, and which need an upload.
var _block_chunks: Array = []
var _block_boxes: Array = []
var _blocks_x: int = 0
var _block_dirty: Dictionary = {}
var _heights_dirty := false
var _cover_dirty := false
var _cover_bytes := PackedByteArray()
var _skin_counter: int = 0

var _height_image: Image
var _height_texture: ImageTexture
var _cover_image: Image
var _cover_texture: ImageTexture
var _litter_material: ShaderMaterial
## Per hero block: [MultiMeshInstance3D or null] x SPECIES.
var _views: Array = []
var _fade_views: Array = []
var _rect := Vector4.ZERO
var _warm: Array = []
var _warm_frames: int = 0

var _instant: int = 0
var _morph_units: int = 0
var _rebuild_ms_peak: float = 0.0
var _rebuilds: int = 0
var _log_on := false
var _log: Array = []

## The field's clean line (LeafField.CLEAN_DENSITY): at or under it, no hero leaves.
static var _clean: int = 8
## The view whose maps the leaf shader globals show.
static var _globals_owner: Node = null


func _ready() -> void:
	add_to_group("leaf_view")
	add_to_group("seasonal")
	_field = get_parent() as Node3D
	if _field == null or not _field.has_method("density_at_cell"):
		push_error("[Leaves] the leaf view must be a child of a leaf field")
		return
	var headless := DisplayServer.get_name() == "headless"
	_stateful = not headless or keep_state_headless or OS.get_cmdline_user_args().has(HEADLESS_FLAG)
	_gpu = not headless
	if not _stateful:
		return
	# Children are ready before their parent, and the field sizes its grid in its own _ready.
	if not _field.is_node_ready():
		await _field.ready
	_setup()


func _exit_tree() -> void:
	if _globals_owner == self:
		_globals_owner = null
		RenderingServer.global_shader_parameter_set("leaf_rect", Vector4.ZERO)


# ---------------------------------------------------------------- the API (contract C3)

## A density's hero leaves: none at or under the clean line, else
## Constants.LEAF_HERO_MAX * (units / 255) ^ LEAF_HERO_CURVE rounded up, at least one.
static func hero_count(units: int) -> int:
	if units <= _clean:
		return 0
	var share := pow(clampf(float(units) / 255.0, 0.0, 1.0), Constants.LEAF_HERO_CURVE)
	return clampi(ceili(share * float(Constants.LEAF_HERO_MAX) - 0.0001), 1, Constants.LEAF_HERO_MAX)


## The skin's height for a blurred density b (meters above the lawn).
static func mound_height(b: float) -> float:
	var low := Constants.LEAF_MOUND_BASE * minf(b, 60.0) / 60.0
	var high := Constants.LEAF_MOUND_HEIGHT * pow(maxf(b - 60.0, 0.0) / 195.0, Constants.LEAF_MOUND_EXP)
	return low + high


## Listeners claim units during targets_changed: negative = units they will
## launch out of the cell, positive = units they will land in it.
func claim(cell: Vector2i, delta: int) -> void:
	var c := _index(cell)
	if c < 0:
		return
	if not _claiming:
		push_warning("[Leaves] claim() outside targets_changed")
	_pending[c] += delta
	_update_morph(c)


## A listener launches units out of a cell: the top hero leaf (if the count
## drops) leaves the same frame. Returns where it was: {xform, color, custom,
## species, slot}; slot -1 means it rises out of the skin (scale it in).
func take_launch(cell: Vector2i, units: int) -> Dictionary:
	var c := _index(cell)
	if c < 0:
		return {}
	var before := hero_count(_displayed[c])
	var after := hero_count(_displayed[c] - units)
	var out := {}
	var k := before - 1
	while k >= after and (_hidden[c] & (1 << k)) != 0:
		k -= 1
	if after < before and k >= after:
		out = _slot_info(cell, k)
		_end_fade(c, k)
		_note(cell, k, "launch")
	else:
		out = _skin_point(cell)
	_pending[c] += units
	_set_displayed(c, _displayed[c] - units, CAUSE_HANDOFF)
	return out


## Where a landing of units into a cell will lie: the slot that appears, or a
## point on the skin (slot -1: dive in, sink 2 cm and shrink).
func reserve_landing(cell: Vector2i, units: int) -> Dictionary:
	var c := _index(cell)
	if c < 0:
		return {}
	var base := _displayed[c] + _reserved[c]
	var before := hero_count(base)
	var after := hero_count(base + units)
	_reserved[c] += units
	if after > before:
		return _slot_info(cell, after - 1)
	return _skin_point(cell)


## Units arrive: displayed rises now and the static leaf draws from the
## returned physics frame (a mover parks until then).
func land(cell: Vector2i, units: int, slot: int) -> int:
	var c := _index(cell)
	if c < 0:
		return Engine.get_physics_frames()
	_reserved[c] = maxi(0, _reserved[c] - units)
	_pending[c] -= units
	_set_displayed(c, _displayed[c] + units, CAUSE_HANDOFF)
	if slot >= 0:
		_end_fade(c, slot)
		_note(cell, slot, "land")
	return Engine.get_physics_frames() + 1


## A kick lifts one exact leaf (units unchanged); return_slot puts it back.
func take_slot(cell: Vector2i, k: int) -> Dictionary:
	var c := _index(cell)
	if c < 0 or k < 0 or k >= Constants.LEAF_HERO_MAX:
		return {}
	_hidden[c] |= 1 << k
	_mark_cell(c, true)
	_note(cell, k, "kick_take")
	return _slot_info(cell, k)


func return_slot(cell: Vector2i, k: int) -> void:
	var c := _index(cell)
	if c < 0 or k < 0 or k >= Constants.LEAF_HERO_MAX:
		return
	_hidden[c] &= ~(1 << k)
	_mark_cell(c, true)
	_note(cell, k, "kick_return")


## The top of the leaves at a world point: the lawn plus the skin's height,
## blended between cell centres exactly as the shaders blend the height map.
func surface_y(world_xz: Vector2) -> float:
	if not _built:
		return global_position.y + _ground_local
	var local := _to_local_xz(world_xz)
	return (global_transform * Vector3(local.x, _ground_local, local.y)).y + _height_at_local(local).x


## The lawn under the leaves (world y): surface_y with no leaves.
func ground_y() -> float:
	return (global_transform * Vector3(_grid_origin.x, _ground_local, _grid_origin.z)).y


## Where slot k of a cell is drawn, exactly as the GPU draws it (world).
func slot_world(cell: Vector2i, k: int) -> Transform3D:
	var c := _index(cell)
	if c < 0:
		return Transform3D.IDENTITY
	var floats := _slots_of(c)
	var at := clampi(k, 0, Constants.LEAF_HERO_MAX - 1) * STRIDE
	var local := Transform3D(
		Basis(Vector3(floats[at], floats[at + 4], floats[at + 8]), Vector3(floats[at + 1], floats[at + 5], floats[at + 9]), Vector3(floats[at + 2], floats[at + 6], floats[at + 10])),
		Vector3(floats[at + 3], floats[at + 7], floats[at + 11]))
	var world := global_transform * local
	var ground := _height_at_local(Vector2(local.origin.x, local.origin.z))
	world.origin.y += ground.x
	world.basis = Basis(Vector3(1.0, ground.y, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, ground.z, 1.0)) * world.basis
	return world


func cell_of(world: Vector3) -> Vector2i:
	var local := _to_local_xz(Vector2(world.x, world.z))
	return Vector2i(int(floor((local.x - _grid_origin.x) / _cell)), int(floor((local.y - _grid_origin.z) / _cell)))


## A cell's centre on top of its leaves (world).
func cell_center_world(cell: Vector2i) -> Vector3:
	var local := Vector3(_grid_origin.x + (float(cell.x) + 0.5) * _cell, _ground_local, _grid_origin.z + (float(cell.y) + 0.5) * _cell)
	var world := global_transform * local
	world.y += _height_at_local(Vector2(local.x, local.z)).x
	return world


func species_mesh(i: int) -> Mesh:
	return LeafMeshes.mesh(i)


## "hero" (rides the skin) or "mover" (in flight).
func flake_material(mode: String) -> Material:
	return _LeafShaders.flake_material(mode)


func displayed_units(cell: Vector2i) -> int:
	var c := _index(cell)
	return _displayed[c] if c >= 0 else 0


func target_units(cell: Vector2i) -> int:
	var c := _index(cell)
	return _target[c] if c >= 0 else 0


func stats() -> Dictionary:
	var heroes := 0
	var draws := 0
	for chunk: Array in _views:
		for view: Variant in chunk:
			if view != null and (view as MultiMeshInstance3D).visible:
				heroes += (view as MultiMeshInstance3D).multimesh.instance_count
				draws += 1
	if not _gpu:
		for c: int in _displayed.size():
			heroes += hero_count(_displayed[c])
	return {
		"hero_instances": heroes,
		"hero_draws": draws,
		"fading": _fades.size(),
		"instant": _instant,
		"morph_units": _morph_units,
		"morphing": _morphing.size(),
		"moving": _moving.size(),
		"rebuild_ms_peak": _rebuild_ms_peak,
		"rebuilds": _rebuilds,
		"looks": _looks.size(),
	}


func set_flake_log(on: bool) -> void:
	_log_on = on
	if not on:
		_log.clear()


func flake_log() -> Array:
	return _log


## Every seasonal node: the leaves turn with the season.
func apply_season(season: int) -> void:
	if not _built or season == _season:
		return
	_season = season
	_apply_season_look()
	_slot_floats.fill(null)
	_slot_species.fill(null)
	for c: int in _displayed.size():
		if hero_count(_displayed[c]) > 0:
			_cell_dirty[c] = true
	for chunk: int in _chunks_x * _chunks_z:
		_chunk_queue[chunk] = false


# ---------------------------------------------------------------- setup

func _setup() -> void:
	_width = int(_field.get("grid_width"))
	_depth = int(_field.get("grid_depth"))
	_cell = float(_field.get("cell_size"))
	_grid_origin = _field.get("grid_origin")
	_ground_local = _grid_origin.y + Constants.LEAF_GROUND_OFFSET
	if _field.has_method("clean_density"):
		_clean = int(_field.call("clean_density"))
	_chunks_x = int(ceil(float(_width) / float(CHUNK_CELLS)))
	_chunks_z = int(ceil(float(_depth) / float(CHUNK_CELLS)))
	var count := _width * _depth
	_target.resize(count)
	_displayed.resize(count)
	_pending.resize(count)
	_reserved.resize(count)
	_hidden.resize(count)
	_fading.resize(count)
	_height.resize(count)
	_height_vel.resize(count)
	_height_goal.resize(count)
	_press.resize(count)
	_morph_rate.resize(count)
	_morph_acc.resize(count)
	_cell_look.resize(count)
	_cover_bytes.resize(count * 4)
	_slot_floats.resize(count)
	_slot_species.resize(count)
	_slices.resize(count)
	_chunk_cells.clear()
	for chunk: int in _chunks_x * _chunks_z:
		var cells := PackedInt32Array()
		var corner := Vector2i((chunk % _chunks_x) * CHUNK_CELLS, (chunk / _chunks_x) * CHUNK_CELLS)
		for dz: int in CHUNK_CELLS:
			for dx: int in CHUNK_CELLS:
				var x := corner.x + dx
				var z := corner.y + dz
				if x < _width and z < _depth:
					cells.append(x + z * _width)
		_chunk_cells.append(cells)
	_chunk_buffers.clear()
	_chunk_buffers.resize(_chunks_x * _chunks_z)
	var per := maxi(Constants.LEAF_HERO_BLOCK_CHUNKS, 1)
	_blocks_x = int(ceil(float(_chunks_x) / float(per)))
	var blocks_z := int(ceil(float(_chunks_z) / float(per)))
	_block_chunks.clear()
	_block_boxes.clear()
	for block: int in _blocks_x * blocks_z:
		var chunks := PackedInt32Array()
		var bx := (block % _blocks_x) * per
		var bz := (block / _blocks_x) * per
		for cz: int in range(bz, mini(bz + per, _chunks_z)):
			for cx: int in range(bx, mini(bx + per, _chunks_x)):
				chunks.append(cx + cz * _chunks_x)
		_block_chunks.append(chunks)
		var low := Vector3(_grid_origin.x + float(bx * CHUNK_CELLS) * _cell - 0.4, _ground_local - 0.2, _grid_origin.z + float(bz * CHUNK_CELLS) * _cell - 0.4)
		var span := Vector3(float(mini(per * CHUNK_CELLS, _width - bx * CHUNK_CELLS)) * _cell + 0.8, 1.5, float(mini(per * CHUNK_CELLS, _depth - bz * CHUNK_CELLS)) * _cell + 0.8)
		_block_boxes.append(AABB(low, span))
	_season = Seasons.current()
	_refresh_looks(true)
	if _gpu:
		_build_gpu()
	if _field.has_signal("leaves_changed"):
		_field.connect("leaves_changed", _on_chunk)
	else:
		_field.connect("chunk_changed", _on_chunk)
	if _field.has_signal("field_reset"):
		_has_reset = true
		_field.connect("field_reset", _on_reset)
	_built = true
	_hard_pending = true
	_schedule_flush()
	if ResourceLoader.exists(MOTION_SCRIPT):
		call_deferred("_spawn_motion")


func _spawn_motion() -> void:
	var holder := _field.get_parent()
	if holder == null or holder.get_node_or_null("LeafMotion") != null:
		return
	var script: Script = load(MOTION_SCRIPT)
	if script == null:
		return
	var motion: Node = script.new()
	motion.name = "LeafMotion"
	holder.add_child(motion)
	if motion.has_method("attach"):
		motion.call("attach", self, _field)


func _build_gpu() -> void:
	_height_image = Image.create(_width, _depth, false, Image.FORMAT_RF)
	_height_texture = ImageTexture.create_from_image(_height_image)
	_cover_image = Image.create(_width, _depth, false, Image.FORMAT_RGBA8)
	_cover_texture = ImageTexture.create_from_image(_cover_image)
	_litter_material = _LeafShaders.litter_material()
	_apply_season_look()
	_views.clear()
	for chunk: int in _chunks_x * _chunks_z:
		var corner := Vector2i((chunk % _chunks_x) * CHUNK_CELLS, (chunk / _chunks_x) * CHUNK_CELLS)
		var size := Vector2(float(mini(CHUNK_CELLS, _width - corner.x)), float(mini(CHUNK_CELLS, _depth - corner.y))) * _cell
		var at := Vector3(_grid_origin.x + float(corner.x) * _cell, _ground_local, _grid_origin.z + float(corner.y) * _cell)
		var litter := LeafLitter.chunk(at, size, _litter_material)
		litter.name = "Litter%d" % chunk
		add_child(litter)
	for _block: int in _block_chunks.size():
		_views.append([null, null, null])
	for species: int in SPECIES:
		var view := _new_flakes(species, AABB(Vector3(_grid_origin.x, _ground_local - 0.2, _grid_origin.z), Vector3(float(_width) * _cell, 1.5, float(_depth) * _cell)))
		view.name = "Fading%d" % species
		_fade_views.append(view)
	_apply_globals()
	_warm_up()


## A MultiMesh of one species' hero leaves, empty.
func _new_flakes(species: int, box: AABB) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = LeafMeshes.mesh(species)
	var view := MultiMeshInstance3D.new()
	view.multimesh = multi
	view.material_override = _LeafShaders.flake_material("hero")
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.custom_aabb = box
	view.visibility_range_end = Constants.LEAF_HERO_RANGE
	view.visibility_range_end_margin = Constants.LEAF_HERO_FADE
	view.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	view.visible = false
	add_child(view)
	return view


## One leaf of each species in the hero and the mover materials, drawn tiny for
## a couple of frames, so the first stroke has no shader-compile hitch.
func _warm_up() -> void:
	var at := Vector3(_grid_origin.x + float(_width) * _cell * 0.5, _ground_local, _grid_origin.z + float(_depth) * _cell * 0.5)
	for mode: String in ["hero", "mover"]:
		for species: int in SPECIES:
			var view := MeshInstance3D.new()
			view.mesh = LeafMeshes.mesh(species)
			view.material_override = _LeafShaders.flake_material(mode)
			view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			view.set_meta("keep_material", true)
			add_child(view)
			view.transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.01), at)
			_warm.append(view)
	_warm_frames = 3


func _apply_globals() -> void:
	var corner := global_transform * Vector3(_grid_origin.x, 0.0, _grid_origin.z)
	_rect = Vector4(corner.x, corner.z, 1.0 / (float(_width) * _cell), 1.0 / (float(_depth) * _cell))
	RenderingServer.global_shader_parameter_set("leaf_height_map", _height_texture)
	RenderingServer.global_shader_parameter_set("leaf_cover_map", _cover_texture)
	RenderingServer.global_shader_parameter_set("leaf_rect", _rect)
	_globals_owner = self


## The yard's looks, from the trees the lot generator left on the field
## (meta "leaf_sources"). Rebuilt when they change (a new lot shapes the field).
func _refresh_looks(force: bool) -> void:
	var sources: Array = _field.get_meta("leaf_sources", [])
	var key := str(sources)
	if not force and key == _sources_key:
		return
	_sources_key = key
	var first := Vector2(_grid_origin.x + _cell * 0.5, _grid_origin.z + _cell * 0.5)
	var made := LeafPalette.cell_looks(sources, _width, _depth, first, _cell)
	_looks = made["looks"]
	_mix = made["mix"]
	_cell_look = made["cells"]
	_slot_floats.fill(null)
	_slot_species.fill(null)
	if _litter_material != null:
		_apply_season_look()


func _apply_season_look() -> void:
	_LeafShaders.set_wet(1.0 if _season == 1 else 0.0)
	if _litter_material == null:
		return
	var colors := LeafPalette.litter(_looks, _season)
	var centre := PackedVector4Array()
	var rim := PackedVector4Array()
	var alt_centre := PackedVector4Array()
	var alt_rim := PackedVector4Array()
	for index: int in LeafPalette.MAX_LOOKS:
		var entry: Dictionary = colors[mini(index, colors.size() - 1)]
		var a: Color = entry["centre"]
		var b: Color = entry["rim"]
		var c: Color = entry["alt_centre"]
		var d: Color = entry["alt_rim"]
		centre.append(Vector4(a.r, a.g, a.b, float(entry["age_lo"])))
		rim.append(Vector4(b.r, b.g, b.b, float(entry["age_hi"])))
		alt_centre.append(Vector4(c.r, c.g, c.b, float(entry["alt_share"])))
		# The skin draws each look's leaves in its tree's shape (w: species).
		var look: Dictionary = _looks[mini(index, _looks.size() - 1)] if not _looks.is_empty() else {}
		alt_rim.append(Vector4(d.r, d.g, d.b, float(look.get("species", LeafPalette.OVAL))))
	_litter_material.set_shader_parameter("look_centre", centre)
	_litter_material.set_shader_parameter("look_rim", rim)
	_litter_material.set_shader_parameter("look_alt_centre", alt_centre)
	_litter_material.set_shader_parameter("look_alt_rim", alt_rim)
	_litter_material.set_shader_parameter("look_count", maxi(colors.size(), 1))
	_litter_material.set_shader_parameter("wet", 1.0 if _season == 1 else 0.0)


# ---------------------------------------------------------------- field changes

func _on_chunk(chunk_index: int) -> void:
	if not _built:
		return
	_queued[chunk_index] = true
	_schedule_flush()


func _on_reset(hard: bool) -> void:
	if not _built:
		return
	if hard:
		_hard_pending = true
	for chunk: int in _chunks_x * _chunks_z:
		_queued[chunk] = true
	_schedule_flush()


func _schedule_flush() -> void:
	if _flush_scheduled:
		return
	_flush_scheduled = true
	call_deferred("_flush")


func _flush() -> void:
	_flush_scheduled = false
	if not _built:
		return
	var hard := _hard_pending
	# Before the field had field_reset (raking:1): a lot shaping or a snapshot
	# refreshes every chunk at once, and nothing else does.
	if not _has_reset and _queued.size() >= _chunks_x * _chunks_z:
		hard = true
	if hard:
		_hard_reset()
		return
	if _queued.is_empty():
		return
	var changes := PackedInt32Array()
	for key: Variant in _queued.keys():
		var chunk := int(key)
		if chunk < 0 or chunk >= _chunk_cells.size():
			continue
		for c: int in _chunk_cells[chunk]:
			var x := c % _width
			var z := c / _width
			var density := int(_field.call("density_at_cell", x, z))
			var delta := density - _target[c]
			if delta != 0:
				changes.append_array([x, z, delta])
				_target[c] = density
	_queued.clear()
	if changes.is_empty():
		return
	_claiming = true
	targets_changed.emit(changes, false)
	_claiming = false
	for index: int in range(0, changes.size(), 3):
		_update_morph(changes[index] + changes[index + 1] * _width)


func _hard_reset() -> void:
	_hard_pending = false
	_queued.clear()
	_claiming = true
	targets_changed.emit(PackedInt32Array(), true)
	_claiming = false
	_refresh_looks(false)
	_morphing.clear()
	_moving.clear()
	_pressing.clear()
	_fades.clear()
	for c: int in _target.size():
		var density := int(_field.call("density_at_cell", c % _width, c / _width))
		_target[c] = density
		_displayed[c] = density
		_pending[c] = 0
		_reserved[c] = 0
		_hidden[c] = 0
		_fading[c] = 0
		_morph_acc[c] = 0.0
		_press[c] = _press_goal(density)
	for c: int in _target.size():
		_height_goal[c] = mound_height(_blurred(c))
		_height[c] = _height_goal[c]
		_height_vel[c] = 0.0
		_write_cover(c)
		_slices[c] = null
	_heights_dirty = true
	_cover_dirty = true
	for chunk: int in _chunks_x * _chunks_z:
		_rebuild_chunk(chunk)
	_upload_blocks()
	_chunk_queue.clear()
	_cell_dirty.clear()
	_update_fade_views()
	_upload()


func _update_morph(c: int) -> void:
	var diff := _target[c] - _displayed[c] - _pending[c]
	if diff == 0:
		_morphing.erase(c)
		_morph_acc[c] = 0.0
		return
	_morph_rate[c] = maxf(float(absi(diff)) / Constants.LEAF_MORPH_SECONDS, 1.0 / Constants.LEAF_MORPH_SECONDS)
	_morphing[c] = true


func _set_displayed(c: int, value: int, cause: int) -> void:
	var old := _displayed[c]
	if value == old:
		return
	_displayed[c] = value
	var before := hero_count(old)
	var after := hero_count(value)
	if before != after:
		if cause == CAUSE_MORPH:
			for k: int in range(before, after):
				_fade_slot(c, k, 1)
			for k: int in range(after, before):
				_fade_slot(c, k, -1)
		_mark_cell(c, cause == CAUSE_HANDOFF)
	# The skin's height reads a 3 x 3 blur, so the neighbours move too.
	var x := c % _width
	var z := c / _width
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var nx := x + dx
			var nz := z + dz
			if nx < 0 or nz < 0 or nx >= _width or nz >= _depth:
				continue
			var n := nx + nz * _width
			_height_goal[n] = mound_height(_blurred(n))
			_moving[n] = true
	_pressing[c] = true
	_write_cover(c)
	_cover_dirty = true


## A cell's density blurred [1 2 1] x [1 2 1], the edge repeated.
func _blurred(c: int) -> float:
	var x := c % _width
	var z := c / _width
	var total := 0.0
	for dz: int in range(-1, 2):
		var nz := clampi(z + dz, 0, _depth - 1)
		var wz := 2.0 if dz == 0 else 1.0
		for dx: int in range(-1, 2):
			var nx := clampi(x + dx, 0, _width - 1)
			var wx := 2.0 if dx == 0 else 1.0
			total += wx * wz * float(clampi(_displayed[nx + nz * _width], 0, 255))
	return total / 16.0


func _press_goal(density: int) -> float:
	return smoothstep(Constants.LEAF_GRASS_PRESS.x, Constants.LEAF_GRASS_PRESS.y, float(density))


func _write_cover(c: int) -> void:
	var at := c * 4
	_cover_bytes[at] = clampi(_displayed[c], 0, 255)
	_cover_bytes[at + 1] = _cell_look[c]
	_cover_bytes[at + 2] = 0
	_cover_bytes[at + 3] = clampi(int(round(_press[c] * 255.0)), 0, 255)


# ---------------------------------------------------------------- every frame

func _process(delta: float) -> void:
	if not _built:
		return
	if _warm_frames > 0:
		_warm_frames -= 1
		if _warm_frames == 0:
			for view: Node in _warm:
				view.queue_free()
			_warm.clear()
	var dt := minf(delta, 0.05)
	_step_morph(dt)
	_step_fades(dt)
	_step_heights(dt)
	_step_press(dt)
	_rebuild_queued()
	if _gpu:
		var corner := global_transform * Vector3(_grid_origin.x, 0.0, _grid_origin.z)
		if not is_equal_approx(corner.x, _rect.x) or not is_equal_approx(corner.z, _rect.y) or _globals_owner != self:
			_apply_globals()
		_upload()


func _step_morph(dt: float) -> void:
	if _morphing.is_empty():
		return
	for key: Variant in _morphing.keys():
		var c := int(key)
		var diff := _target[c] - _displayed[c] - _pending[c]
		if diff == 0:
			_morphing.erase(c)
			_morph_acc[c] = 0.0
			continue
		_morph_acc[c] += _morph_rate[c] * dt
		var step := int(_morph_acc[c])
		if step <= 0:
			continue
		_morph_acc[c] -= float(step)
		step = mini(step, absi(diff))
		_morph_units += step
		_set_displayed(c, _displayed[c] + (step if diff > 0 else -step), CAUSE_MORPH)


func _fade_slot(c: int, k: int, direction: int) -> void:
	var key := c * 16 + k
	if _fades.has(key):
		var running: Array = _fades[key]
		if int(running[1]) != direction:
			running[0] = 1.0 - float(running[0])
			running[1] = direction
		if direction > 0:
			_fading[c] |= 1 << k
		else:
			_fading[c] &= ~(1 << k)
		return
	if _fades.size() >= Constants.LEAF_FADE_MAX:
		_instant += 1
		_note(Vector2i(c % _width, c / _width), k, "instant")
		return
	_fades[key] = [0.0, direction]
	if direction > 0:
		_fading[c] |= 1 << k
	_note(Vector2i(c % _width, c / _width), k, "morph_in" if direction > 0 else "morph_out")


## A slot a mover takes or fills: no fade on it any more.
func _end_fade(c: int, k: int) -> void:
	var key := c * 16 + k
	if _fades.erase(key):
		_fading[c] &= ~(1 << k)
		_mark_cell(c, true)


func _step_fades(dt: float) -> void:
	if _fades.is_empty():
		return
	for key: Variant in _fades.keys():
		var running: Array = _fades[key]
		running[0] = float(running[0]) + dt / Constants.LEAF_FADE_SECONDS
		if float(running[0]) >= 1.0:
			_fades.erase(key)
			var c := int(key) / 16
			var k := int(key) % 16
			if int(running[1]) > 0:
				_fading[c] &= ~(1 << k)
				_mark_cell(c, true)
	_update_fade_views()


func _update_fade_views() -> void:
	if not _gpu:
		return
	var buffers: Array = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for key: Variant in _fades:
		var running: Array = _fades[key]
		var c := int(key) / 16
		var k := int(key) % 16
		var t := clampf(float(running[0]), 0.0, 1.0)
		var grow := t * t * (3.0 - 2.0 * t)
		var size := grow if int(running[1]) > 0 else 1.0 - grow
		var floats := _slots_of(c)
		var species: PackedByteArray = _slot_species[c]
		var record := floats.slice(k * STRIDE, (k + 1) * STRIDE)
		for index: int in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
			record[index] *= maxf(size, 0.001)
		# Packed arrays held in an Array come out as copies: append, then put back.
		var into: PackedFloat32Array = buffers[species[k]]
		into.append_array(record)
		buffers[species[k]] = into
	for species: int in SPECIES:
		_fill(_fade_views[species], buffers[species])


func _step_heights(dt: float) -> void:
	if _moving.is_empty():
		return
	var omega := Constants.LEAF_MOUND_SPRING_W
	var zeta := Constants.LEAF_MOUND_SPRING_Z
	for key: Variant in _moving.keys():
		var c := int(key)
		var goal := _height_goal[c]
		var velocity := _height_vel[c] + (omega * omega * (goal - _height[c]) - 2.0 * zeta * omega * _height_vel[c]) * dt
		var height := _height[c] + velocity * dt
		if absf(goal - height) < 0.0004 and absf(velocity) < 0.004:
			height = goal
			velocity = 0.0
			_moving.erase(c)
		_height[c] = maxf(height, 0.0)
		_height_vel[c] = velocity
	_heights_dirty = true


func _step_press(dt: float) -> void:
	if _pressing.is_empty():
		return
	for key: Variant in _pressing.keys():
		var c := int(key)
		var goal := _press_goal(_displayed[c])
		var now := _press[c]
		if goal > now:
			now = minf(goal, now + dt / Constants.LEAF_GRASS_SETTLE)
		else:
			now = maxf(goal, now - dt / Constants.LEAF_GRASS_SPRING)
		_press[c] = now
		if is_equal_approx(now, goal):
			_pressing.erase(c)
		_write_cover(c)
	_cover_dirty = true


func _upload() -> void:
	if not _gpu:
		return
	if _heights_dirty:
		_heights_dirty = false
		_height_image.set_data(_width, _depth, false, Image.FORMAT_RF, _height.to_byte_array())
		_height_texture.update(_height_image)
	if _cover_dirty:
		_cover_dirty = false
		_cover_image.set_data(_width, _depth, false, Image.FORMAT_RGBA8, _cover_bytes)
		_cover_texture.update(_cover_image)


# ---------------------------------------------------------------- hero leaves

func _mark_cell(c: int, urgent: bool) -> void:
	_cell_dirty[c] = true
	var chunk := _chunk_of(c)
	_chunk_queue[chunk] = urgent or bool(_chunk_queue.get(chunk, false))


func _rebuild_queued() -> void:
	if _chunk_queue.is_empty():
		return
	var started := Time.get_ticks_usec()
	var budget := Constants.LEAF_REBUILD_BUDGET_MS * 1000.0
	# Chunks with launches, landings or kicks this frame always go first.
	var later: Array = []
	for key: Variant in _chunk_queue.keys():
		if bool(_chunk_queue[key]):
			_rebuild_chunk(int(key))
			_chunk_queue.erase(key)
		else:
			later.append(key)
	for key: Variant in later:
		if float(Time.get_ticks_usec() - started) > budget:
			break
		_rebuild_chunk(int(key))
		_chunk_queue.erase(key)
	_upload_blocks()
	_rebuild_ms_peak = maxf(_rebuild_ms_peak, float(Time.get_ticks_usec() - started) / 1000.0)


## A chunk's hero instance floats by species, from its cells' cached slices
## (only cells that changed are recomputed). Its block uploads afterwards.
func _rebuild_chunk(chunk: int) -> void:
	if chunk < 0 or chunk >= _chunk_cells.size():
		return
	_rebuilds += 1
	var cells: PackedInt32Array = _chunk_cells[chunk]
	for c: int in cells:
		if _cell_dirty.has(c) or _slices[c] == null:
			_cell_dirty.erase(c)
			_slices[c] = _cell_slices(c)
	var buffers: Array = []
	for species: int in SPECIES:
		var buffer := PackedFloat32Array()
		for c: int in cells:
			buffer.append_array((_slices[c] as Array)[species])
		buffers.append(buffer)
	_chunk_buffers[chunk] = buffers
	_block_dirty[_block_of(chunk)] = true


## Hero leaves draw per block of Constants.LEAF_HERO_BLOCK_CHUNKS squared
## chunks and species: the chunks' buffers joined, one MultiMesh each.
func _upload_blocks() -> void:
	if _block_dirty.is_empty():
		return
	for key: Variant in _block_dirty.keys():
		var block := int(key)
		var chunks: PackedInt32Array = _block_chunks[block]
		for species: int in SPECIES:
			var buffer := PackedFloat32Array()
			for chunk: int in chunks:
				if _chunk_buffers[chunk] != null:
					buffer.append_array((_chunk_buffers[chunk] as Array)[species])
			if not _gpu:
				continue
			var view: MultiMeshInstance3D = _views[block][species]
			if view == null:
				if buffer.is_empty():
					continue
				view = _new_flakes(species, _block_boxes[block])
				view.name = "Heroes%d_%d" % [block, species]
				_views[block][species] = view
			_fill(view, buffer)
	_block_dirty.clear()

func _fill(view: MultiMeshInstance3D, buffer: PackedFloat32Array) -> void:
	var count := buffer.size() / STRIDE
	var multi := view.multimesh
	if multi.instance_count != count:
		multi.instance_count = count
	if count > 0:
		multi.buffer = buffer
	view.visible = count > 0


## A cell's drawn hero leaves, by species.
func _cell_slices(c: int) -> Array:
	var out: Array = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	var count := hero_count(_displayed[c])
	if count == 0:
		return out
	var floats := _slots_of(c)
	var species: PackedByteArray = _slot_species[c]
	var skip := _hidden[c] | _fading[c]
	for k: int in count:
		if (skip & (1 << k)) != 0:
			continue
		var into: PackedFloat32Array = out[species[k]]
		into.append_array(floats.slice(k * STRIDE, (k + 1) * STRIDE))
		out[species[k]] = into
	return out


## Every slot of a cell as MultiMesh instance floats (local to this node), cached.
func _slots_of(c: int) -> PackedFloat32Array:
	if _slot_floats[c] != null:
		return _slot_floats[c]
	var x := c % _width
	var z := c / _width
	var floats := PackedFloat32Array()
	var species := PackedByteArray()
	var centre := Vector2(_grid_origin.x + (float(x) + 0.5) * _cell, _grid_origin.z + (float(z) + 0.5) * _cell)
	for k: int in Constants.LEAF_HERO_MAX:
		var spot := LeafPalette.slot(x, z, k)
		# Each leaf takes the look of a cell near it, so tree colours blend leaf by leaf.
		var jx := clampi(x + int(round((LeafPalette.unit(x, z, k, 50) * 2.0 - 1.0) * 1.6)), 0, _width - 1)
		var jz := clampi(z + int(round((LeafPalette.unit(x, z, k, 51) * 2.0 - 1.0) * 1.6)), 0, _depth - 1)
		var leaf := LeafPalette.flake(_looks, _mix, _cell_look[jx + jz * _width], _season, x, z, k)
		var length := float(spot["size"]) * float(leaf["scale"])
		var basis := Basis.from_euler(Vector3(float(spot["tilt_x"]), float(spot["yaw"]), float(spot["tilt_z"]))) * Basis.from_scale(Vector3(length * float(leaf["width"]), length, length))
		var offset: Vector2 = spot["offset"]
		var origin := Vector3(centre.x + offset.x, _ground_local + Constants.LEAF_HERO_LIFT.x + Constants.LEAF_HERO_LIFT.y * float(k), centre.y + offset.y)
		var color: Color = leaf["centre"]
		var rim: Color = leaf["rim"]
		floats.append_array([
			basis.x.x, basis.y.x, basis.z.x, origin.x,
			basis.x.y, basis.y.y, basis.z.y, origin.y,
			basis.x.z, basis.y.z, basis.z.z, origin.z,
			color.r, color.g, color.b, float(leaf["age"]),
			rim.r, rim.g, rim.b, float(leaf["loose"]),
		])
		species.append(int(leaf["species"]))
	_slot_floats[c] = floats
	_slot_species[c] = species
	return floats


func _slot_info(cell: Vector2i, k: int) -> Dictionary:
	var c := _index(cell)
	var floats := _slots_of(c)
	var at := k * STRIDE
	return {
		"xform": slot_world(cell, k),
		"color": Color(floats[at + 12], floats[at + 13], floats[at + 14], floats[at + 15]),
		"custom": Color(floats[at + 16], floats[at + 17], floats[at + 18], floats[at + 19]),
		"species": int((_slot_species[c] as PackedByteArray)[k]),
		"slot": k,
	}


## A leaf on the skin somewhere in a cell (for units that leave or arrive
## without a hero leaf of their own).
func _skin_point(cell: Vector2i) -> Dictionary:
	_skin_counter += 1
	var k := Constants.LEAF_HERO_MAX + (_skin_counter % 64)
	var c := _index(cell)
	var spot := LeafPalette.slot(cell.x, cell.y, k)
	var leaf := LeafPalette.flake(_looks, _mix, _cell_look[c] if c >= 0 else 0, _season, cell.x, cell.y, k)
	var offset: Vector2 = spot["offset"]
	var local := Vector3(_grid_origin.x + (float(cell.x) + 0.5) * _cell + offset.x, _ground_local, _grid_origin.z + (float(cell.y) + 0.5) * _cell + offset.y)
	var world := global_transform * local
	world.y = surface_y(Vector2(world.x, world.z))
	var length := float(spot["size"]) * float(leaf["scale"])
	var basis := Basis(Vector3.UP, float(spot["yaw"])) * Basis.from_scale(Vector3(length * float(leaf["width"]), length, length))
	var centre: Color = leaf["centre"]
	var rim: Color = leaf["rim"]
	return {
		"xform": Transform3D(basis, world),
		"color": Color(centre.r, centre.g, centre.b, float(leaf["age"])),
		"custom": Color(rim.r, rim.g, rim.b, float(leaf["loose"])),
		"species": int(leaf["species"]),
		"slot": -1,
	}


# ---------------------------------------------------------------- helpers

func _index(cell: Vector2i) -> int:
	if not _built or cell.x < 0 or cell.y < 0 or cell.x >= _width or cell.y >= _depth:
		return -1
	return cell.x + cell.y * _width


func _block_of(chunk: int) -> int:
	var per := maxi(Constants.LEAF_HERO_BLOCK_CHUNKS, 1)
	return int((chunk % _chunks_x) / per) + int((chunk / _chunks_x) / per) * _blocks_x


func _chunk_of(c: int) -> int:
	return int((c % _width) / CHUNK_CELLS) + int((c / _width) / CHUNK_CELLS) * _chunks_x


## A world xz point in this node's local xz.
func _to_local_xz(world_xz: Vector2) -> Vector2:
	var local := global_transform.affine_inverse() * Vector3(world_xz.x, 0.0, world_xz.y)
	return Vector2(local.x, local.z)


## The skin's height and slope (per meter, x and z) at a local xz point:
## bilinear between cell centres, the edge repeated (the shaders' leaf_height).
func _height_at_local(local: Vector2) -> Vector3:
	if not _built:
		return Vector3.ZERO
	var gx := (local.x - _grid_origin.x) / _cell - 0.5
	var gz := (local.y - _grid_origin.z) / _cell - 0.5
	var ix := int(floor(gx))
	var iz := int(floor(gz))
	var fx := gx - float(ix)
	var fz := gz - float(iz)
	var a := _h(ix, iz)
	var b := _h(ix + 1, iz)
	var d := _h(ix, iz + 1)
	var e := _h(ix + 1, iz + 1)
	var height := lerpf(lerpf(a, b, fx), lerpf(d, e, fx), fz)
	var slope_x := ((b - a) * (1.0 - fz) + (e - d) * fz) / _cell
	var slope_z := ((d - a) * (1.0 - fx) + (e - b) * fx) / _cell
	return Vector3(height, slope_x, slope_z)


func _h(x: int, z: int) -> float:
	return _height[clampi(x, 0, _width - 1) + clampi(z, 0, _depth - 1) * _width]


func _note(cell: Vector2i, slot: int, what: String) -> void:
	if not _log_on or _log.size() >= LOG_MAX:
		return
	_log.append({"cell": cell, "slot": slot, "what": what, "frame": Engine.get_process_frames()})
