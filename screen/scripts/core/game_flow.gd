class_name GameFlow
extends Node

## 流程状态机：大厅 → 倒计时 → 对局中 →（等奖励）→ 对局中 / 结算 → 大厅。
##
## 框架层。它只做四件事：
##   1. 决定什么时候能开局（人数落在玩法的 min/max 区间内）
##   2. 在开局那一刻分配槽位、把 sessions 交给玩法
##   3. 按状态驱动玩法的钩子，并负责收尾清理
##   4. 玩法要奖励（道具/复活）时挂起对局，去网关走一趟再放行
## 它不懂任何玩法规则，也不懂奖励从哪来 —— 那是 MiniGame 和 RewardGateway 的事。

signal state_changed(from: int, to: int)
signal game_started(game_id: String, player_count: int)
signal game_finished(result: Dictionary)
signal reward_started(req: Dictionary)
signal reward_settled(req: Dictionary, granted: bool, data: Dictionary)

enum State { LOBBY, COUNTDOWN, PLAYING, REWARD, RESULT }

const COUNTDOWN_SEC := 5.0
const RESULT_SEC := 5.0

## 奖励网关的门房。没配也能跑 —— 那样奖励请求一律按「拿不到」处理，不会卡死对局。
var reward_service: RewardService = null

var state: int = State.LOBBY
var current: MiniGame = null
var current_id: String = ""
var last_result: Dictionary = {}

var _timer: float = 0.0
var _log_timer: float = 0.0
## 本局玩家（直接引用 UdpServer 里的 session 对象）
var _sessions: Array = []

## 正在等的奖励请求（空 = 没在等）
var _reward_req: Dictionary = {}
var _pending_id: int = -1
var _reward_log_timer: float = 0.0


func state_name() -> String:
	match state:
		State.LOBBY: return "大厅"
		State.COUNTDOWN: return "倒计时"
		State.PLAYING: return "对局中"
		State.REWARD: return "等奖励"
		State.RESULT: return "结算"
	return "?"


## 正在等奖励结果
func is_awaiting_reward() -> bool:
	return state == State.REWARD


## 倒计时还剩几秒（不在倒计时阶段返回 0）。HUD 用它把数字放大上屏。
func countdown_left() -> float:
	return maxf(_timer, 0.0) if state == State.COUNTDOWN else 0.0


## 当前奖励请求（HUD 用）
func pending_reward() -> Dictionary:
	return _reward_req


func is_busy() -> bool:
	return state != State.LOBBY


## 有人掉线：把对应槽位腾空。
## 注意是**置空而不是删掉** —— 槽位一旦分配给某人就固定下来，抽掉中间一个会让
## 后面所有人的槽位号前移，颜色和身份就全乱了。玩法层遇到空槽自己跳过。
func drop_player(player_id: int) -> void:
	if state == State.LOBBY or current == null:
		return
	for i in _sessions.size():
		var s: PlayerSession = _sessions[i]
		if s != null and s.player_id == player_id:
			_sessions[i] = null
			print("[flow] 槽位 %d（%s）掉线，本局还剩 %d 人" % [i, s.display_name(), _active_count()])
			break
	if not current.accepts_count(_active_count()):
		# 注意用 accepts_count 而不是 min_players()：玩法可能有额外的组队规则。
		# 拔河就是这样 —— 少一个人还能凑够 2 人，但两队从 2v2 变成 1v2 就不公平了。
		abort("剩下 %d 人，不够接着打这一局了" % _active_count())


