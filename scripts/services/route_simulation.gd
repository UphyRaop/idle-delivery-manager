extends RefCounted
class_name IDMRouteSimulation

## Advances a partner along two real-road polyline legs: current position to
## pickup, then pickup to destination. The caller supplies fixed simulation
## time (already scaled by the simulation clock); rendering delta is never used.
##
## Router success dictionaries use normalized map UV points, exact segment
## distances, and road-class segment times. The latter control both movement
## and ETA; the simulation speed multiplier scales simulation time.

const SAVE_VERSION := 2
const PHASE_IDLE := "idle"
const PHASE_PICKUP := "to_pickup"
const PHASE_DROPOFF := "to_dropoff"
const PHASE_DELIVERED := "delivered"
const PHASE_FAILED := "failed"
const MIN_SEGMENT_KM := 0.000001
const MAX_SPEED_KPH := 180.0

var phase: String = PHASE_IDLE
var error_message: String = ""
var partner_speed_kph: float = 25.0
var pickup_route: Dictionary = {}
var dropoff_route: Dictionary = {}
var distance_on_leg_km: float = 0.0
var time_on_leg_seconds: float = 0.0
var current_uv: Vector2 = Vector2.ZERO
var _events_emitted: Dictionary = {}


## Begin a routed two-leg job. Both legs must contain valid geometry; a failed
## or disconnected route fails closed and cannot move the partner.
func initialize(pickup: Dictionary, dropoff: Dictionary, speed_kph: float = 25.0) -> bool:
	if is_active():
		return false
	var pickup_checked := _validated_route(pickup)
	var dropoff_checked := _validated_route(dropoff)
	if not pickup_checked.get("ok", false):
		_fail(str(pickup_checked.get("error", "Pickup route unavailable")))
		return false
	if not dropoff_checked.get("ok", false):
		_fail(str(dropoff_checked.get("error", "Delivery route unavailable")))
		return false
	if not _endpoints_connect(pickup_checked, dropoff_checked):
		_fail("Pickup and delivery routes do not connect")
		return false
	if not is_finite(speed_kph) or speed_kph <= 0.0 or speed_kph > MAX_SPEED_KPH:
		_fail("Invalid partner road speed")
		return false
	pickup_route = pickup_checked
	dropoff_route = dropoff_checked
	partner_speed_kph = speed_kph
	_apply_partner_speed_scale(pickup_route, speed_kph)
	_apply_partner_speed_scale(dropoff_route, speed_kph)
	distance_on_leg_km = 0.0
	time_on_leg_seconds = 0.0
	current_uv = pickup_route["points"][0]
	_events_emitted.clear()
	error_message = ""
	phase = PHASE_PICKUP
	return true


## Advance by simulation seconds, not wall-clock/render delta. The simulation
## clock should pass zero while paused. Returns each transition once in order.
func advance(real_delta_seconds: float, speed_multiplier: float = 1.0) -> Array[String]:
	var events: Array[String] = []
	if not is_active() or not is_finite(real_delta_seconds) or real_delta_seconds <= 0.0 or not is_finite(speed_multiplier) or speed_multiplier <= 0.0:
		return events
	var simulation_seconds := real_delta_seconds * speed_multiplier
	var time_budget := simulation_seconds
	while time_budget > 0.0 and is_active():
		var leg: Dictionary = pickup_route if phase == PHASE_PICKUP else dropoff_route
		var remaining := maxf(0.0, float(leg["estimated_time_seconds"]) - time_on_leg_seconds)
		var elapsed := minf(time_budget, remaining)
		time_on_leg_seconds += elapsed
		time_budget -= elapsed
		var progress := _progress_on_route(leg, time_on_leg_seconds)
		current_uv = progress["uv"]
		distance_on_leg_km = progress["distance_km"]
		if time_on_leg_seconds + 0.0000001 < float(leg["estimated_time_seconds"]):
			break
		if phase == PHASE_PICKUP:
			phase = PHASE_DROPOFF
			distance_on_leg_km = 0.0
			time_on_leg_seconds = 0.0
			current_uv = dropoff_route["points"][0]
			if not _events_emitted.has("reached_pickup"):
				_events_emitted["reached_pickup"] = true
				events.append("reached_pickup")
		else:
			current_uv = dropoff_route["points"][-1]
			distance_on_leg_km = float(dropoff_route["distance_km"])
			phase = PHASE_DELIVERED
			if not _events_emitted.has("delivered"):
				_events_emitted["delivered"] = true
				events.append("delivered")
	return events


