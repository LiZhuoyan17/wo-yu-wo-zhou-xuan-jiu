extends CharacterBody2D

const ParticleFXUtil = preload("res://particle_fx.gd")
const SHADOW_SCENE = preload("res://Shadow.tscn")

# ==================== 状态枚举 ====================
enum State {
	IDLE,
	RUN,
	JUMP,
	FALL,
	ATTACK,
	HURT,
	REWIND
}
# 魅惑是状态叠加（不替换上面枚举），避免打断 IDLE/RUN/JUMP/REWIND
# 🔥 引入魔法球模具
@export var magic_orb_scene: PackedScene 
# 魔法球在主角身前多远的位置生成（防止刚发射就碰到自己）
@export var orb_spawn_offset: float = 30.0 
# 贴脸自动索敌距离：在此范围内开火会朝向最近的怪，并保证能打中
@export var point_blank_range: float = 45.0

# 在脚本顶部，其他 @export 变量下面添加
@export var shadow_texture: Texture2D

# ==================== 移动参数 ====================
@export var max_speed: float = 200.0
@export var acceleration: float = 1000.0
@export var friction: float = 1500.0

# ==================== 跳跃与重力 ====================
@export var gravity: float = 1000.0
@export var jump_velocity: float = -456.0
## 空中二段跳初速度（略弱于一段，手感更稳）
@export var double_jump_velocity: float = -420.0
## 离地后额外可跳次数（1 = 二连跳）
@export var max_air_jumps: int = 1
var air_jumps_remaining: int = 1

@export var coyote_time_duration: float = 0.3
var coyote_timer: float = 0.0

@export var jump_buffer_duration: float = 0.3
var jump_buffer_timer: float = 0.0

## 梯子攀爬（不新增 State；与魅惑一样是叠加标记）
@export var climb_speed: float = 160.0
var on_ladder: bool = false
var _ladder_node: Node2D = null
var _ladder_mask_backup: int = -1 ## 攀爬时临时关掉与 Floor/Platform 的碰撞，否则下不去井
var _ladder_reentry_cooldown: float = 0.0 ## 从梯底离开后短暂禁止再抓，防吸回顶端
## 梯-平台连接处：连按两下 W → 跳跃（单击仍攀爬）
@export var w_double_tap_window: float = 0.28
var _w_double_tap_timer: float = 0.0
var _ladder_grab_suppress: float = 0.0 ## 连按 W 跳后短暂禁止再抓梯

## 所有离散按键（跳/射/攻/回溯）统一：按下后等 0.3s 再结算，避免 W+A+L 先跳再射
@export var input_judge_window: float = 0.3

# ==================== 攻击参数 ====================
@export var attack_speed_multiplier: float = 3.0
@export var attack_duration: float = 0.3
@export var attack_cooldown: float = 0.3
## 连按两下 J：二连攻击的突进距离 = 单击的该倍数
@export var attack_combo_distance_mult: float = 1.3
@export var attack_double_tap_window: float = 0.28
var attack_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var attack_direction: Vector2 = Vector2.RIGHT
var _attack_lunge_mult: float = 1.0 ## 1.0=单击；1.3=二连
var _attack_is_combo: bool = false
var _attack_second_hit_timer: float = -1.0 ## 二连中段再判定一次伤害
var _j_double_tap_timer: float = 0.0
var _want_double_attack: bool = false

# ==================== 回溯参数 ====================
@export var rewind_duration: float = 3.0
@export var rewind_cooldown: float = 1.0
@export var max_shadows: int = 2

var position_history: Array[Dictionary] = []
var history_interval: float = 1.0 / 60.0
var history_timer: float = 0.0
var rewind_cooldown_timer: float = 0.0
var is_rewinding: bool = false
var rewind_freeze_frames: int = 0

# ==================== 视觉参数 ====================
@export var inner_radius: float = 6.0
@export var max_offset: float = 12.0
@export var offset_damping: float = 8.0

var inner_offset: Vector2 = Vector2.ZERO
var facing: float = 1.0

## 光之门过场：锁定移动/攻击/射击/回溯输入（不改状态机枚举）
var input_locked: bool = false

var glow_sprite: Sprite2D
var original_glow_scale: Vector2 = Vector2(1.0, 1.0)

# ==================== 运动拖尾光斑 ====================
var trail_points: Array[Dictionary] = [] # {pos: Vector2, life: float}
@export var trail_spawn_distance: float = 14.0
@export var trail_lifetime: float = 0.35
var _last_trail_pos: Vector2 = Vector2.ZERO

# ==================== 影子相关 ====================
var shadows: Array[Dictionary] = []

# ==================== 视觉：能量白圆 + Squash&Stretch ====================
var energy_core: Sprite2D
var _player_sprite: Sprite2D
var _player_sprite_base_scale: Vector2 = Vector2(0.08, 0.08)
var _energy_core_base_scale: Vector2 = Vector2(1.0, 1.0)
var _visual_squash: Vector2 = Vector2.ONE
var _hurt_squash_timer: float = 0.0
var _sprite_tilt: float = 0.0
var _sprite_tilt_target: float = 0.0
var _sprite_tilt_hold: float = 0.0

# ==================== 状态机 ====================
var current_state: State = State.IDLE
var glow_texture: ImageTexture
var light_texture: GradientTexture2D   # Day 3 新增：光源纹理


# ==================== 成长系统参数（新增）====================
var current_glow_scale: float = 1.0  # 当前光晕大小（初始值和 original_glow_scale 保持一致）
var max_glow_scale: float = 2.5      # 光晕最大能长到多大
var glow_growth_step: float = 0.16   # 每吃一个光点，光晕变大多少

# ==================== HP / MP（Day 8 前置）====================
@export var max_hp: int = 5
var current_hp: int = 5
@export var max_mp: float = 10.0
var current_mp: float = 10.0
var mp_regen_duration: float = 6.0   # 基础回蓝间隔（秒）：每 6 秒回 1 点蓝
var mp_regen_timer: float = 0.0

# Day 8：吃光点强化（回蓝更快；发射固定扣满蓝 1/10）
@export var base_magic_orb_mp_cost: float = 1.0   # 兼容旧逻辑，实际以 max_mp/10 为准
@export var mp_cost_reduction_per_orb: float = 0.25
var orb_bonus_count: int = 0
var orb_bonus_regen: float = 0.0
var max_orb_bonus: int = 3

# 受击无敌（防止同一下被连续判定多次）
var hurt_invincible: bool = false
@export var hurt_invincible_duration: float = 0.8
@export var contact_damage: int = 1

# ==================== 魅惑（提灯狐妖光斑）====================
var is_charmed: bool = false
var charm_timer: float = 0.0
@export var charm_duration_default: float = 3.0
## 魅惑中按跳跃键的向上冲量（跃至半空）
@export var charm_leap_velocity: float = -720.0
var charm_leap_available: bool = false

# 【UI 贴图】屏幕固定 HUD（CanvasLayer，永远在画面左上角）
var hud: CanvasLayer
## 调试：周期写入玩家坐标，供外部读取 user://debug_player_pos.txt
var _debug_pos_timer: float = 0.0


