extends Node3D

const ENEMY_FOV := 0.45 * TAU
var men: Array[Man] = []
var player_has_gun := false
var possessed_man_name := "the civilian"
var player_hunted := false
@onready var patrol: Node = $Patrol
@onready var use_label: Label = $UI/UseLabel
@onready var possessing_label: Label = $UI/PossessingLabel
@onready var player: Player = $Player
@onready var bullet_impact_scene := preload("res://bullet_impact.tscn")
@onready var blood_impact_scene := preload("res://blood_impact.tscn")
@onready var tracer_scene := preload("res://tracer.tscn")
@onready var crosshair := $UI/Crosshair as Control
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
@onready var damage_audio_stream_player := (
	$DamageAudioStreamPlayer as AudioStreamPlayer
)
@onready var messages := $UI/Messages as Control

enum PhysicsLayers {
	DEFAULT = 1 << 0,
}


func _ready() -> void:
	men.assign($Men.get_children())
	for man in men:
		man.navigation_agent.path_desired_distance = 0.5
		man.navigation_agent.target_desired_distance = 0.5
		man.navigation_agent.velocity_computed.connect(on_velocity_computed.bind(man))
	call_deferred("actor_setup")
	player.m_16.visible = player_has_gun
	player.m_16.muzzle_flash_particles.visible = false
	player.m_16.muzzle_flash_particles.one_shot = true
	player.jumped.connect(func() -> void:
		player.m_16.accuracy -= 0.5
	)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	player.setup()


func on_velocity_computed(safe_velocity: Vector3, man: Man) -> void:
	man.safe_velocity = safe_velocity


func actor_setup() -> void:
	await get_tree().physics_frame
	for man in men:
		if man.patrol:
			man.navigation_agent.set_target_position((patrol.get_child(0) as Node3D).position)


func _input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed("ui_cancel"):
		get_tree().quit() # Quits the game
	var motion := event as InputEventMouseMotion
	if motion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		player.rotate_head(motion.relative)
	if event.is_action_pressed("change_mouse_input"):
		match Input.get_mouse_mode():
			Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			Input.MOUSE_MODE_VISIBLE:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# Capture mouse if clicked on the game, needed for HTML5
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
		and Global.time() - player.m_16.last_fired_at > 0.1
	):
		for man: Man in men:
			if (
				is_instance_valid(man)
				and can_man_see_point(man, player.camera.global_position)
				and not player_hunted
			):
				hunt_player()
				log_message(
					"<%s> I think %s is possessed by the demon, engaging!"
					% [man.name, possessed_man_name]
				)
				break
		gun_shot_audio_stream_player.play()
		var hit := fire_m_16(
			player.m_16, player.camera.global_transform, [], true
		)
		if hit:
			var man := hit.get_parent() as Man
			if man:
				var damage := 0.2
				if hit == man.head_hitbox:
					damage = 1.0
					headshot_audio_stream_player.play(4.9)
				hitmarker_audio_stream_player.play(0.1)
				man.health -= damage
				if man.health <= 0.0:
					man.queue_free()
	for man: Man in men:
		if not player_hunted or not is_instance_valid(man):
			continue
		if Global.time() - man.m_16.last_fired_at <= 0.1:
			continue
		var ray_query := PhysicsRayQueryParameters3D.create(
			man.head_hitbox.global_position,
			player.camera.global_position,
		)
		var exclude: Array[Variant] = []
		exclude.append(player.get_rid())
		ray_query.exclude = exclude
		ray_query.collide_with_areas = true
		if not get_world_3d().direct_space_state.intersect_ray(ray_query):
			exclude = []
			for man_2: Man in men:
				if is_instance_valid(man_2):
					exclude.append(man_2.head_hitbox.get_rid())
					exclude.append(man_2.body_hitbox.get_rid())

			var hit := fire_m_16(
				man.m_16, man.m_16.global_transform, exclude, false
			)
			if hit and hit == player:
				damage_audio_stream_player.play()
			man.m_16.last_fired_at = Global.time()

	for m_16: M16 in get_tree().get_nodes_in_group("m_16s"):
		if not is_instance_valid(m_16):
			continue
		m_16.accuracy += 1.5 * delta - m_16.accuracy * delta
		m_16.accuracy = clampf(m_16.accuracy, 0.0, 1.0)

	# Player movement innaccuracy
	var max_accuracy := 1.0
	if player._direction != Vector3.ZERO:
		max_accuracy = 0.9
	if player.sprint_ability._active:
		max_accuracy = 0.6
	player.m_16.accuracy = clampf(player.m_16.accuracy, 0.0, max_accuracy)
	crosshair.scale = Vector2(1.0, 1.0) * (1.0 + 3.0 * (1.0 - player.m_16.accuracy))

	for m_16: M16 in get_tree().get_nodes_in_group("m_16s"):
		if not is_instance_valid(m_16):
			continue
		var reset_velocity := -m_16.position * m_16.accuracy * 5.0
		var velocity := m_16.kick_velocity + reset_velocity
		m_16.position += velocity * delta
		m_16.kick_velocity -= m_16.kick_velocity * delta * 40.0


