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
	MOVING_TO_FOLLOW_TARGET,
	PATHING_TO_FOLLOW_TARGET,
	MOVING_TO_INITIAL_POSITION,
	PATHING_TO_INITIAL_POSITION,
	REACHED_INITIAL_POSITION,
	MOVING_TO_ENGAGE_POSITION,
	PATHING_TO_ENGAGE_POSITION,
	MOVING_TO_LAST_KNOWN_POSITION,
	PATHING_TO_LAST_KNOWN_POSITION,
	MOVING_TO_RANDOM_SEARCH_POSITION,
	PATHING_TO_RANDOM_SEARCH_POSITION,
	MOVING_TO_SUSPICIOUS_SOUND_POSITION,
	PATHING_TO_SUSPICIOUS_SOUND_POSITION,
	PAUSING,
	ENGAGING_PLAYER_WHILE_STANDING_STILL,
	PAUSING_TO_LOOK_AT_PLAYER,
}

enum GunType { M16, SNIPER_RIFLE, SHOTGUN }


class BulletHit:
	var collider: Node3D
	var position: Vector3


const LOOKING_SUSPICIOUS_DURATION := 6.0
const ENEMY_FOV := 0.42 * TAU
const POSSESSION_ENERGY_COST := 0.25
const INVISIBILITY_ENERGY_COST := 0.25
const KILL_ENERGY_GAIN := 0.2
var possessed_man_name := "the civilian"
var player_identity_compromised := false
var ai_team_state_last_frame := AiTeamState.PATROLLING
var can_any_man_see_player_last_frame := false
var suspicious_sound_position: Vector3
var suspicious_sound_heard_at := -10000.0
var suspicious_sound_has_been_investigated := true
@onready var men: Node = $Men
@onready var patrol: Node = $Patrol
@onready var player: Player = $Player
@onready var bullet_impact_scene := preload("res://bullet_impact.tscn")
@onready var blood_impact_scene := preload("res://blood_impact.tscn")
@onready var tracer_scene := preload("res://tracer.tscn")
@onready var almost_invisible := preload("res://almost_invisible.tres")
@onready var m_16_scene := preload("res://m_16.tscn")
@onready var sniper_rifle_scene := preload("res://sniper_rifle.tscn")
@onready var shotgun_scene := preload("res://shotgun.tscn")
@onready var world_environment: WorldEnvironment = $Lighting/WorldEnvironment
@onready var hescos: Node3D = $NavigationRegion3D/Hescos


func _ready() -> void:
	world_environment.environment.sdfgi_enabled = true
	for hesco: Hesco in hescos.get_children():
		hesco.rotate_y(randi_range(0, 3) * TAU / 4.0 + randf_range(-0.01, 0.01) * TAU)
		hesco.rotate_x(randf_range(-0.005, 0.005) * TAU)
		hesco.rotate_z(randf_range(-0.005, 0.005) * TAU)
		hesco.global_position.x += randf_range(-0.02, 0.02)
		hesco.global_position.z += randf_range(-0.02, 0.02)
		hesco.model.scale.x *= 1.0 + randf_range(-0.02, 0.02)
		hesco.model.scale.y *= 1.0 + randf_range(-0.02, 0.02)
		hesco.model.scale.z *= 1.0 + randf_range(-0.02, 0.02)
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
	player.invisibility_overlay.visible = false


func on_velocity_computed(safe_velocity: Vector3, man: Man) -> void:
	man.safe_velocity = safe_velocity


func actor_setup() -> void:
	await get_tree().physics_frame
	for man: Man in men.get_children():
		if man.mode == Man.Mode.Patrol:
			man.navigation_agent.set_target_position(
				(patrol.get_child(0) as Node3D).global_position
			)


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
	if (
		key
		and key.keycode == KEY_F
		and key.pressed
		and player.energy >= INVISIBILITY_ENERGY_COST
	):
		if player.invisible:
			make_player_visible()
		else:
			make_player_invisible()


