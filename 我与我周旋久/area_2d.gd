extends Area2D

func _ready() -> void:
	# 确保信号连接上了
	if not is_connected("body_entered", _on_body_entered):
		connect("body_entered", _on_body_entered)

# 注意：func 必须顶格写，前面绝对不能有任何空格或 Tab
func _on_body_entered(body: Node) -> void:
	# 判断进来的物体是不是影子
	if body.is_in_group("shadows"):
		print("检测到影子，门正在打开...")
		# 在这里可以写门打开的逻辑，或者发信号给门
