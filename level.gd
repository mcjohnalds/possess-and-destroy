class_name Level
extends Node3D

enum PhysicsLayers {
	DEFAULT = 1 << 0,
}

enum AiTeamState {
	PATROLLING,
	ENGAGING,
	APPROACHING_LAST_KNOWN_POSITION,
	SEARCHING_RANDOMLY,
	INVESTIGATING_SUSPICIOUS_SOUND,
}

enum AiManState {
	MOVING_TO_PATROL_POSITION,
	PATHING_TO_PATROL_POSITION,
	MOVING_TO_ENGAGE_POSITION,
	PATHING_TO_ENGAGE_POSITION,
	MOVING_TO_LAST_KNOWN_POSITION,
	PATHING_TO_LAST_KNOWN_POSITION,
	MOVING_TO_RANDOM_SEARCH_POSITION,
	PATHING_TO_RANDOM_SEARCH_POSITION,
	MOVING_TO_SUSPICIOUS_SOUND_POSITION,
	PATHING_TO_SUSPICIOUS_SOUND_POSITION,
	PAUSING,
}

enum GunType { M16, SNIPER_RIFLE }

const ENEMY_FOV := 0.42 * TAU
var possessed_man_name := "the civilian"
var player_identity_compromised := false
var ai_team_state_last_frame := AiTeamState.PATROLLING
var can_any_man_see_player_last_frame := false
var suspicious_sound_position: Vector3
var suspicious_sound_heard_at := -10000.0
var suspicious_sound_has_been_investigated := true
@onready var men: Node = $Men
@onready var patrol: Node = $Patrol
@onready var use_label: Label = $UI/UseLabel
@onready var possessing_label: Label = $UI/PossessingLabel
@onready var player: Player = $Player
@onready var bullet_impact_scene := preload("res://bullet_impact.tscn")
@onready var blood_impact_scene := preload("res://blood_impact.tscn")
@onready var tracer_scene := preload("res://tracer.tscn")
@onready var almost_invisible := preload("res://almost_invisible.tres")
@onready var m_16_scene := preload("res://m_16.tscn")
@onready var sniper_rifle_scene := preload("res://sniper_rifle.tscn")
@onready var crosshair := $UI/Crosshair as Control
@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var invisibility_overlay: Control = $UI/InvisibilityOverlay
@onready var vignette: TextureRect = $UI/Vignette
@onready var vignette_gradient_2d: GradientTexture2D = vignette.texture
@onready var vignette_gradient: Gradient = (
	vignette_gradient_2d.gradient
)
@onready var m_16_audio_stream_player := (
	$M16AudioStreamPlayer as AudioStreamPlayer
)
@onready var sniper_rifle_audio_stream_player := (
	$SniperRifleAudioStreamPlayer as AudioStreamPlayer
)
@onready var invisibility_audio_stream_player := (
	$InvisibilityAudioStreamPlayer as AudioStreamPlayer
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
	for man: Man in men.get_children():
		man.navigation_agent.path_desired_distance = 0.5
		man.navigation_agent.target_desired_distance = 0.5
		man.navigation_agent.velocity_computed.connect(on_velocity_computed.bind(man))
	call_deferred("actor_setup")
	for gun: Gun in get_tree().get_nodes_in_group("guns"):
		gun.muzzle_flash_particles.emitting = false
		gun.muzzle_flash_particles.one_shot = true
	player.jumped.connect(func() -> void:
		if player.gun:
			player.gun.accuracy -= 0.5
	)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	player.setup()
	invisibility_overlay.visible = false


func on_velocity_computed(safe_velocity: Vector3, man: Man) -> void:
	man.safe_velocity = safe_velocity


func actor_setup() -> void:
	await get_tree().physics_frame
	for man: Man in men.get_children():
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
	if key and key.keycode == KEY_F and key.pressed:
		player.invisible = not player.invisible
		invisibility_overlay.visible = player.invisible
		if player.gun:
			if player.invisible:
				make_player_gun_invisible()
			else:
				make_player_gun_visible()
			invisibility_audio_stream_player.play(0.9)


func make_player_gun_invisible() -> void:
	for n: Node in player.gun.model.find_children(
		"*", "MeshInstance3D", true, false
	):
		var mesh := n as MeshInstance3D
		if mesh:
			for i in mesh.get_surface_override_material_count():
				mesh.set_surface_override_material(i, almost_invisible)
		else:
			push_error("Invalid state")


func make_player_gun_visible() -> void:
	for n: Node in player.gun.model.find_children(
		"*", "MeshInstance3D", true, false
	):
		var mesh := n as MeshInstance3D
		if mesh:
			for i in mesh.get_surface_override_material_count():
				mesh.set_surface_override_material(i, null)
		else:
			push_error("Invalid state")


# Capture mouse if clicked on the game, needed for HTML5
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if m.button_index == MOUSE_BUTTON_LEFT && m.pressed:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	# print(AiTeamState.keys()[ai_team_state_last_frame])
	# print(AiManState.keys()[(men.get_children()[0] as Man).last_ai_state])
	process_use()
	process_vignette()
	for msg: Message in messages.get_children():
		msg.modulate.a = lerpf(
			1.0,
			0.6,
			clampf((Global.time() - msg.created_at) / 2.0, 0.0, 1.0)
		)
	process_player_shooting()
	process_man_shooting()
	process_guns(delta)


func process_use() -> void:
	# --- Calculations, no side-effects --- #

	var query := PhysicsRayQueryParameters3D.create(
		player.camera.global_position,
		player.camera.global_position + player.camera.global_basis.z * -10.0
	)

	var collision := get_world_3d().direct_space_state.intersect_ray(query)

	var targetted_man: Man
	if collision and collision.collider is Man:
		var man: Man = collision.collider
		if man and man.alive:
			targetted_man = collision.collider


	var target_to_player_dir: Vector3
	if targetted_man:
		target_to_player_dir = (
			targetted_man.global_position.direction_to(player.global_position)
		)

	var targetted_man_rear_dir: Vector3
	if targetted_man:
		targetted_man_rear_dir = targetted_man.global_basis.z

	var behind_target := (
		targetted_man
		and target_to_player_dir.angle_to(targetted_man_rear_dir) < TAU * 0.23
	)

	var possessed := false
	if behind_target and Input.is_action_just_pressed("use"):
		possessed = true

	var possession_witness: Man
	if possessed:
		for man: Man in men.get_children():
			if (
				is_instance_valid(man)
				and man != targetted_man
				and man.alive
				and (
					can_man_see_point(
						man,
						targetted_man.head_hitbox.global_position
					)
					or can_man_see_player(man)
				)
				and not player_identity_compromised
			):
				possession_witness = man
				break

	# --- Side effects ---

	use_label.visible = behind_target

	if possessed:
		possession_audio_stream_player.play(4.9)
		possessed_man_name = targetted_man.name
		# + 0.1 prevents player from falling beneath floor
		player.position = targetted_man.position + 0.1 * Vector3.UP
		player.velocity = Vector3.ZERO
		possessing_label.text = "Possessing: " + targetted_man.name
		player.last_possessed_at = Global.time()
		targetted_man.queue_free()

		if player.gun:
			player.gun.queue_free()
			player.gun_transform.remove_child(player.gun)
		var gun_scene := (
			m_16_scene if targetted_man.gun_type == GunType.M16
			else sniper_rifle_scene
		)
		player.gun = gun_scene.instantiate()
		player.gun_transform.add_child(player.gun)
		if player.invisible:
			make_player_gun_invisible()

		if not possession_witness:
			player_identity_compromised = false

	if possession_witness:
		hunt_player()
		log_message(
			"<%s> I saw the demon possess %s, engaging enemy!"
			% [possession_witness.name, targetted_man.name]
		)


func process_vignette() -> void:
	var d := Global.time() - player.last_possessed_at
	var t := minf(d / 0.1, 1.0)
	var a1 := lerpf(0.8, 0.0, t)
	var a2 := lerpf(1.0, 0.3, t)
	vignette_gradient.set_color(0, Color(0.0, 0.0, 0.0, a1))
	vignette_gradient.set_color(1, Color(0.0, 0.0, 0.0, a2))


func process_player_shooting() -> void:
	if (
		player.gun
		and Input.is_action_pressed("primary")
		and Global.time() - player.gun.last_fired_at
			> get_gun_cooldown(player.gun)
	):
		get_gun_audio_stream_player(player.gun).play()
		var hit := fire_gun(
			player.gun, player.camera.global_transform, [], true
		)
		if hit:
			var man := hit.get_parent() as Man
			if man and man.alive:
				var damage := get_gun_damage(player.gun)
				if hit == man.head_hitbox:
					damage = damage * 5.0
					headshot_audio_stream_player.play(0.085)
				hitmarker_audio_stream_player.play(0.1)
				man.health -= damage
				if man.health <= 0.0:
					man.alive = false
					man.died_at = Global.time()
					man.collision_layer = 0
					man.collision_mask = 0
		suspicious_sound_position = player.global_position
		suspicious_sound_heard_at = Global.time()
		suspicious_sound_has_been_investigated  = false


func process_man_shooting() -> void:
	for man: Man in men.get_children():
		if not is_instance_valid(man) or not man.alive:
			continue
		if not man.alive and Global.time() - man.died_at > 5.0:
			man.queue_free()
			continue
		var fired_recently := (
			Global.time() - man.gun.last_fired_at <= get_gun_cooldown(man.gun)
		)
		var can_fire := (
			player_identity_compromised
			and not fired_recently
			and can_man_see_player(man)
		)
		if can_fire:
			var exclude: Array[Variant] = []
			for man_2: Man in men.get_children():
				if is_instance_valid(man_2):
					exclude.append(man_2.head_hitbox.get_rid())
					exclude.append(man_2.body_hitbox.get_rid())

			var hit := fire_gun(
				man.gun, man.gun.global_transform, exclude, false
			)
			if hit and hit == player:
				damage_audio_stream_player.play()
			man.gun.last_fired_at = Global.time()
			man.gun.gun_shot_audio_stream_player.play()


func process_guns(delta: float) -> void:
	for gun: Gun in get_tree().get_nodes_in_group("guns"):
		if not is_instance_valid(gun):
			continue
		gun.accuracy += 1.5 * delta - gun.accuracy * delta
		gun.accuracy = clampf(gun.accuracy, 0.0, 1.0)

	# Player movement innaccuracy
	var max_accuracy := 1.0
	if player._direction != Vector3.ZERO:
		max_accuracy = 0.9
	if player.sprint_ability._active:
		max_accuracy = 0.6
	if player.gun:
		player.gun.accuracy = clampf(
			player.gun.accuracy, 0.0, max_accuracy
		)
		crosshair.scale = (
			Vector2(1.0, 1.0) * (1.0 + 3.0 * (1.0 - player.gun.accuracy))
		)

	for gun: Gun in get_tree().get_nodes_in_group("guns"):
		if not is_instance_valid(gun):
			continue
		var reset_velocity := -gun.position * gun.accuracy * 5.0
		var velocity := gun.kick_velocity + reset_velocity
		gun.position += velocity * delta
		gun.kick_velocity -= gun.kick_velocity * delta * 40.0


func can_man_see_player(man: Man) -> bool:
	return (
		not player.invisible
		and can_man_see_point(man, player.camera.global_position)
	)


func can_man_see_point(man: Man, point: Vector3) -> bool:
	var exclude: Array[Variant] = []
	exclude.append(player.get_rid())
	for man2: Man in men.get_children():
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
	physics_process_man(delta)


func physics_process_man(delta: float) -> void:
	# --- Calculations, no state or side-effects ---

	var can_any_man_see_player := false
	for man: Man in men.get_children():
		if is_instance_valid(man) and man.alive and can_man_see_player(man):
			can_any_man_see_player = true

	var player_shooting_witnessed_this_frame := false
	var name_of_player_shooting_witness: String
	for man: Man in men.get_children():
		if (
			is_instance_valid(man)
			and man.alive
			and can_man_see_player(man)
			and Global.time() - suspicious_sound_heard_at < 3.0
			and player.last_possessed_at < suspicious_sound_heard_at
			and not player_identity_compromised
		):
			player_shooting_witnessed_this_frame = true
			name_of_player_shooting_witness = man.name

	var spotted_this_frame := (
		can_any_man_see_player and not can_any_man_see_player_last_frame 
	)

	var valid_men_names: Array[String] = []
	for man: Man in men.get_children():
		if is_instance_valid(man) and man.alive:
			valid_men_names.append(man.name)

	var random_man_name: String
	if valid_men_names.size() > 0:
		random_man_name = valid_men_names.pick_random()

	var max_team_search_duration_exceeded := (
		Global.time() - suspicious_sound_heard_at > 20.0
		and (
			not player_identity_compromised
			or Global.time() - player.last_seen_at > 20.0
		)
	)

	var last_known_position_has_been_visited_last_frame := false
	for man: Man in men.get_children():
		if (
			man.last_ai_state == AiManState.MOVING_TO_LAST_KNOWN_POSITION
			and man.navigation_agent.is_navigation_finished()
		):
			last_known_position_has_been_visited_last_frame = true

	var suspicious_sound_was_visited_last_frame := false
	for man: Man in men.get_children():
		if (
			man.last_ai_state == AiManState.MOVING_TO_SUSPICIOUS_SOUND_POSITION
			and man.navigation_agent.is_navigation_finished()
		):
			suspicious_sound_was_visited_last_frame = true

	var ai_team_state := (
		AiTeamState.ENGAGING if
			player_identity_compromised
			and (
				spotted_this_frame or Global.time() - player.last_seen_at < 4.0
			)
			or player_shooting_witnessed_this_frame
		else AiTeamState.INVESTIGATING_SUSPICIOUS_SOUND if
			Global.time() - suspicious_sound_heard_at < 20.0
			and not suspicious_sound_was_visited_last_frame
			and not suspicious_sound_has_been_investigated
		else AiTeamState.SEARCHING_RANDOMLY if
			ai_team_state_last_frame == AiTeamState.SEARCHING_RANDOMLY
			and not max_team_search_duration_exceeded
			or ai_team_state_last_frame
				== AiTeamState.APPROACHING_LAST_KNOWN_POSITION
			and last_known_position_has_been_visited_last_frame
			or ai_team_state_last_frame
				== AiTeamState.INVESTIGATING_SUSPICIOUS_SOUND
		else AiTeamState.APPROACHING_LAST_KNOWN_POSITION if
			ai_team_state_last_frame
				== AiTeamState.APPROACHING_LAST_KNOWN_POSITION
			and not max_team_search_duration_exceeded
			or ai_team_state_last_frame == AiTeamState.ENGAGING
		else AiTeamState.PATROLLING
	)

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

	var began_investigating_suspicious_sound_this_frame := (
		ai_team_state_last_frame != AiTeamState.INVESTIGATING_SUSPICIOUS_SOUND
		and ai_team_state == AiTeamState.INVESTIGATING_SUSPICIOUS_SOUND
	)

	var stopped_investigating_suspicious_sound_this_frame := (
		ai_team_state_last_frame == AiTeamState.INVESTIGATING_SUSPICIOUS_SOUND
		and ai_team_state != AiTeamState.INVESTIGATING_SUSPICIOUS_SOUND
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
		if began_investigating_suspicious_sound_this_frame:
			message = (
				"<%s> I heard a suspicious sound, investigating"
				% random_man_name
			)
		if player_shooting_witnessed_this_frame:
			message = (
				"<%s> I think %s is possessed by the demon, engaging!"
				% [name_of_player_shooting_witness, possessed_man_name]
			)

	for man: Man in men.get_children():
		if not is_instance_valid(man):
			continue

		var nav_finished := man.navigation_agent.is_navigation_finished()

		var next_path_pos := man.navigation_agent.get_next_path_position()

		var man_pos := man.global_position

		var search_duration := Global.time() - man.nav_last_updated_at

		var random_search_duration := lerpf(
			5.0, 10.0, hash_int_to_random_float(man.get_index())
		)

		var pathing_cooldown := search_duration < 3.0

		var ai_state := (
			AiManState.MOVING_TO_ENGAGE_POSITION if
				man.alive
				and ai_team_state == AiTeamState.ENGAGING
				and pathing_cooldown
			else AiManState.PATHING_TO_ENGAGE_POSITION if
				man.alive
				and ai_team_state == AiTeamState.ENGAGING
			else AiManState.MOVING_TO_SUSPICIOUS_SOUND_POSITION if
				man.alive
				and ai_team_state
					== AiTeamState.INVESTIGATING_SUSPICIOUS_SOUND
				and ai_team_state_last_frame
					== AiTeamState.INVESTIGATING_SUSPICIOUS_SOUND
				and not nav_finished
				and search_duration < 20.0
			else AiManState.PATHING_TO_SUSPICIOUS_SOUND_POSITION if
				man.alive
				and began_investigating_suspicious_sound_this_frame
			else AiManState.MOVING_TO_RANDOM_SEARCH_POSITION if
				man.alive
				and ai_team_state == AiTeamState.SEARCHING_RANDOMLY
				and not nav_finished
				and search_duration < random_search_duration
			else AiManState.PATHING_TO_RANDOM_SEARCH_POSITION if
				man.alive
				and ai_team_state == AiTeamState.SEARCHING_RANDOMLY
				and not pathing_cooldown
			else AiManState.MOVING_TO_LAST_KNOWN_POSITION if
				man.alive
				and ai_team_state
					== AiTeamState.APPROACHING_LAST_KNOWN_POSITION
				and not nav_finished
				and search_duration < 20.0
			else AiManState.PATHING_TO_RANDOM_SEARCH_POSITION if
				man.alive
				and ai_team_state
					== AiTeamState.APPROACHING_LAST_KNOWN_POSITION
			else AiManState.MOVING_TO_PATROL_POSITION if
				man.alive
				and man.patrol
				and ai_team_state == AiTeamState.PATROLLING
				and not nav_finished
				and search_duration < 20.0
			else AiManState.PATHING_TO_PATROL_POSITION if
				man.alive
				and man.patrol
				and ai_team_state == AiTeamState.PATROLLING
				and not pathing_cooldown
			else AiManState.PAUSING
		)

		var random_dist := 10.0
		var random_search_pos := man_pos + Vector3(
			(1 if randi() % 2 == 0 else -1) * random_dist,
			(1 if randi() % 2 == 0 else -1) * random_dist,
			(1 if randi() % 2 == 0 else -1) * random_dist,
		)


		var has_new_nav_target := false
		var new_nav_target: Vector3
		var has_look_at_target := false
		var look_at_target: Vector3
		var has_nav_target := false
		var has_aim_target := false

		match ai_state:
			AiManState.MOVING_TO_PATROL_POSITION:
				has_nav_target = true
				has_look_at_target = true
				look_at_target = next_path_pos
			AiManState.PATHING_TO_PATROL_POSITION:
				has_new_nav_target = true
				var patrol_node: Node3D = patrol.get_child(man.patrol_index)
				new_nav_target = patrol_node.position
			AiManState.MOVING_TO_ENGAGE_POSITION:
				has_nav_target = true
				has_look_at_target = true
				look_at_target = player.last_known_position
				has_aim_target = true
			AiManState.PATHING_TO_ENGAGE_POSITION:
				has_new_nav_target = true
				new_nav_target = player.last_known_position
				has_look_at_target = true
				look_at_target = player.last_known_position
				has_aim_target = true
			AiManState.MOVING_TO_LAST_KNOWN_POSITION:
				has_nav_target = true
				has_look_at_target = true
				look_at_target = player.last_known_position
			AiManState.PATHING_TO_LAST_KNOWN_POSITION:
				has_new_nav_target = true
				new_nav_target = player.last_known_position
			AiManState.MOVING_TO_RANDOM_SEARCH_POSITION:
				has_nav_target = true
				has_look_at_target = true
				look_at_target = next_path_pos
			AiManState.PATHING_TO_RANDOM_SEARCH_POSITION:
				has_new_nav_target = true
				new_nav_target = random_search_pos
			AiManState.MOVING_TO_SUSPICIOUS_SOUND_POSITION:
				has_nav_target = true
				has_look_at_target = true
				look_at_target = suspicious_sound_position
			AiManState.PATHING_TO_SUSPICIOUS_SOUND_POSITION:
				has_new_nav_target = true
				new_nav_target = suspicious_sound_position
			AiManState.PAUSING:
				pass

		var next_patrol_index := (
			(man.patrol_index + 1) % patrol.get_child_count()
				if ai_state == AiManState.PATHING_TO_PATROL_POSITION
			else man.patrol_index
		)

		var velocity := Vector3(0.0, man.velocity.y - 9.8 * delta, 0.0)
		if man.alive:
			velocity += Vector3(man.safe_velocity.x, 0.0, man.safe_velocity.z)
			if has_nav_target:
				var dir := man.global_position.direction_to(next_path_pos)
				velocity += dir * 4.0
		if man.is_on_floor():
			velocity.y = 0.0

		# --- Side effects ---

		man.patrol_index = next_patrol_index
		if has_new_nav_target:
			man.navigation_agent.set_target_position(new_nav_target)
			man.nav_last_updated_at = Global.time()
		if has_look_at_target:
			man.look_at(look_at_target, Vector3.UP)
		man.rotation.x = 0
		man.rotation.z = 0
		if has_aim_target:
			man.gun.look_at(player.last_known_position, Vector3.UP)
		else:
			man.gun.rotation.x = 0
			man.gun.rotation.y = 0
			man.gun.rotation.z = 0
		man.velocity = velocity
		# man.safe_velocity = Vector3.ZERO
		man.move_and_slide()
		man.last_ai_state = ai_state

	if player_shooting_witnessed_this_frame:
		hunt_player()

	if can_any_man_see_player:
		player.last_known_position = player.global_position
		player.last_seen_at = Global.time()

	if (
		stopped_investigating_suspicious_sound_this_frame
		or ai_team_state == AiTeamState.ENGAGING
	):
		suspicious_sound_has_been_investigated = true

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
		var c := messages.get_child(0)
		c.queue_free()
		messages.remove_child(c)
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
	for man: Man in men.get_children():
		if is_instance_valid(man) and man.alive:
			man.gun.reparent(man.aim_transform, false)


func fire_gun(
	gun: Gun,
	source: Transform3D,
	ray_exclude: Array[Variant],
	scale_impact_with_distance: bool
) -> Node3D:
	gun.last_fired_at = Global.time()

	var hit_man: Man
	var hit_anything := false
	var hit_player := false

	var max_spread := 0.2 * (1.0 - gun.accuracy)
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
	for man: Man in men.get_children():
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
				gun.muzzle_flash.global_position.distance_to(
					hit_position
				) - 1.0,
				1.0,
				3.0
			)
		add_child(impact)

	gun.muzzle_flash_particles.emitting = true
	gun.muzzle_flash_particles.restart()

	var tracer: Node3D = tracer_scene.instantiate()
	tracer.position = gun.muzzle_flash.global_position
	tracer.scale.z = (
		gun.muzzle_flash.global_position.distance_to(hit_position)
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

	gun.accuracy -= 0.1 - 0.1 * (1.0 - gun.accuracy)

	var gun_accel := 0.8
	gun.kick_velocity += Vector3(
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


func get_gun_cooldown(gun: Gun) -> float:
	match gun.gun_type:
		Level.GunType.M16:
			return 0.1
		Level.GunType.SNIPER_RIFLE:
			return 2.3
	push_error("Unhandled state")
	return 1.0


func get_gun_damage(gun: Gun) -> float:
	match gun.gun_type:
		Level.GunType.M16:
			return 0.2
		Level.GunType.SNIPER_RIFLE:
			return 2.0
	push_error("Unhandled state")
	return 1.0


func get_gun_audio_stream_player(gun: Gun) -> AudioStreamPlayer:
	match gun.gun_type:
		Level.GunType.M16:
			return m_16_audio_stream_player
		Level.GunType.SNIPER_RIFLE:
			return sniper_rifle_audio_stream_player
	push_error("Unhandled state")
	return null
