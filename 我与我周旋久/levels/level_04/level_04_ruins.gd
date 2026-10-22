extends Node2D
## Level 4「地下遗迹」
## 斜向下展开（可掉深渊）+ 少量上爬梯子；总体趋势持续向下
## Floor/Platform 贴图 = L1–L3 同款 TerrainArtPainter
## 星星尺寸/分配、LanternFox、怪物密度对齐 L1–L3 习惯

const PLAYER_SCENE = preload("res://Player.tscn")
const STORY := preload("res://scripts/story_data.gd")
const ENEMY_SCENE = preload("res://enemy.tscn")
const FOX_SCENE = preload("res://lantern_fox.tscn")
const LIGHT_ORB_SCENE = preload("res://light_orb.tscn")
const BACKDROP_SCENE = preload("res://levels/ParallaxBackdrop.tscn")
const PETALS_SCENE = preload("res://levels/PetalsParticle.tscn")
const SPIKE_SCENE = preload("res://levels/Spike.tscn")
const LIGHT_DOOR_SCENE = preload("res://levels/LightDoor.tscn")
const KILL_ZONE_SCRIPT = preload("res://levels/kill_zone.gd")
const LADDER_ZONE_SCRIPT = preload("res://levels/ladder_zone.gd")
const TerrainArtPainter = preload("res://levels/terrain_art_painter.gd")

const FLOOR_TOP_Y := 256.0
const PLAYER_JUMP_SPEED := 456.0
const PLAYER_DOUBLE_JUMP_SPEED := 420.0
const PLAYER_GRAVITY_REF := 1000.0
const PLATFORM_LANDING_MARGIN := 12.0
const MIN_PLATFORM_Y_GAP := 220.0
const LADDER_OVERLAP_MIN := 48.0
const LADDER_MIN_HEIGHT := 40.0
const SAFE_JUMP_X := 140.0
const SPIKE_W := 40.0
const SPIKE_H := 32.0
## 边界：LightDoor 再往下这么多像素；掉到这里回出生点
const DEATH_BELOW_DOOR := 100.0
## 星星：与 L1–L3 相同 scale；数量取 L2/L3 之间
const STAR_SCALE := Vector2(0.03, 0.03)
const STAR_COUNT := 7 ## 关长约现长 2/3，按前中后桶分配
const STAR_MIN_SEP := 280.0

@export var level_id: int = 4
@export var use_parallax_backdrop: bool = true

const LEFT_FLOOR_A := 0.0
const LEFT_FLOOR_B := 420.0
const WORLD_LEFT := -120.0

var _grounds: Node2D
var _platforms: Node2D
var _hazards: Node2D
var _enemies: Node2D
var _props: Node2D
var _painter = null
var _ground_tex: Array[Texture2D] = []
var _plat_tex: Array[Texture2D] = []
var _goth_tex: Array[Texture2D] = []
var _lowest_solid_y: float = FLOOR_TOP_Y
var _world_right: float = 4000.0
## 可站立表面 {x0,x1,top,kind} kind: "floor"|"plat"
var _surfaces: Array = []
var _floor_segments: Array = [] ## Vector2(x0,x1) 供视差
## 梯子柱心 X：尖刺禁止落在同一竖向带宽内
var _ladder_xs: Array[float] = []
const LADDER_SPIKE_CLEAR := 56.0 ## 梯子中心左右各清这么宽，不放刺


func _ready() -> void:
	var lm := get_node_or_null("/root/LevelManager")
	if lm:
		lm.current_level_id = level_id

	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	_lowest_solid_y = FLOOR_TOP_Y
	_surfaces.clear()
	_floor_segments.clear()
	_ladder_xs.clear()

	_ensure_groups()
	_painter = TerrainArtPainter.new()
	_ground_tex = _painter.load_ground_textures()
	_plat_tex = _painter.load_platform_textures(false)
	_goth_tex = _painter.load_platform_textures(true)

	if use_parallax_backdrop and get_node_or_null("ParallaxBackdrop") == null:
		var bg = BACKDROP_SCENE.instantiate()
		bg.name = "ParallaxBackdrop"
		add_child(bg)
		move_child(bg, 0)

	if get_node_or_null("PetalsAtmosphere") == null:
		var petals = PETALS_SCENE.instantiate()
		petals.name = "PetalsAtmosphere"
		add_child(petals)

	_build_ruins()
	_place_spawn_and_door()
	_spawn_entities()
	_ensure_killzone()
	call_deferred("_boot_player_at_spawn")
	call_deferred("_sync_atmosphere")
	call_deferred("_sync_backdrop_horizon")
	call_deferred("_try_start_prologue")

	print("🏛️ L4 斜向下遗迹 | 表面×", _surfaces.size(),
		" 最低=", snappedf(_lowest_solid_y, 0.1))


