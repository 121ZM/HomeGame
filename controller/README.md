# 手机端控制器（controller/）

把手机变成大屏游戏的**体感手柄**。安卓与鸿蒙 HarmonyOS NEXT 双端，一套 Dart 代码。

```
controller/
├── lib/
│   ├── net/           协议与传输（与大屏对接的全部逻辑）
│   │   ├── protocol.dart        协议 v2 字节编解码（纯逻辑）
│   │   └── udp_transport.dart   UDP 门面，字节交原生发
│   ├── sensor/        传感器读取与坐标规整
│   │   └── sensor_source.dart   统一坐标系（易错点都在这）
│   ├── platform/      平台差异封装（安卓 / 鸿蒙各一条通道）
│   ├── ui/            界面
│   └── main.dart      入口
├── android/           安卓原生（Kotlin：SensorManager + DatagramSocket）
├── ohos/              鸿蒙原生（ArkTS：@ohos.sensor + @ohos.net.socket）
├── test/              纯 Dart 自校验，**不需要真机、不需要大屏**
└── tools/
    └── setup_flutter_ohos.sh    装 Flutter 鸿蒙适配版（含两处必需的补丁）
```

## 协议

权威定义：`screen/scripts/net/net_protocol.gd`（大屏侧 Godot 实现）
对接文档：`docs/controller-protocol.md`
本端实现：`lib/net/protocol.dart`

**三处必须永远一致，改一处必须改三处。**

## 环境搭建

### Flutter 用鸿蒙适配版，不是官方版

| | 官方 Flutter | 鸿蒙适配版 |
|---|---|---|
| 版本 | 3.47.x | **3.35.x**（落后约 4 个月） |
| 能编 .hap | ❌ | ✅ |
| 能编 .apk | ✅ | ✅ |

**为什么必须用适配版**：HarmonyOS NEXT（纯血鸿蒙）**不兼容 Android APK**，只能装 `.hap`。
官方 Flutter 产不出 `.hap`。安卓侧也一起用适配版编 —— 一套代码两端跑，版本不漂。

一键装（含两处必需的补丁，脚本幂等可重跑）：

```bash
bash tools/setup_flutter_ohos.sh
```

脚本干的事与**为什么**：

1. **浅克隆 `oh-3.35.7-release` 分支**（gitcode.com/openharmony-tpc/flutter_flutter）。
2. **补一个 `3.35.7` tag** —— 浅克隆没有 tag 历史，`git describe` 算不出，
   Flutter 于是把版本读成 `0.0.0-unknown`，
   接着 `pub get` 会因为「`flutter_test` 要求 Flutter >=3.18.0」而**依赖解析失败**。
   手动补 tag 后 describe 得 `3.35.7-0-g3dbfa8d7`，一切正常。
3. **给 SDK 源码打一处补丁**（`packages/flutter_tools/lib/src/project.dart`）——
   见下节。**升级 SDK 会覆盖，重装后必须重跑脚本。**
4. 引导下载 Dart SDK（约 200MB，走华为云 OBS `flutter-ohos.obs.cn-south-1.myhuaweicloud.com`）。

装完加 PATH：

