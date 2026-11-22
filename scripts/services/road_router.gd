extends RefCounted
class_name IDMRoadRouter

## A* router for the bundled, directed OSM node graph. The graph is stored as
## compact CSR bytes; no per-node Dictionaries are created at runtime.
const DEFAULT_NETWORK_PATH := "res://data/kl_selangor_route_graph.bin.gz"
const MAGIC := "IDMG"
const VERSION := 1
const HEADER_SIZE := 46
const MAX_SNAP_DISTANCE_M := 2.0
const GRID_WIDTH := 256
const GRID_HEIGHT := 320
const MAX_ROUTE_SPEED_KMH := 80.0 # Simulated road-class speed ceiling, not live traffic.
const CLASS_SPEED_KMH := [80.0, 65.0, 50.0, 40.0, 30.0, 24.0, 16.0]
const UV_TEXTURE_WIDTH := 1152.0
const UV_TEXTURE_HEIGHT := 1320.0

var network_bytes := PackedByteArray()
var node_count := 0
var arc_count := 0
var west := 0.0
var south := 0.0
var east := 0.0
var north := 0.0
var node_data_offset := HEADER_SIZE
var offsets_data_offset := 0
var arcs_data_offset := 0
var _grid_offsets := PackedInt32Array()
var _grid_nodes := PackedInt32Array()
var _spawn_candidate_nodes := PackedInt32Array()
var _g_scores := PackedFloat32Array()
var _g_stamp := PackedInt32Array()
var _closed_stamp := PackedInt32Array()
var _came_from := PackedInt32Array()
var _came_distance_m := PackedFloat32Array()
var _came_seconds := PackedFloat32Array()
var _heap_keys := PackedFloat32Array()
var _heap_nodes := PackedInt32Array()
var _epoch := 0
var last_error := ""


func load_network(path: String = DEFAULT_NETWORK_PATH) -> bool:
	if not FileAccess.file_exists(path):
		last_error = "Road network data is unavailable."
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Road network data could not be opened."
		return false
	var file_bytes := file.get_buffer(file.get_length())
	if path.ends_with(".gz"):
		if file_bytes.size() < 5:
			return _fail("Compressed road graph is incomplete.")
		var raw_size := int(file_bytes.decode_u32(0))
		if raw_size < HEADER_SIZE or raw_size > 256 * 1024 * 1024:
			return _fail("Compressed road graph declares an invalid size.")
		var decompressed := file_bytes.slice(4).decompress(raw_size, FileAccess.COMPRESSION_GZIP)
		if decompressed.size() != raw_size:
			return _fail("Compressed road graph could not be decompressed.")
		return load_network_bytes(decompressed)
	return load_network_bytes(file_bytes)


func load_network_bytes(bytes: PackedByteArray) -> bool:
	_clear()
	if bytes.size() < HEADER_SIZE or bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return _fail("Invalid road graph header.")
	if bytes.decode_u16(4) != VERSION:
		return _fail("Unsupported road graph version.")
	west = bytes.decode_double(6)
	south = bytes.decode_double(14)
	east = bytes.decode_double(22)
	north = bytes.decode_double(30)
	node_count = int(bytes.decode_u32(38))
	arc_count = int(bytes.decode_u32(42))
	if node_count < 2 or arc_count < 1 or west >= east or south >= north:
		return _fail("Road graph dimensions are invalid.")
	offsets_data_offset = node_data_offset + node_count * 8
	arcs_data_offset = offsets_data_offset + (node_count + 1) * 4
	var expected_size := arcs_data_offset + arc_count * 9
	if expected_size != bytes.size():
		return _fail("Road graph data is incomplete or has an invalid size.")
	network_bytes = bytes
	if not _validate_graph():
		_clear()
		return false
	_build_spatial_index()
	_build_spawn_candidates()
	_g_scores.resize(node_count)
	_g_stamp.resize(node_count)
	_closed_stamp.resize(node_count)
	_came_from.resize(node_count)
	_came_distance_m.resize(node_count)
	_came_seconds.resize(node_count)
	_epoch = 0
	last_error = ""
	return true


