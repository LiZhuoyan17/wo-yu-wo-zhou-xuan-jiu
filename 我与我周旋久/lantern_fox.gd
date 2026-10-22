extends "res://enemy_base.gd"
## 提灯狐妖（Lantern-Fox）
## 继承 BaseEnemy：半空漂浮 / 投射魅惑光斑 / 幽蓝鬼火弹 / 碎光反应

const LIGHT_ORB_SCENE = preload("res://light_orb.tscn")
const MAGIC_ORB_SCENE = preload("res://magic_orb.tscn")
const CHARM_SPOT_SCRIPT = preload("res://charm_spot.gd")

@export var float_amplitude: float = 16.0
@export var float_speed: float = 1.4
@export var hover_amplitude: float = 40.0
@export var hover_speed: float = 0.55
@export var idle_scale: float = 0.091
@export var side_scale: float = 0.182

@export var spot_interval: float = 2.0
@export var spot_lifetime: float = 4.0
@export var charm_duration: float = 3.0
## 关卡注入的必经站立点（世界坐标）；有则蓝光优先砸这里
var charm_path_points: Array[Vector2] = []

@export var shatter_aoe_radius: float = 120.0
@export var shatter_aoe_damage: int = 2
@export var shatter_orb_min: int = 3
@export var shatter_orb_max: int = 5

## 幽蓝鬼火弹
@export var blast_interval: float = 5.0
@export var blast_windup: float = 0.5

## 与 player 二连跳同步：相对站立面最大抬升（含漂浮上摆）
const PLAYER_JUMP_SPEED := 456.0
const PLAYER_DOUBLE_JUMP_SPEED := 420.0
const PLAYER_GRAVITY_REF := 1000.0
const FLOOR_TOP_Y_REF := 256.0

var _base_pos: Vector2 = Vector2.ZERO
var _float_t: float = 0.0
var _anim_name: StringName = &""
var _spot_timer: float = 0.0
var _shattered: bool = false
## 狐妖中心允许的最小 Y（越高越小）；漂浮不得突破，保证玩家二连跳够得到 / 碎光星可吃
var _hover_min_y: float = -INF

var _blast_timer: float = 0.0
var _windup_left: float = 0.0
var _is_winding_up: bool = false
var _windup_pos: Vector2 = Vector2.ZERO
var _lantern_base_energy: float = 0.85

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var lantern_light: PointLight2D = $LanternLight
@onready var lantern_marker: Marker2D = $LanternMarker
@onready var spot_spawn: Marker2D = $SpotSpawn
@onready var lantern_hitbox: Area2D = get_node_or_null("LanternHitbox") as Area2D


func _enemy_ready() -> void:
	immune_to_ground_melee = true
	max_hp = 5
	current_hp = max_hp
	add_to_group("lantern_fox") # 供玩家斜向自动瞄准

	_base_pos = global_position
	_float_t = randf() * TAU
	_spot_timer = spot_interval * 0.5
	_blast_timer = blast_interval

	collision_mask = 0

	_setup_sprite_frames()
	_setup_lantern_light()
	_setup_lantern_hitbox()
	_play_anim(&"idle")
	if lantern_light:
		_lantern_base_energy = lantern_light.energy
	# 默认按二连跳钳制（关卡可再调一次）
	clamp_hover_to_double_jump(FLOOR_TOP_Y_REF, _default_max_air_rise())


func _default_max_air_rise() -> float:
	var h := (
		PLAYER_JUMP_SPEED * PLAYER_JUMP_SPEED
		+ PLAYER_DOUBLE_JUMP_SPEED * PLAYER_DOUBLE_JUMP_SPEED
	) / (2.0 * PLAYER_GRAVITY_REF)
	return maxf(h - 12.0, 64.0)


## floor_top_y：站立面顶；max_rise：二连跳最大抬升。狐妖（含上漂）不得高于此。
func clamp_hover_to_double_jump(floor_top_y: float, max_rise: float) -> void:
	_base_pos = global_position
	var amp := maxf(float_amplitude, 0.0)
	var min_y := floor_top_y - max_rise
	_hover_min_y = min_y
	var max_base_above := maxf(max_rise - amp - 4.0, 40.0)
	var base_min_y := floor_top_y - max_base_above
	if _base_pos.y < base_min_y:
		_base_pos.y = base_min_y
	if global_position.y < base_min_y:
		global_position.y = base_min_y
	if amp > max_rise * 0.25:
		float_amplitude = max_rise * 0.25