func _ready() -> void:
	add_to_group("player")
	current_hp = max_hp
	current_mp = max_mp
	_setup_screen_hud()
	_write_debug_player_pos(true)
	
	# --- 1. 径向渐变光晕：中心亮、向外逐渐变暗淡出 ---
	var glow_size := 128
	var glow_img := Image.create(glow_size, glow_size, false, Image.FORMAT_RGBA8)
	var glow_center := Vector2(glow_size / 2.0, glow_size / 2.0)
	var glow_radius := glow_size / 2.0

	for x in range(glow_size):
		for y in range(glow_size):
			var dist := Vector2(float(x), float(y)).distance_to(glow_center)
			var t := clampf(1.0 - dist / glow_radius, 0.0, 1.0)
			# 平滑扩散：越靠外越暗、越透明（整体略提亮 ×1.2）
			var falloff := pow(t, 2.2)
			var alpha := falloff * 0.94
			# 暖黄略更黄、略更亮
			var col := Color(
				lerpf(0.95, 1.0, falloff),
				lerpf(0.76, 0.9, falloff),
				lerpf(0.32, 0.48, falloff),
				alpha
			)
			glow_img.set_pixel(x, y, col)

	glow_texture = ImageTexture.create_from_image(glow_img)

	# --- 2. 获取光源节点并设置 ---
	glow_sprite = get_node("Sprite_light")
	if glow_sprite is Sprite2D:
		glow_sprite.texture = glow_texture
		glow_sprite.scale = original_glow_scale
		glow_sprite.modulate = Color(1.0, 0.92, 0.55, 1.0)
		glow_sprite.z_index = -1
		glow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	# --- 3. 确保 rewind 输入动作存在 ---
	if not InputMap.has_action("rewind"):
		InputMap.add_action("rewind")
		var event = InputEventKey.new()
		event.keycode = KEY_K
		InputMap.action_add_event("rewind", event)

	# --- 4. Day 3：生成光源用的径向渐变纹理 ---
	light_texture = GradientTexture2D.new()
	light_texture.width = 256
	light_texture.height = 256
	light_texture.fill = GradientTexture2D.FILL_RADIAL
	light_texture.fill_from = Vector2(0.5, 0.5)
	light_texture.fill_to = Vector2(1.0, 0.5)

	# 暖黄真实光源：中心别过曝，边缘柔和淡出
	var light_gradient := Gradient.new()
	light_gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	light_gradient.colors = PackedColorArray([
		Color(1.0, 0.9, 0.5, 0.58),
		Color(1.0, 0.82, 0.4, 0.26),
		Color(0.95, 0.7, 0.28, 0.0),
	])
	light_texture.gradient = light_gradient

	# RealLight：压中心亮度，保留照地范围
	var real_light = get_node_or_null("RealLight")
	if real_light is PointLight2D:
		real_light.texture = light_texture
		real_light.color = Color(1.0, 0.9, 0.5, 1.0)
		real_light.energy = 0.12 ## 默认跟 L1；进关后由 GameManager Tween 到本关亮度
		real_light.texture_scale = 1.0

	_last_trail_pos = global_position
	_setup_energy_core_visual()
	var story_dm := get_node_or_null("/root/DialogueManager")
	if story_dm:
		if story_dm.has_signal("dialogue_started") and not story_dm.dialogue_started.is_connected(_on_story_dialogue_started):
			story_dm.dialogue_started.connect(_on_story_dialogue_started)
		if story_dm.has_signal("dialogue_finished") and not story_dm.dialogue_finished.is_connected(_on_story_dialogue_finished):
			story_dm.dialogue_finished.connect(_on_story_dialogue_finished)
	_player_sprite = get_node_or_null("PlayerSprite") as Sprite2D
	if _player_sprite:
		_player_sprite_base_scale = _player_sprite.scale
	
		# --- 5. 魔法球输入（L 键 / 鼠标右键；由 GameManager 统一优化绑定）---
	if not InputMap.has_action("shoot_orb"):
		InputMap.add_action("shoot_orb")
		var mouse_event = InputEventMouseButton.new()
		mouse_event.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("shoot_orb", mouse_event)
		var key_event = InputEventKey.new()
		key_event.physical_keycode = KEY_L
		key_event.keycode = KEY_L
		InputMap.action_add_event("shoot_orb", key_event)
		



func _physics_process(delta: float) -> void:
	var tree := get_tree()
	if tree and tree.paused:
		return
	var dm := get_node_or_null("/root/DialogueManager")
	if dm and dm.has_method("is_dialogue_active") and dm.is_dialogue_active():
		return

	_debug_pos_timer -= delta
	if _debug_pos_timer <= 0.0:
		_debug_pos_timer = 0.25
		_write_debug_player_pos(false)

	# --- 计时器更新 ---
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta
	if rewind_cooldown_timer > 0:
		rewind_cooldown_timer -= delta
	if _j_double_tap_timer > 0.0:
		_j_double_tap_timer -= delta
	if _w_double_tap_timer > 0.0:
		_w_double_tap_timer -= delta
	if _ladder_grab_suppress > 0.0:
		_ladder_grab_suppress -= delta
	if is_charmed:
		charm_timer -= delta
		if charm_timer <= 0.0:
			_clear_charm()

	_update_diagonal_combo_stamps(delta)
	if _diagonal_lock_timer > 0.0:
		_diagonal_lock_timer -= delta

	# --- 0.3s 输入判定窗：收集意图，到期统一结算 ---
	# 受击(HURT)时仍可发光球：贴脸立即射出，不进判定窗（避免顿帧把 0.3s 拖很长）
	# 跳跃：受击中也应收键，否则站在台上只能走不能跳，像“W/空格失灵”
	if not is_rewinding and not input_locked:
		if magic_orb_scene and Input.is_action_just_pressed("shoot_orb"):
			if current_state == State.HURT:
				_try_shoot_magic_orb()
			else:
				_queue_input_intent("shoot")
		if Input.is_action_just_pressed("ui_accept"):
			_handle_jump_accept_press()
		if current_state != State.HURT:
			# J：单击攻击；短时间内再按 → 二连攻击（突进距离×1.3，两段伤害）
			if Input.is_action_just_pressed("attack"):
				if _j_double_tap_timer > 0.0:
					_j_double_tap_timer = 0.0
					_want_double_attack = true
					if current_state == State.ATTACK and not _attack_is_combo:
						_upgrade_attack_to_combo()
					elif current_state != State.ATTACK and attack_cooldown_timer <= 0.0:
						# 判定窗内升级，或立刻开二连
						if _intent_attack:
							pass ## resolve 时读 _want_double_attack
						else:
							_start_melee_attack(true)
				elif current_state != State.ATTACK and attack_cooldown_timer <= 0.0:
					_want_double_attack = false
					_queue_input_intent("attack")
					_j_double_tap_timer = attack_double_tap_window
			if rewind_cooldown_timer <= 0.0 and Input.is_action_just_pressed("rewind") and position_history.size() > 10:
				_queue_input_intent("rewind")

	if _judge_active and not input_locked:
		# 用真实时间扣判定窗：顿帧 time_scale=0.05 时若用 physics delta，0.3s 会被拉成数秒，像跳键失灵
		var judge_dt := delta
		var ts := Engine.time_scale
		if ts > 0.0001 and ts < 0.999:
			judge_dt = delta / ts
		_judge_timer -= judge_dt
		if _judge_timer <= 0.0:
			_resolve_input_judge()
	elif input_locked and _judge_active:
		_clear_input_intents()
		_judge_active = false
		_judge_timer = 0.0

	# --- 位置历史记录（每帧记录） ---
	if not is_rewinding:
		history_timer += delta
		if history_timer >= history_interval:
			history_timer = 0.0
			position_history.append({
				"pos": global_position,
				"facing": facing
			})
			var max_records = int(rewind_duration / history_interval)
			while position_history.size() > max_records:
				position_history.pop_front()

	# --- 重力与土狼时间 ---
	if not is_rewinding:
		_repair_ladder_collision_mask()
		_update_ladder_state()
		if on_ladder:
			coyote_timer = 0.0
			# 攀爬时不受重力；W/S 上下，A/D 轻移并贴梯心
			velocity.y = 0.0
		elif not is_on_floor():
			velocity.y += gravity * delta
			coyote_timer -= delta
		else:
			coyote_timer = coyote_time_duration
			air_jumps_remaining = max_air_jumps

	var suppress_move_jump := _should_suppress_move_and_jump()

	# --- 攻击中：突进（单击×1 / 二连×1.3）---
	if current_state == State.ATTACK:
		if attack_timer > 0:
			velocity.x = max_speed * attack_speed_multiplier * _attack_lunge_mult * attack_direction.x
			velocity.y = 0.0
			attack_timer -= delta
			if _attack_second_hit_timer >= 0.0:
				_attack_second_hit_timer -= delta
				if _attack_second_hit_timer < 0.0:
					_try_ground_melee_hit()
		else:
			_attack_is_combo = false
			_attack_lunge_mult = 1.0
			_attack_second_hit_timer = -1.0
			if glow_sprite:
				glow_sprite.scale = original_glow_scale
				glow_sprite.modulate = Color(1.0, 0.92, 0.55, 1.0)
			if is_on_floor():
				_change_state(State.IDLE)
			else:
				_change_state(State.FALL)

	# --- 非攻击状态才处理移动和跳跃 ---
	if current_state != State.ATTACK and not is_rewinding:
		if input_locked:
			jump_buffer_timer = 0.0
			_leave_ladder()
			velocity.x = move_toward(velocity.x, 0.0, friction * delta * 2.0)
		elif on_ladder:
			_process_ladder_move(delta)
		elif suppress_move_jump:
			# 判定窗内跳/射：不跳、不左右走（防止 W+A+L 先斜跳再打）
			jump_buffer_timer = 0.0
			facing = _combo_side_facing()
			velocity.x = move_toward(velocity.x, 0.0, friction * delta * 2.0)
		else:
			if jump_buffer_timer > 0:
				if is_on_floor() or coyote_timer > 0:
					_perform_jump(false)
				elif air_jumps_remaining > 0:
					_perform_jump(true)

			var input_dir: float = Input.get_axis("ui_left", "ui_right")
			if is_charmed:
				input_dir *= -1.0
			if input_dir != 0.0:
				velocity.x = move_toward(velocity.x, input_dir * max_speed, acceleration * delta)
				facing = input_dir
			else:
				velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	# --- 移动（攀爬时不 move_and_slide，避免又吸回台面导致按 S 下不去）---
	if rewind_freeze_frames > 0:
		rewind_freeze_frames -= 1
	elif not is_rewinding and not on_ladder:
		move_and_slide()
	elif on_ladder:
		velocity = Vector2.ZERO

	# --- 白圆偏移 ---
	var target_offset = Vector2.ZERO
	var h_ratio = clampf(abs(velocity.x) / max_speed, 0.0, 1.0)
	if h_ratio > 0.05:
		target_offset.x = sign(velocity.x) * h_ratio * max_offset
	var v_ratio = clampf(abs(velocity.y) / abs(jump_velocity), 0.0, 1.0)
	if v_ratio > 0.05:
		target_offset.y = sign(velocity.y) * v_ratio * max_offset
	inner_offset = inner_offset.lerp(target_offset, offset_damping * delta)

	# --- 状态更新 ---
	if current_state != State.ATTACK and current_state != State.HURT and not is_rewinding:
		_update_state()

	# 【Day 8】蓝量自动回复：吃光点后回蓝速度更快（每颗 +0.05 倍）
	if current_mp < max_mp:
		mp_regen_timer += delta
		# 实际间隔 = 基础间隔 / (1 + 加成)。例：吃 2 颗 → 速度 1.10 倍 → 间隔变短
		var regen_speed := 1.0 + orb_bonus_regen
		var actual_regen_time = max(2.0, mp_regen_duration / regen_speed)
		if mp_regen_timer >= actual_regen_time:
			mp_regen_timer = 0.0
			current_mp += 1.0
			if current_mp > max_mp:
				current_mp = max_mp
			_update_hud()

		# --- 视觉：光晕跟随偏移 + 拖尾光斑 + 挤压拉伸 ---
	if glow_sprite:
		glow_sprite.position = inner_offset
	_update_motion_trail(delta)
	_update_squash_stretch(delta)
	_prune_dead_shadows()

	if _player_sprite:
		# 脚底对齐碰撞底，避免贴图中心偏下穿进地面
		_player_sprite.position = inner_offset + Vector2(0, -10)
		_player_sprite.flip_h = facing > 0
		_player_sprite.scale = Vector2(
			_player_sprite_base_scale.x * _visual_squash.x,
			_player_sprite_base_scale.y * _visual_squash.y
		)
		_update_aim_tilt(delta)
		_player_sprite.rotation = _sprite_tilt
	if energy_core:
		energy_core.position = inner_offset + Vector2(0, -10)
		energy_core.scale = Vector2(
			_energy_core_base_scale.x * _visual_squash.x,
			_energy_core_base_scale.y * _visual_squash.y
		)
		energy_core.rotation = _sprite_tilt * 0.5
	queue_redraw()


