extends RefCounted

## Authority: local, cosmetic. Things people leave behind that make a street
## feel lived in, drawn in code into textures (no image files): spray-paint tags
## with bubble outlines and drips, sidewalk chalk (hopscotch, a smiley, a stick
## figure, a sun, a little house, hearts), sticky notes with scribbles, and paper
## posters on lamp posts. None of them have words: names, jokes, and writing in
## the world are design decisions (docs/GAME.md), so scribbles stand in for text.
## Textures are cached by kind and seed, so the same seed looks the same on
## every peer. place_*() put them in the world as decals or paper cards.

const CHALK: Array[Color] = [Color(0.95, 0.35, 0.55), Color(0.98, 0.55, 0.2), Color(0.25, 0.6, 0.95), Color(0.98, 0.8, 0.15), Color(0.35, 0.75, 0.35), Color(0.65, 0.4, 0.9)]
const SPRAY: Array[Color] = [Color(0.95, 0.3, 0.55), Color(0.3, 0.75, 0.95), Color(0.98, 0.85, 0.2), Color(0.45, 0.85, 0.35), Color(0.7, 0.4, 0.95), Color(0.98, 0.55, 0.15)]
const NOTE_PAPER: Array[Color] = [Color(0.99, 0.93, 0.45), Color(0.99, 0.72, 0.8), Color(0.62, 0.88, 0.99), Color(0.7, 0.96, 0.6)]
const INK := Color(0.12, 0.13, 0.25)

static var _cache: Dictionary = {}
static var _brushes: Dictionary = {}


# ---------------------------------------------------------------- textures

## A spray-paint tag: a run of fat bubble loops with a dark outline, a light
## highlight, and a few drips, plus a little star or arrow flourish.
static func graffiti(seed_value: int) -> Texture2D:
	return _cached("graffiti", seed_value, func() -> Image:
		var rng := _rng(seed_value)
		var image := Image.create(512, 256, false, Image.FORMAT_RGBA8)
		var fill: Color = SPRAY[rng.randi() % SPRAY.size()]
		var outline := fill.darkened(0.7)
		var points := PackedVector2Array()
		var x := 70.0
		var y := 128.0
		var loops := rng.randi_range(4, 6)
		for loop: int in loops:
			var size := rng.randf_range(28.0, 46.0)
			for step: int in 14:
				var angle := TAU * float(step) / 13.0 + float(loop)
				points.append(Vector2(x + cos(angle) * size * 0.6 + float(step) * 2.0, y + sin(angle) * size + rng.randf_range(-4.0, 4.0)))
			x += rng.randf_range(55.0, 80.0)
			y = clampf(y + rng.randf_range(-22.0, 22.0), 90.0, 160.0)
		_stroke(image, points, 26.0, outline)
		_stroke(image, points, 19.0, fill)
		_stroke(image, _shifted(points, Vector2(-5.0, -7.0)), 5.0, fill.lightened(0.5))
		# Drips running down from the bottom of the letters.
		for drip: int in rng.randi_range(3, 6):
			var at := points[rng.randi() % points.size()]
			var length := rng.randf_range(15.0, 60.0)
			_stroke(image, PackedVector2Array([at, at + Vector2(0.0, length)]), 3.5, fill)
			_disc(image, at + Vector2(0.0, length), 5.0, fill)
		# A flourish: a star, or an arrow underlining it.
		if rng.randf() < 0.5:
			_star(image, Vector2(470.0, 50.0), 26.0, SPRAY[rng.randi() % SPRAY.size()], outline)
		else:
			_stroke(image, PackedVector2Array([Vector2(50.0, 215.0), Vector2(440.0, 205.0)]), 6.0, outline)
			_stroke(image, PackedVector2Array([Vector2(415.0, 185.0), Vector2(445.0, 205.0), Vector2(415.0, 228.0)]), 6.0, outline)
		_speckle(image, rng, fill, 260)
		return image
	)


