class_name Man
extends CharacterBody3D

@export var patrol := true
var patrol_index := 0
var safe_velocity: Vector3
var health := 1.0
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var head_hitbox: Area3D = $HeadHitbox
@onready var body_hitbox: Area3D = $BodyHitbox
