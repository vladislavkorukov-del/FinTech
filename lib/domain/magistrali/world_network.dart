part of 'world.dart';

/// Stage S18: transfers (PASS-06), trams (PASS-08), the look of vehicles
/// (VEH-13), by-products (PROD-20), auctions (BIZ-13), historical
/// contracts (META-07) and regions to open (MAP-08).
class MagHistoric {
  const MagHistoric(
    this.id,
    this.level,
    this.title,
    this.cargo,
    this.amount,
    this.reward,
  );
  final String id, title;
  final int level, amount, reward;
  final MagCargo cargo;
}

/// An auction lot: a business sold to the best bidder (BIZ-13).
class MagAuction {
  MagAuction(this.industry, this.price, this.end);
  final int industry;
  int price;
  final int end;
}

extension MagWorldNetwork on MagWorld {
  // ---- PASS-06: transfers ----

  /// A settlement two or more lines meet at: a transfer hub.
  bool isHub(MagIndustry t) =>
      t.town != null &&
      routes.values.where((r) => r.stops.contains(t.id)).length >= 2;

  /// Passengers brought to a hub: a share stays to ride on (they count as
  /// delivered here, and wait for the next line). Returns how many stay.
  int transferAt(MagIndustry t, int n) {
    if (!isHub(t)) return 0;
    final stay = (n * MagRules.transferShare).floor();
    if (stay > 0) {
      t.stock[MagCargo.passengers] = (t.stock[MagCargo.passengers] ?? 0) + stay;
    }
    return stay;
  }

  // ---- PASS-08: trams ----

  /// Trams run only between settlements.
  String? tramRouteBlocker(int routeId) {
    final r = routes[routeId];
    if (r == null) return 'Нет маршрута';
    if (r.stops.any((s) => map.industry(s)?.town == null)) {
      return 'Трамвай ходит только между поселениями';
    }
    return null;
  }

  // ---- VEH-13: the look of a vehicle ----

  /// The vehicle's paint (null: the model's colour).
  String? paintVehicle(int id, int? color) {
    final v = vehicles[id];
    if (v == null) return 'Нет такой машины';
    if (color != null) {
      if (money < MagRules.paintPrice) return 'Не хватает кредитов';
      _spend(MagRules.paintPrice, 'upgrades', source: 'vehicle', sourceId: id);
    }
    v.paint = color;
    return null;
  }

  /// 0–3: how upgraded it looks (stripes over it).
  int visualTier(MagVehicle v) {
    final total = MagUpgrade.values.fold(0, (s, u) => s + v.level(u));
    return math.min(3, total ~/ 8);
  }

  // ---- PROD-20: by-products ----

  void _byProduct(MagIndustry i, int made) {
    final b = MagRules.byProducts[i.kind];
    if (b == null) return;
    final n = (made * b.$2).floor();
    if (n <= 0) return;
    i.stock[b.$1] = (i.stock[b.$1] ?? 0) + n;
    created[b.$1] = (created[b.$1] ?? 0) + n;
  }

  // ---- BIZ-13: auctions ----

  void _dayAuction() {
    final a = auction;
    if (a != null) {
      if (tick > a.end) {
        auction = null;
        _remember('Аукцион: «${map.industry(a.industry)?.name}» ушёл другому');
      } else {
        a.price = (a.price * (1 + MagRules.auctionRise)).round();
      }
      return;
    }
    if (level < 4 || day % MagRules.auctionEvery != 0) return;
    final lots = [
      for (final i in map.industries)
        if (!i.owned && forSale(i) && accessCells(i).isNotEmpty) i,
    ];
    if (lots.isEmpty) return;
    final i = lots[_roll(lots.length)];
    auction = MagAuction(
      i.id,
      (buyPrice(i) * MagRules.auctionStart).round(),
      tick + MagRules.auctionDays * MagRules.ticksPerDay,
    );
    _say('Аукцион: «${i.name}»');
  }

