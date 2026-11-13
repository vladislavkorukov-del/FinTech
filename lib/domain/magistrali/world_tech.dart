part of 'world.dart';

/// Research: the technology tree bought with credits.
extension MagWorldTech on MagWorld {
  /// Sum of a bonus over the technologies learned.
  double bonus(String key) {
    var sum = 0.0;
    for (final id in techs) {
      sum += MagTechTree.byId(id)?.effects[key] ?? 0;
    }
    return sum;
  }

  /// Multiplier from a fractional bonus (never below 10 %).
  double factor(String key) => math.max(.1, 1 + bonus(key));

  /// Units moved per tick when loading or unloading.
  int get handleRate =>
      math.max(1, (MagRules.handlePerTick * factor(MagBonus.handling)).round());

  /// Why a technology cannot be learned now (null: it can, money allowing).
  String? techBlocker(MagTech t) {
    if (techs.contains(t.id)) return 'Уже изучено';
    if (level < t.level) return 'Нужен ${t.level} уровень компании';
    for (final r in t.requires) {
      if (!techs.contains(r)) {
        return 'Сначала: ${MagTechTree.byId(r)?.title ?? r}';
      }
    }
    if (deliveries < t.deliveries) {
      return 'Нужно ${t.deliveries} доставок (сейчас $deliveries)';
    }
    return null;
  }

  String? research(String id) {
    final t = MagTechTree.byId(id);
    if (t == null) return 'Нет такой технологии';
    final why = techBlocker(t);
    if (why != null) return why;
    if (money < t.cost) return 'Не хватает кредитов';
    _spend(t.cost, 'research');
    techs.add(id);
    _say('Изучено: ${t.title}');
    return null;
  }
}