## 试着开局。人数不满足玩法要求会被拒绝并返回 false。
func start_game(game_id: String, sessions: Array) -> bool:
	if is_busy():
		print("[flow] 已经在「%s」，先等这局完" % state_name())
		return false

	var game := GameRegistry.create(game_id)
	if game == null:
		return false

	if not game.accepts_count(sessions.size()):
		var m := game.meta()
		print("[flow] 《%s》需要 %d-%d 人（另有规则见 accepts_count），当前 %d 人，开不了" % [
			m.get("name", game_id), game.min_players(), game.max_players(), sessions.size(),
		])
		game.free()
		return false

	# 开局这一刻才分配槽位 —— 网络会话与游戏角色就此解耦。
	# 中途有人进出不会打乱已上场的玩家身份。
	_sessions = sessions.duplicate()
	for i in _sessions.size():
		_sessions[i].slot = i

	current = game
	current_id = game_id
	current.sessions = _sessions
	add_child(current)
	current.setup()

	_timer = COUNTDOWN_SEC
	_log_timer = 0.0
	_set_state(State.COUNTDOWN)

	var m := current.meta()
	print("[flow] 开局《%s》%d 人：%s" % [
		m.get("name", game_id), _sessions.size(),
		_player_roster(_sessions),
	])
	print("[flow] 槽位 → %s" % _slot_roster(_sessions))
	game_started.emit(game_id, _sessions.size())
	return true


## 硬中止（比如人都跑光了），不产生结算
func abort(reason: String = "") -> void:
	if state == State.LOBBY:
		return
	print("[flow] 中止本局 %s" % reason)
	if not _reward_req.is_empty() and reward_service != null:
		reward_service.cancel_all()
	_cleanup()
	_set_state(State.LOBBY)


## 接上奖励网关的门房。接完就能用 turn-based 的奖励流程了。
func set_reward_service(svc: RewardService) -> void:
	if reward_service != null and reward_service.resolved.is_connected(_on_reward_resolved):
		reward_service.resolved.disconnect(_on_reward_resolved)
	reward_service = svc
	if reward_service != null and not reward_service.resolved.is_connected(_on_reward_resolved):
		reward_service.resolved.connect(_on_reward_resolved)


func _process(delta: float) -> void:
	match state:
		State.LOBBY:
			pass
		State.COUNTDOWN:
			_timer -= delta
			if current != null:
				current.countdown(maxf(_timer, 0.0))
			if _timer <= 0.0:
				_set_state(State.PLAYING)
		State.PLAYING:
			_tick_playing(delta)
		State.REWARD:
			_tick_reward(delta)
		State.RESULT:
			_timer -= delta
			if _timer <= 0.0:
				_cleanup()
				_set_state(State.LOBBY)


func _tick_playing(delta: float) -> void:
	if current == null:
		abort("玩家人数为 0")
		return

	# 人都走了就没什么好比的
	if _active_count() == 0:
		abort("玩家全部离线")
		return

	current.tick(delta)

	# 每秒打一行状态，无头验证时这是主要证据
	_log_timer += delta
	if _log_timer >= 1.0:
		_log_timer = 0.0
		print("[flow] %s  %s" % [state_name(), current.status_text()])

	# 玩法想要奖励吗？先说奖励 —— 比如绳子已经压线了，救回来这局就还没完。
	# 顺序很重要：排在 is_over() 前面，才有机会把「即将判负」翻盘。
	var req := current.pending_reward_request()
	if not req.is_empty():
		_begin_reward(req)
		return

	if current.is_over():
		_finish_round()


## 等奖励期间对局是**挂起**的：不 tick、不判胜负，绳子/场面冻在那里。
## 玩家此刻在答题（或看广告），大屏只显示等待提示。
func _tick_reward(delta: float) -> void:
	if current == null:
		abort("等奖励时玩法没了")
		return
	_reward_log_timer -= delta
	if _reward_log_timer <= 0.0:
		_reward_log_timer = 5.0
		print("[flow] 等奖励中… %s" % _describe_reward(_reward_req))


func _finish_round() -> void:
	last_result = current.result()
	_set_state(State.RESULT)
	_timer = RESULT_SEC
	print("[flow] 本局结束 → %s" % _describe_result(last_result))
	game_finished.emit(last_result)


# ------------------------------------------------------------------ 奖励

