extends Node2D
## Level 5「极限逃生」
## 入口崩塌追赶 → 怪物猎场（影子调虎离山）→ 极限终跳 + LightDoor
## 地形贴图 = L1–L4 同款 TerrainArtPainter；尖刺 = Spike.tscn；怪 = enemy.tscn

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
const COLLAPSE_SCRIPT = preload("res://levels/level_05/collapsing_floor.gd")
const PHANTOM_SCRIPT = preload("res://levels/level_05/phantom_platform.gd")
const TerrainArtPainter = preload("res://levels/terrain_art_painter.gd")

const FLOOR_TOP_Y := 256.0
const SPIKE_W := 40.0
const SPIKE_H := 32.0
## 助跑极限单跳水平跨度（max_speed≈200, jump≈456, g≈1000）
const FINAL_GAP := 186.0
const DEATH_BELOW := 120.0
const WORLD_LEFT := -80.0
## 与当前猎场岛距一致，且不超过 L1–L3 的 PLATFORM_MAX_X_GAP(88)
const ISLAND_GAP := 56.0
const HOP_PLAT_W := 72.0
const SCATTER_PLAT_W := 66.0
const STAR_SCALE := Vector2(0.03, 0.03)
const STAR_COUNT := 3 ## 每关三颗，前中后桶随机
const STAR_MIN_SEP := 360.0 ## 太近不要
const STAR_MAX_SEP := 2200.0 ## 太远不要（关长×2 后仍落在相邻桶内）

@export var level_id: int = 5
@export var use_parallax_backdrop: bool = true
@export var collapse_chain_delay: float = 0.55 ## 略快于奔跑追赶感（段宽≈150 时）
@export var collapse_segment_w: float = 150.0

var _grounds: Node2D
var _platforms: Node2D
var _hazards: Node2D
var _enemies: Node2D
var _props: Node2D
var _painter = null
var _ground_tex: Array[Texture2D] = []
var _plat_tex: Array[Texture2D] = []
var _goth_tex: Array[Texture2D] = []
var _world_right: float = 3200.0
var _lowest_y: float = FLOOR_TOP_Y
var _collapse_segments: Array = [] ## collapsing_floor 节点
var _collapse_started: bool = false
## 平台记录供刷怪 {name,x0,x1,top}
var _hunt_plats: Array = []
var _gate_plat: Dictionary = {}
var _final_plat: Dictionary = {}
var _surfaces: Array = [] ## {x0,x1,top,kind}
var _fox_anchors: Array = [] ## 较大站立面，供狐妖
var _plat_seq: int = 0
var _entrance_x0: float = 0.0
var _entrance_x1: float = 320.0
var _collapse_x0: float = 320.0
var _collapse_x1: float = 1100.0


func _ready() -> void:
	var lm := get_node_or_null("/root/LevelManager")
	if lm:
		lm.current_level_id = level_id

	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
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

	_build_escape()
	_place_spawn_and_door()
	_spawn_enemies()
	_spawn_foxes()
	_spawn_stars()
	_ensure_killzone()
	call_deferred("_boot_player_at_spawn")
	call_deferred("_sync_atmosphere")
	call_deferred("_sync_backdrop_horizon")
	call_deferred("_try_start_prologue")
	print("🚨 L5 极限逃生 | 崩塌段×", _collapse_segments.size(),
		" 猎场台×", _hunt_plats.size(), " 表面×", _surfaces.size())


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
	_grounds = _ensure_child("Level_Grounds")
	_platforms = _ensure_child("Level_Platforms")
	_hazards = _ensure_child("Level_Hazards")
	_enemies = _ensure_child("Level_Enemies")
	_props = _ensure_child("Level_Props")


func _ensure_child(n: String) -> Node2D:
	var node := get_node_or_null(n) as Node2D
	if node == null:
		node = Node2D.new()
		node.name = n
		add_child(node)
	return node


func _max_jump_rise() -> float:
	return (456.0 * 456.0 + 420.0 * 420.0) / (2.0 * 1000.0)