func _try_start_prologue() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if level_id != 1:
		return
	var gm := get_node_or_null("/root/GameManager")
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


func _ensure_groups() -> void:
	_grounds = _ensure_child_group("Level_Grounds")
	_platforms = _ensure_child_group("Level_Platforms")
	_hazards = _ensure_child_group("Level_Hazards")
	_enemies = _ensure_child_group("Level_Enemies")
	_props = _ensure_child_group("Level_Props")


func _ensure_child_group(n: String) -> Node2D:
	var node := get_node_or_null(n) as Node2D
	if node == null:
		node = Node2D.new()
		node.name = n
		add_child(node)
	return node


func _note_solid_bottom(top_y: float, h: float) -> void:
	_lowest_solid_y = maxf(_lowest_solid_y, top_y + h)


func _register_surface(x0: float, x1: float, top: float, kind: String) -> void:
	_surfaces.append({"x0": x0, "x1": x1, "top": top, "kind": kind})
	if kind == "floor":
		_floor_segments.append(Vector2(x0, x1))


func _max_jump_rise() -> float:
	var h := (
		PLAYER_JUMP_SPEED * PLAYER_JUMP_SPEED
		+ PLAYER_DOUBLE_JUMP_SPEED * PLAYER_DOUBLE_JUMP_SPEED
	) / (2.0 * PLAYER_GRAVITY_REF)
	return maxf(h - PLATFORM_LANDING_MARGIN, 64.0)


