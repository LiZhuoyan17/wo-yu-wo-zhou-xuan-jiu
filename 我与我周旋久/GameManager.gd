extends Node
## ==================== Day 8：GameManager 全局单例 ====================
## 挂载方式：项目设置 → 全局（Autoload）→ 路径选本脚本，名称填 GameManager
## 之后任意脚本可直接调用：GameManager.reset_level() / pause_game() 等

# -------------------- 全局状态 --------------------
enum GameState {
	MENU,      # 主界面（预留）
	PLAYING,   # 游戏中
	PAUSED,    # 暂停
	DEAD       # 死亡
}

var current_state: GameState = GameState.MENU

# 主关卡场景路径（与 LevelManager 第 1 关一致；旧 Main.tscn 仍可手动打开）
@export var main_scene_path: String = "res://levels/Level_01.tscn"
const MENU_SCENE_PATH := "res://ui/main_menu/MainMenu.tscn"
const LEVEL_SELECT_PATH := "res://ui/level_select/LevelSelect.tscn"
const ENDING_SCENE_PATH := "res://scenes/ending_screen.tscn"
const SAVE_PATH := "user://save_data.json"
const HUD_SCENE := preload("res://ui/hud/HUD.tscn")
const PAUSE_SCENE := preload("res://ui/pause_menu/PauseMenu.tscn")
const DEATH_SCENE := preload("res://ui/death_screen/DeathScreen.tscn")
const COMPLETE_SCENE := preload("res://ui/level_complete/LevelCompleteScreen.tscn")
const TUTORIAL_SCENE := preload("res://ui/tutorial/ControlTutorial.tscn")
const STORY := preload("res://scripts/story_data.gd")

const LEVEL_DISPLAY_NAMES := {
	1: "Level 1 - 初入林间",
	2: "Level 2 - 夜路渐深",
	3: "Level 3 - 裂谷试炼",
	4: "Level 4 - 地下遗迹",
	5: "Level 5 - 极限逃生",
}

var current_level_display_name: String = ""
var _hud: CanvasLayer
var _hud_hold: bool = false ## 开场视频期间强制隐藏 HUD
var _pause_ui
var _death_ui
var _complete_ui
var _tutorial_ui
var _control_tutorial_done: bool = false
var _intro_l2_done: bool = false
var _intro_l3_done: bool = false
var _pending_enemy_intro_level: int = 0
var _awaiting_prologue_tutorial: bool = false
var _reopen_pause_after_tutorial: bool = false
var _level_started_msec: int = 0
var _deaths_this_level: int = 0
var _stars_total: int = 0
var _pending_next_level: int = 1
var _last_rewind_ratio: float = -1.0
var _unlocked_max: int = 1 ## 已解锁的最高关；仅通关上一关后 +1
var _story_settling: bool = false ## 通关剧情播放中，防止重复结算

# 信号：方便 UI / 相机 / 音效后续监听
signal state_changed(new_state: GameState)
signal level_reset
signal player_died
signal level_completed
signal shadow_rewind_cooldown_changed(ratio: float)
signal level_name_changed(level_name: String)

## -------------------- 打击感信号（解耦：业务只 emit/调 GM，不碰相机）--------------------
## 为什么用信号：音效、UI 闪白、后期 Hit Spark 都可以监听，而不改怪物脚本
signal hit_stop_triggered(duration: float)
signal camera_shake_triggered(intensity: float, duration: float, frequency: float)
signal light_impact   ## 普通怪被魔法球命中
signal glass_impact   ## 提灯狐妖被命中（玻璃清脆感）
signal heavy_impact   ## 自爆 / 主角受击 / 光球互撞

# -------------------- 顿帧（Hit Stop / Engine.time_scale）--------------------
# 注意：绝对不能用 get_tree().paused —— 那会把 CameraShake 和粒子一起冻住
var _hit_stopping: bool = false
var _hit_stop_end_msec: int = 0 ## 用真实毫秒合并多次顿帧，取最晚结束时间
@export var default_hit_stop_duration: float = 0.05
@export var hit_stop_time_scale: float = 0.05 ## 顿帧时世界变极慢，模拟“打实了”的阻力

# 三级预设集中在此：怪物脚本只调 trigger_xxx_impact()，改手感只改这里
const LIGHT_HIT_STOP := 0.05
const LIGHT_SHAKE := Vector3(2.0, 0.1, 30.0) # intensity, duration, frequency

const GLASS_HIT_STOP := 0.08 ## 狐妖略长，突出玻璃碎裂前的清脆一顿
const GLASS_SHAKE := Vector3(4.0, 0.15, 45.0) # 中等强度 + 更高频率 = 玻璃震颤

const HEAVY_HIT_STOP := 0.1
const HEAVY_SHAKE := Vector3(8.0, 0.3, 40.0)

