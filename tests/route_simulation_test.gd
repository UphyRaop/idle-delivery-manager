extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	_test_two_leg_progress_and_speed()
	_test_pause_and_restore()
	_test_already_at_pickup()
	_test_reject_bad_routes()
	print("ROUTE SIMULATION RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		printerr("FAIL: " + label)

func _route(points: Array[Vector2], lengths: Array[float], times: Array[float], distance: float) -> Dictionary:
	var total_time := 0.0
	for seconds in times:
		total_time += seconds
	return {"ok": true, "points": points, "segment_lengths_km": lengths, "segment_times_seconds": times, "distance_km": distance, "estimated_time_seconds": total_time}

func _test_two_leg_progress_and_speed() -> void:
	var sim := IDMRouteSimulation.new()
	var pickup := _route([Vector2(0.1, 0.1), Vector2(0.2, 0.1)], [2.0], [200.0], 2.0)
	var dropoff := _route([Vector2(0.2, 0.1), Vector2(0.22, 0.1), Vector2(0.25, 0.15)], [0.5, 2.5], [100.0, 200.0], 3.0)
	_check(sim.initialize(pickup, dropoff, 25.0), "valid connected pickup and dropoff routes initialize")
	_check(is_equal_approx(sim.total_distance_km(), 5.0), "route mileage sums both routed legs")
	_check(is_equal_approx(sim.total_estimated_seconds(), 500.0), "route timing sums road-class segment ETAs")
	_check(is_equal_approx(sim.estimated_remaining_seconds(), 500.0), "ETA uses router segment timing")
	_check(sim.advance(100.0, 1.0).is_empty(), "partner advances without skipping an incomplete pickup leg")
	_check(sim.current_uv.distance_to(Vector2(0.15, 0.1)) < 0.000001, "partner position interpolates on pickup road geometry")
	_check(is_equal_approx(sim.travelled_distance_km(), 1.0), "route mileage records travelled road distance")
	_check(is_equal_approx(sim.estimated_remaining_seconds(5.0), 80.0), "5x simulation speed scales ETA consistently")
	var pickup_events := sim.advance(100.0, 1.0)
	_check(pickup_events == ["reached_pickup"] and sim.phase == IDMRouteSimulation.PHASE_DROPOFF, "pickup event occurs once before delivery leg")
	sim.advance(50.0, 1.0)
	_check(sim.current_uv.distance_to(Vector2(0.21, 0.1)) < 0.000001, "movement follows per-edge road-class time rather than uniform distance time")
	var delivery_events := sim.advance(50.0, 5.0)
	_check(delivery_events == ["delivered"] and sim.phase == IDMRouteSimulation.PHASE_DELIVERED, "5x speed completes the dropoff leg")
	_check(sim.current_uv.distance_to(Vector2(0.25, 0.15)) < 0.000001, "completed partner ends at routed destination")
	_check(sim.advance(10.0, 10.0).is_empty(), "completed delivery cannot emit a duplicate completion")

func _test_pause_and_restore() -> void:
	var sim := IDMRouteSimulation.new()
	var pickup := _route([Vector2(0.1, 0.1), Vector2(0.2, 0.1)], [2.0], [200.0], 2.0)
	var dropoff := _route([Vector2(0.2, 0.1), Vector2(0.25, 0.15)], [3.0], [300.0], 3.0)
	sim.initialize(pickup, dropoff, 25.0)
	var before := sim.current_uv
	_check(sim.advance(60.0, 0.0).is_empty() and sim.current_uv == before, "zero speed multiplier pauses without movement")
	sim.advance(200.0, 1.0)
	_check(sim.phase == IDMRouteSimulation.PHASE_DROPOFF, "pickup progress transitions to the delivery leg")
	var encoded := JSON.stringify(sim.to_save())
	var decoded: Variant = JSON.parse_string(encoded)
	var restored := IDMRouteSimulation.new()
	_check(restored.restore(decoded), "active routed job restores from JSON save data")
	_check(restored.current_uv.distance_to(sim.current_uv) < 0.000001 and is_equal_approx(restored.travelled_distance_km(), sim.travelled_distance_km()), "restore preserves position and distance")
	var corrupt_save: Dictionary = decoded.duplicate(true)
	corrupt_save["current_uv"] = [0.95, 0.95]
	_check(not IDMRouteSimulation.new().restore(corrupt_save), "save with a position inconsistent with its road progress is rejected")
	_check(restored.estimated_remaining_seconds(0.0) == -1.0, "paused ETA is explicitly unbounded")
	_check(restored.advance(300.0, 1.0) == ["delivered"], "resumed route completes without repeating pickup event")

func _test_already_at_pickup() -> void:
	var sim := IDMRouteSimulation.new()
	var zero_leg := {"ok": true, "points": [Vector2(0.2, 0.2), Vector2(0.2, 0.2)], "distance_km": 0.0, "segment_lengths_km": [], "segment_times_seconds": [], "estimated_time_seconds": 0.0}
	var delivery := _route([Vector2(0.2, 0.2), Vector2(0.3, 0.2)], [1.0], [100.0], 1.0)
	_check(sim.initialize(zero_leg, delivery), "already-reached pickup is represented as a zero-distance road route")
	_check(sim.advance(1.0, 1.0) == ["reached_pickup"] and sim.phase == IDMRouteSimulation.PHASE_DROPOFF, "zero-distance pickup advances without fabricating movement")
	_check(sim.total_distance_km() == 1.0, "zero-distance pickup does not inflate route mileage")

func _test_reject_bad_routes() -> void:
	var sim := IDMRouteSimulation.new()
	var good := _route([Vector2(0.1, 0.1), Vector2(0.2, 0.1)], [2.0], [200.0], 2.0)
	var missing := {"ok": false, "error": "No connected road route"}
	_check(not sim.initialize(missing, good) and sim.phase == IDMRouteSimulation.PHASE_FAILED, "unreachable route fails without teleporting")
	_check(sim.advance(9999.0, 10.0).is_empty(), "failed route cannot advance or deliver")
	var invalid_segments := {"ok": true, "points": [Vector2(0.1, 0.1), Vector2(0.2, 0.1)], "distance_km": 2.0, "segment_lengths_km": [], "segment_times_seconds": [], "estimated_time_seconds": 10.0}
	_check(not sim.initialize(good, invalid_segments) and sim.phase == IDMRouteSimulation.PHASE_FAILED, "missing road-segment distances and times are rejected")
	var disconnected := _route([Vector2(0.21, 0.1), Vector2(0.3, 0.1)], [3.0], [300.0], 3.0)
	_check(not sim.initialize(good, disconnected), "disconnected pickup and delivery route endpoints are rejected")
