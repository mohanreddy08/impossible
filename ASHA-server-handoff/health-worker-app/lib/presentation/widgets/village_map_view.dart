import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../maps/offline_map_source.dart';

const double _mPerDegLat = 111320.0;

/// Draws a [VillageMap] with plain Flutter painting: no network and no map library. [focus] zooms in on [selectedHouseId] (the small map
/// on a household); otherwise the whole village is shown. [interactive] adds pinch-zoom and drag (the big map).
///
/// [houseColors] colours houses by status, [extraHouses] adds houses that are not in the pack (families added on this phone),
/// [selectedAt] puts the red pin at any point, [onHouseTap] is called with the nearest house when one is tapped, and [onTapAt] with the
/// tapped place (the "pick the house on the map" screen).
class VillageMapView extends StatelessWidget {
  const VillageMapView({
    super.key,
    required this.map,
    this.selectedHouseId,
    this.selectedAt,
    this.focus = false,
    this.interactive = false,
    this.houseColors,
    this.extraHouses,
    this.onHouseTap,
    this.onTapAt,
    this.maxScale = 6,
  });
  final VillageMap map;
  final String? selectedHouseId;
  final LatLng? selectedAt;
  final bool focus, interactive;
  final Map<String, Color>? houseColors;
  final Map<String, LatLng>? extraHouses;
  final void Function(String houseId)? onHouseTap;
  final void Function(LatLng at)? onTapAt;
  final double maxScale;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      final painter = VillageMapPainter(
        map,
        selected: selectedAt ?? (selectedHouseId == null ? null : (map.houses[selectedHouseId] ?? extraHouses?[selectedHouseId])),
        focus: focus,
        houseColors: houseColors,
        extraHouses: extraHouses,
      );
      Widget paint = SizedBox(width: size.width, height: size.height, child: CustomPaint(painter: painter));
      if (onHouseTap != null || onTapAt != null) {
        paint = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            if (onTapAt != null) {
              onTapAt!(painter.unproject(d.localPosition, size));
            } else {
              final id = painter.houseAt(d.localPosition, size);
              if (id != null) onHouseTap!(id);
            }
          },
          child: paint,
        );
      }
      return ClipRect(
        child: interactive ? InteractiveViewer(minScale: 1, maxScale: maxScale, child: paint) : paint,
      );
    },
  );
}

class VillageMapPainter extends CustomPainter {
  VillageMapPainter(this.map, {this.selected, this.focus = false, this.houseColors, this.extraHouses});
  final VillageMap map;
  final LatLng? selected;
  final bool focus;
  final Map<String, Color>? houseColors;
  final Map<String, LatLng>? extraHouses;

  // metres east / north of the centre, and pixels per metre: set by _setup()
  late double _cLat, _cLng, _k, _cosC;
  late Size _size;

  Offset _px(LatLng p) => Offset(
    _size.width / 2 + (p.lng - _cLng) * _mPerDegLat * _cosC * _k,
    _size.height / 2 - (p.lat - _cLat) * _mPerDegLat * _k,
  );

  void _setup(Size size) {
    _size = size;
    final cosLat = math.cos((map.minLat + map.maxLat) / 2 * math.pi / 180);
    if (focus && selected != null) {
      _cLat = selected!.lat;
      _cLng = selected!.lng;
      _k = size.height / 2 / 135; // about 135 m each side of the house
    } else {
      _cLat = (map.minLat + map.maxLat) / 2;
      _cLng = (map.minLng + map.maxLng) / 2;
      final w = (map.maxLng - map.minLng) * _mPerDegLat * cosLat * 1.12;
      final h = (map.maxLat - map.minLat) * _mPerDegLat * 1.12;
      _k = math.min(size.width / w, size.height / h);
    }
    _cosC = math.cos(_cLat * math.pi / 180);
  }

  Map<String, LatLng> get _allHouses => extraHouses == null || extraHouses!.isEmpty ? map.houses : {...map.houses, ...extraHouses!};

  /// Where a point on the ground is drawn (pixels) for a map of this size.
  Offset project(LatLng p, Size size) {
    _setup(size);
    return _px(p);
  }

  /// The tapped place on the ground (the inverse of drawing).
  LatLng unproject(Offset o, Size size) {
    _setup(size);
    return LatLng(
      _cLat - (o.dy - size.height / 2) / (_mPerDegLat * _k),
      _cLng + (o.dx - size.width / 2) / (_mPerDegLat * _cosC * _k),
    );
  }

