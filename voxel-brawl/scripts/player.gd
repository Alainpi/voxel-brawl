# scripts/player.gd
class_name Player
extends CharacterBody3D

const SPEED := 5.0
const SPRINT_MULT := 1.6
const JUMP_FORCE := 6.0
const GRAVITY := 9.8

# Top-down camera: height=14, z-offset=8 → atan2(14,8) ≈ 60° down from horizontal
const CAM_HEIGHT := 11
const CAM_Z_OFFSET := 10
const CAM_FOLLOW_SPEED := 8.0  # Slight lag for juice
const CAM_ROT_SENS := 0.005    # Radians per pixel for middle-mouse orbit
const CAM_ROT_FRICTION := 3.0  	# Damping after release — lower slides longer
const CAM_DEFAULT_YAW := 90.0  # Degrees — starting Y rotation of camera
const CAM_PITCH := -45.0       # Degrees — X tilt. More negative = steeper/more top-down
const CRAWL_SPEED := 1.2

@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var anim_player: AnimationPlayer = $PlayerModel.find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var weapon_holder: Node3D = $CameraPivot/Camera3D/WeaponHolder
@onready var stance_manager: StanceManager = $StanceManager

# [vox_path, bone_name, position_offset, attach_rot_x, attach_rot_z, scale, root_axis, seg_rot_x, seg_rot_y]
# attach_rot: corrects MagicaVoxel coordinate system on the BoneAttachment3D
# seg_rot: additional visual correction on the VoxelSegment itself — does not affect animations or weapon holder
# Offsets are relative to each bone origin
const PLAYER_SEGMENT_CONFIG := {
	"torso_bottom": ["res://assets/voxels/torso_bottom.vox", "torso_bottom", Vector3(-1.0,  0.0, -0.4), -90, 0, Vector3(1,1,1),  Vector3i.ZERO,    0,   0],
	"torso_top":    ["res://assets/voxels/torso_top.vox",    "torso_top",    Vector3(-1.0,  0.0, -0.4), -90, 0, Vector3(1,1,1),  Vector3i(0,-1,0), 0,   0],
	"head_bottom":  ["res://assets/voxels/head_bottom.vox",  "head_bottom",  Vector3(-0.9,  0.0,  0.8), -90, 0, Vector3(1,1,-1), Vector3i(0,-1,0), 0,   0],
	"head_top":     ["res://assets/voxels/head_top.vox",     "head_top",     Vector3(-0.9,  0.0,  0.8), -90, 0, Vector3(1,1,-1), Vector3i(0,-1,0), 0,   0],
	"arm_r_upper":  ["res://assets/voxels/arm_r_upper.vox",  "arm_r_upper",  Vector3(-0.44, 1.65, 0.3), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  180, 0],
	"arm_r_fore":   ["res://assets/voxels/arm_r_fore.vox",   "arm_r_fore",   Vector3(-0.44, 0.0, -0.4), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  0,   0],
	"hand_r":       ["res://assets/voxels/hand_r.vox",       "hand_r",       Vector3( 0.2,  0.7, -0.4), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  180, 180],
	"arm_l_upper":  ["res://assets/voxels/arm_l_upper.vox",  "arm_l_upper",  Vector3(-0.44, 1.65, 0.3), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  180, 0],
	"arm_l_fore":   ["res://assets/voxels/arm_l_fore.vox",   "arm_l_fore",   Vector3(-0.44, 0.0, -0.4), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  0,   0],
	"hand_l":       ["res://assets/voxels/hand_l.vox",       "hand_l",       Vector3( 0.2,  0.7, -0.4), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  180, 180],
	"leg_r_upper":  ["res://assets/voxels/leg_r_upper.vox",  "leg_r_upper",  Vector3(-0.35, 0.0, -0.5), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  0,   0],
	"leg_r_fore":   ["res://assets/voxels/leg_r_fore.vox",   "leg_r_fore",   Vector3(-0.35, 0.0, -0.5), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  0,   0],
	"leg_l_upper":  ["res://assets/voxels/leg_l_upper.vox",  "leg_l_upper",  Vector3(-0.45, 0.0, -0.3), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  0,   0],
	"leg_l_fore":   ["res://assets/voxels/leg_l_fore.vox",   "leg_l_fore",   Vector3(-0.45, 0.0, -0.3), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  0,   0],
}

var segments: Dictionary = {}
var _is_dead: bool = false
var _legs_lost: int = 0
var _weapon_anchor: Node3D = null

