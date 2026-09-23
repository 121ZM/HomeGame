class_name UdpServer
extends Node

## 网络层：监听局域网 UDP，把数据包变成「玩家会话」。
##
## 职责边界：只管「收包 / 维持会话 / 统计链路」。不解释包的业务含义，
## 也不决定谁是几号槽位 —— 那是玩法层在开局那一刻的事。
##
## 注意：必须绑 0.0.0.0（Godot 里写 "*"），绑 127.0.0.1 只能收到本机包，
## 手机连不上 —— 这是局域网方案最常见的坑。

signal player_joined(session: PlayerSession)
signal player_left(player_id: int)
signal motion_event(player_id: int, event: Dictionary)
signal packet_received(session: PlayerSession)
## 房间已满，已回包告知该地址（UI 层可据此提示）
signal room_full(address: String, port: int)

const DEFAULT_PORT := 8910
const TIMEOUT_MS := 3000
## 被拒过的地址在这个时间窗内不再重复回「已满」。
## 否则一台被拒的手机每帧发包、大屏每帧回包 —— 白白刷屏还占带宽。
const REJECT_COOLDOWN_MS := 2000

## 架构硬上限：同时能接多少台设备。这个数由资源决定（颜色可辨识度 / HUD 布局 /
## 客厅里能看清几个角色），**不由玩法决定**。每种玩法自己的 min/max_players 是
## 另一回事，由玩法层再声明一次。
var max_players: int = 8

var port: int = DEFAULT_PORT
var sessions: Dictionary = {}


var _udp: PacketPeerUDP = null
var _now_ms: int = 0
var _bad_packets: int = 0
var _rejected: int = 0
## "ip:port" -> 冷却截止时间(ms)
var _reject_cooldown: Dictionary = {}


func _ready() -> void:
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(port, "*")
	if err != OK:
		push_error("[net] UDP 绑定失败 端口=%d 错误=%s" % [port, error_string(err)])
		_udp = null
		return
	print("[net] UDP 已监听 0.0.0.0:%d（上限 %d 人）" % [port, max_players])


func _process(_delta: float) -> void:
	if _udp == null:
		return

	_now_ms = Time.get_ticks_msec()

	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var src_port := _udp.get_packet_port()
		_handle_packet(packet, ip, src_port)

	_check_timeouts()


func get_session(player_id: int) -> PlayerSession:
	return sessions.get(player_id)


## 取第一个在线玩家（单人调试场景够用）
func first_session() -> PlayerSession:
	for pid in sessions:
		return sessions[pid]
	return null


## 是否还能再进人
func is_full() -> bool:
	return sessions.size() >= max_players


func stats() -> Dictionary:
	var total_rx := 0
	var total_lost := 0
	for pid in sessions:
		var s: PlayerSession = sessions[pid]
		total_rx += s.packets_received
		total_lost += s.packets_lost
	return {
		"players": sessions.size(),
		"max_players": max_players,
		"received": total_rx,
		"lost": total_lost,
		"bad_packets": _bad_packets,
		"rejected": _rejected,
	}


func _handle_packet(packet: PackedByteArray, ip: String, src_port: int) -> void:
	# 先只解 10 字节头，用它决定这包该走哪条路
	var head := NetProtocol.decode_header(packet)
	if head.is_empty():
		_bad_packets += 1
		return

	var pid: int = head["player_id"]

	match int(head["type"]):
		NetProtocol.TYPE_HELLO:
			_handle_hello(packet, pid, ip, src_port)
		NetProtocol.TYPE_BYE:
			_handle_bye(pid)
		NetProtocol.TYPE_DATA:
			_handle_data(packet, pid, ip, src_port)
		_:
			_bad_packets += 1


func _handle_hello(packet: PackedByteArray, pid: int, ip: String, src_port: int) -> void:
	var d := NetProtocol.decode_hello(packet)
	if d.is_empty():
		_bad_packets += 1
		return

	var existing: PlayerSession = sessions.get(pid)

	# 新面孔 + 房间满 → 明确回一包「已满」，否则手机只会傻等
	if existing == null and is_full():
		_reject(ip, src_port, "player_id=%d" % pid)
		return

	var name: String = str(d["name"]).strip_edges()
	if name.is_empty():
		# 手机没输名字 → 默认分配一个。玩家在手机的设置里改完再发一次 HELLO 就换掉了。
		name = _default_name_for(pid)

	if existing == null:
		var s := PlayerSession.new()
		s.player_id = pid
		s.player_name = name
		s.address = ip
		s.port = src_port
		s.first_seen_ms = _now_ms
		s.last_seen_ms = _now_ms
		sessions[pid] = s
		print("[net] 「%s」已连接 (%s:%d)  在线 %d/%d" % [name, ip, src_port, sessions.size(), max_players])
		player_joined.emit(s)
	else:
		existing.player_name = name
		_touch_address(existing, ip, src_port)
		print("[net] 玩家 %d 名字更新为「%s」" % [pid, name])