  String? buyAuction() {
    final a = auction;
    if (a == null) return 'Аукциона нет';
    final i = map.industry(a.industry)!;
    if (i.owned) return 'Уже ваше';
    if (money < a.price) return 'Не хватает кредитов: нужно ${a.price}';
    _spend(a.price, 'industry_buy', source: 'industry', sourceId: i.id);
    i
      ..owned = true
      ..since = tick
      ..invested += a.price;
    auction = null;
    _remember('Куплено на аукционе: ${i.name}');
    return null;
  }

  // ---- META-07: historical contracts ----

  static const historics = [
    MagHistoric(
      'fair',
      5,
      'Хлеб для губернской ярмарки',
      MagCargo.bread,
      60,
      12000,
    ),
    MagHistoric(
      'school',
      8,
      'Кирпич для первой школы',
      MagCargo.bricks,
      80,
      18000,
    ),
    MagHistoric(
      'railway',
      12,
      'Сталь для великой дороги',
      MagCargo.steel,
      100,
      30000,
    ),
    MagHistoric(
      'power',
      16,
      'Детали для электростанции',
      MagCargo.parts,
      80,
      40000,
    ),
    MagHistoric(
      'expo',
      20,
      'Электроника для всемирной выставки',
      MagCargo.electronics,
      40,
      60000,
    ),
  ];

  /// A historical contract opens once, when the company grows to it:
  /// any settlement may take the cargo; 60 days.
  void _offerHistorics() {
    for (final h in historics) {
      if (level < h.level || historicOffered.contains(h.id)) continue;
      if (!cargoAvailable(h.cargo)) continue;
      historicOffered.add(h.id);
      final centre = map.startPlant;
      deals.add(
        MagDeal(
            id: nextId++,
            kind: MagDealKind.region,
            cargo: h.cargo,
            to: centre.id,
            amount: h.amount,
            reward: h.reward,
            deadline: tick + 60 * MagRules.ticksPerDay,
          )
          ..radius = 9999
          ..story = h.title,
      );
      _say('Исторический контракт: ${h.title}');
      _remember('Исторический контракт: ${h.title}');
    }
  }

  // ---- MAP-08: regions ----

  /// Regions: the map in 3 × 3 parts.
  int regionOf(int x, int y) {
    final s = (size / 3).ceil();
    return math.min(2, x ~/ s) + 3 * math.min(2, y ~/ s);
  }

  bool regionOpen(int x, int y) =>
      !regionsLocked || openRegions.contains(regionOf(x, y));

  /// The price of the next region to open.
  int get regionPrice => MagRules.regionPrice * openRegions.length;

  String? openRegion(int region) {
    if (!regionsLocked || openRegions.contains(region)) {
      return 'Регион уже открыт';
    }
    if (region < 0 || region > 8) return 'Нет такого региона';
    final price = regionPrice;
    if (money < price) return 'Не хватает кредитов: нужно $price';
    _spend(price, 'regions');
    openRegions.add(region);
    roadVersion++;
    _remember('Открыт новый регион');
    return null;
  }

  // ---- Saves ----

  Map<String, Object> _saveNetwork() => {
    if (vehicles.values.any((v) => v.paint != null))
      'paints': {
        for (final v in vehicles.values)
          if (v.paint != null) '${v.id}': v.paint!,
      },
    if (auction != null)
      'auction': [auction!.industry, auction!.price, auction!.end],
    if (historicOffered.isNotEmpty)
      'historic': historicOffered.toList()..sort(),
    if (regionsLocked) 'regions': openRegions.toList()..sort(),
  };

  void loadNetwork(Map<String, dynamic> j) {
    for (final e in (j['paints'] as Map? ?? const {}).entries) {
      vehicles[int.parse('${e.key}')]?.paint = e.value as int;
    }
    final a = j['auction'] as List?;
    if (a != null) auction = MagAuction(a[0] as int, a[1] as int, a[2] as int);
    historicOffered.addAll([
      for (final h in j['historic'] as List? ?? const []) h as String,
    ]);
    final r = j['regions'] as List?;
    if (r != null) {
      regionsLocked = true;
      openRegions.addAll([for (final x in r) x as int]);
    }
  }
}
