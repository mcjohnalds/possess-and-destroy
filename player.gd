class_name Player
extends FPSController3D

var last_known_position: Vector3
var last_seen_at := -10000.0
var last_possessed_at := -10000.0
var invisible := false
var gun: Gun
@onready var gun_transform: Node3D = $Head/GunTransform
@onready var camera: Camera3D = $Head/FirstPersonCameraReference/Camera3D