func _build_escape() -> void:
	_collapse_segments.clear()
	_hunt_plats.clear()
	_surfaces.clear()
	_fox_anchors.clear()
	_plat_seq = 0

	# —— 1) 入口短 Floor（碎裂观感：偏暗橙）——
	_entrance_x0 = 0.0
	_entrance_x1 = 300.0
	_add_floor_span("Floor_Entrance", _entrance_x0, _entrance_x1, FLOOR_TOP_Y, Color(1.35, 1.05, 0.9, 1.0))

	# —— 崩塌段：只铺 3 块会消失的板；冲刺最后一块固定保留 ——
	_collapse_x0 = _entrance_x1
	var n_seg := 3
	var x := _collapse_x0
	for i in range(n_seg):
		var x1 := x + collapse_segment_w
		_add_collapsing_floor(i + 1, x, x1, FLOOR_TOP_Y)
		x = x1
	_collapse_x1 = x

	# 冲刺落脚板：不崩塌，衔接下一段猎场
	var land_x0 := _collapse_x1
	var land_x1 := land_x0 + 220.0
	_add_floor_span("Floor_Sprint_End", land_x0, land_x1, FLOOR_TOP_Y)

	# 崩塌底即死尖刺带：只铺在会消失的板下方，不铺到落脚板
	var pit_y := FLOOR_TOP_Y + 96.0
	_fill_spikes_row(_collapse_x0 - 20.0, _collapse_x1 + 8.0, pit_y, "Spike_Collapse_Bottom")
	_lowest_y = maxf(_lowest_y, pit_y + SPIKE_H)

	# 触发区：入口末段
	_add_collapse_trigger(_entrance_x1 - 80.0, _entrance_x1 + 40.0, FLOOR_TOP_Y - 80.0, 120.0)

	# —— 2) 中段猎场 Platforms（空隙约一跳；边刺会吃落点，几何间距再收）——
	var hunt_y0 := FLOOR_TOP_Y - 20.0
	var hx := land_x1 + ISLAND_GAP
	var p1 := _add_platform("Platform_Hunt_01", hx, hx + 200.0, hunt_y0, false, true)
	_hunt_plats.append(p1)
	hx = float(p1["x1"]) + ISLAND_GAP
	var p2 := _add_platform("Platform_Hunt_02", hx, hx + 180.0, hunt_y0 - 28.0, true, true)
	_hunt_plats.append(p2)
	hx = float(p2["x1"]) + ISLAND_GAP
	var p3 := _add_platform("Platform_Hunt_03", hx, hx + 210.0, hunt_y0 + 4.0, false, true)
	_hunt_plats.append(p3)
	hx = float(p3["x1"]) + ISLAND_GAP
	var p4 := _add_platform("Platform_Hunt_04", hx, hx + 190.0, hunt_y0 - 22.0, true, true)
	_hunt_plats.append(p4)

	# —— 关长×2：hop / scatter 岛链（板缝=ISLAND_GAP，高差≤二连跳，小跳板不放边刺）——
	var cursor := float(p4["x1"])
	cursor = _add_hop_chain(cursor, hunt_y0, 0, 2)
	cursor = _add_rest_island(cursor, hunt_y0 - 6.0, 180.0, false)
	cursor = _add_scatter_chain(cursor, 780.0, hunt_y0, 1)
	cursor = _add_rest_island(cursor, hunt_y0 - 12.0, 200.0, true)
	cursor = _add_hop_chain(cursor, hunt_y0, 2, 2)
	cursor = _add_scatter_chain(cursor, 720.0, hunt_y0, 3)
	cursor = _add_rest_island(cursor, hunt_y0 - 8.0, 180.0, true)

	# —— 闪现平台 + 影子时间校准（不改前面段落，只追加）——
	cursor = _add_phantom_platform_gate(cursor, hunt_y0 - 8.0)

	# —— 守门台 ——
	hx = cursor + ISLAND_GAP
	_gate_plat = _add_platform("Platform_Gatekeeper", hx, hx + 200.0, hunt_y0 - 8.0, false, false)

	# —— 3) 极限终跳 ——
	var leap_from_x1 := float(_gate_plat["x1"])
	var final_x0 := leap_from_x1 + FINAL_GAP
	var final_w := 260.0
	var final_y := float(_gate_plat["top"])
	_final_plat = _add_platform("Platform_Final", final_x0, final_x0 + final_w, final_y, true, false)
	# 终点两侧朝内尖刺（左右边），中央安全
	_add_up_spike(final_x0 + 6.0, final_y, "Spike_Final_Left")
	_add_up_spike(final_x0 + 6.0 + SPIKE_W + 2.0, final_y, "Spike_Final_Left2")
	_add_up_spike(final_x0 + final_w - SPIKE_W - 6.0, final_y, "Spike_Final_Right")
	_add_up_spike(final_x0 + final_w - SPIKE_W * 2.0 - 8.0, final_y, "Spike_Final_Right2")

	_world_right = final_x0 + final_w + 200.0
	_lowest_y = maxf(_lowest_y, final_y + 200.0)

	# 左侧挡墙，防跑出世界
	_add_wall_column(WORLD_LEFT, WORLD_LEFT + 36.0, FLOOR_TOP_Y - 100.0, pit_y + 200.0)


func _add_floor_span(fname: String, x0: float, x1: float, top_y: float, tint: Color = Color.WHITE) -> void:
	if _painter == null or _ground_tex.is_empty():
		return
	var host := Node2D.new()
	host.name = fname
	_grounds.add_child(host)
	var result: Dictionary = _painter.pave_floor_span(
		host, _ground_tex, x0, x1, top_y, TerrainArtPainter.FLOOR_COLL_H
	)
	_tint_under(host, tint)
	_lowest_y = maxf(_lowest_y, top_y + float(result.get("max_h", 48.0)))
	_register_surface(x0, x1, top_y, "floor")


func _add_collapsing_floor(idx: int, x0: float, x1: float, top_y: float) -> void:
	var seg := Node2D.new()
	seg.name = "CollapsingFloor_%02d" % idx
	seg.set_script(COLLAPSE_SCRIPT)
	_grounds.add_child(seg)
	var result: Dictionary = _painter.pave_floor_span(
		seg, _ground_tex, x0, x1, top_y, TerrainArtPainter.FLOOR_COLL_H
	)
	_tint_under(seg, Color(1.4, 1.0, 0.85, 1.0))
	# 找到刚铺的 StaticBody
	var body: StaticBody2D = null
	for ch in seg.get_children():
		if ch is StaticBody2D:
			body = ch as StaticBody2D
			break
	if seg.has_method("setup_body"):
		seg.call("setup_body", body, body.get_node_or_null("FloorVisuals") if body else null)
	_collapse_segments.append(seg)
	_lowest_y = maxf(_lowest_y, top_y + float(result.get("max_h", 48.0)))


func _tint_under(root: Node, tint: Color) -> void:
	if tint == Color.WHITE:
		return
	for n in root.find_children("*", "Sprite2D", true, false):
		if n is Sprite2D:
			(n as Sprite2D).modulate = (n as Sprite2D).modulate * tint


func _add_collapse_trigger(x0: float, x1: float, y: float, h: float) -> void:
	var area := Area2D.new()
	area.name = "CollapseTrigger"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = false
	_grounds.add_child(area)
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(maxf(x1 - x0, 32.0), h)
	cs.shape = rect
	cs.position = Vector2((x0 + x1) * 0.5, y + h * 0.5)
	area.add_child(cs)
	area.body_entered.connect(_on_collapse_trigger)


func _on_collapse_trigger(body: Node2D) -> void:
	if _collapse_started:
		return
	if body == null or not body.is_in_group("player"):
		return
	_collapse_started = true
	print("💥 L5 崩塌连锁启动")
	_run_collapse_chain()


func _run_collapse_chain() -> void:
	for i in range(_collapse_segments.size()):
		var seg = _collapse_segments[i]
		if is_instance_valid(seg) and seg.has_method("begin_collapse"):
			seg.call("begin_collapse")
		if i < _collapse_segments.size() - 1:
			await get_tree().create_timer(collapse_chain_delay).timeout


func _add_platform(
	pname: String, x0: float, x1: float, top_y: float, goth: bool, edge_spikes: bool
) -> Dictionary:
	var texs := _goth_tex if goth and not _goth_tex.is_empty() else _plat_tex
	if texs.is_empty():
		texs = _ground_tex
	var host := Node2D.new()
	host.name = pname
	_platforms.add_child(host)
	var h: float = _painter.place_platform_span(host, texs, x0, x1, top_y, pname)
	_lowest_y = maxf(_lowest_y, top_y + maxf(h, 40.0))
	if edge_spikes:
		_add_up_spike(x0 + 6.0, top_y, "Spike_%s_L" % pname)
		_add_up_spike(x1 - SPIKE_W - 6.0, top_y, "Spike_%s_R" % pname)
	var rec := {"name": pname, "x0": x0, "x1": x1, "top": top_y}
	_register_surface(x0, x1, top_y, "plat")
	if x1 - x0 >= 160.0:
		_fox_anchors.append(rec)
	return rec


func _register_surface(x0: float, x1: float, top: float, kind: String) -> void:
	_surfaces.append({"x0": x0, "x1": x1, "top": top, "kind": kind})


## hop：1～2 块短跳板，缝=ISLAND_GAP，高差≤二连跳
func _add_hop_chain(prev_x1: float, base_y: float, seed_i: int, hops: int = 2) -> float:
	var max_h := maxf(_max_jump_rise() - 8.0, 48.0)
	var x := prev_x1
	var rise := clampf(36.0 + float(seed_i % 3) * 8.0, 28.0, max_h)
	var deltas: Array[float] = [16.0, -12.0, 18.0, -14.0]
	for i in range(hops):
		x += ISLAND_GAP
		var top := base_y - rise
		_plat_seq += 1
		_add_platform("Platform_Hop_%d" % _plat_seq, x, x + HOP_PLAT_W, top, ((seed_i + i) % 2) == 1, false)
		x += HOP_PLAT_W
		rise = clampf(rise + deltas[(i + seed_i) % deltas.size()], 28.0, max_h)
	return x


## scatter：一串可跳跳板，铺满 span_w（板缝钳在 ISLAND_GAP）
func _add_scatter_chain(prev_x1: float, span_w: float, base_y: float, seed_i: int) -> float:
	var max_h := maxf(_max_jump_rise() - 8.0, 48.0)
	var x0 := prev_x1 + ISLAND_GAP
	var pw := SCATTER_PLAT_W
	var n := int(floor((span_w + ISLAND_GAP) / (pw + ISLAND_GAP)))
	n = clampi(n, 3, 12)
	var rise := clampf(40.0 + float(seed_i % 4) * 6.0, 28.0, max_h)
	var deltas: Array[float] = [18.0, -14.0, 22.0, -16.0, 20.0, -12.0]
	var x := x0
	for i in range(n):
		var top := base_y - rise
		_plat_seq += 1
		_add_platform("Platform_Scatter_%d" % _plat_seq, x, x + pw, top, ((seed_i + i) % 2) == 0, false)
		x += pw
		if i < n - 1:
			x += ISLAND_GAP
		rise = clampf(rise + deltas[(i + seed_i) % deltas.size()], 28.0, max_h)
	return x


func _add_rest_island(prev_x1: float, top_y: float, w: float, goth: bool) -> float:
	var x0 := prev_x1 + ISLAND_GAP
	_plat_seq += 1
	_add_platform("Platform_Rest_%d" % _plat_seq, x0, x0 + w, top_y, goth, false)
	return x0 + w


