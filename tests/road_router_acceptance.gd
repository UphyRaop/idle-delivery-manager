extends SceneTree

## Standalone routing acceptance suite. Run after Godot import:
## godot --headless --path . -s tests/road_router_acceptance.gd
const WEST := 101.55
const SOUTH := 2.98
const EAST := 101.83
const NORTH := 3.30
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_real_osm_route_uses_road_geometry()
	_test_generated_locations_are_visible_and_routable()
	_test_disconnected_graph_fails_closed()
	_test_one_way_direction_is_respected()
	_test_invalid_graph_is_rejected()
	print("ROUTING RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _test_real_osm_route_uses_road_geometry() -> void:
	var router := IDMRoadRouter.new()
	var loaded: bool = router.load_network()
	_check(loaded, "bundled OSM road graph loads")
	if not loaded:
		return
	# Actual OSM nodes on Jalan Batu Tiga Lama way 110, indexes 3 and 29,
	# from the committed ODbL graph. The routed road polyline is ~0.81 km;
	# the geodesic chord is ~0.59 km, so direct interpolation is detectable.
	var start_uv := Vector2(0.0233142857143, 0.6958103348857)
	var end_uv := Vector2(0.0415285714286, 0.6907106404986)
	var result: Dictionary = router.route_between_uv(start_uv, end_uv)
	_check(result.get("ok", false), "known connected OSM locations route successfully")
	if not result.get("ok", false):
		print("route failure: %s" % result.get("error", "no message"))
		return
	var points: Array = result.get("points", [])
	var distance := float(result.get("distance_km", 0.0))
	var chord := _haversine_km(Vector2(3.077351, 101.556528), Vector2(3.078983, 101.561628))
	_check(points.size() >= 3, "route contains intermediate road geometry")
	_check(distance > chord * 1.02, "route distance follows a road detour, not a straight line")
	_check(distance > 0.5 and distance < 2.0, "known OSM route distance is within a plausible range")
	_check(float(result.get("estimated_time_seconds", 0.0)) > 0.0, "route includes a positive ETA")
	_check(float(result.get("snap_distance_m", 1.0e9)) <= 5.0, "route endpoints snap to nearby road nodes")
	var all_points_valid := points.size() >= 2
	for point in points:
		var uv := Vector2(point)
		all_points_valid = all_points_valid and is_finite(uv.x) and is_finite(uv.y) and uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0
	_check(all_points_valid, "road polyline points stay within the normalized geographic map")
	var lengths: Array = result.get("segment_lengths_km", [])
	var lengths_valid := lengths.size() == points.size() - 1
	var summed := 0.0
	for segment in lengths:
		var length := float(segment)
		lengths_valid = lengths_valid and is_finite(length) and length > 0.0
		summed += length
	_check(lengths_valid, "each route segment has a positive real distance")
	_check(absf(summed - distance) <= maxf(0.002, distance * 0.02), "segment lengths sum to routed distance")
	var segment_times: Array = result.get("segment_times_seconds", [])
	var time_sum := 0.0
	var times_valid := segment_times.size() == lengths.size()
	for segment_time in segment_times:
		var value := float(segment_time)
		times_valid = times_valid and is_finite(value) and value > 0.0
		time_sum += value
	_check(times_valid, "each route segment has a positive travel time")
	_check(absf(time_sum - float(result.get("estimated_time_seconds", 0.0))) <= 0.01, "segment travel times sum to ETA")
	var same_location: Dictionary = router.route_between_uv(start_uv, start_uv)
	_check(same_location.get("ok", false) and same_location["distance_km"] == 0.0 and same_location["points"].size() == 2, "already-reached route preserves zero-distance geometry")

func _test_disconnected_graph_fails_closed() -> void:
	var router := IDMRoadRouter.new()
	var synthetic := _make_graph_bytes([
		Vector2(3.10, 101.60), Vector2(3.1005, 101.6005),
		Vector2(3.20, 101.70), Vector2(3.2005, 101.7005),
	], [[0, 1, 300, 5], [1, 0, 300, 5], [2, 3, 300, 5], [3, 2, 300, 5]])
	var loaded: bool = router.load_network_bytes(synthetic)
	_check(loaded, "synthetic disconnected graph loads")
	if not loaded:
		return
	var result: Dictionary = router.route_between_uv(_geo_to_uv(Vector2(3.10, 101.60)), _geo_to_uv(Vector2(3.20, 101.70)))
	_check(not result.get("ok", false), "unreachable destination returns a route failure")
	_check(result.get("points", []).is_empty(), "failed route does not contain fallback or teleport geometry")
	_check(not str(result.get("error", "")).is_empty(), "unreachable route has a useful error")

func _test_generated_locations_are_visible_and_routable() -> void:
	var router := IDMRoadRouter.new()
	if not router.load_network():
		_check(false, "router loads before testing road-based spawn locations")
		return
	seed(83721)
	var viewport := Vector2(390, 844)
	var all_valid := true
	for index in 20:
		var uv := router.random_location_for_view(viewport)
		var in_mobile_band := uv.x >= 0.235 and uv.x <= 0.765 and uv.y >= 0.20 and uv.y <= 0.68
		var route: Dictionary = router.route_between_uv(uv, uv)
		all_valid = all_valid and in_mobile_band and route.get("ok", false) and float(route.get("snap_distance_m", INF)) < 0.01
	_check(all_valid, "sampled booking/rider spawn nodes are visible and route exactly to the road graph")

func _test_invalid_graph_is_rejected() -> void:
	var router := IDMRoadRouter.new()
	_check(not router.load_network_bytes(PackedByteArray([0, 1, 2, 3])), "malformed route graph is rejected")

func _test_one_way_direction_is_respected() -> void:
	var router := IDMRoadRouter.new()
	var first := Vector2(3.10, 101.60)
	var second := Vector2(3.101, 101.601)
	var synthetic := _make_graph_bytes([first, second], [[0, 1, 300, 5]])
	_check(router.load_network_bytes(synthetic), "synthetic directed road graph loads")
	var forward: Dictionary = router.route_between_uv(_geo_to_uv(first), _geo_to_uv(second))
	var reverse: Dictionary = router.route_between_uv(_geo_to_uv(second), _geo_to_uv(first))
	_check(forward.get("ok", false), "one-way road allows travel in its encoded direction")
	_check(not reverse.get("ok", false), "router does not violate a one-way road")

func _make_graph_bytes(nodes: Array, arcs: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.append_array("IDMG".to_ascii_buffer())
	_put_u16(bytes, 1)
	for number in [WEST, SOUTH, EAST, NORTH]:
		_put_f64(bytes, float(number))
	_put_u32(bytes, nodes.size())
	_put_u32(bytes, arcs.size())
	for location in nodes:
		var point := Vector2(location)
		_put_s32(bytes, roundi(point.x * 1000000.0))
		_put_s32(bytes, roundi(point.y * 1000000.0))
	var outgoing_by_node: Array = []
	for index in nodes.size():
		outgoing_by_node.append([])
	for arc in arcs:
		outgoing_by_node[int(arc[0])].append(arc)
	var cursor := 0
	_put_u32(bytes, cursor)
	for outgoing in outgoing_by_node:
		cursor += outgoing.size()
		_put_u32(bytes, cursor)
	for outgoing in outgoing_by_node:
		for arc in outgoing:
			_put_u32(bytes, int(arc[1]))
			_put_u32(bytes, int(arc[2]))
			_put_u8(bytes, int(arc[3]))
	return bytes

func _geo_to_uv(lat_lon: Vector2) -> Vector2:
	var mercator := func(latitude: float) -> float:
		return log(tan(PI / 4.0 + deg_to_rad(latitude) / 2.0))
	var x := (lat_lon.y - WEST) / (EAST - WEST)
	var y: float = 1.0 - (float(mercator.call(lat_lon.x)) - float(mercator.call(SOUTH))) / (float(mercator.call(NORTH)) - float(mercator.call(SOUTH)))
	return Vector2(x, y)

func _haversine_km(a_lat_lon: Vector2, b_lat_lon: Vector2) -> float:
	var a_lat := deg_to_rad(a_lat_lon.x)
	var b_lat := deg_to_rad(b_lat_lon.x)
	var d_lat := b_lat - a_lat
	var d_lon := deg_to_rad(b_lat_lon.y - a_lat_lon.y)
	var value := sin(d_lat / 2.0) ** 2 + cos(a_lat) * cos(b_lat) * sin(d_lon / 2.0) ** 2
	return 6371.0088 * 2.0 * asin(sqrt(value))

func _put_u8(bytes: PackedByteArray, value: int) -> void:
	bytes.append(value & 0xff)

func _put_u16(bytes: PackedByteArray, value: int) -> void:
	_put_u8(bytes, value)
	_put_u8(bytes, value >> 8)

func _put_u32(bytes: PackedByteArray, value: int) -> void:
	for shift in [0, 8, 16, 24]:
		_put_u8(bytes, value >> shift)

func _put_s32(bytes: PackedByteArray, value: int) -> void:
	_put_u32(bytes, value if value >= 0 else (1 << 32) + value)

func _put_f64(bytes: PackedByteArray, value: float) -> void:
	var encoded := PackedByteArray()
	encoded.resize(8)
	encoded.encode_double(0, value)
	bytes.append_array(encoded)

func _check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: %s" % description)
	else:
		failed += 1
		push_error("FAIL: %s" % description)
