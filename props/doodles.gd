extends RefCounted

## Authority: local, cosmetic. Things people leave behind that make a street
## feel lived in, drawn in code into textures (no image files): spray-paint tags
## with bubble outlines and drips, sidewalk chalk (hopscotch, a smiley, a stick
## figure, a sun, a little house, hearts), sticky notes, and paper posters on
## lamp posts.
##
## cast:7, words in the world (docs/GAME.md "Words in the world"): every poster
## and sticky note says something, from ui/strings.gd SIGNS (the POSTERS and
## NOTES keys). A poster is a title, its own picture and a body line (the
## courtesy notice carries a Daisy Seal, props/nice_seal.gd); a note is one line
## in ballpoint or marker. The words are printed: a Label3D on the card a hair in
## front of the paper, depth-tested, never billboarded, so they tilt, curl and
## hide behind things with it, and fade out past Constants.WORDS_VISIBLE_M.
## Which words come from the seed, so every peer reads the same street.
## Textures are cached by kind and seed (posters by key), so the same seed looks
## the same on every peer. place_*() put them in the world as decals or paper cards.

const _NiceSeal = preload("res://props/nice_seal.gd")
const _Strings = preload("res://ui/strings.gd")

const CHALK: Array[Color] = [Color(0.95, 0.35, 0.55), Color(0.98, 0.55, 0.2), Color(0.25, 0.6, 0.95), Color(0.98, 0.8, 0.15), Color(0.35, 0.75, 0.35), Color(0.65, 0.4, 0.9)]
const SPRAY: Array[Color] = [Color(0.95, 0.3, 0.55), Color(0.3, 0.75, 0.95), Color(0.98, 0.85, 0.2), Color(0.45, 0.85, 0.35), Color(0.7, 0.4, 0.95), Color(0.98, 0.55, 0.15)]
const NOTE_PAPER: Array[Color] = [Color(0.99, 0.93, 0.45), Color(0.99, 0.72, 0.8), Color(0.62, 0.88, 0.99), Color(0.7, 0.96, 0.6)]
const INK := Color(0.12, 0.13, 0.25)
## A note's pen: blue ballpoint or black marker.
const NOTE_INKS: Array[Color] = [Color(0.13, 0.2, 0.55), Color(0.1, 0.1, 0.12)]
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)

## The posters and notes in rotation (Strings.SIGNS keys). A poster's first line
## is its title, the rest its body.
const POSTERS: Array[String] = ["poster_gnome", "poster_courtesy", "poster_depot", "poster_yard_sale", "poster_turf", "poster_cat"]
const NOTES: Array[String] = ["note_side", "note_2am", "note_mailman", "note_rake", "note_gerald", "note_hoa"]
## Each poster's paper, title ink, the band behind its title (CLEAR for none) and
## whether it has tear-off tabs. The courtesy notice is Courtesy Lavender's deep
## rosette; Homie Depot's flyer is the store's orange; TurfMasters™' is lawn green.
const POSTER_LOOKS: Dictionary = {
	"poster_gnome": {"paper": Color(0.97, 0.96, 0.9), "title": Color(0.72, 0.12, 0.1), "band": CLEAR, "tabs": true},
	"poster_courtesy": {"paper": Color(0.96, 0.95, 0.99), "title": Color(0.98, 0.98, 0.95), "band": _NiceSeal.ROSETTE, "tabs": false},
	"poster_depot": {"paper": Color(0.98, 0.97, 0.92), "title": Color(0.99, 0.98, 0.95), "band": Color(0.95, 0.5, 0.15), "tabs": false},
	"poster_yard_sale": {"paper": Color(0.99, 0.9, 0.38), "title": Color(0.12, 0.13, 0.25), "band": CLEAR, "tabs": true},
	"poster_turf": {"paper": Color(0.95, 0.98, 0.93), "title": Color(0.99, 0.98, 0.95), "band": Color(0.13, 0.45, 0.22), "tabs": false},
	"poster_cat": {"paper": Color(0.98, 0.85, 0.6), "title": Color(0.12, 0.13, 0.25), "band": CLEAR, "tabs": true},
}
## The poster texture (px) and where its parts are, top to bottom (px): the title
## band, the picture's middle, where the body starts and where the tabs start.
const POSTER_PX := Vector2i(256, 352)
const POSTER_TITLE_Y: float = 34.0
const POSTER_PICTURE_Y: float = 150.0
const POSTER_BODY_Y: float = 238.0
const POSTER_TABS_Y: float = 322.0
## Words keep this share of the paper's width.
const WORDS_WIDTH_SHARE: float = 0.86
## How heavy the titles and the rest are drawn (FontVariation embolden).
const WORDS_TITLE_WEIGHT: float = 0.8
const WORDS_BODY_WEIGHT: float = 0.55

