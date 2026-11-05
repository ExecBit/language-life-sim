extends Node3D

const VIEWS: Array[Dictionary] = [
	{"frame": 0, "name": "entrance", "position": Vector3(14.0, 1.65, 10.8), "target": Vector3(8.0, 1.0, 6.0)},
	{"frame": 2, "name": "bar", "position": Vector3(8.0, 1.65, 6.0), "target": Vector3(3.0, 1.0, 8.5)},
	{"frame": 4, "name": "kitchen", "position": Vector3(8.0, 1.65, 5.0), "target": Vector3(3.0, 1.0, 2.5)},
	{"frame": 6, "name": "guest_tables", "position": Vector3(8.0, 1.65, 4.5), "target": Vector3(12.5, 1.0, 6.5)},
]

var _frame := 0
var _camera: Camera3D


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "ReviewCamera"
	_camera.fov = 75.0
	add_child(_camera)
	_camera.current = true
	_set_view(VIEWS[0])


func _process(_delta: float) -> void:
	for view in VIEWS:
		if int(view["frame"]) == _frame:
			_set_view(view)
	_frame += 1


func _set_view(view: Dictionary) -> void:
	_camera.global_position = view["position"]
	_camera.look_at(view["target"], Vector3.UP)
