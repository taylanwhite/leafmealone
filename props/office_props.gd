class_name OfficeProps
extends RefCounted

## Authority: local, cosmetic. The furniture of Satellite Annex B (levels/annex/
## annex_b.gd builds the room from these; docs/GAME.md "Satellite Annex B").
## Every stateful prop is a Node3D with set_state(state, at, args := {}): it
## starts showing that state at server time `at` (fast-forwarding when the call
## comes late, skipping a sound that is more than Constants.BEAT_SKIP late), and plays
## its own sound on the frame its motion lands, so the KA-CHUNK is the stamp
## hitting the pad. Nothing here decides anything: net/annex/annex.gd (R2
## chunk 6) is the host's, and it calls these on every peer.
##
## Builders (each returns the prop, already named):
##   service_window(id, look)  a window in the counter wall: counter, glass, the
##       serving lamp, venetian blinds, the clock sign, a desk bell, the window
##       stamp on its pad, a filing cabinet, the clerk's stool, footprints, and
##       its pictogram plaque (look {icon, color}); markers Counter, QueueSpots/
##       Spot0..2, StampPad, Bell, ClerkSeat, Cabinet, BreakSpot0..2. States
##       lamp_on, lamp_off, blind_up, blind_down, clock_sign, clock_sign_off,
##       stamp_lifted, stamp_down (args.volley: that many slams), bell.
##       Window D also has a cobweb and the cardboard BACK AT clock.
##   floor_line(points, color) pulse; big_stamp() (on the desk annex_b.gd builds)
##   (set_held(node|null), on_pad, held, slam); appliance("copier") idle, copying,
##   jam; appliance("cooler") glug; appliance("coffee") brew; cosign_sheet() signing; outgoing_tray()
##   receive (args.from); turnstile() open (args.seconds), bounce, closed;
##   light_row(width) on, off, flicker; wall_clock() set_speed(x);
##   now_serving() show_number(n); slide_door(name, width, pair) open, closed;
##   staff_door(width, staff) (swings by itself when a staff body walks through).
## Models are built in code (props/mesh_kit.gd, one draw call per moving part).
## Every word on them comes from ui/strings.gd ANNEX_SIGNS.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _Strings = preload("res://ui/strings.gd")
const _NiceSeal = preload("res://props/nice_seal.gd")

const WOOD := Color(0.62, 0.47, 0.32)
const LAMINATE := Color(0.86, 0.83, 0.76)
const TRIM := Color(0.36, 0.33, 0.42)
const STEEL := Color(0.62, 0.65, 0.7)
const DARK := Color(0.16, 0.16, 0.19)
const BEIGE := Color(0.83, 0.79, 0.68)
const CARDBOARD := Color(0.72, 0.56, 0.36)
const PAPER := Color(0.97, 0.96, 0.92)
const INK := Color(0.42, 0.22, 0.62)
const VELVET := Color(0.62, 0.12, 0.2)
const LAMP_WARM := Color(1.0, 0.82, 0.42)
const LAMP_OFF := Color(0.28, 0.27, 0.26)
const GLASS_TINT := Color(0.75, 0.88, 0.92, 0.07)
const BLIND := Color(0.9, 0.88, 0.8)

## The window's frame, in its own space: the glass is the plane z = 0, the lobby
## is +Z, the counter top is at COUNTER_Y, the hatch is the gap under the glass.
const COUNTER_Y: float = 0.98
const GLASS_WIDTH: float = 1.5
const GLASS_BOTTOM: float = 1.2
const GLASS_TOP: float = 2.25
const HATCH_HALF: float = 0.32
const STAMP_SPOT := Vector3(0.24, COUNTER_Y, -0.16)
## A window's footprints: the first pair this far out from the glass (m), the
## rest FOOT_STEP apart, each print this big.
const FOOT_Z: float = 0.85
const FOOT_STEP: float = 0.75
const FOOT_SIZE := Vector3(0.11, 0.006, 0.26)


# ---------------------------------------------------------------- time and sound

## Server time where there is a session (every peer agrees on it), else this
## machine's clock (the studio, the headless checks).
static func now() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var net := tree.root.get_node_or_null("Net") if tree != null else null
	if net != null and net.has_method("server_time") and net.has_method("current_state") and int(net.call("current_state")) != 0:
		return float(net.call("server_time"))
	return float(Time.get_ticks_msec()) / 1000.0


## Whether player is this peer's own and its view is first person right now
## (player/camera_rig.gd): what a held clipboard or slip attaches to.
static func sees_first_person(player: Node) -> bool:
	if player == null or not player.is_inside_tree() or not player.is_multiplayer_authority():
		return false
	var rig := player.get_node_or_null("CameraRig")
	return rig == null or bool(rig.get("first_person"))


## A sound for server time at still plays when this peer is at most
## Constants.BEAT_SKIP late (the beat clock's rule, net/run_events/beat.gd).
static func plays_sound(at: float) -> bool:
	return now() - at <= Constants.BEAT_SKIP


## One positional one-shot from the sfx group (audio/sfx.gd), if there is one.
static func _play_sfx(node: Node, id: String, at: Vector3) -> void:
	if node == null or not node.is_inside_tree():
		return
	var sfx := node.get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", id, at)


## An emissive material (lamps, the copier's light, the floor lines' glow).
static func glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


## The service windows' and doors' see-through glass.
static func glass_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = GLASS_TINT
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Clear, not milky (R2b): the sky's reflection washed the clerks behind it
	# out to a haze, so it keeps only a faint sheen.
	material.metallic = 0.0
	material.roughness = 0.12
	material.metallic_specular = 0.3
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## A mesh of kit under parent. bake marks it static: levels/annex/annex_b.gd
## merges every baked look into one mesh (one draw call for the whole room).
static func _view(parent: Node3D, kit: RefCounted, name: String, options: Dictionary = {}, bake: bool = false) -> MeshInstance3D:
	var mesh: ArrayMesh = kit.call("commit")
	var view := _Stylized.instance(mesh, options)
	view.name = name
	if bake:
		view.set_meta("bake", true)
	parent.add_child(view)
	return view


static func _marker(parent: Node3D, name: String, at: Vector3, yaw: float = 0.0) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = name
	parent.add_child(marker)
	marker.position = at
	marker.rotation.y = yaw
	return marker


static func _solid(parent: Node3D, name: String, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	parent.add_child(body)
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body


static func _label(parent: Node3D, text: String, at: Vector3, font_size: int, color: Color, pixel: float = 0.004) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = color
	label.position = at
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(label)
	return label


## A printed card's face (a sign's words in ink on paper, inside an ink
## border) as a texture, drawn once by a SubViewport under owner: a card and its
## words in one draw call, where a mesh and a Label3D take two.
static func card_texture(owner: Node, text: String, pixels: Vector2i, ink: Color, paper: Color) -> Texture2D:
	var viewport := SubViewport.new()
	viewport.name = "CardPrint"
	viewport.size = pixels
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	owner.add_child(viewport)
	var face := CardPrint.new()
	face.text = text
	face.ink = ink
	face.paper = paper
	face.size = Vector2(pixels)
	viewport.add_child(face)
	return viewport.get_texture()


class CardPrint extends Control:
	var text: String = ""
	var ink := Color.BLACK
	var paper := Color.WHITE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), ink)
		var border := size.y * 0.05
		draw_rect(Rect2(Vector2(border, border), size - Vector2(border, border) * 2.0), paper)
		var lines := text.split("\n")
		var font := ThemeDB.fallback_font
		var font_size := int(minf(size.y * 0.7 / float(maxi(lines.size(), 1)), size.x * 0.13))
		var line_height := font.get_height(font_size)
		var top := (size.y - line_height * float(lines.size())) * 0.5 + font.get_ascent(font_size)
		for index: int in lines.size():
			draw_string(font, Vector2(border, top + line_height * float(index)), lines[index], HORIZONTAL_ALIGNMENT_CENTER, size.x - border * 2.0, font_size, ink)


## A stand-in pictogram: the window's icon from ui/icons.gd (the same picture
## its box on Form 27-B shows), or a plain colored disc when there is no icon.
static func pictogram_texture(icon_id: String) -> Texture2D:
	var path := "res://assets/icons/%s.png" % icon_id
	if icon_id != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## The color a pictogram always wears in the Annex (Constants.ANNEX_ICON_COLORS).
static func icon_color(icon_id: String) -> Color:
	return Constants.ANNEX_ICON_COLORS.get(icon_id, Color(0.6, 0.6, 0.65))


static var _badges: Dictionary = {}


## The room's one sign for a window (R2b): a board in the color, a white disc,
## the pictogram on it. The plaque, the form's box and the floor sticker all draw
## this same picture, so a box on the clipboard matches its window from the door.
## Drawn once per pair on the CPU (no SubViewport: it is there the frame it's asked for).
static func badge_texture(icon_id: String, color: Color) -> Texture2D:
	var key := "%s|%s" % [icon_id, color.to_html()]
	if _badges.has(key):
		return _badges[key]
	var px := Constants.ANNEX_BADGE_PX
	var image := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var half := float(px) * 0.5
	var corner := float(px) * 0.18
	var rim := float(px) * 0.045
	var disc := float(px) * 0.36
	var rim_color := color.darkened(0.4)
	for y: int in px:
		for x: int in px:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			# Distance outside the rounded square (negative inside).
			var q := (p - Vector2(half, half)).abs() - Vector2(half - corner, half - corner)
			var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - corner
			if outside > 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var shade := rim_color if outside > -rim else color
			var d := p.distance_to(Vector2(half, half))
			if d < disc:
				shade = Color(0.99, 0.98, 0.95)
			elif d < disc + rim * 0.6:
				shade = color.darkened(0.25)
			image.set_pixel(x, y, shade)
	var icon := pictogram_texture(icon_id)
	if icon != null:
		var art := icon.get_image()
		if art != null:
			art = art.duplicate() as Image
			if art.is_compressed():
				art.decompress()
			art.convert(Image.FORMAT_RGBA8)
			var size := int(disc * 1.9)
			art.resize(size, size, Image.INTERPOLATE_LANCZOS)
			image.blend_rect(art, Rect2i(0, 0, size, size), Vector2i(int(half) - size / 2, int(half) - size / 2))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_badges[key] = texture
	return texture


static func ease_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)


