/// «Магистрали»: the rules of the transport game in one place, so balance
/// changes never touch the simulation.
library;

enum MagCargo { grain, wood, ore, food, goods }

enum MagTerrain { grass, forest, hill, river, lake }

/// Road surfaces; [none] is a cell without a road.
enum MagRoad { none, dirt, asphalt, highway, motorway }

enum MagIndustryKind {
  farm,
  sawmill,
  mine,
  foodPlant,
  factory,
  city,
  village,

  /// Built by the player (stage 2): stores any cargo.
  warehouse,
}

/// Upgrade lines of a truck.
enum MagUpgrade { engine, body, economy, reliability }

/// The four directions on the grid: up (−y), right (+x), down, left.
abstract final class MagDir {
  static const dx = [0, 1, 0, -1], dy = [-1, 0, 1, 0];
  static int opposite(int d) => (d + 2) % 4;
}

class MagRoadSpec {
  const MagRoadSpec(this.cost, this.speed, this.level, this.upkeep);

  /// Credits per cell on grass (terrain multiplies it).
  final int cost;

  /// Speed multiplier for vehicles on it.
  final double speed;

  /// Company level that unlocks it.
  final int level;

  /// Credits per 10 cells per day.
  final int upkeep;
}

class MagIndustrySpec {
  const MagIndustrySpec({
    required this.size,
    this.produces = const {},
    this.accepts = const {},
    this.converts = const {},
    this.stores = false,
  });

  /// A warehouse: takes any cargo into its stock and hands it out again.
  final bool stores;

  /// Footprint in cells (square).
  final int size;

  /// Raw production per day.
  final Map<MagCargo, int> produces;

  /// Cargo it takes in.
  final Set<MagCargo> accepts;

  /// Processing: each input unit becomes one unit of the output.
  final Map<MagCargo, MagCargo> converts;
}

class MagTruckModel {
  const MagTruckModel({
    required this.id,
    required this.name,
    required this.speed,
    required this.capacity,
    required this.price,
    required this.runningCost,
    required this.upkeep,
    required this.level,
    required this.color,
  });
  final String id, name;

  /// Cells per second at 1× on asphalt.
  final double speed;
  final int capacity, price;

  /// Credits per cell driven.
  final double runningCost;

  /// Credits per day.
  final int upkeep;
  final int level;
  final int color;
}

abstract final class MagRules {
  static const mapSize = 64;
  static const defaultSeed = 20261113;
  static const startMoney = 6000;

  /// Fixed step: 10 ticks per second at 1×, 40 ticks a day, 30 days a month.
  static const tickMs = 100;
  static const ticksPerSecond = 10;
  static const ticksPerDay = 40;
  static const daysPerMonth = 30;

  static const outputCap = 80;

  /// Store for delivered cargo at plants (orders never overfill it).
  static const inputCap = 120;

  /// An order whose truck finds no road this many days fails.
  static const orderNoRoadDays = 3;

  /// Warehouses: room before technologies, price of the first, ids kept
  /// apart from the map's places.
  static const warehouseBase = 200;
  static const warehousePrice = 3000;
  static const warehouseIdBase = 100000;

  /// Open automatic orders per warehouse rule, the smallest one sent on,
  /// and how often warehouses plan (ticks).
  static const autoOrdersPerRule = 3;
  static const minAutoBatch = 5;
  static const planEveryTicks = 20;
  static const processPerDay = 14;

  /// Loading and unloading: units per tick, and the shortest stop.
  static const handlePerTick = 4;
  static const minStopTicks = 6;

  /// A partly loaded truck leaves after this many days of waiting.
  static const partialWaitDays = 2;

  /// A truck that finds no road tries again after this many ticks.
  static const retryTicks = 20;

  static const maxUpgrade = 10;
  static const maxContracts = 3;

  static const roads = <MagRoad, MagRoadSpec>{
    MagRoad.dirt: MagRoadSpec(20, .75, 1, 1),
    MagRoad.asphalt: MagRoadSpec(55, 1, 2, 2),
    MagRoad.highway: MagRoadSpec(140, 1.3, 12, 4),
    MagRoad.motorway: MagRoadSpec(320, 1.6, 30, 7),
  };

  /// Building cost multiplier per terrain (null: not buildable).
  static double? terrainCost(MagTerrain t) => switch (t) {
    MagTerrain.grass => 1,
    MagTerrain.forest => 1.8, // clearing
    MagTerrain.hill => 2.4,
    MagTerrain.river => 6, // a bridge
    MagTerrain.lake => null,
  };

  static const industries = <MagIndustryKind, MagIndustrySpec>{
    MagIndustryKind.farm: MagIndustrySpec(
      size: 2,
      produces: {MagCargo.grain: 9},
    ),
    MagIndustryKind.sawmill: MagIndustrySpec(
      size: 2,
      produces: {MagCargo.wood: 8},
    ),
    MagIndustryKind.mine: MagIndustrySpec(size: 2, produces: {MagCargo.ore: 8}),
    MagIndustryKind.foodPlant: MagIndustrySpec(
      size: 2,
      accepts: {MagCargo.grain},
      converts: {MagCargo.grain: MagCargo.food},
    ),
    MagIndustryKind.factory: MagIndustrySpec(
      size: 3,
      accepts: {MagCargo.wood, MagCargo.ore},
      converts: {MagCargo.wood: MagCargo.goods, MagCargo.ore: MagCargo.goods},
    ),
    MagIndustryKind.city: MagIndustrySpec(
      size: 3,
      accepts: {MagCargo.food, MagCargo.goods},
    ),
    MagIndustryKind.village: MagIndustrySpec(size: 2, accepts: {MagCargo.food}),
    MagIndustryKind.warehouse: MagIndustrySpec(
      size: 2,
      accepts: {...MagCargo.values},
      stores: true,
    ),
  };

  /// Credits per unit per cell of distance between the two places.
  static const cargoRate = <MagCargo, double>{
    MagCargo.grain: 1.8,
    MagCargo.wood: 1.9,
    MagCargo.ore: 2.2,
    MagCargo.food: 2.9,
    MagCargo.goods: 3.8,
  };

  static const minPayDistance = 4;

  static const trucks = <MagTruckModel>[
    MagTruckModel(
      id: 'pickup',
      name: 'Пикап «Старт»',
      speed: 1.25,
      capacity: 10,
      price: 2200,
      runningCost: .5,
      upkeep: 4,
      level: 1,
      color: 0xFF2BB59A,
    ),
    MagTruckModel(
      id: 'lorry',
      name: 'Грузовик «Терра»',
      speed: 1.4,
      capacity: 22,
      price: 6800,
      runningCost: .9,
      upkeep: 8,
      level: 3,
      color: 0xFFE28A3B,
    ),
    MagTruckModel(
      id: 'tractor',
      name: 'Тягач «Магистраль»',
      speed: 1.6,
      capacity: 38,
      price: 16500,
      runningCost: 1.4,
      upkeep: 14,
      level: 6,
      color: 0xFF4A6FD8,
    ),
  ];

  static MagTruckModel? truck(String id) =>
      trucks.where((t) => t.id == id).firstOrNull;
}
