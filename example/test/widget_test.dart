// Smoke test for the example app.
// 示例应用的冒烟测试。
//
// The default `flutter create` counter test does not apply here: this example
// is a real plugin demo (no counter, no "+" button), so that template fails to
// compile/run against the actual app.
// 默认的 `flutter create` 计数器测试在此不适用：本示例是真实的插件演示应用
// （无计数器、无 "+" 按钮），原模板无法对真实 App 编译/运行。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_rtc_link_example/main.dart';

void main() {
  testWidgets('example app builds and shows its title', (tester) async {
    await tester.pumpWidget(const RtcLinkExampleApp());

    // The app bar carries the product name. / 应用栏显示产品名称。
    expect(find.text('RTC LINK'), findsOneWidget);

    // Five demo tabs are exposed through the bottom navigation.
    // 底部导航暴露五个演示页签。
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