static func ease_in(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t


## The base of every stateful prop: the state, when it began, and the sounds
## waiting for their moment.
class Prop extends Node3D:
	var state: StringName = &""
	var state_at: float = -1000.0
	var state_args: Dictionary = {}
	## [{at, id, where}]: sounds that play when server time reaches at.
	var _cues: Array[Dictionary] = []
	var _busy_until: float = -1000.0

	## Show `next` from server time `at` on. Calls that change nothing are ignored.
	func set_state(next: StringName, at: float, args: Dictionary = {}) -> void:
		state = next
		state_at = at
		state_args = args
		_begin(next, at, args)
		set_process(true)
		_animate(OfficeProps.now())

	func _begin(_next: StringName, _at: float, _args: Dictionary) -> void:
		pass

	## Pose for server time t; returns true while still moving.
	func _animate(_t: float) -> bool:
		return false

	## A sound at server time at, from where (this prop's origin when INF).
	func cue(id: String, at: float, where: Vector3 = Vector3.INF) -> void:
		_cues.append({"at": at, "id": id, "where": where})
		_busy_until = maxf(_busy_until, at)

	func _ready() -> void:
		# Only a prop with something to show keeps ticking (set_state wakes it).
		set_process(state != &"" or not _cues.is_empty())

	func _process(_delta: float) -> void:
		var t := OfficeProps.now()
		var moving := _animate(t)
		var index := 0
		while index < _cues.size():
			var entry: Dictionary = _cues[index]
			if t >= float(entry["at"]):
				_cues.remove_at(index)
				if OfficeProps.plays_sound(float(entry["at"])):
					var where: Vector3 = entry["where"]
					OfficeProps._play_sfx(self, str(entry["id"]), global_position if not where.is_finite() else where)
				continue
			index += 1
		if not moving and _cues.is_empty() and t > _busy_until:
			set_process(false)


## Venetian blinds: slats hanging from a head rail at the top; down covers the
## glass, up stacks them under the rail (each slat squeezes toward it).
class Blinds extends Node3D:
	var drop: float = 1.0
	var _slats: Node3D
	var _width: float
	var _height: float

	func build(width: float, height: float) -> void:
		_width = width
		_height = height
		var rail := _MeshKit.new()
		rail.box(Vector3(0.0, 0.02, 0.0), Vector3(width + 0.06, 0.05, 0.05), TRIM)
		OfficeProps._view(self, rail, "Rail", {}, true)
		_slats = Node3D.new()
		_slats.name = "Slats"
		add_child(_slats)
		var kit := _MeshKit.new()
		var count := int(height / 0.075)
		for index: int in count:
			var y := -(float(index) + 0.5) * height / float(count)
			kit.box(Vector3(0.0, y, 0.0), Vector3(width, 0.012, 0.045), BLIND, Basis(Vector3.RIGHT, 0.35))
		kit.box(Vector3(0.0, -height - 0.01, 0.0), Vector3(width + 0.02, 0.025, 0.05), TRIM)
		OfficeProps._view(_slats, kit, "Slat")
		set_drop(1.0)

	## 1 covers the glass, 0 is drawn up.
	func set_drop(amount: float) -> void:
		drop = clampf(amount, 0.0, 1.0)
		_slats.scale = Vector3(1.0, maxf(0.04, drop), 1.0)
		# Drawn up tight under the rail they're out of sight (and out of the draw calls).
		_slats.visible = drop > 0.03


## A service window: everything a caught player needs to read with no words.
class ServiceWindow extends Prop:
	var window_id: String = "A"
	var look: Dictionary = {}
	var lamp_on: bool = false
	var blind_down: bool = false
	var _lamp: MeshInstance3D
	var _lamp_on_mat: StandardMaterial3D
	var _blinds: Blinds
	## Each part keeps its own clock, so one state never freezes another part
	## mid-move: the blinds, the clock sign, the stamp.
	var _blind_from: float = 0.0
	var _blind_to: float = 0.0
	var _blind_at: float = -1000.0
	var _blind_set: bool = false
	var _stamp_state: StringName = &""
	var _stamp_at: float = -1000.0
	var _stamp_volley: int = 1
	var _stamp_gap: float = Constants.CLERK_VOLLEY_GAP
	var _stamp_lift: float = 0.24
	var _stamp_first: float = Constants.ANNEX_STAMP_HIT
	var _stamp_from: float = 0.0
	var _stamp_rise_now: float = 0.0
	var _flutter_from: float = -1000.0
	var _scraps: Array[MeshInstance3D] = []
	var _scrap_material: StandardMaterial3D
	const FLUTTER_COUNT: int = 5
	var _stamp: Node3D
	var _plaque: Sprite3D
	var _plaque_board: MeshInstance3D
	var _clock_sign: Node3D
	var _sign_up: bool = false
	var _sign_from: float = 0.0
	var _ink: MeshInstance3D
	## The stamp out of its window in a hand (R2c annex, the self-stamp): a
	## Callable giving the world point it's carried to (where it slams), when it
	## started, whether it just shoots out (others' view), and drawn over the
	## first-person form; then the way back to the pad.
	var _borrow_to: Callable = Callable()
	var _borrow_at: float = -1000.0
	var _borrow_quick: bool = false
	var _return_at: float = -1000.0
	var _return_from := Vector3.ZERO
	var _stamp_saved_material: Material = null
	var _stamp_top_material: StandardMaterial3D = null

	func build(id: String, window_look: Dictionary) -> void:
		window_id = id
		name = id
		var color: Color = window_look.get("color", Color(0.6, 0.6, 0.65))
		var kit := _MeshKit.new()
		# The counter runs through under the glass: the lobby's ledge in front, the
		# clerk's sill behind, the hatch the gap between them and the glass.
		kit.box(Vector3(0.0, COUNTER_Y - 0.025, 0.12), Vector3(GLASS_WIDTH + 0.5, 0.05, 0.6), LAMINATE)
		kit.box(Vector3(0.0, COUNTER_Y - 0.055, 0.405), Vector3(GLASS_WIDTH + 0.52, 0.03, 0.03), TRIM)
		# The glass's frame and the hatch's chrome lip.
		for side: float in [-1.0, 1.0]:
			kit.box(Vector3(side * (GLASS_WIDTH * 0.5 + 0.04), (GLASS_BOTTOM + GLASS_TOP) * 0.5 + 0.0, 0.0), Vector3(0.08, GLASS_TOP - COUNTER_Y + 0.02, 0.09), TRIM)
		kit.box(Vector3(0.0, GLASS_TOP + 0.04, 0.0), Vector3(GLASS_WIDTH + 0.16, 0.08, 0.09), TRIM)
		kit.box(Vector3(0.0, GLASS_BOTTOM - 0.015, 0.0), Vector3(GLASS_WIDTH, 0.03, 0.06), STEEL)
		for side: float in [-1.0, 1.0]:
			kit.box(Vector3(side * (HATCH_HALF + 0.5) * 0.5 + side * 0.17, (COUNTER_Y + GLASS_BOTTOM) * 0.5, 0.0), Vector3(GLASS_WIDTH * 0.5 - HATCH_HALF, GLASS_BOTTOM - COUNTER_Y, 0.02), STEEL.lightened(0.2))
		# The plaque's frame (the run's badge, OfficeProps.badge_texture, hangs in it:
		# the same picture as the box on the form), and the lamp's housing beside it.
		# Window D, which has no pictogram, keeps a plain board.
		if id == "D":
			kit.box(Vector3(0.0, 2.68, 0.02), Vector3(0.62, 0.62, 0.04), color)
		kit.box(Vector3(0.0, 2.68, 0.0), Vector3(0.7, 0.7, 0.02), TRIM)
		kit.box(Vector3(0.58, 2.8, 0.01), Vector3(0.36, 0.36, 0.03), DARK)
		# The lamp's dead bulb, baked: the lit one covers it while the window serves
		# (so a window that isn't serving costs no draw call for its lamp).
		kit.blob(Vector3(0.58, 2.8, 0.05), Vector3(0.15, 0.1, 0.15), LAMP_OFF, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
		# The desk bell on the ledge: a chrome dome on a black base.
		kit.cone(Vector3(-0.58, COUNTER_Y, 0.24), 0.07, 0.03, DARK, 10)
		kit.blob(Vector3(-0.58, COUNTER_Y + 0.045, 0.24), Vector3(0.055, 0.04, 0.055), STEEL.lightened(0.25), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
		kit.box(Vector3(-0.58, COUNTER_Y + 0.095, 0.24), Vector3(0.012, 0.03, 0.012), STEEL)
		# The clerk's side: a desk, a stool, a filing cabinet, a typewriter, a mug.
		kit.box(Vector3(0.0, 0.74, -0.62), Vector3(1.5, 0.05, 0.6), WOOD)
		for x: float in [-0.68, 0.68]:
			kit.box(Vector3(x, 0.36, -0.62), Vector3(0.05, 0.72, 0.55), WOOD.darkened(0.2))
		kit.box(Vector3(-0.35, 0.82, -0.66), Vector3(0.36, 0.12, 0.28), DARK)
		kit.box(Vector3(-0.35, 0.9, -0.72), Vector3(0.32, 0.06, 0.06), DARK.lightened(0.1))
		# The mug and the stool stay neutral: only the badge, the line and the
		# footprints wear the window's color (R2b), so nothing else hints at it.
		kit.cone(Vector3(0.45, 0.765, -0.55), 0.04, 0.09, PAPER, 8)
		# A tall drafting stool with a foot ring (R2c: on a low one he sat hidden
		# below the hatch, and a booth read empty from the line).
		var stool_top := 0.82 - Constants.CLERK_STOOL_DROP - 0.03
		kit.cone(Vector3(0.0, 0.0, -1.05), 0.2, 0.04, DARK, 8)
		kit.box(Vector3(0.0, stool_top * 0.5, -1.05), Vector3(0.04, stool_top - 0.02, 0.04), STEEL)
		var ring := PackedVector3Array()
		for step: int in 13:
			var angle := TAU * float(step) / 12.0
			ring.append(Vector3(cos(angle) * 0.17, 0.3, -1.05 + sin(angle) * 0.17))
		kit.tube(ring, PackedFloat32Array([0.012]), STEEL, 5, {"jitter": 0.0})
		kit.cone(Vector3(0.0, stool_top - 0.05, -1.05), 0.2, 0.05, DARK.lightened(0.15), 10)
		# The filing cabinet stands back against the wall, out of the corridor the
		# clerks walk behind the stools (R2c annex).
		kit.box(Vector3(0.62, 0.62, -1.875), Vector3(0.5, 1.24, 0.45), STEEL.darkened(0.15))
		for drawer: int in 3:
			kit.box(Vector3(0.62, 0.25 + float(drawer) * 0.38, -1.645), Vector3(0.42, 0.3, 0.02), STEEL)
			kit.box(Vector3(0.62, 0.33 + float(drawer) * 0.38, -1.63), Vector3(0.12, 0.025, 0.02), DARK)
		# The stamp's ink pad on the sill, right behind the hatch.
		kit.box(STAMP_SPOT + Vector3(0.0, 0.012, 0.0), Vector3(0.16, 0.024, 0.11), DARK)
		kit.box(STAMP_SPOT + Vector3(0.0, 0.026, 0.0), Vector3(0.13, 0.005, 0.08), INK)
		# Footprints: where to stand, and the line behind it. A-C's are painted by
		# their floor line (FloorLine, in the run's color); D's stay grey here.
		if id == "D":
			for spot: int in 4:
				for side: float in [-1.0, 1.0]:
					kit.box(Vector3(side * 0.12, 0.013, FOOT_Z + float(spot) * FOOT_STEP), FOOT_SIZE, color.darkened(0.05), Basis(Vector3.UP, side * -0.12))
		OfficeProps._view(self, kit, "Look", {}, true)
		var glass := MeshInstance3D.new()
		glass.name = "Glass"
		var pane := QuadMesh.new()
		pane.size = Vector2(GLASS_WIDTH, GLASS_TOP - GLASS_BOTTOM)
		glass.mesh = pane
		glass.material_override = OfficeProps.glass_material()
		glass.set_meta("keep_material", true)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glass.position = Vector3(0.0, (GLASS_BOTTOM + GLASS_TOP) * 0.5, 0.0)
		glass.set_meta("bake_glass", true)
		add_child(glass)
		# The serving lamp: lit warm while the window serves.
		_lamp_on_mat = OfficeProps.glow_material(LAMP_WARM, Constants.ANNEX_WINDOW_LAMP_ENERGY)
		var bulb := _MeshKit.new()
		bulb.blob(Vector3(0.58, 2.8, 0.05), Vector3(0.158, 0.106, 0.158), Color.WHITE, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
		_lamp = MeshInstance3D.new()
		_lamp.name = "Lamp"
		_lamp.mesh = bulb.commit()
		_lamp.material_override = _lamp_on_mat
		_lamp.set_meta("keep_material", true)
		_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_lamp)
		# Blinds behind the glass, up by default.
		_blinds = Blinds.new()
		_blinds.name = "Blind"
		add_child(_blinds)
		_blinds.position = Vector3(0.0, GLASS_TOP - 0.02, -0.06)
		_blinds.build(GLASS_WIDTH - 0.04, GLASS_TOP - GLASS_BOTTOM + 0.18)
		_blinds.set_drop(0.0)
		# The window's stamp: a wooden knob on a stem on a rubber block.
		_stamp = Node3D.new()
		_stamp.name = "Stamp"
		add_child(_stamp)
		_stamp.position = STAMP_SPOT + Vector3(0.0, 0.026, 0.0)
		var stamp := _MeshKit.new()
		stamp.box(Vector3(0.0, 0.02, 0.0), Vector3(0.1, 0.04, 0.07), DARK)
		stamp.box(Vector3(0.0, 0.003, 0.0), Vector3(0.09, 0.006, 0.06), INK)
		stamp.tube(PackedVector3Array([Vector3(0.0, 0.04, 0.0), Vector3(0.0, 0.11, 0.0)]), PackedFloat32Array([0.012, 0.012]), STEEL, 6, {"jitter": 0.0})
		stamp.blob(Vector3(0.0, 0.135, 0.0), Vector3(0.04, 0.035, 0.04), WOOD, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
		OfficeProps._view(_stamp, stamp, "Mesh")
		# The pictogram: the run's icon on the colored board.
		_plaque = Sprite3D.new()
		_plaque.name = "Plaque"
		_plaque.pixel_size = 0.5 / 256.0
		_plaque.position = Vector3(0.0, 2.68, 0.03)
		_plaque.shaded = false
		_plaque.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_plaque.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_plaque.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_plaque)
		# The clock sign: a folded card on the ledge, flat until shown.
		_clock_sign = Node3D.new()
		_clock_sign.name = "ClockSign"
		add_child(_clock_sign)
		_clock_sign.position = Vector3(0.0, COUNTER_Y, 0.2)
		# One draw call: the card and its words are one printed texture (a break
		# on every window stays inside the set's draw-call budget).
		var card := MeshInstance3D.new()
		card.name = "Card"
		var face := QuadMesh.new()
		face.size = Vector2(0.44, 0.24)
		card.mesh = face
		card.position = Vector3(0.0, 0.12, 0.0)
		var printed := StandardMaterial3D.new()
		printed.albedo_texture = OfficeProps.card_texture(self, _Strings.ANNEX_SIGNS["back_soon"], Vector2i(512, 280), INK, PAPER)
		printed.roughness = 0.85
		card.material_override = printed
		card.set_meta("keep_material", true)
		_clock_sign.add_child(card)
		_clock_sign.visible = false
		var counter := OfficeProps._marker(self, "Counter", Vector3(0.0, 0.0, 0.85))
		counter.rotation.y = 0.0
		var queue := Node3D.new()
		queue.name = "QueueSpots"
		add_child(queue)
		for spot: int in 3:
			OfficeProps._marker(queue, "Spot%d" % spot, Vector3(0.0, 0.0, 1.6 + float(spot) * 0.75))
		OfficeProps._marker(self, "StampPad", STAMP_SPOT + Vector3(0.0, 0.05, 0.0))
		OfficeProps._marker(self, "Bell", Vector3(-0.58, COUNTER_Y + 0.06, 0.24))
		OfficeProps._marker(self, "ClerkSeat", Vector3(0.0, 0.0, -1.05), PI)
		OfficeProps._marker(self, "Cabinet", Vector3(0.62, 0.0, -1.5), PI)
		for spot: int in 3:
			OfficeProps._marker(self, "BreakSpot%d" % spot, Vector3(0.0, 0.0, -1.05))
		# The lobby can't climb the counter or walk through the glass.
		OfficeProps._solid(self, "CounterBody", Vector3(GLASS_WIDTH + 0.5, COUNTER_Y, 0.6), Vector3(0.0, COUNTER_Y * 0.5, 0.12))
		OfficeProps._solid(self, "GlassBody", Vector3(GLASS_WIDTH + 0.2, GLASS_TOP - COUNTER_Y + 0.1, 0.1), Vector3(0.0, (COUNTER_Y + GLASS_TOP) * 0.5 + 0.05, -0.02))
		if id == "D":
			_window_d(kit)
		apply_look(window_look)
		_set_lamp(false)

	## Window D: a cobweb in the corner of the glass and the cardboard BACK AT clock
	## propped against it, both gone while its blinds are up.
	func _window_d(_kit: RefCounted) -> void:
		# The cobweb in the glass's top corner, and the cardboard clock propped on
		# the sill behind the glass, drawn in marker: BACK AT a quarter past never.
		var web := _MeshKit.new()
		var corner := Vector3(GLASS_WIDTH * 0.5 - 0.02, GLASS_TOP - 0.02, 0.012)
		for strand: int in 5:
			var angle := PI + PI * 0.5 * float(strand) / 4.0
			var tip := corner + Vector3(cos(angle), sin(angle), 0.0) * 0.32
			web.tube(PackedVector3Array([corner, tip]), PackedFloat32Array([0.002, 0.002]), PAPER, 3, {"jitter": 0.0})
		for ring: int in 3:
			var radius := 0.09 + float(ring) * 0.08
			var points := PackedVector3Array()
			for step: int in 5:
				var angle := PI + PI * 0.5 * float(step) / 4.0
				points.append(corner + Vector3(cos(angle), sin(angle), 0.0) * radius)
			web.tube(points, PackedFloat32Array([0.0018]), PAPER, 3, {"jitter": 0.0})
		var cardboard := Node3D.new()
		cardboard.name = "BackAt"
		add_child(cardboard)
		cardboard.position = Vector3(-0.25, COUNTER_Y, -0.1)
		cardboard.rotation.x = -0.12
		var clock := _MeshKit.new()
		clock.box(Vector3(0.0, 0.29, 0.0), Vector3(0.5, 0.58, 0.012), CARDBOARD)
		clock.tube(PackedVector3Array([Vector3(0.0, 0.22, 0.006), Vector3(0.0, 0.22, 0.01)]), PackedFloat32Array([0.17, 0.17]), PAPER, 16, {"jitter": 0.0})
		clock.box(Vector3(0.0, 0.27, 0.014), Vector3(0.016, 0.11, 0.004), DARK)
		clock.box(Vector3(0.04, 0.22, 0.014), Vector3(0.09, 0.016, 0.004), DARK)
		OfficeProps._view(cardboard, clock, "Clock")
		OfficeProps._label(cardboard, _Strings.ANNEX_SIGNS["back_at"], Vector3(0.0, 0.5, 0.009), 44, DARK, 0.0022)
		var webs := OfficeProps._view(self, web, "Cobweb", {"roughness": 0.6}, true)
		webs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	## The run's pictogram and color: {icon, color}. The plaque is the room's
	## badge for it (OfficeProps.badge_texture), the picture the form's box shows.
	func apply_look(window_look: Dictionary) -> void:
		look = window_look
		var icon := str(window_look.get("icon", ""))
		var texture: Texture2D = null
		if OfficeProps.pictogram_texture(icon) != null:
			texture = OfficeProps.badge_texture(icon, window_look.get("color", OfficeProps.icon_color(icon)))
		_plaque.texture = texture
		_plaque.visible = texture != null
		if texture != null:
			_plaque.pixel_size = 0.66 / float(maxi(texture.get_width(), 1))

	func _set_lamp(on: bool) -> void:
		lamp_on = on
		_lamp.visible = on

	## Someone takes the stamp out of the hatch (R2c annex: it inked your form from
	## 1.5 m away with no hand on it). to() is where it's carried, in the world.
	## quick: it goes straight there (someone else's self-stamp, seen as it lands);
	## on_top: drawn over your own first-person clipboard.
	func borrow(to: Callable, at: float, quick: bool, on_top: bool) -> void:
		_borrow_to = to
		_borrow_at = at
		_borrow_quick = quick
		_return_at = -1000.0
		_stamp_on_top(on_top)
		set_process(true)

	## Taken back to its pad from wherever it is, from server time at.
	func give_back(at: float) -> void:
		if not _borrow_to.is_valid():
			return
		_borrow_to = Callable()
		_return_at = at
		_return_from = _stamp.global_position
		set_process(true)

	## Out of its window, in a hand or on its way back.
	func borrowed() -> bool:
		return _borrow_to.is_valid() or OfficeProps.now() - _return_at < Constants.ANNEX_BORROW_RETURN

	## In someone's hand right now (not on its way home).
	func in_hand() -> bool:
		return _borrow_to.is_valid()

	## Where the stamp's knob is (a hand holding it goes here).
	func stamp_knob() -> Vector3:
		return _stamp.global_position + _stamp.global_basis.y * 0.135

	func _stamp_on_top(on: bool) -> void:
		var view := _stamp.get_node_or_null("Mesh") as MeshInstance3D
		if view == null:
			return
		if on:
			if _stamp_top_material == null:
				_stamp_top_material = StandardMaterial3D.new()
				_stamp_top_material.vertex_color_use_as_albedo = true
				_stamp_top_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				_stamp_top_material.no_depth_test = true
				_stamp_top_material.render_priority = 3
				_stamp_saved_material = view.material_override
			view.material_override = _stamp_top_material
		elif _stamp_top_material != null:
			view.material_override = _stamp_saved_material

	## Where a borrowed stamp is now (world), before the slam's own lift.
	func _borrowed_at(t: float) -> Vector3:
		var pad := global_transform * (STAMP_SPOT + Vector3(0.0, 0.026, 0.0))
		var carry: Vector3 = _borrow_to.call()
		if not carry.is_finite():
			return pad
		var since := t - _borrow_at
		if _borrow_quick:
			return pad.lerp(carry, OfficeProps.ease_out(since / Constants.ANNEX_BORROW_QUICK))
		var reach := Constants.ANNEX_BORROW_REACH
		var slide := Constants.ANNEX_BORROW_SLIDE
		# Under the glass, out over the lobby side of the ledge.
		var lip := global_transform * Vector3(STAMP_SPOT.x * 0.5, COUNTER_Y + 0.026, 0.34)
		if since < reach:
			return pad
		if since < reach + slide:
			return pad.lerp(lip, OfficeProps.ease_out((since - reach) / slide))
		var k := OfficeProps.ease_out((since - reach - slide) / Constants.ANNEX_BORROW_LIFT)
		return lip.lerp(carry, k) + Vector3.UP * 0.06 * sin(k * PI)

	func _begin(next: StringName, at: float, args: Dictionary) -> void:
		match next:
			&"lamp_on":
				# The bing is the lamp coming on, once: a window that stays lit
				# through a serve or a head shake stays quiet (R2b).
				if not lamp_on:
					cue("office_ding", at)
				_set_lamp(true)
			&"lamp_off":
				_set_lamp(false)
			&"blind_up", &"blind_down":
				_blind_from = _blinds.drop
				_blind_to = 0.0 if next == &"blind_up" else 1.0
				_blind_at = at
				_blind_set = true
				blind_down = next == &"blind_down"
				cue("blinds_rattle", at)
				if next == &"blind_up":
					_set_lamp(true)
			&"clock_sign":
				_sign_up = true
				_sign_from = at
				_clock_sign.visible = true
			&"clock_sign_off":
				_sign_up = false
				_sign_from = at
			&"stamp_lifted":
				_stamp_from = _stamp_rise_now
				_stamp_state = next
				_stamp_at = at
			&"stamp_rest":
				# Put back down without a sound (a hold let go before it counted).
				_stamp_from = _stamp_rise_now
				_stamp_state = next
				_stamp_at = at
				give_back(at)
			&"stamp_down":
				# Lift, then slam, the KA-CHUNK on the frame it hits the pad
				# (at + ANNEX_STAMP_HIT); a volley slams again every args.gap, the
				# first lift args.lift high (a wind-up), paper flying off each hit.
				var slams := maxi(1, int(args.get("volley", 1)))
				_stamp_state = next
				_stamp_at = at
				_stamp_volley = slams
				_stamp_gap = float(args.get("gap", Constants.CLERK_VOLLEY_GAP))
				_stamp_lift = float(args.get("lift", 0.24))
				_stamp_first = maxf(float(args.get("first", Constants.ANNEX_STAMP_HIT)), Constants.ANNEX_STAMP_SLAM_SECONDS + 0.05)
				_stamp_from = _stamp_rise_now if _stamp_rise_now > 0.01 else 0.0
				# A borrowed stamp lands on the form in a hand, and sounds there.
				var lands: Vector3 = _borrow_to.call() if _borrow_to.is_valid() else Vector3.INF
				if not lands.is_finite():
					lands = global_position + global_basis * STAMP_SPOT
				for index: int in slams:
					cue("stamp_kachunk", at + _stamp_first + float(index) * _stamp_gap, lands)
				_flutter_from = at + _stamp_first if slams > 1 else -1000.0
			&"bell":
				cue("desk_bell", at, global_position + global_basis * Vector3(-0.58, COUNTER_Y + 0.06, 0.24))
		_busy_until = maxf(_busy_until, at + 2.0 + (float(_stamp_volley) * _stamp_gap if next == &"stamp_down" else 0.0))

	func _animate(t: float) -> bool:
		var moving := false
		# Blinds, on their own clock whatever the window did since.
		if _blind_set:
			var k := clampf((t - _blind_at) / Constants.ANNEX_BLIND_SECONDS, 0.0, 1.0)
			# A rattle on the way: they jerk, not glide.
			var jerk := 0.04 * sin(k * 26.0) * (1.0 - k)
			_blinds.set_drop(lerpf(_blind_from, _blind_to, OfficeProps.ease_out(k)) + jerk)
			moving = k < 1.0
			if _clock_sign_card() != null:
				_clock_sign_card().visible = _blinds.drop > 0.5
		# The clock sign flips up off the ledge (or folds back down).
		var flip := clampf((t - _sign_from) / 0.25, 0.0, 1.0)
		var up := OfficeProps.ease_out(flip) if _sign_up else 1.0 - OfficeProps.ease_out(flip)
		_clock_sign.rotation.x = -(1.0 - up) * PI * 0.5
		if not _sign_up and flip >= 1.0:
			_clock_sign.visible = false
		moving = moving or flip < 1.0
		# The stamp: lifted in the clerk's hand, or lift-and-slam onto the pad.
		var rise := 0.0
		var since := t - _stamp_at
		if _stamp_state == &"stamp_lifted":
			rise = lerpf(_stamp_from, 0.24, OfficeProps.ease_out(since / Constants.ANNEX_STAMP_LIFT_SECONDS))
			moving = moving or since < Constants.ANNEX_STAMP_LIFT_SECONDS
		elif _stamp_state == &"stamp_rest":
			rise = lerpf(_stamp_from, 0.0, OfficeProps.ease_out(since / 0.18))
			moving = moving or since < 0.18
		elif _stamp_state == &"stamp_down":
			rise = _slam_rise(since)
			moving = moving or since < _stamp_first + float(_stamp_volley) * _stamp_gap + 0.4
		_stamp_rise_now = rise
		_stamp.position = STAMP_SPOT + Vector3(0.0, 0.026 + rise, 0.0)
		# Behind closed blinds the stamp is out of sight.
		_stamp.visible = _blinds.drop < 0.97
		_stamp.rotation.z = -rise * 0.6
		if _borrow_to.is_valid():
			# In a hand (R2c annex): carried to the form, the slam on top of that.
			var slam_up := rise if _stamp_state == &"stamp_down" else 0.0
			# In hand it isn't lifted off a pad: the slam starts from the form.
			_stamp_rise_now = slam_up
			_stamp.global_position = _borrowed_at(t) + Vector3.UP * slam_up
			_stamp.rotation.z = 0.0
			moving = true
			if _stamp_state == &"stamp_down" and since > _stamp_first + float(_stamp_volley - 1) * _stamp_gap + Constants.ANNEX_BORROW_LET_GO:
				give_back(t)
		elif t - _return_at < Constants.ANNEX_BORROW_RETURN:
			# Put back on its pad over the sill.
			var k := OfficeProps.ease_out((t - _return_at) / Constants.ANNEX_BORROW_RETURN)
			var pad := global_transform * (STAMP_SPOT + Vector3(0.0, 0.026, 0.0))
			_stamp.global_position = _return_from.lerp(pad, k) + Vector3.UP * Constants.ANNEX_BORROW_RETURN_ARC * sin(k * PI)
			moving = true
		elif _stamp_top_material != null and (_stamp.get_node("Mesh") as MeshInstance3D).material_override == _stamp_top_material:
			_stamp_on_top(false)
		moving = _flutter(t) or moving
		return moving

	## How high the stamp is `since` into a stamp_down: up (from where it was) and
	## down onto the pad by _stamp_first, then for a volley up and down again
	## every _stamp_gap, a squash settling after the last.
	func _slam_rise(since: float) -> float:
		var slam := Constants.ANNEX_STAMP_SLAM_SECONDS
		if since < 0.0:
			return _stamp_from
		if since < _stamp_first:
			var up_for := _stamp_first - slam
			if since < up_for:
				return lerpf(_stamp_from, _stamp_lift, OfficeProps.ease_out(since / maxf(up_for, 0.01)))
			return (1.0 - OfficeProps.ease_in((since - up_for) / slam)) * _stamp_lift
		var after := since - _stamp_first
		var index := floori(after / _stamp_gap)
		if index >= _stamp_volley - 1:
			# The squash on contact, settling.
			var settle := after - float(_stamp_volley - 1) * _stamp_gap
			return -0.006 * exp(-settle * 18.0) * cos(settle * 40.0)
		var local := after - float(index) * _stamp_gap
		var rise_for := maxf(_stamp_gap - slam, 0.01)
		var height := 0.15
		if local < rise_for:
			return OfficeProps.ease_out(local / rise_for) * height
		return (1.0 - OfficeProps.ease_in((local - rise_for) / slam)) * height

	## A volley's paper: a scrap shoots out of the hatch on each slam and flutters
	## down to the lobby floor. A pure function of time, like everything here.
	func _flutter(t: float) -> bool:
		var any := false
		if _flutter_from < -999.0 and _scraps.is_empty():
			return false
		for index: int in FLUTTER_COUNT:
			var scrap := _scrap(index)
			var launch := _flutter_from + float(index) * _stamp_gap
			var age := t - launch
			if _flutter_from < -999.0 or index >= _stamp_volley or age < 0.0 or age > 1.1:
				scrap.visible = false
				if _flutter_from > -999.0 and index < _stamp_volley and age < 0.0:
					any = true
				continue
			any = true
			scrap.visible = true
			var side := (float(index % 3) - 1.0) * 0.55 + 0.15 * sin(float(index) * 2.3)
			var velocity := Vector3(side, 1.7 + 0.25 * float(index % 2), 1.3)
			var drag := 1.0 - exp(-age * 2.2)
			var drift := velocity * drag / 2.2 + Vector3(0.0, -1.6 * age * age, 0.0)
			# Out of the hatch, under the glass, and down onto the lobby floor.
			var at := Vector3(STAMP_SPOT.x, COUNTER_Y + 0.1, 0.12) + drift
			at.y = maxf(at.y, 0.02)
			scrap.position = at
			scrap.rotation = Vector3(age * 7.0 + float(index), age * 5.0 * (1.0 if index % 2 == 0 else -1.0), sin(age * 9.0) * 0.6)
		return any

	func _scrap(index: int) -> MeshInstance3D:
		while _scraps.size() <= index:
			var scrap := MeshInstance3D.new()
			scrap.name = "Scrap%d" % _scraps.size()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.09, 0.12)
			scrap.mesh = quad
			if _scrap_material == null:
				_scrap_material = StandardMaterial3D.new()
				_scrap_material.albedo_color = PAPER
				_scrap_material.cull_mode = BaseMaterial3D.CULL_DISABLED
				_scrap_material.roughness = 0.9
			scrap.material_override = _scrap_material
			scrap.set_meta("keep_material", true)
			scrap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			scrap.visible = false
			add_child(scrap)
			_scraps.append(scrap)
		return _scraps[index]

	func _clock_sign_card() -> Node3D:
		return get_node_or_null("BackAt") as Node3D


## A colored line on the floor along points (lobby floor space, y ignored): the
## way from the chairs to its window. pulse brightens it twice.
class FloorLine extends Prop:
	var _material: StandardMaterial3D
	var color: Color
	var _sticker: Sprite3D

	## feet: the window's footprints (left/right print centers, floor space), in
	## the line's paint; the badge sticker sits at the line's start (R2b).
	func build(points: PackedVector3Array, line_color: Color, feet: PackedVector3Array = PackedVector3Array()) -> void:
		color = line_color
		var kit := _MeshKit.new()
		for index: int in feet.size():
			var side := -1.0 if index % 2 == 0 else 1.0
			kit.box(Vector3(feet[index].x, 0.016, feet[index].z), FOOT_SIZE, Color.WHITE, Basis(Vector3.UP, side * -0.12))
		if points.size() > 1:
			# The sticker: the window's badge, flat on the floor where the line begins,
			# turned so it reads the right way up walking along the line.
			_sticker = Sprite3D.new()
			_sticker.name = "Sticker"
			_sticker.shaded = true
			_sticker.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			_sticker.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			_sticker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var along := points[1] - points[0]
			_sticker.position = Vector3(points[0].x, 0.028, points[0].z) + Vector3(along.x, 0.0, along.z).normalized() * 0.32
			_sticker.rotation = Vector3(-PI * 0.5, atan2(-along.x, -along.z), 0.0)
			_sticker.visible = false
			add_child(_sticker)
		for index: int in points.size() - 1:
			var a := points[index]
			var b := points[index + 1]
			var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
			var length := along.length()
			if length < 0.01:
				continue
			var mid := (a + b) * 0.5
			var basis := Basis(Vector3.UP, atan2(along.x, along.z))
			kit.box(Vector3(mid.x, 0.02, mid.z), Vector3(0.12, 0.006, length + 0.12), Color.WHITE, basis)
		var view := MeshInstance3D.new()
		view.name = "Line"
		view.mesh = kit.commit()
		_material = OfficeProps.glow_material(line_color, 0.0)
		_material.roughness = 0.6
		view.material_override = _material
		view.set_meta("keep_material", true)
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(view)

	func recolor(line_color: Color) -> void:
		color = line_color
		_material.albedo_color = line_color
		_material.emission = line_color

	## The run's {icon, color}: the paint and the sticker.
	func apply_look(window_look: Dictionary) -> void:
		var icon := str(window_look.get("icon", ""))
		recolor(window_look.get("color", OfficeProps.icon_color(icon)))
		if _sticker != null:
			var texture: Texture2D = OfficeProps.badge_texture(icon, color) if OfficeProps.pictogram_texture(icon) != null else null
			_sticker.texture = texture
			_sticker.visible = texture != null
			if texture != null:
				_sticker.pixel_size = 0.5 / float(maxi(texture.get_width(), 1))

	func _animate(t: float) -> bool:
		var since := t - state_at
		if state != &"pulse" or since > Constants.ANNEX_PULSE_SECONDS:
			_material.emission_energy_multiplier = 0.0
			return false
		var k := clampf(since / Constants.ANNEX_PULSE_SECONDS, 0.0, 1.0)
		_material.emission_energy_multiplier = 1.6 * maxf(0.0, sin(k * PI * 2.0)) * (1.0 - k * 0.3)
		return true


## The big APPROVED, NICELY stamp on its velvet pad, the Head NICE BOY's.
class BigStamp extends Prop:
	var holder: Node3D = null
	var _rest: Vector3
	var _sheet: Node3D
	var _ink: MeshInstance3D

	func build() -> void:
		var kit := _MeshKit.new()
		kit.box(Vector3(0.0, 0.05, 0.0), Vector3(0.3, 0.1, 0.2), DARK)
		kit.box(Vector3(0.0, 0.004, 0.0), Vector3(0.28, 0.008, 0.18), VELVET.lightened(0.2))
		kit.box(Vector3(0.0, 0.105, 0.0), Vector3(0.32, 0.012, 0.22), _NiceSeal.LAVENDER)
		kit.tube(PackedVector3Array([Vector3(0.0, 0.1, 0.0), Vector3(0.0, 0.3, 0.0)]), PackedFloat32Array([0.026, 0.022]), Color(0.88, 0.7, 0.28), 8, {"jitter": 0.0})
		kit.blob(Vector3(0.0, 0.35, 0.0), Vector3(0.09, 0.07, 0.09), WOOD, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
		OfficeProps._view(self, kit, "Mesh", {"roughness": 0.5, "specular": 0.3})
		_rest = position
		# The form he lays on the pad to approve it (R2c): a sheet under the stamp,
		# APPROVED, NICELY inked on it when the stamp comes down. Set by the Head
		# NICE BOY's pose (npcs/clerk.gd), not here.
		_sheet = Node3D.new()
		_sheet.name = "Sheet"
		add_child(_sheet)
		var paper := _MeshKit.new()
		paper.box(Vector3(0.0, 0.002, 0.0), Vector3(0.24, 0.004, 0.32), PAPER)
		OfficeProps._view(_sheet, paper, "Paper", {"roughness": 0.9})
		var mark := _MeshKit.new()
		mark.box(Vector3(0.0, 0.0055, 0.02), Vector3(0.2, 0.002, 0.1), INK, Basis(Vector3.UP, 0.18))
		_ink = OfficeProps._view(_sheet, mark, "Ink", {"roughness": 0.9})
		_sheet.visible = false

	func set_rest(at: Vector3) -> void:
		_rest = at
		position = at

	## The sheet under the stamp at its rest (the Head NICE BOY's approval): shown
	## or not, and inked or not. It lies where the stamp rests, wherever the stamp is.
	func set_sheet(shown: bool, inked: bool) -> void:
		_sheet.visible = shown
		_ink.visible = inked
		if shown:
			_sheet.global_position = (get_parent() as Node3D).to_global(_rest)
			_sheet.global_rotation = Vector3(0.0, (get_parent() as Node3D).global_rotation.y + 0.2, 0.0)

	## Where it rests, in its parent's space.
	func rest() -> Vector3:
		return _rest

	## While the Head NICE BOY has it (a slam with args.puppet), his hands place it.
	func puppeted() -> bool:
		return state == &"slam" and bool(state_args.get("puppet", false))

	## Someone carries it (two-handed, at the chest), or null puts it back on its pad.
	func set_held(by: Node3D) -> void:
		holder = by
		set_process(true)
		if by == null:
			set_state(&"on_pad", OfficeProps.now())

	## How long after a slam's `at` the stamp hits the form (the KA-CHUNK): R2
	## chunk 6 lines the form's APPROVED, NICELY up with it. A player's slam
	## hesitates only ANNEX_BIG_STAMP_HOLDER_HESITATE (the drama is his).
	static func slam_lands_after(hesitate: float = Constants.ANNEX_BIG_STAMP_HESITATE) -> float:
		return Constants.ANNEX_BIG_STAMP_LIFT_SECONDS + hesitate + Constants.ANNEX_BIG_STAMP_SLAM_SECONDS

	## Where a holder carries it: low and right, two-handed (holder space).
	const HELD := Vector3(0.3, 1.0, -0.5)

	func _hesitate() -> float:
		return float(state_args.get("hesitate", Constants.ANNEX_BIG_STAMP_HESITATE))

	func _begin(next: StringName, at: float, args: Dictionary) -> void:
		if next == &"slam":
			var hit := at + slam_lands_after(float(args.get("hesitate", Constants.ANNEX_BIG_STAMP_HESITATE)))
			cue("stamp_kachunk", hit)
			if bool(args.get("toot", true)):
				cue("party_toot", hit + 0.08)
		elif next == &"on_pad":
			holder = null

	func _process(delta: float) -> void:
		super._process(delta)
		if holder != null and is_instance_valid(holder) and state != &"slam":
			var target := holder.global_transform * HELD
			global_position = global_position.lerp(target, clampf(delta * 10.0, 0.0, 1.0))
			global_rotation.y = holder.global_rotation.y
			set_process(true)

	func _animate(t: float) -> bool:
		var since := t - state_at
		if puppeted():
			# In the Head NICE BOY's hands (R2c: it rose and slammed by itself while
			# he stood at the cooler): his pose moves it; here only the sounds.
			return since < slam_lands_after(_hesitate()) + 0.6
		if state == &"slam":
			# In the holder's hands: raised high,
			# a held breath, slammed down where it was.
			var held := holder != null and is_instance_valid(holder)
			var lift := Constants.ANNEX_BIG_STAMP_LIFT_SECONDS
			# Held, it swings in from low right to the middle as it goes up, and
			# comes down there, in front of you (not up out of your view).
			var swing := OfficeProps.ease_out(since / lift)
			var base: Vector3 = holder.global_transform * Vector3(lerpf(HELD.x, 0.03, swing), HELD.y - 0.05 * swing, HELD.z) if held else (get_parent() as Node3D).to_global(_rest)
			var raise := Constants.ANNEX_BIG_STAMP_RAISE * (0.6 if held else 1.0)
			var up := 0.0
			var hesitate := _hesitate()
			if since < lift:
				up = OfficeProps.ease_out(since / lift)
			elif since < lift + hesitate:
				up = 1.0 + 0.03 * sin((since - lift) * 30.0)
			else:
				up = 1.0 - OfficeProps.ease_in((since - lift - hesitate) / Constants.ANNEX_BIG_STAMP_SLAM_SECONDS)
			global_position = base + Vector3(0.0, maxf(up, 0.0) * raise, 0.0)
			if held:
				global_rotation.y = holder.global_rotation.y
			var still := since < slam_lands_after(hesitate) + 0.4
			if not still and held:
				# Back to carrying it.
				state = &"held"
				return true
			return still
		if holder == null and state != &"held":
			position = position.lerp(_rest, 0.35)
			return position.distance_to(_rest) > 0.002
		return holder != null


## Copier, cooler, coffee machine: a Spot marker in front where the staff stand,
## and a light or bubble that shows what it's doing.
class Appliance extends Prop:
	var kind: String = "copier"
	var _light: MeshInstance3D
	var _light_on: StandardMaterial3D
	var _light_off: StandardMaterial3D

	func build(appliance: String) -> void:
		kind = appliance
		name = {"copier": "Copier", "cooler": "Cooler", "coffee": "CoffeeMachine"}[appliance]
		var kit := _MeshKit.new()
		var light_at := Vector3.ZERO
		var light_color := Color(0.3, 1.0, 0.4)
		match appliance:
			"copier":
				kit.box(Vector3(0.0, 0.45, 0.0), Vector3(1.0, 0.9, 0.65), BEIGE)
				kit.box(Vector3(0.0, 0.95, 0.0), Vector3(0.95, 0.1, 0.6), BEIGE.darkened(0.12))
				kit.box(Vector3(0.0, 1.01, 0.02), Vector3(0.8, 0.02, 0.5), DARK)
				kit.box(Vector3(0.55, 0.62, 0.0), Vector3(0.12, 0.04, 0.4), PAPER)
				kit.box(Vector3(0.3, 0.98, 0.31), Vector3(0.3, 0.05, 0.04), DARK.lightened(0.15))
				for drawer: int in 2:
					kit.box(Vector3(0.0, 0.2 + float(drawer) * 0.25, 0.33), Vector3(0.85, 0.2, 0.02), BEIGE.darkened(0.06))
				light_at = Vector3(0.12, 0.985, 0.33)
				light_color = Color(1.0, 0.25, 0.15)
			"cooler":
				kit.box(Vector3(0.0, 0.5, 0.0), Vector3(0.38, 1.0, 0.38), PAPER)
				kit.blob(Vector3(0.0, 1.25, 0.0), Vector3(0.16, 0.24, 0.16), Color(0.55, 0.78, 0.95), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
				kit.box(Vector3(-0.08, 0.78, 0.2), Vector3(0.04, 0.05, 0.04), Color(0.3, 0.45, 0.95))
				kit.box(Vector3(0.08, 0.78, 0.2), Vector3(0.04, 0.05, 0.04), Color(0.9, 0.25, 0.2))
				kit.box(Vector3(0.24, 0.9, 0.0), Vector3(0.08, 0.2, 0.08), PAPER.darkened(0.08))
				light_at = Vector3(0.0, 0.62, 0.195)
				light_color = Color(0.4, 0.75, 1.0)
			"coffee":
				kit.box(Vector3(0.0, 0.45, 0.0), Vector3(0.6, 0.9, 0.45), WOOD.darkened(0.3))
				kit.box(Vector3(0.0, 1.06, 0.0), Vector3(0.36, 0.32, 0.3), DARK)
				kit.box(Vector3(0.0, 1.25, 0.0), Vector3(0.38, 0.06, 0.32), DARK.lightened(0.1))
				kit.cone(Vector3(0.0, 0.92, 0.06), 0.08, 0.12, Color(0.25, 0.15, 0.08, 1.0), 10)
				kit.cone(Vector3(-0.2, 0.9, 0.1), 0.035, 0.08, PAPER, 8)
				kit.cone(Vector3(0.2, 0.9, 0.1), 0.035, 0.08, PAPER, 8)
				light_at = Vector3(0.12, 1.12, 0.155)
				light_color = Color(1.0, 0.55, 0.15)
		OfficeProps._view(self, kit, "Look", {}, true)
		_light_on = OfficeProps.glow_material(light_color, 2.0)
		_light_off = StandardMaterial3D.new()
		_light_off.albedo_color = light_color.darkened(0.7)
		var bulb := _MeshKit.new()
		bulb.box(light_at, Vector3(0.05, 0.03, 0.012), Color.WHITE)
		_light = MeshInstance3D.new()
		_light.name = "Light"
		_light.mesh = bulb.commit()
		_light.material_override = _light_off
		_light.set_meta("keep_material", true)
		_light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_light)
		OfficeProps._marker(self, "Spot", Vector3(0.0, 0.0, 0.75), PI)
		var size := {"copier": Vector3(1.0, 1.05, 0.65), "cooler": Vector3(0.4, 1.4, 0.4), "coffee": Vector3(0.6, 1.3, 0.45)}[appliance] as Vector3
		OfficeProps._solid(self, "Body", size, Vector3(0.0, size.y * 0.5, 0.0))

	func _begin(next: StringName, at: float, args: Dictionary) -> void:
		match next:
			&"jam":
				var beeps := int(args.get("beeps", 6))
				for index: int in beeps:
					cue("copier_beep", at + float(index) * 1.6)
			&"glug":
				cue("glug", at)

	func _animate(t: float) -> bool:
		var since := t - state_at
		var lit := false
		match state:
			&"jam":
				lit = fmod(maxf(since, 0.0), 0.8) < 0.4
			&"copying", &"brew":
				lit = true
			&"glug":
				lit = since < 1.2 and fmod(since, 0.3) < 0.15
		_light.material_override = _light_on if lit else _light_off
		return state == &"jam" or state == &"copying" or state == &"brew" or (state == &"glug" and since < 1.2)


## The co-signer sheet: a clipboard on a chain on the lobby podium.
class CoSignSheet extends Prop:
	var _pen: Node3D

	func build() -> void:
		var kit := _MeshKit.new()
		kit.box(Vector3(0.0, 0.01, 0.0), Vector3(0.26, 0.012, 0.34), WOOD.darkened(0.1))
		kit.box(Vector3(0.0, 0.018, 0.01), Vector3(0.22, 0.004, 0.28), PAPER)
		for line: int in 6:
			kit.box(Vector3(-0.01, 0.021, -0.1 + float(line) * 0.045), Vector3(0.17, 0.002, 0.004), INK.lightened(0.3))
		kit.box(Vector3(0.0, 0.025, -0.16), Vector3(0.1, 0.02, 0.03), STEEL)
		var chain := PackedVector3Array()
		for step: int in 6:
			var k := float(step) / 5.0
			chain.append(Vector3(0.13 + k * 0.12, 0.02 - sin(k * PI) * 0.04, 0.12 - k * 0.04))
		kit.tube(chain, PackedFloat32Array([0.004]), STEEL, 4, {"jitter": 0.0})
		OfficeProps._view(self, kit, "Look", {}, true)
		_pen = Node3D.new()
		_pen.name = "Pen"
		add_child(_pen)
		_pen.position = Vector3(0.06, 0.03, 0.05)
		var pen := _MeshKit.new()
		pen.tube(PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -0.13)]), PackedFloat32Array([0.006, 0.006]), Color(0.2, 0.35, 0.8), 6, {"jitter": 0.0})
		OfficeProps._view(_pen, pen, "Mesh")
		_pen.rotation = Vector3(0.0, 0.4, 0.0)

	func _begin(next: StringName, at: float, _args: Dictionary) -> void:
		if next == &"signing":
			cue("pen_squeak", at)
			cue("pen_squeak", at + 0.7)

	func _animate(t: float) -> bool:
		var since := t - state_at
		if state != &"signing" or since > Constants.ANNEX_PULSE_SECONDS + 0.3:
			_pen.position = Vector3(0.06, 0.03, 0.05)
			_pen.rotation = Vector3(0.0, 0.4, 0.0)
			return false
		_pen.position = Vector3(0.02 + 0.05 * sin(since * 14.0), 0.035, -0.02 + 0.02 * sin(since * 9.0))
		_pen.rotation = Vector3(0.5, 0.4 + 0.2 * sin(since * 14.0), 0.0)
		return true


