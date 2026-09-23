class_name PlayerNames
extends RefCounted

## 默认名字池：中国神话人物。
##
## 语义是「**默认分配一个，玩家也能自己改**」，三句话说完：
##   · 手机上没输名字 → 大屏从池子里挑一个**还没被占**的给他（`pick()`）
##   · 手机自己报了名字 → 用他自己的，池子完全不参与
##   · 想改名 → 重发一次 HELLO 就行（`UdpServer` 会把旧名字覆盖掉）
##
## 名单**只有这一份**，三处共用：`UdpServer` 的兜底、大屏 `--simulate`、单跑 `simulator.tscn`。
## 加名字只改这里。
##
## 为什么用神话人物而不是「小明/小红」：反正都是假名字，不如选个记得住的 ——
## 调试时看日志「孙悟空 拉了一把」比「玩家 3 拉了一把」好认得多。
## 选人标准：2-4 字（HUD 一行放得下）、念得出、**一眼能分清**。
## 前五个正好是取经五人组，凑够 5 人时名单自带故事感。

const POOL := [
	"孙悟空", "猪八戒", "沙悟净", "唐僧", "白龙马",
	"哪吒", "二郎神", "红孩儿", "牛魔王",
]


## 按序号取名字（从 0 数）。越界就绕回来，负数也行 —— 
## 保证**任何**整数都能拿到名字，调用方不用自己写「超了怎么办」。
static func at(index: int) -> String:
	var n := POOL.size()
	return str(POOL[((index % n) + n) % n])


## 挑一个**还没被占用**的默认名字，给没报名字的玩家兜底。
## `taken` 传本房间已有的名字列表（可以带空格，这里会自己 strip 一遍）。
##
## 池子被占满了就退化成按人数取 —— 宁可重名，也不要「玩家 7」那种没人认得出的名字。
## 重名至少还能靠 HUD 上的槽位号和队伍颜色区分。
static func pick(taken: Array) -> String:
	var used := {}
	for t in taken:
		used[str(t).strip_edges()] = true
	for nm in POOL:
		if not used.has(nm):
			return str(nm)
	return at(used.size())


## 名字池里有没有这个名字（区分「玩家自己起的」和「系统分配」时用得上）
static func is_default(name: String) -> bool:
	return POOL.has(name.strip_edges())


static func size() -> int:
	return POOL.size()
