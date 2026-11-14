part of 'world.dart';

/// Research: the technology tree bought with credits.
extension MagWorldTech on MagWorld {
  /// Sum of a bonus over the technologies learned.
  double bonus(String key) {
    var sum = 0.0;
    for (final id in techs) {
      sum += MagTechTree.byId(id)?.effects[key] ?? 0;
    }
    // Finished megaprojects work for ever (stage S10).
    for (final i in map.industries) {
      if (!i.projectDone) continue;
      sum += MagMegaprojects.byId(i.project ?? '')?.effects[key] ?? 0;
    }
    return sum;
  }

  /// Multiplier from a fractional bonus (never below 10 %).
  double factor(String key) => math.max(.1, 1 + bonus(key));

  /// Can the company buy motor vehicles? Companies from before the horse
  /// era (old maps) always could; new games learn the engine first.
  bool get motorUnlocked => map.version < 2 || bonus(MagBonus.motors) > 0;

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

  /// Reads the learned technologies of a save. A save from before 1.83
  /// ([old]) gets the recipe technologies its company level allowed then,
  /// so nothing it could build is taken away.
  void loadTechs(List<Object?> ids, {required bool old}) {
    for (final t in ids) {
      if (t is! String || MagTechTree.byId(t) == null) {
        throw const FormatException('Unknown technology');
      }
      techs.add(t);
    }
    if (!old) return;
    for (final t in magTechRecipes) {
      if (level >= t.level) techs.add(t.id);
    }
  }
}
