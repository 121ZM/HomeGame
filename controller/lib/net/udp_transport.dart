/// 手机 ⟶ 大屏 的 UDP 传输通道。**平台无关的门面**。
///
/// 真正的 socket 在原生侧创建（安卓 Kotlin / 鸿蒙 ArkTS），理由：
/// 1. 鸿蒙 OHOS 生态没有可用的 Dart UDP 插件；
/// 2. 协议字节必须完全可控（小端），交给第三方插件反而要再验一遍字节序；
/// 3. 安卓侧还想拿到 socket 的本机地址与错误码，平台通道给得最直接。
///
/// 本文件只负责：
/// - 拼 [NetProtocol] 的字节，交给原生发出去
/// - 保存大屏地址与玩家 id
/// - 把「发失败」这种非致命错误降级成计数器，不打断 60Hz 主循环
///
/// 原生侧接口（两端必须同名同参，见 `android/` 与 `ohos/`）：
/// - `open(port)` → 绑定本地随机端口，返回 `{ok: bool, error: String?}`
/// - `send(host, port, bytes)` → 发一包，返回 `{ok: bool, error: String?}`
/// - `close()` → 释放
library;

import 'package:flutter/services.dart';

import 'protocol.dart';

/// 大屏地址。
class ScreenAddress {
  const ScreenAddress(this.host, this.port);

  final String host;
  final int port;

  @override
  String toString() => '$host:$port';
}

/// UDP 发送门面。
///
/// 60Hz 调用 [sendData]，**任何失败都不抛异常** —— 网络抖一下不能把游戏搞崩。
/// 失败计入 [failCount]，UI 层据此显示「网络不稳」。
class UdpTransport {
  UdpTransport({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// 与原生侧约定的通道名。改这里必须同步改安卓 / 鸿蒙两侧。
  static const String channelName = 'cn.zm.homegame/udp';

  final MethodChannel _channel;

  ScreenAddress? _address;
  int _playerId = 0;
  int _seq = 0;
  bool _opened = false;

  /// 发送失败累计次数（含编码前就被判定为非法的包）。
  int failCount = 0;

  /// 成功发出的包数。
  int sentCount = 0;

  bool get isOpen => _opened;
  ScreenAddress? get address => _address;
  int get playerId => _playerId;

  /// 绑定本地端口。返回是否成功；失败原因通过 [lastError] 取。
  String? lastError;

  Future<bool> open({int localPort = 0}) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'open',
        <String, Object>{'port': localPort},
      );
      final ok = res?['ok'] == true;
      _opened = ok;
      lastError = ok ? null : (res?['error'] as String? ?? 'open 返回失败');
      return ok;
    } on PlatformException catch (e) {
      lastError = e.message ?? e.code;
      _opened = false;
      return false;
    } on MissingPluginException {
      // 还没接原生侧（例如在桌面跑单元测试）——不算致命，标记未开。
      lastError = '原生通道未接入（当前不是手机运行环境）';
      _opened = false;
      return false;
    }
  }

  /// 设定大屏目标。玩家每次进房会调一次。
  void target(ScreenAddress addr, int playerId) {
    _address = addr;
    _playerId = playerId;
    _seq = 0;
  }

  /// 发一包传感器数据。60Hz 调用。失败只计数，不抛。
  Future<void> sendData({
    required double gx,
    required double gy,
    required double gz,
    required double ax,
    required double ay,
    required double az,
    int buttons = 0,
    required int timestampMs,
  }) async {
    final addr = _address;
    if (addr == null || !_opened) return;

    final pkt = NetProtocol.encodeData(
      playerId: _playerId,
      seq: _seq,
      gx: gx,
      gy: gy,
      gz: gz,
      ax: ax,
      ay: ay,
      az: az,
      buttons: buttons,
      timestampMs: timestampMs,
    );
    _seq = (_seq + 1) & 0xFFFFFFFF;
    await _raw(pkt, addr);
  }

  /// 报名 / 改名。**改名 = 再发一次**，不需要新报文。
  Future<void> sendHello(String name) async {
    final addr = _address;
    if (addr == null || !_opened) return;
    await _raw(NetProtocol.encodeHello(playerId: _playerId, name: name), addr);
  }

  /// 道别（主动退出房间）。
  Future<void> sendBye() async {
    final addr = _address;
    if (addr == null || !_opened) return;
    await _raw(NetProtocol.encodeBye(playerId: _playerId), addr);
  }

  Future<void> _raw(Uint8List pkt, ScreenAddress addr) async {
    try {
      await _channel.invokeMethod<void>('send', <String, Object>{
        'host': addr.host,
        'port': addr.port,
        'bytes': pkt,
      });
      sentCount++;
    } on PlatformException {
      failCount++;
    } on MissingPluginException {
      failCount++;
    }
  }

  Future<void> close() async {
    if (!_opened) return;
    try {
      await _channel.invokeMethod<void>('close');
    } on PlatformException {
      // 关不掉就算了，下次 open 会覆盖
    } on MissingPluginException {
      // 忽略
    }
    _opened = false;
  }
}
