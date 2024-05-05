extends Node3D

enum PhysicsLayers {
	DEFAULT = 1 << 0,
}

enum AiTeamState {
	PATROLLING, ENGAGING, APPROACHING_LAST_KNOWN_POSITION, SEARCHING_RANDOMLY
}

const ENEMY_FOV := 0.45 * TAU
var men: Array[Man] = []
var player_has_gun := false
var possessed_man_name := "the civilian"
var player_identity_compromised := false
var any_enemy_approached_last_known_position := false
var ai_team_state_last_frame := AiTeamState.PATROLLING
var can_any_man_see_player_last_frame := false
@onready var patrol: Node = $Patrol
@onready var use_label: Label = $UI/UseLabel
@onready var possessing_label: Label = $UI/PossessingLabel
@onready var player: Player = $Player
@onready var bullet_impact_scene := preload("res://bullet_impact.tscn")
@onready var blood_impact_scene := preload("res://blood_impact.tscn")
@onready var tracer_scene := preload("res://tracer.tscn")
@onready var crosshair := $UI/Crosshair as Control
@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
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


func _ready() -> void:
	men.assign($Men.get_children())
	for man in men:
		man.navigation_agent.path_desired_distance = 0.5
		man.navigation_agent.target_desired_distance = 0.5
		man.navigation_agent.velocity_computed.connect(on_velocity_computed.bind(man))
	call_deferred("actor_setup")
	player.m_16.visible = player_has_gun
	for m_16: M16 in get_tree().get_nodes_in_group("m_16s"):
		m_16.muzzle_flash_particles.emitting = false
		m_16.muzzle_flash_particles.one_shot = true
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
	var key := event as InputEventKey
	if key and key.keycode == KEY_I and key.pressed:
		player.invisible = not player.invisible


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
				and can_man_see_player(man)
				and not player_identity_compromised
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
		if not is_instance_valid(man):
			continue
		var fired_recently := Global.time() - man.m_16.last_fired_at <= 0.1
		var can_fire := (
			player_identity_compromised
			and not fired_recently
			and can_man_see_player(man)
		)
		if can_fire:
			var exclude: Array[Variant] = []
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
						or can_man_see_player(man)
					)
					and not player_identity_compromised
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