static var _cache: Dictionary = {}
static var _brushes: Dictionary = {}
static var _fonts: Dictionary = {}


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


## The words on the note this seed makes (a Strings.SIGNS key from NOTES).
static func note_key(seed_value: int) -> String:
	return NOTES[posmod(seed_value, NOTES.size())]


## The poster this seed makes (a Strings.SIGNS key from POSTERS).
static func poster_key(seed_value: int) -> String:
	return POSTERS[posmod(seed_value, POSTERS.size())]


## A sticky note's paper: square, colored, a darker glue strip along the top,
## and sometimes a tiny doodle in the corner (a smiley, a heart, an underline)
## clear of where its words go (place_note).
static func note(seed_value: int) -> Texture2D:
	return _cached("note", seed_value, func() -> Image:
		var rng := _rng(seed_value)
		var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		var paper: Color = NOTE_PAPER[rng.randi() % NOTE_PAPER.size()]
		image.fill(paper)
		image.fill_rect(Rect2i(0, 0, 128, 14), paper.darkened(0.08))
		var pen: Color = NOTE_INKS[posmod(seed_value, NOTE_INKS.size())]
		match rng.randi() % 4:
			0:
				_stroke(image, _circle(Vector2(108.0, 110.0), 9.0, 14), 1.4, pen)
				_disc(image, Vector2(105.0, 108.0), 1.5, pen)
				_disc(image, Vector2(111.0, 108.0), 1.5, pen)
				_stroke(image, _arc(Vector2(108.0, 110.0), 5.0, 0.4, PI - 0.4, 8), 1.2, pen)
			1:
				_heart(image, rng, Vector2(108.0, 110.0), 8.0, Color(0.85, 0.15, 0.2))
			2:
				_stroke(image, PackedVector2Array([Vector2(30.0, 104.0), Vector2(98.0, 102.0)]), 1.4, pen)
			_:
				pass
		return image
	)


## A paper poster for a lamp post (the seed's POSTERS key): poster_paper().
static func poster(seed_value: int) -> Texture2D:
	return poster_paper(poster_key(seed_value))