  /// The house nearest to the tapped point, if one is within about 22 px.
  String? houseAt(Offset o, Size size) {
    _setup(size);
    String? best;
    var bestD = 22.0 * 22.0;
    for (final e in _allHouses.entries) {
      final d = (_px(e.value) - o).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = e.key;
      }
    }
    return best;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _setup(size);

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE9F1EC),
    );

    // roads: a grey edge under a white line; the main road is wider
    for (final r in map.roads) {
      final path = Path();
      for (var i = 0; i < r.points.length; i++) {
        final o = _px(r.points[i]);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      final w = math.max(r.major ? 5.0 : 3.0, (r.major ? 9 : 5) * _k);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = w + 2.5
          ..color = const Color(0xFFC3D3CF),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = w
          ..color = r.major ? const Color(0xFFFFF3D0) : Colors.white,
      );
    }

    // houses (coloured by status when [houseColors] is given)
    final houseR = math.max(2.2, 4.5 * _k);
    final plain = Paint()..color = const Color(0xFF6F9A98);
    for (final e in _allHouses.entries) {
      final o = _px(e.value);
      if (o.dx < -10 || o.dy < -10 || o.dx > size.width + 10 || o.dy > size.height + 10) {
        continue;
      }
      final c = houseColors?[e.key];
      final r = c == null ? houseR : math.max(houseR * 1.25, 2.8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: r * 2, height: r * 2), const Radius.circular(1.5)),
        c == null ? plain : (Paint()..color = c),
      );
    }

    // landmarks. Zoomed all the way out (the block overview) the icons would hide the houses, so only the village names are drawn.
    final overview = _k < 0.25;
    for (final pl in map.places) {
      final o = _px(pl.at);
      if (o.dx < -20 || o.dy < -20 || o.dx > size.width + 20 || o.dy > size.height + 20) {
        continue;
      }
      if (pl.type == 'village') {
        if (overview) _text(canvas, pl.name, o, 13, Tk.text, bold: true);
        continue;
      }
      if (overview) continue;
      final (IconData icon, Color color) = switch (pl.type) {
        'phc' => (Icons.local_hospital, Tk.danger),
        'school' => (Icons.school, Tk.info),
        'temple' => (Icons.temple_hindu, const Color(0xFF9A5A00)),
        _ => (Icons.place, Tk.neutral),
      };
      canvas.drawCircle(o, 15, Paint()..color = Colors.white);
      canvas.drawCircle(
        o,
        15,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
      _glyph(canvas, icon, o, 18, color);
      _text(canvas, pl.name, o + const Offset(0, 24), 12, Tk.text, bold: true);
    }

    // the selected house: a red pin whose tip is on the house, with a ring
    if (selected != null) {
      final o = _px(selected!);
      canvas.drawCircle(
        o,
        15,
        Paint()..color = Tk.danger.withValues(alpha: 0.16),
      );
      final pin = Path()
        ..moveTo(o.dx, o.dy)
        ..cubicTo(o.dx - 20, o.dy - 20, o.dx - 18, o.dy - 46, o.dx, o.dy - 46)
        ..cubicTo(o.dx + 18, o.dy - 46, o.dx + 20, o.dy - 20, o.dx, o.dy)
        ..close();
      canvas.drawPath(
        pin.shift(const Offset(0, 2)),
        Paint()..color = Colors.black26,
      );
      canvas.drawPath(pin, Paint()..color = Tk.danger);
      canvas.drawCircle(
        Offset(o.dx, o.dy - 30),
        7,
        Paint()..color = Colors.white,
      );
    }

    // scale bar (50 m) and map label
    final bar = 50 * _k;
    final y = size.height - 16;
    final line = Paint()
      ..color = Tk.text
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(14, y), Offset(14 + bar, y), line);
    canvas.drawLine(Offset(14, y - 5), Offset(14, y + 5), line);
    canvas.drawLine(Offset(14 + bar, y - 5), Offset(14 + bar, y + 5), line);
    _text(
      canvas,
      '50 m',
      Offset(14 + bar / 2, y - 12),
      11,
      Tk.text,
      bold: true,
    );
  }

  void _glyph(
    Canvas canvas,
    IconData icon,
    Offset c,
    double size,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _text(
    Canvas canvas,
    String s,
    Offset center,
    double size,
    Color color, {
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          shadows: const [
            Shadow(color: Colors.white, blurRadius: 3),
            Shadow(color: Colors.white, blurRadius: 3),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(VillageMapPainter old) =>
      old.map != map ||
      old.selected != selected ||
      old.focus != focus ||
      old.houseColors != houseColors ||
      old.extraHouses != extraHouses;
}
