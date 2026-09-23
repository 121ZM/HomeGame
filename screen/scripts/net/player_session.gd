class_name PlayerSession
extends RefCounted

## 一个已连接玩家的会话状态。
## 持有该玩家的原始读数、滤波后状态、以及链路质量统计。
## [member filter] 属于输入抽象层，挂在会话上是为了让每个玩家的滤波/零点状态天然隔离。

var player_id: int = -1
var player_name: String = ""
var address: String = ""
var port: int = 0

## 游戏槽位（0..N-1）。由玩法层在「开始游戏那一刻」分配，网络层不关心它的含义。
var slot: int = -1

## 链路统计
var packets_received: int = 0
var packets_lost: int = 0
var last_seq: int = -1
var last_seen_ms: int = 0
var first_seen_ms: int = 0

## 最新原始读数
var raw_gyro: Vector3 = Vector3.ZERO
var raw_accel: Vector3 = Vector3(0.0, 9.81, 0.0)
var buttons: int = 0

## 待消费的离散事件队列（由 UdpServer 追加入队，玩法层用 drain_events() 取走）
var events: Array = []

## 队列上限。没人消费时（比如大厅里没开游戏）不能让事件无限堆积。
const MAX_PENDING_EVENTS := 8

var filter: MotionFilter = MotionFilter.new()


## 取出并清空累积的事件。
##
## **必须用这个而不是直接读 events**，原因是帧率和发包率不是一回事：
## 无头模式下帧率可能几百 Hz，而手机 60Hz 发包 —— 一次挥动产生的事件会
## 在好几帧里一直躺在 events 里，谁直接读就会把它重复计数好几次。
## 「取走即清空」把语义钉死成「自上次 tick 以来发生的事件」，这才是玩法层要的。
func drain_events() -> Array:
	if events.is_empty():
		return []
	var out := events
	events = []
	return out


func push_event(e: Dictionary) -> void:
	if events.size() >= MAX_PENDING_EVENTS:
		events.pop_front()
	events.append(e)


func tilt() -> Vector2:
	return filter.tilt


## 当前蹦劲（0..1）。玩法读它当**连续力量** —— 详见 `MotionFilter.jump`：
## 蹦得越密，这个值长期越接近 1；蹦一次就停，它衰减回 0。
func jump() -> float:
	return filter.jump


## 显示用的名字：没握手就用「玩家 id」兜底
func display_name() -> String:
	return player_name if not player_name.is_empty() else "玩家 %d" % player_id


func lost_ratio() -> float:
	var total := packets_received + packets_lost
	return 0.0 if total == 0 else float(packets_lost) / float(total)


func summary() -> String:
	return "%s @%s:%d  收 %d 丢 %d (%.1f%%)  倾斜(%.2f, %.2f)" % [
		display_name(), address, port,
		packets_received, packets_lost, lost_ratio() * 100.0,
		filter.tilt.x, filter.tilt.y,
	]