func _begin_reward(req: Dictionary) -> void:
	if reward_service == null:
		# 没接网关就别把对局卡死 —— 直接按「拿不到」走，玩家什么都不亏
		print("[flow] 玩法要奖励，但没配奖励网关 → 按「拿不到」处理")
		_resolve_reward(req, false, {"reason": "no_gateway", "detail": "本局没开奖励"})
		return

	_reward_req = req
	_reward_log_timer = 0.0
	current.begin_reward(req)
	_set_state(State.REWARD)
	print("[flow] 请求奖励 → %s" % _describe_reward(req))
	reward_started.emit(req)

	# 网关可能同步就回答了（mock 延迟为 0），所以状态要先摆好再发请求
	_pending_id = -1
	var id := reward_service.request(_enrich(req))
	if state == State.REWARD:
		_pending_id = id


## 给请求补上框架才知道的上下文，网关不用去猜
func _enrich(req: Dictionary) -> Dictionary:
	var out := req.duplicate()
	out["game"] = current_id
	out["game_name"] = str(current.meta().get("name", current_id)) if current != null else current_id

	var slot := int(req.get("slot", -1))
	var target := current.session_for_slot(slot) if current != null else null
	out["player"] = target.display_name() if target != null else ""

	var names: Array = []
	for s in _sessions:
		if s != null:
			names.append(s.display_name())
	out["players"] = names
	return out


func _on_reward_resolved(id: int, req: Dictionary, granted: bool, data: Dictionary) -> void:
	if state != State.REWARD or _reward_req.is_empty():
		return  # 已经不在等了（对局被中止之类），忽略
	if _pending_id != -1 and id != _pending_id:
		return  # 不是我在等的那一单
	if str(req.get("kind", "")) != str(_reward_req.get("kind", "")):
		return
	_resolve_reward(req, granted, data)


func _resolve_reward(req: Dictionary, granted: bool, data: Dictionary) -> void:
	_pending_id = -1
	_reward_req = {}

	var detail := str(data.get("detail", ""))
	print("[flow] 奖励结果：%s → %s%s" % [
		_describe_reward(req), "到手" if granted else "没拿到",
		"（%s）" % detail if not detail.is_empty() else "",
	])

	# 顺序要紧：先让奖励**生效**，再通知外界。
	# 这样监听 reward_settled 的人看到的场面已经是「救回来了 / 道具推过去了」，
	# 而不是一个还没更新的旧状态。
	current.apply_reward(req, granted, data)
	reward_settled.emit(req, granted, data)

	# 答题期间玩家的乱动不算数 —— 清空事件队列，别让等待时的晃动在恢复瞬间变成一串拉拽
	for s in _sessions:
		if s != null:
			s.drain_events()

	if current.is_over():
		_finish_round()
	else:
		_log_timer = 0.0
		_set_state(State.PLAYING)


func _describe_reward(req: Dictionary) -> String:
	var kind := str(req.get("kind", ""))
	var who := ""
	if current != null:
		var s := current.session_for_slot(int(req.get("slot", -1)))
		if s != null:
			who = "给 %s" % s.display_name()
	match kind:
		"revive":
			return "复活 %s —— %s" % [who, str(req.get("reason", ""))]
		"item":
			return "道具「%s」%s —— %s" % [str(req.get("item_id", "")), who, str(req.get("reason", ""))]
	return kind


## 本局还在场上的人数（掉线的槽位已置空）
func _active_count() -> int:
	var n := 0
	for s in _sessions:
		if s != null:
			n += 1
	return n


func _set_state(to: int) -> void:
	if to == state:
		return
	var from := state
	state = to
	state_changed.emit(from, to)


func _cleanup() -> void:
	if current != null:
		current.queue_free()
		current = null
	current_id = ""
	_sessions = []
	_reward_req = {}
	_pending_id = -1


func _player_roster(sessions: Array) -> String:
	var names := PackedStringArray()
	for s: PlayerSession in sessions:
		names.append(s.display_name() if s != null else "空")
	return "、".join(names)


func _slot_roster(sessions: Array) -> String:
	var parts := PackedStringArray()
	for i in sessions.size():
		var s: PlayerSession = sessions[i]
		parts.append("%d=%s" % [i, s.display_name() if s != null else "空"])
	return "  ".join(parts)


func _describe_result(r: Dictionary) -> String:
	if r.is_empty():
		return "（无结算数据）"
	return str(r.get("text", JSON.stringify(r)))
