extends Control

const SAVE_PATH := "user://delivery_ops_save.json"
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
var pause_button: Button
var speed_buttons: Dictionary = {}
var sheet: PanelContainer
var sheet_content: VBoxContainer
var selected_tab := "Map"
var map_mode := "City"
var map_zoom := 1.0
var map_pan := Vector2.ZERO
var gesture_start := Vector2.ZERO
var gesture_pan := Vector2.ZERO
var pinch_distance := 0.0
var suppress_tap := false
var zoom_label: Label
var world_map := false

func _ready() -> void:
	_load_game()
	_build_ui()
	_refresh()
	if orders.is_empty():
		_spawn_order()
		_spawn_order()

func _process(delta: float) -> void:
	if paused:
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
	map_view.draw.connect(_draw_map)
	map_view.gui_input.connect(_on_map_input)
	add_child(map_view)

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12
	top.offset_top = 12
	top.offset_right = -12
	top.offset_bottom = 56
	top.add_theme_stylebox_override("panel", _panel_style("#101e2b", 14))
	add_child(top)
	var top_row := HBoxContainer.new()
	top.add_child(top_row)
	var brand := Label.new()
	brand.text = "IDM  /  OPERATIONS"
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_color_override("font_color", Color("#91eaff"))
	top_row.add_child(brand)
	cash_label = Label.new()
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(cash_label)

	var map_controls := VBoxContainer.new()
	map_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	map_controls.offset_left = -58
	map_controls.offset_top = 78
	map_controls.offset_right = -12
	map_controls.offset_bottom = 245
	add_child(map_controls)
	var zoom_in := _button("+", func(): _zoom_map(1.25))
	var zoom_out := _button("-", func(): _zoom_map(0.8))
	var recenter := _button("Center", _recenter_map)
	var overview := _button("Overview", _toggle_world)
	for control in [zoom_in, zoom_out, recenter, overview]:
		control.custom_minimum_size = Vector2(46, 44)
		map_controls.add_child(control)

	sheet = PanelContainer.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_left = 10
	sheet.offset_right = -10
	sheet.offset_top = -226
	sheet.offset_bottom = -72
	sheet.add_theme_stylebox_override("panel", _panel_style("#101e2b", 18))
	add_child(sheet)
	sheet_content = VBoxContainer.new()
	sheet_content.add_theme_constant_override("separation", 5)
	sheet.add_child(sheet_content)

	var subtabs := HBoxContainer.new()
	sheet_content.add_child(subtabs)
	for name in ["City", "World"]:
		subtabs.add_child(_button(name, func(): _set_subtab(name)))
	var nav := HBoxContainer.new()
	sheet_content.add_child(nav)
	for name in ["Map", "Fleet", "Finance", "Co."]:
		var button := _button(name, func(): _set_tab(name))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 46
		nav.add_child(button)

	order_list = VBoxContainer.new()
	order_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet_content.add_child(order_list)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("#87deef"))
	sheet_content.add_child(status_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	add_child(actions)
	actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	actions.offset_left = 10
	actions.offset_right = -10
	actions.offset_top = -64
	actions.offset_bottom = -8
	pause_button = _button("Pause", _toggle_pause)
	pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(pause_button)
	for multiplier in [1, 2, 4]:
		var factor: int = multiplier
		var button := _button(str(factor) + "x", func(): _set_speed(factor))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)