func _update_motion_trail(delta: float) -> void:
	# 更新已有拖尾寿命
	var i := 0
	while i < trail_points.size():
		trail_points[i]["life"] = float(trail_points[i]["life"]) - delta
		if float(trail_points[i]["life"]) <= 0.0:
			trail_points.remove_at(i)
		else:
			i += 1

	# 移动足够远就留下一颗光斑
	if global_position.distance_to(_last_trail_pos) >= trail_spawn_distance:
		if absf(velocity.x) > 20.0 or absf(velocity.y) > 20.0:
			trail_points.append({
				"pos": global_position + inner_offset,
				"life": trail_lifetime
			})
			_last_trail_pos = global_position
			# 限制数量，避免太密
			while trail_points.size() > 18:
				trail_points.pop_front()


# ==================== 回溯触发 ====================
func _trigger_rewind() -> void:
	is_rewinding = true

	var target_record = position_history[0]
	var target_pos: Vector2 = target_record["pos"]
	var target_facing: float = target_record["facing"]

	var parent := get_parent()
	var depart_pos := global_position

	# 离开点金色粒子 + 影子
	if parent:
		ParticleFXUtil.rewind_depart(parent, depart_pos)
	_spawn_shadow(depart_pos, facing)

	global_position = target_pos
	facing = target_facing
	velocity = Vector2.ZERO

	# 到达点青白粒子
	if parent:
		ParticleFXUtil.rewind_arrive(parent, target_pos)

	# 受击中回溯：清除硬直/无敌，算作成功脱身
	hurt_invincible = false

	rewind_cooldown_timer = rewind_cooldown
	is_rewinding = false
	rewind_freeze_frames = 3
	history_timer = 0.0

	position_history.clear()

	_change_state(State.IDLE)

	print("回溯完成！影子数量：", shadows.size())


# ==================== 影子生成（实体诱饵 Shadow.tscn） ====================
## 回溯离开点留下物理影子；不改 State 枚举 / 蓝条 / 历史点回溯逻辑
func _spawn_shadow(pos: Vector2, face_dir: float) -> void:
	_prune_dead_shadows()
	# 超量：挤掉最旧实体，保证内存有上限（max_shadows）
	while shadows.size() >= max_shadows:
		var oldest = shadows.pop_front()
		if is_instance_valid(oldest.get("node")):
			var n: Node = oldest["node"]
			if n.has_method("dissolve"):
				n.dissolve()
			else:
				n.queue_free()

	var parent := get_parent()
	if parent == null:
		return

	# 实例化实体，挂到与主角同级（主场景下），怪才能扫到 active_shadows
	var shadow_node = SHADOW_SCENE.instantiate()
	parent.add_child(shadow_node)
	# 略低于主角绘制，避免挡住主角精灵
	shadow_node.z_index = self.z_index - 1

	var player_radius := _get_player_collision_radius()
	if shadow_node.has_method("setup"):
		shadow_node.setup(pos, face_dir, shadow_texture, light_texture, player_radius)
	else:
		shadow_node.global_position = pos

	shadows.append({"pos": pos, "facing": face_dir, "node": shadow_node})
	print("实体诱饵影子生成在：", pos)


func _get_player_collision_radius() -> float:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs and cs.shape is CircleShape2D:
		return (cs.shape as CircleShape2D).radius
	return 10.0


func _prune_dead_shadows() -> void:
	var i := 0
	while i < shadows.size():
		var node = shadows[i].get("node")
		# 被击碎 / 超时 queue_free 后，从引用表摘掉，防悬挂
		if not is_instance_valid(node):
			shadows.remove_at(i)
		elif node.has_method("is_shadow_alive") and not node.is_shadow_alive():
			shadows.remove_at(i)
		else:
			shadows[i]["pos"] = node.global_position
			i += 1


## 软清理：关卡重置前或需要时调用（reload 场景本身也会销毁节点）
func clear_all_shadow_entities() -> void:
	_prune_dead_shadows()
	for entry in shadows:
		var node = entry.get("node")
		if is_instance_valid(node):
			if node.has_method("dissolve"):
				node.dissolve()
			else:
				node.queue_free()
	shadows.clear()


## 光之门过场锁输入；重生时自动解锁
func set_input_locked(locked: bool) -> void:
	input_locked = locked
	if locked:
		_clear_input_intents()
		jump_buffer_timer = 0.0
		_j_double_tap_timer = 0.0
		_want_double_attack = false


func _on_story_dialogue_started() -> void:
	set_input_locked(true)


func _on_story_dialogue_finished() -> void:
	set_input_locked(false)


## 关卡出生点：瞬移 + 清影子/历史，重置战斗资源（不改 State 枚举定义）
func _write_debug_player_pos(force_print: bool = false) -> void:
	var line := "player_pos=%.2f,%.2f floor=%s ladder=%s state=%s\n" % [
		global_position.x,
		global_position.y,
		str(is_on_floor()),
		str(on_ladder),
		str(current_state)
	]
	var f := FileAccess.open("user://debug_player_pos.txt", FileAccess.WRITE)
	if f:
		f.store_string(line)
		f.close()
	if force_print:
		print("📍 ", line.strip_edges())


