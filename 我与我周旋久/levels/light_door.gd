extends Area2D
## ==================== LightDoor：关卡光之门转场 ====================
## 使用 DoorClose / DoorOpen 贴图（与 Main 的 lightdoor 同一套资源），不是金色光圈。
## 流程：玩家进入 → 开门 → 锁定输入 → 等 transition_sec → GameManager.load_level
## 不改影子 / 仇恨 / 视差结构。

@export var next_level_id: int = 2
@export var transition_sec: float = 2.0
@export var one_shot: bool = true

@onready var door_closed: Sprite2D = get_node_or_null("DoorClose") as Sprite2D
@onready var door_open: Sprite2D = get_node_or_null("DoorOpen") as Sprite2D

var _triggered: bool = false
var _busy: bool = false


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	add_to_group("light_door")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_ensure_door_sprites()
	_set_door_open(false)


func _ensure_door_sprites() -> void:
	if door_closed == null:
		door_closed = Sprite2D.new()
		door_closed.name = "DoorClose"
		add_child(door_closed)
	if door_open == null:
		door_open = Sprite2D.new()
		door_open.name = "DoorOpen"
		add_child(door_open)
	if door_closed.texture == null and ResourceLoader.exists("res://assets/DoorClose.png"):
		door_closed.texture = load("res://assets/DoorClose.png")
		door_closed.scale = Vector2(0.27, 0.27)
		door_closed.position = Vector2(0, -37)
	if door_open.texture == null and ResourceLoader.exists("res://assets/DoorOpen.png"):
		door_open.texture = load("res://assets/DoorOpen.png")
		door_open.scale = Vector2(0.14, 0.14)
		door_open.position = Vector2(0, -36)


func _on_body_entered(body: Node2D) -> void:
	if _busy:
		return
	if _triggered and one_shot:
		return
	if body == null or not body.is_in_group("player"):
		return
	_triggered = true
	_run_transition(body)


func _run_transition(player: Node2D) -> void:
	_busy = true
	_set_door_open(true)
	print("🚪 LightDoor 开启 → L", next_level_id, "（锁输入 ", transition_sec, "s）")

	# 禁用移动/攻击，防止过场期间乱操作
	if player.has_method("set_input_locked"):
		player.call("set_input_locked", true)
	if "velocity" in player:
		var v: Vector2 = player.velocity
		v.x = 0.0
		player.velocity = v

	await get_tree().create_timer(transition_sec).timeout

	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("complete_current_level"):
		gm.set("_pending_next_level", next_level_id)
		gm.complete_current_level()
		return
	if gm and gm.has_method("load_level"):
		gm.load_level(next_level_id)
		return
	var lm := get_node_or_null("/root/LevelManager")
	if lm and lm.has_method("load_level"):
		lm.load_level(next_level_id)
	else:
		push_error("LightDoor：无法加载关卡")
		_busy = false
		if player.has_method("set_input_locked"):
			player.call("set_input_locked", false)


func _set_door_open(open: bool) -> void:
	if door_closed:
		door_closed.visible = not open
	if door_open:
		door_open.visible = open
