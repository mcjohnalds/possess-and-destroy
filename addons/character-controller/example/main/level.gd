extends Node3D

const ENEMY_FOV := 0.45 * TAU
@export var fast_close := true
var men: Array[Man] = []
var player_has_gun := false
var last_fired_at := 0.0
var possessed_man_name := "the civilian"
var player_hunted := false
@onready var patrol: Node = $Patrol
@onready var camera: Camera3D = (
	$Player/Head/FirstPersonCameraReference/Camera3D
)
@onready var use_label: Label = $UI/UseLabel
@onready var possessing_label: Label = $UI/PossessingLabel
@onready var player: FPSController3D = $Player
@onready var gun := $Player/Head/GunTransform/M16 as M16
@onready var bullet_impact_scene := preload("res://bullet_impact.tscn")
@onready var blood_impact_scene := preload("res://blood_impact.tscn")
@onready var tracer_scene := preload("res://tracer.tscn")
@onready var accuracy := 1.0
@onready var crosshair := $UI/Crosshair as Control
@onready var gun_original_position := gun.position
@onready var gun_kick_velocity := Vector3.ZERO
@onready var gun_shot_audio_stream_player := (
	$GunShotAudioStreamPlayer as AudioStreamPlayer
)
@onready var hitmarker_audio_stream_player := (
	$HitmarkerAudioStreamPlayer as AudioStreamPlayer
)
@onready var headshot_audio_stream_player := (
	$HeadshotAudioStreamPlayer as AudioStreamPlayer
)
@onready var possession_audio_stream_player := (
	$PossessionAudioStreamPlayer as AudioStreamPlayer
)
@onready var messages := $UI/Messages as Control

enum PhysicsLayers {
	DEFAULT = 1 << 0,
}


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
	gun.muzzle_flash_particles.visible = false
	gun.muzzle_flash_particles.one_shot = true
	player.jumped.connect(func() -> void:
		accuracy -= 0.5
	)


func on_velocity_computed(safe_velocity: Vector3, man: Man) -> void:
	man.safe_velocity = safe_velocity


