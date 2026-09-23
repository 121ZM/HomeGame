/// 协议编码自校验 —— **不上真机、不连大屏就能跑**。
///
/// 跑法：`flutter test`（或 `dart test`）
///
/// 期望值来自 `screen/tools/proto_dump.tscn` 的真实输出（Godot 侧权威），
/// 已用 `tools/proto_sync_check.py` 与 Python 参考实现对拍一致。
/// 这三处必须永远一致 —— 改协议时全都要改。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homegame_controller/net/protocol.dart';

void main() {
  group('协议 v2 字节级自校验', () {
    // ------------------------------------------------------------ 1. 静止握持
    test('DATA 竖持静止 —— 与 Godot 输出逐字节一致', () {
      final staticPkt = NetProtocol.encodeData(
        playerId: 1,
        seq: 0,
        gx: 0,
        gy: 0,
        gz: 0,
        ax: 0,
        ay: 9.81,
        az: 0,
        timestampMs: 1234567,
      );
      expect(staticPkt.length, 40);
      expect(
        hexDump(staticPkt),
        'A7 02 00 00 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 '
        '00 00 C3 F5 1C 41 00 00 00 00 00 00 87 D6 12 00',
      );
    });

    // ------------------------------------------------------------ 2. 字节序
    test('字节序 —— 小端，写反了会静默变错值', () {
      final staticPkt = NetProtocol.encodeData(
        playerId: 1,
        seq: 0,
        gx: 0,
        gy: 0,
        gz: 0,
        ax: 0,
        ay: 9.81,
        az: 0,
        timestampMs: 1234567,
      );
      final ayBytes = staticPkt.sublist(26, 30);
      expect(hexDump(ayBytes), 'C3 F5 1C 41');
      expect(hexDump(ayBytes) == '41 1C F5 C3', isFalse,
          reason: '反序说明写成了大端');
    });

    // ------------------------------------------------------------ 3. 蹦
    test('DATA 向上冲（蹦）—— accel.y = 9.81+26', () {
      final jumpPkt = NetProtocol.encodeData(
        playerId: 1,
        seq: 1,
        gx: 0,
        gy: 0,
        gz: 5,
        ax: 0,
        ay: 35.81,
        az: 0,
        timestampMs: 1234583,
      );
      expect(jumpPkt.length, 40);
      expect(
        hexDump(jumpPkt),
        'A7 02 00 00 01 00 01 00 00 00 00 00 00 00 00 00 00 00 00 00 A0 40 00 00 '
        '00 00 71 3D 0F 42 00 00 00 00 00 00 97 D6 12 00',
      );
    });

    // ------------------------------------------------------------ 4. HELLO
    test('HELLO 报名 —— 含汉字', () {
      final h3 = NetProtocol.encodeHello(playerId: 1, name: '孙悟空');
      expect(h3.length, 20);
      expect(hexDump(h3),
          'A7 02 01 00 01 00 00 00 00 00 09 E5 AD 99 E6 82 9F E7 A9 BA');
      expect(h3[10], 9, reason: 'name_len 必须是字节数');

      final h8 = NetProtocol.encodeHello(playerId: 1, name: '一二三四五六七八');
      expect(h8.length, 35);
      expect(h8[10], 24);
    });

    // ------------------------------------------------------------ 5. 截断
    test('名字截断 —— 按字符回退，绝不按字节切', () {
      final h8 = NetProtocol.encodeHello(playerId: 1, name: '一二三四五六七八');
      final h9 = NetProtocol.encodeHello(playerId: 1, name: '一二三四五六七八九');
      expect(hexDump(h9), hexDump(h8));
      expect(h9.length, 35);

      // 按字节切会切断汉字，产生非法 UTF-8。确认每个字符都是完整 3 字节序列。
      var valid = true;
      for (var i = 11; i < h9.length; i += 3) {
        if ((h9[i] & 0xF0) != 0xE0) {
          valid = false;
          break;
        }
      }
      expect(valid, isTrue, reason: '出现半截汉字说明按字节切了');
    });

    // ------------------------------------------------------------ 6. BYE
    test('BYE 道别', () {
      final bye = NetProtocol.encodeBye(playerId: 1);
      expect(bye.length, 10);
      expect(hexDump(bye), 'A7 02 02 00 01 00 00 00 00 00');
    });

    // ------------------------------------------------------------ 7. 往返
    test('往返一致性 —— 自己编的包自己解得回来', () {
      final staticPkt = NetProtocol.encodeData(
        playerId: 1,
        seq: 0,
        gx: 0,
        gy: 0,
        gz: 0,
        ax: 0,
        ay: 9.81,
        az: 0,
        timestampMs: 1234567,
      );
      final back = NetProtocol.decodeData(staticPkt);
      expect(back, isNotNull);
      expect(back!['player_id'], 1);
      expect(back['seq'], 0);
      final accel = back['accel'] as List<double>;
      // float32 精度有限，9.81 存回来是 9.8100004196167
      expect(accel[1], closeTo(9.81, 0.001));
    });

    // ------------------------------------------------------------ 8. 坏包
    test('坏包应被拒 —— 防止把垃圾当数据', () {
      final staticPkt = NetProtocol.encodeData(
        playerId: 1,
        seq: 0,
        gx: 0,
        gy: 0,
        gz: 0,
        ax: 0,
        ay: 9.81,
        az: 0,
        timestampMs: 1234567,
      );
      expect(NetProtocol.decodeHeader(Uint8List.fromList(staticPkt)..[0] = 0x00),
          isNull);
      expect(NetProtocol.decodeHeader(Uint8List.fromList(staticPkt)..[1] = 99),
          isNull);
      expect(NetProtocol.decodeHeader(Uint8List(5)), isNull);
      expect(NetProtocol.decodeData(Uint8List(20)), isNull);
    });

    // ------------------------------------------------------------ 9. 边界
    test('边界值 —— u16 / u32 上限不回绕', () {
      final big = NetProtocol.encodeData(
        playerId: 65535,
        seq: 4294967295,
        gx: 0,
        gy: 0,
        gz: 0,
        ax: 0,
        ay: 0,
        az: 0,
        buttons: 65535,
        timestampMs: 4294967295,
      );
      expect(big.sublist(4, 6), [0xFF, 0xFF]);
      final bt = NetProtocol.decodeData(big)!;
      expect(bt['buttons'], 65535);
      expect(bt['timestamp_ms'], 4294967295);
    });

    // ------------------------------------------------------------ 10. 压力
    test('随机往返 200 次 —— 大范围随机值不失真', () {
      // 用固定种子保证可复现
      var seed = 12345;
      int next() {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        return seed;
      }

      for (var i = 0; i < 200; i++) {
        final gx = (next() % 20000 - 10000) / 100.0;
        final ay = (next() % 6000 - 3000) / 100.0;
        final pid = next() & 0xFFFF;
        final seq = next() & 0xFFFFFFFF;

        final pkt = NetProtocol.encodeData(
          playerId: pid,
          seq: seq,
          gx: gx,
          gy: 0,
          gz: 0,
          ax: 0,
          ay: ay,
          az: 0,
          timestampMs: seq,
        );
        final back = NetProtocol.decodeData(pkt)!;
        expect(back['player_id'], pid);
        expect(back['seq'], seq);
        final gyro = back['gyro'] as List<double>;
        // float32 有效精度约 7 位十进制，量级 100 时误差 < 1e-4
        expect(gyro[0], closeTo(gx, 0.001));
        final accel = back['accel'] as List<double>;
        expect(accel[1], closeTo(ay, 0.001));
      }
    });
  });
}
