extends CanvasLayer
## 暂停菜单：只发信号，不直接改关卡逻辑

signal resume_requested
signal restart_requested
signal back_to_menu_requested
signal tutorial_requested

@onready var overlay: ColorRect = $Overlay
@onready var panel: Control = $CenterContainer/PanelContainer
@onready var btn_resume: Button = $CenterContainer/PanelContainer/VBoxContainer/BtnResume
@onready var btn_restart: Button = $CenterContainer/PanelContainer/VBoxContainer/BtnRestart
@onready var btn_tutorial: Button = $CenterContainer/PanelContainer/VBoxContainer/BtnTutorial
@onready var btn_menu: Button = $CenterContainer/PanelContainer/VBoxContainer/BtnBackToMenu

var _open: bool = false
var _anim: Tween


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# REPLACE_WITH_ART: 暂停面板背景图
	var panel_sb := UiStyle.make_flat(Color(0.16, 0.16, 0.2, 0.95), Color(0.4, 0.4, 0.45))
	panel.add_theme_stylebox_override("panel", panel_sb)
	UiStyle.apply_button(btn_resume)
	UiStyle.apply_button(btn_restart)
	UiStyle.apply_button(btn_tutorial)
	UiStyle.apply_button(btn_menu)
	btn_resume.pressed.connect(func() -> void: resume_requested.emit())
	btn_restart.pressed.connect(func() -> void: restart_requested.emit())
	btn_tutorial.pressed.connect(func() -> void: tutorial_requested.emit())
	btn_menu.pressed.connect(func() -> void: back_to_menu_requested.emit())


func is_open() -> bool:
	return _open


func open_menu() -> void:
	if _open:
		return
	_open = true
	visible = true
	if _anim:
		_anim.kill()
	overlay.modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	panel.pivot_offset = panel.size * 0.5
	_anim = create_tween()
	_anim.set_parallel(true)
	_anim.tween_property(overlay, "modulate:a", 0.6, 0.15)
	_anim.tween_property(panel, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT)
	await get_tree().process_frame
	UiStyle.focus_chain([btn_resume, btn_restart, btn_tutorial, btn_menu])


func close_menu() -> void:
	if not _open:
		return
	_open = false
	if _anim:
		_anim.kill()
	_anim = create_tween()
	_anim.set_parallel(true)
	_anim.tween_property(overlay, "modulate:a", 0.0, 0.15)
	_anim.tween_property(panel, "scale", Vector2(0.9, 0.9), 0.15).set_ease(Tween.EASE_IN)
	await _anim.finished
	if not _open:
		visible = false