func make_player_invisible() -> void:
		player.energy -= INVISIBILITY_ENERGY_COST
		player.invisible = true
		player.invisibility_overlay.visible = true
		if player.gun:
			apply_material_to_player_gun(almost_invisible)
			player.invisibility_audio_stream_player.play(0.9)


func make_player_visible() -> void:
		player.invisible = false
		player.invisibility_overlay.visible = false
		if player.gun:
			apply_material_to_player_gun(null)
			player.invisibility_audio_stream_player.play(0.9)
		for man: Man in men.get_children():
			if (
				is_instance_valid(man)
				and man.alive
				and can_man_see_player(man)
				and not player_identity_compromised
			):
				hunt_player()
				log_message(
					"<%s> I saw %s doing demon stuff, engaging!"
					% [man.name, possessed_man_name]
				)
				break


func apply_material_to_player_gun(material: Material) -> void:
	for n: Node in player.gun.model.find_children(
		"*", "MeshInstance3D", true, false
	):
		var mesh := n as MeshInstance3D
		if mesh:
			for i in mesh.get_surface_override_material_count():
				mesh.set_surface_override_material(i, material)
		else:
			push_error("Invalid state")


# Capture mouse if clicked on the game, needed for HTML5
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("primary"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	player.health_label.text = "Health: %s%%" % ceilf(
		player.health / player.initial_health * 100.0
	)
	player.energy_label.text = "Energy: %s%%" % ceilf(
		player.energy * 100.0
	)
	player.compromised_control.visible = player_identity_compromised
	player.hurt_overlay.modulate.a -= delta
	player.hurt_overlay.modulate.a = clampf(
		player.hurt_overlay.modulate.a, 0.0, 1.0
	)
	player.suspicious_label.visible = (
		Level.get_ticks_sec() - suspicious_sound_heard_at
		< LOOKING_SUSPICIOUS_DURATION
	)
	process_use()
	process_zoom()
	process_vignette()
	for msg: Message in player.messages.get_children():
		msg.modulate.a = lerpf(
			1.0,
			0.6,
			clampf((Level.get_ticks_sec() - msg.created_at) / 2.0, 0.0, 1.0)
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

	var targeted_man: Man
	if collision and collision.collider is Man:
		var man: Man = collision.collider
		if man and man.alive:
			targeted_man = collision.collider


	var target_to_player_dir: Vector3
	if targeted_man:
		target_to_player_dir = (
			targeted_man.global_position.direction_to(player.global_position)
		)

	var targeted_man_rear_dir: Vector3
	if targeted_man:
		targeted_man_rear_dir = targeted_man.global_basis.z

	var behind_target := (
		targeted_man
		and target_to_player_dir.angle_to(targeted_man_rear_dir) < TAU * 0.23
	)

	var possessed := (
		behind_target
		and Input.is_action_just_pressed("use")
		and player.energy >= POSSESSION_ENERGY_COST
	)

	var possession_witness: Man
	if possessed:
		for man: Man in men.get_children():
			if (
				is_instance_valid(man)
				and man != targeted_man
				and man.alive
				and (
					can_man_see_point(
						man,
						targeted_man.head_hitbox.global_position
					)
					or can_man_see_player(man)
				)
			):
				possession_witness = man
				break

	# --- Side effects ---

	player.use_label.visible = behind_target

	if possessed:
		player.possession_audio_stream_player.play(4.9)
		possessed_man_name = targeted_man.name
		player.global_position = (
			# + player height / 2 because player origin is different to enemy
			# origin
			targeted_man.global_position
				+ player.capsule.height / 2.0 * Vector3.UP
		)
		player.velocity = Vector3.ZERO
		player.possessing_label.text = "Possessing: " + targeted_man.name
		player.last_possessed_at = Level.get_ticks_sec()
		targeted_man.queue_free()
		targeted_man.alive = false
		make_followers_stationary(targeted_man)

		if player.gun:
			player.gun.queue_free()
			player.gun_transform.remove_child(player.gun)
		var gun_scene := (
			m_16_scene
				if targeted_man.gun_type == GunType.M16
			else sniper_rifle_scene
				if targeted_man.gun_type == GunType.SNIPER_RIFLE
			else shotgun_scene
		)
		player.gun = gun_scene.instantiate()
		player.gun_transform.add_child(player.gun)
		if player.invisible:
			apply_material_to_player_gun(almost_invisible)

		player.energy -= POSSESSION_ENERGY_COST

		player_identity_compromised = possession_witness != null

		if possession_witness:
			hunt_player()
			log_message(
				"<%s> I saw the demon possess %s, engaging enemy!"
				% [possession_witness.name, targeted_man.name]
			)

		if player.invisible:
			make_player_visible()


func process_vignette() -> void:
	var d := Level.get_ticks_sec() - player.last_possessed_at
	var t := minf(d / 0.1, 1.0)
	var a1 := lerpf(0.8, 0.0, t)
	var a2 := lerpf(1.0, 0.3, t)
	player.vignette_gradient.set_color(0, Color(0.0, 0.0, 0.0, a1))
	player.vignette_gradient.set_color(1, Color(0.0, 0.0, 0.0, a2))


func process_player_shooting() -> void:
	if (
		player.gun
		and Input.is_action_pressed("primary")
		and Level.get_ticks_sec() - player.gun.last_fired_at
			> get_gun_cooldown(player.gun)
	):
		get_gun_audio_stream_player(player.gun).play()
		var hits := fire_gun(
			player.gun, player.camera.global_transform, [], true
		)
		var hit_man := false
		var headshot := false
		for hit in hits:
			var man := hit.collider.get_parent() as Man
			if man and man.alive:
				hit_man = true
				if hit.collider == man.head_hitbox:
					headshot = true
				var distance := (player.gun.muzzle_flash.global_position
					.distance_to(hit.position))
				var damage := get_gun_damage(player.gun, distance, headshot)
				man.health -= damage
				if man.health <= 0.0:
					player.energy = clampf(
						player.energy + KILL_ENERGY_GAIN, 0.0, 1.0
					)
					man.alive = false
					make_followers_stationary(man)
					man.died_at = Level.get_ticks_sec()
					man.gun.gun_shot_audio_stream_player.stop()
					man.collision_layer = 0
					man.collision_mask = 0
		if hit_man:
			player.hitmarker_audio_stream_player.play(0.1)
		if headshot:
			player.headshot_audio_stream_player.play(0.085)
		suspicious_sound_position = player.global_position
		suspicious_sound_heard_at = Level.get_ticks_sec()
		suspicious_sound_has_been_investigated  = false
		if player.invisible:
			make_player_visible()


func process_man_shooting() -> void:
	for man: Man in men.get_children():
		if not is_instance_valid(man) or not man.alive:
			continue
		if not man.alive and Level.get_ticks_sec() - man.died_at > 5.0:
			man.queue_free()
			continue
		var fired_recently := (
			Level.get_ticks_sec() - man.gun.last_fired_at <= get_gun_cooldown(man.gun)
		)
		var can_fire := (
			player_identity_compromised
			and not fired_recently
			and can_man_see_player(man)
			and man.aim_progress >= 1.0
		)
		if can_fire:
			var exclude: Array[Variant] = []
			for man_2: Man in men.get_children():
				if is_instance_valid(man_2):
					exclude.append(man_2.head_hitbox.get_rid())
					exclude.append(man_2.body_hitbox.get_rid())

			var hits := fire_gun(
				man.gun, man.gun.muzzle_flash.global_transform, exclude, false
			)

			var damage_to_player := 0.0
			for hit in hits:
				if hit.collider == player:
					var headshot := false
					var distance := (man.gun.muzzle_flash.global_position
						.distance_to(hit.position))
					damage_to_player += get_gun_damage(
						man.gun, distance, headshot
					)

			if damage_to_player > 0.0:
				player.health -= damage_to_player
				player.hurt_overlay.modulate.a = clampf(
					damage_to_player * 2.0, 0.3, 1.0
				)
				player.damage_audio_stream_player.play()
			man.gun.last_fired_at = Level.get_ticks_sec()
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
		player.crosshair.scale = (
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
	# Need hit from inside since enemy weapon might poke into player
	query.hit_from_inside = true
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
			and
				Level.get_ticks_sec() - suspicious_sound_heard_at
				< LOOKING_SUSPICIOUS_DURATION
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
		Level.get_ticks_sec() - suspicious_sound_heard_at > 20.0
		and (
			not player_identity_compromised
			or Level.get_ticks_sec() - player.last_seen_at > 20.0
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
				spotted_this_frame or Level.get_ticks_sec() - player.last_seen_at < 4.0
			)
			or player_shooting_witnessed_this_frame
		else AiTeamState.INVESTIGATING_SUSPICIOUS_SOUND if
			Level.get_ticks_sec() - suspicious_sound_heard_at < 20.0
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

		var nav_duration := Level.get_ticks_sec() - man.nav_last_updated_at

		var can_see_player := can_man_see_player(man)

		var random_search_duration := lerpf(
			5.0, 10.0, hash_int_to_random_float(man.get_index())
		)

		var engage_pathing_cooldown_duration := (
			0.5 if man.gun_type == GunType.SHOTGUN else 3.0
		)

		var engage_pathing_cooldown := (
			nav_duration < engage_pathing_cooldown_duration
		)

		var follow_pathing_cooldown := nav_duration < 0.5

		var distance_to_player := man.global_position.distance_to(
			player.last_known_position
		)

		var need_to_move_closer_to_engage := (
			man.gun_type == GunType.SHOTGUN
			or man.gun_type == GunType.SNIPER_RIFLE and not can_see_player
			or man.gun_type == GunType.M16 and (
				not can_see_player
				or distance_to_player > 10.0
			)
		)

		var ai_state := (
			AiManState.MOVING_TO_ENGAGE_POSITION if
				man.alive
				and man.mode != Man.Mode.Fixed
				and ai_team_state == AiTeamState.ENGAGING
				and need_to_move_closer_to_engage
				and engage_pathing_cooldown
			else AiManState.PATHING_TO_ENGAGE_POSITION if
				man.alive
				and man.mode != Man.Mode.Fixed
				and ai_team_state == AiTeamState.ENGAGING
				and need_to_move_closer_to_engage
			else AiManState.ENGAGING_PLAYER_WHILE_STANDING_STILL if
				man.alive
				and ai_team_state == AiTeamState.ENGAGING
			else AiManState.MOVING_TO_SUSPICIOUS_SOUND_POSITION if
				man.alive
				and man.mode != Man.Mode.Fixed
				and ai_team_state
					== AiTeamState.INVESTIGATING_SUSPICIOUS_SOUND
				and ai_team_state_last_frame
					== AiTeamState.INVESTIGATING_SUSPICIOUS_SOUND
				and not nav_finished
				and nav_duration < 20.0
			else AiManState.PATHING_TO_SUSPICIOUS_SOUND_POSITION if
				man.alive
				and man.mode != Man.Mode.Fixed
				and began_investigating_suspicious_sound_this_frame
			else AiManState.MOVING_TO_RANDOM_SEARCH_POSITION if
				man.alive
				and man.mode != Man.Mode.Fixed
				and ai_team_state == AiTeamState.SEARCHING_RANDOMLY
				and not nav_finished
				and nav_duration < random_search_duration
			else AiManState.PATHING_TO_RANDOM_SEARCH_POSITION if
				man.alive
				and man.mode != Man.Mode.Fixed
				and ai_team_state == AiTeamState.SEARCHING_RANDOMLY
			else AiManState.MOVING_TO_LAST_KNOWN_POSITION if
				man.alive
				and man.mode != Man.Mode.Fixed
				and ai_team_state
					== AiTeamState.APPROACHING_LAST_KNOWN_POSITION
				and not nav_finished
				and nav_duration < 20.0
			else AiManState.PATHING_TO_RANDOM_SEARCH_POSITION if
				man.alive
				and man.mode != Man.Mode.Fixed
				and ai_team_state
					== AiTeamState.APPROACHING_LAST_KNOWN_POSITION
			else AiManState.MOVING_TO_PATROL_POSITION if
				man.alive
				and man.mode == Man.Mode.Patrol
				and ai_team_state == AiTeamState.PATROLLING
				and not nav_finished
				and nav_duration < 20.0
			else AiManState.PATHING_TO_PATROL_POSITION if
				man.alive
				and man.mode == Man.Mode.Patrol
				and ai_team_state == AiTeamState.PATROLLING
			else AiManState.MOVING_TO_FOLLOW_TARGET if
				man.alive
				and man.mode == Man.Mode.Follow
				and ai_team_state == AiTeamState.PATROLLING
				and not nav_finished
				and follow_pathing_cooldown
			else AiManState.PATHING_TO_FOLLOW_TARGET if
				man.alive
				and man.mode == Man.Mode.Follow
				and ai_team_state == AiTeamState.PATROLLING
			else AiManState.PATHING_TO_INITIAL_POSITION if
				man.alive
				and man.mode == Man.Mode.Stationary
				and ai_team_state == AiTeamState.PATROLLING
				and man.last_ai_state != AiManState.PATHING_TO_INITIAL_POSITION
			else AiManState.MOVING_TO_INITIAL_POSITION if
				man.alive
				and man.mode == Man.Mode.Stationary
				and ai_team_state == AiTeamState.PATROLLING
				and not nav_finished
			else AiManState.REACHED_INITIAL_POSITION if
				man.alive
				and man.mode == Man.Mode.Stationary
				and ai_team_state == AiTeamState.PATROLLING
				and nav_finished
			else AiManState.PAUSING
		)

		# print(AiTeamState.keys()[ai_team_state_last_frame])
		# print(AiManState.keys()[(men.get_children()[0] as Man).last_ai_state])

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
		var reset_to_initial_rotation := false

		match ai_state:
			AiManState.MOVING_TO_PATROL_POSITION:
				has_nav_target = true
				has_look_at_target = true
				look_at_target = next_path_pos
			AiManState.PATHING_TO_PATROL_POSITION:
				has_new_nav_target = true
				var patrol_node: Node3D = patrol.get_child(man.patrol_index)
				new_nav_target = patrol_node.global_position
			AiManState.MOVING_TO_FOLLOW_TARGET:
				has_nav_target = true
				has_look_at_target = true
				look_at_target = next_path_pos
			AiManState.PATHING_TO_FOLLOW_TARGET:
				has_new_nav_target = true
				new_nav_target = man.follow.global_position
			AiManState.MOVING_TO_INITIAL_POSITION:
				has_nav_target = true
				has_look_at_target = true
				look_at_target = next_path_pos
			AiManState.PATHING_TO_INITIAL_POSITION:
				has_new_nav_target = true
				new_nav_target = man.initial_position
			AiManState.REACHED_INITIAL_POSITION:
				reset_to_initial_rotation = true
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
				look_at_target = (
					player.last_known_position
						if can_man_look_at(man, player.last_known_position)
						else next_path_pos
				)
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
				look_at_target = (
					suspicious_sound_position
						if can_man_look_at(man, suspicious_sound_position)
						else next_path_pos
				)
			AiManState.PATHING_TO_SUSPICIOUS_SOUND_POSITION:
				has_new_nav_target = true
				new_nav_target = suspicious_sound_position
			AiManState.ENGAGING_PLAYER_WHILE_STANDING_STILL:
				has_look_at_target = true
				look_at_target = player.last_known_position
				has_aim_target = true
			AiManState.PAUSING:
				pass

		var aim_target := (
			player.camera.global_position if can_see_player
			else player.last_known_position
		)

		var next_patrol_index := (
			(man.patrol_index + 1) % patrol.get_child_count()
				if ai_state == AiManState.PATHING_TO_PATROL_POSITION
			else man.patrol_index
		)

		var run_speed := 7.0 if man.gun_type == GunType.SHOTGUN else 4.0

		var walk_speed := 3.0

		var speed := (
			walk_speed
				if ai_team_state == AiTeamState.PATROLLING
				or ai_team_state == AiTeamState.SEARCHING_RANDOMLY
			else run_speed
		)

		var velocity := Vector3(0.0, man.velocity.y - 9.8 * delta, 0.0)
		if man.alive:
			velocity += Vector3(man.safe_velocity.x, 0.0, man.safe_velocity.z)
			if has_nav_target:
				var dir := man.global_position.direction_to(next_path_pos)
				velocity += dir * speed
		if man.is_on_floor():
			velocity.y = 0.0

		var is_engaging := (
			ai_state == AiManState.PATHING_TO_ENGAGE_POSITION
			or ai_state == AiManState.MOVING_TO_ENGAGE_POSITION
			or ai_state == AiManState.ENGAGING_PLAYER_WHILE_STANDING_STILL
		)

		var next_aim_progress := man.aim_progress
		if is_engaging and man.aim_progress < 0.5:
			next_aim_progress += delta / 1.2
		elif is_engaging and can_see_player:
			var d := clampf(distance_to_player, 1.0, 50.0)
			var r := remap(d, 1.0, 50.0, 0.6, 1.5)
			next_aim_progress += delta / r
		else:
			next_aim_progress -= delta / 1.2
		next_aim_progress = clampf(next_aim_progress, 0.0, 1.0)

		# --- Side effects ---

		man.patrol_index = next_patrol_index
		if has_new_nav_target:
			man.navigation_agent.set_target_position(new_nav_target)
			man.nav_last_updated_at = Level.get_ticks_sec()
		if has_look_at_target:
			Level.safe_look_at(man, look_at_target)
		if reset_to_initial_rotation:
			man.global_rotation = man.initial_rotation
		man.rotation.x = 0
		man.rotation.z = 0
		if has_aim_target:
			man.gun.look_at(aim_target, Vector3.UP)
		else:
			man.gun.rotation.x = 0
			man.gun.rotation.y = 0
			man.gun.rotation.z = 0
		man.velocity = velocity
		# man.safe_velocity = Vector3.ZERO
		man.move_and_slide()
		man.last_ai_state = ai_state
		man.aim_progress = next_aim_progress

	if player_shooting_witnessed_this_frame:
		hunt_player()

	if can_any_man_see_player:
		player.last_known_position = player.global_position
		player.last_seen_at = Level.get_ticks_sec()

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
	new_msg.created_at = Level.get_ticks_sec()
	new_msg.position.x = 8.0
	new_msg.add_theme_font_size_override("font_size", 24)
	new_msg.text = text
	player.messages.add_child(new_msg)
	if player.messages.get_child_count() > 3:
		var c := player.messages.get_child(0)
		c.queue_free()
		player.messages.remove_child(c)
	var y := 8.0
	for msg: Label in player.messages.get_children():
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
) -> Array[BulletHit]:
	var hits: Array[BulletHit] = []

	gun.last_fired_at = Level.get_ticks_sec()

	for i in get_gun_pellets(gun):
		var hit_man: Man
		var hit_anything := false
		var hit_player := false

		var max_spread := get_gun_max_spread(gun)
		var dir := (
			source.basis.z.normalized()
				.rotated(
					source.basis.x.normalized(),
					randf_range(-max_spread, max_spread)
				)
				.rotated(
					source.basis.y.normalized(),
					randf_range(-max_spread, max_spread)
				)
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
			impact.global_position = hit_position

		gun.muzzle_flash_particles.emitting = true
		gun.muzzle_flash_particles.restart()

		if i % 2 == 0:
			var tracer: Node3D = tracer_scene.instantiate()
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
			tracer.global_position = gun.muzzle_flash.global_position
			tracer.look_at(hit_position, Vector3.UP, true)
		if collision:
			var hit := BulletHit.new()
			hit.collider = collision.collider
			hit.position = collision.position
			hits.append(hit)

	gun.accuracy -= 0.1 - 0.1 * (1.0 - gun.accuracy)

	var gun_accel := 0.8
	gun.kick_velocity += Vector3(
		randf_range(-gun_accel, gun_accel),
		randf_range(-gun_accel, gun_accel),
		gun_accel
	)

	return hits


func hash_int_to_random_float(value: int) -> float:
	# Linear congruential generator (LCG)
	var s := value * 1103515245 + 12345
	s = s % 2147483647
	return float(s) / 2147483647.0


func get_gun_cooldown(gun: Gun) -> float:
	match gun.gun_type:
		GunType.M16:
			return 0.1
		GunType.SNIPER_RIFLE:
			return 2.3
		GunType.SHOTGUN:
			return 1.18
	push_error("Unhandled state")
	return 1.0


func get_gun_damage(gun: Gun, distance: float, headshot: bool) -> float:
	match gun.gun_type:
		GunType.M16:
			var m := 5.0 if headshot else 1.0
			var l := 0.05 * m
			var u := 0.2 * m
			return clampf(remap(distance, 5.0, 20.0, u, l), l, u)
		GunType.SNIPER_RIFLE:
			return 1.0
		GunType.SHOTGUN:
			var l := 0.025
			var u := 0.2
			return clampf(remap(distance, 10.0, 30.0, u, l), l, u)
	push_error("Unhandled state")
	return 1.0


func get_gun_audio_stream_player(gun: Gun) -> AudioStreamPlayer:
	match gun.gun_type:
		GunType.M16:
			return player.m_16_audio_stream_player
		GunType.SNIPER_RIFLE:
			return player.sniper_rifle_audio_stream_player
		GunType.SHOTGUN:
			return player.shotgun_audio_stream_player
	push_error("Unhandled state")
	return null


func get_gun_max_spread(gun: Gun) -> float:
	match gun.gun_type:
		GunType.M16:
			return 0.2 * (1.0 - gun.accuracy)
		GunType.SNIPER_RIFLE:
			return 0.0
		GunType.SHOTGUN:
			return 0.06
	push_error("Unhandled state")
	return 1.0


func get_gun_pellets(gun: Gun) -> int:
	match gun.gun_type:
		GunType.M16:
			return 1
		GunType.SNIPER_RIFLE:
			return 1
		GunType.SHOTGUN:
			return 14
	push_error("Unhandled state")
	return 1


static func get_ticks_sec() -> float:
	return Time.get_ticks_msec() / 1000.0


static func safe_look_at(node: Node3D, target: Vector3) -> void:
	var direction: Vector3 = (
		target - node.global_transform.origin
	).normalized()

	for up: Vector3 in [Vector3.UP, Vector3.RIGHT, Vector3.BACK]:
		if node.global_position != target and abs(up.dot(direction)) != 1:
			node.look_at(target, up)
			break


func can_man_look_at(man: Man, point: Vector3) -> bool:
	var exclude: Array[Variant] = []
	exclude.append(player.get_rid())
	for man2: Man in men.get_children():
		if is_instance_valid(man2):
			exclude.append(man2.get_rid())
			exclude.append(man2.head_hitbox.get_rid())
			exclude.append(man2.body_hitbox.get_rid())

	var query := PhysicsRayQueryParameters3D.new()
	query.from = man.head_hitbox.global_position
	query.to = point
	query.exclude = exclude

	var collision := get_world_3d().direct_space_state.intersect_ray(query)

	return collision.is_empty()


func process_zoom() -> void:
	var s := 0.8
	if (
		player.gun
		and player.gun.gun_type == GunType.SNIPER_RIFLE
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	):
		player.camera.fov = 30.0
		player.head.mouse_sensitivity = s * 30.0 / 75.0
	else:
		player.camera.fov = 75.0
		player.head.mouse_sensitivity = s


func make_followers_stationary(man: Man) -> void:
	for man_2: Man in men.get_children():
		if man_2.mode == Man.Mode.Follow and man_2.follow == man:
			man_2.mode = Man.Mode.Stationary