func reset_at_spawn(spawn_pos: Vector2) -> void:
	global_position = spawn_pos
	velocity = Vector2.ZERO
	is_rewinding = false
	hurt_invincible = false
	rewind_freeze_frames = 0
	position_history.clear()
	clear_all_shadow_entities()
	set_input_locked(false)
	# 清输入判定残留，防止进关后被锁移动
	_intent_jump = false
	_intent_shoot = false
	_intent_attack = false
	_intent_rewind = false
	_judge_active = false
	_judge_timer = 0.0
	_diagonal_lock_timer = 0.0
	jump_buffer_timer = 0.0
	air_jumps_remaining = max_air_jumps
	_leave_ladder()
	_j_double_tap_timer = 0.0
	_w_double_tap_timer = 0.0
	_ladder_grab_suppress = 0.0
	_want_double_attack = false
	_attack_is_combo = false
	_attack_lunge_mult = 1.0
	_attack_second_hit_timer = -1.0
	attack_timer = 0.0
	Engine.time_scale = 1.0
	current_hp = max_hp
	current_mp = max_mp
	mp_regen_timer = 0.0
	if is_charmed:
		_clear_charm()
	_change_state(State.IDLE)
	_update_hud()
	print("重生于 SpawnPoint：", spawn_pos)


func _setup_energy_core_visual() -> void:
	# 程序圆贴图 + Shader，只改视觉，不碰 CollisionShape2D
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size / 2.0 - 1.0
	for x in range(size):
		for y in range(size):
			var d := Vector2(float(x), float(y)).distance_to(center)
			var a := clampf(1.0 - d / radius, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))

	energy_core = Sprite2D.new()
	energy_core.name = "EnergyCore"
	energy_core.texture = ImageTexture.create_from_image(img)
	energy_core.z_index = 2
	energy_core.centered = true
	var base := 0.42 # 约 27px 直径，对应白圆视觉，不改碰撞
	_energy_core_base_scale = Vector2(base, base)
	energy_core.scale = _energy_core_base_scale

	var shader := load("res://player_shader.gdshader") as Shader
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		energy_core.material = mat

	add_child(energy_core)


## 挤压拉伸：只改 Sprite 视觉 scale，碰撞体不变
## 含：起跳/下落竖直形变、撞墙水平挤压、受击水平挤压
func _update_squash_stretch(delta: float) -> void:
	var target := Vector2.ONE

	# 水平撞墙：压扁（变窄变高）
	if is_on_wall() and absf(get_real_velocity().x) > 8.0:
		target = Vector2(0.7, 1.22)
	elif is_on_floor() and absf(velocity.y) < 20.0 and absf(velocity.x) < 15.0:
		target = Vector2.ONE
	elif velocity.y < -50.0:
		target = Vector2(0.8, 1.2)
	elif velocity.y > 50.0:
		target = Vector2(1.2, 0.8)
	elif absf(velocity.x) > 80.0:
		# 快跑轻微水平拉长
		target = Vector2(1.08, 0.94)

	# 受击瞬间的水平挤压脉冲（优先）
	if _hurt_squash_timer > 0.0:
		_hurt_squash_timer -= delta
		target = Vector2(0.68, 1.28)

	_visual_squash = _visual_squash.lerp(target, 10.0 * delta)


## 受击时触发水平挤压感
func _pulse_hurt_squash() -> void:
	_hurt_squash_timer = 0.22
	_visual_squash = Vector2(0.62, 1.32)


## 斜向射击时身体短暂倾斜（不改碰撞）
func _update_aim_tilt(delta: float) -> void:
	if _sprite_tilt_hold > 0.0:
		_sprite_tilt_hold -= delta
	else:
		_sprite_tilt_target = lerpf(_sprite_tilt_target, 0.0, 8.0 * delta)
	_sprite_tilt = lerpf(_sprite_tilt, _sprite_tilt_target, 14.0 * delta)


func _apply_shoot_aim_tilt(shoot_dir: Vector2) -> void:
	# 上仰 / 下俯约 35°；flip_h 时符号与视觉一致
	var tilt := shoot_dir.y * deg_to_rad(38.0)
	if facing < 0.0:
		tilt = -tilt
	_sprite_tilt_target = tilt
	_sprite_tilt_hold = 0.28


# ==================== 屏幕左上角 HUD（相对屏幕固定，不跟世界坐标跑）====================
func _setup_screen_hud() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("_ensure_hud"):
		gm._ensure_hud()
	if gm and gm.get("_hud") is CanvasLayer:
		hud = gm.get("_hud") as CanvasLayer
	else:
		hud = preload("res://ui/hud/HUD.tscn").instantiate()
		add_child(hud)
	call_deferred("_update_hud")


func _update_hud() -> void:
	if hud and hud.has_method("update_bars"):
		hud.update_bars(current_hp, max_hp, current_mp, max_mp)


# ==================== 绘制：拖尾光斑 + 角色白核 + 影子 ====================
func _draw() -> void:
	# 1) 运动拖尾光斑（世界坐标转本地）
	for t in trail_points:
		var local_pos: Vector2 = t["pos"] - global_position
		var life_ratio: float = clampf(float(t["life"]) / trail_lifetime, 0.0, 1.0)
		var a := life_ratio * 0.45
		var r := inner_radius * (0.7 + life_ratio * 0.8)
		draw_circle(local_pos, r * 2.2, Color(1.0, 0.9, 0.5, a * 0.35))
		draw_circle(local_pos, r, Color(1.0, 0.95, 0.6, a * 0.9))

	# 2) 影子残光
	for shadow in shadows:
		var shadow_pos: Vector2 = shadow["pos"] - global_position
		draw_circle(shadow_pos, inner_radius * 6.0, Color(1.0, 0.85, 0.55, 0.04))
		draw_circle(shadow_pos, inner_radius * 4.5, Color(1.0, 0.85, 0.55, 0.08))
		draw_circle(shadow_pos, inner_radius * 3.0, Color(1.0, 0.85, 0.55, 0.12))
		draw_circle(shadow_pos, inner_radius * 2.0, Color(1.0, 0.85, 0.55, 0.18))

	# 3) 角色中心核改由 EnergyCore+Shader 绘制；此处只留极淡外晕
	draw_circle(inner_offset + Vector2(0, -10), inner_radius * 2.2, Color(1.0, 0.9, 0.55, 0.08))


# ==================== 收集光点反馈 ====================
func grow_glow() -> void:
	if current_glow_scale < max_glow_scale:
		current_glow_scale += glow_growth_step
		
		# 1. 更新光晕 Sprite 的大小
		if glow_sprite:
			glow_sprite.scale = Vector2(current_glow_scale, current_glow_scale)
			
		# 2. 更新代码里生成的光晕贴图大小（可选，如果你想让光晕边缘也跟着变大）
		# 注意：如果你不想改贴图大小，只改 scale 就足够有视觉冲击力了！
		
		print("光晕升级！当前大小：", current_glow_scale)


# 每发光球扣满蓝的 1/10（max_mp=10 → 扣 1）
func get_magic_orb_mp_cost() -> float:
	return max_mp / 10.0


## 贴脸范围内找最近的敌人
func _get_nearest_enemy_in_range(max_range: float) -> Node2D:
	var nearest: Node2D = null
	var best_dist := max_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist <= best_dist:
			best_dist = dist
			nearest = enemy
	return nearest


## 地面平 A：走 take_melee_damage（空中狐妖 immune_to_ground_melee 会挡下）
func _try_ground_melee_hit() -> void:
	var melee_range := 36.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_to(enemy.global_position) > melee_range:
			continue
		if enemy.has_method("take_melee_damage"):
			enemy.take_melee_damage(1)
		elif enemy.has_method("take_damage"):
			enemy.take_damage(1)


## 斜向自动瞄准范围（W+A/D+L 斜上；S+A/D+L 斜下）
@export var diagonal_auto_aim_range: float = 520.0
## 与 input_judge_window 同步：0.3s 内凑齐组合键
var diagonal_combo_window: float:
	get:
		return input_judge_window

var _combo_clock: float = 0.0
var _stamp_w: float = -999.0
var _stamp_s: float = -999.0
var _stamp_a: float = -999.0
var _stamp_d: float = -999.0
var _was_w: bool = false
var _was_s: bool = false
var _was_a: bool = false
var _was_d: bool = false
## 斜向射击后短锁：禁止跳/走
var _diagonal_lock_timer: float = 0.0

