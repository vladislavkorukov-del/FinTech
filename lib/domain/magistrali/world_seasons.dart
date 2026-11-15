part of 'world.dart';

enum MagSeason { spring, summer, autumn, winter }

enum MagWeather { clear, rain, snow, fog, storm }

/// Something that happens for a while (S22): a festival in a settlement,
/// a strike at a plant, a boom of a cargo, dear fuel.
class MagEvent {
  MagEvent(this.kind, this.until, {this.place, this.cargo});
  final String kind; // festival, strike, boom, fuel
  final int until;
  final int? place;
  final MagCargo? cargo;
}

/// A chapter of the campaign (S22): its goal and reward.
class MagChapter {
  const MagChapter(this.title, this.goal, this.reward, this.test);
  final String title, goal;
  final int reward;
  final bool Function(MagWorld w) test;
}

final magChapters = <MagChapter>[
  MagChapter(
    'Первые шаги',
    'Соберите парк из 3 машин',
    2000,
    (w) => w.vehicles.length >= 3,
  ),
  MagChapter(
    'Своё дело',
    'Купите или постройте своё предприятие',
    5000,
    (w) => w.map.industries.any((i) => i.owned),
  ),
  MagChapter(
    'Стальная колея',
    'Пустите первый поезд',
    12000,
    (w) => w.vehicles.values.any((v) => v.spec.rail),
  ),
  MagChapter(
    'Город растёт',
    'Доведите поселение до 4 уровня',
    15000,
    (w) => w.settlements.any((t) => t.town!.level >= 4),
  ),
  MagChapter(
    'Речной путь',
    'Спустите на воду первое судно',
    20000,
    (w) => w.vehicles.values.any((v) => v.spec.water),
  ),
  MagChapter(
    'Индустрия',
    '3 своих предприятия и 500 доставок',
    40000,
    (w) =>
        w.map.industries.where((i) => i.owned).length >= 3 &&
        w.deliveries >= 500,
  ),
  MagChapter(
    'Небо',
    'Поднимите в воздух первый самолёт',
    80000,
    (w) => w.vehicles.values.any((v) => v.spec.air),
  ),
  MagChapter(
    'Мегаполис',
    'Вырастите город до 10 уровня',
    150000,
    (w) => w.settlements.any((t) => t.town!.level >= 10),
  ),
  MagChapter('Магнат', 'Компания 25 уровня', 300000, (w) => w.level >= 25),
];

/// Stage S22: seasons and weather, events, the campaign. They run in a
/// living world: new companies and saves from before 1.94.
extension MagWorldSeasons on MagWorld {
  // ---- Seasons and weather ----

  MagSeason get season => MagSeason.values[(day ~/ MagRules.daysPerMonth) % 4];

  static String seasonName(MagSeason s) => switch (s) {
    MagSeason.spring => 'Весна',
    MagSeason.summer => 'Лето',
    MagSeason.autumn => 'Осень',
    MagSeason.winter => 'Зима',
  };

  static String weatherName(MagWeather w) => switch (w) {
    MagWeather.clear => 'Ясно',
    MagWeather.rain => 'Дождь',
    MagWeather.snow => 'Снег',
    MagWeather.fog => 'Туман',
    MagWeather.storm => 'Шторм',
  };

  /// Today's weather: the same for a seed and a day.
  MagWeather get weather {
    if (!livingWorld) return MagWeather.clear;
    var h = map.seed * 2654435761 + day * 40503 + 977;
    h = (h ^ (h >> 13)) & 0x7fffffff;
    final r = h % 100;
    return switch (season) {
      MagSeason.winter =>
        r < 35
            ? MagWeather.snow
            : r < 45
            ? MagWeather.fog
            : MagWeather.clear,
      MagSeason.autumn =>
        r < 30
            ? MagWeather.rain
            : r < 42
            ? MagWeather.fog
            : r < 47
            ? MagWeather.storm
            : MagWeather.clear,
      MagSeason.spring =>
        r < 30
            ? MagWeather.rain
            : r < 34
            ? MagWeather.storm
            : MagWeather.clear,
      MagSeason.summer =>
        r < 12
            ? MagWeather.rain
            : r < 16
            ? MagWeather.storm
            : MagWeather.clear,
    };
  }

  /// Harvests follow the year: summer +20%, autumn +10%, winter half.
  double seasonFactor(MagIndustry i) {
    if (!livingWorld || i.spec.produces.isEmpty || i.town != null) return 1;
    if (i.kind == MagIndustryKind.farm) {
      return switch (season) {
        MagSeason.summer => 1.2,
        MagSeason.autumn => 1.1,
        MagSeason.winter => .5,
        MagSeason.spring => 1,
      };
    }
    if (i.kind == MagIndustryKind.sawmill && season == MagSeason.winter) {
      return .9;
    }
    return 1;
  }

