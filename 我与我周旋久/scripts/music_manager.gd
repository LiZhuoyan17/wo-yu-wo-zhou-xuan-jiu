extends Node
## 三首新曲，同一时刻只播一首：
## background.wav → 主界面 / 选关
## level.wav      → 关卡内
## final.wav      → 五关全部通关后的结局

const MENU_PATH := "res://audio/background.wav"
const LEVEL_PATH := "res://audio/level.wav"
const FINAL_PATH := "res://audio/final.wav"

var _player: AudioStreamPlayer
var _current_path: String = ""
var _volume_linear: float = 0.8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.name = "Bgm"
	_player.bus = "Master"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)


func play_menu() -> void:
	_play(MENU_PATH, true)


func play_level() -> void:
	_play(LEVEL_PATH, true)


func play_ending() -> void:
	_play(FINAL_PATH, true)


func stop_all() -> void:
	if _player:
		_player.stop()
		_player.stream = null
	_current_path = ""


func set_volume_linear(v: float) -> void:
	_volume_linear = clampf(v, 0.0, 1.0)
	if _player and _player.playing:
		_player.volume_db = _linear_to_db(_volume_linear)


func get_volume_linear() -> float:
	return _volume_linear


func _play(path: String, loop: bool) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("MusicManager：找不到音乐 " + path)
		return
	if _current_path == path and _player and _player.playing:
		_player.volume_db = _linear_to_db(_volume_linear)
		return
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("MusicManager：无法加载 " + path)
		return
	_prepare_loop(stream, loop)
	_player.stop()
	_player.stream = stream
	_player.volume_db = _linear_to_db(_volume_linear)
	_player.play()
	_current_path = path
	print("♪ 音乐 → ", path.get_file())


func _prepare_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if loop:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			var frames := int(round(wav.get_length() * float(wav.mix_rate)))
			wav.loop_end = maxi(frames, 1)
		else:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED


func _linear_to_db(v: float) -> float:
	if v <= 0.001:
		return -80.0
	return linear_to_db(v)
