extends Area2D
## ==================== KillZone：深渊底部贯穿即死区 ====================
## 玩家坠入 → 与扣完血相同的死亡结算（不是直接重开）

@export var arm_delay_sec: float = 0.35 ## 进关后短暂延迟，避免出生掉落误触


func _ready() -> void:
	name = "KillZone"
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	# 进关瞬间先关掉，防止重生帧误触
	monitoring = false
	var t := get_tree().create_timer(arm_delay_sec)
	t.timeout.connect(func() -> void: monitoring = true)


func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	# 先关监测，避免物理帧内连触发
	monitoring = false
	if body.has_method("kill_by_abyss"):
		body.call_deferred("kill_by_abyss")
		return
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("game_over"):
		gm.call_deferred("game_over", "abyss")
	elif gm and gm.has_method("reset_level"):
		gm.call_deferred("reset_level")


## 铺满 [floor_left, floor_right] 下方一条贯穿带（顶边在 top_y）
func setup_span(floor_left: float, floor_right: float, top_y: float, height: float = 520.0) -> void:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null:
		cs = CollisionShape2D.new()
		cs.name = "CollisionShape2D"
		add_child(cs)
	var rect := cs.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
		cs.shape = rect
	var width := maxf(512.0, floor_right - floor_left + 256.0)
	rect.size = Vector2(width, height)
	# 关卡根节点本地坐标（与 Floor 同空间）
	position = Vector2(
		(floor_left + floor_right) * 0.5,
		top_y + height * 0.5
	)