## -------------------- 关卡动态光照（仅主角 PointLight；不碰视差节点）--------------------
signal level_brightness_changed(level_id: int, tint: Color, light_energy: float)
## Day 9：每关主角灯能量；背景明暗另见 level_atmosphere（L1 几乎看不见 → L5 明显）
var level_brightness: Dictionary = {
	1: 0.20,
	2: 0.35,
	3: 0.50,
	4: 0.5,
	5: 0.80,
}
## 视差层 modulate：关卡图背景从暗到明（L1≈全黑，L5 最亮）；由本脚本 Tween
var level_atmosphere: Dictionary = {
	1: {"tint": Color(0.02, 0.025, 0.045, 1.0)}, ## 基本看不见
	2: {"tint": Color(0.08, 0.07, 0.13, 1.0)},
	3: {"tint": Color(0.18, 0.14, 0.22, 1.0)},
	4: {"tint": Color(0.34, 0.28, 0.26, 1.0)},
	5: {"tint": Color(0.58, 0.52, 0.46, 1.0)}, ## 最亮
}
var _light_tween: Tween
var _backdrop_tint_tween: Tween
@export var brightness_tween_duration: float = 1.5 ## 关卡光照平滑过渡秒数（1–2s）

## 游玩时死亡点记录（控制台 + user://death_points.log）
var death_points: Array = [] ## [{level,x,y,reason,unix}]
const DEATH_LOG_PATH := "user://death_points.log"


func _ready() -> void:
	# 暂停菜单时仍可处理 Esc；顿帧不再依赖 get_tree().paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configure_better_inputs()
	_boot_overlay_ui()
	var lm := get_node_or_null("/root/LevelManager")
	if lm and lm.has_signal("level_loaded"):
		if not lm.level_loaded.is_connected(_on_level_loaded_ui):
			lm.level_loaded.connect(_on_level_loaded_ui)
	_load_save()
	call_deferred("_connect_dialogue_for_tutorial")
	print("GameManager 已启动，当前状态：", _state_name(current_state))
	call_deferred("_boot_scene_audio")


func _process(_delta: float) -> void:
	_poll_rewind_cooldown()


func _unhandled_input(event: InputEvent) -> void:
	# Esc：暂停 / 继续（主界面、死亡/结算时交给对应界面）
	if event.is_action_pressed("ui_cancel"):
		var dm := get_node_or_null("/root/DialogueManager")
		if dm and dm.has_method("is_dialogue_active") and dm.is_dialogue_active():
			return
		if _complete_ui and _complete_ui.has_method("is_open") and _complete_ui.is_open():
			return
		if _death_ui and _death_ui.has_method("is_open") and _death_ui.is_open():
			return
		match current_state:
			GameState.PLAYING:
				pause_game()
			GameState.PAUSED:
				resume_game()


# ==================== 状态切换 ====================
func change_state(new_state: GameState) -> void:
	if current_state == new_state:
		return
	current_state = new_state
	state_changed.emit(new_state)
	_set_hud_visible(new_state != GameState.MENU)
	print("GameManager 状态 → ", _state_name(new_state))


func _state_name(state: GameState) -> String:
	match state:
		GameState.MENU:
			return "MENU"
		GameState.PLAYING:
			return "PLAYING"
		GameState.PAUSED:
			return "PAUSED"
		GameState.DEAD:
			return "DEAD"
	return "UNKNOWN"


# ==================== 游戏流程接口 ====================
## 从主界面进入游戏
func start_game() -> void:
	_control_tutorial_done = false
	_intro_l2_done = false
	_intro_l3_done = false
	_reset_dialogue_skip_flag()
	start_level(1)


func start_level(level_id: int) -> void:
	if not is_level_unlocked(level_id):
		print("关卡未解锁：L", level_id)
		return
	_abort_hit_stop()
	get_tree().paused = false
	_story_settling = false
	change_state(GameState.PLAYING)
	_deaths_this_level = 0
	_hide_all_overlay_ui()
	_clear_control_tutorial()
	_save_progress(level_id)
	_play_music("level")
	var lm := get_node_or_null("/root/LevelManager")
	if lm and lm.has_method("load_level"):
		lm.load_level(level_id)
	else:
		get_tree().change_scene_to_file(main_scene_path)


func continue_game() -> void:
	start_level(read_save_level())


func go_to_level_select() -> void:
	_abort_hit_stop()
	get_tree().paused = false
	_story_settling = false
	_clear_control_tutorial()
	change_state(GameState.MENU)
	_hide_all_overlay_ui()
	_set_hud_visible(false)
	_play_music("menu")
	get_tree().change_scene_to_file(LEVEL_SELECT_PATH)


func get_unlocked_max() -> int:
	return _unlocked_max


func is_level_unlocked(level_id: int) -> bool:
	return level_id >= 1 and level_id <= _unlocked_max


func quit_game() -> void:
	get_tree().quit()


func go_to_main_menu() -> void:
	_abort_hit_stop()
	get_tree().paused = false
	_story_settling = false
	_clear_control_tutorial()
	change_state(GameState.MENU)
	_hide_all_overlay_ui()
	_play_music("menu")
	get_tree().change_scene_to_file(MENU_SCENE_PATH)


func load_next_level() -> void:
	if _complete_ui and _complete_ui.has_method("close_screen"):
		_complete_ui.close_screen()
	get_tree().paused = false
	change_state(GameState.PLAYING)
	_play_music("level")
	var lm := get_node_or_null("/root/LevelManager")
	if lm and lm.has_method("load_next_level"):
		# 避免 LevelManager.load_next_level 再 emit 一次 completed
		lm.load_level(_pending_next_level)
	else:
		load_level(_pending_next_level)


