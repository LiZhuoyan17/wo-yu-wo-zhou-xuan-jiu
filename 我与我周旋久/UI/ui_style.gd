extends RefCounted
class_name UiStyle
## 纯色按钮三态。# REPLACE_WITH_ART: 换成 TextureButton / StyleBoxTexture

static func make_flat(bg: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_content_margin_all(10)
	box.set_corner_radius_all(4)
	return box


static func apply_button(btn: Button, min_w: float = 260.0) -> void:
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = Vector2(min_w, 44)
	# REPLACE_WITH_ART: 按钮背景图（普通态/悬停态/按下态）
	btn.add_theme_stylebox_override("normal", make_flat(Color(0.22, 0.22, 0.26, 1.0)))
	btn.add_theme_stylebox_override("hover", make_flat(Color(0.48, 0.48, 0.52, 1.0)))
	btn.add_theme_stylebox_override("pressed", make_flat(Color(0.95, 0.95, 0.95, 1.0)))
	btn.add_theme_stylebox_override("focus", make_flat(Color(0.48, 0.48, 0.52, 1.0), Color(0.85, 0.85, 1.0)))
	btn.add_theme_stylebox_override("disabled", make_flat(Color(0.14, 0.14, 0.16, 1.0)))
	btn.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.12, 0.12, 0.14))
	btn.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.48))
	btn.add_theme_font_size_override("font_size", 18)
	if not bool(btn.get_meta("sfx_wired", false)):
		btn.set_meta("sfx_wired", true)
		btn.mouse_entered.connect(_play_ui.bind("ui_select"))
		btn.focus_entered.connect(_play_ui.bind("ui_select"))
		btn.pressed.connect(_play_ui.bind("ui_press"))


static func _play_ui(kind: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var sfx := tree.root.get_node_or_null("SfxManager")
	if sfx and sfx.has_method("play"):
		sfx.play(kind)


static func focus_chain(buttons: Array) -> void:
	var n := buttons.size()
	if n <= 0:
		return
	for i in n:
		var cur: Button = buttons[i]
		var prev: Button = buttons[(i - 1 + n) % n]
		var next: Button = buttons[(i + 1) % n]
		cur.focus_neighbor_top = cur.get_path_to(prev)
		cur.focus_neighbor_bottom = cur.get_path_to(next)
		cur.focus_previous = cur.get_path_to(prev)
		cur.focus_next = cur.get_path_to(next)
	(buttons[0] as Button).grab_focus()
