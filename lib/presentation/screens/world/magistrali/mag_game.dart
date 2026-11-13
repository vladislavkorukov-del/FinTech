import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_art.dart';
import 'mag_buildings.dart';
import 'mag_iso.dart';

/// What the screen wants drawn over the world.
class MagOverlay {
  /// A road being drawn: its cells and whether it can be built.
  List<int> plan = const [];
  bool planOk = true;

  /// Cells marked for removal.
  List<int> removing = const [];
  int? industry, vehicle;

  /// Income popping up over a truck: (x, y, text, start time).
  final floats = <(double, double, String, double)>[];
}

/// The screen side the game reads from.
abstract interface class MagHost {
  MagWorld get world;
  MagCamera get camera;
  MagOverlay get overlay;

  /// Seconds since the screen opened (for motion).
  double get time;

  /// Advances the simulation by real seconds (the host applies speed).
  void advance(double dt);
}

/// The Flame game: its loop drives the fixed-step simulation and draws the
/// isometric world each frame. The world is one renderer, not a component
/// per cell, so a 64×64 map with hundreds of trees stays light.
class MagGame extends Game {
  MagGame(this.host);
  final MagHost host;
  final _renderer = MagRenderer();

  @override
  void update(double dt) => host.advance(dt);

  @override
  void render(Canvas canvas) {
    final s = canvasSize;
    _renderer.paint(canvas, Size(s.x, s.y), host);
  }

  @override
  void onRemove() {
    _renderer.dispose();
    super.onRemove();
  }

  @override
  Color backgroundColor() => MagPalette.sky;
}

class MagRenderer {
  static const chunk = 16;
  final _chunks = <int, ui.Picture>{};
  final _industries = <int, ui.Picture>{};
  final _labels = <int, TextPainter>{};
  MagMap? _map;

  void dispose() {
    for (final p in [..._chunks.values, ..._industries.values]) {
      p.dispose();
    }
    _chunks.clear();
    _industries.clear();
    for (final l in _labels.values) {
      l.dispose();
    }
    _labels.clear();
  }

  ui.Picture _chunk(MagMap map, int cx, int cy) =>
      _chunks.putIfAbsent(cy * 100 + cx, () {
        final rec = ui.PictureRecorder();
        final c = Canvas(rec);
        final x1 = math.min(map.size, (cx + 1) * chunk);
        final y1 = math.min(map.size, (cy + 1) * chunk);
        c.save();
        c.transform(MagIso.ground);
        for (var y = cy * chunk; y < y1; y++) {
          for (var x = cx * chunk; x < x1; x++) {
            paintGround(c, map, x, y);
          }
        }
        c.restore();
        for (var y = cy * chunk; y < y1; y++) {
          for (var x = cx * chunk; x < x1; x++) {
            if (map.at(x, y) == MagTerrain.hill) paintHill(c, map, x, y);
          }
        }
        return rec.endRecording();
      });

  void paint(Canvas canvas, Size size, MagHost host) {
    final w = host.world, cam = host.camera, o = host.overlay;
    if (!identical(_map, w.map)) {
      dispose();
      _map = w.map;
    }
    final map = w.map;
    final view = cam.visibleCells(size, map.size);
    final x0 = view.left.floor(), y0 = view.top.floor();
    final x1 = math.min(map.size - 1, view.right.ceil());
    final y1 = math.min(map.size - 1, view.bottom.ceil());
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(cam.zoom);
    final center = MagIso.project(cam.x, cam.y);
    canvas.translate(-center.dx, -center.dy);

    for (var cy = y0 ~/ chunk; cy <= y1 ~/ chunk; cy++) {
      for (var cx = x0 ~/ chunk; cx <= x1 ~/ chunk; cx++) {
        canvas.drawPicture(_chunk(map, cx, cy));
      }
    }

    // Roads and marks on the ground.
    canvas.save();
    canvas.transform(MagIso.ground);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final r = w.roadAt(x, y);
        if (r == MagRoad.none) continue;
        paintRoad(
          canvas,
          r,
          w.connections(x, y),
          x,
          y,
          map.at(x, y) == MagTerrain.river,
        );
      }
    }
    final sel = o.industry == null ? null : map.industry(o.industry!);
    if (sel != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(sel.x - .1, sel.y - .1, sel.size + .2, sel.size + .2),
          const Radius.circular(.25),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .09
          ..color = MagPalette.mint,
      );
    }
    for (final c in o.plan) {
      canvas.drawRect(
        Rect.fromLTWH(w.cx(c) + .08, w.cy(c) + .08, .84, .84),
        Paint()
          ..color = (o.planOk ? MagPalette.mint : const Color(0xFFE0566B))
              .withValues(alpha: .55),
      );
    }
    for (final c in o.removing) {
      canvas.drawRect(
        Rect.fromLTWH(w.cx(c) + .1, w.cy(c) + .1, .8, .8),
        Paint()..color = const Color(0x99E0566B),
      );
    }
    canvas.restore();

    // Objects in depth order: trees, places and trucks.
    final t = host.time;
    final objects = <(double, void Function())>[];
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if (map.at(x, y) == MagTerrain.forest &&
            w.roadAt(x, y) == MagRoad.none) {
          objects.add((
            x + y + .5,
            () => paintTrees(canvas, map, x, y, cam.zoom),
          ));
        }
      }
    }
    for (final i in map.industries) {
      if (i.x > x1 + 1 ||
          i.y > y1 + 1 ||
          i.x + i.size < x0 ||
          i.y + i.size < y0) {
        continue;
      }
      objects.add((
        i.x + i.y + 2.0 * i.size - 1.5,
        () {
          canvas.drawPicture(
            _industries.putIfAbsent(i.id, () => recordIndustry(i)),
          );
          paintSmoke(canvas, i, t);
        },
      ));
    }
    for (final v in w.vehicles.values) {
      if (!v.onMap) continue;
      final (px, py) = w.positionOf(v);
      if (px < x0 - 1 || py < y0 - 1 || px > x1 + 2 || py > y1 + 2) continue;
      objects.add((
        px + py,
        () => paintTruck(
          canvas,
          px,
          py,
          v.dir,
          v.spec,
          v.load > 0 ? MagPalette.cargo(v.cargo!) : null,
          selected: o.vehicle == v.id,
        ),
      ));
    }
    objects.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, draw) in objects) {
      draw();
    }

    // Names over places, when close enough to read.
    if (cam.zoom >= .7) {
      for (final i in map.industries) {
        if (i.x > x1 || i.y > y1 || i.x + i.size < x0 || i.y + i.size < y0) {
          continue;
        }
        final label = _labels.putIfAbsent(
          i.id,
          () => TextPainter(
            text: TextSpan(
              text: i.name,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: MagPalette.ink,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
        );
        final p = MagIso.project(i.centerX, i.centerY, 56);
        final box = Rect.fromCenter(
          center: p,
          width: label.width + 12,
          height: label.height + 5,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(9)),
          Paint()..color = const Color(0xE6FFFFFF),
        );
        label.paint(canvas, box.topLeft + const Offset(6, 2.5));
      }
    }

    // Income popping up.
    o.floats.removeWhere((f) => t - f.$4 > 1.6);
    for (final (x, y, text, start) in o.floats) {
      final k = (t - start) / 1.6;
      final p = MagIso.project(x, y, 26 + k * 30);
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: MagPalette.teal.withValues(alpha: 1 - k * k),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
    }
    canvas.restore();
  }
}
