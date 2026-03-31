# scripts/bullet_tracer.gd
# Self-contained streak tracer. Call BulletTracer.spawn() — node adds itself,
# fades out, and queue_frees. No pooling needed (short-lived, low frequency).
class_name BulletTracer
extends Node3D

const TRACER_THICKNESS := 0.03  # World-space diameter of the streak
const TRACER_FADE_TIME  := 0.12  # Seconds from full opacity to zero

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

# Spawns a tracer from `from` to `to` with the given color.
# `parent` should be get_tree().root so the tracer outlives the weapon.
static func spawn(from: Vector3, to: Vector3, color: Color, parent: Node) -> void:
	if from.is_equal_approx(to):
		return
	var dir := (to - from).normalized()
	var dist := from.distance_to(to)
	var mid := (from + to) * 0.5

	# Build a basis where the local X axis points along dir.
	var up := Vector3.UP if abs(dir.y) < 0.9 else Vector3.RIGHT
	var side := dir.cross(up).normalized()
	up = side.cross(dir).normalized()
	# Scale the X column by dist so the unit BoxMesh spans exactly from→to.
	var basis := Basis(dir * dist, up, side)

	var tracer := BulletTracer.new()
	parent.add_child(tracer)  # triggers _ready(), which creates _mat and mesh
	tracer.global_transform = Transform3D(basis, mid)
	tracer._mat.albedo_color = color

	var end_color := Color(color.r, color.g, color.b, 0.0)
	var tween := tracer.create_tween()
	tween.tween_property(tracer._mat, "albedo_color", end_color, TRACER_FADE_TIME)
	tween.tween_callback(tracer.queue_free)
