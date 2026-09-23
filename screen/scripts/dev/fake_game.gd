class_name FakeGame
extends MiniGame

## **测试用的假玩法** —— 框架自检的底盘，不是给人玩的，也不进大厅。
##
## 为什么需要它：框架那几组测试（流程状态机、奖励挂起与恢复、掉线、大厅）
## 都要**有一个具体的玩法在跑**才能验。以前它们直接拿真玩法当载体 ——
## 于是「框架自检」在编译期就点名依赖了那个玩法，把玩法目录删掉，自检直接编译不过，
## 框架的回归关卡跟着一起死。这正是「玩法和框架要分开」这条规矩要防的事。
##
## 所以框架测试改用这个自己的假玩法当载体：它跟着框架走，删任何玩法都不影响它。
## 真玩法自己的规则测试写在玩法目录里（比如 minigames/tug/tug_selftest.gd）。
##
## 它的形状是**照着拔河抄的**（一个 -1..1 的标量 + 压线问复活 + 落后问道具），
## 就是为了让框架那几组测试换个 id 就能原样跑 —— 断言一个字都不用改。
## 换句话说：**这里的物理不重要，重要的是它对框架暴露的事件顺序**。

const WIN_AT := 1.0
const MAX_SECONDS := 40.0
## 满强度每秒推多少。**和真玩法同款：力量来自连续蹦劲（`s.jump()`），不是离散事件。**
## 假玩法的物理不重要，重要的是它对框架暴露的那条路和真玩法一致 —— 这样框架这几组
## 测试测到的就是真玩法会走的那条路（输入强度 → 位移 → 压线 → 奖励）。
const JUMP_PULL_PER_SEC := 0.30

const REVIVE_QUOTA := 1
const ITEM_QUOTA := 1
const ITEM_PULL := 0.35
const ITEM_TRIGGER := 0.55
const ITEM_UNLOCK_SEC := 8.0
const REVIVE_GRACE_SEC := 8.0

## 这个假玩法的 id 和名字。框架测试里一律引用它们，别写字面量。
const ID := "fake"
const NAME := "假玩法"

var rope: float = 0.0
var elapsed: float = 0.0
var jumps: Array[int] = [0, 0]
var winner_team: int = -1
var end_reason: String = ""

var revive_left: int = REVIVE_QUOTA
var item_left: int = ITEM_QUOTA

var _over: bool = false
var _reward_pending: Dictionary = {}
var _line_crossed: int = -1

## 框架调 `build_cover()` 的次数。**自检靠它证明「封面确实交给了玩法去画」。**
##
## 只断言「磁贴里有个框」是不够的 —— 那是框架自己也能摆出来的东西，
## 证明不了「框架真的把画板递到了玩法手里」。计数才是那条契约的直接证据。
static var cover_builds: int = 0
## 假玩法画的那块封面的节点名。自检按名字把它从画板底下捞出来。
const COVER_NODE_NAME := "fake_cover"


## 假玩法的封面：一块纯色方块。形状不重要，**重要的是它由玩法挂上去**。
func build_cover(parent: Control) -> void:
	cover_builds += 1
	var rect := ColorRect.new()
	rect.name = COVER_NODE_NAME
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color("b8b0a0")
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(rect)


func meta() -> Dictionary:
	return {
		"id": ID,
		"name": NAME,
		"desc": "框架自检用的假玩法：一个 -1..1 的标量 + 两次奖励机会。",
		"min_players": 2,
		"max_players": 4,
		"inputs": ["jump"],
		# 排在真玩法前面，自检里 index/选中之类的断言以它为准
		"order": -100,
	}


## 和拔河同款规则：2 人或 4 人（用来验「人数在区间里但打不了」这条）
func accepts_count(n: int) -> bool:
	return n == 2 or n == 4


func why_not(n: int) -> String:
	if n >= min_players() and n <= max_players() and not accepts_count(n):
		return "假玩法要均分两队，得 2 人或 4 人"
	return super(n)


func setup() -> void:
	rope = 0.0
	elapsed = 0.0
	jumps = [0, 0]
	winner_team = -1
	end_reason = ""
	_over = false
	revive_left = REVIVE_QUOTA
	item_left = ITEM_QUOTA
	_reward_pending = {}
	_line_crossed = -1
	for i in sessions.size():
		var s := session_for_slot(i)
		if s != null:
			s.drain_events()


func team_of(slot: int) -> int:
	return 0 if slot % 2 == 0 else 1


## 玩家名后面跟的队标 —— 框架的 HUD 契约测试要验「分队玩法在药丸上标了队别」，
## 所以假玩法也得会分队。不分组的玩法留空即可（MiniGame.slot_tag 的默认行为）。
func slot_tag(slot: int) -> String:
	return "左队" if team_of(slot) == 0 else "右队"


func team_slots(team: int) -> Array[int]:
	var out: Array[int] = []
	for i in sessions.size():
		if team_of(i) == team:
			out.append(i)
	return out


