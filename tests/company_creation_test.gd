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

func _select_value(option: OptionButton, value: String) -> bool:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return true
	return false

func _labels_contain(node: Node, expected: String) -> bool:
	if node is Label and expected in (node as Label).text:
		return true
	if node is Button and expected in (node as Button).text:
		return true
	for child in node.get_children():
		if _labels_contain(child, expected):
			return true
	return false

func _run() -> void:
	var game := Control.new()
	game.set_script(load("res://scripts/game.gd"))
	root.add_child(game)
	await process_frame
	var old_path := "user://delivery_ops_session_company_creation_legacy.json"
	game.set("save_path", old_path)
	game.set("legacy_map_mode", true)
	game.set("cash", 321.45)
	game.set("riders", [{"id": 1, "status": "ready", "order_id": -1, "remaining": 0.0, "position": Vector2(0.4, 0.5)}])
	game.set("orders", [])
	game.set("game_session_started", true)
	game.call("_save_game")
	game.call("_register_current_save_profile")
	game.call("_confirm_new_game")
	game.call("_layout_ui")
	_check(is_instance_valid(game.get("new_game_confirmation")), "responsive layout refresh keeps company setup open")	
	var name_field: LineEdit = game.get("company_name_input")
	var service_option: OptionButton = game.get("company_service_option")
	var difficulty_option: OptionButton = game.get("company_difficulty_option")
	var location_option: OptionButton = game.get("company_location_option")
	_check(name_field.text == "My Logistics Sdn. Bhd.", "company name starts with the approved editable default")
	_check(_labels_contain(game.get("new_game_confirmation"), "Create Company"), "company creation action fits a mobile-sized dialog")
	_check(service_option.item_count == 4 and str(service_option.get_item_metadata(service_option.selected)) == "food_delivery", "four founding services are selectable with Food Delivery as default")
	_check(difficulty_option.item_count == 3 and str(difficulty_option.get_item_metadata(difficulty_option.selected)) == "standard", "difficulty choices default to Standard")
	_check(location_option.item_count >= 6 and str(location_option.get_item_metadata(location_option.selected)) == "Kuala Lumpur", "supported real Malaysian starting locations default to Kuala Lumpur")
	_check(_select_value(location_option, "Kampung Pandan"), "starting locations come from bundled real KL/Selangor place data")
	_check(FileAccess.file_exists(old_path), "opening company creation leaves the prior save present")
	name_field.text = ""
	game.call("_start_new_geographic_game")
	_check(bool(game.get("main_menu_active")) and is_instance_valid(game.get("new_game_confirmation")), "an empty company name is rejected without creating the game")
	name_field.text = "Kampung Pandan Couriers"
	_select_value(service_option, "express_logistics")
	_select_value(difficulty_option, "realistic")
	game.call("_start_new_geographic_game")
	var new_path := str(game.get("save_path"))
	var company_name := str(game.get("player_company_name"))
	var company_service := str(game.get("player_company_service"))
	var location := str(game.get("player_starting_location"))
	_check(not bool(game.get("main_menu_active")), "explicit Create Company action starts a game")
	_check(company_name == "Kampung Pandan Couriers" and company_service == "express_logistics" and location == "Kampung Pandan" and str(game.get("player_difficulty")) == "realistic", "selected company setup is applied")
	var brand: Label = game.get("brand_label")
	_check(brand.text == company_name, "the gameplay HUD identifies the player company")
	game.set("selected_tab", "Finance")
	game.set("selected_subtab", "Overview")
	game.call("_refresh")
	_check(_labels_contain(game.get("order_list"), company_name), "finance view identifies the company whose results are shown")
	game.set("selected_tab", "Operations")
	game.set("selected_subtab", "Company")
	game.call("_refresh")
	_check(_labels_contain(game.get("order_list"), company_name), "company records identify the selected company")
	_check(is_equal_approx(float(game.get("cash")), 350.0), "difficulty changes starting capital")
	var selected_center: Array = game.call("_starting_location_center")
	_check(absf(float(selected_center[0]) - 101.734727) < 0.000001 and absf(float(selected_center[1]) - 3.140837) < 0.000001, "map starts at the selected place's real coordinates")
	var payload: Dictionary = game.call("_save_payload_for_path", new_path)
	var company: Dictionary = payload.get("company", {})
	_check(company.get("name", "") == company_name and company.get("service_id", "") == company_service and company.get("difficulty", "") == "realistic" and company.get("starting_location", "") == location, "company setup persists in save metadata")
	var orders: Array = game.get("orders")
	_check(not orders.is_empty() and orders.all(func(order: Dictionary) -> bool: return str(order.get("service_type", "")) == "express_logistics"), "new bookings follow the selected founding service")
	var prior: Dictionary = game.call("_save_payload_for_path", old_path)
	_check(is_equal_approx(float(prior.get("cash", 0.0)), 321.45) and str(prior.get("map_space", "")) == "legacy_normalized", "creating a company preserves the earlier legacy save")
	selected_center = game.call("_starting_location_center")
	_check(absf(float(selected_center[0]) - 101.734727) < 0.000001 and absf(float(selected_center[1]) - 3.140837) < 0.000001, "selected starting locality remains stable for map initialization")
	print("COMPANY CREATION RESULT: %d passed, %d failed" % [passed, failed])
	for path in [old_path, new_path, "user://idm_save_catalog.json", "user://idm_active_save.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.queue_free()
	quit(1 if failed else 0)