func _build_ruins() -> void:
	var jump_rise := _max_jump_rise()
	var step_gap := maxf(MIN_PLATFORM_Y_GAP, jump_rise + 28.0)
	print("⬇️ L4 斜向下级距=", snappedf(step_gap, 0.1), " 二连跳≈", snappedf(jump_rise, 0.1))

	# 入口营地 Floor
	_add_floor_span(LEFT_FLOOR_A, LEFT_FLOOR_B, FLOOR_TOP_Y)
	_add_pit_lip(LEFT_FLOOR_B - 8.0, true)

	# —— 斜向下主链（长度×2）：跳板缝 + 叠台井 ——
	# 每项 [x0, w, top_y, goth, edge_spikes, mid_spike]
	var chain: Array = []
	var x_cursor := LEFT_FLOOR_B + 90.0
	var y_cursor := FLOOR_TOP_Y + step_gap
	var zig := 0
	var ladder_wells: Array = [] ## 记录需架梯的 (upper_idx, lower_idx)
	const CHAIN_LEN := 16 ## 现长 24 的 2/3

	for i in range(CHAIN_LEN):
		var w := 240.0 if (i % 3 != 2) else 280.0
		var x0 := x_cursor
		if zig == 1:
			x0 = x_cursor - 70.0
		elif zig == 2:
			x0 = x_cursor + 40.0

		# 每隔 3 步做叠台井：本板与上一板水平重叠，只能爬梯往来（有用）
		var is_well := (i > 0 and i % 3 == 0)
		if is_well:
			var prev: Array = chain[chain.size() - 1]
			var px0 := float(prev[0])
			var pw := float(prev[1])
			x0 = px0 + 40.0
			w = minf(pw - 50.0, 200.0)
			w = maxf(w, LADDER_OVERLAP_MIN + 80.0)

		var goth := (i % 2) == 1
		# 叠台井上下板不放刺；其余非井台尽量放边刺/中刺（_try_add_spike 仍避梯子竖线）
		var spikes := not is_well
		var mid_n := 0
		if not is_well and w >= 180.0:
			mid_n = 1
			if w >= 220.0 and (i % 2 == 0):
				mid_n = 2
			if w >= 260.0 and (i % 3 == 0):
				mid_n = 3
		chain.append([x0, w, y_cursor, goth, spikes, mid_n])
		if is_well:
			ladder_wells.append([chain.size() - 2, chain.size() - 1])
			var up_i := chain.size() - 2
			if up_i >= 0:
				var up_c: Array = chain[up_i]
				chain[up_i] = [up_c[0], up_c[1], up_c[2], up_c[3], false, 0]

		if is_well:
			x_cursor = x0 + w + 90.0
		else:
			var seam := 80.0 + float(i % 3) * 12.0
			x_cursor = x0 + w + seam
		y_cursor += step_gap
		zig = (zig + 1) % 3

	# 先算出所有梯子柱心 X，再铺板/刺，保证尖刺不与梯子同竖向
	_ladder_xs.clear()
	for well in ladder_wells:
		var ui: int = int(well[0])
		var li: int = int(well[1])
		var up: Array = chain[ui]
		var lo: Array = chain[li]
		var u0 := float(up[0])
		var u1 := u0 + float(up[1])
		var l0 := float(lo[0])
		var l1 := l0 + float(lo[1])
		var ov0 := maxf(u0, l0)
		var ov1 := minf(u1, l1)
		if ov1 - ov0 < LADDER_OVERLAP_MIN:
			continue
		var cx := clampf((ov0 + ov1) * 0.5, ov0 + 10.0, ov1 - 10.0)
		_ladder_xs.append(cx)

	for spur_i in [5, 11]:
		if chain.size() <= spur_i:
			continue
		# 支路所连主台去掉中段刺，避免与回爬梯同竖线
		var mid0: Array = chain[spur_i]
		chain[spur_i] = [mid0[0], mid0[1], mid0[2], mid0[3], mid0[4], 0]
		var mx0 := float(mid0[0]) + 30.0
		var mw := 150.0
		var ov0b := maxf(mx0, float(mid0[0]))
		var ov1b := minf(mx0 + mw, float(mid0[0]) + float(mid0[1]))
		if ov1b - ov0b >= LADDER_OVERLAP_MIN:
			_ladder_xs.append((ov0b + ov1b) * 0.5)

	for i in chain.size():
		var c: Array = chain[i]
		_add_platform_span(
			float(c[0]), float(c[0]) + float(c[1]), float(c[2]),
			bool(c[3]), bool(c[4]), i, int(c[5])
		)

	# 按 L1–L3：重叠中心架梯
	var ladder_i := 0
	for well in ladder_wells:
		var ui2: int = int(well[0])
		var li2: int = int(well[1])
		var up2: Array = chain[ui2]
		var lo2: Array = chain[li2]
		var u0b := float(up2[0])
		var u1b := u0b + float(up2[1])
		var ut := float(up2[2])
		var l0b := float(lo2[0])
		var l1b := l0b + float(lo2[1])
		var lt := float(lo2[2])
		var ov0c := maxf(u0b, l0b)
		var ov1c := minf(u1b, l1b)
		if ov1c - ov0c < LADDER_OVERLAP_MIN:
			continue
		if lt - ut <= jump_rise + 1.0:
			continue
		var cx2 := clampf((ov0c + ov1c) * 0.5, ov0c + 10.0, ov1c - 10.0)
		_place_ladder(cx2, ut, lt, minf(u1b - u0b, l1b - l0b), ladder_i)
		ladder_i += 1

	# 两条回爬支路（前半 / 后半各一）——板本身无刺
	for spur_i2 in [5, 11]:
		if chain.size() <= spur_i2:
			continue
		var mid: Array = chain[spur_i2]
		var sx0 := float(mid[0]) + 30.0
		var sw := 150.0
		var sy := float(mid[2])
		var spur_y := sy - (jump_rise + 48.0)
		_add_platform_span(sx0, sx0 + sw, spur_y, true, false, 200 + spur_i2, 0)
		var ov0d := maxf(sx0, float(mid[0]))
		var ov1d := minf(sx0 + sw, float(mid[0]) + float(mid[1]))
		if ov1d - ov0d >= LADDER_OVERLAP_MIN:
			var cx3 := (ov0d + ov1d) * 0.5
			_place_ladder(cx3, spur_y, sy, minf(sw, float(mid[1])), ladder_i)
			ladder_i += 1

	# 底部大厅：主链终点再右下
	var last: Array = chain[chain.size() - 1]
	var bottom_x0 := float(last[0]) + float(last[1]) + 100.0
	var bottom_w := 520.0
	var bottom_y := float(last[2]) + step_gap
	_add_floor_span(bottom_x0, bottom_x0 + bottom_w, bottom_y)
	# 底厅必经道再补几枚刺（同样避梯子竖线）
	for t_hall: float in [0.22, 0.4, 0.58]:
		_try_add_spike(lerpf(bottom_x0, bottom_x0 + bottom_w, t_hall) - SPIKE_W * 0.5, bottom_y)
	set_meta("l4_bottom_floor_y", bottom_y)
	set_meta("l4_bottom_floor_x0", bottom_x0)
	set_meta("l4_bottom_floor_x1", bottom_x0 + bottom_w)

	_world_right = bottom_x0 + bottom_w + 200.0

	# 仅入口左侧挡墙；不封竖井——斜线两侧与板缝都是深渊
	_add_wall_column(WORLD_LEFT, WORLD_LEFT + 40.0, FLOOR_TOP_Y - 80.0, bottom_y + 80.0)

	print("📐 L4 斜链 Platform×", chain.size(), " 梯子×", ladder_i,
		" 世界右=", snappedf(_world_right, 0.1))