func _panel_style(color: String, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _zoom_map(factor: float) -> void:
	map_zoom = clampf(map_zoom * factor, 0.65, 2.5)
	map_view.queue_redraw()

func _recenter_map() -> void:
	map_pan = Vector2.ZERO
	map_zoom = 1.0
	map_view.queue_redraw()

func _toggle_world() -> void:
	world_map = not world_map
	map_zoom = 0.7 if world_map else 1.0
	map_pan = Vector2.ZERO
	status_label.text = "World overview" if world_map else "City map"

func _set_subtab(name: String) -> void:
	map_mode = name
	world_map = name == "World"
	map_view.queue_redraw()
	status_label.text = name + " map"

func _set_tab(name: String) -> void:
	selected_tab = name
	_refresh()

func _on_map_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			gesture_start = event.position
			gesture_pan = map_pan
			suppress_tap = false
		elif not suppress_tap:
			_select_marker(event.position)
	elif event is InputEventScreenDrag:
		if event.position.distance_to(gesture_start) > 8:
			suppress_tap = true
		map_pan = gesture_pan + event.position - gesture_start
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
		map_view.queue_redraw()

func _select_marker(point: Vector2) -> void:
	for order in orders:
		if order["status"] == "Waiting":
			var destination: Vector2 = order["destination"] * map_view.size * map_zoom + map_pan
			if point.distance_to(destination) < 30:
				selected_order = order["id"]
				_refresh()
				return

func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 48
	button.pressed.connect(callback)
	button.add_theme_color_override("font_color", Color("#eaf7ff"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#173448")
	normal.set_corner_radius_all(10)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("#20516a")
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = Color("#087a96")
	button.add_theme_stylebox_override("pressed", pressed)
	return button

func _spawn_order() -> void:
	if orders.size() >= 5:
		return
	var destination := Vector2(randf_range(0.15, 0.85), randf_range(0.2, 0.82))
	orders.append({
		"id": next_order_id,
		"destination": destination,
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
	order["status"] = "On route"
	order["rider"] = rider["id"]
	selected_order = order_id
	status_label.text = "Rider %02d dispatched" % rider["id"]
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
	status_label.text = "Delivered  +$%d  ·  cost $%d" % [payout, operating_cost]
	_save_game()
	_refresh()

func _hire_rider() -> void:
	if cash < 120:
		status_label.text = "Need $120 to hire"
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
	cash_label.text = "$%0.0f" % cash
	for child in order_list.get_children():
		child.queue_free()
	match selected_tab:
		"Map":
			var heading := Label.new()
			heading.text = "CITY MAP  /  FICTIONAL ROADS"
			heading.add_theme_color_override("font_color", Color("#91eaff"))
			order_list.add_child(heading)
			var selected := _find_order(selected_order)
			if not selected.is_empty() and selected["status"] == "Waiting":
				var detail := Label.new()
				detail.text = "Parcel %03d   ·   $%d delivery payout" % [selected["id"], selected["payout"]]
				order_list.add_child(detail)
				var dispatch := _button("Dispatch rider", func(): _dispatch(selected["id"]))
				dispatch.custom_minimum_size.y = 46
				order_list.add_child(dispatch)
			else:
				var hint := Label.new()
				hint.text = "Tap parcel marker to review."
				order_list.add_child(hint)
		"Fleet":
			var label := Label.new()
			label.text = "FLEET  ·  %d riders ready" % _ready_count()
			order_list.add_child(label)
			var hire := _button("Hire rider  ($120)", _hire_rider)
			hire.custom_minimum_size.y = 46
			order_list.add_child(hire)
		"Finance":
			var label := Label.new()
			label.text = "FINANCE OVERVIEW"
			order_list.add_child(label)
			var figures := Label.new()
			figures.text = "Cash $%0.0f  ·  Revenue $%0.0f  ·  Costs $%0.0f  ·  Delivered %d" % [cash, revenue_total, cost_total, delivered]
			order_list.add_child(figures)
		"Company":
			var label := Label.new()
			label.text = "OPERATIONS  ·  Phase 1"
			order_list.add_child(label)
			var summary := Label.new()
			summary.text = "%d active riders  ·  %d deliveries completed" % [riders.size(), delivered]
			order_list.add_child(summary)
	rider_summary = null
	finance_summary = null
	if is_instance_valid(map_view):
		map_view.queue_redraw()

func _ready_count() -> int:
	var count := 0
	for rider in riders:
		if rider["status"] == "ready":
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
	map_view.draw_rect(Rect2(Vector2.ZERO, size), Color("#0a1723"))
	map_view.draw_set_transform(map_pan, 0.0, Vector2(map_zoom, map_zoom))
	for x in range(-int(size.y), int(size.x) + 100, 84):
		map_view.draw_line(Vector2(x, 0), Vector2(x + int(size.y * 0.55), size.y), Color("#142b3a"), 8.0, true)
	for y in range(18, int(size.y), 58):
		map_view.draw_line(Vector2(0, y), Vector2(size.x, y), Color("#1c3543"), 3.0, true)
	map_view.draw_line(Vector2(size.x * 0.08, size.y * 0.78), Vector2(size.x * 0.91, size.y * 0.2), Color("#183c4b"), 15.0, true)
	for order in orders:
		if order["status"] == "Delivered":
			continue
		var point: Vector2 = order["destination"] * size
		map_view.draw_circle(point, 15, Color("#42d9f3"))
		map_view.draw_circle(point, 4, Color("#e6fcff"))
	for rider in riders:
		var position: Vector2 = rider["position"]
		if rider["status"] == "busy":
			var order := _find_order(rider["order_id"])
			if not order.is_empty():
				var target: Vector2 = order["destination"]
				var progress := clampf(1.0 - rider["remaining"] / TRAVEL_SECONDS, 0.0, 1.0)
				position = Vector2(0.5, 0.5).lerp(target, progress)
				rider["position"] = position
		var point := position * size
		map_view.draw_circle(point, 13, Color("#073746"))
		map_view.draw_circle(point, 8, Color("#65e5fa"))
		map_view.draw_string(ThemeDB.fallback_font, point + Vector2(-4, 4), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#06202a"))
	map_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	var data := {
		"version": 1,
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
	if not FileAccess.file_exists(SAVE_PATH):
		_new_game()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_new_game()
		return
	var parsed := JSON.new()
	if parsed.parse(file.get_as_text()) != OK or typeof(parsed.data) != TYPE_DICTIONARY:
		_new_game()
		return
	var data: Dictionary = parsed.data
	if int(data.get("version", 0)) != 1:
		_new_game()
		return
	cash = float(data.get("cash", STARTING_CASH))
	revenue_total = float(data.get("revenue_total", 0))
	cost_total = float(data.get("cost_total", 0))
	delivered = int(data.get("delivered", 0))
	next_order_id = int(data.get("next_order_id", 1))
	next_rider_id = int(data.get("next_rider_id", 1))
	elapsed = float(data.get("elapsed", 0))
	speed = int(data.get("speed", 1))
	orders.assign(data.get("orders", []))
	riders.assign(data.get("riders", []))
	if riders.is_empty():
		_new_game()
	for rider in riders:
		if rider["status"] == "busy":
			rider["remaining"] = minf(float(rider["remaining"]), TRAVEL_SECONDS)
			var order := _find_order(rider["order_id"])
			if not order.is_empty():
				order["status"] = "On route"

func _new_game() -> void:
	cash = STARTING_CASH
	revenue_total = 0.0
	cost_total = 0.0
	delivered = 0
	orders.clear()
	riders.clear()
	for index in STARTING_RIDERS:
		riders.append({"id": next_rider_id, "status": "ready", "order_id": -1, "remaining": 0.0, "position": Vector2(0.5, 0.5)})
		next_rider_id += 1
