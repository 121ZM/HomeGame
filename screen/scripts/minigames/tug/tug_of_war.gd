class_name TugOfWar
extends MiniGame

## 拔河 —— 本项目第一个玩法，存在的意义是**验证框架接口够不够用**。
##
## 规则：奇数槽位一队、偶数槽位一队（2 人 = 1v1，4 人 = 2v2）。
##   挥动手机  → 一次猛拉，power 越大拉得越狠
##   持续倾斜  → 慢慢蹭（小力，用来奖励「一直用力拉着」的状态）
## 绳子被拉到自己的 −1 / +1 就赢；40 秒到点还没到线，看谁占优。
##
## 奖励（道具 / 复活）—— 这就是「边玩边学」的挂钩：
##   复活  绳子被拔到线上时，落后方还有一次机会：答对一题，绳子拉回中线，比赛继续
##   道具  落后到一定程度后，答对一题换一记「猛力一拽」，绳子朝自己猛推一段
## 两者都**各只有一次**，而且都必须靠答题（或看广告）换来 —— 玩法只负责说
## 「我需要什么」，至于奖励怎么来，它一概不知道。

## 满强度每秒推多少。力量来自「连续蹦劲」（`session.jump()`），不再来自离散挥动。
##
## 定值理由：旧模型的有效拉力约 0.05/s（0.8 次/秒 × 0.085 × 0.7）+ 倾斜 0.22/s；
## 倾斜通道去掉后全靠蹦，要让两头都成立：
##   · 势均力敌 → 两队满强度对推净差为 0，打满 40 秒仍僵持
##   · 一方明显更密 → 差 20% 强度 ≈ 0.06/s，约 17 秒到线
## 0.30 是这两头的折中。**这个数是拍出来的初值，手感待真机验证。**
const JUMP_PULL_PER_SEC := 0.30
const WIN_AT := 1.0                # 拉到 ±1 即出线
const MAX_SECONDS := 40.0
const DRAW_EPS := 0.06             # 时间到时差这么点就算僵持

## 奖励额度：一局各一次。给多了「边玩边学」就变成「一直答题」了。
const REVIVE_QUOTA := 1
const ITEM_QUOTA := 1
## 道具「猛力一拽」一次推多少
const ITEM_PULL := 0.35
## 落后到这个程度才开放道具（要不一开局就人人要道具）
const ITEM_TRIGGER := 0.55
## 开局多少秒后才开放道具
const ITEM_UNLOCK_SEC := 8.0
## 复活成功时至少给这么多秒把优势打回来，免得好不容易救回来又立刻到点
const REVIVE_GRACE_SEC := 8.0

var rope: float = 0.0              # 负 = 左队占优，正 = 右队占优
var elapsed: float = 0.0
var jumps: Array[int] = [0, 0]     # 各队累计蹦了几次（离散事件计数，不是力量来源）
var winner_team: int = -1          # -1 未决 / 0 左 / 1 右 / 2 draw
var end_reason: String = ""

var revive_left: int = REVIVE_QUOTA
var item_left: int = ITEM_QUOTA

var _over: bool = false
var _hud_accent: Color = Color.WHITE
var _last_count: int = -1
## 正在等的奖励请求（空 = 没在等）。tick 期间对局挂起。
var _reward_pending: Dictionary = {}
## 绳子已被拔过线（值是把它拔过线的那一队），等着看有没有人来救
var _line_crossed: int = -1


func meta() -> Dictionary:
	return {
		"id": "tug",
		"name": "拔河",
		"desc": "对着手机往上蹦，蹦得越密拉力越大。奇数位置一队，偶数位置一队。",
		"min_players": 2,
		"max_players": 4,
		"inputs": ["jump"],
	}


## 拔河必须能均分两队：2 人或 4 人
func accepts_count(n: int) -> bool:
	return n == 2 or n == 4


