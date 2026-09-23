#!/usr/bin/env python3
"""手机端协议编码校验器 —— 拿去做「字节级对照」，不用上真机。

用法：
    # 1) 打印参考字节（拿去跟你的实现对比）
    python3 tools/proto_check.py encode

    # 2) 校验你生成的十六进制串
    python3 tools/proto_check.py verify c3f51c41...

    # 3) 起一个假的「大屏接收端」，让真手机直接发过来看
    python3 tools/proto_check.py listen

为什么需要它：协议里两个坑（小端字节序、坐标轴上方向）写错**不会报错**，
只会让数值变 NaN 或方向反向，必须靠字节对照才能第一时间发现。

权威定义见 screen/scripts/net/net_protocol.gd，对接文档见 docs/controller-protocol.md。
"""

import argparse
import socket
import struct
import sys

MAGIC = 0xA7
VERSION = 2
HEADER_SIZE = 10

TYPE_DATA = 0
TYPE_HELLO = 1
TYPE_BYE = 2
TYPE_FULL = 128

DATA_SIZE = 40
MAX_NAME_BYTES = 24


def put_header(pkt_type: int, player_id: int, seq: int) -> bytes:
    """10 字节公共头。'<BBBBHI' = 小端 + u8/u8/u8/u8/u16/u32。"""
    return struct.pack("<BBBBHI", MAGIC, VERSION, pkt_type, 0, player_id, seq)


def encode_data(player_id: int, seq: int, gyro, accel, buttons: int, ts_ms: int) -> bytes:
    """40 字节传感器包。"""
    if not (0 <= buttons <= 0xFFFF):
        raise ValueError(f"buttons 超出 u16 范围: {buttons}")
    body = struct.pack("<6fHI", gyro[0], gyro[1], gyro[2],
                       accel[0], accel[1], accel[2], buttons, ts_ms & 0xFFFFFFFF)
    pkt = put_header(TYPE_DATA, player_id, seq) + body
    assert len(pkt) == DATA_SIZE, f"DATA 包长度应为 {DATA_SIZE}，实际 {len(pkt)}"
    return pkt


def fit_name(name: str) -> bytes:
    """按「字符」回退到 MAX_NAME_BYTES 以内。

    必须逐字符删，不能按字节切 —— 汉字 3 字节，切中间产生非法 UTF-8，
    大屏 get_string_from_utf8() 会解出乱码尾巴。
    """
    while name and len(name.encode("utf-8")) > MAX_NAME_BYTES:
        name = name[:-1]
    return name.encode("utf-8")


def encode_hello(player_id: int, name: str) -> bytes:
    raw = fit_name(name)
    return put_header(TYPE_HELLO, player_id, 0) + bytes([len(raw)]) + raw


def encode_bye(player_id: int) -> bytes:
    return put_header(TYPE_BYE, player_id, 0)


def hexs(b: bytes) -> str:
    return " ".join(f"{x:02X}" for x in b)


def decode_header(pkt: bytes):
    if len(pkt) < HEADER_SIZE:
        return None
    magic, ver, ptype, _pad, pid, seq = struct.unpack("<BBBBHI", pkt[:HEADER_SIZE])
    if magic != MAGIC or ver != VERSION:
        return None
    return {"type": ptype, "player_id": pid, "seq": seq}


def decode_data(pkt: bytes):
    """返回 (gyro, accel, buttons, ts)。等价于 Godot 的 decode_data()。"""
    if len(pkt) < DATA_SIZE:
        return None
    head = decode_header(pkt)
    if not head or head["type"] != TYPE_DATA:
        return None
    gx, gy, gz, ax, ay, az, buttons, ts = struct.unpack("<6fHI", pkt[HEADER_SIZE:DATA_SIZE])
    return (gx, gy, gz), (ax, ay, az), buttons, ts


# ---------------------------------------------------------------- 子命令

