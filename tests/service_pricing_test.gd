extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	_test_service_quotes()
	_test_bounds_and_invalid_inputs()
	print("SERVICE PRICING RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		printerr("FAIL: " + label)

func _test_service_quotes() -> void:
	var ids := IDMServicePricing.service_ids()
	_check(ids.size() == 4, "four separately priced Malaysian service categories are configured")
	var labels: Array[String] = []
	var markers: Array[String] = []
	var prices: Array[float] = []
	for service_id in ids:
		var quote := IDMServicePricing.quote(service_id, 8.0, 900.0)
		_check(quote.get("ok", false), "%s receives a valid route-based price" % service_id)
		_check(str(quote.get("assumption", "")) == "simulated estimate", "%s clearly identifies simulated pricing" % service_id)
		_check(is_equal_approx(float(quote.get("total_rm", 0.0)), snappedf(float(quote.get("total_rm", 0.0)), 0.01)), "%s rounds to cents" % service_id)
		labels.append(IDMServicePricing.label(service_id))
		markers.append(IDMServicePricing.marker(service_id))
		prices.append(float(quote.get("total_rm", 0.0)))
	_check(labels.size() == 4 and labels[0] != labels[1] and labels[1] != labels[2] and labels[2] != labels[3], "each service has a distinct customer-facing name")
	_check(markers.size() == 4 and markers[0] != markers[1] and markers[1] != markers[2] and markers[2] != markers[3], "each service has a distinct map marker")
	_check(prices[0] != prices[1] and prices[1] != prices[2] and prices[2] != prices[3], "service categories produce different automatic fares")
	var short_route := IDMServicePricing.quote("parcel_logistics", 1.0, 300.0)
	var long_route := IDMServicePricing.quote("parcel_logistics", 10.0, 1200.0)
	_check(float(long_route["total_rm"]) > float(short_route["total_rm"]), "distance and travel time increase the fare")

func _test_bounds_and_invalid_inputs() -> void:
	var minimum := IDMServicePricing.quote("food_delivery", 0.0, 0.0)
	var maximum := IDMServicePricing.quote("express_logistics", 500.0, 500000.0)
	_check(is_equal_approx(float(minimum.get("total_rm", 0.0)), 5.0), "minimum fare floor applies")
	_check(is_equal_approx(float(maximum.get("total_rm", 0.0)), 120.0), "maximum fare cap prevents unbounded prices")
	_check(not IDMServicePricing.quote("unknown", 1.0, 60.0).get("ok", false), "unknown services are rejected")
	_check(not IDMServicePricing.quote("food_delivery", -1.0, 60.0).get("ok", false), "negative route distances are rejected")
