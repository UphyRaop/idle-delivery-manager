extends SceneTree

func _initialize() -> void:
	var camera := IDMMapCamera.new()
	var viewport := Vector2(390, 844)
	var map_rect := camera.content_rect(viewport, Vector2(1152, 1320))
	var uv := Vector2(0.63, 0.41)
	_check(camera.screen_to_world(camera.world_to_screen(uv, map_rect), map_rect).distance_to(uv) < 0.00001, "world/screen transforms round trip")
	var zoom_focus := Vector2(180, 350)
	var uv_under_focus := camera.screen_to_world(zoom_focus, map_rect)
	camera.zoom_at(1.7, zoom_focus, viewport)
	_check(camera.zoom > 1.0, "pointer zoom changes camera zoom")
	_check(camera.screen_to_world(zoom_focus, map_rect).distance_to(uv_under_focus) < 0.00001, "zoom keeps the geographic point under the gesture anchored")
	_check(camera.screen_to_world(camera.world_to_screen(uv, map_rect), map_rect).distance_to(uv) < 0.00001, "world/screen transforms round trip after zoom and pan")
	camera.set_follow(true, uv, map_rect, viewport)
	var next_target := Vector2(0.64, 0.42)
	camera.update_follow(1.0, next_target, map_rect, viewport)
	_check(camera.follow_enabled, "follow updates keep follow enabled")
	_check(camera.world_to_screen(next_target, map_rect).distance_to(viewport * camera.follow_anchor_ratio) < 0.5, "follow camera keeps the selected rider aligned with its screen anchor")
	camera.pan_by(Vector2(1, 0), viewport)
	_check(not camera.follow_enabled, "manual pan immediately disables follow")
	camera.set_follow(true, uv, map_rect, viewport)
	camera.viewport_changed(viewport, Vector2(844, 390), map_rect, camera.content_rect(Vector2(844, 390), Vector2(1152, 1320)))
	_check(camera.follow_enabled, "resize preserves follow mode")
	camera.recenter()
	_check(camera.zoom == 1.0 and camera.pan == Vector2.ZERO and not camera.follow_enabled, "recenter resets map and follow")
	print("Map camera tests: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

var passed := 0
var failed := 0
func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)
