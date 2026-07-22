class_name WorldManager
extends Node3D

@export var player: PlanetaryPlayer
@export var planet_radius: float = 6371000.0

@export_group("Simulação Local")
## Raio (em km) da área ao redor do jogador que é simulada como chunks.
## Fora dessa área nada é gerado — só a vizinhança do jogador existe.
@export var simulation_radius_km: float = 6.0
## Fração do raio de simulação que o jogador pode se afastar da origem do
## patch atual antes dele ser recentralizado (o que reconstrói a quadtree
## local do zero).
@export_range(0.1, 0.9, 0.05) var recenter_margin_ratio: float = 0.5

@export_group("LOD Settings")
@export var view_distance_chunks: float = 2.0
@export var chunk_resolution: int = 16
@export var target_chunk_size_m: float = 128.0

var planet_origin_offset: BigVector3 = BigVector3.new()

var max_lod_level: int = 8
var leaf_chunk_size_m: float = 128.0
var simulation_radius_m: float = 0.0

var tile_cache: TileCache

# Referencial tangente local (plano leste/norte na origem do patch atual).
# Redefinido sempre que o jogador se afasta demais do centro (ver
# _recenter_patch). planet_origin_offset, por outro lado, é atualizado TODO
# frame — ele só serve para posicionar a renderização (floating origin) e
# não tem relação com este referencial de simulação.
var _patch_origin_dir: Vector3 = Vector3.UP
var _patch_origin_abs: BigVector3 = BigVector3.new()
var _patch_east: Vector3 = Vector3.RIGHT
var _patch_north: Vector3 = Vector3.FORWARD

class QuadtreeNode:
	var local_min: Vector2
	var local_max: Vector2
	var lod_level: int
	var chunk_instance: PlanetChunk = null
	var children: Array[QuadtreeNode] = []

	func _init(p_min: Vector2, p_max: Vector2, p_lod: int):
		local_min = p_min
		local_max = p_max
		lod_level = p_lod

	func is_leaf() -> bool:
		return children.is_empty()


var quadtree_root: QuadtreeNode = null


func _ready() -> void:
	process_priority = 100000
	tile_cache = TileCache.new()
	add_child(tile_cache)
	call_deferred("_initialize")


func _initialize() -> void:
	if player:
		player.universal_position = BigVector3.new(0, planet_radius + 5, 0)

	simulation_radius_m = simulation_radius_km * 1000.0
	_calculate_max_lod()
	_recenter_patch()


func _process(_delta: float) -> void:
	if not player:
		return

	planet_origin_offset = player.universal_position
	_maybe_recenter_patch()
	_update_quadtree()
	_update_planetary_entities()


func _calculate_max_lod() -> void:
	var root_size_m = simulation_radius_m * 2.0
	if target_chunk_size_m > 0.0 and root_size_m > 0.0:
		var raw_lod = log(root_size_m / target_chunk_size_m) / log(2.0)
		max_lod_level = maxi(1, ceili(raw_lod))

		# Salva o tamanho real (em metros) do menor chunk possível no solo
		leaf_chunk_size_m = root_size_m / pow(2.0, max_lod_level)

		print("Raio de simulação: %.0fm | LOD Máximo: %d | Tamanho Real do Menor Chunk: %.2fm" % [
			simulation_radius_m,
			max_lod_level,
			leaf_chunk_size_m
		])


func _maybe_recenter_patch() -> void:
	var offset := player.universal_position.sub(_patch_origin_abs).to_vector3()
	# Descarta a componente radial (altitude) — só nos importa o quanto o
	# jogador andou "de lado" em relação à origem atual do patch.
	var horizontal_offset := offset - _patch_origin_dir * offset.dot(_patch_origin_dir)
	var margin := simulation_radius_m * recenter_margin_ratio

	if horizontal_offset.length() > margin:
		_recenter_patch()


