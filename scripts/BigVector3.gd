extends Resource
class_name BigVector3

@export var x: float = 0
@export var y: float = 0
@export var z: float = 0

func _init(_x: float = 0.0, _y: float = 0.0, _z: float = 0.0):
	x = _x
	y = _y
	z = _z

static func zero() -> BigVector3:
	return BigVector3.new()

func to_vector3() -> Vector3:
	return Vector3(x, y, z)

func add(other: BigVector3) -> BigVector3:
	return BigVector3.new(x + other.x, y + other.y, z + other.z)

func sub(other: BigVector3) -> BigVector3:
	return BigVector3.new(x - other.x, y - other.y, z - other.z)

func translate(delta: Vector3) -> void:
	x += delta.x
	y += delta.y
	z += delta.z

func length() -> float:
	return sqrt(x * x + y * y + z * z)

func normalized() -> BigVector3:
	var l := length()
	if l == 0.0:
		return BigVector3.new()
	return BigVector3.new(x / l, y / l, z / l)

func negated() -> BigVector3:
	return BigVector3.new(-x, -y, -z)

func mul(scalar: float) -> BigVector3:
	return BigVector3.new(x * scalar, y * scalar, z * scalar)

func _to_string() -> String:
	return "Big(%f, %f, %f)" % [x, y, z]
