extends Node

## 框架自检。开发期的回归关卡 —— 改完 core/ 或加新玩法后跑一遍。
##
##   godot --headless --path screen res://tools/selfcheck.tscn
##
## 退出码 0 = 全过，1 = 有失败（方便接 CI）。
##
## ## 这个文件里**不许出现任何一个玩法的名字、id 或路径**
##
## 这是「玩法和框架分开」那条规矩在测试上的落地。判断标准很直白：把
## `scripts/minigames/<某玩法>/` 整个目录删掉，框架（含这份自检）必须照常跑 ——
## 只是大厅里少一个玩法、少跑几组玩法自带的测试。
##
## 要做到这一点，两件事必须成立：
##   1. 框架这几组测试（状态机 / 奖励挂起与恢复 / 掉线 / 大厅 / HUD）用**框架自己的
##      假玩法**（scripts/dev/fake_game.gd）当载体，而不是拿某个真玩法来当挡箭牌；
##   2. 玩法自己的规则测试住在玩法目录里（`*_selftest.gd`，继承 MiniGameSelfTest），
##      由这里**扫目录扫出来跑** —— 我不认识它们是谁的。
##
## 最后还有一组 [可插拔] 专门盯着这条规矩本身：剥掉注释扫一遍框架源码，
## 不许出现任何玩法的 id / 名字 / 目录名。规矩写得再好，没有断言守着也会烂掉。
##
## ## 另外：这里**不依赖模拟器**
##
## 而是直接往 session.events 里塞合成的挥动事件。规则是确定性的，就该用确定性的
## 输入去测 —— 靠随机模拟去猜绳子会倒向哪边，那不叫验证，那叫碰运气。

var _pass: int = 0
var _fail: int = 0

## 只统计**框架自己**的断言（玩法自带的那些不计入）。
##
## 为什么非得分家：下面那道哨兵必须对「删掉一个玩法」**无感** —— 那是合法操作，
## 不是静默失败。如果总数里混着玩法自带的断言，删掉玩法就会让总数掉下来，
## 哨兵就会冲着一个完全正常的框架喊「有组崩了」。
var _fw_pass: int = 0
var _fw_fail: int = 0

## 框架断言条数的下限。**加测试务必同步调大这个数。**
##
## 为什么需要它：GDScript 的运行时错误（比如调了不存在的函数）不会抛异常，
## 只会把当前函数当场中断 —— 那一组后面的 _ok 一条都不会执行。
## 于是「脚本崩了」看起来和「全部通过」一模一样：0 失败、退出码 0，
## 接上 CI 就是绿着的坏构建。有了这道闸，少一条就报 FAIL。
##
## 这不是重复计数，是**防静默**。见 memory：这类坑已经真实踩过一次。
##
## 另一个推论：**框架这几组的断言条数不能随「注册了几个玩法」变化**。
## 所以「每个玩法都怎样怎样」的检查一律汇总成一条（列表放在失败信息里），
## 而不是每发现一个玩法就 _ok 一次。删掉一个玩法时这个数字必须纹丝不动 ——
## 不然哨兵会冲着一个完全正常的框架喊「有组崩了」。
##
## 注意这个数是**哨兵自己那条之前**的条数（哨兵也算一条断言，但它没法数自己）。
##
## 第 3 版 UI 改版后：189 → **172**。减少了 17 条，全是**被设计推翻的老断言**，
## 不是「测试变松了」——逐条对账如下（改版时一定照着核一遍，别直接调数字）：
##   · 「在座玩家那块有标题」              删 —— 那块整个没了
##   · 「0 人时在座玩家明说没人连上」      删 —— 换成了「状态条右端说『等待手柄』」
##   · 「3 个人都画成了药丸」              删 —— 名字药丸换成席位圆点
##   · 「大厅屏上看得见谁在线（药丸）」    改 —— 判据换成数席位圆点
##   · 「0 人时大厅自己讲怎么连手机」      改 —— 换查「等待手柄」+「UDP」
##   · 「大厅主卡画出了标题」              改 —— 标题拆成两个 Label，判据跟着拆
## 新增（也计入）：
##   · 0 人时画出 8 个空席位
##   · 0 人时没有一个席位是坐满态
##   · 3 人时恰好 3 个席位坐满
##   · 房主恰好 1 个
##   · 3 人坐下后还剩 5 个空位
##   · 每张真磁贴配一个封面槽
##   · 0 人时报出 UDP 端口号
##
## **改动的净效果是 −17。** 下次再改 UI，先按上面这个格式列出「删了什么、加了什么」，
## 再加起来改这个数字 —— 直接填实测值等于把这个哨兵废掉。
##
## TUG-01（输入层「挥动 → 往上蹦」）后：171 → **172**。净 +1，只动了输入抽象层那一组：
##   · [3] 由「输入抽象层：挥动检测」改写成「输入抽象层：往上蹦检测」。
##     旧判据只看「有没有触发事件」（方向无关）；新判据钉住 5 件事：
##       - 空闲（带 ±0.15 噪声）→ jump 恒为 0
##       - 向上冲 → jump 抬升（> 0）
##       - **向下甩 → 不产生 jump**（「往上蹦」而非「挥动」的核心判据）
##       - 蹦一次就停 → 强度衰减回 0（= 拉不动）
##       - 同冲量下蹦得密 → 平均蹦劲明显更高（「越密拉力越大」）
##     → 4 条变 5 条，+1。
##   其余几组只是把 swing 改名成 jump、判据数字未变（见下），断言条数不动。
##   **净效果 +1。**
##
## TUG-02（对局屏重构：删左信息栏 + 顶部细横条 + 相机重取景）后：172 → **195**。
##   ⚠️ 这一轮先修了一个**静默 bug**：自检里读 `rec["strip"]` —— 那个键早在大厅玩家药丸
##     搬进状态条时就没了。它每跑必抛 `SCRIPT ERROR`、**静默吃掉 `_check_hud_contract`
##      后半段所有断言**（哨兵也没抓到，因为框架总数靠前面几组撑着仍 ≥172）。
##      改成按真实存在的键 `seats` 判之后，那些断言回来了 —— **这是总数 +23 的主因**，
##      不是「新增了很多断言」。
##   删（对局屏左栏的相关内容都不再上屏）：
##     · 「玩法屏左栏也有在座玩家」         删 —— 左栏整个没了
##     · 「对局主卡画出了玩法名」           删 —— 玩法名不再上屏
##     · 「分队玩法在药丸上标了队别」       删 —— 药丸（名单）不再上屏
##     · 「掉线槽位显式画成「槽位 N 空」」  改 —— 该句字原画在名单上，现改成**查模型**
##                                              （槽位数组不缩、被置空的格仍是 null）
##     · 「大厅的玩家药丸住在状态条右端」   改 —— 键 `strip`→`seats`（同时修上面那个 bug）
##   加（对局屏新结构）：
##     · 对局屏上不再有「在座玩家」名单
##     · 顶部横条画出了剩余时间
##     · 顶部横条画出了两队比分（两个数字各占一格、各上队色）
##     · 倒计时大数字上了屏
##     · 倒计时提示「往上蹦」
##     · 顶部横条只在对局屏出现（大厅屏上没有）
##   **净效果 +23（172 → 195）。** 这 23 里大部分是「修好静默 bug 后回来的旧断言」。
const EXPECTED_MIN := 195


func _ready() -> void:
	print("========== HomeGame 框架自检 ==========")

	# 框架自检的载体：一个**不放在玩法目录里**的假玩法。注册它只是为了「有个东西
	# 可以开局」，它跟着框架走 —— 把任何真玩法删掉都不影响它，也就不影响这几组测试。
	GameRegistry.register_for_test(FakeGame)
	print("[selfcheck] 注册表里的玩法：%s（其中 %s 是框架自带的测试载体）" % [
		str(GameRegistry.ids()), FakeGame.ID,
	])

	_check_registry_invariants()
	_check_flow_lifecycle()
	_check_input_layer_jump()
	_check_event_drain_semantics()
	_check_reward_gateway_contract()
	_check_reward_service()
	_check_reward_in_flow()
	_check_reward_without_gateway()
	_check_drop_player()
	_check_lobby()
	_check_player_names()
	await _check_hud_contract()
	_check_pluggable_no_game_refs()

	# 玩法自带的规则测试（扫玩法目录扫出来的，跟在上面的框架组后面）
	_run_game_selftests()

	# 放最后：任何一组中途崩掉都会让总数不达标，在这里兜住
	var fw_total := _fw_pass + _fw_fail
	_ok(fw_total >= EXPECTED_MIN,
		"框架断言总数 ≥ %d（现在 %d）—— 少了说明有组中途崩了" % [EXPECTED_MIN, fw_total])

	print("========== %d 通过 / %d 失败（框架 %d 项，玩法自带 %d 项）==========" % [
		_pass + 0, _fail,
		_fw_pass + _fw_fail,
		(_pass + _fail) - (_fw_pass + _fw_fail),
	])
	get_tree().quit(1 if _fail > 0 else 0)


# ------------------------------------------------------------------ 注册表

