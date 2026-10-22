extends Node
## 程序合成短音效（无外部文件）：跳跃 / 攻击 / 受击 / 死亡 / 通关 / UI

const MIX_RATE := 22050
const VOICES := 8
const SFX_RELATIVE := 0.55

var _players: Array[AudioStreamPlayer] = []
var _voice: int = 0
var _cache: Dictionary = {}
var _volume_linear: float = 0.44
var _last_ui_kind: String = ""
var _last_ui_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx_%d" % i
		p.bus = "Master"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_players.append(p)
	var mm := get_node_or_null("/root/MusicManager")
	if mm and mm.has_method("get_volume_linear"):
		set_volume_linear(float(mm.get_volume_linear()))
	else:
		set_volume_linear(0.8)
	_build_cache()


func set_volume_linear(v: float) -> void:
	_volume_linear = clampf(v, 0.0, 1.0) * SFX_RELATIVE
	var db := linear_to_db(maxf(_volume_linear, 0.0001))
	for p in _players:
		p.volume_db = db


func stop_all() -> void:
	for p in _players:
		p.stop()
		p.stream = null


func play(kind: String) -> void:
	if not _cache.has(kind):
		return
	if kind.begins_with("ui_"):
		var now := Time.get_ticks_msec()
		if kind == _last_ui_kind and now - _last_ui_msec < 70:
			return
		_last_ui_kind = kind
		_last_ui_msec = now
	var p: AudioStreamPlayer = _players[_voice]
	_voice = (_voice + 1) % VOICES
	p.stop()
	p.stream = _cache[kind]
	p.volume_db = linear_to_db(maxf(_volume_linear, 0.0001))
	p.play()


func _build_cache() -> void:
	_cache["jump"] = _make_jump()
	_cache["attack"] = _make_attack()
	_cache["hurt"] = _make_hurt()
	_cache["death"] = _make_death()
	_cache["complete"] = _make_complete()
	_cache["ui_select"] = _make_ui_select()
	_cache["ui_press"] = _make_ui_press()


func _make_jump() -> AudioStreamWAV:
	return _render(0.13, func(t: float, dur: float) -> float:
		var k := t / dur
		var hz := lerpf(320.0, 720.0, k)
		var env := _env(k, 0.02, 0.55)
		return sin(TAU * hz * t) * env * 0.38
	)


func _make_attack() -> AudioStreamWAV:
	return _render(0.16, func(t: float, dur: float) -> float:
		var k := t / dur
		var env := _env(k, 0.01, 0.4)
		var noise := (randf() * 2.0 - 1.0) * (1.0 - k) * 0.28
		var hz := lerpf(180.0, 90.0, k)
		var thump := sin(TAU * hz * t) * env * 0.42
		var click := 0.0
		if t < 0.018:
			click = sin(TAU * 1400.0 * t) * (1.0 - t / 0.018) * 0.22
		return thump + noise * env + click
	)


func _make_hurt() -> AudioStreamWAV:
	return _render(0.22, func(t: float, dur: float) -> float:
		var k := t / dur
		var env := _env(k, 0.01, 0.45)
		var hz := lerpf(420.0, 140.0, k)
		var sq := 1.0 if sin(TAU * hz * t) >= 0.0 else -1.0
		var noise := (randf() * 2.0 - 1.0) * 0.18
		return (sq * 0.22 + sin(TAU * hz * t) * 0.2 + noise) * env
	)


func _make_death() -> AudioStreamWAV:
	return _render(0.7, func(t: float, dur: float) -> float:
		var k := t / dur
		var env := _env(k, 0.02, 0.7)
		var hz := lerpf(260.0, 55.0, pow(k, 0.7))
		var low := sin(TAU * hz * t) * 0.4
		var grit := (randf() * 2.0 - 1.0) * (1.0 - k) * 0.12
		return (low + grit) * env
	)


func _make_complete() -> AudioStreamWAV:
	return _render(0.55, func(t: float, _dur: float) -> float:
		var n1 := _note(t, 0.0, 0.16, 523.25, 0.32) ## C5
		var n2 := _note(t, 0.12, 0.18, 659.25, 0.3) ## E5
		var n3 := _note(t, 0.26, 0.28, 783.99, 0.34) ## G5
		return n1 + n2 + n3
	)


func _make_ui_select() -> AudioStreamWAV:
	return _render(0.055, func(t: float, dur: float) -> float:
		var k := t / dur
		var env := _env(k, 0.005, 0.35)
		return sin(TAU * 880.0 * t) * env * 0.22
	)


func _make_ui_press() -> AudioStreamWAV:
	return _render(0.08, func(t: float, dur: float) -> float:
		var k := t / dur
		var env := _env(k, 0.004, 0.4)
		var a := sin(TAU * 660.0 * t) * 0.2
		var b := sin(TAU * 990.0 * t) * 0.12
		return (a + b) * env
	)


func _note(t: float, start: float, len: float, hz: float, vol: float) -> float:
	if t < start or t > start + len:
		return 0.0
	var k := (t - start) / len
	return sin(TAU * hz * (t - start)) * _env(k, 0.02, 0.5) * vol


func _env(k: float, attack: float, release_start: float) -> float:
	k = clampf(k, 0.0, 1.0)
	var a := 1.0
	if attack > 0.0 and k < attack:
		a = k / attack
	if k > release_start:
		a *= 1.0 - (k - release_start) / maxf(1.0 - release_start, 0.001)
	return clampf(a, 0.0, 1.0)


func _render(duration: float, fn: Callable) -> AudioStreamWAV:
	var n := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var s := clampf(float(fn.call(t, duration)), -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream
