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
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.add_theme_constant_override("margin_left", 12)
	inset.add_theme_constant_override("margin_right", 12)
	inset.add_theme_constant_override("margin_top", 10)
	inset.add_theme_constant_override("margin_bottom", 10)
	add_child(inset)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	inset.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var brand := Label.new()
	brand.text = "IDM  /  DELIVERY OPS"
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_color_override("font_color", Color("#91eaff"))
	brand.add_theme_font_size_override("font_size", 15)
	top.add_child(brand)
	cash_label = Label.new()
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(cash_label)

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 1)
	root.add_child(stats)
	rider_summary = Label.new()
	rider_summary.add_theme_font_size_override("font_size", 14)
	stats.add_child(rider_summary)
	finance_summary = Label.new()
	finance_summary.add_theme_font_size_override("font_size", 14)
	stats.add_child(finance_summary)

	map_view = Control.new()
	map_view.custom_minimum_size = Vector2(0, 150)
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.draw.connect(_draw_map)
	root.add_child(map_view)

	var map_label := Label.new()
	map_label.text = "PROTOTYPE MAP  ·  FICTIONAL ROADS"
	map_label.add_theme_color_override("font_color", Color("#77dbee"))
	map_label.add_theme_font_size_override("font_size", 11)
	root.add_child(map_label)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 170
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#101e2b")
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	panel.add_child(inner)
	var header := HBoxContainer.new()
	inner.add_child(header)
	var heading := Label.new()
	heading.text = "ORDERS"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("#87deef"))
	status_label.add_theme_font_size_override("font_size", 11)
	header.add_child(status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	order_list = VBoxContainer.new()
	order_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(order_list)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	root.add_child(actions)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 3)
	actions.add_child(controls)
	pause_button = _button("Pause", _toggle_pause)
	pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(pause_button)
	for multiplier in [1, 2, 4]:
		var factor: int = multiplier
		var button := _button(str(factor) + "x", func(): _set_speed(factor))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.x = 0
		controls.add_child(button)
	var hire := _button("Hire rider  ($120)", _hire_rider)
	hire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(hire)

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
	rider_summary.text = "Riders  %d ready / %d working" % [_ready_count(), riders.size() - _ready_count()]
	finance_summary.text = "Delivered %d  |  Net $%0.0f  |  Cash $%0.0f" % [delivered, revenue_total - cost_total, cash]
	for child in order_list.get_children():
		child.queue_free()
	for order in orders:
		if order["status"] == "Delivered":
			continue
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 48
		order_list.add_child(row)
		var details := Label.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.text = "Parcel %03d  |  $%d  |  %s" % [order["id"], order["payout"], order["status"]]
		details.clip_text = true
		row.add_child(details)
		if order["status"] == "Waiting":
			var dispatch := _button("Dispatch", func(): _dispatch(order["id"]))
			dispatch.custom_minimum_size = Vector2(92, 44)
			row.add_child(dispatch)
		else:
			var rider_label := Label.new()
			rider_label.text = "Rider %02d" % order["rider"]
			row.add_child(rider_label)
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
	for x in range(-int(size.y), int(size.x) + 100, 84):
		map_view.draw_line(Vector2(x, 0), Vector2(x + int(size.y * 0.55), size.y), Color("#142b3a"), 8.0, true)
	for y in range(18, int(size.y), 58):
		map_view.draw_line(Vector2(0, y), Vector2(size.x, y), Color("#1c3543"), 3.0, true)
	map_view.draw_line(Vector2(size.x * 0.08, size.y * 0.78), Vector2(size.x * 0.91, size.y * 0.2), Color("#183c4b"), 15.0, true)
	for order in orders:
		var point: Vector2 = order["destination"] * size
		map_view.draw_circle(point, 11, Color("#42d9f3"))
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