## 0.3s 输入判定窗：先收集意图，到期再执行
var _judge_active: bool = false
var _judge_timer: float = 0.0
var _intent_jump: bool = false
var _intent_shoot: bool = false
var _intent_attack: bool = false
var _intent_rewind: bool = false


## 直接读按键轴（不依赖 get_vector，避免 W 偶发读不到变成水平射）
func _read_move_aim_axes() -> Vector2:
	var x := 0.0
	var y := 0.0
	if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		y -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		y += 1.0
	if is_charmed:
		x *= -1.0
	return Vector2(x, y)


## 每帧刷新 W/S/A/D（按住刷新，方便判定窗内凑齐斜向）
func _update_diagonal_combo_stamps(delta: float) -> void:
	_combo_clock += delta
	var w_down := Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var s_down := Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	var a_down := Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var d_down := Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	if w_down:
		_stamp_w = _combo_clock
	if s_down:
		_stamp_s = _combo_clock
	if a_down:
		_stamp_a = _combo_clock
	if d_down:
		_stamp_d = _combo_clock
	_was_w = w_down
	_was_s = s_down
	_was_a = a_down
	_was_d = d_down


## 0.3s 内出现过 W + (A或D) → 斜上
func _is_diagonal_up_aim_gesture() -> bool:
	var w_ok := (_combo_clock - _stamp_w) <= diagonal_combo_window
	var a_ok := (_combo_clock - _stamp_a) <= diagonal_combo_window
	var d_ok := (_combo_clock - _stamp_d) <= diagonal_combo_window
	return w_ok and (a_ok or d_ok)


## 0.3s 内出现过 S + (A或D) → 斜下（规则同斜上，仅竖直反向）
func _is_diagonal_down_aim_gesture() -> bool:
	var s_ok := (_combo_clock - _stamp_s) <= diagonal_combo_window
	var a_ok := (_combo_clock - _stamp_a) <= diagonal_combo_window
	var d_ok := (_combo_clock - _stamp_d) <= diagonal_combo_window
	return s_ok and (a_ok or d_ok)


## 给教学 UI 查询用，不改状态机
func wants_diagonal_up_shot() -> bool:
	return _is_diagonal_up_aim_gesture()


func wants_diagonal_down_shot() -> bool:
	return _is_diagonal_down_aim_gesture()


## 兼容旧名：斜上
func _is_diagonal_aim_gesture() -> bool:
	return _is_diagonal_up_aim_gesture()


## 判定窗内可斜向射击（上或下）
func _is_diagonal_combo_buffered() -> bool:
	return _is_diagonal_up_aim_gesture() or _is_diagonal_down_aim_gesture()


## -1=斜上，+1=斜下，0=无；W/S 同窗时取更新近的一戳
func _diagonal_vertical_sign() -> float:
	var up := _is_diagonal_up_aim_gesture()
	var down := _is_diagonal_down_aim_gesture()
	if up and down:
		return -1.0 if _stamp_w >= _stamp_s else 1.0
	if up:
		return -1.0
	if down:
		return 1.0
	return 0.0


## 判定窗进行中且涉及跳/射，或斜向锁定期：禁止跳与左右走
func _should_suppress_move_and_jump() -> bool:
	if _diagonal_lock_timer > 0.0:
		return true
	if _judge_active and (_intent_jump or _intent_shoot):
		return true
	return false


## 按下离散键：进入 0.3s 判定窗（从第一键起算，不重置）
func _queue_input_intent(kind: String) -> void:
	match kind:
		"jump":
			_intent_jump = true
		"shoot":
			_intent_shoot = true
		"attack":
			_intent_attack = true
		"rewind":
			_intent_rewind = true
	if not _judge_active:
		_judge_active = true
		_judge_timer = input_judge_window


func _clear_input_intents() -> void:
	_intent_jump = false
	_intent_shoot = false
	_intent_attack = false
	_intent_rewind = false
	_judge_active = false
	_judge_timer = 0.0


## 0.3s 到期：按优先级结算（射 > 攻 > 回溯 > 跳）；同窗有射则吞掉跳
func _resolve_input_judge() -> void:
	var want_jump := _intent_jump
	var want_shoot := _intent_shoot
	var want_attack := _intent_attack
	var want_rewind := _intent_rewind
	_clear_input_intents()

	# 同窗射击：W 只作瞄准，绝不跳
	if want_shoot:
		want_jump = false
		_try_shoot_magic_orb()

	if want_attack and current_state != State.ATTACK and current_state != State.HURT and not is_rewinding and attack_cooldown_timer <= 0.0:
		_start_melee_attack(_want_double_attack)
		_want_double_attack = false

	if want_rewind and not is_rewinding and rewind_cooldown_timer <= 0.0 and position_history.size() > 10:
		_trigger_rewind()

	if want_jump and not is_rewinding and current_state != State.ATTACK:
		# 已在攀爬：判定窗里的跳意图作废（W 曾兼跳跃时尤其容易误触）
		# 若人其实站在台面上却仍标着 on_ladder，则清掉梯子再跳（防空格失灵）
		if on_ladder and is_on_floor():
			_leave_ladder()
		if on_ladder:
			pass
		elif is_charmed and charm_leap_available:
			velocity.y = charm_leap_velocity
			charm_leap_available = false
			jump_buffer_timer = 0.0
			coyote_timer = 0.0
			_change_state(State.JUMP)
			_play_sfx("jump")
		elif is_on_floor() or coyote_timer > 0:
			# 落地/土狼：立刻一段跳
			_perform_jump(false)
		elif air_jumps_remaining > 0:
			# 空中：立刻二段跳
			_perform_jump(true)
		else:
			# 已用尽空中跳：保留落地缓冲
			jump_buffer_timer = jump_buffer_duration


## 一段跳（地面/土狼）或二段跳（空中）；不新增 State 枚举
func _perform_jump(is_air_jump: bool) -> void:
	if is_air_jump:
		if air_jumps_remaining <= 0:
			return
		air_jumps_remaining -= 1
		velocity.y = double_jump_velocity
	else:
		velocity.y = jump_velocity
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	_leave_ladder()
	_change_state(State.JUMP)
	_play_sfx("jump")


## 平 A：单击突进×1；二连突进×attack_combo_distance_mult，并打两段伤害
func _start_melee_attack(is_combo: bool) -> void:
	_leave_ladder()
	attack_direction = Vector2(facing, 0.0)
	if absf(attack_direction.x) < 0.1:
		attack_direction.x = 1.0
	_attack_is_combo = is_combo
	_attack_lunge_mult = attack_combo_distance_mult if is_combo else 1.0
	attack_timer = attack_duration
	attack_cooldown_timer = attack_cooldown
	_change_state(State.ATTACK)
	_play_sfx("attack")
	_try_ground_melee_hit()
	# 二连：攻击中段再判一次伤
	_attack_second_hit_timer = attack_duration * 0.45 if is_combo else -1.0
	if glow_sprite:
		var grow := 1.65 if is_combo else 1.5
		glow_sprite.scale = original_glow_scale * grow
		glow_sprite.modulate = Color(1.0, 0.95, 0.6, 1.0) if is_combo else Color(1.0, 0.92, 0.55, 1.0)


## 攻击已开始时补按第二下 J → 升成二连（拉满剩余突进到 1.3 倍距离）
func _upgrade_attack_to_combo() -> void:
	if _attack_is_combo or current_state != State.ATTACK:
		return
	_attack_is_combo = true
	_attack_lunge_mult = attack_combo_distance_mult
	# 剩余时间按比例拉长一点，让总位移更接近 1.3×
	attack_timer = maxf(attack_timer, attack_duration * 0.55)
	if _attack_second_hit_timer < 0.0:
		_attack_second_hit_timer = minf(attack_timer * 0.5, attack_duration * 0.35)
	if glow_sprite:
		glow_sprite.scale = original_glow_scale * 1.65
		glow_sprite.modulate = Color(1.0, 0.95, 0.6, 1.0)


