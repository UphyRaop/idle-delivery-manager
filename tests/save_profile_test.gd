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
	var legacy_path := "user://delivery_ops_session_legacy_test.json"
	game.set("save_path", legacy_path)
	game.set("legacy_map_mode", true)
	game.set("cash", 321.45)
	game.set("revenue_total", 87.25)
	game.set("cost_total", 11.0)
	game.set("delivered", 3)
	game.set("riders", [{"id": 1, "status": "ready", "order_id": -1, "remaining": 0.0, "position": Vector2(0.2, 0.7)}])
	game.set("orders", [{"id": 4, "destination": Vector2(0.75, 0.3), "status": "Waiting", "rider": -1, "payout": 40.0}])
	game.call("_save_game")
	game.call("_register_current_save_profile")
	var original_file := FileAccess.open(legacy_path, FileAccess.READ)
	var original := JSON.parse_string(original_file.get_as_text()) as Dictionary
	_check(str(original.get("map_space", "")) == "legacy_normalized", "legacy save retains its fictional coordinate space")
	_check(is_equal_approx(float(original.get("cash", 0.0)), 321.45), "legacy progress is saved before profile switching")
	game.call("_start_new_geographic_game")
	var geographic_path := str(game.get("save_path"))
	var geographic_riders: Array[Dictionary] = game.get("riders")
	_check(geographic_path != legacy_path, "new geographic game uses a separate save path")
	_check(not bool(game.get("legacy_map_mode")), "new game uses the real geographic map mode")
	_check(geographic_riders.size() >= 1 and geographic_riders[0].has("latitude") and geographic_riders[0].has("longitude"), "new partners initialize from real road coordinates")
	var preserved_file := FileAccess.open(legacy_path, FileAccess.READ)
	var preserved := JSON.parse_string(preserved_file.get_as_text()) as Dictionary
	_check(is_equal_approx(float(preserved.get("cash", 0.0)), 321.45) and str(preserved.get("map_space", "")) == "legacy_normalized", "starting a new game leaves the legacy save unchanged")
	game.call("_load_save_profile", legacy_path)
	_check(bool(game.get("legacy_map_mode")), "loading legacy profile restores the fictional map")
	_check(is_equal_approx(float(game.get("cash")), 321.45), "loading legacy profile restores its cash and progress")
	game.call("_load_save_profile", geographic_path)
	_check(not bool(game.get("legacy_map_mode")) and is_equal_approx(float(game.get("cash")), 500.0), "switching back restores the geographic game state")
	var profiles: Array[Dictionary] = game.get("save_profiles")
	_check(profiles.any(func(profile: Dictionary) -> bool: return profile.get("path", "") == legacy_path) and profiles.any(func(profile: Dictionary) -> bool: return profile.get("path", "") == geographic_path), "load catalogue contains both separate profiles")
	print("SAVE PROFILE RESULT: %d passed, %d failed" % [passed, failed])
	for path in [legacy_path, geographic_path, "user://idm_save_catalog.json", "user://idm_active_save.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.queue_free()
	quit(1 if failed else 0)
