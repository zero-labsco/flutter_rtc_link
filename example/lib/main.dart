import 'package:flutter/material.dart';

import 'device_demo_page.dart';
import 'diagnostics_demo_page.dart';
import 'resilience_demo_page.dart';
import 'robot_demo_page.dart';
import 'rtc_demo_page.dart';
import 'widgets/instrument.dart';

/// Example app entry point. / Example 应用入口。
void main() {
  runApp(const RtcLinkExampleApp());
}

/// Root app widget. / 根组件。
///
/// Dark instrument-panel theme — a control-room surface for a link / device
/// tool, deliberately not a Material card wall.
/// 暗色仪表台主题——面向链路 / 设备工具的播控室表面，刻意不做成 Material
/// 卡片墙。
class RtcLinkExampleApp extends StatelessWidget {
  const RtcLinkExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter RTC Link',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomePage(),
    );
  }
}

/// Tabbed host for the demos. / 演示的标签宿主。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  static const List<({String label, IconData icon, Widget page})> _tabs =
      <({String label, IconData icon, Widget page})>[
        (label: 'link', icon: Icons.sensors, page: RtcDemoPage()),
        (label: 'robot', icon: Icons.gamepad, page: RobotDemoPage()),
        (label: 'device', icon: Icons.memory, page: DeviceDemoPage()),
        (label: 'diag', icon: Icons.monitor_heart, page: DiagnosticsDemoPage()),
        (label: 'resil', icon: Icons.healing, page: ResilienceDemoPage()),
      ];

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('RTC LINK'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: StatusChip(
              label: 'example',
              color: status.ok,
              active: false,
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(
          key: ValueKey<int>(_index),
          child: _tabs[_index].page,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: <Widget>[
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon, size: 20),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