## 闪现平台闸门：起跳侧 3 秒跑距 Floor + 0.7 最大跳距深渊 + 闪现板 + 对岸
## 贴图/碰撞走 TerrainArtPainter；周期 2s 实 / 3s 隐，与影子回溯 3s 对齐
func _add_phantom_platform_gate(prev_x1: float, top_y: float) -> float:
	var max_jump_x := (2.0 * 456.0 / 1000.0) * 200.0 ## 助跑单跳水平
	var abyss_jump := max_jump_x * 0.7
	var start_w := 200.0 * 3.0 ## 3 秒奔跑，回溯刚好回到边缘
	var plat_w := 104.0
	var end_w := 240.0
	var x0 := prev_x1 + ISLAND_GAP
	var start_x1 := x0 + start_w
	var phantom_x0 := start_x1 + abyss_jump
	var phantom_x1 := phantom_x0 + plat_w
	var end_x0 := phantom_x1 + abyss_jump
	var end_x1 := end_x0 + end_w

	var gate := Node2D.new()
	gate.name = "PhantomPlatformGate"
	add_child(gate)

	_add_floor_span_under(gate, "Floor_Start", x0, start_x1, top_y)
	_add_floor_span_under(gate, "Floor_End", end_x0, end_x1, top_y)

	var phantom := Node2D.new()
	phantom.name = "PhantomPlatform"
	phantom.set_script(PHANTOM_SCRIPT)
	gate.add_child(phantom)
	var texs := _goth_tex if not _goth_tex.is_empty() else _plat_tex
	if texs.is_empty():
		texs = _ground_tex
	_painter.place_platform_span(phantom, texs, phantom_x0, phantom_x1, top_y, "PhantomPlat")
	# 不登记站立面：消失时不能当星星/狐妖落点

	var glow := _make_phantom_glow(Vector2((phantom_x0 + phantom_x1) * 0.5, top_y), plat_w)
	phantom.add_child(glow)
	if phantom.has_method("setup_from_painted"):
		phantom.call("setup_from_painted")

	var spike_y := top_y + 96.0
	var spikes_host := Node2D.new()
	spikes_host.name = "AbyssSpikes"
	gate.add_child(spikes_host)
	_fill_spikes_row_under(spikes_host, start_x1 - 8.0, end_x0 + 8.0, spike_y, "Spike_PhantomAbyss")
	_lowest_y = maxf(_lowest_y, spike_y + SPIKE_H)

	var red := PointLight2D.new()
	red.name = "AbyssWarnLight"
	red.color = Color(1.0, 0.18, 0.12, 1.0)
	red.energy = 0.55
	red.texture_scale = 1.4
	red.position = Vector2((start_x1 + end_x0) * 0.5, spike_y - 10.0)
	red.z_index = 2
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for px in range(64):
		for py in range(64):
			var d := Vector2(px - 31.5, py - 31.5).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(px, py, Color(1, 0.2, 0.1, a * a))
	var tex := ImageTexture.create_from_image(img)
	red.texture = tex
	gate.add_child(red)

	var helper := Node2D.new()
	helper.name = "TimingHelper"
	helper.visible = false ## 仅调试：在编辑器里打开可见即可看倒计时
	gate.add_child(helper)
	var lab := Label.new()
	lab.name = "Countdown"
	lab.position = Vector2(phantom_x0, top_y - 48.0)
	lab.add_theme_font_size_override("font_size", 14)
	helper.add_child(lab)
	helper.set_process(true)
	helper.set_meta("plat", phantom)
	helper.set_script(load("res://levels/level_05/phantom_timing_helper.gd"))

	var pit := Area2D.new()
	pit.name = "DeathZone"
	pit.set_script(KILL_ZONE_SCRIPT)
	gate.add_child(pit)
	if pit.has_method("setup_span"):
		pit.call("setup_span", start_x1, end_x0, spike_y + 36.0, 280.0)

	print("👻 L5 闪现平台 起跳Floor=", snappedf(start_w, 1),
		" 深渊跳=", snappedf(abyss_jump, 1), " 板宽=", plat_w)
	return end_x1


func _add_floor_span_under(parent: Node2D, fname: String, x0: float, x1: float, top_y: float) -> void:
	if _painter == null or _ground_tex.is_empty():
		return
	var host := Node2D.new()
	host.name = fname
	parent.add_child(host)
	var result: Dictionary = _painter.pave_floor_span(
		host, _ground_tex, x0, x1, top_y, TerrainArtPainter.FLOOR_COLL_H
	)
	_lowest_y = maxf(_lowest_y, top_y + float(result.get("max_h", 48.0)))
	_register_surface(x0, x1, top_y, "floor")


func _fill_spikes_row_under(parent: Node2D, x0: float, x1: float, top_y: float, prefix: String) -> void:
	var x := x0
	var i := 0
	while x + SPIKE_W <= x1 + 1.0:
		var spike := SPIKE_SCENE.instantiate() as Area2D
		spike.name = "%s_%d" % [prefix, i]
		if spike.has_method("setup"):
			spike.call("setup", true, Vector2(SPIKE_W, SPIKE_H), true)
		spike.position = Vector2(x, top_y - SPIKE_H + 2.0)
		spike.z_index = 3
		parent.add_child(spike)
		x += SPIKE_W - 4.0
		i += 1


func _make_phantom_glow(center: Vector2, plat_w: float) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "GlowEffect"
	p.emitting = false
	p.amount = 28
	p.lifetime = 0.55
	p.position = center
	p.z_index = 4
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(plat_w * 0.42, 3.0, 1.0)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 50.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 26.0
	mat.gravity = Vector3(0, -30, 0)
	mat.scale_min = 0.35
	mat.scale_max = 1.05
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(0.55, 0.85, 1.0, 0.75),
		Color(0.35, 0.55, 1.0, 0.0)
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	mat.color_ramp = ramp
	p.process_material = mat
	var pimg := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	pimg.fill(Color(0.7, 0.9, 1.0, 0.9))
	p.texture = ImageTexture.create_from_image(pimg)
	return p


