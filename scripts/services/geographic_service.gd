extends RefCounted
class_name IDMGeographicService

## Local, bundled OSM geography; all locations in the external data are WGS84.
## The UI coordinates returned here are texture UVs using the same Web Mercator
## projection used by tools/build_osm_roads.py.
const WEST := 101.55
const SOUTH := 2.98
const EAST := 101.83
const NORTH := 3.30
const TEXTURE_SIZE := Vector2(1152, 1320)
const SPAWN_PATH := "res://data/kl_selangor_spawns.json"
const PLACES_PATH := "res://data/kl_selangor_places.json"

var spawn_points: Array[Vector2] = []
var places: Array[Dictionary] = []

func load_data() -> bool:
	spawn_points.clear()
	places.clear()
	var spawn_data: Variant = _read_json(SPAWN_PATH)
	if typeof(spawn_data) != TYPE_ARRAY:
		return false
	for value in spawn_data:
		if typeof(value) != TYPE_ARRAY or value.size() < 2:
			continue
		var location := Vector2(float(value[1]) / 1_000_000.0, float(value[0]) / 1_000_000.0)
		spawn_points.append(geo_to_uv(location.y, location.x))
	var place_data: Variant = _read_json(PLACES_PATH)
	if typeof(place_data) == TYPE_ARRAY:
		for value in place_data:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var place: Dictionary = value
			place["uv"] = geo_to_uv(float(place.get("lat_e6", 0)) / 1_000_000.0, float(place.get("lon_e6", 0)) / 1_000_000.0)
			places.append(place)
	return not spawn_points.is_empty()

func random_road_location(view_size: Vector2 = Vector2(390, 844)) -> Vector2:
	if spawn_points.is_empty():
		return Vector2(0.5, 0.5)
	var scale := maxf(view_size.x / TEXTURE_SIZE.x, view_size.y / TEXTURE_SIZE.y)
	var visible_u := view_size.x / (TEXTURE_SIZE.x * scale)
	var visible_v := view_size.y / (TEXTURE_SIZE.y * scale)
	var min_u := (1.0 - visible_u) * 0.5
	var max_u := 1.0 - min_u
	var min_v := maxf((1.0 - visible_v) * 0.5, 0.20)
	var max_v := minf(1.0 - min_v, 0.68)
	var eligible: Array[Vector2] = []
	for point in spawn_points:
		if point.x >= min_u and point.x <= max_u and point.y >= min_v and point.y <= max_v:
			eligible.append(point)
	if eligible.is_empty():
		return spawn_points[randi_range(0, spawn_points.size() - 1)]
	return eligible[randi_range(0, eligible.size() - 1)]

func geo_to_uv(latitude: float, longitude: float) -> Vector2:
	var x := (longitude - WEST) / (EAST - WEST)
	var north_mercator := log(tan(PI / 4.0 + deg_to_rad(NORTH) / 2.0))
	var south_mercator := log(tan(PI / 4.0 + deg_to_rad(SOUTH) / 2.0))
	var point_mercator := log(tan(PI / 4.0 + deg_to_rad(latitude) / 2.0))
	var y := 1.0 - (point_mercator - south_mercator) / (north_mercator - south_mercator)
	return Vector2(clampf(x, 0.0, 1.0), clampf(y, 0.0, 1.0))

func uv_to_geo(uv: Vector2) -> Vector2:
	var longitude := WEST + uv.x * (EAST - WEST)
	var north_mercator := log(tan(PI / 4.0 + deg_to_rad(NORTH) / 2.0))
	var south_mercator := log(tan(PI / 4.0 + deg_to_rad(SOUTH) / 2.0))
	var mercator_y := north_mercator - uv.y * (north_mercator - south_mercator)
	var latitude := rad_to_deg(2.0 * atan(exp(mercator_y)) - PI / 2.0)
	return Vector2(longitude, latitude)

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed := JSON.new()
	if parsed.parse(file.get_as_text()) != OK:
		return null
	return parsed.data
