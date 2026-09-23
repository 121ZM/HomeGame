extends MiniGameSelfTest

## 拔河**自己带的**规则测试。放在玩法目录里，框架自检会扫出来跑
## （见 GameRegistry.selftest_scripts()）。
##
## 这些东西以前住在框架自检里 —— 那是把玩法焊进框架：框架的回归关卡会在**编译期**
## 点名依赖拔河，把 `scripts/minigames/tug/` 一删，自检直接 Parse Error，
## 连「框架还好不好」都验不出来了。现在它跟着玩法走：**删掉玩法，这组测试跟着消失，
## 框架那几组照常绿。**
##
## 测的都是玩法自己的规则：人数规则、绳子怎么动、什么时候算赢、奖励怎么换。


func title() -> String:
	return "拔河（玩法自带的规则测试）"


## 断言条数的下限。**加了断言记得同步调大** —— 运行时错误不会抛异常，
## 只会把当前函数当场中断，少掉的断言看起来和「全过」一模一样。
##
## 「挥动 → 往上蹦」这次改版后：67 → **72**。净 +5，逐条对账：
##   · 「持续倾斜慢慢蹭」一整组（2 条）        删 —— 倾斜通道被设计去掉了
##   · 「2v2 两人赢得更快」                改 —— 旧判据是写死的 `ticks < 60`（旧力量模型
##                                              下一次猛拉推得狠，一秒内到线）；新模型力量是
##                                              连续蹦劲 0.30/s，双人 0.60/s 约 1.7 秒（~100 tick），
##                                              写死数字失效 → 改成**同函数里实测单人耗时**再比大小。
##   · 「连续蹦劲把绳子拔过线」            增 —— 新增 `_jump_density()`，6 条
## 加起来：−2 + 1 + 6 = +5。
func expected_min() -> int:
	return 72


func run() -> void:
	_rule_counts()
	_jump_pull()
	_jump_density()
	_two_versus_two()
	_revive()
	_item()
	_wiring()


# ------------------------------------------------------------------ 人数规则

func _rule_counts() -> void:
	note("\n  · 人数规则（玩法自己声明，跟架构硬上限 8 人是两回事）")

	var tug := TugOfWar.new()
	ok(tug.min_players() == 2 and tug.max_players() == 4, "meta 声明 2-4 人")
	ok(tug.accepts_count(2), "2 人可开（1v1）")
	ok(tug.accepts_count(4), "4 人可开（2v2）")
	ok(not tug.accepts_count(3), "3 人不行（分不成两队）")
	ok(not tug.accepts_count(1), "1 人不行")
	ok(not tug.accepts_count(8), "8 人不行（超出玩法上限，虽然架构容得下）")
	var why3 := tug.why_not(3)
	ok(why3.findn("2 人") >= 0 and why3.findn("4 人") >= 0,
		"3 人时的原因指向「要均分两队」，而不是含糊的「不能开」：%s" % why3)
	tug.free()

	# 被框架扫到并注册了 —— 框架里没有任何一处点名它，全靠 meta() 被认出来
	ok(GameRegistry.find("tug") != null, "玩法脚本已被注册表扫到")
	ok("tug" in GameRegistry.ids(), "ids() 里有 tug")
	var e3 := {}
	for it in GameRegistry.evaluate(3):
		if str(it["id"]) == "tug":
			e3 = it
	ok(not e3.is_empty() and not bool(e3["ready"]), "3 人时它在列表里、但状态是开不了")


# ------------------------------------------------------------------ 绳子怎么动