## A poster's paper for a POSTERS key: its paper, the band behind its title, its
## picture, tape at the top corners and, for the lost-and-found ones, tear-off
## tabs with scribbled numbers. The words are place_poster's.
static func poster_paper(key: String) -> Texture2D:
	return _cached("poster_" + key, 0, func() -> Image:
		var rng := _rng(hash(key))
		var look: Dictionary = POSTER_LOOKS.get(key, POSTER_LOOKS["poster_cat"])
		var image := Image.create(POSTER_PX.x, POSTER_PX.y, false, Image.FORMAT_RGBA8)
		var paper: Color = look["paper"]
		image.fill(paper)
		var band: Color = look["band"]
		if band.a > 0.0:
			image.fill_rect(Rect2i(0, 0, POSTER_PX.x, int(POSTER_TITLE_Y * 2.0)), band)
		var middle := Vector2(POSTER_PX.x * 0.5, POSTER_PICTURE_Y)
		match key:
			"poster_gnome":
				_gnome(image, middle)
			"poster_courtesy":
				# The seal is a mesh over this (place_poster); the fine print and a
				# signature line under the words.
				for line: int in 3:
					_scribble(image, rng, Vector2(28.0, 300.0 + float(line) * 9.0), rng.randf_range(120.0, 190.0), Color(0.45, 0.42, 0.55))
				_stroke(image, PackedVector2Array([Vector2(150.0, 336.0), Vector2(232.0, 336.0)]), 1.0, INK)
				_scribble(image, rng, Vector2(156.0, 330.0), 60.0, Color(0.36, 0.24, 0.55))
				_frame(image, 6, _NiceSeal.ROSETTE)
			"poster_depot":
				_star(image, Vector2(186.0, 102.0), 30.0, Color(0.99, 0.85, 0.2), Color(0.95, 0.5, 0.15))
				_rake(image, middle)
			"poster_yard_sale":
				_leaf_pile(image, rng, middle)
			"poster_turf":
				_trophy(image, middle)
			_:
				_cat(image, middle)
		if bool(look["tabs"]):
			for tab: int in 8:
				var left := 4 + tab * 31
				image.fill_rect(Rect2i(left + 30, int(POSTER_TABS_Y), 1, POSTER_PX.y - int(POSTER_TABS_Y)), paper.darkened(0.25))
				for digit: int in 2:
					_scribble(image, rng, Vector2(left + 8.0 + float(digit) * 7.0, POSTER_TABS_Y + 14.0), 8.0, INK)
		# Clear tape over the top corners.
		image.blend_rect(_tape(), Rect2i(0, 0, 34, 16), Vector2i(-6, 2))
		image.blend_rect(_tape(), Rect2i(0, 0, 34, 16), Vector2i(POSTER_PX.x - 28, 2))
		_speckle_rect(image, rng, paper.darkened(0.12), 120, Rect2(4.0, 4.0, POSTER_PX.x - 8.0, POSTER_PX.y - 8.0))
		return image
	)


# ---------------------------------------------------------------- words

