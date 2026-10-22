extends RefCounted
class_name ParticleFX
## Day 8：统一粒子特效工厂（魔法球爆炸 / 怪物死亡 / 回溯）

static var _dot_tex: Texture2D


static func _get_dot_texture() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size / 2.0
	for x in range(size):
		for y in range(size):
			var d := Vector2(x, y).distance_to(center)
			var a := clampf(1.0 - d / radius, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


## 在父节点下生成一次性爆发粒子，播完自动销毁
static func spawn_burst(
	parent: Node,
	global_pos: Vector2,
	color: Color,
	amount: int = 16,
	lifetime: float = 0.45,
	speed_min: float = 40.0,
	speed_max: float = 120.0,
	scale_min: float = 0.3,
	scale_max: float = 0.8,
	gravity_y: float = 0.0
) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	var particles := GPUParticles2D.new()
	particles.z_index = 20
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = true
	particles.texture = _get_dot_texture()

	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = speed_min
	mat.initial_velocity_max = speed_max
	mat.gravity = Vector3(0, gravity_y, 0)
	mat.scale_min = scale_min
	mat.scale_max = scale_max
	mat.color = color

	# 颜色渐隐
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 1.0),
		Color(color.r, color.g, color.b, 0.0)
	])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex

	particles.process_material = mat
	parent.add_child(particles)
	particles.global_position = global_pos

	# 播完清理（挂在场景树里，不依赖调用者是否还活着）
	var tree := parent.get_tree()
	if tree:
		tree.create_timer(lifetime + 0.15).timeout.connect(
			func():
				if is_instance_valid(particles):
					particles.queue_free()
		)


## 魔法球命中/撞墙爆炸：暖白金光
static func magic_orb_explode(parent: Node, global_pos: Vector2) -> void:
	spawn_burst(parent, global_pos, Color(1.0, 0.95, 0.55, 1.0), 18, 0.35, 60.0, 160.0, 0.25, 0.7, 80.0)
	# 第二层更亮的内核
	spawn_burst(parent, global_pos, Color(1.0, 1.0, 1.0, 1.0), 8, 0.2, 20.0, 70.0, 0.4, 0.9, 0.0)


## 怪物死亡自爆：暗紫 + 粉边
static func enemy_death(parent: Node, global_pos: Vector2) -> void:
	spawn_burst(parent, global_pos, Color(0.65, 0.2, 0.9, 1.0), 22, 0.55, 50.0, 140.0, 0.35, 1.0, 40.0)
	spawn_burst(parent, global_pos, Color(1.0, 0.5, 0.95, 1.0), 10, 0.35, 30.0, 90.0, 0.2, 0.55, 0.0)


## 回溯离开点：金色残影散开
static func rewind_depart(parent: Node, global_pos: Vector2) -> void:
	spawn_burst(parent, global_pos, Color(1.0, 0.85, 0.35, 1.0), 16, 0.4, 30.0, 100.0, 0.25, 0.75, -20.0)


## 回溯到达点：青白光聚散
static func rewind_arrive(parent: Node, global_pos: Vector2) -> void:
	spawn_burst(parent, global_pos, Color(0.75, 1.0, 0.9, 1.0), 14, 0.35, 20.0, 80.0, 0.3, 0.8, 0.0)


## 提灯碎裂：冰蓝玻璃碎片
static func glass_shatter(parent: Node, global_pos: Vector2) -> void:
	spawn_burst(parent, global_pos, Color(0.55, 0.85, 1.0, 1.0), 28, 0.55, 80.0, 220.0, 0.2, 0.65, 120.0)
	spawn_burst(parent, global_pos, Color(0.9, 0.98, 1.0, 1.0), 14, 0.35, 40.0, 140.0, 0.15, 0.45, 60.0)
	spawn_burst(parent, global_pos, Color(0.4, 0.6, 1.0, 1.0), 10, 0.45, 30.0, 100.0, 0.25, 0.7, 180.0)


## 影子被近战击碎：水墨青灰消散（诱饵被识破）
static func ink_dissolve(parent: Node, global_pos: Vector2) -> void:
	spawn_burst(parent, global_pos, Color(0.55, 0.65, 0.85, 1.0), 18, 0.45, 25.0, 95.0, 0.2, 0.65, -15.0)
	spawn_burst(parent, global_pos, Color(0.9, 0.95, 1.0, 1.0), 8, 0.3, 15.0, 55.0, 0.35, 0.8, 0.0)
