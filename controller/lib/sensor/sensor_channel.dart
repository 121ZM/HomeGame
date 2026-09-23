/// 传感器平台通道桥接。**安卓与鸿蒙共用这一份 Dart 代码。**
///
/// 两端的原生侧都往同一条 EventChannel 上推同样格式的 Map，
/// 所以这里不需要按平台分支 —— 差异全在原生侧抹平。
///
/// 原生侧推上来的字段：
/// ```
/// {
///   "gx": double, "gy": double, "gz": double,   // rad/s
///   "ax": double, "ay": double, "az": double,   // m/s²，含重力，y 向上为正
///   "ts": int                                    // 毫秒
/// }
/// ```
///
/// ⚠️ 若某端 SDK 的轴定义与预期不符（静止竖持给 -9.81），
/// 在这里把 [flipY] 打开即可 —— 不要改业务层。
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'sensor_source.dart';

class SensorChannel implements SensorSource {
  SensorChannel();

  /// 与原生侧约定的通道名。改这里必须同步改安卓 / 鸿蒙两侧。
  static const String channelName = 'cn.zm.homegame/sensor';

  static const EventChannel _channel = EventChannel(channelName);

  StreamSubscription<dynamic>? _sub;
  final _ctl = StreamController<SensorSample>.broadcast();

  bool _running = false;
  String? _error;

  /// 兜底开关：某端原生轴定义与协议不符时打开。默认关。
  ///
  /// **默认必须是 false** —— 安卓 / 鸿蒙原生读数都已符合协议约定。
  /// 真机诊断页若显示静止 `ay ≈ -9.81`，再把它改成 true。
  static const bool flipY = false;

  @override
  bool get isRunning => _running;

  @override
  String? get lastError => _error;

  @override
  Stream<SensorSample> get samples => _ctl.stream;

  @override
  Future<bool> start() async {
    if (_running) return true;
    try {
      _sub = _channel.receiveBroadcastStream().listen(
        _onEvent,
        onError: (Object e) {
          _error = '传感器通道出错：$e';
          _running = false;
        },
        cancelOnError: false,
      );
      _running = true;
      _error = null;
      return true;
    } on MissingPluginException {
      // 还没接原生侧（例如在桌面跑）—— 优雅降级，不抛。
      _error = '原生传感器通道未接入（当前不是手机运行环境）';
      _running = false;
      return false;
    } on PlatformException catch (e) {
      _error = e.message ?? e.code;
      _running = false;
      return false;
    }
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _running = false;
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;

    double d(String k) {
      final v = raw[k];
      if (v is num) return v.toDouble();
      return 0;
    }

    int i(String k) {
      final v = raw[k];
      if (v is num) return v.toInt();
      return 0;
    }

    final sample = SensorNormalizer.fromNative(
      gx: d('gx'),
      gy: d('gy'),
      gz: d('gz'),
      ax: d('ax'),
      ay: d('ay'),
      az: d('az'),
      timestampMs: i('ts'),
      flipY: flipY,
    );
    if (!_ctl.isClosed) _ctl.add(sample);
  }

  /// 释放资源。会话断开时调用。
  Future<void> dispose() async {
    await stop();
    await _ctl.close();
  }
}