func can_man_see_player(man: Man) -> bool:
	return (
		not player.invisible
		and can_man_see_point(man, player.camera.global_position)
	)


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
	physics_process_player(delta)

	# --- Calculations, no state or side-effects ---

	var can_any_man_see_player := false
	for man in men:
		if not is_instance_valid(man):
			continue
		if can_man_see_player(man):
			can_any_man_see_player = true
			break

	var player_hunted := (
		player_identity_compromised
		and Global.time() - player.last_seen_at < 20.0
	)
	var searching := player_hunted and not can_any_man_see_player

	var spotted_this_frame := (
		can_any_man_see_player and not can_any_man_see_player_last_frame 
	)

	var valid_men_names: Array[String] = []
	for man: Man in men:
		if is_instance_valid(man):
			valid_men_names.append(man.name)

	var random_man_name: String
	if valid_men_names.size() > 0:
		random_man_name = valid_men_names.pick_random()

	# TODO: use this var in the logic
	var ai_team_state: AiTeamState
	if player_hunted and can_any_man_see_player:
		ai_team_state = AiTeamState.ENGAGING
	elif searching:
		if any_enemy_approached_last_known_position:
			ai_team_state = AiTeamState.SEARCHING_RANDOMLY
		else:
			ai_team_state = AiTeamState.APPROACHING_LAST_KNOWN_POSITION
	else:
		ai_team_state = AiTeamState.PATROLLING

	var began_engaging_player_this_frame_due_to_spotting := (
		ai_team_state_last_frame != AiTeamState.ENGAGING
		and ai_team_state == AiTeamState.ENGAGING
		and spotted_this_frame
	)

	var began_approaching_last_known_position_this_frame := (
		ai_team_state_last_frame != AiTeamState.APPROACHING_LAST_KNOWN_POSITION
		and ai_team_state == AiTeamState.APPROACHING_LAST_KNOWN_POSITION
	)

	var began_searching_randomly_for_player_this_frame := (
		ai_team_state_last_frame != AiTeamState.SEARCHING_RANDOMLY
		and ai_team_state == AiTeamState.SEARCHING_RANDOMLY
	)

	var stopped_hunting_player_this_frame := (
		ai_team_state_last_frame != AiTeamState.PATROLLING
		and ai_team_state == AiTeamState.PATROLLING
	)

	var message: String
	if random_man_name:
		if began_engaging_player_this_frame_due_to_spotting:
			message = (
				"<%s> Demon spotted, engaging!"
					% random_man_name
			)
		if began_approaching_last_known_position_this_frame:
			message = (
				"<%s> Lost eyes on the demon, approaching last known position"
				% random_man_name
			)
		if began_searching_randomly_for_player_this_frame:
			message = (
				"<%s> Searching area for the demon"
				% random_man_name
			)
		if stopped_hunting_player_this_frame:
			message = (
				"<%s> Can't find the demon, returning to patrol"
				% random_man_name
			)

	for man in men:
		if not is_instance_valid(man):
			continue

		var nav_finished := man.navigation_agent.is_navigation_finished()
		var next_path_pos := man.navigation_agent.get_next_path_position()
		var aim_at_player := player_identity_compromised and can_any_man_see_player
		var man_pos := man.global_position
		var search_duration := Global.time() - man.nav_last_updated_at
		var max_search_duration := lerpf(
			5.0, 10.0, hash_int_to_random_float(man.get_index())
		)

		var patrolling := not player_hunted and man.patrol

		var next_patrol_node := patrolling and nav_finished

		var approaching_last_known_position := (
			searching
			and not any_enemy_approached_last_known_position
		)

		var finished_approaching_last_known_position := (
			approaching_last_known_position
			and (nav_finished or search_duration > 20.0)
		)

		var pausing_before_picking_new_search_pos := (
			searching
			and search_duration > max_search_duration / 2.0
			and search_duration < max_search_duration
			and not approaching_last_known_position
		)

		var pick_new_search_pos := (
			searching
			and not pausing_before_picking_new_search_pos
			and search_duration > max_search_duration
		)

		var random_dist := 10.0
		var random_search_pos := man_pos + Vector3(
			(1 if randi() % 2 == 0 else -1) * random_dist,
			(1 if randi() % 2 == 0 else -1) * random_dist,
			(1 if randi() % 2 == 0 else -1) * random_dist,
		)

		var has_new_nav_target := false
		var new_nav_target: Vector3
		if search_duration > 1.0:
			if searching:
				if pick_new_search_pos:
					if any_enemy_approached_last_known_position:
						has_new_nav_target = true
						new_nav_target = random_search_pos
					else:
						has_new_nav_target = true
						new_nav_target = player.last_known_position
			elif player_hunted:
				has_new_nav_target = true
				new_nav_target = player.global_position
			elif next_patrol_node:
				has_new_nav_target = true
				var patrol_node: Node3D = patrol.get_child(man.patrol_index)
				new_nav_target = patrol_node.position

		var has_nav_target := (
			not has_new_nav_target
			and not nav_finished
			and not pausing_before_picking_new_search_pos
			and (patrolling or player_hunted)
		)

		var has_look_at_pos := false
		var look_at_pos: Vector3
		if player_hunted and can_any_man_see_player:
			has_look_at_pos = true
			look_at_pos = player.global_position
		elif has_nav_target:
			has_look_at_pos = true
			look_at_pos = next_path_pos

		var velocity := man.safe_velocity 
		if has_nav_target:
			var dir := man.global_position.direction_to(next_path_pos)
			velocity += dir * 4.0

		# --- Side effects ---
		if finished_approaching_last_known_position:
			any_enemy_approached_last_known_position = true
		if next_patrol_node:
			man.patrol_index += 1
			man.patrol_index = man.patrol_index % patrol.get_child_count()
		if has_new_nav_target:
			man.navigation_agent.set_target_position(new_nav_target)
			man.nav_last_updated_at = Global.time()
		if has_look_at_pos:
			man.look_at(look_at_pos, Vector3.UP)
		man.rotation.x = 0
		man.rotation.z = 0
		if aim_at_player:
			man.m_16.look_at(player.global_position, Vector3.UP)
		else:
			man.m_16.rotation.x = 0
			man.m_16.rotation.y = 0
			man.m_16.rotation.z = 0
		man.velocity = velocity
		man.move_and_slide()

	if can_any_man_see_player:
		player.last_known_position = player.global_position
		player.last_seen_at = Global.time()
		any_enemy_approached_last_known_position = false

	if message:
		log_message(message)
	ai_team_state_last_frame = ai_team_state
	can_any_man_see_player_last_frame = can_any_man_see_player


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


func physics_process_player(delta: float) -> void:
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
	player_identity_compromised = true
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

	m_16.muzzle_flash_particles.emitting = true
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


func hash_int_to_random_float(value: int) -> float:
    # Linear congruential generator (LCG)
	var s := value * 1103515245 + 12345
	s = s % 2147483647
	return float(s) / 2147483647.0