## 空格/W 跳跃键处理：梯-平台连接处连按两下 W → 跳；单击 W 仍爬
func _handle_jump_accept_press() -> void:
	var space_down := Input.is_physical_key_pressed(KEY_SPACE)
	var w_down := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)

	# 站在台面上却仍挂着梯子标记：先摘掉，否则空格会被静默吞掉
	if on_ladder and is_on_floor() and not (Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)):
		_leave_ladder()

	# 空格：始终可跳（梯子中段仍可跳离）
	if space_down and not w_down:
		if on_ladder:
			_leave_ladder()
			_perform_jump(false)
			air_jumps_remaining = max_air_jumps
			return
		_queue_input_intent("jump")
		return
	if space_down and w_down:
		# 同时按：优先跳
		if on_ladder:
			_leave_ladder()
		_ladder_grab_suppress = 0.2
		_w_double_tap_timer = 0.0
		_queue_input_intent("jump")
		return

	# 仅 W/↑
	if not w_down:
		_queue_input_intent("jump")
		return

	if _at_ladder_platform_junction():
		if _w_double_tap_timer > 0.0:
			# 连按第二下 → 立刻跳跃，不攀爬、不等判定窗
			_w_double_tap_timer = 0.0
			_ladder_grab_suppress = 0.28
			var was_on_ladder := on_ladder
			if on_ladder:
				_leave_ladder()
			_intent_jump = false
			if not is_rewinding and current_state != State.ATTACK:
				if is_on_floor() or coyote_timer > 0.0 or was_on_ladder:
					_perform_jump(false)
					air_jumps_remaining = max_air_jumps
				elif air_jumps_remaining > 0:
					_perform_jump(true)
				else:
					_queue_input_intent("jump")
			return
		# 第一下：武装连按窗；若可爬则留给梯子，不跳
		_w_double_tap_timer = w_double_tap_window
		if on_ladder or _w_should_climb_instead_of_jump():
			return
		_queue_input_intent("jump")
		return

	if on_ladder:
		return ## 梯子中段：W 只爬，空格跳离
	if _w_should_climb_instead_of_jump():
		return
	_queue_input_intent("jump")


## 是否在梯子与 Platform/Floor 衔接带（顶或底）
func _at_ladder_platform_junction() -> bool:
	var ladder: Node2D = _ladder_node if on_ladder and is_instance_valid(_ladder_node) else null
	if ladder == null:
		ladder = _find_touching_ladder(true)
		if ladder == null:
			ladder = _find_touching_ladder(false)
	if ladder == null or not _is_aligned_to_ladder_shaft(ladder):
		return false
	var top_y := global_position.y
	var bot_y := global_position.y
	if ladder.has_method("get_climb_top_y"):
		top_y = float(ladder.call("get_climb_top_y"))
	if ladder.has_method("get_climb_bottom_y"):
		bot_y = float(ladder.call("get_climb_bottom_y"))
	var feet_y := global_position.y + 10.0
	# 站在上台/下台衔接
	if is_on_floor() and feet_y <= top_y + 28.0:
		return true
	if is_on_floor() and feet_y >= bot_y - 36.0:
		return true
	# 攀爬中靠近顶/底衔接
	if on_ladder and global_position.y <= top_y + 36.0:
		return true
	if on_ladder and global_position.y >= bot_y - 40.0:
		return true
	return false


## 重叠 climb_ladders 且按上下键（或已在攀爬）→ 进入梯子
## 站在梯顶平台：按 W 不抓梯；按 S 下井
## 水平必须贴柱身正中（几乎不外扩），否则短岛上 W/S 会被整段吸进梯子
func _update_ladder_state() -> void:
	if _ladder_reentry_cooldown > 0.0:
		_ladder_reentry_cooldown = maxf(_ladder_reentry_cooldown - get_physics_process_delta_time(), 0.0)
	if input_locked or is_rewinding or current_state == State.ATTACK or current_state == State.HURT:
		_leave_ladder()
		return
	var climb_axis := _read_climb_axis()
	var want_down := climb_axis > 0.1
	var want_up := climb_axis < -0.1
	# 连按 W 刚跳起：短暂禁止再被吸进梯子
	if _ladder_grab_suppress > 0.0 and want_up and not want_down:
		if on_ladder:
			_leave_ladder()
		return
	var ladder := _find_touching_ladder(want_down)
	if ladder == null:
		_leave_ladder()
		return

	var top_y := global_position.y
	var bot_y := global_position.y
	if ladder.has_method("get_climb_top_y"):
		top_y = float(ladder.call("get_climb_top_y"))
	if ladder.has_method("get_climb_bottom_y"):
		bot_y = float(ladder.call("get_climb_bottom_y"))

	var feet_y := global_position.y + 10.0
	var at_top_surface := is_on_floor() and feet_y <= top_y + 22.0
	var at_bottom_surface := is_on_floor() and feet_y >= bot_y - 28.0
	var near_bottom := global_position.y >= bot_y - 22.0
	var near_top := global_position.y <= top_y + 18.0

	if on_ladder:
		# 任意站在地面且没按 S 下井 → 退出攀爬（不只梯顶），避免台上空格被吞
		if is_on_floor() and not want_down:
			_leave_ladder()
		return

	if not want_up and not want_down:
		return
	if _ladder_grab_suppress > 0.0 and want_up:
		return
	if _ladder_reentry_cooldown > 0.0 and want_down and not want_up:
		return
	if near_bottom and want_down and not want_up:
		return
	# 必须对齐柱心：站在岛上但偏开梯子时，W/S 只作移动/瞄准，不抓梯
	if not _is_aligned_to_ladder_shaft(ladder):
		return

	if is_on_floor():
		if want_down and at_top_surface:
			_enter_ladder(ladder, true)
		elif want_up and at_bottom_surface:
			_enter_ladder(ladder, false)
		# 地面上既不在梯顶也不在梯底：绝不抓梯（把 W/S 留给跳跃判定窗等）
	else:
		# 空中：仍须贴柱身；仅在柱内才可抓
		if near_top and want_down:
			_enter_ladder(ladder, true)
		elif want_up or want_down:
			_enter_ladder(ladder, false)


func _is_aligned_to_ladder_shaft(ladder: Node2D) -> bool:
	var cx := ladder.global_position.x
	var half := 12.0
	if ladder.has_method("get_climb_center_x"):
		cx = float(ladder.call("get_climb_center_x"))
	if ladder.has_method("get_climb_half_width"):
		half = float(ladder.call("get_climb_half_width"))
	# 角色圆心约 10px，只允许柱半宽 + 极小余量
	return absf(global_position.x - cx) <= half + 4.0


func _read_climb_axis() -> float:
	var climb_axis := Input.get_axis("ui_up", "ui_down")
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		climb_axis = -1.0
	elif Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		climb_axis = 1.0
	return climb_axis


## W 刚按下且对齐可上爬的梯子 → 爬，不进跳跃判定窗（空格仍跳）
func _w_should_climb_instead_of_jump() -> bool:
	if Input.is_physical_key_pressed(KEY_SPACE):
		return false
	if not (Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)):
		return false
	var ladder := _find_touching_ladder(false)
	if ladder == null or not _is_aligned_to_ladder_shaft(ladder):
		return false
	var top_y := global_position.y
	var bot_y := global_position.y
	if ladder.has_method("get_climb_top_y"):
		top_y = float(ladder.call("get_climb_top_y"))
	if ladder.has_method("get_climb_bottom_y"):
		bot_y = float(ladder.call("get_climb_bottom_y"))
	var feet_y := global_position.y + 10.0
	# 梯顶按 W = 跳离台面，不抓梯
	if is_on_floor() and feet_y <= top_y + 22.0:
		return false
	# 梯底上爬，或空中贴柱
	if is_on_floor() and feet_y >= bot_y - 28.0:
		return true
	if not is_on_floor():
		return true
	return false


func _enter_ladder(ladder: Node2D, from_top_down: bool = false) -> void:
	on_ladder = true
	_ladder_node = ladder
	# 进梯清掉跳跃意图/缓冲，避免上一帧空格或旧缓冲把人弹下
	jump_buffer_timer = 0.0
	_intent_jump = false
	if _ladder_mask_backup < 0:
		_ladder_mask_backup = collision_mask
		# Floor/Platform 在 layer 1；关掉后才能穿过台面下井/上爬
		collision_mask = collision_mask & ~1
	# 仅站在上台按 S 时沉入井口；人已在中下部时禁止吸回顶端
	if from_top_down and ladder.has_method("get_climb_top_y"):
		var top_y := float(ladder.call("get_climb_top_y"))
		var bot_y := top_y + 80.0
		if ladder.has_method("get_climb_bottom_y"):
			bot_y = float(ladder.call("get_climb_bottom_y"))
		if global_position.y <= top_y + 40.0:
			global_position.y = clampf(top_y + 16.0, top_y + 8.0, bot_y - 20.0)
			if ladder.has_method("get_climb_center_x"):
				global_position.x = float(ladder.call("get_climb_center_x"))
			velocity = Vector2.ZERO


