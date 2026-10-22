extends Area2D
## ==================== 实体诱饵影子（Shadow）====================
## 根节点 Area2D：可被 enemy_base.resolve_aggro_target / try_melee_on_aggro 识别。
## 不改怪物仇恨算法——只提供 Group + is_shadow_alive + destroy_by_hit。

const ParticleFXUtil = preload("res://particle_fx.gd")

## 生命周期：超时自动消散，防止场景里影子无限堆积（内存安全）
@export var lifespan: float = 10.0
## 碰撞半径：与主角默认 CircleShape（约 10）同量级，方便近战贴脸判定
@export var hit_radius: float = 10.0

var facing: float = 1.0
var _alive: bool = true


func _ready() -> void:
	# active_shadows：供 resolve_aggro_target 扫描（绝不改 enemy_base 算法本身）
	add_to_group("active_shadows")
	# shadows：兼容光门等旧逻辑
	add_to_group("shadows")

	monitoring = false
	monitorable = true
	collision_layer = 1
	collision_mask = 0
	z_as_relative = false

	_apply_hit_radius(hit_radius)

	# 寿命到点自动销毁；用场景树 Timer，与主角状态机无关
	var life_timer := get_tree().create_timer(lifespan)
	life_timer.timeout.connect(_on_lifespan_end)


## 由 player 在生成时调用：位置 / 朝向 / 水墨贴图
func setup(pos: Vector2, face_dir: float, tex: Texture2D = null, light_tex: Texture2D = null, radius: float = -1.0) -> void:
	global_position = pos
	facing = face_dir
	if radius > 0.0:
		hit_radius = radius
		_apply_hit_radius(hit_radius)

	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		if tex:
			sprite.texture = tex
		sprite.centered = true
		# 略小于主角，半透明 = 水墨残影感
		sprite.scale = Vector2(0.06, 0.06)
		sprite.modulate = Color(0.75, 0.82, 0.95, 0.38)
		sprite.flip_h = face_dir < 0.0

	var light := get_node_or_null("PointLight2D") as PointLight2D
	if light and light_tex:
		light.texture = light_tex
		light.energy = 0.18
		light.texture_scale = 2.0
		light.color = Color(0.7, 0.85, 1.0, 1.0)


func _apply_hit_radius(r: float) -> void:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null:
		return
	var circle := cs.shape as CircleShape2D
	if circle == null:
		return
	# 复制 shape，避免改到 tscn 共享资源
	circle = circle.duplicate() as CircleShape2D
	circle.radius = r
	cs.shape = circle


func _on_lifespan_end() -> void:
	dissolve()


## enemy_base.try_melee_on_aggro 在 aggro_is_shadow 时会调这里
func destroy_by_hit() -> void:
	if not _alive:
		return
	_alive = false
	# 先退出组，避免同一帧仇恨还扫到已死影子
	if is_in_group("active_shadows"):
		remove_from_group("active_shadows")
	var parent := get_parent()
	if parent:
		ParticleFXUtil.ink_dissolve(parent, global_position)
	queue_free()


## 超时或被主角超量挤掉时的安静消散（无击碎特效）
func dissolve() -> void:
	if not _alive:
		return
	_alive = false
	if is_in_group("active_shadows"):
		remove_from_group("active_shadows")
	queue_free()


## resolve_aggro_target 用来过滤无效节点
func is_shadow_alive() -> bool:
	return _alive and is_inside_tree()
