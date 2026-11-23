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
	var speeds: Dictionary = game.get("speed_buttons")
	var pause_button: Button = game.get("pause_button")
	var controls: PanelContainer = game.get("sim_controls")
	controls.visible = true
	var row := controls.get_child(0) as HBoxContainer
	_check(speeds.size() == 5 and [1, 5, 10, 50, 100].all(func(value: int) -> bool: return speeds.has(value)) and not speeds.has(2), "speed selector retains Pause and exactly 1x, 5x, 10x, 50x, and 100x")
	_check(is_instance_valid(pause_button) and pause_button.text in ["Pause", "Play"], "first segment remains the working Pause/Play control")
	var panel_style := controls.get_theme_stylebox("panel") as StyleBoxFlat
	_check(is_instance_valid(panel_style) and panel_style.bg_color.a > 0.0 and panel_style.bg_color.a < 1.0, "speed control background is translucent")
	var active_factor := int(game.get("speed"))
	var active_button: Button = speeds.get(active_factor)
	var active_style := active_button.get_theme_stylebox("normal") as StyleBoxFlat if is_instance_valid(active_button) else null
	_check(is_instance_valid(active_button) and active_button.get_meta("ui_variant") == "speed_selected" and active_style.bg_color.g > active_style.bg_color.r and active_style.bg_color.b > active_style.bg_color.r, "active simulation speed uses the cyan selection")
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
		var layout_scale := float(game.get("ui_layout_scale"))
		var viewport: Vector2 = game.get("viewport_size")
		var safe: Vector4 = game.get("safe_insets")
		var controls_rect := controls.get_global_rect()
		var hud_rect := (game.get("hud") as Control).get_global_rect()
		var segment_width := (pause_button.custom_minimum_size.x)
		var first_button_rect := pause_button.get_global_rect()
		var equal_segments := is_equal_approx(segment_width, speeds[1].custom_minimum_size.x) and is_equal_approx(first_button_rect.size.x, (speeds[1] as Button).get_global_rect().size.x)
		for button in speeds.values():
			equal_segments = equal_segments and is_equal_approx(segment_width, (button as Button).custom_minimum_size.x) and is_equal_approx(first_button_rect.size.x, (button as Button).get_global_rect().size.x)
		_check(root.size == requested and controls_rect.size.y >= 44.0 * layout_scale - 1.0 and controls_rect.size.y <= 45.0 * layout_scale + 1.0, "speed selector is 44 CSS px high at %dx%d" % [requested.x, requested.y])
		_check(equal_segments, "all six speed segments have equal widths at %dx%d" % [requested.x, requested.y])
		_check(controls_rect.position.x >= safe.x and controls_rect.end.x <= viewport.x - safe.z and absf(controls_rect.position.y - hud_rect.end.y) <= 1.0 and not controls_rect.intersects(hud_rect), "speed selector stays safe and directly below HUD at %dx%d" % [requested.x, requested.y])
		var map_view: Control = game.get("map_view")
		_check(map_view.get_global_rect().position.is_zero_approx() and map_view.get_global_rect().size.is_equal_approx(game.size), "map remains full-viewport behind speed selector at %dx%d" % [requested.x, requested.y])
	(speeds[5] as Button).emit_signal("pressed")
	_check(int(game.get("speed")) == 5 and (speeds[5] as Button).get_meta("ui_variant") == "speed_selected", "5x segment updates simulation and active styling")
	pause_button.emit_signal("pressed")
	_check(not bool(game.get("paused")) and pause_button.tooltip_text == "Pause simulation", "Play segment resumes the simulation and updates its accessible label")
	pause_button.emit_signal("pressed")
	_check(bool(game.get("paused")) and pause_button.tooltip_text == "Resume simulation", "Pause segment pauses the simulation and updates its accessible label")
	print("SPEED CONTROL RESULT: %d passed, %d failed" % [passed, failed])
	game.queue_free()
	quit(1 if failed else 0)