func _add_up_spike(world_x: float, platform_top_y: float, sname: String = "Spike") -> void:
	var spike := SPIKE_SCENE.instantiate() as Area2D
	spike.name = sname
	if spike.has_method("setup"):
		spike.call("setup", true, Vector2(SPIKE_W, SPIKE_H), true)
	spike.position = Vector2(world_x, platform_top_y - SPIKE_H + 2.0)
	spike.z_index = 3
	_hazards.add_child(spike)


func _fill_spikes_row(x0: float, x1: float, top_y: float, prefix: String) -> void:
	var x := x0
	var i := 0
	while x + SPIKE_W <= x1 + 1.0:
		_add_up_spike(x, top_y, "%s_%d" % [prefix, i])
		x += SPIKE_W - 4.0
		i += 1


func _add_wall_column(x0: float, x1: float, y_top: float, y_bottom: float) -> void:
	if _painter == null or _ground_tex.is_empty():
		return
	var y := y_top
	var guard := 0
	while y < y_bottom - 4.0 and guard < 80:
		guard += 1
		var result: Dictionary = _painter.pave_floor_span(
			_grounds, _ground_tex, x0, x1, y, TerrainArtPainter.FLOOR_COLL_H
		)
		var step_h: float = maxf(float(result.get("max_h", 32.0)), 32.0)
		y += step_h
		if int(result.get("count", 0)) <= 0:
			break


func _place_spawn_and_door() -> void:
	# 玩家在关卡最开头入口
	var spawn_pos := Vector2(_entrance_x0 + 56.0, FLOOR_TOP_Y - 32.0)
	var spawn := _props.get_node_or_null("SpawnPoint") as Marker2D
	if spawn == null:
		spawn = Marker2D.new()
		spawn.name = "SpawnPoint"
		_props.add_child(spawn)
	spawn.position = spawn_pos
	if not spawn.is_in_group("spawn_point"):
		spawn.add_to_group("spawn_point")

	var fx0 := float(_final_plat.get("x0", 2000.0))
	var fx1 := float(_final_plat.get("x1", 2260.0))
	var ftop := float(_final_plat.get("top", FLOOR_TOP_Y))
	var door_pos := Vector2((fx0 + fx1) * 0.5, ftop - 32.0)
	var door := _props.get_node_or_null("LightDoor") as Area2D
	if door == null:
		door = LIGHT_DOOR_SCENE.instantiate() as Area2D
		door.name = "LightDoor"
		_props.add_child(door)
	door.position = door_pos
	# 通关：发完成信号并回到第 1 关（与 LevelManager.load_next_level 一致）
	if "next_level_id" in door:
		door.set("next_level_id", 1)
	if not door.is_in_group("light_door"):
		door.add_to_group("light_door")
	# 过门时补发 level_completed
	if not door.body_entered.is_connected(_on_door_entered_completed):
		door.body_entered.connect(_on_door_entered_completed)


