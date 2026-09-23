/// 坐标规整自校验 —— 屏幕旋转映射是**静默出错**的重灾区，必须测。
///
/// 为什么必须有这组测试：
/// 如果旋转映射写错了，真机上的表现是「手机横着拿时方向全乱」，
/// 而这在竖屏测试时**完全看不出来**。等玩家现场横屏玩才发现就太晚了。
///
/// 参照系：协议约定的是**竖屏语义**（x 屏幕向右、y 屏幕向上）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:homegame_controller/sensor/sensor_source.dart';

void main() {
  group('SensorNormalizer 坐标规整', () {
    test('竖屏（rotation=0）读数直通', () {
      final s = SensorNormalizer.fromNative(
        gx: 1, gy: 2, gz: 3,
        ax: 1.5, ay: 9.81, az: -0.5,
        timestampMs: 100,
      );
      expect(s.ax, closeTo(1.5, 1e-9));
      expect(s.ay, closeTo(9.81, 1e-9));
      expect(s.az, closeTo(-0.5, 1e-9));
      // 陀螺不参与旋转映射（先不做，避免过度设计）
      expect(s.gx, closeTo(1, 1e-9));
    });

    test('静止竖持时 ay = +9.81（协议的核心约定）', () {
      final s = SensorNormalizer.fromNative(
        gx: 0, gy: 0, gz: 0,
        ax: 0, ay: 9.81, az: 0,
        timestampMs: 0,
      );
      expect(s.ay, greaterThan(0), reason: 'y 向上为正，静止必须是正数');
      expect(s.ay, closeTo(9.81, 1e-9));
    });

    test('横屏 90°：设备坐标 (x,y) 映射为屏幕坐标 (-y,x)', () {
      // 手机右转 90°（顺时针）后，设备的「+x」方向在屏幕上变成「向下」。
      // 所以屏幕上的左右倾，对应设备坐标的 y 分量。
      final s = SensorNormalizer.fromNative(
        gx: 0, gy: 0, gz: 0,
        ax: 9.81, ay: 0, az: 0, // 设备 x 方向有重力
        timestampMs: 0,
        rotation: 90,
      );
      // 按映射 (-y, x)：ax' = -ay = 0，ay' = ax = 9.81
      expect(s.ax, closeTo(0, 1e-9));
      expect(s.ay, closeTo(9.81, 1e-9),
          reason: '横屏时设备 x 的重力应转到屏幕 y —— 否则「往上蹦」判定会失效');
    });

    test('横屏 270°：设备坐标 (x,y) 映射为屏幕坐标 (y,-x)', () {
      final s = SensorNormalizer.fromNative(
        gx: 0, gy: 0, gz: 0,
        ax: 9.81, ay: 0, az: 0,
        timestampMs: 0,
        rotation: 270,
      );
      expect(s.ax, closeTo(0, 1e-9));
      expect(s.ay, closeTo(-9.81, 1e-9),
          reason: '反向横屏，符号要与 90° 相反');
    });

    test('倒置 180°：两个轴都取反', () {
      final s = SensorNormalizer.fromNative(
        gx: 0, gy: 0, gz: 0,
        ax: 1.0, ay: 9.81, az: 0,
        timestampMs: 0,
        rotation: 180,
      );
      expect(s.ax, closeTo(-1.0, 1e-9));
      expect(s.ay, closeTo(-9.81, 1e-9));
    });

    test('以 g 为单位时自动乘 9.80665', () {
      final s = SensorNormalizer.fromNative(
        gx: 0, gy: 0, gz: 0,
        ax: 0, ay: 1.0, az: 0, // 1g
        timestampMs: 0,
        inG: true,
      );
      expect(s.ay, closeTo(9.80665, 1e-6));
    });

    test('rotation 取模 —— 传 450° 等价于 90°', () {
      final a = SensorNormalizer.fromNative(
        gx: 0, gy: 0, gz: 0, ax: 9.81, ay: 0, az: 0,
        timestampMs: 0, rotation: 450,
      );
      final b = SensorNormalizer.fromNative(
        gx: 0, gy: 0, gz: 0, ax: 9.81, ay: 0, az: 0,
        timestampMs: 0, rotation: 90,
      );
      expect(a.ay, closeTo(b.ay, 1e-9));
      expect(a.ax, closeTo(b.ax, 1e-9));
    });

    test('flipY 开关能翻转 y（某端轴定义变了时的兜底）', () {
      final normal = SensorNormalizer.fromNative(
        gx: 0, gy: 0, gz: 0, ax: 0, ay: 9.81, az: 0,
        timestampMs: 0,
      );
      final flipped = SensorNormalizer.fromNative(
        gx: 0, gy: 0, gz: 0, ax: 0, ay: 9.81, az: 0,
        timestampMs: 0, flipY: true,
      );
      expect(normal.ay, closeTo(9.81, 1e-9));
      expect(flipped.ay, closeTo(-9.81, 1e-9));
    });

    test('looksLikeGravityUnits —— 少样本时不误判', () {
      // 样本不足直接 false，避免挥动瞬间被误判成 g 单位
      expect(SensorNormalizer.looksLikeGravityUnits([1, 2, 3]), isFalse);
      // 8 个全小值 → 判定为 g
      expect(
        SensorNormalizer.looksLikeGravityUnits(List.filled(8, 1.0)),
        isTrue,
      );
      // 有一个大值 → 不是 g
      expect(
        SensorNormalizer.looksLikeGravityUnits([1, 1, 1, 1, 1, 1, 1, 25.0]),
        isFalse,
      );
    });
  });
}
