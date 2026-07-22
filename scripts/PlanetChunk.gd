extends MeshInstance3D
class_name PlanetChunk

var absolute_position: BigVector3 = BigVector3.new()
var lod_level: int = 0

# Bounds do chunk no plano tangente local, em METROS, relativos à origem do
# patch atual (ver WorldManager._patch_origin_*).
var local_min: Vector2
var local_max: Vector2

# Referencial tangente local, definido pelo WorldManager a cada "recenter".
# origin_dir aponta do centro do planeta até a origem do patch (o "up" local);
# east/north formam o plano tangente nesse ponto.
var patch_origin_dir: Vector3 = Vector3.UP
var patch_east: Vector3 = Vector3.RIGHT
var patch_north: Vector3 = Vector3.FORWARD

# Cache compartilhado de tiles de elevação. Deve ser atribuído pelo
# WorldManager antes de chamar generate_chunk_mesh (evita downloads
# duplicados entre chunks vizinhos e entre reconstruções da quadtree local).
var tile_cache: TileCache = null

var current_radius: float = 6371000.0
var current_resolution: int = 16

# Guardamos as coordenadas do tile atual baixado
var current_tile_coords: Vector2i = Vector2i.ZERO
var current_zoom: int = 1

# Gradiente hipsométrico usado para colorir os vértices a partir da
# elevação (em metros, já escalada pelo raio do planeta simulado).
# Cada entrada é [elevação_m, cor]; interpolamos linearmente entre pares.
const ELEVATION_COLOR_STOPS := [
	[-500.0, Color(0.05, 0.15, 0.35)],  # oceano profundo
	[0.0,    Color(0.10, 0.32, 0.58)],  # nível do mar
	[4.0,    Color(0.76, 0.70, 0.45)],  # praia / areia
	[60.0,   Color(0.22, 0.48, 0.20)],  # planície / vegetação
	[500.0,  Color(0.38, 0.46, 0.22)],  # colina
	[1400.0, Color(0.47, 0.40, 0.32)],  # montanha (rocha)
	[2600.0, Color(0.55, 0.54, 0.55)],  # rocha alta
	[3600.0, Color(0.95, 0.95, 0.97)],  # neve
]

func generate_chunk_mesh(
	p_local_min: Vector2,
	p_local_max: Vector2,
	lod: int,
	_max_lod: int,
	radius: float,
	resolution: int,
	origin_dir: Vector3,
	east: Vector3,
	north: Vector3
) -> void:
	local_min = p_local_min
	local_max = p_local_max
	lod_level = lod
	current_radius = radius
	current_resolution = resolution
	patch_origin_dir = origin_dir
	patch_east = east
	patch_north = north

	var mid_local = (local_min + local_max) * 0.5
	var center_dir = _local_to_sphere_dir(mid_local)
	absolute_position = BigVector3.new(
		center_dir.x * radius,
		center_dir.y * radius,
		center_dir.z * radius
	)

	_ensure_vertex_color_material()
	_build_mesh(null)
	_fetch_real_world_data()


func _ensure_vertex_color_material() -> void:
	if material_override == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		material_override = mat


func _local_to_sphere_dir(local_pt: Vector2) -> Vector3:
	return Constants.tangent_to_sphere_dir(local_pt, current_radius, patch_origin_dir, patch_east, patch_north)


func _fetch_real_world_data() -> void:
	var lat_lon_min = _local_to_lat_lon(local_min)
	var lat_lon_max = _local_to_lat_lon(local_max)
	
	var lat_span = abs(lat_lon_max.x - lat_lon_min.x)
	var lon_span = abs(lat_lon_max.y - lat_lon_min.y)
	var max_span = maxf(lat_span, lon_span)
	
	var ideal_zoom = int(floor(log(360.0 / max_span) / log(2.0)))
	current_zoom = clampi(ideal_zoom, 1, 12)
	
	var mid_local = (local_min + local_max) * 0.5
	var lat_lon_mid = _local_to_lat_lon(mid_local)
	current_tile_coords = _lat_lon_to_tile(lat_lon_mid.x, lat_lon_mid.y, current_zoom)

	if tile_cache:
		tile_cache.get_elevation_tile(current_zoom, current_tile_coords.x, current_tile_coords.y, _on_elevation_ready)


func _on_elevation_ready(img: Image) -> void:
	if img:
		_build_mesh(img)