func route_between_uv(start_uv: Vector2, end_uv: Vector2) -> Dictionary:
	if network_bytes.is_empty():
		return _route_error("Road network has not loaded.")
	if not _uv_inside(start_uv) or not _uv_inside(end_uv):
		return _route_error("One or both locations are outside the available road coverage.")
	var start_snap := _nearest_node(start_uv)
	var end_snap := _nearest_node(end_uv)
	if not start_snap.get("ok", false) or not end_snap.get("ok", false):
		return _route_error("A location is not connected to a mapped road within 2 metres.")
	var start_node: int = start_snap["node"]
	var end_node: int = end_snap["node"]
	_epoch += 1
	if _epoch >= 2_000_000_000:
		_g_stamp.fill(0)
		_closed_stamp.fill(0)
		_epoch = 1
	_heap_keys.clear()
	_heap_nodes.clear()
	_g_scores[start_node] = 0.0
	_g_stamp[start_node] = _epoch
	_came_from[start_node] = -1
	_heap_push(_heuristic_seconds(start_node, end_node), start_node)
	var found := false
	var expansions := 0
	while not _heap_nodes.is_empty():
		var popped := _heap_pop()
		var current := int(popped.y)
		if _closed_stamp[current] == _epoch:
			continue
		if current == end_node:
			found = true
			break
		_closed_stamp[current] = _epoch
		expansions += 1
		# Hard cap prevents an unexpectedly disconnected regional graph from
		# freezing a mobile Web session. Hitting it is reported as a route failure.
		if expansions > 300_000:
			return _route_error("Route search exceeded the safe regional limit.")
		var first_arc := int(network_bytes.decode_u32(offsets_data_offset + current * 4))
		var after_last_arc := int(network_bytes.decode_u32(offsets_data_offset + (current + 1) * 4))
		for arc_index in range(first_arc, after_last_arc):
			var arc_offset := arcs_data_offset + arc_index * 9
			var next := int(network_bytes.decode_u32(arc_offset))
			if _closed_stamp[next] == _epoch:
				continue
			var edge_distance_m := float(network_bytes.decode_u32(arc_offset + 4))
			var road_class := int(network_bytes[arc_offset + 8])
			var speed_kmh: float = CLASS_SPEED_KMH[road_class]
			var edge_seconds := edge_distance_m * 3.6 / speed_kmh
			var next_score := _g_scores[current] + edge_seconds
			if _g_stamp[next] != _epoch or next_score < _g_scores[next]:
				_g_stamp[next] = _epoch
				_g_scores[next] = next_score
				_came_from[next] = current
				_came_distance_m[next] = edge_distance_m
				_came_seconds[next] = edge_seconds
				_heap_push(next_score + _heuristic_seconds(next, end_node), next)
	if not found:
		return _route_error("No directed road route connects these locations.")
	return _build_route(start_uv, end_uv, start_node, end_node,
		float(start_snap["distance_m"]), float(end_snap["distance_m"]))


## Pick a real road node suitable for a new partner or booking. Local roads are
## preferred; this excludes motorways, trunk and primary/secondary-only nodes.
## The returned UV is an exact node in this graph and therefore routes without
## off-road snapping. Returns (-1,-1) only if this graph has no eligible node.
func random_location_for_view(viewport_size: Vector2) -> Vector2:
	if _spawn_candidate_nodes.is_empty():
		return Vector2(-1.0, -1.0)
	var view := Vector2(maxf(1.0, viewport_size.x), maxf(1.0, viewport_size.y))
	var fit := maxf(view.x / UV_TEXTURE_WIDTH, view.y / UV_TEXTURE_HEIGHT)
	var visible_u := view.x / (UV_TEXTURE_WIDTH * fit)
	var visible_v := view.y / (UV_TEXTURE_HEIGHT * fit)
	var min_u := (1.0 - visible_u) * 0.5
	var max_u := 1.0 - min_u
	var min_v := maxf((1.0 - visible_v) * 0.5, 0.2)
	var max_v := minf(1.0 - min_v, 0.68)
	for _attempt in 256:
		var node_index: int = _spawn_candidate_nodes[randi_range(0, _spawn_candidate_nodes.size() - 1)]
		var uv := _node_uv(node_index)
		if uv.x >= min_u and uv.x <= max_u and uv.y >= min_v and uv.y <= max_v:
			return uv
	# Avoid returning an off-screen location if the chosen viewport band is sparse.
	var best := Vector2(-1.0, -1.0)
	var best_score := INF
	for node_index in _spawn_candidate_nodes:
		var uv := _node_uv(node_index)
		if uv.x >= min_u and uv.x <= max_u and uv.y >= 0.0 and uv.y <= 1.0:
			var score := absf(uv.y - clampf(0.44, min_v, max_v))
			if score < best_score:
				best_score = score
				best = uv
	return best if best.x >= 0.0 else _node_uv(_spawn_candidate_nodes[randi_range(0, _spawn_candidate_nodes.size() - 1)])


