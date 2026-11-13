import 'dart:convert';

import 'package:finora/domain/finorio/finorio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finorio's simulation: mining, recipes, power, belts, blocking, balance,
/// saving and determinism, and the whole tutorial on the starter kit.
FinWorld flat(Map<(int, int), FinTerrain> marks) {
  final w = FinWorld(seed: 7, terrain: FinTerrainMap.custom(7, 32, marks));
  w.kits.addAll(FinConfig.starterBuildings);
  w.inventory.addAll(FinConfig.starterItems);
  FinConfig.starterItems.forEach((i, n) => w.started[i] = n);
  return w;
}

/// A test bench with more kits than the starter set.
FinWorld bench(Map<(int, int), FinTerrain> marks) {
  final w = flat(marks);
  for (final k in FinBuilding.values) {
    w.kits[k] = 20;
  }
  return w;
}

void run(FinWorld w, int ticks, {bool balance = true}) {
  for (var i = 0; i < ticks; i++) {
    w.step();
    if (balance && i % 50 == 0) expectBalanced(w);
  }
}

/// Items never appear or vanish except by mining, recipes, fuel, research
/// and construction.
void expectBalanced(FinWorld w) {
  final total = w.totalItems();
  for (final i in FinItem.values) {
    expect(
      total[i] ?? 0,
      (w.started[i] ?? 0) + (w.created[i] ?? 0) - (w.destroyed[i] ?? 0),
      reason: '$i at tick ${w.tick}',
    );
  }
}

FinMachine powered(FinWorld w, int x, int y, {int fuel = 10}) {
  final g = w.place(FinBuilding.generator, x, y)!;
  expect(w.insert(g.id, FinItem.biomass, fuel), fuel);
  return g;
}

