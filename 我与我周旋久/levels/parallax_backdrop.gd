extends Node2D
## 视差对齐规则：
## - 远景：far 水平无缝头碰头；亮线地平线锁 floor 顶
## - 中远景：全程无缝头碰头；遮挡远景，被中景/前景遮挡（z: Far0 < MidFar1 < Mid10 < Fg20；条带从 x=0 mirroring）
## - 中景：疏布整图（中心在 Floor 上才放）；禁止切图
## - 前景：水平全程无缝头碰头铺满（含深渊上方）
## 滚动仍全部交给 ParallaxBackground / ParallaxLayer。

@export var auto_build_on_ready: bool = true
@export var enable_far: bool = true
@export var enable_mid_far: bool = true
@export var enable_mid: bool = true
@export var enable_foreground: bool = true
@export var enable_fog: bool = false
@export var enable_petals: bool = false ## 花瓣由顶层 PetalsAtmosphere（独立 ParallaxBackground layer=100）负责

## 世界地平线 Y（应等于玩法地面顶边；可由关卡写入）
@export var horizon_y: float = 256.0
## 远景图内：从上到下的地平线比例（备用）
@export var far_horizon_ratio: float = 5.0 / 6.0
## 中远景图里“废墟脚底”约在图高的比例（自动识别失败时的兜底）
@export var mid_far_foot_ratio: float = 0.78
## 中景每关出现个数（0=按整段 floor / 间距自动铺满）
@export var mid_count_min: int = 0
@export var mid_count_max: int = 0
## 中景沿关卡水平散布的总跨度（世界像素；关卡会写成整段 floor 宽）
@export var mid_span: float = 1600.0
## 中景散布起点 X（地板左端，含出生点左侧）
@export var mid_origin_x: float = 0.0
## 中景之间最小间距（世界像素；实际还会按视野抬高，保证同屏最多约 2 张）
@export var mid_min_gap: float = 320.0
## 同屏最多中景张数（用视野宽推算最小间距）
@export var mid_max_visible: int = 2
## 可变间距上限相对最小间距的倍率（有远有近）
@export var mid_gap_max_mult: float = 2.2
## 中景统一内容高度（相对视野；保持现大小）
@export var mid_height_ratio: float = 0.21
## 中景水平视差（Y=1 底端锁 floor）
@export var mid_motion_scale_x: float = 0.75
## 中景相对 floor 微调（正值向下）
@export var mid_y_offset: float = 0.0
## 远景至少比视野大多少倍（保证视线范围 < 远景）
@export var far_viewport_cover: float = 1.35
## 远景相对 floor 的额外偏移（对齐地平线时保持 0；正值向下）
@export var far_y_offset: float = 0.0
## 远景相对基准尺寸的倍率
@export var far_scale_mult: float = 3.75 ## 相对原基准再 ×1.5（2.5→3.75），地平线仍锁 floor 顶
## 三张远景间距（世界像素）：按「非黑内容」宽度头碰头；略负叠缝消黑线
@export var far_seam_gap: float = -12.0
## 把各图「可见条带」拉到同一目标高度（世界像素，0=按最宽内容自动）
@export var far_content_target_h: float = 0.0
## 远景水平视差（Y 固定为 1，与 floor 同坐标系，地平线才锁得住）
@export var far_motion_scale_x: float = 0.15
## 中远景相对满高基准的倍率（可挡远景，但仍小于中景视觉权重）
@export var mid_far_scale_mult: float = 0.72
## 中远景紧拼重叠（消缝；按内容宽拼接后再叠）
@export var mid_far_seam_gap: float = -10.0
## 中远景内容目标高度（0=按视野×倍率自动；单位世界像素）
@export var mid_far_content_target_h: float = 0.0
## 中远景素材组重复次数（无缝横拼后再 mirroring）
@export var mid_far_repeat_sets: int = 4
## 中远景水平视差（Y=1，底端锁 floor/远景地平线）
@export var mid_far_motion_scale_x: float = 0.4
## 中远景相对地平线的微调（正值向下）
@export var mid_far_y_offset: float = 0.0
## 背景贴图亮度压暗倍数（直接压 Sprite 宿主 modulate，不是关卡 tint）
## Far ÷far_image_darken；Mid/Fg ÷bg_image_darken；中远景较弱 ÷mid_far_image_darken
@export var far_image_darken: float = 1.5 ## 相对 Mid/Fg 的 ÷3，远景再调亮一倍（÷1.5）
@export var bg_image_darken: float = 3.0
@export var mid_far_image_darken: float = 2.0
## 中远景层基础色偏置（再乘贴图压暗）
@export var mid_far_base_modulate: Color = Color(1.0, 1.0, 1.0, 1.0)
## 前景相对满高基准的倍率（约为原先的 2/3）
@export var fg_scale_mult: float = 0.367
## 前景紧拼重叠（消缝）
@export var fg_seam_gap: float = -3.0
## 前景内容目标高度（0=按视野×倍率自动）
@export var fg_content_target_h: float = 0.0
## 前景素材组重复次数（无缝横拼后再 mirroring）
@export var fg_repeat_sets: int = 3
## 前景水平视差（Y=1，底端锁 floor/远景地平线）
@export var fg_motion_scale_x: float = 1.1
## 前景相对地平线微调（正值向下）
@export var fg_y_offset: float = 7.0