## The OUTGOING tray: a wire tray on a stand; a finished form flies into it.
class OutgoingTray extends Prop:
	var _paper: Node3D

	func build() -> void:
		var kit := _MeshKit.new()
		kit.box(Vector3(0.0, 0.45, 0.0), Vector3(0.05, 0.9, 0.05), STEEL)
		kit.cone(Vector3(0.0, 0.0, 0.0), 0.22, 0.03, DARK, 10)
		kit.box(Vector3(0.0, 0.92, 0.0), Vector3(0.42, 0.02, 0.32), STEEL.darkened(0.1))
		for side: float in [-1.0, 1.0]:
			kit.box(Vector3(side * 0.21, 0.97, 0.0), Vector3(0.015, 0.1, 0.32), STEEL)
			kit.box(Vector3(0.0, 0.97, side * 0.16), Vector3(0.42, 0.1, 0.015), STEEL)
		for sheet: int in 3:
			kit.box(Vector3(0.01 * float(sheet), 0.94 + float(sheet) * 0.006, 0.0), Vector3(0.3, 0.004, 0.24), PAPER.darkened(0.03 * float(sheet)), Basis(Vector3.UP, 0.08 * float(sheet)))
		kit.box(Vector3(0.0, 1.06, 0.165), Vector3(0.36, 0.08, 0.01), _NiceSeal.LAVENDER)
		OfficeProps._view(self, kit, "Look", {}, true)
		OfficeProps._label(self, _Strings.ANNEX_SIGNS["outgoing"], Vector3(0.0, 1.06, 0.172), 32, DARK, 0.0028)
		_paper = Node3D.new()
		_paper.name = "Flying"
		add_child(_paper)
		var paper := _MeshKit.new()
		paper.box(Vector3.ZERO, Vector3(0.24, 0.004, 0.3), PAPER)
		OfficeProps._view(_paper, paper, "Mesh")
		_paper.visible = false
		OfficeProps._marker(self, "Spot", Vector3(0.0, 0.0, 0.7), PI)
		# Solid: nobody stands inside it (R2b).
		OfficeProps._solid(self, "Body", Vector3(0.44, 1.05, 0.34), Vector3(0.0, 0.525, 0.0))

	func _begin(next: StringName, at: float, _args: Dictionary) -> void:
		if next == &"receive":
			cue("whoosh", at)
			cue("pen_squeak", at + 0.55)

	func _animate(t: float) -> bool:
		var since := t - state_at
		if state != &"receive" or since > 0.6:
			_paper.visible = false
			return false
		var from: Vector3 = state_args.get("from", global_position + global_basis * Vector3(0.0, 1.2, 0.8))
		var to := global_position + global_basis * Vector3(0.0, 0.97, 0.0)
		var k := OfficeProps.ease_out(since / 0.55)
		_paper.visible = true
		_paper.global_position = from.lerp(to, k) + Vector3(0.0, sin(k * PI) * 0.35, 0.0)
		_paper.rotation = Vector3(sin(k * 9.0) * 0.4, k * 4.0, 0.0)
		return true