void main() {
  test('a powered drill mines one ore every 2 s and stops when full', () {
    final w = flat({(3, 3): FinTerrain.iron});
    final d = w.place(FinBuilding.drill, 3, 3)!;
    powered(w, 6, 3);
    run(w, 20);
    expect(d.output[FinItem.ironOre], 1);
    run(w, 60);
    expect(
      d.output[FinItem.ironOre],
      FinConfig.specs[FinBuilding.drill]!.outputCap,
    );
    expect(d.status, FinStatus.outputBlocked);
    expect(w.created[FinItem.ironOre], 2);
  });

  test('a drill can only stand on a deposit', () {
    final w = flat({(3, 3): FinTerrain.copper, (4, 4): FinTerrain.rock});
    expect(w.whyNot(FinBuilding.drill, 1, 1), isNotNull);
    expect(w.whyNot(FinBuilding.furnace, 4, 4), 'Здесь скалы');
    expect(w.place(FinBuilding.drill, 3, 3), isNotNull);
    expect(w.whyNot(FinBuilding.belt, 3, 3), 'Клетка занята');
  });

  test('recipes take their inputs and take their time', () {
    final w = flat({});
    w.inventory[FinItem.ironOre] = 4;
    w.started[FinItem.ironOre] = 4;
    final f = w.place(FinBuilding.furnace, 3, 3)!;
    powered(w, 6, 3);
    expect(w.insert(f.id, FinItem.ironOre, 4), 4);
    expect(f.recipe, 'iron_plate'); // chosen by the ore
    run(w, 39);
    expect(f.output[FinItem.ironPlate], isNull);
    expect(f.status, FinStatus.working);
    run(w, 1);
    expect(f.output[FinItem.ironPlate], 1);
    run(w, 40);
    expect(f.output[FinItem.ironPlate], 2);
    expect(f.input, isEmpty);
    expect(w.destroyed[FinItem.ironOre], 4);
    run(w, 5);
    expect(f.status, FinStatus.noInput);
    expectBalanced(w);
  });

  test('an assembler waits for a recipe, then for every ingredient', () {
    final w = flat({});
    final a = w.place(FinBuilding.assembler, 3, 3)!;
    powered(w, 6, 3);
    run(w, 1);
    expect(a.status, FinStatus.needsSetup);
    expect(w.setRecipe(a.id, 'circuit'), isTrue);
    w.inventory[FinItem.copperPlate] = 1;
    w.started[FinItem.copperPlate] = 1;
    w.insert(a.id, FinItem.copperPlate, 1);
    run(w, 70);
    expect(a.status, FinStatus.noInput); // no crystal
    expect(a.output, isEmpty);
    w.inventory[FinItem.crystal] = 1;
    w.started[FinItem.crystal] = 1;
    w.insert(a.id, FinItem.crystal, 1);
    run(w, 60);
    expect(a.output[FinItem.circuit], 1);
    expectBalanced(w);
  });

  test('no power: nothing works; partial power slows everyone evenly', () {
    final w = bench({for (var x = 1; x <= 7; x++) (x, 1): FinTerrain.iron});
    final drills = [
      for (var x = 1; x <= 7; x++) w.place(FinBuilding.drill, x, 1, dir: 2)!,
    ];
    run(w, 40);
    expect(drills.every((d) => d.status == FinStatus.noPower), isTrue);
    expect(w.created[FinItem.ironOre], isNull);
    // 7 drills ask for 14, the generator gives 12: each runs at 12/14.
    powered(w, 4, 4);
    run(w, 1);
    expect(drills.first.powered, 12 * 1000 ~/ 14);
    expect(w.demand, 14);
    run(w, 22);
    expect(drills.where((d) => d.output.isNotEmpty), isEmpty);
    run(w, 1);
    expect(drills.every((d) => d.output[FinItem.ironOre] == 1), isTrue);
  });

  test('a generator burns 1 biomass per 20 s at full power, then stops', () {
    final w = bench({for (var x = 1; x <= 6; x++) (x, 1): FinTerrain.iron});
    for (var x = 1; x <= 6; x++) {
      w.place(FinBuilding.drill, x, 1, dir: 2);
      w.place(FinBuilding.storage, x, 2);
    }
    final g = powered(w, 4, 5, fuel: 1);
    run(w, 199);
    expect(w.machines.values.first.powered, 1000);
    run(w, 1);
    expect(g.energy, 0);
    run(w, 1);
    expect(w.machines.values.first.status, FinStatus.noPower);
    // Fuel again: work resumes.
    w.insert(g.id, FinItem.biomass, 1);
    run(w, 1);
    expect(w.machines.values.first.status, FinStatus.working);
  });

  test('belts carry items 1 cell/s, around corners, into a store', () {
    final w = flat({(1, 1): FinTerrain.iron});
    w.place(FinBuilding.drill, 1, 1, dir: 1);
    powered(w, 1, 4);
    // East along row 1, then south down column 6: an L with a corner.
    expect(w.placeBeltLine(2, 1, 6, 3), 7);
    expect(w.machineAt(6, 1)!.dir, 2);
    final store = w.place(FinBuilding.storage, 6, 4)!;
    run(w, 20 + 2); // the first ore is mined and enters the belt
    expect(w.machineAt(2, 1)!.items, hasLength(1));
    run(w, 70);
    expect(store.input[FinItem.ironOre], 1);
    run(w, 400);
    expect(
      store.input[FinItem.ironOre],
      w.created[FinItem.ironOre]! - _onBelts(w) - _inDrills(w),
    );
    expectBalanced(w);
  });

  test('a blocked line stops, keeps half a cell between items, resumes', () {
    final w = flat({(1, 1): FinTerrain.iron, (1, 2): FinTerrain.iron});
    w.place(FinBuilding.drill, 1, 1, dir: 1);
    w.place(FinBuilding.drill, 1, 2, dir: 1);
    powered(w, 1, 5, fuel: 20);
    w.placeBeltLine(2, 2, 2, 2); // a side-loader into the main line
    w.machineAt(2, 2)!.dir = 0;
    w.placeBeltLine(2, 1, 4, 1); // ends in the open: blocked
    run(w, 900);
    for (final b in w.machines.values.where((m) => m.isBelt)) {
      expect(b.items.length, lessThanOrEqualTo(2));
      for (var i = 1; i < b.items.length; i++) {
        expect(
          b.items[i - 1].pos - b.items[i].pos,
          greaterThanOrEqualTo(FinRules.beltSpacing),
        );
      }
    }
    expect(w.machineAt(4, 1)!.status, FinStatus.outputBlocked);
    final drills = w.machines.values.where((m) => m.kind == FinBuilding.drill);
    expect(drills.every((d) => d.status == FinStatus.outputBlocked), isTrue);
    final before = w.created[FinItem.ironOre]!;
    run(w, 100);
    expect(w.created[FinItem.ironOre], before); // stopped
    final store = w.place(FinBuilding.storage, 5, 1)!;
    run(w, 200);
    expect(store.input[FinItem.ironOre], greaterThan(10));
    expect(w.created[FinItem.ironOre], greaterThan(before));
    expectBalanced(w);
  });

  test('taking a machine down returns its kit and everything it held', () {
    final w = flat({});
    w.inventory[FinItem.ironOre] = 6;
    w.started[FinItem.ironOre] = 6;
    final f = w.place(FinBuilding.furnace, 3, 3)!;
    powered(w, 6, 3);
    w.insert(f.id, FinItem.ironOre, 6);
    run(w, 60); // one plate done, one in progress
    expect(f.output[FinItem.ironPlate], 1);
    expect(f.crafting, 'iron_plate');
    final kits = w.kits[FinBuilding.furnace]!;
    expect(w.remove(f.id), isTrue);
    expect(w.kits[FinBuilding.furnace], kits + 1);
    expect(w.inventory[FinItem.ironPlate], 1);
    expect(w.inventory[FinItem.ironOre], 4); // 2 in progress + 2 waiting
    expect(w.machineAt(3, 3), isNull);
    expectBalanced(w);
  });

  test('building without a kit spends its materials', () {
    final w = flat({});
    w.kits.clear();
    expect(w.whyNot(FinBuilding.storage, 2, 2), 'Не хватает материалов');
    w.inventory[FinItem.ironPlate] = 6;
    w.started[FinItem.ironPlate] = 6;
    expect(w.place(FinBuilding.storage, 2, 2), isNotNull);
    expect(w.inventory[FinItem.ironPlate], isNull);
    expectBalanced(w);
    expect(w.whyNot(FinBuilding.fastBelt, 3, 3), 'Нужно исследование');
  });

  test('the whole tutorial runs on the starter kit, automatically', () {
    final w = tutorialFactory();
    var ticks = 0;
    while (w.tasksDone.length < FinTasks.all.length && ticks < 12000) {
      w.step();
      ticks++;
      if (ticks % 200 == 0) expectBalanced(w);
    }
    expect(w.tasksDone, {for (var i = 1; i <= 10; i++) i});
    expect(w.researched, contains('logistics'));
    expect(w.unlocked(FinBuilding.fastBelt), isTrue);
    expect(w.earnedRewards, contains(FinTasks.researchRewardId));
    // Under 10 simulated minutes, and the factory keeps going after.
    expect(ticks, lessThan(6000));
    final gears = w.made(FinItem.gear);
    run(w, 1200);
    expect(w.made(FinItem.gear), greaterThan(gears));
    expectBalanced(w);
  });

  test('a long run keeps the balance, and saving changes nothing', () {
    final a = tutorialFactory();
    run(a, 3000);
    final json = jsonEncode(a.toJson());
    final b = finWorldFromJson(jsonDecode(json) as Map<String, dynamic>);
    expect(jsonEncode(b.toJson()), json);
    run(a, 1500, balance: false);
    run(b, 1500, balance: false);
    expect(jsonEncode(b.toJson()), jsonEncode(a.toJson()));
    expectBalanced(b);
  });

  test('the same start and actions give the same factory', () {
    final a = tutorialFactory(), b = tutorialFactory();
    run(a, 2500, balance: false);
    run(b, 2500, balance: false);
    expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
  });

  test('a save that does not add up, or from the future, is refused', () {
    final w = FinWorld.start(42);
    final j = w.toJson();
    expect(
      () => finWorldFromJson({...j, 'version': 99}),
      throwsFormatException,
    );
    expect(
      () => finWorldFromJson({
        ...j,
        'inventory': {'biomass': 999},
      }),
      throwsFormatException,
    );
    final ok = finWorldFromJson(
      jsonDecode(jsonEncode(j)) as Map<String, dynamic>,
    );
    expect(ok.kits, w.kits);
  });

  test('maps come from their seed; the start always has every deposit', () {
    for (final seed in [1, 42, 2024, 99991, 123456789]) {
      final a = FinTerrainMap.generate(seed), b = FinTerrainMap.generate(seed);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          expect(a.at(x, y), b.at(x, y));
        }
      }
      final near = a.depositsNearStart();
      for (final t in FinConfig.deposits.keys) {
        expect(near[t] ?? 0, greaterThanOrEqualTo(4), reason: '$t seed $seed');
      }
      // Room to build around the start.
      for (var y = 29; y <= 35; y++) {
        for (var x = 29; x <= 35; x++) {
          if ((x - 32) * (x - 32) + (y - 32) * (y - 32) <= 9) {
            expect(a.at(x, y), FinTerrain.ground);
          }
        }
      }
    }
    expect(
      FinTerrainMap.generate(1).at(10, 10) ==
              FinTerrainMap.generate(2).at(10, 10) &&
          FinTerrainMap.generate(1).at(50, 20) ==
              FinTerrainMap.generate(2).at(50, 20) &&
          FinTerrainMap.generate(1).at(5, 55) ==
              FinTerrainMap.generate(2).at(5, 55) &&
          FinTerrainMap.generate(1).at(60, 3) ==
              FinTerrainMap.generate(2).at(60, 3),
      isFalse,
    );
  });
}

