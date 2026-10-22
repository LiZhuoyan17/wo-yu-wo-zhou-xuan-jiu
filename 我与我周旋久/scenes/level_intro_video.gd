extends CanvasLayer
## 关卡开场视频播放器（全屏覆盖层）
## 用法：GameManager 在 Level_01 ready 后实例化，播完自动 queue_free。
## 任意键 / 鼠标点击可跳过。

## 将 mp4 转为 ogv 后放到 assets/ 目录，文件名改为 intro_video.ogv
## 转换命令（需要 ffmpeg）：
##   ffmpeg -i "我与我周旋久.mp4" -c:v libtheora -q:v 7 -c:a libvorbis -q:a 4 intro_video.ogv
const VIDEO_PATH := "res://assets/intro_video.ogv"

signal finished

var _done: bool = false

@onready var player: VideoStreamPlayer = $VideoPlayer
@onready var skip_label: Label = $SkipLabel


func _ready() -> void:
	layer = 100  ## 盖过 HUD（血条是独立 CanvasLayer）
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hold_hud(true)

	if not ResourceLoader.exists(VIDEO_PATH):
		push_warning("LevelIntroVideo：找不到视频 " + VIDEO_PATH)
		_end()
		return

	var stream := load(VIDEO_PATH)
	if stream == null:
		push_warning("LevelIntroVideo：无法加载视频")
		_end()
		return

	player.stream = stream
	player.finished.connect(_end)
	player.play()


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	if pressed:
		_end()


func _end() -> void:
	if _done:
		return
	_done = true
	if player and player.is_playing():
		player.stop()
	finished.emit()
	queue_free()


func _hold_hud(hold: bool) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("hold_hud"):
		gm.hold_hud(hold)
