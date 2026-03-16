# scripts/main.gd
extends Node3D

func _ready() -> void:
	$Dummy.died.connect(func(): print("Dummy died — resetting..."))
