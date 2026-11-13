import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../../../../domain/magistrali/magistrali.dart';

/// Painted sprites that replace the procedural shapes, one file per key in
/// `assets/magistrali/sprites/` (PNG or WebP):
///
/// * `industry_<kind>` — a place, drawn on its footprint (kind: farm,
///   sawmill, mine, foodPlant, factory, city, village);
/// * `truck_<model>_<dir>` — a truck facing up, right, down or left
///   (dir 0..3; model: pickup, lorry, tractor).
///
/// A missing file simply keeps the drawn shape, so sprites can be added
/// one at a time without touching the game's logic.
class MagSprites {
  MagSprites._(this._images);
  final Map<String, ui.Image> _images;

  /// The set the open game uses (null: everything is drawn).
  static MagSprites? current;

  static const root = 'assets/magistrali/sprites';

  static List<String> get keys => [
    for (final k in MagIndustryKind.values) 'industry_${k.name}',
    for (final t in MagRules.trucks)
      for (var d = 0; d < 4; d++) 'truck_${t.id}_$d',
  ];

  static Future<MagSprites> load() async {
    final images = <String, ui.Image>{};
    for (final key in keys) {
      for (final ext in ['png', 'webp']) {
        try {
          final data = await rootBundle.load('$root/$key.$ext');
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          images[key] = (await codec.getNextFrame()).image;
          codec.dispose();
          break;
        } on Object {
          continue; // not painted yet
        }
      }
    }
    return MagSprites._(images);
  }

  ui.Image? industry(MagIndustryKind k) => _images['industry_${k.name}'];
  ui.Image? truck(String model, int dir) => _images['truck_${model}_$dir'];

  void dispose() {
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
  }
}
