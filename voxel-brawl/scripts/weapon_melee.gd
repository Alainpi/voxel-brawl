# scripts/weapon_melee.gd
# Melee weapon base — Area3D overlap hit detection with timer-driven activation window.
# Subclasses override _configure() for stats and _apply_hit() for damage behaviour.
class_name WeaponMelee
extends WeaponBase

var damage := 10.0
var voxel_radius := 2.0
var reach := 0.5
var cooldown := 0.4
var attack_anim := "punch"

var hit_enable_delay := 0.1      # seconds from attack start until hitbox activates
var hit_window_duration := 0.15  # how long the hitbox stays active
var max_hits := 1                # max segments hit per swing; subclasses override
var hit_shape: Shape3D = null    # set by subclass in _configure()
var hit_shape_offset: Vector3 = Vector3.ZERO

var _cooldown_timer := 0.0
var _hit_area: Area3D = null
var _hit_segments: Array[VoxelSegment] = []
var _own_segment_set: Dictionary = {}  # VoxelSegment -> true, lazy-populated on first use

@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D

# _create_hitarea() must come after super() — hit_shape and hit_shape_offset are
# populated by _configure() inside super(), before _create_hitarea() runs.
func _ready() -> void:
	super()
	_create_hitarea()

# Virtual — override in subclasses to build composite hitbox shapes (e.g. axe with
# multiple blades). Call super() first to get _hit_area created and area_entered
# connected, then add additional CollisionShape3D children to _hit_area.
# If overriding without calling super(), you must create _hit_area and connect
# area_entered yourself.
# IMPORTANT: set hit_shape in _configure() for super() to build the primary shape.
# If hit_shape is null, super() skips the primary CollisionShape3D.
func _create_hitarea() -> void:
	_hit_area = Area3D.new()
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = 2   # matches VoxelSegment area layer
	_hit_area.monitorable = false  # other areas cannot detect this hitbox; only this hitbox detects them
	if hit_shape:
		var col := CollisionShape3D.new()
		col.shape = hit_shape
		col.position = hit_shape_offset
		col.disabled = true
		_hit_area.add_child(col)
	add_child(_hit_area)
	_hit_area.area_entered.connect(_on_hit_area_entered)

func _enable_hitbox() -> void:
	for child in _hit_area.get_children():
		if child is CollisionShape3D:
			child.disabled = false

func _disable_hitbox() -> void:
	for child in _hit_area.get_children():
		if child is CollisionShape3D:
			child.disabled = true

func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if Input.is_action_just_pressed("attack") and _cooldown_timer <= 0.0:
		_attack()

func _attack() -> void:
	_cooldown_timer = cooldown
	_hit_segments.clear()
	_player.play_attack_anim(attack_anim)
	await get_tree().create_timer(hit_enable_delay).timeout
	if not is_instance_valid(self) or not _player._is_attacking:
		return   # node freed, or interrupted by death / weapon swap
	_enable_hitbox()
	await get_tree().create_timer(hit_window_duration).timeout
	if is_instance_valid(self):
		_disable_hitbox()

func _on_hit_area_entered(area: Area3D) -> void:
	# Filter order: reject non-segments first so environmental areas don't consume hit slots.
	if not area.has_meta("voxel_segment"):
		return
	var seg: VoxelSegment = area.get_meta("voxel_segment")
	# Lazy-populate own segment set (player builds segments deferred, so segments dict
	# may be empty when weapon _ready() fires — populate on first area_entered instead).
	if _own_segment_set.is_empty() and not _player.segments.is_empty():
		for s: VoxelSegment in _player.segments.values():
			_own_segment_set[s] = true
	if seg in _own_segment_set:   # O(1) hash lookup — no allocation
		return
	if seg in _hit_segments:
		return
	if _hit_segments.size() >= max_hits:
		return
	_hit_segments.append(seg)
	# local_hit uses Area3D origin as approximation — Step 4 replaces with blade-tip sweep.
	var local_hit := seg.to_local(_hit_area.global_position)
	_apply_hit(seg, local_hit)
	if _hit_segments.size() == 1:   # feedback fires once per swing on first hit
		if audio.stream:
			audio.play()
		_player.trigger_hit_shake()
		_player.trigger_crosshair_recoil()

# Override in subclasses to implement weapon-specific damage behaviour.
func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage)
