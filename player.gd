extends CharacterBody3D

const SPEED = 5.0
const GRAVITY = 9.8

func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO
	direction.x = Input.get_axis("ui_left", "ui_right")
	direction.z = Input.get_axis("ui_up", "ui_down")

	if direction.length() > 0:
		direction = direction.normalized()

	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	move_and_slide()
