extends CanvasLayer
## 屏幕固定 HUD：用 _draw 强制缩放到固定尺寸，避免 512/1024 原图像素撑爆屏幕

@export var margin := Vector2(20, 10)  # 血条起点位置保持不变
@export var bar_width: float = 162.0  # 长度
@export var bar_height: float = 115.2  # 蓝条宽度（上下）
@export var hp_bar_height: float = 126.72  # 红条宽度 = 115.2 × 1.1
@export var bar_gap: float = -72.0    # 更负 → 红蓝更近

var _drawer: Control
var _hp_ratio: float = 1.0
var _mp_ratio: float = 1.0
var _hp_fill_content: Rect2
var _mp_fill_content: Rect2

var _hp_bg: Texture2D = preload("res://UI/hp_bar_bg.png")
var _hp_fill: Texture2D = preload("res://UI/hp_bar_fill.png")
var _mp_bg: Texture2D = preload("res://UI/mp_bar_bg.png")
var _mp_fill: Texture2D = preload("res://UI/mp_bar_fill.png")


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hp_fill_content = _opaque_rect(_hp_fill)
	_mp_fill_content = _opaque_rect(_mp_fill)

	_drawer = Control.new()
	_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer.draw.connect(_on_drawer_draw)
	add_child(_drawer)
	_drawer.queue_redraw()


func update_bars(current_hp: float, max_hp: float, current_mp: float, max_mp: float) -> void:
	_hp_ratio = clampf(current_hp / maxf(max_hp, 0.001), 0.0, 1.0)
	_mp_ratio = clampf(current_mp / maxf(max_mp, 0.001), 0.0, 1.0)
	if _drawer:
		_drawer.queue_redraw()


func _on_drawer_draw() -> void:
	var hp_h := hp_bar_height
	var mp_h := bar_height
	var hp_origin := margin
	var mp_origin := margin + Vector2(0, hp_h + bar_gap)
	var hp_full := Vector2(bar_width, hp_h)
	var mp_full := Vector2(bar_width, mp_h)

	_drawer.draw_texture_rect(_hp_bg, Rect2(hp_origin, hp_full), false)
	_draw_fill(_hp_fill, hp_origin, hp_full, _hp_fill_content, _hp_ratio)

	_drawer.draw_texture_rect(_mp_bg, Rect2(mp_origin, mp_full), false)
	_draw_fill(_mp_fill, mp_origin, mp_full, _mp_fill_content, _mp_ratio)


## 只裁切贴图里真正有颜色的那一段，血量才会跟红条长度对齐
func _draw_fill(tex: Texture2D, origin: Vector2, full: Vector2, content: Rect2, ratio: float) -> void:
	if tex == null or ratio <= 0.001 or content.size.x <= 0.5:
		return
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	if tw < 1.0 or th < 1.0:
		return
	var dest := Rect2(
		origin.x + content.position.x / tw * full.x,
		origin.y + content.position.y / th * full.y,
		content.size.x / tw * full.x * ratio,
		content.size.y / th * full.y
	)
	var src := Rect2(content.position.x, content.position.y, content.size.x * ratio, content.size.y)
	_drawer.draw_texture_rect_region(tex, dest, src)


func _opaque_rect(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2()
	var img := tex.get_image()
	if img == null:
		return Rect2(0, 0, tex.get_width(), tex.get_height())
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var minx := w
	var miny := h
	var maxx := -1
	var maxy := -1
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.08 and (c.r + c.g + c.b) > 0.12:
				if x < minx:
					minx = x
				if y < miny:
					miny = y
				if x > maxx:
					maxx = x
				if y > maxy:
					maxy = y
	if maxx < 0:
		return Rect2(0, 0, w, h)
	return Rect2(minx, miny, maxx - minx + 1, maxy - miny + 1)
