/// The resources and production chains of the master plan, as editable
/// configuration. Stage 1 only describes them; each later stage switches
/// its part on (the cargo the simulation already runs is marked
/// [MagResourceDef.active]). Tests check the chains are whole: every input
/// can be made from raw resources of the same era or earlier, and nothing
/// is made from itself.
library;

/// Transport eras of the company (independent of settlement levels).
enum MagEra { horses, steam, trucks, modern, electric }

class MagResourceDef {
  const MagResourceDef(
    this.id,
    this.name,
    this.era, {
    this.raw = false,
    this.active = false,
    this.value = 1,
  });
  final String id, name;
  final MagEra era;

  /// Mined, grown or felled (no inputs).
  final bool raw;

  /// Already carried by the simulation (MagCargo).
  final bool active;

  /// Rough market value per unit (balance reference, credits).
  final double value;
}

class MagRecipeDef {
  const MagRecipeDef({
    required this.building,
    required this.inputs,
    required this.outputs,
    required this.era,
    this.perDay = 10,
    this.townLevel = 1,
  });

  /// Building name (as the player sees it).
  final String building;
  final Map<String, int> inputs, outputs;
  final MagEra era;

  /// Output units per day at level 1 of the building.
  final int perDay;

  /// Settlement level around which this production starts to pay.
  final int townLevel;
}

abstract final class MagEconomy {
  static const resources = <MagResourceDef>[
    // Era I — horses: grain, wood, stone, clay and their first goods.
    MagResourceDef(
      'grain',
      'Зерно',
      MagEra.horses,
      raw: true,
      active: true,
      value: 3,
    ),
    MagResourceDef(
      'wood',
      'Древесина',
      MagEra.horses,
      raw: true,
      active: true,
      value: 3.5,
    ),
    MagResourceDef(
      'stone',
      'Камень',
      MagEra.horses,
      raw: true,
      active: true,
      value: 4,
    ),
    MagResourceDef(
      'clay',
      'Глина',
      MagEra.horses,
      raw: true,
      active: true,
      value: 2.5,
    ),
    MagResourceDef('planks', 'Доски', MagEra.horses, active: true, value: 9),
    MagResourceDef('flour', 'Мука', MagEra.horses, active: true, value: 8),
    MagResourceDef('bread', 'Хлеб', MagEra.horses, active: true, value: 13),
    MagResourceDef('bricks', 'Кирпич', MagEra.horses, active: true, value: 8),
    MagResourceDef('food', 'Продукты', MagEra.horses, active: true, value: 8),
    // Era II — steam: ore, coal, steel.
    MagResourceDef(
      'ore',
      'Железная руда',
      MagEra.steam,
      raw: true,
      active: true,
      value: 4.5,
    ),
    MagResourceDef(
      'coal',
      'Уголь',
      MagEra.steam,
      raw: true,
      active: true,
      value: 4,
    ),
    MagResourceDef('steel', 'Сталь', MagEra.steam, active: true, value: 18),
    MagResourceDef('parts', 'Детали', MagEra.steam, active: true, value: 34),
    // Era III — trucks: machines, oil, fuel, goods.
    MagResourceDef(
      'goods',
      'Промтовары',
      MagEra.trucks,
      active: true,
      value: 12,
    ),
    MagResourceDef(
      'machines',
      'Машины и оборудование',
      MagEra.trucks,
      value: 45,
    ),
    MagResourceDef('oil', 'Нефть', MagEra.trucks, raw: true, value: 6),
    MagResourceDef('fuel', 'Топливо', MagEra.trucks, value: 14),
    // Era IV–V — electronics and high technology.
    MagResourceDef(
      'components',
      'Промышленные компоненты',
      MagEra.modern,
      value: 30,
    ),
    MagResourceDef(
      'electrics',
      'Электрооборудование',
      MagEra.modern,
      value: 55,
    ),
    MagResourceDef('electronics', 'Электроника', MagEra.electric, value: 90),
    MagResourceDef(
      'hightech',
      'Высокотехнологичные товары',
      MagEra.electric,
      value: 160,
    ),
  ];

