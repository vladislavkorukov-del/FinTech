import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_iso.dart';

/// Beyond the edge of the map (S12): no empty sky — the land is an island
/// in a calm sea. Deep water, shallows and a sandy shore along the edge,
/// small islands far out and waves that move with time. Drawn under the
/// ground transform (cells), before the land.
void paintSea(Canvas c, MagMap map, Rect view, double time) {
  final n = map.size.toDouble();
  final land = Rect.fromLTWH(0, 0, n, n);
  c.drawRect(view.inflate(4), Paint()..color = const Color(0xFF3F8EC0));
  for (final (grow, color) in const [
    (3.2, Color(0xFF4B9BCB)),
    (1.8, Color(0xFF5DAFD8)),
    (.9, Color(0xFF7CC4E2)),
    (.45, Color(0xFFE3D5A0)),
  ]) {
    c.drawRRect(
      RRect.fromRectAndRadius(land.inflate(grow), Radius.circular(grow * 1.4)),
      Paint()..color = color,
    );
  }
  // Islands far out: a sandy rim, grass and a few dark spots of wood.
  for (var k = 0; k < 14; k++) {
    final a = _h(k, 1, map.seed) * math.pi * 2;
    final r = n * .5 + 9 + _h(k, 2, map.seed) * 22;
    final p = Offset(n / 2 + math.cos(a) * r, n / 2 + math.sin(a) * r);
    final s = 1.2 + _h(k, 3, map.seed) * 3;
    if (!view.inflate(s + 1).contains(p)) continue;
    final o = Rect.fromCenter(center: p, width: s * 1.6, height: s);
    c.drawOval(o.inflate(.6), Paint()..color = const Color(0xFF5DAFD8));
    c.drawOval(o.inflate(.25), Paint()..color = const Color(0xFFE3D5A0));
    c.drawOval(o, Paint()..color = const Color(0xFF86BD5E));
    for (var t = 0; t < 3; t++) {
      c.drawCircle(
        p +
            Offset(
              (_h(k, 10 + t, map.seed) - .5) * s,
              (_h(k, 20 + t, 7) - .5) * s * .5,
            ),
        .18 + s * .06,
        Paint()..color = const Color(0xFF4C9444),
      );
    }
  }
  // Waves: short light strokes drifting slowly, only out at sea.
  final wave = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = .06
    ..color = const Color(0x66FFFFFF);
  final gx0 = (view.left / 2).floor() - 1, gx1 = (view.right / 2).ceil() + 1;
  final gy0 = (view.top / 2).floor() - 1, gy1 = (view.bottom / 2).ceil() + 1;
  for (var gy = gy0; gy <= gy1; gy++) {
    for (var gx = gx0; gx <= gx1; gx++) {
      final hx = _h(gx, gy, 3), hy = _h(gy, gx, 5);
      final x = gx * 2 + hx * 2, y = gy * 2 + hy * 2;
      if (land.inflate(2.2).contains(Offset(x, y))) continue;
      final drift = math.sin(time * .8 + hx * 6) * .25;
      final p = Offset(x + drift, y);
      c.drawArc(
        Rect.fromCenter(center: p, width: .7, height: .35),
        math.pi * 1.1,
        math.pi * .8,
        false,
        wave,
      );
    }
  }
}

double _h(int x, int y, int seed) {
  var v = x * 374761393 + y * 668265263 + seed * 2147483647;
  v = (v ^ (v >> 13)) * 1274126177;
  return ((v ^ (v >> 16)) & 0xffff) / 0xffff;
}

/// The cells the screen shows, not clipped to the map.
Rect seaView(MagCamera cam, Size size) {
  final pts = [
    cam.toCell(Offset.zero, size),
    cam.toCell(Offset(size.width, 0), size),
    cam.toCell(Offset(0, size.height), size),
    cam.toCell(Offset(size.width, size.height), size),
  ];
  return Rect.fromLTRB(
    pts.map((p) => p.dx).reduce(math.min),
    pts.map((p) => p.dy).reduce(math.min),
    pts.map((p) => p.dx).reduce(math.max),
    pts.map((p) => p.dy).reduce(math.max),
  );
}
