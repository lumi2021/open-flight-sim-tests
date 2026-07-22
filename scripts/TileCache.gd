extends Node
class_name TileCache

var elevation_cache: Dictionary = {}
var texture_cache: Dictionary = {}

var active_downloads: Dictionary = {}


func get_elevation_tile(zoom: int, x: int, y: int, callback: Callable) -> void:
	var key = "elev_%d_%d_%d" % [zoom, x, y]
	
	if elevation_cache.has(key):
		callback.call(elevation_cache[key])
		return

	if active_downloads.has(key):
		active_downloads[key].append(callback)
		return

	active_downloads[key] = [callback]

	var http = HTTPRequest.new()
	add_child(http)
	
	var url = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png" % [zoom, x, y]
	var headers = ["User-Agent: OpenFlightSim/1.0"]
	
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		var img: Image = null
		if response_code == 200 and not body.is_empty():
			img = Image.new()
			if img.load_png_from_buffer(body) != OK:
				img = null
		
		if img: elevation_cache[key] = img
			
		if active_downloads.has(key):
			var callbacks: Array = active_downloads[key]
			active_downloads.erase(key)
			for cb in callbacks:
				if cb.is_valid():
					cb.call(img)
		
		http.queue_free()
	)
	
	http.request(url, headers)

func get_texture_tile(zoom: int, x: int, y: int, callback: Callable) -> void:
	var key = "tex_%d_%d_%d" % [zoom, x, y]
	
	if texture_cache.has(key):
		callback.call(texture_cache[key])
		return

	if active_downloads.has(key):
		active_downloads[key].append(callback)
		return

	active_downloads[key] = [callback]

	var http = HTTPRequest.new()
	http.max_redirects = 3
	add_child(http)
	
	var url = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/%d/%d/%d" % [zoom, y, x]
	var headers = ["User-Agent: OpenFlightSim/1.0"]
	
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		var tex: ImageTexture = null
		if response_code == 200 and not body.is_empty():
			var img = Image.new()
			if img.load_jpg_from_buffer(body) == OK or img.load_png_from_buffer(body) == OK:
				tex = ImageTexture.create_from_image(img)
		
		# Salva no cache se a textura for válida
		if tex:
			texture_cache[key] = tex
			
		# Notifica todos os chunks que estavam esperando esta textura
		if active_downloads.has(key):
			var callbacks: Array = active_downloads[key]
			active_downloads.erase(key)
			for cb in callbacks:
				if cb.is_valid():
					cb.call(tex)
		
		http.queue_free()
	)
	
	http.request(url, headers)

func get_texture_atlas(zoom: int, min_tile: Vector2i, callback: Callable) -> void:
	var atlas_image = Image.create_empty(512, 512, false, Image.FORMAT_RGBA8)
	var loaded_count = [0]
	
	var offsets = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1)
	]
	
	for i in range(4):
		var offset = offsets[i]
		var tx = min_tile.x + offset.x
		var ty = min_tile.y + offset.y
		var dest_pos = Vector2i(offset.x * 256, offset.y * 256)
		
		get_texture_tile(zoom, tx, ty, func(tex: ImageTexture):
			if tex:
				var img = tex.get_image()
				atlas_image.blit_rect(img, Rect2i(0, 0, 256, 256), dest_pos)
			
			loaded_count[0] += 1
			if loaded_count[0] == 4:
				var final_tex = ImageTexture.create_from_image(atlas_image)
				callback.call(final_tex)
		)