func tick(delta: float) -> void:
	if _over:
		return
	elapsed += delta
	for i in sessions.size():
		var s := session_for_slot(i)
		if s == null:
			continue
		var dir := -1.0 if team_of(i) == 0 else 1.0
		# 力量来自**连续蹦劲**（`s.jump()`），和真玩法同款 —— 框架这几组测试测到的
		# 就是真玩法会走的那条路（输入强度 → 位移 → 压线 → 奖励）。
		rope += dir * JUMP_PULL_PER_SEC * s.jump() * delta
		# 离散事件只用来数「蹦了几次」。
		# 取走即清空：一次蹦在好几帧里躺着会被重复计数（见 memory 里的教训）。
		for e in s.drain_events():
			# 事件字典的键是 "type"（输入抽象层 MotionFilter 产出的形状）
			if str(e.get("type", "")) == "jump":
				jumps[team_of(i)] += 1
	rope = clampf(rope, -1.25, 1.25)
	if absf(rope) >= WIN_AT:
		_reach_line(0 if rope < 0.0 else 1)
	if elapsed >= MAX_SECONDS and not _over:
		if absf(rope) < 0.01:
			_finish(2, "时间到，僵持")
		else:
			_finish(0 if rope < 0.0 else 1, "时间到，占优")


func _reach_line(crosser: int) -> void:
	if revive_left > 0:
		# 压线不立刻判负：留着一次复活机会。
		# 绳头就停在线上 —— 不夹住的话它会继续往里钻，下一帧又「压线」一次，
		# 额度还没用掉就先判负了（真玩法也是这么夹的，形状对齐）。
		_line_crossed = crosser
		rope = clampf(rope, -WIN_AT, WIN_AT)
		return
	_finish(crosser, "把绳子拔过了线")


func reward_catalog() -> Dictionary:
	return {
		"revive": {"quota": REVIVE_QUOTA, "left": revive_left, "reason": "压线待救"},
		"items": [{"id": "big_pull", "name": "猛力一拽", "left": item_left, "desc": "推一段"}],
	}


func pending_reward_request() -> Dictionary:
	if _over or not _reward_pending.is_empty():
		return {}
	if _line_crossed >= 0 and revive_left > 0:
		return {"kind": "revive", "slot": first_slot_of_team(_line_crossed), "reason": "压线待救"}
	if item_left > 0 and elapsed >= ITEM_UNLOCK_SEC and absf(rope) >= ITEM_TRIGGER:
		# rope 为负 = 左队领先，落后的是右队（1）—— 给落后方，不是给领先方
		var behind := 1 if rope < 0.0 else 0
		return {"kind": "item", "item_id": "big_pull", "slot": first_slot_of_team(behind), "reason": "落后太多"}
	return {}


func begin_reward(req: Dictionary) -> void:
	_reward_pending = req


func apply_reward(req: Dictionary, granted: bool, _data: Dictionary) -> void:
	var kind := str(req.get("kind", ""))
	_reward_pending = {}
	if kind == "revive":
		revive_left -= 1
		if granted:
			rope = 0.0
			_line_crossed = -1
			elapsed = minf(elapsed, MAX_SECONDS - REVIVE_GRACE_SEC)
		else:
			_finish(_line_crossed if _line_crossed >= 0 else 0, "没能救回")
	elif kind == "item":
		item_left -= 1
		if granted:
			rope += (-ITEM_PULL if rope > 0.0 else ITEM_PULL)


func first_slot_of_team(team: int) -> int:
	for i in sessions.size():
		if team_of(i) == team and session_for_slot(i) != null:
			return i
	return -1


func revive_left_count() -> int:
	return revive_left


func item_left_count() -> int:
	return item_left


func is_over() -> bool:
	return _over


func result() -> Dictionary:
	return {
		"game": ID,
		"winner_team": winner_team,
		"winner_slots": team_slots(winner_team) if winner_team in [0, 1] else [],
		"rope": rope,
		"elapsed": elapsed,
		"jumps": jumps,
		"revives_used": REVIVE_QUOTA - revive_left,
		"items_used": ITEM_QUOTA - item_left,
		"text": "假玩法：%s" % end_reason,
	}


func status_text() -> String:
	# 带「左队 N · 右队 N」，好让 HUD 契约那条「顶部横条抠得出两队数字」的断言有东西可查
	# （真实玩法如拔河的 status_text 就是这个格式）。
	return "标量 %+.2f   左队 %d · 右队 %d   剩 %.0f 秒" % [
		rope, jumps[0], jumps[1], maxf(MAX_SECONDS - elapsed, 0.0),
	]


func status_meta() -> String:
	return "还有 复活 %d 次 · 道具 %d 次" % [revive_left, item_left]


## 顶部细横条右端的紧凑徽标（与拔河同款）。假玩法也提供，好让 HUD 契约那条
## 「徽标上屏」的断言有东西可查。
func status_badges() -> Array:
	return [
		{"icon": "revive", "n": revive_left},
		{"icon": "item", "n": item_left},
	]


func _finish(team: int, reason: String) -> void:
	_over = true
	winner_team = team
	end_reason = reason
	_line_crossed = -1
