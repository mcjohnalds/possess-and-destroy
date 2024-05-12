class_name Start
extends Node3D

@onready var camera_parent: Node3D = $CameraParent
@onready var start_button: Button = $UI/Button


func _process(_delta: float) -> void:
	camera_parent.rotation.y = (
		sin(Level.get_ticks_sec() * 0.17) * 0.002 * TAU
	)
	camera_parent.position.y = (
		sin(Level.get_ticks_sec() * 0.15) * 0.1
	)
