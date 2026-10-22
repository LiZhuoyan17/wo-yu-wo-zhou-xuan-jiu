extends Area2D
## 尖刺伤害区：用地图 hazard 贴图；碰到扣血（走已有 take_player_damage）

@export var damage: int = 1
@export var cooldown: float = 0.6
@export var is_ceiling: bool = false

var _cd: float = 0.0


func _ready() -> void:
	add_to_group("hazards")
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	apply_visual(is_ceiling)


func apply_visual(ceiling: bool = false) -> void:
	is_ceiling = ceiling
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr == null:
		spr = Sprite2D.new()
		spr.name = "Sprite2D"
		add_child(spr)

	var path := _pick_hazard_tex(ceiling)
	if path != "" and ResourceLoader.exists(path):
		spr.texture = load(path)
		# 512 图缩到约一格宽
		spr.scale = Vector2(32.0 / 512.0, 32.0 / 512.0)
		spr.centered = true
		spr.flip_v = ceiling
		spr.position = Vector2(0, -6 if ceiling else 6)


func _pick_hazard_tex(ceiling: bool) -> String:
	var folder := "res://assets/tiles/hazard"
	var prefer_prefix := "hazard_ceiling_" if ceiling else "hazard_ground_"
	var da := DirAccess.open(folder)
	if da == null:
		return ""
	var candidates: Array[String] = []
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if not da.current_is_dir() and fname.to_lower().ends_with(".png") and fname.begins_with(prefer_prefix):
			candidates.append(folder.path_join(fname))
		fname = da.get_next()
	da.list_dir_end()
	candidates.sort()
	if candidates.is_empty():
		return ""
	return candidates[randi() % candidates.size()]


func _physics_process(delta: float) -> void:
	if _cd > 0.0:
		_cd -= delta


func _on_body_entered(body: Node2D) -> void:
	if _cd > 0.0:
		return
	if not body.is_in_group("player"):
		return
	if body.has_method("take_player_damage"):
		body.take_player_damage(damage)
		_cd = cooldown