## 3 人是唯一「人数在区间里、但打不了」的情况，值得单独解释一句 ——
## 否则大厅只会说「不能开」，家长还得自己猜为什么。
func why_not(n: int) -> String:
	if n >= min_players() and n <= max_players() and not accepts_count(n):
		return "要均分两队，得 2 人或 4 人"
	return super(n)


func setup() -> void:
	rope = 0.0
	elapsed = 0.0
	jumps = [0, 0]
	winner_team = -1
	end_reason = ""
	_over = false
	_last_count = -1
	revive_left = REVIVE_QUOTA
	item_left = ITEM_QUOTA
	_reward_pending = {}
	_line_crossed = -1

	var left := team_slots(0)
	var right := team_slots(1)
	print("[tug] 左队 %s  vs  右队 %s" % [
		_slot_names(left), _slot_names(right),
	])
	print("[tug] 本局奖励：复活 %d 次、道具「猛力一拽」%d 次（都要答题/看广告换）" % [
		revive_left, item_left,
	])

	# 开局清一次事件队列：大厅/倒计时期间攒下的事件不该在开局瞬间一起炸出来
	for i in sessions.size():
		var s := session_for_slot(i)
		if s != null:
			s.drain_events()


## 队伍 0 = 偶数槽位，队伍 1 = 奇数槽位
func team_of(slot: int) -> int:
	return 0 if slot % 2 == 0 else 1


## 玩家名后面跟的队标。颜色之外再给一条线索，色弱的人也认得出谁跟谁一队。
func slot_tag(slot: int) -> String:
	return "左队" if team_of(slot) == 0 else "右队"


# ------------------------------------------------------------------ 3D 场地

## 3D 场地（绳子、出线柱、地面……）。**整块归玩法自己**，框架只给挂载点。
var _field: TugField = null


## 框架在开局时调一次，给一个空的挂载点。
func build_field(parent: Node3D) -> void:
	_field = TugField.new()
	parent.add_child(_field)
	_field.build()


## 每帧推一次画面。框架只在场地可见时调（大厅里不调）。
##
## 结算时对局已定、`rope` 不再变，这里算出来的就是最终画面 ——
## 所以「绳子冻在出线处」不需要额外写什么，别在状态没变时乱动就行。
func tick_field(_delta: float) -> void:
	if _field != null:
		_field.set_rope(rope_normalized())


## 舞台取景由场地声明（相机取景的理由写在 TugField.camera_view 里 —— 现在是正中、拉近、铺满全屏）
func field_camera() -> Dictionary:
	return TugField.camera_view()


# ------------------------------------------------------------------ 2D 封面画

## 大厅磁贴里那张封面。**和 3D 场地同源**：同一套颜色、同一个构图，
## 所以大厅里看到的和点进去看到的是同一个东西（画法详见 `TugCover`）。
##
## 框架只给一块空白的画板，画什么由玩法决定 —— 删掉这个玩法目录，框架照常跑。
func build_cover(parent: Control) -> void:
	var cover := TugCover.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(cover)


func team_slots(team: int) -> Array[int]:
	var out: Array[int] = []
	for i in sessions.size():
		if team_of(i) == team:
			out.append(i)
	return out


func countdown(t: float) -> void:
	# 倒计时期间绳子不动，玩家摆好姿势就行
	var sec := int(ceil(t))
	if sec != _last_count:
		_last_count = sec
		if sec > 0:
			print("[tug] 倒计时 %d" % sec)


