part of 'world.dart';

/// Trucks: what they can do (with upgrades and technologies), buying,
/// upgrading, repairing, selling, parking and putting on a route.
extension MagWorldFleet on MagWorld {
  MagVehicle _newVehicle(MagTruckModel m) {
    final v = MagVehicle(id: nextId++, model: m.id, name: m.name);
    vehicles[v.id] = v;
    return v;
  }

  double speedOf(MagVehicle v) =>
      v.spec.speed *
      (1 + .08 * v.level(MagUpgrade.engine)) *
      factor(MagBonus.speed);

  int capacityOf(MagVehicle v) =>
      (v.spec.capacity *
              (1 + .1 * v.level(MagUpgrade.body)) *
              factor(MagBonus.capacity))
          .round();

  double runningCostOf(MagVehicle v) =>
      v.spec.runningCost *
      (1 - .06 * v.level(MagUpgrade.economy)) *
      factor(MagBonus.fuel);

  int upkeepOf(MagVehicle v) =>
      (v.spec.upkeep *
              (1 - .05 * v.level(MagUpgrade.economy)) *
              factor(MagBonus.upkeep))
          .round();

  /// Wear in percent per cell driven.
  double wearRateOf(MagVehicle v) =>
      .05 * (1 - .07 * v.level(MagUpgrade.reliability)) * factor(MagBonus.wear);

  /// Speed lost to wear (worn out: 35 % slower).
  double wearFactor(MagVehicle v) => 1 - .35 * v.wear / 100;

  /// Price of the next level of an upgrade line (null at the top).
  int? upgradeCost(MagVehicle v, MagUpgrade u) {
    final l = v.level(u);
    if (l >= MagRules.maxUpgrade) return null;
    return (v.spec.price * .22 * math.pow(1.34, l)).round();
  }

  int serviceCost(MagVehicle v) =>
      (v.spec.price * .0016 * v.wear * factor(MagBonus.service)).round();

  int valueOf(MagVehicle v) =>
      (v.spec.price * .55 * (1 - v.wear / 200) + v.upgradeSpent * .3).round();

  String? buyTruck(String modelId) {
    final m = MagRules.truck(modelId);
    if (m == null) return 'Нет такой модели';
    if (level < m.level) return 'Откроется на ${m.level} уровне';
    if (money < m.price) return 'Не хватает кредитов';
    _spend(m.price, 'vehicles');
    final v = _newVehicle(m);
    final same = vehicles.values.where((o) => o.model == m.id).length;
    v.name = '${m.name.split(' ').first} №$same';
    _say('Куплен ${m.name}');
    return null;
  }

  String? upgrade(int id, MagUpgrade u) {
    final v = vehicles[id];
    if (v == null) return 'Нет такой машины';
    final cost = upgradeCost(v, u);
    if (cost == null) return 'Максимальный уровень';
    if (v.level(u) >= maxUpgradeLevel) {
      return 'Следующий уровень — с ростом компании';
    }
    if (money < cost) return 'Не хватает кредитов';
    _spend(cost, 'upgrades');
    v.upgrades[u.index]++;
    v.upgradeSpent += cost;
    return null;
  }

  String? service(int id) {
    final v = vehicles[id];
    if (v == null) return 'Нет такой машины';
    final cost = serviceCost(v);
    if (cost == 0) return 'Машина в порядке';
    if (money < cost) return 'Не хватает кредитов';
    _spend(cost, 'service');
    v.wear = 0;
    return null;
  }

  /// Takes a truck off the map; cargo on board goes back where it was
  /// loaded, so nothing appears or vanishes.
  void _park(MagVehicle v) {
    // An order it carries is cancelled first (its cargo goes back).
    final o = v.orderId == null ? null : orders.byId(v.orderId!);
    if (o != null && o.status.active) {
      _closeOrder(
        o,
        o.status == MagOrderStatus.unloading
            ? MagOrderStatus.done
            : MagOrderStatus.cancelled,
      );
    }
    v.orderId = null;
    if (v.load > 0) {
      final from = map.industry(v.loadFrom ?? -1);
      if (from != null) {
        from.stock[v.cargo!] = (from.stock[v.cargo!] ?? 0) + v.load;
      } else {
        destroyed[v.cargo!] = (destroyed[v.cargo!] ?? 0) + v.load;
      }
    }
    v
      ..load = 0
      ..cargo = null
      ..loadFrom = null
      ..routeId = null
      ..state = MagVehicleState.garage
      ..cell = -1
      ..path = const []
      ..pathIndex = 0
      ..progress = 0
      ..wait = 0;
  }

  String? sellTruck(int id) {
    final v = vehicles[id];
    if (v == null) return 'Нет такой машины';
    final value = valueOf(v);
    _park(v);
    vehicles.remove(id);
    money += value;
    month.income['sales'] = (month.income['sales'] ?? 0) + value;
    return null;
  }

  /// Puts a truck on a route (null: back to the garage).
  String? assign(int vehicleId, int? routeId) {
    final v = vehicles[vehicleId];
    if (v == null) return 'Нет такой машины';
    if (routeId != null && !routes.containsKey(routeId)) return 'Нет маршрута';
    _park(v);
    if (routeId == null) return null;
    v
      ..routeId = routeId
      ..stop = 0
      ..state = MagVehicleState.noRoad
      ..wait = 0;
    _tryStart(v);
    return null;
  }
}
