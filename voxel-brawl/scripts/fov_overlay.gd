# scripts/fov_overlay.gd
# Raycasts the visibility cone each frame and pushes world-space XZ polygon
# points to fov_world.gdshader. No screen projection at all — the shader reads
# the depth buffer to reconstruct world position for every pixel, then tests
# the world XZ coordinate against this polygon. Correct at every height.
class_name FovOverlay
extends Node

static var instance: FovOverlay = null

const RAY_COUNT        := 96    # Rays across the cone arc
const VISION_RADIUS    := 12.0  # World units
const FOV_ANGLE        := 120.0 # Total cone width in degrees
const PROXIMITY_RADIUS := 3.0   # World units — always visible around player

var _player: Player
var _mat: ShaderMaterial
var _pts: PackedVector2Array
var _prox_center: Vector2

func _ready() -> void:
	instance = self
	_pts.resize(128)

func setup(player: Player, mat: ShaderMaterial) -> void:
	_player = player
	_mat    = mat

func _process(_delta: float) -> void:
	if _mat == null or _player == null:
		return

	var origin  := _player.global_position + Vector3(0.0, 1.2, 0.0)
	var space   := _player.get_world_3d().direct_space_state
	var exclude := [_player.get_rid()]

	var facing     := -_player.global_transform.basis.z
	var base_angle := atan2(facing.z, facing.x)
	var half_fov   := deg_to_rad(FOV_ANGLE * 0.5)

	# Apex: player world XZ
	_pts[0] = Vector2(_player.global_position.x, _player.global_position.z)
	_prox_center = _pts[0]

	for i in RAY_COUNT:
		var t     := float(i) / (RAY_COUNT - 1)
		var angle := base_angle - half_fov + t * (half_fov * 2.0)
		var dir   := Vector3(cos(angle), 0.0, sin(angle))

		var rp := PhysicsRayQueryParameters3D.create(
			origin,
			origin + dir * VISION_RADIUS,
			1  # Layer 1 = walls / static bodies only
		)
		rp.collide_with_bodies = true
		rp.collide_with_areas  = false
		rp.exclude             = exclude

		var hit := space.intersect_ray(rp)
		var raw: Vector3
		if hit.is_empty():
			raw = origin + dir * VISION_RADIUS
		else:
			# Pull back slightly from the wall so the polygon boundary sits inside
			# the wall surface — prevents depth-precision jitter and edge fragments.
			raw = hit.position - dir * -0.5

		_pts[i + 1] = Vector2(raw.x, raw.z)

	# Pad remaining slots
	for i in range(RAY_COUNT + 1, 128):
		_pts[i] = _pts[RAY_COUNT]

	_mat.set_shader_parameter("fov_points", _pts)
	_mat.set_shader_parameter("prox_center", _prox_center)
	_mat.set_shader_parameter("prox_radius", PROXIMITY_RADIUS)

# Returns true if the given world XZ position is within the current FOV.
# Same Jordan curve test as the shader — used to show/hide game entities.
func is_visible_xz(xz: Vector2) -> bool:
	if _pts.is_empty():
		return true
	var inside := false
	var n := _pts.size()
	var j := n - 1
	for i in n:
		var a: Vector2 = _pts[i]
		var b: Vector2 = _pts[j]
		if ((a.y > xz.y) != (b.y > xz.y)) and \
				(xz.x < (b.x - a.x) * (xz.y - a.y) / (b.y - a.y) + a.x):
			inside = !inside
		j = i
	return inside or (_prox_center - xz).length() < PROXIMITY_RADIUS
