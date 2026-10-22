extends ColorRect
## 登入开场：先播载入视频，约 5 秒后滚动世界观旁白，再进主菜单。
## 不叠主界面 BGM，只用视频自带声音。

const MENU_PATH := "res://ui/main_menu/MainMenu.tscn"
const VIDEO_PATH := "res://assets/intro_video.ogv"
const SCROLL_DELAY := 5.0
const SCROLL_DURATION := 22.0

const STORY_TEXT := """远古之初，光与影本为一体。
光，是展现于世的形态；
影，是深埋心底不愿示人的另一面。

然而世人逐渐厌恶自己的影子——
那些软弱、恐惧与不甘。
被遗弃的影子坠入大地深处，
汇聚成一片名为“渊”的地下世界，
在黑暗中无尽地等待。

你是渊中一颗微弱的光球，醒来时已忘却一切。
唯一奇怪的是，你的影子似乎比你先醒了过来。

它不恨你。它只是在等你。

这不是一段征服世界的冒险，
而是一段与自己和好的旅途。

“我与我周旋久，宁作我。”"""

@onready var video: VideoStreamPlayer = $VideoPlayer
@onready var dim: ColorRect = $Dim
@onready var clip: Control = $StoryClip
@onready var story_label: Label = $StoryClip/StoryLabel
@onready var skip_hint: Label = $SkipHint

var _leaving: bool = false
var _seq: Tween
var _scroll: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.BLACK
	_stop_bgm()
	_alpha(dim, 0.0)
	_alpha(skip_hint, 0.0)
	if story_label:
		story_label.text = STORY_TEXT
		story_label.modulate.a = 0.0
	_start_video()
	_play_sequence()


func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	else:
		pressed = event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")
	if pressed:
		_go_to_menu()


func _stop_bgm() -> void:
	var mm := get_node_or_null("/root/MusicManager")
	if mm and mm.has_method("stop_all"):
		mm.stop_all()


func _start_video() -> void:
	if video == null:
		return
	if not ResourceLoader.exists(VIDEO_PATH):
		push_warning("OpeningIntro：找不到视频 " + VIDEO_PATH)
		return
	var stream := load(VIDEO_PATH)
	if stream == null:
		push_warning("OpeningIntro：无法加载视频")
		return
	video.stream = stream
	video.volume_db = 28.0
	if not video.finished.is_connected(_on_video_finished):
		video.finished.connect(_on_video_finished)
	video.play()


func _play_sequence() -> void:
	_seq = create_tween()
	_seq.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_seq.tween_property(skip_hint, "modulate:a", 0.65, 0.8)
	_seq.tween_interval(SCROLL_DELAY - 0.8)
	_seq.tween_callback(_start_story_scroll)


func _start_story_scroll() -> void:
	if story_label == null or clip == null:
		return
	var view := get_viewport_rect().size
	var text_w := view.x * 0.72
	story_label.custom_minimum_size = Vector2(text_w, 0.0)
	story_label.size = Vector2(text_w, 0.0)
	await get_tree().process_frame
	var text_h := maxf(story_label.get_minimum_size().y, story_label.size.y)
	story_label.size = Vector2(text_w, text_h)
	story_label.position = Vector2((view.x - text_w) * 0.5, view.y * 0.62)
	_alpha(dim, 0.38)
	_alpha(story_label, 1.0)
	var end_y := -text_h - 48.0
	_scroll = create_tween()
	_scroll.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_scroll.tween_property(story_label, "position:y", end_y, SCROLL_DURATION).set_trans(Tween.TRANS_LINEAR)


func _on_video_finished() -> void:
	_go_to_menu()


func _go_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	if _seq and _seq.is_valid():
		_seq.kill()
	if _scroll and _scroll.is_valid():
		_scroll.kill()
	if video and video.is_playing():
		video.stop()
	get_tree().change_scene_to_file(MENU_PATH)


func _alpha(node: CanvasItem, a: float) -> void:
	if node == null:
		return
	var c := node.modulate
	c.a = a
	node.modulate = c
