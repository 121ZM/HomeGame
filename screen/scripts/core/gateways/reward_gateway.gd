class_name RewardGateway
extends Node

## 「看广告 / 答题」的提供方接在这里。
##
## 设计要点：框架**不关心**奖励是看广告换来的、答对题换来的、还是家长审批放行的 ——
## 它只认一个布尔结果 granted。所以下面这些可以随便换着插，玩法层零改动：
##   · 你自己的答题程序（见 http_gateway.gd，走 HTTP + JSON）
##   · 真广告 SDK
##   · 家长审批弹窗
##   · 开发期的 mock（直接给 / 直接拒，见 mock_gateway.gd）
##
## 子类要做的事：实现 begin()，并在有结果时 emit answered()。
## 一个请求**只允许回答一次**；超时、取消、重复回答都由 RewardService 兜底。

## 有结果了。granted = 这次奖励给不给。
## data 可以带 {"detail": "答对第 3 题"} 这类给人看的一句话，会显示在大屏提示里。
signal answered(request_id: int, granted: bool, data: Dictionary)


## 给人看的名字，启动日志和 HUD 会显示，方便一眼确认接的是哪个后端
func describe() -> String:
	return "未命名奖励网关"


## 开始一次「广告 / 出题」。req 的字段见 MiniGame.pending_reward_request()，
## 另外框架会补上 game / game_name / player / players。
func begin(_request_id: int, _req: Dictionary) -> void:
	push_error("[reward] %s 没有实现 begin()" % describe())


## 请求被取消了（超时或对局中止）。后端应该把已经打开的题/广告收掉。
func cancel(_request_id: int) -> void:
	pass
