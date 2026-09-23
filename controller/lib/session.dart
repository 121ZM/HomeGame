/// 手机端会话状态机。**这是手机端的大脑。**
///
/// 管三件事：
/// 1. 连接大屏（地址输入 / 最近地址记忆）
/// 2. 保持 60Hz 心跳：把手柄读数取样、编码、发出去
/// 3. 处理「房间已满」（大屏会回 FULL）等异常
///
/// 与玩法**完全无关** —— 手机端不知道对面在玩拔河还是赛车，
/// 它只负责持续上报「手机现在怎么动的」。判定全在大屏。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../net/protocol.dart';
import '../net/udp_transport.dart';
import '../sensor/sensor_source.dart';

enum LinkState {
  /// 还没连
  idle,

  /// 已开 socket，还没收到大屏任何回应
  connecting,

  /// 正常上报中
  streaming,

  /// 被拒（房间满了）
  rejected,

  /// 出错
  error,
}

/// 会话状态机。
class ControllerSession extends ChangeNotifier {
  ControllerSession({
    UdpTransport? transport,
    required SensorSource sensor,
  })  : _udp = transport ?? UdpTransport(),
        _sensor = sensor;

  final UdpTransport _udp;
  final SensorSource _sensor;

  LinkState _state = LinkState.idle;
  LinkState get state => _state;

  String? _error;
  String? get error => _error;

  ScreenAddress? _target;
  ScreenAddress? get target => _target;

  int _playerId = 0;
  int get playerId => _playerId;

  String _name = '';
  String get name => _name;

  /// 最近一次采样，用于诊断页显示。
  SensorSample? _latest;
  SensorSample? get latest => _latest;

  /// 包发送频率统计（每秒重算）。
  int get sentPerSec => _sentPerSec;
  int _sentPerSec = 0;

  /// 本秒内尝试发送的次数（回调里 ++，定时器每秒收割）。
  int _attempted = 0;
  Timer? _rateTimer;

  /// 传感器订阅句柄。**必须保存下来** ——
  /// 不保存的话断开后流还在推，重复 connect 会挂上多个订阅，读数翻倍。
  StreamSubscription<SensorSample>? _sensorSub;

  /// 发送节流目标（Hz）。手机传感器一般 50–100Hz，不必强制 60。
  static const int targetHz = 60;

  bool get isStreaming => _state == LinkState.streaming;

  /// 连大屏并开始上报。
  ///
  /// [host] 大屏局域网 IP；[port] 默认 8910；[playerId] 本机自报的玩家号（1..8）；
  /// [name] 显示名（可为空 → 大屏会分配一个）。
  Future<bool> connect({
    required String host,
    int port = NetProtocol.defaultPort,
    required int playerId,
    required String name,
  }) async {
    await disconnect();

    _playerId = playerId;
    _name = name;
    _target = ScreenAddress(host, port);
    _error = null;
    _setState(LinkState.connecting);

    final opened = await _udp.open();
    if (!opened) {
      _error = _udp.lastError ?? '无法创建 UDP 套接字';
      _setState(LinkState.error);
      return false;
    }

    _udp.target(_target!, playerId);

    // 开始采样
    final ok = await _sensor.start();
    if (!ok) {
      _error = _sensor.lastError ?? '无法读取传感器';
      _setState(LinkState.error);
      await _udp.close();
      return false;
    }

    // 先报名，再开始上报数据 —— 大屏靠 HELLO 建会话，
    // 顺序反了会有一小段数据包被当成未知玩家丢掉。
    await _udp.sendHello(name);

    _sensorSub = _sensor.samples.listen(_onSample);

    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sentPerSec = _attempted;
      _attempted = 0;
      if (!_disposed) notifyListeners();
    });

    _setState(LinkState.streaming);
    return true;
  }

  /// 改名 —— 重发一次 HELLO 即可，不加新报文。
  Future<void> rename(String newName) async {
    _name = newName;
    await _udp.sendHello(newName);
    notifyListeners();
  }

  void _onSample(SensorSample s) {
    _latest = s;
    if (_state != LinkState.streaming) return;

    // 速率按「尝试发送次数」统计，不依赖 transport 的异步计数
    // （异步计数会滞后一到两拍，显示会跳）。
    _attempted++;
    // 不 await —— 60Hz 主循环不能被网络 IO 卡住。
    // 失败只累加 transport.failCount，UI 据此显示「网络不稳」。
    unawaited(_udp.sendData(
      gx: s.gx,
      gy: s.gy,
      gz: s.gz,
      ax: s.ax,
      ay: s.ay,
      az: s.az,
      timestampMs: s.timestampMs,
    ));
  }

  Future<void> disconnect() async {
    _rateTimer?.cancel();
    _rateTimer = null;
    if (_state == LinkState.streaming) {
      await _udp.sendBye();
    }
    await _sensorSub?.cancel();
    _sensorSub = null;
    await _sensor.stop();
    await _udp.close();
    // 若已 dispose，_setState 里的 notifyListeners 会抛
    // 「used after being disposed」—— 用 _disposed 挡住。
    if (!_disposed) _setState(LinkState.idle);
  }

  void _setState(LinkState s) {
    _state = s;
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _rateTimer?.cancel();
    // 收尾（发 BYE / 关 socket）不能 await —— dispose 是同步的。
    // 标记 _disposed 后，异步尾巴里的状态通知会被挡掉。
    unawaited(disconnect());
    super.dispose();
  }
}
