class_name MockRewardGateway
extends RewardGateway

## 开发 / 自检用：不接任何外部程序，直接按策略给答案。
##
## 两个用途：
##   1. 没有真答题程序时先把整条「要奖励 → 挂起 → 生效」的链路跑通
##   2. selfcheck 里把 answer_delay_sec 设成 0，答案在 begin() 里同步返回，
##      完全确定性、不依赖帧率 —— 这是能拿来做回归测试的关键

## 秒。<= 0 时在 begin() 里立刻回答（自检用这种）；> 0 时等这么久再回答
@export var answer_delay_sec: float = 6.0
## grant 全给 / deny 全拒 / alternate 交替给 / timeout 故意不回答
@export var policy: String = "grant"

var _answered_count: int = 0
var _timers: Dictionary = {}


func describe() -> String:
	return "开发用 mock 网关（策略 %s，延迟 %.1fs）" % [policy, answer_delay_sec]


func begin(request_id: int, req: Dictionary) -> void:
	if policy == "timeout":
		print("[reward:mock] 收到「%s」请求，故意不回答（模拟没人管）" % str(req.get("kind", "")))
		return
	if answer_delay_sec <= 0.0:
		_emit_result(request_id)
		return
	_timers[request_id] = answer_delay_sec


func cancel(request_id: int) -> void:
	_timers.erase(request_id)


func _process(delta: float) -> void:
	if _timers.is_empty():
		return
	for id in _timers.keys():
		_timers[id] = float(_timers[id]) - delta
		if float(_timers[id]) <= 0.0:
			_timers.erase(id)
			_emit_result(id)


func _emit_result(request_id: int) -> void:
	var granted := false
	match policy:
		"grant":
			granted = true
		"deny":
			granted = false
		"alternate":
			granted = _answered_count % 2 == 0
		_:
			granted = false
	var detail := "mock 给了" if granted else "mock 不给"
	_answered_count += 1
	print("[reward:mock] 请求 %d → %s" % [request_id, "通过" if granted else "不通过"])
	answered.emit(request_id, granted, {"source": "mock", "detail": detail})
