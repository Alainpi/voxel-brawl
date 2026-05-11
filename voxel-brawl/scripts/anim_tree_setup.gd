# scripts/anim_tree_setup.gd
# Builds the M1 AnimationTree resource structure and activates the tree.
# Shared across Player, Brawler, and Dummy.
class_name AnimTreeSetup

static func build_and_activate(anim_tree: AnimationTree, anim_player: AnimationPlayer) -> void:
	# Force loop on all locomotion and additive clips — GLB import defaults to no-loop.
	for clip in ["idle_a", "idle_b", "idle_c", "walk", "run", "walk_back",
			"strafe_l", "strafe_r", "breathe_idle"]:
		if anim_player.has_animation(clip):
			anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.tree_root = _build_blend_tree()
	anim_tree.active = true
	anim_tree.set("parameters/breathe_add/add_amount", 1.0)

static func _build_blend_tree() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()

	# 1. BlendSpace2D for locomotion
	var loco := AnimationNodeBlendSpace2D.new()
	loco.auto_triangles = false  # manual triangles avoid Delaunay degeneracy on collinear Y-axis points
	loco.min_space = Vector2(-1.0, -1.0)
	loco.max_space = Vector2(1.0, 1.0)
	loco.x_label = "strafe"
	loco.y_label = "fwd_speed"

	# Blend points — indices matter for add_triangle() calls below:
	# 0: idle_a (0,0)
	# 1: walk (0,0.5)   2: run (0,1.0)   3: walk_back (0,-1.0)
	# 4: strafe_l (-1,0)   5: strafe_r (1,0)
	# 6: walk_diag_l (-1,0.5)   7: walk_diag_r (1,0.5)
	_add_clip(loco, &"idle_a",    Vector2( 0.0,  0.0))
	_add_clip(loco, &"walk",      Vector2( 0.0,  0.5))
	_add_clip(loco, &"run",       Vector2( 0.0,  1.0))
	_add_clip(loco, &"walk_back", Vector2( 0.0, -1.0))
	_add_clip(loco, &"strafe_l",  Vector2(-1.0,  0.0))
	_add_clip(loco, &"strafe_r",  Vector2( 1.0,  0.0))
	_add_clip(loco, &"walk",      Vector2(-1.0,  0.5))
	_add_clip(loco, &"walk",      Vector2( 1.0,  0.5))

	# 8 triangles covering the full space
	loco.add_triangle(0, 1, 4)  # idle-walk-strafe_l
	loco.add_triangle(0, 1, 5)  # idle-walk-strafe_r
	loco.add_triangle(0, 3, 4)  # idle-walk_back-strafe_l
	loco.add_triangle(0, 3, 5)  # idle-walk_back-strafe_r
	loco.add_triangle(1, 2, 6)  # walk-run-walk_diag_l
	loco.add_triangle(1, 2, 7)  # walk-run-walk_diag_r
	loco.add_triangle(1, 4, 6)  # walk-strafe_l-walk_diag_l
	loco.add_triangle(1, 5, 7)  # walk-strafe_r-walk_diag_r

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
