# scripts/player.gd
class_name Player
extends CharacterBody3D

const SPEED := 5.0
const SPRINT_MULT := 1.6
const JUMP_FORCE := 6.0
const GRAVITY := 9.8
const MOUSE_SENS := 0.002

@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var anim_player: AnimationPlayer = $PlayerModel.find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var weapon_holder: Node3D = $CameraPivot/Camera3D/WeaponHolder
@onready var fists: WeaponMelee = $CameraPivot/Camera3D/WeaponHolder/Fists
@onready var revolver: WeaponRanged = $CameraPivot/Camera3D/WeaponHolder/Revolver

var _current_weapon: Node = null
var _cam_shake_time := 0.0
var _cam_shake_intensity := 0.0
var _bob_time := 0.0
var _cam_base_y := 0.0

func _ready() -> void:
	# Multiplayer guard — always true for MVP, used in Phase 3
	if not is_multiplayer_authority():
		set_process_input(false)
		set_physics_process(false)
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_cam_base_y = camera.position.y
	revolver.ammo_changed.connect(_on_ammo_changed)
	_equip_weapon.call_deferred(fists)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera_pivot.rotate_x(-event.relative.y * MOUSE_SENS)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.4, 1.4)

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if event.is_action_pressed("switch_weapon_1"):
		_equip_weapon(fists)
	if event.is_action_pressed("switch_weapon_2"):
		_equip_weapon(revolver)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_equip_weapon(revolver)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_equip_weapon(fists)

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_FORCE

	# Horizontal movement
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):  dir -= transform.basis.z
	if Input.is_action_pressed("move_back"):     dir += transform.basis.z
	if Input.is_action_pressed("move_left"):     dir -= transform.basis.x
	if Input.is_action_pressed("move_right"):    dir += transform.basis.x
	dir = dir.normalized()

	var speed := SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	move_and_slide()
	_update_animation(dir, delta)
	_update_camera_effects(dir, delta)

func _update_animation(dir: Vector3, _delta: float) -> void:
	var speed_h := Vector2(velocity.x, velocity.z).length()
	if speed_h > 0.1:
		anim_player.play("walk")
	else:
		anim_player.play("idle")

func _update_camera_effects(dir: Vector3, delta: float) -> void:
	# Walk bob
	var speed_h := Vector2(velocity.x, velocity.z).length()
	if speed_h > 0.1:
		_bob_time += delta * speed_h * 1.5
		camera.position.y = _cam_base_y + sin(_bob_time * 2.0) * 0.02
	else:
		_bob_time = 0.0
		camera.position.y = lerp(camera.position.y, _cam_base_y, delta * 10.0)

	# Hit shake
	if _cam_shake_time > 0:
		_cam_shake_time -= delta
		var shake := randf_range(-_cam_shake_intensity, _cam_shake_intensity)
		camera.rotation.z = shake
	else:
		camera.rotation.z = lerp(camera.rotation.z, 0.0, delta * 20.0)

func _equip_weapon(weapon: Node) -> void:
	fists.visible = (weapon == fists)
	revolver.visible = (weapon == revolver)
	_current_weapon = weapon
	var hud := get_node_or_null("/root/test_scene/hud")
	if hud:
		hud.set_weapon_name("Fists" if weapon == fists else "Revolver")

func _on_ammo_changed(current: int, max_ammo: int) -> void:
	var hud := get_node_or_null("/root/test_scene/hud")
	if hud:
		hud.update_ammo(current, max_ammo)

func trigger_hit_shake() -> void:
	_cam_shake_time = 0.1
	_cam_shake_intensity = 0.03

func play_attack_anim(anim_name: String) -> void:
	var mapped := anim_name
	if anim_name == "shoot":
		mapped = "holding-right-shoot"
	elif anim_name == "punch":
		mapped = "attack-melee-right"
	anim_player.stop()
	anim_player.play(mapped)
