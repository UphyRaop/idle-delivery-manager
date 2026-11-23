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
	game.set("player_company_service", "parcel_logistics")
	game.call("_new_game", false)
	game.set("paused", true)
	(game.get("simulation_clock") as Object).call("set_paused", true)
	game.set("main_menu_active", false)
	game.set("game_session_started", true)
	game.set("selected_tab", "Map")
	game.set("sheet_expanded", false)
	game.call("_spawn_order")
	game.call("_refresh")
	await process_frame

	var button := game.get("bookings_button") as Button
	var page := game.get("waiting_bookings_page") as Control
	var sheet := game.get("sheet") as Control
	var nav := game.get("bottom_nav") as Control
	var count := int(game.call("_waiting_count"))
	_check(is_instance_valid(button) and button.name == "WaitingBookingsButton", "map provides a dedicated floating bookings button")
	_check(is_instance_valid(button) and button.text == "Bookings (%d)" % count and button.accessibility_name.contains(str(count)), "button count and accessible label track real waiting bookings")
	_check(is_instance_valid(button) and button.custom_minimum_size.is_equal_approx(Vector2(148, 48)), "floating booking action keeps a 148 by 48 touch target")
	_check(button.visible and is_instance_valid(page) and not page.visible, "button appears on collapsed Map while full-page list starts hidden")
	_check(is_instance_valid(sheet) and sheet.visible and sheet.get_global_rect().size.x < 200.0, "collapsed map card retains only compact map subtabs")
	_check(is_instance_valid(nav) and nav.visible, "bottom navigation remains available on the Map page")

	var cash_before := float(game.get("cash"))
	var order_snapshot: Array = (game.get("orders") as Array).duplicate(true)
	var camera: IDMMapCamera = game.get("map_camera")
	var camera_before := Vector2(camera.pan.x, camera.zoom)
	var speed_before := int(game.get("speed"))
	button.pressed.emit()
	await process_frame
	_check(bool(game.get("waiting_bookings_page_open")) and page.visible, "Bookings opens the dedicated blocking page")
	_check(not nav.visible and not button.visible, "waiting list hides map controls and bottom navigation from touch input")
	var page_style := page.get_theme_stylebox("panel") as StyleBoxFlat
	_check(is_instance_valid(page_style) and page_style.bg_color == Color("#07151f"), "waiting list uses an opaque panel surface")
	var rows := game.get("waiting_bookings_page_list") as VBoxContainer
	_check(rows.get_child_count() == count and count > 0, "waiting list contains one actionable row per waiting booking")
	var first_card := rows.get_child(0) as PanelContainer
	var review := first_card.find_child("ReviewBooking*", true, false) as Button
	var picker := first_card.find_child("PartnerPicker*", true, false) as OptionButton
	var dispatch_action := first_card.find_child("DispatchBooking*", true, false) as Button
	_check(is_instance_valid(review) and review.text == "Map" and review.custom_minimum_size.y >= 48.0, "each booking row has a touch-sized map review action")
	_check(is_instance_valid(picker) and picker.item_count > 0 and picker.get_item_text(0).begins_with("Recommended · Partner"), "waiting booking recommends the nearest eligible available partner")
	_check(is_instance_valid(dispatch_action) and dispatch_action.text == "Dispatch" and dispatch_action.custom_minimum_size.y >= 48.0 and not dispatch_action.disabled, "waiting booking offers a touch-sized direct dispatch action")
	var back_header := page.find_child("WaitingBookingsBackButton", true, false) as Button
	for requested in [Vector2i(360, 800), Vector2i(375, 812), Vector2i(390, 844), Vector2i(393, 852), Vector2i(414, 896), Vector2i(430, 932), Vector2i(844, 390), Vector2i(768, 1024), Vector2i(1024, 768), Vector2i(1366, 768)]:
		root.size = requested
		await process_frame
		game.call("_layout_ui")
		await process_frame
		var header_rect := back_header.get_global_rect()
		rows = game.get("waiting_bookings_page_list") as VBoxContainer
		var viewport_card := rows.get_child(0) as PanelContainer
		var booking_rect := viewport_card.get_global_rect()
		var logical_viewport: Vector2 = game.get("viewport_size")
		_check(header_rect.position.x >= 0.0 and header_rect.end.x <= logical_viewport.x, "Waiting Bookings back control stays in the logical viewport at %dx%d" % [requested.x, requested.y])
		_check(booking_rect.position.x >= 0.0 and booking_rect.end.x <= logical_viewport.x, "Waiting Bookings card stays in the logical viewport at %dx%d" % [requested.x, requested.y])
	root.size = Vector2i(390, 844)
	await process_frame
	game.call("_layout_ui")
	await process_frame
	_check(is_equal_approx(float(game.get("cash")), cash_before) and (game.get("orders") as Array) == order_snapshot, "opening the list does not change finance or booking state")
	_check(is_equal_approx(camera.pan.x, camera_before.x) and is_equal_approx(camera.zoom, camera_before.y) and int(game.get("speed")) == speed_before, "opening the list preserves map camera and simulation speed")

	# Exercise the real Back button callback and ensure the map/camera session is
	# restored without a save/load cycle.
	var back := page.find_child("WaitingBookingsBackButton", true, false) as Button
	_check(is_instance_valid(back) and back.text == "Map" and back.accessibility_name == "Back to Map", "full-page list has a compact, accessible Back to Map action")
	if is_instance_valid(back):
		back.pressed.emit()
	await process_frame
	_check(not bool(game.get("waiting_bookings_page_open")) and not page.visible and button.visible and nav.visible, "Back to Map restores the collapsed map controls")
	_check(is_equal_approx(float(game.get("cash")), cash_before), "returning to Map preserves company cash")

	# Review a booking returns to its existing map detail/dispatch workflow.
	button.pressed.emit()
	await process_frame
	rows = game.get("waiting_bookings_page_list") as VBoxContainer
	first_card = rows.get_child(0) as PanelContainer
	review = first_card.find_child("ReviewBooking*", true, false) as Button
	var order_id := int((game.get("orders") as Array[Dictionary])[0].get("id", -1))
	if is_instance_valid(review):
		review.pressed.emit()
	await process_frame
	_check(not bool(game.get("waiting_bookings_page_open")) and not page.visible, "Review closes the list and returns to the map")
	_check(str(game.get("selected_tab")) == "Map" and int(game.get("selected_order")) == order_id and bool(game.get("sheet_expanded")), "Review selects the original booking in the existing detail sheet")
	_check(not button.visible, "floating action does not overlap an expanded booking detail sheet")
	# The dedicated list and map share the authoritative dispatch method.
	game.call("_open_waiting_bookings_page")
	await process_frame
	rows = game.get("waiting_bookings_page_list") as VBoxContainer
	first_card = rows.get_child(0) as PanelContainer
	picker = first_card.find_child("PartnerPicker*", true, false) as OptionButton
	dispatch_action = first_card.find_child("DispatchBooking*", true, false) as Button
	var recommended_id := picker.get_selected_id() if is_instance_valid(picker) else -1
	if is_instance_valid(dispatch_action):
		dispatch_action.pressed.emit()
	await process_frame
	var dispatched_order: Dictionary = game.call("_find_order", order_id)
	var dispatched_partner: Dictionary = game.call("_find_rider", int(dispatched_order.get("rider", -1)))
	_check(str(dispatched_order.get("status", "")).begins_with("On route") and int(dispatched_partner.get("id", -1)) == recommended_id, "Waiting Bookings dispatches to the recommended partner through shared gameplay logic")
	_check(str(dispatched_partner.get("status", "")) == "busy" and int(dispatched_partner.get("order_id", -1)) == order_id, "dispatch marks partner busy with exactly one active booking")
	game.call("_close_waiting_bookings_page")
	await process_frame

	# Other pages hide the map action; returning to Map restores the compact state.
	game.call("_set_tab", "Finance")
	_check(not button.visible, "non-Map tab hides the floating bookings action")
	game.call("_set_tab", "Map")
	_check(button.visible and not bool(game.get("sheet_expanded")), "returning to Map restores its collapsed booking-button state")

	# Responsive placement: verify the floating action and tabs sit above nav and
	# fit across the approved phone, tablet, and desktop widths.
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
		var button_rect := button.get_global_rect()
		var nav_rect := nav.get_global_rect()
		_check(button_rect.size.x >= 140.0 and button_rect.size.y >= 44.0, "booking button remains touch-sized at %dx%d" % [requested.x, requested.y])
		_check(button_rect.position.x >= 0.0 and button_rect.end.x <= float(requested.x), "booking button stays inside the viewport at %dx%d" % [requested.x, requested.y])
		_check(button_rect.end.y <= nav_rect.position.y + 1.0, "booking button sits above navigation at %dx%d" % [requested.x, requested.y])
		_check(not button_rect.intersects(nav_rect), "booking button does not overlap navigation at %dx%d" % [requested.x, requested.y])

	# Empty-state copy is useful and no fake order rows are rendered.
	var empty_orders: Array[Dictionary] = []
	game.set("orders", empty_orders)
	game.call("_refresh")
	game.call("_open_waiting_bookings_page")
	await process_frame
	rows = game.get("waiting_bookings_page_list") as VBoxContainer
	_check(rows.get_child_count() == 1 and rows.get_child(0) is Label and str((rows.get_child(0) as Label).text).contains("No waiting bookings"), "empty queue displays a clear empty state")
	_check(button.text == "Bookings (0)", "live counter displays zero for an empty queue")
	game.call("_close_waiting_bookings_page")
	game.queue_free()
	print("BOOKINGS BUTTON RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
