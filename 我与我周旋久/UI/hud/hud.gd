extends CanvasLayer
## 游戏内 HUD：保留现有血/蓝条，外加回溯冷却与关卡名

signal level_name_toggled(visible_now: bool)

const BARS_SCRIPT := preload("res://player_hud.gd")

var _bars: CanvasLayer
var _name_label: Label
var _name_visible: bool = false
var _name_tween: Tween


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	## 默认先隐藏，避免在开场/主菜单场景短暂显示血条
	set_gameplay_visible(false)
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("level_name_changed"):
		if not gm.level_name_changed.is_connected(update_level_name):
			gm.level_name_changed.connect(update_level_name)
		if "current_level_display_name" in gm:
			update_level_name(str(gm.current_level_display_name))
		## 只有在关卡游玩状态才显示
		if "current_state" in gm and int(gm.current_state) == 1:
			set_gameplay_visible(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_level_name"):
		_show_level_name(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("toggle_level_name"):
		_show_level_name(false)
		get_viewport().set_input_as_handled()


func update_level_name(level_name: String) -> void:
	if _name_label:
		_name_label.text = level_name
	_play_enter_name()


func update_bars(current_hp: float, max_hp: float, current_mp: float, current_mp_max: float) -> void:
	if _bars and _bars.has_method("update_bars"):
		_bars.update_bars(current_hp, max_hp, current_mp, current_mp_max)


## 血蓝条是独立 CanvasLayer，只藏父节点挡不住
func set_gameplay_visible(on: bool) -> void:
	visible = on
	if _bars:
		_bars.visible = on


func _build() -> void:
	_bars = BARS_SCRIPT.new()
	_bars.layer = 10
	add_child(_bars)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(root)

	var top := HBoxContainer.new()
	top.name = "TopBar"
	top.add_theme_constant_override("separation", 16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	var hp_slot := Control.new()
	hp_slot.name = "HealthBar"
	hp_slot.custom_minimum_size = Vector2(170, 70)
	hp_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(hp_slot)

	var mp_slot := Control.new()
	mp_slot.name = "ManaBar"
	mp_slot.custom_minimum_size = Vector2(8, 70)
	mp_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(mp_slot)

	_name_label = Label.new()
	_name_label.name = "LevelNameLabel"
	_name_label.text = ""
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_name_label.modulate.a = 0.0
	top.add_child(_name_label)

	var bottom := HBoxContainer.new()
	bottom.name = "BottomInfo"
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)


func _play_enter_name() -> void:
	if _name_label == null:
		return
	if _name_tween:
		_name_tween.kill()
	_name_label.visible = true
	_name_label.modulate.a = 0.0
	_name_tween = create_tween()
	_name_tween.tween_property(_name_label, "modulate:a", 1.0, 0.5)
	_name_tween.tween_interval(3.0)
	_name_tween.tween_property(_name_label, "modulate:a", 0.0, 1.0)


func _show_level_name(show_now: bool) -> void:
	if _name_label == null:
		return
	if _name_tween:
		_name_tween.kill()
	_name_visible = show_now
	_name_tween = create_tween()
	_name_tween.tween_property(_name_label, "modulate:a", 1.0 if show_now else 0.0, 0.15)
	level_name_toggled.emit(show_now)
