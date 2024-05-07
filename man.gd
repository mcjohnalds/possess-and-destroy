@tool
class_name Man
extends CharacterBody3D

@export var patrol := true


@export var gun_type := Level.GunType.M16:
	get:
		return gun_type
	set(value):
		gun_type = value
		if not is_node_ready():
			return
		var mat: StandardMaterial3D = (
			body_mesh.get_surface_override_material(1)
		)
		match value:
			Level.GunType.M16:
				gun = m_16_scene.instantiate()
				mat.albedo_color = Color("b59e67", 1.0)
			Level.GunType.SNIPER_RIFLE:
				gun = sniper_rifle_scene.instantiate()
				mat.albedo_color = Color("6777b5", 1.0)


var patrol_index := 0
var safe_velocity: Vector3
var health := 1.0
var nav_last_updated_at := -10000.0
var alive := true
var died_at := 0.0
var last_ai_state: Level.AiManState


var gun: Gun:
	get:
		if aim_transform.get_child_count(true) > 0:
			return aim_transform.get_child(0, true)
		if rest_transform.get_child_count(true) > 0:
			return rest_transform.get_child(0, true)
		return null
	set(value):
		if gun:
			gun.queue_free()
		rest_transform.add_child(value, false, INTERNAL_MODE_BACK)


@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var head_hitbox: Area3D = $HeadHitbox
@onready var body_hitbox: Area3D = $BodyHitbox
@onready var aim_transform: Node3D = $AimTransform
@onready var rest_transform: Node3D = $RestTransform
@onready var nav_collider: CollisionShape3D = $NavCollider
@onready var m_16_scene := preload("res://m_16.tscn")
@onready var sniper_rifle_scene := preload("res://sniper_rifle.tscn")
@onready var body_mesh: MeshInstance3D = $Mesh/Body


func _ready() -> void:
	gun_type = gun_type