var _current_weapon: Node = null

const SLOT_FISTS  = 0
const SLOT_MELEE  = 1
const SLOT_RANGED = 2

var _inventory: Array = [null, null, null]
var _current_slot: int = 0
var _highlighted_pickup = null  # WeaponPickup or null — populated in Task 9 (pickup raycast)

var _pickup_scene: PackedScene = preload("res://scenes/weapons/weapon_pickup.tscn")

var _is_attacking: bool = false
var _cam_rotating := false
var _cam_velocity := 0.0   # rad/s — persists after release for slide
var _cam_drag_x := 0.0     # pixel accumulator between physics ticks
var _shake_strength := 0.0

func _ready() -> void:
	add_to_group("player")
	if not is_multiplayer_authority():
		set_process_input(false)
		set_physics_process(false)
		return

	# Detach camera_pivot from player rotation — it follows position only
	camera_pivot.top_level = true
	camera_pivot.global_position = global_position

	# Fixed top-down angle: camera sits above and behind player
	camera_pivot.rotation.y = deg_to_rad(CAM_DEFAULT_YAW)
	camera.position = Vector3(0.0, CAM_HEIGHT, CAM_Z_OFFSET)
	camera.rotation_degrees = Vector3(CAM_PITCH, 0.0, 0.0)

	# Visible cursor for mouse aiming; confined so it stays in window
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	# FOV overlay — a full-screen spatial quad reads the depth buffer to reconstruct
	# world XZ for each pixel and tests it against the visibility polygon in world space.
	# This approach is height-agnostic: wall faces, pillar tops, and ground all work correctly.
	var fov_mat := ShaderMaterial.new()
	fov_mat.shader = load("res://shaders/fov_world.gdshader")
	fov_mat.render_priority = 100
	var fov_quad := QuadMesh.new()
	fov_quad.size = Vector2(2.0, 2.0)
	var fov_mesh := MeshInstance3D.new()
	fov_mesh.mesh = fov_quad
	fov_mesh.material_override = fov_mat
	fov_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Large cull margin prevents Godot from frustum-culling the unit-sized quad.
	# The POSITION override in the shader makes the quad fill the screen regardless
	# of where the node sits in the scene, so parent transform doesn't matter.
	fov_mesh.extra_cull_margin = 16384.0
	add_child(fov_mesh)
	var fov_overlay: Node = load("res://scripts/fov_overlay.gd").new()
	add_child(fov_overlay)
	fov_overlay.setup(self, fov_mat)

	var fists_instance := WeaponRegistry.get_scene(&"fists").instantiate() as WeaponBase
	fists_instance._player = self
	fists_instance.weapon_id = &"fists"
	weapon_holder.add_child(fists_instance)
	_inventory[SLOT_FISTS] = fists_instance
	_equip_slot.call_deferred(SLOT_FISTS)
	stance_manager.stance_changed.connect(_on_stance_changed)
	anim_player.animation_finished.connect(_on_anim_finished)
	call_deferred("_build_voxel_body")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_cam_rotating = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if _current_weapon is WeaponMelee:
				stance_manager.cycle(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if _current_weapon is WeaponMelee:
				stance_manager.cycle(-1)

	# Accumulate drag pixels — applied as velocity in _physics_process
	if event is InputEventMouseMotion and _cam_rotating:
		_cam_drag_x -= event.relative.x

	if event.is_action_pressed("switch_weapon_1"):
		_equip_slot(SLOT_FISTS)
	if event.is_action_pressed("switch_weapon_2"):
		_equip_slot(SLOT_MELEE)
	if event.is_action_pressed("switch_weapon_3"):
		_equip_slot(SLOT_RANGED)
	if event.is_action_pressed("drop_weapon"):
		_drop_weapon(_current_slot)
	if event.is_action_pressed("pickup_weapon"):
		if _highlighted_pickup != null:
			give_weapon(_highlighted_pickup.weapon_id)
			_highlighted_pickup.queue_free()
			_highlighted_pickup = null
			var hud := get_node_or_null("/root/test_scene/hud")
			if hud:
				hud.hide_pickup_prompt()

func _physics_process(delta: float) -> void:
	# Camera orbit: while dragging, velocity = exact mouse input; after release, friction glides to zero
	if _cam_rotating and delta > 0.0:
		_cam_velocity = _cam_drag_x * CAM_ROT_SENS / delta
	else:
		_cam_velocity = lerp(_cam_velocity, 0.0, CAM_ROT_FRICTION * delta)
	_cam_drag_x = 0.0
	camera_pivot.rotation.y += _cam_velocity * delta

	# Camera follows player with slight lag
	camera_pivot.global_position = camera_pivot.global_position.lerp(
		global_position, CAM_FOLLOW_SPEED * delta
	)

	# Screen shake — small random XZ offset that decays quickly
	if _shake_strength > 0.005:
		var shake_offset := Vector3(
			randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)
		) * _shake_strength * 0.12
		camera_pivot.global_position += shake_offset
		_shake_strength = lerpf(_shake_strength, 0.0, 18.0 * delta)
	else:
		_shake_strength = 0.0

	if _is_dead:
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Jump — disabled when crawling
	if Input.is_action_just_pressed("jump") and is_on_floor() and _legs_lost == 0:
		velocity.y = JUMP_FORCE

	# Movement relative to camera yaw so WASD always matches screen orientation
	var cam_fwd := -camera_pivot.global_transform.basis.z
	var cam_right := camera_pivot.global_transform.basis.x
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):  dir += cam_fwd
	if Input.is_action_pressed("move_back"):     dir -= cam_fwd
	if Input.is_action_pressed("move_left"):     dir -= cam_right
	if Input.is_action_pressed("move_right"):    dir += cam_right
	dir.y = 0.0
	dir = dir.normalized()

	var speed: float
	if _legs_lost >= 2:
		speed = CRAWL_SPEED
	elif _legs_lost == 1:
		speed = SPEED * 0.5
	else:
		speed = SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	# Rotate player to face mouse cursor on the ground plane
	var mouse_world := get_mouse_world_pos()
	if mouse_world != Vector3.ZERO:
		var flat := Vector3(mouse_world.x - global_position.x, 0.0, mouse_world.z - global_position.z)
		if flat.length() > 0.1:
			look_at(Vector3(mouse_world.x, global_position.y, mouse_world.z), Vector3.UP)

	move_and_slide()
	_update_animation(dir)
	_update_pickup_highlight()