func _validate_graph() -> bool:
	var previous_offset := 0
	for node_index in range(node_count + 1):
		var value := int(network_bytes.decode_u32(offsets_data_offset + node_index * 4))
		if value < previous_offset or value > arc_count:
			last_error = "Road graph adjacency offsets are invalid."
			return false
		previous_offset = value
	if int(network_bytes.decode_u32(offsets_data_offset)) != 0 or previous_offset != arc_count:
		last_error = "Road graph adjacency index is incomplete."
		return false
	for node_index in range(node_count):
		var lat := network_bytes.decode_s32(node_data_offset + node_index * 8)
		var lon := network_bytes.decode_s32(node_data_offset + node_index * 8 + 4)
		if lat < int(south * 1_000_000.0) - 1 or lat > int(north * 1_000_000.0) + 1 or lon < int(west * 1_000_000.0) - 1 or lon > int(east * 1_000_000.0) + 1:
			last_error = "Road graph contains a coordinate outside its declared coverage."
			return false
	for arc_index in range(arc_count):
		var offset := arcs_data_offset + arc_index * 9
		var target := int(network_bytes.decode_u32(offset))
		var distance_m := int(network_bytes.decode_u32(offset + 4))
		var road_class := int(network_bytes[offset + 8])
		if target >= node_count or distance_m <= 0 or road_class >= CLASS_SPEED_KMH.size():
			last_error = "Road graph contains an invalid road edge."
			return false
	return true


func _build_spatial_index() -> void:
	var cell_count := GRID_WIDTH * GRID_HEIGHT
	var counts := PackedInt32Array()
	counts.resize(cell_count)
	counts.fill(0)
	for node_index in range(node_count):
		var cell := _cell_for_geo(_node_geo(node_index))
		counts[cell] += 1
	_grid_offsets.resize(cell_count + 1)
	_grid_offsets[0] = 0
	for index in range(cell_count):
		_grid_offsets[index + 1] = _grid_offsets[index] + counts[index]
	_grid_nodes.resize(node_count)
	var cursor := _grid_offsets.duplicate()
	for node_index in range(node_count):
		var cell := _cell_for_geo(_node_geo(node_index))
		_grid_nodes[cursor[cell]] = node_index
		cursor[cell] += 1


func _build_spawn_candidates() -> void:
	var eligible := PackedByteArray()
	eligible.resize(node_count)
	eligible.fill(0)
	for source in range(node_count):
		var first_arc := int(network_bytes.decode_u32(offsets_data_offset + source * 4))
		var after_last_arc := int(network_bytes.decode_u32(offsets_data_offset + (source + 1) * 4))
		for arc_index in range(first_arc, after_last_arc):
			var arc_offset := arcs_data_offset + arc_index * 9
			if network_bytes[arc_offset + 8] >= 4:
				eligible[source] = 1
				eligible[int(network_bytes.decode_u32(arc_offset))] = 1
	_spawn_candidate_nodes.clear()
	for node_index in range(node_count):
		if eligible[node_index] == 1:
			_spawn_candidate_nodes.append(node_index)


