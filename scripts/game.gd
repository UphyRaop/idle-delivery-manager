extends Control

const LEGACY_SAVE_PATH := "user://delivery_ops_save.json"
const ACTIVE_SAVE_MARKER := "user://idm_active_save.json"
const WEB_SAVE_MIRROR_KEY := "idm_active_save_v1"
const WEB_SAVE_PATH_KEY := "idm_active_save_path"
const WEB_SAVE_CATALOG_KEY := "idm_save_catalog_v1"
const SAVE_CATALOG_PATH := "user://idm_save_catalog.json"
const SAVE_SESSION_PREFIX := "user://delivery_ops_session_"
var save_path := LEGACY_SAVE_PATH
var save_profiles: Array[Dictionary] = []
var save_recovery_required := false
var recovery_overlay: ColorRect
var save_overlay: ColorRect
var new_game_confirmation: ColorRect
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
var autosave_elapsed := 0.0
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
var brand_label: Label
var available_label: Label
var geographic_service := IDMGeographicService.new()
var road_router := IDMRoadRouter.new()
var route_simulations: Dictionary = {}
var geographic_map_available := false
var road_network_available := false
var legacy_map_mode := false
var map_texture: Texture2D
var pause_button: Button
var speed_buttons: Dictionary = {}
var sheet: PanelContainer
var sheet_content: VBoxContainer
var sheet_toggle_button: Button
var sheet_header_label: Label
var map_controls: GridContainer
var fit_route_button: Button
var follow_rider_button: Button
var bottom_nav: PanelContainer
var nav_buttons: Dictionary = {}
var hud: PanelContainer
var sim_controls: PanelContainer
var selected_tab := "Map"
var selected_subtab := "City"
var sheet_expanded := false
var last_tap_msec := 0
var last_touch_input_msec := -1000
var map_mode := "City"
var map_camera := IDMMapCamera.new()
var followed_rider_id := -1
var gesture_start := Vector2.ZERO
var gesture_pan := Vector2.ZERO
var pinch_distance := 0.0
var touch_points: Dictionary = {}
var pinch_active := false
var suppress_tap := false
var zoom_label: Label
var world_map := false
var viewport_size := Vector2(390, 844)
var safe_insets := Vector4(8, 8, 8, 16)
var ui_scale := 1.0
var ui_layout_scale := 1.0
var maplibre_initialized := false
var browser_map_state: Dictionary = {}
var pending_map_camera: Dictionary = {}
var last_city_camera: Dictionary = {}
var follow_update_elapsed := 0.0
var map_camera_sync_elapsed := 0.0
var safe_area_refresh_elapsed := 0.0
var browser_block_rects_dirty := false
var browser_block_rects: Array[Dictionary] = []
var geographic_static_overlay_signature := ""
var pending_tap := false
var pending_tap_generation := 0
var pending_tap_point := Vector2.ZERO

const DEFAULT_CITY_CENTER := Vector2(101.69, 3.14)
const DEFAULT_CITY_ZOOM := 10.7

func _ready() -> void:
	geographic_map_available = geographic_service.load_data()
	road_network_available = road_router.load_network()
	_load_map_texture()
	_load_save_catalog()
	_load_active_save_path()
	_load_game()
	if not save_recovery_required:
		_register_current_save_profile()
	_build_ui()
	ThemeService.theme_changed.connect(_on_theme_changed)
	get_viewport().size_changed.connect(_layout_ui)
	safe_insets = _query_safe_insets()
	_layout_ui()
	_refresh()
	if save_recovery_required:
		_show_save_recovery()
	elif orders.is_empty():
		_spawn_order()
		_spawn_order()
		_save_game()

func _load_active_save_path() -> void:
	var stored_path: Variant = _web_storage_get(WEB_SAVE_PATH_KEY)
	var candidate := ""
	if stored_path != null:
		candidate = str(stored_path)
		if candidate in ["", "Null", "<null>"]:
			candidate = ""
	if candidate == "" and FileAccess.file_exists(ACTIVE_SAVE_MARKER):
		var marker := FileAccess.open(ACTIVE_SAVE_MARKER, FileAccess.READ)
		if marker != null:
			var parsed := JSON.new()
			if parsed.parse(marker.get_as_text()) == OK and typeof(parsed.data) == TYPE_DICTIONARY:
				candidate = str(parsed.data.get("path", ""))
	if _is_valid_save_path(candidate):
		save_path = candidate

func _is_valid_save_path(path: String) -> bool:
	return path == LEGACY_SAVE_PATH or (path.begins_with(SAVE_SESSION_PREFIX) and path.ends_with(".json"))

func _save_mirror_key(path: String) -> String:
	return "idm_save_" + path.sha256_text()

func _load_save_catalog() -> void:
	var catalog_text: Variant = _web_storage_get(WEB_SAVE_CATALOG_KEY)
	if not catalog_text is String or catalog_text.is_empty():
		if FileAccess.file_exists(SAVE_CATALOG_PATH):
			var catalog_file := FileAccess.open(SAVE_CATALOG_PATH, FileAccess.READ)
			if catalog_file != null:
				catalog_text = catalog_file.get_as_text()
	if not catalog_text is String or catalog_text.is_empty():
		return
	var parsed := JSON.new()
	if parsed.parse(catalog_text) != OK or typeof(parsed.data) != TYPE_ARRAY:
		return
	for item in parsed.data:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var profile: Dictionary = item
		var path := str(profile.get("path", ""))
		if not _is_valid_save_path(path):
			continue
		if save_profiles.any(func(existing: Dictionary) -> bool: return str(existing.get("path", "")) == path):
			continue
		profile["path"] = path
		save_profiles.append(profile)

func _persist_save_catalog() -> void:
	var serialized := JSON.stringify(save_profiles)
	var catalog_file := FileAccess.open(SAVE_CATALOG_PATH, FileAccess.WRITE)
	if catalog_file != null:
		catalog_file.store_string(serialized)
		catalog_file.flush()
		catalog_file.close()
	_web_storage_set(WEB_SAVE_CATALOG_KEY, serialized)

func _register_current_save_profile() -> void:
	if not _is_valid_save_path(save_path):
		return
	var display_name := "Legacy save · fictional map" if legacy_map_mode else "Geographic game · KL / Selangor"
	var found := false
	for index in save_profiles.size():
		if str(save_profiles[index].get("path", "")) == save_path:
			save_profiles[index]["title"] = display_name
			save_profiles[index]["map_space"] = "legacy_normalized" if legacy_map_mode else "kl_selangor_web_mercator_uv"
			found = true
			break
	if not found:
		save_profiles.append({
			"path": save_path,
			"title": display_name,
			"map_space": "legacy_normalized" if legacy_map_mode else "kl_selangor_web_mercator_uv",
			"created_at": int(Time.get_unix_time_from_system()),
		})
	_persist_save_catalog()

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
		marker.close()
	_web_storage_set(WEB_SAVE_PATH_KEY, path)

