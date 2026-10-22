extends Area2D
## 提灯狐妖投下的哥特幽蓝光斑：陷阱 + 魅惑跳板
## 只调用玩家已有 apply_charm，不改状态机枚举

@export var lifetime: float = 4.0
@export var charm_duration: float = 3.0
@export var spot_radius: float = 36.0

var _life: float = 0.0
var _triggered: bool = false
var _visual: Sprite2D


func _ready() -> void:
	add_to_group("charm_spots")
	_life = lifetime
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1 # 检测玩家 CharacterBody2D
	body_entered.connect(_on_body_entered)
	_build_visual()


func _build_visual() -> void:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var max_dist := size / 2.0
	for x in range(size):
		for y in range(size):
			var p := Vector2(float(x), float(y))
			# 椭圆压扁，更像地面光斑
			var d := Vector2((p.x - center.x) / max_dist, (p.y - center.y) / (max_dist * 0.55)).length()
			var t := clampf(1.0 - d, 0.0, 1.0)
			var a := pow(t, 1.6) * 0.75
			img.set_pixel(x, y, Color(0.35, 0.7, 1.0, a))

	_visual = Sprite2D.new()
	_visual.texture = ImageTexture.create_from_image(img)
	_visual.z_index = -2
	_visual.scale = Vector2(spot_radius / 16.0, spot_radius / 28.0)
	_visual.modulate = Color(0.7, 0.9, 1.0, 0.95)
	add_child(_visual)

	var shape := CircleShape2D.new()
	shape.radius = spot_radius
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

	# 轻微呼吸，提示可踩
	var tw := create_tween().set_loops()
	tw.tween_property(_visual, "modulate:a", 0.55, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_visual, "modulate:a", 0.95, 0.9).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _triggered:
		return
	if not body.is_in_group("player"):
		return
	_triggered = true
	if body.has_method("apply_charm"):
		body.apply_charm(charm_duration)
	# 踩中后光斑短暂闪一下再消失
	if _visual:
		var tw := create_tween()
		tw.tween_property(_visual, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.25)
		tw.tween_callback(queue_free)
	else:
		queue_free()