func _recenter_patch() -> void:
	var up := player.universal_position.normalized().to_vector3()

	_patch_origin_dir = up
	_patch_origin_abs = BigVector3.new(up.x * planet_radius, up.y * planet_radius, up.z * planet_radius)

	var basis := Constants.compute_tangent_basis(up)
	_patch_east = basis[0]
	_patch_north = basis[1]

	_rebuild_quadtree()


func _rebuild_quadtree() -> void:
	if quadtree_root != null:
		_collapse_node(quadtree_root)
		if quadtree_root.chunk_instance != null:
			quadtree_root.chunk_instance.queue_free()

	quadtree_root = QuadtreeNode.new(
		Vector2(-simulation_radius_m, -simulation_radius_m),
		Vector2(simulation_radius_m, simulation_radius_m),
		0
	)


func _update_quadtree() -> void:
	if quadtree_root:
		_process_node(quadtree_root)


func _process_node(node: QuadtreeNode) -> void:
	var mid_local = (node.local_min + node.local_max) * 0.5
	var node_center_dir = Constants.tangent_to_sphere_dir(mid_local, planet_radius, _patch_origin_dir, _patch_east, _patch_north)
	var node_center_ecef = BigVector3.new(
		node_center_dir.x * planet_radius,
		node_center_dir.y * planet_radius,
		node_center_dir.z * planet_radius
	)

	var distance_to_player = node_center_ecef.sub(player.universal_position).length()
	var current_node_size_m = node.local_max.x - node.local_min.x
	var node_radius = current_node_size_m * 0.7071
	var static_split_distance = node_radius + (leaf_chunk_size_m * view_distance_chunks)
	var should_split = (distance_to_player < static_split_distance) and (node.lod_level < max_lod_level)

	if should_split:
		if node.is_leaf():
			_subdivide_node(node)
		
		if node.chunk_instance != null:
			node.chunk_instance.queue_free()
			node.chunk_instance = null
			
		for child in node.children:
			_process_node(child)
	else:
		if not node.is_leaf():
			_collapse_node(node)
		
		if node.chunk_instance == null:
			_create_chunk_instance(node)
			
		node.chunk_instance.update_render_position(planet_origin_offset)


func _subdivide_node(node: QuadtreeNode) -> void:
	var mid = (node.local_min + node.local_max) * 0.5
	var next_lod = node.lod_level + 1

	node.children.append(QuadtreeNode.new(node.local_min, mid, next_lod))
	node.children.append(QuadtreeNode.new(Vector2(mid.x, node.local_min.y), Vector2(node.local_max.x, mid.y), next_lod))
	node.children.append(QuadtreeNode.new(Vector2(node.local_min.x, mid.y), Vector2(mid.x, node.local_max.y), next_lod))
	node.children.append(QuadtreeNode.new(mid, node.local_max, next_lod))


func _collapse_node(node: QuadtreeNode) -> void:
	for child in node.children:
		_collapse_node(child)
		if child.chunk_instance != null:
			child.chunk_instance.queue_free()
			child.chunk_instance = null
	node.children.clear()


func _create_chunk_instance(node: QuadtreeNode) -> void:
	var chunk = PlanetChunk.new()
	add_child(chunk)
	chunk.tile_cache = tile_cache
	chunk.generate_chunk_mesh(
		node.local_min,
		node.local_max,
		node.lod_level,
		max_lod_level,
		planet_radius,
		chunk_resolution,
		_patch_origin_dir,
		_patch_east,
		_patch_north
	)
	node.chunk_instance = chunk


func _update_planetary_entities() -> void:
	var planetary_entities = get_tree().get_nodes_in_group(Constants.PLANETARY_ENTITY_GROUP)

	for pe in planetary_entities:
		if not pe.get_parent() is Node3D: 
			continue
		var node := pe.get_parent() as Node3D

		var n = pe.universal_position.normalized()
		var latitude = asin(n.y)
		var longitude = atan2(n.x, n.z)

		var local_position: Vector3 = pe.universal_position.sub(planet_origin_offset).to_vector3()

		node.position = local_position
		pe.gcs_position = Vector2(rad_to_deg(latitude), rad_to_deg(longitude))
