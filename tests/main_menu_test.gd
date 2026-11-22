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
	_check(bool(game.get("main_menu_active")), "startup opens the main menu")
	_check(not bool(game.get("game_session_started")), "startup does not start a simulation session")
	var menu: Control = game.get("menu_overlay")
	_check(is_instance_valid(menu), "main menu overlay is available")
	var labels := _all_text(menu)
	_check(labels.has("IDLE DELIVERY MANAGER"), "main menu uses the approved game title")
	_check(labels.has("UR Trade Network"), "main menu shows the approved company name")
	_check(labels.has("Created by UphyRaop"), "main menu shows the approved creator credit")
	for required in ["New Game", "Continue", "Load Game", "Settings"]:
		_check(labels.has(required), "main menu exposes %s" % required)
	var elapsed_before := float(game.get("elapsed"))
	for _frame in 4:
		await process_frame
	_check(is_equal_approx(float(game.get("elapsed")), elapsed_before), "simulation clock remains stopped at the main menu")
	game.call("_open_menu_settings")
	_check(bool(game.get("main_menu_active")) and bool(game.get("menu_settings_open")), "main-menu settings do not start gameplay")
	game.call("_back_to_menu_home")
	_check(bool(game.get("main_menu_active")) and not bool(game.get("menu_settings_open")), "main-menu settings return to the main menu")
	var old_path := "user://delivery_ops_session_menu_test_old.json"
	var latest_path := "user://delivery_ops_session_menu_test_latest.json"
	var invalid_path := "user://delivery_ops_session_menu_test_invalid.json"
	game.set("save_path", old_path)
	game.set("cash", 111.0)
	game.call("_save_game")
	var old_file := FileAccess.open(old_path, FileAccess.READ)
	var old_data := JSON.parse_string(old_file.get_as_text()) as Dictionary
	old_file.close()
	old_data["saved_at"] = 100
	old_file = FileAccess.open(old_path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(old_data))
	old_file.close()
	game.set("save_path", latest_path)
	game.set("cash", 222.0)
	game.call("_save_game")
	var latest_file := FileAccess.open(latest_path, FileAccess.READ)
	var latest_data := JSON.parse_string(latest_file.get_as_text()) as Dictionary
	latest_file.close()
	latest_data["saved_at"] = 200
	latest_file = FileAccess.open(latest_path, FileAccess.WRITE)
	latest_file.store_string(JSON.stringify(latest_data))
	latest_file.close()
	var invalid_file := FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid_file.store_string("{broken")
	invalid_file.close()
	var test_profiles: Array[Dictionary] = [
		{"path": old_path, "created_at": 100, "map_space": "legacy_normalized"},
		{"path": latest_path, "created_at": 200, "map_space": "kl_selangor_web_mercator_uv"},
		{"path": invalid_path, "created_at": 300, "map_space": "legacy_normalized"},
	]
	game.set("save_profiles", test_profiles)
	_check(str(game.call("_latest_valid_save_path")) == latest_path, "Continue selects the most recent valid autosave, excluding invalid data")
	_check(game.call("_save_payload_for_path", invalid_path).is_empty(), "invalid saves are not considered valid continuation targets")
	game.set("save_path", old_path)
	game.call("_continue_game")
	_check(not bool(game.get("main_menu_active")), "Continue opens the selected save without creating another game instance")
	_check(str(game.get("save_path")) == latest_path and is_equal_approx(float(game.get("cash")), 222.0), "Continue restores the newest save profile")
	game.call("_return_to_main_menu")
	game.call("_confirm_return_to_menu")
	var returned_data: Dictionary = game.call("_save_payload_for_path", latest_path)
	_check(bool(game.get("main_menu_active")) and is_equal_approx(float(returned_data.get("cash", 0.0)), 222.0), "returning to the menu saves progress and stops the session")
	print("MAIN MENU RESULT: %d passed, %d failed" % [passed, failed])
	for path in [old_path, latest_path, invalid_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.queue_free()
	quit(1 if failed else 0)

func _all_text(node: Node) -> Array[String]:
	var values: Array[String] = []
	if node is Label:
		values.append((node as Label).text)
	elif node is Button:
		values.append((node as Button).text)
	for child in node.get_children():
		values.append_array(_all_text(child))
	return values
