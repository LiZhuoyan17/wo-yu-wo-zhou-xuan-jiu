extends ColorRect
## 第五关通关后的结局画面

const DEEP_BLUE := Color(0.04, 0.07, 0.18, 1.0)
const GOLD := Color(0.85, 0.7, 0.28, 1.0)
const WAIT_AFTER_TEXT := 3.0

@onready var title_label: Label = $TitleLabel
@onready var subtitle_label: Label = $SubtitleLabel
@onready var fin_label: Label = $FinLabel
@onready var hidden_label_1: Label = $HiddenLabel1
@onready var hidden_label_2: Label = $HiddenLabel2
@onready var hint_label: Label = $HintLabel
@onready var anim: AnimationPlayer = $AnimationPlayer

var _can_return: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.BLACK
	_set_label_alpha(title_label, 0.0)
	_set_label_alpha(subtitle_label, 0.0)
	_set_label_alpha(fin_label, 0.0)
	_set_label_alpha(hidden_label_1, 0.0)
	_set_label_alpha(hidden_label_2, 0.0)
	_set_label_alpha(hint_label, 0.0)
	if hint_label:
		hint_label.visible = false
	_ensure_animation()
	_play_music()
	_play_sequence()


func _play_music() -> void:
	var mm := get_node_or_null("/root/MusicManager")
	if mm and mm.has_method("play_ending"):
		mm.play_ending()


func _unhandled_input(event: InputEvent) -> void:
	if not _can_return:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_return_to_menu()
	elif event is InputEventMouseButton and event.pressed:
		_return_to_menu()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		_return_to_menu()


func _play_sequence() -> void:
	if anim and anim.has_animation("play_ending"):
		anim.play("play_ending")
		await anim.animation_finished
	else:
		await _tween_fallback()

	if _should_show_hidden_ending():
		await _fade_label(hidden_label_1, 1.6)
		await _fade_label(hidden_label_2, 1.6)

	await get_tree().create_timer(WAIT_AFTER_TEXT).timeout
	if hint_label:
		hint_label.visible = true
	await _fade_label(hint_label, 0.8)
	_can_return = true


func _should_show_hidden_ending() -> bool:
	var dm := get_node_or_null("/root/DialogueManager")
	return dm != null and bool(dm.get("never_skipped_dialogue"))


func _return_to_menu() -> void:
	_can_return = false
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("go_to_main_menu"):
		gm.go_to_main_menu()
	else:
		get_tree().change_scene_to_file("res://ui/main_menu/MainMenu.tscn")


func _ensure_animation() -> void:
	if anim == null:
		return
	if anim.has_animation("play_ending"):
		return
	var animation := Animation.new()
	animation.length = 8.0
	_add_color_track(animation, NodePath(".:color"), [
		[0.0, Color.BLACK],
		[3.0, DEEP_BLUE],
	])
	_add_modulate_track(animation, NodePath("TitleLabel:modulate"), 3.0, 5.0, GOLD)
	_add_modulate_track(animation, NodePath("SubtitleLabel:modulate"), 5.0, 7.0, Color.WHITE)
	_add_modulate_track(animation, NodePath("FinLabel:modulate"), 7.0, 8.0, Color(0.55, 0.55, 0.58, 1.0))
	var lib := AnimationLibrary.new()
	lib.add_animation("play_ending", animation)
	if anim.has_animation_library(""):
		anim.remove_animation_library("")
	anim.add_animation_library("", lib)


func _add_color_track(animation: Animation, path: NodePath, keys: Array) -> void:
	var idx := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(idx, path)
	animation.value_track_set_update_mode(idx, Animation.UPDATE_CONTINUOUS)
	for key in keys:
		animation.track_insert_key(idx, key[0], key[1])


func _add_modulate_track(animation: Animation, path: NodePath, from_sec: float, to_sec: float, col: Color) -> void:
	var idx := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(idx, path)
	animation.value_track_set_update_mode(idx, Animation.UPDATE_CONTINUOUS)
	var hidden := Color(col.r, col.g, col.b, 0.0)
	animation.track_insert_key(idx, from_sec, hidden)
	animation.track_insert_key(idx, to_sec, col)


func _tween_fallback() -> void:
	var tw := create_tween()
	tw.tween_property(self, "color", DEEP_BLUE, 3.0)
	await tw.finished
	await _fade_label(title_label, 2.0)
	await _fade_label(subtitle_label, 2.0)
	await _fade_label(fin_label, 1.0)


func _fade_label(label: Label, duration: float) -> void:
	if label == null:
		return
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, duration)
	await tw.finished


func _set_label_alpha(label: Label, alpha: float) -> void:
	if label == null:
		return
	var c := label.modulate
	c.a = alpha
	label.modulate = c
