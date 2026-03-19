# scripts/main.gd
extends Node3D

func _ready() -> void:
	$Dummy.died.connect(func(): print("Dummy died — resetting..."))
	$Brawler.died.connect(func(): print("Brawler died — resetting..."))
