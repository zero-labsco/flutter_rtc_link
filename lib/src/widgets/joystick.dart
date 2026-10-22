import 'package:flutter/material.dart';

/// Joystick change callback with normalized offsets (`dx`, `dy` in [-1, 1]).
/// 摇杆变更回调，归一化偏移（`dx`、`dy` 范围 [-1, 1]）。
///
/// Screen coordinates: `dy` grows downward, so up is negative. Use
/// `velocityFromJoystick` to convert to a [Velocity] command.
/// 屏幕坐标 `dy` 向下为正，因此向上为负。用 `velocityFromJoystick` 转换为
/// [Velocity] 指令。
typedef JoystickChanged = void Function(double dx, double dy);

/// Draggable joystick with spring-back. / 带回弹的可拖拽摇杆。
///
/// Theme-aware: colors come from the ambient [ColorScheme], never hardcoded.
/// 主题感知：颜色取自当前 [ColorScheme]，绝不硬编码。
class Joystick extends StatefulWidget {
  const Joystick({
    super.key,
    this.size = 160,
    this.onChanged,
    this.onRelease,
    this.showCrosshair = true,
  });

  /// Outer diameter in logical pixels. / 外直径（逻辑像素）。
  final double size;

  /// Called while dragging (normalized offsets). / 拖拽中回调（归一化偏移）。
  final JoystickChanged? onChanged;

  /// Called when the stick returns to center. / 摇杆回中时回调。
  final VoidCallback? onRelease;

  /// Whether to draw the crosshair guide. / 是否绘制十字准线。
  final bool showCrosshair;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick>
    with SingleTickerProviderStateMixin {
  Offset _offset = Offset.zero;
  late final AnimationController _controller;
  late final Animation<Offset> _animation;

  double get _radius => widget.size / 2 - widget.size * 0.12;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _animation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateOffset(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    var delta = localPosition - center;
    final distance = delta.distance;
    if (distance > _radius) {
      delta = delta * (_radius / distance);
    }
    setState(() => _offset = delta);
    final dx = (_offset.dx / _radius).clamp(-1.0, 1.0);
    final dy = (_offset.dy / _radius).clamp(-1.0, 1.0);
    widget.onChanged?.call(dx.toDouble(), dy.toDouble());
  }

  void _release() {
    _animation = Tween<Offset>(
      begin: _offset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller
      ..reset()
      ..forward();
    setState(() => _offset = Offset.zero);
    widget.onChanged?.call(0, 0);
    widget.onRelease?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final offset = _controller.isAnimating ? _animation.value : _offset;
          return GestureDetector(
            onPanStart: (details) => _updateOffset(details.localPosition),
            onPanUpdate: (details) => _updateOffset(details.localPosition),
            onPanEnd: (_) => _release(),
            onPanCancel: _release,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHighest,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Center(
                child: Transform.translate(
                  offset: offset,
                  child: Container(
                    width: widget.size * 0.28,
                    height: widget.size * 0.28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
