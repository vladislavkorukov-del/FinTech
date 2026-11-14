part of 'mag_screen.dart';

/// Touch on the map: a finger moves it and two zoom (in every mode); taps
/// plan roads and removals, place buildings or open a place or a truck.
extension _MagScreenInput on MagistraliScreenState {
  int? _cellAt(Offset p, Size size) {
    final c = camera.toCell(p, size);
    final x = c.dx.floor(), y = c.dy.floor();
    return world.map.inside(x, y) ? world.cellOf(x, y) : null;
  }

  /// A finger on the map always moves it (and two fingers zoom), in every
  /// mode: building is done by taps only, so moving the map never lays a
  /// road by mistake.
  void _scaleStart(ScaleStartDetails d, Size size) =>
      _beginPan(d.localFocalPoint, size);

  void _beginPan(Offset focal, Size size) {
    _focalStart = focal;
    _zoomStart = camera.zoom;
    _cellStart = camera.toCell(focal, size);
  }

  void _scaleUpdate(ScaleUpdateDetails d, Size size) {
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

  void _scaleEnd() => _focalStart = null;

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
          // A tap carries the planned road on from its end to the tapped
          // cell; its end again — a reminder.
          final end = plan.cells.isEmpty ? null : plan.cells.last;
          if (end != null && cell != end) {
            _extending = plan;
            _drawFrom = end;
            _drawTo(cell);
            _extending = null;
          } else {
            say('Нажмите «Построить» или «Отмена»');
          }
          return;
        }
        // Two taps make a road: start, then end. The same cell twice drops
        // the start.
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
      case MagTool.port:
        if (!w.isWater(cell)) return say('Порт ставится на воду');
        final targets = w.portTargets(cell);
        if (targets.isEmpty) {
          return say('Рядом (2 клетки) нет предприятия или поселения');
        }
        final why = w.portBlocker(cell, targets.first.id);
        _refresh(() {
          pendingPort = cell;
          pendingPortPlace = targets.first.id;
          overlay
            ..plan = [cell]
            ..planOk = why == null && w.money >= MagRules.portPrice;
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
        // A tap marks a cell (again: unmarks it); a tap in line with the
        // last mark takes the whole straight stretch between them.
        final marks = [...pendingRemove];
        if (marks.contains(cell)) {
          marks.remove(cell);
        } else {
          final last = marks.isEmpty ? null : marks.last;
          if (last != null &&
              (w.cx(last) == w.cx(cell) || w.cy(last) == w.cy(cell))) {
            final dx = (w.cx(cell) - w.cx(last)).sign;
            final dy = (w.cy(cell) - w.cy(last)).sign;
            var x = w.cx(last) + dx, y = w.cy(last) + dy;
            while (x != w.cx(cell) || y != w.cy(cell)) {
              final c = w.cellOf(x, y);
              if (w.roads[c] == 0 && w.rails[c] == 0) break;
              if (!marks.contains(c)) marks.add(c);
              x += dx;
              y += dy;
            }
          }
          marks.add(cell);
        }
        _refresh(() {
          pendingRemove = marks;
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
        if (i == null && w.ports.containsKey(cell)) {
          unawaited(showPortSheet(this, cell));
          return;
        }
        if (i == null && w.stations.containsKey(cell)) {
          unawaited(showStationSheet(this, cell));
          return;
        }
        if (i == null && w.rails[cell] != 0 && w.roads[cell] == 0) {
          unawaited(showRailSheet(this, cell));
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
                : i.kind == MagIndustryKind.megaproject
                ? showMegaprojectSheet(this, i.id)
                : showIndustrySheet(this, i.id),
          );
        }
    }
  }
}