func _add_floor_span(x0: float, x1: float, top_y: float) -> void:
	if _painter == null or _ground_tex.is_empty():
		return
	var result: Dictionary = _painter.pave_floor_span(
		_grounds, _ground_tex, x0, x1, top_y, TerrainArtPainter.FLOOR_COLL_H
	)
	var max_h: float = float(result.get("max_h", TerrainArtPainter.FLOOR_MIN_VISUAL_H))
	_note_solid_bottom(top_y, max_h)
	_register_surface(x0, x1, top_y, "floor")


func _add_wall_column(x0: float, x1: float, y_top: float, y_bottom: float) -> void:
	if _painter == null or _ground_tex.is_empty():
		return
	var y := y_top
	var guard := 0
	while y < y_bottom - 4.0 and guard < 100:
		guard += 1
		var result: Dictionary = _painter.pave_floor_span(
			_grounds, _ground_tex, x0, x1, y, TerrainArtPainter.FLOOR_COLL_H
		)
		var step_h: float = maxf(float(result.get("max_h", TerrainArtPainter.FLOOR_MIN_VISUAL_H)), 32.0)
		_note_solid_bottom(y, step_h)
		y += step_h
		if int(result.get("count", 0)) <= 0:
			break


func _add_platform_span(
	x0: float, x1: float, top_y: float, goth: bool, edge_spikes: bool, seed_i: int,
	mid_n: int = 0
) -> void:
	if _painter == null:
		return
	var texs := _goth_tex if goth and not _goth_tex.is_empty() else _plat_tex
	if texs.is_empty():
		texs = _ground_tex
	var visual_h: float = _painter.place_platform_span(
		_platforms, texs, x0, x1, top_y, "Plat_%d" % seed_i
	)
	_note_solid_bottom(top_y, visual_h)
	_register_surface(x0, x1, top_y, "plat")
	if edge_spikes and visual_h > 0.0:
		_try_add_spike(x0 + 8.0, top_y)
		_try_add_spike(x1 - SPIKE_W - 8.0, top_y)
	# 中段地刺 1～3 枚；与梯子同竖线则跳过
	if mid_n >= 1 and visual_h > 0.0:
		_try_add_spike((x0 + x1) * 0.5 - SPIKE_W * 0.5, top_y)
	if mid_n >= 2 and visual_h > 0.0:
		_try_add_spike(lerpf(x0, x1, 0.35) - SPIKE_W * 0.5, top_y)
	if mid_n >= 3 and visual_h > 0.0:
		_try_add_spike(lerpf(x0, x1, 0.65) - SPIKE_W * 0.5, top_y)


