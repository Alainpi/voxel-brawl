# scripts/voxel_segment.gd
class_name VoxelSegment
extends Node3D

const VOXEL_SIZE := 0.1  # Each voxel cube is 0.1m per side

# Voxel data: position -> color
var voxel_data: Dictionary = {}
var total_voxel_count: int = 0
var current_voxel_count: int = 0

# Detachment config (set by dummy.gd)
var detach_threshold: float = 0.30
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

# Called by DamageManager. hit_pos is in this node's LOCAL space.
func take_hit(local_hit_pos: Vector3, radius_voxels: float, _damage: float) -> void:
	var radius_world := radius_voxels * VOXEL_SIZE
	var to_remove: Array[Vector3i] = []

	for vox_pos: Vector3i in voxel_data:
		var world_vox := Vector3(vox_pos) * VOXEL_SIZE
		if world_vox.distance_to(local_hit_pos) <= radius_world:
			to_remove.append(vox_pos)

	if to_remove.is_empty():
		return

	_spawn_debris(to_remove, local_hit_pos)

	for pos in to_remove:
		voxel_data.erase(pos)
	current_voxel_count = voxel_data.size()

	if not _pending_rebuild:
		_pending_rebuild = true
		call_deferred("rebuild_mesh")

	if not is_detached and current_voxel_count > 0:
		var ratio := float(current_voxel_count) / float(total_voxel_count)
		if ratio < detach_threshold:
			detach()

func _spawn_debris(removed: Array[Vector3i], hit_origin: Vector3) -> void:
	var debris_pool = get_node_or_null("/root/DebrisPool")
	if not is_instance_valid(debris_pool):
		return  # DebrisPool not yet in scene — debris skipped until Task 8

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

	var world_xform := global_transform
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	global_transform = world_xform

	var rb := RigidBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	rb.add_child(col)
	add_child(rb)

	var impulse := Vector3(randf_range(-3,3), randf_range(2,5), randf_range(-3,3))
	rb.apply_central_impulse(impulse)

	emit_signal("detached", self)
