class_name Man
extends CharacterBody3D

var patrol_index := 0
var safe_velocity: Vector3
var health := 1.0
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
