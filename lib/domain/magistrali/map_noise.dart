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