func _leave_ladder(at_bottom: bool = false) -> void:
	on_ladder = false
	_ladder_node = null
	if _ladder_mask_backup >= 0:
		collision_mask = _ladder_mask_backup
		_ladder_mask_backup = -1
	# 兜底：确保仍能踩 Floor/Platform（layer 1）
	if (collision_mask & 1) == 0:
		collision_mask |= 1
	if at_bottom:
		_ladder_reentry_cooldown = 0.35


## 非攀爬时若碰撞掩码丢了地面层，补回（表现为站在台上却跳不起来）
func _repair_ladder_collision_mask() -> void:
	if on_ladder:
		return
	if _ladder_mask_backup >= 0:
		collision_mask = _ladder_mask_backup
		_ladder_mask_backup = -1
	if (collision_mask & 1) == 0:
		collision_mask |= 1


func _find_touching_ladder(prefer_down: bool = false) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	# 几乎不水平外扩：必须站在梯子正上方/柱身内
	var x_pad := 4.0
	var y_above := 18.0 if prefer_down else 10.0
	for n in get_tree().get_nodes_in_group("climb_ladders"):
		if not is_instance_valid(n) or not (n is Area2D):
			continue
		var area := n as Area2D
		var cs := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs == null or cs.disabled or not (cs.shape is RectangleShape2D):
			continue
		var rect := cs.shape as RectangleShape2D
		var half := rect.size * 0.5
		var center: Vector2 = area.global_position + cs.position
		var top := center.y - half.y
		var dx := absf(global_position.x - center.x)
		var dy := global_position.y - top
		# 水平只用碰撞半宽 + 4；不再另加 28/52
		if dx <= half.x + x_pad and dy >= -y_above and dy <= rect.size.y + 20.0:
			if dx < best_d:
				best_d = dx
				best = area
	return best


func _process_ladder_move(delta: float) -> void:
	if _ladder_node == null or not is_instance_valid(_ladder_node):
		_leave_ladder()
		return
	# 仅空格跳离梯子。W/S 专属攀爬；旧跳跃缓冲也不能把人从梯子上弹飞
	if Input.is_physical_key_pressed(KEY_SPACE) and Input.is_action_just_pressed("ui_accept"):
		_leave_ladder()
		_perform_jump(false)
		air_jumps_remaining = max_air_jumps ## 离梯给满空中跳
		return
	jump_buffer_timer = 0.0

	var climb_axis := _read_climb_axis()
	var cx := global_position.x
	if _ladder_node.has_method("get_climb_center_x"):
		cx = float(_ladder_node.call("get_climb_center_x"))
	global_position.x = lerpf(global_position.x, cx, 0.55)

	var top_y := global_position.y - 64.0
	var bot_y := global_position.y + 64.0
	if _ladder_node.has_method("get_climb_top_y"):
		top_y = float(_ladder_node.call("get_climb_top_y"))
	if _ladder_node.has_method("get_climb_bottom_y"):
		bot_y = float(_ladder_node.call("get_climb_bottom_y"))

	velocity = Vector2.ZERO
	if absf(climb_axis) > 0.1:
		var new_y := global_position.y + climb_axis * climb_speed * delta
		if new_y < top_y - 4.0:
			global_position.y = top_y - 10.0
			_leave_ladder()
			velocity = Vector2.ZERO
		elif new_y > bot_y - 8.0:
			global_position.y = bot_y - 12.0
			_leave_ladder(true) ## 梯底离开：冷却后再抓，防按着 S 吸回顶端
		else:
			global_position.y = new_y
			# 刚从台上按 S：若几乎还在顶边，多沉一点确保离开地面
			if climb_axis > 0.1 and global_position.y < top_y + 10.0:
				global_position.y = top_y + 14.0


## 斜向 90° 扇区：
##   W+D / W+A = 上半（右/左）；S+D / S+A = 下半（右/左）
## vertical_sign: -1 上，+1 下
func _is_in_diagonal_sector(world_pos: Vector2, side: float, vertical_sign: float = -1.0) -> bool:
	var to := world_pos - global_position
	if to.length() < 1.0:
		return false
	if vertical_sign < 0.0:
		# 上半：含水平与垂直上边界
		if to.y > 0.05:
			return false
	else:
		# 下半：含水平与垂直下边界
		if to.y < -0.05:
			return false
	if side > 0.0:
		return to.x >= -0.05
	return to.x <= 0.05


func _get_nearest_lantern_fox() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for fox in get_tree().get_nodes_in_group("lantern_fox"):
		if not is_instance_valid(fox):
			continue
		var d := global_position.distance_to(fox.global_position)
		if d < best_d:
			best_d = d
			best = fox
	return best


## 狐妖光球：在其运动直线上，取落在「玩家—狐狸」线段附近的瞄准点
func _aim_point_on_fox_orb_path(orb: Node2D) -> Vector2:
	var orb_pos: Vector2 = orb.global_position
	var move_dir := Vector2.RIGHT
	if "direction" in orb:
		var d: Vector2 = orb.direction
		if d.length() > 0.01:
			move_dir = d.normalized()

	var fox := _get_nearest_lantern_fox()
	var player_pos := global_position
	var fox_pos := fox.global_position if is_instance_valid(fox) else orb_pos

	# 光球运动线（足够长）与「玩家—狐狸」线段的最近点对
	var line_a := orb_pos - move_dir * 2000.0
	var line_b := orb_pos + move_dir * 2000.0
	var pts: PackedVector2Array = Geometry2D.get_closest_points_between_segments(
		line_a, line_b, player_pos, fox_pos
	)
	if pts.size() >= 1:
		return pts[0]
	# 兜底：瞄光球当前位置
	return orb_pos


