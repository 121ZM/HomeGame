/// 界面冒烟测试 —— 不上真机也能验证界面能构建出来。
///
/// 说明：这里**不**测传感器与 UDP（那些要真机），只测：
/// - App 能启动、连接页渲染出来
/// - 8 个色块可点、点了会切换选中态
///
/// 传感器通道在测试环境里会走 `MissingPluginException` 优雅降级，
/// 所以不需要任何 mock。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homegame_controller/main.dart';
import 'package:homegame_controller/ui/theme.dart';

void main() {
  testWidgets('App 启动后停在连接页', (tester) async {
    await tester.pumpWidget(const HomeGameApp());

    expect(find.text('HomeGame 手柄'), findsOneWidget);
    expect(find.text('选你的颜色'), findsOneWidget);
    expect(find.text('大屏地址'), findsOneWidget);
    expect(find.text('连 接'), findsOneWidget);
  });

  testWidgets('8 个玩家色块都在', (tester) async {
    await tester.pumpWidget(const HomeGameApp());
    for (var i = 1; i <= 8; i++) {
      expect(find.text('$i'), findsOneWidget, reason: '缺少玩家号 $i');
    }
  });

  testWidgets('点色块会切换选中态', (tester) async {
    await tester.pumpWidget(const HomeGameApp());

    // 默认选 1，点 5
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    // 找到「5」所在色块的 AnimatedContainer，选中态描边 width 应为 3
    final box = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('5'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final deco = box.decoration as BoxDecoration;
    final border = deco.border as Border;
    expect(border.top.width, 3, reason: '选中的色块描边应该更粗');
  });

  testWidgets('没填 IP 直接点连接会提示', (tester) async {
    await tester.pumpWidget(const HomeGameApp());

    await tester.tap(find.text('连 接'));
    await tester.pump();

    expect(find.text('请先填大屏的 IP 地址'), findsOneWidget);
  });

  testWidgets('主题主色是番茄红', (tester) async {
    final theme = buildTheme();
    expect(theme.colorScheme.primary, AppColors.accent);
  });
}
