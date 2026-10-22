extends CanvasLayer
## 第一关序章后的操作教学：按对应键/组合键推进，不暂停游戏

signal tutorial_finished

const GOLD := Color(0.85, 0.7, 0.28, 1.0)
const MUTED := Color(0.72, 0.72, 0.76, 1.0)

const STEPS: Array = [
	{
		"id": "move",
		"title": "迈出第一步",
		"hint": "按  A  /  D  左右走动。",
		"keys": "A　　D",
	},
	{
		"id": "jump",
		"title": "离开地面",
		"hint": "按  W  或  空格  跳跃。",
		"keys": "W　　空格",
	},
	{
		"id": "double_jump",
		"title": "再借一次力",
		"hint": "先跳起来，在空中再按一次  W  或  空格。",
		"keys": "跳 → 再跳",
	},
	{
		"id": "attack",
		"title": "近身",
		"hint": "按  J  挥灯攻击。短时间内连按两次，突进会更远。",
		"keys": "J　　J+J",
	},
	{
		"id": "shoot",
		"title": "灯笼之光",
		"hint": "按  L  或  鼠标右键  射出光球。",
		"keys": "L　　右键",
	},
	{
		"id": "aim_up",
		"title": "斜上瞄准",
		"hint": "在约 0.3 秒内按下  W + A  或  W + D，再按  L。\n不必同时按死。扇区内有敌人时，光球会对准它。",
		"keys": "W + A/D + L",
	},
	{
		"id": "aim_down",
		"title": "斜下瞄准",
		"hint": "在约 0.3 秒内按下  S + A  或  S + D，再按  L。",
		"keys": "S + A/D + L",
	},
	{
		"id": "rewind",
		"title": "与影子重逢",
		"hint": "先走动几步，再按  K。\n你会回到片刻之前站过的地方。",
		"keys": "K",
	},
]

const SUMMARY := "梯子：贴着梯子时  W / S  攀爬，空格跳离。\n在梯子与平台交界处连按两下 W，也可以跳上去。\nEsc 暂停　　按住 Tab 查看关卡名"

var _index: int = 0
var _done: bool = false
var _review: bool = false
var _panel: PanelContainer
var _step_label: Label
var _title_label: Label
var _hint_label: Label
var _keys_label: Label
var _skip_btn: Button
var _start_btn: Button
var _was_airborne: bool = false
var _block_layer: ColorRect


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_show_step(0)


func start_review() -> void:
	_review = true
	_index = 0
	_done = false
	if _skip_btn:
		_skip_btn.text = "关闭"
		_skip_btn.visible = true
	if _block_layer:
		_block_layer.mouse_filter = Control.MOUSE_FILTER_STOP
		_block_layer.color = Color(0, 0, 0, 0.35)
	_show_step(0)


func _process(_delta: float) -> void:
	if _done or _review:
		return
	var tree := get_tree()
	if tree and tree.paused:
		return
	var dm := get_node_or_null("/root/DialogueManager")
	if dm and dm.has_method("is_dialogue_active") and dm.is_dialogue_active():
		return
	if _index < 0 or _index >= STEPS.size():
		return
	if _step_completed(str(STEPS[_index].get("id", ""))):
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if not _review or _done:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		get_viewport().set_input_as_handled()
		_advance()


func _step_completed(step_id: String) -> bool:
	match step_id:
		"move":
			return _pressed_any(["ui_left", "ui_right"])
		"jump":
			return Input.is_action_just_pressed("ui_accept")
		"double_jump":
			var p := _player()
			var airborne := p != null and not p.is_on_floor()
			var jumped := Input.is_action_just_pressed("ui_accept")
			var ok := jumped and (airborne or _was_airborne)
			_was_airborne = airborne
			return ok
		"attack":
			return Input.is_action_just_pressed("attack")
		"shoot":
			return Input.is_action_just_pressed("shoot_orb")
		"aim_up":
			if not Input.is_action_just_pressed("shoot_orb"):
				return false
			var p_up := _player()
			if p_up and p_up.has_method("wants_diagonal_up_shot"):
				return p_up.wants_diagonal_up_shot()
			return _hold_up() and _hold_side()
		"aim_down":
			if not Input.is_action_just_pressed("shoot_orb"):
				return false
			var p_down := _player()
			if p_down and p_down.has_method("wants_diagonal_down_shot"):
				return p_down.wants_diagonal_down_shot()
			return _hold_down() and _hold_side()
		"rewind":
			return Input.is_action_just_pressed("rewind")
	return false


