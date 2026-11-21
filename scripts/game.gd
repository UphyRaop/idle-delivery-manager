extends Control

const LEGACY_SAVE_PATH := "user://delivery_ops_save.json"
const ACTIVE_SAVE_MARKER := "user://idm_active_save.json"
var save_path := LEGACY_SAVE_PATH
var save_recovery_required := false
var recovery_overlay: ColorRect
const STARTING_CASH := 500.0
const STARTING_RIDERS := 3
const ORDER_INTERVAL := 8.0
const TRAVEL_SECONDS := 12.0

var cash := STARTING_CASH
var revenue_total := 0.0
var cost_total := 0.0
var delivered := 0
var riders: Array[Dictionary] = []
var orders: Array[Dictionary] = []
var paused := false
var speed := 1
var elapsed := 0.0
var next_order_id := 1
var next_rider_id := 1
var selected_order := -1
var map_view: Control
var order_list: VBoxContainer
var rider_summary: Label
var finance_summary: Label
var status_label: Label
var cash_label: Label
var active_jobs_label: Label
var pending_jobs_label: Label
var geographic_service := IDMGeographicService.new()
var geographic_map_available := false
var legacy_map_mode := false
var map_texture: Texture2D
var pause_button: Button
var speed_buttons: Dictionary = {}
var sheet: PanelContainer
var sheet_content: VBoxContainer
var sheet_toggle_button: Button
var sheet_header_label: Label
var map_controls: GridContainer
var bottom_nav: PanelContainer
var nav_buttons: Dictionary = {}
var hud: PanelContainer
var sim_controls: PanelContainer
var selected_tab := "Map"
var selected_subtab := "City"
var sheet_expanded := false
var last_tap_msec := 0
var map_mode := "City"
var map_zoom := 1.0
var map_pan := Vector2.ZERO
var gesture_start := Vector2.ZERO
var gesture_pan := Vector2.ZERO
var pinch_distance := 0.0
var suppress_tap := false
var zoom_label: Label
var world_map := false
var viewport_size := Vector2(390, 844)
var safe_insets := Vector4(8, 8, 8, 16)
var ui_scale := 1.0

func _ready() -> void:
	geographic_map_available = geographic_service.load_data()
	_load_map_texture()
	_load_active_save_path()
	_load_game()
	_build_ui()
	ThemeService.theme_changed.connect(_on_theme_changed)
	get_viewport().size_changed.connect(_layout_ui)
	_layout_ui()
	_refresh()
	if save_recovery_required:
		_show_save_recovery()
	elif orders.is_empty():
		_spawn_order()
		_spawn_order()
		_save_game()

func _load_active_save_path() -> void:
	if not FileAccess.file_exists(ACTIVE_SAVE_MARKER):
		return
	var marker := FileAccess.open(ACTIVE_SAVE_MARKER, FileAccess.READ)
	if marker == null:
		return
	var parsed := JSON.new()
	if parsed.parse(marker.get_as_text()) != OK or typeof(parsed.data) != TYPE_DICTIONARY:
		return
	var candidate := str(parsed.data.get("path", ""))
	if candidate == LEGACY_SAVE_PATH or (candidate.begins_with("user://delivery_ops_session_") and candidate.ends_with(".json")):
		save_path = candidate

func _load_map_texture() -> void:
	if not geographic_map_available:
		map_texture = null
		return
	var texture_path := "res://data/kl_selangor_%s.png" % ThemeService.mode
	map_texture = load(texture_path) as Texture2D

func _set_active_save_path(path: String) -> void:
	var marker := FileAccess.open(ACTIVE_SAVE_MARKER, FileAccess.WRITE)
	if marker != null:
		marker.store_string(JSON.stringify({"path": path}))

func _process(delta: float) -> void:
	if paused or save_recovery_required:
		return
	elapsed += delta * speed
	if elapsed >= ORDER_INTERVAL:
		elapsed = 0.0
		_spawn_order()
	for rider in riders:
		if rider["status"] == "busy":
			rider["remaining"] -= delta * speed
			if rider["remaining"] <= 0:
				_finish_delivery(rider)
	_save_game()
	_refresh_map()

