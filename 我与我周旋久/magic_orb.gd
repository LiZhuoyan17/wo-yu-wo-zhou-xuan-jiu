extends Area2D
## 玩家暖黄魔法球 + 狐妖幽蓝鬼火弹（同脚本，参数切换）

const ParticleFXUtil = preload("res://particle_fx.gd")
const ORB_TEX = preload("res://assets/orb.png")
const FOX_LIGHT_ORB_TEX = preload("res://assets/fox_light_orb.png")

@export var speed: float = 420.0
@export var max_distance: float = 320.0
@export var sprite_scale: float = 0.14

## 幽蓝鬼火弹：平滑追踪玩家
@export var tracks_player: bool = false
## 玩家斜向球：追踪「离玩家最近」的敌人/光点
@export var homing_nearest_to_player: bool = false
@export var turn_speed: float = 3.0
@export var lifetime: float = 5.0
@export var damages_player: bool = false

var start_position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT
var _has_hit: bool = false
var _point_blank_target: Node2D = null
var _flight_ready: bool = false
var _life: float = 0.0
var _use_fox_light_visual: bool = false
var _orb_sprite: Sprite2D = null


func _ready() -> void:
	monitoring = true
	monitorable = true
	# layer 4 = 魔法球互撞；mask 含 layer1(世界/角色) + layer4(其他球)
	collision_layer = 8
	collision_mask = 1 | 8
	z_index = 80
	add_to_group("magic_orbs")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_build_visuals()


## 由玩家在摆好位置后调用：真正开始飞行
func begin_flight(from_pos: Vector2, dir: Vector2) -> void:
	global_position = from_pos
	start_position = from_pos
	direction = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	_flight_ready = true
	_life = 0.0
	_sync_flight_visual()
	call_deferred("_check_spawn_overlaps")


func arm_point_blank(target: Node2D) -> void:
	_point_blank_target = target
	call_deferred("_check_spawn_overlaps")


## 狐妖发射前调用：切成幽蓝鬼火追踪弹（复用本脚本，不新建类）
func setup_as_lantern_blast() -> void:
	tracks_player = true
	homing_nearest_to_player = false
	turn_speed = 3.0
	lifetime = 3.0 # 狐妖鬼火存活 3 秒
	damages_player = true
	speed = 200.0
	max_distance = 9999.0
	sprite_scale = 0.1
	_use_fox_light_visual = true


## 玩家斜向球：持续追踪离玩家最近的敌人或星星
func setup_as_player_homing() -> void:
	tracks_player = false
	homing_nearest_to_player = true
	damages_player = false
	turn_speed = 5.5
	lifetime = 4.0
	speed = 380.0
	max_distance = 480.0
	_use_fox_light_visual = false


