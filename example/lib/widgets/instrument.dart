import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
// Re-export so pages get the theme tokens from one import.
// 再导出，让页面一次导入即可拿到主题令牌。
export '../theme/app_theme.dart';

/// Shared instrument-panel components for the example app.
/// Example 应用的仪表盘共享组件。
///
/// Everything reads colors and text styles from the theme — no literals.
/// 所有颜色与文字样式均取自主题——没有字面量。

/// A bordered panel with an optional header row. Replaces the floating card.
/// 带可选标题行的边框面板。替代悬浮卡片。
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
    this.child,
  });

  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title!.toUpperCase(),
                      style: Theme.of(context).textTheme.monoLabel,
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Mono section label with a hairline rule (instrument group header).
/// 等宽节标签 + 发丝线（仪表分组标题）。
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: <Widget>[
          Text(
            text.toUpperCase(),
            style: Theme.of(context).textTheme.monoLabel,
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: scheme.outlineVariant, height: 1)),
        ],
      ),
    );
  }
}

/// Status LED with a slow pulse while active. / 状态灯，激活时缓慢脉冲。
class StatusLed extends StatefulWidget {
  const StatusLed({
    super.key,
    required this.color,
    this.active = false,
    this.size = 8,
  });

  final Color color;
  final bool active;
  final double size;

  @override
  State<StatusLed> createState() => _StatusLedState();
}

class _StatusLedState extends State<StatusLed>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StatusLed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 6),
        ],
      ),
    );
    if (disableAnimations || !widget.active) return dot;
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.35,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: dot,
    );
  }
}

/// Status chip: LED + mono label. / 状态徽条：灯 + 等宽标签。
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.active = false,
  });

  final String label;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          StatusLed(color: color, active: active),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.monoLabel
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Metric tile: mono label + tabular value. / 指标块：等宽标签 + 等宽数字。
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.accent,
  });

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.monoLabel,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.monoValue
                ?.copyWith(color: accent ?? scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

/// Dense labelled text field. / 紧凑的带标签输入框。
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          labelText: label.toUpperCase(),
          hintText: hint,
        ),
      ),
    );
  }
}

/// Instrument button: mono label, optional icon, primary/secondary weight.
/// 仪表按钮：等宽标签、可选图标、主 / 次权重。
class InstrumentButton extends StatelessWidget {
  const InstrumentButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final fg = danger ? status.error : null;
    final labelWidget = Text(label.toUpperCase());

    if (primary) {
      return FilledButton(
        onPressed: onPressed,
        style: danger
            ? FilledButton.styleFrom(backgroundColor: status.error)
            : null,
        child: _content(labelWidget),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: fg == null
          ? null
          : OutlinedButton.styleFrom(
              foregroundColor: fg,
              side: BorderSide(color: fg.withValues(alpha: 0.5)),
            ),
      child: _content(labelWidget),
    );
  }

  Widget _content(Widget label) {
    final icon = this.icon;
    if (icon == null) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[Icon(icon, size: 15), const SizedBox(width: 8), label],
    );
  }
}

/// Key/value readout row for log lines. / 日志行的键值读数行。
class ReadoutRow extends StatelessWidget {
  const ReadoutRow({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.monoLabel,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: color ?? scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
