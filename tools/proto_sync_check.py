#!/usr/bin/env python3
"""协议对拍：确认 Godot 侧与 Python 侧编码出的字节完全一致。

**为什么需要它**：协议有两个「写错也不报错」的坑 —— 小端字节序、字段偏移。
一旦以后改了 `net_protocol.gd` 而手机端（或这份 Python 参考）没跟上，
大屏会开始丢包或数值乱套，但不会有任何显式错误。这个脚本把两边钉在一起。

用法（仓库根目录）：
    python3 tools/proto_sync_check.py

退出码 0 = 一致；1 = 有差异（会打印差异位置）。
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCREEN = ROOT / "screen"
GODOT = Path.home() / ".local" / "bin" / "godot"

sys.path.insert(0, str(ROOT / "tools"))
import proto_check as pc  # noqa: E402


def godot_dump() -> dict[str, bytes]:
    """跑 proto_dump.tscn，解析出各用例的字节。"""
    if not GODOT.exists():
        raise SystemExit(f"找不到 Godot：{GODOT}")
    proc = subprocess.run(
        [str(GODOT), "--headless", "--path", str(SCREEN),
         "res://tools/proto_dump.tscn"],
        capture_output=True, text=True, timeout=120,
    )
    out = proc.stdout + proc.stderr
    want = {
        "DATA_STATIC": None, "DATA_JUMP": None, "HELLO_3": None,
        "HELLO_8": None, "HELLO_9": None, "BYE": None,
    }
    for line in out.splitlines():
        m = re.match(r"^([A-Z_0-9]+)\s+([0-9A-F ]+?)\s+len=(\d+)\s*$", line.strip())
        if not m:
            continue
        key, hexstr, length = m.group(1), m.group(2), int(m.group(3))
        if key not in want:
            continue
        raw = bytes.fromhex(hexstr.replace(" ", ""))
        if len(raw) != length:
            raise SystemExit(f"{key}: 声明的 len={length} 与实际 {len(raw)} 不符")
        want[key] = raw
    missing = [k for k, v in want.items() if v is None]
    if missing:
        raise SystemExit(f"Godot 输出里缺这些用例：{missing}\n--- 原始输出 ---\n{out}")
    return want  # type: ignore[return-value]


def main() -> int:
    print("跑 Godot 侧 proto_dump 拿真实字节 …")
    g = godot_dump()

    p = {
        "DATA_STATIC": pc.encode_data(1, 0, (0, 0, 0), (0, 9.81, 0), 0, 1234567),
        "DATA_JUMP": pc.encode_data(1, 1, (0, 0, 5), (0, 35.81, 0), 0, 1234583),
        "HELLO_3": pc.encode_hello(1, "孙悟空"),
        "HELLO_8": pc.encode_hello(1, "一二三四五六七八"),
        "HELLO_9": pc.encode_hello(1, "一二三四五六七八九"),
        "BYE": pc.encode_bye(1),
    }

    print()
    bad = 0
    for key in p:
        gv, pv = g[key], p[key]
        if gv == pv:
            print(f"  [OK]   {key:12s} {len(gv):3d} 字节")
        else:
            bad += 1
            print(f"  [DIFF] {key}")
            print(f"         Godot : {gv.hex(' ').upper()}")
            print(f"         Python: {pv.hex(' ').upper()}")
            for i in range(max(len(gv), len(pv))):
                a = gv[i] if i < len(gv) else None
                b = pv[i] if i < len(pv) else None
                if a != b:
                    fa = f"{a:02X}" if a is not None else "--"
                    fb = f"{b:02X}" if b is not None else "--"
                    print(f"           首个差异 @ 偏移 {i}: Godot={fa} Python={fb}")
                    break

    print()
    if bad:
        print(f"✗ {bad} 个用例不一致 —— 两端协议已跑偏，改协议时必须同步！")
        return 1
    print(f"✓ 全部 {len(p)} 个用例逐字节一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