var _parallax: ParallaxBackground
var _brightness_tween: Tween
## 远景一条带的世界宽度（铺 floor / 中景跨度用）
var _far_strip_width: float = 0.0


func get_far_strip_width() -> float:
	return _far_strip_width


## 有 floor 贴图的世界 X 区间 [x0,x1]；仅裁中景/前景。远景与中远景始终无缝全铺。
var _floor_cover: Array[Vector2] = []


func _ready() -> void:
	z_index = -20
	if auto_build_on_ready:
		rebuild()
	call_deferred("_apply_initial_brightness")


## 关卡铺好地面后调用：把地平线锁到地面顶边
func set_horizon_from_ground_top(ground_top_y: float) -> void:
	horizon_y = ground_top_y
	rebuild()


## 只裁中景/前景：无 floor 碰撞/贴图处不铺；可从贴图中间切开，贴齐缺口边缘（不突兀）
## 远景 / 中远景不受影响，保持无缝头碰头
func set_floor_coverage_segments(segments: Array) -> void:
	_floor_cover.clear()
	for s in segments:
		if s is Vector2:
			var v: Vector2 = s
			if v.y - v.x >= 8.0:
				_floor_cover.append(v)
		elif typeof(s) == TYPE_DICTIONARY:
			var d: Dictionary = s
			_floor_cover.append(Vector2(float(d.get("x", 0)), float(d.get("y", 0))))
	print("🌿 中景/前景 floor 蒙版 ×", _floor_cover.size(), " ", _floor_cover)
	_rebuild_mid_and_foreground_only()


## 只重建中远景（无缝）+ 中景 + 前景（按 floor 切开）；不动远景
func _rebuild_mid_and_foreground_only() -> void:
	if _parallax == null:
		rebuild()
		return
	for child in _parallax.get_children():
		var n := String(child.name)
		if n == "Layer2_MidFar" or n == "Layer3_Mid" or n == "Layer4_Foreground":
			child.queue_free()
	call_deferred("_build_mid_fg_deferred")


func _build_mid_fg_deferred() -> void:
	if _parallax == null:
		return
	for child in _parallax.get_children():
		var n := String(child.name)
		if n == "Layer2_MidFar" or n == "Layer3_Mid" or n == "Layer4_Foreground":
			child.free()
	# 中远景：始终无缝全铺（此时 mid_origin / mid_span 已由关卡写入）
	if enable_mid_far:
		_build_mid_far_layer()
	if enable_mid:
		_build_mid_props()
	if enable_foreground:
		_build_foreground_layer()
	_finalize_parallax_draw_order()
	_verify_parallax_layers()
	_reapply_brightness_after_rebuild()


func rebuild() -> void:
	for c in get_children():
		c.queue_free()

	_far_strip_width = 0.0
	_parallax = ParallaxBackground.new()
	_parallax.name = "ParallaxBackground"
	_parallax.add_to_group("level_parallax_bg")
	add_child(_parallax)
	add_to_group("parallax_backdrop")

	if enable_far:
		_build_far_layer()
	if enable_mid_far:
		_build_mid_far_layer()
	if enable_fog:
		_add_fog_layer()
	if enable_mid:
		_build_mid_props()
	if enable_foreground:
		_build_foreground_layer()
	if enable_petals:
		_add_petal_layer()

	print("🌌 视差对齐：horizon_y=", horizon_y, " far=", enable_far,
		" far_w=", snappedf(_far_strip_width, 0.1),
		" floor_mask×", _floor_cover.size())
	_finalize_parallax_draw_order()
	_verify_parallax_layers()


## 强制树序 + z：Far < MidFar < Mid < Fg（重建后 MidFar 常被 add 到末尾，会盖住中/前景）
func _finalize_parallax_draw_order() -> void:
	if _parallax == null:
		return
	var order: Array[String] = [
		"Layer1_Far", "Layer2_MidFar", "FogBreath",
		"Petals", "Layer3_Mid", "Layer4_Foreground",
	]
	var z_of := {
		"Layer1_Far": 0,
		"Layer2_MidFar": 1,
		"FogBreath": 2,
		"Petals": 5, ## 与背景同系，在 Mid/Fg 之下
		"Layer3_Mid": 10,
		"Layer4_Foreground": 20,
	}
	var idx := 0
	for name_s in order:
		var layer := _parallax.get_node_or_null(name_s)
		if layer == null:
			continue
		if layer is CanvasItem:
			var ci := layer as CanvasItem
			ci.z_as_relative = false
			ci.z_index = int(z_of.get(name_s, idx))
		_parallax.move_child(layer, idx)
		idx += 1


