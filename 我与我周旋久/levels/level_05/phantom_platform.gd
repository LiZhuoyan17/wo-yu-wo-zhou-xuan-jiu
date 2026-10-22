extends Node2D
## 闪现平台：2s 浮现 / 3s 隐藏。碰撞随消失关闭，站上的人会掉下去。
## 隐藏结束前 0.5s 出半透明虚影，方便卡影子回溯时机。

signal platform_appeared
signal platform_disappeared

@export var visible_duration: float = 2.0
@export var hidden_duration: float = 3.0
@export var ghost_lead: float = 0.5
@export var auto_start: bool = true

var _is_visible: bool = false
var _ghost_on: bool = false
var _timer: float = 0.0
var _colliders: Array[CollisionShape2D] = []
var _sprites: Array[CanvasItem] = []
var _glow: GPUParticles2D = null
var _tween: Tween = null


func _ready() -> void:
	_collect_nodes()
	_set_platform_state(false, true)
	if auto_start:
		_timer = hidden_duration


func setup_from_painted() -> void:
	_collect_nodes()
	_set_platform_state(false, true)
	_timer = hidden_duration if auto_start else _timer


func remaining() -> float:
	return _timer


func is_platform_solid() -> bool:
	return _is_visible


func _process(delta: float) -> void:
	_timer -= delta
	if not _is_visible and not _ghost_on and _timer <= ghost_lead:
		_show_ghost()
	if _timer <= 0.0:
		_toggle()


func _toggle() -> void:
	_is_visible = not _is_visible
	_ghost_on = false
	_set_platform_state(_is_visible, false)
	if _is_visible:
		_timer = visible_duration
		platform_appeared.emit()
	else:
		_timer = hidden_duration
		platform_disappeared.emit()


func _collect_nodes() -> void:
	_colliders.clear()
	_sprites.clear()
	_glow = get_node_or_null("GlowEffect") as GPUParticles2D
	_gather(self)


func _gather(n: Node) -> void:
	if n is CollisionShape2D:
		_colliders.append(n as CollisionShape2D)
	elif n is CollisionPolygon2D:
		pass
	if n is Sprite2D:
		_sprites.append(n as CanvasItem)
	for ch in n.get_children():
		_gather(ch)


func _show_ghost() -> void:
	_ghost_on = true
	visible = true
	_kill_tween()
	for s in _sprites:
		if is_instance_valid(s):
			s.visible = true
			s.modulate.a = 0.2
	if _glow:
		_glow.emitting = false
	# 虚影阶段仍无碰撞，不能提前站上去
	_set_colliders(false)


func _set_platform_state(now_visible: bool, instant: bool) -> void:
	_set_colliders(now_visible)
	_kill_tween()
	if now_visible:
		visible = true
		if _glow:
			_glow.emitting = true
		if instant:
			for s in _sprites:
				if is_instance_valid(s):
					s.visible = true
					s.modulate.a = 1.0
			return
		_tween = create_tween()
		_tween.set_parallel(true)
		for s in _sprites:
			if is_instance_valid(s):
				s.visible = true
				_tween.tween_property(s, "modulate:a", 1.0, 0.15)
	else:
		if _glow:
			_glow.emitting = false
		if instant:
			for s in _sprites:
				if is_instance_valid(s):
					s.modulate.a = 0.0
			visible = false
			return
		_tween = create_tween()
		_tween.set_parallel(true)
		for s in _sprites:
			if is_instance_valid(s):
				_tween.tween_property(s, "modulate:a", 0.0, 0.15)
		_tween.set_parallel(false)
		_tween.tween_callback(func() -> void:
			visible = false
		)


func _set_colliders(enabled: bool) -> void:
	for cs in _colliders:
		if is_instance_valid(cs):
			cs.set_deferred("disabled", not enabled)
	for n in find_children("*", "CollisionPolygon2D", true, false):
		if n is CollisionPolygon2D:
			(n as CollisionPolygon2D).set_deferred("disabled", not enabled)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
