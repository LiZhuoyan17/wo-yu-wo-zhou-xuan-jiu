extends Node2D
## 调试用：显示闪现平台剩余时间。默认父节点 TimingHelper.visible=false。

func _process(_delta: float) -> void:
	var plat = get_meta("plat") if has_meta("plat") else null
	var lab := get_node_or_null("Countdown") as Label
	if lab == null or plat == null or not is_instance_valid(plat):
		return
	if not plat.has_method("remaining"):
		return
	var t: float = float(plat.call("remaining"))
	var solid := false
	if plat.has_method("is_platform_solid"):
		solid = bool(plat.call("is_platform_solid"))
	lab.text = ("实 %0.2f" % t) if solid else ("隐 %0.2f" % t)
