import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_art.dart';
import 'mag_curve.dart';
import 'mag_game.dart';
import 'mag_iso.dart';

/// The light of the hour (S20+): a slow day over about six real minutes —
/// day, a warm sunset, a blue night with lit windows and headlights, dawn.
/// Returns (sunset warmth, night depth), each 0..1.
(double, double) dayLight(double time, {bool on = true}) {
  if (!on) return (0, 0);
  final p = (time / 360) % 1;
  double ramp(double a, double b) => ((p - a) / (b - a)).clamp(0.0, 1.0);
  if (p < .6) return (0, 0);
  if (p < .7) return (math.sin(ramp(.6, .7) * math.pi), ramp(.62, .72) * .7);
  if (p < .9) return (0, .7 + .3 * math.sin(ramp(.7, .9) * math.pi) * .4);
  final d = 1 - ramp(.9, 1);
  return (math.sin(ramp(.9, 1) * math.pi) * .6, d * .7);
}

/// Shadows of clouds drifting over the land, in world space.
void paintCloudShadows(Canvas c, MagWorld w, double time) {
  final n = 7;
  for (var k = 0; k < n; k++) {
    final sx = (k * 37 % 100) / 100 * w.size;
    final sy = (k * 61 % 100) / 100 * w.size;
    final x = (sx + time * .35 + k * 9) % (w.size + 20) - 10;
    final y = (sy + time * .12) % (w.size + 20) - 10;
    final p = MagIso.project(x, y);
    final r = 140.0 + (k * 29 % 5) * 40;
    final rect = Rect.fromCenter(center: p, width: r * 2, height: r);
    c.drawOval(
      rect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x1A10241C), Color(0x0010241C)],
        ).createShader(rect),
    );
  }
}

/// Night lights in world space: lit windows in settlements, warm glows at
/// own businesses, headlights of vehicles on the move.
void paintNightLights(
  Canvas c,
  MagWorld w,
  double night,
  int x0,
  int y0,
  int x1,
  int y1,
) {
  if (night <= .05) return;
  final glow = Paint()
    ..shader = null
    ..color = Color.fromRGBO(255, 226, 140, .95 * night);
  final halo = Paint()..color = Color.fromRGBO(255, 190, 90, .22 * night);
  for (final i in w.map.industries) {
    if (i.right < x0 - 1 ||
        i.left > x1 + 1 ||
        i.bottom < y0 - 1 ||
        i.top > y1 + 1) {
      continue;
    }
    final t = i.town;
    if (t != null) {
      for (final k in t.cells) {
        final x = MagSettlement.keyX(k), y = MagSettlement.keyY(k);
        for (var n = 0; n < 2 + math.min(t.level, 6) ~/ 2; n++) {
          final h = ((x * 73 + y * 37 + n * 11) % 97) / 97;
          final p = MagIso.project(
            x + .25 + h * .5,
            y + .3 + (1 - h) * .4,
            6 + h * (10 + 6.0 * t.level),
          );
          c.drawCircle(p, 5, halo);
          c.drawCircle(p, 1.9, glow);
        }
      }
      continue;
    }
    // S24: resorts glow all night, owned or not.
    final resort =
        i.kind == MagIndustryKind.lakeResort ||
        i.kind == MagIndustryKind.skiResort;
    if (resort) {
      for (var n = 0; n < 8; n++) {
        final p = MagIso.project(
          i.x + .45 + (n % 4) * .3,
          i.y + .55 + (n ~/ 4) * .15,
          6 + (n ~/ 4) * 8.0,
        );
        c.drawCircle(p, 5, halo);
        c.drawCircle(p, 1.9, glow);
      }
      continue;
    }
    if (!i.owned) continue;
    final p = MagIso.project(i.centerX, i.centerY, 8);
    final r = Rect.fromCircle(center: p, radius: 26);
    c.drawOval(
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.fromRGBO(255, 200, 110, .35 * night),
            const Color(0x00FFC86E),
          ],
        ).createShader(r),
    );
  }
  // S24: airports — runway lights blinking in turn, a lamp on the tower.
  for (final cell in w.airports.keys) {
    final x = w.cx(cell), y = w.cy(cell);
    if (x < x0 - 1 || x > x1 + 1 || y < y0 - 1 || y > y1 + 1) continue;
    for (var k = 0; k < 5; k++) {
      for (final side in const [.12, .88]) {
        final p = MagIso.project(x + .1 + k * .2, y + side);
        c.drawCircle(p, 3.5, halo);
        c.drawCircle(
          p,
          1.3,
          Paint()..color = Color.fromRGBO(255, 236, 160, night),
        );
      }
    }
    final top = MagIso.project(x + .85, y + .82, 24);
    c.drawCircle(
      top,
      6,
      Paint()..color = Color.fromRGBO(255, 80, 70, .35 * night),
    );
    c.drawCircle(top, 2, Paint()..color = Color.fromRGBO(255, 90, 80, night));
  }
  for (final v in w.vehicles.values) {
    if (!v.onMap || v.state != MagVehicleState.driving) continue;
    final (pose, heading) = vehiclePose(w, v);
    if (pose.dx < x0 - 2 ||
        pose.dy < y0 - 2 ||
        pose.dx > x1 + 2 ||
        pose.dy > y1 + 2) {
      continue;
    }
    final a = MagIso.project(pose.dx, pose.dy, 4);
    final b = MagIso.project(
      pose.dx + heading.dx * .9,
      pose.dy + heading.dy * .9,
      2,
    );
    final r = Rect.fromCircle(center: b, radius: 14);
    c.drawOval(
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.fromRGBO(255, 244, 200, .5 * night),
            const Color(0x00FFF4C8),
          ],
        ).createShader(r),
    );
    c.drawCircle(
      a,
      1.8,
      Paint()..color = Color.fromRGBO(255, 250, 220, .9 * night),
    );
  }
}

