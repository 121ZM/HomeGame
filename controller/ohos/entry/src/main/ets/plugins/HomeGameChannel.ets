
/**
 * HomeGame 手机手柄 —— 鸿蒙原生侧（ArkTS）。
 *
 * 与安卓侧 `android/.../MainActivity.kt` **一一对应**：通道名、方法签名、
 * 返回结构、传感器字段名必须完全一致 —— 因为 Dart 侧只有一份代码
 * （`lib/net/udp_transport.dart` 和 `lib/sensor/sensor_channel.dart`）。
 *
 * ## 两个通道
 * - MethodChannel `cn.zm.homegame/udp` —— open / send / close
 * - EventChannel  `cn.zm.homegame/sensor` —— 每帧推传感器读数
 *
 * ## 为什么 UDP 不写进业务层
 * Dart 侧要的是「把这段字节原样发给这个地址」，用平台通道控制力最强：
 * 字节序、发包时机、socket 生命周期全在原生侧，Dart 只管拼字节。
 *
 * ## ⚠️ 本文件尚未编译验证
 * 本机没装 DevEco Studio + HarmonyOS SDK，没法编 .hap。
 * 通道名、字段名、权限名已逐项核对（错这些会导致真机联调排查半天），
 * 但 **API 用法（尤其 socket / sensor 的参数形态）需装好 DevEco 后实测校正**。
 */

import { FlutterEngine, MethodChannel, MethodCall, EventChannel, EventSink } from '@ohos/flutter_ohos';
import sensor from '@ohos.sensor';
import socket from '@ohos.net.socket';
import display from '@ohos.display';
import { BusinessError } from '@ohos.base';

const UDP_CHANNEL = 'cn.zm.homegame/udp';
const SENSOR_CHANNEL = 'cn.zm.homegame/sensor';

/** sensor.on 的 interval 单位是纳秒。20_000_000ns = 50Hz（对齐安卓 SENSOR_DELAY_GAME）。 */
const SENSOR_INTERVAL_NS = 20000000;

export class HomeGameChannel {
  private udpChannel: MethodChannel | null = null;
  private sensorChannel: EventChannel | null = null;

  private udpSocket: socket.UDPSocket | null = null;
  private sink: EventSink | null = null;

  /** 屏幕旋转角（度）。0 / 90 / 180 / 270。 */
  private rotationDeg: number = 0;

  /** 两个传感器回调频率不同，各自更新分量，发事件时组合成完整一帧。 */
  private ax = 0;
  private ay = 0;
  private az = 0;
  private gx = 0;
  private gy = 0;
  private gz = 0;
  private haveAccel = false;
  private haveGyro = false;

