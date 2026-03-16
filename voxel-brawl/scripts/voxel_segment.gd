# scripts/voxel_segment.gd
class_name VoxelSegment
extends Node3D

const VOXEL_SIZE := 0.1  # Each voxel cube is 0.1m per side
const DAMAGE_COLOR := Color(0.12, 0.04, 0.04)  # charred dark red

# Voxel data: position -> color
var voxel_data: Dictionary = {}
var total_voxel_count: int = 0
var current_voxel_count: int = 0

# Detachment config (set by dummy.gd)
var detach_threshold: float = 0.60
var is_detached: bool = false
var bone_attachment: String = ""  # Phase 1: name of skeleton bone to attach to

# Internal nodes
var mesh_instance: MeshInstance3D
var _pending_rebuild: bool = false

# Signals
signal detached(segment)

# Shared material — vertex colors, unshaded
static var _shared_material: StandardMaterial3D = null

static func _get_material() -> StandardMaterial3D:
	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.vertex_color_use_as_albedo = true
		_shared_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _shared_material

func _ready() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.material_override = _get_material()
	add_child(mesh_instance)

func load_from_vox(path: String) -> void:
	voxel_data = VoxelLoader.load_vox(path)
	total_voxel_count = voxel_data.size()
	current_voxel_count = total_voxel_count
	rebuild_mesh()

func rebuild_mesh() -> void:
	_pending_rebuild = false
	if voxel_data.is_empty():
		mesh_instance.mesh = null
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for vox_pos: Vector3i in voxel_data:
		var color: Color = voxel_data[vox_pos]
		_emit_voxel_faces(st, vox_pos, color)

	mesh_instance.mesh = st.commit()

