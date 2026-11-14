/// Megaprojects (stage S10: META-06, CONT-08): great works a city commissions
/// and the company builds by real deliveries — a contract for
/// infrastructure. Each is built once per company; when the last load
/// arrives the city pays the reward and the work gives a lasting effect.
library;

import 'config.dart';

class MagMegaproject {
  const MagMegaproject({
    required this.id,
    required this.name,
    required this.lore,
    required this.cityLevel,
    required this.fee,
    required this.needs,
    required this.reward,
    required this.effects,
    required this.effectText,
  });

  final String id, name, lore;

  /// The city's level needed to commission it.
  final int cityLevel;

  /// What the company pays to start the works (an investment).
  final int fee;

  /// What must be delivered (cargo nobody can make is waived).
  final Map<MagCargo, int> needs;

  /// What the city pays when it is done.
  final int reward;

  /// Lasting bonuses once built (keys of MagBonus), and in words.
  final Map<String, double> effects;
  final String effectText;
}

abstract final class MagMegaprojects {
  static const all = <MagMegaproject>[
    MagMegaproject(
      id: 'bridge',
      name: 'Большой мост',
      lore:
          'Стальные фермы над рекой и гранитные быки. Город соединит берега, '
          'а вся страна поедет быстрее.',
      cityLevel: 7,
      fee: 15000,
      needs: {MagCargo.steel: 200, MagCargo.stone: 300, MagCargo.bricks: 150},
      reward: 30000,
      effects: {'roadSpeed': .1},
      effectText: 'Скорость на всех дорогах +10%',
    ),
    MagMegaproject(
      id: 'station',
      name: 'Центральный вокзал',
      lore:
          'Кирпичный дворец с часами и стеклянным дебаркадером. Грузы здесь '
          'перекладывают быстрее, чем где-либо.',
      cityLevel: 7,
      fee: 20000,
      needs: {MagCargo.bricks: 300, MagCargo.steel: 150, MagCargo.planks: 200},
      reward: 36000,
      effects: {'handling': .25},
      effectText: 'Погрузка и разгрузка +25%',
    ),
    MagMegaproject(
      id: 'exchange',
      name: 'Товарная биржа',
      lore:
          'Колонны, табло и сотни телефонов. Цены на перевозки здесь '
          'назначают для всего региона.',
      cityLevel: 8,
      fee: 30000,
      needs: {MagCargo.goods: 300, MagCargo.parts: 100, MagCargo.bread: 300},
      reward: 50000,
      effects: {'pay': .06},
      effectText: 'Оплата перевозок +6%',
    ),
    MagMegaproject(
      id: 'tower',
      name: 'Телебашня',
      lore:
          'Стальная игла выше облаков. Её видно из каждого посёлка — и каждый '
          'хочет работать с вашей компанией.',
      cityLevel: 9,
      fee: 45000,
      needs: {MagCargo.steel: 500, MagCargo.parts: 250, MagCargo.bricks: 400},
      reward: 80000,
      effects: {'contract': .25, 'xp': .1},
      effectText: 'Награды контрактов +25%, опыт +10%',
    ),
    MagMegaproject(
      id: 'expo',
      name: 'Выставка достижений',
      lore:
          'Павильоны, фонтаны и аллеи — витрина всего, что сделала страна '
          'и ваша компания.',
      cityLevel: 10,
      fee: 60000,
      needs: {
        MagCargo.goods: 600,
        MagCargo.parts: 400,
        MagCargo.steel: 400,
        MagCargo.bread: 500,
      },
      reward: 120000,
      effects: {'pay': .08, 'speed': .05},
      effectText: 'Оплата перевозок +8%, скорость машин +5%',
    ),
  ];

  static MagMegaproject? byId(String id) =>
      all.where((p) => p.id == id).firstOrNull;
}
