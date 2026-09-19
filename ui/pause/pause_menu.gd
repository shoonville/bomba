class_name PauseMenu
extends Control
## In-match overlay (Esc). Never pauses the tree: the match keeps running for everyone else.

signal resumed
signal left

var _settings: SettingsPanel
var _buttons: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UiStyle.ink(), 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var title := UiStyle.title("PAUSED", 84)
	title.position = Vector2(80, 60)
	add_child(title)
	UiStyle.slam(title)
	_buttons = VBoxContainer.new()
	_buttons.position = Vector2(100, 220)
	_buttons.custom_minimum_size = Vector2(360, 0)
	_buttons.add_theme_constant_override("separation", 12)
	add_child(_buttons)
	_buttons.add_child(UiStyle.button("RESUME", func(): resumed.emit(), 26))
	_buttons.add_child(UiStyle.button("SETTINGS", _toggle_settings, 26))
	_buttons.add_child(UiStyle.button("LEAVE MATCH", func(): left.emit(), 26, Palette.hud_colour("danger")))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _toggle_settings() -> void:
	if _settings != null:
		_settings.queue_free()
		_settings = null
		return
	_settings = SettingsPanel.new()
	_settings.position = Vector2(520, 120)
	_settings.closed.connect(_toggle_settings)
	add_child(_settings)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		resumed.emit()
		get_viewport().set_input_as_handled()