## Sidewalk chalk: "hopscotch", "smiley", "stick_figure", "sun", "house", or "hearts".
static func chalk(kind: String, seed_value: int) -> Texture2D:
	return _cached("chalk_" + kind, seed_value, func() -> Image:
		var rng := _rng(seed_value)
		var size := Vector2i(256, 512) if kind == "hopscotch" else Vector2i(256, 256)
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		var color: Color = CHALK[rng.randi() % CHALK.size()]
		match kind:
			"hopscotch":
				var rows := [[1], [2], [1], [2], [1], [2]]
				var y := 480.0
				for row: Array in rows:
					var cells := int(row[0])
					for cell: int in cells:
						var left := 128.0 - 40.0 * float(cells) + 80.0 * float(cell)
						_chalk_box(image, rng, Rect2(left, y - 74.0, 80.0, 74.0), color)
					y -= 76.0
				_chalk_line(image, rng, _circle(Vector2(128.0, 26.0), 22.0, 18), CHALK[(rng.randi() + 1) % CHALK.size()])
			"smiley":
				_chalk_line(image, rng, _circle(Vector2(128.0, 128.0), 100.0, 36), color)
				_disc(image, Vector2(92.0, 100.0), 10.0, color)
				_disc(image, Vector2(164.0, 100.0), 10.0, color)
				_chalk_line(image, rng, _arc(Vector2(128.0, 135.0), 55.0, 0.3, PI - 0.3, 16), color)
			"stick_figure":
				_chalk_line(image, rng, _circle(Vector2(128.0, 50.0), 26.0, 18), color)
				_chalk_line(image, rng, PackedVector2Array([Vector2(128.0, 76.0), Vector2(128.0, 160.0)]), color)
				_chalk_line(image, rng, PackedVector2Array([Vector2(78.0, 95.0), Vector2(128.0, 112.0), Vector2(190.0, 70.0)]), color)
				_chalk_line(image, rng, PackedVector2Array([Vector2(92.0, 232.0), Vector2(128.0, 160.0), Vector2(168.0, 232.0)]), color)
			"sun":
				_chalk_line(image, rng, _circle(Vector2(128.0, 128.0), 48.0, 24), CHALK[3])
				for ray: int in 10:
					var angle := TAU * float(ray) / 10.0
					_chalk_line(image, rng, PackedVector2Array([Vector2(128.0, 128.0) + Vector2(cos(angle), sin(angle)) * 64.0, Vector2(128.0, 128.0) + Vector2(cos(angle), sin(angle)) * 110.0]), CHALK[3])
			"house":
				_chalk_box(image, rng, Rect2(58.0, 118.0, 140.0, 110.0), color)
				_chalk_line(image, rng, PackedVector2Array([Vector2(48.0, 122.0), Vector2(128.0, 40.0), Vector2(208.0, 122.0)]), CHALK[1])
				_chalk_box(image, rng, Rect2(112.0, 168.0, 34.0, 60.0), CHALK[2])
			_:
				for heart: int in 3:
					_heart(image, rng, Vector2(rng.randf_range(60.0, 196.0), rng.randf_range(60.0, 196.0)), rng.randf_range(24.0, 44.0), CHALK[rng.randi() % CHALK.size()])
		return image
	)


## A sticky note: square colored paper, a few lines of scribble, and sometimes a
## tiny doodle (a smiley, a heart, or an arrow).
static func note(seed_value: int) -> Texture2D:
	return _cached("note", seed_value, func() -> Image:
		var rng := _rng(seed_value)
		var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		var paper: Color = NOTE_PAPER[rng.randi() % NOTE_PAPER.size()]
		image.fill(paper)
		image.fill_rect(Rect2i(0, 0, 128, 14), paper.darkened(0.08))
		var lines := rng.randi_range(2, 4)
		for line: int in lines:
			_scribble(image, rng, Vector2(14.0, 30.0 + float(line) * 20.0), rng.randf_range(60.0, 100.0), INK)
		match rng.randi() % 4:
			0:
				_stroke(image, _circle(Vector2(100.0, 104.0), 12.0, 14), 1.6, INK)
				_disc(image, Vector2(96.0, 101.0), 1.8, INK)
				_disc(image, Vector2(104.0, 101.0), 1.8, INK)
				_stroke(image, _arc(Vector2(100.0, 104.0), 7.0, 0.4, PI - 0.4, 8), 1.4, INK)
			1:
				_heart(image, rng, Vector2(100.0, 104.0), 11.0, Color(0.85, 0.15, 0.2))
			2:
				_stroke(image, PackedVector2Array([Vector2(70.0, 108.0), Vector2(112.0, 108.0), Vector2(102.0, 98.0)]), 1.8, INK)
			_:
				pass
		return image
	)