func _check_registry_invariants() -> void:
	print("\n[1] 注册表与新玩法契约")

	var scripts := GameRegistry.scripts()
	var cat := GameRegistry.catalog()

	# 注意：**不断言「至少有一个玩法」**。玩法是可插拔的，一个都没注册也是一种
	# 合法状态（大厅会说「还没有注册任何玩法」）。这里只查「注册表自己是不是自洽」。
	_ok(scripts.size() == cat.size(),
		"扫到的每个脚本都通过了玩法契约（场地、自带测试这些辅助脚本没被误认成玩法）：%d 个脚本 / %d 个玩法"
		% [scripts.size(), cat.size()])

	# 「每个玩法的 meta 合不合法」汇总成一条 —— 断言条数不能随玩法增减而变，
	# 否则「删掉一个玩法」会让总数变化，最后那道防静默的闸就失灵了。
	var bad: Array[String] = []
	for m in cat:
		var id := str(m["id"])
		var lo := int(m["min_players"])
		var hi := int(m["max_players"])
		if lo < 1 or lo > hi:
			bad.append("%s 人数区间不合法 (%d-%d)" % [id, lo, hi])
		# 架构硬上限是 8 —— 由颜色可辨识度决定。玩法声明的人数不能越过它。
		if hi > PlayerPalette.count():
			bad.append("%s 上限 %d 超过颜色表容量 %d" % [id, hi, PlayerPalette.count()])
		if str(m.get("name", "")) == "":
			bad.append("%s 没有中文名" % id)
		if str(m.get("desc", "")) == "":
			bad.append("%s 没有一句话说明" % id)
		if not (m.get("inputs", []) is Array) or (m["inputs"] as Array).is_empty():
			bad.append("%s 没声明输入类型" % id)
	_ok(bad.is_empty(), "每个玩法的 meta 都完整合法%s" % ("" if bad.is_empty() else " —— 但：%s" % str(bad)))

	# 扫目录扫出来的玩法必须都住在玩法目录里。
	# 框架自带的测试载体（register_for_test 挂进来的）不算 —— 它按设计就在 dev/ 下。
	var extra := GameRegistry.test_registered()
	var stray: Array[String] = []
	for s in scripts:
		if extra.has(s):
			continue
		if not s.resource_path.begins_with(GameRegistry.GAMES_DIR + "/"):
			stray.append(s.resource_path)
	_ok(stray.is_empty(), "扫到的玩法都住在玩法目录里%s" % ("" if stray.is_empty() else " —— 但：%s" % str(stray)))

	_ok(GameRegistry.ids().size() == cat.size(), "ids() 与 catalog() 条数一致")
	_ok(_ready_count_in(GameRegistry.evaluate(2)) == GameRegistry.available_for(2).size(),
		"available_for() 与 evaluate() 是同一个口径（两处问法打架会让大厅和开局条件不一致）")

	var missing: Array[String] = []
	for id in GameRegistry.ids():
		if GameRegistry.find(id) == null:
			missing.append(str(id))
	_ok(missing.is_empty(), "每个已注册的 id 都查得回自己的脚本%s" % ("" if missing.is_empty() else " —— 但：%s" % str(missing)))
	_ok(GameRegistry.find("no_such_game") == null, "查不到的 id 返回 null")
	_ok(GameRegistry.create("no_such_game") == null, "实例化不存在的玩法返回 null")

	# 顺序必须**定死**：菜单第 N 项、数字 1-9 直选、光标记忆全挂在顺序上，
	# 顺序随文件系统飘会让「按 2 进第二个玩法」这种操作失效。
	var orders: Array = []
	for m in cat:
		orders.append(int(m.get("order", 0)))
	var sorted_orders := orders.duplicate()
	sorted_orders.sort()
	_ok(str(orders) == str(sorted_orders), "玩法按 order 升序排（order 相同的才看 id 字母序）")


# ------------------------------------------------------------------ 流程状态机

func _check_flow_lifecycle() -> void:
	print("\n[2] 流程状态机：大厅 → 倒计时 → 对局中 → 结算 → 大厅")

	var flow := GameFlow.new()
	add_child(flow)
	flow.set_process(false)  # 手动喂 delta，避免和真实帧混在一起

	var s0 := _fake_session(11, "小明")
	var s1 := _fake_session(22, "小红")
	var incoming := [s0, s1]

	# 人数不够时应该开不了
	_ok(not flow.start_game(FakeGame.ID, [s0]), "1 人开不了这一局")
	_ok(flow.state == GameFlow.State.LOBBY, "拒绝后仍在大厅")

	_ok(flow.start_game(FakeGame.ID, incoming), "2 人成功开局")
	_ok(flow.state == GameFlow.State.COUNTDOWN, "进入倒计时")
	# 槽位是开局那一刻分配的 —— 网络层的 player_id 11/22 跟槽位 0/1 无关
	_ok(s0.slot == 0 and s1.slot == 1, "槽位 0/1 已分配（与 player_id 解耦）")
	_ok(flow.current_id == FakeGame.ID and flow.current != null, "current 指向本局的玩法实例")
	_ok(not flow.start_game(FakeGame.ID, incoming), "对局中不允许重复开局")

	_step(flow, GameFlow.COUNTDOWN_SEC + 0.5, 0.1)
	_ok(flow.state == GameFlow.State.PLAYING, "倒计时走完进入对局中")

	# 左队一直往上蹦（打满连续强度），直到分出胜负
	var guard := 0
	while flow.state == GameFlow.State.PLAYING and guard < 2000:
		s0.filter.jump = 1.0
		s1.filter.jump = 0.0
		flow._process(0.05)
		guard += 1

	_ok(flow.state == GameFlow.State.RESULT, "分出胜负后进入结算")
	_ok(int(flow.last_result.get("winner_team", -1)) == 0, "结算数据里左队获胜")
	_ok(int(flow.last_result.get("winner_slots", [-1])[0]) == 0, "结算带回了获胜槽位")

	_step(flow, GameFlow.RESULT_SEC + 1.0, 0.1)
	_ok(flow.state == GameFlow.State.LOBBY, "结算展示完自动回大厅")
	_ok(flow.current == null, "回大厅后玩法实例已清理")

	# 再来一局，验证可重入
	_ok(flow.start_game(FakeGame.ID, incoming), "回大厅后能再开一局")
	_ok(flow.state == GameFlow.State.COUNTDOWN, "新一局从倒计时开始")
	flow.abort()
	_ok(flow.state == GameFlow.State.LOBBY, "abort() 能硬回大厅")

	remove_child(flow)
	flow.free()


# ------------------------------------------------------------------ 输入抽象层

## 输入抽象层：只认「往上蹦」，并产出一个**连续强度** `jump`（不是一次性事件）。
##
## 这里测的是新行为的核心：**方向性**（向下甩不算）+ **连续性**（越密越强）。
## 这两条都是「挥动 → 往上蹦」这次改动的实质，光测「有事件产生」是测不到的。
func _check_input_layer_jump() -> void:
	print("\n[3] 输入抽象层：往上蹦检测")

	# ① 静止（带 ±0.15 噪声）不该攒出蹦劲
	var f := MotionFilter.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ms := 0
	for i in 180:
		var a := Vector3(0.0, 9.81, 0.0) + Vector3(
			rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15)
		)
		f.feed(Vector3.ZERO, a, ms)
		ms += 16
	_ok(is_zero_approx(f.jump), "静止 3 秒、带 ±0.15 噪声 → jump 一直是 0")

	# ② 向上冲 → 蹦劲抬升
	var up := MotionFilter.new()
	up.feed(Vector3.ZERO, Vector3(0.0, 9.81 + 26.0, 0.0), 0)
	_ok(up.jump > 0.0, "向上冲一下 → jump 抬升到 %.2f（> 0）" % up.jump)

	# ③ **向下冲不产生蹦劲** —— 这是「往上蹦」而不是「挥动」的核心判据
	var down := MotionFilter.new()
	down.feed(Vector3.ZERO, Vector3(0.0, 9.81 - 26.0, 0.0), 0)
	_ok(is_zero_approx(down.jump), "向下甩不产生 jump（只认向上，jump=%.3f）" % down.jump)

	# ④ 蹦一次就停 → 强度衰减回 0（= 拉不动）
	var one := MotionFilter.new()
	one.feed(Vector3.ZERO, Vector3(0.0, 9.81 + 26.0, 0.0), 0)
	var peak := one.jump
	var t := 0
	for i in 150:  # 2.5 秒
		t += 16
		one.feed(Vector3.ZERO, Vector3(0.0, 9.81, 0.0), t)
	_ok(peak > 0.0 and is_zero_approx(one.jump),
		"蹦一次就停 → 强度衰减回 0（峰值 %.2f，2.5 秒后 %.3f）" % [peak, one.jump])

	# ⑤ 同样的冲量，蹦得密 → 平均蹦劲明显更高（「越密拉力越大」的直接验证）
	var dense := _avg_jump(0.4, 8.0)
	var sparse := _avg_jump(1.6, 8.0)
	_ok(dense > sparse + 0.15, "蹦得密平均蹦劲明显更高（密 %.2f vs 疏 %.2f）" % [dense, sparse])


func _check_event_drain_semantics() -> void:
	print("\n[4] 事件队列：取走即清空（帧率高于发包率时的正确性）")

	var s := PlayerSession.new()
	s.push_event({"type": "jump", "power": 1.0})

	var first := s.drain_events()
	var second := s.drain_events()
	_ok(first.size() == 1, "第一次取走拿到 1 个事件")
	_ok(second.is_empty(), "紧接着再取是空的（不会被重复消费）")

	# 端到端：同一次「往上蹦」，连 tick 两次也只能算一次蹦
	var game := _new_game(2)
	game.sessions[0].push_event(_jump())
	game.tick(1.0 / 60.0)
	game.tick(1.0 / 60.0)
	_ok(int(game.result()["jumps"][0]) == 1, "同一次蹦连 tick 两次只算 1 次")

	# 队列不会无限堆积
	var s2 := PlayerSession.new()
	for i in 50:
		s2.push_event(_jump())
	_ok(s2.events.size() <= PlayerSession.MAX_PENDING_EVENTS,
		"没人消费时队列封顶在 %d" % PlayerSession.MAX_PENDING_EVENTS)

	# 开局清空：大厅里攒的事件不该在开局瞬间炸出来
	var game2 := FakeGame.new()
	game2.sessions = _sessions(2)
	game2.sessions[0].push_event(_jump())
	game2.sessions[1].push_event(_jump())
	game2.setup()
	game2.tick(1.0 / 60.0)
	_ok(int(game2.result()["jumps"][0]) == 0, "开局时队列已清空，不会瞬间多出几次蹦")

	game.free()
	game2.free()


## 复刻模拟器的蹦跳波形，返回一段时间内的**平均蹦劲**（0..1）。
##
## 冲量固定（每次都往上冲同样一下），只改「多久蹦一次」—— 返回的平均值越高，
## 就说明「蹦得越密，长期挂着的力量越大」。这是「往上蹦要连续、越密拉力越大」
## 这条设计在**输入层**的直接验证：密 vs 疏两次调用一比即可。
func _avg_jump(period: float, seconds: float) -> float:
	var f := MotionFilter.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var t := 0.0
	var jump_t := 999.0
	var next_jump: float = period
	var total := 0.0
	var samples := 0
	var ms := 0
	while t < seconds:
		var dt := 1.0 / 60.0
		if t >= next_jump:
			jump_t = 0.0
			next_jump = t + period
		jump_t += dt

		var accel := Vector3(sin(t * 1.7) * 3.2, 9.81, cos(t * 0.9) * 2.1)
		if jump_t < 1.0:
			accel.y += 26.0 * exp(-jump_t * 6.0)
		accel += Vector3(
			rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15)
		)
		f.feed(Vector3(0.0, 0.0, cos(t * 1.7) * 0.9), accel, ms)
		# 跳过开头 1 秒预热（EMA 还没稳），之后再统计
		if t >= 1.0:
			total += f.jump
			samples += 1
		t += dt
		ms += 16
	return total / maxf(float(samples), 1.0)


