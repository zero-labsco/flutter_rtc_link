// ignore_for_file: avoid_print

import 'dart:io';

/// Module boundary self-check / 模块边界自检
///
/// Usage / 用法:
/// ```bash
/// dart run tool/check_module_boundaries.dart
/// ```
///
/// `lib/src/` is split into feature modules (core, engines, publishers,
/// subscribers, relay, resilience, platforms, device, robot, ble, widgets) and
/// the package ships one public entry point per module. That split only means
/// something while the dependency directions hold: `core` must stay a
/// dependency-free shared kernel, the resilience layer must keep working
/// against abstractions only, and `device` / `robot` / `ble` must never reach
/// into each other.
/// `lib/src/` 按功能模块划分（core、engines、publishers、subscribers、relay、
/// resilience、platforms、device、robot、ble、widgets），包为每个模块提供独立
/// 公开入口。只有依赖方向成立时这种拆分才有意义：`core` 必须保持零依赖的共享
/// 内核，韧性层只能面向抽象工作，`device` / `robot` / `ble` 绝不互相伸手。
///
/// Conventions rot; a script does not. This one fails with a non-zero exit code
/// on the first forbidden import so CI blocks the regression.
/// 约定会腐化，脚本不会。本脚本在发现第一条违规 import 时以非零退出码失败，
/// 由 CI 拦截回归。
void main() {
  final problems = <String>[..._checkInternalImports(), ..._checkEntryPoints()];

  if (problems.isNotEmpty) {
    print('');
    print('${problems.length} module boundary problem(s) found:');
    for (final p in problems) {
      print('  x $p');
    }
    print('');
    print(
      'See AGENTS.md ("Module boundaries"): core and resilience must not '
      'depend on device / robot / ble, and device / robot / ble must stay '
      'mutually independent.',
    );
    exit(1);
  }
  print('All module boundaries hold.');
}

/// Forbidden import directions, keyed by the importing module.
/// 禁止的 import 方向，以发起导入的模块为键。
///
/// `core -> engines` is deliberately allowed: `RtcEngine.create` is a factory
/// that has to name its concrete implementations. Everything else here is a
/// real inversion that would drag a feature module into the shared kernel.
/// `core -> engines` 是刻意放行的：`RtcEngine.create` 是工厂，必须点名具体实现。
/// 其余条目都是真实的倒置，会把功能模块拖进共享内核。
const Map<String, Set<String>> _forbidden = <String, Set<String>>{
  'core': <String>{'device', 'robot', 'ble', 'platforms', 'widgets', 'relay'},
  'resilience': <String>{
    'device',
    'robot',
    'ble',
    'platforms',
    'widgets',
    'engines',
    'relay',
  },
  'device': <String>{'robot'},
  'robot': <String>{'device'},
  'ble': <String>{'device', 'robot'},
};

/// Entry points and the `src/` prefixes they must not re-export.
/// 各入口及其禁止再导出的 `src/` 前缀。
const Map<String, Set<String>> _entryPointForbidden = <String, Set<String>>{
  'lib/flutter_rtc_link.dart': <String>{
    'src/device/',
    'src/robot/',
    'src/ble/',
  },
  'lib/flutter_rtc_link_device.dart': <String>{'src/robot/'},
  'lib/flutter_rtc_link_robot.dart': <String>{'src/device/'},
};

/// Matches a relative import or export directive. / 匹配相对路径的 import / export 指令。
final RegExp _relativeDirective = RegExp(
  r"^(?:import|export)\s+'(\.[^']*)'",
  multiLine: true,
);

/// Scans every file under `lib/src/` for forbidden cross-module imports.
/// 扫描 `lib/src/` 下每个文件，查找被禁止的跨模块 import。
List<String> _checkInternalImports() {
  final problems = <String>[];
  final srcDir = Directory('lib/src');
  if (!srcDir.existsSync()) {
    problems.add('lib/src: directory not found.');
    return problems;
  }

  final files =
      srcDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final rel = _toPosix(file.path);
    final from = _moduleOf(rel);
    if (from == null) continue;
    final banned = _forbidden[from];
    if (banned == null) continue;

    final content = file.readAsStringSync();
    for (final match in _relativeDirective.allMatches(content)) {
      final target = _resolve(rel, match.group(1)!);
      if (!target.startsWith('lib/src/')) continue;
      final to = _moduleOf(target);
      if (to == null || to == from) continue;
      if (banned.contains(to)) {
        problems.add(
          '$rel imports $target — `$from` must not depend on `$to`.',
        );
      }
    }
  }
  return problems;
}

/// Checks that each public entry point stays within its own module.
/// 校验每个公开入口只导出本模块的内容。
List<String> _checkEntryPoints() {
  final problems = <String>[];
  for (final entry in _entryPointForbidden.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) {
      problems.add('${entry.key}: entry point not found.');
      continue;
    }
    final content = file.readAsStringSync();
    for (final match in _relativeDirective.allMatches(content)) {
      final target = _resolve(entry.key, match.group(1)!);
      for (final prefix in entry.value) {
        if (target.startsWith(prefix)) {
          problems.add(
            '${entry.key} re-exports $target — this entry point must not '
            'expose `$prefix`.',
          );
        }
      }
    }
  }
  return problems;
}

/// Module name of a `lib/src/...` path (null when not under `lib/src/`).
/// `lib/src/...` 路径所属的模块名（不在 `lib/src/` 下时返回 null）。
String? _moduleOf(String posixPath) {
  if (!posixPath.startsWith('lib/src/')) return null;
  final rest = posixPath.substring('lib/src/'.length);
  final slash = rest.indexOf('/');
  // Files directly under lib/src/ belong to no module. / 直接位于 lib/src/ 下的文件不属于任何模块。
  if (slash < 0) return null;
  return rest.substring(0, slash);
}

/// Resolves a relative directive against the importing file.
/// 将相对路径指令按导入方文件解析为绝对路径。
String _resolve(String fromPath, String relative) {
  final parts = fromPath.split('/')..removeLast();
  for (final segment in relative.split('/')) {
    if (segment == '.' || segment.isEmpty) continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(segment);
    }
  }
  return parts.join('/');
}

/// Normalizes Windows separators so path logic stays identical on every OS.
/// 归一化 Windows 分隔符，使路径逻辑在各平台一致。
String _toPosix(String path) => path.replaceAll('\\', '/');
