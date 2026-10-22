extends CanvasLayer
## 死亡结算：只发信号

signal retry_requested
signal back_to_menu_requested
signal level_select_requested

@onready var overlay: ColorRect = $Overlay
@onready var death_label: Label = $CenterContainer/VBoxContainer/DeathLabel
@onready var btn_home: Button = $CenterContainer/VBoxContainer/BtnHome
@onready var btn_select: Button = $CenterContainer/VBoxContainer/BtnLevelSelect
@onready var btn_retry: Button = $CenterContainer/VBoxContainer/BtnRetry

var _open: bool = false


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	UiStyle.apply_button(btn_home)
	UiStyle.apply_button(btn_select)
	UiStyle.apply_button(btn_retry)
	btn_home.pressed.connect(func() -> void: back_to_menu_requested.emit())
	btn_select.pressed.connect(func() -> void: level_select_requested.emit())
	btn_retry.pressed.connect(func() -> void: retry_requested.emit())


func is_open() -> bool:
	return _open


func open_screen() -> void:
	_open = true
	visible = true
	overlay.modulate = Color(1, 1, 1, 0)
	death_label.scale = Vector2(2, 2)
	death_label.pivot_offset = death_label.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(overlay, "modulate:a", 1.0, 0.5)
	tw.tween_property(death_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().process_frame
	UiStyle.focus_chain([btn_home, btn_select, btn_retry])


func close_screen() -> void:
	_open = false
	visible = false