# ------------------------------------------------------------------ 奖励接口（道具 / 复活）

## 网关契约：发给答题程序的 JSON 字段，以及「不认识的网关不许静默失败」
func _check_reward_gateway_contract() -> void:
	print("\n[5] 奖励网关契约")

	var mock := MockRewardGateway.new()
	_ok(not mock.describe().is_empty(), "mock 网关有说明文字：%s" % mock.describe())
	mock.free()

	# HTTP 网关发给答题程序的 JSON —— 这是你的程序要照着实现的契约，字段少了就断言失败
	var http := HttpRewardGateway.new()
	var payload := http.build_payload(7, {
		"kind": "revive", "slot": 1, "item_id": "", "reason": "压线了",
		"player": "小红", "players": ["小明", "小红"], "game": FakeGame.ID, "game_name": FakeGame.NAME,
	})
	for key in ["request_id", "kind", "item_id", "slot", "player", "players", "game", "game_name", "reason"]:
		_ok(payload.has(key), "payload 含字段 %s" % key)
	_ok(int(payload["request_id"]) == 7, "request_id 原样带上")
	_ok(payload["players"] is Array and (payload["players"] as Array).size() == 2, "带上本局全部玩家")
	_ok(JSON.stringify(payload).length() > 0, "payload 能序列化成 JSON")
	print("      给答题程序的请求体长这样：\n      %s" % JSON.stringify(payload))
	http.free()


## 奖励服务：同步回答、异步回答、超时兜底
func _check_reward_service() -> void:
	print("\n[6] 奖励服务：转发 + 超时兜底")

	# A. 网关延迟为 0 → 同步回答
	var a := _new_reward_stack("grant", 0.0, 5.0)
	var got_a := []
	a["svc"].resolved.connect(func(id, req, granted, _d): got_a.append(granted))
	a["svc"].request({"kind": "revive"})
	_ok(got_a.size() == 1 and got_a[0] == true, "同步网关：request() 返回时答案已经到手")
	_ok(not a["svc"].is_busy(), "同步回答后服务已空闲")
	_free_stack(a)

	# B. 网关延迟 2 秒 → 先 busy，推进 mock 的计时器后才出结果
	var b := _new_reward_stack("grant", 2.0, 5.0)
	var got_b := []
	b["svc"].resolved.connect(func(id, req, granted, _d): got_b.append(granted))
	b["svc"].request({"kind": "item"})
	_ok(b["svc"].is_busy(), "异步网关：刚发请求时处于忙碌")
	b["gw"]._process(1.0)
	b["svc"]._process(1.0)
	_ok(got_b.is_empty(), "还没到点，没有结果")
	b["gw"]._process(1.5)
	_ok(got_b.size() == 1 and got_b[0] == true, "到点后拿到结果")
	_free_stack(b)

	# C. 网关永远不回答 → 超时按「拿不到」处理，不能卡死对局
	var c := _new_reward_stack("timeout", 0.0, 3.0)
	var got_c := []
	c["svc"].resolved.connect(func(id, req, granted, data): got_c.append([granted, str(data.get("reason", ""))]))
	c["svc"].request({"kind": "revive"})
	c["svc"]._process(1.0)
	_ok(got_c.is_empty(), "超时前不判负")
	c["svc"]._process(2.5)
	_ok(got_c.size() == 1 and got_c[0][0] == false, "超时后按「拿不到」处理")
	_ok(str(got_c[0][1]) == "timeout", "结果里带上了超时原因")
	_ok(not c["svc"].is_busy(), "超时后服务不再忙碌")
	_free_stack(c)

	# D. 没配网关 → request() 返回 0，不崩
	var svc := RewardService.new()
	_ok(svc.request({"kind": "revive"}) == 0, "没配网关时请求返回 0 而不是崩掉")
	_ok(not svc.is_busy(), "没配网关时也不会挂起")
	svc.free()


## 完整链路：对局中 → 等奖励 → 对局中（复活成功）/ 结算（复活失败）
func _check_reward_in_flow() -> void:
	print("\n[7] 流程状态机接奖励：对局中 → 等奖励 → 对局中 / 结算")

	for policy: String in ["grant", "deny"]:
		var stack := _new_reward_stack(policy, 0.0, 5.0)
		var flow: GameFlow = stack["flow"]
		flow.set_reward_service(stack["svc"])

		var s0 := _fake_session(11, "小明")
		var s1 := _fake_session(22, "小红")

		# 复活成功的证据必须在**那一刻**抓，不能等循环自然退出 ——
		# mock 网关同步回答，同一帧内就走完 REWARD → PLAYING，而复活后比赛继续，
		# 循环要到第二次压线（额度已尽）才退出，那时 state 早已是 RESULT。
		#
		# 注意：GDScript 的 lambda 捕获按值，给捕获的**变量重新赋值**外面看不到；
		# 所以可变状态一律塞进 Dictionary，靠「同一个对象」改内部字段。
		var log := {"states": [], "settled": "", "hops": [], "after": {}}
		flow.reward_settled.connect(func(req: Dictionary, granted: bool, _data: Dictionary):
			log["settled"] = "%s/%s" % [
				str(req.get("kind", "")), "到手" if granted else "没拿到",
			]
			# reward_settled 必须在 apply_reward **之后**发。这里当场记下玩法的状态：
			# 顺序要是被改回「先通知后生效」，下面两条断言立刻会红。
			var t: FakeGame = flow.current
			var snaps: Dictionary = log["after"]
			snaps[str(req.get("kind", ""))] = {
				"rope": t.rope, "over": t.is_over(), "granted": granted,
			})
		flow.state_changed.connect(func(from: int, to: int):
			var st: Array = log["states"]
			st.append(to)
			if from == GameFlow.State.REWARD and to == GameFlow.State.PLAYING:
				var t: FakeGame = flow.current
				var hs: Array = log["hops"]
				hs.append({
					"kind": str(log["settled"]),
					"rope": t.rope,
					"over": t.is_over(),
					"revive_left": t.revive_left_count(),
				}))

		_ok(flow.start_game(FakeGame.ID, [s0, s1]), "[%s] 开局成功" % policy)
		_step(flow, GameFlow.COUNTDOWN_SEC + 0.5, 0.1)
		_ok(flow.state == GameFlow.State.PLAYING, "[%s] 进入对局中" % policy)

		# 左队一路猛拉，直到比赛自然收场（压线 → 问奖励 → 救回 / 判负）
		var guard := 0
		while flow.state == GameFlow.State.PLAYING and guard < 4000:
			s0.filter.jump = 1.0
			s1.filter.jump = 0.0
			flow._process(0.05)
			guard += 1
		if flow.state == GameFlow.State.PLAYING:
			flow._process(0.05)

		var states: Array = log["states"]
		var hops: Array = log["hops"]
		_ok(GameFlow.State.REWARD in states, "[%s] 中间经过了「等奖励」状态" % policy)

		var revive_hop: Dictionary = {}
		for h: Dictionary in hops:
			if str(h["kind"]).begins_with("revive/"):
				revive_hop = h

		var game := flow.current as FakeGame
		var after: Dictionary = log["after"]
		var revive_after: Dictionary = after.get("revive", {})
		_ok(not revive_after.is_empty(), "[%s] 收到了 reward_settled" % policy)
		if policy == "grant":
			_ok(not revive_hop.is_empty(), "[grant] 复活成功 → 回到了对局中")
			_ok(not bool(revive_hop.get("over", true)), "[grant] 救回来那一刻比赛还没结束")
			_ok(absf(float(revive_hop.get("rope", 99.0))) < 0.0001,
				"[grant] 绳子已拉回中线（%+.2f）" % float(revive_hop.get("rope", 99.0)))
			_ok(int(revive_hop.get("revive_left", -1)) == 0, "[grant] 复活额度已用掉")
			_ok(flow.state == GameFlow.State.RESULT, "[grant] 最终还是打到了结算")
			_ok(int(flow.last_result.get("revives_used", 0)) == 1, "[grant] 结算记录了复活消耗")
			# 通知时机：reward_settled 到手时，绳子**已经**被拉回中线了
			_ok(absf(float(revive_after.get("rope", 99.0))) < 0.0001,
				"[grant] 通知来时绳子已归零（%+.2f）" % float(revive_after.get("rope", 99.0)))
		else:
			_ok(hops.is_empty(), "[deny] 复活失败不会回到对局中")
			_ok(game.is_over(), "[deny] 复活失败 → 直接判负")
			_ok(flow.state == GameFlow.State.RESULT, "[deny] 状态进入结算")
			_ok(int(flow.last_result.get("winner_team", -1)) == 0, "[deny] 压线那一队获胜")
			# 通知时机：判负是 apply_reward 里发生的，通知来时必须已经是「已结束」
			_ok(bool(revive_after.get("over", false)), "[deny] 通知来时判负已生效")

		remove_child(flow)
		flow.free()
		_free_stack(stack, false)


## 没配网关时，玩法要奖励也不能把对局卡死
func _check_reward_without_gateway() -> void:
	print("\n[8] 没配奖励网关时不卡死")

	var flow := GameFlow.new()
	add_child(flow)
	flow.set_process(false)
	var s0 := _fake_session(11, "小明")
	var s1 := _fake_session(22, "小红")
	flow.start_game(FakeGame.ID, [s0, s1])
	_step(flow, GameFlow.COUNTDOWN_SEC + 0.5, 0.1)

	var guard := 0
	while flow.state == GameFlow.State.PLAYING and guard < 4000:
		s0.filter.jump = 1.0
		s1.filter.jump = 0.0
		flow._process(0.05)
		guard += 1
	_ok(flow.state != GameFlow.State.REWARD, "没有网关时不会停在等奖励状态")
	_ok(flow.state == GameFlow.State.RESULT, "没有网关时按「拿不到」直接走到结算")

	remove_child(flow)
	flow.free()


