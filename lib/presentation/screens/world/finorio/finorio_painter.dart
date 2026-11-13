import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../domain/finorio/finorio.dart';
import 'finorio_art.dart';
import 'finorio_names.dart';

/// The camera: where the view is centred (in cells) and its zoom.
class FinCamera {
  FinCamera(this.x, this.y, this.zoom);
  double x, y, zoom;
  static const cell = 44.0, minZoom = .35, maxZoom = 3.0;
  double get scale => cell * zoom;

  Offset toWorld(Offset screen, Size size) => Offset(
    x + (screen.dx - size.width / 2) / scale,
    y + (screen.dy - size.height / 2) / scale,
  );
}

/// Ground pictures, one per 16×16 chunk, recorded once and reused.
class FinTerrainCache {
  FinTerrainCache(this.map);
  final FinTerrainMap map;
  final _chunks = <int, ui.Picture>{};

  ui.Picture chunk(int cx, int cy) => _chunks.putIfAbsent(cy * 1000 + cx, () {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const n = FinRules.chunk;
    for (var y = cy * n; y < (cy + 1) * n && y < map.height; y++) {
      for (var x = cx * n; x < (cx + 1) * n && x < map.width; x++) {
        paintTerrain(c, map.at(x, y), x, y, map.seed);
      }
    }
    return rec.endRecording();
  });

  void dispose() {
    for (final p in _chunks.values) {
      p.dispose();
    }
    _chunks.clear();
  }
}

/// What the screen wants drawn on top of the factory.
class FinOverlay {
  int? selectedX, selectedY;
  FinBuilding? ghost;
  int ghostDir = 1;
  bool ghostOk = true;
  List<(int, int, int)> beltPreview = const [];
  int? beltStartX, beltStartY;
}

/// Paints the visible part of the map, belts, items and buildings. One
/// painter for the whole world; nothing per cell is a widget.
class FinWorldPainter extends CustomPainter {
  FinWorldPainter({
    required this.world,
    required this.camera,
    required this.cache,
    required this.overlay,
    required this.time,
    required this.alpha,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final FinWorld world;
  final FinCamera camera;
  final FinTerrainCache cache;
  final FinOverlay overlay;

  /// Seconds of simulated time (for motion) and the fraction of the next
  /// tick already elapsed (to glide items between ticks).
  final double Function() time, alpha;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFCFC7DB),
    );
    final s = camera.scale;
    final halfW = size.width / 2 / s, halfH = size.height / 2 / s;
    final x0 = math.max(0, (camera.x - halfW).floor());
    final y0 = math.max(0, (camera.y - halfH).floor());
    final x1 = math.min(world.terrain.width - 1, (camera.x + halfW).ceil());
    final y1 = math.min(world.terrain.height - 1, (camera.y + halfH).ceil());
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    canvas.translate(-camera.x, -camera.y);

    const n = FinRules.chunk;
    for (var cy = y0 ~/ n; cy <= y1 ~/ n; cy++) {
      for (var cx = x0 ~/ n; cx <= x1 ~/ n; cx++) {
        canvas.drawPicture(cache.chunk(cx, cy));
      }
    }
    if (world.showGrid && camera.zoom > .55) {
      final grid = Paint()
        ..color = FinPalette.plum.withValues(alpha: .06)
        ..strokeWidth = 1 / s;
      for (var x = x0; x <= x1 + 1; x++) {
        canvas.drawLine(
          Offset(x.toDouble(), y0.toDouble()),
          Offset(x.toDouble(), y1 + 1.0),
          grid,
        );
      }
      for (var y = y0; y <= y1 + 1; y++) {
        canvas.drawLine(
          Offset(x0.toDouble(), y.toDouble()),
          Offset(x1 + 1.0, y.toDouble()),
          grid,
        );
      }
    }

