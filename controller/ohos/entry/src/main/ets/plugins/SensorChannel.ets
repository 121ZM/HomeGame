import {
  Any,
  BinaryMessenger,
  EventChannel,
  EventSink,
  StreamHandler
} from '@ohos/flutter_ohos';
import sensor from '@ohos.sensor';
import display from '@ohos.display';

const CHANNEL_NAME: string = 'cn.zm.homegame/sensor';

// 采样间隔（纳秒）。README 里写的 "20000ns" 是单位笔误，50Hz 实际是 20000000ns（20ms）。
// 想要更快（如 60Hz）可调小到约 16666667ns。
const SAMPLE_INTERVAL_NS: number = 20000000;

/**
 * 传感器通道（鸿蒙原生侧）。
 *
 * 对应 lib/sensor/sensor_channel.dart 的 SensorChannel。
 * EventChannel 名 cn.zm.homegame/sensor，每帧推：
 *   { gx, gy, gz, ax, ay, az, ts, rot }
 * 加速度单位 m/s²（含重力），角速度单位 rad/s，ts 单位毫秒，rot 为屏幕旋转角（0/90/180/270）。
 *
 * 坐标轴：@ohos.sensor 的 ACCELEROMETER / GYROSCOPE 与安卓同源，
 * 竖持静止时加速度约为 (0, +9.81, 0)，已符合协议，**不要翻负号**。
 *
 * rot：协议是「竖屏语义」，但传感器给的是设备坐标。横屏时若不带回旋转角，
 * 玩家转 90° 后「往左倾」会变成「往前倾」。Dart 侧用这个 rot 做轴映射。
 * 旋转角从 @ohos.display 取（Display.rotation 是 0/1/2/3，需 ×90 转成角度）。
 *
 * 互补合成：加速度计与陀螺仪各自异步回调，缓存对方最新值，任一到达即用最新值合成一帧推出。
 *
 * ⚠️ 隐私合规：本端只在 Dart 侧订阅（onListen）后才开始读传感器；
 *    上架华为应用市场前，Dart 侧须在用户同意隐私政策之后再订阅本通道。
 */
export class SensorChannel implements StreamHandler {
  private channel: EventChannel | null = null;
  private eventSink: EventSink | null = null;
  private accelCallback: ((data: sensor.AccelerometerResponse) => void) | null = null;
  private gyroCallback: ((data: sensor.GyroscopeResponse) => void) | null = null;

  // 互补传感器的最新读数缓存，用于合成同一帧。
  private lastAx: number = 0;
  private lastAy: number = 0;
  private lastAz: number = 0;
  private lastGx: number = 0;
  private lastGy: number = 0;
  private lastGz: number = 0;
  private lastAccelTs: number = 0;
  private haveAccel: boolean = false;
  private haveGyro: boolean = false;

  // 屏幕旋转角（度）。
  private rotationDeg: number = 0;

  attach(messenger: BinaryMessenger): void {
    this.channel = new EventChannel(messenger, CHANNEL_NAME);
    this.channel.setStreamHandler(this);
  }

  detach(): void {
    this.channel?.setStreamHandler(null);
    this.channel = null;
    this.stopSensors();
  }

  onListen(args: Any, events: EventSink): void {
    this.eventSink = events;
    this.updateRotation();
    this.startRotationWatch();
    this.startSensors();
  }

  onCancel(args: Any): void {
    this.stopSensors();
    this.eventSink = null;
  }

  private startSensors(): void {
    const accelCallback = (data: sensor.AccelerometerResponse): void => {
      this.lastAx = data.x;
      this.lastAy = data.y;
      this.lastAz = data.z;
      this.lastAccelTs = data.timestamp;
      this.haveAccel = true;
      this.emit();
    };
    this.accelCallback = accelCallback;
    sensor.on(sensor.SensorId.ACCELEROMETER, accelCallback, { interval: SAMPLE_INTERVAL_NS });

    const gyroCallback = (data: sensor.GyroscopeResponse): void => {
      this.lastGx = data.x;
      this.lastGy = data.y;
      this.lastGz = data.z;
      this.haveGyro = true;
      this.emit();
    };
    this.gyroCallback = gyroCallback;
    sensor.on(sensor.SensorId.GYROSCOPE, gyroCallback, { interval: SAMPLE_INTERVAL_NS });
  }

  private stopSensors(): void {
    if (this.accelCallback !== null) {
      sensor.off(sensor.SensorId.ACCELEROMETER, this.accelCallback);
      this.accelCallback = null;
    }
    if (this.gyroCallback !== null) {
      sensor.off(sensor.SensorId.GYROSCOPE, this.gyroCallback);
      this.gyroCallback = null;
    }
    this.haveAccel = false;
    this.haveGyro = false;
    this.stopRotationWatch();
  }

  private updateRotation(): void {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      // ⚠️ Display.rotation 是 **枚举** Rotation（不是裸数字）。直接 `* 90` 在 ArkTS
      // 严格模式下可能报「不允许对枚举做算术」。显式映射最稳，也顺便兜住未知值。
      switch (d.rotation) {
        case display.Rotation.ROTATION_90:
          this.rotationDeg = 90;
          break;
        case display.Rotation.ROTATION_180:
          this.rotationDeg = 180;
          break;
        case display.Rotation.ROTATION_270:
          this.rotationDeg = 270;
          break;
        default:
          this.rotationDeg = 0;
          break;
      }
    } catch (e) {
      // 拿不到就按竖屏处理 —— 不影响竖屏玩。
      this.rotationDeg = 0;
    }
  }

  private startRotationWatch(): void {
    try {
      // 'change' 回调拿到的是 display id（number），需要重新取一次 Display 拿最新 rotation。
      display.on('change', (id: number): void => {
        this.updateRotation();
      });
    } catch (e) {
      // 监听失败不致命。
    }
  }

  private stopRotationWatch(): void {
    try {
      display.off('change');
    } catch (e) {
      // 忽略
    }
  }

  private emit(): void {
    const sink: EventSink | null = this.eventSink;
    if (sink === null || !this.haveAccel || !this.haveGyro) {
      return;
    }
    // ts：传感器时间戳是纳秒，协议要毫秒。
    const ts: number = Math.floor(this.lastAccelTs / 1000000);
    sink.success({
      gx: this.lastGx,
      gy: this.lastGy,
      gz: this.lastGz,
      ax: this.lastAx,
      ay: this.lastAy,
      az: this.lastAz,
      ts: ts,
      rot: this.rotationDeg
    });
  }
}
