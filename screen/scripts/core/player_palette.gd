class_name PlayerPalette
extends RefCounted

## 玩家颜色表 —— 框架公共能力的一部分。
##
## 顺序即槽位号。挑色的标准是**在客厅距离上互相分得开**，不是好看：
## 相邻槽位刻意拉开色相，红/橙不相邻，绿/青不相邻。
## 两个人的局永远拿 0、1（红、蓝）—— 对比最强的那一对。

const COLORS: Array[Color] = [
	Color("e5484d"),  # 0 红
	Color("3b82f6"),  # 1 蓝
	Color("f5b301"),  # 2 黄
	Color("2fbf71"),  # 3 绿
	Color("a855f7"),  # 4 紫
	Color("f97316"),  # 5 橙
	Color("06b6d4"),  # 6 青
	Color("ec4899"),  # 7 粉
]

const FALLBACK := Color("9ca3af")  # 灰，兜底


static func color_for_slot(slot: int) -> Color:
	if slot < 0 or slot >= COLORS.size():
		return FALLBACK
	return COLORS[slot]


static func count() -> int:
	return COLORS.size()


## 队伍色（拔河这种分队玩法用）：队伍下标 0 / 1
static func color_for_team(team: int) -> Color:
	return color_for_slot(0 if team == 0 else 1)
