# scripts/voxel_segment.gd
class_name VoxelSegment
extends Node3D

const VOXEL_SIZE := 0.1
const DAMAGE_COLOR := Color(0.12, 0.04, 0.04)
const BONE_COLOR := Color(0.92, 0.88, 0.78)
const BONE_HP := 3.0          # interior voxels need this many hits to destroy
const CHUNK_MIN_VOXELS := 8   # clusters smaller than this become debris particles

const DIRS6 := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

# Voxel data: position -> color
var voxel_data: Dictionary = {}
var voxel_hp: Dictionary = {}      # position -> float HP
var total_voxel_count: int = 0
var current_voxel_count: int = 0

# root_axis: direction toward the attachment end of this segment (in vox local space).
# The outermost voxel row along this axis is the "root" — destroy it to sever the limb.
# Vector3i.ZERO means no detachment (e.g. torso).
var root_axis: Vector3i = Vector3i.ZERO

var is_detached: bool = false
var is_broken: bool = false
var bone_attachment: String = ""
var _root_voxels_cached: Array[Vector3i] = []

var mesh_instance: MeshInstance3D
var _pending_rebuild: bool = false

signal detached(segment)

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
	_init_voxel_hp()
	rebuild_mesh()

# Mark interior voxels as bone (higher HP, bone color).
func _init_voxel_hp() -> void:
	voxel_hp.clear()
	for pos: Vector3i in voxel_data:
		var interior := true
		for d in DIRS6:
			if not voxel_data.has(pos + d):
				interior = false
				break
		if interior:
			voxel_hp[pos] = BONE_HP
			voxel_data[pos] = BONE_COLOR
		else:
			voxel_hp[pos] = 1.0
	_cache_root_voxels()

func _cache_root_voxels() -> void:
	_root_voxels_cached.clear()
	if root_axis == Vector3i.ZERO or voxel_data.is_empty():
		return

	# Prefer world-space proximity: find the torso sibling and project voxels
	# toward it. This is rotation/orientation-agnostic.
	var ref_pos := _get_attachment_ref_pos()
	if ref_pos != Vector3.INF:
		var local_ref := to_local(ref_pos)
		var dir := local_ref.normalized()
		if not dir.is_zero_approx():
			var best := -INF
			for pos: Vector3i in voxel_data:
				var proj: float = (Vector3(pos) * VOXEL_SIZE).dot(dir)
				if proj > best:
					best = proj
			for pos: Vector3i in voxel_data:
				var proj: float = (Vector3(pos) * VOXEL_SIZE).dot(dir)
				if proj >= best - VOXEL_SIZE * 0.5:
					_root_voxels_cached.append(pos)
			return

	# Fallback: use root_axis direction — single outermost row only
	var best := -999999
	for pos: Vector3i in voxel_data:
		var coord := pos.x * root_axis.x + pos.y * root_axis.y + pos.z * root_axis.z
		if coord > best:
			best = coord
	for pos: Vector3i in voxel_data:
		var coord := pos.x * root_axis.x + pos.y * root_axis.y + pos.z * root_axis.z
		if coord == best:
			_root_voxels_cached.append(pos)

func _get_attachment_ref_pos() -> Vector3:
	if not is_inside_tree():
		return Vector3.INF
	# Find the CharacterBody3D ancestor
	var body: Node = get_parent()
	while body != null and not body is CharacterBody3D:
		body = body.get_parent()
	if body == null:
		return Vector3.INF
	# Use the torso segment's position as the attachment reference
	var torso: Node = body.find_child("VoxelSegment_torso_bottom", true, false)
	if torso is Node3D:
		return (torso as Node3D).global_position
	return (body as Node3D).global_position

func rebuild_mesh() -> void:
	_pending_rebuild = false
	if voxel_data.is_empty():
		mesh_instance.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vox_pos: Vector3i in voxel_data:
		_emit_voxel_faces(st, vox_pos, voxel_data[vox_pos], voxel_data)
	mesh_instance.mesh = st.commit()

func _emit_voxel_faces(st: SurfaceTool, p: Vector3i, color: Color, neighbor_set: Dictionary) -> void:
	const S := VOXEL_SIZE
	for dir in DIRS6:
		if neighbor_set.has(p + dir):
			continue
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

