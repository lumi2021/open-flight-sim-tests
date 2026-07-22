class_name PlanetaryPlayer
extends Node3D

var planetary_entity : PlanetaryEntity
var universal_position: BigVector3:
	get: return planetary_entity.universal_position
	set(value): planetary_entity.universal_position = value
var gcs_position: Vector2:
	get: return planetary_entity.gcs_position
	set(value): planetary_entity.gcs_position = value

@export var world_manager: WorldManager
@export var camera_pos: Node3D

@export var accel_speed: float = 500.0
@export var rotat_speed: float = 3.0
var velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	planetary_entity = PlanetaryEntity.new()
	add_child(planetary_entity)

func _process(delta: float) -> void:
	var input_forward := Input.get_axis("ui_down", "ui_up")
	var input_sides := Input.get_axis("ui_left", "ui_right")

	var up := planetary_entity.universal_position.normalized().to_vector3()

	var forward := _project_and_normalize(-global_basis.z, up)
	var right := forward.cross(up).normalized()
	forward = up.cross(right).normalized()

	global_basis = Basis(right, up, -forward)

	var direction := -forward * input_forward
	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	planetary_entity.universal_position.translate(direction * accel_speed * delta)
	rotate_y(input_sides * rotat_speed * delta)


func _project_and_normalize(vec: Vector3, up: Vector3) -> Vector3:
	var projected := vec - up * vec.dot(up)
	if projected.length_squared() < 0.0001:
		var fallback := Vector3.FORWARD
		if absf(up.dot(fallback)) > 0.99:
			fallback = Vector3.RIGHT
		projected = fallback - up * fallback.dot(up)
	return projected.normalized()