func _emit_voxel_faces(st: SurfaceTool, p: Vector3i, color: Color) -> void:
	const DIRS := [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	const S := VOXEL_SIZE

	for dir in DIRS:
		if voxel_data.has(p + dir):
			continue  # face hidden by neighbor

		st.set_color(color)
		st.set_normal(Vector3(dir))

		var verts := _face_vertices(p, dir, S)
		st.add_vertex(verts[0])
		st.add_vertex(verts[1])
		st.add_vertex(verts[2])
		st.add_vertex(verts[0])
		st.add_vertex(verts[2])
		st.add_vertex(verts[3])

func _face_vertices(p: Vector3i, dir: Vector3i, s: float) -> Array:
	var x := p.x * s
	var y := p.y * s
	var z := p.z * s

	match dir:
		Vector3i(1, 0, 0):
			return [Vector3(x+s,y,z+s), Vector3(x+s,y+s,z+s), Vector3(x+s,y+s,z), Vector3(x+s,y,z)]
		Vector3i(-1, 0, 0):
			return [Vector3(x,y,z), Vector3(x,y+s,z), Vector3(x,y+s,z+s), Vector3(x,y,z+s)]
		Vector3i(0, 1, 0):
			return [Vector3(x,y+s,z), Vector3(x+s,y+s,z), Vector3(x+s,y+s,z+s), Vector3(x,y+s,z+s)]
		Vector3i(0, -1, 0):
			return [Vector3(x+s,y,z), Vector3(x,y,z), Vector3(x,y,z+s), Vector3(x+s,y,z+s)]
		Vector3i(0, 0, 1):
			return [Vector3(x+s,y,z+s), Vector3(x+s,y+s,z+s), Vector3(x,y+s,z+s), Vector3(x,y,z+s)]
		Vector3i(0, 0, -1):
			return [Vector3(x,y,z), Vector3(x,y+s,z), Vector3(x+s,y+s,z), Vector3(x+s,y,z)]
	return []

# Amanatides & Woo DDA raycast through voxel grid.
# local_origin and local_dir must be in this node's local space.
# Returns {hit: bool, voxel: Vector3i} — voxel is the first occupied cell hit.
func dda_raycast(local_origin: Vector3, local_dir: Vector3, max_steps: int = 200) -> Dictionary:
	if local_dir.is_zero_approx():
		return {"hit": false, "voxel": Vector3i.ZERO}

	var inv := 1.0 / VOXEL_SIZE
	var gx := int(floor(local_origin.x * inv))
	var gy := int(floor(local_origin.y * inv))
	var gz := int(floor(local_origin.z * inv))

	var step_x := 1 if local_dir.x > 0.0 else -1
	var step_y := 1 if local_dir.y > 0.0 else -1
	var step_z := 1 if local_dir.z > 0.0 else -1

	var td_x: float = abs(VOXEL_SIZE / local_dir.x) if local_dir.x != 0.0 else INF
	var td_y: float = abs(VOXEL_SIZE / local_dir.y) if local_dir.y != 0.0 else INF
	var td_z: float = abs(VOXEL_SIZE / local_dir.z) if local_dir.z != 0.0 else INF

	var tm_x: float = ((gx + 1) * VOXEL_SIZE - local_origin.x) / local_dir.x if local_dir.x > 0.0 \
			else (gx * VOXEL_SIZE - local_origin.x) / local_dir.x if local_dir.x < 0.0 else INF
	var tm_y: float = ((gy + 1) * VOXEL_SIZE - local_origin.y) / local_dir.y if local_dir.y > 0.0 \
			else (gy * VOXEL_SIZE - local_origin.y) / local_dir.y if local_dir.y < 0.0 else INF
	var tm_z: float = ((gz + 1) * VOXEL_SIZE - local_origin.z) / local_dir.z if local_dir.z > 0.0 \
			else (gz * VOXEL_SIZE - local_origin.z) / local_dir.z if local_dir.z < 0.0 else INF

	for _i in max_steps:
		if voxel_data.has(Vector3i(gx, gy, gz)):
			return {"hit": true, "voxel": Vector3i(gx, gy, gz)}
		if tm_x < tm_y:
			if tm_x < tm_z:
				gx += step_x;  tm_x += td_x
			else:
				gz += step_z;  tm_z += td_z
		else:
			if tm_y < tm_z:
				gy += step_y;  tm_y += td_y
			else:
				gz += step_z;  tm_z += td_z

	return {"hit": false, "voxel": Vector3i.ZERO}

# Called by DamageManager. center_local must be in this node's local space.
func take_hit(center_local: Vector3, radius_voxels: float, _damage: float) -> void:
	var radius_world := radius_voxels * VOXEL_SIZE
	var tint_world := radius_world * 2.0
	var to_remove: Array[Vector3i] = []
	var to_tint: Array[Vector3i] = []

	for vox_pos: Vector3i in voxel_data:
		var vc := (Vector3(vox_pos) + Vector3(0.5, 0.5, 0.5)) * VOXEL_SIZE
		var dist := vc.distance_to(center_local)
		if dist <= radius_world:
			to_remove.append(vox_pos)
		elif dist <= tint_world:
			to_tint.append(vox_pos)

	if to_remove.is_empty() and to_tint.is_empty():
		return

	# Apply tint after the loop — modifying voxel_data during iteration breaks it
	for pos in to_tint:
		voxel_data[pos] = voxel_data[pos].lerp(DAMAGE_COLOR, 0.5)

	if not to_remove.is_empty():
		_spawn_debris(to_remove, center_local)
		for pos in to_remove:
			voxel_data.erase(pos)
		current_voxel_count = voxel_data.size()
		if not is_detached and total_voxel_count > 0:
			var ratio := float(current_voxel_count) / float(total_voxel_count)
			if ratio < detach_threshold:
				detach()

	if not _pending_rebuild:
		_pending_rebuild = true
		call_deferred("rebuild_mesh")

func _spawn_debris(removed: Array[Vector3i], hit_origin: Vector3) -> void:
	var debris_pool := DebrisPool.instance
	if not is_instance_valid(debris_pool):
		return

	var sorted := removed.duplicate()
	sorted.sort_custom(func(a, b):
		var da = (Vector3(a) * VOXEL_SIZE).distance_to(hit_origin)
		var db = (Vector3(b) * VOXEL_SIZE).distance_to(hit_origin)
		return da < db
	)

	var physics_count := mini(8, sorted.size())
	for i in physics_count:
		var world_pos := global_position + Vector3(sorted[i]) * VOXEL_SIZE
		var impulse := (world_pos - global_position - hit_origin).normalized() * randf_range(2.0, 5.0)
		impulse.y += randf_range(1.0, 3.0)
		debris_pool.spawn_cube(world_pos, voxel_data.get(sorted[i], Color.WHITE), impulse)

	debris_pool.spawn_particles(global_position + hit_origin)

func detach() -> void:
	if is_detached:
		return
	is_detached = true

	emit_signal("detached", self)

	# Build a RigidBody3D to carry the mesh so physics actually moves it
	var rb := RigidBody3D.new()
	rb.add_to_group("detached_limb")

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh_instance.get_aabb().size if mesh_instance.mesh else Vector3(0.3, 0.6, 0.3)
	col.shape = box
	rb.add_child(col)

	# Transfer mesh ownership into the rigidbody
	remove_child(mesh_instance)
	mesh_instance.position = Vector3.ZERO
	mesh_instance.rotation = Vector3.ZERO
	rb.add_child(mesh_instance)

	get_tree().root.add_child(rb)
	rb.global_transform = global_transform

	rb.apply_central_impulse(Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3)))
	rb.apply_torque_impulse(Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)))