def cmd_encode(_args) -> int:
    print("=" * 66)
    print("参考字节（拿去和你的实现逐字节对照）")
    print("=" * 66)

    # --- 竖持静止
    pkt = encode_data(player_id=1, seq=0, gyro=(0.0, 0.0, 0.0),
                      accel=(0.0, 9.81, 0.0), buttons=0, ts_ms=1234567)
    print("\n[DATA] 竖持静止  pid=1 seq=0 accel=(0, 9.81, 0)")
    print(f"  {hexs(pkt)}")
    print(f"  长度 {len(pkt)}（应为 {DATA_SIZE}）")
    print("\n  ★ 关键校验点：accel.y=9.81 的 4 字节在偏移 26..29")
    print(f"    偏移 26-29 = {hexs(pkt[26:30])}   期望 C3 F5 1C 41")
    print("    如果你拿到 41 1C F5 C3 → 字节序写反了（改成小端）")

    # --- 向上冲（模拟蹦）
    jump_y = 9.81 + 26.0
    pkt2 = encode_data(player_id=1, seq=1, gyro=(0.0, 0.0, 5.0),
                       accel=(0.0, jump_y, 0.0), buttons=0, ts_ms=1234583)
    print(f"\n[DATA] 向上冲（蹦）  accel.y = 9.81+26 = {jump_y}")
    print(f"  {hexs(pkt2)}")
    print(f"  偏移 26-29 = {hexs(pkt2[26:30])}   （这是 accel.y 的小端 float32）")
    print(f"  对照：向上冲时偏移 26 的值应明显大于静止时的 {pkt[26]:02X}")

    # --- HELLO
    for nm in ("孙悟空", "一二三四五六七八", "一二三四五六七八九"):
        h = encode_hello(player_id=1, name=nm)
        print(f"\n[HELLO] 名字「{nm}」({len(nm)} 字 → {len(nm.encode('utf-8'))} 字节)")
        print(f"  {hexs(h)}")
        print(f"  长度 {len(h)}，name_len 字段 = {h[10]}")

    # --- BYE
    b = encode_bye(player_id=1)
    print(f"\n[BYE]  {hexs(b)}   长度 {len(b)}（应为 10）")

    print("\n" + "=" * 66)
    print("移植提示")
    print("=" * 66)
    print("""
Kotlin : ByteBuffer.allocate(40).order(ByteOrder.LITTLE_ENDIAN)   ← 默认是大端！
Dart   : ByteData.setFloat32(off, v, Endian.little)               ← 必须显式传
ArkTS  : DataView.setFloat32(off, v, true)                        ← 第三参 true = 小端
C/C++  : 桌面/手机一般已是小端，但别假设
""")
    return 0