func _on_door_entered_completed(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	var lm := get_node_or_null("/root/LevelManager")
	if lm and lm.has_signal("level_completed"):
		lm.emit_signal("level_completed", level_id)


func _spawn_enemies() -> void:
	# 猎场 4 只
	var names := ["BaseEnemy_Hunt_01", "BaseEnemy_Hunt_02", "BaseEnemy_Hunt_03", "BaseEnemy_Hunt_04"]
	for i in range(mini(4, _hunt_plats.size())):
		var p: Dictionary = _hunt_plats[i]
		_spawn_one_enemy(names[i], p)
	# 守门怪
	if not _gate_plat.is_empty():
		_spawn_one_enemy("BaseEnemy_Gatekeeper", _gate_plat)
	print("👾 L5 怪 ×", _enemies.get_child_count())


func _spawn_one_enemy(ename: String, p: Dictionary) -> void:
	var e = ENEMY_SCENE.instantiate()
	e.name = ename
	e.position = Vector2((float(p["x0"]) + float(p["x1"])) * 0.5, float(p["top"]) - 40.0)
	_enemies.add_child(e)
	if e.has_method("set_patrol_island"):
		e.set_patrol_island(float(p["x0"]), float(p["x1"]), 24.0)


func _spawn_foxes() -> void:
	if _fox_anchors.is_empty():
		return
	var jump_rise := _max_jump_rise()
	var path_pts: Array[Vector2] = []
	for s in _surfaces:
		var a: float = float(s["x0"])
		var b: float = float(s["x1"])
		var top: float = float(s["top"])
		if b - a < 80.0:
			continue
		var samples: Array = [0.3, 0.7] if b - a >= 140.0 else [0.5]
		for t in samples:
			path_pts.append(Vector2(lerpf(a, b, float(t)), top - 2.0))
	var fox_want := mini(3, _fox_anchors.size())
	var fox_n := 0
	for k in range(fox_want):
		var si := int(floor(float(k) * float(_fox_anchors.size()) / float(fox_want)))
		si = clampi(si, 0, _fox_anchors.size() - 1)
		var a2: Dictionary = _fox_anchors[si]
		var top2 := float(a2["top"])
		var fox = FOX_SCENE.instantiate()
		fox.name = "LevelFox_%d" % fox_n
		fox.position = Vector2((float(a2["x0"]) + float(a2["x1"])) * 0.5, top2 - 64.0)
		_enemies.add_child(fox)
		if fox.has_method("clamp_hover_to_double_jump"):
			fox.call("clamp_hover_to_double_jump", top2, jump_rise)
		if fox.has_method("set_charm_path_points"):
			fox.call("set_charm_path_points", path_pts)
		fox_n += 1
	print("🦊 L5 狐妖 ×", fox_n)


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
		candidates.append(Vector2(randf_range(a + 12.0, b - 12.0), top - randf_range(36.0, 58.0)))
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
	for bi3 in range(3):
		for cpos2 in buckets[bi3]:
			if placed.size() >= STAR_COUNT:
				break
			if not _star_sep_ok(cpos2, placed):
				continue
			_place_star(cpos2, placed.size())
			placed.append(cpos2)
			break
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
	print("⭐ L5 星星 ×", placed.size(), "/", STAR_COUNT)


func _star_sep_ok(cpos: Vector2, placed: Array[Vector2]) -> bool:
	if placed.is_empty():
		return true
	var nearest := INF
	for p in placed:
		var d := cpos.distance_to(p)
		if d < STAR_MIN_SEP:
			return false
		nearest = minf(nearest, d)
	if nearest > STAR_MAX_SEP:
		return false
	return true


func _place_star(cpos: Vector2, idx: int) -> void:
	var star = LIGHT_ORB_SCENE.instantiate()
	star.name = "LevelStar_%d" % idx
	star.scale = STAR_SCALE
	star.position = cpos
	_props.add_child(star)


func _ensure_killzone() -> void:
	var legacy := get_node_or_null("DeathZone")
	if legacy and legacy.get_script() == null:
		legacy.set_script(KILL_ZONE_SCRIPT)
	var kill := get_node_or_null("KillZone") as Area2D
	if kill == null:
		kill = get_node_or_null("DeathZone") as Area2D
	if kill == null:
		kill = Area2D.new()
		kill.set_script(KILL_ZONE_SCRIPT)
		kill.name = "DeathZone"
		add_child(kill)
	var door_y := float(_final_plat.get("top", FLOOR_TOP_Y))
	var death_top := maxf(_lowest_y, door_y) + DEATH_BELOW
	if kill.has_method("setup_span"):
		kill.call("setup_span", WORLD_LEFT - 200.0, _world_right + 200.0, death_top, 900.0)
	print("💀 L5 DeathZone top=", snappedf(death_top, 0.1))


func _boot_player_at_spawn() -> void:
	var spawn := get_node_or_null("Level_Props/SpawnPoint") as Marker2D
	var spawn_pos := Vector2(_entrance_x0 + 56.0, FLOOR_TOP_Y - 32.0)
	if spawn:
		spawn_pos = spawn.global_position
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		player = PLAYER_SCENE.instantiate()
		player.name = "Player"
		add_child(player)
	# 强制放到关卡开头入口
	if player.has_method("reset_at_spawn"):
		player.reset_at_spawn(spawn_pos)
	else:
		player.global_position = spawn_pos
		if "velocity" in player:
			player.velocity = Vector2.ZERO
	print("📍 L5 玩家置于入口开头 ", spawn_pos)


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
	if bg.has_method("set_floor_coverage_segments"):
		bg.set_floor_coverage_segments([Vector2(_entrance_x0, _collapse_x1 + 220.0)])