func tick(delta: float) -> void:
	if _over:
		return
	# 正在等奖励结果 —— 对局挂起，绳子冻住（框架那边也不会 tick 我，这是双保险）
	if not _reward_pending.is_empty():
		return

	elapsed += delta

	for i in sessions.size():
		var s: PlayerSession = session_for_slot(i)
		if s == null:
			continue
		var dir := -1.0 if team_of(i) == 0 else 1.0

		# 力量来自**连续蹦劲**（`s.jump()`），不是离散事件：
		# 蹦得越密，jump 长期越接近 1，推得越快；蹦一次就停，它衰减回 0，推不动。
		rope += dir * JUMP_PULL_PER_SEC * s.jump() * delta

		# 离散事件只用来**数「蹦了几次」**（给状态行和将来的音效用）。
		# 仍用 drain_events() 取走即清空 —— 否则帧率高于发包率时一次蹦会被重复计数。
		for e in s.drain_events():
			if str(e.get("type", "")) != "jump":
				continue
			jumps[team_of(i)] += 1

	rope = clampf(rope, -1.25, 1.25)
	_hud_accent = team_color(0 if rope < 0.0 else 1)

	if rope <= -WIN_AT:
		_reach_line(0)
	elif rope >= WIN_AT:
		_reach_line(1)
	elif elapsed >= MAX_SECONDS:
		if absf(rope) < DRAW_EPS:
			_finish(2, "时间到，僵持不下")
		else:
			_finish(0 if rope < 0.0 else 1, "时间到，占优")


## 绳子被拔过线了。
## 注意这里**不立刻判负** —— 只要落后方还有复活额度，就先停在线上，
## 让框架去问一次「答案对不对」。答对就救回来，答错再判负。
func _reach_line(winner_team: int) -> void:
	_line_crossed = winner_team
	if revive_left > 0:
		rope = clampf(rope, -WIN_AT, WIN_AT)
		return
	_finish(winner_team, "把绳子拔过线")


# ------------------------------------------------------------------ 奖励接口

func reward_catalog() -> Dictionary:
	return {
		"revive": {
			"quota": REVIVE_QUOTA,
			"left": revive_left,
			"reason": "绳子被拔过线时，答对一题把它拉回中线",
		},
		"items": [{
			"id": "big_pull",
			"name": "猛力一拽",
			"left": item_left,
			"desc": "答对一题，绳子朝自己这边猛推 %.0f%%" % (ITEM_PULL * 100.0),
		}],
	}


func pending_reward_request() -> Dictionary:
	if _over or not _reward_pending.is_empty():
		return {}

	# 1) 压线了 —— 最高优先级，救回来这局就还没输
	if _line_crossed >= 0 and revive_left > 0:
		var loser := 1 - _line_crossed
		return {
			"kind": "revive",
			"slot": first_slot_of_team(loser),
			"reason": "绳子就要被拔过线了 —— 答对一题，把它拉回中线",
		}

	# 2) 落后到一定程度，给落后方一次挣道具的机会
	if item_left > 0 and elapsed >= ITEM_UNLOCK_SEC and absf(rope) >= ITEM_TRIGGER:
		var behind := 1 if rope < 0.0 else 0
		return {
			"kind": "item",
			"item_id": "big_pull",
			"slot": first_slot_of_team(behind),
			"reason": "落后了 —— 答对一题换一记「猛力一拽」",
		}

	return {}


func begin_reward(req: Dictionary) -> void:
	_reward_pending = req


