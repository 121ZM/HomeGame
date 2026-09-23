class_name NetProtocol
extends RefCounted

## 手机 ⇄ 大屏 的 UDP 包协议（v2）。
##
## 与 v1 的区别：加了 type 字段，从此一个 socket 能跑多种包（数据 / 握手 / 道别 / 下行通知），
## 名字这类变长内容不再需要塞进每帧的定长包里。改协议务必同步两端并 +1 VERSION。
##
## 所有包共用 10 字节头，小端序：
##   偏移  类型  字段
##   0     u8    magic      0xA7
##   1     u8    version
##   2     u8    type
##   3     u8    pad        保留，固定 0
##   4     u16   player_id
##   6     u32   seq
##
## 上行（手机 → 大屏）
##   TYPE_DATA  0  头 + gyro 3×f32 + accel 3×f32 + buttons u16 + ts u32  = 40 字节
##   TYPE_HELLO 1  头 + name_len u8 + name utf8(≤24B)                   = 11..35 字节
##   TYPE_BYE   2  头                                                    = 10 字节
##
## 下行（大屏 → 手机）
##   TYPE_FULL  128  头（player_id 置 0）—— 房间已满，别傻等
##
## 手机坐标系（Android 约定）：x 屏幕向右，y 屏幕向上，z 垂直屏幕向外。

const MAGIC := 0xA7
const VERSION := 2
const HEADER_SIZE := 10

const TYPE_DATA := 0
const TYPE_HELLO := 1
const TYPE_BYE := 2
const TYPE_FULL := 128

const DATA_SIZE := 40
const MAX_NAME_BYTES := 24


static func _put_header(buf: StreamPeerBuffer, type: int, player_id: int, seq: int) -> void:
	buf.put_u8(MAGIC)
	buf.put_u8(VERSION)
	buf.put_u8(type)
	buf.put_u8(0)
	buf.put_u16(player_id)
	buf.put_u32(seq)


static func encode_data(player_id: int, seq: int, gyro: Vector3, accel: Vector3,
		buttons: int, timestamp_ms: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	_put_header(buf, TYPE_DATA, player_id, seq)
	buf.put_float(gyro.x)
	buf.put_float(gyro.y)
	buf.put_float(gyro.z)
	buf.put_float(accel.x)
	buf.put_float(accel.y)
	buf.put_float(accel.z)
	buf.put_u16(buttons)
	buf.put_u32(timestamp_ms)
	return buf.data_array


static func encode_hello(player_id: int, player_name: String) -> PackedByteArray:
	var raw := _fit_name(player_name)
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	_put_header(buf, TYPE_HELLO, player_id, 0)
	buf.put_u8(raw.size())
	buf.put_data(raw)
	return buf.data_array


## 把名字裁到 MAX_NAME_BYTES 以内。
## 必须按「字符」回退而不是按字节切 —— 一个汉字占 3 字节，从中间切开会产生
## 非法 UTF-8，对面 get_string_from_utf8() 出来的就是乱码尾巴。
static func _fit_name(player_name: String) -> PackedByteArray:
	var s := player_name
	while s.length() > 0 and s.to_utf8_buffer().size() > MAX_NAME_BYTES:
		s = s.substr(0, s.length() - 1)
	return s.to_utf8_buffer()


static func encode_bye(player_id: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	_put_header(buf, TYPE_BYE, player_id, 0)
	return buf.data_array


static func encode_full() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	_put_header(buf, TYPE_FULL, 0, 0)
	return buf.data_array


## 只解头部，用于路由。解析失败返回空字典。
static func decode_header(packet: PackedByteArray) -> Dictionary:
	if packet.size() < HEADER_SIZE:
		return {}
	if packet[0] != MAGIC or packet[1] != VERSION:
		return {}
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = packet
	buf.seek(2)
	var type := buf.get_u8()
	buf.get_u8()
	var player_id := buf.get_u16()
	var seq := buf.get_u32()
	return {"type": type, "player_id": player_id, "seq": seq}


## 解析传感器数据包；类型不符或长度不足返回空字典。
static func decode_data(packet: PackedByteArray) -> Dictionary:
	if packet.size() < DATA_SIZE:
		return {}
	var head := decode_header(packet)
	if head.is_empty() or head["type"] != TYPE_DATA:
		return {}
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = packet
	buf.seek(HEADER_SIZE)
	var gx := buf.get_float()
	var gy := buf.get_float()
	var gz := buf.get_float()
	var ax := buf.get_float()
	var ay := buf.get_float()
	var az := buf.get_float()
	var buttons := buf.get_u16()
	var ts := buf.get_u32()
	return {
		"player_id": head["player_id"],
		"seq": head["seq"],
		"gyro": Vector3(gx, gy, gz),
		"accel": Vector3(ax, ay, az),
		"buttons": buttons,
		"timestamp_ms": ts,
	}


## 解析握手包，取出玩家名字（UTF-8 截断成合法字符串）。失败返回空字符串。
static func decode_hello(packet: PackedByteArray) -> Dictionary:
	if packet.size() < HEADER_SIZE + 1:
		return {}
	var head := decode_header(packet)
	if head.is_empty() or head["type"] != TYPE_HELLO:
		return {}
	var name_len := packet[HEADER_SIZE]
	var start := HEADER_SIZE + 1
	var end := mini(start + name_len, packet.size())
	var raw := packet.slice(start, end)
	return {"player_id": head["player_id"], "name": raw.get_string_from_utf8()}