# Returns camera ray origin and direction for the current mouse position.
func get_camera_ray() -> Dictionary:
	var mouse_pos := get_viewport().get_mouse_position()
	return {
		"origin": camera.project_ray_origin(mouse_pos),
		"dir": camera.project_ray_normal(mouse_pos)
	}

# Returns world position of the mouse cursor on the y=0 ground plane.
# Returns Vector3.ZERO if the ray misses (camera always angled down so this is rare).
func get_mouse_world_pos() -> Vector3:
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	if ray_dir.y >= 0.0:
		return Vector3.ZERO
	var t := -ray_origin.y / ray_dir.y
	return ray_origin + ray_dir * t

func _update_animation(_dir: Vector3) -> void:
	if _is_attacking:
		return
	if _current_weapon is WeaponRanged:
		anim_player.play("holding_right")
	elif _current_weapon is WeaponBat:
		anim_player.play("bat-hold")
	elif _current_weapon is WeaponKatana:
		anim_player.play("katana-hold")
	else:
		var speed_h := Vector2(velocity.x, velocity.z).length()
		if speed_h > 0.1:
			anim_player.play("walk")
		else:
			anim_player.play("idle")

func _equip_slot(idx: int) -> void:
	if idx != SLOT_FISTS and _inventory[idx] == null:
		return
	_is_attacking = false
	if _current_weapon != null:
		_current_weapon.visible = false
		_current_weapon.set_physics_process(false)
	_current_slot = idx
	_current_weapon = _inventory[idx]
	if _current_weapon != null:
		_current_weapon.visible = true
		_current_weapon.set_physics_process(true)
	var hud := get_node_or_null("/root/test_scene/hud")
	if hud and _current_weapon != null:
		var wb := _current_weapon as WeaponBase
		hud.set_weapon_name(WeaponRegistry.get_display_name(wb.weapon_id))
	_update_stance_for_weapon(_current_weapon)

func give_weapon(id: StringName) -> void:
	if not WeaponRegistry.has(id):
		push_error("give_weapon: unknown weapon id: " + id)
		return
	var slot := WeaponRegistry.get_slot(id)
	if _inventory[slot] != null:
		_drop_weapon(slot)
	var instance := WeaponRegistry.get_scene(id).instantiate() as WeaponBase
	instance._player = self
	instance.weapon_id = id
	if instance is WeaponRanged:
		(instance as WeaponRanged).ammo_changed.connect(_on_ammo_changed)
	weapon_holder.add_child(instance)
	instance.visible = false
	instance.set_physics_process(false)
	_inventory[slot] = instance
	_equip_slot(slot)

