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
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(game)
	await process_frame
	game.call("_new_game", false)
	game.set("paused", true)
	(game.get("simulation_clock") as Object).call("set_paused", true)
	game.set("main_menu_active", false)
	game.set("game_session_started", true)
	game.call("_spawn_order")
	game.call("_refresh")
	await process_frame

	var nav := game.get("bottom_nav") as Control
	var nav_buttons: Dictionary = game.get("nav_buttons")
	var nav_labels: Dictionary = game.get("nav_labels")
	var map_view := game.get("map_view") as Control
	var sheet := game.get("sheet") as Control
	var sheet_toggle := game.get("sheet_toggle_button") as Button
	var sheet_body := game.get("sheet_body") as ScrollContainer
	var hud := game.get("hud") as Control
	var speed := game.get("sim_controls") as Control
	var controls := game.get("map_controls") as Control
	var bookings := game.get("bookings_button") as Control
	var camera: IDMMapCamera = game.get("map_camera")
	camera.pan = Vector2(17, -9)
	camera.zoom = 1.4
	var cash_before := float(game.get("cash"))
	var orders_before: Array = (game.get("orders") as Array).duplicate(true)
	var original_speed := int(game.get("speed"))

	_check(nav.visible and nav_buttons.size() == 4, "four persistent navigation buttons remain visible during play")
	_check((nav_buttons["Map"] as Button).get_meta("ui_variant") == "selected", "active destination receives the selected cyan icon state")
	for name in ["Map", "Operations", "Finance", "Settings"]:
		var button := nav_buttons[name] as Button
		var label := nav_labels[name] as Label
		var content := button.get_child(0) as HBoxContainer
		var icon := content.get_child(0) as Control
		_check(button.accessibility_name == name and button.tooltip_text == name, "%s icon keeps an accessible name" % name)
		_check(not label.visible and content.get_child_count() == 2, "%s tab is icon-only" % name)
		_check(button.custom_minimum_size.y >= 50.0 and icon.custom_minimum_size == Vector2(24, 24), "%s tab has a touch-sized button and readable icon" % name)

	var viewports: Array[Vector2i] = [
		Vector2i(360, 800), Vector2i(375, 812), Vector2i(390, 844),
		Vector2i(393, 852), Vector2i(414, 896), Vector2i(430, 932),
		Vector2i(844, 390), Vector2i(768, 1024), Vector2i(1024, 768), Vector2i(1366, 768),
	]
	for requested in viewports:
		root.size = requested
		await process_frame
		game.call("_layout_ui")
		await process_frame
		var camera_pan := camera.pan
		var camera_zoom := camera.zoom
		for name in ["Operations", "Finance", "Settings"]:
			game.call("_set_tab", name)
			await process_frame
			_check((nav_buttons[name] as Button).get_meta("ui_variant") == "selected", "%s becomes the active navigation destination" % name)
			var viewport: Vector2 = game.get("viewport_size")
			var safe: Vector4 = game.get("safe_insets")
			var sheet_rect := sheet.get_global_rect()
			var nav_rect := nav.get_global_rect()
			_check(not map_view.visible and not hud.visible and not speed.visible and not controls.visible and not bookings.visible, "%s hides the Map page and every map-specific overlay at %dx%d" % [name, requested.x, requested.y])
			_check(sheet.visible and sheet_rect.position.y >= safe.y and sheet_rect.position.x >= safe.x and sheet_rect.end.x <= viewport.x - safe.z and sheet_rect.end.y <= nav_rect.position.y + 1.0, "%s content fills its safe page area above navigation at %dx%d" % [name, requested.x, requested.y])
			_check(nav.visible and sheet_body.visible and sheet_body.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "%s page keeps navigation and a non-horizontal content scroller at %dx%d" % [name, requested.x, requested.y])
			_check(not sheet_toggle.visible, "%s full-page content hides the map-only sheet toggle at %dx%d" % [name, requested.x, requested.y])
			_check(int(game.get("speed")) == original_speed and is_equal_approx(float(game.get("cash")), cash_before) and (game.get("orders") as Array) == orders_before, "%s tab switch preserves simulation and business state at %dx%d" % [name, requested.x, requested.y])
			game.call("_set_tab", "Map")
			await process_frame
			_check(map_view.visible and hud.visible and speed.visible and controls.visible and bookings.visible, "Map restores its controls after %s at %dx%d" % [name, requested.x, requested.y])
			_check(camera.pan == camera_pan and is_equal_approx(camera.zoom, camera_zoom), "Map camera remains unchanged after %s at %dx%d" % [name, requested.x, requested.y])

	# The full-screen waiting page is also a blocking page, not a way for the
	# hidden map or tab bar to continue receiving input.
	bookings.mouse_filter = Control.MOUSE_FILTER_STOP
	game.call("_open_waiting_bookings_page")
	game.call("_layout_ui")
	_check(not map_view.visible and not nav.visible and bool(game.get("waiting_bookings_page_open")), "Waiting Bookings remains a full-page modal over the hidden Map")
	game.call("_close_waiting_bookings_page")
	game.queue_free()
	print("FULL PAGE NAVIGATION RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