func _nearest_node(uv: Vector2) -> Dictionary:
	var query_geo := _uv_to_geo(uv)
	var cell_x := clampi(int((query_geo.x - west) / (east - west) * GRID_WIDTH), 0, GRID_WIDTH - 1)
	var cell_y := clampi(int((north - query_geo.y) / (north - south) * GRID_HEIGHT), 0, GRID_HEIGHT - 1)
	var best_node := -1
	var best_distance := INF
	# Two cells cover >200m in this bbox; the strict 2m limit ensures the final
	# endpoint is a real OSM node, while avoiding a full 521k-node scan per order.
	for dy in range(-2, 3):
		var y := cell_y + dy
		if y < 0 or y >= GRID_HEIGHT:
			continue
		for dx in range(-2, 3):
			var x := cell_x + dx
			if x < 0 or x >= GRID_WIDTH:
				continue
			var cell := y * GRID_WIDTH + x
			for at in range(_grid_offsets[cell], _grid_offsets[cell + 1]):
				var node_index: int = _grid_nodes[at]
				var distance := _geo_distance_m(query_geo, _node_geo(node_index))
				if distance < best_distance:
					best_distance = distance
					best_node = node_index
	if best_node < 0 or best_distance > MAX_SNAP_DISTANCE_M:
		return {"ok": false, "node": -1, "distance_m": best_distance}
	return {"ok": true, "node": best_node, "distance_m": best_distance}


func _build_route(start_uv: Vector2, end_uv: Vector2, start_node: int, end_node: int,
		start_snap_m: float, end_snap_m: float) -> Dictionary:
	var reversed_nodes: Array[int] = []
	var cursor := end_node
	while cursor != start_node:
		reversed_nodes.append(cursor)
		cursor = _came_from[cursor]
		if cursor < 0 or reversed_nodes.size() > node_count:
			return _route_error("The road route could not be reconstructed safely.")
	reversed_nodes.append(start_node)
	reversed_nodes.reverse()
	var points: Array[Vector2] = [start_uv]
	var lengths: Array[float] = []
	var segment_times: Array[float] = []
	var distance_total := 0.0
	var time_total := 0.0
	var node_start_uv := _node_uv(start_node)
	var start_connector := start_snap_m / 1000.0
	if start_connector > 0.00005:
		points.append(node_start_uv)
		lengths.append(start_connector)
		distance_total += start_connector
		var connector_time := start_connector * 3600.0 / 16.0
		segment_times.append(connector_time)
		time_total += connector_time
	else:
		points[0] = start_uv
	for index in range(reversed_nodes.size() - 1):
		var node_index := reversed_nodes[index + 1]
		var segment_km := _came_distance_m[node_index] / 1000.0
		points.append(_node_uv(node_index))
		lengths.append(segment_km)
		distance_total += segment_km
		segment_times.append(_came_seconds[node_index])
		time_total += _came_seconds[node_index]
	var end_node_uv := _node_uv(end_node)
	var end_connector := end_snap_m / 1000.0
	if end_connector > 0.00005:
		points.append(end_uv)
		lengths.append(end_connector)
		distance_total += end_connector
		var connector_time := end_connector * 3600.0 / 16.0
		segment_times.append(connector_time)
		time_total += connector_time
	else:
		points[points.size() - 1] = end_uv
	# When both coordinates snap to the same road node and neither connector is
	# needed, preserve a two-point zero-length geometry. The simulation can then
	# process an already-reached pickup without inventing distance or delaying it.
	if points.size() == 1:
		points.append(end_uv)
	return {
		"ok": true,
		"points": points,
		"segment_lengths_km": lengths,
		"segment_times_seconds": segment_times,
		"distance_km": distance_total,
		"estimated_time_seconds": time_total,
		"snap_distance_m": maxf(start_snap_m, end_snap_m),
		"error": "",
	}


func _node_geo(node_index: int) -> Vector2:
	var offset := node_data_offset + node_index * 8
	return Vector2(float(network_bytes.decode_s32(offset + 4)) / 1_000_000.0,
		float(network_bytes.decode_s32(offset)) / 1_000_000.0) # lon, lat


func _node_uv(node_index: int) -> Vector2:
	var geo := _node_geo(node_index)
	return _geo_to_uv(geo)