## 尖刺左缘 world_x；与任一梯子柱心竖直对齐则不放
func _spike_blocked_by_ladder(spike_left_x: float) -> bool:
	var spike_cx := spike_left_x + SPIKE_W * 0.5
	for lx in _ladder_xs:
		if absf(spike_cx - lx) < LADDER_SPIKE_CLEAR:
			return true
	return false


func _try_add_spike(world_x: float, platform_top_y: float) -> void:
	if _spike_blocked_by_ladder(world_x):
		return
	_add_up_spike_flush(world_x, platform_top_y)


## 与 level_controller._place_one_ladder 同款：根节点挂载 + ladder_XX 轮换贴图
func _place_ladder(
	center_x: float, top_y: float, bottom_y: float, max_plat_len: float, idx: int
) -> void:
	if bottom_y - top_y < LADDER_MIN_HEIGHT:
		return
	var ladder := Area2D.new()
	ladder.name = "LevelLadder_%d" % idx
	ladder.set_script(LADDER_ZONE_SCRIPT)
	add_child(ladder) ## 与 L1–L3 一样挂关卡根，不用 Props 偏移
	if ladder.has_method("setup"):
		var tex_i := (idx * 3 + level_id) % 9
		ladder.call("setup", center_x, top_y, bottom_y, max_plat_len, tex_i)
	print("🪜 L4 梯子#", idx, " x=", snappedf(center_x, 0.1),
		" Y[", snappedf(top_y, 0.1), "→", snappedf(bottom_y, 0.1), "] tex=", (idx * 3 + level_id) % 9)


func _add_pit_lip(x: float, from_left: bool) -> void:
	if _ground_tex.is_empty() or _painter == null:
		return
	var spr := Sprite2D.new()
	spr.texture = _ground_tex[0]
	spr.centered = false
	var info: Dictionary = _painter.analyze_floor_texture(spr.texture)
	var cw := maxf(float(info["content_w"]), 1.0)
	var ch := maxf(float(info["content_h"]), 1.0)
	spr.region_enabled = true
	spr.region_rect = Rect2(float(info["x0"]), float(info["y0"]), cw, ch)
	spr.scale = Vector2(56.0 / cw, 40.0 / ch)
	spr.modulate = Color(0.78, 0.72, 0.68, 0.9)
	spr.position = Vector2(x, FLOOR_TOP_Y - 6.0)
	spr.rotation_degrees = -10.0 if from_left else 12.0
	spr.z_index = 1
	_grounds.add_child(spr)


func _add_up_spike_flush(world_x: float, platform_top_y: float) -> void:
	var spike := SPIKE_SCENE.instantiate() as Area2D
	if spike.has_method("setup"):
		spike.call("setup", true, Vector2(SPIKE_W, SPIKE_H), true)
	spike.position = Vector2(world_x, platform_top_y - SPIKE_H + 2.0)
	spike.z_index = 3
	_hazards.add_child(spike)


func _place_spawn_and_door() -> void:
	var spawn_pos := Vector2(LEFT_FLOOR_A + 48.0, FLOOR_TOP_Y - 32.0)
	var bottom_y := float(get_meta("l4_bottom_floor_y")) if has_meta("l4_bottom_floor_y") else 2560.0
	var bx0 := float(get_meta("l4_bottom_floor_x0")) if has_meta("l4_bottom_floor_x0") else 3000.0
	var bx1 := float(get_meta("l4_bottom_floor_x1")) if has_meta("l4_bottom_floor_x1") else 3600.0
	var door_pos := Vector2((bx0 + bx1) * 0.5, bottom_y - 32.0)

	var spawn := _props.get_node_or_null("SpawnPoint") as Marker2D
	if spawn == null:
		spawn = Marker2D.new()
		spawn.name = "SpawnPoint"
		_props.add_child(spawn)
	spawn.position = spawn_pos
	if not spawn.is_in_group("spawn_point"):
		spawn.add_to_group("spawn_point")

	var door := _props.get_node_or_null("LightDoor") as Area2D
	if door == null:
		door = LIGHT_DOOR_SCENE.instantiate() as Area2D
		door.name = "LightDoor"
		_props.add_child(door)
	door.position = door_pos
	if "next_level_id" in door:
		door.set("next_level_id", 5)
	if not door.is_in_group("light_door"):
		door.add_to_group("light_door")


