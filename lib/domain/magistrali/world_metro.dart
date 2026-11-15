part of 'world.dart';

/// Stage S29: metro lines (METRO-02) — tunnels under the map between
/// cities that have a metro. A line carries people by itself: fares every
/// day by the size of both cities, and each line makes its cities grow a
/// little faster still.
extension MagWorldMetro on MagWorld {
  bool _linked(int a, int b) =>
      metroLines.any((l) => l.$1 == a && l.$2 == b || l.$1 == b && l.$2 == a);

  int _metroDistance(MagIndustry a, MagIndustry b) =>
      (a.centerX - b.centerX).abs().round() +
      (a.centerY - b.centerY).abs().round();

  int metroLinePrice(MagIndustry a, MagIndustry b) =>
      MagRules.metroLineCell * _metroDistance(a, b);

  String? metroLineBlocker(int a, int b) {
    final x = map.industry(a), y = map.industry(b);
    if (x == null || y == null || a == b) return 'Нужны два города';
    if (!metros.contains(a) || !metros.contains(b)) {
      return 'Линия соединяет города, где уже есть метро';
    }
    if (_linked(a, b)) return 'Линия уже есть';
    if (_metroDistance(x, y) > MagRules.metroLineReach) {
      return 'Слишком далеко: линия метро — до ${MagRules.metroLineReach} клеток';
    }
    return null;
  }

  String? buildMetroLine(int a, int b) {
    final why = metroLineBlocker(a, b);
    if (why != null) return why;
    final price = metroLinePrice(map.industry(a)!, map.industry(b)!);
    if (money < price) return 'Не хватает кредитов: нужно $price';
    _spend(price, 'metro', source: 'industry', sourceId: a);
    metroLines.add((a, b));
    _say(
      'Линия метро «${map.industry(a)!.name}» — «${map.industry(b)!.name}» открыта',
    );
    return null;
  }

  /// Lines from a city.
  int metroLinesOf(MagIndustry i) =>
      metroLines.where((l) => l.$1 == i.id || l.$2 == i.id).length;

  /// Fares a line brings a day.
  int metroLineFares((int, int) l) {
    final a = map.industry(l.$1)?.town, b = map.industry(l.$2)?.town;
    if (a == null || b == null) return 0;
    return ((a.population + b.population) * MagRules.metroLineFare).round();
  }

  void _dayMetroLines() {
    metroLines.removeWhere(
      (l) => !metros.contains(l.$1) || !metros.contains(l.$2),
    );
    for (final l in metroLines) {
      final f = metroLineFares(l);
      if (f > 0) _earn(f, 'metro_lines');
    }
  }

  Map<String, Object> _saveMetro() => {
    if (metroLines.isNotEmpty)
      'metrolines': [
        for (final l in metroLines) [l.$1, l.$2],
      ],
  };

  void loadMetro(Map<String, dynamic> j) {
    for (final raw in j['metrolines'] as List? ?? const []) {
      final l = raw as List;
      metroLines.add((l[0] as int, l[1] as int));
    }
  }
}