func _jump_pull() -> void:
	note("\n  · 往上蹦：蹦劲把绳子朝自己这边推，过线就算赢")

	# 左队（槽位 0）一直在密蹦（drive 会把 filter.jump 打满）
	var tug := _new_tug(2)
	var ticks := drive(tug, [0], 5.0)
	var r := tug.result()
	ok(tug.is_over(), "对局已结束")
	ok(tug.winner_team == 0, "赢家是左队（槽位 0）")
	ok(tug.rope <= -TugOfWar.WIN_AT, "绳子到达左队边线 (rope=%.2f)" % tug.rope)
	ok(int(r["winner_slots"][0]) == 0, "结算里的获胜槽位正确")
	ok(int(r["jumps"][0]) > 0 and int(r["jumps"][1]) == 0, "只有左队有蹦记录")
	ok(str(r["text"]) != "", "结算文字非空：%s" % r["text"])
	note("      用时 %.1f 秒 / 蹦了 %d 次（%d tick）" % [tug.elapsed, int(r["jumps"][0]), ticks])
	tug.free()

	# 右队一直密蹦，方向应该反过来
	var tug2 := _new_tug(2)
	drive(tug2, [1], 5.0)
	ok(tug2.is_over(), "对局已结束")
	ok(tug2.winner_team == 1, "赢家是右队（槽位 1）")
	ok(tug2.rope >= TugOfWar.WIN_AT, "绳子到达右队边线 (rope=%.2f)" % tug2.rope)
	tug2.free()

	# 谁都不动 → 到点判僵持
	var tug3 := _new_tug(2)
	drive(tug3, [], TugOfWar.MAX_SECONDS + 2.0)
	var r3 := tug3.result()
	ok(tug3.is_over(), "时间到后对局结束")
	ok(tug3.winner_team == 2, "判为平局")
	ok(str(r3["text"]).contains("僵持"), "结算文字说明是僵持：%s" % r3["text"])
	ok(absf(tug3.rope) < 0.01, "绳子没有移动 (rope=%.3f)" % tug3.rope)
	tug3.free()


## 「往上蹦」是**连续**力量：拉力来自 `session.jump()`（0..1 的连续强度），
## 不是「一次挥动一拉」。这一组专门验证这一点，并顺手钉住「力量」和「计数」是
## **两条分开的通道**：绳子看连续蹦劲，蹦的次数看离散事件。
func _jump_density() -> void:
	note("\n  · 连续蹦劲：光靠 filter.jump 就能把绳子拔过线")

	# A. 只给连续强度、不给任何离散事件 → 绳子照样被拔过线
	var tug := _new_tug(2)
	var s0: PlayerSession = tug.sessions[0]
	var t := 0.0
	while t < 6.0 and not tug.is_over():
		s0.filter.jump = 1.0  # 一直在密蹦
		s0.events = []        # 故意不塞离散事件
		tug.tick(1.0 / 60.0)
		t += 1.0 / 60.0
	ok(tug.is_over(), "只靠连续蹦劲也能打到结束")
	ok(tug.winner_team == 0, "赢家是左队（槽位 0）")
	ok(tug.rope <= -TugOfWar.WIN_AT, "绳子到达左队边线 (rope=%.2f)" % tug.rope)
	ok(int(tug.result()["jumps"][0]) == 0, "没塞离散事件时蹦次数为 0（力量≠计数）")

	# B. 反过来：只有事件、强度为 0 → 绳子几乎不动，但次数照记
	var tug2 := _new_tug(2)
	var s: PlayerSession = tug2.sessions[0]
	for i in 30:
		s.filter.jump = 0.0
		s.events = [jump()]
		tug2.tick(1.0 / 60.0)
	ok(absf(tug2.rope) < 0.001, "只发事件、没有蹦劲 → 绳子几乎不动 (rope=%.4f)" % tug2.rope)
	ok(int(tug2.result()["jumps"][0]) == 30, "30 个蹦事件记成 30 次 (jumps=%d)" % int(tug2.result()["jumps"][0]))

	tug.free()
	tug2.free()


func _two_versus_two() -> void:
	note("\n  · 2v2：队伍按槽位奇偶分")

	var tug := _new_tug(4)
	ok(tug.team_of(0) == 0 and tug.team_of(2) == 0, "槽位 0、2 是左队")
	ok(tug.team_of(1) == 1 and tug.team_of(3) == 1, "槽位 1、3 是右队")

	# 同一个人一直密蹦，单人 1v1 与双人 2v2 各打一局：双人合力该更快到线。
	# 不写死 tick 数 —— 力量值（JUMP_PULL_PER_SEC）还会按手感调，写死就等着变红。
	var solo := _new_tug(2)
	var solo_ticks := drive(solo, [0], 5.0)
	ok(solo.winner_team == 0, "单人（1v1）也靠蹦劲取胜")
	solo.free()

	var ticks := drive(tug, [0, 2], 5.0)
	ok(tug.winner_team == 0, "左队（2 人）获胜")
	ok(ticks < solo_ticks, "两人合力赢得更快（双人 %d tick < 单人 %d tick）" % [ticks, solo_ticks])
	tug.free()


