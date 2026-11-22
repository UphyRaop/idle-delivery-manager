extends RefCounted
class_name IDMServicePricing

## Transparent, configurable gameplay estimates. These are simulation values,
## not official rates or representations of any real Malaysian platform.
const RATES := {
	"food_delivery": {"label": "Food delivery", "marker": "F", "base_rm": 4.50, "per_km_rm": 1.35, "per_minute_rm": 0.12, "minimum_rm": 5.00, "maximum_rm": 65.00},
	"parcel_logistics": {"label": "Parcel logistics", "marker": "P", "base_rm": 5.00, "per_km_rm": 1.05, "per_minute_rm": 0.10, "minimum_rm": 5.00, "maximum_rm": 85.00},
	"e_hailing": {"label": "Passenger e-hailing", "marker": "R", "base_rm": 3.50, "per_km_rm": 1.55, "per_minute_rm": 0.16, "minimum_rm": 5.00, "maximum_rm": 100.00},
	"express_logistics": {"label": "Same-day express", "marker": "X", "base_rm": 8.00, "per_km_rm": 1.45, "per_minute_rm": 0.13, "minimum_rm": 8.00, "maximum_rm": 120.00},
}

static func service_ids() -> Array[String]:
	var result: Array[String] = []
	for service_id in RATES:
		result.append(service_id)
	return result

static func label(service_id: String) -> String:
	return str(RATES.get(service_id, RATES["parcel_logistics"]).get("label", "Parcel logistics"))

static func marker(service_id: String) -> String:
	return str(RATES.get(service_id, RATES["parcel_logistics"]).get("marker", "P"))

static func short_label(service_id: String) -> String:
	return str({
		"food_delivery": "FOOD",
		"parcel_logistics": "PARCEL",
		"e_hailing": "E-HAIL",
		"express_logistics": "EXPRESS",
	}.get(service_id, "PARCEL"))

static func quote(service_id: String, distance_km: float, travel_seconds: float) -> Dictionary:
	if not RATES.has(service_id) or not is_finite(distance_km) or not is_finite(travel_seconds) or distance_km < 0.0 or travel_seconds < 0.0:
		return {"ok": false, "error": "Invalid service or route estimate"}
	var rates: Dictionary = RATES[service_id]
	var base := float(rates["base_rm"])
	var distance := distance_km * float(rates["per_km_rm"])
	var time := travel_seconds / 60.0 * float(rates["per_minute_rm"])
	var total := clampf(base + distance + time, float(rates["minimum_rm"]), float(rates["maximum_rm"]))
	return {
		"ok": true,
		"service_id": service_id,
		"currency": "RM",
		"base_rm": base,
		"distance_rm": distance,
		"time_rm": time,
		"total_rm": snappedf(total, 0.01),
		"assumption": "simulated estimate",
	}
