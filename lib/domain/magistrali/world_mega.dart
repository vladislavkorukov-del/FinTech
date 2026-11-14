part of 'world.dart';

/// Stage S10: megaprojects (META-06) commissioned by a city as an
/// infrastructure contract (CONT-08), and the first megalopolis (META-03,
/// META-04).
extension MagWorldMega on MagWorld {
  Iterable<MagIndustry> get megaprojects =>
      map.industries.where((i) => i.kind == MagIndustryKind.megaproject);

  /// The site of a project, if it was started (done or not).
  MagIndustry? siteOf(String projectId) =>
      megaprojects.where((i) => i.project == projectId).firstOrNull;

  /// Why [p] cannot be started for city [townId] (null: it can).
  String? megaprojectBlocker(String projectId, int townId) {
    final p = MagMegaprojects.byId(projectId);
    final town = map.industry(townId);
    if (p == null) return 'Нет такого мегапроекта';
    if (town?.town == null) return 'Мегапроект заказывает город';
    if (town!.town!.level < p.cityLevel) {
      return 'Городу нужен ${p.cityLevel} уровень';
    }
    if (siteOf(projectId) != null) return 'Этот мегапроект уже начат';
    if (money < p.fee) return 'Не хватает кредитов: нужно ${p.fee}';
    if (_megaSpot(town) == null) return 'Рядом с городом нет места 3×3';
    return null;
  }

  /// Free 3×3 land near a city (nearest first), or null.
  (int, int)? _megaSpot(MagIndustry town) {
    const s = 3;
    for (var r = 1; r <= 8; r++) {
      for (var y = town.top - r - s; y <= town.bottom + r; y++) {
        for (var x = town.left - r - s; x <= town.right + r; x++) {
          var ok = true;
          for (var yy = y; yy < y + s && ok; yy++) {
            for (var xx = x; xx < x + s && ok; xx++) {
              ok =
                  map.roadable(xx, yy) &&
                  !hasRoad(xx, yy) &&
                  !hasRail(xx, yy) &&
                  !town.covers(xx, yy);
            }
          }
          if (ok) return (x, y);
        }
      }
    }
    return null;
  }

  /// Starts a megaproject by a city: the company pays the fee, a building
  /// site appears next to the city and takes the deliveries it needs.
  String? startMegaproject(String projectId, int townId) {
    final why = megaprojectBlocker(projectId, townId);
    if (why != null) return why;
    final p = MagMegaprojects.byId(projectId)!;
    final town = map.industry(townId)!;
    final (x, y) = _megaSpot(town)!;
    final id = MagRules.builtIdBase + nextId++;
    _spend(p.fee, 'megaprojects', source: 'industry', sourceId: id);
    final site =
        MagIndustry(
            id: id,
            kind: MagIndustryKind.megaproject,
            x: x,
            y: y,
            name: '${p.name} · ${town.name}',
          )
          ..built = true
          ..project = p.id
          ..projectTown = townId;
    for (final e in p.needs.entries) {
      if (cargoAvailable(e.key)) site.projectNeeds[e.key] = e.value;
    }
    map.industries.add(site);
    roadVersion++;
    town.town!.remember(tick, 'Начат мегапроект «${p.name}»');
    _say('Мегапроект «${p.name}»: подведите дорогу и везите материалы');
    return null;
  }

  /// A delivery to a site: what it still needs counts, the rest is sold.
  void _megaReceive(MagIndustry site, MagCargo c, int n) {
    final left = site.projectLeft[c] ?? 0;
    final used = math.min(left, n);
    if (used > 0) {
      site.projectProgress[c] = (site.projectProgress[c] ?? 0) + used;
    }
    destroyed[c] = (destroyed[c] ?? 0) + n; // built in, or sold
    if (site.projectDone || site.projectLeft.isNotEmpty) return;
    final p = MagMegaprojects.byId(site.project ?? '');
    if (p == null) return;
    site.projectDone = true;
    _earn(p.reward, 'infrastructure', source: 'industry', sourceId: site.id);
    _gainXp(p.reward ~/ 20);
    final town = map.industry(site.projectTown ?? -1);
    final t = town?.town;
    if (t != null) {
      t
        ..reputation += 1000
        ..revenue += p.reward
        ..remember(tick, 'Мегапроект «${p.name}» построен: +${p.reward} кр');
    }
    _say('Мегапроект «${p.name}» построен! ${p.effectText}');
  }

  /// A settlement reached level 10: the first one that started as a hamlet
  /// earns «От хутора до мегаполиса» — once per game, for ever.
  void _megapolisReached(MagIndustry i) {
    final t = i.town!;
    if (firstMegapolis != null || t.origin != 1) return;
    firstMegapolis = i.id;
    firstMegapolisTick = tick;
    _earn(
      MagRules.megapolisReward,
      'achievement',
      source: 'settlement',
      sourceId: i.id,
    );
    _gainXp(MagRules.megapolisReward ~/ 20);
    t.remember(tick, 'Достижение «От хутора до мегаполиса»!');
    _say('«От хутора до мегаполиса»: ${i.name} — первый мегаполис!');
  }
}