## A paper poster for a lamp post: a drawn cat (or a tall wavy thing) and lines
## of scribble where the words would go, with tear-off tabs at the bottom.
static func poster(seed_value: int) -> Texture2D:
	return _cached("poster", seed_value, func() -> Image:
		var rng := _rng(seed_value)
		var image := Image.create(128, 176, false, Image.FORMAT_RGBA8)
		var paper := Color(0.97, 0.96, 0.9) if rng.randf() < 0.6 else Color(0.98, 0.85, 0.6)
		image.fill(paper)
		_scribble(image, rng, Vector2(18.0, 18.0), 92.0, INK)
		# A cat: round head, triangle ears, whiskers, a curly tail.
		var center := Vector2(64.0, 78.0)
		_stroke(image, _circle(center, 26.0, 20), 2.2, INK)
		_stroke(image, PackedVector2Array([center + Vector2(-22.0, -12.0), center + Vector2(-18.0, -36.0), center + Vector2(-4.0, -24.0)]), 2.2, INK)
		_stroke(image, PackedVector2Array([center + Vector2(22.0, -12.0), center + Vector2(18.0, -36.0), center + Vector2(4.0, -24.0)]), 2.2, INK)
		_disc(image, center + Vector2(-9.0, -4.0), 2.6, INK)
		_disc(image, center + Vector2(9.0, -4.0), 2.6, INK)
		for side: float in [-1.0, 1.0]:
			_stroke(image, PackedVector2Array([center + Vector2(side * 8.0, 6.0), center + Vector2(side * 30.0, 2.0)]), 1.0, INK)
			_stroke(image, PackedVector2Array([center + Vector2(side * 8.0, 9.0), center + Vector2(side * 30.0, 12.0)]), 1.0, INK)
		_stroke(image, _arc(center + Vector2(0.0, 8.0), 6.0, 0.2, PI - 0.2, 8), 1.2, INK)
		for line: int in 3:
			_scribble(image, rng, Vector2(16.0, 120.0 + float(line) * 12.0), rng.randf_range(70.0, 96.0), INK)
		for tab: int in 6:
			var left := 8 + tab * 19
			image.fill_rect(Rect2i(left, 160, 1, 16), paper.darkened(0.25))
		return image
	)


# ---------------------------------------------------------------- placing

## A decal on whatever is under it (the ground faces up), size in meters.
static func place_on_ground(parent: Node3D, texture: Texture2D, at: Vector3, size: Vector2, yaw: float = 0.0, fade: float = 0.85) -> Decal:
	var decal := Decal.new()
	decal.texture_albedo = texture
	decal.size = Vector3(size.x, 0.6, size.y)
	decal.modulate = Color(1.0, 1.0, 1.0, fade)
	decal.cull_mask = 1
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 40.0
	decal.distance_fade_length = 15.0
	parent.add_child(decal)
	decal.position = at
	decal.rotation.y = yaw
	return decal


## A decal on a wall that faces normal (in parent space), size in meters, the
## texture's top toward the sky.
static func place_on_wall(parent: Node3D, texture: Texture2D, at: Vector3, normal: Vector3, size: Vector2, fade: float = 0.95) -> Decal:
	var decal := Decal.new()
	decal.texture_albedo = texture
	decal.size = Vector3(size.x, 0.5, size.y)
	decal.modulate = Color(1.0, 1.0, 1.0, fade)
	decal.cull_mask = 1
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 50.0
	decal.distance_fade_length = 15.0
	parent.add_child(decal)
	# A decal projects down its -Y, so its +Y points out of the wall.
	var out := normal.normalized()
	var across := Vector3.UP.cross(out).normalized()
	decal.transform = Transform3D(Basis(across, out, across.cross(out)), at)
	return decal


## A paper card stuck on a surface facing normal: a sticky note or a poster,
## slightly tilted and with one corner curling off, size in meters.
static func place_paper(parent: Node3D, texture: Texture2D, at: Vector3, normal: Vector3, size: Vector2, tilt: float = 0.0) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var card := MeshInstance3D.new()
	card.mesh = quad
	card.material_override = material
	card.set_meta("keep_material", true)
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(card)
	card.position = at + normal.normalized() * 0.012
	card.look_at(card.global_position + normal, Vector3.UP if absf(normal.y) < 0.9 else Vector3.FORWARD)
	card.rotate_object_local(Vector3.UP, PI)
	card.rotate_object_local(Vector3.BACK, tilt)
	# A curl: tipped off the surface a touch.
	card.rotate_object_local(Vector3.RIGHT, 0.08)
	return card


# ---------------------------------------------------------------- drawing

static func _cached(kind: String, seed_value: int, draw: Callable) -> Texture2D:
	var key := "%s|%d" % [kind, seed_value]
	if not _cache.has(key):
		var image: Image = draw.call()
		image.generate_mipmaps()
		_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## A round soft-edged brush of this radius and color, made once and reused.
