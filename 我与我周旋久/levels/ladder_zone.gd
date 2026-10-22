extends Area2D
## ==================== 攀爬梯子区 ====================
## 纯 Area2D 检测；裁掉黑边后按目标宽度放大竖向铺满。不改玩家状态机枚举。
## 逻辑顶/底 = 两台表面；判定盒向上加长，方便站在上台按 S 下井。

const LADDER_PATHS: Array[String] = [
	"res://assets/tiles/ladder/ladder_01.png",
	"res://assets/tiles/ladder/ladder_02.png",
	"res://assets/tiles/ladder/ladder_03.png",
	"res://assets/tiles/ladder/ladder_04.png",
	"res://assets/tiles/ladder/ladder_05.png",
	"res://assets/tiles/ladder/ladder_06.png",
	"res://assets/tiles/ladder/ladder_07.png",
	"res://assets/tiles/ladder/ladder_08.png",
	"res://assets/tiles/ladder/ladder_09.png",
]

## 裁黑边后梯子本体的目标显示宽度（原 64 → 0.8 倍）
@export var visual_width: float = 51.2
## 攀爬判定宽度（须贴近视觉柱身；过宽会吞掉岛上走路/起跳的 W·S）
@export var climb_hit_width: float = 28.0
## 判定盒向上超出逻辑顶少许（仅方便站在梯顶正上按 S）
@export var top_grab_extend: float = 14.0
## 判定盒向下超出逻辑底少许
@export var bottom_grab_extend: float = 8.0

## setup 时按台子长度钳制后的实际宽度
var _visual_w: float = 51.2
var _hit_w: float = 28.0
var _tex_index: int = 0
## 逻辑顶/底（世界 Y，不含 grab 外扩）
var _logical_top_y: float = 0.0
var _logical_bottom_y: float = 64.0


func _ready() -> void:
	add_to_group("climb_ladders")
	monitoring = true
	monitorable = true
	collision_layer = 0
	collision_mask = 1 ## 检测玩家层
	z_index = 3


## top_y / bottom_y：世界坐标（Y 向下增大）；center_x 为梯子中心
## max_platform_len：所连两台较短边长度；梯子视觉须细于它，但判定不能细到抓不住
func setup(
	center_x: float,
	top_y: float,
	bottom_y: float,
	max_platform_len: float = -1.0,
	tex_index: int = 0
) -> void:
	if bottom_y < top_y:
		var tmp := top_y
		top_y = bottom_y
		bottom_y = tmp
	var height := maxf(bottom_y - top_y, 24.0)
	_logical_top_y = top_y
	_logical_bottom_y = bottom_y
	_tex_index = maxi(tex_index, 0)

	_visual_w = visual_width
	_hit_w = climb_hit_width
	if max_platform_len > 0.0:
		var cap := maxf(max_platform_len * 0.45, 18.0)
		_visual_w = minf(_visual_w, cap)
		# 判定贴柱身：约视觉宽，下限 18（只认正上方）
		_hit_w = clampf(minf(climb_hit_width, _visual_w * 0.85), 18.0, maxf(cap * 0.85, 18.0))

	# 节点放在「外扩后的顶」，视觉仍从逻辑顶开始画
	var grab_h := height + top_grab_extend + bottom_grab_extend
	position = Vector2(center_x, top_y - top_grab_extend)

	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null:
		cs = CollisionShape2D.new()
		cs.name = "CollisionShape2D"
		add_child(cs)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_hit_w, grab_h)
	cs.shape = rect
	cs.position = Vector2(0.0, grab_h * 0.5)
	cs.disabled = false

	_pave_visuals(height)


func _pave_visuals(height: float) -> void:
	var old := get_node_or_null("Visuals")
	if old:
		old.queue_free()
	var host := Node2D.new()
	host.name = "Visuals"
	add_child(host)
	# 视觉从逻辑顶画起（节点已上移 top_grab_extend）
	host.position = Vector2(0.0, top_grab_extend)

	var tex := _load_ladder_tex_by_index(_tex_index)
	if tex == null:
		var fallback := ColorRect.new()
		fallback.size = Vector2(_visual_w * 0.55, height)
		fallback.position = Vector2(-fallback.size.x * 0.5, 0.0)
		fallback.color = Color(0.62, 0.48, 0.30, 0.9)
		host.add_child(fallback)
		return

	var atlas := _make_content_atlas(tex)
	var region: Rect2 = atlas.region
	var cw := maxf(region.size.x, 1.0)
	var ch := maxf(region.size.y, 1.0)
	var sx := _visual_w / cw
	var piece_h := ch * sx
	var y := 0.0
	var guard := 0
	while y < height - 1.0 and guard < 120:
		guard += 1
		var remain := height - y
		var use_h := minf(piece_h, remain)
		var src_h := use_h / sx
		var piece := AtlasTexture.new()
		piece.atlas = atlas.atlas
		piece.region = Rect2(region.position.x, region.position.y, cw, src_h)
		var spr := Sprite2D.new()
		spr.centered = false
		spr.texture = piece
		spr.scale = Vector2(sx, sx)
		spr.position = Vector2(-_visual_w * 0.5, y)
		spr.modulate = Color(1.2, 1.12, 1.0, 1.0)
		host.add_child(spr)
		y += use_h
		if remain <= use_h + 0.5:
			break


func _make_content_atlas(tex: Texture2D) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	var full := Rect2(0.0, 0.0, float(tex.get_width()), float(tex.get_height()))
	var img := tex.get_image()
	if img == null:
		atlas.region = full
		return atlas
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	var step := 2
	for yy in range(0, h, step):
		for xx in range(0, w, step):
			var c := img.get_pixel(xx, yy)
			if c.a < 0.12:
				continue
			if c.r + c.g + c.b < 0.18:
				continue
			min_x = mini(min_x, xx)
			min_y = mini(min_y, yy)
			max_x = maxi(max_x, xx)
			max_y = maxi(max_y, yy)
	if max_x < min_x:
		atlas.region = full
		return atlas
	min_x = maxi(min_x - 4, 0)
	min_y = maxi(min_y - 4, 0)
	max_x = mini(max_x + 4, w - 1)
	max_y = mini(max_y + 4, h - 1)
	atlas.region = Rect2(float(min_x), float(min_y), float(max_x - min_x + 1), float(max_y - min_y + 1))
	return atlas


func _load_ladder_tex_by_index(idx: int) -> Texture2D:
	var available: Array[String] = []
	for p in LADDER_PATHS:
		if ResourceLoader.exists(p):
			available.append(p)
	if available.is_empty():
		return null
	var path: String = available[idx % available.size()]
	return load(path) as Texture2D


func get_climb_center_x() -> float:
	return global_position.x


func get_climb_half_width() -> float:
	return _hit_w * 0.5


func get_climb_top_y() -> float:
	return _logical_top_y


func get_climb_bottom_y() -> float:
	return _logical_bottom_y