func is_active() -> bool:
	return phase == PHASE_PICKUP or phase == PHASE_DROPOFF


func total_distance_km() -> float:
	if pickup_route.is_empty() or dropoff_route.is_empty():
		return 0.0
	return float(pickup_route.get("distance_km", 0.0)) + float(dropoff_route.get("distance_km", 0.0))


func travelled_distance_km() -> float:
	if phase == PHASE_PICKUP:
		return distance_on_leg_km
	if phase in [PHASE_DROPOFF, PHASE_DELIVERED]:
		return float(pickup_route.get("distance_km", 0.0)) + distance_on_leg_km
	return 0.0


func current_route_points() -> Array:
	if phase == PHASE_PICKUP:
		return pickup_route.get("points", []).duplicate()
	if phase == PHASE_DROPOFF:
		return dropoff_route.get("points", []).duplicate()
	return []


func remaining_distance_km() -> float:
	if phase == PHASE_PICKUP:
		return maxf(0.0, float(pickup_route.get("distance_km", 0.0)) - distance_on_leg_km) + float(dropoff_route.get("distance_km", 0.0))
	if phase == PHASE_DROPOFF:
		return maxf(0.0, float(dropoff_route.get("distance_km", 0.0)) - distance_on_leg_km)
	return 0.0


func estimated_remaining_seconds(speed_multiplier: float = 1.0) -> float:
	if not is_active() or partner_speed_kph <= 0.0:
		return 0.0
	if not is_finite(speed_multiplier) or speed_multiplier <= 0.0:
		return -1.0 # Paused: no finite wall-clock ETA.
	var remaining_sim_seconds := 0.0
	if phase == PHASE_PICKUP:
		remaining_sim_seconds = maxf(0.0, float(pickup_route["estimated_time_seconds"]) - time_on_leg_seconds) + float(dropoff_route["estimated_time_seconds"])
	else:
		remaining_sim_seconds = maxf(0.0, float(dropoff_route["estimated_time_seconds"]) - time_on_leg_seconds)
	return remaining_sim_seconds / speed_multiplier


func total_estimated_seconds() -> float:
	if pickup_route.is_empty() or dropoff_route.is_empty():
		return 0.0
	return float(pickup_route["estimated_time_seconds"]) + float(dropoff_route["estimated_time_seconds"])


## Serializable snapshot for JSON saves. No Vector2 or Object values escape.
func to_save() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"phase": phase,
		"error_message": error_message,
		"partner_speed_kph": partner_speed_kph,
		"pickup_route": _route_to_save(pickup_route),
		"dropoff_route": _route_to_save(dropoff_route),
		"distance_on_leg_km": distance_on_leg_km,
		"time_on_leg_seconds": time_on_leg_seconds,
		"current_uv": [current_uv.x, current_uv.y],
		"events_emitted": _events_emitted.duplicate(),
	}