func _setup_lantern_hitbox() -> void:
	# 提灯弱点区：与本体同组，便于魔法球 body 命中；视觉上偏下
	if lantern_hitbox == null:
		return
	lantern_hitbox.monitoring = false
	lantern_hitbox.monitorable = true
	lantern_hitbox.collision_layer = 1
	lantern_hitbox.collision_mask = 0
	if lantern_marker:
		lantern_hitbox.position = lantern_marker.position


func _setup_sprite_frames() -> void:
	if anim == null:
		return

	var frames := SpriteFrames.new()

	frames.add_animation(&"idle")
	frames.set_animation_loop(&"idle", true)
	frames.set_animation_speed(&"idle", 1.0)
	frames.add_frame(&"idle", load("res://assets/fox_face.png"))

	frames.add_animation(&"run")
	frames.set_animation_loop(&"run", true)
	frames.set_animation_speed(&"run", 7.0)
	frames.add_frame(&"run", load("res://assets/fox_run1.png"))
	frames.add_frame(&"run", load("res://assets/fox_run2.png"))

	frames.add_animation(&"jump_up")
	frames.set_animation_loop(&"jump_up", true)
	frames.set_animation_speed(&"jump_up", 1.0)
	frames.add_frame(&"jump_up", load("res://assets/fox_jumpup.png"))

	frames.add_animation(&"jump_down")
	frames.set_animation_loop(&"jump_down", true)
	frames.set_animation_speed(&"jump_down", 1.0)
	frames.add_frame(&"jump_down", load("res://assets/fox_jumpdown.png"))

	anim.sprite_frames = frames
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	anim.z_index = 1


func _setup_lantern_light() -> void:
	if lantern_light == null:
		return

	var tex := GradientTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([
		Color(0.45, 0.85, 1.0, 0.9),
		Color(0.25, 0.55, 1.0, 0.35),
		Color(0.1, 0.2, 0.6, 0.0),
	])
	tex.gradient = g
	lantern_light.texture = tex
	lantern_light.color = Color(0.4, 0.75, 1.0, 1.0)
	lantern_light.energy = 0.85
	lantern_light.texture_scale = 1.1
	lantern_light.z_index = -1
	if lantern_marker:
		lantern_light.position = lantern_marker.position


func _physics_process(delta: float) -> void:
	if _is_dead or _shattered:
		return

	# —— 蓄力前摇：悬停 + 提灯闪烁 ——
	if _is_winding_up:
		_update_facing()
		global_position = _windup_pos
		_windup_left -= delta
		_flash_lantern_windup()
		if _windup_left <= 0.0:
			_is_winding_up = false
			_restore_lantern_light()
			_fire_lantern_blast()
			_blast_timer = blast_interval
		return

	_float_t += delta
	var bob_y := sin(_float_t * float_speed) * float_amplitude
	var hover_x := sin(_float_t * hover_speed) * hover_amplitude
	var pos := _base_pos + Vector2(hover_x, bob_y)
	# 硬钳：不得高于二连跳上限（碎光星/本体都要够得着）
	if _hover_min_y > -INF:
		pos.y = maxf(pos.y, _hover_min_y)
	global_position = pos

	var vy := cos(_float_t * float_speed) * float_amplitude * float_speed
	var vx := cos(_float_t * hover_speed) * hover_amplitude * hover_speed

	_update_facing()
	_update_animation(vx, vy)

	_spot_timer -= delta
	if _spot_timer <= 0.0:
		_spot_timer = spot_interval
		_cast_charm_spot()

	_blast_timer -= delta
	if _blast_timer <= 0.0:
		_start_blast_windup()


func _update_facing() -> void:
	if anim == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player:
		anim.flip_h = player.global_position.x > global_position.x


func _update_animation(vx: float, vy: float) -> void:
	var abs_vx := absf(vx)
	var abs_vy := absf(vy)
	if abs_vx > 12.0 and abs_vx >= abs_vy * 0.85:
		_play_anim(&"run")
	elif vy < -8.0:
		_play_anim(&"jump_up")
	elif vy > 8.0:
		_play_anim(&"jump_down")
	else:
		_play_anim(&"idle")


func _play_anim(name: StringName) -> void:
	if anim == null or _anim_name == name:
		return
	_anim_name = name
	var s := idle_scale if name == &"idle" else side_scale
	anim.scale = Vector2(s, s)
	anim.play(name)


# -------------------- 魅惑光斑 --------------------
func _cast_charm_spot() -> void:
	var parent := get_parent()
	if parent == null:
		return

	var spot := Area2D.new()
	spot.set_script(CHARM_SPOT_SCRIPT)
	spot.set("lifetime", spot_lifetime)
	spot.set("charm_duration", charm_duration)
	parent.add_child(spot)

	# 放在玩家必经地面上，禁止落在狐妖正下方
	var drop_pos := _find_path_drop_position()
	spot.global_position = drop_pos