func _build_ui() -> void:
	map_view = Control.new()
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_view.mouse_filter = Control.MOUSE_FILTER_STOP
	map_view.draw.connect(_draw_map)
	map_view.gui_input.connect(_on_map_input)
	add_child(map_view)

	hud = PanelContainer.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.add_theme_stylebox_override("panel", _panel_style("#101e2b", 18))
	add_child(hud)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	hud.add_child(top_row)
	var brand := Label.new()
	brand.text = "IDM"
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_color_override("font_color", Color("#45d9ec"))
	brand.add_theme_font_size_override("font_size", 19)
	top_row.add_child(brand)
	var activity := VBoxContainer.new()
	activity.add_theme_constant_override("separation", 1)
	activity.custom_minimum_size.x = 70
	top_row.add_child(activity)
	active_jobs_label = Label.new()
	active_jobs_label.add_theme_font_size_override("font_size", 10)
	active_jobs_label.add_theme_color_override("font_color", ThemeService.color("text"))
	activity.add_child(active_jobs_label)
	pending_jobs_label = Label.new()
	pending_jobs_label.add_theme_font_size_override("font_size", 10)
	pending_jobs_label.add_theme_color_override("font_color", ThemeService.color("muted"))
	activity.add_child(pending_jobs_label)
	var balance := VBoxContainer.new()
	balance.custom_minimum_size.x = 70
	balance.add_theme_constant_override("separation", 0)
	top_row.add_child(balance)
	cash_label = Label.new()
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash_label.add_theme_font_size_override("font_size", 16)
	cash_label.add_theme_color_override("font_color", Color("#f3f7fb"))
	balance.add_child(cash_label)
	var balance_caption := Label.new()
	balance_caption.text = "AVAILABLE"
	balance_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	balance_caption.add_theme_font_size_override("font_size", 9)
	balance_caption.add_theme_color_override("font_color", Color("#91a8ba"))
	balance.add_child(balance_caption)

	sim_controls = PanelContainer.new()
	sim_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	sim_controls.add_theme_stylebox_override("panel", _panel_style("#102433", 16))
	add_child(sim_controls)
	var sim_row := HBoxContainer.new()
	sim_row.add_theme_constant_override("separation", 4)
	sim_controls.add_child(sim_row)
	pause_button = _button("Pause", _toggle_pause)
	pause_button.custom_minimum_size = Vector2(70, 46)
	sim_row.add_child(pause_button)
	for multiplier in [1, 2, 5, 10]:
		var factor: int = multiplier
		var speed_button := _button(str(factor) + "×", func(): _set_speed(factor))
		speed_button.custom_minimum_size = Vector2(46, 46)
		speed_button.add_theme_font_size_override("font_size", 14)
		speed_buttons[factor] = speed_button
		sim_row.add_child(speed_button)

	map_controls = GridContainer.new()
	map_controls.columns = 1
	map_controls.add_theme_constant_override("h_separation", 4)
	map_controls.add_theme_constant_override("v_separation", 5)
	add_child(map_controls)
	var zoom_in := _button("+", func(): _zoom_map(1.25))
	var zoom_out := _button("−", func(): _zoom_map(0.8))
	var recenter := _button("Center", _recenter_map)
	for control in [zoom_in, zoom_out, recenter]:
		control.custom_minimum_size = Vector2(72, 46)
		control.add_theme_font_size_override("font_size", 14)
		map_controls.add_child(control)

	sheet = PanelContainer.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.add_theme_stylebox_override("panel", _panel_style("#102433", 22))
	add_child(sheet)
	sheet_content = VBoxContainer.new()
	sheet_content.add_theme_constant_override("separation", 6)
	sheet.add_child(sheet_content)

	var handle_row := CenterContainer.new()
	handle_row.custom_minimum_size.y = 10
	sheet_content.add_child(handle_row)
	var sheet_grabber := ColorRect.new()
	sheet_grabber.color = Color("#547184")
	sheet_grabber.custom_minimum_size = Vector2(38, 4)
	handle_row.add_child(sheet_grabber)

	var sheet_header := HBoxContainer.new()
	sheet_header.add_theme_constant_override("separation", 8)
	sheet_content.add_child(sheet_header)
	sheet_header_label = _label("INCOMING PARCELS", 12, "#91a8ba")
	sheet_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_header.add_child(sheet_header_label)
	sheet_toggle_button = _button("Expand", _toggle_sheet)
	sheet_toggle_button.custom_minimum_size = Vector2(76, 44)
	sheet_header.add_child(sheet_toggle_button)
	var subtabs := HBoxContainer.new()
	subtabs.add_theme_constant_override("separation", 5)
	subtabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtabs.name = "Subtabs"
	sheet_content.add_child(subtabs)
	order_list = VBoxContainer.new()
	order_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	order_list.custom_minimum_size.y = 24
	order_list.add_theme_constant_override("separation", 8)
	sheet_content.add_child(order_list)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#53d5ba"))
	sheet_content.add_child(status_label)

	bottom_nav = PanelContainer.new()
	bottom_nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var nav_style := _panel_style("#0d1e2a", 0)
	nav_style.content_margin_top = 4
	nav_style.content_margin_bottom = 4
	bottom_nav.add_theme_stylebox_override("panel", nav_style)
	add_child(bottom_nav)
	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 5)
	bottom_nav.add_child(nav_row)
	for name in ["Map", "Operations", "Finance", "Settings"]:
		var internal_tab: String = name
		var button := _button(name, func(): _set_tab(internal_tab))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 56)
		button.add_theme_font_size_override("font_size", 14)
		nav_buttons[internal_tab] = button
		nav_row.add_child(button)