func _process(delta: float) -> void:
	if save_recovery_required:
		return
	_update_safe_area(delta)
	_update_browser_map(delta)
	_flush_map_input_blockers()
	if not paused:
		elapsed += delta * speed
		if elapsed >= ORDER_INTERVAL:
			elapsed = 0.0
			_spawn_order()
		for rider in riders:
			if rider.get("status", "") != "busy":
				continue
			var rider_id := int(rider.get("id", -1))
			if route_simulations.has(rider_id):
				var simulation: IDMRouteSimulation = route_simulations[rider_id]
				var events := simulation.advance(delta, float(speed))
				rider["position"] = simulation.current_uv
				rider["remaining"] = simulation.estimated_remaining_seconds(float(speed))
				rider["route_state"] = simulation.to_save()
				if geographic_map_available and not legacy_map_mode:
					var current_geo := geographic_service.uv_to_geo(rider["position"])
					rider["latitude"] = current_geo.y
					rider["longitude"] = current_geo.x
				for route_event in events:
					var active_order := _find_order(int(rider.get("order_id", -1)))
					if route_event == "reached_pickup" and not active_order.is_empty():
						active_order["status"] = "On route to delivery"
						status_label.text = "Partner %02d collected the parcel" % rider_id
					elif route_event == "delivered":
						_finish_delivery(rider)
			elif legacy_map_mode:
				# Retain progress for pre-geography saves in their original fictional coordinate space.
				rider["remaining"] = float(rider.get("remaining", TRAVEL_SECONDS)) - delta * speed
				if rider["remaining"] <= 0.0:
					_finish_delivery(rider)
	if map_camera.follow_enabled and followed_rider_id >= 0:
		var followed_rider := _find_rider(followed_rider_id)
		if followed_rider.is_empty():
			map_camera.follow_enabled = false
			followed_rider_id = -1
		elif _maplibre_active():
			follow_update_elapsed += delta
			if follow_update_elapsed >= 0.08:
				follow_update_elapsed = 0.0
				var geo := geographic_service.uv_to_geo(followed_rider["position"])
				_maplibre_call("window.IDMMap.setFollowTarget(%s, %s)" % [JSON.stringify(geo.x), JSON.stringify(geo.y)])
		else:
			map_camera.update_follow(delta, followed_rider["position"], _map_content_rect(map_view.size), map_view.size)
	if not paused:
		autosave_elapsed += delta
		if autosave_elapsed >= 1.0:
			autosave_elapsed = 0.0
			_save_game()
	_sync_geographic_overlays()
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
	brand_label = Label.new()
	brand_label.text = "IDM"
	brand_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_label.add_theme_color_override("font_color", Color("#45d9ec"))
	brand_label.add_theme_font_size_override("font_size", 19)
	top_row.add_child(brand_label)
	var activity := VBoxContainer.new()
	activity.add_theme_constant_override("separation", 1)
	activity.custom_minimum_size.x = 70
	top_row.add_child(activity)
	active_jobs_label = Label.new()
	active_jobs_label.add_theme_font_size_override("font_size", 11)
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
	available_label = Label.new()
	available_label.text = "1× · RUNNING"
	available_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	available_label.add_theme_font_size_override("font_size", 9)
	available_label.add_theme_color_override("font_color", Color("#91a8ba"))
	balance.add_child(available_label)

	sim_controls = PanelContainer.new()
	sim_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	sim_controls.add_theme_stylebox_override("panel", _panel_style("#102433", 16))
	add_child(sim_controls)
	var sim_row := HBoxContainer.new()
	sim_row.add_theme_constant_override("separation", 4)
	sim_controls.add_child(sim_row)
	pause_button = _button("Pause", _toggle_pause)
	pause_button.custom_minimum_size = Vector2(60, 46)
	pause_button.tooltip_text = "Pause or resume the simulation"
	sim_row.add_child(pause_button)
	for multiplier in [1, 2, 5, 10]:
		var factor: int = multiplier
		var speed_button := _button(str(factor) + "×", func(): _set_speed(factor))
		speed_button.custom_minimum_size = Vector2(42, 46)
		speed_button.add_theme_font_size_override("font_size", 13)
		speed_button.tooltip_text = "Set simulation speed to %d times" % factor
		speed_buttons[factor] = speed_button
		sim_row.add_child(speed_button)

	map_controls = GridContainer.new()
	map_controls.columns = 1
	map_controls.add_theme_constant_override("h_separation", 4)
	map_controls.add_theme_constant_override("v_separation", 5)
	add_child(map_controls)
	var zoom_in := _button("+", func(): _zoom_map(1.25))
	var zoom_out := _button("-", func(): _zoom_map(0.8))
	var recenter := _button("Center", _recenter_map)
	fit_route_button = _button("Fit", _fit_selected_booking)
	follow_rider_button = _button("Follow", _follow_selected_rider)
	zoom_in.tooltip_text = "Zoom in"
	zoom_out.tooltip_text = "Zoom out"
	recenter.tooltip_text = "Center map"
	fit_route_button.tooltip_text = "Fit selected booking or active route"
	follow_rider_button.tooltip_text = "Follow selected delivery partner"
	for control in [zoom_in, zoom_out, recenter, fit_route_button, follow_rider_button]:
		control.custom_minimum_size = Vector2(66, 48)
		control.add_theme_font_size_override("font_size", 13)
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
	sheet_header_label = _label("INCOMING BOOKINGS", 12, "#91a8ba")
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
	order_list.add_theme_constant_override("separation", 3)
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
	var previous_viewport := viewport_size
	var previous_map_rect := _map_content_rect(previous_viewport)
	var window := get_window()
	viewport_size = Vector2(window.size)
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		viewport_size = get_viewport_rect().size
	var viewport_changed := previous_viewport != viewport_size
	if viewport_changed:
		map_camera.viewport_changed(previous_viewport, viewport_size, previous_map_rect, _map_content_rect(viewport_size))
	var is_landscape := viewport_size.x > viewport_size.y
	var is_desktop := viewport_size.x >= 1024.0 and viewport_size.y >= 600.0
	ui_layout_scale = 1.0
	if is_landscape and not is_desktop:
		# Godot's portrait canvas scale is based on the short landscape height.
		# Compensate UI geometry and offsets so touch targets stay CSS-sized.
		ui_layout_scale = clampf(844.0 / viewport_size.y, 1.0, 2.2)
	ui_scale = clampf(minf(viewport_size.x / 390.0, viewport_size.y / 844.0), 1.0, 1.15)
	if is_landscape and not is_desktop:
		ui_scale = ui_layout_scale
	safe_insets = _read_safe_insets()
	for speed_button in speed_buttons.values():
		speed_button.add_theme_font_size_override("font_size", int(round(14.0 * ui_scale)))
	for map_control in map_controls.get_children():
		map_control.add_theme_font_size_override("font_size", int(round((13.0 if map_control.text in ["Center", "Fit", "Follow"] else 20.0) * ui_scale)))
	if is_instance_valid(follow_rider_button):
		follow_rider_button.text = "Stop" if map_camera.follow_enabled else "Follow"
		follow_rider_button.tooltip_text = "Exit rider follow mode" if map_camera.follow_enabled else "Follow selected delivery partner"
	for nav_button in nav_buttons.values():
		nav_button.add_theme_font_size_override("font_size", int(round(14.0 * ui_scale)))
	brand_label.add_theme_font_size_override("font_size", int(round(19.0 * ui_scale)))
	active_jobs_label.add_theme_font_size_override("font_size", int(round(12.0 * ui_scale)))
	pending_jobs_label.add_theme_font_size_override("font_size", int(round(11.0 * ui_scale)))
	cash_label.add_theme_font_size_override("font_size", int(round(16.0 * ui_scale)))
	available_label.add_theme_font_size_override("font_size", int(round(9.0 * ui_scale)))
	status_label.add_theme_font_size_override("font_size", int(round(13.0 * ui_scale)))
	pause_button.add_theme_font_size_override("font_size", int(round(13.0 * ui_scale)))
	_update_sim_controls()
	var sim_row := sim_controls.get_child(0) as HBoxContainer
	if sim_row != null:
		sim_row.add_theme_constant_override("separation", int(round(4.0 * ui_layout_scale)))
	var nav_row := bottom_nav.get_child(0) as HBoxContainer
	if nav_row != null:
		nav_row.add_theme_constant_override("separation", int(round(5.0 * ui_layout_scale)))
	var selected := _find_order(selected_order)
	var order_detail_open: bool = selected_tab == "Map" and not selected.is_empty() and (selected["status"] == "Waiting" or str(selected["status"]).begins_with("On route"))
	var nav_height: int = 76 if not is_landscape else 64
	var sheet_height: int = 268 if sheet_expanded else 124
	if is_landscape:
		sheet_height = 218 if sheet_expanded else 116
	if is_desktop:
		sheet_height = 268 if sheet_expanded else 124
	var safe_left := safe_insets.x
	var safe_top := safe_insets.y
	var safe_right := safe_insets.z
	var safe_bottom := safe_insets.w

	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.offset_left = safe_left + 12 * ui_layout_scale
	hud.offset_top = safe_top + 8 * ui_layout_scale
	hud.offset_right = -safe_right - 12 * ui_layout_scale
	hud.offset_bottom = safe_top + 64 * ui_layout_scale
	sim_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	sim_controls.offset_left = safe_left + 12 * ui_layout_scale
	sim_controls.offset_top = safe_top + 72 * ui_layout_scale
	sim_controls.offset_right = safe_left + 306 * ui_layout_scale
	sim_controls.offset_bottom = safe_top + 134 * ui_layout_scale
	pause_button.custom_minimum_size = Vector2(60, 46) * ui_layout_scale
	for speed_button in speed_buttons.values():
		speed_button.custom_minimum_size = Vector2(42, 46) * ui_layout_scale

	# The compact landscape sheet sits over the right side of the map. Keep
	# zoom/recenter controls on the left in both compact and expanded states.
	var controls_on_left := is_landscape
	map_controls.columns = 2 if is_landscape else 1
	map_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT if controls_on_left else Control.PRESET_TOP_RIGHT)
	map_controls.offset_left = safe_left + 12 * ui_layout_scale if controls_on_left else -safe_right - 78 * ui_layout_scale
	map_controls.offset_right = safe_left + 150 * ui_layout_scale if controls_on_left else -safe_right - 12 * ui_layout_scale
	map_controls.offset_top = safe_top + 142 * ui_layout_scale
	map_controls.offset_bottom = safe_top + 302 * ui_layout_scale
	for index in range(map_controls.get_child_count()):
		var map_control: Button = map_controls.get_child(index)
		map_control.custom_minimum_size = Vector2(66, 48) * ui_layout_scale

	bottom_nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	if is_desktop:
		var nav_width := 480.0 * ui_layout_scale
		bottom_nav.offset_left = maxf(safe_left + 12 * ui_layout_scale, (viewport_size.x - nav_width) * 0.5)
		bottom_nav.offset_right = -maxf(safe_right + 12 * ui_layout_scale, (viewport_size.x - nav_width) * 0.5)
	else:
		bottom_nav.offset_left = safe_left + 8 * ui_layout_scale
		bottom_nav.offset_right = -safe_right - 8 * ui_layout_scale
	bottom_nav.offset_top = -safe_bottom - nav_height * ui_layout_scale
	bottom_nav.offset_bottom = -safe_bottom
	for nav_button in nav_buttons.values():
		nav_button.custom_minimum_size.y = 56 * ui_layout_scale

	if is_desktop or is_landscape:
		sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		sheet.offset_left = -366 * ui_layout_scale
		sheet.offset_right = -safe_right - 12 * ui_layout_scale
		sheet.offset_top = -safe_bottom - (nav_height + 8 + sheet_height) * ui_layout_scale
		sheet.offset_bottom = -safe_bottom - (nav_height + 8) * ui_layout_scale
	else:
		sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		sheet.offset_left = safe_left + 10 * ui_layout_scale
		sheet.offset_right = -safe_right - 10 * ui_layout_scale
		sheet.offset_top = -safe_bottom - (nav_height + 8 + sheet_height) * ui_layout_scale
		sheet.offset_bottom = -safe_bottom - (nav_height + 8) * ui_layout_scale

	if is_instance_valid(sheet_toggle_button):
		sheet_toggle_button.text = "Hide" if sheet_expanded else "Expand"
		sheet_toggle_button.add_theme_font_size_override("font_size", int(round(15.0 * ui_scale)))
	if is_instance_valid(sheet_header_label):
		sheet_header_label.text = _sheet_title()
	sheet_content.add_theme_constant_override("separation", 3 if is_landscape and sheet_expanded else 6)
	if sheet_content.get_child_count() > 0:
			sheet_content.get_child(0).custom_minimum_size.y = (8 if is_landscape and sheet_expanded else 10) * ui_layout_scale
	if is_instance_valid(sheet_toggle_button):
		sheet_toggle_button.custom_minimum_size = Vector2(76, 40 if is_landscape and sheet_expanded else 44) * ui_layout_scale
	if is_instance_valid(order_list):
		order_list.add_theme_constant_override("separation", 3 if sheet_expanded else 0)
		var subtabs: HBoxContainer = sheet_content.find_child("Subtabs", true, false)
		if is_instance_valid(subtabs):
			# Keep the dispatch action above the bottom navigation on short screens.
			# City/World navigation remains available again when the order card closes.
			subtabs.visible = sheet_expanded and not order_detail_open
			for subtab in subtabs.get_children():
				subtab.custom_minimum_size.y = (40 if is_landscape and sheet_expanded else 46) * ui_layout_scale
		order_list.visible = sheet_expanded or selected_tab == "Map"
		if not sheet_expanded and selected_tab == "Map":
			for child in order_list.get_children():
				child.visible = false
			if order_list.get_child_count() > 0:
				order_list.get_child(0).visible = true
	if is_instance_valid(status_label):
		var active_map_order: bool = selected_tab == "Map" and not selected.is_empty() and (selected["status"] == "Waiting" or str(selected["status"]).begins_with("On route"))
		status_label.visible = status_label.text != "" and (sheet_expanded or selected_tab == "Map") and not active_map_order
	for tab in nav_buttons:
		var nav_button: Button = nav_buttons[tab]
		var selected_button: bool = tab == selected_tab
		nav_button.modulate = Color("#3bd5e8") if selected_button else Color("#dbe7ef")
	map_view.queue_redraw()
	_sync_map_input_blockers()
	if viewport_changed:
		call_deferred("_refresh")

