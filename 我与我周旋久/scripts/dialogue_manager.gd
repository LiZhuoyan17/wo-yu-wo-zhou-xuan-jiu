extends CanvasLayer
## 剧情对话：打字机逐字显示，对话期间暂停游戏

signal dialogue_started
signal dialogue_finished

const CHAR_INTERVAL := 0.04
const PUNCT_PAUSE := 0.15
const PUNCTUATION := "。！？，、；：…——"

@onready var panel: PanelContainer = $DialoguePanel
@onready var speaker_label: Label = $DialoguePanel/MarginContainer/VBoxContainer/SpeakerLabel
@onready var text_label: RichTextLabel = $DialoguePanel/MarginContainer/VBoxContainer/TextLabel
@onready var continue_hint: Label = $DialoguePanel/MarginContainer/VBoxContainer/ContinueHint

var _lines: Array = []
var _index: int = -1
var _active: bool = false
var _typing: bool = false
var _full_text: String = ""
var _visible_count: int = 0
var _wait: float = 0.0
var _paused_by_us: bool = false
## 本存档内只要跳过一次打字机，隐藏结局不再触发
var never_skipped_dialogue: bool = true
## 教学/敌人介绍里跳过打字，不计入隐藏结局
var _affects_hidden_ending: bool = true


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_panel_style()
	if panel:
		panel.visible = false
	if continue_hint:
		continue_hint.visible = false
	visible = true


func is_dialogue_active() -> bool:
	return _active


func start_dialogue(data: Array, affects_hidden_ending: bool = true) -> void:
	if data.is_empty():
		return
	if _active:
		_finish(false)
	_affects_hidden_ending = affects_hidden_ending
	_lines = data.duplicate()
	_index = -1
	_active = true
	_typing = false
	if panel:
		panel.visible = true
	if continue_hint:
		continue_hint.visible = false
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_us = true
	else:
		_paused_by_us = false
	dialogue_started.emit()
	_advance_line()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if not (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select")):
		return
	get_viewport().set_input_as_handled()
	if _typing:
		skip_typing()
	else:
		_advance_line()


func skip_typing() -> void:
	if not _typing:
		return
	if _affects_hidden_ending and never_skipped_dialogue:
		never_skipped_dialogue = false
		var gm := get_node_or_null("/root/GameManager")
		if gm and gm.has_method("persist_dialogue_skip_flag"):
			gm.persist_dialogue_skip_flag()
	_reveal_all()


func _process(delta: float) -> void:
	if not _active or not _typing:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_visible_count += 1
	text_label.visible_characters = _visible_count
	if _visible_count >= _full_text.length():
		_reveal_all()
		return
	_wait = CHAR_INTERVAL
	var just := _full_text[_visible_count - 1]
	if PUNCTUATION.contains(just):
		_wait += PUNCT_PAUSE


func _advance_line() -> void:
	_index += 1
	if _index >= _lines.size():
		_finish(true)
		return
	var entry: Dictionary = _parse_line(_lines[_index])
	speaker_label.text = str(entry.get("speaker", ""))
	speaker_label.visible = speaker_label.text != ""
	_full_text = str(entry.get("text", ""))
	text_label.bbcode_enabled = true
	text_label.text = _full_text
	text_label.visible_characters = 0
	_visible_count = 0
	_wait = 0.0
	_typing = true
	if continue_hint:
		continue_hint.visible = false


func _reveal_all() -> void:
	_typing = false
	_visible_count = _full_text.length()
	text_label.visible_characters = -1
	if continue_hint:
		continue_hint.visible = true


func _finish(emit_done: bool) -> void:
	_active = false
	_typing = false
	_lines.clear()
	_index = -1
	if panel:
		panel.visible = false
	if continue_hint:
		continue_hint.visible = false
	if _paused_by_us and get_tree():
		get_tree().paused = false
	_paused_by_us = false
	if emit_done:
		dialogue_finished.emit()


func _parse_line(raw) -> Dictionary:
	if raw is Dictionary:
		var d: Dictionary = raw
		return {
			"speaker": str(d.get("speaker", d.get("name", ""))),
			"text": str(d.get("text", d.get("line", ""))),
		}
	if raw is Array and raw.size() >= 1:
		if raw.size() >= 2:
			return {"speaker": str(raw[0]), "text": str(raw[1])}
		return {"speaker": "", "text": str(raw[0])}
	return {"speaker": "", "text": str(raw)}


func _apply_panel_style() -> void:
	if panel == null:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.75)
	box.set_corner_radius_all(10)
	box.set_border_width_all(1)
	box.border_color = Color(0.35, 0.35, 0.4, 0.8)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", box)
