extends CanvasLayer
## 通关结算：只发信号

signal next_level_requested
signal back_to_menu_requested
signal level_select_requested
signal retry_requested

@onready var overlay: ColorRect = $Overlay
@onready var panel: Control = $CenterContainer/PanelContainer
@onready var time_label: Label = $CenterContainer/PanelContainer/VBoxContainer/StatsContainer/TimeLabel
@onready var death_label: Label = $CenterContainer/PanelContainer/VBoxContainer/StatsContainer/DeathCountLabel
@onready var loot_label: Label = $CenterContainer/PanelContainer/VBoxContainer/StatsContainer/CollectiblesLabel
@onready var btn_next: Button = $CenterContainer/PanelContainer/VBoxContainer/BtnNextLevel
@onready var btn_home: Button = $CenterContainer/PanelContainer/VBoxContainer/BtnHome
@onready var btn_select: Button = $CenterContainer/PanelContainer/VBoxContainer/BtnLevelSelect
@onready var btn_retry: Button = $CenterContainer/PanelContainer/VBoxContainer/BtnRetry

var _open: bool = false
var _base_y: float = 0.0


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# REPLACE_WITH_ART: 结算面板背景图
	var panel_sb := UiStyle.make_flat(Color(0.28, 0.22, 0.1, 0.95), Color(0.85, 0.7, 0.28))
	panel.add_theme_stylebox_override("panel", panel_sb)
	UiStyle.apply_button(btn_next)
	UiStyle.apply_button(btn_home)
	UiStyle.apply_button(btn_select)
	UiStyle.apply_button(btn_retry)
	btn_next.pressed.connect(func() -> void: next_level_requested.emit())
	btn_home.pressed.connect(func() -> void: back_to_menu_requested.emit())
	btn_select.pressed.connect(func() -> void: level_select_requested.emit())
	btn_retry.pressed.connect(func() -> void: retry_requested.emit())


func is_open() -> bool:
	return _open


func update_stats(time_sec: float, deaths: int, collected: int, total: int) -> void:
	var m := int(time_sec) / 60
	var s := int(time_sec) % 60
	time_label.text = "用时：%02d:%02d" % [m, s]
	death_label.text = "死亡次数：%d" % deaths
	loot_label.text = "收集品：%d/%d" % [collected, total]


func open_screen() -> void:
	_open = true
	visible = true
	await get_tree().process_frame
	_base_y = panel.position.y
	panel.position.y = _base_y + 100.0
	var tw := create_tween()
	tw.tween_property(panel, "position:y", _base_y, 0.4).set_ease(Tween.EASE_OUT)
	UiStyle.focus_chain([btn_next, btn_home, btn_select, btn_retry])


func close_screen() -> void:
	_open = false
	visible = false
