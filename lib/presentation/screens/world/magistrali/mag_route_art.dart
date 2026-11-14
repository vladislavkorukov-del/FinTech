import 'package:flutter/painting.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_curve.dart';
import 'mag_iso.dart';

/// The way of the selected vehicle, dashed on the map: the leg it drives
/// now in bright mint from where it is, the other legs of its route paler,
/// and each stop marked with its number in the route.
void paintVehicleRoute(Canvas c, MagWorld w, MagVehicle v) {
  final now = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0xFF2BB59A)
    ..strokeWidth = 3.2
    ..strokeCap = StrokeCap.round;
  final later = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0xCCFFFFFF)
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round;
  final halo = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0x55203038)
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round;
  if (v.state == MagVehicleState.driving && v.path.length > 1) {
    final ahead = wayAhead(w, v.path, v.pathIndex + v.progress);
    c.drawPath(dashed(ahead, 9, 7), halo);
    c.drawPath(dashed(ahead, 9, 7), now);
  }
  final r = w.routes[v.routeId];
  if (r == null || r.stops.length < 2) return;
  final places = [for (final id in r.stops) w.map.industry(id)];
  // The other legs, from the stop it heads to round the loop.
  for (var k = 1; k < places.length; k++) {
    final a = places[(v.stop + k - 1) % places.length];
    final b = places[(v.stop + k) % places.length];
    if (a == null || b == null) continue;
    final leg = v.spec.rail
        ? w.railPath(w.stationCells(a), b)
        : v.spec.water
        ? w.waterPath(w.portCells(a), b)
        : w.roadPath(w.accessCells(a), b);
    if (leg == null || leg.length < 2) continue;
    final p = wayAhead(w, leg, 0);
    c.drawPath(dashed(p, 6, 8), halo);
    c.drawPath(dashed(p, 6, 8), later);
  }
  for (var k = 0; k < places.length; k++) {
    final i = places[k];
    if (i == null) continue;
    final p = MagIso.project(i.centerX, i.centerY, 34);
    final current = k == v.stop % places.length;
    c.drawCircle(
      p,
      10,
      Paint()
        ..color = current ? const Color(0xFF2BB59A) : const Color(0xFF233238),
    );
    c.drawCircle(
      p,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: '${k + 1}',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFFFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }
}
