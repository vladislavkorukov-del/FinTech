/// Settlements that grow on their own, from a hamlet to a megacity. Every
/// number here is configuration: levels, territory, population, regular
/// needs, what development asks for, and what each level opens to earn.
library;

import 'config.dart';

/// What a settlement leans towards (chosen from its surroundings).
enum MagSpecialization { farming, forestry, mining, trade, industry }

/// One level of a settlement.
class MagTownLevel {
  const MagTownLevel({
    required this.level,
    required this.name,
    required this.cells,
    required this.population,
    required this.needs,
    required this.development,
    required this.opens,
    this.payBonus = 0,
  });

  final int level;
  final String name;

  /// Territory it should cover at this level (cells of the map).
  final int cells;

  /// Population needed to reach this level.
  final int population;

  /// Regular supply: units per day it uses up at this level.
  final Map<MagCargo, int> needs;

  /// One-off delivery needed (beyond regular supply) to grow from this
  /// level to the next. Counted once, used up on growth.
  final Map<MagCargo, int> development;

  /// New ways to earn that this level brings (shown to the player).
  final List<String> opens;

  /// Extra pay for deliveries to a settlement of this level (a bigger
  /// market pays more).
  final double payBonus;
}

abstract final class MagTowns {
  static const levels = <MagTownLevel>[
    MagTownLevel(
      level: 1,
      name: 'Хутор',
      cells: 1,
      population: 20,
      needs: {MagCargo.grain: 2},
      development: {
        MagCargo.grain: 20,
        MagCargo.planks: 15,
        MagCargo.bread: 10,
      },
      opens: [
        'Перевозка зерна жителям',
        'Первые простые контракты',
        'Контракт развития: доски и хлеб на первые дома',
      ],
    ),
    MagTownLevel(
      level: 2,
      name: 'Деревня',
      cells: 2,
      population: 60,
      needs: {MagCargo.grain: 2, MagCargo.food: 2},
      development: {
        MagCargo.food: 30,
        MagCargo.wood: 20,
        MagCargo.planks: 30,
        MagCargo.stone: 20,
        MagCargo.bread: 20,
      },
      opens: [
        'Спрос на продукты и хлеб',
        'Доставка древесины и досок',
        'Контракт развития: камень и доски на село',
      ],
      payBonus: .02,
    ),
    MagTownLevel(
      level: 3,
      name: 'Большое село',
      cells: 3,
      population: 150,
      needs: {MagCargo.food: 4, MagCargo.wood: 2},
      development: {
        MagCargo.food: 80,
        MagCargo.wood: 60,
        MagCargo.stone: 50,
        MagCargo.planks: 40,
      },
      opens: [
        'Постоянный спрос на древесину',
        'Рынок камня: стройка идёт всерьёз',
        'Контракты крупнее',
      ],
      payBonus: .04,
    ),
    MagTownLevel(
      level: 4,
      name: 'Торговый посёлок',
      cells: 5,
      population: 350,
      needs: {MagCargo.food: 6, MagCargo.wood: 3, MagCargo.goods: 1},
      development: {MagCargo.goods: 40, MagCargo.food: 120},
      opens: ['Первый спрос на промтовары', 'Торговые контракты'],
      payBonus: .06,
    ),
    MagTownLevel(
      level: 5,
      name: 'Малый город',
      cells: 7,
      population: 700,
      needs: {MagCargo.food: 8, MagCargo.wood: 4, MagCargo.goods: 3},
      development: {MagCargo.goods: 90, MagCargo.wood: 150},
      opens: ['Городской рынок: выше оплата', 'Контракты городского снабжения'],
      payBonus: .08,
    ),
    MagTownLevel(
      level: 6,
      name: 'Промышленный город',
      cells: 10,
      population: 1400,
      needs: {
        MagCargo.food: 11,
        MagCargo.wood: 5,
        MagCargo.goods: 5,
        MagCargo.ore: 2,
      },
      development: {MagCargo.goods: 160, MagCargo.ore: 120, MagCargo.food: 220},
      opens: ['Промышленные заказы на руду', 'Крупные склады выгодны'],
      payBonus: .1,
    ),
    MagTownLevel(
      level: 7,
      name: 'Развитый город',
      cells: 15,
      population: 3000,
      needs: {
        MagCargo.food: 15,
        MagCargo.wood: 6,
        MagCargo.goods: 8,
        MagCargo.ore: 3,
      },
      development: {MagCargo.goods: 280, MagCargo.food: 380, MagCargo.ore: 200},
      opens: ['Дорогие контракты', 'Спрос на быстрые доставки'],
      payBonus: .12,
    ),
    MagTownLevel(
      level: 8,
      name: 'Региональный центр',
      cells: 21,
      population: 6000,
      needs: {
        MagCargo.food: 20,
        MagCargo.wood: 8,
        MagCargo.goods: 12,
        MagCargo.ore: 4,
      },
      development: {
        MagCargo.goods: 450,
        MagCargo.food: 600,
        MagCargo.wood: 400,
      },
      opens: ['Региональные поставки', 'Крупные логистические заказы'],
      payBonus: .15,
    ),
    MagTownLevel(
      level: 9,
      name: 'Метрополия',
      cells: 28,
      population: 12000,
      needs: {
        MagCargo.food: 27,
        MagCargo.wood: 10,
        MagCargo.goods: 17,
        MagCargo.ore: 5,
      },
      development: {MagCargo.goods: 700, MagCargo.food: 900, MagCargo.ore: 500},
      opens: ['Главный рынок региона', 'Огромные объёмы снабжения'],
      payBonus: .18,
    ),
    MagTownLevel(
      level: 10,
      name: 'Мегаполис',
      cells: 37,
      population: 25000,
      needs: {
        MagCargo.food: 36,
        MagCargo.wood: 12,
        MagCargo.goods: 24,
        MagCargo.ore: 6,
      },
      development: {},
      opens: ['Источник самых крупных заказов', 'Высшая оплата перевозок'],
      payBonus: .22,
    ),
  ];

