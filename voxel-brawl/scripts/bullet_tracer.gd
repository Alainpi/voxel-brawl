# scripts/bullet_tracer.gd
# Self-contained streak tracer. Call BulletTracer.spawn() — node adds itself,
# fades out, and queue_frees. No pooling needed (short-lived, low frequency).
class_name BulletTracer
extends Node3D

const TRACER_THICKNESS := 0.03   # World-space diameter of the streak
const TRACER_FADE_TIME  := 0.10  # Seconds to fade after reaching target
const TRAIL_LENGTH      := 1.5   # World-space length of the moving streak
const TRAVEL_SPEED      := 80.0  # Simulated bullet speed for trail animation (m/s)

var _mat := StandardMaterial3D.new()

func _ready() -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	# X=1.0 unit so scaling global_transform.basis.x by distance stretches it correctly.
	box.size = Vector3(1.0, TRACER_THICKNESS, TRACER_THICKNESS)
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.flags_transparent = true
	_mat.albedo_color = Color.WHITE  # overridden in spawn()
	mesh_instance.mesh = box
	mesh_instance.material_override = _mat
	add_child(mesh_instance)

# Spawns a short tracer streak that travels from `from` to `to`, then fades.
# `parent` should be get_tree().root so the tracer outlives the weapon.
static func spawn(from: Vector3, to: Vector3, color: Color, parent: Node) -> void:
	if from.is_equal_approx(to):
		return
	var dir := (to - from).normalized()
	var dist := from.distance_to(to)
	var trail_len := minf(TRAIL_LENGTH, dist)
	var travel_time := clampf(dist / TRAVEL_SPEED, 0.04, 0.12)

	# Build a basis where the local X axis points along dir, scaled by trail_len.
	var up := Vector3.UP if abs(dir.y) < 0.9 else Vector3.RIGHT
	var side := dir.cross(up).normalized()
	up = side.cross(dir).normalized()
	var basis := Basis(dir * trail_len, up, side)

	# Start: front of streak at `from`; end: front of streak at `to`.
	# (Center is half a trail_len behind the front.)
	var start_pos := from - dir * (trail_len * 0.5)
	var end_pos   := to   - dir * (trail_len * 0.5)

	var tracer := BulletTracer.new()
	parent.add_child(tracer)  # triggers _ready(), which creates _mat and mesh
	tracer.global_transform = Transform3D(basis, start_pos)
	tracer._mat.albedo_color = color

	var end_color := Color(color.r, color.g, color.b, 0.0)
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "global_position", end_pos, travel_time)
	tween.tween_property(tracer._mat, "albedo_color", end_color, TRACER_FADE_TIME)
	tween.tween_callback(tracer.queue_free)
