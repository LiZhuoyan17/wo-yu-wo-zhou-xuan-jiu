extends Node2D

@export var door_closed: Sprite2D
@export var door_open: Sprite2D
@export var trigger_distance: float = 50.0 # 我把距离稍微调大到 50

var is_open: bool = false

func _ready() -> void:
	
	# 游戏启动时，强制确保门是关闭的
	_set_door_state(false)
	print("门已就绪，当前状态：关闭")
	
@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	# 1. 记录这一帧是否检测到了玩家或影子
	var is_player_nearby = false
	var is_shadow_nearby = false
	
	# 2. 如果门已经打开，我们需要检测“是否该关门”
	if is_open:
		# 检测玩家是否还在附近
		@warning_ignore("confusable_local_declaration")
		var player = get_tree().get_first_node_in_group("player") 
		if player:
			var player_sprite = player.get_node_or_null("PlayerSprite")
			if player_sprite:
				var player_distance = abs(global_position.x - player_sprite.global_position.x)
				if player_distance <= trigger_distance:
					is_player_nearby = true
		
		# 检测影子是否还在附近
		@warning_ignore("confusable_local_declaration")
		var shadow_nodes = get_tree().get_nodes_in_group("shadows")
		for shadow in shadow_nodes:
			if shadow is Node2D:
				var horizontal_distance = abs(global_position.x - shadow.global_position.x)
				if horizontal_distance <= trigger_distance:
					is_shadow_nearby = true
		
		# 3. 核心关门逻辑：如果玩家和影子都不在附近，就关门！
		if not is_player_nearby and not is_shadow_nearby:
			_close_door()
			
		return # 门开着的时候，不需要再执行下面的开门逻辑
	
	# 4. 如果门是关着的，执行原有的开门逻辑
	# --- 检测主角是否靠近 ---
	var player = get_tree().get_first_node_in_group("player") 
	if player:
		var player_sprite = player.get_node_or_null("PlayerSprite")
		if player_sprite:
			var player_distance = abs(global_position.x - player_sprite.global_position.x)
			if player_distance <= trigger_distance:
				_open_door()
				return
	
	# --- 检测影子是否靠近 ---
	var shadow_nodes = get_tree().get_nodes_in_group("shadows")
	for shadow in shadow_nodes:
		if shadow is Node2D:
			var horizontal_distance = abs(global_position.x - shadow.global_position.x)
			if horizontal_distance <= trigger_distance:
				_open_door()
				return
				
func _open_door() -> void:
	if is_open: 
		return
	is_open = true
	_set_door_state(true)
	print("光门已开启！")

func _close_door() -> void:
	is_open = false
	if door_closed:
		door_closed.visible = true
	if door_open:
		door_open.visible = false
	print("光门已关闭！")

func _set_door_state(open: bool) -> void:
	if door_closed: 
		door_closed.visible = !open
		#print("door_closed 现在的可见性是：", door_closed.visible) # 新增打印
		
	if door_open: 
		door_open.visible = open

	