func process_use() -> void:
	var query := PhysicsRayQueryParameters3D.create(
		player.camera.global_position,
		player.camera.global_position + player.camera.global_basis.z * -10.0
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
						or can_man_see_point(man, player.camera.global_position)
					)
					and not player_hunted
				):
					hunt_player()
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
			player.m_16.visible = true
			player_has_gun = true
			player.m_16.visible = player_has_gun
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


func _physics_process(delta: float) -> void:
	_physics_process_player(delta)
	for man in men:
		if not is_instance_valid(man):
			continue
		var has_nav_target := false
		var look_at_pos := Vector3.ZERO
		var has_look_at_target := false
		if player_hunted:
			has_look_at_target = true
			look_at_pos = player.position
			if Global.time() - man.nav_last_updated_at > 3.0:
				man.nav_last_updated_at = Global.time()
				man.navigation_agent.set_target_position(
					player.global_position
				)
				continue
			elif man.navigation_agent.distance_to_target() > 4.0:
				has_nav_target = true
		elif man.patrol:
			has_nav_target = true
			has_look_at_target = true
			look_at_pos = man.navigation_agent.get_next_path_position()
			if man.navigation_agent.is_navigation_finished():
				man.patrol_index += 1
				man.navigation_agent.set_target_position(
					(
						patrol.get_child(
							man.patrol_index % patrol.get_child_count()
						) as Node3D
					).position
				)
				continue
		if has_look_at_target:
			man.look_at(look_at_pos, Vector3.UP)
			man.rotation.x = 0
			man.rotation.z = 0
			if player_hunted:
				man.m_16.look_at(player.camera.global_position, Vector3.UP)
		if has_nav_target:
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


func _physics_process_player(delta: float) -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("move_fly_mode"):
			player.fly_ability.set_active(not player.fly_ability.is_actived())
		var input_axis := Input.get_vector(
			"move_left",
			"move_right",
			"move_backward",
			"move_forward"
		)
		player.move(
			delta,
			input_axis,
			Input.is_action_just_pressed("move_jump"),
			Input.is_action_pressed("move_crouch"),
			Input.is_action_pressed("move_sprint"),
			Input.is_action_pressed("move_jump"),
			Input.is_action_pressed("move_jump")
		)
	else:
		player.move(delta)


func hunt_player() -> void:
	player_hunted = true
	for man: Man in men:
		if is_instance_valid(man):
			man.m_16.reparent(man.aim_transform, false)


func fire_m_16(
	m_16: M16,
	source: Transform3D,
	ray_exclude: Array[Variant],
	scale_impact_with_distance: bool
) -> Node3D:
	m_16.last_fired_at = Global.time()

	var hit_man: Man
	var hit_anything := false
	var hit_player := false

	var max_spread := 0.2 * (1.0 - m_16.accuracy)
	var dir := (
		source.basis.z
			.rotated(source.basis.x, randf_range(-max_spread, max_spread))
			.rotated(source.basis.y, randf_range(-max_spread, max_spread))
	)

	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = source.origin
	ray_query.to = source.origin + dir * -1000.0

	# TODO: use physics layers instead of ray_exclude list to simplify logic
	ray_exclude = Array(ray_exclude)
	for man: Man in men:
		if is_instance_valid(man):
			ray_exclude.append(man.get_rid())
	ray_query.exclude = ray_exclude
	ray_query.collide_with_areas = true
	var collision := get_world_3d().direct_space_state.intersect_ray(ray_query)

	var hit_position := ray_query.to

	if collision:
		hit_anything = true
		hit_position = collision.position
		var hit: Node3D = collision.collider
		if hit.get_parent() is Man:
			hit_man = hit.get_parent() as Man
		elif hit == player:
			hit_player = true

	if hit_anything and not hit_player:
		var impact_scene := (
			blood_impact_scene if hit_man else bullet_impact_scene
		)
		var impact := impact_scene.instantiate() as GPUParticles3D
		impact.position = hit_position
		impact.emitting = false
		impact.finished.connect(
			func() -> void: impact.queue_free()
		)
		impact.one_shot = true
		impact.emitting = true
		if scale_impact_with_distance:
			impact.scale *= clamp(
				m_16.muzzle_flash.global_position.distance_to(
					hit_position
				) - 1.0,
				1.0,
				3.0
			)
		add_child(impact)

	m_16.muzzle_flash_particles.visible = true
	m_16.muzzle_flash_particles.restart()

	var tracer: Node3D = tracer_scene.instantiate()
	tracer.position = m_16.muzzle_flash.global_position
	tracer.scale.z = (
		m_16.muzzle_flash.global_position.distance_to(hit_position)
	)

	var tracer_particles: GPUParticles3D = (
		tracer.get_node("GPUParticles3D")
	)
	tracer_particles.emitting = false
	tracer_particles.finished.connect(func() -> void: tracer.queue_free())
	tracer_particles.one_shot = true
	tracer_particles.emitting = true

	add_child(tracer)
	tracer.look_at(hit_position, Vector3.UP, true)

	m_16.accuracy -= 0.1 - 0.1 * (1.0 - m_16.accuracy)

	var gun_accel := 0.8
	m_16.kick_velocity += Vector3(
		randf_range(-gun_accel, gun_accel),
		randf_range(-gun_accel, gun_accel),
		gun_accel
	)

	return collision.collider if collision else null
