# scripts/anim_tree_setup.gd
# Builds the M1 AnimationTree resource structure and activates the tree.
# Shared across Player, Brawler, and Dummy.
class_name AnimTreeSetup

static func build_and_activate(anim_tree: AnimationTree, anim_player: AnimationPlayer) -> void:
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.tree_root = _build_blend_tree()
	anim_tree.active = true
	# Set breathe additive blend amount to always-on
	anim_tree.set("parameters/breathe_add/add_amount", 1.0)

static func _build_blend_tree() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()

	# 1. BlendSpace2D for locomotion
	var loco := AnimationNodeBlendSpace2D.new()
	loco.auto_triangles = true
	loco.min_space = Vector2(-1.0, -1.0)
	loco.max_space = Vector2(1.0, 1.0)
	loco.x_label = "strafe"
	loco.y_label = "fwd_speed"

	# (0,0): idle state machine — round-robins idle_a/b/c at end of each clip
	loco.add_blend_point(_build_idle_sm(), Vector2(0.0, 0.0))

	# Forward/back/strafe clips
	_add_clip(loco, "walk",      Vector2( 0.0,  0.5))
	_add_clip(loco, "run",       Vector2( 0.0,  1.0))
	_add_clip(loco, "walk_back", Vector2( 0.0, -1.0))
	_add_clip(loco, "strafe_l",  Vector2(-1.0,  0.0))
	_add_clip(loco, "strafe_r",  Vector2( 1.0,  0.0))
	# Diagonal corners: blend between walk and strafe
	_add_clip(loco, "walk",      Vector2(-1.0,  0.5))
	_add_clip(loco, "walk",      Vector2( 1.0,  0.5))

	# 2. Breathe additive source
	var breathe_anim := AnimationNodeAnimation.new()
	breathe_anim.animation = &"breathe_idle"

	# 3. Add2 node: base = locomotion, add = breathe
	var breathe_add := AnimationNodeAdd2.new()

	# Wire into BlendTree
	bt.add_node(&"locomotion",   loco)
	bt.add_node(&"breathe_anim", breathe_anim)
	bt.add_node(&"breathe_add",  breathe_add)

	# breathe_add port 0 (base) ← locomotion
	bt.connect_node(&"breathe_add", 0, &"locomotion")
	# breathe_add port 1 (add) ← breathe_anim
	bt.connect_node(&"breathe_add", 1, &"breathe_anim")
	# output ← breathe_add
	bt.connect_node(&"output", 0, &"breathe_add")

	return bt

static func _add_clip(bs: AnimationNodeBlendSpace2D, clip: StringName, pos: Vector2) -> void:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	bs.add_blend_point(node, pos)

static func _build_idle_sm() -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()
	# NESTED so it can live inside the BlendSpace2D blend point
	sm.state_machine_type = AnimationNodeStateMachine.STATE_MACHINE_TYPE_NESTED

	_add_idle_clip(sm, &"idle_a")
	_add_idle_clip(sm, &"idle_b")
	_add_idle_clip(sm, &"idle_c")

	# Round-robin: lowest priority wins → a→b→c→a deterministic cycle.
	# Each clip plays once (break_loop_at_end), then auto-advances.
	_link(sm, &"idle_a", &"idle_b", 1)
	_link(sm, &"idle_a", &"idle_c", 2)
	_link(sm, &"idle_b", &"idle_c", 1)
	_link(sm, &"idle_b", &"idle_a", 2)
	_link(sm, &"idle_c", &"idle_a", 1)
	_link(sm, &"idle_c", &"idle_b", 2)

	return sm

static func _add_idle_clip(sm: AnimationNodeStateMachine, clip: StringName) -> void:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	sm.add_node(clip, node)

static func _link(sm: AnimationNodeStateMachine, from: StringName, to: StringName, priority: int) -> void:
	var t := AnimationNodeStateMachineTransition.new()
	t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	t.break_loop_at_end = true
	t.xfade_time = 0.4
	t.priority = priority
	sm.add_transition(from, to, t)