func _spawn_entities() -> void:
	_spawn_enemies()
	_spawn_foxes()
	_spawn_stars()


## 怪物：沿斜链均布，数量对齐 L2/L3 密度（约 10～12）
func _spawn_enemies() -> void:
	var plats: Array = []
	for s in _surfaces:
		if String(s["kind"]) != "plat":
			continue
		if float(s["x1"]) - float(s["x0"]) < 120.0:
			continue
		plats.append(s)
	var want := mini(18, maxi(plats.size() - 1, 0))
	var enemy_i := 0
	for k in range(want):
		var si := int(floor(float(k) * float(plats.size()) / float(maxi(want, 1))))
		si = clampi(si, 0, plats.size() - 1)
		var p: Dictionary = plats[si]
		var e = ENEMY_SCENE.instantiate()
		e.name = "LevelEnemy_%d" % enemy_i
		e.position = Vector2((float(p["x0"]) + float(p["x1"])) * 0.5, float(p["top"]) - 40.0)
		_enemies.add_child(e)
		if e.has_method("set_patrol_island"):
			e.set_patrol_island(float(p["x0"]), float(p["x1"]), 28.0)
		enemy_i += 1
	print("👾 L4 怪 ×", enemy_i)


## LanternFox：前/中/后均布；蓝光落点强制用主链必经站立面
func _spawn_foxes() -> void:
	var jump_rise := _max_jump_rise()
	var fox_amp := 16.0
	var max_above := maxf(jump_rise - fox_amp - 8.0, 48.0)
	var fox_above := minf(72.0, max_above * 0.55)

	# 必经落点：主链每块站立面取多个点（避开梯子竖线），供蓝光优先砸在玩家必经道上
	var path_pts: Array[Vector2] = []
	for s in _surfaces:
		var a: float = float(s["x0"])
		var b: float = float(s["x1"])
		var top: float = float(s["top"])
		if b - a < 80.0:
			continue
		var samples: Array = [0.22, 0.5, 0.78] if b - a >= 160.0 else [0.4, 0.7]
		for t in samples:
			var px := lerpf(a, b, float(t))
			if _spike_blocked_by_ladder(px - SPIKE_W * 0.5):
				continue
			path_pts.append(Vector2(px, top - 2.0))

	var anchors: Array = []
	for s2 in _surfaces:
		if float(s2["x1"]) - float(s2["x0"]) < 160.0:
			continue
		anchors.append(s2)
	if anchors.is_empty():
		return
	var fox_want := 3
	var fox_n := 0
	for k in range(fox_want):
		var si := int(floor(float(k) * float(anchors.size()) / float(fox_want)))
		si = clampi(si, 0, anchors.size() - 1)
		var a2: Dictionary = anchors[si]
		var top2 := float(a2["top"])
		var fox = FOX_SCENE.instantiate()
		fox.name = "LevelFox_%d" % fox_n
		fox.position = Vector2((float(a2["x0"]) + float(a2["x1"])) * 0.5, top2 - fox_above)
		_enemies.add_child(fox)
		if fox.has_method("clamp_hover_to_double_jump"):
			fox.call("clamp_hover_to_double_jump", top2, jump_rise)
		if fox.has_method("set_charm_path_points"):
			fox.call("set_charm_path_points", path_pts)
		fox_n += 1
	print("🦊 L4 狐妖 ×", fox_n, " 蓝光必经点×", path_pts.size())


