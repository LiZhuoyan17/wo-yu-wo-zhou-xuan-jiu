extends Node2D
## 关卡：Floor 碰撞覆盖出生点左右直至远景边界；碰撞体上头碰头铺 ground 图。
## 不改玩家状态机。

const ForestTiles = preload("res://levels/forest_tileset_builder.gd")
const STORY := preload("res://scripts/story_data.gd")
const PLAYER_SCENE = preload("res://Player.tscn")
const ENEMY_SCENE = preload("res://enemy.tscn")
const FOX_SCENE = preload("res://lantern_fox.tscn")
const LIGHT_ORB_SCENE = preload("res://light_orb.tscn")
const BACKDROP_SCENE = preload("res://levels/ParallaxBackdrop.tscn")
const PETALS_SCENE = preload("res://levels/PetalsParticle.tscn")
const SPIKE_SCENE = preload("res://levels/SpikeHazard.tscn")
const LIGHT_DOOR_SCENE = preload("res://levels/LightDoor.tscn")
const LADDER_ZONE_SCRIPT = preload("res://levels/ladder_zone.gd")
## 可二连跳够到的相邻板：水平空隙上限（超过则拉近）
## 理论同高跑跳：max_speed200 × 2×456/1000 ≈ 182；冲刺再加 ≈101 → 跳+扑硬上限~280
## 邻接目标收紧，保证普通跳跃可过，不必依赖飞扑
const PLATFORM_MAX_X_GAP := 88.0
## 仍过远时自动补跳板（低于理论跑跳，留余量）
const SAFE_JUMP_X := 140.0
## 超过此值视为设计错误（连跳+飞扑都危险），强制补板
const JUMP_DASH_MAX_X := 220.0
## 高度过大需架梯：两板水平重叠至少这么宽，梯子落在重叠中心
const LADDER_OVERLAP_MIN := 48.0
const LADDER_MIN_HEIGHT := 40.0

const FLOOR_TOP_Y := 256.0 ## 地板碰撞顶边（= 原 tile 行 y=8 的顶）
const FLOOR_COLL_H := 32.0 ## 碰撞体基准厚度
## Floor/Platform 贴图：提亮、细条加粗、超宽则水平切中拼接
const TERRAIN_BRIGHTEN := 1.55
const FLOOR_MIN_VISUAL_H := 48.0
const PLATFORM_MIN_VISUAL_H := 56.0
## 屋顶贴图顶端有翘角，碰撞顶边相对贴图下移，贴齐可站瓦面
## （先前 2px 仍偏高；再下移 5px → 共 7px）
const PLATFORM_COLLISION_Y_NUDGE := 7.0
const TERRAIN_THIN_ASPECT := 6.5 ## content_w/content_h 超过此值视为过细，强制加粗
## 与 player.gd 跳跃同步：一段 456 + 二段 420，g=1000 → 理论抬升≈192；留落点余量
const PLAYER_JUMP_SPEED := 456.0
const PLAYER_DOUBLE_JUMP_SPEED := 420.0
const PLAYER_GRAVITY_REF := 1000.0
const PLATFORM_LANDING_MARGIN := 12.0

@export var level_id: int = 1
@export var layout_preset: String = "tutorial"
@export var use_parallax_backdrop: bool = true
## 开发验收：仅 L1 出生点放到 LightDoor 旁，专测转场（默认关）
@export var debug_spawn_near_light_door: bool = false
@export var debug_spawn_offset_x: float = -96.0

var _ground: TileMapLayer
var _platforms: TileMapLayer
var _decor: TileMapLayer
var _floor_body: StaticBody2D
## 切中拼接后的贴图缓存 key → ImageTexture
var _terrain_stitch_cache: Dictionary = {}
## 邻接修正后的运行时布局（Floor 岛 + Platform 槽）
var _layout_ready: bool = false
var _runtime_floor_islands: Array[Vector2] = []
var _runtime_platform_specs: Array = []
## 岛链中段：不做整段 Floor，改成 scatter 跳板簇（少量）
var _design_scatter_spans: Array[Vector2] = []


func _ready() -> void:
	var lm := get_node_or_null("/root/LevelManager")
	if lm:
		lm.current_level_id = level_id

	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0

	if use_parallax_backdrop and get_node_or_null("ParallaxBackdrop") == null:
		var bg = BACKDROP_SCENE.instantiate()
		bg.name = "ParallaxBackdrop"
		add_child(bg)
		move_child(bg, 0)

	# 花瓣：最上层独立视差层（不跟屏幕 Canvas 钉死；不进背景树）
	if get_node_or_null("PetalsAtmosphere") == null:
		var petals = PETALS_SCENE.instantiate()
		petals.name = "PetalsAtmosphere"
		add_child(petals)

	_ensure_tile_layers()
	_paint_layout(layout_preset)
	call_deferred("_boot_player_at_spawn")
	if use_parallax_backdrop:
		call_deferred("_sync_backdrop_and_build_floor")
	else:
		call_deferred("_build_floor_collider_and_art", -800.0, 800.0)
	call_deferred("_sync_level_atmosphere")
	call_deferred("_try_start_prologue")


func _try_start_prologue() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var current_level := level_id
	var gm := get_node_or_null("/root/GameManager")
	if current_level != 1:
		if current_level == 2 or current_level == 3:
			if gm and gm.has_method("try_level_enemy_intro"):
				gm.try_level_enemy_intro(current_level)
		return

	var prologue: Array = STORY.get_dialogue("prologue")
	if gm and gm.has_method("arm_prologue_tutorial"):
		gm.arm_prologue_tutorial()
	var dm := get_node_or_null("/root/DialogueManager")
	if prologue.size() > 0 and dm and dm.has_method("start_dialogue"):
		dm.start_dialogue(prologue)
	elif gm and gm.has_method("maybe_start_control_tutorial"):
		gm.maybe_start_control_tutorial()


func _on_level_completed() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("run_clear_story_then_settle"):
		gm.run_clear_story_then_settle(level_id)
		return
	var story_key := "level" + str(level_id) + "_after"
	var dialogue: Array = STORY.get_dialogue(story_key)
	var dm := get_node_or_null("/root/DialogueManager")
	if dialogue.size() > 0 and dm and dm.has_method("start_dialogue"):
		dm.start_dialogue(dialogue)
		if dm.has_signal("dialogue_finished"):
			await dm.dialogue_finished
	_show_level_complete()


func _show_level_complete() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if level_id >= 5:
		if gm and gm.has_method("go_to_ending_screen"):
			gm.go_to_ending_screen()
		return
	if gm and gm.has_method("show_level_complete_after_story"):
		gm.show_level_complete_after_story()


func _sync_backdrop_and_build_floor() -> void:
	var bg := get_node_or_null("ParallaxBackdrop")
	if bg == null:
		_build_floor_collider_and_art(-800.0, 800.0)
		return

	if bg.has_method("set_horizon_from_ground_top"):
		bg.set_horizon_from_ground_top(FLOOR_TOP_Y)

	var far_w := 800.0
	if bg.has_method("get_far_strip_width"):
		far_w = maxf(float(bg.call("get_far_strip_width")), 800.0)

	var play := _level_play_span()
	var floor_left := minf(-far_w, play.x - 40.0)
	var floor_right := maxf(far_w, play.y + 80.0)
	var covered: Array[Vector2] = _build_floor_collider_and_art(floor_left, floor_right)

	var total_w := floor_right - floor_left
	if "mid_span" in bg:
		bg.set("mid_span", total_w)
	if "mid_origin_x" in bg:
		bg.set("mid_origin_x", floor_left)
	# 无 floor 贴图处去掉中景/前景（在 mid_span 设好后再蒙版重建）
	if bg.has_method("set_floor_coverage_segments"):
		bg.set_floor_coverage_segments(covered)

	print("🧱 Floor 碰撞 [", snappedf(floor_left, 0.1), ",", snappedf(floor_right, 0.1),
		"] 顶边Y=", FLOOR_TOP_Y, " 有贴图段×", covered.size())


## 返回实际铺上 floor 贴图的世界 X 区段（无图处不进蒙版 → 视差中/前景也不铺）
func _build_floor_collider_and_art(floor_left: float = 0.0, floor_right: float = 800.0) -> Array[Vector2]:
	# 先统一修正 L1–L5 的 Floor/Platform 邻接，再铺碰撞与梯子
	_prepare_level_layout()

	if _ground:
		_ground.clear()
		_ground.collision_enabled = false
	if _platforms:
		_platforms.clear()
		_platforms.collision_enabled = false

	var old := get_node_or_null("FloorBody")
	if old:
		old.free()
	var old_plat := get_node_or_null("PlatformBody")
	if old_plat:
		old_plat.free()

	_floor_body = StaticBody2D.new()
	_floor_body.name = "FloorBody"
	_floor_body.collision_layer = 1
	_floor_body.collision_mask = 0
	_floor_body.add_to_group("walls")
	add_child(_floor_body)

	var visuals := Node2D.new()
	visuals.name = "FloorVisuals"
	visuals.z_index = -1
	_floor_body.add_child(visuals)

	var textures := _load_ground_textures()
	var gaps := _stereo_abyss_gaps(floor_left, floor_right)
	var segments := _floor_segments(floor_left, floor_right, gaps)

	var covered: Array[Vector2] = []
	var floor_pieces := 0
	for seg in segments:
		var a: float = float(seg.x)
		var b: float = float(seg.y)
		if b - a < 8.0:
			continue
		var result: Dictionary = _pave_matched_strip(
			_floor_body, visuals, textures, a, b, FLOOR_TOP_Y, FLOOR_COLL_H, false
		)
		floor_pieces += int(result.get("count", 0))
		# 铺贴提前结束 / 无贴图：整段岛仍必须有碰撞（禁止看得见的地却踩空，也禁止岛定义有洞）
		_ensure_floor_segment_collision_complete(a, b, float(result.get("x_end", a)), FLOOR_TOP_Y)
		if b > a + 4.0:
			covered.append(Vector2(a, b))

	if textures.is_empty():
		print("⚠️ ground 文件夹无可用地板图——已为各岛强制生成碰撞")

	_set_markers_world(_spawn_pos_for_level(), _door_pos_for_level())
	_ensure_abyss_killzone(floor_left, floor_right)
	var plat_pieces := _paint_stereo_platforms(floor_left, floor_right, gaps)
	_spawn_level_entities()

	# 地板铺完后再钉一次出生（L3 = 第一座岛开头）
	_boot_player_at_spawn()

	print("🧱 地板块 ×", floor_pieces, " 平台块 ×", plat_pieces,
		" 深渊缺口 ×", gaps.size(),
		" Floor岛 ×", _stereo_floor_islands().size(),
		" 有贴图段 ×", covered.size(),
		" 范围 [", snappedf(floor_left, 0.1), ",", snappedf(floor_right, 0.1), "]")
	_verify_floor_and_platform_art(floor_pieces, plat_pieces, gaps)
	_audit_terrain_art_vs_collision()
	return covered


## Floor 岛 [a,b]：若铺贴未覆盖到 b，为缺口补实心碰撞（高度取地板最小可视高）
func _ensure_floor_segment_collision_complete(a: float, b: float, paved_end: float, top_y: float) -> void:
	if _floor_body == null or b - a < 8.0:
		return
	var h := maxf(FLOOR_COLL_H, FLOOR_MIN_VISUAL_H)
	# 完全没铺上：整段补碰撞
	if paved_end <= a + 2.0:
		_add_box_collision(_floor_body, a, b, top_y, h, false)
		push_warning("⚠️ Floor 岛 [%.1f,%.1f] 无贴图铺贴——已整段补碰撞" % [a, b])
		return
	# 铺到一半：只补尾段
	if paved_end < b - 4.0:
		_add_box_collision(_floor_body, paved_end, b, top_y, h, false)
		push_warning("⚠️ Floor 岛 [%.1f,%.1f] 贴图只铺到 %.1f——已补尾段碰撞" % [a, b, paved_end])


func _add_box_collision(
	body: StaticBody2D, x0: float, x1: float, top_y: float, height: float, one_way: bool
) -> void:
	var w := x1 - x0
	if body == null or w < 4.0:
		return
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(w, height)
	cs.shape = rect
	cs.position = Vector2(x0 + w * 0.5, top_y + height * 0.5)
	if one_way:
		cs.one_way_collision = true
		cs.one_way_collision_margin = 4.0
	cs.disabled = false
	body.add_child(cs)


## Floor / Platform 贴图硬自检（违反 scenery 规则即报错）
func _verify_floor_and_platform_art(floor_pieces: int, plat_pieces: int, gaps: Array[Vector2]) -> void:
	if floor_pieces <= 0:
		push_error("❌ Floor 无贴图块（有碰撞必须有 ground 贴图）")
	var floor_vis := get_node_or_null("FloorBody/FloorVisuals")
	if floor_vis and floor_vis.get_child_count() <= 0:
		push_error("❌ FloorVisuals 子节点为空——地板贴图丢失")
	var specs := _platform_specs_for_level(gaps)
	var expect := _count_valid_platform_slots(specs)
	if specs.size() > 0 and plat_pieces <= 0:
		push_error("❌ Platform 有槽位但贴图块=0（必须贴 platform/ 美术）")
	var plat_body := get_node_or_null("PlatformBody")
	var plat_vis := get_node_or_null("PlatformBody/PlatformVisuals")
	if expect > 0 and plat_body == null:
		push_error("❌ 缺少 PlatformBody——平台碰撞未生成")
	elif expect > 0:
		var coll_n := _count_platform_colliders(plat_body)
		if coll_n < expect:
			push_error("❌ Platform 碰撞自检失败：槽位×", expect, " 碰撞×", coll_n)
		else:
			print("✅ Platform 碰撞自检 槽位×", expect, " 碰撞×", coll_n)
	if expect > 0 and (plat_vis == null or plat_vis.get_child_count() <= 0):
		push_error("❌ PlatformVisuals 无 Sprite——平台贴图丢失")
	else:
		print("✅ 地形贴图自检 Floor×", floor_pieces, " Platform×", plat_pieces)


