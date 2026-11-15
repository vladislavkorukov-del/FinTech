import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_iso.dart';
import 'mag_terrain_art.dart';

/// Trees and rocks recorded once per 16×16 piece of the map (S20): far
/// away the whole map is in view, and drawing every tree each frame was
/// what made the game stutter. Close up they are drawn one by one, in
/// depth order with vehicles and buildings.
class MagDecorCache {
  static const chunk = 16;

  /// Below this zoom the recorded pieces are used.
  static const farZoom = 1.05;
  final _pics = <int, ui.Picture>{};
  Object? _key;

  void dispose() {
    for (final p in _pics.values) {
      p.dispose();
    }
    _pics.clear();
  }

  /// Draws the pieces covering cells [x0]..[x1], [y0]..[y1].
  void paint(
    Canvas c,
    MagWorld w,
    double zoom,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    final lod = zoom < .55 ? 0 : 1;
    final key = (
      MagFoliage.season,
      w.map,
      w.roadVersion,
      w.map.terrainVersion,
      w.map.industries.length,
      lod,
    );
    if (key != _key) {
      dispose();
      _key = key;
    }
    for (var cy = y0 ~/ chunk; cy <= y1 ~/ chunk; cy++) {
      for (var cx = x0 ~/ chunk; cx <= x1 ~/ chunk; cx++) {
        c.drawPicture(
          _pics.putIfAbsent(cy * 1000 + cx, () => _record(w, cx, cy, lod)),
        );
      }
    }
  }

  ui.Picture _record(MagWorld w, int cx, int cy, int lod) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final map = w.map;
    final xs = cx * chunk, ys = cy * chunk;
    final xe = (xs + chunk).clamp(0, map.size),
        ye = (ys + chunk).clamp(0, map.size);
    // Trees go into a few big shapes, one per colour: thousands of small
    // drawings become six. Rocks are fewer and keep their own look.
    final shadow = Path(), firLit = Path(), firDark = Path();
    final leaf = Path(), leafLit = Path();
    for (var s = xs + ys; s <= xe + ye - 2; s++) {
      for (var x = xs; x < xe; x++) {
        final y = s - x;
        if (y < ys || y >= ye || !decorAt(w, x, y)) continue;
        if (map.at(x, y) != MagTerrain.forest) {
          paintRocks(c, map, x, y);
          continue;
        }
        for (final (px, py, sz, fir) in forestTrees(map, x, y)) {
          final p = MagIso.project(px, py);
          if (lod == 0) {
            (fir ? firDark : leaf).addOval(
              Rect.fromCircle(
                center: Offset(p.dx, p.dy - 10 * sz),
                radius: 7 * sz,
              ),
            );
            continue;
          }
          shadow.addOval(
            Rect.fromCenter(
              center: p + Offset(5 * sz, 1.5),
              width: 18 * sz,
              height: 7 * sz,
            ),
          );
          if (fir) {
            for (var k = 0; k < 2; k++) {
              final wd = (15 - k * 5) * sz, base = p.dy - (4 + k * 9) * sz;
              final tip = Offset(p.dx, base - 13 * sz);
              final m = Offset(p.dx + wd * .05, base + 1.5 * sz);
              firLit.addPolygon([Offset(p.dx - wd / 2, base), tip, m], true);
              firDark.addPolygon([m, tip, Offset(p.dx + wd / 2, base)], true);
            }
          } else {
            final ctr = Offset(p.dx, p.dy - 13 * sz);
            leaf.addOval(Rect.fromCircle(center: ctr, radius: 7.5 * sz));
            leafLit.addOval(
              Rect.fromCircle(
                center: ctr - Offset(2 * sz, 3.5 * sz),
                radius: 4 * sz,
              ),
            );
          }
        }
      }
    }
    void fill(Path p, int color) =>
        c.drawPath(p, Paint()..color = Color(color));
    final shades = MagFoliage.leaves(.5);
    final winter = MagFoliage.season == MagSeason.winter;
    fill(shadow, 0x33182418);
    fill(leaf, shades[1].toARGB32());
    fill(leafLit, shades[3].toARGB32());
    fill(firLit, winter ? 0xFFE9EEF1 : 0xFF3B8F55);
    fill(firDark, lod == 0 ? 0xFF2F7546 : 0xFF256B3D);
    return rec.endRecording();
  }
}