func apply_reward(req: Dictionary, granted: bool, data: Dictionary) -> void:
	_reward_pending = {}
	var kind := str(req.get("kind", ""))
	var detail := str(data.get("detail", ""))
	var tail := "（%s）" % detail if not detail.is_empty() else ""

	match kind:
		"revive":
			revive_left -= 1
			if granted:
				# 救回来了：绳子回中线，比赛继续 —— 这一局还没完
				rope = 0.0
				_line_crossed = -1
				# 压线时往往已经快到点了，至少留出 REVIVE_GRACE_SEC 让救回来的人有机会
				elapsed = minf(elapsed, MAX_SECONDS - REVIVE_GRACE_SEC)
				print("[tug] 复活成功 —— 绳子拉回中线，比赛继续%s" % tail)
			else:
				var loser := team_of(int(req.get("slot", 0)))
				_line_crossed = -1
				_finish(1 - loser, "没能救回，绳子被拔过线")
		"item":
			item_left -= 1
			if granted:
				var team := team_of(int(req.get("slot", 0)))
				var dir := -1.0 if team == 0 else 1.0
				rope = clampf(rope + dir * ITEM_PULL, -1.25, 1.25)
				print("[tug] 道具生效 —— %s队猛拉 %.2f，绳子到 %+.2f%s" % [
					"左" if team == 0 else "右", ITEM_PULL, rope, tail,
				])
			else:
				print("[tug] 道具没拿到，绳子不动%s" % tail)
		_:
			push_warning("[tug] 不认识的奖励类型：%s" % kind)


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
	var text := ""
	match winner_team:
		0: text = "左队胜（%s）—— %s" % [_slot_names(team_slots(0)), end_reason]
		1: text = "右队胜（%s）—— %s" % [_slot_names(team_slots(1)), end_reason]
		2: text = "平局 —— %s" % end_reason
	# 把奖励消耗也带上：家长能一眼看出孩子这局答了几次题
	var used: Array = []
	if revive_left < REVIVE_QUOTA:
		used.append("复活 %d 次" % (REVIVE_QUOTA - revive_left))
	if item_left < ITEM_QUOTA:
		used.append("道具 %d 次" % (ITEM_QUOTA - item_left))
	if not used.is_empty():
		text += "（本局用了：%s）" % "、".join(used)
	return {
		"game": "tug",
		"winner_team": winner_team,
		"winner_slots": team_slots(winner_team) if winner_team in [0, 1] else [],
		"rope": rope,
		"elapsed": elapsed,
		"jumps": jumps,
		"revives_used": REVIVE_QUOTA - revive_left,
		"items_used": ITEM_QUOTA - item_left,
		"text": text,
	}


func status_text() -> String:
	var extra := ""
	if not _reward_pending.is_empty():
		extra = "   ⏸ 等奖励中（%s）" % ("复活" if str(_reward_pending.get("kind", "")) == "revive" else "道具")
	elif _line_crossed >= 0:
		extra = "   ⚠ 压线待救"
	# 只放「现在最该看的一件事」：绳子偏到哪、双方蹦了多少次、还剩多久，外加警报。
	# 「额度」是次要信息，挪到 status_meta() —— 挤在这一行会在电视上折得很难看。
	# 不塞玩法名、不换行：新对局屏的顶部细横条会原样复用这条串。
	return "绳子 %+.2f   左队 %d · 右队 %d   剩 %.0f 秒%s" % [
		rope, jumps[0], jumps[1], maxf(MAX_SECONDS - elapsed, 0.0), extra,
	]


## 次要信息那一行：奖励额度还剩几次。两次都用完（或者这局根本不给）就没必要占地方。
## **顶部细横条容不下一整句**，所以对局屏优先用下面的 `status_badges()`；
## 这个方法保留给日志 / 兜底显示。
func status_meta() -> String:
	if revive_left <= 0 and item_left <= 0:
		return ""
	return "还有 复活 %d 次 · 道具 %d 次" % [revive_left, item_left]


## 顶部细横条右端的紧凑徽标：复活 / 道具各一枚「图标 + 数字」。
## 全列出来（HUD 自己跳过 0 的项），这样「额度用完了」和「本来就没有」在 HUD 眼里一致 ——
## 都是不画。额度一局只发 1 次，所以数字基本是 1；留着 `n` 字段是给将来加额度用。
func status_badges() -> Array:
	return [
		{"icon": "revive", "n": revive_left},
		{"icon": "item", "n": item_left},
	]


## HUD 用：绳子当前偏向哪队的颜色
func hud_accent() -> Color:
	return _hud_accent


func team_color(team: int) -> Color:
	return PlayerPalette.color_for_team(team)


## 绳子归一化位置，-1..1，给 HUD / 3D 视图用
func rope_normalized() -> float:
	return clampf(rope, -1.0, 1.0)


func _finish(team: int, reason: String) -> void:
	winner_team = team
	end_reason = reason
	_over = true


func _slot_names(slots: Array[int]) -> String:
	var names := PackedStringArray()
	for slot in slots:
		var s := session_for_slot(slot)
		names.append(s.display_name() if s != null else "空位 %d" % slot)
	return "、".join(names) if names.size() > 0 else "（无人）"