func _cell_for_geo(geo: Vector2) -> int:
	var x := clampi(int((geo.x - west) / (east - west) * GRID_WIDTH), 0, GRID_WIDTH - 1)
	var y := clampi(int((north - geo.y) / (north - south) * GRID_HEIGHT), 0, GRID_HEIGHT - 1)
	return y * GRID_WIDTH + x


func _heuristic_seconds(from_node: int, to_node: int) -> float:
	return _geo_distance_m(_node_geo(from_node), _node_geo(to_node)) * 3.6 / MAX_ROUTE_SPEED_KMH * 0.99


func _geo_distance_m(first: Vector2, second: Vector2) -> float:
	var mean_lat := deg_to_rad((first.y + second.y) * 0.5)
	var north_m := (second.y - first.y) * 111_195.0
	var east_m := (second.x - first.x) * 111_195.0 * cos(mean_lat)
	return sqrt(north_m * north_m + east_m * east_m)


func _geo_to_uv(geo: Vector2) -> Vector2:
	var x := (geo.x - west) / (east - west)
	var north_mercator := log(tan(PI / 4.0 + deg_to_rad(north) / 2.0))
	var south_mercator := log(tan(PI / 4.0 + deg_to_rad(south) / 2.0))
	var point_mercator := log(tan(PI / 4.0 + deg_to_rad(geo.y) / 2.0))
	var y := 1.0 - (point_mercator - south_mercator) / (north_mercator - south_mercator)
	return Vector2(x, y)


func _uv_to_geo(uv: Vector2) -> Vector2:
	var longitude := west + uv.x * (east - west)
	var north_mercator := log(tan(PI / 4.0 + deg_to_rad(north) / 2.0))
	var south_mercator := log(tan(PI / 4.0 + deg_to_rad(south) / 2.0))
	var mercator_y := north_mercator - uv.y * (north_mercator - south_mercator)
	var latitude := rad_to_deg(2.0 * atan(exp(mercator_y)) - PI / 2.0)
	return Vector2(longitude, latitude)


func _uv_inside(uv: Vector2) -> bool:
	return uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0


func _route_error(message: String) -> Dictionary:
	return {"ok": false, "points": [], "segment_lengths_km": [], "distance_km": 0.0,
		"segment_times_seconds": [], "estimated_time_seconds": 0.0, "snap_distance_m": INF, "error": message}


func _fail(message: String) -> bool:
	last_error = message
	return false


func _clear() -> void:
	network_bytes = PackedByteArray()
	node_count = 0
	arc_count = 0
	_grid_offsets.clear()
	_grid_nodes.clear()
	_spawn_candidate_nodes.clear()
	_g_scores.clear()
	_g_stamp.clear()
	_closed_stamp.clear()
	_came_from.clear()
	_came_distance_m.clear()
	_came_seconds.clear()
	_heap_keys.clear()
	_heap_nodes.clear()


func _heap_push(key: float, node_index: int) -> void:
	var index := _heap_nodes.size()
	_heap_keys.append(key)
	_heap_nodes.append(node_index)
	while index > 0:
		var parent := (index - 1) >> 1
		if _heap_keys[parent] <= key:
			break
		_heap_keys[index] = _heap_keys[parent]
		_heap_nodes[index] = _heap_nodes[parent]
		index = parent
	_heap_keys[index] = key
	_heap_nodes[index] = node_index


func _heap_pop() -> Vector2:
	var result := Vector2(_heap_keys[0], _heap_nodes[0])
	var last := _heap_nodes.size() - 1
	if last == 0:
		_heap_nodes.clear()
		_heap_keys.clear()
		return result
	var key := _heap_keys[last]
	var node_index := _heap_nodes[last]
	_heap_nodes.resize(last)
	_heap_keys.resize(last)
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= last:
			break
		var right := left + 1
		var child := right if right < last and _heap_keys[right] < _heap_keys[left] else left
		if _heap_keys[child] >= key:
			break
		_heap_keys[index] = _heap_keys[child]
		_heap_nodes[index] = _heap_nodes[child]
		index = child
	_heap_keys[index] = key
	_heap_nodes[index] = node_index
	return result