## A poster on a surface (place_paper, size in meters) with its words printed on
## it, and for the courtesy notice a Daisy Seal; the seed picks which poster.
## Returns the card; its meta "words" is the Strings.SIGNS key.
static func place_poster(parent: Node3D, seed_value: int, at: Vector3, normal: Vector3, size: Vector2, tilt: float = 0.0) -> MeshInstance3D:
	var key := poster_key(seed_value)
	var card := place_paper(parent, poster_paper(key), at, normal, size, tilt)
	card.name = "Poster"
	card.set_meta("words", key)
	var look: Dictionary = POSTER_LOOKS.get(key, POSTER_LOOKS["poster_cat"])
	# Its back is plain paper (from the road you see the back of a lamp post's
	# poster, and the print showed through mirrored).
	(card.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_BACK
	var back := MeshInstance3D.new()
	back.name = "Back"
	back.mesh = card.mesh
	var plain := StandardMaterial3D.new()
	plain.albedo_color = (look["paper"] as Color).darkened(0.08)
	plain.roughness = 0.9
	back.material_override = plain
	back.set_meta("keep_material", true)
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.add_child(back)
	back.rotation.y = PI
	var lines := str(_Strings.SIGNS.get(key, "")).split("\n", false, 1)
	if lines.is_empty():
		return card
	var width := size.x * WORDS_WIDTH_SHARE
	var title := ink(card, lines[0], Constants.WORDS_POSTER_TITLE_M, Constants.WORDS_TITLE_FONT_PX, Vector2(0.0, _card_y(size, POSTER_TITLE_Y)), width, look["title"], true, VERTICAL_ALIGNMENT_CENTER)
	title.name = "Title"
	if lines.size() > 1:
		var body := ink(card, lines[1], Constants.WORDS_POSTER_BODY_M, Constants.WORDS_BODY_FONT_PX, Vector2(0.0, _card_y(size, POSTER_BODY_Y)), width, INK, false, VERTICAL_ALIGNMENT_TOP)
		body.name = "Body"
	if key == "poster_courtesy":
		var radius := size.y * 0.15
		var seal := _NiceSeal.node(radius, Vector3.BACK)
		card.add_child(seal)
		# The rosette in the picture's middle, its tails hanging toward the words.
		seal.position = Vector3(0.0, _card_y(size, POSTER_PICTURE_Y - 14.0), Constants.WORDS_INK_LIFT_M * 0.5)
	return card


## A sticky note on a surface (place_paper, size in meters) with its line written
## on it; the seed picks the paper, the pen and the words. Returns the card; its
## meta "words" is the Strings.SIGNS key.
static func place_note(parent: Node3D, seed_value: int, at: Vector3, normal: Vector3, size: Vector2, tilt: float = 0.0) -> MeshInstance3D:
	var key := note_key(seed_value)
	var card := place_paper(parent, note(seed_value), at, normal, size, tilt)
	card.name = "Note"
	card.set_meta("words", key)
	var pen: Color = NOTE_INKS[posmod(seed_value, NOTE_INKS.size())]
	var line := ink(card, str(_Strings.SIGNS.get(key, "")), Constants.WORDS_NOTE_LINE_M, Constants.WORDS_BODY_FONT_PX, Vector2(0.0, -size.y * 0.06), size.x * WORDS_WIDTH_SHARE, pen, false, VERTICAL_ALIGNMENT_CENTER)
	line.name = "Line"
	return card


## Printed words on a card (its local +Z is the paper's face): a line line_m tall
## (font px times pixel size), wrapped at width_m, centered across at `at` (the
## card's local x and y), a hair in front of the paper. Lit like the paper, never
## billboarded or drawn over the world, fading out past Constants.WORDS_VISIBLE_M.
static func ink(card: Node3D, text: String, line_m: float, font_px: int, at: Vector2, width_m: float, color: Color, bold: bool, align: VerticalAlignment) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = _font(bold)
	label.font_size = font_px
	label.pixel_size = line_m / float(font_px)
	label.outline_size = 0
	label.modulate = color
	label.shaded = true
	label.double_sided = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = width_m / label.pixel_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = align
	label.line_spacing = -float(font_px) * 0.12
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visibility_range_end = Constants.WORDS_VISIBLE_M
	label.visibility_range_end_margin = Constants.WORDS_FADE_M
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	card.add_child(label)
	label.position = Vector3(at.x, at.y, Constants.WORDS_INK_LIFT_M)
	return label


## The paper's local y (m) for a row of the poster texture (px from the top).
static func _card_y(size: Vector2, row_px: float) -> float:
	return size.y * (0.5 - row_px / float(POSTER_PX.y))


## The game's one font, rasterized as a multichannel distance field with mipmaps
## so the small print stays sharp up close and at a low render scale; bold is it
## emboldened, for titles.
static func _font(bold: bool) -> Font:
	if _fonts.has(bold):
		return _fonts[bold]
	var base: Font = ThemeDB.fallback_font
	var sharp: Font = base
	if base is FontFile:
		var file := (base as FontFile).duplicate() as FontFile
		file.multichannel_signed_distance_field = true
		file.generate_mipmaps = true
		sharp = file
	# Both a touch heavy: at reading distance the strokes are a few pixels wide,
	# and a thin one blends into the paper's color.
	var heavy := FontVariation.new()
	heavy.base_font = sharp
	heavy.variation_embolden = WORDS_TITLE_WEIGHT if bold else WORDS_BODY_WEIGHT
	_fonts[bold] = heavy
	return heavy


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


## Speckles inside a rect (the paper's grain).
static func _speckle_rect(image: Image, rng: RandomNumberGenerator, color: Color, count: int, rect: Rect2) -> void:
	var mist := color
	mist.a = 0.35
	for _index: int in count:
		_disc(image, Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y)), rng.randf_range(0.5, 1.1), mist)