func _build_visuals() -> void:
	var glow_col: Color
	var tex: Texture2D
	if _use_fox_light_visual or damages_player:
		glow_col = Color(0.45, 0.8, 1.0, 1.0)
		tex = FOX_LIGHT_ORB_TEX
	else:
		glow_col = Color(1.0, 0.88, 0.5, 1.0)
		tex = ORB_TEX

	var glow_size := 48
	var glow_img := Image.create(glow_size, glow_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(glow_size / 2.0, glow_size / 2.0)
	for x in range(glow_size):
		for y in range(glow_size):
			var dist := Vector2(x, y).distance_to(center)
			var alpha := clampf(1.0 - dist / (glow_size * 0.5), 0.0, 1.0)
			alpha *= alpha * 0.7
			glow_img.set_pixel(x, y, Color(glow_col.r, glow_col.g, glow_col.b, alpha * 0.75))
	var glow := Sprite2D.new()
	glow.texture = ImageTexture.create_from_image(glow_img)
	glow.scale = Vector2(2.0, 2.0)
	glow.modulate = glow_col
	glow.z_index = 0
	add_child(glow)

	_orb_sprite = Sprite2D.new()
	_orb_sprite.texture = tex
	_orb_sprite.centered = true
	_orb_sprite.scale = Vector2(sprite_scale, sprite_scale)
	_orb_sprite.z_index = 2
	add_child(_orb_sprite)
	_sync_flight_visual()


## 玩家球：旋转对齐轨迹；狐妖球：左右 flip
func _sync_flight_visual() -> void:
	if damages_player or _use_fox_light_visual:
		rotation = 0.0
		_update_sprite_facing()
	else:
		# 斜向飞行时球体朝向与速度一致
		rotation = direction.angle()
		if _orb_sprite:
			_orb_sprite.flip_h = false


## fox_light_orb 默认朝左；向右飞时 flip_h
func _update_sprite_facing() -> void:
	if _orb_sprite == null:
		return
	if not (_use_fox_light_visual or damages_player):
		return
	_orb_sprite.flip_h = direction.x > 0.05


func _physics_process(delta: float) -> void:
	if _has_hit or not _flight_ready:
		return

	_life += delta
	# 幽蓝鬼火 / 玩家追踪球：lifetime 到期销毁
	if (damages_player or tracks_player or homing_nearest_to_player) and _life >= lifetime:
		_explode_and_free()
		return

	# 狐妖球：追踪玩家
	if tracks_player:
		var player := get_tree().get_first_node_in_group("player")
		if is_instance_valid(player):
			var desired: Vector2 = player.global_position - global_position
			if desired.length() > 1.0:
				desired = desired.normalized()
				direction = direction.lerp(desired, turn_speed * delta)
				if direction.length() > 0.001:
					direction = direction.normalized()

	# 玩家斜向球：追踪「当前离玩家最近」的敌人/光点
	elif homing_nearest_to_player:
		var lock := _find_nearest_target_to_player()
		if is_instance_valid(lock):
			var desired2: Vector2 = lock.global_position - global_position
			if desired2.length() > 1.0:
				desired2 = desired2.normalized()
				direction = direction.lerp(desired2, turn_speed * delta)
				if direction.length() > 0.001:
					direction = direction.normalized()

	_sync_flight_visual()

	# 步骤3：固定速度推进
	global_position += direction * speed * delta

	if not damages_player and not tracks_player:
		if global_position.distance_to(start_position) > max_distance:
			_explode_and_free()


## 找离玩家最近的敌人或星星（斜向追踪用）
func _find_nearest_target_to_player() -> Node2D:
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return null
	var origin: Vector2 = player.global_position
	var nearest: Node2D = null
	var best := 520.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var d: float = origin.distance_to(enemy.global_position)
		if d < best:
			best = d
			nearest = enemy
	for orb in get_tree().get_nodes_in_group("light_orbs"):
		if not is_instance_valid(orb):
			continue
		var d2: float = origin.distance_to(orb.global_position)
		if d2 < best:
			best = d2
			nearest = orb
	return nearest


func _check_spawn_overlaps() -> void:
	if _has_hit:
		return
	if is_instance_valid(_point_blank_target) and not damages_player:
		if _try_hit(_point_blank_target):
			return
	for body in get_overlapping_bodies():
		if _try_hit(body):
			return


func _on_body_entered(body: Node2D) -> void:
	_try_hit(body)


## 光球互撞：双方爆炸 + 重击反馈（只由 instance_id 较小的一方触发一次）
func _on_area_entered(area: Area2D) -> void:
	if _has_hit or not is_instance_valid(area):
		return
	if not area.is_in_group("magic_orbs"):
		return
	_has_hit = true
	if get_instance_id() < area.get_instance_id():
		if GameManager:
			GameManager.trigger_heavy_impact()
	if area.has_method("force_explode_from_orb_clash"):
		area.force_explode_from_orb_clash()
	_explode_and_free()


func force_explode_from_orb_clash() -> void:
	if _has_hit:
		return
	_has_hit = true
	_explode_and_free()


func _try_hit(body: Node2D) -> bool:
	if _has_hit or not is_instance_valid(body):
		return false

	# —— 幽蓝鬼火：打玩家（走 take_player_damage，尊重无敌/回溯）——
	if damages_player:
		if body.is_in_group("player"):
			_has_hit = true
			if body.has_method("take_player_damage"):
				body.take_player_damage(1)
			_explode_and_free()
			return true
		if body.is_in_group("enemies"):
			return false
		if body.is_in_group("walls") or body is StaticBody2D or body is TileMapLayer:
			_has_hit = true
			_explode_and_free()
			return true
		return false

	# —— 玩家暖黄魔法球：原逻辑 ——
	if body.is_in_group("player"):
		return false

	if body.is_in_group("enemies"):
		_has_hit = true
		if body.has_method("take_damage"):
			body.take_damage(1)
		# 打击感分级：只调 GameManager，不在这里写震动参数（解耦）
		# 提灯狐妖飘空+玻璃感 → glass；其余普通怪 → light
		if GameManager:
			if body.is_in_group("lantern_fox"):
				GameManager.trigger_glass_impact()
			else:
				GameManager.trigger_light_impact()
		_explode_and_free()
		return true

	if body.is_in_group("walls") or body is TileMapLayer:
		_has_hit = true
		_explode_and_free()
		return true

	return false


func _explode_and_free() -> void:
	if not is_inside_tree():
		queue_free()
		return
	var parent := get_parent()
	if parent:
		if damages_player:
			ParticleFXUtil.spawn_burst(
				parent, global_position,
				Color(0.5, 0.85, 1.0, 1.0),
				14, 0.3, 40.0, 120.0, 0.2, 0.55, 40.0
			)
		else:
			ParticleFXUtil.magic_orb_explode(parent, global_position)
	queue_free()
