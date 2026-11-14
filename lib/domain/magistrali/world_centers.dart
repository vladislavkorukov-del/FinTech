part of 'world.dart';

/// Logistics centres (stage S7: LOG-08, LOG-09, LOG-11, LOG-12). A centre
/// looks after the company's plants and the settlements within its
/// radius: when a plant runs short of an input or a settlement's pantry
/// or growth runs short, it writes a logistics order from the nearest
/// supplier joined by road. The orders reserve cargo and room like any
/// other, and the automatic fleet carries them — so a centre works only
/// with the dispatcher and at least one truck in the fleet (otherwise it
/// would only lock stock). A bigger centre reaches further and keeps more
/// orders open.
extension MagWorldCenters on MagWorld {
  Iterable<MagIndustry> get centers =>
      map.industries.where((i) => i.kind == MagIndustryKind.logisticsCenter);

  int get centerSlots => bonus(MagBonus.logistics).round();

  int centerRadius(MagIndustry c) =>
      MagRules.centerRadius + MagRules.centerRadiusStep * (c.level - 1);

  int centerOrderCap(MagIndustry c) =>
      MagRules.centerOrders + MagRules.centerOrdersStep * (c.level - 1);

  String _centerTag(MagIndustry c) => 'lc:${c.id}';

  /// Orders a centre has open now.
  List<MagOrder> centerOrders(MagIndustry c) =>
      orders.active.where((o) => o.tag == _centerTag(c)).toList();

  /// Why a centre is not writing orders (null: it works).
  String? centerIdle(MagIndustry c) {
    if (!dispatcherUnlocked) return 'Нужна технология «Диспетчерская»';
    if (!vehicles.values.any((v) => v.auto)) {
      return 'Нет машин в автопарке: отметьте «Автопарк» у машины';
    }
    if (!c.supplyPlants && !c.supplyTowns) return 'Снабжение выключено';
    return null;
  }

  /// Places a centre serves.
  Iterable<MagIndustry> centerArea(MagIndustry c) => map.industries.where(
    (i) =>
        i != c &&
        i.distanceTo(c) <= centerRadius(c) &&
        (c.supplyTowns && i.town != null ||
            c.supplyPlants &&
                i.owned &&
                i.town == null &&
                !i.spec.stores &&
                (i.spec.converts.isNotEmpty || i.spec.extra.isNotEmpty)),
  );

  /// What a place is short of now: cargo → (amount, priority). Plants keep
  /// half their input store filled; settlements their pantry for
  /// [MagTowns.pantryDays] and what growth still asks for. Orders already
  /// on their way count.
  Map<MagCargo, (int, int)> shortages(MagIndustry i) {
    final out = <MagCargo, (int, int)>{};
    if (i.town != null) {
      final t = i.town!;
      for (final e in needsOf(i).entries) {
        final target = e.value * MagTowns.pantryDays;
        final have = (t.pantry[e.key] ?? 0) + orders.reservedIn(i.id, e.key);
        if (have * 2 < target) out[e.key] = (target - have, 2);
      }
      for (final e in missingForGrowth(i).entries) {
        final left = e.value - orders.reservedIn(i.id, e.key);
        if (left > 0 && !out.containsKey(e.key)) out[e.key] = (left, 1);
      }
      return out;
    }
    const target = MagRules.inputCap ~/ 2;
    for (final c in {...i.spec.converts.keys, ...i.spec.extra.keys}) {
      final have = (i.input[c] ?? 0) + orders.reservedIn(i.id, c);
      if (have * 2 < target) out[c] = (target - have, 1);
    }
    return out;
  }

  /// What [s] may give for [c] now (a warehouse only what it sends on).
  int _freeAt(MagIndustry s, MagCargo c) {
    if (s.spec.stores) {
      final r = ruleOf(s, c);
      return r.mode == MagStockMode.distribute ? _surplus(s, c, r) : 0;
    }
    return availableOf(s, c);
  }

  void _planCenters() {
    for (final c in centers.toList()) {
      if (centerIdle(c) != null) continue;
      final tag = _centerTag(c);
      var open = centerOrders(c).length;
      final cap = centerOrderCap(c);
      // Settlements' daily needs first, then plants and growth.
      final wants = <(MagIndustry, MagCargo, int, int)>[];
      for (final i in centerArea(c)) {
        for (final e in shortages(i).entries) {
          wants.add((i, e.key, e.value.$1, e.value.$2));
        }
      }
      wants.sort((a, b) {
        if (a.$4 != b.$4) return b.$4.compareTo(a.$4);
        return a.$1.distanceTo(c).compareTo(b.$1.distanceTo(c));
      });
      for (final (to, cargo, need, priority) in wants) {
        if (open >= cap) break;
        // One order at a time for each place and cargo.
        if (orders.active.any(
          (o) => o.tag == tag && o.receiver == to.id && o.cargo == cargo,
        )) {
          continue;
        }
        final sources =
            map.industries.where((s) {
                if (s == to || s.town != null || !s.supplies.contains(cargo)) {
                  return false;
                }
                return _freeAt(s, cargo) >= MagRules.minAutoBatch;
              }).toList()
              ..sort((a, b) => a.distanceTo(to).compareTo(b.distanceTo(to)));
        for (final s in sources) {
          if (!connected(s, to)) continue;
          final amount = [
            math.max(need, MagRules.minAutoBatch),
            _freeAt(s, cargo),
            _batch,
            roomOf(to, cargo) ?? 0,
          ].reduce(math.min);
          if (amount <= 0) continue;
          if (createOrder(
                cargo: cargo,
                from: s.id,
                to: to.id,
                amount: amount,
                priority: priority,
                tag: tag,
              ) ==
              null) {
            open++;
            c.ordersMade++;
            break;
          }
        }
      }
    }
  }

  /// Turns a centre's supply of plants or settlements on or off.
  String? setCenterSupply(int id, {bool? plants, bool? towns}) {
    final c = map.industry(id);
    if (c == null || c.kind != MagIndustryKind.logisticsCenter) {
      return 'Это не логистический центр';
    }
    if (plants != null) c.supplyPlants = plants;
    if (towns != null) c.supplyTowns = towns;
    return null;
  }
}
