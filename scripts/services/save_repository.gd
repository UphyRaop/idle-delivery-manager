extends RefCounted
class_name IDMSaveRepository

## Versioned save adapter. Migration is pure and never mutates the supplied
## v1 object or the existing delivery_ops_save.json file.
const CURRENT_SCHEMA := 2
const SLOT_COUNT := 3
const DEFAULT_DIRECTORY := "user://idm_saves"

static func migrate_legacy_v1(payload: Dictionary) -> Dictionary:
	if int(payload.get("version", 0)) != 1:
		return {}
	var cash_sen := _rm_to_sen(payload.get("cash", 500.0))
	var migrated_speed := IDMSimulationClock.normalize_saved_speed(int(payload.get("speed", 1)))
	var partners: Array[Dictionary] = []
	for value in payload.get("riders", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var rider: Dictionary = value
		var old_id := str(rider.get("id", partners.size() + 1))
		partners.append({
			"id": "legacy_partner_%s" % old_id,
			"legacy_id": old_id,
			"relationship": "independent_contractor",
			"status": "delivering" if str(rider.get("status", "ready")) == "busy" else "available",
			"job_id": "legacy_job_%s" % str(rider.get("order_id", -1)) if str(rider.get("status", "ready")) == "busy" else "",
			"vehicle": {
				"type": "motorcycle",
				"capacity": 1,
				"assumption_from_legacy_save": true,
			},
			"legacy_position": _legacy_point(rider.get("position", null)),
			"remaining_simulation_seconds": maxf(0.0, float(rider.get("remaining", 0.0))),
		})
	var jobs: Array[Dictionary] = []
	for value in payload.get("orders", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var order: Dictionary = value
		var old_status := str(order.get("status", "Waiting"))
		var migrated_status := "offered"
		if old_status == "On route":
			migrated_status = "in_transit"
		elif old_status == "Delivered":
			migrated_status = "completed"
		var job_id := "legacy_job_%s" % str(order.get("id", jobs.size() + 1))
		jobs.append({
			"id": job_id,
			"company_id": "company_parcel_legacy",
			"service": "parcel",
			"state": migrated_status,
			"assigned_partner_id": "legacy_partner_%s" % str(order.get("rider", -1)) if int(order.get("rider", -1)) >= 0 else "",
			"legacy_destination": _legacy_point(order.get("destination", null)),
			"legacy_payout_sen": _rm_to_sen(order.get("payout", 0.0)),
		})
	var migrated := {
		"schema_version": CURRENT_SCHEMA,
		"holding_group": {"id": "holding_legacy", "name": "Legacy Delivery Group", "company_ids": ["company_parcel_legacy"]},
		"companies": [{
			"id": "company_parcel_legacy",
			"service": "parcel",
			"name": "Parcel Logistics",
			"cash_sen": cash_sen,
			"legacy_revenue_sen": _rm_to_sen(payload.get("revenue_total", 0.0)),
			"legacy_cost_sen": _rm_to_sen(payload.get("cost_total", 0.0)),
			"legacy_delivered_count": maxi(0, int(payload.get("delivered", 0))),
			"partners": partners,
			"jobs": jobs,
			"legacy_finance_has_no_job_level_ledger": true,
		}],
		"ledger": {"entries": [], "opening_cash_sen": cash_sen},
		"manual_slots": {"slot_1": null, "slot_2": null, "slot_3": null},
		"simulation": {
			"elapsed_seconds": maxf(0.0, float(payload.get("elapsed", 0.0))),
			"speed": migrated_speed,
			"paused": false,
		},
		"settings": {"difficulty": "standard", "theme": "dark", "language": "en"},
		"migration": {
			"source_schema": 1,
			"source_preserved": true,
			"assumptions": ["Legacy riders are represented as independent partners.", "Legacy normalized map positions remain local placeholders, not geographic coordinates.", "Historic totals are preserved without inventing job-level ledger entries.", "Motorcycle vehicle type is a migration default and may be changed by the player."],
		},
	}
	return migrated if validate_v2(migrated) else {}

static func validate_v2(payload: Dictionary) -> bool:
	if int(payload.get("schema_version", 0)) != CURRENT_SCHEMA:
		return false
	if typeof(payload.get("holding_group", null)) != TYPE_DICTIONARY:
		return false
	if typeof(payload.get("companies", null)) != TYPE_ARRAY or payload["companies"].is_empty():
		return false
	if typeof(payload.get("ledger", null)) != TYPE_DICTIONARY or typeof(payload.get("manual_slots", null)) != TYPE_DICTIONARY:
		return false
	for slot in range(1, SLOT_COUNT + 1):
		if not payload["manual_slots"].has("slot_%d" % slot):
			return false
	for company in payload["companies"]:
		if typeof(company) != TYPE_DICTIONARY or not _is_integer_number(company.get("cash_sen", null)):
			return false
		if int(company["cash_sen"]) < 0:
			return false
	return true

static func _is_integer_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and is_equal_approx(float(value), roundf(float(value)))

static func save_slot(slot: int, payload: Dictionary, directory: String = DEFAULT_DIRECTORY) -> bool:
	if slot < 1 or slot > SLOT_COUNT or not validate_v2(payload):
		return false
	if DirAccess.open(directory) == null and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return false
	var path := "%s/slot_%d.json" % [directory, slot]
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	file.close()
	var check := JSON.new()
	var temp := FileAccess.open(temp_path, FileAccess.READ)
	if temp == null:
		return false
	var temp_text := temp.get_as_text()
	var parse_error := check.parse(temp_text)
	if parse_error != OK or typeof(check.data) != TYPE_DICTIONARY or not validate_v2(check.data):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	if FileAccess.file_exists(path):
		var backup_path := path + ".bak"
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup_path)) != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
			return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	return true

static func load_slot(slot: int, directory: String = DEFAULT_DIRECTORY) -> Dictionary:
	if slot < 1 or slot > SLOT_COUNT:
		return {"ok": false, "error": "invalid_slot"}
	var file := FileAccess.open("%s/slot_%d.json" % [directory, slot], FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "not_found"}
	var parsed := JSON.new()
	if parsed.parse(file.get_as_text()) != OK or typeof(parsed.data) != TYPE_DICTIONARY or not validate_v2(parsed.data):
		return {"ok": false, "error": "invalid_save"}
	return {"ok": true, "data": parsed.data}

static func _rm_to_sen(value: Variant) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0
	return int(round(float(value) * 100.0))

static func _legacy_point(value: Variant) -> Dictionary:
	var point := Vector2(-1.0, -1.0)
	if value is Vector2:
		point = value
	elif typeof(value) == TYPE_ARRAY and value.size() >= 2:
		point = Vector2(float(value[0]), float(value[1]))
	elif typeof(value) == TYPE_DICTIONARY and value.has("x") and value.has("y"):
		point = Vector2(float(value["x"]), float(value["y"]))
	elif typeof(value) == TYPE_STRING:
		var text := str(value).strip_edges().trim_prefix("(").trim_suffix(")")
		var parts := text.split(",")
		if parts.size() == 2:
			parts[0] = parts[0].strip_edges()
			parts[1] = parts[1].strip_edges()
		if parts.size() == 2 and parts[0].is_valid_float() and parts[1].is_valid_float():
			point = Vector2(float(parts[0]), float(parts[1]))
	if point.x < 0.0 or point.x > 1.0 or point.y < 0.0 or point.y > 1.0:
		return {"coordinate_space": "unknown_legacy", "valid": false}
	return {"coordinate_space": "legacy_normalized", "valid": true, "x": point.x, "y": point.y}
