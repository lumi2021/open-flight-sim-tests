extends Node
class_name PlanetaryEntity

@export var universal_position := BigVector3.zero()
@export var gcs_position := Vector2.ZERO

func _ready() -> void:
	add_to_group(Constants.PLANETARY_ENTITY_GROUP)

func _to_string() -> String:
	return "UP(%f, %f, %f) GCS(%fº %fº)" % [
		universal_position.x,
		universal_position.y,
		universal_position.z,
		
		gcs_position.x,
		gcs_position.y
	]
