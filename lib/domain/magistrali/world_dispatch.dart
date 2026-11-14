part of 'world.dart';

/// The automatic dispatcher (stage 3): trucks the player puts into the
/// automatic fleet take waiting orders by themselves. Every few ticks the
/// most urgent orders are matched, one by one, with the best free fleet
/// truck by a clear score of cost, time, filled room and urgency; the
/// chosen truck must reach the supplier by road. Trucks outside the fleet
/// are never touched.
extension MagWorldDispatch on MagWorld {
  bool get dispatcherUnlocked => bonus(MagBonus.dispatcher) > 0;

  /// Puts a truck into the automatic fleet (it leaves its route first) or
  /// takes it out (an order in work is finished first, not dropped).
  String? setAuto(int vehicleId, bool on) {
    final v = vehicles[vehicleId];
    if (v == null) return 'Нет такой машины';
    if (on && !dispatcherUnlocked) return 'Нужна технология «Диспетчерская»';
    if (on && (v.spec.rail || v.spec.water)) {
      return 'Поезда и суда ходят только по маршрутам';
    }
    if (on && v.routeId != null) _park(v);
    v.auto = on;
    return null;
  }

  Iterable<MagVehicle> get autoFleet => vehicles.values.where((v) => v.auto);

  /// Score of [v] for [o] (lower is better) and why, or null if it cannot
  /// take it.
  (double, String)? scoreFor(MagOrder o, MagVehicle v) {
    if (!v.auto || !isFree(v) || capacityOf(v) < o.amount) return null;
    final from = map.industry(o.supplier), to = map.industry(o.receiver);
    if (from == null || to == null) return null;
    final empty = v.onMap
        ? (cx(v.cell) + .5 - from.centerX).abs() +
              (cy(v.cell) + .5 - from.centerY).abs()
        : MagDispatch.garageCells.toDouble();
    final loaded = from.distanceTo(to).toDouble();
    final cells = empty + loaded;
    final seconds = cells / (speedOf(v) * wearFactor(v));
    final cost = cells * runningCostOf(v);
    final waste = (capacityOf(v) - o.amount).toDouble();
    final k = MagDispatchWeights.of(dispatchMode);
    final age = (tick - o.createdTick) / MagRules.ticksPerDay;
    final score =
        k.cost * cost +
        k.time * seconds +
        k.waste * waste -
        MagDispatch.priorityBonus * o.priority -
        MagDispatch.agePerDay * age;
    final why =
        '${empty.round()} кл. до погрузки, ${seconds.round()} с в пути, '
        '${cost.round()} кр топлива, груз ${o.amount}/${capacityOf(v)}';
    return (score, why);
  }

  /// One dispatcher pass: returns how many orders got a truck.
  int dispatch() {
    if (!dispatcherUnlocked) return 0;
    final free = autoFleet.where(isFree).toList();
    if (free.isEmpty) return 0;
    final waiting =
        orders.active.where((o) => o.status == MagOrderStatus.pending).toList()
          ..sort((a, b) {
            final p = b.priority.compareTo(a.priority);
            return p != 0 ? p : a.createdTick.compareTo(b.createdTick);
          });
    var n = 0;
    for (final o in waiting) {
      if (free.isEmpty) break;
      final from = map.industry(o.supplier)!;
      // An order between places not joined by road waits for a road.
      if (!connected(from, map.industry(o.receiver)!)) continue;
      final candidates = <(double, String, MagVehicle)>[];
      for (final v in free) {
        final s = scoreFor(o, v);
        if (s != null) candidates.add((s.$1, s.$2, v));
      }
      candidates.sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$3.id.compareTo(b.$3.id);
      });
      for (final (_, why, v) in candidates) {
        // The truck must reach the supplier by road (from the garage it
        // starts there, which needs a road to the supplier).
        final reach = v.onMap
            ? roadPath([v.cell, ..._yardAround(v.cell)], from) != null
            : accessCells(from).isNotEmpty;
        if (!reach) continue;
        if (assignOrder(o.id, v.id) != null) continue;
        free.remove(v);
        n++;
        dispatchLog.add(
          MagDispatchNote(tick: tick, order: o.id, vehicle: v.id, reason: why),
        );
        if (dispatchLog.length > MagDispatch.log) dispatchLog.removeAt(0);
        break;
      }
    }
    return n;
  }
}
