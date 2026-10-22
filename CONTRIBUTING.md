# Contributing to Flutter RTC Link

First off, thanks for taking the time to contribute!

> 感谢你抽出时间为本项目做贡献！以下是参与贡献 Flutter RTC Link 的指引，内容以建议为主而非强制规则。请运用你的判断力，也欢迎通过 PR 提出对本文档的改进。

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Code Style](#code-style)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Reporting Bugs](#reporting-bugs)
- [Suggesting Enhancements](#suggesting-enhancements)
- [Release Process](#release-process)

## Code of Conduct

This project is licensed under MPL-2.0. By participating, you are expected to uphold a respectful and collaborative tone. Please be kind to maintainers and other contributors.

> 本项目采用 MPL-2.0 许可证。参与贡献请保持尊重、协作的态度，对维护者和其他贡献者友善。

## Getting Started

### Prerequisites

- Flutter >= 3.35.0 (stable channel)
- Dart >= 3.9.0
- Android Studio / Xcode (for platform-specific testing; the DPP and foreground-service modules are Android-only)
- Node.js (only needed to preview the docs site locally: `cd website && npm ci && npm run build`. The site build runs in CI, so committing does not require Node)
- Git

> 环境要求：Flutter >= 3.35.0（stable 通道）、Dart >= 3.9.0、Android Studio / Xcode（用于平台测试；DPP 与前台服务模块仅 Android）、Git。

### Setup

1. Fork the repository on GitHub.
2. Clone your fork locally:

   ```bash
   git clone https://github.com/<your-username>/flutter_rtc_link.git
   cd flutter_rtc_link
   ```

3. Add the upstream remote to keep your fork in sync:

   ```bash
   git remote add upstream https://github.com/zero-labsco/flutter_rtc_link.git
   ```

4. Install dependencies:

   ```bash
   flutter pub get
   cd example && flutter pub get && cd ..
   ```

5. Run the example app to verify everything works:

   ```bash
   cd example && flutter run
   ```

> 本地初始化步骤：Fork 仓库 → clone 你的 fork → 添加 upstream 远程 → 安装依赖 → 运行 example 验证。

## Development Workflow

1. Create a feature branch from `main`:

   ```bash
   git checkout -b feat/your-feature-name
   # or
   git checkout -b fix/your-bug-fix
   ```

2. Make your changes. Keep commits focused and write clear commit messages (see [Conventional Commits](https://www.conventionalcommits.org/)).

3. Run all checks before committing (see [Code Style](#code-style) and [Testing](#testing)).

4. Push to your fork and open a Pull Request against `main`.

> 开发流程：从 `main` 切出 `feat/` `fix/` 分支 → 提交时保持 commit 聚合并写清晰消息（遵循 Conventional Commits） → 提交前跑完所有检查 → push 到你的 fork 并向 `main` 发起 PR。

## Code Style

This project follows the [Effective Dart](https://dart.dev/guides/language/effective-dart) style guide.

> 本项目遵循 [Effective Dart](https://dart.dev/guides/language/effective-dart) 风格指南。

### Pure-English code with bilingual comments

All code (identifiers, string literals, API surface) is **English-only**. Comments are **bilingual with English first and Chinese second**, separated by ` / ` — for example `/// Publishes the camera track / 发布摄像头轨道`. This is a hard constraint of this project.

> 所有代码（标识符、字符串字面量、API 表面）保持**纯英文**。注释为**英中双语、英文在前中文在后**，以 ` / ` 分隔——例如 `/// Publishes the camera track / 发布摄像头轨道`。这是本项目的硬性约定。

Example:

```dart
/// Local publisher for the lead operator role / 牵头操作者角色的本地推流器
class LocalPublisher {
  /// Switches the capture source without renegotiation / 在不重协商的情况下切换采集源
  Future<void> switchCamera(CameraFacing facing);
}
```

### Formatting

Run before committing:

```bash
dart format lib/
dart format example/lib/
```

CI uses `dart format --set-exit-if-changed` to enforce formatting. **All text files in this repository use LF line endings** (enforced by `.gitattributes`); never commit CRLF.

> 提交前运行 `dart format` 格式化。CI 使用 `--set-exit-if-changed` 强制检查。**本仓库所有文本文件统一使用 LF 换行**（由 `.gitattributes` 强制），严禁提交 CRLF。

### Analysis

Run before committing:

```bash
flutter analyze lib/
flutter analyze example/lib/
```

CI uses `flutter analyze` to enforce zero warnings/errors. The rule set lives in `analysis_options.yaml`.

> 提交前运行 `flutter analyze` 静态分析。CI 要求零警告、零错误。规则集见 `analysis_options.yaml`。

### Dependency Versions

Use caret (`^`) constraints in `pubspec.yaml`; do not pin exact versions without reason. Dependabot is configured with `versioning-strategy: increase` to preserve the caret style.

> `pubspec.yaml` 中使用 caret（`^`）约束，无充分理由不要锁定精确版本。Dependabot 已配置 `versioning-strategy: increase` 以保持 caret 风格。

### Line endings

The repository enforces LF via `.gitattributes` (`* text=auto eol=lf`). CI additionally renormalizes the tree before running `dart format`, and the `dart-format-fix.yml` workflow auto-commits formatting fixes.

> 仓库通过 `.gitattributes`（`* text=auto eol=lf`）强制 LF。CI 在运行 `dart format` 前会重新规范化工作树，`dart-format-fix.yml` 工作流会自动提交格式修复。

## Testing

### Run Tests

```bash
flutter test
```

All new features and bug fixes should include tests in the `test/` directory.

> 所有新功能和 bug 修复都应在 `test/` 目录中补充对应测试。

### Test Naming

Name test files `<source_file>_test.dart` and place them under `test/` mirroring the `lib/` structure.

> 测试文件命名 `<源文件>_test.dart`，放在 `test/` 下并镜像 `lib/` 结构。

### Testing on real devices

The RTC link can be validated with a browser plus a real phone, but **device management (BLE / NFC / SoftAP / DPP) requires real hardware** — iOS Simulator has no camera/NFC/Bluetooth and the Android Emulator's BLE/NFC/SoftAP support is effectively unusable.

> RTC 链路可用「浏览器 + 真机」组合验证，但**设备管理（BLE / NFC / SoftAP / DPP）必须有真机**——iOS 模拟器没有摄像头 / NFC / 蓝牙，Android 模拟器的 BLE / NFC / SoftAP 基本不可用。

## Pull Request Process

1. **Update CHANGELOG.md** under an `## [Unreleased]` section (or create one if missing). Describe what changed and why.
2. **Update documentation** if your change affects public API or user-facing behavior (README.md, README_zh.md, `website/pages/`).
3. **Bilingual comments** must be added for any new code.
4. **CI must pass** — the CI workflow runs format check, analyze, and tests on every PR.
5. **Keep PRs focused** — one feature/fix per PR makes review faster.
6. **Link related issues** in the PR description (e.g., `Closes #123`).

> PR 流程：1) 在 CHANGELOG.md 的 `## [Unreleased]` 节更新变更说明；2) 若影响公开 API 或用户行为，同步更新 README/docs；3) 新代码必须加英中双语注释；4) CI 必须通过；5) 一个 PR 只做一件事，便于审查；6) 在 PR 描述中关联相关 Issue（如 `Closes #123`）。

### PR Title Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat: add WHIP publish support`
- `fix: resolve camera switch flicker on Android`
- `docs: update README with OTA section`
- `refactor: simplify grid layout math`
- `test: add watchdog unit tests`
- `chore: bump dependencies`

> PR 标题遵循 Conventional Commits 规范，如 `feat:` / `fix:` / `docs:` / `refactor:` / `test:` / `chore:`。

### PR body template

Use the bilingual body template from [AGENTS.md](AGENTS.md) (EN-primary, ZH-secondary per section), and brand the assistant with **Zero Buddy** (two words, NOT "ZeroBuddy") at the end.

> PR 正文使用 [AGENTS.md](AGENTS.md) 中的双语模板（每节英文为主、中文为辅），文末以 **Zero Buddy**（两个单词，不要写成 "ZeroBuddy"）署名。

## Reporting Bugs

Use the [Bug Report template](https://github.com/zero-labsco/flutter_rtc_link/issues/new?template=bug_report.md). Please include:

- Flutter / Dart version (`flutter doctor -v`)
- Plugin version
- Platform (Android / iOS) and device/OS version
- Engine in use (WHIP/WHEP or LiveKit)
- Minimal reproduction steps
- Expected vs actual behavior
- Logs / screenshots if applicable

> 报告 Bug 请使用 Bug Report 模板，并提供：Flutter/Dart 版本（`flutter doctor -v`）、插件版本、平台与设备系统版本、使用的引擎（WHIP/WHEP 或 LiveKit）、最小复现步骤、期望 vs 实际行为、相关日志/截图。

## Suggesting Enhancements

Use the [Feature Request template](https://github.com/zero-labsco/flutter_rtc_link/issues/new?template=feature_request.md). For general discussion, please use [GitHub Discussions](https://github.com/zero-labsco/flutter_rtc_link/discussions) instead of opening an issue.

> 功能建议请用 Feature Request 模板；一般性讨论请到 [GitHub Discussions](https://github.com/zero-labsco/flutter_rtc_link/discussions)，而非开 Issue。

## Release Process

Releases are managed by maintainers via git tags:

1. Ensure `pubspec.yaml` `version` is updated.
2. Ensure `CHANGELOG.md` is updated with the new version section.
3. Run `dart run tool/check_release.dart` to verify every version reference is consistent.
4. Commit and push to `main`.
5. Create and push a tag `v<version>` (e.g., `v0.1.0`). **Do not name a branch `v<version>`** — a same-named branch/tag pair makes `git push origin v<version>` ambiguous. Use `refs/tags/` to push the tag explicitly:

   ```bash
   git tag v0.1.0
   git push origin refs/tags/v0.1.0
   ```

6. The `pub-publish.yml` workflow will automatically publish to pub.dev and create a GitHub Release.
7. (Optional) Archive the release as a branch named `release/v<version>` (e.g., `release/v0.1.0`). This branch does **not** trigger CI and exists only for archival. Create it via an explicit refspec:

   ```bash
   git push origin <commit>:refs/heads/release/v0.1.0
   ```

> 发布由维护者通过 git tag 管理：1) 更新 `pubspec.yaml` 的 `version`；2) 更新 `CHANGELOG.md` 对应版本节；3) 运行 `dart run tool/check_release.dart` 核对所有版本引用一致；4) 提交并 push 到 `main`；5) 创建并 push `v<version>` tag——**不要把分支命名为 `v<version>`**，请用 `refs/tags/` 显式推送；6) `pub-publish.yml` 工作流会自动发布到 pub.dev 并创建 GitHub Release；7)（可选）以 `release/v<version>` 命名归档分支，仅作归档、不触发 CI，需经显式 refspec 创建。

---

Thank you for contributing! / 感谢你的贡献!
