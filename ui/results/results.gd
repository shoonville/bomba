extends Control
## Results screen: ranked list on the swirl, one accent, a button back to the lobby.

var _result: MinigameResult
var _list: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(UiStyle.swirl_background("counter", "field"))
	var title := UiStyle.title("RESULTS", 96)
	title.position = Vector2(64, 40)
	add_child(title)
	UiStyle.slam(title)
	_list = VBoxContainer.new()
	_list.position = Vector2(90, 220)
	_list.add_theme_constant_override("separation", 10)
	add_child(_list)
	var btn := UiStyle.button("BACK TO LOBBY", func():
		Game.transition(func():
			queue_free()
			Game.show_menu()
		)
	, 26)
	btn.position = Vector2(90, 760)
	add_child(btn)


func show_result(result: MinigameResult) -> void:
	_result = result
	var i := 0
	for r in result.rankings:
		var first := int(r["rank"]) == 1
		var value := str(r["label"]) if r.has("label") else "%d" % int(r["score"])
		var l := UiStyle.label("#%d   %s   %s" % [int(r["rank"]), str(r["display_name"]).to_upper(), value],
			44 if first else 30, Palette.hud_colour("score") if first else UiStyle.paper())
		_list.add_child(l)
		UiStyle.slam(l, 0.12 + 0.08 * i)
		i += 1
