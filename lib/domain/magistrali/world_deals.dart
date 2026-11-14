part of 'world.dart';

/// Special contracts (S16): production orders (CONT-04), regular supply
/// of a settlement (CONT-05), contracts in stages (CONT-06) and regional
/// contracts (CONT-07). They live apart from the regular contracts and
/// city orders; each pays when done (supply — every period).
enum MagDealKind { production, supply, stages, region }

class MagDeal {
  MagDeal({
    required this.id,
    required this.kind,
    required this.cargo,
    required this.to,
    required this.amount,
    required this.reward,
    this.deadline,
  });
  final int id;
  final MagDealKind kind;

  /// Production: what an own plant must make, and the plant. Supply: what
  /// the settlement needs each period. Region: what any settlement within
  /// [radius] of [to] takes. Stages: the current stage (see [stages]).
  MagCargo cargo;
  int to, amount;
  final int reward;
  int delivered = 0;
  final int? deadline;

  /// Supply: days of a period, periods left, the tick the period ends.
  int period = 0, periodsLeft = 0, periodEnd = 0;

  /// Stages: (cargo, place, amount) in order, and the current one.
  final List<(MagCargo, int, int)> stages = [];
  int stage = 0;

  /// Region: how far from [to] a settlement still counts (cells).
  int radius = 0;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'cargo': cargo.name,
    'to': to,
    'amount': amount,
    'reward': reward,
    'delivered': delivered,
    'deadline': deadline,
    if (period != 0) 'period': [period, periodsLeft, periodEnd],
    if (stages.isNotEmpty)
      'stages': [
        for (final (c, p, n) in stages) [c.name, p, n],
      ],
    if (stage != 0) 'stage': stage,
    if (radius != 0) 'radius': radius,
  };

  static MagDeal fromJson(Map m) {
    final d =
        MagDeal(
            id: m['id'] as int,
            kind: MagDealKind.values.byName(m['kind'] as String),
            cargo: MagCargo.values.byName(m['cargo'] as String),
            to: m['to'] as int,
            amount: m['amount'] as int,
            reward: m['reward'] as int,
            deadline: m['deadline'] as int?,
          )
          ..delivered = m['delivered'] as int? ?? 0
          ..stage = m['stage'] as int? ?? 0
          ..radius = m['radius'] as int? ?? 0;
    final p = m['period'] as List?;
    if (p != null) {
      d
        ..period = p[0] as int
        ..periodsLeft = p[1] as int
        ..periodEnd = p[2] as int;
    }
    for (final s in m['stages'] as List? ?? const []) {
      final l = s as List;
      d.stages.add((
        MagCargo.values.byName(l[0] as String),
        l[1] as int,
        l[2] as int,
      ));
    }
    return d;
  }
}

extension MagWorldDeals on MagWorld {
  /// How many special contracts may be open (grows with the level).
  int get dealSlots => level < 3
      ? 0
      : level < 8
      ? 2
      : level < 15
      ? 3
      : 4;

  /// Does a delivery of [c] to [here] count for [d]?
  bool _dealTakes(MagDeal d, MagCargo c, MagIndustry here) => switch (d.kind) {
    MagDealKind.production => false,
    MagDealKind.supply || MagDealKind.stages => d.cargo == c && d.to == here.id,
    MagDealKind.region =>
      d.cargo == c &&
          here.town != null &&
          here.distanceTo(map.industry(d.to)!) <= d.radius,
  };

  /// Real deliveries count for the special contracts.
  void _countDeals(MagCargo c, MagIndustry here, int n) {
    for (final d in deals.toList()) {
      if (!_dealTakes(d, c, here)) continue;
      d.delivered = math.min(d.amount, d.delivered + n);
      _advanceDeal(d);
    }
  }

  /// Output made at an own plant counts for production orders (CONT-04).
  void _countProduction(MagIndustry plant, MagCargo c, int n) {
    for (final d in deals.toList()) {
      if (d.kind != MagDealKind.production) continue;
      if (d.to != plant.id || d.cargo != c) continue;
      d.delivered = math.min(d.amount, d.delivered + n);
      _advanceDeal(d);
    }
  }

  void _advanceDeal(MagDeal d) {
    if (d.delivered < d.amount) return;
    switch (d.kind) {
      case MagDealKind.supply:
        return; // paid at the end of the period
      case MagDealKind.stages:
        if (d.stage + 1 < d.stages.length) {
          d.stage++;
          final (c, p, n) = d.stages[d.stage];
          d
            ..cargo = c
            ..to = p
            ..amount = n
            ..delivered = 0;
          _say('Этап ${d.stage} из ${d.stages.length} выполнен');
          return;
        }
      case MagDealKind.production:
      case MagDealKind.region:
        break;
    }
    _payDeal(d, d.reward);
    deals.remove(d);
  }

  void _payDeal(MagDeal d, int amount) {
    final paid = (amount * factor(MagBonus.contract)).round();
    _earn(paid, 'deals');
    _gainXp(math.max(1, paid ~/ 12));
    _say('${dealTitle(d)}: +$paid кр');
    _remember('Выполнено: ${dealTitle(d)}');
  }