static func _brush(radius: float, color: Color) -> Image:
	var key := "%.1f|%s" % [radius, color.to_html()]
	if _brushes.has(key):
		return _brushes[key]
	var size := int(ceil(radius * 2.0)) + 2
	var brush := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var middle := Vector2(size, size) * 0.5
	for y: int in size:
		for x: int in size:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(middle)
			var alpha := clampf(radius - distance + 0.5, 0.0, 1.0)
			if alpha > 0.0:
				brush.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * alpha))
	_brushes[key] = brush
	return brush


static func _disc(image: Image, at: Vector2, radius: float, color: Color) -> void:
	var brush := _brush(radius, color)
	var corner := Vector2i(at - Vector2(brush.get_width(), brush.get_height()) * 0.5)
	image.blend_rect(brush, Rect2i(Vector2i.ZERO, brush.get_size()), corner)


## A smooth line through points, stamped with a round brush.
static func _stroke(image: Image, points: PackedVector2Array, radius: float, color: Color) -> void:
	if points.size() == 1:
		_disc(image, points[0], radius, color)
	var step := maxf(radius * 0.35, 0.75)
	for index: int in points.size() - 1:
		var a := points[index]
		var b := points[index + 1]
		var stamps := maxi(1, int(a.distance_to(b) / step))
		for stamp: int in stamps + 1:
			_disc(image, a.lerp(b, float(stamp) / float(stamps)), radius, color)


## Chalk: a rough line that skips and doubles back, never quite solid.
static func _chalk_line(image: Image, rng: RandomNumberGenerator, points: PackedVector2Array, color: Color) -> void:
	var rough := PackedVector2Array()
	for point: Vector2 in points:
		rough.append(point + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5)))
	var faded := color
	faded.a = 0.9
	_stroke(image, rough, 7.5, faded)
	var dust := color.lightened(0.3)
	dust.a = 0.45
	_stroke(image, _shifted(rough, Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))), 5.0, dust)


static func _chalk_box(image: Image, rng: RandomNumberGenerator, rect: Rect2, color: Color) -> void:
	_chalk_line(image, rng, PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end, rect.position + Vector2(0.0, rect.size.y), rect.position]), color)


## A line of handwriting that isn't words: loops along a baseline.
static func _scribble(image: Image, rng: RandomNumberGenerator, start: Vector2, length: float, color: Color) -> void:
	var points := PackedVector2Array()
	var x := start.x
	while x < start.x + length:
		points.append(Vector2(x, start.y + rng.randf_range(-5.0, 1.0)))
		x += rng.randf_range(2.5, 5.0)
		points.append(Vector2(x, start.y + rng.randf_range(0.0, 3.0)))
		x += rng.randf_range(2.0, 4.0)
		if rng.randf() < 0.12:
			_stroke(image, points, 1.2, color)
			points = PackedVector2Array()
			x += rng.randf_range(4.0, 8.0)
	_stroke(image, points, 1.2, color)


static func _heart(image: Image, rng: RandomNumberGenerator, at: Vector2, size: float, color: Color) -> void:
	var points := PackedVector2Array()
	for step: int in 25:
		var t := TAU * float(step) / 24.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		points.append(at + Vector2(x, y) * size / 16.0 + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)))
	_stroke(image, points, maxf(1.5, size * 0.08), color)


static func _star(image: Image, at: Vector2, size: float, fill: Color, outline: Color) -> void:
	var points := PackedVector2Array()
	for step: int in 11:
		var angle := -PI * 0.5 + TAU * float(step) / 10.0
		var radius := size if step % 2 == 0 else size * 0.45
		points.append(at + Vector2(cos(angle), sin(angle)) * radius)
	_stroke(image, points, 7.0, outline)
	_stroke(image, points, 4.0, fill)


static func _speckle(image: Image, rng: RandomNumberGenerator, color: Color, count: int) -> void:
	var mist := color
	mist.a = 0.5
	for _index: int in count:
		_disc(image, Vector2(rng.randf_range(20.0, 492.0), rng.randf_range(30.0, 230.0)), rng.randf_range(0.6, 1.6), mist)


static func _circle(center: Vector2, radius: float, steps: int) -> PackedVector2Array:
	return _arc(center, radius, 0.0, TAU, steps)


static func _arc(center: Vector2, radius: float, from: float, to: float, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step: int in steps + 1:
		var angle := lerpf(from, to, float(step) / float(steps))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _shifted(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	for point: Vector2 in points:
		moved.append(point + by)
	return moved
