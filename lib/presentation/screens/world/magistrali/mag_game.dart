import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_network_art.dart';
import 'mag_curve.dart';
import 'mag_route_art.dart';
import 'mag_terrain_art.dart';
import 'mag_rail_art.dart';
import 'mag_art.dart';
import 'mag_buildings.dart';
import 'mag_town_art.dart';
import 'mag_iso.dart';

/// What the screen wants drawn over the world.
class MagOverlay {
  /// A road being drawn: its cells and whether it can be built.
  List<int> plan = const [];
  bool planOk = true;

  /// Cells marked for removal.
  List<int> removing = const [];
  int? industry, vehicle;

  /// Places with a problem (advice), marked over their names.
  Set<int> problems = const {};

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
  final _industries = <String, ui.Picture>{};
  final _labels = <String, TextPainter>{};
  int _netVersion = -1;
  List<NetChain> _roadChains = const [], _railChains = const [];
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
        // One smooth surface: colours blend across cells (no squares).
        paintTerrain(c, map, cx * chunk, cy * chunk, x1, y1);
        c.restore();
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
    // Roads and track as whole smooth lines (rebuilt when they change).
    if (_netVersion != w.roadVersion) {
      _netVersion = w.roadVersion;
      _roadChains = netChains(w, (c) => w.roads[c]);
      _railChains = netChains(w, (c) => w.rails[c]);
    }
    final netView = Rect.fromLTRB(x0 - 2.0, y0 - 2.0, x1 + 3.0, y1 + 3.0);
    bool seen(NetChain ch) => ch.cells.any(
      (c) => netView.contains(Offset(w.cx(c) + .5, w.cy(c) + .5)),
    );
    for (final ch in _roadChains) {
      if (seen(ch)) paintRoadChain(canvas, ch);
    }
    // Short pieces into the places a road serves.
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final r = w.roadAt(x, y);
        if (r == MagRoad.none) continue;
        for (var d = 0; d < 4; d++) {
          final nx = x + MagDir.dx[d], ny = y + MagDir.dy[d];
          if (map.inside(nx, ny) &&
              !w.hasRoad(nx, ny) &&
              map.industryAt(nx, ny) != null) {
            paintRoadStub(canvas, r, x, y, d);
          }
        }
      }
    }
    for (final s in w.stations.keys) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w.cx(s) + .04, w.cy(s) + .04, .92, .92),
          const Radius.circular(.08),
        ),
        Paint()..color = const Color(0xFFD9D4C7),
      );
    }
    for (final ch in _railChains) {
      if (seen(ch)) paintRailChain(canvas, ch);
    }
    // Piers of ports (stage S9).
    for (final p in w.ports.keys) {
      final x = w.cx(p), y = w.cy(p);
      if (x < x0 - 1 || y < y0 - 1 || x > x1 + 1 || y > y1 + 1) continue;
      paintPier(canvas, x, y);
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
        final ground = map.at(x, y);
        final cell = w.cellOf(x, y);
        final way = w.roads[cell] != 0 || w.rails[cell] != 0;
        if (ground == MagTerrain.river && way) {
          // A bridge with its own model.
          final rail = w.rails[cell] != 0 && w.roads[cell] == 0;
          objects.add((
            x + y + .4,
            () => paintBridge(canvas, w, cell, rail: rail),
          ));
          continue;
        }
        if (ground == MagTerrain.hill && way) {
          // A tunnel: rock covers the way, a portal where it leaves.
          objects.add((x + y + .45, () => paintTunnelCover(canvas, x, y)));
          for (var d = 0; d < 4; d++) {
            final nx = x + MagDir.dx[d], ny = y + MagDir.dy[d];
            if (!map.inside(nx, ny) || map.at(nx, ny) == MagTerrain.hill) {
              continue;
            }
            final n = w.cellOf(nx, ny);
            final joins =
                w.roads[cell] != 0 && w.roads[n] != 0 ||
                w.rails[cell] != 0 && w.rails[n] != 0 ||
                map.industryAt(nx, ny) != null;
            if (joins) {
              objects.add((x + y + .55, () => paintPortal(canvas, w, cell, d)));
            }
          }
        }
        if (ground != MagTerrain.forest && ground != MagTerrain.hill) continue;
        if (ground == MagTerrain.forest && way) continue;
        if (map.industryAt(x, y) != null) continue;
        objects.add((
          x + y + .5,
          ground == MagTerrain.forest
              ? () => paintForest(canvas, map, x, y, cam.zoom)
              : () => paintRocks(canvas, map, x, y),
        ));
      }
    }
    for (final i in map.industries) {
      if (i.left > x1 + 1 ||
          i.top > y1 + 1 ||
          i.right + 1 < x0 ||
          i.bottom + 1 < y0) {
        continue;
      }
      // A settlement is redrawn when it grows.
      final key = i.town != null
          ? '${i.id}:${i.town!.level}:${i.town!.cells.length}'
          : i.kind == MagIndustryKind.megaproject
          ? '${i.id}:${i.projectDone}:${i.projectProgress.values.fold(0, (a, b) => a + b) ~/ 40}'
          : '${i.id}';
      objects.add((
        i.right + i.bottom + .5,
        () {
          canvas.drawPicture(
            _industries.putIfAbsent(key, () => recordIndustry(i)),
          );
          paintSmoke(canvas, i, t);
          if (i.owned) paintOwnerFlag(canvas, i);
        },
      ));
    }
    for (final s in w.stations.keys) {
      final x = w.cx(s), y = w.cy(s);
      if (x < x0 - 1 || y < y0 - 1 || x > x1 + 1 || y > y1 + 1) continue;
      objects.add((x + y + .3, () => paintStationHouse(canvas, x, y)));
    }
    for (final p in w.ports.keys) {
      final x = w.cx(p), y = w.cy(p);
      if (x < x0 - 1 || y < y0 - 1 || x > x1 + 1 || y > y1 + 1) continue;
      objects.add((x + y + .2, () => paintPortCrane(canvas, x, y)));
    }
    for (final v in w.vehicles.values) {
      if (!v.onMap) continue;
      // On the curve of its way, facing along it.
      final (pose, heading) = vehiclePose(w, v);
      final px = pose.dx, py = pose.dy, dir = dirOf(heading);
      // Inside a tunnel it is out of sight.
      if (map.at(w.cx(v.cell), w.cy(v.cell)) == MagTerrain.hill &&
          !v.spec.water) {
        continue;
      }
      if (v.spec.water) {
        if (px < x0 - 2 || py < y0 - 2 || px > x1 + 3 || py > y1 + 3) continue;
        objects.add((
          px + py,
          () => paintShip(
            canvas,
            px,
            py,
            dir,
            v.spec,
            v.load > 0 ? MagPalette.cargo(v.cargo!) : null,
            selected: o.vehicle == v.id,
          ),
        ));
        continue;
      }
      if (v.spec.rail) {
        if (px < x0 - 2 || py < y0 - 2 || px > x1 + 3 || py > y1 + 3) continue;
        final cars = trainCars(w, v);
        objects.add((
          px + py,
          () => paintTrain(
            canvas,
            cars,
            v.spec,
            v.load > 0 ? MagPalette.cargo(v.cargo!) : null,
            selected: o.vehicle == v.id,
          ),
        ));
        continue;
      }
      if (px < x0 - 1 || py < y0 - 1 || px > x1 + 2 || py > y1 + 2) continue;
      objects.add((
        px + py,
        () => paintTruck(
          canvas,
          px,
          py,
          dir,
          v.spec,
          v.load > 0 ? MagPalette.cargo(v.cargo!) : null,
          selected: o.vehicle == v.id,
        ),
      ));
    }
    // The selected vehicle's way, dashed: the leg it drives now and the
    // rest of its route, with its stops numbered.
    final chosen = o.vehicle == null ? null : w.vehicles[o.vehicle!];
    if (chosen != null && chosen.onMap) paintVehicleRoute(canvas, w, chosen);
    objects.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, draw) in objects) {
      draw();
    }

    // Names over places, when close enough to read.
    if (cam.zoom >= .7) {
      for (final i in map.industries) {
        if (i.left > x1 ||
            i.top > y1 ||
            i.right + 1 < x0 ||
            i.bottom + 1 < y0) {
          continue;
        }
        final title = i.town == null
            ? i.name
            : '${i.name} · ${i.town!.spec.name}';
        final label = _labels.putIfAbsent(
          title,
          () => TextPainter(
            text: TextSpan(
              text: title,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: MagPalette.ink,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
        );
        final p = MagIso.project(
          i.centerX,
          i.centerY,
          i.town == null ? 56 : 30 + 6.0 * i.town!.level,
        );
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
        if (w.firstMegapolis == i.id) {
          // The first megalopolis: a golden crown for ever (META-04).
          final cp = box.centerLeft - const Offset(12, 0);
          canvas.drawCircle(cp, 9, Paint()..color = const Color(0xFFD4A017));
          canvas.drawPath(
            Path()
              ..moveTo(cp.dx - 5, cp.dy + 3)
              ..lineTo(cp.dx - 5, cp.dy - 3)
              ..lineTo(cp.dx - 2, cp.dy)
              ..lineTo(cp.dx, cp.dy - 4)
              ..lineTo(cp.dx + 2, cp.dy)
              ..lineTo(cp.dx + 5, cp.dy - 3)
              ..lineTo(cp.dx + 5, cp.dy + 3)
              ..close(),
            Paint()..color = const Color(0xFFFFFFFF),
          );
        }
        if (o.problems.contains(i.id)) {
          // A red mark: something here needs the player (see «Советы»).
          final m = box.centerRight + const Offset(7, 0);
          canvas.drawCircle(m, 6.5, Paint()..color = const Color(0xFFD64B5C));
          canvas.drawRect(
            Rect.fromCenter(
              center: m - const Offset(0, 1),
              width: 1.8,
              height: 5,
            ),
            Paint()..color = const Color(0xFFFFFFFF),
          );
          canvas.drawCircle(
            m + const Offset(0, 3),
            1,
            Paint()..color = const Color(0xFFFFFFFF),
          );
        }
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
