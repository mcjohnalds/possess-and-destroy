class_name BulletRay


class Query:
	var source: Node3D
	var accuracy: float
	var men: Array[Man]


class Result:
	var hit_position: Vector3
	var hit_man: Man
	var headshot: bool
	var hit_anything: bool


static func intersect(query: Query) -> Result:
	var result := Result.new()

	var max_spread := 0.2 * (1.0 - query.accuracy)
	var dir := (
		query.source.global_basis.z
			.rotated(
				query.source.global_basis.x,
				randf_range(-max_spread, max_spread)
			)
			.rotated(
				query.source.global_basis.y,
				randf_range(-max_spread, max_spread)
			)
	)

	var ray_query := PhysicsRayQueryParameters3D.create(
		query.source.global_position,
		query.source.global_position + dir * -100.0
	)
	var arr: Array[Variant] = []
	for man: Man in query.men:
		if is_instance_valid(man):
			arr.append(man.get_rid())
	ray_query.exclude = arr
	ray_query.collide_with_areas = true
	var collision := (
		query.source.get_world_3d().direct_space_state.intersect_ray(ray_query)
	)

	result.hit_position = ray_query.to

	if collision:
		result.hit_anything = true

		var hit: Node3D = collision.collider
		if hit.name == "HeadHitbox":
			result.hit_man = hit.get_parent()
			result.headshot = true
		elif hit.name == "BodyHitbox":
			result.hit_man = hit.get_parent()
		result.hit_position = collision.position
	
	return result