# ------------------------------------------------------------------ 奖励换来的规则

## 压线**不立刻判负**：先停下等落后方答题。答对拉回中线继续打，答错才判负。
func _revive() -> void:
	note("\n  · 复活：压线时答对一题，绳子回中线继续打")

	var tug := _new_tug(2, true)
	ok(tug.revive_left_count() == 1, "开局有 1 次复活额度")
	ok(tug.item_left_count() == 1, "开局有 1 次道具额度")

	drive(tug, [0], 5.0)
	ok(not tug.is_over(), "绳子压线了但**还没判负** —— 留着机会去答题")
	ok(tug.rope <= -TugOfWar.WIN_AT, "绳子停在线上 (rope=%.2f)" % tug.rope)

	var req := tug.pending_reward_request()
	ok(str(req.get("kind", "")) == "revive", "玩法提出的是复活请求")
	ok(int(req.get("slot", -1)) == 1, "请求挂在落后方（槽位 1，右队）身上")
	ok(str(req.get("reason", "")) != "", "请求带了给人看的说明：%s" % req.get("reason"))

	# 挂起期间绳子冻住
	tug.begin_reward(req)
	ok(tug.pending_reward_request().is_empty(), "等奖励期间不再重复提请求")
	var frozen := tug.rope
	drive(tug, [0], 2.0)
	ok(absf(tug.rope - frozen) < 0.0001, "等奖励期间绳子不动（对局挂起）")

	# 答对 → 拉回中线
	tug.apply_reward(req, true, {"detail": "答对第 3 题"})
	ok(not tug.is_over(), "救回来了，这局还没完")
	ok(absf(tug.rope) < 0.0001, "绳子回到中线 (rope=%.2f)" % tug.rope)
	ok(tug.revive_left_count() == 0, "复活额度已用掉")
	ok(tug.elapsed <= TugOfWar.MAX_SECONDS - TugOfWar.REVIVE_GRACE_SEC + 0.1,
		"给救回来的人留了至少 %.0f 秒" % TugOfWar.REVIVE_GRACE_SEC)

	# 再压线一次，额度没了 → 直接判负
	drive(tug, [0], 30.0)
	ok(tug.is_over(), "第二次压线直接判负（额度用完）")
	ok(tug.winner_team == 0, "左队获胜")
	ok(int(tug.result()["revives_used"]) == 1, "结算里记了用了 1 次复活")
	ok(str(tug.result()["text"]).contains("复活"), "结算文案带上了奖励消耗")
	tug.free()

	# 答错 → 判负，且赢家是压线那一队
	var tug2 := _new_tug(2, true)
	drive(tug2, [0], 5.0)
	var req2 := tug2.pending_reward_request()
	tug2.begin_reward(req2)
	tug2.apply_reward(req2, false, {"detail": "答错了：has → have"})
	ok(tug2.is_over(), "答错 → 直接判负")
	ok(tug2.winner_team == 0, "赢家是原本压线的那一队")
	ok(str(tug2.end_reason).contains("没能救回"), "判负原因写明是没救回：%s" % tug2.end_reason)
	tug2.free()


