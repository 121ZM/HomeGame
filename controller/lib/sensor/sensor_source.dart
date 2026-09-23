/// 传感器读数 → 统一坐标系。**这是整个手机端最容易静默搞错的地方。**
///
/// 协议约定（见 `docs/controller-protocol.md`）：
/// - 加速度单位 m/s²、**含重力**、**y 轴向上为正**
/// - 角速度单位 rad/s，右手系
///
/// 但各平台原生坐标系命名不同，必须先核一遍：
/// - **安卓** `SensorManager` 的 `TYPE_ACCELEROMETER`：坐标系为「屏幕坐标」，
///   但加速度计读的是**设备受的惯性力**。竖持静止时，重力朝下，加速度计读数为
///   `(0, +9.81, 0)`（y 指向屏幕上方，数值为正）。**正好等于协议要求**。
/// - **鸿蒙** `@ohos.sensor` 的 `ACCELEROMETER`：定义与安卓一致（同源），
///   竖持静止同样给 `(0, +9.81, 0)`。**同样正好等于协议要求**。
///
/// ⚠️ 结论：**两端原生读数都已经符合协议约定，本层不做符号翻转。**
/// 本层只做两件兜底：① 单位确认（个别第三方插件以 g 为单位，要乘 9.80665）；
/// ② 留一个 `flipY` 开关给「某天某端 SDK 轴定义变了」兜底，默认关闭。
///
/// 真机联调第一步：用 `lib/ui/diag_page.dart` 的原始读数页看静止竖持值，
/// 应显示 `ay ≈ +9.81`。若显示 `-9.81`，才把该端的 `flipY` 打开。
library;

/// 单位统一的一帧传感器读数。
class SensorSample {
  const SensorSample({
    required this.gx,
    required this.gy,
    required this.gz,
    required this.ax,
    required this.ay,
    required this.az,
    required this.timestampMs,
  });

  /// 角速度 rad/s（设备坐标系）
  final double gx;
  final double gy;
  final double gz;

  /// 加速度 m/s²，**含重力**，**y 向上为正**
  final double ax;
  final double ay;
  final double az;

  final int timestampMs;
}

/// 把原生读数规整成协议约定的量。
///
/// 现在只是**直通 + 单位兜底**（某些平台给 g 而不是 m/s²）。
/// 保留这一层是为了：以后某端轴定义变了，只改这里，不动业务。
class SensorNormalizer {
  /// 标准重力加速度。用来判断原生是否以 g 为单位。
  static const double g = 9.80665;

  /// 判断一批读数是不是以 g 为单位（绝对值普遍 < 3 就认为是 g）。
  ///
  /// 需要连续几帧都小才判定，避免挥动瞬间的加速度被误判。
  static bool looksLikeGravityUnits(List<double> mags) {
    if (mags.length < 8) return false;
    var small = 0;
    for (final m in mags) {
      if (m.abs() < 3.0) small++;
    }
    return small == mags.length;
  }

  /// 原生读数 → 协议量。
  ///
  /// [inG] 为 true 时把加速度乘以 [g]（有些平台默认给 g，尤其第三方插件）。
  /// [flipY] 某端原生轴定义与协议不符时打开，默认关。
  /// [rotation] 屏幕旋转角（0/90/180/270 度），用于把「屏幕坐标」转回「设备坐标」。
  static SensorSample fromNative({
    required double gx,
    required double gy,
    required double gz,
    required double ax,
    required double ay,
    required double az,
    required int timestampMs,
    bool inG = false,
    bool flipY = false,
    int rotation = 0,
  }) {
    final k = inG ? g : 1.0;

    // 先把设备坐标转成「屏幕坐标」—— 玩家是拿着手机看屏幕的，
    // 他感知的「左右」「上下」跟着屏幕走，不是跟着手机外壳走。
    //
    // 协议约定的是**竖屏（rotation=0）下的设备坐标**。横屏时原生给的轴
    // 仍然是设备坐标，如果直接用，玩家把手机转 90° 后「往左倾」会变成
    // 「往前倾」—— 手感直接废掉。
    //
    // 所以按旋转角做一次二维旋转，把读数映射回竖屏语义。
    // 规则（顺时针旋转屏幕 → 需要逆时针转回读数）：
    //   rotation=0   → (x, y) 不变
    //   rotation=90  → (x', y') = (-y,  x)   横屏，手机右转
    //   rotation=180 → (x', y') = (-x, -y)   倒置
    //   rotation=270 → (x', y') = ( y, -x)   横屏，手机左转
    double rx, ry;
    switch (rotation % 360) {
      case 90:
        rx = -ay * k;
        ry = ax * k;
        break;
      case 180:
        rx = -ax * k;
        ry = -ay * k;
        break;
      case 270:
        rx = ay * k;
        ry = -ax * k;
        break;
      default: // 0
        rx = ax * k;
        ry = ay * k;
    }

    return SensorSample(
      gx: gx,
      gy: gy,
      gz: gz,
      ax: rx,
      // flipY 默认关 —— 安卓/鸿蒙原生都已符合协议。留着是给未来某端轴变了兜底。
      ay: flipY ? -ry : ry,
      az: az * k,
      timestampMs: timestampMs,
    );
  }
}

/// 传感器数据源接口。安卓 / 鸿蒙各实现一个（都走平台通道）。
abstract class SensorSource {
  /// 开始采样。安卓目标 60Hz（`SENSOR_DELAY_GAME`），鸿蒙用 `SENSOR_DELAY_GAME`（20000ns）。
  Future<bool> start();

  Future<void> stop();

  /// 采样流。
  Stream<SensorSample> get samples;

  bool get isRunning;

  String? get lastError;
}
