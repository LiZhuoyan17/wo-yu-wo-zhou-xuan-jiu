extends Node
## ==================== LevelManager：关卡加载 / 切换 ====================
## Autoload。不替代 GameManager：只负责换场景与记录关卡 id。
## 影子清理 / 状态重置由关卡内 level_controller + player.reset_at_spawn 完成。

signal level_loaded(level_id: int)
signal level_completed(level_id: int)

## level_id -> 场景路径（可继续往下加 Level_05…）
var level_scenes: Dictionary = {
	1: "res://levels/Level_01.tscn",
	2: "res://levels/Level_02.tscn",
	3: "res://levels/Level_03.tscn",
	4: "res://levels/Level_04.tscn",
	5: "res://levels/Level_05.tscn",
}

var current_level_id: int = 1
var _loading: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("LevelManager 就绪，关卡数：", level_scenes.size())


## 对外主接口：按编号加载关卡
func load_level(level_id: int) -> void:
	if _loading:
		return
	if not level_scenes.has(level_id):
		push_warning("LevelManager: 无此关卡 id=%s" % level_id)
		return

	_loading = true
	current_level_id = level_id
	var path: String = level_scenes[level_id]

	# 换关前恢复时间缩放，避免上一关顿帧残留
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		if gm.has_method("abort_hit_stop"):
			gm.abort_hit_stop()
		# GameState.PLAYING == 1（避免 Autoload 循环解析问题）
		if gm.has_method("change_state"):
			gm.change_state(1)

	print("📦 加载关卡 ", level_id, " → ", path)
	get_tree().change_scene_to_file(path)
	# change_scene 后本帧后续可能无效；用 call_deferred 发信号
	call_deferred("_emit_loaded", level_id)
	_loading = false


func _emit_loaded(level_id: int) -> void:
	level_loaded.emit(level_id)
	# 延迟一帧：场景树就绪后再出生点重置 + 本关光照 Tween（死亡重开同 level_id，亮度不退档）
	call_deferred("_after_level_ready", level_id)


func _after_level_ready(level_id: int) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("place_player_at_spawn_and_apply_light"):
		gm.place_player_at_spawn_and_apply_light(level_id)
	elif gm and gm.has_method("apply_level_brightness"):
		gm.apply_level_brightness(level_id, 1.5)


## 重载当前关（死亡 / Esc 重置用）
func reload_current_level() -> void:
	load_level(current_level_id)


## 通关进入下一关；没有下一关则回到第 1 关
func load_next_level() -> void:
	level_completed.emit(current_level_id)
	var next_id := current_level_id + 1
	if level_scenes.has(next_id):
		load_level(next_id)
	else:
		print("🎉 全部测试关完成，回到 Level 1")
		load_level(1)


func get_level_count() -> int:
	return level_scenes.size()
