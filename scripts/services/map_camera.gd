extends RefCounted
class_name IDMMapCamera

## Camera state for the map canvas. World locations are normalized texture UVs.
## Keeping this transform in one place keeps markers and polylines aligned.
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var follow_enabled: bool = false
var follow_anchor_ratio: Vector2 = Vector2(0.5, 0.55)
var min_zoom: float = 0.65
var max_zoom: float = 2.5
var follow_smoothing: float = 8.0

func content_rect(viewport_size: Vector2, texture_size: Vector2, use_texture: bool = true) -> Rect2:
	if not use_texture or texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Rect2(Vector2.ZERO, viewport_size)
	var scale := maxf(viewport_size.x / texture_size.x, viewport_size.y / texture_size.y)
	var fitted := texture_size * scale
	return Rect2((viewport_size - fitted) * 0.5, fitted)

func world_to_screen(world_uv: Vector2, map_rect: Rect2) -> Vector2:
	return (map_rect.position + world_uv * map_rect.size) * zoom + pan

func screen_to_world(screen_point: Vector2, map_rect: Rect2) -> Vector2:
	if zoom <= 0.0 or map_rect.size.x == 0.0 or map_rect.size.y == 0.0:
		return Vector2.ZERO
	return ((screen_point - pan) / zoom - map_rect.position) / map_rect.size

func pan_by(delta: Vector2, viewport_size: Vector2) -> void:
	if delta.length_squared() > 0.0:
		# A manual gesture always takes control immediately.
		follow_enabled = false
		pan += delta
		clamp_pan(viewport_size)

func zoom_at(factor: float, screen_point: Vector2, viewport_size: Vector2) -> void:
	if factor <= 0.0:
		return
	var world_under_pointer := (screen_point - pan) / zoom
	zoom = clampf(zoom * factor, min_zoom, max_zoom)
	pan = screen_point - world_under_pointer * zoom
	clamp_pan(viewport_size)

func clamp_pan(viewport_size: Vector2) -> void:
	pan.x = clampf(pan.x, -viewport_size.x * 0.8, viewport_size.x * 0.8)
	pan.y = clampf(pan.y, -viewport_size.y * 0.8, viewport_size.y * 0.8)

func set_follow(enabled: bool, target_uv: Vector2, map_rect: Rect2, viewport_size: Vector2, anchor_ratio: Vector2 = Vector2(0.5, 0.55)) -> void:
	follow_enabled = enabled
	follow_anchor_ratio = anchor_ratio
	if enabled:
		_snap_follow(target_uv, map_rect, viewport_size)

func update_follow(delta: float, target_uv: Vector2, map_rect: Rect2, viewport_size: Vector2) -> void:
	if not follow_enabled or delta <= 0.0:
		return
	var anchor := viewport_size * follow_anchor_ratio
	var target_in_map := map_rect.position + target_uv * map_rect.size
	var desired_pan := anchor - target_in_map * zoom
	var blend := 1.0 - exp(-maxf(follow_smoothing, 0.0) * delta)
	pan = pan.lerp(desired_pan, blend)
	clamp_pan(viewport_size)

func viewport_changed(old_viewport: Vector2, new_viewport: Vector2, old_map_rect: Rect2, new_map_rect: Rect2) -> void:
	if old_viewport.x <= 0.0 or old_viewport.y <= 0.0 or new_viewport.x <= 0.0 or new_viewport.y <= 0.0:
		return
	if follow_enabled:
		# The next update_follow call places the tracked vehicle at the same relative anchor.
		return
	var preserved_uv := screen_to_world(old_viewport * 0.5, old_map_rect)
	pan = new_viewport * 0.5 - (new_map_rect.position + preserved_uv * new_map_rect.size) * zoom
	clamp_pan(new_viewport)

func recenter() -> void:
	pan = Vector2.ZERO
	zoom = 1.0
	follow_enabled = false

func _snap_follow(target_uv: Vector2, map_rect: Rect2, viewport_size: Vector2) -> void:
	var anchor := viewport_size * follow_anchor_ratio
	var target_in_map := map_rect.position + target_uv * map_rect.size
	pan = anchor - target_in_map * zoom
	clamp_pan(viewport_size)