## 是否为狐妖飞行光球（有运动方向）
func _is_fox_blast_orb(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if not node.is_in_group("magic_orbs"):
		return false
	if "damages_player" in node and bool(node.damages_player):
		return true
	return false


## 扇区内最近目标 + 直线瞄准点（怪物→本体；狐妖光球→轨迹上玩家-狐狸区一点）
## vertical_sign: -1 斜上，+1 斜下
func _resolve_diagonal_aim(side: float, max_range: float = -1.0, vertical_sign: float = -1.0) -> Dictionary:
	if max_range < 0.0:
		max_range = diagonal_auto_aim_range
	if absf(vertical_sign) < 0.1:
		vertical_sign = -1.0

	var best_node: Node2D = null
	var best_dist := max_range
	var best_aim := global_position + Vector2(side, vertical_sign).normalized() * 80.0
	var best_kind := "none"

	# 1) 怪物
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if not _is_in_diagonal_sector(enemy.global_position, side, vertical_sign):
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best_node = enemy
			best_aim = enemy.global_position
			best_kind = "enemy"

	# 2) 狐妖飞行光球（优先参与「最近」比较）
	for orb in get_tree().get_nodes_in_group("magic_orbs"):
		if not _is_fox_blast_orb(orb):
			continue
		if not _is_in_diagonal_sector(orb.global_position, side, vertical_sign):
			continue
		var dist2 := global_position.distance_to(orb.global_position)
		if dist2 < best_dist:
			best_dist = dist2
			best_node = orb
			best_aim = _aim_point_on_fox_orb_path(orb)
			best_kind = "fox_orb"

	# 3) 场景星星光点（静止，直接连线）
	for star in get_tree().get_nodes_in_group("light_orbs"):
		if not is_instance_valid(star):
			continue
		if not _is_in_diagonal_sector(star.global_position, side, vertical_sign):
			continue
		var dist3 := global_position.distance_to(star.global_position)
		if dist3 < best_dist:
			best_dist = dist3
			best_node = star
			best_aim = star.global_position
			best_kind = "star"

	return {
		"node": best_node,
		"aim": best_aim,
		"kind": best_kind,
		"found": best_node != null
	}


func _combo_side_facing() -> float:
	if (_combo_clock - _stamp_d) <= diagonal_combo_window and _stamp_d >= _stamp_a:
		return 1.0
	if (_combo_clock - _stamp_a) <= diagonal_combo_window:
		return -1.0
	return facing


## 发射方向
func _get_shoot_aim_vector() -> Vector2:
	var v := _read_move_aim_axes()

	if _is_diagonal_combo_buffered():
		var side := _combo_side_facing()
		var vsign := _diagonal_vertical_sign()
		facing = side
		var resolved := _resolve_diagonal_aim(side, -1.0, vsign)
		if resolved["found"]:
			var to_aim: Vector2 = resolved["aim"] - global_position
			if to_aim.length() > 1.0:
				if absf(to_aim.x) > 0.05:
					facing = signf(to_aim.x)
				return to_aim.normalized()
		return Vector2(side, vsign).normalized()

	# 普通：原逻辑
	if absf(v.x) < 0.5 and absf(v.y) < 0.5:
		return Vector2(facing, 0.0)
	if absf(v.x) < 0.5:
		return Vector2(0.0, signf(v.y))
	facing = signf(v.x)
	if absf(v.y) < 0.5:
		return Vector2(facing, 0.0)
	return v.normalized()


## 发射：W+A/D+L 斜上 / S+A/D+L 斜下 → 扇区内直线连线瞄准（不追踪）
func _try_shoot_magic_orb() -> void:
	var mp_cost := get_magic_orb_mp_cost()
	if current_mp < mp_cost:
		print("💧 蓝量不足！需要 ", mp_cost, "，当前只有 ", current_mp)
		return

	var diagonal := _is_diagonal_combo_buffered()
	var shoot_dir := _get_shoot_aim_vector()
	var spawn_pos := global_position + shoot_dir * orb_spawn_offset + Vector2(0, -4)
	var point_blank_target := _get_nearest_enemy_in_range(point_blank_range)

	if diagonal:
		jump_buffer_timer = 0.0
		_diagonal_lock_timer = diagonal_combo_window
		if velocity.y < 0.0:
			velocity.y = 0.0
		var side := _combo_side_facing()
		var vsign := _diagonal_vertical_sign()
		facing = side
		var resolved := _resolve_diagonal_aim(side, -1.0, vsign)
		if resolved["found"]:
			var to_aim: Vector2 = resolved["aim"] - global_position
			if to_aim.length() > 1.0:
				shoot_dir = to_aim.normalized()
				if absf(shoot_dir.x) > 0.05:
					facing = signf(shoot_dir.x)
			spawn_pos = global_position + shoot_dir * orb_spawn_offset
			var tip := "斜上" if vsign < 0.0 else "斜下"
			print("🎯 ", tip, "直线连线 [", resolved["kind"], "] → ", resolved["aim"])
		else:
			shoot_dir = Vector2(side, vsign).normalized()
			spawn_pos = global_position + shoot_dir * orb_spawn_offset
			if vsign < 0.0:
				print("↗️ 扇区内无目标，默认斜上")
			else:
				print("↘️ 扇区内无目标，默认斜下")
		_sprite_tilt_target = 0.0
		_sprite_tilt_hold = 0.0
	elif point_blank_target and absf(shoot_dir.y) < 0.2:
		var to_enemy: Vector2 = point_blank_target.global_position - global_position
		if to_enemy.length() > 1.0:
			shoot_dir = to_enemy.normalized()
			if absf(shoot_dir.x) > 0.05:
				facing = signf(shoot_dir.x)
		spawn_pos = point_blank_target.global_position - shoot_dir * 4.0
		print("🎯 贴脸锁定敌人")
		_apply_shoot_aim_tilt(shoot_dir)
	else:
		_apply_shoot_aim_tilt(shoot_dir)

	current_mp -= mp_cost
	var orb = magic_orb_scene.instantiate()
	# 斜向改为直线飞行，不再开启追踪
	get_parent().add_child(orb)
	if orb.has_method("begin_flight"):
		orb.begin_flight(spawn_pos, shoot_dir)
	else:
		orb.global_position = spawn_pos
		orb.direction = shoot_dir
	if (not diagonal) and point_blank_target and absf(shoot_dir.y) < 0.2 and orb.has_method("arm_point_blank"):
		orb.arm_point_blank(point_blank_target)

	_update_hud()
	print("🔥 魔法球发射 dir=", shoot_dir, " 耗蓝：", mp_cost)


# ==================== 被怪物咬到：扣血条 ====================
func take_player_damage(amount: int = -1) -> void:
	if amount < 0:
		amount = contact_damage

	# 回溯中 / 已在无敌 / 已死：不重复扣血
	if is_rewinding or hurt_invincible or current_hp <= 0:
		return

	current_hp -= amount
	if current_hp < 0:
		current_hp = 0

	hurt_invincible = true
	_change_state(State.HURT)
	_pulse_hurt_squash()
	_update_hud() # 刷新屏幕左上角血条
	print("💔 被咬！剩余血量：", current_hp, "/", max_hp)

	if current_hp > 0:
		_play_sfx("hurt")

	# 打击感：由 GameManager 统一顿帧+震动（重击）
	if GameManager:
		GameManager.trigger_heavy_impact()

	if current_hp <= 0:
		GameManager.game_over("hp_zero")
		return

	# 无敌结束，退出受击状态（真实时间，不受顿帧 time_scale 拖长）
	await get_tree().create_timer(hurt_invincible_duration, true, false, true).timeout
	hurt_invincible = false
	if current_state == State.HURT:
		if is_on_floor():
			_change_state(State.IDLE)
		else:
			_change_state(State.FALL)


## 坠入深渊：血条清零，走与扣完血相同的死亡界面
func kill_by_abyss() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm and int(gm.get("current_state")) == 3: ## GameState.DEAD
		return
	current_hp = 0
	hurt_invincible = true
	set_input_locked(true)
	_update_hud()
	if gm and gm.has_method("game_over"):
		gm.game_over("abyss")


# ==================== 魅惑状态（叠加，不替换 State 枚举）====================
func apply_charm(duration: float = -1.0) -> void:
	if is_rewinding:
		return
	if duration < 0.0:
		duration = charm_duration_default
	is_charmed = true
	charm_timer = duration
	charm_leap_available = true
	if glow_sprite:
		glow_sprite.modulate = Color(0.55, 0.75, 1.0, 1.0)
	print("💫 魅惑！左右反转 ", duration, " 秒；跳跃可触发跃升")


func _clear_charm() -> void:
	is_charmed = false
	charm_timer = 0.0
	charm_leap_available = false
	if glow_sprite and current_state != State.ATTACK:
		glow_sprite.modulate = Color(1.0, 0.92, 0.55, 1.0)


func is_player_charmed() -> bool:
	return is_charmed


# ==================== 【Day 8 核心机制】吃光点反馈 ====================
func collect_light_orb() -> void:
	# 1. 每次吃光点：回蓝速度 +0.05 倍（可一直叠加）
	orb_bonus_regen += 0.05
	print("⚡ 回蓝加速！当前速度倍率：", 1.0 + orb_bonus_regen)

	# 2. 发射扣蓝更少（最多叠 3 层）
	if orb_bonus_count < max_orb_bonus:
		orb_bonus_count += 1
		print("✨ 法力强化！发射耗蓝降至 ", get_magic_orb_mp_cost(), "（", orb_bonus_count, "/", max_orb_bonus, "）")

	# 3. 蓝量直接补满
	current_mp = max_mp

	# 4. 残血救命：如果当前血量 < 最大血量，回复一半血量
	if current_hp < max_hp:
		var heal_amount = int(float(max_hp) / 2.0)
		current_hp += heal_amount

		if current_hp > max_hp:
			current_hp = max_hp

		print("🩸 仙丹救命！恢复了 ", heal_amount, " 点生命值！")

	_update_hud() # 刷新屏幕左上角 UI

# ==================== 状态机逻辑 ====================
func _update_state() -> void:
	if current_state == State.ATTACK or current_state == State.HURT:
		return

	if is_on_floor():
		if abs(velocity.x) > 10.0:
			_change_state(State.RUN)
		else:
			_change_state(State.IDLE)
	else:
		if velocity.y < 0:
			_change_state(State.JUMP)
		else:
			_change_state(State.FALL)


func _change_state(new_state: State) -> void:
	if current_state == new_state:
		return
	_on_state_exit(current_state)
	current_state = new_state
	_on_state_enter(new_state)


func _on_state_enter(state: State) -> void:
	match state:
		State.IDLE:
			pass
		State.RUN:
			pass
		State.JUMP:
			pass
		State.FALL:
			pass
		State.ATTACK:
			pass
		State.HURT:
			pass
		State.REWIND:
			pass


func _on_state_exit(state: State) -> void:
	match state:
		State.ATTACK:
			pass
		State.HURT:
			pass


func _play_sfx(kind: String) -> void:
	var sfx := get_node_or_null("/root/SfxManager")
	if sfx and sfx.has_method("play"):
		sfx.play(kind)
