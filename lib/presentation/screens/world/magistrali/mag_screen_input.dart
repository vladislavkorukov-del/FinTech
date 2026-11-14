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
    if ((tool == MagTool.road ||
            tool == MagTool.rail ||
            tool == MagTool.remove) &&
        d.pointerCount == 1) {
      final at = _downAt ?? d.localFocalPoint;
      var from = _cellAt(at, size);
      // Starting at (or right next to) the end of a drawn road carries it
      // on instead of starting a new one.
      final plan = pendingRoad;
      _extending = null;
      if (from != null &&
          (tool == MagTool.road || tool == MagTool.rail) &&
          plan != null) {
        final end = plan.cells.isEmpty ? null : plan.cells.last;
        if (end != null && _near(from, end)) {
          _extending = plan;
          from = end;
        }
      }
      if (from != null) {
        // Nothing is drawn until the finger reaches another cell: a short
        // wobble on one cell never makes a road.
        _drawFrom = from;
        _drawing = true;
        _drawStarted = false;
        return;
      }
    }
    _beginPan(d.localFocalPoint, size);
  }

  /// The same cell or one of its eight neighbours.
  bool _near(int a, int b) =>
      (world.cx(a) - world.cx(b)).abs() <= 1 &&
      (world.cy(a) - world.cy(b)).abs() <= 1;

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
        if (c != null && (_drawStarted || c != _drawFrom)) {
          _drawStarted = true;
          _drawTo(c);
        }
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
    _extending = null;
    if (!_drawStarted) return; // stayed on one cell: nothing drawn
    _refresh(() {}); // shows the confirm bar
  }

  void _drawTo(int to) {
    final w = world, from = _drawFrom!;
    if (tool == MagTool.road || tool == MagTool.rail) {
      final plan = tool == MagTool.rail
          ? w.planRail(w.cx(from), w.cy(from), w.cx(to), w.cy(to))
          : w.planRoad(w.cx(from), w.cy(from), w.cx(to), w.cy(to), roadType);
      final base = _extending;
      final full = base == null ? plan : w.joinPlans(base, plan);
      pendingRoad = full;
      overlay
        ..plan = full.cells.isEmpty ? [from] : full.cells
        ..planOk = full.error == null && full.cost <= w.money;
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
          if (w.roads[c] != 0 || w.rails[c] != 0) c,
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
      case MagTool.rail:
        final plan = pendingRoad;
        if (plan != null) {
          // A drawn road is never lost to a stray tap: a tap next to its
          // end carries it on, anywhere else only reminds what to do.
          final end = plan.cells.isEmpty ? null : plan.cells.last;
          if (end != null && cell != end && _near(cell, end)) {
            _extending = plan;
            _drawFrom = end;
            _drawTo(cell);
            _extending = null;
          } else {
            say('Нажмите «Построить» или «Отмена»');
          }
          return;
        }
        // Two taps also make a road: start, then end. The same cell twice
        // drops the start.
        final start = _tapStart;
        if (start == null) {
          _refresh(() {
            _tapStart = cell;
            overlay
              ..plan = [cell]
              ..planOk = true;
          });
          say('Начало отмечено. Коснитесь, где дорога закончится');
        } else if (start == cell) {
          _refresh(_clearPending);
        } else {
          _drawFrom = start;
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
      case MagTool.station:
        if (w.rails[cell] == 0) return say('Станция ставится на путь');
        final targets = w.stationTargets(cell);
        if (targets.isEmpty) {
          return say('Рядом (2 клетки) нет предприятия или поселения');
        }
        final why = w.stationBlocker(cell, targets.first.id);
        _refresh(() {
          pendingStation = cell;
          pendingStationPlace = targets.first.id;
          overlay
            ..plan = [cell]
            ..planOk = why == null && w.money >= MagRules.stationPrice;
        });
        if (why != null) say(why);
      case MagTool.remove:
        if (w.roads[cell] == 0 && w.rails[cell] == 0) {
          return say('Здесь нет дороги или пути');
        }
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
        if (i == null && w.stations.containsKey(cell)) {
          unawaited(showStationSheet(this, cell));
          return;
        }
        if (i == null && w.roads[cell] != 0) {
          _refresh(() {
            overlay
              ..industry = null
              ..vehicle = null;
          });
          unawaited(showRoadSheet(this, cell));
          return;
        }
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
                : i.kind == MagIndustryKind.logisticsCenter
                ? showCenterSheet(this, i.id)
                : showIndustrySheet(this, i.id),
          );
        }
    }
  }
}
