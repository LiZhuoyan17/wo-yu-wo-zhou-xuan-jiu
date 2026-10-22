extends Area2D
## ==================== Spike（地下遗迹尖刺）====================
## 裁非黑内容 → 放大显示 → 底边对齐本地 y=visual_h（便于贴紧 Platform 顶）
## 伤害 = max(1, ceil(player.max_hp / 8))；冷却 0.5s

@export var cooldown: float = 0.5
@export var facing_up: bool = true
@export var visual_size: Vector2 = Vector2(40, 32)
@export var side_face_right: bool = true

var _cd: float = 0.0
var _ready_done: bool = false


func _ready() -> void:
	add_to_group("hazards")
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_ensure_visual_and_poly()
	_ready_done = true


func setup(facing_up_: bool = true, size: Vector2 = Vector2(40, 32), face_right: bool = true) -> void:
	facing_up = facing_up_
	visual_size = size
	side_face_right = face_right
	if _ready_done or is_inside_tree():
		_ensure_visual_and_poly()


func _ensure_visual_and_poly() -> void:
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr == null:
		spr = Sprite2D.new()
		spr.name = "Sprite2D"
		add_child(spr)

	var path := _pick_hazard_tex(not facing_up)
	var w := visual_size.x
	var h := visual_size.y
	if path != "" and ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		spr.texture = tex
		spr.centered = false
		spr.flip_v = false
		spr.flip_h = false
		spr.rotation = 0.0
		# 裁掉透明/纯黑边，只显示刺体，方便底边贴齐平台
		var info := _analyze_hazard_content(tex)
		var cw := maxf(float(info["content_w"]), 1.0)
		var ch := maxf(float(info["content_h"]), 1.0)
		spr.region_enabled = true
		spr.region_rect = Rect2(float(info["x0"]), float(info["y0"]), cw, ch)
		# 提亮，让尖刺更醒目
		spr.modulate = Color(1.55, 1.35, 1.25, 1.0)
		if facing_up:
			spr.scale = Vector2(w / cw, h / ch)
			spr.position = Vector2.ZERO
		else:
			spr.scale = Vector2(h / cw, w / ch)
			if side_face_right:
				spr.rotation_degrees = -90.0
				spr.position = Vector2(0, w)
			else:
				spr.rotation_degrees = 90.0
				spr.position = Vector2(h, 0)

	var poly := get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if poly == null:
		poly = CollisionPolygon2D.new()
		poly.name = "CollisionPolygon2D"
		add_child(poly)
	var inset := 2.0
	if facing_up:
		# 三角形感：上尖下宽，底边贴齐平台
		poly.polygon = PackedVector2Array([
			Vector2(w * 0.5, inset),
			Vector2(w - inset, h - inset),
			Vector2(inset, h - inset),
		])
	else:
		poly.polygon = PackedVector2Array([
			Vector2(inset, inset),
			Vector2(h - inset, inset),
			Vector2(h - inset, w - inset),
			Vector2(inset, w - inset),
		])


func _analyze_hazard_content(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	var tw := tex.get_width()
	var th := tex.get_height()
	var x0 := 0
	var y0 := 0
	var x1 := tw - 1
	var y1 := th - 1
	if img != null:
		if img.is_compressed():
			img = img.duplicate()
			img.decompress()
		tw = img.get_width()
		th = img.get_height()
		var first_y := -1
		var last_y := -1
		var first_x := tw
		var last_x := -1
		var step := maxi(1, tw / 128)
		for y in range(th):
			var hit := false
			for x in range(0, tw, step):
				var c := img.get_pixel(x, y)
				if c.a > 0.12 and (c.r + c.g + c.b) > 0.12:
					hit = true
					first_x = mini(first_x, x)
					last_x = maxi(last_x, x)
			if hit:
				if first_y < 0:
					first_y = y
				last_y = y
		if first_y >= 0:
			for y2 in range(first_y, last_y + 1, maxi(1, th / 64)):
				for x in range(tw):
					var c2 := img.get_pixel(x, y2)
					if c2.a > 0.12 and (c2.r + c2.g + c2.b) > 0.12:
						first_x = mini(first_x, x)
						break
				for x in range(tw - 1, -1, -1):
					var c3 := img.get_pixel(x, y2)
					if c3.a > 0.12 and (c3.r + c3.g + c3.b) > 0.12:
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


func _pick_hazard_tex(sideways: bool) -> String:
	var folder := "res://assets/tiles/hazard"
	var prefer := "hazard_ceiling_" if sideways else "hazard_ground_"
	var da := DirAccess.open(folder)
	if da == null:
		return ""
	var candidates: Array[String] = []
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if not da.current_is_dir() and fname.to_lower().ends_with(".png") and fname.begins_with(prefer):
			candidates.append(folder.path_join(fname))
		fname = da.get_next()
	da.list_dir_end()
	candidates.sort()
	if candidates.is_empty():
		return ""
	return candidates[0]


func _physics_process(delta: float) -> void:
	if _cd > 0.0:
		_cd -= delta


func _damage_amount(player: Node) -> int:
	var mh := 5
	if "max_hp" in player:
		mh = int(player.get("max_hp"))
	elif "max_health" in player:
		mh = int(player.get("max_health"))
	return maxi(1, int(ceil(float(mh) / 8.0)))


func _on_body_entered(body: Node2D) -> void:
	if _cd > 0.0:
		return
	if body == null or not body.is_in_group("player"):
		return
	if "hurt_invincible" in body and bool(body.get("hurt_invincible")):
		return
	if "is_rewinding" in body and bool(body.get("is_rewinding")):
		return
	if not body.has_method("take_player_damage"):
		return
	body.take_player_damage(_damage_amount(body))
	_cd = cooldown
