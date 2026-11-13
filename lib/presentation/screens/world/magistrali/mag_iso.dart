import 'dart:typed_data';
import 'dart:ui';

/// The 2.5D projection: grid cells (x, y) and a height z (in screen
/// pixels at zoom 1) to isometric screen space. Game logic never sees it;
/// it only works in cells.
abstract final class MagIso {
  /// Half the width and half the height of a cell's diamond at zoom 1.
  static const hw = 32.0, hh = 16.0;

  static Offset project(double x, double y, [double z = 0]) =>
      Offset((x - y) * hw, (x + y) * hh - z);

  /// The ground plane as a canvas transform: draw in cells, get diamonds.
  static final Float64List ground = Float64List.fromList([
    hw, hh, 0, 0, //
    -hw, hh, 0, 0, //
    0, 0, 1, 0, //
    0, 0, 0, 1,
  ]);

  /// Back from isometric space to cells (on the ground).
  static Offset unproject(Offset iso) {
    final a = iso.dx / hw, b = iso.dy / hh;
    return Offset((a + b) / 2, (b - a) / 2);
  }
}

/// Where the view looks (a cell position) and how close.
class MagCamera {
  MagCamera(this.x, this.y, this.zoom);
  double x, y, zoom;
  static const minZoom = .4, maxZoom = 2.5;

  Offset get _center => MagIso.project(x, y);

  Offset toScreen(Offset iso, Size size) =>
      Offset(size.width / 2, size.height / 2) + (iso - _center) * zoom;

  Offset cellToScreen(double cx, double cy, Size size, [double z = 0]) =>
      toScreen(MagIso.project(cx, cy, z), size);

  /// The ground point (in cells) under a screen point.
  Offset toCell(Offset screen, Size size) => MagIso.unproject(
    (screen - Offset(size.width / 2, size.height / 2)) / zoom + _center,
  );

  /// Cells the screen can show (a rectangle in cells holding the view).
  Rect visibleCells(Size size, int mapSize) {
    final corners = [
      toCell(Offset.zero, size),
      toCell(Offset(size.width, 0), size),
      toCell(Offset(0, size.height), size),
      toCell(Offset(size.width, size.height), size),
    ];
    var l = double.infinity, t = double.infinity;
    var r = -double.infinity, b = -double.infinity;
    for (final c in corners) {
      if (c.dx < l) l = c.dx;
      if (c.dx > r) r = c.dx;
      if (c.dy < t) t = c.dy;
      if (c.dy > b) b = c.dy;
    }
    // Tall things stand above their cell: look a few cells further down.
    return Rect.fromLTRB(
      (l - 1).clamp(0, mapSize.toDouble()),
      (t - 1).clamp(0, mapSize.toDouble()),
      (r + 4).clamp(0, mapSize.toDouble()),
      (b + 4).clamp(0, mapSize.toDouble()),
    );
  }
}