## 道具：落后 + 过了开放时间 → 答对换一记猛力一拽。
## 两道闸（时间 + 落后幅度）都要在，否则一开局就人人要道具。
func _item() -> void:
	note("\n  · 道具：落后到一定程度，答对换一记「猛力一拽」")

	var tug := _new_tug(2, true)

	# 开局就落后也不给 —— 得先打一会儿
	tug.rope = 0.7
	ok(tug.pending_reward_request().is_empty(), "开局 %.0f 秒内不开放道具" % TugOfWar.ITEM_UNLOCK_SEC)

	# 时间够了但没落后那么多，也不给
	tug.elapsed = TugOfWar.ITEM_UNLOCK_SEC + 1.0
	tug.rope = 0.2
	ok(tug.pending_reward_request().is_empty(), "没什么落后就不给道具")

	# 落后到一定程度 → 给（而且是给**落后**那一方）
	tug.rope = 0.7
	var req := tug.pending_reward_request()
	ok(str(req.get("kind", "")) == "item", "提出了道具请求")
	ok(str(req.get("item_id", "")) == "big_pull", "道具 id 是 big_pull")
	ok(int(req.get("slot", -1)) == 0, "道具给落后方（槽位 0，左队）")

	# 答对 → 绳子朝自己这边猛推
	var before := tug.rope
	tug.begin_reward(req)
	tug.apply_reward(req, true, {})
	ok(tug.rope < before, "答对后绳子朝落后方推进 (%.2f → %.2f)" % [before, tug.rope])
	ok(absf(tug.rope - (before - TugOfWar.ITEM_PULL)) < 0.0001, "推进量等于 ITEM_PULL")

	# 额度用完后不再提
	tug.elapsed = TugOfWar.ITEM_UNLOCK_SEC + 5.0
	tug.rope = 0.7
	ok(tug.pending_reward_request().is_empty(), "道具额度用完后不再提请求")
	ok(tug.item_left_count() == 0, "道具额度归零")

	# 答错 → 绳子不动（但额度照样消耗，不能反复白嫖）
	var tug2 := _new_tug(2, true)
	tug2.elapsed = TugOfWar.ITEM_UNLOCK_SEC + 1.0
	tug2.rope = 0.7
	var req2 := tug2.pending_reward_request()
	tug2.begin_reward(req2)
	tug2.apply_reward(req2, false, {})
	ok(absf(tug2.rope - 0.7) < 0.0001, "答错时绳子不动 (%.2f)" % tug2.rope)
	ok(tug2.item_left_count() == 0, "答错也消耗额度（不能反复白嫖）")

	tug.free()
	tug2.free()


# ------------------------------------------------------------------ 与框架的接线

## 玩法对框架暴露的那几个钩子：3D 场地要挂在**框架给的挂载点**下，分队标签要有。
## 这一组是「玩法侧的契约自检」—— 反过来框架那边也有一组盯着 HUD。
func _wiring() -> void:
	note("\n  · 与框架的接线：3D 场地挂在框架给的挂载点上、分队标签")

	var tug := TugOfWar.new()
	tug.sessions = make_sessions(2)
	tug.setup()

	ok(tug.slot_tag(0) == "左队" and tug.slot_tag(1) == "右队",
		"分队标签给的是「左队 / 右队」（色弱的人也认得出谁跟谁一边）")
	ok(not tug.status_text().is_empty(), "状态行有内容：%s" % tug.status_text())

	# 场地必须整块挂在框架给的挂载点下：挂到别处会同时躲开「换局清场」和
	# 「回大厅整块隐藏」，症状是回大厅后画面里还留着上一局的场地。
	var holder := Node3D.new()
	tug.build_field(holder)
	ok(holder.get_child_count() == 1, "场地挂上了（恰好 1 个节点，不多不少）")
	ok(holder.get_child(0) is Node3D, "挂上去的是个 3D 节点（场地归玩法自己搭）")
	var cam := tug.field_camera()
	ok(cam.get("position") is Vector3, "声明了自己的取景（相机位置）")
	ok(cam.get("rotation_deg") is Vector3, "声明了自己的取景（俯角）")
	tug.tick_field(1.0 / 60.0)
	ok(tug.rope_normalized() >= -1.0 and tug.rope_normalized() <= 1.0,
		"喂给场地的绳子位置在 -1..1 之间")

	holder.free()
	tug.free()


# ------------------------------------------------------------------ 小工具

## 造一个拔河实例。
## [param with_rewards] 默认 false —— 基础规则测试要把道具/复活额度清零，
## 否则绳子一到线就挂起等奖励，根本走不到判负那一步（这个坑踩过）。
func _new_tug(player_count: int, with_rewards: bool = false) -> TugOfWar:
	var tug := TugOfWar.new()
	tug.sessions = make_sessions(player_count)
	tug.setup()  # setup() 会把额度重置成默认值，所以覆盖必须放在它之后
	if not with_rewards:
		tug.revive_left = 0
		tug.item_left = 0
	return tug
