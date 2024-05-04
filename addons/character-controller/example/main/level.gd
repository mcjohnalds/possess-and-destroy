extends Node3D

@export var fast_close := true
var men: Array[Man] = []
@onready var patrol: Node = $Patrol
@onready var camera: Camera3D = $Player/Head/FirstPersonCameraReference/Camera3D
@onready var use_ray: RayCast3D
@onready var use_label: Label = $UI/UseLabel
@onready var possessing_label: Label = $UI/PossessingLabel
@onready var player: FPSController3D = $Player


func _ready() -> void:
	if !OS.is_debug_build():
		fast_close = false
	if fast_close:
		print("** Fast Close enabled in the 'level.gd' script **")
		print("** 'Esc' to close 'Shift + F1' to release mouse **")
	set_process_input(fast_close)
	men.assign($Men.get_children())
	for man in men:
		man.navigation_agent.path_desired_distance = 0.5
		man.navigation_agent.target_desired_distance = 0.5
		man.navigation_agent.velocity_computed.connect(on_velocity_computed.bind(man))
	call_deferred("actor_setup")


func on_velocity_computed(safe_velocity: Vector3, man: Man) -> void:
	man.safe_velocity = safe_velocity


func actor_setup() -> void:
	await get_tree().physics_frame
	for man in men:
		man.navigation_agent.set_target_position((patrol.get_child(0) as Node3D).position)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit() # Quits the game
	
	if event.is_action_pressed("change_mouse_input"):
		match Input.get_mouse_mode():
			Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			Input.MOUSE_MODE_VISIBLE:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# Capture mouse if clicked on the game, needed for HTML5
# Called when an InputEvent hasn't been consumed by _input() or any GUI item
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if m.button_index == MOUSE_BUTTON_LEFT && m.pressed:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(_delta: float) -> void:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + camera.global_basis.z * -10.0)
	var collision := get_world_3d().direct_space_state.intersect_ray(query)
	if collision and collision.collider is Man:
		var man: Man = collision.collider
		if Input.is_action_just_pressed("use"):
			player.position = man.position
			player.velocity = Vector3.ZERO
			possessing_label.text = "Possessing: " + man.name
			man.queue_free()
		use_label.visible = true
	else:
		use_label.visible = false


func _physics_process(_delta: float) -> void:
	for man in men:
		if not is_instance_valid(man):
			continue
		if man.navigation_agent.is_navigation_finished():
			man.patrol_index += 1
			man.navigation_agent.set_target_position((patrol.get_child(man.patrol_index % patrol.get_child_count()) as Node3D).position)
			continue
		man.look_at(man.navigation_agent.get_next_path_position(), Vector3.UP)
		man.rotation.x = 0
		man.rotation.z = 0
		man.velocity = man.global_position.direction_to(man.navigation_agent.get_next_path_position()) * 4.0 + man.safe_velocity
		man.move_and_slide()
