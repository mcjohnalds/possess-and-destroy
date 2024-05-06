class_name Man
extends CharacterBody3D

@export var patrol := true
var patrol_index := 0
var safe_velocity: Vector3
var health := 1.0
var nav_last_updated_at := -10000.0
var alive := true
var died_at := 0.0
var last_ai_state: Level.AiManState
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var head_hitbox: Area3D = $HeadHitbox
@onready var body_hitbox: Area3D = $BodyHitbox
@onready var m_16: M16 = get_node("%M16")
@onready var aim_transform: Node3D = $AimTransform
@onready var rest_transform: Node3D = $RestTransform
@onready var nav_collider: CollisionShape3D = $NavCollider
