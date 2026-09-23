/// 诊断页 —— **真机联调的第一步就看它**。
///
/// 为什么必须有这一页：协议里有两个「写错也不报错」的坑 ——
/// 字节序和坐标轴。这两个坑在大屏上表现为「手机在乱动」或「完全没反应」，
/// 但从大屏端根本看不出是编码错了、轴反了、还是传感器没读到。
///
/// 这一页把**原始读数**摊开：
/// - 静止竖持时 `ay` 应该是 **+9.81**（正数）。是 -9.81 说明轴反了。
/// - 把手机翻过来屏幕朝下，`ay` 应变成 **-9.81**。
/// - 左右倾斜，`ax` 应该在正负之间平滑变化。
/// - 甩一下，`ay` 会明显冲高（拔河的「蹦」就是这个信号）。
/// - 十六进制包体可以直接跟 `tools/proto_check.py` 对字节。
library;

import 'package:flutter/material.dart';

import '../net/protocol.dart';
import '../session.dart';
import 'theme.dart';

class DiagPage extends StatefulWidget {
  const DiagPage({super.key, required this.session});

  final ControllerSession session;

  @override
  State<DiagPage> createState() => _DiagPageState();
}

class _DiagPageState extends State<DiagPage> {
  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final latest = s.latest;

    return Scaffold(
      appBar: AppBar(title: const Text('诊断')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _hintCard(),
            const SizedBox(height: 16),
            if (latest == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('还没有传感器读数 —— 传感器可能没启动。'),
                ),
              )
            else ...[
              _row('加速度 ax（左右）', latest.ax),
              _row('加速度 ay（上下）★', latest.ay),
              _row('加速度 az（前后）', latest.az),
              const SizedBox(height: 8),
              _row('角速度 gx', latest.gx),
              _row('角速度 gy', latest.gy),
              _row('角速度 gz', latest.gz),
              const SizedBox(height: 20),
              _hexCard(latest.ax, latest.ay, latest.az, latest.timestampMs),
              const SizedBox(height: 20),
              _sendStats(s),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hintCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 2),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '静止竖持时，ay 必须是 +9.81',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '显示 -9.81 → 该端坐标轴反了，要在 sensor_source.dart 里把 flipY 打开。\n'
            '屏幕上翻朝下 → ay 应变成 -9.81。\n'
            '甩一下（往上蹦）→ ay 会冲到 20 以上。',
            style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, double v) {
    final warn = label.contains('★') && (v < 0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.inkSoft),
            ),
          ),
          Text(
            v.toStringAsFixed(3),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: warn ? AppColors.accent : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  /// 直接展示协议字节，可以跟 `tools/proto_check.py` 的输出对照。
  Widget _hexCard(double ax, double ay, double az, int ts) {
    final pkt = NetProtocol.encodeData(
      playerId: widget.session.playerId,
      seq: 0,
      gx: 0,
      gy: 0,
      gz: 0,
      ax: ax,
      ay: ay,
      az: az,
      timestampMs: ts,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '协议字节（seq=0，陀螺为零）',
            style: TextStyle(fontSize: 12, color: AppColors.inkMute),
          ),
          const SizedBox(height: 8),
          SelectableText(
            hexDump(pkt),
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              fontFamily: 'monospace',
              color: AppColors.paper,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sendStats(ControllerSession s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _kv('发送频率', '${s.sentPerSec}/s'),
          _kv('玩家号', '${s.playerId}'),
          _kv('目标', '${s.target ?? "-"}'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Column(
      children: [
        Text(k, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
        const SizedBox(height: 4),
        Text(
          v,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}
