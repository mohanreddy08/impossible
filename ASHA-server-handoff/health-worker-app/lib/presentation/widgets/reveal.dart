import 'package:flutter/material.dart';

/// Fades a section in and lifts it a few pixels when it first appears. [index] staggers sections so a screen "builds up"
/// from the top. One light controller per section, plays once, and is skipped entirely when the phone's "reduce motion"
/// (remove animations) setting is on.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  static const _step = 70; // ms between sections
  static const _length = 380; // ms for one section
  late final AnimationController _c;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    final total = _length + widget.index * _step;
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    );
    _t = CurvedAnimation(
      parent: _c,
      curve: Interval(
        widget.index * _step / total,
        1,
        curve: Curves.easeOutCubic,
      ),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _t,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(_t),
        child: widget.child,
      ),
    );
  }
}
