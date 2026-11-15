import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_art.dart';
import 'mag_buildings.dart';
import 'mag_iso.dart';
import 'mag_rail_art.dart';

/// Icons of the game's own (S21): a drawn glyph for every cargo, every
/// vehicle model drawn by the same art as on the map, every kind of place
/// as its building.
class MagCargoIcon extends StatelessWidget {
  const MagCargoIcon(this.cargo, {super.key, this.size = 18});
  final MagCargo cargo;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _CargoPainter(cargo));
}

class _CargoPainter extends CustomPainter {
  _CargoPainter(this.c);
  final MagCargo c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24);
    paintCargoGlyph(canvas, c);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CargoPainter old) => old.c != c;
}

Paint _p(int color) => Paint()..color = Color(color);
Paint _line(int color, double w) => Paint()
  ..color = Color(color)
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round;

/// A cargo's glyph in a 24×24 box.
void paintCargoGlyph(Canvas c, MagCargo cargo) {
  switch (cargo) {
    case MagCargo.grain:
      for (final dx in [-5.0, 0.0, 5.0]) {
        c.drawLine(
          Offset(12 + dx * .4, 22),
          Offset(12 + dx, 6),
          _line(0xFFB8902A, 1.4),
        );
        for (var k = 0; k < 4; k++) {
          final y = 7.0 + k * 3.2, x = 12 + dx * (1 - k * .12);
          c.drawOval(
            Rect.fromCenter(center: Offset(x - 1.5, y), width: 3, height: 4.4),
            _p(0xFFE8C14A),
          );
          c.drawOval(
            Rect.fromCenter(center: Offset(x + 1.5, y), width: 3, height: 4.4),
            _p(0xFFD9AE34),
          );
        }
      }
    case MagCargo.wood:
      for (final (x, y) in [(7.5, 15.5), (16.5, 15.5), (12.0, 8.0)]) {
        c.drawCircle(Offset(x, y), 5.4, _p(0xFF8A5A2E));
        c.drawCircle(Offset(x, y), 4.2, _p(0xFFD9A867));
        c.drawCircle(Offset(x, y), 2.4, _line(0xFFA9773F, 1));
        c.drawCircle(Offset(x, y), .8, _p(0xFF8A5A2E));
      }
    case MagCargo.ore:
      final rock = Path()
        ..addPolygon(const [
          Offset(3, 18),
          Offset(6, 8),
          Offset(13, 4),
          Offset(20, 8),
          Offset(22, 17),
          Offset(14, 21),
        ], true);
      c.drawPath(rock, _p(0xFF6C7683));
      c.drawPath(
        Path()..addPolygon(const [
          Offset(6, 8),
          Offset(13, 4),
          Offset(20, 8),
          Offset(12, 11),
        ], true),
        _p(0xFF8D97A4),
      );
      for (final (x, y, col) in [
        (9.0, 14.0, 0xFFE0743C),
        (15.0, 15.0, 0xFFD9B95A),
        (13.0, 9.0, 0xFFE0743C),
      ]) {
        c.drawCircle(Offset(x, y), 1.6, _p(col));
      }
    case MagCargo.food:
      c.drawRRect(
        RRect.fromLTRBR(5, 6, 19, 21, const Radius.circular(2)),
        _p(0xFFC9473D),
      );
      c.drawRect(const Rect.fromLTRB(5, 10, 19, 16), _p(0xFFF3E6CF));
      c.drawOval(const Rect.fromLTRB(5, 3.5, 19, 8.5), _p(0xFFBFC6CC));
      c.drawCircle(const Offset(12, 13), 2, _p(0xFFE86A5A));
    case MagCargo.goods:
      c.drawPath(
        Path()..addPolygon(const [
          Offset(3, 8),
          Offset(12, 4),
          Offset(21, 8),
          Offset(12, 12),
        ], true),
        _p(0xFF7FC7D6),
      );
      c.drawPath(
        Path()..addPolygon(const [
          Offset(3, 8),
          Offset(12, 12),
          Offset(12, 22),
          Offset(3, 18),
        ], true),
        _p(0xFF4FB3C9),
      );
      c.drawPath(
        Path()..addPolygon(const [
          Offset(21, 8),
          Offset(12, 12),
          Offset(12, 22),
          Offset(21, 18),
        ], true),
        _p(0xFF3A93A8),
      );
      c.drawLine(
        const Offset(7.5, 6),
        const Offset(16.5, 10),
        _line(0xFFF3E6CF, 1.6),
      );
    case MagCargo.stone:
      for (final (x, y, w) in [
        (3.0, 14.0, 9.0),
        (12.5, 14.0, 9.0),
        (7.5, 7.0, 9.0),
      ]) {
        c.drawRRect(
          RRect.fromLTRBR(x, y, x + w, y + 6.5, const Radius.circular(1.5)),
          _p(0xFF9EA1A4),
        );
        c.drawRect(Rect.fromLTRB(x, y, x + w, y + 1.8), _p(0xFFC3C5C8));
      }
    case MagCargo.planks:
      for (var k = 0; k < 3; k++) {
        final y = 6.0 + k * 5;
        c.drawRRect(
          RRect.fromLTRBR(3, y, 21, y + 4, const Radius.circular(1)),
          _p(k.isEven ? 0xFFD9A867 : 0xFFC9954F),
        );
        c.drawLine(Offset(7, y + 2), Offset(16, y + 2), _line(0xFFB07B3E, .6));
      }
    case MagCargo.flour:
      final sack = Path()
        ..moveTo(6, 8)
        ..quadraticBezierTo(3, 21, 12, 21)
        ..quadraticBezierTo(21, 21, 18, 8)
        ..close();
      c.drawPath(sack, _p(0xFFEDE6D3));
      c.drawPath(sack, _line(0xFFC9BFA5, 1));
      c.drawRect(const Rect.fromLTRB(8, 5, 16, 8), _p(0xFFC9BFA5));
      c.drawCircle(const Offset(12, 14.5), 2.6, _p(0xFFE8C14A));
    case MagCargo.bread:
      c.drawOval(const Rect.fromLTRB(2, 7, 22, 19), _p(0xFFB9783C));
      c.drawOval(const Rect.fromLTRB(3, 7, 21, 16), _p(0xFFD9A15C));
      for (final x in [8.0, 12.0, 16.0]) {
        c.drawLine(
          Offset(x - 1.5, 9.5),
          Offset(x + 1.5, 13.5),
          _line(0xFFF3D9A8, 1.3),
        );
      }
    case MagCargo.coal:
      for (final (x, y, r) in [
        (8.0, 15.0, 5.0),
        (15.5, 15.5, 5.0),
        (12.0, 9.0, 4.6),
      ]) {
        c.drawPath(_lump(x, y, r), _p(0xFF2B2E33));
        c.drawCircle(Offset(x - r * .3, y - r * .35), r * .25, _p(0xFF5A6068));
      }
    case MagCargo.clay:
      c.drawPath(_lump(12, 14, 9), _p(0xFFB8774A));
      c.drawPath(_lump(10.5, 12, 5), _p(0xFFCC8C5C));
      c.drawArc(
        const Rect.fromLTRB(7, 12, 17, 20),
        .3,
        2.2,
        false,
        _line(0xFF9A5F38, 1),
      );
    case MagCargo.bricks:
      for (var row = 0; row < 3; row++) {
        for (var k = 0; k < 3; k++) {
          final x = 2.0 + k * 7 - (row.isOdd ? 3.5 : 0), y = 6.0 + row * 4.8;
          if (x < 0 || x > 20) continue;
          c.drawRRect(
            RRect.fromLTRBR(
              math.max(2, x),
              y,
              math.min(22, x + 6.4),
              y + 4,
              const Radius.circular(.8),
            ),
            _p(0xFFC8664E),
          );
        }
      }
    case MagCargo.steel:
      final beam = Path()
        ..addPolygon(const [
          Offset(4, 6),
          Offset(20, 6),
          Offset(20, 9),
          Offset(14, 9),
          Offset(14, 15),
          Offset(20, 15),
          Offset(20, 18),
          Offset(4, 18),
          Offset(4, 15),
          Offset(10, 15),
          Offset(10, 9),
          Offset(4, 9),
        ], true);
      c.drawPath(beam, _p(0xFF7D8A97));
      c.drawRect(const Rect.fromLTRB(4, 6, 20, 7.5), _p(0xFFB3BDC7));
    case MagCargo.parts:
      c.drawPath(_gear(12, 12, 9, 6.5, 8), _p(0xFFE8B23E));
      c.drawCircle(const Offset(12, 12), 3, _p(0xFF9A6B10));
    case MagCargo.passengers:
      c.drawCircle(const Offset(12, 7), 3.6, _p(0xFF8E7CC3));
      c.drawPath(
        Path()..addRRect(
          RRect.fromLTRBAndCorners(
            5,
            12,
            19,
            22,
            topLeft: const Radius.circular(7),
            topRight: const Radius.circular(7),
          ),
        ),
        _p(0xFF8E7CC3),
      );
    case MagCargo.workers:
      c.drawCircle(const Offset(12, 10), 3.6, _p(0xFFE9C9A8));
      c.drawPath(
        Path()
          ..addArc(const Rect.fromLTRB(6.5, 3, 17.5, 13), math.pi, math.pi)
          ..close(),
        _p(0xFFE8B23E),
      );
      c.drawRect(const Rect.fromLTRB(5.5, 7.5, 18.5, 9), _p(0xFFD49A1E));
      c.drawPath(
        Path()..addRRect(
          RRect.fromLTRBAndCorners(
            5,
            15,
            19,
            22,
            topLeft: const Radius.circular(6),
            topRight: const Radius.circular(6),
          ),
        ),
        _p(0xFF3F8E9C),
      );
    case MagCargo.oil:
      c.drawRRect(
        RRect.fromLTRBR(5, 4, 19, 21, const Radius.circular(3)),
        _p(0xFF2E2A26),
      );
      for (final y in [8.5, 16.5]) {
        c.drawRect(Rect.fromLTRB(5, y, 19, y + 1.4), _p(0xFF4C4640));
      }
      c.drawPath(
        Path()
          ..moveTo(12, 9.5)
          ..quadraticBezierTo(15, 13.5, 12, 15)
          ..quadraticBezierTo(9, 13.5, 12, 9.5),
        _p(0xFFE8B23E),
      );
    case MagCargo.fuel:
      c.drawRRect(
        RRect.fromLTRBR(5, 6, 19, 21, const Radius.circular(2.5)),
        _p(0xFFE0743C),
      );
      c.drawRect(const Rect.fromLTRB(13, 3, 17, 6), _p(0xFFB8551F));
      c.drawLine(
        const Offset(8, 9),
        const Offset(16, 18),
        _line(0xFFF6B48A, 1.4),
      );
      c.drawLine(
        const Offset(16, 9),
        const Offset(8, 18),
        _line(0xFFF6B48A, 1.4),
      );
    case MagCargo.electronics:
      for (var k = 0; k < 4; k++) {
        final d = 7.5 + k * 3;
        for (final (a, b) in [
          (Offset(d, 2), Offset(d, 6)),
          (Offset(d, 18), Offset(d, 22)),
          (Offset(2, d), Offset(6, d)),
          (Offset(18, d), Offset(22, d)),
        ]) {
          c.drawLine(a, b, _line(0xFF9AA6AA, 1.2));
        }
      }
      c.drawRRect(
        RRect.fromLTRBR(5, 5, 19, 19, const Radius.circular(2)),
        _p(0xFF2F5D75),
      );
      c.drawRRect(
        RRect.fromLTRBR(8.5, 8.5, 15.5, 15.5, const Radius.circular(1)),
        _p(0xFF5BB0D6),
      );
    case MagCargo.machines:
      c.drawRRect(
        RRect.fromLTRBR(2, 13, 22, 21, const Radius.circular(1.5)),
        _p(0xFF3F6E5E),
      );
      c.drawRect(const Rect.fromLTRB(4, 9, 11, 13), _p(0xFF5D7286));
      c.drawPath(_gear(16, 9, 6, 4.4, 8), _p(0xFFE8B23E));
      c.drawCircle(const Offset(16, 9), 1.8, _p(0xFF3F6E5E));
      c.drawCircle(const Offset(6, 21.5), 1.4, _p(0xFF2B2E33));
      c.drawCircle(const Offset(18, 21.5), 1.4, _p(0xFF2B2E33));
  }
}

