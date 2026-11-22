extends Node

signal theme_changed(mode: String)

const SETTINGS_PATH := "user://idm_user_settings.json"
var mode := "dark"

func _ready() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed := JSON.new()
	if parsed.parse(file.get_as_text()) == OK and typeof(parsed.data) == TYPE_DICTIONARY:
		var stored := str(parsed.data.get("theme", "dark"))
		mode = stored if stored in ["dark", "light"] else "dark"

func toggle() -> String:
	mode = "light" if mode == "dark" else "dark"
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"theme": mode}))
	theme_changed.emit(mode)
	return mode

func color(token: String) -> Color:
	var dark := mode == "dark"
	var palette := {
		"map_background": "#091722" if dark else "#e7eff1",
		"map_block": "#102632" if dark else "#f7fafb",
		"map_block_alt": "#112b35" if dark else "#edf4f5",
		"map_park": "#15362f" if dark else "#cce5d5",
		"map_road_outline": "#07131c" if dark else "#d2dde1",
		"map_road": "#284354" if dark else "#8499a2",
		"map_label": "#7894a5" if dark else "#546c78",
		"panel": "#102433" if dark else "#f9fcfd",
		"panel_border": "#1b3546" if dark else "#c7d7dd",
		"button": "#183246" if dark else "#e1edf1",
		"button_hover": "#244b60" if dark else "#d3e5ea",
		"button_text": "#eaf2f8" if dark else "#15313e",
		"muted": "#91a8ba" if dark else "#566f7c",
		"text": "#f1f6fa" if dark else "#172d38",
		"accent": "#45d9ec" if dark else "#087d91",
		"accent_fill": "#48d9e9" if dark else "#20b8cc",
		"status": "#53d5ba" if dark else "#16866d",
		"rider": "#70e4f3" if dark else "#07889b",
		"rider_back": "#06242e" if dark else "#d0eef2",
		"surface": "#142c3b" if dark else "#eef5f7",
		"selected": "#123c4a" if dark else "#d2f1f4",
		"warning": "#f0b95b" if dark else "#986116",
		"positive": "#53d5ba" if dark else "#16866d",
	}
	return Color(str(palette.get(token, "#091722")))

## Shared UI rhythm and typography tokens in CSS-pixel equivalents.
func space(token: String) -> int:
	return {"xs": 4, "sm": 8, "md": 12, "lg": 16, "xl": 20}.get(token, 12)

func font_size(token: String) -> int:
	return {"caption": 11, "body": 14, "section": 16, "title": 20, "metric": 18}.get(token, 14)

func corner_radius(token: String) -> int:
	return {"control": 12, "card": 16, "sheet": 22, "pill": 999}.get(token, 14)

func control_height(token: String) -> int:
	return {"compact": 44, "standard": 48, "large": 52}.get(token, 48)

func resolve_existing_text(original: Color) -> Color:
	if mode == "dark":
		return original
	if original.g > 0.75 and original.b > 0.75:
		return color("text")
	if original.g > 0.65 and original.b > 0.6:
		return color("muted")
	if original.g > original.r * 1.4 and original.b < original.g:
		return color("status")
	if original.b > original.r * 1.1:
		return color("accent")
	return original
