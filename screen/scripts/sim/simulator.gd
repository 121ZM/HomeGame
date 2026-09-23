class_name PhoneSimulator
extends Node

## 模拟手机端：按固定频率向大屏发送假的传感器数据。
##
## 用途：没有真机时验证整条链路（网络层 → 输入抽象层 → 可视化）。
## 它就是「真实手机端的第一版实现」—— 改 target_host 指向大屏 IP，行为一致。
##
## 造的数据刻意模仿「竖持手机当手柄」：
##   静止    accel ≈ (0, 9.81, 0)，gyro ≈ 0
##   左右倾  正弦摆动，体现在 accel.x
##   前后倾  低频正弦，体现在 accel.z
##   往上蹦  每 jump_period 秒叠加一次衰减脉冲（accel.y 冲高）
##   噪声    ±NOISE 的随机扰动 —— 故意加的，用来验证滤波是不是真在起作用
##
## 报文序列：先发一包 HELLO（带名字），再开始发 DATA，退出时补一包 BYE。

@export var target_host: String = "127.0.0.1"
@export var target_port: int = 8910
@export var player_id: int = 1
@export var player_name: String = ""
## 故意**不报名字**，让大屏走「默认分配一个」那条路。
## 平时用不到（真机总有名字），但「没输名字也该有个名字」这个功能得能验证。
@export var anonymous: bool = false
@export var rate_hz: float = 60.0
@export var enable_jump: bool = true
@export var enable_noise: bool = true
## 多久往上蹦一次。多人自测时给不同的人不同节奏，否则双方永远势均力敌。
@export var jump_period: float = 1.2
## 绑一个本地端口收大屏的回包（目前只有「房间已满」）。关掉也无妨，只是看不到提示。
@export var listen_for_reply: bool = true

const JUMP_DECAY := 6.0
const NOISE := 0.15
## 收到「房间已满」后安静这么久，然后重新握手试一次（真机就是这个行为）
const FULL_BACKOFF := 3.0

var _udp: PacketPeerUDP = null
var _seq: int = 0
var _elapsed: float = 0.0
var _accum: float = 0.0
var _jump_t: float = 999.0
var _next_jump: float = 0.0
var _rng := RandomNumberGenerator.new()
## 被拒后的静默截止时刻（_elapsed 秒），< 0 表示没在被拒状态
var _blocked_until: float = -1.0


func _ready() -> void:
	_rng.randomize()

	# 允许命令行覆盖，方便双进程/多人测试：
	#   godot --headless --path screen res://tools/simulator.tscn -- --name=孙悟空 --pid=2 --host=192.168.1.10
	#   godot --headless --path screen res://tools/simulator.tscn -- --anon --pid=2   # 不报名，试默认分配
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			player_name = a.get_slice("=", 1)
		elif a == "--anon":
			anonymous = true
		elif a.begins_with("--pid="):
			player_id = int(a.get_slice("=", 1))
		elif a.begins_with("--host="):
			target_host = a.get_slice("=", 1)
		elif a.begins_with("--period="):
			jump_period = maxf(0.3, float(a.get_slice("=", 1)))

	if player_name.is_empty() and not anonymous:
		# 单独跑这个场景（不经过大屏的 --simulate）时也要有个像样的名字，
		# 别显示成「模拟玩家 2」—— 真机验证时大屏上要能认出是谁。
		player_name = PlayerNames.at(player_id - 1)
	_next_jump = jump_period

	_udp = PacketPeerUDP.new()
	if listen_for_reply:
		var err := _udp.bind(0, "*")
		if err != OK:
			push_warning("[sim] 本地端口绑定失败（收不到回包）：%s" % error_string(err))

	print("[sim] 「%s」player=%d -> %s:%d @ %.0fHz，每 %.1fs 往上蹦一次" % [
		_label(), player_id, target_host, target_port, rate_hz, jump_period,
	])
	_send_hello()


## 日志里怎么称呼自己。不报名时名字是空的，直接打出来会是「」—— 看不出那是故意的，
## 后面接一句「大屏会给你分一个」才对得上。
func _label() -> String:
	return player_name if not player_name.is_empty() else "不报名（等大屏分配）"


func _exit_tree() -> void:
	# 正常退出时礼貌地道个别，省得大屏等 3 秒超时
	if _udp != null:
		_udp.set_dest_address(target_host, target_port)
		_udp.put_packet(NetProtocol.encode_bye(player_id))
		print("[sim] 已发送 BYE")


func _process(delta: float) -> void:
	_drain_replies()

	_elapsed += delta

	# 被拒状态：先闭嘴，静默期满再重新握手
	if _blocked_until > 0.0:
		if _elapsed >= _blocked_until:
			_blocked_until = -1.0
			print("[sim] 静默期满，重试握手…")
			_send_hello()
		return

	if enable_jump and _elapsed >= _next_jump:
		_jump_t = 0.0
		_next_jump = _elapsed + jump_period
	_jump_t += delta

	var interval := 1.0 / maxf(rate_hz, 1.0)
	_accum += delta
	while _accum >= interval:
		_accum -= interval
		_send_one()


func _send_hello() -> void:
	_udp.set_dest_address(target_host, target_port)
	var err := _udp.put_packet(NetProtocol.encode_hello(player_id, player_name))
	if err != OK:
		push_warning("[sim] HELLO 发送失败：%s" % error_string(err))
	else:
		print("[sim] 已发送 HELLO：%s" % _label())


func _drain_replies() -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		var head := NetProtocol.decode_header(packet)
		if head.is_empty():
			continue
		if int(head["type"]) == NetProtocol.TYPE_FULL:
			if _blocked_until < 0.0:
				push_warning("[sim] 大屏回：房间已满，静默 %.0f 秒后重试" % FULL_BACKOFF)
				print("[sim] !!! 房间已满 !!! 静默 %.0f 秒" % FULL_BACKOFF)
			_blocked_until = _elapsed + FULL_BACKOFF


func _send_one() -> void:
	var accel := Vector3(
		sin(_elapsed * 1.7) * 3.2,
		9.81,
		cos(_elapsed * 0.9) * 2.1
	)
	var gyro := Vector3(0.0, 0.0, cos(_elapsed * 1.7) * 0.9)

	if enable_jump and _jump_t < 1.0:
		var p := exp(-_jump_t * JUMP_DECAY)
		accel.y += 26.0 * p
		gyro.z += 5.0 * p

	if enable_noise:
		accel += Vector3(
			_rng.randf_range(-NOISE, NOISE),
			_rng.randf_range(-NOISE, NOISE),
			_rng.randf_range(-NOISE, NOISE)
		)

	_udp.set_dest_address(target_host, target_port)
	var err := _udp.put_packet(NetProtocol.encode_data(
		player_id, _seq, gyro, accel, 0, Time.get_ticks_msec()
	))
	if err != OK:
		push_warning("[sim] 发送失败：%s" % error_string(err))
	_seq += 1