    // Power zones: of the selected generator, or all while placing one.
    final selected = overlay.selectedX == null
        ? null
        : world.machineAt(overlay.selectedX!, overlay.selectedY!);
    for (final g in world.machines.values) {
      if (g.kind != FinBuilding.generator) continue;
      if (selected != g &&
          overlay.ghost != FinBuilding.generator &&
          !(selected != null &&
              selected.spec.power > 0 &&
              selected.kind != FinBuilding.generator &&
              (g.x - selected.x).abs() <= FinRules.generatorRadius &&
              (g.y - selected.y).abs() <= FinRules.generatorRadius)) {
        continue;
      }
      const r = FinRules.generatorRadius;
      final zone = Rect.fromLTRB(
        g.x - r + 0.0,
        g.y - r + 0.0,
        g.x + r + 1.0,
        g.y + r + 1.0,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(zone, const Radius.circular(.6)),
        Paint()..color = FinPalette.teal.withValues(alpha: .1),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(zone, const Radius.circular(.6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .05
          ..color = FinPalette.teal.withValues(alpha: .55),
      );
    }

    final t = time();
    final a = alpha();
    // Belts, then what lies on them, then machines.
    final belts = <FinMachine>[], others = <FinMachine>[];
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final m = world.machineAt(x, y);
        if (m == null) continue;
        (m.isBelt ? belts : others).add(m);
      }
    }
    for (final b in belts) {
      paintBelt(canvas, b, entrySide(world, b), t);
    }
    for (final b in belts) {
      final from = entrySide(world, b);
      final moving = b.status != FinStatus.outputBlocked;
      final speed = FinRules.beltSpeed[b.kind]!;
      for (var i = 0; i < b.items.length; i++) {
        final it = b.items[i];
        var pos = it.pos + (moving ? speed * a : 0);
        final cap = i == 0
            ? FinRules.beltLength - 1.0
            : b.items[i - 1].pos - FinRules.beltSpacing + speed * a;
        pos = math.min(pos, cap);
        paintItem(
          canvas,
          beltPoint(b, from, pos / FinRules.beltLength),
          it.item,
          .3,
        );
      }
    }
    for (final m in others) {
      paintBuilding(canvas, m, t, active: m.status == FinStatus.working);
      // A small status light; the words are in the inspector.
      canvas.drawCircle(
        Offset(m.x + .82, m.y + .18),
        .09,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(m.x + .82, m.y + .18),
        .065,
        Paint()..color = FinNames.statusColor(m.status),
      );
    }

    // Belt line preview and the ghost of the building to place.
    for (final (x, y, dir) in overlay.beltPreview) {
      final ok =
          world.terrain.buildable(x, y) &&
          (world.machineAt(x, y) == null || world.machineAt(x, y)!.isBelt);
      final ghost = FinMachine(
        id: 0,
        kind: overlay.ghost ?? FinBuilding.belt,
        x: x,
        y: y,
        dir: dir,
      );
      canvas.saveLayer(
        null,
        Paint()..color = Colors.white.withValues(alpha: ok ? .7 : .35),
      );
      paintBelt(canvas, ghost, FinDir.opposite(dir), t);
      canvas.restore();
    }
    if (overlay.beltStartX != null) {
      _outline(
        canvas,
        overlay.beltStartX!,
        overlay.beltStartY!,
        FinPalette.teal,
      );
    }
    if (overlay.ghost != null &&
        overlay.selectedX != null &&
        overlay.beltPreview.isEmpty &&
        overlay.ghost != FinBuilding.belt &&
        overlay.ghost != FinBuilding.fastBelt) {
      final g = FinMachine(
        id: 0,
        kind: overlay.ghost!,
        x: overlay.selectedX!,
        y: overlay.selectedY!,
        dir: overlay.ghostDir,
      );
      canvas.saveLayer(
        null,
        Paint()..color = Colors.white.withValues(alpha: .6),
      );
      paintBuilding(canvas, g, t, active: false);
      canvas.restore();
      _outline(
        canvas,
        g.x,
        g.y,
        overlay.ghostOk ? FinPalette.teal : const Color(0xFFE0566B),
      );
    } else if (overlay.selectedX != null) {
      _outline(
        canvas,
        overlay.selectedX!,
        overlay.selectedY!,
        FinPalette.lavender,
      );
    }
    canvas.restore();
  }

  void _outline(Canvas c, int x, int y, Color color) => c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(x + .02, y + .02, .96, .96),
      const Radius.circular(.2),
    ),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .07
      ..color = color,
  );

  @override
  bool shouldRepaint(FinWorldPainter old) => true;
}

/// The side a belt's items come in from: its back, or a side where a belt
/// feeds it (then it is drawn as a bend).
int entrySide(FinWorld w, FinMachine b) {
  final back = FinDir.opposite(b.dir);
  bool feeds(int side) {
    final m = w.machineAt(b.x + FinDir.dx[side], b.y + FinDir.dy[side]);
    return m != null && m.frontX == b.x && m.frontY == b.y;
  }

  if (feeds(back)) return back;
  for (final side in [(b.dir + 1) % 4, (b.dir + 3) % 4]) {
    final m = w.machineAt(b.x + FinDir.dx[side], b.y + FinDir.dy[side]);
    if (m != null && m.isBelt && feeds(side)) return side;
  }
  return back;
}
