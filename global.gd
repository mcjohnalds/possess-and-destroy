class_name Global


static func time() -> float:
	return Time.get_ticks_msec() / 1000.0


static func safe_look_at(node: Node3D, target: Vector3) -> void:
	var direction: Vector3 = (
		target - node.global_transform.origin
	).normalized()

	for up: Vector3 in [Vector3.UP, Vector3.RIGHT, Vector3.BACK]:
		if abs(up.dot(direction)) != 1:
			node.look_at(target, up)
			break
