extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	_test_save_migration()
	_test_save_slots()
	_test_ledger()
	_test_clock()
	_test_geographic_data()
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		printerr("FAIL: " + label)

func _test_save_migration() -> void:
	var old := {
		"version": 1, "cash": 123.45, "revenue_total": 987.65, "cost_total": 45.67,
		"delivered": 9, "elapsed": 23.0, "speed": 4,
		"riders": [{"id": 1, "status": "busy", "order_id": 8, "position": "(0.2, 0.5)", "remaining": 3.0}],
		"orders": [{"id": 8, "status": "On route", "rider": 1, "destination": [0.75, 0.25], "payout": 20.0}],
	}
	var migrated := IDMSaveRepository.migrate_legacy_v1(old)
	_check(IDMSaveRepository.validate_v2(migrated), "legacy schema migrates to valid v2")
	_check(migrated["companies"][0]["cash_sen"] == 12345, "legacy cash preserved in integer sen")
	_check(migrated["companies"][0]["legacy_revenue_sen"] == 98765, "legacy revenue preserved without fabricated ledger")
	_check(migrated["companies"][0]["partners"][0]["relationship"] == "independent_contractor", "legacy riders represented as partners")
	_check(migrated["companies"][0]["partners"][0]["legacy_position"]["coordinate_space"] == "legacy_normalized", "normalized map positions not misrepresented as geographic")
	_check(migrated["simulation"]["speed"] == 5, "legacy 4x maps to supported 5x speed")
	_check(old["cash"] == 123.45 and old["version"] == 1, "migration leaves source payload unchanged")
	_check(IDMSaveRepository.migrate_legacy_v1({"version": 99}).is_empty(), "unknown schema rejected")

func _test_ledger() -> void:
	var ledger := IDMLedgerService.new()
	var lines: Array[Dictionary] = [
		{"account": "cash", "side": "debit", "amount_sen": 1500},
		{"account": "platform_revenue", "side": "credit", "amount_sen": 1500},
	]
	_check(ledger.post_transaction("job:1:settlement", "parcel_co", "job:1", lines), "balanced transaction posts")
	_check(not ledger.post_transaction("job:1:settlement", "parcel_co", "job:1", lines), "duplicate transaction is idempotently rejected")
	_check(ledger.account_balance_sen("cash") == 1500, "ledger balance uses integer sen")
	_check(ledger.journal_is_balanced(), "journal remains balanced")
	var invalid: Array[Dictionary] = [
		{"account": "cash", "side": "debit", "amount_sen": 1500},
		{"account": "platform_revenue", "side": "credit", "amount_sen": 1499},
	]
	_check(not ledger.post_transaction("job:2:settlement", "parcel_co", "job:2", invalid), "unbalanced transaction rejected")

func _test_save_slots() -> void:
	var directory := "user://idm_test_slots"
	var payload := IDMSaveRepository.migrate_legacy_v1({"version": 1, "riders": [{"id": 1}], "orders": []})
	_check(IDMSaveRepository.save_slot(1, payload, directory), "manual slot saves through verified temporary file")
	var loaded := IDMSaveRepository.load_slot(1, directory)
	_check(loaded.get("ok", false), "manual slot loads and validates")
	payload["companies"][0]["cash_sen"] = 123
	_check(IDMSaveRepository.save_slot(1, payload, directory), "manual slot overwrite succeeds")
	_check(FileAccess.file_exists(directory + "/slot_1.json.bak"), "slot overwrite preserves a prior backup")
	_check(IDMSaveRepository.load_slot(0, directory).get("error", "") == "invalid_slot", "invalid manual slot is rejected")
	for suffix in ["slot_1.json", "slot_1.json.bak", "slot_1.json.tmp"]:
		var path: String = directory + "/" + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))

func _test_clock() -> void:
	var clock := IDMSimulationClock.new()
	_check(clock.advance(0.25) == 2, "clock returns deterministic fixed ticks")
	_check(is_equal_approx(clock.simulation_seconds, 0.2), "clock advances only completed fixed steps")
	_check(clock.set_speed(10), "10x speed supported")
	_check(clock.advance(0.1) == 10, "simulation speed scales ticks")
	clock.set_paused(true)
	_check(clock.advance(5.0) == 0, "pause prevents simulation advancement")
	_check(not clock.set_speed(4), "unsupported simulation speed rejected")

func _test_geographic_data() -> void:
	var geography := IDMGeographicService.new()
	_check(geography.load_data(), "bundled OSM spawn and locality data load")
	_check(geography.spawn_points.size() >= 1000, "KL/Selangor includes a useful road-based spawn set")
	_check(geography.places.any(func(place: Dictionary) -> bool: return place.get("name", "") == "Kuala Lumpur"), "real Kuala Lumpur place label is present")
	var uv := geography.geo_to_uv(3.139, 101.686)
	var ll := geography.uv_to_geo(uv)
	_check(absf(ll.x - 101.686) < 0.00001 and absf(ll.y - 3.139) < 0.00001, "WGS84 and Web Mercator UV transforms round trip")
	var mobile_size := Vector2(390, 844)
	var points_visible := true
	for sample in 100:
		var point := geography.random_road_location(mobile_size)
		points_visible = points_visible and point.x > 0.2 and point.x < 0.8 and point.y >= 0.2 and point.y <= 0.68
	_check(points_visible, "100 sampled road booking points are visible at mobile portrait size")