func _advance() -> void:
	_index += 1
	if _index >= STEPS.size():
		_show_summary()
		return
	_show_step(_index)


func _show_step(i: int) -> void:
	_index = i
	_was_airborne = false
	var step: Dictionary = STEPS[i]
	_step_label.text = "操作教学  %d / %d" % [i + 1, STEPS.size()]
	_title_label.text = str(step.get("title", ""))
	_hint_label.text = str(step.get("hint", ""))
	_keys_label.text = str(step.get("keys", ""))
	if _start_btn:
		_start_btn.visible = false
	if _review:
		_hint_label.text += "\n（按 空格 看下一项）"


func _show_summary() -> void:
	_done = true
	_step_label.text = "操作教学  完成"
	_title_label.text = "灯火会跟着你"
	_hint_label.text = SUMMARY
	_keys_label.text = "Esc　　Tab"
	if _start_btn:
		_start_btn.visible = true
		_start_btn.text = "关闭" if _review else "开始前行"
		_start_btn.grab_focus()
	if _skip_btn:
		_skip_btn.visible = false


func _finish() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("mark_control_tutorial_done") and not _review:
		gm.mark_control_tutorial_done()
	tutorial_finished.emit()
	queue_free()


func _player() -> CharacterBody2D:
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_player"):
		return gm.get_player() as CharacterBody2D
	var tree := get_tree()
	if tree:
		return tree.get_first_node_in_group("player") as CharacterBody2D
	return null


func _pressed_any(actions: Array) -> bool:
	for action in actions:
		if Input.is_action_pressed(str(action)):
			return true
	return false


func _hold_up() -> bool:
	return Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)


func _hold_down() -> bool:
	return Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)


func _hold_side() -> bool:
	return (
		Input.is_action_pressed("ui_left")
		or Input.is_action_pressed("ui_right")
		or Input.is_physical_key_pressed(KEY_A)
		or Input.is_physical_key_pressed(KEY_D)
		or Input.is_physical_key_pressed(KEY_LEFT)
		or Input.is_physical_key_pressed(KEY_RIGHT)
	)


func _build_ui() -> void:
	_block_layer = ColorRect.new()
	_block_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_block_layer.color = Color(0, 0, 0, 0)
	_block_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_block_layer)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 28)
	root.add_theme_constant_override("margin_right", 28)
	root.add_theme_constant_override("margin_bottom", 28)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bottom := VBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(520, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.04, 0.07, 0.86)
	box.set_corner_radius_all(10)
	box.set_border_width_all(1)
	box.border_color = Color(0.85, 0.7, 0.28, 0.45)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 12
	box.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", box)
	bottom.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)

	_step_label = Label.new()
	_step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_label.add_theme_color_override("font_color", GOLD)
	_step_label.add_theme_font_size_override("font_size", 14)
	header.add_child(_step_label)

	_skip_btn = Button.new()
	_skip_btn.text = "跳过教学"
	_skip_btn.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_button(_skip_btn, 96)
	_skip_btn.custom_minimum_size = Vector2(96, 28)
	_skip_btn.add_theme_font_size_override("font_size", 13)
	_skip_btn.pressed.connect(_finish)
	header.add_child(_skip_btn)

	_title_label = Label.new()
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.9, 1.0))
	_title_label.add_theme_font_size_override("font_size", 22)
	col.add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(480, 0)
	_hint_label.add_theme_color_override("font_color", MUTED)
	_hint_label.add_theme_font_size_override("font_size", 16)
	col.add_child(_hint_label)

	_keys_label = Label.new()
	_keys_label.add_theme_color_override("font_color", GOLD)
	_keys_label.add_theme_font_size_override("font_size", 18)
	col.add_child(_keys_label)

	_start_btn = Button.new()
	_start_btn.visible = false
	_start_btn.text = "开始前行"
	UiStyle.apply_button(_start_btn, 180)
	_start_btn.pressed.connect(_finish)
	col.add_child(_start_btn)
