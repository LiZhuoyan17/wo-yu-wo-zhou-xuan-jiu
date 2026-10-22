extends Area2D
## 关卡终点 / 机关触发点：玩家触碰后进入下一关
## 不改影子与 GameManager 核心，只调 LevelManager.load_next_level()

@export var next_on_touch: bool = true
@export var require_player_group: bool = true


func _ready() -> void:
	add_to_group("level_goals")
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)

	# 可视化提示（无贴图时画圈）
	if get_node_or_null("Sprite2D") == null:
		queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if require_player_group and not body.is_in_group("player"):
		return
	if not next_on_touch:
		return
	print("🏁 到达终点：", name)
	var lm := get_node_or_null("/root/LevelManager")
	if lm and lm.has_method("load_next_level"):
		lm.load_next_level()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 18.0, Color(1.0, 0.85, 0.35, 0.35))
	draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.4, 0.8), 2.0)
