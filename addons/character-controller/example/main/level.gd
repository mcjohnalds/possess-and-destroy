extends Node3D

@export var fast_close := true
var men: Array[Man] = []
var player_has_gun := true
var last_fired_at := 0.0
@onready var patrol: Node = $Patrol
@onready var camera: Camera3D = $Player/Head/FirstPersonCameraReference/Camera3D
@onready var use_ray: RayCast3D
@onready var use_label: Label = $UI/UseLabel
@onready var possessing_label: Label = $UI/PossessingLabel
@onready var player: FPSController3D = $Player
@onready var gun: Node3D = $Player/Head/M16
@onready var bullet_impact_scene := preload("res://bullet_impact.tscn")
@onready var tracer_scene := preload("res://tracer.tscn")
@onready var muzzle_flash := $Player/Head/M16/MuzzleFlash as Node3D
@onready var muzzle_flash_particles := $Player/Head/M16/MuzzleFlash/GPUParticles3D as GPUParticles3D
@onready var accuracy := 1.0
@onready var crosshair := $UI/Crosshair as Control
@onready var gun_original_position := gun.position
@onready var gun_kick_velocity := Vector3.ZERO
@onready var gun_shot_audio_stream_player := $GunShotAudioStreamPlayer as AudioStreamPlayer


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
	gun.visible = player_has_gun
	muzzle_flash_particles.visible = false
	muzzle_flash_particles.one_shot = true
	player.jumped.connect(func() -> void:
		accuracy -= 0.5
	)


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


func _process(delta: float) -> void:
	process_use()
	if player_has_gun and Input.is_action_pressed("primary") and Time.get_ticks_msec() / 1000.0 - last_fired_at > 0.1:
		gun_shot_audio_stream_player.play()

		last_fired_at = Time.get_ticks_msec() / 1000.0

		var dir := camera.global_basis.z
		var max_spread := 0.2 * (1.0 - accuracy)
		dir = dir.rotated(camera.global_basis.x, randf_range(-max_spread, max_spread))
		dir = dir.rotated(camera.global_basis.y, randf_range(-max_spread, max_spread))
		var end := camera.global_position + dir * -100.0
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, end)
		var collision := get_world_3d().direct_space_state.intersect_ray(query)
		if collision:
			end = collision.position

		muzzle_flash_particles.visible = true
		muzzle_flash_particles.restart()

		var tracer: Node3D = tracer_scene.instantiate()
		tracer.position = muzzle_flash.global_position
		tracer.scale.z = muzzle_flash.global_position.distance_to(end)

		var tracer_particles: GPUParticles3D = tracer.get_node("GPUParticles3D")
		tracer_particles.emitting = false
		tracer_particles.finished.connect(func() -> void: tracer_particles.queue_free())
		tracer_particles.one_shot = true
		tracer_particles.emitting = true

		add_child(tracer)
		tracer.look_at(end, Vector3.UP, true)

		var impact: GPUParticles3D = bullet_impact_scene.instantiate()
		impact.position = end
		impact.emitting = false
		impact.finished.connect(func() -> void: impact.queue_free())
		impact.one_shot = true
		impact.emitting = true
		add_child(impact)

		accuracy -= 0.1 - 0.1 * (1.0 - accuracy)

		var gun_accel := 0.8
		gun_kick_velocity += Vector3(randf_range(-gun_accel, gun_accel), randf_range(-gun_accel, gun_accel), gun_accel)
	
	accuracy += 1.5 * delta - accuracy * delta
	var max_accuracy := 1.0
	if player._direction != Vector3.ZERO:
		max_accuracy = 0.9
	if player.sprint_ability._active:
		max_accuracy = 0.6
	accuracy = clampf(accuracy, 0.0, max_accuracy)
	crosshair.scale = Vector2(1.0, 1.0) * (1.0 + 3.0 * (1.0 - accuracy))

	var gun_reset_velocity := (gun_original_position - gun.position) * accuracy * 5.0
	var gun_velocity := gun_kick_velocity + gun_reset_velocity
	gun.position += gun_velocity * delta
	gun_kick_velocity -= gun_kick_velocity * delta * 40.0


func process_use() -> void:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + camera.global_basis.z * -10.0)
	var collision := get_world_3d().direct_space_state.intersect_ray(query)
	if collision and collision.collider is Man:
		var man: Man = collision.collider
		if Input.is_action_just_pressed("use"):
			player.position = man.position
			player.velocity = Vector3.ZERO
			possessing_label.text = "Possessing: " + man.name
			gun.visible = true
			player_has_gun = true
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