## 硬核自检：禁止「只有贴图没有碰撞」；并报告「有碰撞无贴图」
func _audit_terrain_art_vs_collision() -> void:
	var art_no_col := 0
	var col_no_art := 0
	var checked_art := 0

	# --- Floor ---
	var floor_body := get_node_or_null("FloorBody") as StaticBody2D
	var floor_vis := get_node_or_null("FloorBody/FloorVisuals") as Node2D
	var floor_cols: Array = _collect_collision_spans(floor_body)
	if floor_vis:
		for c in floor_vis.get_children():
			if not (c is Sprite2D):
				continue
			checked_art += 1
			var span := _sprite_world_x_span(c as Sprite2D)
			if not _span_covered_by_any_collision(span, floor_cols, 6.0):
				art_no_col += 1
				push_error("❌ Floor 贴图无碰撞 x≈[%.1f,%.1f]" % [span.x, span.y])
	# 岛定义必须被碰撞覆盖
	for isl in _stereo_floor_islands():
		var a := float(isl.x)
		var b := float(isl.y)
		if b - a < 8.0:
			continue
		if not _span_covered_by_any_collision(Vector2(a, b), floor_cols, 10.0):
			# 再强制补一整段，杜绝踩空
			_add_box_collision(floor_body, a, b, FLOOR_TOP_Y, maxf(FLOOR_COLL_H, FLOOR_MIN_VISUAL_H), false)
			push_error("❌ Floor 岛 [%.1f,%.1f] 碰撞未盖满——已强制补碰撞" % [a, b])
			floor_cols = _collect_collision_spans(floor_body)

	# --- Platform：硬规则——有贴图必须有同尺寸碰撞（按 2D 矩形配对，禁止只比 X）---
	var plat_root := get_node_or_null("PlatformBody")
	var plat_vis := get_node_or_null("PlatformBody/PlatformVisuals") as Node2D
	if plat_root and plat_vis:
		_rebuild_all_platform_collisions_from_sprites(plat_root, plat_vis)
	var plat_fix := _ensure_platform_sprites_have_matching_collisions(plat_root, plat_vis)
	if plat_fix > 0:
		push_error("❌ Platform 贴图缺/错碰撞——已按贴图尺寸强制补齐 ×", plat_fix)
	var plat_cols: Array = _collect_collision_spans_from_platform_root(plat_root)
	if plat_vis:
		for c2 in plat_vis.get_children():
			if not (c2 is Sprite2D):
				continue
			checked_art += 1
			var art_r := _sprite_local_rect(c2 as Sprite2D)
			if not _platform_art_has_exact_collision(plat_root, art_r, 2.5):
				art_no_col += 1
				_add_platform_piece_body(plat_root, art_r.position.x, art_r.position.y, art_r.size.x, art_r.size.y, c2 as Sprite2D)
				push_error("❌ Platform 贴图无同尺寸碰撞——已现场补齐 rect≈[%.1f,%.1f] %.1f×%.1f" % [
					art_r.position.x, art_r.position.y, art_r.size.x, art_r.size.y
				])
	# 每个有效槽位必须有碰撞（兜底）
	var specs: Array = _platform_specs_for_level([])
	_ensure_all_platform_specs_have_collision(plat_root, specs)
	plat_cols = _collect_collision_spans_from_platform_root(plat_root)

	# 碰撞块附近是否有贴图（有碰撞无贴图 = 隐形台，也报）
	col_no_art += _count_collisions_without_nearby_art(floor_cols, floor_vis, 24.0)
	col_no_art += _count_collisions_without_nearby_art(plat_cols, plat_vis, 24.0)
	if col_no_art > 0:
		push_warning("⚠️ 有碰撞但附近无贴图 ×", col_no_art, "（隐形台/补碰撞残留）")

	if art_no_col == 0:
		print("✅ 贴图↔碰撞配对自检 通过（检查贴图×", checked_art, "；Platform 强制同尺寸）")
	else:
		push_error("❌ 贴图↔碰撞配对失败：有图无碰撞/尺寸不符 ×", art_no_col)


func _collect_collision_spans(body: StaticBody2D) -> Array:
	var out: Array = [] ## Vector2(x0,x1) in body local
	if body == null:
		return out
	for c in body.get_children():
		if not (c is CollisionShape2D):
			continue
		var cs := c as CollisionShape2D
		if cs.disabled or not (cs.shape is RectangleShape2D):
			continue
		var rect := cs.shape as RectangleShape2D
		var half_w := rect.size.x * 0.5
		var cx := cs.position.x
		out.append(Vector2(cx - half_w, cx + half_w))
	return out


func _sprite_world_x_span(spr: Sprite2D) -> Vector2:
	# FloorVisuals/PlatformVisuals 下 sprite.position 为本地，与 collision 同空间
	var r := _sprite_local_rect(spr)
	return Vector2(r.position.x, r.position.x + r.size.x)


## Sprite 本地矩形（centered=false：左上角 = position；尺寸 = 贴图像素 × scale）
func _sprite_local_rect(spr: Sprite2D) -> Rect2:
	if spr.has_meta("plat_w") and spr.has_meta("plat_h"):
		return Rect2(
			spr.position.x,
			spr.position.y,
			float(spr.get_meta("plat_w")),
			float(spr.get_meta("plat_h"))
		)
	var w := 8.0
	var h := 8.0
	if spr.texture:
		if spr.region_enabled:
			w = maxf(spr.region_rect.size.x * absf(spr.scale.x), 4.0)
			h = maxf(spr.region_rect.size.y * absf(spr.scale.y), 4.0)
		else:
			w = maxf(float(spr.texture.get_width()) * absf(spr.scale.x), 4.0)
			h = maxf(float(spr.texture.get_height()) * absf(spr.scale.y), 4.0)
	return Rect2(spr.position.x, spr.position.y, w, h)


func _collision_local_rect(cs: CollisionShape2D) -> Rect2:
	if cs == null or not (cs.shape is RectangleShape2D):
		return Rect2()
	var sz := (cs.shape as RectangleShape2D).size
	return Rect2(cs.position.x - sz.x * 0.5, cs.position.y - sz.y * 0.5, sz.x, sz.y)


## 碰撞与贴图同位置、同宽高（容差 tol 像素）
func _collision_matches_art_size(cs: CollisionShape2D, art: Rect2, tol: float) -> bool:
	var cr := _collision_local_rect(cs)
	if cr.size.x < 1.0 or art.size.x < 1.0:
		return false
	return (
		absf(cr.position.x - art.position.x) <= tol
		and absf(cr.position.y - art.position.y) <= tol
		and absf(cr.size.x - art.size.x) <= tol
		and absf(cr.size.y - art.size.y) <= tol
	)


## 找覆盖该贴图的平台碰撞（必须同顶边 Y，禁止跨高度误配）
func _find_platform_collision_for_art(root: Node, art: Rect2) -> CollisionShape2D:
	if root == null or art.size.x < 1.0:
		return null
	var best: CollisionShape2D = null
	var best_ov := -1.0
	for rect_info in _iter_platform_collision_shapes(root):
		var cs: CollisionShape2D = rect_info["cs"]
		var cr: Rect2 = rect_info["rect"]
		if absf(cr.position.y - art.position.y) > 4.0:
			continue
		var ov := minf(art.position.x + art.size.x, cr.position.x + cr.size.x) - maxf(art.position.x, cr.position.x)
		if ov >= art.size.x * 0.55 and ov > best_ov:
			best_ov = ov
			best = cs
	return best


