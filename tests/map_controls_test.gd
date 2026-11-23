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
	var controls: GridContainer = game.get("map_controls")
	game.set("game_session_started", true)
	game.set("main_menu_active", false)
	game.set("selected_tab", "Map")
	controls.visible = true
	game.call("_layout_ui")
	controls.queue_sort()
	await process_frame
	var expected := ["ZoomIn", "ZoomOut", "Center", "FitRoute", "FollowRider", "Legend"]
	_check(is_instance_valid(controls) and controls.get_child_count() == 6, "six independent floating map controls are present")
	_check(controls.get_parent() == game, "map controls are not inside a large grouped panel")
	for index in range(mini(controls.get_child_count(), expected.size())):
		var button := controls.get_child(index) as Button
		var icon := button.get_node_or_null("MapControlIcon") as Control
		_check(button.name == expected[index] and button.accessibility_name == str(button.get_meta("accessible_label", "")) and not button.accessibility_name.is_empty(), "%s has an accessible action label" % expected[index])
		_check(button.text.is_empty() and is_instance_valid(icon) and icon.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s uses a non-blocking vector icon" % expected[index])
	var actual_layout: Dictionary = game.call("_map_control_layout_for", game.get("viewport_size"), game.get("safe_insets"), game.get("ui_layout_scale"))
	_check(controls.columns == int(actual_layout["columns"]), "visible button container uses the computed responsive column count")
	var actual_rects: Array[Rect2] = []
	var actual_separate := true
	for button_node in controls.get_children():
		var button := button_node as Button
		actual_rects.append(button.get_global_rect())
	for index in range(actual_rects.size()):
		for other_index in range(index):
			actual_separate = actual_separate and not actual_rects[index].intersects(actual_rects[other_index])
	_check(actual_separate, "visible button hit areas are individually laid out without overlap")

	var viewports: Array[Vector2i] = [
		Vector2i(360, 800), Vector2i(375, 812), Vector2i(390, 844),
		Vector2i(393, 852), Vector2i(414, 896), Vector2i(430, 932),
		Vector2i(844, 390), Vector2i(768, 1024), Vector2i(1024, 768), Vector2i(1366, 768),
	]
	for requested in viewports:
		var landscape := requested.x > requested.y
		var scale := clampf(844.0 / float(requested.y), 1.0, 2.2) if landscape and requested.x < 1024 else 1.0
		var ui_viewport := Vector2(requested) * scale
		var layout: Dictionary = game.call("_map_control_layout_for", ui_viewport, Vector4.ZERO, scale)
		var css_width := float(layout["width"]) / scale
		var css_height := float(layout["height"]) / scale
		var css_left := (ui_viewport.x + float(layout["left"])) / scale
		var css_right := (ui_viewport.x + float(layout["right"])) / scale
		var css_top := float(layout["top"]) / scale
		_check(int(layout["columns"]) == (3 if landscape else 1), "control arrangement adapts at %dx%d" % [requested.x, requested.y])
		_check(is_equal_approx(float(layout["button_size"]) / scale, 48.0), "48px touch target is preserved at %dx%d" % [requested.x, requested.y])
		_check(css_right <= requested.x - 12.0 and css_left >= 0.0, "controls stay at the safe right-side map edge at %dx%d" % [requested.x, requested.y])
		_check(is_equal_approx(css_width, 154.0 if landscape else 48.0), "control footprint fits at %dx%d" % [requested.x, requested.y])
		_check(is_equal_approx(css_top, 116.0 if landscape else 142.0), "controls clear HUD and speed strip at %dx%d" % [requested.x, requested.y])
		var nav_height := 60.0 if landscape else 68.0
		var sheet_height := 210.0 if landscape else 260.0
		var sheet_top := float(requested.y) - nav_height - 8.0 - sheet_height
		var sheet_left := float(requested.x) - 352.0 - 12.0 if landscape else 10.0
		var sheet_width := 352.0 if landscape else float(requested.x) - 20.0
		var controls_rect := Rect2(css_left, css_top, css_width, css_height)
		var sheet_rect := Rect2(sheet_left, sheet_top, sheet_width, sheet_height)
		_check(not controls_rect.intersects(sheet_rect), "controls avoid expanded booking sheet at %dx%d" % [requested.x, requested.y])
		var legend_rect := Rect2(12, maxf(12.0, (float(requested.y) - 246.0) * 0.5), 252, 246)
		_check(not controls_rect.intersects(legend_rect), "controls leave room for marker legend at %dx%d" % [requested.x, requested.y])
		_check(css_top + css_height <= float(requested.y) - nav_height, "controls stay above bottom navigation at %dx%d" % [requested.x, requested.y])

	var zoom := float(game.get("map_camera").zoom)
	(controls.get_child(0) as Button).pressed.emit()
	_check(float(game.get("map_camera").zoom) > zoom, "Zoom In control changes map zoom")
	(controls.get_child(1) as Button).pressed.emit()
	_check(float(game.get("map_camera").zoom) < zoom * 1.3, "Zoom Out control changes map zoom back")
	var camera: IDMMapCamera = game.get("map_camera")
	camera.pan = Vector2(42, 28)
	(controls.get_child(2) as Button).pressed.emit()
	_check(camera.pan.is_zero_approx(), "Center control recenters the map")
	game.set("selected_order", -1)
	(controls.get_child(3) as Button).pressed.emit()
	_check(str(game.get("status_label").text).contains("geographic map"), "Fit control reports when the geographic map bridge is unavailable")
	(controls.get_child(4) as Button).pressed.emit()
	_check(str(game.get("status_label").text).contains("Select an active delivery"), "Follow control gives useful feedback when no active partner is selected")
	(controls.get_child(5) as Button).pressed.emit()
	_check(bool(game.get("map_legend_open")), "Legend control toggles the map key")
	_check((controls.get_child(5) as Button).accessibility_name == "Hide map marker legend", "Legend accessibility label tracks its expanded state")
	_check((game.get("map_legend_panel") as Control).visible, "Legend control displays its panel during a game")
	var legend_layout := (game.get("map_legend_panel") as Control).get_global_rect()
	var controls_layout := controls.get_global_rect()
	_check(not legend_layout.intersects(controls_layout), "open map legend does not cover the map-control stack")
	game.queue_free()
	print("MAP CONTROLS RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