Path _lump(double x, double y, double r) {
  final p = Path();
  for (var k = 0; k < 7; k++) {
    final a = k * math.pi * 2 / 7;
    final rr = r * (k.isEven ? 1 : .82);
    final o = Offset(x + math.cos(a) * rr, y + math.sin(a) * rr * .85);
    k == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

Path _gear(double x, double y, double outer, double inner, int teeth) {
  final p = Path();
  for (var k = 0; k < teeth * 2; k++) {
    final a = k * math.pi / teeth;
    final r = k.isEven ? outer : inner;
    final o = Offset(x + math.cos(a) * r, y + math.sin(a) * r);
    k == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

/// A vehicle model as it looks on the map, in a square.
class MagVehicleIcon extends StatelessWidget {
  const MagVehicleIcon(this.model, {super.key, this.size = 40, this.paint});
  final MagTruckModel model;
  final double size;
  final Color? paint;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _VehiclePainter(model, paint),
  );
}

class _VehiclePainter extends CustomPainter {
  _VehiclePainter(this.m, this.color);
  final MagTruckModel m;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height * .62);
    final span = m.rail
        ? 74.0
        : m.water
        ? (m.capacity > 100 ? 66.0 : 50.0)
        : m.horse
        ? 40.0
        : 54.0;
    canvas.scale(size.width / span);
    final p = MagIso.project(0, 0);
    canvas.translate(-p.dx, -p.dy);
    if (m.rail) {
      paintTrain(canvas, const [(.5, 0, 1), (-.45, 0, 1)], m, null);
    } else if (m.water) {
      paintShip(canvas, 0, 0, 1, m, null);
    } else {
      paintTruck(canvas, 0, 0, 1, m, null, paint: color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VehiclePainter old) => old.m != m || old.color != color;
}

/// A kind of place as its building (settlements as a cottage or a city).
class MagPlaceIcon extends StatelessWidget {
  const MagPlaceIcon(this.kind, {super.key, this.size = 36});
  final MagIndustryKind kind;
  final double size;

  @override
  Widget build(BuildContext context) =>
      kind == MagIndustryKind.village || kind == MagIndustryKind.city
      ? SizedBox.square(
          dimension: size,
          child: Icon(
            kind == MagIndustryKind.city
                ? Icons.location_city_rounded
                : Icons.cottage_rounded,
            size: size * .72,
            color: MagPalette.teal,
          ),
        )
      : CustomPaint(size: Size.square(size), painter: _PlacePainter(kind));
}

final _places = <MagIndustryKind, ui.Picture>{};

class _PlacePainter extends CustomPainter {
  _PlacePainter(this.k);
  final MagIndustryKind k;

  @override
  void paint(Canvas canvas, Size size) {
    final s = MagRules.industries[k]!.size.toDouble();
    final pic = _places.putIfAbsent(
      k,
      () => recordIndustry(MagIndustry(id: -1, kind: k, x: 0, y: 0, name: '')),
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height * .66);
    canvas.scale(size.width / (s * 64 + 8));
    final mid = MagIso.project(s / 2, s / 2);
    canvas.translate(-mid.dx, -mid.dy);
    canvas.drawPicture(pic);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlacePainter old) => old.k != k;
}
