extends Node3D


func _ready() -> void:
	# The embedded Test Walk player marks its own camera current in _ready().
	# Reassert this scene's overview camera after all child scenes initialize.
	await get_tree().process_frame
	$OverviewCamera.make_current()
