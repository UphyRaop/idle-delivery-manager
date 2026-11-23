extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		printerr("FAIL: " + label)

func _run() -> void:
	var game := Control.new()
	game.set_script(load("res://scripts/game.gd"))
	root.add_child(game)
	await process_frame
	_check(bool(game.get("road_network_available")), "game loads the bundled road graph")
	game.set("save_path", "user://delivery_ops_session_m3_route_integration_test.json")
	game.call("_new_game")
	game.call("_continue_game")
	var riders: Array[Dictionary] = game.get("riders")
	if riders.is_empty():
		_check(false, "new game creates starting delivery partners")
		print("INTEGRATION RESULT: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	# Use a known connected real OSM road segment for deterministic end-to-end
	# verification. The partner begins at the pickup, so the first road leg is
	# a valid zero-distance arrival and the second leg follows mapped geometry.
	var pickup := Vector2(0.0233142857143, 0.6958103348857)
	var destination := Vector2(0.0415285714286, 0.6907106404986)
	var dropoff: Dictionary = game.get("road_router").route_between_uv(pickup, destination)
	if not dropoff.get("ok", false):
		_check(false, "known OSM test route is connected")
		print("INTEGRATION RESULT: %d passed, %d failed" % [passed, failed])
		quit(1)
		return
	riders[0]["position"] = pickup
	riders[0]["status"] = "ready"
	riders[0]["order_id"] = -1
	game.set("riders", riders)
	var order_id := 424242
	var orders: Array[Dictionary] = [{
		"id": order_id, "pickup": pickup, "destination": destination,
		"status": "Waiting", "rider": -1, "payout": 67,
		"route_distance_km": dropoff["distance_km"],
		"route_eta_seconds": dropoff["estimated_time_seconds"],
	}]
	game.set("orders", orders)
	var candidates: Array[Dictionary] = game.call("_eligible_partner_candidates", orders[0])
	_check(not candidates.is_empty() and int(candidates[0].get("rider_id", -1)) == int(riders[0].get("id", -1)), "nearest eligible partner is ranked first by real road distance")
	_check(int(candidates[0].get("pickup_distance_km", 1.0)) == 0 or is_zero_approx(float(candidates[0].get("pickup_distance_km", 1.0))), "partner already at pickup has zero road distance")
	_check(float(riders[0].get("capacity", 0.0)) > 0.0 and str(riders[0].get("vehicle_type", "")) == "motorcycle", "new partners carry persisted vehicle capability and capacity metadata")
	var incompatible_order: Dictionary = orders[0].duplicate(true)
	incompatible_order["service_type"] = "e_hailing"
	_check((game.call("_eligible_partner_candidates", incompatible_order) as Array).is_empty(), "motorcycle-only partners are not recommended for passenger bookings")
	incompatible_order = orders[0].duplicate(true)
	incompatible_order["required_capacity"] = 12.0
	_check((game.call("_eligible_partner_candidates", incompatible_order) as Array).is_empty(), "partners below a booking capacity requirement are excluded")
	var cash_before := float(game.get("cash"))
	var revenue_before := float(game.get("revenue_total"))
	var costs_before := float(game.get("cost_total"))
	game.call("_dispatch", order_id)
	orders = game.get("orders")
	var order: Dictionary = orders.filter(func(item: Dictionary) -> bool: return int(item["id"]) == order_id)[0]
	_check(str(order["status"]).begins_with("On route"), "manual dispatch assigns a reachable partner")
	var rider_id := int(order.get("rider", -1))
	var rider: Dictionary = game.get("riders").filter(func(item: Dictionary) -> bool: return int(item["id"]) == rider_id)[0]
	var saved_route: Dictionary = rider.get("route_state", {})
	_check(saved_route.get("pickup_route", {}).get("points", []).size() >= 2 and saved_route.get("dropoff_route", {}).get("points", []).size() >= 2, "dispatch stores current-to-pickup and pickup-to-dropoff road geometry")
	var second_order := {"id": order_id + 1, "pickup": pickup, "destination": destination, "status": "Waiting", "rider": -1, "payout": 40.0, "service_type": "parcel_logistics"}
	orders.append(second_order)
	game.set("orders", orders)
	game.call("_dispatch", order_id + 1, rider_id)
	_check(str(game.call("_find_order", order_id + 1).get("status", "")) == "Waiting", "busy partner cannot receive a second active order through dispatch")
	_check(int(game.call("_find_rider", rider_id).get("order_id", -1)) == order_id, "rejected duplicate assignment preserves the active route")
	game.call("_set_speed", 100)
	for _frame in 1000:
		if str(game.call("_find_order", order_id).get("status", "")) == "Delivered":
			break
		game.call("_process", 0.016)
	orders = game.get("orders")
	order = orders.filter(func(item: Dictionary) -> bool: return int(item["id"]) == order_id)[0]
	rider = game.get("riders").filter(func(item: Dictionary) -> bool: return int(item["id"]) == rider_id)[0]
	_check(order.get("status", "") == "Delivered", "integrated simulation reaches pickup and completes delivery")
	_check(rider.get("status", "") == "ready", "partner returns to available after delivery")
	_check(is_equal_approx(float(game.get("cash")), cash_before + float(order["payout"]) - 18.0), "completed route updates cash by payout less operating cost")
	_check(is_equal_approx(float(game.get("revenue_total")), revenue_before + float(order["payout"])), "completed route posts revenue once")
	_check(is_equal_approx(float(game.get("cost_total")), costs_before + 18.0) and int(game.get("delivered")) == 1, "completed route posts cost and delivery totals once")
	game.call("_dispatch", order_id + 1, rider_id)
	_check(str(game.call("_find_order", order_id + 1).get("status", "")).begins_with("On route"), "partner can accept a new booking after simulation confirms delivery")
	var third_order := {"id": order_id + 2, "pickup": pickup, "destination": destination, "status": "Waiting", "rider": -1, "payout": 45.0, "service_type": "parcel_logistics"}
	orders = game.get("orders")
	orders.append(third_order)
	game.set("orders", orders)
	var map_candidates: Array[Dictionary] = game.call("_eligible_partner_candidates", third_order)
	var manually_selected_id := int(map_candidates[-1].get("rider_id", -1)) if map_candidates.size() > 1 else -1
	game.set("selected_dispatch_partner_id", manually_selected_id)
	game.call("_dispatch", order_id + 2)
	_check(manually_selected_id >= 0 and int(game.call("_find_order", order_id + 2).get("rider", -1)) == manually_selected_id, "map-selected eligible partner is honored by the shared dispatch path")
	var test_path := "user://delivery_ops_session_m3_route_integration_test.json"
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	game.queue_free()
	print("GAME ROUTE INTEGRATION: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