## A waist-high three-arm turnstile in the exit passage.
class Turnstile extends Prop:
	var _arms: Node3D
	var _body: StaticBody3D
	var _turn_from: float = 0.0
	var _turned: float = 0.0

	func build(passage: float, clear_height: float) -> void:
		var kit := _MeshKit.new()
		kit.box(Vector3(-passage * 0.5 - 0.14, 0.5, 0.0), Vector3(0.28, 1.0, 0.7), STEEL.darkened(0.2))
		kit.box(Vector3(-passage * 0.5 - 0.14, 1.01, 0.0), Vector3(0.3, 0.03, 0.72), DARK)
		kit.box(Vector3(passage * 0.5 + 0.04, 0.5, 0.0), Vector3(0.08, 1.0, 0.7), STEEL.darkened(0.2))
		kit.box(Vector3(-passage * 0.5 - 0.14, 0.86, 0.36), Vector3(0.1, 0.06, 0.01), Color(0.3, 1.0, 0.4))
		OfficeProps._view(self, kit, "Posts", {}, true)
		# The classic tripod: three arms 120 degrees apart round a hub on the post,
		# its axle tilted so the top arm lies level across the passage.
		_arms = Node3D.new()
		_arms.name = "Arms"
		add_child(_arms)
		_arms.position = Vector3(-passage * 0.5, 0.86, 0.0)
		var arms := _MeshKit.new()
		arms.blob(Vector3.ZERO, Vector3(0.09, 0.09, 0.09), STEEL.lightened(0.2), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
		for index: int in 3:
			var angle := TAU * float(index) / 3.0
			var spoke := Vector3(cos(angle), 0.0, sin(angle)) * passage * 0.92
			arms.tube(PackedVector3Array([Vector3.ZERO, spoke]), PackedFloat32Array([0.022, 0.02]), STEEL.lightened(0.25), 6, {"jitter": 0.0})
		OfficeProps._view(_arms, arms, "Mesh", {"roughness": 0.3, "specular": 0.6})
		_spin(0.0)
		# Closed, it seals the passage up to the lintel (clear_height): the arms are
		# waist high, but a jump with a crouch at the top would clear them.
		_body = OfficeProps._solid(self, "Body", Vector3(passage, clear_height, 0.15), Vector3(0.0, clear_height * 0.5, 0.0))

	## The arms turned by spin (radians) round the tilted axle.
	func _spin(spin: float) -> void:
		_turned = spin
		_arms.basis = Basis(Vector3.RIGHT, -PI * 0.25) * Basis(Vector3.UP, spin)

	## Who's pushing through, how far (0..1), whether this push has clacked (R2b:
	## the arms turn with the body, one ratchet clack per push, never on a timer).
	var _push_progress: float = 0.0
	var _push_clacked: bool = false
	var _push_done: bool = false
	## Whose push turns the arms (player node names); empty means anyone's. Only
	## the players it was unlocked for: someone it wasn't for stops at the bar.
	var _who: Array = []
	## Server time it locks again (INF: until told, as at closing).
	var _open_until: float = -1000.0

	## Whether this prop dropped its own bar (an open for anyone).
	var _unsealed: bool = false

	## open args: {seconds} (a span, then it locks again; none: until "closed"),
	## {who} (the player node names it turns for). Opened for named players, the
	## bar's collider is not the prop's: annex.gd lets only its own local player
	## through (_step_turnstile), so no one else walks through on their own peer.
	## Opened for anyone (no who), it drops the bar itself.
	func _begin(next: StringName, at: float, args: Dictionary) -> void:
		match next:
			&"open":
				# Unlocked: the arms wait for a push, and turn with it.
				_turn_from = _turned
				var seconds := float(args.get("seconds", 0.0))
				var until := at + seconds if seconds > 0.0 else INF
				var who: Array = args.get("who", [])
				if who.is_empty() and not _unsealed:
					_unsealed = true
					_set_solid(false)
				var still_open := at < _open_until
				if still_open and _who.is_empty():
					pass
				elif still_open and not who.is_empty():
					for name_id: Variant in who:
						if not _who.has(name_id):
							_who.append(name_id)
				else:
					_who = who.duplicate()
				_open_until = maxf(until, _open_until if still_open else -1000.0)
				_busy_until = maxf(_busy_until, at + (seconds if seconds > 0.0 else Constants.ANNEX_TURNSTILE_OPEN + 1.0))
			&"bounce":
				_turn_from = _turned
				cue("turnstile_clunk", at)
			&"closed":
				_open_until = -1000.0
				_who = []
				_push_progress = 0.0
				_push_clacked = false
				_push_done = false
				if _unsealed:
					_unsealed = false
					_set_solid(true)

	func _set_solid(on: bool) -> void:
		var shape := _body.get_child(0) as CollisionShape3D
		shape.set_deferred("disabled", not on)

	func _animate(t: float) -> bool:
		var since := t - state_at
		match state:
			&"open":
				var push := _pushing()
				if _push_done:
					# Through: the next push starts once they're clear of the arms.
					_push_done = push > 0.0
					push = 0.0
				if push > _push_progress or push <= 0.0:
					_push_progress = push
				else:
					# Backing off lets the arms ease back (a turnstile won't turn backwards past its pawl).
					_push_progress = move_toward(_push_progress, push, 0.05)
				if _push_progress >= 0.5 and not _push_clacked:
					_push_clacked = true
					OfficeProps._play_sfx(self, "turnstile_clack", global_position + Vector3(0.0, 0.9, 0.0))
				var spin := _turn_from + OfficeProps.ease_out(_push_progress) * TAU / 3.0
				_arms.basis = Basis(Vector3.RIGHT, -PI * 0.25) * Basis(Vector3.UP, spin)
				if _push_progress >= 0.999:
					# Through: the arms rest a third further round, ready for the next.
					_turned = fmod(_turn_from + TAU / 3.0, TAU)
					_turn_from = _turned
					_push_progress = 0.0
					_push_clacked = false
					_push_done = true
				if t >= _open_until and _push_progress <= 0.0:
					set_state(&"closed", minf(t, _open_until))
					return false
				return true
			&"bounce":
				var k := clampf(since / Constants.ANNEX_TURNSTILE_BOUNCE_SECONDS, 0.0, 1.0)
				_arms.basis = Basis(Vector3.RIGHT, -PI * 0.25) * Basis(Vector3.UP, _turn_from + sin(k * PI * 3.0) * 0.12 * (1.0 - k))
				if k >= 1.0 and t < _open_until:
					# Someone bounced while it was unlocked for another: still theirs to push.
					state = &"open"
					return true
				return k < 1.0
		_spin(_turned)
		return false

	## How far through the passage the nearest person in it is, 0 (before the
	## bar) to 1 (past it); 0 when nobody's in it. Lobby side is -Z.
	func _pushing() -> float:
		if not is_inside_tree():
			return 0.0
		var best := 0.0
		var half := absf(_arms.position.x) + 0.35
		for node: Node in get_tree().get_nodes_in_group("players"):
			var person := node as Node3D
			if person == null or not person.is_visible_in_tree():
				continue
			if not _who.is_empty() and not _who.has(str(person.name)):
				continue
			var local := global_transform.affine_inverse() * person.global_position
			if absf(local.x) > half or local.z < Constants.ANNEX_TURNSTILE_PUSH.x - 0.2 or local.z > Constants.ANNEX_TURNSTILE_PUSH.y + 0.2:
				continue
			best = maxf(best, inverse_lerp(Constants.ANNEX_TURNSTILE_PUSH.x, Constants.ANNEX_TURNSTILE_PUSH.y, local.z))
		return clampf(best, 0.0, 1.0)


## A row of fluorescent panels in the drop ceiling, and its warm fill light.
class LightRow extends Prop:
	var lit: bool = true
	var _panels: MeshInstance3D
	var _on_mat: StandardMaterial3D
	var _off_mat: StandardMaterial3D
	var _lights: Array[OmniLight3D] = []

	func build(width: float, panel_count: int) -> void:
		var kit := _MeshKit.new()
		for index: int in panel_count:
			var x := -width * 0.5 + (float(index) + 0.5) * width / float(panel_count)
			kit.box(Vector3(x, 0.0, 0.0), Vector3(1.1, 0.02, 0.5), Color.WHITE)
		_panels = MeshInstance3D.new()
		_panels.name = "Panels"
		_panels.mesh = kit.commit()
		_on_mat = OfficeProps.glow_material(Color(1.0, 0.97, 0.9), 0.9)
		_off_mat = StandardMaterial3D.new()
		_off_mat.albedo_color = Color(0.55, 0.55, 0.52)
		_panels.material_override = _on_mat
		_panels.set_meta("keep_material", true)
		_panels.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_panels)
		for side: float in [-0.25, 0.25]:
			var light := OmniLight3D.new()
			light.name = "Light%d" % _lights.size()
			light.light_color = Color(1.0, 0.92, 0.8)
			light.light_energy = Constants.ANNEX_LAMP_ENERGY
			light.omni_range = Constants.ANNEX_LAMP_RANGE
			light.omni_attenuation = 1.2
			light.position = Vector3(side * width, -0.7, 0.0)
			light.shadow_enabled = false
			# Fill light, not spotlights: no blown-out glints on the tiles (R2b).
			light.light_specular = 0.08
			light.add_to_group("lamps")
			add_child(light)
			_lights.append(light)

	func _begin(next: StringName, at: float, _args: Dictionary) -> void:
		if next == &"off":
			cue("lights_off_clunk", at)
		elif next == &"on":
			_set_lit(true, 1.0)

	func _set_lit(on: bool, level: float) -> void:
		lit = on
		_panels.material_override = _on_mat if on else _off_mat
		for light: OmniLight3D in _lights:
			light.visible = on
			light.light_energy = Constants.ANNEX_LAMP_ENERGY * level

	func _animate(t: float) -> bool:
		var since := t - state_at
		match state:
			&"off":
				_set_lit(since < 0.0, 1.0)
				return since < 0.0
			&"flicker":
				# A tired tube: mostly on, dropping out in uneven blinks.
				var blink := sin(since * 23.0) + sin(since * 37.0 + 1.3) > 1.2
				_set_lit(not blink, 0.8 if blink else 1.0)
				return true
		_set_lit(true, 1.0)
		return false


