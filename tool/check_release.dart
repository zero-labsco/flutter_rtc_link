// ignore_for_file: avoid_print

import 'dart:io';

/// Pre-release version consistency self-check / 发版前版本一致性自检
///
/// Usage / 用法:
/// ```bash
/// dart run tool/check_release.dart
/// ```
///
/// The most common release mistake is not code but a version string left stale
/// in one place: `pubspec.yaml`, `ios/flutter_rtc_link.podspec`, the install
/// snippets and upgrade callouts in both READMEs, and the top of
/// `CHANGELOG.md`. Missing any of them leaves the published package
/// contradicting its own docs.
/// 发版最容易出错的地方不是代码，而是"版本号忘了改全一处"：
/// `pubspec.yaml`、`ios/flutter_rtc_link.podspec`、两个 README 的安装片段与
/// 升级提示、以及 `CHANGELOG.md` 顶部。漏掉任何一处都会让 pub.dev 上的包与
/// 文档相互矛盾。
///
/// This script treats `pubspec.yaml`'s `version` as the single source of truth,
/// verifies every other location against it, and fails with a non-zero exit
/// code on any mismatch so CI can block the release.
/// 本脚本以 `pubspec.yaml` 的 `version` 为唯一真值，逐处核对，
/// 任何一处不一致即以非零退出码失败（供 CI 拦截）。
void main() {
  final version = _readPubspecVersion();
  if (version == null) {
    _fail('pubspec.yaml: cannot parse the top-level `version:` field.');
    exit(1);
  }
  print('Release version (from pubspec.yaml): $version');

  final problems = <String>[
    ..._checkPodspec(version),
    ..._checkReadme('README.md', version),
    ..._checkReadme('README_zh.md', version),
    ..._checkChangelog(version),
  ];

  if (problems.isNotEmpty) {
    print('');
    print('${problems.length} version problem(s) found:');
    for (final p in problems) {
      print('  ✗ $p');
    }
    print('');
    print(
      'Bump every occurrence to $version (see AGENTS.md release checklist).',
    );
    exit(1);
  }
  print('✅ All version references are consistent with $version.');
}

/// Version string pattern (X.Y.Z) / 版本串正则（X.Y.Z）
final RegExp _anyVersion = RegExp(r'\d+\.\d+\.\d+');

/// Read the top-level version from pubspec.yaml / 读取 pubspec.yaml 顶层的 version
String? _readPubspecVersion() {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) return null;
  // Only scan the header so dependency constraints are not mistaken for it.
  // 只取文件头部（避免命中 dependency 里的 version 约束）。
  final head = file.readAsStringSync().split('\n').take(40).join('\n');
  final match = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$',
    multiLine: true,
  ).firstMatch(head);
  return match?.group(1);
}

/// Read a file's content, report when missing / 读取文件内容，缺失时报错
String? _read(String path, List<String> problems) {
  final file = File(path);
  if (!file.existsSync()) {
    problems.add('$path: file not found.');
    return null;
  }
  return file.readAsStringSync();
}

/// Check the iOS podspec version / 校验 iOS podspec 版本
List<String> _checkPodspec(String version) {
  const path = 'ios/flutter_rtc_link.podspec';
  final problems = <String>[];
  final content = _read(path, problems);
  if (content == null) return problems;
  final match = RegExp(r"s\.version\s*=\s*'([^']+)'").firstMatch(content);
  if (match == null) {
    problems.add('$path: no `s.version` found.');
  } else if (match.group(1) != version) {
    problems.add('$path: s.version is ${match.group(1)}, expected $version.');
  }
  return problems;
}

/// Check README install snippets & callouts / 校验 README 里的安装片段与升级提示
///
/// Only "version-sensitive" lines are checked (those declaring the
/// `flutter_rtc_link:` dependency or referencing a `release/v` archive branch);
/// historical prose such as "since v0.1.0" is intentionally ignored to avoid
/// false positives.
/// 只核对"版本敏感行"（含 `flutter_rtc_link:` 依赖声明或 `release/v` 归档分支
/// 引用的行），历史性叙述（如 "since v0.1.0"）不参与校验，避免误报。
List<String> _checkReadme(String path, String version) {
  final problems = <String>[];
  final content = _read(path, problems);
  if (content == null) return problems;

  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final isSensitive =
        line.contains('flutter_rtc_link:') ||
        line.contains('release/v') ||
        line.contains('^$version') ||
        line.contains(RegExp(r'\^\d+\.\d+\.\d+'));
    if (!isSensitive) continue;
    for (final match in _anyVersion.allMatches(line)) {
      final found = match.group(0)!;
      if (found != version) {
        problems.add('$path:${i + 1}: found $found, expected $version.');
      }
    }
  }

  // Hard requirement: both install snippets must exist, otherwise the doc
  // structure changed (or the snippet was deleted by accident).
  // 硬性要求：两个安装片段必须存在，否则说明文档结构变了/被误删。
  if (!content.contains('flutter_rtc_link: ^$version')) {
    problems.add('$path: missing the `flutter_rtc_link: ^$version` snippet.');
  }
  if (!content.contains('release/v$version')) {
    problems.add('$path: missing the `ref: release/v$version` git snippet.');
  }
  return problems;
}

/// Check the CHANGELOG top version / 校验 CHANGELOG 顶部版本
List<String> _checkChangelog(String version) {
  const path = 'CHANGELOG.md';
  final problems = <String>[];
  final content = _read(path, problems);
  if (content == null) return problems;
  final match = RegExp(
    r'^##\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$',
    multiLine: true,
  ).firstMatch(content);
  if (match == null) {
    problems.add('$path: no `## X.Y.Z` section found at the top.');
  } else if (match.group(1) != version) {
    problems.add(
      '$path: top section is ${match.group(1)}, expected $version '
      '(add a `## $version` entry before releasing).',
    );
  }
  return problems;
}

/// Print a fatal error / 打印一条致命错误
void _fail(String message) => print('✗ $message');