  registerWith(engine: FlutterEngine): void {
    const messenger = engine.dartExecutor.binaryMessenger;

    this.udpChannel = new MethodChannel(messenger, UDP_CHANNEL);
    this.udpChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.onUdpCall(call, result);
      },
    });

    this.sensorChannel = new EventChannel(messenger, SENSOR_CHANNEL);
    this.sensorChannel.setStreamHandler({
      onListen: (args: object, events: EventSink) => {
        this.sink = events;
        this.startSensors();
      },
      onCancel: (args: object) => {
        this.stopSensors();
        this.sink = null;
      },
    });

    this.watchRotation();
  }

  // ---------------------------------------------------------------- UDP

  private onUdpCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'open':
        this.udpOpen(call, result);
        break;
      case 'send':
        this.udpSend(call, result);
        break;
      case 'close':
        this.udpClose(result);
        break;
      default:
        result.notImplemented();
    }
  }

  /**
   * 绑定本地端口。port=0 表示让系统分配。
   *
   * ⚠️ **无论成功失败都走 result.success**，失败信息放 error 字段 ——
   * Dart 侧把失败当正常路径处理（降级成计数器），抛异常会打断 60Hz 主循环。
   */
  private udpOpen(call: MethodCall, result: MethodResult): void {
    const port: number = call.argument<number>('port') ?? 0;
    try {
      const udp = socket.constructUDPSocketInstance();
      udp.bind({ address: '0.0.0.0', port: port })
        .then(() => {
          this.udpSocket = udp;
          result.success({ ok: true, error: null });
        })
        .catch((err: BusinessError) => {
          this.udpSocket = null;
          result.success({ ok: false, error: `bind 失败: ${err.code} ${err.message}` });
        });
    } catch (e) {
      this.udpSocket = null;
      const err = e as BusinessError;
      result.success({ ok: false, error: `创建 socket 失败: ${err.message}` });
    }
  }

  private udpSend(call: MethodCall, result: MethodResult): void {
    const host: string = call.argument<string>('host') ?? '';
    const port: number = call.argument<number>('port') ?? 0;
    const bytes: ArrayBuffer | undefined = call.argument<ArrayBuffer>('bytes');

    const udp = this.udpSocket;
    if (udp === null) {
      result.success({ ok: false, error: 'socket 未打开，请先调用 open()' });
      return;
    }
    if (host.length === 0 || port === 0 || bytes === undefined) {
      result.success({ ok: false, error: 'send 参数缺失 (host/port/bytes)' });
      return;
    }

    // ⚠️ Flutter 侧传来的 Uint8List 落到 ArkTS 侧是 ArrayBuffer。
    // 如果实际拿到的是 Uint8Array（取决于 flutter_ohos 版本），
    // 这里要改成 `const buf = (bytes as Uint8Array).buffer` —— 装好 SDK 后实测确认。
    udp.send({ data: bytes, address: host, port: port })
      .then(() => {
        result.success({ ok: true, error: null });
      })
      .catch((err: BusinessError) => {
        result.success({ ok: false, error: `${err.code} ${err.message}` });
      });
  }

  private udpClose(result: MethodResult): void {
    const udp = this.udpSocket;
    this.udpSocket = null;
    if (udp === null) {
      result.success({ ok: true, error: null });
      return;
    }
    udp.close()
      .then(() => result.success({ ok: true, error: null }))
      .catch(() => {
        // 关不掉就算了，下次 open 会覆盖
        result.success({ ok: true, error: null });
      });
  }

  // ------------------------------------------------------------ 传感器

  /**
   * 跟踪屏幕旋转。
   *
   * ⚠️ 协议约定的是**竖屏语义**，但传感器给的是**设备坐标**。
   * 玩家横着拿手机时若不映射，「往左倾」会变成「往前倾」。
   * Dart 侧按我们推的 `rot` 做映射（见 `sensor_source.dart`）。
   */
  private watchRotation(): void {
    try {
      // 取初始值。⚠️ display.rotation 是 0/1/2/3 **枚举**，不是角度，必须 ×90。
      const d: display.Display = display.getDefaultDisplaySync();
      this.rotationDeg = d.rotation * 90;

      display.on('change', (data: display.Display) => {
        this.rotationDeg = data.rotation * 90;
      });
    } catch (e) {
      // 拿不到就按竖屏处理 —— 不影响竖屏玩。
      this.rotationDeg = 0;
    }
  }

  private startSensors(): void {
    // 上架前 TODO：此处应先确认用户已同意隐私政策，再开始读传感器
    //（华为应用市场会检查这一条）。
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, (data: sensor.AccelerometerResponse) => {
        // 单位 m/s²，含重力，y 向上为正 —— 与协议约定一致，**不要翻转符号**。
        this.ax = data.x;
        this.ay = data.y;
        this.az = data.z;
        this.haveAccel = true;
        this.emit();
      }, { interval: SENSOR_INTERVAL_NS });

      sensor.on(sensor.SensorId.GYROSCOPE, (data: sensor.GyroscopeResponse) => {
        // 单位 rad/s —— 与协议约定一致。
        this.gx = data.x;
        this.gy = data.y;
        this.gz = data.z;
        this.haveGyro = true;
        this.emit();
      }, { interval: SENSOR_INTERVAL_NS });
    } catch (e) {
      // 传感器不可用（模拟器 / 无权限）—— 不抛，静默降级。
      const err = e as BusinessError;
      console.error(`[HomeGame] 启动传感器失败: ${err.code} ${err.message}`);
    }
  }

  private stopSensors(): void {
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER);
      sensor.off(sensor.SensorId.GYROSCOPE);
    } catch (e) {
      // 忽略
    }
    this.haveAccel = false;
    this.haveGyro = false;
  }

  /** 两个传感器都至少到过一次再往上推，避免前半段是 0 的脏数据。 */
  private emit(): void {
    if (!this.haveAccel || !this.haveGyro) {
      return;
    }
    const s = this.sink;
    if (s === null) {
      return;
    }
    s.success({
      'gx': this.gx,
      'gy': this.gy,
      'gz': this.gz,
      'ax': this.ax,
      'ay': this.ay,
      'az': this.az,
      // ⚠️ 字段名是 ts，不是 timestamp —— 必须与安卓侧一致。
      'ts': Date.now(),
      'rot': this.rotationDeg,
    });
  }

  dispose(): void {
    this.stopSensors();
    try {
      display.off('change');
    } catch (e) {
      // 忽略
    }
    const udp = this.udpSocket;
    this.udpSocket = null;
    if (udp !== null) {
      udp.close().catch(() => {});
    }
  }
}

/** MethodChannel 的回调签名在 flutter_ohos 里叫 MethodResult —— 与安卓 Result 同义。 */
type MethodResult = {
  success(value?: object | string | number | boolean | null): void;
  error(code: string, message?: string, details?: object): void;
  notImplemented(): void;
};