func _drop_weapon(slot: int) -> void:
	if slot == SLOT_FISTS:
		return
	var weapon: WeaponBase = _inventory[slot]
	if weapon == null:
		return
	var pickup = _pickup_scene.instantiate()
	pickup.weapon_id = weapon.weapon_id
	var forward := -global_transform.basis.z
	pickup.position = global_position + forward * 1.0
	pickup.position.y = global_position.y + 0.1
	get_tree().current_scene.add_child(pickup)
	weapon.queue_free()
	_inventory[slot] = null
	if _current_slot == slot:
		_equip_slot(SLOT_FISTS)

func _update_pickup_highlight() -> void:
	var space := get_world_3d().direct_space_state
	var cam_origin := camera.global_position
	var cam_forward := -camera.global_transform.basis.z
	var params := PhysicsRayQueryParameters3D.create(
		cam_origin,
		cam_origin + cam_forward * 3.0,
		4  # layer 3 only (weapon_pickups)
	)
	params.collide_with_areas = false
	var result := space.intersect_ray(params)
	var hud := get_node_or_null("/root/test_scene/hud")
	if result and result.collider is WeaponPickup:
		var pickup := result.collider as WeaponPickup
		if pickup != _highlighted_pickup:
			if _highlighted_pickup:
				_highlighted_pickup.highlight(false)
			pickup.highlight(true)
			_highlighted_pickup = pickup
		if hud:
			hud.show_pickup_prompt(WeaponRegistry.get_display_name(pickup.weapon_id))
	else:
		if _highlighted_pickup:
			_highlighted_pickup.highlight(false)
			_highlighted_pickup = null
		if hud:
			hud.hide_pickup_prompt()

func _update_stance_for_weapon(weapon: Node) -> void:
	if not weapon is WeaponBase:
		return
	var wb := weapon as WeaponBase
	match wb.weapon_type:
		WeaponBase.WeaponType.BLUNT:
			stance_manager.setup([StanceManager.Stance.LOW, StanceManager.Stance.MID, StanceManager.Stance.HIGH] as Array[StanceManager.Stance])
		WeaponBase.WeaponType.SHARP:
			stance_manager.setup([StanceManager.Stance.LOW, StanceManager.Stance.MID, StanceManager.Stance.HIGH, StanceManager.Stance.THRUST] as Array[StanceManager.Stance])
		WeaponBase.WeaponType.RANGED:
			pass  # no setup — scroll is no-op via WeaponMelee check
	# Always update HUD immediately on equip — setup() does not emit stance_changed
	var hud := get_node_or_null("/root/test_scene/hud")
	if hud:
		if wb.weapon_type == WeaponBase.WeaponType.RANGED:
			hud.update_stance(StanceManager.Stance.MID, [] as Array[StanceManager.Stance])
		else:
			hud.update_stance(stance_manager.current_stance(), stance_manager.current_stances())

func _on_stance_changed(stance: StanceManager.Stance) -> void:
	var hud := get_node_or_null("/root/test_scene/hud")
	if hud:
		hud.update_stance(stance, stance_manager.current_stances())

func _on_ammo_changed(current: int, max_ammo: int) -> void:
	var hud := get_node_or_null("/root/test_scene/hud")
	if hud:
		hud.update_ammo(current, max_ammo)

# Called by weapons on fire — short camera jolt. strength: 0.0–1.0 scale.
func trigger_hit_shake(strength: float = 0.2) -> void:
	_shake_strength = maxf(_shake_strength, strength)

func trigger_crosshair_recoil(kick: float = 12.0, recovery: float = 0.25) -> void:
	var hud := get_node_or_null("/root/test_scene/hud")
	if hud:
		hud.recoil(kick, recovery)

func play_attack_anim(anim_name: String) -> void:
	var mapped: String
	if anim_name == "shoot":
		mapped = "holding_right_shoot"
	else:
		var stance_key: String = StanceManager.Stance.find_key(stance_manager.current_stance()).to_lower()
		mapped = anim_name + "_" + stance_key
	if not anim_player.has_animation(mapped):
		push_error("play_attack_anim: animation not found: " + mapped)
		return
	_is_attacking = true
	anim_player.stop()
	anim_player.play(mapped)

