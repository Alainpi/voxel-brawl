@tool
extends EditorScript

func _run() -> void:
	# Dimensions are MV (X=width, Y=depth, Z=height).
	# VoxelLoader remaps MV(x,y,z) -> Godot(x,z,y), so Z must be the tall axis.
	var segments = [
		["torso",  8,  6, 12, Color(0.39, 0.47, 0.71)],
		["head",   6,  6,  6, Color(0.86, 0.71, 0.55)],
		["arm_l",  4,  4, 10, Color(0.39, 0.47, 0.71)],
		["arm_r",  4,  4, 10, Color(0.39, 0.47, 0.71)],
		["leg_l",  4,  4, 12, Color(0.24, 0.27, 0.39)],
		["leg_r",  4,  4, 12, Color(0.24, 0.27, 0.39)],
	]
	for seg in segments:
		_write_vox("res://assets/voxels/" + seg[0] + ".vox", seg[1], seg[2], seg[3], seg[4])
		print("Generated: ", seg[0], ".vox")

func _write_vox(path: String, sx: int, sy: int, sz: int, color: Color) -> void:
	var n = sx * sy * sz

	var voxels = PackedByteArray()
	for x in sx:
		for y in sy:
			for z in sz:
				voxels.append(x)
				voxels.append(y)
				voxels.append(z)
				voxels.append(1)

	var xyzi = PackedByteArray()
	xyzi.resize(4)
	xyzi.encode_s32(0, n)
	xyzi.append_array(voxels)

	var size_c = PackedByteArray()
	size_c.resize(12)
	size_c.encode_s32(0, sx)
	size_c.encode_s32(4, sy)
	size_c.encode_s32(8, sz)

	var rgba = PackedByteArray()
	rgba.resize(1024)
	rgba[0] = int(color.r * 255)
	rgba[1] = int(color.g * 255)
	rgba[2] = int(color.b * 255)
	rgba[3] = 255

	var children = _chunk("SIZE", size_c) + _chunk("XYZI", xyzi) + _chunk("RGBA", rgba)
	var main = _chunk_with_children("MAIN", PackedByteArray(), children)

	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("VOX ".to_ascii_buffer())
	f.store_32(150)
	f.store_buffer(main)

func _chunk(id: String, content: PackedByteArray) -> PackedByteArray:
	var out = PackedByteArray()
	out.append_array(id.to_ascii_buffer())
	var content_size = PackedByteArray()
	content_size.resize(4)
	content_size.encode_s32(0, content.size())
	out.append_array(content_size)
	var zero = PackedByteArray()
	zero.resize(4)
	out.append_array(zero)
	out.append_array(content)
	return out

func _chunk_with_children(id: String, content: PackedByteArray, children: PackedByteArray) -> PackedByteArray:
	var out = PackedByteArray()
	out.append_array(id.to_ascii_buffer())
	var content_size = PackedByteArray()
	content_size.resize(4)
	content_size.encode_s32(0, content.size())
	out.append_array(content_size)
	var children_size = PackedByteArray()
	children_size.resize(4)
	children_size.encode_s32(0, children.size())
	out.append_array(children_size)
	out.append_array(content)
	out.append_array(children)
	return out
