extends Area2D

var _glow: Sprite2D
var _point_light: PointLight2D
var _base_glow_scale: Vector2 = Vector2(34, 34)
var _is_shatter_drop: bool = false

## 拾取判定半径（世界像素，不受节点 scale 缩小影响）
@export var pickup_radius_world: float = 42.0


func mark_as_shatter_drop() -> void:
	_is_shatter_drop = true
	# 高纯度冰蓝观感（收集逻辑仍走 collect_light_orb）
	if _glow:
		_glow.modulate = Color(0.75, 0.95, 1.0, 1.0)
	if _point_light:
		_point_light.color = Color(0.65, 0.9, 1.0, 1.0)
		_point_light.energy = 0.95
	call_deferred("_apply_pickup_radius")


## 把碰撞半径换算成固定世界尺寸，避免 scale=0.03 时判定几乎为 0
func _apply_pickup_radius() -> void:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null:
		return
	var circle := cs.shape as CircleShape2D
	if circle == null:
		return
	circle = circle.duplicate() as CircleShape2D
	var s := maxf(absf(global_scale.x), 0.001)
	circle.radius = pickup_radius_world / s
	cs.shape = circle


func _ready() -> void:
	add_to_group("light_orbs")
	body_entered.connect(_on_body_entered)
	# 等实例 scale 设完再算半径（Main / 碎光掉落都会改 scale）
	call_deferred("_apply_pickup_radius")

	_glow = $starlight
	if _glow == null:
		push_error("找不到 starlight 节点")
		return

	# 暖黄绿光晕：峰值要够亮，呼吸时才有「明显 ↔ 几乎没有」
	var glow_size := 64
	var glow_img := Image.create(glow_size, glow_size, false, Image.FORMAT_RGBA8)
	var glow_center := Vector2(glow_size / 2.0, glow_size / 2.0)
	var max_dist := glow_size / 2.0

	for x in range(glow_size):
		for y in range(glow_size):
			var dist := Vector2(float(x), float(y)).distance_to(glow_center)
			var t := clampf(1.0 - dist / max_dist, 0.0, 1.0)
			var alpha := pow(t, 1.15) * 1.0
			glow_img.set_pixel(x, y, Color(0.85, 1.0, 0.38, alpha))

	_glow.texture = ImageTexture.create_from_image(glow_img)
	_glow.z_index = -1
	_glow.scale = _base_glow_scale
	_glow.modulate = Color(1.15, 1.25, 0.65, 1.0)
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	_point_light = PointLight2D.new()
	var light_tex := GradientTexture2D.new()
	light_tex.width = 128
	light_tex.height = 128
	light_tex.fill = GradientTexture2D.FILL_RADIAL
	light_tex.fill_from = Vector2(0.5, 0.5)
	light_tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 0.45, 1.0))
	g.set_color(1, Color(0.5, 0.75, 0.2, 0.0))
	light_tex.gradient = g
	_point_light.texture = light_tex
	_point_light.color = Color(0.95, 1.0, 0.45, 1.0)
	_point_light.energy = 1.6
	_point_light.texture_scale = 1.45
	_point_light.z_index = -2
	add_child(_point_light)

	_start_breathing()
	if _is_shatter_drop:
		mark_as_shatter_drop()


## 呼吸：明显光晕 ↔ 几乎看不见（尺寸不变）
func _start_breathing() -> void:
	if _glow == null:
		return

	var lit_mod := Color(1.2, 1.35, 0.7, 1.0)
	var dim_mod := Color(0.35, 0.4, 0.2, 0.04) ## 几乎看不见
	var lit_energy := 2.4
	var dim_energy := 0.02
	var half_beat := 0.85

	_glow.scale = _base_glow_scale
	_glow.modulate = lit_mod
	if _point_light:
		_point_light.energy = lit_energy

	var tween := create_tween().set_loops()
	tween.set_parallel(true)

	# 暗相：光晕退到几乎没有
	tween.tween_property(_glow, "modulate", dim_mod, half_beat).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _point_light:
		tween.tween_property(_point_light, "energy", dim_energy, half_beat).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.chain().set_parallel(true)
	# 亮相：光晕清楚鼓起来
	tween.tween_property(_glow, "modulate", lit_mod, half_beat).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _point_light:
		tween.tween_property(_point_light, "energy", lit_energy, half_beat).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		# 光晕成长 + 满蓝 + orb_bonus_count / orb_bonus_regen（现有蓝条系统）
		if body.has_method("grow_glow"):
			body.grow_glow()
		if body.has_method("collect_light_orb"):
			body.collect_light_orb()
		queue_free()
