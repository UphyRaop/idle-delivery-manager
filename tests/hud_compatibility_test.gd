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
	var brand: Label = game.get("brand_label")
	var cash: Label = game.get("cash_label")
	var active: Label = game.get("active_jobs_label")
	var pending: Label = game.get("pending_jobs_label")
	var hud: Control = game.get("hud")
	var speeds: Control = game.get("sim_controls")
	var map_controls: Control = game.get("map_controls")
	_check(is_instance_valid(brand) and is_instance_valid(cash) and is_instance_valid(active) and is_instance_valid(pending), "existing company, cash, active-job, and waiting-booking HUD values are present")
	_check(brand.get_theme_color("font_color") == Color("#45d9ec"), "approved cyan company identity styling is preserved")
	_check(brand.get_theme_font_size("font_size") == 16, "approved company identity type size is preserved at the 390px reference width")
	_check(cash.get_theme_font_size("font_size") == 16, "approved cash type size is preserved at the 390px reference width")
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
		var viewport: Vector2 = game.get("viewport_size")
		var insets: Vector4 = game.get("safe_insets")
		var hud_rect := hud.get_global_rect()
		var speed_rect := speeds.get_global_rect()
		var map_rect := (game.get("map_view") as Control).get_global_rect()
		var hud_inside_safe_area := hud_rect.position.x >= insets.x and hud_rect.end.x <= viewport.x - insets.z and hud_rect.position.y >= insets.y
		_check(root.size == requested and viewport.x > 0.0 and viewport.y > 0.0, "viewport %dx%d is reflected in the HUD layout" % [requested.x, requested.y])
		_check(hud_inside_safe_area, "HUD stays inside the horizontal and top safe areas at %dx%d" % [requested.x, requested.y])
		_check(not hud_rect.intersects(speed_rect), "HUD does not overlap speed controls at %dx%d" % [requested.x, requested.y])
		_check(map_rect.position.is_zero_approx() and map_rect.size.is_equal_approx(game.size), "map remains full-viewport behind controls at %dx%d" % [requested.x, requested.y])
		_check(map_controls.get_global_rect().position.y >= speed_rect.end.y, "map controls remain below the HUD/speed row at %dx%d" % [requested.x, requested.y])
	root.size = Vector2i(390, 844)
	await process_frame
	game.set("safe_insets_css", Vector4(8, 59, 8, 34))
	game.call("_layout_ui")
	await process_frame
	var simulated_viewport: Vector2 = game.get("viewport_size")
	var simulated_safe: Vector4 = game.get("safe_insets")
	var notch_hud_rect := hud.get_global_rect()
	var home_nav_rect := (game.get("bottom_nav") as Control).get_global_rect()
	var full_map_rect := (game.get("map_view") as Control).get_global_rect()
	_check(simulated_safe.y > 0.0 and notch_hud_rect.position.y >= simulated_safe.y, "HUD clears simulated Dynamic Island and status-bar safe inset")
	_check(simulated_safe.w > 0.0 and home_nav_rect.end.y <= simulated_viewport.y - simulated_safe.w, "navigation clears simulated home-indicator safe inset")
	_check(full_map_rect.position.is_zero_approx() and full_map_rect.size.is_equal_approx(game.size), "map continues edge-to-edge behind safe-area controls")
	print("HUD COMPATIBILITY RESULT: %d passed, %d failed" % [passed, failed])
	game.queue_free()
	quit(1 if failed else 0)