func set_charm_path_points(points: Array) -> void:
	charm_path_points.clear()
	for p in points:
		if p is Vector2:
			charm_path_points.append(p as Vector2)


## 优先砸关卡注入的必经站立点；否则射线沿玩家→门取样（避开脚下）
func _find_path_drop_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var door := get_tree().get_first_node_in_group("light_door") as Node2D
	if door == null:
		var parent := get_parent()
		if parent:
			door = parent.get_node_or_null("LightDoor") as Node2D
			if door == null:
				door = parent.get_node_or_null("Level_Props/LightDoor") as Node2D

	var fox_clear := 100.0
	var from_x := global_position.x
	var to_x := global_position.x + 400.0
	var base_y := global_position.y
	if player:
		from_x = player.global_position.x
		base_y = player.global_position.y
	if door:
		to_x = door.global_position.x
	elif player:
		to_x = player.global_position.x + 480.0

	var toward := signf(to_x - from_x)
	if toward == 0.0:
		toward = 1.0

	if not charm_path_points.is_empty():
		var best_pt := Vector2.ZERO
		var best_ok := false
		var best_score := -INF
		for pt in charm_path_points:
			if absf(pt.x - global_position.x) < fox_clear:
				continue
			var ahead: float = (pt.x - from_x) * toward
			if ahead < 40.0 or ahead > 520.0:
				continue
			var along: float = 1.0 - absf(pt.x - lerpf(from_x, to_x, 0.4)) / maxf(absf(to_x - from_x), 1.0)
			var score: float = along * 4.0 + clampf(ahead, 40.0, 400.0) * 0.02
			score -= absf(ahead - 160.0) * 0.01
			if score > best_score:
				best_score = score
				best_pt = pt
				best_ok = true
		if best_ok:
			return best_pt
		var near_pt := Vector2.ZERO
		var near_d := INF
		for pt2 in charm_path_points:
			if absf(pt2.x - global_position.x) < fox_clear:
				continue
			if (pt2.x - from_x) * toward < 20.0:
				continue
			var d: float = absf(pt2.x - from_x)
			if d < near_d:
				near_d = d
				near_pt = pt2
		if near_d < INF:
			return near_pt

	var space := get_world_2d().direct_space_state
	if space == null:
		return _ray_ground_at(global_position.x)

	var sample_xs: Array[float] = []
	for t: float in [0.15, 0.28, 0.4, 0.55, 0.7, 0.85]:
		sample_xs.append(lerpf(from_x, to_x, t))
	for ox: float in [80.0, 140.0, 200.0, 280.0, 360.0, 450.0]:
		sample_xs.append(from_x + toward * ox)

	var best := Vector2.ZERO
	var best_ok2 := false
	var best_score2 := -INF
	for x: float in sample_xs:
		if absf(x - global_position.x) < fox_clear:
			continue
		var hit: Vector2 = _ray_ground_at(x, base_y - 160.0)
		if hit == Vector2.ZERO:
			hit = _ray_ground_at(x, global_position.y - 80.0)
		if hit == Vector2.ZERO:
			continue
		if absf(hit.x - global_position.x) < fox_clear:
			continue
		var along2: float = 1.0 - absf(x - lerpf(from_x, to_x, 0.45)) / maxf(absf(to_x - from_x), 1.0)
		var ahead2: float = (hit.x - from_x) * toward
		var dist_fox: float = absf(hit.x - global_position.x)
		var score2: float = along2 * 3.0 + clampf(ahead2, 0.0, 400.0) * 0.01 - absf(dist_fox - 200.0) * 0.02
		if ahead2 < 30.0:
			score2 -= 2.0
		if score2 > best_score2:
			best_score2 = score2
			best = hit
			best_ok2 = true

	if best_ok2:
		return best

	if player:
		for step: float in [120.0, 180.0, 260.0, 340.0]:
			var fx: float = player.global_position.x + toward * step
			if absf(fx - global_position.x) < fox_clear:
				continue
			var h2: Vector2 = _ray_ground_at(fx, player.global_position.y - 160.0)
			if h2 != Vector2.ZERO:
				return h2

	return _ray_ground_at(global_position.x + toward * 200.0, global_position.y - 120.0)


func _ray_ground_at(world_x: float, from_y: float = -INF) -> Vector2:
	var space := get_world_2d().direct_space_state
	if space == null:
		return Vector2.ZERO
	var y0 := from_y
	if y0 <= -INF:
		y0 = global_position.y - 40.0
	var from := Vector2(world_x, y0)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 720))
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit:
		return hit.position + Vector2(0, -2)
	return Vector2.ZERO