func complete_current_level() -> void:
	if _story_settling:
		return
	var lm := get_node_or_null("/root/LevelManager")
	var lid := _current_level_id()
	if _pending_next_level < 1 or _pending_next_level == lid:
		_pending_next_level = lid + 1
	if lm and not lm.level_scenes.has(_pending_next_level):
		_pending_next_level = 1
	_play_sfx("complete")
	level_completed.emit()
	# 通关第 N 关才解锁 N+1
	if lid >= 1 and lid < 5:
		_unlocked_max = maxi(_unlocked_max, lid + 1)
	_save_progress(lid)
	var scene := get_tree().current_scene
	if scene and scene.has_method("_on_level_completed"):
		scene._on_level_completed()
		return
	run_clear_story_then_settle(lid)


## 通关剧情在本单例上 await，避免关卡节点被 paused 卡住协程
func run_clear_story_then_settle(current_level: int) -> void:
	if _story_settling:
		return
	_story_settling = true
	var story_key := "level" + str(current_level) + "_after"
	var dialogue: Array = STORY.get_dialogue(story_key)
	var dm := get_node_or_null("/root/DialogueManager")
	if dm and dialogue.size() > 0 and dm.has_method("start_dialogue"):
		dm.start_dialogue(dialogue)
		if dm.has_signal("dialogue_finished"):
			await dm.dialogue_finished
	_story_settling = false
	if current_level >= 5:
		go_to_ending_screen()
	else:
		show_level_complete_after_story()


func show_level_complete_after_story() -> void:
	_story_settling = false
	_show_complete_ui()


func go_to_ending_screen() -> void:
	_story_settling = false
	_abort_hit_stop()
	get_tree().paused = false
	_clear_control_tutorial()
	change_state(GameState.MENU)
	_hide_all_overlay_ui()
	_set_hud_visible(false)
	_play_music("ending")
	get_tree().change_scene_to_file(ENDING_SCENE_PATH)


func persist_dialogue_skip_flag() -> void:
	_save_progress(_current_level_id())


func _boot_scene_audio() -> void:
	var path := _current_scene_path()
	if _is_opening_scene(path):
		change_state(GameState.MENU)
		var mm := get_node_or_null("/root/MusicManager")
		if mm and mm.has_method("stop_all"):
			mm.stop_all()
		return
	if path.is_empty() or _is_ui_scene(path):
		change_state(GameState.MENU)
		_play_music("menu")
		return
	if _is_ending_scene(path):
		_play_music("ending")
		return
	change_state(GameState.PLAYING)
	call_deferred("_on_level_loaded_ui", _current_level_id())
	_play_music("level")


func _sync_music_for_state() -> void:
	var path := _current_scene_path()
	if _is_ending_scene(path):
		_play_music("ending")
		return
	if path.is_empty() or _is_ui_scene(path):
		_play_music("menu")
		return
	if _is_level_scene(path):
		_play_music("level")


func _current_scene_path() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	return str(scene.scene_file_path).replace("\\", "/").to_lower()


func _is_opening_scene(path: String) -> bool:
	return path.ends_with("opening_intro.tscn")


func _is_ui_scene(path: String) -> bool:
	return path.ends_with("mainmenu.tscn") or path.ends_with("levelselect.tscn") or path.contains("/ui/")


func _is_ending_scene(path: String) -> bool:
	return path.ends_with("ending_screen.tscn")


func _is_level_scene(path: String) -> bool:
	return path.contains("/levels/") or path.ends_with("main.tscn")


func _play_music(kind: String) -> void:
	var mm := get_node_or_null("/root/MusicManager")
	if mm == null:
		return
	match kind:
		"menu":
			if mm.has_method("play_menu"):
				mm.play_menu()
		"level":
			if mm.has_method("play_level"):
				mm.play_level()
		"ending":
			if mm.has_method("play_ending"):
				mm.play_ending()


func _play_sfx(kind: String) -> void:
	var sfx := get_node_or_null("/root/SfxManager")
	if sfx and sfx.has_method("play"):
		sfx.play(kind)


func _apply_saved_skip_flag(never_skipped: bool) -> void:
	var dm := get_node_or_null("/root/DialogueManager")
	if dm:
		dm.never_skipped_dialogue = never_skipped


func _reset_dialogue_skip_flag() -> void:
	var dm := get_node_or_null("/root/DialogueManager")
	if dm:
		dm.never_skipped_dialogue = true
	_save_progress(1)


func arm_prologue_tutorial() -> void:
	_awaiting_prologue_tutorial = not _control_tutorial_done


func maybe_start_control_tutorial() -> void:
	if _control_tutorial_done:
		return
	if _current_level_id() != 1:
		return
	if current_state != GameState.PLAYING:
		return
	if _story_settling:
		return
	open_control_tutorial(false)


func open_control_tutorial_review() -> void:
	if current_state == GameState.PAUSED:
		_reopen_pause_after_tutorial = true
		if _pause_ui and _pause_ui.has_method("close_menu"):
			_pause_ui.close_menu()
	open_control_tutorial(true)


func mark_control_tutorial_done() -> void:
	_control_tutorial_done = true
	_save_progress(_current_level_id())


