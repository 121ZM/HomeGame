/// 手机 ⟶ 大屏 的 UDP 包协议（v2）。**纯逻辑，不依赖 Flutter / 平台 API。**
///
/// 权威定义在 `screen/scripts/net/net_protocol.gd`；对接文档 `docs/controller-protocol.md`。
/// 本文件是它的 Dart 等价实现 —— **必须逐字节一致**，改协议时三处同步。
///
/// 用 `tools/proto_sync_check.py` 可以自动对拍（Godot 侧 vs Python 侧），
/// 本文件用 `dart test` 或 `dart run` 自校验（见文件末尾的 `main`）。
///
/// ## 两个「写错也不报错」的坑
/// 1. **小端字节序**：Dart 的 `ByteData` 必须显式传 `Endian.little`，
///    写反了数值会变 NaN 或天文数字，但**代码不会抛异常**。
/// 2. **坐标轴映射**：协议约定 y 轴向上（「蹦」靠它判定），
///    各平台原生坐标轴不同，必须转换。
library;

import 'dart:typed_data';

/// 协议常量。与 Godot 侧 `NetProtocol` 一一对应。
class NetProtocol {
  NetProtocol._(); // 纯静态，不实例化

  static const int magic = 0xA7;
  static const int version = 2;
  static const int headerSize = 10;

  static const int typeData = 0;
  static const int typeHello = 1;
  static const int typeBye = 2;
  static const int typeFull = 128;

  static const int dataSize = 40;
  static const int maxNameBytes = 24;

  /// 大屏默认监听端口。
  static const int defaultPort = 8910;

  /// 10 字节公共头。
  ///
  /// 偏移：magic u8 / version u8 / type u8 / pad u8 / player_id u16 / seq u32
  static Uint8List _header(int type, int playerId, int seq) {
    final b = ByteData(headerSize);
    b.setUint8(0, magic);
    b.setUint8(1, version);
    b.setUint8(2, type);
    b.setUint8(3, 0); // pad，固定 0
    // ⚠️ 必须显式小端 —— setUint16/setUint32 的默认值是 Endian.big
    b.setUint16(4, playerId & 0xFFFF, Endian.little);
    b.setUint32(6, seq & 0xFFFFFFFF, Endian.little);
    return b.buffer.asUint8List();
  }

  /// 40 字节传感器数据包。**按 60Hz 发送。**
  ///
  /// [accel] 单位 m/s²、**含重力分量**，且 **y 轴向上为正**。
  /// [gyro] 单位 rad/s。
  /// [buttons] 位掩码，不用就传 0。
  /// [timestampMs] 手机本地毫秒时间戳，仅调试用。
  static Uint8List encodeData({
    required int playerId,
    required int seq,
    required double gx,
    required double gy,
    required double gz,
    required double ax,
    required double ay,
    required double az,
    int buttons = 0,
    required int timestampMs,
  }) {
    final b = ByteData(dataSize);
    b.buffer.asUint8List().setAll(0, _header(typeData, playerId, seq));
    // float32 也是显式小端
    b.setFloat32(10, gx, Endian.little);
    b.setFloat32(14, gy, Endian.little);
    b.setFloat32(18, gz, Endian.little);
    b.setFloat32(22, ax, Endian.little);
    b.setFloat32(26, ay, Endian.little);
    b.setFloat32(30, az, Endian.little);
    b.setUint16(34, buttons & 0xFFFF, Endian.little);
    b.setUint32(36, timestampMs & 0xFFFFFFFF, Endian.little);
    return b.buffer.asUint8List();
  }

  /// 报名包，进场发一次；**改名 = 重发一次 HELLO**（不需要新报文）。
  ///
  /// 名字超过 [maxNameBytes] 时**按字符回退**，绝不按字节切 ——
  /// 一个汉字 3 字节，切中间会产生非法 UTF-8，大屏解出来是乱码。
  static Uint8List encodeHello({required int playerId, required String name}) {
    final raw = fitName(name);
    final out = Uint8List(headerSize + 1 + raw.length);
    out.setAll(0, _header(typeHello, playerId, 0));
    out[headerSize] = raw.length;
    out.setAll(headerSize + 1, raw);
    return out;
  }

  /// 把名字裁到 24 字节以内，**按字符回退**。
  ///
  /// 注意用 `runes` 而不是 `String.length` —— 后者数的是 UTF-16 code unit，
  /// emoji 和部分汉字会被算成 2 个，导致边界判断错位。
  static Uint8List fitName(String name) {
    var s = name;
    while (s.isNotEmpty && _utf8Len(s) > maxNameBytes) {
      final r = s.runes.toList();
      if (r.isEmpty) break;
      s = String.fromCharCodes(r.sublist(0, r.length - 1));
    }
    return Uint8List.fromList(_utf8(s));
  }

  static Uint8List encodeBye({required int playerId}) =>
      _header(typeBye, playerId, 0);

  /// 只解头，用于路由。头非法返回 null。
  static Map<String, int>? decodeHeader(Uint8List pkt) {
    if (pkt.length < headerSize) return null;
    final b = ByteData.sublistView(pkt);
    if (b.getUint8(0) != magic) return null;
    if (b.getUint8(1) != version) return null;
    return {
      'type': b.getUint8(2),
      'player_id': b.getUint16(4, Endian.little),
      'seq': b.getUint32(6, Endian.little),
    };
  }

  /// 解 DATA 包；类型不符或长度不足返回 null。
  static Map<String, dynamic>? decodeData(Uint8List pkt) {
    if (pkt.length < dataSize) return null;
    final head = decodeHeader(pkt);
    if (head == null || head['type'] != typeData) return null;
    final b = ByteData.sublistView(pkt);
    return {
      'player_id': head['player_id'],
      'seq': head['seq'],
      'gyro': [
        b.getFloat32(10, Endian.little),
        b.getFloat32(14, Endian.little),
        b.getFloat32(18, Endian.little),
      ],
      'accel': [
        b.getFloat32(22, Endian.little),
        b.getFloat32(26, Endian.little),
        b.getFloat32(30, Endian.little),
      ],
      'buttons': b.getUint16(34, Endian.little),
      'timestamp_ms': b.getUint32(36, Endian.little),
    };
  }

  // ---- UTF-8 编解码。不用 dart:convert 是为了避开 BOM/替换字符之类的差异，
  //      保持与 Godot `to_utf8_buffer()` 的严格一致。
  static List<int> _utf8(String s) {
    final out = <int>[];
    for (final r in s.runes) {
      if (r < 0x80) {
        out.add(r);
      } else if (r < 0x800) {
        out.add(0xC0 | (r >> 6));
        out.add(0x80 | (r & 0x3F));
      } else if (r < 0x10000) {
        out.add(0xE0 | (r >> 12));
        out.add(0x80 | ((r >> 6) & 0x3F));
        out.add(0x80 | (r & 0x3F));
      } else {
        out.add(0xF0 | (r >> 18));
        out.add(0x80 | ((r >> 12) & 0x3F));
        out.add(0x80 | ((r >> 6) & 0x3F));
        out.add(0x80 | (r & 0x3F));
      }
    }
    return out;
  }

  static int _utf8Len(String s) {
    var n = 0;
    for (final r in s.runes) {
      if (r < 0x80) {
        n += 1;
      } else if (r < 0x800) {
        n += 2;
      } else if (r < 0x10000) {
        n += 3;
      } else {
        n += 4;
      }
    }
    return n;
  }
}

/// 十六进制打印，用于跟 `screen/tools/proto_dump.tscn` 的输出对拍。
String hexDump(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