/// Screen-space light: the hour's tint and a soft vignette.
void paintScreenLight(Canvas c, Size size, double warm, double night) {
  final all = Offset.zero & size;
  if (warm > .01) {
    c.drawRect(all, Paint()..color = Color.fromRGBO(255, 140, 60, .16 * warm));
  }
  if (night > .01) {
    c.drawRect(all, Paint()..color = Color.fromRGBO(14, 28, 72, .55 * night));
  }
  c.drawRect(
    all,
    Paint()
      ..shader = const RadialGradient(
        radius: .95,
        colors: [Color(0x00000000), Color(0x00000000), Color(0x2A0A1A16)],
        stops: [0, .6, 1],
      ).createShader(all),
  );
}

/// Income over a vehicle: a coin and the sum, popping up and rising.
void paintFloats(Canvas c, MagOverlay o, double t) {
  o.floats.removeWhere((f) => t - f.$4 > 1.6);
  for (final (x, y, text, start) in o.floats) {
    final k = ((t - start) / 1.6).clamp(0.0, 1.0);
    final pop = k < .15 ? .6 + k / .15 * .5 : 1.1 - math.min(.1, (k - .15));
    final alpha = 1 - k * k;
    final p = MagIso.project(x, y, 26 + k * 34);
    final money = text.startsWith('+');
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 12.5 * pop,
          fontWeight: FontWeight.w900,
          color: (money ? const Color(0xFF14725F) : MagPalette.ink).withValues(
            alpha: alpha,
          ),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final coin = money ? 7.0 * pop : 0.0;
    final w = tp.width + (money ? coin * 2 + 4 : 0) + 12;
    final box = RRect.fromRectAndRadius(
      Rect.fromCenter(center: p, width: w, height: tp.height + 6),
      const Radius.circular(20),
    );
    c.drawRRect(
      box,
      Paint()..color = Color.fromRGBO(255, 255, 255, .92 * alpha),
    );
    if (money) {
      final cc = Offset(box.left + 6 + coin, p.dy);
      c.drawCircle(
        cc,
        coin,
        Paint()..color = Color.fromRGBO(242, 190, 60, alpha),
      );
      c.drawCircle(
        cc,
        coin * .55,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Color.fromRGBO(255, 236, 170, alpha),
      );
    }
    tp.paint(c, Offset(box.right - 6 - tp.width, p.dy - tp.height / 2));
    tp.dispose();
  }
}

/// The chosen place: a soft pulsing ring on the ground.
void paintSelection(Canvas c, MagIndustry sel, double t) {
  final pulse = .5 + .5 * math.sin(t * 4);
  final r = RRect.fromRectAndRadius(
    Rect.fromLTWH(sel.x - .15, sel.y - .15, sel.size + .3, sel.size + .3),
    const Radius.circular(.3),
  );
  c.drawRRect(
    r.inflate(.08 * pulse),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .14
      ..color = MagPalette.mint.withValues(alpha: .25 + .25 * pulse),
  );
  c.drawRRect(
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .08
      ..color = MagPalette.mint,
  );
}

/// S22: the weather over the screen — slanted rain, drifting snow, a fog
/// veil, a darker sky in a storm.
void paintWeather(Canvas c, Size size, MagWeather w, double t) {
  switch (w) {
    case MagWeather.clear:
      return;
    case MagWeather.fog:
      c.drawRect(Offset.zero & size, Paint()..color = const Color(0x40E6ECEA));
      return;
    case MagWeather.rain || MagWeather.storm:
      if (w == MagWeather.storm) {
        c.drawRect(
          Offset.zero & size,
          Paint()..color = const Color(0x2A1C2630),
        );
      }
      final p = Paint()
        ..color = const Color(0xA6D2E2EC)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      final n = w == MagWeather.storm ? 170 : 120;
      for (var k = 0; k < n; k++) {
        final x0 = (k * 97.0 + t * 40) % (size.width + 60) - 30;
        final y0 = (k * 53.0 + t * 520) % (size.height + 40) - 20;
        c.drawLine(Offset(x0, y0), Offset(x0 - 6, y0 + 18), p);
      }
    case MagWeather.snow:
      final p = Paint()..color = const Color(0xCCFFFFFF);
      for (var k = 0; k < 110; k++) {
        final drift = math.sin(t * 1.3 + k) * 12;
        final x0 = (k * 83.0 + drift + t * 12) % size.width;
        final y0 = (k * 61.0 + t * 46) % size.height;
        c.drawCircle(Offset(x0, y0), 1.2 + (k % 3) * .6, p);
      }
  }
}