## Restore only this service's current version. Legacy saves without routed
## geometry must stay in the caller's legacy migration path; never invent a
## route from their old normalized positions.
func restore(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != SAVE_VERSION:
		return false
	var restored_phase := str(data.get("phase", PHASE_IDLE))
	if restored_phase not in [PHASE_IDLE, PHASE_PICKUP, PHASE_DROPOFF, PHASE_DELIVERED, PHASE_FAILED]:
		return false
	var pick := _validated_route(_route_from_save(data.get("pickup_route", {}))) if data.get("pickup_route", {}) is Dictionary else {"ok": false}
	var drop := _validated_route(_route_from_save(data.get("dropoff_route", {}))) if data.get("dropoff_route", {}) is Dictionary else {"ok": false}
	if restored_phase in [PHASE_PICKUP, PHASE_DROPOFF, PHASE_DELIVERED] and (not pick.get("ok", false) or not drop.get("ok", false) or not _endpoints_connect(pick, drop)):
		return false
	var speed := float(data.get("partner_speed_kph", 25.0))
	var travelled := float(data.get("distance_on_leg_km", 0.0))
	var elapsed := float(data.get("time_on_leg_seconds", 0.0))
	if not is_finite(speed) or speed <= 0.0 or speed > MAX_SPEED_KPH or not is_finite(travelled) or travelled < 0.0 or not is_finite(elapsed) or elapsed < 0.0:
		return false
	var raw_uv: Variant = data.get("current_uv", [])
	if not raw_uv is Array or raw_uv.size() != 2:
		return false
	var uv := Vector2(float(raw_uv[0]), float(raw_uv[1]))
	if not _valid_uv(uv):
		return false
	if restored_phase == PHASE_PICKUP and travelled > float(pick["distance_km"]) + 0.000001:
		return false
	if restored_phase == PHASE_DROPOFF and travelled > float(drop["distance_km"]) + 0.000001:
		return false
	if restored_phase == PHASE_DELIVERED and absf(travelled - float(drop["distance_km"])) > 0.000001:
		return false
	if restored_phase == PHASE_PICKUP and elapsed > float(pick["estimated_time_seconds"]) + 0.000001:
		return false
	if restored_phase == PHASE_DROPOFF and elapsed > float(drop["estimated_time_seconds"]) + 0.000001:
		return false
	if restored_phase == PHASE_DELIVERED and absf(elapsed - float(drop["estimated_time_seconds"])) > 0.000001:
		return false
	if restored_phase == PHASE_PICKUP and _progress_on_route(pick, elapsed)["uv"].distance_to(uv) > 0.00001:
		return false
	if restored_phase == PHASE_DROPOFF and _progress_on_route(drop, elapsed)["uv"].distance_to(uv) > 0.00001:
		return false
	if restored_phase == PHASE_DELIVERED and Vector2(drop["points"][-1]).distance_to(uv) > 0.00001:
		return false
	phase = restored_phase
	error_message = str(data.get("error_message", ""))
	partner_speed_kph = speed
	pickup_route = pick if pick.get("ok", false) else {}
	dropoff_route = drop if drop.get("ok", false) else {}
	distance_on_leg_km = travelled
	time_on_leg_seconds = elapsed
	current_uv = uv
	_events_emitted = data.get("events_emitted", {}).duplicate(true) if data.get("events_emitted", {}) is Dictionary else {}
	return true


func _validated_route(route: Dictionary) -> Dictionary:
	if not route.get("ok", false):
		return {"ok": false, "error": str(route.get("error", "Road route unavailable"))}
	var points: Array = route.get("points", [])
	var total := float(route.get("distance_km", 0.0))
	if points.size() < 2 or not is_finite(total) or total < 0.0:
		return {"ok": false, "error": "Road route has no usable geometry"}
	for point in points:
		if not point is Vector2 or not _valid_uv(point):
			return {"ok": false, "error": "Road route contains an invalid coordinate"}
	var lengths: Array = route.get("segment_lengths_km", [])
	var times: Array = route.get("segment_times_seconds", [])
	var estimated_time := float(route.get("estimated_time_seconds", 0.0))
	if total == 0.0 and estimated_time == 0.0 and lengths.is_empty() and times.is_empty() and Vector2(points[0]).distance_to(Vector2(points[-1])) <= 0.00001:
		return {"ok": true, "points": points.duplicate(), "distance_km": 0.0, "segment_lengths_km": [], "estimated_time_seconds": 0.0, "segment_times_seconds": []}
	if total <= 0.0:
		return {"ok": false, "error": "Road route has no usable geometry"}
	if lengths.is_empty():
		return {"ok": false, "error": "Road route is missing per-segment distances"}
	if lengths.size() != points.size() - 1 or times.size() != points.size() - 1:
		return {"ok": false, "error": "Road route per-segment distances or times are inconsistent"}
	if not is_finite(estimated_time) or estimated_time <= 0.0:
		return {"ok": false, "error": "Road route is missing its travel time estimate"}
	var distance_sum := 0.0
	var time_sum := 0.0
	for index in lengths.size():
		var length: Variant = lengths[index]
		var value := float(length)
		if not is_finite(value) or value <= 0.0:
			return {"ok": false, "error": "Road route contains a zero-length segment"}
		var edge_time := float(times[index])
		if not is_finite(edge_time) or edge_time <= 0.0:
			return {"ok": false, "error": "Road route contains an invalid segment time"}
		distance_sum += value
		time_sum += edge_time
	if absf(distance_sum - total) > maxf(0.002, total * 0.02):
		return {"ok": false, "error": "Road route distance does not match its segments"}
	if absf(time_sum - estimated_time) > maxf(0.1, estimated_time * 0.02):
		return {"ok": false, "error": "Road route ETA does not match its segment times"}
	# Normalize small rounding differences while retaining router totals.
	for index in lengths.size():
		lengths[index] = float(lengths[index]) * total / distance_sum
		times[index] = float(times[index]) * estimated_time / time_sum
	return {"ok": true, "points": points.duplicate(), "distance_km": total, "segment_lengths_km": lengths, "estimated_time_seconds": estimated_time, "segment_times_seconds": times}


func _progress_on_route(route: Dictionary, elapsed_seconds: float) -> Dictionary:
	var points: Array = route["points"]
	var lengths: Array = route["segment_lengths_km"]
	var times: Array = route["segment_times_seconds"]
	var remaining := clampf(elapsed_seconds, 0.0, float(route["estimated_time_seconds"]))
	var distance_travelled := 0.0
	for index in lengths.size():
		var segment_time := float(times[index])
		var segment_length := float(lengths[index])
		if remaining <= segment_time or index == lengths.size() - 1:
			var fraction := clampf(remaining / segment_time, 0.0, 1.0)
			return {"uv": Vector2(points[index]).lerp(Vector2(points[index + 1]), fraction), "distance_km": distance_travelled + segment_length * fraction}
		remaining -= segment_time
		distance_travelled += segment_length
	return {"uv": points[-1], "distance_km": distance_travelled}


func _apply_partner_speed_scale(route: Dictionary, speed_kph: float) -> void:
	var times: Array = route["segment_times_seconds"]
	var scale := 25.0 / speed_kph
	var total := 0.0
	for index in times.size():
		times[index] = float(times[index]) * scale
		total += float(times[index])
	route["estimated_time_seconds"] = total


func _endpoints_connect(pick: Dictionary, drop: Dictionary) -> bool:
	if pick.get("points", []).is_empty() or drop.get("points", []).is_empty():
		return false
	return Vector2(pick["points"][-1]).distance_to(Vector2(drop["points"][0])) <= 0.00001


func _valid_uv(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y) and value.x >= 0.0 and value.x <= 1.0 and value.y >= 0.0 and value.y <= 1.0


func _fail(message: String) -> void:
	phase = PHASE_FAILED
	error_message = message
	distance_on_leg_km = 0.0
	pickup_route = {}
	dropoff_route = {}
	_events_emitted.clear()


func _route_to_save(route: Dictionary) -> Dictionary:
	if route.is_empty():
		return {}
	var points: Array = []
	for point in route.get("points", []):
		points.append([point.x, point.y])
	return {
		"ok": true,
		"points": points,
		"distance_km": route["distance_km"],
		"segment_lengths_km": route["segment_lengths_km"].duplicate(),
		"segment_times_seconds": route["segment_times_seconds"].duplicate(),
		"estimated_time_seconds": route["estimated_time_seconds"],
	}


func _route_from_save(route: Dictionary) -> Dictionary:
	var points: Array[Vector2] = []
	var raw_points: Variant = route.get("points", [])
	if not raw_points is Array:
		return {"ok": false}
	for raw_point in raw_points:
		if not raw_point is Array or raw_point.size() != 2:
			return {"ok": false}
		points.append(Vector2(float(raw_point[0]), float(raw_point[1])))
	return {
		"ok": bool(route.get("ok", false)),
		"points": points,
		"distance_km": float(route.get("distance_km", 0.0)),
		"segment_lengths_km": route.get("segment_lengths_km", []),
		"segment_times_seconds": route.get("segment_times_seconds", []),
		"estimated_time_seconds": float(route.get("estimated_time_seconds", 0.0)),
		"error": str(route.get("error", "")),
	}
