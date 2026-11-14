part of 'map.dart';

/// Smooth value noise in 0..1 (the map generator's land).
double _valueNoise(int seed, double x, double y) {
  final x0 = x.floor(), y0 = y.floor();
  final fx = x - x0, fy = y - y0;
  double h(int ix, int iy) {
    var n = ix * 374761393 + iy * 668265263 + seed * 2147483647;
    n = (n ^ (n >> 13)) * 1274126177;
    n = n ^ (n >> 16);
    return (n & 0xffff) / 0xffff;
  }

  double s(double v) => v * v * (3 - 2 * v);
  final a = h(x0, y0), b = h(x0 + 1, y0);
  final c = h(x0, y0 + 1), d = h(x0 + 1, y0 + 1);
  final u = s(fx), v = s(fy);
  return (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v;
}

/// The big river of generator 5 (1.83): three to four cells wide, from the
/// top edge to the bottom, always east of the start (so the first line
/// never needs a bridge) and splitting the map in two.
void _carveBigRiver(Uint8List t, int size, int seed, math.Random rnd) {
  final c = size ~/ 2;
  final base = size * (.7 + rnd.nextDouble() * .06);
  final swing = size * .09;
  for (var y = 0; y < size; y++) {
    final m = _valueNoise(seed + 991, y / 15, .5) * 2 - 1;
    final m2 = _valueNoise(seed + 997, y / 6, .5) * 2 - 1;
    final cx = (base + m * swing + m2 * 1.5).clamp(c + 18.0, size - 6.0);
    final half = 1.4 + _valueNoise(seed + 983, y / 9, .5) * .9;
    for (var x = (cx - half).round(); x <= (cx + half).round(); x++) {
      if (x < 0 || x >= size) continue;
      t[y * size + x] = MagTerrain.river.index;
    }
  }
  // Each cell of the river touches the next row's (no diagonal gaps).
  for (var y = 1; y < size; y++) {
    for (var x = 1; x < size - 1; x++) {
      if (t[y * size + x] != MagTerrain.river.index) continue;
      final up = t[(y - 1) * size + x];
      if (up == MagTerrain.river.index || up == MagTerrain.lake.index) continue;
      final l = t[(y - 1) * size + x - 1] == MagTerrain.river.index;
      final r = t[(y - 1) * size + x + 1] == MagTerrain.river.index;
      if (l || r) t[(y - 1) * size + x] = MagTerrain.river.index;
    }
  }
}