  /// Weather on the move: rain and snow slow road vehicles (less on good
  /// roads), fog and storms slow vessels and aircraft.
  double weatherSpeed(MagVehicle v) {
    final w = weather;
    if (w == MagWeather.clear) return 1;
    if (v.spec.air) {
      return w == MagWeather.storm
          ? .5
          : w == MagWeather.fog
          ? .8
          : 1;
    }
    if (v.spec.water) {
      return w == MagWeather.storm
          ? .6
          : w == MagWeather.fog
          ? .8
          : season == MagSeason.winter
          ? .85
          : 1;
    }
    if (v.spec.rail) return w == MagWeather.snow ? .9 : 1;
    return switch (w) {
      MagWeather.rain => .9,
      MagWeather.snow => .8,
      MagWeather.storm => .85,
      _ => 1,
    };
  }

  // ---- Events ----

  bool isStruck(MagIndustry i) => events.any(
    (e) => e.kind == 'strike' && e.place == i.id && e.until > tick,
  );

  /// Festivals pay +40% for their cargo in their settlement; a boom pays
  /// +30% for its cargo everywhere.
  double eventPayFactor(MagIndustry here, MagCargo c) {
    var k = 1.0;
    for (final e in events) {
      if (e.until <= tick) continue;
      if (e.kind == 'festival' && e.place == here.id && e.cargo == c) k *= 1.4;
      if (e.kind == 'boom' && e.cargo == c) k *= 1.3;
    }
    return k;
  }

  /// Dear fuel: running costs +40%.
  double get fuelFactor =>
      events.any((e) => e.kind == 'fuel' && e.until > tick) ? 1.4 : 1;

  /// The living world's day: events, then the campaign.
  void _dayLiving() {
    _dayEvents();
    _dayCampaign();
  }

  void _dayEvents() {
    events.removeWhere((e) => e.until <= tick);
    if (!livingWorld || level < 3 || events.length >= 3) return;
    var h = map.seed * 40503 + day * 2654435761 + 31;
    h = (h ^ (h >> 15)) & 0x7fffffff;
    if (h % 100 >= MagRules.eventChance) return;
    final kind = const [
      'festival',
      'strike',
      'boom',
      'fuel',
      'grant',
    ][(h >> 8) % 5];
    final towns = settlements.toList();
    final days = MagRules.ticksPerDay;
    switch (kind) {
      case 'festival':
        if (towns.isEmpty) return;
        final t = towns[(h >> 12) % towns.length];
        final goods = t.accepts.where(cargoAvailable).toList()
          ..sort((a, b) => a.index - b.index);
        if (goods.isEmpty) return;
        final c = goods[(h >> 16) % goods.length];
        events.add(
          MagEvent('festival', tick + 6 * days, place: t.id, cargo: c),
        );
        _say('${t.name}: ярмарка — «${magCargoWord(c)}» +40% к оплате 6 дней');
      case 'strike':
        final plants = map.industries
            .where((i) => i.spec.converts.isNotEmpty && i.town == null)
            .toList();
        if (plants.isEmpty) return;
        final p = plants[(h >> 12) % plants.length];
        events.add(MagEvent('strike', tick + 3 * days, place: p.id));
        _say('${p.name}: забастовка — 3 дня без выпуска');
      case 'boom':
        final all = MagCargo.values
            .where((c) => !c.people && cargoAvailable(c))
            .toList();
        if (all.isEmpty) return;
        final c = all[(h >> 12) % all.length];
        events.add(MagEvent('boom', tick + 7 * days, cargo: c));
        _say('Бум спроса: «${magCargoWord(c)}» +30% к оплате 7 дней');
      case 'fuel':
        events.add(MagEvent('fuel', tick + 5 * days));
        _say('Топливо подорожало: расходы в пути +40% на 5 дней');
      default:
        final grant = 1000 + level * 500;
        _earn(grant, 'grants');
        _say('Городской грант на развитие транспорта: +$grant кр');
        _remember('Грант на развитие транспорта: +$grant кр');
    }
  }

  // ---- The campaign ----

  MagChapter? get chapter =>
      chapterIndex < magChapters.length ? magChapters[chapterIndex] : null;

  void _dayCampaign() {
    if (!livingWorld) return;
    final c = chapter;
    if (c == null || !c.test(this)) return;
    chapterIndex++;
    _earn(c.reward, 'campaign');
    _gainXp(c.reward ~/ 20);
    _say('Глава «${c.title}» пройдена: +${c.reward} кр');
    _remember('Кампания: глава «${c.title}» пройдена');
  }

  // ---- Saves ----

  Map<String, Object> _saveSeasons() => {
    'living': livingWorld,
    if (chapterIndex > 0) 'chapter': chapterIndex,
    if (events.isNotEmpty)
      'events': [
        for (final e in events)
          [e.kind, e.until, e.place ?? -1, e.cargo?.name ?? ''],
      ],
  };

  void loadSeasons(Map<String, dynamic> j) {
    // Saves from before 1.94 come alive; worlds saved since keep their
    // choice.
    livingWorld = j['living'] as bool? ?? true;
    chapterIndex = j['chapter'] as int? ?? 0;
    for (final raw in j['events'] as List? ?? const []) {
      final l = raw as List;
      final place = l[2] as int, cargo = l[3] as String;
      events.add(
        MagEvent(
          l[0] as String,
          l[1] as int,
          place: place < 0 ? null : place,
          cargo: cargo.isEmpty ? null : MagCargo.values.byName(cargo),
        ),
      );
    }
  }
}