  static const maxLevel = 10;

  static MagTownLevel of(int level) => levels[level.clamp(1, maxLevel) - 1];

  /// Goods its market buys besides its needs: bread and planks from the
  /// start, stone once it builds in earnest.
  static Set<MagCargo> marketGoods(int level) => {
    MagCargo.bread,
    MagCargo.planks,
    if (level >= 3) MagCargo.stone,
  };

  /// Days of regular needs a settlement's pantry holds.
  static const pantryDays = 5;

  /// Days of supply remembered for satisfaction.
  static const memoryDays = 7;

  /// Daily growth at full satisfaction (share of population), and loss
  /// when supply is poor. A settlement never falls below its level.
  static const growth = .03, decline = .01;

  /// Satisfaction needed to grow, and below which it shrinks.
  static const growAt = .6, shrinkAt = .3;

  /// Free ring kept round each settlement on new maps, so it can grow.
  static const room = 4;

  /// Reward of a development contract: half the market value of what it
  /// asks for, plus a bonus by level.
  static int devReward(int level, Map<MagCargo, int> asks) {
    var value = 0.0;
    for (final e in asks.entries) {
      value += e.value * MagRules.cargoValue[e.key]!;
    }
    return (value * .5 + 200 * level).round();
  }

  static String specializationName(MagSpecialization s) => switch (s) {
    MagSpecialization.farming => 'Аграрное',
    MagSpecialization.forestry => 'Лесное',
    MagSpecialization.mining => 'Горняцкое',
    MagSpecialization.trade => 'Торговое',
    MagSpecialization.industry => 'Промышленное',
  };
}

/// A real event in a settlement's life.
class MagTownEvent {
  const MagTownEvent(this.tick, this.text);
  final int tick;
  final String text;
}

/// The life of one settlement: its level, people, land, supply and story.
class MagSettlement {
  MagSettlement({
    required this.level,
    required this.population,
    required this.specialization,
  });

  int level;
  int population;
  MagSpecialization specialization;

  /// Cells it covers, as `y * 1024 + x` keys.
  final Set<int> cells = {};

  /// Its own stores for regular needs (filled by deliveries, used daily).
  final Map<MagCargo, int> pantry = {};

  /// Share of needs met on each of the last days (0..1).
  final List<double> satisfaction = [];

  /// Delivered towards the next level (beyond regular supply).
  final Map<MagCargo, int> devStock = {};

  /// Grows with every delivery by the player.
  int reputation = 0;

  /// The development contract of the current level has been paid (once
  /// per level).
  bool devPaid = false;

  /// Why the last growth could not happen (null: no problem).
  String? blocked;

  final history = <MagTownEvent>[];

  static int key(int x, int y) => y * 1024 + x;
  static int keyX(int k) => k % 1024;
  static int keyY(int k) => k ~/ 1024;

  MagTownLevel get spec => MagTowns.of(level);

  double get averageSatisfaction => satisfaction.isEmpty
      ? 0
      : satisfaction.reduce((a, b) => a + b) / satisfaction.length;

  void remember(int tick, String text) {
    history.add(MagTownEvent(tick, text));
    if (history.length > 40) history.removeAt(0);
  }
}
