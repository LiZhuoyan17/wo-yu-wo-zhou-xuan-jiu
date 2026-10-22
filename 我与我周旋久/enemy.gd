extends "res://enemy_base.gd"
## 地面巡逻怪 —— 继承 BaseEnemy；可被影子仇恨吸引

const LIGHT_ORB_SCENE = preload("res://light_orb.tscn")

@export var gravity: float = 980.0
@export var patrol_speed: float = 40.0
@export var chase_speed: float = 70.0
@export var detect_range: float = 150.0
@export var aggro_range: float = 250.0
## 巡逻探崖：前方水平伸出、向下探测的距离（未交战前绝不走下深渊）
@export var ledge_check_ahead: float = 18.0
@export var ledge_check_down: float = 48.0

var is_stunned: bool = false
var patrol_direction: float = 1.0
var patrol_distance: float = 100.0
## 可选硬边界（世界 X）；由关卡写入后优先于 patrol_distance
var patrol_min_x: float = -INF
var patrol_max_x: float = INF
var start_position: Vector2
var is_chasing: bool = false
var is_hurt: bool = false
var attack_cooldown: bool = false
var enemy_texture: Texture2D


func _enemy_ready() -> void:
	start_position = global_position
	enemy_texture = load("res://assets/enemy.png")


func _physics_process(delta: float) -> void:
	if current_hp <= 0 or _is_dead:
		return

	if is_stunned:
		if velocity.length() < 100.0:
			var target_player = get_tree().get_first_node_in_group("player")
			if target_player:
				var knockback_dir = -global_position.direction_to(target_player.global_position)
				velocity = knockback_dir * 200.0
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		queue_redraw()
		return

	var player = get_tree().get_first_node_in_group("player")
	if player:
		var aggro := resolve_aggro_target(player)
		if aggro.is_empty():
			is_chasing = false
			_patrol(delta)
		else:
			var target_pos: Vector2 = aggro["pos"]
			var dist_to_target := global_position.distance_to(target_pos)
			# 索敌范围仍以玩家距离为准，避免影子把怪永久拉走
			var dist_player := global_position.distance_to(player.global_position)
			if dist_player <= aggro_range or (aggro["is_shadow"] and dist_to_target <= aggro_range):
				is_chasing = true
				if dist_to_target <= 25.0:
					velocity.x = 0.0
					if not attack_cooldown:
						# 影子：挥空击碎；玩家：咬人
						try_melee_on_aggro(25.0)
						attack_cooldown = true
						get_tree().create_timer(0.8).timeout.connect(func(): attack_cooldown = false)
				else:
					var direction: Vector2 = (target_pos - global_position).normalized()
					velocity.x = direction.x * chase_speed
					if target_pos.y < global_position.y - 10.0:
						velocity.y = -350.0
			else:
				is_chasing = false
				_clear_aggro()
				_patrol(delta)
	else:
		_clear_aggro()
		_patrol(delta)

	if not is_on_floor():
		velocity.y += gravity * delta

	move_and_slide()
	queue_redraw()


func _patrol(_delta: float) -> void:
	# 未交战：只在安全地面上来回走，遇崖/越界立刻掉头
	if global_position.x >= patrol_max_x - 2.0:
		patrol_direction = -1.0
	elif global_position.x <= patrol_min_x + 2.0:
		patrol_direction = 1.0
	elif global_position.x > start_position.x + patrol_distance:
		patrol_direction = -1.0
	elif global_position.x < start_position.x - patrol_distance:
		patrol_direction = 1.0

	if is_on_floor() and _is_ledge_ahead(patrol_direction):
		patrol_direction *= -1.0

	velocity.x = patrol_direction * patrol_speed


## 前方脚下是否没有可站立碰撞（Floor/Platform）
func _is_ledge_ahead(dir: float) -> bool:
	if dir == 0.0:
		return false
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	var origin := global_position + Vector2(signf(dir) * ledge_check_ahead, 2.0)
	var query := PhysicsRayQueryParameters2D.create(
		origin,
		origin + Vector2(0.0, ledge_check_down)
	)
	query.collision_mask = collision_mask if collision_mask != 0 else 1
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty()


## 关卡：把巡逻钳在某段 Floor 岛内（留边距，避免贴边掉坑）
func set_patrol_island(x0: float, x1: float, margin: float = 28.0) -> void:
	patrol_min_x = x0 + margin
	patrol_max_x = x1 - margin
	if patrol_max_x < patrol_min_x:
		var mid := (x0 + x1) * 0.5
		patrol_min_x = mid - 8.0
		patrol_max_x = mid + 8.0
	patrol_distance = minf(patrol_distance, (patrol_max_x - patrol_min_x) * 0.5)
	start_position = global_position
	# 若出生点略偏出边界，拉回岛心
	if global_position.x < patrol_min_x or global_position.x > patrol_max_x:
		global_position.x = clampf(global_position.x, patrol_min_x, patrol_max_x)
		start_position = global_position


func take_damage(amount: int) -> void:
	if _is_dead:
		return
	current_hp -= amount
	is_hurt = true
	is_stunned = true

	if current_hp <= 0:
		die()
	else:
		# 非致命：轻击反馈由魔法球侧 trigger_light_impact；这里只做受击硬直
		await get_tree().create_timer(0.2, true, false, true).timeout
		is_hurt = false
		is_stunned = false


func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	if GameManager:
		GameManager.trigger_heavy_impact()
	set_physics_process(false)
	modulate.a = 0.0
	var parent := get_parent()
	var death_pos := global_position
	if parent:
		ParticleFXUtil.enemy_death(parent, death_pos)
		_spawn_death_star(parent, death_pos)
	queue_free()


## 死后掉落一颗可拾取星星（light_orb）
func _spawn_death_star(parent: Node, pos: Vector2) -> void:
	var star = LIGHT_ORB_SCENE.instantiate()
	parent.add_child(star)
	star.global_position = pos + Vector2(0, -8)
	star.scale = Vector2(0.03, 0.03)


func _draw() -> void:
	var glow_color = Color(0.6, 0.2, 0.8, 0.3)
	if is_hurt:
		glow_color = Color(1.0, 1.0, 1.0, 0.5)

	draw_circle(Vector2.ZERO, 32.0, Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * 0.3))
	draw_circle(Vector2.ZERO, 24.0, Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * 0.5))
	draw_circle(Vector2.ZERO, 18.0, Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * 0.8))

	if enemy_texture:
		var draw_color = Color(1, 1, 1, 1.0)
		if is_hurt:
			draw_color = Color(1.5, 1.5, 1.5, 1.0)
		draw_texture_rect(enemy_texture, Rect2(-20, -20, 40, 40), false, draw_color)
	else:
		var color = Color(0.6, 0.2, 0.8, 1.0)
		if is_hurt:
			color = Color(1.0, 1.0, 1.0, 1.0)
		draw_circle(Vector2.ZERO, 16.0, color)
		var eye_color = Color(1.0, 0.8, 0.2, 1.0)
		draw_circle(Vector2(-5, -4), 3.0, eye_color)
		draw_circle(Vector2(5, -4), 3.0, eye_color)