def cmd_verify(args) -> int:
    raw = args.hex.replace(" ", "").replace("0x", "").replace(",", "")
    try:
        pkt = bytes.fromhex(raw)
    except ValueError as e:
        print(f"[X] 十六进制串无法解析：{e}")
        return 1

    print(f"输入 {len(pkt)} 字节：{hexs(pkt)}\n")

    if len(pkt) < HEADER_SIZE:
        print(f"[X] 太短，连 10 字节头都不够")
        return 1

    head = decode_header(pkt)
    if head is None:
        print(f"[X] 头校验失败：magic={pkt[0]:#04x}（应 0xa7）, "
              f"version={pkt[1]}（应 {VERSION}）")
        if pkt[0] != MAGIC:
            print("    → magic 不对，这包大屏会直接丢弃")
        if pkt[1] != VERSION:
            print(f"    → 版本不匹配，大屏要求 {VERSION}")
        return 1

    names = {TYPE_DATA: "DATA", TYPE_HELLO: "HELLO", TYPE_BYE: "BYE", TYPE_FULL: "FULL"}
    print(f"[OK] 头合法：type={head['type']}（{names.get(head['type'], '未知')}）"
          f"  player_id={head['player_id']}  seq={head['seq']}")

    if head["type"] == TYPE_DATA:
        if len(pkt) != DATA_SIZE:
            print(f"[!] 长度 {len(pkt)}，应为 {DATA_SIZE}")
            return 1
        gyro, accel, buttons, ts = decode_data(pkt)
        print(f"[OK] 长度正确（{len(pkt)}）")
        print(f"     gyro  = ({gyro[0]:+.3f}, {gyro[1]:+.3f}, {gyro[2]:+.3f})")
        print(f"     accel = ({accel[0]:+.3f}, {accel[1]:+.3f}, {accel[2]:+.3f})")
        print(f"     buttons={buttons}  ts={ts}")

        import math
        if any(math.isnan(v) or abs(v) > 1e4 for v in (*gyro, *accel)):
            print("\n[X] 数值异常（NaN 或超大）→ 几乎肯定是字节序写反了")
            return 1
        mag = math.sqrt(sum(v * v for v in accel))
        if not (5.0 < mag < 15.0):
            print(f"\n[!] 加速度模长 {mag:.2f} m/s² 不在 5~15（静止应约 9.81）")
            print("    → 可能单位不是 m/s²（用 g 的话会差 9.8 倍）")
        else:
            print(f"\n[OK] 加速度模长 {mag:.2f} m/s²，符合静止时的重力预期")
        if accel[1] < 0:
            print("[!] accel.y 为负 → 检查 y 轴是否向上。竖持静止时 y 应约 +9.81")
    elif head["type"] == TYPE_HELLO:
        if len(pkt) < HEADER_SIZE + 1:
            print("[X] 缺 name_len 字段")
            return 1
        n = pkt[HEADER_SIZE]
        raw_name = pkt[HEADER_SIZE + 1: HEADER_SIZE + 1 + n]
        if len(raw_name) != n:
            print(f"[X] name_len 说 {n} 字节，实际只有 {len(raw_name)}")
            return 1
        try:
            name = raw_name.decode("utf-8")
            print(f"[OK] 名字 = 「{name}」（{n} 字节）")
        except UnicodeDecodeError:
            print(f"[X] 名字不是合法 UTF-8：{raw_name.hex()}")
            print("    → 大概率是按字节截断汉字造成的（必须按字符回退）")
            return 1
        if n > MAX_NAME_BYTES:
            print(f"[!] name_len {n} 超过上限 {MAX_NAME_BYTES}")
    return 0


def cmd_listen(args) -> int:
    port = args.port
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", port))
    print(f"假大屏已监听 UDP :{port} —— 把手机指向本机 IP 就能看到包")
    print("（这里只解析不解码滤波，用来确认「包能到、格式对」）\n")

    count, bad = 0, 0
    names: dict[int, str] = {}
    try:
        while True:
            pkt, addr = sock.recvfrom(2048)
            count += 1
            head = decode_header(pkt)
            if head is None:
                bad += 1
                print(f"[{count}] 来自 {addr[0]}:{addr[1]}  ← 头非法 {hexs(pkt[:10])}")
                continue
            t = head["type"]
            pid = head["player_id"]
            if t == TYPE_DATA:
                r = decode_data(pkt)
                if r is None:
                    bad += 1
                    print(f"[{count}] DATA 解析失败，长度 {len(pkt)}")
                    continue
                gyro, accel, _b, _ts = r
                print(f"[{count}] DATA  pid={pid} seq={head['seq']} "
                      f"accel.y={accel[1]:+7.2f} "
                      f"(模 {sum(v*v for v in accel)**0.5:5.2f}) "
                      f"@{addr[0]}")
            elif t == TYPE_HELLO:
                n = pkt[HEADER_SIZE] if len(pkt) > HEADER_SIZE else 0
                nm = pkt[HEADER_SIZE + 1: HEADER_SIZE + 1 + n].decode("utf-8", "replace")
                names[pid] = nm
                print(f"[{count}] HELLO pid={pid} 名字「{nm}」@{addr[0]}:{addr[1]}")
            elif t == TYPE_BYE:
                print(f"[{count}] BYE   pid={pid} 退出")
            else:
                print(f"[{count}] type={t} 长度 {len(pkt)}")
    except KeyboardInterrupt:
        print(f"\n共收到 {count} 包，其中非法 {bad} 包")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="手机端协议编码校验器")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("encode", help="打印参考字节").set_defaults(func=cmd_encode)

    p = sub.add_parser("verify", help="校验十六进制串")
    p.add_argument("hex", help="如 c3f51c41 或 'c3 f5 1c 41'")
    p.set_defaults(func=cmd_verify)

    p = sub.add_parser("listen", help="起一个假的 UDP 接收端")
    p.add_argument("--port", type=int, default=8910)
    p.set_defaults(func=cmd_listen)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
