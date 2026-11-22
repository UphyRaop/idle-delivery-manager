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
	var speed_buttons: Dictionary = game.get("speed_buttons")
	_check(speed_buttons.keys().size() == 5 and speed_buttons.has(1) and speed_buttons.has(5) and speed_buttons.has(10) and speed_buttons.has(50) and speed_buttons.has(100) and not speed_buttons.has(2), "speed selector exposes exactly 1x, 5x, 10x, 50x and 100x")
	var labels := _all_text(menu)
	if Vector2(game.get("viewport_size")).x < 600.0:
		var brand_icon := menu.find_child("IDMBrandIcon", true, false) as TextureRect
		_check(is_instance_valid(brand_icon) and brand_icon.texture != null and labels.has("IDLE DELIVERY MANAGER") and labels.has("Build Your Logistics Empire"), "phone menu keeps the official truck icon and readable branding")
	else:
		var logo := menu.find_child("IDMFullLogo", true, false) as TextureRect
		_check(is_instance_valid(logo) and logo.texture != null and logo.tooltip_text.contains("IDLE DELIVERY MANAGER"), "wider main menu uses the approved full vector brand logo")
	_check(labels.has("Created by UphyRaop"), "main menu shows the approved creator credit")
	_check(labels.has("© 2026 UR Trade Network. All rights reserved."), "main menu shows the required copyright")
	_check(not labels.has("UR Trade Network"), "main menu does not add a duplicate publisher line above the creator credit")
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
	game.set("sheet_expanded", true)
	game.call("_layout_ui")
	var sheet: Control = game.get("sheet")
	var navigation: Control = game.get("bottom_nav")
	_check(navigation.get_index() > sheet.get_index(), "persistent bottom navigation is layered above expanded sheets")
	_check(navigation.visible, "primary navigation stays visible while a sheet is expanded")
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