func _reapply_brightness_after_rebuild() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("apply_level_brightness"):
		return
	var lm := get_node_or_null("/root/LevelManager")
	var id := 1
	if lm:
		id = int(lm.get("current_level_id"))
	gm.apply_level_brightness(id, 0.01)


## 每次重建后自检：中远景绝不能消失；层级 Far<MidFar<Mid<Fg
func _verify_parallax_layers() -> void:
	if _parallax == null:
		return
	var far_n := 0
	var mf_n := 0
	var mid_n := 0
	var fg_n := 0
	var mf_z := -999
	var mid_z := -999
	var fg_z := -999
	var names_in_order: PackedStringArray = PackedStringArray()
	for layer in _parallax.get_children():
		var name_s := String(layer.name)
		names_in_order.append(name_s)
		var spr_count := _count_sprites(layer)
		var zi := int(layer.get("z_index")) if layer is CanvasItem else 0
		match name_s:
			"Layer1_Far":
				far_n = spr_count
			"Layer2_MidFar":
				mf_n = spr_count
				mf_z = zi
			"Layer3_Mid":
				mid_n = spr_count
				mid_z = zi
			"Layer4_Foreground":
				fg_n = spr_count
				fg_z = zi
	print("✅ 视差自检 Far×", far_n, " MidFar×", mf_n, " Mid×", mid_n, " Fg×", fg_n,
		" z=", mf_z, "/", mid_z, "/", fg_z, " order=", ", ".join(names_in_order))
	if enable_far and far_n <= 0:
		push_error("❌ 远景无 Sprite")
	if enable_mid_far and mf_n <= 0:
		push_error("❌ 中远景无 Sprite（反复消失回归）——请检查 tint/加载/内容裁切")
	if enable_mid_far and enable_mid and mid_z >= 0 and mf_z >= mid_z:
		push_error("❌ 中远景 z≥中景，会遮挡中景（违反 scenery 规则）")
	if enable_mid_far and enable_foreground and fg_z >= 0 and mf_z >= fg_z:
		push_error("❌ 中远景 z≥前景，会遮挡前景（违反 scenery 规则）")


func _count_sprites(node: Node) -> int:
	var n := 0
	if node is Sprite2D:
		n += 1
	for c in node.get_children():
		n += _count_sprites(c)
	return n


# -------------------- 远景：按非黑内容区头碰头；亮线锁 floor --------------------
func _build_far_layer() -> void:
	var textures := _load_folder_textures("res://assets/tiles/background/far")
	if textures.is_empty():
		print("⚠️ 无远景图")
		return

	var pl := ParallaxLayer.new()
	pl.name = "Layer1_Far"
	pl.motion_scale = Vector2(far_motion_scale_x, 1.0)

	var host := Node2D.new()
	host.name = "Tiles"
	host.modulate = _bg_image_modulate(far_image_darken, Color(0.95, 0.97, 1.0, 1.0))
	pl.add_child(host)

	var vp_h := _estimate_viewport_h()
	var vp_w := _estimate_viewport_w()
	var world_horizon := horizon_y + far_y_offset

	var infos: Array[Dictionary] = []
	var max_content_h := 1.0
	for tex in textures:
		var info := _analyze_far_texture(tex)
		info["tex"] = tex
		infos.append(info)
		max_content_h = maxf(max_content_h, float(info["content_h"]))
		print("  • 远景内容 ", tex.resource_path.get_file(),
			" x=", info["x0"], "-", info["x1"],
			" y=", info["y0"], "-", info["y1"],
			" 亮线=", int(info["horizon_px"]))

	var base_s := (vp_h * far_viewport_cover) / 512.0
	base_s = maxf(base_s, (vp_w * 0.55) / 512.0) * far_scale_mult
	var target_h := far_content_target_h
	if target_h <= 1.0:
		target_h = max_content_h * base_s

	var x_cursor := 0.0
	for i in infos.size():
		var info: Dictionary = infos[i]
		var tex: Texture2D = info["tex"]
		var content_h: float = maxf(float(info["content_h"]), 1.0)
		var content_w: float = maxf(float(info["content_w"]), 1.0)
		var x0: float = float(info["x0"])
		var y0: float = float(info["y0"])
		var horizon_px: float = float(info["horizon_px"])
		var sy := target_h / content_h
		var sx := sy
		var piece_w := content_w * sx

		# 只显示非黑内容矩形，头碰头拼；略重叠消缝
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.region_enabled = true
		spr.region_rect = Rect2(x0, y0, content_w, content_h)
		spr.scale = Vector2(sx, sy)
		# region 顶 = y0；亮线相对 region 的偏移 = horizon_px - y0
		spr.position = Vector2(x_cursor, world_horizon - (horizon_px - y0) * sy)
		host.add_child(spr)

		x_cursor += piece_w
		if i < infos.size() - 1:
			x_cursor += far_seam_gap
		print("  • 内容拼接 ", tex.resource_path.get_file(),
			" w=", snappedf(piece_w, 0.1), " →x=", snappedf(x_cursor, 0.1))

	pl.motion_mirroring = Vector2(maxf(x_cursor, 1.0), 0.0)
	_far_strip_width = maxf(x_cursor, 1.0)
	pl.z_as_relative = false
	pl.z_index = 0 ## 最远
	_parallax.add_child(pl)
	print("📐 远景内容无缝宽=", snappedf(_far_strip_width, 0.1),
		" 地平线Y=", snappedf(world_horizon, 0.1))


