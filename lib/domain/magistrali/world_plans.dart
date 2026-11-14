part of 'world.dart';

/// One investment the planner suggests (FIN-14): what, what it costs,
/// what it should bring a day, and what to open to do it.
class MagInvestment {
  const MagInvestment({
    required this.kind,
    required this.title,
    required this.detail,
    required this.cost,
    this.daily,
    this.routeId,
    this.industryId,
    this.cell,
    this.model,
  });
  final MagInvestmentKind kind;
  final String title, detail;
  final int cost;

  /// Expected extra profit a day (null: no money estimate, e.g. a jam).
  final double? daily;
  final int? routeId, industryId, cell;
  final String? model;

  /// Days to earn the cost back (null: not known).
  int? get paybackDays =>
      daily == null || daily! <= 0 ? null : (cost / daily!).ceil();
}

enum MagInvestmentKind { vehicle, upgrade, business, road }

/// Copying lines (ROUTE-12), cargo priorities (ROUTE-09) and the
/// investment planner (FIN-14).
extension MagWorldPlans on MagWorld {
  // ---- ROUTE-12 ----

  /// A copy of route [id] — the same stops, orders and priorities, or the
  /// same line the other way round ([reverse]).
  String? copyRoute(int id, {bool reverse = false}) {
    final r = routes[id];
    if (r == null) return 'Нет такого маршрута';
    final n = r.stops.length;
    int map(int k) => reverse ? n - 1 - k : k;
    final stops = [for (var k = 0; k < n; k++) r.stops[map(k)]];
    final why = createRoute(
      stops,
      name: '${r.name} · ${reverse ? 'обратно' : 'копия'}',
    );
    if (why != null) return why;
    final c = routes.values.last;
    for (final e in r.pickAt.entries) {
      c.pickAt[map(e.key)] = e.value;
    }
    c.noPick.addAll(r.noPick.map(map));
    c.noDrop.addAll(r.noDrop.map(map));
    c.ifCargo.addAll(r.ifCargo.map(map));
    c.priority.addAll(r.priority);
    c.minLoad = r.minLoad;
    _say('Маршрут скопирован: ${c.name}');
    return null;
  }

  // ---- ROUTE-09 ----

  /// Cargo the line's vehicles take first where there is any (in order).
  String? setPriority(int id, List<MagCargo> list) {
    final r = routes[id];
    if (r == null) return 'Нет такого маршрута';
    r.priority
      ..clear()
      ..addAll(list.toSet());
    return null;
  }

  /// The first priority cargo [ok] for the vehicle that has stock here.
  MagCargo? _priorityPick(
    MagRoute r,
    MagIndustry here,
    bool Function(MagCargo) ok,
  ) {
    for (final c in r.priority) {
      if (here.supplies.contains(c) && ok(c) && availableOf(here, c) > 0) {
        return c;
      }
    }
    return null;
  }

  // ---- FIN-14 ----

  /// Investments worth a look, quickest payback first: another vehicle on
  /// a line that pays, a level for an own business, a business to buy
  /// next to the roads, a jammed road to improve.
  List<MagInvestment> get investmentIdeas {
    final out = <MagInvestment>[];
    // Another vehicle on a profitable line: its vehicles' profit a day,
    // a fifth less for the newcomer.
    for (final r in routes.values) {
      final fleet = vehicles.values.where((v) => v.routeId == r.id).toList();
      final days = (tick - r.since) / MagRules.ticksPerDay;
      if (fleet.isEmpty || days < 2 || r.profit <= 0) continue;
      final per = r.profit / days / fleet.length * .8;
      final counts = <String, int>{};
      for (final v in fleet) {
        counts[v.model] = (counts[v.model] ?? 0) + 1;
      }
      final model =
          (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
      final m = MagRules.truck(model)!;
      out.add(
        MagInvestment(
          kind: MagInvestmentKind.vehicle,
          title: 'Ещё ${m.name} на «${r.name}»',
          detail:
              '${fleet.length} в работе приносят ${(per / .8 * fleet.length).round()} кр в день',
          cost: m.price + m.wagonPrice,
          daily: per,
          routeId: r.id,
          model: model,
        ),
      );
    }
    // A level for an own business: its output grows by a share.
    for (final f in industryFigures) {
      final i = f.industry, cost = upgradePrice(i);
      final since = i.since;
      if (cost == null || since == null || f.profit <= 0) continue;
      final days = (tick - since) / MagRules.ticksPerDay;
      if (days < 2) continue;
      final perDay = f.profit / days;
      final share = MagRules.levelOutput / outputFactor(i);
      out.add(
        MagInvestment(
          kind: MagInvestmentKind.upgrade,
          title: '${i.name}: уровень ${i.level + 1}',
          detail: 'Выработка +${(MagRules.levelOutput * 100).round()}%',
          cost: cost,
          daily: perDay * share,
          industryId: i.id,
        ),
      );
    }
    // A producer next to the roads, for sale: its goods' worth a day,
    // less its upkeep.
    for (final i in map.industries) {
      if (i.owned || !forSale(i) || accessCells(i).isEmpty) continue;
      var worth = 0.0;
      for (final e in i.spec.produces.entries) {
        worth += e.value * outputFactor(i) * MagRules.cargoValue[e.key]!;
      }
      if (worth <= 0) continue;
      final daily = worth - i.spec.price / MagRules.upkeepShare * i.level;
      out.add(
        MagInvestment(
          kind: MagInvestmentKind.business,
          title: 'Купить ${i.name}',
          detail: 'Своё сырьё: товар без закупки, продажа по рынку',
          cost: buyPrice(i),
          daily: daily,
          industryId: i.id,
        ),
      );
    }
    // A jammed road: improving it lifts the jam (no money estimate).
    final seen = <int>{};
    for (final e in traffic.entries) {
      if (seen.contains(e.key) || roads[e.key] == 0 || loadOf(e.key) <= 1) {
        continue;
      }
      final segment = roadSegment(e.key);
      seen.addAll(segment);
      final plan = upgradePlan(segment);
      if (plan.error != null) continue;
      out.add(
        MagInvestment(
          kind: MagInvestmentKind.road,
          title: 'Улучшить участок в пробке (${segment.length} кл.)',
          detail:
              '${trafficOf(e.key)} машин в день при ёмкости ${MagRules.roads[MagRoad.values[roads[e.key]]]!.capacity}',
          cost: plan.cost,
          cell: e.key,
        ),
      );
    }
    out.sort((a, b) {
      final pa = a.paybackDays, pb = b.paybackDays;
      if (pa == null || pb == null) return pa == null ? 1 : -1;
      return pa.compareTo(pb);
    });
    return out.take(12).toList();
  }

  /// Buys one more vehicle of [model] and puts it on route [routeId].
  String? buyForRoute(String model, int routeId) {
    final why = buyTruck(model);
    if (why != null) return why;
    return assign(vehicles.values.last.id, routeId);
  }
}