## A wall clock whose hands go set_speed times real time (closing time speeds it).
class WallClock extends Node3D:
	var speed: float = 1.0
	var minutes: float = 16.0 * 60.0 + 25.0
	var _minute: Node3D
	var _hour: Node3D

	func build() -> void:
		# A school clock facing +Z: a black rim round a white face, twelve ticks.
		var kit := _MeshKit.new()
		kit.tube(PackedVector3Array([Vector3(0.0, 0.0, -0.03), Vector3(0.0, 0.0, 0.02)]), PackedFloat32Array([0.3, 0.3]), PAPER, 18, {"jitter": 0.0})
		kit.tube(PackedVector3Array([Vector3(0.0, 0.0, -0.03), Vector3(0.0, 0.0, 0.035)]), PackedFloat32Array([0.32, 0.32]), DARK, 18, {"jitter": 0.0, "cap": false})
		for tick: int in 12:
			var angle := TAU * float(tick) / 12.0
			kit.box(Vector3(sin(angle) * 0.25, cos(angle) * 0.25, 0.022), Vector3(0.015, 0.04, 0.004), DARK, Basis(Vector3.BACK, -angle))
		OfficeProps._view(self, kit, "Face", {}, true)
		_minute = _hand(0.22, 0.012)
		_hour = _hand(0.14, 0.018)
		set_process(true)

	func _hand(length: float, width: float) -> Node3D:
		var pivot := Node3D.new()
		add_child(pivot)
		pivot.position = Vector3(0.0, 0.0, 0.03)
		var kit := _MeshKit.new()
		kit.box(Vector3(0.0, length * 0.4, 0.0), Vector3(width, length, 0.006), DARK)
		OfficeProps._view(pivot, kit, "Hand")
		return pivot

	func set_speed(times: float) -> void:
		speed = times

	func _process(delta: float) -> void:
		minutes += delta * speed / 60.0
		_minute.rotation.z = -TAU * fmod(minutes, 60.0) / 60.0
		_hour.rotation.z = -TAU * fmod(minutes / 60.0, 12.0) / 12.0


