extends RefCounted
class_name TerrainArtPainter
## 与 level_controller（L1–L3）相同的 Floor/Platform 贴图铺法：
## 裁非黑内容 → 提亮 → 细条加粗 → 超宽切中拼接 → 头碰头铺满 → 碰撞=贴图显示尺寸
## 仅供 Level 04 等手写关复用；不改动 level_controller 本体。

const FLOOR_COLL_H := 32.0
const FLOOR_MIN_VISUAL_H := 48.0
const PLATFORM_MIN_VISUAL_H := 56.0
const TERRAIN_BRIGHTEN := 1.55
const TERRAIN_THIN_ASPECT := 6.5
const PLATFORM_COLLISION_Y_NUDGE := 7.0

var _stitch_cache: Dictionary = {}


func load_ground_textures() -> Array[Texture2D]:
	return _load_paths([
		"res://assets/tiles/ground/stoneBrick/brick_01.png",
		"res://assets/tiles/ground/stoneBrick/brick_02.png",
		"res://assets/tiles/ground/stoneBrick/brick_03.png",
		"res://assets/tiles/ground/wooden/wooden_01.png",
		"res://assets/tiles/ground/wooden/wooden_02.png",
		"res://assets/tiles/ground/wooden/wooden_03.png",
	])


func load_platform_textures(goth_only: bool = false) -> Array[Texture2D]:
	var paths: Array[String] = []
	if goth_only:
		paths = [
			"res://assets/tiles/platform/goth_01.png",
			"res://assets/tiles/platform/goth_02.png",
			"res://assets/tiles/platform/goth_03.png",
		]
	else:
		paths = [
			"res://assets/tiles/platform/platform_01.png",
			"res://assets/tiles/platform/platform_02.png",
			"res://assets/tiles/platform/platform_03.png",
		]
	var out := _load_paths(paths)
	if out.is_empty() and goth_only:
		return load_platform_textures(false)
	return out


func _load_paths(paths: Array[String]) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var tex := load(p) as Texture2D
		if tex:
			out.append(tex)
	return out


## Floor：StaticBody2D + Visuals，头碰头铺贴，碰撞=可视（同 L1–L3 _pave_matched_strip）
## 返回实际铺到的 x_end 与最大块高
func pave_floor_span(
	parent: Node2D,
	textures: Array[Texture2D],
	x0: float,
	x1: float,
	top_y: float,
	target_h: float = FLOOR_COLL_H
) -> Dictionary:
	if textures.is_empty() or x1 - x0 < 4.0:
		return {"count": 0, "x_end": x0, "max_h": 0.0}

	var body := StaticBody2D.new()
	body.name = "FloorBody_%d" % int(x0)
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("walls")
	body.position = Vector2.ZERO
	parent.add_child(body)

	var visuals := Node2D.new()
	visuals.name = "FloorVisuals"
	body.add_child(visuals)

	var x_cursor := x0
	var count := 0
	var max_h := 0.0
	var guard := 0
	while x_cursor < x1 - 2.0 and guard < 400:
		guard += 1
		var remain := x1 - x_cursor
		var best_tex: Texture2D = null
		var best_info: Dictionary = {}
		var best_w := 0.0
		var best_h := 0.0

		for _try in range(mini(16, maxi(textures.size() * 3, 8))):
			var tex: Texture2D = textures[randi() % textures.size()]
			var info := analyze_floor_texture(tex)
			var content_h: float = maxf(float(info["content_h"]), 1.0)
			var content_w_px: float = maxf(float(info["content_w"]), 1.0)
			var piece_h := terrain_visual_height(content_w_px, content_h, maxf(target_h, FLOOR_MIN_VISUAL_H))
			var natural_w := content_w_px * (piece_h / content_h)
			var piece_w := minf(natural_w, remain)
			if piece_w >= 4.0:
				best_tex = tex
				best_info = info
				best_w = piece_w
				best_h = piece_h
				if natural_w <= remain + 0.25:
					break

		if best_tex == null or best_w < 4.0:
			break

		if x1 - (x_cursor + best_w) < 8.0:
			best_w = x1 - x_cursor
			best_h = maxf(best_h, FLOOR_MIN_VISUAL_H)

		var vis: Dictionary = make_terrain_sprite_fit(best_tex, best_info, best_w, best_h)
		if vis.is_empty():
			break

		var spr := Sprite2D.new()
		spr.texture = vis["texture"]
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.region_enabled = bool(vis["region_enabled"])
		if spr.region_enabled:
			spr.region_rect = vis["region_rect"]
		var src_w := spr.region_rect.size.x if spr.region_enabled else float(spr.texture.get_width())
		var src_h := spr.region_rect.size.y if spr.region_enabled else float(spr.texture.get_height())
		spr.scale = Vector2(best_w / maxf(src_w, 1.0), best_h / maxf(src_h, 1.0))
		spr.modulate = vis["modulate"]
		spr.position = Vector2(x_cursor, top_y)
		visuals.add_child(spr)

		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(best_w, best_h)
		cs.shape = rect
		cs.position = Vector2(x_cursor + best_w * 0.5, top_y + best_h * 0.5)
		body.add_child(cs)

		max_h = maxf(max_h, best_h)
		x_cursor += best_w
		count += 1
		if x1 - x_cursor < 0.5:
			break

	return {"count": count, "x_end": x_cursor, "max_h": max_h}


