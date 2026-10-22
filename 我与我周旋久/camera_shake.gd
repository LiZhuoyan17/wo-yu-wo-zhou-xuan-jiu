extends Camera2D
## ==================== CameraShake：正弦衰减震动 ====================
## 挂在玩家 Camera2D 上。业务禁止直接改 offset——统一经 GameManager.trigger_camera_shake。
## 为什么不用随机数：纯 Random offset 会像马赛克抽搐；正弦波在视觉上连贯、可预期。

@export var max_rotation_deg: float = 1.2 ## 轻微滚转，增强“砸中”感，但仍平滑

var _shaking: bool = false
var _intensity: float = 0.0 ## 峰值偏移（像素）
var _duration: float = 0.0
var _frequency: float = 30.0
var _elapsed: float = 0.0
var _phase: float = 0.0


func _ready() -> void:
	make_current()
	add_to_group("main_camera")
	# ALWAYS：即使将来有人误用 paused，震动节点仍尽量可跑；
	# 真正顿帧用的是 time_scale，下面用真实 delta 补偿。
	process_mode = Node.PROCESS_MODE_ALWAYS
	position_smoothing_enabled = false
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER


func _process(delta: float) -> void:
	# Engine.time_scale 变小时，引擎传入的 delta 也会变小。
	# 震动要按“玩家真实时间”播完，否则顿帧期间几乎看不清抖。
	var real_delta := delta
	if Engine.time_scale > 0.0001:
		real_delta = delta / Engine.time_scale

	if not _shaking:
		# 结束态强制归位，避免残留 offset 让画面永久偏掉
		offset = Vector2.ZERO
		rotation = 0.0
		return

	_elapsed += real_delta
	if _elapsed >= _duration:
		_shaking = false
		offset = Vector2.ZERO
		rotation = 0.0
		return

	# 线性衰减包络：开始最猛，结束归零
	var decay := 1.0 - (_elapsed / maxf(_duration, 0.0001))
	decay = clampf(decay, 0.0, 1.0)
	# 平方衰减：收尾更干净，减少“拖尾抖”
	var amp := _intensity * decay * decay

	# 正弦 / 余弦正交位移：平滑、可重复，绝不用 randf
	var t := (_elapsed * _frequency) + _phase
	offset = Vector2(
		sin(t) * amp,
		cos(t * 1.13) * amp * 0.85
	)
	rotation = deg_to_rad(sin(t * 0.7) * max_rotation_deg * (amp / maxf(_intensity, 0.001)))


## intensity: 偏移像素峰值；duration: 真实秒；frequency: 抖动快慢
func shake(intensity: float = 2.0, duration: float = 0.1, frequency: float = 30.0) -> void:
	# 连击时取更强/更长，避免后一次弱震把前一次强震掐断
	if _shaking:
		var remain_amp := _intensity * (1.0 - _elapsed / maxf(_duration, 0.0001))
		_intensity = maxf(remain_amp, intensity)
		_duration = maxf(_duration - _elapsed, duration)
		_frequency = maxf(_frequency, frequency)
		_elapsed = 0.0
	else:
		_intensity = intensity
		_duration = duration
		_frequency = frequency
		_elapsed = 0.0
	_phase = 0.0
	_shaking = true


## 兼容旧调用名（参数已由 GameManager 分级接管）
func shake_player_hurt() -> void:
	shake(8.0, 0.3, 40.0)


func shake_enemy_explode() -> void:
	shake(8.0, 0.3, 40.0)
