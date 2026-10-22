import 'dart:io';

import 'package:flutter/material.dart';

/// The single brand seed for the example app.
/// Example 应用唯一的品牌种子色。
///
/// Every other color is derived from it (ColorScheme) or declared as a
/// semantic status token below. Pages never contain color literals — they
/// read `Theme.of(context).colorScheme` or `AppStatusColors.of(context)`.
/// 其它颜色全部由它派生（ColorScheme）或在下方声明为语义状态令牌。
/// 页面绝不出现颜色字面量——只读 `Theme.of(context).colorScheme` 或
/// `AppStatusColors.of(context)`。
///
/// Amber signal: the avionics / broadcast-instrument accent, deliberately
/// not the default AI blue-purple.
/// 琥珀信号色：航电 / 播控仪器的经典强调色，刻意避开默认的 AI 蓝紫。
const Color brandSeed = Color(0xFFE8A33D);

/// Semantic status colors, shared through a [ThemeExtension].
/// 语义状态色，经 [ThemeExtension] 共享。
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.live,
    required this.ok,
    required this.warn,
    required this.error,
    required this.idle,
  });

  /// Live / recording signal. / 直播 / 录制中信号。
  final Color live;

  /// Healthy state. / 健康状态。
  final Color ok;

  /// Degraded but usable. / 降级但仍可用。
  final Color warn;

  /// Failure state. / 失败状态。
  final Color error;

  /// Inactive / unknown. / 未激活 / 未知。
  final Color idle;

  /// Convenience accessor. / 便捷访问器。
  static AppStatusColors of(BuildContext context) {
    return Theme.of(context).extension<AppStatusColors>()!;
  }

  @override
  AppStatusColors copyWith({
    Color? live,
    Color? ok,
    Color? warn,
    Color? error,
    Color? idle,
  }) {
    return AppStatusColors(
      live: live ?? this.live,
      ok: ok ?? this.ok,
      warn: warn ?? this.warn,
      error: error ?? this.error,
      idle: idle ?? this.idle,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      live: Color.lerp(live, other.live, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      error: Color.lerp(error, other.error, t)!,
      idle: Color.lerp(idle, other.idle, t)!,
    );
  }
}

/// Typography helpers for the instrument look.
/// 仪表盘风格的排版辅助。
///
/// Labels are mono uppercase with tracking; numeric readouts use tabular
/// figures so values do not jitter while updating.
/// 标签为等宽大写加字距；数值读数使用等宽数字，更新时不跳动。
extension InstrumentTextTheme on TextTheme {
  /// Mono micro-label (section headers, field labels). / 等宽微标签（节标题、字段标签）。
  TextStyle? get monoLabel => TextStyle(
    fontFamily: _monoFamily,
    fontSize: 11,
    height: 1.4,
    letterSpacing: 1.6,
    color: bodyMedium?.color?.withValues(alpha: 0.72),
    fontWeight: FontWeight.w500,
  );

  /// Mono numeric readout. / 等宽数值读数。
  TextStyle? get monoValue => TextStyle(
    fontFamily: _monoFamily,
    fontSize: 15,
    height: 1.3,
    letterSpacing: 0.4,
    fontWeight: FontWeight.w600,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Large metric display. / 大号指标展示。
  TextStyle? get metricDisplay => TextStyle(
    fontFamily: _monoFamily,
    fontSize: 28,
    height: 1.15,
    letterSpacing: -0.5,
    fontWeight: FontWeight.w600,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );
}

/// Platform mono family without bundling assets.
/// 不打包资产即可获得平台等宽字体。
String? get _monoFamily {
  if (Platform.isIOS || Platform.isMacOS) return 'Menlo';
  if (Platform.isAndroid) return 'monospace';
  return null;
}

/// Builds the example app theme (dark instrument panel).
/// 构建 example 应用主题（暗色仪表台）。
ThemeData buildAppTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: brandSeed,
    brightness: Brightness.dark,
  );

  final scheme = base.copyWith(
    primary: base.primary,
    secondary: base.secondary,
    // Warm instrument surfaces: deep neutral with a faint amber bias.
    // 暖色仪表表面：带微弱琥珀倾向的深中性色。
    surface: const Color(0xFF14110D),
    surfaceContainerLowest: const Color(0xFF100E0B),
    surfaceContainerLow: const Color(0xFF1A1712),
    surfaceContainer: const Color(0xFF211D16),
    surfaceContainerHigh: const Color(0xFF29241C),
    surfaceContainerHighest: const Color(0xFF332D23),
    onSurface: const Color(0xFFEDE6D8),
    onSurfaceVariant: const Color(0xFFB8AE9B),
    outline: const Color(0xFF4A4436),
    outlineVariant: const Color(0xFF322D24),
  );

  const statusColors = AppStatusColors(
    live: Color(0xFFFF5A5F),
    ok: Color(0xFF4CC38A),
    warn: Color(0xFFF2B04A),
    error: Color(0xFFFF6B5E),
    idle: Color(0xFF7A7263),
  );

  final textTheme = Typography.material2021(platform: TargetPlatform.android)
      .white
      .copyWith(
        bodyMedium: TextStyle(
          fontFamily: _monoFamily,
          fontSize: 13,
          height: 1.5,
          letterSpacing: 0.2,
          color: scheme.onSurface,
        ),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: textTheme,
    extensions: <ThemeExtension<dynamic>>[statusColors],
    // Slim instrument app bar: no elevation, hairline bottom border.
    // 纤细仪表顶栏：无阴影，底部发丝线。
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLow,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: _monoFamily,
        fontSize: 15,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    // Panels: flat, hairline border, small radius — not floating cards.
    // 面板：扁平、发丝边框、小圆角——而不是悬浮卡片。
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
      labelStyle: TextStyle(
        fontFamily: _monoFamily,
        fontSize: 11,
        letterSpacing: 1.4,
        color: scheme.onSurfaceVariant,
      ),
      floatingLabelStyle: TextStyle(
        fontFamily: _monoFamily,
        fontSize: 11,
        letterSpacing: 1.4,
        color: scheme.primary,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.surfaceContainerLowest,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: TextStyle(
          fontFamily: _monoFamily,
          fontSize: 12,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        side: BorderSide(color: scheme.outline),
        textStyle: TextStyle(
          fontFamily: _monoFamily,
          fontSize: 12,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainer,
      side: BorderSide(color: scheme.outline),
      labelStyle: TextStyle(
        fontFamily: _monoFamily,
        fontSize: 11,
        letterSpacing: 1.2,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.16),
      trackHeight: 2,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(
        TextStyle(
          fontFamily: _monoFamily,
          fontSize: 10,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: TextStyle(
        fontFamily: _monoFamily,
        fontSize: 12,
        color: scheme.onSurface,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      linearMinHeight: 3,
    ),
  );
}