func _panel_style(color: String, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeService.color("panel")
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = ThemeService.color("panel_border")
	return style

func _label(text: String, size: int, color: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", int(round(float(size) * ui_scale)))
	label.add_theme_color_override("font_color", ThemeService.resolve_existing_text(Color(color)))
	return label

func _layout_ui() -> void:
	if not is_instance_valid(map_view) or not is_instance_valid(sheet) or not is_instance_valid(bottom_nav):
		return
	var window := get_window()
	if window.size.x > 0 and window.size.y > 0:
		window.content_scale_size = window.size
	viewport_size = Vector2(window.size)
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		viewport_size = get_viewport_rect().size
	ui_scale = clampf(minf(viewport_size.x / 390.0, viewport_size.y / 844.0), 1.0, 1.15)
	safe_insets = _read_safe_insets()
	var is_landscape := viewport_size.x > viewport_size.y
	var is_desktop := viewport_size.x >= 1024.0 and viewport_size.y >= 600.0
	var selected := _find_order(selected_order)
	var order_detail_open: bool = selected_tab == "Map" and not selected.is_empty() and selected["status"] == "Waiting"
	var nav_height: int = 76 if not is_landscape else 64
	var sheet_height: int = 258 if sheet_expanded else 148
	if is_landscape:
		sheet_height = 222 if sheet_expanded else 122
	if is_desktop:
		sheet_height = 260 if sheet_expanded else 128
	var safe_left := safe_insets.x
	var safe_top := safe_insets.y
	var safe_right := safe_insets.z
	var safe_bottom := safe_insets.w

	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.offset_left = safe_left + 12
	hud.offset_top = safe_top + 8
	hud.offset_right = -safe_right - 12
	hud.offset_bottom = safe_top + 64
	sim_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	sim_controls.offset_left = safe_left + 12
	sim_controls.offset_top = safe_top + 72
	sim_controls.offset_right = safe_left + 306
	sim_controls.offset_bottom = safe_top + 134

	var controls_on_left := is_landscape and sheet_expanded
	map_controls.columns = 1
	map_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT if controls_on_left else Control.PRESET_TOP_RIGHT)
	map_controls.offset_left = safe_left + 12 if controls_on_left else -safe_right - 84
	map_controls.offset_right = safe_left + 84 if controls_on_left else -safe_right - 12
	map_controls.offset_top = safe_top + 132
	map_controls.offset_bottom = safe_top + 284

	bottom_nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	if is_desktop:
		var nav_width := 480.0
		bottom_nav.offset_left = maxf(safe_left + 12, (viewport_size.x - nav_width) * 0.5)
		bottom_nav.offset_right = -maxf(safe_right + 12, (viewport_size.x - nav_width) * 0.5)
	else:
		bottom_nav.offset_left = safe_left + 8
		bottom_nav.offset_right = -safe_right - 8
	bottom_nav.offset_top = -safe_bottom - nav_height
	bottom_nav.offset_bottom = -safe_bottom

	if is_desktop or is_landscape:
		sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		sheet.offset_left = -366
		sheet.offset_right = -safe_right - 12
		sheet.offset_top = -safe_bottom - nav_height - 8 - sheet_height
		sheet.offset_bottom = -safe_bottom - nav_height - 8
	else:
		sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		sheet.offset_left = safe_left + 10
		sheet.offset_right = -safe_right - 10
		sheet.offset_top = -safe_bottom - nav_height - 8 - sheet_height
		sheet.offset_bottom = -safe_bottom - nav_height - 8

	if is_instance_valid(sheet_toggle_button):
		sheet_toggle_button.text = "Hide" if sheet_expanded else "Expand"
	if is_instance_valid(sheet_header_label):
		sheet_header_label.text = _sheet_title()
	sheet_content.add_theme_constant_override("separation", 3 if is_landscape and sheet_expanded else 6)
	if sheet_content.get_child_count() > 0:
		sheet_content.get_child(0).custom_minimum_size.y = 8 if is_landscape and sheet_expanded else 10
	if is_instance_valid(sheet_toggle_button):
		sheet_toggle_button.custom_minimum_size.y = 40 if is_landscape and sheet_expanded else 44
	if is_instance_valid(order_list):
		var subtabs: HBoxContainer = sheet_content.find_child("Subtabs", true, false)
		if is_instance_valid(subtabs):
			subtabs.visible = sheet_expanded
			for subtab in subtabs.get_children():
				subtab.custom_minimum_size.y = 40 if is_landscape and sheet_expanded else 46
		order_list.visible = sheet_expanded or selected_tab == "Map"
		if not sheet_expanded and selected_tab == "Map":
			for child in order_list.get_children():
				child.visible = false
			if order_list.get_child_count() > 0:
				order_list.get_child(0).visible = true
	if is_instance_valid(status_label):
		var active_map_order: bool = selected_tab == "Map" and not selected.is_empty() and selected["status"] in ["Waiting", "On route"]
		status_label.visible = status_label.text != "" and (sheet_expanded or selected_tab == "Map") and not active_map_order
	for tab in nav_buttons:
		var nav_button: Button = nav_buttons[tab]
		var selected_button: bool = tab == selected_tab
		nav_button.modulate = Color("#3bd5e8") if selected_button else Color("#dbe7ef")
	map_view.queue_redraw()

func _read_safe_insets() -> Vector4:
	var insets := Vector4(8, 8, 8, 16)
	if Engine.has_singleton("JavaScriptBridge"):
		var bridge: Object = Engine.get_singleton("JavaScriptBridge")
		if bridge != null:
			insets.x = maxf(insets.x, _safe_value(bridge, "left"))
			insets.y = maxf(insets.y, _safe_value(bridge, "top"))
			insets.z = maxf(insets.z, _safe_value(bridge, "right"))
			insets.w = maxf(insets.w, _safe_value(bridge, "bottom"))
	return insets

func _safe_value(bridge: Object, side: String) -> float:
	var value: Variant = bridge.call("eval", "parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--idm-safe-" + side + "')) || 0", true)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return clampf(float(value), 0.0, 80.0)
	return 0.0

func _sheet_title() -> String:
	match selected_tab:
		"Map":
			if sheet_expanded:
				return "KL + SELANGOR  ·  OPENSTREETMAP" if geographic_map_available and not legacy_map_mode else "PARCELS  ·  FICTIONAL CITY MAP"
			return "%d PARCELS WAITING  ·  TAP A PIN" % _waiting_count()
		"Operations": return "OPERATIONS  ·  " + selected_subtab.to_upper()
		"Finance": return "COMPANY FINANCES"
		_: return "SETTINGS  ·  " + selected_subtab.to_upper()

func _zoom_map(factor: float) -> void:
	var center := map_view.size * 0.5
	var world_center := (center - map_pan) / map_zoom
	map_zoom = clampf(map_zoom * factor, 0.65, 2.5)
	map_pan = center - world_center * map_zoom
	_clamp_map_pan()
	map_view.queue_redraw()

func _clamp_map_pan() -> void:
	map_pan.x = clampf(map_pan.x, -map_view.size.x * 0.8, map_view.size.x * 0.8)
	map_pan.y = clampf(map_pan.y, -map_view.size.y * 0.8, map_view.size.y * 0.8)

func _recenter_map() -> void:
	map_pan = Vector2.ZERO
	map_zoom = 1.0
	map_view.queue_redraw()

func _toggle_world() -> void:
	world_map = not world_map
	selected_subtab = "World" if world_map else "City"
	map_mode = selected_subtab
	map_zoom = 0.7 if world_map else 1.0
	map_pan = Vector2.ZERO
	status_label.text = "World overview" if world_map else "City map"
	_refresh()

func _set_subtab(name: String) -> void:
	selected_subtab = name
	sheet_expanded = true
	if selected_tab == "Map":
		map_mode = name
		world_map = name == "World"
		map_zoom = 0.7 if world_map else 1.0
		map_pan = Vector2.ZERO
		map_view.queue_redraw()
		status_label.text = name + " map"
	else:
		status_label.text = name + " selected"
	_refresh()

func _set_tab(name: String) -> void:
	selected_tab = name
	sheet_expanded = true
	if name == "Map":
		selected_subtab = "World" if world_map else "City"
	else:
		selected_subtab = {"Operations":"Fleet", "Finance":"Overview", "Settings":"Game"}.get(name, "City")
	status_label.text = ""
	_refresh()

func _toggle_sheet() -> void:
	sheet_expanded = not sheet_expanded
	_layout_ui()

func _on_map_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			gesture_start = event.position
			gesture_pan = map_pan
			suppress_tap = false
		elif not suppress_tap:
			var now := Time.get_ticks_msec()
			if now - last_tap_msec < 320:
				_zoom_map(1.4)
			else:
				_select_marker(event.position)
			last_tap_msec = now
	elif event is InputEventScreenDrag:
		if event.position.distance_to(gesture_start) > 8:
			suppress_tap = true
		map_pan = gesture_pan + event.position - gesture_start
		_clamp_map_pan()
		map_view.queue_redraw()
	elif event is InputEventMagnifyGesture:
		_zoom_map(event.factor)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_zoom_map(1.4)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_map(1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_map(0.87)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				gesture_start = event.position
				gesture_pan = map_pan
				suppress_tap = false
			elif not suppress_tap:
				_select_marker(event.position)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if event.position.distance_to(gesture_start) > 8:
			suppress_tap = true
		map_pan = gesture_pan + event.position - gesture_start
		_clamp_map_pan()
		map_view.queue_redraw()

func _select_marker(point: Vector2) -> void:
	var map_rect := _map_content_rect(map_view.size)
	for order in orders:
		if order["status"] == "Waiting":
			var destination: Vector2 = map_rect.position + order["destination"] * map_rect.size
			var screen_destination := destination * map_zoom + map_pan
			if point.distance_to(screen_destination) < 30:
				selected_order = order["id"]
				sheet_expanded = true
				_refresh()
				return

func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 46
	button.pressed.connect(callback)
	button.add_theme_font_size_override("font_size", int(round(15.0 * ui_scale)))
	button.add_theme_color_override("font_color", ThemeService.color("button_text"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = ThemeService.color("button")
	normal.set_corner_radius_all(14)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = ThemeService.color("button_hover")
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = ThemeService.color("accent_fill")
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate()
	disabled.bg_color = ThemeService.color("panel_border")
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_disabled_color", ThemeService.color("muted"))
	return button

func _on_theme_changed(_mode: String) -> void:
	_load_map_texture()
	_apply_theme_to_ui()
	if is_instance_valid(map_view):
		map_view.queue_redraw()

func _apply_theme_to_ui() -> void:
	for node in find_children("*", "PanelContainer", true, false):
		var style: StyleBoxFlat = node.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		style.bg_color = ThemeService.color("panel")
		style.border_color = ThemeService.color("panel_border")
		node.add_theme_stylebox_override("panel", style)
	for node in find_children("*", "Button", true, false):
		var button: Button = node
		var is_action := button.text.contains("Dispatch")
		var normal: StyleBoxFlat = button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		normal.bg_color = ThemeService.color("accent_fill") if is_action else ThemeService.color("button")
		button.add_theme_stylebox_override("normal", normal)
		var hover: StyleBoxFlat = button.get_theme_stylebox("hover").duplicate() as StyleBoxFlat
		hover.bg_color = ThemeService.color("accent_fill") if is_action else ThemeService.color("button_hover")
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_color_override("font_color", ThemeService.color("button_text") if not is_action else Color("#04252d"))
	for node in find_children("*", "Label", true, false):
		var label: Label = node
		label.add_theme_color_override("font_color", ThemeService.resolve_existing_text(label.get_theme_color("font_color")))

func _spawn_order() -> void:
	if orders.size() >= 5:
		for index in orders.size():
			if orders[index]["status"] == "Delivered":
				orders.remove_at(index)
				break
		if orders.size() >= 5:
			return
	var viewport_size := get_viewport_rect().size
	var min_x := 0.12
	var max_x := 0.60
	var min_y := 0.35
	var max_y := 0.62
	if viewport_size.x > viewport_size.y:
		max_x = 0.52
		min_y = 0.34
		max_y = 0.74
	var destination := geographic_service.random_road_location(get_viewport_rect().size) if geographic_map_available and not legacy_map_mode else Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
	for attempt in 10:
		var overlaps := false
		for existing in orders:
			if existing["status"] != "Delivered" and destination.distance_to(existing["destination"]) < 0.16:
				overlaps = true
				break
		if not overlaps:
			break
		destination = geographic_service.random_road_location(get_viewport_rect().size) if geographic_map_available and not legacy_map_mode else Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
	orders.append({
		"id": next_order_id,
		"destination": destination,
		"destination_latitude": geographic_service.uv_to_geo(destination).y if geographic_map_available and not legacy_map_mode else null,
		"destination_longitude": geographic_service.uv_to_geo(destination).x if geographic_map_available and not legacy_map_mode else null,
		"coordinate_reference": "EPSG:4326" if geographic_map_available and not legacy_map_mode else "legacy_normalized",
		"payout": randi_range(55, 105),
		"status": "Waiting",
		"rider": -1,
	})
	next_order_id += 1
	_save_game()
	_refresh()

func _dispatch(order_id: int) -> void:
	var order := _find_order(order_id)
	if order.is_empty() or order["status"] != "Waiting":
		return
	var available := -1
	for index in riders.size():
		if riders[index]["status"] == "ready":
			available = index
			break
	if available < 0:
		status_label.text = "No rider available"
		return
	var rider: Dictionary = riders[available]
	rider["status"] = "busy"
	rider["order_id"] = order_id
	rider["remaining"] = TRAVEL_SECONDS
	order["origin"] = rider["position"]
	if geographic_map_available and not legacy_map_mode:
		var origin_geo := geographic_service.uv_to_geo(rider["position"])
		order["origin_latitude"] = origin_geo.y
		order["origin_longitude"] = origin_geo.x
	order["status"] = "On route"
	order["rider"] = rider["id"]
	selected_order = order_id
	status_label.text = "Rider %02d dispatched · road routing pending" % rider["id"] if geographic_map_available and not legacy_map_mode else "Rider %02d dispatched" % rider["id"]
	_save_game()
	_refresh()

func _finish_delivery(rider: Dictionary) -> void:
	var order := _find_order(rider["order_id"])
	if order.is_empty():
		rider["status"] = "ready"
		return
	var payout: float = order["payout"]
	var operating_cost := 18.0
	cash += payout - operating_cost
	revenue_total += payout
	cost_total += operating_cost
	delivered += 1
	order["status"] = "Delivered"
	order["delivered_at"] = Time.get_unix_time_from_system()
	rider["status"] = "ready"
	rider["order_id"] = -1
	status_label.text = "Delivered  +RM%d  ·  cost RM%d" % [payout, operating_cost]
	# Return control to the map after a completed stop; keep the outcome visible in the compact sheet.
	sheet_expanded = false
	_save_game()
	_refresh()

func _hire_rider() -> void:
	if cash < 120:
		status_label.text = "Need RM120 to recruit partner"
		return
	cash -= 120
	riders.append({"id": next_rider_id, "status": "ready", "order_id": -1, "remaining": 0.0, "position": Vector2(0.5, 0.5)})
	next_rider_id += 1
	status_label.text = "Rider hired and ready"
	_save_game()
	_refresh()

func _toggle_pause() -> void:
	paused = not paused
	pause_button.text = "Resume" if paused else "Pause"
	status_label.text = "Simulation paused" if paused else "Operations resumed"

func _set_speed(value: int) -> void:
	speed = value
	status_label.text = "Simulation speed: %d×" % speed
	for factor in speed_buttons:
		var button: Button = speed_buttons[factor]
		button.modulate = Color("#69e4fa") if factor == speed else Color.WHITE

func _find_order(order_id: int) -> Dictionary:
	for order in orders:
		if order["id"] == order_id:
			return order
	return {}

func _refresh() -> void:
	if not is_instance_valid(order_list):
		return
	cash_label.text = "RM%0.0f" % cash
	active_jobs_label.text = "ACTIVE  %d" % _busy_count()
	pending_jobs_label.text = "ORDERS  %d" % _waiting_count()
	if selected_tab == "Map" and status_label.text == "" and _find_order(selected_order).is_empty():
		status_label.text = "Tap a parcel pin to see payout and dispatch."
	for child in order_list.get_children():
		child.queue_free()
	var subtabs: HBoxContainer = sheet_content.find_child("Subtabs", true, false)
	if is_instance_valid(subtabs):
		for child in subtabs.get_children():
			child.queue_free()
		var options: Array[String] = []
		match selected_tab:
			"Map": options = ["City", "World"]
			"Operations": options = ["Fleet", "Company"]
			"Finance": options = ["Overview", "Statements"]
			_: options = ["Game", "Preferences"]
		for option in options:
			var subtab := _button(option, func(): _set_subtab(option))
			subtab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			subtab.custom_minimum_size = Vector2(0, 46)
			if option == selected_subtab:
				subtab.modulate = Color("#43d6e8")
			subtabs.add_child(subtab)
	match selected_tab:
		"Map":
			var selected := _find_order(selected_order)
			if not selected.is_empty() and selected["status"] == "Waiting":
				var detail := _label("PARCEL %03d" % selected["id"], 13, "#91a8ba")
				order_list.add_child(detail)
				var payout := _label("RM%d delivery payout" % selected["payout"], 20, "#f1f6fa")
				payout.add_theme_font_size_override("font_size", int(round(20.0 * ui_scale)))
				order_list.add_child(payout)
				var dispatch := _button("Dispatch rider", func(): _dispatch(selected["id"]))
				dispatch.custom_minimum_size.y = 50
				dispatch.add_theme_color_override("font_color", Color("#04252d"))
				var dispatch_style := StyleBoxFlat.new()
				dispatch_style.bg_color = Color("#48d9e9")
				dispatch_style.set_corner_radius_all(15)
				dispatch.add_theme_stylebox_override("normal", dispatch_style)
				order_list.add_child(dispatch)
			elif not selected.is_empty() and selected["status"] == "On route":
				order_list.add_child(_label("PARCEL %03d  ·  ON ROUTE" % selected["id"], 16, "#f1f6fa"))
				var route_notice := _label("Road routing is still in development; prototype travel continues.", 13, "#a8bac8")
				route_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				route_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				order_list.add_child(route_notice)
			else:
				var waiting_count := _waiting_count()
				var hint := _label("%d parcels waiting" % waiting_count if waiting_count > 0 else "Tap a parcel pin to review", 16, "#f1f6fa")
				order_list.add_child(hint)
				if sheet_expanded:
					var map_caption := "WORLD VIEW DATA UNAVAILABLE" if world_map else "OSM STREET MAP · KL/SELANGOR CORE" if geographic_map_available and not legacy_map_mode else "FICTIONAL CITY MAP · LEGACY SAVE"
					order_list.add_child(_label(map_caption, 12, "#91a8ba"))
		"Operations":
			if selected_subtab == "Fleet":
				var ready_label := _label("%d READY" % _ready_count(), 20, "#f1f6fa")
				order_list.add_child(ready_label)
				order_list.add_child(_label("%d on route   ·   %d total partners" % [_busy_count(), riders.size()], 13, "#a8bac8"))
				var hire := _button("+   Recruit partner  ·  RM120", _hire_rider)
				hire.custom_minimum_size.y = 50
				hire.disabled = cash < 120
				order_list.add_child(hire)
			else:
				order_list.add_child(_label("OPERATIONS  ·  PHASE 1", 13, "#91a8ba"))
				order_list.add_child(_label("%d active partners" % riders.size(), 20, "#f1f6fa"))
				order_list.add_child(_label("%d deliveries completed" % delivered, 14, "#a8bac8"))
		"Finance":
			if selected_subtab == "Statements":
				order_list.add_child(_label("Legacy prototype totals; ledger migration is not complete.", 12, "#91a8ba"))
			var metrics_row := HBoxContainer.new()
			metrics_row.add_theme_constant_override("separation", 8)
			order_list.add_child(metrics_row)
			metrics_row.add_child(_metric_card("BALANCE", "RM%0.0f" % cash))
			metrics_row.add_child(_metric_card("REVENUE", "RM%0.0f" % revenue_total))
			var totals_row := HBoxContainer.new()
			totals_row.add_theme_constant_override("separation", 8)
			order_list.add_child(totals_row)
			totals_row.add_child(_metric_card("OPERATING COST", "RM%0.0f" % cost_total))
			totals_row.add_child(_metric_card("DELIVERIES", str(delivered)))
		"Settings":
			if selected_subtab == "Preferences":
				order_list.add_child(_label("Appearance", 16, "#f1f6fa"))
				order_list.add_child(_label("Choose a readable map and panel theme.", 13, "#a8bac8"))
				var theme_button := _button("Switch to light theme" if ThemeService.mode == "dark" else "Switch to dark theme", _toggle_theme)
				theme_button.custom_minimum_size.y = 50
				order_list.add_child(theme_button)
			else:
				order_list.add_child(_label("Game controls", 16, "#f1f6fa"))
				order_list.add_child(_label("Pause and simulation speed are available on the map.", 13, "#a8bac8"))
				order_list.add_child(_label("The current prototype keeps its existing save format.", 12, "#91a8ba"))
	rider_summary = null
	finance_summary = null
	if is_instance_valid(sheet_header_label):
		sheet_header_label.text = _sheet_title()
	if is_instance_valid(map_view):
		map_view.queue_redraw()
	_layout_ui()

func _metric_card(title: String, value: String) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 46)
	var card_style := _panel_style("#152e3e", 13)
	card_style.content_margin_left = 8
	card_style.content_margin_right = 8
	card_style.content_margin_top = 3
	card_style.content_margin_bottom = 3
	card.add_theme_stylebox_override("panel", card_style)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	card.add_child(stack)
	stack.add_child(_label(title, 10, "#9db1c1"))
	var amount := _label(value, 18, "#f1f6fa")
	amount.add_theme_font_size_override("font_size", int(round(18.0 * ui_scale)))
	stack.add_child(amount)
	return card

func _toggle_theme() -> void:
	ThemeService.toggle()
	_refresh()

func _ready_count() -> int:
	var count := 0
	for rider in riders:
		if rider["status"] == "ready":
			count += 1
	return count

func _busy_count() -> int:
	var count := 0
	for rider in riders:
		if rider["status"] == "busy":
			count += 1
	return count

func _waiting_count() -> int:
	var count := 0
	for order in orders:
		if order["status"] == "Waiting":
			count += 1
	return count

func _refresh_map() -> void:
	if is_instance_valid(map_view):
		map_view.queue_redraw()

func _draw_map() -> void:
	var rect := map_view.get_rect()
	var size := rect.size
	if size.x <= 0 or size.y <= 0:
		return
	map_view.draw_rect(Rect2(Vector2.ZERO, size), ThemeService.color("map_background"))
	map_view.draw_set_transform(map_pan, 0.0, Vector2(map_zoom, map_zoom))
	var map_rect := _map_content_rect(size)
	if geographic_map_available and not legacy_map_mode and is_instance_valid(map_texture):
		map_view.draw_texture_rect(map_texture, map_rect, false)
		var major_places := ["Kuala Lumpur", "Petaling Jaya", "Shah Alam", "Subang Jaya", "Klang", "Kajang", "Ampang Jaya", "Puchong"]
		var drawn_label_rects: Array[Rect2] = []
		for place in geographic_service.places:
			var place_name := str(place.get("name", ""))
			var place_type := str(place.get("type", ""))
			if map_zoom < 1.25 and place_name not in major_places:
				continue
			if map_zoom >= 1.25 and place_type not in ["city", "town", "suburb", "quarter", "neighbourhood"]:
				continue
			var place_point: Vector2 = map_rect.position + place["uv"] * map_rect.size
			var screen_point := place_point * map_zoom + map_pan
			var label_width := ThemeDB.fallback_font.get_string_size(place_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var screen_bounds := Rect2(screen_point + Vector2(3, -18), Vector2(label_width + 8, 20))
			var label_bounds := Rect2(place_point + Vector2(3, -18), Vector2(label_width + 8, 20))
			var panel_obstruction := (size.x > size.y and screen_point.x > size.x - 390.0) or (size.x <= size.y and screen_point.y > size.y - 240.0)
			if panel_obstruction or screen_point.x < 8 or screen_point.x + label_width > size.x - 8 or screen_point.y < 185 or screen_point.y > size.y - 40:
				continue
			var overlaps_label := false
			for existing_bounds in drawn_label_rects:
				if existing_bounds.intersects(screen_bounds.grow(8)):
					overlaps_label = true
					break
			if overlaps_label:
				continue
			drawn_label_rects.append(screen_bounds)
			map_view.draw_rect(label_bounds, Color(0.02, 0.07, 0.10, 0.76))
			map_view.draw_string(ThemeDB.fallback_font, place_point + Vector2(7, -4), place_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ThemeService.color("text"))
		map_view.draw_string(ThemeDB.fallback_font, Vector2(18, 155), "© OpenStreetMap contributors · KL/Selangor", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ThemeService.color("map_label"))
		if world_map:
			map_view.draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.5 - 105, size.y * 0.24), "World map coverage is not available in this build.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ThemeService.color("text"))
	else:
		_draw_fictional_map_background(size)
	for order in orders:
		if order["status"] == "Delivered":
			continue
		var point: Vector2 = map_rect.position + order["destination"] * map_rect.size
		map_view.draw_circle(point, 21, ThemeService.color("rider_back"))
		map_view.draw_circle(point, 16, ThemeService.color("accent_fill"))
		map_view.draw_string(ThemeDB.fallback_font, point + Vector2(-4, 5), "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#06202a"))
	for rider in riders:
		var position: Vector2 = rider["position"]
		if rider["status"] == "busy":
			var order := _find_order(rider["order_id"])
			if not order.is_empty():
				var target: Vector2 = order["destination"]
				var progress := clampf(1.0 - rider["remaining"] / TRAVEL_SECONDS, 0.0, 1.0)
				var origin: Vector2 = order.get("origin", rider["position"])
				position = origin.lerp(target, progress)
				rider["position"] = position
				if geographic_map_available and not legacy_map_mode:
					var current_geo := geographic_service.uv_to_geo(position)
					rider["latitude"] = current_geo.y
					rider["longitude"] = current_geo.x
		var point := map_rect.position + position * map_rect.size
		map_view.draw_circle(point, 17, ThemeService.color("rider_back"))
		map_view.draw_circle(point, 12, ThemeService.color("rider"))
		map_view.draw_string(ThemeDB.fallback_font, point + Vector2(-4, 5), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#06202a"))
	map_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _map_content_rect(size: Vector2) -> Rect2:
	if not geographic_map_available or legacy_map_mode:
		return Rect2(Vector2.ZERO, size)
	var fit := maxf(size.x / IDMGeographicService.TEXTURE_SIZE.x, size.y / IDMGeographicService.TEXTURE_SIZE.y)
	var fitted := IDMGeographicService.TEXTURE_SIZE * fit
	return Rect2((size - fitted) * 0.5, fitted)

func _draw_fictional_map_background(size: Vector2) -> void:
	var columns := 7
	var rows := 9
	var cell_w := size.x / float(columns)
	var cell_h := size.y / float(rows)
	for row in rows:
		for column in columns:
			var cell := Rect2(Vector2(column * cell_w + 9, row * cell_h + 10), Vector2(cell_w - 18, cell_h - 20))
			var block := ThemeService.color("map_block") if (row + column) % 3 != 0 else ThemeService.color("map_block_alt")
			if (row == 2 and column == 1) or (row == 6 and column == 5):
				block = ThemeService.color("map_park")
			map_view.draw_rect(cell, block)
			map_view.draw_rect(cell, ThemeService.color("panel_border"), false, 1.0)
	for column in columns + 1:
		var x := column * cell_w
		map_view.draw_line(Vector2(x, 0), Vector2(x, size.y), ThemeService.color("map_road_outline"), 13.0, true)
		map_view.draw_line(Vector2(x, 0), Vector2(x, size.y), ThemeService.color("map_road"), 6.0, true)
	for row in rows + 1:
		var y := row * cell_h
		map_view.draw_line(Vector2(0, y), Vector2(size.x, y), ThemeService.color("map_road_outline"), 13.0, true)
		map_view.draw_line(Vector2(0, y), Vector2(size.x, y), ThemeService.color("map_road"), 6.0, true)
	map_view.draw_line(Vector2(size.x * 0.12, size.y * 0.78), Vector2(size.x * 0.88, size.y * 0.2), ThemeService.color("map_road_outline"), 23.0, true)
	map_view.draw_line(Vector2(size.x * 0.12, size.y * 0.78), Vector2(size.x * 0.88, size.y * 0.2), ThemeService.color("map_road"), 13.0, true)
	map_view.draw_string(ThemeDB.fallback_font, Vector2(18, 157), "FICTIONAL CITY  ·  EXISTING SAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ThemeService.color("map_label"))
	map_view.draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.12, size.y * 0.3), "NORTH DEPOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ThemeService.color("map_label"))
	map_view.draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.57, size.y * 0.67), "MARKET DISTRICT", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ThemeService.color("map_label"))

func _save_game() -> void:
	if save_recovery_required:
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return
	var data := {
		"version": 1,
		"map_space": "kl_selangor_web_mercator_uv" if geographic_map_available and not legacy_map_mode else "legacy_normalized",
		"map_bounds_wsen": [IDMGeographicService.WEST, IDMGeographicService.SOUTH, IDMGeographicService.EAST, IDMGeographicService.NORTH] if geographic_map_available and not legacy_map_mode else [],
		"cash": cash,
		"revenue_total": revenue_total,
		"cost_total": cost_total,
		"delivered": delivered,
		"riders": riders,
		"orders": orders,
		"next_order_id": next_order_id,
		"next_rider_id": next_rider_id,
		"elapsed": elapsed,
		"speed": speed,
	}
	file.store_string(JSON.stringify(data))

func _load_game() -> void:
	if not FileAccess.file_exists(save_path):
		_new_game()
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		save_recovery_required = true
		return
	var parsed := JSON.new()
	if parsed.parse(file.get_as_text()) != OK or typeof(parsed.data) != TYPE_DICTIONARY:
		save_recovery_required = true
		return
	var data: Dictionary = parsed.data
	if int(data.get("version", 0)) != 1:
		save_recovery_required = true
		return
	# Existing normalized saves belong to the old fictional prototype map. Keep
	# them in that coordinate space until a deliberate, visible migration exists.
	legacy_map_mode = str(data.get("map_space", "legacy_normalized")) != "kl_selangor_web_mercator_uv"
	cash = float(data.get("cash", STARTING_CASH))
	revenue_total = float(data.get("revenue_total", 0))
	cost_total = float(data.get("cost_total", 0))
	delivered = int(data.get("delivered", 0))
	next_order_id = int(data.get("next_order_id", 1))
	next_rider_id = int(data.get("next_rider_id", 1))
	elapsed = float(data.get("elapsed", 0))
	var loaded_speed := int(data.get("speed", 1))
	speed = 5 if loaded_speed == 4 else loaded_speed if loaded_speed in [1, 2, 5, 10] else 1
	orders.assign(data.get("orders", []))
	riders.assign(data.get("riders", []))
	if riders.is_empty():
		save_recovery_required = true
		return
	for order in orders:
		order["destination"] = _as_vector2(order.get("destination", ""), Vector2(0.5, 0.5))
	for rider in riders:
		rider["position"] = _as_vector2(rider.get("position", ""), Vector2(0.5, 0.5))
	for rider in riders:
		if rider["status"] == "busy":
			rider["remaining"] = minf(float(rider["remaining"]), TRAVEL_SECONDS)
			var order := _find_order(rider["order_id"])
			if not order.is_empty():
				order["status"] = "On route"

func _as_vector2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary and value.has("x") and value.has("y"):
		return Vector2(float(value["x"]), float(value["y"]))
	if value is String:
		var parts: PackedStringArray = value.strip_edges().trim_prefix("(").trim_suffix(")").split(",")
		if parts.size() >= 2:
			return Vector2(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float())
	return fallback

func _new_game() -> void:
	save_recovery_required = false
	legacy_map_mode = false
	cash = STARTING_CASH
	revenue_total = 0.0
	cost_total = 0.0
	delivered = 0
	orders.clear()
	riders.clear()
	for index in STARTING_RIDERS:
		var start_position := geographic_service.random_road_location(get_viewport_rect().size) if geographic_map_available else Vector2(0.5, 0.5)
		var rider := {"id": next_rider_id, "status": "ready", "order_id": -1, "remaining": 0.0, "position": start_position}
		if geographic_map_available:
			var point_geo := geographic_service.uv_to_geo(start_position)
			rider["latitude"] = point_geo.y
			rider["longitude"] = point_geo.x
			rider["coordinate_reference"] = "EPSG:4326"
		riders.append(rider)
		next_rider_id += 1
	_save_game()

func _show_save_recovery() -> void:
	if is_instance_valid(recovery_overlay):
		return
	recovery_overlay = ColorRect.new()
	recovery_overlay.color = Color(0.015, 0.04, 0.06, 0.88)
	recovery_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	recovery_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(recovery_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	recovery_overlay.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 0)
	card.add_theme_stylebox_override("panel", _panel_style("#102433", 20))
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	column.add_child(_label("SAVE NEEDS ATTENTION", 17, "#f1f6fa"))
	column.add_child(_label("Your existing save was kept unchanged. Try loading it again, or start a separate recovery game.", 13, "#a8bac8"))
	column.add_child(_button("Try Load Again", _retry_load))
	column.add_child(_button("Start New Game · Keep Old Save", _start_recovery_game))

func _retry_load() -> void:
	save_recovery_required = false
	_load_game()
	if not save_recovery_required:
		if is_instance_valid(recovery_overlay):
			recovery_overlay.queue_free()
		_refresh()
	else:
		status_label.text = "Save could not be loaded. The original remains untouched."

func _start_recovery_game() -> void:
	var session_path := "user://delivery_ops_session_%d.json" % Time.get_unix_time_from_system()
	save_path = session_path
	_set_active_save_path(save_path)
	_new_game()
	if is_instance_valid(recovery_overlay):
		recovery_overlay.queue_free()
	_refresh()
