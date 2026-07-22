class_name Constants

const PLANETARY_ENTITY_GROUP := "planetary_entity"
const EARTH_RADIUS_M: float = 6371000.0

const POLAR_AXIS := Vector3(0.0, 1.0, 0.0)

static func tangent_to_sphere_dir(
	local_pt: Vector2,
	radius: float,
	origin_dir: Vector3,
	east: Vector3,
	north: Vector3
) -> Vector3:
	var flat := origin_dir * radius + east * local_pt.x + north * local_pt.y
	return flat.normalized()


static func compute_tangent_basis(up: Vector3) -> Array[Vector3]:
	var reference := POLAR_AXIS
	if absf(up.dot(reference)) > 0.999:
		reference = Vector3(1.0, 0.0, 0.0)

	var east := reference.cross(up).normalized()
	var north := up.cross(east).normalized()
	return [east, north]
