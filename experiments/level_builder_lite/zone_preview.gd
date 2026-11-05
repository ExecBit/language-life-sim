extends Node3D

const DEBUG := preload("res://addons/level_builder/generator/gen_debug.gd")


func _ready() -> void:
	DEBUG.build($Level)
	$Camera3D.current = true