## The NOW SERVING board: a number, nothing else.
class NowServing extends Node3D:
	var number: int = 7
	var _label3d: Label3D

	func build() -> void:
		var kit := _MeshKit.new()
		kit.box(Vector3.ZERO, Vector3(1.25, 0.56, 0.06), DARK)
		OfficeProps._view(self, kit, "Board", {}, true)
		_label3d = OfficeProps._label(self, "", Vector3(0.0, 0.0, 0.035), 56, Color(1.0, 0.35, 0.2), 0.0032)
		show_number(number)

	func show_number(n: int) -> void:
		number = n
		_label3d.text = "%s\n%02d" % [_Strings.ANNEX_SIGNS["now_serving"], posmod(n, 100)]


## A glass door (or a pair) that slides open sideways, with its collider.
class SlideDoor extends Prop:
	var _panels: Array[Node3D] = []
	var _closed_x: Array[float] = []
	var _width: float
	var _bodies: Array[CollisionShape3D] = []
	var _open_from: float = 0.0
	var opened: float = 0.0

	func build(width: float, pair: bool) -> void:
		_width = width
		var count := 2 if pair else 1
		var glass := OfficeProps.glass_material()
		for index: int in count:
			var panel := Node3D.new()
			panel.name = "Panel%d" % index
			add_child(panel)
			var x := (-width * 0.25 if index == 0 else width * 0.25) if pair else 0.0
			panel.position.x = x
			_closed_x.append(x)
			var w := width * 0.5 if pair else width
			var kit := _MeshKit.new()
			kit.box(Vector3(0.0, 1.1, 0.0), Vector3(w, 0.06, 0.06), TRIM)
			kit.box(Vector3(0.0, 0.03, 0.0), Vector3(w, 0.06, 0.06), TRIM)
			kit.box(Vector3(-w * 0.5 + 0.03, 1.1, 0.0), Vector3(0.06, 2.2, 0.06), TRIM)
			kit.box(Vector3(w * 0.5 - 0.03, 1.1, 0.0), Vector3(0.06, 2.2, 0.06), TRIM)
			kit.box(Vector3(0.0, 2.17, 0.0), Vector3(w, 0.06, 0.06), TRIM)
			kit.box(Vector3((w * 0.5 - 0.12) * (1.0 if index == 0 else -1.0), 1.05, 0.04), Vector3(0.03, 0.4, 0.03), STEEL)
			OfficeProps._view(panel, kit, "Frame", {"roughness": 0.4})
			var pane := MeshInstance3D.new()
			pane.name = "Glass"
			var quad := QuadMesh.new()
			quad.size = Vector2(w - 0.1, 2.1)
			pane.mesh = quad
			pane.material_override = glass
			pane.set_meta("keep_material", true)
			pane.position = Vector3(0.0, 1.1, 0.0)
			pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			panel.add_child(pane)
			var body := OfficeProps._solid(panel, "Body", Vector3(w, 2.2, 0.08), Vector3(0.0, 1.1, 0.0))
			_bodies.append(body.get_child(0) as CollisionShape3D)
		state = &"closed"

	func _begin(next: StringName, at: float, _args: Dictionary) -> void:
		_open_from = opened
		if next == &"open":
			cue("door_chime", at)
			for shape: CollisionShape3D in _bodies:
				shape.set_deferred("disabled", true)
		elif next == &"closed":
			for shape: CollisionShape3D in _bodies:
				shape.set_deferred("disabled", false)

	func _animate(t: float) -> bool:
		var since := t - state_at
		var k := clampf(since / Constants.ANNEX_DOOR_SECONDS, 0.0, 1.0)
		var target := 1.0 if state == &"open" else 0.0
		opened = lerpf(_open_from, target, OfficeProps.ease_out(k))
		for index: int in _panels_count():
			var panel := get_child(index) as Node3D
			var away := (-1.0 if index == 0 else 1.0) if _closed_x.size() > 1 else 1.0
			var travel := _width * (0.48 if _closed_x.size() > 1 else 0.95)
			panel.position.x = _closed_x[index] + away * travel * opened
		return k < 1.0

	func _panels_count() -> int:
		return _closed_x.size()


