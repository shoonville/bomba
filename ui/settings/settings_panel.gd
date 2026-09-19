class_name SettingsPanel
extends Control
## Player settings: name, look, volumes, network. Same panel in the menu and the pause overlay.
## Every change applies live and persists through Settings.

signal closed

var _name_edit: LineEdit
var _noray_edit: LineEdit


func _ready() -> void:
	custom_minimum_size = Vector2(560, 0)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.skewed_box(Color(UiStyle.ink(), 0.82), UiStyle.accent(), 0.12, 22))
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var t := UiStyle.label("SETTINGS", 34, UiStyle.accent())
	col.add_child(t)

	var name_row := HBoxContainer.new()
	name_row.add_child(UiStyle.label("NAME", 20))
	_name_edit = UiStyle.line_edit(Settings.player_name, 300)
	_name_edit.text_submitted.connect(func(v: String): Settings.set_value("player_name", v.strip_edges()))
	_name_edit.focus_exited.connect(func(): Settings.set_value("player_name", _name_edit.text.strip_edges()))
	name_row.add_child(_name_edit)
	col.add_child(name_row)

	col.add_child(_slider("MOUSE SENSITIVITY", 0.0005, 0.008, Settings.mouse_sensitivity, 0.0001,
		func(v: float): Settings.set_value("mouse_sensitivity", v)))
	col.add_child(_slider("SCOPED SENSITIVITY", 0.2, 1.0, Settings.ads_sensitivity_multiplier, 0.05,
		func(v: float): Settings.set_value("ads_sensitivity_multiplier", v)))
	var invert := CheckButton.new()
	invert.text = "INVERT LOOK"
	invert.button_pressed = Settings.invert_y
	invert.add_theme_font_size_override("font_size", 20)
	invert.add_theme_color_override("font_color", UiStyle.paper())
	invert.add_theme_color_override("font_outline_color", UiStyle.ink())
	invert.add_theme_constant_override("outline_size", 6)
	invert.toggled.connect(func(on: bool): Settings.set_value("invert_y", on))
	col.add_child(invert)

	col.add_child(_slider("MASTER", 0.0, 1.0, Settings.volume_master, 0.01, func(v: float): Settings.set_value("volume_master", v)))
	col.add_child(_slider("MUSIC", 0.0, 1.0, Settings.volume_music, 0.01, func(v: float): Settings.set_value("volume_music", v)))
	col.add_child(_slider("EFFECTS", 0.0, 1.0, Settings.volume_sfx, 0.01, func(v: float):
		Settings.set_value("volume_sfx", v)
		Audio.play("hitmarker", -4.0)
	))
	col.add_child(_slider("INTERFACE", 0.0, 1.0, Settings.volume_ui, 0.01, func(v: float): Settings.set_value("volume_ui", v)))
	col.add_child(_slider("RENDER SCALE", 0.5, 2.0, Settings.render_scale, 0.25, func(v: float):
		Settings.set_value("render_scale", v)
		Game.apply_render_scale()
	))

	var noray_row := HBoxContainer.new()
	noray_row.add_child(UiStyle.label("RELAY", 20))
	_noray_edit = UiStyle.line_edit(Settings.noray_host, 300)
	_noray_edit.text_submitted.connect(func(v: String): Settings.set_value("noray_host", v.strip_edges()))
	_noray_edit.focus_exited.connect(func(): Settings.set_value("noray_host", _noray_edit.text.strip_edges()))
	noray_row.add_child(_noray_edit)
	col.add_child(noray_row)

	col.add_child(UiStyle.button("DONE", func():
		Settings.save()
		closed.emit()
	))


func _slider(label: String, lo: float, hi: float, value: float, step: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	var l := UiStyle.label(label, 18)
	l.custom_minimum_size = Vector2(230, 36)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(240, 36)
	s.value_changed.connect(on_change)
	row.add_child(s)
	return row
