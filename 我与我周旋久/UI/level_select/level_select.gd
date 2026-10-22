extends CanvasLayer
## 关卡选择：只发信号，解锁状态由 GameManager 提供

signal level_chosen(level_id: int)
signal back_requested

const LEVEL_TITLES := {
	1: "第一关  初入林间",
	2: "第二关  夜路渐深",
	3: "第三关  裂谷试炼",
	4: "第四关  地下遗迹",
	5: "第五关  极限逃生",
}

@onready var list: VBoxContainer = $CenterContainer/VBoxContainer/LevelList
@onready var btn_back: Button = $CenterContainer/VBoxContainer/BtnBack


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiStyle.apply_button(btn_back)
	btn_back.pressed.connect(func() -> void: back_requested.emit())
	_build_level_buttons()
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		if gm.has_method("start_level") and not level_chosen.is_connected(gm.start_level):
			level_chosen.connect(gm.start_level)
		if gm.has_method("go_to_main_menu") and not back_requested.is_connected(gm.go_to_main_menu):
			back_requested.connect(gm.go_to_main_menu)
		if gm.has_method("change_state"):
			gm.change_state(0)
	await get_tree().process_frame
	var first := list.get_child(0) as Button
	if first:
		first.grab_focus()


func _build_level_buttons() -> void:
	for ch in list.get_children():
		ch.queue_free()
	var gm := get_node_or_null("/root/GameManager")
	var unlocked := 1
	if gm and gm.has_method("get_unlocked_max"):
		unlocked = int(gm.get_unlocked_max())
	var buttons: Array = []
	for i in range(1, 6):
		var btn := Button.new()
		btn.name = "BtnLevel_%d" % i
		var open := i <= unlocked
		btn.text = str(LEVEL_TITLES.get(i, "第%d关" % i))
		if not open:
			btn.text += "  （未解锁）"
			btn.disabled = true
			btn.tooltip_text = "通关上一关后解锁"
		UiStyle.apply_button(btn, 360)
		var lid := i
		if open:
			btn.pressed.connect(func() -> void: level_chosen.emit(lid))
		list.add_child(btn)
		buttons.append(btn)
	buttons.append(btn_back)
	UiStyle.focus_chain(buttons)