func open_control_tutorial(review: bool) -> void:
	if _tutorial_ui and is_instance_valid(_tutorial_ui):
		if review and _tutorial_ui.has_method("start_review"):
			_tutorial_ui.start_review()
		return
	_tutorial_ui = TUTORIAL_SCENE.instantiate()
	add_child(_tutorial_ui)
	if _tutorial_ui.has_signal("tutorial_finished"):
		_tutorial_ui.tutorial_finished.connect(_on_control_tutorial_finished)
	if review and _tutorial_ui.has_method("start_review"):
		_tutorial_ui.call_deferred("start_review")


func _on_control_tutorial_finished() -> void:
	_tutorial_ui = null
	if _reopen_pause_after_tutorial and current_state == GameState.PAUSED:
		_reopen_pause_after_tutorial = false
		if _pause_ui and _pause_ui.has_method("open_menu"):
			_pause_ui.open_menu()
	_reopen_pause_after_tutorial = false


func _clear_control_tutorial() -> void:
	_awaiting_prologue_tutorial = false
	_reopen_pause_after_tutorial = false
	_pending_enemy_intro_level = 0
	if _tutorial_ui and is_instance_valid(_tutorial_ui):
		_tutorial_ui.queue_free()
	_tutorial_ui = null


func _connect_dialogue_for_tutorial() -> void:
	var dm := get_node_or_null("/root/DialogueManager")
	if dm and dm.has_signal("dialogue_finished"):
		if not dm.dialogue_finished.is_connected(_on_prologue_dialogue_finished):
			dm.dialogue_finished.connect(_on_prologue_dialogue_finished)


func _on_prologue_dialogue_finished() -> void:
	if _pending_enemy_intro_level > 0:
		_mark_enemy_intro_done(_pending_enemy_intro_level)
		_pending_enemy_intro_level = 0
	if not _awaiting_prologue_tutorial:
		return
	_awaiting_prologue_tutorial = false
	call_deferred("maybe_start_control_tutorial")


func try_level_enemy_intro(level_id: int) -> void:
	if current_state != GameState.PLAYING:
		return
	if _story_settling:
		return
	var already := false
	var stage := ""
	match level_id:
		2:
			already = _intro_l2_done
			stage = "level2_enemy_intro"
		3:
			already = _intro_l3_done
			stage = "level3_fox_intro"
		_:
			return
	if already:
		return
	var dialogue: Array = STORY.get_dialogue(stage)
	var dm := get_node_or_null("/root/DialogueManager")
	if dialogue.is_empty() or dm == null or not dm.has_method("start_dialogue"):
		_mark_enemy_intro_done(level_id)
		return
	_pending_enemy_intro_level = level_id
	dm.start_dialogue(dialogue, false)


func _mark_enemy_intro_done(level_id: int) -> void:
	if level_id == 2:
		_intro_l2_done = true
	elif level_id == 3:
		_intro_l3_done = true
	_save_progress(_current_level_id())


func update_level_name(name: String) -> void:
	current_level_display_name = name
	if _hud_hold:
		return
	level_name_changed.emit(name)
	if _hud and _hud.has_method("update_level_name"):
		_hud.update_level_name(name)


## 暂停
func pause_game() -> void:
	if current_state != GameState.PLAYING:
		return
	_abort_hit_stop()
	get_tree().paused = true
	change_state(GameState.PAUSED)
	if _pause_ui and _pause_ui.has_method("open_menu"):
		_pause_ui.open_menu()


## 继续
func resume_game() -> void:
	if current_state != GameState.PAUSED:
		return
	get_tree().paused = false
	change_state(GameState.PLAYING)
	if _pause_ui and _pause_ui.has_method("close_menu"):
		_pause_ui.close_menu()


## 玩家死亡
func game_over(reason: String = "hp_zero") -> void:
	if current_state == GameState.DEAD:
		return
	_abort_hit_stop()
	change_state(GameState.DEAD)
	var p := get_player()
	var pos: Vector2 = Vector2.ZERO
	if p is Node2D:
		pos = (p as Node2D).global_position
		if "current_hp" in p:
			p.current_hp = 0
		if p.has_method("_update_hud"):
			p._update_hud()
		if p.has_method("set_input_locked"):
			p.set_input_locked(true)
	record_player_death(reason, pos)
	player_died.emit()
	_play_sfx("death")
	get_tree().paused = true
	_show_death_ui()
	print("游戏结束（", reason, "）。选择重试或返回主菜单。")


## 强制结束顿帧（换关 / 重置用）
func abort_hit_stop() -> void:
	_abort_hit_stop()


## Day 9：按关卡 id 加载（转发 LevelManager，并在进关后处理出生点 / 光照）
func load_level(level_id: int) -> void:
	_abort_hit_stop()
	get_tree().paused = false
	change_state(GameState.PLAYING)
	_play_music("level")
	var lm := get_node_or_null("/root/LevelManager")
	if lm and lm.has_method("load_level"):
		lm.load_level(level_id)
	else:
		push_warning("GameManager.load_level：找不到 LevelManager")