## 星星：scale/分段分配同 L1–L3（前中后桶 + 最小间距）
func _spawn_stars() -> void:
	if _surfaces.is_empty():
		return
	var candidates: Array[Vector2] = []
	var x_lo := INF
	var x_hi := -INF
	for s in _surfaces:
		var a: float = float(s["x0"])
		var b: float = float(s["x1"])
		var top: float = float(s["top"])
		if b - a < 48.0:
			continue
		x_lo = minf(x_lo, a)
		x_hi = maxf(x_hi, b)
		var x0 := a + 16.0
		var x1 := b - 16.0
		if x1 <= x0:
			continue
		for _k in range(2):
			candidates.append(Vector2(randf_range(x0, x1), top - randf_range(36.0, 58.0)))

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
	var per_bucket := 2 ## 接近 L2
	for bi3 in range(3):
		var got := 0
		for cpos2 in buckets[bi3]:
			if got >= per_bucket or placed.size() >= STAR_COUNT:
				break
			if not _star_sep_ok(cpos2, placed):
				continue
			_place_star(cpos2, placed.size())
			placed.append(cpos2)
			got += 1

	if placed.size() < STAR_COUNT:
		var rest: Array[Vector2] = []
		for bi4 in range(3):
			for cpos3 in buckets[bi4]:
				rest.append(cpos3)
		rest.shuffle()
		for cpos4 in rest:
			if placed.size() >= STAR_COUNT:
				break
			if not _star_sep_ok(cpos4, placed):
				continue
			_place_star(cpos4, placed.size())
			placed.append(cpos4)

	print("⭐ L4 星星 ×", placed.size(), "/", STAR_COUNT, " scale=", STAR_SCALE)


func _star_sep_ok(cpos: Vector2, placed: Array[Vector2]) -> bool:
	for p in placed:
		if cpos.distance_to(p) < STAR_MIN_SEP:
			return false
	return true


func _place_star(cpos: Vector2, idx: int) -> void:
	var star = LIGHT_ORB_SCENE.instantiate()
	star.name = "LevelStar_%d" % idx
	star.scale = STAR_SCALE
	star.position = cpos
	_props.add_child(star)


func _ensure_killzone() -> void:
	var legacy := get_node_or_null("AbyssKillZone")
	if legacy:
		legacy.queue_free()
	var kill := get_node_or_null("KillZone") as Area2D
	if kill == null:
		kill = Area2D.new()
		kill.set_script(KILL_ZONE_SCRIPT)
		kill.name = "KillZone"
		add_child(kill)

	# 边界 = LightDoor 下方 100px；触碰 → reset_level → 回出生点
	var door_y := _lowest_solid_y
	if has_meta("l4_bottom_floor_y"):
		door_y = float(get_meta("l4_bottom_floor_y")) - 32.0
	var door := _props.get_node_or_null("LightDoor") as Node2D
	if door == null:
		door = get_node_or_null("LightDoor") as Node2D
	if door:
		door_y = door.position.y
	var death_top := door_y + DEATH_BELOW_DOOR
	if kill.has_method("setup_span"):
		kill.call("setup_span", WORLD_LEFT - 400.0, _world_right + 400.0, death_top, 900.0)
	print("💀 L4 边界=LightDoor.y+", DEATH_BELOW_DOOR, " → top=", snappedf(death_top, 0.1),
		" (door_y=", snappedf(door_y, 0.1), ")")


func _boot_player_at_spawn() -> void:
	var spawn := get_node_or_null("Level_Props/SpawnPoint") as Marker2D
	var spawn_pos := Vector2(LEFT_FLOOR_A + 48.0, FLOOR_TOP_Y - 32.0)
	if spawn:
		spawn_pos = spawn.global_position
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		player = PLAYER_SCENE.instantiate()
		add_child(player)
	if player.has_method("reset_at_spawn"):
		player.reset_at_spawn(spawn_pos)
	else:
		player.global_position = spawn_pos
		if "velocity" in player:
			player.velocity = Vector2.ZERO


func _sync_atmosphere() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("apply_level_brightness"):
		gm.apply_level_brightness(level_id, 1.2)


func _sync_backdrop_horizon() -> void:
	var bg := get_node_or_null("ParallaxBackdrop")
	if bg == null:
		return
	if bg.has_method("set_horizon_from_ground_top"):
		bg.set_horizon_from_ground_top(FLOOR_TOP_Y)
	if bg.has_method("set_floor_coverage_segments") and not _floor_segments.is_empty():
		bg.set_floor_coverage_segments(_floor_segments)
