extends RefCounted
class_name StoryData

# 序章：醒来（进入第一关前触发）
static var prologue: Array = [
	{"speaker": "", "text": "……"},
	{"speaker": "", "text": "你睁开眼。"},
	{"speaker": "", "text": "四周是无尽的黑暗，手中只剩一盏将熄的灯笼。"},
	{"speaker": "", "text": "你不记得自己是谁。"},
	{"speaker": "", "text": "但你感觉到——黑暗中，有什么东西在注视着你。"},
	{"speaker": "", "text": "（灯笼微弱地闪烁了一下）"},
	{"speaker": "", "text": "走吧。总不能待在原地。"},
]

# 第一关通关后
static var level1_after: Array = [
	{"speaker": "", "text": "（你停下脚步。灯笼的光照到了地面上——）"},
	{"speaker": "", "text": "（一个模糊的影子出现了。）"},
	{"speaker": "你", "text": "……你是谁？"},
	{"speaker": "", "text": "（影子没有回答，只是微微动了一下，指向了前方的路。）"},
	{"speaker": "", "text": "你盯着它看了很久。"},
	{"speaker": "", "text": "那是……你自己的影子？"},
	{"speaker": "", "text": "它似乎一直在等你。"},
]

# 第二关通关后
static var level2_after: Array = [
	{"speaker": "", "text": "（影子停在一面石壁前，石壁上刻着模糊的文字。）"},
	{"speaker": "", "text": "「我与我周旋久，宁作我。」"},
	{"speaker": "你", "text": "……这是什么意思？"},
	{"speaker": "", "text": "（影子轻轻触碰了石壁，文字发出微弱的光芒。）"},
	{"speaker": "", "text": "你隐约觉得，这句话很重要。"},
	{"speaker": "", "text": "重要到……你曾经用它来对抗过什么。"},
]

# 第三关通关后
static var level3_after: Array = [
	{"speaker": "", "text": "（影子突然消失了。你慌了。）"},
	{"speaker": "你", "text": "等等——！"},
	{"speaker": "", "text": "（片刻后，影子从对面的墙壁中浮现，向你伸出了手。）"},
	{"speaker": "你", "text": "……你没有离开。"},
	{"speaker": "", "text": "（影子摇了摇头，又点了点头。）"},
	{"speaker": "", "text": "你第一次意识到——"},
	{"speaker": "", "text": "它不是在为你引路。"},
	{"speaker": "", "text": "它是在等你自己走完这段路。"},
]

# 第四关通关后
static var level4_after: Array = [
	{"speaker": "", "text": "（壁画上描绘着一个画面：）"},
	{"speaker": "", "text": "（一个人亲手将自己的影子从脚下撕下，丢入深渊。）"},
	{"speaker": "你", "text": "……我想起来了。"},
	{"speaker": "你", "text": "是我。是我把你丢掉的。"},
	{"speaker": "", "text": "（影子静静地看着你，没有愤怒，没有悲伤。）"},
	{"speaker": "你", "text": "我害怕你。你承载了我不愿面对的一切——"},
	{"speaker": "你", "text": "我的软弱，我的恐惧，我的不甘。"},
	{"speaker": "你", "text": "我以为丢掉你，我就能变得更强。"},
	{"speaker": "", "text": "（灯笼的光突然变亮了一些。）"},
	{"speaker": "你", "text": "但没有你的世界……一片漆黑。"},
	{"speaker": "", "text": "（影子轻轻向你走近了一步。）"},
	{"speaker": "你", "text": "对不起。"},
]

# 第五关通关后（结局）
static var level5_after: Array = [
	{"speaker": "", "text": "（风暴平息。你们站在渊的边缘，头顶是久违的天空。）"},
	{"speaker": "", "text": "你回头望向深渊。"},
	{"speaker": "", "text": "无数影子在黑暗中闪烁，像是无数双等待被认领的眼睛。"},
	{"speaker": "", "text": "（你低头看向自己的影子。）"},
	{"speaker": "你", "text": "走吧。和我一起回去。"},
	{"speaker": "", "text": "（影子第一次笑了——）"},
	{"speaker": "", "text": "（虽然你看不见它的脸，但你确信它在笑。）"},
	{"speaker": "", "text": ""},
	{"speaker": "", "text": "「我与我周旋久，宁作我。」"},
	{"speaker": "", "text": ""},
	{"speaker": "", "text": "——与自己和好，是这世上最漫长的旅途。"},
	{"speaker": "", "text": ""},
	{"speaker": "", "text": "我与我周旋久"},
	{"speaker": "", "text": "（FIN）"},
]

# 隐藏结局（每关都不跳过对话触发）
static var hidden_ending: Array = [
	{"speaker": "", "text": "（白屏之后，一行小字缓缓浮现——）"},
	{"speaker": "", "text": "那些被你丢掉的影子，终会在某个黑暗的角落等你。"},
	{"speaker": "", "text": "而你需要做的，只是愿意回头看一眼。"},
]

# 第二关开场：地面看守（Base Enemy）
static var level2_enemy_intro: Array = [
	{"speaker": "", "text": "黑暗里，有东西贴着地面爬行。"},
	{"speaker": "", "text": "它们会追你。被咬到，灯笼的光会弱一截。"},
	{"speaker": "", "text": "用 J 挥灯近身，或用 L 射出光球。"},
	{"speaker": "", "text": "按 K 留下影子——它们有时会去咬影子，而不是你。"},
]

# 第三关开场：提灯狐妖（技能：释放光球 / 铺蓝色光晕）
static var level3_fox_intro: Array = [
	{"speaker": "", "text": "空中飘着提灯的狐。灯火是幽蓝的。"},
	{"speaker": "", "text": "提灯会蓄力，然后放出光球。躲开，或用 L 对射打掉。"},
	{"speaker": "", "text": "它还会在地面铺开蓝色光晕。踩上去，左右会颠倒，但这一跳会更高。"},
	{"speaker": "", "text": "近身砍不到提灯。用 L 斜上瞄准，更容易打中灯。"},
	{"speaker": "", "text": "灯碎时后退——碎光会伤人，也会落下可拾取的星。"},
]


static func get_dialogue(stage: String) -> Array:
	match stage:
		"prologue":
			return prologue
		"level1_after":
			return level1_after
		"level2_after":
			return level2_after
		"level3_after":
			return level3_after
		"level4_after":
			return level4_after
		"level5_after":
			return level5_after
		"hidden_ending":
			return hidden_ending
		"level2_enemy_intro":
			return level2_enemy_intro
		"level3_fox_intro":
			return level3_fox_intro
		_:
			return []