# -------------------- 幽蓝鬼火弹 --------------------
func _start_blast_windup() -> void:
	_is_winding_up = true
	_windup_left = blast_windup
	_windup_pos = global_position
	# 蓄力期间锚定漂浮基准，避免结束后瞬移
	_base_pos = Vector2(_base_pos.x, _windup_pos.y)


func _flash_lantern_windup() -> void:
	if lantern_light == null:
		return
	# 提灯快闪，给玩家反应时间
	var pulse := 0.45 + absf(sin(Time.get_ticks_msec() * 0.02)) * 1.1
	lantern_light.energy = pulse
	lantern_light.color = Color(0.55, 0.9, 1.0, 1.0)


func _restore_lantern_light() -> void:
	if lantern_light == null:
		return
	lantern_light.energy = _lantern_base_energy
	lantern_light.color = Color(0.4, 0.75, 1.0, 1.0)


func _fire_lantern_blast() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	var from := global_position
	if lantern_marker:
		from = lantern_marker.global_position

	var dir := Vector2.LEFT
	if is_instance_valid(player):
		dir = (player.global_position - from).normalized()
		if dir.length() < 0.01:
			dir = Vector2.LEFT

	var orb = MAGIC_ORB_SCENE.instantiate()
	# 进树前切模式，_ready 会贴 fox_light_orb
	if orb.has_method("setup_as_lantern_blast"):
		orb.setup_as_lantern_blast()
	parent.add_child(orb)
	if orb.has_method("begin_flight"):
		orb.begin_flight(from, dir)
	print("👻 提灯狐妖发射幽蓝鬼火弹")


# -------------------- 受击：提灯碎光 --------------------
## 魔法球命中：扣血，满 5 下后碎光
func take_damage(amount: int) -> void:
	if _is_dead or _shattered or amount <= 0:
		return
	current_hp -= amount
	_flash_hurt(Color(0.55, 0.85, 1.0, 1.0))
	if current_hp <= 0:
		_trigger_shatter()


func _on_damaged(_amount: int) -> void:
	pass


func _trigger_shatter() -> void:
	if _shattered:
		return
	_shattered = true
	_is_dead = true

	var parent := get_parent()
	var pos := global_position

	# 1) 玻璃碎裂特效
	if parent:
		ParticleFXUtil.glass_shatter(parent, pos)
	if lantern_light:
		lantern_light.enabled = false
	# 碎光自爆：走 GameManager 重击（禁止在本脚本硬编码 shake 参数）
	if GameManager:
		GameManager.trigger_heavy_impact()

	# 2) AOE：周围敌人受伤（不伤自己 / 玩家）
	_apply_shatter_aoe(pos)

	# 3) 掉落高纯度光点（吃到走玩家 collect_light_orb：满蓝 + orb_bonus）
	_spawn_shatter_orbs(parent, pos)

	print("💠 碎光反应！提灯狐妖碎裂")
	queue_free()


func _apply_shatter_aoe(center: Vector2) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or node == self:
			continue
		if node.global_position.distance_to(center) > shatter_aoe_radius:
			continue
		if node.has_method("take_damage"):
			node.take_damage(shatter_aoe_damage)


func _spawn_shatter_orbs(parent: Node, center: Vector2) -> void:
	if parent == null:
		return
	var count := randi_range(shatter_orb_min, shatter_orb_max)
	var min_y := _hover_min_y
	if min_y <= -INF:
		min_y = FLOOR_TOP_Y_REF - _default_max_air_rise()
	# 碎光星略低于狐妖，保证站跳能吃到
	var orb_ceiling := maxf(min_y + 24.0, FLOOR_TOP_Y_REF - _default_max_air_rise() + 8.0)
	for i in count:
		var orb = LIGHT_ORB_SCENE.instantiate()
		parent.add_child(orb)
		var ang := TAU * float(i) / float(count) + randf() * 0.4
		var radius := 28.0 + randf() * 24.0
		var pos := center + Vector2(cos(ang), sin(ang) * 0.35) * radius
		# Y 越大越低；钳制不要飞到二连跳够不着的高度
		pos.y = maxf(pos.y, orb_ceiling)
		pos.y = minf(pos.y, FLOOR_TOP_Y_REF - 36.0)
		orb.global_position = pos
		orb.scale = Vector2(0.04, 0.04)
		if orb.has_method("mark_as_shatter_drop"):
			orb.mark_as_shatter_drop()


func _on_death() -> void:
	# 碎光已自行处理特效；普通 die() 不重复播
	pass


func _flash_hurt(tint: Color) -> void:
	if anim == null:
		return
	var tw := create_tween()
	anim.modulate = tint
	tw.tween_property(anim, "modulate", Color.WHITE, 0.18)