func _iter_platform_collision_shapes(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if c is CollisionShape2D:
			var cs := c as CollisionShape2D
			if cs.disabled or not (cs.shape is RectangleShape2D):
				continue
			out.append({"cs": cs, "rect": _collision_local_rect(cs)})
		elif c is StaticBody2D:
			var body := c as StaticBody2D
			for c2 in body.get_children():
				if not (c2 is CollisionShape2D):
					continue
				var cs2 := c2 as CollisionShape2D
				if cs2.disabled or not (cs2.shape is RectangleShape2D):
					continue
				var r := _collision_local_rect(cs2)
				r.position += body.position
				out.append({"cs": cs2, "rect": r})
	return out


func _platform_art_has_exact_collision(root: Node, art: Rect2, tol: float) -> bool:
	var expect_top := art.position.y + PLATFORM_COLLISION_Y_NUDGE
	for rect_info in _iter_platform_collision_shapes(root):
		var cr: Rect2 = rect_info["rect"]
		if (
			absf(cr.position.x - art.position.x) <= tol
			and absf(cr.position.y - expect_top) <= tol
			and absf(cr.size.x - art.size.x) <= tol
			and absf(cr.size.y - art.size.y) <= tol
		):
			return true
	return false


func _collect_collision_spans_from_platform_root(root: Node) -> Array:
	var out: Array = []
	for r in _collect_platform_collision_rects(root):
		out.append(Vector2(float(r.position.x), float(r.position.x) + float(r.size.x)))
	return out


## 硬保证：每张 Platform 贴图都有同尺寸 One-Way 碰撞；尺寸不符则按贴图重建
func _ensure_platform_sprites_have_matching_collisions(root: Node, visuals: Node2D) -> int:
	if root == null or visuals == null:
		return 0
	var fixed := 0
	for c in visuals.get_children():
		if not (c is Sprite2D):
			continue
		var art := _sprite_local_rect(c as Sprite2D)
		if art.size.x < 2.0 or art.size.y < 2.0:
			continue
		if _platform_art_has_exact_collision(root, art, 2.5):
			continue
		_add_platform_piece_body(root, art.position.x, art.position.y, art.size.x, art.size.y, c as Sprite2D)
		fixed += 1
		push_warning("⚠️ 已为 Platform 贴图补同尺寸碰撞 [%.1f,%.1f] %.1f×%.1f" % [
			art.position.x, art.position.y, art.size.x, art.size.y
		])
	return fixed


func _span_covered_by_any_collision(span: Vector2, cols: Array, pad: float) -> bool:
	var a := span.x + pad
	var b := span.y - pad
	if b <= a:
		a = span.x
		b = span.y
	for col in cols:
		var c0: float = float(col.x)
		var c1: float = float(col.y)
		# 贴图跨度大部分落在某碰撞内，或与碰撞显著重叠
		var ov := minf(b, c1) - maxf(a, c0)
		if ov >= (b - a) * 0.55:
			return true
		if a >= c0 - 2.0 and b <= c1 + 2.0:
			return true
	return false


func _count_collisions_without_nearby_art(cols: Array, visuals: Node2D, pad: float) -> int:
	if visuals == null or cols.is_empty():
		return 0
	var art_spans: Array = []
	for c in visuals.get_children():
		if c is Sprite2D:
			art_spans.append(_sprite_world_x_span(c as Sprite2D))
	var n := 0
	for col in cols:
		var c0: float = float(col.x)
		var c1: float = float(col.y)
		var mid := (c0 + c1) * 0.5
		var ok := false
		for art in art_spans:
			var a0: float = float(art.x) - pad
			var a1: float = float(art.y) + pad
			if mid >= a0 and mid <= a1:
				ok = true
				break
			if minf(c1, a1) - maxf(c0, a0) > 8.0:
				ok = true
				break
		if not ok:
			n += 1
	return n


## 关卡内容水平跨度（用于拉长 Floor 范围，保证门岛在界内）
func _level_play_span() -> Vector2:
	var islands := _stereo_floor_islands()
	if islands.is_empty():
		return Vector2(0.0, 1400.0)
	var x0 := float(islands[0].x)
	var x1 := float(islands[0].y)
	for isl in islands:
		x0 = minf(x0, float(isl.x))
		x1 = maxf(x1, float(isl.y))
	return Vector2(x0, x1)


func _spawn_pos_for_level() -> Vector2:
	# 专测转场：仅 L1 出生在门旁；钳在门岛内，禁止落深渊
	if debug_spawn_near_light_door and level_id == 1:
		var islands := _stereo_floor_islands()
		if not islands.is_empty():
			var last: Vector2 = islands[islands.size() - 1]
			var a: float = float(last.x)
			var b: float = float(last.y)
			var door_x := (a + b) * 0.5
			var sx := clampf(door_x + debug_spawn_offset_x, a + 24.0, b - 24.0)
			return Vector2(sx, FLOOR_TOP_Y - 32.0)
		var door_p := _door_pos_for_level()
		return Vector2(door_p.x + debug_spawn_offset_x, door_p.y)
	var islands2 := _stereo_floor_islands()
	if islands2.is_empty():
		return Vector2(64.0, FLOOR_TOP_Y - 32.0)
	var a2: float = float(islands2[0].x)
	var b2: float = float(islands2[0].y)
	# L3 / L4：出生钉在第一座 Floor 岛开头（左缘内一点）
	if level_id == 3 or level_id == 4:
		var sx_start := clampf(a2 + 32.0, a2 + 16.0, b2 - 24.0)
		return Vector2(sx_start, FLOOR_TOP_Y - 32.0)
	# 其它关：岛心留边距
	var sx2 := clampf((a2 + b2) * 0.5, a2 + 32.0, b2 - 32.0)
	return Vector2(sx2, FLOOR_TOP_Y - 32.0)


func _door_pos_for_level() -> Vector2:
	var islands := _stereo_floor_islands()
	if islands.is_empty():
		return Vector2(1200.0, FLOOR_TOP_Y - 32.0)
	var last: Vector2 = islands[islands.size() - 1]
	var a: float = float(last.x)
	var b: float = float(last.y)
	var dx := clampf((a + b) * 0.5, a + 32.0, b - 32.0)
	return Vector2(dx, FLOOR_TOP_Y - 32.0)


## 碎岛 Floor：优先返回邻接修正后的运行时岛
func _stereo_floor_islands() -> Array[Vector2]:
	if _layout_ready and not _runtime_floor_islands.is_empty():
		return _runtime_floor_islands
	return _raw_floor_islands()


func _raw_floor_islands() -> Array[Vector2]:
	_design_scatter_spans.clear()
	match level_id:
		1:
			return _build_level1_islands()
		2:
			return _build_level2_islands()
		3:
			return _build_level3_islands()
		4:
			return _build_level4_islands()
		5:
			return _build_level5_islands()
		_:
			return [Vector2(0, 200), Vector2(400, 520)]


## 生成并缓存修正后的 Floor + Platform（全关通用）
## Floor 与 Platform 视为同一类可站立表面：先按设计生成，再统一邻接修正
func _prepare_level_layout() -> void:
	_layout_ready = false
	_runtime_floor_islands.clear()
	_runtime_platform_specs.clear()

	# 先用原始岛生成板（不要先压缩 Floor，否则 L1 深渊被捏扁、板无处可放）
	var islands: Array[Vector2] = _raw_floor_islands()
	_runtime_floor_islands = islands
	_layout_ready = true

	var plats: Array = _build_raw_platform_specs()
	plats = _clamp_air_platform_specs(plats)

	# 再把 Floor+Platform 当成一类，按中心 X 串成链做邻接修正
	var pair: Dictionary = _normalize_all_surface_adjacencies(_runtime_floor_islands, plats)
	_runtime_floor_islands = pair["islands"]
	_runtime_platform_specs = pair["plats"]
	# 仍超安全跳距 / 跳+扑距 → 自动塞跳板，再归一化一次
	var filled: Array = _bridge_unreachable_gaps(_runtime_floor_islands, _runtime_platform_specs)
	if filled.size() != _runtime_platform_specs.size():
		_runtime_platform_specs = filled
		pair = _normalize_all_surface_adjacencies(_runtime_floor_islands, _runtime_platform_specs)
		_runtime_floor_islands = pair["islands"]
		_runtime_platform_specs = pair["plats"]
	_layout_ready = true
	_audit_surface_adjacencies(_runtime_floor_islands, _runtime_platform_specs)


func _build_raw_platform_specs() -> Array:
	var ft := FLOOR_TOP_Y
	# 全关统一：按 Floor 岛间隙生成 hop / 高空桥 / 地下道（梯子交替）
	match level_id:
		1, 2, 3, 4, 5:
			return _build_gap_routed_platform_specs(ft)
		_:
			return [[192.0, 320.0, ft - 64.0]]


## L1：开头地面加长 3 倍方便教学试玩；其后岛整体右移，跳跃间隙不变
## ⑤ 做成 scatter 跳板岛（非整段 Floor）
func _build_level1_islands() -> Array[Vector2]:
	const START_W := 280.0
	const START_SCALE := 3.0
	const SHIFT := START_W * (START_SCALE - 1.0) ## 560：后面所有岛右移这么多
	_design_scatter_spans.append(Vector2(1900.0 + SHIFT, 2140.0 + SHIFT))
	return [
		Vector2(0.0, START_W * START_SCALE), ## 0~840 练习地面
		Vector2(420.0 + SHIFT, 560.0 + SHIFT),
		Vector2(640.0 + SHIFT, 760.0 + SHIFT),
		Vector2(860.0 + SHIFT, 1000.0 + SHIFT),
		Vector2(1280.0 + SHIFT, 1560.0 + SHIFT),
		## ⑤ → scatter span
		Vector2(2520.0 + SHIFT, 2780.0 + SHIFT),
		Vector2(3000.0 + SHIFT, 3140.0 + SHIFT),
		Vector2(3320.0 + SHIFT, 3600.0 + SHIFT),
		Vector2(3920.0 + SHIFT, 4240.0 + SHIFT),
	]


func _build_level2_islands() -> Array[Vector2]:
	var out: Array[Vector2] = []
	const END_X := 9200.0
	const MIN_ISLAND_W := 260.0
	const LONG_GAP_FROM := 280.0
	const LONG_GAP_SCALE := 0.8
	out.append(Vector2(0.0, 400.0))
	var x := 400.0
	var beats: Array[Vector2] = [
		Vector2(200.0, 280.0),
		Vector2(480.0, 340.0),
		Vector2(150.0, 260.0),
		Vector2(140.0, 300.0),
		Vector2(560.0, 320.0),
		Vector2(260.0, 380.0),
		Vector2(360.0, 280.0),
		Vector2(180.0, 260.0),
		Vector2(520.0, 340.0),
		Vector2(130.0, 300.0),
		Vector2(110.0, 280.0),
		Vector2(640.0, 300.0),
		Vector2(240.0, 400.0),
		Vector2(400.0, 280.0),
		Vector2(320.0, 320.0),
		Vector2(170.0, 280.0),
		Vector2(480.0, 340.0),
	]
	var mid_n := 0
	for beat in beats:
		var gap: float = float(beat.x)
		if gap >= LONG_GAP_FROM:
			gap *= LONG_GAP_SCALE
		var w: float = maxf(float(beat.y), MIN_ISLAND_W)
		x += gap
		if x + w > END_X - 480.0:
			break
		mid_n += 1
		# 约每 3 个中段岛抽 1 个 → scatter 跳板岛（不要太多）
		if (mid_n % 3) == 0:
			_design_scatter_spans.append(Vector2(x, x + w))
		else:
			out.append(Vector2(x, x + w))
		x += w
	out.append(Vector2(x + 280.0, x + 620.0))
	return out


## L3：加长约 3 倍；坑型轮换 hop / scatter / terrace / 岛链（宽坑 over·under）
func _build_level3_islands() -> Array[Vector2]:
	return _build_beats_islands(
		380.0,
		[
			# —— 前段：短 hop + 中 scatter ——
			Vector2(150.0, 280.0), Vector2(280.0, 300.0), Vector2(160.0, 260.0),
			Vector2(420.0, 320.0), Vector2(180.0, 280.0), Vector2(240.0, 300.0),
			Vector2(500.0, 340.0), ## 宽 → 岛链梯
			Vector2(170.0, 280.0), Vector2(300.0, 300.0), Vector2(140.0, 260.0),
			# —— 中前：terrace/scatter 穿插 ——
			Vector2(260.0, 300.0), Vector2(480.0, 320.0), Vector2(190.0, 280.0),
			Vector2(220.0, 300.0), Vector2(560.0, 340.0), Vector2(160.0, 280.0),
			Vector2(340.0, 300.0), Vector2(150.0, 260.0), Vector2(400.0, 320.0),
			# —— 中段长途 ——
			Vector2(180.0, 300.0), Vector2(520.0, 360.0), Vector2(200.0, 280.0),
			Vector2(280.0, 300.0), Vector2(170.0, 260.0), Vector2(460.0, 340.0),
			Vector2(190.0, 300.0), Vector2(320.0, 300.0), Vector2(600.0, 360.0),
			Vector2(160.0, 280.0), Vector2(250.0, 300.0), Vector2(180.0, 280.0),
			# —— 后段加压 ——
			Vector2(440.0, 320.0), Vector2(150.0, 260.0), Vector2(300.0, 300.0),
			Vector2(540.0, 340.0), Vector2(200.0, 280.0), Vector2(280.0, 300.0),
			Vector2(160.0, 260.0), Vector2(480.0, 340.0), Vector2(190.0, 300.0),
			Vector2(360.0, 320.0), Vector2(170.0, 280.0), Vector2(580.0, 360.0),
			Vector2(210.0, 300.0), Vector2(260.0, 280.0), Vector2(420.0, 320.0),
		],
		15600.0
	)


## L4：宽跳渊与梯路由穿插
func _build_level4_islands() -> Array[Vector2]:
	return _build_beats_islands(
		320.0,
		[
			Vector2(180.0, 280.0), Vector2(500.0, 300.0), Vector2(160.0, 260.0),
			Vector2(280.0, 280.0), Vector2(560.0, 320.0), Vector2(200.0, 300.0),
			Vector2(440.0, 280.0), Vector2(600.0, 340.0), Vector2(170.0, 280.0),
			Vector2(480.0, 320.0),
		],
		5600.0
	)


## L5：密短跳 + 若干宽渊（尖刺挂在空中跳板上）
func _build_level5_islands() -> Array[Vector2]:
	return _build_beats_islands(
		280.0,
		[
			Vector2(140.0, 260.0), Vector2(160.0, 260.0), Vector2(420.0, 280.0),
			Vector2(130.0, 260.0), Vector2(500.0, 300.0), Vector2(150.0, 280.0),
			Vector2(180.0, 260.0), Vector2(380.0, 260.0), Vector2(560.0, 320.0),
			Vector2(200.0, 280.0), Vector2(460.0, 300.0), Vector2(240.0, 280.0),
		],
		6200.0
	)


## beats: [gap, island_w]；出生宽 + 门岛；约每 3 个中段岛抽 1 个做 scatter
func _build_beats_islands(spawn_w: float, beats: Array[Vector2], end_x: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	const MIN_ISLAND_W := 240.0
	const LONG_GAP_FROM := 280.0
	const LONG_GAP_SCALE := 0.85
	out.append(Vector2(0.0, spawn_w))
	var x := spawn_w
	var mid_n := 0
	for beat in beats:
		var gap: float = float(beat.x)
		if gap >= LONG_GAP_FROM:
			gap *= LONG_GAP_SCALE
		var w: float = maxf(float(beat.y), MIN_ISLAND_W)
		x += gap
		if x + w > end_x - 400.0:
			break
		mid_n += 1
		if (mid_n % 3) == 0:
			_design_scatter_spans.append(Vector2(x, x + w))
		else:
			out.append(Vector2(x, x + w))
		x += w
	out.append(Vector2(x + 240.0, x + 560.0))
	return out


## 由 Floor 岛反推深渊缺口（岛外全部挖空）
func _stereo_abyss_gaps(floor_left: float, floor_right: float) -> Array[Vector2]:
	var islands := _stereo_floor_islands()
	islands.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var gaps: Array[Vector2] = []
	var cursor := floor_left
	for isl in islands:
		var a := maxf(float(isl.x), floor_left)
		var b := minf(float(isl.y), floor_right)
		if a > cursor + 8.0:
			gaps.append(Vector2(cursor, a))
		cursor = maxf(cursor, b)
	if floor_right > cursor + 8.0:
		gaps.append(Vector2(cursor, floor_right))
	return gaps


func _floor_segments(floor_left: float, floor_right: float, gaps: Array[Vector2]) -> Array[Vector2]:
	# 优先直接用岛定义（避免浮点缝）；若无岛则回退缺口切割
	var islands := _stereo_floor_islands()
	if not islands.is_empty():
		var segs: Array[Vector2] = []
		for isl in islands:
			var a := maxf(float(isl.x), floor_left)
			var b := minf(float(isl.y), floor_right)
			if b - a >= 8.0:
				segs.append(Vector2(a, b))
		if not segs.is_empty():
			return segs
	var cuts: Array[Vector2] = gaps.duplicate()
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var segs2: Array[Vector2] = []
	var cursor := floor_left
	for g in cuts:
		var gl: float = maxf(float(g.x), floor_left)
		var gr: float = minf(float(g.y), floor_right)
		if gl > cursor + 4.0:
			segs2.append(Vector2(cursor, gl))
		cursor = maxf(cursor, gr)
	if floor_right > cursor + 4.0:
		segs2.append(Vector2(cursor, floor_right))
	if segs2.is_empty():
		segs2.append(Vector2(floor_left, floor_right))
	return segs2


## 悬浮 + 地下平台：必须贴 platform/ 美术图 + One-Way（禁止绿块）
## 贴图缺失时仍强制为每个槽位生成碰撞，禁止“看得见踩空”
func _paint_stereo_platforms(_floor_left: float, _floor_right: float, gaps: Array[Vector2]) -> int:
	var textures := _load_platform_textures()
	if textures.is_empty():
		push_error("❌ platform/ 贴图加载失败——仍会生成碰撞。请检查 res://assets/tiles/platform/")

	var old_plat := get_node_or_null("PlatformBody")
	if old_plat:
		old_plat.free()

	# 容器用 Node2D：每块平台是独立 StaticBody2D（贴图+碰撞绑死，禁止有图无碰撞）
	var root := Node2D.new()
	root.name = "PlatformBody"
	root.z_index = 2
	add_child(root)

	var visuals := Node2D.new()
	visuals.name = "PlatformVisuals"
	visuals.z_index = 2
	root.add_child(visuals)

	var pieces := 0
	var tex_i := 0
	var specs: Array = _platform_specs_for_level(gaps)
	for s in specs:
		var tex: Texture2D = null
		if not textures.is_empty():
			tex = textures[tex_i % textures.size()]
			tex_i += 1
		pieces += _place_one_platform_art(
			root, visuals, tex, float(s[0]), float(s[1]), float(s[2])
		)

	# 铁律：按现有贴图强制重建碰撞（有图必有同尺寸碰撞）
	var rebuilt := _rebuild_all_platform_collisions_from_sprites(root, visuals)
	print("🪵 Platform 按贴图重建碰撞 ×", rebuilt)

	# 无贴图的槽位仍须可踩
	_ensure_all_platform_specs_have_collision(root, specs)

	if level_id >= 5:
		_spawn_gauntlet_spikes(specs)

	var coll_final := _count_platform_colliders(root)
	var expect := _count_valid_platform_slots(specs)
	var spr_n := 0
	for c in visuals.get_children():
		if c is Sprite2D:
			spr_n += 1
	if coll_final < spr_n:
		push_error("❌ Platform 碰撞仍少于贴图：贴图×", spr_n, " 碰撞×", coll_final)
	elif coll_final < expect:
		push_error("❌ Platform 碰撞自检失败 L", level_id, " 槽位×", expect, " 碰撞×", coll_final)
	else:
		print("✅ Platform 碰撞自检 L", level_id, " 槽位×", expect, " 贴图×", spr_n, " 碰撞×", coll_final)

	var ladder_n := _spawn_ladders_for_tall_gaps(specs)

	print("🪵 L", level_id, " 平台美术块 ×", pieces, "/", specs.size(),
		" 碰撞×", coll_final, " 梯子×", ladder_n,
		" 贴图池×", textures.size(), " 最大抬升≤", snappedf(_max_air_platform_rise(), 0.1))
	return pieces


## 架梯规则（台子 = Floor ∪ Platform）：
## 1) 每根梯子只连接「上台 → 正下方最近一台」——向下进通道 / 向上上高塔皆可
## 2) 高差 > 二连跳抬升，且水平重叠 ≥ LADDER_OVERLAP_MIN
## 3) 柱心不得穿过第三块台；重叠放在岛缘或中层↔高塔，避免挡路
func _spawn_ladders_for_tall_gaps(plat_specs: Array) -> int:
	for c in get_children():
		if c is Node and String(c.name).begins_with("LevelLadder_"):
			c.free()

	var surfaces: Array = [] ## {x0,x1,top}
	for isl in _stereo_floor_islands():
		surfaces.append({"x0": float(isl.x), "x1": float(isl.y), "top": FLOOR_TOP_Y})
	for s in plat_specs:
		surfaces.append({"x0": float(s[0]), "x1": float(s[1]), "top": float(s[2])})

	var max_rise := _max_air_platform_rise()
	var placed := 0

	for i in range(surfaces.size()):
		var upper: Dictionary = surfaces[i]
		var u0: float = float(upper["x0"])
		var u1: float = float(upper["x1"])
		var ut: float = float(upper["top"])

		# 在所有与上台水平重叠、且顶边更低的台子里，取「最近下方」那一块
		var best_j := -1
		var best_top := INF
		for j in range(surfaces.size()):
			if j == i:
				continue
			var cand: Dictionary = surfaces[j]
			var ct: float = float(cand["top"])
			if ct <= ut + 1.0:
				continue
			var ov0 := maxf(u0, float(cand["x0"]))
			var ov1 := minf(u1, float(cand["x1"]))
			if ov1 - ov0 < LADDER_OVERLAP_MIN:
				continue
			if ct < best_top:
				best_top = ct
				best_j = j

		if best_j < 0:
			continue
		var lower: Dictionary = surfaces[best_j]
		var lt: float = float(lower["top"])
		var hgap := lt - ut
		if hgap <= max_rise + 1.0:
			continue
		if hgap < LADDER_MIN_HEIGHT:
			continue

		var ov0b := maxf(u0, float(lower["x0"]))
		var ov1b := minf(u1, float(lower["x1"]))
		# 柱心取重叠段内侧，避免贴边导致「看得见抓不到」
		var cx := (ov0b + ov1b) * 0.5
		cx = clampf(cx, ov0b + 10.0, ov1b - 10.0)

		# 穿模检测：柱心 X 上若有第三块台顶夹在中间 → 不架
		if _ladder_pierces_third_surface(surfaces, i, best_j, cx, ut, lt):
			continue

		_place_one_ladder(cx, ut, lt, placed, minf(u1 - u0, float(lower["x1"]) - float(lower["x0"])))
		placed += 1

	if placed > 0:
		print("🪜 L", level_id, " 两台直连架梯 ×", placed, "（高差>", snappedf(max_rise, 0.1), "）")
	return placed


## 梯子柱心是否穿过第三块台子（只连两台）
func _ladder_pierces_third_surface(
	surfaces: Array, upper_i: int, lower_i: int, cx: float, top_y: float, bot_y: float
) -> bool:
	for k in range(surfaces.size()):
		if k == upper_i or k == lower_i:
			continue
		var mid: Dictionary = surfaces[k]
		var mt: float = float(mid["top"])
		if mt <= top_y + 2.0 or mt >= bot_y - 2.0:
			continue
		if float(mid["x0"]) - 4.0 <= cx and cx <= float(mid["x1"]) + 4.0:
			return true
	return false

func _horizontal_gap(a0: float, a1: float, b0: float, b1: float) -> float:
	if a1 < b0:
		return b0 - a1
	if b1 < a0:
		return a0 - b1
	return 0.0 ## 重叠


func _place_one_ladder(center_x: float, top_y: float, bottom_y: float, idx: int, max_platform_len: float = 64.0) -> void:
	var ladder := Area2D.new()
	ladder.name = "LevelLadder_%d" % idx
	ladder.set_script(LADDER_ZONE_SCRIPT)
	add_child(ladder)
	if ladder.has_method("setup"):
		# 每根梯子轮换不同 ladder_XX；显示宽仍由 ladder_zone 统一钳到同一目标宽
		var tex_i := (idx * 3 + level_id) % 9
		ladder.call("setup", center_x, top_y, bottom_y, max_platform_len, tex_i)


func _count_platform_colliders(root: Node) -> int:
	var n := 0
	if root == null:
		return 0
	for c in root.get_children():
		if c is CollisionShape2D and not (c as CollisionShape2D).disabled:
			n += 1
		elif c is StaticBody2D:
			for c2 in c.get_children():
				if c2 is CollisionShape2D and not (c2 as CollisionShape2D).disabled:
					n += 1
	return n


func _count_valid_platform_slots(specs: Array) -> int:
	var n := 0
	for s in specs:
		if float(s[1]) - float(s[0]) >= 8.0:
			n += 1
	return n


## 二连跳相对 Floor 的最大抬升（世界像素）；空中板不得超过此高度
func _max_air_platform_rise() -> float:
	var h := (
		PLAYER_JUMP_SPEED * PLAYER_JUMP_SPEED
		+ PLAYER_DOUBLE_JUMP_SPEED * PLAYER_DOUBLE_JUMP_SPEED
	) / (2.0 * PLAYER_GRAVITY_REF)
	return maxf(h - PLATFORM_LANDING_MARGIN, 64.0)


## 空中板顶边钳制：top_y >= FLOOR_TOP_Y - max_rise（地下板 top_y > Floor 不改）
## 第 4 元为 true 时视为「爬梯高塔」，允许高于二连跳（必须与下方台重叠出梯）
func _clamp_air_platform_specs(specs: Array) -> Array:
	var max_rise := _max_air_platform_rise()
	var min_top := FLOOR_TOP_Y - max_rise
	var out: Array = []
	for s in specs:
		var x0: float = float(s[0])
		var x1: float = float(s[1])
		var top: float = float(s[2])
		var ladder_tower: bool = s.size() >= 4 and bool(s[3])
		if not ladder_tower and top < FLOOR_TOP_Y and top < min_top:
			top = min_top
		out.append([x0, x1, top])
	return out


## Floor↔Floor：水平过远则拉近右侧岛（同高不重叠，保留可跳深渊）
func _normalize_floor_island_gaps(islands: Array[Vector2]) -> Array[Vector2]:
	if islands.size() < 2:
		return islands
	var arr: Array[Vector2] = []
	for isl in islands:
		arr.append(Vector2(float(isl.x), float(isl.y)))
	arr.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var pulled := 0
	for _pass in range(3):
		for i in range(arr.size() - 1):
			var a: Vector2 = arr[i]
			var b: Vector2 = arr[i + 1]
			var gap := float(b.x) - float(a.y)
			if gap > PLATFORM_MAX_X_GAP:
				var w := float(b.y) - float(b.x)
				var nx0 := float(a.y) + PLATFORM_MAX_X_GAP
				arr[i + 1] = Vector2(nx0, nx0 + w)
				pulled += 1
	if pulled > 0:
		print("📐 Floor↔Floor 拉近 ×", pulled, " 最大隙=", PLATFORM_MAX_X_GAP)
	return arr


## Floor/Platform 全组合：过远拉近；过高则造水平重叠供架梯
## 返回 { "islands": Array[Vector2], "plats": Array }
func _normalize_all_surface_adjacencies(islands: Array[Vector2], plats: Array) -> Dictionary:
	var max_rise := _max_air_platform_rise()
	# 统一表面：{x0,x1,top,kind,idx} kind 0=floor 1=plat
	var surfs: Array = []
	for i in range(islands.size()):
		var isl: Vector2 = islands[i]
		surfs.append({
			"x0": float(isl.x), "x1": float(isl.y), "top": FLOOR_TOP_Y,
			"kind": 0, "idx": i
		})
	for i in range(plats.size()):
		var s = plats[i]
		surfs.append({
			"x0": float(s[0]), "x1": float(s[1]), "top": float(s[2]),
			"kind": 1, "idx": i
		})
	surfs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (float(a["x0"]) + float(a["x1"])) * 0.5 < (float(b["x0"]) + float(b["x1"])) * 0.5
	)

	var pulled := 0
	var overlapped := 0
	for _pass in range(8):
		for i in range(surfs.size() - 1):
			var a: Dictionary = surfs[i]
			var b: Dictionary = surfs[i + 1]
			var a0: float = float(a["x0"])
			var a1: float = float(a["x1"])
			var at: float = float(a["top"])
			var b0: float = float(b["x0"])
			var b1: float = float(b["x1"])
			var bt: float = float(b["top"])
			var bw := b1 - b0
			if bw < 8.0:
				continue
			var hgap := absf(at - bt)
			var xgap := _horizontal_gap(a0, a1, b0, b1)
			if hgap > max_rise + 1.0:
				var ov_w := minf(a1, b1) - maxf(a0, b0)
				if ov_w < LADDER_OVERLAP_MIN:
					# 优先平移 Platform，尽量不动 Floor 岛
					if int(b["kind"]) == 0 and int(a["kind"]) == 1:
						var aw := a1 - a0
						var target_a1 := b0 + LADDER_OVERLAP_MIN
						a["x1"] = target_a1
						a["x0"] = target_a1 - aw
						surfs[i] = a
					else:
						var target_b0 := a1 - LADDER_OVERLAP_MIN
						b["x0"] = target_b0
						b["x1"] = target_b0 + bw
						surfs[i + 1] = b
					overlapped += 1
			else:
				if xgap > PLATFORM_MAX_X_GAP:
					# 拉近时也优先动 Platform
					if int(b["kind"]) == 0 and int(a["kind"]) == 1:
						var aw2 := a1 - a0
						var target_a12 := b0 - PLATFORM_MAX_X_GAP
						a["x1"] = target_a12
						a["x0"] = target_a12 - aw2
						surfs[i] = a
					else:
						var target_b0b := a1 + PLATFORM_MAX_X_GAP
						b["x0"] = target_b0b
						b["x1"] = target_b0b + bw
						surfs[i + 1] = b
					pulled += 1

	# 写回
	var out_islands: Array[Vector2] = islands.duplicate()
	var out_plats: Array = plats.duplicate()
	for s2 in surfs:
		var kind: int = int(s2["kind"])
		var idx: int = int(s2["idx"])
		if kind == 0:
			out_islands[idx] = Vector2(float(s2["x0"]), float(s2["x1"]))
		else:
			out_plats[idx] = [float(s2["x0"]), float(s2["x1"]), float(s2["top"])]

	if pulled > 0 or overlapped > 0:
		print("📐 全表面邻接修正 L", level_id, " 拉近×", pulled, " 造重叠(供梯)×", overlapped)
	return {"islands": out_islands, "plats": out_plats}


## 自检：列出仍违规的相邻对（仅日志）
func _audit_surface_adjacencies(islands: Array[Vector2], plats: Array) -> void:
	var max_rise := _max_air_platform_rise()
	var surfs: Array = []
	for isl in islands:
		surfs.append([float(isl.x), float(isl.y), FLOOR_TOP_Y, "F"])
	for s in plats:
		surfs.append([float(s[0]), float(s[1]), float(s[2]), "P"])
	surfs.sort_custom(func(a: Array, b: Array) -> bool:
		return (float(a[0]) + float(a[1])) * 0.5 < (float(b[0]) + float(b[1])) * 0.5
	)
	var bad_far := 0
	var bad_tall := 0
	for i in range(surfs.size() - 1):
		var a: Array = surfs[i]
		var b: Array = surfs[i + 1]
		var hgap := absf(float(a[2]) - float(b[2]))
		var xgap := _horizontal_gap(float(a[0]), float(a[1]), float(b[0]), float(b[1]))
		var ov := minf(float(a[1]), float(b[1])) - maxf(float(a[0]), float(b[0]))
		if hgap > max_rise + 1.0:
			if ov < 8.0:
				bad_tall += 1
		elif xgap > SAFE_JUMP_X + 0.5:
			bad_far += 1
	if bad_far == 0 and bad_tall == 0:
		print("✅ 邻接自检 L", level_id, " Floor×", islands.size(), " Plat×", plats.size(),
			" 跳距≤", SAFE_JUMP_X, " 跳扑硬限=", JUMP_DASH_MAX_X)
	else:
		push_warning("⚠️ 邻接自检 L%d 仍过远×%d 高差缺重叠×%d（安全跳距%.0f）" % [level_id, bad_far, bad_tall, SAFE_JUMP_X])


## 相邻台子水平距仍超过安全跳距时，在缝中自动补跳板（同高差可跳范围内）
func _bridge_unreachable_gaps(islands: Array[Vector2], plats: Array) -> Array:
	var max_rise := _max_air_platform_rise()
	var surfs: Array = []
	for isl in islands:
		surfs.append([float(isl.x), float(isl.y), FLOOR_TOP_Y])
	for s in plats:
		surfs.append([float(s[0]), float(s[1]), float(s[2])])
	surfs.sort_custom(func(a: Array, b: Array) -> bool:
		return (float(a[0]) + float(a[1])) * 0.5 < (float(b[0]) + float(b[1])) * 0.5
	)

	var added: Array = []
	for i in range(surfs.size() - 1):
		var a: Array = surfs[i]
		var b: Array = surfs[i + 1]
		var a1: float = float(a[1])
		var b0: float = float(b[0])
		var at: float = float(a[2])
		var bt: float = float(b[2])
		var hgap := absf(at - bt)
		var xgap := _horizontal_gap(float(a[0]), a1, b0, float(b[1]))
		if hgap > max_rise + 1.0:
			continue ## 过高靠梯子，不水平硬桥
		if xgap <= SAFE_JUMP_X:
			continue
		# 缝中插一块（必要时插两块），保证每段 ≤ SAFE_JUMP_X
		var span := b0 - a1
		if span < 40.0:
			continue
		var mid_y := (at + bt) * 0.5
		# 空中板钳制：不要高于 max_rise
		var min_top := FLOOR_TOP_Y - max_rise
		if mid_y < FLOOR_TOP_Y and mid_y < min_top:
			mid_y = min_top
		var pieces := 1
		if xgap > JUMP_DASH_MAX_X:
			pieces = 2
		elif xgap > SAFE_JUMP_X * 1.6:
			pieces = 2
		for p_i in range(pieces):
			var t0 := (float(p_i) + 1.0) / float(pieces + 1)
			var cx := a1 + span * t0
			var pw := 64.0
			var x0 := cx - pw * 0.5
			var x1 := cx + pw * 0.5
			# 不贴死两侧
			x0 = clampf(x0, a1 + 8.0, b0 - pw - 8.0)
			x1 = x0 + pw
			added.append([x0, x1, mid_y])

	if added.is_empty():
		return plats
	var out: Array = plats.duplicate()
	for s2 in added:
		out.append(s2)
	print("🧱 L", level_id, " 补跳板 ×", added.size(), "（安全跳距≤", SAFE_JUMP_X, " / 跳扑硬限≤", JUMP_DASH_MAX_X, "）")
	return out


func _repair_missing_platform_collisions(root: Node, specs: Array, _already: int = 0) -> void:
	_ensure_all_platform_specs_have_collision(root, specs)


## 每个有效槽位在对应顶边高度必须有碰撞覆盖
func _ensure_all_platform_specs_have_collision(root: Node, specs: Array) -> void:
	if root == null:
		return
	for s in specs:
		var x0: float = float(s[0])
		var x1: float = float(s[1])
		var top_y: float = float(s[2])
		var span_w := x1 - x0
		if span_w < 8.0:
			continue
		if _platform_range_has_collision(root, x0, x1, top_y, 6.0):
			continue
		_add_platform_piece_body(root, x0, top_y, span_w, PLATFORM_MIN_VISUAL_H, null)
		push_error("❌ Platform 槽 [%.1f,%.1f] y=%.1f 无碰撞——已补 One-Way 同尺寸体" % [x0, x1, top_y])


func _platform_range_has_collision(root: Node, x0: float, x1: float, top_y: float, tol: float) -> bool:
	var need_w := x1 - x0
	if need_w < 4.0:
		return true
	var covered := 0.0
	for rect in _collect_platform_collision_rects(root):
		if absf(float(rect.position.y) - top_y) > tol:
			continue
		var ov := minf(x1, float(rect.position.x) + float(rect.size.x)) - maxf(x0, float(rect.position.x))
		if ov > 0.0:
			covered += ov
	return covered >= need_w * 0.7


func _collect_platform_collision_rects(root: Node) -> Array:
	var out: Array = [] ## Rect2 in PlatformBody local
	if root == null:
		return out
	for c in root.get_children():
		if c is CollisionShape2D:
			var r := _collision_local_rect(c as CollisionShape2D)
			if r.size.x > 1.0:
				out.append(r)
		elif c is StaticBody2D:
			var body := c as StaticBody2D
			for c2 in body.get_children():
				if c2 is CollisionShape2D:
					var r2 := _collision_local_rect(c2 as CollisionShape2D)
					# piece body 可能有自己的 position
					r2.position += body.position
					if r2.size.x > 1.0:
						out.append(r2)
	return out


## 删光旧碰撞，按每张 Sprite 重建同尺寸 One-Way；返回碰撞数
func _rebuild_all_platform_collisions_from_sprites(root: Node, visuals: Node2D) -> int:
	if root == null or visuals == null:
		return 0
	# 清掉旧的 piece StaticBody2D / 裸 CollisionShape2D（保留 PlatformVisuals）
	var to_free: Array[Node] = []
	for c in root.get_children():
		if c == visuals:
			continue
		if c is StaticBody2D or c is CollisionShape2D:
			to_free.append(c)
	for n in to_free:
		n.free()

	var n := 0
	for c in visuals.get_children():
		if not (c is Sprite2D):
			continue
		var spr := c as Sprite2D
		var art := _sprite_local_rect(spr)
		# sprite 在 visuals 下；visuals 在 root 下且 position=0
		_add_platform_piece_body(root, art.position.x, art.position.y, art.size.x, art.size.y, spr)
		n += 1
	return n


## 一块平台：独立 StaticBody2D + 可选绑定 Sprite 元数据
func _add_platform_piece_body(
	root: Node, x: float, top_y: float, w: float, h: float, spr: Sprite2D
) -> StaticBody2D:
	if root == null or w < 2.0 or h < 2.0:
		return null
	var body := StaticBody2D.new()
	body.name = "PlatformPiece_%d" % root.get_child_count()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector2.ZERO
	body.add_to_group("walls")
	root.add_child(body)

	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(w, h)
	# 碰撞相对贴图下移 NUDGE，避免顶边悬在翘角上方
	var col_top := top_y + PLATFORM_COLLISION_Y_NUDGE
	cs.shape = rect
	cs.position = Vector2(x + w * 0.5, col_top + h * 0.5)
	cs.one_way_collision = true
	cs.one_way_collision_margin = 4.0
	cs.disabled = false
	body.add_child(cs)

	if spr != null:
		spr.set_meta("platform_piece", body.get_path())
		body.set_meta("art_rect", Rect2(x, top_y, w, h))
	return body


## 返回 Array of [x0, x1, top_y]；优先用邻接修正后的运行时结果
func _platform_specs_for_level(_gaps: Array[Vector2]) -> Array:
	if _layout_ready and not _runtime_platform_specs.is_empty():
		return _runtime_platform_specs
	return _clamp_air_platform_specs(_build_raw_platform_specs())


## ============================================================
## 全关深渊板型（混搭：跳跃渊 + 岛链梯子 + 少量 scatter 中段岛）
##   hop / scatter / terrace(少) = 纯跳跃
##   over / under / deep         = 岛缘梯子
##   _design_scatter_spans       = 岛链中间岛改成跳板簇
## ============================================================
func _build_gap_routed_platform_specs(ft: float) -> Array:
	var islands := _stereo_floor_islands()
	var specs: Array = []
	var wide_i := 0
	var ladder_i := 0
	var hop_n := 0
	var jump_n := 0
	var ladder_n := 0
	var scatter_island_n := 0
	var placed_span_keys: Dictionary = {}

	for i in range(islands.size() - 1):
		var left_end: float = float(islands[i].y)
		var right_start: float = float(islands[i + 1].x)
		var left_w := left_end - float(islands[i].x)
		var right_w := float(islands[i + 1].y) - right_start

		# 大坑内若夹着 scatter 中段岛：左渊 → 跳板岛 → 右渊
		var spans_in: Array[Vector2] = []
		for sp in _design_scatter_spans:
			var sx0 := float(sp.x)
			var sx1 := float(sp.y)
			if sx0 >= left_end - 1.0 and sx1 <= right_start + 1.0:
				spans_in.append(sp)
		spans_in.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

		var cursor := left_end
		for sp2 in spans_in:
			var counts := _gap_fill_segment(
				specs, cursor, float(sp2.x), ft, i, wide_i, ladder_i, left_w, 9999.0
			)
			hop_n += int(counts["hop"])
			jump_n += int(counts["jump"])
			ladder_n += int(counts["ladder"])
			wide_i += int(counts["wide_delta"])
			ladder_i += int(counts["ladder_delta"])
			_gap_append_scatter_island(specs, float(sp2.x), float(sp2.y), ft, scatter_island_n)
			placed_span_keys["%.0f_%.0f" % [float(sp2.x), float(sp2.y)]] = true
			scatter_island_n += 1
			cursor = float(sp2.y)

		var counts2 := _gap_fill_segment(
			specs, cursor, right_start, ft, i, wide_i, ladder_i, left_w, right_w
		)
		hop_n += int(counts2["hop"])
		jump_n += int(counts2["jump"])
		ladder_n += int(counts2["ladder"])
		wide_i += int(counts2["wide_delta"])
		ladder_i += int(counts2["ladder_delta"])

	for sp3 in _design_scatter_spans:
		var key := "%.0f_%.0f" % [float(sp3.x), float(sp3.y)]
		if placed_span_keys.has(key):
			continue
		_gap_append_scatter_island(specs, float(sp3.x), float(sp3.y), ft, scatter_island_n)
		scatter_island_n += 1

	print(
		"🪵 L", level_id, " 深渊 短跳×", hop_n,
		" 跳跃渊×", jump_n, " 梯路由×", ladder_n,
		" scatter岛×", scatter_island_n
	)
	return specs


## 填充一段 [a,b] 深渊；返回计数 Dictionary
func _gap_fill_segment(
	specs: Array, a: float, b: float, ft: float, gap_i: int,
	wide_i: int, ladder_i: int, left_w: float, right_w: float
) -> Dictionary:
	var out := {"hop": 0, "jump": 0, "ladder": 0, "wide_delta": 0, "ladder_delta": 0}
	var gap_w := b - a
	if gap_w < 90.0:
		return out
	var style := _gap_pick_style(gap_w, wide_i, left_w, right_w)
	match style:
		"hop":
			_gap_append_hop_plats(specs, a, b, ft)
			out["hop"] = 1
		"scatter":
			_gap_append_scatter_plats(specs, a, b, ft, gap_i)
			out["jump"] = 1
			out["wide_delta"] = 1
		"terrace":
			_gap_append_terrace_plats(specs, a, b, ft, gap_i)
			out["jump"] = 1
			out["wide_delta"] = 1
		"over":
			_gap_append_over_plats(specs, a, b, ft, ladder_i)
			out["ladder"] = 1
			out["ladder_delta"] = 1
			out["wide_delta"] = 1
		"under":
			_gap_append_under_plats(specs, a, b, ft, ladder_i)
			out["ladder"] = 1
			out["ladder_delta"] = 1
			out["wide_delta"] = 1
		"deep":
			_gap_append_deep_plats(specs, a, b, ft, ladder_i)
			out["ladder"] = 1
			out["ladder_delta"] = 1
			out["wide_delta"] = 1
		_:
			_gap_append_hop_plats(specs, a, b, ft)
			out["hop"] = 1
	return out


## 少 terrace、多 scatter；宽坑仍穿插梯子；L3 四型更均匀
func _gap_pick_style(gap_w: float, wide_i: int, left_w: float, right_w: float) -> String:
	if level_id == 3:
		return _gap_pick_style_level3(gap_w, wide_i, left_w, right_w)
	if gap_w < 200.0:
		return "hop"
	if gap_w < 340.0:
		if (wide_i % 5) == 4 and left_w >= 160.0 and right_w >= 160.0:
			return "over" if (wide_i % 2) == 0 else "under"
		if (wide_i % 7) == 6:
			return "terrace"
		return "scatter"
	var can_ladder := left_w >= 160.0 and right_w >= 160.0
	if not can_ladder:
		return "scatter"
	match wide_i % 5:
		0, 2:
			return "scatter"
		1:
			return "over"
		3:
			return "deep" if gap_w >= 500.0 else "under"
		_:
			return "terrace" if (wide_i % 10) == 9 else "scatter"


## L3：hop / scatter / terrace / 岛链（over·under）轮换，保证都有
func _gap_pick_style_level3(gap_w: float, wide_i: int, left_w: float, right_w: float) -> String:
	if gap_w < 200.0:
		return "hop"
	var can_ladder := left_w >= 160.0 and right_w >= 160.0
	if gap_w < 360.0:
		match wide_i % 4:
			0:
				return "scatter"
			1:
				return "terrace"
			2:
				return "hop"
			_:
				if can_ladder:
					return "over"
				return "scatter"
	# 宽坑：跳跃渊与岛链梯子对仗
	if not can_ladder:
		return "scatter" if (wide_i % 2) == 0 else "terrace"
	match wide_i % 4:
		0:
			return "scatter"
		1:
			return "over"
		2:
			return "terrace"
		_:
			return "deep" if gap_w >= 520.0 else "under"


## 中段「岛」：可跳 scatter 链（高差≤二连跳，板缝≤PLATFORM_MAX_X_GAP）
func _gap_append_scatter_island(specs: Array, a: float, b: float, ft: float, seed_i: int) -> void:
	_gap_append_scatter_chain(specs, a, b, ft, seed_i, true)


## 短坑：1~2 块；与两岸距离/高差仍按可跳约束
func _gap_append_hop_plats(specs: Array, a: float, b: float, ft: float) -> void:
	_gap_append_scatter_chain(specs, a, b, ft, 0, false)


## 跳跃深渊：scatter 链（相邻高差≤二连跳抬升，水平板缝≤可跳空隙）
func _gap_append_scatter_plats(specs: Array, a: float, b: float, ft: float, gap_i: int) -> void:
	_gap_append_scatter_chain(specs, a, b, ft, gap_i, false)


## 跳跃台阶：同样走可跳链，高度用缓升缓降（不再超过二连跳/过远）
func _gap_append_terrace_plats(specs: Array, a: float, b: float, ft: float, gap_i: int) -> void:
	_gap_append_scatter_chain(specs, a, b, ft, gap_i + 3, false)


## 通用可跳链：从左岸 Floor 附近铺到右岸
## - 相对 Floor 高度 ∈ (0, max_rise]，故邻板高差自然 ≤ 二连跳
## - 相邻板边缘空隙 ≤ PLATFORM_MAX_X_GAP；首尾距岛缘同样受此约束
func _gap_append_scatter_chain(
	specs: Array, a: float, b: float, ft: float, seed_i: int, denser: bool
) -> void:
	var max_rise := _max_air_platform_rise()
	var max_h := maxf(max_rise - 8.0, 48.0)
	var gap := b - a
	if gap < 72.0:
		return

	var pw := 64.0 if denser else 68.0
	## 板与板之间的「空气缝」（边缘到边缘），低于邻接拉近阈值，留余量
	var edge_gap := PLATFORM_MAX_X_GAP * (0.72 if denser else 0.82)
	edge_gap = clampf(edge_gap, 48.0, PLATFORM_MAX_X_GAP)
	## 首尾离 Floor 岛缘也不要远于可跳
	var shore := clampf(PLATFORM_MAX_X_GAP * 0.7, 40.0, 72.0)

	var x0 := a + shore
	var x1_limit := b - shore
	if x1_limit - x0 < pw:
		# 坑太窄：中间一块，高度压在二连跳一半左右
		var mx := (a + b) * 0.5
		var h0 := clampf(52.0 + float(seed_i % 3) * 8.0, 40.0, max_h)
		specs.append([mx - pw * 0.5, mx + pw * 0.5, ft - h0])
		return

	var usable := x1_limit - x0
	# n*pw + (n-1)*edge_gap <= usable  →  n <= (usable + edge_gap) / (pw + edge_gap)
	var n := int(floor((usable + edge_gap) / (pw + edge_gap)))
	n = clampi(n, 1, 12 if denser else 10)
	# 若算出来缝仍偏大，增加板数直到缝 ≤ edge_gap
	while n < 14:
		var gaps_n := maxi(n - 1, 0)
		var seam := 0.0 if n <= 1 else (usable - float(n) * pw) / float(gaps_n)
		if seam <= edge_gap + 1.0:
			break
		n += 1

	var gaps_n2 := maxi(n - 1, 0)
	var seam2 := 0.0 if n <= 1 else (usable - float(n) * pw) / float(gaps_n2)
	seam2 = minf(seam2, edge_gap)

	# 高度：相对 Floor，且相邻步进 |dh| ≤ max_rise（再钳到 [40, max_h]）
	var deltas: Array[float] = [18.0, -14.0, 22.0, -16.0, 20.0, -12.0, 24.0, -18.0]
	var h := clampf(48.0 + float(seed_i % 4) * 6.0, 40.0, max_h)
	var cursor := x0
	# 若 seam 用满后总长不足，从 x0 起按 pw+seam 走
	var step := pw + seam2
	for i in range(n):
		# 最后一块右缘对齐 x1_limit 附近
		var px0 := cursor
		var px1 := px0 + pw
		if i == n - 1:
			px1 = minf(x1_limit, px0 + pw)
			px0 = px1 - pw
			if px0 < x0:
				px0 = x0
				px1 = px0 + pw
		h = clampf(h, 40.0, max_h)
		specs.append([px0, px1, ft - h])
		var dh: float = deltas[(i + seed_i) % deltas.size()]
		# 邻板高差硬限制：不超过二连跳抬升
		dh = clampf(dh, -max_rise, max_rise)
		var next_h := clampf(h + dh, 40.0, max_h)
		# 双保险：|next-h| 仍可能因钳制变小，无需再管
		if absf(next_h - h) > max_rise:
			next_h = h + signf(next_h - h) * max_rise
			next_h = clampf(next_h, 40.0, max_h)
		h = next_h
		cursor += step


func _gap_append_over_plats(specs: Array, a: float, b: float, ft: float, gap_i: int) -> void:
	var max_rise := _max_air_platform_rise()
	_gap_append_over_route(specs, a, b, ft, max_rise + 44.0, gap_i, false)


func _gap_append_under_plats(specs: Array, a: float, b: float, ft: float, gap_i: int) -> void:
	var max_rise := _max_air_platform_rise()
	_gap_append_under_route(specs, a, b, ft, max_rise + 44.0, gap_i, false)


func _gap_append_deep_plats(specs: Array, a: float, b: float, ft: float, gap_i: int) -> void:
	var max_rise := _max_air_platform_rise()
	_gap_append_under_route(specs, a, b, ft, max_rise + 60.0, gap_i, true)


## 高空通道：左岛缘上梯 → 高桥 → 右岛缘下梯（第 4 元 true 免高度钳制）
func _gap_append_over_route(
	specs: Array, a: float, b: float, ft: float, rise: float, gap_i: int, extra_wide: bool
) -> void:
	var over_y := ft - rise
	specs.append([a - 52.0, a + 28.0, over_y, true])
	specs.append([b - 28.0, b + 52.0, over_y, true])
	var cursor := a + 56.0
	var corridor_end := b - 56.0
	var pw := 86.0 if extra_wide else 78.0
	var step := pw + 30.0
	var ci := 0
	var max_pieces := 6 if extra_wide else 4
	while cursor + pw <= corridor_end and ci < max_pieces:
		var y_off := float((ci + gap_i) % 3) * 8.0
		specs.append([cursor, cursor + pw, over_y + y_off, true])
		cursor += step
		ci += 1


## 地下通道：左岛缘下梯 → 地道 → 右岛缘上梯
func _gap_append_under_route(
	specs: Array, a: float, b: float, ft: float, deep: float, gap_i: int, extra_wide: bool
) -> void:
	var under_y := ft + deep
	specs.append([a - 52.0, a + 28.0, under_y])
	specs.append([b - 28.0, b + 52.0, under_y])
	var cursor := a + 56.0
	var corridor_end := b - 56.0
	var pw := 86.0 if extra_wide else 78.0
	var step := pw + 30.0
	var ci := 0
	var max_pieces := 6 if extra_wide else 4
	while cursor + pw <= corridor_end and ci < max_pieces:
		var y_off := float((ci + gap_i) % 3) * 8.0
		specs.append([cursor, cursor + pw, under_y - y_off])
		cursor += step
		ci += 1


## L5：在跳板上方挂尖刺压迫（每隔一块主链板）
func _spawn_gauntlet_spikes(specs: Array) -> void:
	for c in get_children():
		if c is Node and String(c.name).begins_with("Spike_"):
			c.queue_free()
	var i := 0
	var air_i := 0
	for s in specs:
		var x0: float = float(s[0])
		var x1: float = float(s[1])
		var top_y: float = float(s[2])
		if top_y > FLOOR_TOP_Y:
			continue
		air_i += 1
		if (air_i % 2) == 0:
			continue
		var spike = SPIKE_SCENE.instantiate()
		spike.name = "Spike_%d" % i
		add_child(spike)
		spike.position = Vector2((x0 + x1) * 0.5, top_y - 48.0)
		if spike.has_method("apply_visual"):
			spike.apply_visual(true)
		i += 1


## L2 怪均布 / L3 地面怪+多狐妖 / 星星分段
func _spawn_level_entities() -> void:
	var to_remove: Array[Node] = []
	for c in get_children():
		if c is Node and (
			String(c.name).begins_with("LevelEnemy_")
			or String(c.name).begins_with("LevelFox_")
			or String(c.name).begins_with("LevelStar_")
		):
			to_remove.append(c)
	for n in to_remove:
		n.free()
	match level_id:
		2:
			_spawn_level2_enemies()
		3:
			_spawn_level3_enemies_and_foxes()
		_:
			pass
	_spawn_level_stars()


## L3：全关均布 BaseEnemy + 多只 LanternFox（高度钳在二连跳内）
func _spawn_level3_enemies_and_foxes() -> void:
	var islands := _stereo_floor_islands()
	if islands.is_empty():
		return

	var max_rise := _max_air_platform_rise()
	var fox_amp := 16.0
	var max_above := maxf(max_rise - fox_amp - 8.0, 48.0)
	var fox_above := minf(72.0, max_above * 0.55)
	var fox_y := FLOOR_TOP_Y - fox_above

	# —— 地面巡逻怪：中段岛尽量都放，上限约 18 ——
	var slots: Array[int] = []
	for i in range(1, maxi(islands.size() - 1, 1)):
		var island: Vector2 = islands[i]
		if float(island.y) - float(island.x) < 140.0:
			continue
		slots.append(i)
	var enemy_i := 0
	var want_e := mini(18, slots.size())
	var used: Dictionary = {}
	for k in range(want_e):
		var si: int = int(floor(float(k) * float(slots.size()) / float(maxi(want_e, 1))))
		si = clampi(si, 0, slots.size() - 1)
		while used.has(si) and si < slots.size() - 1:
			si += 1
		if used.has(si):
			continue
		used[si] = true
		var isl: Vector2 = islands[slots[si]]
		var e = ENEMY_SCENE.instantiate()
		e.name = "LevelEnemy_%d" % enemy_i
		e.position = Vector2((isl.x + isl.y) * 0.5, FLOOR_TOP_Y - 40.0)
		add_child(e)
		if e.has_method("set_patrol_island"):
			e.set_patrol_island(isl.x, isl.y, 36.0)
		enemy_i += 1

	# 后半跳板再补几只
	var plats: Array = _platform_specs_for_level([])
	var x_mid := (float(islands[0].x) + float(islands[islands.size() - 1].y)) * 0.5
	var plat_slots: Array = []
	for s in plats:
		var px0: float = float(s[0])
		var px1: float = float(s[1])
		var top_y: float = float(s[2])
		if px1 - px0 < 70.0:
			continue
		if (px0 + px1) * 0.5 < x_mid:
			continue
		if top_y > FLOOR_TOP_Y + 8.0:
			continue ## 地下通道少放，避免怪掉深渊观感差
		plat_slots.append(s)
	plat_slots.shuffle()
	var plat_extra := 0
	for s2 in plat_slots:
		if plat_extra >= 5:
			break
		var e2 = ENEMY_SCENE.instantiate()
		e2.name = "LevelEnemy_%d" % enemy_i
		e2.position = Vector2((float(s2[0]) + float(s2[1])) * 0.5, float(s2[2]) - 40.0)
		add_child(e2)
		if e2.has_method("set_patrol_island"):
			e2.set_patrol_island(float(s2[0]), float(s2[1]), 20.0)
		enemy_i += 1
		plat_extra += 1

	# —— 狐妖：前 / 中 / 后 各放，约 4 只 ——
	var fox_n := 0
	var fox_want := 4
	var fox_slots: Array[int] = []
	for i2 in range(2, maxi(islands.size() - 1, 2)):
		if float(islands[i2].y) - float(islands[i2].x) >= 180.0:
			fox_slots.append(i2)
	var fox_used: Dictionary = {}
	for k2 in range(mini(fox_want, fox_slots.size())):
		var fi: int = int(floor(float(k2) * float(fox_slots.size()) / float(fox_want)))
		fi = clampi(fi, 0, fox_slots.size() - 1)
		while fox_used.has(fi) and fi < fox_slots.size() - 1:
			fi += 1
		if fox_used.has(fi):
			continue
		fox_used[fi] = true
		var fisl: Vector2 = islands[fox_slots[fi]]
		var fox = FOX_SCENE.instantiate()
		fox.name = "LevelFox_%d" % fox_n
		fox.position = Vector2((fisl.x + fisl.y) * 0.5, fox_y)
		add_child(fox)
		if fox.has_method("clamp_hover_to_double_jump"):
			fox.call("clamp_hover_to_double_jump", FLOOR_TOP_Y, max_rise)
		fox_n += 1

	print("👾 L3 怪 ×", enemy_i, " 狐妖 ×", fox_n)


## L2：怪按岛序均匀抽到全关（含后半），另在后半高台补 2~3 只
func _spawn_level2_enemies() -> void:
	var islands := _stereo_floor_islands()
	var slots: Array[int] = []
	for i in range(1, maxi(islands.size() - 1, 1)):
		var island: Vector2 = islands[i]
		if float(island.y) - float(island.x) < 150.0:
			continue
		slots.append(i)
	if slots.is_empty():
		return

	const FLOOR_ENEMY_MAX := 11
	var want_floor := mini(FLOOR_ENEMY_MAX, slots.size())
	var enemy_i := 0
	var used_slots: Dictionary = {}
	for k in range(want_floor):
		# 均匀映射到 slots，保证前/中/后都有
		var si: int = int(floor(float(k) * float(slots.size()) / float(want_floor)))
		si = clampi(si, 0, slots.size() - 1)
		while used_slots.has(si) and si < slots.size() - 1:
			si += 1
		if used_slots.has(si):
			continue
		used_slots[si] = true
		var island: Vector2 = islands[slots[si]]
		var e = ENEMY_SCENE.instantiate()
		e.name = "LevelEnemy_%d" % enemy_i
		e.position = Vector2((island.x + island.y) * 0.5, FLOOR_TOP_Y - 40.0)
		add_child(e)
		if e.has_method("set_patrol_island"):
			e.set_patrol_island(island.x, island.y, 36.0)
		enemy_i += 1

	# 后半段高台/跳板再补怪（X 过中点）
	var plats: Array = _platform_specs_for_level([])
	if plats.is_empty() or islands.is_empty():
		print("👾 L2 怪 ×", enemy_i, "（仅地面）")
		return
	var x_mid := (float(islands[0].x) + float(islands[islands.size() - 1].y)) * 0.5
	var plat_slots: Array = []
	for s in plats:
		var px0: float = float(s[0])
		var px1: float = float(s[1])
		var top_y: float = float(s[2])
		if px1 - px0 < 70.0:
			continue
		if (px0 + px1) * 0.5 < x_mid:
			continue
		# 只要站得住的板（含地下通道与高塔）
		plat_slots.append(s)
	plat_slots.shuffle()
	var plat_extra := 0
	for s2 in plat_slots:
		if plat_extra >= 3:
			break
		var px0b: float = float(s2[0])
		var px1b: float = float(s2[1])
		var top_yb: float = float(s2[2])
		var e2 = ENEMY_SCENE.instantiate()
		e2.name = "LevelEnemy_%d" % enemy_i
		e2.position = Vector2((px0b + px1b) * 0.5, top_yb - 40.0)
		add_child(e2)
		if e2.has_method("set_patrol_island"):
			e2.set_patrol_island(px0b, px1b, 20.0)
		enemy_i += 1
		plat_extra += 1
	print("👾 L2 怪 ×", enemy_i, "（地面均布+", want_floor, " 后半高台+", plat_extra, "）")


## 星星：随机但只落在玩家从出生岛 BFS 可达的 Floor/Platform 上（前中后分段）
func _spawn_level_stars() -> void:
	var max_stars := 6 if level_id == 2 else (8 if level_id == 3 else 3)
	const MIN_SEP := 280.0
	var reachable := _reachable_stand_surfaces()
	if reachable.is_empty():
		push_warning("⚠️ L%d 无可达表面，跳过星星" % level_id)
		return

	var candidates: Array[Vector2] = []
	var x_lo := INF
	var x_hi := -INF
	for s in reachable:
		var a: float = float(s["x0"])
		var b: float = float(s["x1"])
		var top: float = float(s["top"])
		var w := b - a
		if w < 48.0:
			continue
		x_lo = minf(x_lo, a)
		x_hi = maxf(x_hi, b)
		var pad := 16.0
		var x0 := a + pad
		var x1 := b - pad
		if x1 <= x0:
			continue
		# 每块可达表面抽 2 点；星星在站立面上方，保证站上去就能碰到
		for _k in range(2):
			var sx := randf_range(x0, x1)
			var sy := top - randf_range(36.0, 58.0)
			candidates.append(Vector2(sx, sy))

	if candidates.is_empty() or x_hi <= x_lo:
		return

	var span := maxf(x_hi - x_lo, 1.0)
	var buckets: Array = [[], [], []]
	for cpos in candidates:
		var t := (cpos.x - x_lo) / span
		var bi := 0
		if t >= 0.66:
			bi = 2
		elif t >= 0.33:
			bi = 1
		buckets[bi].append(cpos)

	for bi2 in range(3):
		(buckets[bi2] as Array).shuffle()

	var placed: Array[Vector2] = []
	var per_bucket := 2 if level_id == 2 else (3 if level_id == 3 else 1)
	for bi3 in range(3):
		var got := 0
		for cpos2 in buckets[bi3]:
			if got >= per_bucket or placed.size() >= max_stars:
				break
			if not _star_sep_ok(cpos2, placed, MIN_SEP):
				continue
			_place_one_level_star(cpos2, placed.size())
			placed.append(cpos2)
			got += 1

	if placed.size() < max_stars:
		var rest: Array[Vector2] = []
		for bi4 in range(3):
			for cpos3 in buckets[bi4]:
				rest.append(cpos3)
		rest.shuffle()
		for cpos4 in rest:
			if placed.size() >= max_stars:
				break
			if not _star_sep_ok(cpos4, placed, MIN_SEP):
				continue
			_place_one_level_star(cpos4, placed.size())
			placed.append(cpos4)

	print("⭐ L", level_id, " 关卡星星 ×", placed.size(), "/", max_stars,
		"（可达表面×", reachable.size(), "）")


func _star_sep_ok(cpos: Vector2, placed: Array[Vector2], min_sep: float) -> bool:
	for p in placed:
		if cpos.distance_to(p) < min_sep:
			return false
	return true


func _place_one_level_star(cpos: Vector2, idx: int) -> void:
	var star = LIGHT_ORB_SCENE.instantiate()
	star.name = "LevelStar_%d" % idx
	star.scale = Vector2(0.03, 0.03)
	add_child(star)
	star.position = cpos


## 从出生 Floor 岛出发：可跳（高差≤二连跳且水平≤安全跳距）或可爬梯（高差>二连跳且重叠）连通的表面
func _reachable_stand_surfaces() -> Array:
	var surfs: Array = []
	var islands := _stereo_floor_islands()
	for isl in islands:
		surfs.append({"x0": float(isl.x), "x1": float(isl.y), "top": FLOOR_TOP_Y})
	for s in _platform_specs_for_level([]):
		var x0: float = float(s[0])
		var x1: float = float(s[1])
		if x1 - x0 < 24.0:
			continue
		surfs.append({"x0": x0, "x1": x1, "top": float(s[2])})
	if surfs.is_empty():
		return []

	var max_rise := _max_air_platform_rise()
	var n := surfs.size()
	var adj: Array = []
	for _i in range(n):
		adj.append([])
	for i in range(n):
		for j in range(i + 1, n):
			if _stand_surfaces_linked(surfs[i], surfs[j], max_rise):
				adj[i].append(j)
				adj[j].append(i)

	# 出生 = 第一座 Floor 岛（index 0）
	var seen: Dictionary = {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var u: int = queue.pop_front()
		for v in adj[u]:
			var vi: int = int(v)
			if seen.has(vi):
				continue
			seen[vi] = true
			queue.append(vi)

	var out: Array = []
	for i2 in range(n):
		if seen.has(i2):
			out.append(surfs[i2])
	return out


func _stand_surfaces_linked(a: Dictionary, b: Dictionary, max_rise: float) -> bool:
	var a0: float = float(a["x0"])
	var a1: float = float(a["x1"])
	var at: float = float(a["top"])
	var b0: float = float(b["x0"])
	var b1: float = float(b["x1"])
	var bt: float = float(b["top"])
	var hgap := absf(at - bt)
	var xgap := _horizontal_gap(a0, a1, b0, b1)
	var ov := minf(a1, b1) - maxf(a0, b0)
	if hgap <= max_rise + 1.0:
		# 可跳或已重叠可走
		return xgap <= SAFE_JUMP_X + 12.0 or ov > 0.0
	# 须架梯：水平重叠足够（与架梯规则一致）
	return ov >= LADDER_OVERLAP_MIN - 2.0


## 每个平台槽位：头碰头铺满贴图；碰撞由 `_rebuild_all_platform_collisions_from_sprites` 按贴图强制生成
## 硬规则：只要生成了 Sprite，后续重建必带同宽同高 One-Way 碰撞。
func _place_one_platform_art(
	_root: Node,
	visuals: Node2D,
	tex: Texture2D,
	x0: float,
	x1: float,
	top_y: float
) -> int:
	var span_w := x1 - x0
	if span_w < 8.0:
		push_warning("⚠️ Platform 槽位过窄已跳过 [", snappedf(x0, 0.1), ",", snappedf(x1, 0.1), "]")
		return 0

	var visual_h := PLATFORM_MIN_VISUAL_H
	var placed := 0
	var info: Dictionary = {}
	if tex != null:
		info = _analyze_platform_texture(tex)
		var content_w: float = maxf(float(info["content_w"]), 1.0)
		var content_h: float = maxf(float(info["content_h"]), 1.0)
		visual_h = _terrain_visual_height(content_w, content_h, PLATFORM_MIN_VISUAL_H)

	var x_cursor := x0
	var guard := 0
	while x_cursor < x1 - 0.5 and guard < 200:
		guard += 1
		var remain := x1 - x_cursor
		var piece_w := remain
		if tex != null and not info.is_empty():
			var content_w2: float = maxf(float(info["content_w"]), 1.0)
			var content_h2: float = maxf(float(info["content_h"]), 1.0)
			var natural_w := content_w2 * (visual_h / content_h2)
			piece_w = minf(natural_w, remain)
			if remain - piece_w < 8.0:
				piece_w = remain
		if piece_w < 2.0:
			break

		if tex != null and not info.is_empty():
			var vis: Dictionary = _make_terrain_sprite_fit(tex, info, piece_w, visual_h)
			if not vis.is_empty():
				var spr := Sprite2D.new()
				spr.texture = vis["texture"]
				spr.centered = false
				spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				spr.region_enabled = bool(vis["region_enabled"])
				if spr.region_enabled:
					spr.region_rect = vis["region_rect"]
				var src_w := spr.region_rect.size.x if spr.region_enabled else float(spr.texture.get_width())
				var src_h := spr.region_rect.size.y if spr.region_enabled else float(spr.texture.get_height())
				# 显示尺寸强制 = piece_w × visual_h（与随后重建的碰撞完全一致）
				spr.scale = Vector2(piece_w / maxf(src_w, 1.0), visual_h / maxf(src_h, 1.0))
				spr.modulate = vis["modulate"]
				spr.position = Vector2(x_cursor, top_y)
				spr.z_index = 1
				spr.set_meta("plat_w", piece_w)
				spr.set_meta("plat_h", visual_h)
				visuals.add_child(spr)
				placed += 1

		x_cursor += piece_w

	if placed <= 0 and tex == null:
		push_warning("⚠️ Platform 槽位 [", snappedf(x0, 0.1), ",", snappedf(x1, 0.1),
			"] 无贴图——将由槽位兜底生成碰撞 h=", snappedf(visual_h, 0.1))
	return 1 if x_cursor >= x1 - 1.0 or placed > 0 else 0


## 贴图目标可视高度：过细（超宽扁）则加粗
func _terrain_visual_height(content_w: float, content_h: float, min_h: float) -> float:
	var h := maxf(min_h, FLOOR_COLL_H)
	var aspect := content_w / maxf(content_h, 1.0)
	if aspect >= TERRAIN_THIN_ASPECT:
		h = maxf(h, min_h * 1.35)
	return h


## 生成贴合碰撞盒的 Sprite 数据：提亮；过宽则水平切掉中间再左右拼接
## 返回 { texture, region_enabled, region_rect, scale, modulate }
func _make_terrain_sprite_fit(tex: Texture2D, info: Dictionary, world_w: float, world_h: float) -> Dictionary:
	if tex == null or world_w < 2.0 or world_h < 2.0:
		return {}
	var x0: float = float(info["x0"])
	var y0: float = float(info["y0"])
	var cw: float = maxf(float(info["content_w"]), 1.0)
	var ch: float = maxf(float(info["content_h"]), 1.0)
	var sy := world_h / ch
	var natural_w := cw * sy
	var bright := Color(TERRAIN_BRIGHTEN, TERRAIN_BRIGHTEN, minf(TERRAIN_BRIGHTEN * 1.05, 1.85), 1.0)

	# 自然宽度未超过碰撞：等比（或略拉满宽）
	if natural_w <= world_w + 0.5:
		var sx := sy
		if natural_w < world_w * 0.92:
			sx = world_w / cw ## 略窄则拉满碰撞宽
		return {
			"texture": tex,
			"region_enabled": true,
			"region_rect": Rect2(x0, y0, cw, ch),
			"scale": Vector2(sx, sy),
			"modulate": bright,
		}

	# 图片水平超出碰撞：切掉中间，左右拼成目标像素宽
	var need_px := world_w / sy
	need_px = clampf(need_px, 8.0, cw)
	var stitched: Texture2D = _stitch_trim_horizontal(tex, int(x0), int(y0), int(cw), int(ch), int(ceil(need_px)))
	if stitched == null:
		# 回退：直接压扁宽度
		return {
			"texture": tex,
			"region_enabled": true,
			"region_rect": Rect2(x0, y0, cw, ch),
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


## 水平切掉中间，保留左右两端拼成 keep_w 宽（像素）
func _stitch_trim_horizontal(
	tex: Texture2D, x0: int, y0: int, cw: int, ch: int, keep_w: int
) -> Texture2D:
	keep_w = clampi(keep_w, 4, cw)
	var key := "%s_%d_%d_%d_%d_%d" % [tex.resource_path, x0, y0, cw, ch, keep_w]
	if _terrain_stitch_cache.has(key):
		return _terrain_stitch_cache[key] as Texture2D

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
	# 左端
	out.blit_rect(img, Rect2i(x0, y0, left_w, ch), Vector2i(0, 0))
	# 右端
	out.blit_rect(img, Rect2i(x0 + cw - right_w, y0, right_w, ch), Vector2i(left_w, 0))

	var tex_out := ImageTexture.create_from_image(out)
	_terrain_stitch_cache[key] = tex_out
	return tex_out


## 平台图：裁掉纯黑/透明边，只留可见平台美术
func _analyze_platform_texture(tex: Texture2D) -> Dictionary:
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


func _is_platform_pixel(c: Color) -> bool:
	if c.a < 0.08:
		return false
	var lum := c.r * 0.3 + c.g * 0.5 + c.b * 0.2
	if lum > 0.05:
		return true
	var chroma := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
	return chroma > 0.04 and lum > 0.02


## 只加载 platform/ 内美术（写死路径，避免 DirAccess 漏文件）
func _load_platform_textures() -> Array[Texture2D]:
	var paths: Array[String] = [
		"res://assets/tiles/platform/platform_01.png",
		"res://assets/tiles/platform/platform_02.png",
		"res://assets/tiles/platform/platform_03.png",
		"res://assets/tiles/platform/goth_01.png",
		"res://assets/tiles/platform/goth_02.png",
		"res://assets/tiles/platform/goth_03.png",
	]
	var out: Array[Texture2D] = []
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var tex := load(p) as Texture2D
		if tex:
			out.append(tex)
			print("  • 平台贴图 OK ", p.get_file(), " ", tex.get_width(), "x", tex.get_height())
	if out.is_empty():
		push_error("platform/ 无任何可贴图（禁止使用 platform_tile 绿块）")
	return out


## 兼容旧调用名
func _place_platform_run(
	root: Node,
	visuals: Node2D,
	textures: Array[Texture2D],
	x0: float,
	x1: float,
	top_y: float
) -> int:
	if textures.is_empty():
		return 0
	return _place_one_platform_art(root, visuals, textures[0], x0, x1, top_y)


## 头碰头铺贴（地板）：提亮+细条加粗；超碰撞宽则切中拼接；碰撞=可视
## 返回 { "count": int, "x_end": float }
func _pave_matched_strip(
	body: StaticBody2D,
	visuals: Node2D,
	textures: Array[Texture2D],
	x_from: float,
	x_to: float,
	top_y: float,
	target_h: float,
	one_way: bool
) -> Dictionary:
	if textures.is_empty() or x_to - x_from < 4.0:
		return {"count": 0, "x_end": x_from}
	var x_cursor := x_from
	var count := 0
	var guard := 0
	while x_cursor < x_to - 2.0 and guard < 400:
		guard += 1
		var remain := x_to - x_cursor
		var best_tex: Texture2D = null
		var best_info: Dictionary = {}
		var best_w := 0.0
		var best_h := 0.0

		for _try in range(mini(16, maxi(textures.size() * 3, 8))):
			var tex: Texture2D = textures[randi() % textures.size()]
			var info := _analyze_floor_texture(tex)
			var content_h: float = maxf(float(info["content_h"]), 1.0)
			var content_w_px: float = maxf(float(info["content_w"]), 1.0)
			var piece_h := _terrain_visual_height(content_w_px, content_h, maxf(target_h, FLOOR_MIN_VISUAL_H))
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

		# 末块拉满到 x_to，保证贴图与岛碰撞同宽
		if x_to - (x_cursor + best_w) < 8.0:
			best_w = x_to - x_cursor
			best_h = maxf(best_h, FLOOR_MIN_VISUAL_H)

		var vis: Dictionary = _make_terrain_sprite_fit(best_tex, best_info, best_w, best_h)
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
		if one_way:
			cs.one_way_collision = true
			cs.one_way_collision_margin = 2.0
		body.add_child(cs)

		x_cursor += best_w
		count += 1
		if x_to - x_cursor < 0.5:
			break
	return {"count": count, "x_end": x_cursor}


func _pave_floor_sprites(host: Node2D, textures: Array[Texture2D], x_from: float, x_to: float) -> void:
	push_warning("_pave_floor_sprites 已弃用，请用 _pave_matched_strip")
	if _floor_body:
		_pave_matched_strip(_floor_body, host, textures, x_from, x_to, FLOOR_TOP_Y, FLOOR_COLL_H, false)


func _analyze_floor_texture(tex: Texture2D) -> Dictionary:
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
		# 再细扫左右边界（避免 step 漏边）
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
		"y0": y0,
		"y1": y1,
		"x0": x0,
		"x1": x1,
		"content_h": y1 - y0 + 1,
		"content_w": x1 - x0 + 1,
	}


## 只用地板美术：stoneBrick + wooden。禁止 greenSlabstone / floor_tile 绿块占位
func _load_ground_textures() -> Array[Texture2D]:
	var paths: Array[String] = [
		"res://assets/tiles/ground/stoneBrick/brick_01.png",
		"res://assets/tiles/ground/stoneBrick/brick_02.png",
		"res://assets/tiles/ground/stoneBrick/brick_03.png",
		"res://assets/tiles/ground/wooden/wooden_01.png",
		"res://assets/tiles/ground/wooden/wooden_02.png",
		"res://assets/tiles/ground/wooden/wooden_03.png",
	]
	var out: Array[Texture2D] = []
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var tex := load(p) as Texture2D
		if tex:
			out.append(tex)
			print("  • 地板贴图 OK ", p.get_file())
	if out.is_empty():
		push_error("❌ ground 无 brick/wooden 贴图——禁止回退绿块")
	return out


func _collect_pngs_recursive(dir_path: String, out: Array[Texture2D]) -> void:
	var abs_path := ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if fname.begins_with("."):
			fname = da.get_next()
			continue
		var full := dir_path.path_join(fname)
		if da.current_is_dir():
			_collect_pngs_recursive(full, out)
		elif fname.to_lower().ends_with(".png"):
			var tex := load(full) as Texture2D
			if tex:
				out.append(tex)
		fname = da.get_next()
	da.list_dir_end()


func _set_markers_world(spawn_pos: Vector2, goal_pos: Vector2) -> void:
	var spawn := get_node_or_null("SpawnPoint") as Marker2D
	if spawn == null:
		spawn = Marker2D.new()
		spawn.name = "SpawnPoint"
		add_child(spawn)
	spawn.position = spawn_pos
	if not spawn.is_in_group("spawn_point"):
		spawn.add_to_group("spawn_point")

	# 移除金色光圈 GoalTrigger；改用 LightDoor（DoorClose/DoorOpen）
	var legacy := get_node_or_null("GoalTrigger")
	if legacy:
		legacy.free()

	var door := get_node_or_null("LightDoor") as Area2D
	if door == null:
		door = LIGHT_DOOR_SCENE.instantiate() as Area2D
		door.name = "LightDoor"
		add_child(door)
	door.position = goal_pos
	var next_id := level_id + 1
	if next_id > 5:
		next_id = 1 ## L5 通关回第一关（可再改菜单）
	if "next_level_id" in door:
		door.set("next_level_id", next_id)
	if debug_spawn_near_light_door and level_id == 1:
		print("🧪 L1 出生点调试位：LightDoor 旁 offset_x=", debug_spawn_offset_x, " spawn→", spawn_pos, " door→", goal_pos)


func _infer_ground_top_y() -> float:
	return FLOOR_TOP_Y


## 直接打开关卡场景时也要本关光照；换关时 LevelManager 还会再调一次（同目标，无害）
## 只改主角 RealLight，绝不写 ParallaxBackground
func _sync_level_atmosphere() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("apply_level_brightness"):
		var dur := 1.5
		if "brightness_tween_duration" in gm:
			dur = float(gm.brightness_tween_duration)
		gm.apply_level_brightness(level_id, dur)


## 深渊底部贯穿 KillZone：触碰玩家 → GameManager.reset_level()
func _ensure_abyss_killzone(floor_left_x: float, floor_right_x: float) -> void:
	var legacy := get_node_or_null("AbyssKillZone")
	if legacy:
		legacy.free()
	var kill := get_node_or_null("KillZone") as Area2D
	if kill == null:
		kill = Area2D.new()
		kill.name = "KillZone"
		kill.set_script(load("res://levels/kill_zone.gd"))
		add_child(kill)
	elif kill.get_script() == null:
		kill.set_script(load("res://levels/kill_zone.gd"))
	# 顶边低于最深地下平台（L4 ≈ Floor+280），避免误杀
	var top_y := FLOOR_TOP_Y + 320.0
	if kill.has_method("setup_span"):
		kill.setup_span(floor_left_x, floor_right_x, top_y, 560.0)


func _on_abyss_body_entered(body: Node2D) -> void:
	# 兼容旧连接；正式逻辑在 kill_zone.gd
	if body == null or not body.is_in_group("player"):
		return
	if body.has_method("kill_by_abyss"):
		body.call_deferred("kill_by_abyss")
		return
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("game_over"):
		gm.call_deferred("game_over", "abyss")


func _ensure_tile_layers() -> void:
	var ts: TileSet = ForestTiles.build()
	_ground = get_node_or_null("TileLayers/Ground") as TileMapLayer
	_platforms = get_node_or_null("TileLayers/Platforms") as TileMapLayer
	_decor = get_node_or_null("TileLayers/Decor") as TileMapLayer

	if _ground == null:
		var root := get_node_or_null("TileLayers")
		if root == null:
			root = Node2D.new()
			root.name = "TileLayers"
			add_child(root)
			move_child(root, 0)
		_ground = TileMapLayer.new()
		_ground.name = "Ground"
		root.add_child(_ground)
		_platforms = TileMapLayer.new()
		_platforms.name = "Platforms"
		root.add_child(_platforms)
		_decor = TileMapLayer.new()
		_decor.name = "Decor"
		root.add_child(_decor)

	_ground.tile_set = ts
	_platforms.tile_set = ts
	_decor.tile_set = ts
	_ground.scale = Vector2.ONE
	_platforms.scale = Vector2.ONE
	_decor.scale = Vector2.ONE
	_platforms.add_to_group("walls")
	_ground.collision_enabled = false
	_platforms.collision_enabled = false ## 平台改用 PlatformBody + platform/ 美术，禁用绿块 TileMap
	_platforms.visible = false
	_ground.visible = false ## 地板改用 FloorBody + brick/wooden，禁用 TileMap 绿石板
	_decor.collision_enabled = false
	_decor.z_index = -2
	_ground.z_index = -1
	_platforms.z_index = -1


func _boot_player_at_spawn() -> void:
	# 每次用关卡逻辑重算出生点，避免场景里旧 Marker / 时序把人扔到别处
	var spawn_pos := _spawn_pos_for_level()
	var spawn := get_node_or_null("SpawnPoint") as Marker2D
	if spawn == null:
		spawn = Marker2D.new()
		spawn.name = "SpawnPoint"
		add_child(spawn)
	spawn.position = spawn_pos
	if not spawn.is_in_group("spawn_point"):
		spawn.add_to_group("spawn_point")

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		player = PLAYER_SCENE.instantiate()
		add_child(player)

	if player.has_method("reset_at_spawn"):
		player.reset_at_spawn(spawn.global_position)
	else:
		player.global_position = spawn.global_position
		if "velocity" in player:
			player.velocity = Vector2.ZERO

	print("📍 Level ", level_id, " 出生 → ", spawn.global_position)


func _paint_layout(_preset: String) -> void:
	if _ground:
		_ground.clear()
	if _platforms:
		_platforms.clear()
	if _decor:
		_decor.clear()
	# 占位：真正地板在 _build_floor_collider_and_art（碎岛 + LightDoor）
	_set_markers_world(_spawn_pos_for_level(), _door_pos_for_level())


func _fill_ground(_y: int, _x0: int, _x1: int) -> void:
	pass


func _platform(x0: int, x1: int, y: int, goth: bool = false) -> void:
	var src := ForestTiles.SRC_PLATFORM_GOTH if goth else ForestTiles.SRC_PLATFORM
	if not _platforms.tile_set.has_source(src):
		src = ForestTiles.SRC_PLATFORM
	for x in range(x0, x1 + 1):
		if _platforms.tile_set.has_source(src):
			_platforms.set_cell(Vector2i(x, y), src, Vector2i(0, 0))


func _ladder(x: int, y0: int, y1: int) -> void:
	if not _decor.tile_set.has_source(ForestTiles.SRC_LADDER):
		return
	for y in range(y0, y1 + 1):
		_decor.set_cell(Vector2i(x, y), ForestTiles.SRC_LADDER, Vector2i(0, 0))


func _spike(cell: Vector2i, ceiling: bool = false) -> void:
	var spike = SPIKE_SCENE.instantiate()
	add_child(spike)
	spike.position = Vector2(cell) * ForestTiles.WORLD_CELL + Vector2(16, 24)
	if spike.has_method("apply_visual"):
		spike.apply_visual(ceiling)


func _cell_pos(cx: float, cy: float) -> Vector2:
	return Vector2(cx, cy) * ForestTiles.WORLD_CELL + Vector2(16, 0)


func _spawn(scene: PackedScene, cell: Vector2, scl: Vector2 = Vector2.ONE) -> void:
	var ent = scene.instantiate()
	add_child(ent)
	ent.position = _cell_pos(cell.x, cell.y)
	if scl != Vector2.ONE:
		ent.scale = scl