func _on_anim_finished(_anim_name: String) -> void:
	if _is_attacking:
		_is_attacking = false

func _build_voxel_body() -> void:
	# Hide the original GLB meshes — skeleton stays alive to drive animations
	for mesh in $PlayerModel.find_children("*", "MeshInstance3D", true, false):
		mesh.visible = false

	var skeleton: Skeleton3D = $PlayerModel.find_child("Skeleton3D", true, false)
	if skeleton == null:
		push_error("Player: Skeleton3D not found in PlayerModel")
		return

	for seg_name in PLAYER_SEGMENT_CONFIG:
		var cfg = PLAYER_SEGMENT_CONFIG[seg_name]
		var vox_path: String = cfg[0]
		var bone_name: String = cfg[1]

		var bone_idx := skeleton.find_bone(bone_name)
		if bone_idx == -1:
			push_warning("Player: bone not found: " + bone_name)
			continue

		var attach := BoneAttachment3D.new()
		attach.bone_name = bone_name
		attach.bone_idx = bone_idx
		attach.rotation_degrees = Vector3(cfg[3], 0.0, cfg[4])
		skeleton.add_child(attach)


		var seg := VoxelSegment.new()
		seg.name = "VoxelSegment_" + seg_name
		seg.root_axis = cfg[6]
		seg.position = cfg[2]
		seg.scale = cfg[5]
		seg.rotation_degrees = Vector3(cfg[7], cfg[8], 0.0)
		attach.add_child(seg)
		seg.load_from_vox(vox_path)

		var area := Area3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		var aabb: AABB = seg.mesh_instance.get_aabb() if seg.mesh_instance.mesh else AABB()
		if aabb.size != Vector3.ZERO:
			shape.size = aabb.size
			col.position = aabb.get_center()
		else:
			shape.size = Vector3(0.4, 0.8, 0.4)
		col.shape = shape
		area.add_child(col)
		area.collision_layer = 2
		area.collision_mask = 0
		area.set_meta("voxel_segment", seg)
		seg.add_child(area)

		segments[seg_name] = seg

		if seg_name == "hand_r":
			var anchor := Node3D.new()
			anchor.name = "WeaponAnchor"
			anchor.position = Vector3(0, 0, 0)  # tune in-game once segments are positioned
			attach.add_child(anchor)
			_weapon_anchor = anchor

	var limb_system := LimbSystem.new()
	limb_system.name = "LimbSystem"
	add_child(limb_system)
	for seg_name in segments:
		segments[seg_name].set_meta("limb_system", limb_system)
	limb_system.initialize(segments)
	limb_system.leg_lost.connect(_on_leg_lost)
	limb_system.died.connect(_die)

	if _weapon_anchor:
		weapon_holder.reparent(_weapon_anchor, false)
		weapon_holder.position = Vector3.ZERO
		weapon_holder.rotation = Vector3.ZERO
		weapon_holder.scale = Vector3.ONE
		# Weapon nodes carry .tscn transforms (scale 2, rotations, offsets) that were
		# designed for camera space. Now that we're in bone space, those transforms
		# corrupt hitarea and sweep marker positions. Bake each weapon node's transform
		# into its visual children only (mesh, audio, particles), then zero the weapon
		# node. Hitareas (Area3D) and sweep markers (Marker3D) are left untouched so
		# they operate in clean hand-bone-relative space.
		for weapon_node in weapon_holder.get_children():
			var old_xform: Transform3D = weapon_node.transform
			if old_xform.is_equal_approx(Transform3D.IDENTITY):
				continue
			weapon_node.transform = Transform3D.IDENTITY
			for child in weapon_node.get_children():
				if child is MeshInstance3D or child is AudioStreamPlayer3D or child is GPUParticles3D:
					child.transform = old_xform * child.transform


func take_damage(amount: float) -> void:
	if _is_dead or segments.is_empty():
		return
	var seg: VoxelSegment = segments.get("torso_bottom")
	if seg != null:
		seg.take_hit(Vector3.ZERO, 2.0, amount)

func _on_leg_lost(seg_name: String) -> void:
	if seg_name in ["leg_r_upper", "leg_l_upper"]:
		_legs_lost += 2
	elif seg_name in ["leg_r_fore", "leg_l_fore"]:
		_legs_lost += 1

func _die() -> void:
	_is_dead = true
	_is_attacking = false
	print("Player died! (TODO Task 6: death/respawn)")