## Platform：Visuals 头碰头 + 每 Sprite 同尺寸 One-Way（含 Y nudge，同 L1–L3）
func place_platform_span(
	parent: Node2D,
	textures: Array[Texture2D],
	x0: float,
	x1: float,
	top_y: float,
	name_hint: String = "Plat"
) -> float:
	var span_w := x1 - x0
	if textures.is_empty() or span_w < 8.0:
		return 0.0

	var root := Node2D.new()
	root.name = name_hint
	root.position = Vector2.ZERO
	root.add_to_group("platforms")
	parent.add_child(root)

	var visuals := Node2D.new()
	visuals.name = "PlatformVisuals"
	root.add_child(visuals)

	var tex: Texture2D = textures[randi() % textures.size()]
	var info := analyze_platform_texture(tex)
	var content_w: float = maxf(float(info["content_w"]), 1.0)
	var content_h: float = maxf(float(info["content_h"]), 1.0)
	var visual_h := terrain_visual_height(content_w, content_h, PLATFORM_MIN_VISUAL_H)

	var x_cursor := x0
	var guard := 0
	while x_cursor < x1 - 0.5 and guard < 200:
		guard += 1
		var remain := x1 - x_cursor
		var natural_w := content_w * (visual_h / content_h)
		var piece_w := minf(natural_w, remain)
		if remain - piece_w < 8.0:
			piece_w = remain
		if piece_w < 2.0:
			break

		var vis: Dictionary = make_terrain_sprite_fit(tex, info, piece_w, visual_h)
		if vis.is_empty():
			break

		var spr := Sprite2D.new()
		spr.texture = vis["texture"]
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.region_enabled = bool(vis["region_enabled"])
		if spr.region_enabled:
			spr.region_rect = vis["region_rect"]
		var src_w := spr.region_rect.size.x if spr.region_enabled else float(spr.texture.get_width())
		var src_h := spr.region_rect.size.y if spr.region_enabled else float(spr.texture.get_height())
		spr.scale = Vector2(piece_w / maxf(src_w, 1.0), visual_h / maxf(src_h, 1.0))
		spr.modulate = vis["modulate"]
		spr.position = Vector2(x_cursor, top_y)
		spr.z_index = 1
		spr.set_meta("plat_w", piece_w)
		spr.set_meta("plat_h", visual_h)
		visuals.add_child(spr)

		# 碰撞 = 贴图显示矩形；顶边相对贴图下移 NUDGE（翘角对齐）
		var body := StaticBody2D.new()
		body.name = "PlatformPiece_%d" % root.get_child_count()
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("walls")
		root.add_child(body)
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(piece_w, visual_h)
		cs.shape = rect
		var col_top := top_y + PLATFORM_COLLISION_Y_NUDGE
		cs.position = Vector2(x_cursor + piece_w * 0.5, col_top + visual_h * 0.5)
		cs.one_way_collision = true
		cs.one_way_collision_margin = 4.0
		body.add_child(cs)
		body.set_meta("art_rect", Rect2(x_cursor, top_y, piece_w, visual_h))

		x_cursor += piece_w

	return visual_h


func terrain_visual_height(content_w: float, content_h: float, min_h: float) -> float:
	var h := maxf(min_h, FLOOR_COLL_H)
	var aspect := content_w / maxf(content_h, 1.0)
	if aspect >= TERRAIN_THIN_ASPECT:
		h = maxf(h, min_h * 1.35)
	return h


func make_terrain_sprite_fit(tex: Texture2D, info: Dictionary, world_w: float, world_h: float) -> Dictionary:
	if tex == null or world_w < 2.0 or world_h < 2.0:
		return {}
	var rx0: float = float(info["x0"])
	var ry0: float = float(info["y0"])
	var cw: float = maxf(float(info["content_w"]), 1.0)
	var ch: float = maxf(float(info["content_h"]), 1.0)
	var sy := world_h / ch
	var natural_w := cw * sy
	var bright := Color(TERRAIN_BRIGHTEN, TERRAIN_BRIGHTEN, minf(TERRAIN_BRIGHTEN * 1.05, 1.85), 1.0)

	if natural_w <= world_w + 0.5:
		var sx := sy
		if natural_w < world_w * 0.92:
			sx = world_w / cw
		return {
			"texture": tex,
			"region_enabled": true,
			"region_rect": Rect2(rx0, ry0, cw, ch),
			"scale": Vector2(sx, sy),
			"modulate": bright,
		}

	var need_px := world_w / sy
	need_px = clampf(need_px, 8.0, cw)
	var stitched: Texture2D = _stitch_trim_horizontal(tex, int(rx0), int(ry0), int(cw), int(ch), int(ceil(need_px)))
	if stitched == null:
		return {
			"texture": tex,
			"region_enabled": true,
			"region_rect": Rect2(rx0, ry0, cw, ch),
			"scale": Vector2(world_w / cw, sy),
			"modulate": bright,
		}
	var sw := float(stitched.get_width())
	var sh := float(stitched.get_height())
	return {
		"texture": stitched,
		"region_enabled": false,
		"region_rect": Rect2(),
		"scale": Vector2(world_w / maxf(sw, 1.0), world_h / maxf(sh, 1.0)),
		"modulate": bright,
	}


