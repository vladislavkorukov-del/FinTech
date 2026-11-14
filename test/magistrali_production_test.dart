import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Master plan stage 3: first production chains and the journal. Recipes
/// with ratios, levels, buying, building, modernising and selling a
/// business; own goods sold, raw goods bought, own goods moved (never a
/// sale); no money from moving cargo round; one journal of every credit;
/// saves old and new.
void main() {
  void expectBalanced(MagWorld w) {
    final total = w.totalCargo();
    for (final c in MagCargo.values) {
      expect(
        total[c] ?? 0,
        (w.created[c] ?? 0) - (w.destroyed[c] ?? 0),
        reason: '$c at tick ${w.tick}',
      );
    }
  }

  /// Money from outside customers so far: freight and goods sold (task
  /// rewards are left out — they are not trade).
  int trade(MagWorld w) => w.months.fold(
    0,
    (n, m) => n + (m.income['delivery'] ?? 0) + (m.income['goods_sale'] ?? 0),
  );

  MagIndustry first(MagWorld w, MagIndustryKind k) =>
      w.map.industries.firstWhere((i) => i.kind == k);

  /// Free road cells next to a place.
  List<(int, int)> sides(MagWorld w, MagIndustry i) => [
    for (var y = i.top - 1; y <= i.bottom + 1; y++)
      for (var x = i.left - 1; x <= i.right + 1; x++)
        if (w.map.roadable(x, y) &&
            List.generate(
              4,
              (d) => i.covers(x + MagDir.dx[d], y + MagDir.dy[d]),
            ).any((e) => e))
          (x, y),
  ];

  /// Joins two places by road (the first plan that works).
  void connect(MagWorld w, MagIndustry a, MagIndustry b) {
    for (final (ax, ay) in sides(w, a)) {
      for (final (bx, by) in sides(w, b)) {
        final plan = w.planRoad(ax, ay, bx, by, MagRoad.dirt);
        if (plan.error == null && w.buildRoad(plan) == null) {
          if (w.connected(a, b)) return;
        }
      }
    }
    fail('cannot join ${a.name} and ${b.name}');
  }

  /// A rich company on a new map with a pickup per route.
  MagWorld rich() => MagWorld.start()
    ..money = 1000000
    ..xp = MagWorldProgress.xpFor(10)
    ..techs.add('combustion');

  void carry(MagWorld w, MagIndustry a, MagIndustry b) {
    connect(w, a, b);
    w.createRoute([a.id, b.id]);
    w.buyTruck('pickup');
    w.assign(w.vehicles.values.last.id, w.routes.keys.last);
  }

  /// Puts [n] of [c] into a place's stock (recorded as made).
  void give(
    MagWorld w,
    MagIndustry i,
    MagCargo c,
    int n, {
    bool input = false,
  }) {
    final m = input ? i.input : i.stock;
    m[c] = (m[c] ?? 0) + n;
    w.created[c] = (w.created[c] ?? 0) + n;
  }

  test('new maps have the first chains; recipes keep their ratios', () {
    final w = MagWorld.start();
    expect(w.map.version, 3);
    for (final k in [
      MagIndustryKind.quarry,
      MagIndustryKind.mill,
      MagIndustryKind.bakery,
      MagIndustryKind.lumbermill,
    ]) {
      expect(
        w.map.industries.where((i) => i.kind == k),
        isNotEmpty,
        reason: '$k',
      );
    }
    final mill = first(w, MagIndustryKind.mill);
    give(w, mill, MagCargo.grain, 9, input: true);
    w.step(MagRules.ticksPerDay);
    expect(mill.stock[MagCargo.flour], 4); // 2 grain per flour
    expect(mill.input[MagCargo.grain], 1);
    final bakery = first(w, MagIndustryKind.bakery);
    give(w, bakery, MagCargo.flour, 5, input: true);
    w.step(MagRules.ticksPerDay);
    expect(bakery.stock[MagCargo.bread], 5);
    // Never beyond the store.
    give(w, mill, MagCargo.grain, 400, input: true);
    for (var d = 0; d < 40; d++) {
      w.step(MagRules.ticksPerDay);
      expect(
        mill.stock[MagCargo.flour]!,
        lessThanOrEqualTo(w.outputCapOf(mill)),
      );
    }
    final quarry = first(w, MagIndustryKind.quarry);
    expect(quarry.stock[MagCargo.stone], greaterThan(0));
    // Settlements buy bread and planks in their market.
    final village = w.settlements.first;
    expect(village.accepts, containsAll([MagCargo.bread, MagCargo.planks]));
    expectBalanced(w);
  });

  test('buy, upkeep, modernise and sell a business', () {
    final w = rich();
    final farm = w.map.startFarm;
    expect(w.forSale(farm), isTrue);
    expect(w.forSale(w.settlements.first), isFalse);
    final price = w.buyPrice(farm);
    final money = w.money;
    expect(w.buyIndustry(farm.id), isNull);
    expect(w.money, money - price);
    expect(farm.owned, isTrue);
    expect(w.journal.entries.last.kind, MagEntryKind.capex);
    expect(w.buyIndustry(farm.id), contains('Уже'));
    // A day: upkeep is an operating cost; production is counted.
    w.step(MagRules.ticksPerDay);
    expect(farm.costs, w.upkeepOfIndustry(farm));
    expect(farm.produced, greaterThan(0));
    final day1 = farm.produced;
    // Modernising raises output.
    expect(w.upgradeIndustry(farm.id), isNull);
    expect(farm.level, 2);
    farm.stock.clear(); // room to make the full day
    w.created[MagCargo.grain] = 0;
    w.destroyed[MagCargo.grain] = 0;
    w.step(MagRules.ticksPerDay);
    expect(farm.produced - day1, greaterThan(9));
    for (var l = 3; l <= MagRules.maxIndustryLevel; l++) {
      expect(w.upgradeIndustry(farm.id), isNull);
    }
    expect(w.upgradeIndustry(farm.id), contains('Максимальный'));
    // Selling: half the outlay back, as an asset sale; it works on alone.
    final back = w.sellPrice(farm);
    final before = w.money;
    expect(w.sellIndustry(farm.id), isNull);
    expect(w.money, before + back);
    expect(farm.owned, isFalse);
    expect(farm.level, MagRules.maxIndustryLevel);
    expect(w.journal.entries.last.kind, MagEntryKind.assetSale);
  });

  test('own goods sold outside pay freight and their price', () {
    final w = rich();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    w.buyIndustry(farm.id);
    carry(w, farm, plant);
    for (var t = 0; t < 4000 && w.month.income['goods_sale'] == null; t++) {
      w.step();
    }
    final sale = w.month.income['goods_sale']!;
    expect(sale, (farm.sold * MagRules.cargoValue[MagCargo.grain]!).round());
    expect(w.month.income['delivery'], greaterThan(0));
    expect(farm.revenue, sale);
    expect(
      w.journal.entries
          .where((e) => e.category == 'goods_sale')
          .every(
            (e) => e.kind == MagEntryKind.revenue && e.sourceId == farm.id,
          ),
      isTrue,
    );
    expectBalanced(w);
  });

  test('raw goods bought for an own plant; own goods only moved', () {
    final w = rich();
    final farm = w.map.startFarm;
    final mill = first(w, MagIndustryKind.mill);
    w.buyIndustry(mill.id);
    carry(w, farm, mill);
    for (var t = 0; t < 5000 && w.month.expense['purchase'] == null; t++) {
      w.step();
    }
    // Bought at market price, no freight paid to anyone.
    final bought = w.journal.entries.where((e) => e.category == 'purchase');
    expect(bought, isNotEmpty);
    expect(
      bought.first.amount,
      -(bought.first.units * MagRules.cargoValue[MagCargo.grain]!).round(),
    );
    expect(w.month.income['delivery'], isNull);
    expect(mill.costs, greaterThan(0));
    // Owning the farm too: the grain is only moved.
    w.buyIndustry(farm.id);
    final revenue = trade(w);
    for (var t = 0; t < 4000; t++) {
      w.step();
    }
    expect(
      w.journal.entries.where((e) => e.kind == MagEntryKind.transfer),
      isNotEmpty,
    );
    expect(trade(w), revenue); // no new income from own goods
    expect(
      w.journal.entries
          .where((e) => e.kind == MagEntryKind.transfer)
          .every((e) => e.amount == 0),
      isTrue,
    );
    expectBalanced(w);
  });

  test('moving cargo round own warehouses never makes money', () {
    final w = rich()..techs.addAll(['storage', 'network', 'racks']);
    final plant = w.map.startPlant;
    // Two warehouses joined by road, a truck going back and forth.
    late MagIndustry a, b;
    var built = 0;
    for (var r = 3; r < 14 && built < 2; r++) {
      for (final (dx, dy) in [(0, r), (r, 0), (0, -r), (-r, 0)]) {
        if (built == 2) break;
        if (w.buildWarehouse(plant.x + dx, plant.y + dy) == null) built++;
      }
    }
    expect(built, 2);
    a = w.warehouses.first;
    b = w.warehouses.last;
    give(w, a, MagCargo.grain, 60);
    connect(w, a, b);
    w.createRoute([a.id, b.id]);
    w.buyTruck('pickup');
    w.assign(w.vehicles.values.last.id, w.routes.keys.last);
    final revenue = trade(w);
    int bonus() => w.months.fold(0, (n, m) => n + (m.income['bonus'] ?? 0));
    final money = w.money, rewards = bonus();
    for (var t = 0; t < 3000; t++) {
      w.step();
    }
    expect(trade(w), revenue);
    // Apart from task rewards, money only went out.
    expect(w.money - (bonus() - rewards), lessThan(money));
    expect(
      w.journal.entries.where((e) => e.kind == MagEntryKind.transfer),
      isNotEmpty,
    );
    expectBalanced(w);
  });

  test('building: level, free land, terrain, price; saved and reloaded', () {
    final w = MagWorld.start()..money = 1000000;
    final plant = w.map.startPlant;
    expect(
      w.buildBlocker(MagIndustryKind.mill, plant.x, plant.y + 4),
      contains('2 уровня'),
    );
    w.xp = MagWorldProgress.xpFor(3);
    expect(w.buildBlocker(MagIndustryKind.mill, plant.x, plant.y), isNotNull);
    expect(w.buildBlocker(MagIndustryKind.warehouse, 5, 5), isNotNull);
    // A quarry far from hills is refused.
    (int, int)? flat, hilly;
    for (var y = 3; y < 58 && (flat == null || hilly == null); y++) {
      for (var x = 3; x < 58; x++) {
        final why = w.buildBlocker(MagIndustryKind.quarry, x, y);
        if (why == null) hilly ??= (x, y);
        if (why != null && why.contains('холмы')) flat ??= (x, y);
      }
    }
    expect(flat, isNotNull);
    expect(hilly, isNotNull);
    final money = w.money;
    expect(
      w.buildIndustry(MagIndustryKind.quarry, hilly!.$1, hilly.$2),
      isNull,
    );
    final q = w.map.industries.last;
    expect(q.built && q.owned, isTrue);
    expect(w.money, money - w.buildPrice(MagIndustryKind.quarry));
    expect(
      w.buildPrice(MagIndustryKind.quarry),
      greaterThan(MagRules.industries[MagIndustryKind.quarry]!.price),
    );
    w.step(MagRules.ticksPerDay * 2 + 5);
    expect(q.stock[MagCargo.stone], greaterThan(0));
    final saved = jsonEncode(w.toJson());
    final b = magWorldFromJson(jsonDecode(saved) as Map<String, dynamic>);
    expect(jsonEncode(b.toJson()), saved);
    expect(b.map.industry(q.id)!.built, isTrue);
    w.step(1000);
    b.step(1000);
    expect(jsonEncode(b.toJson()), jsonEncode(w.toJson()));
    // A road under a building is refused.
    final bad = jsonDecode(saved) as Map<String, dynamic>;
    final roads = base64Decode(bad['roads'] as String);
    roads[q.y * 64 + q.x] = 1;
    bad['roads'] = base64Encode(roads);
    expect(() => magWorldFromJson(bad), throwsFormatException);
  });

  test('the journal: unique ids, kinds kept apart, totals agree', () {
    final w = rich();
    final farm = w.map.startFarm, plant = w.map.startPlant;
    w.buyIndustry(farm.id);
    carry(w, farm, plant);
    w.step(3000);
    final ids = w.journal.entries.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
    for (var k = 1; k < ids.length; k++) {
      expect(ids[k], greaterThan(ids[k - 1]));
    }
    // Revenue in the journal equals the months' income from real deals.
    var revenue = 0, sales = 0;
    for (final m in w.months) {
      for (final e in m.income.entries) {
        if (const {
          'sales',
          'industry_sale',
          'warehouse_sale',
        }.contains(e.key)) {
          sales += e.value;
        } else {
          revenue += e.value;
        }
      }
    }
    expect(w.journal.total(MagEntryKind.revenue), revenue);
    expect(w.journal.total(MagEntryKind.assetSale), sales);
    // Buying the farm and a truck were investments, not running costs.
    final capex = w.journal.entries.where((e) => e.kind == MagEntryKind.capex);
    expect(
      capex.map((e) => e.category),
      containsAll(['industry_buy', 'vehicles', 'roads']),
    );
    expect(
      w.journal.entries
          .where((e) => e.kind == MagEntryKind.opex)
          .map((e) => e.category)
          .toSet()
          .intersection({'industry_buy', 'vehicles', 'roads'}),
      isEmpty,
    );
    final b = magWorldFromJson(
      jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
    );
    expect(b.journal.entries.length, w.journal.entries.length);
    expect(b.journal.seq, w.journal.seq);
  });

  test('old saves load: nothing owned, empty journal, their own map', () {
    for (final f in ['v1', 'v2', 'v3', 'v5_map2']) {
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/magistrali_save_$f.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final w = magWorldFromJson(raw);
      expect(w.map.version, f == 'v5_map2' ? 2 : 1, reason: f);
      expect(w.map.industries.any((i) => i.owned), isFalse);
      expect(w.journal.entries, isEmpty);
      expect(w.money, raw['money']);
      if (f == 'v5_map2') {
        // Generator 2 is unchanged: the same places in the same spots.
        expect(
          w.map.industries.where((i) => i.kind == MagIndustryKind.mill),
          isEmpty,
        );
        expect(w.vehicles.values.first.model, 'cart');
      }
      w.step(1500);
      expect(w.toJson()['version'], MagWorldSave.version);
      final again = magWorldFromJson(
        jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
      );
      expect(jsonEncode(again.toJson()), jsonEncode(w.toJson()));
      expectBalanced(w);
    }
  });
}
