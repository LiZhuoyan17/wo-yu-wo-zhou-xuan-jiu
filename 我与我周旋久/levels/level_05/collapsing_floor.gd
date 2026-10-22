extends Node2D
## 可崩塌地面段：震动 → 淡出 → 关碰撞 → queue_free
## 由 Level 05 连锁触发；不改玩家状态机。

signal collapsed

@export var shake_sec: float = 0.3
@export var fade_sec: float = 0.5
@export var shake_amp: float = 2.0

var _body: StaticBody2D = null
var _visual_root: Node2D = null
var _busy: bool = false
var _base_pos: Vector2 = Vector2.ZERO


func setup_body(body: StaticBody2D, visual_root: Node2D = null) -> void:
	_body = body
	_visual_root = visual_root
	if _visual_root == null and body:
		_visual_root = body.get_node_or_null("FloorVisuals") as Node2D
	_base_pos = position


func begin_collapse() -> void:
	if _busy:
		return
	_busy = true
	_base_pos = position
	await _shake()
	await _fade_out()
	_disable_collision()
	collapsed.emit()
	queue_free()


func _shake() -> void:
	var t := 0.0
	while t < shake_sec:
		var dt := get_process_delta_time()
		t += dt
		position = _base_pos + Vector2(
			randf_range(-shake_amp, shake_amp),
			randf_range(-shake_amp, shake_amp)
		)
		await get_tree().process_frame
	position = _base_pos


func _fade_out() -> void:
	var targets: Array[CanvasItem] = []
	if _visual_root:
		_collect_canvas(_visual_root, targets)
	else:
		_collect_canvas(self, targets)
	if targets.is_empty():
		await get_tree().create_timer(fade_sec).timeout
		return
	var tween := create_tween()
	tween.set_parallel(true)
	for c in targets:
		tween.tween_property(c, "modulate:a", 0.0, fade_sec)
	await tween.finished


func _collect_canvas(n: Node, out: Array[CanvasItem]) -> void:
	if n is CanvasItem:
		out.append(n as CanvasItem)
	for ch in n.get_children():
		_collect_canvas(ch, out)


func _disable_collision() -> void:
	if _body and is_instance_valid(_body):
		for ch in _body.get_children():
			if ch is CollisionShape2D:
				(ch as CollisionShape2D).disabled = true
			elif ch is CollisionPolygon2D:
				(ch as CollisionPolygon2D).disabled = true
		_body.collision_layer = 0
