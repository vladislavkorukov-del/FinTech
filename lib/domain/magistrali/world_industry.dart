part of 'world.dart';

/// Own production (master plan stage 3): buy an independent business or
/// build a new one, modernise it (levels 1–5 add output and storage) and
/// sell it. An owned place's stock belongs to the company: selling it to
/// an outside buyer brings its market price, buying an independent
/// producer's goods into an owned place costs its price, and moving goods
/// between own places is a transfer — never a sale.
extension MagWorldIndustry on MagWorld {
  /// Can this place change hands (a producer or a plant, not a settlement
  /// or a warehouse)?
  bool forSale(MagIndustry i) =>
      i.town == null && !i.spec.stores && i.spec.price > 0;

  /// Is this place the company's (owned, or one of its warehouses)?
  bool ownedPlace(MagIndustry? i) => i != null && (i.owned || i.spec.stores);

  /// Output and storage multiplier of a level.
  double outputFactor(MagIndustry i) =>
      1 + MagRules.levelOutput * (i.level - 1);
  double storageFactor(MagIndustry i) =>
      1 + MagRules.levelStorage * (i.level - 1);

  /// How much finished stock a place holds.
  int outputCapOf(MagIndustry i) =>
      (MagRules.outputCap * storageFactor(i)).round();

  /// Price to buy it now (a modernised independent costs more).
  int buyPrice(MagIndustry i) =>
      (i.spec.price * (1 + .6 * (i.level - 1))).round();

  int buildPrice(MagIndustryKind k) =>
      (MagRules.industries[k]!.price * MagRules.buildFactor).round();

  /// Price of the next level (null at the top).
  int? upgradePrice(MagIndustry i) => i.level >= MagRules.maxIndustryLevel
      ? null
      : (i.spec.price * .6 * i.level).round();

  /// What selling it brings back: half of what was put in.
  int sellPrice(MagIndustry i) => (i.invested * .5).round();

  /// Daily upkeep of an owned place.
  int upkeepOfIndustry(MagIndustry i) =>
      (i.spec.price / MagRules.upkeepShare * i.level).round();

  String? buyIndustry(int id) {
    final i = map.industry(id);
    if (i == null || !forSale(i)) return 'Это нельзя купить';
    if (i.owned) return 'Уже ваше';
    final price = buyPrice(i);
    if (money < price) return 'Не хватает кредитов: нужно $price';
    _spend(price, 'industry_buy', source: 'industry', sourceId: id);
    i
      ..owned = true
      ..since = tick
      ..invested += price;
    _say('${i.name} теперь ваше');
    return null;
  }

  String? upgradeIndustry(int id) {
    final i = map.industry(id);
    if (i == null || !i.owned) return 'Модернизировать можно только своё';
    final cost = upgradePrice(i);
    if (cost == null) return 'Максимальный уровень';
    if (money < cost) return 'Не хватает кредитов';
    _spend(cost, 'industry_upgrade', source: 'industry', sourceId: id);
    i
      ..level += 1
      ..invested += cost;
    return null;
  }

  /// Sells an owned place back to the market: it keeps working on its
  /// own (with its level and stock), the company gets half its outlay.
  String? sellIndustry(int id) {
    final i = map.industry(id);
    if (i == null || !i.owned) return 'Это не ваше';
    if (orders.active.any((o) => o.supplier == id || o.receiver == id)) {
      return 'К предприятию привязаны заказы';
    }
    _assetSale(sellPrice(i), 'industry_sale', source: 'industry', sourceId: id);
    i
      ..owned = false
      ..invested = 0
      ..since = null;
    return null;
  }

  /// Why [k] cannot be built with its corner at (x, y).
  String? buildBlocker(MagIndustryKind k, int x, int y) {
    final spec = MagRules.industries[k]!;
    if (spec.price == 0 || spec.stores) return 'Это не строят';
    if (k == MagIndustryKind.logisticsCenter) {
      if (centerSlots == 0) return 'Нужна технология «Логистический центр»';
      if (centers.length >= centerSlots) return 'Больше центров не разрешено';
    }
    if (level < spec.buildLevel) {
      return 'Строить можно с ${spec.buildLevel} уровня компании';
    }
    for (var yy = y; yy < y + spec.size; yy++) {
      for (var xx = x; xx < x + spec.size; xx++) {
        if (!map.roadable(xx, yy) || hasRoad(xx, yy) || hasRail(xx, yy)) {
          return 'Нужно ${spec.size}×${spec.size} свободных клеток без дорог';
        }
      }
    }
    final near = spec.near;
    if (near != null) {
      var found = false;
      for (var yy = y - 2; yy < y + spec.size + 2 && !found; yy++) {
        for (var xx = x - 2; xx < x + spec.size + 2; xx++) {
          if (map.inside(xx, yy) && map.at(xx, yy) == near) {
            found = true;
            break;
          }
        }
      }
      if (!found) {
        return switch (near) {
          MagTerrain.forest => 'Нужен лес рядом (2 клетки)',
          MagTerrain.river => 'Нужна река рядом (2 клетки)',
          _ => 'Нужны холмы рядом (2 клетки)',
        };
      }
    }
    return null;
  }

  String? buildIndustry(MagIndustryKind k, int x, int y) {
    final why = buildBlocker(k, x, y);
    if (why != null) return why;
    final price = buildPrice(k);
    if (money < price) return 'Не хватает кредитов: нужно $price';
    final id = MagRules.builtIdBase + nextId++;
    _spend(price, 'industry_build', source: 'industry', sourceId: id);
    final same = map.industries.where((i) => i.built && i.kind == k).length;
    map.industries.add(
      MagIndustry(
          id: id,
          kind: k,
          x: x,
          y: y,
          name: '${_kindTitle(k)} «Ваша» №${same + 1}',
        )
        ..owned = true
        ..since = tick
        ..built = true
        ..invested = price,
    );
    roadVersion++;
    _say('Построено — подведите дорогу');
    return null;
  }

  static String _kindTitle(MagIndustryKind k) => switch (k) {
    MagIndustryKind.farm => 'Ферма',
    MagIndustryKind.sawmill => 'Лесозаготовка',
    MagIndustryKind.mine => 'Рудник',
    MagIndustryKind.foodPlant => 'Пищевой завод',
    MagIndustryKind.factory => 'Завод',
    MagIndustryKind.quarry => 'Каменоломня',
    MagIndustryKind.mill => 'Мельница',
    MagIndustryKind.bakery => 'Пекарня',
    MagIndustryKind.lumbermill => 'Лесопилка',
    MagIndustryKind.coalMine => 'Угольная шахта',
    MagIndustryKind.clayPit => 'Глиняный карьер',
    MagIndustryKind.brickworks => 'Кирпичный завод',
    MagIndustryKind.steelMill => 'Сталелитейный завод',
    MagIndustryKind.partsFactory => 'Завод деталей',
    MagIndustryKind.logisticsCenter => 'Логистический центр',
    _ => 'Предприятие',
  };

  /// Value of the businesses the company owns (for the company's worth).
  int get industriesValue {
    var v = 0;
    for (final i in map.industries) {
      if (i.owned) v += sellPrice(i);
    }
    return v;
  }
}