func _handle_bye(pid: int) -> void:
	if sessions.erase(pid):
		print("[net] 玩家 %d 主动退出" % pid)
		player_left.emit(pid)


## 给「没报名字」的玩家分配一个默认名字：`PlayerNames` 池里挑一个**还没被占**的。
##
## **排除自己已有的名字**，这样手机重发一次空名 HELLO 不会莫名其妙把自己改名 ——
## 手机端「改名字」的实现就是重发 HELLO，得让空名的那次是幂等的，不然改坏一次就没法回头。
func _default_name_for(pid: int) -> String:
	var taken: Array = []
	for other_pid in sessions:
		if other_pid == pid:
			continue
		taken.append((sessions[other_pid] as PlayerSession).player_name)
	return PlayerNames.pick(taken)


func _handle_data(packet: PackedByteArray, pid: int, ip: String, src_port: int) -> void:
	var d := NetProtocol.decode_data(packet)
	if d.is_empty():
		_bad_packets += 1
		return

	var s: PlayerSession = sessions.get(pid)
	if s == null:
		# 没握手就直接发数据：宽容接入，补一个默认名字。
		# 真机走不到这里，但少了 HELLO 也不该让整条链路哑掉。
		if is_full():
			_reject(ip, src_port, "未握手")
			return
		s = PlayerSession.new()
		s.player_id = pid
		s.player_name = _default_name_for(pid)
		s.address = ip
		s.port = src_port
		s.first_seen_ms = _now_ms
		s.last_seen_ms = _now_ms
		sessions[pid] = s
		print("[net] 玩家 %d 未握手直接发数据，已自动接入「%s」" % [pid, s.player_name])
		player_joined.emit(s)
	else:
		# 换网络（切 WiFi / 重连）时地址会变，跟上
		_touch_address(s, ip, src_port)

	# 序号跳变 → 累计丢包
	var seq: int = d["seq"]
	if s.last_seq >= 0 and seq > s.last_seq + 1:
		s.packets_lost += seq - s.last_seq - 1
	s.last_seq = seq
	s.packets_received += 1
	s.last_seen_ms = _now_ms

	var gyro: Vector3 = d["gyro"]
	var accel: Vector3 = d["accel"]
	s.raw_gyro = gyro
	s.raw_accel = accel
	s.buttons = d["buttons"]

	# 交给输入抽象层做滤波/死区/动作识别。
	# 事件是**入队**不是覆盖 —— 消费方取走前一直留着，见 PlayerSession.drain_events()。
	for e in s.filter.feed(gyro, accel, _now_ms):
		s.push_event(e)
		motion_event.emit(pid, e)

	packet_received.emit(s)


func _touch_address(s: PlayerSession, ip: String, src_port: int) -> void:
	if s.address != ip or s.port != src_port:
		print("[net] 玩家 %d 地址变更 %s:%d -> %s:%d" % [s.player_id, s.address, s.port, ip, src_port])
		s.address = ip
		s.port = src_port


func _reply(ip: String, src_port: int, data: PackedByteArray) -> void:
	if _udp == null:
		return
	_udp.set_dest_address(ip, src_port)
	_udp.put_packet(data)


## 房间已满：回一包 FULL 让对方别再傻等。
## 同一个地址在 REJECT_COOLDOWN_MS 内只回一次 —— 被拒的手机往往还在闷头发包，
## 不加冷却就是「它发多少我回多少」，日志和带宽都白烧。
func _reject(ip: String, src_port: int, why: String) -> void:
	_rejected += 1
	var key := "%s:%d" % [ip, src_port]
	if _now_ms < int(_reject_cooldown.get(key, 0)):
		return
	_reject_cooldown[key] = _now_ms + REJECT_COOLDOWN_MS
	_reply(ip, src_port, NetProtocol.encode_full())
	print("[net] 拒绝 %s（%s）：房间已满 %d/%d" % [key, why, sessions.size(), max_players])
	room_full.emit(ip, src_port)


func _check_timeouts() -> void:
	var dead: Array = []
	for pid in sessions:
		var s: PlayerSession = sessions[pid]
		if _now_ms - s.last_seen_ms > TIMEOUT_MS:
			dead.append(pid)

	for pid in dead:
		sessions.erase(pid)
		print("[net] 玩家 %d 超时离线" % pid)
		player_left.emit(pid)
