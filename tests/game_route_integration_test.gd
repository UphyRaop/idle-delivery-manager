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
	game.set("speed", 10)
	game.call("_process", 10000.0)
	orders = game.get("orders")
	order = orders.filter(func(item: Dictionary) -> bool: return int(item["id"]) == order_id)[0]
	rider = game.get("riders").filter(func(item: Dictionary) -> bool: return int(item["id"]) == rider_id)[0]
	_check(order.get("status", "") == "Delivered", "integrated simulation reaches pickup and completes delivery")
	_check(rider.get("status", "") == "ready", "partner returns to available after delivery")
	_check(is_equal_approx(float(game.get("cash")), cash_before + float(order["payout"]) - 18.0), "completed route updates cash by payout less operating cost")
	_check(is_equal_approx(float(game.get("revenue_total")), revenue_before + float(order["payout"])), "completed route posts revenue once")
	_check(is_equal_approx(float(game.get("cost_total")), costs_before + 18.0) and int(game.get("delivered")) == 1, "completed route posts cost and delivery totals once")
	var test_path := "user://delivery_ops_session_m3_route_integration_test.json"
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	game.queue_free()
	print("GAME ROUTE INTEGRATION: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
