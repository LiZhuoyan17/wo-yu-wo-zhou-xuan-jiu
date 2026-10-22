extends CanvasLayer
## 主菜单：只发信号；退出由 GameManager 监听后 quit

signal start_game_requested
signal continue_game_requested
signal level_select_requested
signal settings_requested
signal quit_requested

const SAVE_PATH := "user://save_data.json"

@onready var btn_start: Button = $CenterContainer/VBoxContainer/BtnStart
@onready var btn_continue: Button = $CenterContainer/VBoxContainer/BtnContinue
@onready var btn_select: Button = $CenterContainer/VBoxContainer/BtnLevelSelect
@onready var btn_settings: Button = $CenterContainer/VBoxContainer/BtnSettings
@onready var btn_quit: Button = $CenterContainer/VBoxContainer/BtnQuit
@onready var settings_panel: Control = $SettingsPanel


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiStyle.apply_button(btn_start)
	UiStyle.apply_button(btn_continue)
	UiStyle.apply_button(btn_select)
	UiStyle.apply_button(btn_settings)
	UiStyle.apply_button(btn_quit)
	_refresh_continue()
	btn_start.pressed.connect(func() -> void: start_game_requested.emit())
	btn_continue.pressed.connect(_on_continue)
	btn_select.pressed.connect(func() -> void: level_select_requested.emit())
	btn_settings.pressed.connect(_on_settings)
	btn_quit.pressed.connect(func() -> void: quit_requested.emit())
	if settings_panel:
		settings_panel.visible = false
		var close_btn := settings_panel.get_node_or_null("Panel/VBox/BtnClose") as Button
		if close_btn:
			UiStyle.apply_button(close_btn, 160)
			close_btn.pressed.connect(func() -> void: settings_panel.visible = false)
		var tutorial_btn := settings_panel.get_node_or_null("Panel/VBox/BtnTutorial") as Button
		if tutorial_btn:
			UiStyle.apply_button(tutorial_btn, 160)
			tutorial_btn.pressed.connect(_on_settings_tutorial)
		var vol := settings_panel.get_node_or_null("Panel/VBox/VolumeSlider") as HSlider
		if vol:
			var mm := get_node_or_null("/root/MusicManager")
			if mm and mm.has_method("get_volume_linear"):
				vol.value = float(mm.get_volume_linear())
			vol.value_changed.connect(_on_volume_changed)
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		if not start_game_requested.is_connected(gm.start_game):
			start_game_requested.connect(gm.start_game)
		if gm.has_method("continue_game") and not continue_game_requested.is_connected(gm.continue_game):
			continue_game_requested.connect(gm.continue_game)
		if gm.has_method("quit_game") and not quit_requested.is_connected(gm.quit_game):
			quit_requested.connect(gm.quit_game)
		if gm.has_method("go_to_level_select") and not level_select_requested.is_connected(gm.go_to_level_select):
			level_select_requested.connect(gm.go_to_level_select)
		if gm.has_method("change_state"):
			gm.change_state(0) ## GameState.MENU
	var mm := get_node_or_null("/root/MusicManager")
	if mm and mm.has_method("play_menu"):
		mm.play_menu()
	await get_tree().process_frame
	UiStyle.focus_chain([btn_start, btn_continue, btn_select, btn_settings, btn_quit])


func _refresh_continue() -> void:
	var has_save := FileAccess.file_exists(SAVE_PATH)
	btn_continue.disabled = not has_save
	btn_continue.tooltip_text = "" if has_save else "暂无存档"


func _on_continue() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		continue_game_requested.emit()
	else:
		btn_continue.disabled = true


func _on_settings() -> void:
	settings_requested.emit()
	if settings_panel:
		settings_panel.visible = true


func _on_volume_changed(value: float) -> void:
	var mm := get_node_or_null("/root/MusicManager")
	if mm and mm.has_method("set_volume_linear"):
		mm.set_volume_linear(value)
	var sfx := get_node_or_null("/root/SfxManager")
	if sfx and sfx.has_method("set_volume_linear"):
		sfx.set_volume_linear(value)


func _on_settings_tutorial() -> void:
	if settings_panel:
		settings_panel.visible = false
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("open_control_tutorial_review"):
		gm.open_control_tutorial_review()