## 分析远景/中远景：非黑（可见）内容包围盒 + 亮线地平线
## 黑边/黑底不算内容，避免头碰头时留下黑缝
func _analyze_far_texture(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	var h := tex.get_height()
	var w := tex.get_width()
	var y0 := 0
	var y1 := h - 1
	var x0 := 0
	var x1 := w - 1
	var horizon_px := float(h) * 0.5

	if img != null:
		if img.is_compressed():
			img = img.duplicate()
			img.decompress()
		w = img.get_width()
		h = img.get_height()
		var step_x := maxi(1, w / 128)
		var step_y := maxi(1, h / 128)
		var first_y := -1
		var last_y := -1
		var first_x := w
		var last_x := -1
		var row_lum: Dictionary = {}

		for y in range(h):
			var opaque := 0
			var lum_sum := 0.0
			var lum_n := 0
			for x in range(0, w, step_x):
				if _is_scenery_pixel(img.get_pixel(x, y)):
					opaque += 1
					var c := img.get_pixel(x, y)
					lum_sum += c.r * 0.3 + c.g * 0.5 + c.b * 0.2
					lum_n += 1
					first_x = mini(first_x, x)
					last_x = maxi(last_x, x)
			if opaque > 1:
				if first_y < 0:
					first_y = y
				last_y = y
				if lum_n > 0:
					row_lum[y] = lum_sum / float(lum_n)

		# 细扫左右，避免 step 漏边
		if first_y >= 0:
			for y in range(first_y, last_y + 1, maxi(1, step_y)):
				for x in range(w):
					if _is_scenery_pixel(img.get_pixel(x, y)):
						first_x = mini(first_x, x)
						break
				for x in range(w - 1, -1, -1):
					if _is_scenery_pixel(img.get_pixel(x, y)):
						last_x = maxi(last_x, x)
						break
			y0 = first_y
			y1 = last_y
			if last_x >= first_x:
				x0 = first_x
				x1 = last_x
			var mid := (first_y + last_y) * 0.5
			var band := maxi(4, int(float(last_y - first_y) * 0.25))
			var search0 := maxi(first_y, int(mid) - band)
			var search1 := mini(last_y, int(mid) + band)
			var best_y := int(mid)
			var best_lum := -1.0
			for y in range(search0, search1 + 1):
				if row_lum.has(y) and float(row_lum[y]) > best_lum:
					best_lum = float(row_lum[y])
					best_y = y
			horizon_px = float(best_y)

	# 左右各收缩 0px；内容宽至少 1
	x0 = clampi(x0, 0, w - 1)
	x1 = clampi(x1, x0, w - 1)
	y0 = clampi(y0, 0, h - 1)
	y1 = clampi(y1, y0, h - 1)
	return {
		"y0": y0,
		"y1": y1,
		"x0": x0,
		"x1": x1,
		"content_h": y1 - y0 + 1,
		"content_w": x1 - x0 + 1,
		"horizon_px": horizon_px,
		"horizon_ratio": horizon_px / float(maxi(h, 1)),
	}


## 可见景色：有一定亮度/色度；纯黑边不算（否则会拼进黑缝）
func _is_scenery_pixel(c: Color) -> bool:
	if c.a < 0.06:
		return false
	var lum := c.r * 0.3 + c.g * 0.5 + c.b * 0.2
	# 夜景建筑偏暗蓝，阈值放低；纯黑 (≈0) 排除
	if lum > 0.045:
		return true
	# 有明显色度的暗色也算内容
	var chroma := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
	return chroma > 0.04 and lum > 0.02


## 返回贴图不透明内容的 (top_ratio, bottom_ratio)，找不到则 (0,1)
func _texture_opaque_y_ratio(tex: Texture2D) -> Vector2:
	var info := _analyze_far_texture(tex)
	var h := float(maxi(tex.get_height(), 1))
	return Vector2(float(info["y0"]) / h, float(info["y1"]) / h)


# -------------------- 中远景：按非黑内容无缝头碰头（不受深渊影响）--------------------
func _build_mid_far_layer() -> void:
	var textures := _load_folder_textures("res://assets/tiles/background/mid_far")
	if textures.is_empty():
		print("⚠️ 无中远景图")
		return

	var pl := ParallaxLayer.new()
	pl.name = "Layer2_MidFar"
	pl.motion_scale = Vector2(mid_far_motion_scale_x, 1.0)

	var host := Node2D.new()
	host.name = "Tiles"
	# 贴图亮度压暗（中远景较弱）；禁止靠关卡 tint 伪装成“调图”
	host.modulate = _bg_image_modulate(mid_far_image_darken, mid_far_base_modulate)
	pl.add_child(host)

	var world_horizon := horizon_y + far_y_offset + mid_far_y_offset
	var vp_h := _estimate_viewport_h()

	var infos: Array[Dictionary] = []
	for tex in textures:
		var info := _analyze_far_texture(tex)
		info["tex"] = tex
		infos.append(info)
		print("  • 中远景内容 ", tex.resource_path.get_file(),
			" x=", info["x0"], "-", info["x1"],
			" y=", info["y0"], "-", info["y1"])

	var full_h := vp_h * 0.40
	var target_h := mid_far_content_target_h
	if target_h <= 1.0:
		target_h = full_h * mid_far_scale_mult

	# ⚠ mirroring 要求内容落在 [0, strip_w)。禁止用 mid_origin_x 偏移——
	# 否则滚到 wrap 空档会「走一段有、左移一步没」的假消失。
	var x_cursor := 0.0
	var placed := 0
	var sets := maxi(mid_far_repeat_sets, 1)
	for _set_i in sets:
		for i in infos.size():
			var info: Dictionary = infos[i]
			var tex: Texture2D = info["tex"]
			var content_h: float = maxf(float(info["content_h"]), 1.0)
			var content_w: float = maxf(float(info["content_w"]), 1.0)
			var x0: float = float(info["x0"])
			var y0: float = float(info["y0"])
			var y1: float = float(info["y1"])
			var sy := target_h / content_h
			var sx := sy
			var piece_w := content_w * sx
			# 脚底 = 内容底边 y1
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			spr.region_enabled = true
			spr.region_rect = Rect2(x0, y0, content_w, content_h)
			spr.scale = Vector2(sx, sy)
			spr.position = Vector2(x_cursor, world_horizon - (y1 - y0) * sy)
			host.add_child(spr)
			x_cursor += piece_w + mid_far_seam_gap
			placed += 1

	x_cursor -= mid_far_seam_gap
	var strip_w := maxf(x_cursor, 1.0)
	pl.motion_mirroring = Vector2(strip_w, 0.0)
	pl.z_as_relative = false
	pl.z_index = 1 ## 远景之上，中景/前景之下（_finalize 会再校正树序）
	_parallax.add_child(pl)
	print("📐 中远景内容无缝×", placed, " 带宽=", snappedf(strip_w, 0.1),
		" 高=", snappedf(target_h, 0.1), " 底→floor Y=", snappedf(world_horizon, 0.1),
		" 起点x=0(mirroring)")
	if placed <= 0:
		push_error("❌ 中远景放置失败：0 块 Sprite（违反 scenery 规则）")


# -------------------- 中景：按 Floor 段疏布整图；中心在 Floor 上；禁止切图 --------------------
func _build_mid_props() -> void:
	var textures := _load_folder_textures("res://assets/tiles/background/mid")
	if textures.is_empty():
		print("⚠️ 无中景图")
		return

	var pl := ParallaxLayer.new()
	pl.name = "Layer3_Mid"
	pl.motion_scale = Vector2(mid_motion_scale_x, 1.0)
	pl.motion_mirroring = Vector2.ZERO
	pl.z_as_relative = false
	pl.z_index = 10 ## 盖过中远景

	var host := Node2D.new()
	host.name = "Props"
	host.modulate = _bg_image_modulate(bg_image_darken, Color(1, 1, 1, 1))
	pl.add_child(host)

	var world_horizon := horizon_y + far_y_offset + mid_y_offset
	var vp_h := _estimate_viewport_h()
	var target_h := vp_h * mid_height_ratio

	var infos: Array[Dictionary] = []
	for tex in textures:
		var info := _analyze_far_texture(tex)
		info["tex"] = tex
		info["foot_px"] = float(info["y1"])
		infos.append(info)

	# 按 Floor 段放置：每段至少尝试 1 张；长段按间距疏布（避免抽点落空导致长平地无中景）
	var xs: Array[float] = []
	if not _floor_cover.is_empty():
		var vp_w := _estimate_viewport_w()
		var base_gap := maxf(mid_min_gap, vp_w * 0.55)
		for seg in _floor_cover:
			var a := float(seg.x)
			var b := float(seg.y)
			var seg_w := b - a
			if seg_w < 48.0:
				continue
			if seg_w < base_gap * 0.85:
				xs.append((a + b) * 0.5)
			else:
				var gap := clampf(seg_w * 0.5, base_gap * 0.65, base_gap * 1.15)
				var x := a + minf(80.0, seg_w * 0.25)
				var guard := 0
				while x <= b - 24.0 and guard < 40:
					guard += 1
					xs.append(x)
					x += gap
	else:
		var span := mid_span
		if span < 100.0 and _far_strip_width > 100.0:
			span = _far_strip_width * 2.0
		var vp_w2 := _estimate_viewport_w()
		var visible_n := maxi(mid_max_visible, 1)
		var min_gap := maxf(mid_min_gap, vp_w2 / float(visible_n) + 40.0)
		var max_gap := min_gap * maxf(mid_gap_max_mult, 1.0)
		var rel: Array[float] = _variable_spaced_xs(span, min_gap, max_gap)
		for r in rel:
			xs.append(mid_origin_x + r)

	var count := xs.size()
	if count <= 0:
		print("⚠️ 中景无可用 Floor 点")
		return

	var order: Array[int] = _mid_texture_order(infos.size(), count)
	var placed := 0

	for i in count:
		var info: Dictionary = infos[order[i]]
		var tex: Texture2D = info["tex"]
		var content_h: float = maxf(float(info["content_h"]), 1.0)
		var foot_px: float = float(info["foot_px"])
		var sy := target_h / content_h
		var sx := sy
		var dw := float(info["content_w"]) * sx
		var cx := xs[i]
		if not _floor_cover.is_empty() and not _center_on_floor(cx):
			continue
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# 不切图：只用非黑内容 region（等同裁黑边，不是跨缺口切开）
		spr.region_enabled = true
		spr.region_rect = Rect2(
			float(info["x0"]), float(info["y0"]),
			float(info["content_w"]), float(info["content_h"])
		)
		spr.scale = Vector2(sx, sy)
		spr.position = Vector2(cx - dw * 0.5, world_horizon - (foot_px - float(info["y0"])) * sy)
		host.add_child(spr)
		placed += 1

	_parallax.add_child(pl)
	print("📐 中景整图疏布×", placed, "（Floor 点 ", count, "，无切图）")
	if placed <= 0 and not _floor_cover.is_empty():
		push_error("❌ 中景未放置：有 Floor 却无 Mid（违反 scenery）")


## 中心 X 是否落在有 Floor 的区段内
func _center_on_floor(cx: float) -> bool:
	if _floor_cover.is_empty():
		return true
	for seg in _floor_cover:
		if cx >= float(seg.x) and cx <= float(seg.y):
			return true
	return false


## 沿 span 铺点：相邻间距在 [min_gap, max_gap] 随机（有远有近）
func _variable_spaced_xs(span: float, min_gap: float, max_gap: float) -> Array[float]:
	var out: Array[float] = []
	if span <= 0.0 or min_gap <= 0.0:
		return out
	var lo := min_gap
	var hi := maxf(max_gap, min_gap)
	var x := randf_range(0.0, lo * 0.45)
	var guard := 0
	while x <= span and guard < 400:
		guard += 1
		out.append(x)
		x += randf_range(lo, hi)
	if out.size() < 2 and span > lo:
		out.clear()
		x = randf_range(0.0, lo * 0.3)
		while x <= span and out.size() < 200:
			out.append(x)
			x += randf_range(lo, hi)
	return out


## 生成中景贴图顺序：先打乱用尽全部，再追加且相邻不重复
func _mid_texture_order(tex_n: int, count: int) -> Array[int]:
	var order: Array[int] = []
	if tex_n <= 0 or count <= 0:
		return order
	var bag: Array[int] = []
	for j in tex_n:
		bag.append(j)
	bag.shuffle()
	for j in bag:
		if order.size() >= count:
			break
		order.append(j)
	while order.size() < count:
		var last := order[order.size() - 1]
		var candidates: Array[int] = []
		for j in tex_n:
			if j != last:
				candidates.append(j)
		if candidates.is_empty():
			order.append(last)
		else:
			order.append(candidates[randi() % candidates.size()])
	return order


## 在 [0, span] 内随机生成 count 个 X，相邻至少 min_gap
func _random_spaced_xs(count: int, span: float, min_gap: float) -> Array[float]:
	var out: Array[float] = []
	if count <= 0:
		return out
	var gap := min_gap
	var need := gap * float(maxi(count - 1, 0))
	var use_span := span
	if need > span and count > 1:
		use_span = need * 1.05

	var tries := 0
	while out.size() < count and tries < 400:
		tries += 1
		var x := randf() * use_span
		var ok := true
		for existing in out:
			if absf(x - existing) < gap:
				ok = false
				break
		if ok:
			out.append(x)

	while out.size() < count:
		var i := out.size()
		var t := float(i + 1) / float(count + 1)
		out.append(use_span * t + randf_range(-gap * 0.1, gap * 0.1))
	return out


# -------------------- 前景：水平全程无缝头碰头铺满（不按 Floor 挖空）--------------------
func _build_foreground_layer() -> void:
	var textures := _load_folder_textures("res://assets/tiles/background/foreground")
	if textures.is_empty():
		print("⚠️ 无前景图")
		return

	var pl := ParallaxLayer.new()
	pl.name = "Layer4_Foreground"
	pl.motion_scale = Vector2(fg_motion_scale_x, 1.0)
	pl.z_as_relative = false
	pl.z_index = 20 ## 最前（视差层内）

	var host := Node2D.new()
	host.name = "Tiles"
	host.modulate = _bg_image_modulate(bg_image_darken, Color(1, 1, 1, 1))
	pl.add_child(host)

	var world_horizon := horizon_y + far_y_offset + fg_y_offset
	var vp_h := _estimate_viewport_h()

	var infos: Array[Dictionary] = []
	for tex in textures:
		var info := _analyze_far_texture(tex)
		info["tex"] = tex
		info["foot_px"] = float(info["y1"])
		infos.append(info)

	var full_h := vp_h * 0.45
	var target_h := fg_content_target_h
	if target_h <= 1.0:
		target_h = full_h * fg_scale_mult

	var span := _foreground_full_span()
	var x0 := float(span.x)
	var x1 := float(span.y)
	# 保证至少覆盖关卡 Floor 蒙版的左右极值
	if not _floor_cover.is_empty():
		for seg in _floor_cover:
			x0 = minf(x0, float(seg.x))
			x1 = maxf(x1, float(seg.y))

	var placed := _pave_fg_seamless_span(host, infos, target_h, fg_seam_gap, x0, x1, world_horizon)
	# 条带从关卡原点铺满，不用 mirroring（起点常非 0，mirror 会空档）
	pl.motion_mirroring = Vector2.ZERO

	_parallax.add_child(pl)
	print("📐 前景水平无缝铺满×", placed, " 区间[", snappedf(x0, 0.1), ",", snappedf(x1, 0.1), "]")
	if placed <= 0:
		push_error("❌ 前景无缝铺满失败：0 块 Sprite")


func _foreground_full_span() -> Vector2:
	if absf(mid_origin_x) > 1.0 and mid_span > 100.0:
		return Vector2(mid_origin_x, mid_origin_x + mid_span)
	var w := maxf(_far_strip_width, mid_span)
	if w < 100.0:
		w = 1600.0
	if absf(mid_origin_x) > 1.0:
		return Vector2(mid_origin_x, mid_origin_x + w)
	return Vector2(0.0, w)


## 水平全程头碰头无缝铺满；非黑内容 region；末块拉满剩余宽度，不留空缝
func _pave_fg_seamless_span(
	host: Node2D,
	infos: Array[Dictionary],
	target_h: float,
	seam_gap: float,
	x0: float,
	x1: float,
	world_horizon: float
) -> int:
	if infos.is_empty() or x1 - x0 < 8.0:
		return 0
	var x_cursor := x0
	var placed := 0
	var guard := 0
	var i := 0
	while x_cursor < x1 - 0.5 and guard < 2000:
		guard += 1
		var info: Dictionary = infos[i % infos.size()]
		i += 1
		var tex: Texture2D = info["tex"]
		var cw: float = maxf(float(info["content_w"]), 1.0)
		var ch: float = maxf(float(info["content_h"]), 1.0)
		var y0: float = float(info["y0"])
		var y1: float = float(info["y1"])
		var sy := target_h / ch
		var sx := sy
		var piece_w := cw * sx
		var remain := x1 - x_cursor
		var is_last := (x_cursor + piece_w + seam_gap >= x1 - 0.5)
		if is_last:
			piece_w = remain
			sx = piece_w / cw
			# 高度保持目标，仅横向拉满消缝
			sy = target_h / ch

		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.region_enabled = true
		spr.region_rect = Rect2(float(info["x0"]), y0, cw, ch)
		spr.scale = Vector2(sx, sy)
		spr.position = Vector2(x_cursor, world_horizon - (y1 - y0) * sy)
		host.add_child(spr)
		placed += 1
		if is_last:
			break
		x_cursor += piece_w + seam_gap
	return placed


func _add_fog_layer() -> void:
	var pl := ParallaxLayer.new()
	pl.name = "FogBreath"
	pl.motion_scale = Vector2(0.65, 0.65)
	pl.motion_mirroring = Vector2(960, 0)
	var fog := GPUParticles2D.new()
	fog.amount = 18
	fog.lifetime = 10.0
	fog.preprocess = 4.0
	fog.position = Vector2(480, horizon_y - 90)
	fog.visibility_rect = Rect2(-900, -500, 1800, 1000)
	fog.texture = _soft_dot()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(500, 50, 1)
	mat.direction = Vector3(0.3, -0.05, 0)
	mat.spread = 18.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 11.0
	mat.gravity = Vector3(0, -1.2, 0)
	mat.scale_min = 0.7
	mat.scale_max = 1.8
	mat.color = Color(0.55, 0.7, 0.95, 0.14)
	fog.process_material = mat
	pl.add_child(fog)
	_parallax.add_child(pl)


func _add_petal_layer() -> void:
	var paths := _list_pngs("res://assets/tiles/background/petals")
	if paths.is_empty():
		return
	var prefer: Array[String] = [
		"petal_flower_01.png", "petal_flower_02.png", "petal_flower_03.png", "petal_flower_05.png",
		"petal_leaf_01.png", "petal_leaf_03.png", "petal_leaf_05.png",
		"petal_spore_01.png", "petal_spore_03.png",
	]
	var use_paths: Array[String] = []
	for name_s in prefer:
		var full := "res://assets/tiles/background/petals/%s" % name_s
		if ResourceLoader.exists(full):
			use_paths.append(full)
	if use_paths.is_empty():
		use_paths = paths

	var pl := ParallaxLayer.new()
	pl.name = "Petals"
	# 与中远景同滚动率：钉在背景空间，不跟屏幕 Canvas 走
	pl.motion_scale = Vector2(mid_far_motion_scale_x, 1.0)
	pl.motion_mirroring = Vector2(960.0, 0.0)
	pl.z_index = 5

	var fade_shader: Shader = load("res://levels/petals_fade.gdshader") as Shader
	var total := 30
	var n := use_paths.size()
	var per := maxi(int(floor(float(total) / float(n))), 1)
	var remain := total
	for i in range(n):
		var amt := per if i < n - 1 else maxi(remain, 1)
		remain -= amt
		if amt <= 0:
			break
		var tex := load(use_paths[i]) as Texture2D
		if tex == null:
			continue
		var p := GPUParticles2D.new()
		p.name = "PetalsEmitter_%d" % i
		p.amount = amt
		p.lifetime = 7.5
		p.preprocess = 3.5
		p.explosiveness = 0.0
		p.randomness = 0.45
		p.texture = tex
		p.position = Vector2(480.0, horizon_y - 200.0)
		p.visibility_rect = Rect2(-1000, -400, 2200, 1200)
		p.local_coords = true
		p.emitting = true

		if fade_shader:
			var sh := ShaderMaterial.new()
			sh.shader = fade_shader
			sh.set_shader_parameter("floor_y", horizon_y)
			sh.set_shader_parameter("fade_band", 80.0)
			p.material = sh
		else:
			var blend := CanvasItemMaterial.new()
			blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			p.material = blend

		var mat := ParticleProcessMaterial.new()
		mat.particle_flag_disable_z = true
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(520.0, 16.0, 0.0)
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
		mat.scale_min = 0.0275
		mat.scale_max = 0.0825
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
		pl.add_child(p)

	_parallax.add_child(pl)
	print("🌸 花瓣已挂入视差层 motion_scale=", mid_far_motion_scale_x, "（不跟屏幕）")


func tween_level_atmosphere(tint: Color, duration: float = 1.2) -> void:
	# ParallaxBackground 是 CanvasLayer，没有 modulate；改 Tween 各 ParallaxLayer
	# 氛围色过暗会把远景“吃掉”，抬到最低可见亮度
	var safe := Color(
		maxf(tint.r, 0.42),
		maxf(tint.g, 0.45),
		maxf(tint.b, 0.55),
		1.0
	)
	if _parallax == null:
		return
	if _brightness_tween and _brightness_tween.is_valid():
		_brightness_tween.kill()
	_brightness_tween = create_tween()
	_brightness_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_brightness_tween.set_parallel(true)
	var any := false
	for child in _parallax.get_children():
		if child is CanvasItem:
			any = true
			_brightness_tween.tween_property(child, "modulate", safe, duration) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not any:
		_brightness_tween.kill()
		_brightness_tween = null


func _apply_initial_brightness() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("apply_level_brightness"):
		var lm := get_node_or_null("/root/LevelManager")
		var id := 1
		if lm:
			id = int(lm.get("current_level_id"))
		gm.apply_level_brightness(id, 0.01)
	elif _parallax:
		for child in _parallax.get_children():
			if child is CanvasItem:
				(child as CanvasItem).modulate = Color(0.35, 0.4, 0.6, 1.0)


func _estimate_viewport_h() -> float:
	var vr := get_viewport().get_visible_rect().size
	return maxf(vr.y, 360.0)


## 贴图亮度压暗：modulate = bias / darken（直接压暗 Sprite 宿主，不改 PNG 文件）
func _bg_image_modulate(darken: float, bias: Color = Color(1, 1, 1, 1)) -> Color:
	var d := maxf(darken, 1.0)
	return Color(bias.r / d, bias.g / d, bias.b / d, bias.a)


func _estimate_viewport_w() -> float:
	var vr := get_viewport().get_visible_rect().size
	return maxf(vr.x, 640.0)


func _soft_dot() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size * 0.5, size * 0.5)
	for x in size:
		for y in size:
			var d := Vector2(x, y).distance_to(c) / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a *= a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _load_folder_textures(dir_path: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for p in _list_pngs(dir_path):
		var tex := load(p) as Texture2D
		if tex:
			out.append(tex)
	return out


func _list_pngs(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		return out
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if not da.current_is_dir() and fname.to_lower().ends_with(".png"):
			out.append(dir_path.path_join(fname))
		fname = da.get_next()
	da.list_dir_end()
	out.sort()
	return out