  static const recipes = <MagRecipeDef>[
    MagRecipeDef(
      building: 'Лесопилка',
      inputs: {'wood': 2},
      outputs: {'planks': 1},
      era: MagEra.horses,
      perDay: 8,
    ),
    MagRecipeDef(
      building: 'Мельница',
      inputs: {'grain': 2},
      outputs: {'flour': 1},
      era: MagEra.horses,
      perDay: 8,
    ),
    MagRecipeDef(
      building: 'Пекарня',
      inputs: {'flour': 1},
      outputs: {'bread': 1},
      era: MagEra.horses,
      perDay: 6,
      townLevel: 2,
    ),
    MagRecipeDef(
      building: 'Кирпичная мастерская',
      inputs: {'clay': 2},
      outputs: {'bricks': 1},
      era: MagEra.horses,
      perDay: 6,
      townLevel: 3,
    ),
    MagRecipeDef(
      building: 'Пищевой завод',
      inputs: {'grain': 1},
      outputs: {'food': 1},
      era: MagEra.horses,
      perDay: 14,
      townLevel: 2,
    ),
    MagRecipeDef(
      building: 'Металлургический завод',
      inputs: {'ore': 2, 'coal': 1},
      outputs: {'steel': 1},
      era: MagEra.steam,
      perDay: 6,
      townLevel: 5,
    ),
    MagRecipeDef(
      building: 'Завод деталей',
      inputs: {'planks': 1, 'steel': 1},
      outputs: {'parts': 1},
      era: MagEra.steam,
      perDay: 5,
      townLevel: 6,
    ),
    MagRecipeDef(
      building: 'Машиностроительный завод',
      inputs: {'steel': 2, 'parts': 1},
      outputs: {'machines': 1},
      era: MagEra.trucks,
      perDay: 3,
      townLevel: 7,
    ),
    MagRecipeDef(
      building: 'Завод товаров',
      inputs: {'wood': 1, 'ore': 1},
      outputs: {'goods': 2},
      era: MagEra.trucks,
      perDay: 14,
      townLevel: 4,
    ),
    MagRecipeDef(
      building: 'НПЗ',
      inputs: {'oil': 2},
      outputs: {'fuel': 1},
      era: MagEra.trucks,
      perDay: 8,
      townLevel: 6,
    ),
    MagRecipeDef(
      building: 'Завод компонентов',
      inputs: {'steel': 1, 'parts': 1},
      outputs: {'components': 1},
      era: MagEra.modern,
      perDay: 4,
      townLevel: 8,
    ),
    MagRecipeDef(
      building: 'Электротехнический завод',
      inputs: {'components': 2},
      outputs: {'electrics': 1},
      era: MagEra.modern,
      perDay: 3,
      townLevel: 8,
    ),
    MagRecipeDef(
      building: 'Завод электроники',
      inputs: {'electrics': 1, 'components': 1},
      outputs: {'electronics': 1},
      era: MagEra.electric,
      perDay: 2,
      townLevel: 9,
    ),
    MagRecipeDef(
      building: 'Технопарк',
      inputs: {'electronics': 1, 'steel': 1},
      outputs: {'hightech': 1},
      era: MagEra.electric,
      perDay: 1,
      townLevel: 10,
    ),
  ];

  static MagResourceDef? resource(String id) =>
      resources.where((r) => r.id == id).firstOrNull;

  /// Resources that can be made by [era]: raw ones of that era or earlier,
  /// and everything their recipes of that era or earlier make.
  static Set<String> makeable(MagEra era) {
    final made = {
      for (final r in resources)
        if (r.raw && r.era.index <= era.index) r.id,
    };
    var more = true;
    while (more) {
      more = false;
      for (final rc in recipes) {
        if (rc.era.index > era.index) continue;
        if (rc.inputs.keys.every(made.contains)) {
          for (final o in rc.outputs.keys) {
            if (made.add(o)) more = true;
          }
        }
      }
    }
    return made;
  }
}