# Called by DamageManager. center_local is in this node's local space.
func take_hit(center_local: Vector3, radius_voxels: float, damage: float) -> void:
	var radius_world := radius_voxels * VOXEL_SIZE
	var tint_world := radius_world * 2.0
	var actually_removed: Array[Vector3i] = []
	var removed_colors: Dictionary = {}
	var to_tint: Array[Vector3i] = []

	for vox_pos: Vector3i in voxel_data:
		var vc := (Vector3(vox_pos) + Vector3(0.5, 0.5, 0.5)) * VOXEL_SIZE
		var dist := vc.distance_to(center_local)
		if dist <= radius_world:
			voxel_hp[vox_pos] = voxel_hp.get(vox_pos, 1.0) - damage
			if voxel_hp[vox_pos] <= 0.0:
				removed_colors[vox_pos] = voxel_data[vox_pos]
				actually_removed.append(vox_pos)
		elif dist <= tint_world:
			to_tint.append(vox_pos)

	if actually_removed.is_empty() and to_tint.is_empty():
		return

	for pos in to_tint:
		voxel_data[pos] = voxel_data[pos].lerp(DAMAGE_COLOR, 0.5)

	if not actually_removed.is_empty():
		_spawn_debris_from(actually_removed, removed_colors, center_local)
		for pos in actually_removed:
			voxel_data.erase(pos)
			voxel_hp.erase(pos)
		current_voxel_count = voxel_data.size()

		if not is_detached:
			_check_connectivity()

	if not _pending_rebuild:
		_pending_rebuild = true
		call_deferred("rebuild_mesh")

# --- Connectivity ---

func _get_root_voxels() -> Array[Vector3i]:
	if root_axis == Vector3i.ZERO:
		return []
	# Root region is fixed at load time — only return roots that still exist.
	# When all original attachment voxels are gone, the segment detaches.
	var alive: Array[Vector3i] = []
	for pos in _root_voxels_cached:
		if voxel_data.has(pos):
			alive.append(pos)
	return alive

func _flood_fill_connected(roots: Array[Vector3i]) -> Dictionary:
	var connected := {}
	var queue: Array[Vector3i] = []
	for r in roots:
		if voxel_data.has(r) and not connected.has(r):
			connected[r] = true
			queue.append(r)
	var i := 0
	while i < queue.size():
		var cur := queue[i]
		i += 1
		for d in DIRS6:
			var nb: Vector3i = cur + d
			if voxel_data.has(nb) and not connected.has(nb):
				connected[nb] = true
				queue.append(nb)
	return connected

func _find_clusters(voxels: Array[Vector3i]) -> Array:
	var remaining := {}
	for v in voxels:
		remaining[v] = true
	var clusters: Array = []
	while not remaining.is_empty():
		var cluster: Array[Vector3i] = []
		var seed: Vector3i = remaining.keys()[0]
		var queue: Array[Vector3i] = [seed]
		remaining.erase(seed)
		var i := 0
		while i < queue.size():
			cluster.append(queue[i])
			for d in DIRS6:
				var nb: Vector3i = queue[i] + d
				if remaining.has(nb):
					remaining.erase(nb)
					queue.append(nb)
			i += 1
		clusters.append(cluster)
	return clusters

func _check_connectivity() -> void:
	if root_axis == Vector3i.ZERO:
		return  # torso — never detaches by connectivity

	var roots := _get_root_voxels()
	# Detach when ≤30% of the original attachment region survives
	var root_ratio := float(roots.size()) / maxf(1.0, float(_root_voxels_cached.size()))
	if root_ratio <= 0.3:
		rebuild_mesh()
		detach()
		return

	var connected := _flood_fill_connected(roots)

	var disconnected: Array[Vector3i] = []
	for pos: Vector3i in voxel_data:
		if not connected.has(pos):
			disconnected.append(pos)

	if disconnected.is_empty():
		return

	# Collect colors before erasing
	var dis_colors: Dictionary = {}
	for pos in disconnected:
		dis_colors[pos] = voxel_data.get(pos, Color.WHITE)

	for pos in disconnected:
		voxel_data.erase(pos)
		voxel_hp.erase(pos)
	current_voxel_count = voxel_data.size()

	var clusters := _find_clusters(disconnected)
	for cluster in clusters:
		if cluster.size() >= CHUNK_MIN_VOXELS:
			_spawn_cluster_chunk(cluster, dis_colors)
		else:
			_spawn_small_debris(cluster, dis_colors)