## A swinging half door (the staff gate): it swings open when a staff body walks
## through it, and back with a little wobble. Its collider (door height) keeps the
## lobby out of the back; the staff are cosmetic and walk through it.
class StaffDoor extends Node3D:
	var _leaf: Node3D
	var _staff: Node3D
	var _swing: float = 0.0
	var _speed: float = 0.0

	func build(width: float, staff: Node3D) -> void:
		_staff = staff
		_leaf = Node3D.new()
		_leaf.name = "Leaf"
		add_child(_leaf)
		_leaf.position = Vector3(-width * 0.5, 0.0, 0.0)
		var kit := _MeshKit.new()
		kit.box(Vector3(width * 0.5, 0.65, 0.0), Vector3(width - 0.04, 0.9, 0.05), WOOD)
		kit.box(Vector3(width * 0.5, 1.12, 0.0), Vector3(width, 0.06, 0.07), WOOD.darkened(0.2))
		OfficeProps._view(_leaf, kit, "Mesh")
		# Taller than the leaf: the lobby can't hop the half door into the back.
		OfficeProps._solid(self, "Body", Vector3(width, 2.3, 0.08), Vector3(0.0, 1.15, 0.0))
		set_process(true)

	func _process(delta: float) -> void:
		var want := 0.0
		if _staff != null:
			for body: Node in _staff.get_children():
				var person := body as Node3D
				if person != null and person.global_position.distance_to(global_position) < 0.9:
					want = 1.4 * signf((global_transform.affine_inverse() * person.global_position).z + 0.001)
		# A spring: it overshoots and swings back.
		_speed += (want - _swing) * 40.0 * delta - _speed * 6.0 * delta
		_swing += _speed * delta
		_leaf.rotation.y = _swing


