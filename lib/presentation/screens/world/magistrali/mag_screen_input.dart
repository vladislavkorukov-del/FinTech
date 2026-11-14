part of 'mag_screen.dart';

/// Touch on the map: pan and pinch, drawing roads and removals, tapping
/// to place buildings or open a place or a truck.
extension _MagScreenInput on MagistraliScreenState {
  int? _cellAt(Offset p, Size size) {
    final c = camera.toCell(p, size);
    final x = c.dx.floor(), y = c.dy.floor();
    return world.map.inside(x, y) ? world.cellOf(x, y) : null;
  }

  void _scaleStart(ScaleStartDetails d, Size size) {
    if ((tool == MagTool.road || tool == MagTool.remove) &&
        d.pointerCount == 1) {
      _drawFrom = _cellAt(_downAt ?? d.localFocalPoint, size);
      if (_drawFrom != null) {
        _drawing = true;
        _drawTo(_drawFrom!);
        return;
      }
    }
    _beginPan(d.localFocalPoint, size);
  }

  void _beginPan(Offset focal, Size size) {
    _drawing = false;
    _focalStart = focal;
    _zoomStart = camera.zoom;
    _cellStart = camera.toCell(focal, size);
  }

  void _scaleUpdate(ScaleUpdateDetails d, Size size) {
    if (_drawing) {
      if (d.pointerCount > 1) {
        _refresh(_clearPending);
        _beginPan(d.localFocalPoint, size);
        _zoomStart = camera.zoom / d.scale;
      } else {
        final c = _cellAt(d.localFocalPoint, size);
        if (c != null) _drawTo(c);
        return;
      }
    }
    if (_focalStart == null) return;
    final cam = camera;
    cam.zoom = (_zoomStart * d.scale).clamp(
      MagCamera.minZoom,
      MagCamera.maxZoom,
    );
    // Keep the cell under the fingers where it was.
    final now = cam.toCell(d.localFocalPoint, size);
    final n = world.size.toDouble();
    cam
      ..x = (cam.x + _cellStart.dx - now.dx).clamp(0, n)
      ..y = (cam.y + _cellStart.dy - now.dy).clamp(0, n);
  }

  void _scaleEnd() {
    _focalStart = null;
    if (!_drawing) return;
    _drawing = false;
    _refresh(() {}); // shows the confirm bar
  }

  void _drawTo(int to) {
    final w = world, from = _drawFrom!;
    if (tool == MagTool.road) {
      final plan = w.planRoad(
        w.cx(from),
        w.cy(from),
        w.cx(to),
        w.cy(to),
        roadType,
      );
      pendingRoad = plan;
      overlay
        ..plan = plan.cells.isEmpty ? [from] : plan.cells
        ..planOk = plan.error == null && plan.cost <= w.money;
    } else {
      // Removal follows a straight L from the first cell.
      final cells = <int>[];
      final fx = w.cx(from), fy = w.cy(from), tx = w.cx(to), ty = w.cy(to);
      for (var x = fx; x != tx + (tx >= fx ? 1 : -1); x += tx >= fx ? 1 : -1) {
        cells.add(w.cellOf(x, fy));
      }
      for (var y = fy; y != ty + (ty >= fy ? 1 : -1); y += ty >= fy ? 1 : -1) {
        if (y != fy) cells.add(w.cellOf(tx, y));
      }
      pendingRemove = [
        for (final c in cells)
          if (w.roads[c] != 0) c,
      ];
      overlay.removing = pendingRemove;
    }
    _refresh(() {});
  }

  void _tap(Offset p, Size size) {
    final cell = _cellAt(p, size);
    if (cell == null) return;
    final w = world;
    switch (tool) {
      case MagTool.road:
        // Two taps also make a road: start, then end.
        if (_tapStart == null || pendingRoad != null) {
          _refresh(() {
            _clearPending();
            _tapStart = cell;
            overlay
              ..plan = [cell]
              ..planOk = true;
          });
          say('Теперь коснитесь, где дорога закончится');
        } else {
          _drawFrom = _tapStart;
          _drawTo(cell);
          _tapStart = null;
        }
      case MagTool.warehouse:
        // The tapped cell is the warehouse's top corner (2×2).
        final x = w.cx(cell), y = w.cy(cell);
        final why = w.warehouseBlocker(x, y);
        _refresh(() {
          pendingWarehouse = cell;
          overlay
            ..plan = [
              for (var dy = 0; dy < 2; dy++)
                for (var dx = 0; dx < 2; dx++)
                  if (w.map.inside(x + dx, y + dy)) w.cellOf(x + dx, y + dy),
            ]
            ..planOk = why == null && w.money >= w.warehousePrice;
        });
        if (why != null) say(why);
      case MagTool.industry:
        final kind = buildKind;
        if (kind == null) return;
        final x = w.cx(cell), y = w.cy(cell);
        final s = MagRules.industries[kind]!.size;
        final why = w.buildBlocker(kind, x, y);
        _refresh(() {
          pendingIndustry = cell;
          overlay
            ..plan = [
              for (var dy = 0; dy < s; dy++)
                for (var dx = 0; dx < s; dx++)
                  if (w.map.inside(x + dx, y + dy)) w.cellOf(x + dx, y + dy),
            ]
            ..planOk = why == null && w.money >= w.buildPrice(kind);
        });
        if (why != null) say(why);
      case MagTool.remove:
        if (w.roads[cell] == 0) return say('Здесь нет дороги');
        _refresh(() {
          pendingRemove = [...pendingRemove, cell];
          overlay.removing = pendingRemove;
        });
      case MagTool.view:
        // A truck under the finger first, then a place.
        for (final v in w.vehicles.values) {
          if (!v.onMap) continue;
          final (x, y) = w.positionOf(v);
          if ((camera.cellToScreen(x, y, size) - p).distance < 22) {
            _refresh(() {
              overlay.vehicle = v.id;
              overlay.industry = null;
            });
            unawaited(showVehicleSheet(this, v.id));
            return;
          }
        }
        final i = w.map.industryAt(w.cx(cell), w.cy(cell));
        _refresh(() {
          overlay.industry = i?.id;
          overlay.vehicle = null;
        });
        if (i != null) {
          unawaited(
            i.town != null
                ? showTownSheet(this, i.id)
                : i.spec.stores
                ? showWarehouseSheet(this, i.id)
                : showIndustrySheet(this, i.id),
          );
        }
    }
  }
}