func _ui_size(value: float) -> float:
	return value * ui_layout_scale

func _read_safe_insets() -> Vector4:
	return safe_insets

func _query_safe_insets() -> Vector4:
	var insets := Vector4(8, 8, 8, 16)
	if Engine.has_singleton("JavaScriptBridge"):
		var bridge: Object = Engine.get_singleton("JavaScriptBridge")
		if bridge != null:
			insets.x = maxf(insets.x, _safe_value(bridge, "left"))
			insets.y = maxf(insets.y, _safe_value(bridge, "top"))
			insets.z = maxf(insets.z, _safe_value(bridge, "right"))
			insets.w = maxf(insets.w, _safe_value(bridge, "bottom"))
	return insets

func _update_safe_area(delta: float) -> void:
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	safe_area_refresh_elapsed += delta
	if safe_area_refresh_elapsed < 0.5:
		return
	safe_area_refresh_elapsed = 0.0
	var queried := _query_safe_insets()
	if queried != safe_insets:
		safe_insets = queried
		call_deferred("_layout_ui")

func _maplibre_call(expression: String) -> Variant:
	if not Engine.has_singleton("JavaScriptBridge"):
		return null
	var bridge: Object = Engine.get_singleton("JavaScriptBridge")
	if bridge == null:
		return null
	return bridge.call("eval", expression, true)

func _maplibre_ready() -> bool:
	return _javascript_truth(_maplibre_call("Boolean(window.IDMMap && window.IDMMap.isReady())"))

func _javascript_truth(value: Variant) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	return str(value).to_lower() in ["true", "1"]

func _maplibre_active() -> bool:
	return geographic_map_available and not legacy_map_mode and maplibre_initialized

func _browser_camera_snapshot() -> Dictionary:
	var raw: Variant = _maplibre_call("window.IDMMap ? JSON.stringify(window.IDMMap.getCamera()) : ''")
	if not raw is String or raw.is_empty():
		return {}
	var parsed := JSON.new()
	if parsed.parse(raw) != OK or typeof(parsed.data) != TYPE_DICTIONARY:
		return {}
	return parsed.data

func _update_browser_map(delta: float) -> void:
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	var ready := _maplibre_ready()
	if not ready:
		return
	if not maplibre_initialized:
		_maplibre_call("window.IDMMap.setTheme(%s)" % JSON.stringify(ThemeService.mode))
		if geographic_map_available and not legacy_map_mode:
			var center := [DEFAULT_CITY_CENTER.x, DEFAULT_CITY_CENTER.y]
			var target_zoom := DEFAULT_CITY_ZOOM
			if pending_map_camera.has("center") and pending_map_camera["center"] is Array and pending_map_camera["center"].size() >= 2:
				center = pending_map_camera["center"]
				target_zoom = float(pending_map_camera.get("zoom", DEFAULT_CITY_ZOOM))
			elif not last_city_camera.is_empty():
				center = last_city_camera.get("center", center)
				target_zoom = float(last_city_camera.get("zoom", target_zoom))
			_maplibre_call("window.IDMMap.setVisible(true)")
			_maplibre_call("window.IDMMap.setView(%s, %s, 0)" % [JSON.stringify(center), JSON.stringify(target_zoom)])
		else:
			_maplibre_call("window.IDMMap.setVisible(false)")
		maplibre_initialized = true
		pending_map_camera.clear()
	if not geographic_map_available or legacy_map_mode:
		_maplibre_call("window.IDMMap.setVisible(false)")
		return
	_maplibre_call("window.IDMMap.setVisible(true)")
	map_camera_sync_elapsed += delta
	if map_camera_sync_elapsed < 0.10 and not map_camera.follow_enabled:
		return
	map_camera_sync_elapsed = 0.0
	if map_camera.follow_enabled and followed_rider_id >= 0:
		var camera := _browser_camera_snapshot()
		if not camera.is_empty():
			browser_map_state = camera
			map_camera.follow_enabled = _javascript_truth(_maplibre_call("Boolean(window.IDMMap.isFollowing())"))
			if not map_camera.follow_enabled:
				followed_rider_id = -1
				_update_follow_button()
	else:
		browser_map_state = _browser_camera_snapshot()
		if not browser_map_state.is_empty():
			last_city_camera = browser_map_state.duplicate(true)
	map_view.queue_redraw()

func _screen_for_uv(uv: Vector2) -> Vector2:
	return map_camera.world_to_screen(uv, _map_content_rect(map_view.size))

## Push simulation-owned geographic coordinates to MapLibre. MapLibre owns
## projection and camera transforms; Godot never paints map-world overlays in
## screen coordinates while the geographic map is active.
func _sync_geographic_overlays() -> void:
	if not _maplibre_active() or not _maplibre_ready():
		return
	if not _javascript_truth(_maplibre_call("Boolean(window.IDMMap && window.IDMMap.setGameplayOverlays && window.IDMMap.setRiderPositions)")):
		return
	var selected := _find_order(selected_order)
	var signature_data: Array = [selected_order]
	for order in orders:
		signature_data.append([
			int(order.get("id", -1)), str(order.get("status", "")),
			str(order.get("service_type", "parcel_logistics")),
			Vector2(order.get("pickup", Vector2.ZERO)), Vector2(order.get("destination", Vector2.ZERO)),
		])
	var static_signature := JSON.stringify(signature_data)
	var rider_features: Array[Dictionary] = []
	for rider in riders:
		var rider_uv: Vector2 = rider.get("position", Vector2.ZERO)
		var rider_geo := geographic_service.uv_to_geo(rider_uv)
		var rider_id := int(rider.get("id", -1))
		rider_features.append({
			"id": "rider-%d" % rider_id,
			"kind": "rider_active" if str(rider.get("status", "ready")) == "busy" else "rider_available",
			"label": "R",
			"status": str(rider.get("status", "ready")),
			"selected": not selected.is_empty() and int(selected.get("rider", -1)) == rider_id,
			"coordinates": [rider_geo.x, rider_geo.y],
		})
	if static_signature == geographic_static_overlay_signature:
		# Rider positions change every simulation frame; keep those updates small
		# and synchronous while leaving road geometry in MapLibre's GeoJSON source.
		_maplibre_call("window.IDMMap.setRiderPositions(%s)" % JSON.stringify(rider_features))
		return
	var route_features: Array[Dictionary] = []
	var marker_features: Array[Dictionary] = []
	var selected_sim: IDMRouteSimulation
	if not selected.is_empty():
		selected_sim = route_simulations.get(int(selected.get("rider", -1)))
	if selected_sim != null and selected_sim.is_active():
		for phase_info in [
			{"id": "pickup", "route": selected_sim.pickup_route},
			{"id": "delivery", "route": selected_sim.dropoff_route},
		]:
			var coordinates: Array = []
			for point_value in phase_info["route"].get("points", []):
				var geo := geographic_service.uv_to_geo(Vector2(point_value))
				coordinates.append([geo.x, geo.y]) # GeoJSON is [longitude, latitude].
			if coordinates.size() >= 2:
				route_features.append({
					"id": "booking-%d-%s" % [int(selected["id"]), str(phase_info["id"])],
					"phase": str(phase_info["id"]),
					"selected": true,
					"coordinates": coordinates,
				})
	var selected_id := int(selected.get("id", -1)) if not selected.is_empty() else -1
	for order in orders:
		if str(order.get("status", "")) in ["Delivered", "Cancelled"]:
			continue
		var order_id := int(order.get("id", -1))
		var is_selected := order_id == selected_id
		var destination_uv: Vector2 = order.get("destination", Vector2.ZERO)
		var destination := geographic_service.uv_to_geo(destination_uv)
		var active := str(order.get("status", "")).begins_with("On route")
		marker_features.append({
			"id": "booking-%d-destination" % order_id,
			"kind": "destination" if active else _booking_marker_kind(str(order.get("service_type", "parcel_logistics"))),
			"label": "D" if active else IDMServicePricing.marker(str(order.get("service_type", "parcel_logistics"))),
			"service": str(order.get("service_type", "parcel_logistics")),
			"status": str(order.get("status", "Waiting")),
			"selected": is_selected,
			"bookingId": order_id,
			"coordinates": [destination.x, destination.y],
		})
		if is_selected:
			var pickup_uv: Vector2 = order.get("pickup", destination_uv)
			var pickup := geographic_service.uv_to_geo(pickup_uv)
			marker_features.append({
				"id": "booking-%d-pickup" % order_id,
				"kind": "pickup",
				"label": "P",
				"status": str(order.get("status", "Waiting")),
				"selected": true,
				"bookingId": order_id,
				"coordinates": [pickup.x, pickup.y],
			})
	marker_features.append_array(rider_features)
	var payload := {"routes": route_features, "markers": marker_features}
	_maplibre_call("window.IDMMap.setGameplayOverlays(%s)" % JSON.stringify(payload))
	geographic_static_overlay_signature = static_signature

