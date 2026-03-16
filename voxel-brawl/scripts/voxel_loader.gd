# scripts/voxel_loader.gd
class_name VoxelLoader

# MagicaVoxel .vox format parser.
# Returns a Dictionary mapping Vector3i positions to Color values.
# Coordinate remap: MagicaVoxel is Z-up, Godot is Y-up.
# MV (x, y, z) -> Godot Vector3i(x, z, y)

# Default palette fallback — used when no RGBA chunk is present in the file.
static var DEFAULT_PALETTE: Array[Color] = []

static func _build_default_palette() -> void:
	if DEFAULT_PALETTE.size() > 0:
		return
	DEFAULT_PALETTE.resize(256)
	for i in 256:
		var v = float(i) / 255.0
		DEFAULT_PALETTE[i] = Color(v, v, v, 1.0)

static func load_vox(path: String) -> Dictionary:
	_build_default_palette()

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("VoxelLoader: cannot open file: " + path)
		return {}

	# Validate header
	var magic = file.get_buffer(4).get_string_from_ascii()
	if magic != "VOX ":
		push_error("VoxelLoader: not a .vox file: " + path)
		return {}

	var _version = file.get_32()  # 150 or 200, not needed

	# Skip MAIN chunk header (12 bytes: id + chunk_bytes + children_bytes)
	file.get_buffer(12)

	var raw_voxels: Dictionary = {}  # Vector3i -> int (color index)
	var palette: Array[Color] = DEFAULT_PALETTE.duplicate()

	while file.get_position() < file.get_length():
		var chunk_id = file.get_buffer(4).get_string_from_ascii()
		var chunk_bytes = file.get_32()
		var _child_bytes = file.get_32()

		match chunk_id:
			"SIZE":
				# Consume dimensions (not needed for voxel dict)
				file.get_32()  # x
				file.get_32()  # y
				file.get_32()  # z
			"XYZI":
				var num_voxels = file.get_32()
				for _i in num_voxels:
					var vx = file.get_8()
					var vy = file.get_8()
					var vz = file.get_8()
					var ci = file.get_8()
					# Remap: MV Z-up -> Godot Y-up
					raw_voxels[Vector3i(vx, vz, vy)] = ci
			"RGBA":
				palette.clear()
				palette.append(Color.BLACK)  # index 0 is unused in .vox spec
				for _i in 255:
					var r = file.get_8() / 255.0
					var g = file.get_8() / 255.0
					var b = file.get_8() / 255.0
					var _a = file.get_8()  # always 255 in MagicaVoxel
					palette.append(Color(r, g, b, 1.0))
			_:
				# Unknown chunk — skip
				if chunk_bytes > 0:
					file.get_buffer(chunk_bytes)

	# Resolve color indices to Color values
	var result: Dictionary = {}
	for pos in raw_voxels:
		var ci: int = raw_voxels[pos]
		result[pos] = palette[ci] if ci < palette.size() else Color.WHITE

	return result