func _build_mesh(heightmap: Image) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var img_width = heightmap.get_width() - 1 if heightmap else 0
	var img_height = heightmap.get_height() - 1 if heightmap else 0

	var elevation_scale_factor: float = current_radius / Constants.EARTH_RADIUS_M

	for y in range(current_resolution + 1):
		for x in range(current_resolution + 1):
			var percent = Vector2(x, y) / float(current_resolution)
			
			var local_pt = Vector2(
				lerp(local_min.x, local_max.x, percent.x),
				lerp(local_min.y, local_max.y, percent.y)
			)
			
			var dir = _local_to_sphere_dir(local_pt)
			
			var lat = rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
			var lon = rad_to_deg(atan2(dir.x, dir.z))
			
			var elevation_uv = _lat_lon_to_tile_uv(lat, lon, current_zoom, current_tile_coords)
			
			var real_elevation_m = 0.0
			if heightmap:
				var px = int(clampf(elevation_uv.x, 0.0, 1.0) * img_width)
				var py = int(clampf(elevation_uv.y, 0.0, 1.0) * img_height)
				var color = heightmap.get_pixel(px, py)
				
				real_elevation_m = (color.r * 255.0 * 256.0 + color.g * 255.0 + color.b * 255.0 / 256.0) - 32768.0

			var scaled_elevation_m = real_elevation_m * elevation_scale_factor
			var final_radius = current_radius + scaled_elevation_m

			var point_on_sphere = BigVector3.new(
				dir.x * final_radius,
				dir.y * final_radius,
				dir.z * final_radius
			)

			var local_vertex := point_on_sphere.sub(absolute_position).to_vector3()

			st.set_color(_color_for_elevation(real_elevation_m))
			st.set_normal(dir)
			st.add_vertex(local_vertex)

	for y in range(current_resolution):
		for x in range(current_resolution):
			var i = x + y * (current_resolution + 1)
			st.add_index(i)
			st.add_index(i + current_resolution + 1)
			st.add_index(i + 1)
			
			st.add_index(i + 1)
			st.add_index(i + current_resolution + 1)
			st.add_index(i + current_resolution + 2)

	st.generate_normals()
	mesh = st.commit()


## Interpola a cor hipsométrica correspondente a uma elevação (em metros).
func _color_for_elevation(elevation_m: float) -> Color:
	var stops := ELEVATION_COLOR_STOPS
	if elevation_m <= stops[0][0]:
		return stops[0][1]

	for i in range(stops.size() - 1):
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if elevation_m <= b[0]:
			var t = inverse_lerp(a[0], b[0], elevation_m)
			return (a[1] as Color).lerp(b[1], t)

	return stops[stops.size() - 1][1]


func update_render_position(planet_origin_offset: BigVector3) -> void:
	position = absolute_position.sub(planet_origin_offset).to_vector3()


func _lat_lon_to_tile_uv(lat: float, lon: float, zoom: int, tile_coords: Vector2i) -> Vector2:
	var clamped_lat = clampf(lat, -85.05112878, 85.05112878)
	
	var normalized_lon = fmod(lon + 180.0, 360.0)
	if normalized_lon < 0.0: normalized_lon += 360.0
	normalized_lon -= 180.0

	var lat_rad = deg_to_rad(clamped_lat)
	var n = pow(2.0, zoom)
	
	var global_x = (normalized_lon + 180.0) / 360.0 * n
	var global_y = (1.0 - asinh(tan(lat_rad)) / PI) / 2.0 * n
	
	var u = global_x - float(tile_coords.x)
	var v = global_y - float(tile_coords.y)
	
	return Vector2(u, v)


func _lat_lon_to_tile(lat: float, lon: float, zoom: int) -> Vector2i:
	var clamped_lat = clampf(lat, -85.05112878, 85.05112878)
	
	var normalized_lon = fmod(lon + 180.0, 360.0)
	if normalized_lon < 0.0: normalized_lon += 360.0
	normalized_lon -= 180.0

	var lat_rad = deg_to_rad(clamped_lat)
	var n = pow(2.0, zoom)
	
	var xtile = int((normalized_lon + 180.0) / 360.0 * n)
	var ytile = int((1.0 - asinh(tan(lat_rad)) / PI) / 2.0 * n)
	
	xtile = clampi(xtile, 0, int(n) - 1)
	ytile = clampi(ytile, 0, int(n) - 1)
	
	return Vector2i(xtile, ytile)


func _local_to_lat_lon(local_pt: Vector2) -> Vector2:
	var dir = _local_to_sphere_dir(local_pt)

	var lat = rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
	var lon = rad_to_deg(atan2(dir.x, dir.z))
	
	return Vector2(lat, lon)
