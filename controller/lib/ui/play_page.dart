/// 运行中的手柄页 —— 连上大屏后停在这里。
///
/// 这一屏存在的主要意义是**让玩家确认手机真的在发数据**：
/// - 大大的实时读数（倾斜条 / 加速度条）—— 挥一下能看到动，就有信心
/// - 发送频率 + 失败计数 —— 卡不卡一眼可见
/// - 改名入口 —— 重发 HELLO 即可，不用重连
///
/// 真正的玩法画面在大屏上，这块小屏**不该喧宾夺主**。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../session.dart';
import '../ui/theme.dart';
import 'diag_page.dart';

class PlayPage extends StatefulWidget {
  const PlayPage({super.key, required this.session});

  final ControllerSession session;

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 传感器 60Hz 但界面不需要 —— 20Hz 重绘足够顺滑，省电。
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _rename() async {
    final ctl = TextEditingController(text: widget.session.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('改名字'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 8,
          decoration: const InputDecoration(
            hintText: '最多 8 个字',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await widget.session.rename(name);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final latest = s.latest;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: AppColors.ok,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            const Text('已连接'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '诊断',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DiagPage(session: s)),
            ),
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
          IconButton(
            tooltip: '断开',
            onPressed: () async {
              await s.disconnect();
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.link_off),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _card(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name.isEmpty ? '（由大屏分配）' : s.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '玩家 ${s.playerId}  ·  ${s.target ?? "未连接"}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _rename,
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('改名'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.ink, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 倾斜条 —— 左右倾斜时能明显看到动
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('左右倾斜', style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    )),
                    const SizedBox(height: 12),
                    _tiltBar(latest?.ax ?? 0),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 前后倾斜 —— 拔河的「蹦」判定靠 ay
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('前后倾斜（含重力）', style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    )),
                    const SizedBox(height: 12),
                    _tiltBar(latest?.ay ?? 0, vertical: true),
                  ],
                ),
              ),
              const Spacer(),
              _stats(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ink, width: 2.5),
      ),
      child: child,
    );
  }

  /// 一根以中心为零点的双向条。[vertical] 时显示为上下（y 轴）。
  Widget _tiltBar(double v, {bool vertical = false}) {
    // 归一化到 ±10 m/s²，超出裁剪
    var t = (v / 10.0).clamp(-1.0, 1.0);
    final frac = (t + 1) / 2; // 0..1

    return Column(
      children: [
        SizedBox(
          height: 34,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.paperAlt,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.line, width: 2),
                ),
              ),
              // 中心刻度
              Center(
                child: Container(width: 2, height: 22, color: AppColors.inkMute),
              ),
              // 指示块
              Align(
                alignment: Alignment(frac * 2 - 1, 0),
                child: Container(
                  width: 30,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.ink, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          v.toStringAsFixed(2),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }

  Widget _stats(ControllerSession s) {
    final unstable = s.sentPerSec < 30;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unstable ? AppColors.waiting : AppColors.line,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('发送', '${s.sentPerSec}/s', unstable),
          Container(width: 2, height: 28, color: AppColors.line),
          _stat('状态', unstable ? '信号弱' : '正常', unstable),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, bool warn) {
    return Column(
      children: [
        Text(label, style: const TextStyle(
          fontSize: 12,
          color: AppColors.inkSoft,
        )),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: warn ? AppColors.waiting : AppColors.ink,
          ),
        ),
      ],
    );
  }
}
