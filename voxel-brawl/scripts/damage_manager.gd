# scripts/damage_manager.gd
# Autoload singleton — register in Project -> Project Settings -> Autoload
# Name: DamageManager
extends Node

# All weapon hits funnel through here.
# In single-player, multiplayer.is_server() is always true.
# In Phase 3: add @rpc("any_peer") decorator and broadcast to clients.
func process_hit(segment: VoxelSegment, hit_pos_local: Vector3, radius: float, damage: float) -> void:
	if multiplayer.is_server():
		segment.take_hit(hit_pos_local, radius, damage)
