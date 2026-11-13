import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../domain/finorio/finorio.dart';
import 'finorio_sprites.dart';

/// The painted ground under the map: six landscapes blended by soft masks
/// (Finorio_Terrain_Backgrounds). Each landscape's weight is 1 on its cells,
/// spread over two cells around borders and normalised; the GPU's bilinear
/// filtering of the per-cell masks then gives smooth transitions, triple
/// joins included. Built once per map; drawing touches only the visible
/// rectangle.
class FinGround {
  FinGround._(this.map, this._masks, this._present);
  final FinTerrainMap map;
  final Map<int, ui.Image> _masks;
  final Set<int> _present;

  static const blur = 2;

  static Future<FinGround> build(FinTerrainMap map) async {
    final w = map.width, h = map.height;
    final n = FinConfig.terrainThemes.length;
    final present = <int>{};
    // Box-blurred one-hot weights (separable), normalised.
    final weights = List.generate(n, (_) => Float32List(w * h));
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final b = map.biomeAt(x, y);
        present.add(b);
        weights[b][y * w + x] = 1;
      }
    }
    void pass(Float32List f, bool horizontal) {
      final copy = Float32List.fromList(f);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var sum = 0.0;
          var count = 0;
          for (var k = -blur; k <= blur; k++) {
            final xx = horizontal ? x + k : x, yy = horizontal ? y : y + k;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            sum += copy[yy * w + xx];
            count++;
          }
          f[y * w + x] = sum / count;
        }
      }
    }

    for (final b in present) {
      pass(weights[b], true);
      pass(weights[b], false);
    }
    final masks = <int, ui.Image>{};
    for (final b in present) {
      final pixels = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        var total = 0.0;
        for (final k in present) {
          total += weights[k][i];
        }
        final a = (weights[b][i] / (total == 0 ? 1 : total) * 255).round();
        pixels[i * 4] = 255;
        pixels[i * 4 + 1] = 255;
        pixels[i * 4 + 2] = 255;
        pixels[i * 4 + 3] = a.clamp(0, 255);
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        w,
        h,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      masks[b] = await done.future;
    }
    return FinGround._(map, masks, present);
  }

  /// Cells each texture repeat spans (mirrored so tiles meet seamlessly).
  static const repeatCells = 16.0;

  /// Draws the blended ground over [visible] (world units, one cell = 1).
  void paint(Canvas c, Rect visible) {
    final bank = FinSpriteBank.current;
    if (bank == null) return;
    final world = Rect.fromLTWH(
      0,
      0,
      map.width.toDouble(),
      map.height.toDouble(),
    );
    final area = visible.intersect(world);
    if (area.isEmpty) return;
    c.saveLayer(area, Paint());
    for (final b in _present) {
      final tex = bank.landscape(b);
      final mask = _masks[b];
      if (tex == null || mask == null) continue;
      final k = repeatCells / tex.width;
      c.saveLayer(area, Paint()..blendMode = BlendMode.plus);
      c.drawRect(
        area,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..shader = ImageShader(
            tex,
            TileMode.mirror,
            TileMode.mirror,
            Matrix4.diagonal3Values(k, k, 1).storage,
          ),
      );
      c.drawImageRect(
        mask,
        Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()),
        world,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..filterQuality = FilterQuality.low,
      );
      c.restore();
    }
    c.restore();
  }

  void dispose() {
    for (final m in _masks.values) {
      m.dispose();
    }
    _masks.clear();
  }
}