func _booking_marker_kind(service_id: String) -> String:
	match service_id:
		"food_delivery": return "booking_food"
		"parcel_logistics": return "booking_parcel"
		"e_hailing": return "booking_passenger"
		"express_logistics": return "booking_express"
		_: return "booking_parcel"

func _sync_map_input_blockers() -> void:
	browser_block_rects.clear()
	for node in get_children():
		if node is Control and node != map_view and node.visible:
			var rect: Rect2 = node.get_global_rect()
			if rect.size.x > 0.0 and rect.size.y > 0.0:
				browser_block_rects.append({"x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y})
	browser_block_rects_dirty = true

func _flush_map_input_blockers() -> void:
	if not browser_block_rects_dirty or not Engine.has_singleton("JavaScriptBridge"):
		return
	_maplibre_call("window.IDMMap && window.IDMMap.setBlockRects(%s)" % JSON.stringify(browser_block_rects))
	browser_block_rects_dirty = false

func _safe_value(bridge: Object, side: String) -> float:
	var value: Variant = bridge.call("eval", "parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--idm-safe-" + side + "')) || 0", true)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return clampf(float(value), 0.0, 80.0)
	return 0.0

func _sheet_title() -> String:
	match selected_tab:
		"Map":
			var selected := _find_order(selected_order)
			if not selected.is_empty():
				var service := IDMServicePricing.short_label(str(selected.get("service_type", "parcel_logistics")))
				var state := str(selected.get("status", "Waiting")).to_upper()
				return "%s  ·  BOOKING %03d  ·  %s" % [service, int(selected.get("id", 0)), state]
			if sheet_expanded:
				return "KL + SELANGOR  ·  OPENSTREETMAP" if geographic_map_available and not legacy_map_mode else "PARCELS  ·  FICTIONAL CITY MAP"
			return "%d BOOKINGS WAITING  ·  TAP A PIN" % _waiting_count()
		"Operations": return "OPERATIONS  ·  " + selected_subtab.to_upper()
		"Finance": return "COMPANY FINANCES"
		_: return "SETTINGS  ·  " + selected_subtab.to_upper()

func _zoom_map(factor: float, screen_point: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if not is_instance_valid(map_view):
		return
	if _maplibre_active():
		var anchor := map_view.size * 0.5 if screen_point.x < 0.0 or screen_point.y < 0.0 else screen_point
		_maplibre_call("window.IDMMap.zoomBy(%s, [%s, %s], 200)" % [JSON.stringify(factor), JSON.stringify(anchor.x), JSON.stringify(anchor.y)])
		return
	var anchor := map_view.size * 0.5 if screen_point.x < 0.0 or screen_point.y < 0.0 else screen_point
	map_camera.zoom_at(factor, anchor, map_view.size)
	map_view.queue_redraw()

func _clamp_map_pan() -> void:
	map_camera.clamp_pan(map_view.size)

func _recenter_map() -> void:
	if _maplibre_active():
		_maplibre_call("window.IDMMap.setView(%s, %s, 350)" % [JSON.stringify([DEFAULT_CITY_CENTER.x, DEFAULT_CITY_CENTER.y]), JSON.stringify(DEFAULT_CITY_ZOOM)])
		map_camera.follow_enabled = false
		followed_rider_id = -1
		return
	map_camera.recenter()
	followed_rider_id = -1
	map_view.queue_redraw()

func _restore_city_camera() -> void:
	if _maplibre_active() and not last_city_camera.is_empty():
		var center: Array = last_city_camera.get("center", [DEFAULT_CITY_CENTER.x, DEFAULT_CITY_CENTER.y])
		_maplibre_call("window.IDMMap.setView(%s, %s, 450)" % [JSON.stringify(center), JSON.stringify(last_city_camera.get("zoom", DEFAULT_CITY_ZOOM))])
	else:
		_recenter_map()

func _toggle_follow(rider_id: int) -> void:
	if followed_rider_id == rider_id and map_camera.follow_enabled:
		map_camera.follow_enabled = false
		followed_rider_id = -1
		_maplibre_call("window.IDMMap.stopFollow()")
		status_label.text = "Follow camera off"
		_refresh()
		return
	var rider := _find_rider(rider_id)
	if rider.is_empty():
		return
	followed_rider_id = rider_id
	map_camera.set_follow(true, rider["position"], _map_content_rect(map_view.size), map_view.size)
	if _maplibre_active():
		var geo := geographic_service.uv_to_geo(rider["position"])
		_maplibre_call("window.IDMMap.setFollowTarget(%s, %s)" % [JSON.stringify(geo.x), JSON.stringify(geo.y)])
	status_label.text = "Following partner %02d · pan map to stop" % rider_id
	map_view.queue_redraw()
	_refresh()

func _find_rider(rider_id: int) -> Dictionary:
	for rider in riders:
		if int(rider.get("id", -1)) == rider_id:
			return rider
	return {}

func _toggle_world() -> void:
	world_map = not world_map
	selected_subtab = "World" if world_map else "City"
	map_mode = selected_subtab
	map_camera.zoom = 0.7 if world_map else 1.0
	map_camera.pan = Vector2.ZERO
	if _maplibre_active():
		if world_map:
			_maplibre_call("window.IDMMap.setView([102, 20], 2.5, 500)")
		else:
			_restore_city_camera()
	map_camera.follow_enabled = false
	followed_rider_id = -1
	status_label.text = "World overview" if world_map else "City map"
	_refresh()

func _set_subtab(name: String) -> void:
	selected_subtab = name
	sheet_expanded = true
	if selected_tab == "Map":
		map_mode = name
		world_map = name == "World"
		map_camera.zoom = 0.7 if world_map else 1.0
		map_camera.pan = Vector2.ZERO
		if _maplibre_active():
			if world_map:
				_maplibre_call("window.IDMMap.setView([102, 20], 2.5, 500)")
			else:
				_restore_city_camera()
		map_camera.follow_enabled = false
		followed_rider_id = -1
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
	if _maplibre_active():
		if event is InputEventScreenTouch:
			# Web browsers synthesize compatibility mouse events after touch. Do
			# not let one finger tap be interpreted a second time as a double-tap.
			last_touch_input_msec = Time.get_ticks_msec()
			if event.pressed:
				touch_points[event.index] = event.position
				if touch_points.size() == 1:
					gesture_start = event.position
					suppress_tap = false
				else:
					suppress_tap = true
					_stop_follow_for_manual_gesture()
			else:
				touch_points.erase(event.index)
				if touch_points.is_empty() and not suppress_tap and event.position.distance_to(gesture_start) < 12.0:
					_queue_map_tap(event.position)
				if touch_points.is_empty():
					suppress_tap = false
			if event.pressed and event.position.distance_to(gesture_start) > 12.0:
				suppress_tap = true
				_stop_follow_for_manual_gesture()
		elif event is InputEventScreenDrag:
			if event.position.distance_to(gesture_start) > 12.0:
				suppress_tap = true
				_stop_follow_for_manual_gesture()
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and Time.get_ticks_msec() - last_touch_input_msec < 700:
				return
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
				pending_tap = false
				pending_tap_generation += 1
				last_tap_msec = 0
				suppress_tap = true # Browser native dblclick is forwarded by the JS bridge.
			elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				gesture_start = event.position
				suppress_tap = false
			elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not suppress_tap and event.position.distance_to(gesture_start) < 12.0:
				_queue_map_tap(event.position)
			elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
				_stop_follow_for_manual_gesture()
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if event.position.distance_to(gesture_start) > 12.0:
				suppress_tap = true
				_stop_follow_for_manual_gesture()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index] = event.position
			if touch_points.size() == 1:
				gesture_start = event.position
				gesture_pan = map_camera.pan
				suppress_tap = false
			elif touch_points.size() == 2:
				var points: Array = touch_points.values()
				pinch_distance = Vector2(points[0]).distance_to(Vector2(points[1]))
				pinch_active = true
				suppress_tap = true
				_stop_follow_for_manual_gesture()
		else:
			touch_points.erase(event.index)
			if pinch_active:
				pinch_active = false
				pinch_distance = 0.0
				suppress_tap = true
			elif touch_points.is_empty() and not suppress_tap:
				var now := Time.get_ticks_msec()
				if now - last_tap_msec < 320:
					_zoom_map(1.4, event.position)
				else:
					_select_marker(event.position)
				last_tap_msec = now
			if touch_points.size() == 1:
				var remaining_point: Vector2 = touch_points.values()[0]
				gesture_start = remaining_point
				gesture_pan = map_camera.pan
				suppress_tap = true
	elif event is InputEventScreenDrag:
		if touch_points.has(event.index):
			touch_points[event.index] = event.position
		if touch_points.size() >= 2:
			var points: Array = touch_points.values()
			var new_distance := Vector2(points[0]).distance_to(Vector2(points[1]))
			var pinch_center := (Vector2(points[0]) + Vector2(points[1])) * 0.5
			if pinch_distance > 0.0 and new_distance > 0.0:
				_zoom_map(new_distance / pinch_distance, pinch_center)
			pinch_distance = new_distance
			pinch_active = true
			suppress_tap = true
		elif event.position.distance_to(gesture_start) > 8.0:
			suppress_tap = true
			_stop_follow_for_manual_gesture()
			map_camera.pan = gesture_pan + event.position - gesture_start
			_clamp_map_pan()
			map_view.queue_redraw()

func _queue_map_tap(point: Vector2) -> void:
	# Mobile Safari does not reliably synthesize dblclick for canvas touches.
	# The MapLibre bridge recognizes two stationary native touch taps and zooms
	# at their anchor; consume that result here to avoid selecting an order or
	# applying a second zoom on the second tap.
	if _javascript_truth(_maplibre_call("Boolean(window.IDMMap && window.IDMMap.consumeTouchDoubleTap())")):
		pending_tap = false
		pending_tap_generation += 1
		last_tap_msec = 0
		return
	var now := Time.get_ticks_msec()
	if now - last_tap_msec < 320:
		pending_tap = false
		pending_tap_generation += 1
		last_tap_msec = 0
		_maplibre_call("window.IDMMap.zoomBy(1.5, [%s, %s], 200)" % [JSON.stringify(point.x), JSON.stringify(point.y)])
		return
	last_tap_msec = now
	pending_tap = true
	pending_tap_point = point
	pending_tap_generation += 1
	var generation := pending_tap_generation
	get_tree().create_timer(0.32).timeout.connect(func():
		if pending_tap and generation == pending_tap_generation:
			pending_tap = false
			_select_marker(point)
	)

func _forward_map_input(event: InputEvent) -> void:
	var payload: Dictionary = {}
	if event is InputEventScreenTouch:
		payload = {"type": "screen_touch", "pressed": event.pressed, "index": event.index, "positionX": event.position.x, "positionY": event.position.y, "pointerType": "touch"}
	elif event is InputEventScreenDrag:
		payload = {"type": "screen_drag", "index": event.index, "positionX": event.position.x, "positionY": event.position.y, "pointerType": "touch"}
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			payload = {"type": "wheel", "clientX": event.position.x, "clientY": event.position.y, "deltaY": -120.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 120.0}
		elif event.button_index == MOUSE_BUTTON_LEFT:
			payload = {"type": "pointerdown" if event.pressed else "pointerup", "pointerId": 1, "pointerType": "mouse", "clientX": event.position.x, "clientY": event.position.y, "button": 0, "buttons": 1 if event.pressed else 0}
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			payload = {"type": "pointermove", "pointerId": 1, "pointerType": "mouse", "clientX": event.position.x, "clientY": event.position.y, "button": 0, "buttons": 1}
	if not payload.is_empty():
		_maplibre_call("window.IDMMap.forwardPointerEvent(%s)" % JSON.stringify(payload))
	elif event is InputEventMagnifyGesture:
		_zoom_map(event.factor, event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_zoom_map(1.4, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_map(1.15, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_map(0.87, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				gesture_start = event.position
				gesture_pan = map_camera.pan
				suppress_tap = false
			elif not suppress_tap:
				_select_marker(event.position)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if event.position.distance_to(gesture_start) > 8.0:
			suppress_tap = true
			_stop_follow_for_manual_gesture()
			map_camera.pan = gesture_pan + event.position - gesture_start
			_clamp_map_pan()
			map_view.queue_redraw()

func _stop_follow_for_manual_gesture() -> void:
	if map_camera.follow_enabled:
		map_camera.follow_enabled = false
		followed_rider_id = -1
		_maplibre_call("window.IDMMap && window.IDMMap.stopFollow()")
		_update_follow_button()

func _update_follow_button() -> void:
	if not is_instance_valid(follow_rider_button):
		return
	follow_rider_button.text = "Stop" if map_camera.follow_enabled else "Follow"
	follow_rider_button.tooltip_text = "Exit rider follow mode" if map_camera.follow_enabled else "Follow selected delivery partner"

func _select_marker(point: Vector2) -> void:
	if _maplibre_active():
		var raw: Variant = _maplibre_call("JSON.stringify(window.IDMMap.pickBookingAt(%s, %s) || null)" % [JSON.stringify(point.x), JSON.stringify(point.y)])
		if not raw is String or raw in ["", "null", "<null>"]:
			return
		var parsed := JSON.new()
		if parsed.parse(raw) != OK or typeof(parsed.data) != TYPE_DICTIONARY:
			return
		var booking_id := int(parsed.data.get("bookingId", -1))
		var booking := _find_order(booking_id)
		if booking.is_empty() or str(booking.get("status", "")) != "Waiting":
			return
		selected_order = booking_id
		sheet_expanded = true
		status_label.text = ""
		_refresh()
		return
	var map_rect := _map_content_rect(map_view.size)
	for order in orders:
		if order["status"] == "Waiting":
			var screen_destination := _screen_for_uv(order["destination"])
			if point.distance_to(screen_destination) < 30:
				selected_order = order["id"]
				sheet_expanded = true
				_refresh()
				return

func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = _ui_size(46)
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
	_maplibre_call("window.IDMMap && window.IDMMap.setTheme(%s)" % JSON.stringify(ThemeService.mode))
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
	var pickup := Vector2.ZERO
	var destination := Vector2.ZERO
	var dropoff_route: Dictionary = {}
	if geographic_map_available and not legacy_map_mode:
		if not road_network_available:
			status_label.text = road_router.last_error if road_router.last_error != "" else "Road routing data is unavailable"
			return
		for attempt in 20:
			pickup = road_router.random_location_for_view(viewport_size)
			destination = _random_order_location(viewport_size)
			if destination.x < 0.0:
				continue
			if pickup.distance_to(destination) < 0.025:
				continue
			dropoff_route = road_router.route_between_uv(pickup, destination)
			if dropoff_route.get("ok", false) and _has_reachable_partner(pickup):
				break
		if not dropoff_route.get("ok", false) or not _has_reachable_partner(pickup):
			status_label.text = "No connected road job is available in this area yet"
			return
	else:
		pickup = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		destination = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
	var duplicate_point := false
	for existing in orders:
		if existing["status"] != "Delivered" and destination.distance_to(existing["destination"]) < 0.06:
			duplicate_point = true
			break
	if duplicate_point and geographic_map_available and not legacy_map_mode:
		for attempt in 20:
			pickup = road_router.random_location_for_view(viewport_size)
			destination = _random_order_location(viewport_size)
			if destination.x < 0.0:
				continue
			if pickup.distance_to(destination) >= 0.025:
				dropoff_route = road_router.route_between_uv(pickup, destination)
				if dropoff_route.get("ok", false) and _has_reachable_partner(pickup):
					duplicate_point = false
					for existing in orders:
						if existing["status"] != "Delivered" and destination.distance_to(existing["destination"]) < 0.06:
							duplicate_point = true
							break
					if not duplicate_point:
						break
	if duplicate_point:
		return
	var service_id: String = IDMServicePricing.service_ids().pick_random()
	var route_distance_km := float(dropoff_route.get("distance_km", 0.0))
	var route_eta_seconds := float(dropoff_route.get("estimated_time_seconds", 0.0))
	var price_quote := IDMServicePricing.quote(service_id, route_distance_km, route_eta_seconds)
	var estimated_fare := float(price_quote.get("total_rm", randi_range(55, 105)))
	var order := {
		"id": next_order_id,
		"service_type": service_id,
		"price_quote": price_quote,
		"pickup": pickup,
		"destination": destination,
		"pickup_latitude": geographic_service.uv_to_geo(pickup).y if geographic_map_available and not legacy_map_mode else null,
		"pickup_longitude": geographic_service.uv_to_geo(pickup).x if geographic_map_available and not legacy_map_mode else null,
		"destination_latitude": geographic_service.uv_to_geo(destination).y if geographic_map_available and not legacy_map_mode else null,
		"destination_longitude": geographic_service.uv_to_geo(destination).x if geographic_map_available and not legacy_map_mode else null,
		"coordinate_reference": "EPSG:4326" if geographic_map_available and not legacy_map_mode else "legacy_normalized",
		"payout": estimated_fare,
		"status": "Waiting",
		"rider": -1,
		"route_distance_km": route_distance_km,
		"route_eta_seconds": route_eta_seconds,
	}
	orders.append(order)
	next_order_id += 1
	_save_game()
	_refresh()

func _random_order_location(view_size: Vector2) -> Vector2:
	# Keep new booking pins clear of the HUD, simulation buttons, compact map
	# panels, map controls, and bottom navigation. In landscape the panel is at
	# the right, so jobs remain visible and tappable on the map's left side.
	for _attempt in 128:
		var candidate := road_router.random_location_for_view(view_size)
		if candidate.x < 0.0:
			return candidate
		var point := map_camera.world_to_screen(candidate, _map_content_rect(view_size))
		if point.x < 24.0 or point.x > view_size.x - 24.0 or point.y < 72.0 or point.y > view_size.y - 84.0:
			continue
		if point.y < 144.0 and point.x < 320.0:
			continue
		if view_size.x > view_size.y:
			if point.x < 104.0 and point.y >= 144.0 and point.y <= 312.0:
				continue
			var sheet_top := 84.0 if sheet_expanded else view_size.y - 256.0
			if point.x >= view_size.x - 378.0 and point.y >= sheet_top:
				continue
		else:
			if point.x >= view_size.x - 96.0 and point.y >= 136.0 and point.y <= 304.0:
				continue
			var portrait_sheet_height := 354.0 if sheet_expanded else 244.0
			if point.y >= view_size.y - portrait_sheet_height:
				continue
		return candidate
	return Vector2(-1.0, -1.0)

func _has_reachable_partner(pickup_uv: Vector2) -> bool:
	for partner in riders:
		if partner.get("status", "") != "ready":
			continue
		var candidate := road_router.route_between_uv(partner["position"], pickup_uv)
		if candidate.get("ok", false):
			return true
	return false

func _dispatch(order_id: int) -> void:
	var order := _find_order(order_id)
	if order.is_empty() or order.get("status", "") != "Waiting":
		return
	var available := -1
	var simulation: IDMRouteSimulation
	if geographic_map_available and not legacy_map_mode:
		if not road_network_available:
			status_label.text = road_router.last_error if road_router.last_error != "" else "Road routes unavailable; dispatch was not started"
			return
		var pickup_uv: Vector2 = _as_vector2(order.get("pickup", ""), order["destination"])
		var destination_uv: Vector2 = order["destination"]
		var dropoff_route := road_router.route_between_uv(pickup_uv, destination_uv)
		if not dropoff_route.get("ok", false):
			status_label.text = "Delivery route failed: %s" % dropoff_route.get("error", "unreachable road")
			return
		var pickup_error := "No ready partner can reach this pickup by road."
		for index in riders.size():
			if riders[index].get("status", "") != "ready":
				continue
			var candidate_pickup := road_router.route_between_uv(riders[index]["position"], pickup_uv)
			if not candidate_pickup.get("ok", false):
				pickup_error = str(candidate_pickup.get("error", pickup_error))
				continue
			var candidate_simulation := IDMRouteSimulation.new()
			if not candidate_simulation.initialize(candidate_pickup, dropoff_route, 25.0):
				pickup_error = candidate_simulation.error_message
				continue
			available = index
			simulation = candidate_simulation
			break
		if available < 0 or simulation == null:
			status_label.text = "Dispatch unavailable: %s" % pickup_error
			return
	else:
		for index in riders.size():
			if riders[index].get("status", "") == "ready":
				available = index
				break
		if available < 0:
			status_label.text = "No partner available"
			return
	var rider: Dictionary = riders[available]
	var rider_id := int(rider["id"])
	if simulation != null:
		route_simulations[rider_id] = simulation
		rider["route_state"] = simulation.to_save()
		rider["position"] = simulation.current_uv
		rider["remaining"] = simulation.estimated_remaining_seconds(float(speed))
		order["route_distance_km"] = simulation.total_distance_km()
		order["route_eta_seconds"] = simulation.estimated_remaining_seconds(float(speed))
		order["status"] = "On route to pickup"
		status_label.text = "Partner %02d dispatched · %.1f km road route" % [rider_id, simulation.total_distance_km()]
	else:
		# Preserve old prototype trips only inside legacy saves and their fictional coordinate space.
		rider["remaining"] = TRAVEL_SECONDS
		order["origin"] = rider["position"]
		order["status"] = "On route"
		status_label.text = "Rider %02d dispatched on legacy route" % rider_id
	rider["status"] = "busy"
	rider["order_id"] = order_id
	order["rider"] = rider_id
	selected_order = order_id
	_save_game()
	_refresh()

func _finish_delivery(rider: Dictionary) -> void:
	var order := _find_order(rider["order_id"])
	if order.is_empty() or order.get("status", "") == "Delivered":
		rider["status"] = "ready"
		rider["order_id"] = -1
		route_simulations.erase(int(rider.get("id", -1)))
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
	rider.erase("route_state")
	rider["position"] = order["destination"]
	route_simulations.erase(int(rider.get("id", -1)))
	status_label.text = "Delivered  +RM%.2f  ·  cost RM%.2f" % [payout, operating_cost]
	# Return control to the map after a completed stop; keep the outcome visible in the compact sheet.
	sheet_expanded = false
	_save_game()
	_refresh()

func _hire_rider() -> void:
	if cash < 120:
		status_label.text = "Need RM120 to recruit partner"
		return
	cash -= 120
	var new_position := road_router.random_location_for_view(get_viewport_rect().size) if geographic_map_available and not legacy_map_mode and road_network_available else Vector2(0.5, 0.5)
	if geographic_map_available and not legacy_map_mode and (not road_network_available or new_position.x < 0.0):
		cash += 120
		status_label.text = "No connected road recruitment location is available"
		return
	riders.append({"id": next_rider_id, "status": "ready", "order_id": -1, "remaining": 0.0, "position": new_position})
	next_rider_id += 1
	status_label.text = "Rider hired and ready"
	_save_game()
	_refresh()

func _toggle_pause() -> void:
	paused = not paused
	pause_button.text = "Resume" if paused else "Pause"
	status_label.text = "Simulation paused" if paused else "Operations resumed"
	_update_sim_controls()
	_save_game()

func _set_speed(value: int) -> void:
	speed = value
	status_label.text = "Simulation speed: %d×" % speed
	_update_sim_controls()
	_save_game()

func _update_sim_controls() -> void:
	if is_instance_valid(available_label):
		available_label.text = "%d×  ·  %s" % [speed, "PAUSED" if paused else "LIVE"]
	if is_instance_valid(pause_button):
		pause_button.text = "Resume" if paused else "Pause"
	for factor in speed_buttons:
		var button: Button = speed_buttons[factor]
		button.modulate = Color("#57d9e8") if int(factor) == speed else Color.WHITE
		button.tooltip_text = "Current speed %d times" % int(factor) if int(factor) == speed else "Set simulation speed to %d times" % int(factor)

func _find_order(order_id: int) -> Dictionary:
	for order in orders:
		if order["id"] == order_id:
			return order
	return {}

func _fit_selected_booking() -> void:
	if not _maplibre_active():
		status_label.text = "Route fitting is available on the geographic map."
		return
	var selected := _find_order(selected_order)
	if selected.is_empty():
		status_label.text = "Select a booking to fit its route."
		_refresh()
		return
	var route_points: Array = []
	var simulation: IDMRouteSimulation = route_simulations.get(int(selected.get("rider", -1)))
	if simulation != null and simulation.is_active():
		for route in [simulation.pickup_route, simulation.dropoff_route]:
			for uv_value in route.get("points", []):
				var geo := geographic_service.uv_to_geo(Vector2(uv_value))
				route_points.append([geo.x, geo.y])
	else:
		var pickup: Vector2 = selected.get("pickup", Vector2.ZERO)
		var destination: Vector2 = selected.get("destination", Vector2.ZERO)
		var route := road_router.route_between_uv(pickup, destination)
		if route.get("ok", false):
			for uv_value in route.get("points", []):
				var geo := geographic_service.uv_to_geo(Vector2(uv_value))
				route_points.append([geo.x, geo.y])
	if route_points.size() >= 2:
		_maplibre_call("window.IDMMap.fitRoute(%s, 500)" % JSON.stringify(route_points))
	else:
		status_label.text = "No connected road route is available for this booking."
		_refresh()

func _follow_selected_rider() -> void:
	if map_camera.follow_enabled and followed_rider_id >= 0:
		_toggle_follow(followed_rider_id)
		return
	var selected := _find_order(selected_order)
	if selected.is_empty() or not str(selected.get("status", "")).begins_with("On route"):
		status_label.text = "Select an active delivery to follow its partner."
		_refresh()
		return
	_toggle_follow(int(selected.get("rider", -1)))

func _refresh() -> void:
	if not is_instance_valid(order_list):
		return
	cash_label.text = "RM%0.2f" % cash
	active_jobs_label.text = "ACTIVE  %d" % _busy_count()
	pending_jobs_label.text = "ORDERS  %d" % _waiting_count()
	_update_sim_controls()
	if selected_tab == "Map" and status_label.text == "" and _find_order(selected_order).is_empty():
		status_label.text = "Tap a booking pin to review and dispatch."
	for child in order_list.get_children():
		child.queue_free()
	_sync_geographic_overlays()
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
			subtab.custom_minimum_size = Vector2(0, _ui_size(46))
			if option == selected_subtab:
				subtab.modulate = Color("#43d6e8")
			subtabs.add_child(subtab)
	match selected_tab:
		"Map":
			var selected := _find_order(selected_order)
			if not selected.is_empty() and selected["status"] == "Waiting":
				var eta_minutes := int(ceil(float(selected.get("route_eta_seconds", 0.0)) / 60.0))
				var service_name := IDMServicePricing.short_label(str(selected.get("service_type", "parcel_logistics")))
				var compact_eta := "  ·  ~%d min" % eta_minutes if eta_minutes > 0 else ""
				order_list.add_child(_label("%s  ·  WAITING  ·  RM%.2f%s" % [service_name, float(selected.get("payout", 0.0)), compact_eta], 11, "#a8bac8"))
				if sheet_expanded:
					var pickup_uv: Vector2 = selected.get("pickup", Vector2.ZERO)
					var destination_uv: Vector2 = selected.get("destination", Vector2.ZERO)
					var pickup_geo := geographic_service.uv_to_geo(pickup_uv)
					var destination_geo := geographic_service.uv_to_geo(destination_uv)
					order_list.add_child(_label("Pickup  %.5f, %.5f" % [pickup_geo.y, pickup_geo.x], 10, "#a8bac8"))
					order_list.add_child(_label("Drop-off  %.5f, %.5f" % [destination_geo.y, destination_geo.x], 10, "#a8bac8"))
					if float(selected.get("route_distance_km", 0.0)) > 0.0:
						order_list.add_child(_label("Road  %.1f km  ·  ETA  ~%d min" % [float(selected["route_distance_km"]), eta_minutes], 10, "#a8bac8"))
				var quote: Dictionary = selected.get("price_quote", {})
				if sheet_expanded and not quote.is_empty():
					order_list.add_child(_label("Fare RM%.2f  ·  base %.2f + distance %.2f + time %.2f" % [float(selected["payout"]), float(quote.get("base_rm", 0.0)), float(quote.get("distance_rm", 0.0)), float(quote.get("time_rm", 0.0))], 10, "#c4d3dd"))
				elif sheet_expanded:
					order_list.add_child(_label("Estimated fare RM%.2f" % float(selected["payout"]), 12, "#c4d3dd"))
				var dispatch := _button("Dispatch rider", func(): _dispatch(selected["id"]))
				dispatch.custom_minimum_size.y = _ui_size(46)
				dispatch.add_theme_color_override("font_color", Color("#04252d"))
				var dispatch_style := StyleBoxFlat.new()
				dispatch_style.bg_color = Color("#48d9e9")
				dispatch_style.set_corner_radius_all(15)
				dispatch.add_theme_stylebox_override("normal", dispatch_style)
				order_list.add_child(dispatch)
			elif not selected.is_empty() and str(selected["status"]).begins_with("On route"):
				var route_service := IDMServicePricing.short_label(str(selected.get("service_type", "parcel_logistics")))
				var route_state := str(selected["status"]).to_upper()
				order_list.add_child(_label("%s  ·  %s" % [route_service, route_state], 12, "#a8bac8"))
				var route_rider_id := int(selected.get("rider", -1))
				var route_sim: IDMRouteSimulation = route_simulations.get(route_rider_id)
				if route_sim != null and route_sim.is_active():
					var eta := route_sim.estimated_remaining_seconds(float(speed))
					var eta_text := "ETA paused" if paused or eta < 0.0 else "ETA %d min" % int(ceil(eta / 60.0))
					order_list.add_child(_label("%.1f km  ·  %.1f km remaining  ·  %s" % [route_sim.total_distance_km(), route_sim.remaining_distance_km(), eta_text], 11, "#a8bac8"))
				else:
					order_list.add_child(_label("The road route is being restored.", 13, "#a8bac8"))
			else:
				var waiting_count := _waiting_count()
				var hint := _label("%d waiting  ·  tap a pin" % waiting_count if waiting_count > 0 else "Tap a booking pin to review", 12, "#f1f6fa")
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
				hire.custom_minimum_size.y = _ui_size(50)
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
				theme_button.custom_minimum_size.y = _ui_size(50)
				order_list.add_child(theme_button)
			else:
				order_list.add_child(_label("LEGACY · FICTIONAL MAP · PRESERVED" if legacy_map_mode else "GEOGRAPHIC · KL / SELANGOR", 12, "#f1f6fa"))
				var continue_button := _button("Continue Game", _continue_game)
				continue_button.custom_minimum_size.y = _ui_size(46)
				order_list.add_child(continue_button)
				var save_actions := HBoxContainer.new()
				save_actions.add_theme_constant_override("separation", 6)
				order_list.add_child(save_actions)
				var load_button := _button("Load Game", _show_load_game)
				load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				load_button.custom_minimum_size.y = _ui_size(46)
				save_actions.add_child(load_button)
				var new_game_button := _button("New Game", _confirm_new_game)
				new_game_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				new_game_button.custom_minimum_size.y = _ui_size(46)
				save_actions.add_child(new_game_button)
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

func _continue_game() -> void:
	_close_save_overlay()
	selected_tab = "Map"
	selected_subtab = "City" if not world_map else "World"
	sheet_expanded = false
	status_label.text = "Continuing legacy fictional-map save" if legacy_map_mode else "Continuing KL / Selangor geographic game"
	_refresh()

func _confirm_new_game() -> void:
	if not geographic_map_available or not road_network_available:
		status_label.text = "New geographic games are unavailable because KL road data did not load. Your save is unchanged."
		return
	_close_new_game_confirmation()
	new_game_confirmation = ColorRect.new()
	new_game_confirmation.color = Color(0.008, 0.025, 0.04, 0.84)
	new_game_confirmation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	new_game_confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
	new_game_confirmation.name = "NewGameConfirmation"
	add_child(new_game_confirmation)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	new_game_confirmation.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(minf(350.0, viewport_size.x - 24.0), 0)
	card.add_theme_stylebox_override("panel", _panel_style("#102433", 20))
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	column.add_child(_label("START A NEW GAME?", 18, "#f1f6fa"))
	var message := _label("A separate real KL / Selangor game will be created. Your current progress, including the legacy fictional-map save, will remain saved and available under Load Game.", 14, "#a8bac8")
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(message)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	var cancel_button := _button("Cancel", _close_new_game_confirmation)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.custom_minimum_size.y = 50
	actions.add_child(cancel_button)
	var start_button := _button("Start New Game", _start_new_geographic_game)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.custom_minimum_size.y = 50
	start_button.add_theme_color_override("font_color", Color("#04252d"))
	var start_style := StyleBoxFlat.new()
	start_style.bg_color = Color("#48d9e9")
	start_style.set_corner_radius_all(14)
	start_button.add_theme_stylebox_override("normal", start_style)
	actions.add_child(start_button)

func _close_new_game_confirmation() -> void:
	if is_instance_valid(new_game_confirmation):
		new_game_confirmation.queue_free()
	new_game_confirmation = null

func _start_new_geographic_game() -> void:
	if not geographic_map_available or not road_network_available:
		return
	_save_game()
	_register_current_save_profile()
	var session_path := "%s%d_%06d.json" % [SAVE_SESSION_PREFIX, int(Time.get_unix_time_from_system()), randi_range(0, 999999)]
	while FileAccess.file_exists(session_path) or _web_save_mirror_exists(session_path):
		session_path = "%s%d_%06d.json" % [SAVE_SESSION_PREFIX, int(Time.get_unix_time_from_system()), randi_range(0, 999999)]
	save_path = session_path
	_set_active_save_path(save_path)
	selected_tab = "Map"
	selected_subtab = "City"
	sheet_expanded = false
	world_map = false
	_new_game()
	for _index in 2:
		_spawn_order()
	_register_current_save_profile()
	_close_save_overlay()
	_close_new_game_confirmation()
	status_label.text = "New geographic game · real KL / Selangor roads"
	_refresh()

func _show_load_game() -> void:
	_save_game()
	_register_current_save_profile()
	_close_save_overlay()
	save_overlay = ColorRect.new()
	save_overlay.color = Color(0.008, 0.025, 0.04, 0.84)
	save_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	save_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	save_overlay.name = "SaveProfilesOverlay"
	add_child(save_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	save_overlay.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(minf(340.0, viewport_size.x - 32.0), minf(520.0, viewport_size.y - 32.0))
	card.add_theme_stylebox_override("panel", _panel_style("#102433", 20))
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	column.add_child(_label("LOAD GAME", 19, "#f1f6fa"))
	var description := _label("Each game is saved separately. Legacy map coordinates stay fictional.", 12, "#a8bac8")
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = minf(390.0, viewport_size.y - 180.0)
	column.add_child(scroll)
	var profile_list := VBoxContainer.new()
	profile_list.add_theme_constant_override("separation", 6)
	scroll.add_child(profile_list)
	var ordered_profiles := save_profiles.duplicate()
	ordered_profiles.reverse()
	var visible_count := 0
	for profile in ordered_profiles:
		var path := str(profile.get("path", ""))
		if not _is_valid_save_path(path):
			continue
		visible_count += 1
		var is_legacy := str(profile.get("map_space", "legacy_normalized")) != "kl_selangor_web_mercator_uv"
		var label := ("Legacy save · fictional map\n%s" % ("Current game · preserved" if path == save_path else "Preserved · tap to load")) if is_legacy else ("KL / Selangor · geographic game\n%s" % ("Current game" if path == save_path else "Tap to load"))
		var target_path := path
		var load_button := _button(label, func(): _load_save_profile(target_path))
		load_button.custom_minimum_size.y = 58
		load_button.disabled = path == save_path
		profile_list.add_child(load_button)
	if visible_count == 0:
		profile_list.add_child(_label("No saved games are available yet.", 13, "#a8bac8"))
	var close_button := _button("Return to Game", _close_save_overlay)
	close_button.custom_minimum_size.y = 46
	column.add_child(close_button)

func _web_save_mirror_exists(path: String) -> bool:
	var value: Variant = _web_storage_get(_save_mirror_key(path))
	if value is String and not value.is_empty():
		var parsed := JSON.new()
		if parsed.parse(value) == OK and typeof(parsed.data) == TYPE_DICTIONARY and str(parsed.data.get("path", "")) == path and parsed.data.get("data", {}) is Dictionary:
			return true
	if path == LEGACY_SAVE_PATH:
		value = _web_storage_get(WEB_SAVE_MIRROR_KEY)
		if value is String and not value.is_empty():
			var parsed := JSON.new()
			return parsed.parse(value) == OK and typeof(parsed.data) == TYPE_DICTIONARY and str(parsed.data.get("path", "")) == path
	return FileAccess.file_exists(path)

func _load_save_profile(path: String) -> void:
	if not _is_valid_save_path(path):
		status_label.text = "That saved game could not be found. Your current game remains active."
		return
	var previous_path := save_path
	_save_game()
	_register_current_save_profile()
	save_path = path
	_set_active_save_path(path)
	save_recovery_required = false
	world_map = false
	_load_game()
	if save_recovery_required:
		save_path = previous_path
		_set_active_save_path(previous_path)
		save_recovery_required = false
		_load_game()
		_close_save_overlay()
		status_label.text = "That save could not be loaded. Your previous game was restored and kept unchanged."
		_refresh()
		return
	_register_current_save_profile()
	selected_tab = "Map"
	selected_subtab = "City" if not world_map else "World"
	_close_save_overlay()
	status_label.text = "Loaded %s" % ("legacy fictional-map save" if legacy_map_mode else "KL / Selangor geographic game")
	_refresh()

func _close_save_overlay() -> void:
	if is_instance_valid(save_overlay):
		save_overlay.queue_free()
	save_overlay = null

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
	var browser_active := _maplibre_active()
	var map_rect := _map_content_rect(size)
	if not browser_active:
		map_view.draw_rect(Rect2(Vector2.ZERO, size), ThemeService.color("map_background"))
		map_view.draw_set_transform(map_camera.pan, 0.0, Vector2(map_camera.zoom, map_camera.zoom))
	if geographic_map_available and not legacy_map_mode and not browser_active and is_instance_valid(map_texture):
		map_view.draw_texture_rect(map_texture, map_rect, false)
		var major_places := ["Kuala Lumpur", "Petaling Jaya", "Shah Alam", "Subang Jaya", "Klang", "Kajang", "Ampang Jaya", "Puchong"]
		var drawn_label_rects: Array[Rect2] = []
		for place in geographic_service.places:
			var place_name := str(place.get("name", ""))
			var place_type := str(place.get("type", ""))
			if map_camera.zoom < 1.25 and place_name not in major_places:
				continue
			if map_camera.zoom >= 1.25 and place_type not in ["city", "town", "suburb", "quarter", "neighbourhood"]:
				continue
			var place_point: Vector2 = map_rect.position + place["uv"] * map_rect.size
			var screen_point := map_camera.world_to_screen(place["uv"], map_rect)
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
		var attribution_x := 108.0 if size.x > size.y else 18.0
		map_view.draw_string(ThemeDB.fallback_font, Vector2(attribution_x, 155), "© OpenStreetMap contributors · KL/Selangor", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ThemeService.color("map_label"))
		if world_map:
			map_view.draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.5 - 105, size.y * 0.24), "World map coverage is not available in this build.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ThemeService.color("text"))
	else:
		if not browser_active:
			_draw_fictional_map_background(size)
	# MapLibre owns geographic projection, line tessellation, culling, and marker
	# placement. Painting a second copy here used a stale polled camera snapshot
	# and drifted behind the continuously animated browser map.
	if browser_active:
		return
	var selected_route_order := _find_order(selected_order)
	var selected_sim: IDMRouteSimulation = route_simulations.get(int(selected_route_order.get("rider", -1))) if not selected_route_order.is_empty() else null
	if selected_sim != null and selected_sim.is_active():
		_draw_route_polyline(selected_sim.pickup_route.get("points", []), Color("#ffcf63"), 5.0, map_rect)
		_draw_route_polyline(selected_sim.dropoff_route.get("points", []), Color("#39d5e8"), 5.0, map_rect)
		var pickup_point := _screen_for_uv(Vector2(selected_sim.pickup_route["points"][-1])) if browser_active else map_rect.position + Vector2(selected_sim.pickup_route["points"][-1]) * map_rect.size
		map_view.draw_circle(pickup_point, 11.0, Color("#ffcf63"))
		map_view.draw_string(ThemeDB.fallback_font, pickup_point + Vector2(-4, 4), "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#342307"))
	for order in orders:
		if order["status"] == "Delivered":
			continue
		var point := _screen_for_uv(Vector2(order["destination"])) if browser_active else map_rect.position + Vector2(order["destination"]) * map_rect.size
		if point.x < -28 or point.y < -28 or point.x > size.x + 28 or point.y > size.y + 28:
			continue
		map_view.draw_circle(point, 23, ThemeService.color("rider_back"))
		map_view.draw_circle(point, 18, ThemeService.color("accent_fill"))
		map_view.draw_string(ThemeDB.fallback_font, point + Vector2(-5, 6), IDMServicePricing.marker(str(order.get("service_type", "parcel_logistics"))), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#06202a"))
	for rider in riders:
		var position: Vector2 = rider["position"]
		var route_sim: IDMRouteSimulation = route_simulations.get(int(rider.get("id", -1)))
		if route_sim != null and route_sim.is_active():
			position = route_sim.current_uv
		var point := _screen_for_uv(position) if browser_active else map_rect.position + position * map_rect.size
		if point.x < -28 or point.y < -28 or point.x > size.x + 28 or point.y > size.y + 28:
			continue
		map_view.draw_circle(point, 20, ThemeService.color("rider_back"))
		map_view.draw_circle(point, 15, ThemeService.color("rider"))
		map_view.draw_string(ThemeDB.fallback_font, point + Vector2(-5, 5), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#06202a"))
	map_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_route_polyline(route_points: Array, color: Color, width: float, map_rect: Rect2) -> void:
	if route_points.size() < 2:
		return
	var projected := PackedVector2Array()
	for point in route_points:
		projected.append(_screen_for_uv(Vector2(point)) if _maplibre_active() else map_rect.position + Vector2(point) * map_rect.size)
	map_view.draw_polyline(projected, color, width, true)

func _map_content_rect(size: Vector2) -> Rect2:
	return map_camera.content_rect(size, IDMGeographicService.TEXTURE_SIZE, geographic_map_available and not legacy_map_mode)

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
	if _maplibre_active():
		var camera := _browser_camera_snapshot()
		if not camera.is_empty():
			data["map_camera"] = camera
	var serialized := JSON.stringify(data)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		file.store_string(serialized)
		file.close()
	# Web IDBFS persistence completes asynchronously. This synchronous mirror
	# keeps the latest autosave available if Safari/Chrome reloads before its
	# IndexedDB transaction finishes; the versioned user:// file remains primary
	# on native builds and a fallback on Web.
	var envelope := JSON.stringify({"path": save_path, "data": data})
	_web_storage_set(_save_mirror_key(save_path), envelope)
	# Keep the pre-profile mirror key writable for older IDM builds. Per-path
	# mirrors remain intact when the active profile changes.
	_web_storage_set(WEB_SAVE_MIRROR_KEY, envelope)

func _web_storage_get(key: String) -> Variant:
	if not Engine.has_singleton("JavaScriptBridge"):
		return null
	var bridge: Object = Engine.get_singleton("JavaScriptBridge")
	if bridge == null:
		return null
	return bridge.call("eval", "localStorage.getItem(" + JSON.stringify(key) + ")", true)

func _web_storage_set(key: String, value: String) -> void:
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	var bridge: Object = Engine.get_singleton("JavaScriptBridge")
	if bridge == null:
		return
	var code := "try { localStorage.setItem(" + JSON.stringify(key) + ", " + JSON.stringify(value) + "); true; } catch (error) { false; }"
	bridge.call("eval", code, true)

func _web_save_mirror() -> Dictionary:
	var mirrored: Variant = _web_storage_get(_save_mirror_key(save_path))
	if not mirrored is String or mirrored.is_empty():
		mirrored = _web_storage_get(WEB_SAVE_MIRROR_KEY)
	if not mirrored is String or mirrored.is_empty():
		return {}
	var parsed := JSON.new()
	if parsed.parse(mirrored) != OK or typeof(parsed.data) != TYPE_DICTIONARY:
		return {}
	var envelope: Dictionary = parsed.data
	if str(envelope.get("path", "")) != save_path or not envelope.get("data", {}) is Dictionary:
		return {}
	var data: Dictionary = envelope["data"]
	if int(data.get("version", 0)) != 1 or not data.get("riders", []) is Array or not data.get("orders", []) is Array:
		return {}
	return data

func _load_game() -> void:
	selected_order = -1
	sheet_expanded = false
	maplibre_initialized = false
	browser_map_state.clear()
	pending_map_camera.clear()
	var data := _web_save_mirror()
	if data.is_empty():
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
		data = parsed.data
	if int(data.get("version", 0)) != 1:
		save_recovery_required = true
		return
	# Existing normalized saves belong to the old fictional prototype map. Keep
	# them in that coordinate space until a deliberate, visible migration exists.
	legacy_map_mode = str(data.get("map_space", "legacy_normalized")) != "kl_selangor_web_mercator_uv"
	var saved_camera: Variant = data.get("map_camera", {})
	if not legacy_map_mode and saved_camera is Dictionary and saved_camera.get("center", null) is Array:
		pending_map_camera = saved_camera.duplicate(true)
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
	route_simulations.clear()
	for order in orders:
		order["destination"] = _as_vector2(order.get("destination", ""), Vector2(0.5, 0.5))
		if order.has("pickup"):
			order["pickup"] = _as_vector2(order["pickup"], order["destination"])
		elif geographic_map_available and not legacy_map_mode:
			order["pickup"] = road_router.random_location_for_view(get_viewport_rect().size)
	for rider in riders:
		rider["position"] = _as_vector2(rider.get("position", ""), Vector2(0.5, 0.5))
	for rider in riders:
		if rider.get("status", "") != "busy":
			continue
		var order := _find_order(int(rider.get("order_id", -1)))
		if order.is_empty():
			rider["status"] = "ready"
			rider["order_id"] = -1
			continue
		if legacy_map_mode:
			rider["remaining"] = maxf(0.0, minf(float(rider.get("remaining", TRAVEL_SECONDS)), TRAVEL_SECONDS))
			order["status"] = "On route"
			continue
		var saved_route: Variant = rider.get("route_state", {})
		var simulation := IDMRouteSimulation.new()
		if road_network_available and saved_route is Dictionary and simulation.restore(saved_route) and simulation.is_active():
			route_simulations[int(rider["id"])] = simulation
			rider["position"] = simulation.current_uv
			rider["remaining"] = simulation.estimated_remaining_seconds(float(speed))
			order["status"] = "On route to pickup" if simulation.phase == IDMRouteSimulation.PHASE_PICKUP else "On route to delivery"
		else:
			# Older geographic saves have no road geometry. Requeue the booking and free the partner instead of teleporting.
			order["status"] = "Waiting"
			order["rider"] = -1
			rider["status"] = "ready"
			rider["order_id"] = -1
			rider.erase("route_state")
	for order in orders:
		if str(order.get("status", "")).begins_with("On route"):
			selected_order = int(order.get("id", -1))
			sheet_expanded = true
			break

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
	elapsed = 0.0
	autosave_elapsed = 0.0
	next_order_id = 1
	next_rider_id = 1
	speed = 1
	paused = false
	selected_order = -1
	sheet_expanded = false
	selected_tab = "Map"
	selected_subtab = "City"
	world_map = false
	maplibre_initialized = false
	browser_map_state.clear()
	pending_map_camera.clear()
	orders.clear()
	riders.clear()
	route_simulations.clear()
	followed_rider_id = -1
	for index in STARTING_RIDERS:
		var start_position := road_router.random_location_for_view(get_viewport_rect().size) if geographic_map_available and road_network_available else geographic_service.random_road_location(get_viewport_rect().size) if geographic_map_available else Vector2(0.5, 0.5)
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
	var session_path := "%s%d_%06d.json" % [SAVE_SESSION_PREFIX, int(Time.get_unix_time_from_system()), randi_range(0, 999999)]
	save_path = session_path
	_set_active_save_path(save_path)
	_new_game()
	for _index in 2:
		_spawn_order()
	_register_current_save_profile()
	if is_instance_valid(recovery_overlay):
		recovery_overlay.queue_free()
	_refresh()
