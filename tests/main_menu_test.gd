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
	var initial_content := menu.find_child("MainMenuContent", true, false) as VBoxContainer
	_check(initial_content.get_parent() is CenterContainer, "full-screen menu content is not wrapped in an oversized outer panel")
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
	var old_saved_at := int(Time.get_unix_time_from_system()) + 100
	var latest_saved_at := old_saved_at + 100
	game.set("save_path", old_path)
	game.set("cash", 111.0)
	game.call("_save_game")
	var old_file := FileAccess.open(old_path, FileAccess.READ)
	var old_data := JSON.parse_string(old_file.get_as_text()) as Dictionary
	old_file.close()
	old_data["saved_at"] = old_saved_at
	old_file = FileAccess.open(old_path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(old_data))
	old_file.close()
	game.set("save_path", latest_path)
	game.set("player_company_name", "Kampung Pandan Courier Sdn. Bhd.")
	game.set("player_starting_location", "Kampung Pandan")
	game.set("elapsed", 2.0 * 86400.0 + 9.0 * 3600.0)
	game.set("cash", 222.0)
	game.call("_save_game")
	var latest_file := FileAccess.open(latest_path, FileAccess.READ)
	var latest_data := JSON.parse_string(latest_file.get_as_text()) as Dictionary
	latest_file.close()
	latest_data["saved_at"] = latest_saved_at
	latest_file = FileAccess.open(latest_path, FileAccess.WRITE)
	latest_file.store_string(JSON.stringify(latest_data))
	latest_file.close()
	var invalid_file := FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid_file.store_string("{broken")
	invalid_file.close()
	var test_profiles: Array[Dictionary] = [
		{"path": old_path, "created_at": old_saved_at, "map_space": "legacy_normalized"},
		{"path": latest_path, "created_at": latest_saved_at, "map_space": "kl_selangor_web_mercator_uv"},
		{"path": invalid_path, "created_at": latest_saved_at + 100, "map_space": "legacy_normalized"},
	]
	game.set("save_profiles", test_profiles)
	game.call("_render_main_menu")
	await process_frame
	menu = game.get("menu_overlay")
	var dashboard := menu.find_child("LastSessionDashboard", true, false) as PanelContainer
	_check(is_instance_valid(dashboard), "valid saved session adds the compact last-session dashboard")
	_check(str((dashboard.find_child("LastSessionStatus", true, false) as Label).text) == "LAST SESSION · VALID SAVE", "dashboard identifies the session as a valid save")
	_check(str((dashboard.find_child("LastSessionCompany", true, false) as Label).text) == "Kampung Pandan Courier Sdn. Bhd.", "dashboard uses the saved company name")
	_check(str((dashboard.find_child("LastSessionCash", true, false) as Label).text) == "RM222.00" and str((dashboard.find_child("LastSessionDate", true, false) as Label).text).begins_with("Game Day 03"), "dashboard uses saved cash and in-game date")
	var dashboard_continue: Button = _find_button(menu, "Continue")
	_check(is_instance_valid(dashboard_continue) and not dashboard_continue.disabled, "Continue is enabled for the valid dashboard save")
	_check(str(game.call("_latest_valid_save_path")) == latest_path, "Continue selects the most recent valid autosave, excluding invalid data")
	_check(game.call("_save_payload_for_path", invalid_path).is_empty(), "invalid saves are not considered valid continuation targets")
	game.set("save_path", old_path)
	game.call("_continue_game")
	_check(not bool(game.get("main_menu_active")), "Continue opens the selected save without creating another game instance")
	_check(str(game.get("save_path")) == latest_path and is_equal_approx(float(game.get("cash")), 222.0), "Continue restores the newest save profile")
	var map_legend: Control = game.get("map_legend_panel")
	_check(is_instance_valid(map_legend) and not map_legend.visible, "map icon legend is available but compactly hidden by default")
	game.call("_toggle_map_legend")
	_check(map_legend.visible, "map icon legend opens during gameplay")
	game.call("_toggle_map_legend")
	_check(not map_legend.visible, "map icon legend closes on demand")
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
	_check(not map_legend.visible, "returning to the main menu hides the map legend")
	var menu_viewports: Array[Vector2i] = [
		Vector2i(360, 800), Vector2i(375, 812), Vector2i(390, 844), Vector2i(393, 852),
		Vector2i(414, 896), Vector2i(430, 932), Vector2i(844, 390), Vector2i(768, 1024),
		Vector2i(1024, 768), Vector2i(1366, 768),
	]
	for requested in menu_viewports:
		root.size = requested
		await process_frame
		game.call("_layout_ui")
		game.call("_render_main_menu")
		await process_frame
		menu = game.get("menu_overlay")
		var content := menu.find_child("MainMenuContent", true, false) as VBoxContainer
		var content_rect := content.get_global_rect()
		var footer := menu.find_child("MainMenuCredits", true, false) as VBoxContainer
		var footer_rect := footer.get_global_rect()
		var settings_rect := _find_button(menu, "Settings").get_global_rect()
		var copyright_label := menu.find_child("MainMenuCopyright", true, false) as Label
		var viewport: Vector2 = game.get("viewport_size")
		var actions_inside := true
		for action_name in ["New Game", "Continue", "Load Game", "Settings"]:
			var action_button: Button = _find_button(menu, action_name)
			if action_button == null:
				actions_inside = false
				continue
			var action_rect: Rect2 = action_button.get_global_rect()
			if action_rect.position.x < 0.0 or action_rect.end.x > viewport.x or action_rect.position.y < 0.0 or action_rect.end.y > viewport.y:
				actions_inside = false
		var viewport_labels := _all_text(menu)
		_check(content_rect.position.x >= 0.0 and content_rect.end.x <= viewport.x, "main menu content fits horizontally at %dx%d" % [requested.x, requested.y])
		_check(actions_inside, "all four actions stay in the viewport at %dx%d" % [requested.x, requested.y])
		_check(viewport_labels.has("Created by UphyRaop") and viewport_labels.has("© 2026 UR Trade Network. All rights reserved."), "creator and copyright remain in the menu at %dx%d" % [requested.x, requested.y])
		_check(footer_rect.position.y >= 0.0 and footer_rect.end.y <= viewport.y and footer.visible, "menu credits remain visibly inside %dx%d" % [requested.x, requested.y])
		_check(not footer_rect.intersects(settings_rect), "footer does not overlap menu actions at %dx%d" % [requested.x, requested.y])
		_check(copyright_label.get_global_rect().size.y >= 12.0 and copyright_label.visible, "copyright has visible line height at %dx%d" % [requested.x, requested.y])
		if requested.x < 600:
			_check(is_instance_valid(menu.find_child("IDMMenuTitle", true, false)) and is_instance_valid(menu.find_child("IDMMenuTagline", true, false)), "mobile menu shows explicit brand title and subtitle at %dx%d" % [requested.x, requested.y])
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

func _find_button(node: Node, target: String) -> Button:
	if node is Button and (node as Button).text == target:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, target)
		if found != null:
			return found
	return null
