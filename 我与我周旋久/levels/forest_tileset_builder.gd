extends RefCounted
class_name ForestTileSetBuilder
## 使用现有 ground / platform / ladder / hazard 贴图。
## 逻辑格 32×32（碰撞正确）；贴图多为 512，由引擎按格缩放显示。
## 禁止再对 TileMapLayer 做 scale——缩放碰撞体会卡死角色。

const TILE_SIZE := Vector2i(32, 32)
const WORLD_CELL := 32.0
const ART_SIZE := Vector2i(512, 512)

const SRC_FLOOR := 0
const SRC_PLATFORM := 1
const SRC_WALL := 2
const SRC_DECOR := 3
const SRC_LADDER := 4
const SRC_SPIKE := 5
const SRC_FLOOR_BRICK := 6
const SRC_FLOOR_WOOD := 7
const SRC_PLATFORM_GOTH := 8
const SRC_FLOOR_G2 := 9
const SRC_FLOOR_G3 := 10
const SRC_FLOOR_BRICK2 := 11
const SRC_FLOOR_BRICK3 := 12
const SRC_FLOOR_WOOD2 := 13


static func world_tilemap_scale() -> Vector2:
	# 兼容旧调用：一律 1，不再缩放图层
	return Vector2.ONE


## 可用于铺长地板的 source id（从 ground 文件夹选用）
static func floor_source_ids() -> Array[int]:
	return [
		SRC_FLOOR, SRC_FLOOR_G2, SRC_FLOOR_G3,
		SRC_FLOOR_BRICK, SRC_FLOOR_BRICK2, SRC_FLOOR_BRICK3,
		SRC_FLOOR_WOOD, SRC_FLOOR_WOOD2,
	]


static func build() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = TILE_SIZE
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)

	_add_art_tile(ts, SRC_FLOOR, _first_existing([
		"res://assets/tiles/ground/stoneBrick/brick_01.png",
		"res://assets/tiles/ground/wooden/wooden_01.png",
	]), false)
	_add_art_tile(ts, SRC_FLOOR_G2, _first_existing([
		"res://assets/tiles/ground/stoneBrick/brick_02.png",
		"res://assets/tiles/ground/wooden/wooden_02.png",
	]), false)
	_add_art_tile(ts, SRC_FLOOR_G3, _first_existing([
		"res://assets/tiles/ground/stoneBrick/brick_03.png",
		"res://assets/tiles/ground/wooden/wooden_03.png",
	]), false)
	_add_art_tile(ts, SRC_FLOOR_BRICK, _first_existing([
		"res://assets/tiles/ground/stoneBrick/brick_01.png",
	]), false)
	_add_art_tile(ts, SRC_FLOOR_BRICK2, _first_existing([
		"res://assets/tiles/ground/stoneBrick/brick_02.png",
	]), false)
	_add_art_tile(ts, SRC_FLOOR_BRICK3, _first_existing([
		"res://assets/tiles/ground/stoneBrick/brick_03.png",
	]), false)
	_add_art_tile(ts, SRC_FLOOR_WOOD, _first_existing([
		"res://assets/tiles/ground/wooden/wooden_01.png",
	]), false)
	_add_art_tile(ts, SRC_FLOOR_WOOD2, _first_existing([
		"res://assets/tiles/ground/wooden/wooden_02.png",
	]), false)
	_add_art_tile(ts, SRC_PLATFORM, _first_existing([
		"res://assets/tiles/platform/platform_01.png",
		"res://assets/tiles/platform/platform_02.png",
		"res://assets/tiles/platform/platform_03.png",
	]), true)
	_add_art_tile(ts, SRC_PLATFORM_GOTH, _first_existing([
		"res://assets/tiles/platform/goth_01.png",
		"res://assets/tiles/platform/goth_02.png",
		"res://assets/tiles/platform/goth_03.png",
	]), true)
	_add_art_tile(ts, SRC_WALL, _first_existing([
		"res://assets/tiles/ground/stoneBrick/brick_02.png",
		"res://assets/tiles/wall_tile.png",
	]), false)
	_add_art_tile(ts, SRC_DECOR, _first_existing([
		"res://assets/tiles/ground/wooden/wooden_03.png",
	]), false, true)
	_add_art_tile(ts, SRC_LADDER, _first_existing([
		"res://assets/tiles/ladder/ladder_01.png",
	]), false, true)
	_add_art_tile(ts, SRC_SPIKE, _first_existing([
		"res://assets/tiles/hazard/hazard_ground_01.png",
	]), false, true)
	return ts


static func _first_existing(paths: Array) -> String:
	for p in paths:
		if ResourceLoader.exists(str(p)):
			return str(p)
	return ""


## 裁掉上下透明边，让“可见地面顶”贴齐格子顶（碰撞仍是整格 32×32）
static func _crop_opaque_top_aligned(tex: Texture2D) -> Texture2D:
	var img: Image = tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()

	var w := img.get_width()
	var h := img.get_height()
	var y0 := h
	var y1 := -1
	var step := maxi(1, w / 128)
	for y in range(h):
		var hit := false
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			if c.a > 0.08 and (c.r + c.g + c.b) > 0.05:
				hit = true
				break
		if hit:
			y0 = mini(y0, y)
			y1 = maxi(y1, y)

	if y1 < y0:
		return tex

	# 上下各留 1px，避免裁切锯齿
	y0 = maxi(0, y0 - 1)
	y1 = mini(h - 1, y1 + 1)
	var cropped := img.get_region(Rect2i(0, y0, w, y1 - y0 + 1))
	return ImageTexture.create_from_image(cropped)


static func _add_art_tile(
	ts: TileSet,
	source_id: int,
	tex_path: String,
	one_way: bool,
	no_collision: bool = false
) -> void:
	if tex_path == "" or not ResourceLoader.exists(tex_path):
		return
	var tex: Texture2D = load(tex_path)
	if tex == null:
		return

	# 美术图常带上下大块透明（地面内容约在竖直 40%~55%），
	# 整图塞进 32×32 会让“看得见的地面顶”远低于碰撞顶 → 角色像陷进贴图。
	# 裁到不透明内容后再当一格，视觉顶与碰撞顶对齐。
	var aligned := _crop_opaque_top_aligned(tex)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = aligned
	atlas.texture_region_size = Vector2i(aligned.get_width(), aligned.get_height())
	atlas.create_tile(Vector2i(0, 0))
	ts.add_source(atlas, source_id)

	var td: TileData = atlas.get_tile_data(Vector2i(0, 0), 0)
	if td == null or no_collision:
		return

	# 碰撞按逻辑格 32×32
	var half := Vector2(TILE_SIZE) * 0.5
	var poly := PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	if one_way:
		poly = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, -half.y + 6.0),
			Vector2(-half.x, -half.y + 6.0),
		])
	td.add_collision_polygon(0)
	td.set_collision_polygon_points(0, 0, poly)
	if one_way:
		td.set_collision_polygon_one_way(0, 0, true)
		td.set_collision_polygon_one_way_margin(0, 0, 1.0)