func _stitch_trim_horizontal(
	tex: Texture2D, x0: int, y0: int, cw: int, ch: int, keep_w: int
) -> Texture2D:
	keep_w = clampi(keep_w, 4, cw)
	var key := "%s_%d_%d_%d_%d_%d" % [tex.resource_path, x0, y0, cw, ch, keep_w]
	if _stitch_cache.has(key):
		return _stitch_cache[key] as Texture2D

	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()

	var left_w := keep_w / 2
	var right_w := keep_w - left_w
	var out := Image.create(keep_w, ch, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(img, Rect2i(x0, y0, left_w, ch), Vector2i(0, 0))
	out.blit_rect(img, Rect2i(x0 + cw - right_w, y0, right_w, ch), Vector2i(left_w, 0))

	var tex_out := ImageTexture.create_from_image(out)
	_stitch_cache[key] = tex_out
	return tex_out


func analyze_platform_texture(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	var w := tex.get_width()
	var h := tex.get_height()
	var x0 := 0
	var y0 := 0
	var x1 := w - 1
	var y1 := h - 1
	if img != null:
		if img.is_compressed():
			img = img.duplicate()
			img.decompress()
		w = img.get_width()
		h = img.get_height()
		var first_y := -1
		var last_y := -1
		var first_x := w
		var last_x := -1
		var step := maxi(1, w / 128)
		for y in range(h):
			var hit := false
			for x in range(0, w, step):
				var c := img.get_pixel(x, y)
				if _is_platform_pixel(c):
					hit = true
					first_x = mini(first_x, x)
					last_x = maxi(last_x, x)
			if hit:
				if first_y < 0:
					first_y = y
				last_y = y
		if first_y >= 0:
			for y in range(first_y, last_y + 1, maxi(1, h / 64)):
				for x in range(w):
					if _is_platform_pixel(img.get_pixel(x, y)):
						first_x = mini(first_x, x)
						break
				for x in range(w - 1, -1, -1):
					if _is_platform_pixel(img.get_pixel(x, y)):
						last_x = maxi(last_x, x)
						break
			y0 = first_y
			y1 = last_y
			if last_x >= first_x:
				x0 = first_x
				x1 = last_x
	return {
		"x0": x0, "y0": y0, "x1": x1, "y1": y1,
		"content_w": maxi(1, x1 - x0 + 1),
		"content_h": maxi(1, y1 - y0 + 1),
	}


func analyze_floor_texture(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	var h := tex.get_height()
	var w := tex.get_width()
	var y0 := 0
	var y1 := h - 1
	var x0 := 0
	var x1 := w - 1
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
		for y in range(h):
			var row_hit := false
			for x in range(0, w, step_x):
				var c := img.get_pixel(x, y)
				if c.a > 0.08 and (c.r + c.g + c.b) > 0.05:
					row_hit = true
					first_x = mini(first_x, x)
					last_x = maxi(last_x, x)
			if row_hit:
				if first_y < 0:
					first_y = y
				last_y = y
		if first_y >= 0:
			for y in range(first_y, last_y + 1, maxi(1, step_y)):
				for x in range(w):
					var c2 := img.get_pixel(x, y)
					if c2.a > 0.08 and (c2.r + c2.g + c2.b) > 0.05:
						first_x = mini(first_x, x)
						break
				for x in range(w - 1, -1, -1):
					var c3 := img.get_pixel(x, y)
					if c3.a > 0.08 and (c3.r + c3.g + c3.b) > 0.05:
						last_x = maxi(last_x, x)
						break
			y0 = first_y
			y1 = last_y
			if last_x >= first_x:
				x0 = first_x
				x1 = last_x
	return {
		"y0": y0, "y1": y1, "x0": x0, "x1": x1,
		"content_h": y1 - y0 + 1,
		"content_w": x1 - x0 + 1,
	}


func _is_platform_pixel(c: Color) -> bool:
	if c.a < 0.08:
		return false
	var lum := c.r * 0.3 + c.g * 0.5 + c.b * 0.2
	if lum > 0.05:
		return true
	var chroma := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
	return chroma > 0.04 and lum > 0.02
