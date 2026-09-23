/// HomeGame 手机体感手柄 —— 入口。
///
/// 这一屏只做路由：没连上 → 连接页；连上了 → 手柄页。
///
/// 手机端与玩法**完全解耦** —— 它不知道对面在玩拔河还是赛车，
/// 只负责持续上报「手机现在怎么动的」。所有判定在大屏。
library;

import 'package:flutter/material.dart';

import 'session.dart';
import 'sensor/sensor_channel.dart';
import 'ui/connect_page.dart';
import 'ui/play_page.dart';
import 'ui/theme.dart';

void main() {
  runApp(const HomeGameApp());
}

class HomeGameApp extends StatefulWidget {
  const HomeGameApp({super.key});

  @override
  State<HomeGameApp> createState() => _HomeGameAppState();
}

class _HomeGameAppState extends State<HomeGameApp> {
  late final ControllerSession _session;

  @override
  void initState() {
    super.initState();
    // 传感器实现由平台侧注入。鸿蒙 / 安卓都走同一条平台通道，
    // 所以这里用同一个 SensorChannel，无需按平台分支。
    _session = ControllerSession(sensor: SensorChannel());
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeGame 手柄',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: _session,
        builder: (context, _) {
          if (_session.isStreaming) {
            return PlayPage(session: _session);
          }
          return ConnectPage(session: _session);
        },
      ),
    );
  }
}
