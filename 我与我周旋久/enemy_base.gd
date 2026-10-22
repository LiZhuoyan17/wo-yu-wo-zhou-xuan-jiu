extends CharacterBody2D
class_name BaseEnemy
## 怪物底层：HP / 受击 / 死亡 / 近战免疫 / 影子仇恨（带滞回）

const ParticleFXUtil = preload("res://particle_fx.gd")

@export var max_hp: int = 3
@export var immune_to_ground_melee: bool = false

## 影子比玩家近多少（或影子在此距离内）才倾向追影子
@export var shadow_prefer_distance: float = 100.0
## 切换目标所需的最小优势距离，防止原地抽搐乱切
@export var target_switch_hysteresis: float = 45.0

var current_hp: int = 3
var _is_dead: bool = false

## 当前仇恨：玩家或影子（滞回锁定）
var aggro_target: Node2D = null
var aggro_is_shadow: bool = false


func _ready() -> void:
	add_to_group("enemies")
	current_hp = max_hp
	_enemy_ready()


func _enemy_ready() -> void:
	pass


func is_dead() -> bool:
	return _is_dead


func take_damage(amount: int) -> void:
	if _is_dead or amount <= 0:
		return
	current_hp -= amount
	_on_damaged(amount)
	if current_hp <= 0:
		die()


func take_melee_damage(amount: int) -> void:
	if immune_to_ground_melee:
		return
	take_damage(amount)


func _on_damaged(_amount: int) -> void:
	pass


func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_on_death()
	queue_free()


func _on_death() -> void:
	pass


func play_default_death_fx() -> void:
	var parent := get_parent()
	if parent:
		ParticleFXUtil.enemy_death(parent, global_position)
	if GameManager:
		GameManager.trigger_heavy_impact()


## 平滑仇恨：优先较近的 active_shadows，用滞回避免疯狂切换
## 返回 { "node": Node2D, "pos": Vector2, "is_shadow": bool } 或空字典
func resolve_aggro_target(player: Node2D) -> Dictionary:
	if not is_instance_valid(player):
		_clear_aggro()
		return {}

	var player_pos: Vector2 = player.global_position
	var dist_player := global_position.distance_to(player_pos)

	var best_shadow: Node2D = null
	var best_shadow_dist := INF
	for s in get_tree().get_nodes_in_group("active_shadows"):
		if not is_instance_valid(s):
			continue
		if s.has_method("is_shadow_alive") and not s.is_shadow_alive():
			continue
		var d := global_position.distance_to(s.global_position)
		if d < best_shadow_dist:
			best_shadow_dist = d
			best_shadow = s

	# 影子是否“更值得追”：比玩家近，或在偏好距离内且不远于玩家太多
	var shadow_attractive := false
	if best_shadow != null:
		shadow_attractive = (
			best_shadow_dist + target_switch_hysteresis < dist_player
			or (best_shadow_dist <= shadow_prefer_distance and best_shadow_dist <= dist_player + target_switch_hysteresis)
		)

	# --- 滞回：已锁定影子时，除非影子没了或玩家明显更近，否则不切回 ---
	if aggro_is_shadow and is_instance_valid(aggro_target):
		if aggro_target.has_method("is_shadow_alive") and not aggro_target.is_shadow_alive():
			_clear_aggro()
		else:
			var dist_locked := global_position.distance_to(aggro_target.global_position)
			# 玩家近很多才切回
			if dist_player + target_switch_hysteresis < dist_locked:
				aggro_target = player
				aggro_is_shadow = false
			else:
				return {
					"node": aggro_target,
					"pos": aggro_target.global_position,
					"is_shadow": true
				}

	if shadow_attractive and best_shadow != null:
		# 若当前追玩家，需要影子优势超过滞回才切换
		if not aggro_is_shadow and is_instance_valid(aggro_target):
			if best_shadow_dist + target_switch_hysteresis >= dist_player:
				aggro_target = player
				aggro_is_shadow = false
				return {"node": player, "pos": player_pos, "is_shadow": false}
		aggro_target = best_shadow
		aggro_is_shadow = true
		return {
			"node": best_shadow,
			"pos": best_shadow.global_position,
			"is_shadow": true
		}

	aggro_target = player
	aggro_is_shadow = false
	return {"node": player, "pos": player_pos, "is_shadow": false}


func _clear_aggro() -> void:
	aggro_target = null
	aggro_is_shadow = false


## 贴脸攻击：影子则击碎，玩家则扣血
func try_melee_on_aggro(reach: float = 25.0) -> bool:
	if not is_instance_valid(aggro_target):
		return false
	if global_position.distance_to(aggro_target.global_position) > reach:
		return false
	if aggro_is_shadow:
		if aggro_target.has_method("destroy_by_hit"):
			aggro_target.destroy_by_hit()
		_clear_aggro()
		return true
	if aggro_target.is_in_group("player") and aggro_target.has_method("take_player_damage"):
		aggro_target.take_player_damage()
		return true
	return false
