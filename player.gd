class_name Player
extends FPSController3D

var last_known_position: Vector3
var invisible := false
@onready var m_16 := $Head/GunTransform/M16 as M16
@onready var camera: Camera3D = $Head/FirstPersonCameraReference/Camera3D
