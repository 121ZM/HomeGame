/// 手机端界面。
///
/// 视觉基调跟大屏一致：奶油纸底 + 墨色粗描边 + 番茄红强调（见大屏 `ui_kit.gd`）。
/// 但手机是**竖屏、单手、近距离**，所以：
/// - 字号比大屏小得多（大屏按「隔客厅看 55 寸电视」定的，直接搬过来会巨大）
/// - 触控目标最小 48dp
/// - 深色也 OK —— 手机常在全黑环境玩，但这里用亮色保持与大屏同族
library;

import 'package:flutter/material.dart';

/// 配色。数值与大屏 `ui_kit.gd` 对齐，命名保持一致，方便对照。
class AppColors {
  AppColors._();

  static const Color ink = Color(0xFF221F1A); // 暖褐黑，所有描边与主文字
  static const Color inkSoft = Color(0xFF5C564A); // 次级文字
  static const Color inkMute = Color(0xFFB3A98F); // 提示、禁用
  static const Color paper = Color(0xFFFFFDF6); // 卡片底
  static const Color paperAlt = Color(0xFFEFE8D8); // 次级底
  static const Color backdrop = Color(0xFFF7F2E7); // 页面底（奶油纸）
  static const Color line = Color(0xFFD9D0BC); // 分割线
  static const Color accent = Color(0xFFE8543F); // 番茄红，主行动
  static const Color accentDeep = Color(0xFFC93F2C); // 番茄红按下态
  static const Color ok = Color(0xFF2F9E6E); // 已连接
  static const Color waiting = Color(0xFFE2A400); // 连接中
  static const Color seatJoined = Color(0xFF2BA39A); // 席位已占
}

/// 主题。跟大屏一样：全圆角、粗描边、硬阴影。
ThemeData buildTheme() {
  const radius = 18.0;
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.backdrop,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      primary: AppColors.accent,
      surface: AppColors.paper,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.backdrop,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    textTheme: const TextTheme(
      // 手机字号：标题 24 / 正文 16 / 说明 14
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      bodyMedium: TextStyle(fontSize: 16, color: AppColors.ink),
      bodySmall: TextStyle(fontSize: 14, color: AppColors.inkSoft),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.paper,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AppColors.ink, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AppColors.line, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AppColors.accent, width: 2.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.ink, width: 2.5),
        ),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    ),
  );
}
