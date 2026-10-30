import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The ASHA mark: a white shield with a medical cross. Same drawing as the Android launcher icon, so the icon, the launch
/// screen and the splash screen all show one logo.
class AshaLogo extends StatelessWidget {
  const AshaLogo({
    super.key,
    this.size = 96,
    this.shield = Colors.white,
    this.cross = Tk.primary,
  });
  final double size;
  final Color shield, cross;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _LogoPainter(shield, cross),
    ),
  );
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter(this.shield, this.cross);
  final Color shield, cross;

  @override
  void paint(Canvas canvas, Size size) {
    // drawing coordinates come from the 108x108 launcher-icon viewport; the mark itself spans x 33..75, y 27..82
    const w = 42.0, h = 55.0;
    final s = size.shortestSide / h;
    canvas.translate((size.width - w * s) / 2, 0);
    canvas.scale(s);
    canvas.translate(-33, -27);
    final body = Path()
      ..moveTo(54, 27)
      ..lineTo(75, 35)
      ..lineTo(75, 55)
      ..cubicTo(75, 68, 66, 77, 54, 82)
      ..cubicTo(42, 77, 33, 68, 33, 55)
      ..lineTo(33, 35)
      ..close();
    canvas.drawPath(body, Paint()..color = shield);
    final plus = Path()
      ..moveTo(50, 42)
      ..lineTo(58, 42)
      ..lineTo(58, 50)
      ..lineTo(66, 50)
      ..lineTo(66, 58)
      ..lineTo(58, 58)
      ..lineTo(58, 66)
      ..lineTo(50, 66)
      ..lineTo(50, 58)
      ..lineTo(42, 58)
      ..lineTo(42, 50)
      ..lineTo(50, 50)
      ..close();
    canvas.drawPath(plus, Paint()..color = cross);
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.shield != shield || old.cross != cross;
}