/// A forest or rock cell drawn as decoration (no way, no building on it).
bool decorAt(MagWorld w, int x, int y) {
  final g = w.map.at(x, y);
  if (g != MagTerrain.forest && g != MagTerrain.hill) return false;
  final cell = w.cellOf(x, y);
  if (g == MagTerrain.forest && (w.roads[cell] != 0 || w.rails[cell] != 0)) {
    return false;
  }
  return w.map.industryAt(x, y) == null;
}

/// Names of the mountain ranges (MAP-07), seen from afar.
void paintMountainNames(Canvas c, MagWorld w, double zoom) {
  if (zoom > 1.1) return;
  for (final m in w.mountains) {
    final p = MagIso.project(m.x, m.y, 40);
    final tp = TextPainter(
      text: TextSpan(
        text: '▲ ${m.name}',
        style: TextStyle(
          fontSize: 11 / zoom.clamp(.6, 1.0),
          fontWeight: FontWeight.w800,
          color: const Color(0xFF5B4E3E),
          shadows: const [Shadow(color: Color(0xCCFFFFFF), blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }
}

/// MAP-09: each region's land tints the ground a little (new companies).
void paintBiomeTint(Canvas c, MagWorld w) {
  if (!w.biomesOn) return;
  final s = (w.size / 3).ceil().toDouble();
  for (var r = 0; r < 9; r++) {
    final color = switch (w.biomeOf(r)) {
      MagBiome.taiga => const Color(0x2A1E4A3A),
      MagBiome.steppe => const Color(0x30E0B850),
      MagBiome.highlands => const Color(0x24806A50),
      MagBiome.lakes => const Color(0x2240A6B8),
      MagBiome.meadows => const Color(0x00000000),
    };
    if (color.a == 0) continue;
    c.drawRect(
      Rect.fromLTWH((r % 3) * s, (r ~/ 3) * s, s, s),
      Paint()..color = color,
    );
  }
}

/// Names of the lands, seen from far away.
void paintBiomeNames(Canvas c, MagWorld w, double zoom) {
  if (!w.biomesOn || zoom > .75) return;
  final s = (w.size / 3).ceil();
  for (var r = 0; r < 9; r++) {
    final p = MagIso.project((r % 3) * s + s / 2, (r ~/ 3) * s + s / 2, 10);
    final tp = TextPainter(
      text: TextSpan(
        text: MagWorldBiomes.biomeName(w.biomeOf(r)).toUpperCase(),
        style: TextStyle(
          fontSize: 13 / zoom.clamp(.45, 1.0),
          letterSpacing: 3,
          fontWeight: FontWeight.w900,
          color: const Color(0xCC24413A),
          shadows: const [
            Shadow(color: Color(0xE6FFFFFF), blurRadius: 4),
            Shadow(color: Color(0x99FFFFFF), blurRadius: 10),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }
}

/// S22: the season on the land — snow in winter, gold in autumn, fresh
/// green in spring.
void paintSeasonTint(Canvas c, MagWorld w) {
  if (!w.livingWorld) return;
  final color = switch (w.season) {
    MagSeason.winter => const Color(0x8CF4F7FA),
    MagSeason.autumn => const Color(0x22D9902E),
    MagSeason.spring => const Color(0x0F8FD06A),
    MagSeason.summer => const Color(0x00000000),
  };
  if (color.a == 0) return;
  c.drawRect(
    Rect.fromLTWH(0, 0, w.size.toDouble(), w.size.toDouble()),
    Paint()..color = color,
  );
}