## 进关后：找 spawn_point → reset_at_spawn；再 Tween 本关亮度（死亡重开也走这里，亮度不退档）
func place_player_at_spawn_and_apply_light(level_id: int = -1) -> void:
	var lid := level_id
	if lid < 0:
		var lm := get_node_or_null("/root/LevelManager")
		if lm:
			lid = int(lm.get("current_level_id"))
		else:
			lid = 1

	var spawn := get_tree().get_first_node_in_group("spawn_point") as Node2D
	var player := get_player()
	if spawn == null:
		push_warning("GameManager：场景中无 group=spawn_point 的出生点")
	elif player:
		if player.has_method("reset_at_spawn"):
			player.reset_at_spawn(spawn.global_position)
		else:
			player.global_position = spawn.global_position
			if "velocity" in player:
				player.velocity = Vector2.ZERO
		print("📍 出生点就位 → ", spawn.global_position)

	# 光照保持「当前关」目标亮度；死亡重置不会退回上一关
	apply_level_brightness(lid, brightness_tween_duration)


## 关卡光照：主角 RealLight + 视差层 modulate（只改属性，不改视差脚本/节点结构）
## duration < 0 → 用默认 1.5s；≥1 → 夹到 1–2s；0~1 → 允许短时初始化
func apply_level_brightness(level_id: int, duration: float = -1.0) -> void:
	if duration < 0.0:
		duration = clampf(brightness_tween_duration, 1.0, 2.0)
	elif duration >= 1.0:
		duration = clampf(duration, 1.0, 2.0)

	var energy: float = float(level_brightness.get(level_id, 0.12))
	var atm: Dictionary = level_atmosphere.get(level_id, {})
	var tint: Color = atm.get("tint", Color(0.12, 0.14, 0.24, 1.0)) as Color

	var player := get_player()
	if player:
		var light := player.get_node_or_null("RealLight") as PointLight2D
		if light:
			if _light_tween and _light_tween.is_valid():
				_light_tween.kill()
			_light_tween = create_tween()
			_light_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			_light_tween.tween_property(light, "energy", energy, duration) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_tween_parallax_tint(tint, duration)

	level_brightness_changed.emit(level_id, tint, energy)
	print("🌑 关卡光照 → L", level_id, " light=", energy, " tint=", tint, " tween=", duration, "s")


