class_name MiniGameSelfTest
extends RefCounted

## 玩法自带的规则测试的基类。**放玩法目录里**，文件名以 `_selftest.gd` 结尾。
##
## 为什么玩法测试要住在玩法目录里：
## 框架自检（`scripts/dev/selfcheck.gd`）只该验**框架自己**的东西 —— 状态机、奖励挂起、
## 掉线、大厅。而「一次挥动推多少」「什么时候算出线」是**玩法自己**的规则，测试也该跟着
## 玩法走。这样把某个玩法目录**整个删掉**时，它自带的测试跟着一起消失，框架自检
## 不用改一个字、也不会有任何一组因为「找不到那个玩法」而崩。
##
## 子类只要覆盖 title() 和 run()：
##
##     class_name TugSelfTest
##     extends MiniGameSelfTest
##
##     func title() -> String:
##         return "拔河规则"
##
##     func run() -> void:
##         ok(true, "看起来还行")
##
## 框架侧不认识任何具体玩法 —— 它只是扫目录、把扫到的 `*_selftest.gd` 挨个跑一遍
## （见 GameRegistry.selftest_scripts()）。判断标准还是那条：
## **框架文件里不该出现任何一个玩法的名字、id 或路径。**

var pass_count: int = 0
var fail_count: int = 0

var _lines: Array[String] = []


## 这一组的标题（打印在组名后面）。
func title() -> String:
	return "未命名玩法测试"


## 这一组「本来应该产出多少条断言」。
##
## 和 EXPECTED_MIN 是同一个道理：GDScript 的运行时错误不会抛异常，只会把当前函数
## 当场中断 —— 那一组的断言就无声无息地少了，日志看起来「0 失败」，实际是绿的坏测试。
## 所以玩法自己声明一个下限，跑完对不上就报 FAIL。
##
## **加了断言记得同步调大这个数。** 填 0 表示不检查。
func expected_min() -> int:
	return 0


## 跑自己的规则测试。子类覆盖。
func run() -> void:
	pass


## 一条断言。
func ok(cond: bool, label: String) -> void:
	if cond:
		pass_count += 1
		_lines.append("  [OK]   %s" % label)
	else:
		fail_count += 1
		_lines.append("  [FAIL] %s" % label)


## 打一行附注（不断言，只给人看）。
func note(line: String) -> void:
	_lines.append(line)


func lines() -> Array[String]:
	return _lines


## 一条断言都没跑成（中途崩了）时，由框架调这个补记一笔失败。
func note_crash(detail: String) -> void:
	fail_count += 1
	_lines.append("  [FAIL] %s" % detail)


# ------------------------------------------------------------------ 造数据的小工具

## 造一个假玩家。玩法测规则**不连网络** —— 直接往 session 里塞合成事件就够了。
func make_session(pid: int, name: String) -> PlayerSession:
	var s := PlayerSession.new()
	s.player_id = pid
	s.player_name = name
	return s


func make_sessions(player_count: int) -> Array:
	var out: Array = []
	for i in player_count:
		out.append(make_session(100 + i, PlayerNames.at(i)))
	return out


## 一次「往上蹦」事件。形状和输入抽象层（MotionFilter）产出的一致。
func jump(power: float = 1.0) -> Dictionary:
	return {"type": "jump", "power": power}


## 驱动一个玩法直到结束或超时。`jumpers` 里的槽位每 tick 蹦一次。
##
## 这里直接写 `session.events` 而不是 push_event()：要的是**确定性的「每帧正好一次」**，
## 而事件队列有 MAX_PENDING_EVENTS 封顶、语义是「自上次取走以来发生的事件」——
## 在测试里每帧覆写一遍，才不依赖消费方有没有及时 drain。
##
## 同时把 `session.filter.jump` 打满 —— 新力量模型（拔河）读的是**连续蹦劲**，
## 不是离散事件；事件只用来数「蹦了几次」，事件驱动的假玩法也靠它推进。
##
## 注意必须读写**玩法自己持有的那套 sessions**：另建一套塞事件是测不到东西的
## （这个坑踩过）。
func drive(game: MiniGame, jumpers: Array, seconds: float, dt: float = 1.0 / 60.0) -> int:
	var t := 0.0
	var ticks := 0
	while t < seconds and not game.is_over():
		for i in game.sessions.size():
			var s: PlayerSession = game.sessions[i]
			if s == null:
				continue
			var on := i in jumpers
			s.filter.jump = 1.0 if on else 0.0
			s.events = [jump()] if on else []
		game.tick(dt)
		t += dt
		ticks += 1
	return ticks