```bash
export PATH="$HOME/DEV/flutter-ohos/bin:$PATH"
export FLUTTER_GIT_URL="https://gitcode.com/openharmony-tpc/flutter_flutter.git"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

### SDK 补丁：让 `flutter test` 不再要求鸿蒙 SDK

原版 `project.dart` 的 `ensureReadyForPlatformSpecificTooling()` 无脑调用：

```dart
hvigor.updateLocalProperties(project: parent);   // requireHarmonySdk 默认 true
```

该函数在 `globals.hmosSdk == null` 时直接 `throwToolExit`。
而 `flutter test` 会走这个 readiness 路径 →
**在没装鸿蒙 SDK 的机器上，`flutter test` 静默 exit 1，一个测试都不跑**
（输出只有一行 `[!] No Hmos SDK found.`，很容易误判成「测试通过」）。

补丁把这一处改成 `requireHarmonySdk: false`：有 SDK 照常写 local.properties，
没有就跳过。真正编 `.hap` 的路径另有独立检查（`build_hap.dart:70` 等），不受影响。

### 测试

```bash
flutter test          # 纯 Dart，不需要真机 / 不需要大屏 / 不需要鸿蒙 SDK
```

覆盖：字节序、坐标、名字截断、坏包拒绝、u16/u32 边界、随机往返 200 次。

## 原生侧

### 安卓（`android/`）

- 传感器：`SensorManager` + `TYPE_ACCELEROMETER` / `TYPE_GYROSCOPE`，
  采样率 `SENSOR_DELAY_GAME`（约 50–100Hz）
- UDP：`java.net.DatagramSocket`
- 权限：`INTERNET`、`VIBRATE`、
  `HIGH_SAMPLING_RATE_SENSORS`（Android 12+ 要 >200Hz 采样时需要）

### 鸿蒙（`ohos/`）

- 传感器：`@ohos.sensor`，`ACCELEROMETER` / `GYROSCOPE`，
  `sensor.on(id, cb, {interval: 20000000})` —— ⚠️ interval 单位是**纳秒**，
  `20000000ns = 20ms = 50Hz`（对齐安卓的 `SENSOR_DELAY_GAME`）。
  想 60Hz 用 `16666667`。**别写成 `20000`** —— 那是 50kHz，白耗电。
- UDP：`@ohos.net.socket` 的 `constructUDPSocketInstance()`
- 权限：`ohos.permission.INTERNET`、`ohos.permission.ACCELEROMETER`、
  `ohos.permission.GYROSCOPE` —— 后两个属 `system_grant`，**安装即授权、不弹窗**
- 权限：`ohos.permission.INTERNET`、`ohos.permission.ACCELEROMETER`、
  `ohos.permission.GYROSCOPE`（后两个 system_grant）
- 隐私合规：**不能在用户同意隐私政策前读传感器**（上架华为应用市场会查）
- 编译需要 DevEco Studio + HarmonyOS SDK；`ohpm` / `hvigorw` 要在 PATH 里

### 通道名

两端必须与 `lib/net/udp_transport.dart` 的 `channelName` 一致：

```
cn.zm.homegame/udp
```

方法：`open({port}) -> {ok, error?}` / `send({host, port, bytes}) -> {ok, error?}` / `close()`

## 两个「写错也不报错」的坑

1. **字节序** —— 协议全是小端。Dart `ByteData` 的 `setUint16/setUint32/setFloat32`
   **默认是大端**，必须显式传 `Endian.little`；Kotlin `ByteBuffer` 默认也是大端，
   要 `order(ByteOrder.LITTLE_ENDIAN)`。写反了数值变成天文数字或 NaN，**代码不抛异常**。
   `test/protocol_test.dart` 里专门有一组断言守着。
2. **坐标轴** —— 协议要求加速度 **y 向上为正、静止竖持 ≈ +9.81**。
   安卓 / 鸿蒙原生读数都已经符合，**不要自作聪明加负号**。
   真机第一件事是看诊断页：显示 `ay ≈ +9.81` 才对。显示 `-9.81` 才需要翻。

### 通道契约

两端**必须**与 Dart 侧完全一致 —— Dart 只有一份代码，不一致就要在真机联调时排查半天。

| 通道 | 类型 | 方法 / 字段 |
|---|---|---|
| `cn.zm.homegame/udp` | MethodChannel | `open({port})` / `send({host, port, bytes})` / `close()` |
| `cn.zm.homegame/sensor` | EventChannel | 推 `{gx, gy, gz, ax, ay, az, ts, rot}` |

返回值一律是 `{ok: bool, error: String?}` —— **失败也走 `success`，不抛异常**
（Dart 侧把发送失败当正常路径，降级成计数器；抛异常会打断 60Hz 主循环）。

传感器字段约定：

| 字段 | 单位 | 说明 |
|---|---|---|
| `gx/gy/gz` | rad/s | 角速度 |
| `ax/ay/az` | m/s² | 含重力，**y 向上为正** |
| `ts` | ms | 传感器硬件时间戳（两端统一：纳秒 ÷ 1e6） |
| `rot` | 度 | 屏幕旋转角，0/90/180/270。缺省按 0 处理 |

### ⚠️ 鸿蒙 ArkTS 的写法（写错就编不过）

这几条都不能靠读文档猜，是实测校正过的（详见全局 skill `flutter-ohos-harmonyos-setup`）：

| 坑 | 错误写法 | 正确写法 |
|---|---|---|
| BinaryMessenger 是私有字段 | `engine.dartExecutor.binaryMessenger` | `engine.dartExecutor.getBinaryMessenger()` |
| `argument()` 不是泛型 | `call.argument<number>('port')` | `call.argument('port') as number` |
| UDP data 要 ArrayBuffer | `udp.send({data: uint8})` | `udp.send({data: uint8.buffer})` |
| UDP address 是一个对象 | `{data, address: host, port}` | `{data, address: {address: host, port}}` |
| `display.on('change')` 回调参数 | `(d: display.Display) => d.rotation` | `(displayId: number) => /* 重新取 Display */` |
| `Display.rotation` 是枚举 | `d.rotation * 90` | `switch` 显式映射 |
