# scripts/debris_pool.gd
class_name DebrisPool
extends Node

# Singleton reference — VoxelSegment accesses via get_node_or_null("/root/DebrisPool")
static var instance: DebrisPool = null

const CUBE_COUNT := 80
const CUBE_SIZE := 0.08
const CUBE_LIFETIME := 3.0

const STAIN_COUNT := 60
const STAIN_LIFETIME := 20.0

var _cubes: Array[RigidBody3D] = []
var _cursor: int = 0
var _particles: GPUParticles3D

var _stains: Array[Decal] = []
var _stain_cursor: int = 0
var _stain_texture: ImageTexture

func _ready() -> void:
	instance = self
	_spawn_cube_pool()
	_setup_particles()
	_create_stain_texture()
	_spawn_stain_pool.call_deferred()

func _spawn_cube_pool() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * CUBE_SIZE
	mesh.surface_set_material(0, mat)

	for _i in CUBE_COUNT:
		var rb := RigidBody3D.new()
		rb.freeze = true

		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		rb.add_child(mi)

		var col := CollisionShape3D.new()
		col.shape = BoxShape3D.new()
		(col.shape as BoxShape3D).size = Vector3.ONE * CUBE_SIZE
		rb.add_child(col)

		add_child(rb)
		rb.global_position = Vector3(0, -100, 0)
		_cubes.append(rb)

func _setup_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = 40
	_particles.one_shot = true
	_particles.explosiveness = 0.95
	_particles.lifetime = 0.6
	_particles.emitting = false

	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.05
	var particle_mat := StandardMaterial3D.new()
	particle_mat.albedo_color = Color(0.9, 0.05, 0.03)
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, particle_mat)
	_particles.draw_pass_1 = mesh

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	_particles.process_material = pm

	add_child(_particles)

func _create_stain_texture() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var center := Vector2(32.0, 32.0)
	for y in 64:
		for x in 64:
			var d := Vector2(x, y).distance_to(center) / 32.0
			var alpha: float = clamp(1.0 - d, 0.0, 1.0)
			alpha = pow(alpha, 0.4)  # soft falloff
			img.set_pixel(x, y, Color(0.55, 0.02, 0.02, alpha * 0.8))
	_stain_texture = ImageTexture.create_from_image(img)

func _spawn_stain_pool() -> void:
	for _i in STAIN_COUNT:
		var decal := Decal.new()
		decal.texture_albedo = _stain_texture
		decal.size = Vector3(0.35, 1.0, 0.35)
		decal.global_position = Vector3(0, -100, 0)
		add_child(decal)
		_stains.append(decal)

func _place_stain(pos: Vector3) -> void:
	var decal := _stains[_stain_cursor]
	_stain_cursor = (_stain_cursor + 1) % STAIN_COUNT
	# Raise slightly above floor so decal projects downward onto it
	decal.global_position = Vector3(pos.x, pos.y + 0.1, pos.z)
	get_tree().create_timer(STAIN_LIFETIME).timeout.connect(func():
		decal.global_position = Vector3(0, -100, 0)
	)

func spawn_cube(world_pos: Vector3, color: Color, impulse: Vector3) -> void:
	var rb := _cubes[_cursor]
	_cursor = (_cursor + 1) % CUBE_COUNT

	rb.freeze = false
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO
	rb.global_position = world_pos

	var mi := rb.get_child(0) as MeshInstance3D
	var mat := mi.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	# Grey voxels (low saturation) → dark maroon; others → bright red
	var tint_target := Color(0.35, 0.02, 0.02) if color.s < 0.2 else Color(1.0, 0.08, 0.04)
	mat.albedo_color = color.lerp(tint_target, 0.85)
	mi.set_surface_override_material(0, mat)

	rb.apply_central_impulse(impulse)

	get_tree().create_timer(CUBE_LIFETIME).timeout.connect(func():
		_place_stain(rb.global_position)
		rb.freeze = true
		rb.global_position = Vector3(0, -100, 0)
	)

func spawn_particles(world_pos: Vector3) -> void:
	_particles.global_position = world_pos
	_particles.restart()
