class_name RewardService
extends Node

## 奖励服务的统一出入口。
##
## 分工：玩法说「我要什么」，网关说「给不给」，这里负责转发 + 兜底超时。
## 它不认识广告、也不认识题目 —— 只知道有一次请求，最后会有一个布尔结果。
##
## 超时是必须的：网关可能永远不回答（答题程序崩了、网络断了、玩家跑掉了），
## 没有超时兜底，对局会永远卡在「等奖励」上出不来。

signal resolved(request_id: int, req: Dictionary, granted: bool, data: Dictionary)

## 真正去出题/播广告的那个东西。换后端 = 换这一个对象。
var gateway: RewardGateway = null
## 一次奖励最多等多久。到点按「拿不到」处理。
var timeout_sec: float = 45.0

var _next_id: int = 1
## request_id -> {"req": Dictionary, "age": float}
var _open: Dictionary = {}


func set_gateway(gw: RewardGateway) -> void:
	if gateway != null and gateway.answered.is_connected(_on_gateway_answered):
		gateway.answered.disconnect(_on_gateway_answered)
	gateway = gw
	if gateway != null and not gateway.answered.is_connected(_on_gateway_answered):
		gateway.answered.connect(_on_gateway_answered)


func is_busy() -> bool:
	return not _open.is_empty()


func pending_count() -> int:
	return _open.size()


## 发一次请求。返回请求号；没有配网关时返回 0。
func request(req: Dictionary) -> int:
	if gateway == null:
		push_error("[reward] 没配网关，请求被拒")
		return 0
	var id := _next_id
	_next_id += 1
	_open[id] = {"req": req, "age": 0.0}
	# 注意：begin() 可能**同步**就把答案 emit 回来（mock 延迟为 0 时就是这样），
	# 所以 _open 必须先填好再调 begin()，否则那次的回答会被当成「陌生人」丢掉。
	gateway.begin(id, req)
	return id


## 外部直接回调。答题程序跟大屏跑在同一个进程里时用这个，省掉 HTTP 那一圈。
func notify(request_id: int, granted: bool, data: Dictionary = {}) -> void:
	_on_gateway_answered(request_id, granted, data)


func cancel_all() -> void:
	for id in _open.keys():
		if gateway != null:
			gateway.cancel(id)
	_open.clear()


func _process(delta: float) -> void:
	if _open.is_empty():
		return
	var timed_out: Array = []
	for id in _open.keys():
		_open[id]["age"] = float(_open[id]["age"]) + delta
		if float(_open[id]["age"]) >= timeout_sec:
			timed_out.append(id)
	for id in timed_out:
		var req: Dictionary = _open[id]["req"]
		_open.erase(id)
		if gateway != null:
			gateway.cancel(id)
		print("[reward] 请求 %d 超时（等满 %.0f 秒）→ 按「拿不到」处理" % [id, timeout_sec])
		resolved.emit(id, req, false, {"reason": "timeout", "detail": "等太久了，这次不算"})


func _on_gateway_answered(request_id: int, granted: bool, data: Dictionary) -> void:
	if not _open.has(request_id):
		return  # 已经超时或取消了，迟到的回答直接丢
	var req: Dictionary = _open[request_id]["req"]
	_open.erase(request_id)
	resolved.emit(request_id, req, granted, data)
