class_name MotionFilter
extends RefCounted

## 输入抽象层：把手机原始传感器读数，归一化成玩法层能直接用的量。
##
## 做三件事（缺一个玩法都会很难调）：
##   1. 低通滤波       —— 去掉传感器高频抖动
##   2. 死区           —— 手不可能完全静止，小信号一律归零
##   3. 动作识别       —— 把「往上蹦」这类连续曲线，归一化成**连续强度** + 一个瞬时事件
##
## 倾斜量以「握持零点」为基准，玩家按校准键时把当前姿态记为零。
## 这是首版近似（小角度线性化）；要更稳可以后续换成互补滤波 + 四元数姿态解算。

## 低通系数，0..1，越大跟得越快、越抖
const GYRO_ALPHA := 0.35
const ACCEL_ALPHA := 0.25

## 倾斜死区与灵敏度（0.5 表示偏差 0.5 个单位到满量程）
const TILT_DEADZONE := 0.06
const TILT_GAIN := 2.0

## 往上蹦检测：`accel.y` 高出它自己慢速均值的幅度 = 「这一下蹦得多猛」。
##
## **只认向上**（`accel.y` 的冲高），向下甩 / 左右晃都不算 ——
## 这正是「往上蹦」和「来回挥」的区别。判据拿 y 轴自己的慢速均值做基准，
## 所以手机怎么拿都行：静止时 y 的基线会自己稳定下来，不用手动标定重力。
const JUMP_THRESHOLD := 9.0
## 两次蹦的最小间隔 —— 只用来选出「刚蹦了一下」这个瞬时事件（音效 / 振动用），
## **不是力量来源**：力量是下面那个连续强度 `jump`。
const JUMP_COOLDOWN_MS := 320
## `accel.y` 慢速均值的**向下**跟踪速度（握姿一变就贴上去）。
const JUMP_EMA_ALPHA := 0.04
## `accel.y` 慢速均值的**向上**跟踪速度。必须远慢于向下。
##
## 为什么：蹦的冲量和它的尾巴**永远在基线之上**。如果基线向上也跟得快，密蹦时每一下
## 的尾巴都会把基线一点点抬上去，冲量 `accel.y − 基线` 越来越小 —— 最后冲不过阈值，
## `jump` 一直贴地，「越密越强」直接反成「越密越弱」。这不是理论担忧：框架自检组 [3]
## 用「同冲量、不同密度」的合成波形抓到了（密 0.00 vs 疏 0.11）。
## 向上给慢速，基线在整局里只慢慢抬一点点（40 秒约 +2.5），冲量始终有足够的头顶空间。
const JUMP_EMA_RISE := 0.0005
## 强度衰减：不蹦的时候每秒掉多少。**这就是「越密越强」的来源** ——
## 蹦得密 → 强度长期维持在高位；蹦一次就停 → 很快掉回 0，拉不动。
const JUMP_DECAY_PER_SEC := 1.6
## dt 上限：首个包没有上一帧；网络抖动时也不该让一次衰减吞掉太多时间
const MAX_DT_SEC := 0.25

## 滤波后的状态
var gyro: Vector3 = Vector3.ZERO
var accel: Vector3 = Vector3(0.0, 9.81, 0.0)
var tilt: Vector2 = Vector2.ZERO
## 当前这一下的蹦劲，0..1。检测到向上冲量就冲高，没有就按时间衰减。
## 玩法读它当**连续力量**（如拔河：`s.jump()`），而不是读离散事件。
var jump: float = 0.0

var _zero_dir: Vector3 = Vector3(0.0, 1.0, 0.0)
## `accel.y` 的慢速均值 —— 蹦的判据是「高出它多少」，不是绝对阈值
var _accel_y_ema: float = 9.81
var _has_data: bool = false
var _last_jump_ms: int = -999999
## 上一帧时间戳，用来算 dt（feed 只给 now_ms，dt 得自己算）
var _last_ms: int = -1


func reset() -> void:
	gyro = Vector3.ZERO
	accel = Vector3(0.0, 9.81, 0.0)
	tilt = Vector2.ZERO
	jump = 0.0
	_zero_dir = Vector3(0.0, 1.0, 0.0)
	_accel_y_ema = 9.81
	_has_data = false
	_last_jump_ms = -999999
	_last_ms = -1


## 把当前姿态记为零点。玩家怎么握都行，按下校准后以那一刻为基准。
func calibrate() -> void:
	if accel.length() > 0.1:
		_zero_dir = accel.normalized()


## 喂入一帧原始数据。[param now_ms] 用统一时钟（Time.get_ticks_msec()）。
## 返回本帧产生的离散事件数组，每项形如 {"type": "jump", "power": 0.0..1.0}。
##
## 注意：**力量不来自这个事件**，来自连续强度 `jump`。
## 事件只是「刚蹦了一下」的瞬时信号（受冷却时间限制），玩法按需消费。
func feed(raw_gyro: Vector3, raw_accel: Vector3, now_ms: int) -> Array:
	var events: Array = []
	var dt := _tick_dt(now_ms)

	# --- 1. 低通滤波 ---
	if _has_data:
		gyro = gyro.lerp(raw_gyro, GYRO_ALPHA)
		accel = accel.lerp(raw_accel, ACCEL_ALPHA)
	else:
		gyro = raw_gyro
		accel = raw_accel
		_has_data = true

	# --- 2. 倾斜：相对零点的偏差，投影到手机的 x / z 轴 ---
	var n := accel.normalized()
	var delta := n - _zero_dir
	var t := Vector2(delta.x * TILT_GAIN, delta.z * TILT_GAIN)
	t.x = 0.0 if absf(t.x) < TILT_DEADZONE else clampf(t.x, -1.0, 1.0)
	t.y = 0.0 if absf(t.y) < TILT_DEADZONE else clampf(t.y, -1.0, 1.0)
	tilt = t

	# --- 3. 往上蹦：accel.y 对慢速均值的**向上**冲击 ---
	var impulse := accel.y - _accel_y_ema
	if impulse > JUMP_THRESHOLD:
		# 冲高取 max、不是直接赋值 —— 连着蹦时中间帧不能把它拉低
		jump = maxf(jump, clampf(impulse / (JUMP_THRESHOLD * 2.0), 0.0, 1.0))
		# 冲高期间**不更新基线** —— 它是「高出基线多少」的基准，被冲高自己带跑就没意义了
		if now_ms - _last_jump_ms > JUMP_COOLDOWN_MS:
			_last_jump_ms = now_ms
			events.append({"type": "jump", "power": jump})
	else:
		# 基线：向下跟得快（握姿一变就贴上去），向上跟得极慢（不被蹦的尾巴一点点抬走）。
		# 这两条不对称，正是「密蹦也能一直有冲量」的关键，理由见 JUMP_EMA_RISE。
		var alpha := JUMP_EMA_RISE if impulse > 0.0 else JUMP_EMA_ALPHA
		_accel_y_ema = lerpf(_accel_y_ema, accel.y, alpha)
		# 没冲量就按时间衰减：蹦一次就停 → 强度很快掉回 0
		jump = maxf(jump - JUMP_DECAY_PER_SEC * dt, 0.0)

	return events


## 从 now_ms 算到上一帧的 dt。
## 首个包返回 0（绝不拿 0 当除数、也不让它跳成一个巨大的 dt）。
func _tick_dt(now_ms: int) -> float:
	if _last_ms < 0:
		_last_ms = now_ms
		return 0.0
	var dt := clampf(float(now_ms - _last_ms) / 1000.0, 0.0, MAX_DT_SEC)
	_last_ms = now_ms
	return dt
