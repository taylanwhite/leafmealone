extends Node3D

## Authority: local, cosmetic. A real mirror (docs/GAME.md "Cosmetics"; gap-specs
## shops chunk 7): Homie Depot's, by the hat rack, so you can see the hat you just
## put on. In first person your own head is hidden from you
## (CartoonBody.HEAD_LAYER); here you see all of you, and your crew behind you.
##
## The glass faces the node's +Z, centered on its origin, `size` across. While
## the camera on screen is within Constants.MIRROR_RANGE in front of it, a
## SubViewport sharing the world draws the room from the camera's reflection
## through the glass (an off-axis frustum whose near plane is the glass, so
## nothing behind the mirror shows), and the glass shows that picture flipped
## left to right. Otherwise it stops drawing and shows plain glass. The camera
## leaves out the first-person arms (FirstPersonArms.ARMS_LAYER): you see your
## body's arms instead.

const _FirstPersonArms = preload("res://player/first_person_arms.gd")

## The glass's size (m) and its picture's size (pixels).
var size := Constants.MIRROR_SIZE
var pixels := Constants.MIRROR_PIXELS
## Whether it drew a reflection this frame (tests and recordings).
var reflecting: bool = false

var _viewport: SubViewport
var _camera: Camera3D
var _glass: MeshInstance3D
var _live: StandardMaterial3D
var _plain: StandardMaterial3D


func _ready() -> void:
	add_to_group("mirrors")
	_viewport = SubViewport.new()
	_viewport.name = "Reflection"
	_viewport.size = pixels
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.name = "Eye"
	_camera.cull_mask = 0xFFFFF & ~(1 << (_FirstPersonArms.ARMS_LAYER - 1))
	_viewport.add_child(_camera)
	_camera.current = true
	var quad := QuadMesh.new()
	quad.size = size
	_glass = MeshInstance3D.new()
	_glass.name = "Glass"
	_glass.mesh = quad
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass)
	_live = StandardMaterial3D.new()
	_live.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_live.albedo_texture = _viewport.get_texture()
	# The camera's picture, flipped left to right: that's what a mirror shows.
	_live.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	_live.uv1_offset = Vector3(1.0, 0.0, 0.0)
	_live.albedo_color = Color(0.94, 0.97, 1.0)
	_plain = StandardMaterial3D.new()
	_plain.albedo_color = Color(0.62, 0.7, 0.76)
	_plain.metallic = 0.8
	_plain.roughness = 0.12
	_glass.material_override = _plain


func _process(_delta: float) -> void:
	var view := get_viewport().get_camera_3d() if is_inside_tree() else null
	var normal := global_basis.z.normalized()
	var on := false
	var eye := Vector3.ZERO
	if view != null and DisplayServer.get_name() != "headless":
		eye = view.global_position
		var ahead := (eye - global_position).dot(normal)
		on = ahead > 0.05 and eye.distance_to(global_position) <= Constants.MIRROR_RANGE
	if on != reflecting:
		reflecting = on
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		_glass.material_override = _live if on else _plain
	if on:
		_aim(eye, normal)


## The reflected eye behind the glass, looking out through it at the room, with
## its frustum cut to the glass.
func _aim(eye: Vector3, normal: Vector3) -> void:
	var distance := (eye - global_position).dot(normal)
	var reflected := eye - 2.0 * distance * normal
	# Looking along +normal: the mirror's own frame turned round.
	var basis := (global_basis.orthonormalized() * Basis(Vector3.UP, PI))
	_camera.global_transform = Transform3D(basis, reflected)
	var center := basis.inverse() * (global_position - reflected)
	# The frustum's size and offset are measured on its near plane, just this side
	# of the glass: scale the glass down to it.
	var near := maxf(distance - 0.01, 0.05)
	var k := near / maxf(distance, 0.001)
	_camera.set_frustum(size.y * k, Vector2(center.x, center.y) * k, near, 80.0)
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
