extends ParallaxBackground
## 花瓣：最上层（layer=100），不挂进背景树。
## 运动与上上一步相同：ParallaxLayer + 中远景滚动率，不跟屏幕 Canvas 钉死。
## mirroring 保证镜头左右移时整屏仍有花瓣。
## 贴图：res://assets/tiles/background/petals/

const PETALS_DIR := "res://assets/tiles/background/petals/"
const FLOOR_TOP_Y := 256.0
const TARGET_AMOUNT := 36
const LIFETIME := 7.5
const BASE_SCALE := 0.055
const FADE_BAND_PX := 80.0
const MOTION_SCALE_X := 0.4 ## 与中远景同系
const MIRROR_W := 1920.0 ## 范围 ×2

const FADE_SHADER := preload("res://levels/petals_fade.gdshader")

@export var petals_enabled: bool = true


func _ready() -> void:
	layer = 100
	name = "PetalsAtmosphere"
	if not petals_enabled:
		return
	_build()


func _build() -> void:
	var paths := _collect_petal_paths()
	if paths.is_empty():
		push_warning("PetalsAtmosphere: 未找到花瓣贴图于 ", PETALS_DIR)
		return

	var pl := ParallaxLayer.new()
	pl.name = "Petals"
	pl.motion_scale = Vector2(MOTION_SCALE_X, 1.0)
	pl.motion_mirroring = Vector2(MIRROR_W, 0.0)
	add_child(pl)

	var n := paths.size()
	var per := maxi(int(floor(float(TARGET_AMOUNT) / float(n))), 1)
	var remain := TARGET_AMOUNT
	for i in range(n):
		var amt := per if i < n - 1 else maxi(remain, 1)
		remain -= amt
		if amt <= 0:
			break
		var tex := load(paths[i]) as Texture2D
		if tex == null:
			continue
		pl.add_child(_make_emitter("PetalsEmitter_%d" % i, tex, amt))


func _collect_petal_paths() -> Array[String]:
	var out: Array[String] = []
	var prefer: Array[String] = [
		"petal_flower_01.png", "petal_flower_02.png", "petal_flower_03.png", "petal_flower_05.png",
		"petal_leaf_01.png", "petal_leaf_03.png", "petal_leaf_05.png",
		"petal_spore_01.png", "petal_spore_03.png",
	]
	for name_s in prefer:
		var p := PETALS_DIR + name_s
		if ResourceLoader.exists(p):
			out.append(p)
	if not out.is_empty():
		return out
	var dir := DirAccess.open(PETALS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".png"):
			out.append(PETALS_DIR + fn)
		fn = dir.get_next()
	dir.list_dir_end()
	return out


func _make_emitter(node_name: String, tex: Texture2D, amount: int) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = LIFETIME
	p.preprocess = 3.5
	p.explosiveness = 0.0
	p.randomness = 0.45
	p.texture = tex
	p.emitting = true
	p.local_coords = true
	# 与上上一步相同的世界位置；mirroring 负责铺满左右视野
	p.position = Vector2(480.0, FLOOR_TOP_Y - 400.0)
	p.visibility_rect = Rect2(-2000, -800, 4400, 2400)

	var sh := ShaderMaterial.new()
	sh.shader = FADE_SHADER
	sh.set_shader_parameter("floor_y", FLOOR_TOP_Y)
	sh.set_shader_parameter("fade_band", FADE_BAND_PX)
	p.material = sh

	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(1040.0, 32.0, 0.0)
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 28.0
	mat.gravity = Vector3(18.0, 22.0, 0.0)
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 20.0
	mat.angular_velocity_min = -90.0
	mat.angular_velocity_max = 90.0
	mat.damping_min = 1.5
	mat.damping_max = 4.0
	mat.linear_accel_min = -6.0
	mat.linear_accel_max = 6.0
	mat.tangential_accel_min = -8.0
	mat.tangential_accel_max = 8.0
	mat.scale_min = BASE_SCALE * 0.5
	mat.scale_max = BASE_SCALE * 1.5
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.08, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.92, 0.95, 0.0),
		Color(1.0, 0.88, 0.92, 0.9),
		Color(1.0, 0.85, 0.9, 0.85),
		Color(1.0, 0.9, 0.95, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	mat.hue_variation_min = -0.04
	mat.hue_variation_max = 0.06
	p.process_material = mat
	return p
