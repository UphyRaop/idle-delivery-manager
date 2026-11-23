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
	root.add_child(game)
	await process_frame
	var auto_path := "user://delivery_ops_session_save_management_test.json"
	for path in [auto_path, auto_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for slot in range(1, 4):
		for suffix in [".json", ".json.bak", ".json.tmp"]:
			var slot_path := "user://delivery_ops_manual_slot_%d%s" % [slot, suffix]
			if FileAccess.file_exists(slot_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path))
	game.set("save_path", auto_path)
	game.call("_set_active_save_path", auto_path)
	game.set("main_menu_active", false)
	game.set("game_session_started", true)
	game.set("paused", true)
	game.set("legacy_map_mode", false)
	game.set("player_company_name", "Kampung Pandan Courier Sdn. Bhd.")
	game.set("player_company_service", "parcel_logistics")
	game.set("player_difficulty", "realistic")
	game.set("player_starting_location", "Kampung Pandan")
	game.set("cash", 1324.56)
	game.set("revenue_total", 836.42)
	game.set("cost_total", 122.35)
	game.set("delivered", 7)
	game.set("elapsed", 187200.0)
	game.set("speed", 10)
	var test_orders: Array[Dictionary] = [{"id": 23, "status": "Waiting", "rider": -1, "destination": Vector2(0.62, 0.44), "pickup": Vector2(0.51, 0.43), "payout": 34.5, "service_type": "parcel_logistics"}]
	var test_riders: Array[Dictionary] = [{"id": 5, "status": "ready", "order_id": -1, "remaining": 0.0, "position": Vector2(0.49, 0.41), "latitude": 3.12, "longitude": 101.72, "coordinate_reference": "EPSG:4326"}]
	game.set("orders", test_orders)
	game.set("riders", test_riders)
	game.call("_save_game")
	game.call("_register_current_save_profile")
	var auto_before: Dictionary = game.call("_save_payload_for_path", auto_path)
	_check(not auto_before.is_empty(), "active autosave is valid before manual save")
	game.call("_set_tab", "Settings")
	var settings_text := _all_text(game.get("order_list"))
	_check(settings_text.has("Save Game") and settings_text.has("AUTOSAVE · CURRENT GAME") and settings_text.any(func(value: String) -> bool: return value.contains("Game Day") and value.contains("Saved ") and value.contains("UTC")), "Settings → Game exposes Save Game and current save metadata")
	var save_game_button := _find_button(game.get("order_list"), "Save Game")
	if save_game_button != null:
		save_game_button.emit_signal("pressed")
	await process_frame
	var overlay: Control = game.get("save_overlay")
	_check(overlay.name == "ManualSaveOverlay", "Settings Save Game opens the manual slot manager")
	_check(overlay.find_children("", "Button", true, false).size() == 4, "all three manual slots and Return to Game are visible")
	var slot_one := overlay.find_child("ManualSaveSlot1", true, false) as PanelContainer
	var slot_two := overlay.find_child("ManualSaveSlot2", true, false) as PanelContainer
	var slot_three := overlay.find_child("ManualSaveSlot3", true, false) as PanelContainer
	_check(is_instance_valid(slot_one) and slot_one.get_child(0) is HBoxContainer and is_instance_valid(slot_two) and slot_two.get_child(0) is HBoxContainer and is_instance_valid(slot_three) and slot_three.get_child(0) is HBoxContainer, "all manual slots use full-width horizontal rows")
	_check(_find_button(slot_one, "Save") != null and _find_button(overlay, "Return to Game") != null, "empty slot has Save action and popup has Return to Game")
	var save_card := overlay.find_child("ManualSaveCard", true, false) as PanelContainer
	var save_card_rect := save_card.get_global_rect()
	var logical_viewport: Vector2 = game.get("viewport_size")
	_check(save_card_rect.position.x >= 0.0 and save_card_rect.end.x <= logical_viewport.x, "save popup fits inside the mobile logical viewport")
	_check(slot_one.get_global_rect().size.x >= save_card_rect.size.x - 60.0, "manual slot rows expand to the popup's full content width")
	var save_action := _find_button(slot_one, "Save")
	var save_action_rect := save_action.get_global_rect()
	_check(save_action_rect.size.x >= 80.0 and save_action_rect.size.y >= 44.0 and save_action_rect.end.x <= logical_viewport.x, "Save action stays touch-sized and visible")
	var save_viewports: Array[Vector2i] = [
		Vector2i(360, 800), Vector2i(375, 812), Vector2i(390, 844), Vector2i(393, 852),
		Vector2i(414, 896), Vector2i(430, 932), Vector2i(844, 390), Vector2i(768, 1024),
		Vector2i(1024, 768), Vector2i(1366, 768),
	]
	for requested in save_viewports:
		root.size = requested
		await process_frame
		game.call("_layout_ui")
		await process_frame
		var resized_viewport: Vector2 = game.get("viewport_size")
		var resized_card_rect := save_card.get_global_rect()
		var resized_slot_rect := slot_one.get_global_rect()
		var resized_action_rect := save_action.get_global_rect()
		_check(resized_card_rect.position.x >= 0.0 and resized_card_rect.end.x <= resized_viewport.x and resized_card_rect.position.y >= 0.0 and resized_card_rect.end.y <= resized_viewport.y, "save popup stays within %dx%d viewport" % [requested.x, requested.y])
		_check(resized_slot_rect.position.x >= resized_card_rect.position.x and resized_slot_rect.end.x <= resized_card_rect.end.x and resized_action_rect.end.x <= resized_slot_rect.end.x, "save slot row and action stay inside the popup at %dx%d" % [requested.x, requested.y])
	root.size = Vector2i(390, 844)
	await process_frame
	game.call("_layout_ui")
	await process_frame
	_check(not game.call("_manual_slot_exists", 1), "manual slots are initially separate and empty")
	_check(bool(game.call("_save_manual_slot", 1)), "first manual save writes to Slot 1")
	var first_snapshot: Dictionary = game.call("_manual_slot_payload", 1)
	_check(not first_snapshot.is_empty() and str(game.get("save_path")) == auto_path, "manual save leaves the autosave path unchanged")
	_check(is_equal_approx(float(first_snapshot.get("cash", 0.0)), 1324.56) and is_equal_approx(float(first_snapshot.get("revenue_total", 0.0)), 836.42) and is_equal_approx(float(first_snapshot.get("cost_total", 0.0)), 122.35), "manual save preserves cash and financial totals")
	_check(int(first_snapshot.get("speed", 0)) == 10 and int(first_snapshot.get("delivered", 0)) == 7 and first_snapshot.get("orders", []).size() == 1 and first_snapshot.get("riders", []).size() == 1, "manual save preserves speed, bookings, partners, and delivery count")
	var company: Dictionary = first_snapshot.get("company", {})
	_check(company.get("name", "") == "Kampung Pandan Courier Sdn. Bhd." and company.get("service_id", "") == "parcel_logistics" and company.get("difficulty", "") == "realistic" and company.get("starting_location", "") == "Kampung Pandan", "manual save preserves company selections and locality")
	var metadata := str(game.call("_save_metadata_text", first_snapshot))
	_check(metadata.contains("Kampung Pandan Courier") and metadata.contains("Game Day 03") and metadata.contains("Kampung Pandan") and metadata.contains("UTC"), "slot metadata shows company, game date, location, and saved timestamp")
	game.call("_show_manual_save_slots")
	var overwrite_action := _find_button(game.get("save_overlay"), "Overwrite")
	_check(overwrite_action != null, "occupied slot row presents an Overwrite action")
	game.set("cash", 999.0)
	_check(not bool(game.call("_save_manual_slot", 1)), "occupied manual slot requires overwrite confirmation")
	var confirm: Control = game.get("overwrite_confirmation_overlay")
	_check(confirm.name == "ManualSaveOverwriteConfirmation" and _all_text(confirm).has("OVERWRITE SLOT 1?"), "overwrite dialog names the selected slot before saving")
	var unchanged: Dictionary = game.call("_manual_slot_payload", 1)
	_check(is_equal_approx(float(unchanged.get("cash", 0.0)), 1324.56), "cancel path leaves the existing manual slot unchanged")
	var slot_list_before_cancel: Control = game.get("save_overlay")
	var cancel_button := _find_button(confirm, "Cancel")
	if cancel_button != null:
		cancel_button.emit_signal("pressed")
	await process_frame
	var slot_list_after_cancel: Variant = game.get("save_overlay")
	var overwrite_after_cancel: Variant = game.get("overwrite_confirmation_overlay")
	var confirmation_dismissed := not is_instance_valid(overwrite_after_cancel) or (overwrite_after_cancel is Control and (overwrite_after_cancel as Control).is_queued_for_deletion())
	_check(is_instance_valid(slot_list_before_cancel) and slot_list_after_cancel == slot_list_before_cancel and (slot_list_after_cancel as Control).find_children("", "Button", true, false).size() == 4 and confirmation_dismissed and is_equal_approx(float((game.call("_manual_slot_payload", 1) as Dictionary).get("cash", 0.0)), 1324.56), "Cancel returns to slot list without changing the existing save")
	var auto_before_manual_write: Dictionary = game.call("_save_payload_for_path", auto_path)
	_check(bool(game.call("_save_manual_slot", 1, true)), "confirmed overwrite saves the updated snapshot")
	_check(FileAccess.file_exists("user://delivery_ops_manual_slot_1.json.bak"), "overwriting a manual slot keeps a previous backup")
	var auto_after: Dictionary = game.call("_save_payload_for_path", auto_path)
	_check(is_equal_approx(float(auto_after.get("cash", 0.0)), float(auto_before_manual_write.get("cash", -1.0))) and str(auto_after.get("path", auto_path)) == auto_path, "manual overwrite does not overwrite the separate autosave")
	var latest_path := str(game.call("_latest_valid_save_path"))
	_check(latest_path == "user://delivery_ops_manual_slot_1.json", "Continue considers the newest valid manual save")
	game.set("cash", 1.0)
	game.call("_load_manual_slot", 1)
	var loaded_path := str(game.get("save_path"))
	game.set("paused", true)
	game.get("simulation_clock").call("set_paused", true)
	_check(not bool(game.get("main_menu_active")) and loaded_path.begins_with("user://delivery_ops_session_") and loaded_path != "user://delivery_ops_manual_slot_1.json", "loading a manual slot resumes into a separate autosave session")
	_check(is_equal_approx(float(game.get("cash")), 999.0) and is_equal_approx(float(game.get("revenue_total")), 836.42) and int(game.get("speed")) == 10, "manual load restores cash, finance totals, and simulation speed")
	_check(str(game.get("player_company_name")) == "Kampung Pandan Courier Sdn. Bhd." and str(game.get("player_starting_location")) == "Kampung Pandan" and game.get("orders").size() == 1 and game.get("riders").size() == 1, "manual load restores company, locality, bookings, and partners")
	var preserved_manual: Dictionary = game.call("_manual_slot_payload", 1)
	_check(is_equal_approx(float(preserved_manual.get("cash", 0.0)), 999.0), "loading a manual save does not mutate its original slot")
	var corrupt_path := "user://delivery_ops_manual_slot_2.json"
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt_file.store_string("{broken")
	corrupt_file.close()
	_check(game.call("_manual_slot_exists", 2) and game.call("_manual_slot_payload", 2).is_empty(), "corrupt slot is reported but not discarded")
	game.call("_show_load_game")
	var load_overlay: Control = game.get("save_overlay")
	var buttons := load_overlay.find_children("", "Button", true, false)
	var empty_or_corrupt_disabled := false
	for button in buttons:
		if button is Button and (button as Button).text == "Load Slot 2":
			empty_or_corrupt_disabled = (button as Button).disabled
	_check(empty_or_corrupt_disabled, "corrupt slot cannot be loaded through the UI")
	var previous_save: Dictionary = game.call("_save_payload_for_path", loaded_path)
	game.call("_load_manual_slot", 2)
	_check(not previous_save.is_empty() and str(game.get("save_path")) == loaded_path and is_equal_approx(float(game.get("cash")), 999.0), "failed manual load leaves the current game active and unchanged")
	print("SAVE MANAGEMENT RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _all_text(node: Node) -> Array[String]:
	var values: Array[String] = []
	if node is Label:
		values.append((node as Label).text)
	elif node is Button:
		values.append((node as Button).text)
	for child in node.get_children():
		values.append_array(_all_text(child))
	return values

func _find_button(node: Node, target: String) -> Button:
	if node is Button and (node as Button).text == target:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, target)
		if found != null:
			return found
	return null
