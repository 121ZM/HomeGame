class_name HttpRewardGateway
extends RewardGateway

## 接你自己的答题程序（将来也可以换成真广告服务）。
##
## 走 HTTP + JSON：任何语言都能实现，跑在同一台 PC、平板、手机上都可以。
##
## ══════ 接口约定（两个端点）═══════════════════════════════════
## 1) 开一单
##    POST  {base}/reward/open
##    Content-Type: application/json
##    body {
##      "request_id": 1,          # 大屏内部的请求号，回包原样带回来最好
##      "kind": "revive",         # revive（复活）| item（道具）
##      "item_id": "",            # kind=item 时有值，如 "big_pull"
##      "slot": 0,                # 玩家槽位号
##      "player": "孙悟空",        # 玩家名字（大屏上显示的那个；没自己起名就是默认分配的）
##      "players": ["孙悟空","猪八戒"], # 本局全部玩家
##      "game": "tug",            # 玩法 id
##      "game_name": "拔河",
##      "reason": "绳子就要被拔过线了 —— 答对一题，把它拉回中线"
##    }
##    回     {"ticket": "abc123"}                       ← 题目要慢慢出/广告要播
##       或  {"granted": true, "detail": "答对第 3 题"}  ← 已经能立刻判定
##
## 2) 问结果（大屏每 poll_interval_sec 秒轮询一次）
##    GET   {base}/reward/poll?ticket=abc123
##    回    {"state": "pending"}                        ← 还在答题/播广告
##       或  {"state": "granted", "detail": "答对第 3 题"}
##       或  {"state": "denied",  "detail": "答错了：has → have"}
##
## ══════ 规矩 ══════════════════════════════════════════════
## · detail 是给人看的一句话，会直接显示在大屏提示里，写中文没问题。
## · 大屏最多等 RewardService.timeout_sec 秒（默认 45），到点按「拿不到」算，
##   并且会调 cancel()。**答题程序允许比这慢**，游戏是在等，玩家在看大屏倒计时。
## · 单次轮询失败不算数，下一轮会重试；只有超时才判负。
## · 跨设备时答题程序必须监听 0.0.0.0，绑 127.0.0.1 手机连不上（局域网方案的经典坑）。
## · 这个后端**不负责显示题目** —— 题目显示在你自己的程序里，大屏只显示一句
##   「答题中… 答对可得复活」的等待提示。

## 答题程序地址。主程序可用 --reward-url= 覆盖。
@export var base_url: String = "http://127.0.0.1:8787"
## 轮询间隔（秒）。出题是给人做的，0.4 秒足够灵敏也不费流量。
@export var poll_interval_sec: float = 0.4
## 单次 HTTP 请求的超时（秒）。注意这**不是**答题时限，答题时限在 RewardService。
@export var request_timeout_sec: float = 10.0

## request_id -> {"ticket": String, "poll_timer": float, "busy": bool}
var _open: Dictionary = {}


func describe() -> String:
	return "HTTP 答题程序网关 → %s" % base_url


func begin(request_id: int, req: Dictionary) -> void:
	_open[request_id] = {"ticket": "", "poll_timer": 0.0, "busy": false}

	var http := _new_http()
	http.request_completed.connect(_on_open_done.bind(request_id, http))
	var err := http.request(
		"%s/reward/open" % base_url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(build_payload(request_id, req))
	)
	if err != OK:
		_fail(request_id, "答题程序连不上：%s" % error_string(err))


## 发给答题程序的 JSON。单独抽出来是为了能被自检断言（契约变了测试会报）。
func build_payload(request_id: int, req: Dictionary) -> Dictionary:
	return {
		"request_id": request_id,
		"kind": str(req.get("kind", "")),
		"item_id": str(req.get("item_id", "")),
		"slot": int(req.get("slot", -1)),
		"player": str(req.get("player", "")),
		"players": req.get("players", []),
		"game": str(req.get("game", "")),
		"game_name": str(req.get("game_name", "")),
		"reason": str(req.get("reason", "")),
	}


func cancel(request_id: int) -> void:
	_open.erase(request_id)
	# 顺手告诉答题程序把它收掉，不去猜对方有没有实现
	var http := _new_http()
	http.request("%s/reward/cancel?request_id=%d" % [base_url, request_id],
		[], HTTPClient.METHOD_POST)


func _process(delta: float) -> void:
	if _open.is_empty():
		return
	for id in _open.keys():
		var e: Dictionary = _open[id]
		if str(e["ticket"]).is_empty() or bool(e["busy"]):
			continue
		e["poll_timer"] = float(e["poll_timer"]) - delta
		if float(e["poll_timer"]) <= 0.0:
			e["poll_timer"] = poll_interval_sec
			e["busy"] = true
			_poll(id, str(e["ticket"]))


func _new_http() -> HTTPRequest:
	var http := HTTPRequest.new()
	http.timeout = request_timeout_sec
	add_child(http)
	return http


func _poll(request_id: int, ticket: String) -> void:
	var http := _new_http()
	http.request_completed.connect(_on_poll_done.bind(request_id, http))
	var url := "%s/reward/poll?ticket=%s" % [base_url, ticket.uri_encode()]
	var err := http.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		_release(request_id)
		http.queue_free()


func _on_open_done(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, request_id: int, http: HTTPRequest) -> void:
	http.queue_free()
	if not _open.has(request_id):
		return
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_fail(request_id, "答题程序没回应（HTTP %d）" % code)
		return

	var json := _parse(body)
	# 允许答题程序直接给结论，省掉一轮轮询
	if json.has("granted"):
		_finish(request_id, bool(json["granted"]), str(json.get("detail", "")))
		return

	var ticket := str(json.get("ticket", ""))
	if ticket.is_empty():
		_fail(request_id, "答题程序的回包既没有 granted 也没有 ticket")
		return

	var e: Dictionary = _open[request_id]
	e["ticket"] = ticket
	e["poll_timer"] = 0.0        # 立刻开始第一轮
	e["busy"] = false
	print("[reward:http] 已开单，ticket=%s，开始等结果" % ticket)


func _on_poll_done(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, request_id: int, http: HTTPRequest) -> void:
	http.queue_free()
	if not _open.has(request_id):
		return
	_release(request_id)

	# 单次轮询失败不判负 —— 下一轮重试，真正的时限由 RewardService 兜底
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return

	var json := _parse(body)
	match str(json.get("state", "")):
		"granted":
			_finish(request_id, true, str(json.get("detail", "")))
		"denied":
			_finish(request_id, false, str(json.get("detail", "")))
		_:
			pass  # pending，继续等


func _release(request_id: int) -> void:
	if _open.has(request_id):
		_open[request_id]["busy"] = false


func _finish(request_id: int, granted: bool, detail: String) -> void:
	if not _open.has(request_id):
		return
	_open.erase(request_id)
	print("[reward:http] 请求 %d → %s%s" % [
		request_id, "通过" if granted else "不通过",
		"（%s）" % detail if not detail.is_empty() else "",
	])
	answered.emit(request_id, granted, {"source": "http", "detail": detail})


func _fail(request_id: int, why: String) -> void:
	if not _open.has(request_id):
		return
	_open.erase(request_id)
	push_warning("[reward:http] %s" % why)
	answered.emit(request_id, false, {"source": "http", "detail": why})


func _parse(body: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed
	return {}