## A filled polygon (points in px), outlined when outline has alpha.
static func _fill(image: Image, points: PackedVector2Array, color: Color, outline: Color = CLEAR, width: float = 2.0) -> void:
	var box := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		box = box.expand(point)
	var from := Vector2i(maxi(0, int(box.position.x)), maxi(0, int(box.position.y)))
	var to := Vector2i(mini(image.get_width() - 1, int(ceil(box.end.x))), mini(image.get_height() - 1, int(ceil(box.end.y))))
	for y: int in range(from.y, to.y + 1):
		for x: int in range(from.x, to.x + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
				image.set_pixel(x, y, image.get_pixel(x, y).blend(color))
	if outline.a > 0.0:
		var loop := points.duplicate()
		loop.append(points[0])
		_stroke(image, loop, width, outline)


## A thin frame round the paper, inset px.
static func _frame(image: Image, inset: int, color: Color) -> void:
	var w := image.get_width()
	var h := image.get_height()
	for rect: Rect2i in [Rect2i(inset, inset, w - inset * 2, 2), Rect2i(inset, h - inset - 2, w - inset * 2, 2), Rect2i(inset, inset, 2, h - inset * 2), Rect2i(w - inset - 2, inset, 2, h - inset * 2)]:
		image.fill_rect(rect, color)


## A strip of clear tape (34 x 16 px), made once.
static func _tape() -> Image:
	if _brushes.has("tape"):
		return _brushes["tape"]
	var tape := Image.create(34, 16, false, Image.FORMAT_RGBA8)
	tape.fill(Color(0.93, 0.95, 0.96, 0.5))
	for x: int in 34:
		tape.set_pixel(x, 0, Color(0.8, 0.82, 0.84, 0.6))
		tape.set_pixel(x, 15, Color(0.8, 0.82, 0.84, 0.6))
	_brushes["tape"] = tape
	return tape


## Gerald: a red pointy hat, a round face, a big white beard, a nose.
static func _gnome(image: Image, at: Vector2) -> void:
	var skin := Color(0.96, 0.8, 0.68)
	_fill(image, PackedVector2Array([at + Vector2(-30.0, 46.0), at + Vector2(30.0, 46.0), at + Vector2(22.0, 76.0), at + Vector2(-22.0, 76.0)]), Color(0.25, 0.42, 0.72), INK)
	_fill(image, PackedVector2Array([at + Vector2(-34.0, -6.0), at + Vector2(4.0, -72.0), at + Vector2(34.0, -6.0)]), Color(0.82, 0.16, 0.14), INK)
	_disc(image, at + Vector2(0.0, 6.0), 22.0, INK)
	_disc(image, at + Vector2(0.0, 6.0), 20.0, skin)
	_fill(image, PackedVector2Array([at + Vector2(-30.0, 4.0), at + Vector2(-16.0, 14.0), at + Vector2(16.0, 14.0), at + Vector2(30.0, 4.0), at + Vector2(22.0, 46.0), at + Vector2(0.0, 64.0), at + Vector2(-22.0, 46.0)]), Color(0.98, 0.98, 0.96), INK)
	_disc(image, at + Vector2(0.0, 12.0), 8.0, Color(0.92, 0.55, 0.5))
	_disc(image, at + Vector2(-9.0, 2.0), 2.4, INK)
	_disc(image, at + Vector2(9.0, 2.0), 2.4, INK)
	_stroke(image, PackedVector2Array([at + Vector2(-36.0, -6.0), at + Vector2(36.0, -6.0)]), 3.0, INK)


## A leaf rake, head down, with a starburst behind it.
static func _rake(image: Image, at: Vector2) -> void:
	var wood := Color(0.62, 0.42, 0.24)
	var metal := Color(0.45, 0.47, 0.5)
	_stroke(image, PackedVector2Array([at + Vector2(-4.0, -70.0), at + Vector2(0.0, 40.0)]), 6.0, INK)
	_stroke(image, PackedVector2Array([at + Vector2(-4.0, -70.0), at + Vector2(0.0, 40.0)]), 4.0, wood)
	var tines := PackedVector2Array()
	for index: int in 11:
		var t := float(index) / 10.0
		var root := at + Vector2(0.0, 40.0)
		var tip := at + Vector2(lerpf(-48.0, 48.0, t), 76.0 - absf(t - 0.5) * 10.0)
		_stroke(image, PackedVector2Array([root, tip]), 1.6, metal.darkened(0.3))
		tines.append(tip)
	_stroke(image, tines, 2.2, metal)


## A leaf pile in autumn colors with an arrow pointing at it.
static func _leaf_pile(image: Image, rng: RandomNumberGenerator, at: Vector2) -> void:
	var colors: Array[Color] = [Color(0.9, 0.45, 0.12), Color(0.8, 0.2, 0.12), Color(0.95, 0.75, 0.2), Color(0.6, 0.35, 0.15)]
	for index: int in 90:
		var t := rng.randf()
		var x := lerpf(-70.0, 70.0, t)
		var top := 70.0 - 48.0 * sin(t * PI)
		var spot := at + Vector2(x, rng.randf_range(top, 72.0))
		_disc(image, spot, rng.randf_range(4.0, 7.0), colors[index % colors.size()].darkened(0.35))
		_disc(image, spot + Vector2(-0.5, -0.5), rng.randf_range(3.0, 5.0), colors[index % colors.size()])
	_stroke(image, PackedVector2Array([at + Vector2(-80.0, -58.0), at + Vector2(-10.0, -18.0)]), 4.0, INK)
	_stroke(image, PackedVector2Array([at + Vector2(-34.0, -20.0), at + Vector2(-10.0, -18.0), at + Vector2(-22.0, -40.0)]), 4.0, INK)


## A gold trophy on a striped lawn, with sparkles.
static func _trophy(image: Image, at: Vector2) -> void:
	for stripe: int in 6:
		var color := Color(0.3, 0.62, 0.28) if stripe % 2 == 0 else Color(0.38, 0.72, 0.34)
		image.fill_rect(Rect2i(int(at.x - 96.0 + float(stripe) * 32.0), int(at.y + 48.0), 32, 30), color)
	var gold := Color(0.96, 0.76, 0.2)
	for side: float in [-1.0, 1.0]:
		var start := -PI * 0.5 + (PI if side < 0.0 else 0.0)
		_stroke(image, _arc(at + Vector2(side * 30.0, -38.0), 14.0, start, start + PI, 10), 3.0, INK)
	_fill(image, PackedVector2Array([at + Vector2(-34.0, -60.0), at + Vector2(34.0, -60.0), at + Vector2(24.0, -10.0), at + Vector2(-24.0, -10.0)]), gold, INK)
	_fill(image, PackedVector2Array([at + Vector2(-6.0, -10.0), at + Vector2(6.0, -10.0), at + Vector2(6.0, 20.0), at + Vector2(-6.0, 20.0)]), gold, INK)
	_fill(image, PackedVector2Array([at + Vector2(-26.0, 20.0), at + Vector2(26.0, 20.0), at + Vector2(26.0, 38.0), at + Vector2(-26.0, 38.0)]), gold.darkened(0.2), INK)
	_star(image, at + Vector2(-56.0, -56.0), 10.0, Color.WHITE, gold)
	_star(image, at + Vector2(58.0, -30.0), 8.0, Color.WHITE, gold)


## A cat: round head, triangle ears, whiskers.
static func _cat(image: Image, at: Vector2) -> void:
	var center := at + Vector2(0.0, 8.0)
	_stroke(image, _circle(center, 44.0, 28), 3.0, INK)
	_stroke(image, PackedVector2Array([center + Vector2(-38.0, -20.0), center + Vector2(-30.0, -62.0), center + Vector2(-8.0, -42.0)]), 3.0, INK)
	_stroke(image, PackedVector2Array([center + Vector2(38.0, -20.0), center + Vector2(30.0, -62.0), center + Vector2(8.0, -42.0)]), 3.0, INK)
	_disc(image, center + Vector2(-15.0, -6.0), 4.2, INK)
	_disc(image, center + Vector2(15.0, -6.0), 4.2, INK)
	for side: float in [-1.0, 1.0]:
		_stroke(image, PackedVector2Array([center + Vector2(side * 14.0, 10.0), center + Vector2(side * 52.0, 4.0)]), 1.4, INK)
		_stroke(image, PackedVector2Array([center + Vector2(side * 14.0, 15.0), center + Vector2(side * 52.0, 20.0)]), 1.4, INK)
	_stroke(image, _arc(center + Vector2(0.0, 14.0), 10.0, 0.2, PI - 0.2, 10), 1.8, INK)


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