func actor_setup() -> void:
	await get_tree().physics_frame
	for man in men:
		if man.patrol:
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
	for msg: Message in messages.get_children():
		msg.modulate.a = lerpf(
			1.0,
			0.6,
			clampf((Global.time() - msg.created_at) / 2.0, 0.0, 1.0)
		)
	if (
		player_has_gun
		and Input.is_action_pressed("primary")
		and Global.time() - last_fired_at > 0.1
	):
		for man: Man in men:
			if (
				is_instance_valid(man)
				and can_man_see_point(man, camera.global_position)
				and not player_hunted
			):
				player_hunted = true
				log_message(
					"<%s> I think %s is possessed by the demon, engaging!"
					% [man.name, possessed_man_name]
				)
				break
		gun_shot_audio_stream_player.play()

		last_fired_at = Global.time()

		var query := BulletRay.Query.new()
		query.source = camera
		query.accuracy = accuracy
		query.men = men
		var result := BulletRay.intersect(query)

		if result.hit_man:
			var damage := 0.2
			if result.headshot:
				damage = 1.0
				headshot_audio_stream_player.play(4.9)

			if damage > 0:
				hitmarker_audio_stream_player.play(0.1)
				result.hit_man.health -= damage
				if result.hit_man.health <= 0.0:
					result.hit_man.queue_free()

		if result.hit_anything:
			var impact_scene := (
				blood_impact_scene if result.hit_man else bullet_impact_scene
			)
			var impact := impact_scene.instantiate() as Node3D
			var impact_particle_effect := (
				impact.get_node("GPUParticles3D") as GPUParticles3D
			)
			impact.position = result.hit_position
			impact_particle_effect.emitting = false
			impact_particle_effect.finished.connect(
				func() -> void: impact.queue_free()
			)
			impact_particle_effect.one_shot = true
			impact_particle_effect.emitting = true
			impact.scale *= clamp(
				camera.global_position.distance_to(result.hit_position) - 1.0,
				1.0,
				3.0
			)
			add_child(impact)

		gun.muzzle_flash_particles.visible = true
		gun.muzzle_flash_particles.restart()

		var tracer: Node3D = tracer_scene.instantiate()
		tracer.position = gun.muzzle_flash.global_position
		tracer.scale.z = (
			gun.muzzle_flash.global_position.distance_to(result.hit_position)
		)

		var tracer_particles: GPUParticles3D = (
			tracer.get_node("GPUParticles3D")
		)
		tracer_particles.emitting = false
		tracer_particles.finished.connect(func() -> void: tracer.queue_free())
		tracer_particles.one_shot = true
		tracer_particles.emitting = true

		add_child(tracer)
		tracer.look_at(result.hit_position, Vector3.UP, true)

		accuracy -= 0.1 - 0.1 * (1.0 - accuracy)

		var gun_accel := 0.8
		gun_kick_velocity += Vector3(
			randf_range(-gun_accel, gun_accel),
			randf_range(-gun_accel, gun_accel),
			gun_accel
		)

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
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		camera.global_position + camera.global_basis.z * -10.0
	)
	var collision := get_world_3d().direct_space_state.intersect_ray(query)
	if collision and collision.collider is Man:
		var possessed_man: Man = collision.collider
		if Input.is_action_just_pressed("use"):
			for man: Man in men:
				if (
					man != possessed_man
					and is_instance_valid(man)
					and (
						can_man_see_point(
							man,
							possessed_man.head_hitbox.global_position
						)
						or can_man_see_point(man, camera.global_position)
					)
					and not player_hunted
				):
					player_hunted = true
					log_message(
						"<%s> I saw the demon possess %s, engaging enemy!"
						% [man.name, possessed_man.name]
					)
					break

			possession_audio_stream_player.play(0.7)
			possessed_man_name = possessed_man.name
			# + 0.1 prevents player from falling beneath floor
			player.position = possessed_man.position + 0.1 * Vector3.UP
			player.velocity = Vector3.ZERO
			possessing_label.text = "Possessing: " + possessed_man.name
			gun.visible = true
			player_has_gun = true
			gun.visible = player_has_gun
			possessed_man.queue_free()

		use_label.visible = true
	else:
		use_label.visible = false


func can_man_see_point(man: Man, point: Vector3) -> bool:
	var exclude: Array[Variant] = []
	exclude.append(player.get_rid())
	for man2: Man in men:
		if is_instance_valid(man2):
			exclude.append(man2.get_rid())
			exclude.append(man2.head_hitbox.get_rid())
			exclude.append(man2.body_hitbox.get_rid())

	var v1 := -man.head_hitbox.global_basis.z
	var v2 := point - man.head_hitbox.global_position
	if v1.angle_to(v2) > ENEMY_FOV / 2.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		man.head_hitbox.global_position,
		point
	)
	query.exclude = exclude
	return not get_world_3d().direct_space_state.intersect_ray(query)


func _physics_process(_delta: float) -> void:
	for man in men:
		if not is_instance_valid(man) or not man.patrol:
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


func print_hierarchy(node: Node) -> void:
	var s := ""
	var x: Node = node
	while x.get_parent():
		s += x.name + " <- "
		x = x.get_parent()
	s = s.substr(0, s.length() - " <- ".length())
	print(s)


func log_message(text: String) -> void:
	var new_msg := Message.new()
	new_msg.created_at = Global.time()
	new_msg.position.x = 8.0
	new_msg.add_theme_font_size_override("font_size", 24)
	new_msg.text = text
	messages.add_child(new_msg)
	if messages.get_child_count() > 3:
		messages.remove_child(messages.get_child(0))
	var y := 8.0
	for msg: Label in messages.get_children():
		msg.position.y = y
		y += 36.0