## 掉线与空槽位。
## 判「人还够不够」必须问玩法的 accepts_count()，不能只看 min_players()：
## 一个 2–4 人的玩法可能额外要求能均分两队 —— 4 人局掉 1 个剩 3 人，人数还在区间里，
## 2v2 却变成了 1v2，只能中止。这就是框架不许自己猜规则的原因。
func _check_drop_player() -> void:
	print("\n[9] 掉线处理与空槽位")

	# 4 人局掉 1 人 → 中止（以前只看 min_players，会继续打 1v2）
	var flow := GameFlow.new()
	add_child(flow)
	flow.set_process(false)
	var four := _sessions(4)
	_ok(flow.start_game(FakeGame.ID, four), "4 人局开局成功")
	_step(flow, GameFlow.COUNTDOWN_SEC + 0.5, 0.1)
	_ok(flow.state == GameFlow.State.PLAYING, "进入对局中")
	flow.drop_player(four[1].player_id)
	_ok(flow.state == GameFlow.State.LOBBY, "掉 1 人后中止（剩 3 人无法均分两队）")
	_ok(flow.current == null, "中止后玩法已清理")

	# 2 人局掉 1 人 → 也中止（剩 1 人连局都开不了）
	var flow2 := GameFlow.new()
	add_child(flow2)
	flow2.set_process(false)
	var two := _sessions(2)
	flow2.start_game(FakeGame.ID, two)
	_step(flow2, GameFlow.COUNTDOWN_SEC + 0.5, 0.1)
	flow2.drop_player(two[0].player_id)
	_ok(flow2.state == GameFlow.State.LOBBY, "2 人局掉 1 人也中止")

	# 槽位「置空不删除」：玩法层必须能容忍中间空出来的槽位。
	# 抽掉中间一个会让后面所有人的槽位号前移 —— 颜色和身份就全乱了，所以宁可留空。
	var game := FakeGame.new()
	var mixed := _sessions(4)
	mixed[1] = null
	game.sessions = mixed
	game.setup()
	_ok(game.team_slots(0).size() == 2 and game.team_slots(1).size() == 2,
		"槽位编号不变（左 0/2、右 1/3）")
	_ok(game.first_slot_of_team(1) == 3, "队里第一个「在场」的槽位跳过空位（右队 → 3）")
	_drive(game, [0, 2], 3.0)
	_ok(not game.is_over(), "空槽位下推进 3 秒不炸（左队 2 打 1）")
	_ok(game.status_text().length() > 0, "空槽位下 status_text 正常")
	game.free()

	remove_child(flow)
	flow.free()
	remove_child(flow2)
	flow2.free()


## 大厅：当前人数能开哪些玩法、开不了是为什么、光标怎么走。
## 「为什么开不了」由玩法自己回答（MiniGame.why_not）——
## 框架猜不到「某玩法要均分两队」这种规则，猜出来的提示只会含糊。
##
## 这里所有跟「有几个能开」有关的断言都**相对注册表**来写，不写死数字 ——
## 玩法是可插拔的，写死就等着删玩法那天打脸。
func _check_lobby() -> void:
	print("\n[10] 大厅：能开哪些玩法 + 说清原因")

	var lobby := Lobby.new()

	lobby.refresh(2)
	_ok(not lobby.is_empty(), "大厅列出了玩法")
	# 框架自带的假玩法 order = -100，永远排在最前 —— 这条不随真玩法增减而变
	_ok(lobby.selected_id() == FakeGame.ID, "2 人时光标落在第一个玩法上")
	_ok(bool(lobby.selected_entry().get("ready", false)), "2 人时第一个玩法可以开")
	_ok(lobby.ready_count() == GameRegistry.available_for(2).size(),
		"2 人能开的个数与注册表一致（%d 个）" % lobby.ready_count())

	# 「开不了」的说明：有开不了的就必须有、一个都没有时必须是空的
	# （有个把能玩的混进提示里，这行字就没意义了）
	for n in [1, 2, 3, 4, 5]:
		lobby.refresh(n)
		var blocked := lobby.entries.size() - lobby.ready_count()
		_ok(lobby.blocked_hint().is_empty() == (blocked == 0),
			"%d 人：能开 %d 个 / 开不了 %d 个 → 提示%s" % [
				n, lobby.ready_count(), blocked, "为空" if blocked == 0 else "非空",
			])

	# 「为什么开不了」的两种说法（人数不够 / 人太多）由 MiniGame.why_not 给
	lobby.refresh(1)
	var why1 := str(lobby.selected_entry().get("reason", ""))
	_ok(why1.findn("还差") >= 0, "1 人的原因说「还差人」：%s" % why1)

	lobby.refresh(5)
	var why5 := str(lobby.selected_entry().get("reason", ""))
	_ok(why5.findn("最多") >= 0, "5 人的原因说「人太多」：%s" % why5)

	# 光标在人数变化后要停住：有人进出就会重建列表，不能每次都被扔回第一个
	lobby.refresh(2)
	lobby.move_grid(1, 0, UiKit.LOBBY_COLUMNS)
	lobby.move_grid(-1, 0, UiKit.LOBBY_COLUMNS)
	_ok(lobby.selected_id() == FakeGame.ID, "左右走一格再走回来，光标回到原处")
	lobby.refresh(4)
	_ok(lobby.selected_id() == FakeGame.ID, "人数变化后光标仍停在同一个玩法上")

	# ---- 网格导航（← → ↑ ↓）。用一组**人造条目**铺出网格：
	# 真玩法只有一两个，验不出「行尾不满」「跨行循环」这些边界。
	# 这里只关心光标怎么跳，条目内容无所谓。
	lobby.entries = _probe_entries(5)
	lobby.selected = 0
	lobby.move_grid(1, 0, 3)
	_ok(lobby.selected == 1, "3 列 5 项：按右 → 第 1 格")
	lobby.selected = 2
	lobby.move_grid(1, 0, 3)
	_ok(lobby.selected == 0, "行尾再按右 → 回本行第一个（**不跨行**，否则焦点会跳行）")
	lobby.selected = 0
	lobby.move_grid(0, 1, 3)
	_ok(lobby.selected == 3, "按下 → 下一行的同一列")
	lobby.selected = 3
	lobby.move_grid(0, 1, 3)
	_ok(lobby.selected == 0, "最后一行再按下 → 跨行循环回第一行")
	lobby.selected = 1
	lobby.move_grid(0, 1, 3)
	_ok(lobby.selected == 4, "下到不满的那一行 → 落到该行最后一格（不落到空处）")
	lobby.selected = 4
	lobby.move_grid(1, 0, 3)
	_ok(lobby.selected == 3, "不满的那一行只有 2 格：按右 → 在本行内循环")
	lobby.move_grid(0, 0, 3)
	_ok(lobby.selected == 3, "dx=dy=0 时不动（空按不能把光标弄丢）")

	# 按 id 定位光标（自动开局、将来的「再来一局」都要用）
	lobby.entries = GameRegistry.evaluate(2)
	lobby.refresh(2)
	_ok(lobby.select_id(FakeGame.ID), "按 id 能把光标挪过去")
	_ok(lobby.index_of(FakeGame.ID) == 0, "第一个玩法的下标是 0")
	_ok(lobby.index_of("no_such_game") < 0, "没注册的玩法下标是 -1")
	_ok(not lobby.select_id("no_such_game"), "按 id 找不到就返回否")
	_ok(lobby.selected_id() == FakeGame.ID, "找不到时光标不乱跑")

	# 注册表两种问法必须一致，否则大厅和实际开局条件会打架
	for n in [1, 2, 3, 4, 5, 8]:
		_ok(GameRegistry.available_for(n).size() == _ready_count_in(GameRegistry.evaluate(n)),
			"%d 人时 available_for 与 evaluate 一致" % n)


## 造一组**人造**大厅条目，只为了让网格导航有足够多的格子可跳。
## 字段形状照抄 `GameRegistry.evaluate()`（磁贴会读 name / min_players / max_players / ready）。
## 造几份人造条目给布局用。`id` 默认取**真实注册过的**玩法（本组用 `fake`）——
## 给不存在的 id 会让磁贴里的 `GameRegistry.create()` 报 ERROR，把自检输出搅浑。
func _probe_entries(n: int, id: String = "fake") -> Array:
	var out: Array = []
	for i in n:
		out.append({
			"id": id,
			"name": "探测 %d" % i,
			"desc": "",
			"min_players": 1,
			"max_players": 8,
			"players": 1,
			"ready": true,
			"reason": "",
		})
	return out


## 默认名字池：不报名时分配一个，报了就用自己的。
## 「默认分配一个 + 能自己改」这句产品话，在这里落成可断言的行为。
func _check_player_names() -> void:
	print("\n[11] 默认名字池（不报名时分配，报了就用自己的）")

	_ok(PlayerNames.size() >= 8, "名字池够架构上限 8 人用（现在 %d 个）" % PlayerNames.size())

	# 名字要放得进 HUD 一行、彼此不重复 —— 重名了就只剩颜色和槽位号能认人
	var longest := 0
	var seen := {}
	var dup := ""
	for nm in PlayerNames.POOL:
		var s := str(nm)
		longest = maxi(longest, s.length())
		if seen.has(s):
			dup = s
		seen[s] = true
	_ok(dup.is_empty(), "池子里没有重名" if dup.is_empty() else "池子里有重名：「%s」" % dup)
	_ok(longest <= 4, "最长的名字 %d 字，HUD 一行放得下" % longest)
	_ok(not PlayerNames.is_default("小明"), "玩家自己起的名字不会被当成系统分配的")
	_ok(PlayerNames.is_default(PlayerNames.at(0)), "池子里的名字认得出是系统分配的")

	# at()：任何整数序号都得拿到名字，越界和负数都不许炸
	_ok(PlayerNames.at(0) == str(PlayerNames.POOL[0]), "第 0 个是「%s」" % PlayerNames.at(0))
	_ok(PlayerNames.at(PlayerNames.size() - 1) == str(PlayerNames.POOL[-1]),
		"最后一个是「%s」" % PlayerNames.at(PlayerNames.size() - 1))
	_ok(PlayerNames.at(PlayerNames.size()) == PlayerNames.at(0), "刚超出一个就绕回开头")
	_ok(PlayerNames.at(-1) == PlayerNames.at(PlayerNames.size() - 1), "负数序号绕到末尾，不越界")
	_ok(PlayerNames.at(9999) == PlayerNames.at(9999 % PlayerNames.size()), "大序号按取模绕回")
	_ok(not PlayerNames.at(9999).is_empty(), "离谱的序号也返回得出名字")

	# pick()：分配时避开已经被占的名字
	_ok(PlayerNames.pick([]) == PlayerNames.at(0), "没人占时给第一个")
	_ok(PlayerNames.pick([PlayerNames.at(0)]) == PlayerNames.at(1), "第一个被占了就给第二个")
	_ok(PlayerNames.pick([" %s " % PlayerNames.at(0)]) == PlayerNames.at(1),
		"已占名字两侧带空格也算占用")
	_ok(PlayerNames.pick(["小明", "小红"]) == PlayerNames.at(0), "玩家自己起的名字不占池子里的位")

	# 池子占满：宁可重名，也不要「玩家 7」这种没人认得出的名字
	var all_taken: Array = []
	for i in PlayerNames.size():
		all_taken.append(PlayerNames.at(i))
	var overflow := PlayerNames.pick(all_taken)
	_ok(not overflow.is_empty(), "池子占满也返回得出名字")
	_ok(PlayerNames.is_default(overflow), "池子占满时重用一个默认名，而不是「玩家 N」")
	_ok(PlayerNames.pick(["孙悟空", "猪八戒"]) in PlayerNames.POOL, "分配出来的名字一定出自池子")

	# 接上服务端那条路：不能把别人已经拿到的名字再发一遍
	var srv := UdpServer.new()
	var first := PlayerSession.new()
	first.player_id = 1
	first.player_name = PlayerNames.at(0)
	srv.sessions[1] = first
	_ok(srv._default_name_for(2) != first.player_name, "新来的拿不到 1 号已经占住的名字")
	_ok(srv._default_name_for(2) == PlayerNames.at(1), "新来的拿到下一个没被占的名字")
	_ok(srv._default_name_for(1) == first.player_name,
		"1 号重发一次空名 HELLO 不会把自己改名（改名得是幂等的）")

	# 「也可以自己改」：重发一次**带名字**的 HELLO 就把默认名换掉 ——
	# 手机端「改名字」就靠这一条，不用为它加新报文。
	srv._handle_hello(NetProtocol.encode_hello(1, "齐天大圣"), 1, "127.0.0.1", 1234)
	_ok(first.player_name == "齐天大圣", "重发 HELLO 就换成自己起的名字（现在「%s」）" % first.player_name)
	_ok(srv.sessions.size() == 1, "改名不会在名单里多出一个人")
	_ok(not PlayerNames.is_default(first.player_name), "自己起的名字不会被当成默认名")
	srv.free()


