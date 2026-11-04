import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Scales its child to 0.97 while a pointer is down, so buttons feel like
/// they heard the tap. Goes down in 100 ms and comes back in 160 ms. No
/// scaling when the system asks for reduced motion.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: _down ? Motion.pressIn : Motion.pressOut,
        curve: Motion.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Wraps each widget in [PressScale].
List<Widget> pressable(Iterable<Widget> children) => [
  for (final c in children) PressScale(child: c),
];

/// Draws a 3 px ink ring over [child] while something inside it has keyboard
/// focus. For large tappable areas (list rows, the logo link) where an
/// InkWell's tinted focus overlay is too faint to see.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child, this.radius = Radii.md});

  final Widget child;
  final double radius;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final visible =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: Container(
        foregroundDecoration: visible
            ? BoxDecoration(
                border: Border.all(color: LecternColors.ink, width: 3),
                borderRadius: BorderRadius.circular(widget.radius),
              )
            : null,
        child: widget.child,
      ),
    );
  }
}
