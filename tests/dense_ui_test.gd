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
	var theme: Node = load("res://scripts/services/theme_service.gd").new()
	_check(theme.dense_space("sm") < theme.dense_space("card") and theme.dense_space("card") < theme.dense_space("md"), "dense spacing tokens define a consistent compact rhythm")
	_check(theme.dense_font_size("caption") >= 11 and theme.dense_font_size("body") >= 13 and theme.dense_font_size("title") >= 18, "dense typography keeps readable caption, body, and heading sizes")
	_check(theme.dense_panel_padding("compact") < theme.panel_padding("compact"), "dense panel tokens reduce padding without changing touch targets")

	var game := Control.new()
	game.set_script(load("res://scripts/game.gd"))
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(game)
	await process_frame
	var dense_style := game.call("_panel_style", "#102433", 12) as StyleBoxFlat
	var preserved_style := game.call("_panel_style", "#102433", 12, true) as StyleBoxFlat
	_check(dense_style.content_margin_left == 7.0 and dense_style.content_margin_top == 4.0, "shared content panels use compact horizontal and vertical padding")
	_check(preserved_style.content_margin_left == 10.0 and preserved_style.content_margin_top == 6.0, "HUD retains its previously approved panel inset")
	var large_heading := game.call("_label", "Section heading", 18, "#f1f6fa") as Label
	var body := game.call("_label", "A compact body line", 14, "#a8bac8") as Label
	var meta := game.call("_label", "Small status", 10, "#91a8ba") as Label
	_check(large_heading.get_theme_font_size("font_size") == 15, "section headings use the dense type scale")
	_check(body.get_theme_font_size("font_size") == 13, "body labels use the dense type scale")
	_check(meta.get_theme_font_size("font_size") == 11, "metadata stays at the readable caption floor")
	_check(meta.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "single-line labels trim safely instead of clipping at panel edges")
	var action := game.call("_button", "Touch action", func() -> void: pass) as Button
	_check(action.custom_minimum_size.y >= 44.0 and action.get_theme_font_size("font_size") == 13, "dense buttons keep 44px targets with compact readable text")
	var metric := game.call("_metric_card", "AVAILABLE CASH", "RM500.00") as Control
	_check(metric.custom_minimum_size.y == 52.0, "financial KPI cards use compact card height")
	var hud := game.get("hud") as Control
	var hud_style := hud.get_theme_stylebox("panel") as StyleBoxFlat
	_check(hud_style.content_margin_left == 10.0 and hud_style.content_margin_top == 6.0, "existing top HUD spacing remains unchanged")
	_check((game.get("brand_label") as Label).get_theme_font_size("font_size") == 16, "existing top HUD type size remains unchanged")
	large_heading.free()
	body.free()
	meta.free()
	action.free()
	metric.free()
	game.queue_free()
	await process_frame
	theme.free()
	print("DENSE UI RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