## 大屏 HUD 的契约：**喂一组假数据，断言真的画出了该有的字**。
##
## 为什么非要有这么一组：视图层的错**全是静默的**。
##   · 指纹撞车（空指纹 vs 初值 ""）→ 那一次该画的内容被当成「没变」跳过，画面上就是空的；
##   · `String(颜色)` 这种伪构造器 → 运行时错误只中断当前函数、不抛异常、不冒泡，
##     于是「在座玩家」整块被吃掉，而日志里只有一行 SCRIPT ERROR（很容易被 grep 漏掉）。
## 这两种都真实发生过，而且**只看单元测试是看不出来的** —— 它们只在「画」这一步暴露。
## 所以这里不看内部变量，只扫节点树里真实的文字。
func _check_hud_contract() -> void:
	# 协程：里面有 `await get_tree().process_frame`（布局问题不看真实尺寸就只能猜）
	# 调用点写 `await`，见 `_ready`。
	print("\n[12] 大屏 HUD 契约（喂假数据看真画出了什么）")

	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	hud.setup()

	# ---- 0 人在线：主卡要有菜单，席位圆点要全部空着
	hud.update_view(_hud_model(0, GameFlow.State.LOBBY))
	# 标题「玩什么？」第 3 版**拆成两个 Label**了：「玩什么」用墨色、「？」用番茄红
	# （设计稿 `.hero h1 em`）。所以判据要**分开查**，合起来查是查不到的。
	_ok(_has_text(hud, "玩什么") and _has_text(hud, "？"), "大厅主卡画出了标题（「？」单独着色）")
	_ok(_has_text(hud, FakeGame.NAME), "大厅主卡画出了注册的玩法")
	_ok(_has_text(hud, "在线"), "状态条画出了「在线」标签")
	_ok(not _has_text(hud, "孙悟空"), "0 人时不该凭空冒出名字")

	# 0 人时**席位圆点必须全部是空的**（8 个空位就是「还没人来」的表达方式）。
	#
	# 数的是**大厅那份**状态条。历史上 HUD 里状态条有两份实例（大厅、对局左栏各一份），
	# 要筛才不数到双份；TUG-02 删掉对局屏左栏后只剩大厅这一份（`lobby_only` 参数保留兼容）。
	# `_hud_model` 喂的是 LOBBY 状态，所以按可见性筛一定只数到大厅那份。
	var empty_seats := _count_seat_dots(hud, true)
	_ok(empty_seats == 8,
		"0 人时大厅状态条上仍画出 %d 个席位圆点 —— 「还剩几个位置」正是靠空格子说出来的"
			% empty_seats)
	_ok(_count_joined_seats(hud, true) == 0,
		"0 人时一个席位都不该是坐满态（现在 %d 个）" % _count_joined_seats(hud, true))

	# ---- 3 人在线
	hud.update_view(_hud_model(3, GameFlow.State.LOBBY))
	# 「谁在线」是大厅必须回答的两件事之一。第 3 版的判据是**席位圆点的状态**：
	# 3 个人坐进前 3 个位子（第 1 个是房主=红，第 2、3 个=青），后面几个仍是空位。
	# 这条必须在**刚喂过 3 个人**之后断 —— 喂 0 人时所有圆点都是空的，在那儿数只能数到 0。
	var joined := _count_joined_seats(hud, true)
	_ok(joined == 3,
		"大厅屏上看得见谁在线（状态条上 %d / %d 个席位坐满了）—— 「谁在线」是大厅必须回答的两件事之一"
			% [joined, _count_seat_dots(hud, true)])
	# 房主必须**恰好一个** —— 设计稿用番茄红单独标出房主，
	# 多标一个就是「两个房主」，少标一个就是「看不出谁是」。
	var lobby_hosts := _count_seat_hosts(hud, true)
	_ok(lobby_hosts == 1,
		"房主恰好标出 1 个（现在 %d 个）—— 红点标的是「这台机器的主人」" % lobby_hosts)
	_ok(empty_seats - joined == 5,
		"3 个人坐下后还剩 %d 个空位 —— 「还差几个人」由空格子直接数出来"
			% (empty_seats - joined))

	# ---- 同一份数据连喂两次：指纹要挡住重建（否则每帧造一堆节点）
	var before := _texts(hud).size()
	hud.update_view(_hud_model(3, GameFlow.State.LOBBY))
	_ok(_texts(hud).size() == before, "内容没变时不重建节点（节点数不变）")

	# ---- 大厅和玩法是**两屏**，同一时刻只显示一屏
	#
	# 这是「大厅里不该看见游戏场地」在 UI 层的对应断言。判据只能用 `_has_visible_text`：
	# `_has_text` 连藏起来的子树也扫，两屏都建了节点的前提下它永远为真，什么也证明不了。
	hud.update_view(_hud_model(0, GameFlow.State.LOBBY))
	_ok(hud._lobby_root.visible and not hud._play_root.visible,
		"大厅状态：显示大厅屏、藏起玩法屏")
	# 「玩什么」和「？」现在分属两个 Label（设计稿要单独给问号上红），
	# 所以这条查「玩什么」就够 —— 副标题才是「这是一屏玩法清单」的证据。
	_ok(_has_visible_text(hud, "玩什么") and _has_visible_text(hud, "选一个玩法，人齐就能开局"),
		"大厅屏上看得见玩法清单")
	_ok(not _has_visible_text(hud, "《%s》" % FakeGame.NAME), "大厅屏上不该出现对局信息（两屏没混在一起）")
	_ok(not _has_visible_text(hud, "拿稳手机"), "大厅屏上不该有倒计时那种舞台浮层")
	# 「怎么连手机」第 3 版挪到了**状态条右端**（`UDP 8910 · 等待手柄`）——
	# 原来那句「手机连到同一个 Wi-Fi，打开手柄 App」是一整行文字药丸，
	# 现在用一个**呼吸绿点的熄灭状态** + 端口号表达「还没人接上来，端口已经开着」。
	# 判据跟着改成查这句话，而不是查已经删掉的长提示。
	_ok(_has_visible_text(hud, "等待手柄"),
		"0 人时状态条右端明说「等待手柄」（端口开着、没人连上）")
	_ok(_has_visible_text(hud, "UDP"), "0 人时也报出监听的端口号（真机排查第一眼要看它）")

	# ---- 大厅自己的底：HUD 是透明的一层，底下就是 3D 世界。
	# 对局屏要的正是让场地透出来；但大厅里没有场地，不铺底就直接透出 3D 世界的清屏色。
	_ok(hud._lobby_backdrop.visible, "大厅状态：铺上了大厅自己的底色")
	hud.update_view(_hud_model(2, GameFlow.State.PLAYING, _mini_flow(2)))
	_ok(not hud._lobby_backdrop.visible, "对局状态：底色收掉了（不铺底才看得见场地）")

	# ---- 玩法磁贴网格 + **封面画确实交给了玩法自己画**
	#
	# 这条是「框架只给画板、画面归玩法」在 UI 层的证据。
	# 光断言「磁贴里有个框」是没用的 —— 那是框架自己也能摆出来的东西，
	# 证明不了「框架真的把画板递到了玩法手里」。所以看玩法那边的计数。
	var covers_before := FakeGame.cover_builds
	var lm := _hud_model(0, GameFlow.State.LOBBY)
	var entry_n: int = (lm["lobby"] as Lobby).entries.size()
	hud._lobby_sig = hud.NEVER_SIG      # 强制重画（指纹没变的话这一步会被跳过）
	hud.update_view(lm)
	# 张数按**注册表里实际有几个玩法**算，不写死数字：写死了，以后多加一个玩法
	# 这条断言就变成「测今天注册了几个玩法」，而不是「每个玩法一张磁贴」。
	var real_tiles := _find_named(hud, UiKit.TILE_NAME)
	var slots := _find_named(hud, UiKit.COVER_SLOT_NAME)
	# 空位磁贴**不叫** `UiKit.TILE_NAME`（它叫 `NEXT_SLOT_NAME`），所以这里数到的
	# 只可能是真玩法磁贴 —— 但为了保险，还是把两者分开数、只比真玩法那一类。
	var ghosts := _find_named(hud, Hud.NEXT_SLOT_NAME)
	_ok(real_tiles.size() == entry_n,
		"每个注册的玩法一张磁贴（条目 %d / 磁贴 %d / 空位 %d）"
			% [entry_n, real_tiles.size(), ghosts.size()])
	# 封面槽必须**和真磁贴一一对应**（空位磁贴没有封面槽 —— 它不画封面）。
	_ok(slots.size() == real_tiles.size(),
		"每张真磁贴配一个封面槽（磁贴 %d / 槽 %d）—— 槽少了就是某张卡开了天窗"
			% [real_tiles.size(), slots.size()])
	# ---- 封面槽的**真实尺寸**：这不是审美问题，是「画得出来吗」的问题。
	#
	# 必须 `await` 一帧：`Container.get_child(size)` 是**上次布局的结果**，
	# 刚 `add_child` 完读到的全是 0 —— 看着像布局坏了，其实只是还没跑。
	# （自检曾因此误判「封面槽宽 0，封面是一片看不见的竖线」。）
	#
	# 横向那个标志是**真的容易漏**：`SIZE_FILL` 是父容器默认值，含义是
	# 「至少给到我的**最小宽度**」，而普通 Control 的最小宽度是 0 ——
	# 于是封面槽宽 0、里面锚 `PRESET_FULL_RECT` 的 plate 也宽 0，一片空白且不报错。
	# 所以这里按「有没有拿到宽度」断言，而不是靠肉眼看截图。
	await get_tree().process_frame
	var slot_rects: Array = []
	for s in slots:
		slot_rects.append((s as Control).size)
	var too_narrow := 0
	for r in slot_rects:
		if (r as Vector2).x < 40.0:
			too_narrow += 1
	_ok(too_narrow == 0,
		"每个封面槽都拿到了宽度（%d 个，最窄 %.0fpx）—— 宽 0 的封面是一片空白"
			% [slot_rects.size(), _min_x(slot_rects)])

	# ---- 玩家药丸**住在状态条里**，不是单独占一行。
	#
	# 这条守的是一个**布局决定**：「谁在线」原来自己占一整行（底栏 70 基准高 + 24 间距），
	# 而状态条只用掉左端一小截、右端整片空着 —— 两块纵向代价换一件信息。
	# 搬进状态条之后省下整行高度给封面，同时那条空横条也被填满了。
	#
	# 判据：**大厅那份玩家位的容器**必须就是状态条里的席位盒（`rec["seats"]`）。
	# 注意变量名 `strip`/`_lobby_roster_box` 是历史名 —— 第 3 版起它装的是**席位圆点盒**，
	# 不再填名字药丸（见 `_build_lobby` 末尾）。`rec["strip"]` 这个键早就没了，
	# 早先这里读它会抛 SCRIPT ERROR、**静默吃掉本函数后面所有断言**（哨兵都没抓到）。
	# 现在按真实存在的键 `seats` 判。
	var strip_in_bar := false
	for row_d in hud._status_rows:
		var rd: Dictionary = row_d
		var seat_box: Node = rd["seats"]
		if seat_box != null and hud._lobby_roster_box == seat_box:
			strip_in_bar = true
	_ok(strip_in_bar,
		"大厅的玩家位（席位圆点盒）住在状态条里（不另占一行）—— 省下一整行高度给封面")
	_ok(_find_named(hud, Hud.NEXT_SLOT_NAME).size() == 1,
		"末尾补**一张**空位磁贴（不是把这一行补满 —— 补满会有一半屏幕是空框）")
	_ok(slots.size() == real_tiles.size() and slots.size() > 0,
		"每张玩法磁贴都有封面槽（磁贴 %d / 封面槽 %d）" % [real_tiles.size(), slots.size()])

	# ---- 空位磁贴必须和真磁贴**一样高**。
	#
	# 这条是实拍抓出来的 bug（polish-3）：空位磁贴原来只有「一个 EXPAND 的 ＋ 加一行说明」，
	# 而真磁贴的高度是它自己那套内容（封面 + rule + 名字行 + 药丸行）撑出来的。
	# 于是空位版少了两行 → 384 高，旁边真磁贴 494 高，**上边低 48、下边高 62**，
	# 一行里两张卡高矮不齐，看着像布局坏了。
	#
	# 已有的断言一条都拦不住：张数对、封面槽有宽度、封面画得出来 —— 全都通过。
	# 所以必须**直接量高度**。判据用「差别小于一档内边距」而不是全等：
	# 两张卡的描边档位不同（STROKE_STRONG vs STROKE_THIN），差几个像素是正常的，
	# 但差 100 多就不是了。
	var next_tiles := _find_named(hud, Hud.NEXT_SLOT_NAME)
	if next_tiles.size() == 1 and real_tiles.size() > 0:
		var h_next := (next_tiles[0] as Control).size.y
		var h_real := (real_tiles[0] as Control).size.y
		_ok(absf(h_next - h_real) < float(UiKit.TILE_PAD),
			"空位磁贴和真磁贴一样高（空位 %.0f / 真 %.0f）—— 高矮不齐看着像布局坏了"
				% [h_next, h_real])

	_ok(FakeGame.cover_builds > covers_before,
		"框架把封面画板递给了玩法：build_cover 被调了 %d 次"
			% (FakeGame.cover_builds - covers_before))

	# ---- 焦点态：三张磁贴里要有**两档描边**，且选中的那张更粗。
	# 这是「我现在在哪」在屏幕上唯一的指示 —— 遥控器没有指针，全靠它。
	var m3 := _hud_model(0, GameFlow.State.LOBBY)
	var lb: Lobby = m3["lobby"]
	lb.entries = _probe_entries(3)
	lb.selected = 1
	hud._lobby_sig = hud.NEVER_SIG
	hud.update_view(m3)
	var tiles3 := _find_named(hud, UiKit.TILE_NAME)
	_ok(tiles3.size() == 3, "一页排满 3 张磁贴（现在 %d 张）" % tiles3.size())
	var widths := {}
	var dimmed := 0
	for t in tiles3:
		var sb := (t as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		widths[sb.border_width_left] = true
		# 用 `_find_named`（前缀）而不是 `find_child`（全等）：槽名带序号（`cover_slot_0`）。
		var found := _find_named(t, UiKit.COVER_SLOT_NAME)
		var slot: Node = found[0] if not found.is_empty() else null
		var plate: Control = slot.get_child(0) if slot != null and slot.get_child_count() > 0 else null
		if plate != null and plate.modulate.a < 0.999:
			dimmed += 1
	var ws: Array = widths.keys()
	ws.sort()
	_ok(ws.size() == 2 and int(ws[1]) > int(ws[0]),
		"选中的磁贴描边比未选中的粗（两档：%s）" % str(ws))
	_ok(dimmed == 2, "未选中的两张封面被压暗、选中的那张保持原样（压暗 %d 张）" % dimmed)

	# ---- 页点：只有一页时不画（画一个孤零零的点等于告诉人「还有别的」，是误导）
	hud.update_view(_hud_model(0, GameFlow.State.LOBBY))
	_ok(not _has_visible_text(hud, "下一页"), "单页时不出现翻页提示")

	# ---- 对局屏：**没有左信息栏**，只有顶部细横条（时间 + 比分）
	#
	# TUG-02 把左栏整个删了：玩法名 / 在座玩家名单都不再上屏。
	# 这条断言就是「左栏真的没了」的可执行版本 —— 查那两样旧内容都查不到。
	var flow := _mini_flow(2)
	_ok(flow.current != null, "2 人能把这一局开起来（这组的其它断言都以此为前提）")

	hud.update_view(_hud_model(2, GameFlow.State.PLAYING, flow))
	_ok(hud._play_root.visible and not hud._lobby_root.visible,
		"对局状态：显示玩法屏、藏起大厅屏")
	_ok(not _has_visible_text(hud, "在座玩家"),
		"对局屏上不再有「在座玩家」名单（左信息栏整个删了 —— 谁跟谁一边由场上的队色说）")
	_ok(not _has_visible_text(hud, "玩什么"), "对局屏上不该出现大厅清单")

	# 顶部细横条：时间和两队的数字都要看得见。
	var bar := _collect_play_bar_labels(hud)
	var bar_text := " ".join(bar)
	_ok(bar_text.contains("剩"),
		"顶部横条画出了剩余时间（现在：「%s」）" % bar_text.strip_edges())
	_ok(_bar_shows_left_and_right(hud),
		"顶部横条画出了两队比分（左队/右队两个数字各占一格，各上队色）")

	hud.update_view(_hud_model(2, GameFlow.State.COUNTDOWN, flow))
	_ok(_stage_countdown_number(hud) != "", "倒计时的大数字上了屏（舞台上那个 HUGE 数字）")
	_ok(_has_text(hud, "拿稳手机"), "倒计时在舞台上提示了准备")
	_ok(_has_text(hud, "往上蹦"), "倒计时提示的是「往上蹦」（动作从「拉」换成了蹦 —— TUG-01）")

	# 横条是**对局屏专属**：大厅屏上不该出现它的文字。
	hud.update_view(_hud_model(2, GameFlow.State.LOBBY, flow))
	_ok(not _has_visible_text(hud, "剩 "),
		"顶部横条只在对局屏出现，大厅屏上没有它")

	# ---- 掉线：槽位置空**不删**，后面的人槽位号不会前移。
	#
	# 「槽位 N 空」这句字**原来画在玩家名单上**（对局屏左栏 / 大厅底栏的药丸）。
	# TUG-02 把名单两处都删了，所以这句字不再上屏 —— 这条断言从「查屏上的字」
	# 改成查**模型本身**：槽位数组长度不变、被置空的那个还是 null、
	# 后面那个人的下标没往前挤。槽位不漂移是**逻辑保证**，不该依赖有没有画出来。
	var cur: FakeGame = flow.current
	cur.sessions[1] = null
	_ok(cur.sessions.size() == 2 and cur.sessions[1] == null,
		"掉线槽位置空不删：数组长度仍是 2、被置空的那格仍是 null（槽位号不漂移）")
	hud.update_view(_hud_model(2, GameFlow.State.PLAYING, flow))

	# ---- 结算：遮罩要真的亮起来，文案要上屏；回大厅要收掉
	hud.update_view(_hud_model(2, GameFlow.State.RESULT, flow, "甲队赢啦——这句是结算详情"))
	_ok(_has_text(hud, "甲队赢啦"), "结算文案真的上屏了（历史上它只进日志）")
	_ok(_has_text(hud, "这句是结算详情"), "结算详情的破折号后半段也上了屏")
	_ok(hud._result_layer.visible, "结算遮罩真的显示了")
	hud.update_view(_hud_model(2, GameFlow.State.LOBBY, flow))
	_ok(not hud._result_layer.visible, "离开结算遮罩自己收掉（不会留一块点不掉的灰）")

	remove_child(layer)
	layer.free()
	flow.free()


# ------------------------------------------------------------------ 可插拔（玩法与框架分家）

## 框架源码里**不许出现任何一个玩法的 id / 名字 / 目录名**。
##
## 这条断言就是「哪怕这个玩法删掉也不影响框架」的可执行版本。它盯两件事：
##   1. **编译期耦合**：`preload("res://scripts/minigames/<玩法>/…")` 会让框架在编译期
##      点名依赖那个玩法 —— 删掉玩法目录，框架连大厅都起不来。
##   2. **运行期耦合**：`match game_id: "tug"`、`if cur is TugOfWar` 这类分支，
##      同样把玩法焊进框架。
##
## 判定方式：**剥掉注释**再找这些字符串。注释里提到某个玩法做举例是正常的文档，
## 不该拦；真正要拦的是代码里出现它的名字。
##
## 顺带说明为什么断言条数要**汇总成一条**：这组要是「每个玩法 _ok 一次」，
## 删掉玩法会让总数变化，别处那道防静默的哨兵就会误报。
func _check_pluggable_no_game_refs() -> void:
	print("\n[13] 可插拔：框架源码里不许出现任何玩法的 id / 名字 / 目录名")

	var srcs := _framework_sources()
	_ok(srcs.size() >= 10, "扫到了 %d 个框架源文件（scripts/ 下除玩法目录以外的一切）" % srcs.size())

	# 先给扫描器自己做个反证：不然这组可能只是「什么都没查」地绿着。
	# 这段假源码是**拼**出来的 —— 免得它自己命中下面那条「不许 preload 玩法脚本」的检查。
	var fake_dir := "minigames/zzz_game"
	var probe_code := 'var id = "zzz_game"\npreload("res://scripts/%s/g.gd")\n' % fake_dir
	_ok(_scan_game_refs(probe_code, ["zzz_game"], []).size() == 2,
		"扫描器抓得到代码里的玩法 id 与目录名（反证，防止空转）")
	_ok(_scan_game_refs('# 注释里提到 "zzz_game" 和 %s/x.gd 不算耦合' % fake_dir,
		["zzz_game"], []).is_empty(),
		"注释里提到玩法不算耦合（剥注释这步是有效的）")
	_ok(_scan_game_refs(probe_code, [], ["假玩法"]).is_empty(),
		"不传玩法名字，就只按 id / 目录名扫")

	# 只盯**住在玩法目录里**的玩法。框架自带的测试假玩法（scripts/dev/）是框架零件，
	# 不受这条约束 —— 它要是也得躲着名字走，这组测试自己就没法读。
	var game_ids: Array = []
	var game_names: Array = []
	for s in GameRegistry.scripts():
		if not s.resource_path.begins_with(GameRegistry.GAMES_DIR + "/"):
			continue
		var probe: MiniGame = s.new()
		var m := probe.meta()
		game_ids.append(str(m.get("id", "")))
		game_names.append(str(m.get("name", "")))
		probe.free()

	var hits: Array[String] = []
	for path in srcs:
		for ref in _scan_game_refs(srcs[path], game_ids, game_names):
			hits.append("%s 里的 %s" % [path, ref])
	_ok(hits.is_empty(), "框架源码里没有出现任何玩法的 id / 名字 / 目录名%s" % (
		"" if hits.is_empty() else " —— 但：%s\n      （把它挪进玩法目录，或者在框架里说「某个玩法」而不是点名）" % str(hits)))

	# 编译期那条单独再钉一次：整个框架不许 preload 任何玩法脚本
	var preload_hits: Array[String] = []
	for path in srcs:
		if _strip_comments(srcs[path]).contains("preload(\"res://scripts/minigames"):
			preload_hits.append(path)
	_ok(preload_hits.is_empty(), "框架里没有 preload 任何玩法脚本（preload 是编译期依赖）%s" % (
		"" if preload_hits.is_empty() else " —— 但：%s" % str(preload_hits)))

	var cur := 0
	for path in srcs:
		cur += str(srcs[path]).length()
	print("      扫了 %d 个文件 / %d 字符；当前住在玩法目录里的玩法：%s" % [
		srcs.size(), cur, str(game_ids),
	])


## 框架自己的源码 = `scripts/` 下**除了 `scripts/minigames/` 之外**的全部 `.gd`。
##
## 定义成「除了玩法目录以外的一切」，以后加框架文件就不用回来改这个列表。
func _framework_sources() -> Dictionary:
	var out := {}
	_collect_gd("res://scripts", out)
	return out


func _collect_gd(dir_path: String, out: Dictionary) -> void:
	if dir_path == GameRegistry.GAMES_DIR:
		return
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with(".gd"):
			var p := dir_path.path_join(f)
			out[p] = FileAccess.get_file_as_string(p)
	for d in DirAccess.get_directories_at(dir_path):
		_collect_gd(dir_path.path_join(d), out)


## 扫一段源码里有没有出现这些玩法特征串，返回命中的原串（空 = 干净）。
##
## 认这三种写法：
##   "tug" / 'tug'        → 直接比较 id
##   minigames/tug        → preload/load 一个玩法目录下的东西
##   "拔河" / '拔河'      → 直接比较玩法名
func _scan_game_refs(code: String, ids: Array, names: Array) -> Array[String]:
	var out: Array[String] = []
	var stripped := _strip_comments(code)
	for id in ids:
		for needle in ["\"%s\"" % id, "'%s'" % id, "minigames/%s" % id]:
			if stripped.contains(needle):
				if not out.has(needle):
					out.append(needle)
	for nm in names:
		for needle in ["\"%s\"" % nm, "'%s'" % nm]:
			if stripped.contains(needle):
				if not out.has(needle):
					out.append(needle)
	return out


## 把 GDScript 源码里的注释剥掉（专供上面那条扫描，不打算当通用解析器）。
##
## 走一遍字符、跟踪「在不在字符串里」：字符串里的 `#` 不算注释开头，行内的 `#`
## 到行尾整段丢掉（换行保留，免得把两行粘成一句）。
##
## 已知的简化：三引号多行字符串没特殊处理 —— 真碰上了就干脆不剥（宁可偏严，
## 让这组测试误报，也别漏报一处真耦合）。
func _strip_comments(code: String) -> String:
	if code.contains("\"\"\""):
		return code
	var out := ""
	var quote := ""
	var i := 0
	var n := code.length()
	while i < n:
		var ch := code[i]
		if not quote.is_empty():
			out += ch
			if ch == "\\" and i + 1 < n:
				out += code[i + 1]
				i += 2
				continue
			if ch == quote:
				quote = ""
			i += 1
			continue
		if ch == "\"" or ch == "'":
			quote = ch
			out += ch
			i += 1
			continue
		if ch == "#":
			while i < n and code[i] != "\n":
				i += 1
			continue
		out += ch
		i += 1
	return out


# ------------------------------------------------------------------ 玩法自带测试

## 把各玩法**自己带的**规则测试跑一遍。
##
## 这里不认识任何一个玩法 —— 只是把玩法目录里扫到的 `*_selftest.gd`
## 挨个 new 出来 run() 一遍（见 GameRegistry.selftest_scripts()）。
## 所以删掉一个玩法目录，它带的那几组测试跟着一起消失，这里一个字都不用改。
##
## 它们的断言**不计入**框架的 EXPECTED_MIN：玩法是可插拔的，
## 总数跟着变是正常的，而哨兵要盯的是「框架自己有没有静默崩掉」。
func _run_game_selftests() -> void:
	var found := GameRegistry.selftest_scripts()
	print("\n===== 玩法自带的规则测试（扫到 %d 组）=====" % found.size())
	if found.is_empty():
		print("  （没有玩法带自检 —— 一个玩法都没注册也是合法状态，不算失败）")

	for s in found:
		var t: MiniGameSelfTest = s.new()
		print("\n[玩法自带] %s —— %s" % [t.title(), s.resource_path])
		t.run()
		# 玩法自己声明了断言下限：对不上就说明它中途崩了（GDScript 的运行时错误
		# 不会抛异常，只会把当前函数当场中断 —— 少了断言看起来和全过一模一样）
		if t.pass_count + t.fail_count < t.expected_min():
			t.note_crash("断言只有 %d 条，不到这一组自己声明的 %d 条 —— 中途崩了" % [
				t.pass_count + t.fail_count, t.expected_min(),
			])
		for line in t.lines():
			print(line)
		print("  —— %d 通过 / %d 失败" % [t.pass_count, t.fail_count])
		_pass += t.pass_count
		_fail += t.fail_count


# ------------------------------------------------------------------ 小工具

## 造一个**框架自带的假玩法**实例（框架这几组测试的载体）。
## [param with_rewards] 默认 false —— 基础规则测试要把道具/复活额度清零，
## 否则绳子一到线就挂起等奖励，根本走不到判负那一步（这个坑踩过一次）。
func _new_game(player_count: int, with_rewards: bool = false) -> FakeGame:
	var game := FakeGame.new()
	game.sessions = _sessions(player_count)
	game.setup()  # setup() 会把额度重置成默认值，所以覆盖必须放在它之后
	if not with_rewards:
		game.revive_left = 0
		game.item_left = 0
	return game


func _sessions(player_count: int) -> Array:
	var out: Array = []
	for i in player_count:
		out.append(_fake_session(100 + i, "玩家 %d" % (i + 1)))
	return out


func _fake_session(pid: int, name: String) -> PlayerSession:
	var s := PlayerSession.new()
	s.player_id = pid
	s.player_name = name
	return s


func _jump(power: float = 1.0) -> Dictionary:
	return {"type": "jump", "power": power}


## 驱动玩法直到结束或超时。`jumpers` 里的槽位每 tick 蹦一下。
## 和新力量模型（`minigame_selftest.drive()`）对齐：既把 `filter.jump` 打满
## （拔河这类玩法读的是**连续蹦劲**），也塞一个 `{"type":"jump"}` 事件
## （事件驱动的玩法靠它推进，同时供数「蹦了几次」）。
## 直接读写 game.sessions —— 玩法持有的那套 session 才是它真正读的，
## 另建一套塞事件是测不到东西的（这个坑踩过一次）。
func _drive(game: MiniGame, jumpers: Array, seconds: float,
		dt: float = 1.0 / 60.0) -> int:
	var t := 0.0
	var ticks := 0
	while t < seconds and not game.is_over():
		for i in game.sessions.size():
			var s: PlayerSession = game.sessions[i]
			if s != null:
				var on := i in jumpers
				s.filter.jump = 1.0 if on else 0.0
				s.events = [_jump()] if on else []
		game.tick(dt)
		t += dt
		ticks += 1
	return ticks


func _step(flow: GameFlow, seconds: float, dt: float) -> void:
	var t := 0.0
	while t < seconds:
		flow._process(dt)
		t += dt


## 造一套「流程 + 奖励服务 + mock 网关」，answer_delay_sec=0 时完全确定性
func _new_reward_stack(policy: String, delay: float, timeout: float) -> Dictionary:
	var flow := GameFlow.new()
	add_child(flow)
	flow.set_process(false)

	var svc := RewardService.new()
	svc.timeout_sec = timeout
	add_child(svc)
	svc.set_process(false)

	var gw := MockRewardGateway.new()
	gw.policy = policy
	gw.answer_delay_sec = delay
	add_child(gw)
	gw.set_process(false)

	svc.set_gateway(gw)
	flow.set_reward_service(svc)
	return {"flow": flow, "svc": svc, "gw": gw}


func _free_stack(stack: Dictionary, free_flow: bool = true) -> void:
	if free_flow:
		var flow: GameFlow = stack["flow"]
		remove_child(flow)
		flow.free()
	for key in ["svc", "gw"]:
		var n: Node = stack[key]
		remove_child(n)
		n.free()


func _ready_count_in(entries: Array) -> int:
	var n := 0
	for e in entries:
		if bool(e.get("ready", false)):
			n += 1
	return n


## 造一份 HUD 认识的模型。键名和 main.gd 的 `_hud_model()` 保持一致 ——
## 这里故意**不调用** main.gd 的那个函数（那要整个 Main 场景），
## 而是照它的契约另造一份：契约一旦漂移，这组断言就会红，正是想要的效果。
func _hud_model(
	online: int, state: int, flow: GameFlow = null, result_text: String = ""
) -> Dictionary:
	var roster: Array = []
	var cur: MiniGame = flow.current if flow != null else null
	if cur != null:
		for slot in cur.sessions.size():
			var ps: PlayerSession = cur.sessions[slot]
			if ps == null:
				roster.append({"label": "槽位 %d 空" % slot, "color": UiKit.PILL_MUTE})
			else:
				# 名字后面跟什么标签由**玩法**说了算（MiniGame.slot_tag）
				var tag := cur.slot_tag(slot)
				roster.append({
					"label": ps.display_name() + ("" if tag.is_empty() else " " + tag),
					"color": PlayerPalette.color_for_slot(slot),
				})
	else:
		for i in online:
			roster.append({
				"label": PlayerNames.at(i), "color": PlayerPalette.color_for_slot(i),
			})
	var lobby := Lobby.new()
	lobby.refresh(online)
	return {
		"state": state,
		"state_name": "测试",
		"online": online,
		"max_players": 8,
		"recv": 0,
		"lost": 0,
		"port": 8910,
		"lobby": lobby,
		"hint": "",
		"game": cur,
		"countdown": 2.0,
		"awaiting_reward": false,
		"reward": {},
		"result": {"text": result_text, "winner_team": 0},
		"roster": roster,
	}


## 造一套「已经开始的一局」：n 个假玩家、槽位已分配
func _mini_flow(n: int) -> GameFlow:
	var flow := GameFlow.new()
	add_child(flow)
	flow.set_process(false)
	var sessions: Array = []
	for i in n:
		sessions.append(_fake_session(200 + i, PlayerNames.at(i)))
	flow.start_game(FakeGame.ID, sessions)
	return flow


## 扫一整棵子树的 Label 文字。断言只认「画出来的字」，不认内部变量 ——
## 内部变量对得上但没画的 bug 才正是要抓的那些。
func _texts(root: Node, out: Array = []) -> Array:
	for c in root.get_children():
		if c is Label:
			out.append((c as Label).text)
		_texts(c, out)
	return out


func _has_text(root: Node, needle: String) -> bool:
	for t in _texts(root):
		if str(t).contains(needle):
			return true
	return false


## 只扫 **visible** 的子树。
##
## 为什么必须有这个：`_texts` 连藏起来的节点也扫。大厅和玩法两屏的节点**都是建好的**，
## 所以「大厅里不该出现对局信息」这种话用 `_has_text` 永远验不出来 —— 它翻得到藏起来那一屏。
## 要证明「这一屏现在没显示」，只能按 visible 走。
func _visible_texts(root: Node, out: Array = []) -> Array:
	for c in root.get_children():
		if c is CanvasItem and not (c as CanvasItem).visible:
			continue
		if c is Label:
			out.append((c as Label).text)
		_visible_texts(c, out)
	return out


func _has_visible_text(root: Node, needle: String) -> bool:
	for t in _visible_texts(root):
		if str(t).contains(needle):
			return true
	return false


## 顶部细横条上**可见**的文字（时间格 + 两队格 + 徽标格）。
##
## 按 `visible` 走：横条只在 `_play_root` 可见时才算数（大厅状态下整棵藏起来）。
## 直接抓 `hud._play_bar_*` 这几个字段所在的 Label —— 它们是横条的全部文字面。
func _collect_play_bar_labels(hud: Node) -> Array:
	var out: Array = []
	for field in ["_play_bar_time", "_play_bar_left", "_play_bar_right"]:
		var l := hud.get(field) as Label
		if l != null and l.is_visible_in_tree() and not l.text.is_empty():
			out.append(l.text)
	# 右端徽标盒里的数字/图标（可能为空 —— 没额度时整盒无内容）。
	var badges := hud.get("_play_bar_badges") as Node
	if badges != null and badges.is_visible_in_tree():
		for t in _visible_texts(badges):
			if not str(t).is_empty():
				out.append(str(t))
	return out


## 顶部横条是不是画出了两队比分：时间格之外，`_play_bar_left` / `_play_bar_right`
## 两个字段都有非空数字文本，并且**颜色不同**（各自队伍色）。
func _bar_shows_left_and_right(hud: Node) -> bool:
	var l := hud.get("_play_bar_left") as Label
	var r := hud.get("_play_bar_right") as Label
	if l == null or r == null:
		return false
	if l.text.is_empty() or r.text.is_empty():
		return false
	if not (l.text.is_valid_int() and r.text.is_valid_int()):
		return false
	# 两队数字各自上队色 —— 颜色必须不同，否则「两队」这个区分就没了。
	return l.get_theme_color("font_color") != r.get_theme_color("font_color")


## 倒计时大数字的文本：舞台居中的那张卡里，字号 = `FONT_HUGE` 的那个 Label。
## 找不到就返回空串（断言据此判红）。
func _stage_countdown_number(hud: Node) -> String:
	var card := hud.get("_stage_center_card") as Node
	if card == null or not (card as CanvasItem).is_visible_in_tree():
		return ""
	for t in _texts(card):
		var s := str(t)
		if s.is_valid_int():
			return s
	return ""


## 一组 `Vector2` 里最小的 x（自检报错信息要用，0 宽是最难从截图上看出来的那种坏）。
func _min_x(rects: Array) -> float:
	if rects.is_empty():
		return 0.0
	var m := INF
	for r in rects:
		m = minf(m, (r as Vector2).x)
	return m


## 按节点名**前缀**递归收集整棵子树里的节点。
##
## 为什么不能改成「数一个容器有几个孩子」：磁贴外面还套着行、空位占位、弹性垫片，
## 数孩子的结果是布局的副作用，不是「有几个玩法」。按名字找才盯得住**磁贴本身**。
##
## 为什么是前缀而不是全等：磁贴和封面槽的名字都**自带序号**（`game_tile_0`、
## `cover_slot_2`），调用点传的是基名（`UiKit.TILE_NAME`）。全等匹配会把带序号的全漏掉 ——
## 这个 bug 真发生过：注册了 2 个玩法（`fake` + `tug`），却只数到 1 张磁贴。
## （序号是为了绕开 Godot 的「同名兄弟自动改名」，见 `UiKit.tile` 的注释。）
##
## `out` 是拿来递归累积的，调用点只传前两个参数。
func _find_named(root: Node, base_name: String, out: Array = []) -> Array:
	for c in root.get_children():
		if str(c.name).begins_with(base_name):
			out.append(c)
		_find_named(c, base_name, out)
	return out


## 数状态条上一共有几个「席位圆点」。
##
## 判据是**类型**：`UiKit.seat_dot()` 返回的是 `UiKit.SeatDot`（自绘控件），
## 全项目只有它一处用。这比找文字可靠 —— 圆点上写的序号（1..8）会跟着
## `UdpServer.max_players` 变，钉死在「有 8 个」上，一改容量断言就碎，
## 而它本来要证明的是「席位被画出来了」。
##
## ⚠️ 状态条现在**只有一份**（在大厅屏上）。曾经有两份（大厅 + 对局左栏各一份），
## 所以历史判据加了 `lobby_only` 去筛。TUG-02 删掉对局屏左信息栏后，那份随栏一起没了。
## `lobby_only` 参数**保留**（调用点还传着），语义仍是「只数可见的」——
## 现在无论传什么都不影响结果（只有一份），但留着它以后再加对局屏状态条时不用改调用点。
##
## 从 HUD 根往下递归找，不依赖节点路径 —— 路径写死一份就只数到一半。
func _count_seat_dots(hud: Node, lobby_only: bool = false) -> int:
	return _collect_seat_dots(hud, lobby_only).size()


## 数**已经坐人**的席位圆点（`state` 是 `joined` 或 `host`）。
func _count_joined_seats(hud: Node, lobby_only: bool = false) -> int:
	var n := 0
	for d in _collect_seat_dots(hud, lobby_only):
		if str(d.get("state")) != "empty":
			n += 1
	return n


## 数**房主**席位（`state == "host"`）。设计稿用番茄红单独标出房主，应当恰好一个。
func _count_seat_hosts(hud: Node, lobby_only: bool = false) -> int:
	var n := 0
	for d in _collect_seat_dots(hud, lobby_only):
		if str(d.get("state")) == "host":
			n += 1
	return n


## 递归收集所有席位圆点节点。
##
## `lobby_only` 会跳过不可见的子树 —— 判据是 `is_visible_in_tree()` 而不是 `visible`：
## 后者的意思是「我自己这个节点上的开关」，父节点关掉了它照样是 true。
func _collect_seat_dots(node: Node, lobby_only: bool = false) -> Array:
	var out := []
	if lobby_only and node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return out
	if node is UiKit.SeatDot:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_seat_dots(c, lobby_only))
	return out


## 框架自己的断言。要跨组传一个可变状态就塞进字典里传（lambda 是按值捕获的）。
func _ok(cond: bool, label: String) -> void:
	# EXPECTED_MIN 只盯框架这一摊
	_fw_pass += 1 if cond else 0
	_fw_fail += 1 if not cond else 0
	_tally(cond, label)


## 只记总数、不进框架那道哨兵（玩法自带的测试走这里，实际由 _run_game_selftests 记账）。
func _tally(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  [OK]   %s" % label)
	else:
		_fail += 1
		print("  [FAIL] %s" % label)
