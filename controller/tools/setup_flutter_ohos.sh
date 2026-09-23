#!/usr/bin/env bash
# 安装 HomeGame 手机端需要的 Flutter（鸿蒙适配版）到 ~/DEV/flutter-ohos
#
# 为什么不用官方 Flutter：
#   鸿蒙 HarmonyOS NEXT（5.0+）**不兼容 Android APK**，必须打成 .hap。
#   只有鸿蒙适配版 Flutter 能产出 .hap；官方 Flutter 编不出来。
#   Android 也用同一个 SDK 编 —— 一套代码两端跑，版本不会漂。
#
# 为什么钉 oh-3.35.7-release：
#   官方 Flutter 已经 3.47.x，但鸿蒙适配线还在 3.35.x，落后约 4 个月。
#   这是「能用 .hap」与「用最新 Dart」之间的取舍 —— 我们选能用。
#
# 用法：bash tools/setup_flutter_ohos.sh
set -euo pipefail

FLUTTER_DIR="${FLUTTER_DIR:-$HOME/DEV/flutter-ohos}"
BRANCH="${BRANCH:-oh-3.35.7-release}"
REPO="https://gitcode.com/openharmony-tpc/flutter_flutter.git"

# 国内镜像：pub 与 flutter 资源各一个。华为的 OHOS 引擎包自带专用源，不用配。
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
# 上游不是标准 remote，不给这个变量 flutter 会一直唠叨
export FLUTTER_GIT_URL="$REPO"

echo "==> 1/4 克隆 $BRANCH 到 $FLUTTER_DIR"
if [ -d "$FLUTTER_DIR/.git" ]; then
  echo "    已存在，跳过克隆"
else
  rm -rf "$FLUTTER_DIR"
  # --depth 1 省时间，但**会导致版本号解析成 0.0.0-unknown** —— 见第 2 步
  git clone --depth 1 --single-branch --branch "$BRANCH" "$REPO" "$FLUTTER_DIR"
fi

echo "==> 2/4 补版本 tag"
# ⚠️ 浅克隆没有 tag 历史，`git describe` 报「没有发现名称」，
#    flutter 于是把版本算成 0.0.0-unknown，
#    结果 pub get 时 flutter_test 因「要求 Flutter >=3.18.0」被拒 → 依赖解析失败。
#    手动补一个 tag，describe 就能算出 3.35.7-0-gXXXX。
cd "$FLUTTER_DIR"
if ! git tag | grep -qx "3.35.7"; then
  git tag 3.35.7
  echo "    已补 tag 3.35.7"
else
  echo "    tag 已存在"
fi
git describe --match "*.*.*" --first-parent --long --tags

echo "==> 3/4 打本地补丁：让 flutter test 不需要鸿蒙 SDK"
# 原版 project.dart 里 ensureReadyForPlatformSpecificTooling() 无脑调用
#   hvigor.updateLocalProperties(project: parent)
# 该函数 requireHarmonySdk 默认 true，没装鸿蒙 SDK 就 throwToolExit，
# **连带把 `flutter test` 也拦死** —— 纯 Dart 单测凭什么要鸿蒙工具链。
# 这里把调用点改成 requireHarmonySdk: false（有 SDK 照常写，没有就跳过）。
# 真正编 .hap 的路径另有检查，不受影响。
# ⚠️ 升级 Flutter SDK 会覆盖此补丁，重装后需重跑本脚本。
PATCH_FILE="packages/flutter_tools/lib/src/project.dart"
if grep -q "requireHarmonySdk: false);$" <(grep -A0 "hvigor.updateLocalProperties(project: parent" "$PATCH_FILE" | head -2) 2>/dev/null; then
  echo "    补丁已存在"
elif grep -q "requireHarmonySdk: false" "$PATCH_FILE"; then
  echo "    补丁已存在"
else
  python3 - "$PATCH_FILE" <<'PY'
import sys, io
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()
old = "    hvigor.updateLocalProperties(project: parent);\n    hvigor.installHvigorPlugin(parent.ohos);"
new = ("    // 本地补丁（HomeGame）：原版 requireHarmonySdk 默认 true，导致 `flutter test`\n"
       "    // 在没有 OHOS SDK 的机器上直接 exit 1。纯 Dart 单测不需要鸿蒙工具链。\n"
       "    hvigor.updateLocalProperties(project: parent, requireHarmonySdk: false);\n"
       "    hvigor.installHvigorPlugin(parent.ohos);")
if old not in s:
    print("    !! 未找到待替换片段，可能 SDK 版本变了，请手工核对 " + p)
    sys.exit(1)
io.open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
print("    补丁写入成功")
PY
fi

echo "==> 4/4 引导下载 Dart SDK 与工具链（约 200MB，华为云 OBS）"
rm -f bin/cache/flutter_tools.stamp
./bin/flutter --version

echo
echo "完成。把下面这行加进 shell 配置："
echo "    export PATH=\"$FLUTTER_DIR/bin:\$PATH\""
echo "    export FLUTTER_GIT_URL=\"$REPO\""
echo
echo "建议同时写死镜像（否则每次都要 export）："
echo "    export PUB_HOSTED_URL=https://pub.flutter-io.cn"
echo "    export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"