# --- Spawning ---

func _spawn_cluster_chunk(cluster: Array[Vector3i], colors: Dictionary) -> void:
	var cluster_set := {}
	for pos in cluster:
		cluster_set[pos] = true

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pos: Vector3i in cluster:
		_emit_voxel_faces(st, pos, colors.get(pos, Color.WHITE), cluster_set)
	var mesh := st.commit()
	if mesh == null:
		return

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _get_material()

	var rb := RigidBody3D.new()
	rb.add_to_group("detached_limb")

	var aabb := mesh.get_aabb()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size.clamp(Vector3(0.05, 0.05, 0.05), Vector3(10.0, 10.0, 10.0))
	col.position = aabb.get_center()
	col.shape = box
	rb.add_child(col)
	rb.add_child(mi)

	get_tree().root.add_child(rb)
	rb.global_transform = global_transform
	rb.apply_central_impulse(Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3)))
	rb.apply_torque_impulse(Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)))

func _spawn_small_debris(cluster: Array[Vector3i], colors: Dictionary) -> void:
	var debris_pool := DebrisPool.instance
	if not is_instance_valid(debris_pool):
		return
	var center := _cluster_center_local(cluster)
	for pos in cluster:
		var world_pos := global_transform * (Vector3(pos) * VOXEL_SIZE)
		var impulse := (world_pos - global_position - to_global(center) + global_position).normalized() * randf_range(2.0, 5.0)
		impulse.y += randf_range(1.0, 3.0)
		debris_pool.spawn_cube(world_pos, colors.get(pos, Color.WHITE), impulse)
	debris_pool.spawn_particles(to_global(center))

func _spawn_debris_from(removed: Array[Vector3i], colors: Dictionary, hit_origin: Vector3) -> void:
	var debris_pool := DebrisPool.instance
	if not is_instance_valid(debris_pool):
		return
	var sorted := removed.duplicate()
	sorted.sort_custom(func(a, b):
		return (Vector3(a) * VOXEL_SIZE).distance_to(hit_origin) < (Vector3(b) * VOXEL_SIZE).distance_to(hit_origin)
	)
	var hit_world := to_global(hit_origin)
	var physics_count := mini(8, sorted.size())
	for i in physics_count:
		var world_pos := to_global(Vector3(sorted[i]) * VOXEL_SIZE)
		var impulse := (world_pos - hit_world).normalized() * randf_range(2.0, 5.0)
		impulse.y += randf_range(1.0, 3.0)
		debris_pool.spawn_cube(world_pos, colors.get(sorted[i], Color.WHITE), impulse)
	debris_pool.spawn_particles(hit_world)

func _cluster_center_local(cluster: Array[Vector3i]) -> Vector3:
	var sum := Vector3.ZERO
	for pos in cluster:
		sum += Vector3(pos) * VOXEL_SIZE
	return sum / cluster.size()

func detach() -> void:
	if is_detached:
		return
	is_detached = true

	for child in get_children():
		if child is Area3D:
			child.collision_layer = 0

	emit_signal("detached", self)

	# LimbSystem handles ragdoll when present — skip standalone spawn
	if get_meta("limb_system", null) != null:
		return

	if voxel_data.is_empty():
		return  # nothing left to launch

	var rb := RigidBody3D.new()
	rb.add_to_group("detached_limb")

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh_instance.get_aabb().size if mesh_instance.mesh else Vector3(0.3, 0.6, 0.3)
	col.shape = box
	rb.add_child(col)

	remove_child(mesh_instance)
	mesh_instance.position = Vector3.ZERO
	mesh_instance.rotation = Vector3.ZERO
	rb.add_child(mesh_instance)

	# Replace with a fresh instance so rebuild_mesh() doesn't crash if called later
	mesh_instance = MeshInstance3D.new()
	mesh_instance.material_override = _get_material()
	add_child(mesh_instance)

	get_tree().root.add_child(rb)
	rb.global_transform = global_transform
	rb.apply_central_impulse(Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3)))
	rb.apply_torque_impulse(Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)))