## 视差层只做关卡氛围色（夜景色相）；贴图明暗在 parallax_backdrop 的 Sprite 宿主上压暗，这里不再 ÷3 叠暗
func _tween_parallax_tint(tint: Color, duration: float) -> void:
	var pb := get_tree().get_first_node_in_group("level_parallax_bg")
	if pb == null:
		return
	if _backdrop_tint_tween and _backdrop_tint_tween.is_valid():
		_backdrop_tint_tween.kill()

	var targets: Array = []
	for child in pb.get_children():
		if child is CanvasItem:
			targets.append([child, _tint_for_parallax_layer(child, tint)])

	if targets.is_empty():
		return

	if duration <= 0.02:
		for pair in targets:
			(pair[0] as CanvasItem).modulate = pair[1] as Color
		return

	_backdrop_tint_tween = create_tween()
	_backdrop_tint_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_backdrop_tint_tween.set_parallel(true)
	for pair in targets:
		_backdrop_tint_tween.tween_property(pair[0], "modulate", pair[1], duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 视差层氛围：直接用关卡 tint 控制明暗（L1→L5 递亮）；不再抬亮度下限
func _tint_for_parallax_layer(layer: Node, tint: Color) -> Color:
	var name_s := String(layer.name)
	var mul := 1.0
	match name_s:
		"Layer1_Far", "Layer0_Far":
			mul = 0.85 ## 远景略暗一层
		"Layer2_MidFar":
			mul = 1.12 ## 中远景略亮，层次还在，但仍跟关卡总亮度走
		"Petals":
			mul = 1.1 ## 与中远景同系
		"Layer3_Mid":
			mul = 1.0
		"Layer4_Foreground", "Layer4_Fg":
			mul = 1.05
		_:
			mul = 1.0
	return Color(
		clampf(tint.r * mul, 0.0, 1.0),
		clampf(tint.g * mul, 0.0, 1.0),
		clampf(tint.b * mul, 0.0, 1.0),
		1.0
	)


## 重置关卡：硬重载当前场景（deferred，避开 KillZone 物理回调里直接切场景卡死）
func reset_level() -> void:
	print("重置关卡（硬重载）…")
	_abort_hit_stop()
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	get_tree().paused = false
	_story_settling = false
	change_state(GameState.PLAYING)
	_hide_all_overlay_ui()
	_clear_control_tutorial()
	level_reset.emit()
	call_deferred("_hard_reload_level")


func hard_reload_level() -> void:
	call_deferred("_hard_reload_level")


func _hard_reload_level() -> void:
	print("硬重载当前关…")
	_abort_hit_stop()
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	get_tree().paused = false
	change_state(GameState.PLAYING)
	var lm := get_node_or_null("/root/LevelManager")
	if lm and lm.has_method("reload_current_level"):
		lm.reload_current_level()
		return
	var tree := get_tree()
	if tree.current_scene != null:
		tree.reload_current_scene()
	else:
		tree.change_scene_to_file(main_scene_path)


## 记录死亡点（深渊 / 掉血等）；写日志方便对照离谱间距
func record_player_death(reason: String, pos: Vector2 = Vector2.INF) -> void:
	var lid := 0
	var lm := get_node_or_null("/root/LevelManager")
	if lm:
		lid = int(lm.get("current_level_id"))
	if pos.x == INF:
		var p := get_player()
		if p is Node2D:
			pos = (p as Node2D).global_position
	var entry := {
		"level": lid,
		"x": snappedf(pos.x, 0.1),
		"y": snappedf(pos.y, 0.1),
		"reason": reason,
		"unix": Time.get_unix_time_from_system(),
	}
	_deaths_this_level += 1
	death_points.append(entry)
	var line := "💀 DEATH L%d (%.1f, %.1f) reason=%s  [session ×%d]" % [
		lid, pos.x, pos.y, reason, death_points.size()
	]
	print(line)
	var f := FileAccess.open(DEATH_LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(DEATH_LOG_PATH, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("%s\tx=%.1f\ty=%.1f\tL%d\t%s" % [
			Time.get_datetime_string_from_system(), pos.x, pos.y, lid, reason
		])
		f.close()
	# 本关最近几次，方便对照岛间距
	var recent: Array = []
	for e in death_points:
		if int(e.get("level", -1)) == lid:
			recent.append(e)
	if recent.size() > 0:
		var tail := mini(3, recent.size())
		print("   ↳ 本关近%d次死亡: " % tail, recent.slice(recent.size() - tail))


# ==================== 打击感（顿帧 + 相机震动，解耦入口）====================
## 获取场景中的玩家（player 组）
func get_player() -> Node:
	return get_tree().get_first_node_in_group("player")


## 是否处于可操作的游玩状态
func is_playing() -> bool:
	return current_state == GameState.PLAYING and not get_tree().paused


## 轻击：魔法球命中普通地面怪（微顿 + 轻震）
func trigger_light_impact() -> void:
	if current_state != GameState.PLAYING:
		return
	light_impact.emit()
	trigger_hit_stop(LIGHT_HIT_STOP)
	trigger_camera_shake(LIGHT_SHAKE.x, LIGHT_SHAKE.y, LIGHT_SHAKE.z)


## 玻璃击：魔法球命中提灯狐妖（稍长顿帧 + 高频中震，模拟玻璃震颤）
func trigger_glass_impact() -> void:
	if current_state != GameState.PLAYING:
		return
	glass_impact.emit()
	trigger_hit_stop(GLASS_HIT_STOP)
	trigger_camera_shake(GLASS_SHAKE.x, GLASS_SHAKE.y, GLASS_SHAKE.z)


## 重击：怪物自爆 / 主角受击 / 光球互撞爆炸（重顿 + 剧烈震动）
func trigger_heavy_impact() -> void:
	if current_state != GameState.PLAYING:
		return
	heavy_impact.emit()
	trigger_hit_stop(HEAVY_HIT_STOP)
	trigger_camera_shake(HEAVY_SHAKE.x, HEAVY_SHAKE.y, HEAVY_SHAKE.z)


## 顿帧核心：只改 Engine.time_scale，绝不 pause 场景树
## duration 为「真实秒」；多次触发会合并到最晚结束时刻，避免轻击打断重击
func trigger_hit_stop(duration: float = -1.0) -> void:
	if duration < 0.0:
		duration = default_hit_stop_duration
	if duration <= 0.0:
		return
	if current_state != GameState.PLAYING:
		return

	# 用墙钟毫秒：不受 time_scale 影响，顿帧时长才是玩家感知的真实时间
	var end_msec := Time.get_ticks_msec() + int(duration * 1000.0)
	_hit_stop_end_msec = maxi(_hit_stop_end_msec, end_msec)
	hit_stop_triggered.emit(duration)

	# 已在顿帧循环里：只延长结束时间，不新开协程
	if _hit_stopping:
		return
	_run_hit_stop()


## 兼容旧 await GameManager.hit_stop(...)：内部仍走 time_scale 方案
func hit_stop(duration: float = -1.0) -> void:
	trigger_hit_stop(duration)
	if duration < 0.0:
		duration = default_hit_stop_duration
	# ignore_time_scale=true：等待真实时间，否则 time_scale=0.05 时会等超久
	await get_tree().create_timer(maxf(duration, 0.0), true, false, true).timeout


func _run_hit_stop() -> void:
	_hit_stopping = true
	# 世界变慢，但 CameraShake 用真实 delta 补偿，所以震动仍流畅
	Engine.time_scale = hit_stop_time_scale
	_sync_audio_to_time_scale()

	while Time.get_ticks_msec() < _hit_stop_end_msec:
		if current_state != GameState.PLAYING:
			break
		await get_tree().create_timer(0.01, true, false, true).timeout

	_finish_hit_stop()


func _finish_hit_stop() -> void:
	_hit_stopping = false
	_hit_stop_end_msec = 0
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	_sync_audio_to_time_scale()


func _abort_hit_stop() -> void:
	# 暂停菜单 / 重置关卡时必须立刻恢复，否则会卡在慢动作
	_hit_stop_end_msec = 0
	_finish_hit_stop()


## 顿帧时补偿音频播放速率，避免 BGM/音效一起变慢变调
func _sync_audio_to_time_scale() -> void:
	if Engine.time_scale > 0.0001:
		AudioServer.playback_speed_scale = 1.0 / Engine.time_scale
	else:
		AudioServer.playback_speed_scale = 1.0


## 相机震动唯一入口：业务侧禁止直接改 Camera2D.offset
func trigger_camera_shake(intensity: float = 2.0, duration: float = 0.1, frequency: float = 30.0) -> void:
	camera_shake_triggered.emit(intensity, duration, frequency)
	var cam = get_tree().get_first_node_in_group("main_camera")
	if cam and cam.has_method("shake"):
		cam.shake(intensity, duration, frequency)


## 兼容旧接口 → 转发到分级打击感
func screen_shake(intensity: float = 0.5, frequency: float = 25.0) -> void:
	trigger_camera_shake(intensity * 10.0, 0.15, frequency)


func shake_player_hurt() -> void:
	trigger_heavy_impact()


func shake_enemy_explode() -> void:
	trigger_heavy_impact()


# ==================== 按键优化（不改状态机，只改 InputMap）====================
## 空格/W=跳；贴梯时 W 改作攀爬（由 player 区分，避免上梯被弹飞）
## W+A/D+L = 斜上追踪；S+A/D+L = 斜下
func _configure_better_inputs() -> void:
	# 1) 跳跃：空格 + W（移动手感）；梯子冲突在 player 里处理
	_ensure_physical_key("ui_accept", KEY_SPACE)
	_ensure_physical_key("ui_accept", KEY_W)

	# 2) 上下：W/S（攀爬 + 斜向组合）
	if not InputMap.has_action("ui_up"):
		InputMap.add_action("ui_up")
	_ensure_physical_key("ui_up", KEY_W)
	_ensure_physical_key("ui_up", KEY_UP)

	if not InputMap.has_action("ui_down"):
		InputMap.add_action("ui_down")
	_ensure_physical_key("ui_down", KEY_S)
	_ensure_physical_key("ui_down", KEY_DOWN)

	# 3) 左右
	_ensure_physical_key("ui_left", KEY_A)
	_ensure_physical_key("ui_left", KEY_LEFT)
	_ensure_physical_key("ui_right", KEY_D)
	_ensure_physical_key("ui_right", KEY_RIGHT)

	# 4) J 平A / K 回溯 / L 发射
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
	_erase_physical_key("attack", KEY_H)
	_ensure_physical_key("attack", KEY_J)

	if not InputMap.has_action("rewind"):
		InputMap.add_action("rewind")
	_ensure_physical_key("rewind", KEY_K)

	if not InputMap.has_action("shoot_orb"):
		InputMap.add_action("shoot_orb")
	_erase_physical_key("shoot_orb", KEY_H)
	_ensure_physical_key("shoot_orb", KEY_L)
	_ensure_mouse_button("shoot_orb", MOUSE_BUTTON_RIGHT)

	if not InputMap.has_action("toggle_level_name"):
		InputMap.add_action("toggle_level_name")
	_ensure_physical_key("toggle_level_name", KEY_TAB)

	print("⌨️ 按键：W/空格跳 | 贴梯时 W/S 攀爬 | W/S+A/D+L 斜向 | J平A K回溯 L/右键发射 | Esc暂停 | Tab关卡名")


func _erase_physical_key(action: String, physical_keycode: Key) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == physical_keycode:
			InputMap.action_erase_event(action, ev)
		elif ev is InputEventKey and (ev as InputEventKey).keycode == physical_keycode:
			InputMap.action_erase_event(action, ev)


func _ensure_physical_key(action: String, physical_keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			if k.physical_keycode == physical_keycode or k.keycode == physical_keycode:
				return
	var e := InputEventKey.new()
	e.physical_keycode = physical_keycode
	e.keycode = physical_keycode
	InputMap.action_add_event(action, e)


func _ensure_mouse_button(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == button:
			return
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


func _boot_overlay_ui() -> void:
	_pause_ui = PAUSE_SCENE.instantiate()
	_death_ui = DEATH_SCENE.instantiate()
	_complete_ui = COMPLETE_SCENE.instantiate()
	add_child(_pause_ui)
	add_child(_death_ui)
	add_child(_complete_ui)
	if _pause_ui.has_signal("resume_requested"):
		_pause_ui.resume_requested.connect(resume_game)
	if _pause_ui.has_signal("restart_requested"):
		_pause_ui.restart_requested.connect(reset_level)
	if _pause_ui.has_signal("back_to_menu_requested"):
		_pause_ui.back_to_menu_requested.connect(go_to_main_menu)
	if _pause_ui.has_signal("tutorial_requested"):
		_pause_ui.tutorial_requested.connect(open_control_tutorial_review)
	if _death_ui.has_signal("retry_requested"):
		_death_ui.retry_requested.connect(reset_level)
	if _death_ui.has_signal("back_to_menu_requested"):
		_death_ui.back_to_menu_requested.connect(go_to_main_menu)
	if _complete_ui.has_signal("next_level_requested"):
		_complete_ui.next_level_requested.connect(load_next_level)
	if _complete_ui.has_signal("back_to_menu_requested"):
		_complete_ui.back_to_menu_requested.connect(go_to_main_menu)
	if _complete_ui.has_signal("level_select_requested"):
		_complete_ui.level_select_requested.connect(go_to_level_select)
	if _complete_ui.has_signal("retry_requested"):
		_complete_ui.retry_requested.connect(reset_level)
	if _death_ui.has_signal("level_select_requested"):
		_death_ui.level_select_requested.connect(go_to_level_select)


var _tracked_level_id: int = -1

func _on_level_loaded_ui(level_id: int) -> void:
	if level_id != _tracked_level_id:
		_deaths_this_level = 0
		_tracked_level_id = level_id
	_level_started_msec = Time.get_ticks_msec()
	_stars_total = 0
	_save_progress(level_id)
	update_level_name(str(LEVEL_DISPLAY_NAMES.get(level_id, "Level %d" % level_id)))
	_ensure_hud()
	call_deferred("_count_level_stars")


func _ensure_hud() -> void:
	if _hud and is_instance_valid(_hud):
		_set_hud_visible(current_state != GameState.MENU)
		return
	if current_state == GameState.MENU:
		return
	_hud = HUD_SCENE.instantiate()
	add_child(_hud)
	_set_hud_visible(true)


func hold_hud(hold: bool) -> void:
	_hud_hold = hold
	if hold:
		_set_hud_visible(false)
		_hide_player_owned_hud()
		return
	_set_hud_visible(current_state == GameState.PLAYING)
	if current_state == GameState.PLAYING and current_level_display_name != "":
		update_level_name(current_level_display_name)


func _hide_player_owned_hud() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for p in tree.get_nodes_in_group("player"):
		var extra = p.get("hud")
		if extra is CanvasLayer and extra != _hud:
			if extra.has_method("set_gameplay_visible"):
				extra.set_gameplay_visible(false)
			else:
				extra.visible = false


func _set_hud_visible(on: bool) -> void:
	if _hud_hold:
		on = false
	if _hud == null or not is_instance_valid(_hud):
		_hide_player_owned_hud()
		return
	if _hud.has_method("set_gameplay_visible"):
		_hud.set_gameplay_visible(on)
	else:
		_hud.visible = on
	if not on:
		_hide_player_owned_hud()


func _count_level_stars() -> void:
	var tree := get_tree()
	if tree:
		_stars_total = tree.get_nodes_in_group("light_orbs").size()


func _show_death_ui() -> void:
	if _pause_ui and _pause_ui.has_method("close_menu"):
		_pause_ui.close_menu()
	if _death_ui and _death_ui.has_method("open_screen"):
		_death_ui.open_screen()


func _show_complete_ui() -> void:
	get_tree().paused = true
	var elapsed := (Time.get_ticks_msec() - _level_started_msec) / 1000.0
	var left := 0
	if get_tree():
		left = get_tree().get_nodes_in_group("light_orbs").size()
	var collected := maxi(_stars_total - left, 0)
	if _complete_ui and _complete_ui.has_method("update_stats"):
		_complete_ui.update_stats(elapsed, _deaths_this_level, collected, _stars_total)
	if _complete_ui and _complete_ui.has_method("open_screen"):
		_complete_ui.open_screen()


func _hide_all_overlay_ui() -> void:
	if _pause_ui and _pause_ui.has_method("close_menu"):
		_pause_ui.close_menu()
	if _death_ui and _death_ui.has_method("close_screen"):
		_death_ui.close_screen()
	if _complete_ui and _complete_ui.has_method("close_screen"):
		_complete_ui.close_screen()


func _poll_rewind_cooldown() -> void:
	var p := get_player()
	var ratio := 0.0
	if p and "rewind_cooldown_timer" in p and "rewind_cooldown" in p:
		var cd: float = float(p.rewind_cooldown)
		var left: float = float(p.rewind_cooldown_timer)
		if cd > 0.001:
			ratio = clampf(left / cd, 0.0, 1.0)
	if absf(ratio - _last_rewind_ratio) > 0.01 or (ratio <= 0.0 and _last_rewind_ratio > 0.0):
		_last_rewind_ratio = ratio
		shadow_rewind_cooldown_changed.emit(ratio)


func _current_level_id() -> int:
	var lm := get_node_or_null("/root/LevelManager")
	if lm:
		return int(lm.get("current_level_id"))
	return 1


func write_save(level_id: int) -> void:
	_save_progress(level_id)


func _save_progress(last_level_id: int) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		var never_skipped := true
		var dm := get_node_or_null("/root/DialogueManager")
		if dm:
			never_skipped = bool(dm.never_skipped_dialogue)
		f.store_string(JSON.stringify({
			"level_id": last_level_id,
			"unlocked_max": _unlocked_max,
			"never_skipped_dialogue": never_skipped,
			"control_tutorial_done": _control_tutorial_done,
			"intro_l2_done": _intro_l2_done,
			"intro_l3_done": _intro_l3_done,
			"intro_l3_skills_done": _intro_l3_done,
		}))


func _load_save() -> void:
	_unlocked_max = 1
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_unlocked_max = clampi(int(data.get("unlocked_max", 1)), 1, 5)
		_control_tutorial_done = bool(data.get("control_tutorial_done", false))
		_intro_l2_done = bool(data.get("intro_l2_done", false))
		_intro_l3_done = bool(data.get("intro_l3_skills_done", false))
		call_deferred("_apply_saved_skip_flag", bool(data.get("never_skipped_dialogue", true)))


func read_save_level() -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return 1
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return 1
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		var lid := int(data.get("level_id", 1))
		return clampi(lid, 1, _unlocked_max)
	return 1

