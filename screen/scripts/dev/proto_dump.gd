extends Node

## 一次性小工具：把 NetProtocol 的编码结果打成十六进制。
##
## **用途**：给手机端实现者做「字节级对拍」——
## 手机端编出来的字节串必须和这里一模一样，否则大屏解不出来或数值乱套。
##
## 跑法：`godot --headless --path . res://tools/proto_dump.tscn`
##
## 对拍清单与失败症状见 `docs/controller-protocol.md`；
## 电脑端校验器（不用装任何手机 SDK）见 `tools/proto_check.py`。

func _ready() -> void:
	print("=== NetProtocol 编码参考字节（v%d）===" % NetProtocol.VERSION)

	var static_pkt := NetProtocol.encode_data(
			1, 0, Vector3.ZERO, Vector3(0.0, 9.81, 0.0), 0, 1234567)
	print("DATA_STATIC %s len=%d" % [_h(static_pkt), static_pkt.size()])

	var jump_pkt := NetProtocol.encode_data(
			1, 1, Vector3(0.0, 0.0, 5.0), Vector3(0.0, 35.81, 0.0), 0, 1234583)
	print("DATA_JUMP   %s len=%d" % [_h(jump_pkt), jump_pkt.size()])

	var hello_3 := NetProtocol.encode_hello(1, "孙悟空")
	print("HELLO_3     %s len=%d" % [_h(hello_3), hello_3.size()])

	var hello_8 := NetProtocol.encode_hello(1, "一二三四五六七八")
	print("HELLO_8     %s len=%d" % [_h(hello_8), hello_8.size()])

	# 9 个字超 24 字节，应被截成前 8 个 —— 结果必须与 HELLO_8 逐字节相同
	var hello_9 := NetProtocol.encode_hello(1, "一二三四五六七八九")
	print("HELLO_9     %s len=%d" % [_h(hello_9), hello_9.size()])
	print("HELLO_9_IS_TRUNCATED %s" % ("true" if hello_9 == hello_8 else "false"))

	var bye_pkt := NetProtocol.encode_bye(1)
	print("BYE         %s len=%d" % [_h(bye_pkt), bye_pkt.size()])

	# 自校验：把刚编出来的 DATA 再解回去，确认 round-trip 无损。
	# 这一步证明「编码器与解码器对同一份字节的理解一致」——
	# 手机端写完后也该做同样的自查。
	var back := NetProtocol.decode_data(static_pkt)
	if back.is_empty():
		print("ROUNDTRIP   FAIL 解不回来")
	else:
		var a: Vector3 = back["accel"]
		print("ROUNDTRIP   OK accel=(%.3f, %.3f, %.3f) pid=%d seq=%d"
				% [a.x, a.y, a.z, back["player_id"], back["seq"]])

	# 手机端最容易错的字节序，这里给一次性「怎么读」的说明。
	print("")
	print("★ 关键校验点：偏移 26..29 是 accel.y 的小端 float32")
	print("  静止 9.81 → %s" % _h(static_pkt.slice(26, 30)))
	print("  若你拿到的是这个的倒序，就是字节序写反了")

	get_tree().quit(0)


func _h(b: PackedByteArray) -> String:
	var parts := PackedStringArray()
	for x in b:
		parts.append("%02X" % x)
	return " ".join(parts)