  String dealTitle(MagDeal d) {
    final place = map.industry(d.to)?.name ?? '';
    return switch (d.kind) {
      MagDealKind.production => 'Производственный заказ «$place»',
      MagDealKind.supply => 'Снабжение «$place»',
      MagDealKind.stages => 'Многоэтапный контракт',
      MagDealKind.region => 'Региональный контракт: окрестности «$place»',
    };
  }

  /// Gives up a special contract (no fine).
  String? dropDeal(int id) {
    final d = deals.where((e) => e.id == id).firstOrNull;
    if (d == null) return 'Нет такого контракта';
    deals.remove(d);
    return null;
  }

  /// The day: supply periods close, deadlines pass, new ones come.
  void _dayDeals() {
    for (final d in deals.toList()) {
      if (d.kind == MagDealKind.supply && tick >= d.periodEnd) {
        if (d.delivered >= d.amount) {
          _payDeal(d, d.reward ~/ 4); // four periods, paid one by one
          d
            ..periodsLeft -= 1
            ..delivered = 0
            ..periodEnd = tick + d.period * MagRules.ticksPerDay;
          if (d.periodsLeft <= 0) deals.remove(d);
        } else {
          deals.remove(d);
          _say('${dealTitle(d)}: период сорван');
          _remember('Сорвано: ${dealTitle(d)}');
        }
        continue;
      }
      final dl = d.deadline;
      if (dl != null && tick > dl) {
        deals.remove(d);
        _remember('Не выполнено в срок: ${dealTitle(d)}');
      }
    }
    for (var tries = 0; deals.length < dealSlots && tries < 8; tries++) {
      // Kinds in turn, starting from a different one each day.
      final d = _newDeal(MagDealKind.values[(day + tries) % 4]);
      if (d != null) deals.add(d);
    }
  }

  MagDeal? _newDeal(MagDealKind kind) {
    final days = MagRules.ticksPerDay;
    switch (kind) {
      case MagDealKind.production:
        final plants = map.industries
            .where((i) => i.owned && i.spec.converts.isNotEmpty)
            .toList();
        if (plants.isEmpty) return null;
        final p = plants[_roll(plants.length)];
        final out = p.spec.converts.values.first;
        final n = math.min(120, 20 + level * 2);
        return MagDeal(
          id: nextId++,
          kind: kind,
          cargo: out,
          to: p.id,
          amount: n,
          reward: (n * MagRules.cargoRate[out]! * 25 + 500).round(),
          deadline: tick + 25 * days,
        );
      case MagDealKind.supply:
        final towns = settlements
            .where((i) => accessCells(i).isNotEmpty && needsOf(i).isNotEmpty)
            .toList();
        if (towns.isEmpty) return null;
        final t = towns[_roll(towns.length)];
        final need = needsOf(t).keys.where(cargoAvailable).toList()
          ..sort((a, b) => a.index - b.index);
        if (need.isEmpty) return null;
        final c = need[_roll(need.length)];
        final n = 15 + level;
        return MagDeal(
            id: nextId++,
            kind: kind,
            cargo: c,
            to: t.id,
            amount: n,
            reward: (n * MagRules.cargoRate[c]! * 30 * 4).round(),
          )
          ..period = 7
          ..periodsLeft = 4
          ..periodEnd = tick + 7 * days;
      case MagDealKind.stages:
        final plants = map.industries
            .where((i) => i.town == null && i.spec.converts.isNotEmpty)
            .toList();
        if (plants.isEmpty) return null;
        final p = plants[_roll(plants.length)];
        final input = p.spec.converts.keys.first, out = p.spec.converts[input]!;
        final buyers =
            map.industries
                .where((i) => i != p && i.accepts.contains(out))
                .toList()
              ..sort((a, b) => a.distanceTo(p).compareTo(b.distanceTo(p)));
        if (buyers.isEmpty || !cargoAvailable(input)) return null;
        final t = buyers.first;
        final d = MagDeal(
          id: nextId++,
          kind: kind,
          cargo: input,
          to: p.id,
          amount: 25,
          reward:
              (25 * MagRules.cargoRate[input]! * 30 +
                      20 * MagRules.cargoRate[out]! * 40 +
                      1000)
                  .round(),
          deadline: tick + 40 * days,
        );
        d.stages
          ..add((input, p.id, 25))
          ..add((out, t.id, 20));
        return d;
      case MagDealKind.region:
        final centres = [
          for (final t in settlements)
            if (settlements.where((o) => o.distanceTo(t) <= 16).length >= 3) t,
        ];
        if (centres.isEmpty) return null;
        final t = centres[_roll(centres.length)];
        final goods =
            t.accepts.where((c) => !c.people && cargoAvailable(c)).toList()
              ..sort((a, b) => a.index - b.index);
        if (goods.isEmpty) return null;
        final c = goods[_roll(goods.length)];
        final n = 40 + level * 2;
        return MagDeal(
          id: nextId++,
          kind: kind,
          cargo: c,
          to: t.id,
          amount: n,
          reward: (n * MagRules.cargoRate[c]! * 28).round(),
          deadline: tick + 30 * days,
        )..radius = 16;
    }
  }

  /// A fair pick among [n] (the high bits of the game's random numbers).
  int _roll(int n) => (_random(0x7fffffff) >> 11) % n;
}
