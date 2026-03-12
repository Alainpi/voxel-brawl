# scripts/debris_pool.gd
extends Node

# Singleton reference — VoxelSegment accesses via get_node_or_null("/root/DebrisPool")
static var instance: DebrisPool = null

const CUBE_COUNT := 80
const CUBE_SIZE := 0.08
const CUBE_LIFETIME := 3.0

var _cubes: Array[RigidBody3D] = []
var _cursor: int = 0
var _particles: GPUParticles3D

func _ready() -> void:
	instance = self
	_spawn_cube_pool()
	_setup_particles()

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

func spawn_cube(world_pos: Vector3, color: Color, impulse: Vector3) -> void:
	var rb := _cubes[_cursor]
	_cursor = (_cursor + 1) % CUBE_COUNT

	rb.freeze = false
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO
	rb.global_position = world_pos

	var mi := rb.get_child(0) as MeshInstance3D
	var mat := mi.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	mat.albedo_color = color
	mi.set_surface_override_material(0, mat)

	rb.apply_central_impulse(impulse)

	get_tree().create_timer(CUBE_LIFETIME).timeout.connect(func():
		rb.freeze = true
		rb.global_position = Vector3(0, -100, 0)
	)

func spawn_particles(world_pos: Vector3) -> void:
	_particles.global_position = world_pos
	_particles.restart()
