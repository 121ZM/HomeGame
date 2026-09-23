/// 连接页 —— 手机端第一屏。
///
/// 三件事：选玩家号 / 填大屏 IP / 连上。
///
/// 设计取舍：
/// - **玩家号用 8 个色块直接点**，不让用户输数字 —— 色块同时把「这个号是什么颜色」
///   提前告诉他，跟大屏席位圆点一一对应。
/// - **IP 记忆最近一个**，第二次进来不用再敲。
/// - 名字可选 —— 留空由大屏分配（孙悟空/猪八戒…），玩家想改就在这填。
library;

import 'package:flutter/material.dart';

import '../session.dart';
import '../ui/theme.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.session});

  final ControllerSession session;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _hostCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  int _playerId = 1;
  bool _busy = false;

  /// 与大屏 `player_palette.gd` 的 8 色槽位对齐（顺序即槽位号）。
  static const _seatColors = <Color>[
    Color(0xFFE8543F), // 1 番茄红
    Color(0xFF2F9E6E), // 2 草绿
    Color(0xFF3B82F6), // 3 天蓝
    Color(0xFFE2A400), // 4 琥珀
    Color(0xFF8B5CF6), // 5 紫
    Color(0xFFEC4899), // 6 粉
    Color(0xFF14B8A6), // 7 青
    Color(0xFFF97316), // 8 橙
  ];

  @override
  void dispose() {
    _hostCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _hostCtl.text.trim();
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填大屏的 IP 地址')),
      );
      return;
    }

    setState(() => _busy = true);
    final ok = await widget.session.connect(
      host: host,
      playerId: _playerId,
      name: _nameCtl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.session.error ?? '连接失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('HomeGame 手柄'),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const Text('选你的颜色', style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                )),
                const SizedBox(height: 10),
                _seatPicker(),
                const SizedBox(height: 24),

                const Text('大屏地址', style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                )),
                const SizedBox(height: 10),
                TextField(
                  controller: _hostCtl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: '例如 192.168.1.100',
                    prefixIcon: Icon(Icons.tv_rounded),
                  ),
                ),
                const SizedBox(height: 24),

                const Text('你的名字（可留空）', style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                )),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameCtl,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    hintText: '留空则由大屏分配',
                    prefixIcon: Icon(Icons.badge_outlined),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 32),

                FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('连 接'),
                ),
                const SizedBox(height: 16),
                _statusLine(s),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _seatPicker() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: List.generate(8, (i) {
        final id = i + 1;
        final on = id == _playerId;
        final c = _seatColors[i];
        return GestureDetector(
          onTap: () => setState(() => _playerId = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: on ? c : c.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: on ? AppColors.ink : AppColors.line,
                width: on ? 3 : 2,
              ),
              boxShadow: on
                  ? const [
                      BoxShadow(
                        color: AppColors.ink,
                        offset: Offset(0, 3),
                        blurRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                '$id',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: on ? Colors.white : AppColors.inkSoft,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _statusLine(ControllerSession s) {
    if (s.state == LinkState.error) {
      return Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.error ?? '出错了',
              style: const TextStyle(color: AppColors.accent, fontSize: 14),
            ),
          ),
        ],
      );
    }
    return const Text(
      '提示：手机与大屏要在同一个 Wi-Fi / 局域网里。',
      style: TextStyle(color: AppColors.inkMute, fontSize: 13),
    );
  }
}