# ---------------------------------------------------------------- builders

static func service_window(id: String, look: Dictionary) -> Node3D:
	var window := ServiceWindow.new()
	window.build(id, look)
	return window


static func floor_line(points: PackedVector3Array, color: Color, feet: PackedVector3Array = PackedVector3Array()) -> Node3D:
	var line := FloorLine.new()
	line.build(points, color, feet)
	return line


static func big_stamp() -> Node3D:
	var stamp := BigStamp.new()
	stamp.name = "BigStamp"
	stamp.build()
	return stamp


static func appliance(kind: String) -> Node3D:
	var made := Appliance.new()
	made.build(kind)
	return made


static func cosign_sheet() -> Node3D:
	var sheet := CoSignSheet.new()
	sheet.name = "CoSignSheet"
	sheet.build()
	return sheet


static func outgoing_tray() -> Node3D:
	var tray := OutgoingTray.new()
	tray.name = "OutgoingTray"
	tray.build()
	return tray


## clear_height: the passage's lintel, which the closed turnstile seals up to.
static func turnstile(passage: float, clear_height: float = 2.4) -> Node3D:
	var made := Turnstile.new()
	made.name = "Turnstile"
	made.build(passage, clear_height)
	return made


static func light_row(index: int, width: float, panels: int) -> Node3D:
	var row := LightRow.new()
	row.name = "Row%d" % index
	row.build(width, panels)
	return row


static func wall_clock() -> Node3D:
	var clock := WallClock.new()
	clock.name = "WallClock"
	clock.build()
	return clock


static func now_serving() -> Node3D:
	var board := NowServing.new()
	board.name = "NowServing"
	board.build()
	return board


static func slide_door(node_name: String, width: float, pair: bool) -> Node3D:
	var door := SlideDoor.new()
	door.name = node_name
	door.build(width, pair)
	return door


static func staff_door(width: float, staff: Node3D) -> Node3D:
	var door := StaffDoor.new()
	door.name = "StaffDoor"
	door.build(width, staff)
	return door