int _onBelts(FinWorld w) => w.machines.values
    .where((m) => m.isBelt)
    .fold(0, (n, m) => n + m.items.length);
int _inDrills(FinWorld w) => w.machines.values
    .where((m) => m.kind == FinBuilding.drill)
    .fold(0, (n, m) => n + m.count(m.output));

/// The tutorial's chain on a small map, built only from the starter kit:
/// iron → furnace → gears → store; copper + crystal → circuits → lab;
/// biomass → generator.
FinWorld tutorialFactory() {
  final w = flat({
    (5, 10): FinTerrain.iron,
    (5, 11): FinTerrain.iron,
    (5, 14): FinTerrain.copper,
    (5, 18): FinTerrain.crystal,
    (5, 22): FinTerrain.biomass,
  });
  void put(FinBuilding k, int x, int y, {int dir = 1}) =>
      expect(w.place(k, x, y, dir: dir), isNotNull, reason: '$k at $x,$y');
  // Iron: two drills merge on one belt into the furnace, plates to gears.
  put(FinBuilding.drill, 5, 10);
  put(FinBuilding.drill, 5, 11);
  w.placeBeltLine(6, 11, 6, 11);
  w.machineAt(6, 11)!.dir = 0;
  w.placeBeltLine(6, 10, 8, 10);
  put(FinBuilding.furnace, 9, 10);
  w.placeBeltLine(10, 10, 12, 10);
  put(FinBuilding.assembler, 13, 10);
  w.setRecipe(w.machineAt(13, 10)!.id, 'gear');
  put(FinBuilding.storage, 14, 10);
  // Copper and crystal into the circuit assembler, circuits into the lab.
  put(FinBuilding.drill, 5, 14);
  w.placeBeltLine(6, 14, 8, 14);
  put(FinBuilding.furnace, 9, 14);
  w.placeBeltLine(10, 14, 12, 14);
  put(FinBuilding.assembler, 13, 14);
  w.setRecipe(w.machineAt(13, 14)!.id, 'circuit');
  put(FinBuilding.lab, 14, 14);
  put(FinBuilding.drill, 5, 18);
  w.placeBeltLine(6, 18, 13, 15);
  // Power: two generators, one fed by a biomass belt.
  put(FinBuilding.generator, 10, 12);
  put(FinBuilding.generator, 9, 20);
  put(FinBuilding.drill, 5, 22);
  w.placeBeltLine(6, 22, 9, 21);
  w.insert(w.machineAt(10, 12)!.id, FinItem.biomass, 20);
  w.insert(w.machineAt(9, 20)!.id, FinItem.biomass, 10);
  return w;
}
