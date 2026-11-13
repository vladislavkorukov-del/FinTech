import 'dart:math' as math;
import 'dart:typed_data';

import 'config.dart';

/// The ground of one map, made from its seed. Stored as one byte per cell
/// and read by chunks, so later maps can grow chunk by chunk.
class FinTerrainMap {
  FinTerrainMap._(
    this.seed,
    this.width,
    this.height,
    this._cells, [
    Uint8List? biomes,
  ]) : _biomes = biomes ?? _makeBiomes(seed, width);

  final int seed, width, height;
  final Uint8List _cells;

  /// The landscape of each cell (index into [FinConfig.terrainThemes]):
  /// large regions with soft borders, drawn blended on screen. View only:
  /// it never changes what can be built or mined.
  final Uint8List _biomes;
  int biomeAt(int x, int y) =>
      _biomes[(y.clamp(0, height - 1)) * width + x.clamp(0, width - 1)];
  List<int> get biomeBytes => List.unmodifiable(_biomes);

  FinTerrain at(int x, int y) =>
      inside(x, y) ? FinTerrain.values[_cells[y * width + x]] : FinTerrain.rock;
  bool inside(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;
  bool buildable(int x, int y) => inside(x, y) && at(x, y) != FinTerrain.rock;

  /// A hand-made map (future sectors, tests): ground with [marks].
  factory FinTerrainMap.custom(
    int seed,
    int size,
    Map<(int, int), FinTerrain> marks,
  ) {
    final cells = Uint8List(size * size);
    marks.forEach((c, t) => cells[c.$2 * size + c.$1] = t.index);
    return FinTerrainMap._(seed, size, size, cells, Uint8List(size * size));
  }

  /// The cells as saved (one byte each).
  List<int> get bytes => List.unmodifiable(_cells);

  /// A saved map; refuses a wrong size or unknown terrain.
  factory FinTerrainMap.fromBytes(
    int seed,
    int size,
    List<int> bytes, {
    List<int>? biomes,
  }) {
    if (bytes.length != size * size ||
        bytes.any((b) => b < 0 || b >= FinTerrain.values.length) ||
        biomes != null &&
            (biomes.length != size * size ||
                biomes.any(
                  (b) => b < 0 || b >= FinConfig.terrainThemes.length,
                ))) {
      throw const FormatException('Bad Finorio map');
    }
    return FinTerrainMap._(
      seed,
      size,
      size,
      Uint8List.fromList(bytes),
      biomes == null ? null : Uint8List.fromList(biomes),
    );
  }

  /// The start area at the centre: always holds every deposit the
  /// tutorial needs.
  int get startX => width ~/ 2;
  int get startY => height ~/ 2;
  static const startRadius = 9;

  /// Landscapes: six soft noise fields, warped so borders meander; each
  /// cell takes the strongest. Large regions (about 25 cells across).
  static Uint8List _makeBiomes(int seed, int size) {
    final out = Uint8List(size * size);
    final noise = _Noise(seed ^ 0x5bd1e995);
    final n = FinConfig.terrainThemes.length;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final wx = x + 9 * (noise.at(x / 17, y / 17, 40) - .5);
        final wy = y + 9 * (noise.at(x / 17, y / 17, 41) - .5);
        var best = 0;
        var top = -1.0;
        for (var b = 0; b < n; b++) {
          final v =
              noise.at(wx / 24, wy / 24, 50 + b) * .8 +
              noise.at(wx / 9, wy / 9, 60 + b) * .2;
          if (v > top) {
            top = v;
            best = b;
          }
        }
        out[y * size + x] = best;
      }
    }
    return out;
  }

  static FinTerrainMap generate(int seed, {int size = FinRules.mapSize}) {
    final cells = Uint8List(size * size);
    final noise = _Noise(seed);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final rock =
            noise.at(x / 10, y / 10, 1) * .75 + noise.at(x / 4, y / 4, 4) * .25;
        final ore =
            noise.at(x / 7, y / 7, 2) * .7 + noise.at(x / 3, y / 3, 5) * .3;
        final kind = noise.at(x / 13, y / 13, 3);
        var t = FinTerrain.ground;
        if (rock > .73) {
          t = FinTerrain.rock;
        } else if (ore > .64) {
          t = [
            FinTerrain.iron,
            FinTerrain.copper,
            FinTerrain.crystal,
            FinTerrain.biomass,
          ][(kind * 4).floor().clamp(0, 3)];
        }
        cells[y * size + x] = t.index;
      }
    }
    final map = FinTerrainMap._(seed, size, size, cells);
    map._prepareStart();
    return map;
  }

  void _set(int x, int y, FinTerrain t) {
    if (inside(x, y)) _cells[y * width + x] = t.index;
  }

  /// Clears rock around the start and places one patch of each deposit at
  /// seed-chosen spots on a ring, so the tutorial can always be finished.
  void _prepareStart() {
    for (var y = startY - startRadius; y <= startY + startRadius; y++) {
      for (var x = startX - startRadius; x <= startX + startRadius; x++) {
        final d = math.sqrt(math.pow(x - startX, 2) + math.pow(y - startY, 2));
        if (d <= startRadius && at(x, y) == FinTerrain.rock) {
          _set(x, y, FinTerrain.ground);
        }
        // Natural deposits near the centre are cleared for building room.
        if (d <= 3) _set(x, y, FinTerrain.ground);
      }
    }
    final r = math.Random(seed);
    final start = r.nextDouble() * math.pi * 2;
    const kinds = [
      FinTerrain.iron,
      FinTerrain.copper,
      FinTerrain.crystal,
      FinTerrain.biomass,
    ];
    for (var k = 0; k < kinds.length; k++) {
      final angle = start + k * math.pi / 2;
      final cx = (startX + math.cos(angle) * 6).round();
      final cy = (startY + math.sin(angle) * 6).round();
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx.abs() + dy.abs() <= 1 || r.nextDouble() < .6) {
            _set(cx + dx, cy + dy, kinds[k]);
          }
        }
      }
    }
  }

  /// How many cells of each deposit lie within [radius] of the start.
  Map<FinTerrain, int> depositsNearStart([int radius = startRadius]) {
    final out = <FinTerrain, int>{};
    for (var y = startY - radius; y <= startY + radius; y++) {
      for (var x = startX - radius; x <= startX + radius; x++) {
        final t = at(x, y);
        if (FinConfig.deposits.containsKey(t)) out[t] = (out[t] ?? 0) + 1;
      }
    }
    return out;
  }
}

/// Smooth value noise from integer hashing: the same seed, the same map.
class _Noise {
  _Noise(this.seed);
  final int seed;

  double _hash(int x, int y, int layer) {
    var h =
        (x * 374761393 +
            y * 668265263 +
            seed * 2246822519 +
            layer * 3266489917) &
        0xffffffff;
    h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff;
    h ^= h >> 16;
    return (h & 0xffffff) / 0xffffff;
  }

  double at(double x, double y, int layer) {
    final x0 = x.floor(), y0 = y.floor();
    final fx = x - x0, fy = y - y0;
    double s(double t) => t * t * (3 - 2 * t);
    final a = _hash(x0, y0, layer), b = _hash(x0 + 1, y0, layer);
    final c = _hash(x0, y0 + 1, layer), d = _hash(x0 + 1, y0 + 1, layer);
    final top = a + (b - a) * s(fx), bottom = c + (d - c) * s(fx);
    return top + (bottom - top) * s(fy);
  }
}
